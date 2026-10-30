"""Read-only engineering audit of assets/blender/level05_alpine_watermill.blend.

    blender -b --factory-startup assets/blender/level05_alpine_watermill.blend \
            -P tools/blender/audit_level05.py -- <output.json>

Measures world-space geometry: floor heights, deck extents and thickness,
marble (r = 0.33 m) clearance along the routes, headroom, gaps, mechanism
interference, gear meshing, lift travel and camera occlusion. Nothing is
saved: in-memory moves (lift cage travel) are restored before exit.
"""
import json
import math
import sys
from collections import defaultdict

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

R = 0.33
Z0, Z1, Z2 = 0.0, 1.4, 2.8
OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "level05_audit.json"


def coll_of(obj):
    names = [c.name for c in obj.users_collection]
    return names[0] if names else ""


def in_tree(obj, root):
    """True when obj sits anywhere below the collection named root."""
    def walk(col):
        if obj.name in col.objects:
            return True
        return any(walk(c) for c in col.children)
    col = bpy.data.collections.get(root)
    return walk(col) if col else False


def world_mesh(obj):
    mw = obj.matrix_world
    verts = [mw @ v.co for v in obj.data.vertices]
    polys = [tuple(p.vertices) for p in obj.data.polygons]
    return verts, polys


def bbox(obj):
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    return [min(p.x for p in pts), max(p.x for p in pts), min(p.y for p in pts), max(p.y for p in pts), min(p.z for p in pts), max(p.z for p in pts)]


def r3(v):
    return round(v, 3)


meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.hide_render]
groups = defaultdict(list)
for o in meshes:
    for root in ("Platforms", "Static_Architecture", "Mechanisms", "Water", "Terrain", "Vegetation", "Background", "Game_Markers"):
        if in_tree(o, root):
            groups[root].append(o)
            break

report = {"objects": len(bpy.data.objects), "mesh_objects": len(meshes)}

# ---------------------------------------------------------------- extents ----
def union(objs):
    bs = [bbox(o) for o in objs]
    return [r3(min(b[0] for b in bs)), r3(max(b[1] for b in bs)), r3(min(b[2] for b in bs)), r3(max(b[3] for b in bs)), r3(min(b[4] for b in bs)), r3(max(b[5] for b in bs))]


report["extents"] = {k: union(v) for k, v in groups.items() if v}
tri = {}
for k, v in groups.items():
    tri[k] = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in v)
report["triangles_by_group"] = tri

# ---------------------------------------------- floors: heights, thickness ----
floors = {}
for o in groups["Platforms"] + [x for x in groups["Mechanisms"] if x.name.startswith("Bridge_")]:
    verts, polys = world_mesh(o)
    area_by_z = defaultdict(float)
    for p in o.data.polygons:
        n = (o.matrix_world.to_3x3() @ p.normal).normalized()
        if n.z > 0.98:
            z = round(sum(verts[i].z for i in p.vertices) / len(p.vertices), 2)
            area_by_z[z] += p.area
    # Walking surface = the highest up-facing level with substantial area
    # (boards sit 5 cm above the subfloor slab, which has more area).
    biggest = max(area_by_z.values())
    top = max(z for z, a in area_by_z.items() if a >= 0.2 * biggest)
    # Walking-surface extent: up-facing faces at the floor height.
    xs, ys = [], []
    for p in o.data.polygons:
        n = (o.matrix_world.to_3x3() @ p.normal).normalized()
        if n.z > 0.98 and abs(sum(verts[i].z for i in p.vertices) / len(p.vertices) - top) < 0.015:
            for i in p.vertices:
                xs.append(verts[i].x)
                ys.append(verts[i].y)
    b = bbox(o)
    floors[o.name] = {"floor_z": top, "walk_x": [r3(min(xs)), r3(max(xs))], "walk_y": [r3(min(ys)), r3(max(ys))],
                      "size": [r3(max(xs) - min(xs)), r3(max(ys) - min(ys))], "thickness_below_floor": r3(top - b[4]), "rail_top_above_floor": r3(b[5] - top)}
report["floors"] = floors

