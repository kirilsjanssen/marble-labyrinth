"""Level 05 — Alpine Watermill. Procedural Blender 5.x scene built from the
owner's reference art (assets/blender/reference_level05.png).

Run headless:
    blender -b --factory-startup -P tools/blender/build_level05.py -- --save --render [--samples 192]

1 Blender unit = 1 metre = 1 Godot unit. Z is up (glTF export converts to Y-up).
Play floors: LOWER z=0.0, MIDDLE z=1.4, UPPER z=2.8 (deck tops). Every lane is
at least 1.0 m wide for a 0.33 m marble. Mechanisms are separate objects with
their pivot at the rotation axis so Godot can drive them.
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND_PATH = os.path.join(ROOT, "assets", "blender", "level05_alpine_watermill.blend")
RENDER_DIR = os.path.join(ROOT, "assets", "blender", "renders", "level05")

Z0, Z1, Z2 = 0.0, 1.4, 2.8
DECK_T = 0.24          # floor + joists thickness below the walking surface
CURB_H = 0.22          # timber curb above the floor
RAIL_H = 0.62          # handrail height above the floor
RNG = random.Random(5005)
# v3: UV offsets and per-piece colour jitter draw from their own stream, so the
# layout RNG (board lengths, stone sizes, splash) is exactly the v2 sequence.
UV_RNG = random.Random(5150)
TEX_DIR = os.path.join(ROOT, "assets", "luma", "level05")
TEX_L04 = os.path.join(ROOT, "assets", "luma", "level04")
BOARD_MATS = {"Wood_Plank", "Deck_Board"}
BOARD_BANDS = 8        # single-board bands stacked in wood_board_albedo.jpg
BOARD_LEN = 2.0        # metres of board per texture repeat along the grain


# ----------------------------------------------------------------------------
# Scene and collections
# ----------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    return scene


COLLECTIONS = {}


def collection(path):
    """'L05/Mechanisms/Wheels' -> nested collections created on demand."""
    if path in COLLECTIONS:
        return COLLECTIONS[path]
    parent = bpy.context.scene.collection
    current = ""
    for part in path.split("/"):
        current = part if not current else current + "/" + part
        if current not in COLLECTIONS:
            col = bpy.data.collections.new(part)
            parent.children.link(col)
            COLLECTIONS[current] = col
        parent = COLLECTIONS[current]
    return COLLECTIONS[path]


# ----------------------------------------------------------------------------
# Materials (procedural PBR; nothing reused from Level 04)
# ----------------------------------------------------------------------------

MATS = {}
IMAGES = {}


def _new_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    for node in list(nodes):
        nodes.remove(node)
    out = nodes.new("ShaderNodeOutputMaterial")
    out.location = (600, 0)
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (300, 0)
    mat.node_tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat, bsdf


def _set(bsdf, name, value):
    if name in bsdf.inputs:
        bsdf.inputs[name].default_value = value


def _coords(mat, scale=(1, 1, 1), coord="Object"):
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    tex = nodes.new("ShaderNodeTexCoord")
    tex.location = (-900, 0)
    mapping = nodes.new("ShaderNodeMapping")
    mapping.location = (-700, 0)
    mapping.inputs["Scale"].default_value = scale
    links.new(tex.outputs[coord], mapping.inputs["Vector"])
    return mapping


def _ramp(mat, stops, location=(-150, 0)):
    ramp = mat.node_tree.nodes.new("ShaderNodeValToRGB")
    ramp.location = location
    elements = ramp.color_ramp.elements
    elements[0].position, elements[0].color = stops[0][0], (*stops[0][1], 1.0)
    elements[1].position, elements[1].color = stops[-1][0], (*stops[-1][1], 1.0)
    for position, color in stops[1:-1]:
        element = elements.new(position)
        element.color = (*color, 1.0)
    return ramp


def _bump(mat, height_socket, strength, bsdf, distance=0.02):
    bump = mat.node_tree.nodes.new("ShaderNodeBump")
    bump.location = (100, -300)
    bump.inputs["Strength"].default_value = strength
    bump.inputs["Distance"].default_value = distance
    mat.node_tree.links.new(height_socket, bump.inputs["Height"])
    mat.node_tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


def _image(path, data=False):
    if path not in IMAGES:
        img = bpy.data.images.load(path, check_existing=True)
        if data:
            img.colorspace_settings.name = "Non-Color"
        IMAGES[path] = img
    return IMAGES[path]


def _tex(mat, path, vector, data=False, location=(-800, 0)):
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.location = location
    node.image = _image(path, data)
    mat.node_tree.links.new(vector, node.inputs["Vector"])
    return node


def _math(mat, op, a, b=None, c=None, clamp=False, location=(-300, -500)):
    node = mat.node_tree.nodes.new("ShaderNodeMath")
    node.operation = op
    node.use_clamp = clamp
    node.location = location
    for i, v in enumerate((a, b, c)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            node.inputs[i].default_value = v
        else:
            mat.node_tree.links.new(v, node.inputs[i])
    return node.outputs[0]


def _sock(sockets, identifier):
    return next(x for x in sockets if x.identifier == identifier)


def _mix(mat, factor, a, b, blend="MIX", location=(-150, 250)):
    """RGBA Mix node; factor/a/b are sockets or constants."""
    node = mat.node_tree.nodes.new("ShaderNodeMix")
    node.data_type = "RGBA"
    node.blend_type = blend
    node.location = location
    for ident, v in (("Factor_Float", factor), ("A_Color", a), ("B_Color", b)):
        sock = _sock(node.inputs, ident)
        if isinstance(v, (int, float)):
            sock.default_value = v
        elif isinstance(v, tuple):
            sock.default_value = (*v[:3], 1.0)
        else:
            mat.node_tree.links.new(v, sock)
    return _sock(node.outputs, "Result_Color")


def _map_range(mat, value, f0, f1, t0=0.0, t1=1.0, location=(-500, -600)):
    node = mat.node_tree.nodes.new("ShaderNodeMapRange")
    node.location = location
    node.clamp = True
    mat.node_tree.links.new(value, node.inputs["Value"])
    for name, v in (("From Min", f0), ("From Max", f1), ("To Min", t0), ("To Max", t1)):
        node.inputs[name].default_value = v
    return node.outputs["Result"]


def _uv_mapping(mat, scale=(1.0, 1.0), location=(-1100, 0)):
    nodes = mat.node_tree.nodes
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "UVMap"
    uv.location = (location[0] - 200, location[1])
    mapping = nodes.new("ShaderNodeMapping")
    mapping.location = location
    mapping.inputs["Scale"].default_value = (scale[0], scale[1], 1.0)
    mat.node_tree.links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    return mapping


def _scroll(mapping, axis, speed):
    """Animates a Mapping location (texture units per second at 24 fps) with a
    `frame` driver: cheap, deterministic and mirrored 1:1 by a Godot UV offset."""
    fcurve = mapping.inputs["Location"].driver_add("default_value", axis)
    fcurve.driver.type = "SCRIPTED"
    fcurve.driver.expression = "frame*%.6f" % (speed / 24.0)


def mat_pbr(name, key, tile=1.0, hue=0.0, sat=1.0, val=1.0, jitter=(0.015, 0.1, 0.2), rough=(1.0, 0.0), metal=0.0,
            normal=1.0, board=False, up=None):
    """Image PBR from the Level 05 Luma set (assets/luma/level05: albedo from
    Luma, normal/roughness derived - see PROVENANCE.json). Builder UVs are
    metres per piece with U along its longest side, so `tile` is the repeat in
    metres (boards use the board atlas instead). l05_rand (one value per
    piece) jitters hue/saturation/value so beams, boards and stones differ."""
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    mapping = _uv_mapping(mat, (1.0, 1.0) if board else (1.0 / tile, 1.0 / tile))
    vec = mapping.outputs["Vector"]
    base = os.path.join(TEX_DIR, key)
    albedo = _tex(mat, base + "_albedo.jpg", vec, location=(-800, 300))
    rough_t = _tex(mat, base + "_rough.jpg", vec, True, (-800, 0))
    normal_t = _tex(mat, base + "_normal.png", vec, True, (-800, -300))
    rnd = nodes.new("ShaderNodeAttribute")
    rnd.attribute_type = "GEOMETRY"
    rnd.attribute_name = "l05_rand"
    rnd.location = (-800, 600)
    hsv = nodes.new("ShaderNodeHueSaturation")
    hsv.location = (-450, 300)
    for socket, centre, amount in (("Hue", 0.5 + hue, jitter[0]), ("Saturation", sat, jitter[1]), ("Value", val, jitter[2])):
        links.new(_math(mat, "MULTIPLY_ADD", rnd.outputs["Fac"], 2.0 * amount, centre - amount), hsv.inputs[socket])
    links.new(albedo.outputs["Color"], hsv.inputs["Color"])
    color = hsv.outputs["Color"]
    if up:
        # Moss/grass on up-facing surfaces, broken up by noise.
        up_color, lo, hi = up
        geo = nodes.new("ShaderNodeNewGeometry")
        sep = nodes.new("ShaderNodeSeparateXYZ")
        links.new(geo.outputs["Normal"], sep.inputs["Vector"])
        breakup = nodes.new("ShaderNodeTexNoise")
        breakup.inputs["Scale"].default_value = 0.45
        breakup.inputs["Detail"].default_value = 6.0
        links.new(geo.outputs["Position"], breakup.inputs["Vector"])
        f = _math(mat, "MULTIPLY_ADD", breakup.outputs["Fac"], 0.7, sep.outputs["Z"])
        color = _mix(mat, _map_range(mat, f, lo + 0.35, hi + 0.35), color, _mix(mat, 1.0, color, up_color, "MULTIPLY"))
    links.new(color, bsdf.inputs["Base Color"])
    links.new(_math(mat, "MULTIPLY_ADD", rough_t.outputs["Color"], rough[0], rough[1], clamp=True), bsdf.inputs["Roughness"])
    nmap = nodes.new("ShaderNodeNormalMap")
    nmap.uv_map = "UVMap"
    nmap.location = (-300, -300)
    nmap.inputs["Strength"].default_value = normal
    links.new(normal_t.outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    _set(bsdf, "Metallic", metal)
    MATS[name] = mat
    return mat


def mat_simple(name, color, rough=0.5, metal=0.0, emission=None, strength=0.0, alpha=1.0):
    mat, bsdf = _new_material(name)
    _set(bsdf, "Base Color", (*color, 1.0))
    _set(bsdf, "Roughness", rough)
    _set(bsdf, "Metallic", metal)
    if emission:
        _set(bsdf, "Emission Color", (*emission, 1.0))
        _set(bsdf, "Emission Strength", strength)
    MATS[name] = mat
    return mat


def mat_metal(name, color, rough=0.3):
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    mapping = _coords(mat, (6, 6, 6))
    wear = nodes.new("ShaderNodeTexNoise")
    wear.location = (-500, 0)
    wear.inputs["Scale"].default_value = 5.0
    wear.inputs["Detail"].default_value = 8.0
    links.new(mapping.outputs["Vector"], wear.inputs["Vector"])
    ramp = _ramp(mat, [(0.35, tuple(c * 0.8 for c in color)), (0.65, color)])
    links.new(wear.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    _set(bsdf, "Metallic", 1.0)
    rough_ramp = _ramp(mat, [(0.3, (rough * 0.6,) * 3), (0.7, (rough * 1.5,) * 3)], (-150, -250))
    links.new(wear.outputs["Fac"], rough_ramp.inputs["Fac"])
    links.new(rough_ramp.outputs["Color"], bsdf.inputs["Roughness"])
    MATS[name] = mat
    return mat


# Water: every layer scrolls along +U (downstream) / -V (down a fall) at its
# own speed; the same numbers go to assets/luma/level05/level05_water_params.json.
WATER_LAYERS = {
    "channel": {"tile_a": 1.6, "speed_a": 0.45, "tile_b": 0.9, "speed_b": 0.75, "ripple_speed": 0.5},
    "still": {"tile_a": 2.4, "speed_a": 0.04, "tile_b": 1.3, "speed_b": 0.07, "ripple_speed": 0.15},
    "fall_body": {"tile_u": 0.6, "tile_v": 1.2, "speed_a": 1.7, "speed_b": 2.4},
    "fall_foam": {"tile_u": 0.5, "tile_v": 0.9, "speed_a": 2.8, "speed_b": 2.1},
}
WATER_COLOR = (0.02, 0.36, 0.40)


def mat_water_surface(name, layers):
    """Translucent turquoise water: two scrolling samples of the Level 04
    Luma water/foam texture (different scale and speed, so the repeat never
    lines up), foam from their brightness, animated 4D-noise ripples."""
    p = WATER_LAYERS[layers]
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    foam_path = os.path.join(TEX_L04, "water_foam.jpg")
    map_a = _uv_mapping(mat, (1.0 / p["tile_a"], 1.0 / p["tile_a"]), (-1100, 200))
    map_b = _uv_mapping(mat, (1.0 / p["tile_b"], 1.0 / p["tile_b"]), (-1100, -200))
    map_b.inputs["Rotation"].default_value = (0.0, 0.0, 0.35)
    _scroll(map_a, 0, -p["speed_a"] / p["tile_a"])
    _scroll(map_b, 0, -p["speed_b"] / p["tile_b"])
    tex_a = _tex(mat, foam_path, map_a.outputs["Vector"], location=(-800, 200))
    tex_b = _tex(mat, foam_path, map_b.outputs["Vector"], location=(-800, -200))
    both = _mix(mat, 0.5, tex_a.outputs["Color"], tex_b.outputs["Color"])
    bw = nodes.new("ShaderNodeRGBToBW")
    links.new(both, bw.inputs["Color"])
    foam = _map_range(mat, bw.outputs["Val"], 0.62, 0.9)
    body = _mix(mat, 0.45, WATER_COLOR, both, "MULTIPLY")
    body = _mix(mat, 0.5, body, WATER_COLOR)
    color = _mix(mat, foam, body, (0.9, 0.96, 1.0))
    links.new(color, bsdf.inputs["Base Color"])
    links.new(_math(mat, "MULTIPLY_ADD", foam, 0.45, 0.03), bsdf.inputs["Roughness"])
    links.new(_math(mat, "MULTIPLY_ADD", foam, -0.7, 0.85), bsdf.inputs["Transmission Weight"])
    _set(bsdf, "IOR", 1.333)
    # Self-glow keeps shallow channels turquoise from above (dark beds behind).
    links.new(body, bsdf.inputs["Emission Color"])
    _set(bsdf, "Emission Strength", 0.55)
    ripples = nodes.new("ShaderNodeTexNoise")
    ripples.noise_dimensions = "4D"
    ripples.inputs["Scale"].default_value = 5.0
    ripples.inputs["Detail"].default_value = 4.0
    fc = ripples.inputs["W"].driver_add("default_value")
    fc.driver.type = "SCRIPTED"
    fc.driver.expression = "frame*%.6f" % (p["ripple_speed"] / 24.0)
    links.new(map_a.outputs["Vector"], ripples.inputs["Vector"])
    _bump(mat, ripples.outputs["Fac"], 0.18, bsdf, 0.02)
    MATS[name] = mat
    return mat


def mat_waterfall(name, layer):
    """Falling water layer. body: Luma waterfall streaks (RGBA) twice at two
    speeds; foam: the derived foam mask as alpha, faster, in front."""
    p = WATER_LAYERS[layer]
    mat, bsdf = _new_material(name)
    links = mat.node_tree.links
    if layer == "fall_body":
        img, data = os.path.join(TEX_DIR, "waterfall_streaks.png"), False
    else:
        img, data = os.path.join(TEX_DIR, "waterfall_foam_mask.png"), True
    map_a = _uv_mapping(mat, (1.0 / p["tile_u"], 1.0 / p["tile_v"]), (-1100, 200))
    map_b = _uv_mapping(mat, (1.0 / (p["tile_u"] * 1.6), 1.0 / (p["tile_v"] * 1.5)), (-1100, -200))
    map_b.inputs["Location"].default_value = (0.37, 0.0, 0.0)
    _scroll(map_a, 1, p["speed_a"] / p["tile_v"])
    _scroll(map_b, 1, p["speed_b"] / (p["tile_v"] * 1.5))
    tex_a = _tex(mat, img, map_a.outputs["Vector"], data, (-800, 200))
    tex_b = _tex(mat, img, map_b.outputs["Vector"], data, (-800, -200))
    if layer == "fall_body":
        color = _mix(mat, 0.5, tex_a.outputs["Color"], tex_b.outputs["Color"])
        color = _mix(mat, 0.25, color, WATER_COLOR)
        alpha = _math(mat, "MULTIPLY", _math(mat, "MAXIMUM", tex_a.outputs["Alpha"], tex_b.outputs["Alpha"]), 0.88)
        links.new(color, bsdf.inputs["Base Color"])
        links.new(color, bsdf.inputs["Emission Color"])
        _set(bsdf, "Emission Strength", 0.4)
        _set(bsdf, "Roughness", 0.12)
        _set(bsdf, "Transmission Weight", 0.35)
    else:
        alpha = _math(mat, "MULTIPLY", _math(mat, "MAXIMUM", tex_a.outputs["Color"], tex_b.outputs["Color"]), 0.95, clamp=True)
        _set(bsdf, "Base Color", (0.92, 0.97, 1.0, 1.0))
        _set(bsdf, "Emission Color", (0.85, 0.95, 1.0, 1.0))
        _set(bsdf, "Emission Strength", 0.45)
        _set(bsdf, "Roughness", 0.45)
    links.new(alpha, bsdf.inputs["Alpha"])
    _set(bsdf, "IOR", 1.333)
    MATS[name] = mat
    return mat


def mat_spray(name, alpha_scale, mist=False):
    """White water: churned foam blobs, flat foam patches, soft spray cards."""
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    noise_t = nodes.new("ShaderNodeTexNoise")
    noise_t.noise_dimensions = "4D"
    noise_t.inputs["Scale"].default_value = 9.0 if not mist else 3.5
    noise_t.inputs["Detail"].default_value = 6.0
    fc = noise_t.inputs["W"].driver_add("default_value")
    fc.driver.type = "SCRIPTED"
    fc.driver.expression = "frame*0.05"
    geo = nodes.new("ShaderNodeNewGeometry")
    links.new(geo.outputs["Position"], noise_t.inputs["Vector"])
    alpha = _map_range(mat, noise_t.outputs["Fac"], 0.35, 0.7, 0.25, 1.0)
    if mist:
        # Radial falloff on the card's 0..1 UVs.
        uv = nodes.new("ShaderNodeUVMap")
        uv.uv_map = "UVMap"
        sep = nodes.new("ShaderNodeSeparateXYZ")
        links.new(uv.outputs["UV"], sep.inputs["Vector"])
        dx = _math(mat, "SUBTRACT", sep.outputs["X"], 0.5)
        dy = _math(mat, "SUBTRACT", sep.outputs["Y"], 0.35)
        d = _math(mat, "SQRT", _math(mat, "ADD", _math(mat, "MULTIPLY", dx, dx), _math(mat, "MULTIPLY", dy, dy)))
        alpha = _math(mat, "MULTIPLY", alpha, _map_range(mat, d, 0.5, 0.1))
    links.new(_math(mat, "MULTIPLY", alpha, alpha_scale), bsdf.inputs["Alpha"])
    _set(bsdf, "Base Color", (0.9, 0.96, 1.0, 1.0))
    _set(bsdf, "Roughness", 0.5)
    _set(bsdf, "Emission Color", (0.85, 0.95, 1.0, 1.0))
    _set(bsdf, "Emission Strength", 0.35)
    _set(bsdf, "Subsurface Weight", 0.2 if not mist else 0.0)
    MATS[name] = mat
    return mat


def mat_mountain(name):
    """Distant peaks: granite (rock texture, 22 m repeat, greyed), snow only
    on high and gentle slopes (altitude + steepness + noise), forest-dark
    lower flanks, and aerial haze by camera distance."""
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    mapping = _uv_mapping(mat, (1.0 / 22.0, 1.0 / 22.0))
    albedo = _tex(mat, os.path.join(TEX_DIR, "rock_moss_albedo.jpg"), mapping.outputs["Vector"], location=(-800, 300))
    normal_t = _tex(mat, os.path.join(TEX_DIR, "rock_moss_normal.png"), mapping.outputs["Vector"], True, (-800, -300))
    hsv = nodes.new("ShaderNodeHueSaturation")
    hsv.inputs["Saturation"].default_value = 0.55
    hsv.inputs["Value"].default_value = 0.42
    links.new(albedo.outputs["Color"], hsv.inputs["Color"])
    geo = nodes.new("ShaderNodeNewGeometry")
    sep_n = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Normal"], sep_n.inputs["Vector"])
    sep_p = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Position"], sep_p.inputs["Vector"])
    breakup = nodes.new("ShaderNodeTexNoise")
    breakup.inputs["Scale"].default_value = 0.035
    breakup.inputs["Detail"].default_value = 8.0
    links.new(geo.outputs["Position"], breakup.inputs["Vector"])
    alt = _map_range(mat, sep_p.outputs["Z"], -74.0, -28.0)
    s1 = _math(mat, "MULTIPLY_ADD", alt, 0.95, sep_n.outputs["Z"])
    s2 = _math(mat, "MULTIPLY_ADD", breakup.outputs["Fac"], 0.8, s1)
    snow = _map_range(mat, s2, 1.95, 2.12)
    forest = _math(mat, "MULTIPLY", _map_range(mat, sep_p.outputs["Z"], -70.0, -84.0), _map_range(mat, sep_n.outputs["Z"], 0.45, 0.75))
    color = _mix(mat, forest, hsv.outputs["Color"], (0.02, 0.045, 0.025))
    color = _mix(mat, snow, color, (0.86, 0.9, 0.97))
    cam = nodes.new("ShaderNodeCameraData")
    haze = _map_range(mat, cam.outputs["View Distance"], 80.0, 330.0, 0.06, 0.45)
    haze_color = (0.56, 0.68, 0.86)
    color = _mix(mat, haze, color, haze_color)
    links.new(color, bsdf.inputs["Base Color"])
    _set(bsdf, "Emission Color", (*haze_color, 1.0))
    links.new(_math(mat, "MULTIPLY", haze, 0.25), bsdf.inputs["Emission Strength"])
    links.new(_math(mat, "MULTIPLY_ADD", snow, -0.4, 0.88), bsdf.inputs["Roughness"])
    nmap = nodes.new("ShaderNodeNormalMap")
    nmap.uv_map = "UVMap"
    nmap.inputs["Strength"].default_value = 1.5
    links.new(normal_t.outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    MATS[name] = mat
    return mat


def mat_card(name, image, strength, haze=0.0, haze_color=(0.56, 0.68, 0.86)):
    """Unlit painted backdrop layer (Luma parallax image with alpha): the same
    images become Godot's parallax planes later."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    for node in list(nodes):
        nodes.remove(node)
    out = nodes.new("ShaderNodeOutputMaterial")
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "UVMap"
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = _image(image)
    tex.extension = "CLIP"
    links.new(uv.outputs["UV"], tex.inputs["Vector"])
    color = _mix(mat, haze, tex.outputs["Color"], haze_color)
    # Fade the card's sides and bottom so no hard quad edge ever shows.
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(uv.outputs["UV"], sep.inputs["Vector"])
    side = _math(mat, "MINIMUM", sep.outputs["X"], _math(mat, "SUBTRACT", 1.0, sep.outputs["X"]))
    fade = _math(mat, "MULTIPLY", _map_range(mat, side, 0.0, 0.12), _map_range(mat, sep.outputs["Y"], 0.0, 0.15))
    alpha = _math(mat, "MULTIPLY", tex.outputs["Alpha"], fade)
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = strength
    links.new(color, emit.inputs["Color"])
    clear = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(alpha, mix.inputs["Fac"])
    links.new(clear.outputs["BSDF"], mix.inputs[1])
    links.new(emit.outputs["Emission"], mix.inputs[2])
    links.new(mix.outputs["Shader"], out.inputs["Surface"])
    MATS[name] = mat
    return mat


