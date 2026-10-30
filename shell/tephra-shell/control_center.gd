extends CanvasLayer
## Tephra control center (v1.3): icon cards with pop-up panels.
## Quick-press the system button (F1 on a keyboard) to open or close.
## Left/Right picks a card, confirm opens/toggles, back closes. In the Sound panel Left/Right change the volume.
## Volume and Power open a small panel above their card (PS5-style).

signal perf_changed
signal quit_game_requested
signal perf_move_requested
signal keyboard_requested(title: String, initial: String, done: Callable)
signal closed(resume: bool)  # resume = closed by B / the PS button (not by choosing a card)
signal album_requested
signal mods_requested
signal download_action(action: String, id: String)  # "pause_all", "resume_all", "start", "stop"
signal theme_requested(theme: String)
signal browser_action(action: String, arg: String)  # "open" url, "ask", "address", "type", "reload"

const AudioFade = preload("res://audio_fade.gd")
const Themes = preload("res://themes.gd")
const Settings = preload("res://settings.gd")
const Motion = preload("res://motion.gd")
const Perf = preload("res://perf.gd")
const InGameHud = preload("res://ingame_hud.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Icons = preload("res://icons.gd")
const Notifications = preload("res://notifications.gd")
const SelfUpdate = preload("res://self_update.gd")
const FilesBrowser = preload("res://files_browser.gd")
const Browser = preload("res://browser.gd")

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var SELECT: Color = Themes.c("select")  # soft white outline for the selected card
var CARD_BG: Color = Color(Themes.c("card"), 0.94)
## How the cards look in each theme: corner roundness, the thickness of the outline when selected, how see-through the
## card is, how big the selected one grows, and the gap between cards. A theme not listed here uses "tephra".
const LOOKS := {
	"tephra": {"radius": 22, "border": 4, "alpha": 0.94, "grow": 1.08, "gap": 24},
	"volcanic": {"radius": 10, "border": 4, "alpha": 0.96, "grow": 1.10, "gap": 22},     # blocky, like cut stone
	"sleek": {"radius": 30, "border": 3, "alpha": 0.80, "grow": 1.06, "gap": 26},        # clear glass
	"channels": {"radius": 78, "border": 5, "alpha": 0.98, "grow": 1.12, "gap": 30},     # round white buttons
	"ps2": {"radius": 2, "border": 3, "alpha": 0.82, "grow": 1.05, "gap": 18},           # sharp, thin and cool
	"frutiger": {"radius": 40, "border": 4, "alpha": 0.72, "grow": 1.10, "gap": 28},     # soft and glossy
	"wave": {"radius": 34, "border": 3, "alpha": 0.78, "grow": 1.08, "gap": 26},         # blue glass
	"gunmetal": {"radius": 4, "border": 3, "alpha": 0.9, "grow": 1.05, "gap": 18},     # dark, shiny and calm
	"neon": {"radius": 6, "border": 5, "alpha": 0.86, "grow": 1.10, "gap": 20},        # chunky neon blocks
	"gothic": {"radius": 3, "border": 2, "alpha": 0.9, "grow": 1.06, "gap": 22},       # carved black stone, a thin silver edge
	"nature": {"radius": 16, "border": 4, "alpha": 0.92, "grow": 1.06, "gap": 24},        # warm planks
	"temple": {"radius": 0, "border": 4, "alpha": 1.0, "grow": 1.0, "gap": 20},         # white pages in square blue frames
	"pcb": {"radius": 10, "border": 3, "alpha": 0.92, "grow": 1.06, "gap": 22},         # dark green boards with a gold edge
	"planet": {"radius": 22, "border": 3, "alpha": 0.82, "grow": 1.08, "gap": 24},      # dark glass with a cool blue edge
	"castle": {"radius": 14, "border": 3, "alpha": 0.9, "grow": 1.08, "gap": 24},      # dark slate with a gold edge
	"mold": {"radius": 4, "border": 2, "alpha": 0.9, "grow": 1.06, "gap": 22},         # damp, stained wood
}
var LOOK: Dictionary = LOOKS.get(Themes.id(), LOOKS["tephra"])
const CARD_SIZE := Vector2(156, 156)
const ICON_PX := 72
# Monitor brightness over DDC/CI. Some laptops' mini-DisplayPort can't do it, and
# ddcutil probing the ports can blank the screen for a moment, so it's off here.
# Set to true on a PC where `ddcutil detect` finds your monitor.
const DDC_BRIGHTNESS := false

var is_open := false
var downloads_source := Callable()  # set by home.gd: returns [{id, title, pct, state}]
var _dl_game := ""                  # the game whose actions the Downloads panel shows
var _dl_confirm := false
var _dl_ms := 0
var game_running := false  # set by home.gd; adds the Quit game card
var game_id := ""          # set by home.gd while a game is running
var hud_status := ""       # set by home.gd: whether the numbers over the game work
var bar_selected := false  # the info bar at the bottom is the selected thing (Down from the cards)
var bar_rect := Rect2()    # set by home.gd every frame: where the info bar is on screen
var bar_zone := "bottom-center"  # set by home.gd: which of the 8 spots the bar is in
var controllers            # controllers.gd, set by home.gd

var _root: Control
var _clock: Label
var _shard: TextureRect
var _wifi_top: TextureRect
var _hints: HBoxContainer
var _row: HBoxContainer
var _cards: Array = []  # each: {"id", "panel", "icon", "badge", "value", "style", "slot"}
var _sel := 0

# Pop-up panel (Sound or Power) above a card
var _popup: PanelContainer
var _popup_box: VBoxContainer
var _popup_scroll: ScrollContainer   # holds the rows: when they are taller than the screen has room for, they scroll
const POPUP_TEXT_W := 400.0          # width of a row's text: longer lines wrap onto more lines, the pop-up grows tall instead of wide
var _popup_kind := ""    # "", "sound" or "power"
var _popup_rows: Array = []  # each: {"type": "slider"/"item"/"toggle", "action", "text", "node"}
var _popup_sel := 0
var _popup_card: Control
var _files: Control  # files_browser.gd, opened from the Files card; takes the input while open

var _bright_pending := false
var _reading := false
var _task_id := -1

# System state (read in the background every 2 s while open)
var _vol_pct := -1  # 0 to 100 in steps of 5, -1 = unknown
var _muted := false
var _last_adjust_ms := -100000  # when sound was last changed here
var _last_h_ms := -100000       # when the selection last moved left/right
var _last_read_ms := 0
var _brightness := -1
var held := false  # set by home: the direction being sent is a repeat of a held press
var _bright_max := 100
var _bright_ms := -100000  # when brightness was last changed here (the sensor is not re-read right after)
var _bl_dir := ""   # the laptop screen's /sys/class/backlight/<name> folder ("" = none)
var _wifi_on := false
var _wifi_name := ""
var _wifi_signal := 0
var _sinks: Array = []      # [{name, desc}]
var _default_sink := ""
var _mic_present := false
var _mic_muted := false
var _laptop_bat := ""
var _album_count := 0
var _drive_count := 1

func _count_album() -> int:
	return preload("res://album.gd").count_files()

# ---------- Build ----------
func _ready() -> void:
	layer = 95  # above the launch screen (90), below toasts (97) and the boot logo (100)
	# Volume, Wi-Fi and sound outputs are read quietly in the background every few seconds (never during a game),
	# so the control center opens already showing the right values instead of catching up a second later.
	var poll := Timer.new()
	poll.wait_time = 4.0
	poll.autostart = true
	add_child(poll)
	poll.timeout.connect(func() -> void:
		if not game_running and not _root.visible:
			_read_system_state())
	_read_system_state.call_deferred()

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Themes.dim(0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Whatever is behind the control center (the Home screen, a theme's background) is blurred, then tinted.
	var blur := Shader.new()
	blur.code = """shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 6.0;
	vec3 c = textureLod(scr, SCREEN_UV, 3.0).rgb * 0.28;
	c += textureLod(scr, SCREEN_UV + vec2(px.x, 0.0), 3.0).rgb * 0.18;
	c += textureLod(scr, SCREEN_UV - vec2(px.x, 0.0), 3.0).rgb * 0.18;
	c += textureLod(scr, SCREEN_UV + vec2(0.0, px.y), 3.0).rgb * 0.18;
	c += textureLod(scr, SCREEN_UV - vec2(0.0, px.y), 3.0).rgb * 0.18;
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}"""
	var bmat := ShaderMaterial.new()
	bmat.shader = blur
	bmat.set_shader_parameter("tint", dim.color)
	dim.material = bmat
	dim.color = Color.WHITE
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Clock: placed exactly over the home screen's clock when opened (see open()).
	_clock = _label("", 32, TEXT)
	_root.add_child(_clock)
	# Copies of the home screen's logo and Wi-Fi icon, so they brighten with the clock.
	_shard = TextureRect.new()
	_shard.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shard.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shard)
	_wifi_top = TextureRect.new()
	_wifi_top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wifi_top.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wifi_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_wifi_top)
	_wifi_top.visible = false  # the corner Wi-Fi icon sat on the logo; Wi-Fi shows in its own tile

	# A darker band along the bottom, so the cards read as a dock rather than floating mid-screen.
	var dock_g := Gradient.new()
	dock_g.offsets = PackedFloat32Array([0.0, 1.0])
	dock_g.colors = PackedColorArray([Themes.dim(0.0), Themes.dim(0.55)])
	var dock_t := GradientTexture2D.new()
	dock_t.gradient = dock_g
	dock_t.fill_from = Vector2(0, 0)
	dock_t.fill_to = Vector2(0, 1)
	dock_t.width = 4
	dock_t.height = 128
	var dock := TextureRect.new()
	dock.texture = dock_t
	dock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dock.stretch_mode = TextureRect.STRETCH_SCALE
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dock)
	dock.anchor_top = 1.0
	dock.anchor_right = 1.0
	dock.anchor_bottom = 1.0
	dock.offset_top = -380
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", int(LOOK["gap"]))
	_root.add_child(_row)
	_row.anchor_left = 0.0
	_row.anchor_right = 1.0
	_row.anchor_top = 1.0
	_row.anchor_bottom = 1.0
	_row.offset_top = -(CARD_SIZE.y + 124)
	_row.offset_bottom = -124
	_row.grow_vertical = Control.GROW_DIRECTION_BEGIN

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
	refresh_hints()

	_popup = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(22)
	_popup.add_theme_stylebox_override("panel", sb)
	_popup.visible = false
	_root.add_child(_popup)
	_popup_scroll = ScrollContainer.new()
	_popup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_popup_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_popup.add_child(_popup_scroll)
	_popup_box = VBoxContainer.new()
	_popup_box.add_theme_constant_override("separation", 12)
	_popup_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_popup_scroll.add_child(_popup_box)

	_files = FilesBrowser.new()
	_root.add_child(_files)
	_files.hints_changed.connect(refresh_hints)
	_files.keyboard_requested.connect(func(t: String, i: String, cb: Callable) -> void: keyboard_requested.emit(t, i, cb))
	_files.closed.connect(func() -> void:
		Motion.fade_to(_row, 1.0, 0.15)
		refresh_hints()
		if _pick_closes:
			_pick_closes = false
			close(true))  # opened only to choose a file: the control center goes too