# ------------------------------------------------------- solid BVH (lanes) ----
SOLID_ROOTS = ("Platforms", "Static_Architecture", "Mechanisms", "Terrain")
solid_objs = [o for root in SOLID_ROOTS for o in groups[root] if not o.name.startswith("Lift_Chain")]
all_v, all_p, owner = [], [], []
for o in solid_objs:
    verts, polys = world_mesh(o)
    base = len(all_v)
    all_v.extend(verts)
    for p in polys:
        all_p.append(tuple(base + i for i in p))
        owner.append(o.name)
SOLID = BVHTree.FromPolygons(all_v, all_p)


def ray(origin, direction, dist=50.0, tree=None):
    hit = (tree or SOLID).ray_cast(Vector(origin), Vector(direction).normalized(), dist)
    if hit[0] is None:
        return None, None
    return (hit[0] - Vector(origin)).length, owner[hit[2]] if tree is None else hit[2]


def nearest(center, dist):
    hit = SOLID.find_nearest(Vector(center), dist)
    if hit[0] is None:
        return None, None
    return (hit[0] - Vector(center)).length, owner[hit[2]]


# Routes on the lane centrelines (world X, Y, floor Z). Lift legs are checked
# separately (vertical travel of the cage).
ROUTES = {
    "main_lower": [(0.8, 4.0, Z0), (2.0, 3.9, Z0), (3.3, 3.85, Z0), (4.6, 3.8, Z0), (4.6, 3.05, Z0), (4.6, 1.95, Z0), (4.6, 1.0, Z0), (6.0, 1.0, Z0), (6.8, 1.0, Z0), (7.9, 1.0, Z0), (9.0, 1.0, Z0), (9.8, 1.0, Z0)],
    "main_middle": [(9.8, 1.0, Z1), (9.8, 1.8, Z1), (9.8, 2.4, Z1), (9.8, 3.0, Z1), (8.0, 3.0, Z1), (6.6, 4.0, Z1), (6.0, 5.6, Z1), (5.5, 5.75, Z1), (4.9, 5.75, Z1), (4.3, 5.6, Z1)],
    "main_upper": [(9.8, 1.0, Z2), (9.9, 1.8, Z2), (9.9, 5.6, Z2), (9.98, 6.5, Z2), (9.98, 8.5, Z2), (9.4, 8.5, Z2), (8.5, 8.5, Z2), (6.6, 8.5, Z2), (4.5, 8.5, Z2), (2.4, 8.6, Z2)],
    "secret_corridor": [(5.0, 4.0, Z0), (5.55, 4.0, Z0), (6.0, 4.0, Z0), (8.2, 4.0, Z0), (9.0, 4.0, Z0), (9.7, 4.0, Z0)],
}


def sample(route, step=0.05):
    pts = []
    for a, b in zip(route, route[1:]):
        a, b = Vector(a), Vector(b)
        n = max(1, int((b - a).length / step))
        for i in range(n):
            pts.append(a.lerp(b, i / n))
    pts.append(Vector(route[-1]))
    return pts


