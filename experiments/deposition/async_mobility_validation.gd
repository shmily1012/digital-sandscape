extends SceneTree
const Job=preload("res://experiments/deposition/async_mobility_job.gd")
var job:Node
var result:Dictionary={}
var captured:=false
var matrix:=PackedByteArray()
func _initialize() -> void:_run.call_deferred()
func _idle() -> bool:
	for frame in range(1200):
		await process_frame
		if job.state=="idle":return true
	return false
func _run() -> void:
	Engine.max_fps=120
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/calibrated-contact-fixtures.json"))
	var test:Dictionary=fixture.cases[3]
	job=Job.new();root.add_child(job);job.completed.connect(func(r:Dictionary):result=r)
	job.initialize(fixture.base,test.grains)
	if not await _idle():quit(2);return
	var failures:=0
	var rows:Array=[]
	for scenario:Dictionary in [{"name":"budget","budget":1},{"name":"complete","budget":96},{"name":"cancel","budget":96}]:
		if not job.start(scenario.budget,8):failures+=1
		if job.start():failures+=1
		if scenario.name=="cancel" and not job.cancel():failures+=1
		if not await _idle():quit(2);return
		if result.success!=(scenario.name=="complete"):failures+=1
		if scenario.name=="cancel" and result.reason!="cancelled":failures+=1
		if result.status_bytes!=(result.packets*16-12 if result.success else result.packets*16):failures+=1
		rows.append(result.duplicate(true))
		if result.success:
			captured=false
			job.capture_for_test(func(data:PackedByteArray):matrix=data;captured=true)
			for frame in range(600):
				await process_frame
				if captured:break
			if not captured:quit(2);return
	if matrix.size()!=test.matrix.size()*test.matrix.size()*4:quit(2);return
	var error:=0.0
	for i in range(test.matrix.size()):
		for j in range(test.matrix.size()):
			var value:=matrix.decode_float((i*test.matrix.size()+j)*4)
			if not is_finite(value):failures+=1
			error=maxf(error,absf(value-test.matrix[i][j]))
	if error>0.001:failures+=1
	job.start();job.close()
	for frame in range(1200):
		await process_frame
		if job.state=="closed":break
	if job.state!="closed" or job.pending:failures+=1
	var report:={"failures":failures,"matrix_error":error,"closed":job.state=="closed","cases":rows,"scope":"main-device asynchronous calibration only; one packet in flight, 4/16-byte status, no joint physics commit"}
	FileAccess.open("res://reports/async-mobility-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ASYNC_MOBILITY ",JSON.stringify(report));quit(0 if failures==0 else 1)