var _pick_closes := false  # Files was opened by pick_file(): closing it closes the control center as well

## Library > Add a game: the control center opens straight into Files to choose one file. done(path) gets the chosen
## file once Files and the control center have closed; backing out closes both without calling it.
func pick_file(note: String, exts: Array, verb: String, done: Callable) -> void:
	_pick_closes = true
	Motion.fade_to(_row, 0.3, 0.15)  # the cards step back behind the browser, as when the Files card opens it
	_files.pick(note, exts, verb, done)
	refresh_hints()

## Rebuilds the hint bar, e.g. after switching between controllers.
func refresh_hints() -> void:
	if _files != null and _files.is_open:
		TephraGlyphs.fill(_hints, _files.hints())
	elif _popup_kind == "" and bar_selected:
		var hidden := bool(Settings.get_value("perf_hidden", false))
		TephraGlyphs.fill(_hints, [["dpad", "Choose"], ["accept", "Numbers"], ["north", "Show" if hidden else "Hide"], ["west", "Move"], ["back", "Close"]])
	elif _popup_kind == "":
		if bool(Settings.get_value("guide_swap", false)):
			TephraGlyphs.fill(_hints, [["dpad", "Choose"], ["accept", "Select"], ["back", "Close"], ["guide", "Home"]])
		else:
			TephraGlyphs.fill(_hints, [["dpad", "Choose"], ["accept", "Select"], ["back", "Close"], ["hold_guide", "Home"]])
	elif _popup_kind == "sound":
		var on_vol := _popup_sel < _popup_rows.size() and str(_popup_rows[_popup_sel]["action"]) == "volume"
		var items: Array = [["dpad_h", "Volume"]]
		if _popup_rows.size() > 1:
			items.append(["dpad_v", "Choose"])
		items.append(["accept", ("Unmute" if _muted else "Mute") if on_vol else "Select"])
		items.append(["back", "Back"])
		TephraGlyphs.fill(_hints, items)
	else:
		TephraGlyphs.fill(_hints, [["dpad", "Choose"], ["accept", "Select"], ["back", "Back"]])

