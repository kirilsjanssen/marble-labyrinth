"""Level 05 MOBILE export: Blender (mobile variant) -> Godot 4 GL Compatibility.

1) blender -b --factory-startup -P tools/blender/build_level05.py -- --mobile
2) python -I tools/textures/make_level05_mobile_textures.py
3) blender -b --factory-startup assets/blender/level05_alpine_watermill_mobile.blend \
       -P tools/blender/export_level05_mobile.py

What it does (the HQ v4 .blend is never touched):
  * 40 v4 materials -> 15 mobile materials; each role's colour grade and the
    per-piece l05_rand jitter become vertex colours (tint table from step 2),
    multiplied by a Cycles AO bake on the static geometry;
  * static architecture / dressing / terrain merged per area (draw calls);
    decks, bridges and every mechanism stay separate nodes with their own
    pivots and custom properties (gear axes, roles) as glTF extras;
  * conifers become MultiMesh data (transforms per prototype) + 1 proto mesh
    each; distant peaks are replaced by the rendered panorama sky;
  * analytic box colliders from the layout data (decks, rails, walls with
    arch openings, flumes, lift tower, millhouse) + per-mechanism local boxes;
  * GLB with embedded textures, plus JSON for vegetation, colliders, scene.
Coordinates in the JSON files are already Godot's (Y up): (x, y, z)_blender
-> (x, z, -y)_godot, metres.
"""
import json
import math
import os
import sys
import time

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
import build_level05 as L5  # noqa: E402  (layout constants only; main() is not run)

OUT = os.path.join(ROOT, "assets", "levels", "level05")
TEX = os.path.join(OUT, "textures_pbr")
MAP = json.load(open(os.path.join(OUT, "mobile_material_map.json"), encoding="utf-8"))
C = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))   # Blender -> Godot


def g_vec(v):
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def g_xform(m, local_converted=True):
    """Blender world matrix -> Godot Transform3D as [bx, by, bz, origin] columns.
    Meshes exported through glTF also have their local axes converted (C on
    the right); cameras and lights share Godot's local convention (-Z forward,
    +Y up), so only the world side is converted for them."""
    g = C @ m @ C.inverted() if local_converted else C @ m
    cols = [[round(g[r][c], 5) for r in range(3)] for c in range(3)]
    return cols + [[round(g[0][3], 4), round(g[1][3], 4), round(g[2][3], 4)]]


def in_tree(obj, root):
    def walk(col):
        return obj.name in col.objects or any(walk(c) for c in col.children)
    col = bpy.data.collections.get(root)
    return bool(col) and walk(col)


def stats(label):
    objs = [o for o in bpy.data.objects if o.type == "MESH" and not o.hide_render]
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    mats = {m.name for o in objs for m in o.data.materials if m}
    surfaces = sum(len({p.material_index for p in o.data.polygons}) for o in objs)
    return {"stage": label, "mesh_objects": len(objs), "unique_meshes": len({o.data.name for o in objs}),
            "triangles": tris, "materials": len(mats), "surfaces_draw_calls_upper_bound": surfaces}


# ------------------------------------------------------------ mobile mats --
GROUP_MATS = {}


def mobile_material(group):
    if group in GROUP_MATS:
        return GROUP_MATS[group]
    name = "M_" + "".join(p.capitalize() for p in group.split("_"))
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    textured = group in ("wood_beam", "wood_board", "stone", "rock", "meadow", "roof", "fir", "brass")
    if textured:
        def img(suffix, data):
            node = nt.nodes.new("ShaderNodeTexImage")
            node.image = bpy.data.images.load(os.path.join(TEX, "%s_%s" % (group, suffix)), check_existing=True)
            if data:
                node.image.colorspace_settings.name = "Non-Color"
            return node
        alb = img("albedo.jpg", False)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        next(s for s in mix.inputs if s.identifier == "Factor_Float").default_value = 1.0
        nt.links.new(alb.outputs["Color"], next(s for s in mix.inputs if s.identifier == "A_Color"))
        nt.links.new(col.outputs["Color"], next(s for s in mix.inputs if s.identifier == "B_Color"))
        nt.links.new(next(s for s in mix.outputs if s.identifier == "Result_Color"), bsdf.inputs["Base Color"])
        rough = img("rough.jpg", True)
        nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
        nrm = img("normal.png", True)
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        bsdf.inputs["Metallic"].default_value = 1.0 if group == "brass" else 0.0
    else:
        nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
        settings = {"painted": (0.0, 0.55), "iron": (1.0, 0.45), "glow": (0.0, 0.5), "water": (0.0, 0.05),
                    "fall_body": (0.0, 0.15), "fall_foam": (0.0, 0.4), "spray": (0.0, 0.5)}[group]
        bsdf.inputs["Metallic"].default_value, bsdf.inputs["Roughness"].default_value = settings
        if group == "glow":
            bsdf.inputs["Emission Color"].default_value = (1.0, 0.4, 0.08, 1.0)
            bsdf.inputs["Emission Strength"].default_value = 3.0
    GROUP_MATS[group] = mat
    return mat


