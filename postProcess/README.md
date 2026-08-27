# Post-processing

Diagnostics and visualisation for the snapshots written by
`simulationCases/jumpingDrops_main.c` under `simulationCases/<CaseNo>/intermediate/snapshot-*`.

Two independent pipelines:

- **Rendering** (`getView3D_v3.c` + `render_frames_mpi.py`) - MPI restore,
  rendering and composition within each frame, with multiple frames rendered
  concurrently. The serial `v2` pathway remains available for comparison.
- **Energy** (`getEnergy.c` + `run_energy.py` + `energy_budget.py`) - per-snapshot energy diagnostics and the assembled budget plot.

Both Basilisk tools read snapshots directly; the Python drivers only fan the
work across snapshots and assemble the outputs.

## Contents

```
postProcess/
├── getView3D_v2.c       - Basilisk: serial reference renderer
├── getView3D_v3.c       - Basilisk: MPI renderer producing rank-zero PPM
├── render_frames.py     - legacy serial-frame driver
├── render_frames_mpi.py - MPI renderer with parallel frame lanes
├── render_frames_mpi.sbatch - two-node Snellius MPI render sweep
├── getEnergy.c           - Basilisk: energy diagnostics for one snapshot
├── run_energy.py         - driver: run getEnergy over every snapshot, assemble getEnergy.dat
└── energy_budget.py - assemble + plot the energy budget from getEnergy.dat
```

## Requirements

- Basilisk with `qcc` on `PATH` (`source .project_config`).
- MPI tools (`mpicc` and `srun`) for distributed restore/rendering.
- For rendering: the Basilisk GL libraries (`$BASILISK/gl/libglutils.a`, `libfb_tiny.a`); rendering is headless (offscreen framebuffer).
- For the video: `ffmpeg`. On Snellius: `module load 2024 FFmpeg/7.0.2-GCCcore-13.3.0`.
- For the budget plot: Python 3 with `numpy` and `matplotlib`.

## Compile

```bash
source .project_config   # puts qcc on PATH and sets $BASILISK

qcc -O2 -Wall -disable-dimensions getEnergy.c -o getEnergy -lm
qcc -O2 -Wall -disable-dimensions getView3D_v2.c -o getView3D_v2 \
    -L$BASILISK/gl -lglutils -lfb_tiny -lm
```

## Run

The drivers expect to run from a directory that contains `intermediate/snapshot-*`
and the compiled binaries. Either run inside `simulationCases/<CaseNo>/`, or make
a working directory and symlink the snapshots:

```bash
ln -s /path/to/simulationCases/<CaseNo>/intermediate intermediate
cp /path/to/simulationCases/<CaseNo>/case.params .
```

### Energy

```bash
NPROC=32 python3 run_energy.py        # Oh read from case.params (or pass it: run_energy.py 0.05)
python3 energy_budget.py getEnergy.dat energyBudget
```

`run_energy.py` runs `getEnergy` once per snapshot in parallel (each writing its
own one-line file) and concatenates them in time order into `getEnergy.dat`:

| col | name | meaning |
|----:|------|---------|
| 1 | `t` | time |
| 2 | `ke1` | liquid kinetic energy |
| 3-5 | `xcm ucm ycm` | liquid CoM x, u, y |
| 6-8 | `vcm zcm wcm` | liquid CoM v, z, w |
| 9 | `se` | surface energy, `interface_area(f) - 8*pi` |
| 10 | `eps1` | liquid viscous dissipation rate |
| 11 | `ke2` | gas kinetic energy |
| 12 | `eps2` | gas viscous dissipation rate |

`energy_budget.py` integrates `eps1`/`eps2` in time and writes `energyBudget.png`
and `energyBudget.csv`.

### Video

```bash
NPROC=32 python3 render_frames.py     # -> Video_view3_v2/<index>.png
ffmpeg -y -framerate 50 -pattern_type glob -i "Video_view3_v2/*.png" \
       -c:v libx264 -pix_fmt yuv420p -movflags +faststart video.mp4
```

