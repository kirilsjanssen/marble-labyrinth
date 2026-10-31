"""Non-destructive v5 material/light patch for the existing Level 05 blend.

Usage:
  blender -b assets/blender/level05_alpine_watermill.blend \
    -P tools/blender/apply_level05_visual_overhaul.py -- OUTPUT.blend

Geometry, transforms, animation pivots and physics metadata are untouched.
"""
import os
import sys

import bpy


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX = os.path.join(ROOT, "assets", "luma", "level05")


def _set_socket(bsdf, names, value):
    for name in names:
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = value
            return True
    return False


def _principled(material):
    if not material or not material.use_nodes:
        return None
    return next((n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)


def _replace_weathered_textures():
    material = bpy.data.materials.get("Wood_Weathered")
    if not material or not material.use_nodes:
        return 0
    changed = 0
    for node in material.node_tree.nodes:
        if node.type != "TEX_IMAGE" or node.image is None:
            continue
        source = os.path.basename(bpy.path.abspath(node.image.filepath)).lower()
        suffix = None
        if "albedo" in source:
            suffix = "albedo.jpg"
        elif "rough" in source:
            suffix = "rough.jpg"
        elif "normal" in source:
            suffix = "normal.png"
        if suffix:
            path = os.path.join(TEX, "wet_wood_" + suffix)
            node.image = bpy.data.images.load(path, check_existing=True)
            changed += 1
    return changed


def _tune_materials():
    normal_strengths = {
        "Wood_Frame": 0.48, "Wood_Dark": 0.48, "Wood_Plank": 0.52,
        "Deck_Board": 0.52, "Wood_Weathered": 0.38,
        "Stone_Masonry": 0.62, "Stone_Wet": 0.58,
        "Rock_Moss": 0.58, "Roof_Slate": 0.55, "Brass": 0.28,
    }
    for name, strength in normal_strengths.items():
        material = bpy.data.materials.get(name)
        if material and material.use_nodes:
            for node in material.node_tree.nodes:
                if node.type == "NORMAL_MAP":
                    node.inputs["Strength"].default_value = strength
    marble = _principled(bpy.data.materials.get("Marble_Steel"))
    if marble:
        _set_socket(marble, ("Base Color",), (0.62, 0.67, 0.72, 1.0))
        _set_socket(marble, ("Metallic",), 0.92)
        _set_socket(marble, ("Roughness",), 0.24)
    for name, strength in (("Water", 0.12), ("Water_Still", 0.08),
                           ("Waterfall_Body", 0.16), ("Waterfall_Foam", 0.18)):
        bsdf = _principled(bpy.data.materials.get(name))
        if bsdf:
            _set_socket(bsdf, ("Emission Strength",), strength)


def _tune_lighting():
    for obj in bpy.data.objects:
        if obj.type == "LIGHT" and obj.data.type == "SUN":
            obj.data.energy = 1.12
            obj.data.color = (1.0, 0.88, 0.72)
            obj.data.angle = 0.0096
    if bpy.context.scene.world and bpy.context.scene.world.use_nodes:
        background = next((n for n in bpy.context.scene.world.node_tree.nodes if n.type == "BACKGROUND"), None)
        if background:
            background.inputs["Strength"].default_value = min(background.inputs["Strength"].default_value, 0.45)
    looks = {item.identifier for item in bpy.context.scene.view_settings.bl_rna.properties["look"].enum_items}
    preferred = "AgX - Medium High Contrast"
    if preferred in looks:
        bpy.context.scene.view_settings.look = preferred
    bpy.context.scene.view_settings.exposure = -0.15


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    output = argv[0] if argv else os.path.join(ROOT, "assets", "blender", "level05_alpine_watermill_visual_v5.blend")
    replaced = _replace_weathered_textures()
    _tune_materials()
    _tune_lighting()
    bpy.context.scene["level05_visual_overhaul"] = "v5_luma_wet_wood_natural_water_soft_morning"
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(output), compress=True)
    print("LEVEL05_VISUAL_OVERHAUL", os.path.abspath(output), "weathered_textures", replaced)


if __name__ == "__main__":
    main()
