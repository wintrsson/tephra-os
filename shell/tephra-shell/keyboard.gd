extends CanvasLayer
## Tephra's on-screen keyboard. Used for Wi-Fi passwords and names; made so any screen can use it:
##   keyboard.open("Password for Home Wi-Fi", "", true, func(text): ..., {"min_len": 8})
## D-pad / stick: move between keys. A: type the key. Buttons follow each console's own keyboard:
##   PlayStation: Square delete (hold repeats), Triangle space, L2 Shift (tap again = Caps), R2 Done, Circle close.
##   Xbox: X delete, Y space, LT symbols page, L3 Shift, Menu Done, B close.
##   Switch: B delete, Y space, ZL Shift, + OK, X cancel.
## LB / RB: move the text cursor. R3: show or hide a password. Start: done.
## A real keyboard works too (type, Backspace, Enter, Esc).

signal closed(accepted: bool)
signal phone_requested   # the Phone key: home.gd shows the QR code (phone_screen.gd)

const TephraGlyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
const BAD := Color("E8645A")
var UNIT := 82.0     # one key's width: smaller than the whole screen so the page behind stays visible
var GAP := 8.0
var KEY_H := 56.0
const STYLES := {
	"ps": {"accent": Color("2F7BFF"), "radius": 14, "name": "DualSense"},
	"xbox": {"accent": Color("62D12F"), "radius": 6, "name": "Xbox"},
	"nintendo": {"accent": Color("FF3C3C"), "radius": 22, "name": "Switch"},
}
var _style := "ps"   # which console's keyboard: set from the controller in use every time it opens
var _offset := Vector2.ZERO  # how far the right stick has moved the keyboard from its usual place
var _stick_dev := -1
var _trig := [false, false]

var is_open := false

var _root: Control
var _panel: PanelContainer
var _title: Label
var _field: PanelContainer
var _before: Label
var _after: Label
var _caret: ColorRect
var _status: Label
var _grid: VBoxContainer
var _hints: HBoxContainer

var _text := ""
var _cursor := 0
var _secret := false
var _shown := false          # a password is being shown as typed
var _min_len := 0
var _max_len := 63
var _done := Callable()
var _page := "abc"           # "abc" or "sym"
var _shift := 0              # 0 off, 1 next letter, 2 caps lock
var _rows: Array = []        # per row: [{node, style, label, kind, value, x0, x1}]
var _sel := Vector2i(1, 0)   # row, column
var _pref_x := 0.0           # where the cursor wants to be horizontally while moving up and down
var _blink := 0.0
var _del_dev := -1           # device whose delete button is held (-1 = none)
var _del_t := 0.0
var _del_next := 0.0

## The shade behind the keyboard; opts "clear" removes it, so the page being typed into stays fully visible.
var _dim: ColorRect

func _ready() -> void:
	layer = 98  # above the control center (95) and notifications (97), below the boot logo (100)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)
	var dim := ColorRect.new()
	_dim = dim
	dim.color = Themes.dim(0.18)  # light, so the screen behind (and the text box being filled) stays visible
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Themes.c("panel"), 0.98)
	sb.set_corner_radius_all(Themes.r(26))
	sb.set_content_margin_all(18)
	sb.set_border_width_all(2)
	sb.border_color = Themes.ink(0.2)
	_panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)

	_title = _label("", 24, TEXT)
	v.add_child(_title)

	_field = PanelContainer.new()
	_field.custom_minimum_size = Vector2(UNIT * 10 + GAP * 9, 56)
	_field.clip_contents = true
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Themes.ink(0.08)
	fsb.set_corner_radius_all(Themes.r(16))
	fsb.content_margin_left = 22
	fsb.content_margin_right = 22
	_field.add_theme_stylebox_override("panel", fsb)
	v.add_child(_field)
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 0)
	fh.alignment = BoxContainer.ALIGNMENT_BEGIN
	_field.add_child(fh)
	_before = _label("", 28, TEXT)
	_before.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(_before)
	_caret = ColorRect.new()
	_caret.color = TEXT
	_caret.custom_minimum_size = Vector2(3, 32)
	_caret.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(_caret)
	_after = _label("", 28, TEXT)
	_after.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(_after)

	_status = _label(" ", 18, MUTED)
	v.add_child(_status)

	_grid = VBoxContainer.new()
	_grid.add_theme_constant_override("separation", int(GAP))
	v.add_child(_grid)

	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_hints.add_theme_constant_override("separation", 12)
	v.add_child(_hints)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# ---------- Open / close ----------
