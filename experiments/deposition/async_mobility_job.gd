extends Node
signal completed(result:Dictionary)
signal closed
const Online=preload("res://experiments/liquid/online_grains.gd")
const Packets=preload("res://experiments/deposition/mobility_packets_gpu.gd")
var state:="new"
var pending:=false
var closing:=false
var cancel_requested:=false
var generation:=0
var packet_count:=0
var status_bytes:=0
var rd:RenderingDevice
var online:RefCounted
var job:RefCounted
func initialize(base:Dictionary, grains:Array) -> void:
	if state!="new":return
	state="initializing";pending=true
	RenderingServer.call_on_render_thread(_init_gpu.bind(base.duplicate(true),grains.duplicate(true)))
func _init_gpu(base:Dictionary, grains:Array) -> void:
	rd=RenderingServer.get_rendering_device();online=Online.new()
	var ok:bool=rd!=null and online.initialize(rd,base,grains)
	if ok:job=Packets.new();job.initialize(online)
	_initialized.call_deferred(ok)
func _initialized(ok:bool) -> void:
	pending=false;state="idle" if ok else "failed"
	if closing:close()
func start(budget:int=96, batch:int=8) -> bool:
	if state!="idle" or pending or closing or budget<1 or budget>128 or batch<1 or batch>8:return false
	state="solving";pending=true;cancel_requested=false;packet_count=0;status_bytes=0;generation+=1
	RenderingServer.call_on_render_thread(_start_gpu.bind(budget,batch,generation))
	return true
func _start_gpu(budget:int, batch:int, ticket:int) -> void:
	if not job.start(budget,batch):_finished.call_deferred(false,"start_rejected",ticket);return
	_packet_gpu(ticket)
func _packet_gpu(ticket:int) -> void:
	if not job.record_next():_finished.call_deferred(false,"record_rejected",ticket);return
	var error:=rd.buffer_get_data_async(job.status_rid,_status_gpu.bind(ticket),0,job.status_size)
	if error!=OK:_finished.call_deferred(false,"readback_error",ticket)
func _status_gpu(data:PackedByteArray, ticket:int) -> void:
	job.consume(data)
	_status_main.call_deferred(job.state,data.size(),ticket)
func _status_main(outcome:String, size:int, ticket:int) -> void:
	if ticket!=generation or state!="solving":return
	pending=false;packet_count+=1;status_bytes+=size
	if closing or cancel_requested:
		pending=true;RenderingServer.call_on_render_thread(_cancel_gpu.bind(ticket))
	elif outcome in ["done","failed"]:_finished(outcome=="done",outcome,ticket)
	else:
		pending=true;RenderingServer.call_on_render_thread(_packet_gpu.bind(ticket))
func _cancel_gpu(ticket:int) -> void:
	job.cancel();_finished.call_deferred(false,"cancelled",ticket)
func _finished(success:bool, reason:String, ticket:int) -> void:
	if ticket!=generation:return
	pending=false;state="idle"
	completed.emit({"success":success,"reason":reason,"packets":packet_count,"status_bytes":status_bytes})
	if closing:close()
func cancel() -> bool:
	if state!="solving":return false
	cancel_requested=true;return true
func capture_for_test(callback:Callable) -> bool:
	if pending or state!="idle" or closing:return false
	RenderingServer.call_on_render_thread(_capture_gpu.bind(callback));return true
func _capture_gpu(callback:Callable) -> void:
	rd.buffer_get_data_async(online.buffers[8],func(data:PackedByteArray):callback.call_deferred(data))
func close() -> void:
	closing=true
	if pending or state=="solving":cancel_requested=true;return
	if state in ["closed","closing"]:return
	state="closing";pending=true;RenderingServer.call_on_render_thread(_close_gpu)
func _close_gpu() -> void:
	if online!=null and rd!=null:online.release()
	_closed.call_deferred()
func _closed() -> void:
	pending=false;state="closed";closed.emit()
