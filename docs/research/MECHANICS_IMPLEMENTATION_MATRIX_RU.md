# MARBLE LABYRINTH — матрица механик и зависимостей

Дата ревизии: 30.10.2026. База P1: `feature/stage-5-stable-android-updates`, чтобы сохранить уровни 1/2, мобильную физику PR #3 и цепочку подписи PR #4. Документы PR #5 перенесены без объединения PR. Сторонний код в P1 не копировался.

| Этап | Механика | Источник/API и лицензия | Компонент | Проверка | Статус |
| --- | --- | --- | --- | --- | --- |
| P1 | 7 типов шаров, масса, качение, инерция | Godot 4.6 `RigidBody3D`; официальный API | `PhysicsBall`, `BallMaterialProfile` | живой `RigidBody3D`, угловая скорость | Реализовано, headless |
| P1 | 9 поверхностей и контактные пары | Godot 4.6 `PhysicsMaterial`; официальный API; MIT friction demo указан в `VERIFIED_SOURCE_FILES_RU.md` | `PhysicsMaterialCatalog`, `SurfaceZone` | разные дистанции лёд/дерево/липкая поверхность | Реализовано, headless |
| P1 | Разный отскок | Godot 4.6 `PhysicsMaterial`; официальный API | каталог пар материалов | резина отскакивает выше камня на металле | Реализовано, headless |
| P1 | Ветер | Godot 4.6 силы `RigidBody3D`; официальный API | `FieldZone.WIND` | лёгкий шар получает скорость от силы | Реализовано, headless |
| P1 | Магнит с полярностью и спадом | Godot 4.6 силы `RigidBody3D`; оригинальная реализация | `FieldZone.MAGNETIC` | сталь притягивается, алюминий остаётся на месте | Реализовано, headless |
| P1 | Локальная/нулевая гравитация | Godot 4.6 силы и project gravity; официальный API | `FieldZone.LOCAL_GRAVITY` | тело в 0g не падает, контрольное падает | Реализовано, headless |
| P1 | Адгезионное поле | Godot 4.6 силы; оригинальная реализация | `FieldZone.ADHESION` | отдельная калибровка силы отрыва | Прототип API, тест P1.1 |
| P1 | Температурный предел шара | Требования `MATERIAL_TRANSFORMATIONS_AND_FIELDS_RU.md` | данные `BallMaterialProfile` | тепловая зона и урон | Данные готовы, логика P5 |
| P2 | Объём воды, клапаны, насосы, реверс | собственная сеть резервуаров; WaterBox/GDWaterKart MIT только как изученные ссылки | `WaterHydraulics`, `WaterBodyForces`, `WaterSurfaceVisual` | сохранение объёма, плавучесть, обратный поток | Следующий этап |
| P3 | Лифт, мост, шестерни, платформы | Godot `AnimatableBody3D`; MIT moving-platform demo как справочник | существующий `ClockworkMechanisms` + новые модули | старый L02 smoke + новые механизмы | Частично уже в L02 |
| P4 | Несколько шаров и Magnetic Relay | оригинальная архитектура | `BallRegistry`, `BallSwitcher`, puzzle graph | алюминий не поднимается, сталь поднимается силой | Запланировано |
| P5 | Cooling Crucible, лава/вода/корка | оригинальная state machine | thermal/material state, lava network | оба маршрута, урон, временная коллизия | Запланировано |
| P6 | Звёзды, награды и сохранение | Godot `FileAccess`/JSON; официальный API | progression modules | 1–3 звезды, рекорды, повтор | Запланировано |
| P7 | Камеры и окружение | Godot Camera3D; MIT orbit-camera ссылка только для изучения | camera modules | плавные режимы, Android ввод | Запланировано |

## Зависимости

`BallMaterialProfile` является общим источником массы, плотности, контактных, магнитных, адгезионных и температурных свойств. `PhysicsBall` применяет профиль к настоящему `RigidBody3D`. `SurfaceZone` выбирает контактную пару, а `FieldZone` читает только нужный отклик материала и прикладывает ограниченную силу. P2 будет читать плотность и скорость того же шара, поэтому водная система не потребует отдельного типа игрового объекта.

Физический расчёт отделён от визуала и от `main.gd`. Лаборатория находится в `scenes/labs/physics_lab.tscn`, автоматическая проверка — в `tests/physics_lab_test.gd`. Значения настроены для геймплея и должны уточняться на физическом Android-устройстве; они не заявлены как инженерные коэффициенты материалов.

## Изученные внешние проекты

- `godotengine/godot-demo-projects`, MIT: friction, collision pairs, rigid impact, joints и moving platforms. API master требует проверки против Godot 4.6.3.
- `Adisoreq/godot-waterbox`, MIT: плавучесть и drag, но не гидравлическая сеть и заявлен старый Godot 4.0.1.
- `JorisAR/GDWaterKart`, MIT: visual ocean и buoyancy; GPU-часть не принята как Android GL fallback.
- `emilje/godot-water-shader`, MIT, и `taillight-games/godot-4-pixelated-water-shader`, MIT: только визуальные идеи; вращение water mesh имеет известные ограничения.
- `EthanCS/crest-godot`, MIT: тяжёлая океанская модель; не выбрана для мобильного пазла.
- `OzanA78/godot-exit-portal-free`, MIT: orbit camera как справочник для P7.
- `Yogeb-tech/Godot-Moving-Platforms-2D`, MIT: архитектурные идеи состояний; 2D-код не переносился.
- `Donitzo/godot-simple-portal-system`: код не используется, пока лицензия конкретной версии не подтверждена.

Точные пути файлов и LICENSE собраны в `VERIFIED_SOURCE_FILES_RU.md`. В P1 нет сторонних зависимостей и нет кода, требующего NOTICE/атрибуции.
