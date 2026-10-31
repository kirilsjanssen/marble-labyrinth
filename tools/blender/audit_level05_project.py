"""Read-only helper: projects audit points into the render cameras (pixels).

    blender -b assets/blender/level05_alpine_watermill.blend -P tools/blender/audit_level05_project.py -- <points.json> <out.json>
"""
import json
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
points = json.load(open(args[0], encoding="utf-8"))
scene = bpy.context.scene
scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
out = {}
for cam_name in ("Cam_01_Isometric", "Cam_02_Top"):
    cam = bpy.data.objects[cam_name]
    out[cam_name] = {}
    for key, xyz in points.items():
        co = world_to_camera_view(scene, cam, Vector(xyz))
        out[cam_name][key] = [round(co.x * 1920, 1), round((1.0 - co.y) * 1080, 1), round(co.z, 2)]
json.dump(out, open(args[1], "w", encoding="utf-8"), indent=1)
print("PROJECTED", len(points))
