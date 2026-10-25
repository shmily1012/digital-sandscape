extends "res://src/phase_preview.gd"
## Default product entry. Legacy and diagnostic hosts remain explicit tools.
const Rhythm = preload("res://src/rotation_rhythm.gd")
var rhythm := Rhythm.new()
var rhythm_mode := "Manual"
var applying_rhythm := false

func configure_profile()->void:
	with_sand=true
	contact_bed=false
	bubble_barrier=true
	sandscape_layout=true
	energy_persistence=true

func _set_angle(value: float) -> void:
	if not applying_rhythm and rhythm.enabled:
		rhythm.configure(false, 600.0, 15.0)
		rhythm_mode = "Manual"
	super._set_angle(value)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.keycode == KEY_A or event.keycode == KEY_M:
			var requested := "Meditation" if event.keycode == KEY_M else "Auto"
			var active := rhythm_mode != requested
			rhythm_mode = requested if active else "Manual"
			var wait_time := float(ProjectSettings.get_setting("application_settings/rotation/appreciation_seconds", 600.0))
			rhythm.configure(active, wait_time * (3.0 if requested == "Meditation" else 1.0), 60.0 if requested == "Meditation" else 15.0)
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _process(delta: float) -> void:
	if initialized and not closing and not paused and not pending and not dragging:
		applying_rhythm = true
		_set_angle(rhythm.advance(delta, director.angle_degrees))
		applying_rhythm = false
	super._process(delta)
	if initialized and not closing:
		status.text += "\nA auto · M meditation · %s · F10 ornament" % rhythm_mode
