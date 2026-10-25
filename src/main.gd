extends Control

const StateManager=preload("res://src/simulation_state_manager.gd")
const Physics = preload("res://src/physics_engine.gd")
const Art = preload("res://src/art_renderer.gd")
const Director = preload("res://src/aesthetic_director.gd")
const Resources = preload("res://src/adaptive_resource_manager.gd")
var physics := Physics.new()
var art := Art.new()
var director := Director.new()
var budget := Resources.new()
var picture: TextureRect
var status: Label
var angle_slider: HSlider
var resource_picker:OptionButton
var art_dirty:=false
var glass: ShaderMaterial
var shared_texture: Texture2DRD
var initialized := false
var pending := false
var paused := false
var dragging := false
var last_drag_angle := 0.0
var completed_tick := 0
var grid_size := 256
var world_seed := 20261024
var closing := false
var mineral_style := true
var session_enabled:=true
var sessions:=StateManager.new()
var restored_session:Dictionary={}
var session_age:=0.0
var session_note:=""

func _ready() -> void:
	grid_size = int(ProjectSettings.get_setting("application_settings/simulation/size", 256))
	world_seed = int(ProjectSettings.get_setting("application_settings/simulation/seed", 20261024))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			world_seed = argument.trim_prefix("--seed=").to_int() & 0xffffffff
		if argument.begins_with("--size="):
			grid_size = argument.trim_prefix("--size=").to_int()
	if grid_size not in [256, 512, 1024]:
		grid_size = 256
	if "--fresh-session" in OS.get_cmdline_user_args():
		session_enabled=false;session_note="Temporary session (not saved)"
	if session_enabled:
		restored_session=sessions.load_latest();session_note=sessions.message
		if not restored_session.is_empty():
			grid_size=int(restored_session.side);world_seed=int(restored_session.seed);paused=restored_session.paused;mineral_style=restored_session.mineral_style
		elif not session_note.is_empty():session_enabled=false
	budget.select_preset(int(restored_session.get("resource_preset",2)))
	_build_ui()
	if not restored_session.is_empty():_set_angle(float(restored_session.angle))
	Engine.max_fps = 60
	get_tree().auto_accept_quit = false
	if RenderingServer.get_rendering_device() == null:
		status.text = "GPU compute unavailable. Run with Vulkan / Mobile or Forward+."
		return
	RenderingServer.call_on_render_thread(_initialize_gpu)

func _build_ui() -> void:
	var title := Label.new()
	title.text = "DIGITAL SANDSCAPE"
	title.position = Vector2(40, 22)
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)
	resource_picker=OptionButton.new()
	for index in range(Resources.NAMES.size()):resource_picker.add_item("%s · target %d%%" % [Resources.NAMES[index],Resources.TARGETS[index]])
	resource_picker.select(budget.preset)
	resource_picker.tooltip_text="Requested budget, not a utilization limit. GPU cost/utilization unavailable; cadence adapts using frame-time proxy."
	resource_picker.item_selected.connect(_select_resource)
	add_child(resource_picker)
	picture = TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glass = ShaderMaterial.new()
	glass.shader = load("res://shaders/glass.gdshader")
	picture.material = glass
	add_child(picture)
	angle_slider = HSlider.new()
	angle_slider.min_value = 0.0
	angle_slider.max_value = 360.0
	angle_slider.step = 0.1
	angle_slider.value_changed.connect(_set_angle)
	add_child(angle_slider)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 14)
	status.text = "Initializing GPU compute..."
	add_child(status)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	resource_picker.position=Vector2(maxf(300.,size.x-245.),20.)
	resource_picker.size=Vector2(205.,32.)
	var diameter := maxf(80.0, minf(size.x - 80.0, size.y - 180.0))
	picture.position = Vector2((size.x - diameter) * 0.5, 65)
	picture.size = Vector2.ONE * diameter
	angle_slider.position = Vector2(80, size.y - 90)
	angle_slider.size = Vector2(maxf(100, size.x - 160), 24)
	status.position = Vector2(40, size.y - 55)

func _initialize_gpu() -> void:
	var device := RenderingServer.get_rendering_device()
	if not physics.initialize(device, grid_size, world_seed, true, restored_session.get("bytes",PackedByteArray())):
		_gpu_failed.call_deferred(physics.error_message)
		return
	if not restored_session.is_empty():physics.tick=int(restored_session.tick)
	if not art.initialize(device, physics.state, grid_size):
		_gpu_failed.call_deferred("Art compute initialization failed. See console.")
		return
	art.mineral_filter=mineral_style
	art.refresh()
	_gpu_ready.call_deferred(art.texture)

