extends RefCounted
const Fluid=preload("res://src/phase_fluid.gd")
static func run(rd:RenderingDevice)->int:
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-displacement-fixture.json"))
	var failures:=0;var results:Array=[]
	for data in fixtures:
		var n:int=data.side;var count:=n*n
		var materials:=PackedInt32Array(data.materials)
		var gas:=PackedFloat32Array();gas.resize(count)
		var v:=PackedVector2Array();v.resize(count)
		var populations:=PackedFloat32Array();populations.resize(count*9)
		var residual:=PackedFloat32Array();residual.resize(count)
		for i in range(count):
			v[i]=Vector2(data.velocity[i][0],data.velocity[i][1])
			gas[i]=0. if materials[i]!=0 else float(i%17)/1024.
			residual[i]=float(i)/1048576.
			for q in range(9):populations[i*9+q]=float(i*9+q)/65536.
		var forced:bool=data.get("forced",false)
		var gravity:=Vector2.ZERO
		if forced:
			gas.fill(0.);residual.fill(0.);populations=PackedFloat32Array(data.populations)
			gravity=Vector2(data.gravity[0],data.gravity[1])
		var solver:=Fluid.new();solver.grain_motion_enabled=false
		if not solver.initialize(rd,n,gas,materials,PackedVector2Array(),true,709,v):return 1
		rd.buffer_update(solver.distributions[0],0,populations.size()*4,populations.to_byte_array())
		rd.buffer_update(solver.mass_residual,0,residual.size()*4,residual.to_byte_array())
		var joint:bool=data.get("joint",false)
		if joint:
			if not solver.initialize_displacement():return 1
			var offsets:=PackedVector2Array();offsets.resize(count)
			for i in range(count):offsets[i]=Vector2(data.initial_offset[i][0],data.initial_offset[i][1])
			rd.buffer_update(solver.grain_offset,0,count*8,offsets.to_byte_array())
		var before_failures:=failures;var accepted_steps:=0;var momentum_residual:=0.
		for frame in data.frames:
			var before:=solver.snapshot_bytes()
			if not (solver.record_grain_contact_motion(1.,128,.5,gravity,forced) if joint else solver.record_grain_displacement()):return 1
			rd.submit();rd.sync()
			var status:=rd.buffer_get_data(solver.displacement_status).to_int32_array()
			var accepted:bool=status[1]==1
			if accepted!=bool(frame.accepted):failures+=1
			if accepted:accepted_steps+=1
			var actual:=solver.snapshot_bytes()
			var offsets:=rd.buffer_get_data(solver.grain_offset).to_float32_array()
			if joint:
				var reaction:=rd.buffer_get_data(solver.contact_reaction).to_float32_array()
				for i in range(count):
					for axis in range(2):
						if absf(reaction[2*i+axis]-float(frame.reaction[i][axis]))>2e-7:failures+=1
			for i in range(count):
				var source:int=frame.sources[i]
				if actual.decode_float(i*4)!=gas[source] or actual.decode_u32(count*40+i*4)!=int(frame.materials[i]) or actual.decode_float(count*52+i*4)!=residual[source]:failures+=1
				for q in range(9):
					if actual.decode_float(count*4+(i*9+q)*4)!=populations[source*9+q]:failures+=1
				for axis in range(2):
					if absf(actual.decode_float(count*44+i*8+axis*4)-float(frame.velocity[i][axis]))>1e-7 or absf(offsets[i*2+axis]-float(frame.offset[i][axis]))>1e-7:failures+=1
			if not accepted:
				# The first invocation lazily allocates a zero offset buffer.
				if before.size()==count*56:before.resize(count*64)
				if solver.snapshot_bytes()!=before:failures+=1
		if forced:
			var raw:=rd.buffer_get_data(solver.traction).to_float32_array()
			for i in range(count):
				for axis in range(2):
					if absf(raw[2*i+axis]-float(data.raw_impulse[i][axis]))>2e-7:failures+=1
			# A separate same-input fluid branch verifies momentum exchange. It is
			# deliberately not claimed as an atomic fluid+grain production step.
			var fluid:=Fluid.new();fluid.grain_motion_enabled=false
			if not fluid.initialize(rd,n,gas,materials,PackedVector2Array(),true,709,v):return 1
			rd.buffer_update(fluid.distributions[0],0,populations.size()*4,populations.to_byte_array())
			fluid.advance(1,gravity,0.);rd.submit();rd.sync()
			var next_f:=rd.buffer_get_data(fluid.distributions[1]).to_float32_array()
			var final_v:=rd.buffer_get_data(solver.boundary_velocity).to_float32_array()
			var reaction:=rd.buffer_get_data(solver.contact_reaction).to_float32_array()
			var ledger:=Vector2.ZERO
			var directions:Array[Vector2]=[Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(-1,0),Vector2(0,-1),Vector2(1,1),Vector2(-1,1),Vector2(-1,-1),Vector2(1,-1)]
			for i in range(count):
				for q in range(9):
					if absf(next_f[i*9+q]-float(data.fluid_next[i*9+q]))>2e-7:failures+=1
					if materials[i]==0:ledger+=(next_f[i*9+q]-populations[i*9+q])*directions[q]
				if materials[i]>=2:
					var mass:float=3. if materials[i]==2 else (2.7 if materials[i]==3 else 2.4)
					ledger+=mass*(Vector2(final_v[2*i],final_v[2*i+1])-v[i])-(mass-1.)*gravity
				elif materials[i]==1:ledger+=Vector2(raw[2*i]+reaction[2*i],raw[2*i+1]+reaction[2*i+1])
			momentum_residual=ledger.length()
			if momentum_residual>2e-6:failures+=1
			print("FORCED_CONTACT_LEDGER ",data.name," residual=",ledger.length())
			fluid.release()
		var final_bytes:=solver.snapshot_bytes()
		if solver.record_grain_displacement(0.) or solver.snapshot_bytes()!=final_bytes:failures+=1
		results.append({"case":data.name,"accepted_steps":accepted_steps,"momentum_residual":momentum_residual,"failures":failures-before_failures})
		solver.release()
	var result:Dictionary={"failures":failures,"cases":results,"scope":"Contact, continuous displacement and optional raw fluid/gravity impulse prediction. Same-input fluid branch verifies momentum exchange; no atomic fluid/grain time advancement or bubble support acceptance."}
	var file:=FileAccess.open("res://reports/grain-displacement.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("GRAIN_DISPLACEMENT ",result)
	return failures

