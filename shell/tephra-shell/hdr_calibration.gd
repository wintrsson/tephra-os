extends CanvasLayer
## Display calibration, three pages like a console's HDR set-up: black level, white level, and the "barely visible"
## symbol. Up/Down (or Left/Right) make the picture brighter or darker, Accept goes on, Back goes back.
##
## What it can and cannot do, honestly: Tephra draws in SDR, so it cannot show a real HDR highlight. Every test
## picture is made from exact colour codes (no smoothing) so a symbol that is "barely visible" means the same thing
## on every screen. The one control that changes the whole desktop is KDE's "Brightness of non-HDR content"
## (kscreen-doctor, nits), so that is what Up/Down change while HDR is on. With HDR off the pictures are a guide for
## the monitor's own brightness and contrast buttons.

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Motion = preload("res://motion.gd")
const DisplayCtl = preload("res://display_ctl.gd")

const NITS_MIN := 80
const NITS_MAX := 600
const NITS_STEP := 20
const APPLY_DELAY := 0.35   # kscreen-doctor takes a moment: the number moves at once, the screen follows when you pause

# sRGB codes (0-255) of the test pictures. "ref" is clearly visible, "dim" is the one that should be barely visible.
const BLACK_REF := 16
const BLACK_DIM := 6
const WHITE_REF := 235
const WHITE_DIM := 249
const SUN_BG := 14
const SUN_DIM := 22

var is_open := false
var _home
var _view: Control
var _hints: HBoxContainer
var _page := 0
var _nits := 200
var _start_nits := 200
var _hdr := false
var _pending := -1.0   # seconds until the nits are applied, -1 = nothing waiting

func setup(home) -> void:
	_home = home

func _ready() -> void:
	layer = 89
	visible = false
	set_process(false)
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

func open() -> void:
	DisplayCtl.refresh()
	_hdr = DisplayCtl.hdr_supported() and DisplayCtl.hdr_on()
	_nits = clampi(DisplayCtl.sdr_brightness(), NITS_MIN, NITS_MAX)
	_start_nits = _nits
	_page = 0
	_pending = -1.0
	is_open = true
	visible = true
	set_process(true)
	_fill_hints()
	_view.queue_redraw()

func close() -> void:
	if not is_open:
		return
	_apply_now()
	is_open = false
	visible = false
	set_process(false)

func _fill_hints() -> void:
	var items := [["accept", "Done" if _page == 2 else "Next"], ["back", "Back" if _page > 0 else "Cancel"]]
	if _hdr:
		items.insert(1, ["dpad_v", "Brighter / Darker"])
	TephraGlyphs.fill(_hints, items, 26)

func move(dir: Vector2i) -> void:
	var d := -dir.y if dir.y != 0 else dir.x
	if d == 0 or not _hdr:
		return
	var n := clampi(_nits + d * NITS_STEP, NITS_MIN, NITS_MAX)
	if n != _nits:
		_nits = n
		_pending = APPLY_DELAY
		_view.queue_redraw()

func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event.is_action_pressed("ui_accept"):
		if _page >= 2:
			Settings.set_value("display_calibrated", true)
			Settings.set_value("display_calibrated_nits", _nits if _hdr else 0)
			close()
		else:
			_page += 1
			_fill_hints()
			_view.queue_redraw()
	elif event.is_action_pressed("ui_cancel"):
		if _page > 0:
			_page -= 1
			_fill_hints()
			_view.queue_redraw()
		else:
			_nits = _start_nits  # cancelled: back to how it was
			_pending = 0.0
			close()
	return true

func _process(delta: float) -> void:
	if _pending >= 0.0:
		_pending -= delta
		if _pending <= 0.0:
			_apply_now()

func _apply_now() -> void:
	_pending = -1.0
	if _hdr and _nits != DisplayCtl.sdr_brightness():
		DisplayCtl.set_sdr_brightness(_nits)

