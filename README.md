# Jumping Drops

Jumping Drops is a Basilisk two-phase drop-impact workflow split into two entry
points:

- `simulationCases/jumpingDrops_init.c` creates `dumpInit` from STL geometry in serial.
- `simulationCases/jumpingDrops_main.c` restores `dump`/`dumpInit` and runs the MPI-ready main simulation.

The standardized runtime contract is `case.params`: shell scripts generate and
validate parameter files, and the Basilisk executables read the same file
directly at runtime.

## Requirements

- Basilisk with `qcc` available on `PATH`
- MPI tools (`mpicc`, `mpirun`, and `srun`) for parallel main runs and
  distributed 3D rendering
- A local `.project_config` file

Setup the local Basilisk path by copying and editing the example if needed:

```bash
cp .project_config.example .project_config
source .project_config
```

The vendored `basilisk/` directory is treated as a local dependency and is
ignored by git.

## Quick Start

```bash
# Full workflow for one case
./runSimulation.sh default.params

# Initialization only
./runSimulation.sh --init-only default.params

# Main phase only with MPI
./runSimulation.sh --main-only --mpi --cores 8 default.params

# Deterministic parameter sweep
./runParameterSweep.sh sweep.params

# Inspect generated sweep cases without running them
./runParameterSweep.sh --dry-run sweep.params
```

## Runtime Parameters

Parameter files use `key=value` lines with optional `#` comments.

Required single-case keys:

- `CaseNo`
- `Oh`
- `Bo`
- `MAXlevel`
- `tmax`

The shared parser layers are:

- `src-local/parse_params.sh` for shell runners and sweep generation
- `src-local/parse_params.h` for low-level C parsing
- `src-local/params.h` for typed C accessors with defaults and warnings

`runSimulation.sh` copies the chosen input file into
`simulationCases/<CaseNo>/case.params`, then runs the compiled executable as:

```bash
./jumpingDrops_init case.params
./jumpingDrops_main case.params
```

Sweep files define:

- `BASE_CONFIG`
- `CASE_START`
- `CASE_END`
- one or more `SWEEP_*` variables

`runParameterSweep.sh` generates one `case.params` file per combination,
enforces exact agreement between the generated combination count and the
`CASE_START`/`CASE_END` range, and then dispatches each case through
`runSimulation.sh`.

## HPC Workflow

`runSweepSnellius.sbatch` is the main-only HPC runner. The expected workflow is:

1. Generate `dumpInit` locally with `./runSimulation.sh --init-only ...`
2. Transfer `dumpInit` into each `simulationCases/<CaseNo>/` directory on HPC
3. Submit `runSweepSnellius.sbatch`

On Snellius, the batch script delegates to the shared root sweep runner in
main-only MPI mode:

```bash
bash runParameterSweep.sh --skip-init --mpi --cores "${SLURM_NTASKS}" sweep.params
```

It sets `MPI_LAUNCHER=srun` and `MPI_LAUNCHER_NFLAG=-n` so the shared
`runSimulation.sh` runner launches the main executable with `srun` instead of
duplicating a separate HPC-only execution path.

For individually scheduled 3D production cases, stage
`sweep_cases/case_<CaseNo>.params` and `simulationCases/<CaseNo>/dumpInit`,
then submit the same runner with a case identifier:

```bash
sbatch --job-name=jd1020 --export=ALL,CASE_NO=1020 runCaseSnellius.sbatch
```

The matched ultra-low-Oh take-off-energy campaigns use
`ultralow-oh.params` at `MAXlevel=9` and `ultralow-oh-ml10.params` at
`MAXlevel=10`.

## Post-processing

`postProcess/` holds the rendering and energy-diagnostic pipelines for the
`intermediate/snapshot-*` outputs. Compile the Basilisk tools, then drive them
across snapshots from a case directory:

```bash
source .project_config
cd postProcess
qcc -O2 -Wall -disable-dimensions getEnergy.c -o getEnergy -lm
CC99='mpicc -std=c99 -D_GNU_SOURCE=1' \
  qcc -O2 -Wall -D_MPI=1 -disable-dimensions getView3D_v3.c \
  -o getView3D_v3 -L"$BASILISK/gl" -lglutils -lfb_tiny -lm
```

`run_energy.py` + `energy_budget.py` produce the energy budget;
`render_frames_mpi.py` + `ffmpeg` produce the parallel MPI video. The serial
`getView3D_v2.c` and `render_frames.py` remain available as a regression
reference. See `postProcess/README.md` for the MPI rank and memory workflow.

## Repository Structure

```
├── .github/ - documentation site assets, build scripts, and workflows
├── .project_config.example - example Basilisk environment configuration
├── AGENTS.md - authoritative project instructions for coding agents
├── README.md - project overview and workflow documentation
├── default.params - example single-case runtime parameters
├── runParameterSweep.sh - deterministic sweep generator and dispatcher
├── runSimulation.sh - single-case compile/run entry point
├── runSweepSnellius.sbatch - Snellius wrapper around the shared MPI main-phase sweep runner
├── simulationCases/ - Basilisk entry points and preserved legacy sources
│   ├── JumpingDrops_Snellius_legacy.c - preserved legacy HPC variant
│   ├── JumpingDrops_legacy.c - preserved monolithic legacy source
│   ├── jumpingDrops_init.c - STL-to-dumpInit initialization phase
│   └── jumpingDrops_main.c - MPI-compatible main simulation phase
├── postProcess/ - rendering and energy diagnostics for saved snapshots
│   ├── getView3D_v2.c - serial reference renderer
│   ├── getView3D_v3.c - MPI renderer for one snapshot
│   ├── render_frames.py - legacy serial-frame driver
│   ├── render_frames_mpi.py - MPI renderer with resumable frame lanes
│   ├── render_frames_mpi.sbatch - Snellius MPI batch wrapper
│   ├── getEnergy.c - energy diagnostics for one snapshot
│   ├── run_energy.py - run getEnergy over all snapshots, assemble getEnergy.dat
│   ├── energy_budget.py - assemble and plot the energy budget
│   └── README.md - post-processing usage
├── src-local/ - shared headers and parameter parsing helpers
│   ├── jumpingDrops_common.h - shared Basilisk constants, AMR logic, and events
│   ├── params.h - typed runtime accessors for C entry points
│   ├── parse_params.h - low-level C parser for key=value files
│   └── parse_params.sh - shared shell parser/update helpers
└── sweep.params - example sweep definition
```

At runtime, new case directories are created under `simulationCases/<CaseNo>/`.
These directories typically contain `case.params`, `dumpInit`, `dump`, `log`,
and `intermediate/snapshot-*` outputs.

## Notes

- STL geometry is only used in the initialization phase; do not enable MPI there.
- The main phase restores from `dump`, so `dumpInit` is copied to `dump` after a fresh init run.
- `CLAUDE.md` is intentionally a one-line pointer to `AGENTS.md` and is ignored by git.
