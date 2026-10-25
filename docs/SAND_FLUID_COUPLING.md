# Candidate resolved-voxel sand / fluid coupling

Status: geometric coupling and a stationary-link excess-traction estimate are
implemented in the candidate shared application host. The estimate now influences
hop direction/rate. Full moving-boundary force/contact coupling is not accepted.

## State and scheduling

The shared material buffer contains 0 fluid, 1 permanent wall, 2 dark sand,
3 gray sand, 4 cream sand. These IDs are distinct from the legacy engine schema.
All nonzero cells are solid to LBM streaming and gas-fraction transport.
The renderer only reads this buffer. Initialization is owned by PhaseFluid and
uses an explicit seed. Existing application snapshots are neither read nor migrated.

Each fixed tick runs LBM momentum, three phase transport passes, then two shifted
2x2 grain partitions. Each partition invocation reads and writes only its own
block. It must not read evolving neighboring blocks to infer support; local block
support is consequently a coarse approximation. Explicit barriers separate passes.

A grain may exchange with a downhill fluid cell with c<=0.05. Direction choices
use integer gravity projections and seeded tick/partition/block hashes. Diagonal
choices require support visible inside the same block and a slope threshold.
Effective acceptance rates are 12/256, 9/256 and 6/256 for the three minerals.
These are prototype mobility parameters, not measured physical densities or a
Stokes settling model. There is no wall-clock RNG and no reinitialization on rotation.

## Conservative displacement

For accepted grain cell a / fluid cell b, exchange material, gas fraction and
all nine postcollision LBM populations. The displaced fluid packet moves into
the vacated cell. No fluid distribution is rebuilt from equilibrium during a
move. Since gas at a is zero, gas at the new grain cell remains zero.

This preserves each material inventory, gas sum, and the multiset of active-fluid
packets exactly for the displacement operator. LBM collision/transport introduces
floating-point error separately. The voxel move is an underresolved displacement
closure; its local fluid relocation is not an accurate resolved moving-boundary
solution. It must not be described as exact momentum exchange or pressure work.

The coupling is observable in both geometric directions: gas-rich regions restrict
sand motion, and sand changes fluid boundaries and redirects gas/fluid evolution.
However, pressure/drag impulses are not yet fed into sand velocities/contact forces.
The gas threshold behaves as a simplified interface barrier and does not resolve
capillary breakthrough or wetting films. A pressure-driven bubble cannot yet push
a loaded sand bed correctly. These are central remaining physics requirements.

## Geometric baseline evidence (before traction response)

`python run.py phase-grains` compares 180 steps, five gravity directions plus zero,
against the CPU reference. Gas, every LBM population and all material IDs match
byte for byte. CPU tests separately check active-fluid packet conservation and
fixed walls, including mixed gas fractions and nonuniform populations.

`python run.py phase-sand-smoke` runs the actual 256² shared host for 5000 ticks,
including rotation. Counts [fluid,wall,dark,gray,cream] remain
[42352,15652,2395,2591,2546]. No gas occupies solids, no material escapes the
circle, and no nonfinite state is observed at sampled checkpoints. Gas changes
from 2336.90427054 to 2336.90420805. Active-fluid population sum changes from
42352.00031555 to 42352.01915197 (about 4.45e-7 relative); do not call full LBM
fluid mass exactly conserved. At 5000 ticks fluid density ranges .999121–1.002620.
The drift needs longer-run investigation before persistent desktop acceptance.

Sand mean y moves 77.74→110.82 before rotation; after gravity reversal it reaches
55.81. The gas-only scene rises about 8.18 cells by tick 2000, versus about 2.52
with sand. Initial gas inventories differ by less than 2e-7 because the seeded
constructor suppresses tiny tails at initial grain cells. This is an approximate
counterfactual, not proof of calibrated sand load response.

The inspected screenshots show sand routing around bubbles, temporary grain
accumulation above bubbles and later deposition after rotation. Rendering remains
coarse; natural mineral layering and a full quiet settling cycle are not accepted.

On the tested RX 7900 XTX, local-RD one complete tick plus colorize measured p95
.08520 ms at 256² and .09744 ms at 512² (10 warmup, 60 samples). Dedicated buffers
and image are 7/28 MiB. These exclude Canvas, driver allocations, CPU scheduling,
long-run behavior and GPU utilization. They do not guarantee a budget percentage.

## Collision mass closure

The earlier direct BGK evaluation of all nine populations had about 3.94e-5
relative mass drift over the same 5000-tick mixed scene. Guo forcing has zero
mass moment, so the rest population is now computed as incoming local density
minus the eight updated moving populations. This enforces the collision's mass
constraint locally without injecting a global compensation source or altering
moving-population momentum. Floating-point streaming/summation error remains.
The same test now measures about 4.45e-7 drift; the main-host regression threshold
has been tightened to 1e-6. CPU reference, static pressure and coupled GPU tests
must be rerun after this change. This is not a long-duration stability guarantee.

## Stationary-link traction response (2026-10-24)

Before each grain partition, a separate gather pass reads immutable postcollision
populations and the current material map. For a grain, it evaluates
`F = -2 sum_q e_q (f_opp(q)(neighbor) - w_q rho_bar)` over adjacent fluid links.
`rho_bar` is the average density of those neighboring fluid cells. This removes
ambient pressure from partially exposed grains, assigning that background to
unresolved solid contacts. No neighbor writes or atomics are used. A barrier
precedes the subsequent material displacement, and force is recomputed after
that displacement before the next partition.

