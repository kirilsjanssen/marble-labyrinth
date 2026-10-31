"""Renders the far Alpine layer for Godot: a 360 x 180 equirectangular panorama
of the v4 background only (peaks, mountain forests, cloud/forest cards and the
painted sky), seen from above the board centre.

blender -b --factory-startup assets/blender/level05_alpine_watermill.blend \
    -P tools/blender/render_level05_panorama.py -- OUT.png [width]

Image centre = Blender +Y (= Godot -Z), right = +X, so it maps straight onto
Godot's PanoramaSkyMaterial and stays correct for every camera rotation.
"""
import math
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
width = int(argv[1]) if len(argv) > 1 else 4096
scene = bpy.context.scene

keep = bpy.data.collections.get("Background")


def under(obj, col):
    if col is None:
        return False
    return obj.name in col.all_objects


for obj in bpy.data.objects:
    if obj.type == "MESH" and not under(obj, keep):
        obj.hide_render = True
cam_data = bpy.data.cameras.new("Pano")
cam_data.type = "PANO"
try:
    cam_data.panorama_type = "EQUIRECTANGULAR"
except AttributeError:
    cam_data.cycles.panorama_type = "EQUIRECTANGULAR"
cam = bpy.data.objects.new("Pano", cam_data)
cam.location = (6.0, 6.0, 8.0)
cam.rotation_euler = (math.radians(90), 0.0, 0.0)
scene.collection.objects.link(cam)
scene.camera = cam
scene.render.resolution_x = width
scene.render.resolution_y = width // 2
scene.render.resolution_percentage = 100
scene.cycles.samples = 96
scene.view_settings.exposure = -0.7
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("panorama", out)
