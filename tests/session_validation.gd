extends SceneTree
const State=preload("res://src/simulation_state_manager.gd")
const Physics=preload("res://src/physics_engine.gd")
var failures:=0
var app:Control
var folder:=""
var expected:=PackedByteArray()
func _initialize()->void:_run.call_deferred()
func check(condition:bool,label:String)->void:
 if not condition:failures+=1;push_error("SESSION_FAIL "+label)
func _run()->void:
 folder="user://session-test-"+str(OS.get_process_id())
 var store=State.new();store.directory=folder
 var rd:=RenderingServer.create_local_rendering_device()
 if rd==null:quit(2);return
 var a=Physics.new();var b=Physics.new()
 if not a.initialize(rd,256,709,true):rd.free();quit(2);return
 a.advance(Vector2i(0,32767),80);rd.submit();rd.sync()
 expected=rd.texture_get_data(a.state,0)
 var metadata:={"side":256,"seed":709,"tick":80,"angle":37.5,"paused":true,"mineral_style":false,"resource_preset":1}
 check(store.save(expected,metadata),"first save")
 var recovered:=store.load_latest()
 check(not recovered.is_empty() and recovered.bytes==expected,"restore exact bytes")
 if recovered.is_empty():a.release();rd.free();quit(1);return
 if not b.initialize(rd,256,709,true,recovered.bytes):quit(2);return
 b.tick=int(recovered.tick)
 for step in range(40):
  var g:=Vector2i(roundi(sin(step*.17)*32767),roundi(cos(step*.17)*32767))
  a.advance(g,1);b.advance(g,1)
 rd.submit();rd.sync()
 check(rd.texture_get_data(a.state,0)==rd.texture_get_data(b.state,0),"restored continuation matches live GPU")
 metadata.tick=120
 check(store.save(rd.texture_get_data(a.state,0),metadata),"second save")
 var latest:=folder.path_join("session-b.json")
 var original:=FileAccess.get_file_as_string(latest)
 check(State.decode(original.substr(0,original.length()/2)).is_empty(),"truncation rejected")
 var envelope:Dictionary=JSON.parse_string(original)
 envelope.sha256="bad"
 check(State.decode(JSON.stringify(envelope)).is_empty(),"checksum rejected")
 for fault in ["version","wall","tick"]:
  var outer:Dictionary=JSON.parse_string(original);var body:Dictionary=JSON.parse_string(outer.body)
  if fault=="version":body.version=99
  if fault=="tick":body.tick=1.5
  if fault=="wall":
   var bytes:=Marshalls.base64_to_raw(body.cells);bytes.encode_u32(0,0);body.cells=Marshalls.raw_to_base64(bytes)
  outer.body=JSON.stringify(body);outer.sha256=State.digest(outer.body)
  check(State.decode(JSON.stringify(outer)).is_empty(),fault+" rejected after valid checksum")
 var corrupt:=FileAccess.open(latest,FileAccess.WRITE);corrupt.store_string("truncated");corrupt.close()
 var fresh=State.new();fresh.directory=folder;recovered=fresh.load_latest()
 check(recovered.get("tick")==80 and recovered.get("bytes")==expected,"newest corrupt falls back to previous")
 a.release();b.release();rd.free()
 # Exercise actual startup/manual save/close on the main RenderingDevice.
 app=load("res://main.tscn").instantiate();app.set_script(load("res://tests/session_host.gd"));app.sessions.directory=folder
 root.add_child(app)
 for frame in range(300):
  await process_frame
  if app.initialized:break
 check(app.initialized,"main startup")
 if not app.initialized:quit(1);return
 check(app.budget.preset==1,"resource preset restored")
 check(app.completed_tick==80 and app.world_seed==709 and app.paused,"main restores metadata")
 check(is_equal_approx(app.director.angle_degrees,37.5) and not app.mineral_style,"main restores angle and style")
 app.save_session()
 while app.pending:await process_frame
 check(app.session_note=="Session saved","manual main-device save")
 app.session_age=121.0
 await process_frame
 while app.pending:await process_frame
 check(app.sessions.generation==3,"periodic checkpoint")
 app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
func session_closed()->void:
 var store=State.new();store.directory=folder;var saved:=store.load_latest()
 check(saved.get("bytes")==expected and saved.get("tick")==80,"close saved exact main state")
 check(store.generation==4,"manual and close commits")
 var file:=FileAccess.open("res://reports/session-validation.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"generation":store.generation,"scope":"GPU snapshot/continuation, corruption fallback, actual app startup/manual save/close","folder":folder},"  "));file.close()
 print("SESSION_RESULT failures=",failures," generation=",store.generation)
 quit(0 if failures==0 else 1)
