class_name AestheticDirector
extends RefCounted

# Natural mode only in M1. The director never owns or writes cell state.
var angle_degrees: float = 0.0

func set_angle(value: float) -> void:
	angle_degrees = fposmod(value, 360.0)

func gravity() -> Vector2i:
	var radians := deg_to_rad(angle_degrees)
	return Vector2i(roundi(sin(radians) * 32767.0), roundi(cos(radians) * 32767.0))
