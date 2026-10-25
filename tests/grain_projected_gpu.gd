extends RefCounted
const Fluid=preload("res://src/phase_fluid.gd")
static func run(rd:RenderingDevice)->int:
	var cases:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-projected-fixture.json"))
	var failures:=0;var error:=0.;var residual_error:=0.
	for data in cases:
		var n:int=data.side;var c:=PackedFloat32Array();c.resize(n*n)
		var m:=PackedInt32Array(data.materials);var v:=PackedVector2Array();v.resize(n*n)
		for i in range(n*n):v[i]=Vector2(data.velocity[i][0],data.velocity[i][1])
		var solver:=Fluid.new();solver.grain_motion_enabled=false
		if not solver.initialize(rd,n,c,m,PackedVector2Array(),true,709,v):return 1
		var diagonals:bool=data.get("diagonals",false)
		if diagonals:
			if not solver.initialize_displacement():return 1
			var offset:=PackedVector2Array();offset.resize(n*n)
			for i in range(n*n):offset[i]=Vector2(data.offset[i][0],data.offset[i][1])
			rd.buffer_update(solver.grain_offset,0,n*n*8,offset.to_byte_array())
		var before:=solver.snapshot_bytes()
		if not solver.record_grain_contact_impulses(128,float(data.friction),1.,false,Vector2.ZERO,false,float(data.relaxation),diagonals):return 1
		rd.submit();rd.sync()
		var actual:=rd.buffer_get_data(solver.contact_velocity).to_float32_array()
		var reaction:=rd.buffer_get_data(solver.contact_candidate_reaction).to_float32_array()
		var status:=rd.buffer_get_data(solver.contact_status)
		if (status.decode_u32(8)==1)!=bool(data.accepted):failures+=1
		if status.decode_u32(8)==0 and solver.snapshot_bytes()!=before:failures+=1
		residual_error=maxf(residual_error,absf(status.decode_float(0)-float(data.residual)))
		var energy_before:=0.;var energy_after:=0.;var work:=0.;var balance:=Vector2.ZERO
		for i in range(n*n):
			for axis in range(2):
				error=maxf(error,absf(actual[2*i+axis]-float(data.expected[i][axis])))
				error=maxf(error,absf(reaction[2*i+axis]-float(data.reaction[i][axis])))
			var current:=Vector2(actual[2*i],actual[2*i+1]);var impulse:=Vector2(reaction[2*i],reaction[2*i+1])
			if m[i]>=2:
				var mass:float=3. if m[i]==2 else (2.7 if m[i]==3 else 2.4)
				energy_before+=.5*mass*v[i].length_squared();energy_after+=.5*mass*current.length_squared();balance+=mass*(current-v[i])
			elif m[i]==1:balance+=impulse;work-=impulse.dot(v[i])
		if balance.length()>2e-7 or energy_after>energy_before+work+1e-8:failures+=1
		solver.release()
	if error>2e-7 or residual_error>1e-7:failures+=1
	var result:Dictionary={"failures":failures,"cases":cases.size(),"max_cpu_error":error,"max_residual_error":residual_error}
	var file:=FileAccess.open("res://reports/grain-projected.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("GRAIN_PROJECTED ",result)
	return failures
