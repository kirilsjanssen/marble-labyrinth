# P1 Physics Lab — отчёт headless-проверки

Дата: 30.10.2026. Среда: Codex Cloud, Godot `4.6.3.stable.official`, fixed physics 60 Hz.

## Выполненные команды

```text
godot --headless --path . --editor --quit
godot --headless --path . --fixed-fps 60 --script res://tests/physics_lab_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/smoke_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/level_02_smoke_test.gd
godot --headless --path . --fixed-fps 60 --script res://tests/mobile_controls_test.gd
```

## Результат

```text
PHYSICS LAB PASS: 7 balls, 9 surfaces, pair friction/bounce, rolling, wind, selective magnet and zero gravity
SMOKE PASS: scene, rigid marble, deck and wall collisions, tilt, motion, wind, magnet, trap, reset, goal
LEVEL 2 PASS: floor gaps, physical gears, shafts, bridge, moving platform, lift, timer gate, reset, completion and transition
MOBILE CONTROLS PASS: touch capture, REAL MARBLE MOTION, camera orbit, simultaneous multitouch, release, HUD layout and sensor mapping
```

Импорт проекта завершился с кодом 0. В sandbox появились предупреждения о невозможности открыть локальный TCP-порт редактора и об отсутствующем Android SDK; на импорт GDScript и headless-физику они не повлияли.

## Что подтверждено

- Все тестовые шары — активные `RigidBody3D`; движение создаётся гравитацией, контактами и силами.
- Сталь, алюминий, дерево, резина, стекло, камень и пустотелая оболочка имеют отдельные профили.
- Дерево, металл, резина, лёд, камень, песок, масло, грязь и липкая поверхность дают настраиваемые контактные пары.
- На одинаковом старте лёд, дерево и липкая дорожка дают различающиеся дистанции остановки; резина отскакивает выше камня.
- Ветер ускоряет лёгкое тело. Магнит действует на магнитную сталь и не действует на алюминий. 0g отменяет дальнейшее ускорение мировой гравитацией.
- Регрессионные тесты уровней 1/2 и мобильного управления проходят.

## Ограничения проверки

Headless не подтверждает внешний вид, FPS/нагрев Android, реальные оси датчиков, ощущение управления или мультитач конкретного телефона. APK должен собраться отдельным GitHub Actions workflow; стабильная сборка намеренно требует постоянный ключ владельца из repository secrets. Одноразовый ключ не создаётся и не подменяет постоянную подпись.
