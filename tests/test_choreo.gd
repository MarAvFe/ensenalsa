extends SceneTree
## Run: godot --headless --path . -s res://tests/test_choreo.gd
## Checks over a sequence covering every basic-to-basic switch, for the leader and the follower:
## the weight-bearing foot never slides, every IK target is reachable (no knee pop), nothing jumps
## between samples (no teleporting), and timing is square: every weight change happens inside the
## last `weight_phase` of its beat, landing on it. Reach and square shoulders are checked in every
## style (hip twist moves the hips); taps land on the toe tip; held hands meet.

func _initialize() -> void:
	var ch = load("res://scripts/choreo.gd").new("res://data/routine.json")
	var lead: Node3D = load("res://scripts/dancer.gd").new()
	root.add_child(lead)
	var fol: Node3D = load("res://scripts/dancer.gd").new() # placed as in main.gd
	fol.position = Vector3(0, 0, -ch.p.partner_distance)
	fol.rotation.y = PI
	root.add_child(fol)
	await process_frame
	var D := "diagonal_basic"
	var I := "inline_basic"
	var S := "side_basic"
	var seq := [D, D, I, I, S, S, I, D, S] # cycle containing all 9 ordered switch pairs
	var beats := seq.size() * 8
	var at := func(T: float, as_follower := false) -> Dictionary: # pose at global beat T, wrapping over seq
		T = fposmod(T, beats)
		var k := int(T / 8)
		return ch.sample(fmod(T, 8.0), seq[(k + seq.size() - 1) % seq.size()], seq[k], seq[(k + 1) % seq.size()], as_follower)
	var fails := 0

	for as_follower in [false, true]:
		var d: Node3D = fol if as_follower else lead
		var who := "follower" if as_follower else "leader"
		var n := 14000
		var prev = null
		for k in n + 1:
			var t := float(k) / n * beats - 1.0
			var pose: Dictionary = at.call(t, as_follower)
			for st in ch.styles.values():
				d.apply(pose.feet, pose.pitch, pose.pelvis, ch.p.pelvis_height, pose.dip, {"yaw": st.hip_twist * pose.twist})
				for side in ["L", "R"]:
					var leg: Dictionary = d.legs[side]
					var f: Vector3 = pose.feet[side]
					var target: Vector3 = d.global_transform * Vector3(f.x, d.ANKLE_H + f.y, -f.z)
					if leg.hip.global_position.distance_to(target) > d.THIGH + d.SHIN - 0.002:
						fails += 1
						printerr("FAIL %s unreachable %s t=%.3f %s" % [who, side, t, st.label])
				if d.spine[2].global_basis.z.dot(d.global_basis.z) < 0.9999: # shoulders always face front
					fails += 1
					printerr("FAIL %s shoulders turned t=%.3f %s" % [who, t, st.label])
			for side in ["L", "R"]:
				var f: Vector3 = pose.feet[side]
				if prev != null:
					var share: float = pose.w_r if side == "R" else 1.0 - pose.w_r
					var prev_share: float = prev.w_r if side == "R" else 1.0 - prev.w_r
					var moved: float = f.distance_to(prev.feet[side])
					if share > 0.5 and prev_share > 0.5 and moved > 1e-6:
						fails += 1
						printerr("FAIL %s weighted %s slid %.4f at t=%.3f" % [who, side, moved, t])
					if moved > 0.03:
						fails += 1
						printerr("FAIL %s %s jumped %.3f at t=%.3f" % [who, side, moved, t])
			prev = pose

		for i in beats:
			var st: Dictionary = at.call(float(i), as_follower).state
			var now: float = at.call(float(i), as_follower).w_r
			var want := 1.0 if st.weight == "R" else 0.0
			var before: float = at.call(i - ch.p.weight_phase - 0.01, as_follower).w_r
			var changes: bool = st.weight != at.call(i - 1.0, as_follower).state.weight
			if absf(now - want) > 1e-4 or (changes and absf(before - now) < 0.99):
				fails += 1
				printerr("FAIL %s beat %d: weight not landing on the beat (before=%.2f now=%.2f)" % [who, i, before, now])
			for side in ["L", "R"]:
				if st.action[side] != "tap":
					continue
				# the tap lands on the toe tip, heel up: on the beat, or when it is a release
				# (the foot only just gave up its weight) at the end of the release window
				var on_toe := false
				for when in [float(i), i + ch.p.release_phase]:
					var pose: Dictionary = at.call(when, as_follower)
					d.apply(pose.feet, pose.pitch, pose.pelvis, ch.p.pelvis_height, pose.dip)
					var foot: Node3D = d.legs[side].ankle
					var toe: float = (foot.global_transform * Vector3(0, -d.ANKLE_H, -d.FOOT_TOE)).y
					var heel: float = (foot.global_transform * Vector3(0, -d.ANKLE_H, d.FOOT_HEEL)).y
					on_toe = on_toe or (absf(toe) < 0.003 and heel > 0.05)
				if not on_toe:
					fails += 1
					printerr("FAIL %s beat %d: %s tap not on the toe" % [who, i, side])

	# held hands meet on the hold point at every beat (Flat: always held)
	for i in beats:
		var lp: Dictionary = at.call(float(i))
		var fp: Dictionary = at.call(float(i), true)
		lead.apply(lp.feet, lp.pitch, lp.pelvis, ch.p.pelvis_height, lp.dip)
		fol.apply(fp.feet, fp.pitch, fp.pelvis, ch.p.pelvis_height, fp.dip)
		for side in ["L", "R"]:
			var other := "R" if side == "L" else "L"
			var target: Vector3 = lead.hold_point(lead.arms[side].upper.global_position, fol.arms[other].upper.global_position, ch.p.hold_drop)
			lead.hold(side, target, 1.0)
			fol.hold(other, target, 1.0)
			for pair in [[lead, side], [fol, other]]:
				var hand: Vector3 = pair[0].arms[pair[1]].fore.global_transform * Vector3(0, -lead.FOREARM, 0)
				if hand.distance_to(target) > 0.01:
					fails += 1
					printerr("FAIL beat %d: hand %s misses the hold by %.3f" % [i, pair[1], hand.distance_to(target)])
	print("Choreo test (%d beats, leader + follower): %s" % [beats, "PASS" if fails == 0 else "%d FAILS" % fails])
	quit(fails)
