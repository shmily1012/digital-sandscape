extends SceneTree
## Fork saved test states; never mutate the observation trajectory or user saves.
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	for name in ["water-4000","relaxed-bubble-8000","relaxed-bubble-9000","relaxed-bubble-12000"]:
		var prefix:String="res://reports/contact-"+name
		var c:=FileAccess.get_file_as_bytes(prefix+".phase")
		var m:=FileAccess.get_file_as_bytes(prefix+".materials")
		var f:=FileAccess.get_file_as_bytes(prefix+".populations")
		var residual:=FileAccess.get_file_as_bytes(prefix+".residual")
		if c.size()!=128*128*4 or m.size()!=c.size() or f.size()!=c.size()*9 or residual.size()!=c.size():quit(1);return
		var solver:=Fluid.new();solver.grain_motion_enabled=false
		if not solver.initialize(rd,128,c.to_float32_array(),m.to_int32_array(),PackedVector2Array(),true,20261024):quit(1);return
		rd.buffer_update(solver.distributions[0],0,f.size(),f)
		rd.buffer_update(solver.mass_residual,0,residual.size(),residual)
		var list:=rd.compute_list_begin();solver.record_boundary_impulse(list,0);rd.compute_list_end()
		solver.advance(1,Vector2(0,.00002),.01);rd.submit();rd.sync()
		if rd.buffer_get_data(solver.materials)!=m:quit(1);return
		for entry in [["next",rd.buffer_get_data(solver.distributions[1])],["impulse",rd.buffer_get_data(solver.traction)]]:
			var file:=FileAccess.open(prefix+"."+entry[0],FileAccess.WRITE);file.store_buffer(entry[1]);file.close()
		solver.release()
	rd.free();print("CONTACT_LEDGER_GPU captures complete; run independent verifier");quit(0)
