extends Node3D
## Playback (BPM, play/pause, beat stepping, loop, speed), basic switching on count 1,
## footprints, beat counter, weight marker, cameras, music.

const Choreo := preload("res://scripts/choreo.gd")
const Dancer := preload("res://scripts/dancer.gd")
const GOLD := Color(1.0, 0.8, 0.2)
const SIDE_COL := {"L": Color(0.25, 0.45, 0.95), "R": Color(0.95, 0.3, 0.25)}
const FOOT_FWD := 0.07 # footprint centre sits this far ahead of the ankle
const CAM_NAMES := ["Behind", "Front", "Feet (from head)", "Feet (side)", "Behind 30°", "Front 30°", "Behind 45°", "Front 45°"]

@onready var dancer := $Dancer

var ch: Choreo
var T := -1.0 # unwrapped beat clock; 8 beats per basic. -1 = count 8, so playback starts by stepping into 1
var glide := 0.0 # beats still to travel after a beat-step button, played out at tempo
var prev_basic: String
var cur_basic: String
var queued: String # takes over at the next count 1
var playing := true
var looping := true
var bpm := 100.0
var speed := 1.0

var ui := {}
var prints := {} # "side:x,z" -> {mesh, ring, label}
var prints_basic := "" # "basic|role" the footprints were built for
var weight_disc: MeshInstance3D
var cams: Array[Camera3D] = []
var music := AudioStreamPlayer.new()
var music_on := true
var floor_numbers := false # count labels on the footprints
var style: String # target style; `look` eases toward it so switching never snaps
var look := {}
var follower: Node3D
var main_is_follower := false # whose point of view: cameras, footprints and weight follow the main dancer
var pov := Node3D.new() # eases onto the main dancer's transform; all cameras hang under it
var rig := Node3D.new() # under pov: cameras that frame the couple, centred between them when both dance
var stretch := AudioEffectPitchShift.new()
var next_seek_ms := 0
var tick := AudioStreamPlayer.new() # counts are clicked when the music is off
var tick_sound := _click(1500.0, 0.035)
var tap_sound := _click(2600.0, 0.06)


func _ready() -> void:
	ch = Choreo.new("res://data/routine.json")
	bpm = ch.p.bpm
	prev_basic = ch.start_basic
	cur_basic = ch.start_basic
	queued = ch.start_basic
	style = ch.start_style
	for k in ch.styles[style]:
		if k != "label":
			look[k] = ch.styles[style][k]
	add_child(pov)
	pov.add_child(rig)
	# [eye, look-at] per entry in CAM_NAMES. Dancer stands at the origin facing -Z, right = +X.
	var r30 := Basis(Vector3.UP, deg_to_rad(30)) # orbit toward the dancer's right
	var r45 := Basis(Vector3.UP, deg_to_rad(45))
	for v in [[Vector3(0, 1.5, 2.3), Vector3(0, 0.55, -0.1)], [Vector3(0, 1.5, -2.4), Vector3(0, 0.6, 0)],
			[Vector3(0, 1.78, 0.32), Vector3(0, 0, -0.18)], [Vector3(2.6, 0.45, -0.05), Vector3(0, 0.12, -0.05)],
			[r30 * Vector3(0, 1.5, 2.3), Vector3(0, 0.55, 0)], [r30.inverse() * Vector3(0, 1.5, -2.4), Vector3(0, 0.6, 0)],
			[r45 * Vector3(0, 1.5, 2.3), Vector3(0, 0.55, 0)], [r45.inverse() * Vector3(0, 1.5, -2.4), Vector3(0, 0.6, 0)]]:
		var cam := Camera3D.new()
		cam.near = 0.03
		if cams.size() == 2:
			cam.cull_mask = 1 # feet cam skips the upper body (layer 2)
		if cams.size() == 3:
			cam.fov = 38 # side close-up from far enough to keep wide steps in frame
		(pov if cams.size() == 2 else rig).add_child(cam) # the head-down cam stays the main dancer's view
		cam.look_at_from_position(v[0], v[1])
		cams.append(cam)
	_build_ui()
	set_camera(0)
	pick_basic(ch.start_basic)
	var stream: AudioStreamMP3 = load(ch.p.music)
	stream.loop = true
	stream.bpm = ch.p.music_bpm
	stream.beat_count = int(ch.p.music_beats) # loop on the beat grid, not the mp3's padded end
	music.stream = stream
	# Web defaults to browser-native samples, which report no playback position: the sync then
	# re-seeked every frame (heard as buzzing). Engine-mixed streams report it and allow the effect.
	music.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(music)
	add_child(tick)
	AudioServer.add_bus_effect(0, stretch)
	follower = Dancer.new()
	follower.name = "Follower"
	follower.head_color = Color(1.0, 0.55, 0.1)
	follower.hand_color = Dancer.COL_BODY
	follower.hand_size = 0.042
	follower.position = Vector3(0, 0, -ch.p.partner_distance) # in front of the leader, facing him
	follower.rotation.y = PI
	add_child(follower)
	set_main(false)
	weight_disc = _flat(CylinderMesh.new(), GOLD, 0.8)
	weight_disc.mesh.top_radius = 0.13
	weight_disc.mesh.bottom_radius = 0.13
	weight_disc.mesh.height = 0.004
	add_child(weight_disc)


