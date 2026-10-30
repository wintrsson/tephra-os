extends CanvasLayer
## Small pop-up menus that open under the icons in the top bar:
##   "dev"  - the Tephra icon: developer tools
##   "wifi" - Wi-Fi: on/off, nearby networks, join (with the on-screen keyboard), forget
##   "bt"   - Bluetooth: turn on/off, scan, pair and connect devices
##   "pad"  - your controllers: battery, priority, vibration, dead zone, lightbar, test
## Controllers are never disconnected from here (that could leave you with no way to
## control Tephra), and connected controllers show as "stays connected".

const TephraGlyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
const Settings = preload("res://settings.gd")
const Haptics = preload("res://haptics.gd")

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var CARD_BG: Color = Color(Themes.c("card"), 0.97)
var SELECT: Color = Themes.c("select")
const VISIBLE_ROWS := 7
const Motion = preload("res://motion.gd")
const Icons = preload("res://icons.gd")
const VIB_NAMES := ["Off", "Low", "Medium", "High"]
const LIGHT_MODES := ["theme", "battery", "custom"]
const LIGHT_NAMES := ["Tephra theme", "Battery level", "Custom colour"]

const GLYPH_CHOICES := ["", "ds5", "ds4", "xbox", "nintendo", "keyboard"]
const GLYPH_NAMES := ["Auto-detect", "DualSense (PS5)", "DualShock 4 (PS4)", "Xbox", "Nintendo", "Keyboard"]

signal closed

var is_open := false
var kind := ""
var _home
var _root: Control
var _panel: PanelContainer
var _box: VBoxContainer
var _hints: HBoxContainer
var _rows: Array = []   # [{type, text, value, key, data}]
var _nodes: Array = []  # per row: {panel, style, name, value}
var _sel := 0
var _top := 0           # first row shown (the list scrolls when it is long)
var _anchor := Rect2()
var _dim: ColorRect
var _full := false  # PS2 theme: a full-screen page instead of a pop-up under its icon
var _busy := ""         # what Bluetooth is doing right now ("Scanning...", "Pairing...")
var _bt_devices: Array = []
var _bt_on := false
var _wifi_on := false
var _wifi_name := ""
var _wifi_known := false  # false until the first check has finished
var _wifi_nets: Array = []   # [{ssid, signal, secure, security, saved, active}]
var _wifi_note := ""         # the last thing that happened ("Wrong password...")
var _wifi_scanned := false   # the automatic look for networks after opening has been done
var _scanning := false       # a Wi-Fi scan is running (picking a network still works meanwhile)
var _task := -1
var _more: Label

func setup(home) -> void:
	_home = home

func _ready() -> void:
	Engine.time_scale = 1.0  # slow motion was removed
	layer = 85  # above Library/Profile/Settings (80), below the control center (95)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)
	_dim = ColorRect.new()
	var dim := _dim
	dim.color = Themes.dim(0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.set_corner_radius_all(Themes.r(20))
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_box)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(_hints)
	_hints.anchor_left = 0.0
	_hints.anchor_right = 1.0
	_hints.anchor_top = 1.0
	_hints.anchor_bottom = 1.0
	_hints.offset_left = 80
	_hints.offset_right = -80
	_hints.offset_top = -110
	_hints.offset_bottom = -60

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# ---------- Open / close ----------
## anchor = the icon this menu hangs under (screen coordinates).
func open_menu(menu_kind: String, anchor: Rect2) -> void:
	if is_open:
		return
	kind = menu_kind
	_anchor = anchor
	_full = str(Themes.data().get("layout", "row")) in ["ps2", "xmb", "neon"]
	_dim.color = Themes.dim(0.93 if _full else 0.45)
	is_open = true
	_sel = 0
	_top = 0
	_busy = ""
	_wifi_note = ""
	_wifi_scanned = false
	_scanning = false
	_root.visible = true
	_build()
	if kind == "wifi":
		_read_wifi()
	elif kind == "bt":
		_read_bluetooth()
	Motion.fade_to(_root, 1.0, 0.16)
	_pop_panel.call_deferred()

func _pop_panel() -> void:
	if not is_open:
		return
	_panel.pivot_offset = _panel.size / 2.0 if _full else Vector2(40.0, 0.0)
	if Motion.on():
		_panel.scale = Vector2.ONE * 0.94
		var tw := create_tween()
		tw.tween_property(_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_panel.scale = Vector2.ONE

func close() -> void:
	if not is_open:
		return
	is_open = false
	closed.emit()
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, Motion.dur(0.12))
	await t.finished
	if not is_open:
		_root.visible = false

