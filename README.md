# Marble Labyrinth — Clockwork Prototype

An original Android-first Godot 4.6.3 physics puzzle. The player tilts detailed miniature labyrinths and guides a real `RigidBody3D` marble through physical hazards and linked mechanical puzzles.

This repository contains two playable development levels and CI pipelines for Android test APKs. It has not been published to Google Play.

## Levels

### Level 1 — The Brass Workshop

The original level remains fully playable: a dark-metal and brass maze with wind, magnetic attraction, a reset trap and a goal. It introduces board tilt, camera movement and the marble's inertia.

### Level 2 — The Clockwork Factory

A multi-stage miniature machine built from steel decks, brass gears, moving shafts, lamps and elevated factory structures. Its route is deliberately sequential:

1. Time a path between two counter-rotating physical gears.
2. Roll onto the lever plate to lower a collidable bridge.
3. Cross the bridge and board an oscillating transfer platform over a real floor gap.
4. Ride the lift to the elevated factory deck.
5. Trigger the timed pressure plate and pass the gate before it closes.
6. Avoid the final timing gear and reach the goal.

Missing floor sections are actual gaps rather than painted hazards. Falling into the machinery resets the level.

## Physics and presentation

- The marble is always a live `RigidBody3D` with continuous collision detection, tuned friction, damping and inertia.
- Tilting decks use a physics-synchronised `AnimatableBody3D`.
- Gears have individual hub and tooth collision shapes; bridge, transfer platform, lift, gate and shafts are moving `AnimatableBody3D` objects with real colliders.
- Level 1 wind and magnet forces remain board-local and work while the board is tilted.
- Geometry and materials are procedural: layered steel decks, brass rails, fasteners, gear teeth, shafts, lamps, emissive controls, warm lighting and shadows.
- No paid or third-party art assets are used.

## Controls

| Platform | Action | Control |
| --- | --- | --- |
| Windows | Tilt board | Arrow keys |
| Windows | Orbit camera | Hold right mouse button and drag |
| Windows | Zoom | Mouse wheel |
| Android | Tilt board | Phone motion sensor or drag on the left half |
| Android | Orbit camera | Drag on the right half |
| Both | Change Auto/Touch/Sensor mode | **Control** HUD button or `G`/`M` |
| Both | Calibrate sensor | **Calibrate** HUD button or `C` |
| Both | Reset level | **Reset** HUD button or `R` |
| Testing | Select level | HUD selector, `1`, `2`, or `L` |
| Completion | Continue | Completion button, `N`, or Enter |

For sensor play, hold the phone in a comfortable neutral position and press **Calibrate**. The HUD uses viewport anchors and display-safe-area margins, and rearranges its top controls on narrower viewports.

## Architecture

```text
project.godot                                  Project settings and entry point
scenes/main.tscn                               Canonical game scene
scripts/main.gd                                Shared game, input, HUD and level flow
scripts/components/clockwork_mechanisms.gd    Reusable moving physical mechanisms
scripts/levels/level_01.gd                     Brass Workshop data
scripts/levels/level_02.gd                     Clockwork Factory data
scenes/labs/physics_lab.tscn                   P1 material and force laboratory
scenes/labs/water_lab.tscn                     P2 conservative hydraulic laboratory
scripts/balls/physics_ball.gd                   Reusable material-driven RigidBody3D
scripts/physics/                                Contact profiles and force fields
scripts/water/                                  Reservoir graph, buoyancy and water visual
tests/smoke_test.gd                            Level 1 regression test
tests/level_02_smoke_test.gd                   Level 2 and transition test
tests/physics_lab_test.gd                      P1 physical integration test
tests/water_network_test.gd                    P2 conservation/valve/pump test
tests/water_buoyancy_test.gd                   P2 rigid-body water forces test
tests/water_lab_test.gd                        P2 scene and reset test
```

Both levels use the same controller and marble. Level files contain layout and tuning data; the mechanism component owns reusable physical behavior. Adding a later clockwork level does not require copying `main.gd`.

## Run and verify

Open the project with the standard Godot 4.6.3 editor:

```bash
godot --path . --editor
```

Headless validation:

```bash
godot --headless --path . --editor --quit
godot --headless --path . --debug --fixed-fps 60 --quit-after 600
godot --headless --path . --fixed-fps 60 --script res://tests/smoke_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/level_02_smoke_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/physics_lab_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/water_network_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/water_buoyancy_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/water_lab_test.gd
```

The tests cover both level definitions, scene loading, the rigid marble, static floor and wall collisions, tilt and movement, Level 1 forces and hazards, gear teeth, rotating shafts, a platform carrying the marble, bridge, lift, timer gate, mechanism reset, completion UI and Level 1 → Level 2 transition. P1 additionally checks seven ball profiles, nine surfaces, pair-dependent stopping and bounce, wind, selective magnetism and zero gravity using real rigid bodies.

## Android debug APK

The repository includes an **Android Debug APK** GitHub Actions workflow. It installs Android SDK 36, downloads Godot 4.6.3 and its official export templates, verifies the Godot downloads against the published SHA-512 values, runs both level tests plus Physics Lab, builds and verifies a signed debug APK, and publishes it as a workflow artifact.

To download it:

1. Open **Actions → Android Debug APK** in this GitHub repository.
2. Open the latest successful run for `main` or the Android build branch.
3. Find **Artifacts** at the bottom of the run summary.
4. Download **MarbleLabyrinth-debug-apk** and unzip it.
5. Compare the APK with `MarbleLabyrinth-debug.apk.sha256`, then install `MarbleLabyrinth-debug.apk` on the phone.

Each GitHub Actions run now increases the Android `versionCode` and `versionName` automatically for both debug and stable APK workflows.

**Important:** Debug CI creates an ephemeral signing key on every run. These APKs are for one-off testing, NOT install-over updates. For update-compatible builds, use **Actions → Android Stable APK**, after configuring the owner's permanent keystore via [Russian signing guide](docs/ANDROID_UPDATE_SIGNING_RU.md). That stable workflow increments Android versionCode and uses one consistent signer. A previously installed ephemeral-debug APK must be uninstalled once when switching to stable-signed APKs.

The debug package ID is `com.kirilsjanssen.marblelabyrinth`. The export targets Android SDK 36 and includes ARM64 plus 32-bit ARM libraries. The APK, generated debug keystore and Android SDK are build outputs and are never committed.

For a configured local machine, the same validation and export can be run with:

```bash
tools/build_android_debug.sh
```

## Android work still requiring physical devices

- Confirm gravity-axis direction and calibration feel in landscape orientation.
- Test simultaneous tilt and camera multi-touch across different screen aspect ratios.
- Verify cutouts, rounded corners and safe-area placement on representative devices.
- Tune touch sensitivity, moving-platform timing and gate duration using real play sessions.
- Measure frame rate, thermals, battery use and shadow cost on low/mid-range hardware.
- Test pause/resume, focus loss and device rotation behavior.
- Verify real-phone behavior, persistent-signing setup and compatibility of updates.

Do not use an Android emulator for this project, commit signing keys, or publish to Google Play without the owner's explicit approval.
