# Jumping Drops - Agent Guidance

## Repository layout
- `src-local/`: shared headers and shell helpers (`jumpingDrops_common.h`, `parse_params.sh`).
- `simulationCases/`: Basilisk C entry points and per-case output folders.
- `runSimulation.sh`, `runParameterSweep.sh`, `runSweepSnellius.sbatch`: primary workflows.
- `default.params`, `sweep.params`: example parameter inputs.

## Setup
- Run `./reset_install_requirements.sh` to install Basilisk and generate `.project_config`.
- Or copy `.project_config.example` to `.project_config` and set `BASILISK` manually.
- Ensure `qcc` is on `PATH` after sourcing `.project_config`.

## Running
- Single case: `./runSimulation.sh default.params`
- Init only: `./runSimulation.sh --init-only default.params`
- Main only (MPI): `./runSimulation.sh --main-only --mpi --cores 8 default.params`
- Sweep: `./runParameterSweep.sh sweep.params`
- HPC: `runSweepSnellius.sbatch` expects `dumpInit` already transferred per case.

## Parameters
- Param files are `key=value` lines.
- Required keys: `CaseNo`, `Oh`, `Bo`, `MAXlevel`, `tmax`.
- Sweep files define `BASE_CONFIG`, `CASE_START`, `CASE_END`, and `SWEEP_*` values.

## Notes
- STL geometry is only used in the init phase (`jumpingDrops_init.c`, no MPI).
- Main simulation (`jumpingDrops_main.c`) is MPI-compatible and restores from `dump`.