# ---------- Rows ----------
func _definitions() -> Array:
	var rows: Array = []
	match kind:
		"dev":
			rows.append({"type": "head", "text": "Developer"})
			var gi := GLYPH_CHOICES.find(str(Settings.get_value("glyph_override", "")))
			rows.append({"type": "item", "key": "glyphs", "text": "Button glyphs", "value": GLYPH_NAMES[maxi(gi, 0)]})
			rows.append({"type": "item", "key": "hints", "text": "Button hints", "value": "Shown" if Settings.get_value("show_hints", true) else "Hidden"})
			rows.append({"type": "item", "key": "dev_overlay", "text": "Performance info on every screen", "value": "On" if Settings.get_value("dev_overlay", false) else "Off"})
			rows.append({"type": "item", "key": "dev_under", "text": "Keep Tephra under all apps (troubleshooting)", "value": "On" if Settings.get_value("dev_under", false) else "Off"})
			rows.append({"type": "item", "key": "hide_mods", "text": "Hide Mods (game info button and control center tab)", "value": "Hidden" if Settings.get_value("hide_mods", false) else "Shown"})
			rows.append({"type": "item", "key": "files_show_all", "text": "Files: show hidden and system folders", "value": "On" if Settings.get_value("files_show_all", false) else "Off"})
			rows.append({"type": "item", "key": "refresh_all", "text": "Refresh all", "value": ""})
			rows.append({"type": "item", "key": "view_log", "text": "View log", "value": ""})
			rows.append({"type": "item", "key": "test_toast", "text": "Test notification", "value": ""})
			rows.append({"type": "item", "key": "fake_loading", "text": "Fake loading screen", "value": "Shows the loading messages. Back stops it"})
			var lvl: int = _home.alert.force_level if _home.alert != null else 0
			rows.append({"type": "item", "key": "battery_low", "text": "Test low battery (orange)", "value": "Flashing" if lvl == 1 else "Off"})
			rows.append({"type": "item", "key": "battery_crit", "text": "Test critical battery (red)", "value": "Flashing" if lvl == 2 else "Off"})
			rows.append({"type": "item", "key": "pad_test", "text": "Controller test", "value": ""})
			rows.append({"type": "item", "key": "scene_test", "text": "3D and particle tests", "value": "Cubes, spheres, particles, animation"})
			rows.append({"type": "item", "key": "redo_setup", "text": "Redo first-boot setup", "value": ""})
			rows.append({"type": "item", "key": "phone_test", "text": "Phone link (screenshots)", "value": ""})
			rows.append({"type": "item", "key": "reduce_flashing", "text": "Gentle alerts (no pulsing)", "value": "On" if Settings.get_value("reduce_flashing", false) else "Off"})
			rows.append({"type": "item", "key": "show_fps", "text": "Cap frame rate (Tephra window)", "value": _fps_text()})
			rows.append({"type": "item", "key": "refresh_games", "text": "Re-scan games", "value": ""})
			rows.append({"type": "item", "key": "clear_art", "text": "Clear cover art cache", "value": ""})
			rows.append({"type": "item", "key": "clear_ach", "text": "Clear achievement cache", "value": ""})
			rows.append({"type": "item", "key": "reset_perf", "text": "Reset performance data", "value": ""})
			rows.append({"type": "item", "key": "show_paths", "text": "Show data folder", "value": ""})
			rows.append({"type": "item", "key": "restart_tephra", "text": "Restart Tephra", "value": ""})
		"pad":
			rows.append({"type": "head", "text": "Controllers"})
			var list: Array = _home.controllers.list() if _home.controllers != null else []
			if list.is_empty():
				rows.append({"type": "info", "text": "No controller connected"})
			# One row per controller (P1 is the first to connect). Choose one to put it in charge.
			var boss := TephraGlyphs.in_charge_slot()
			var any_boss := false
			for c in list:
				any_boss = any_boss or int(c["slot"]) == boss
			for c in list:
				var pct := int(c.get("battery", -1))
				var txt := "P%d  %s" % [int(c["slot"]), str(c.get("name", "Controller"))]
				if pct >= 0:
					txt += "  %d%%%s" % [pct, " +" if bool(c.get("charging", false)) else ""]
				var charge: bool = int(c["slot"]) == boss or (not any_boss and c == list[0])
				rows.append({"type": "item", "key": "pad_pick", "text": txt, "value": "In charge" if charge else "",
					"data": {"slot": int(c["slot"])}, "icon": Icons.texture("pad_" + str(c.get("model", c["family"])), Icons.svg_pad(str(c.get("model", c["family"]))), 32)})
			rows.append({"type": "item", "key": "vibration", "text": "Vibration", "value": VIB_NAMES[clampi(int(Settings.get_value("vibration", 2)), 0, 3)]})
			rows.append({"type": "item", "key": "deadzone", "text": "Stick dead zone", "value": "%d%%" % roundi(float(Settings.get_value("deadzone", 0.15)) * 100.0)})
			rows.append({"type": "item", "key": "pad_test", "text": "Test buttons, sticks and vibration", "value": ""})
		"battery":
			rows.append({"type": "head", "text": "Battery"})
			var bat: Dictionary = preload("res://perf.gd").laptop_battery()
			if not bool(bat["has"]):
				rows.append({"type": "info", "text": "This PC has no battery."})
			else:
				var state := "Charging" if bool(bat["charging"]) else ("Fully charged" if bool(bat["full"]) else "Using battery")
				rows.append({"type": "info", "text": "%d%%  -  %s" % [int(bat["pct"]), state]})
				var mins := int(bat["minutes"])
				if mins > 0:
					rows.append({"type": "info", "text": "About %dh %02dmin %s" % [mins / 60, mins % 60, "until full" if bool(bat["charging"]) else "left"]})
			rows.append({"type": "item", "key": "close_menu", "text": "Done", "value": ""})
		"wifi":
			rows.append({"type": "head", "text": "Wi-Fi"})
			if not _wifi_known:
				rows.append({"type": "info", "text": "Checking..."})
			else:
				rows.append({"type": "info", "text": ("Connected to " + _wifi_name) if (_wifi_on and _wifi_name != "") else ("Not connected" if _wifi_on else "Wi-Fi is off")})
			if _busy != "":
				rows.append({"type": "info", "text": _busy})
			elif _wifi_note != "":
				rows.append({"type": "info", "text": _wifi_note})
			rows.append({"type": "item", "key": "wifi_toggle", "text": "Wi-Fi", "value": ("On" if _wifi_on else "Off") if _wifi_known else "..."})
			if _wifi_on:
				rows.append({"type": "item", "key": "wifi_scan", "text": "Look for networks", "value": "Scanning..." if _scanning else ""})
				rows.append({"type": "head", "text": "Networks"})
				if _wifi_nets.is_empty():
					rows.append({"type": "info", "text": "None found yet." if _wifi_scanned else "Looking..."})
				for n in _wifi_nets:
					rows.append({"type": "item", "key": "wifi_net", "text": n["ssid"], "value": _net_value(n), "data": n})
				rows.append({"type": "item", "key": "wifi_hidden", "text": "Other network...", "value": "Hidden or not listed"})
		"bt":
			rows.append({"type": "head", "text": "Bluetooth"})
			rows.append({"type": "item", "key": "bt_toggle", "text": "Bluetooth", "value": "On" if _bt_on else "Off"})
			if _bt_on:
				rows.append({"type": "item", "key": "bt_scan", "text": "Scan for devices", "value": _busy if _busy.begins_with("Scanning") else ""})
				if _busy != "" and not _busy.begins_with("Scanning"):
					rows.append({"type": "info", "text": _busy})
				if _bt_devices.is_empty():
					rows.append({"type": "info", "text": "No devices yet. Put yours in pairing mode, then Scan."})
				for d in _bt_devices:
					var v := "Pair"
					if d["connected"]:
						v = "Connected"
					elif d["paired"]:
						v = "Saved"
					rows.append({"type": "item", "key": "bt_dev", "text": d["name"], "value": v, "data": d, "icon": bt_icon(str(d.get("kind", "")))})
	return rows

