/**
# Title: Jumping drops - Main Simulation Phase
- Author: Vatsal Sanjay (vatsal.sanjay@comphy-lab.org)
- CoMPhy Lab, Durham University

Purpose: Runs full simulation from initial dump file
Usage: ./jumpingDrops_main tmax Oh Bo MAXlevel
Input: Requires dumpInit file from jumpingDrops_init.c
Output: Simulation results and snapshots

This version is MPI-compatible and does NOT include distance.h.
Use this for HPC execution with mpirun/srun.

============================================================
MPI Configuration
============================================================
Define MPI_MODE before including common header
This enables MPI-aware logging (pid() checks)
*/

#define MPI_MODE

/**
============================================================
Common Definitions
============================================================
*/

#include "jumpingDrops_common.h"

/**
============================================================
Global Variable Definitions
============================================================
*/

double tmax, Oh, Bo;
int MAXlevel;


/**
============================================================
Main Function
============================================================
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
============================================================
Initialization Event
============================================================
Restores simulation state from dump file created by init phase
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
