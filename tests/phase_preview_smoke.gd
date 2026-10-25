extends SceneTree
const Topology=preload("res://tests/phase_topology_gpu.gd")
var app:Control
var captured:=false
var state:=PackedByteArray()
var failures:=0
var materials:=PackedInt32Array()
var populations:=PackedFloat32Array()
func _initialize()->void:call_deferred("run")
func capture_gpu()->void:
	var bytes:PackedByteArray=app.fluid.rd.buffer_get_data(app.fluid.phase[app.fluid.tick%2])
	var m:PackedByteArray=app.fluid.rd.buffer_get_data(app.fluid.materials)
	var f:PackedByteArray=app.fluid.rd.buffer_get_data(app.fluid.distributions[app.fluid.tick%2])
	accept_state.call_deferred(bytes,m,f)
func accept_state(bytes:PackedByteArray,m:PackedByteArray,f:PackedByteArray)->void:state=bytes;materials=m.to_int32_array();populations=f.to_float32_array();captured=true
func capture()->void:
	captured=false;RenderingServer.call_on_render_thread(capture_gpu)
	while not captured:await process_frame
func check(value:bool,message:String)->void:
	if not value:failures+=1;push_error(message)
func advance(ticks:int)->void:
	while ticks>0:
		var count:=mini(32,ticks);app.pending=true
		RenderingServer.call_on_render_thread(app._update_gpu.bind(app.director.gravity(),count,true))
		while app.pending:await process_frame
		ticks-=count
func metrics(bytes:PackedByteArray)->Dictionary:
	var gas:=bytes.to_float32_array();var mass:=0.;var height:=0.;var invalid:=0;var n:int=app.grid_size;var counts:Array[int]=[0,0,0,0,0];var sand_y:=0.;var fluid_mass:=0.;var rho_min:=INF;var rho_max:=-INF
	for i in range(materials.size()):
		counts[materials[i]]+=1
		var outside:=Vector2(i%n,i/n).distance_to(Vector2.ONE*(n-1)*0.5)>=n*0.5-2.
		if outside!=(materials[i]==1):invalid+=1
		if materials[i]==0:
			var rho:=0.
			for q in range(9):
				rho+=populations[9*i+q]
				if not is_finite(populations[9*i+q]) or populations[9*i+q]<-1e-7:invalid+=1
			fluid_mass+=rho;rho_min=minf(rho_min,rho);rho_max=maxf(rho_max,rho)
		if materials[i]>=2:sand_y+=i/n
	for i in range(gas.size()):
		mass+=gas[i];height+=gas[i]*(i/n)
		if Vector2(i%n,i/n).distance_to(Vector2.ONE*(n-1)*0.5)>=n*0.5-2. and gas[i]!=0.:invalid+=1
		if materials[i]!=0 and gas[i]!=0.:invalid+=1
		if not is_finite(gas[i]) or gas[i]<-1e-6 or gas[i]>1.000001:invalid+=1
	return {"fluid_mass":fluid_mass,"rho_min":rho_min,"rho_max":rho_max,"counts":counts,"sand_height":sand_y/maxi(1,counts[2]+counts[3]+counts[4]),"mass":mass,"height":height/mass,"invalid":invalid,"gas_components":Topology.measure(gas,n).components,"gas_components_04":Topology.measure(gas,n,.4).components,"gas_components_06":Topology.measure(gas,n,.6).components}
func candidate_suffix()->String:
	return ("-buoyant" if app.fluid.grain_buoyant_enabled else "")+("-energy-exchange" if app.fluid.grain_energy_enabled else "")+("-collective" if app.fluid.grain_collective_enabled else "")+("-wetting-%.1f"%app.fluid.grain_wetting_cosine if app.fluid.grain_wetting_cosine!=0. else "")
func screenshot(name:String)->void:
	if app.fluid.voxel_interface_enabled:name+="-paired-interface"
	name+=candidate_suffix()
	if not app.fluid.grain_traction_enabled:name+="-without-traction"
	if app.sandscape_layout:name=name.replace("phase-preview","sandscape-natural")
	elif app.bubble_barrier:name=name.replace("phase-preview","sandscape-barrier")
	elif app.contact_bed:name=name.replace("phase-preview","phase-contact-bed")
	elif app.with_sand:name=name.replace("phase-preview","phase-sand")
	var raw:=FileAccess.open("res://reports/"+name+".f32",FileAccess.WRITE);raw.store_buffer(state);raw.close()
	var material_file:=FileAccess.open("res://reports/"+name+".materials.u32",FileAccess.WRITE)
	material_file.store_buffer(materials.to_byte_array());material_file.close()
	var population_file:=FileAccess.open("res://reports/"+name+".populations.f32",FileAccess.WRITE)
	population_file.store_buffer(populations.to_byte_array());population_file.close()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/"+name+".png")
