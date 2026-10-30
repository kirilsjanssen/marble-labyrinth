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

### Level 3 — Vertical Liftworks

One continuous three-tier board (deck tops at 0.02 / 1.42 / 2.82) joined by a physical three-stop lift:

1. **Tier 1:** roll over the lever plate to lower the pit bridge, time the rotating sweeper and gear, cross the narrow bridge, then shove the wooden `PuzzleShapeBody` cube into the pocket on the POWER plate.
2. Board the lift from the east lane. Once the marble rests on the deck, the lift rises to tier 2 (it stays locked without power).
3. **Tier 2:** a low corridor runs under tier 3. Pass the rotating paddle shaft, the choke and two cycling shutters (wait for both to drop), then ride the transfer platform across the gap to the open west deck and pull the UPPER RELEASE lever.
4. Return through the corridor and ride the lift to tier 3.
5. **Tier 3:** hit the timer pad and pass the gate before it closes, or take the secret gear run along the north wall. Finish in the seated goal socket.

The lift deck is an `AnimatableBody3D` with side lips and deck doors. Each landing has its own gate, and call pads summon the lift. It carries any rigid body, so cubes and pyramids can ride too. Falling into the tier-2 gap returns the marble to the tier-2 landing without undoing solved mechanisms.

### Level 4 — Alpine Watermill

A three-tier watermill board (deck tops 0.02 / 1.42 / 2.82). Every mechanism hangs off one conservative `WaterNetwork`:

```text
cistern --sluice--> race --wheel buckets--> stream --ram pump--> cistern
cistern --diverter--> float tank --drain--> stream
```

1. **Mountain stream (tier 1):** pull the SLUICE lever. Water now runs down the aqueduct onto the overshot wheel. Pass the stream paddle and cross the wooden bridge over the mill channel; the channel has real buoyancy, drag and current, and a fall returns the marble just after the lever. A secret millrace walkway bypasses the bridge.
2. **The wheel turns only from the simulated flux** (NO WATER / LOW FLOW / WORKING / OVERLOAD). Its bevel gears and line shaft wind the lift winch: the lift climbs only while the wheel works, and it always descends under a brake, so it can never strand the marble.
3. Shove the wooden cube onto the plate to open the MILL GATE, then ride the lift to tier 2.
4. **Mill machinery (tier 2):** a camshaft and two timed sluice boards guard the corridor under the terrace. Here the smart camera switches to CHASE. Cross the float pontoon (flush at tier 2) and pull the DIVERTER. Water leaves the wheel, the tank fills, and the pontoon, released by the marble's weight, floats it up to tier 3.
5. **Alpine millhouse (tier 3):** time the sweeper, hit the timer pad and pass the gate (or take the secret terrace run), then settle into the goal socket.

Water visuals (`shaders/flow_water.gdshader`, `scripts/water/flow_water_surface.gd`) scroll two detail layers whose speed and direction come from the live flux. Surfaces of the cistern, tank and pool follow the simulated volume. Waterfalls fall at the rate of their channel.

`scripts/environment/alpine_parallax_controller.gd` builds the surroundings. There are four cylindrical far layers that follow the camera by different amounts, each with a cap on how far it can shift: Luma snow peaks, haze ridges, and two Luma forest-ridge bands. Nearer layers are real 3D geometry: boulders, firs, moss and shrubs (MultiMesh), granite cliffs with waterfalls, and a mountain river.

**Luma assets** live in `assets/luma/level04/`, with prompts listed in `PROVENANCE.json`. They were generated with the Luma Agents API (`uni-1`, 5 images, 150 credits): a far Alps panorama, a forest-ridge band keyed to alpha, wood planks, wet stone, and water/foam detail. The Luma key is read from the environment only and is not stored anywhere in the project.

**Engineering fixes found by the physical playthrough (apply to levels 2–4):**
- Mechanism bodies nested under the tilting board now use `sync_to_physics = false`. With `true`, tilting the board made the physics server write back stale transforms, so a parked lift deck sank about 0.8 units and dropped the marble.
- The power cube is 0.45 (was 0.55): a rotated 0.55 cube wedged diagonally in the 0.75 lane.
- A fascia beam under the tier-3 edge closes a sight slot above the tier-2 rail, so the auto camera no longer stays in OVERVIEW while only a sliver of the marble is visible.

### Level 5 — Alpine Cascade

The first level built from finished art: the Blender v4 model (`tools/blender/build_level05.py`) exported as an optimised mobile GLB (`assets/levels/level05/`) and mounted on the tilting board by `scripts/levels/level05_visuals.gd`. Its 206 box colliders (decks with their railing openings, bridges, walls with arch openings, flumes, lift tower) become shapes of the board itself, so the marble, the crate and the smart camera all see the same geometry. Deck tops 0 / 1.4 / 2.8 m; the marble is a live `RigidBody3D` all the way.

