extends SceneTree
const Solver=preload("res://experiments/deposition/resistance_solver_gpu.gd")
func _initialize()->void:_run.call_deferred()
func _run()->void:
 var rd:=RenderingServer.create_local_rendering_device()
 if rd==null:quit(2);return
 var fixtures:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/resistance-solve-fixtures.json"))
 var failures:=0;var rows:Array=[]
 for test:Dictionary in fixtures.cases:
  var solver=Solver.new()
  if not solver.initialize(rd,test):solver.release();rd.free();quit(2);return
  var previous:=rd.buffer_get_data(solver.output)
  for scenario:String in ["force","reverse","budget","pressure_budget","nan","zero","recover"]:
   var f:=PackedFloat32Array(test.force);var scale:float=-1. if scenario=="reverse" else (0. if scenario=="zero" else 1.)
   for i in range(f.size()):f[i]*=scale
   if scenario=="nan":f[-1]=NAN
   rd.buffer_update(solver.force,0,f.size()*4,f.to_byte_array())
   rd.capture_timestamp("start")
   var list:=rd.compute_list_begin()
   if not solver.record(list,1 if scenario=="budget" else 8,1 if scenario=="pressure_budget" else 128):failures+=1
   rd.compute_list_end();rd.capture_timestamp("end");rd.submit();rd.sync()
   var begin:int=-1;var end:int=-1
   for i in range(rd.get_captured_timestamps_count()):
    if rd.get_captured_timestamp_name(i)=="start":begin=rd.get_captured_timestamp_gpu_time(i)
    if rd.get_captured_timestamp_name(i)=="end":end=rd.get_captured_timestamp_gpu_time(i)
   var state:=rd.buffer_get_data(solver.status);var output:=rd.buffer_get_data(solver.output)
   var accepted:bool=state.decode_u32(0)==1 and state.decode_u32(4)==0
   var expected:bool=scenario not in ["budget","pressure_budget","nan"]
   if expected!=accepted:failures+=1
   var error:=0.
   if accepted:
    for i in range(f.size()):
     var v:=output.decode_float(i*4)
     if not is_finite(v):failures+=1
     error=maxf(error,absf(v-float(test.expected_velocity[i])*scale))
    if error>6e-6 or state.decode_float(12)>2e-7:failures+=1
   elif output!=previous:failures+=1
   rows.append({"name":test.name,"pressure_residual":rd.buffer_get_data(solver.op.solver.control).decode_float(0),"geometry_ok":rd.buffer_get_data(solver.op.refs[9]).decode_u32(0),"scenario":scenario,"accepted":accepted,"iterations":state.decode_u32(8),"residual":state.decode_float(12),"velocity_error":error,"velocity":Array(output.to_float32_array()),"scale":scale,"gpu_ms":float(end-begin)/1e6})
   previous=output
  solver.release()
 var result:={"failures":failures,"cases":rows,"scope":"Force-driven GPU Richardson solve at frozen geometry, no contacts or particle advancement"}
 var file:=FileAccess.open("res://reports/resistance-solve-gpu.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
 print("RESISTANCE_SOLVE_RESULT ",JSON.stringify(result))
 rd.free();quit(0 if failures==0 else 1)
