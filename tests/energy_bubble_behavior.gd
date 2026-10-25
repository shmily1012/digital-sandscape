extends SceneTree
## Exercise the same energy-exchange configuration as the visible candidate.
const Fluid=preload("res://src/phase_fluid.gd")
const Topology=preload("res://tests/phase_topology_gpu.gd")
const N=128
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	if not value:failures.append(message);push_error(message)
func sample(rd:RenderingDevice,solver:RefCounted,name:String)->Dictionary:
	var c:=rd.buffer_get_data(solver.phase[solver.tick%2]).to_float32_array()
	var m:=rd.buffer_get_data(solver.materials).to_int32_array()
	var f:=rd.buffer_get_data(solver.distributions[solver.tick%2]).to_float32_array()
	var fluid_mass:=0.
	var counts:Array[int]=[0,0,0,0,0];var released:=0;var sy:=0.;var gx:=0.;var gy:=0.;var invalid:=0
	for i in range(N*N):
		if m[i]<0 or m[i]>4:invalid+=1;continue
		counts[m[i]]+=1
		if m[i]!=0 and c[i]!=0.:invalid+=1
		if m[i]==0:
			for q in range(9):
				var value:=f[9*i+q]
				if not is_finite(value) or value<0.:invalid+=1
				fluid_mass+=value
		var outside:=Vector2(i%N-63.5,i/N-63.5).length()>=62.
		if outside!=(m[i]==1):invalid+=1
		if m[i]>=2:sy+=i/N;released+=int(i/N>=.72*N)
		gx+=c[i]*(i%N);gy+=c[i]*(i/N)
	var result:=Topology.measure(c,N);var mass:float=result.mass
	result.tick=solver.tick;result.counts=counts;result.invalid+=invalid
	result.fluid_mass=fluid_mass
	result.released=released;result.sand_count=counts[2]+counts[3]+counts[4]
	result.sand_y=sy/maxi(1,result.sand_count);result.gas_y=gy/maxf(mass,1e-30)
	result.components_04=Topology.measure(c,N,.4).components;result.components_06=Topology.measure(c,N,.6).components
	var cx:=gx/maxf(mass,1e-30);var cy:=gy/maxf(mass,1e-30);var xx:=0.;var yy:=0.;var xy:=0.
	for i in range(N*N):
		var x:=float(i%N)-cx;var y:=float(i/N)-cy;xx+=c[i]*x*x;yy+=c[i]*y*y;xy+=c[i]*x*y
	var disc:=sqrt((xx-yy)*(xx-yy)+4.*xy*xy)
	result.axis_ratio=sqrt((xx+yy+disc)/maxf(xx+yy-disc,1e-30)) if mass>0 else 0.
	if solver.tick in [0,1000,4000] or (name=="sand-column" and result.components>=2):
		var img:=Image.create(N,N,false,Image.FORMAT_RGB8)
		for i in range(N*N):
			var color:=Color(.55,.57,.56).lerp(Color(.88,.9,.88),c[i])
			if m[i]==1:color=Color(.05,.05,.05)
			elif m[i]>=2:
				var shade:float=[.1,.4,.82][m[i]-2];color=Color(shade,shade,shade)
			img.set_pixel(i%N,i/N,color)
		img.resize(512,512,Image.INTERPOLATE_NEAREST)
		check(img.save_png("res://reports/energy-behavior-%s%s-%d.png"%[name,"-collective" if solver.grain_collective_enabled else "",solver.tick])==OK,"Capture failed")
	return result
func run_case(rd:RenderingDevice,fields:Dictionary,name:String,flow:PackedVector2Array,gravity:Vector2)->Dictionary:
	var solver:=Fluid.new();solver.grain_energy_enabled=true;solver.voxel_interface_enabled=true;solver.grain_wetting_cosine=.5
	solver.grain_collective_enabled="--collective-exchange" in OS.get_cmdline_user_args()
	if not solver.initialize(rd,N,fields.gas,fields.walls,flow,true,20261024):failures.append("Initialization "+name);return {}
	var initial:=sample(rd,solver,name);var samples:Array=[initial]
	for batch in range(40):
		solver.advance(100,gravity,.01);rd.submit();rd.sync()
		if solver.tick%500!=0 and name!="sand-column":continue
		var current:=sample(rd,solver,name);samples.append(current)
		check(current.invalid==0 and current.counts==initial.counts,name+" containment/materials")
		check(absf(current.mass-initial.mass)<=maxf(1e-6,initial.mass*1e-4),name+" gas inventory")
		check(absf(current.fluid_mass-initial.fluid_mass)<=initial.fluid_mass*1e-6,name+" fluid mass")
	var result:Dictionary={"name":name,"samples":samples};solver.release();return result
