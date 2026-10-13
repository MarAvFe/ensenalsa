extends Node3D
## Playback (BPM, play/pause, beat stepping, loop, speed), footprints, beat counter, weight marker.

const Choreo := preload("res://scripts/choreo.gd")
const GOLD := Color(1.0, 0.8, 0.2)
const SIDE_COL := {"L": Color(0.25, 0.45, 0.95), "R": Color(0.95, 0.3, 0.25)}
const FOOT_FWD := 0.07 # footprint centre sits this far ahead of the ankle

@onready var dancer := $Dancer

var ch: Choreo
var t := -1.0 # beats; -1 wraps to the last count so playback starts by stepping into count 1
var playing := true
var looping := true
var bpm := 100.0
var speed := 1.0

var ui := {}
var prints := {} # "side:x,z" -> {mesh, ring}
var prints_block := -1
var weight_disc: MeshInstance3D
var cams: Array[Camera3D] = []
var music := AudioStreamPlayer.new()
var music_on := true
var stretch := AudioEffectPitchShift.new()


func _ready() -> void:
	ch = Choreo.new("res://data/routine.json")
	bpm = ch.p.bpm
	t = fposmod(t, ch.size())
	# Behind, front, head-down-to-feet. Dancer stands at the origin facing -Z.
	for v in [[Vector3(0, 1.5, 2.3), Vector3(0, 0.55, -0.1)], [Vector3(0, 1.5, -2.4), Vector3(0, 0.6, 0)],
			[Vector3(0, 1.78, 0.32), Vector3(0, 0, -0.18)]]:
		var cam := Camera3D.new()
		cam.near = 0.03
		if cams.size() == 2:
			cam.cull_mask = 1 # feet cam skips the upper body (layer 2)
		add_child(cam)
		cam.look_at_from_position(v[0], v[1])
		cams.append(cam)
	_build_ui()
	set_camera(0)
	var stream: AudioStreamMP3 = load(ch.p.music)
	stream.loop = true
	stream.bpm = ch.p.music_bpm
	stream.beat_count = int(ch.p.music_beats) # loop on the beat grid, not the mp3's padded end
	music.stream = stream
	add_child(music)
	AudioServer.add_bus_effect(0, stretch)
	weight_disc = _flat(CylinderMesh.new(), GOLD, 0.8)
	weight_disc.mesh.top_radius = 0.13
	weight_disc.mesh.bottom_radius = 0.13
	weight_disc.mesh.height = 0.004
	add_child(weight_disc)


