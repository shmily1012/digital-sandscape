extends SceneTree
const Job=preload("res://experiments/deposition/async_coupled_job.gd")
var job:Node
var result:Dictionary={}
var captured:=false
var snapshot:=PackedByteArray()
var cancel_at_ready:=false
var failures:=0
func _initialize() -> void:_run.call_deferred()
func _idle() -> bool:
	for frame in range(2400):
		await process_frame
		if job.state=="idle":return true
	return false
func _capture(liquid:bool=false) -> PackedByteArray:
	captured=false
	if not job.capture_for_test(func(data:PackedByteArray):snapshot=data;captured=true,liquid):failures+=1;return PackedByteArray()
	for frame in range(600):
		await process_frame
		if captured:return snapshot
	failures+=1;return PackedByteArray()
func _run() -> void:
	Engine.max_fps=120
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/coupled-cycle-fixtures.json"))
	job=Job.new();root.add_child(job)
	job.completed.connect(func(r:Dictionary):result=r)
	job.candidate_ready.connect(func():
		if cancel_at_ready and not job.cancel():failures+=1)
	job.initialize(fixture.base,fixture.initial,fixture.planes)
	if not await _idle():quit(2);return
	var rows:Array=[]
	for step in range(80):
		var gravity:=Vector2(0,1) if step<60 else Vector2(0,-1)
		if step==60:
			var before:PackedByteArray=await _capture()
			var old_flux:PackedByteArray=await _capture(true)
			if not job.start(gravity,.005,1):failures+=1
			if not await _idle():quit(2);return
			if result.success or job.tick!=60 or await _capture()!=before or await _capture(true)!=old_flux:failures+=1
			rows.append(result.duplicate(true))
		if not job.start(gravity,.005):failures+=1
		if job.start(gravity,.005):failures+=1
		if not await _idle():quit(2);return
		rows.append(result.duplicate(true))
		if not result.success or job.tick!=step+1:failures+=1;break
	var final_state:PackedByteArray=await _capture()
	var final_flux:PackedByteArray=await _capture(true)
	var all_states:=FileAccess.get_file_as_bytes("res://reports/coupled-cycle-particles.bin")
	var all_flux:=FileAccess.get_file_as_bytes("res://reports/coupled-cycle-flux.bin")
	var particle_equal:=final_state==all_states.slice(all_states.size()-final_state.size())
	var flux_equal:=final_flux==all_flux.slice(all_flux.size()-final_flux.size())
	if not particle_equal or not flux_equal:failures+=1
	cancel_at_ready=true
	if not job.start(Vector2.DOWN,.005):failures+=1
	if not await _idle():quit(2);return
	if result.success or result.reason!="cancelled" or job.tick!=80 or await _capture()!=final_state or await _capture(true)!=final_flux:failures+=1
	rows.append(result.duplicate(true));cancel_at_ready=false
	if not job.start(Vector2.DOWN,.005):failures+=1
	job.close()
	for frame in range(2400):
		await process_frame
		if job.state=="closed":break
	if job.state!="closed" or job.tick!=80 or job.pending:failures+=1
	var report:={"failures":failures,"accepted":job.tick,"time":job.simulated_time,"particle_bytes_equal":particle_equal,"flux_bytes_equal":flux_equal,"closed":job.state=="closed","steps":rows,"scope":"main-device async coupled cycle; cancel after final validation before publication; only 4/16-byte normal status"}
	FileAccess.open("res://reports/async-coupled-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ASYNC_COUPLED failures=",failures," tick=",job.tick," particles_equal=",particle_equal," flux_equal=",flux_equal)
	quit(0 if failures==0 else 1)
