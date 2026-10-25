extends SceneTree
const Pressure=preload("res://src/cut_cell_pressure.gd")
func _initialize()->void:call_deferred("run")
func residual(data:Dictionary,p:PackedFloat32Array)->float:
	var force:=PackedFloat64Array();force.resize(int(data.grains)*2)
	for w in data.weights:
		force[2*int(w[1])]-=float(w[2])*p[int(w[0])]
		force[2*int(w[1])+1]-=float(w[3])*p[int(w[0])]
	var error:=0.
	for i in range(int(data.nodes)):
		var value:=0.
		for k in range(int(data.edge_rows[i]),int(data.edge_rows[i+1])):
			var edge:Array=data.edges[k];value+=float(edge[1])*(float(p[i])-float(p[int(edge[0])]))
		for k in range(int(data.node_rows[i]),int(data.node_rows[i+1])):
			var w:Array=data.weights[int(data.node_ids[k])];var g:=int(w[1])
			value-=float(data.dt)*(float(w[2])*force[2*g]+float(w[3])*force[2*g+1])/float(data.mass[g])
		error=maxf(error,absf(value-float(data.expected[2*i+1])))
	return error

func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var cases:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/cut-cell-operator-fixture.json"))
	var results:Array=[];var failures:=0;var accepted_count:=0
	for data in cases:
		if not data.has("solve"):continue
		var solver:=Pressure.new()
		if not solver.initialize(rd,data):solver.release();rd.free();quit(1);return
		var rounded_reference_error:=residual(data,PackedFloat32Array(data.solve.pressure))
		for tolerance in [1e-7,1e-8,1e-9]:
			var old_pressure:=rd.buffer_get_data(solver.solution);var old_force:=rd.buffer_get_data(solver.solution_force)
			var old_generation:=rd.buffer_get_data(solver.accepted_generation)
			if not solver.record_pressure(float(data.dt),256,tolerance):failures+=1;continue
			rd.submit();rd.sync()
			var status:=rd.buffer_get_data(solver.solve_status);var accepted:=status.decode_u32(0)==1
			var p:=rd.buffer_get_data(solver.candidate_pressure).to_float32_array()
			var independent:=residual(data,p)
			if status.decode_u32(8)+status.decode_u32(20)>256 or status.decode_u32(16)>status.decode_u32(20):failures+=1
			if accepted:
				accepted_count+=1
				if not is_finite(independent) or independent>tolerance*1.1:failures+=1
			elif rd.buffer_get_data(solver.solution)!=old_pressure or rd.buffer_get_data(solver.solution_force)!=old_force or rd.buffer_get_data(solver.accepted_generation)!=old_generation:failures+=1
			results.append({"case":data.name,"tolerance":tolerance,"accepted":accepted,"iterations":status.decode_u32(8),"restarts":status.decode_u32(16),"verifications":status.decode_u32(20),"gpu_residual":status.decode_float(12),"independent_residual":independent,"rounded_reference_residual":rounded_reference_error})
		solver.release()
	var report:Dictionary={"failures":failures,"accepted_cases":accepted_count,"requested_cases":results.size(),"cases":results,"scope":"Precision diagnostic; safe rejection is not attainment of accuracy. Rounded reference residual is not a mathematical lower bound. No world-state update."}
	var file:=FileAccess.open("res://reports/cut-cell-pressure-precision.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("CUT_CELL_PRECISION ",report);rd.free();quit(0 if failures==0 else 1)
