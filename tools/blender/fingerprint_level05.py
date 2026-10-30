"""Geometry fingerprint of a Level 05 .blend (read-only).

blender -b --factory-startup FILE.blend -P tools/blender/fingerprint_level05.py -- out.json

Per mesh object: vertex/triangle counts, world bbox and a SHA-1 of the sorted
world-space vertex positions (0.1 mm), plus object transforms. Comparing two
fingerprints proves whether a material/UV pass changed any geometry.
"""
import hashlib
import json
import sys

import bpy

out = sys.argv[sys.argv.index("--") + 1]
deps = bpy.context.evaluated_depsgraph_get()
data = {}
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    # Base mesh, no modifiers: the water Wave modifiers animate on purpose.
    mw = obj.matrix_world
    pts = sorted(tuple(round(c, 4) for c in (mw @ v.co)) for v in obj.data.vertices)
    digest = hashlib.sha1(repr(pts).encode()).hexdigest()
    xs, ys, zs = zip(*pts) if pts else ((0,), (0,), (0,))
    data[obj.name] = {
        "verts": len(pts),
        "tris": sum(len(p.vertices) - 2 for p in obj.data.polygons),
        "bbox": [min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)],
        "sha1": digest,
        "hidden_render": obj.hide_render,
    }
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=1, sort_keys=True)
print("fingerprint", len(data), "meshes ->", out)
