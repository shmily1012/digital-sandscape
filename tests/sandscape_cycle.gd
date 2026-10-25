extends "res://tests/energy_rotation_cycle.gd"
## Four long observation periods on one persistent world, followed by replay.
func deposit_profile(angle:float)->Array:
	var n:int=app.grid_size;var profile:Array=[];profile.resize(n);profile.fill(0)
	for y in range(n/2,n):
		for x in range(n):
			var i:=y*n+x
			if angle==180.:i=n*n-1-i
			if materials[i]>=2:profile[x]+=1
	return profile

func run()->void:
	output_prefix="sandscape-long-cycle"
	app=load("res://main.tscn").instantiate();app.set_script(load("res://tests/phase_smoke_host.gd"));app.session_enabled=false;root.add_child(app);app.paused=true
	for _frame in range(300):
		await process_frame
		if app.initialized:break
	if not app.initialized or not app.sandscape_layout or not app.fluid.grain_energy_enabled:quit(1);return
	check(not app.session_enabled,"Long cycle must not touch artwork saves")
	await capture();var initial:=metrics(state);await digest(true)
	var profiles:Array=[]
	for cycle in range(4):
		var angle:=180. if cycle%2==1 else 0.
		for period in range(3):
			await checkpoint(10000,angle,initial)
			await remember("cycle %d period %d"%[cycle+1,period+1])
		profiles.append({"cycle":cycle+1,"angle":angle,"tick":app.completed_tick,"lower_half_column_occupancy":deposit_profile(angle)})
	var differences:Array=[]
	for pair in [[0,2],[1,3]]:
		var a:Array=profiles[pair[0]].lower_half_column_occupancy
		var b:Array=profiles[pair[1]].lower_half_column_occupancy
		var difference:=0;var inventory:=0
		for i in range(a.size()):difference+=absi(int(a[i])-int(b[i]));inventory+=int(a[i])+int(b[i])
		differences.append({"cycles":[pair[0]+1,pair[1]+1],"l1_cells":difference,"normalized_l1":float(difference)/maxi(1,inventory)})
	var replay:Dictionary=await verify_replay()
	var report:Dictionary={"failures":failures,"initial":initial,"samples":samples,"inputs":inputs,"checkpoints":checkpoints,"profiles":profiles,"composition_differences":differences,"replay":replay,"total_ticks":app.completed_tick,"simulated_seconds":app.completed_tick/30.,"scope":"Four 30000-tick observation periods, alternating 0/180 degrees, same physical world. Lower-half occupancy is not a silhouette or a novelty guarantee. Endpoint movement is not proof of equilibrium. Same-hardware replay, not real-time power/thermal or weeks-long reliability."}
	var file:=FileAccess.open("res://reports/sandscape-long-cycle.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("SANDSCAPE_LONG_CYCLE failures=",failures," ticks=",app.completed_tick)
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
