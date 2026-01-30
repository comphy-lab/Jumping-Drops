/**
# Jumping Drops - Main Simulation Phase

Runs the full drop dynamics simulation from the initial condition created by
the initialization phase. This version is MPI-compatible for parallel execution.

## Usage

```bash
./jumpingDrops_main tmax Oh Bo MAXlevel
```

Example (serial):

```bash
./jumpingDrops_main 10.0 0.001 0.001 10
```

Example (parallel with MPI):

```bash
mpirun -np 8 ./jumpingDrops_main 10.0 0.001 0.001 10
```

## Inputs

- `tmax`: Maximum simulation time (dimensionless)
- `Oh`: Ohnesorge number (dimensionless viscosity)
- `Bo`: Bond number (dimensionless gravity)
- `MAXlevel`: Maximum AMR refinement level
- `dump` or `dumpInit`: Binary dump file from initialization phase (must exist)

## Outputs

- `dump`: Current simulation state (overwritten at each snapshot)
- `intermediate/snapshot-*.dump`: Periodic snapshots for post-processing
- `log`: Time series of kinetic energy and center-of-mass velocity

## Dependencies

This file does **not** include `distance.h`, making it MPI-compatible.
Use `mpirun` or `srun` for parallel execution on HPC systems.

## MPI Configuration

The `MPI_MODE` macro is defined before including the common header to enable
MPI-aware logging (only rank 0 writes to files).

## Author

Vatsal Sanjay (vatsal.sanjay@comphy-lab.org)  
CoMPhy Lab, Durham University  
Last updated: 2026-01-30
*/

#define MPI_MODE

/**
## Common Definitions

Includes shared constants, tolerances, and helper functions.
*/

#include "jumpingDrops_common.h"

/**
## Global Variable Definitions

Runtime parameters set from command-line arguments.
*/

double tmax, Oh, Bo;
int MAXlevel;


/**
## Main Function

Parses arguments, sets fluid properties, and starts the main simulation run.
*/

int main(int argc, char *argv[]) {
  // Parse command-line arguments
  // argv[1]: Maximum simulation time (tmax)
  // argv[2]: Ohnesorge number (Oh)
  // argv[3]: Bond number (Bo)
  // argv[4]: Maximum refinement level (MAXlevel)
  if (argc < 5) {
    fprintf(ferr, "ERROR: Insufficient arguments\n");
    fprintf(ferr, "Usage: %s tmax Oh Bo MAXlevel\n", argv[0]);
    fprintf(ferr, "Example: %s 10.0 0.001 0.001 10\n", argv[0]);
    return 1;
  }

  tmax = atof(argv[1]);
  Oh = atof(argv[2]);
  Bo = atof(argv[3]);
  MAXlevel = atoi(argv[4]);

  // Initialize grid
  init_grid (1 << MINlevel);
  L0 = Ldomain;

  fprintf(ferr, "==============================================\n");
  fprintf(ferr, "Jumping drops - Main Simulation Phase\n");
  fprintf(ferr, "==============================================\n");
  fprintf(ferr, "tmax = %g\n", tmax);
  fprintf(ferr, "Oh = %g\n", Oh);
  fprintf(ferr, "Bo = %g\n", Bo);
  fprintf(ferr, "MAXlevel = %d\n", MAXlevel);
#ifdef _MPI
  fprintf(ferr, "MPI enabled: %d processes\n", npe());
#endif
  fprintf(ferr, "==============================================\n\n");

  // Set fluid properties
  rho1 = 1.0;                         // liquid density (normalized)
  mu1 = Oh;                           // liquid viscosity
  rho2 = Rho21;                       // gas density
  mu2 = Mu21*Oh;                      // gas viscosity (consistent with init)
  f.sigma = 1.0;                      // surface tension (normalized)
  G.y = -Bo;                          // gravity (CRITICAL FIX: was missing!)

  // Create intermediate directory for snapshots
  char comm[80];
  sprintf (comm, "mkdir -p intermediate");
  system(comm);

  // Start simulation
  run();
}

/**
## Initialization Event

Restores simulation state from `dump` or `dumpInit` file created by the
initialization phase. Fails with an error message if no dump file is found.
*/
event init(t = 0){
  if(!restore (file = "dump")){
    fprintf(ferr, "ERROR: Cannot restore from dump file\n");
    fprintf(ferr, "Make sure dumpInit exists from initialization phase\n");
    fprintf(ferr, "Run jumpingDrops_init.c first to create initial condition\n");
    return 1;
  }
  fprintf(ferr, "Successfully restored from dump file\n");
}
