extends "res://src/simulation_state_manager.gd"
## Separate binary journal for the candidate model; never reads legacy saves.
const PHASE_MODEL="phase-boussinesq-voxel-v1"
const MAX_FILE_BYTES=61*1024*1024
static func checksum(bytes:PackedByteArray)->PackedByteArray:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish()
static func encode(payload:PackedByteArray,metadata:Dictionary)->PackedByteArray:
	var header:=JSON.stringify(metadata).to_utf8_buffer();var bytes:=PackedByteArray();bytes.resize(4)
	bytes.encode_u32(0,header.size());bytes.append_array(header);bytes.append_array(payload);bytes.append_array(checksum(bytes));return bytes
static func unpack(bytes:PackedByteArray,expected_model:String=PHASE_MODEL,extra_bytes_per_cell:int=0)->Dictionary:
	if bytes.size()<36 or bytes.size()>MAX_FILE_BYTES:return {}
	var length:=bytes.decode_u32(0)
	if length>4096 or length+36>bytes.size():return {}
	if checksum(bytes.slice(0,-32))!=bytes.slice(-32):return {}
	var parsed=JSON.parse_string(bytes.slice(4,4+length).get_string_from_utf8())
	if not parsed is Dictionary:return {}
	var data:Dictionary=parsed
	if data.get("model")!=expected_model or data.get("version")!=1:return {}
	for key in ["side","seed","tick","generation","resource_preset"]:
		if not data.get(key) is float and not data.get(key) is int:return {}
		if not is_finite(float(data[key])) or float(data[key])!=floor(float(data[key])):return {}
	if int(data.side) not in [256,512,1024] or data.seed<0 or data.seed>4294967295 or data.tick<0 or data.tick>4294967295:return {}
	if data.generation<1 or data.generation>4294967295 or data.resource_preset<0 or data.resource_preset>4:return {}
	for key in ["paused","mineral_style","with_sand"]:
		if not data.get(key) is bool:return {}
	if not data.get("angle") is float and not data.get("angle") is int:return {}
	if not is_finite(float(data.angle)) or data.angle<0 or data.angle>=360:return {}
	if data.get("gravity_magnitude")!=0.00002 or data.get("sigma")!=0.01:return {}
	var drag=data.get("grain_drag_divisor",1)
	if not drag is float and not drag is int:return {}
	if not is_finite(float(drag)) or float(drag)!=floor(float(drag)) or int(drag) not in [1,16,64,256]:return {}
	data.grain_drag_divisor=int(drag)
	var n:=int(data.side);var cells:=n*n
	var payload:=bytes.slice(4+length,-32)
	if not data.get("mass_compensation",false) is bool:return {}
	var compensated:bool=data.get("mass_compensation",false)
	if payload.size()!=cells*((56 if compensated else 52)+extra_bytes_per_cell):return {}
	for i in range(cells):
		var c:=payload.decode_float(i*4);var m:=payload.decode_u32(cells*40+i*4)
		var dx:=2*(i%n)+1-n;var dy:=2*(i/n)+1-n
		var wall:bool=dx*dx+dy*dy>=(n-4)*(n-4)
		if m>4 or (m==1)!=wall or (not data.with_sand and m>=2):return {}
		if not is_finite(c) or c<0. or c>1. or (m!=0 and c!=0.):return {}
		var rho:=0.
		for q in range(9):
			var f:=payload.decode_float(cells*4+(i*9+q)*4)
			if not is_finite(f) or f<0.:return {}
			rho+=f
		if rho<=0.:return {}
		# Nonzero prescribed walls are not a supported interactive session yet.
		if payload.decode_float(cells*44+i*8)!=0. or payload.decode_float(cells*44+i*8+4)!=0.:return {}
		if compensated:
			var residual:=payload.decode_float(cells*52+i*4)
			if not is_finite(residual) or absf(residual)>1e-5:return {}
	data["bytes"]=payload;return data
func model_identifier()->String:return PHASE_MODEL
func decode_snapshot(bytes:PackedByteArray)->Dictionary:return unpack(bytes)
func load_latest()->Dictionary:
	var best:Dictionary={};var found:=false
	for slot in ["a","b"]:
		var path:=directory.path_join("phase-"+slot+".bin")
		if not FileAccess.file_exists(path):continue
		found=true
		var file:=FileAccess.open(path,FileAccess.READ)
		if file==null:continue
		if file.get_length()>MAX_FILE_BYTES:file.close();continue
		var candidate:=decode_snapshot(file.get_buffer(file.get_length()));file.close()
		if not candidate.is_empty() and (best.is_empty() or candidate.generation>best.generation):best=candidate
	if not best.is_empty():generation=int(best.generation);message="Candidate session restored"
	elif found:message="Candidate save invalid; files retained"
	else:message=""
	return best
func save(payload:PackedByteArray,metadata:Dictionary)->bool:
	var data:=metadata.duplicate(true);data.version=1;data.model=model_identifier();data.generation=generation+1
	var bytes:=encode(payload,data)
	if decode_snapshot(bytes).is_empty():message="Invalid candidate snapshot; not saved";return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))!=OK:message="Cannot create candidate folder";return false
	var path:=ProjectSettings.globalize_path(directory.path_join("phase-"+("a" if (generation+1)%2==1 else "b")+".bin"));var temp:=path+".tmp"
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:message="Cannot write candidate snapshot";return false
	file.store_buffer(bytes);file.flush();var error:=file.get_error();file.close()
	if error!=OK or decode_snapshot(FileAccess.get_file_as_bytes(temp)).is_empty():message="Candidate write verification failed";return false
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path)!=OK:message="Cannot replace candidate slot";return false
	if DirAccess.rename_absolute(temp,path)!=OK:message="Candidate commit failed; other slot retained";return false
	generation+=1;message="Candidate session saved";return true
