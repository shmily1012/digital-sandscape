extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
const Compiler=preload("res://src/physics_engine.gd")
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func evaluate(rd:RenderingDevice,c:PackedFloat32Array,m:PackedInt32Array,n:int,cosine:float)->Dictionary:
	var owner:=Fluid.new();owner.rd=rd
	var phase:RID=owner.buffer(c.size()*4,c.to_byte_array())
	var material:RID=owner.buffer(m.size()*4,m.to_byte_array())
	var work:RID=owner.buffer(m.size()*16);var mask:RID=owner.buffer(m.size()*4)
	var shader:=Compiler.compile_shader(rd,"res://shaders/grain_interface_work.glsl")
	if not shader.is_valid():failures.append("Compile failed");return {}
	owner.shaders.append(shader)
	var pipeline:=rd.compute_pipeline_create(shader);owner.pipelines.append(pipeline)
	var uniforms:RID=owner.uniform_set([phase,material,work,mask],shader)
	var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniforms,0)
	var params:=PackedByteArray();params.resize(16);params.encode_u32(0,n);params.encode_float(4,.01);params.encode_float(8,4.);params.encode_float(12,cosine)
	rd.compute_list_set_push_constant(list,params,16);rd.compute_list_dispatch(list,ceili(n*n/64.),1,1);rd.compute_list_end();rd.submit();rd.sync()
	if rd.buffer_get_data(phase)!=c.to_byte_array() or rd.buffer_get_data(material)!=m.to_byte_array():failures.append("Input mutated")
	var result:Dictionary={"work":rd.buffer_get_data(work),"mask":rd.buffer_get_data(mask)}
	owner.release();return result
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://reports/grain-interface-work-fixture.json"))
	var max_error:=0.
	for case:Dictionary in fixtures:
		var result:=evaluate(rd,PackedFloat32Array(case.phase),PackedInt32Array(case.materials),int(case.side),float(case.cosine))
		if result.is_empty():quit(1);return
		var work:PackedFloat32Array=result.work.to_float32_array()
		for i in range(work.size()):
			if not is_finite(work[i]):failures.append("Nonfinite work")
			max_error=maxf(max_error,absf(work[i]-float(case.work[i])))
		if result.mask!=PackedInt32Array(case.mask).to_byte_array():failures.append("Validity mask")
	if max_error>1e-8:failures.append("CPU/GPU work mismatch")
	var c:=FileAccess.get_file_as_bytes("res://reports/phase-contact-bed-tick-10000.f32").to_float32_array()
	var m:=FileAccess.get_file_as_bytes("res://reports/phase-contact-bed-tick-10000.materials.u32").to_int32_array()
	if c.size()!=256*256 or m.size()!=c.size():failures.append("Missing window state")
	else:
		var result:=evaluate(rd,c,m,256,0.)
		for key in ["work","mask"]:
			var file:=FileAccess.open("res://reports/contact-interface-"+key+".bin",FileAccess.WRITE);file.store_buffer(result[key]);file.close()
	var report:Dictionary={"failures":failures,"max_cpu_gpu_error":max_error,"cases":fixtures.size(),"physical_acceptance":false,"scope":"Finite interface work only. No pressure work, movement, reaction or state commit."}
	var out:=FileAccess.open("res://reports/grain-interface-work-gpu.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	print("INTERFACE_WORK ",report);rd.free();quit(0 if failures.is_empty() else 1)