## title = what is being typed. secret = a password (dots, R3 shows it). done is called with the text.
## opts: min_len, max_len, hint (a line under the field), show (start with a password visible).
func open(title: String, initial := "", secret := false, done := Callable(), opts := {}) -> void:
	if is_open:
		return
	is_open = true
	_title.text = title
	_text = initial
	_cursor = initial.length()
	_secret = secret
	_shown = bool(opts.get("show", false))
	_min_len = int(opts.get("min_len", 0))
	_max_len = int(opts.get("max_len", 63))
	_done = done
	_dim.visible = not bool(opts.get("clear", false))
	_style = TephraGlyphs.family if STYLES.has(TephraGlyphs.family) else "ps"
	_offset = Vector2.ZERO
	_page = "abc"
	_shift = 1 if not secret else 0  # names start with a capital letter, passwords don't
	_sel = Vector2i(1, 0)
	_pref_x = 0.0
	_del_dev = -1
	_set_status(str(opts.get("hint", "")), MUTED)
	_build_keys()
	_refresh_text()
	_build_hints()
	_root.visible = true
	Motion.fade_to(_root, 1.0, 0.14)
	_place.call_deferred()

func close(accepted := false) -> void:
	if not is_open:
		return
	is_open = false
	_del_dev = -1
	closed.emit(accepted)
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, Motion.dur(0.12))
	await t.finished
	if not is_open:
		_root.visible = false

func _place() -> void:
	if not is_open:
		return
	_panel.reset_size()
	var vp := _root.get_viewport_rect().size
	var home_pos := Vector2((vp.x - _panel.size.x) / 2.0, vp.y - _panel.size.y - 40.0)
	_offset.x = clampf(_offset.x, -home_pos.x, vp.x - _panel.size.x - home_pos.x)
	_offset.y = clampf(_offset.y, -home_pos.y, vp.y - _panel.size.y - home_pos.y)
	_panel.position = home_pos + _offset

func _set_status(text: String, color: Color) -> void:
	_status.text = text if text != "" else " "
	_status.add_theme_color_override("font_color", color)

# ---------- Keys ----------
# A row is a list of [text, kind, width in key units]. Kinds: char, shift, back, sym, space, done.
func _page_rows() -> Array:
	var abc := _page == "abc"
	if _style == "xbox":
		# Xbox: "#+=" (LT) and delete (X) round the numbers, cursor keys (LB / RB) round the top letters,
		# shift (L3) and done (Menu) round the bottom letters, "@" and ".com" beside the space bar (Y).
		var bottom := [["@", "char", 1.5], ["space", "space", 8.5], [".com", "text", 1.5], ["Phone", "phone", 1.5]]
		if abc:
			return [[["#+=", "sym", 1.5]] + _chars("1234567890") + [["Delete", "back", 1.5]],
				[["<", "cur_l", 1.5]] + _chars("qwertyuiop") + [[">", "cur_r", 1.5]],
				_chars("asdfghjkl'"),
				[["Shift", "shift", 1.5]] + _chars("zxcvbnm,.?") + [["Done", "done", 1.5]],
				bottom]
		return [[["ABC", "sym", 1.5]] + _chars("1234567890") + [["Delete", "back", 1.5]],
			[["<", "cur_l", 1.5]] + _chars("!@#$%^&*()") + [[">", "cur_r", 1.5]],
			_chars("-_=+[]{}/\\"),
			[["Shift", "shift", 1.5]] + _chars(":;\"<>~`|?") + [["Done", "done", 1.5]],
			bottom]
	if _style == "nintendo":
		# Switch: numbers on top with delete (B) at the end, OK (+) beside the home-row letters, shift (ZL) and
		# the "#+=" page at the left of the space bar (Y).
		var bottom := [["Shift", "shift", 1.5], ["#+=" if abc else "ABC", "sym", 1.5], ["space", "space", 6.5], ["Phone", "phone", 1.5]]
		if abc:
			return [_chars("1234567890-") + [["Delete", "back", 1.5]],
				_chars("qwertyuiop/"),
				_chars("asdfghjkl:'") + [["OK", "done", 1.5]],
				_chars("zxcvbnm,.!?"),
				bottom]
		return [_chars("1234567890-") + [["Delete", "back", 1.5]],
			_chars("@#$%&*()+=/"),
			_chars("~^_<>[]{};|") + [["OK", "done", 1.5]],
			_chars("\\`\"!?:,.'()"),
			bottom]
	# DualSense: numbers with "@", a hash / quote / slash column on the right, space (Triangle), delete (Square),
	# shift (L2) and Done (R2) along the bottom.
	var bottom := [["Shift", "shift", 1.5], ["?123" if abc else "ABC", "sym", 1.5], ["space", "space", 3.0], ["Delete", "back", 1.5], ["Phone", "phone", 1.5], ["Done", "done", 1.5]]
	if abc:
		return [_chars("1234567890@"), _chars("qwertyuiop#"), _chars("asdfghjkl\"/"), _chars("zxcvbnm-_?!"), bottom]
	return [_chars("1234567890@"), _chars("!$%^&*()+=~"), _chars("[]{}<>\\|;:,"), _chars("-_.?!'\"/`#:"), bottom]

