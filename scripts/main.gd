extends Node3D
## Step 3 demo: weight rocks L <-> R, the unweighted foot lifts.

@onready var dancer := $Dancer

var t := 0.0


func _process(dt: float) -> void:
	t += dt
	var w_r := 0.5 + 0.5 * sin(t * 2.0)
	var feet := {
		"L": Vector3(-0.18, 0.04 * clampf((w_r - 0.7) / 0.3, 0, 1), 0),
		"R": Vector3(0.18, 0.04 * clampf((0.3 - w_r) / 0.3, 0, 1), 0),
	}
	dancer.apply(feet, {}, w_r, 0.85, 0.93, 0.03 * absf(cos(t * 2.0)))