func _build() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_more = null
	var keep := _row_identity(_sel) if (kind == "wifi" or kind == "bt") else ""
	_rows = _definitions()
	_nodes.clear()
	if keep != "":  # lists refresh in the background: stay on the same network / device
		for i in _rows.size():
			if _row_identity(i) == keep:
				_sel = i
				break
	# Keep the selection on a row you can actually pick.
	if _sel >= _rows.size() or _rows[_sel]["type"] != "item":
		_sel = _first_item()
	var width := 640 if (kind == "bt" or kind == "wifi") else 520
	if _full:
		width = 1100
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		if r["type"] == "head":
			var h := _label(r["text"], 22, MUTED)
			h.custom_minimum_size = Vector2(width, 34)
			_box.add_child(h)
			_nodes.append({})
			continue
		if r["type"] == "info":
			var l := _label(r["text"], 22, MUTED)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = width
			_box.add_child(l)
			_nodes.append({})
			continue
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(width, 50)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(Themes.r(14))
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		p.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		p.add_child(hb)
		if r.has("icon"):
			hb.add_theme_constant_override("separation", 14)
			var ic := TextureRect.new()
			ic.texture = r["icon"]
			ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(ic)
		var n := _label(r["text"], 24, TEXT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hb.add_child(n)
		var v := _label(r["value"], 22, MUTED)
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(v)
		_box.add_child(p)
		_nodes.append({"panel": p, "style": sb, "name": n, "value": v})
	_refresh()
	_place.call_deferred()

# "key|name" of a row, so the same network / device can be found again after the list is rebuilt.
func _row_identity(i: int) -> String:
	if i < 0 or i >= _rows.size() or not _rows[i].has("key"):
		return ""
	var d = _rows[i].get("data", null)
	var who := ""
	if d is Dictionary:
		who = str(d.get("ssid", d.get("mac", "")))
	return str(_rows[i]["key"]) + "|" + who

# The pop-up sits just under its icon, kept on screen.
func _place() -> void:
	if not is_open:
		return
	_panel.reset_size()
	var vp := _root.get_viewport_rect().size
	if _full:
		_panel.position = Vector2((vp.x - _panel.size.x) / 2.0, maxf(60.0, (vp.y - _panel.size.y) / 2.0 - 30.0))
		return
	var x := clampf(_anchor.position.x - 12.0, 40.0, vp.x - _panel.size.x - 40.0)
	_panel.position = Vector2(x, _anchor.end.y + 14.0)

func _first_item() -> int:
	for i in _rows.size():
		if _rows[i]["type"] == "item":
			return i
	return 0

func _refresh() -> void:
	for i in _nodes.size():
		if _nodes[i].is_empty():
			continue
		var on := i == _sel
		var sb: StyleBoxFlat = _nodes[i]["style"]
		sb.bg_color = Themes.ink(0.16) if on else Themes.ink(0.05)
		sb.set_border_width_all(3 if on else 0)
		sb.border_color = SELECT
		(_nodes[i]["name"] as Label).add_theme_color_override("font_color", TEXT if on else Color(TEXT, 0.8))
	# Long lists (Bluetooth devices): show a window of rows around the selection.
	var item_count := 0
	for i in _nodes.size():
		if not _nodes[i].is_empty():
			item_count += 1
	var shown := 0
	var pos := 0
	for i in _nodes.size():
		if _nodes[i].is_empty():
			continue
		pos += 1
		if _sel == i:
			if pos - 1 < _top:
				_top = pos - 1
			elif pos - 1 >= _top + VISIBLE_ROWS:
				_top = pos - VISIBLE_ROWS
	pos = 0
	for i in _nodes.size():
		if _nodes[i].is_empty():
			continue
		var vis := pos >= _top and pos < _top + VISIBLE_ROWS
		(_nodes[i]["panel"] as Control).visible = vis
		pos += 1
	if _more == null:
		_more = _label("", 20, MUTED)
		_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(_more)
	_box.move_child(_more, _box.get_child_count() - 1)
	var below := item_count - (_top + VISIBLE_ROWS)
	_more.text = ("%d more below" % below) if below > 0 else ""
	_more.visible = below > 0
	var hints: Array = [["accept", "Select"], ["dpad_v", "Choose"], ["back", "Back"]]
	if kind == "wifi" and _sel < _rows.size() and _rows[_sel].get("key", "") == "wifi_net" and bool(_rows[_sel]["data"]["saved"]):
		hints.insert(1, ["west", "Forget"])
	elif kind == "bt" and _sel < _rows.size() and _rows[_sel].get("key", "") == "bt_dev":
		hints.insert(1, ["west", "Remove"])
	TephraGlyphs.fill(_hints, hints, 26)
	_place.call_deferred()

## Up/down moves between rows; left/right flips a value.
func move(dir: Vector2i) -> void:
	if not is_open:
		return
	if dir.y != 0:
		var i := _sel
		for _k in _rows.size():
			i = posmod(i + dir.y, _rows.size())  # round the ends
			if _rows[i]["type"] == "item":
				break
		_sel = i
		_refresh()
	elif dir.x != 0 and _rows[_sel]["type"] == "item" and _rows[_sel]["key"] in ["glyphs", "hints", "dev_overlay", "dev_under", "hide_mods", "files_show_all", "menu_backdrop", "wifi_toggle", "bt_toggle", "battery_low", "battery_crit", "pad_priority", "vibration", "deadzone", "lightbar_mode", "reduce_flashing", "show_fps"]:
		_activate(dir.x)

func _activate(step := 1) -> void:
	if _rows.is_empty() or _rows[_sel]["type"] != "item":
		return
	var r: Dictionary = _rows[_sel]
	match str(r["key"]):
		"glyphs":
			var gi := GLYPH_CHOICES.find(str(Settings.get_value("glyph_override", "")))
			gi = posmod(maxi(gi, 0) + step, GLYPH_CHOICES.size())
			Settings.set_value("glyph_override", GLYPH_CHOICES[gi])
			TephraGlyphs.detect()
			_home._refresh_all_hints()
			_build()
		"dev_overlay":
			Settings.set_value("dev_overlay", not Settings.get_value("dev_overlay", false))
			_build()
		"files_show_all":
			Settings.set_value("files_show_all", not Settings.get_value("files_show_all", false))
			_build()
		"hide_mods":
			Settings.set_value("hide_mods", not Settings.get_value("hide_mods", false))
			_build()
		"dev_under":
			Settings.set_value("dev_under", not Settings.get_value("dev_under", false))
			_home.apply_under_apps()
			_build()
		"hints":
			Settings.set_value("show_hints", not Settings.get_value("show_hints", true))
			_home._refresh_all_hints()
			_build()
		"menu_backdrop":
			Settings.set_value("menu_backdrop", "screenshot" if str(Settings.get_value("menu_backdrop", "screenshot")) == "live" else "live")
			_build()
		"close_menu":
			close()
		"view_log":
			close()
			_home.open_log()
		"test_toast":
			_home.dev_fake_toast()
		"fake_loading":
			close()
			_home.dev_fake_loading()
		"battery_low":
			_home.dev_battery_test(0 if _home.alert.force_level == 1 else 1)
			_build()
		"battery_crit":
			_home.dev_battery_test(0 if _home.alert.force_level == 2 else 2)
			_build()
		"pad_pick":
			Settings.set_value("pad_priority", str(int(r["data"]["slot"])))
			Haptics.confirm()
			TephraGlyphs.detect()
			_home._refresh_all_hints()
			_build()
		"vibration":
			var vi := posmod(int(Settings.get_value("vibration", 2)) + step, VIB_NAMES.size())
			Settings.set_value("vibration", vi)
			Haptics.preview()  # feel the new strength straight away
			_build()
		"deadzone":
			var dz := clampf(float(Settings.get_value("deadzone", 0.15)) + 0.05 * step, 0.0, 0.5)
			Settings.set_value("deadzone", snappedf(dz, 0.05))
			TephraGlyphs.apply_deadzone()
			_build()
		"lightbar_mode":
			var li := posmod(maxi(LIGHT_MODES.find(str(Settings.get_value("lightbar_mode", "theme"))), 0) + step, LIGHT_MODES.size())
			Settings.set_value("lightbar_mode", LIGHT_MODES[li])
			_home.alert.apply_mode_now()
			_build()
		"lightbar_pick":
			close()
			_home.color_picker.open(_home.alert.custom_color(), "Lightbar colour", func(c: Color):
				Settings.set_value("lightbar_custom", "#" + c.to_html(false))
				Settings.set_value("lightbar_mode", "custom")
				_home.alert.apply_mode_now())
		"pad_test":
			close()
			_home.controller_test.open()
		"scene_test":
			close()
			_home.scene_test.open()
		"redo_setup":
			close()
			_home.setup_screen.open(0, true)
		"phone_test":
			close()
			_home.phone_screen.open("captures")
		"reduce_flashing":
			Settings.set_value("reduce_flashing", not Settings.get_value("reduce_flashing", false))
			_build()
		"show_fps":
			if str(Settings.get_value("gpu_mode", "normal")) == "saver":
				_home.dev_toast("Power saver keeps the frame limit at 30")
				return
			var caps := [0, 30, 60, 90, 120, 144, 180, 240]
			var ci := posmod(maxi(caps.find(Engine.max_fps), 0) + step, caps.size())
			Engine.max_fps = caps[ci]
			Settings.set_value("fps_cap", caps[ci])
			_build()
		"refresh_all":
			_home.refresh_everything()
		"refresh_games":
			_home.refresh_games()
			_home.dev_toast("Games re-scanned")
		"clear_art":
			_home.dev_toast("Cleared %d cover images. Restart Tephra to reload them." % _clear_dir("user://art"))
		"clear_ach":
			_home.dev_toast("Cleared %d achievement files" % _clear_dir("user://ach"))
		"reset_perf":
			_home.perf.reset()
			_home.dev_toast("Performance data reset")
		"show_paths":
			_home.dev_toast("Data folder: " + OS.get_user_data_dir())
		"restart_tephra":
			_home.restart_tephra()
		"wifi_toggle":
			if not _wifi_known:
				return  # still checking
			_wifi_on = not _wifi_on
			OS.create_process("nmcli", ["radio", "wifi", "on" if _wifi_on else "off"])
			if not _wifi_on:
				_wifi_name = ""
				_wifi_nets.clear()
			_wifi_note = ""
			_wifi_scanned = false
			_build()
			await get_tree().create_timer(2.5).timeout
			if is_open and kind == "wifi":
				_read_wifi()
				_home._poll_wifi()
		"wifi_scan":
			_scan_wifi()
		"wifi_net":
			_wifi_pick(r["data"])
		"wifi_hidden":
			_wifi_hidden()
		"bt_toggle":
			_bt_on = not _bt_on
			_run(func(): OS.execute("bluetoothctl", ["power", "on" if _bt_on else "off"], []))
			if not _bt_on:
				_bt_devices.clear()
			_build()
			if _bt_on:
				await get_tree().create_timer(1.5).timeout
				_read_bluetooth()
		"bt_scan":
			_scan()
		"bt_dev":
			_device_action(r["data"])

func _fps_text() -> String:
	return "Unlimited" if Engine.max_fps == 0 else "%d fps" % Engine.max_fps

## Deletes every file in a folder (not the folder). Returns how many were removed.
func _clear_dir(path: String) -> int:
	var n := 0
	for f in DirAccess.get_files_at(path):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(path + "/" + f)) == OK:
			n += 1
	return n

