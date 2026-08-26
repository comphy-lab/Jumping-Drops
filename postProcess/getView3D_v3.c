/**
# getView3D_v3 - MPI render one snapshot to a PPM image

Authors: Saumili Jana, Vatsal Sanjay (CoMPhy Lab).

Restores one `intermediate/snapshot-*` dump on a distributed octree and
renders the same mirrored scene as `getView3D_v2.c`. Every MPI rank draws its
local cells and enters `save()` collectively; Basilisk View composites the
colour and depth buffers on rank zero.

The renderer writes PPM because it is Basilisk View's native MPI image format.
The sweep driver converts the rank-zero PPM output to PNG atomically.

## Usage

```bash
srun --ntasks=24 ./getView3D_v3 snapshot output.ppm \
  [theta phi psi fov tx ty tz]
```
*/

#include <string.h>
#include <stdlib.h>
#include <limits.h>

#include "grid/octree.h"
#include "navier-stokes/centered.h"
#include "view.h"
#include "draw.h"

scalar f[];
char filename[PATH_MAX], Imagename[PATH_MAX];

static void draw_scene()
{
  draw_vof (c = "f", edges = false, fc = {0.95, 0.55, 0.00});
  squares (color = "0.0", min = -1.0, max = 1.0,
           n = {0, 1, 0}, alpha = -1.003, map = cool_warm);
  cells (n = {0, 1, 0}, lc = {0., 0., 0.}, alpha = -1.003, lw = 1);
}

static void draw_mirrored_xz_scene()
{
  draw_scene();

  mirror (n = {1, 0, 0})
    draw_scene();

  mirror (n = {0, 0, 1})
    draw_scene();

  {
    bview * view = draw();

    glMatrixMode (GL_MODELVIEW);
    glPushMatrix();
    glScalef (-1.0, 1.0, -1.0);
    gl_get_frustum (&view->frustum);
    view->reversed = !view->reversed;

    draw_scene();

    glMatrixMode (GL_MODELVIEW);
    glPopMatrix();
    gl_get_frustum (&view->frustum);
    view->reversed = !view->reversed;
  }
}

static void draw_time_label()
{
  double time = 0.;
  char label[80];
  char * dash = strrchr (filename, '-');

  if (dash && sscanf (dash + 1, "%lf", &time) == 1)
    snprintf (label, sizeof(label), "t = %.2f", time);
  else
    snprintf (label, sizeof(label), "t = %.2f", t);

  draw_string (label, pos = 2, size = 55, lc = {0., 0., 0.}, lw = 1.2);
}

int main (int argc, char const * argv[])
{
  if (argc < 3) {
    if (pid() == 0)
      fprintf (stderr,
               "usage: %s snapshot output.ppm [theta phi psi fov tx ty tz]\n",
               argv[0]);
    return 1;
  }

  snprintf (filename, sizeof(filename), "%s", argv[1]);
  snprintf (Imagename, sizeof(Imagename), "%s", argv[2]);
  if (!restore (file = filename)) {
    if (pid() == 0)
      fprintf (stderr, "could not restore '%s'\n", filename);
    return 2;
  }

  double theta = -1.57, phi = 0.35, psi = 0.;
  double fov = 15., tx = 0., ty = -0.08, tz = -4.55;
  if (argc > 3) theta = atof (argv[3]);
  if (argc > 4) phi   = atof (argv[4]);
  if (argc > 5) psi   = atof (argv[5]);
  if (argc > 6) fov   = atof (argv[6]);
  if (argc > 7) tx    = atof (argv[7]);
  if (argc > 8) ty    = atof (argv[8]);
  if (argc > 9) tz    = atof (argv[9]);

  view (theta = theta, phi = phi, psi = psi,
        fov = fov, near = 0.01, far = 1000,
        tx = tx, ty = ty, tz = tz,
        width = 1024, height = 768, samples = 4,
        bg = {1.0, 1.0, 1.0});

  draw_mirrored_xz_scene();
  draw_time_label();

  FILE * output = pid() == 0 ? fopen (Imagename, "wb")
                             : fopen ("/dev/null", "wb");
  int can_write = output != NULL, all_can_write = can_write;
  MPI_Allreduce (&can_write, &all_can_write, 1, MPI_INT, MPI_MIN,
                 MPI_COMM_WORLD);
  if (!all_can_write) {
    if (pid() == 0)
      perror (Imagename);
    if (output)
      fclose (output);
    return 3;
  }

  bool saved = save (fp = output, format = "ppm");
  if (fclose (output) != 0)
    saved = false;
  return saved ? 0 : 4;
}
