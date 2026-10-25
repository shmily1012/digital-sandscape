# Directed scalar load transfer candidate

Status: REJECTED for product use after the static-work gate. Default load_factor=0.
Implementation remains only for reproducing the failure. Historical verification
below describes numerical consistency, not physical acceptance.

## Rule and numerical implementation

Each mineral voxel contributes an effective buoyant weight of 2.0, 1.7 or 1.4.
It passes its accumulated scalar load to the two cardinal downstream neighbors
with fractions `abs(gx)/(abs(gx)+abs(gy))` and `abs(gy)/(abs(gx)+abs(gy))`.
Grain neighbors accumulate and forward it; liquid/gas cells and permanent walls
are terminal receivers. At zero gravity the derived load field is zero.
There is no timestep history or persistent load accumulation between updates.

This takes inspiration from scalar load-transfer models such as
[Coppersmith et al.](https://doi.org/10.1103/PhysRevE.53.4673), but does not implement
their stochastic bead-pack model. Contact directions, frictional force balance,
arching and torque are not resolved. The gravity-based split is our explicit
approximation, not a measured constitutive law.

After orienting coordinates with gravity, each cell depends only on its logical
left/up predecessors. The GPU evaluates 8x8 tiles in diagonal wavefronts. Inside
a tile, 15 shared-memory diagonals with barriers resolve the dependencies;
between tiles, dispatch barriers make earlier tile results visible. Each cell
has one writer. The number of dispatches is bounded at `2*ceil(side/8)-1`, with
no convergence loop, atomics, floating accumulation across writers or CPU readback.

The field is derived from the current material geometry at the beginning of every
tick. In a fluid receiver the momentum force becomes
`mu grad(c) + (load_factor * terminal_load - c) g`.
Permanent walls absorb their received load rather than forcing the fluid.
The original experiment used load_factor=1; the current host defaults to 0.
The field includes accumulated load at grains for routing, but the momentum
kernel never applies those grain values directly to fluid inside solids.

## Verification

- `python run.py grain-load`: 19x19 (including partial tiles), eight gravity
  directions and zero gravity. Maximum GPU/CPU difference 1.94e-6; terminal
  received weight agrees with total 309.1 within 4.1e-5. Closed material boundaries
  ensure every path terminates before leaving the grid.
- CPU tests check arbitrary-angle conservation, stack-to-fluid transfer, floor
  absorption and reduced load after removing a top grain.
- `python run.py phase-coupled`: a second 80-step fixture with a fixed grain
  column verifies the nonzero load source together with phase/momentum evolution;
  maximum phase/velocity errors 4.34e-7 / 9.18e-8. Fixed geometry isolates the
  operator; it is not a mechanical equilibrium test.
- `python run.py phase-load-response`: identical 256² initial gas, particles,
  distributions, seed and gravity, 1500 steps, load_factor0 versus1. Gas rise is
  about2.53 versus1.70 cells; phase L1 difference174.75 cells. Material inventory
  is identical. Final terminal weight sums match total12759.1 to floating-point
  tolerance. This demonstrates a causal load effect, not quantitative fidelity.
- Actual sand host5000 steps passes particle/gas inventory, no solid-gas overlap,
  boundary, finite/nonnegative fluid distributions, rotation and shutdown checks.

## Budget and unresolved physical questions

RX7900XTX local-RD tick plus colorize, 60 samples after10 warmups: p95 approximately
1.015ms at256² and1.817ms at512². Dedicated buffers/output are7.75/31MiB. This is
about an order of magnitude slower than the prior traction-only candidate. It
excludes Canvas, CPU scheduling, engine/driver memory, utilization and long runs.
Do not claim the requested GPU percentage is enforced or optimize by silently
dropping load transfers. The existing bounded scheduling still applies.

The fluid sink assumes transfer of effective weight into the carrier through an
overdamped support/drag approximation. It does not implement a reciprocal moving
boundary or exact mechanical work. In particular, a motionless bed could create
spurious persistent flow if the localized force is not balanced by pressure.
Static-load energy/work and stationary-flow tests are a required next gate.
Also outstanding: realistic friction/contact paths, wetting/capillary breakthrough,
angle/resolution convergence, calibrated time scale and a natural settling cycle.
Conservation and altered bubble rise alone are insufficient for product acceptance.

## Static-work gate result (2026-10-24)

REJECTED for default use. See reports/phase-static-work.json: a fixed grain roof in initially resting gas-free liquid sustains positive work through tick 8000. Default load_factor is now zero; explicitly enabled tests preserve the failure. Conservative scalar force totals do not establish a mechanically admissible coupling. Frozen boundaries supply no mechanical work; a stationary contact load must not be inserted as a persistent local fluid body force. Moving-boundary momentum exchange and contact support remain unresolved.
