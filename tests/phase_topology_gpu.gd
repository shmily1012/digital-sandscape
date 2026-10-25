extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:call_deferred("run")
static func measure(c:PackedFloat32Array,n:int,threshold:float=0.5)->Dictionary:
	var seen:=PackedByteArray();seen.resize(c.size());var components:Array[int]=[];var mass:=0.;var invalid:=0;var small:Array[int]=[]
	for value in c:
		mass+=value
		if not is_finite(value) or value< -1e-6 or value>1.000001:invalid+=1
	for i in range(c.size()):
		if seen[i]!=0 or c[i]<threshold:continue
		var stack:Array[int]=[i];seen[i]=1;var count:=0
		while not stack.is_empty():
			var a:int=stack.pop_back();count+=1
			for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
				var q:Vector2i=Vector2i(a%n,a/n)+d
				if q.x<0 or q.y<0 or q.x>=n or q.y>=n:continue
				var b:int=q.y*n+q.x
				if seen[b]==0 and c[b]>=threshold:seen[b]=1;stack.append(b)
		if count>=20:components.append(count)
		else:small.append(count)
	return {"components":components.size(),"small_areas":small,"all_components":components.size()+small.size(),"areas":components,"mass":mass,"invalid":invalid}
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device();var reports:Array=[];var failures:=0
	for scenario in ["merge","separated","neck","stretch"]:
		var n:=128;var c:=PackedFloat32Array();c.resize(n*n);var wall:=PackedInt32Array();wall.resize(n*n)
		for y in range(n):
			for x in range(n):
				var i:=y*n+x;var point:=Vector2(x,y)
				if point.distance_to(Vector2(63.5,63.5))>=62.:wall[i]=1;continue
				var radius:=12. if scenario in ["merge","separated"] else 13.
				var separation:=27. if scenario=="merge" else 40.
				var left:=Vector2(64.-separation*.5,64.);var right:=Vector2(64.+separation*.5,64.)
				var a:=.5*(1.-tanh(.5*(point.distance_to(left)-radius)))
				var b:=.5*(1.-tanh(.5*(point.distance_to(right)-radius)))
				c[i]=1.-(1.-a)*(1.-b)
				if scenario in ["neck","stretch"]:
					var box:=Vector2(absf(point.x-64.)-20.,absf(point.y-64.)-2.)
					var distance:=Vector2(maxf(box.x,0.),maxf(box.y,0.)).length()+minf(maxf(box.x,box.y),0.)
					var bridge:=.5*(1.-tanh(.5*distance));c[i]=1.-(1.-c[i])*(1.-bridge)
		var flow:=PackedVector2Array()
		if scenario=="stretch":
			flow.resize(n*n)
			for i in range(n*n):
				var point:=Vector2(i%n-64,i/n-64);var envelope:=exp(-point.length_squared()/1225.)
				flow[i]=0.003*envelope*Vector2(point.x*(1.-2.*point.y*point.y/1225.),-point.y*(1.-2.*point.x*point.x/1225.))
		var solver:=Fluid.new()
		if not solver.initialize(rd,n,c,wall,flow):quit(1);return
		var record:Dictionary={"scenario":scenario,"initial":measure(c,n),"samples":[]}
		if record.initial.components!=(2 if scenario in ["merge","separated"] else 1):failures+=1
		for _batch in range(40):
			solver.advance(100,Vector2.ZERO,0.01);rd.submit();rd.sync()
			if solver.tick%500==0:
				var current:=rd.buffer_get_data(solver.phase[solver.tick%2]).to_float32_array()
				var stats:=measure(current,n);stats["tick"]=solver.tick;stats["components_04"]=measure(current,n,0.4).components;stats["components_06"]=measure(current,n,0.6).components;record.samples.append(stats)
				if stats.invalid!=0 or absf(stats.mass-record.initial.mass)/record.initial.mass>1e-4:failures+=1
				var image:=Image.create(n,n,false,Image.FORMAT_RGB8)
				for pixel in range(current.size()):image.set_pixel(pixel%n,pixel/n,Color(current[pixel],current[pixel],current[pixel]))
				image.save_png("res://reports/topology-%s-%d.png"%[scenario,solver.tick])
		var last:Dictionary=record.samples.back();var expected:=1 if scenario in ["merge","neck"] else 2
		if last.components!=expected or last.components_04!=expected or last.components_06!=expected:failures+=1
		reports.append(record);solver.release()
	var file:=FileAccess.open("res://reports/phase-topology-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(reports,"  "));file.close()
	print("PHASE_TOPOLOGY_RESULT failures=%d"%failures);rd.free();quit(0 if failures==0 else 1)

