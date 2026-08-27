"""Render Basilisk snapshots with MPI within and across frames.

`getView3D_v3` distributes each octree restore and drawing pass over
`MPI_RANKS_PER_FRAME` ranks. `FRAME_WORKERS` independent Slurm steps process
different snapshots concurrently. Existing complete PNGs are retained, so a
cancelled sweep resumes without rewriting finished frames.

Run inside a Slurm allocation from a case post-processing directory:

```bash
MPI_RANKS_PER_FRAME=12 python3 render_frames_mpi.py --cpus 2
```

The default output remains `Video_view3_v2` so an MPI sweep can resume the
existing serial-render directory and feed the unchanged video encoder.
"""

from __future__ import annotations

import glob
import argparse
import os
from pathlib import Path
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
import uuid


FOLDER = Path(os.environ.get("FRAME_FOLDER", "Video_view3_v2"))
EXE = os.environ.get("RENDER_EXE", "./getView3D_v3")
RANKS_PER_FRAME = int(os.environ.get("MPI_RANKS_PER_FRAME", "12"))
MEMORY_PER_FRAME = os.environ.get("MPI_MEMORY_PER_FRAME", "125G")
NODES_PER_FRAME = int(os.environ.get("MPI_NODES_PER_FRAME", "1"))
TASKS_PER_NODE = int(os.environ.get("MPI_TASKS_PER_NODE", str(RANKS_PER_FRAME)))
FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
SNAPSHOT_TIMES = {
    float(value)
    for value in re.split(r"[,;:]", os.environ.get("SNAPSHOT_TIMES", ""))
    if value.strip()
}


def snapshot_time(path: str) -> float | None:
    """Return the physical time encoded at the end of a snapshot path."""

    match = re.search(r"snapshot-([0-9.]+)$", path)
    return float(match.group(1)) if match else None


def is_complete_png(path: Path) -> bool:
    """Check the PNG signature and terminal IEND marker."""

    try:
        with path.open("rb") as stream:
            if stream.read(8) != b"\x89PNG\r\n\x1a\n":
                return False
            stream.seek(-12, os.SEEK_END)
            return stream.read(8)[4:] == b"IEND"
    except (OSError, ValueError):
        return False


def render(job: tuple[str, Path]) -> tuple[str, Path, str]:
    """Render one snapshot through an exclusive MPI Slurm step."""

    snapshot, output = job
    if is_complete_png(output):
        return "skip", output, ""

    token = uuid.uuid4().hex
    ppm = output.parent / f".{output.name}.{token}.ppm"
    png = output.parent / f".{output.name}.{token}.png"
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
            str(ppm),
        ]
        rendered = subprocess.run(mpi, capture_output=True, text=True)
        if rendered.returncode != 0 or not ppm.exists() or ppm.stat().st_size == 0:
            detail = (rendered.stderr or rendered.stdout)[-500:]
            return "FAIL", output, f"renderer exit {rendered.returncode}: {detail}"

        converted = subprocess.run(
            [FFMPEG, "-y", "-loglevel", "error", "-i", str(ppm), str(png)],
            capture_output=True,
            text=True,
        )
        if converted.returncode != 0 or not is_complete_png(png):
            detail = (converted.stderr or converted.stdout)[-500:]
            return "FAIL", output, f"PNG conversion exit {converted.returncode}: {detail}"

        os.replace(png, output)
        return "ok", output, ""
    finally:
        ppm.unlink(missing_ok=True)
        png.unlink(missing_ok=True)


def validate_allocation(frame_workers: int) -> None:
    """Reject configurations that oversubscribe the Slurm allocation."""

    if min(RANKS_PER_FRAME, frame_workers, NODES_PER_FRAME, TASKS_PER_NODE) < 1:
        raise SystemExit("MPI render ranks, workers, nodes and tasks per node must be positive")
    if TASKS_PER_NODE * NODES_PER_FRAME != RANKS_PER_FRAME:
        raise SystemExit("MPI_TASKS_PER_NODE * MPI_NODES_PER_FRAME must equal MPI_RANKS_PER_FRAME")
    if not re.fullmatch(r"[1-9][0-9]*[KMGTP]?", MEMORY_PER_FRAME):
        raise SystemExit("MPI_MEMORY_PER_FRAME must be a Slurm memory value such as 125G")
    allocated = int(os.environ.get("SLURM_NTASKS", "0"))
    required = RANKS_PER_FRAME * frame_workers
    if allocated and required > allocated:
        raise SystemExit(
            f"render lanes need {required} ranks but SLURM_NTASKS={allocated}"
        )
    allocated_nodes = int(os.environ.get("SLURM_NNODES", "0"))
    required_nodes = NODES_PER_FRAME * frame_workers
    if allocated_nodes and required_nodes > allocated_nodes:
        raise SystemExit(
            f"render lanes need {required_nodes} nodes but SLURM_NNODES={allocated_nodes}"
        )


def main(argv: list[str] | None = None) -> int:
    """Render every available snapshot and report resumable progress."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cpus", "--CPUs", dest="cpus", type=int, default=4,
        help="number of concurrent MPI frame lanes (default: 4)",
    )
    parser.add_argument(
        "--max-frames", type=int, default=None,
        help="process only the first N snapshots",
    )
    parser.add_argument(
        "--skip-video", action="store_true",
        help="accepted for post-processing compatibility; this driver never encodes video",
    )
    args = parser.parse_args(argv)
    if args.cpus <= 0:
        parser.error("--cpus must be greater than zero")
    if args.max_frames is not None and args.max_frames <= 0:
        parser.error("--max-frames must be greater than zero")

    frame_workers = args.cpus
    validate_allocation(frame_workers)
    FOLDER.mkdir(parents=True, exist_ok=True)
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
        snapshots = snapshots[:args.max_frames]
    jobs = []
    for snapshot in snapshots:
        time = snapshot_time(snapshot)
        if time is not None:
            output = FOLDER / f"{int(round(1e4 * time)):06d}.png"
            jobs.append((snapshot, output))

    print(
        f"snapshots={len(jobs)} workers={frame_workers} "
        f"ranks_per_frame={RANKS_PER_FRAME}",
        flush=True,
    )
    counts = {"ok": 0, "skip": 0, "FAIL": 0}
    failures = []
    with ThreadPoolExecutor(max_workers=frame_workers) as pool:
        futures = [pool.submit(render, job) for job in jobs]
        for completed, future in enumerate(as_completed(futures), start=1):
            status, output, detail = future.result()
            counts[status] += 1
            if status == "FAIL":
                failures.append((output, detail))
            print(
                f"progress={completed}/{len(jobs)} status={status} frame={output.name}",
                flush=True,
            )

    print(
        f"rendered={counts['ok']} skipped={counts['skip']} "
        f"failed={counts['FAIL']} total={len(jobs)}",
        flush=True,
    )
    for output, detail in failures[:10]:
        print(f"FAIL {output}: {detail}", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
