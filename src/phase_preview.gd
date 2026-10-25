extends "res://src/main.gd"
## Shared application host; model-specific saves never migrate legacy artwork.
const Fluid=preload("res://src/phase_fluid.gd")
const PhaseArt=preload("res://src/phase_art.gd")
const EnergyState=preload("res://src/energy_state_manager.gd")
const PhaseState=preload("res://src/phase_state_manager.gd")
var fluid:=Fluid.new()
var fluid_art:=PhaseArt.new()
var with_sand:=false
var contact_bed:=false
var bubble_barrier:=false
var sandscape_layout:=false
var energy_persistence:=false
var checkpoint_worker:Thread
var checkpoint_in_flight:=false
var close_after_checkpoint:=false

func _init()->void:
	sessions=PhaseState.new()
	sessions.directory="user://phase-sessions"

func configure_profile()->void:
	with_sand="--with-sand" in OS.get_cmdline_user_args()
	contact_bed="--contact-bed" in OS.get_cmdline_user_args()
	bubble_barrier="--bubble-barrier" in OS.get_cmdline_user_args()
	sandscape_layout="--sandscape-layout" in OS.get_cmdline_user_args()
	energy_persistence="--persistent-sandscape" in OS.get_cmdline_user_args()

func _ready()->void:
	configure_profile()
	if energy_persistence:
		var folder:String=sessions.directory
		sessions=EnergyState.new()
		sessions.directory="user://sandscape-energy-sessions" if folder=="user://phase-sessions" else folder
	if contact_bed or bubble_barrier:
		with_sand=true
		if not energy_persistence:session_enabled=false
	if sessions.directory=="user://phase-sessions":sessions.directory+="-sand" if with_sand else "-gas"
	super._ready()

func _initialize_gpu()->void:
	var device:=RenderingServer.get_rendering_device()
	if energy_persistence or "--energy-exchange" in OS.get_cmdline_user_args():
		assert((contact_bed or bubble_barrier) and (not session_enabled or energy_persistence))
		fluid.grain_energy_enabled=true;fluid.voxel_interface_enabled=true
		if sandscape_layout:fluid.grain_wetting_cosine=.5
		fluid.grain_buoyant_enabled=energy_persistence or "--buoyant-exchange" in OS.get_cmdline_user_args()
		assert(not fluid.grain_buoyant_enabled or not session_enabled or energy_persistence)
		fluid.grain_collective_enabled="--collective-exchange" in OS.get_cmdline_user_args()
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--wetting-cosine="):fluid.grain_wetting_cosine=argument.trim_prefix("--wetting-cosine=").to_float()
	var ok:=false
	if not restored_session.is_empty():
		with_sand=restored_session.with_sand
		ok=fluid.restore_energy(device,restored_session) if energy_persistence else fluid.restore(device,restored_session)
	else:
		var air_scale:=1.
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--barrier-air-scale="):air_scale=clampf(argument.trim_prefix("--barrier-air-scale=").to_float(),1.,1.25)
			if argument.begins_with("--grain-drag="):
				var requested:=argument.trim_prefix("--grain-drag=").to_int()
				if requested in [1,16,64,256]:fluid.grain_drag_divisor=requested
		var fields:=Fluid.contact_fields(grid_size,int(grid_size*.25)) if contact_bed else Fluid.initial_fields(grid_size,world_seed,with_sand,"--bubble-barrier" in OS.get_cmdline_user_args(),air_scale)
		if sandscape_layout:fields=Fluid.sandscape_fields(grid_size,world_seed)
		ok=fluid.initialize(device,grid_size,fields.gas,fields.walls,PackedVector2Array(),with_sand,world_seed)
	if ok and fluid.grain_energy_enabled:ok=fluid.initialize_energy_exchange()
	if not ok:_gpu_failed.call_deferred("Fluid initialization failed");return
	if not fluid_art.initialize(device,fluid.phase,grid_size,fluid.materials):_gpu_failed.call_deferred("Fluid renderer initialization failed");return
	fluid_art.refresh(fluid.tick%2);_gpu_ready.call_deferred(fluid_art.texture)

