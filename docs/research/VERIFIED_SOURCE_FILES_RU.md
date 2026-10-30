# OPEN SOURCE CODE INDEX — конкретные исходные файлы

Исследование 30.10.2026; это карта чужого кода для анализа, НЕ включённые в Marble Labyrinth зависимости. Пути проверены по публичному GitHub API. Перед копированием проверить точный commit/tag, LICENSE и права на содержащиеся ресурсы.

## Базовая 3D-физика, MIT (godotengine/godot-demo-projects)
- Физическое трение и реальные различия поверхностей:
  https://github.com/godotengine/godot-demo-projects/blob/master/3d/physics_tests/tests/functional/test_friction.tscn
- Движущиеся платформы:
  https://github.com/godotengine/godot-demo-projects/blob/master/3d/physics_tests/tests/functional/test_moving_platform.gd
  https://github.com/godotengine/godot-demo-projects/blob/master/3d/physics_tests/tests/functional/test_moving_platform.tscn
- Контактные пары (дерево/металл/шар):
  https://github.com/godotengine/godot-demo-projects/blob/master/3d/physics_tests/tests/functional/test_collision_pairs.gd
- Удары, скорость, отскоки:
  https://github.com/godotengine/godot-demo-projects/blob/master/3d/physics_tests/tests/functional/test_rigidbody_impact.tscn
- Шарнирные системы для мостов, канатов, качающихся конструкций:
  https://github.com/godotengine/godot-demo-projects/blob/master/3d/physics_tests/tests/functional/test_joints.gd
- Нагрузочные проверки RigidBody3D и контактов:
  https://github.com/godotengine/godot-demo-projects/blob/master/3d/physics_tests/tests/performance/test_perf_contacts.gd
- Лицензия: https://github.com/godotengine/godot-demo-projects/blob/master/LICENSE.md
- ⚠ master не закреплён на 4.6.3; сравнить API/выбрать совместимый commit.

## Вода — buoyancy / drag (Adisoreq/godot-waterbox, MIT)
- Объём воды:
  https://github.com/Adisoreq/godot-waterbox/blob/main/addons/waterbox/scripts/water_box.gd
- Компонент плавучести:
  https://github.com/Adisoreq/godot-waterbox/blob/main/addons/waterbox/scripts/buoyancy_component.gd
- Лицензия: https://github.com/Adisoreq/godot-waterbox/blob/main/LICENSE
- ⚠ проект заявляет тестирование на старом Godot 4.0.1; не означает совместимости с 4.6.3. Это **не water-flow-network**: гидравлические переливы/насосы придётся сделать собственными.

## Вода — visual + force (JorisAR/GDWaterKart, MIT)
- Физическая buoyancy-сущность:
  https://github.com/JorisAR/GDWaterKart/blob/main/water/buoyant_body3d.gd
- Чувствительный к воде сенсор:
  https://github.com/JorisAR/GDWaterKart/blob/main/water/water_buoyancy_sensor.gd
- Контроллер океана:
  https://github.com/JorisAR/GDWaterKart/blob/main/water/ocean.gd
- GPU shader:
  https://github.com/JorisAR/GDWaterKart/blob/main/water/water_surface.gdshader
- Лицензия: https://github.com/JorisAR/GDWaterKart/blob/main/LICENSE
- ⚠ океан и шейдер НЕ являются системой потоков через наклонённые каналы, Android GL Compatibility может не поддерживать используемые вычислительные эффекты. Проверить оригинальные лицензии вспомогательных исходников.

## Вода — visual, НЕ hydraulics (emilje/godot-water-shader, MIT)
- Волны: https://github.com/emilje/godot-water-shader/blob/main/shaders/g_wave.gdshader
- Пена: https://github.com/emilje/godot-water-shader/blob/main/shaders/foam_calc.gdshader
- Глубина: https://github.com/emilje/godot-water-shader/blob/main/shaders/i_depth.gdshader
- Лицензия: https://github.com/emilje/godot-water-shader/blob/main/LICENSE
- ⚠ проверять на GL Compatibility и не путать визуальную волну с водой, способной выталкивать или нести шар.

## Вода — буферный тест / ограничение вращения (taillight-games/godot-4-pixelated-water-shader, MIT)
- Плавучесть: https://github.com/taillight-games/godot-4-pixelated-water-shader/blob/main/scripts/buoyancy.gd
- Управление водой: https://github.com/taillight-games/godot-4-pixelated-water-shader/blob/main/scripts/water-manager.gd
- Лицензия: https://github.com/taillight-games/godot-4-pixelated-water-shader/blob/main/LICENSE
- ⚠ автор README прямо предупреждает: вращение mesh воды нарушает расчёты. Для наклоняемой платформы использовать собственную модель с независимой world-space поверхностью и физикой жидкости.

## Камера (OzanA78/godot-exit-portal-free, MIT)
- Orbit controls: https://github.com/OzanA78/godot-exit-portal-free/blob/main/addons/exit_portal_free/orbit_camera.gd
- Лицензия: https://github.com/OzanA78/godot-exit-portal-free/blob/main/LICENSE
- ⚠ адаптировать под touch / double-finger и collision avoidance.

## 2D идеи активаторов (Yogeb-tech/Godot-Moving-Platforms-2D, MIT)
- Репо https://github.com/Yogeb-tech/Godot-Moving-Platforms-2D
- Архитектура LOOP/TRIGGERED/TOGGLE/ONE_WAY интересна, но скрипты НЕ 3D.

## Порталы и смена гравитации (только после LICENSE-проверки)
- https://github.com/Donitzo/godot-simple-portal-system/blob/master/src/scripts/portal.gd
- https://github.com/Donitzo/godot-simple-portal-system/blob/master/src/scripts/simple_portal_teleport.gd
- ⚠ Не переносить код, пока явная лицензия конкретного релиза/вложенных файлов не проверена.

## Чего в готовом виде НЕ найдено
- Портативная 4.6.3/Android low-cost реализация сохранения объёма воды при наклоне многоуровневой сети резервуаров и переключении насосов.
- Унифицированная коммерчески-лицензированная готовая библиотека всех комбинаций: магниты, адгезия, гравитация, 3D шар, вода/поток, огонь, клапаны, лифты и puzzle graph.

Это надо реализовывать своими небольшими компонентами и тестами, не имитировать визуальной анимацией. Точная лицензия каждого источника повторно проверяется при фактическом заимствовании.
