extends SceneTree

var failures := 0
var app: Control
var snapshot := PackedByteArray()
var captured := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	app = load("res://main.tscn").instantiate()
	app.set_script(load("res://tests/smoke_host.gd"))
	root.add_child(app)
	app.paused = true
	for frame in range(300):
		await process_frame
		if app.initialized:
			break
	if not app.initialized:
		push_error("APP_SMOKE: initialization failed")
		quit(1)
		return
	var original_state: RID = app.physics.state
	await _capture_state()
	var initial := snapshot.duplicate()
	await _screenshot("app-initial.png")
	# Exercise the actual mouse input handler, not only the angle setter.
	var center: Vector2 = app.picture.position + app.picture.size * 0.5
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center + Vector2(100, 0)
	Input.parse_input_event(press)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = center + Vector2(0, 100)
	Input.parse_input_event(motion)
	await process_frame
	_check(absf(app.director.angle_degrees - 90.0) < 1.0, "mouse quarter rotation")
	press.pressed = false
	press.position = motion.position
	Input.parse_input_event(press)
	await process_frame
	await _capture_state()
	_check(snapshot == initial, "rotation while paused preserves bytes")
	root.size = Vector2i(820, 740)
	await process_frame
	await _capture_state()
	_check(snapshot == initial, "resize preserves bytes")
	app._set_angle(0.0)
	await _advance(600)
	await _capture_state()
	_check(snapshot != initial, "GPU world evolves")
	_check(_counts(snapshot) == _counts(initial), "main-device material conservation")
	await _screenshot("app-tick-600.png")
	await _advance(2400)
	await _capture_state()
	_check(_counts(snapshot)==_counts(initial),"longer evolution conservation")
	await _screenshot("app-tick-3000.png")
	var same_state:=snapshot.duplicate()
	for mode in range(5):
		app._select_resource(mode)
		await _capture_state()
		_check(snapshot==same_state,"budget switch preserves state")
	app._select_resource(2)
	app.set_art_style(false)
	while app.pending:await process_frame
	await _capture_state()
	_check(snapshot==same_state,"art style preserves physical state")
	await _screenshot("app-raw-same-state.png")
	app.set_art_style(true)
	while app.pending:await process_frame
	await _capture_state()
	_check(snapshot==same_state,"restored art style preserves physical state")
	await _screenshot("app-mineral-same-state.png")
	var settled := snapshot.duplicate()
	app._set_angle(180.0)
	await _capture_state()
	_check(snapshot == settled, "flip does not regenerate")
	await _advance(3000)
	await _capture_state()
	_check(snapshot != settled, "flip changes subsequent physical evolution")
	_check(_counts(snapshot) == _counts(initial), "flip conservation")
	_check(app.physics.state == original_state, "persistent state RID")
	await _screenshot("app-flipped.png")
	print("APP_SMOKE_RESULT failures=%d tick=%d counts=%s" % [failures, app.completed_tick, _counts(snapshot)])
	var report := FileAccess.open("res://reports/app-smoke-%d.json" % app.grid_size, FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures": failures, "side": app.grid_size, "tick": app.completed_tick, "counts": _counts(snapshot), "engine": Engine.get_version_info().string}, "  "))
	report.close()
	# Use the real asynchronous release path and exit code after it completes.
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func _advance(ticks: int) -> void:
	for batch in range(ceili(ticks / 8.0)):
		app.pending = true
		RenderingServer.call_on_render_thread(app._update_gpu.bind(app.director.gravity(), mini(8,ticks-batch*8)))
		while app.pending:
			await process_frame

func _capture_state() -> void:
	captured = false
	RenderingServer.call_on_render_thread(_read_state)
	while not captured:
		await process_frame

func _read_state() -> void:
	var data: PackedByteArray = app.physics.rd.texture_get_data(app.physics.state, 0)
	_received.call_deferred(data)

func _received(data: PackedByteArray) -> void:
	snapshot = data
	captured = true

func _counts(data: PackedByteArray) -> Array:
	var counts := [0, 0, 0, 0, 0, 0]
	for index in range(data.size() / 4):
		var value := data.decode_u32(index * 4)
		if value > 5:
			_check(false, "invalid material")
		else:
			counts[value] += 1
	return counts

func _screenshot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/" + filename.replace(".png", "-%d.png" % app.grid_size))

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("APP_SMOKE_FAIL: " + message)
