#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"

if [[ -z "$android_sdk" ]]; then
  echo "ANDROID_SDK_ROOT or ANDROID_HOME must point to an Android SDK." >&2
  exit 1
fi

build_tools_dir="$(find "$android_sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
if [[ -z "$build_tools_dir" ]]; then
  echo "Android SDK build-tools are missing." >&2
  exit 1
fi

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$project_root/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$project_root/builds"

cd "$project_root"
"$godot_bin" --headless --path . --editor --quit
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/smoke_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/level_02_smoke_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/level_03_smoke_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/mobile_controls_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/physics_lab_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/water_network_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/water_buoyancy_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/water_lab_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/goal_socket_test.gd
"$godot_bin" --headless --path . --fixed-fps 60 --script res://tests/shape_lab_test.gd
"$godot_bin" --headless --path . --export-debug "Android Debug" builds/MarbleLabyrinth-debug.apk

apk="$project_root/builds/MarbleLabyrinth-debug.apk"
test -s "$apk"
unzip -tq "$apk"
"$build_tools_dir/apksigner" verify --verbose --print-certs "$apk"
"$build_tools_dir/aapt2" dump badging "$apk" > "$project_root/builds/MarbleLabyrinth-debug.badging.txt"
grep -Fq "package: name='com.kirilsjanssen.marblelabyrinth'" "$project_root/builds/MarbleLabyrinth-debug.badging.txt"
grep -Fq "targetSdkVersion:'36'" "$project_root/builds/MarbleLabyrinth-debug.badging.txt"
sha256sum "$apk" > "$project_root/builds/MarbleLabyrinth-debug.apk.sha256"

ls -lh "$apk"
cat "$project_root/builds/MarbleLabyrinth-debug.apk.sha256"
