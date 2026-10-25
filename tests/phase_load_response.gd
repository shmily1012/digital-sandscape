extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:call_deferred("run")
func stats(c:PackedFloat32Array,m:PackedInt32Array,n:int)->Dictionary:
	var mass:=0.;var cy:=0.;var sand_y:=0.;var count:=0;var invalid:=0;var inventory:Array[int]=[0,0,0,0,0]
	for i in range(c.size()):
		mass+=c[i];cy+=(i/n)*c[i];inventory[m[i]]+=1
		if not is_finite(c[i]) or c[i]<-1e-6 or c[i]>1.000001 or (m[i]!=0 and c[i]!=0.):invalid+=1
		if m[i]>=2:sand_y+=i/n;count+=1
	return {"gas_mass":mass,"gas_y":cy/mass,"sand_y":sand_y/maxi(count,1),"inventory":inventory,"invalid":invalid}
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device();var n:=256;var fields:=Fluid.initial_fields(n,20261024,true)
	var initial:=stats(fields.gas,fields.walls,n);var reports:Array=[];var previous:=PackedFloat32Array();var difference:=0.;var failures:=0
	for factor in [0.,1.]:
		var solver:=Fluid.new();solver.load_factor=factor
		if not solver.initialize(rd,n,fields.gas,fields.walls,PackedVector2Array(),true,20261024):quit(1);return
		for _batch in range(15):solver.advance(100,Vector2(0,0.00002),0.01);rd.submit();rd.sync()
		var gas:=rd.buffer_get_data(solver.phase[solver.tick%2]).to_float32_array();var m:=rd.buffer_get_data(solver.materials).to_int32_array()
		var result:=stats(gas,m,n);result["factor"]=factor
		if result.invalid!=0 or result.inventory!=initial.inventory or absf(result.gas_mass-initial.gas_mass)/initial.gas_mass>1e-6:failures+=1
		# Derived load is recomputed on final geometry for an unambiguous budget audit.
		var list:=rd.compute_list_begin();solver.record_load(list,Vector2(0,0.00002));rd.compute_list_end();rd.submit();rd.sync()
		var load:=rd.buffer_get_data(solver.loads).to_float32_array();var fluid_sink:=0.;var wall_sink:=0.;var weight:=0.
		for i in range(m.size()):
			if m[i]==0:fluid_sink+=load[i]
			elif m[i]==1:wall_sink+=load[i]
			else:weight+=2. if m[i]==2 else (1.7 if m[i]==3 else 1.4)
		result["fluid_sink"]=fluid_sink;result["wall_sink"]=wall_sink;result["weight"]=weight
		if absf(fluid_sink+wall_sink-weight)/weight>1e-5:failures+=1
		if previous.is_empty():previous=gas
		else:
			for i in range(gas.size()):difference+=absf(gas[i]-previous[i])
		reports.append(result);solver.release()
	if difference<1.:failures+=1
	var report:Dictionary={"failures":failures,"initial":initial,"steps":1500,"gas_l1_difference":difference,"cases":reports}
	var file:=FileAccess.open("res://reports/phase-load-response.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("PHASE_LOAD_RESPONSE ",report)
	rd.free();quit(0 if failures==0 else 1)
