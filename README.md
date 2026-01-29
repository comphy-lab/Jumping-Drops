# Jumping-Drops

Jumping drops Basilisk simulation with a two-phase workflow:
initialization (STL geometry to `dumpInit`) and a main MPI-compatible run.

## Requirements
- Basilisk (`qcc` on `PATH`)
- MPI (optional, for parallel main phase)
- macOS or Linux

## Setup
- Run `./reset_install_requirements.sh` to install Basilisk and generate `.project_config`.
- Or copy `.project_config.example` to `.project_config` and set `BASILISK` manually.

## Quick start
```bash
# Full workflow (init + main)
./runSimulation.sh default.params

# Init only (STL -> dumpInit)
./runSimulation.sh --init-only default.params

# Main only (MPI)
./runSimulation.sh --main-only --mpi --cores 8 default.params

# Parameter sweep
./runParameterSweep.sh sweep.params
```

## Repository structure
- `src-local/`: shared headers and helpers (`jumpingDrops_common.h`, `parse_params.sh`).
- `simulationCases/`: Basilisk entry points and per-case output folders.
- `runSimulation.sh`, `runParameterSweep.sh`, `runSweepSnellius.sbatch`: workflows.
- `default.params`, `sweep.params`: example parameter inputs.

## Parameters
- Parameter files are `key=value` lines.
- Required keys: `CaseNo`, `Oh`, `Bo`, `MAXlevel`, `tmax`.
- Sweep files define `BASE_CONFIG`, `CASE_START`, `CASE_END`, and `SWEEP_*` values.

## HPC workflow (Snellius)
1. Local: create `dumpInit` for each case.
2. Transfer `dumpInit` to the HPC case folders.
3. Run: `sbatch runSweepSnellius.sbatch`.

## More docs
- `QUICK_REFERENCE.md`
- `REFACTORING_SUMMARY.md`
