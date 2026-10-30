extends CanvasLayer
## The small actions menu that Triangle opens on a game (Home, and over a running game):
## Resume / Close game, Hide from Home / Show on Home, Uninstall.

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const Motion = preload("res://motion.gd")
const PageSkin = preload("res://page_skin.gd")
const TephraGlyphs = preload("res://glyphs.gd")

signal chosen(key: String)

var is_open := false
var _items: Array = []   # [key, label, danger]
var _sel := 0
var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _hints: HBoxContainer

func _init() -> void:
	layer = 99
	_dim = ColorRect.new()
	_dim.color = Themes.dim(0.6)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", PageSkin.panel())
	preload("res://rounded.gd").rough(_panel)
	center.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size.x = 520
	_panel.add_child(vb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Themes.c("text"))
	_title.clip_text = true
	vb.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	vb.add_child(_list)
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 14)
	vb.add_child(_hints)

func open(title: String, items: Array) -> void:
	_items = items
	_sel = 0
	_title.text = title
	_rebuild()
	TephraGlyphs.fill(_hints, [["accept", "Choose"], ["back", "Close"]], 26)
	is_open = true
	_dim.visible = true
	_dim.modulate.a = 0.0
	Motion.fade_to(_dim, 1.0, 0.15)
	Motion.pop(_panel, 0.94, 0.2)

func close() -> void:
	if not is_open:
		return
	is_open = false
	var t := create_tween()
	t.tween_property(_dim, "modulate:a", 0.0, Motion.dur(0.12))
	t.tween_callback(func():
		if not is_open:
			_dim.visible = false)

func move(dy: int) -> void:
	if _items.is_empty() or dy == 0:
		return
	_sel = posmod(_sel + dy, _items.size())
	_rebuild()

func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for i in _items.size():
		var it: Array = _items[i]
		var row := PanelContainer.new()
		var on := i == _sel
		var sb := PageSkin.button(on, false, Themes.c("select"))
		if on and it[2]:  # a red row for the ones you can't undo (Uninstall, Close game)
			sb.bg_color = Color(0.80, 0.25, 0.28, 0.9)
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		row.add_theme_stylebox_override("panel", sb)
		preload("res://rounded.gd").rough(row)
		var l := Label.new()
		l.text = PageSkin.words(it[1])
		l.add_theme_font_size_override("font_size", 28)
		l.add_theme_color_override("font_color", Color(1, 1, 1) if on and it[2] else PageSkin.button_text(on, false, Themes.c("select")))
		row.add_child(l)
		_list.add_child(row)

## Returns true when the menu used the event.
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event is InputEventJoypadMotion:
		return true
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		var key: String = _items[_sel][0]
		close()
		chosen.emit(key)
	return true
