"""Assemble and plot the energy budget from getEnergy.dat.

Author: Vatsal Sanjay (CoMPhy Lab). Python port of the original EnergyOriginal.m.
Reads the 12-column getEnergy.dat, integrates the dissipation rates in time
(trapezoid) into cumulative dissipation, and builds the stacked budget

    A = dE_s ; B = A + ke1 ; C = B + ke2 ; D = C + intEps1 ; E = D + intEps2

A closed budget keeps E near 0. Uses matplotlib mathtext only (no system LaTeX).

    python3 energy_budget.py [getEnergy.dat] [output_prefix]
"""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

DAT = sys.argv[1] if len(sys.argv) > 1 else "getEnergy.dat"
OUT = sys.argv[2] if len(sys.argv) > 2 else "energyBudget"

d = np.loadtxt(DAT)
d = d[np.argsort(d[:, 0])]
t = d[:, 0]
ke1, se, eps1, ke2, eps2 = d[:, 1], d[:, 8], d[:, 9], d[:, 10], d[:, 11]


def cumtrap(y, x):
    out = np.zeros_like(y)
    out[1:] = np.cumsum(0.5 * (y[1:] + y[:-1]) * (x[1:] - x[:-1]))
    return out


vd1 = cumtrap(eps1, t)
vd2 = cumtrap(eps2, t)

A = se - se[0]          # dE_surface
B = A + ke1             # + drop KE
C = B + ke2             # + gas KE
D = C + vd1             # + cumulative liquid dissipation
E = D + vd2             # + cumulative gas dissipation (closure -> ~0)

cu = plt.get_cmap("copper")
c_hi, c_mid, c_lo = cu(0.95), cu(0.55), cu(0.15)

plt.rcParams.update({"mathtext.fontset": "cm", "font.size": 18})
fig, ax = plt.subplots(figsize=(8, 7))
ax.plot(t, A, "-",  color=c_hi,  lw=3, label=r"$\Delta E_s$")
ax.plot(t, B, ":",  color=c_hi,  lw=3, label=r"$E_k(\mathrm{Drops})$")
ax.plot(t, C, "-",  color=c_mid, lw=3, label=r"$\Delta E_s + \sum E_k$")
ax.plot(t, D, "-",  color=c_lo,  lw=3, label=r"$\sum E_k + \Delta E_s + E_d(\mathrm{Drops})$")
ax.plot(t, E, ":",  color=c_lo,  lw=3, label=r"$\sum E_k + \Delta E_s + \sum E_d$")
ax.axhline(0, color="0.7", lw=1, zorder=0)
ax.set_xlabel(r"$t/\sqrt{\rho r^3/\gamma}$", fontsize=22)
ax.set_ylabel(r"$E/(\gamma r^2)$", fontsize=22)
ax.legend(frameon=False, fontsize=13, loc="upper left")
ax.tick_params(width=1.5)
for s in ax.spines.values():
    s.set_linewidth(1.5)
fig.tight_layout()
fig.savefig(OUT + ".png", dpi=200, facecolor="white")

hdr = "t dE_s ke1 ke2 intEps1 intEps2 A B C D E"
np.savetxt(OUT + ".csv",
           np.column_stack([t, A, ke1, ke2, vd1, vd2, A, B, C, D, E]),
           header=hdr, comments="# ")
print(f"closure: E[0]={E[0]:.4e}  E[-1]={E[-1]:.4e}  max|E|={np.max(np.abs(E)):.4e}")
print(f"wrote {OUT}.png and {OUT}.csv  ({len(t)} rows, t in [{t[0]:.3f},{t[-1]:.3f}])")
