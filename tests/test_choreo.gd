extends SceneTree
## Run: godot --headless --path . -s res://tests/test_choreo.gd
## Checks over a sequence covering every basic-to-basic switch: the weight-bearing foot never slides, every IK target
## is reachable (no knee pop), nothing jumps between samples (no teleporting), and timing is
## square: every weight change happens inside the last `weight_phase` of its beat, landing on it.

func _initialize() -> void:
	var ch = load("res://scripts/choreo.gd").new("res://data/routine.json")
	var d: Node3D = load("res://scripts/dancer.gd").new()
	root.add_child(d)
	await process_frame
	var seq := ["diagonal_basic", "diagonal_basic", "inline_basic", "inline_basic"] # every switch pair
	var beats := seq.size() * 8
	var at := func(T: float) -> Dictionary: # pose at global beat T, wrapping over seq
		T = fposmod(T, beats)
		var k := int(T / 8)
		return ch.sample(fmod(T, 8.0), seq[(k + 3) % 4], seq[k], seq[(k + 1) % 4])
	var fails := 0
	var n := 6000
	var prev = null
	for k in n + 1:
		var t := float(k) / n * beats - 1.0
		var pose: Dictionary = at.call(t)
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
	for i in beats:
		var st: Dictionary = at.call(float(i)).state
		var now: float = at.call(float(i)).w_r
		var want := 1.0 if st.weight == "R" else 0.0
		var before: float = at.call(i - ch.p.weight_phase - 0.01).w_r
		var changes: bool = st.weight != at.call(i - 1.0).state.weight
		if absf(now - want) > 1e-4 or (changes and absf(before - now) < 0.99):
			fails += 1
			printerr("FAIL beat %d: weight not landing on the beat (before=%.2f now=%.2f)" % [i, before, now])
	print("Choreo test (%d beats): %s" % [beats, "PASS" if fails == 0 else "%d FAILS" % fails])
	quit(fails)
