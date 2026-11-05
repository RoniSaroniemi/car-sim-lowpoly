"""Stage unchanged baseline solver sources for the null-provider comparison."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
destination = root / "verification/contact_baseline"
destination.mkdir(parents=True, exist_ok=True)
for filename in ("structure_solver.gd", "wheel_physics.gd", "vehicle_simulation.gd", "collision_forecast.gd"):
    source = subprocess.check_output(
        ["git", "show", f"2ad1656:scripts/{filename}"], cwd=root, text=True
    )
    for dependency in ("structure_solver.gd", "wheel_physics.gd", "collision_forecast.gd"):
        source = source.replace(
            f"res://scripts/{dependency}",
            f"res://verification/contact_baseline/{dependency}",
        )
    (destination / filename).write_text(source)
print("Staged 2ad1656 under ignored verification/contact_baseline")
