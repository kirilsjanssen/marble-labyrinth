#!/usr/bin/env bash
set -euo pipefail

# This build is for install-over updates: it requires a stable owner-managed key.
# NEVER generate a new signing key on a CI runner as part of this script.
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?Stable signing keystore path required}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?Signing alias required}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?Signing password required}"
test -s "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH"
test -n "$android_sdk"
build_tools_dir="$(find "$android_sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
test -n "$build_tools_dir"

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$project_root/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$project_root/builds"
cd "$project_root"

"$godot_bin" --headless --path . --editor --quit
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/smoke_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/level_02_smoke_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/level_03_smoke_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/level_04_smoke_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/mobile_controls_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/physics_lab_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/water_network_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/water_buoyancy_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/water_lab_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/goal_socket_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/shape_lab_test.gd
"$godot_bin" --headless --path . --export-release "Android Stable" builds/MarbleLabyrinth-stable.apk

apk="$project_root/builds/MarbleLabyrinth-stable.apk"
test -s "$apk"
unzip -tq "$apk"
"$build_tools_dir/apksigner" verify --verbose "$apk"
"$build_tools_dir/aapt2" dump badging "$apk" > "$project_root/builds/MarbleLabyrinth-stable.badging.txt"
grep -Fq "package: name='com.kirilsjanssen.marblelabyrinth'" "$project_root/builds/MarbleLabyrinth-stable.badging.txt"
grep -Fq "targetSdkVersion:'36'" "$project_root/builds/MarbleLabyrinth-stable.badging.txt"
sha256sum "$apk" > "$project_root/builds/MarbleLabyrinth-stable.apk.sha256"

# Public certificate digest, NOT the signing private key.
"$build_tools_dir/apksigner" verify --print-certs "$apk" \
  | grep 'Signer #1 certificate SHA-256 digest:' \
  > "$project_root/builds/MarbleLabyrinth-signing-certificate.txt"
cat "$project_root/builds/MarbleLabyrinth-signing-certificate.txt"
ls -lh "$apk"
