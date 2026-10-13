extends SceneTree
## Run: godot --headless -s tests/test_ik.gd

func _initialize() -> void:
	var d: Node3D = load("res://scripts/dancer.gd").new()
	root.add_child(d)
	await process_frame # let _ready build the figure
	var fails := 0
	for t in [Vector3(-0.18, 0.08, 0), Vector3(0.10, 0.12, 0.30), Vector3(-0.18, 0.08, -0.30), Vector3(0.18, 0.2, 0)]:
		for side in ["L", "R"]:
			d.solve_leg(side, t)
			var leg: Dictionary = d.legs[side]
			var err: float = leg.ankle.global_position.distance_to(t)
			var hip: Vector3 = leg.hip.global_position
			var knee: Vector3 = leg.knee.global_position
			# knee must sit in front (-Z) of the hip->ankle line
			var mid := hip.lerp(t, (knee.y - hip.y) / (t.y - hip.y))
			var reachable: bool = hip.distance_to(t) < d.THIGH + d.SHIN
			if (reachable and err > 1e-3) or knee.z > mid.z + 1e-4:
				fails += 1
				printerr("FAIL %s %s err=%.4f knee.z=%.3f line.z=%.3f" % [side, t, err, knee.z, mid.z])
	print("IK test: %s" % ("PASS" if fails == 0 else "%d FAILS" % fails))
	quit(fails)
