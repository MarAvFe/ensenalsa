extends RefCounted
## Routine data -> per-beat foot states -> continuous pose sampling.
## Beat i is the instant the dancer lands count states[i]; each move is split into ordered
## segments so a foot never moves while it holds weight.

const SIDES := ["L", "R"]

var p: Dictionary # params from the data file
var basics := {} # name -> 8 states {count, basic, weight, action:{L,R}, feet:{L:Vector3,R:Vector3}}
var labels: Dictionary # name -> button label
var start_basic: String
var styles: Dictionary # name -> {label, hip_twist, arm_forward, arm_out, elbow}
var start_style: String


func _init(path: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data != null, "bad routine json: " + path)
	p = data.params
	labels = data.labels
	start_basic = data.start_basic
	styles = data.styles
	start_style = data.start_style
	for basic_name in data.basics:
		var counts: Array = data.basics[basic_name]
		var feet := {"L": _v(p.home_L, 0.0), "R": _v(p.home_R, 0.0)} # every basic starts and ends at home
		var states: Array[Dictionary] = []
		# every basic is a full 8-count, so switching between basics only happens on count 1
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
		basics[basic_name] = states


## Dancer-frame foot position (x, lift, z).
func _v(xz: Array, y: float) -> Vector3:
	return Vector3(xz[0], y, xz[1])


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


## [up to and including the key segment, after it]. The key is the last weight change
## (or the last move when weight stays), so it is what lands on the beat.
static func _split(segs: Array) -> Array:
	var k := segs.size() - 1
	for j in segs.size():
		if segs[j][0] == "w":
			k = j
	return [segs.slice(0, k + 1), segs.slice(k + 1)]


## Pose at time t (beats into the current basic, in [0, 8)). `prev`/`next` are the basics
## danced before/after `cur`, so the moves across count 1 blend into the right states.
## Square timing: the key event of every count lands exactly on its beat, the weight change
## always takes the last `weight_phase` of the beat, and moves that must wait for the weight
## to leave a foot (releases) play out in the first `release_phase` of the next beat.
func sample(t: float, prev: String, cur: String, next: String) -> Dictionary:
	var i := int(floor(t))
	var s := t - i
	var z: Dictionary = basics[prev][7] if i == 0 else basics[cur][i - 1]
	var a: Dictionary = basics[cur][i]
	var b: Dictionary = basics[next][0] if i == 7 else basics[cur][i + 1]
	var out := {"feet": a.feet.duplicate(), "pitch": {"L": 0.0, "R": 0.0},
		"w_r": 1.0 if a.weight == "R" else 0.0, "dip": 0.0, "state": a}

	_play_all(z, a, b, s, out)
	out.pelvis = _pelvis(out.feet, out.w_r)
	# how far R is ahead of L relative to home (metres); a style's hip_twist turns it into hip yaw
	out.twist = (out.feet.R.z - p.home_R[1]) - (out.feet.L.z - p.home_L[1])
	return out


## Pelvis over the weight, measured on the home stance. On a break step (weighted foot away
## from home) that shift fades out over `break_distance` and the body follows only `break_follow`
## of the step: the leg stretches, the torso stays near neutral because it is coming back.
func _pelvis(feet: Dictionary, w_r: float) -> Vector3:
	var hl := _v(p.home_L, 0.0)
	var hr := _v(p.home_R, 0.0)
	var mix: float = (1.0 - p.pelvis_over_foot) + (2.0 * p.pelvis_over_foot - 1.0) * w_r
	var away: Vector3 = (feet.L - hl).lerp(feet.R - hr, mix)
	away.y = 0.0
	var centre := hl.lerp(hr, 0.5)
	var breaking := clampf(away.length() / p.break_distance, 0.0, 1.0)
	return centre + (hl.lerp(hr, mix) - centre) * (1.0 - breaking) + away * p.break_follow


## Releases left over from the move into a, then the moves into b with the key on the beat.
func _play_all(z: Dictionary, a: Dictionary, b: Dictionary, s: float, out: Dictionary) -> void:
	var t0 := 0.0
	var rel: Array = _split(segments(z, a))[1]
	if not rel.is_empty():
		t0 = p.release_phase
		for g in rel:
			out.feet[g[1]] = z.feet[g[1]] # not released yet at the beat
		_play(rel, z, a, s, 0.0, t0, out)

	var pre: Array = _split(segments(a, b))[0]
	if pre.is_empty():
		return
	var key: Array = pre.back()
	if key[0] == "w":
		var w_start := 1.0 - float(p.weight_phase)
		_play(pre.slice(0, -1), a, b, s, t0, w_start, out)
		_play([key], a, b, s, w_start, 1.0, out)
	else:
		_play(pre, a, b, s, t0, 1.0, out)


## Play segments (moves from state a to b) one after another inside [from, to] of the beat.
func _play(segs: Array, a: Dictionary, b: Dictionary, s: float, from: float, to: float, out: Dictionary) -> void:
	var total := 0.0
	for g in segs:
		total += 1.0 if g[0] == "m" else 0.6
	var start := from
	for g in segs:
		var dur := (1.0 if g[0] == "m" else 0.6) / total * (to - from)
		if s > start:
			var u := clampf((s - start) / dur, 0.0, 1.0)
			var e := smoothstep(0.0, 1.0, u)
			var bump := sin(PI * u)
			var side: String = g[1]
			if g[0] == "w":
				out.w_r = lerpf(out.w_r, 1.0 if side == "R" else 0.0, e)
				out.dip = maxf(out.dip, p.pelvis_dip * bump)
			else:
				var f0: Vector3 = a.feet[side]
				var f1: Vector3 = b.feet[side]
				var tap: bool = b.action[side] == "tap"
				var moved := Vector2(f0.x, f0.z).distance_to(Vector2(f1.x, f1.z)) > 0.001
				var arc: float = p.tap_height if tap else (p.step_arc if moved else 0.0)
				out.feet[side] = f0.lerp(f1, e) + Vector3(0, arc * bump, 0)
				if tap:
					out.pitch[side] = -p.tap_pitch * bump
		start += dur
