# Bubble-supported sand: unresolved product gate

## 2026-10-25: isolated linear failure repaired; outer geometry still rejects

Failed pressure exceptions now carry diagnostic candidates without publishing
them as accepted pressure. The probe saves the actual system. A 60-digit Decimal
audit agrees with the old 2.80995e-9 residual; float operator evaluation error is
only 1.62e-17. The 1063-node, 2067-edge system has conductances from 3.55e-15 to
1.61e7. The failure was genuine nonconvergence, not an overly strict float audit.

Endpoint joint solves now use scaled shifted IC(0) as a preconditioner. Four
bounded shifts are attempted; shifts affect only the preconditioner, never the
physical matrix or source. All channels remain. Replaying the same captured system
now needs 169 of 2048 iterations, residual/continuity 1.01866e-11. The analytic
network test checks the unshifted physical flux despite a nonzero factor shift.

Contact polishing now solves increments with complete pivoting and up to eight
backtracks per each of four polish rounds. Unresolved null coordinates retain
their existing impulse; a polish is accepted only if its complementarity merit
decreases. The old absolute solve worsened 4.64e-8 to .00121; the safeguarded
version reaches 3.80e-8. Tightening endpoint response solves to 1e-12 then allows
all eight outer iterations to finish their inner contact/pressure gates.

The complete endpoint candidate still rejects: original momentum residual
.001302476 after eight geometry iterations. No positions/gas are published and
no GPU bubble implementation is claimed. Next address nonlinear geometry/volume
feedback, rather than increasing the already passing inner solve budget.
Evidence: endpoint-system-audit.json (input hash and replay),
endpoint-shared-ic-accurate.log, cpu-endpoint-ic-final.log (241 tests),
gpu-endpoint-ic-regression.log (existing GPU path only).

## 2026-10-25: endpoint operator shared with contact (CPU only)

The existing `moving_contact_candidate` now rebuilds its joint pressure/contact
operator from the endpoint overlay and finite boundary weights used by gas
transport. It no longer repeatedly adds an endpoint force correction to the old
geometry. Final acceptance still requires the original momentum equation against
the endpoint pressure, with the same 1e-8 gate. No live application state is written.

The thin overlay uses a diagonal preconditioner, compensated pressure and a
low-part-aware custom inertia operator. Default linear budgets are explicit:
512 iterations for ordinary geometry, 2048 for an endpoint overlay; an explicitly
provided budget is honored. The outer budget stays 8 (maximum allowed 16).
A three-node analytic inertia/network test verifies the custom compensated path.

The dense-chain probe still fails: a contact response column reaches pressure
residual 2.80995e-9 versus 1e-10. Thus this is an incomplete integration fix, not
permission to commit endpoint gas/positions or port an accepted solver to GPU.
An earlier Aitken relaxation trial also failed (outer residual .00119319); it was
removed, with its diagnostic result retained. Probe failures now exit nonzero and
produce a structured reason. Next investigate conditioning/product cancellation
in the joint endpoint operator without weakening the original acceptance gates.
Evidence: endpoint-feedback-shared-operator-observed.json,
endpoint-feedback-relaxed.json, cpu-shared-endpoint-operator.log.

## 2026-10-25: actual continuous-candidate gas-entry geometry

The shared coupled solver exposes its already allocated candidate phase RID for
test-only observation. The GPU rejection check records at most 16 examples and
the total count, using live material/offsets, candidate velocity and candidate gas.
No threshold, force, acceptance or physical state was changed.

The heavy diagonal-contact trajectory accepts 1709 ticks, then rejects flag 32
on 18 grains. Example source 5559 to 5687: y offset .49832526, displacement
.003247805; target overlap changes from .49831856 to .50156631, only .00324776
new area. Live gas fraction .05038368 becomes candidate .05041352. Thus the
geometry is already almost half covered while the old LBM node remains wholly
fluid; crossing the center-bin boundary triggers a whole-node remap/veto.
These geometric areas are NOT a measurement of gas displaced: phase within the
cell is unresolved. Do not multiply them by concentration and claim a proven
local gas transport without a capacity-consistent scheme.

This confirms the integration gap: persist and evolve fluid capacity with actual
particle coverage before crossing cell ownership, then commit matching pressure,
gas transport and contact velocity together. Existing local volume/transport
candidates cannot be attached after the old whole-node step and called complete.
The observation is in `grain-coupled.json` / `gas_entry_geometry`; GPU regression
still correctly rejects the candidate and preserves the accepted state.

