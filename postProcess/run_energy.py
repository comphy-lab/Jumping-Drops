"""Run getEnergy over every snapshot of a case and assemble getEnergy.dat.

Author: Vatsal Sanjay (CoMPhy Lab). Based on the original getEnergyScript.py;
parallelised across snapshots. Each snapshot is written to its own one-line file
(no shared-append contention) and concatenated in time order at the end.

Run from a case directory containing `intermediate/snapshot-*` and the compiled
`./getEnergy` binary:

    python3 run_energy.py [Oh]          # Oh defaults to the value in case.params
    NPROC=32 python3 run_energy.py 0.05

Output: getEnergy.dat with columns
    t ke1 xcm ucm ycm vcm zcm wcm se eps1 ke2 eps2
"""
import subprocess as sp
import os, glob, re, sys
from multiprocessing import Pool

EXE = "./getEnergy"
TMP = "energy_parts"
OUT = "getEnergy.dat"
NPROC = int(os.environ.get("NPROC", "16"))


def get_oh():
    if len(sys.argv) > 1:
        return sys.argv[1]
    if os.path.exists("case.params"):
        for line in open("case.params"):
            m = re.match(r"\s*Oh\s*=\s*([0-9.eE+-]+)", line)
            if m:
                return m.group(1)
    raise SystemExit("Oh not given and not found in case.params")


def snap_to_t(path):
    m = re.search(r"snapshot-([0-9.]+)$", path)
    return float(m.group(1)) if m else None


def run_one(args):
    place, part, oh = args
    if os.path.exists(part) and os.path.getsize(part) > 0:
        return ("skip", place)
    open(part, "w").close()
    p = sp.Popen([EXE, place, part, oh], stdout=sp.PIPE, stderr=sp.PIPE)
    _, err = p.communicate()
    if p.returncode != 0 or os.path.getsize(part) == 0:
        return ("FAIL", place, err.decode("utf-8", "ignore")[-300:])
    return ("ok", place)


if __name__ == "__main__":
    oh = get_oh()
    os.makedirs(TMP, exist_ok=True)
    snaps = sorted(glob.glob("intermediate/snapshot-*"), key=lambda p: (snap_to_t(p) or 0))
    jobs = []
    for s in snaps:
        t = snap_to_t(s)
        if t is None:
            continue
        part = "%s/e_%6.6d.dat" % (TMP, int(round(1e4 * t)))
        jobs.append((s, part, oh))
    print(f"Oh={oh}  {len(jobs)} snapshots  NPROC={NPROC}", flush=True)

    with Pool(processes=NPROC) as pool:
        results = pool.map(run_one, jobs)

    fails = [r for r in results if r[0] == "FAIL"]
    ok = sum(1 for r in results if r[0] == "ok")
    print(f"computed={ok} failed={len(fails)} of {len(jobs)}", flush=True)
    for r in fails[:10]:
        print("FAIL", r[1], r[2], flush=True)

    parts = sorted(glob.glob(f"{TMP}/e_*.dat"))
    with open(OUT, "w") as out:
        for pth in parts:
            data = open(pth).read()
            if data.strip():
                out.write(data if data.endswith("\n") else data + "\n")
    print(f"wrote {OUT} ({sum(1 for _ in open(OUT))} rows)", flush=True)
