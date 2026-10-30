extends Control
## Notepad: a small text editor for .txt files in Files. Up/Down choose a line, Cross edits it with Tephra's keyboard,
## Square adds a line below, Triangle deletes the line, Circle saves and closes (nothing is saved if nothing changed).

signal closed
signal hints_changed
signal keyboard_requested(title: String, initial: String, done: Callable)

const Themes = preload("res://themes.gd")
const Glyphs = preload("res://glyphs.gd")
const VISIBLE := 13
const LINE_H := 46
const MAX_BYTES := 262144

var is_open := false
var _path := ""
var _lines: Array = []
var _sel := 0
var _top := 0
var _dirty := false
var _msg: Label
var _title: Label
var _panel: PanelContainer
var _list: VBoxContainer
var _rows: Array = []
var _count: Label

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Themes.c("panel"), 0.98)
	sb.set_corner_radius_all(Themes.r(28))
	sb.set_content_margin_all(26)
	sb.set_border_width_all(2)
	sb.border_color = Themes.ink(0.15)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(1120, 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	_title = _label("", 34, Themes.c("text"))
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	v.add_child(_list)
	for i in VISIBLE:
		var p := PanelContainer.new()
		var rs := StyleBoxFlat.new()
		rs.set_corner_radius_all(Themes.r(10))
		rs.content_margin_left = 14
		rs.content_margin_right = 14
		p.add_theme_stylebox_override("panel", rs)
		p.custom_minimum_size = Vector2(0, LINE_H)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		p.add_child(hb)
		var num := _label("", 20, Themes.c("muted"))
		num.custom_minimum_size.x = 54
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(num)
		var txt := _label("", 26, Themes.c("text"))
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		txt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hb.add_child(txt)
		_list.add_child(p)
		_rows.append({"panel": p, "style": rs, "num": num, "text": txt})
	var foot := HBoxContainer.new()
	v.add_child(foot)
	_msg = _label("", 22, Themes.c("muted"))
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_msg)
	_count = _label("", 20, Themes.c("muted"))
	foot.add_child(_count)
	resized.connect(_place)

func _label(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l

func _place() -> void:
	_panel.reset_size()
	_panel.position = (size - _panel.size) / 2.0

func open_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	if f.get_length() > MAX_BYTES:
		return false
	_path = path
	_lines = f.get_as_text().replace("\r\n", "\n").split("\n")
	if _lines.is_empty():
		_lines = [""]
	_sel = 0
	_top = 0
	_dirty = false
	_msg.text = ""
	_title.text = path.get_file()
	is_open = true
	visible = true
	_redraw()
	_place.call_deferred()
	hints_changed.emit()
	return true

func hints() -> Array:
	return [["dpad", "Choose line"], ["accept", "Edit line"], ["west", "New line"], ["north", "Delete line"], ["back", "Save and close"]]

func _redraw() -> void:
	_sel = clampi(_sel, 0, _lines.size() - 1)
	if _sel < _top:
		_top = _sel
	elif _sel >= _top + VISIBLE:
		_top = _sel - VISIBLE + 1
	for i in VISIBLE:
		var r: Dictionary = _rows[i]
		var idx := _top + i
		var p: Control = r["panel"]
		p.visible = idx < _lines.size()
		if not p.visible:
			continue
		(r["num"] as Label).text = str(idx + 1)
		(r["text"] as Label).text = str(_lines[idx]) if str(_lines[idx]) != "" else " "
		var st: StyleBoxFlat = r["style"]
		st.bg_color = Themes.ink(0.16) if idx == _sel else Themes.ink(0.04)
	_count.text = "%d / %d" % [_sel + 1, _lines.size()] + ("   ·   edited" if _dirty else "")
	_place.call_deferred()

func vertical(dir: int) -> void:
	_sel = clampi(_sel + dir, 0, _lines.size() - 1)
	_redraw()

func move(dir: int) -> void:
	vertical(dir * VISIBLE)

func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	var north: bool = event is InputEventJoypadButton and event.pressed and event.button_index == Glyphs.north_button()
	var west: bool = event is InputEventJoypadButton and event.pressed and event.button_index == Glyphs.west_button()
	if event is InputEventKey and event.pressed and not event.echo:
		north = north or event.keycode == KEY_Y
		west = west or event.keycode == KEY_X
	if west:
		_lines.insert(_sel + 1, "")
		_sel += 1
		_dirty = true
		_redraw()
		_edit()
	elif north:
		if _lines.size() > 1:
			_lines.remove_at(_sel)
		else:
			_lines[0] = ""
		_dirty = true
		_redraw()
	elif event.is_action_pressed("ui_cancel"):
		_save_and_close()
	elif event.is_action_pressed("ui_accept"):
		_edit()
	return true

func _edit() -> void:
	var idx := _sel
	keyboard_requested.emit("Line %d" % (idx + 1), str(_lines[idx]), func(text: String) -> void:
		if idx < _lines.size() and text != str(_lines[idx]):
			_lines[idx] = text
			_dirty = true
		_redraw())

func _save_and_close() -> void:
	if _dirty:
		var f := FileAccess.open(_path, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(PackedStringArray(_lines)))
		else:
			_msg.text = "Couldn't save %s." % _path.get_file()
			return
	is_open = false
	visible = false
	closed.emit()
