extends SceneTree

const Resources = preload("res://src/adaptive_resource_manager.gd")
var failures := 0

func _initialize() -> void:
	var budget := Resources.new()
	var total := 0
	for _frame in range(120):
		total += budget.schedule(1.0 / 60.0, true, false)
	check(total == 60, "30 physics ticks per 60 rendered frames")
	for _frame in range(30):
		check(budget.schedule(0.1, true, true) == 0, "pause")
	check(budget.accumulator == 0.0, "pause clears time debt only")
	check(budget.schedule(3600.0, true, false) <= 2, "bounded catch-up")
	budget = Resources.new()
	total = 0
	for _frame in range(100):
		total += budget.schedule(0.1, false, false)
	check(total == 50, "background continues at 5 Hz")
	budget = Resources.new()
	for _frame in range(300):
		check(budget.schedule(0.06, true, false) <= 2, "overload dispatch cap")
	check(budget.render_fps == 30, "reduce render first")
	check(budget.target_hz >= 15.0 and budget.target_hz < 30.0, "bounded physics reduction")
	check(budget.fps_limit(false) == 10, "background render cap")
	for mode in range(5):
		budget=Resources.new();check(budget.select_preset(mode),"preset accepted")
		var ticks:=0;var redraws:=0
		for frame in range(600):
			ticks+=budget.schedule(1./60.,true,false)
			if budget.render_due(1./60.,true):redraws+=1
		check(absf(ticks-10.*Resources.PHYSICS_HZ[mode])<=1.,"preset cadence")
		check(absf(redraws-10.*minf(Resources.COLOR_HZ[mode],Resources.DISPLAY_FPS[mode]))<=1.,"independent visual cadence")
		check(budget.schedule(3600.,true,false)<=2,"preset wake cap")
	check(not budget.select_preset(99),"invalid preset")
	print("SCHEDULER_TEST_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
