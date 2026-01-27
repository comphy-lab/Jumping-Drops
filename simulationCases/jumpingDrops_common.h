/**  
# Title: Jumping Drops - Common Definitions
- Author: Vatsal Sanjay (vatsal.sanjay@comphy-lab.org)
- CoMPhy Lab, Durham University

This header contains shared definitions and functions used by both
initialization (jumpingDrops_init.c) and main simulation (jumpingDrops_main.c)
*/

#ifndef JUMPING_DROPS_COMMON_H
#define JUMPING_DROPS_COMMON_H

/** 
============================================================
Common Includes
============================================================
*/

#include "grid/octree.h"
#include "navier-stokes/centered.h"
#define FILTERED
#include "two-phase.h"
#include "navier-stokes/conserving.h"
#include "tension.h"
#include "adapt_wavelet_limited_v2.h"

/** 
============================================================
Grid and Domain Parameters
============================================================
*/

#define MINlevel 5                    // minimum refinement level
#define Ldomain 4                     // dimension of the domain

/** 
============================================================
Time Stepping Parameters
============================================================
*/
#define tsnap (1e-2)                  // snapshot interval
#define tsnap2 (1e-4)                 // log writing interval

/**
============================================================
Adaptive Mesh Refinement Tolerances
============================================================
These values are consistent across init and main phases
Stricter tolerances ensure accurate initial conditions
*/
#define fErr (1e-3)                   // error tolerance in VOF
#define KErr (1e-4)                   // error tolerance in curvature
#define VelErr (1e-2)                 // error tolerance in velocity

/** 
============================================================
Fluid Properties (Dimensionless Ratios)
============================================================
*/
#define Mu21 (1.00e-3)                // viscosity ratio (gas/liquid)
#define Rho21 (1.00e-3)               // density ratio (gas/liquid)

/** 
============================================================
Global Variables
============================================================
*/
extern double tmax;                   // maximum simulation time
extern double Oh;                     // Ohnesorge number
extern double Bo;                     // Bond number
extern int MAXlevel;                  // maximum refinement level

/** 
============================================================
Boundary Conditions
============================================================
No-slip wall at bottom (substrate)
*/
u.t[bottom] = dirichlet(0.);
u.r[bottom] = dirichlet(0.);
f[bottom] = dirichlet(0.);

/** 
============================================================
Refinement Region Function
============================================================
Defines spatially-varying maximum refinement levels
Returns the target refinement level for a given (x, y, z) location
*/
int refRegion(double x, double y, double z){
  return (y < 1.5 && x < 1.5 && z < 1e-2) ? MAXlevel+1:  // coalescence plane
         (y < -0.999 && x < 1.5 && z < 2.5)? MAXlevel+1: // near substrate
         (y < 1.5 && x < 2e0 && z < 3e0)? MAXlevel:      // inside drop
         MAXlevel-1;                                      // everywhere else
}

/** 
============================================================
Adaptive Mesh Refinement Event
============================================================
Triggered every iteration to adapt the mesh based on flow features
*/
event adapt(i++) {
  scalar KAPPA[];
  curvature(f, KAPPA);
  adapt_wavelet_limited ((scalar *){f, KAPPA, u.x, u.y, u.z},
     (double[]){fErr, KErr, VelErr, VelErr, VelErr},
      refRegion, minlevel=MINlevel);
}

/** 
============================================================
Snapshot Writing Event
============================================================
Writes dump files at regular intervals for restart and post-processing
*/
event writingFiles (t = 0; t += tsnap; t <= tmax+tsnap) {
  dump (file = "dump");
  char nameOut[80];
  sprintf (nameOut, "intermediate/snapshot-%5.4f", t);
  dump (file = nameOut);
}

/** 
============================================================
Log Writing Event
============================================================
Records kinetic energy and center-of-mass velocity
MPI_MODE flag controls whether to use MPI-aware writing (pid() check)
*/
event logWriting (t = 0; t += tsnap2; t <= tmax+tsnap) {

  // Compute volume-averaged quantities
  double ke = 0., wt = 0., Vcm = 0.;
  foreach (reduction(+:ke), reduction(+:Vcm), reduction(+:wt)){
    ke += 0.5*(sq(u.x[]) + sq(u.y[]) + sq(u.z[]))*clamp(f[], 0., 1.)*cube(Delta);
    Vcm += clamp(f[], 0., 1.)*u.y[]*cube(Delta);
    wt += clamp(f[], 0., 1.)*cube(Delta);
  }
  Vcm /= wt;

  static FILE * fp;

#ifdef MPI_MODE
  // MPI mode: Only rank 0 writes to file
  if (pid() == 0) {
#endif
    if (i == 0) {
      fprintf(ferr, "tmax = %g. Oh = %g\n", tmax, Oh);
      fprintf (ferr, "i dt t ke Vcm\n");
      fp = fopen ("log", "w");
      fprintf (fp, "i dt t ke Vcm\n");
      fprintf (fp, "%d %g %g %g %g\n", i, dt, t, ke, Vcm);
      fclose(fp);
    } else {
      fp = fopen ("log", "a");
      fprintf (fp, "%d %g %g %g %g\n", i, dt, t, ke, Vcm);
      fclose(fp);
    }
    fprintf (ferr, "%d %g %g %g %g\n", i, dt, t, ke, Vcm);
#ifdef MPI_MODE
  }
#endif
}

#endif // JUMPING_DROPS_COMMON_H
