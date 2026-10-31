"""Android import presets for every Level 05 texture (.import files).

Godot imports textures extracted from a GLB as Lossless by default; on a phone
they must be VRAM compressed (ETC2/ASTC, project setting import_etc2_astc) with
mipmaps, and normal maps flagged so the compressor keeps their precision.
Run after one editor/headless import has created the .import files, then
import again:  python -I tools/textures/set_level05_import_presets.py [project]
"""
import glob
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE = os.path.join(ROOT, "assets", "levels", "level05")


def set_param(text, key, value):
    pattern = re.compile(r"^%s=.*$" % re.escape(key), re.M)
    line = "%s=%s" % (key, value)
    return pattern.sub(line, text) if pattern.search(text) else text.rstrip("\n") + "\n" + line + "\n"


changed = 0
for path in glob.glob(os.path.join(BASE, "**", "*.import"), recursive=True):
    text = open(path, encoding="utf-8").read()
    if 'importer="texture"' not in text:
        continue
    name = os.path.basename(path).lower()
    text = set_param(text, "compress/mode", 2)            # VRAM Compressed
    text = set_param(text, "mipmaps/generate", "true")
    text = set_param(text, "compress/normal_map", 1 if "normal" in name else 2)
    text = set_param(text, "detect_3d/compress_to", 0)
    open(path, "w", encoding="utf-8", newline="\n").write(text)
    changed += 1
print("Level05 texture import presets:", changed)
