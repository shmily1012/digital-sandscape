extends Node
## Window-only integration; never reads or writes simulation state.
var ornament := false
var moving := false
var original_borderless := false
var original_top := false
var drag_pointer := Vector2i.ZERO
var drag_window := Vector2i.ZERO

func _ready() -> void:
	original_borderless = get_window().borderless
	original_top = get_window().always_on_top

func set_ornament(enabled: bool) -> void:
	ornament = enabled
	moving = false
	get_window().borderless = true if enabled else original_borderless
	if not enabled:
		get_window().always_on_top = original_top

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			set_ornament(not ornament)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and ornament:
			set_ornament(false)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9:
			get_window().always_on_top = not get_window().always_on_top
			get_viewport().set_input_as_handled()
	if not ornament:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		moving = event.pressed
		drag_pointer = DisplayServer.mouse_get_position()
		drag_window = get_window().position
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and moving:
		get_window().position = drag_window + DisplayServer.mouse_get_position() - drag_pointer
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		moving = false
