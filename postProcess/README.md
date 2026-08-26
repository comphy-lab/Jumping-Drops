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
├── render_frames_mpi.sbatch - one-node Snellius MPI render sweep
├── getEnergy.c      - Basilisk: energy diagnostics for one snapshot
├── run_energy.py    - driver: run getEnergy over every snapshot, assemble getEnergy.dat
└── energy_budget.py - assemble + plot the energy budget from getEnergy.dat
```

## Requirements

- Basilisk with `qcc` on `PATH` (`source .project_config`).
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

## HPC note

Rendering and energy extraction are serial per snapshot, so the drivers
parallelise across snapshots with a process pool. On Snellius, run them from a
single-node batch job (set `NPROC` to the available cores) rather than on a
login node. The fluid properties baked into `getEnergy.c` must match
`simulationCases/jumpingDrops_main.c` (`rho1=1`, `mu1=Oh`, `rho2=1e-3`,
`mu2=1e-5`, `sigma=1`).
