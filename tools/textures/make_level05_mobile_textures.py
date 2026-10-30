"""Mobile (Android / Godot GL Compatibility) texture sets for Level 05.

The v4 Blender look grades one Luma texture set per role with a Hue/Sat/Value
node (e.g. Wood_Frame, Wood_Dark, Wood_Weathered and Bark all use wood_beam).
On mobile each set becomes ONE material: the texture is pre-graded for its
brightest role, and every other role (plus the per-piece jitter) becomes a
vertex-colour multiplier computed here from the real pixels. 40 Blender
materials collapse to 15 mobile materials without losing the colour variety.

Usage: python -I tools/textures/make_level05_mobile_textures.py
Writes assets/levels/level05/textures/ and mobile_material_map.json.
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "luma", "level05")
L04 = os.path.join(ROOT, "assets", "luma", "level04")
OUT = os.path.join(ROOT, "assets", "levels", "level05", "textures")
# PBR sets only feed the GLB (Godot extracts them from it): keep the source
# copies out of the Godot import so they are not packed twice into the APK.
PBR = os.path.join(ROOT, "assets", "levels", "level05", "textures_pbr")
BINS = 16

# group: (source key, size, base role)
GROUPS = {
    "wood_beam": ("wood_beam", 1024, "Wood_Frame"),
    "wood_board": ("wood_board", 1024, "Deck_Board"),
    "stone": ("stone_masonry", 1024, "Stone_Masonry"),
    "rock": ("rock_moss", 1024, "Rock_Moss"),
    "meadow": ("meadow", 1024, "Meadow"),
    "roof": ("roof_slate", 512, "Roof_Slate"),
    "fir": ("fir_needles", 512, "Fir_Needles"),
}
# Blender v4 grades: role -> (group, hue offset, saturation, value, jitter (h, s, v)).
ROLES = {
    "Wood_Frame": ("wood_beam", 0.012, 1.3, 1.95, (0.012, 0.12, 0.3)),
    "Wood_Dark": ("wood_beam", 0.0, 1.1, 0.8, (0.01, 0.1, 0.2)),
    "Wood_Weathered": ("wood_beam", 0.0, 1.0, 1.45, (0.01, 0.12, 0.3)),
    "Bark": ("wood_beam", 0.0, 0.9, 0.7, (0.015, 0.1, 0.2)),
    "Deck_Board": ("wood_board", 0.0, 1.2, 1.08, (0.015, 0.12, 0.3)),
    "Wood_Plank": ("wood_board", 0.0, 1.15, 1.0, (0.012, 0.1, 0.25)),
    "Stone_Masonry": ("stone", 0.0, 1.05, 1.0, (0.015, 0.15, 0.32)),
    "Stone_Wet": ("stone", 0.0, 1.15, 0.6, (0.01, 0.1, 0.2)),
    "Slate_Floor": ("stone", 0.0, 0.7, 0.5, (0.01, 0.1, 0.2)),
    "Rock_Moss": ("rock", 0.0, 1.0, 0.85, (0.01, 0.1, 0.15)),
    "Mortar_Moss": ("rock", 0.02, 1.2, 0.42, (0.01, 0.1, 0.1)),
    "Meadow": ("meadow", 0.0, 1.0, 1.0, (0.01, 0.08, 0.15)),
    "Roof_Slate": ("roof", 0.0, 0.95, 0.4, (0.03, 0.2, 0.3)),
    "Roof_Shingle": ("roof", 0.03, 1.5, 0.34, (0.03, 0.2, 0.2)),
    "Fir_Needles": ("fir", -0.01, 1.25, 1.7, (0.025, 0.15, 0.35)),
    "Fir_Needles_Far": ("fir", 0.03, 0.9, 1.6, (0.02, 0.1, 0.3)),
}
# Untextured roles: flat linear colours in vertex colour (M_Painted / M_Iron / M_Glow).
FLAT = {
    "Red_Paint": ("painted", (0.55, 0.05, 0.03)),
    "Plate_White": ("painted", (0.85, 0.82, 0.78)),
    "Banner_Red": ("painted", (0.45, 0.03, 0.03)),
    "Petal_Red": ("painted", (0.7, 0.03, 0.025)),
    "Petal_Pink": ("painted", (0.85, 0.22, 0.3)),
    "Petal_White": ("painted", (0.9, 0.88, 0.8)),
    "Leaf_Green": ("painted", (0.035, 0.12, 0.02)),
    "Grass": ("painted", (0.07, 0.17, 0.03)),
    "Marble_Steel": ("iron", (0.8, 0.82, 0.85)),
    "Iron": ("iron", (0.2, 0.2, 0.21)),
    "Brass": ("brass", (0.86, 0.86, 0.86)),
    "Goal_Gold": ("brass", (1.0, 1.0, 1.0)),
    "Window_Glow": ("glow", (1.0, 0.4, 0.09)),
    "Lantern_Glow": ("glow", (1.0, 0.36, 0.06)),
    "Water": ("water", (1.0, 1.0, 1.0)),          # COLOR.r = flow speed factor
    "Water_Still": ("water", (0.1, 1.0, 1.0)),
    "Waterfall_Body": ("fall_body", (1.0, 1.0, 1.0)),
    "Waterfall_Foam": ("fall_foam", (1.0, 1.0, 1.0)),
    "Water_Spray": ("spray", (1.0, 1.0, 1.0)),
    "Water_FoamPatch": ("spray", (1.0, 1.0, 1.0)),
    "Water_Mist": ("spray", (0.8, 0.8, 0.8)),
    "Chimney_Smoke": ("spray", (0.55, 0.55, 0.58)),
}


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-8
    rc = np.where(m, (mx - r) / np.where(m, d, 1), 0)
    gc = np.where(m, (mx - g) / np.where(m, d, 1), 0)
    bc = np.where(m, (mx - b) / np.where(m, d, 1), 0)
    h = np.where(r == mx, bc - gc, np.where(g == mx, 2.0 + rc - bc, 4.0 + gc - rc))
    h = np.where(m, (h / 6.0) % 1.0, 0.0)
    s = np.where(mx > 1e-8, d / np.maximum(mx, 1e-8), 0.0)
    return np.stack([h, s, mx], -1)


def hsv_to_rgb(hsv):
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    i = np.floor(h * 6.0)
    f = h * 6.0 - i
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    i = i.astype(int) % 6
    conds = [i == k for k in range(6)]
    r = np.select(conds, [v, q, p, p, t, v])
    g = np.select(conds, [t, v, v, q, p, p])
    b = np.select(conds, [p, p, t, v, v, q])
    return np.stack([r, g, b], -1)


def grade(lin, hue, sat, val):
    """Blender Hue/Saturation/Value node on scene-linear colour."""
    hsv = rgb_to_hsv(lin)
    hsv[..., 0] = (hsv[..., 0] + hue) % 1.0
    hsv[..., 1] = np.clip(hsv[..., 1] * sat, 0.0, 1.0)
    hsv[..., 2] = hsv[..., 2] * val
    return hsv_to_rgb(hsv)


def load(path, size=None):
    img = Image.open(path).convert("RGB")
    if size:
        img = img.resize(size, Image.LANCZOS)
    return np.asarray(img, np.float64) / 255.0


def save_rgb(a, path, quality=90):
    Image.fromarray(np.uint8(np.clip(a, 0, 1) * 255 + 0.5)).save(path, quality=quality, optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PBR, exist_ok=True)
    open(os.path.join(PBR, ".gdignore"), "w").close()
    tints = {}
    for group, (key, size, base_role) in GROUPS.items():
        src = os.path.join(SRC, key + "_albedo.jpg")
        lin = srgb_to_linear(load(src, (size, size)))
        small = srgb_to_linear(load(src, (64, 64)))
        # Neutral base grade: the group's lowest saturation and highest value,
        # raised until every role's mean colour is reachable with a tint <= 1
        # (a multiplier can darken and re-saturate, but never brighten).
        members = [r for r in ROLES.values() if r[0] == group]
        bh, bs, bv = 0.0, min(m[2] for m in members), max(m[3] for m in members)
        for _ in range(6):
            base_mean = grade(small, bh, bs, bv).reshape(-1, 3).mean(0)
            need = max(float((grade(small, m[1], m[2] * (1 + m[4][1]), m[3] + m[4][2]).reshape(-1, 3).mean(0) / base_mean).max()) for m in members)
            if need <= 1.0:
                break
            bv *= need
        base = grade(lin, bh, bs, bv)
        save_rgb(linear_to_srgb(base), os.path.join(PBR, group + "_albedo.jpg"))
        # Normal/roughness at half the albedo size: low-frequency on a phone screen.
        for suffix in ("normal.png", "rough.jpg"):
            Image.open(os.path.join(SRC, "%s_%s" % (key, suffix))).resize((size // 2, size // 2), Image.LANCZOS).save(
                os.path.join(PBR, "%s_%s" % (group, suffix)), **({"quality": 92} if suffix.endswith("jpg") else {"optimize": True}))
        base_mean = grade(small, bh, bs, bv).reshape(-1, 3).mean(0)
        print(group, "base grade sat %.2f val %.2f" % (bs, bv))
        for role, (g, h, s, v, (jh, js, jv)) in ROLES.items():
            if g != group:
                continue
            table = []
            for k in range(BINS):
                r = (k + 0.5) / BINS
                graded = grade(small, h + (r - 0.5) * 2 * jh, s * 1.0 + (r - 0.5) * 2 * js, v + (r - 0.5) * 2 * jv)
                tint = graded.reshape(-1, 3).mean(0) / np.maximum(base_mean, 1e-5)
                table.append([round(float(min(1.0, x)), 4) for x in tint])
            tints[role] = {"group": group, "tint_bins": table}
    # Brass: clean golden F0 with 20 % texture variation, exactly as mat_brass.
    lin = srgb_to_linear(load(os.path.join(SRC, "brass_albedo.jpg"), (512, 512)))
    gold = np.array([0.95, 0.64, 0.24]) * 0.8 + 0.2 * lin * np.array([1.05, 0.83, 0.55])
    save_rgb(linear_to_srgb(gold), os.path.join(PBR, "brass_albedo.jpg"))
    for suffix in ("normal.png", "rough.jpg"):
        Image.open(os.path.join(SRC, "brass_" + suffix)).resize((256, 256), Image.LANCZOS).save(os.path.join(PBR, "brass_" + suffix))
    # Water / falls / spray (shader inputs) and the derived water normal.
    foam = Image.open(os.path.join(L04, "water_foam.jpg")).convert("RGB").resize((512, 512), Image.LANCZOS)
    foam.save(os.path.join(OUT, "water_foam.jpg"), quality=90)
    f = np.asarray(foam, np.float64).mean(-1) / 255.0
    dx = (np.roll(f, -1, 1) - np.roll(f, 1, 1)) * 0.5
    dv = (np.roll(f, 1, 0) - np.roll(f, -1, 0)) * 0.5
    n = np.stack([-dx * 6.0, -dv * 6.0, np.ones_like(f)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    Image.fromarray(np.uint8((n * 0.5 + 0.5) * 255 + 0.5)).save(os.path.join(OUT, "water_normal.png"))
    for name, size in (("waterfall_streaks.png", (256, 512)), ("waterfall_foam_mask.png", (256, 512)), ("waterfall_normal.png", (256, 512))):
        Image.open(os.path.join(SRC, name)).resize(size, Image.LANCZOS).save(os.path.join(OUT, name))
    # Soft round sprite for spray particles and lantern glow billboards.
    yy, xx = np.mgrid[0:128, 0:128] / 127.0 * 2 - 1
    soft = np.clip(1.0 - np.sqrt(xx * xx + yy * yy), 0, 1) ** 1.8
    Image.fromarray(np.uint8(np.dstack([np.ones_like(soft)] * 3 + [soft]) * 255), "RGBA").save(os.path.join(OUT, "soft_sprite.png"))
    # Parallax layers (mobile sizes) - the far layer is the Blender panorama.
    par = os.path.join(OUT, "..", "parallax")
    os.makedirs(par, exist_ok=True)
    for name, size in (("mid_forest_slopes.png", (2048, 683)), ("cloud_bank.png", (2048, 683)), ("near_rocks_plants.png", (2048, 683))):
        Image.open(os.path.join(SRC, "parallax", name)).resize(size, Image.LANCZOS).save(os.path.join(par, name), optimize=True)
    flat = {role: {"group": g, "color": list(c)} for role, (g, c) in FLAT.items()}
    data = {"note": "v4 Blender material -> mobile group + vertex-colour tint. tint_bins: 16 bins of the piece's l05_rand.",
            "textured": tints, "flat": flat}
    json.dump(data, open(os.path.join(OUT, "..", "mobile_material_map.json"), "w", encoding="utf-8"), indent=1)
    print("mobile textures ->", OUT, "roles:", len(tints) + len(flat))


if __name__ == "__main__":
    main()
