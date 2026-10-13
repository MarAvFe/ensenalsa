extends Node3D
## Stylized dancer built from primitives. Faces Godot -Z (dancer +Z forward).

const THIGH := 0.44
const SHIN := 0.44
const ANKLE_H := 0.08 # ankle joint height above the sole
const FOOT_TOE := 0.20 # toe tip, ahead of the ankle
const FOOT_HEEL := 0.06 # heel, behind the ankle
const HIP_X := 0.10
const HIP_DROP := 0.05 # hip joints sit this far below the pelvis origin
const PELVIS_H := 0.93
const SPINE_UNTWIST := [0.4, 0.35, 0.25] # share of the hip twist each spine joint undoes: shoulders stay square

const COL_BODY := Color(0.75, 0.72, 0.68)
const COL_L := Color(0.25, 0.45, 0.95)
const COL_R := Color(0.95, 0.3, 0.25)

var pelvis: Node3D
var legs := {} # "L"/"R" -> {hip, knee, ankle}
var arms := {} # "L"/"R" -> {upper, fore}
var spine: Array[Node3D] = []


func _ready() -> void:
	pelvis = _joint(self, "Pelvis", Vector3(0, PELVIS_H, 0))
	_box(pelvis, Vector3(0.30, 0.12, 0.16), Vector3.ZERO, COL_BODY)

	var s := pelvis
	for i in 3:
		s = _joint(s, "Spine%d" % (i + 1), Vector3(0, 0.06 if i == 0 else 0.15, 0))
		spine.append(s)
		_capsule(s, 0.15, 0.09 + 0.015 * i, COL_BODY, true)
	var neck := _joint(s, "Neck", Vector3(0, 0.15, 0))
	_capsule(neck, 0.10, 0.04, COL_BODY, true)
	var head := _joint(neck, "Head", Vector3(0, 0.10, 0))
	_sphere(head, 0.11, Vector3(0, 0.10, 0), COL_BODY)
	_box(head, Vector3(0.04, 0.03, 0.05), Vector3(0, 0.1, -0.11), COL_BODY) # nose shows facing

	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var col := COL_L if side == "L" else COL_R
		var sh := _joint(s, "Shoulder" + side, Vector3(0.19 * sx, 0.13, 0))
		_sphere(sh, 0.05, Vector3.ZERO, COL_BODY)
		var ua := _joint(sh, "UpperArm" + side, Vector3.ZERO)
		_capsule(ua, 0.30, 0.04, COL_BODY)
		var fa := _joint(ua, "Forearm" + side, Vector3(0, -0.30, 0))
		_capsule(fa, 0.27, 0.035, COL_BODY)
		arms[side] = {"upper": ua, "fore": fa}

		var hip := _joint(pelvis, "Thigh" + side, Vector3(HIP_X * sx, -HIP_DROP, 0))
		_capsule(hip, THIGH, 0.065, col)
		var knee := _joint(hip, "Shin" + side, Vector3(0, -THIGH, 0))
		_capsule(knee, SHIN, 0.05, col)
		var ankle := _joint(knee, "Foot" + side, Vector3(0, -SHIN, 0))
		_box(ankle, Vector3(0.10, 0.06, FOOT_TOE + FOOT_HEEL), Vector3(0, -ANKLE_H + 0.03, (FOOT_HEEL - FOOT_TOE) / 2.0), col)
		legs[side] = {"hip": hip, "knee": knee, "ankle": ankle}
	for m in pelvis.get_node("Spine1").find_children("*", "MeshInstance3D", true, false) \
			+ pelvis.find_children("*", "MeshInstance3D", false, false):
		m.layers = 2 # hips and up: hidden from the head-down feet camera
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		solve_leg(side, global_transform * Vector3(0.18 * sx, ANKLE_H, 0))


