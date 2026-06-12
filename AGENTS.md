# Jumping Drops - Agent Guidance

## Repository layout

- `src-local/` holds shared Basilisk headers and parameter parsing helpers.
- `simulationCases/` holds the active Basilisk entry points plus preserved legacy sources.
- `postProcess/` holds the rendering and energy-diagnostic pipelines for `intermediate/snapshot-*` outputs; its `getEnergy.c` fluid properties must track `simulationCases/jumpingDrops_main.c`.
- Root scripts are the primary user workflows: `runSimulation.sh`, `runParameterSweep.sh`, and `runSweepSnellius.sbatch`.
- Root parameter files are `default.params` and `sweep.params`.

## Setup

- Copy `.project_config.example` to `.project_config` if a local project config does not exist yet.
- Source `.project_config` before running the scripts so `qcc` resolves from the configured Basilisk tree.
- Treat `basilisk/` as a local dependency; it is intentionally ignored by git.

## Runtime parameter model

- Use `key=value` parameter files.
- Required case keys: `CaseNo`, `Oh`, `Bo`, `MAXlevel`, `tmax`.
- Required sweep keys: `BASE_CONFIG`, `CASE_START`, `CASE_END`, and one or more `SWEEP_*` variables.
- Shell workflows must reuse `src-local/parse_params.sh`.
- Basilisk entry points must read runtime values through `src-local/parse_params.h` and `src-local/params.h`.
- The executable contract is `./jumpingDrops_init case.params` and `./jumpingDrops_main case.params`.

## Running

- Single case: `./runSimulation.sh default.params`
- Init only: `./runSimulation.sh --init-only default.params`
- Main only with MPI: `./runSimulation.sh --main-only --mpi --cores 8 default.params`
- Sweep: `./runParameterSweep.sh sweep.params`
- Sweep dry run: `./runParameterSweep.sh --dry-run sweep.params`
- HPC: `runSweepSnellius.sbatch` expects `dumpInit` already transferred per case and delegates to `runParameterSweep.sh --skip-init --mpi`.

## Notes

- `simulationCases/jumpingDrops_init.c` is serial-only because it uses STL geometry support.
- `simulationCases/jumpingDrops_main.c` is the MPI-capable executable and restores from `dump`.
- `runSimulation.sh` creates `simulationCases/<CaseNo>/`, copies the chosen parameter file to `case.params`, and executes from that directory.
- `runParameterSweep.sh` must keep generated case counts exactly consistent with `CASE_START` and `CASE_END`.
- `runSweepSnellius.sbatch` should stay a thin environment wrapper; shared sweep and case logic belongs in the root runner scripts.
- Preserve legacy sources and generated case outputs unless the user explicitly asks to remove them.
