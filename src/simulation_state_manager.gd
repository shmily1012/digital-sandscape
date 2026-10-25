extends RefCounted
# Two-slot journal: only the older slot is replaced, preserving the last valid save.
const MODEL="liquid-grid-support-v2"
const LIMIT=12582912
var directory:="user://sessions"
var generation:=0
var message:=""
static func digest(text:String)->String:
 var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(text.to_utf8_buffer());return context.finish().hex_encode()
static func decode(text:String)->Dictionary:
 if text.length()>LIMIT:return {}
 var parser:=JSON.new()
 if parser.parse(text)!=OK:return {}
 var envelope=parser.data
 if not envelope is Dictionary or not envelope.get("body") is String or not envelope.get("sha256") is String:return {}
 var body:String=envelope.body
 if digest(body)!=envelope.sha256:return {}
 if parser.parse(body)!=OK:return {}
 var data=parser.data
 if not data is Dictionary or data.get("version")!=1 or data.get("model")!=MODEL:return {}
 for key in ["side","seed","tick","generation"]:
  if not data.get(key) is float and not data.get(key) is int:return {}
  if not is_finite(float(data[key])) or float(data[key])!=floor(float(data[key])):return {}
 if int(data.side) not in [256,512,1024] or data.seed<0 or data.seed>4294967295 or data.tick<0 or data.tick>4294967295 or data.generation<1 or data.generation>4294967295:return {}
 if not data.get("angle") is float and not data.get("angle") is int:return {}
 if not is_finite(float(data.angle)) or data.angle<0 or data.angle>=360:return {}
 if not data.get("paused") is bool or not data.get("mineral_style") is bool or not data.get("cells") is String:return {}
 if data.has("resource_preset"):
  var value=data.resource_preset
  if not value is float and not value is int:return {}
  if not is_finite(float(value)) or float(value)!=floor(float(value)) or value<0 or value>4:return {}
 var n:=int(data.side)
 if data.cells.length()!=ceili(n*n*4/3.0)*4:return {}
 var bytes:=Marshalls.base64_to_raw(data.cells)
 if bytes.size()!=n*n*4:return {}
 for y in range(n):
  for x in range(n):
   var m:=bytes.decode_u32((y*n+x)*4);var dx:=2*x+1-n;var dy:=2*y+1-n
   var wall:bool=dx*dx+dy*dy>(n-8)*(n-8)
   if m>5 or (m==4)!=wall:return {}
 data["bytes"]=bytes
 return data
func load_latest()->Dictionary:
 var best:Dictionary={};var found:=false
 for slot in ["a","b"]:
  var path:=directory.path_join("session-"+slot+".json")
  if not FileAccess.file_exists(path):continue
  found=true
  var file:=FileAccess.open(path,FileAccess.READ)
  if file==null:continue
  if file.get_length()>LIMIT:file.close();continue
  var candidate:=decode(file.get_as_text());file.close()
  if not candidate.is_empty() and (best.is_empty() or int(candidate.generation)>int(best.generation)):best=candidate
 if not best.is_empty():generation=int(best.generation);message="Session restored"
 elif found:message="Saved session invalid; existing files retained"
 else:message=""
 return best
func save(bytes:PackedByteArray,metadata:Dictionary)->bool:
 var data:=metadata.duplicate(true);data["version"]=1;data["model"]=MODEL;data["generation"]=generation+1;data["cells"]=Marshalls.raw_to_base64(bytes)
 var body:=JSON.stringify(data)
 var encoded:=JSON.stringify({"body":body,"sha256":digest(body)})
 if encoded.length()>LIMIT or decode(encoded).is_empty():message="Invalid snapshot; not saved";return false
 if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))!=OK:message="Cannot create session folder";return false
 var path:=ProjectSettings.globalize_path(directory.path_join("session-"+("a" if (generation+1)%2==1 else "b")+".json"))
 var temp:=path+".tmp"
 var file:=FileAccess.open(temp,FileAccess.WRITE)
 if file==null:message="Cannot write session";return false
 file.store_string(encoded);file.flush();var error:=file.get_error();file.close()
 if error!=OK:message="Session write failed";return false
 # Validate bytes written before replacing the older slot.
 if decode(FileAccess.get_file_as_string(temp)).is_empty():message="Session verification failed";return false
 if FileAccess.file_exists(path) and DirAccess.remove_absolute(path)!=OK:message="Cannot replace old session slot";return false
 if DirAccess.rename_absolute(temp,path)!=OK:message="Session commit failed; other slot retained";return false
 generation+=1;message="Session saved";return true
