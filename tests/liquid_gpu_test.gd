extends SceneTree

const Physics = preload("res://src/physics_engine.gd")
const Randomness = preload("res://src/randomness_manager.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("GPU TEST BLOCKED: RenderingDevice unavailable; do not use --headless.")
		quit(2)
		return
	var physics := Physics.new()
	if not physics.initialize(rd, 32, 709, true):
		push_error(physics.error_message)
		physics.release()
		rd.free()
		quit(2)
		return
	var initial := Randomness.liquid_state(32, 709)
	for tick in range(70):
		var radians := deg_to_rad(tick * 3.75)
		var gravity := Vector2i(roundi(sin(radians)*32767), roundi(cos(radians)*32767))
		physics.advance(gravity, 1)
	# Tests may synchronize and read back. The interactive renderer never does this.
	rd.submit()
	rd.sync()
	var actual := rd.texture_get_data(physics.state, 0)
	_check(actual.size() == initial.size(), "state byte size")
	if actual.size() != initial.size():
		physics.release()
		rd.free()
		quit(1)
		return
	var counts_before := [0, 0, 0, 0, 0, 0]
	var counts_after := [0, 0, 0, 0, 0, 0]
	for index in range(32 * 32):
		var before := initial.decode_u32(index * 4)
		var after := actual.decode_u32(index * 4)
		counts_before[before] += 1
		if after <= 5:
			counts_after[after] += 1
		else:
			_check(false, "invalid material")
		if before == 4:
			_check(after == 4, "boundary")
	_check(counts_before == counts_after, "per-material conservation")
	var expected_path := "res://reports/liquid_gpu_expected.bin"
	if FileAccess.file_exists(expected_path):
		_check(actual == FileAccess.get_file_as_bytes(expected_path), "CPU/GPU byte equality")
	else:
		_check(false, "missing CPU fixture: run python tests/run_validation.py first")
	var output := FileAccess.open("res://reports/liquid_gpu_actual.bin", FileAccess.WRITE)
	output.store_buffer(actual)
	output.close()
	# Extend the real GPU integrity run beyond the differential fixture.
	for tick in range(70, 1000):
		var radians := deg_to_rad(fposmod(tick * 137.507764, 360.0))
		physics.advance(Vector2i(roundi(sin(radians)*32767), roundi(cos(radians)*32767)), 1)
	rd.submit()
	rd.sync()
	var final_state := rd.texture_get_data(physics.state, 0)
	var final_counts := [0, 0, 0, 0, 0, 0]
	for index in range(32*32):
		var value := final_state.decode_u32(index*4)
		_check(value <= 5, "1000 tick material validity")
		if value <= 5:
			final_counts[value] += 1
		if initial.decode_u32(index*4) == 4:
			_check(value == 4, "1000 tick boundary")
	_check(final_counts == counts_before, "1000 tick conservation")
	print("LIQUID_GPU_TEST_RESULT failures=%d tick=%d counts=%s" % [failures, physics.tick, counts_after])
	var report := FileAccess.open("res://reports/liquid-gpu-validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures": failures, "tick": physics.tick, "counts": final_counts, "cpu_differential_ticks": 70, "engine": Engine.get_version_info().string, "device": rd.get_device_name()}, "  "))
	report.close()
	physics.release()
	rd.free()
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