```text
pond --headgate--> upper channel --spill notches--> middle channel --shutter--> MILL wheel -> pit -> stream
pond --headgate--> upper pool --pool sluice--> LIFT wheel -> valley --ram pump--> pond
spring --stream sluice--> stream (stream wheel) --spillway--> valley --spring--> spring
```

1. Roll over the brass **start ring**: the headgate opens and water reaches every channel, fall and wheel (all still until then).
2. Push the **crate** across the spillway bridge onto the **plate**: the lift interlock releases.
3. The **east wheel** turns only from the pool sluice flux; its bevel train (10:10, 10:10, 8:16) winds the lift winch at half the wheel angle. The **three-stop lift** carries the marble to the workshop tier; the GLB cage and doors ride the physical deck.
4. Wind the **terrace crank** (pinion 9 → pillar crown 22): it releases the lift's top stop. Ride up, cross the pool and valve decks and settle in the **goal socket**.
5. **Secret:** the arch off the start lane opens into a hidden corridor (the camera switches to CHASE); its ring and the alcove lever free the top stop without the crank.

The mill wheel drives the millstone through the pit wheel and wallower (16:7). The diverter on the valve deck closes the spill notches, so the mill stops and the lift wheel gets the water. Every water sheet, fall and spray reads its own live flux, and the volume of the closed loop is conserved. The far Alps are a 360° panorama rendered from the Blender scene (`PanoramaSkyMaterial`), correct for any camera yaw including CHASE. Forest, cloud and near-rock rings come from the Luma parallax images. **GFX** (or `Q`) toggles the LOW and HIGH tiers.

**Engineering fixes found by the Level 5 physical playthrough:**
- The cube plate sat in the middle of the only lane to the lift, so the parked crate left 0.59 m either side of it for a 0.66 m marble. It now sits on the north side (`build_level05.py`, v5).
- Stacked cargo slid into the lanes under the 15° tilt, so it is now lashed to its decks. Only the puzzle crate is free.
- A sharp-edged crate collider snagged on the internal edge between two floor boxes; it now uses a chamfered convex hull, as modelled.

### Smart camera

`scripts/camera/smart_camera_controller.gd` owns camera modes, so `main.gd` only supplies the overview orbit pose:

- **OVERVIEW / ORBIT:** the classic tilted overview. Dragging on the right half of the screen orbits it.
- **CHASE:** behind and slightly above the marble, looking down the corridor.
- On Level 3 the camera checks every frame, using physics rays against the walls and decks, whether the overview can see the marble. After 0.35 s hidden it blends into CHASE, and after 0.9 s visible again it blends back. Short occlusions never flip the view.
- The chase camera starts on the board axis that has room behind the marble and is nearest the overview direction, so screen-relative controls stay predictable. It turns at a limited rate, ignores short reverses and stops, is pulled in front of walls and ceilings, and moves closer when a moving part would block the shot.
- **CAM** (or **V**) cycles AUTO → TOP → CHASE. A manual choice always wins over auto. The HUD shows `CAMERA: OVERVIEW / ORBIT / CHASE`.

Level 3 visuals are procedural Godot geometry and materials.

## Physics and presentation

- The marble is always a live `RigidBody3D` with continuous collision detection, tuned friction, damping and inertia.
- Tilting decks use a physics-synchronised `AnimatableBody3D`.
- Gears have individual hub and tooth collision shapes; bridge, transfer platform, lift, gate and shafts are moving `AnimatableBody3D` objects with real colliders.
- Level 1 wind and magnet forces remain board-local and work while the board is tilted.
- Geometry and materials are procedural: layered steel decks, brass rails, fasteners, gear teeth, shafts, lamps, emissive controls, warm lighting and shadows.
- No paid or third-party art assets are used.

## Goal confirmation and puzzle object shapes

Reaching the goal requires more than clipping the side of the glowing ring. The centred rigid marble must remain inside the socket within a tight horizontal and vertical tolerance, with low enough speed, for a short dwell time. A broad `Area3D` overlap alone cannot finish a level. Restart/level switching clears the socket state; regressions cover both L01/L02.

The board-tilt thumb now has a **180 px diameter** on standard landscape devices (150% of its previous 120 px size) with responsive scaling on shorter viewports.

For later puzzle levels, `PuzzleShapeBody` supports real **cube** and **pyramid** `RigidBody3D` bodies. Cubes have `BoxShape3D` colliders; pyramids use real convex colliders. They reuse P1 material profiles and the existing wind/magnetic/gravity/adhesion fields. `scenes/labs/shape_lab.tscn` demonstrates a magnetic steel cube, wooden pyramid and existing sphere. Water forces for non-spherical shapes and authoring full cube/pyramid gameplay levels remain future tasks.

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
| Testing | Select level | HUD selector, `1`–`5`, or `L` |
| Level 5 | Graphics tier LOW / HIGH | **GFX** HUD button or `Q` |
| Completion | Continue | Completion button, `N`, or Enter |

