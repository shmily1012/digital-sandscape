extends RefCounted
const Fluid=preload("res://src/phase_fluid.gd")
static func run(rd:RenderingDevice)->int:
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-coupled-fixture.json"))
	var failures:=0;var results:Array=[]
	for data in fixtures:
		var n:int=data.side;var cells:=n*n;var initial:Dictionary=data.initial
		var v:=PackedVector2Array();v.resize(cells)
		var offset:=PackedVector2Array();offset.resize(cells)
		for i in range(cells):v[i]=Vector2(initial.velocity[i][0],initial.velocity[i][1]);offset[i]=Vector2(initial.offset[i][0],initial.offset[i][1])
		var solver:=Fluid.new();solver.grain_motion_enabled=false
		if not solver.initialize(rd,n,PackedFloat32Array(initial.phase),PackedInt32Array(initial.materials),PackedVector2Array(),true,709,v) or not solver.initialize_displacement():return 1
		rd.buffer_update(solver.grain_offset,0,cells*8,offset.to_byte_array())
		var old_failures:=failures;var max_error:=0.;var accepted_ticks:=0
		for frame in data.frames:
			var before:=solver.snapshot_bytes()
			if not solver.record_coupled_step(Vector2(data.gravity[0],data.gravity[1]),float(data.sigma),128,.5):return 1
			rd.submit();rd.sync()
			var status:=rd.buffer_get_data(solver.displacement_status).to_int32_array()
			accepted_ticks=rd.buffer_get_data(solver.coupled_clock).decode_u32(0)
			if (status[1]==1)!=bool(frame.accepted) or accepted_ticks!=int(frame.ticks):failures+=1
			var actual:=solver.snapshot_bytes()
			if not bool(frame.accepted):
				if before.size()==cells*64:before.resize(cells*64+4)
				if actual!=before:failures+=1
			for i in range(cells):
				if actual.decode_u32(cells*40+i*4)!=int(frame.materials[i]):failures+=1
				max_error=maxf(max_error,absf(actual.decode_float(i*4)-float(frame.phase[i])))
				for q in range(9):max_error=maxf(max_error,absf(actual.decode_float(cells*4+(i*9+q)*4)-float(frame.populations[i*9+q])))
				for axis in range(2):
					max_error=maxf(max_error,absf(actual.decode_float(cells*44+i*8+axis*4)-float(frame.velocity[i][axis])))
					max_error=maxf(max_error,absf(actual.decode_float(cells*56+i*8+axis*4)-float(frame.offset[i][axis])))
		if max_error>2e-6:failures+=1
		results.append({"case":data.name,"accepted_ticks":accepted_ticks,"max_cpu_error":max_error,"failures":failures-old_failures})
		solver.release()
	# Exercise the actual heavy-bed initializer, not just isolated particles.
	var fields:=Fluid.contact_fields(128,32)
	for config in [[0.,128,false],[1.9,128,false],[1.9,128,true]]:
		var relaxation:float=config[0];var budget:int=config[1];var diagonals:bool=config[2]
		var bed:=Fluid.new();bed.grain_motion_enabled=false
		if not bed.initialize(rd,128,fields.gas,fields.walls,PackedVector2Array(),true,709) or not bed.initialize_displacement():return 1
		var bed_before:=bed.snapshot_bytes()
		var initial_inventory:=inventory(bed_before,128)
		rd.capture_timestamp("bed_begin")
		if not bed.record_coupled_step(Vector2(0,.00002),.01,budget,.5,relaxation,diagonals):return 1
		rd.capture_timestamp("bed_end")
		rd.submit();rd.sync()
		var begin_time:=0;var end_time:=0
		for index in range(rd.get_captured_timestamps_count()):
			if rd.get_captured_timestamp_name(index)=="bed_begin":begin_time=rd.get_captured_timestamp_gpu_time(index)
			if rd.get_captured_timestamp_name(index)=="bed_end":end_time=rd.get_captured_timestamp_gpu_time(index)
		var bed_status:=rd.buffer_get_data(bed.displacement_status).to_int32_array()
		var bed_contact:=rd.buffer_get_data(bed.contact_status)
		var bed_clock:=rd.buffer_get_data(bed.coupled_clock).decode_u32(0)
		if bed_status[1]==0:
			bed_before.resize(bed_before.size()+4)
			if bed.snapshot_bytes()!=bed_before or bed_clock!=0:failures+=1
		var continued:=0
		if relaxation>=1.9 and bed_status[1]==1:
			for _step in range(9999):
				var previous:=bed.snapshot_bytes()
				if not bed.record_coupled_step(Vector2(0,.00002),.01,budget,.5,relaxation,diagonals):return 1
				rd.submit();rd.sync()
				bed_status=rd.buffer_get_data(bed.displacement_status).to_int32_array()
				if bed_status[1]==0:
					var zero:=PackedByteArray();zero.resize(128*128*8)
					if bed.snapshot_bytes()!=previous or rd.buffer_get_data(bed.contact_reaction)!=zero:failures+=1
					break
				continued+=1
			bed_contact=rd.buffer_get_data(bed.contact_status)
			bed_clock=rd.buffer_get_data(bed.coupled_clock).decode_u32(0)
		if relaxation==1.9 and bed_status[1]==0:
			for entry in [["state",bed.snapshot_bytes()],["candidate",rd.buffer_get_data(bed.contact_velocity)]]:
				var capture:=FileAccess.open("res://reports/coupled-heavy-rejected"+("-diagonal" if diagonals else "")+"."+entry[0],FileAccess.WRITE);capture.store_buffer(entry[1]);capture.close()
		var final_bytes:=bed.snapshot_bytes()
		var final_inventory:=inventory(final_bytes,128)
		var mass_drift:float=absf(final_inventory.mass-initial_inventory.mass)/initial_inventory.mass
		var gas_drift:float=absf(final_inventory.gas-initial_inventory.gas)
		if mass_drift>1e-6 or gas_drift>1e-3:failures+=1
		if diagonals:
			var capture:=FileAccess.open("res://reports/coupled-heavy-diagonal-final.state",FileAccess.WRITE);capture.store_buffer(final_bytes);capture.close()
		var final_material:=rd.buffer_get_data(bed.materials).to_int32_array()
		var final_offset:=rd.buffer_get_data(bed.grain_offset).to_float32_array()
		var initial_counts:=[0,0,0,0,0];var final_counts:=[0,0,0,0,0];var changed_cells:=0;var mean_offset_y:=0.
		for i in range(128*128):
			initial_counts[fields.walls[i]]+=1
			if final_material[i]>=2:mean_offset_y+=final_offset[2*i+1]/1280.
			if final_material[i]<0 or final_material[i]>4:failures+=1;continue
			final_counts[final_material[i]]+=1
			if final_material[i]!=fields.walls[i]:changed_cells+=1
			if fields.walls[i]==1 and final_material[i]!=1:failures+=1
		if initial_counts!=final_counts:failures+=1
		var crossing:Dictionary={"count":0,"examples":[]}
		if (bed_status[0]&32)!=0:
			var candidate_gas:=rd.buffer_get_data(bed.coupled_candidate_phase).to_float32_array()
			var live_gas:=rd.buffer_get_data(bed.phase[bed.tick%2]).to_float32_array()
			var trial_velocity:=rd.buffer_get_data(bed.contact_velocity).to_float32_array()
			for i in range(128*128):
				if final_material[i]<2:continue
				var old:=Vector2(final_offset[2*i],final_offset[2*i+1])
				var delta:=Vector2(trial_velocity[2*i],trial_velocity[2*i+1])
				var shift:=Vector2i((old+delta+Vector2(.5,.5)).floor())
				var xy:=Vector2i(i%128,i/128);var dest:=xy+shift
				if dest.x<0 or dest.y<0 or dest.x>=128 or dest.y>=128:continue
				var j:=dest.y*128+dest.x
				if final_material[j]!=0 or candidate_gas[j]<=.05:continue
				crossing.count+=1
				if crossing.examples.size()<16:
					var overlap_before:float=maxf(0.,1.-absf(float(shift.x)-old.x))*maxf(0.,1.-absf(float(shift.y)-old.y))
					var overlap_after:float=maxf(0.,1.-absf(float(shift.x)-old.x-delta.x))*maxf(0.,1.-absf(float(shift.y)-old.y-delta.y))
					crossing.examples.append({"source":i,"target":j,"offset":[old.x,old.y],"displacement":[delta.x,delta.y],"live_gas":live_gas[j],"candidate_gas":candidate_gas[j],"target_solid_area_before":overlap_before,"target_solid_area_after":overlap_after,"new_covered_area":overlap_after-overlap_before})
			if crossing.count==0:failures+=1
		results.append({"case":"actual-heavy-bed-first-step","changed_material_cells":changed_cells,"mean_grain_offset_y":mean_offset_y,"relaxation":relaxation,"diagonals":diagonals,"sweep_budget":budget,"first_step_gpu_ms":float(end_time-begin_time)/1000000.,"continued_steps":continued,"accepted_ticks":bed_clock,"contact_residual":bed_contact.decode_float(0),"contact_invalid":bed_contact.decode_u32(4),"rejection_flags":bed_status[0],"fluid_mass_relative_drift":mass_drift,"gas_drift":gas_drift,"accepted":bed_status[1]==1,"physical_acceptance":"NOT ESTABLISHED"})
		results[-1]["gas_entry_geometry"]=crossing
		bed.release()
	var result:Dictionary={"failures":failures,"cases":results,"scope":"Joint fluid, phase, grain and accepted-clock transaction. Short trajectories only; interface work and bubble support remain unvalidated."}
	var file:=FileAccess.open("res://reports/grain-coupled.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("GRAIN_COUPLED ",result)
	return failures

static func inventory(bytes:PackedByteArray,n:int)->Dictionary:
	var cells:=n*n;var gas:=0.;var mass:=0.
	for i in range(cells):
		gas+=bytes.decode_float(i*4)
		if bytes.decode_u32(cells*40+i*4)!=0:continue
		mass+=bytes.decode_float(cells*52+i*4)
		for q in range(9):mass+=bytes.decode_float(cells*4+(i*9+q)*4)
	return {"gas":gas,"mass":mass}
