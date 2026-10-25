extends RefCounted
## Candidate fluid component. All methods run on the owning RD thread.
const Compiler=preload("res://src/physics_engine.gd")
const GRAIN_RULE_REVISION=2
const COLLECTIVE_RULE_REVISION=2
var rd:RenderingDevice
var side:int
var tick:=0
var phase:Array[RID]=[]
var distributions:Array[RID]=[]
var velocity:RID
var resources:Array[RID]=[]
var shaders:Array[RID]=[]
var pipelines:Array[RID]=[]
var phase_sets:Array[RID]=[]
var momentum_sets:Array[RID]=[]
var materials:RID
var grain_sets:Array[RID]=[]
var grains_enabled:=false
var grain_seed:=0
var traction:RID
var traction_sets:Array[RID]=[]
var loads:RID
var load_set:RID
# Experimental scalar load injection fails the fixed-boundary work test.
# Keep opt-in for reproducing that failure; never enable in product defaults.
var load_factor:=0.0
var grain_motion_enabled:=true
## Experimental effective overdamped model. Temporary sessions only.
# Separate effective gravity work from kinetic resistance. Temporary model only.
var grain_weight_scale:=1.0
var grain_mobility_scale:=1.0
var grain_buoyant_enabled:=false
var buoyant_exchange:RefCounted
var grain_energy_enabled:=false
var grain_energy_pipeline:=RID()
var grain_energy_sets:Array[RID]=[]
var grain_energy_stamp:=RID()
var grain_collective_enabled:=false
var grain_collective_pipeline:=RID()
var grain_collective_sets:Array[RID]=[]
var grain_collective_gate_enabled:=true
var grain_collective_activity_pipeline:=RID()
var grain_collective_activity_set:=RID()
var grain_collective_dispatch:=RID()
## Diagnostic ablation only; do not interpret disabled traction as valid coupling.
var grain_traction_enabled:=true
## Temporary live-path candidate; no checkpoint compatibility is implied.
var voxel_interface_enabled:=false
var voxel_momentum_sets:Array[RID]=[]
var grain_drag_divisor:=1
var boundary_velocity:RID
var mass_residual:RID
var boundary_motion_enabled:=false
var contact_pipeline:=RID()
var contact_shader:=RID()
var contact_set:=RID()
var contact_reaction:=RID()
var contact_velocity:=RID()
var contact_candidate_reaction:=RID()
var contact_status:=RID()
var grain_offset:=RID()
var displacement_status:=RID()
var displacement_pipeline:=RID()
var displacement_sets:Array[RID]=[]
var displacement_joint_sets:Array[RID]=[]
var displacement_shader:=RID()
var displacement_scratch:Array[RID]=[]
var contact_offset:=RID()
var contact_edges:=RID()
var contact_edge_remainder:=RID()
var contact_diagonal_axes:=RID()
var coupled_clock:=RID()
var interface_stress_enabled:=false
var grain_wetting_cosine:=0.0
var local_displacement_geometry_enabled:=false
var volume_geometry:=RID()
var volume_aperture:=RID()
var volume_pipeline:=RID()
var volume_set:=RID()
var drainage_pipeline:=RID()
var drainage_set:=RID()
var drainage_flux:=RID()
var drainage_status:=RID()
var drainage_state:=RID()
var drainage_reaction:=RID()
var drainage_reaction_pipeline:=RID()
var drainage_reaction_set:=RID()
var gas_transport_pipeline:=RID()
var gas_transport_sets:Array[RID]=[]
var gas_transport_input:=RID()
var gas_transport_candidate:=RID()
var gas_transport_status:=RID()
var interface_force:=RID()
var interface_pipeline:=RID()
var interface_sets:Array[RID]=[]
var interface_traction_sets:Array[RID]=[]
var coupled_sets:Array[RID]=[]
var coupled_momentum_sets:Array[RID]=[]
var coupled_transport_sets:Array[RID]=[]
var coupled_candidate_phase:=RID()

func record_grain_displacement(dt:float=1.)->bool:
	# Kinematic remap only: no gravity, fluid step, or contact impulse is applied.
	# Acceptance is displacement_status[1]; false acceptance preserves all live
	# buffers. Not yet eligible for session saves or stochastic motion.
	if not grains_enabled or grain_motion_enabled or not is_finite(dt) or dt<=0. or dt>1.:return false
	if not initialize_displacement():return false
	return dispatch_displacement(dt,false)

func initialize_displacement()->bool:
	if not displacement_pipeline.is_valid():
		var shader:=Compiler.compile_shader(rd,"res://shaders/grain_displacement.glsl")
		if not shader.is_valid():return false
		displacement_shader=shader;shaders.append(shader);displacement_pipeline=rd.compute_pipeline_create(shader);pipelines.append(displacement_pipeline)
		var zero:=PackedByteArray();zero.resize(side*side*8)
		grain_offset=buffer(zero.size(),zero);displacement_status=buffer(8)
		var claims:=buffer(side*side*4);var targets:=buffer(side*side*4);var scratch:=buffer(side*side*64)
		displacement_scratch=[claims,targets,scratch]
		for parity in range(2):
			displacement_sets.append(uniform_set([phase[parity],distributions[parity],materials,mass_residual,boundary_velocity,grain_offset,claims,targets,scratch,displacement_status,boundary_velocity,displacement_status,boundary_velocity,boundary_velocity,phase[parity],distributions[parity],mass_residual,displacement_status],shader))
	return true

func dispatch_displacement(dt:float,joint:bool,coupled:bool=false)->bool:
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,displacement_pipeline)
	rd.compute_list_bind_uniform_set(list,(coupled_sets if coupled else (displacement_joint_sets if joint else displacement_sets))[tick%2],0)
	var push:=PackedByteArray();push.resize(16);push.encode_u32(0,side);push.encode_float(8,dt);push.encode_u32(12,2 if coupled else (1 if joint else 0))
	for mode in range(4):
		push.encode_u32(4,mode);rd.compute_list_set_push_constant(list,push,16)
		rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	rd.compute_list_end();return true

