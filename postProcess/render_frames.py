"""Render video frames for a case with getView3D_v2.

Authors: Saumili Jana, Vatsal Sanjay (CoMPhy Lab). Based on the original
render3D.py; globs every snapshot actually present and parallelises rendering.

Run from a case directory containing `intermediate/snapshot-*` and the compiled
`./getView3D_v2` binary:

    NPROC=32 python3 render_frames.py

Frames are written to `Video_view3_v2/<NNNNNN>.png` where the index is
`int(1e4 * t)`, so lexical order is time order (ready for ffmpeg).
"""
import subprocess as sp
import os, glob, re
from multiprocessing import Pool

FOLDER = "Video_view3_v2"
EXE = "./getView3D_v2"
NPROC = int(os.environ.get("NPROC", "16"))


def snap_to_t(path):
    m = re.search(r"snapshot-([0-9.]+)$", path)
    return float(m.group(1)) if m else None


def render(args):
    place, name = args
    if os.path.exists(name):
        return ("skip", name)
    p = sp.Popen([EXE, place, name], stdout=sp.PIPE, stderr=sp.PIPE)
    _, err = p.communicate()
    if p.returncode != 0 or not os.path.exists(name):
        return ("FAIL", name, err.decode("utf-8", "ignore")[-300:])
    return ("ok", name)


if __name__ == "__main__":
    os.makedirs(FOLDER, exist_ok=True)
    snaps = sorted(glob.glob("intermediate/snapshot-*"), key=lambda p: (snap_to_t(p) or 0))
    jobs = []
    for s in snaps:
        t = snap_to_t(s)
        if t is None:
            continue
        name = "%s/%6.6d.png" % (FOLDER, int(round(1e4 * t)))
        jobs.append((s, name))
    print(f"{len(jobs)} snapshots to render, NPROC={NPROC}", flush=True)

    with Pool(processes=NPROC) as pool:
        results = pool.map(render, jobs)

    ok = sum(1 for r in results if r[0] == "ok")
    skip = sum(1 for r in results if r[0] == "skip")
    fails = [r for r in results if r[0] == "FAIL"]
    print(f"rendered={ok} skipped={skip} failed={len(fails)} of {len(jobs)}", flush=True)
    for r in fails[:10]:
        print("FAIL", r[1], r[2], flush=True)
