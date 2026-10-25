extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-collective-fixture.json"))
	var failures:Array=[]
	for index in range(fixtures.size()):
		var case:Dictionary=fixtures[index];var solver:=Fluid.new();solver.grain_wetting_cosine=float(case.cosine)
		solver.grain_weight_scale=float(case.get("weight_scale",1.));solver.grain_mobility_scale=float(case.get("mobility_scale",1.))
		if not solver.initialize(rd,int(case.side),PackedFloat32Array(case.phase),PackedInt32Array(case.materials),PackedVector2Array(),true,20261024):quit(1);return
		var f:=PackedFloat32Array(case.populations).to_byte_array();var residual:=PackedFloat32Array(case.residual).to_byte_array()
		rd.buffer_update(solver.distributions[0],0,f.size(),f);rd.buffer_update(solver.mass_residual,0,residual.size(),residual)
		if not solver.initialize_collective_exchange():quit(1);return
		var list:=rd.compute_list_begin()
		for tick in range(int(case.steps)):
			solver.tick=tick;solver.record_collective_exchange(list,0,Vector2(case.gravity[0],case.gravity[1]),float(case.sigma))
		rd.compute_list_end();rd.submit();rd.sync()
		for pair in [[solver.phase[0],PackedFloat32Array(case.expected_phase).to_byte_array(),"phase"],[solver.materials,PackedInt32Array(case.expected_materials).to_byte_array(),"materials"],[solver.distributions[0],PackedFloat32Array(case.expected_populations).to_byte_array(),"populations"],[solver.mass_residual,PackedFloat32Array(case.expected_residual).to_byte_array(),"residual"],[solver.grain_energy_stamp,PackedInt32Array(case.expected_moved).to_byte_array(),"moved"]]:
			if rd.buffer_get_data(pair[0])!=pair[1]:failures.append([index,pair[2]])
		solver.release()
	var report:Dictionary={"failures":failures,"cases":fixtures.size(),"scope":"Collective exchange kernel only; no LBM coupling or physical acceptance."}
	var file:=FileAccess.open("res://reports/grain-collective-gpu.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("COLLECTIVE_EXCHANGE ",report);rd.free();quit(0 if failures.is_empty() else 1)