def role_of(mat_name):
    base = mat_name.split(".")[0]
    if base in MAP["textured"]:
        return base, MAP["textured"][base]["group"]
    if base in MAP["flat"]:
        return base, MAP["flat"][base]["group"]
    return None, None


def remap_object(obj):
    """Assigns mobile materials and writes the tint into colour attribute Col."""
    mesh = obj.data
    if not mesh.materials:
        return
    old = [m.name if m else "" for m in mesh.materials]
    rnd = mesh.attributes.get("l05_rand")
    rvals = [0.5] * len(mesh.polygons)
    if rnd and rnd.domain == "FACE":
        rvals = [d.value for d in rnd.data]
    normal_m = obj.matrix_world.to_3x3()
    groups, colors = [], []
    for i, poly in enumerate(mesh.polygons):
        role, group = role_of(old[poly.material_index] if poly.material_index < len(old) else "")
        if group is None:
            role, group = "Plate_White", "painted"
        if role == "Rock_Moss" and (normal_m @ poly.normal).normalized().z > 0.72:
            role, group = "Meadow", "meadow"
        if role in MAP["textured"]:
            bins = MAP["textured"][role]["tint_bins"]
            colors.append(bins[min(len(bins) - 1, int(rvals[i] * len(bins)))])
        else:
            colors.append(MAP["flat"][role]["color"])
        groups.append(group)
    order = sorted(set(groups), key=groups.index)
    mesh.materials.clear()
    for g in order:
        mesh.materials.append(mobile_material(g))
    for i, poly in enumerate(mesh.polygons):
        poly.material_index = order.index(groups[i])
    attr = mesh.color_attributes.get("Col") or mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for i, poly in enumerate(mesh.polygons):
        c = colors[i]
        for li in poly.loop_indices:
            attr.data[li].color = (c[0], c[1], c[2], 1.0)
    mesh.color_attributes.active_color = attr
    mesh.color_attributes.render_color_index = list(mesh.color_attributes).index(attr)


# ------------------------------------------------------------- colliders --
def box(center, size, yaw=0.0, kind="static", tag=""):
    c = g_vec(center)
    return {"center": c, "size": [round(size[0], 4), round(size[2], 4), round(size[1], 4)], "yaw": round(yaw, 5), "kind": kind, "tag": tag}


