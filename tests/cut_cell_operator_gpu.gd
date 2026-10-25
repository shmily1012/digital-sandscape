extends SceneTree
const Operator=preload("res://src/cut_cell_operator.gd")
const Pressure=preload("res://src/cut_cell_pressure.gd")
func _initialize()->void:call_deferred("run")
func check_operator_gate(rd:RenderingDevice,solver,dt:float)->bool:
	var previous:=rd.buffer_get_data(solver.output);var previous_force:=rd.buffer_get_data(solver.force)
	var marker:=previous.duplicate();marker.fill(90)
	var force_marker:=previous_force.duplicate();force_marker.fill(90)
	rd.buffer_update(solver.output,0,marker.size(),marker);rd.buffer_update(solver.force,0,force_marker.size(),force_marker)
	var list:=rd.compute_list_begin();solver.record_into(list,dt,solver.direction_set,true);rd.compute_list_end()
	rd.submit();rd.sync()
	var skipped:=rd.buffer_get_data(solver.output)==marker and rd.buffer_get_data(solver.force)==force_marker
	list=rd.compute_list_begin();solver.record_into(list,dt,solver.candidate_set);rd.compute_list_end()
	rd.submit();rd.sync()
	# Small buffers are padded to 16 bytes; the kernel owns only grains*8 bytes.
	return skipped and rd.buffer_get_data(solver.output)==previous and rd.buffer_get_data(solver.force).slice(0,solver.grains*8)==previous_force.slice(0,solver.grains*8)