func record_grain_contact_motion(dt:float=1.,sweeps:int=32,friction:float=.5,gravity:Vector2=Vector2.ZERO,use_fluid_impulse:bool=false,relaxation:float=0.,diagonals:bool=false)->bool:
	if not is_finite(relaxation) or (relaxation!=0. and (relaxation<1. or relaxation>1.95)):return false
	# Force prediction, contact and displacement share acceptance. The fluid step
	# is NOT committed here; the caller must not treat this as a coupled tick.
	if not gravity.is_finite() or gravity.length()>.01 or (use_fluid_impulse and dt!=1.):return false
	if not grains_enabled or grain_motion_enabled or not is_finite(dt) or dt<=0. or dt>1. or sweeps<1 or sweeps>128 or not is_finite(friction) or friction<0. or friction>1.:return false
	if not initialize_displacement():return false
	if use_fluid_impulse:
		# Velocities may have evolved from zero since initialization.
		var list:=rd.compute_list_begin();record_boundary_impulse(list,tick%2,true);rd.compute_list_end()
	if not record_grain_contact_impulses(sweeps,friction,dt,true,gravity,use_fluid_impulse,relaxation,diagonals):return false
	if displacement_joint_sets.is_empty():
		for parity in range(2):
			displacement_joint_sets.append(uniform_set([phase[parity],distributions[parity],materials,mass_residual,boundary_velocity,grain_offset,displacement_scratch[0],displacement_scratch[1],displacement_scratch[2],displacement_status,contact_velocity,contact_status,contact_candidate_reaction,contact_reaction,phase[parity],distributions[parity],mass_residual,displacement_status],displacement_shader))
	return dispatch_displacement(dt,true)

func record_coupled_step(gravity:Vector2=Vector2(0,.00002),sigma:float=.01,sweeps:int=32,friction:float=.5,relaxation:float=0.,diagonals:bool=false)->bool:
	if not is_finite(grain_wetting_cosine) or absf(grain_wetting_cosine)>.95 or (grain_wetting_cosine!=0. and not interface_stress_enabled):return false
	if not is_finite(relaxation) or (relaxation!=0. and (relaxation<1. or relaxation>1.95)):return false
	# Experimental dt=1 joint fluid/grain transaction. CPU tick stays the parity
	# anchor; coupled_clock counts accepted lattice steps entirely on the GPU.
	if not grains_enabled or grain_motion_enabled or not gravity.is_finite() or gravity.length()>.01 or not is_finite(sigma) or sigma<0. or sigma>.1 or sweeps<1 or sweeps>128 or not is_finite(friction) or friction<0. or friction>1. or load_factor!=0.:return false
	if not initialize_displacement():return false
	if interface_stress_enabled and not initialize_interface_stress():return false
	var list:=rd.compute_list_begin()
	if interface_stress_enabled:record_interface_stress(list,tick%2,sigma)
	record_boundary_impulse(list,tick%2,true,interface_stress_enabled);rd.compute_list_end()
	if not record_grain_contact_impulses(sweeps,friction,1.,true,gravity,true,relaxation,diagonals):return false
	if local_displacement_geometry_enabled and not record_grain_volume_flux(1.):return false
	if coupled_sets.is_empty():
		var c:=buffer(side*side*4);var f:=buffer(side*side*36);var carry:=buffer(side*side*4)
		coupled_candidate_phase=c
		var u:=buffer(side*side*8);var flux:=buffer(side*side*8);var capacity:=buffer(side*side*8)
		var zero:=PackedByteArray();zero.resize(4);coupled_clock=buffer(4,zero)
		for parity in range(2):
			coupled_sets.append(uniform_set([phase[parity],distributions[parity],materials,mass_residual,boundary_velocity,grain_offset,displacement_scratch[0],displacement_scratch[1],displacement_scratch[2],displacement_status,contact_velocity,contact_status,contact_candidate_reaction,contact_reaction,c,f,carry,coupled_clock],displacement_shader))
			coupled_momentum_sets.append(uniform_set([phase[parity],distributions[parity],f,u,materials,loads,boundary_velocity,carry,interface_force if interface_stress_enabled else velocity],shaders[0]))
			coupled_transport_sets.append(uniform_set([phase[parity],c,flux,capacity,materials,u],shaders[1]))
	list=rd.compute_list_begin()
	var push:=PackedByteArray();push.resize(32);push.encode_u32(0,side);push.encode_u32(4,4)
	rd.compute_list_bind_compute_pipeline(list,displacement_pipeline);rd.compute_list_bind_uniform_set(list,coupled_sets[tick%2],0)
	rd.compute_list_set_push_constant(list,push.slice(0,16),16);rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	push.fill(0);push.encode_u32(0,side);push.encode_float(4,.9);push.encode_float(8,sigma);push.encode_float(12,4.)
	push.encode_float(16,gravity.x);push.encode_float(20,gravity.y);push.encode_u32(28,3 if interface_stress_enabled else 1)
	rd.compute_list_bind_compute_pipeline(list,pipelines[0]);rd.compute_list_bind_uniform_set(list,coupled_momentum_sets[tick%2],0)
	rd.compute_list_set_push_constant(list,push,32);rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	rd.compute_list_bind_compute_pipeline(list,pipelines[1]);rd.compute_list_bind_uniform_set(list,coupled_transport_sets[tick%2],0)
	for mode in range(3):
		push.fill(0);push.encode_u32(0,side);push.encode_u32(4,mode);push.encode_float(8,1.);push.encode_float(12,.02);push.encode_float(16,4.)
		push.encode_float(28,grain_wetting_cosine)
		rd.compute_list_set_push_constant(list,push,32);rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	rd.compute_list_end()
	return dispatch_displacement(1.,true,true)