def colliders(walls, flumes):
    out = []
    Z = {"floor": L5.DECK_T}
    for name, x0, x1, y0, y1, z, _m, openings, _zone in L5.DECKS:
        holes = [L5.WHEEL_PIT] if name == "M_Workshop" else []
        inlays = list(L5.INLAYS.get(name, ()))
        cuts = list(L5.CUTOUTS.get(name, ()))
        for rx0, rx1, ry0, ry1 in L5._rect_minus((x0, x1, y0, y1), holes + inlays + cuts):
            out.append(box(((rx0 + rx1) / 2, (ry0 + ry1) / 2, z - Z["floor"] / 2), (rx1 - rx0, ry1 - ry0, Z["floor"]), tag=name + ":floor"))
        for rx0, rx1, ry0, ry1 in inlays:
            if name == "U_GoalDeck":
                # The goal dish is a real 5 cm recess the marble settles into.
                out.append(box(((rx0 + rx1) / 2, (ry0 + ry1) / 2, z - 0.05 - 0.05), (rx1 - rx0, ry1 - ry0, 0.1), tag=name + ":recess"))
            else:
                # Flush ring plates fill their inlay; their top is 1.5 cm proud.
                out.append(box(((rx0 + rx1) / 2, (ry0 + ry1) / 2, z + 0.015 - 0.05), (rx1 - rx0, ry1 - ry0, 0.1), tag=name + ":plate"))
        gaps = {side: list(spans) for side, spans in openings.items()}
        for side, spans in L5.SPILL_NOTCHES.get(name, {}).items():
            gaps.setdefault(side, []).extend(spans)
        t = 0.16
        for side, (a0, a1) in (("S", (x0, x1)), ("N", (x0, x1)), ("W", (y0, y1)), ("E", (y0, y1))):
            for s0, s1 in L5.side_segments(a0, a1, gaps.get(side, [])):
                mid, length = (s0 + s1) / 2, s1 - s0
                if side in "SN":
                    y = y0 + t / 2 if side == "S" else y1 - t / 2
                    out.append(box((mid, y, z + L5.RAIL_H / 2), (length, t, L5.RAIL_H), tag=name + ":rail"))
                else:
                    x = x0 + t / 2 if side == "W" else x1 - t / 2
                    out.append(box((x, mid, z + L5.RAIL_H / 2), (t, length, L5.RAIL_H), tag=name + ":rail"))
    for name, x0, x1, y0, y1, z, along in L5.BRIDGES:
        out.append(box(((x0 + x1) / 2, (y0 + y1) / 2, z - 0.05), (x1 - x0, y1 - y0, 0.1), tag=name + ":floor"))
        if along == "Y":
            for x in (x0 + 0.06, x1 - 0.06):
                out.append(box((x, (y0 + y1) / 2, z + L5.RAIL_H / 2), (0.15, y1 - y0, L5.RAIL_H), tag=name + ":rail"))
        else:
            for y in (y0 + 0.06, y1 - 0.06):
                out.append(box(((x0 + x1) / 2, y, z + L5.RAIL_H / 2), (x1 - x0, 0.15, L5.RAIL_H), tag=name + ":rail"))
    for p0, p1, z0, z1, thick, arches in walls:
        a, b = Vector((*p0, 0)), Vector((*p1, 0))
        d = b - a
        length = d.length
        if length < 0.05:
            continue
        d.normalize()
        yaw = math.atan2(d.y, d.x)
        cuts = sorted((c - s / 2 - 0.02, c + s / 2 + 0.02, sp + s / 2 + 0.24) for c, s, sp in arches)
        cursor = 0.0
        for c0, c1, top in cuts + [(length, length, z1)]:
            if c0 - cursor > 0.02:
                m = a + d * ((cursor + c0) / 2)
                out.append(box((m.x, m.y, (z0 + z1) / 2), (c0 - cursor, thick, z1 - z0), yaw, tag="wall"))
            if c1 > c0 and z1 - top > 0.02:
                m = a + d * ((c0 + c1) / 2)
                out.append(box((m.x, m.y, (top + z1) / 2), (c1 - c0, thick, z1 - top), yaw, tag="wall:lintel"))
            cursor = max(cursor, c1)
    for x0, x1, y0, y1, z_bed, depth, notches, spill, caps in flumes:
        along_x = (x1 - x0) >= (y1 - y0)
        out.append(box(((x0 + x1) / 2, (y0 + y1) / 2, z_bed - 0.04), (x1 - x0, y1 - y0, 0.08), tag="flume:bed"))
        if along_x:
            for y, low in ((y0 + 0.04, True), (y1 - 0.04, False)):
                spans = L5.side_segments(x0, x1, notches) if (low and notches) else [(x0, x1)]
                for s0, s1 in spans:
                    out.append(box(((s0 + s1) / 2, y, z_bed + depth / 2), (s1 - s0, 0.08, depth), tag="flume:wall"))
        else:
            for x in (x0 + 0.04, x1 - 0.04):
                out.append(box((x, (y0 + y1) / 2, z_bed + depth / 2), (0.08, y1 - y0, depth), tag="flume:wall"))
    lx0, lx1, ly0, ly1 = L5.LIFT["x0"], L5.LIFT["x1"], L5.LIFT["y0"], L5.LIFT["y1"]
    top = L5.Z2 + 1.65
    for x in (lx0 - 0.1, lx1 + 0.1):
        for y in (ly0 - 0.1, ly1 + 0.1):
            out.append(box((x, y, top / 2), (0.2, 0.2, top), tag="lift:post"))
    zf = L5.Z2 + 0.32
    out.append(box((7.825, 10.975, zf + 1.0), (2.55, 1.75, 2.0), tag="millhouse"))
    out.append(box((7.825, 10.95, L5.Z2 + 0.2), (2.9, 2.05, 0.2), tag="millhouse:plinth_top"))
    return out