# ---------- Background work ----------
# Slow commands (scanning, pairing) run on a worker thread; the result comes back
# to the main thread through call_deferred.
func _run(work: Callable, done := Callable()) -> void:
	var box := {}
	box["id"] = WorkerThreadPool.add_task(func():
		work.call()
		_run_finished.call_deferred(box, done))
	_runs[box["id"]] = true

var _runs := {}

func _run_finished(box: Dictionary, done: Callable) -> void:
	if _runs.erase(box["id"]):
		WorkerThreadPool.wait_for_task_completion(box["id"])
	if done.is_valid():
		done.call()

# Changing the theme rebuilds this menu; a command still running is waited for first, so it never
# reaches into the freed menu (that crashed Tephra).
func _exit_tree() -> void:
	for id in _runs.keys():
		WorkerThreadPool.wait_for_task_completion(id)
	_runs.clear()

# The menu opens at once (showing what it knew last time, or "Checking...") and the real
# state arrives a moment later from a worker thread. Asking NetworkManager can take a second or
# more, and doing that before the menu opened is what made the Wi-Fi icon lag.
func _read_wifi() -> void:
	_run(func():
		var radio := []
		OS.execute("nmcli", ["-t", "-f", "WIFI", "radio"], radio)
		var on := radio.size() > 0 and str(radio[0]).strip_edges() == "enabled"
		var name := ""
		var nets: Array = []
		if on:
			# "--rescan no": use the list NetworkManager already has instead of scanning again.
			nets = _list_networks()
			for n in nets:
				if n["active"]:
					name = n["ssid"]
		_wifi_ready.call_deferred(on, name, nets))

