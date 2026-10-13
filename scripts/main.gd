extends Node3D
## Playback: BPM, play/pause, beat stepping, loop, speed multiplier.

const Choreo := preload("res://scripts/choreo.gd")

@onready var dancer := $Dancer

var ch: Choreo
var t := -1.0 # beats; -1 wraps to the last count so playback starts by stepping into count 1
var playing := true
var looping := true
var bpm := 100.0
var speed := 1.0

var ui := {}


func _ready() -> void:
	ch = Choreo.new("res://data/routine.json")
	bpm = ch.p.bpm
	t = fposmod(t, ch.size())
	_build_ui()


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


func step_beat(dir: int) -> void:
	playing = false
	t = fposmod(roundf(t) + dir, ch.size())


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.is_pressed():
		return
	match e.keycode:
		KEY_SPACE: playing = not playing
		KEY_RIGHT: step_beat(1)
		KEY_LEFT: step_beat(-1)


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

	ui.play = _button(bar, "Pause", func(): playing = not playing)
	_button(bar, "< Beat", step_beat.bind(-1))
	_button(bar, "Beat >", step_beat.bind(1))
	var loop := CheckBox.new()
	loop.text = "Loop"
	loop.button_pressed = looping
	loop.toggled.connect(func(on): looping = on)
	loop.focus_mode = Control.FOCUS_NONE
	bar.add_child(loop)

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


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE # keep Space/arrows for the shortcuts
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _label(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l
