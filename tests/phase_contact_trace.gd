extends SceneTree
## Test-only instrumentation of the actual voxel kernel, with an uninstrumented twin.
const Fluid=preload("res://src/phase_fluid.gd")
const N=256
const START=10000
const STEPS=128
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	if not value:failures.append(message);push_error(message)
func group(c:PackedFloat32Array,m:PackedInt32Array,i:int)->String:
	var vertical:=0.;var weight:=0.
	for dy in [-1,0,1]:
		for dx in [-1,0,1]:
			var x:int=i%N+dx;var y:int=i/N+dy
			if (dx==0 and dy==0) or x<0 or y<0 or x>=N or y>=N:continue
			var j:int=y*N+x
			if m[j]!=0 or c[j]<=.05:continue
			weight+=c[j];vertical+=c[j]*dy/Vector2(dx,dy).length()
	if weight==0.:return "no_adjacent_gas"
	return "gas_downstream" if vertical/weight>.5 else ("gas_upstream" if vertical/weight<-.5 else "lateral_or_ambiguous")
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var base:=Fluid.new();var fields:=Fluid.contact_fields(N,N/4)
	if not base.initialize(rd,N,fields.gas,fields.walls,PackedVector2Array(),true,20261024):quit(1);return
	# Rebuild the full state: old screenshot exports omit the mass residual.
	while base.tick<START:
		base.advance(mini(128,START-base.tick),Vector2(0,.00002),.01);rd.submit();rd.sync()
		if base.tick%2048==0:print("CONTACT_TRACE warmup ",base.tick)
	var snapshot:PackedByteArray=base.snapshot_bytes()
	var saved_c:=FileAccess.get_file_as_bytes("res://reports/phase-contact-bed-tick-10000.f32")
	var saved_m:=FileAccess.get_file_as_bytes("res://reports/phase-contact-bed-tick-10000.materials.u32")
	var matching:=snapshot.slice(0,N*N*4)==saved_c and snapshot.slice(N*N*40,N*N*44)==saved_m
	check(matching,"Replayed state differs from the observed window")
	var checkpoint:=FileAccess.open("res://reports/contact-trace-start.bin",FileAccess.WRITE);checkpoint.store_buffer(snapshot);checkpoint.close()
	var traced:=Fluid.new()
	if not traced.restore(rd,{"side":N,"bytes":snapshot,"tick":START,"seed":20261024,"with_sand":true}):quit(1);return
	check(traced.snapshot_bytes()==snapshot,"Full snapshot restore")
	var c:=saved_c.to_float32_array();var m:=saved_m.to_int32_array()
	var ids:=PackedInt32Array();ids.resize(N*N)
	for i in range(N*N):ids[i]=i
	var identities:RID=traced.buffer(N*N*4,ids.to_byte_array())
	var zero:=PackedByteArray();zero.resize(N*N*16)
	var events:RID=traced.buffer(zero.size(),zero)
	var forces:RID=traced.buffer(zero.size(),zero)
	var source:=FileAccess.get_file_as_string("res://shaders/phase_grains.glsl").replace("#[compute]","")
	var declarations:="""
layout(set=0,binding=5,std430) buffer TraceIds { uint trace_ids[]; };
layout(set=0,binding=6,std430) buffer TraceMoves { ivec4 trace_moves[]; };
layout(set=0,binding=7,std430) buffer TraceForce { vec4 trace_force[]; };
"""
	source=source.replace("void main(){",declarations+"\nvoid main(){")
	var anchor:="        bool supported=false;"
	check(source.count(anchor)==1,"Trace evaluation anchor")
	source=source.replace(anchor,"""
        uint trace_id=trace_ids[index[a]];
        trace_force[trace_id]+=vec4(response,1.,drive[a].y<0?1.:0.);
"""+anchor)
	anchor="    material[b]=m[source];material[a]=0u;"
	check(source.count(anchor)==1,"Trace swap anchor")
	source=source.replace(anchor,"""
    uint moved_id=trace_ids[a];
    ivec2 move=O[target]-O[source];
    trace_moves[moved_id]+=ivec4(move,1,move.y<0?1:0);
    trace_ids[a]=trace_ids[b];trace_ids[b]=moved_id;
"""+anchor)
	var shader_source:=RDShaderSource.new();shader_source.source_compute=source
	var spirv:=rd.shader_compile_spirv_from_source(shader_source)
	if not spirv.compile_error_compute.is_empty():push_error(spirv.compile_error_compute);quit(1);return
	var shader:=rd.shader_create_from_spirv(spirv);traced.shaders.append(shader)
	var pipeline:=rd.compute_pipeline_create(shader)
	# Retain the replaced pipeline for release; only the test twin uses instrumentation.
	traced.pipelines.append(traced.pipelines[2]);traced.pipelines[2]=pipeline
	for parity in range(2):
		traced.grain_sets[parity]=traced.uniform_set([traced.phase[parity],traced.distributions[parity],traced.materials,traced.traction,traced.mass_residual,identities,events,forces],shader)
	base.advance(STEPS,Vector2(0,.00002),.01);traced.advance(STEPS,Vector2(0,.00002),.01);rd.submit();rd.sync()
	check(base.snapshot_bytes()==traced.snapshot_bytes(),"Instrumentation altered physical evolution")
	var end_ids:=rd.buffer_get_data(identities).to_int32_array()
	var end_m:=rd.buffer_get_data(traced.materials).to_int32_array()
	var movements:=rd.buffer_get_data(events).to_int32_array()
	var force:=rd.buffer_get_data(forces).to_float32_array()
	var seen:Dictionary={};var rows:Array=[];var groups:Dictionary={}
	for i in range(N*N):
		var id:int=end_ids[i]
		check(id>=0 and id<N*N and not seen.has(id),"Identity duplicate/out of bounds");seen[id]=true
		if end_m[i]<2:continue
		check(end_m[i]==m[id],"Mineral identity changed")
		check(i%N-id%N==movements[4*id] and i/N-id/N==movements[4*id+1],"Move ledger differs from position")
		check(force[4*id+2]==2*STEPS,"Missing per-partition force observation")
		var name:=group(c,m,id)
		if not groups.has(name):groups[name]={"grains":0,"moved":0,"upward_hops":0,"net_dy":0,"upward_drive_samples":0,"force_samples":0,"force_y_sum":0.}
		var entry:Dictionary=groups[name];entry.grains+=1;entry.moved+=int(movements[4*id+2]>0)
		entry.upward_hops+=movements[4*id+3];entry.net_dy+=movements[4*id+1]
		entry.upward_drive_samples+=int(force[4*id+3]);entry.force_samples+=int(force[4*id+2])
		entry.force_y_sum+=force[4*id+1]
		rows.append({"initial_cell":id,"final_cell":i,"material":m[id],"initial_group":name,"moves":Array(movements.slice(4*id,4*id+4)),"force_over_weight_sum_samples":Array(force.slice(4*id,4*id+4))})
	for entry:Dictionary in groups.values():
		entry.stationary_grains=entry.grains-entry.moved
		entry.mean_force_y_over_weight=entry.force_y_sum/maxi(1,entry.force_samples)
	var report:Dictionary={"failures":failures,"start_tick":START,"steps":STEPS,"source_matches_window":matching,"physical_acceptance":false,"groups":groups,"particles":rows,"scope":"Actual production voxel kernel plus test-only identity/force/movement counters. Uninstrumented twin must remain byte-identical. Groups are initial local adjacency, not persistent contact or proof of support."}
	var out:=FileAccess.open("res://reports/contact-motion-trace.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	print("CONTACT_TRACE failures=",failures," groups=",groups)
	traced.release();base.release();rd.free();quit(0 if failures.is_empty() else 1)
