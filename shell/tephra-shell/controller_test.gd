extends CanvasLayer
## Controller test. Draws a big picture of the controller that is actually in use (DualSense, DualShock 4,
## Xbox or Nintendo style: it switches by itself when you pick up another pad) and lights up every button,
## both sticks (with the dead zone) and both triggers as you press them. Squeeze L2 / R2 to feel the two
## rumble motors. Hold Back for a second to leave.

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const Haptics = preload("res://haptics.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Motion = preload("res://motion.gd")
const Icons = preload("res://icons.gd")

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
const GREEN := Color("46D17B")
const DARKC := Color("121A24")

# What each button is called on each kind of pad. Godot names buttons by position (A = bottom, B = right,
# X = left, Y = top), so the names here are the ones printed on the real controller.
const NAMES := {
	"ds5": {"bottom": "Cross", "right": "Circle", "left": "Square", "top": "Triangle", "l1": "L1", "r1": "R1", "l2": "L2", "r2": "R2",
		"select": "Create", "start": "Options", "guide": "PS", "touch": "Touchpad", "pad": "DualSense"},
	"ds4": {"bottom": "Cross", "right": "Circle", "left": "Square", "top": "Triangle", "l1": "L1", "r1": "R1", "l2": "L2", "r2": "R2",
		"select": "Share", "start": "Options", "guide": "PS", "touch": "Touchpad", "pad": "DualShock 4"},
	"xbox": {"bottom": "A", "right": "B", "left": "X", "top": "Y", "l1": "LB", "r1": "RB", "l2": "LT", "r2": "RT",
		"select": "View", "start": "Menu", "guide": "Guide", "touch": "", "pad": "Xbox-style controller"},
	"nintendo": {"bottom": "B", "right": "A", "left": "Y", "top": "X", "l1": "L", "r1": "R", "l2": "ZL", "r2": "ZR",
		"select": "Minus", "start": "Plus", "guide": "Home", "touch": "", "pad": "Nintendo-style controller"},
}

var is_open := false
var _home
var _view: Control
var _dev := -1
var _model := "generic"
var _model_dev := -2   # the device the cached model belongs to
var _hold := 0.0
var _hold_row: HBoxContainer
var _ring: CenterContainer
const HOLD_WAIT := 1.0   # Circle must be held this long before the ring even starts: leaving is never an accident
const HOLD_FILL := 1.0

## How full the "hold to close" ring is, 0..1.
func _fill() -> float:
	return clampf((_hold - HOLD_WAIT) / HOLD_FILL, 0.0, 1.0)

func _make_hold_row() -> void:
	for c in _hold_row.get_children():
		_hold_row.remove_child(c)
		if c != _ring:
			c.queue_free()
	for c in _ring.get_children():
		_ring.remove_child(c)
		c.queue_free()
	var a := Label.new()
	a.text = "Hold"
	a.add_theme_font_size_override("font_size", 24)
	a.add_theme_color_override("font_color", TEXT)
	_hold_row.add_child(a)
	# The back button's own icon, with the ring filling up around it while it is held.
	var gl: Control = TephraGlyphs.glyph("back", 36)
	_ring.add_child(gl)
	_hold_row.add_child(_ring)
	var b := Label.new()
	b.text = "to close"
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", TEXT)
	_hold_row.add_child(b)

func setup(home) -> void:
	_home = home

func _ready() -> void:
	layer = 88
	visible = false
	set_process(false)
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.draw.connect(_on_draw)
	# "Hold (Circle) to close", with the controller's own glyph and a ring that fills while it is held.
	_hold_row = HBoxContainer.new()
	_hold_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_row.add_theme_constant_override("separation", 14)
	add_child(_hold_row)
	_ring = CenterContainer.new()  # the back icon sits in the middle; the ring is drawn round it
	_ring.custom_minimum_size = Vector2(52, 52)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(func() -> void:
		var c := _ring.size * 0.5
		var held := _fill()
		if held > 0.0:
			var rad := maxf(_ring.size.x, _ring.size.y) * 0.5 - 2.0
			_ring.draw_arc(c, rad, -PI / 2.0, -PI / 2.0 + TAU * held, 48, GREEN, 4.0, true))

func open() -> void:
	_dev = TephraGlyphs.primary_device()
	_model_dev = -2
	_hold = 0.0
	_make_hold_row()
	is_open = true
	visible = true
	set_process(true)
	Motion.pop(_view, 0.97, 0.2)

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	set_process(false)
	Haptics.stop()

func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	return true  # the test eats every button, so pressing things never navigates

func _process(delta: float) -> void:
	if not is_open:
		return
	_dev = TephraGlyphs.primary_device()  # follows whichever controller you used last
	if _dev != _model_dev:
		_model_dev = _dev
		_model = TephraGlyphs.model_for_device(_dev) if _dev >= 0 else "generic"
	if Input.is_action_pressed("ui_cancel"):
		_hold += delta
		if _hold >= HOLD_WAIT + HOLD_FILL:
			close()
			return
	else:
		_hold = 0.0
	if _dev >= 0:
		var lt := Input.get_joy_axis(_dev, JOY_AXIS_TRIGGER_LEFT)
		var rt := Input.get_joy_axis(_dev, JOY_AXIS_TRIGGER_RIGHT)
		if lt > 0.05 or rt > 0.05:
			Haptics.raw(clampf(lt, 0.0, 1.0), clampf(rt, 0.0, 1.0), 0.1)  # L2 = light motor, R2 = heavy motor
	_view.queue_redraw()
	_ring.queue_redraw()
	var vs := _view.size
	_hold_row.position = Vector2(maxf(60.0, vs.x * 0.06), vs.y - 100.0)

# Press, hold or tap: when each button went down, and its recent presses.
const HOLD_AFTER := 0.45  # held this long (seconds) = Holding
const TAP_GAP := 0.5      # pressed again within this long = Tapping
var _since := {}          # button -> when it went down (ms)
var _taps := {}           # button -> [when it went down, ...], recent ones only

## Which word goes above the list ("Pressing", "Holding" or "Tapping") and the buttons it covers. A button you
## are tapping stays listed in the short gaps between taps.
func _press_states(pressed: PackedStringArray) -> Array:
	var now := Time.get_ticks_msec()
	var held := {}
	for label in pressed:
		var key := label.get_slice(" ", 0) if label.ends_with("%") else label  # "R2 40%" is still R2
		held[key] = label
		if not _since.has(key):
			_since[key] = now
			var t: Array = _taps.get(key, [])
			t.append(now)
			_taps[key] = t
	for key in _since.keys():
		if not held.has(key):
			_since.erase(key)
	var tapping: PackedStringArray = []
	var holding: PackedStringArray = []
	for key in _taps.keys():
		var t: Array = _taps[key].filter(func(ms: int) -> bool: return now - ms < 1500)
		if t.is_empty():
			_taps.erase(key)
			continue
		_taps[key] = t
		var last: int = t[-1]
		var gap_ok := held.has(key) or now - last < TAP_GAP * 1000.0
		if t.size() >= 2 and gap_ok and (t[-1] - t[-2]) < TAP_GAP * 1000.0 and not (held.has(key) and now - int(_since[key]) > HOLD_AFTER * 1000.0):
			tapping.append(held.get(key, key))
	for key in held.keys():
		if now - int(_since[key]) >= HOLD_AFTER * 1000.0:
			holding.append(held[key])
	if not tapping.is_empty():
		return ["Tapping", tapping]
	if not holding.is_empty() and holding.size() == pressed.size():
		return ["Holding", holding]
	return ["Pressing", pressed]

func _down(btn: int) -> bool:
	return _dev >= 0 and Input.is_joy_button_pressed(_dev, btn)

func _on_draw() -> void:
	var sz := _view.size
	var font := ThemeDB.fallback_font
	_view.draw_rect(Rect2(Vector2.ZERO, sz), Color(Themes.c("bg"), 0.94))
	var left := maxf(60.0, sz.x * 0.06)
	var names: Dictionary = NAMES.get(_model, NAMES["xbox"])
	var joy_name := Input.get_joy_name(_dev) if _dev >= 0 else "No controller connected"
	_view.draw_string(font, Vector2(left, 120), "Controller test", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, TEXT)
	_view.draw_string(font, Vector2(left, 162), ("%s  -  %s" % [names["pad"], joy_name]) if _dev >= 0 else joy_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, MUTED)
	if _dev < 0:
		return
	var lay := Icons.pad_layout(_model)
	var px := minf(800.0, sz.x * 0.45)   # width of the picture
	var k := px / 48.0                    # screen pixels per picture unit
	var org := Vector2(left, 210.0)
	var tex := Icons.texture("padbig_%s_%d" % [_model, int(px)], Icons.svg_pad(_model), int(px))
	_view.draw_texture(tex, org, Color(1, 1, 1, 0.9))
	var P := func(v: Vector2) -> Vector2: return org + v * k
	var pressed: PackedStringArray = []
	# Shoulder buttons (L1 / R1) and triggers (L2 / R2, shown filling up).
	for side in 2:
		var key1 := "l1" if side == 0 else "r1"
		var key2 := "l2" if side == 0 else "r2"
		var r1: Rect2 = lay[key1]
		var on1 := _down(JOY_BUTTON_LEFT_SHOULDER if side == 0 else JOY_BUTTON_RIGHT_SHOULDER)
		_view.draw_rect(Rect2(P.call(r1.position), r1.size * k), GREEN if on1 else Color(1, 1, 1, 0.3), true)
		if on1:
			pressed.append(names[key1])
		var r2: Rect2 = lay[key2]
		var tv := clampf(Input.get_joy_axis(_dev, JOY_AXIS_TRIGGER_LEFT if side == 0 else JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)
		var rr := Rect2(P.call(r2.position), r2.size * k)
		_view.draw_rect(rr, Color(1, 1, 1, 0.14), true)
		_view.draw_rect(Rect2(rr.position, Vector2(rr.size.x * tv, rr.size.y)), GREEN, true)
		if tv > 0.05:
			pressed.append("%s %d%%" % [names[key2], int(tv * 100.0)])
		var lbl_x := rr.position.x if side == 0 else rr.end.x - 60.0
		_view.draw_string(font, Vector2(lbl_x, rr.position.y - 6.0), names[key2] + " / " + names[key1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MUTED)
	# Face buttons: bottom, right, left, top (named for this pad).
	var fc: Vector2 = lay["face"]
	var g: float = lay["face_gap"]
	var faces := [["bottom", JOY_BUTTON_A, Vector2(0, g)], ["right", JOY_BUTTON_B, Vector2(g, 0)], ["left", JOY_BUTTON_X, Vector2(-g, 0)], ["top", JOY_BUTTON_Y, Vector2(0, -g)]]
	for f in faces:
		var c: Vector2 = P.call(fc + f[2])
		var on := _down(f[1])
		var fr: float = lay["face_r"] * k
		_view.draw_circle(c, fr, GREEN if on else DARKC)
		_view.draw_arc(c, fr, 0.0, TAU, 24, Color(1, 1, 1, 0.5), 2.0)
		if _model == "xbox" or _model == "nintendo" or _model == "generic":
			_view.draw_string(font, c + Vector2(-fr, 0.45 * fr), names[f[0]], HORIZONTAL_ALIGNMENT_CENTER, 2.0 * fr, int(1.3 * fr), Color.BLACK if on else TEXT)
		if on:
			pressed.append(names[f[0]])
	# D-pad: drawn exactly over the cross in the picture (Icons.dpad_parts): the arm you press lights up.
	var parts: Array = Icons.dpad_parts(lay)
	var lit := {"Up": _down(JOY_BUTTON_DPAD_UP), "Down": _down(JOY_BUTTON_DPAD_DOWN), "Left": _down(JOY_BUTTON_DPAD_LEFT), "Right": _down(JOY_BUTTON_DPAD_RIGHT)}
	for part in parts:
		var q: Rect2 = part[1]
		var on: bool = lit.get(part[0], false)
		_view.draw_rect(Rect2(P.call(q.position), q.size * k), GREEN if on else DARKC, true)
	for part in parts:  # pressed arms again on top, so the dark centre never covers their inner end
		if lit.get(part[0], false):
			var q2: Rect2 = part[1]
			_view.draw_rect(Rect2(P.call(q2.position), q2.size * k), GREEN, true)
			pressed.append("D-pad " + part[0])
	for tri in Icons.dpad_arrows(lay):
		_view.draw_colored_polygon(PackedVector2Array([P.call(tri[0]), P.call(tri[1]), P.call(tri[2])]), Color(1, 1, 1, 0.35))
	# Select / Start / Guide / Touchpad.
	var smalls := [["select", JOY_BUTTON_MISC1 if _model == "ds5" else JOY_BUTTON_BACK], ["start", JOY_BUTTON_START], ["guide", JOY_BUTTON_GUIDE]]
	if _model == "ds4":
		smalls[0][1] = JOY_BUTTON_BACK
	for sm in smalls:
		var on := _down(sm[1])
		# On a DualSense, Create may arrive as Select (Back); light for either.
		if sm[0] == "select" and _model == "ds5":
			on = on or _down(JOY_BUTTON_BACK)
		_view.draw_circle(P.call(lay[sm[0]]), 0.8 * k, GREEN if on else Color(0.07, 0.1, 0.14))
		_view.draw_arc(P.call(lay[sm[0]]), 0.8 * k, 0.0, TAU, 16, Color(1, 1, 1, 0.4), 1.5)
		if on:
			pressed.append(names[sm[0]])
	if lay["touch"] != Rect2():
		var t: Rect2 = lay["touch"]
		if _down(JOY_BUTTON_TOUCHPAD):
			_view.draw_rect(Rect2(P.call(t.position), t.size * k), GREEN, true)
			pressed.append(names["touch"])
	# Sticks drawn on the pad: the dot follows the stick, the ring turns green when it is pushed in (L3 / R3).
	var dz := float(Settings.get_value("deadzone", 0.15))
	var sr: float = lay["stick_r_px"] * k
	for s in 2:
		var c: Vector2 = P.call(lay["stick_l"] if s == 0 else lay["stick_r"])
		var ax := Input.get_joy_axis(_dev, JOY_AXIS_LEFT_X if s == 0 else JOY_AXIS_RIGHT_X)
		var ay := Input.get_joy_axis(_dev, JOY_AXIS_LEFT_Y if s == 0 else JOY_AXIS_RIGHT_Y)
		var click := _down(JOY_BUTTON_LEFT_STICK if s == 0 else JOY_BUTTON_RIGHT_STICK)
		_view.draw_arc(c, sr, 0.0, TAU, 32, GREEN if click else Color(1, 1, 1, 0.45), 3.0)
		_view.draw_circle(c + Vector2(ax, ay) * sr * 0.45, sr * 0.5, GREEN if Vector2(ax, ay).length() > dz else Color(1, 1, 1, 0.8))
		if click:
			pressed.append("L3" if s == 0 else "R3")
	# Right-hand side: big stick readouts with the dead zone, so you can see drift.
	var rx := maxf(left + px + 120.0, sz.x * 0.6)
	var radius := 95.0
	var top := 230.0
	var gap2 := maxf(320.0, (sz.x - 60.0 - rx) * 0.5)
	for s in 2:
		var c := Vector2(rx + radius + 10.0 + s * gap2, top + radius + 10.0)
		var ax := Input.get_joy_axis(_dev, JOY_AXIS_LEFT_X if s == 0 else JOY_AXIS_RIGHT_X)
		var ay := Input.get_joy_axis(_dev, JOY_AXIS_LEFT_Y if s == 0 else JOY_AXIS_RIGHT_Y)
		_view.draw_arc(c, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.3), 3.0)
		_view.draw_arc(c, radius * dz, 0.0, TAU, 32, Color(1, 0.6, 0.2, 0.8), 2.0)
		_view.draw_circle(c + Vector2(ax, ay) * radius, 12.0, GREEN if Vector2(ax, ay).length() > dz else Color(1, 1, 1, 0.7))
		_view.draw_string(font, Vector2(c.x - 120, c.y + radius + 34), "%s stick   %.2f, %.2f" % ["Left" if s == 0 else "Right", ax, ay], HORIZONTAL_ALIGNMENT_CENTER, 240, 19, MUTED)
	# What is held right now, in this pad's own words.
	var ty := top + radius * 2.0 + 140.0
	var shown := _press_states(pressed)
	_view.draw_string(font, Vector2(rx, ty), shown[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, MUTED)
	_view.draw_string(font, Vector2(rx, ty + 36), ", ".join(shown[1]) if not shown[1].is_empty() else "-", HORIZONTAL_ALIGNMENT_LEFT, 540, 28, TEXT)
	_view.draw_string(font, Vector2(rx, ty + 120), "Squeeze L2 for the light motor and R2 for the heavy motor.", HORIZONTAL_ALIGNMENT_LEFT, sz.x - rx - 60.0, 20, MUTED)
	_view.draw_string(font, Vector2(rx, ty + 150), "The orange ring is the dead zone.", HORIZONTAL_ALIGNMENT_LEFT, sz.x - rx - 60.0, 20, MUTED)