func _update_gpu(gravity:Vector2i,count:int,redraw:bool=true)->void:
	fluid.advance(count,Vector2(gravity)/32767.*0.00002,0.01)
	if redraw:fluid_art.refresh(fluid.tick%2)
	_gpu_done.call_deferred(fluid.tick)

func _layout()->void:
	super._layout()
	status.position.y=size.y-70.

func _process(delta:float)->void:
	super._process(delta)
	if initialized:
		var controls := "Drag to rotate · Space pause"
		if session_enabled:controls += " · Ctrl+S save"
		var model := ("Sand + liquid — experimental · settling resistance ×%d" % fluid.grain_drag_divisor) if with_sand else "Gas/liquid — experimental"
		if fluid.grain_energy_enabled:
			model = "Bubble + sand prototype · natural sand-driven splitting not validated"
		if sandscape_layout:model = "Sandscape physics preview · experimental"
		var persistence := session_note if session_enabled else "Temporary artwork · not saved on exit"
		if not session_enabled and session_note.begins_with("Candidate save invalid"):
			persistence = session_note + " · saving disabled"
		status.text = "%s · tick %d\n%s\n%s" % [controls, completed_tick, model, persistence]

func set_art_style(_filtered:bool)->void:
	pass

func session_metadata()->Dictionary:
	var data:=super.session_metadata();data.with_sand=with_sand;data.gravity_magnitude=0.00002;data.sigma=0.01;data.grain_drag_divisor=fluid.grain_drag_divisor;data.mass_compensation=true;data.grain_rule_revision=Fluid.GRAIN_RULE_REVISION
	if energy_persistence:
		data.merge({"energy_exchange":true,"paired_interface":true,"energy_revision":1,"collective_revision":Fluid.COLLECTIVE_RULE_REVISION,"collective_exchange":fluid.grain_collective_enabled,"weight_scale":fluid.grain_weight_scale,"mobility_scale":fluid.grain_mobility_scale,"wetting_cosine":fluid.grain_wetting_cosine,"initial_profile":"seeded-irregular-bubbles-v1"})
	return data

func _save_session_gpu(metadata:Dictionary)->void:
	metadata.tick=fluid.tick
	_start_checkpoint.call_deferred((fluid.energy_snapshot_bytes() if energy_persistence else fluid.snapshot_bytes()),metadata,false)

func save_session()->void:
	if not session_enabled or not initialized or pending or closing or checkpoint_in_flight:return
	checkpoint_in_flight=true
	super.save_session()

func _start_checkpoint(payload:PackedByteArray,metadata:Dictionary,finish_close:bool)->void:
	checkpoint_worker=Thread.new()
	var error:=checkpoint_worker.start(_write_checkpoint.bind(payload,metadata,finish_close))
	if error!=OK:
		checkpoint_worker=null;checkpoint_in_flight=false
		if finish_close:push_error("Candidate checkpoint worker failed");_finish_close()
		else:
			_saved("Candidate checkpoint worker failed")
			if close_after_checkpoint:_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func _write_checkpoint(payload:PackedByteArray,metadata:Dictionary,finish_close:bool)->void:
	# No RenderingDevice operations on the IO worker. At most one checkpoint exists.
	sessions.save(payload,metadata)
	_checkpoint_complete.call_deferred(sessions.message,finish_close)

func _checkpoint_complete(note:String,finish_close:bool)->void:
	checkpoint_worker.wait_to_finish();checkpoint_worker=null;checkpoint_in_flight=false
	if finish_close:
		if note!="Candidate session saved":push_error(note)
		_finish_close();return
	_saved(note)
	if close_after_checkpoint:_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)

func _notification(what:int)->void:
	if what==Node.NOTIFICATION_WM_CLOSE_REQUEST and checkpoint_in_flight and not closing:
		close_after_checkpoint=true;return
	super._notification(what)

func _release_gpu(metadata:Dictionary)->void:
	var payload:=PackedByteArray()
	if session_enabled and fluid.materials.is_valid():
		metadata.tick=fluid.tick
		payload=(fluid.energy_snapshot_bytes() if energy_persistence else fluid.snapshot_bytes())
	fluid_art.release();fluid.release()
	if not payload.is_empty():_start_checkpoint.call_deferred(payload,metadata,true)
	else:_finish_close.call_deferred()
