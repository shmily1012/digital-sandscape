"""Run CPU tests and create the fixture used by the real GPU differential test."""
import hashlib
import json
import math
from pathlib import Path
import time
import unittest

from reference_model import center, centered_cloud, gravity, initial_state, serialize, step

ROOT = Path(__file__).resolve().parents[1]


def main():
    started = time.perf_counter()
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.discover(str(ROOT / "tests"), pattern="test_*.py"))
    cells = initial_state(32, 709)
    for tick in range(70):
        step(cells, 32, 709, tick, gravity(tick*3.75))
    data = serialize(cells)
    (ROOT / "reports/reference_gpu_expected.bin").write_bytes(data)
    angles = []
    for angle in (0, 30, 45, 90, 120, 180, 270, 13.7):
        cells = centered_cloud(48)
        before = center(cells, 48)
        for tick in range(30):
            step(cells, 48, 908, tick, gravity(angle))
        after = center(cells, 48)
        dx, dy = after[0]-before[0], after[1]-before[1]
        measured = math.degrees(math.atan2(dx, dy)) % 360
        error = (measured-angle+180) % 360-180
        angles.append({"angle": angle, "centroid_displacement": [dx, dy],
                       "direction_error_deg": round(error, 3)})
    report = {"kind": "CPU reference only; NOT GPU validation",
              "tests_run": result.testsRun, "failures": len(result.failures),
              "errors": len(result.errors), "elapsed_seconds": round(time.perf_counter()-started, 2),
              "fixture_sha256": hashlib.sha256(data).hexdigest(),
              "direction_probe": angles,
              "gpu_test": "Separate run; see gpu-validation.json", "macos": "NOT TESTED"}
    (ROOT / "reports/cpu_validation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
