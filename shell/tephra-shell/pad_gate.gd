extends Node
## With several controllers connected everyone can move around the menus, but only the player in charge (P1 by default)
## can press Cross / A to select. Added last, so it sees input first.

const Glyphs = preload("res://glyphs.gd")

func _input(event: InputEvent) -> void:
	if not event is InputEventJoypadButton or not event.pressed or not event.is_action("ui_accept"):
		return
	var pads := Input.get_connected_joypads().filter(func(p): return Glyphs.family_for_device(p) != "")
	if pads.size() < 2:
		return
	if event.device != Glyphs.primary_device():
		get_viewport().set_input_as_handled()
