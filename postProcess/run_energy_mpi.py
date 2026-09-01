"""Extract getEnergy.dat with MPI restore of each snapshot.

`getEnergy` compiled with `-D_MPI=1` distributes the octree restore and the
volume integrals. `ENERGY_WORKERS` independent Slurm steps can process
different snapshots concurrently when the allocation has enough complete MPI
groups. Existing non-empty part files are kept, so a cancelled sweep resumes.

Set `ENERGY_ADAPTIVE=1` to size each lane from the dump: snapshots smaller
than `ENERGY_SMALL_MAX_BYTES` use a one-node group, and larger dumps keep
the two-node layout. A node-credit lock packs mixed lanes into the same
allocation instead of reserving the large-dump shape for every snapshot.

Run inside a Slurm allocation from a case post-processing directory:

```bash
MPI_RANKS_PER_FRAME=48 python3 run_energy_mpi.py --cpus 1
ENERGY_ADAPTIVE=1 python3 run_energy_mpi.py --cpus 4
```
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

EXE = os.environ.get("ENERGY_EXE", "./getEnergy")
TMP = Path(os.environ.get("ENERGY_PARTS", "energy_parts"))
OUT = Path(os.environ.get("ENERGY_OUT", "getEnergy.dat"))
RANKS_PER_FRAME = int(os.environ.get("MPI_RANKS_PER_FRAME", "12"))
MEMORY_PER_FRAME = os.environ.get("MPI_MEMORY_PER_FRAME", "125G")
NODES_PER_FRAME = int(os.environ.get("MPI_NODES_PER_FRAME", "1"))
TASKS_PER_NODE = int(os.environ.get("MPI_TASKS_PER_NODE", str(RANKS_PER_FRAME)))
ADAPTIVE = os.environ.get("ENERGY_ADAPTIVE", "0") == "1"
SMALL_MAX_BYTES = int(os.environ.get("ENERGY_SMALL_MAX_BYTES", str(20 * 1024 ** 3)))
SMALL_NODES = int(os.environ.get("ENERGY_SMALL_NODES", "1"))
SMALL_RANKS = int(os.environ.get("ENERGY_SMALL_RANKS", "24"))
SMALL_TASKS_PER_NODE = int(os.environ.get("ENERGY_SMALL_TASKS_PER_NODE", "24"))
SMALL_MEMORY = os.environ.get("ENERGY_SMALL_MEMORY", "125G")
LARGE_NODES = int(os.environ.get("ENERGY_LARGE_NODES", "2"))
LARGE_RANKS = int(os.environ.get("ENERGY_LARGE_RANKS", "48"))
LARGE_TASKS_PER_NODE = int(os.environ.get("ENERGY_LARGE_TASKS_PER_NODE", "24"))
LARGE_MEMORY = os.environ.get("ENERGY_LARGE_MEMORY", "250G")
SNAPSHOT_TIMES = {
    float(value)
    for value in re.split(r"[,;:]", os.environ.get("SNAPSHOT_TIMES", ""))
    if value.strip()
}

_NODE_GUARD = threading.Condition()
_NODE_CREDITS = 0


@dataclass(frozen=True)
class Lane:
    """Slurm step shape for one snapshot restore."""

    label: str
    nodes: int
    ranks: int
    tasks_per_node: int
    memory: str


@dataclass(frozen=True)
class Job:
    """One snapshot extraction, including its MPI lane."""

    snapshot: str
    part: Path
    oh: str
    lane: Lane


def snapshot_time(path: str) -> float | None:
    """Return the physical time encoded at the end of a snapshot path."""

    match = re.search(r"snapshot-([0-9]+(?:\.[0-9]+)?)$", path)
    return float(match.group(1)) if match else None


def get_oh(explicit: str | None) -> str:
    """Read Oh from the CLI or case.params."""

    if explicit:
        return explicit
    if Path("case.params").exists():
        for line in Path("case.params").read_text(encoding="utf-8").splitlines():
            match = re.match(r"\s*Oh\s*=\s*([0-9.eE+-]+)", line)
            if match:
                return match.group(1)
    raise SystemExit("Oh not given and not found in case.params")


def is_complete_part(path: Path) -> bool:
    """Accept a non-empty one-line energy record."""

    try:
        text = path.read_text(encoding="utf-8").strip()
    except OSError:
        return False
    return len(text.split()) >= 12


def snapshot_bytes(path: str) -> int:
    """Return the on-disk size of a snapshot, following one symlink."""

    try:
        return Path(path).stat().st_size
    except OSError:
        return 0


def parse_memory(value: str) -> None:
    """Reject a Slurm memory string that the inner srun step cannot use."""

    if not re.fullmatch(r"[1-9][0-9]*[KMGTP]?", value):
        raise SystemExit(f"memory value must look like 125G, not {value!r}")


def validate_lane(lane: Lane) -> None:
    """Reject a lane that cannot be packed into exclusive srun steps."""

    if min(lane.nodes, lane.ranks, lane.tasks_per_node) < 1:
        raise SystemExit("MPI energy ranks, nodes and tasks per node must be positive")
    if lane.tasks_per_node * lane.nodes != lane.ranks:
        raise SystemExit(
            f"{lane.label} lane: tasks per node times nodes must equal ranks"
        )
    parse_memory(lane.memory)


def fixed_lane() -> Lane:
    """Return the single-shape lane used when adaptive packing is off."""

    return Lane(
        label="fixed",
        nodes=NODES_PER_FRAME,
        ranks=RANKS_PER_FRAME,
        tasks_per_node=TASKS_PER_NODE,
        memory=MEMORY_PER_FRAME,
    )


def adaptive_lane(path: str) -> Lane:
    """Choose a one-node or two-node lane from the dump size."""

    if snapshot_bytes(path) < SMALL_MAX_BYTES:
        return Lane(
            label="small",
            nodes=SMALL_NODES,
            ranks=SMALL_RANKS,
            tasks_per_node=SMALL_TASKS_PER_NODE,
            memory=SMALL_MEMORY,
        )
    return Lane(
        label="large",
        nodes=LARGE_NODES,
        ranks=LARGE_RANKS,
        tasks_per_node=LARGE_TASKS_PER_NODE,
        memory=LARGE_MEMORY,
    )


def lane_for(path: str) -> Lane:
    """Return the MPI lane for one snapshot."""

    return adaptive_lane(path) if ADAPTIVE else fixed_lane()


def acquire_nodes(count: int) -> None:
    """Block until `count` allocation nodes are free, then take them."""

    global _NODE_CREDITS
    with _NODE_GUARD:
        while _NODE_CREDITS < count:
            _NODE_GUARD.wait()
        _NODE_CREDITS -= count


def release_nodes(count: int) -> None:
    """Return `count` allocation nodes to the packer."""

    global _NODE_CREDITS
    with _NODE_GUARD:
        _NODE_CREDITS += count
        _NODE_GUARD.notify_all()


def extract(job: Job) -> tuple[str, Path, str, str]:
    """Restore one snapshot through an exclusive MPI Slurm step."""

    if is_complete_part(job.part):
        return "skip", job.part, job.lane.label, ""

    acquire_nodes(job.lane.nodes)
    token = uuid.uuid4().hex
    temporary = job.part.with_name(f".{job.part.name}.{token}.tmp")
    try:
        mpi = [
            "srun",
            "--exclusive",
            "--exact",
            f"--nodes={job.lane.nodes}",
            f"--ntasks={job.lane.ranks}",
            f"--ntasks-per-node={job.lane.tasks_per_node}",
            "--cpus-per-task=1",
            f"--mem={job.lane.memory}",
            EXE,
            job.snapshot,
            str(temporary),
            job.oh,
        ]
        completed = subprocess.run(mpi, capture_output=True, text=True)
        if completed.returncode != 0 or not is_complete_part(temporary):
            detail = (completed.stderr or completed.stdout)[-500:]
            return (
                "FAIL",
                job.part,
                job.lane.label,
                f"getEnergy exit {completed.returncode}: {detail}",
            )
        os.replace(temporary, job.part)
        return "ok", job.part, job.lane.label, ""
    finally:
        temporary.unlink(missing_ok=True)
        release_nodes(job.lane.nodes)


def validate_allocation(workers: int, lanes: list[Lane]) -> None:
    """Reject configurations that oversubscribe the Slurm allocation."""

    if workers < 1:
        raise SystemExit("energy worker count must be positive")
    for lane in lanes:
        validate_lane(lane)
    allocated = int(os.environ.get("SLURM_NTASKS", "0"))
    allocated_nodes = int(os.environ.get("SLURM_NNODES", "0"))
    max_ranks = max(lane.ranks for lane in lanes)
    max_nodes = max(lane.nodes for lane in lanes)
    if allocated and max_ranks > allocated:
        raise SystemExit(
            f"largest energy lane needs {max_ranks} ranks but SLURM_NTASKS={allocated}"
        )
    if allocated_nodes and max_nodes > allocated_nodes:
        raise SystemExit(
            f"largest energy lane needs {max_nodes} nodes but SLURM_NNODES={allocated_nodes}"
        )
    if not ADAPTIVE:
        required = RANKS_PER_FRAME * workers
        required_nodes = NODES_PER_FRAME * workers
        if allocated and required > allocated:
            raise SystemExit(
                f"energy lanes need {required} ranks but SLURM_NTASKS={allocated}"
            )
        if allocated_nodes and required_nodes > allocated_nodes:
            raise SystemExit(
                f"energy lanes need {required_nodes} nodes but SLURM_NNODES={allocated_nodes}"
            )


def assemble(parts: list[Path]) -> int:
    """Write time-ordered getEnergy.dat from complete part files."""

    rows = []
    for part in parts:
        if is_complete_part(part):
            rows.append(part.read_text(encoding="utf-8").strip() + "\n")
    OUT.write_text("".join(rows), encoding="utf-8")
    return len(rows)


def main(argv: list[str] | None = None) -> int:
    """Extract energy diagnostics for every available snapshot."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cpus", "--CPUs", dest="cpus", type=int, default=4,
        help="number of concurrent MPI snapshot lanes (default: 4)",
    )
    parser.add_argument(
        "--max-frames", type=int, default=None,
        help="process only the first N snapshots",
    )
    parser.add_argument(
        "--skip-video", action="store_true",
        help="accepted for post-processing compatibility; this driver writes no video",
    )
    parser.add_argument("oh", nargs="?", help="Ohnesorge number (default: case.params)")
    args = parser.parse_args(argv)
    if args.cpus <= 0:
        parser.error("--cpus must be greater than zero")
    if args.max_frames is not None and args.max_frames <= 0:
        parser.error("--max-frames must be greater than zero")

    oh = get_oh(args.oh)
    TMP.mkdir(parents=True, exist_ok=True)
    snapshots = sorted(
        glob.glob("intermediate/snapshot-*"),
        key=lambda path: snapshot_time(path) or 0.0,
    )
    if SNAPSHOT_TIMES:
        snapshots = [
            path
            for path in snapshots
            if snapshot_time(path) is not None
            and any(abs(snapshot_time(path) - time) < 5e-8 for time in SNAPSHOT_TIMES)
        ]
        if len(snapshots) != len(SNAPSHOT_TIMES):
            found = ",".join(str(snapshot_time(path)) for path in snapshots)
            raise SystemExit(
                f"requested {len(SNAPSHOT_TIMES)} snapshot times but found "
                f"{len(snapshots)}: {found}"
            )
    if args.max_frames is not None:
        snapshots = snapshots[: args.max_frames]

    jobs: list[Job] = []
    for snapshot in snapshots:
        time = snapshot_time(snapshot)
        if time is None:
            continue
        part = TMP / f"e_{int(round(1e4 * time)):06d}.dat"
        jobs.append(Job(snapshot, part, oh, lane_for(snapshot)))

    if not jobs:
        raise SystemExit("no snapshots found under intermediate/")

    lanes = [job.lane for job in jobs]
    validate_allocation(args.cpus, lanes)
    global _NODE_CREDITS
    _NODE_CREDITS = int(os.environ.get("SLURM_NNODES", "0")) or max(
        lane.nodes for lane in lanes
    )
    # Submit slower large dumps first so one-node lanes can fill leftover
    # nodes as two-node groups finish. Keep the original time order for
    # getEnergy.dat assembly.
    submit_jobs = sorted(
        jobs,
        key=lambda job: (0 if job.lane.label == "large" else 1, snapshot_time(job.snapshot) or 0.0),
    )

    small = sum(1 for job in jobs if job.lane.label == "small")
    large = sum(1 for job in jobs if job.lane.label == "large")
    print(
        f"Oh={oh} snapshots={len(jobs)} workers={args.cpus} "
        f"adaptive={int(ADAPTIVE)} small={small} large={large} "
        f"node_credits={_NODE_CREDITS}",
        flush=True,
    )
    counts = {"ok": 0, "skip": 0, "FAIL": 0}
    failures = []
    with ThreadPoolExecutor(max_workers=args.cpus) as pool:
        futures = [pool.submit(extract, job) for job in submit_jobs]
        for completed, future in enumerate(as_completed(futures), start=1):
            status, part, label, detail = future.result()
            counts[status] += 1
            if status == "FAIL":
                failures.append((part, detail))
            print(
                f"progress={completed}/{len(jobs)} status={status} "
                f"lane={label} part={part.name}",
                flush=True,
            )

    rows = assemble([job.part for job in jobs])
    print(
        f"computed={counts['ok']} skipped={counts['skip']} "
        f"failed={counts['FAIL']} total={len(jobs)} wrote={OUT} rows={rows}",
        flush=True,
    )
    for part, detail in failures[:10]:
        print(f"FAIL {part}: {detail}", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
