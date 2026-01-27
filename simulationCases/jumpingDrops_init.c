/**
# Title: Jumping Drops - Initialization Phase
- Author: Vatsal Sanjay (vatsal.sanjay@comphy-lab.org)
- CoMPhy Lab, Durham University

Purpose: Creates initial condition from STL geometry
Usage: ./jumpingDrops_init Oh Bo MAXlevel
Output: Creates dumpInit file for continuation with jumpingDrops_main.c

This version includes distance.h and STL loading, which are
incompatible with MPI. Run this locally to generate initial dump,
then use jumpingDrops_main.c with MPI for the full simulation.

============================================================
Phase-Specific Includes
============================================================
*/

#include "distance.h"                 // STL geometry handling (NOT MPI-compatible)
#include "reduced.h"                  // Reduced gravity model

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
  // argv[1]: Ohnesorge number (Oh)
  // argv[2]: Bond number (Bo)
  // argv[3]: Maximum refinement level (MAXlevel)
  if (argc < 4) {
    fprintf(ferr, "ERROR: Insufficient arguments\n");
    fprintf(ferr, "Usage: %s Oh Bo MAXlevel\n", argv[0]);
    fprintf(ferr, "Example: %s 0.001 0.001 10\n", argv[0]);
    return 1;
  }

  Oh = atof(argv[1]);
  Bo = atof(argv[2]);
  MAXlevel = atoi(argv[3]);

  // Initialization phase: short run just to create dump
  tmax = tsnap;

  // Initialize grid
  init_grid (1 << MINlevel);
  L0 = Ldomain;

  fprintf(ferr, "==============================================\n");
  fprintf(ferr, "Jumping Drops - Initialization Phase\n");
  fprintf(ferr, "==============================================\n");
  fprintf(ferr, "tmax = %g (initialization run)\n", tmax);
  fprintf(ferr, "Oh = %g\n", Oh);
  fprintf(ferr, "Bo = %g\n", Bo);
  fprintf(ferr, "MAXlevel = %d\n", MAXlevel);
  fprintf(ferr, "==============================================\n\n");

  // Set fluid properties
  rho1 = 1.0;                         // liquid density (normalized)
  mu1 = Oh;                           // liquid viscosity
  rho2 = Rho21;                       // gas density
  mu2 = Mu21*Oh;                      // gas viscosity (consistent with main)
  f.sigma = 1.0;                      // surface tension (normalized)
  G.y = -Bo;                          // gravity (CRITICAL: must match main phase)

  // Create intermediate directory for snapshots
  char comm[80];
  sprintf (comm, "mkdir -p intermediate");
  system(comm);

  // Start simulation
  run();

  return 0;
}

/** 
============================================================
Initialization Event
============================================================
Loads STL geometry and creates initial volume fraction field
*/

event init(t = 0){
  if(!restore (file = "dumpInit")){
    char filename[60];
    sprintf(filename,"InitialCondition.stl");

    fprintf(ferr, "Loading STL geometry: %s\n", filename);

    FILE * fp = fopen (filename, "r");
    if (fp == NULL){
      fprintf(ferr, "ERROR: Cannot open STL file: %s\n", filename);
      return 1;
    }

    // Read STL geometry
    coord * p = input_stl (fp);
    fclose (fp);

    // Get bounding box
    coord min, max;
    bounding_box (p, &min, &max);

    fprintf(ferr, "STL bounding box:\n");
    fprintf(ferr, "  x: [%g, %g]\n", min.x, max.x);
    fprintf(ferr, "  y: [%g, %g]\n", min.y, max.y);
    fprintf(ferr, "  z: [%g, %g]\n", min.z, max.z);

    // Set origin to position drop correctly
    // Drop bottom at y = -1 with small offset for grid cell
    double origin_x = 0.;
    double origin_y = -1. - L0/pow(2, MAXlevel);
    double origin_z = (min.z + max.z)/2.;

    fprintf(ferr, "Setting origin: (%g, %g, %g)\n", origin_x, origin_y, origin_z);
    origin (origin_x, origin_y, origin_z);

    // Compute distance field from STL
    scalar d[];
    distance (d, p);

    // Adapt mesh based on distance field
    fprintf(ferr, "Adapting mesh based on STL geometry...\n");
    while (adapt_wavelet_limited ((scalar *){f, d},
                                   (double[]){1e-6, 1e-6*L0},
                                   refRegion,
                                   minlevel=MINlevel).nf);

    // Convert distance field to volume fraction
    vertex scalar phi[];
    foreach_vertex(){
      phi[] = (d[] + d[-1] + d[0,-1] + d[-1,-1] +
               d[0,0,-1] + d[-1,0,-1] + d[0,-1,-1] + d[-1,-1,-1])/8.;
    }
    fractions (phi, f);

    // Initialize velocity to zero
    foreach () {
      foreach_dimension(){
        u.x[] = 0.0;
      }
    }

    // Save initial condition
    dump (file = "dumpInit");
    fprintf(ferr, "Initial condition saved to dumpInit\n");
    fprintf(ferr, "==============================================\n\n");
  }
}
