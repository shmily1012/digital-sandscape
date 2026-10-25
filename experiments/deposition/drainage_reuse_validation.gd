extends SceneTree
const Operator=preload("res://experiments/deposition/drainage_operator_gpu.gd")
func _initialize()->void:_run.call_deferred()
func _run()->void:
 var rd:=RenderingServer.create_local_rendering_device()
 if rd==null:quit(2);return
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/drainage-gpu-fixtures.json"))
 var test:Dictionary=fixture.cases[1]
 var op=Operator.new()
 if not op.initialize(rd,test):op.release();rd.free();quit(2);return
 var base:=PackedFloat32Array()
 for v:Array in test.velocities:base.append_array(PackedFloat32Array(v))
 var previous:=rd.buffer_get_data(op.output_force())
 var failures:=0;var rows:Array=[]
 var cases:Array=[{"name":"cold","scale":1.,"budget":128},{"name":"same","scale":1.,"budget":128},{"name":"reverse_budget","scale":-1.,"budget":1},{"name":"reverse_recover","scale":-1.,"budget":128},{"name":"nan","scale":1.,"budget":128},{"name":"recover","scale":.5,"budget":127},{"name":"zero","scale":0.,"budget":128},{"name":"double_record","scale":1.,"budget":128}]
 cases.push_front({"name":"tiny_cold","scale":1e-20,"budget":128})
 cases.append_array([{"name":"tiny","scale":1e-20,"budget":128},{"name":"huge","scale":1e38,"budget":128},{"name":"after_huge","scale":1.,"budget":128}])
 for sample:Dictionary in cases:
  var v:=base.duplicate()
  for i in range(v.size()):v[i]*=float(sample.scale)
  if sample.name=="nan":v[-1]=NAN
  rd.buffer_update(op.input_velocity(),0,v.size()*4,v.to_byte_array())
  rd.capture_timestamp("begin")
  var list:=rd.compute_list_begin()
  if not op.record(list,int(sample.budget)):failures+=1
  if sample.name=="double_record":
   if not op.record(list,int(sample.budget)):failures+=1
  rd.compute_list_end();rd.capture_timestamp("end");rd.submit();rd.sync()
  var begin: int=-1;var end: int=-1
  for i in range(rd.get_captured_timestamps_count()):
   if rd.get_captured_timestamp_name(i)=="begin":begin=rd.get_captured_timestamp_gpu_time(i)
   if rd.get_captured_timestamp_name(i)=="end":end=rd.get_captured_timestamp_gpu_time(i)
  var accepted:=rd.buffer_get_data(op.output_status()).decode_u32(0)==1
  var output:=rd.buffer_get_data(op.output_force());var status:=rd.buffer_get_data(op.solver.control)
  var expected:bool=sample.name!="nan" and sample.name!="reverse_budget"
  if accepted!=expected:failures+=1
  var error:=0.
  if expected and accepted:
   for i in range(v.size()):
    var value:=output.decode_float(i*4)
    if not is_finite(value):failures+=1
    var scale:float=absf(float(sample.scale))
    error=maxf(error,absf(value/scale-float(test.expected_h[i])*signf(float(sample.scale))) if scale>0. else absf(value))
    if scale==0. and value!=0.:failures+=1
   if error>1e-7:failures+=1
  elif output!=previous:failures+=1
  if sample.name in ["same","double_record"] and status.decode_u32(8)!=0:failures+=1
  rows.append({"name":sample.name,"geometry_status":rd.buffer_get_data(op.refs[9]).decode_u32(0),"source_scale":rd.buffer_get_data(op.extra[5]).decode_float(0),"accepted":accepted,"scale_normalized_error":error,"cycles":status.decode_u32(8),"gpu_ms":float(end-begin)/1e6})
  previous=output
 # Host budget validation must not record an operation or mutate published bytes.
 var list:=rd.compute_list_begin()
 if op.record(list,0) or op.record(list,129):failures+=1
 rd.compute_list_end();rd.submit();rd.sync()
 if rd.buffer_get_data(op.output_force())!=previous:failures+=1
 var result:={"failures":failures,"cases":rows,"scope":"Reusable GPU operator, persistent pressure, mutable velocity, rejection recovery, odd parity and two records without CPU readback"}
 var file:=FileAccess.open("res://reports/drainage-reuse-gpu.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
 print("DRAINAGE_REUSE_RESULT ",JSON.stringify(result))
 op.release();rd.free();quit(0 if failures==0 else 1)
