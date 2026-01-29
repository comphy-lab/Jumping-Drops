# Jumping-Drops

Jumping drops Basilisk simulation with a two-phase workflow:
initialization (STL geometry to `dumpInit`) and a main MPI-compatible run.

## Requirements
- Basilisk (`qcc` on `PATH`)
- MPI (optional, for parallel main phase)
- macOS or Linux

## Basilisk (Required)

First-time install (or reinstall):
```bash
curl -sL https://raw.githubusercontent.com/comphy-lab/basilisk-C/main/reset_install_basilisk-ref-locked.sh | bash -s -- --ref=v2026-01-29 --hard
```

Subsequent runs (reuses existing `basilisk/` if same ref):
```bash
curl -sL https://raw.githubusercontent.com/comphy-lab/basilisk-C/main/reset_install_basilisk-ref-locked.sh | bash -s -- --ref=v2026-01-29
```

Load the environment before running the scripts:
```bash
source .project_config
```

> Note: Replace `v2026-01-29` with the latest release tag from https://github.com/comphy-lab/basilisk-C/releases.

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
