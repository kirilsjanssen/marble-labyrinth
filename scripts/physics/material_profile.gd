extends Resource
class_name BallMaterialProfile
## Gameplay-tuned physical properties for a reusable rigid marble.
## Values are intentionally configurable and are not presented as laboratory data.

@export var id: StringName = &"steel"
@export var display_name := "Steel"
@export_range(0.05, 10.0, 0.01) var mass := 0.34
@export_range(50.0, 10000.0, 1.0) var density := 7800.0
@export_range(0.0, 2.0, 0.01) var friction := 0.55
@export_range(0.0, 1.0, 0.01) var bounce := 0.08
@export_range(0.0, 4.0, 0.01) var linear_damp := 0.08
@export_range(0.0, 4.0, 0.01) var angular_damp := 0.05
@export_range(-1.0, 1.0, 0.01) var magnetic_response := 0.0
@export_range(-1.0, 1.0, 0.01) var electric_charge := 0.0
@export_range(0.0, 2.0, 0.01) var adhesion := 0.0
@export_range(-100.0, 2000.0, 1.0) var damage_temperature := 500.0


func duplicate_profile() -> BallMaterialProfile:
	return duplicate(true) as BallMaterialProfile
