extends Node
signal ready_gpu(texture: RID)
signal completed(result: Dictionary)
signal closed
const Solver = preload("res://experiments/liquid/multigrid_gpu.gd")
const Transport = preload("res://experiments/liquid/geometric_gpu.gd")
const Force = preload("res://experiments/liquid/buoyancy_gpu.gd")
const Art = preload("res://experiments/liquid/live_art.gd")
var pending := false
var closing := false
var initialized := false
var ticks := 0
var elapsed := 0.0
var started := 0
var rd: RenderingDevice
var solver: RefCounted
var transport: RefCounted
var force: RefCounted
var art: RefCounted
var forcing: RID
var face_count := 0
var candidate: RID
var status_bytes := 0
var pressure_packets := 0
var combined_status: RID
var maximum_cycles := 96

func initialize(fixture: Dictionary) -> void:
	if pending or initialized or closing: return
	pending = true
	RenderingServer.call_on_render_thread(_initialize_gpu.bind(fixture))

func _initialize_gpu(fixture: Dictionary) -> void:
	rd = RenderingServer.get_rendering_device()
	solver = Solver.new()
	transport = Transport.new()
	force = Force.new()
	art = Art.new()
	if rd==null or not solver.initialize(rd,fixture.levels) or not transport.initialize(rd,fixture.geometry) or not force.initialize(rd) or not art.initialize(rd):
		_failed.call_deferred("initialization")
		return
	face_count = fixture.faces.size()
	var data := PackedByteArray()
	data.resize(face_count*16)
	for i in range(face_count):
		data.encode_u32(i*16,fixture.faces[i][0])
		data.encode_u32(i*16+4,fixture.faces[i][1])
		data.encode_float(i*16+8,fixture.faces[i][2])
	forcing = rd.storage_buffer_create(data.size(),data)
	combined_status = rd.storage_buffer_create(32)
	var list := rd.compute_list_begin()
	art.record(list,transport.output())
	rd.compute_list_end()
	_initialized.call_deferred(art.texture)

func _initialized(texture: RID) -> void:
	pending = false
	initialized = true
	if closing: close()
	else: ready_gpu.emit(texture)

func step(gravity: Vector2, cycle_limit: int = 96) -> bool:
	if not initialized or pending or closing or not gravity.is_finite() or cycle_limit<8 or cycle_limit>96 or cycle_limit%8!=0: return false
	maximum_cycles = cycle_limit
	pending = true
	started = Time.get_ticks_usec()
	RenderingServer.call_on_render_thread(_step_gpu.bind(gravity))
	return true

func _step_gpu(gravity: Vector2) -> void:
	solver.reset_statistics()
	var list := rd.compute_list_begin()
	force.record(list,transport.output(),forcing,transport.buffers[3],solver.levels[0].equations,32,face_count,gravity,0.02,0.001,5.0)
	candidate = solver.record_adaptive(list,8,2e-6)
	_record_conditional_transport(list)
	rd.compute_list_end()
	_request_pressure_status()

func _pressure_packet_gpu() -> void:
	var list := rd.compute_list_begin()
	candidate = solver.record_adaptive(list,8,2e-6)
	_record_conditional_transport(list)
	rd.compute_list_end()
	_request_pressure_status()

func _request_pressure_status() -> void:
	rd.buffer_copy(solver.control,combined_status,0,0,16)
	rd.buffer_copy(transport.buffers[10],combined_status,0,16,16)
	var error := rd.buffer_get_data_async(combined_status,_pressure_status_gpu,0,32)
	if error!=OK: _failed.call_deferred("pressure_status_readback")

func _pressure_status_gpu(data: PackedByteArray) -> void:
	_pressure_status.call_deferred(data)

func _pressure_status(data: PackedByteArray) -> void:
	status_bytes += data.size()
	pressure_packets += 1
	if closing:
		pending = false
		close()
		return
	if data.size()!=32 or data.decode_u32(12)!=0 or not is_finite(data.decode_float(0)):
		_failed("invalid_pressure")
	elif data.decode_u32(4)==1:
		_status(data.slice(16,32))
	elif data.decode_u32(8)>=maximum_cycles:
		_failed("pressure_budget_exhausted")
	else:
		RenderingServer.call_on_render_thread(_pressure_packet_gpu)

func _record_conditional_transport(list: int) -> void:
	# The transport shader copies unchanged state until GPU convergence is true.
	transport.record_dynamic_step(list,candidate,forcing,solver.control,0.0005)
	art.record(list,transport.output())

func _status(data: PackedByteArray) -> void:
	pending = false
	var accepted := data.size()==16 and data.decode_u32(4)==1
	if accepted:
		ticks += 1
		elapsed += data.decode_float(0)/32.0
	completed.emit({"accepted":accepted,"ticks":ticks,"elapsed":elapsed,"wall_ms":(Time.get_ticks_usec()-started)/1000.0})
	if closing: close()

func _failed(reason: String) -> void:
	pending = false
	completed.emit({"accepted":false,"reason":reason,"ticks":ticks,"elapsed":elapsed})
	if closing: close()

func capture_for_test(callback: Callable) -> bool:
	if pending or not initialized or closing: return false
	pending = true
	RenderingServer.call_on_render_thread(_capture_gpu.bind(callback))
	return true

func _capture_gpu(callback: Callable) -> void:
	var error := rd.buffer_get_data_async(transport.output(),func(data: PackedByteArray): _captured.call_deferred(data,callback))
	if error!=OK: _captured.call_deferred(PackedByteArray(),callback)

func _captured(data: PackedByteArray, callback: Callable) -> void:
	pending = false
	callback.call(data)
	if closing: close()

func close() -> void:
	closing = true
	if pending: return
	pending = true
	RenderingServer.call_on_render_thread(_close_gpu)

func _close_gpu() -> void:
	if rd!=null and forcing.is_valid():
		art.release()
		force.release()
		transport.release()
		rd.free_rid(forcing)
		rd.free_rid(combined_status)
		solver.release()
	_closed.call_deferred()

func _closed() -> void:
	pending = false
	initialized = false
	closed.emit()
