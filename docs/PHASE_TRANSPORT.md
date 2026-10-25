# Candidate phase transport contract

This is the gas-fraction transport component, not a completed two-phase fluid solver.
It is not enabled in the production scene. No buoyancy or sand feedback is claimed.

For gas fraction c, the conservative Allen–Cahn transport equation used here is

`dc/dt + div(c u) = div(M (grad(c) - 4 c (1-c) n / W))`,

where n is the normalized phase gradient, W is interface width in cells and M
is mobility. The flat equilibrium profile is a hyperbolic tangent. This follows
the conservative interface-sharpening form investigated in the algorithm review;
it is an independently implemented finite-volume transport discretization, not a
port of CLIP's MRT collision step. The candidate momentum component is described below.

Each positive x/y face stores one transfer. Advection uses donor-cell upwinding;
diffusion uses a face difference; sharpening uses averaged phase fraction and a
face gradient. Solid and exterior faces have zero transfer. Normal gradients at
walls use mirrored center values: this is a neutral boundary approximation, not
a calibrated contact-angle law.

Three GPU passes: (1) face transfer, (2) each cell's incoming/outgoing capacity,
(3) gather limited shared transfers into the next state. A face uses the minimum
of donor gas capacity and receiver empty capacity. No independent cell clipping
or global mass repair is allowed. Limiting can alter physical rates: it is a
numerical safety mechanism, not permission to take arbitrary large time steps.
First-order upwinding adds diffusion; interface width/step refinement must be
checked before claiming quantitative accuracy or correct coalescence timing.

Each invocation owns one output cell/face pair; barriers separate passes;
state buffers alternate between steps. Only test code reads back the GPU result.
The shader reads a per-cell velocity buffer. The isolated transport fixture fills
that buffer uniformly; the coupled fixture obtains it from the momentum shader.

Run `python run.py phase-gpu` to regenerate the CPU fixture and compare 80 steps
on a real Vulkan device. Acceptance: maximum fraction error < 2e-5, absolute
gas-area drift < 1e-4 cells at 24², no solid leakage/nonfinite values, fraction
within [-1e-6, 1+1e-6]. These tolerances apply only to this small transport fixture,
not to a full 256² simulation or long-term conservation requirement.

Next gate: momentum/phase coupling, static-bubble parasitic currents and pressure
jump, then buoyant rise in the main host. Do not extend unrelated test solvers.

## Momentum coupling added 2026-10-24

`src/phase_fluid.gd` owns D2Q9 distribution ping-pong buffers, gas fraction,
velocity and transport workspace. `phase_momentum.glsl` performs pull streaming,
halfway wall bounce-back, BGK collision and Guo forcing, then phase transport uses
its spatial velocity. Lattice dx=dt=1; viscosity=(tau-0.5)/3 with tau=0.9.
Force is `mu grad(c) - c g`, with `mu=2 beta c(1-c)(1-2c)-kappa lap(c)`,
`beta=12 sigma/W`, `kappa=1.5 sigma W`. The free-energy constants match the
chosen flat tanh profile and surface tension in lattice units.

Force discretization reference: [Guo, Zheng, Shi (2002)](https://journals.aps.org/pre/abstract/10.1103/PhysRevE.65.046308).
This is an independent BGK implementation, not CLIP's variable-density MRT solver.
Boussinesq forcing uses a common inertial density and effective buoyancy. It does
not validate air/water density ratios or full multiphase momentum conservation.
This approximation must be revisited before calling the bubble model accepted;
passing CPU/GPU equality is not evidence that the approximation is sufficient.

`python run.py phase-coupled` runs an 80-step CPU/GPU coupled comparison.
Maximum phase error must be <2e-5, velocity error <2e-6, gas drift <1e-4 cells,
with no invalid values or wall penetration. GPU readback is test-only.
CPU physical tests also check a fixed-interface circular pressure jump against
sigma/R (10% tolerance), maximum parasitic speed <2e-5 after 400 steps, fluid
mass conservation, and upward gas centroid displacement under buoyancy after
200 coupled steps. The fixed-interface test does not establish freely evolving
bubble equilibrium, deformation, merging or breakup. Sand feedback and live
main-window integration remain outstanding.

## Interface-normal correction and topology checks (2026-10-24)

The previous face normal replaced its normal component with the raw adjacent-cell
jump. It amplified grid-scale perturbations inside nearly uniform gas. In the
256² main scene, raw-field trough counts (both axes, .6<c<.99, neighbors at least
.02 higher) reached 352 at tick 5000. The renderer was not the source.

The normal now uses the average of centered cell gradients on both sides, and
`n = g / sqrt(dot(g,g) + (0.08/W)^2)`. Diffusion still uses the unmodified face
jump. This suppresses normalization of tiny bulk gradients; it does not blur the
rendered image, clip state, or repair mass. Regularization changes the phase
transport model, especially its tails, and remains a parameter requiring
resolution sensitivity checks. It is not a claim of an exact sharp-interface
solution or a wholesale port of CLIP.

Saved raw before/after fields and `python tests/analyze_phase_quality.py` provide
an auditable same-seed, same-parameter comparison: troughs 139→0 at 2000 ticks,
352→0 at 5000; .1<c<.9 cell counts 1141→1126 and 1242→1110. These band counts
alone do not prove interface-width convergence. A CPU regression checks that
small alternating perturbations in .99 gas decay without losing inventory.

`python run.py phase-topology` evolves four 128² GPU cases for 4000 steps each:
nearby bubbles merge; separated bubbles remain separate; an unforced dumbbell
remains connected; the same dumbbell in a smooth initial extensional flow breaks.
The flow is initialized once through equilibrium LBM distributions derived from
an analytic streamfunction. It is not applied by moving/splitting gas cells.
The analytical field is divergence-free before discretization; discrete sampling
and wall treatment introduce error. No flow forcing or gas reset occurs afterward.

Connectivity is measured at fractions .4/.5/.6. Counts of components >=20 cells
are asserted, with smaller components separately reported rather than hidden.
The stretching case leaves small satellites; a two-large-component result does
not mean exactly two perfectly clean bubbles. All samples enforce finite/bounded
fractions and relative mass drift <1e-4. Raw phase images are diagnostic outputs,
not precomputed content for the application. Film drainage/coalescence timing,
resolution convergence, and sand interaction remain unvalidated.
