extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-load-fixture.json"))
	var rd:=RenderingServer.create_local_rendering_device();var solver:=Fluid.new();var gas:=PackedFloat32Array();gas.resize(int(data.side)*int(data.side))
	if not solver.initialize(rd,int(data.side),gas,PackedInt32Array(data.materials),PackedVector2Array(),true):quit(1);return
	var reports:Array=[];var failures:=0
	for sample in data.cases:
		var list:=rd.compute_list_begin();solver.record_load(list,Vector2(sample.gravity[0],sample.gravity[1]));rd.compute_list_end();rd.submit();rd.sync()
		var actual:=rd.buffer_get_data(solver.loads).to_float32_array();var error:=0.;var terminal:=0.
		for i in range(actual.size()):
			if not is_finite(actual[i]) or actual[i]<0.:failures+=1
			error=maxf(error,absf(actual[i]-float(sample.expected[i])))
			if data.materials[i]<2:terminal+=actual[i]
		var expected_total:float=data.total_weight if sample.angle!=null else 0.
		if error>2e-5 or absf(terminal-expected_total)>1e-4:failures+=1
		reports.append({"angle":sample.angle,"max_error":error,"terminal":terminal,"expected_total":expected_total})
	var file:=FileAccess.open("res://reports/grain-load-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"cases":reports},"  "));file.close()
	print("GRAIN_LOAD_RESULT failures=%d "%failures,reports);solver.release();rd.free();quit(0 if failures==0 else 1)
