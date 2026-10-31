#!/usr/bin/env python3
"""Automated dimensional and animation audit for the open Level 06 blend."""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy


ROOT = Path(bpy.path.abspath("//")).parents[1]
OUT = ROOT / "docs/level06_v2_automated_audit.json"


def close(a: float, b: float, tolerance: float = 1e-4) -> bool:
    return abs(float(a) - float(b)) <= tolerance


def main() -> None:
    scene = bpy.context.scene
    required = [
        "R01_Segment_00", "P01_Deck", "B01_Deck", "B02_Deck", "B03_Deck",
        "B04_Movable", "B05_Deck", "L01_PLATFORM_PIVOT", "L02_PLATFORM_PIVOT",
        "T01_GlassShell", "T02_GlassShell", "M01_FLYWHEEL_PIVOT",
        "M01_ROTOR_CORE_PIVOT", "P02_GoldenReceiver", "DEMO_ROUTE_BALL",
    ]
    missing = [name for name in required if name not in bpy.data.objects]
    checks: dict[str, bool] = {
        "required_objects_present": not missing,
        "metric_scene_units": scene.unit_settings.system == "METRIC" and close(scene.unit_settings.scale_length, 1.0),
    }
    if not missing:
        t1 = bpy.data.objects["T01_GlassShell"]
        t2 = bpy.data.objects["T02_GlassShell"]
        checks.update({
            "tube_T01_outer_diameter": close(t1["outer_diameter_m"], 1.85),
            "tube_T01_inner_diameter": close(t1["inner_diameter_m"], 1.65),
            "tube_T01_ball_clearance": close(t1["radial_clearance_m"], 0.325),
            "tube_T02_outer_diameter": close(t2["outer_diameter_m"], 1.85),
            "platform_P01_diameter": close(bpy.data.objects["P01_Deck"]["platform_diameter_m"], 7.2),
            "platform_P02_diameter": close(bpy.data.objects["P02_Deck"]["platform_diameter_m"], 7.2),
            "flywheel_diameter": close(bpy.data.objects["M01_FLYWHEEL_PIVOT"]["diameter_m"], 7.0),
            "lift_L01_travel": close(bpy.data.objects["L01_PLATFORM_PIVOT"]["travel_m"], 5.0),
            "lift_L02_travel": close(bpy.data.objects["L02_PLATFORM_PIVOT"]["travel_m"], 3.0),
        })
        for bridge in ("B01_Deck", "B02_Deck", "B03_Deck", "B04_Movable", "B05_Deck"):
            checks[f"{bridge}_width"] = close(bpy.data.objects[bridge]["walkable_width_m"], 2.8)
        scene.frame_set(1)
        l01_bottom = bpy.data.objects["L01_PLATFORM_PIVOT"].matrix_world.translation.z
        l02_bottom = bpy.data.objects["L02_PLATFORM_PIVOT"].matrix_world.translation.z
        scene.frame_set(90)
        l01_top = bpy.data.objects["L01_PLATFORM_PIVOT"].matrix_world.translation.z
        l02_top = bpy.data.objects["L02_PLATFORM_PIVOT"].matrix_world.translation.z
        checks["lift_L01_animation_range"] = close(l01_bottom, 4.5) and close(l01_top, 9.5)
        checks["lift_L02_animation_range"] = close(l02_bottom, 9.5) and close(l02_top, 12.5)
        scene.frame_set(1)
    required_actions = {f"ANIM_{i:02d}" for i in range(1, 11)}
    action_names = sorted(a.name for a in bpy.data.actions)
    action_prefixes = {name[:7] for name in action_names if name.startswith("ANIM_")}
    checks["ten_animation_categories"] = required_actions.issubset(action_prefixes)
    result = {
        "passed": all(checks.values()),
        "checks": checks,
        "missing_objects": missing,
        "actions": action_names,
        "object_count": len(scene.objects),
        "note": "This is a Blender geometry/animation audit, not a Godot physics test.",
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    if not result["passed"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
