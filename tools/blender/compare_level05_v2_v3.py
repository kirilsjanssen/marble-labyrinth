"""Compares v2 and v3 geometry fingerprints and audits (plain Python).

python tools/blender/compare_level05_v2_v3.py FP_V2 FP_V3 AUDIT_V2 AUDIT_V3 OUT.json
"""
import json
import sys

fp2, fp3 = (json.load(open(p, encoding="utf-8")) for p in sys.argv[1:3])
au2, au3 = (json.load(open(p, encoding="utf-8")) for p in sys.argv[3:5])
out = sys.argv[5]

common = sorted(set(fp2) & set(fp3))
same = [n for n in common if fp2[n]["sha1"] == fp3[n]["sha1"]]
changed = {n: {"v2_verts": fp2[n]["verts"], "v3_verts": fp3[n]["verts"], "v2_bbox": fp2[n]["bbox"], "v3_bbox": fp3[n]["bbox"]}
           for n in common if fp2[n]["sha1"] != fp3[n]["sha1"]}
added = sorted(set(fp3) - set(fp2))
removed = sorted(set(fp2) - set(fp3))


def added_groups(names):
    groups = {}
    for n in names:
        key = n.split(".")[0]
        key = key.rstrip("0123456789_") if key[-1:].isdigit() else key
        groups[key] = groups.get(key, 0) + 1
    return groups


def pick(audit, keys):
    return {k: audit.get(k) for k in keys}


routes2, routes3 = au2.get("routes", {}), au3.get("routes", {})
route_cmp = {}
for name in routes2:
    r2, r3 = routes2[name], routes3.get(name, {})
    route_cmp[name] = {k: [r2.get(k), r3.get(k)] for k in r2 if not isinstance(r2.get(k), (list, dict))}
result = {
    "geometry": {
        "common_meshes": len(common),
        "identical": len(same),
        "changed": changed,
        "added": added_groups(added),
        "removed": removed,
    },
    "floors_identical": au2.get("floors") == au3.get("floors"),
    "gear_pairs_identical": au2.get("gear_pairs") == au3.get("gear_pairs"),
    "lift_travel_identical": au2.get("lift_travel") == au3.get("lift_travel"),
    "lift_cage_identical": au2.get("lift_cage") == au3.get("lift_cage"),
    "mechanism_interference_unintended": [len(au2.get("mechanism_interference_unintended", [])), len(au3.get("mechanism_interference_unintended", []))],
    "mechanism_interference_total": [len(au2.get("mechanism_interference", [])), len(au3.get("mechanism_interference", []))],
    "routes_v2_v3": route_cmp,
    "routes_identical": routes2 == routes3,
    "camera_occlusion_iso": [au2.get("camera_occlusion_iso"), au3.get("camera_occlusion_iso")],
    "water_bodies": [sorted(au2.get("water", {})), sorted(au3.get("water", {}))],
}
json.dump(result, open(out, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
g = result["geometry"]
print("meshes common %d, identical %d, changed %d, added %d, removed %d" % (g["common_meshes"], g["identical"], len(g["changed"]), len(added), len(removed)))
print("changed:", sorted(g["changed"]))
print("added groups:", g["added"])
for k in ("floors_identical", "gear_pairs_identical", "lift_travel_identical", "lift_cage_identical", "routes_identical",
          "mechanism_interference_unintended", "mechanism_interference_total"):
    print(k, result[k])
