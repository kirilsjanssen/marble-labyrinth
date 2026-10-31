# Level 05 — Alpine Cascade: визуальный overhaul

Дата: 30.10.2026  
Ветка: `feature/level-05-alpine-watermill` (в `main` не сливалась)  
Recovery tag: `backup/level05-visual-overhaul-start-20261030` → `6880292`

## Результат

Существующая модель, инженерная архитектура и игровой маршрут сохранены. Работа выполнена как материал/свет/шейдер/camera pass поверх текущей сцены: геометрия механики, pivots, передаточные числа, WaterNetwork и коллайдеры не перестраивались.

- Обновлённая Blender-модель: `assets/blender/level05_alpine_watermill_visual_v5.blend`.
- Мобильный экспортный Blender-файл: `assets/blender/level05_alpine_watermill_mobile_export.blend`.
- Godot GLB: `assets/levels/level05/level05_mobile.glb` (188 936 треугольников, 16 мобильных материалов).
- Интеграция Godot: `scripts/levels/level05_visuals.gd`, water shaders, HIGH/LOW profiles и smart camera.
- Короткое Godot-видео: `docs/media/level05_overhaul/level05_visual_overhaul_demo.avi`, 1280×720, 30 FPS, 10,5 с, 315 кадров.

## Luma и PBR

Перед платной генерацией проверены доступность API и актуальная официальная цена: `uni-1` text-to-image — **$0.0404 за 2K-изображение**. Выполнена ровно одна новая генерация, массовый batch не запускался.

- Generation ID: `0238b030-9085-43ec-b742-ed3c0c4b079a`.
- Исходник: `assets/luma/level05/source/wet_alpine_timber_trial.png`.
- Назначение: старая выветренная/влажная альпийская древесина возле воды.
- Runtime-набор: `wet_wood_albedo.jpg`, `wet_wood_normal.png`, `wet_wood_rough.jpg` и мобильные варианты.
- `Wood_Weathered` вынесен в отдельный материал, поэтому сухие балки и настилы не потеряли собственный характер.

Luma сгенерировала только цветной исходник. Normal и roughness созданы локально скриптом `tools/textures/process_luma_level05.py` как правдоподобные художественные приближения (band-passed luminance + градиенты + отдельная модель влажности). Они **не заявляются как физически измеренные карты**. Полный prompt и provenance записаны в `assets/luma/level05/PROVENANCE.json`; API-ключ нигде не сохранён.

## Что изменено визуально

- Древесина: уменьшены оранжевый пересвет, чрезмерная насыщенность и сила normal maps; влажная древесина получила отдельный Luma PBR-набор.
- Камень и металл: нормали приглушены для уменьшения shimmer; латунь стала темнее и грубее, сохранив металлическое чтение шестерён, креплений и валов.
- Вода: естественный glacier-teal, более глубокий цвет, Fresnel на скользящих углах, контролируемая прозрачность/roughness, менее яркая emission; водопады стали прозрачнее. Все 23 участка по-прежнему получают живой flow из WaterNetwork.
- Освещение: мягкое альпийское утро, тёплый солнечный ключ, более ровный ambient, filmic tonemap, атмосферная перспектива и умеренный glow. Фонари используют ограниченное число omni lights и мягкие halos.
- Панорама: отдельные 4096×2048 HIGH и 2048×1024 LOW варианты, highlight compression и симметричный 0°/360° blend; проверенный `seam_mae = 0`.
- Шар: brushed steel вместо почти идеального зеркала (`metallic 0.88`, `roughness 0.24`), более гладкая сфера и латунное кольцо.
- Камера: CHASE отодвинута и поднята, расширен набор безопасных позиций и probe-radius. OVERVIEW/ORBIT/CHASE проходят smoke test.
- Окружение остаётся в world-space и не наклоняется вместе с доской.

## HIGH / LOW

| Профиль | Растительность | Свет | Вода/частицы | Панорама | Cam 01 draw calls | Texture memory* |
|---|---:|---|---|---|---:|---:|
| HIGH | 613 instances | тени, 3 локальных света, glow | 2 слоя + normal, 28 spray particles/fall | 4096×2048 | 453 | 66,9 MB |
| LOW | 219 instances | без теней/omni/glow | 1 слой, без normal и spray | 2048×1024 | 260 | 40,0 MB |

\* Диагностический показатель desktop OpenGL Compatibility при capture, не Android benchmark. Android Emulator не запускался.

## Скриншоты до/после

Одинаковые семь камер Blender v4/Godot preview:

- `docs/media/level05_overhaul/before/godot_Cam_01_Isometric.png`
- `docs/media/level05_overhaul/after/godot_Cam_01_Isometric.png`
- Аналогично `Cam_02_Top`, `Cam_03_Side`, `Cam_04_Mill`, `Cam_05_Corridor`, `Cam_06_Wheel`, `Cam_07_Lift`.
- LOW-профиль: `docs/media/level05_overhaul/after_low/`.

## Проверки

Среда: Godot 4.7.2 stable, Blender 5.2.3 LTS, Windows x64, Godot OpenGL Compatibility. Импорт проекта и GLB завершён без ошибок. Все тесты запускались headless с fixed physics 60 Hz.

| Тест | Результат |
|---|---|
| `smoke_test` | PASS |
| `goal_socket_test` | PASS |
| `mobile_controls_test` | PASS |
| `physics_lab_test` | PASS |
| `shape_lab_test` | PASS |
| `water_buoyancy_test` | PASS |
| `water_lab_test` | PASS |
| `water_network_test` | PASS — клапаны, pump, reverse flow, overflow, conservation |
| `level_02_smoke_test` | PASS |
| `level_03_smoke_test` | PASS |
| `level_04_smoke_test` | PASS |
| `level05_visuals_test` | PASS — 206 static colliders, 8 dynamic, 23 water bodies, pivots/materials |
| `level_05_smoke_test` | PASS — физический START→GOAL, crate, lift ×2, crank, secret corridor/alcove, gears 1/2 и 16/7, water flow, CHASE/OVERVIEW, HIGH/LOW, reset, старые уровни |

Итого: **13/13 PASS**. Физическое Android-устройство и гироскоп в этой сессии не проверялись; эмулятор намеренно не запускался.

