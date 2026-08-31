"""Extract getEnergy.dat with MPI restore of each snapshot.

`getEnergy` compiled with `-D_MPI=1` distributes the octree restore and the
volume integrals. `ENERGY_WORKERS` independent Slurm steps can process
different snapshots concurrently when the allocation has enough complete MPI
groups. Existing non-empty part files are kept, so a cancelled sweep resumes.

Run inside a Slurm allocation from a case post-processing directory:

```bash
MPI_RANKS_PER_FRAME=48 python3 run_energy_mpi.py --cpus 1
```
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
import sys
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

EXE = os.environ.get("ENERGY_EXE", "./getEnergy")
TMP = Path(os.environ.get("ENERGY_PARTS", "energy_parts"))
OUT = Path(os.environ.get("ENERGY_OUT", "getEnergy.dat"))
RANKS_PER_FRAME = int(os.environ.get("MPI_RANKS_PER_FRAME", "12"))
MEMORY_PER_FRAME = os.environ.get("MPI_MEMORY_PER_FRAME", "125G")
NODES_PER_FRAME = int(os.environ.get("MPI_NODES_PER_FRAME", "1"))
TASKS_PER_NODE = int(os.environ.get("MPI_TASKS_PER_NODE", str(RANKS_PER_FRAME)))
SNAPSHOT_TIMES = {
    float(value)
    for value in re.split(r"[,;:]", os.environ.get("SNAPSHOT_TIMES", ""))
    if value.strip()
}


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


def extract(job: tuple[str, Path, str]) -> tuple[str, Path, str]:
    """Restore one snapshot through an exclusive MPI Slurm step."""

    snapshot, part, oh = job
    if is_complete_part(part):
        return "skip", part, ""

    token = uuid.uuid4().hex
    temporary = part.with_name(f".{part.name}.{token}.tmp")
    try:
        mpi = [
            "srun",
            "--exclusive",
            "--exact",
            f"--nodes={NODES_PER_FRAME}",
            f"--ntasks={RANKS_PER_FRAME}",
            f"--ntasks-per-node={TASKS_PER_NODE}",
            "--cpus-per-task=1",
            f"--mem={MEMORY_PER_FRAME}",
            EXE,
            snapshot,
            str(temporary),
            oh,
        ]
        completed = subprocess.run(mpi, capture_output=True, text=True)
        if completed.returncode != 0 or not is_complete_part(temporary):
            detail = (completed.stderr or completed.stdout)[-500:]
            return "FAIL", part, f"getEnergy exit {completed.returncode}: {detail}"
        os.replace(temporary, part)
        return "ok", part, ""
    finally:
        temporary.unlink(missing_ok=True)


def validate_allocation(workers: int) -> None:
    """Reject configurations that oversubscribe the Slurm allocation."""

    if min(RANKS_PER_FRAME, workers, NODES_PER_FRAME, TASKS_PER_NODE) < 1:
        raise SystemExit("MPI energy ranks, workers, nodes and tasks per node must be positive")
    if TASKS_PER_NODE * NODES_PER_FRAME != RANKS_PER_FRAME:
        raise SystemExit("MPI_TASKS_PER_NODE * MPI_NODES_PER_FRAME must equal MPI_RANKS_PER_FRAME")
    if not re.fullmatch(r"[1-9][0-9]*[KMGTP]?", MEMORY_PER_FRAME):
        raise SystemExit("MPI_MEMORY_PER_FRAME must be a Slurm memory value such as 125G")
    allocated = int(os.environ.get("SLURM_NTASKS", "0"))
    required = RANKS_PER_FRAME * workers
    if allocated and required > allocated:
        raise SystemExit(
            f"energy lanes need {required} ranks but SLURM_NTASKS={allocated}"
        )
    allocated_nodes = int(os.environ.get("SLURM_NNODES", "0"))
    required_nodes = NODES_PER_FRAME * workers
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
    validate_allocation(args.cpus)
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

    jobs = []
    for snapshot in snapshots:
        time = snapshot_time(snapshot)
        if time is None:
            continue
        part = TMP / f"e_{int(round(1e4 * time)):06d}.dat"
        jobs.append((snapshot, part, oh))

    print(
        f"Oh={oh} snapshots={len(jobs)} workers={args.cpus} "
        f"ranks_per_frame={RANKS_PER_FRAME}",
        flush=True,
    )
    counts = {"ok": 0, "skip": 0, "FAIL": 0}
    failures = []
    with ThreadPoolExecutor(max_workers=args.cpus) as pool:
        futures = [pool.submit(extract, job) for job in jobs]
        for completed, future in enumerate(as_completed(futures), start=1):
            status, part, detail = future.result()
            counts[status] += 1
            if status == "FAIL":
                failures.append((part, detail))
            print(
                f"progress={completed}/{len(jobs)} status={status} part={part.name}",
                flush=True,
            )

    rows = assemble([part for _, part, _ in jobs])
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