func _make_card(id: String, slot := 0, show_number := false) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CARD_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Themes.c("card"), float(LOOK["alpha"]))
	sb.border_color = SELECT
	sb.set_corner_radius_all(int(LOOK["radius"]))
	sb.set_content_margin_all(16)
	if Themes.id() in ["sleek", "frutiger", "wave", "gunmetal", "gothic", "mold"]:
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", sb)
	preload("res://rounded.gd").rough(panel, 0.5)  # lighter char, so the chosen card's edge still shows

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	v.add_child(icon_box)
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_box.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Small player-number badge for controller cards.
	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 22)
	badge.add_theme_color_override("font_color", Color("121a24"))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = TEXT
	bsb.set_corner_radius_all(14)
	badge.add_theme_stylebox_override("normal", bsb)
	badge.visible = show_number
	badge.text = str(slot)
	icon_box.add_child(badge)
	badge.position = Vector2(ICON_PX - 18, ICON_PX - 26)
	badge.size = Vector2(28, 28)
	var value := _label("", 24, TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.custom_minimum_size.x = CARD_SIZE.x - 32
	v.add_child(value)

	_row.add_child(panel)
	_cards.append({"id": id, "panel": panel, "icon": icon, "value": value, "style": sb, "slot": slot})

func _rebuild_cards() -> void:
	for c in _cards:
		var old: Control = c["panel"]
		_row.remove_child(old)
		old.queue_free()
	_cards.clear()
	_laptop_bat = _find_laptop_battery()
	if game_running:
		_make_card("quit")
	_make_card("notifications")
	_make_card("downloads")
	_make_card("volume")
	_bl_dir = _find_backlight()
	if _bl_dir != "" or DDC_BRIGHTNESS:
		_make_card("brightness")
	_album_count = _count_album()
	_drive_count = FilesBrowser.drives().size()
	_make_card("album")  # screenshots
	_make_card("files")  # drives and folders; hold A to move things
	if not bool(Settings.get_value("hide_mods", false)):  # Developer menu > Hide Mods
		_make_card("mods")  # per-game mod manager
	_make_card("browser")  # the web: Firefox, driven by the pad
	if not game_running:
		_make_card("themes")  # not while a game is open: every screen is rebuilt to change theme
	_make_card("power")  # controllers live in the top bar now (the pad icon next to Bluetooth)
	_sel = 0
	_refresh_values()
	_highlight.call_deferred()  # after layout, so cards scale from their centre

## Called by home.gd when a controller connects, disconnects or its battery changes.
func controllers_changed() -> void:
	if is_open:
		_refresh_values()

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

# ---------- Open / close ----------
## clock_rect = where the home screen's clock is, so ours sits exactly on top.
func open(clock_rect := Rect2(), shard_tex: Texture2D = null, shard_rect := Rect2(), wifi_tex: Texture2D = null, wifi_rect := Rect2()) -> void:
	if is_open:
		return
	is_open = true
	if clock_rect.size != Vector2.ZERO:
		_clock.position = clock_rect.position
		_clock.size = clock_rect.size
	if shard_tex != null:
		_shard.texture = shard_tex
		_shard.position = shard_rect.position
		_shard.size = shard_rect.size
	if wifi_tex != null:
		_wifi_top.texture = wifi_tex
		_wifi_top.position = wifi_rect.position
		_wifi_top.size = wifi_rect.size
	_close_popup()
	bar_selected = false
	refresh_hints()
	_rebuild_cards()
	_clock.text = _clock_src.text if _clock_src != null else _time_text()
	_root.visible = true
	_read_system_state()
	_root.modulate.a = 0.0
	Motion.fade_to(_root, 1.0, 0.12)  # quick: over a game, every millisecond shows
	if Motion.on():
		_row.pivot_offset = _row.size / 2.0
		_row.scale = Vector2.ONE * 0.96
		var tw := create_tween()
		tw.tween_property(_row, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func close(quiet := false) -> void:
	if not is_open:
		return
	is_open = false
	_files.close()
	closed.emit(not quiet)
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, Motion.dur(0.15))
	await t.finished
	if not is_open:  # it may have been reopened during the fade
		_root.visible = false
		_close_popup()

func _process(_delta: float) -> void:
	if not is_open:
		return
	_clock.text = _clock_src.text if _clock_src != null else _time_text()
	for c in _cards:
		if c["id"] == "wifi":
			_wifi_top.texture = (c["icon"] as TextureRect).texture
	if Time.get_ticks_msec() - _last_read_ms > 2000:
		_read_system_state()
	if Time.get_ticks_msec() - _dl_ms > 1500:
		_dl_ms = Time.get_ticks_msec()
		_refresh_values()
		if _popup.visible and _popup_kind == "downloads":
			var keep := _popup_sel
			_build_popup_rows()
			_popup_sel = clampi(keep, 0, maxi(_popup_rows.size() - 1, 0))
			_refresh_popup()
	if _popup.visible and _popup_kind == "perf":
		# The numbers list opens right next to the info bar, wherever it has been put.
		var vp := _root.get_viewport_rect().size
		var x := clampf(bar_rect.get_center().x - _popup.size.x / 2.0, 20.0, vp.x - _popup.size.x - 20.0)
		var y := bar_rect.position.y - _popup.size.y - 20.0
		if bar_rect.get_center().y < vp.y / 2.0:
			y = bar_rect.end.y + 20.0
		_popup.position = Vector2(x, clampf(y, 10.0, vp.y - _popup.size.y - 10.0))
	elif _popup.visible and _popup_card != null:
		# Keep the pop-up centred just above its card.
		var c := _popup_card.get_global_rect()
		var vp2 := _root.get_viewport_rect().size
		var px := clampf(c.get_center().x - _popup.size.x / 2.0, 20.0, maxf(vp2.x - _popup.size.x - 20.0, 20.0))
		var py := clampf(c.position.y - _popup.size.y - 28.0, 20.0, maxf(vp2.y - _popup.size.y - 20.0, 20.0))
		_popup.position = Vector2(px, py)

func _overlay_row_text() -> String:
	return "Web overlay: " + ("on" if bool(Settings.get_value("browser_page_mode", true)) else "off")

func _time_text() -> String:
	return preload("res://settings.gd").clock_text()

# ---------- Input (called by home.gd) ----------
## Returns true when the control center used the event.
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event is InputEventJoypadMotion:
		return true  # the left stick is routed through move() / vertical()
	if _files.is_open:
		return _files.handle_input(event)
	if bar_selected and _popup_kind == "":
		var north: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.north_button()) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Y)
		var west: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.west_button()) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X)
		if north:
			var hide := not bool(Settings.get_value("perf_hidden", false))
			Settings.set_value("perf_hidden", hide)
			if hide:
				# Hidden: it goes back to its usual spot at the bottom, ready for when it is shown again.
				InGameHud.save_zone("", "")
				if game_id != "":
					InGameHud.save_zone(game_id, "")
			perf_changed.emit()
			refresh_hints()
			return true
		if west:
			perf_move_requested.emit()
			return true
	if event.is_action_pressed("ui_cancel"):
		if _popup_kind != "":
			_close_popup()
		else:
			close()
	elif event.is_action_pressed("ui_accept"):
		if _popup_kind != "":
			_popup_activate()
		else:
			_activate()
	return true  # swallow everything while open

# Which way you press, from the cards, to reach the info bar: it depends on where the bar is.
# Anything on the left (corner or side): Left from the first card. Anything on the right: Right from the last card.
# Only the middle of the top edge (Up) and of the bottom edge (Down) are reached with Up / Down.
func _bar_edge() -> Vector2i:
	if bar_zone.ends_with("left"):
		return Vector2i(-1, 0)
	if bar_zone.ends_with("right"):
		return Vector2i(1, 0)
	return Vector2i(0, -1) if bar_zone.begins_with("top") else Vector2i(0, 1)

