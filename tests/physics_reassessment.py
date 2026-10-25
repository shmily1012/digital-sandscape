"""Isolated analytical checks and falsification probes, NOT a new app solver."""
import json
import math
from pathlib import Path
import statistics

from reference_model import gravity, step

ROOT = Path(__file__).resolve().parents[1]


def settling_probe():
    # Dilute, unbounded creeping-flow sphere; no wall or added-mass correction.
    diameter, rho_s, rho_l, viscosity, g = 20e-6, 2650.0, 1000.0, 0.001, 9.81
    terminal = (rho_s-rho_l)*g*diameter**2/(18*viscosity)
    tau = rho_s*diameter**2/(18*viscosity)
    acceleration = g*(1-rho_l/rho_s)
    errors = []
    for subdivisions in (10, 100):
        dt = tau/subdivisions
        velocity = 0.0
        for _ in range(10*subdivisions):
            velocity = (velocity+dt*acceleration)/(1+dt/tau)
        exact = terminal*(1-math.exp(-10))
        errors.append(abs(velocity-exact)/terminal)
    assert errors[1] < errors[0] and errors[1] < 1e-4
    reynolds = rho_l*terminal*diameter/viscosity
    assert reynolds < 0.1
    return {"scope": "Unbounded single sphere only; parameters illustrative, not KB measurements",
            "diameter_m": diameter, "viscosity_pa_s": viscosity,
            "terminal_m_s": terminal, "relaxation_s": tau, "Re": reynolds,
            "backward_euler_relative_errors_dt_tau_10_and_100": errors,
            "status": "analytical-limit numerical check passed; real mixture uncalibrated"}


def interface_probe():
    # Independent energy/volume finite difference checks spherical Laplace pressure.
    sigma, radius, epsilon = 0.072, 0.001, 1e-8
    energy = lambda r: sigma*4*math.pi*r*r
    volume = lambda r: 4*math.pi*r**3/3
    numerical = (energy(radius+epsilon)-energy(radius-epsilon))/(volume(radius+epsilon)-volume(radius-epsilon))
    exact = 2*sigma/radius
    assert abs(numerical/exact-1) < 1e-7
    return {"scope": "Single spherical gas/liquid interface, NOT confined bubble release",
            "radius_m": radius, "sigma_N_m": sigma, "pressure_jump_pa": exact,
            "energy_volume_finite_difference_pa": numerical,
            "status": "analytical-limit check passed; functional bubble experiment NOT IMPLEMENTED"}


def legacy_freeflight_probe():
    results = []
    for material in (1, 2, 3):
        offsets = []
        for seed in range(64):
            side = 32
            cells = [0]*(side*side)
            for y in range(side):
                for x in range(side):
                    if x in (0, side-1) or y in (0, side-1):
                        cells[y*side+x] = 4
            cells[5*side+16] = material
            for tick in range(10):
                step(cells, side, seed, tick, gravity(0))
            locations = [i for i, value in enumerate(cells) if value == material]
            assert len(locations) == 1
            x, y = locations[0] % side, locations[0] // side
            # Maximum 20 cell moves cannot reach the floor from y=5.
            assert y < side-2
            offsets.append((x-16, y-5))
        moved_sideways = sum(dx != 0 for dx, _ in offsets)
        assert moved_sideways > 0
        results.append({"material": material, "seeds": 64, "ticks": 10,
                        "sideways_count": moved_sideways,
                        "mean_dx_cells": statistics.mean(dx for dx, _ in offsets),
                        "rms_dx_cells": math.sqrt(statistics.mean(dx*dx for dx, _ in offsets)),
                        "mean_dy_cells": statistics.mean(dy for _, dy in offsets)})
    return {"scope": "Existing CPU-equivalent solver, solitary grain, still implicit medium, vertical gravity",
            "results": results,
            "finding": "Sideways movement occurs without contact or resolved flow. This is rule-induced diffusion, not avalanche friction.",
            "pile_experiment": "Contact/slope and controlled-feed validation still required"}


def main():
    report = {"kind": "Physics reassessment diagnostics; not physical product validation",
              "E1_settling_limit": settling_probe(),
              "E2_interface_limit_only": interface_probe(),
              "E3_legacy_negative_control": legacy_freeflight_probe()}
    (ROOT / "reports/physics-reassessment.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