## Pose the dancer. `feet` maps "L"/"R" to dancer-frame Vector3(x, lift, z) of the sole,
## `pitch` maps side to foot pitch, `c` is the dancer-frame pelvis position (x, _, z),
## `dip` lowers the pelvis from `height`. `style` (all optional): hip `yaw` in radians
## (+ = right hip forward), `arm_forward`/`arm_out` upper-arm angles, `elbow` bend.
func apply(feet: Dictionary, pitch: Dictionary, c: Vector3, height: float, dip: float, style := {}) -> void:
	var yaw: float = style.get("yaw", 0.0)
	pelvis.rotation.y = yaw
	for i in 3:
		spine[i].rotation.y = -yaw * SPINE_UNTWIST[i]
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		arms[side].upper.rotation = Vector3(style.get("arm_forward", 0.0), 0, style.get("arm_out", 0.12) * sx)
		arms[side].fore.rotation = Vector3(style.get("elbow", 0.35), style.get("forearm_in", 0.0) * sx, 0)
	var y := height - dip
	for side in ["L", "R"]: # wide stance: sink the pelvis just enough that both legs keep a slight bend
		var f: Vector3 = feet[side]
		var hx := HIP_X * (-1.0 if side == "L" else 1.0)
		var hip := Vector2(c.x + hx * cos(yaw), c.z + hx * sin(yaw))
		var flat := hip.distance_to(Vector2(f.x, f.z))
		var reach := (THIGH + SHIN) * 0.97
		y = minf(y, _ankle_h(pitch.get(side, 0.0)) + f.y + HIP_DROP + sqrt(maxf(reach * reach - flat * flat, 0.0)))
	pelvis.position = Vector3(c.x, y, -c.z)
	for side in ["L", "R"]:
		var f: Vector3 = feet[side]
		var ph: float = pitch.get(side, 0.0)
		solve_leg(side, global_transform * Vector3(f.x, _ankle_h(ph) + f.y, -f.z), ph)


## Ankle height that puts the lowest point of a foot pitched by `ph` on the sole height
## (toe-down: the toe tip touches, as in a tap).
static func _ankle_h(ph: float) -> float:
	return ANKLE_H * cos(ph) + maxf(-FOOT_TOE * sin(ph), FOOT_HEEL * sin(ph))


## Two-bone IK: place the ankle of `side` at world `target`, knee bending forward.
## `pitch` is the foot's rotation about the dancer's lateral axis (+ = toe up).
func solve_leg(side: String, target: Vector3, pitch := 0.0) -> void:
	var leg: Dictionary = legs[side]
	var hip_p: Vector3 = leg.hip.global_position
	var to := target - hip_p
	var d := clampf(to.length(), 0.01, THIGH + SHIN - 0.001)
	var dir := to.normalized()
	var fwd := global_basis * Vector3.FORWARD
	var pole := (fwd - dir * fwd.dot(dir)).normalized()
	var a := (THIGH * THIGH - SHIN * SHIN + d * d) / (2.0 * d) # law of cosines along hip->ankle
	var knee_p := hip_p + dir * a + pole * sqrt(maxf(THIGH * THIGH - a * a, 0.0))
	leg.hip.global_basis = _bone_basis(hip_p, knee_p, fwd)
	leg.knee.global_basis = _bone_basis(knee_p, hip_p + dir * d, fwd)
	leg.ankle.global_basis = global_basis * Basis(Vector3.RIGHT, pitch)


## Basis whose -Y runs from `from` to `to` and whose -Z leans toward `fwd`.
func _bone_basis(from: Vector3, to: Vector3, fwd: Vector3) -> Basis:
	var y := (from - to).normalized()
	var z := (-fwd - y * (-fwd).dot(y)).normalized()
	return Basis(y.cross(z), y, z)


func _joint(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = pos
	parent.add_child(j)
	return j


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


## Capsule from the joint along -Y (or +Y when up) for `length`.
func _capsule(j: Node3D, length: float, r: float, c: Color, up := false) -> void:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = length + r * 2.0
	m.material = _mat(c)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position.y = length * (0.5 if up else -0.5)
	j.add_child(mi)


func _box(j: Node3D, size: Vector3, pos: Vector3, c: Color) -> void:
	var m := BoxMesh.new()
	m.size = size
	m.material = _mat(c)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	j.add_child(mi)


func _sphere(j: Node3D, r: float, pos: Vector3, c: Color) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.material = _mat(c)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	j.add_child(mi)
