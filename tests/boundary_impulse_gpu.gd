extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
const E=[Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(-1,0),Vector2(0,-1),Vector2(1,1),Vector2(-1,1),Vector2(-1,-1),Vector2(1,-1)]
const O=[0,3,4,1,2,7,8,5,6]
func _initialize()->void:call_deferred("run")
func momentum(f:PackedFloat32Array,m:PackedInt32Array)->Vector2:
	var result:=Vector2.ZERO
	for i in range(m.size()):
		if m[i]!=0:continue
		for q in range(9):result+=E[q]*f[9*i+q]
	return result
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-traction-fixture.json"))
	var reports:Array=[];var failures:=0
	for fixture in fixtures:
		var n:int=fixture.side;var m:=PackedInt32Array(fixture.materials)
		var c:=PackedFloat32Array();c.resize(n*n)
		var f:=PackedFloat32Array(fixture.populations);var solver:=Fluid.new()
		solver.grain_motion_enabled=false
		if not solver.initialize(rd,n,c,m,PackedVector2Array(),true,709):quit(1);return
		rd.buffer_update(solver.distributions[0],0,f.size()*4,f.to_byte_array())
		var list:=rd.compute_list_begin();var p:=PackedByteArray();p.resize(16);p.encode_u32(0,n);p.encode_u32(4,1)
		rd.compute_list_bind_compute_pipeline(list,solver.pipelines[3]);rd.compute_list_bind_uniform_set(list,solver.traction_sets[0],0)
		rd.compute_list_set_push_constant(list,p,16);rd.compute_list_dispatch(list,ceili(n*n/64.),1,1);rd.compute_list_add_barrier(list)
		rd.compute_list_end();rd.submit();rd.sync()
		var actual:=rd.buffer_get_data(solver.traction).to_float32_array()
		var max_error:=0.;var grain_impulse:=Vector2.ZERO;var wall_impulse:=Vector2.ZERO
		for i in range(n*n):
			var expected:=Vector2.ZERO
			if m[i]!=0:
				for q in range(1,9):
					var x:=i%n+int(E[q].x);var y:=i/n+int(E[q].y)
					if x<0 or y<0 or x>=n or y>=n:continue
					var j:=y*n+x
					if m[j]==0:expected-=2.*E[q]*f[9*j+O[q]]
			var impulse:=Vector2(actual[2*i],actual[2*i+1])
			if not impulse.is_finite():failures+=1
			max_error=maxf(max_error,(impulse-expected).length())
			max_error=maxf(max_error,absf(actual[2*i]-float(fixture.raw_expected[2*i])))
			max_error=maxf(max_error,absf(actual[2*i+1]-float(fixture.raw_expected[2*i+1])))
			if m[i]==1:wall_impulse+=impulse
			elif m[i]>=2:grain_impulse+=impulse
		solver.advance(1,Vector2.ZERO,0.);rd.submit();rd.sync()
		var after:=rd.buffer_get_data(solver.distributions[1]).to_float32_array()
		var delta:=momentum(after,m)-momentum(f,m)
		var residual:float=(delta+grain_impulse+wall_impulse).length()
		if max_error>1e-7 or residual>2e-5:failures+=1
		reports.append({"case":fixture.name,"cpu_gpu_error":max_error,"fluid_delta":[delta.x,delta.y],"grain_impulse":[grain_impulse.x,grain_impulse.y],"wall_impulse":[wall_impulse.x,wall_impulse.y],"momentum_residual":residual})
		solver.release()
	var report:Dictionary={"failures":failures,"scope":"fixed geometry, zero body force, one fluid step; no moving-particle claim","cases":reports}
	var file:=FileAccess.open("res://reports/boundary-impulse.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("BOUNDARY_IMPULSE ",report);rd.free();quit(0 if failures==0 else 1)
