extends SceneTree

const Physics = preload("res://src/physics_engine.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/phase-fixture.json"))
	var side:int=fixture.side
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var initial:=PackedFloat32Array(fixture.initial).to_byte_array()
	var walls:=PackedInt32Array(fixture.wall).to_byte_array()
	var buffers:Array[RID]=[rd.storage_buffer_create(initial.size(),initial),rd.storage_buffer_create(initial.size()),rd.storage_buffer_create(side*side*8),rd.storage_buffer_create(side*side*8),rd.storage_buffer_create(walls.size(),walls)]
	var velocities:=PackedFloat32Array()
	for i in range(side*side):velocities.append(0.04);velocities.append(-0.07)
	buffers.append(rd.storage_buffer_create(velocities.size()*4,velocities.to_byte_array()))
	var shader:=Physics.compile_shader(rd,"res://shaders/phase_transport.glsl")
	if not shader.is_valid():quit(1);return
	var pipeline:=rd.compute_pipeline_create(shader)
	var sets:Array[RID]=[]
	for phase in range(2):
		var uniforms:Array[RDUniform]=[]
		for binding in range(6):
			var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=binding
			u.add_id(buffers[(binding+phase)%2] if binding<2 else buffers[binding]);uniforms.append(u)
		sets.append(rd.uniform_set_create(uniforms,shader,0))
	var list:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	for tick in range(int(fixture.steps)):
		rd.compute_list_bind_uniform_set(list,sets[tick%2],0)
		for mode in range(3):
			var p:=PackedByteArray();p.resize(32)
			p.encode_u32(0,side);p.encode_u32(4,mode)
			p.encode_float(8,0.1);p.encode_float(12,0.02);p.encode_float(16,4.)
			p.encode_float(20,0.04);p.encode_float(24,-0.07)
			rd.compute_list_set_push_constant(list,p,32)
			rd.compute_list_dispatch(list,ceili(side*side/64.),1,1)
			rd.compute_list_add_barrier(list)
	rd.compute_list_end();rd.submit();rd.sync()
	var actual:=rd.buffer_get_data(buffers[int(fixture.steps)%2]).to_float32_array()
	var error:=0.;var total:=0.;var violations:=0
	for i in range(actual.size()):
		error=maxf(error,absf(actual[i]-float(fixture.expected[i])));total+=actual[i]
		if not is_finite(actual[i]) or actual[i]<-1e-6 or actual[i]>1.000001 or (fixture.wall[i]!=0 and actual[i]!=0):violations+=1
	var drift:=absf(total-float(fixture.mass))
	var report:Dictionary={"max_cpu_gpu_error":error,"mass_drift":drift,"violations":violations,"steps":fixture.steps,"side":side}
	var file:=FileAccess.open("res://reports/phase-gpu-validation.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("PHASE_TRANSPORT_RESULT ",report)
	for r in sets:rd.free_rid(r)
	for r in buffers:rd.free_rid(r)
	rd.free_rid(pipeline);rd.free_rid(shader);rd.free()
	quit(0 if error<2e-5 and drift<1e-4 and violations==0 else 1)