func _process(dt: float) -> void:
	var rate := bpm / 60.0 * speed
	var bar := floori(T / 8.0)
	var T0 := T
	if playing:
		T += dt * rate
	elif glide != 0.0:
		var d := clampf(glide, -dt * rate, dt * rate)
		T += d
		glide -= d
	var new_bar := floori(T / 8.0)
	if new_bar > bar:
		if looping:
			prev_basic = cur_basic
			cur_basic = queued
		else:
			T = bar * 8 + 7.0 # stop on count 8
			playing = false
			glide = 0.0
	elif new_bar < bar:
		prev_basic = cur_basic # stepping back over count 1: stay in this basic
	var t := fposmod(T, 8.0)
	var pose := ch.sample(t, prev_basic, cur_basic, queued)
	if not music_on and (floori(T) > floori(T0) or ceili(T) < ceili(T0)): # landed on a count
		var st: Dictionary = ch.basics[cur_basic][posmod(roundi(T), 8)]
		tick.stream = tap_sound if "tap" in st.action.values() else tick_sound
		tick.play()
	for k in look:
		look[k] = lerpf(look[k], ch.styles[style][k], 1.0 - exp(-dt * 6.0))
	# count 8 with a different basic queued: the leader prepares the change. His hands glow and
	# his arms (shoulder, elbow, wrist) draw away from the next basic's first step, leading her.
	var prep := 0.0
	if queued != cur_basic:
		prep = smoothstep(6.5, 7.0, t) * (1.0 - smoothstep(7.6, 8.0, t))
	dancer.set_halo(prep * (0.8 + 0.2 * sin(TAU * 2.0 * t)))
	var away := -ch.first_step(queued) # dancer frame
	var lead: Vector3 = dancer.global_basis * Vector3(away.x, 0, -away.z) * prep * ch.p.prep_reach
	var lead_style := look.duplicate()
	lead_style.yaw = look.hip_twist * pose.twist
	lead_style.lead = lead * ch.p.prep_shoulder
	dancer.apply(pose.feet, pose.pitch, pose.pelvis, ch.p.pelvis_height, pose.dip, lead_style)
	var ease := 1.0 - exp(-dt * 4.0)
	var centre: float = -ch.p.partner_distance / 2.0 if follower.visible else 0.0
	rig.position.z = lerpf(rig.position.z, centre, ease)
	pov.transform = pov.transform.interpolate_with(main_dancer().transform, ease)
	var main_pose := pose
	if follower.visible:
		var m := ch.sample(t, prev_basic, cur_basic, queued, true)
		if main_is_follower:
			main_pose = m
		var look_f := look.duplicate()
		look_f.yaw = look.hip_twist * m.twist
		look_f.lead = lead * ch.p.prep_shoulder # she is led: her shoulders give the same way
		follower.apply(m.feet, m.pitch, m.pelvis, ch.p.pelvis_height, m.dip, look_f)
		for side in ["L", "R"]: # leader's hand `side` holds the follower's opposite hand
			var other := "R" if side == "L" else "L"
			var at: Vector3 = Dancer.hold_point(dancer.arms[side].upper.global_position,
				follower.arms[other].upper.global_position, ch.p.hold_drop) + lead
			var h: float = 1.0 - look.release_hands * pose.free[side]
			dancer.hold(side, at, h)
			follower.hold(other, at, h)
	ui.play.text = "Pause" if playing else "Play"
	_update_markers(main_pose, t)
	_sync_music()