func _wifi_ready(on: bool, name: String, nets := []) -> void:
	_wifi_known = true
	_wifi_on = on
	_wifi_name = name
	if on:
		_wifi_nets = nets
	else:
		_wifi_nets = []
	if is_open and kind == "wifi":
		_build()
		if on and not _wifi_scanned:
			_wifi_scanned = true
			_scan_wifi()  # the cached list is up; now ask for a fresh one

# Asks the Wi-Fi card to look again (takes a few seconds), then shows the new list.
func _scan_wifi() -> void:
	if _scanning or not _wifi_on:
		return
	_scanning = true
	_wifi_scanned = true
	_build()
	_run(func():
		OS.execute("nmcli", ["dev", "wifi", "rescan"], [], true)
		OS.delay_msec(3500)
		var nets := _list_networks()
		var name := ""
		for n in nets:
			if n["active"]:
				name = n["ssid"]
		_scan_wifi_done.call_deferred(name, nets))

func _scan_wifi_done(name: String, nets: Array) -> void:
	_scanning = false
	_wifi_name = name
	_wifi_nets = nets
	if is_open and kind == "wifi":
		_build()

## The networks in range, strongest first (the connected one on top). Slow: call from a worker thread.
func _list_networks() -> Array:
	var out := []
	OS.execute("nmcli", ["-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "no"], out)
	var saved := {}
	var sv := []
	OS.execute("nmcli", ["-t", "-f", "NAME,TYPE", "connection", "show"], sv)
	for line in (str(sv[0]).split("\n", false) if sv.size() > 0 else PackedStringArray()):
		var f := _split_terse(line)
		if f.size() >= 2 and (f[1].contains("wireless") or f[1] == "wifi"):
			# A saved connection's name isn't always the network's name: ask for the real one.
			var so := []
			OS.execute("nmcli", ["-g", "802-11-wireless.ssid", "connection", "show", "id", f[0]], so)
			var real := str(so[0]).strip_edges() if so.size() > 0 else ""
			saved[real if real != "" else f[0]] = f[0]
	var best := {}
	for line in (str(out[0]).split("\n", false) if out.size() > 0 else PackedStringArray()):
		var f := _split_terse(line)
		if f.size() < 4 or f[1] == "":
			continue  # hidden networks show up without a name
		var n := {"ssid": f[1], "signal": f[2].to_int(), "security": f[3], "secure": f[3] != "" and f[3] != "--",
			"active": f[0] == "yes", "saved": saved.has(f[1]), "profile": str(saved.get(f[1], f[1]))}
		if not best.has(f[1]):
			best[f[1]] = n
		else:
			var old: Dictionary = best[f[1]]
			if n["active"] or (not old["active"] and n["signal"] > old["signal"]):
				best[f[1]] = n
	var list: Array = best.values()
	# Connected first, then by signal in coarse steps and by name, so the list doesn't shuffle on every refresh.
	list.sort_custom(func(a, b):
		if a["active"] != b["active"]:
			return a["active"]
		var ba := int(a["signal"]) / 25
		var bb := int(b["signal"]) / 25
		if ba != bb:
			return ba > bb
		return str(a["ssid"]).naturalnocasecmp_to(str(b["ssid"])) < 0)
	return list.slice(0, 30)

## nmcli's "terse" lines: fields split by ":", with a literal ":" or "\" written as "\:" / "\\".
func _split_terse(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if ch == "\\" and i + 1 < line.length():
			cur += line[i + 1]
			i += 2
			continue
		if ch == ":":
			out.append(cur)
			cur = ""
		else:
			cur += ch
		i += 1
	out.append(cur)
	return out

func _net_value(n: Dictionary) -> String:
	var strength := "Strong" if int(n["signal"]) >= 70 else ("Good" if int(n["signal"]) >= 40 else "Weak")
	var what := "Connected" if n["active"] else ("Saved" if n["saved"] else ("Secured" if n["secure"] else "Open"))
	return "%s  -  %s" % [what, strength]

# ---------- Joining a network ----------
func _wifi_pick(n: Dictionary) -> void:
	if _busy != "":
		return
	var ssid: String = n["ssid"]
	_wifi_note = ""
	if n["active"]:
		_busy = "Disconnecting from %s..." % ssid
		_build()
		var prof: String = n["profile"]
		_run(func(): OS.execute("nmcli", ["connection", "down", "id", prof], [], true), _wifi_action_done)
	elif n["saved"]:
		_wifi_join(ssid, "", false, true, str(n["profile"]))
	elif not n["secure"]:
		_wifi_join(ssid, "", false, false)
	elif str(n["security"]).contains("802.1X"):
		_wifi_note = "%s needs a work or school login, which Tephra can't enter yet." % ssid
		_build()
	else:
		_wifi_ask_password(ssid, "", "")

func _wifi_ask_password(ssid: String, typed: String, problem: String) -> void:
	var wep := false
	for n in _wifi_nets:
		if n["ssid"] == ssid and str(n["security"]).contains("WEP"):
			wep = true
	_home.keyboard.open("Password for %s" % ssid, typed, true, func(pw: String): _wifi_join(ssid, pw, false, false),
		{"min_len": 5 if wep else 8, "hint": problem if problem != "" else "Type the Wi-Fi password"})

func _wifi_hidden() -> void:
	if _busy != "":
		return
	_home.keyboard.open("Network name", "", false, _wifi_hidden_name, {"min_len": 1, "hint": "The exact name of the network, capital letters count"})

func _wifi_hidden_name(net_name: String) -> void:
	_home.keyboard.open("Password for %s" % net_name, "", true, func(pw: String): _wifi_join(net_name, pw, true, false),
		{"min_len": 0, "hint": "Leave empty for an open network"})

# Joins a network on a worker thread. saved = it is already known to this PC (no password to send).
func _wifi_join(ssid: String, password: String, hidden: bool, saved: bool, profile := "") -> void:
	_busy = "Connecting to %s..." % ssid
	_wifi_note = ""
	_build()
	_run(func():
		var out := []
		var args: Array = ["-w", "30"]
		if saved:
			args += ["connection", "up", "id", profile if profile != "" else ssid]
		else:
			args += ["dev", "wifi", "connect", ssid]
			if password != "":
				args += ["password", password]
			if hidden:
				args += ["hidden", "yes"]
		var rc := OS.execute("nmcli", args, out, true)
		var text := str(out[0]).strip_edges() if out.size() > 0 else ""
		if rc != 0 and not saved:
			OS.execute("nmcli", ["connection", "delete", "id", ssid], [], true)  # a failed try must not stay saved
		_wifi_join_done.call_deferred(ssid, password, hidden, saved, rc, text))

func _wifi_join_done(ssid: String, password: String, hidden: bool, saved: bool, rc: int, text: String) -> void:
	_busy = ""
	if rc == 0:
		_wifi_note = "Connected to %s" % ssid
		_home.dev_toast("Connected to %s" % ssid)
	else:
		var low := text.to_lower()
		var wrong := low.contains("secrets were required") or low.contains("password") or low.contains("(7)") or low.contains("timeout") or low.contains("(4)") or low.contains("(3)")
		if saved:
			_wifi_note = "Couldn't join %s. If its password changed, press %s to forget it and join again." % [ssid, TephraGlyphs.btn("west")]
		elif wrong and password != "":
			_wifi_note = "Wrong password for %s" % ssid
			if is_open and kind == "wifi":
				_wifi_ask_password(ssid, password, "That password didn't work. Check it and try again")
		else:
			_wifi_note = "Couldn't join %s%s" % [ssid, (": " + text.get_slice("\n", 0)) if text != "" else ""]
	_home._poll_wifi()
	if is_open and kind == "wifi":
		_read_wifi()

func _wifi_action_done() -> void:
	_busy = ""
	_home._poll_wifi()
	if is_open and kind == "wifi":
		_read_wifi()

# Y on a saved network: make this PC forget it.
func _wifi_forget_selected() -> void:
	if _busy != "" or _sel >= _rows.size() or _rows[_sel].get("key", "") != "wifi_net":
		return
	var n: Dictionary = _rows[_sel]["data"]
	if not n["saved"]:
		return
	var ssid: String = n["ssid"]
	var prof: String = n["profile"]
	_wifi_note = "Forgot %s" % ssid
	_busy = "Forgetting %s..." % ssid
	_build()
	_run(func(): OS.execute("nmcli", ["connection", "delete", "id", prof], [], true), _wifi_forget_done)

func _wifi_forget_done() -> void:
	_busy = ""
	_home._poll_wifi()
	if is_open and kind == "wifi":
		_read_wifi()

func _read_bluetooth() -> void:
	_run(func():
		var show := []
		OS.execute("bluetoothctl", ["show"], show)
		var on := show.size() > 0 and str(show[0]).contains("Powered: yes")
		var list := []
		var devs: Array = []
		if on:
			OS.execute("bluetoothctl", ["devices"], list)
			for line in (str(list[0]).split("\n") if list.size() > 0 else PackedStringArray()):
				if not line.begins_with("Device "):
					continue
				var parts := line.split(" ", false, 2)
				if parts.size() < 3:
					continue
				var mac := parts[1]
				var info := []
				OS.execute("bluetoothctl", ["info", mac], info)
				var txt := str(info[0]) if info.size() > 0 else ""
				var icon := ""
				for l2 in txt.split("\n"):
					if l2.strip_edges().begins_with("Icon:"):
						icon = l2.strip_edges().get_slice(":", 1).strip_edges()
				var paired := txt.contains("Paired: yes")
				var name := parts[2].strip_edges()
				# Nameless things nearby (phones, TVs, beacons) only show up as their address, like 4F-82-E1-8F-29-AD:
				# nobody can tell what they are, so they are left out unless already paired.
				if not paired and (_mac_like.search(name) != null or name == ""):
					continue
				devs.append({"mac": mac, "name": name, "paired": paired, "connected": txt.contains("Connected: yes"),
					"controller": icon == "input-gaming" or icon == "input-joystick", "rank": _bt_rank(icon, name), "kind": bt_kind(icon, name)})
			# Connected first, then saved ones, then new; within each, controllers and headphones before other things.
			devs.sort_custom(func(a, b):
				var ka: int = (0 if a["connected"] else (1 if a["paired"] else 2)) * 10 + int(a["rank"])
				var kb: int = (0 if b["connected"] else (1 if b["paired"] else 2)) * 10 + int(b["rank"])
				if ka != kb:
					return ka < kb
				return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
		_bt_ready.call_deferred(on, devs))

static var _mac_like := RegEx.create_from_string("^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$")

## What a device is, from the type it reports to Bluetooth (its "Icon") and its name: a controller family
## ("ds5", "ds4", "xbox", "nintendo", "pad"), "headphones", "earbuds", "speaker", "keyboard", "mouse", "phone",
## "computer", "tv", "watch", or "" when it can't be told.
static func bt_kind(icon: String, name: String) -> String:
	var n := name.to_lower()
	var has := func(words: Array) -> bool:
		for w in words:
			if n.contains(w):
				return true
		return false
	if has.call(["dualsense", "ps5 controller", "edge wireless"]):
		return "ds5"
	if has.call(["dualshock", "wireless controller", "ps4 controller"]):
		return "ds4"
	if has.call(["xbox", "x-box"]):
		return "xbox"
	if has.call(["pro controller", "joy-con", "joycon", "switch", "nintendo"]):
		return "nintendo"
	if icon in ["input-gaming", "input-joystick"] or has.call(["controller", "gamepad", "8bitdo", "8bit do", "stadia", "gamesir", "flydigi"]):
		return "pad"
	if has.call(["buds", "airpods", "earbud", "wf-", "jabra elite", "beats fit", "powerbeats", "pixel buds", "nothing ear"]):
		return "earbuds"
	if icon in ["audio-headset", "audio-headphones"] or has.call(["headphone", "headset", "wh-", "airpods max", "qc35", "qc45", "quietcomfort", "arctis", "hyperx", "momentum"]):
		return "headphones"
	if icon in ["audio-card", "audio-speakers"] or has.call(["speaker", "soundbar", "jbl", "bose", "sonos", "ue boom", "boom", "flip", "charge", "marshall", "anker sound", "soundcore", "echo"]):
		return "speaker"
	if icon == "input-keyboard" or has.call(["keyboard", "keychron", "k380"]):
		return "keyboard"
	if icon in ["input-mouse", "input-tablet"] or has.call(["mouse", "mx master", "trackpad", "magic"]):
		return "mouse"
	if icon == "phone" or has.call(["iphone", "galaxy", "pixel", "phone", "oneplus", "redmi", "xperia"]):
		return "phone"
	if icon == "computer" or has.call(["macbook", "laptop", "desktop", "-pc", "thinkpad"]):
		return "computer"
	if icon in ["video-display", "multimedia-player"] or has.call(["tv", "bravia", "roku", "fire tv", "chromecast", "shield"]):
		return "tv"
	if has.call(["watch", "band", "fitbit", "garmin"]):
		return "watch"
	return ""

static func bt_icon(kind: String, px := 32) -> Texture2D:
	if kind in ["ds5", "ds4", "xbox", "nintendo", "pad"]:
		var fam := "ds5" if kind == "pad" else kind
		return Icons.texture("btpad_" + kind, Icons.svg_pad(fam), px)
	return Icons.texture("bt_" + (kind if kind != "" else "other"), Icons.svg_bt_kind(kind), px)

## 0 controllers, 1 headphones and speakers, 2 keyboards and mice, 3 anything else.
static func _bt_rank(icon: String, name: String) -> int:
	var n := name.to_lower()
	if icon in ["input-gaming", "input-joystick"] or n.contains("controller") or n.contains("dualsense") or n.contains("gamepad") or n.contains("xbox"):
		return 0
	if icon.begins_with("audio") or n.contains("headphone") or n.contains("buds") or n.contains("headset") or n.contains("airpods") or n.contains("speaker"):
		return 1
	if icon in ["input-keyboard", "input-mouse", "input-tablet"]:
		return 2
	return 3

func _bt_ready(on: bool, devs: Array) -> void:
	_bt_on = on
	_bt_devices = devs.slice(0, 40)
	if is_open and kind == "bt":
		_build()

func _scan() -> void:
	if _busy != "":
		return
	_busy = "Scanning..."
	_build()
	_run(func(): OS.execute("bluetoothctl", ["--timeout", "8", "scan", "on"], []), _scan_done)

func _scan_done() -> void:
	_busy = ""
	if is_open and kind == "bt":
		_read_bluetooth()

func _device_action(d: Dictionary) -> void:
	if _busy != "":
		return
	var mac: String = d["mac"]
	if d["connected"]:
		if d["controller"]:
			return  # never disconnect a controller from here
		_busy = "Disconnecting " + str(d["name"]) + "..."
		_build()
		_run(func(): OS.execute("bluetoothctl", ["disconnect", mac], []), _action_done)
	elif d["paired"]:
		_busy = "Connecting to " + str(d["name"]) + "..."
		_build()
		_run(func(): OS.execute("bluetoothctl", ["connect", mac], []), _action_done)
	else:
		_busy = "Pairing with " + str(d["name"]) + "..."
		_build()
		_run(func():
			OS.execute("bluetoothctl", ["--timeout", "25", "--agent", "NoInputNoOutput", "pair", mac], [])
			OS.execute("bluetoothctl", ["trust", mac], [])
			OS.execute("bluetoothctl", ["connect", mac], []), _action_done)

# Square on any device in the list: remove it (unpairs, disconnects and drops it from the list).
func _bt_forget_selected() -> void:
	if _busy != "" or _sel >= _rows.size() or _rows[_sel].get("key", "") != "bt_dev":
		return
	var d: Dictionary = _rows[_sel]["data"]
	var mac: String = d["mac"]
	_busy = "Removing %s..." % str(d["name"])
	_build()
	_run(func(): OS.execute("bluetoothctl", ["remove", mac], []), _action_done)

func _action_done() -> void:
	_busy = ""
	if is_open and kind == "bt":
		_read_bluetooth()

## Returns true when this menu used the event.
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_accept"):
		_activate()
	elif kind == "wifi" and ((event is InputEventJoypadButton and event.pressed and (event.button_index == TephraGlyphs.west_button() or event.button_index == TephraGlyphs.north_button())) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_X, KEY_Y, KEY_DELETE])):
		_wifi_forget_selected()
	elif kind == "bt" and ((event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.west_button()) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_X, KEY_DELETE])):
		_bt_forget_selected()
	return true
