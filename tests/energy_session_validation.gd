extends SceneTree
const State=preload("res://src/energy_state_manager.gd")
const Fluid=preload("res://src/phase_fluid.gd")
var failures:=0
var folder:=""
var app:Control
var expected:=PackedByteArray()
var checkpoint_ms:=0.0
var frames_during_checkpoint:=0
func _initialize()->void:call_deferred("run")
func check(condition:bool,label:String)->void:
	if not condition:failures+=1;push_error("ENERGY_SESSION_FAIL "+label)
func run()->void:
	folder="user://energy-session-test-"+str(OS.get_process_id())
	var store:=State.new();store.directory=folder
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(2);return
	var a:=Fluid.new();a.grain_drag_divisor=16
	a.grain_energy_enabled=true;a.voxel_interface_enabled=true;a.grain_collective_enabled=true
	a.grain_weight_scale=.7;a.grain_mobility_scale=.5;a.grain_wetting_cosine=.5
	var b:=Fluid.new();var fields:=Fluid.sandscape_fields(256,709)
	if not a.initialize(rd,256,fields.gas,fields.walls,PackedVector2Array(),true,709):quit(2);return
	for _batch in range(19):a.advance(100,Vector2(0,.00002),.01);rd.submit();rd.sync()
	a.advance(81,Vector2(0,.00002),.01);rd.submit();rd.sync();expected=a.energy_snapshot_bytes()
	var metadata:Dictionary={"side":256,"seed":709,"tick":1981,"angle":37.5,"paused":true,"mineral_style":false,"resource_preset":1,"with_sand":true,"gravity_magnitude":.00002,"sigma":.01,"grain_drag_divisor":16,"mass_compensation":true,"energy_exchange":true,"paired_interface":true,"energy_revision":1,"collective_revision":2,"collective_exchange":true,"weight_scale":.7,"mobility_scale":.5,"wetting_cosine":.5,"initial_profile":"seeded-irregular-bubbles-v1"}
	var started:=Time.get_ticks_usec()
	check(store.save(expected,metadata),"save odd parity")
	checkpoint_ms=(Time.get_ticks_usec()-started)/1000.
	check(preload("res://src/phase_state_manager.gd").unpack(FileAccess.get_file_as_bytes(folder.path_join("phase-a.bin"))).is_empty(),"legacy decoder rejects energy journal")
	var recovered:=store.load_latest()
	check(not recovered.is_empty() and recovered.bytes==expected,"restore complete bytes")
	if recovered.is_empty() or not b.restore_energy(rd,recovered):quit(1);return
	check(b.grain_energy_enabled and b.grain_collective_enabled and b.grain_weight_scale==.7 and b.grain_mobility_scale==.5 and b.grain_wetting_cosine==.5,"all physics parameters restored")
	check(b.energy_snapshot_bytes()==expected and b.grain_drag_divisor==16,"GPU initialization and drag exact")
	for step in range(40):
		var gravity:=Vector2.DOWN.rotated(step*.17)*.00002
		a.advance(1,gravity,.01);b.advance(1,gravity,.01)
	rd.submit();rd.sync()
	check(a.energy_snapshot_bytes()==b.energy_snapshot_bytes(),"continued GPU state exact")
	metadata.tick=2021
	check(store.save(a.energy_snapshot_bytes(),metadata),"second generation")
	var latest:=folder.path_join("phase-b.bin");var original:=FileAccess.get_file_as_bytes(latest)
	check(State.unpack_energy(original.slice(0,original.size()/2)).is_empty(),"truncation rejected")
	var corrupt:=original.duplicate();corrupt[-1]^=1
	check(State.unpack_energy(corrupt).is_empty(),"checksum rejected")
	for fault in ["model","tick","wall","nan","size","config","drag","residual","format","stamp","weight","revision","wetting","flag_type","old_payload"]:
		var header:=metadata.duplicate(true);header.model=State.ENERGY_MODEL;header.version=1;header.generation=2
		var payload:=expected.duplicate()
		if fault=="model":header.model="legacy"
		if fault=="tick":header.tick=1.5
		if fault=="wall":payload.encode_u32(256*256*40,0)
		if fault=="nan":payload.encode_float(256*256*4,NAN)
		if fault=="size":payload.resize(payload.size()-1)
		if fault=="config":header.sigma=.02
		if fault=="drag":header.grain_drag_divisor=1.5
		if fault=="residual":payload.encode_float(256*256*52,NAN)
		if fault=="flag_type":header.energy_exchange=1
		if fault=="old_payload":payload=payload.slice(0,256*256*56)
		if fault=="stamp":payload.encode_u32(256*256*56,int(header.tick))
		if fault=="weight":header.weight_scale=0.
		if fault=="revision":header.collective_revision=1
		if fault=="wetting":header.wetting_cosine=2.
		if fault=="format":header.mass_compensation=false
		check(State.unpack_energy(State.encode(payload,header)).is_empty(),fault+" rejected with valid checksum")
	var file:=FileAccess.open(latest,FileAccess.WRITE);file.store_buffer(corrupt);file.close()
	var fallback:=State.new();fallback.directory=folder;recovered=fallback.load_latest()
	check(recovered.get("tick")==1981 and recovered.get("bytes")==expected,"two-slot fallback")
	a.release();b.release();rd.free()
	app=load("res://main.tscn").instantiate();app.set_script(load("res://tests/phase_session_host.gd"));app.sessions.directory=folder;root.add_child(app)
	for frame in range(600):
		await process_frame
		if app.initialized:break
	check(app.initialized,"main host initialized")
	if not app.initialized:quit(1);return
	check(app.fluid.grain_drag_divisor==16,"main drag restored")
	check(app.completed_tick==1981 and app.world_seed==709 and app.paused and app.with_sand,"main metadata restored")
	check(is_equal_approx(app.director.angle_degrees,37.5) and app.budget.preset==1,"orientation and budget restored")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/energy-session-restored.png")
	app.save_session()
	while app.pending:
		await process_frame
		frames_during_checkpoint+=1
	check(app.session_note=="Candidate session saved","manual checkpoint")
	app.session_age=121.
	await process_frame
	while app.pending:await process_frame
	check(app.sessions.generation==3,"periodic checkpoint")
	app.save_session()
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(app.close_after_checkpoint and not app.closing,"close waits for in-flight checkpoint")
func session_closed()->void:
	var store:=State.new();store.directory=folder;var saved:=store.load_latest()
	check(saved.get("tick")==1981 and saved.get("bytes")==expected,"close preserves full state")
	check(store.generation==5,"close checkpoint committed after queued save")
	var file:=FileAccess.open("res://reports/energy-session-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"generation":store.generation,"checkpoint_encode_validate_write_ms":checkpoint_ms,"frames_during_checkpoint":frames_during_checkpoint,"restored_tick":1981,"continuation_steps":40,"folder":folder,"scope":"full active phase/f/material/wall velocity/residual/move stamps and physics config, odd parity, rotated continuation, corruption fallback, main host manual/periodic/close during worker"},"  "));file.close()
	print("ENERGY_SESSION failures=",failures," generation=",store.generation);quit(0 if failures==0 else 1)
