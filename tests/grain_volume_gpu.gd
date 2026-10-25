extends RefCounted
const Fluid=preload("res://src/phase_fluid.gd")
static func run(rd:RenderingDevice)->int:
	var cases:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-volume-fixture.json"))
	var failures:=0;var results:Array=[]
	for data in cases:
		var n:int=data.side;var c:=PackedFloat32Array();c.resize(n*n)
		var o:=PackedVector2Array();var v:=PackedVector2Array();o.resize(n*n);v.resize(n*n)
		for i in range(n*n):o[i]=Vector2(data.offset[i][0],data.offset[i][1]);v[i]=Vector2(data.velocity[i][0],data.velocity[i][1])
		var solver:=Fluid.new();solver.grain_motion_enabled=false
		if not solver.initialize(rd,n,c,PackedInt32Array(data.material),PackedVector2Array(),true,709) or not solver.initialize_displacement():return 1
		if not solver.record_grain_contact_impulses(1):return 1
		rd.submit();rd.sync()
		rd.buffer_update(solver.grain_offset,0,n*n*8,o.to_byte_array());rd.buffer_update(solver.contact_velocity,0,n*n*8,v.to_byte_array())
		var zero:=PackedByteArray();zero.resize(16);rd.buffer_update(solver.contact_status,0,16,zero)
		var before:=solver.snapshot_bytes()
		if not solver.record_grain_volume_flux():return 1
		rd.submit();rd.sync()
		var actual:=rd.buffer_get_data(solver.volume_geometry).to_float32_array()
		var aperture:=rd.buffer_get_data(solver.volume_aperture).to_float32_array();var aperture_error:=0.
		var invalid:=rd.buffer_get_data(solver.contact_status).decode_u32(4)!=0
		var error:=0.;var residual:=0.;var volume_change:=0.
		for i in range(n*n):
			for axis in range(2):aperture_error=maxf(aperture_error,absf(aperture[2*i+axis]-float(data.aperture[i][axis])))
			for k in range(4):error=maxf(error,absf(actual[4*i+k]-float(data.expected[i][k])))
			var divergence:float=actual[4*i+2]+actual[4*i+3]-(actual[4*(i-1)+2] if i%n else 0.)-(actual[4*(i-n)+3] if i>=n else 0.)
			residual=maxf(residual,absf(actual[4*i+1]-actual[4*i]-divergence));volume_change+=actual[4*i+1]-actual[4*i]
		if error>1e-6 or aperture_error>1e-6 or residual>5e-7 or absf(volume_change)>1e-5 or invalid==bool(data.valid) or solver.snapshot_bytes()!=before:failures+=1
		if not solver.record_local_drainage(128,1e-7):return 1
		rd.submit();rd.sync()
		var drainage:=rd.buffer_get_data(solver.drainage_status);var flow:=rd.buffer_get_data(solver.drainage_flux).to_float32_array();var flow_error:=0.;var blocked_flux:=0.
		for i in range(n*n):
			for axis in range(2):
				if bool(data.valid):flow_error=maxf(flow_error,absf(flow[2*i+axis]-float(data.fluid_flux[i][axis])))
				if aperture[2*i+axis]==0.:blocked_flux=maxf(blocked_flux,absf(flow[2*i+axis]))
		if (drainage.decode_u32(4)==1)!=bool(data.valid) or flow_error>5e-6 or blocked_flux!=0. or solver.snapshot_bytes()!=before:failures+=1
		if not solver.record_drainage_reaction():return 1
		rd.submit();rd.sync()
		var pressure_force:=rd.buffer_get_data(solver.drainage_reaction).to_float32_array()
		var force_error:=0.;var pressure_work:=0.;var dissipation:=0.
		for i in range(n*n):
			for axis in range(2):
				var expected:float=data.pressure_reaction[i][axis] if bool(data.valid) else 0.
				force_error=maxf(force_error,absf(pressure_force[2*i+axis]-expected));pressure_work+=pressure_force[2*i+axis]*v[i][axis]
				if aperture[2*i+axis]>0.:dissipation+=flow[2*i+axis]*flow[2*i+axis]/aperture[2*i+axis]
		if force_error>2e-6 or (bool(data.valid) and (pressure_work>0. or absf(pressure_work+dissipation)>1e-7)) or solver.snapshot_bytes()!=before:failures+=1
		results.append({"case":data.name+"-reaction","force_cpu_error":force_error,"pressure_work":pressure_work,"drainage_dissipation":dissipation,"work_residual":absf(pressure_work+dissipation)})
		results.append({"case":data.name,"max_cpu_error":error,"aperture_error":aperture_error,"continuity_residual":residual,"volume_change":volume_change,"invalid":invalid,"drainage_residual":drainage.decode_float(0),"drainage_iterations":drainage.decode_u32(8),"drainage_accepted":drainage.decode_u32(4)==1,"flow_cpu_error":flow_error,"blocked_face_flux":blocked_flux})
		if bool(data.valid):
			var input_gas:=solver.buffer(n*n*4)
			for profile in data.gas_profiles:
				var gas:=PackedFloat32Array();gas.resize(n*n)
				for i in range(n*n):gas[i]=actual[4*i]*float(profile.fraction[i])
				rd.buffer_update(input_gas,0,n*n*4,gas.to_byte_array());rd.buffer_update(solver.contact_status,0,16,zero)
				if not solver.record_gas_transport(input_gas):return 1
				rd.submit();rd.sync()
				var gas_state:=rd.buffer_get_data(solver.gas_transport_status)
				var gas_after:=rd.buffer_get_data(solver.gas_transport_candidate).to_float32_array()
				var gas_error:=0.;var drift:=0.;var violations:=0
				for i in range(n*n):
					gas_error=maxf(gas_error,absf(gas_after[i]-float(profile.expected[i])));drift+=gas_after[i]-gas[i]
					if gas_after[i]<0. or gas_after[i]>actual[4*i+1]:violations+=1
				if gas_state.decode_u32(4)!=1 or gas_error>2e-6 or violations!=0 or solver.snapshot_bytes()!=before or rd.buffer_get_data(input_gas)!=gas.to_byte_array():failures+=1
				results.append({"case":data.name+"-"+profile.name,"gas_accepted":gas_state.decode_u32(4)==1,"gas_flags":gas_state.decode_u32(8),"gas_cpu_error":gas_error,"gas_inventory_delta":drift,"gas_equation_residual":gas_state.decode_float(0),"transport_error_after_volume_defect":gas_state.decode_float(16),"upstream_pressure_residual":gas_state.decode_float(20),"capacity_violations":violations})
			if data.name=="angle-0":
				var malformed:=PackedFloat32Array();malformed.resize(n*n);malformed[n+1]=actual[4*(n+1)]+1.
				rd.buffer_update(input_gas,0,n*n*4,malformed.to_byte_array());rd.buffer_update(solver.contact_status,0,16,zero)
				if not solver.record_gas_transport(input_gas):return 1
				rd.submit();rd.sync();var overflow_rejected:=rd.buffer_get_data(solver.gas_transport_status).decode_u32(4)==0
				malformed.fill(0.);rd.buffer_update(input_gas,0,n*n*4,malformed.to_byte_array());rd.buffer_update(solver.contact_status,0,16,zero)
				if not solver.record_gas_transport(input_gas,64,.5):return 1
				rd.submit();rd.sync();var timestep_rejected:=rd.buffer_get_data(solver.gas_transport_status).decode_u32(4)==0
				for i in range(n*n):malformed[i]=actual[4*i]*float(data.gas_profiles[2].fraction[i])
				rd.buffer_update(input_gas,0,n*n*4,malformed.to_byte_array());rd.buffer_update(solver.contact_status,0,16,zero)
				if not solver.record_gas_transport(input_gas,1):return 1
				rd.submit();rd.sync();var budget_rejected:=rd.buffer_get_data(solver.gas_transport_status).decode_u32(4)==0
				rd.buffer_update(solver.contact_status,0,16,zero)
				if not solver.record_gas_transport(input_gas):return 1
				rd.submit();rd.sync();var recovered:=rd.buffer_get_data(solver.gas_transport_status).decode_u32(4)==1
				if not overflow_rejected or not timestep_rejected or not budget_rejected or not recovered or solver.snapshot_bytes()!=before:failures+=1
				results.append({"case":"gas-rejection-and-recovery","overflow_rejected":overflow_rejected,"timestep_rejected":timestep_rejected,"budget_rejected":budget_rejected,"recovered":recovered})
		if data.name=="angle-0":
			# Insufficient work and sealed drainage must reject without publishing
			# a stale success or changing any physical state.
			rd.buffer_update(solver.contact_status,0,16,zero)
			if not solver.record_local_drainage(1,1e-7):return 1
			rd.submit();rd.sync()
			var budget_rejected:=rd.buffer_get_data(solver.drainage_status).decode_u32(4)==0
			var sealed:=PackedByteArray();sealed.resize(n*n*8)
			if not solver.record_drainage_reaction():return 1
			rd.submit();rd.sync();var stale_force_cleared:=rd.buffer_get_data(solver.drainage_reaction)==sealed
			rd.buffer_update(solver.contact_status,0,16,zero);rd.buffer_update(solver.volume_aperture,0,sealed.size(),sealed)
			if not solver.record_local_drainage():return 1
			rd.submit();rd.sync()
			var sealed_rejected:=rd.buffer_get_data(solver.drainage_status).decode_u32(4)==0
			rd.buffer_update(solver.contact_status,0,16,zero)
			if not solver.record_grain_volume_flux() or not solver.record_local_drainage(128,1e-7):return 1
			rd.submit();rd.sync()
			var recovered:=rd.buffer_get_data(solver.drainage_status).decode_u32(4)==1
			if not budget_rejected or not sealed_rejected or not recovered or not stale_force_cleared or solver.snapshot_bytes()!=before:failures+=1
			results.append({"case":"rejection-and-recovery","budget_rejected":budget_rejected,"sealed_rejected":sealed_rejected,"recovered":recovered,"stale_force_cleared":stale_force_cleared})
		solver.release()
	var report:Dictionary={"failures":failures,"cases":results,"scope":"Local candidate geometry, drainage, gas advection and pressure reaction; NOT closed dynamics, publication or static bubble-support acceptance"}
	var file:=FileAccess.open("res://reports/grain-volume.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("GRAIN_VOLUME ",report)
	return failures
