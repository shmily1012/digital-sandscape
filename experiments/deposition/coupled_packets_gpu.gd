extends RefCounted
const Calibration=preload("res://experiments/deposition/mobility_packets_gpu.gd")
var model:RefCounted
var calibration:RefCounted
var state:="idle"
var pending:=false
var status_rid:RID
var status_size:=16
var gravity:=Vector2.ZERO
var dt:=0.0
var maximum_cycles:=96
var batch:=8
var cycles:=0
var awaiting:=""
var reason:=""
func initialize(value:RefCounted) -> void:
	model=value;calibration=Calibration.new();calibration.initialize(model.online)
func start(direction:Vector2, step:float, budget:int=96, packet_cycles:int=8) -> bool:
	if pending or model.pending or not direction.is_finite() or not is_finite(step) or step<=0 or budget<1 or budget>128 or packet_cycles<1 or packet_cycles>8:return false
	if not model.begin_transaction(step):return false
	if not calibration.start(budget,packet_cycles):model.pending=false;return false
	gravity=direction;dt=step;maximum_cycles=budget;batch=packet_cycles;cycles=0;state="calibration";reason=""
	return true
func record_next() -> bool:
	if pending:return false
	status_size=16
	match state:
		"calibration":
			if not calibration.record_next():return false
			status_rid=calibration.status_rid;status_size=calibration.status_size
		"contact":
			model.record_contact(gravity,dt);status_rid=model.buffers[3]
		"prepare","pressure":
			if state=="prepare":model.feedback.prepare(model.online,model.online.output(),model.buffers[0],model.buffers[2],model.buffers[3],model.contact_count,gravity,dt)
			var work:=mini(batch,maximum_cycles-cycles)
			model.feedback.pressure_packet(work);cycles+=work
			status_rid=model.online.solvers[-1].control
		"validate":
			model.feedback.validate_candidate();status_rid=model.status_buffer()
		_:return false
	pending=true;awaiting=state;return true
func publish() -> bool:
	if pending or state!="ready":return false
	model.feedback.publish_candidate();status_rid=model.status_buffer();status_size=16
	pending=true;state="publishing";awaiting="publishing";return true
func _fail(message:String) -> void:
	state="failed";reason=message;model.pending=false
func consume(data:PackedByteArray) -> void:
	if not pending:return
	pending=false
	if data.size()!=status_size:_fail("invalid_status");return
	match awaiting:
		"calibration":
			calibration.consume(data)
			if calibration.state=="failed":_fail("calibration_failed")
			elif calibration.state=="done":state="contact"
		"contact":
			if data.decode_u32(0)!=1:_fail("contact_failed")
			else:state="prepare"
		"prepare","pressure":
			if data.decode_u32(12)!=0:_fail("pressure_invalid")
			elif data.decode_u32(4)==1:state="validate"
			elif cycles>=maximum_cycles:_fail("pressure_budget")
			else:state="pressure"
		"validate":
			if data.decode_u32(0)!=1:_fail("joint_check_failed")
			else:state="ready"
		"publishing":
			if model.complete(data):state="done"
			else:_fail("publication_failed")
func cancel() -> bool:
	if pending or state in ["idle","done","failed","cancelled","publishing"]:return false
	calibration.cancel();model.pending=false;state="cancelled";reason="cancelled";return true
