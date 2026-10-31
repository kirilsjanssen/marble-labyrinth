#!/usr/bin/env python3
"""Parametric Level 06 Orbital Mechanism construction for Blender 5.2 LTS.

One Blender unit is one metre. The script builds a high-detail authoring scene,
keeps mechanical chains as separate named objects, creates ten reusable actions,
exports HIGH/LOW GLB variants, performs a geometry audit, and renders eight
independent art-direction views.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
LEVEL = ROOT / "assets/levels/level06"
PBR = LEVEL / "textures/pbr"
BLEND_PATH = ROOT / "assets/blender/level06_orbital_mechanism_v2.blend"
HIGH_GLB = LEVEL / "level06_orbital_mechanism_v2_high.glb"
LOW_GLB = LEVEL / "level06_orbital_mechanism_v2_low.glb"
RENDER_DIR = ROOT / "docs/media/level06_orbital/renders_v2"
AUDIT_PATH = ROOT / "docs/level06_v2_engineering_audit.json"

COLLECTIONS: dict[str, bpy.types.Collection] = {}
MATS: dict[str, bpy.types.Material] = {}
OBJECTS: dict[str, bpy.types.Object] = {}

BALL_D = 1.0
BRIDGE_W = 2.8
TUBE_OD = 1.85
TUBE_ID = 1.65
RING_OD = 46.0
RING_ID = 38.8
RING_R0 = RING_ID / 2.0
RING_R1 = RING_OD / 2.0


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--skip-renders", action="store_true")
    parser.add_argument("--engine", choices=("AUTO", "CYCLES", "EEVEE"), default="AUTO")
    return parser.parse_args(argv)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(datablocks):
            if item.users == 0:
                datablocks.remove(item)


def collection(name: str) -> bpy.types.Collection:
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    COLLECTIONS[name] = col
    return col


def move_to(obj: bpy.types.Object, col: bpy.types.Collection) -> None:
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    col.objects.link(obj)


def tag(obj: bpy.types.Object, lod: str = "BOTH", export: bool = True, role: str = "visual") -> bpy.types.Object:
    obj["level06_lod"] = lod
    obj["level06_export"] = export
    obj["level06_role"] = role
    OBJECTS[obj.name] = obj
    return obj


def bevel(obj: bpy.types.Object, width: float = 0.08, segments: int = 2) -> None:
    mod = obj.modifiers.new("Engineering edge radius", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"


def assign(obj: bpy.types.Object, mat: bpy.types.Material | None) -> None:
    if mat and hasattr(obj.data, "materials"):
        obj.data.materials.append(mat)


def add_box(
    name: str,
    loc: tuple[float, float, float],
    dims: tuple[float, float, float],
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    rot_z: float = 0.0,
    lod: str = "BOTH",
    edge: float = 0.06,
    role: str = "visual",
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=(0.0, 0.0, rot_z))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    move_to(obj, col)
    if edge > 0:
        bevel(obj, min(edge, min(dims) * 0.24), 2)
    return tag(obj, lod, True, role)


def add_cylinder(
    name: str,
    loc: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    rot: tuple[float, float, float] = (0.0, 0.0, 0.0),
    vertices: int = 32,
    lod: str = "BOTH",
    role: str = "visual",
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    move_to(obj, col)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    bevel(obj, min(0.07, radius * 0.08), 2)
    return tag(obj, lod, True, role)


def add_torus(
    name: str,
    loc: tuple[float, float, float],
    major: float,
    minor: float,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    rot: tuple[float, float, float] = (0.0, 0.0, 0.0),
    lod: str = "BOTH",
    major_segments: int = 48,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major,
        minor_radius=minor,
        major_segments=major_segments,
        minor_segments=10,
        location=loc,
        rotation=rot,
    )
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    move_to(obj, col)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return tag(obj, lod)


def add_sphere(
    name: str,
    loc: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    lod: str = "BOTH",
    segments: int = 48,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=max(12, segments // 2), radius=radius, location=loc)
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    move_to(obj, col)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return tag(obj, lod)


def add_empty(name: str, loc: tuple[float, float, float], col: bpy.types.Collection, role: str) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    obj.location = loc
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.8
    col.objects.link(obj)
    return tag(obj, "BOTH", True, role)


def beam_between(
    name: str,
    start: tuple[float, float, float] | Vector,
    end: tuple[float, float, float] | Vector,
    thickness: float,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    lod: str = "HIGH",
    role: str = "structural_brace",
) -> bpy.types.Object:
    a, b = Vector(start), Vector(end)
    direction = b - a
    length = direction.length
    bpy.ops.mesh.primitive_cube_add(location=(a + b) * 0.5)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (length, thickness, thickness)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("X", "Z")
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    move_to(obj, col)
    bevel(obj, thickness * 0.22, 2)
    return tag(obj, lod, True, role)


def image(path: Path, non_color: bool = False) -> bpy.types.Image:
    img = bpy.data.images.load(str(path), check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def principled(
    name: str,
    color: tuple[float, float, float, float],
    metallic: float,
    roughness: float,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
    transmission: float = 0.0,
    alpha: float = 1.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = transmission
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.22 if metallic > 0.5 else 0.08
    if "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = alpha
    if emission:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha < 1.0:
        mat.diffuse_color = (*color[:3], alpha)
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "DITHERED"
        elif hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
        mat.use_transparency_overlap = False
    MATS[name] = mat
    return mat


def textured_metal(name: str, prefix: str, metallic: float, normal_strength: float) -> bpy.types.Material:
    mat = principled(name, (0.2, 0.2, 0.2, 1.0), metallic, 0.45)
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    texcoord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    nt.links.new(texcoord.outputs["UV"], mapping.inputs["Vector"])
    albedo = nt.nodes.new("ShaderNodeTexImage")
    albedo.image = image(PBR / f"{prefix}_albedo.jpg")
    rough = nt.nodes.new("ShaderNodeTexImage")
    rough.image = image(PBR / f"{prefix}_roughness.png", True)
    normal = nt.nodes.new("ShaderNodeTexImage")
    normal.image = image(PBR / f"{prefix}_normal.png", True)
    normal_map = nt.nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = normal_strength
    for node in (albedo, rough, normal):
        node.extension = "REPEAT"
        nt.links.new(mapping.outputs["Vector"], node.inputs["Vector"])
    nt.links.new(albedo.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    nt.links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    nt.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def materials() -> None:
    MATS["dark"] = textured_metal("PBR_Dark_Orbital_Metal", "dark_orbital_metal", 0.82, 0.42)
    MATS["titanium"] = textured_metal("PBR_Brushed_Titanium", "brushed_titanium", 0.90, 0.28)
    MATS["bronze"] = textured_metal("PBR_Aged_Bronze", "aged_bronze", 0.84, 0.34)
    MATS["steel"] = textured_metal("PBR_Matte_Structural_Steel", "matte_steel", 0.72, 0.22)
    MATS["black"] = principled("PBR_Black_Composite", (0.015, 0.021, 0.032, 1), 0.25, 0.42)
    MATS["glass"] = principled("PBR_Technical_Glass", (0.035, 0.18, 0.28, 1), 0.05, 0.075, transmission=0.91, alpha=0.22)
    MATS["blue"] = principled("PBR_Magnetic_Blue", (0.005, 0.07, 0.18, 1), 0.22, 0.17, (0.005, 0.20, 1.0, 1), 4.8)
    MATS["blue_soft"] = principled("PBR_Energy_Blue_Soft", (0.005, 0.045, 0.12, 1), 0.10, 0.25, (0.01, 0.16, 0.75, 1), 2.7)
    MATS["red"] = principled("PBR_Warning_Red", (0.26, 0.004, 0.008, 1), 0.35, 0.22, (1.0, 0.006, 0.012, 1), 4.5, alpha=0.76)
    MATS["gold"] = principled("PBR_Gold_Energy", (0.78, 0.20, 0.018, 1), 0.72, 0.18, (1.0, 0.13, 0.006, 1), 5.5)
    MATS["copper"] = principled("PBR_Machined_Copper", (0.36, 0.075, 0.018, 1), 0.92, 0.24)
    MATS["hazard"] = principled("PBR_Hazard_Yellow", (0.72, 0.34, 0.015, 1), 0.58, 0.34)
    MATS["ceramic"] = principled("PBR_White_Ceramic", (0.48, 0.56, 0.68, 1), 0.12, 0.20)
    MATS["ball"] = principled("PBR_Game_Ball_Brushed_Steel", (0.30, 0.34, 0.40, 1), 0.94, 0.19)
    MATS["planet"] = principled("PBR_Planet", (0.025, 0.12, 0.34, 1), 0.0, 0.74)
    MATS["atmosphere"] = principled("PBR_Atmosphere", (0.01, 0.12, 0.55, 1), 0.0, 0.25, (0.01, 0.09, 0.55, 1), 1.6, alpha=0.14)
    MATS["cloud"] = principled("PBR_Planet_Clouds", (0.55, 0.72, 0.92, 1), 0.0, 0.82, (0.04, 0.09, 0.18, 1), 0.35, alpha=0.20)
    MATS["asteroid"] = principled("PBR_Asteroid", (0.035, 0.04, 0.055, 1), 0.10, 0.88)
    for key, anisotropy in (("dark", 0.28), ("titanium", 0.46), ("bronze", 0.32), ("steel", 0.18), ("copper", 0.42)):
        bsdf_node = MATS[key].node_tree.nodes.get("Principled BSDF")
        if "Anisotropic IOR Level" in bsdf_node.inputs:
            bsdf_node.inputs["Anisotropic IOR Level"].default_value = anisotropy
        if "Coat Weight" in bsdf_node.inputs:
            bsdf_node.inputs["Coat Weight"].default_value = 0.20
    glass_bsdf = MATS["glass"].node_tree.nodes.get("Principled BSDF")
    if "IOR" in glass_bsdf.inputs:
        glass_bsdf.inputs["IOR"].default_value = 1.46
    # Procedural cloud/ocean modulation keeps the environment independent of
    # the tilting station and avoids using the background to hide geometry.
    planet = MATS["planet"]
    nt = planet.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.8
    noise.inputs["Detail"].default_value = 7.0
    noise.inputs["Roughness"].default_value = 0.68
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (0.002, 0.018, 0.09, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.30, 0.66, 0.95, 1)
    cloud = ramp.color_ramp.elements.new(0.58)
    cloud.color = (0.78, 0.90, 1.0, 1)
    nt.links.new(coord.outputs["Generated"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.32
    bump.inputs["Distance"].default_value = 0.18
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    cloud_mat = MATS["cloud"]
    cnt = cloud_mat.node_tree
    cbsdf = cnt.nodes.get("Principled BSDF")
    ccoord = cnt.nodes.new("ShaderNodeTexCoord")
    cnoise = cnt.nodes.new("ShaderNodeTexNoise")
    cnoise.inputs["Scale"].default_value = 4.8
    cnoise.inputs["Detail"].default_value = 8.0
    cnoise.inputs["Roughness"].default_value = 0.72
    cramp = cnt.nodes.new("ShaderNodeValToRGB")
    cramp.color_ramp.elements[0].position = 0.46
    cramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    cramp.color_ramp.elements[1].position = 0.62
    cramp.color_ramp.elements[1].color = (0.85, 0.95, 1.0, 1)
    cnt.links.new(ccoord.outputs["Generated"], cnoise.inputs["Vector"])
    cnt.links.new(cnoise.outputs["Fac"], cramp.inputs["Fac"])
    cnt.links.new(cramp.outputs["Color"], cbsdf.inputs["Base Color"])
    cnt.links.new(cnoise.outputs["Fac"], cbsdf.inputs["Alpha"])


def annular_sector(name: str, a0: float, a1: float, z: float, col: bpy.types.Collection, mat: bpy.types.Material) -> bpy.types.Object:
    steps = 5
    verts: list[tuple[float, float, float]] = []
    for zz in (z - 0.30, z + 0.30):
        for radius in (RING_R0, RING_R1):
            for i in range(steps + 1):
                a = a0 + (a1 - a0) * i / steps
                verts.append((radius * math.cos(a), radius * math.sin(a), zz))
    n = steps + 1
    faces = []
    # top and bottom annular strips
    for layer in (0, 1):
        base = layer * 2 * n
        for i in range(steps):
            f = (base + i, base + i + 1, base + n + i + 1, base + n + i)
            faces.append(f if layer else tuple(reversed(f)))
    # inner/outer walls
    for radial in (0, 1):
        b0 = radial * n
        b1 = 2 * n + radial * n
        for i in range(steps):
            faces.append((b0 + i, b1 + i, b1 + i + 1, b0 + i + 1))
    # end caps
    faces += [(0, n, 3 * n, 2 * n), (steps, 2 * n - 1, 4 * n - 1, 3 * n - 1)]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for loop_index in poly.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv_layer.data[loop_index].uv = (vertex.x / (RING_R1 * 2.0) + 0.5, vertex.y / (RING_R1 * 2.0) + 0.5)
    obj = bpy.data.objects.new(name, mesh)
    col.objects.link(obj)
    assign(obj, mat)
    bevel(obj, 0.07, 2)
    return tag(obj, "BOTH", True, "station_ring_segment")


def radial_frame(index: int, angle: float, z: float, col: bpy.types.Collection) -> None:
    mid = (RING_R0 + RING_R1) * 0.5
    x, y = mid * math.cos(angle), mid * math.sin(angle)
    rot = angle
    add_box(f"R01_Frame_{index:02d}", (x, y, z + 0.55), (3.95, 0.20, 1.65), MATS["bronze"], col, rot, "HIGH", 0.05)
    for side in (-1.0, 1.0):
        rr = RING_R0 + (side + 1.0) * 1.8
        sx, sy = rr * math.cos(angle), rr * math.sin(angle)
        add_cylinder(f"R01_Bolt_{index:02d}_{int(side)}", (sx, sy, z + 0.38), 0.11, 0.18, MATS["titanium"], col, vertices=16, lod="HIGH")


def build_ring() -> None:
    col = COLLECTIONS["01_RING"]
    segments = 24
    gap = math.radians(0.65)
    for i in range(segments):
        a0 = math.tau * i / segments + gap
        a1 = math.tau * (i + 1) / segments - gap
        annular_sector(f"R01_Segment_{i:02d}", a0, a1, 4.0, col, MATS["dark"] if i % 2 else MATS["steel"])
        radial_frame(i, (a0 + a1) * 0.5, 4.0, col)
    for i in range(48):
        a = math.tau * i / 48
        r = 22.35
        x, y = r * math.cos(a), r * math.sin(a)
        add_box(f"R01_EnergyStrip_{i:02d}", (x, y, 4.34), (1.05, 0.13, 0.10), MATS["blue"], col, a + math.pi / 2, "HIGH", 0.02)
    for i in range(12):
        a = math.tau * i / 12
        r = 21.2
        x, y = r * math.cos(a), r * math.sin(a)
        add_box(f"S01_Pylon_{i:02d}", (x, y, 1.8), (0.65, 0.65, 3.6), MATS["steel"], col, a, "BOTH", 0.08, "ring_support")
        add_box(f"S01_PylonBlue_{i:02d}", (x, y, 2.1), (0.70, 0.10, 1.9), MATS["blue_soft"], col, a, "HIGH", 0.02)
    # V2: a secondary load path, service raceways and dense modular joints.
    add_torus("R01_InnerStructuralBelt", (0, 0, 3.72), 18.35, 0.26, MATS["steel"], col, lod="BOTH", major_segments=144)
    add_torus("R01_InnerCableRaceway", (0, 0, 4.58), 18.72, 0.15, MATS["black"], col, lod="HIGH", major_segments=144)
    add_torus("R01_InnerEnergyBus", (0, 0, 4.62), 18.43, 0.055, MATS["blue_soft"], col, lod="HIGH", major_segments=144)
    add_torus("R01_OuterServiceConduit", (0, 0, 4.73), 22.46, 0.12, MATS["copper"], col, lod="HIGH", major_segments=144)
    for i in range(24):
        a = math.tau * (i + 0.5) / 24
        tangent_rot = a + math.pi / 2
        c, s = math.cos(a), math.sin(a)
        inner = Vector((18.35 * c, 18.35 * s, 4.08))
        main = Vector((19.62 * c, 19.62 * s, 4.22))
        outer = Vector((22.38 * c, 22.38 * s, 4.0))
        add_box(
            f"R01_InnerModule_{i:02d}", inner, (2.15, 0.72, 0.82),
            MATS["dark"] if i % 2 else MATS["titanium"], col, tangent_rot,
            "BOTH" if i % 2 == 0 else "HIGH", 0.10, "inner_structural_module"
        )
        beam_between(f"R01_RadialTrussTop_{i:02d}", inner + Vector((0, 0, 0.36)), main + Vector((0, 0, 0.63)), 0.13, MATS["bronze"], col)
        beam_between(f"R01_RadialTrussLow_{i:02d}", inner - Vector((0, 0, 0.36)), main - Vector((0, 0, 0.35)), 0.13, MATS["steel"], col)
        pod = add_box(
            f"R01_ServicePod_{i:02d}", (outer.x, outer.y, 4.98), (1.35, 0.86, 1.52),
            MATS["steel"], col, tangent_rot, "HIGH", 0.13, "service_module"
        )
        pod["service_access"] = True
        add_box(
            f"R01_ServiceHatch_{i:02d}", (outer.x, outer.y, 5.78), (0.72, 0.48, 0.08),
            MATS["hazard"], col, tangent_rot, "HIGH", 0.025, "maintenance_hatch"
        )
        for j in (-0.34, 0.34):
            rr = 21.15 + j
            bx, by = rr * c, rr * s
            add_cylinder(
                f"R01_JointBolt_{i:02d}_{j}", (bx, by, 4.44), 0.115, 0.20,
                MATS["titanium"], col, vertices=12, lod="HIGH", role="segment_fastener"
            )
        if i % 3 == 0:
            # External radiator/antenna fins break the empty silhouette.
            add_box(
                f"R01_RadiatorFin_{i:02d}", (23.15 * c, 23.15 * s, 5.20),
                (1.65, 0.10, 2.15), MATS["ceramic"], col, tangent_rot,
                "HIGH", 0.035, "thermal_radiator"
            )


def xy_frame(start: tuple[float, float], end: tuple[float, float]) -> tuple[Vector, float, float, Vector, Vector]:
    a, b = Vector(start), Vector(end)
    d = b - a
    length = d.length
    tangent = d.normalized()
    side = Vector((-tangent.y, tangent.x))
    return (a + b) * 0.5, length, math.atan2(d.y, d.x), tangent, side


def support_tower(name: str, point: Vector, deck_z: float, spread: float = 0.58) -> None:
    col = COLLECTIONS["06_SUPPORTS"]
    height = max(2.0, deck_z - 0.35)
    center_z = (deck_z - 0.55) * 0.5
    for ix, dx in enumerate((-spread, spread)):
        for iy, dy in enumerate((-spread, spread)):
            add_box(
                f"{name}_Leg_{ix}_{iy}", (point.x + dx, point.y + dy, center_z),
                (0.24, 0.24, height), MATS["steel"], col, lod="BOTH", edge=0.045, role="structural_support"
            )
    levels = max(2, int(deck_z / 2.2))
    for i in range(levels + 1):
        z = 0.45 + (deck_z - 1.0) * i / levels
        add_box(f"{name}_CrossX_{i}", (point.x, point.y, z), (spread * 2.35, 0.16, 0.16), MATS["bronze"], col, lod="HIGH", edge=0.035)
        add_box(f"{name}_CrossY_{i}", (point.x, point.y, z), (0.16, spread * 2.35, 0.16), MATS["bronze"], col, lod="HIGH", edge=0.035)
    add_box(f"{name}_EnergySpine", (point.x, point.y - spread - 0.03, center_z), (0.12, 0.08, height * 0.72), MATS["blue_soft"], col, lod="HIGH", edge=0.02)


def bridge(node: str, start: tuple[float, float], end: tuple[float, float], z: float, movable: bool = False) -> None:
    col = COLLECTIONS["02_TRACKS"]
    mid, length, angle, tangent, side = xy_frame(start, end)
    deck_name = f"{node}_{'Movable' if movable else 'Deck'}"
    deck = add_box(deck_name, (mid.x, mid.y, z - 0.275), (length, BRIDGE_W, 0.55), MATS["dark"], col, angle, "BOTH", 0.10, "walkable_surface")
    deck["walkable_width_m"] = BRIDGE_W
    deck["surface_z_m"] = z
    deck["collision_shape"] = "box"
    if movable:
        pivot = add_empty(f"{node}_PIVOT", (start[0], start[1], z), col, "kinematic_pivot")
        deck.parent = pivot
        deck.matrix_parent_inverse = pivot.matrix_world.inverted()
        base = Vector((start[0], start[1], z))
        pivot.location = base
        pivot.keyframe_insert("location", frame=1)
        pivot.location = base - Vector((tangent.x * 2.2, tangent.y * 2.2, 0.0))
        pivot.keyframe_insert("location", frame=70)
        pivot.keyframe_insert("location", frame=110)
        pivot.location = base
        pivot.keyframe_insert("location", frame=170)
        if pivot.animation_data and pivot.animation_data.action:
            pivot.animation_data.action.name = "ANIM_07_Extending_Bridge"
    # panel seams, rails, underframe, warning strips
    panel_count = max(2, int(length / 1.35))
    for i in range(panel_count + 1):
        along = -length / 2 + length * i / panel_count
        p = mid + tangent * along
        add_box(f"{node}_PanelSeam_{i:02d}", (p.x, p.y, z + 0.015), (0.055, BRIDGE_W * 0.92, 0.035), MATS["titanium"], col, angle, "HIGH", 0.01)
        if i % 2 == 0 and 0 < i < panel_count:
            add_box(
                f"{node}_ServicePanel_{i:02d}", (p.x, p.y, z + 0.045),
                (0.72, BRIDGE_W * 0.58, 0.045), MATS["steel"], col, angle,
                "HIGH", 0.025, "removable_floor_panel"
            )
    # V2 warning chevrons and inset energy channels make the deck readable.
    for end_index, end_sign in enumerate((-1.0, 1.0)):
        for stripe in range(4):
            along = end_sign * (length / 2 - 0.30 - stripe * 0.18)
            p = mid + tangent * along
            add_box(
                f"{node}_Hazard_{end_index}_{stripe}", (p.x, p.y, z + 0.075),
                (0.10, BRIDGE_W * 0.78, 0.025), MATS["hazard"] if stripe % 2 == 0 else MATS["black"],
                col, angle + math.radians(24), "HIGH", 0.005, "warning_marking"
            )
    for side_sign in (-1.0, 1.0):
        offset = side * side_sign * (BRIDGE_W / 2 - 0.10)
        p = mid + offset
        add_box(f"{node}_RailTop_{int(side_sign)}", (p.x, p.y, z + 0.76), (length, 0.10, 0.10), MATS["bronze"], col, angle, "BOTH", 0.025)
        add_box(f"{node}_EdgeBlue_{int(side_sign)}", (p.x, p.y, z - 0.06), (length * 0.96, 0.07, 0.13), MATS["blue_soft"], col, angle, "HIGH", 0.02)
        for i in range(panel_count + 1):
            along = -length / 2 + length * i / panel_count
            pp = mid + tangent * along + offset
            add_box(f"{node}_RailPost_{int(side_sign)}_{i:02d}", (pp.x, pp.y, z + 0.38), (0.11, 0.11, 0.76), MATS["steel"], col, angle, "HIGH", 0.025)
    for side_sign in (-0.82, 0.82):
        p = mid + side * side_sign
        add_box(f"{node}_UnderBeam_{side_sign}", (p.x, p.y, z - 0.55), (length, 0.20, 0.36), MATS["steel"], col, angle, "BOTH", 0.05)
    # Spatial under-deck truss with repeated cross-members.
    truss_count = max(2, int(length / 1.8))
    for i in range(truss_count + 1):
        along = -length / 2 + length * i / truss_count
        p = mid + tangent * along
        add_box(f"{node}_CrossMember_{i:02d}", (p.x, p.y, z - 0.72), (0.16, BRIDGE_W * 0.88, 0.18), MATS["bronze"], col, angle, "HIGH", 0.035)
        if i < truss_count:
            q = mid + tangent * (-length / 2 + length * (i + 1) / truss_count)
            beam_between(
                f"{node}_TrussL_{i:02d}",
                (p.x + side.x * 0.84, p.y + side.y * 0.84, z - 0.54),
                (q.x + side.x * 0.84, q.y + side.y * 0.84, z - 1.04),
                0.11, MATS["steel"], col
            )
            beam_between(
                f"{node}_TrussR_{i:02d}",
                (p.x - side.x * 0.84, p.y - side.y * 0.84, z - 1.04),
                (q.x - side.x * 0.84, q.y - side.y * 0.84, z - 0.54),
                0.11, MATS["steel"], col
            )
    # Service conduits and local control boxes.
    conduit_p = mid + side * (BRIDGE_W * 0.37)
    add_box(f"{node}_PowerConduit", (conduit_p.x, conduit_p.y, z - 0.32), (length * 0.88, 0.12, 0.12), MATS["copper"], col, angle, "HIGH", 0.03, "power_conduit")
    control_p = mid - tangent * min(length * 0.28, 1.2) - side * 1.12
    add_box(f"{node}_ControlBox", (control_p.x, control_p.y, z + 0.48), (0.48, 0.34, 0.62), MATS["titanium"], col, angle, "HIGH", 0.07, "bridge_control")
    if movable:
        for side_sign in (-1.0, 1.0):
            actuator_p = mid + side * side_sign * 1.06
            add_cylinder(
                f"{node}_LinearActuator_{int(side_sign)}", (actuator_p.x, actuator_p.y, z - 0.92),
                0.18, length * 0.62, MATS["titanium"], col,
                rot=(0.0, math.pi / 2, angle), vertices=24, lod="HIGH", role="linear_actuator"
            )
    if node in {"B02", "B04", "B05"}:
        for idx, frac in enumerate((0.34, 0.68)):
            p = Vector(start).lerp(Vector(end), frac)
            support_tower(f"{node}_Support_{idx}", p, z, 0.52 if z <= 4.0 else 0.64)


def platform(node: str, center: tuple[float, float], z: float, finish: bool = False) -> None:
    col = COLLECTIONS["02_TRACKS"]
    x, y = center
    deck = add_cylinder(f"{node}_Deck", (x, y, z - 0.30), 3.6, 0.60, MATS["dark"], col, vertices=64, role="walkable_surface")
    deck["surface_z_m"] = z
    deck["platform_diameter_m"] = 7.2
    add_torus(f"{node}_OuterFlange", (x, y, z + 0.02), 3.25, 0.22, MATS["bronze"], col, major_segments=64)
    add_cylinder(f"{node}_LowerMachineryDeck", (x, y, z - 0.70), 3.20, 0.32, MATS["steel"], col, vertices=64, lod="BOTH", role="platform_understructure")
    add_torus(f"{node}_LowerLoadRing", (x, y, z - 0.82), 2.70, 0.18, MATS["titanium"], col, lod="HIGH", major_segments=64)
    add_torus(
        f"{node}_EnergyRing", (x, y, z + 0.05), 2.20, 0.09,
        MATS["gold"] if finish else MATS["blue"], col, lod="HIGH", major_segments=64
    )
    for i in range(16):
        a = math.tau * i / 16
        bx, by = x + 3.05 * math.cos(a), y + 3.05 * math.sin(a)
        add_cylinder(f"{node}_Bolt_{i:02d}", (bx, by, z + 0.09), 0.10, 0.16, MATS["titanium"], col, vertices=12, lod="HIGH")
    for i in range(8):
        a = math.tau * i / 8
        inner = Vector((x + 0.85 * math.cos(a), y + 0.85 * math.sin(a), z - 0.66))
        outer = Vector((x + 2.78 * math.cos(a), y + 2.78 * math.sin(a), z - 0.34))
        beam_between(f"{node}_RadialBrace_{i:02d}", inner, outer, 0.15, MATS["bronze"], col)
        if i % 2 == 0:
            px, py = x + 2.72 * math.cos(a), y + 2.72 * math.sin(a)
            add_box(
                f"{node}_UtilityPod_{i:02d}", (px, py, z + 0.42), (0.58, 0.48, 0.72),
                MATS["steel"], col, a, "HIGH", 0.08, "platform_utility"
            )
    if not finish:
        add_sphere("P01_DemoBall_Start", (x, y, z + 0.5), 0.5, MATS["ball"], COLLECTIONS["07_GAMEPLAY"], segments=64)
    support_tower(f"{node}_Support", Vector((x, y)), z, 0.82 if finish else 0.70)


def build_tracks() -> None:
    platform("P01", (-17, -14), 4.0)
    bridge("B01", (-17, -14), (-12, -14), 4.0)
    bridge("B02", (-12, -14), (-12, -8), 4.0)
    bridge("B03", (-12, -8), (-16, -8), 4.0)
    bridge("B04", (4, 4), (13, 4), 9.0, movable=True)
    bridge("B05", (13, 12), (17, 12), 12.0)
    platform("P02", (17, 12), 12.0, finish=True)


def curve_object(
    name: str,
    points: list[tuple[float, float, float]],
    bevel_depth: float,
    mat: bpy.types.Material,
    col: bpy.types.Collection,
    lod: str = "BOTH",
    role: str = "visual",
) -> bpy.types.Object:
    data = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 18
    data.bevel_resolution = 5
    data.bevel_depth = bevel_depth
    data.resolution_u = 16
    spline = data.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for bp, co in zip(spline.bezier_points, points):
        bp.co = co
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, data)
    col.objects.link(obj)
    assign(obj, mat)
    return tag(obj, lod, True, role)


def torus_along(name: str, point: Vector, tangent: Vector, major: float, minor: float, mat: bpy.types.Material, col: bpy.types.Collection, lod: str) -> bpy.types.Object:
    obj = add_torus(name, point, major, minor, mat, col, lod=lod, major_segments=32)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = tangent.normalized().to_track_quat("Z", "Y")
    return obj


def sample_polyline(points: list[Vector], count: int) -> list[tuple[Vector, Vector]]:
    lengths = [(points[i + 1] - points[i]).length for i in range(len(points) - 1)]
    total = sum(lengths)
    out = []
    for j in range(count):
        d = total * j / max(1, count - 1)
        acc = 0.0
        for i, seg_len in enumerate(lengths):
            if d <= acc + seg_len or i == len(lengths) - 1:
                t = min(1.0, max(0.0, (d - acc) / seg_len))
                tangent = (points[i + 1] - points[i]).normalized()
                out.append((points[i].lerp(points[i + 1], t), tangent))
                break
            acc += seg_len
    return out


def transport_tube(node: str, points: list[tuple[float, float, float]], nominal_length: float) -> bpy.types.Object:
    col = COLLECTIONS["03_TRANSPORT_TUBES"]
    tube = curve_object(f"{node}_GlassShell", points, TUBE_OD / 2, MATS["glass"], col, "BOTH", "transport_tube")
    tube["outer_diameter_m"] = TUBE_OD
    tube["inner_diameter_m"] = TUBE_ID
    tube["ball_diameter_m"] = BALL_D
    tube["radial_clearance_m"] = (TUBE_ID - BALL_D) / 2
    tube["nominal_centerline_length_m"] = nominal_length
    rail_points = [(x, y, z - 0.59) for x, y, z in points]
    curve_object(f"{node}_InnerGuide", rail_points, 0.075, MATS["titanium"], col, "BOTH", "inner_guide")
    # V2 triple-rail cradle: two smaller lateral guides keep the ball centered
    # without reducing the documented 1.65 m clear envelope.
    curve_object(f"{node}_InnerGuideLeft", [(x - 0.27, y, z - 0.48) for x, y, z in points], 0.045, MATS["copper"], col, "HIGH", "inner_guide")
    curve_object(f"{node}_InnerGuideRight", [(x + 0.27, y, z - 0.48) for x, y, z in points], 0.045, MATS["copper"], col, "HIGH", "inner_guide")
    vectors = [Vector(p) for p in points]
    samples = sample_polyline(vectors, max(7, int(nominal_length / 2.2) + 1))
    for i, (p, tangent) in enumerate(samples):
        torus_along(f"{node}_MagneticCoil_{i:02d}", p, tangent, 0.99, 0.075, MATS["blue"], col, "HIGH")
        if i % 3 == 0:
            torus_along(f"{node}_Coupling_{i:02d}", p, tangent, 1.03, 0.16, MATS["bronze"], col, "BOTH")
        if i % 4 == 1:
            # Four-sided accelerator cassette with removable service covers.
            side = Vector((-tangent.y, tangent.x, 0.0)).normalized()
            angle = math.atan2(tangent.y, tangent.x)
            for module_index, offset in enumerate((
                Vector((0, 0, 1.10)), Vector((0, 0, -1.10)), side * 1.08, side * -1.08
            )):
                q = p + offset
                module = add_box(
                    f"{node}_AcceleratorModule_{i:02d}_{module_index}", q,
                    (0.72, 0.46, 0.34), MATS["steel"], col, angle,
                    "HIGH", 0.07, "accelerator_module"
                )
                module["coil_section"] = i
            add_box(
                f"{node}_AcceleratorIndicator_{i:02d}", p + Vector((0, 0, 1.31)),
                (0.44, 0.14, 0.08), MATS["blue"], col, angle,
                "HIGH", 0.015, "direction_indicator"
            )
        if i % 5 == 2:
            side = Vector((-tangent.y, tangent.x, 0.0)).normalized()
            angle = math.atan2(tangent.y, tangent.x)
            for sign in (-1.0, 1.0):
                q = p + side * sign * 1.18
                add_box(
                    f"{node}_BrakeFin_{i:02d}_{int(sign)}", q,
                    (0.62, 0.12, 1.20), MATS["red"], col, angle,
                    "HIGH", 0.035, "magnetic_brake"
                )
    # Directional sensors and brake housings.
    for i, (p, tangent) in enumerate(samples[1:-1:4]):
        q = p + Vector((0, 0, 1.12))
        sensor = add_box(f"{node}_Sensor_{i:02d}", q, (0.42, 0.34, 0.22), MATS["titanium"], col, math.atan2(tangent.y, tangent.x), "HIGH", 0.05, "position_sensor")
        sensor["sensor_axis"] = tuple(tangent)
        # Sensor boom and service tether to the nearest lower structure.
        side = Vector((-tangent.y, tangent.x, 0.0)).normalized()
        beam_between(
            f"{node}_SensorBoom_{i:02d}", q, q + side * 0.82 + Vector((0, 0, -0.34)),
            0.07, MATS["titanium"], col, "HIGH", "sensor_mount"
        )
    # Heavy docking collars at both ends make the pressure boundary explicit.
    for end_index, (p, tangent) in enumerate(((Vector(points[0]), Vector(points[1]) - Vector(points[0])), (Vector(points[-1]), Vector(points[-1]) - Vector(points[-2])))):
        torus_along(f"{node}_DockingFlange_{end_index}", p, tangent, 1.08, 0.24, MATS["titanium"], col, "BOTH")
        torus_along(f"{node}_DockingGasket_{end_index}", p, tangent, 0.95, 0.06, MATS["red"], col, "HIGH")
    return tube


def build_tubes() -> None:
    transport_tube("T01", [(-16, -8, 9.5), (-16, -1.0, 9.5), (-15.3, 3.3, 9.5), (-11, 4, 9.5), (4, 4, 9.5)], 32.0)
    transport_tube("T02", [(13, 4, 12.5), (13, 12, 12.5)], 8.0)
    bsdf = MATS["blue"].node_tree.nodes.get("Principled BSDF")
    strength = bsdf.inputs["Emission Strength"]
    for frame, value in ((1, 2.0), (18, 11.0), (36, 2.0), (54, 11.0), (72, 2.0)):
        strength.default_value = value
        strength.keyframe_insert("default_value", frame=frame)
    if MATS["blue"].node_tree.animation_data and MATS["blue"].node_tree.animation_data.action:
        MATS["blue"].node_tree.animation_data.action.name = "ANIM_05_Accelerator_Coil_Pulses"


def elevator(node: str, xy: tuple[float, float], bottom: float, top: float) -> None:
    col = COLLECTIONS["04_LIFTS"]
    x, y = xy
    mid = (bottom + top) * 0.5
    height = top - bottom + 2.2
    shell = add_cylinder(f"{node}_SafetyGlass", (x, y, mid), 1.55, height, MATS["glass"], col, vertices=48, role="lift_shaft")
    shell["travel_m"] = top - bottom
    for i, (dx, dy) in enumerate(((1.12, 0), (-1.12, 0), (0, 1.12), (0, -1.12))):
        add_box(f"{node}_Guide_{i}", (x + dx, y + dy, mid), (0.16, 0.16, height), MATS["steel"], col, lod="BOTH", edge=0.035, role="lift_guide")
    frame_points = []
    for i in range(8):
        a = math.tau * i / 8
        px, py = x + 1.72 * math.cos(a), y + 1.72 * math.sin(a)
        frame_points.append((px, py))
        add_box(
            f"{node}_OuterFrame_{i:02d}", (px, py, mid), (0.18, 0.18, height + 0.65),
            MATS["titanium"], col, a, "HIGH", 0.04, "lift_outer_frame"
        )
    brace_levels = max(2, int((top - bottom) / 1.4) + 1)
    for level in range(brace_levels + 1):
        bz = bottom - 0.55 + (top - bottom + 1.10) * level / brace_levels
        add_torus(f"{node}_FrameRing_{level:02d}", (x, y, bz), 1.72, 0.09, MATS["bronze"], col, lod="HIGH", major_segments=48)
        for i in range(0, 8, 2):
            p0 = Vector((frame_points[i][0], frame_points[i][1], bz - 0.50))
            p1 = Vector((frame_points[(i + 1) % 8][0], frame_points[(i + 1) % 8][1], bz + 0.50))
            beam_between(f"{node}_DiagonalBrace_{level:02d}_{i:02d}", p0, p1, 0.07, MATS["steel"], col)
    coil_z = bottom - 0.35
    index = 0
    while coil_z <= top + 0.45:
        add_torus(f"{node}_Coil_{index:02d}", (x, y, coil_z), 1.26, 0.08, MATS["blue"], col, lod="HIGH", major_segments=32)
        coil_z += 1.1
        index += 1
    for z, suffix in ((bottom - 0.45, "LowerLock"), (top + 0.45, "UpperLock")):
        add_torus(f"{node}_{suffix}", (x, y, z), 1.44, 0.18, MATS["bronze"], col, major_segments=48)
        add_cylinder(f"{node}_{suffix}Dock", (x, y, z - 0.18 if z < mid else z + 0.18), 1.72, 0.24, MATS["steel"], col, vertices=48, lod="HIGH", role="landing_dock")
        for i in range(4):
            a = math.tau * i / 4
            px, py = x + 1.62 * math.cos(a), y + 1.62 * math.sin(a)
            add_box(
                f"{node}_{suffix}Clamp_{i}", (px, py, z), (0.48, 0.32, 0.44),
                MATS["hazard"], col, a, "HIGH", 0.06, "emergency_lock"
            )
    root = add_empty(f"{node}_PLATFORM_PIVOT", (x, y, bottom), col, "kinematic_pivot")
    parts = [
        add_cylinder(f"{node}_Platform", (0, 0, 0), 1.18, 0.24, MATS["titanium"], col, vertices=48, role="lift_platform"),
        add_cylinder(f"{node}_PlatformLower", (0, 0, -0.18), 1.02, 0.20, MATS["steel"], col, vertices=48, role="lift_platform"),
        add_torus(f"{node}_PlatformEnergy", (0, 0, 0.14), 0.88, 0.07, MATS["blue"], col, lod="HIGH", major_segments=40),
        add_torus(f"{node}_PlatformMagnet", (0, 0, -0.27), 0.78, 0.10, MATS["copper"], col, lod="HIGH", major_segments=40),
    ]
    for part in parts:
        part.parent = root
        part.location = (0, 0, 0)
    root["travel_m"] = top - bottom
    root["bottom_center_z_m"] = bottom
    root["top_center_z_m"] = top
    root.location = (x, y, bottom)
    root.keyframe_insert("location", frame=1)
    root.location.z = top
    root.keyframe_insert("location", frame=90)
    root.keyframe_insert("location", frame=145)
    root.location.z = bottom
    root.keyframe_insert("location", frame=235)
    if root.animation_data and root.animation_data.action:
        root.animation_data.action.name = f"ANIM_{'03' if node == 'L01' else '04'}_Magnetic_Lift_{node}"


def build_lifts() -> None:
    elevator("L01", (-16, -8), 4.5, 9.5)
    elevator("L02", (13, 4), 9.5, 12.5)


def gear(name: str, loc: tuple[float, float, float], radius: float, teeth: int, col: bpy.types.Collection, lod: str = "BOTH") -> bpy.types.Object:
    root = add_empty(f"{name}_PIVOT", loc, col, "rotational_pivot")
    wheel = add_torus(f"{name}_Rim", (0, 0, 0), radius * 0.74, radius * 0.20, MATS["bronze"], col, rot=(math.pi / 2, 0, 0), lod=lod, major_segments=48)
    wheel.parent = root
    wheel.location = (0, 0, 0)
    for i in range(teeth):
        a = math.tau * i / teeth
        tooth = add_box(f"{name}_Tooth_{i:02d}", (0, 0, 0), (radius * 0.26, 0.30, radius * 0.13), MATS["bronze"], col, lod="HIGH", edge=0.035)
        tooth.parent = root
        tooth.location = (radius * math.cos(a), 0, radius * math.sin(a))
        tooth.rotation_euler[1] = -a
    root["teeth"] = teeth
    return root


def build_mechanics() -> None:
    col = COLLECTIONS["05_MECHANICS"]
    center = (-2, -3, 7)
    # Two service decks surround the rotor while preserving the full 7 m
    # flywheel sweep between them.
    for suffix, y in (("South", -6.0), ("North", 0.0)):
        service = add_box(
            f"M01_ServiceDeck_{suffix}", (-2, y, 3.70), (12.0, 2.7, 0.60),
            MATS["dark"], col, lod="BOTH", edge=0.11, role="service_platform"
        )
        service["clear_of_flywheel_sweep"] = True
        add_box(f"M01_ServiceBlue_{suffix}", (-2, y - 1.31, 3.75), (11.2, 0.07, 0.13), MATS["blue_soft"], col, lod="HIGH", edge=0.02)
        support_tower(f"M01_{suffix}_SupportA", Vector((-6.2, y)), 3.4, 0.52)
        support_tower(f"M01_{suffix}_SupportB", Vector((2.2, y)), 3.4, 0.52)
    root = add_empty("M01_FLYWHEEL_PIVOT", center, col, "rotational_pivot")
    root["axis"] = "Y"
    root["diameter_m"] = 7.0
    rim = add_torus("M01_Rotor_Rim", (0, 0, 0), 3.0, 0.50, MATS["bronze"], col, rot=(math.pi / 2, 0, 0), major_segments=72)
    rim.parent = root
    rim.location = (0, 0, 0)
    for side_index, local_y in enumerate((-0.72, 0.72)):
        side_rim = add_torus(
            f"M01_InertiaRim_{side_index}", (0, 0, 0), 2.74, 0.22,
            MATS["titanium"], col, rot=(math.pi / 2, 0, 0), lod="HIGH", major_segments=72
        )
        side_rim.parent = root
        side_rim.location = (0, local_y, 0)
    hub = add_cylinder("M01_Hub", (0, 0, 0), 0.72, 2.2, MATS["titanium"], col, rot=(math.pi / 2, 0, 0), vertices=48)
    hub.parent = root
    hub.location = (0, 0, 0)
    rotor_root = add_empty("M01_ROTOR_CORE_PIVOT", center, col, "rotational_pivot")
    rotor_core = add_torus("M01_Rotor_Core", (0, 0, 0), 1.38, 0.22, MATS["blue"], col, rot=(math.pi / 2, 0, 0), lod="HIGH", major_segments=56)
    rotor_core.parent = rotor_root
    rotor_core.location = (0, 0, 0)
    for i in range(8):
        a = math.tau * i / 8
        spoke = add_box(f"M01_Spoke_{i:02d}", (0, 0, 0), (2.55, 0.34, 0.34), MATS["steel"], col, rot_z=a, lod="HIGH", edge=0.08)
        spoke.parent = root
        spoke.location = (1.55 * math.cos(a), 0, 1.55 * math.sin(a))
        spoke.rotation_euler = (0, a, 0)
    # Shaft, bearings, motor, cooling fins and guard.
    add_cylinder("M01_MainShaft", (-2, -3, 7), 0.32, 5.4, MATS["titanium"], col, rot=(math.pi / 2, 0, 0), vertices=40, role="mechanical_shaft")
    for y in (-5.25, -0.75):
        add_box(f"M01_BearingPedestal_{y}", (-2, y, 5.75), (1.7, 0.7, 2.5), MATS["steel"], col, edge=0.13, role="bearing_support")
        add_torus(f"M01_Bearing_{y}", (-2, y, 7), 0.62, 0.18, MATS["bronze"], col, rot=(math.pi / 2, 0, 0), major_segments=40)
    motor = add_cylinder("M01_ElectricMotor", (-2, -6.2, 7), 1.10, 1.8, MATS["dark"], col, rot=(math.pi / 2, 0, 0), vertices=48, role="electric_motor")
    for i in range(12):
        a = math.tau * i / 12
        add_box(f"M01_CoolingFin_{i:02d}", (-2 + 1.10 * math.cos(a), -6.2, 7 + 1.10 * math.sin(a)), (0.08, 1.65, 0.34), MATS["titanium"], col, lod="HIGH", edge=0.02)
    gear_a = gear("M01_GearA", (1.5, -3, 6.4), 1.35, 18, col)
    gear_b = gear("M01_GearB", (3.75, -3, 5.8), 0.92, 12, col)
    gear_c = gear("M01_GearC", (4.95, -3, 7.35), 0.72, 14, col, "HIGH")
    gear_d = gear("M01_GearD", (5.95, -3, 8.30), 0.54, 10, col, "HIGH")
    # Layered reduction gearbox and visible bearing cartridges.
    add_box("M01_GearboxHousing", (4.25, -3.75, 6.65), (4.3, 1.25, 3.25), MATS["dark"], col, lod="BOTH", edge=0.18, role="gearbox_housing")
    add_box("M01_GearboxServiceCover", (4.25, -4.40, 6.65), (3.45, 0.10, 2.30), MATS["titanium"], col, lod="HIGH", edge=0.08, role="service_cover")
    for i in range(10):
        px = 2.75 + (i % 5) * 0.75
        pz = 5.72 + (i // 5) * 1.82
        add_cylinder(f"M01_GearboxBolt_{i:02d}", (px, -4.50, pz), 0.10, 0.18, MATS["bronze"], col, rot=(math.pi / 2, 0, 0), vertices=12, lod="HIGH")
    add_box("M01_GearboxStatus", (4.25, -4.50, 6.65), (1.10, 0.05, 0.18), MATS["blue"], col, lod="HIGH", edge=0.02)
    # Animation 01 and 02: flywheel start/stop plus secondary reverse gearing.
    root.rotation_mode = "XYZ"
    for frame, angle in ((1, 0.0), (45, 0.0), (180, math.tau * 6.0), (240, math.tau * 6.0), (300, math.tau * 7.0)):
        root.rotation_euler[1] = angle
        root.keyframe_insert("rotation_euler", frame=frame, index=1)
    if root.animation_data and root.animation_data.action:
        root.animation_data.action.name = "ANIM_01_Main_Flywheel_Rotation_Start_Stop"
    for frame, angle in ((1, 0.0), (35, 0.0), (120, math.tau * 9.0), (215, math.tau * 20.0), (270, math.tau * 20.0)):
        rotor_root.rotation_euler[1] = angle
        rotor_root.keyframe_insert("rotation_euler", frame=frame, index=1)
    if rotor_root.animation_data and rotor_root.animation_data.action:
        rotor_root.animation_data.action.name = "ANIM_02_Rotor_Start_Stop"
    for pivot, sign, ratio in ((gear_a, 1, 1.0), (gear_b, -1, 1.5), (gear_c, 1, 2.1), (gear_d, -1, 2.9)):
        for frame, angle in ((1, 0.0), (180, sign * math.tau * 6 * ratio), (300, sign * math.tau * 8 * ratio)):
            pivot.rotation_euler[1] = angle
            pivot.keyframe_insert("rotation_euler", frame=frame, index=1)
    if gear_b.animation_data and gear_b.animation_data.action:
        gear_b.animation_data.action.name = "ANIM_08_Secondary_Mechanisms"
    # Guard hoops and cable paths.
    for y in (-3.75, -2.25):
        add_torus(f"M01_GuardHoop_{y}", (-2, y, 7), 3.55, 0.10, MATS["titanium"], col, rot=(math.pi / 2, 0, 0), lod="HIGH", major_segments=64)
    curve_object("M01_PowerCable", [(-2, -6.8, 6.5), (-5, -8, 5.2), (-8, -6, 4.3)], 0.10, MATS["black"], col, "HIGH", "technical_cable")
    curve_object("M01_CoolantFeed", [(-2, -6.9, 7.8), (-0.5, -8.4, 6.8), (3.8, -6.5, 5.2)], 0.13, MATS["copper"], col, "HIGH", "coolant_pipe")
    curve_object("M01_CoolantReturn", [(-2, -6.9, 6.9), (-0.2, -8.9, 6.0), (4.3, -6.7, 4.8)], 0.11, MATS["blue_soft"], col, "HIGH", "coolant_pipe")
    curve_object("M01_DataTrunk_A", [(-9, -5.8, 4.5), (-11, -2, 5.2), (-9, 3, 6.1), (-5, 5, 8.8)], 0.075, MATS["blue_soft"], col, "HIGH", "data_cable")
    curve_object("M01_DataTrunk_B", [(5.8, -5.5, 4.8), (8, -2, 6.2), (10, 1, 8.8), (13, 4, 10.4)], 0.085, MATS["copper"], col, "HIGH", "power_cable")
    curve_object("M01_ServiceHose", [(-6.5, 0.8, 4.8), (-5, 3.2, 5.6), (-2, 3.7, 7.1), (2.8, 1.2, 8.3)], 0.105, MATS["black"], col, "HIGH", "service_hose")
    # Capacitor banks and control manifold turn M01 into the station's visual heart.
    for bank in range(6):
        bx = -7.25 + (bank % 3) * 1.15
        by = -5.85 + (bank // 3) * 5.75
        add_box(f"M01_Capacitor_{bank:02d}", (bx, by, 5.25), (0.82, 0.72, 2.45), MATS["steel"], col, lod="HIGH", edge=0.12, role="energy_capacitor")
        add_box(f"M01_CapacitorGlow_{bank:02d}", (bx, by - 0.37, 5.35), (0.42, 0.05, 1.62), MATS["blue_soft"], col, lod="HIGH", edge=0.02)
        add_torus(f"M01_CapacitorCollar_{bank:02d}", (bx, by, 6.47), 0.31, 0.08, MATS["bronze"], col, lod="HIGH", major_segments=24)
    manifold = add_box("M01_ControlManifold", (-2, 1.05, 5.12), (5.6, 0.88, 1.65), MATS["dark"], col, lod="HIGH", edge=0.16, role="control_manifold")
    for i in range(7):
        add_box(f"M01_ManifoldIndicator_{i:02d}", (-4.35 + i * 0.78, 0.59, 5.20), (0.34, 0.05, 0.18), MATS["blue"] if i < 5 else MATS["red"], col, lod="HIGH", edge=0.02)


def barrier(node: str, loc: tuple[float, float, float], rot_z: float) -> None:
    col = COLLECTIONS["07_GAMEPLAY"]
    field = add_box(f"{node}_EnergyField", loc, (2.55, 0.05, 1.35), MATS["red"], col, rot_z, "BOTH", 0.01, "energy_barrier")
    pivot = add_empty(f"{node}_BARRIER_PIVOT", loc, col, "kinematic_pivot")
    field.parent = pivot
    field.matrix_parent_inverse = pivot.matrix_world.inverted()
    for frame, zscale in ((1, 1.0), (50, 1.0), (70, 0.04), (140, 0.04), (160, 1.0)):
        pivot.scale.z = zscale
        pivot.keyframe_insert("scale", frame=frame, index=2)
    if pivot.animation_data and pivot.animation_data.action:
        pivot.animation_data.action.name = "ANIM_06_Power_Barriers"
    for side in (-1, 1):
        add_box(f"{node}_Post_{side}", (loc[0], loc[1] + side * 1.36, loc[2]), (0.30, 0.30, 1.85), MATS["bronze"], col, rot_z, "BOTH", 0.06)


def build_gameplay() -> None:
    barrier("G01", (-12, -8, 4.85), 0.0)
    barrier("G02", (8, 4, 9.85), math.pi / 2)
    col = COLLECTIONS["07_GAMEPLAY"]
    add_torus("E01_Accelerator", (3, -9, 4.10), 1.20, 0.15, MATS["blue"], col, lod="BOTH")
    for i in range(7):
        a = math.tau * i / 7
        add_cylinder(f"H01_Spike_{i:02d}", (3 + 1.15 * math.cos(a), -13 + 1.15 * math.sin(a), 4.55), 0.16, 1.1, MATS["red"], col, vertices=12, lod="HIGH", role="hazard")
    # Finish mechanism with separately animated rings.
    finish_root = add_empty("P02_FINISH_PIVOT", (17, 12, 12.0), col, "rotational_pivot")
    add_cylinder("P02_GoldenReceiver", (17, 12, 12.22), 0.82, 0.42, MATS["gold"], col, vertices=64, role="goal_receiver")
    add_cylinder("P02_ReceiverPedestal", (17, 12, 11.88), 1.22, 0.46, MATS["titanium"], col, vertices=64, role="goal_receiver")
    add_torus("P02_ReceiverCoil", (17, 12, 12.47), 0.62, 0.10, MATS["copper"], col, lod="HIGH", major_segments=48)
    for i in range(8):
        a = math.tau * i / 8
        inner = Vector((17 + 0.92 * math.cos(a), 12 + 0.92 * math.sin(a), 12.05))
        outer = Vector((17 + 2.15 * math.cos(a), 12 + 2.15 * math.sin(a), 12.05))
        beam_between(f"P02_EnergyChannel_{i:02d}", inner, outer, 0.11, MATS["gold"] if i % 2 == 0 else MATS["blue"], col)
    for i in range(4):
        a = math.tau * i / 4 + math.pi / 4
        px, py = 17 + 2.45 * math.cos(a), 12 + 2.45 * math.sin(a)
        add_box(f"P02_EnergyPylon_{i:02d}", (px, py, 13.05), (0.42, 0.42, 2.25), MATS["bronze"], col, a, "HIGH", 0.09, "finish_energy_pylon")
        add_sphere(f"P02_PylonNode_{i:02d}", (px, py, 14.28), 0.22, MATS["gold"], col, lod="HIGH", segments=24)
    add_torus("P02_CeremonialHalo", (17, 12, 14.1), 2.25, 0.13, MATS["gold"], col, rot=(math.pi / 2, 0, 0), lod="HIGH", major_segments=72)
    rings = []
    for i, radius in enumerate((1.20, 1.65, 2.05)):
        ring = add_torus(f"P02_ActivationRing_{i}", (17, 12, 12.52 + i * 0.08), radius, 0.08, MATS["gold"] if i == 0 else MATS["blue"], col, lod="BOTH", major_segments=64)
        rings.append(ring)
    for i, ring in enumerate(rings):
        ring.rotation_mode = "XYZ"
        ring.rotation_euler[0] = i * 0.18
        ring.keyframe_insert("rotation_euler", frame=1)
        ring.rotation_euler[2] = math.tau * (2 + i)
        ring.rotation_euler[0] += (-1 if i % 2 else 1) * 0.55
        ring.keyframe_insert("rotation_euler", frame=300)
    if rings[0].animation_data and rings[0].animation_data.action:
        rings[0].animation_data.action.name = "ANIM_09_Finish_Activation"
    for i in range(4):
        a = math.tau * i / 4
        node = add_sphere(f"P02_OrbitNode_{i:02d}", (0, 0, 0), 0.16, MATS["gold"], col, lod="HIGH", segments=20)
        node.parent = finish_root
        node.location = (1.55 * math.cos(a), 1.55 * math.sin(a), 1.18 + 0.12 * (i % 2))
    finish_root.rotation_euler[2] = 0.0
    finish_root.keyframe_insert("rotation_euler", frame=1, index=2)
    finish_root.rotation_euler[2] = math.tau * 2.0
    finish_root.keyframe_insert("rotation_euler", frame=300, index=2)
    # Demonstration ball follows the declared route; no claim of game physics.
    ball = add_sphere("DEMO_ROUTE_BALL", (-17, -14, 4.5), 0.5, MATS["ball"], col, lod="BOTH", segments=64)
    ball["animation_only"] = True
    waypoints = [
        (1, (-17, -14, 4.5)), (30, (-12, -14, 4.5)), (55, (-12, -8, 4.5)),
        (72, (-16, -8, 4.5)), (102, (-16, -8, 9.5)), (132, (-16, 3.5, 9.5)),
        (165, (4, 4, 9.5)), (195, (13, 4, 9.5)), (220, (13, 4, 12.5)),
        (255, (13, 12, 12.5)), (285, (17, 12, 12.5)),
    ]
    for frame, position in waypoints:
        ball.location = position
        ball.keyframe_insert("location", frame=frame)
    if ball.animation_data and ball.animation_data.action:
        ball.animation_data.action.name = "ANIM_10_Demonstration_Ball_Route"


def build_environment() -> None:
    col = COLLECTIONS["08_ENVIRONMENT"]
    planet_center = (52, 132, -72)
    planet = add_sphere("ENV_Planet", planet_center, 44.0, MATS["planet"], col, lod="HIGH", segments=96)
    planet["level06_export"] = False
    atmosphere = add_sphere("ENV_Atmosphere", planet_center, 45.2, MATS["atmosphere"], col, lod="HIGH", segments=96)
    atmosphere["level06_export"] = False
    clouds = add_sphere("ENV_CloudLayer", planet_center, 44.45, MATS["cloud"], col, lod="HIGH", segments=128)
    clouds["level06_export"] = False
    # Cloud bands are independent toroidal layers.
    for i, radius in enumerate((39.0, 41.0, 42.5)):
        band = add_torus(f"ENV_CloudBand_{i}", planet_center, radius, 0.55, MATS["atmosphere"], col, rot=(0.22 + i * 0.10, 0.0, 0.0), lod="HIGH", major_segments=96)
        band["level06_export"] = False
    for i in range(26):
        a = (i * 2.399963) % math.tau
        r = 31 + (i % 5) * 4.2
        z = -8 + (i % 9) * 4.7
        x, y = r * math.cos(a), r * math.sin(a)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.55 + (i % 4) * 0.23, location=(x, y, z))
        asteroid = bpy.context.object
        asteroid.name = f"ENV_Asteroid_{i:02d}"
        asteroid.scale = (1.0, 0.72 + (i % 3) * 0.14, 0.58 + (i % 4) * 0.11)
        assign(asteroid, MATS["asteroid"])
        move_to(asteroid, col)
        tag(asteroid, "HIGH", False, "environment")
        if i % 4 == 0:
            crater = add_torus(
                f"ENV_AsteroidCrater_{i:02d}", (x, y, z + 0.34), 0.28 + (i % 3) * 0.07, 0.055,
                MATS["black"], col, rot=(0.4, 0.2, a), lod="HIGH", major_segments=18
            )
            crater["level06_export"] = False
    def distant_station(name: str, loc: tuple[float, float, float], radius: float, rot: tuple[float, float, float]) -> None:
        ring = add_torus(name, loc, radius, radius * 0.055, MATS["steel"], col, rot=rot, lod="HIGH", major_segments=72)
        ring["level06_export"] = False
        glow = add_torus(f"{name}_Energy", loc, radius * 0.86, radius * 0.015, MATS["blue_soft"], col, rot=rot, lod="HIGH", major_segments=72)
        glow["level06_export"] = False
        core = add_cylinder(f"{name}_Core", loc, radius * 0.18, radius * 0.65, MATS["titanium"], col, rot=rot, vertices=32, lod="HIGH")
        core["level06_export"] = False
        for side in (-1.0, 1.0):
            panel = add_box(
                f"{name}_Solar_{int(side)}", (loc[0] + side * radius * 1.18, loc[1], loc[2]),
                (radius * 0.62, 0.08, radius * 0.34), MATS["blue_soft"], col, rot_z=rot[2], lod="HIGH", edge=0.02
            )
            panel["level06_export"] = False
    distant_station("ENV_DistantStation_A", (-44, 32, 11), 6.5, (0.65, 0.2, 0.4))
    distant_station("ENV_DistantStation_B", (46, 48, 24), 3.2, (1.1, 0.1, -0.5))
    distant_station("ENV_DistantStation_C", (-18, 78, -2), 2.2, (0.3, 0.8, 0.1))


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_camera(name: str, loc: tuple[float, float, float], target: tuple[float, float, float], lens: float) -> bpy.types.Object:
    data = bpy.data.cameras.new(name)
    data.lens = lens
    data.sensor_width = 36
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    COLLECTIONS["09_CAMERAS_LIGHTS"].objects.link(obj)
    look_at(obj, target)
    obj["level06_export"] = False
    OBJECTS[name] = obj
    return obj


def add_light(name: str, kind: str, loc: tuple[float, float, float], energy: float, color: tuple[float, float, float], size: float = 5.0) -> None:
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.shape = "DISK"
        data.size = size
    if kind == "SUN":
        data.angle = math.radians(5.0)
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    COLLECTIONS["09_CAMERAS_LIGHTS"].objects.link(obj)
    obj["level06_export"] = False
    if kind != "POINT":
        look_at(obj, (0, 0, 6))


def cameras_lights() -> list[bpy.types.Object]:
    cams = [
        add_camera("Cam_01_Station_Overview", (-54, -60, 51), (0, 0, 7), 52),
        add_camera("Cam_02_Reverse_Overview", (55, 49, 43), (0, 0, 7), 54),
        add_camera("Cam_03_Top", (0, 0, 72), (0, 0, 5), 53),
        add_camera("Cam_04_Start", (-28, -25, 14), (-14, -10, 5.2), 58),
        add_camera("Cam_05_Central_Mechanism", (-16, -20, 14), (-2, -3, 7), 62),
        add_camera("Cam_06_Magnetic_Lifts", (-34, -27, 17), (-16, -8, 7.5), 58),
        add_camera("Cam_07_Transparent_Tubes", (-32, 12, 21), (-4, 3, 10), 56),
        add_camera("Cam_08_Engineering_Close", (-38, -34, 15), (-20, -18, 5.5), 62),
        add_camera("Cam_09_Finish", (30, 26, 22), (17, 12, 12), 64),
        add_camera("Cam_10_Artistic", (42, -52, 31), (1, 0, 8), 58),
    ]
    add_light("Orbital_Sun", "SUN", (-30, -50, 70), 2.2, (0.68, 0.80, 1.0), 16)
    add_light("Key_Sun", "AREA", (-16, -22, 42), 11000, (0.72, 0.82, 1.0), 16)
    add_light("Warm_Rim", "AREA", (30, 18, 26), 8500, (1.0, 0.42, 0.12), 13)
    add_light("Planet_Fill", "AREA", (-28, 32, 10), 6500, (0.08, 0.24, 0.65), 18)
    for i, loc in enumerate(((-17, -14, 7), (-2, -3, 12), (13, 4, 16), (17, 12, 16))):
        add_light(f"Local_Blue_{i}", "POINT", loc, 950, (0.02, 0.22, 1.0), 2)
    return cams


def world_and_render(engine_arg: str, preview: bool) -> str:
    scene = bpy.context.scene
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.003, 0.008, 0.025, 1)
    bg.inputs["Strength"].default_value = 0.16
    texcoord = scene.world.node_tree.nodes.new("ShaderNodeTexCoord")
    noise = scene.world.node_tree.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 330.0
    noise.inputs["Detail"].default_value = 2.0
    ramp = scene.world.node_tree.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.78
    ramp.color_ramp.elements[0].color = (0.001, 0.004, 0.015, 1)
    ramp.color_ramp.elements[1].position = 0.84
    ramp.color_ramp.elements[1].color = (0.55, 0.75, 1.0, 1)
    scene.world.node_tree.links.new(texcoord.outputs["Normal"], noise.inputs["Vector"])
    scene.world.node_tree.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    scene.world.node_tree.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    scene.render.film_transparent = False
    scene.render.resolution_percentage = 100
    scene.render.resolution_x = 960 if preview else 1920
    scene.render.resolution_y = 540 if preview else 1080
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = 300
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 1.05
    selected_engine = "BLENDER_EEVEE_NEXT"
    if engine_arg != "EEVEE":
        try:
            scene.render.engine = "CYCLES"
            prefs = bpy.context.preferences.addons["cycles"].preferences
            for backend in ("OPTIX", "CUDA"):
                try:
                    prefs.compute_device_type = backend
                    prefs.get_devices()
                    gpu_devices = [d for d in prefs.devices if d.type != "CPU"]
                    if gpu_devices:
                        for device in prefs.devices:
                            device.use = device.type != "CPU"
                        scene.cycles.device = "GPU"
                        selected_engine = f"CYCLES_{backend}"
                        break
                except Exception:
                    continue
            if selected_engine.startswith("CYCLES"):
                scene.cycles.samples = 20 if preview else 40
                scene.cycles.use_denoising = True
                scene.cycles.use_adaptive_sampling = True
            elif engine_arg == "CYCLES":
                selected_engine = "CYCLES_CPU"
                scene.cycles.samples = 12 if preview else 24
            else:
                scene.render.engine = "BLENDER_EEVEE_NEXT"
        except Exception as exc:
            print(f"Cycles unavailable, falling back to Eevee: {exc}")
            scene.render.engine = "BLENDER_EEVEE_NEXT"
    else:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    if scene.render.engine == "BLENDER_EEVEE_NEXT":
        scene.render.image_settings.color_depth = "8"
    return selected_engine


def export_glb(path: Path, lod: str) -> None:
    scaled_images: list[bpy.types.Image] = []
    if lod == "LOW":
        for img in bpy.data.images:
            if img.source == "FILE" and max(img.size) > 512:
                img.scale(512, 512)
                scaled_images.append(img)
    bpy.ops.object.select_all(action="DESELECT")
    count = 0
    for obj in bpy.context.scene.objects:
        should = obj.get("level06_export", False) and obj.type in {"MESH", "CURVE", "EMPTY"}
        obj_lod = obj.get("level06_lod", "BOTH")
        should = should and (lod == "HIGH" or obj_lod == "BOTH")
        obj.select_set(bool(should))
        if should:
            count += 1
    path.parent.mkdir(parents=True, exist_ok=True)
    kwargs = {
        "filepath": str(path),
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_yup": True,
        "export_animations": True,
        "export_materials": "EXPORT",
    }
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    kwargs = {k: v for k, v in kwargs.items() if k in props}
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    finally:
        for img in scaled_images:
            try:
                img.reload()
            except RuntimeError:
                pass
    print(f"Exported {lod}: {count} objects -> {path}")


def mesh_stats() -> tuple[int, int, int]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    meshes = 0
    vertices = 0
    triangles = 0
    for obj in bpy.context.scene.objects:
        if obj.type not in {"MESH", "CURVE"} or not obj.get("level06_export", False):
            continue
        eval_obj = obj.evaluated_get(depsgraph)
        mesh = eval_obj.to_mesh()
        if mesh:
            mesh.calc_loop_triangles()
            meshes += 1
            vertices += len(mesh.vertices)
            triangles += len(mesh.loop_triangles)
            eval_obj.to_mesh_clear()
    return meshes, vertices, triangles


def audit(engine: str) -> dict:
    meshes, vertices, triangles = mesh_stats()
    actions = sorted(a.name for a in bpy.data.actions)
    report = {
        "units": "metres",
        "engine_for_renders": engine,
        "dimensions": {
            "ring_outer_diameter": RING_OD,
            "ring_inner_diameter": RING_ID,
            "ring_radial_width": RING_R1 - RING_R0,
            "ball_diameter": BALL_D,
            "bridge_width": BRIDGE_W,
            "tube_outer_diameter": TUBE_OD,
            "tube_inner_diameter": TUBE_ID,
            "tube_radial_clearance": (TUBE_ID - BALL_D) / 2,
            "levels_surface_z": [4.0, 9.0, 12.0],
            "lift_L01_travel": 5.0,
            "lift_L02_travel": 3.0,
            "flywheel_M01_diameter": 7.0,
        },
        "checks": {
            "ring_width_matches_blueprint": abs((RING_OD - RING_ID) / 2 - 3.6) < 1e-6,
            "tube_clears_ball": TUBE_ID > BALL_D,
            "bridge_wider_than_ball": BRIDGE_W > BALL_D,
            "rail_height_m": 0.8,
            "route_nodes_connected_by_design": True,
            "godot_physics_tested": False,
        },
        "engineering_adjustments": [
            "T01 keeps blueprint endpoints and nominal 32 m orthogonal run; the visible Bezier elbow shortens the exact sampled centerline slightly.",
            "Transparent shells are visual meshes; inner guide rails and diameter metadata are authored for later collision design.",
            "No structural-strength or power-consumption claims are made; this is game-device engineering geometry.",
        ],
        "object_count": len(bpy.context.scene.objects),
        "export_mesh_count": meshes,
        "evaluated_vertices": vertices,
        "evaluated_triangles": triangles,
        "actions": actions,
        "collections": sorted(COLLECTIONS),
    }
    AUDIT_PATH.parent.mkdir(parents=True, exist_ok=True)
    AUDIT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def render_views(cameras: list[bpy.types.Object], preview: bool) -> None:
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    use = cameras[:1] if preview else cameras
    scene = bpy.context.scene
    scene.frame_set(1)
    for camera in use:
        scene.camera = camera
        scene.render.filepath = str(RENDER_DIR / f"{camera.name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"Rendered {scene.render.filepath}")


def main() -> None:
    args = parse_args()
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.context.scene.unit_settings.length_unit = "METERS"
    for name in (
        "01_RING", "02_TRACKS", "03_TRANSPORT_TUBES", "04_LIFTS", "05_MECHANICS",
        "06_SUPPORTS", "07_GAMEPLAY", "08_ENVIRONMENT", "09_CAMERAS_LIGHTS",
    ):
        collection(name)
    materials()
    build_ring()
    build_tracks()
    build_tubes()
    build_lifts()
    build_mechanics()
    build_gameplay()
    build_environment()
    cams = cameras_lights()
    engine = world_and_render(args.engine, args.preview)
    scene = bpy.context.scene
    scene["level06_blueprint_revision"] = "ORB-06 REV 0.1"
    scene["level06_units"] = "1 Blender unit = 1 metre"
    scene["level06_reference_image"] = "docs/reference/level06/level06_visual_reference.jpg"
    scene["level06_engineering_status"] = "Geometry audited; Godot physics intentionally not tested"
    scene["level06_render_engine"] = engine
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    export_glb(HIGH_GLB, "HIGH")
    export_glb(LOW_GLB, "LOW")
    report = audit(engine)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    if not args.skip_renders:
        render_views(cams, args.preview)
    print(json.dumps({"blend": str(BLEND_PATH), "high": str(HIGH_GLB), "low": str(LOW_GLB), "audit": report}, ensure_ascii=False))


if __name__ == "__main__":
    main()
