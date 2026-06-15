/**
# Jumping Drops - Common Definitions

Shared constants, tolerances, boundary conditions, and helper functions used
by both the initialization phase and the main simulation phase.

## Purpose

This header ensures consistent behavior across both phases by centralizing:

- Grid and domain parameters
- Time-stepping parameters
- Adaptive mesh refinement tolerances
- Fluid property ratios
- Boundary conditions
- Event handlers (adapt, snapshot writing, log writing)

## Usage

Include this header in both `jumpingDrops_init.c` and `jumpingDrops_main.c`:

```c
#include "jumpingDrops_common.h"
```

For MPI-aware logging in the main phase, define `MPI_MODE` before including:

```c
#define MPI_MODE
#include "jumpingDrops_common.h"
```

## Dependencies

Requires Basilisk C headers:

- `grid/octree.h`
- `navier-stokes/centered.h`
- `two-phase.h`
- `navier-stokes/conserving.h`
- `tension.h`

## Author

Vatsal Sanjay (vatsal.sanjay@comphy-lab.org)  
CoMPhy Lab, Durham University  
Last updated: 2026-01-30
*/

#ifndef JUMPING_DROPS_COMMON_H
#define JUMPING_DROPS_COMMON_H

/**
## Common Includes

Basilisk C modules for 3D octree grids, Navier-Stokes solver, two-phase flow,
and surface tension.
*/

#include "grid/octree.h"
#include "navier-stokes/centered.h"
#define FILTERED 1
#include "two-phase.h"
#include "navier-stokes/conserving.h"
#include "tension.h"

/**
## Grid and Domain Parameters

- `MINlevel`: Minimum refinement level across the entire domain
- `Ldomain`: Physical size of the cubic domain (normalized units)
*/

#define MINlevel 2                    // minimum refinement level
#define Ldomain 4                     // dimension of the domain

/**
## Time Stepping Parameters

- `tsnap`: Interval for writing dump files (snapshots)
- `tsnap2`: Interval for logging kinetic energy and velocity
*/
#define tsnap (1e-2)                  // snapshot interval
#define tsnap2 (1e-2)                 // log writing interval

/**
## Adaptive Mesh Refinement Tolerances

These values are consistent across init and main phases. Stricter tolerances
ensure accurate initial conditions and stable time integration.

- `fErr`: Error tolerance for volume fraction field
- `KErr`: Error tolerance for interface curvature
- `VelErr`: Error tolerance for velocity components
*/
#define fErr (1e-3)                   // error tolerance in VOF
#define KErr (1e-4)                   // error tolerance in curvature
#define VelErr (1e-2)                 // error tolerance in velocity

/**
## Fluid Properties (Dimensionless Ratios)

- `Mu21`: Viscosity ratio (gas/liquid), typically O(10^-3)
- `Rho21`: Density ratio (gas/liquid), typically O(10^-3)
*/
#define Mu21 (1.00e-3)                // viscosity ratio (gas/liquid)
#define Rho21 (1.00e-3)               // density ratio (gas/liquid)

/**
## Global Variables

External declarations for runtime parameters set in main programs.
*/
extern double tmax;                   // maximum simulation time
extern double Oh;                     // Ohnesorge number
extern double Bo;                     // Bond number
extern int MAXlevel;                  // maximum refinement level

/**
## Boundary Conditions

No-slip wall at the bottom boundary (substrate). Velocity components and
volume fraction are set to zero.
*/
u.t[bottom] = dirichlet(0.);
u.r[bottom] = dirichlet(0.);
f[bottom] = dirichlet(0.);

/**
## Adaptive Mesh Refinement Event

Triggered every iteration to adapt the mesh based on flow features: volume
fraction gradients, interface curvature, and velocity gradients. Refinement is
uniform up to `MAXlevel` via the standard `adapt_wavelet`.
*/
event adapt(i++) {
  scalar KAPPA[];
  curvature(f, KAPPA);
  adapt_wavelet ((scalar *){f, KAPPA, u.x, u.y, u.z},
     (double[]){fErr, KErr, VelErr, VelErr, VelErr},
      maxlevel=MAXlevel, minlevel=MINlevel);
}

/**
## Snapshot Writing Event

Writes dump files at regular intervals (`tsnap`) for restart and post-processing.
Saves to both `dump` (current state) and `intermediate/snapshot-*` (archive).
*/
event writingFiles (t = 0; t += tsnap; t <= tmax+tsnap) {
  dump (file = "dump");
  char nameOut[80];
  sprintf (nameOut, "intermediate/snapshot-%5.4f", t);
  dump (file = nameOut);
}

/**
## Log Writing Event

Records time series of kinetic energy and center-of-mass velocity at high
frequency (`tsnap2`). When `MPI_MODE` is defined, only rank 0 writes to the
log file.
*/
event logWriting (t = 0; t += tsnap2; t <= tmax+tsnap) {

  // Compute volume-averaged quantities
  double ke = 0., wt = 0., Vcm = 0.;
  foreach (reduction(+:ke) reduction(+:Vcm) reduction(+:wt)){
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