func _process(dt: float) -> void:
	if playing:
		t += dt * bpm / 60.0 * speed
		if t >= ch.size() and not looping:
			t = ch.size() - 1
			playing = false
		t = fposmod(t, ch.size())
	var pose := ch.sample(t)
	dancer.apply(pose.feet, pose.pitch, pose.w_r, ch.p.pelvis_over_foot, ch.p.pelvis_height, pose.dip)
	ui.play.text = "Pause" if playing else "Play"
	_update_markers(pose)
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
	var want: float = fposmod(t, beats) * 60.0 / ch.p.music_bpm + ch.p.music_offset
	var length: float = beats * 60.0 / ch.p.music_bpm
	if not music.playing:
		music.play(want)
	music.stream_paused = false
	var heard := music.get_playback_position() + (AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * rate
	var err := wrapf(heard - want, -length / 2.0, length / 2.0)
	if absf(err) > 0.25:
		music.seek(want) # after a jump (beat step, resume): realign the audio once
	else:
		t += err * ch.p.music_bpm / 60.0 * 0.05 # otherwise ease the dance clock onto the audio, no audible seeks


## Floor position (Godot) of the footprint for a dancer-frame foot position.
func _floor_pos(f: Vector3, y := 0.002) -> Vector3:
	return dancer.global_transform * Vector3(f.x, y, -f.z - FOOT_FWD)


func _update_markers(pose: Dictionary) -> void:
	var i := int(floor(t))
	var st: Dictionary = pose.state
	var block := i / 8 * 8
	if block != prints_block:
		_build_prints(block)
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
	ui.info.text = "%s  (%d/%d)   •   weight %s" % [st.basic.replace("_", " "), i / 8 + 1, ch.size() / 8, w_side]


func _key(side: String, f: Vector3) -> String:
	return "%s:%.2f,%.2f" % [side, f.x, f.z]


## Footprints for the 8-count block starting at state index `block`.
func _build_prints(block: int) -> void:
	prints_block = block
	for pr in prints.values():
		pr.mesh.queue_free()
	prints.clear()
	var counts := {}
	for st in ch.states.slice(block, block + 8):
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
		m.position = _floor_pos(Vector3(info.pos.x, 0, info.pos.z))
		add_child(m)
		var lbl := Label3D.new()
		lbl.text = side + "\n" + " ".join(info.counts.map(func(c): return str(c)))
		lbl.font_size = 32
		lbl.pixel_size = 0.004
		lbl.outline_size = 10
		lbl.rotation_degrees.x = -90
		lbl.modulate = SIDE_COL[side].lightened(0.5)
		lbl.position = Vector3(signf(info.pos.x) * 0.2, 0.006, 0) # outward, so crossed steps don't swap labels
		m.add_child(lbl)
		var ring: MeshInstance3D = null
		if info.tap:
			var tor := TorusMesh.new()
			tor.inner_radius = 0.15
			tor.outer_radius = 0.17
			ring = _flat(tor, GOLD, 0.9)
			ring.scale = Vector3.ONE
			m.add_child(ring)
		prints[key] = {"mesh": m, "ring": ring}


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


func step_beat(dir: int) -> void:
	playing = false
	t = fposmod(roundf(t) + dir, ch.size())


func set_camera(k: int) -> void:
	cams[k].make_current()
	for j in 3:
		ui.cam_buttons[j].button_pressed = j == k


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.is_pressed():
		return
	match e.keycode:
		KEY_SPACE: playing = not playing
		KEY_RIGHT: step_beat(1)
		KEY_LEFT: step_beat(-1)
		KEY_1, KEY_2, KEY_3: set_camera(e.keycode - KEY_1)
		KEY_M: ui.music.button_pressed = not music_on


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 8
	bar.offset_top = -44
	bar.offset_bottom = -8
	bar.add_theme_constant_override("separation", 8)
	layer.add_child(bar)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 8
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
	var credit := _label(layer, "Music: \"Salsa 90 BPM\" by TheLastOneOnEarth (freesound.org), CC BY 4.0")
	credit.add_theme_font_size_override("font_size", 11)
	credit.modulate.a = 0.6
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	credit.position.y -= 44 # sit above the control bar

	ui.play = _button(bar, "Pause", func(): playing = not playing)
	_button(bar, "< Beat", step_beat.bind(-1))
	_button(bar, "Beat >", step_beat.bind(1))
	var loop := CheckBox.new()
	loop.text = "Loop"
	loop.button_pressed = looping
	loop.toggled.connect(func(on): looping = on)
	loop.focus_mode = Control.FOCUS_NONE
	bar.add_child(loop)

	ui.music = CheckBox.new()
	ui.music.text = "Music"
	ui.music.button_pressed = music_on
	ui.music.toggled.connect(func(on): music_on = on)
	ui.music.focus_mode = Control.FOCUS_NONE
	bar.add_child(ui.music)

	_label(bar, "BPM")
	var bpm_box := SpinBox.new()
	bpm_box.min_value = 40
	bpm_box.max_value = 220
	bpm_box.value = bpm
	bpm_box.value_changed.connect(func(v): bpm = v)
	bar.add_child(bpm_box)

	var speed_lbl := _label(bar, "Speed 1.00x")
	var sl := HSlider.new()
	sl.min_value = 0.25
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = speed
	sl.custom_minimum_size.x = 140
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(v): speed = v; speed_lbl.text = "Speed %.2fx" % v)
	bar.add_child(sl)

	ui.cam_buttons = []
	var group := ButtonGroup.new()
	for k in 3:
		var b := _button(bar, ["1 Behind", "2 Front", "3 Feet"][k], set_camera.bind(k))
		b.toggle_mode = true
		b.button_group = group
		ui.cam_buttons.append(b)


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