func _select_bar(on: bool) -> void:
	bar_selected = on
	_highlight()
	refresh_hints()

## Left/right (D-pad or stick).
func move(dir: int) -> void:
	if _files.is_open:
		_files.move(dir)
		return
	if _popup_kind == "sound":
		_change_volume(dir)  # Left / Right always change the volume here, whichever row is picked
		return
	if _popup_kind != "":
		return
	if _cards.is_empty():
		return
	var e := _bar_edge()
	if bar_selected:
		if e.x != 0 and dir == -e.x:  # back from the side towards the cards
			_sel = 0 if e.x < 0 else _cards.size() - 1
			_select_bar(false)
		return
	if e.x != 0 and dir == e.x and _sel == (0 if e.x < 0 else _cards.size() - 1):
		_select_bar(true)  # past the last card on that side: onto the bar
		return
	_sel = posmod(_sel + dir, _cards.size()) if e.x == 0 else clampi(_sel + dir, 0, _cards.size() - 1)  # round the ends (when the info bar isn't beside the cards)
	_last_h_ms = Time.get_ticks_msec()
	_highlight()

## Up/down (D-pad or stick). dir = -1 for up, 1 for down.
## The info bar is reached from the cards in the direction it sits (see _bar_edge).
## (Volume is changed in its pop-up: A on the card, then left / right.)
func vertical(dir: int) -> void:
	if _files.is_open:
		_files.vertical(dir)
		return
	if _popup_kind != "":
		_popup_sel = posmod(_popup_sel + dir, _popup_rows.size()) if not _popup_rows.is_empty() else 0
		_refresh_popup()
		if _popup_kind == "sound":
			refresh_hints()  # A means Mute on the volume row, Select on the others
		return
	var e := _bar_edge()
	if not bar_selected and _sel < _cards.size() and _cards[_sel]["id"] == "brightness":
		# Up brightens, down darkens; at the end of the range the press goes on to the bar as usual.
		var at_end := (dir < 0 and _brightness >= 100) or (dir > 0 and _brightness <= BRIGHT_MIN)
		if _brightness >= 0 and not at_end:
			_change_brightness(-dir)
			return
		if _brightness >= 0 and held:
			return  # still holding: stop at the end, only a fresh press goes on to the bar
	if bar_selected:
		if e.y != 0 and dir == -e.y:
			_select_bar(false)
	elif not _cards.is_empty() and e.y != 0 and dir == e.y:
		_select_bar(true)

func _highlight() -> void:
	for i in _cards.size():
		var on := i == _sel and not bar_selected
		var sb: StyleBoxFlat = _cards[i]["style"]
		sb.set_border_width_all(int(LOOK["border"]) if on else 0)
		if Themes.id() == "volcanic":  # hot metal edge and an ember glow on the selected card
			sb.border_color = Color(1.0, 0.55, 0.15)
			sb.shadow_color = Color(1.0, 0.35, 0.05, 0.7) if on else Color(0, 0, 0, 0)
			sb.shadow_size = 30 if on else 0
		var p: Control = _cards[i]["panel"]
		p.pivot_offset = p.size / 2
		Motion.scale_to(p, float(LOOK["grow"]) if on else 1.0, 0.14)

# ---------- Card actions ----------
func _activate() -> void:
	if bar_selected:
		_open_popup("perf")
		return
	var id: String = _cards[_sel]["id"]
	match id:
		"quit":
			close(true)
			quit_game_requested.emit()
		"notifications":
			_open_popup("notifications")
		"downloads":
			_dl_game = ""
			_dl_confirm = false
			_open_popup("downloads")
		"volume":
			_open_popup("sound")
		"wifi":
			_wifi_on = not _wifi_on
			OS.create_process("nmcli", ["radio", "wifi", "on" if _wifi_on else "off"])
			if not _wifi_on:
				_wifi_name = ""
				_wifi_signal = 0
		"album":
			close(true)
			album_requested.emit()
		"mods":
			close(true)
			mods_requested.emit()
		"files":
			Motion.fade_to(_row, 0.3, 0.15)  # the cards step back behind the browser
			_files.open()
		"browser":
			_open_popup("browser")
		"themes":
			_open_popup("themes")
			_popup_sel = maxi(Themes.ORDER.find(Themes.id()), 0)
			_refresh_popup()
		"perf":
			_open_popup("perf")
		"power":
			_open_popup("power")
	_refresh_values()

func _change_volume(step: int) -> void:
	if _vol_pct < 0:
		return
	# Whole-number steps and an exact target value, so presses can't drift.
	_vol_pct = clampi(snappedi(_vol_pct, 5) + 5 * step, 0, 100)
	_last_adjust_ms = Time.get_ticks_msec()
	if _bar_tween != null:
		_bar_tween.kill()
	if _muted:
		_muted = false
		OS.execute("pkill", ["-f", "tephra_audio_fade"], [])  # a mute fade still running must not win
		OS.create_process("wpctl", ["set-mute", "@DEFAULT_AUDIO_SINK@", "0"])
	OS.create_process("wpctl", ["set-volume", "@DEFAULT_AUDIO_SINK@", "%.2f" % (_vol_pct / 100.0)])
	_refresh_values()
	_refresh_popup()

const BRIGHT_MIN := 5

func _find_backlight() -> String:
	var d := DirAccess.open("/sys/class/backlight")
	if d == null:
		return ""
	for n in d.get_directories():
		if FileAccess.file_exists("/sys/class/backlight/%s/max_brightness" % n):
			return n
	return ""

func _read_backlight() -> void:
	var mx := _read_int("/sys/class/backlight/%s/max_brightness" % _bl_dir)
	var cur := _read_int("/sys/class/backlight/%s/brightness" % _bl_dir)
	if mx > 0 and cur >= 0:
		_bright_max = mx
		_brightness = roundi(cur * 100.0 / mx)

func _change_brightness(step: int) -> void:
	if _brightness < 0:
		return
	_brightness = clampi(_brightness + 10 * step, BRIGHT_MIN, 100)
	_bright_ms = Time.get_ticks_msec()
	_refresh_values()
	_queue_brightness()

# The screen is slow to talk to (and a monitor slower), so send only the latest value once presses settle.
func _queue_brightness() -> void:
	if _bright_pending:
		return
	_bright_pending = true
	await get_tree().create_timer(0.15 if _bl_dir != "" else 0.3).timeout
	_bright_pending = false
	var v := roundi(_brightness * _bright_max / 100.0)
	if _bl_dir != "":
		# logind lets the logged-in user set the backlight without root; brightnessctl and sysfs are fallbacks.
		var out := []
		if OS.execute("busctl", ["call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", _bl_dir, str(v)], out, true) != 0:
			if OS.execute("brightnessctl", ["-q", "-d", _bl_dir, "set", str(v)], out, true) != 0:
				var f := FileAccess.open("/sys/class/backlight/%s/brightness" % _bl_dir, FileAccess.WRITE)
				if f != null:
					f.store_string(str(v))
	else:
		OS.create_process("ddcutil", ["setvcp", "10", str(v), "--noverify"])

