extends Node
signal completed(result:Dictionary)
signal closed
signal candidate_ready
signal texture_ready(texture:RID)
const View=preload("res://experiments/deposition/coupled_view_gpu.gd")
const Model=preload("res://experiments/deposition/coupled_contact_gpu.gd")
const Packets=preload("res://experiments/deposition/coupled_packets_gpu.gd")
var state:="new"
var pending:=false
var closing:=false
var cancel_requested:=false
var generation:=0
var packet_count:=0
var status_bytes:=0
var tick:=0
var simulated_time:=0.0
var rd:RenderingDevice
var model:RefCounted
var job:RefCounted
var view:RefCounted
var show_view:=false
func initialize(base:Dictionary, grains:Array, planes:Array, visualize:bool=false) -> void:
	if state!="new":return
	state="initializing";pending=true;show_view=visualize
	RenderingServer.call_on_render_thread(_init_gpu.bind(base.duplicate(true),grains.duplicate(true),planes.duplicate(true)))
func _init_gpu(base:Dictionary, grains:Array, planes:Array) -> void:
	rd=RenderingServer.get_rendering_device();model=Model.new()
	var ok:bool=rd!=null and model.initialize(rd,base,grains,planes)
	if ok:job=Packets.new();job.initialize(model)
	if ok and show_view:
		view=View.new();ok=view.initialize(rd,model)
		if ok:
			view.refresh();_texture_main.call_deferred(view.texture)
	_initialized.call_deferred(ok)
func _texture_main(texture:RID) -> void:texture_ready.emit(texture)
func _initialized(ok:bool) -> void:
	pending=false;state="idle" if ok else "failed"
	if closing:close()
func start(gravity:Vector2, dt:float, budget:int=96, batch:int=8) -> bool:
	if state!="idle" or pending or closing or budget<1 or budget>128 or batch<1 or batch>8 or not gravity.is_finite() or not is_finite(dt) or dt<=0:return false
	state="solving";pending=true;cancel_requested=false;packet_count=0;status_bytes=0;generation+=1
	RenderingServer.call_on_render_thread(_start_gpu.bind(gravity,dt,budget,batch,generation))
	return true
func _start_gpu(gravity:Vector2, dt:float, budget:int, batch:int, ticket:int) -> void:
	if not job.start(gravity,dt,budget,batch):_finished.call_deferred(false,"start_rejected",ticket);return
	_packet_gpu(ticket)
func _packet_gpu(ticket:int) -> void:
	if not job.record_next():_finished.call_deferred(false,"record_rejected",ticket);return
	var error:=rd.buffer_get_data_async(job.status_rid,_status_gpu.bind(ticket),0,job.status_size)
	if error!=OK:_finished.call_deferred(false,"readback_error",ticket)
func _status_gpu(data:PackedByteArray, ticket:int) -> void:
	job.consume(data)
	_status_main.call_deferred(job.state,data.size(),ticket,model.tick,model.simulated_time)
func _status_main(outcome:String, size:int, ticket:int, completed_tick:int, completed_time:float) -> void:
	if ticket!=generation or state not in ["solving","publishing"]:return
	pending=false;packet_count+=1;status_bytes+=size;tick=completed_tick;simulated_time=completed_time
	if state=="publishing":
		_finished(outcome=="done",outcome,ticket)
	elif closing or cancel_requested:
		pending=true;RenderingServer.call_on_render_thread(_cancel_gpu.bind(ticket))
	elif outcome=="ready":
		candidate_ready.emit()
		pending=true
		if closing or cancel_requested:RenderingServer.call_on_render_thread(_cancel_gpu.bind(ticket))
		else:
			state="publishing";RenderingServer.call_on_render_thread(_publish_gpu.bind(ticket))
	elif outcome in ["done","failed"]:_finished(outcome=="done",outcome,ticket)
	else:
		pending=true;RenderingServer.call_on_render_thread(_packet_gpu.bind(ticket))
func _publish_gpu(ticket:int) -> void:
	if not job.publish():_finished.call_deferred(false,"publication_rejected",ticket);return
	if view!=null:view.refresh()
	var error:=rd.buffer_get_data_async(job.status_rid,_status_gpu.bind(ticket),0,16)
	if error!=OK:_finished.call_deferred(false,"publication_readback_error",ticket)
func _cancel_gpu(ticket:int) -> void:
	job.cancel();_finished.call_deferred(false,"cancelled",ticket)
func _finished(success:bool, reason:String, ticket:int) -> void:
	if ticket!=generation:return
	pending=false;state="failed" if reason in ["readback_error","publication_readback_error","record_rejected","start_rejected","publication_rejected"] else "idle"
	completed.emit({"success":success,"reason":reason,"packets":packet_count,"status_bytes":status_bytes,"tick":tick,"time":simulated_time})
	if closing:close()
func cancel() -> bool:
	if state!="solving":return false
	cancel_requested=true;return true
func capture_for_test(callback:Callable, liquid:bool=false) -> bool:
	if pending or state!="idle" or closing:return false
	RenderingServer.call_on_render_thread(_capture_gpu.bind(callback,liquid));return true
func _capture_gpu(callback:Callable, liquid:bool) -> void:
	rd.buffer_get_data_async(model.flux() if liquid else model.output(),func(data:PackedByteArray):callback.call_deferred(data))
func close() -> void:
	closing=true
	if pending or state=="solving":cancel_requested=true;return
	if state in ["closed","closing"]:return
	state="closing";pending=true;RenderingServer.call_on_render_thread(_close_gpu)
func _close_gpu() -> void:
	if view!=null and rd!=null:view.release()
	if model!=null and rd!=null:model.release()
	_closed.call_deferred()
func _closed() -> void:
	pending=false;state="closed";closed.emit()
