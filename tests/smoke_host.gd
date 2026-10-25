extends "res://src/main.gd"

# Preserve the production cleanup path while propagating test failures to the OS.
func _finish_close() -> void:
	get_tree().quit(0 if get_tree().failures == 0 else 1)

func _init()->void:
	session_enabled=false
