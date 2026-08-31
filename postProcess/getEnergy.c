/**
# getEnergy - energy diagnostics from a saved snapshot

Author: Vatsal Sanjay (vatsal.sanjay@comphy-lab.org), CoMPhy Lab.

Restores one `intermediate/snapshot-*` dump and writes a single line of
volume-integrated energy diagnostics. Phase 1 is liquid, phase 2 is gas.

## Usage

```bash
./getEnergy <snapshot> <output.dat> <Oh>
```

Appends one whitespace-separated row to `<output.dat>`:

```
t ke1 xcm ucm ycm vcm zcm wcm se eps1 ke2 eps2
```

where `ke1`/`ke2` are kinetic energies, `(xcm..wcm)` the liquid centre-of-mass
position and velocity, `se = interface_area(f) - 8*pi` the surface energy
relative to two unit drops, and `eps1`/`eps2` the instantaneous viscous
dissipation rates.

## Fluid properties

These must match `simulationCases/jumpingDrops_main.c`:
`rho1 = 1`, `mu1 = Oh`, `rho2 = Rho21 = 1e-3`,
`mu2 = Mu21*Oh` with `Mu21 = 1e-2`, and `f.sigma = 1`.
*/
#include <string.h>
#include <stdlib.h>
#include <limits.h>

#include "grid/octree.h"
#include "navier-stokes/centered.h"
#include "fractions.h"

scalar f[];
double ke1, xcm, ucm, ycm, vcm, zcm, wcm, se, eps1, ke2, eps2, rho1, rho2, mu1, mu2;
char nameEnergy[PATH_MAX], nameOut[PATH_MAX];

#define Rho21 (1.00e-3)   // density ratio gas/liquid (matches src-local/jumpingDrops_common.h)
#define Mu21  (1.00e-2)   // dynamic-viscosity ratio gas/liquid

int main(int argc, char const *arguments[]) {
  if (argc < 4) {
    if (pid() == 0)
      fprintf (stderr, "usage: %s snapshot output.dat Oh\n", arguments[0]);
    return 1;
  }

  snprintf (nameOut, sizeof(nameOut), "%s", arguments[1]);
  snprintf (nameEnergy, sizeof(nameEnergy), "%s", arguments[2]);
  double Oh = atof(arguments[3]);

  if (!restore (file = nameOut)) {
    if (pid() == 0)
      fprintf (stderr, "could not restore '%s'\n", nameOut);
    return 2;
  }

  rho1 = 1.0; mu1 = Oh;
  rho2 = Rho21; mu2 = Mu21*Oh;

  // boundary conditions
  u.t[bottom] = dirichlet(0.);
  u.r[bottom] = dirichlet(0.);
  f[bottom] = dirichlet(0.);

  #if TREE
    f.prolongation = fraction_refine;
  #endif
  boundary((scalar *){f, u.x, u.y, u.z});

  ke1 = 0., xcm = 0., ucm = 0., ycm = 0., vcm = 0., zcm = 0., wcm = 0., se = 0., eps1 = 0., ke2 = 0., eps2 = 0.;

  double sumU = 0.; double sumV = 0.; double sumW = 0.;
  double sumX = 0.; double sumY = 0.; double sumZ = 0.;
  double wt = 0.;

  foreach (reduction(+:ke1) reduction(+:ke2)
           reduction(+:sumU) reduction(+:sumV) reduction(+:sumW)
           reduction(+:sumX) reduction(+:sumY) reduction(+:sumZ)
           reduction(+:wt) reduction(+:eps1) reduction(+:eps2)) {
    ke1 += (0.5*clamp(f[], 0., 1.)*rho1*(sq(u.x[]) + sq(u.y[]) + sq(u.z[])))*cube(Delta);
    ke2 += (0.5*clamp(1.-f[], 0., 1.)*rho2*(sq(u.x[]) + sq(u.y[]) + sq(u.z[])))*cube(Delta);

    sumU += clamp(f[], 0., 1.)*u.x[]*cube(Delta);
    sumV += clamp(f[], 0., 1.)*u.y[]*cube(Delta);
    sumW += clamp(f[], 0., 1.)*u.z[]*cube(Delta);

    sumX += clamp(f[], 0., 1.)*x*cube(Delta);
    sumY += clamp(f[], 0., 1.)*y*cube(Delta);
    sumZ += clamp(f[], 0., 1.)*z*cube(Delta);

    wt += clamp(f[], 0., 1.)*cube(Delta);

    double D2 = 0.;
    foreach_dimension(){
      double DII = (u.x[1,0,0]-u.x[-1,0,0])/(2*Delta);
      double DIJ = 0.5*((u.x[0,1,0]-u.x[0,-1,0] + u.y[1,0,0] - u.y[-1,0,0])/(2*Delta));
      double DIK = 0.5*((u.x[0,0,1]-u.x[0,0,-1] + u.z[1,0,0] - u.z[-1,0,0])/(2*Delta));
      D2 += sq(DII) + sq(DIJ) + sq(DIK);
    }
    eps1 += ( 2*mu1*clamp(f[], 0., 1.)*D2 )*cube(Delta);
    eps2 += ( 2*mu2*clamp(1.-f[], 0., 1.)*D2 )*cube(Delta);
  }

  if (wt == 0.) {
    if (pid() == 0)
      fprintf (stderr, "empty liquid volume in '%s'\n", nameOut);
    return 3;
  }

  sumU /= wt; sumX /= wt;
  sumV /= wt; sumY /= wt;
  sumW /= wt; sumZ /= wt;

  ucm = sumU; vcm = sumV; wcm = sumW;
  xcm = sumX; ycm = sumY; zcm = sumZ;

  se = (interface_area (f)-8*pi);

  if (pid() != 0)
    return 0;

  FILE *fp = fopen (nameEnergy, "a");
  if (!fp) {
    perror (nameEnergy);
    return 4;
  }
  fprintf(fp, "%f %f %f %f %f %f %f %f %f %f %f %f\n", t, ke1, xcm, ucm, ycm, vcm, zcm, wcm, se, eps1, ke2, eps2);
  if (fclose(fp) != 0)
    return 5;
  return 0;
}
