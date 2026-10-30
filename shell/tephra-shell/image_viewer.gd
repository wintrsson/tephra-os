extends Control
## Image viewer for Files: a picture fills the screen. Left/Right (or L1/R1) step through the pictures in the same
## folder, Cross zooms (fit, 2x, 4x), the D-pad pans while zoomed, Circle closes.

signal closed
signal hints_changed

const Themes = preload("res://themes.gd")
const Glyphs = preload("res://glyphs.gd")
const EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga"]
const MAX_SIDE := 8192
const ZOOMS := [1.0, 2.0, 4.0]

var is_open := false
var _paths: Array = []
var _idx := 0
var _tex: Texture2D
var _zoom := 0
var _pan := Vector2.ZERO
var _name: Label
var _msg: Label

static func is_image(path: String) -> bool:
	return path.get_extension().to_lower() in EXTS

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	visible = false
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 24)
	_name.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_name.add_theme_constant_override("shadow_offset_x", 2)
	_name.add_theme_constant_override("shadow_offset_y", 2)
	_name.position = Vector2(48, 36)
	add_child(_name)
	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", 28)
	_msg.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_msg)

## Opens `path`; the other pictures in its folder become the Left/Right list.
func open_file(path: String) -> bool:
	_paths = []
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	var names := Array(dir.get_files())
	names.sort_custom(func(a, b) -> bool: return str(a).naturalnocasecmp_to(str(b)) < 0)
	for n in names:
		if is_image(str(n)):
			_paths.append(path.get_base_dir().path_join(str(n)))
	_idx = maxi(_paths.find(path), 0)
	if _paths.is_empty():
		return false
	is_open = true
	visible = true
	_load()
	hints_changed.emit()
	return true

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	_tex = null
	closed.emit()

func hints() -> Array:
	var items: Array = [["dpad", "Next / previous" if _zoom == 0 else "Move around"], ["accept", "Zoom"]]
	items.append(["back", "Close"])
	return items

func _load() -> void:
	var p: String = _paths[_idx]
	_zoom = 0
	_pan = Vector2.ZERO
	_tex = null
	_msg.text = ""
	_name.text = "%s   (%d / %d)" % [p.get_file(), _idx + 1, _paths.size()]
	var img := Image.load_from_file(p)
	if img == null or img.is_empty():
		_msg.text = "Can't open this picture."
	else:
		var big := maxi(img.get_width(), img.get_height())
		if big > MAX_SIDE:
			var f := float(MAX_SIDE) / big
			img.resize(int(img.get_width() * f), int(img.get_height() * f), Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		_tex = ImageTexture.create_from_image(img)
	queue_redraw()

func _step(dir: int) -> void:
	if _paths.size() < 2:
		return
	_idx = (_idx + dir + _paths.size()) % _paths.size()
	_load()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.97))
	if _tex == null:
		return
	var ts := _tex.get_size()
	var fit := minf(size.x / ts.x, size.y / ts.y)
	var s := ts * fit * float(ZOOMS[_zoom])
	_pan = _pan.clamp(-(s - size).max(Vector2.ZERO) / 2.0, (s - size).max(Vector2.ZERO) / 2.0)
	draw_texture_rect(_tex, Rect2((size - s) / 2.0 - _pan, s), false)

func move(dir: int) -> void:
	if _zoom == 0:
		_step(dir)
	else:
		_pan.x += dir * size.x * 0.25
		queue_redraw()

func vertical(dir: int) -> void:
	if _zoom > 0:
		_pan.y += dir * size.y * 0.25
		queue_redraw()

func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_step(-1)
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_step(1)
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_accept"):
		_zoom = (_zoom + 1) % ZOOMS.size()
		_pan = Vector2.ZERO
		queue_redraw()
		hints_changed.emit()
	return true