**Important:** On Android, dragging the **left half tilts the entire board**. The ball is never moved directly: gravity, collisions and inertia make it roll. Dragging the **right half changes the camera only**. After rotating the camera, left drag is interpreted relative to the current screen view so left/right feel consistent.

Android now defaults to **BOARD: DRAG** rather than mixed Auto mode. Tap the BOARD mode button to select finger drag, phone sensors or auto. The sensor option requires **Calibrate**; the calibration button is hidden in finger-only mode. The left corner shows a visible, non-intercepting gesture thumb that follows actual board tilt. **VIEW** restores the default camera angle; **?** opens the controls tutorial, which is also shown once on first Android launch. User-facing onboarding/help text is available in RU, DE and EN based on system locale.

For sensor play, hold the phone in a comfortable neutral position and press **Calibrate**. The HUD uses viewport anchors and display-safe-area margins, and rearranges its top controls on narrower viewports.

## Architecture

```text
project.godot                                  Project settings and entry point
scenes/main.tscn                               Canonical game scene
scripts/main.gd                                Shared game, input, HUD and level flow
scripts/components/clockwork_mechanisms.gd    Reusable moving physical mechanisms
scripts/levels/level_01.gd                     Brass Workshop data
scripts/levels/level_02.gd                     Clockwork Factory data
scripts/levels/level_03.gd                     Vertical Liftworks data and route
scripts/mechanisms/vertical_lift.gd            Reusable multi-stop physical lift
scripts/mechanisms/liftworks_mechanisms.gd     Level 3 mechanisms (extends clockwork)
scripts/camera/smart_camera_controller.gd      Overview/orbit/chase camera manager
scripts/levels/level_04.gd                     Alpine Watermill data, hydraulics and route
scripts/mechanisms/watermill_mechanisms.gd     Water network, wheel, pontoon, mill gate
scripts/mechanisms/water_wheel.gd              Flux-driven wheel with gear train and states
scripts/environment/alpine_parallax_controller.gd  Layered Alpine parallax surroundings
scripts/water/flow_water_surface.gd            Flux-driven animated water sheet
scripts/levels/level_05.gd                     Alpine Cascade data, hydraulics and route
scripts/levels/level05_visuals.gd              GLB scene, colliders, MultiMesh, sky, parallax, water
scripts/mechanisms/level05_mechanisms.gd       Water network, wheels/gear trains, lift skin, crank
shaders/level05_water.gdshader                 Two-layer flux-driven channel water
shaders/level05_waterfall.gdshader             Waterfall body / foam / spray layers
assets/levels/level05/                         Mobile GLB, colliders, vegetation, parallax
shaders/flow_water.gdshader                    GL Compatibility water / waterfall shader
shaders/parallax_layer.gdshader                Seamless cylindrical backdrop layer
assets/luma/level04/                           Luma-generated textures and panoramas
scenes/labs/physics_lab.tscn                   P1 material and force laboratory
scenes/labs/water_lab.tscn                     P2 conservative hydraulic laboratory
scenes/labs/shape_lab.tscn                     Reusable cube/pyramid/ball physics laboratory
scripts/balls/physics_ball.gd                   Reusable material-driven RigidBody3D
scripts/physics/                                Contact profiles and force fields
scripts/water/                                  Reservoir graph, buoyancy and water visual
tests/smoke_test.gd                            Level 1 regression test
tests/level_02_smoke_test.gd                   Level 2 and transition test
tests/level_03_smoke_test.gd                   Level 3 tiers, lift, route and camera test
tests/level_04_smoke_test.gd                   Level 4 PHYSICAL playthrough, water, parallax
tests/level_05_smoke_test.gd                   Level 5 PHYSICAL playthrough on the GLB model
tests/level05_visuals_test.gd                  Level 5 GLB import, pivots, textures, colliders
tests/physics_lab_test.gd                      P1 physical integration test
tests/water_network_test.gd                    P2 conservation/valve/pump test
tests/water_buoyancy_test.gd                   P2 rigid-body water forces test
tests/water_lab_test.gd                        P2 scene and reset test
```

Goal and shape-regression tests run in Android CI: `tests/goal_socket_test.gd` and `tests/shape_lab_test.gd`.

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
godot --headless --path . --fixed-fps 60 --script res://tests/level_03_smoke_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/level_04_smoke_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/level_05_smoke_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/level05_visuals_test.gd
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