Related primary research distinguishes boundary mass-transfer momentum from
ordinary bounce-back impulse: [Chen et al., PRE 88, 013303](https://journals.aps.org/pre/abstract/10.1103/PhysRevE.88.013303).
Its abstract supports checking this distinction; it does not validate our packet
remap or supply a drop-in repair for single-cell grains and diffuse gas.

## 2026-10-25: sealed-corner route correction (grain rule revision 2)

The live `phase_grains` kernel previously permitted a diagonal hop when both
cardinal routes were blocked, e.g. gas below and a wall beside a grain. A target
liquid cell across that corner does not establish a connected passage. Diagonal
hops now require at least one intervening fluid cell with gas fraction <= .05.
This is a discrete route rule, not a continuous swept-shape collision test.
All reads stay in the invocation's 2x2 block; no neighboring writes or extra pass.

The CPU oracle matches the new rule. Four rotated blocked-corner cases remain
unchanged for 180 ticks, while four opened-route cases still release sideways.
The GPU fixture suite matches materials, gas, populations, force packets and
residuals exactly. Actual-window smoke still shows the lower-edge band, so this
fix is accepted for legal motion only, not bubble support.

New reports/checkpoint metadata record grain_rule_revision=2. Old checkpoint
arrays can still restore without a reset, then evolve under the current rule;
this is not historical replay of revision 1. The comparison analyzer now refuses
mixed rule revisions. Prior wetting/traction comparisons are historical evidence
and must be rerun before comparing against the new baseline. Pre-change baseline
tick-10000 artifacts are retained under reports/corner-route-before.

## 2026-10-25: consistent wetting in the live candidate

The paired smoke candidate now accepts `--wetting-cosine=0.5` and `=-0.5`.
The same grain surface preference enters both the boundary stress and phase
transport; container walls stay neutral. Positive values prefer liquid in the
implemented surface-energy convention. These are diagnostic values, not measured
mineral contact angles. Output names and the window show the selected value.
Nonzero values require paired-interface smoke mode, so production sessions cannot
silently change model parameters.

Both runs reach tick 13000 with numerical integrity checks passing, but both retain
the lower-edge grain band at tick 10000. The fixed-grain 80-step CPU/GPU test now
includes both signs: maximum phase error 3.17e-7, velocity error 6.85e-8 across the
five cases, gas drift <=3.20e-6. These results reject a parameter-only cure for
the observed band in these cases; they do not establish that wetting is irrelevant.
The remaining live-path gap is the whole-voxel displacement and its mechanical
response, including displaced-fluid momentum/work and load transmission. Do not
keep tuning wetting or clipping pressure to make the picture pass.

Evidence: contact-wetting-positive.log, contact-wetting-negative.log,
gpu-live-wetting-coupling.log, and paired-interface-wetting screenshots/raw arrays.

## 2026-10-25: paired stress in the actual voxel host

`python run.py phase-sand-smoke --contact-bed --paired-interface` now evolves the
same temporary host using the existing interface stress on both fluid and grains.
The force is computed before streaming, sampled by the old excess-traction
estimator, and shared with fluid momentum through a dedicated descriptor set.
Each dispatch has a barrier; initialization is lazy and bounded. Neutral wetting
only, no new shader, no normal-frame readback, no production default/save change.
This is still the old voxel hopping rule, not a conservative mechanical grain
integrator. Shared capillary forces do not close its displacement/work ledger.

The run conserves tested inventories through tick 13000, but fails the intended
visual behavior: at tick 10000 lower-half adjacency is 175 versus baseline 177,
and the lower band remains. Mean reconstructed force/weight is -15.7294 including
the paired stress, versus baseline -12.3778. Do not promote this candidate.
`phase-coupled` now includes an 80-step fixed-grain CPU/GPU comparison of this
live fluid/phase dispatch: phase error 2.84e-7, velocity error 6.85e-8, gas drift
2.23e-6. That validates dispatch ordering for fixed geometry, not grain mechanics.
Evidence: contact-paired-interface.log, contact-paired-comparison.log and
gpu-live-paired-coupling.log. Next inspect wetting and contact mobility; neutral
surface energy is an assumption, not calibrated mineral behavior.

## 2026-10-25: frozen-state force decomposition

The smoke observer now saves `.populations.f32` beside phase and material snapshots.
`analyze_contact_ablation.py` reuses the existing traction reference and splits
each population exactly into isotropic `W*rho`, opposite-direction odd, and the
remaining even part. Applying the same estimator to each part reconstructs its
force; this is an algebraic attribution, not a new physical force model. The odd
part is not assumed to be pure viscous drag. Values below precede the production
component clamp and describe the captured state, not the last historical hop.

For the baseline at tick 10000, the 177 lower-half interface-adjacent grains have
mean vertical force/weight: pressure -13.6722, odd +1.3294, even -0.0350,
total -12.3778 (negative means upward). Total upward force exceeds effective
weight for 156/177 grains. Reconstruction error is 4.12e-17. This identifies the
isotropic pressure contribution as the dominant term in this captured failure;
it does not prove that every pressure force or all attachment is unphysical.

Evaluating the existing neutral capillary-stress candidate on that same geometry
gives mean -3.3177 additional vertical force/weight on those grains. It does NOT
cancel the old estimate. This candidate was not used to evolve the captured
pressure field; adding it retrospectively would mix two discretizations and is
not a validated repair. The paired force sum is near zero, but force cancellation
alone does not establish interface work, loading response or grain motion.

Next correction must make the fluid stress and grain response use a consistent
boundary model in the live path. Do not normalize the measured force, simply
delete pressure, or append the unused stress to improve a screenshot.

## 2026-10-25: runtime traction ablation

Run `python run.py phase-sand-smoke --contact-bed`, then the same command with
`--without-traction`, and `python tests/analyze_contact_ablation.py`.
The switch is restricted to the temporary smoke host; it disables only the old
grain traction estimator. Gas/fluid evolution, material mobility, gas exclusion,
seed, rotation schedule and initial arrays stay the same. The disabled path clears
derived traction before dispatch, including any values left by earlier steps.
No shader or production default was changed. This is diagnostic, not a replacement
for reciprocal interface forces or a model of a physically supported bed.

At tick 10000, lower-half interface-adjacent grains fall from 177 to 16; upper-half
adjacent grains increase from 65 to 194. The number below 72% of container height
falls from 3175 to 170 (5120 grains in both). Adjacency means an 8-neighbor gas
fraction above .05, classified relative to the gas centroid; it is not contact
force or attachment duration. Initial raw material and phase arrays match exactly.
The baseline forms a visible lower-edge band; the ablation retains a top bed with
side release. Different trajectories also alter residence time, so these counts
alone do not isolate individual attachment forces. Next inspect the estimator's
pressure/background contribution on the same frozen interface geometry; do not
adopt force removal as a completed physical fix.

Evidence: `reports/contact-traction-ablation.json` and paired runtime images at
ticks 2000, 5000, 10000. Both runs preserve tested inventories and pass through
rotation to tick 13000; physical acceptance remains open.

## 2026-10-25: gas-entry veto ablation and remap locality

The current coupled baseline accepts 1709 steps, then rejects with flag 32
(gas entry), despite a contact residual of 4.66e-10. The earlier 1431-step
contact stall was removed by treating already tolerated negative contact gaps
as zero clearance, without loosening the swept-overlap or residual thresholds.

`python tests/probe_gas_exclusion.py` temporarily disables only the coupled
gas-entry veto, runs the existing GPU suite, archives the changed outputs, and
restores shader and baseline report bytes. This is an ablation, not a product
mode or an implemented wetting model. It accepts 9246 steps before a swept
collision (flag 128), preserving 1280 grains and fluid inventory. Its 57 contact
GPU/CPU comparisons pass, but they do not validate the removed gas veto.
The short coupled fixtures also pass; they do not cover sustained support.

State inspection shows a near-rectangular packed bed over the bubble, with no
demonstrated sustained leakage. Grain centroid y is 27.9983 at baseline tick
1709 and 25.7503 at ablation tick 9246 (initial 23.5). These are different times,
not a matched-time causal comparison. The ablation is not retained in runtime.
See `reports/gas-exclusion-probe.zip`, `gas-exclusion-inventory.json` and the
state-derived `gas-exclusion-comparison.png` (baseline left, ablation right;
blue is a diagnostic phase color, not intended artwork).

An independent application of the existing CPU remap to a 20-grain vertical
chain demonstrates that a 0.02-cell grain displacement across an occupancy
threshold transports the terminal fluid packet 20 cells to the chain head.
This is exact inventory conservation but nonlocal phase transport through a
packed bed. It does not prove that this specific event occurs in the heavy-bed
trajectory. Evidence: `reports/remap-chain-locality.json`.

Next implementation must address local displaced-fluid transport and mechanical
interface work together. Do not replace the gas-entry veto with an immovable
bubble wall, accept nonlocal gas transfer as bubble splitting, or spend another
iteration solely extending the contact scan budget. Stable-bed sleeping remains
unimplemented and must preserve load transmission and wake on support changes.

Primary-source review: Jansen and Harting, sections III-IV,
https://arxiv.org/html/1004.4414 . Their model accounts for momentum during
occupancy changes and includes virtual boundary fluid with reciprocal interaction
forces to represent wettability. It uses a multicomponent Shan-Chen formulation;
those equations cannot simply be pasted into our free-energy phase formulation.
Their resolved particles also differ from our single-cell grains. This comparison
identifies missing boundary coupling; it is not validation of our approximation.

Current observation update: the original 160-grain bed has nominal effective
weight only 0.195 times total bubble buoyancy in this model. It must not be the
only support fixture. The existing check now also uses a 32-row, 1280-grain bed
(ratio 1.559), with cold and pre-relaxed fluid. This is a load/geometry comparison,
not isolation of mechanical load from obstacle shape or a force-balance proof.
The heavier pre-relaxed bed retains grains above and releases them around the
sides; the bubble remains flatter, but lower-edge trapping persists.

The shared Physics initializer is also available in the actual host through
`python run.py phase-sand --contact-bed`. At 256 squared it contains 5120 grains
and has nominal weight/buoyancy ratio 1.568. No solver is duplicated; the option
disables session IO and changes only new-world initial conditions. Rotation still
evolves that same state. Normal artwork initialization remains unchanged.

The required behavior is a grain bed temporarily carried by a deformable gas/liquid
interface, with reciprocal load, redistribution, release through changing passages,
and relaxation after unloading. Gas exclusion alone does not establish support.
Interfacial retention also depends on wetting; not all mineral grains should be
treated as permanently attached to bubbles.

## Reproducible current-candidate observation

Run `python run.py phase-contact`. This uses the same `phase_fluid.gd` and shaders
as `phase-sand`, not another solver. It creates test-only worlds, never opens user
sessions, and writes raw phase/material arrays and exact-state diagnostic PNGs.

128 squared sealed circle; 160 mineral cells in a 40 by 4 bed; one diffuse bubble
below the bed, radius 21; seed 20261024; gravity (0, 0.00002); sigma 0.01. Four cases:

- Bubble and freely moving bed, 4000 ticks.
- Identical bed without gas, 4000 ticks.
- Bubble with externally fixed bed, 4000 ticks.
- Bubble with bed fixed for 8000 ticks, then released without resetting any fields
  and evolved for another 4000 ticks. This is pre-relaxation, not proof of equilibrium.

Snapshots measure inventory, gas integral, fluid mass, closed boundaries, release
below y=92, grain centroid, gas covariance, and the candidate traction estimator.
The observer recomputes only the derived traction; full physical snapshot bytes
are checked unchanged. Readback is confined to this test.

Exit 0 means diagnostic integrity. `physical_acceptance` explicitly remains
`NOT ESTABLISHED`. The fixed bed has external support; its deformation must not be
misrepresented as the response to an independently prescribed grain load.
Gas covariance changes do not, by themselves, demonstrate load-induced deformation.

## Observed failure, 2026-10-24

All four cases conserve materials and meet gas-relative-drift 1e-4 and fluid-relative-
drift 1e-6 bounds. At 4000 ticks, the water case releases 160/160 grains below y=92;
the bubble case releases 104/160. The latter exhibits a grain band on the bubble's
lower edge rather than the required upper supporting bed. The pre-relaxed case
also develops a lower-edge band; 72/160 grains reach y=92 after release.

At 1000 ticks after pre-relaxed release, 116/160 grains have at least one normalized
traction component beyond the shader's +/-4 clamp. At 500 ticks after cold release,
108/160 have an upward traction component exceeding their effective downward weight.
These are properties of the current heuristic, not measured physical forces.
They identify a next investigation target, not proof that any upward force is invalid.

The code rejects entry into c>0.05 but recognizes only solid downstream cells for
diagonal support. It has no grain momentum/contact reaction ledger, no calibrated
wetting law, and no reciprocal work accounting for its stochastic displacements.
Replacing a clamp constant or recognizing gas as rigid support cannot close these gaps.
Do not re-enable the rejected scalar load source (GRAIN_LOAD_MODEL.md).

## Required next implementation evidence

Numerical update on the same date: the first-moment collision closure was corrected
after a separate contact-state impulse ledger exposed rounding bias. Re-evolving
the fixture changes the released counts to 111/160 (cold bubble) and 102/160
(pre-relaxed bubble). The lower-edge band remains visible; physical acceptance is
unchanged. The earlier counts above are preserved historical evidence, not current
trajectory predictions. Run `python run.py phase-contact-ledger` after the observation
to validate the current force ledger. It automatically runs an independent Python
reference and fails the command when that verification fails.

Keep the existing Physics/Renderer/Director/ResourceManager boundary. Changes belong
to Physics. Reuse this fixture and the current application rather than building a
new disconnected solver or claiming success from a CPU-only example.

1. Define how grain/interface contact work and reaction enter the same discrete
   update, including the chosen wetting approximation and displaced fluid.
2. Demonstrate a static supported bed with balanced forces and no sustained energy
   generation. Record external support separately when geometry is fixed.
3. Increase the load by physical arrival of additional grains, without replacing
   state; measure interface displacement and contact/reaction changes.
4. Let grains leave through a physically opened passage; measure unloading and
   interface relaxation. Do not schedule particle deletion, bubble splitting or
   release times to make the test pass.
5. Compare GPU and CPU operators, inventories, work/energy residuals, arbitrary
   gravity orientations, and actual-window images. Mechanical and visual gates
   both remain open until this evidence exists.

Primary experimental background on capillary forces and detachment:
https://pubmed.ncbi.nlm.nih.gov/22423648/ . It does not calibrate the current
single-cell grain / diffuse-interface representation or prove KB-specific behavior.
# Continuous long-chain reference (2026-10-25)

The 20-grain CPU reference now accepts three consecutive endpoint steps with
preserved gas and material inventories. Local offsets are stored explicitly;
displacement is not recovered by subtracting rounded world coordinates.
Shared box faces are evaluated as grid-plane plus offset consistently in
partitioning, pressure boundary weights and finite displacement maps. No tiny
fluid regions were deleted or acceptance thresholds relaxed. Maximum momentum
residual is 1.80e-12, capacity residual 7.13e-13 and cumulative gas drift 1.14e-13.
This uses a fixed contact set and passive gas transport; it does not establish
bubble buoyancy/deformation, contact discovery, GPU timing or live-window
acceptance. Existing integer-cell GPU displacement is not an equivalent solver.

# Long-chain active-set null coordinate (2026-10-25)

For a verified uniform response null mode with every contact active and sticking,
the CPU incremental solve now preserves the existing mean normal impulse. It
does not invert the noisy redundant pressure/contact coordinate. Inactive and
sliding sets retain the full solve. Original pressure, momentum and contact
checks remain authoritative. All eight inner contact solves now pass the long
chain probe, but endpoint geometry cycles and capacity remains 4.12e-8, so no
state is published. The 243 CPU tests and existing GPU regression pass; this is
not application bubble acceptance. Next: local-coordinate and shared-face
construction accuracy, without deleting small fluid regions.

# Coherent sticking-contact prediction (2026-10-25)

The three-grain chain now accepts three geometry iterations and five consecutive
steps with conserved material and gas inventories. A diagnostic ablation with
identical initial state still rejects. Geometry prediction alone shares the
mass-weighted velocity of active, closed, axis-aligned sticking contacts, only
within the existing solver tolerance. Sliding tangent directions, opening,
walls and oblique contacts are not locked. No force/pressure is overwritten;
original momentum, capacity, work and actual geometric contact gates apply.
The 20-grain case still fails its contact residual (3.32e-8 versus 1e-8).
This is CPU reference progress, not GPU or application bubble acceptance.

# Endpoint joint pressure consistency (2026-10-25)

The CPU endpoint reference now uses one simultaneous pressure/contact solution
for both solid reaction and gas transport flux. It rejects inconsistent endpoint
capacity before transporting gas; it no longer substitutes a separately gauged
kinematic pressure while keeping old contact impulses. Static sealed support is
retained. Single-grain checks pass, but a three-grain chain and the 20-grain probe
still reject. The latter ends with capacity residual 7.49040e-7 after eight bounded
iterations. The 242 passing CPU tests include rejection checks, not physical
acceptance of these chains. Existing GPU regression does not cover this CPU
algorithm. No application bubble acceptance or visual improvement is claimed.

