extends SceneTree
const Job=preload("res://experiments/deposition/async_coupled_job.gd")
var job:Node
var picture:TextureRect
var shared:Texture2DRD
var slider:HSlider
var label:Label
var simulation_paused:=false
var closing:=false
var dragging:=false
var smoke:=false
var checking:=false
var failures:=0
var pause_retained:=false
var initial:PackedByteArray
var snapshot:=PackedByteArray()
var captured:=false
var started:=0
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	Engine.max_fps=30;auto_accept_quit=false
	root.size=Vector2i(680,720);root.title="Digital Sandscape — Coupled physics diagnostic"
	smoke="--coupled-smoke" in OS.get_cmdline_user_args()
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/coupled-cycle-fixtures.json"))
	var planes:Array=fixture.planes.duplicate(true)
	for i in range(32):
		var normal:=Vector2.from_angle(TAU*i/32.0)
		planes.append([normal.x,normal.y,normal.dot(Vector2(.5,.5))-.46*cos(PI/32),0])
	picture=TextureRect.new();picture.position=Vector2(84,84);picture.size=Vector2(512,512);picture.pivot_offset=Vector2(256,256)
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;picture.gui_input.connect(_picture_input);root.add_child(picture)
	label=Label.new();label.position=Vector2(22,16);label.text="Coupled physics diagnostic / 2 magnified grains\nPlanar support + sealed carrier; no bubbles or dense sand model";root.add_child(label)
	slider=HSlider.new();slider.position=Vector2(50,620);slider.size=Vector2(580,24);slider.min_value=0;slider.max_value=360;slider.step=.1
	slider.value_changed.connect(func(angle:float):picture.rotation=deg_to_rad(angle));root.add_child(slider)
	var button:=Button.new();button.position=Vector2(50,663);button.text="Pause / Resume (drag picture to rotate)";button.pressed.connect(_toggle_pause);root.add_child(button)
	job=Job.new();root.add_child(job)
	job.texture_ready.connect(func(texture:RID):shared=Texture2DRD.new();shared.texture_rd_rid=texture;picture.texture=shared)
	job.completed.connect(_completed);job.closed.connect(func():quit(1 if failures else 0))
	root.close_requested.connect(_close);process_frame.connect(_frame)
	started=Time.get_ticks_msec();job.initialize(fixture.base,fixture.initial,planes,true)
func _picture_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:dragging=event.pressed
	if event is InputEventMouseMotion and dragging:slider.value=fposmod(slider.value+event.relative.x*.6,360.0)
func _toggle_pause() -> void:
	simulation_paused=not simulation_paused
	if simulation_paused:job.cancel()
func _frame() -> void:
	if closing or checking:return
	if smoke and Time.get_ticks_msec()-started>120000:failures+=1;_close();return
	if simulation_paused or job.state!="idle":return
	if smoke and job.tick>=12:checking=true;_finish();return
	job.start(Vector2.DOWN.rotated(-deg_to_rad(slider.value)),.005)
func _completed(result:Dictionary) -> void:
	if not result.success:
		if result.reason=="cancelled":return
		simulation_paused=true;label.text="Step rejected; world retained. Diagnostic model limit."
		if smoke:failures+=1;_close()
		return
	label.text="Coupled diagnostic / 2 magnified grains / no bubbles\nTick %d | model time %.3f | %d async packets" % [job.tick,job.simulated_time,result.packets]
	if smoke and job.tick==6:simulation_paused=true;checking=true;_pause_check()
func _capture() -> PackedByteArray:
	captured=false
	if not job.capture_for_test(func(data:PackedByteArray):snapshot=data;captured=true):failures+=1;return PackedByteArray()
	for frame in range(600):
		await process_frame
		if captured:return snapshot
	failures+=1;return PackedByteArray()
func _pause_check() -> void:
	initial=await _capture()
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;_picture_input(down)
	var move:=InputEventMouseMotion.new();move.relative=Vector2(150,0);_picture_input(move)
	down.pressed=false;_picture_input(down)
	for frame in range(8):await process_frame
	pause_retained=await _capture()==initial and absf(slider.value-90)<.01 and job.tick==6
	if not pause_retained:failures+=1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/coupled-lab-paused.png")
	slider.value=180;simulation_paused=false;checking=false
func _finish() -> void:
	var final_state:PackedByteArray=await _capture()
	var moved_up:=true
	for i in range(2):
		moved_up=moved_up and final_state.decode_float(i*32+4)<initial.decode_float(i*32+4)
		if final_state.slice(i*32+8,i*32+32)!=initial.slice(i*32+8,i*32+32):failures+=1
		var point:=Vector2(final_state.decode_float(i*32),final_state.decode_float(i*32+4))
		if point.distance_to(Vector2(.5,.5))+final_state.decode_float(i*32+8)>.460001:failures+=1
	if not moved_up:failures+=1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/coupled-lab-final.png")
	var render_checked:=_verify_texture(final_state)
	var report:={"render_checked":render_checked,"failures":failures,"ticks":job.tick,"paused_rotation_retained":pause_retained,"reversal_moved_up":moved_up,"scope":"GPU texture directly samples jointly published particles; diagnostic only, no liquid arrows or aesthetic claim"}
	FileAccess.open("res://reports/coupled-lab-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COUPLED_LAB ",JSON.stringify(report));_close()
func _verify_texture(state:PackedByteArray) -> bool:
	var image:=shared.get_image()
	if image==null or image.get_width()!=512 or image.get_height()!=512:failures+=1;return false
	image.save_png("res://reports/coupled-lab-texture.png")
	var samples:Array=[{"point":Vector2i(0,0),"color":Color(.075,.08,.085)}, {"point":Vector2i(256,100),"color":Color(.79,.80,.79)}, {"point":Vector2i(80,268),"color":Color(.36,.36,.36)}]
	for i in range(2):
		var shade:=.11 if state.decode_float(i*32+20)<1.5 else .43
		samples.append({"point":Vector2i(floori(state.decode_float(i*32)*512),floori(state.decode_float(i*32+4)*512)),"color":Color(shade,shade,shade)})
	var ok:=true
	for sample:Dictionary in samples:
		var actual:=image.get_pixelv(sample.point)
		var expected:Color=sample.color
		if maxf(absf(actual.r-expected.r),maxf(absf(actual.g-expected.g),absf(actual.b-expected.b)))>1.0/255.0+.001:ok=false
	if not ok:failures+=1
	return ok
func _close() -> void:
	if closing:return
	closing=true
	picture.texture=null
	if shared!=null:shared.texture_rd_rid=RID()
	job.close()
