extends CanvasLayer
## Colour picker. Up/Down choose Hue, Saturation or Brightness, Left/Right change it.
## The controller's lightbar shows the colour while you choose. Accept keeps it, Back cancels.

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Motion = preload("res://motion.gd")

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var SELECT: Color = Themes.c("select")

var is_open := false
var _home
var _view: Control
var _title := "Colour"
var _cb := Callable()
var _h := 0.6
var _s := 0.7
var _v := 0.9
var _row := 0
var _hints: HBoxContainer

func setup(home) -> void:
	_home = home

func _ready() -> void:
	layer = 89
	visible = false
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.draw.connect(_on_draw)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	_view.add_child(_hints)
	_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hints.offset_top = -90
	_hints.offset_right = -80

func color() -> Color:
	return Color.from_hsv(_h, _s, _v)

## Opens the picker on `initial`. `cb` is called with the chosen Color when you accept.
func open(initial: Color, title: String, cb: Callable) -> void:
	_title = title
	_cb = cb
	_h = initial.h
	_s = initial.s
	_v = maxf(initial.v, 0.15)
	_row = 0
	is_open = true
	visible = true
	TephraGlyphs.fill(_hints, [["accept", "Use this colour"], ["dpad_v", "Choose"], ["dpad_h", "Change"], ["back", "Cancel"]], 26)
	Motion.pop(_view, 0.97, 0.2)
	_preview()
	_view.queue_redraw()

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if _home != null and _home.alert != null:
		_home.alert.clear_preview()

func move(dir: Vector2i) -> void:
	if dir.y != 0:
		_row = clampi(_row + dir.y, 0, 2)
	elif dir.x != 0:
		match _row:
			0:
				_h = fposmod(_h + dir.x * 0.01389, 1.0)  # 5 degrees
			1:
				_s = clampf(_s + dir.x * 0.05, 0.0, 1.0)
			2:
				_v = clampf(_v + dir.x * 0.05, 0.1, 1.0)
		_preview()
	_view.queue_redraw()

func _preview() -> void:
	if _home != null and _home.alert != null:
		_home.alert.set_preview(color())

func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event.is_action_pressed("ui_accept"):
		var c := color()
		close()
		if _cb.is_valid():
			_cb.call(c)
	elif event.is_action_pressed("ui_cancel"):
		close()
	return true

func _on_draw() -> void:
	var sz := _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, sz), Color(Themes.c("bg"), 0.88))
	var font := ThemeDB.fallback_font
	var cx := sz.x / 2.0
	var top := sz.y / 2.0 - 230.0
	_view.draw_string(font, Vector2(cx - 340, top), _title, HORIZONTAL_ALIGNMENT_CENTER, 680, 34, TEXT)
	# Preview swatch
	var c := color()
	_view.draw_rect(Rect2(cx - 340, top + 30, 680, 90), c)
	_view.draw_string(font, Vector2(cx - 340, top + 150), "#" + c.to_html(false).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 680, 24, MUTED)
	var names := ["Hue", "Saturation", "Brightness"]
	for i in 3:
		var y := top + 190 + i * 74
		var on := i == _row
		_view.draw_string(font, Vector2(cx - 340, y), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, TEXT if on else MUTED)
		var bar := Rect2(cx - 340, y + 10, 680, 22)
		var steps := 48
		for k in steps:
			var t := float(k) / float(steps - 1)
			var col: Color
			match i:
				0: col = Color.from_hsv(t, 1.0, 1.0)
				1: col = Color.from_hsv(_h, t, _v)
				_: col = Color.from_hsv(_h, _s, lerpf(0.1, 1.0, t))
			_view.draw_rect(Rect2(bar.position.x + bar.size.x * k / steps, bar.position.y, bar.size.x / steps + 1.0, bar.size.y), col)
		var val := _h if i == 0 else (_s if i == 1 else inverse_lerp(0.1, 1.0, _v))
		var px := bar.position.x + bar.size.x * val
		var w := 14.0 if on else 9.0
		_view.draw_rect(Rect2(px - w / 2.0, bar.position.y - 6, w, bar.size.y + 12), SELECT if on else Themes.ink(0.6))
