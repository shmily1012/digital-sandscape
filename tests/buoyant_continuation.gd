extends "res://tests/phase_preview_smoke.gd"
# One requested continuation, using the actual production scene and energy path.
var ledger := {}
func capture_gpu()->void:
	var solver:RefCounted=app.fluid
	var result:=PackedByteArray()
	if solver.buoyant_exchange!=null:result=solver.rd.buffer_get_data(solver.buoyant_exchange.result)
	accept_packet.call_deferred(solver.rd.buffer_get_data(solver.phase[solver.tick%2]),solver.rd.buffer_get_data(solver.materials),solver.rd.buffer_get_data(solver.distributions[solver.tick%2]),result)
func accept_packet(bytes:PackedByteArray,m:PackedByteArray,f:PackedByteArray,result:PackedByteArray)->void:
	if result.size()>=32:
		ledger={"minimum_delta":result.decode_float(0),"accepted_loops":result.decode_u32(12),"interface":result.decode_float(16),"sand_weight":result.decode_float(20),"gas_buoyancy":result.decode_float(24),"eligible_proposals":result.decode_u32(28)}
	accept_state(bytes,m,f)
func summary()->Dictionary:
	var gas:=state.to_float32_array();var mass:=0.;var moment:=0.;var counts:=[0,0,0,0,0]
	for i in range(gas.size()):
		mass+=gas[i];moment+=gas[i]*floori(float(i)/256.);counts[materials[i]]+=1
	return {"gas_y":moment/mass,"gas_mass":mass,"sand_counts":[counts[2],counts[3],counts[4]]}
func run()->void:
	var initial_bytes:=FileAccess.get_file_as_bytes("res://reports/buoyant-transaction-input.bin")
	var metadata:Dictionary={"side":256,"bytes":initial_bytes,"tick":90000,"seed":20261024,"with_sand":true,"paused":true,"mineral_style":false,"angle":0.,"resource_preset":2,"grain_drag_divisor":1,"collective_exchange":false,"weight_scale":1.,"mobility_scale":1.,"wetting_cosine":.5}
	app=load("res://sandscape.tscn").instantiate();app.session_enabled=false;app.restored_session=metadata;app.paused=true;root.add_child(app)
	for _frame in range(300):
		await process_frame
		if app.initialized:break
	if not app.initialized:push_error("Production scene initialization failed");quit(1);return
	await capture();var initial:=summary()
	await advance(2000)
	await capture();var final:=summary()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/closed-loop-once.png")
	var rise:float=initial.gas_y-final.gas_y
	var result:={"initial":initial,"final":final,"rise_cells":rise,"sand_conserved":initial.sand_counts==final.sand_counts,"rise_at_least_one_cell":rise>=1.,"energy":ledger,"requested_ticks":2000,"completed_ticks":app.completed_tick-90000,"scene":"sandscape.tscn","source":"Recorded 90000-tick stalled phase/material/populations; existing reconstructed fixture has zero residual and initialized movement stamps; not a full historical journal."}
	var file:=FileAccess.open("res://reports/closed-loop-once.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("CLOSED_LOOP_ONCE ",JSON.stringify(result))
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
