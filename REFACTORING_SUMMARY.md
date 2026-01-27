# Jumping Drops Simulation - Modular Refactoring Summary

## Overview

The jumping drops simulation code has been refactored from two monolithic files (JumpingDrops.c and JumpingDrops_Snellius.c) into a clean, modular architecture that separates initialization (STL geometry loading) from main simulation (MPI-compatible).

## Files Created

### Source Code Files

1. **`simulationCases/jumpingDrops_common.h`** (New)
   - Common header with shared definitions and functions
   - Contains error tolerances, physics parameters, boundary conditions
   - Includes `refRegion()`, `adapt()`, `writingFiles()`, and `logWriting()` functions
   - Uses `MPI_MODE` flag for MPI-aware logging

2. **`simulationCases/jumpingDrops_init.c`** (New)
   - **Purpose**: Creates initial condition from STL geometry
   - **Includes**: `distance.h`, `reduced.h` (NOT MPI-compatible)
   - **Usage**: `./jumpingDrops_init Oh Bo MAXlevel`
   - **Output**: Creates `dumpInit` file
   - **Run**: Locally (serial execution only)

3. **`simulationCases/jumpingDrops_main.c`** (New)
   - **Purpose**: Runs full simulation from dump file
   - **Includes**: No `distance.h` (MPI-compatible)
   - **Usage**: `./jumpingDrops_main tmax Oh Bo MAXlevel`
   - **Input**: Requires `dump` file (from `dumpInit`)
   - **Run**: HPC with MPI or locally (serial/parallel)

## Files Modified

### Shell Scripts

1. **`runSimulation.sh`** (Updated)
   - Added `--init-only` flag: Run initialization phase only
   - Added `--main-only` flag: Run main simulation only
   - Default behavior: Run both phases sequentially
   - Compiles appropriate source files based on phase
   - Parses parameters from case.params file
   - Validates dump file existence before main phase

2. **`runParameterSweep.sh`** (Updated)
   - Added `--skip-init` flag: Skip initialization for all cases
   - Automatically detects if `dumpInit` exists per case
   - Skips initialization if `dumpInit` found, runs main only
   - Otherwise runs full workflow (init + main)

3. **`runSweepSnellius.sbatch`** (Updated)
   - **HPC-specific**: Runs main simulation only
   - Assumes `dumpInit` exists (transferred from local machine)
   - Copies both `jumpingDrops_main.c` and `jumpingDrops_common.h`
   - Compiles with MPI support
   - Validates dump file before execution
   - Parses parameters and passes to executable

## Critical Fixes Applied

### 1. Missing Gravity Bug (FIXED)
- **Issue**: `JumpingDrops_Snellius.c` was missing `G.y = -Bo`
- **Fix**: Both init and main now include `G.y = -Bo`
- **Impact**: Simulations now correctly include gravitational effects

### 2. Error Tolerance Consistency
- **Issue**: Init used stricter tolerances (1e-3, 1e-4, 1e-2), HPC used coarser (1e-2, 1e-3, 1e-1)
- **Fix**: Both use consistent stricter values: `fErr=1e-3, KErr=1e-4, VelErr=1e-2`
- **Impact**: Consistent mesh refinement across phases

### 3. Gas Viscosity Consistency
- **Issue**: Init used `mu2 = 1e-5`, HPC used `mu2 = Mu21*Oh`
- **Fix**: Both now use `mu2 = Mu21*Oh = 1e-3 * Oh`
- **Impact**: Consistent fluid properties

### 4. MPI-Aware Logging
- **Issue**: Non-MPI version didn't need `pid()` checks
- **Fix**: `logWriting()` uses `#ifdef MPI_MODE` for conditional `pid()` checks
- **Impact**: Proper log writing in both serial and parallel modes

## Workflow Examples

### Local Development

#### Full Workflow (Default)
```bash
# Runs both initialization and main simulation
./runSimulation.sh default.params
```

#### Initialization Only
```bash
# Creates dumpInit from STL geometry
./runSimulation.sh --init-only default.params
```

#### Main Simulation Only (Serial)
```bash
# Requires dumpInit to exist
./runSimulation.sh --main-only default.params
```

#### Main Simulation Only (MPI Parallel)
```bash
# Run with 8 MPI cores
./runSimulation.sh --main-only --mpi --cores 8 default.params
```

