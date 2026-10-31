#!/usr/bin/env python3
"""Build reproducible Level 06 PBR texture sets.

The Luma image is used only as an authored albedo source. Roughness and normal
maps are deliberately derived, not claimed to be physically measured scans.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/levels/level06/textures/source/luma_dark_orbital_metal.png"
OUT = ROOT / "assets/levels/level06/textures/pbr"


def seamless_edges(rgb: np.ndarray, width: int = 96) -> np.ndarray:
    result = rgb.astype(np.float32).copy()
    h, w, _ = result.shape
    for i in range(width):
        t = (i + 1) / (width + 1)
        a = result[:, i].copy()
        b = result[:, w - 1 - i].copy()
        mix = (a + b) * 0.5
        result[:, i] = a * t + mix * (1.0 - t)
        result[:, w - 1 - i] = b * t + mix * (1.0 - t)
    for i in range(width):
        t = (i + 1) / (width + 1)
        a = result[i].copy()
        b = result[h - 1 - i].copy()
        mix = (a + b) * 0.5
        result[i] = a * t + mix * (1.0 - t)
        result[h - 1 - i] = b * t + mix * (1.0 - t)
    return np.clip(result, 0, 255).astype(np.uint8)


def derived_maps(rgb: np.ndarray, rough_base: float, normal_strength: float) -> tuple[np.ndarray, np.ndarray]:
    linear = rgb.astype(np.float32) / 255.0
    gray = linear[..., 0] * 0.2126 + linear[..., 1] * 0.7152 + linear[..., 2] * 0.0722
    local = gray - (
        gray
        + np.roll(gray, 1, 0)
        + np.roll(gray, -1, 0)
        + np.roll(gray, 1, 1)
        + np.roll(gray, -1, 1)
    ) / 5.0
    rough = np.clip(rough_base + local * 1.8 + (0.5 - gray) * 0.12, 0.18, 0.92)
    dx = (np.roll(gray, -1, 1) - np.roll(gray, 1, 1)) * normal_strength
    dy = (np.roll(gray, -1, 0) - np.roll(gray, 1, 0)) * normal_strength
    normal = np.dstack((-dx, -dy, np.ones_like(gray)))
    normal /= np.maximum(np.linalg.norm(normal, axis=2, keepdims=True), 1e-6)
    normal = ((normal * 0.5 + 0.5) * 255.0).astype(np.uint8)
    return (rough * 255.0).astype(np.uint8), normal


def save_set(name: str, rgb: np.ndarray, rough_base: float, normal_strength: float) -> dict[str, str]:
    rough, normal = derived_maps(rgb, rough_base, normal_strength)
    albedo_path = OUT / f"{name}_albedo.jpg"
    rough_path = OUT / f"{name}_roughness.png"
    normal_path = OUT / f"{name}_normal.png"
    Image.fromarray(rgb, "RGB").save(albedo_path, quality=95, subsampling=0)
    Image.fromarray(rough, "L").save(rough_path)
    Image.fromarray(normal, "RGB").save(normal_path)
    return {
        "albedo": albedo_path.relative_to(ROOT).as_posix(),
        "roughness": rough_path.relative_to(ROOT).as_posix(),
        "normal": normal_path.relative_to(ROOT).as_posix(),
        "map_note": "roughness and normal are derived artist maps, not measured material data",
    }


def procedural_brushed(size: int, base: tuple[int, int, int], seed: int, axis: int = 1) -> np.ndarray:
    rng = np.random.default_rng(seed)
    h = w = size
    fine = rng.normal(0.0, 1.0, (h, w))
    kernel = 31
    acc = np.zeros_like(fine)
    for offset in range(-kernel, kernel + 1):
        acc += np.roll(fine, offset, axis=axis)
    acc /= kernel * 2 + 1
    acc = (acc - acc.mean()) / max(acc.std(), 1e-6)
    y, x = np.mgrid[0:h, 0:w]
    panel = ((x // (size // 4) + y // (size // 4)) % 2) * 0.035
    base_arr = np.array(base, dtype=np.float32) / 255.0
    rgb = base_arr[None, None, :] * (1.0 + acc[..., None] * 0.055 + panel[..., None])
    return np.clip(rgb * 255.0, 0, 255).astype(np.uint8)


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"Missing Luma source: {SOURCE}")
    OUT.mkdir(parents=True, exist_ok=True)
    source_image = Image.open(SOURCE).convert("RGB").resize((2048, 2048), Image.Resampling.LANCZOS)
    source_image = ImageEnhance.Color(source_image).enhance(0.86)
    source_image = ImageEnhance.Contrast(source_image).enhance(0.94)
    source_image = ImageEnhance.Brightness(source_image).enhance(1.22)
    dark_rgb = seamless_edges(np.asarray(source_image), 112)

    manifest = {
        "dark_orbital_metal": save_set("dark_orbital_metal", dark_rgb, 0.50, 3.2),
        "brushed_titanium": save_set(
            "brushed_titanium", procedural_brushed(1024, (112, 126, 143), 6061, axis=1), 0.31, 1.8
        ),
        "aged_bronze": save_set(
            "aged_bronze", procedural_brushed(1024, (132, 76, 30), 6062, axis=0), 0.38, 2.1
        ),
        "matte_steel": save_set(
            "matte_steel", procedural_brushed(1024, (64, 72, 84), 6063, axis=1), 0.62, 1.2
        ),
        "luma": {
            "generation_id": "3bd79b45-443f-4224-90e7-4c1006bba3f1",
            "model": "uni-1",
            "type": "image",
            "price_usd_at_generation": 0.0404,
            "source": SOURCE.relative_to(ROOT).as_posix(),
            "prompt": "Seamless tileable PBR albedo source of dark aerospace structural metal panels for a futuristic orbital engineering station, graphite-black titanium alloy, subtle brushed grain, fine machined panel seams, restrained edge wear, sparse micro-scratches, clean maintained spacecraft, orthographic flat material scan, uniform diffuse illumination, no directional shadows, no specular highlights, no rust, no dirt piles, no bolts, no labels, no text, no perspective, physically plausible game material",
        },
    }
    manifest_path = OUT / "LEVEL06_TEXTURE_MANIFEST.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"sets": 4, "output": str(OUT), "manifest": str(manifest_path)}))


if __name__ == "__main__":
    main()
