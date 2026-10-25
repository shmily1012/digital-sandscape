extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:call_deferred("run")
func force_pass(rd:RenderingDevice,solver:RefCounted,list:int)->void:
	var p:=PackedByteArray();p.resize(16);p.encode_u32(0,solver.side)
	rd.compute_list_bind_compute_pipeline(list,solver.pipelines[3]);rd.compute_list_bind_uniform_set(list,solver.traction_sets[0],0)
	rd.compute_list_set_push_constant(list,p,16);rd.compute_list_dispatch(list,ceili(solver.side*solver.side/64.),1,1);rd.compute_list_add_barrier(list)
func run()->void:
	var cases:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-traction-fixture.json"))
	var rd:=RenderingServer.create_local_rendering_device();var reports:Array=[];var failures:=0
	for data in cases:
		var n:int=data.side;var gas:=PackedFloat32Array();gas.resize(n*n);var solver:=Fluid.new()
		if not solver.initialize(rd,n,gas,PackedInt32Array(data.materials),PackedVector2Array(),true,709):quit(1);return
		var bytes:=PackedFloat32Array(data.populations).to_byte_array();rd.buffer_update(solver.distributions[0],0,bytes.size(),bytes)
		var list:=rd.compute_list_begin();force_pass(rd,solver,list);rd.compute_list_end();rd.submit();rd.sync()
		var actual:=rd.buffer_get_data(solver.traction).to_float32_array();var error:=0.
		for i in range(actual.size()):
			if not is_finite(actual[i]):failures+=1
			error=maxf(error,absf(actual[i]-float(data.expected[i])))
		if error>1e-7:failures+=1
		var report:Dictionary={"case":data.name,"max_error":error,"force":[actual[int(data.center)*2],actual[int(data.center)*2+1]]}
		if data.name=="pressure":
			var moved:=false
			for tick in range(256):
				list=rd.compute_list_begin()
				for partition in range(2):
					force_pass(rd,solver,list)
					var p:=PackedByteArray();p.resize(32);p.encode_u32(0,n);p.encode_u32(4,709);p.encode_u32(8,tick);p.encode_u32(12,partition);p.encode_s32(20,32767);p.encode_float(24,0.00002)
					rd.compute_list_bind_compute_pipeline(list,solver.pipelines[2]);rd.compute_list_bind_uniform_set(list,solver.grain_sets[0],0)
					rd.compute_list_set_push_constant(list,p,32);rd.compute_list_dispatch(list,ceili((n/2.+1.)/8.),ceili((n/2.+1.)/8.),1);rd.compute_list_add_barrier(list)
				rd.compute_list_end();rd.submit();rd.sync()
				var m:=rd.buffer_get_data(solver.materials).to_int32_array();var index:=m.find(2)
				if index!=int(data.center):
					moved=true;report["first_move_tick"]=tick;report["from_y"]=int(data.center)/n;report["to_y"]=index/n
					if index<0 or index/n>=int(data.center)/n or m.count(2)!=1:failures+=1
					break
			if not moved:failures+=1
		reports.append(report);solver.release()
	var file:=FileAccess.open("res://reports/grain-traction-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"cases":reports},"  "));file.close()
	print("GRAIN_TRACTION_RESULT failures=%d "%failures,reports);rd.free();quit(0 if failures==0 else 1)
