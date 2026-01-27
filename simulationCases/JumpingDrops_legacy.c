/* Title: Jumping Drops
# Author: Vatsal Sanjay
# vatsalsanjay@gmail.com
# Physics of Fluids
*/

#include "grid/octree.h"
#include "navier-stokes/centered.h"
#define FILTERED
#include "two-phase.h"
#include "navier-stokes/conserving.h"
#include "tension.h"
#include "distance.h"
#include "adapt_wavelet_limited_v2.h"
#include "reduced.h"

#define MINlevel 2                                              // maximum level

#define tsnap (1e-2)
#define tsnap2 (1e-4)
// Error tolerances
#define fErr (1e-3)                                 // error tolerance in VOF
#define KErr (1e-4)                                 // error tolerance in KAPPA
#define VelErr (1e-2)                            // error tolerances in velocity

#define Mu21 (1.00e-3)
#define Rho21 (1.00e-3)

// domain
#define Ldomain 4                                // Dimension of the domain

// boundary conditions
u.t[bottom] = dirichlet(0.);
u.r[bottom] = dirichlet(0.);
f[bottom] = dirichlet(0.);

double tmax, Oh, Bo;
int MAXlevel;                                              // maximum level

int main(int argc, char *argv[]) {

  tmax = tsnap;
  Oh = atof(argv[2]); // <0.001/sqrt(1000*0.072*0.001)>
  Bo = atof(argv[3]); // <0.001/(1000*9.81*0.072)>
  MAXlevel = atoi(argv[4]);

  init_grid (1 << MINlevel);
  L0=Ldomain;
  fprintf(ferr, "tmax = %g. Oh = %g\n",tmax, Oh);
  rho1 = 1.0; mu1 = Oh;
  rho2 = Rho21; mu2 = 1e-5; //Mu21*Oh;
  f.sigma = 1.0;
  G.y = -Bo;

  char comm[80];
  sprintf (comm, "mkdir -p intermediate");
  system(comm);

  run();

}

int refRegion(double x, double y, double z){
  return (y < 1.5 && x < 1.5 && z < 1e-2) ? MAXlevel+1: // close to coalescence plane
   (y < -0.999 && x < 1.5 && z < 2.5)? MAXlevel+1: // close to the substrate
   (y < 1.5 && x < 2e0 && z < 3e0)? MAXlevel: // inside the drop
   MAXlevel-1; // everywhere else
}

event init(t = 0){
  if(!restore (file = "dump")){
    char filename[60];
    sprintf(filename,"InitialCondition.stl");
    FILE * fp = fopen (filename, "r");
    if (fp == NULL){
      fprintf(ferr, "There is no file named %s\n", filename);
      return 1;
    }
    coord * p = input_stl (fp);
    fclose (fp);
    coord min, max;

    bounding_box (p, &min, &max);
    fprintf(ferr, "xmin %g xmax %g\nymin %g ymax %g\nzmin %g zmax %g\n", min.x, max.x, min.y, max.y, min.z, max.z);
    fprintf(ferr, "x0 = %g, y0 = %g, z0 = %g\n", 0., - 1 - L0/pow(2,MAXlevel), (min.z+max.z)/2.);
    origin (0., - 1 - L0/pow(2,MAXlevel), (min.z+max.z)/2.);

    scalar d[];
    distance (d, p);
    while (adapt_wavelet_limited ((scalar *){f, d}, (double[]){1e-6, 1e-6*L0}, refRegion, minlevel=MINlevel).nf);
    vertex scalar phi[];
    foreach_vertex(){
      phi[] = (d[] + d[-1] + d[0,-1] + d[-1,-1] +
  	     d[0,0,-1] + d[-1,0,-1] + d[0,-1,-1] + d[-1,-1,-1])/8.;
    }
    fractions (phi, f);

    foreach () {
      foreach_dimension(){
        u.x[] = 0.0;
      }
    }

    dump (file = "dumpInit");
    fprintf(ferr, "Done with initial condition!\n");
    // return 1;
  }
}

event adapt(i++) {
  scalar KAPPA[];
  curvature(f, KAPPA);
  adapt_wavelet_limited ((scalar *){f, KAPPA, u.x, u.y, u.z},
     (double[]){fErr, KErr, VelErr, VelErr, VelErr},
      refRegion, minlevel=MINlevel);
}

// Outputs
event writingFiles (t = 0; t += tsnap; t <= tmax+tsnap) {
  dump (file = "dump");
  char nameOut[80];
  sprintf (nameOut, "intermediate/snapshot-%5.4f", t);
  dump (file = nameOut);
}

event logWriting (t = 0; t += tsnap2; t <= tmax+tsnap) {

  double ke = 0., wt = 0., Vcm = 0.;
  foreach (reduction(+:ke), reduction(+:Vcm), reduction(+:wt)){
    ke += 0.5*(sq(u.x[]) + sq(u.y[]) + sq(u.z[]))*clamp(f[], 0., 1.)*cube(Delta);
    Vcm += clamp(f[], 0., 1.)*u.y[]*cube(Delta);
    wt += clamp(f[], 0., 1.)*cube(Delta);
  }
  Vcm /= wt;

  static FILE * fp;
  if (i == 0) {
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
}
