extends "res://tests/energy_bubble_behavior.gd"
## Same-geometry material intervention. Mobility and effective weight both vary.
## Frozen grains are a diagnostic boundary control, not a physical loaded bed.
func fluid_hash(rd:RenderingDevice,solver:RefCounted)->String:
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
	digest.update(rd.buffer_get_data(solver.phase[solver.tick%2]))
	digest.update(rd.buffer_get_data(solver.distributions[solver.tick%2]))
	digest.update(rd.buffer_get_data(solver.mass_residual))
	return digest.finish().hex_encode()

func intervention(rd:RenderingDevice,material:int,movable:bool,weight_scale:float=1.,mobility_scale:float=1.)->Dictionary:
	var fields:=Fluid.contact_fields(N,32,true)
	for i in range(N*N):
		if fields.walls[i]>=2:fields.walls[i]=material
	var solver:=Fluid.new()
	solver.grain_energy_enabled=true;solver.voxel_interface_enabled=true
	solver.grain_weight_scale=weight_scale;solver.grain_mobility_scale=mobility_scale
	solver.grain_wetting_cosine=.5;solver.grain_motion_enabled=movable
	solver.grain_collective_enabled="--collective-exchange" in OS.get_cmdline_user_args()
	if not solver.initialize(rd,N,fields.gas,fields.walls,PackedVector2Array(),true,20261024):
		check(false,"Initialization failed");return {}
	var name:="material-%d-%s"%[material,"moving" if movable else "fixed"]
	if weight_scale!=1. or mobility_scale!=1.:name+="-weight-%.2f-mobility-%.2f"%[weight_scale,mobility_scale]
	var initial:=sample(rd,solver,name)
	var record:Dictionary={"material":material,"movable":movable,"weight_scale":weight_scale,"mobility_scale":mobility_scale,"initial_fluid_hash":fluid_hash(rd,solver),"samples":[initial]}
	for batch in range(40):
		solver.advance(100,Vector2(0,.00002),.01);rd.submit();rd.sync()
		if solver.tick%1000!=0:continue
		var current:=sample(rd,solver,name)
		current.fluid_hash=fluid_hash(rd,solver);record.samples.append(current)
		check(current.invalid==0 and current.counts==initial.counts,name+" containment/materials")
		check(absf(current.mass-initial.mass)<=initial.mass*1e-4,name+" gas inventory")
		check(absf(current.fluid_mass-initial.fluid_mass)<=initial.fluid_mass*1e-6,name+" fluid inventory")
	solver.release();return record

func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var cases:Array=[]
	for movable in [false,true]:
		for material in [2,4]:
			var result:=intervention(rd,material,movable)
			if result.is_empty():rd.free();quit(1);return
			cases.append(result)
	for item:Dictionary in cases:
		check(item.initial_fluid_hash==cases[0].initial_fluid_hash,"Initial fluids differ")
	var fixed_equal:=true
	for k in range(1,cases[0].samples.size()):
		fixed_equal=fixed_equal and cases[0].samples[k].fluid_hash==cases[1].samples[k].fluid_hash
	var dark:Dictionary=cases[2].samples.back();var white:Dictionary=cases[3].samples.back()
	var report:Dictionary={"failures":failures,"cases":cases,"fixed_geometry_fluid_identical":fixed_equal,
		"moving_dark_minus_white":{"gas_y":dark.gas_y-white.gas_y,"axis_ratio":dark.axis_ratio-white.axis_ratio,"released":dark.released-white.released},
		"physical_acceptance":false,
		"scope":"Material 2 versus 4 changes effective weight AND mobility; this is not a density-only experiment. Fixed grains disable the movement kernel and act as externally constrained boundaries. Identical fixed-boundary fluid does not alone prove missing physical load transfer."}
	report.collective_exchange="--collective-exchange" in OS.get_cmdline_user_args()
	var suffix:="-collective" if report.collective_exchange else ""
	var out:=FileAccess.open("res://reports/energy-material-response%s.json"%suffix,FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "));out.close()
	print("ENERGY_MATERIAL_RESPONSE failures=",failures," fixed_equal=",fixed_equal," response=",report.moving_dark_minus_white)
	rd.free();quit(0 if failures.is_empty() else 1)
