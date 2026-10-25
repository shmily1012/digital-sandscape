extends SceneTree
## Observe the production candidate; this is not a second physics solver.
const Fluid=preload("res://src/phase_fluid.gd")
const N=128
const STEPS=4000
var failures:Array[String]=[]

func _initialize()->void:call_deferred("run")

func fields(has_gas:bool,bed_rows:int=4)->Dictionary:
	var result:=Fluid.contact_fields(N,bed_rows,has_gas)
	return {"gas":result.gas,"materials":result.walls}

func measure(c:PackedFloat32Array,m:PackedInt32Array,f:PackedFloat32Array)->Dictionary:
	var counts:Array[int]=[0,0,0,0,0];var gas:=0.;var gx:=0.;var gy:=0.;var sy:=0.;var released:=0;var blocked:=0;var mass:=0.;var invalid:=0
	for i in range(N*N):
		if m[i]<0 or m[i]>4:invalid+=1;continue
		counts[m[i]]+=1
		if not is_finite(c[i]) or c[i]<0. or c[i]>1. or (m[i]!=0 and c[i]!=0.):invalid+=1
		gas+=c[i];gx+=(i%N)*c[i];gy+=floori(float(i)/N)*c[i]
		if m[i]>=2:
			sy+=floori(float(i)/N)
			if i/N>=92:released+=1
			if i+N<N*N and m[i+N]==0 and c[i+N]>.05:blocked+=1
		if m[i]==0:
			for q in range(9):
				var value:=f[9*i+q]
				if not is_finite(value) or value<0.:invalid+=1
				mass+=value
		var outside:=Vector2(i%N-63.5,floori(float(i)/N)-63.5).length()>=62.
		if outside!=(m[i]==1):invalid+=1
	var cx:=gx/maxf(gas,1e-30);var cy:=gy/maxf(gas,1e-30);var xx:=0.;var yy:=0.;var xy:=0.
	for i in range(N*N):
		var x:=float(i%N)-cx;var y:=floori(float(i)/N)-cy
		xx+=c[i]*x*x;yy+=c[i]*y*y;xy+=c[i]*x*y
	var disc:=sqrt((xx-yy)*(xx-yy)+4.*xy*xy)
	var weight:=2.*counts[2]+1.7*counts[3]+1.4*counts[4]
	return {"counts":counts,"gas_mass":gas,"gas_center":[cx,cy],"gas_axis_ratio":sqrt((xx+yy+disc)/maxf(xx+yy-disc,1e-30)) if gas>0. else 0.,"sand_center_y":sy/maxi(1,counts[2]+counts[3]+counts[4]),"effective_sand_weight_over_bubble_buoyancy":weight/gas if gas>0. else -1.,"released_below_y92":released,"gas_blocked_downstream_cells":blocked,"fluid_mass":mass,"invalid":invalid}