## Music follows the dance clock: count 1 of the routine = music beat 0. Tempo is
## time-stretched to bpm*speed with pitch kept by the PitchShift effect.
func _sync_music() -> void:
	if not (playing and music_on):
		music.stream_paused = true
		return
	var rate: float = bpm * speed / ch.p.music_bpm
	music.pitch_scale = rate
	stretch.pitch_scale = 1.0 / rate
	var beats: float = ch.p.music_beats
	var want: float = fposmod(T, beats) * 60.0 / ch.p.music_bpm + ch.p.music_offset
	var length: float = beats * 60.0 / ch.p.music_bpm
	if not music.playing:
		music.play(want)
	music.stream_paused = false
	var heard := music.get_playback_position() + (AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * rate
	var err := wrapf(heard - want, -length / 2.0, length / 2.0)
	if absf(err) > 0.25:
		if Time.get_ticks_msec() >= next_seek_ms: # never seek in a tight loop
			next_seek_ms = Time.get_ticks_msec() + 1000
			music.seek(want) # after a jump (beat step, resume): realign the audio once
	else:
		T += err * ch.p.music_bpm / 60.0 * 0.05 # otherwise ease the dance clock onto the audio, no audible seeks


## Floor position (Godot) of the footprint for a dancer-frame foot position.
func _floor_pos(f: Vector3, y := 0.002) -> Vector3:
	return main_dancer().global_transform * Vector3(f.x, y, -f.z - FOOT_FWD)


func main_dancer() -> Node3D:
	return follower if main_is_follower else dancer


## Choose the main dancer; the other one turns see-through. The follower must be dancing to be main.
func set_main(is_follower: bool) -> void:
	main_is_follower = is_follower and follower.visible
	dancer.set_alpha(0.3 if main_is_follower else 1.0)
	follower.set_alpha(1.0 if main_is_follower else 0.3)
	if ui.has("main"):
		ui.main.set_pressed_no_signal(main_is_follower)
		ui.main.text = "Main: %s  (P)" % ("Follower" if main_is_follower else "Leader")


func _update_markers(pose: Dictionary, t: float) -> void:
	var i := int(floor(t))
	var st: Dictionary = pose.state
	if "%s|%s" % [cur_basic, main_is_follower] != prints_basic:
		_build_prints(cur_basic)
	for key in prints:
		var pr: Dictionary = prints[key]
		var side: String = key.left(1)
		var act: String = st.action[side]
		var active: bool = act in ["step", "place", "tap"] and _key(side, st.feet[side]) == key
		pr.mesh.material_override.albedo_color.a = 0.85 if active else 0.3
		if pr.ring:
			var pulse := 1.0 + 0.8 * (1.0 - (t - i)) if active and act == "tap" else 1.0
			pr.ring.scale = Vector3(pulse, 1, pulse)
	var w_side := "R" if pose.w_r >= 0.5 else "L"
	weight_disc.position = _floor_pos(pose.feet[w_side], 0.001)

	for k in 8:
		var c := k + 1
		var lbl: Label = ui.counts[k]
		var cur: bool = c == st.count
		var tap := c == 4 or c == 8
		var col := GOLD if tap else Color(0.85, 0.85, 0.9)
		lbl.add_theme_color_override("font_color", col if cur else col.darkened(0.55))
		lbl.add_theme_font_size_override("font_size", 84 if cur else 52)
	ui.info.text = ch.labels[cur_basic]
	if queued != cur_basic:
		ui.info.text += "   •   %s on the next 1" % ch.labels[queued]


func _key(side: String, f: Vector3) -> String:
	return "%s:%.2f,%.2f" % [side, f.x, f.z]


## Footprints for one basic.
func _build_prints(basic: String) -> void:
	prints_basic = "%s|%s" % [basic, main_is_follower]
	for pr in prints.values():
		pr.mesh.queue_free()
	prints.clear()
	var counts := {}
	for st in (ch.follower if main_is_follower else ch.basics)[basic]:
		for side in ["L", "R"]:
			if st.action[side] in ["step", "place", "tap"]:
				var key := _key(side, st.feet[side])
				if not counts.has(key):
					counts[key] = {"pos": st.feet[side], "counts": [], "tap": false}
				counts[key].counts.append(st.count)
				counts[key].tap = counts[key].tap or st.action[side] == "tap"
	for key in counts:
		var side: String = key.left(1)
		var info: Dictionary = counts[key]
		var box := BoxMesh.new()
		box.size = Vector3(0.10, 0.004, 0.26)
		var m := _flat(box, SIDE_COL[side], 0.3)
		m.transform = Transform3D(main_dancer().global_basis, _floor_pos(Vector3(info.pos.x, 0, info.pos.z))) # labels read from the main POV
		add_child(m)
		var lbl := Label3D.new()
		lbl.text = side + "\n" + " ".join(info.counts.map(func(c): return str(c)))
		lbl.font_size = 32
		lbl.pixel_size = 0.004
		lbl.outline_size = 10
		lbl.rotation_degrees.x = -90
		lbl.modulate = SIDE_COL[side].lightened(0.5)
		lbl.position = Vector3(signf(info.pos.x) * 0.2, 0.006, 0) # outward, so crossed steps don't swap labels
		lbl.visible = floor_numbers
		m.add_child(lbl)
		var ring: MeshInstance3D = null
		if info.tap:
			var tor := TorusMesh.new()
			tor.inner_radius = 0.15
			tor.outer_radius = 0.17
			ring = _flat(tor, GOLD, 0.9)
			ring.scale = Vector3.ONE
			m.add_child(ring)
		prints[key] = {"mesh": m, "ring": ring, "label": lbl}


func _flat(mesh: Mesh, col: Color, alpha: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col, alpha)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Glide to the next/previous count at the current tempo instead of jumping.
func step_beat(dir: int) -> void:
	playing = false
	glide = roundf(T + glide) + dir - T


func toggle_play() -> void:
	playing = not playing
	glide = 0.0


func set_camera(k: int) -> void:
	cams[k].make_current()
	ui.cam.select(k)


func pick_basic(basic: String) -> void:
	queued = basic
	for name in ui.basic_buttons:
		ui.basic_buttons[name].button_pressed = name == basic


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.is_pressed():
		return
	match e.keycode:
		KEY_SPACE: toggle_play()
		KEY_RIGHT: step_beat(1)
		KEY_LEFT: step_beat(-1)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8: set_camera(e.keycode - KEY_1)
		KEY_M: ui.music.button_pressed = not music_on
		KEY_F: ui.follower.button_pressed = not follower.visible
		KEY_P: set_main(not main_is_follower)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 8
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	top.add_child(row)
	ui.counts = []
	for c in range(1, 9):
		var l := _label(row, str(c))
		l.custom_minimum_size = Vector2(56, 110)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 8)
		ui.counts.append(l)
	ui.info = _label(top, "")
	ui.info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.info.add_theme_font_size_override("font_size", 20)

	# top right: camera dropdown
	ui.cam = OptionButton.new()
	for k in CAM_NAMES.size():
		ui.cam.add_item("%d  %s" % [k + 1, CAM_NAMES[k]])
	ui.cam.focus_mode = Control.FOCUS_NONE
	ui.cam.item_selected.connect(set_camera)
	_corner(layer, ui.cam, Control.PRESET_TOP_RIGHT)

	# top left: style (how much body movement goes on top of the footwork)
	var style_box := OptionButton.new()
	for name in ch.styles:
		style_box.add_item("Style: " + ch.styles[name].label)
		if name == style:
			style_box.select(style_box.item_count - 1)
	style_box.focus_mode = Control.FOCUS_NONE
	style_box.item_selected.connect(func(k): style = ch.styles.keys()[k])
	var top_left := HBoxContainer.new()
	top_left.add_child(style_box)
	ui.follower = _button(top_left, "Follower  (F)", func(): pass)
	ui.follower.toggle_mode = true
	ui.follower.button_pressed = true
	ui.follower.toggled.connect(func(on):
		follower.visible = on
		set_main(main_is_follower)) # hiding the follower hands the main role back to the leader
	ui.main = _button(top_left, "", func(): set_main(not main_is_follower))
	ui.main.toggle_mode = true
	_corner(layer, top_left, Control.PRESET_TOP_LEFT)

	# bottom centre: transport
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 8)
	_button(transport, "< Beat", step_beat.bind(-1))
	ui.play = _button(transport, "Pause", toggle_play)
	ui.play.custom_minimum_size.x = 80
	_button(transport, "Beat >", step_beat.bind(1))
	_corner(layer, transport, Control.PRESET_CENTER_BOTTOM)

	# bottom left: settings, collapsed under a gear
	var settings := VBoxContainer.new()
	var panel := PanelContainer.new()
	panel.visible = false
	settings.add_child(panel)
	var opts := VBoxContainer.new()
	panel.add_child(opts)
	var loop := _check(opts, "Loop", looping, func(on): looping = on)
	loop.tooltip_text = "Off: stop on count 8"
	ui.music = _check(opts, "Music  (M)", music_on, func(on): music_on = on)
	_check(opts, "Floor numbers", floor_numbers, func(on):
		floor_numbers = on
		for pr in prints.values():
			pr.label.visible = on)
	var bpm_row := HBoxContainer.new()
	opts.add_child(bpm_row)
	_label(bpm_row, "BPM")
	var bpm_box := SpinBox.new()
	bpm_box.min_value = 40
	bpm_box.max_value = 220
	bpm_box.value = bpm
	bpm_box.value_changed.connect(func(v): bpm = v)
	bpm_row.add_child(bpm_box)
	var speed_lbl := _label(opts, "Speed 1.00x")
	var sl := HSlider.new()
	sl.min_value = 0.25
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = speed
	sl.custom_minimum_size.x = 160
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(v): speed = v; speed_lbl.text = "Speed %.2fx" % v)
	opts.add_child(sl)
	var gear := _button(settings, "", func(): panel.visible = not panel.visible)
	gear.icon = load("res://assets/gear.svg")
	gear.tooltip_text = "Settings"
	gear.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_corner(layer, settings, Control.PRESET_BOTTOM_LEFT)

	# bottom right: basics (switch on the next count 1) + music credit
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	var credit := _label(right, "Music: \"Salsa 90 BPM\" by TheLastOneOnEarth (freesound.org), CC BY 4.0")
	credit.add_theme_font_size_override("font_size", 11)
	credit.modulate.a = 0.6
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var basics_row := HBoxContainer.new()
	basics_row.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(basics_row)
	ui.basic_buttons = {}
	var group := ButtonGroup.new()
	for name in ch.basics:
		var b := _button(basics_row, ch.labels[name], pick_basic.bind(name))
		b.toggle_mode = true
		b.button_group = group
		ui.basic_buttons[name] = b
	_corner(layer, right, Control.PRESET_BOTTOM_RIGHT)


## Pin `c` to a screen corner/edge; it sizes itself to its content and grows inward.
func _corner(layer: CanvasLayer, c: Control, preset: Control.LayoutPreset) -> void:
	layer.add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 10)
	var left := preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]
	var up := preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM]
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH if preset == Control.PRESET_CENTER_BOTTOM \
		else (Control.GROW_DIRECTION_BEGIN if left else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if up else Control.GROW_DIRECTION_END


## Short decaying sine "click" generated in code (no audio asset needed).
static func _click(freq: float, length: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var x := float(i) / rate
		data.encode_s16(i * 2, int(sin(TAU * freq * x) * exp(-x / length * 6.0) * 0.5 * 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _check(parent: Control, text: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	parent.add_child(c)
	return c


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE # keep Space/arrows for the shortcuts
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _label(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l