route_report = {}
lane_issues = []
for name, route in ROUTES.items():
    pts = sample(route)
    min_clear, min_width, min_head = 9, 9, 9
    head_by = None
    seg_width = []
    blocked = []
    gaps = []
    for k, p in enumerate(pts):
        center = p + Vector((0, 0, R + 0.012))
        d, who = nearest(center, R)
        if d is not None and d < R - 0.002:
            blocked.append({"at": [r3(p.x), r3(p.y), r3(p.z)], "penetration_cm": round((R - d) * 100, 1), "by": who})
        # Floor support under the marble footprint: probe a 0.12 m cross so
        # the 1.4 cm gaps between floor boards do not count as holes.
        supported = False
        offsets = []
        for dx, dy in ((0, 0), (0.06, 0), (-0.06, 0), (0, 0.06), (0, -0.06)):
            down, by = ray(p + Vector((dx, dy, 0.3)), (0, 0, -1), 1.0)
            if down is not None:
                offsets.append(0.3 - down)
                if abs(0.3 - down) <= 0.03:
                    supported = True
        if not supported:
            gaps.append({"at": [r3(p.x), r3(p.y)], "floor_offset": r3(max(offsets)) if offsets else None, "by": by})
        # Lateral free width at marble-centre height, perpendicular to travel.
        nxt = pts[min(k + 1, len(pts) - 1)]
        prv = pts[max(k - 1, 0)]
        t = (nxt - prv)
        t.z = 0
        if t.length > 1e-6:
            t.normalize()
            side = Vector((-t.y, t.x, 0))
            l, _ = ray(center, side, 5.0)
            r, _ = ray(center, -side, 5.0)
            if l is not None and r is not None:
                min_width = min(min_width, l + r)
                seg_width.append((k, l + r))
        # Headroom over the marble: from its centre upward (+0.33).
        up, by_up = ray(center, (0, 0, 1), 6.0)
        if up is not None and up + R < min_head:
            min_head = up + R
            head_by = (by_up, [r3(p.x), r3(p.y)])
        dd, _ = nearest(center, 2.0)
        if dd is not None:
            min_clear = min(min_clear, dd)
    # Deduplicate blocked points into contiguous stretches.
    stretches = []
    for b in blocked:
        if stretches and stretches[-1]["by"] == b["by"] and (Vector(stretches[-1]["to"][:2] + [0]) - Vector(b["at"][:2] + [0])).length < 0.12:
            stretches[-1]["to"] = b["at"]
            stretches[-1]["max_penetration_cm"] = max(stretches[-1]["max_penetration_cm"], b["penetration_cm"])
        else:
            stretches.append({"from": b["at"], "to": b["at"], "by": b["by"], "max_penetration_cm": b["penetration_cm"]})
    # Per-leg minimum free width (wall-to-wall at marble-centre height).
    legs = []
    per = max(1, len(pts) // max(1, len(route) - 1))
    for i in range(len(route) - 1):
        ws = [w for k, w in seg_width if i * per <= k < (i + 1) * per]
        legs.append({"from": route[i], "to": route[i + 1], "min_width": r3(min(ws)) if ws else None})
    route_report[name] = {"samples": len(pts), "blocked_stretches": stretches, "floor_gaps": gaps[:12], "floor_gap_count": len(gaps),
                          "min_free_width_m": r3(min_width), "min_headroom_m": r3(min_head), "headroom_limited_by": head_by,
                          "min_centre_clearance_m": r3(min_clear), "legs": legs}
report["routes"] = route_report

# ---------------------------------------- protrusions of plates on floors ----
prot = {}
for name in ("Plate_StartRing", "Gear_StartRing", "Plate_Cube", "Plate_CorridorRing", "Gear_CorridorTrigger", "Goal_Socket", "Lever_Sluice_Base", "Lever_Secret_Base", "Lever_Sluice"):
    o = bpy.data.objects.get(name)
    if o:
        b = bbox(o)
        down, _ = ray((o.location.x + 0.6, o.location.y + 0.6, b[5] + 0.5), (0, 0, -1), 5.0)
        prot[name] = {"top_z": r3(b[5]), "footprint": [r3(b[1] - b[0]), r3(b[3] - b[2])], "location": [r3(o.location.x), r3(o.location.y), r3(o.location.z)]}
report["floor_items"] = prot

# ---------------------------------------------------- wheels and gears ----
mech = {}
for o in groups["Mechanisms"]:
    role = o.get("l05_role")
    if role in ("water_wheel", "gear", "shaft", "lift_deck"):
        b = bbox(o)
        mech[o.name] = {"role": role, "location": [r3(o.location.x), r3(o.location.y), r3(o.location.z)], "axis": o.get("l05_axis"),
                        "radius": o.get("l05_radius"), "teeth": o.get("l05_teeth"), "bbox": [r3(x) for x in b]}
report["mechanisms"] = mech


def axis_vec(name):
    o = bpy.data.objects[name]
    a = o.get("l05_axis", "Z")
    v = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}[a]
    return (o.matrix_world.to_3x3() @ v).normalized()


gear_names = [n for n, m in mech.items() if m["role"] == "gear"]
pairs = []
for i, a in enumerate(gear_names):
    for b in gear_names[i + 1:]:
        oa, ob = bpy.data.objects[a], bpy.data.objects[b]
        d = (oa.location - ob.location).length
        ra, rb = oa["l05_radius"], ob["l05_radius"]
        if d > ra + rb + 0.6:
            continue
        va, vb = axis_vec(a), axis_vec(b)
        parallel = abs(va.dot(vb)) > 0.99
        offset_plane = abs((ob.location - oa.location).dot(va)) if parallel else None
        pitch_a = 2 * math.pi * ra / oa["l05_teeth"]
        pitch_b = 2 * math.pi * rb / ob["l05_teeth"]
        ideal = ra + rb - 0.5 * (ra * 0.16 + rb * 0.16)
        pairs.append({"a": a, "b": b, "centre_distance": r3(d), "ideal_spur_distance": r3(ideal), "axes": "parallel" if parallel else "crossed %.0f deg" % math.degrees(math.acos(min(1, abs(va.dot(vb))))),
                      "plane_offset": None if offset_plane is None else r3(offset_plane), "pitch_mm": [round(pitch_a * 1000), round(pitch_b * 1000)]})
