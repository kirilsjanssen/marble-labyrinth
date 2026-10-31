"""Build the v5 Level 05 panorama variants used by Godot.

The source panorama is the project's own Blender render.  This pass performs
only colour finishing and a symmetric wrap-edge blend: it does not invent
mountains or replace the 360-degree geometry.  The high and low outputs keep
the original 2:1 equirectangular projection.
"""
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PARALLAX = ROOT / "assets" / "levels" / "level05" / "parallax"


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1.0 / 2.4) - 0.055)


def smoothstep(t):
    return t * t * (3.0 - 2.0 * t)


def wrap_blend(rgb, width=128):
    """Make the equirectangular 0/360 boundary identical without a hard blur."""
    out = rgb.copy()
    width = min(width, rgb.shape[1] // 8)
    for x in range(width):
        t = smoothstep(x / max(1.0, width - 1.0))
        pair = (rgb[:, x] + rgb[:, -1 - x]) * 0.5
        out[:, x] = pair * (1.0 - t) + rgb[:, x] * t
        out[:, -1 - x] = pair * (1.0 - t) + rgb[:, -1 - x] * t
    out[:, -1] = out[:, 0]
    return out


def finish(source, target, size):
    image = Image.open(source).convert("RGB")
    if image.size != size:
        image = image.resize(size, Image.Resampling.LANCZOS)
    rgb = np.asarray(image, np.float64) / 255.0
    linear = srgb_to_linear(rgb) * 0.90
    # Shoulder compression retains snow/cloud detail under Godot's filmic map.
    linear = linear / (1.0 + linear * 0.32)
    luma = linear[..., 0] * 0.2126 + linear[..., 1] * 0.7152 + linear[..., 2] * 0.0722
    linear = luma[..., None] + (linear - luma[..., None]) * 0.88
    result = wrap_blend(linear_to_srgb(linear), max(48, size[0] // 32))
    Image.fromarray(np.uint8(result * 255.0 + 0.5), "RGB").save(target, quality=92, subsampling=0, optimize=True)
    edge_mae = float(np.abs(result[:, 0] - result[:, -1]).mean())
    print(f"{target.name}: {size[0]}x{size[1]}, seam_mae={edge_mae:.6f}")


def main():
    source = PARALLAX / "sky_panorama.jpg"
    finish(source, PARALLAX / "sky_panorama_v2.jpg", (4096, 2048))
    finish(source, PARALLAX / "sky_panorama_v2_low.jpg", (2048, 1024))


if __name__ == "__main__":
    main()