# ---------- Pop-up panels ----------
func _open_popup(kind: String) -> void:
	_popup_kind = kind
	_popup_card = null if kind == "perf" else _cards[_sel]["panel"]
	_popup_sel = 0
	_build_popup_rows()
	_popup.visible = true
	_popup.modulate.a = 0.0
	create_tween().tween_property(_popup, "modulate:a", 1.0, 0.15)
	refresh_hints()

func _close_popup() -> void:
	_popup_kind = ""
	_popup.visible = false
	_popup_card = null
	refresh_hints()

func _build_popup_rows() -> void:
	for c in _popup_box.get_children():
		_popup_box.remove_child(c)
		c.queue_free()
	_popup_rows = []
	if _popup_kind == "sound":
		# Kept short: one big volume bar (Left / Right change it from anywhere, A mutes), then the
		# speakers in use (A switches to the next one) and the microphone, only when there is a choice.
		_add_row("slider", "volume", "")
		if _sinks.size() > 1:
			_add_row("item", "sink_next", "")
		if _mic_present:
			_add_row("toggle", "mic", "")
	elif _popup_kind == "downloads":
		# A Tephra update waiting to be installed comes first.
		if SelfUpdate.state == "ready":
			_popup_box.add_child(_note("Tephra %s is available (you have %s)" % [SelfUpdate.remote, SelfUpdate.local_version()], 20))
			_add_row("item", "tephra_update", "Install Tephra %s (Tephra restarts)" % SelfUpdate.remote)
		elif SelfUpdate.state == "installing":
			_popup_box.add_child(_note("Installing Tephra %s. Tephra will restart by itself." % SelfUpdate.remote, 20))
		elif SelfUpdate.state == "failed":
			_popup_box.add_child(_note("The Tephra update didn't install. Nothing was changed.", 20))
			if SelfUpdate.remote != "":
				_add_row("item", "tephra_update", "Try again: install Tephra %s" % SelfUpdate.remote)
		elif SelfUpdate.state == "checking":
			_popup_box.add_child(_note("Looking for the Tephra update...", 20))
		elif SelfUpdate.state == "offline":
			_popup_box.add_child(_note("Couldn't reach GitHub to check for the Tephra update. Check the connection and open this again.", 20))
		var dl: Array = downloads_source.call() if downloads_source.is_valid() else []
		var shown_game := {}
		for d in dl:
			if str(d["id"]) == _dl_game:
				shown_game = d
		if _dl_game != "" and shown_game.is_empty():
			_dl_game = ""
		if _dl_game != "":
			_popup_box.add_child(_note("%s   %d%%   %s" % [str(shown_game["title"]), roundi(float(shown_game["pct"]) * 100.0), str(shown_game["state"])], 20))
			_popup_box.add_child(_dl_bar(float(shown_game["pct"]), str(shown_game["state"]), POPUP_TEXT_W + 60.0))
			_add_row("item", "dl_start:" + _dl_game, "Start / resume this game")
			if not bool(shown_game.get("installed", false)):  # an update to an installed game can only be paused, never removed
				_add_row("item", "dl_stop:" + _dl_game, "Press %s again to stop and delete the partial download" % TephraGlyphs.btn("accept") if _dl_confirm else "Stop this download")
			_add_row("item", "dl_back", "Back to the list")
		elif dl.is_empty() and SelfUpdate.state != "ready":
			_popup_box.add_child(_note("Nothing is downloading or waiting. Install a game from the Library to queue it.", 22))
		elif not dl.is_empty():
			var any_active := false
			for d in dl:
				if str(d["state"]) != "Paused":
					any_active = true
			_add_row("item", "dl_pause_all" if any_active else "dl_resume_all", "Pause all (closes Steam)" if any_active else "Resume all")
			for d in dl:
				_add_row("item", "dl:" + str(d["id"]), "%s   %d%%   %s" % [str(d["title"]), roundi(float(d["pct"]) * 100.0), str(d["state"])])
				_under_last_row(_dl_bar(float(d["pct"]), str(d["state"]), POPUP_TEXT_W))
	elif _popup_kind == "notifications":
		var all := Notifications.all()
		if all.is_empty():
			_popup_box.add_child(_note("Nothing yet. Updates, weather changes and battery warnings show up here.", 22))
		else:
			_add_row("item", "notif_clear", "Clear all")
			for i in mini(all.size(), 12):
				_add_row("item", "notif:%d" % i, "%s\n%s" % [Notifications.when(float(all[i]["time"])), str(all[i]["text"])])
		Notifications.mark_read()
	elif _popup_kind == "perf":
		_popup_box.add_child(_label("Show on the info bar", 20, MUTED))
		for it in Perf.ITEMS:
			_add_row("toggle", "perf:" + str(it[0]), str(it[1]))
		if game_running:
			if hud_status != "":
				var st := _label(hud_status, 18, MUTED)
				st.custom_minimum_size.x = 420
				st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_popup_box.add_child(st)
	elif _popup_kind == "browser":
		if game_id == Browser.ID:
			if bool(Settings.get_value("browser_page_mode", true)):
				_add_row("item", "br_page", "Page view")
			else:
				_add_row("item", "br_resume", "Back to the page")
			_add_row("item", "br_tabs", "Tabs")
			_add_row("item", "br_address", "Go to an address or search")
			_add_row("item", "br_mode", _overlay_row_text())
			_add_row("item", "br_close", "Close browser")
		else:
			for link in get_tree().current_scene.game_links:
				_add_row("item", "br_open:" + str(link), "From the game: " + str(link).get_slice("://", 1).get_slice("/", 0))
			_add_row("item", "br_ask", "Go to an address or search")
			for site in Browser.SITES:
				_add_row("item", "br_open:" + str(site[1]), str(site[0]))
			_add_row("item", "br_mode", _overlay_row_text())
			if game_running:
				_popup_box.add_child(_note("Quit the game first to open the browser.", 18))
	elif _popup_kind == "themes":
		_popup_box.add_child(_label("Theme", 20, MUTED))
		for g in Themes.GROUPS:
			_popup_box.add_child(_label(str(g[0]), 16, MUTED))
			for t in g[1]:
				_add_row("item", "theme:" + t, str(Themes.DATA[t]["name"]))
	elif _popup_kind == "power":
		_add_row("item", "suspend", "Rest mode")
		_add_row("item", "restart_tephra", "Restart Tephra")
		_add_row("item", "close_tephra", "Close Tephra")
		_add_row("item", "reboot", "Restart")
		_add_row("item", "poweroff", "Turn off")
	_popup_sel = clampi(_popup_sel, 0, _popup_rows.size() - 1)
	_refresh_popup()
	_fit_popup()