func _chars(s: String) -> Array:
	var out: Array = []
	for i in s.length():
		out.append([s[i], "char", 1.0])
	return out

func _build_keys() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_rows.clear()
	var widths: Array = []
	for def in _page_rows():
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", int(GAP))
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		_grid.add_child(hb)
		var row: Array = []
		var x := 0.0
		for kd in def:
			var w: float = kd[2]
			var p := PanelContainer.new()
			p.custom_minimum_size = Vector2(w * UNIT + (w - 1.0) * GAP, KEY_H)
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(Themes.r(int(STYLES[_style]["radius"])))
			sb.border_color = STYLES[_style]["accent"]
			p.add_theme_stylebox_override("panel", sb)
			var l := _label(kd[0], 26 if str(kd[1]) == "char" else 20, TEXT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			p.add_child(l)
			hb.add_child(p)
			var span := w * UNIT + (w - 1.0) * GAP
			row.append({"node": p, "style": sb, "label": l, "kind": str(kd[1]), "value": str(kd[0]), "x0": x, "x1": x + span})
			x += span + GAP
		# Rows are centred, so shift this row's x range to match.
		_rows.append(row)
		widths.append(x - GAP)
	var full := 0.0
	for w in widths:
		full = maxf(full, float(w))
	for r in _rows.size():
		for k in _rows[r]:
			k["x0"] += (full - float(widths[r])) / 2.0
			k["x1"] += (full - float(widths[r])) / 2.0
	_field.custom_minimum_size.x = full
	_sel.x = clampi(_sel.x, 0, _rows.size() - 1)
	_sel.y = clampi(_sel.y, 0, _rows[_sel.x].size() - 1)
	_pref_x = _center(_sel)
	_refresh_keys()
	_place.call_deferred()

func _center(at: Vector2i) -> float:
	var k: Dictionary = _rows[at.x][at.y]
	return (float(k["x0"]) + float(k["x1"])) / 2.0

func _refresh_keys() -> void:
	for r in _rows.size():
		for c in _rows[r].size():
			var k: Dictionary = _rows[r][c]
			var on := Vector2i(r, c) == _sel
			var sb: StyleBoxFlat = k["style"]
			var kind: String = k["kind"]
			var active := kind == "shift" and _shift > 0
			sb.bg_color = Color(STYLES[_style]["accent"], 0.55) if on else (Color(0.35, 0.6, 0.95, 0.45) if active else (Color(1, 1, 1, 0.14) if kind != "char" else Color(1, 1, 1, 0.08)))
			sb.set_border_width_all(4 if on else 0)
			var l: Label = k["label"]
			var v: String = k["value"]
			if kind == "char":
				l.text = v.to_upper() if _shift > 0 else v
			elif kind == "shift":
				l.text = "CAPS" if _shift == 2 else "Shift"
			elif kind == "cur_l":
				l.text = "<"
			l.add_theme_color_override("font_color", TEXT)

func _build_hints() -> void:
	for c in _hints.get_children():
		_hints.remove_child(c)
		c.queue_free()
	var items: Array = []
	match _style:
		"xbox":
			items = [["accept", "Type"], ["west", "Delete"], ["north", "Space"], ["l2", "Symbols"], ["chip:L3", "Shift"], ["l1", ""], ["r1", "Cursor"], ["chip:Menu", "Done"]]
		"nintendo":
			items = [["accept", "Type"], ["back", "Delete"], ["north", "Space"], ["l2", "Shift"], ["l1", ""], ["r1", "Cursor"], ["chip:+", "OK"], ["west", "Cancel"]]
		_:
			items = [["accept", "Type"], ["west", "Delete"], ["north", "Space"], ["l2", "Shift"], ["r2", "Done"], ["l1", ""], ["r1", "Cursor"], ["back", "Close"]]
	items.append(["chip:R stick", "Move"])
	if _secret:
		items.append(["chip:R3", "Show"])
	if _style == "xbox":
		items.append(["back", "Close"])
	var first := true
	for it in items:
		if not first and str(it[0]) != "r1":
			var gap := Control.new()
			gap.custom_minimum_size.x = 22
			_hints.add_child(gap)
		first = false
		var a := str(it[0])
		if a.begins_with("chip:"):
			_hints.add_child(_chip(a.substr(5)))
		else:
			_hints.add_child(TephraGlyphs.glyph(a, 34))
		if str(it[1]) != "":
			_hints.add_child(_label(str(it[1]), 22, MUTED))

func _chip(t: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.0)
	sb.set_border_width_all(2)
	sb.border_color = Color(TEXT, 0.7)
	sb.set_corner_radius_all(Themes.r(16))
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(t, 20, TEXT))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

