extends SceneTree
func _initialize()->void:
	var app:=load("res://main.tscn").instantiate()
	app.set_script(load("res://src/phase_preview.gd"));root.add_child.call_deferred(app)
