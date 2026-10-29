# Marble Labyrinth: rules for Codex Cloud

This is an original Android-first Godot 4.x 3D marble physics puzzle game.
Keep everything compatible with Godot GDScript, Android touch and motion sensors.

- Maintain a runnable game: `project.godot` and `scenes/main.tscn` must load.
- Preserve physics: a real `RigidBody3D` sphere, collidable labyrinth, and real gravity.
- Do not replace physics with fake animations.
- Do not copy the Resident Evil Village level, assets or art: only the general genre inspires the game.
- Do not incorporate GitHub sample code unless its license explicitly permits reuse, and record attribution.
- Art and music are owner-created. Do not purchase assets or add paid dependencies.
- Prioritize small code and procedural prototype geometry, modular assets, low draw calls.
- Exclude `.godot`, exports, cache and signing keys from Git.
- Never create, upload or reveal signing keystore passwords; never publish to Google Play without owner approval.
- Do not use Android emulators on the owner's weak HP computer; physical Android or headless tests only.
- Test project import with: `godot --headless --path . --editor --quit` (if engine installed).
- Report candidly if local Android export/gyro calibration cannot be tested.

Roadmap: 1. verify mechanics and mobile gyro 2. add camera modes 3. modular magnetic/air/water/rope/lift obstacles 4. original Blender assets and polished materials 5. signed AAB for Play Console.