static func contact_fields(n:int,bed_rows:int,has_gas:bool=true)->Dictionary:
	# Reproducible loaded-interface scene shared by the host and contact checks.
	var gas:=PackedFloat32Array();gas.resize(n*n)
	var walls:=PackedInt32Array();walls.resize(n*n)
	var center:=Vector2.ONE*(n-1)*.5
	for y in range(n):
		for x in range(n):
			var i:=y*n+x
			if Vector2(x,y).distance_to(center)>=n*.5-2.:walls[i]=1;continue
			if x>=int(n*.34375) and x<int(n*.65625) and y>=int(n*.3125)-bed_rows and y<int(n*.3125):
				walls[i]=2+(x+y)%3;continue
			if has_gas:gas[i]=.5*(1.-tanh(.5*(Vector2(x,y).distance_to(Vector2(center.x,n*.53125))-n*.1640625)))
	return {"gas":gas,"walls":walls}

static func sandscape_fields(n:int,seed_value:int)->Dictionary:
	# Seeded physical initial conditions only. No deposit silhouette is generated.
	var fields:=initial_fields(n,seed_value,true)
	var bubbles:Array[Vector3]=[];var cursor:=0.
	for k in range(9):
		var h:int=preload("res://src/randomness_manager.gd").hash32(seed_value^(k*747796405)^0x65a49f31)
		var radius:=n*(.032+.012*float(h&65535)/65535.)
		var gap:=n*(.012+.012*float((h>>16)&255)/255.)
		var y:=n*(.50+.016*(float((h>>24)&255)/255.-.5))
		bubbles.append(Vector3(cursor+radius,y,radius));cursor+=2.*radius
		if k<8:cursor+=gap
	var scale_factor:=minf(1.,n*.88/cursor)
	var left:=(n-1-cursor*scale_factor)*.5
	for k in range(bubbles.size()):
		bubbles[k].x=left+bubbles[k].x*scale_factor;bubbles[k].z*=scale_factor
	var gas:=PackedFloat32Array();gas.resize(n*n)
	for y in range(n):
		for x in range(n):
			var i:=y*n+x
			if fields.walls[i]!=0:continue
			var liquid:=1.
			for bubble in bubbles:
				liquid*=1.-.5*(1.-tanh(.5*(Vector2(x,y).distance_to(Vector2(bubble.x,bubble.y))-bubble.z)))
			gas[i]=1.-liquid
	fields.gas=gas;return fields

static func initial_fields(n:int,seed_value:int,with_sand:bool=false,bubble_barrier:bool=false,barrier_air_scale:float=1.)->Dictionary:
	if bubble_barrier:
		# New-world fixture only. Reuse the baseline grains exactly for a release comparison.
		var fields:=initial_fields(n,seed_value,with_sand,false)
		var fraction:=PackedFloat32Array();fraction.resize(n*n)
		var origin:=Vector2.ONE*(n-1)*0.5
		var bubbles:Array[Vector2]=[]
		for k in range(7):
			var h:=preload("res://src/randomness_manager.gd").hash32(seed_value^(k*747796405))
			bubbles.append(origin+Vector2((k-3)*n*.14,(int(h%7)-3)*n*.002))
		for y in range(n):
			for x in range(n):
				var i:=y*n+x
				if fields.walls[i]!=0:continue
				var liquid:=1.
				for bubble in bubbles:liquid*=1.-.5*(1.-tanh(.5*(Vector2(x,y).distance_to(bubble)-n*.0395*barrier_air_scale)))
				fraction[i]=1.-liquid
		fields.gas=fraction;return fields
	var gas:=PackedFloat32Array();gas.resize(n*n)
	var walls:=PackedInt32Array();walls.resize(n*n)
	var center:=Vector2.ONE*(n-1)*0.5
	var shift:=float(seed_value%17-8)*0.001*n
	var centers:Array[Vector2]=[center+Vector2(-0.10*n,0.16*n+shift),center+Vector2(0.12*n,0.05*n-shift)]
	for y in range(n):
		for x in range(n):
			var point:=Vector2(x,y);var i:=y*n+x
			if point.distance_to(center)>=n*0.5-2.:walls[i]=1;continue
			var liquid:=1.
			for bubble in centers:
				var fraction:=0.5*(1.-tanh(0.5*(point.distance_to(bubble)-n*0.075)))
				liquid*=1.-fraction
			gas[i]=1.-liquid
			if with_sand and y>n*.20 and y<n*.40 and gas[i]<1e-8:
				var h:int=preload("res://src/randomness_manager.gd").hash32(seed_value^i)
				if h%100<65:walls[i]=2+(int(y/4)+h%2)%3;gas[i]=0.
	return {"gas":gas,"walls":walls}

func buffer(bytes:int,data:PackedByteArray=PackedByteArray())->RID:
	var rid:=rd.storage_buffer_create(bytes,data);resources.append(rid);return rid

func uniform_set(ids:Array[RID],shader:RID)->RID:
	var uniforms:Array[RDUniform]=[]
	for b in range(ids.size()):
		var u:=RDUniform.new();u.binding=b;u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.add_id(ids[b]);uniforms.append(u)
	var rid:=rd.uniform_set_create(uniforms,shader,0);resources.append(rid);return rid