report["gear_pairs"] = pairs

# --------------------------------------------- interference (mesh overlap) ----
def obj_tree(o, offset=Vector((0, 0, 0))):
    verts, polys = world_mesh(o)
    return BVHTree.FromPolygons([v + offset for v in verts], polys)


trees = {o.name: obj_tree(o) for o in solid_objs}
clashes = []
moving = [o for o in groups["Mechanisms"] if o.get("l05_role") in ("water_wheel", "gear", "shaft", "lift_deck", "gate", "lift_gate")]
for m in moving:
    tm = trees[m.name]
    for o in solid_objs:
        if o is m:
            continue
        hits = tm.overlap(trees[o.name])
        if hits:
            clashes.append({"moving": m.name, "with": o.name, "faces": len(hits)})
report["mechanism_interference"] = clashes

# ------------------------------------------------ lift travel 0 -> 2.8 m ----
cage = bpy.data.objects["Lift_Cage"]
travel = []
others = [o for o in solid_objs if not o.name.startswith("Lift_Cage") and not o.name.startswith("Lift_Gate")]
z = 0.0
while z <= 2.81:
    t = obj_tree(cage, Vector((0, 0, z)))
    hit_names = sorted({o.name for o in others if t.overlap(trees[o.name])})
    travel.append({"z": r3(z), "touches": hit_names})
    z += 0.1
report["lift_travel"] = travel
cb = bbox(cage)
report["lift_cage"] = {"deck_size": [r3(cb[1] - cb[0]), r3(cb[3] - cb[2])], "bbox_at_Z0": [r3(x) for x in cb]}
# Clear height inside the cage at its centre line (crossbar).
inside_up, by = ray((cage.location.x + 0.4, cage.location.y + 0.0, cage.location.z + 0.02), (0, 0, 1), 3.0)
report["lift_cage"]["clear_height_under_crossbar"] = None if inside_up is None else r3(inside_up + 0.02)

# ---------------------------------------- camera occlusion (iso camera) ----
cam = bpy.data.objects.get("Cam_01_Isometric")
occ = {}
if cam:
    cpos = cam.matrix_world.translation
    for name, route in ROUTES.items():
        pts = sample(route, 0.25)
        hidden = 0
        blockers = defaultdict(int)
        for p in pts:
            ball = p + Vector((0, 0, R))
            seen = 0
            for off in (Vector((0, 0, 0)), Vector((0, 0, R * 0.8))):
                target = ball + off
                d = (target - cpos)
                dist, who = ray(cpos, d, d.length - 0.36)
                if dist is None:
                    seen += 1
                else:
                    blockers[who] += 1
            if seen == 0:
                hidden += 1
        occ[name] = {"samples": len(pts), "fully_hidden": hidden, "hidden_pct": round(100 * hidden / len(pts)), "top_blockers": sorted(blockers.items(), key=lambda kv: -kv[1])[:5]}
report["camera_occlusion_iso"] = occ

# --------------------------------------------------------- water bodies ----
water = {}
for o in groups["Water"]:
    b = bbox(o)
    water[o.name] = {"x": [r3(b[0]), r3(b[1])], "y": [r3(b[2]), r3(b[3])], "z": [r3(b[4]), r3(b[5])], "w": r3(min(b[1] - b[0], b[3] - b[2])), "l": r3(max(b[1] - b[0], b[3] - b[2]))}
report["water"] = water

# --------------------------------------------- markers and pixel mapping ----
markers = {o.name: [r3(o.location.x), r3(o.location.y), r3(o.location.z)] for o in bpy.data.objects if o.name.startswith("Marker_")}
report["markers"] = markers

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=1, ensure_ascii=False)
print("AUDIT written", OUT)