def build_materials():
    # Timber: aged dark oak (Luma) graded per role; decks use the board atlas.
    mat_pbr("Wood_Frame", "wood_beam", 1.4, hue=0.008, sat=1.2, val=1.75, jitter=(0.012, 0.12, 0.3), normal=0.9)
    mat_pbr("Wood_Plank", "wood_board", board=True, sat=1.05, val=0.95, jitter=(0.012, 0.1, 0.25), normal=0.8)
    mat_pbr("Deck_Board", "wood_board", board=True, sat=1.0, val=0.92, jitter=(0.015, 0.12, 0.3), normal=0.8)
    mat_pbr("Wood_Dark", "wood_beam", 1.4, sat=1.0, val=0.85, jitter=(0.01, 0.1, 0.2))
    mat_pbr("Wood_Weathered", "wood_beam", 1.2, hue=-0.01, sat=0.8, val=1.45, jitter=(0.01, 0.12, 0.3), rough=(1.0, 0.06))
    # Stone: wet granite masonry with mossy joints; corridor flags polished darker.
    mat_pbr("Slate_Floor", "stone_masonry", 1.6, sat=0.7, val=0.55, jitter=(0.01, 0.1, 0.2), rough=(0.75, 0.0))
    mat_pbr("Stone_Masonry", "stone_masonry", 2.2, sat=1.0, val=0.95, jitter=(0.015, 0.15, 0.3))
    mat_pbr("Stone_Wet", "stone_masonry", 2.2, sat=1.15, val=0.62, jitter=(0.01, 0.1, 0.2), rough=(0.55, 0.0))
    mat_pbr("Rock_Moss", "rock_moss", 3.0, val=0.85, jitter=(0.01, 0.1, 0.15), normal=1.3, up=((0.42, 0.72, 0.2), 0.55, 0.85))
    # Metals: brass is fully metallic with the golden albedo as its F0.
    mat_pbr("Brass", "brass", 0.8, val=1.0, jitter=(0.008, 0.08, 0.12), rough=(0.85, 0.0), metal=1.0, normal=0.5)
    mat_metal("Iron", (0.20, 0.20, 0.21), 0.45)
    mat_simple("Red_Paint", (0.55, 0.05, 0.03), 0.35)
    mat_pbr("Roof_Slate", "roof_slate", 2.4, sat=0.9, val=0.36, jitter=(0.03, 0.2, 0.25))
    mat_pbr("Roof_Shingle", "roof_slate", 2.4, hue=0.03, sat=1.5, val=0.32, jitter=(0.03, 0.2, 0.2))
    mat_simple("Window_Glow", (1.0, 0.62, 0.25), 0.3, emission=(1.0, 0.55, 0.18), strength=9.0)
    mat_simple("Lantern_Glow", (1.0, 0.7, 0.3), 0.2, emission=(1.0, 0.52, 0.16), strength=9.0)
    gold = mat_pbr("Goal_Gold", "brass", 0.6, val=1.08, jitter=(0.0, 0.0, 0.0), rough=(0.6, 0.0), metal=1.0, normal=0.4)
    bsdf = gold.node_tree.nodes["Principled BSDF"]
    _set(bsdf, "Emission Color", (1.0, 0.66, 0.2, 1.0))
    _set(bsdf, "Emission Strength", 0.6)
    mat_simple("Plate_White", (0.85, 0.82, 0.78), 0.4)
    mat_simple("Banner_Red", (0.45, 0.03, 0.03), 0.7)
    grass = mat_simple("Grass", (0.07, 0.17, 0.03), 0.85)
    _set(grass.node_tree.nodes["Principled BSDF"], "Subsurface Weight", 0.1)
    mat_pbr("Bark", "wood_beam", 0.7, sat=0.9, val=0.7)
    mat_pbr("Fir_Needles", "fir_needles", 0.3, sat=1.15, val=1.1, jitter=(0.025, 0.15, 0.35))
    mat_pbr("Fir_Needles_Far", "fir_needles", 0.5, hue=0.03, sat=0.8, val=1.15, jitter=(0.02, 0.1, 0.3))
    mat_water_surface("Water", "channel")
    mat_water_surface("Water_Still", "still")
    mat_waterfall("Waterfall_Body", "fall_body")
    mat_waterfall("Waterfall_Foam", "fall_foam")
    mat_spray("Water_Spray", 0.9)
    mat_spray("Water_FoamPatch", 0.8)
    mat_spray("Water_Mist", 0.45, mist=True)
    mat_mountain("Mountain_Snow")
    mat_card("Cloud_Card", os.path.join(TEX_DIR, "parallax", "cloud_bank.png"), 2.0, haze=0.05)
    mat_card("Forest_Card", os.path.join(TEX_DIR, "parallax", "mid_forest_slopes.png"), 0.55, haze=0.4)
    mat_simple("Marble_Steel", (0.8, 0.82, 0.85), 0.08, metal=1.0)


# ----------------------------------------------------------------------------
# Mesh builder
# ----------------------------------------------------------------------------

class Builder:
    """Accumulates beveled primitives into one bmesh, then makes one object."""

    def __init__(self, name, coll):
        self.name = name
        self.coll = coll
        self.bm = bmesh.new()
        self.materials = []
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.rand = self.bm.faces.layers.float.new("l05_rand")
        self.has_uv = self.bm.faces.layers.int.new("l05_uv")

    def _mi(self, mat_name):
        mat = MATS[mat_name]
        if mat not in self.materials:
            self.materials.append(mat)
        return self.materials.index(mat)

    def _finish_faces(self, faces, mat_name, smooth):
        index = self._mi(mat_name)
        for face in faces:
            face.material_index = index
            face.smooth = smooth

    def box(self, center, size, mat, rot=(0.0, 0.0, 0.0), bevel=0.02, smooth=False):
        size = Vector(size)
        matrix = Matrix.Translation(Vector(center)) @ _euler(rot) @ Matrix.Diagonal((*size, 1.0))
        result = bmesh.ops.create_cube(self.bm, size=1.0, matrix=matrix)
        verts = result["verts"]
        faces = list({f for v in verts for f in v.link_faces})
        if bevel > 0.0:
            edges = list({e for f in faces for e in f.edges})
            offset = min(bevel, min(size) * 0.45)
            bev = bmesh.ops.bevel(self.bm, geom=edges + verts, offset=offset, segments=1, profile=0.5, affect="EDGES", clamp_overlap=True)
            faces = list({f for v in bev["verts"] for f in v.link_faces} | set(bev["faces"]) | set(f for f in faces if f.is_valid))
        faces = [f for f in faces if f.is_valid]
        self._finish_faces(faces, mat, smooth)
        self.box_uv(faces, _euler(rot).to_3x3(), Vector(center), size, mat)

    def box_uv(self, faces, rot, center, size, mat):
        """Per-piece UVs in metres: U runs along the piece's longest in-face
        axis (grain along beams and boards), each piece gets its own random
        texture offset and l05_rand value. Boards map across onto one band of
        the board atlas, so no fake gap ever crosses a real board."""
        inv = rot.transposed()
        off_u, off_v = UV_RNG.uniform(0.0, 8.0), UV_RNG.uniform(0.0, 8.0)
        rnd = UV_RNG.random()
        band = UV_RNG.randrange(BOARD_BANDS)
        for f in faces:
            f.normal_update()
            n = inv @ f.normal
            k = max(range(3), key=lambda i: abs(n[i]))
            a, c = [i for i in range(3) if i != k]
            ua, va = (a, c) if size[a] >= size[c] else (c, a)
            for loop in f.loops:
                p = inv @ (loop.vert.co - center)
                if mat in BOARD_MATS:
                    across = max(size[va], 1e-4)
                    count = max(1, round(across / 0.3))
                    loop[self.uv].uv = (p[ua] / BOARD_LEN + off_u, ((p[va] / across + 0.5) * count + band) / BOARD_BANDS)
                else:
                    loop[self.uv].uv = (p[ua] + off_u, p[va] + off_v)
            f[self.rand] = rnd
            f[self.has_uv] = 1

    def _face_uv(self, f):
        """Fallback for non-box faces: planar projection on the dominant axis,
        U along the face's longest edge; l05_rand varies smoothly in space."""
        n = f.normal
        k = max(range(3), key=lambda i: abs(n[i]))
        a, c = [i for i in range(3) if i != k]
        edge = max(f.edges, key=lambda e: e.calc_length())
        d = edge.verts[1].co - edge.verts[0].co
        if abs(d[c]) > abs(d[a]):
            a, c = c, a
        for loop in f.loops:
            loop[self.uv].uv = (loop.vert.co[a], loop.vert.co[c])
        f[self.rand] = noise.noise(f.calc_center_median() * 0.9 + Vector((0.31, 0.77, 0.13))) * 0.5 + 0.5

    def cylinder(self, center, radius, depth, mat, axis="Z", segments=16, radius2=None, rot=None, smooth=True, caps=True):
        matrix = Matrix.Translation(Vector(center)) @ (_euler(rot) if rot else _axis_matrix(axis))
        result = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segments, radius1=radius,
                                       radius2=radius if radius2 is None else radius2, depth=depth, matrix=matrix)
        faces = list({f for v in result["verts"] for f in v.link_faces})
        for face in faces:
            face.material_index = self._mi(mat)
            # Caps stay flat; the sides shade smoothly.
            face.smooth = smooth and len(face.verts) == 4
        return faces

    def torus(self, center, major, minor, mat, axis="Z", seg_major=24, seg_minor=8):
        transform = Matrix.Translation(Vector(center)) @ _axis_matrix(axis)
        rings = []
        for i in range(seg_major):
            a = i / seg_major * math.tau
            ring = []
            for j in range(seg_minor):
                b = j / seg_minor * math.tau
                local = Vector(((major + minor * math.cos(b)) * math.cos(a), (major + minor * math.cos(b)) * math.sin(a), minor * math.sin(b)))
                ring.append(self.bm.verts.new(transform @ local))
            rings.append(ring)
        faces = []
        for i in range(seg_major):
            for j in range(seg_minor):
                a, b = rings[i], rings[(i + 1) % seg_major]
                faces.append(self.bm.faces.new((a[j], b[j], b[(j + 1) % seg_minor], a[(j + 1) % seg_minor])))
        self._finish_faces(faces, mat, True)

    def polygon_prism(self, outline, z0, z1, mat, transform=Matrix.Identity(4), smooth=False, top_scale=1.0):
        """Extrudes a 2D outline (counter-clockwise, XY) from z0 to z1; a
        top_scale < 1 tapers it into a cone frustum (bevel gear teeth)."""
        bottom = [self.bm.verts.new(transform @ Vector((x, y, z0))) for x, y in outline]
        top = [self.bm.verts.new(transform @ Vector((x * top_scale, y * top_scale, z1))) for x, y in outline]
        faces = [self.bm.faces.new(list(reversed(bottom))), self.bm.faces.new(top)]
        n = len(outline)
        for i in range(n):
            faces.append(self.bm.faces.new((bottom[i], bottom[(i + 1) % n], top[(i + 1) % n], top[i])))
        self._finish_faces(faces, mat, smooth)

    def raw(self, verts, faces, mat, smooth=True, uvs=None):
        bverts = [self.bm.verts.new(v) for v in verts]
        made = [self.bm.faces.new([bverts[i] for i in f]) for f in faces]
        self._finish_faces(made, mat, smooth)
        if uvs is not None:
            rnd = UV_RNG.random()
            for face, idx in zip(made, faces):
                for loop, i in zip(face.loops, idx):
                    loop[self.uv].uv = uvs[i]
                face[self.rand] = rnd
                face[self.has_uv] = 1

    def finish(self, origin=(0.0, 0.0, 0.0)):
        origin = Vector(origin)
        if origin.length > 0.0:
            bmesh.ops.translate(self.bm, verts=self.bm.verts, vec=-origin)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        for face in self.bm.faces:
            if not face[self.has_uv]:
                self._face_uv(face)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        if "l05_uv" in mesh.attributes:
            mesh.attributes.remove(mesh.attributes["l05_uv"])
        for mat in self.materials:
            mesh.materials.append(mat)
        obj = bpy.data.objects.new(self.name, mesh)
        obj.location = origin
        self.coll.objects.link(obj)
        if len(mesh.uv_layers) == 0:
            _box_uv(obj)
        return obj


def _euler(rot):
    from mathutils import Euler
    return Euler(rot, "XYZ").to_matrix().to_4x4()


def _axis_matrix(axis):
    if axis == "X":
        return Matrix.Rotation(math.pi / 2, 4, "Y")
    if axis == "Y":
        return Matrix.Rotation(math.pi / 2, 4, "X")
    return Matrix.Identity(4)


def _box_uv(obj):
    """Cube-projection UVs in metres (1 UV unit = 1 m) for every face."""
    mesh = obj.data
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        n = poly.normal
        axis = max(range(3), key=lambda k: abs(n[k]))
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            if axis == 0:
                uv.data[li].uv = (co.y, co.z)
            elif axis == 1:
                uv.data[li].uv = (co.x, co.z)
            else:
                uv.data[li].uv = (co.x, co.y)


def empty(name, location, coll, kind="PLAIN_AXES", size=0.3):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = kind
    obj.empty_display_size = size
    obj.location = location
    coll.objects.link(obj)
    return obj


# ----------------------------------------------------------------------------
# Layout (metres). X runs screen-right/back, Y screen-left/back in the
# reference's isometric view; the camera looks from (-X, -Y, +Z).
# ----------------------------------------------------------------------------

LIFT = {"x0": 9.0, "x1": 10.6, "y0": 0.2, "y1": 1.8}

DECKS = [
    # name, x0, x1, y0, y1, z, floor material, openings {side: [(a, b)]}, zone
    # v2 (audit fixes): bridges and openings widened to >= 1.1-1.4 m clear;
    # railing posts stand outside every opening; the corridor is 1.6 m wide.
    ("L_Start", 0.0, 6.0, 3.0, 5.0, Z0, "Deck_Board", {"S": [(3.9, 5.3)], "E": [(3.25, 4.75)]}, "Lower"),
    ("L_Front", 3.5, 6.0, 0.0, 2.0, Z0, "Deck_Board", {"N": [(3.9, 5.3)], "E": [(0.3, 1.7)]}, "Lower"),
    ("L_FrontEast", 6.8, 9.0, 0.0, 2.0, Z0, "Deck_Board", {"W": [(0.3, 1.7)], "E": [(0.25, 1.75)]}, "Lower"),
    ("L_HiddenCorridor", 6.0, 9.0, 3.2, 4.8, Z0, "Slate_Floor", {"W": [(3.25, 4.75)], "E": [(3.25, 4.75)]}, "Lower"),
    ("L_SecretAlcove", 9.0, 10.4, 2.9, 5.0, Z0, "Slate_Floor", {"W": [(3.25, 4.75)]}, "Lower"),
    ("M_Workshop", 5.5, 11.2, 2.4, 6.8, Z1, "Deck_Board", {"S": [(9.1, 10.5)], "W": [(5.25, 6.45)]}, "Middle"),
    ("M_GearTerrace", 3.2, 5.5, 5.2, 7.4, Z1, "Deck_Board", {"E": [(5.25, 6.45)]}, "Middle"),
    ("U_LiftWalk", 9.35, 10.85, 1.8, 5.6, Z2, "Deck_Board", {"S": [(9.4, 10.8)], "N": [(9.4, 10.8)]}, "Upper"),
    # The pool/valve link runs north of the front channel and under the pond aqueduct.
    ("U_PoolDeck", 9.4, 12.0, 5.6, 9.3, Z2, "Deck_Board", {"S": [(9.4, 10.8)], "W": [(8.05, 9.15)]}, "Upper"),
    ("U_ValveDeck", 4.5, 9.4, 7.4, 9.8, Z2, "Deck_Board", {"E": [(8.05, 9.15)], "W": [(7.6, 9.4)]}, "Upper"),
    ("U_GoalDeck", 1.0, 4.5, 7.0, 10.0, Z2, "Deck_Board", {"E": [(7.6, 9.4)]}, "Upper"),
]

# Spill notches in railings over a channel: water leaves the deck there, the
# marble cannot (the channel lies between lane and notch). Not ball openings.
SPILL_NOTCHES = {"U_ValveDeck": {"S": [(6.6, 7.05), (7.3, 7.75)]}}