Frame indices are `int(1e4 * t)` zero-padded, so the glob is already in time order.

### Parallel MPI 3D rendering

`getView3D_v3.c` is the MPI renderer for large three-dimensional snapshots.
It restores the octree collectively, draws local cells on every rank, and
lets Basilisk compose the colour/depth buffers on rank zero. The renderer
writes PPM, Basilisk View's MPI-safe image format; the Python driver converts
each completed PPM to PNG and renames it atomically.

MPI output defaults to `Video_view3_v3`, keeping it separate from the
`Video_view3_v2` serial reference. Point `FRAME_FOLDER` at the legacy folder
only for an intentional comparison or resumable migration.

Compile the renderer with an MPI C compiler:

```bash
source .project_config
CC99='mpicc -std=c99 -D_GNU_SOURCE=1' \
  qcc -O2 -Wall -D_MPI=1 -disable-dimensions getView3D_v3.c \
  -o getView3D_v3 -L"$BASILISK/gl" -lglutils -lfb_tiny -lm
```

For a Slurm allocation, the driver uses one MPI step per snapshot. `--cpus`
controls the number of concurrent frame lanes, not the number of MPI ranks in
one frame. The latter is set with `MPI_RANKS_PER_FRAME`; the node layout is
set with `MPI_NODES_PER_FRAME` and `MPI_TASKS_PER_NODE`:

```bash
MPI_RANKS_PER_FRAME=48 \
MPI_NODES_PER_FRAME=2 \
MPI_TASKS_PER_NODE=24 \
MPI_MEMORY_PER_FRAME=250G \
python3 render_frames_mpi.py --cpus 1 --skip-video
```

The batch wrapper compiles the renderer once and assembles the video after
every frame has succeeded:

```bash
sbatch --export=ALL,ROOT=<repository-root>,CASE_ID=<CaseNo>,POST_DIR=<post-process-directory> \
  postProcess/render_frames_mpi.sbatch
```

Submit from the repository root. Slurm writes `mpi-render-<job-name>-<job-id>`
logs in the submission directory; `ROOT` is required so the batch job always
copies renderer sources from the submitted checkout rather than a stale or
machine-specific campaign path.

Submit separate case jobs when cases should render concurrently. Use
`--cpus 2` only when the allocation contains two complete frame groups. For
large late-time dumps, one two-node frame lane per allocation is the safe
configuration. In Slurm, `MPI_MEMORY_PER_FRAME` is memory **per node** for
the inner `srun` step and must not exceed the batch allocation's `--mem`.
The driver rejects rank/node oversubscription before launching work.

The workflow is resumable: valid existing PNGs are skipped, incomplete output
is replaced through a temporary file, and the MP4 is created only after every
canonical frame in `frames.ffconcat` passes the PNG completeness check. Stale
or unrelated numeric PNGs are never included in the video. For a small driver
check, use:

```bash
python3 render_frames_mpi.py --help
python3 render_frames_mpi.py --cpus 1 --max-frames 4 --skip-video
python3 render_frames_mpi.py --cpus 4 --max-frames 4 --skip-video
```

Compare MPI output against `getView3D_v2` for at least one common snapshot
before a production sweep. The serial renderer remains the visual regression
reference; the MPI renderer should preserve the camera, mirrored geometry,
field colouring, mesh overlay, and time label.

## HPC note

Energy extraction remains serial per snapshot, so `run_energy.py` parallelises
across snapshots with a process pool. The MPI renderer parallelises the
restore and drawing of each frame, and can also run independent frame lanes
when the allocation has enough complete MPI groups. On Snellius, run both
drivers from a batch job rather than on a login node. The fluid properties
baked into `getEnergy.c` must match
`simulationCases/jumpingDrops_main.c` (`rho1=1`, `mu1=Oh`, `rho2=1e-3`,
`mu2=1e-5`, `sigma=1`).
