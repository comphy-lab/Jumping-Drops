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
`rho1 = 1`, `mu1 = Oh`, `rho2 = Rho21 = 1e-3`, `mu2 = 1e-5` (constant),
`f.sigma = 1`. Note `mu2` is fixed at `1e-5`, not `Mu21*Oh`.
*/
#include "grid/octree.h"
#include "navier-stokes/centered.h"
#include "fractions.h"

scalar f[];
double ke1, xcm, ucm, ycm, vcm, zcm, wcm, se, eps1, ke2, eps2, rho1, rho2, mu1, mu2;
char nameEnergy[80], nameOut[80];

#define Rho21 (1.00e-3)   // density ratio gas/liquid (matches src-local/jumpingDrops_common.h)
#define MU2   (1.00e-5)   // gas viscosity, constant (matches simulationCases/jumpingDrops_main.c)

int main(int a, char const *arguments[]) {
  sprintf(nameOut, "%s", arguments[1]);
  sprintf(nameEnergy, "%s", arguments[2]);
  double Oh = atof(arguments[3]);

  FILE *fp;
  fp = fopen (nameEnergy, "a");
  restore (file = nameOut);

  rho1 = 1.0; mu1 = Oh;
  rho2 = Rho21; mu2 = MU2;

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

  foreach (){
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

  sumU /= wt; sumX /= wt;
  sumV /= wt; sumY /= wt;
  sumW /= wt; sumZ /= wt;

  ucm = sumU; vcm = sumV; wcm = sumW;
  xcm = sumX; ycm = sumY; zcm = sumZ;

  se = (interface_area (f)-8*pi);

  boundary((scalar *){f, u.x, u.y, u.z});

  fprintf(fp, "%f %f %f %f %f %f %f %f %f %f %f %f\n", t, ke1, xcm, ucm, ycm, vcm, zcm, wcm, se, eps1, ke2, eps2);
  fclose(fp);
}
