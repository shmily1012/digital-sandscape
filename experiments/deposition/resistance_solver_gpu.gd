extends RefCounted
const Operator=preload("res://experiments/deposition/drainage_operator_gpu.gd")
const Physics=preload("res://src/physics_engine.gd")
var rd:RenderingDevice
var op:RefCounted
var shader:RID
var pipeline:RID
var uniforms:RID
var force:RID
var output:RID
var status:RID
func initialize(device:RenderingDevice,description:Dictionary)->bool:
 rd=device;op=Operator.new();op.pressure_backward_error=true
 if not op.initialize(rd,description):return false
 shader=Physics.compile_shader(rd,"res://experiments/deposition/resistance_solve.glsl")
 if not shader.is_valid():return false
 pipeline=rd.compute_pipeline_create(shader)
 var zero:=PackedByteArray();zero.resize(op.n*8);zero.fill(0)
 force=rd.storage_buffer_create(zero.size(),zero);output=rd.storage_buffer_create(zero.size(),zero);status=rd.storage_buffer_create(16)
 var refs:Array[RID]=[force,op.input_velocity(),op.output_force(),op.output_status(),output,status]
 var items:Array[RDUniform]=[]
 for i in range(refs.size()):
  var u:=RDUniform.new();u.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;u.binding=i;u.add_id(refs[i]);items.append(u)
 uniforms=rd.uniform_set_create(items,shader,0)
 return true
func record(list:int,budget:int=8,pressure_budget:int=128,tolerance:float=2e-7)->bool:
 if budget<1 or budget>16 or pressure_budget<1 or pressure_budget>128 or not is_finite(tolerance) or tolerance<=0.:return false
 dispatch(list,0,false,tolerance)
 for iteration in range(budget+1):
  if not op.record(list,pressure_budget):return false
  dispatch(list,1,iteration==budget,tolerance)
 dispatch(list,2,true,tolerance)
 return true
func dispatch(list:int,phase:int,last:bool,tolerance:float)->void:
 var pc:=PackedByteArray();pc.resize(16);pc.encode_u32(0,op.n);pc.encode_u32(4,phase);pc.encode_u32(8,1 if last else 0);pc.encode_float(12,tolerance)
 rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,uniforms,0);rd.compute_list_set_push_constant(list,pc,16)
 rd.compute_list_dispatch(list,1,1,1);rd.compute_list_add_barrier(list)
func release()->void:
 for rid:RID in [uniforms,pipeline,shader,force,output,status]:
  if rid.is_valid():rd.free_rid(rid)
 if op!=null:op.release();op=null
