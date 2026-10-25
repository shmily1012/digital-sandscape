extends SceneTree
const Cell = preload("res://experiments/liquid/live_cell.gd")
var cell: Node
var picture: TextureRect
var shared_texture: Texture2DRD
var label: Label
var slider: HSlider
var simulation_paused := false
var closing := false
var smoke := false
var finalizing := false
var failures := 0
var sequence: Array
var latencies: Array = []
var started := 0
var readback := PackedByteArray()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 30
	auto_accept_quit = false
	root.size = Vector2i(640,680)
	root.title = "Digital Sandscape — Two-phase physics laboratory"
	smoke = "--lab-smoke" in OS.get_cmdline_user_args()
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/pressure-transport-fixtures.json"))
	sequence = JSON.parse_string(FileAccess.get_file_as_string("res://reports/capillary-sequence.json"))
	var fixture: Dictionary = fixtures[0]
	fixture.geometry.initial = sequence[0].initial
	picture = TextureRect.new()
	picture.position = Vector2(70,60)
	picture.size = Vector2(500,500)
	picture.pivot_offset = Vector2(250,250)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.add_child(picture)
	label = Label.new()
	label.position = Vector2(24,12)
	label.text = "Two-phase lab: gas / liquid only; no sand yet"
	root.add_child(label)
	slider = HSlider.new()
	slider.position = Vector2(50,580)
	slider.size = Vector2(540,24)
	slider.min_value = 0
	slider.max_value = 360
	slider.step = 0.1
	slider.value_changed.connect(func(value: float): picture.rotation = deg_to_rad(value))
	root.add_child(slider)
	var pause := Button.new()
	pause.position = Vector2(50,620)
	pause.text = "Pause / Resume"
	pause.pressed.connect(func(): simulation_paused = not simulation_paused)
	root.add_child(pause)
	cell = Cell.new()
	root.add_child(cell)
	cell.ready_gpu.connect(func(texture: RID):
		shared_texture = Texture2DRD.new()
		shared_texture.texture_rd_rid = texture
		picture.texture = shared_texture)
	cell.completed.connect(_completed)
	cell.closed.connect(func(): quit(1 if failures else 0))
	root.close_requested.connect(_close)
	process_frame.connect(_frame)
	started = Time.get_ticks_msec()
	cell.initialize(fixture)

func _frame() -> void:
	if closing or finalizing: return
	if smoke and Time.get_ticks_msec()-started>120000:
		failures += 1
		_close()
		return
	if simulation_paused or not cell.initialized or cell.pending: return
	if smoke and cell.ticks>=sequence.size():
		finalizing = true
		_finish_smoke()
		return
	var gravity := Vector2.DOWN.rotated(-deg_to_rad(slider.value))
	if smoke:
		gravity = Vector2(sequence[cell.ticks].gravity[0],sequence[cell.ticks].gravity[1])
		slider.value = 0 if gravity.y>0 else 180
	if cell.step(gravity) and smoke and cell.step(gravity): failures += 1

func _completed(result: Dictionary) -> void:
	if not result.accepted:
		simulation_paused = true
		label.text = "Step rejected; state retained. See logs."
		if smoke:
			failures += 1
			_close()
		return
	latencies.append(result.wall_ms)
	label.text = "Two-phase lab / no sand | tick %d | time %.5f\nGPU completion latency %.1f ms (not GPU execution time)" % [result.ticks,result.elapsed,result.wall_ms]

func _finish_smoke() -> void:
	if not cell.capture_for_test(func(data: PackedByteArray): readback = data):
		failures += 1
		_close()
		return
	while cell.pending: await process_frame
	var error := 0.0
	var area_error := 0.0
	if readback.size()!=4096:
		failures += 1
	else:
		for i in range(1024):
			var c := readback.decode_float(i*4)
			if not is_finite(c) or c < -2e-6 or c > 1+2e-6: failures += 1
			error = maxf(error,absf(c-float(sequence[-1].expected[i])))
			area_error += c-float(sequence[0].initial[i])
	area_error /= 1024.0
	if error>3e-4 or absf(area_error)>1e-6 or absf(cell.elapsed-float(sequence[-1].elapsed))>1e-6: failures += 1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/live-lab-smoke.png")
	latencies.sort()
	# Exercise shutdown with a real GPU step in flight after capturing validation state.
	var close_inflight: bool = cell.step(Vector2.DOWN)
	if not close_inflight: failures += 1
	var result := {"failures":failures,"ticks":cell.ticks,"elapsed":cell.elapsed,"max_fraction_error":error,"gas_area_error":area_error,"status_bytes":cell.status_bytes,"pressure_packets":cell.pressure_packets,"close_with_step_inflight":close_inflight,"completion_latency_median_ms":latencies[latencies.size()/2],"scope":"Main RenderingDevice real-time texture; one pending step, pressure batches of 8 with total limit 96, 32-byte combined asynchronous status packets; one test-only final full-state capture. Not sand or product visuals."}
	var file := FileAccess.open("res://reports/live-lab-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("LIVE_LAB_RESULT ",JSON.stringify(result))
	_close()

func _close() -> void:
	if closing: return
	closing = true
	picture.texture = null
	if shared_texture!=null: shared_texture.texture_rd_rid = RID()
	cell.close()


