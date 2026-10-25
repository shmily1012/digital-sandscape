extends "res://src/phase_preview.gd"
func _initialize_gpu()->void:
	fluid.grain_traction_enabled=not ("--without-traction" in OS.get_cmdline_user_args())
	fluid.voxel_interface_enabled="--paired-interface" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--wetting-cosine="):
			fluid.grain_wetting_cosine=argument.trim_prefix("--wetting-cosine=").to_float()
	super._initialize_gpu()
func _process(delta:float)->void:
	super._process(delta)
	if initialized and not fluid.grain_traction_enabled:
		status.text=status.text.replace("Sand + liquid — experimental", "DIAGNOSTIC: grain traction disabled")
	if initialized and fluid.voxel_interface_enabled:
		status.text=status.text.replace("Sand + liquid — experimental", "CANDIDATE: paired stress, wetting %.1f"%fluid.grain_wetting_cosine)
	if initialized and fluid.grain_energy_enabled:
		status.text=status.text.replace("CANDIDATE: paired stress", "EXPERIMENT: overdamped exchange")
func _finish_close()->void:
	get_tree().quit(0 if get_tree().failures==0 else 1)
