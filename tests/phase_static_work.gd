extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var n:=64;var c:=PackedFloat32Array();c.resize(n*n)
	var m:=PackedInt32Array();m.resize(n*n)
	for y in range(n):
		for x in range(n):
			if Vector2(x-31.5,y-31.5).length()>30.:m[y*n+x]=1
			elif x>=26 and x<=37 and y>=18 and y<=25:m[y*n+x]=2
	var cases:Array=[];var integrity_failures:=0
	if Fluid.new().load_factor!=0.:integrity_failures+=1
	for factor in [0.,1.]:
		var solver:=Fluid.new();solver.load_factor=factor;solver.grain_motion_enabled=false
		if not solver.initialize(rd,n,c,m,PackedVector2Array(),true,123):quit(1);return
		var samples:Array=[]
		for batch in range(80):
			solver.advance(100,Vector2(0,0.00002),0.01);rd.submit();rd.sync()
			if (batch+1)%5!=0:continue
			var u:=rd.buffer_get_data(solver.velocity).to_float32_array()
			var f:=rd.buffer_get_data(solver.distributions[solver.tick%2]).to_float32_array()
			var load:=rd.buffer_get_data(solver.loads).to_float32_array()
			var kinetic:=0.;var power:=0.;var max_speed:=0.;var mass:=0.;var invalid:=0
			for i in range(n*n):
				if m[i]!=0:continue
				var rho:=0.
				for q in range(9):rho+=f[9*i+q]
				var speed2:=u[2*i]*u[2*i]+u[2*i+1]*u[2*i+1]
				if not is_finite(speed2) or not is_finite(rho):invalid+=1
				kinetic+=0.5*rho*speed2;mass+=rho;max_speed=maxf(max_speed,sqrt(speed2))
				power+=factor*load[i]*0.00002*u[2*i+1]
			if invalid>0:integrity_failures+=1
			samples.append({"tick":solver.tick,"kinetic_energy":kinetic,"load_power":power,"max_speed":max_speed,"fluid_mass":mass,"invalid":invalid})
		if rd.buffer_get_data(solver.materials)!=m.to_byte_array():integrity_failures+=1
		cases.append({"load_factor":factor,"samples":samples});solver.release()
	var baseline:Dictionary=cases[0].samples[-1];var loaded:Dictionary=cases[1].samples[-1]
	# A fixed boundary does no mechanical work. Persistent positive source power
	# and flow above the unforced numerical floor reject this load closure.
	var rejected:=true
	for sample in cases[1].samples.slice(-4):
		rejected=rejected and sample.load_power>1e-10 and sample.kinetic_energy>maxf(1e-8,100.*baseline.kinetic_energy)
	var report:Dictionary={"integrity_failures":integrity_failures,"static_load_model_rejected":rejected,"geometry":"fixed 12x8 grain roof in sealed circle; zero gas; initially resting fluid","steps":8000,"cases":cases}
	var file:=FileAccess.open("res://reports/phase-static-work.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("STATIC_WORK rejected=",rejected," baseline=",baseline," loaded=",loaded)
	rd.free();quit(0 if integrity_failures==0 else 1)
