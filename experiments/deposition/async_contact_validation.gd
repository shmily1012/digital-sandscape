extends SceneTree
const Job=preload("res://experiments/deposition/async_contact_job.gd")
var job:Node
var last:Dictionary={}
var snapshot:=PackedByteArray()
var captured:=false
var failures:=0
func _initialize() -> void:_run.call_deferred()
func _ready_job() -> bool:
	for frame in range(1200):
		await process_frame
		if job.state=="idle":return true
	return false
func _capture() -> void:
	captured=false
	if not job.capture_for_test(func(data:PackedByteArray):snapshot=data;captured=true):failures+=1;return
	for frame in range(600):
		await process_frame
		if captured:return
	failures+=1
func _run() -> void:
	Engine.max_fps=120
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/contact-cycle-fixtures.json")).cases[0]
	job=Job.new();root.add_child(job)
	job.completed.connect(func(result:Dictionary):last=result)
	job.initialize(fixture.initial,fixture.planes)
	if not await _ready_job():quit(2);return
	var rows:Array=[]
	for step in range(240):
		var gravity:=Vector2(0,1) if step<160 else Vector2(.6,-.8)
		if step==61:
			await _capture()
			var original:=snapshot
			if not job.start(gravity,.05,0):failures+=1
			if not await _ready_job():quit(2);return
			if last.success or last.reason!="budget_exhausted" or job.tick!=61:failures+=1
			await _capture()
			if snapshot!=original:failures+=1
			rows.append(last.duplicate(true))
		if not job.start(gravity,.05):failures+=1
		if job.start(gravity,.05):failures+=1
		if not await _ready_job():quit(2);return
		if not last.success or last.tick!=step+1 or last.status_readback_bytes!=last.packets*16:failures+=1
		rows.append(last.duplicate(true))
		if not last.success:break
	await _capture()
	var expected:=FileAccess.get_file_as_bytes("res://reports/refined-cycle-trace.bin")
	var final_expected:=expected.slice(expected.size()-snapshot.size())
	var maximum:=0.0
	if final_expected.size()!=snapshot.size():failures+=1
	else:
		for i in range(snapshot.size()/4):maximum=maxf(maximum,absf(snapshot.decode_float(i*4)-final_expected.decode_float(i*4)))
		if maximum>2e-7:failures+=1
	var committed:=snapshot
	if not job.start(Vector2(1,0),.05) or not job.cancel():failures+=1
	if not await _ready_job():quit(2);return
	if last.success or last.reason!="cancelled" or job.tick!=240:failures+=1
	await _capture()
	if snapshot!=committed:failures+=1
	rows.append(last.duplicate(true))
	if not job.start(Vector2(0,-1),.05):failures+=1
	job.close()
	for frame in range(1200):
		await process_frame
		if job.state=="closed":break
	if job.state!="closed" or job.tick!=240 or job.pending:failures+=1
	var result:={"failures":failures,"tick":job.tick,"max_local_main_difference":maximum,"closed":job.state=="closed","steps":rows,"scope":"main RenderingDevice, one async packet in flight, 16-byte status; full-state reads only at test checkpoints"}
	FileAccess.open("res://reports/async-contact-validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ASYNC_CONTACT failures=",failures," tick=",job.tick," difference=",maximum)
	quit(0 if failures==0 else 1)