# ---------- Text ----------
func _shown_text() -> String:
	if _secret and not _shown:
		return "•".repeat(_text.length())
	return _text

func _refresh_text() -> void:
	var s := _shown_text()
	_before.text = s.substr(0, _cursor)
	_after.text = s.substr(_cursor)
	_blink = 0.0
	_caret.modulate.a = 1.0

func _insert(ch: String) -> void:
	if _text.length() >= _max_len:
		_set_status("That's as long as it can be (%d characters)" % _max_len, BAD)
		return
	_text = _text.insert(_cursor, ch)
	_cursor += ch.length()
	_set_status("", MUTED)
	_refresh_text()

func _backspace() -> void:
	if _cursor <= 0:
		return
	_text = _text.substr(0, _cursor - 1) + _text.substr(_cursor)
	_cursor -= 1
	_set_status("", MUTED)
	_refresh_text()

# ---------- The phone link types here (phone_link.gd) ----------
## What the phone's page shows: whether a text box is waiting, its title, what is typed so far.
func phone_state() -> Dictionary:
	return {"open": is_open, "title": _title.text if is_open else "", "text": _text if is_open else "", "secret": _secret, "max": _max_len}

## The phone typed: this is now the text (cut to the longest allowed).
func phone_set(text: String) -> void:
	if not is_open:
		return
	_text = text.substr(0, _max_len)
	_cursor = _text.length()
	_set_status("", MUTED)
	_refresh_text()

## The phone pressed Done. Returns what is wrong ("" when it went through).
func phone_submit() -> String:
	if not is_open:
		return "Nothing is waiting for text any more."
	if _text.length() < _min_len:
		return "Needs at least %d characters" % _min_len
	_submit()
	return ""

func _submit() -> void:
	if _text.length() < _min_len:
		_set_status("Needs at least %d characters" % _min_len, BAD)
		return
	var cb := _done
	var t := _text
	close(true)
	if cb.is_valid():
		cb.call(t)

func _press(k: Dictionary) -> void:
	match str(k["kind"]):
		"char":
			var ch: String = k["value"]
			if _shift > 0:
				ch = ch.to_upper()
			_insert(ch)
			if _shift == 1:
				_shift = 0
				_refresh_keys()
		"shift":
			_shift = (_shift + 1) % 3
			_refresh_keys()
		"back":
			_backspace()
		"space":
			_insert(" ")
		"text":
			_insert(str(k["value"]))
		"cur_l":
			_cursor = maxi(_cursor - 1, 0)
			_refresh_text()
		"cur_r":
			_cursor = mini(_cursor + 1, _text.length())
			_refresh_text()
		"sym":
			_page = "sym" if _page == "abc" else "abc"
			_build_keys()
		"done":
			_submit()
		"phone":
			phone_requested.emit()

func _cycle_shift() -> void:
	_shift = (_shift + 1) % 3
	_refresh_keys()

# ---------- Input (called by home.gd) ----------
## D-pad / stick step.
func move(dir: Vector2i) -> void:
	if not is_open:
		return
	if dir.x != 0:
		_sel.y = posmod(_sel.y + dir.x, _rows[_sel.x].size())
		_pref_x = _center(_sel)
	elif dir.y != 0:
		var r := posmod(_sel.x + dir.y, _rows.size())
		if r == _sel.x:
			return
		var best := 0
		var best_d := 1e9
		for c in _rows[r].size():
			var d := absf(_center(Vector2i(r, c)) - _pref_x)
			if d < best_d:
				best_d = d
				best = c
		_sel = Vector2i(r, best)
	_refresh_keys()