The stationary bounce-back link-momentum idea is informed by
[Ladd's particulate-suspension work](https://arxiv.org/abs/comp-gas/9306005).
Our local-background subtraction and stochastic hop mapping are additional
approximations, not a reproduction of that suspension solver. In particular,
[moving-boundary force evaluation](https://harvest.aps.org/v2/journals/articles/10.1103/PhysRevE.85.016704/fulltext)
requires treatment of changing-cell impulses and boundary motion; those terms
are not implemented here.

The traction is normalized against reference effective buoyant weights
[2.0,1.7,1.4] times max(|g|,2e-5), then added to the integer gravity drive. Each
response component is capped at four reference drives. Hop probabilities scale
with total drive, capped at four times their original rates. These bounds control
stability/work; they are not experimentally fitted mineral properties, a Newton
integrator or a calibrated Stokes mobility. Near-zero residuals produce zero hop
rate, avoiding uniform-pressure noise-driven motion.

`python run.py grain-traction` compares the estimator to a CPU reference for
uniform pressure, partially exposed uniform pressure, uniform flow, and a linear
pressure gradient. Maximum measured error is 2.224e-8 (tolerance 1e-7). An isolated
grain moves from row6 to row5 at test tick2 despite downward gravity in the
prescribed-pressure fixture. This proves that the pressure signal reaches the
movement rule, not that the fixture is a self-consistent evolving fluid solution.
`phase-grains` now also checks 180 steps under prescribed upward traction against
the CPU reference byte for byte, in addition to the gravity-only fixture.

Current main-window 5000-tick checks pass: unchanged material counts, gas
2336.90428025, active-fluid mass42351.98866039 versus42352.00031555 initially
(relative drift about2.75e-7), and density .997624–1.001645. Sand mean row at5000
is58.56. Inspected images show changed release/deposition and local grains along
bubble edges; that accumulation is not yet accepted as physical wetting/adhesion.

Current measured p95 tick+colorize is .09972/.11404 ms at256/512, with7.5/30MiB
of dedicated state/work/output storage; same benchmark exclusions apply.

Remaining critical gap: stationary sand weight is not propagated through a
contact network into fluid pressure. A fully static load is therefore not
transmitted correctly to the bubble. Stationary-wall traction influencing hops
must not be called complete reciprocal momentum exchange, moving-wall drag, or
validated sand-bed loading. Resolve and test that gap before claiming full
sand/bubble physical interaction or promoting this candidate to the saved app.

## Latest load-routing candidate

A directed scalar load-transfer closure now supplies a fluid force source; see
[GRAIN_LOAD_MODEL.md](GRAIN_LOAD_MODEL.md). This supersedes the statement that no
load path exists, but does not establish frictional static equilibrium, moving-wall
momentum exchange or correct mechanical work. Earlier benchmark values above are
historical; the new load sweep is materially more expensive.

## Fixed-boundary impulse ledger and next coupling contract

The scalar load closure above was subsequently rejected by the static-work gate;
its default factor is zero. See GRAIN_LOAD_MODEL.md and phase-static-work.json.

`grain_traction.glsl` mode 1 returns the *raw* stationary bounce-back impulse
`J_s = -2 sum_q e_q f_opp(q)(fluid_neighbor)` on every solid voxel, including walls.
Sample it from the populations BEFORE the matching fluid streaming/collision.
Mode 0 remains the legacy pressure-subtracted hop heuristic. The modes are not
interchangeable. Tests use explicit mode 1 and a frozen geometry, zero body force,
and zero gas, verifying `delta P_fluid + sum J_grain + sum J_wall = 0`.
The wall/support reaction belongs to an external fixed support in this test.

The candidate does not yet possess grain velocity, angular velocity, persistent
particle IDs or subcell positions. Material classes alone do not supply these.
Stochastic swaps preserve population inventories but are not a moving-boundary
integrator. Do not claim full reciprocity by assigning the measured impulse to a
hop probability. Do not add the raw pressure term to the hop drive: partially
exposed particles require contact reactions, which are currently absent.

Required next integration contract:
1. Physics owns persistent particle identity, position, velocity and mass, with
   a spatial occupancy/contact mapping. State restoration must include them.
2. Accumulate hydrodynamic impulses and body forces separately from contact and
   fixed-wall reactions. Include torque if resolved finite-size grains are used.
3. Solve admissible contact motion, then handle moving-wall reflection and cells
   covered/uncovered by that motion without inventing mass or momentum.
4. Validate closed-system momentum, static support/no work, driven-boundary work,
   and single-grain settling before enabling it in the main candidate.
5. Retain seeded material inventory, bounded GPU scheduling and current render
   interfaces. Never silently convert an old saved material grid into a new
   particle phase-space state.

These are unimplemented requirements, not a completed model. The new raw mode is
only the verified fixed-geometry impulse primitive needed by that integration.

## Prescribed tangential wall motion (2026-10-24)

The existing momentum kernel now accepts a Physics-owned boundary velocity field,
with a disabled-by-default push flag. For incoming link direction e from solid to
fluid, halfway reflection uses `f_in = f_out + 6 w rho_local dot(e,u_wall)`.
The matching raw boundary impulse is `J = -e (2 f_out + correction)` (traction
mode 2). Both operators use the same pre-stream fluid density. Mode 1 is still
stationary raw impulse and mode 0 is the legacy excess-pressure heuristic.

This is the standard moving-wall bounce-back correction, independently written;
see the primary discussion of its limitations in
[Yin and Zhang, PRE 85, 016704](https://doi.org/10.1103/PhysRevE.85.016704).
No reference source code was copied. Exact lattice momentum accounting does not
establish Galilean invariance, curved-wall accuracy or correct changing-cell forces.

`moving-boundary` verifies CPU/GPU populations, reaction impulse, positive work,
wall-velocity reversal, and decay after stopping a tangentially driven lid. The
geometry remains fixed. Positive accumulated wall work exceeds final kinetic
energy in the test; this is a necessary budget check, not a full discrete viscous
energy identity. Mass is measured independently rather than globally repaired.

Initialization validates finite bounded velocities and zero velocity on fluid
cells. Nonzero prescribed boundary motion plus stochastic grain motion is rejected
before allocating resources; advance also asserts this combination is absent.
This prevents using the new primitive as if translating voxel geometry were already
implemented. Product particles still lack their own integrated velocity/contact
state. Changing occupancy requires additional impulses and population reconstruction.
The new field adds 8 bytes/cell (0.5/2 MiB at256/512). Any future candidate snapshot
schema must include nonzero boundary motion or reconstruct it from saved physical
body state; candidate snapshot migration is still unimplemented.

## Gravity magnitude consistency (2026-10-24)

The normalized direction sent to the grain kernel now carries a separate actual
acceleration magnitude (including zero). Body drive scales with |g|/2e-5, capped
at4. Traction is divided by relative_weight*2e-5 rather than relative_weight*|g|,
so lowering gravity no longer inflates the same hydrodynamic input. The legacy
sliding threshold scales with gravity magnitude as an effective normal-load term.
This remains a stochastic voxel mobility, not an inertial force integrator or a
validated Coulomb contact law. The 8-bit acceptance rate rounds weak forces and
limits strong ones; the linear-response evidence only covers 0.5x/1x/2x in the
free-settling test. No claim is made near zero, saturation or dense contact.

Six actual GPU fixtures match the updated CPU model exactly, including zero-g
traction transport. The default interactive acceleration remains2e-5 and snapshot
configuration validation still enforces it. The measured default5000-tick phase
hash and metrics match the pre-change artifacts. This fixes a magnitude-interface
inconsistency but does not calibrate bubble-to-grain speed or physical units.

## Effective drag and compensated rest population (2026-10-24)

`grain_drag_divisor` takes1/16/64/256. The original integer mobility is divided
using a16-bit acceptance threshold. Rearranging random bytes preserves the exact
old accept/reject decision at divisor1. It does not eliminate the original
force-to-integer mobility quantization near zero or establish physical units.
It changes future dynamics only; no cell reset or reseed occurs. The parameter is
saved, and old snapshots without it retain divisor1.

Long slow-grain runs revealed systematic FP32 mass drift despite a rest-population
closure. Pairwise grouping and balancing small collision increments alone did not
meet the existing1e-6 gate. The final kernel carries the rest-population rounding
residual per cell. With `delta = old_residual + sum(pulled[q]-post[q], q=1..8)`,
`rest = round(pulled[0]+delta)` and `residual = (pulled[0]-rest)+delta`.
GLSL precise qualifiers preserve this arithmetic. Each invocation owns its residual;
solid cells retain it, and disjoint grain swaps transport it with the fluid packet.
No global inventory correction, GPU readback or added pass is used.

The residual is persistent numerical state, not decorative data. Snapshot payloads
append4n² bytes and set mass_compensation=true; readers validate finite bounded
residuals. Legacy52-byte/cell payloads retain all original fields and start the new
residual at zero. Restored new snapshots preserve it exactly. Raw population mass
remains the regression metric; it is not replaced by a compensated total to pass.
The slow-grain50k test maximum raw relative drift fell from2.952e-6 to9.306e-11.
This is a tested precision improvement, not exact arithmetic or long-term proof.

The tested64x resistance yields very slow release and remains experimental. It
must not become the default merely because it has more plausible relative speeds.
Physical contacts, hydrodynamic reaction and useful temporal pacing remain open.

## Contact-state impulse ledger and first-moment closure (2026-10-24)

`phase-contact-ledger` forks four evolved test snapshots, fixes their geometry for
one fluid step, and samples raw boundary impulse BEFORE streaming. Independent
Python code verifies every output population and boundary impulse, then checks
`P_next - P_old + J_wall + J_grain - F_capillary - F_buoyancy = 0`.
It includes the nonzero summed capillary force near solid boundaries rather than
assuming that sum vanishes. This is a ledger of the implemented operators, not
proof that their wetting/contact conditions are physically complete.

The original momentum operator failed two cases at the existing 2e-5 tolerance:
maximum residual norm 2.6741e-5. Independent FP32 rounding of collision terms
introduced a bias in weak net force. After evaluating collision, the kernel now
reconstructs f1 and f2 from target momentum `sum(pulled_q e_q) + force`, retaining
the other moving populations. The existing compensated f0 closure then balances
mass using these final values. No global correction, clipping, new state, pass,
or readback is introduced. This is algebraically the same BGK/Guo first moment;
rounding and subsequent trajectories can differ. It is not an exact FP32 identity.

On the SAME input states, all four cases pass; maximum norm 4.368e-7, population
error against double reference 1.361e-7, impulse error 3.353e-8. Original failure
is preserved in phase-contact-ledger-before-momentum-closure.json; test inputs are
archived in contact-ledger-baseline.zip. Current reports include input hashes.

Raw link impulses are already transferred to fluid by bounce-back. Adding another
opposite force to fluid would double count. The gauge-subtracted post-step hop
estimator is not interchangeable with this raw ledger: partial-contact ambient
pressure and contact reactions must be handled together. The next mechanics
implementation must reconcile grain motion, contact impulses and interface work,
including changing occupied cells. See [moving-particle refill research](https://www.sciencedirect.com/science/article/pii/S0045793016301116)
for the general issue; this numerical closure is independently derived and does
not implement that paper's moving-particle method.

## Traction sampling order (2026-10-24)

The grain hop estimator is now sampled once from incoming populations and
geometry BEFORE the matching fluid step. Its vector is exchanged with material
through both disjoint grain partitions, instead of resampling after collision
and again on geometry changed by the first grain partition. This removes one
dispatch per tick. The field is derived, recomputed before grain use following
restoration, and does not increase the snapshot payload.

This remains gauge-subtracted stochastic mobility, not integration of raw
boundary impulse into grain momentum. Contact reactions and interface work are
still missing; lower-edge trapping persists in the loaded scene. Further work
must address those mechanics rather than tune probabilities to fit an image.

## Local grain contact impulse primitive (2026-10-24)

The existing Physics component now exposes `record_grain_contact_impulses`.
It queues bounded sweeps on `boundary_velocity` as translational grain velocity,
and writes a separate reaction buffer. It does NOT advance positions or tick,
integrate gravity/hydrodynamic force, or certify global contact convergence.
The normal stochastic mover must be disabled; mixing both paths is rejected.
The normal app does not call it. Resources are allocated lazily, so there is no
added default-window memory or dispatch cost.

For a face joining a to b, n points a-to-b. With closing velocity
`s=(v_a-v_b).n>0`, the zero-restitution impulse is
`j_n=s/(1/m_a+1/m_b)`. Tangential impulse is projected into
`[-mu*j_n,+mu*j_n]`. Grains receive opposite impulses; prescribed walls retain
their velocity and record the balancing impulse. Separating pairs receive none.
Effective inertial masses are 3/2.7/2.4 (unit displaced-liquid mass plus the
existing buoyant weights), an uncalibrated model choice. Four edge colors give
each updated velocity/reaction a unique writer; dispatch barriers separate them.
This models translational voxel-face impacts, not grain spin or diagonal contact.

Twenty real GPU cases cover horizontal/vertical pair impacts, separation,
stationary/moving walls, friction and a five-grain chain; the 9-square chain also
checks a partial final workgroup. Maximum CPU/GPU velocity error6.623e-10,
impulse error1.389e-8, and momentum residual1.546e-8. Kinetic energy never exceeds
initial kinetic energy plus prescribed wall work within the tested tolerance.
Material, gas, populations and mass-correction state remain unchanged.

The five-grain chain still closes at up to7.276e-4 cells/tick after32 sweeps.
That is explicitly NOT a converged global contact solve or permission to advance
positions. Before integrating this path into the host, add a convergence/commit
gate, continuous grain displacement, and matching fluid/interface work. Nonzero
body velocities remain unsupported by interactive snapshot validation. No claim
is made for large dense networks or complete bubble support.

## Transactional normal-contact gate (2026-10-24)

The impulse primitive now copies live velocity into scratch, performs at most
128 sweeps, and reduces maximum positive face-closing speed plus invalid-data
flags on the GPU. Only a finite candidate with closing speed<=1e-7 cells/tick
is published. Failed candidates preserve every live physical byte and publish
zero reaction. Four edge colors and dispatch barriers are unchanged; reduction
uses integer atomics on nonnegative float bit patterns, without float atomic sums.
The boolean method return means submission validity, not physical acceptance;
`contact_status[2]` is the GPU acceptance flag. Callers must distinguish them.

The five-grain fixtures are rejected after32 sweeps (closing speed7.276e-4) and
accepted after128 (maximum6.043e-8), with CPU/GPU recovery velocity error2.236e-10.
Tests cover retry from unchanged state, success followed by an insufficient-budget
retry, stale-status/reaction prevention, a NaN input, and the128-sweep bound.
Default rendering still performs no readback and does not enable this path.

This is a finite/nonpenetrating-velocity gate on current voxel faces, NOT a full
frictional-complementarity convergence proof, positional collision check, or a
joint fluid/grain timestep. Continuous displacement and a common commit decision
with fluid/interface work are still required. Scratch and published reactions are
derived; optional allocations total24 bytes/cell plus16 status bytes, allocated
only when this primitive is requested. Dense-network convergence/performance and
interactive snapshots with moving grains remain unverified.

## Continuous kinematic displacement (not enabled in the host)

`PhaseFluid.record_grain_displacement(dt)` records four bounded GPU passes: clear claims, predict/validate, gather conservative packets, and commit. It integrates persistent subcell offsets using prescribed grain velocity. Target-cell claims use integer compare-and-swap; collision checks use swept unit boxes over a 5x5 neighborhood with 1e-6 cell overlap tolerance. Each component of displacement is bounded by 0.25 cell per call. Fixed walls must have zero velocity in this path.

A chain of grains moving into liquid transfers the terminal liquid packet to the vacated head. Material, phase, all nine populations, and mass compensation move without conversion; velocity and offset follow the grain. Traversal is capped at 32 links and rejects the entire candidate if exceeded. Cyclic permutations have no vacant head. All live writes occur after validation barriers; rejected candidates leave live state unchanged. No tick or physical time is advanced by this kinematic operation.

This is not yet a coupled fluid step: it supplies neither gravity integration nor covered/uncovered-cell work, and does not resolve collisions itself. The contact operator now subtracts the available normal gap divided by dt from closing speed. record_grain_contact_motion solves into scratch, validates displacement, then publishes both velocity and position only if both checks pass. Published reactions describe the pre-move contact geometry and are zero on rejection. Joint acceptance is displacement_status[1]; deferred contact status is not a commit flag. Fluid advance remains blocked after displacement allocation: covered/uncovered-cell work and common fluid/particle acceptance are still missing. Default host behavior is unchanged.

Explicit snapshots include the offset buffer (64 bytes/cell); production session validation and restore reject this experimental layout rather than silently losing positions. No user sessions are migrated. Optional allocation costs 80 bytes/cell plus 8 bytes status; no allocations occur in the default window. Large dense-scene performance is not yet measured.

Validation is included in `python run.py grain-contact-impulse`: an independent all-pairs CPU reference checks translation, chain remapping, vertical/diagonal motion, wall/corner collisions, escape, and traversal-budget rejection. GPU comparison uses unique fluid-packet values so conservation cannot pass merely because all liquid cells initially look identical.


### Joint contact and displacement verification

The same GPU check now includes a grain traversing a 0.125-cell gap before stopping at a fixed wall, a moving contact chain, and a corner collision that rejects a step after contact has already changed candidate velocities. Twelve accepted steps match the independent CPU reference for each of the first two cases; the third preserves every live byte and publishes zero contact impulse. This validates the velocity/position transaction, not bubble support. Gravity and raw fluid impulses now enter candidate velocity through the optional predictor described below; fluid-state commitment is still separate. Diagonal contacts are detected by the swept-box rejection gate but not resolved by the face solver, so dense scenes can stall; this remains a known restriction.

### Raw fluid impulse and effective weight prediction

`record_grain_contact_motion(..., gravity, use_fluid_impulse=true)` samples the raw incoming bounce-back impulse on the current geometry, including ambient pressure and moving-boundary correction. It predicts grain velocity as `v + J_fluid / mass + (mass-1) * gravity * dt / mass`, then uses the existing contact/position joint gate. Mass is 3, 2.7, or 2.4 in reference-liquid units. Effective weight follows the current Boussinesq convention, whose reference hydrostatic pressure was removed; this is not an independently validated full-density water model. Raw bounce-back impulse is NOT added again to the fluid.

Fluid impulse sampling requires dt=1 because it represents one lattice streaming step. Gravity-only prediction accepts the existing bounded dt. Moving correction is explicitly requested even when the grain started at rest, because its current velocity can differ from initialization. Nonfinite gravity or magnitude above .01 is rejected at the API boundary, not clamped.

This call still does not advance fluid distributions or the simulation tick. Tests use a separate same-input fluid branch to compare CPU/GPU populations and total fluid+grain+wall momentum. Three cases cover drag, wall support under gravity, and oblique gravity. Joint fluid-state acceptance, interface work during occupancy changes, and dense contact resolution remain necessary before this path can replace the host update. Repeating this predictor against unchanged fluid is not a physical time integrator.

### Joint fluid-state transaction

`record_coupled_step(gravity, sigma, sweeps, friction)` now stages momentum collision, phase transport, and mass-compensation state in separate GPU buffers. Grain impulses are sampled from the same pre-step geometry and populations. Contact/position validation gathers staged fluid packets and grain state into the existing remap scratch. Only the final commit changes live phase, populations, materials, compensation, grain velocity and offset. Rejection leaves all those fields untouched. Candidate populations must be finite and nonnegative; phase must remain finite in [0,1].

The CPU `tick` is a fixed storage-parity anchor in this experimental path. `coupled_clock[0]` counts accepted lattice steps on the GPU; rejection does not increment it. Full diagnostic snapshots append that counter, and production saves still reject the experimental layout. The host is not switched over until its scheduling/session interface handles the accepted clock and physical validation passes. No per-step CPU readback is introduced by the operator.

Additional fluid staging costs 68 bytes/cell plus the 4-byte clock, allocated only on first use. The existing sweeps/step limits remain; no automatic retry loop. This is a joint transaction, not an energy-consistent moving-interface proof: covered-cell work and moving-boundary fluid mass under dense normal motion remain to be checked.

GPU validation covers 12 accepted steps each of settling, a cell crossing, and phase-field transport; maximum CPU difference is 2.017e-7. A corner collision rejects both fluid and grains, including the accepted clock. The actual 128-square/1280-grain heavy-bed initializer rejects its first step after 128 contact sweeps: closing residual 9.143e-4 versus 1e-7 threshold. State stays unchanged. This is a known physical-progress failure, not a passing heavy-bed simulation. The next priority is resolving dense contact support within the resource budget; do not loosen the rejection threshold to hide overlap or enable this path as the default artwork.

### Projected accumulated-contact iteration

An optional `relaxation` argument enables accumulated normal/tangent impulses in the existing colored-edge kernel. Each update projects total normal impulse to nonnegative values and total tangential impulse to its Coulomb interval, then applies only the change. This allows earlier over-corrections to be released. The final eight scans use relaxation 1 to damp oscillatory modes; the total cap remains 128. Default relaxation 0 preserves the comparison implementation and host defaults.

The general projected-SOR approach was checked against [Project Chrono's PSOR documentation](https://api.projectchrono.org/classchrono_1_1_ch_solver_p_s_o_r.html). No source was copied. This implementation is specific to the current voxel face constraints and is not a replacement for diagonal or rotating-grain contact geometry.

Acceptance now checks a projected fixed-point residual for normal complementarity and tangential friction in addition to positive closing speed. The equivalent residual is evaluated without subtracting two rounded pressure-scale impulse totals to recover a very small correction. The 1e-7 velocity gate is unchanged. Edge accumulators cost 16 bytes/cell, allocated with the optional contact path and reset for each solve; they are solver scratch, not persistent physical state.

Forty CPU/GPU comparisons pass, including reaction balance, kinetic energy versus prescribed-wall work, separation and both axes. The actual heavy bed with relaxation 1.9 accepts 155 steps, then rejects at residual 1.0124e-7. Materials and closed walls remain intact; failed continuation preserves the full physical snapshot and zeroes published reactions. Mean grain offset is 0.02550 cell downward; no material cell has changed, so this is not yet visible release or accepted bubble support. The first 128-square joint step measured about 1.61 ms GPU on RX7900XTX (single sample, not a percentile or full-window utilization).

Increasing the scan budget to 256 did not resolve the stopping condition and roughly doubled cost; it was reverted. Reconstructing velocities periodically from total edge impulses also did not improve the dense trajectory and was reverted. Evidence is retained in reports/projected-contact-reconstruction-trial.json and its shader snapshot. The next unresolved issue is pressure-scale impulse accumulation versus weak grain-motion precision, not permission to loosen the nonpenetration gate.

### Compensated contact totals and local-gap collision arithmetic

Projected contact totals now retain a high/low float pair for both normal and tangential impulses. Error-free sum decomposition keeps small increments below the main impulse's ULP; friction bounds use the same paired representation and an explicit FMA product remainder. Only the change is applied to the two bodies. The low buffers are reset solver scratch (another 16 bytes/cell on the optional contact path), not new physical state. No float64 device requirement, extra scan, or relaxed acceptance threshold was introduced.

The heavy-bed trajectory extended from 155 to 1098 accepted steps, where displacement rejection occurred despite contact residual 1.256e-8. Independent analysis found no overlap beyond tolerance in double precision but two false positives when emulating the old float32 expression `(integer_distance + offset_b) - offset_a`. The swept-box test now cancels integer grid distances first and computes lower/upper clearance directly from the small offset difference. A near-corner clearance and a genuine overlap fixture distinguish acceptance from rejection at unchanged 1e-6 geometric tolerance.

The resulting trajectory reaches 1179 accepted steps, mean vertical subcell offset 0.12423, no material-cell transfers. At step 1180 a genuine diagonal contact is confirmed by independent high-precision analysis (cells 1860 and 1989, contact during approximately the last 90% of the step). The current face-only solver cannot resolve it; rejection is correct and preserves the whole state. This now identifies a geometry-model limitation rather than the earlier contact-accumulation floor. Adding diagonal contact response is the next core task; no claim of successful bubble support or sand release is made.

Forty projected GPU/CPU cases still pass (max velocity/reaction difference 1.238e-7), as do the existing joint-fluid and near-corner checks. Failure evidence is in coupled-heavy-rejected.state/.candidate and coupled-heavy-rejected-analysis.json; the earlier float32 false-positive reconstruction remains in coupled-heavy-rejected-float32.json. The former failures and new actual contact must not be conflated.

### Optional diagonal box-contact response

The contact kernel now supports the two forward diagonal neighbor families in addition to horizontal/vertical faces. Each family uses two x-parity colors with disjoint endpoints; explicit barriers separate colors. A separating box axis is frozen per activated corner contact, with a free-motion tie-break on exact corner ties. Existing compensated normal/tangent impulse projection and equal/opposite reactions then apply on that axis. This is axis-aligned unit-box contact, not circular mineral grains or grain rotation.

Activating every diagonal at initialization worsened dense convergence and was rejected. Activating corners before the face solution finished also perturbed otherwise valid trajectories. The retained opt-in path completes up to 128 face scans, identifies diagonal pairs whose swept offsets would cross the existing geometric tolerance, then records at most 64 additional correction scans. Without an active corner, these extra kernels skip their update bodies; command/barrier overhead still exists. This is an explicit increase in the maximum solve budget to 192 scans, not unchanged 128-scan performance. The default host does not enable it.

Residual, displacement, material-count and full-state rejection gates remain in force. The separating axes are solver scratch, recomputed each step; they cannot reset particle positions. Scratch adds two more directional edge families (32 bytes/cell high+low totals) and 8 bytes/cell axis choices. No float64 feature or per-frame full-grid readback is required by the runtime operation.

Sixteen new CPU/GPU cases cover both diagonal directions, both separating axes, grain/grain versus grain/wall, and zero/nonzero friction. Independent swept-box checks verify their resolved trajectories, with momentum and dissipation checks. One test fixture initially put a nonzero offset on a fixed wall and correctly failed the motion validator; it was corrected by assigning the relative offset to the movable grain, keeping the wall fixed. This was a fixture correction, not a relaxed collision rule.

### Moving-boundary mass closure and latest heavy-bed result

The extended test exposed fluid mass drift even in the face-only predecessor: relative drift 1.416e-6 after 1179 steps and 5.740e-6 after 8962 diagonal-enabled steps, exceeding the new 1e-6 integrity check. The moving bounce-back correction changed both momentum and the population sum while the represented fluid occupancy stayed fixed within that lattice step.

The momentum kernel now removes the actual added population sum from the zero-velocity population, preserving boundary momentum exchange. Subtraction roundoff joins the existing mass remainder rather than disappearing. The independent CPU model uses the same fixed-volume mass contract. This closes mass in the represented lattice/remapping model; it does not establish exact interface work for continuously moving subcell geometry.

After the fix, the heavy bed accepts 1431 steps with actual conservative grid transfers: 1440 material cells differ from initialization, all 1280 grain identities/counts remain valid, and the grain center moves from y=23.5 to y=27.08970 (3.58970 cells downward). Reported relative fluid-mass drift is 0 at the diagnostic's numeric precision, and gas drift is 3.731e-5. The next step is rejected at contact residual 1.00175e-7; the complete state and clock remain unchanged. This is progress to repeated cell transfers, not sustained release or bubble-support acceptance. The negative mean subcell offset after remapping must not be mistaken for upward physical motion.

Latest validation: 186 CPU tests; 56 projected/contact GPU comparisons; joint-state, moving-boundary, phase-fluid and old-host regression checks pass. The long-trajectory integrity command now exits successfully while explicitly reporting physical acceptance as not established. Baseline failure evidence is retained in grain-coupled-before-wall-mass-closure.json. The host still uses its existing path; enabling the candidate before the remaining contact/energy/appearance gates would misrepresent product readiness.
# 2026-10-25: optional paired interface stress in the existing coupled path

`PhaseFluid.interface_stress_enabled` selects a finite-volume interface stress
before the first coupled transaction (default false). It adds one 8-byte/cell
force buffer and one dispatch/barrier per coupled step. Default application
paths allocate no additional force buffer. Existing unused descriptor slots
alias the velocity buffer and are not read when the mode is disabled.

For bulk free energy `f(c)=beta*c^2*(1-c)^2`, the implemented tensor is
`K=(f+kappa*|grad(c)|^2/2)I-kappa*grad(c) outer grad(c)`.
In the continuum `div(K)=mu*grad(c)`, matching the existing pressure convention.
The discrete operator uses shared face tractions, so each fluid-fluid or
fluid-solid face contributes equal/opposite force. A solid-fluid face uses the
fluid-side phase value and tangential gradient (neutral/90-degree approximation).
This is not calibrated mineral wetting or a resolved liquid-film model.

Fluid-side force replaces, rather than supplements, the original capillary
body force in the staged LBM update. Solid-side force is added to the same
pre-step bounce-back impulse used by the grain predictor. Both sample the old
geometry and phase. Existing atomic state acceptance and the gas-entry veto
remain; remap locality and moving-interface energy are still unresolved.

The implementation is an original discretization informed by the distinction
between body-force and stress-divergence coupling in the Ludwig documentation:
https://ludwig.epcc.ed.ac.uk/inputs/force.html . No external source code was copied.
Its explicit warning about spurious currents applies here; continuum equivalence
does not imply identical discrete equilibrium.

Validation: 3 coupled single-step GPU cases match CPU face-paired forces,
fluid populations and grain velocities (maximum errors 4.60e-10, 4.32e-8,
6.29e-11 respectively); maximum net capillary force 3.47e-9. The same heavy bed
accepts 1688 steps then hits gas-entry rejection 32. Counts remain
426/427/427; this does not improve the product gate or justify enabling by default.
CPU fixed-phase radius-4 bubble after 400 steps has Laplace-pressure error 3.13%,
but maximum parasitic speed 5.30e-5 exceeds the old baseline test's 2e-5 gate.
Keep the new option experimental until boundary work, transport locality and
static-current behavior are addressed. Do not describe this as solved support.

Evidence: `interface-stress.json`, `interface-stress-heavy.state`,
`interface-stress-laplace.json`, and `interface-stress-validation.log` in reports.


## 2026-10-25: consistent cubic grain wetting boundary (experimental)

The optional interface-stress path now accepts `grain_wetting_cosine` in
[-0.95, 0.95], default zero. Nonzero values require interface stress enabled.
It controls grain surface energy, not an upward body-force multiplier. Permanent
container walls remain neutral. This option does not alter normal app behavior.

Using gas fraction c and normal from fluid into solid, define
`h(c)=sigma*cosine*(3*c^2-2*c^3)`. Its natural condition is
`kappa*dc/dn + h'(c)=0`. For a halfway boundary, the face value cb solves
`cb + (2*cosine/width)*cb*(1-cb) = c_fluid`.
The shader uses the cancellation-resistant quadratic root
`cb=2*c_fluid/(1+a+sqrt((1+a)^2-4*a*c_fluid))`, a=2*cosine/width.
The CPU reference instead brackets the root with 52 bisections.
The virtual solid sample is `2*cb-c_fluid`; it is not stored as physical gas.

Both phase-transport gradients and interface-stress gradients use this boundary
value. Solid-fluid face stress uses cb and the corresponding normal derivative.
Shared-face reaction remains equal/opposite; boundary-normal phase flux remains
zero. No gas is created inside a grain. Positive cosine lowers gas fraction at
the grain surface and therefore represents preference for liquid in this sign
convention. The paper below uses its own order parameter/normal conventions;
we derived the sign from h rather than copying it mechanically.

Background: Sugimoto et al., Entropy 24(2), 219 (2022), equations 26-28,
https://pmc.ncbi.nlm.nih.gov/articles/PMC8870962/ . This provides the cubic
boundary-condition method, not calibration of single-cell mineral grains.
No source code was copied. Neither equilibrium apparent contact angle nor
moving-boundary energy conservation is established by this implementation.

Five single-step coupled GPU cases cover neutral and +/-0.5 coefficients,
including force, fluid populations, phase transport and grain velocity against
CPU references. Maximum errors are 1.18e-9 (force), 8.40e-8 (populations),
6.71e-8 (phase), and 3.55e-10 (grain velocity). CPU checks verify the surface
energy derivative condition, pure phases, inventory, bounds and 90-degree
rotation covariance. The full 193-test CPU suite passed, along with existing
GPU contact checks, 80-step fluid and 5000-step old host regression.

Crucially, the heavy-bed comparison is NOT a successful support result:
neutral accepts 1688 steps; cosine=0.5 accepts 1689; both stop at gas-entry
rejection 32. Material counts remain 426/427/427. A one-step extension is not
meaningful product progress. Do not tune this coefficient to bypass the failure.
The next structural task is local displaced-fluid transport and subcell moving
geometry; whole-packet chain relocation and the gas veto remain unresolved.
The previous neutral-stress parasitic-current failure remains open as well.
Evidence: reports/interface-stress.json, interface-stress-heavy-wetting.state,
wetting-boundary-validation.log, cpu-wetting-boundary.log and wetting-*.log.

## 2026-10-25: local swept-volume geometry in the coupled transaction

The experimental `local_displacement_geometry_enabled` option adds a geometry
pass after candidate contact velocities are computed. `grain_volume_flux.glsl`
reads the SAME material, subcell offsets and candidate velocities used by the
existing joint step. Each invocation owns one output cell; no atomics distribute
volume. A barrier precedes consumers. Over-capacity/invalid geometry marks the
existing contact rejection ledger, never clips particles or changes their IDs.
The default application does not allocate this 16-byte/cell buffer.

Output is `(old_fluid_capacity, new_fluid_capacity, solid_flux_x, solid_flux_y)`.
Unit boxes match the current contact model; they are not reinterpreted as disks.
Rectangle overlaps give exact endpoint areas. Swept solid face flux averages
x-then-y and y-then-x coordinate paths, adapting the already existing construction
in `experiments/deposition/disk_volume.py`. These paths are a finite-volume
construction, not a claimed physical trajectory. With dx=dt=1, every cell obeys
`new_capacity-old_capacity = div(solid_flux)` within floating-point error.
No particle or fluid packet is moved by this pass.

For a packed 20-grain column moving 0.02 cells, the top capacity increases by
0.02 and the bottom decreases by 0.02; interior cells remain full of solid.
The previous packet remap would transport one fluid packet across 20 cells at
an occupancy crossing. The new volume representation requires local face fluxes
and does not perform that packet transfer. It does NOT yet prevent the old remap
from doing so later: this is derived geometry awaiting a fluid-transport consumer.

Next coupling contract: fluid volume flux must satisfy
`div(fluid_flux) = -div(solid_flux)` while respecting impermeable faces. Gas must
be stored/transported as volume bounded by the changing fluid capacity. Merely
feeding solid flux into the current full-cell phase fraction solver would be
incorrect; it would permit fluid through packed interiors or violate capacity.
The existing LBM full-cell occupancy and whole-packet remap therefore remain
unreplaced. Bubble support and release are still unaccepted.

CPU reference assembles rectangle areas then cumulative coordinate-path fluxes;
GPU computes bounded 3x3 local overlap contributions directly. Tests cover eight
motion angles, a 20-grain chain and a wall-overlap rejection. GPU/CPU maximum error
6.25e-8, local continuity residual 4.15e-8; chain residual is zero. Full physical
snapshot bytes stay unchanged by the geometry pass. Coupled force fixtures also
compare its output against candidate grain velocities from the same step.
Evidence: `reports/grain-volume.json`, `grain-volume-validation.log`,
`interface-stress.json`, and `cpu-grain-volume.log`.

## 2026-10-25: candidate local drainage respects closed grain faces

The existing swept-volume pass now also computes mean endpoint fluid-face
apertures. It unions blocked face intervals rather than summing them: touching
boxes can cover the same face twice, but that must not create negative openings.
The CPU oracle integrates segment coverage independently. The geometry option
now allocates 24 bytes/cell (previously 16); default runtime still does not use it.

`PhaseFluid.record_local_drainage()` constructs an aperture-weighted pressure
projection of the candidate solid volume flux. For face i->j,
`q_liquid = aperture * (p_i-p_j)`, and the pressure equation requires
`div(q_liquid) = -div(q_solid)`. This is a unit-coefficient volume projection,
not a calibrated liquid viscosity or a replacement LBM momentum model.
Zero aperture gives exactly zero liquid flux. The CPU comparison reuses
`experiments/liquid/model.py`'s existing CG projection, in lattice units.

GPU uses Jacobi-preconditioned CG with local workgroup reductions and a bounded
GPU-only global reduction. There is no normal CPU readback, float atomic scatter,
or unbounded retry. At most 128 iterations are submitted. A recursive residual
is not sufficient: convergence is checked using the actual pressure operator;
if necessary the search restarts within the SAME iteration budget. A final
true-residual/finite-value/geometry check controls acceptance and propagates
failure to the existing joint contact-invalid ledger. All pressure and face
fluxes remain scratch candidates, not physical state.

An initial run exposed the reason for true-residual checking: the 20-grain
column's recurrence stopped after 118 iterations, but actual residual was
1.0803e-7, above the unchanged 1e-7 test gate. In-budget residual refresh yields
119 actual CG updates and 7.3225e-8 residual. Eight angle cases converge in
25-36 updates. All valid cases match CPU face flux within 8.11e-8 and have
exactly zero flux on closed faces. Wall overlap is rejected. The full CPU suite
passes 197 tests. See `grain-volume.json`, `local-drainage-validation.log`,
`local-drainage-before-residual-refresh.json`, and `cpu-local-drainage.log`.

Still missing: gas-volume advection under changing capacity, consistent pressure
reaction/work on grains, replacement of the old packet remap, actual-host visual
validation, and large-grid timing. Do not call the new face flux an implemented
bubble or enable it as a physical updater. It is the local drainage candidate
needed to remove the nonlocal packet transport. Endpoint-averaged apertures are
an approximation of the moving face over time, not an exact swept open geometry.

## 2026-10-25: gas-volume advection on local drainage candidates

`record_gas_transport(input_gas, iterations=64, dt=1, tolerance=1e-7)` consumes
an explicitly supplied gas-VOLUME buffer and the existing volume/drainage
candidates. It does not reinterpret the legacy phase buffer, migrate a saved
world, or write physical materials, populations, positions or phase. Its stable
input RID belongs to the owning RD. Gas output/status remain candidates.
All iterations and reductions stay on GPU; iteration count is bounded by 128.

Let old capacity be V0, new geometric capacity V1, incoming flux volumes a_ji,
and old gas volume G0. Implicit upwind fractions solve the convex equation
`(V0 + sum incoming a) * C_i = G0_i + sum incoming a_ji*C_j`.
In exact volume continuity, its diagonal equals `V1 + sum outgoing a`.
Using the incoming-volume ledger avoids creating out-of-range fractions from
pressure roundoff. An increment formulation with FMA avoids cancellation of
small transfers against O(1) capacities. Candidate gas is `G1=V1*C`; there is
no per-cell clipping, global gas rescaling or injection into solids.
The independent CPU oracle uses alternating Gauss-Seidel on `V1+outgoing`.

Acceptance retains three separate ledgers. Raw gas and volume equation residuals
are measured, not replaced by the iteration recurrence. A volume-continuity
error b can contribute at most |b| to a gas residual because 0<=C<=1. The
additional transport error is bounded separately from this contribution, and
the volume defect in excess of the measured pressure residual must also meet
the requested tolerance. Raw residual and adjusted error are BOTH reported.
The previous single absolute 1e-7 gas residual gate incorrectly charged upstream
pressure error to gas iteration; it was not made smaller by this correction.
Inventory change independently must be <=max(1e-7,initial_gas*1e-6), and every
published candidate value must be finite and satisfy 0<=G1<=V1 exactly in its
stored representation. This is numerical conservation within reported error,
not bitwise gas-count conservation. Material counts remain untouched/exact.

Initial GPU trials rejected cases: direct large-term evaluation introduced
roundoff, then one mixed case still had raw residual 1.0464e-7 after stable
increment updates. That upstream-error distinction motivated the explicit
component budget, not a claim of exact mass or of improved bubble mechanics.
The CPU oracle also handles only sub-1e-12 negative analytic-area roundoff;
actual negative capacity is rejected. GPU capacity checks remain strict.

Validation includes full water, full gas and a mixed interface for all eight
motion angles and the 20-grain chain, plus invalid capacity, insufficient
iterations, mismatched time step and recovery. This is first-order upwind
transport and may smear interfaces. No interface sharpening or long-run shape
acceptance is claimed. The live world still uses its old updater: pressure
reaction/work, state publication and replacing whole-packet remap remain next.
See reports/local-gas-validation.log, grain-volume.json,
local-gas-before-stable-update.json and cpu-local-gas.log.

## 2026-10-25: work-conjugate candidate drainage reaction

`record_drainage_reaction(dt)` gathers pressure differences against the same
finite-step box swept-volume weights as `grain_volume_flux.glsl`. Each grain
owns its force output; no force scatter or float atomics are used. Pressure
state is retained from the existing projection, and an 8-byte/cell force buffer
is allocated only on demand. Failed pressure solves explicitly write zero
candidate forces so old successful forces cannot leak through a rejection.
The pass does not update live grain velocities or add to old LBM impulses.

For each axis, swept solid flux is written as `J_s = B(v)*v`. The secant weights
are derived from exact endpoint overlaps and symmetric coordinate paths.
Reaction is `F = B^T * pressure_difference`, giving
`sum(F dot v) = sum(pressure_difference * J_s)`.
Since projected liquid flux is `A*pressure_difference` and its divergence
cancels solid flux, pressure work is the negative drainage dissipation
`-sum(q_liquid^2/A)` up to the pressure residual. This extends the existing
project-local geometric adjoint construction to current box particles; it is
not a new independent particle solver.

Zero velocity components use the symmetric instantaneous face-cut extension.
This specifies a candidate force but does not validate static support or a
unique traction inside a packed region. Nor does finite-step work equality
prove an implicit time integrator, friction law or full fluid momentum balance.
The model still uses unit drainage coefficients, not measured water viscosity.

The first packed-chain comparison had correct total work but individual force
error 4.53e-5. CG and preconditioned CG chose different pressure constants on
the connected flow domain while fully solid cells remained zero. An explicit
zero-mean pressure convention over cells with open faces now precedes final
residual verification and reaction evaluation; three bounded GPU passes, no
readback. CPU comparison uses its zero-mean CG solution. Independent gauges for
multiple disconnected liquid domains remain unvalidated; do not promote this
reaction into general product dynamics before resolving that limitation.

Final eight-angle and 20-grain-chain GPU/CPU force comparisons have maximum
error 1.54e-7; work/dissipation residual <=4.45e-11. Rejection clears stale forces
and preserves physical snapshots. The 202-test CPU suite and the GPU candidate
suite pass. The uniform-pressure-shift CPU check also passes. Evidence:
`reports/grain-volume.json`, `drainage-reaction-validation.log`,
`drainage-reaction-before-gauge.json`, `cpu-drainage-reaction.log`.

Next: use the reaction in a bounded velocity/contact feedback solve, with work
and motion checked on the SAME candidate. Do not simply add this pressure on
top of the old LBM force or publish positions computed before its reaction.
Only after that feedback is accepted can gas volume, fluid capacity and grain
positions replace the old packet-remap transaction. Main-window bubble support,
shape, release and long-run performance remain unfinished.
# 2026-10-25 Same-step feedback feasibility gate

## Split liquid topology reference

### Matching boundary source and pressure/inertia coupling

#### Fixed-contact pressure-aware reference

### Box-region endpoint mapping

The thin-region pressure failure is now resolved in the CPU reference without
changing the 2048 update budget or true-residual gate. Recurrence convergence
triggers a true-residual refresh/restart within that budget. That alone reduced
the chain failure from 1.454e-10 to 3.587e-12 but did not pass. Optional TwoSum
pressure accumulation then retains low bits throughout updates, pressure-datum
shifts and face differences; low bits are returned with pressure and must not
be discarded by a future force-feedback implementation. The compensated path
currently supports the built-in network operator only, not arbitrary custom
pressure/contact operators. Failure clears its candidate low-part metadata.

The endpoint chain now takes 1510 updates on 1025 nodes/1986 edges, reaching
true pressure residual 9.019e-13, gas residual 6.712e-14, endpoint area error
3.553e-15 and measured global gas drift 0.0. This is successful prescribed-motion
mapping, not a coupled physical-state commit. Its endpoint-averaged passages
remain an approximation, and the recomputed pressure has not yet changed the
contact/velocity solution that supplied the motion. Dense responses and this
iteration cost are not a product GPU implementation or performance acceptance.

Regression checks include a 1e12 conductance contrast, a pressure-datum shift
of 1e6 with unchanged flux, insufficient-budget rejection, and the original
20-grain joint candidate followed by exact endpoint gas mapping. Historical
failure values below document the preceding state; see the latest phase report.

`overlap_ledger` records exact same-cell rectangle intersections, covered
fluid/gas and newly exposed capacity. Covered gas remains an explicit pending
inventory; it is not deleted or assigned an arbitrary distant recipient.
Pure stationary repartition can complete using overlap alone. Material/owner
identity changes, curved bands and displacement above 0.25 are rejected.
Negative area tails within the stated double-roundoff tolerance are zeroed;
positive uncovered/covered areas are never hidden.

`moving_box_gas` overlays old/new rectangle cuts locally. Nodes have exact old
and new capacities; a neighbor face is available only when both sides contain
fluid at at least one endpoint. Coefficients use endpoint time averaging, which
is an approximation and not proof of full space-time connectivity. New pressure
drains these exact capacity changes before implicit gas transport. A sealed
kinematic plug remains incompatible and is rejected. This is a kinematic remap,
not a new jointly accepted pressure/contact step: its recomputed pressure still
needs matching feedback before any physical position publication.

The shared CG now optionally accepts a positive diagonal preconditioner; the
old path is unchanged by default. The overlay supplies an explicit source
roundoff bound from coordinate ULPs, accumulated separately per component.
No source mean is removed, and true residual checks remain unchanged. The
20-grain endpoint first had net source -2.375e-12 (volume -2.375e-13 at dt .1),
within the coordinate arithmetic bound; pressure still fails its 1e-12 true
residual gate at 1.454e-10. It remains rejected rather than clipping thin cells
or accepting the recurrence residual. Thin-region conditioning is still open.

Single-box translation with nonuniform gas passes exact endpoint capacity,
inventory and local flow tests (reports/region-remap-single.json). Tests also
cover static repartition, sealed sides, incompatible plug motion, identity and
displacement bounds. No GPU remap or main-window change has been delivered.

`local_gas_reference.transport_regions` now transports gas volume on these
separate regions with bounded implicit upwinding. Supplied end capacities must
match oriented local volume flux before solving. Concentrations are convex
updates; no clipping or inventory rescaling is used. Each disconnected gas
inventory is checked separately. The tests include a disappearing region,
newly available capacity, a sealed disk barrier, incompatible capacity/flux,
iteration exhaustion and recovery. These are gas transport checks, not a
moving-geometry correspondence implementation.

For the joint 20-grain candidate, flux-derived capacities give gas equation
residual 2.082e-14, volume residual 2.870e-16 and inventory drift -1.503e-13.
However, aggregated capacities differ from exact endpoint box geometry by
1.234e-7 at dt=0.1. The candidate remains uncommitted. Frozen region nodes
cannot represent all newly opened/closed regions merely by changing their
volumes. The next remap must preserve local region correspondence and the
geometric conservation law, not accept this mismatch or globally rescale gas.

`coupled_contacts` now uses unit contact impulse responses from the same
pressure/inertia operator. A bounded projected Coulomb solve updates contact
impulses; a small active-set refinement resolves sticking/sliding constraints.
Pressure is re-solved from the final impulse-adjusted predictor before checking
the contact law. Momentum balance, volume continuity and the discrete energy
identity include both pressure force and contact impulse.

The 20-grain fixture initially stopped at residual 3.289e-8 after 128 sweeps.
Naive active-set elimination amplified the result because uniform normal
contact impulses form a response null mode with the sealed liquid pressure.
The reference detects this uniform mode from its computed velocity response
(<=1e-9), selects a representative at the friction cone boundary, and checks
all original constraints again. It does not remove the volume equation or
relax final tolerances. The fixture reaches contact residual 2.526e-12 and
continuity 8.446e-11 with the same 128 sweeps and at most four refinements.
The local cone has also been tested at friction 0 and 0.5 with a two-grain pair.

This oracle stores two response columns per supplied contact (38 solves for
the chain), capped at 64 contacts. It is not an acceptable production GPU
algorithm. General redundant contact networks, automatic contact discovery,
prospective diagonal collisions and moving region/gas transport remain open.
Only a supplied fixed contact set on frozen geometry is covered. No positions
or physical state are committed, and pressure/contact force partition at a
detected null mode must not be mistaken for a calibrated absolute liquid load.

The integrated solid normal on each exposed region boundary defines S. For
translation v, the liquid volume source is S v and the grain reaction is
-S^T p. Curved-band normals integrate analytically; artificial strip cuts add
no solid force. The source aggregated by original grid cell matches an
independent central difference of solid occupancy in the tested offset box
and disk cases. Constant pressure produces zero net force on an immersed grain.

`coupled_pressure` solves (L + dt S M^-1 S^T) p = S v_free with the shared CG,
then v_new = v_free - dt M^-1 S^T p. This is simultaneous pressure/inertia
coupling on frozen geometry, not the earlier relaxed outer force iteration.
It does not apply the prescribed-source per-component rejection: grain motion
is now an unknown, so pressure may stop incompatible motion. Fluid conductance
remains the uncalibrated stationary two-point network described below.

A unit box plug in a sealed one-cell-high channel (mass 3, predicted speed
0.02, dt 0.1) stops to 3.47e-18, with force -0.6000000000000001 and maximum
fluid flux 5.56e-17. The prescribed-motion solve rejects the same attempted
compression. Single-grain checks satisfy the discrete energy identity:
delta kinetic energy + 0.5 sum M |delta v|^2 + dt sum q^2/conductance = 0.

The original 20-grain chain pressure solve now converges in 198 CG updates
(883 region nodes, residual 9.413e-11), but its closing contact speed reaches
7.7686e-4. It is NOT an accepted physical step: friction/contact constraints
are not yet included. Next integrate these constraints in the same pressure/
inertia step before any position commit, followed by conservative gas/region
transport. No state publication, bubble support or runtime replacement is
established by these CPU results.

The region graph now reuses `DarcyGrid.pressure_for_source` and its existing
CG implementation. `DarcyGrid.from_graph` supplies arbitrary positive network
conductances without duplicating the solver. Each disconnected component must
have zero net volume source (absolute double-precision check 1e-12); incompatible
sources fail before CG. No source mean is subtracted. Pressure gauges are
normalized independently by component after solving, then true residual is
checked again.

The initial reference conductance is liquid port length divided by distance
between band interior sample points. It is positive and reproduces the regular
Cartesian operator in empty cells, but is not a calibrated viscous model or
an accuracy claim on skew/curved bands. Source rates remain explicitly supplied,
not yet computed from moving grains. Tests cover sealed rejection, within-side
drainage with the other side unchanged, flow through a true gap, finite budgets,
input preservation, local volume balance and pressure work = network dissipation.

For the sealed fixtures, compatible-source residuals are 2.695e-11 (box) and
5.718e-11 (disk); pressure on the undriven side remains exactly zero. Network
work residual is at most 5.263e-13. These are stationary CPU network checks,
not GPU cut-cell or bubble/particle coupling acceptance. The next step is a
conservative moving-region source/transport map with matching reaction; a
naive source assignment by the old full-cell volume change is insufficient.

`tests/grain_cut_cells.py` now decomposes each cell into vertical free bands,
cut at box edges, disk extrema, circle/cell intersections and disk tangencies.
Arc integrals give band areas; only positive-length liquid ports connect
neighboring bands. Geometric openings <=1e-12 are treated as closed in this
double-precision reference. Solids must not overlap; general overlapping or
deforming shapes are outside its preconditions.

The original touching disk barrier has two components with 130 nodes and 209
edges; the box barrier has two with 90 nodes and 151 edges. Both have no graph
path across the barrier. Removing a grain reconnects the domain. A horizontal
disk barrier likewise separates the domain; moving one disk by +/-0.01 creates
a real connecting gap. A centered disk has four separate local corner regions.
Band areas match the independent occupancy integral within 1e-12 in the tested
offset single-grain fixture. These checks establish topology and area only.

This reference is deliberately not the runtime layout: its all-body searches
and dynamic node lists have not been budgeted for GPU use. Pressure, moving
region transport, capillary traction and joint contact are not yet connected.
The next step must assign source/flux to the separate regions and reject net
volume sources incompatible with each closed connected component, rather
than reconnecting components to make a pressure solve succeed. A graph with
correct connectivity alone is not a validated hydraulic conductance model.

## Topology counterexample before adopting new weights

The same geometry reference now accepts an optional disk shape (radius 0.5),
reusing the existing analytic disk/rectangle area integration. This is a
diagnostic alternative only: no live conversion, material-volume change or
GPU shape change is authorized by it. Walls remain exact boxes; conservative
coordinate-path flux and the corresponding pressure reaction use the same
selected shape. Contact is still the conservative box constraint, so this is
not a finished disk dynamics model.

With disk geometry the original chain converges in 7 secant iterations
(velocity residual 7.3112e-9, contact residual 7.553e-14). However, a stationary
chain of touching disks connecting the top and bottom walls should partition
the 2D liquid domain. The existing one-pressure-per-cell graph incorrectly
admits cross-barrier flux -0.132074 under an imposed left/right source. The
same box barrier correctly rejects that incompatible source. This disqualifies
the round-shape substitution as a fix despite its better convergence.

The next geometry/pressure implementation must preserve separate liquid
components within a cut cell or otherwise prove that it cannot bridge them.
Face opening alone, even when continuous, is insufficient. The counterexample
is part of `probe_drainage_alignment.py` and its generated report, explicitly
marked physical_acceptance=false. Geometry unit tests check area, swept-volume
balance, tangent continuity and unchanged wall shape, not bubble acceptance.

Operator isolation now reproduces the jump while holding the prescribed solid
flux and reaction weights fixed: replacing only face coefficients changes the
top vertical reaction from -0.027533 to -0.013047 and dissipation from
0.001007210 to 0.000953625. Changing solid flux while retaining the old sealed
faces instead creates an incompatible source; the pressure solve rejects it.
These crossed operators are diagnostic only and cannot define a physical step.
Run `python tests/probe_drainage_alignment.py` to regenerate the evidence.

The current coefficient is endpoint-averaged geometric face opening. A tiny
box displacement can uncover a large portion of a face adjacent to a thin
fluid sliver; assigning that opening directly as conductance gives the lumped
pressure cell a finite new route. This observation identifies the coefficient
construction as sufficient to cause the jump, not proof that it is the only
issue. Do not smooth particle positions or floor fluid capacity to hide it.
The replacement must account for the fluid region inside the cell as well as
its boundary, retain sealed faces, and keep pressure/reaction work consistent.

Relevant primary research: [Batty, Bertails and Bridson 2007](https://uwspace.uwaterloo.ca/items/f5cb877f-1b56-4ff5-81d9-f7473a5e7f1a)
formulates fluid-solid pressure coupling as kinetic-energy minimization with a
symmetric positive-semidefinite system. The repository abstract was verified;
the UBC full-PDF fetch failed, but the Waterloo mirror subsequently supplied
the full paper (local reports/batty-2007-coupling.pdf). Section 2.1 uses fluid
volume in the cell surrounding each staggered velocity sample for kinetic
energy weights. Section 3.1 derives the solid pressure map from matching solid
volume weights; section 3.2 incorporates solid inverse mass into the pressure
system. This is not equivalent to replacing only our face coefficient: the
source, reaction and transport operators must remain compatible. No detailed
discretization from the paper has been implemented here. A variational replacement still
has to satisfy this project's finite-volume gas transport and contact gates.

Follow-up: a depth-one secant mixing option in the same reference reduces the
single-grain iteration count to 3-5 without altering acceptance. For the chain,
offset x=0 still fails (2.528816e-4), while x=0.01, 0.2 and -0.2 converge in
8, 7 and 7 iterations. These offsets are diagnostic only, not changed product
initial conditions. More importantly, with the original aligned geometry and
fixed downward speed 0.02, top-grain pressure reaction changes from roughly
(+0.006154,-0.012954) at horizontal speed -1e-7, through
(0.000045,-0.027533) at zero, to (-0.006014,-0.013046) at +1e-7.
Thus a vanishing lateral perturbation has a finite reaction change. Existing
work-conjugacy tests do not establish continuity of the pressure reaction.

This changes the next action: inspect cut-cell mobility and pressure extension
when fluid capacity opens from zero, before choosing another coupled solver.
The open-face/zero-capacity topology changes at exact grid alignment; the
specific cause of the force jump is not yet isolated. Do not add position
jitter, accept the stalled step, or interpret secant mixing as a physics fix.
Evidence: reports/feedback-grid-alignment.json. GPU and main host are unchanged.

The existing pressure reaction reference now recomputes contact velocity,
swept capacity, face apertures, drainage pressure and reaction in one bounded
fixed-point loop. It relaxes the force input by 0.5, never the solved contact
velocity. Contact works in displacement units for the selected dt and returns
impulses in velocity units. This is a test oracle, not an additional runtime
solver, and does not commit any live state or include capillary forcing.

At dt=0.1, 16 outer iterations and a velocity residual limit of 1e-8, eight
single-grain directions converge (maximum residual 8.716e-9). Their momentum
balances, pressure-work identity and decreasing kinetic energy are checked.
The existing 20-grain chain does not converge: residual 3.015241e-4, despite
contact residual 1.009e-13 with the established 128+64 contact sweep budget. Both an
insufficient one-iteration budget and the chain must be rejected without input
mutation. See reports/pressure-feedback.json and test_drainage_reaction.py.

Decision: do not port this simple relaxed force feedback to GPU as the coupled
step. Its dense-contact failure would reintroduce whole-world rejection. The
next implementation must address the coupled pressure/contact system (for
example a consistent linearized resistance solve with contact constraints),
using this chain as a required gate. More iterations or a looser residual are
not the acceptance strategy. No bubble support, breakup or main-window visual
improvement is established by these tests.

