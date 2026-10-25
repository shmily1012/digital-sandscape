extends "res://tests/phase_cycle.gd"
## Real visible host plus independent local-RD replay of its exact tick inputs.
const FluidReplay=preload("res://src/phase_fluid.gd")
const DirectorReplay=preload("res://src/aesthetic_director.gd")
var inputs:Array=[]
var checkpoints:Array=[]
var initial_bytes:=PackedByteArray()
var digest_ready:=false
var current_digest:=""
var digest_tick:=0

func advance(ticks:int)->void:
	if ticks>0:inputs.append({"angle":app.director.angle_degrees,"ticks":ticks})
	await super.advance(ticks)

func digest_gpu(save_initial:bool)->void:
	var bytes:PackedByteArray=app.fluid.snapshot_bytes()
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	if app.fluid.grain_energy_stamp.is_valid():hash.update(app.fluid.rd.buffer_get_data(app.fluid.grain_energy_stamp))
	digest_accept.call_deferred(hash.finish().hex_encode(),app.fluid.tick,bytes if save_initial else PackedByteArray())

func digest_accept(value:String,tick:int,bytes:PackedByteArray)->void:
	current_digest=value;digest_tick=tick
	if not bytes.is_empty():initial_bytes=bytes
	digest_ready=true

func digest(save_initial:bool=false)->void:
	digest_ready=false;RenderingServer.call_on_render_thread(digest_gpu.bind(save_initial))
	while not digest_ready:await process_frame

func remember(label:String)->void:
	await digest()
	checkpoints.append({"after_input":inputs.size(),"tick":digest_tick,"sha256":current_digest,"label":label})
	print("ENERGY_ROTATION checkpoint=",label," tick=",digest_tick)

func verify_replay()->Dictionary:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:check(false,"Replay RD unavailable");return {}
	var replay:=FluidReplay.new();replay.grain_energy_enabled=true;replay.voxel_interface_enabled=true
	replay.grain_collective_enabled=app.fluid.grain_collective_enabled;replay.grain_wetting_cosine=app.fluid.grain_wetting_cosine
	if not replay.restore(rd,{"side":app.grid_size,"bytes":initial_bytes,"tick":0,"seed":app.world_seed,"with_sand":true,"grain_drag_divisor":app.fluid.grain_drag_divisor}):
		check(false,"Replay restore failed");replay.release();rd.free();return {}
	var director:=DirectorReplay.new();var checkpoint_index:=0;var comparisons:Array=[]
	for index in range(inputs.size()):
		var entry:Dictionary=inputs[index];director.set_angle(entry.angle)
		var remaining:=int(entry.ticks)
		while remaining>0:
			var count:=mini(128,remaining)
			replay.advance(count,Vector2(director.gravity())/32767.*.00002,.01);rd.submit();rd.sync()
			remaining-=count;await process_frame
		if checkpoint_index<checkpoints.size() and index+1==int(checkpoints[checkpoint_index].after_input):
			var expected:Dictionary=checkpoints[checkpoint_index]
			var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(replay.snapshot_bytes());hash.update(rd.buffer_get_data(replay.grain_energy_stamp))
			var actual:=hash.finish().hex_encode();var matches:bool=actual==expected.sha256 and replay.tick==int(expected.tick)
			check(matches,"Replay mismatch at "+str(expected.tick));comparisons.append({"tick":replay.tick,"matches":matches,"sha256":actual})
			print("ENERGY_ROTATION replay tick=",replay.tick," matches=",matches)
			checkpoint_index+=1
	check(checkpoint_index==checkpoints.size(),"Replay omitted a checkpoint")
	var result:Dictionary={"checkpoints":comparisons,"ticks":replay.tick,"device":rd.get_device_name()}
	replay.release();rd.free();return result

func run()->void:
	output_prefix="energy-rotation"+("-collective" if "--collective-exchange" in OS.get_cmdline_user_args() else "")
	app=load("res://main.tscn").instantiate();app.set_script(load("res://tests/phase_smoke_host.gd"));app.session_enabled=false;root.add_child(app);app.paused=true
	for _frame in range(300):
		await process_frame
		if app.initialized:break
	if not app.initialized or not app.with_sand or not app.fluid.grain_energy_enabled:quit(1);return
	check(not app.session_enabled,"Rotation test must not touch saved artwork")
	await capture();var initial:=metrics(state);await digest(true)
	check(digest_tick==0,"Initial state already advanced")
	for angle in [0.,30.,45.,90.,120.,180.,270.,17.3,315.]:
		await checkpoint(2000,angle,initial);await remember("angle %.1f"%angle)
	# Continuous input rotation, with fixed physical steps and no reinitialization.
	for angle in range(360):
		app._set_angle(float(angle));await advance(16)
	await checkpoint(256,0.,initial);await remember("continuous full turn")
	await checkpoint(10000,0.,initial);await remember("long dwell")
	var replay:Dictionary=await verify_replay()
	var report:Dictionary={"failures":failures,"initial":initial,"samples":samples,"checkpoints":checkpoints,"inputs":inputs,"replay":replay,"total_ticks":app.completed_tick,"collective_exchange":app.fluid.grain_collective_enabled,"scope":"Actual 256-grid host, fixed-angle dwell plus 360 one-degree inputs and final dwell; same-hardware local-RD replay. Not weeks/months stability, cross-platform determinism, angular-bias calibration, or physical/aesthetic acceptance."}
	var file:=FileAccess.open("res://reports/"+output_prefix+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("ENERGY_ROTATION failures=",failures," ticks=",app.completed_tick)
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