## Returns true when the keyboard used the event (it swallows everything while open).
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event is InputEventKey:
		_key_event(event)
		return true
	if event is InputEventJoypadMotion:
		_stick_dev = event.device
		# The triggers follow each console's own keyboard: PS L2 Shift / R2 Done, Xbox LT symbols, Switch ZL Shift.
		if event.axis == JOY_AXIS_TRIGGER_LEFT or event.axis == JOY_AXIS_TRIGGER_RIGHT:
			var ti := 0 if event.axis == JOY_AXIS_TRIGGER_LEFT else 1
			var down: bool = event.axis_value > 0.6
			if down and not _trig[ti]:
				if ti == 0:
					if _style == "xbox":
						_press({"kind": "sym"})  # LT: the symbols page
					else:
						_cycle_shift()  # L2 / ZL: Shift
				elif _style == "ps":
					_submit()  # R2: Done
			_trig[ti] = down
		return true
	if event is InputEventJoypadButton:
		_stick_dev = event.device
		var b: int = event.button_index
		var nin := _style == "nintendo"
		var del_b := (JOY_BUTTON_A if nin else TephraGlyphs.west_button())  # Switch: B (the bottom button); else Square / X
		if not event.pressed:
			if b == del_b:
				_del_dev = -1
			return true
		if b == del_b:
			_backspace()
			_del_dev = event.device
			_del_t = 0.0
			_del_next = 0.4
			return true
		if b == TephraGlyphs.west_button() and nin:
			close(false)  # Switch: X cancels (Tephra's "west" action is the Switch's X)
		elif b == TephraGlyphs.north_button():
			_insert(" ")  # Switch Y / PS Triangle / Xbox Y: space
		elif b == JOY_BUTTON_LEFT_STICK and _style == "xbox":
			_cycle_shift()  # Xbox: L3 is Shift
		elif b == JOY_BUTTON_LEFT_SHOULDER:
			_cursor = maxi(_cursor - 1, 0)
			_refresh_text()
		elif b == JOY_BUTTON_RIGHT_SHOULDER:
			_cursor = mini(_cursor + 1, _text.length())
			_refresh_text()
		elif b == JOY_BUTTON_RIGHT_STICK and _secret:
			_shown = not _shown
			_refresh_text()
		elif b == JOY_BUTTON_START:
			_submit()
		elif event.is_action_pressed("ui_cancel") and not nin:
			close(false)
		elif event.is_action_pressed("ui_accept"):
			Haptics.confirm()
			_press(_rows[_sel.x][_sel.y])
		return true
	return true

func _key_event(event: InputEventKey) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			close(false)
		KEY_ENTER, KEY_KP_ENTER:
			_submit()
		KEY_BACKSPACE:
			_backspace()
		KEY_DELETE:
			if _cursor < _text.length():
				_text = _text.substr(0, _cursor) + _text.substr(_cursor + 1)
				_refresh_text()
		KEY_HOME:
			_cursor = 0
			_refresh_text()
		KEY_END:
			_cursor = _text.length()
			_refresh_text()
		_:
			if event.unicode >= 32 and event.unicode != 127 and not event.ctrl_pressed and not event.alt_pressed:
				_insert(String.chr(event.unicode))

func _process(delta: float) -> void:
	if not is_open:
		return
	# The right stick slides the keyboard around the screen.
	var dev := _stick_dev if _stick_dev >= 0 else TephraGlyphs.primary_device()
	if dev >= 0:
		var sv := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if sv.length() > 0.25:
			_offset += sv * 900.0 * delta
			_place()
	_blink += delta
	if _blink >= 0.55:
		_blink = 0.0
		_caret.modulate.a = 0.0 if _caret.modulate.a > 0.5 else 1.0
	# Hold the delete button to keep deleting.
	if _del_dev >= 0:
		if Input.is_joy_button_pressed(_del_dev, (JOY_BUTTON_A if _style == "nintendo" else TephraGlyphs.west_button()) as JoyButton):
			_del_t += delta
			if _del_t >= _del_next:
				_del_next = _del_t + 0.06
				_backspace()
		else:
			_del_dev = -1
