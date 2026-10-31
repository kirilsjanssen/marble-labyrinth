"""Level 05 — Alpine Watermill. Procedural Blender 5.x scene built from the
owner's reference art (assets/blender/reference_level05.png).

Run headless:
    blender -b --factory-startup -P tools/blender/build_level05.py -- --save --render [--samples 192]

1 Blender unit = 1 metre = 1 Godot unit. Z is up (glTF export converts to Y-up).
Play floors: LOWER z=0.0, MIDDLE z=1.4, UPPER z=2.8 (deck tops). Every lane is
at least 1.0 m wide for a 0.33 m marble. Mechanisms are separate objects with
their pivot at the rotation axis so Godot can drive them.
"""
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


def mat_wood(name, light, dark, rough=0.62, grain_scale=(1.0, 1.0, 9.0)):
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    mapping = _coords(mat, grain_scale)
    wave = nodes.new("ShaderNodeTexWave")
    wave.location = (-500, 100)
    wave.wave_type = "RINGS"
    wave.inputs["Scale"].default_value = 3.2
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 3.0
    links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
    grain = nodes.new("ShaderNodeTexNoise")
    grain.location = (-500, -150)
    grain.inputs["Scale"].default_value = 28.0
    grain.inputs["Detail"].default_value = 6.0
    links.new(mapping.outputs["Vector"], grain.inputs["Vector"])
    mix = nodes.new("ShaderNodeMath")
    mix.operation = "MULTIPLY_ADD"
    mix.location = (-320, 0)
    links.new(wave.outputs["Fac"], mix.inputs[0])
    mix.inputs[1].default_value = 0.7
    links.new(grain.outputs["Fac"], mix.inputs[2])
    ramp = _ramp(mat, [(0.25, dark), (0.65, light), (1.0, tuple(min(1.0, c * 1.15) for c in light))])
    links.new(mix.outputs[0], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    _set(bsdf, "Roughness", rough)
    _bump(mat, mix.outputs[0], 0.25, bsdf, 0.01)
    MATS[name] = mat
    return mat


def mat_stone(name, light, dark, rough=0.78, scale=3.0, wet=0.0):
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    mapping = _coords(mat, (scale, scale, scale))
    noise_tex = nodes.new("ShaderNodeTexNoise")
    noise_tex.location = (-500, 100)
    noise_tex.inputs["Scale"].default_value = 2.5
    noise_tex.inputs["Detail"].default_value = 10.0
    noise_tex.inputs["Roughness"].default_value = 0.62
    links.new(mapping.outputs["Vector"], noise_tex.inputs["Vector"])
    voronoi = nodes.new("ShaderNodeTexVoronoi")
    voronoi.location = (-500, -180)
    voronoi.inputs["Scale"].default_value = 6.0
    links.new(mapping.outputs["Vector"], voronoi.inputs["Vector"])
    # Per-block tint from object-space position keeps blocks individual.
    ramp = _ramp(mat, [(0.3, dark), (0.55, tuple((a + b) * 0.5 for a, b in zip(light, dark))), (0.8, light)])
    links.new(noise_tex.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    _set(bsdf, "Roughness", rough - wet * 0.45)
    height = nodes.new("ShaderNodeMath")
    height.operation = "ADD"
    height.location = (-150, -250)
    links.new(noise_tex.outputs["Fac"], height.inputs[0])
    links.new(voronoi.outputs["Distance"], height.inputs[1])
    _bump(mat, height.outputs[0], 0.35, bsdf, 0.03)
    MATS[name] = mat
    return mat


def mat_rock(name):
    """Granite cliffs with moss and grass on upward faces (normal.z)."""
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    mapping = _coords(mat, (0.9, 0.9, 1.6), coord="Object")
    strata = nodes.new("ShaderNodeTexNoise")
    strata.location = (-500, 150)
    strata.inputs["Scale"].default_value = 2.2
    strata.inputs["Detail"].default_value = 12.0
    strata.inputs["Roughness"].default_value = 0.66
    links.new(mapping.outputs["Vector"], strata.inputs["Vector"])
    rock_ramp = _ramp(mat, [(0.32, (0.035, 0.033, 0.03)), (0.5, (0.10, 0.095, 0.085)), (0.72, (0.22, 0.21, 0.19))], (-250, 200))
    links.new(strata.outputs["Fac"], rock_ramp.inputs["Fac"])
    geo = nodes.new("ShaderNodeNewGeometry")
    geo.location = (-700, -300)
    sep = nodes.new("ShaderNodeSeparateXYZ")
    sep.location = (-520, -300)
    links.new(geo.outputs["Normal"], sep.inputs["Vector"])
    moss_noise = nodes.new("ShaderNodeTexNoise")
    moss_noise.location = (-520, -480)
    moss_noise.inputs["Scale"].default_value = 4.0
    links.new(mapping.outputs["Vector"], moss_noise.inputs["Vector"])
    add = nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    add.location = (-340, -380)
    links.new(sep.outputs["Z"], add.inputs[0])
    sub = nodes.new("ShaderNodeMath")
    sub.operation = "SUBTRACT"
    sub.location = (-420, -480)
    links.new(moss_noise.outputs["Fac"], sub.inputs[0])
    sub.inputs[1].default_value = 0.5
    links.new(sub.outputs[0], add.inputs[1])
    moss_mask = _ramp(mat, [(0.55, (0, 0, 0)), (0.72, (1, 1, 1))], (-200, -380))
    links.new(add.outputs[0], moss_mask.inputs["Fac"])
    moss_color = _ramp(mat, [(0.3, (0.018, 0.04, 0.01)), (0.7, (0.05, 0.10, 0.02))], (-200, -600))
    links.new(moss_noise.outputs["Fac"], moss_color.inputs["Fac"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.location = (80, 0)
    links.new(moss_mask.outputs["Color"], mix.inputs["Factor"])
    links.new(rock_ramp.outputs["Color"], mix.inputs["A"])
    links.new(moss_color.outputs["Color"], mix.inputs["B"])
    links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    _set(bsdf, "Roughness", 0.85)
    _bump(mat, strata.outputs["Fac"], 0.6, bsdf, 0.08)
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


def mat_water(name, color=(0.01, 0.2, 0.55), foam=False):
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    mapping = _coords(mat, (1.0, 4.0, 1.0) if not foam else (2.0, 2.0, 0.4))
    ripples = nodes.new("ShaderNodeTexNoise")
    ripples.location = (-500, -200)
    ripples.inputs["Scale"].default_value = 3.5 if not foam else 6.0
    ripples.inputs["Detail"].default_value = 6.0
    links.new(mapping.outputs["Vector"], ripples.inputs["Vector"])
    if foam:
        ramp = _ramp(mat, [(0.38, (0.55, 0.78, 0.95)), (0.62, (0.96, 0.98, 1.0))])
        links.new(ripples.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
        _set(bsdf, "Roughness", 0.25)
        _set(bsdf, "Transmission Weight", 0.35)
        _set(bsdf, "Emission Color", (0.7, 0.85, 1.0, 1.0))
        _set(bsdf, "Emission Strength", 0.15)
    else:
        _set(bsdf, "Base Color", (*color, 1.0))
        _set(bsdf, "Roughness", 0.05)
        _set(bsdf, "Transmission Weight", 0.55)
        _set(bsdf, "IOR", 1.333)
        # A blue glow keeps shallow channels saturated and readable from above.
        _set(bsdf, "Emission Color", (0.02, 0.28, 0.75, 1.0))
        _set(bsdf, "Emission Strength", 0.9)
    _bump(mat, ripples.outputs["Fac"], 0.22, bsdf, 0.02)
    MATS[name] = mat
    return mat


def mat_needles(name, color):
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    info = nodes.new("ShaderNodeObjectInfo")
    info.location = (-600, 0)
    ramp = _ramp(mat, [(0.0, tuple(c * 0.7 for c in color)), (1.0, tuple(min(1, c * 1.3) for c in color))])
    links.new(info.outputs["Random"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    _set(bsdf, "Roughness", 0.8)
    _set(bsdf, "Subsurface Weight", 0.08)
    MATS[name] = mat
    return mat


def mat_snow_mountain(name):
    mat, bsdf = _new_material(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    geo = nodes.new("ShaderNodeNewGeometry")
    geo.location = (-800, 0)
    sep_n = nodes.new("ShaderNodeSeparateXYZ")
    sep_n.location = (-600, 0)
    links.new(geo.outputs["Normal"], sep_n.inputs["Vector"])
    sep_p = nodes.new("ShaderNodeSeparateXYZ")
    sep_p.location = (-600, -200)
    links.new(geo.outputs["Position"], sep_p.inputs["Vector"])
    height = nodes.new("ShaderNodeMapRange")
    height.location = (-420, -200)
    height.inputs["From Min"].default_value = -60.0
    height.inputs["From Max"].default_value = 5.0
    links.new(sep_p.outputs["Z"], height.inputs["Value"])
    combine = nodes.new("ShaderNodeMath")
    combine.operation = "MULTIPLY_ADD"
    combine.location = (-250, -100)
    links.new(sep_n.outputs["Z"], combine.inputs[0])
    combine.inputs[1].default_value = 0.8
    links.new(height.outputs["Result"], combine.inputs[2])
    ramp = _ramp(mat, [(0.85, (0.035, 0.04, 0.05)), (1.05 / 1.8, (0.12, 0.13, 0.16)), (1.0, (0.92, 0.95, 1.0))])
    ramp.color_ramp.elements[0].position = 0.62
    ramp.color_ramp.elements[1].position = 0.78
    ramp.color_ramp.elements[2].position = 0.86
    links.new(combine.outputs[0], ramp.inputs["Fac"])
    # Aerial perspective: distant peaks take on the sky's blue.
    haze = nodes.new("ShaderNodeMix")
    haze.data_type = "RGBA"
    haze.inputs["Factor"].default_value = 0.32
    haze.inputs["B"].default_value = (0.32, 0.45, 0.68, 1.0)
    links.new(ramp.outputs["Color"], haze.inputs["A"])
    links.new(haze.outputs["Result"], bsdf.inputs["Base Color"])
    _set(bsdf, "Roughness", 0.7)
    MATS[name] = mat
    return mat


def build_materials():
    mat_wood("Wood_Frame", (0.42, 0.15, 0.035), (0.16, 0.05, 0.012), 0.5)
    mat_wood("Wood_Plank", (0.26, 0.11, 0.035), (0.08, 0.035, 0.012), 0.62)
    mat_wood("Wood_Dark", (0.10, 0.045, 0.018), (0.03, 0.015, 0.006), 0.7)
    mat_wood("Wood_Weathered", (0.20, 0.12, 0.06), (0.07, 0.04, 0.02), 0.75)
    mat_stone("Slate_Floor", (0.035, 0.037, 0.045), (0.012, 0.013, 0.016), 0.55, 2.0)
    mat_stone("Stone_Masonry", (0.20, 0.19, 0.17), (0.06, 0.058, 0.055), 0.8, 2.5)
    mat_stone("Stone_Wet", (0.11, 0.11, 0.105), (0.03, 0.03, 0.03), 0.8, 2.5, wet=0.8)
    mat_rock("Rock_Moss")
    mat_metal("Brass", (0.95, 0.6, 0.16), 0.34)
    mat_metal("Iron", (0.20, 0.20, 0.21), 0.45)
    mat_simple("Red_Paint", (0.55, 0.05, 0.03), 0.35)
    mat_simple("Roof_Slate", (0.035, 0.033, 0.035), 0.55)
    mat_wood("Roof_Shingle", (0.08, 0.055, 0.04), (0.025, 0.018, 0.014), 0.8, (1.0, 6.0, 1.0))
    mat_simple("Window_Glow", (1.0, 0.62, 0.25), 0.3, emission=(1.0, 0.55, 0.18), strength=6.0)
    mat_simple("Lantern_Glow", (1.0, 0.7, 0.3), 0.2, emission=(1.0, 0.6, 0.2), strength=18.0)
    mat_simple("Goal_Gold", (1.0, 0.72, 0.22), 0.2, metal=1.0, emission=(1.0, 0.66, 0.2), strength=0.6)
    mat_simple("Plate_White", (0.85, 0.82, 0.78), 0.4)
    mat_simple("Banner_Red", (0.45, 0.03, 0.03), 0.7)
    mat_simple("Grass", (0.05, 0.14, 0.02), 0.85)
    mat_simple("Bark", (0.16, 0.10, 0.06), 0.9)
    mat_needles("Fir_Needles", (0.015, 0.06, 0.02))
    mat_needles("Fir_Needles_Far", (0.03, 0.07, 0.05))
    mat_water("Water")
    mat_water("Water_Foam", foam=True)
    mat_snow_mountain("Mountain_Snow")
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
        self._finish_faces([f for f in faces if f.is_valid], mat, smooth)

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

    def polygon_prism(self, outline, z0, z1, mat, transform=Matrix.Identity(4), smooth=False):
        """Extrudes a 2D outline (counter-clockwise, XY) from z0 to z1."""
        bottom = [self.bm.verts.new(transform @ Vector((x, y, z0))) for x, y in outline]
        top = [self.bm.verts.new(transform @ Vector((x, y, z1))) for x, y in outline]
        faces = [self.bm.faces.new(list(reversed(bottom))), self.bm.faces.new(top)]
        n = len(outline)
        for i in range(n):
            faces.append(self.bm.faces.new((bottom[i], bottom[(i + 1) % n], top[(i + 1) % n], top[i])))
        self._finish_faces(faces, mat, smooth)

    def raw(self, verts, faces, mat, smooth=True):
        bverts = [self.bm.verts.new(v) for v in verts]
        made = [self.bm.faces.new([bverts[i] for i in f]) for f in faces]
        self._finish_faces(made, mat, smooth)

    def finish(self, origin=(0.0, 0.0, 0.0)):
        origin = Vector(origin)
        if origin.length > 0.0:
            bmesh.ops.translate(self.bm, verts=self.bm.verts, vec=-origin)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
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
    ("L_Start", 0.0, 6.0, 3.0, 5.0, Z0, "Slate_Floor", {"S": [(4.0, 5.2)], "E": [(3.3, 4.7)]}, "Lower"),
    ("L_Front", 3.5, 6.0, 0.0, 2.0, Z0, "Slate_Floor", {"N": [(4.0, 5.2)], "E": [(0.4, 1.6)]}, "Lower"),
    ("L_FrontEast", 6.8, 9.0, 0.0, 2.0, Z0, "Slate_Floor", {"W": [(0.4, 1.6)], "E": [(0.25, 1.75)]}, "Lower"),
    ("L_HiddenCorridor", 6.0, 9.0, 3.3, 4.7, Z0, "Slate_Floor", {"W": [(3.3, 4.7)], "E": [(3.3, 4.7)]}, "Lower"),
    ("L_SecretAlcove", 9.0, 10.4, 2.9, 5.0, Z0, "Slate_Floor", {"W": [(3.3, 4.7)]}, "Lower"),
    ("M_Workshop", 5.5, 11.2, 2.4, 6.8, Z1, "Slate_Floor", {"S": [(9.2, 10.4)], "W": [(5.4, 6.6)]}, "Middle"),
    ("M_GearTerrace", 3.2, 5.5, 5.2, 7.4, Z1, "Slate_Floor", {"E": [(5.4, 6.6)]}, "Middle"),
    ("U_LiftWalk", 9.4, 10.8, 1.8, 5.6, Z2, "Slate_Floor", {"S": [(9.5, 10.5)], "N": [(9.5, 10.7)]}, "Upper"),
    # The pool/valve link runs north of the front channel and under the pond aqueduct.
    ("U_PoolDeck", 9.4, 12.0, 5.6, 9.1, Z2, "Slate_Floor", {"S": [(9.5, 10.7)], "W": [(8.0, 9.0)]}, "Upper"),
    ("U_ValveDeck", 4.5, 9.4, 7.4, 9.8, Z2, "Slate_Floor", {"E": [(8.0, 9.0)], "W": [(7.6, 9.4)]}, "Upper"),
    ("U_GoalDeck", 1.0, 4.5, 7.0, 10.0, Z2, "Slate_Floor", {"E": [(7.6, 9.4)]}, "Upper"),
]

BRIDGES = [
    ("Bridge_StreamWest", 4.0, 5.2, 2.0, 3.0, Z0, "Y"),
    ("Bridge_Spillway", 6.0, 6.8, 0.4, 1.6, Z0, "X"),
    ("Bridge_LiftMiddle", 9.2, 10.4, 1.8, 2.4, Z1, "Y"),
]

WHEEL_PIT = (8.35, 10.3, 5.95, 6.8)   # opening in M_Workshop for the main wheel


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


def build_deck(name, x0, x1, y0, y1, z, floor_mat, openings, zone, holes=()):
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
            a = (x0 if along_x else y0) + cursor + l * 0.5
            center = (a, c, z - 0.025) if along_x else (c, a, z - 0.025)
            size = (l - 0.012, width - 0.014, 0.05) if along_x else (width - 0.014, l - 0.012, 0.05)
            if not any(_inside(center, hole) for hole in holes):
                b.box(center, size, floor_mat, bevel=0.008)
            cursor += l
            seg = 1.4 + RNG.random() * 1.2
    # Joists and subfloor under the boards.
    b.box(((x0 + x1) / 2, (y0 + y1) / 2, z - DECK_T * 0.5 - 0.025), (x1 - x0 - 0.1, y1 - y0 - 0.1, DECK_T - 0.05), "Wood_Dark", bevel=0.0)
    for hole in holes:
        _pit_frame(b, hole, z)
    _deck_frame(b, x0, x1, y0, y1, z, openings)
    return b.finish()


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
    for k in range(posts + 1):
        a = s0 + length * k / posts
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
    if along == "Y":
        n = round((y1 - y0) / 0.2)
        for i in range(n):
            yc = y0 + (i + 0.5) * (y1 - y0) / n
            b.box(((x0 + x1) / 2, yc, z - 0.03 - RNG.random() * 0.01), (x1 - x0 + 0.1, (y1 - y0) / n - 0.02, 0.06), "Wood_Plank", rot=(0, RNG.uniform(-0.02, 0.02), 0), bevel=0.01)
        for x in (x0 + 0.06, x1 - 0.06):
            b.box((x, (y0 + y1) / 2, z - 0.15), (0.14, y1 - y0 + 0.2, 0.2), "Wood_Frame", bevel=0.02)
            b.box((x, (y0 + y1) / 2, z + 0.15), (0.12, y1 - y0, 0.3), "Wood_Frame", bevel=0.02)
            b.box((x, (y0 + y1) / 2, z + RAIL_H - 0.04), (0.1, y1 - y0, 0.08), "Wood_Frame", bevel=0.02)
            for y in (y0, y1):
                b.box((x, y, z + RAIL_H / 2), (0.15, 0.15, RAIL_H + 0.1), "Wood_Frame", bevel=0.02)
                b.box((x, y, z + RAIL_H + 0.08), (0.19, 0.19, 0.08), "Brass", bevel=0.015)
    else:
        n = round((x1 - x0) / 0.2)
        for i in range(n):
            xc = x0 + (i + 0.5) * (x1 - x0) / n
            b.box((xc, (y0 + y1) / 2, z - 0.03 - RNG.random() * 0.01), ((x1 - x0) / n - 0.02, y1 - y0 + 0.1, 0.06), "Wood_Plank", rot=(RNG.uniform(-0.02, 0.02), 0, 0), bevel=0.01)
        for y in (y0 + 0.06, y1 - 0.06):
            b.box(((x0 + x1) / 2, y, z - 0.15), (x1 - x0 + 0.2, 0.14, 0.2), "Wood_Frame", bevel=0.02)
            b.box(((x0 + x1) / 2, y, z + 0.15), (x1 - x0, 0.12, 0.3), "Wood_Frame", bevel=0.02)
            b.box(((x0 + x1) / 2, y, z + RAIL_H - 0.04), (x1 - x0, 0.1, 0.08), "Wood_Frame", bevel=0.02)
            for x in (x0, x1):
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
    faces = list({f for v in bev["verts"] for f in v.link_faces} | set(bev["faces"]) | set(f for f in faces if f.is_valid))
    b._finish_faces([f for f in faces if f.is_valid], mat, False)


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
    masonry_wall(middle, (6.0, 3.22), (9.0, 3.22), Z0, zt, 0.16)
    masonry_wall(middle, (6.0, 4.78), (9.0, 4.78), Z0, zt, 0.16)
    # The corridor arch (y 3.3-4.7) is the entrance of the hidden lower path.
    masonry_wall(middle, (5.55, 2.45), (5.55, 6.75), rock_top, zt, 0.36, arches=[(1.55, 1.42, 0.42)])
    masonry_wall(middle, (11.15, 2.45), (11.15, 6.75), rock_top, zt, 0.36, arches=[(2.0, 1.4, 0.0)])
    masonry_wall(middle, (5.55, 6.75), (8.35, 6.75), rock_top, zt, 0.36)
    masonry_wall(middle, (10.3, 6.75), (11.15, 6.75), rock_top, zt, 0.36)
    masonry_wall(middle, (3.25, 5.25), (3.25, 7.35), rock_top, zt, 0.32)
    masonry_wall(middle, (3.25, 7.35), (5.5, 7.35), rock_top, zt, 0.32)
    masonry_wall(middle, (3.25, 5.25), (5.5, 5.25), rock_top, zt, 0.32, arches=[(1.1, 0.9, Z0 - 0.4)])
    # Wheel pit lining.
    masonry_wall(middle, (8.35, 5.95), (8.35, 6.75), -0.6, zt, 0.24, mat="Stone_Wet")
    masonry_wall(middle, (10.3, 5.95), (10.3, 6.75), -0.6, zt, 0.24, mat="Stone_Wet")
    masonry_wall(middle, (8.35, 5.95), (10.3, 5.95), -0.6, zt, 0.24, mat="Stone_Wet")
    middle.finish()

    # Upper tier: tall walls with arches and buttresses.
    upper = Builder("Masonry_UpperTerraces", col)
    zt = Z2 - DECK_T - 0.02
    masonry_wall(upper, (4.55, 7.45), (8.35, 7.45), Z1 - 0.3, zt, 0.42, arches=[(0.75, 0.9, Z1 + 0.25), (2.95, 0.9, Z1 + 0.25)])
    masonry_wall(upper, (1.05, 7.05), (3.2, 7.05), rock_top, zt, 0.42, arches=[(1.1, 1.0, Z1 - 0.1)])
    masonry_wall(upper, (1.05, 7.05), (1.05, 9.95), rock_top, zt, 0.42, arches=[(1.5, 1.2, Z1)])
    masonry_wall(upper, (1.05, 9.95), (9.4, 9.95), rock_top, zt, 0.42)
    masonry_wall(upper, (11.95, 5.65), (11.95, 9.05), rock_top, zt, 0.42, arches=[(1.25, 1.1, Z1 + 0.2)])
    masonry_wall(upper, (9.45, 9.05), (11.95, 9.05), rock_top, zt, 0.42)
    for x, y in ((9.45, 5.65), (11.95, 5.65), (10.75, 1.85), (9.45, 1.85), (10.75, 3.7)):
        stone_pier(upper, x, y, Z1, zt - 0.12, 0.42)
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

def water_surface(name, x0, x1, y0, y1, z):
    b = Builder(name, collection("L05/Water"))
    # Slightly subdivided so the glTF importer and shaders get UVs per metre.
    nx, ny = max(2, int((x1 - x0) * 3)), max(2, int((y1 - y0) * 3))
    verts = []
    faces = []
    for j in range(ny + 1):
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx
            y = y0 + (y1 - y0) * j / ny
            verts.append((x, y, z + noise.noise(Vector((x * 2.0, y * 2.0, 3.0))) * 0.008))
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    b.raw(verts, faces, "Water")
    return b.finish()


def flume(b, x0, x1, y0, y1, z_bed, depth=0.28, mat="Wood_Plank", posts_to=None):
    """Open timber channel; the long axis is the larger extent."""
    along_x = (x1 - x0) >= (y1 - y0)
    b.box(((x0 + x1) / 2, (y0 + y1) / 2, z_bed - 0.04), (x1 - x0, y1 - y0, 0.08), mat, bevel=0.01)
    if along_x:
        for y in (y0 + 0.04, y1 - 0.04):
            b.box(((x0 + x1) / 2, y, z_bed + depth / 2), (x1 - x0, 0.08, depth), mat, bevel=0.01)
        span = x1 - x0
        for k in range(int(span / 0.9) + 1):
            x = x0 + 0.05 + k * min(0.9, span - 0.1)
            b.box((x, (y0 + y1) / 2, z_bed + depth * 0.5), (0.08, y1 - y0 + 0.14, depth + 0.1), "Wood_Frame", bevel=0.015)
            b.box((x, y0 - 0.03, z_bed + depth + 0.03), (0.1, 0.1, 0.06), "Brass", bevel=0.01)
            b.box((x, y1 + 0.03, z_bed + depth + 0.03), (0.1, 0.1, 0.06), "Brass", bevel=0.01)
            if posts_to is not None:
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
            if posts_to is not None:
                b.box(((x0 + x1) / 2, y, (posts_to + z_bed) / 2), (0.12, 0.12, z_bed - posts_to), "Wood_Frame", bevel=0.02)


def waterfall(name, a0, a1, edge, z_top, z_bottom, outward, axis="X", thickness=0.05):
    """Curved falling sheet leaving an edge; `axis` is the lip direction."""
    b = Builder(name, collection("L05/Water/Waterfalls"))
    cols, rows = max(3, int((a1 - a0) * 6)), max(6, int((z_top - z_bottom) * 5))
    verts, faces = [], []
    for j in range(rows + 1):
        t = j / rows
        z = z_top - (z_top - z_bottom) * t
        out = outward * (0.12 + 0.55 * math.sqrt(t)) * min(1.0, (z_top - z_bottom) / 1.5)
        for i in range(cols + 1):
            a = a0 + (a1 - a0) * i / cols
            wob = noise.noise(Vector((a * 3.0, z * 2.0, 7.0))) * 0.04
            if axis == "X":
                verts.append((a, edge + out + wob, z))
            else:
                verts.append((edge + out + wob, a, z))
    for j in range(rows):
        for i in range(cols):
            p = j * (cols + 1) + i
            faces.append((p, p + 1, p + cols + 2, p + cols + 1))
    b.raw(verts, faces, "Water_Foam")
    # Splash: foam blobs and churned water where the sheet lands.
    for k in range(int((a1 - a0) * 9) + 4):
        a = RNG.uniform(a0, a1)
        r = RNG.uniform(0.06, 0.16)
        out = outward * (0.67 + RNG.uniform(-0.15, 0.25)) * min(1.0, (z_top - z_bottom) / 1.5)
        c = (a, edge + out, z_bottom + r * 0.4) if axis == "X" else (edge + out, a, z_bottom + r * 0.4)
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=1, radius=r)
        mapping = {v: b.bm.verts.new(v.co + Vector(c)) for v in tmp.verts}
        index = b._mi("Water_Foam")
        for f in tmp.faces:
            nf = b.bm.faces.new([mapping[v] for v in f.verts])
            nf.material_index = index
            nf.smooth = True
        tmp.free()
    return b.finish()


def build_water():
    col = collection("L05/Static_Architecture/Channels")
    ch = Builder("Flumes_And_Channels", col)
    # Upper valve-deck channel along its front edge, fed from the mill pond.
    flume(ch, 4.6, 9.3, 7.45, 7.95, Z2 - 0.18, depth=0.3, mat="Wood_Plank")
    # Pond aqueduct on trestles: the marble rolls underneath (0.9 m clearance).
    flume(ch, 8.85, 9.35, 7.95, 9.85, Z2 + 0.9, depth=0.26, mat="Wood_Plank")
    for x in (8.8, 9.4):
        for y in (7.97, 9.75):
            ch.box((x, y, Z2 + 0.45), (0.12, 0.12, 0.9), "Wood_Frame", bevel=0.02)
            ch.box((x, y, Z2 + 0.02), (0.18, 0.18, 0.05), "Iron", bevel=0.01)
    # Middle workshop channel feeding the main wheel.
    flume(ch, 4.0, 8.4, 6.15, 6.7, Z1 - 0.2, depth=0.3, mat="Wood_Plank")
    # Elevated flume from the upper pool down to the east wheel (aqueduct on posts).
    flume(ch, 11.78, 12.24, 2.75, 6.0, Z2 - 0.32, depth=0.28, mat="Wood_Plank", posts_to=Z0 - 0.6)
    ch.finish()

    water_surface("Water_UpperChannel", 4.66, 9.24, 7.51, 7.89, Z2 + 0.05)
    water_surface("Water_PondFeed", 8.91, 9.29, 7.95, 9.85, Z2 + 1.1)
    water_surface("Water_MiddleChannel", 4.06, 8.34, 6.21, 6.64, Z1 + 0.03)
    water_surface("Water_EastFlume", 11.84, 12.18, 2.75, 6.0, Z2 - 0.1)
    water_surface("Water_Stream", 0.0, 6.0, 2.06, 2.94, -0.18)
    water_surface("Water_Spillway", 6.06, 6.74, 0.0, 2.94, -0.2)
    water_surface("Water_UpperPool", 10.55, 11.85, 6.0, 7.8, Z2 + 0.18)
    water_surface("Water_MillPond", 6.6, 9.0, 12.15, 13.4, Z2 + 0.05)
    water_surface("Water_WheelPit", 8.45, 10.2, 6.0, 6.7, -0.45)

    # Waterfalls: upper channel spills twice into the middle channel; the
    # spillway drops off the front cliff; the east wheel tail falls far below.
    waterfall("Waterfall_PondDrop", 8.92, 9.28, 7.98, Z2 + 1.1, Z2 + 0.08, -0.25)
    waterfall("Waterfall_UpperWest", 5.1, 5.7, 7.45, Z2 + 0.05, Z1 + 0.05, -1.0)
    waterfall("Waterfall_UpperEast", 7.2, 7.7, 7.45, Z2 + 0.05, Z1 + 0.05, -1.0)
    waterfall("Waterfall_Spillway", 6.06, 6.74, 0.0, -0.2, -5.5, -1.0)
    waterfall("Waterfall_EastFeed", 11.84, 12.18, 2.75, Z2 - 0.1, Z1 + 0.6, -0.6)
    waterfall("Waterfall_EastWheel", 2.0, 3.2, 12.5, Z1 + 0.4, -7.0, 1.0, axis="Y")
    waterfall("Waterfall_PoolOverflow", 6.4, 7.6, 12.0, Z2 + 0.15, Z1 - 1.0, 1.0, axis="Y")
    waterfall("Waterfall_Spring", 2.1, 2.9, -0.15, 0.9, -0.18, 1.0, axis="Y")
    waterfall("Waterfall_WheelFeed", 6.2, 6.6, 8.4, Z1 + 0.05, Z0 + 0.3, 1.0, axis="Y")

    # Upper pool basin and mill pond walls.
    pool = Builder("Basins", col)
    for p0, p1 in (((10.5, 5.95), (11.9, 5.95)), ((11.9, 5.95), (11.9, 7.85)), ((11.9, 7.85), (10.5, 7.85)), ((10.5, 7.85), (10.5, 5.95))):
        masonry_wall(pool, p0, p1, Z2 - 0.1, Z2 + 0.32, 0.18, backing=False)
    pool.box((11.2, 6.9, Z2 - 0.02), (1.4, 1.9, 0.06), "Stone_Wet", bevel=0.0)
    for p0, p1 in (((6.5, 12.1), (9.1, 12.1)), ((9.1, 12.1), (9.1, 13.5)), ((9.1, 13.5), (6.5, 13.5)), ((6.5, 13.5), (6.5, 12.1))):
        masonry_wall(pool, p0, p1, Z2 - 0.6, Z2 + 0.22, 0.25, backing=False)
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
    obj["l05_axis"] = axis
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


def build_mechanisms():
    static = Builder("Mechanism_Supports", collection("L05/Static_Architecture/Timber"))
    # Main wheel (breastshot) in its pit at the end of the middle channel.
    build_water_wheel("Wheel_Main", (9.32, 6.38, 1.3), 1.02, 0.55, axis="Y", paddles=16)
    for y in (5.98, 6.78):
        bearing_block(static, (9.32, y, 1.3))
    build_shaft("Axle_Main", (9.32, 5.7, 1.3), (9.32, 7.1, 1.3), 0.07)
    # East wheel (overshot) fed by the aqueduct flume from the upper pool.
    build_water_wheel("Wheel_East", (12.0, 2.6, 1.55), 0.74, 0.42, axis="X", paddles=12)
    build_shaft("Axle_East", (10.95, 2.6, 1.55), (12.45, 2.6, 1.55), 0.06)
    bearing_block(static, (11.5, 2.6, 1.55))
    bearing_block(static, (12.4, 2.6, 1.55))
    for x in (11.5, 12.4):
        static.box((x, 2.6, 0.1), (0.24, 0.24, 2.4), "Wood_Frame", bevel=0.02)
    static.box((11.95, 2.6, -1.0), (1.3, 0.6, 0.3), "Stone_Masonry", bevel=0.03)
    # Small stream wheel by the start (undershot), first sluice beside it.
    build_water_wheel("Wheel_Stream", (2.5, 2.5, 0.05), 0.48, 0.32, axis="Y", paddles=10)
    for y in (2.08, 2.92):
        bearing_block(static, (2.5, y, 0.05))

    # Gear train: east wheel axle -> line shaft -> lift winch (all real meshes).
    build_gear("Gear_EastDrive", (11.2, 2.6, 1.55), 0.34, 18, 0.08, axis="X")
    build_gear("Gear_LineBevel", (10.98, 2.32, 1.55), 0.22, 12, 0.07, axis="Y")
    build_shaft("Shaft_LineToLift", (10.98, 2.28, 1.55), (10.98, 1.0, 1.55), 0.05)
    build_gear("Gear_LiftBevel", (10.98, 1.0, 1.77), 0.22, 12, 0.07, axis="Z")
    build_shaft("Shaft_LiftVertical", (10.98, 1.0, 1.75), (10.98, 1.0, 4.35), 0.05)
    build_gear("Gear_Winch", (10.98, 1.0, 4.45), 0.3, 16, 0.08, axis="X")
    for y in (1.8, 1.25):
        bearing_block(static, (10.98, y, 1.55))
    # Main wheel axle -> pillar gear on the middle terrace (drives the shutters).
    build_gear("Gear_MainAxle", (9.32, 5.75, 1.3), 0.28, 14, 0.07, axis="Y")
    build_gear("Gear_LineDrop", (9.32, 5.62, 0.86), 0.2, 10, 0.07, axis="Y")
    build_shaft("Shaft_MainToPillar", (9.1, 5.62, 0.86), (4.3, 5.62, 0.86), 0.05)
    build_gear("Gear_PillarCrown", (4.3, 6.3, Z1 + 0.95), 0.5, 22, 0.1, axis="Z")
    pillar = Builder("Gear_Pillar", collection("L05/Static_Architecture/Stone"))
    stone_pier(pillar, 4.3, 6.3, Z1, Z1 + 0.75, 0.55)
    pillar.cylinder((4.3, 6.3, Z1 + 0.85), 0.08, 0.3, "Iron")
    pillar.finish()
    static.finish()

    # Start-floor gear + ring button (pressure plate) and the sluice lever.
    build_gear("Gear_StartRing", (3.3, 3.85, Z0 + 0.12), 0.42, 16, 0.1, axis="Z")
    build_ring_plate("Plate_StartRing", (3.3, 3.85, Z0 + 0.2), 0.3, "Goal_Gold", "Iron")
    build_lever("Lever_Sluice", (2.2, 4.55, Z0), yaw=0.4)
    build_lever("Lever_Secret", (9.9, 4.4, Z0), yaw=-1.2)
    build_ring_plate("Plate_Cube", (7.9, 1.0, Z0 + 0.02), 0.34, "Plate_White", "Red_Paint")
    build_valve("Valve_Diverter", (6.6, 7.7, Z2 + 0.1), "X")
    build_valve("Valve_PoolSluice", (12.0, 6.05, Z2 + 0.2), "X")
    build_sluice_gate("Gate_StreamSluice", (1.6, 2.5, -0.2), "Y", 0.9)
    build_sluice_gate("Gate_MiddleShutter", (7.6, 4.2, Z1), "Y", 1.2, height=0.6)
    build_corridor_dressing()
    build_crate("Crate_Cube", (5.0, 1.0, Z0 + 0.23), 0.45)
    build_crate("Crate_Workshop", (6.3, 3.0, Z1 + 0.25), 0.5)
    build_crate("Crate_ValveDeck", (8.1, 9.2, Z2 + 0.25), 0.5)
    build_crate("Crate_Stack_A", (10.6, 5.2, Z1 + 0.25), 0.5)
    build_crate("Crate_Stack_B", (10.6, 5.2, Z1 + 0.76), 0.5, yaw=0.3)
    build_goal("Goal_Socket", (2.4, 8.6, Z2))


def build_corridor_dressing():
    """Hidden lower path (reference panel 04): beams, lanterns, gear and ring."""
    b = Builder("Corridor_Beams_Lanterns", collection("L05/Static_Architecture/Timber"))
    for x in (6.3, 7.2, 8.1, 8.9):
        b.box((x, 4.0, Z1 - DECK_T - 0.12), (0.18, 1.6, 0.22), "Wood_Dark", bevel=0.02)
        for y in (3.32, 4.68):
            b.box((x, y, (Z1 - DECK_T) / 2), (0.16, 0.12, Z1 - DECK_T), "Wood_Frame", bevel=0.02)
    for x, y in ((6.75, 3.4), (8.5, 4.6), (9.7, 4.85)):
        b.box((x, y, 0.92), (0.05, 0.05, 0.25), "Iron", bevel=0.005)
        b.box((x, y, 0.72), (0.14, 0.14, 0.2), "Lantern_Glow", bevel=0.01)
        b.box((x, y, 0.84), (0.18, 0.18, 0.04), "Brass", bevel=0.008)
        light = bpy.data.lights.new("Corridor_Lantern", "POINT")
        light.energy = 25
        light.color = (1.0, 0.6, 0.28)
        light.shadow_soft_size = 0.08
        lo = bpy.data.objects.new("Corridor_Lantern", light)
        lo.location = (x, y, 0.72)
        collection("L05/Lights_Cameras").objects.link(lo)
    b.finish()
    build_gear("Gear_CorridorTrigger", (8.2, 3.75, Z0 + 0.1), 0.32, 14, 0.08, axis="Z")
    build_ring_plate("Plate_CorridorRing", (8.2, 3.75, Z0 + 0.16), 0.24, "Goal_Gold", "Iron")


def build_ring_plate(name, center, radius, ring_mat, base_mat):
    b = Builder(name, collection("L05/Mechanisms/Buttons_Levers"))
    b.cylinder((0, 0, 0.0), radius + 0.08, 0.05, base_mat, segments=28)
    b.torus((0, 0, 0.04), radius, 0.055, ring_mat, seg_major=32, seg_minor=8)
    b.cylinder((0, 0, 0.02), radius * 0.75, 0.03, "Slate_Floor", segments=28)
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
    b = Builder(name, collection("L05/Mechanisms/Buttons_Levers"))
    b.cylinder((0, 0, 0.02), 0.62, 0.05, "Iron", segments=36)
    b.torus((0, 0, 0.07), 0.44, 0.08, "Goal_Gold", seg_major=40, seg_minor=10)
    b.torus((0, 0, 0.07), 0.56, 0.025, "Brass", seg_major=40, seg_minor=6)
    b.cylinder((0, 0, 0.03), 0.34, 0.04, "Slate_Floor", segments=36)
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
    # Header frame, pulley sheaves and winch drum.
    for y in (y0 - 0.1, y1 + 0.1):
        tower.box(((x0 + x1) / 2, y, top), (x1 - x0 + 0.4, 0.2, 0.2), "Wood_Frame", bevel=0.025)
    for x in (x0 - 0.1, x1 + 0.1):
        tower.box((x, (y0 + y1) / 2, top), (0.2, y1 - y0 + 0.4, 0.2), "Wood_Frame", bevel=0.025)
    tower.cylinder(((x0 + x1) / 2, (y0 + y1) / 2, top + 0.25), 0.22, x1 - x0 + 0.2, "Wood_Dark", axis="X", segments=18)
    for x in (x0 + 0.25, x1 - 0.25):
        tower.cylinder((x, (y0 + y1) / 2, top + 0.25), 0.27, 0.05, "Iron", axis="X", segments=20)
    # Guide rails inside each corner.
    for x in (x0 + 0.04, x1 - 0.04):
        for y in (y0 + 0.04, y1 - 0.04):
            tower.box((x, y, (top - 0.6) / 2 + 0.0), (0.05, 0.05, top + 0.6), "Iron", bevel=0.005)
    # Counterweight with iron bands on the east face.
    tower.box((x1 + 0.38, (y0 + y1) / 2, 2.4), (0.3, 0.5, 0.7), "Stone_Masonry", bevel=0.03)
    for z in (2.15, 2.65):
        tower.box((x1 + 0.38, (y0 + y1) / 2, z), (0.33, 0.53, 0.05), "Iron", bevel=0.005)
    tower.finish()

    cage = Builder("Lift_Cage", collection("L05/Mechanisms/Lift"))
    w, d = x1 - x0 - 0.12, y1 - y0 - 0.12
    for k in range(6):
        cage.box((0, -d / 2 + (k + 0.5) * d / 6, -0.03), (w, d / 6 - 0.015, 0.06), "Wood_Plank", bevel=0.008)
    cage.box((0, 0, -0.12), (w, d, 0.12), "Wood_Dark", bevel=0.01)
    # Fixed lips on the closed south and east sides; corner posts with brass.
    cage.box((0, -d / 2 + 0.05, 0.14), (w, 0.1, 0.28), "Wood_Frame", bevel=0.02)
    cage.box((w / 2 - 0.05, 0, 0.14), (0.1, d, 0.28), "Wood_Frame", bevel=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cage.box((sx * (w / 2 - 0.05), sy * (d / 2 - 0.05), 0.35), (0.12, 0.12, 0.7), "Wood_Frame", bevel=0.02)
            cage.box((sx * (w / 2 - 0.05), sy * (d / 2 - 0.05), 0.73), (0.16, 0.16, 0.07), "Brass", bevel=0.015)
    cage.box((0, 0, 0.75), (w, 0.1, 0.1), "Wood_Frame", bevel=0.02)
    cage.cylinder((0, 0, 0.83), 0.06, 0.1, "Iron", segments=10)
    cage_obj = cage.finish()
    cage_obj.location = ((x0 + x1) / 2, (y0 + y1) / 2, Z0)
    cage_obj["l05_role"] = "lift_deck"
    cage_obj["l05_floors"] = [Z0, Z1, Z2]
    for gate_name, at, axis in (("Lift_Gate_West", (x0 + 0.06, (y0 + y1) / 2, Z0), "Y"), ("Lift_Gate_North", ((x0 + x1) / 2, y1 - 0.06, Z0), "X")):
        g = Builder(gate_name, collection("L05/Mechanisms/Lift"))
        for k in range(3):
            size = (0.05, d - 0.2, 0.06) if axis == "Y" else (w - 0.2, 0.05, 0.06)
            g.box((0, 0, 0.1 + k * 0.12), size, "Wood_Frame", bevel=0.01)
        go = g.finish()
        go.location = at
        go["l05_role"] = "lift_gate"
    chain = Builder("Lift_Chain", collection("L05/Mechanisms/Lift"))
    links = int((top + 0.25 - 0.85) / 0.09)
    for k in range(links):
        z = 0.85 + k * 0.09
        chain.torus((0, 0, z), 0.035, 0.009, "Iron", axis="X" if k % 2 else "Y", seg_major=10, seg_minor=4)
    co = chain.finish()
    co.location = ((x0 + x1) / 2, (y0 + y1) / 2, Z0)
    co["l05_role"] = "lift_chain"


# ----------------------------------------------------------------------------
# Summit millhouse: timber frame, plank walls, door, glowing windows, tile roof
# ----------------------------------------------------------------------------

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
    for attr, value in (("sun_elevation", math.radians(38)), ("sun_rotation", math.radians(-115)), ("altitude", 2200.0), ("air_density", 1.0), ("dust_density", 0.6), ("sun_intensity", 0.7)):
        if hasattr(sky, attr):
            try:
                setattr(sky, attr, value)
            except Exception:
                pass
    bg.inputs["Strength"].default_value = 0.32
    links.new(sky.outputs["Color"], bg.inputs["Color"])
    links.new(bg.outputs["Background"], out.inputs["Surface"])

    sun = bpy.data.lights.new("Alpine_Sun", "SUN")
    sun.energy = 3.4
    sun.color = (1.0, 0.95, 0.86)
    sun.angle = math.radians(1.5)
    so = bpy.data.objects.new("Alpine_Sun", sun)
    so.rotation_euler = (math.radians(52), 0, math.radians(-145))
    collection("L05/Lights_Cameras").objects.link(so)
    fill = bpy.data.lights.new("Sky_Fill", "AREA")
    fill.energy = 400
    fill.size = 20
    fill.color = (0.75, 0.85, 1.0)
    fo = bpy.data.objects.new("Sky_Fill", fill)
    fo.location = (-8, -10, 14)
    fo.rotation_euler = (math.radians(50), 0, math.radians(-45))
    collection("L05/Lights_Cameras").objects.link(fo)
    # Warm glow inside the mill so the windows light the deck.
    inner = bpy.data.lights.new("Mill_Interior", "POINT")
    inner.energy = 120
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
    empty("Marker_Goal", (2.4, 8.6, Z2), col, "CIRCLE", 0.45)
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


def render_all(cameras, only=None):
    os.makedirs(RENDER_DIR, exist_ok=True)
    scene = bpy.context.scene
    for key, cam in cameras.items():
        if only and key not in only:
            continue
        scene.camera = cam
        scene.render.filepath = os.path.join(RENDER_DIR, "L05_%s.png" % key)
        bpy.ops.render.render(write_still=True)
        print("L05 rendered", scene.render.filepath)


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
    reset_scene()
    build_materials()
    for spec in DECKS:
        holes = (WHEEL_PIT,) if spec[0] == "M_Workshop" else ()
        build_deck(*spec, holes=holes)
    for spec in BRIDGES:
        build_bridge(*spec)
    build_foundations()
    build_water()
    build_mechanisms()
    build_lift()
    build_millhouse()
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
        print("L05 saved", BLEND_PATH)
    if "--render" in argv:
        render_all(cameras, only)
    stats = {"objects": len(bpy.data.objects), "meshes": len(bpy.data.meshes),
             "triangles": sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == "MESH" and not o.hide_render)}
    print("L05 stats", stats)


if __name__ == "__main__":
    main()
