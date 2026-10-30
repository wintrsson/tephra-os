extends Node
## Helper for frame_probe.gd: one copy runs first in every frame, one runs last (see process_priority).

var probe
var is_first := true

func _process(delta: float) -> void:
	if probe == null:
		return
	if is_first:
		probe.tick_first()
	else:
		probe.tick_last(delta)
