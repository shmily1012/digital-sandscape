extends Node

signal completed(result: Dictionary)
signal closed

const Solver = preload("res://experiments/liquid/multigrid_gpu.gd")
var state := "new"
var published_version := 0
var pending := false
var cancel_requested := false
var closing := false
var generation := 0
var packets := 0
var status_bytes := 0
var cycles := 0
var budget := 96
var batch_size := 8
var tolerance := 2e-6
var started_usec := 0
# GPU fields are accessed only through render-thread methods.
var rd: RenderingDevice
var solver: RefCounted
var committed := RID()
var candidate := RID()
var pressure_bytes := 0

func initialize(descriptions: Array) -> void:
	if state != "new":
		return
	state = "initializing"
	pending = true
	RenderingServer.call_on_render_thread(_initialize_gpu.bind(descriptions))

func _initialize_gpu(descriptions: Array) -> void:
	rd = RenderingServer.get_rendering_device()
	solver = Solver.new()
	var ok: bool = rd != null and solver.initialize(rd, descriptions)
	if ok:
		pressure_bytes = int(descriptions[0].size)*int(descriptions[0].size)*4
		var zero := PackedByteArray()
		zero.resize(pressure_bytes)
		zero.fill(0)
		committed = rd.storage_buffer_create(pressure_bytes, zero)
	_on_initialized.call_deferred(ok)

func _on_initialized(ok: bool) -> void:
	pending = false
	state = "idle" if ok else "failed"
	if closing:
		close()

func start(equations: PackedByteArray, maximum_cycles: int = 96, packet_cycles: int = 8) -> bool:
	if state != "idle" or pending or closing or maximum_cycles < 1 or maximum_cycles > 128 or packet_cycles < 1 or packet_cycles > 8:
		return false
	state = "solving"
	generation += 1
	budget = maximum_cycles
	batch_size = packet_cycles
	cycles = 0
	packets = 0
	status_bytes = 0
	cancel_requested = false
	started_usec = Time.get_ticks_usec()
	pending = true
	RenderingServer.call_on_render_thread(_begin_gpu.bind(equations, generation))
	return true

func _begin_gpu(equations: PackedByteArray, ticket: int) -> void:
	if equations.size() != pressure_bytes*8:
		_on_transfer_error.call_deferred(ticket)
		return
	rd.buffer_update(solver.levels[0].equations, 0, equations.size(), equations)
	solver.reset_statistics()
	# A check-only packet avoids even one V-cycle when warm state is valid.
	var list := rd.compute_list_begin()
	solver.check_residual(list, tolerance, true)
	rd.compute_list_end()
	candidate = solver.levels[0].p[solver.levels[0].parity]
	_request_status_gpu(ticket)

func _packet_gpu(count: int, ticket: int) -> void:
	var list := rd.compute_list_begin()
	candidate = solver.record_adaptive(list, count, tolerance)
	rd.compute_list_end()
	_request_status_gpu(ticket)

func _request_status_gpu(ticket: int) -> void:
	var error := rd.buffer_get_data_async(solver.control, _status_gpu.bind(ticket), 0, 16)
	if error != OK:
		_on_transfer_error.call_deferred(ticket)

func _status_gpu(data: PackedByteArray, ticket: int) -> void:
	_on_status.call_deferred(data, ticket)

func _on_transfer_error(ticket: int) -> void:
	if ticket == generation:
		pending = false
		_finish(false, "readback_error", INF)

func _on_status(data: PackedByteArray, ticket: int) -> void:
	if ticket != generation or state != "solving":
		return
	pending = false
	packets += 1
	status_bytes += data.size()
	if data.size() != 16:
		_finish(false, "invalid_status", INF)
		return
	cycles = data.decode_u32(8)
	var residual := data.decode_float(0)
	if cancel_requested or closing:
		_finish(false, "cancelled", residual)
	elif data.decode_u32(12) != 0 or not is_finite(residual):
		_finish(false, "nonfinite", residual)
	elif data.decode_u32(4) == 1 and residual <= tolerance:
		_finish(true, "converged", residual)
	elif cycles >= budget:
		_finish(false, "budget_exhausted", residual)
	else:
		pending = true
		RenderingServer.call_on_render_thread(_packet_gpu.bind(mini(batch_size, budget-cycles), ticket))

func _finish(success: bool, reason: String, residual: float) -> void:
	# This is the transaction decision point. Cancellation after this point
	# cannot revoke an already queued publication; close waits for it safely.
	state = "publishing"
	pending = true
	var result := {"success":success, "reason":reason, "residual":residual if is_finite(residual) else "nonfinite", "cycles":cycles, "packets":packets, "status_readback_bytes":status_bytes, "wall_ms":float(Time.get_ticks_usec()-started_usec)/1000.0}
	RenderingServer.call_on_render_thread(_publish_gpu.bind(success, result))

func _publish_gpu(success: bool, result: Dictionary) -> void:
	if success:
		rd.buffer_copy(candidate, committed, 0, 0, pressure_bytes)
	else:
		# Reject candidate pressure, including its use as the next warm start.
		for buffer: RID in solver.levels[0].p:
			rd.buffer_copy(committed, buffer, 0, 0, pressure_bytes)
	_on_finished.call_deferred(result)

func _on_finished(result: Dictionary) -> void:
	pending = false
	state = "idle"
	if result.success:
		published_version += 1
	result["published_version"] = published_version
	completed.emit(result)
	if closing:
		close()

func cancel() -> bool:
	if state == "solving":
		cancel_requested = true
		return true
	return false

# Test-only full-state readback; normal scheduling reads exactly 16 bytes.
func capture_published_for_test(callback: Callable) -> void:
	RenderingServer.call_on_render_thread(_capture_gpu.bind(callback))

func _capture_gpu(callback: Callable) -> void:
	rd.buffer_get_data_async(committed, func(data: PackedByteArray): callback.call_deferred(data))

func close() -> void:
	closing = true
	if pending or state == "solving":
		cancel_requested = true
		return
	if state == "closed" or state == "closing":
		return
	state = "closing"
	pending = true
	RenderingServer.call_on_render_thread(_release_gpu)

func _release_gpu() -> void:
	if committed.is_valid():
		rd.free_rid(committed)
	if solver != null and rd != null:
		solver.release()
	_on_closed.call_deferred()

func _on_closed() -> void:
	pending = false
	state = "closed"
	closed.emit()
