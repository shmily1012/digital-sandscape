extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:call_deferred("run")
func mass_of(m:int)->float:return 3. if m==2 else (2.7 if m==3 else 2.4)
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-contact-impulse-fixture.json"))
	var reports:Array=[];var failures:=0
	for data in fixtures:
		var n:int=data.side;var m:=PackedInt32Array(data.materials);var c:=PackedFloat32Array();c.resize(n*n)
		var velocity:=PackedVector2Array();velocity.resize(n*n)
		for i in range(n*n):velocity[i]=Vector2(data.velocity[i][0],data.velocity[i][1])
		var solver:=Fluid.new();solver.grain_motion_enabled=false
		if not solver.initialize(rd,n,c,m,PackedVector2Array(),true,709,velocity):quit(1);return
		var physical_before:=solver.snapshot_bytes()
		# The old stochastic mover must not silently mix with physical velocities.
		solver.grain_motion_enabled=true
		if solver.record_grain_contact_impulses() or solver.snapshot_bytes()!=physical_before:failures+=1
		solver.grain_motion_enabled=false
		if not solver.record_grain_contact_impulses(int(data.sweeps),float(data.friction)):quit(1);return
		rd.submit();rd.sync()
		var actual:=rd.buffer_get_data(solver.contact_velocity).to_float32_array()
		var reaction:=rd.buffer_get_data(solver.contact_candidate_reaction).to_float32_array()
		var status:=rd.buffer_get_data(solver.contact_status)
		var accepted:=status.decode_u32(8)==1
		if accepted!=bool(data.accepted) or status.decode_u32(4)!=0:failures+=1
		var published:=rd.buffer_get_data(solver.contact_reaction)
		if accepted:
			if rd.buffer_get_data(solver.boundary_velocity)!=actual.to_byte_array() or published!=reaction.to_byte_array():failures+=1
		else:
			var zero:=PackedByteArray();zero.resize(n*n*8)
			if solver.snapshot_bytes()!=physical_before or published!=zero:failures+=1
		var velocity_error:=0.;var impulse_error:=0.;var residual_x:=0.;var residual_y:=0.;var initial_energy:=0.;var final_energy:=0.;var work:=0.;var max_closing:=0.
		for i in range(n*n):
			for axis in range(2):
				if not is_finite(actual[2*i+axis]) or not is_finite(reaction[2*i+axis]):failures+=1
				velocity_error=maxf(velocity_error,absf(actual[2*i+axis]-float(data.expected[i][axis])))
				impulse_error=maxf(impulse_error,absf(reaction[2*i+axis]-float(data.reaction[i][axis])))
			if m[i]>=2:
				var mass:=mass_of(m[i])
				residual_x+=mass*(actual[2*i]-float(data.velocity[i][0]));residual_y+=mass*(actual[2*i+1]-float(data.velocity[i][1]))
				initial_energy+=.5*mass*(pow(float(data.velocity[i][0]),2)+pow(float(data.velocity[i][1]),2))
				final_energy+=.5*mass*(pow(actual[2*i],2)+pow(actual[2*i+1],2))
			elif m[i]==1:
				residual_x+=reaction[2*i];residual_y+=reaction[2*i+1]
				work-=reaction[2*i]*float(data.velocity[i][0])+reaction[2*i+1]*float(data.velocity[i][1])
				if actual[2*i]!=velocity[i].x or actual[2*i+1]!=velocity[i].y:failures+=1
			for axis in range(2):
				var coordinate:int=i%n if axis==0 else i/n
				if coordinate+1>=n:continue
				var j:int=i+(1 if axis==0 else n)
				if m[i]!=0 and m[j]!=0 and (m[i]>=2 or m[j]>=2):max_closing=maxf(max_closing,actual[2*i+axis]-actual[2*j+axis])
		var residual:=sqrt(residual_x*residual_x+residual_y*residual_y)
		if velocity_error>1e-7 or impulse_error>2e-7 or residual>2e-7 or final_energy>initial_energy+work+1e-8:failures+=1
		if data.name!="chain" and max_closing>1e-7:failures+=1
		var physical_after:=solver.snapshot_bytes();var cells:=n*n
		if physical_after.slice(0,cells*44)!=physical_before.slice(0,cells*44) or physical_after.slice(cells*52)!=physical_before.slice(cells*52):failures+=1
		if absf(status.decode_float(0)-max_closing)>1e-9:failures+=1
		var recovery_error:=0.;var recovery_closing:=0.
		if data.name=="chain":
			if not solver.record_grain_contact_impulses(128,float(data.friction)):quit(1);return
			rd.submit();rd.sync();status=rd.buffer_get_data(solver.contact_status)
			recovery_closing=status.decode_float(0)
			if status.decode_u32(8)!=1 or status.decode_u32(4)!=0 or recovery_closing>1e-7:failures+=1
			var recovered:=rd.buffer_get_data(solver.boundary_velocity).to_float32_array()
			for i in range(n*n):
				for axis in range(2):recovery_error=maxf(recovery_error,absf(recovered[2*i+axis]-float(data.recovery_expected[i][axis])))
			if recovery_error>1e-7:failures+=1
			# Apply a test-only kick, then deliberately exhaust the next budget.
			# A previous success must not leak its acceptance flag or reaction.
			rd.buffer_update(solver.boundary_velocity,0,n*n*8,velocity.to_byte_array())
			var before_retry:=solver.snapshot_bytes()
			if not solver.record_grain_contact_impulses(1,float(data.friction)):quit(1);return
			rd.submit();rd.sync();status=rd.buffer_get_data(solver.contact_status)
			var zero:=PackedByteArray();zero.resize(n*n*8)
			if status.decode_u32(8)!=0 or solver.snapshot_bytes()!=before_retry or rd.buffer_get_data(solver.contact_reaction)!=zero:failures+=1
			if solver.record_grain_contact_impulses(129,float(data.friction)) or solver.snapshot_bytes()!=before_retry:failures+=1
		if data.name=="pair" and int(data.orientation)==0 and float(data.friction)==.5:
			# Corrupt a test input after validated initialization; NaN must never
			# pass the reduction or publish a candidate into other live entries.
			var corrupted:=rd.buffer_get_data(solver.boundary_velocity);corrupted.encode_float((3*n+3)*8,NAN)
			rd.buffer_update(solver.boundary_velocity,0,corrupted.size(),corrupted)
			var before_invalid:=solver.snapshot_bytes()
			if not solver.record_grain_contact_impulses(8,.5):quit(1);return
			rd.submit();rd.sync();status=rd.buffer_get_data(solver.contact_status)
			var zero:=PackedByteArray();zero.resize(n*n*8)
			if status.decode_u32(4)==0 or status.decode_u32(8)!=0 or solver.snapshot_bytes()!=before_invalid or rd.buffer_get_data(solver.contact_reaction)!=zero:failures+=1
		reports.append({"case":data.name,"orientation":data.orientation,"friction":data.friction,"accepted":accepted,"velocity_error":velocity_error,"impulse_error":impulse_error,"momentum_residual":residual,"initial_energy":initial_energy,"final_energy":final_energy,"wall_work":work,"remaining_closing_speed":max_closing,"recovery_error":recovery_error,"recovery_closing_speed":recovery_closing})
		solver.release()
	var displacement_failures:int=preload("res://tests/grain_displacement_gpu.gd").run(rd)
	failures+=displacement_failures
	failures+=preload("res://tests/grain_projected_gpu.gd").run(rd)
	failures+=preload("res://tests/grain_coupled_gpu.gd").run(rd)
	failures+=preload("res://tests/interface_stress_gpu.gd").run(rd)
	failures+=preload("res://tests/grain_volume_gpu.gd").run(rd)
	var result:Dictionary={"failures":failures,"cases":reports,"scope":"GPU nonpenetration gate for local face impulses; rejected candidates preserve live state and publish zero reaction. No position advancement or bubble coupling. Does not establish a full frictional complementarity solve. Default app does not call this operator."}
	var file:=FileAccess.open("res://reports/grain-contact-impulse.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("GRAIN_CONTACT_IMPULSE ",result);rd.free();quit(0 if failures==0 else 1)