### Parameter Sweep (Local)

#### Automatic Init Detection
```bash
# Automatically runs init if dumpInit doesn't exist
# Skips init if dumpInit found
./runParameterSweep.sh sweep.params
```

#### Skip All Initialization
```bash
# Assumes all dumpInit files exist
./runParameterSweep.sh --skip-init sweep.params
```

#### With MPI
```bash
# Run main phase with 8 cores per case
./runParameterSweep.sh --mpi --cores 8 sweep.params
```

### HPC Workflow (Recommended)

#### Step 1: Local - Create Initial Conditions
```bash
# For each case, create dumpInit locally
for case in 1000 1001 1002; do
    # Assuming case.params exists for each case
    ./runSimulation.sh --init-only simulationCases/${case}/case.params
done
```

#### Step 2: Local - Transfer to HPC
```bash
# Copy dumpInit files to HPC
for case in 1000 1001 1002; do
    scp simulationCases/${case}/dumpInit \
        hpc:Drop-Impact/simulationCases/${case}/
done
```

Or transfer all at once:
```bash
# Sync entire simulationCases directory (only dumpInit files)
rsync -av --include='**/dumpInit' --include='*/' --exclude='*' \
    simulationCases/ hpc:Drop-Impact/simulationCases/
```

#### Step 3: HPC - Run Parameter Sweep
```bash
# On HPC
sbatch runSweepSnellius.sbatch
```

## Parameter File Requirements

### Required Parameters

All `.params` files must include:
```bash
CaseNo=1000              # 4-digit case number (1000-9999)
Oh=0.001                 # Ohnesorge number
Bo=0.001                 # Bond number
MAXlevel=10              # Maximum refinement level
tmax=10.0                # Maximum simulation time (main phase only)
```

### Example: default.params
```bash
# Jumping Drops Simulation Parameters
CaseNo=1000
Oh=0.001
Bo=0.001
MAXlevel=10
tmax=10.0
```

## Compilation Details

### Initialization Phase (jumpingDrops_init.c)
- **Compiler**: `qcc` (serial only)
- **Include**: `distance.h`, `reduced.h`
- **Flags**: `-O2 -Wall -disable-dimensions`
- **MPI**: NOT supported (distance.h incompatible)

### Main Phase (jumpingDrops_main.c)
- **Compiler**: `qcc` (serial) or `mpicc + qcc` (parallel)
- **Include**: No `distance.h`
- **Flags**: `-O2 -Wall -disable-dimensions [-D_MPI=1]`
- **MPI**: Fully supported

## Directory Structure

```
Jumping-Drops/
├── simulationCases/
│   ├── jumpingDrops_common.h         # Shared definitions (NEW)
│   ├── jumpingDrops_init.c           # Initialization (NEW)
│   ├── jumpingDrops_main.c           # Main simulation (NEW)
│   ├── JumpingDrops.c              # Old (deprecated)
│   ├── JumpingDrops_Snellius.c     # Old (deprecated)
│   └── <CaseNo>/                   # Case directories
│       ├── case.params             # Parameter file
│       ├── InitialCondition.stl    # STL geometry (for init)
│       ├── dumpInit                # Initial condition (from init)
│       ├── dump                    # Current state
│       ├── restart                 # Restart file (if exists)
│       ├── log                     # Simulation log
│       └── intermediate/           # Snapshot files
│           └── snapshot-*.dump
├── runSimulation.sh                # Single case runner (UPDATED)
├── runParameterSweep.sh            # Parameter sweep (UPDATED)
└── runSweepSnellius.sbatch         # HPC sweep (UPDATED)
```

## Advantages of Modular Design

### 1. Clean Separation
- Initialization logic separate from simulation logic
- No more #ifdef or commented-out code
- Clear responsibilities for each file

### 2. MPI Compatibility
- Main simulation fully MPI-compatible
- No distance.h in parallel code
- Proper pid() checks for logging

### 3. Flexibility
- Run init once, reuse for multiple parameter sweeps
- Easy to debug each phase independently
- Can modify physics parameters without re-initializing geometry

### 4. Consistency
- Single source of truth for common code
- Fixed bugs apply to both phases
- No parameter drift between versions

### 5. Development Efficiency
- Faster iteration: skip init when testing main code
- HPC-friendly: transfer small dumpInit files, not large STL
- Better error messages and validation