# ---------- Drawing ----------
static func _g(code: int) -> Color:
	var v := code / 255.0
	return Color(v, v, v, 1.0)

## The sun: a ring with eight blocks around it (the symbol a PlayStation shows).
func _sun(c: Vector2, r: float, col: Color) -> void:
	_view.draw_arc(c, r * 0.62, 0.0, TAU, 96, col, r * 0.2, false)
	for i in 8:
		var a := i * TAU / 8.0
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var p0 := c + dir * r * 0.88
		var p1 := c + dir * r * 1.12
		var w := r * 0.085
		_view.draw_colored_polygon(PackedVector2Array([p0 + side * w, p1 + side * w, p1 - side * w, p0 - side * w]), col)

## A double ring with small marks, a stand-in for a detailed emblem.
func _emblem(c: Vector2, r: float, col: Color) -> void:
	_view.draw_arc(c, r, 0.0, TAU, 96, col, r * 0.07, false)
	_view.draw_arc(c, r * 0.68, 0.0, TAU, 96, col, r * 0.07, false)
	for i in 24:
		var a := i * TAU / 24.0
		var dir := Vector2(cos(a), sin(a))
		_view.draw_circle(c + dir * r * 1.0, r * 0.06, col)
		_view.draw_circle(c + dir * r * 0.68, r * 0.04, col)

func _on_draw() -> void:
	var sz := _view.size
	var font := ThemeDB.fallback_font
	var white_page := _page == 1
	var bg := 255 if white_page else (SUN_BG if _page == 2 else 0)
	var fg := _g(0 if white_page else 235)
	var text_col := _g(40 if white_page else 215)
	_view.draw_rect(Rect2(Vector2.ZERO, sz), _g(bg))
	var titles := ["Black level", "White level", "Brightness"]
	var lines := [
		"Make the symbol on the right barely visible. It should only just stand out from the black.",
		"Make the symbol on the right barely visible. It should only just stand out from the white.",
		"One last time: make the symbol barely visible.",
	]
	_view.draw_string(font, Vector2(0, sz.y * 0.12), "%s   %d/3" % [titles[_page], _page + 1], HORIZONTAL_ALIGNMENT_CENTER, sz.x, 44, fg)
	_view.draw_string(font, Vector2(sz.x * 0.1, sz.y * 0.19), lines[_page], HORIZONTAL_ALIGNMENT_CENTER, sz.x * 0.8, 26, text_col)
	var cy := sz.y * 0.5
	var r := minf(sz.x * 0.13, sz.y * 0.24)
	var lc := Vector2(sz.x * 0.3, cy)
	var rc := Vector2(sz.x * 0.7, cy)
	match _page:
		0:
			_emblem(lc, r, _g(BLACK_REF))
			_emblem(rc, r, _g(BLACK_DIM))
		1:
			_emblem(lc, r, _g(WHITE_REF))
			_emblem(rc, r, _g(WHITE_DIM))
		_:
			var box := Rect2(sz.x * 0.5 - r * 1.5, cy - r * 1.5, r * 3.0, r * 3.0)
			_view.draw_rect(box, _g(SUN_BG + 6), false, 3.0)
			_sun(box.get_center(), r, _g(SUN_DIM))
	var note: String
	if _hdr:
		note = "Brightness of non-HDR content: %d nits" % _nits
	elif DisplayCtl.hdr_supported():
		note = "HDR is off. Use your monitor's brightness and contrast buttons, or turn HDR on in Settings to adjust it here."
	else:
		note = "This display doesn't report HDR. Use your monitor's brightness and contrast buttons."
	_view.draw_string(font, Vector2(0, sz.y * 0.8), note, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 26, text_col)
	if _page == 2:
		_view.draw_string(font, Vector2(sz.x * 0.1, sz.y * 0.86), "Tephra draws in SDR, so this sets how bright everything looks, not the HDR peak.", HORIZONTAL_ALIGNMENT_CENTER, sz.x * 0.8, 20, text_col)