func initialize(device:RenderingDevice,n:int,initial:PackedFloat32Array,walls:PackedInt32Array,initial_velocity:PackedVector2Array=PackedVector2Array(),with_sand:bool=false,seed_value:int=0,wall_velocity:PackedVector2Array=PackedVector2Array())->bool:
	rd=device;side=n;grains_enabled=with_sand;grain_seed=seed_value
	if rd==null or initial.size()!=n*n or walls.size()!=n*n:return false
	if not initial_velocity.is_empty() and initial_velocity.size()!=n*n:return false
	for value in initial_velocity:
		if not value.is_finite() or value.length()>0.1:return false
	if not wall_velocity.is_empty() and wall_velocity.size()!=n*n:return false
	for i in range(wall_velocity.size()):
		if not wall_velocity[i].is_finite() or wall_velocity[i].length()>0.1:return false
		if walls[i]==0 and wall_velocity[i]!=Vector2.ZERO:return false
		boundary_motion_enabled=boundary_motion_enabled or wall_velocity[i]!=Vector2.ZERO
	# Geometry changes need additional covered/uncovered-cell impulses, not yet implemented.
	if boundary_motion_enabled and with_sand and grain_motion_enabled:return false
	var boundary_bytes:=PackedByteArray()
	if wall_velocity.is_empty():boundary_bytes.resize(n*n*8)
	else:boundary_bytes=wall_velocity.to_byte_array()
	boundary_velocity=buffer(n*n*8,boundary_bytes)
	var zero_residual:=PackedByteArray();zero_residual.resize(n*n*4);mass_residual=buffer(n*n*4,zero_residual)
	phase=[buffer(n*n*4,initial.to_byte_array()),buffer(n*n*4)]
	var weights:=PackedFloat32Array([4./9.,1./9.,1./9.,1./9.,1./9.,1./36.,1./36.,1./36.,1./36.])
	var f:=PackedFloat32Array();f.resize(n*n*9)
	var directions:Array[Vector2]=[Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(-1,0),Vector2(0,-1),Vector2(1,1),Vector2(-1,1),Vector2(-1,-1),Vector2(1,-1)]
	for i in range(n*n):
		var u:=Vector2.ZERO if initial_velocity.is_empty() or walls[i]!=0 else initial_velocity[i]
		for q in range(9):
			var eu:=directions[q].dot(u)
			f[i*9+q]=weights[q]*(1.+3.*eu+4.5*eu*eu-1.5*u.length_squared())
	distributions=[buffer(f.size()*4,f.to_byte_array()),buffer(f.size()*4)]
	velocity=buffer(n*n*8)
	var flux:=buffer(n*n*8);var capacity:=buffer(n*n*8);var wall:=buffer(n*n*4,walls.to_byte_array())
	materials=wall
	var zero_load:=PackedByteArray();zero_load.resize(n*n*4);loads=buffer(n*n*4,zero_load)
	var paths:Array[String]=["res://shaders/phase_momentum.glsl","res://shaders/phase_transport.glsl"]
	if grains_enabled:
		paths.append("res://shaders/phase_grains.glsl");paths.append("res://shaders/grain_traction.glsl");paths.append("res://shaders/grain_load.glsl")
		traction=buffer(n*n*8)
	for path in paths:
		var shader:=Compiler.compile_shader(rd,path)
		if not shader.is_valid():return false
		shaders.append(shader);pipelines.append(rd.compute_pipeline_create(shader))
	for parity in range(2):
		momentum_sets.append(uniform_set([phase[parity],distributions[parity],distributions[1-parity],velocity,wall,loads,boundary_velocity,mass_residual,velocity],shaders[0]))
		phase_sets.append(uniform_set([phase[parity],phase[1-parity],flux,capacity,wall,velocity],shaders[1]))
		if grains_enabled:
			grain_sets.append(uniform_set([phase[parity],distributions[parity],wall,traction,mass_residual],shaders[2]))
			traction_sets.append(uniform_set([distributions[parity],wall,traction,boundary_velocity,velocity],shaders[3]))
	if grains_enabled:load_set=uniform_set([materials,loads],shaders[4])
	return true

func record_load(list:int,gravity:Vector2)->void:
	rd.compute_list_bind_compute_pipeline(list,pipelines[4]);rd.compute_list_bind_uniform_set(list,load_set,0)
	var tiles:=ceili(side/8.)
	for wave in range(2*tiles-1):
		var p:=PackedByteArray();p.resize(16);p.encode_u32(0,side);p.encode_u32(4,wave);p.encode_float(8,gravity.x);p.encode_float(12,gravity.y)
		rd.compute_list_set_push_constant(list,p,16);rd.compute_list_dispatch(list,tiles,1,1);rd.compute_list_add_barrier(list)

