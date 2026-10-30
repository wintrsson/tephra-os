extends CanvasLayer
## Tephra's tab list for the browser (PS > Browser > Tabs). Firefox runs without any bars of its own, so this is
## where you see which pages are open and which one you are on: a row of cards with each page's title and site,
## the current one marked. Cross goes to a page, Square closes it, Triangle (or the last card) opens a new one.
## Opened by home.gd over a picture of the browser, the same way the control center opens over a game.

signal finished(action: String, index: int)  # "switch" i, "close" i, "new" -1, "" -1 = nothing (just closed)

const Themes = preload("res://themes.gd")
const Icons = preload("res://icons.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Rounded = preload("res://rounded.gd")

const CARD := Vector2(330, 190)
const GAP := 24
const SHOWN := 5

var is_open := false
var _tabs: Array = []
var _current := 0
var _sel := 0
var _first := 0
var _root: Control
var _row: HBoxContainer
var _title: Label
var _where: Label
var _hints: HBoxContainer
var _cards: Array = []

func _ready() -> void:
	layer = 95
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Themes.dim(0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 80
	v.offset_right = -80
	v.offset_top = 120
	v.add_theme_constant_override("separation", 18)
	_root.add_child(v)
	_title = _label("Tabs", 40, Themes.c("text"))
	v.add_child(_title)
	_where = _label("", 22, Themes.c("muted"))
	_where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_where.custom_minimum_size.x = 600
	v.add_child(_where)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", GAP)
	v.add_child(_row)
	for i in SHOWN:
		_row.add_child(_make_card())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	_hints.custom_minimum_size.y = 60
	v.add_child(_hints)
	var pad := Control.new()
	pad.custom_minimum_size.y = 40
	v.add_child(pad)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _make_card() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = CARD
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Themes.c("card"), 0.92)
	sb.border_color = Themes.c("select")
	sb.set_corner_radius_all(Themes.r(16))
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	top.add_child(icon)
	var site := _label("", 18, Themes.c("muted"))
	site.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	site.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	site.custom_minimum_size.x = 120
	top.add_child(site)
	var name := _label("", 24, Themes.c("text"))
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.max_lines_visible = 3
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.custom_minimum_size = Vector2(CARD.x - 36, 0)
	name.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(name)
	var here := _label("", 16, Themes.c("select"))
	v.add_child(here)
	_cards.append({"panel": p, "style": sb, "icon": icon, "site": site, "name": name, "here": here})
	return p

## tabs: [{title, url}], current: the page on screen now.
func open(tabs: Array, current: int) -> void:
	_tabs = tabs
	_current = current
	_sel = clampi(current, 0, _tabs.size())  # _tabs.size() = the "New tab" card
	_first = 0
	is_open = true
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.15)
	_redraw()

func close(action := "", index := -1) -> void:
	if not is_open:
		return
	is_open = false
	if action == "_quiet":
		_root.visible = false
		finished.emit(action, index)
		return
	# fades away instead of cutting out (the page or the keyboard follows once it has gone)
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.14)
	await t.finished
	_root.visible = false
	finished.emit(action, index)

static func _site(url: String) -> String:
	var s := url.get_slice("://", 1) if "://" in url else url
	s = s.get_slice("/", 0)
	return s.trim_prefix("www.")

func _redraw() -> void:
	var count := _tabs.size() + 1
	if _sel < _first:
		_first = _sel
	elif _sel >= _first + SHOWN:
		_first = _sel - SHOWN + 1
	_title.text = "Tabs (%d open)" % _tabs.size() if _tabs.size() != 1 else "Tabs (1 open)"
	if _current < _tabs.size():
		var cur: Dictionary = _tabs[_current]
		_where.text = "You're on: %s   %s" % [str(cur["title"]), _site(str(cur["url"]))]
	else:
		_where.text = ""
	for i in SHOWN:
		var c: Dictionary = _cards[i]
		var idx := _first + i
		var p: Control = c["panel"]
		p.visible = idx < count
		if not p.visible:
			continue
		var on := idx == _sel
		var st: StyleBoxFlat = c["style"]
		st.set_border_width_all(4 if on else 0)
		st.bg_color = Color(Themes.c("card"), 1.0 if on else 0.82)
		p.scale = Vector2.ONE * (1.04 if on else 1.0)
		p.pivot_offset = CARD * 0.5
		var name: Label = c["name"]
		var site: Label = c["site"]
		var here: Label = c["here"]
		var icon: TextureRect = c["icon"]
		if idx == _tabs.size():
			name.text = "New tab"
			site.text = ""
			here.text = ""
			icon.texture = Icons.texture("globe", Icons.svg_globe(), 30)
		else:
			var t: Dictionary = _tabs[idx]
			name.text = str(t["title"])
			site.text = _site(str(t["url"]))
			here.text = "On screen now" if idx == _current else ""
			icon.texture = Icons.texture("globe", Icons.svg_globe(), 30)
		name.add_theme_color_override("font_color", Themes.c("text") if on else Themes.c("muted"))
	var items: Array = [["dpad", "Choose (or L1 / R1)"], ["accept", "Open" if _sel < _tabs.size() else "New tab"]]
	if _sel < _tabs.size():
		items.append(["west", "Close tab"])
	items.append(["north", "New tab"])
	items.append(["back", "Back"])
	TephraGlyphs.fill(_hints, items)

static func _shoulder(event: InputEvent, button: int) -> bool:
	return event is InputEventJoypadButton and event.pressed and event.button_index == button

## One card left or right (D-pad, or L1 / R1): the cards slide in from that side.
func _step(d: int) -> void:
	var to := clampi(_sel + d, 0, _tabs.size())
	if to == _sel:
		return
	_sel = to
	_redraw()
	await get_tree().process_frame  # after the row has been laid out again
	_row.position.x = float(d) * (CARD.x + GAP) * 0.6
	create_tween().tween_property(_row, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	var vp := get_viewport()
	if event.is_action_pressed("ui_left") or _shoulder(event, JOY_BUTTON_LEFT_SHOULDER):
		_step(-1)
	elif event.is_action_pressed("ui_right") or _shoulder(event, JOY_BUTTON_RIGHT_SHOULDER):
		_step(1)
	elif event.is_action_pressed("ui_accept"):
		if _sel >= _tabs.size():
			close("new")
		else:
			close("switch", _sel)
	elif event.is_action_pressed("ui_cancel"):
		close()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.west_button() \
			or event is InputEventKey and event.pressed and event.keycode == KEY_X:
		if _sel < _tabs.size():
			close("close", _sel)
	elif event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.north_button() \
			or event is InputEventKey and event.pressed and event.keycode == KEY_Y:
		close("new")
	else:
		return
	vp.set_input_as_handled()
