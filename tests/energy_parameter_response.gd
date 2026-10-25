extends "res://tests/energy_material_response.gd"
## Effective weight and kinetic mobility interventions on identical material 2.
func run()->void:
	var rd:=RenderingServer.create_local_rendering_device()
	if rd==null:quit(1);return
	var cases:Array=[]
	for config in [[1.,1.],[.7,1.],[1.4,1.],[1.,.5],[1.,2.]]:
		var result:=intervention(rd,2,true,config[0],config[1])
		if result.is_empty():rd.free();quit(1);return
		cases.append(result)
	for item:Dictionary in cases:
		check(item.initial_fluid_hash==cases[0].initial_fluid_hash,"Initial fluids differ")
		check(item.samples[0].counts==cases[0].samples[0].counts,"Initial material inventories differ")
	var report:Dictionary={"failures":failures,"cases":cases,"physical_acceptance":false,
		"scope":"Same initial geometry, material identity, seed and fluid arrays. Effective grain weight scales gravity work only, mobility scales grain kinetic resistance only. Fluid drag and gas buoyancy unchanged. Does not establish a resolved contact-pressure load balance."}
	report.collective_exchange="--collective-exchange" in OS.get_cmdline_user_args()
	var suffix:="-collective" if report.collective_exchange else ""
	var out:=FileAccess.open("res://reports/energy-parameter-response%s.json"%suffix,FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "));out.close()
	print("ENERGY_PARAMETER_RESPONSE failures=",failures)
	rd.free();quit(0 if failures.is_empty() else 1)