func advance(count:int,gravity:Vector2=Vector2(0,0.0001),sigma:float=0.002)->void:
	# Coverage-change impulses and moving-interface work are not coupled yet.
	assert(not grain_offset.is_valid())
	assert(count>=0 and count<=128)
	assert(grain_drag_divisor in [1,16,64,256])
	assert(not (boundary_motion_enabled and grains_enabled and grain_motion_enabled))
	if grain_energy_enabled:
		assert(grains_enabled and voxel_interface_enabled)
		if not initialize_energy_exchange():return
		if grain_buoyant_enabled and buoyant_exchange==null:
			buoyant_exchange=preload("res://src/buoyant_loop_transaction.gd").new()
			if not buoyant_exchange.initialize(rd,self,PackedInt32Array(),true):buoyant_exchange.release();buoyant_exchange=null;return
		if grain_collective_enabled and not initialize_collective_exchange():return
	if voxel_interface_enabled:
		assert(grains_enabled and grain_traction_enabled and is_finite(grain_wetting_cosine) and absf(grain_wetting_cosine)<=.95)
		if voxel_momentum_sets.is_empty():
			var initialized_interface:=initialize_interface_stress()
			assert(initialized_interface)
			if not initialized_interface:return
			for parity in range(2):
				voxel_momentum_sets.append(uniform_set([phase[parity],distributions[parity],distributions[1-parity],velocity,materials,loads,boundary_velocity,mass_residual,interface_force],shaders[0]))
	if grains_enabled and not grain_traction_enabled:
		rd.buffer_clear(traction,0,side*side*8)
	var list:=rd.compute_list_begin()
	for _i in range(count):
		if voxel_interface_enabled:record_interface_stress(list,tick%2,sigma)
		if grains_enabled and load_factor!=0.:record_load(list,gravity)
		var p:=PackedByteArray();p.resize(32)
		if grains_enabled and grain_motion_enabled and grain_traction_enabled and not grain_energy_enabled:
			# Sample incoming populations on the geometry used by this fluid step.
			# The derived grain force travels with its grain through both partitions.
			rd.compute_list_bind_compute_pipeline(list,pipelines[3]);rd.compute_list_bind_uniform_set(list,interface_traction_sets[tick%2] if voxel_interface_enabled else traction_sets[tick%2],0)
			p.encode_u32(8,1 if voxel_interface_enabled else 0)
			p.encode_u32(0,side);rd.compute_list_set_push_constant(list,p,16)
			rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
		p.encode_u32(0,side);p.encode_float(4,0.9);p.encode_float(8,sigma);p.encode_float(12,4.)
		p.encode_float(16,gravity.x);p.encode_float(20,gravity.y);p.encode_float(24,load_factor)
		p.encode_u32(28,(1 if boundary_motion_enabled else 0)|(2 if voxel_interface_enabled else 0))
		rd.compute_list_bind_compute_pipeline(list,pipelines[0]);rd.compute_list_bind_uniform_set(list,voxel_momentum_sets[tick%2] if voxel_interface_enabled else momentum_sets[tick%2],0)
		rd.compute_list_set_push_constant(list,p,32);rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
		rd.compute_list_bind_compute_pipeline(list,pipelines[1]);rd.compute_list_bind_uniform_set(list,phase_sets[tick%2],0)
		for mode in range(3):
			p.fill(0);p.encode_u32(0,side);p.encode_u32(4,mode);p.encode_float(8,1.);p.encode_float(12,0.02);p.encode_float(16,4.)
			p.encode_float(28,grain_wetting_cosine if voxel_interface_enabled else 0.)
			rd.compute_list_set_push_constant(list,p,32);rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
		if grains_enabled and grain_motion_enabled:
			if grain_energy_enabled:
				if grain_buoyant_enabled:buoyant_exchange.record(list,self,gravity,(tick+1)%2)
				if grain_collective_enabled:record_collective_exchange(list,(tick+1)%2,gravity,sigma)
				record_energy_exchange(list,(tick+1)%2,gravity,sigma)
				tick+=1
				continue
			var direction:=gravity.normalized()*32767.
			for partition in range(2):
				rd.compute_list_bind_compute_pipeline(list,pipelines[2]);rd.compute_list_bind_uniform_set(list,grain_sets[(tick+1)%2],0)
				p.fill(0);p.encode_u32(0,side);p.encode_u32(4,grain_seed);p.encode_u32(8,tick);p.encode_u32(12,partition)
				p.encode_s32(16,roundi(direction.x));p.encode_s32(20,roundi(direction.y));p.encode_float(24,gravity.length())
				p.encode_u32(28,grain_drag_divisor)
				rd.compute_list_set_push_constant(list,p,32);rd.compute_list_dispatch(list,ceili((side/2.+1.)/8.),ceili((side/2.+1.)/8.),1);rd.compute_list_add_barrier(list)
		tick+=1
	rd.compute_list_end()

func initialize_energy_exchange()->bool:
	if grain_energy_pipeline.is_valid():return true
	var shader:=Compiler.compile_shader(rd,"res://shaders/grain_energy_exchange.glsl")
	if not shader.is_valid():return false
	shaders.append(shader);grain_energy_pipeline=rd.compute_pipeline_create(shader);pipelines.append(grain_energy_pipeline)
	var stamps:=PackedInt32Array();stamps.resize(side*side);stamps.fill(-1)
	grain_energy_stamp=buffer(side*side*4,stamps.to_byte_array())
	for parity in range(2):
		grain_energy_sets.append(uniform_set([phase[parity],materials,distributions[parity],mass_residual,grain_energy_stamp],shader))
	return true

func validate_energy_parameters()->void:
	assert(is_finite(grain_weight_scale) and grain_weight_scale>0. and grain_weight_scale<=4.)
	assert(is_finite(grain_mobility_scale) and grain_mobility_scale>0. and grain_mobility_scale<=4.)

func record_energy_exchange(list:int,parity:int,gravity:Vector2,sigma:float)->void:
	validate_energy_parameters()
	rd.compute_list_bind_compute_pipeline(list,grain_energy_pipeline)
	rd.compute_list_bind_uniform_set(list,grain_energy_sets[parity],0)
	var push:=PackedByteArray();push.resize(48)
	push.encode_u32(0,side);push.encode_float(4,sigma);push.encode_float(8,4.);push.encode_float(12,grain_wetting_cosine)
	push.encode_u32(16,tick);push.encode_u32(20,grain_seed);push.encode_u32(28,grain_drag_divisor)
	push.encode_float(32,gravity.x);push.encode_float(36,gravity.y)
	push.encode_float(40,grain_weight_scale);push.encode_float(44,grain_mobility_scale)
	for phase_index in range(16):
		push.encode_u32(24,(phase_index+tick)%16)
		rd.compute_list_set_push_constant(list,push,48)
		rd.compute_list_dispatch(list,ceili(side/32.),ceili(side/32.),1);rd.compute_list_add_barrier(list)

