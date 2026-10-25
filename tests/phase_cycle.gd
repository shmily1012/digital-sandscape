extends "res://tests/phase_preview_smoke.gd"
var samples:Array=[]
var output_prefix:="phase-cycle"
func shape_metrics()->Array:
	var n:int=app.grid_size;var c:=state.to_float32_array();var visited:=PackedByteArray();visited.resize(c.size())
	var components:Array=[]
	for start in range(c.size()):
		if visited[start]!=0 or c[start]<.5:continue
		var queue:Array[int]=[start];visited[start]=1;var head:=0;var sx:=0.;var sy:=0.;var xx:=0.;var yy:=0.;var xy:=0.
		while head<queue.size():
			var i:=queue[head];head+=1;var x:=i%n;var y:=i/n
			sx+=x;sy+=y;xx+=x*x;yy+=y*y;xy+=x*y
			for offset in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
				var nx:int=x+offset.x;var ny:int=y+offset.y
				if nx<0 or ny<0 or nx>=n or ny>=n:continue
				var j:=ny*n+nx
				if visited[j]==0 and c[j]>=.5:visited[j]=1;queue.append(j)
		if head<20:continue
		var vx:=xx/head-pow(sx/head,2);var vy:=yy/head-pow(sy/head,2);var cov:=xy/head-sx*sy/(head*head)
		var discriminant:=sqrt(pow(vx-vy,2)+4.*cov*cov)
		components.append({"cells":head,"center":[sx/head,sy/head],"axis_ratio":sqrt((vx+vy+discriminant)/maxf(vx+vy-discriminant,1e-12))})
	return components
func checkpoint(steps:int,angle:float,baseline:Dictionary)->void:
	# A caller may have advanced since the previous screenshot (e.g. a full turn).
	await capture()
	var unchanged_phase:=state.duplicate();var unchanged_materials:=materials.duplicate()
	app._set_angle(angle);await capture()
	check(state==unchanged_phase and materials==unchanged_materials,"Angle reset state")
	await advance(steps-256);await capture();var prior:=materials.duplicate()
	await advance(256);await capture()
	var result:=metrics(state);var changed:=0;var occupancy:=0
	for i in range(materials.size()):
		if materials[i]!=prior[i]:changed+=1
		if (materials[i]>=2)!=(prior[i]>=2):occupancy+=1
	result.tick=app.completed_tick;result.angle=angle;result.changed_material_cells_last_256=changed;result.changed_sand_occupancy_last_256=occupancy;result.bubbles=shape_metrics()
	check(result.invalid==0,"Invalid physical state")
	check(result.counts==baseline.counts,"Material inventory changed")
	check(absf(result.fluid_mass-baseline.fluid_mass)/baseline.fluid_mass<1e-6,"Fluid mass drift at tick "+str(app.completed_tick))
	check(absf(result.mass-baseline.mass)/baseline.mass<1e-4,"Gas drift")
	check(result.rho_min>.9 and result.rho_max<1.1,"Density out of bounds")
	samples.append(result)
	var name:="%s-%d"%[output_prefix,app.completed_tick]
	await screenshot(name)
	var file:=FileAccess.open("res://reports/"+name+".materials",FileAccess.WRITE);file.store_buffer(materials.to_byte_array());file.close()
	print("CYCLE_SAMPLE ",JSON.stringify(result))
func run()->void:
	if "--bubble-barrier" in OS.get_cmdline_user_args():output_prefix="phase-barrier-cycle"
	if "--barrier-air-scale=1.25" in OS.get_cmdline_user_args():output_prefix="phase-barrier-dense-cycle"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--grain-drag=") and argument!="--grain-drag=1":output_prefix+="-drag"+argument.trim_prefix("--grain-drag=")
	app=load("res://main.tscn").instantiate();app.set_script(load("res://tests/phase_smoke_host.gd"));app.session_enabled=false;root.add_child(app);app.paused=true
	for _frame in range(300):
		await process_frame
		if app.initialized:break
	if not app.initialized or not app.with_sand:quit(1);return
	await capture();var initial:=metrics(state)
	for schedule in [[2000,0.],[6000,0.],[12000,0.],[4000,0.],[2000,30.],[2000,90.],[20000,180.],[2000,270.]]:
		await checkpoint(int(schedule[0]),float(schedule[1]),initial)
	var report:Dictionary={"failures":failures,"initial":initial,"samples":samples,"grain_drag_divisor":app.fluid.grain_drag_divisor,"scope":"50k actual host ticks; 256-tick endpoint occupancy changes are not particle trajectories or proof of equilibrium; no aesthetic pass implied"}
	var file:=FileAccess.open("res://reports/"+output_prefix+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("PHASE_CYCLE failures=",failures);app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
