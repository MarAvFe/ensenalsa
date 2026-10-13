extends SceneTree
## Run: godot --headless --path . -s res://tests/test_choreo.gd
## Checks over the whole routine: the weight-bearing foot never slides, every IK target
## is reachable (no knee pop), and nothing jumps between samples (no teleporting).

func _initialize() -> void:
	var ch = load("res://scripts/choreo.gd").new("res://data/routine.json")
	var d: Node3D = load("res://scripts/dancer.gd").new()
	root.add_child(d)
	await process_frame
	var fails := 0
	var n := 4000
	var prev = null
	for k in n + 1:
		var t := fposmod(float(k) / n * ch.size() - 1.0, ch.size())
		var pose: Dictionary = ch.sample(t)
		d.apply(pose.feet, pose.pitch, pose.w_r, ch.p.pelvis_over_foot, ch.p.pelvis_height, pose.dip)
		for side in ["L", "R"]:
			var leg: Dictionary = d.legs[side]
			var f: Vector3 = pose.feet[side]
			var target: Vector3 = d.global_transform * Vector3(f.x, d.ANKLE_H + f.y, -f.z)
			if leg.hip.global_position.distance_to(target) > d.THIGH + d.SHIN - 0.002:
				fails += 1
				printerr("FAIL unreachable %s t=%.3f" % [side, t])
			if prev != null:
				var share: float = pose.w_r if side == "R" else 1.0 - pose.w_r
				var prev_share: float = prev.w_r if side == "R" else 1.0 - prev.w_r
				var moved: float = f.distance_to(prev.feet[side])
				if share > 0.5 and prev_share > 0.5 and moved > 1e-6:
					fails += 1
					printerr("FAIL weighted %s slid %.4f at t=%.3f" % [side, moved, t])
				if moved > 0.03:
					fails += 1
					printerr("FAIL %s jumped %.3f at t=%.3f" % [side, moved, t])
		prev = pose
	print("Choreo test (%d beats): %s" % [ch.size(), "PASS" if fails == 0 else "%d FAILS" % fails])
	quit(fails)