# Flush recesses (no boards) for pressure plates and the goal socket.
INLAYS = {
    "L_Start": [(2.8, 3.8, 3.5, 4.5)],
    "L_FrontEast": [(7.4, 8.4, 0.5, 1.5)],
    "L_HiddenCorridor": [(7.8, 8.6, 3.6, 4.4)],
    "U_GoalDeck": [(1.72, 3.08, 7.92, 9.28)],
}

# Floor boards are left out where a channel trough is sunk into the deck.
CUTOUTS = {
    "M_Workshop": [(6.5, 8.0, 5.95, 6.45)],
    "U_ValveDeck": [(4.6, 9.3, 7.45, 7.95)],
}

BRIDGES = [
    ("Bridge_StreamWest", 3.9, 5.3, 2.0, 3.0, Z0, "Y"),
    ("Bridge_Spillway", 6.0, 6.8, 0.3, 1.7, Z0, "X"),
    ("Bridge_LiftMiddle", 9.1, 10.5, 1.8, 2.4, Z1, "Y"),
]

# Wheel pit in M_Workshop: 2.5 m long so the 2.04 m wheel clears it by 0.23 m.
WHEEL_PIT = (8.05, 10.55, 5.65, 6.6)
WHEEL_MAIN = (9.3, 6.125, 1.3)


def side_segments(a0, a1, openings):
    cuts = sorted(openings)
    segments, cursor = [], a0
    for start, end in cuts:
        if start > cursor:
            segments.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < a1:
        segments.append((cursor, a1))
    return [s for s in segments if s[1] - s[0] > 0.05]


def build_deck(name, x0, x1, y0, y1, z, floor_mat, openings, zone, holes=(), inlays=(), cutouts=()):
    b = Builder(name, collection("L05/Platforms/" + zone))
    # Floor boards run along the longer side, with hairline gaps and jitter.
    along_x = (x1 - x0) >= (y1 - y0)
    span0, span1 = (y0, y1) if along_x else (x0, x1)
    board_w = 0.32
    count = max(1, round((span1 - span0) / board_w))
    width = (span1 - span0) / count
    for i in range(count):
        c = span0 + (i + 0.5) * width
        # Boards are split into staggered lengths so seams read like a real floor.
        length_total = (x1 - x0) if along_x else (y1 - y0)
        cursor = 0.0
        seg = 1.6 + (i % 3) * 0.55
        while cursor < length_total - 0.01:
            l = min(seg, length_total - cursor)
            start = (x0 if along_x else y0) + cursor
            for p0, p1 in _board_pieces(start, start + l, c, width, along_x, list(holes) + list(inlays) + list(cutouts)):
                a = (p0 + p1) / 2
                center = (a, c, z - 0.025) if along_x else (c, a, z - 0.025)
                size = (p1 - p0 - 0.012, width - 0.014, 0.05) if along_x else (width - 0.014, p1 - p0 - 0.012, 0.05)
                b.box(center, size, floor_mat, bevel=0.008)
            cursor += l
            seg = 1.4 + RNG.random() * 1.2
    # Joists and subfloor under the boards; open holes (the wheel pit) are
    # cut through the subfloor too, so nothing crosses them.
    for sx0, sx1, sy0, sy1 in _rect_minus((x0 + 0.05, x1 - 0.05, y0 + 0.05, y1 - 0.05), holes):
        b.box(((sx0 + sx1) / 2, (sy0 + sy1) / 2, z - DECK_T * 0.5 - 0.025), (sx1 - sx0, sy1 - sy0, DECK_T - 0.05), "Wood_Dark", bevel=0.0)
    for hole in holes:
        _pit_frame(b, hole, z)
    for rect in inlays:
        _inlay_frame(b, rect, z)
    railing_gaps = {side: list(spans) for side, spans in openings.items()}
    for side, spans in SPILL_NOTCHES.get(name, {}).items():
        railing_gaps.setdefault(side, []).extend(spans)
    _deck_frame(b, x0, x1, y0, y1, z, railing_gaps)
    return b.finish()


def _board_pieces(a0, a1, c, width, along_x, rects):
    """Splits one board [a0, a1] (at cross position c) around every rect."""
    pieces = [(a0, a1)]
    for rx0, rx1, ry0, ry1 in rects:
        lo, hi = (rx0, rx1) if along_x else (ry0, ry1)
        clo, chi = (ry0, ry1) if along_x else (rx0, rx1)
        if c + width / 2 <= clo or c - width / 2 >= chi:
            continue
        nxt = []
        for p0, p1 in pieces:
            if p1 <= lo or p0 >= hi:
                nxt.append((p0, p1))
                continue
            if p0 < lo:
                nxt.append((p0, lo))
            if p1 > hi:
                nxt.append((hi, p1))
        pieces = nxt
    return [pc for pc in pieces if pc[1] - pc[0] > 0.06]


def _rect_minus(rect, holes):
    """Rectangle minus axis-aligned holes, as a list of rectangles."""
    parts = [rect]
    for hx0, hx1, hy0, hy1 in holes:
        nxt = []
        for x0, x1, y0, y1 in parts:
            if hx1 <= x0 or hx0 >= x1 or hy1 <= y0 or hy0 >= y1:
                nxt.append((x0, x1, y0, y1))
                continue
            if y0 < hy0:
                nxt.append((x0, x1, y0, hy0))
            if hy1 < y1:
                nxt.append((x0, x1, hy1, y1))
            if x0 < hx0:
                nxt.append((x0, hx0, max(y0, hy0), min(y1, hy1)))
            if hx1 < x1:
                nxt.append((hx1, x1, max(y0, hy0), min(y1, hy1)))
        parts = nxt
    return parts


def _board_hits(center, size, rect):
    return not (center[0] + size[0] / 2 <= rect[0] or center[0] - size[0] / 2 >= rect[1] or center[1] + size[1] / 2 <= rect[2] or center[1] - size[1] / 2 >= rect[3])


def _inlay_frame(b, rect, z):
    """Flush iron rim around a recess; the recess floor is the subfloor 5 cm down."""
    rx0, rx1, ry0, ry1 = rect
    w = 0.05
    for center, size in ((((rx0 + rx1) / 2, ry0 + w / 2), (rx1 - rx0, w, 0.05)), (((rx0 + rx1) / 2, ry1 - w / 2), (rx1 - rx0, w, 0.05)),
                         ((rx0 + w / 2, (ry0 + ry1) / 2), (w, ry1 - ry0, 0.05)), ((rx1 - w / 2, (ry0 + ry1) / 2), (w, ry1 - ry0, 0.05))):
        b.box((center[0], center[1], z - 0.025), size, "Iron", bevel=0.006)


def _inside(center, hole):
    return hole[0] - 0.05 < center[0] < hole[1] + 0.05 and hole[2] - 0.05 < center[1] < hole[3] + 0.05


def _deck_frame(b, x0, x1, y0, y1, z, openings):
    t = 0.16
    sides = {
        "S": ((x0, x1), lambda a: (a, y0 + t / 2), "X"),
        "N": ((x0, x1), lambda a: (a, y1 - t / 2), "X"),
        "W": ((y0, y1), lambda a: (x0 + t / 2, a), "Y"),
        "E": ((y0, y1), lambda a: (x1 - t / 2, a), "Y"),
    }
    # Edge beams wrap the whole deck (also under openings) below floor level.
    for side, ((a0, a1), at, axis) in sides.items():
        mid = at((a0 + a1) / 2)
        size = (a1 - a0, t, DECK_T) if axis == "X" else (t, a1 - a0, DECK_T)
        b.box((mid[0], mid[1], z - DECK_T / 2 - 0.01), size, "Wood_Frame", bevel=0.025)
        for s0, s1 in side_segments(a0, a1, openings.get(side, [])):
            _railing(b, at, axis, s0, s1, z, t)


def _railing(b, at, axis, s0, s1, z, t):
    mid = at((s0 + s1) / 2)
    length = s1 - s0
    curb = (length, t, CURB_H) if axis == "X" else (t, length, CURB_H)
    b.box((mid[0], mid[1], z + CURB_H / 2), curb, "Wood_Frame", bevel=0.025)
    rail = (length, 0.1, 0.09) if axis == "X" else (0.1, length, 0.09)
    b.box((mid[0], mid[1], z + RAIL_H - 0.045), rail, "Wood_Frame", bevel=0.02)
    posts = max(1, math.ceil(length / 1.3))
    # Posts are inset from the segment ends so none of them narrows an opening.
    inset = min(0.085, length / 2)
    for k in range(posts + 1):
        a = (s0 + inset) + (length - 2 * inset) * k / posts
        p = at(a)
        b.box((p[0], p[1], z + (RAIL_H + 0.06) / 2 - 0.03), (0.17, 0.17, RAIL_H + 0.06), "Wood_Frame", bevel=0.025)
        b.box((p[0], p[1], z + RAIL_H + 0.08), (0.21, 0.21, 0.09), "Brass", bevel=0.02)
        # Iron corner straps where post meets curb.
        b.box((p[0], p[1], z + 0.12), (0.2, 0.2, 0.05), "Iron", bevel=0.01)


def _pit_frame(b, hole, z):
    hx0, hx1, hy0, hy1 = hole
    for (a, c, axis, l) in [((hx0 + hx1) / 2, hy0, "X", hx1 - hx0), ((hx0 + hx1) / 2, hy1, "X", hx1 - hx0), (hx0, (hy0 + hy1) / 2, "Y", hy1 - hy0), (hx1, (hy0 + hy1) / 2, "Y", hy1 - hy0)]:
        size = (l, 0.14, CURB_H + 0.1) if axis == "X" else (0.14, l, CURB_H + 0.1)
        center = (a, c, z + CURB_H / 2 - 0.05) if axis == "X" else (a, c, z + CURB_H / 2 - 0.05)
        b.box(center, size, "Wood_Frame", bevel=0.02)


def build_bridge(name, x0, x1, y0, y1, z, along):
    b = Builder(name, collection("L05/Mechanisms/Bridges"))
    # The lift bridge must not reach into the shaft (v1 beams overhung 0.10 m).
    over = 0.0 if name == "Bridge_LiftMiddle" else 0.2
    if along == "Y":
        n = round((y1 - y0) / 0.2)
        for i in range(n):
            yc = y0 + (i + 0.5) * (y1 - y0) / n
            b.box(((x0 + x1) / 2, yc, z - 0.03 - RNG.random() * 0.01), (x1 - x0 + 0.1, (y1 - y0) / n - 0.02, 0.06), "Wood_Plank", rot=(0, RNG.uniform(-0.02, 0.02), 0), bevel=0.01)
        for x in (x0 + 0.06, x1 - 0.06):
            b.box((x, (y0 + y1) / 2, z - 0.15), (0.14, y1 - y0 + over, 0.2), "Wood_Frame", bevel=0.02)
            b.box((x, (y0 + y1) / 2, z + 0.15), (0.12, y1 - y0, 0.3), "Wood_Frame", bevel=0.02)
            b.box((x, (y0 + y1) / 2, z + RAIL_H - 0.04), (0.1, y1 - y0, 0.08), "Wood_Frame", bevel=0.02)
            for y in (y0 + 0.08, y1 - 0.08):
                b.box((x, y, z + RAIL_H / 2), (0.15, 0.15, RAIL_H + 0.1), "Wood_Frame", bevel=0.02)
                b.box((x, y, z + RAIL_H + 0.08), (0.19, 0.19, 0.08), "Brass", bevel=0.015)
    else:
        n = round((x1 - x0) / 0.2)
        for i in range(n):
            xc = x0 + (i + 0.5) * (x1 - x0) / n
            b.box((xc, (y0 + y1) / 2, z - 0.03 - RNG.random() * 0.01), ((x1 - x0) / n - 0.02, y1 - y0 + 0.1, 0.06), "Wood_Plank", rot=(RNG.uniform(-0.02, 0.02), 0, 0), bevel=0.01)
        for y in (y0 + 0.06, y1 - 0.06):
            b.box(((x0 + x1) / 2, y, z - 0.15), (x1 - x0 + over, 0.14, 0.2), "Wood_Frame", bevel=0.02)
            b.box(((x0 + x1) / 2, y, z + 0.15), (x1 - x0, 0.12, 0.3), "Wood_Frame", bevel=0.02)
            b.box(((x0 + x1) / 2, y, z + RAIL_H - 0.04), (x1 - x0, 0.1, 0.08), "Wood_Frame", bevel=0.02)
            for x in (x0 + 0.08, x1 - 0.08):
                b.box((x, y, z + RAIL_H / 2), (0.15, 0.15, RAIL_H + 0.1), "Wood_Frame", bevel=0.02)
                b.box((x, y, z + RAIL_H + 0.08), (0.19, 0.19, 0.08), "Brass", bevel=0.015)
    return b.finish()


# ----------------------------------------------------------------------------
# Masonry: coursed blocks, arches, piers
# ----------------------------------------------------------------------------

def masonry_wall(b, p0, p1, z0, z1, thick, mat="Stone_Masonry", course=0.3, arches=(), backing=True):
    """Coursed stone wall from p0 to p1 (XY). `arches` = [(along, span, spring_z)]."""
    p0, p1 = Vector((p0[0], p0[1], 0)), Vector((p1[0], p1[1], 0))
    d = p1 - p0
    length = d.length
    if length < 0.05 or z1 - z0 < 0.05:
        return
    d.normalize()
    n = Vector((-d.y, d.x, 0))
    yaw = math.atan2(d.y, d.x)
    if backing:
        # Mortar core fills the joints between irregular blocks; it is split
        # around every arch so the openings stay truly open.
        cuts = sorted((c - s / 2 - 0.12, c + s / 2 + 0.12, sp + s / 2 + 0.26) for c, s, sp in arches)
        cursor = 0.0
        for a0, a1, top in cuts + [(length, length, z1)]:
            if a0 - cursor > 0.05:
                core = p0 + d * ((cursor + max(a0, cursor)) / 2)
                b.box((core.x, core.y, (z0 + z1) / 2), (a0 - cursor - 0.02, thick - 0.07, z1 - z0 - 0.02), "Stone_Wet", rot=(0, 0, yaw), bevel=0.0)
            if a1 > a0 and z1 - top > 0.05:
                core = p0 + d * ((a0 + a1) / 2)
                b.box((core.x, core.y, (top + z1) / 2), (a1 - a0, thick - 0.07, z1 - top), "Stone_Wet", rot=(0, 0, yaw), bevel=0.0)
            cursor = max(cursor, a1)
    rows = max(1, round((z1 - z0) / course))
    h = (z1 - z0) / rows
    for r in range(rows):
        zc = z0 + (r + 0.5) * h
        cursor = -RNG.uniform(0.0, 0.3) if r % 2 else 0.0
        while cursor < length:
            bl = RNG.uniform(0.38, 0.72)
            s = max(cursor, 0.0)
            e = min(cursor + bl, length)
            cursor += bl
            if e - s < 0.08:
                continue
            mid = (s + e) / 2
            if any(_in_arch(mid, zc, a) for a in arches):
                continue
            c = p0 + d * mid + n * RNG.uniform(-0.012, 0.012)
            b.box((c.x, c.y, zc), (e - s - 0.025, thick + RNG.uniform(-0.01, 0.03), h - 0.025), mat if RNG.random() > 0.18 else "Stone_Wet",
                  rot=(0, 0, yaw + RNG.uniform(-0.01, 0.01)), bevel=0.035)
    for along, span, spring in arches:
        _arch_ring(b, p0 + d * along, d, yaw, span, spring, thick, mat)


def _in_arch(along, z, arch):
    center, span, spring = arch
    r = span / 2
    dx = along - center
    if abs(dx) >= r + 0.12:
        return False
    if z < spring:
        return abs(dx) < r + 0.02
    return math.hypot(dx, z - spring) < r + 0.24