## A line of explanation: wraps within the pop-up's width, so a long sentence makes it taller instead of wider.
func _note(text: String, font_size: int) -> Label:
	var l := _label(text, font_size, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = POPUP_TEXT_W + 60.0
	return l

## The pop-up never goes off the screen: its rows scroll when the room above the card (or on the screen) is short.
func _fit_popup() -> void:
	var vp := _root.get_viewport_rect().size
	var need := _popup_box.get_combined_minimum_size()
	var room := vp.y - 40.0
	if _popup_card != null:
		room = _popup_card.get_global_rect().position.y - 28.0 - 20.0
	room -= 44.0  # the pop-up's own padding
	_popup_scroll.custom_minimum_size = Vector2(need.x, minf(need.y, maxf(room, 160.0)))
	_popup.reset_size()
	_popup_scroll.scroll_vertical = 0

func _add_row(type: String, action: String, text: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var mark := _label("", 26, TEXT)
	mark.custom_minimum_size.x = 22
	h.add_child(mark)
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	h.add_child(icon)
	var row := {"type": type, "action": action, "text": text, "mark": mark, "icon": icon}
	if type == "slider":
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(440, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bg := StyleBoxFlat.new()
		bg.bg_color = Themes.ink(0.18)
		bg.set_corner_radius_all(9)
		var fill := StyleBoxFlat.new()
		fill.bg_color = TEXT
		fill.set_corner_radius_all(9)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
		h.add_child(bar)
		row["bar"] = bar
	var l := _label(text, 26, TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 120 if type == "slider" else POPUP_TEXT_W
	h.add_child(l)
	row["label"] = l
	row["box"] = h
	_popup_box.add_child(h)
	_popup_rows.append(row)

## A download's progress as a filled bar (dimmer when paused or queued).
func _dl_bar(pct: float, state: String, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(pct, 0.0, 1.0)
	bar.custom_minimum_size = Vector2(width, 10)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bg := StyleBoxFlat.new()
	bg.bg_color = Themes.ink(0.18)
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(Themes.c("select"), 1.0 if state in ["Downloading", "Updating"] else 0.45)
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

## Puts a node right under the text of the row just added (the text and it stack in one column).
func _under_last_row(node: Control) -> void:
	var l: Label = _popup_rows[_popup_rows.size() - 1]["label"]
	var h := l.get_parent()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	h.remove_child(l)
	col.add_child(l)
	col.add_child(node)
	h.add_child(col)

func _refresh_popup() -> void:
	if _popup_kind == "":
		return
	for i in _popup_rows.size():
		var r: Dictionary = _popup_rows[i]
		var on := i == _popup_sel
		var l: Label = r["label"]
		var icon: TextureRect = r["icon"]
		var mark: Label = r["mark"]
		mark.text = "›" if on else ""
		l.add_theme_color_override("font_color", TEXT if on else MUTED)
		icon.modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)
		if on and r.has("box") and _popup_scroll != null:
			_popup_scroll.ensure_control_visible.call_deferred(r["box"])
		var action: String = r["action"]
		if action == "volume":
			var bar: ProgressBar = r["bar"]
			if _bar_tween == null or not _bar_tween.is_running():
				bar.value = _bar_target()
			l.text = "Muted" if _muted else ("%d%%" % _vol_pct if _vol_pct >= 0 else "-")
			icon.texture = Icons.texture(_vol_key(), _vol_svg(), 32)
		elif action == "sink_next":
			l.text = _sink_desc()
			icon.texture = Icons.texture("vol2false", Icons.svg_volume(2, false), 32)
		elif action.begins_with("perf:"):
			var key := action.substr(5)
			var is_on := bool(Settings.get_value(key, _perf_default(key)))
			l.text = r["text"]
			icon.texture = Icons.texture("check", Icons.svg_check(), 28) if is_on else null
		elif action == "perf_move":
			l.text = r["text"]
			icon.texture = Icons.texture("perf", Icons.svg_perf(), 32)
		elif action == "mute":
			l.text = "Sound muted" if _muted else "Mute sound"
			icon.texture = Icons.texture("vol0true", Icons.svg_volume(0, true), 32)
		elif action == "mic":
			l.text = "Mic muted" if _mic_muted else "Mic on"
			icon.texture = Icons.texture("mic%s" % _mic_muted, Icons.svg_mic(_mic_muted), 32)
		elif action.begins_with("dl"):
			l.text = r["text"]
			l.custom_minimum_size.x = POPUP_TEXT_W
			icon.texture = Icons.texture("download", Icons.svg_download(), 32)
		elif action == "notif_clear" or action.begins_with("notif:"):
			l.text = r["text"]
			l.custom_minimum_size.x = POPUP_TEXT_W
			icon.texture = Icons.texture("bell", Icons.svg_bell(), 32)
		elif action.begins_with("br_"):
			l.text = r["text"]
			l.custom_minimum_size.x = POPUP_TEXT_W
			icon.texture = Icons.texture("globe", Icons.svg_globe(), 32)
		elif action.begins_with("theme:"):
			var tid := action.substr(6)
			l.text = r["text"] + ("   ✓" if tid == Themes.id() else "")
			icon.texture = Themes.swatch(tid, 44, 28)
			icon.modulate = Color.WHITE
		elif action == "suspend" or action == "restart_tephra" or action == "close_tephra" or action == "reboot" or action == "poweroff":
			l.text = r["text"]
			var pk: String = {"suspend": "moon", "restart_tephra": "refresh", "close_tephra": "close", "reboot": "restart", "poweroff": "power"}[action]
			var psvg: String = {"moon": Icons.svg_moon(), "refresh": Icons.svg_refresh(), "close": Icons.svg_close(), "restart": Icons.svg_restart(), "power": Icons.svg_power()}[pk]
			icon.texture = Icons.texture(pk, psvg, 32)

func _popup_activate() -> void:
	var r: Dictionary = _popup_rows[_popup_sel]
	var action: String = r["action"]
	_last_adjust_ms = Time.get_ticks_msec()
	if action.begins_with("perf:"):
		var key := action.substr(5)
		Settings.set_value(key, not bool(Settings.get_value(key, _perf_default(key))))
		perf_changed.emit()
	elif action == "perf_move":
		_close_popup()
		perf_move_requested.emit()
	elif action == "sink_next":
		var idx := 0
		for i in _sinks.size():
			if _sinks[i]["name"] == _default_sink:
				idx = i
		if not _sinks.is_empty():
			_default_sink = str(_sinks[(idx + 1) % _sinks.size()]["name"])
			OS.create_process("pactl", ["set-default-sink", _default_sink])
	elif action == "mute" or action == "volume":
		_muted = not _muted
		AudioFade.set_muted(float(_vol_pct) / 100.0, _muted)  # fades out / in instead of snapping
		_slide_bar()
		refresh_hints()
	elif action == "mic":
		_mic_muted = not _mic_muted
		OS.create_process("pactl", ["set-source-mute", "@DEFAULT_SOURCE@", "1" if _mic_muted else "0"])
	elif action == "dl_pause_all":
		download_action.emit("pause_all", "")
	elif action == "dl_resume_all":
		download_action.emit("resume_all", "")
	elif action == "dl_back":
		_dl_game = ""
		_dl_confirm = false
		_build_popup_rows()
	elif action.begins_with("dl_start:"):
		download_action.emit("start", action.substr(9))
	elif action.begins_with("dl_stop:"):
		if _dl_confirm:
			_dl_confirm = false
			download_action.emit("stop", action.substr(8))
			_dl_game = ""
		else:
			_dl_confirm = true
		_build_popup_rows()
	elif action.begins_with("dl:"):
		_dl_game = action.substr(3)
		_dl_confirm = false
		_popup_sel = 0
		_build_popup_rows()
	elif action == "notif_clear":
		Notifications.clear()
		_build_popup_rows()
	elif action.begins_with("notif:"):
		var all := Notifications.all()
		var i := int(action.substr(6))
		if i < all.size() and str(all[i]["kind"]) == "tephra_update":
			# "Update available": A takes you to the Downloads panel to install it. If Tephra hasn't looked yet this
			# run (or the last look failed), it looks now, so the notice never sits there unclickable.
			if not SelfUpdate.state in ["ready", "installing"]:
				SelfUpdate.state = "idle"
				SelfUpdate.check(get_tree().current_scene, func(_r: String) -> void:
					if is_open and _popup_kind == "downloads":
						_build_popup_rows()
						refresh_hints())
			_popup_kind = "downloads"
			_dl_game = ""
			_dl_confirm = false
			_popup_sel = 0
			_build_popup_rows()
			refresh_hints()
			return
		Notifications.remove(i)  # A on one removes it
		_build_popup_rows()
	elif action == "tephra_update":
		SelfUpdate.install(get_tree().current_scene, func(result: String) -> void:
			if result == "failed" and is_open and _popup_kind == "downloads":
				_build_popup_rows())
		_build_popup_rows()
	elif action.begins_with("br_open:"):
		_close_popup()
		browser_action.emit("open", action.substr(8))
	elif action.begins_with("br_"):
		_close_popup()
		browser_action.emit(action.substr(3), "")
	elif action.begins_with("theme:"):
		if action.substr(6) != Themes.id():
			theme_requested.emit(action.substr(6))
		else:
			_close_popup()
	elif action == "suspend":
		close(true)
		OS.create_process("systemctl", ["suspend"])
	elif action == "restart_tephra":
		# Start a fresh Tephra a second from now (so this one has let go of the
		# screen and controllers), then close this one. Reloads every script and
		# re-reads Steam, which is handy after an update or when something's stuck.
		get_tree().current_scene.restart_tephra()  # closes the game, PCSX2 and Steam first
	elif action == "close_tephra":
		# Quit Tephra and leave the desktop (same as Ctrl+Alt+Q). Games and the browser close with it.
		get_tree().current_scene.close_tephra()
	elif action == "reboot":
		get_tree().current_scene.power_command("reboot")
	elif action == "poweroff":
		get_tree().current_scene.power_command("poweroff")
	_refresh_popup()
	_refresh_values()

# The volume bar follows muting: it slides down to empty with the fade, and back up to the
# old level on unmute (the level itself is kept, so unmuting brings back exactly what it was).
var _bar_tween: Tween

func _bar_target() -> float:
	return 0.0 if _muted else float(maxi(_vol_pct, 0))

func _slide_bar() -> void:
	for r in _popup_rows:
		if r["action"] == "volume":
			if _bar_tween != null:
				_bar_tween.kill()
			_bar_tween = create_tween()
			_bar_tween.tween_property(r["bar"], "value", _bar_target(), AudioFade.SECONDS).set_trans(Tween.TRANS_SINE)

func _sink_desc() -> String:
	for k in _sinks:
		if k["name"] == _default_sink:
			return str(k["desc"])
	return "-"

func _perf_default(key: String) -> bool:
	for it in Perf.ITEMS:
		if it[0] == key:
			return bool(it[2])
	return false

func _perf_count() -> int:
	var n := 0
	for it in Perf.ITEMS:
		if bool(Settings.get_value(str(it[0]), it[2])):
			n += 1
	return n

# ---------- Card icons and values ----------
func _vol_key() -> String:
	return "vol%d%s" % [_vol_level(), _muted or _vol_pct == 0]

func _vol_svg() -> String:
	return Icons.svg_volume(_vol_level(), _muted or _vol_pct == 0)

func _vol_level() -> int:
	if _vol_pct > 66:
		return 3
	if _vol_pct > 33:
		return 2
	return 1 if _vol_pct > 0 else 0

func _refresh_values() -> void:
	var pads := {}
	if controllers != null:
		for c in controllers.list():
			pads[c["slot"]] = c
	for c in _cards:
		var icon: TextureRect = c["icon"]
		var l: Label = c["value"]
		l.visible = not (c["id"] == "power" or c["id"] == "quit")  # no text: icon sits in the middle
		match c["id"]:
			"quit":
				icon.texture = Icons.texture("quit", Icons.svg_quit(), ICON_PX)
				l.text = ""
			"downloads":
				icon.texture = Icons.texture("download", Icons.svg_download(), ICON_PX)
				var dl: Array = downloads_source.call() if downloads_source.is_valid() else []
				if SelfUpdate.state == "ready":
					l.text = "Update"
				elif dl.is_empty():
					l.text = "None"
				else:
					var active := 0
					for d in dl:
						if str(d["state"]) in ["Downloading", "Updating"]:
							active += 1
					l.text = ("%d%%" % roundi(float(dl[0]["pct"]) * 100.0)) if active == 1 and dl.size() == 1 else ("1 game" if dl.size() == 1 else "%d games" % dl.size())
			"notifications":
				icon.texture = Icons.texture("bell", Icons.svg_bell(), ICON_PX)
				var nu := Notifications.unread()
				l.text = "%d new" % nu if nu > 0 else "None new"
			"volume":
				icon.texture = Icons.texture(_vol_key(), _vol_svg(), ICON_PX)  # 0% shows mute too
				if _vol_pct < 0:
					l.text = "-"
				elif _muted:
					l.text = "Muted"
				else:
					l.text = "%d%%" % _vol_pct
			"brightness":
				if _bl_dir != "" and Time.get_ticks_msec() - _bright_ms > 2000:
					_read_backlight()
				var lv := 0 if _brightness <= 25 else (1 if _brightness <= 50 else (2 if _brightness <= 75 else 3))
				icon.texture = Icons.texture("sunlv%d" % lv, Icons.svg_sun_level(lv), ICON_PX)
				l.text = ""
				l.visible = false  # just the sun, no words: the icon sits in the card's middle
			"wifi":
				var bars := 0
				if _wifi_on and _wifi_name != "":
					bars = 1 if _wifi_signal < 40 else (2 if _wifi_signal < 70 else 3)
				icon.texture = Icons.texture("wifi%d%s" % [bars, _wifi_on], Icons.svg_wifi(bars, _wifi_on), ICON_PX)
				l.text = _wifi_name if _wifi_on else "Off"
			"battery":
				var pct := _read_int(_laptop_bat + "/capacity")
				var charging := _read(_laptop_bat + "/status") == "Charging"
				var level := roundi(maxi(pct, 0) / 20.0)  # 0 to 5 steps, so the cache stays small
				icon.texture = Icons.texture("bat%d%s" % [level, charging], Icons.svg_battery(level / 5.0, charging), ICON_PX)
				l.text = "%d%%" % pct if pct >= 0 else "-"
			"controller":
				var info: Dictionary = pads.get(c["slot"], {})
				var fam: String = info.get("family", "generic")
				icon.texture = Icons.texture("pad_" + fam, Icons.svg_pad(fam), ICON_PX)
				var bat: int = info.get("battery", -1)
				l.text = ("%d%%" % bat + (" +" if info.get("charging", false) else "")) if bat >= 0 else "Connected"
			"album":
				icon.texture = Icons.texture("album", Icons.svg_album(), ICON_PX)
				l.text = "Album"
			"mods":
				icon.texture = Icons.texture("mods", Icons.svg_mods(), ICON_PX)
				l.text = "Mods"
			"files":
				icon.texture = Icons.texture("folder", Icons.svg_folder(), ICON_PX)
				l.text = "Files"
			"browser":
				icon.texture = Icons.texture("globe", Icons.svg_globe(), ICON_PX)
				l.text = "Open" if game_id == Browser.ID else "Web"
			"perf":
				icon.texture = Icons.texture("perf", Icons.svg_perf(), ICON_PX)
				l.text = "%d shown" % _perf_count()
			"themes":
				icon.texture = Icons.texture("palette", Icons.svg_palette(), ICON_PX)
				l.text = str(Themes.data()["name"])
			"power":
				icon.texture = Icons.texture("power", Icons.svg_power(), ICON_PX)
				l.text = ""

func _find_laptop_battery() -> String:
	var dir := DirAccess.open("/sys/class/power_supply")
	if dir == null:
		return ""
	var names := Array(dir.get_directories()) + Array(dir.get_files())
	for d: String in names:
		if d.begins_with("BAT") and _read_int("/sys/class/power_supply/" + d + "/capacity") >= 0:
			return "/sys/class/power_supply/" + d
	return ""

# Read one line from a /sys file (get_file_as_string returned garbage for these).
func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_line().strip_edges() if f != null else ""

func _read_int(path: String) -> int:
	var s := _read(path)
	return s.to_int() if s.is_valid_int() else -1

# ---------- Reading system state (in the background) ----------
# Changing the theme rebuilds the control center; a reading still running would reach into the freed
# one when it finished and crash Tephra, so it is waited for first.
func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1

## The clock sits exactly on Home's clock: same font, size, alignment and words, so opening the control center
## never makes it jump; only the dimming behind it changes, and the clock itself stays bright above it.
var _clock_src: Label

func match_clock(src: Label, at: Rect2) -> void:
	_clock_src = src
	_clock.add_theme_font_override("font", src.get_theme_font("font"))
	_clock.add_theme_font_size_override("font_size", src.get_theme_font_size("font_size"))
	_clock.add_theme_constant_override("outline_size", src.get_theme_constant("outline_size"))
	_clock.add_theme_color_override("font_outline_color", src.get_theme_color("font_outline_color"))
	_clock.horizontal_alignment = src.horizontal_alignment
	_clock.vertical_alignment = src.vertical_alignment
	_clock.position = at.position
	_clock.size = at.size
	_clock.text = src.text

func _read_system_state() -> void:
	if _reading:
		return
	_reading = true
	_last_read_ms = Time.get_ticks_msec()
	_task_id = WorkerThreadPool.add_task(_read_state_task)

func _read_state_task() -> void:
	var s := {}
	s["volume"] = _cmd("wpctl", ["get-volume", "@DEFAULT_AUDIO_SINK@"])
	s["wifi"] = _cmd("nmcli", ["-t", "-f", "WIFI", "radio"])
	s["ssid"] = _cmd("nmcli", ["-t", "-f", "ACTIVE,SIGNAL,SSID", "dev", "wifi"])
	s["sinks"] = _cmd("pactl", ["-f", "json", "list", "sinks"])
	s["default_sink"] = _cmd("pactl", ["get-default-sink"])
	s["default_source"] = _cmd("pactl", ["get-default-source"])
	s["mic_mute"] = _cmd("pactl", ["get-source-mute", "@DEFAULT_SOURCE@"])
	s["brightness"] = _cmd("ddcutil", ["getvcp", "10", "--brief"]) if DDC_BRIGHTNESS else ""
	_apply_state.call_deferred(s)

func _cmd(path: String, args: PackedStringArray) -> String:
	var out := []
	var code := OS.execute(path, args, out)
	if code != 0 or out.is_empty():
		return ""
	return str(out[0])

func _apply_state(s: Dictionary) -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	_reading = false
	var fresh := Time.get_ticks_msec() - _last_adjust_ms > 1500  # skip readings older than our own changes

	var vol: String = s["volume"]  # e.g. "Volume: 0.45 [MUTED]"
	if vol.begins_with("Volume:") and fresh:
		_vol_pct = roundi(vol.split(" ", false)[1].to_float() * 100.0)
		_muted = vol.contains("MUTED")

	var wifi: String = s["wifi"]
	_wifi_on = wifi.strip_edges() == "enabled"
	_wifi_name = ""
	_wifi_signal = 0
	var ssid: String = s["ssid"]  # lines like "yes:72:MyNetwork"
	for line in ssid.split("\n"):
		if line.begins_with("yes:"):
			var parts := line.split(":", true, 2)
			if parts.size() == 3:
				_wifi_signal = parts[1].to_int()
				_wifi_name = parts[2]

	var sinks = JSON.parse_string(s["sinks"]) if s["sinks"] != "" else null
	if sinks is Array:
		var list: Array = []
		for k in sinks:
			if k is Dictionary:
				list.append({"name": str(k.get("name", "")), "desc": str(k.get("description", k.get("name", "")))})
		var changed := list.size() != _sinks.size()
		_sinks = list
		if fresh:
			_default_sink = str(s["default_sink"]).strip_edges()
		if changed and _popup_kind == "sound":
			_build_popup_rows()
	var src: String = str(s["default_source"]).strip_edges()
	var had_mic := _mic_present
	_mic_present = src != "" and not src.ends_with(".monitor")
	if had_mic != _mic_present and _popup_kind == "sound":
		_build_popup_rows()
	if fresh:
		_mic_muted = str(s["mic_mute"]).contains("yes")

	var br: String = s["brightness"]  # e.g. "VCP 10 C 50 100"
	var bparts := br.split(" ", false)
	if bparts.size() >= 5 and bparts[0] == "VCP":
		_bright_max = maxi(bparts[4].to_int(), 1)
		_brightness = roundi(bparts[3].to_int() * 100.0 / _bright_max)

	_refresh_values()
	_refresh_popup()
