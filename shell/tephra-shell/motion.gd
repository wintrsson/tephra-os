extends RefCounted
## Animation helpers. Every fade, grow and slide in Tephra goes through here, so
## Settings > Accessibility > Animations can turn them all off in one place.

const Settings = preload("res://settings.gd")

## Off when animations are switched off, and in Power saver (Settings > Display), where menus switch instantly.
static func on() -> bool:
	return bool(Settings.get_value("animations", true)) and str(Settings.get_value("gpu_mode", "")) != "saver"

## A duration that becomes 0 (instant) when animations are off.
static func dur(t: float) -> float:
	return t if on() else 0.0

## Fades a control in while it grows from a slightly smaller size (menu to menu moves).
static func pop(c: Control, from := 0.95, t := 0.22) -> void:
	c.pivot_offset = c.size / 2.0
	if not on():
		c.scale = Vector2.ONE
		c.modulate.a = 1.0
		return
	c.scale = Vector2.ONE * from
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, t)

## Smoothly grows or shrinks a control to a scale. A new call replaces the previous one for
## the same control, so quick presses never fight each other (that made icons jitter).
static func scale_to(c: Control, to: float, t := 0.16) -> void:
	if c.has_meta("_motion_tween"):
		var old = c.get_meta("_motion_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	c.pivot_offset = c.size / 2.0
	if not on():
		c.scale = Vector2.ONE * to
		return
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * to, t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c.set_meta("_motion_tween", tw)

## Same idea for opacity.
static func fade_to(c: CanvasItem, to: float, t := 0.16) -> void:
	var key := "_motion_fade"
	if c.has_meta(key):
		var old = c.get_meta(key)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	if not on():
		c.modulate.a = to
		return
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", to, t).set_trans(Tween.TRANS_SINE)
	c.set_meta(key, tw)