def local_box(obj):
    """Local-space AABB of a mechanism (collider follows the node's pivot)."""
    vs = [v.co for v in obj.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c, s = (lo + hi) / 2, hi - lo
    return {"node": obj.name, "center": g_vec(c), "size": [round(s.x, 4), round(s.z, 4), round(s.y, 4)]}


# -------------------------------------------------------------- AO bake ----
def bake_ao(objs):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
        scene.cycles.device = "GPU"
    except Exception as error:
        print("bake device", error)
    scene.cycles.samples = 48
    scene.world.light_settings.distance = 0.9
    for obj in objs:
        mesh = obj.data
        ao = mesh.color_attributes.get("AO") or mesh.color_attributes.new("AO", "BYTE_COLOR", "CORNER")
        mesh.color_attributes.active_color = ao
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        t = time.time()
        bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
        col = mesh.color_attributes["Col"]
        for i in range(len(col.data)):
            a = ao.data[i].color[0]
            a = 0.35 + 0.65 * a          # keep it a soft contact shadow
            c = col.data[i].color
            col.data[i].color = (c[0] * a, c[1] * a, c[2] * a, 1.0)
        mesh.color_attributes.remove(mesh.color_attributes["AO"])
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
        print("AO baked", obj.name, "%.1fs" % (time.time() - t))


# ------------------------------------------------------------------ main ---
def join(objs, name):
    objs = [o for o in objs if o.type == "MESH"]
    if not objs:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    return obj


def main():
    os.makedirs(OUT, exist_ok=True)
    scene = bpy.context.scene
    walls = json.loads(scene.get("l05_walls", "[]"))
    flumes = json.loads(scene.get("l05_flumes", "[]"))
    before = stats("mobile build, before export pass")

    # Scene data for Godot: cameras, sun, lamps, waterfall landings, markers.
    data = {"cameras": {}, "lamps": [], "waterfalls": [], "markers": {}}
    for o in bpy.data.objects:
        if o.type == "CAMERA":
            hfov = 2 * math.atan(18.0 / o.data.lens) if o.data.type != "ORTHO" else None
            data["cameras"][o.name] = {"xform": g_xform(o.matrix_world, False), "hfov_deg": round(math.degrees(hfov), 3) if hfov else None,
                                       "ortho_size": o.data.ortho_scale if o.data.type == "ORTHO" else None}
        elif o.type == "LIGHT" and o.data.type == "SUN":
            data["sun"] = {"xform": g_xform(o.matrix_world, False), "color": list(o.data.color), "energy": o.data.energy}
        elif o.type == "LIGHT" and o.data.type == "POINT":
            data["lamps"].append({"pos": g_vec(o.matrix_world.translation), "energy_w": o.data.energy, "kind": o.name.split(".")[0]})
        elif o.type == "EMPTY" and o.name.startswith("Marker_"):
            data["markers"][o.name] = g_vec(o.matrix_world.translation)
        elif o.type == "MESH" and o.name.startswith("Waterfall_"):
            vs = [o.matrix_world @ v.co for v in o.data.vertices]
            low = min(v.z for v in vs)
            base = [v for v in vs if v.z < low + 0.25]
            c = sum(base, Vector()) / len(base)
            span = max(max(v.x for v in base) - min(v.x for v in base), max(v.y for v in base) - min(v.y for v in base))
            data["waterfalls"].append({"name": o.name, "landing": g_vec(c), "width": round(span, 3),
                                       "drop": round(max(v.z for v in vs) - low, 3)})

    # Vegetation -> MultiMesh transforms; prototypes stay as hidden nodes.
    veg = {}
    protos = {}
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.name.startswith("Fir_") and "Variant" not in o.name:
            veg.setdefault(o.data.name, []).append(g_xform(o.matrix_world))
            bpy.data.objects.remove(o)
    proto_col = bpy.data.collections.new("Protos")
    scene.collection.children.link(proto_col)
    for o in list(bpy.data.objects):
        if o.type == "MESH" and "Variant" in o.name:
            if o.data.name in veg:
                for c in o.users_collection:
                    c.objects.unlink(o)
                proto_col.objects.link(o)
                o.hide_render = False
                o.hide_viewport = False
                o.matrix_world = Matrix.Identity(4)
                o.name = "Proto_" + o.data.name
                protos[o.data.name] = o.name
            else:
                bpy.data.objects.remove(o)
    json.dump({"note": "MultiMesh per prototype node; transforms are Godot Transform3D columns [x, y, z, origin].",
               "prototypes": {protos[k]: v for k, v in veg.items() if k in protos}},
              open(os.path.join(OUT, "level05_vegetation.json"), "w"), separators=(",", ":"))

    # Drop render-only objects; lights/cameras live in the JSON.
    for o in list(bpy.data.objects):
        if o.type in ("LIGHT", "CAMERA") or o.name in ("Preview_Marble",):
            bpy.data.objects.remove(o)

    # Mechanism colliders (local to their pivots), before any join.
    # The cage is hollow (the marble rides inside) and the goal socket is a
    # recess, so neither may become one solid box.
    movers = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith(("Lift_Gate", "Crate_", "Gate_", "Valve_", "Lever_"))]
    dyn = [local_box(o) for o in movers if not in_tree(o, "Static_Architecture")]
    # Fixed frames (sluice gate frames) are merged into the static mesh, so
    # their collider is a world box instead of a node-local one.
    frames = []
    for o in movers:
        if in_tree(o, "Static_Architecture"):
            vs = [o.matrix_world @ v.co for v in o.data.vertices]
            lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
            hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
            frames.append(box((lo + hi) / 2, hi - lo, tag=o.name))
    w = d = L5.LIFT["x1"] - L5.LIFT["x0"] - 0.16
    cage_parts = [((0, 0, -0.06), (w, d, 0.12)), ((0, -d / 2 + 0.05, 0.14), (w, 0.1, 0.28)), ((w / 2 - 0.05, 0, 0.14), (0.1, d, 0.28)),
                  ((0, 0, 1.0), (w, 0.1, 0.1))]
    cage_parts += [((sx * (w / 2 - 0.06), sy * (d / 2 - 0.06), 0.5), (0.12, 0.12, 1.0)) for sx in (-1, 1) for sy in (-1, 1)]
    for c, sz in cage_parts:
        dyn.append({"node": "Lift_Cage", "center": g_vec(c), "size": [sz[0], sz[2], sz[1]]})

    # Materials -> mobile groups + vertex colours.
    for o in bpy.data.objects:
        if o.type == "MESH":
            remap_object(o)
    for m in list(bpy.data.materials):
        if not m.name.startswith("M_") and m.users == 0:
            bpy.data.materials.remove(m)

    # Merge static, non-moving geometry per area; keep decks, bridges and
    # mechanisms as separate nodes (pivots + extras intact).
    static, terrain, water, falls = {}, [], [], []
    for o in list(bpy.data.objects):
        if o.type != "MESH" or o.users_collection[0].name == "Protos":
            continue
        if in_tree(o, "Water"):
            (falls if o.name.startswith("Waterfall_") else water).append(o)
        elif in_tree(o, "Terrain") or in_tree(o, "Vegetation"):
            terrain.append(o)
        elif in_tree(o, "Static_Architecture") or in_tree(o, "Dressing"):
            step = max(1, len(o.data.vertices) // 64)
            vs = [o.matrix_world @ o.data.vertices[i].co for i in range(0, len(o.data.vertices), step)]
            cx = sum(v.x for v in vs) / max(1, len(vs))
            cy = sum(v.y for v in vs) / max(1, len(vs))
            key = ("W" if cx < 6.0 else "E") + ("S" if cy < 6.0 else "N")
            static.setdefault(key, []).append(o)
    merged = [join(v, "Static_" + k) for k, v in sorted(static.items())]
    merged.append(join(terrain, "Terrain_Summit"))
    # Water bodies stay separate nodes: gameplay drives each one from its own
    # hydraulic connection (flow speed, foam, falls on/off).
    for o in water + falls:
        for mod in list(o.modifiers):
            o.modifiers.remove(mod)
    merged = [m for m in merged if m]
    bake_ao(merged)
    after = stats("mobile GLB content")

    # Export.
    path = os.path.join(OUT, "level05_mobile.glb")
    kwargs = dict(filepath=path, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
                  export_extras=True, export_lights=False, export_cameras=False, export_animations=False,
                  export_image_format="AUTO", export_materials="EXPORT", export_texcoords=True, export_normals=True)
    for key, value in (("export_vertex_color", "ACTIVE"), ("export_all_vertex_colors", False), ("export_colors", True)):
        try:
            bpy.ops.export_scene.gltf.get_rna_type().properties[key]
            kwargs[key] = value
        except KeyError:
            pass
    bpy.ops.export_scene.gltf(**kwargs)
    data["stats"] = {"before": before, "after": after, "glb_bytes": os.path.getsize(path)}
    data["colliders_static_count"] = 0
    col = colliders(walls, flumes) + frames
    data["colliders_static_count"] = len(col)
    json.dump({"note": "BoxShape3D colliders. static: world boxes (yaw about +Y). dynamic: local boxes on the named node.",
               "static": col, "dynamic": dyn}, open(os.path.join(OUT, "level05_colliders.json"), "w"), indent=0)
    json.dump(data, open(os.path.join(OUT, "level05_scene.json"), "w"), indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "assets", "blender", "level05_alpine_watermill_mobile_export.blend"), compress=True)
    print("L05 MOBILE", json.dumps(data["stats"]))


main()