func topology_fields(scenario:String)->Dictionary:
	var c:=PackedFloat32Array();c.resize(N*N);var m:=PackedInt32Array();m.resize(N*N)
	for y in range(N):
		for x in range(N):
			var i:=y*N+x;var point:=Vector2(x,y)
			if point.distance_to(Vector2(63.5,63.5))>=62.:m[i]=1;continue
			# Mineral grains are real, movable inventory in the same solver path.
			if y in [106,107] and x>=48 and x<80:m[i]=2+(x+y)%3;continue
			var radius:=12. if scenario in ["merge","separated"] else 13.
			var separation:=27. if scenario=="merge" else 40.
			var a:=.5*(1.-tanh(.5*(point.distance_to(Vector2(64.-separation*.5,64.))-radius)))
			var b:=.5*(1.-tanh(.5*(point.distance_to(Vector2(64.+separation*.5,64.))-radius)))
			c[i]=1.-(1.-a)*(1.-b)
			if scenario in ["neck","stretch"]:
				var box:=Vector2(absf(point.x-64.)-20.,absf(point.y-64.)-2.)
				var distance:=Vector2(maxf(box.x,0.),maxf(box.y,0.)).length()+minf(maxf(box.x,box.y),0.)
				c[i]=1.-(1.-c[i])*(1.-.5*(1.-tanh(.5*distance)))
	return {"gas":c,"walls":m}
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var topology:Array=[];var loads:Array=[]
	for name in ["merge","separated","neck","stretch"]:
		var flow:=PackedVector2Array()
		if name=="stretch":
			flow.resize(N*N)
			for i in range(N*N):
				var point:=Vector2(i%N-64,i/N-64);var envelope:=exp(-point.length_squared()/1225.)
				flow[i]=.003*envelope*Vector2(point.x*(1.-2.*point.y*point.y/1225.),-point.y*(1.-2.*point.x*point.x/1225.))
		var result:=run_case(rd,topology_fields(name),name,flow,Vector2.ZERO)
		if result.is_empty():quit(1);return
		var initial:Dictionary=result.samples[0];var last:Dictionary=result.samples.back()
		check(initial.components==(2 if name in ["merge","separated"] else 1),name+" initial topology")
		var expected:=1 if name in ["merge","neck"] else 2
		check(last.components==expected and last.components_04==expected and last.components_06==expected,name+" final topology")
		topology.append(result)
	var common:=Fluid.contact_fields(N,32,true)
	for config in [["free",0,true],["thin",4,true],["medium",16,true],["heavy",32,true],["water",32,false]]:
		var fields:=Fluid.contact_fields(N,config[1],config[2])
		if config[2]:fields.gas=common.gas.duplicate()
		loads.append(run_case(rd,fields,config[0],PackedVector2Array(),Vector2(0,.00002)))
	var free:Dictionary=loads[0].samples.back();var heavy:Dictionary=loads[3].samples.back();var water:Dictionary=loads[4].samples.back()
	check(free.gas_y<float(loads[0].samples[0].gas_y)-1.,"Free bubble did not rise")
	check(heavy.gas_y>free.gas_y,"Sand did not obstruct bubble rise")
	check(water.released>heavy.released,"Gas did not regulate sand release")
	var column:=Fluid.contact_fields(N,0,false)
	for i in range(N*N):
		if column.walls[i]!=0:continue
		var x:=i%N;var y:=i/N
		if x>=60 and x<68 and y>=15 and y<64:column.walls[i]=2+(x+y)%3
		else:column.gas[i]=.5*(1.-tanh(.5*(Vector2(x,y).distance_to(Vector2(64,88))-18.)))
	var sand_split:=run_case(rd,column,"sand-column",PackedVector2Array(),Vector2(0,.00002))
	check(sand_split.samples[0].components==1,"Sand column initial bubble")
	var split_observed:=false
	for current:Dictionary in sand_split.samples:
		if current.components>=2 and current.components_04>=2 and current.components_06>=2:split_observed=true
	check(split_observed,"No sand-induced split observed")
	var report:Dictionary={"failures":failures,"topology":topology,"loads":loads,"sand_column":sand_split,"sand_split_observed":split_observed,"physical_acceptance":false,"scope":"Same effective energy-exchange runtime, cosine +0.5. Stretch uses controlled initial flow; sand-column uses only gravity and movable grains. Bed comparison measures obstruction/release, not force or pressure load balance."}
	report.collective_exchange="--collective-exchange" in OS.get_cmdline_user_args()
	var out:=FileAccess.open("res://reports/energy-bubble-behavior-collective.json" if report.collective_exchange else "res://reports/energy-bubble-behavior.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	print("ENERGY_BUBBLE_BEHAVIOR failures=",failures);rd.free();quit(0 if failures.is_empty() else 1)