func run()->void:
	app=load("res://main.tscn").instantiate();app.set_script(load("res://tests/phase_smoke_host.gd"));app.session_enabled=false;root.add_child(app);app.paused=true
	for _frame in range(300):
		await process_frame
		if app.initialized:break
	if not app.initialized:quit(1);return
	if app.contact_bed or app.bubble_barrier:check(not app.session_enabled,"Contact scene must not read/write user sessions")
	await capture();var initial:=state.duplicate();var start:=metrics(state)
	await screenshot("phase-preview-initial")
	app._set_angle(37.5);await capture();check(state==initial,"Rotation changed physical state")
	app._set_angle(0.);await advance(2000);await capture();var end:=metrics(state)
	check(end.invalid==0,"Invalid gas fraction")
	check(absf(end.mass-start.mass)/start.mass<1e-4,"Gas drift exceeded tolerance")
	if not app.with_sand:check(end.height<start.height-2.,"No observable upward displacement")
	else:
		check(end.sand_height>start.sand_height+2.,"Sand did not descend")
		check(end.counts==start.counts,"Sand material inventory changed")
	await screenshot("phase-preview-tick-2000")
	var observations:Dictionary={"tick_2000":end}
	# Let the loaded bed reach the interface before testing a reversal.
	# Numerical integrity is not evidence of physical support.
	if app.contact_bed or app.bubble_barrier:
		for target_tick in [5000,10000]:
			await advance(target_tick-app.fluid.tick);await capture()
			var observed:=metrics(state)
			observations["tick_%d"%target_tick]=observed
			check(observed.invalid==0,"Invalid loaded-bed state")
			check(observed.counts==start.counts,"Loaded-bed material inventory changed")
			check(absf(observed.mass-start.mass)/start.mass<1e-4,"Loaded-bed gas drift")
			check(absf(observed.fluid_mass-start.fluid_mass)/start.fluid_mass<1e-6,"Loaded-bed fluid drift")
			await screenshot("phase-preview-tick-%d"%app.fluid.tick)
	var flip_tick:int=app.fluid.tick
	var before_flip:=state.duplicate();app._set_angle(180.);await capture();check(state==before_flip,"Flip reset state")
	await advance(1000);await capture();var flipped:=metrics(state)
	check(flipped.invalid==0,"Invalid fraction after flip")
	check(absf(flipped.mass-start.mass)/start.mass<1e-4,"Gas drift after flip")
	check(state!=before_flip,"Flip did not evolve")
	observations["tick_%d"%app.fluid.tick]=flipped
	await screenshot("phase-preview-tick-%d"%app.fluid.tick)
	await advance(2000);await capture();var reversal:=metrics(state)
	check(reversal.invalid==0,"Invalid phase after longer reversal")
	if not app.with_sand:check(reversal.height>flipped.height+2.,"Gravity reversal did not reverse vertical motion")
	check(reversal.counts==start.counts,"Final material inventory changed")
	check(absf(reversal.fluid_mass-start.fluid_mass)/start.fluid_mass<1e-6,"Active fluid mass drift")
	check(reversal.rho_min>0.9 and reversal.rho_max<1.1,"Excessive fluid density deviation")
	check(absf(reversal.mass-start.mass)/start.mass<1e-4,"Gas drift after reversal")
	await screenshot("phase-preview-tick-%d"%app.fluid.tick)
	observations["tick_%d"%app.fluid.tick]=reversal
	var report:Dictionary={"failures":failures,"initial":start,"side":app.grid_size,"flip_tick":flip_tick,"physical_acceptance":"NOT ESTABLISHED"}
	report.merge(observations)
	report.initial_profile="seeded-bubble-barrier" if app.bubble_barrier else ("loaded-contact-bed" if app.contact_bed else "default")
	if app.sandscape_layout:report.initial_profile="seeded-irregular-bubbles-v1"
	report.seed=app.world_seed
	report.traction_enabled=app.fluid.grain_traction_enabled
	report.paired_interface=app.fluid.voxel_interface_enabled
	report.wetting_cosine=app.fluid.grain_wetting_cosine
	report.grain_rule_revision=app.fluid.GRAIN_RULE_REVISION
	report.grain_motion_model="overdamped-energy-exchange-v1" if app.fluid.grain_energy_enabled else "traction-voxel-v2"
	report.buoyant_exchange=app.fluid.grain_buoyant_enabled
	report.collective_exchange=app.fluid.grain_collective_enabled
	report.collective_rule_revision=app.fluid.COLLECTIVE_RULE_REVISION if report.collective_exchange else 0
	var output:="sandscape-barrier-smoke" if app.bubble_barrier else ("phase-contact-bed-smoke" if app.contact_bed else ("phase-sand-smoke" if app.with_sand else "phase-preview-smoke"))
	if app.sandscape_layout:output="sandscape-natural-smoke"
	if not app.fluid.grain_traction_enabled:output+="-without-traction"
	if app.fluid.voxel_interface_enabled:output+="-paired-interface"
	output+=candidate_suffix()
	var file:=FileAccess.open("res://reports/"+output+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("PHASE_PREVIEW_RESULT ",report)
	# Verify the production shutdown path; process exit is checked by the launcher.
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