func _gpu_ready(texture_rid: RID) -> void:
	if closing:
		return
	shared_texture = Texture2DRD.new()
	shared_texture.texture_rd_rid = texture_rid
	picture.texture = shared_texture
	completed_tick=int(restored_session.get("tick",0))
	restored_session.erase("bytes")
	initialized = true

func _gpu_failed(message: String) -> void:
	status.text = message
	push_error(message)

func _process(delta: float) -> void:
	if not initialized or closing:
		return
	session_age+=delta
	if session_enabled and session_age>=120.0 and not pending:save_session();session_age=0.0
	var focused := get_window().has_focus()
	Engine.max_fps = budget.fps_limit(focused)
	# Only one outstanding render-thread package; do not accumulate GPU work.
	if not pending:
		var count := budget.schedule(delta, focused, paused)
		var redraw:=budget.render_due(delta,focused) and (art_dirty or count>0)
		if count>0 or redraw:
			art_dirty=(art_dirty or count>0) and not redraw
			pending = true
			RenderingServer.call_on_render_thread(_update_gpu.bind(director.gravity(), count,redraw))
	status.text = "Drag to rotate · Space pause · V texture · Ctrl+S save\n%.1f° · %s · physics %.0f Hz / display cap %d · requested %d%% (target)\nGPU cost/utilization unavailable · %s" % [director.angle_degrees,"Paused" if paused else "Running",budget.physics_rate(focused),Engine.max_fps,Resources.TARGETS[budget.preset],session_note]


func _update_gpu(gravity: Vector2i, count: int,redraw:bool=true) -> void:
	physics.advance(gravity, count)
	if redraw:art.refresh()
	_gpu_done.call_deferred(physics.tick)

func _gpu_done(tick_value: int) -> void:
	completed_tick = tick_value
	pending = false

func _select_resource(index:int)->void:
	if budget.select_preset(index):resource_picker.select(index)

func _set_angle(value: float) -> void:
	director.set_angle(value)
	glass.set_shader_parameter("angle", deg_to_rad(director.angle_degrees))
	angle_slider.set_value_no_signal(director.angle_degrees)

func set_art_style(filtered:bool)->void:
	if not initialized or pending or closing:return
	mineral_style=filtered
	pending=true
	RenderingServer.call_on_render_thread(_refresh_art_style.bind(filtered))

func _refresh_art_style(filtered:bool)->void:
	art.mineral_filter=filtered
	art.refresh()
	_gpu_done.call_deferred(physics.tick)

func session_metadata()->Dictionary:
	return {"side":grid_size,"seed":world_seed,"angle":director.angle_degrees,"paused":paused,"mineral_style":mineral_style,"resource_preset":budget.preset}

func save_session()->void:
	if not session_enabled or not initialized or pending or closing:return
	pending=true
	RenderingServer.call_on_render_thread(_save_session_gpu.bind(session_metadata()))

func _save_session_gpu(metadata:Dictionary)->void:
	metadata["tick"]=physics.tick & 0xffffffff
	sessions.save(physics.rd.texture_get_data(physics.state,0),metadata)
	_saved.call_deferred(sessions.message)

func _saved(note:String)->void:
	session_note=note;pending=false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_S and event.ctrl_pressed:
		save_session()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_V:
		set_art_style(not mineral_style)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		paused = not paused
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var offset := local_position - picture.position - picture.size * 0.5
		dragging = event.pressed and offset.length() < picture.size.x * 0.5 and offset.length() > 12.0
		last_drag_angle = offset.angle()
	if event is InputEventMouseMotion and dragging:
		var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var offset := local_position - picture.position - picture.size * 0.5
		if offset.length() > 12.0:
			var next_angle := offset.angle()
			_set_angle(director.angle_degrees + rad_to_deg(wrapf(next_angle - last_drag_angle, -PI, PI)))
			last_drag_angle = next_angle

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not closing:
		closing = true
		initialized = false
		picture.texture = null
		if shared_texture != null:
			shared_texture.texture_rd_rid = RID()
		RenderingServer.call_on_render_thread(_release_gpu.bind(session_metadata()))

func _release_gpu(metadata:Dictionary) -> void:
	if session_enabled and physics.state.is_valid():
		metadata["tick"]=physics.tick & 0xffffffff
		if not sessions.save(physics.rd.texture_get_data(physics.state,0),metadata):push_error(sessions.message)
	art.release()
	physics.release()
	_finish_close.call_deferred()

func _finish_close() -> void:
	get_tree().quit()
