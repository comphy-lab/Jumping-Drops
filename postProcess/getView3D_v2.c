/**
# getView3D_v2 - render one snapshot to a PNG

Authors: Saumili Jana, Vatsal Sanjay (CoMPhy Lab).

Restores one `intermediate/snapshot-*` dump and renders the drop interface with
the cross-section coloured field and the mesh, mirrored across the symmetry
planes to reconstruct the full drop. The time label is parsed from the snapshot
filename (`...-<t>`).

## Usage

```bash
./getView3D_v2 <snapshot> <output.png> [theta phi psi fov tx ty tz]
```

Camera defaults match the production frames; the optional arguments override
view angles and translation.
*/

#include <string.h>
#include <stdlib.h>

#include "grid/octree.h"
#include "navier-stokes/centered.h"
#include "view.h"
#include "draw.h"

scalar f[];
char filename[80], Imagename[80];

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

int main (int a, char const * arguments[])
{
  if (a < 3) {
    fprintf (stderr, "usage: %s snapshot output.png [theta phi psi fov tx ty tz]\n", arguments[0]);
    return 1;
  }

  snprintf (filename, sizeof(filename), "%s", arguments[1]);
  snprintf (Imagename, sizeof(Imagename), "%s", arguments[2]);
  restore (file = filename);

  double theta = -1.57, phi = 0.35, psi = 0.;
  double fov = 15., tx = 0., ty = -0.08, tz = -4.55;
  if (a > 3) theta = atof (arguments[3]);
  if (a > 4) phi   = atof (arguments[4]);
  if (a > 5) psi   = atof (arguments[5]);
  if (a > 6) fov   = atof (arguments[6]);
  if (a > 7) tx    = atof (arguments[7]);
  if (a > 8) ty    = atof (arguments[8]);
  if (a > 9) tz    = atof (arguments[9]);

  view (theta = theta, phi = phi, psi = psi,
        fov = fov, near = 0.01, far = 1000,
        tx = tx, ty = ty, tz = tz,
        width = 1024, height = 768, samples = 4,
        bg = {1.0, 1.0, 1.0});

  draw_mirrored_xz_scene();
  draw_time_label();
  save (Imagename);
}