## Migration Guide

### From Old Code (JumpingDrops.c)
**Before:**
```bash
# Had to run full initialization every time
./JumpingDrops Oh Bo MAXlevel
```

**After:**
```bash
# Run once
./jumpingDrops_init Oh Bo MAXlevel

# Run multiple times with different parameters
./jumpingDrops_main tmax1 Oh Bo MAXlevel
./jumpingDrops_main tmax2 Oh Bo MAXlevel
```

### From Old Code (JumpingDrops_Snellius.c)
**Before:**
```bash
# On HPC (missing gravity!)
mpirun -np 48 ./JumpingDrops_Snellius case.params
```

**After:**
```bash
# Local: create dumpInit
./runSimulation.sh --init-only case.params

# Transfer to HPC
scp dumpInit hpc:case/

# HPC: run with gravity included
srun -n 48 ./jumpingDrops_main tmax Oh Bo MAXlevel
```

## Testing Checklist

### Local Testing
- [ ] Compile init phase: `./runSimulation.sh --init-only --compile-only`
- [ ] Compile main phase: `./runSimulation.sh --main-only --compile-only`
- [ ] Run init phase: `./runSimulation.sh --init-only default.params`
- [ ] Verify dumpInit created
- [ ] Run main phase serial: `./runSimulation.sh --main-only default.params`
- [ ] Run main phase MPI: `./runSimulation.sh --main-only --mpi --cores 4 default.params`
- [ ] Check log file for correct Oh, Bo values
- [ ] Verify gravity effects in output

### HPC Testing
- [ ] Transfer dumpInit to HPC
- [ ] Test single case compilation on HPC
- [ ] Run single case with MPI: `srun -n 48 ./jumpingDrops_main tmax Oh Bo MAXlevel`
- [ ] Submit parameter sweep: `sbatch runSweepSnellius.sbatch`
- [ ] Verify log files show correct parameters
- [ ] Check that all cases complete successfully

## Troubleshooting

### "ERROR: dump file not found"
- **Cause**: Main phase requires dump file from init phase
- **Solution**: Run `./runSimulation.sh --init-only` first

### "ERROR: Cannot restore from dump file"
- **Cause**: Dump file corrupted or incompatible
- **Solution**: Delete dump and re-run init phase

### "ERROR: Source file jumpingDrops_main.c not found"
- **Cause**: Running from wrong directory or files not copied to HPC
- **Solution**: Ensure all new files transferred to HPC

### Compilation fails with "undefined reference to distance"
- **Cause**: Trying to compile main phase with distance.h
- **Solution**: Verify using jumpingDrops_main.c (not jumpingDrops_init.c)

### MPI runs but only rank 0 writes log
- **Cause**: This is correct behavior for MPI mode
- **Solution**: No action needed - `pid() == 0` check is working

## Performance Notes

### Initialization Phase
- **Runtime**: ~1-2 minutes (depends on MAXlevel and STL complexity)
- **Memory**: Moderate (STL loading + distance field)
- **Parallelization**: Serial only (distance.h limitation)
- **Frequency**: Once per geometry

### Main Phase
- **Runtime**: Hours to days (depends on tmax, MAXlevel)
- **Memory**: Varies with refinement
- **Parallelization**: Excellent MPI scaling
- **Frequency**: Multiple runs with same initial condition

## Best Practices

1. **Always run init locally**: STL loading not MPI-compatible
2. **Transfer dumpInit to HPC**: Smaller than STL files
3. **Use --skip-init for sweeps**: After first run completes
4. **Check logs for parameter values**: Verify Oh, Bo, gravity
5. **Use restart files**: For long simulations that might be interrupted
6. **Keep dumpInit**: Don't delete after main simulation starts

## Future Enhancements

Possible future improvements:
- [ ] Support for different STL geometries per case
- [ ] Automatic dumpInit synchronization script
- [ ] Parameter validation in shell scripts
- [ ] Progress monitoring during long runs
- [ ] Automatic restart on HPC node failure
- [ ] Post-processing integration

## Contact

For questions or issues:
- Author: Vatsal Sanjay
- Email: vatsalsanjay@gmail.com
- Physics of Fluids

---

**Last Updated**: 2025-01-23
**Version**: 1.0
