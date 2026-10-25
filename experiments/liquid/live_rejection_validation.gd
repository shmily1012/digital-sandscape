extends SceneTree
const Cell = preload("res://experiments/liquid/live_cell.gd")
var cell: Node
var snapshot := PackedByteArray()
var result: Dictionary = {}
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _idle() -> bool:
	for frame in range(600):
		await process_frame
		if not cell.pending: return true
	failures += 1
	return false

func _capture() -> PackedByteArray:
	if not cell.capture_for_test(func(data: PackedByteArray): snapshot=data):
		failures += 1
		return PackedByteArray()
	await _idle()
	return snapshot

func _run() -> void:
	Engine.max_fps = 60
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/pressure-transport-fixtures.json"))
	var sequence: Array = JSON.parse_string(FileAccess.get_file_as_string("res://reports/capillary-sequence.json"))
	var fixture: Dictionary = fixtures[0]
	fixture.geometry.initial = sequence[0].initial
	cell = Cell.new()
	root.add_child(cell)
	cell.completed.connect(func(value: Dictionary): result=value)
	cell.closed.connect(func(): quit(0 if failures==0 else 1))
	cell.initialize(fixture)
	if not await _idle() or not cell.initialized:
		quit(2)
		return
	var before := await _capture()
	if not cell.step(Vector2.DOWN,8): failures += 1
	if cell.step(Vector2.DOWN): failures += 1
	await _idle()
	var rejected: bool = not result.get("accepted",true)
	var after := await _capture()
	if not rejected or before!=after or cell.ticks!=0 or cell.elapsed!=0:
		failures += 1
	if not cell.step(Vector2.DOWN,96): failures += 1
	await _idle()
	if not result.get("accepted",false) or cell.ticks!=1: failures += 1
	var actual := await _capture()
	var error := 0.0
	if actual.size()!=4096:
		failures += 1
	else:
		for i in range(1024): error=maxf(error,absf(actual.decode_float(i*4)-float(sequence[0].expected[i])))
	if error>3e-4: failures += 1
	var report := {"failures":failures,"budget_rejected":rejected,"fraction_byte_identical_on_rejection":before==after,"recovered_ticks":cell.ticks,"max_fraction_error":error,"scope":"Main-device fused pressure/transport packets: cold budget rejection retains interface and time, retry evolves same state."}
	var file := FileAccess.open("res://reports/live-rejection-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("LIVE_REJECTION_RESULT ",JSON.stringify(report))
	cell.close()
