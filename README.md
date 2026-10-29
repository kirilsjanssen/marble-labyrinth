# Marble Labyrinth — Cloud Starter 0.1.0

Original compact Godot 4.x 3D physics prototype for Android / Google Play.
**A development starter, not a finished game and not a Google Play-ready AAB.**

## Current features

- Real rolling `RigidBody3D` marble, board tilt and wall collisions.
- Keyboard arrows on desktop, optional Android gravity sensor, left-screen touch-drag tilt.
- Orbit camera using right-screen touch-drag or right mouse drag.
- A wind-force tile, magnetic attraction tile, reset trap and goal with timer.
- Procedural metal-look 3D board, lights, UI; no purchased assets or runtime network.

### Test locally

1. Download an up-to-date Godot 4 editor, open this folder via **Import**.
2. Press F5; arrows move the tilt, right mouse drag rotates camera; R resets; G toggles sensor.
3. Android input orientation and gyro calibration must be tested on a real phone.

### Test in Codex Cloud (after environment setup)

Install the Godot 4 Linux editor binary in cloud setup as needed. Run:

```bash
godot --headless --path . --editor --quit
godot --headless --path . --quit-after 3
```

The engine is not bundled. Do not add generated caches or export templates to Git.

### Google Play preparation

1. Open the project with a current Godot build that supports Android API **36**.
2. Install Android SDK, Android export templates, Java tooling and configure Android export.
3. In **Project → Export**, add Android with Gradle build and select **AAB**.
4. Choose the final unique package name (draft: `com.cosmiclab.marblelabyrinth`).
5. Sign release with a private non-debug keystore stored safely outside Git.
6. Test physical Android input and performance, privacy disclosures, icon and store listing.
7. Upload signed AAB to Play Console internal test track, then publish only after review.

Google now requires API 36+ for new mobile apps (as of Aug 31, 2026).

### Notes

- `project.godot` is portable. No platform-specific SDK or keys included.
- Godot export preset must be generated and verified in the editor before release.
- Visual style currently shows simple materials and primitive shapes; replace with original Blender `.glb` assets later.
- No runtime/Android build verification was possible in the starter creation environment because Godot was not installed.

## Existing learning references (inspect their licenses)

- Godot official 3D physics demos: https://github.com/godotengine/godot-demo-projects/tree/master/3d/physics_tests (MIT license)
- 2D marble/tilt demo: https://github.com/neote250/SimplePhysicsMarble (not our intended 3D gameplay)
- Unreal Engine 4 Blueprint rolling ball labyrinth: https://github.com/eherozhao/Rolling-ball-in-Maze
- Old Godot 3/C# marble physics: https://github.com/CyberFoxHax/MarblePhysicsGodot

