extends CanvasLayer
const TephraGlyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const Rounded = preload("res://rounded.gd")
## Tephra's own "Install this game?" screen, shown before anything is handed to Steam.
## It shows the game's art, how big it is, how much room the drive has and where it will go.
## The size comes from the game's Steam store page (its listed "Storage" requirement),
## so it is an estimate; Steam's real number appears on the tile once the download starts.

signal confirmed(game: Dictionary)
signal cancelled

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
const WARN := Color("F0A35A")
const BAD := Color("E8645A")
const STORE_URL := "https://store.steampowered.com/api/appdetails?appids=%s&filters=pc_requirements&l=english"

var is_open := false

var _game := {}
var _root: Control
var _dim: ColorRect
var _panel: Panel
var _art: TextureRect
var _title: Label
var _size_val: Label
var _free_val: Label
var _where_val: Label
var _note: Label
var _hints: HBoxContainer
var _req: HTTPRequest
var _need := 0.0     # bytes the game needs (0 = unknown)
var _free := 0.0     # bytes free on the drive
var _can_install := true
var _busy := false   # true once Install was pressed: showing progress until Steam accepts it

func _ready() -> void:
	layer = 86  # above the Library (80), below the launch screen (90)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Themes.dim(0.72)
	_root.add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Themes.c("panel")
	sb.set_corner_radius_all(Themes.r(22))
	sb.border_color = Themes.ink(0.10)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 40
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(1120, 560)
	_root.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -560
	_panel.offset_right = 560
	_panel.offset_top = -290
	_panel.offset_bottom = 290
	_panel.pivot_offset = Vector2(560, 290)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	_panel.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 40
	row.offset_right = -40
	row.offset_top = 40
	row.offset_bottom = -30

	_art = TextureRect.new()
	_art.custom_minimum_size = Vector2(300, 450)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	Rounded.apply(_art, Vector2(300, 450), 16.0)
	row.add_child(_art)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	row.add_child(col)
	var head := _label("Install", 24, MUTED)
	col.add_child(head)
	_title = _label("", 46, TEXT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.max_lines_visible = 2
	col.add_child(_title)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	col.add_child(gap)
	_size_val = _info_row(col, "Download size")
	_free_val = _info_row(col, "Free space")
	_where_val = _info_row(col, "Install to")
	_note = _label("", 20, MUTED)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_note.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	col.add_child(_note)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(_hints)

	_req = HTTPRequest.new()
	_req.timeout = 8.0
	add_child(_req)
	_req.request_completed.connect(_on_store)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _info_row(parent: Control, name: String) -> Label:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var k := _label(name, 26, MUTED)
	k.custom_minimum_size.x = 250
	h.add_child(k)
	var v := _label("", 30, TEXT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.clip_text = true
	h.add_child(v)
	return v

# ---------- Open / close ----------
## game = {id, title}; cover = the tile's cover texture (may be null); lib_path = the Steam
## library the game will be installed to.
func open(game: Dictionary, cover: Texture2D, lib_path: String) -> void:
	_game = game
	_busy = false
	_art.texture = cover
	_title.text = str(game["title"])
	_size_val.text = "Checking..."
	_size_val.add_theme_color_override("font_color", TEXT)
	_need = 0.0
	_free = _free_bytes(lib_path)
	_where_val.text = lib_path.replace(OS.get_environment("HOME"), "~")
	_note.text = "Installing means you accept the Steam Subscriber Agreement and this game's license terms. Tephra confirms them for you."
	_update_free()
	_refresh_hints()
	is_open = true
	_root.visible = true
	_root.modulate.a = 0.0
	Motion.fade_to(_root, 1.0, 0.2)
	Motion.pop(_panel, 0.95, 0.22)
	_req.cancel_request()
	_req.request(STORE_URL % str(game["id"]))

func close() -> void:
	if not is_open:
		return
	is_open = false
	_req.cancel_request()
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, Motion.dur(0.15))
	await t.finished
	if not is_open:
		_root.visible = false

func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event is InputEventJoypadMotion:
		return true
	if event.is_action_pressed("ui_cancel"):
		Haptics.tick()
		close()
		cancelled.emit()
	elif event.is_action_pressed("ui_accept"):
		if _can_install and not _busy:
			_busy = true
			_note.text = "Starting Steam..."
			_note.add_theme_color_override("font_color", TEXT)
			_refresh_hints()
			confirmed.emit(_game)
		else:
			Haptics.tick()
	return true

# The buttons are always shown on this card (even when button hints are switched off in
# Settings), because it is the one place where nothing happens until you press one.
func _refresh_hints() -> void:
	for c in _hints.get_children():
		_hints.remove_child(c)
		c.queue_free()
	_hints.add_theme_constant_override("separation", 14)
	var items: Array = []
	if _busy:
		items.append(["back", "Hide"])
	else:
		if _can_install:
			items.append(["accept", "Install"])
		items.append(["back", "Cancel"])
	var first := true
	for item in items:
		if not first:
			var gap := Control.new()
			gap.custom_minimum_size.x = 34
			_hints.add_child(gap)
		first = false
		_hints.add_child(TephraGlyphs.glyph(item[0], 44))
		_hints.add_child(_label(item[1], 30, TEXT))

## Progress line shown after Install was pressed (called by the Library while Steam gets going).
func set_status(text: String) -> void:
	if is_open and _busy:
		_note.text = text

## Steam accepted the download: say so for a moment, then close.
func finish() -> void:
	if not is_open or not _busy:
		return
	_note.text = "Download started. You can follow it on the tile."
	await get_tree().create_timer(1.4).timeout
	if _busy:
		close()

# ---------- Size and space ----------
func _on_store(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_need = 0.0
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_need = need_from_store_json(body.get_string_from_utf8(), str(_game.get("id", "")))
	if _need > 0.0:
		_size_val.text = "About " + fmt_bytes(_need)
	else:
		_size_val.text = "Shown by Steam once it starts"
	_update_free()

func _update_free() -> void:
	_free_val.text = fmt_bytes(_free) if _free > 0.0 else "Unknown"
	_free_val.add_theme_color_override("font_color", TEXT)
	_can_install = true
	if _need > 0.0 and _free > 0.0:
		if _need > _free:
			_free_val.text += "   (not enough room)"
			_free_val.add_theme_color_override("font_color", BAD)
			_can_install = false
		elif _free - _need < _need * 0.15 + 2.0e9:
			_free_val.text += "   (almost full afterwards)"
			_free_val.add_theme_color_override("font_color", WARN)
	_refresh_hints()

static func _free_bytes(path: String) -> float:
	var out := []
	if OS.execute("df", ["-B1", "--output=avail", path], out) != 0 or out.is_empty():
		return 0.0
	var lines: PackedStringArray = str(out[0]).strip_edges().split("\n")
	return float(lines[lines.size() - 1].strip_edges().to_int()) if lines.size() > 1 else 0.0

## Reads the "Storage: 60 GB available space" line out of a store appdetails reply.
## Returns bytes, or 0.0 when the store page doesn't say.
static func need_from_store_json(text: String, appid: String) -> float:
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has(appid):
		return 0.0
	var entry = data[appid]
	if typeof(entry) != TYPE_DICTIONARY or not entry.get("success", false):
		return 0.0
	var d = entry.get("data", {})
	if typeof(d) != TYPE_DICTIONARY:
		return 0.0
	var reqs = d.get("pc_requirements", {})
	if typeof(reqs) != TYPE_DICTIONARY:  # the store sends [] when it has nothing
		return 0.0
	var best := 0.0
	for key in ["minimum", "recommended"]:
		var html := str(reqs.get(key, ""))
		if html == "":
			continue
		var tag := RegEx.new()
		tag.compile("<[^>]*>")
		var plain := tag.sub(html.replace("<br>", "\n").replace("</li>", "\n"), "", true)
		var re := RegEx.new()
		re.compile("(?i)(?:storage|hard\\s*(?:disk|drive)(?:\\s*space)?|disk\\s*space)\\s*:?\\s*([0-9]+(?:[.,][0-9]+)?)\\s*(tb|gb|mb)")
		var m := re.search(plain)
		if m == null:
			continue
		var n := m.get_string(1).replace(",", ".").to_float()
		var mult := 1.0e6
		match m.get_string(2).to_lower():
			"gb": mult = 1.0e9
			"tb": mult = 1.0e12
		best = maxf(best, n * mult)
		if best > 0.0:
			break  # the minimum line is the one we want when it has a size
	return best

static func fmt_bytes(b: float) -> String:
	if b >= 1.0e12:
		return "%.1f TB" % (b / 1.0e12)
	if b >= 1.0e9:
		return ("%.0f GB" % (b / 1.0e9)) if b >= 1.0e10 else ("%.1f GB" % (b / 1.0e9))
	return "%.0f MB" % (b / 1.0e6)
