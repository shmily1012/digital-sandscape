extends RefCounted
## Optional orientation intent only. No particle access or settling inference.
var enabled := false
var wait_seconds := 600.0
var turn_seconds := 15.0
var elapsed := 0.0
var turning := false
var start_angle := 0.0

func configure(active: bool, wait_time: float, turn_time: float) -> void:
	enabled = active
	wait_seconds = clampf(wait_time, 60.0, 86400.0)
	turn_seconds = clampf(turn_time, 5.0, 300.0)
	elapsed = 0.0
	turning = false

func advance(delta: float, angle: float) -> float:
	if not enabled:
		return angle
	# Discard suspension backlog instead of fast-forwarding the container.
	elapsed += clampf(delta, 0.0, 0.1)
	if not turning:
		if elapsed >= wait_seconds:
			turning = true
			start_angle = angle
			elapsed = 0.0
		return angle
	var progress := clampf(elapsed / turn_seconds, 0.0, 1.0)
	var eased := progress * progress * (3.0 - 2.0 * progress)
	var result := start_angle + 180.0 * eased
	if progress >= 1.0:
		turning = false
		elapsed = 0.0
	return result
