"""Turns the raw Level 05 Luma (uni-1) images into game textures.

Luma only paints colour. Everything physical here is *derived*, not generated:
  * albedo   - de-lit (large-scale lighting gradient divided out) and made
               seamlessly tileable (half-offset cross-fade, both axes);
  * height   - band-passed luminance (an approximation, documented as such);
  * normal   - Sobel-style central differences of that height, OpenGL (+Y up)
               tangent space, which both Blender and Godot expect;
  * rough    - per-material remap of height/luminance/moss masks;
  * alpha    - colour-keyed from the solid backgrounds the prompts asked for.

Usage: python -I tools/textures/process_luma_level05.py RAW_DIR [RAW_DIR...]
Writes to assets/luma/level05/ (textures, parallax/, source/).
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "luma", "level05")
SIZE = 1024


def load(raw_dirs, name):
    for d in raw_dirs:
        for ext in (".jpg", ".png"):
            p = os.path.join(d, name + ext)
            if os.path.exists(p):
                return p, np.asarray(Image.open(p).convert("RGB"), np.float64) / 255.0
    raise FileNotFoundError(name)


def blur(a, sigma):
    """Gaussian blur with wrap-around (FFT), so tileable inputs stay tileable."""
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    k = np.exp(-2.0 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    if a.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(a) * k))
    return np.stack([np.real(np.fft.ifft2(np.fft.fft2(a[..., c]) * k)) for c in range(a.shape[2])], -1)


def luminance(a):
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def make_tileable(a, axes=(1, 0), band=0.22):
    """Cross-fades each edge band with the half-rolled copy (whose seam sits
    in the middle), so opposite edges match exactly."""
    for axis in axes:
        n = a.shape[axis]
        rolled = np.roll(a, n // 2, axis=axis)
        d = np.minimum(np.arange(n), n - 1 - np.arange(n)) / n
        w = smoothstep(0.0, band, d)
        shape = [1] * a.ndim
        shape[axis] = n
        w = w.reshape(shape)
        a = a * w + rolled * (1 - w)
    return a


def delight(a, strength, scale=6.0):
    lum = luminance(a)
    low = blur(lum, a.shape[1] / scale)
    gain = (low.mean() / np.maximum(low, 1e-3)) ** strength
    return np.clip(a * gain[..., None], 0, 1)


def resize(a, size):
    img = Image.fromarray(np.uint8(np.clip(a, 0, 1) * 255 + 0.5))
    return np.asarray(img.resize(size, Image.LANCZOS), np.float64) / 255.0


def height_from(albedo):
    lum = luminance(albedo)
    hp = lum - blur(lum, albedo.shape[1] / 24.0)
    hp = blur(hp, 0.8)
    return (hp - hp.mean()) / (hp.std() + 1e-6)


def normal_from(height, strength):
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5
    dv = (np.roll(height, 1, 0) - np.roll(height, -1, 0)) * 0.5   # +V = image up
    n = np.stack([-dx * strength, -dv * strength, np.ones_like(height)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save_rgb(a, path, quality=90):
    Image.fromarray(np.uint8(np.clip(a, 0, 1) * 255 + 0.5)).save(path, quality=quality, optimize=True)


def save_gray(a, path):
    Image.fromarray(np.uint8(np.clip(a, 0, 1) * 255 + 0.5), "L").save(path, quality=92, optimize=True)


def save_rgba(rgb, alpha, path, size=None):
    img = Image.fromarray(np.uint8(np.clip(np.dstack([rgb, alpha]), 0, 1) * 255 + 0.5), "RGBA")
    if size:
        img = img.resize(size, Image.LANCZOS)
    img.save(path, optimize=True)


def moss_mask(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return smoothstep(0.01, 0.06, g - np.maximum(r, b))


# Per-material roughness remaps: (base, height gain, moss/wet adjustments).
def rough_wood_beam(a, h):
    return 0.66 + 0.10 * np.clip(-h, 0, 3) / 3 - 0.10 * np.clip(h, 0, 3) / 3


def rough_board(a, h):
    return 0.52 + 0.14 * np.clip(-h, 0, 3) / 3 - 0.08 * np.clip(h, 0, 3) / 3


def rough_wet_wood(a, h):
    """Plausible (not measured) wet-timber roughness.

    The Luma image is colour-only.  Dark, broad damp areas are treated as a
    smoother clear water film while open grain remains rough.  This is kept
    deliberately subtle so Godot lighting, rather than baked highlights,
    describes the moisture.
    """
    lum = luminance(a)
    broad = blur(lum, 28)
    damp = smoothstep(0.05, 0.16, broad.mean() - broad)
    grain = np.clip(np.abs(h), 0, 3) / 3
    return np.clip(0.68 - 0.26 * damp + 0.10 * grain, 0.34, 0.82)


def rough_roof(a, h):
    return 0.48 + 0.12 * np.clip(-h, 0, 3) / 3 + 0.3 * moss_mask(a)


def rough_masonry(a, h):
    lum = luminance(a)
    wet = smoothstep(0.04, 0.14, blur(lum, 24) - lum)   # darker damp patches
    return np.clip(0.80 - 0.42 * wet + 0.06 * np.clip(-h, 0, 3) / 3 + 0.1 * moss_mask(a), 0.25, 0.95)


def rough_brass(a, h):
    return 0.30 + 0.10 * np.abs(h) / 3 + 0.12 * smoothstep(0.0, 0.25, 0.42 - luminance(a))


def rough_rock(a, h):
    return np.clip(0.78 + 0.08 * np.clip(-h, 0, 3) / 3 + 0.12 * moss_mask(a), 0.6, 0.97)


def rough_needles(a, h):
    return 0.72 + 0.12 * np.clip(-h, 0, 3) / 3


def rough_peak(a, h):
    snow = smoothstep(0.6, 0.8, luminance(a))
    return np.clip(0.86 - 0.36 * snow + 0.06 * np.clip(-h, 0, 3) / 3, 0.4, 0.95)


def rough_meadow(a, h):
    return 0.82 + 0.1 * np.clip(-h, 0, 3) / 3


MATERIALS = [
    # key, raw name, de-light strength, normal strength, roughness fn, albedo target mean (linear-ish sRGB) or None
    ("wood_beam", "beams_dark_oak", 0.6, 3.5, rough_wood_beam, None),
    ("wet_wood", "wet_alpine_timber_trial", 0.75, 3.0, rough_wet_wood, None),
    ("roof_slate", "roof_tiles_graphite", 0.6, 4.0, rough_roof, None),
    ("stone_masonry", "stone_masonry_wet", 0.5, 4.0, rough_masonry, None),
    # Brass: the photo-like hot spots are lighting, not material - flatten finer.
    ("brass", "brass_bronze", 1.0, 1.2, rough_brass, (0.95, 0.80, 0.46)),   # sRGB mean ~ gold-brass F0
    ("rock_moss", "alpine_rock_moss", 0.5, 5.0, rough_rock, None),
    ("fir_needles", "fir_needles", 0.5, 3.0, rough_needles, None),
    # v4: snowy granite for the peaks, meadow for the summit's flat tops.
    ("peak_rock", "peak_rock_snow", 0.5, 4.5, rough_peak, None),
    ("meadow", "alpine_meadow", 0.5, 2.5, rough_meadow, None),
]

PLANK_GAPS = None   # detected from the image


def board_atlas(a):
    """Deck planks image -> atlas of 8 equal, gap-free single-board bands.
    Each modelled board picks one band, so no fake gaps cross real boards."""
    lum = luminance(a)
    rows = lum.mean(1)
    gaps = [i for i in range(3, len(rows) - 3) if rows[i] == rows[i - 3:i + 4].min() and rows[i] < rows.mean() - 0.1]
    merged = []
    for g in gaps:
        if merged and g - merged[-1] < 20:
            merged[-1] = (merged[-1] + g) // 2
        else:
            merged.append(g)
    bands = []
    for g0, g1 in zip(merged, merged[1:]):
        bands.append(a[g0 + 14:g1 - 14])
    bands = bands[:8]
    band_h = SIZE // len(bands)
    out = []
    for band in bands:
        band = resize(band, (SIZE, band_h))
        band = make_tileable(band, axes=(1,))
        # Slightly worn, darker arrises at each board edge.
        edge = np.ones(band_h)
        edge[:3] = (0.72, 0.82, 0.92)
        edge[-3:] = (0.92, 0.82, 0.72)
        out.append(band * edge[:, None, None])
    return np.concatenate(out, 0), merged, len(bands)


def main(raw_dirs):
    os.makedirs(os.path.join(OUT, "parallax"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "source"), exist_ok=True)
    derived = {}

    for key, raw, delight_k, nstrength, rough_fn, target in MATERIALS:
        _, a = load(raw_dirs, raw)
        a = resize(a, (SIZE, SIZE))
        a = delight(a, delight_k, 40.0 if key == "brass" else 6.0)
        a = make_tileable(a)
        if target is not None:
            a = np.clip(a * (np.array(target) / a.reshape(-1, 3).mean(0)), 0, 1)
        h = height_from(a)
        save_rgb(a, os.path.join(OUT, key + "_albedo.jpg"))
        save_rgb(normal_from(h, nstrength), os.path.join(OUT, key + "_normal.png"))
        save_gray(rough_fn(a, h), os.path.join(OUT, key + "_rough.jpg"))
        derived[key] = {"source": raw, "maps": ["albedo", "normal", "rough"], "delight": delight_k, "normal_strength": nstrength}

    _, planks = load(raw_dirs, "deck_planks")
    planks = delight(planks, 0.4)
    atlas, gaps, nb = board_atlas(planks)
    h = height_from(atlas)
    save_rgb(atlas, os.path.join(OUT, "wood_board_albedo.jpg"))
    save_rgb(normal_from(h, 3.0), os.path.join(OUT, "wood_board_normal.png"))
    save_gray(rough_board(atlas, h), os.path.join(OUT, "wood_board_rough.jpg"))
    derived["wood_board"] = {"source": "deck_planks", "maps": ["albedo", "normal", "rough"], "layout": "%d single-board bands stacked in V (gap rows %s removed)" % (nb, gaps)}

    # Waterfall: tile both ways; alpha from brightness (foam opaque, body translucent).
    _, w = load(raw_dirs, "waterfall_streaks")
    w = resize(w, (512, 1024))
    w = make_tileable(w)
    lum = luminance(w)
    foam = smoothstep(0.55, 0.85, lum)
    alpha = np.clip(0.6 + 0.4 * smoothstep(0.25, 0.8, lum), 0, 1)
    save_rgba(w, alpha, os.path.join(OUT, "waterfall_streaks.png"))
    save_gray(foam, os.path.join(OUT, "waterfall_foam_mask.png"))
    h = height_from(w)
    save_rgb(normal_from(h, 2.0), os.path.join(OUT, "waterfall_normal.png"))
    derived["waterfall_streaks"] = {"source": "waterfall_streaks", "maps": ["rgba (alpha from luminance)", "foam mask", "normal"]}

    # Parallax layers (not tiled; keyed from the solid backgrounds).
    for key, raw, bg in (("near_rocks_plants", "near_rocks_plants", "white"), ("mid_forest_slopes", "mid_forest_slopes", "white"), ("cloud_bank", "cloud_bank_black", "black")):
        _, a = load(raw_dirs, raw)
        if bg == "white":
            ref = np.median(a[:8].reshape(-1, 3), 0)
            d = np.abs(a - ref).max(-1)
            alpha = smoothstep(0.04, 0.16, d)
            alpha = np.maximum(alpha, smoothstep(0.04, 0.16, blur(d, 0.7)))
            rgb = np.clip((a - ref * (1 - alpha[..., None])) / np.maximum(alpha[..., None], 0.05), 0, 1)
            # Generated images carry a 1-2 px border row; it must not key as opaque.
            alpha[:4] = 0.0
        else:
            m = a.max(-1)
            alpha = smoothstep(0.03, 0.85, m) ** 0.85
            rgb = np.clip(a / np.maximum(alpha[..., None], 0.05), 0, 1)
        save_rgba(rgb, alpha, os.path.join(OUT, "parallax", key + ".png"), size=(2048, 683))
        derived[key] = {"source": raw, "maps": ["rgba (alpha keyed from %s background)" % bg]}
    _, sky = load(raw_dirs, "sky_clouds")
    save_rgb(resize(sky, (2048, 683)), os.path.join(OUT, "parallax", "sky_clouds.jpg"), quality=90)
    derived["sky_clouds"] = {"source": "sky_clouds", "maps": ["rgb"]}

    # Untouched originals for provenance (Godot must not import them).
    gens = {}
    previous_provenance = os.path.join(OUT, "PROVENANCE.json")
    if os.path.exists(previous_provenance):
        try:
            gens.update(json.load(open(previous_provenance, encoding="utf-8")).get("generations", {}))
        except (OSError, ValueError, TypeError):
            pass
    for d in raw_dirs:
        for f in os.listdir(d):
            if f.endswith((".jpg", ".png")):
                source_file = os.path.abspath(os.path.join(d, f))
                target_file = os.path.abspath(os.path.join(OUT, "source", f))
                if source_file != target_file:
                    shutil.copy2(source_file, target_file)
        meta = os.path.join(d, "_generations.json")
        if os.path.exists(meta):
            gens.update(json.load(open(meta, encoding="utf-8")))
    open(os.path.join(OUT, "source", ".gdignore"), "w").close()
    provenance = {
        "provider": "Luma Agents API (agents.lumalabs.ai/v1)",
        "model": "uni-1",
        "generated": "2026-10-30",
        "credits_each": 30,
        "credits_total": 30 * len(gens),
        "generations": gens,
        "reused_from_level04": {
            "alps_far": "assets/luma/level04/alps_far.jpg (far parallax / backdrop)",
            "forest_ridge": "assets/luma/level04/forest_ridge.png (distant forest band)",
            "water_foam": "assets/luma/level04/water_foam.jpg (pool/channel surface colour + foam)",
        },
        "derived_maps": derived,
        "derivation_note": "Normal, roughness, alpha and foam maps are computed by tools/textures/process_luma_level05.py "
                           "from the colour images (band-passed luminance height, central differences, per-material remaps). "
                           "They are plausible approximations for stylised rendering, not scanned/measured physical data.",
    }
    json.dump(provenance, open(os.path.join(OUT, "PROVENANCE.json"), "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    print("wrote", OUT, "materials:", ", ".join(derived))


if __name__ == "__main__":
    main(sys.argv[1:])