def _arch_ring(b, center, d, yaw, span, spring, thick, mat):
    r = span / 2 + 0.11
    count = 11
    for i in range(count):
        a0 = math.pi * i / count
        a1 = math.pi * (i + 1) / count
        a = (a0 + a1) / 2
        c = center + d * (-math.cos(a) * r)
        z = spring + math.sin(a) * r
        chord = 2 * r * math.sin(math.pi / count / 2) - 0.03
        # Voussoir: oriented along the arch tangent in the wall plane.
        local = Matrix.Translation((c.x, c.y, z)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(-(a - math.pi / 2), 4, "Y")
        _box_matrix(b, local, (chord, thick + 0.05, 0.24), mat if i % 2 else "Stone_Masonry")
    keystone = center + Vector((0, 0, 0))
    _box_matrix(b, Matrix.Translation((keystone.x, keystone.y, spring + r + 0.02)) @ Matrix.Rotation(yaw, 4, "Z"), (0.22, thick + 0.09, 0.3), "Stone_Masonry")


def _box_matrix(b, matrix, size, mat, bevel=0.03):
    m = matrix @ Matrix.Diagonal((*size, 1.0))
    result = bmesh.ops.create_cube(b.bm, size=1.0, matrix=m)
    verts = result["verts"]
    faces = list({f for v in verts for f in v.link_faces})
    edges = list({e for f in faces for e in f.edges})
    bev = bmesh.ops.bevel(b.bm, geom=edges + verts, offset=min(bevel, min(size) * 0.45), segments=1, profile=0.5, affect="EDGES", clamp_overlap=True)
    faces = [f for f in {f for v in bev["verts"] for f in v.link_faces} | set(bev["faces"]) | set(f for f in faces if f.is_valid) if f.is_valid]
    b._finish_faces(faces, mat, False)
    b.box_uv(faces, matrix.to_3x3().normalized(), matrix.to_translation(), Vector(size), mat)


def stone_pier(b, x, y, z0, z1, size=0.5, mat="Stone_Masonry"):
    rows = max(1, round((z1 - z0) / 0.3))
    h = (z1 - z0) / rows
    for r in range(rows):
        twist = 0.0 if r % 2 else 0.04
        b.box((x + RNG.uniform(-0.01, 0.01), y + RNG.uniform(-0.01, 0.01), z0 + (r + 0.5) * h), (size + twist, size - twist, h - 0.025), mat, bevel=0.035)
    b.box((x, y, z1 + 0.06), (size + 0.12, size + 0.12, 0.12), "Stone_Masonry", bevel=0.03)


def build_foundations():
    col = collection("L05/Static_Architecture/Stone")
    rock_top = -1.5
    # Lower decks rest on coursed stone skirts down to the cliff.
    lower = Builder("Masonry_LowerFoundations", col)
    for name, x0, x1, y0, y1, z, _m, _o, zone in DECKS:
        if zone != "Lower":
            continue
        zt = z - DECK_T - 0.02
        for p0, p1 in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
            masonry_wall(lower, _inset(p0, p1, 0.08), _inset(p1, p0, 0.08), rock_top, zt, 0.32)
    # Stream bed walls and spillway.
    for p0, p1 in (((0.0, 2.0), (6.0, 2.0)), ((0.0, 3.0), (6.8, 3.0)), ((6.0, 0.0), (6.0, 2.0)), ((6.8, 0.0), (6.8, 3.0))):
        masonry_wall(lower, p0, p1, rock_top, -0.15, 0.24, mat="Stone_Wet")
    lower.box((3.4, 2.5, -0.45), (6.8, 1.0, 0.1), "Stone_Wet", bevel=0.02)
    lower.box((6.4, 1.0, -0.45), (0.8, 2.0, 0.1), "Stone_Wet", bevel=0.02)
    lower.finish()

    # Middle tier: arcade facing the camera over the stream, corridor walls.
    middle = Builder("Masonry_MiddleArcade", col)
    zt = Z1 - DECK_T - 0.02
    masonry_wall(middle, (5.55, 2.45), (9.15, 2.45), rock_top, zt, 0.42, arches=[(0.85, 1.1, -0.2), (2.35, 1.1, 0.25)])
    masonry_wall(middle, (6.0, 3.12), (9.0, 3.12), Z0, zt, 0.16)
    masonry_wall(middle, (6.0, 4.88), (9.0, 4.88), Z0, zt, 0.16)
    # The corridor arch (y 3.25-4.75) is the entrance of the hidden lower path.
    masonry_wall(middle, (5.55, 2.45), (5.55, 6.75), rock_top, zt, 0.36, arches=[(1.55, 1.5, 0.3)])
    masonry_wall(middle, (11.15, 2.45), (11.15, 6.75), rock_top, zt, 0.36, arches=[(2.0, 1.4, 0.0)])
    # North wall is continuous; the main axle runs through it in a bearing.
    masonry_wall(middle, (5.55, 6.75), (11.15, 6.75), rock_top, zt, 0.36)
    masonry_wall(middle, (3.25, 5.25), (3.25, 7.35), rock_top, zt, 0.32)
    masonry_wall(middle, (3.25, 7.35), (5.5, 7.35), rock_top, zt, 0.32)
    masonry_wall(middle, (3.25, 5.25), (5.5, 5.25), rock_top, zt, 0.32, arches=[(1.1, 0.9, Z0 - 0.4)])
    # Wheel pit lining (2.5 m pit; the wheel clears every wall by >= 0.2 m).
    px0, px1, py0, py1 = WHEEL_PIT
    masonry_wall(middle, (px0 - 0.12, py0), (px0 - 0.12, py1 + 0.1), -0.6, zt, 0.24, mat="Stone_Wet")
    masonry_wall(middle, (px1 + 0.12, py0), (px1 + 0.12, py1 + 0.1), -0.6, zt, 0.24, mat="Stone_Wet")
    masonry_wall(middle, (px0 - 0.12, py0 - 0.12), (px1 + 0.12, py0 - 0.12), -0.6, zt, 0.24, mat="Stone_Wet")
    middle.finish()

    # Upper tier: tall walls with arches and buttresses.
    upper = Builder("Masonry_UpperTerraces", col)
    zt = Z2 - DECK_T - 0.02
    masonry_wall(upper, (4.55, 7.45), (8.35, 7.45), Z1 - 0.3, zt, 0.42, arches=[(0.75, 0.9, Z1 + 0.25), (2.95, 0.9, Z1 + 0.25)])
    masonry_wall(upper, (1.05, 7.05), (3.2, 7.05), rock_top, zt, 0.42, arches=[(1.1, 1.0, Z1 - 0.1)])
    masonry_wall(upper, (1.05, 7.05), (1.05, 9.95), rock_top, zt, 0.42, arches=[(1.5, 1.2, Z1)])
    masonry_wall(upper, (1.05, 9.95), (9.4, 9.95), rock_top, zt, 0.42)
    masonry_wall(upper, (11.95, 5.65), (11.95, 9.25), rock_top, zt, 0.42, arches=[(1.25, 1.1, Z1 + 0.2)])
    masonry_wall(upper, (9.45, 9.25), (11.95, 9.25), rock_top, zt, 0.42)
    stone_pier(upper, 11.95, 5.65, Z1, zt - 0.12, 0.42)
    upper.finish()
    # The lift walk stands on timber posts along its edges (under-walk lane 1.12 m)
    # and on the lift tower's north header beam; no pier stands in the shaft.
    walk = Builder("Timber_WalkSupports", collection("L05/Static_Architecture/Timber"))
    for x in (9.4, 10.8):
        for y in (3.7, 5.45):
            walk.box((x, y, (Z1 + Z2 - DECK_T) / 2), (0.18, 0.18, Z2 - DECK_T - Z1), "Wood_Frame", bevel=0.02)
            walk.box((x, y, Z2 - DECK_T - 0.05), (0.26, 0.26, 0.06), "Brass", bevel=0.01)
            walk.box((x, y, Z1 + 0.04), (0.24, 0.24, 0.08), "Iron", bevel=0.01)
    walk.box((9.4, 4.575, Z2 - DECK_T - 0.12), (0.14, 1.75, 0.14), "Wood_Frame", bevel=0.02)
    walk.box((10.8, 4.575, Z2 - DECK_T - 0.12), (0.14, 1.75, 0.14), "Wood_Frame", bevel=0.02)
    walk.finish()
    upper = Builder("Masonry_Millhouse_Plinth", col)
    # Millhouse plinth.
    for p0, p1 in (((6.3, 9.85), (9.35, 9.85)), ((9.35, 9.85), (9.35, 12.05)), ((9.35, 12.05), (6.3, 12.05)), ((6.3, 12.05), (6.3, 9.85))):
        masonry_wall(upper, p0, p1, rock_top, Z2 + 0.32, 0.4)
    upper.box((7.825, 10.95, Z2 + 0.2), (2.9, 2.05, 0.2), "Stone_Masonry", bevel=0.03)
    upper.finish()


def _inset(p, q, amount):
    v = Vector((q[0] - p[0], q[1] - p[1]))
    if v.length == 0:
        return p
    v.normalize()
    return (p[0] + v.x * amount, p[1] + v.y * amount)


# ----------------------------------------------------------------------------
# Terrain: the mountain top, faceted granite outcrops, stratified cliffs
# ----------------------------------------------------------------------------

FOOTPRINT = (-0.8, 12.8, -0.8, 12.8)


def ground_height(x, y):
    fx0, fx1, fy0, fy1 = FOOTPRINT
    dx = max(fx0 - x, 0.0, x - fx1)
    dy = max(fy0 - y, 0.0, y - fy1)
    edge = math.hypot(dx, dy)
    rough = noise.noise(Vector((x * 0.18, y * 0.18, 1.7))) * 1.2 + noise.noise(Vector((x * 0.6, y * 0.6, 4.2))) * 0.35
    # Plateau under the mill; the summit drops away steeply beyond the board,
    # rising again into the higher ridge behind the summit mill.
    base = -1.55 + rough * 0.25
    drop = -min(edge, 14.0) ** 1.35 * 0.9
    return base + drop + rough * min(edge, 6.0) * 0.25


def build_ground():
    col = collection("L05/Terrain")
    size, res = 80.0, 150
    bm = bmesh.new()
    verts = []
    for j in range(res + 1):
        row = []
        for i in range(res + 1):
            x = 6.0 - size / 2 + size * i / res
            y = 6.0 - size / 2 + size * j / res
            row.append(bm.verts.new((x, y, ground_height(x, y))))
        verts.append(row)
    for j in range(res):
        for i in range(res):
            f = bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
            f.smooth = True
    mesh = bpy.data.meshes.new("Mountain_Summit")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(MATS["Rock_Moss"])
    obj = bpy.data.objects.new("Mountain_Summit", mesh)
    col.objects.link(obj)
    _box_uv(obj)
    return obj


def rock_chunk(b, center, size, seed, mat="Rock_Moss", subdiv=2):
    """Faceted granite block: displaced icosphere with flattened strata."""
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=1.0)
    offset = Vector((seed * 3.1, seed * 1.7, seed * 0.9))
    for v in tmp.verts:
        p = v.co.copy()
        n1 = noise.noise(p * 1.3 + offset)
        n2 = noise.noise(p * 3.2 + offset * 2.0) * 0.35
        p *= 1.0 + n1 * 0.28 + n2 * 0.12
        # Stratification: quantise height softly into ledges.
        p.z = math.floor(p.z * 3.0) / 3.0 * 0.55 + p.z * 0.45
        v.co = Vector((p.x * size[0], p.y * size[1], p.z * size[2])) + Vector(center)
    mapping = {}
    for v in tmp.verts:
        mapping[v] = b.bm.verts.new(v.co)
    index = b._mi(mat)
    for f in tmp.faces:
        nf = b.bm.faces.new([mapping[v] for v in f.verts])
        nf.material_index = index
        nf.smooth = False
    tmp.free()


def build_cliffs():
    col = collection("L05/Terrain")
    b = Builder("Cliff_Outcrops", col)
    rng = random.Random(77)
    fx0, fx1, fy0, fy1 = FOOTPRINT
    # Ring of stacked outcrops around the summit, denser on the camera sides.
    for k in range(70):
        t = rng.random()
        side = rng.choice(["S", "S", "W", "W", "E", "N"])
        if side == "S":
            x, y = fx0 + t * (fx1 - fx0), fy0 - rng.uniform(0.2, 2.5)
        elif side == "W":
            x, y = fx0 - rng.uniform(0.2, 2.5), fy0 + t * (fy1 - fy0)
        elif side == "E":
            x, y = fx1 + rng.uniform(0.2, 2.5), fy0 + t * (fy1 - fy0)
        else:
            x, y = fx0 + t * (fx1 - fx0), fy1 + rng.uniform(0.0, 2.5)
        z = ground_height(x, y) + rng.uniform(-0.4, 0.6)
        s = rng.uniform(0.8, 2.2)
        rock_chunk(b, (x, y, z), (s * rng.uniform(0.8, 1.4), s * rng.uniform(0.8, 1.4), s * rng.uniform(0.6, 1.1)), k + 1)
    # Boulders right under the deck foundations hide the masonry footing.
    for k in range(40):
        x = rng.uniform(fx0, fx1)
        y = rng.uniform(fy0, fy1)
        rock_chunk(b, (x, y, -1.75 + rng.uniform(-0.2, 0.15)), (rng.uniform(0.5, 1.0), rng.uniform(0.5, 1.0), rng.uniform(0.25, 0.45)), 200 + k, subdiv=1)
    # Tall stratified cliff faces dropping below the lift and the east wheel.
    for k, (x, y, z) in enumerate([(12.8, 4.0, -3.5), (12.2, 0.5, -4.2), (13.2, 7.0, -3.0), (5.5, -1.6, -3.8), (1.5, -1.0, -3.2), (-1.4, 3.0, -3.0), (-1.4, 8.0, -2.6)]):
        rock_chunk(b, (x, y, z), (1.6, 1.8, 3.2), 400 + k)
    return b.finish()


# ----------------------------------------------------------------------------
# Water: channels, surfaces, waterfalls, spray
# ----------------------------------------------------------------------------

def water_surface(name, x0, x1, y0, y1, z, flow=(0, 1), mat="Water"):
    """Water sheet. UVs are metres with +U pointing downstream (`flow` =
    (axis 0=X / 1=Y, sign)), so one scrolling offset animates every channel
    in its own direction; a Wave modifier gives the surface live ripples."""
    b = Builder(name, collection("L05/Water"))
    # Slightly subdivided so the glTF importer and shaders get UVs per metre.
    nx, ny = max(2, int((x1 - x0) * 3)), max(2, int((y1 - y0) * 3))
    verts = []
    faces = []
    uvs = []
    axis, sign = flow
    for j in range(ny + 1):
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx
            y = y0 + (y1 - y0) * j / ny
            verts.append((x, y, z + noise.noise(Vector((x * 2.0, y * 2.0, 3.0))) * 0.008))
            uvs.append((sign * x, y) if axis == 0 else (sign * y, x))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    b.raw(verts, faces, mat, uvs=uvs)
    obj = b.finish()
    _wave(obj, 0.006 if mat == "Water" else 0.003, 0.3)
    return obj


def _wave(obj, height, width):
    mod = obj.modifiers.new("Flow_Wave", "WAVE")
    mod.height = height
    mod.width = width
    mod.narrowness = 1.2
    mod.speed = 0.03
    mod.use_normal = True
    mod.use_cyclic = True
    return mod


def flume(b, x0, x1, y0, y1, z_bed, depth=0.28, mat="Wood_Plank", posts_to=None, notches=(), spill_depth=0.2, posts_from=None, caps=()):
    """Open timber channel; the long axis is the larger extent. `notches` are
    spill gaps (along the long axis) in the low-side wall, cut down to
    `spill_depth` above the bed; `caps` closes the "start"/"end" of the run."""
    along_x = (x1 - x0) >= (y1 - y0)
    b.box(((x0 + x1) / 2, (y0 + y1) / 2, z_bed - 0.04), (x1 - x0, y1 - y0, 0.08), mat, bevel=0.01)
    if along_x:
        for y in (y0 + 0.04, y1 - 0.04):
            spans = [(x0, x1)] if (y > (y0 + y1) / 2 or not notches) else side_segments(x0, x1, list(notches))
            for a0, a1 in spans:
                b.box(((a0 + a1) / 2, y, z_bed + depth / 2), (a1 - a0, 0.08, depth), mat, bevel=0.01)
            if y < (y0 + y1) / 2:
                for a0, a1 in notches:
                    b.box(((a0 + a1) / 2, y, z_bed + spill_depth / 2), (a1 - a0, 0.08, spill_depth), "Stone_Wet", bevel=0.01)
        for which in caps:
            x = x0 + 0.04 if which == "start" else x1 - 0.04
            b.box((x, (y0 + y1) / 2, z_bed + depth / 2), (0.08, y1 - y0, depth), mat, bevel=0.01)
        span = x1 - x0
        for k in range(int(span / 0.9) + 1):
            x = x0 + 0.05 + k * min(0.9, span - 0.1)
            b.box((x, (y0 + y1) / 2, z_bed + depth * 0.5), (0.08, y1 - y0 + 0.14, depth + 0.1), "Wood_Frame", bevel=0.015)
            b.box((x, y0 - 0.03, z_bed + depth + 0.03), (0.1, 0.1, 0.06), "Brass", bevel=0.01)
            b.box((x, y1 + 0.03, z_bed + depth + 0.03), (0.1, 0.1, 0.06), "Brass", bevel=0.01)
            if posts_to is not None and (posts_from is None or x >= posts_from):
                b.box((x, (y0 + y1) / 2, (posts_to + z_bed) / 2), (0.12, 0.12, z_bed - posts_to), "Wood_Frame", bevel=0.02)
    else:
        for x in (x0 + 0.04, x1 - 0.04):
            b.box((x, (y0 + y1) / 2, z_bed + depth / 2), (0.08, y1 - y0, depth), mat, bevel=0.01)
        span = y1 - y0
        for k in range(int(span / 0.9) + 1):
            y = y0 + 0.05 + k * min(0.9, span - 0.1)
            b.box(((x0 + x1) / 2, y, z_bed + depth * 0.5), (x1 - x0 + 0.14, 0.08, depth + 0.1), "Wood_Frame", bevel=0.015)
            b.box((x0 - 0.03, y, z_bed + depth + 0.03), (0.1, 0.1, 0.06), "Brass", bevel=0.01)
            b.box((x1 + 0.03, y, z_bed + depth + 0.03), (0.1, 0.1, 0.06), "Brass", bevel=0.01)
            if posts_to is not None and (posts_from is None or y >= posts_from):
                b.box(((x0 + x1) / 2, y, (posts_to + z_bed) / 2), (0.12, 0.12, z_bed - posts_to), "Wood_Frame", bevel=0.02)
        for which in caps:
            y = y0 + 0.04 if which == "start" else y1 - 0.04
            b.box(((x0 + x1) / 2, y, z_bed + depth / 2), (x1 - x0, 0.08, depth), mat, bevel=0.01)