func initialize_collective_exchange()->bool:
	if grain_collective_pipeline.is_valid():return grain_collective_activity_pipeline.is_valid() and grain_collective_dispatch.is_valid() and grain_collective_activity_set.is_valid()
	if not initialize_energy_exchange():return false
	var shader:=Compiler.compile_shader(rd,"res://shaders/grain_collective_exchange.glsl")
	if not shader.is_valid():return false
	shaders.append(shader);grain_collective_pipeline=rd.compute_pipeline_create(shader);pipelines.append(grain_collective_pipeline)
	for parity in range(2):
		grain_collective_sets.append(uniform_set([phase[parity],materials,distributions[parity],mass_residual,grain_energy_stamp],shader))
	var activity_shader:=Compiler.compile_shader(rd,"res://shaders/grain_collective_activity.glsl")
	if not activity_shader.is_valid():return false
	shaders.append(activity_shader);grain_collective_activity_pipeline=rd.compute_pipeline_create(activity_shader);pipelines.append(grain_collective_activity_pipeline)
	var zero:=PackedByteArray();zero.resize(16)
	grain_collective_dispatch=rd.storage_buffer_create(16,zero,RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	if not grain_collective_dispatch.is_valid():return false
	resources.append(grain_collective_dispatch)
	grain_collective_activity_set=uniform_set([materials,grain_energy_stamp,grain_collective_dispatch],activity_shader)
	return grain_collective_activity_set.is_valid()

func record_collective_exchange(list:int,parity:int,gravity:Vector2,sigma:float)->void:
	validate_energy_parameters()
	if grain_collective_gate_enabled:
		rd.compute_list_bind_compute_pipeline(list,grain_collective_activity_pipeline)
		rd.compute_list_bind_uniform_set(list,grain_collective_activity_set,0)
		var activity:=PackedByteArray();activity.resize(32)
		activity.encode_u32(0,side);activity.encode_u32(4,tick);activity.encode_float(16,gravity.x);activity.encode_float(20,gravity.y)
		rd.compute_list_set_push_constant(list,activity,32);rd.compute_list_dispatch(list,1,1,1);rd.compute_list_add_barrier(list)
		activity.encode_u32(8,1);rd.compute_list_set_push_constant(list,activity,32)
		rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	rd.compute_list_bind_compute_pipeline(list,grain_collective_pipeline)
	rd.compute_list_bind_uniform_set(list,grain_collective_sets[parity],0)
	var push:=PackedByteArray();push.resize(48)
	push.encode_u32(0,side);push.encode_float(4,sigma);push.encode_float(8,4.);push.encode_float(12,grain_wetting_cosine)
	push.encode_u32(16,tick);push.encode_u32(20,grain_seed);push.encode_u32(28,grain_drag_divisor)
	push.encode_float(32,gravity.x);push.encode_float(36,gravity.y)
	push.encode_float(40,grain_weight_scale);push.encode_float(44,grain_mobility_scale)
	for phase_index in range(48):
		push.encode_u32(24,(phase_index+tick)%48)
		rd.compute_list_set_push_constant(list,push,48)
		if grain_collective_gate_enabled:rd.compute_list_dispatch_indirect(list,grain_collective_dispatch,0)
		else:rd.compute_list_dispatch(list,ceili(side/32.),ceili(side/96.),1)
		rd.compute_list_add_barrier(list)

func record_grain_volume_flux(dt:float=1.)->bool:
	# Derive local displaced volume from the SAME candidate positions as the
	# joint transaction. Fluid transport must consume this before replacing remap.
	if not contact_velocity.is_valid() or not grain_offset.is_valid() or not is_finite(dt) or dt<=0. or dt>1.:return false
	if not volume_pipeline.is_valid():
		var shader:=Compiler.compile_shader(rd,"res://shaders/grain_volume_flux.glsl")
		if not shader.is_valid():return false
		shaders.append(shader);volume_pipeline=rd.compute_pipeline_create(shader);pipelines.append(volume_pipeline)
		volume_geometry=buffer(side*side*16)
		volume_aperture=buffer(side*side*8)
		volume_set=uniform_set([materials,grain_offset,contact_velocity,volume_geometry,contact_status,volume_aperture],shader)
	var list:=rd.compute_list_begin();var push:=PackedByteArray();push.resize(16);push.encode_u32(0,side);push.encode_float(4,dt)
	rd.compute_list_bind_compute_pipeline(list,volume_pipeline);rd.compute_list_bind_uniform_set(list,volume_set,0)
	rd.compute_list_set_push_constant(list,push,16);rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	rd.compute_list_end();return true

func record_local_drainage(iterations:int=128,tolerance:float=1e-6)->bool:
	# Candidate-only projection. Do not feed it to the full-cell LBM/remap.
	if not volume_geometry.is_valid() or iterations<1 or iterations>128 or not is_finite(tolerance) or tolerance<=0. or tolerance>1e-4:return false
	if not drainage_pipeline.is_valid():
		var shader:=Compiler.compile_shader(rd,"res://shaders/local_drainage.glsl")
		if not shader.is_valid():return false
		shaders.append(shader);drainage_pipeline=rd.compute_pipeline_create(shader);pipelines.append(drainage_pipeline)
		drainage_flux=buffer(side*side*8);drainage_status=buffer(16);drainage_state=buffer(side*side*16)
		drainage_set=uniform_set([volume_geometry,volume_aperture,drainage_state,buffer(side*side*4),buffer(ceili(side*side/64.)*8),buffer(16),drainage_flux,drainage_status,contact_status],shader)
	var list:=rd.compute_list_begin();var push:=PackedByteArray();push.resize(16)
	push.encode_u32(0,side);push.encode_float(8,tolerance);push.encode_u32(12,ceili(side*side/64.))
	rd.compute_list_bind_compute_pipeline(list,drainage_pipeline);rd.compute_list_bind_uniform_set(list,drainage_set,0)
	var modes:Array[int]=[9,0,1]
	for iteration in range(iterations):modes.append_array([2,3,4,5,6])
	# Explicit pressure gauge for reaction comparisons. No-flow solid cells
	# remain zero. Disconnected fluid components need a separate gauge audit.
	modes.append_array([12,13,14,7,8])
	for mode in modes:
		push.encode_u32(4,mode);rd.compute_list_set_push_constant(list,push,16)
		rd.compute_list_dispatch(list,1 if mode in [1,3,5,8,9,13] else ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	rd.compute_list_end();return true

func record_drainage_reaction(dt:float=1.)->bool:
	if not drainage_state.is_valid() or not is_finite(dt) or dt<=0. or dt>1.:return false
	if not drainage_reaction_pipeline.is_valid():
		var shader:=Compiler.compile_shader(rd,"res://shaders/drainage_reaction.glsl")
		if not shader.is_valid():return false
		shaders.append(shader);drainage_reaction_pipeline=rd.compute_pipeline_create(shader);pipelines.append(drainage_reaction_pipeline)
		drainage_reaction=buffer(side*side*8)
		drainage_reaction_set=uniform_set([materials,grain_offset,contact_velocity,drainage_state,drainage_status,drainage_reaction],shader)
	var list:=rd.compute_list_begin();var push:=PackedByteArray();push.resize(16);push.encode_u32(0,side);push.encode_float(4,dt)
	rd.compute_list_bind_compute_pipeline(list,drainage_reaction_pipeline);rd.compute_list_bind_uniform_set(list,drainage_reaction_set,0)
	rd.compute_list_set_push_constant(list,push,16);rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	rd.compute_list_end();return true

func record_gas_transport(input_gas:RID,iterations:int=64,dt:float=1.,tolerance:float=1e-7)->bool:
	# Input is gas VOLUME, not the legacy full-cell phase fraction. The stable
	# input RID belongs to this RD; only candidates and status are written.
	if not drainage_flux.is_valid() or not input_gas.is_valid() or iterations<1 or iterations>128 or not is_finite(dt) or dt<=0. or dt>1. or not is_finite(tolerance) or tolerance<=0. or tolerance>1e-4:return false
	if not gas_transport_sets.is_empty() and input_gas!=gas_transport_input:return false
	if not gas_transport_pipeline.is_valid():
		var shader:=Compiler.compile_shader(rd,"res://shaders/local_gas_transport.glsl")
		if not shader.is_valid():return false
		shaders.append(shader);gas_transport_pipeline=rd.compute_pipeline_create(shader);pipelines.append(gas_transport_pipeline)
		gas_transport_input=input_gas;gas_transport_candidate=buffer(side*side*4);gas_transport_status=buffer(24)
		var fractions:Array[RID]=[buffer(side*side*4),buffer(side*side*4)];var partial:=buffer(ceili(side*side/64.)*16)
		for parity in range(2):gas_transport_sets.append(uniform_set([volume_geometry,drainage_flux,input_gas,fractions[parity],fractions[1-parity],gas_transport_candidate,partial,gas_transport_status,drainage_status,contact_status],shader))
	var list:=rd.compute_list_begin();var push:=PackedByteArray();push.resize(16)
	push.encode_u32(0,side);push.encode_float(8,dt);push.encode_float(12,tolerance)
	rd.compute_list_bind_compute_pipeline(list,gas_transport_pipeline)
	var passes:Array[Vector2i]=[Vector2i(4,0),Vector2i(0,0)]
	for iteration in range(iterations):passes.append(Vector2i(1,iteration%2))
	passes.append_array([Vector2i(2,iterations%2),Vector2i(3,iterations%2)])
	for pass_info in passes:
		push.encode_u32(4,pass_info.x);rd.compute_list_bind_uniform_set(list,gas_transport_sets[pass_info.y],0)
		rd.compute_list_set_push_constant(list,push,16);rd.compute_list_dispatch(list,1 if pass_info.x in [3,4] else ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	rd.compute_list_end();return true

func initialize_interface_stress()->bool:
	if interface_pipeline.is_valid():return true
	# Select before the first coupled transaction; descriptors must stay coherent.
	if not coupled_sets.is_empty():return false
	var shader:=Compiler.compile_shader(rd,"res://shaders/interface_stress.glsl")
	if not shader.is_valid():return false
	shaders.append(shader);interface_pipeline=rd.compute_pipeline_create(shader);pipelines.append(interface_pipeline)
	interface_force=buffer(side*side*8)
	for parity in range(2):
		interface_sets.append(uniform_set([phase[parity],materials,interface_force],shader))
		interface_traction_sets.append(uniform_set([distributions[parity],materials,traction,boundary_velocity,interface_force],shaders[3]))
	return true

func record_interface_stress(list:int,parity:int,sigma:float)->void:
	var push:=PackedByteArray();push.resize(16);push.encode_u32(0,side);push.encode_float(4,sigma);push.encode_float(8,4.)
	push.encode_float(12,grain_wetting_cosine)
	rd.compute_list_bind_compute_pipeline(list,interface_pipeline);rd.compute_list_bind_uniform_set(list,interface_sets[parity],0)
	rd.compute_list_set_push_constant(list,push,16);rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)

func record_boundary_impulse(list:int,parity:int,moving:bool=false,with_interface:bool=false)->void:
	# Record BEFORE the matching fluid step. The result includes ambient pressure
	# on walls and grains; it is not the post-step gauge-subtracted hop estimator.
	assert(grains_enabled and parity in [0,1])
	var push:=PackedByteArray();push.resize(16);push.encode_u32(0,side)
	push.encode_u32(4,2 if (boundary_motion_enabled or moving) else 1)
	push.encode_u32(8,1 if with_interface else 0)
	rd.compute_list_bind_compute_pipeline(list,pipelines[3])
	rd.compute_list_bind_uniform_set(list,interface_traction_sets[parity] if with_interface else traction_sets[parity],0)
	rd.compute_list_set_push_constant(list,push,16)
	rd.compute_list_dispatch(list,ceili(side*side/64.),1,1)
	rd.compute_list_add_barrier(list)

func record_grain_contact_impulses(sweeps:int=8,friction:float=.5,dt:float=1.,defer_commit:bool=false,gravity:Vector2=Vector2.ZERO,use_fluid_impulse:bool=false,relaxation:float=0.,diagonals:bool=false)->bool:
	if not is_finite(relaxation) or (relaxation!=0. and (relaxation<1. or relaxation>1.95)):return false
	# Foundation for the moving-grain path. Do not mix physical velocity contacts
	# with stochastic displacement. No caller may treat this as a full timestep.
	# True means commands were queued, not accepted. contact_status[2] is the GPU
	# acceptance flag. Failed candidates leave live velocity unchanged and publish
	# zero reaction; scratch velocity/reaction remain available for diagnostics.
	if not gravity.is_finite() or gravity.length()>.01 or (use_fluid_impulse and dt!=1.):return false
	if not is_finite(dt) or dt<=0. or dt>1. or not grains_enabled or grain_motion_enabled or sweeps<1 or sweeps>128 or not is_finite(friction) or friction<0. or friction>1.:return false
	if not contact_pipeline.is_valid():
		var shader:=Compiler.compile_shader(rd,"res://shaders/grain_contact_impulse.glsl")
		if not shader.is_valid():return false
		contact_shader=shader;shaders.append(shader);contact_pipeline=rd.compute_pipeline_create(shader);pipelines.append(contact_pipeline)
		contact_reaction=buffer(side*side*8)
		contact_velocity=buffer(side*side*8);contact_candidate_reaction=buffer(side*side*8);contact_status=buffer(16);contact_edges=buffer(side*side*32);contact_edge_remainder=buffer(side*side*32);contact_diagonal_axes=buffer(side*side*8)
		var zero:=PackedByteArray();zero.resize(side*side*8)
		contact_offset=grain_offset if grain_offset.is_valid() else buffer(zero.size(),zero)
		contact_set=uniform_set([contact_velocity,materials,contact_candidate_reaction,boundary_velocity,contact_status,contact_reaction,contact_offset,traction,contact_edges,contact_edge_remainder,contact_diagonal_axes],shader)
	if grain_offset.is_valid() and contact_offset!=grain_offset:
		contact_offset=grain_offset
		contact_set=uniform_set([contact_velocity,materials,contact_candidate_reaction,boundary_velocity,contact_status,contact_reaction,contact_offset,traction,contact_edges,contact_edge_remainder,contact_diagonal_axes],contact_shader)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,contact_pipeline);rd.compute_list_bind_uniform_set(list,contact_set,0)
	var push:=PackedByteArray();push.resize(48);push.encode_u32(0,side);push.encode_float(12,friction);push.encode_float(16,dt);push.encode_float(20,gravity.x);push.encode_float(24,gravity.y);push.encode_u32(28,1 if use_fluid_impulse else 0);push.encode_float(32,relaxation);push.encode_u32(36,1 if diagonals else 0)
	rd.compute_list_set_push_constant(list,push,48);rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	for _sweep in range(sweeps+(64 if diagonals else 0)):
		if diagonals and _sweep==sweeps:
			push.encode_u32(4,5);rd.compute_list_set_push_constant(list,push,48)
			rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
		# Finish with unrelaxed projections to damp high-frequency/roundoff modes.
		push.encode_float(32,1. if relaxation>0. and ((_sweep>=sweeps-8 and _sweep<sweeps) or _sweep>=sweeps+56) else relaxation)
		push.encode_u32(40,1 if _sweep>=sweeps else 0)
		for axis in range(4 if diagonals and _sweep>=sweeps else 2):
			for parity in range(2):
				push.encode_u32(4,axis+1 if axis<2 else axis+4);push.encode_u32(8,parity)
				rd.compute_list_set_push_constant(list,push,48);rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	# Validate the complete candidate before any live velocity is changed.
	for mode in ([3] if defer_commit else [3,4]):
		push.encode_u32(4,mode);rd.compute_list_set_push_constant(list,push,48)
		rd.compute_list_dispatch(list,ceili(side*side/64.),1,1);rd.compute_list_add_barrier(list)
	rd.compute_list_end();return true

func snapshot_bytes()->PackedByteArray:
	# Explicit checkpoint only, on the RD owning thread; never called per frame.
	var bytes:=rd.buffer_get_data(phase[tick%2])
	bytes.append_array(rd.buffer_get_data(distributions[tick%2]))
	bytes.append_array(rd.buffer_get_data(materials))
	bytes.append_array(rd.buffer_get_data(boundary_velocity))
	bytes.append_array(rd.buffer_get_data(mass_residual))
	# Include experimental positions instead of silently producing a lossy save.
	# The production session validator rejects this extended layout for now.
	if grain_offset.is_valid():bytes.append_array(rd.buffer_get_data(grain_offset))
	if coupled_clock.is_valid():bytes.append_array(rd.buffer_get_data(coupled_clock))
	return bytes

func energy_snapshot_bytes()->PackedByteArray:
	assert(grain_energy_enabled and grain_energy_stamp.is_valid() and not grain_offset.is_valid())
	var bytes:=snapshot_bytes();bytes.append_array(rd.buffer_get_data(grain_energy_stamp));return bytes

func restore_energy(device:RenderingDevice,data:Dictionary)->bool:
	# Called only after the versioned journal validates the complete payload.
	var n:=int(data.side);var cells:=n*n;var payload:PackedByteArray=data.bytes
	if payload.size()!=cells*60 or not resources.is_empty():return false
	grain_energy_enabled=true;voxel_interface_enabled=true
	grain_collective_enabled=data.collective_exchange
	grain_weight_scale=data.weight_scale;grain_mobility_scale=data.mobility_scale
	grain_wetting_cosine=data.wetting_cosine
	var core:=data.duplicate();core.bytes=payload.slice(0,cells*56)
	if not restore(device,core) or not initialize_energy_exchange():return false
	if grain_collective_enabled and not initialize_collective_exchange():return false
	rd.buffer_update(grain_energy_stamp,0,cells*4,payload.slice(cells*56))
	return true

func restore(device:RenderingDevice,data:Dictionary)->bool:
	var n:=int(data.side);var cells:=n*n;var bytes:PackedByteArray=data.bytes
	if bytes.size() not in [cells*52,cells*56] or not resources.is_empty():return false
	var gas:=bytes.slice(0,cells*4);var post:=bytes.slice(cells*4,cells*40)
	var m:=bytes.slice(cells*40,cells*44).to_int32_array()
	grain_drag_divisor=int(data.get("grain_drag_divisor",1))
	if not initialize(device,n,gas.to_float32_array(),m,PackedVector2Array(),data.with_sand,int(data.seed)):return false
	tick=int(data.tick)
	for parity in range(2):
		rd.buffer_update(phase[parity],0,gas.size(),gas)
		rd.buffer_update(distributions[parity],0,post.size(),post)
	if bytes.size()==cells*56:rd.buffer_update(mass_residual,0,cells*4,bytes.slice(cells*52))
	return true

func release()->void:
	if buoyant_exchange!=null:buoyant_exchange.release();buoyant_exchange=null
	for i in range(resources.size()-1,-1,-1):rd.free_rid(resources[i])
	for rid in pipelines:rd.free_rid(rid)
	for rid in shaders:rd.free_rid(rid)
	resources.clear();pipelines.clear();shaders.clear()