func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var cases:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/cut-cell-operator-fixture.json"))
	var failures:=0;var results:Array=[];var pressure_results:Array=[]
	var rejected:=0
	for kind in range(4):
		var bad:Dictionary=cases[0].duplicate(true)
		if kind==0:bad.edges[0][0]=bad.nodes
		elif kind==1:bad.edge_rows[1]=-1
		elif kind==2:bad.node_ids[0]=bad.weights.size()
		else:bad.mass[0]=0.
		var invalid:=Operator.new()
		if invalid.initialize(rd,bad):failures+=1
		else:rejected+=1
		invalid.release()
	var asymmetric:Dictionary=cases[0].duplicate(true)
	asymmetric.edges[0][1]*=.5
	var invalid_pressure:=Pressure.new()
	var asymmetric_rejected:=not invalid_pressure.initialize(rd,asymmetric)
	if not asymmetric_rejected:failures+=1
	invalid_pressure.release()
	for data in cases:
		var solver:=Operator.new()
		if not solver.initialize(rd,data):solver.release();rd.free();quit(1);return
		var before:=rd.buffer_get_data(solver.pressure)
		if solver.record(-.1) or not solver.record(float(data.dt)):failures+=1
		rd.submit();rd.sync()
		var actual:=rd.buffer_get_data(solver.output).to_float32_array()
		var forces:=rd.buffer_get_data(solver.force).to_float32_array()
		var error:=0.;var force_error:=0.;var energy:=0.
		for i in range(data.expected.size()):
			if not is_finite(actual[i]):failures+=1
			error=maxf(error,absf(actual[i]-float(data.expected[i]))/maxf(1.,absf(float(data.expected[i]))))
		for i in range(data.expected_force.size()):
			if not is_finite(forces[i]):failures+=1
			force_error=maxf(force_error,absf(forces[i]-float(data.expected_force[i])))
		for i in range(int(data.nodes)):energy+=float(data.pressure[i])*actual[2*i]
		if error>3e-6 or force_error>1e-6 or energy < -1e-7 or rd.buffer_get_data(solver.pressure)!=before:failures+=1
		if int(data.components)>1 and float(data.dt)==0.:
			for i in range(int(data.nodes)):
				if actual[2*i]!=0.:failures+=1
		var first:=rd.buffer_get_data(solver.output)
		if not solver.record(float(data.dt)):failures+=1
		rd.submit();rd.sync()
		if rd.buffer_get_data(solver.output)!=first:failures+=1
		results.append({"case":data.name,"nodes":data.nodes,"components":data.components,"shared_cell_components":data.shared_cell_components,"scaled_error":error,"force_error":force_error,"quadratic_energy":energy})
		solver.release()
	for data in cases:
		var solver:=Pressure.new()
		if not solver.initialize(rd,data):solver.release();rd.free();quit(1);return
		var before:=rd.buffer_get_data(solver.solution)
		var force_before:=rd.buffer_get_data(solver.solution_force)
		if solver.record_pressure(float(data.dt),0) or not solver.record_pressure(float(data.dt),1):failures+=1
		rd.submit();rd.sync()
		var budget_rejected:=rd.buffer_get_data(solver.solve_status).decode_u32(0)==0 and rd.buffer_get_data(solver.solution)==before
		budget_rejected=budget_rejected and rd.buffer_get_data(solver.solution_force)==force_before and rd.buffer_get_data(solver.accepted_generation).decode_u32(0)==0
		budget_rejected=budget_rejected and check_operator_gate(rd,solver,float(data.dt))
		if not budget_rejected or not solver.record_pressure(float(data.dt),128):failures+=1
		rd.submit();rd.sync()
		var status:=rd.buffer_get_data(solver.solve_status);var accepted:=status.decode_u32(0)==1
		var solution:=rd.buffer_get_data(solver.solution).to_float32_array()
		var expected_accept:bool=data.has("solve")
		if accepted!=expected_accept or status.decode_u32(8)>128:failures+=1
		if not expected_accept and (status.decode_u32(8)!=0 or (status.decode_u32(4)&2)==0):failures+=1
		var source_error:=0.;var applied:=rd.buffer_get_data(solver.output).to_float32_array()
		for i in range(int(data.nodes)):source_error=maxf(source_error,absf(applied[2*i+1]-float(data.expected[2*i+1])))
		if source_error>1e-8:failures+=1
		var independent_residual:=0.;var force_error:=0.;var paired_force_error:=0.
		var recovery_ok:=false
		if accepted:
			var manual_force:=PackedFloat64Array();manual_force.resize(int(data.grains)*2)
			for w in data.weights:
				manual_force[2*int(w[1])]-=float(w[2])*solution[int(w[0])]
				manual_force[2*int(w[1])+1]-=float(w[3])*solution[int(w[0])]
			for i in range(int(data.nodes)):
				var value:=0.
				for k in range(int(data.edge_rows[i]),int(data.edge_rows[i+1])):
					var e:Array=data.edges[k];value+=float(e[1])*(float(solution[i])-float(solution[int(e[0])]))
				for k in range(int(data.node_rows[i]),int(data.node_rows[i+1])):
					var w:Array=data.weights[int(data.node_ids[k])];var g:=int(w[1])
					value-=float(data.dt)*(float(w[2])*manual_force[2*g]+float(w[3])*manual_force[2*g+1])/float(data.mass[g])
				independent_residual=maxf(independent_residual,absf(value-float(data.expected[2*i+1])))
			for k in range(manual_force.size()):force_error=maxf(force_error,absf(manual_force[k]-float(data.solve.force[k])))
			var published_force:=rd.buffer_get_data(solver.solution_force).to_float32_array()
			for k in range(manual_force.size()):paired_force_error=maxf(paired_force_error,absf(manual_force[k]-published_force[k]))
			if paired_force_error>1e-6 or rd.buffer_get_data(solver.accepted_generation).decode_u32(0)!=1:failures+=1
			if independent_residual>1.1e-6 or force_error>2e-5:failures+=1
			var accepted_bytes:=rd.buffer_get_data(solver.solution)
			var accepted_force:=rd.buffer_get_data(solver.solution_force)
			if not solver.record_pressure(float(data.dt),1):failures+=1
			rd.submit();rd.sync()
			if rd.buffer_get_data(solver.solve_status).decode_u32(0)!=0 or rd.buffer_get_data(solver.solution)!=accepted_bytes:failures+=1
			if rd.buffer_get_data(solver.solution_force)!=accepted_force or rd.buffer_get_data(solver.accepted_generation).decode_u32(0)!=1:failures+=1
			if not solver.record_pressure(float(data.dt),128):failures+=1
			rd.submit();rd.sync()
			recovery_ok=rd.buffer_get_data(solver.solve_status).decode_u32(0)==1 and rd.buffer_get_data(solver.solution)==accepted_bytes
			recovery_ok=recovery_ok and rd.buffer_get_data(solver.solution_force)==accepted_force and rd.buffer_get_data(solver.accepted_generation).decode_u32(0)==2
			if not recovery_ok:failures+=1
		elif rd.buffer_get_data(solver.solution)!=before or rd.buffer_get_data(solver.solution_force)!=force_before or rd.buffer_get_data(solver.accepted_generation).decode_u32(0)!=0:failures+=1
		var gate_verified:=check_operator_gate(rd,solver,float(data.dt))
		if not gate_verified:failures+=1
		pressure_results.append({"case":data.name,"accepted":accepted,"flags":status.decode_u32(4),"source_error":source_error,"gate_verified":gate_verified,"budget_rejected":budget_rejected,"recovery_ok":recovery_ok if accepted else null,"iterations":status.decode_u32(8),"gpu_true_residual":status.decode_float(12),"independent_residual":independent_residual if accepted else null,"force_cpu_error":force_error if accepted else null,"paired_force_error":paired_force_error if accepted else null,"published_generation":rd.buffer_get_data(solver.accepted_generation).decode_u32(0)})
		solver.release()
	var zero_data:Dictionary=cases[0].duplicate(true)
	zero_data.velocity.fill(0.)
	var zero_solver:=Pressure.new()
	var force_fault_rejected:=false;var generation_wrap_rejected:=false
	if not zero_solver.initialize(rd,zero_data) or not zero_solver.record_pressure(float(zero_data.dt),1):failures+=1
	else:
		rd.submit();rd.sync()
		var status:=rd.buffer_get_data(zero_solver.solve_status)
		if status.decode_u32(0)!=1 or status.decode_u32(8)!=0 or status.decode_float(12)!=0.:failures+=1
		for value in rd.buffer_get_data(zero_solver.solution).to_float32_array():
			if value!=0.:failures+=1
		var good_pressure:=rd.buffer_get_data(zero_solver.solution);var good_force:=rd.buffer_get_data(zero_solver.solution_force)
		rd.buffer_update(zero_solver.force,0,4,PackedFloat32Array([NAN]).to_byte_array())
		var list:=rd.compute_list_begin()
		for mode in [13,9,10,12]:zero_solver.vector_pass(list,mode,1e-6)
		rd.compute_list_end();rd.submit();rd.sync()
		status=rd.buffer_get_data(zero_solver.solve_status)
		force_fault_rejected=status.decode_u32(0)==0 and (status.decode_u32(4)&1)!=0 and rd.buffer_get_data(zero_solver.solution)==good_pressure and rd.buffer_get_data(zero_solver.solution_force)==good_force and rd.buffer_get_data(zero_solver.accepted_generation).decode_u32(0)==1
		var maximum:=PackedByteArray();maximum.resize(4);maximum.encode_u32(0,0xffffffff)
		rd.buffer_update(zero_solver.accepted_generation,0,4,maximum)
		if not zero_solver.record_pressure(float(zero_data.dt),1):failures+=1
		rd.submit();rd.sync();status=rd.buffer_get_data(zero_solver.solve_status)
		generation_wrap_rejected=status.decode_u32(0)==0 and (status.decode_u32(4)&4)!=0 and rd.buffer_get_data(zero_solver.accepted_generation).decode_u32(0)==0xffffffff and rd.buffer_get_data(zero_solver.solution)==good_pressure and rd.buffer_get_data(zero_solver.solution_force)==good_force
		if not force_fault_rejected or not generation_wrap_rejected:failures+=1
	zero_solver.release()
	var report:Dictionary={"failures":failures,"invalid_inputs_rejected":rejected,"asymmetric_rejected":asymmetric_rejected,"force_fault_rejected":force_fault_rejected,"generation_wrap_rejected":generation_wrap_rejected,"cases":results,"pressure_cases":pressure_results,"scope":"Frozen split-region GPU pressure and matching force publication. CPU supplies test topology. No moving topology, gas transport or world-state commit."}
	var file:=FileAccess.open("res://reports/cut-cell-operator-gpu.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("CUT_CELL_OPERATOR ",report);rd.free();quit(0 if failures==0 else 1)