def waterfall(name, a0, a1, edge, z_top, z_bottom, outward, axis="X", thickness=0.05, rng=None, pool=True):
    """Layered falling water leaving an edge (`axis` = lip direction):
    a translucent streaked body sheet, a faster foam sheet peeling off in
    front of it, churned-foam blobs where it lands, a flat foam patch and a
    soft spray card. UVs: U across the lip, V = -metres fallen, so the
    materials' scrolling offsets move the streaks down the fall."""
    rng = rng or RNG
    b = Builder(name, collection("L05/Water/Waterfalls"))
    cols, rows = max(3, int((a1 - a0) * 6)), max(6, int((z_top - z_bottom) * 5))
    scale = min(1.0, (z_top - z_bottom) / 1.5)
    side = 1.0 if outward >= 0 else -1.0

    def sheet(widen, push, mat):
        verts, faces, uvs = [], [], []
        fallen, prev = 0.0, None
        for j in range(rows + 1):
            t = j / rows
            z = z_top - (z_top - z_bottom) * t
            out = outward * (0.12 + 0.55 * math.sqrt(t)) * scale
            if prev is not None:
                fallen += math.hypot(z - prev[0], out - prev[1])
            prev = (z, out)
            for i in range(cols + 1):
                a = a0 - widen + (a1 - a0 + 2 * widen) * i / cols
                wob = noise.noise(Vector((a * 3.0, z * 2.0, 7.0))) * 0.04
                o = out + wob + side * (0.008 + push * min(1.0, t * 4.0))
                verts.append((a, edge + o, z) if axis == "X" else (edge + o, a, z))
                uvs.append((a, -fallen))
        for j in range(rows):
            for i in range(cols):
                p = j * (cols + 1) + i
                faces.append((p, p + 1, p + cols + 2, p + cols + 1))
        b.raw(verts, faces, mat, uvs=uvs)

    sheet(0.0, 0.0, "Waterfall_Body")
    sheet(0.02, 0.035, "Waterfall_Foam")
    # Splash: foam blobs and churned water where the sheet lands.
    for k in range(int((a1 - a0) * 9) + 4):
        a = rng.uniform(a0, a1)
        r = rng.uniform(0.06, 0.16)
        out = outward * (0.67 + rng.uniform(-0.06, 0.06)) * scale
        c = (a, edge + out, z_bottom + r * 0.4) if axis == "X" else (edge + out, a, z_bottom + r * 0.4)
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=r)
        mapping = {v: b.bm.verts.new(v.co + Vector(c)) for v in tmp.verts}
        index = b._mi("Water_Spray")
        for f in tmp.faces:
            nf = b.bm.faces.new([mapping[v] for v in f.verts])
            nf.material_index = index
            nf.smooth = True
        tmp.free()
    # Flat foam patch where the fall lands in water, and a soft spray card.
    land = outward * 0.67 * scale
    mid = (a0 + a1) / 2
    if pool:
        radius = (a1 - a0) * 0.6 + 0.15
        ring = [(mid + math.cos(t) * radius, land + math.sin(t) * radius * 0.7) for t in (k / 16 * math.tau for k in range(16))]
        pts = [((a, edge + o, z_bottom + 0.015) if axis == "X" else (edge + o, a, z_bottom + 0.015)) for a, o in ring]
        b.raw(pts, [tuple(range(16))], "Water_FoamPatch", uvs=[(p[0], p[1]) for p in pts])
    h = min(1.2, 0.35 + (z_top - z_bottom) * 0.15)
    w = (a1 - a0) + 0.5
    quad = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h), (-w / 2, h)]
    verts = [((mid + u, edge + land, z_bottom + v) if axis == "X" else (edge + land, mid + u, z_bottom + v)) for u, v in quad]
    b.raw(verts, [(0, 1, 2, 3)], "Water_Mist", uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
    obj = b.finish()
    _wave(obj, 0.012, 0.25)
    return obj


def build_water():
    col = collection("L05/Static_Architecture/Channels")
    ch = Builder("Flumes_And_Channels", col)
    # Upper valve-deck channel along its front edge, fed from the mill pond.
    # v2: lane-side wall 0.27 m high (was 0.12) and two spill notches.
    # Troughs sit on the subfloor (bed 5 cm below the floor) instead of
    # cutting into it; lane-side walls stand 0.27 m above the floor.
    flume(ch, 4.6, 9.3, 7.45, 7.95, Z2 - 0.05, depth=0.32, mat="Wood_Plank", notches=[(6.6, 7.05), (7.3, 7.75)], spill_depth=0.09, caps=("start",))
    # Mill pond -> aqueduct link along the millhouse (v1 left a 2.3 m gap).
    flume(ch, 9.15, 9.55, 9.75, 12.25, Z2 + 1.1, depth=0.26, mat="Wood_Plank")
    for y in (10.3, 11.4):
        ch.box((9.35, y, (Z2 + 0.32 + Z2 + 1.06) / 2), (0.12, 0.12, 0.74), "Wood_Frame", bevel=0.02)
    # Pond aqueduct on trestles: the marble rolls underneath (0.9 m clearance).
    flume(ch, 8.85, 9.35, 7.95, 9.85, Z2 + 0.9, depth=0.26, mat="Wood_Plank")
    for x in (8.8, 9.4):
        for y in (7.97, 9.75):
            ch.box((x, y, Z2 + 0.45), (0.12, 0.12, 0.9), "Wood_Frame", bevel=0.02)
            ch.box((x, y, Z2 + 0.02), (0.18, 0.18, 0.05), "Iron", bevel=0.01)
    # v3: the upper pool is fed by gravity from the aqueduct (water +3.90):
    # sluiced take-off in the aqueduct's east wall -> branch flume north of the
    # pool deck (y > 9.3, water +3.87) -> down-flume outside the deck's east
    # wall (x > 12.16, water +3.82) -> iron spout over the rim into the basin
    # (+3.12). No part of it crosses a lane or stands on a deck.
    flume(ch, 9.35, 12.65, 9.38, 9.72, Z2 + 1.0, depth=0.2, mat="Wood_Plank", posts_to=-1.5, posts_from=10.0,
          notches=[(12.25, 12.65)], spill_depth=0.02, caps=("end",))
    flume(ch, 12.25, 12.65, 6.7, 9.42, Z2 + 0.95, depth=0.2, mat="Wood_Plank", posts_to=-1.5, caps=("start",))
    ch.box((9.3, 9.55, Z2 + 1.12), (0.06, 0.4, 0.2), "Wood_Dark", bevel=0.008)
    ch.box((9.3, 9.55, Z2 + 1.24), (0.1, 0.46, 0.04), "Iron", bevel=0.005)
    ch.cylinder((9.3, 9.55, Z2 + 1.34), 0.012, 0.2, "Iron", segments=8)
    ch.torus((9.3, 9.55, Z2 + 1.44), 0.07, 0.012, "Red_Paint", axis="Z", seg_major=16, seg_minor=6)
    spout_from, spout_to = Vector((12.45, 6.9, Z2 + 0.99)), Vector((11.62, 6.9, Z2 + 0.86))
    sd = spout_to - spout_from
    ch.cylinder(((spout_from + spout_to) / 2), 0.06, sd.length, "Iron", rot=Vector((0, 0, 1)).rotation_difference(sd.normalized()).to_euler(), segments=12)
    # Middle workshop channel: starts east of the terrace link, ends 0.28 m
    # before the wheel rim (breastshot spout); walls 0.25 m above the floor.
    # Starts at x 6.5: the terrace link beside it keeps a 0.6 m buffer.
    flume(ch, 6.5, 8.0, 5.95, 6.45, Z1 - 0.05, depth=0.3, mat="Wood_Plank", caps=("start",))
    # Elevated flume from the upper pool down to the east wheel; no post stands
    # inside the wheel (posts only from y >= 3.5).
    flume(ch, 11.93, 12.39, 2.75, 5.55, Z2 - 0.32, depth=0.28, mat="Wood_Plank", posts_to=Z0 - 0.6, posts_from=3.5, caps=("end",))
    # Pool outlet pipe through the deck edge onto the flume head.
    pipe_from, pipe_to = Vector((11.7, 6.0, Z2 + 0.1)), Vector((12.16, 5.45, Z2 - 0.02))
    d = pipe_to - pipe_from
    ch.cylinder(((pipe_from + pipe_to) / 2), 0.07, d.length, "Iron", rot=Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler(), segments=12)
    ch.finish()

    water_surface("Water_UpperChannel", 4.66, 9.24, 7.51, 7.89, Z2 + 0.05, (0, -1))
    water_surface("Water_PondFeed", 8.91, 9.29, 7.95, 9.85, Z2 + 1.1, (1, -1))
    water_surface("Water_PondLink", 9.21, 9.49, 9.75, 12.25, Z2 + 1.2, (1, -1))
    water_surface("Water_MiddleChannel", 6.58, 7.96, 6.03, 6.37, Z1 + 0.03, (0, 1))
    water_surface("Water_EastFlume", 11.99, 12.33, 2.75, 5.5, Z2 - 0.1, (1, -1))
    water_surface("Water_Stream", 0.0, 6.0, 2.06, 2.94, -0.18, (0, 1))
    water_surface("Water_Spillway", 6.06, 6.74, 0.0, 2.94, -0.2, (1, -1))
    water_surface("Water_UpperPool", 10.84, 11.81, 6.04, 7.76, Z2 + 0.32, (1, -1), "Water_Still")
    water_surface("Water_MillPond", 6.6, 9.0, 12.15, 13.4, Z2 + 1.25, (1, -1), "Water_Still")
    water_surface("Water_WheelPit", 8.1, 10.5, 5.7, 6.55, -0.45, (0, 1), "Water_Still")
    water_surface("Water_PoolBranch", 9.41, 12.6, 9.44, 9.66, Z2 + 1.07, (0, 1))
    water_surface("Water_PoolDownFlume", 12.31, 12.59, 6.76, 9.42, Z2 + 1.02, (1, -1))

    # Waterfalls: upper channel spills twice into the middle channel; the
    # spillway drops off the front cliff; the east wheel tail falls far below.
    waterfall("Waterfall_PondDrop", 8.92, 9.28, 7.98, Z2 + 1.1, Z2 + 0.08, -0.25)
    waterfall("Waterfall_PondLink", 9.2, 9.34, 9.78, Z2 + 1.2, Z2 + 1.1, -0.1)
    # Spill notches -> middle channel (lands at y ~6.2, inside 6.03-6.37).
    waterfall("Waterfall_UpperWest", 6.62, 7.03, 7.45, Z2 + 0.03, Z1 + 0.05, -1.85)
    waterfall("Waterfall_UpperEast", 7.32, 7.73, 7.45, Z2 + 0.03, Z1 + 0.05, -1.85)
    waterfall("Waterfall_Spillway", 6.06, 6.74, 0.0, -0.2, -5.5, -1.0, pool=False)
    waterfall("Waterfall_EastFeed", 11.99, 12.33, 2.75, Z2 - 0.1, Z1 + 0.6, -0.6, pool=False)
    waterfall("Waterfall_EastWheel", 2.0, 3.2, 12.65, Z1 + 0.4, -7.0, 1.0, axis="Y", pool=False)
    waterfall("Waterfall_PoolOverflow", 6.4, 7.6, 12.0, Z2 + 0.15, Z1 - 1.0, 1.0, axis="Y", pool=False)
    waterfall("Waterfall_Spring", 2.1, 2.9, -0.15, 0.9, -0.18, 1.0, axis="Y")
    waterfall("Waterfall_WheelFeed", 6.05, 6.35, 8.0, Z1 + 0.03, Z0 + 0.3, 0.45, axis="Y", pool=False)
    # Own RNG: adding this fall must not shift the layout sequence.
    waterfall("Waterfall_PoolFeed", 6.85, 6.95, 11.6, Z2 + 0.82, Z2 + 0.33, -0.12, axis="Y", rng=random.Random(5151))

    # Upper pool basin and mill pond walls.
    pool = Builder("Basins", col)
    # v2: basin moved 0.25 m east (lane beside it 1.1 m) and its rim raised to 0.45 m.
    for p0, p1 in (((10.75, 5.95), (11.9, 5.95)), ((11.9, 5.95), (11.9, 7.85)), ((11.9, 7.85), (10.75, 7.85)), ((10.75, 7.85), (10.75, 5.95))):
        masonry_wall(pool, p0, p1, Z2 - 0.1, Z2 + 0.45, 0.18, backing=False)
    pool.box((11.325, 6.9, Z2 - 0.02), (1.15, 1.9, 0.06), "Stone_Wet", bevel=0.0)
    # Mill pond raised so it can feed the aqueduct by gravity (water at +1.25).
    for p0, p1 in (((6.5, 12.1), (9.1, 12.1)), ((9.1, 12.1), (9.1, 13.5)), ((9.1, 13.5), (6.5, 13.5)), ((6.5, 13.5), (6.5, 12.1))):
        masonry_wall(pool, p0, p1, -1.5, Z2 + 1.35, 0.25, backing=True)
    pool.finish()


# ----------------------------------------------------------------------------
# Mechanisms: wheels, gears, shafts, lift, gates, valves, levers
# ----------------------------------------------------------------------------

def build_water_wheel(name, center, radius, width, axis="Y", paddles=14):
    """Timber wheel, pivot on its axle. Local axle = X before orientation."""
    b = Builder(name, collection("L05/Mechanisms/Wheels"))
    c = Vector((0.0, 0.0, 0.0))
    seg = 20
    rim_depth = max(0.09, radius * 0.12)
    for side in (-1.0, 1.0):
        x = side * width / 2
        for i in range(seg):
            a = (i + 0.5) / seg * math.tau
            chord = 2 * (radius - rim_depth / 2) * math.sin(math.pi / seg) + 0.02
            m = Matrix.Translation((x, math.cos(a) * (radius - rim_depth / 2), math.sin(a) * (radius - rim_depth / 2))) @ Matrix.Rotation(a + math.pi / 2, 4, "X")
            _box_matrix(b, m, (0.07, chord, rim_depth), "Wood_Frame", bevel=0.012)
        # Iron tyre on the outer rim.
        b.torus((x, 0, 0), radius - 0.005, 0.018, "Iron", axis="X", seg_major=40, seg_minor=5)
        # Spokes.
        for i in range(8):
            a = i / 8 * math.tau + (0.2 if side > 0 else 0.0)
            r_mid = radius * 0.55
            m = Matrix.Translation((x, math.cos(a) * r_mid, math.sin(a) * r_mid)) @ Matrix.Rotation(a, 4, "X")
            _box_matrix(b, m, (0.06, radius * 0.86, 0.07), "Wood_Frame", bevel=0.01)
    # Paddles / buckets between the rims.
    for i in range(paddles):
        a = i / paddles * math.tau
        r = radius - rim_depth * 0.6
        m = Matrix.Translation((0, math.cos(a) * r, math.sin(a) * r)) @ Matrix.Rotation(a + 0.25, 4, "X")
        _box_matrix(b, m, (width - 0.03, 0.035, rim_depth * 1.9), "Wood_Plank", bevel=0.008)
        # Cross ties keep the rims square.
        m2 = Matrix.Translation((0, math.cos(a + 0.12) * (radius * 0.75), math.sin(a + 0.12) * (radius * 0.75))) @ Matrix.Rotation(a, 4, "X")
        if i % 2 == 0:
            _box_matrix(b, m2, (width, 0.035, 0.035), "Wood_Dark", bevel=0.005)
    # Hub with brass bands, iron axle.
    b.cylinder(c, radius * 0.17, width + 0.12, "Wood_Dark", axis="X", segments=16)
    for side in (-1.0, 1.0):
        b.cylinder((side * (width / 2 + 0.04), 0, 0), radius * 0.2, 0.05, "Brass", axis="X", segments=16)
        for k in range(6):
            a = k / 6 * math.tau
            b.cylinder((side * (width / 2 + 0.075), math.cos(a) * radius * 0.13, math.sin(a) * radius * 0.13), 0.018, 0.03, "Iron", axis="X", segments=6)
    obj = b.finish()
    obj.location = Vector(center)
    if axis == "Y":
        obj.rotation_euler = (0, 0, math.pi / 2)
    obj["l05_role"] = "water_wheel"
    obj["l05_axis"] = axis
    obj["l05_radius"] = radius
    return obj


def gear_outline(radius, teeth, depth=None):
    depth = depth or radius * 0.16
    pts = []
    for i in range(teeth):
        a = i / teeth * math.tau
        step = math.tau / teeth
        for frac, r in ((0.0, radius - depth), (0.18, radius - depth), (0.3, radius), (0.62, radius), (0.74, radius - depth)):
            ang = a + frac * step
            pts.append((math.cos(ang) * r, math.sin(ang) * r))
    return pts


def build_gear(name, center, radius, teeth, thickness, axis="Z", mat="Brass", coll="L05/Mechanisms/Gears_Axles"):
    b = Builder(name, collection(coll))
    transform = _axis_matrix(axis)
    b.polygon_prism(gear_outline(radius, teeth), -thickness / 2, thickness / 2, mat, transform)
    # Recessed web, raised hub, bolt ring.
    web = [(math.cos(i / 24 * math.tau) * radius * 0.72, math.sin(i / 24 * math.tau) * radius * 0.72) for i in range(24)]
    b.polygon_prism(web, -thickness / 2 - 0.004, thickness / 2 + 0.004, "Iron", transform)
    b.cylinder(transform @ Vector((0, 0, 0)), radius * 0.26, thickness + 0.06, mat, rot=None, axis=axis, segments=16)
    for k in range(6):
        a = k / 6 * math.tau
        p = transform @ Vector((math.cos(a) * radius * 0.46, math.sin(a) * radius * 0.46, thickness / 2 + 0.01))
        b.cylinder(p, 0.022, 0.03, "Iron", axis=axis, segments=6)
    obj = b.finish()
    obj.location = Vector(center)
    obj["l05_role"] = "gear"
    obj["l05_kind"] = "spur"
    obj["l05_axis"] = axis
    obj["l05_axis_vec"] = list({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis])
    obj["l05_radius"] = radius
    obj["l05_teeth"] = teeth
    obj["l05_thickness"] = thickness
    return obj


def build_bevel_gear(name, apex, apex_dir, radius, teeth, cone_distance, face=0.07, mat="Brass"):
    """Bevel gear whose pitch cone points at `apex` along `apex_dir`.
    Its large end lies `cone_distance` (= the mating gear's pitch radius)
    from the apex, so two gears built on one apex mesh correctly."""
    b = Builder(name, collection("L05/Mechanisms/Gears_Axles"))
    a = Vector(apex_dir).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(a).to_matrix().to_4x4()
    scale = (cone_distance - face) / cone_distance
    b.polygon_prism(gear_outline(radius, teeth, radius * 0.14), 0.0, face, mat, rot, top_scale=scale)
    b.polygon_prism([(math.cos(i / 24 * math.tau) * radius * 0.7, math.sin(i / 24 * math.tau) * radius * 0.7) for i in range(24)], -0.004, face * 0.6, "Iron", rot)
    b.cylinder(rot @ Vector((0, 0, -0.04)), radius * 0.3, 0.1, mat, rot=Vector((0, 0, 1)).rotation_difference(a).to_euler(), segments=16)
    obj = b.finish()
    obj.location = Vector(apex) - a * cone_distance
    obj["l05_role"] = "gear"
    obj["l05_kind"] = "bevel"
    obj["l05_axis_vec"] = list(a)
    obj["l05_apex"] = list(apex)
    obj["l05_radius"] = radius
    obj["l05_teeth"] = teeth
    return obj


def build_shaft(name, p0, p1, radius=0.05, mat="Iron"):
    b = Builder(name, collection("L05/Mechanisms/Gears_Axles"))
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    mid = (p0 + p1) / 2
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
    b.cylinder((0, 0, 0), radius, d.length, mat, rot=rot, segments=12)
    for t in (0.08, 0.92):
        p = (p0 + d * t) - mid
        b.cylinder(p, radius * 1.7, 0.06, "Brass", rot=rot, segments=12)
    obj = b.finish()
    obj.location = mid
    obj["l05_role"] = "shaft"
    return obj


def bearing_block(b, center, axis="X"):
    b.box((center[0], center[1], center[2] - 0.12), (0.26, 0.26, 0.22), "Wood_Dark", bevel=0.02)
    b.box((center[0], center[1], center[2] + 0.04), (0.28, 0.28, 0.08), "Brass", bevel=0.015)
    b.box((center[0], center[1], center[2] - 0.5), (0.2, 0.2, 0.6), "Wood_Frame", bevel=0.02)


def support_post(b, x, y, z_top, z_ground=-1.5, size=0.2):
    """Timber post from the rock up to a bearing, with an iron foot."""
    b.box((x, y, (z_top + z_ground) / 2), (size, size, z_top - z_ground), "Wood_Frame", bevel=0.02)
    b.box((x, y, z_ground + 0.05), (size + 0.08, size + 0.08, 0.1), "Iron", bevel=0.01)


def journal(b, center, along, length=0.1, size=0.2):
    """Brass bearing journal clamped round a shaft (along = 'X'/'Y'/'Z')."""
    dims = {"X": (length, size, size), "Y": (size, length, size), "Z": (size, size, length)}[along]
    b.box(center, dims, "Brass", bevel=0.015)


def build_mechanisms():
    static = Builder("Mechanism_Supports", collection("L05/Static_Architecture/Timber"))
    wx, wy, wz = WHEEL_MAIN
    # Main wheel (breastshot) in its 2.5 m pit; journals sit on the pit wall
    # (south) and the deck's north wall.
    build_water_wheel("Wheel_Main", WHEEL_MAIN, 1.02, 0.55, axis="Y", paddles=16)
    journal(static, (wx, 5.6, wz), "Y", 0.12, 0.24)
    journal(static, (wx, 6.72, wz), "Y", 0.12, 0.24)
    build_shaft("Axle_Main", (wx, 5.56, wz), (wx, 7.05, wz), 0.07)
    # Classic mill gearing on the axle's north end: bevel pit wheel ->
    # bevel wallower -> vertical shaft -> runner millstone (the wheel's job).
    apex_m = (wx, 7.15, wz)
    build_bevel_gear("Gear_PitWheel", apex_m, (0, 1, 0), 0.42, 16, 0.18)
    build_bevel_gear("Gear_Wallower", apex_m, (0, 0, -1), 0.18, 7, 0.42)
    build_shaft("Shaft_Millstone", (wx, 7.15, wz + 0.45), (wx, 7.15, 2.36), 0.045)
    mill = Builder("Millstone_Floor", collection("L05/Static_Architecture/Timber"))
    mill.box((wx, 7.17, 2.08), (1.1, 0.46, 0.08), "Wood_Plank", bevel=0.01)
    for x in (wx - 0.5, wx + 0.5):
        support_post(mill, x, 7.32, 2.04, -1.5, 0.16)
    mill.cylinder((wx, 7.17, 2.18), 0.2, 0.12, "Stone_Masonry", segments=24)
    mill.cylinder((wx, 7.17, 2.62), 0.2, 0.22, "Wood_Plank", radius2=0.11, segments=12)
    mill.finish()
    runner = Builder("Millstone_Runner", collection("L05/Mechanisms/Gears_Axles"))
    runner.cylinder((0, 0, 0), 0.2, 0.1, "Stone_Masonry", segments=24)
    runner.cylinder((0, 0, 0.06), 0.05, 0.03, "Iron", segments=10)
    ro = runner.finish()
    ro.location = (wx, 7.17, 2.3)
    ro["l05_role"] = "millstone"
    ro["l05_axis_vec"] = [0, 0, 1]

    # East wheel (overshot), moved 0.15 m east so its bevel gear clears the deck.
    build_water_wheel("Wheel_East", (12.15, 2.6, 1.55), 0.74, 0.42, axis="X", paddles=12)
    build_shaft("Axle_East", (11.6, 2.6, 1.55), (12.66, 2.6, 1.55), 0.06)
    journal(static, (11.79, 2.6, 1.55), "X", 0.08, 0.18)
    journal(static, (12.55, 2.6, 1.55), "X", 0.1, 0.18)
    support_post(static, 11.79, 2.6, 1.45, -1.5, 0.16)
    support_post(static, 12.55, 2.6, 1.45, -1.5, 0.16)
    # Drive to the lift winch: three 90-degree bevel pairs (correct gear type
    # for intersecting shafts), one line shaft, one vertical shaft, 2:1 at the top.
    o1, o2, o3 = (11.47, 2.6, 1.55), (11.47, 1.0, 1.55), (11.47, 1.0, 4.7)
    build_bevel_gear("Gear_EastBevel", o1, (-1, 0, 0), 0.18, 10, 0.18)
    build_bevel_gear("Gear_LineBevelNorth", o1, (0, 1, 0), 0.18, 10, 0.18)
    build_shaft("Shaft_Line", (11.47, 2.38, 1.55), (11.47, 1.22, 1.55), 0.05)
    build_bevel_gear("Gear_LineBevelSouth", o2, (0, -1, 0), 0.18, 10, 0.18)
    build_bevel_gear("Gear_MastBevelLow", o2, (0, 0, -1), 0.18, 10, 0.18)
    build_shaft("Shaft_Mast", (11.47, 1.0, 1.75), (11.47, 1.0, 4.38), 0.05)
    build_bevel_gear("Gear_MastBevelTop", o3, (0, 0, 1), 0.15, 8, 0.30)
    build_bevel_gear("Gear_WinchBevel", o3, (1, 0, 0), 0.30, 16, 0.15)
    build_shaft("Shaft_Winch", (10.66, 1.0, 4.7), (11.3, 1.0, 4.7), 0.06)
    for y in (2.05, 1.45):
        journal(static, (11.47, y, 1.55), "Y", 0.1, 0.16)
        support_post(static, 11.47, y, 1.45, -1.5, 0.14)
    # Drive mast beside the tower holds the vertical shaft in two journals.
    support_post(static, 11.82, 1.0, 4.3, -1.5, 0.18)
    for z in (2.6, 4.0):
        static.box((11.65, 1.0, z), (0.3, 0.08, 0.08), "Iron", bevel=0.01)
        journal(static, (11.47, 1.0, z), "Z", 0.1, 0.16)
    # Small stream wheel by the start (undershot), raised 5 cm clear of the bed.
    build_water_wheel("Wheel_Stream", (2.5, 2.5, 0.10), 0.48, 0.32, axis="Y", paddles=10)
    for y in (2.08, 2.92):
        bearing_block(static, (2.5, y, 0.10))

    # Gear terrace: hand-cranked crown gear on a stone pillar (moved out of the
    # channel to the terrace corner). Spur pair with equal 143 mm pitch.
    build_gear("Gear_PillarCrown", (3.72, 6.95, Z1 + 0.95), 0.5, 22, 0.1, axis="Z")
    build_gear("Gear_CrankPinion", (3.72 + 0.648, 6.95, Z1 + 0.95), 0.2045, 9, 0.1, axis="Z")
    pillar = Builder("Gear_Pillar", collection("L05/Static_Architecture/Stone"))
    stone_pier(pillar, 3.72, 6.95, Z1, Z1 + 0.75, 0.55)
    pillar.cylinder((3.72, 6.95, Z1 + 0.85), 0.08, 0.3, "Iron")
    pillar.box((3.72 + 0.648, 6.95, Z1 + 0.42), (0.14, 0.14, 0.84), "Wood_Frame", bevel=0.02)
    pillar.cylinder((3.72 + 0.648, 6.95, Z1 + 0.88), 0.05, 0.1, "Iron")
    pillar.finish()
    crank = Builder("Crank_Handle", collection("L05/Mechanisms/Buttons_Levers"))
    _box_matrix(crank, Matrix.Translation((0.14, 0, 0)), (0.28, 0.05, 0.05), "Red_Paint", bevel=0.015)
    crank.cylinder((0.27, 0, 0.1), 0.035, 0.2, "Wood_Dark", segments=10)
    co = crank.finish()
    co.location = (3.72 + 0.648, 6.95, Z1 + 1.06)
    co["l05_role"] = "lever"
    static.finish()

    # Flush plates: rings rise at most 1.5 cm above the floor (v1: 0.115-0.30 m).
    build_gear("Gear_StartRing", (3.3, 4.0, Z0 - 0.03), 0.42, 16, 0.03, axis="Z")
    build_ring_plate("Plate_StartRing", (3.3, 4.0, Z0 - 0.04), 0.3, "Goal_Gold", "Iron")
    build_lever("Lever_Sluice", (2.2, 4.55, Z0), yaw=0.4)
    build_lever("Lever_Secret", (9.9, 4.4, Z0), yaw=-1.2)
    build_ring_plate("Plate_Cube", (7.9, 1.0, Z0 - 0.04), 0.34, "Plate_White", "Red_Paint")
    build_valve("Valve_Diverter", (6.6, 7.7, Z2 + 0.1), "X")
    build_valve("Valve_PoolSluice", (12.16, 5.3, Z2 - 0.05), "X")
    build_sluice_gate("Gate_StreamSluice", (1.6, 2.5, -0.2), "Y", 0.72)
    # The workshop shutter is now the wheel sluice in the middle channel.
    build_sluice_gate("Gate_MiddleShutter", (7.88, 6.2, Z1 - 0.04), "Y", 0.4, height=0.32)
    build_corridor_dressing()
    build_crate("Crate_Cube", (5.0, 1.0, Z0 + 0.23), 0.45)
    build_crate("Crate_Workshop", (6.3, 3.0, Z1 + 0.25), 0.5)
    build_crate("Crate_ValveDeck", (8.1, 9.2, Z2 + 0.25), 0.5)
    build_crate("Crate_Stack_A", (5.95, 3.62, Z1 + 0.25), 0.5)
    build_crate("Crate_Stack_B", (5.95, 3.62, Z1 + 0.76), 0.5, yaw=0.3)
    build_goal("Goal_Socket", (2.4, 8.6, Z2 - 0.05))


def build_corridor_dressing():
    """Hidden lower path (reference panel 04): beams, lanterns, gear and ring."""
    b = Builder("Corridor_Beams_Lanterns", collection("L05/Static_Architecture/Timber"))
    # Ceiling beams sit tight under the deck: 1.01 m clear (v1: 0.92 m).
    for x in (6.3, 7.2, 8.1, 8.9):
        b.box((x, 4.0, Z1 - DECK_T - 0.08), (0.18, 1.8, 0.14), "Wood_Dark", bevel=0.02)
        for y in (3.16, 4.84):
            b.box((x, y, (Z1 - DECK_T) / 2), (0.16, 0.1, Z1 - DECK_T), "Wood_Frame", bevel=0.02)
    for x, y in ((6.75, 3.27), (8.5, 4.73), (9.7, 4.85)):
        b.box((x, y, 0.92), (0.05, 0.05, 0.25), "Iron", bevel=0.005)
        b.box((x, y, 0.72), (0.14, 0.14, 0.2), "Lantern_Glow", bevel=0.01)
        b.box((x, y, 0.84), (0.18, 0.18, 0.04), "Brass", bevel=0.008)
        light = bpy.data.lights.new("Corridor_Lantern", "POINT")
        light.energy = 45
        light.color = (1.0, 0.6, 0.28)
        light.shadow_soft_size = 0.08
        lo = bpy.data.objects.new("Corridor_Lantern", light)
        lo.location = (x, y, 0.72)
        collection("L05/Lights_Cameras").objects.link(lo)
    b.finish()
    build_gear("Gear_CorridorTrigger", (8.2, 4.0, Z0 - 0.03), 0.32, 14, 0.03, axis="Z")
    build_ring_plate("Plate_CorridorRing", (8.2, 4.0, Z0 - 0.04), 0.24, "Goal_Gold", "Iron")


def build_ring_plate(name, center, radius, ring_mat, base_mat):
    """Flush pressure plate: placed 4 cm below the floor, its ring tops out
    1.5 cm above it, so balls roll and cubes slide over it."""
    b = Builder(name, collection("L05/Mechanisms/Buttons_Levers"))
    b.cylinder((0, 0, 0.0), radius + 0.08, 0.02, base_mat, segments=28)
    b.torus((0, 0, 0.03), radius, 0.025, ring_mat, seg_major=32, seg_minor=8)
    b.cylinder((0, 0, 0.012), radius * 0.8, 0.02, "Slate_Floor", segments=28)
    obj = b.finish()
    obj.location = Vector(center)
    obj["l05_role"] = "plate"
    return obj


def build_lever(name, base, yaw=0.0):
    col = collection("L05/Mechanisms/Buttons_Levers")
    b = Builder(name + "_Base", col)
    b.box((0, 0, 0.04), (0.5, 0.32, 0.08), "Iron", bevel=0.015)
    b.box((0, 0, 0.14), (0.16, 0.22, 0.14), "Brass", bevel=0.02)
    base_obj = b.finish()
    base_obj.location = Vector(base)
    base_obj.rotation_euler = (0, 0, yaw)
    arm = Builder(name, col)
    m = Matrix.Rotation(-0.6, 4, "Y")
    _box_matrix(arm, Matrix.Translation((0.2, 0, 0.0)) @ m, (0.55, 0.07, 0.07), "Red_Paint", bevel=0.02)
    arm.cylinder((0.42, 0, 0.3), 0.07, 0.16, "Wood_Dark", axis="Y", segments=12)
    arm.cylinder((0, 0, 0), 0.06, 0.26, "Brass", axis="Y", segments=12)
    arm_obj = arm.finish()
    arm_obj.location = Vector(base) + Vector((0, 0, 0.18))
    arm_obj.rotation_euler = (0, 0, yaw)
    arm_obj["l05_role"] = "lever"
    return arm_obj


def build_valve(name, center, axis="X"):
    b = Builder(name, collection("L05/Mechanisms/Buttons_Levers"))
    b.torus((0, 0, 0.42), 0.26, 0.035, "Red_Paint", seg_major=28, seg_minor=8)
    for k in range(4):
        a = k / 4 * math.tau
        _box_matrix(b, Matrix.Translation((math.cos(a) * 0.13, math.sin(a) * 0.13, 0.42)) @ Matrix.Rotation(a, 4, "Z"), (0.26, 0.035, 0.035), "Red_Paint", bevel=0.01)
    b.cylinder((0, 0, 0.42), 0.06, 0.08, "Brass", segments=12)
    b.cylinder((0, 0, 0.2), 0.035, 0.44, "Iron", segments=10)
    obj = b.finish()
    obj.location = Vector(center)
    obj["l05_role"] = "valve"
    housing = Builder(name + "_Housing", collection("L05/Mechanisms/Gates"))
    housing.box((0, 0, 0.05), (0.42, 0.42, 0.14), "Iron", bevel=0.02)
    housing.box((0, 0, -0.1), (0.36, 0.5, 0.25), "Brass", bevel=0.02)
    h = housing.finish()
    h.location = Vector(center)
    return obj


def build_sluice_gate(name, center, axis, width, height=0.45):
    frame = Builder(name + "_Frame", collection("L05/Static_Architecture/Timber"))
    for s in (-1, 1):
        off = (0, s * (width / 2 + 0.08), 0) if axis == "Y" else (s * (width / 2 + 0.08), 0, 0)
        frame.box((center[0] + off[0], center[1] + off[1], center[2] + height * 0.75), (0.14, 0.14, height * 1.9), "Wood_Frame", bevel=0.02)
        frame.box((center[0] + off[0], center[1] + off[1], center[2] + height * 1.72), (0.18, 0.18, 0.08), "Brass", bevel=0.015)
    top = (0.14, width + 0.3, 0.14) if axis == "Y" else (width + 0.3, 0.14, 0.14)
    frame.box((center[0], center[1], center[2] + height * 1.6), top, "Wood_Frame", bevel=0.02)
    frame.finish()
    gate = Builder(name, collection("L05/Mechanisms/Gates"))
    boards = 4
    for k in range(boards):
        size = (0.07, width, height / boards - 0.01) if axis == "Y" else (width, 0.07, height / boards - 0.01)
        gate.box((0, 0, (k + 0.5) * height / boards), size, "Wood_Plank", bevel=0.008)
    strap = (0.08, width + 0.02, 0.04) if axis == "Y" else (width + 0.02, 0.08, 0.04)
    for z in (0.08, height - 0.08):
        gate.box((0, 0, z), strap, "Iron", bevel=0.005)
    obj = gate.finish()
    obj.location = Vector(center)
    obj["l05_role"] = "gate"
    return obj


def build_crate(name, center, size, yaw=0.0):
    b = Builder(name, collection("L05/Mechanisms/Crates"))
    s = size
    t = s * 0.12
    b.box((0, 0, 0), (s - 0.03, s - 0.03, s - 0.03), "Wood_Plank", bevel=0.01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((sx * (s / 2 - t / 2), sy * (s / 2 - t / 2), 0), (t, t, s), "Wood_Frame", bevel=0.01)
    for sz in (-1, 1):
        for sx in (-1, 1):
            b.box((sx * (s / 2 - t / 2), 0, sz * (s / 2 - t / 2)), (t, s, t), "Wood_Frame", bevel=0.01)
            b.box((0, sx * (s / 2 - t / 2), sz * (s / 2 - t / 2)), (s, t, t), "Wood_Frame", bevel=0.01)
    for face in range(4):
        yaw_f = face * math.pi / 2
        m = Matrix.Rotation(yaw_f, 4, "Z") @ Matrix.Translation((0, -s / 2 + 0.005, 0)) @ Matrix.Rotation(math.pi / 4, 4, "Y")
        _box_matrix(b, m, (s * 1.25, 0.02, t * 0.7), "Wood_Frame", bevel=0.005)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                b.box((sx * s / 2, sy * s / 2, sz * s / 2), (t * 0.9, t * 0.9, t * 0.9), "Brass", bevel=0.008)
    obj = b.finish()
    obj.location = Vector(center)
    obj.rotation_euler = (0, 0, yaw)
    obj["l05_role"] = "crate"
    return obj


def build_goal(name, center):
    """Recessed socket: placed 5 cm below the floor, the gold ring tops out
    1 cm above it; the marble rolls in and settles in the 5 cm dish."""
    b = Builder(name, collection("L05/Mechanisms/Buttons_Levers"))
    b.cylinder((0, 0, 0.01), 0.62, 0.02, "Iron", segments=36)
    b.torus((0, 0, 0.02), 0.46, 0.04, "Goal_Gold", seg_major=40, seg_minor=10)
    b.torus((0, 0, 0.015), 0.58, 0.02, "Brass", seg_major=40, seg_minor=6)
    b.cylinder((0, 0, 0.021), 0.4, 0.004, "Slate_Floor", segments=36)
    obj = b.finish()
    obj.location = Vector(center)
    obj["l05_role"] = "goal_socket"
    return obj


def build_lift():
    x0, x1, y0, y1 = LIFT["x0"], LIFT["x1"], LIFT["y0"], LIFT["y1"]
    tower = Builder("Lift_Tower", collection("L05/Mechanisms/Lift"))
    top = Z2 + 1.65
    for x in (x0 - 0.1, x1 + 0.1):
        for y in (y0 - 0.1, y1 + 0.1):
            tower.box((x, y, (top - 1.6) / 2 + 0.0 - 0.8 + 0.8), (0.2, 0.2, top + 1.6), "Wood_Frame", bevel=0.025)
            tower.box((x, y, top + 0.1), (0.25, 0.25, 0.12), "Brass", bevel=0.02)
    # Bracing only on the two closed faces (south and east).
    for z in (0.75, 2.15, 3.55):
        tower.box(((x0 + x1) / 2, y0 - 0.1, z), (x1 - x0 + 0.2, 0.12, 0.14), "Wood_Frame", bevel=0.02)
        tower.box((x1 + 0.1, (y0 + y1) / 2, z), (0.12, y1 - y0 + 0.2, 0.14), "Wood_Frame", bevel=0.02)
    for z0, z1 in ((-0.6, 0.75), (0.75, 2.15), (2.15, 3.55)):
        for face in ("S", "E"):
            length = (x1 - x0 + 0.2) if face == "S" else (y1 - y0 + 0.2)
            ang = math.atan2(z1 - z0, length)
            diag = math.hypot(z1 - z0, length)
            if face == "S":
                m = Matrix.Translation(((x0 + x1) / 2, y0 - 0.16, (z0 + z1) / 2)) @ Matrix.Rotation(-ang, 4, "Y")
            else:
                m = Matrix.Translation((x1 + 0.16, (y0 + y1) / 2, (z0 + z1) / 2)) @ Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Rotation(-ang, 4, "Y")
            _box_matrix(tower, m, (diag, 0.08, 0.1), "Wood_Frame", bevel=0.015)
    # North header under the walk's south edge (replaces the v1 piers in the shaft);
    # it sits between the middle and upper doorways.
    tower.box(((x0 + x1) / 2, y1 + 0.1, Z2 - DECK_T - 0.08), (x1 - x0 + 0.4, 0.2, 0.16), "Wood_Frame", bevel=0.02)
    # Header frame, pulley sheaves and winch drum.
    for y in (y0 - 0.1, y1 + 0.1):
        tower.box(((x0 + x1) / 2, y, top), (x1 - x0 + 0.4, 0.2, 0.2), "Wood_Frame", bevel=0.025)
    for x in (x0 - 0.1, x1 + 0.1):
        tower.box((x, (y0 + y1) / 2, top), (0.2, y1 - y0 + 0.4, 0.2), "Wood_Frame", bevel=0.025)
    tower.cylinder(((x0 + x1) / 2, (y0 + y1) / 2, top + 0.25), 0.22, x1 - x0 + 0.2, "Wood_Dark", axis="X", segments=18)
    for x in (x0 + 0.25, x1 - 0.25):
        tower.cylinder((x, (y0 + y1) / 2, top + 0.25), 0.27, 0.05, "Iron", axis="X", segments=20)
    # Guide rails on the shaft corners: 5 cm clear of the cage.
    for x in (x0, x1):
        for y in (y0, y1):
            tower.box((x, y, (top - 0.6) / 2 + 0.0), (0.05, 0.05, top + 0.6), "Iron", bevel=0.005)
    # Counterweight on the south face (v1 sat on the drive shaft's path).
    tower.box(((x0 + x1) / 2, y0 - 0.32, 2.4), (0.5, 0.3, 0.7), "Stone_Masonry", bevel=0.03)
    for z in (2.15, 2.65):
        tower.box(((x0 + x1) / 2, y0 - 0.32, z), (0.53, 0.33, 0.05), "Iron", bevel=0.005)
    for x in ((x0 + x1) / 2 - 0.3, (x0 + x1) / 2 + 0.3):
        tower.box((x, y0 - 0.32, (top + 0.2) / 2), (0.03, 0.03, top - 0.2), "Iron", bevel=0.0)
    tower.finish()

    cage = Builder("Lift_Cage", collection("L05/Mechanisms/Lift"))
    w, d = x1 - x0 - 0.16, y1 - y0 - 0.16
    for k in range(6):
        cage.box((0, -d / 2 + (k + 0.5) * d / 6, -0.03), (w, d / 6 - 0.015, 0.06), "Wood_Plank", bevel=0.008)
    cage.box((0, 0, -0.12), (w, d, 0.12), "Wood_Dark", bevel=0.01)
    # Fixed lips on the closed south and east sides; corner posts with brass.
    cage.box((0, -d / 2 + 0.05, 0.14), (w, 0.1, 0.28), "Wood_Frame", bevel=0.02)
    cage.box((w / 2 - 0.05, 0, 0.14), (0.1, d, 0.28), "Wood_Frame", bevel=0.02)
    # Crossbar 1.0 m up: 0.95 m clear for the marble, cubes and 0.75 m pyramids.
    for sx in (-1, 1):
        for sy in (-1, 1):
            cage.box((sx * (w / 2 - 0.06), sy * (d / 2 - 0.06), 0.5), (0.12, 0.12, 1.0), "Wood_Frame", bevel=0.02)
            cage.box((sx * (w / 2 - 0.06), sy * (d / 2 - 0.06), 1.03), (0.15, 0.15, 0.06), "Brass", bevel=0.015)
    cage.box((0, 0, 1.0), (w, 0.1, 0.1), "Wood_Frame", bevel=0.02)
    cage.cylinder((0, 0, 1.08), 0.06, 0.1, "Iron", segments=10)
    cage_obj = cage.finish()
    cage_obj.location = ((x0 + x1) / 2, (y0 + y1) / 2, Z0)
    cage_obj["l05_role"] = "lift_deck"
    cage_obj["l05_floors"] = [Z0, Z1, Z2]
    for gate_name, at, axis in (("Lift_Gate_West", (x0 + 0.11, (y0 + y1) / 2, Z0), "Y"), ("Lift_Gate_North", ((x0 + x1) / 2, y1 - 0.11, Z0), "X")):
        g = Builder(gate_name, collection("L05/Mechanisms/Lift"))
        for k in range(3):
            size = (0.05, d - 0.2, 0.06) if axis == "Y" else (w - 0.2, 0.05, 0.06)
            g.box((0, 0, 0.1 + k * 0.12), size, "Wood_Frame", bevel=0.01)
        go = g.finish()
        go.location = at
        go["l05_role"] = "lift_gate"
    chain = Builder("Lift_Chain", collection("L05/Mechanisms/Lift"))
    links = int((top + 0.25 - 1.12) / 0.09)
    for k in range(links):
        z = 1.12 + k * 0.09
        chain.torus((0, 0, z), 0.035, 0.009, "Iron", axis="X" if k % 2 else "Y", seg_major=10, seg_minor=4)
    co = chain.finish()
    co.location = ((x0 + x1) / 2, (y0 + y1) / 2, Z0)
    co["l05_role"] = "lift_chain"


# ----------------------------------------------------------------------------
# Summit millhouse: timber frame, plank walls, door, glowing windows, tile roof
# ----------------------------------------------------------------------------

LANTERN_DECKS = ("L_Start", "L_Front", "L_FrontEast", "M_Workshop", "M_GearTerrace", "U_PoolDeck", "U_ValveDeck", "U_GoalDeck")


def build_lanterns():
    """Warm lanterns on the outer corner posts of the decks (reference: glowing
    lamps on every tier). They sit on the post caps, outside every lane, in a
    dressing collection that is not solid for the lane audit."""
    b = Builder("Railing_Lanterns", collection("L05/Dressing/Lanterns"))
    count = 0
    for name, x0, x1, y0, y1, z, _m, openings, _zone in DECKS:
        if name not in LANTERN_DECKS:
            continue
        notches = SPILL_NOTCHES.get(name, {})
        for cx, cy, sides in ((x0, y0, "SW"), (x1, y0, "SE"), (x0, y1, "NW"), (x1, y1, "NE")):
            free = True
            for side in sides:
                a = cx if side in "SN" else cy
                for s0, s1 in list(openings.get(side, [])) + list(notches.get(side, [])):
                    if s0 - 0.3 <= a <= s1 + 0.3:
                        free = False
            if not free:
                continue
            px = cx + (0.085 if cx == x0 else -0.085)
            py = cy + (0.08 if cy == y0 else -0.08)
            zt = z + RAIL_H + 0.125
            b.box((px, py, zt + 0.015), (0.13, 0.13, 0.03), "Iron", bevel=0.005)
            b.box((px, py, zt + 0.11), (0.1, 0.1, 0.16), "Lantern_Glow", bevel=0.008)
            for dx in (-0.055, 0.055):
                for dy in (-0.055, 0.055):
                    b.box((px + dx, py + dy, zt + 0.11), (0.018, 0.018, 0.17), "Brass", bevel=0.003)
            b.box((px, py, zt + 0.21), (0.16, 0.16, 0.04), "Brass", bevel=0.01)
            b.box((px, py, zt + 0.25), (0.05, 0.05, 0.05), "Brass", bevel=0.01)
            light = bpy.data.lights.new("Railing_Lantern", "POINT")
            light.energy = 14
            light.color = (1.0, 0.62, 0.3)
            light.shadow_soft_size = 0.05
            lo = bpy.data.objects.new("Railing_Lantern", light)
            lo.location = (px, py, zt + 0.11)
            collection("L05/Lights_Cameras").objects.link(lo)
            count += 1
    b.finish()
    return count


def build_millhouse():
    col = collection("L05/Static_Architecture/Millhouse")
    x0, x1, y0, y1 = 6.55, 9.1, 10.1, 11.85
    zf = Z2 + 0.32
    wall_h = 2.0
    b = Builder("Millhouse_Walls", col)
    # Vertical board-and-batten walls with a heavy timber frame.
    def plank_wall(p0, p1, openings):
        p0, p1 = Vector((*p0, 0)), Vector((*p1, 0))
        d = (p1 - p0)
        length = d.length
        d.normalize()
        yaw = math.atan2(d.y, d.x)
        n_boards = int(length / 0.18)
        for k in range(n_boards):
            a = (k + 0.5) * length / n_boards
            for z0, z1 in _wall_spans(a, openings, wall_h):
                c = p0 + d * a
                b.box((c.x, c.y, zf + (z0 + z1) / 2), (length / n_boards - 0.012, 0.07, z1 - z0), "Wood_Weathered", rot=(0, 0, yaw), bevel=0.006)
        for z in (0.04, wall_h * 0.55, wall_h - 0.06):
            c = p0 + d * (length / 2)
            b.box((c.x, c.y, zf + z), (length, 0.14, 0.12), "Wood_Dark", rot=(0, 0, yaw), bevel=0.015)
        # Diagonal braces (Alpine half-timbering).
        for s in (0.25, 0.75):
            c = p0 + d * (length * s)
            m = Matrix.Translation((c.x, c.y, zf + wall_h * 0.28)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(0.75 if s < 0.5 else -0.75, 4, "Y")
            _box_matrix(b, m, (wall_h * 0.62, 0.1, 0.09), "Wood_Dark", bevel=0.012)
    front = [(1.275, 0.95, 0.0, 1.75, "door"), (0.42, 0.55, 0.85, 1.55, "window"), (2.13, 0.55, 0.85, 1.55, "window")]
    side = [(0.9, 0.6, 0.8, 1.5, "window")]
    plank_wall((x0, y0), (x1, y0), front)
    plank_wall((x1, y0), (x1, y1), side)
    plank_wall((x1, y1), (x0, y1), [(1.275, 0.6, 0.8, 1.5, "window")])
    plank_wall((x0, y1), (x0, y0), side)
    for x in (x0, x1):
        for y in (y0, y1):
            b.box((x, y, zf + wall_h / 2), (0.2, 0.2, wall_h + 0.1), "Wood_Dark", bevel=0.02)
    _openings_detail(b, (x0, y0), (x1, y0), front, zf, "-Y")
    _openings_detail(b, (x1, y0), (x1, y1), side, zf, "+X")
    _openings_detail(b, (x0, y1), (x0, y0), side, zf, "-X")
    _openings_detail(b, (x1, y1), (x0, y1), [(1.275, 0.6, 0.8, 1.5, "window")], zf, "+Y")
    # Gable ends (ridge runs along Y so the gable faces the camera like the reference).
    ridge_h = 1.15
    for y, sign in ((y0, -1), (y1, 1)):
        rows = 7
        for r in range(rows):
            t0, t1 = r / rows, (r + 1) / rows
            half = (x1 - x0) / 2 * (1 - (t0 + t1) / 2)
            b.box(((x0 + x1) / 2, y + sign * 0.01, zf + wall_h + (t0 + t1) / 2 * ridge_h), (half * 2, 0.07, ridge_h / rows - 0.01), "Wood_Weathered", bevel=0.005)
        b.box(((x0 + x1) / 2, y + sign * 0.05, zf + wall_h + ridge_h * 0.38), (0.36, 0.05, 0.36), "Window_Glow", bevel=0.01)
        b.box(((x0 + x1) / 2, y + sign * 0.07, zf + wall_h + ridge_h * 0.38), (0.44, 0.04, 0.06), "Wood_Dark", bevel=0.005)
        b.box(((x0 + x1) / 2, y + sign * 0.07, zf + wall_h + ridge_h * 0.38), (0.06, 0.04, 0.44), "Wood_Dark", bevel=0.005)
    b.finish()
    build_roof(x0, x1, y0, y1, zf + wall_h, ridge_h)
    # Chimney, lantern on bracket, banner.
    d = Builder("Millhouse_Details", col)
    for r in range(7):
        d.box((x1 - 0.55, y1 - 0.5, zf + wall_h + 0.4 + r * 0.24), (0.42, 0.42, 0.22), "Stone_Masonry", bevel=0.02)
    d.box((x1 - 0.55, y1 - 0.5, zf + wall_h + 2.1), (0.5, 0.5, 0.08), "Stone_Masonry", bevel=0.02)
    for lx in (x0 - 0.18, x1 + 0.18):
        d.box((lx, y0 - 0.25, zf + 1.85), (0.06, 0.45, 0.06), "Iron", bevel=0.005)
        d.box((lx, y0 - 0.45, zf + 1.62), (0.18, 0.18, 0.28), "Lantern_Glow", bevel=0.01)
        d.box((lx, y0 - 0.45, zf + 1.79), (0.24, 0.24, 0.05), "Brass", bevel=0.01)
        d.box((lx, y0 - 0.45, zf + 1.46), (0.22, 0.22, 0.04), "Brass", bevel=0.01)
    d.box((x0 - 0.06, y0 + 0.9, zf + 1.15), (0.03, 0.55, 1.0), "Banner_Red", bevel=0.005)
    d.cylinder((x0 - 0.08, y0 + 0.9, zf + 1.25), 0.14, 0.02, "Brass", axis="X", segments=16)
    d.box((x0 - 0.08, y0 + 0.9, zf + 1.68), (0.05, 0.7, 0.05), "Wood_Dark", bevel=0.005)
    # Doorstep stairs from the valve deck up the plinth.
    for k in range(2):
        d.box(((x0 + x1) / 2, y0 - 0.35 + k * 0.16, Z2 + 0.08 + k * 0.12), (1.1, 0.34, 0.16), "Stone_Masonry", bevel=0.02)
    d.finish()
    for lx in (x0 - 0.18, x1 + 0.18):
        light = bpy.data.lights.new("Lantern_Light", "POINT")
        light.energy = 60
        light.color = (1.0, 0.62, 0.3)
        light.shadow_soft_size = 0.1
        lo = bpy.data.objects.new("Lantern_Light", light)
        lo.location = (lx, y0 - 0.45, zf + 1.62)
        collection("L05/Lights_Cameras").objects.link(lo)


def _wall_spans(a, openings, wall_h):
    spans = [(0.0, wall_h)]
    for center, width, z0, z1, _kind in openings:
        if abs(a - center) < width / 2:
            spans = [(s0, min(s1, z0)) for s0, s1 in spans if s0 < z0] + [(max(s0, z1), s1) for s0, s1 in spans if s1 > z1]
    return [s for s in spans if s[1] - s[0] > 0.02]


def _openings_detail(b, p0, p1, openings, zf, facing):
    p0, p1 = Vector((*p0, 0)), Vector((*p1, 0))
    d = (p1 - p0).normalized()
    out = Vector((d.y, -d.x, 0))
    yaw = math.atan2(d.y, d.x)
    for center, width, z0, z1, kind in openings:
        c = p0 + d * center
        if kind == "door":
            for k in range(5):
                bc = c + d * (-width / 2 + (k + 0.5) * width / 5) - out * 0.0
                b.box((bc.x, bc.y, zf + (z1 - z0) / 2), (width / 5 - 0.01, 0.06, z1 - z0), "Wood_Dark", rot=(0, 0, yaw), bevel=0.006)
            for z in (0.35, 1.35):
                hc = c + out * 0.04
                b.box((hc.x, hc.y, zf + z), (width * 0.9, 0.02, 0.06), "Iron", rot=(0, 0, yaw), bevel=0.004)
            rc = c + out * 0.05 + d * (width * 0.3)
            b.torus((rc.x, rc.y, zf + 0.95), 0.06, 0.012, "Brass", axis="Y" if abs(d.x) > 0.5 else "X", seg_major=12, seg_minor=4)
        else:
            gc = c - out * 0.0
            b.box((gc.x, gc.y, zf + (z0 + z1) / 2), (width, 0.03, z1 - z0), "Window_Glow", rot=(0, 0, yaw), bevel=0.004)
            fc = c + out * 0.03
            b.box((fc.x, fc.y, zf + (z0 + z1) / 2), (0.05, 0.05, z1 - z0), "Wood_Dark", rot=(0, 0, yaw), bevel=0.005)
            b.box((fc.x, fc.y, zf + (z0 + z1) / 2), (width, 0.05, 0.05), "Wood_Dark", rot=(0, 0, yaw), bevel=0.005)
        # Frame around every opening.
        oc = c + out * 0.05
        b.box((oc.x, oc.y, zf + z1 + 0.04), (width + 0.16, 0.08, 0.09), "Wood_Frame", rot=(0, 0, yaw), bevel=0.01)
        if kind == "window":
            b.box((oc.x, oc.y, zf + z0 - 0.05), (width + 0.2, 0.14, 0.07), "Wood_Frame", rot=(0, 0, yaw), bevel=0.01)
            # Flower box under the window.
            fb = c + out * 0.15
            b.box((fb.x, fb.y, zf + z0 - 0.16), (width, 0.16, 0.14), "Wood_Plank", rot=(0, 0, yaw), bevel=0.01)
            for k in range(5):
                fl = fb + d * (-width / 2 + 0.1 + k * (width - 0.2) / 4)
                b.box((fl.x, fl.y, zf + z0 - 0.05), (0.09, 0.09, 0.09), "Grass" if k % 2 else "Red_Paint", bevel=0.03)
        for s in (-1, 1):
            sc = c + d * (s * (width / 2 + 0.04)) + out * 0.05
            b.box((sc.x, sc.y, zf + (z0 + z1) / 2), (0.08, 0.08, z1 - z0 + 0.1), "Wood_Frame", rot=(0, 0, yaw), bevel=0.01)


def build_roof(x0, x1, y0, y1, z_eave, ridge_h):
    b = Builder("Millhouse_Roof", collection("L05/Static_Architecture/Millhouse"))
    over = 0.35
    half = (x1 - x0) / 2 + over
    pitch = math.atan2(ridge_h + over * ridge_h / ((x1 - x0) / 2), half)
    slope_len = half / math.cos(pitch)
    tile_w, tile_l = 0.26, 0.3
    cols = int((y1 - y0 + 2 * over) / tile_w)
    rows = int(slope_len / (tile_l * 0.72))
    xm = (x0 + x1) / 2
    z_ridge = z_eave + ridge_h
    for side in (-1, 1):
        # Rafters and roof boards under the tiles.
        for k in range(5):
            y = y0 - over + k * (y1 - y0 + 2 * over) / 4
            m = Matrix.Translation((xm + side * half / 2, y, z_ridge - math.tan(pitch) * half / 2 - 0.12)) @ Matrix.Rotation(side * pitch, 4, "Y")
            _box_matrix(b, m, (slope_len, 0.1, 0.14), "Wood_Dark", bevel=0.015)
        m = Matrix.Translation((xm + side * half / 2, (y0 + y1) / 2, z_ridge - math.tan(pitch) * half / 2 - 0.04)) @ Matrix.Rotation(side * pitch, 4, "Y")
        _box_matrix(b, m, (slope_len, y1 - y0 + 2 * over, 0.04), "Wood_Plank", bevel=0.0)
        for r in range(rows):
            dist = slope_len - (r + 0.5) * tile_l * 0.72
            hx = math.cos(pitch) * dist
            z = z_ridge - math.sin(pitch) * dist + 0.03
            stagger = (tile_w / 2) if r % 2 else 0.0
            for c in range(cols + 1):
                y = y0 - over + c * tile_w + stagger
                if y > y1 + over:
                    continue
                m = Matrix.Translation((xm + side * hx, y, z)) @ Matrix.Rotation(side * (pitch + 0.06), 4, "Y") @ Matrix.Rotation(RNG.uniform(-0.03, 0.03), 4, "Z")
                _box_matrix(b, m, (tile_l, tile_w - 0.015, 0.025 + RNG.uniform(0, 0.01)), "Roof_Slate" if RNG.random() > 0.35 else "Roof_Shingle", bevel=0.006)
        # Barge boards along the gables.
        for y in (y0 - over, y1 + over):
            m = Matrix.Translation((xm + side * half / 2, y, z_ridge - math.tan(pitch) * half / 2 + 0.02)) @ Matrix.Rotation(side * pitch, 4, "Y")
            _box_matrix(b, m, (slope_len + 0.05, 0.06, 0.16), "Wood_Frame", bevel=0.01)
    b.cylinder((xm, (y0 + y1) / 2, z_ridge + 0.06), 0.09, y1 - y0 + 2 * over + 0.1, "Roof_Slate", axis="Y", segments=10)
    b.finish()


# ----------------------------------------------------------------------------
# Vegetation: Alpine firs from drooping branch tiers, grass and moss tufts
# ----------------------------------------------------------------------------

def fir_mesh(name, height, seed, far=False):
    rng = random.Random(seed)
    b = Builder(name, collection("L05/Vegetation/_Fir_Variants"))
    b.cylinder((0, 0, height * 0.2), height * 0.035, height * 0.4, "Bark", segments=7)
    tiers = 8 if not far else 5
    for t in range(tiers):
        f = t / tiers
        z = height * (0.18 + 0.78 * f)
        radius = height * 0.36 * (1.0 - f) ** 0.95 + height * 0.04
        branches = 9 if not far else 6
        droop = radius * 0.55
        index = b._mi("Fir_Needles_Far" if far else "Fir_Needles")
        offset = rng.random() * math.tau
        for k in range(branches):
            a = offset + k / branches * math.tau + rng.uniform(-0.12, 0.12)
            r = radius * rng.uniform(0.85, 1.12)
            w = r * 0.42
            ca, sa = math.cos(a), math.sin(a)
            root = b.bm.verts.new((0, 0, z + 0.05 * height))
            mid_l = b.bm.verts.new((ca * r * 0.5 - sa * w, sa * r * 0.5 + ca * w, z - droop * 0.35))
            mid_r = b.bm.verts.new((ca * r * 0.5 + sa * w, sa * r * 0.5 - ca * w, z - droop * 0.35))
            tip = b.bm.verts.new((ca * r, sa * r, z - droop))
            under = b.bm.verts.new((ca * r * 0.45, sa * r * 0.45, z - droop * 0.75))
            for face in ((root, mid_l, tip, mid_r), (mid_l, under, tip), (mid_r, tip, under), (root, under, mid_l), (root, mid_r, under)):
                nf = b.bm.faces.new(face)
                nf.material_index = index
                nf.smooth = True
        # Dense inner cone so tiers never look hollow.
        b.cylinder((0, 0, z - droop * 0.45), radius * 0.55, droop * 1.2, "Fir_Needles_Far" if far else "Fir_Needles", radius2=radius * 0.12, segments=8)
    b.cylinder((0, 0, height * 1.0), height * 0.05, height * 0.12, "Fir_Needles", radius2=0.0, segments=6)
    obj = b.finish()
    obj.hide_render = True
    obj.hide_viewport = True
    return obj


def scatter_firs():
    variants = [fir_mesh("Fir_Variant_%d" % i, 1.0, 900 + i) for i in range(5)]
    far = [fir_mesh("Fir_Far_Variant_%d" % i, 1.0, 950 + i, far=True) for i in range(3)]
    col = collection("L05/Vegetation/Firs")
    rng = random.Random(42)
    placed = []
    fx0, fx1, fy0, fy1 = FOOTPRINT

    def place(x, y, h, pool):
        src = rng.choice(pool)
        obj = bpy.data.objects.new(src.name.replace("_Variant", ""), src.data)
        z = ground_height(x, y) - 0.1
        obj.location = (x, y, z)
        obj.rotation_euler = (rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04), rng.random() * math.tau)
        obj.scale = (h * rng.uniform(0.85, 1.1), h * rng.uniform(0.85, 1.1), h)
        col.objects.link(obj)
        placed.append(obj)

    # Near ring: varied heights hugging the cliff edges (kept off the lanes and
    # off the camera side so nothing hides the board).
    for k in range(140):
        side = rng.random()
        if side < 0.35:
            x, y = rng.uniform(-6, 2.5), rng.uniform(-2, 16)
        elif side < 0.6:
            x, y = rng.uniform(-3, 16), rng.uniform(13.2, 22)
        elif side < 0.85:
            x, y = rng.uniform(13.0, 22), rng.uniform(-3, 16)
        else:
            x, y = rng.uniform(-4, 14), rng.uniform(-6, -1.6)
        if fx0 - 0.4 < x < fx1 + 0.4 and fy0 - 0.4 < y < fy1 + 0.4:
            continue
        dist = max(0.0, max(fx0 - x, x - fx1, fy0 - y, y - fy1))
        h = rng.uniform(1.6, 3.6) * (1.0 + dist * 0.04)
        if y < 0 and x < 8:
            h *= 0.6
        place(x, y, h, variants)
    # Lower slopes in front of the cliff: small firs well below the board.
    for k in range(70):
        x, y = rng.uniform(-8, 16), rng.uniform(-9, -2.5)
        if rng.random() < 0.5:
            x, y = rng.uniform(-9, -2.5), rng.uniform(-6, 14)
        place(x, y, rng.uniform(1.4, 3.0), variants)
    # Far forest band on the ridge behind the mill.
    for k in range(220):
        a = rng.uniform(-0.3, 1.9)
        r = rng.uniform(24, 40)
        place(6 + math.cos(a) * r, 6 + math.sin(a) * r, rng.uniform(3.0, 6.0), far)
    return placed


def scatter_grass():
    b = Builder("Grass_Moss_Tufts", collection("L05/Vegetation"))
    rng = random.Random(9)
    fx0, fx1, fy0, fy1 = FOOTPRINT
    index = b._mi("Grass")
    for k in range(900):
        x, y = rng.uniform(fx0 - 6, fx1 + 6), rng.uniform(fy0 - 6, fy1 + 8)
        if fx0 + 0.3 < x < fx1 - 0.3 and fy0 + 0.3 < y < fy1 - 0.3 and rng.random() < 0.7:
            continue
        z = ground_height(x, y)
        blades = rng.randint(5, 9)
        for i in range(blades):
            a = rng.random() * math.tau
            h = rng.uniform(0.12, 0.32)
            lean = rng.uniform(0.03, 0.1)
            v0 = b.bm.verts.new((x + math.cos(a + 1.6) * 0.02, y + math.sin(a + 1.6) * 0.02, z))
            v1 = b.bm.verts.new((x - math.cos(a + 1.6) * 0.02, y - math.sin(a + 1.6) * 0.02, z))
            v2 = b.bm.verts.new((x + math.cos(a) * lean, y + math.sin(a) * lean, z + h))
            f = b.bm.faces.new((v0, v1, v2))
            f.material_index = index
            f.smooth = True
    return b.finish()


# ----------------------------------------------------------------------------
# Background: snowy peaks, distant viaduct, sky and sun
# ----------------------------------------------------------------------------

def build_mountains():
    col = collection("L05/Background")
    specs = [
        # centre (x, y), radius, height, seed
        ((150, 120), 55, 70, 1), ((210, 40), 60, 78, 2), ((60, 200), 55, 58, 3), ((230, -40), 55, 66, 4), ((180, 190), 50, 62, 5), ((-60, 210), 60, 48, 6), ((260, 120), 60, 74, 7),
    ]
    peaks = []
    for k, (c, radius, height, seed) in enumerate(specs):
        bm = bmesh.new()
        res = 70
        grid = []
        for j in range(res + 1):
            row = []
            for i in range(res + 1):
                u, v = i / res * 2 - 1, j / res * 2 - 1
                x, y = c[0] + u * radius * 1.6, c[1] + v * radius * 1.6
                r = math.hypot(u, v)
                # Ridged multifractal: sharp aretes and couloirs like Alpine peaks.
                ridge = 0.0
                amp, freq = 1.0, 2.2
                for _octave in range(4):
                    ridge += (1.0 - abs(noise.noise(Vector((u * freq + seed * 1.7, v * freq, seed))))) ** 2 * amp
                    amp *= 0.5
                    freq *= 2.1
                h = max(0.0, 1.0 - r) ** 1.15 * height * (0.45 + ridge * 0.45)
                row.append(bm.verts.new((x, y, h - 95)))
            grid.append(row)
        for j in range(res):
            for i in range(res):
                f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
                f.smooth = True
        mesh = bpy.data.meshes.new("Alps_Peak_%d" % k)
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(MATS["Mountain_Snow"])
        obj = bpy.data.objects.new("Alps_Peak_%d" % k, mesh)
        col.objects.link(obj)
        _box_uv(obj)
        peaks.append(obj)
    _mountain_forests(peaks)
    _backdrop_cards()


def _mountain_forests(peaks):
    """Conifer forest on the lower, gentler flanks of the peaks (instanced
    far-fir meshes, own RNG): rock shows above the tree line, snow above that."""
    col = collection("L05/Background/Forests")
    rng = random.Random(6262)
    far = [bpy.data.objects["Fir_Far_Variant_%d" % i].data for i in range(3)]
    count = 0
    for peak in peaks:
        for v in peak.data.vertices:
            if not (-93.0 < v.co.z < -64.0) or v.normal.z < 0.6 or rng.random() > 0.11:
                continue
            obj = bpy.data.objects.new("Fir_Mountain", rng.choice(far))
            h = rng.uniform(7.0, 12.0) * (1.0 - (v.co.z + 93.0) / 60.0)
            obj.location = (v.co.x + rng.uniform(-0.8, 0.8), v.co.y + rng.uniform(-0.8, 0.8), v.co.z - 0.4)
            obj.rotation_euler = (0.0, 0.0, rng.random() * math.tau)
            obj.scale = (h * rng.uniform(0.8, 1.1), h * rng.uniform(0.8, 1.1), h)
            col.objects.link(obj)
            count += 1
    return count


def _card(name, mat, center, width, height, facing=(6.0, 6.0)):
    """Vertical backdrop quad facing the board centre (0..1 UVs)."""
    c = Vector(center)
    d = Vector((facing[0] - c.x, facing[1] - c.y, 0.0)).normalized()
    right = Vector((-d.y, d.x, 0.0)) * (width / 2)
    verts = [c - right, c + right, c + right + Vector((0, 0, height)), c - right + Vector((0, 0, height))]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new(name="UVMap")
    for li, co in zip(range(4), ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[li].uv = co
    mesh.materials.append(MATS[mat])
    obj = bpy.data.objects.new(name, mesh)
    collection("L05/Background/Parallax_Cards").objects.link(obj)
    obj.visible_shadow = False
    return obj


def _backdrop_cards():
    """Mid forest slopes and low cloud banks between the summit and the peaks,
    from the Level 05 Luma parallax images (Godot uses the same images)."""
    rng = random.Random(7373)
    for k, deg in enumerate((-15, 10, 32, 55, 78, 100, 125, 150)):
        a = math.radians(deg)
        r = rng.uniform(64.0, 74.0)
        _card("Forest_Card_%d" % k, "Forest_Card", (6 + math.cos(a) * r, 6 + math.sin(a) * r, -50.0), 150.0, 50.0)
    for k, deg in enumerate((-5, 20, 42, 66, 90, 115, 140)):
        a = math.radians(deg + rng.uniform(-6, 6))
        r = rng.uniform(100.0, 140.0)
        _card("Cloud_Card_%d" % k, "Cloud_Card", (6 + math.cos(a) * r, 6 + math.sin(a) * r, rng.uniform(-60.0, -50.0)), 95.0, 30.0)


def build_world_and_lights():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("Alpine_Sky")
    scene.world = world
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    for node in list(nodes):
        nodes.remove(node)
    out = nodes.new("ShaderNodeOutputWorld")
    bg = nodes.new("ShaderNodeBackground")
    sky = nodes.new("ShaderNodeTexSky")
    for sky_type in ("MULTIPLE_SCATTERING", "NISHITA", "SINGLE_SCATTERING", "HOSEK_WILKIE"):
        try:
            sky.sky_type = sky_type
            break
        except TypeError:
            continue
    for attr, value in (("sun_elevation", math.radians(30)), ("sun_rotation", math.radians(-115)), ("altitude", 2200.0), ("air_density", 1.0), ("dust_density", 0.8), ("sun_intensity", 0.7)):
        if hasattr(sky, attr):
            try:
                setattr(sky, attr, value)
            except Exception:
                pass
    bg.inputs["Strength"].default_value = 0.3
    links.new(sky.outputs["Color"], bg.inputs["Color"])
    # Camera rays see the painted Luma sky (wrapped twice around the horizon,
    # golden glow at the horizon); lighting still comes from the physical sky.
    coord = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Generated"], sep.inputs["Vector"])
    atan = nodes.new("ShaderNodeMath")
    atan.operation = "ARCTAN2"
    links.new(sep.outputs["Y"], atan.inputs[0])
    links.new(sep.outputs["X"], atan.inputs[1])
    u = nodes.new("ShaderNodeMath")
    u.operation = "MULTIPLY_ADD"
    links.new(atan.outputs[0], u.inputs[0])
    u.inputs[1].default_value = 2.0 / math.tau
    u.inputs[2].default_value = 0.5
    v = nodes.new("ShaderNodeMapRange")
    links.new(sep.outputs["Z"], v.inputs["Value"])
    # The board cameras look down: the frame top is ~10 deg below the horizon,
    # so the painted horizon band is mapped down to -27 deg.
    v.inputs["From Min"].default_value = -0.45
    v.inputs["From Max"].default_value = 0.5
    v.inputs["To Min"].default_value = 0.0
    v.inputs["To Max"].default_value = 0.98
    uvw = nodes.new("ShaderNodeCombineXYZ")
    links.new(u.outputs[0], uvw.inputs["X"])
    links.new(v.outputs["Result"], uvw.inputs["Y"])
    painted = nodes.new("ShaderNodeTexImage")
    painted.image = _image(os.path.join(TEX_DIR, "parallax", "sky_clouds.jpg"))
    links.new(uvw.outputs["Vector"], painted.inputs["Vector"])
    bg_cam = nodes.new("ShaderNodeBackground")
    bg_cam.inputs["Strength"].default_value = 0.85
    links.new(painted.outputs["Color"], bg_cam.inputs["Color"])
    path = nodes.new("ShaderNodeLightPath")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(path.outputs["Is Camera Ray"], mix.inputs["Fac"])
    links.new(bg.outputs["Background"], mix.inputs[1])
    links.new(bg_cam.outputs["Background"], mix.inputs[2])
    links.new(mix.outputs["Shader"], out.inputs["Surface"])

    # Low golden sun (warm key) ...
    sun = bpy.data.lights.new("Alpine_Sun", "SUN")
    sun.energy = 4.2
    sun.color = (1.0, 0.84, 0.62)
    sun.angle = math.radians(1.5)
    so = bpy.data.objects.new("Alpine_Sun", sun)
    so.rotation_euler = (math.radians(58), 0, math.radians(-145))
    collection("L05/Lights_Cameras").objects.link(so)
    # ... cold bounce from the snowfields behind the summit ...
    cold = bpy.data.lights.new("Mountain_Cold_Fill", "AREA")
    cold.energy = 1800
    cold.size = 30
    cold.color = (0.6, 0.74, 1.0)
    co = bpy.data.objects.new("Mountain_Cold_Fill", cold)
    co.location = (28, 30, 18)
    co.rotation_euler = (Vector((6, 6, 0)) - Vector(co.location)).to_track_quat("-Z", "Y").to_euler()
    collection("L05/Lights_Cameras").objects.link(co)
    # ... and a soft neutral sky fill on the camera side.
    fill = bpy.data.lights.new("Sky_Fill", "AREA")
    fill.energy = 260
    fill.size = 20
    fill.color = (0.82, 0.88, 1.0)
    fo = bpy.data.objects.new("Sky_Fill", fill)
    fo.location = (-8, -10, 14)
    fo.rotation_euler = (math.radians(50), 0, math.radians(-45))
    collection("L05/Lights_Cameras").objects.link(fo)
    # Warm glow inside the mill so the windows light the deck.
    inner = bpy.data.lights.new("Mill_Interior", "POINT")
    inner.energy = 160
    inner.color = (1.0, 0.6, 0.25)
    io = bpy.data.objects.new("Mill_Interior", inner)
    io.location = (7.8, 11.0, Z2 + 1.4)
    collection("L05/Lights_Cameras").objects.link(io)


def add_camera(name, location, target, lens=40.0, ortho=None):
    cam = bpy.data.cameras.new(name)
    cam.lens = lens
    cam.clip_end = 600
    if ortho:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho
    obj = bpy.data.objects.new(name, cam)
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    collection("L05/Lights_Cameras").objects.link(obj)
    return obj


def build_cameras():
    return {
        "01_isometric_overview": add_camera("Cam_01_Isometric", (-11.0, -11.6, 13.0), (6.4, 6.2, 0.6), 36),
        "02_top_lanes": add_camera("Cam_02_Top", (6.0, 6.0, 40.0), (6.0, 6.0001, 0.0), ortho=25.5),
        "03_side_wheels_lift": add_camera("Cam_03_Side", (19.5, -5.5, 4.5), (10.2, 3.2, 1.3), 34),
        "04_mill_aqueducts_falls": add_camera("Cam_04_Mill", (3.2, 3.6, 6.4), (7.6, 9.6, 3.4), 30),
        "05_hidden_corridor": add_camera("Cam_05_Corridor", (4.9, 4.05, 0.42), (9.6, 3.95, 0.3), 22),
    }


def build_markers():
    col = collection("L05/Game_Markers")
    empty("Marker_BallStart", (0.8, 4.0, Z0 + 0.33), col, "SPHERE", 0.33)
    empty("Marker_Goal", (2.4, 8.6, Z2 - 0.05), col, "CIRCLE", 0.45)
    empty("Marker_CubeStart", (5.0, 1.0, Z0 + 0.23), col, "CUBE", 0.22)
    for i, z in enumerate((Z0, Z1, Z2)):
        empty("Marker_LiftStop_%d" % i, ((LIFT["x0"] + LIFT["x1"]) / 2, (LIFT["y0"] + LIFT["y1"]) / 2, z), col, "ARROWS", 0.4)
    # Marble for scale in the renders (Godot spawns its own RigidBody3D).
    b = Builder("Preview_Marble", col)
    tmp = bmesh.new()
    bmesh.ops.create_uvsphere(tmp, u_segments=32, v_segments=16, radius=0.33)
    mapping = {v: b.bm.verts.new(v.co + Vector((0.8, 4.0, Z0 + 0.33))) for v in tmp.verts}
    index = b._mi("Marble_Steel")
    for f in tmp.faces:
        nf = b.bm.faces.new([mapping[v] for v in f.verts])
        nf.material_index = index
        nf.smooth = True
    tmp.free()
    b.finish()


# ----------------------------------------------------------------------------
# Render
# ----------------------------------------------------------------------------

def configure_render(samples):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for device_type in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = device_type
            prefs.get_devices()
            usable = [d for d in prefs.devices if d.type == device_type]
            if usable:
                for d in prefs.devices:
                    d.use = d.type == device_type
                scene.cycles.device = "GPU"
                print("L05 render device:", device_type, [d.name for d in usable])
                break
        except Exception as error:
            print("device", device_type, "unavailable:", error)
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 8
    scene.cycles.transmission_bounces = 8
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.film_transparent = False
    # PBR Neutral keeps the saturated timber and water of the reference.
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Punchy"
    except TypeError:
        pass
    scene.view_settings.exposure = -0.85


def render_all(cameras, only=None, out_dir=RENDER_DIR):
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    for key, cam in cameras.items():
        if only and key not in only:
            continue
        scene.camera = cam
        scene.render.filepath = os.path.join(out_dir, "L05_%s.png" % key)
        bpy.ops.render.render(write_still=True)
        print("L05 rendered", scene.render.filepath)


def export_water_params():
    """Godot hand-off (not wired yet): the same layer tiles/speeds the Blender
    drivers use, flow direction per water body and the texture set, so a
    Godot water shader reproduces the Blender look without a fluid sim."""
    flows = {}
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name.startswith(("Water_", "Waterfall_")):
            mat = obj.data.materials[0].name if obj.data.materials else ""
            flows[obj.name] = {"material": mat}
    for obj in bpy.data.objects:
        if obj.name.startswith("Water_") and obj.name in flows and obj.data.uv_layers:
            uv = obj.data.uv_layers[0].data
            loops = obj.data.loops
            verts = obj.data.vertices
            # Downstream = direction in which U grows (UVs are metres).
            if len(uv) >= 2:
                d = verts[loops[1].vertex_index].co - verts[loops[0].vertex_index].co
                du = uv[1].uv[0] - uv[0].uv[0]
                if abs(du) > 1e-6:
                    v = d * (1.0 / du)
                    flows[obj.name]["downstream_xy"] = [round(v.x, 3), round(v.y, 3)]
    data = {
        "note": "Blender 5 v3 water look for Godot 4 (StandardMaterial3D / ShaderMaterial). UV units are metres; "
                "scroll = speed / tile texture units per second along +U (surfaces) or +V offset (falls, V = -metres fallen).",
        "colour_linear": list(WATER_COLOR),
        "ior": 1.333,
        "layers": WATER_LAYERS,
        "textures": {
            "surface_colour_foam": "res://assets/luma/level04/water_foam.jpg",
            "fall_body_rgba": "res://assets/luma/level05/waterfall_streaks.png",
            "fall_foam_mask": "res://assets/luma/level05/waterfall_foam_mask.png",
            "fall_normal": "res://assets/luma/level05/waterfall_normal.png",
        },
        "parallax_layers_far_to_near": [
            "res://assets/luma/level05/parallax/sky_clouds.jpg",
            "res://assets/luma/level04/alps_far.jpg",
            "res://assets/luma/level05/parallax/cloud_bank.png",
            "res://assets/luma/level05/parallax/mid_forest_slopes.png",
            "res://assets/luma/level05/parallax/near_rocks_plants.png",
        ],
        "bodies": flows,
    }
    path = os.path.join(TEX_DIR, "level05_water_params.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    print("L05 water params", path)


def validate_layout():
    """Every railing opening must meet another floor at the same height, and
    every opening/bridge must be at least 1.0 m wide for the 0.66 m marble."""
    floors = [(n, x0, x1, y0, y1, z) for n, x0, x1, y0, y1, z, *_ in DECKS]
    floors += [(n, x0, x1, y0, y1, z) for n, x0, x1, y0, y1, z, _a in BRIDGES]
    for i, z in enumerate((Z0, Z1, Z2)):
        floors.append(("Lift_Stop_%d" % i, LIFT["x0"], LIFT["x1"], LIFT["y0"], LIFT["y1"], z))
    problems = []
    for name, x0, x1, y0, y1, z, _m, openings, _zone in DECKS:
        for side, spans in openings.items():
            for a, b in spans:
                if b - a < 1.0 - 1e-6:
                    problems.append("%s %s opening %.2f m < 1.0 m" % (name, side, b - a))
                mid = (a + b) / 2
                probe = {"S": (mid, y0 - 0.05), "N": (mid, y1 + 0.05), "W": (x0 - 0.05, mid), "E": (x1 + 0.05, mid)}[side]
                hit = [f[0] for f in floors if f[0] != name and abs(f[5] - z) < 0.01 and f[1] - 0.01 <= probe[0] <= f[2] + 0.01 and f[3] - 0.01 <= probe[1] <= f[4] + 0.01]
                if not hit:
                    problems.append("%s %s opening at %.2f leads nowhere" % (name, side, mid))
    for name, x0, x1, y0, y1, _z, along in BRIDGES:
        # Width is measured across the direction of travel.
        width = (y1 - y0) if along == "X" else (x1 - x0)
        if width < 1.0 - 1e-6:
            problems.append("%s lane %.2f m < 1.0 m" % (name, width))
    print("L05 layout check:", "OK" if not problems else problems)
    return problems


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    samples = int(argv[argv.index("--samples") + 1]) if "--samples" in argv else 160
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
    out_dir = argv[argv.index("--out") + 1] if "--out" in argv else RENDER_DIR
    reset_scene()
    build_materials()
    for spec in DECKS:
        holes = (WHEEL_PIT,) if spec[0] == "M_Workshop" else ()
        build_deck(*spec, holes=holes, inlays=INLAYS.get(spec[0], ()), cutouts=CUTOUTS.get(spec[0], ()))
    for spec in BRIDGES:
        build_bridge(*spec)
    build_foundations()
    build_water()
    build_mechanisms()
    build_lift()
    build_millhouse()
    build_lanterns()
    build_ground()
    build_cliffs()
    scatter_firs()
    scatter_grass()
    build_mountains()
    build_world_and_lights()
    build_markers()
    cameras = build_cameras()
    validate_layout()
    configure_render(samples)
    if "--save" in argv:
        os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, compress=True)
        # Textures are referenced relative to the .blend (//../luma/level05/...).
        bpy.ops.file.make_paths_relative()
        bpy.ops.wm.save_mainfile(compress=True)
        print("L05 saved", BLEND_PATH)
        export_water_params()
    if "--render" in argv:
        render_all(cameras, only, out_dir)
    stats = {"objects": len(bpy.data.objects), "meshes": len(bpy.data.meshes),
             "triangles": sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == "MESH" and not o.hide_render)}
    print("L05 stats", stats)


if __name__ == "__main__":
    main()
