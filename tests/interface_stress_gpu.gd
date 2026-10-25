extends RefCounted
const Fluid=preload("res://src/phase_fluid.gd")
static func run(rd:RenderingDevice)->int:
	var cases:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/interface-stress-fixture.json"))
	var failures:=0;var results:Array=[]
	for data in cases:
		var solver:=Fluid.new();solver.grain_motion_enabled=false;solver.interface_stress_enabled=true
		solver.local_displacement_geometry_enabled=true
		solver.grain_wetting_cosine=float(data.wetting_cosine)
		var n:int=data.side;var m:=PackedInt32Array(data.material)
		if not solver.initialize(rd,n,PackedFloat32Array(data.phase),m,PackedVector2Array(),true,709):return 1
		if not solver.record_coupled_step(Vector2.ZERO,float(data.sigma),128,.5,1.9,true):return 1
		rd.submit();rd.sync()
		var force:=rd.buffer_get_data(solver.interface_force).to_float32_array()
		var actual:=rd.buffer_get_data(solver.distributions[0]).to_float32_array()
		var phase:=rd.buffer_get_data(solver.phase[0]).to_float32_array();var phase_error:=0.
		var volume:=rd.buffer_get_data(solver.volume_geometry).to_float32_array();var volume_error:=0.
		var v:=rd.buffer_get_data(solver.boundary_velocity).to_float32_array()
		var status:=rd.buffer_get_data(solver.displacement_status).to_int32_array()
		var force_error:=0.;var population_error:=0.;var balance:=Vector2.ZERO
		for i in range(n*n):
			for k in range(4):volume_error=maxf(volume_error,absf(volume[4*i+k]-float(data.volume[i][k])))
			phase_error=maxf(phase_error,absf(phase[i]-float(data.phase_after[i])))
			for axis in range(2):force_error=maxf(force_error,absf(force[2*i+axis]-float(data.force[i][axis])))
			balance+=Vector2(force[2*i],force[2*i+1])
			for q in range(9):population_error=maxf(population_error,absf(actual[9*i+q]-float(data.populations[9*i+q])))
		var grain_error:=maxf(absf(v[130]-float(data.force[65][0])/3.),absf(v[131]-float(data.force[65][1])/3.))
		if status[1]!=1 or force_error>2e-8 or population_error>2e-7 or phase_error>2e-7 or volume_error>2e-7 or balance.length()>2e-8 or grain_error>2e-8:failures+=1
		results.append({"sigma":data.sigma,"wetting_cosine":data.wetting_cosine,"force_error":force_error,"phase_error":phase_error,"population_error":population_error,"grain_velocity_error":grain_error,"volume_error":volume_error,"net_force":balance.length(),"accepted":status[1]==1})
		solver.release()
	for cosine in [0.,.5]:
		var fields:=Fluid.contact_fields(128,32)
		var bed:=Fluid.new();bed.grain_motion_enabled=false;bed.interface_stress_enabled=true;bed.grain_wetting_cosine=cosine
		if not bed.initialize(rd,128,fields.gas,fields.walls,PackedVector2Array(),true,709):return 1
		var status:=PackedInt32Array();var accepted:=0
		for step in range(10000):
			if not bed.record_coupled_step(Vector2(0,.00002),.01,128,.5,1.9,true):return 1
			rd.submit();rd.sync();status=rd.buffer_get_data(bed.displacement_status).to_int32_array()
			if status[1]!=1:break
			accepted+=1
		var state:=bed.snapshot_bytes()
		var capture:=FileAccess.open("res://reports/interface-stress-heavy"+("-wetting" if cosine!=0. else "")+".state",FileAccess.WRITE);capture.store_buffer(state);capture.close()
		var counts:=[0,0,0,0,0];var initial_counts:=[0,0,0,0,0];var centroid:=0.
		for i in range(128*128):
			var mat:=state.decode_u32(128*128*40+i*4)
			if mat>4:failures+=1;continue
			counts[mat]+=1;initial_counts[fields.walls[i]]+=1
			if fields.walls[i]==1 and mat!=1:failures+=1
			if mat>=2:centroid+=(float(i/128)+state.decode_float(128*128*56+i*8+4))/1280.
		if counts!=initial_counts:failures+=1
		results.append({"case":"heavy-bed","wetting_cosine":cosine,"accepted_ticks":accepted,"rejection_flags":status[0],"grain_centroid_y":centroid,"counts":counts,"physical_acceptance":"NOT ESTABLISHED"})
		bed.release()
	var report:Dictionary={"cases":results,"failures":failures,"scope":"Coupled neutral/cubic grain boundary action/reaction and heavy-bed observation; not measured contact angles, interface work or sustained support validation"}
	var file:=FileAccess.open("res://reports/interface-stress.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("INTERFACE_STRESS ",report)
	return failures
