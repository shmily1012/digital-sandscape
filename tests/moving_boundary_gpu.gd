extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
const E=[Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(-1,0),Vector2(0,-1),Vector2(1,1),Vector2(-1,1),Vector2(-1,-1),Vector2(1,-1)]
func _initialize()->void:call_deferred("run")
func metrics(f:PackedFloat32Array,m:PackedInt32Array)->Dictionary:
	var mass:=0.;var energy:=0.;var px:=0.;var py:=0.;var invalid:=0
	for i in range(m.size()):
		if m[i]!=0:continue
		var rho:=0.;var x:=0.;var y:=0.
		for q in range(9):
			var value:=f[9*i+q];rho+=value;x+=value*E[q].x;y+=value*E[q].y
			if not is_finite(value) or value<0.:invalid+=1
		mass+=rho;px+=x;py+=y;energy+=.5*(x*x+y*y)/rho
	return {"mass":mass,"energy":energy,"px":px,"py":py,"invalid":invalid}
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/moving-boundary-fixture.json"))
	var results:Array=[];var failures:=0
	for data in fixtures:
		var n:int=data.side;var m:=PackedInt32Array(data.materials);var gas:=PackedFloat32Array();gas.resize(n*n)
		var uw:=PackedVector2Array();uw.resize(n*n)
		for i in range(n*n):uw[i]=Vector2(data.wall_velocity[2*i],data.wall_velocity[2*i+1])
		if data.speed!=0.:
			var unsafe_solver:=Fluid.new()
			if unsafe_solver.initialize(rd,n,gas,m,PackedVector2Array(),true,1,uw):
				failures+=1;unsafe_solver.release()
		var solver:=Fluid.new();solver.grain_motion_enabled=false
		if not solver.initialize(rd,n,gas,m,PackedVector2Array(),true,1,uw):quit(1);return
		var before:=metrics(rd.buffer_get_data(solver.distributions[0]).to_float32_array(),m)
		var max_residual:=0.;var first_error:=0.;var total_work:=0.;var state:=before
		for step in range(int(data.steps)):
			var list:=rd.compute_list_begin();var p:=PackedByteArray();p.resize(16);p.encode_u32(0,n);p.encode_u32(4,2)
			rd.compute_list_bind_compute_pipeline(list,solver.pipelines[3]);rd.compute_list_bind_uniform_set(list,solver.traction_sets[solver.tick%2],0)
			rd.compute_list_set_push_constant(list,p,16);rd.compute_list_dispatch(list,ceili(n*n/64.),1,1);rd.compute_list_add_barrier(list)
			rd.compute_list_end()
			solver.advance(1,Vector2.ZERO,0.);rd.submit();rd.sync()
			var impulse:=rd.buffer_get_data(solver.traction).to_float32_array();var jx:=0.;var jy:=0.
			for i in range(n*n):
				jx+=impulse[2*i];jy+=impulse[2*i+1]
				total_work-=impulse[2*i]*uw[i].x+impulse[2*i+1]*uw[i].y
				if step==0:
					first_error=maxf(first_error,absf(impulse[2*i]-float(data.first_impulse[2*i])))
					first_error=maxf(first_error,absf(impulse[2*i+1]-float(data.first_impulse[2*i+1])))
			state=metrics(rd.buffer_get_data(solver.distributions[solver.tick%2]).to_float32_array(),m)
			max_residual=maxf(max_residual,Vector2(state.px-before.px+jx,state.py-before.py+jy).length())
			if state.invalid>0:failures+=1
			before=state
		var actual:=rd.buffer_get_data(solver.distributions[solver.tick%2]).to_float32_array();var error:=0.
		for i in range(actual.size()):error=maxf(error,absf(actual[i]-float(data.expected[i])))
		if error>2e-6 or first_error>1e-7 or max_residual>2e-5 or absf(state.mass-m.count(0))>2e-4:failures+=1
		if data.speed!=0. and (total_work<=0. or state.energy<=0. or state.energy>total_work):failures+=1
		var driven_energy:float=state.energy
		# Stop the prescribed lid without resetting fluid, then allow viscous decay.
		var zero:=PackedByteArray();zero.resize(n*n*8);rd.buffer_update(solver.boundary_velocity,0,zero.size(),zero)
		for _batch in range(40):solver.advance(100,Vector2.ZERO,0.);rd.submit();rd.sync()
		var rest:=metrics(rd.buffer_get_data(solver.distributions[solver.tick%2]).to_float32_array(),m)
		if rest.invalid>0 or (data.speed!=0. and rest.energy>driven_energy*.001):failures+=1
		if absf(rest.mass-m.count(0))/m.count(0)>1e-6:failures+=1
		results.append({"speed":data.speed,"cpu_gpu_population_error":error,"first_impulse_error":first_error,"max_momentum_residual":max_residual,"wall_work_40_steps":total_work,"driven_energy":driven_energy,"mass_40_steps":state.mass,"after_stop_4000_steps":rest})
		solver.release()
	var report:Dictionary={"failures":failures,"scope":"tangential prescribed lid; fixed occupancy; zero gas; not translating grains","cases":results}
	var file:=FileAccess.open("res://reports/moving-boundary.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("MOVING_BOUNDARY ",report)
	rd.free();quit(0 if failures==0 else 1)
