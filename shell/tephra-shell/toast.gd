extends CanvasLayer

const Themes = preload("res://themes.gd")
const Notifications = preload("res://notifications.gd")
## Small notifications that drop in from the top edge of the screen into the top bar, e.g. a saved
## screenshot. They never come in from the sides.

var TEXT: Color = Themes.c("text")
const RED := Color(1.0, 0.25, 0.2)

var _panel: PanelContainer
var _icon: TextureRect
var _label: Label
var _busy := false
var _queue: Array = []

func _ready() -> void:
	layer = 97  # above the control center
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Themes.c("panel")  # fully solid, so nothing shows through it
	sb.set_border_width_all(2)
	sb.border_color = Themes.ink(0.14)
	sb.set_corner_radius_all(Themes.r(18))
	sb.content_margin_left = 20
	sb.content_margin_right = 26
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.visible = false
	add_child(_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	_panel.add_child(h)
	_icon = TextureRect.new()
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	h.add_child(_icon)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", TEXT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_label)

var _gen := 0          # a new number each time the one on screen is cut short
var _tw: Tween
var _hidden_pos := Vector2.ZERO

## Shows a notification. flash_red makes the icon blink red (for warnings). A new one does not wait in line: the one
## on screen quickly goes back up and the new one drops down.
func show_toast(icon: Texture2D, text: String, flash_red := false, record := true) -> void:
	if record:
		Notifications.push(text, "battery" if flash_red else "info")  # it also stays in Control center > Notifications
	_queue.clear()  # only the newest is shown (all of them stay in Control center > Notifications)
	_queue.append([icon, text, flash_red])
	if not _busy:
		_next()
	else:
		_interrupt()

## The one on screen goes back up fast, then the newest drops down.
func _interrupt() -> void:
	_gen += 1
	if _tw != null:
		_tw.kill()
	var my := _gen
	var up := create_tween()
	up.tween_property(_panel, "position", _hidden_pos, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	up.finished.connect(func() -> void:
		if my == _gen:
			_next())

func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	_gen += 1
	var my := _gen
	var job: Array = _queue.pop_front()
	_icon.texture = job[0]
	_label.text = job[1]
	_icon.modulate = Color.WHITE
	_panel.position = Vector2(0, -400)  # off the top of the screen while it is measured
	_panel.visible = true
	_panel.reset_size()
	await get_tree().process_frame
	if my != _gen:
		return
	var vw := _panel.get_viewport_rect().size.x
	# Sits in the middle of the top bar band (which runs from y 62 to y 154).
	var shown := Vector2((vw - _panel.size.x) / 2.0, 108.0 - _panel.size.y / 2.0)
	var hidden := Vector2(shown.x, -_panel.size.y - 24.0)  # just above the top edge of the screen
	_hidden_pos = hidden
	_panel.position = hidden
	var t := create_tween()
	_tw = t
	t.tween_property(_panel, "position", shown, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if job[2]:
		for i in 6:
			t.tween_property(_icon, "modulate", RED, 0.25)
			t.tween_property(_icon, "modulate", Color.WHITE, 0.25)
	else:
		t.tween_interval(3.0)
	t.tween_interval(1.0)
	t.tween_property(_panel, "position", hidden, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.finished.connect(func() -> void:
		if my == _gen:
			_panel.visible = false
			_next())
