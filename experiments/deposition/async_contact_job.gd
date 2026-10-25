extends Node
signal completed(result:Dictionary)
signal closed
const Solver=preload("res://experiments/deposition/contact_solver_gpu.gd")
var state:="new"
var pending:=false
var closing:=false
var cancelled:=false
var generation:=0
var packets:=0
var rounds:=0
var budget:=16
var readback_bytes:=0
var tick:=0
var simulated_time:=0.0
var started_usec:=0
# Only render-thread methods access the device or solver.
var rd:RenderingDevice
var solver:RefCounted

func initialize(initial:Array, planes:Array) -> void:
	if state!="new":return
	state="initializing";pending=true
	RenderingServer.call_on_render_thread(_initialize_gpu.bind(initial.duplicate(true),planes.duplicate(true)))
func _initialize_gpu(initial:Array, planes:Array) -> void:
	rd=RenderingServer.get_rendering_device();solver=Solver.new()
	var ok:bool=rd!=null and solver.initialize(rd,initial,planes)
	_ready_main.call_deferred(ok)
func _ready_main(ok:bool) -> void:
	pending=false;state="idle" if ok else "failed"
	if closing:close()
func start(gravity:Vector2, dt:float, maximum_rounds:int=16) -> bool:
	if state!="idle" or pending or closing or not gravity.is_finite() or not is_finite(dt) or dt<=0 or maximum_rounds<0 or maximum_rounds>16:return false
	state="solving";pending=true;cancelled=false;generation+=1;packets=0;rounds=0;readback_bytes=0;budget=maximum_rounds;started_usec=Time.get_ticks_usec()
	RenderingServer.call_on_render_thread(_begin_gpu.bind(gravity,dt,generation))
	return true
func _begin_gpu(gravity:Vector2, dt:float, ticket:int) -> void:
	if not solver.record_step(gravity,dt):_error_main.call_deferred(ticket);return
	_read_status_gpu(ticket)
func _refine_gpu(ticket:int) -> void:
	if not solver.record_refinement(1):_error_main.call_deferred(ticket);return
	_read_status_gpu(ticket)
func _read_status_gpu(ticket:int) -> void:
	var error:=rd.buffer_get_data_async(solver.status_buffer(),_status_gpu.bind(ticket),0,16)
	if error!=OK:_error_main.call_deferred(ticket)
func _status_gpu(data:PackedByteArray, ticket:int) -> void:
	_status_main.call_deferred(data,ticket)
func _error_main(ticket:int) -> void:
	if ticket==generation and state=="solving":_finish(false,"readback_or_record_error",PackedByteArray())
func _status_main(data:PackedByteArray, ticket:int) -> void:
	if ticket!=generation or state!="solving":return
	pending=false;packets+=1;readback_bytes+=data.size()
	if cancelled or closing:_finish(false,"cancelled",data)
	elif data.size()!=16:_finish(false,"invalid_status",data)
	elif data.decode_u32(0)==1:_finish(true,"converged",data)
	elif rounds>=budget:_finish(false,"budget_exhausted",data)
	else:
		rounds+=1;pending=true
		RenderingServer.call_on_render_thread(_refine_gpu.bind(ticket))
func _finish(success:bool, reason:String, data:PackedByteArray) -> void:
	# Publication is the transaction boundary; cancellation cannot revoke it.
	state="publishing";pending=true
	var result:={"success":success,"reason":reason,"packets":packets,"rounds":rounds,"status_readback_bytes":readback_bytes,"wall_ms":(Time.get_ticks_usec()-started_usec)/1000.0}
	RenderingServer.call_on_render_thread(_publish_gpu.bind(success,data,result))
func _publish_gpu(success:bool, data:PackedByteArray, result:Dictionary) -> void:
	if success:
		result.success=solver.accept(data)
		if not result.success:result.reason="commit_rejected"
	else:solver.cancel()
	result["tick"]=solver.tick;result["time"]=solver.simulated_time
	_finished_main.call_deferred(result)
func _finished_main(result:Dictionary) -> void:
	pending=false;state="idle";tick=result.tick;simulated_time=result.time
	completed.emit(result)
	if closing:close()
func cancel() -> bool:
	if state!="solving":return false
	cancelled=true;return true
# Full readback is explicitly restricted to idle validation callers.
func capture_for_test(callback:Callable) -> bool:
	if state!="idle" or pending or closing:return false
	RenderingServer.call_on_render_thread(_capture_gpu.bind(callback))
	return true
func _capture_gpu(callback:Callable) -> void:
	rd.buffer_get_data_async(solver.output(),func(data:PackedByteArray):callback.call_deferred(data))
func close() -> void:
	closing=true
	if pending or state=="solving":cancelled=true;return
	if state in ["closed","closing"]:return
	state="closing";pending=true
	RenderingServer.call_on_render_thread(_close_gpu)
func _close_gpu() -> void:
	if rd!=null and solver!=null:solver.release()
	_closed_main.call_deferred()
func _closed_main() -> void:
	state="closed";pending=false;closed.emit()
