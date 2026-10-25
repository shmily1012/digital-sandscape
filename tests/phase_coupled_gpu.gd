extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:call_deferred("run")
func validate(fixture:Dictionary)->Dictionary:
	var rd:=RenderingServer.create_local_rendering_device();var solver:=Fluid.new()
	solver.load_factor=1.0 if fixture.loaded else 0.0
	solver.voxel_interface_enabled=fixture.get("paired",false)
	solver.grain_wetting_cosine=float(fixture.get("wetting_cosine",0.))
	if not solver.initialize(rd,int(fixture.side),PackedFloat32Array(fixture.initial),PackedInt32Array(fixture.wall),PackedVector2Array(),fixture.loaded or solver.voxel_interface_enabled):return {"initialization_failed":true}
	solver.grain_motion_enabled=false
	solver.advance(int(fixture.steps));rd.submit();rd.sync()
	var c:=rd.buffer_get_data(solver.phase[solver.tick%2]).to_float32_array()
	var v:=rd.buffer_get_data(solver.velocity).to_float32_array()
	var error:=0.;var velocity_error:=0.;var mass:=0.;var invalid:=0
	for i in range(c.size()):
		error=maxf(error,absf(c[i]-float(fixture.expected[i])));mass+=c[i]
		if not is_finite(c[i]) or c[i]<-1e-6 or c[i]>1.000001 or (fixture.wall[i]!=0 and c[i]!=0):invalid+=1
	for i in range(v.size()):
		velocity_error=maxf(velocity_error,absf(v[i]-float(fixture.velocity[i])))
		if not is_finite(v[i]):invalid+=1
	var report:Dictionary={"phase_error":error,"velocity_error":velocity_error,"gas_drift":absf(mass-float(fixture.mass)),"invalid":invalid,"steps":solver.tick}
	report["loaded"]=fixture.loaded
	report["paired"]=solver.voxel_interface_enabled
	report["wetting_cosine"]=solver.grain_wetting_cosine
	solver.release();rd.free();return report
func run()->void:
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/phase-coupled-fixture.json"))
	var reports:Array=[];var failures:=0
	for fixture in fixtures:
		var result:=validate(fixture);reports.append(result)
		if result.get("initialization_failed",false) or result.phase_error>=2e-5 or result.velocity_error>=2e-6 or result.gas_drift>=1e-4 or result.invalid!=0:failures+=1
	var file:=FileAccess.open("res://reports/phase-coupled-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"cases":reports},"  "));file.close()
	print("PHASE_COUPLED_RESULT failures=%d "%failures,reports);quit(0 if failures==0 else 1)
