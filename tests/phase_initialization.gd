extends SceneTree
const Fluid=preload("res://src/phase_fluid.gd")
func _initialize()->void:
	var failures:=0;var results:Array=[]
	for n in [256,512]:
		var base:=Fluid.initial_fields(n,20261024,true)
		var barrier:=Fluid.initial_fields(n,20261024,true,true)
		var repeat:=Fluid.initial_fields(n,20261024,true,true)
		var dense:=Fluid.initial_fields(n,20261024,true,true,1.25)
		var other:=Fluid.initial_fields(n,20261025,true,true)
		var contact:=Fluid.contact_fields(n,int(n*.25));var weight:=0.;var gas:=0.
		for i in range(n*n):
			gas+=contact.gas[i]
			if contact.walls[i]>=2:weight+=[2.,1.7,1.4][contact.walls[i]-2]
			if (contact.walls[i]==1)!=(base.walls[i]==1):failures+=1
		if weight<=gas:failures+=1
		if base.walls!=barrier.walls or barrier.walls!=dense.walls:failures+=1
		if barrier.gas!=repeat.gas or barrier.walls!=repeat.walls:failures+=1
		if barrier.gas==other.gas:failures+=1
		var natural:=Fluid.sandscape_fields(n,20261024)
		var natural_repeat:=Fluid.sandscape_fields(n,20261024)
		var natural_other:=Fluid.sandscape_fields(n,20261025)
		if natural.gas!=natural_repeat.gas or natural.walls!=natural_repeat.walls:failures+=1
		if natural.gas==natural_other.gas or natural.walls!=base.walls:failures+=1
		var sums:Array=[]
		for fields in [base,barrier,dense,contact,natural]:
			var mass:=0.
			for i in range(n*n):
				var c:float=fields.gas[i];mass+=c
				if not is_finite(c) or c<0. or c>1. or (fields.walls[i]!=0 and c!=0.):failures+=1
			sums.append(mass)
		if sums[2]<=sums[1]:failures+=1
		results.append({"side":n,"gas_inventory_baseline_barrier_dense_contact":sums,"contact_weight_buoyancy_ratio":weight/gas})
	var file:=FileAccess.open("res://reports/phase-initialization.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"cases":results},"  "));file.close()
	print("PHASE_INITIALIZATION failures=",failures," ",results);quit(0 if failures==0 else 1)