func capture(rd:RenderingDevice,solver:RefCounted,name:String)->Dictionary:
	var before:PackedByteArray=solver.snapshot_bytes()
	var cb:=rd.buffer_get_data(solver.phase[solver.tick%2]);var mb:=rd.buffer_get_data(solver.materials)
	var c:=cb.to_float32_array();var m:=mb.to_int32_array()
	var result:=measure(c,m,rd.buffer_get_data(solver.distributions[solver.tick%2]).to_float32_array());result.tick=solver.tick
	# Recompute the candidate's derived estimator on this exact geometry. This
	# writes only traction, never phase/material/populations or the random stream.
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,solver.pipelines[3]);rd.compute_list_bind_uniform_set(list,solver.traction_sets[solver.tick%2],0)
	var push:=PackedByteArray();push.resize(16);push.encode_u32(0,N)
	rd.compute_list_set_push_constant(list,push,16);rd.compute_list_dispatch(list,ceili(N*N/64.),1,1);rd.compute_list_end();rd.submit();rd.sync()
	var force:=rd.buffer_get_data(solver.traction).to_float32_array();var upward:=0;var saturated:=0;var max_ratio:=0.
	for i in range(N*N):
		if m[i]<2:continue
		var weight:float=[2.,1.7,1.4][m[i]-2]
		var ratio:=Vector2(force[2*i],force[2*i+1])/(weight*.00002)
		if ratio.y< -1.:upward+=1
		if absf(ratio.x)>4. or absf(ratio.y)>4.:saturated+=1
		max_ratio=maxf(max_ratio,ratio.length())
	result.upward_driven_grains=upward;result.component_clamped_grains=saturated;result.max_traction_weight_ratio=max_ratio
	if before!=solver.snapshot_bytes():failures.append("observation mutated physical state")
	# Exact-state diagnostic image. No smoothing or invented grain/bubble geometry.
	var img:=Image.create(N,N,false,Image.FORMAT_RGB8)
	for i in range(N*N):
		var color:=Color(.55,.57,.56).lerp(Color(.88,.9,.88),c[i])
		if m[i]==1:color=Color(.05,.05,.05)
		elif m[i]>=2:
			var shade:float=[.1,.4,.82][m[i]-2];color=Color(shade,shade,shade)
		img.set_pixel(i%N,i/N,color)
	img.resize(512,512,Image.INTERPOLATE_NEAREST)
	if img.save_png("res://reports/contact-"+name+"-%d.png"%solver.tick)!=OK:failures.append("image write")
	for entry in [["phase",cb],["materials",mb],["populations",rd.buffer_get_data(solver.distributions[solver.tick%2])],["residual",rd.buffer_get_data(solver.mass_residual)]]:
		var file:=FileAccess.open("res://reports/contact-"+name+"-%d."%solver.tick+entry[0],FileAccess.WRITE)
		file.store_buffer(entry[1]);file.close()
	return result

func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var cases:Array=[]
	for config in [["bubble",true,true,0,4],["water",false,true,0,4],["fixed-bed",true,false,0,4],["relaxed-bubble",true,true,8000,4],["heavy-bubble",true,true,0,32],["relaxed-heavy-bubble",true,true,8000,32]]:
		var data:=fields(config[1],config[4]);var solver:=Fluid.new();solver.grain_motion_enabled=config[2] and config[3]==0
		if not solver.initialize(rd,N,data.gas,data.materials,PackedVector2Array(),true,20261024):quit(1);return
		var initial:=capture(rd,solver,config[0]);var samples:Array=[initial]
		for _batch in range(int(config[3])/100):
			solver.advance(100,Vector2(0,.00002),.01);rd.submit();rd.sync()
		if config[3]>0:
			if rd.buffer_get_data(solver.materials)!=data.materials.to_byte_array():failures.append("warmup geometry changed")
			samples.append(capture(rd,solver,config[0]))
			solver.grain_motion_enabled=config[2]
		for batch in range(STEPS/100):
			solver.advance(100,Vector2(0,.00002),.01);rd.submit();rd.sync()
			if solver.tick-int(config[3]) not in [500,1000,2000,4000]:continue
			var sample:=capture(rd,solver,config[0]);samples.append(sample)
			if sample.invalid!=0 or sample.counts!=initial.counts:failures.append(str(config[0])+" state integrity")
			if absf(sample.gas_mass-initial.gas_mass)>maxf(1e-6,initial.gas_mass*1e-4):failures.append(str(config[0])+" gas mass")
			if absf(sample.fluid_mass-initial.fluid_mass)/initial.fluid_mass>1e-6:failures.append(str(config[0])+" fluid mass")
		if not config[2] and rd.buffer_get_data(solver.materials)!=data.materials.to_byte_array():failures.append("fixed geometry changed")
		cases.append({"name":config[0],"bed_rows":config[4],"fixed_geometry_warmup":config[3],"samples":samples});solver.release()
	var report:Dictionary={"integrity_failures":failures,"cases":cases,"physical_acceptance":"NOT ESTABLISHED: no contact reaction, load balance or contact work ledger in candidate","scope":"Same candidate Physics as main host. Bubble/water tests measure release regulation. Fixed bed isolates obstacle geometry, not externally applied load. Gas-weighted covariance measures shape, not load-induced compliance. Exit 0 means diagnostic integrity only."}
	var out:=FileAccess.open("res://reports/phase-contact-observation.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	print("CONTACT_OBSERVATION integrity_failures=",failures," physical_acceptance=NOT_ESTABLISHED")
	rd.free();quit(0 if failures.is_empty() else 1)
