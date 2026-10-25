extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:call_deferred("run")
func validate(data:Dictionary)->Dictionary:
	var rd:=RenderingServer.create_local_rendering_device();var solver:=Fluid.new()
	if not solver.initialize(rd,int(data.side),PackedFloat32Array(data.initial),PackedInt32Array(data.materials),PackedVector2Array(),true,int(data.seed)):return {"initialization_failed":true}
	var bytes:=PackedFloat32Array(data.populations).to_byte_array()
	rd.buffer_update(solver.distributions[0],0,bytes.size(),bytes)
	if data.has("residuals"):
		var residual:=PackedFloat32Array(data.residuals).to_byte_array();rd.buffer_update(solver.mass_residual,0,residual.size(),residual)
	if data.has("forces"):
		var force_bytes:=PackedFloat32Array(data.forces).to_byte_array();rd.buffer_update(solver.traction,0,force_bytes.size(),force_bytes)
	else:
		var zero:=PackedByteArray();zero.resize(solver.side*solver.side*8);rd.buffer_update(solver.traction,0,zero.size(),zero)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,solver.pipelines[2]);rd.compute_list_bind_uniform_set(list,solver.grain_sets[0],0)
	for tick in range(int(data.steps)):
		var gravity:Array=data.gravities[int(tick/30)%6]
		for phase in range(2):
			var p:=PackedByteArray();p.resize(32);p.encode_u32(0,solver.side);p.encode_u32(4,int(data.seed));p.encode_u32(8,tick);p.encode_u32(12,phase);p.encode_s32(16,int(gravity[0]));p.encode_s32(20,int(gravity[1]))
			p.encode_float(24,float(data.get("gravity_scale",0.00002)))
			p.encode_u32(28,int(data.get("drag_divisor",1)))
			rd.compute_list_set_push_constant(list,p,32);rd.compute_list_dispatch(list,ceili((solver.side/2.+1.)/8.),ceili((solver.side/2.+1.)/8.),1);rd.compute_list_add_barrier(list)
	rd.compute_list_end();rd.submit();rd.sync()
	var gas_ok:=rd.buffer_get_data(solver.phase[0])==PackedFloat32Array(data.expected).to_byte_array()
	var fluid_ok:=rd.buffer_get_data(solver.distributions[0])==PackedFloat32Array(data.expected_populations).to_byte_array()
	var materials_ok:=rd.buffer_get_data(solver.materials)==PackedInt32Array(data.expected_materials).to_byte_array()
	var residual_ok:=true
	if data.has("expected_residuals"):residual_ok=rd.buffer_get_data(solver.mass_residual)==PackedFloat32Array(data.expected_residuals).to_byte_array()
	var forces_ok:=true
	if data.has("expected_forces"):forces_ok=rd.buffer_get_data(solver.traction)==PackedFloat32Array(data.expected_forces).to_byte_array()
	var report:Dictionary={"gas_exact":gas_ok,"populations_exact":fluid_ok,"materials_exact":materials_ok,"residual_exact":residual_ok,"steps":data.steps,"gravity_scale":data.get("gravity_scale",0.00002),"drag_divisor":data.get("drag_divisor",1)}
	report.forces_exact=forces_ok
	solver.release();rd.free();return report
func run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/phase-grains-fixture.json"))
	var reports:Array=[validate(data),validate(data.pressure_case)];var failures:=0
	for fixture in data.strength_cases:reports.append(validate(fixture))
	for fixture in data.drag_cases:reports.append(validate(fixture))
	for report in reports:
		if not report.get("gas_exact",false) or not report.get("populations_exact",false) or not report.get("materials_exact",false) or not report.get("residual_exact",false) or not report.get("forces_exact",false):failures+=1
	var file:=FileAccess.open("res://reports/phase-grains-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(reports,"  "));file.close();print("PHASE_GRAINS_RESULT failures=%d "%failures,reports)
	quit(0 if failures==0 else 1)
