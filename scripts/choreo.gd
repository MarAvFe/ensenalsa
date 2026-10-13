extends RefCounted
## Routine data -> per-beat foot states -> continuous pose sampling.
## Beat i is the instant the dancer lands count states[i]; between beats i and i+1
## the move is split into ordered segments so a foot never moves while it holds weight.

const SIDES := ["L", "R"]

var p: Dictionary # params from the data file
var states: Array[Dictionary] = [] # {count, basic, weight, action:{L,R}, feet:{L:Vector3,R:Vector3}}


func _init(path: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data != null, "bad routine json: " + path)
	p = data.params
	var feet := {"L": _v(p.home_L, 0.0), "R": _v(p.home_R, 0.0)}
	for basic_name in data.routine:
		var counts: Array = data.basics[basic_name]
		# every basic is a full 8-count, so switching between basics only ever happens on count 1
		assert(counts.map(func(c): return int(c.count)) == [1, 2, 3, 4, 5, 6, 7, 8], basic_name + " must have counts 1-8")
		for c in counts:
			var actions := {}
			for side in SIDES:
				var a: String = c[side].action
				actions[side] = a
				if a != "hold":
					feet[side] = _v(c[side].target, p.lift if a == "lift" else 0.0)
			states.append({"count": int(c.count), "basic": basic_name, "weight": c.weight,
				"action": actions, "feet": feet.duplicate()})


## Dancer-frame foot position (x, lift, z).
func _v(xz: Array, y: float) -> Vector3:
	return Vector3(xz[0], y, xz[1])


func size() -> int:
	return states.size()


static func _other(side: String) -> String:
	return "R" if side == "L" else "L"


## Ordered segments for the move from state a to state b: ["w", side] shifts weight, ["m", side] moves a foot.
func segments(a: Dictionary, b: Dictionary) -> Array:
	var movers := SIDES.filter(func(s): return not a.feet[s].is_equal_approx(b.feet[s]) or b.action[s] == "tap")
	var w0: String = a.weight
	var w1: String = b.weight
	var segs := []
	if movers.is_empty():
		if w0 != w1:
			segs.append(["w", w1])
	elif movers.size() == 1:
		var f: String = movers[0]
		var support := _other(f)
		if w0 != support:
			segs.append(["w", support])
		segs.append(["m", f])
		if w1 != support:
			segs.append(["w", w1])
	else: # the foot that ends with weight moves first, then takes weight, then the other moves
		var second := _other(w1)
		if w0 != second:
			segs.append(["w", second])
		segs += [["m", w1], ["w", w1], ["m", second]]
	return segs


## Pose at time t (beats, already wrapped into [0, size())).
func sample(t: float) -> Dictionary:
	var i := int(floor(t))
	var a: Dictionary = states[i]
	var b: Dictionary = states[(i + 1) % states.size()]
	var s := t - i
	var feet: Dictionary = a.feet.duplicate()
	var pitch := {"L": 0.0, "R": 0.0}
	var w_r := 1.0 if a.weight == "R" else 0.0
	var dip := 0.0
	var segs := segments(a, b)
	var total := 0.0
	for g in segs:
		total += 1.0 if g[0] == "m" else 0.6
	var start := 0.0
	for g in segs:
		var dur := (1.0 if g[0] == "m" else 0.6) / total
		var u := clampf((s - start) / dur, 0.0, 1.0)
		var e := smoothstep(0.0, 1.0, u)
		var bump := sin(PI * u)
		var side: String = g[1]
		if g[0] == "w":
			w_r = lerpf(w_r, 1.0 if side == "R" else 0.0, e)
			dip = maxf(dip, p.pelvis_dip * bump)
		else:
			var f0: Vector3 = a.feet[side]
			var f1: Vector3 = b.feet[side]
			var tap: bool = b.action[side] == "tap"
			var moved := Vector2(f0.x, f0.z).distance_to(Vector2(f1.x, f1.z)) > 0.001
			var arc: float = p.tap_height if tap else (p.step_arc if moved else 0.0)
			feet[side] = f0.lerp(f1, e) + Vector3(0, arc * bump, 0)
			if tap:
				pitch[side] = -p.tap_pitch * bump
		start += dur
	return {"feet": feet, "pitch": pitch, "w_r": w_r, "dip": dip, "state": a}
