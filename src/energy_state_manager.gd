extends "res://src/phase_state_manager.gd"
## Full energy-model journal; incompatible schemas are rejected, never migrated.
const Base=preload("res://src/phase_state_manager.gd")
const ENERGY_MODEL="sandscape-energy-v1"
static func unpack_energy(bytes:PackedByteArray)->Dictionary:
	var data:=Base.unpack(bytes,ENERGY_MODEL,4)
	if data.is_empty():return {}
	for key in ["with_sand","mass_compensation","energy_exchange","paired_interface"]:
		if not data.get(key) is bool or not data[key]:return {}
	if not data.get("collective_exchange") is bool:return {}
	for key in ["energy_revision","collective_revision"]:
		if not data.get(key) is float and not data.get(key) is int:return {}
	if data.get("energy_revision")!=1 or data.get("collective_revision")!=2:return {}
	if data.get("initial_profile")!="seeded-irregular-bubbles-v1":return {}
	for key in ["weight_scale","mobility_scale"]:
		if not data.get(key) is float and not data.get(key) is int:return {}
		if not is_finite(float(data[key])) or data[key]<=0. or data[key]>4.:return {}
	if not data.get("wetting_cosine") is float and not data.get("wetting_cosine") is int:return {}
	if data.get("wetting_cosine") not in [-.5,0.,.5]:return {}
	var cells:=int(data.side)*int(data.side)
	for i in range(cells):
		var stamp:int=data.bytes.decode_u32(cells*56+i*4)
		if stamp!=4294967295 and stamp>=int(data.tick):return {}
	return data
func model_identifier()->String:return ENERGY_MODEL
func decode_snapshot(bytes:PackedByteArray)->Dictionary:return unpack_energy(bytes)
