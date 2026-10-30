extends CanvasLayer
## Tephra's Settings screen. Opened from the gear in the top bar.
## Settings are grouped into tabs (L1 / R1, or Q / E on a keyboard, switch tab):
##     Display  -  Audio  -  Controller  -  Accessibility  -  Updates  -  System
## Up/Down picks a row, Left/Right changes it (or A cycles it). Each row is one of:
##     toggle  - on/off, saved in Settings
##     choice  - one of a few values, saved in Settings
##     custom  - reads and changes the system directly (volume, output device, ...)
##     action  - does something when you press A
##     info    - just shows a fact (not selectable)

const TephraGlyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
const Icons = preload("res://icons.gd")
const Settings = preload("res://settings.gd")
const Visuals = preload("res://visuals.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const DisplayCtl = preload("res://display_ctl.gd")
const DetentSlider = preload("res://detent_slider.gd")
const RATE_STOPS := [30, 60, 90, 120, 144, 180, 240]  # refresh rates shown on the slider, evenly spaced
const NITS_STOPS := [100, 200, 300, 400, 500, 600]

var BG: Color = Themes.c("bg")
var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var SELECT: Color = Themes.c("select")

const Ps2Games = preload("res://ps2_games.gd")
const TABS := ["System", "Display", "Themes", "Audio", "Controllers", "Games", "Accessibility"]
const FPS_CAPS := [30, 60, 90, 120, 240, 0, -1]  # 0 = no limit, -1 = variable (no limit, and the screen follows the frame rate)
const FPS_NAMES := ["30", "60", "90", "120", "240", "∞", "Variable"]
const AudioFade = preload("res://audio_fade.gd")
const VIB_NAMES := ["Off", "Low", "Medium", "High"]
const DEAD_VALUES := [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4]
const DEAD_NAMES := ["None", "5%", "10%", "15%", "20%", "25%", "30%", "40%"]
const LIGHT_MODES := ["theme", "battery", "custom"]
const LIGHT_NAMES := ["Tephra theme", "Battery level", "Custom colour"]
const REST_VALUES := [0, 5, 10, 20, 30]
const REST_NAMES := ["Never", "5 min", "10 min", "20 min", "30 min"]
const START_VOL_VALUES := [-1, 25, 50, 75]
const START_VOL_NAMES := ["Keep as it is", "25%", "50%", "75%"]
const SND_VALUES := [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
const SND_NAMES := ["Off", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"]
const CONFIRM_SECONDS := 12.0
const GLYPH_CHOICES := ["", "ds5", "ds4", "xbox", "nintendo", "keyboard"]
const GLYPH_NAMES := ["Auto-detect", "DualSense (PS5)", "DualShock 4 (PS4)", "Xbox", "Nintendo", "Keyboard"]

var is_open := false
var _home  # home.gd
var _root: Control
var _clock: Label
var _list: VBoxContainer
var _hints: HBoxContainer
var _rows: Array = []     # selectable rows only: {kind, key, text, panel, style, value_label, ...}
var _sel := 0
var _tab := 0
var _tab_labels: Array = []
var _scroll: ScrollContainer
var _bar: Control              # the scroll bar next to the list
var _bar_pos := 0.0            # where its handle is drawn (glides after the list)
var _log: Label
var _log_mode := false
var _log_card: PanelContainer
var _log_only := false
var _info_only := false  # Channels theme's Info button: a read-only page about Tephra and this PC
var _title: Label
var _strip: HBoxContainer
var _log_lines: PackedStringArray = []
var _log_off := 0

# What the Audio tab shows (read when the tab opens).
var _vol := -1
var _muted := false
var _sinks: Array = []     # [{name, desc}]
var _sink := ""
var _mic_present := false
var _mic_muted := false
# What the Updates tab shows (read from git when the tab opens).
var _git := {}
# Display tab: the resolution/refresh you are choosing (applied with Accept) and the
# "keep these display settings?" countdown.
var _res_list: Array = []
var _res_i := 0
var _rate_hz := 60
var _confirm := 0.0
var _prev_mode := {}
var _note: Label

func setup(home) -> void:
	_home = home

func _ready() -> void:
	layer = 80
	apply_display()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BG
	_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var anim = preload("res://tephra_bg.gd").new()
	anim.set("plain", true)  # Temple theme: no desktop windows behind a full page
	_root.add_child(anim)
	anim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	margin.add_child(v)

	var top_gap := Control.new()  # same row as the home clock (placed in open())
	top_gap.custom_minimum_size.y = 56
	v.add_child(top_gap)
	_title = _label("Settings", 60, TEXT)
	v.add_child(_title)

	# Tab strip: [L1] System  Display  Audio  Controllers  Accessibility [R1]
	var strip := HBoxContainer.new()
	_strip = strip
	strip.add_theme_constant_override("separation", 34)
	v.add_child(strip)
	strip.add_child(TephraGlyphs.glyph("l1", 34))
	for t in TABS:
		var l := _label(t, 26, MUTED)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		strip.add_child(l)
		_tab_labels.append(l)
	strip.add_child(TephraGlyphs.glyph("r1", 34))

	# The list, with a thin scroll bar on its right that shows where you are in a long page.
	var list_row := HBoxContainer.new()
	list_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_row.add_theme_constant_override("separation", 18)
	v.add_child(list_row)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	list_row.add_child(_scroll)
	_bar = Control.new()
	_bar.custom_minimum_size.x = 8
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_scrollbar)
	list_row.add_child(_bar)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.custom_minimum_size.x = 1000
	_scroll.add_child(_list)

	# The log sits in its own card with room around it (Developer menu > View log opens only this).
	_log_card = PanelContainer.new()
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Themes.ink(0.05)
	lsb.set_corner_radius_all(Themes.r(18))
	lsb.content_margin_left = 36
	lsb.content_margin_right = 36
	lsb.content_margin_top = 28
	lsb.content_margin_bottom = 28
	_log_card.add_theme_stylebox_override("panel", lsb)
	_log_card.visible = false
	_log_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_log_card)
	_log = _label("", 19, TEXT.lerp(MUTED, 0.4))
	_log.clip_text = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_card.add_child(_log)

	_note = _label("", 26, Color("FFC857"))
	_note.visible = false
	v.add_child(_note)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(_hints)

	_clock = _label("", 32, TEXT)
	_root.add_child(_clock)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Frame-rate cap and VSync, applied at startup and when changed. A setting that was
## never touched leaves Godot's own value alone.
func apply_display() -> void:
	var cap = Settings.get_value("fps_cap", null)
	if cap != null:
		Engine.max_fps = maxi(int(cap), 0)
	if Visuals.saver():
		Engine.max_fps = 30  # Power saver locks the frame limit
	var vs = Settings.get_value("vsync", null)
	if cap != null and int(cap) < 0:
		# Variable: no limit, and adaptive sync, so a FreeSync / G-Sync screen follows Tephra's frame rate
		# (and a frame that comes late is shown at once instead of waiting a whole refresh)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
	elif vs != null:
		var on_mode := DisplayServer.VSYNC_MAILBOX if bool(Settings.get_value("vsync_smooth", false)) else DisplayServer.VSYNC_ENABLED
		DisplayServer.window_set_vsync_mode(on_mode if bool(vs) else DisplayServer.VSYNC_DISABLED)
	elif DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ADAPTIVE:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)  # leaving Variable: back to normal sync

# ---------- Rows ----------
func _definitions() -> Array:
	if _info_only:
		var info: Array = [
			{"kind": "header", "text": "Tephra"},
			{"kind": "info", "text": "Installed version", "value": str(_git.get("version", "-"))},
			{"kind": "info", "text": "Last change", "value": str(_git.get("message", "-"))},
			{"kind": "info", "text": "Updated", "value": str(_git.get("date", "-"))},
			{"kind": "info", "text": "Theme", "value": str(Themes.data()["name"])},
			{"kind": "header", "text": "This PC"},
		]
		if _home != null and _home.perf != null:
			for pair in _home.perf.system_info(_home.steam_dir):
				info.append({"kind": "info", "text": str(pair[0]), "value": str(pair[1])})
		return info
	var vsync_now: bool = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	match _tab:
		0:
			# System: Tephra itself and its updates first, then everyday options, power, and the PC's details last.
			var rows: Array = [
				{"kind": "header", "text": "Tephra"},
				{"kind": "info", "text": "Installed version", "value": str(_git.get("version", "-"))},
				{"kind": "info", "text": "Last change", "value": str(_git.get("message", "-"))},
				{"kind": "info", "text": "Updated", "value": str(_git.get("date", "-"))},
				{"kind": "toggle", "key": "auto_restart_update", "text": "When an update arrives", "off": "Ask me (restart by hand)", "on": "Restart right away", "default": true},
				{"kind": "action", "key": "restart", "text": "Restart Tephra"},
				{"kind": "action", "key": "close", "text": "Close Tephra"},
				{"kind": "header", "text": "Time and units"},
				{"kind": "toggle", "key": "clock_24h", "text": "Clock", "off": "12-hour", "on": "24-hour", "default": false},
				{"kind": "toggle", "key": "temp_c", "text": "Temperature", "off": "Fahrenheit (°F)", "on": "Celsius (°C)", "default": false},
				{"kind": "header", "text": "Power"},
				{"kind": "choice", "slider": true, "key": "idle_minutes", "text": "Dim the screen when idle", "values": REST_VALUES, "names": REST_NAMES, "default": 0},
				{"kind": "action", "key": "suspend", "text": "Rest mode"},
				{"kind": "action", "key": "reboot", "text": "Restart PC"},
				{"kind": "action", "key": "poweroff", "text": "Turn off PC"},
				{"kind": "header", "text": "Help"},
				{"kind": "action", "key": "view_log", "text": "View Tephra's log"},
				{"kind": "action", "key": "redo_setup", "text": "Run first-boot setup again"},
				{"kind": "toggle", "key": "files_show_all", "text": "Files", "off": "Hide system folders", "on": "Show hidden and system folders", "default": false},
				{"kind": "action", "key": "clear_art", "text": "Clear cover art cache"},
				{"kind": "action", "key": "clear_ach", "text": "Clear achievement cache"},
				{"kind": "header", "text": "This PC"},
			]
			if _home != null and _home.perf != null:
				for pair in _home.perf.system_info(_home.steam_dir):
					rows.append({"kind": "info", "text": str(pair[0]), "value": str(pair[1])})
			return rows
		1:
			var rows: Array = [
				{"kind": "header", "text": "Screen"},
			]
			if DisplayServer.get_screen_count() > 1:
				rows.append({"kind": "custom", "key": "screen", "text": "Switch display"})
			if DisplayCtl.available():
				rows.append({"kind": "custom", "key": "resolution", "text": "Resolution"})
				rows.append({"kind": "custom", "key": "refresh", "text": "Refresh rate"})
				rows.append({"kind": "choice", "slider": true, "key": "fps_cap", "text": "Frame rate limit", "values": FPS_CAPS, "names": FPS_NAMES, "default": 0})
				rows.append({"kind": "toggle", "key": "vsync", "text": "VSync", "off": "Off", "on": "On", "default": vsync_now})
				rows.append({"kind": "toggle", "key": "vsync_smooth", "text": "VSync style", "off": "Standard", "on": "Smooth (always shows the newest frame)", "default": false})
				rows.append({"kind": "header", "text": "HDR"})
				rows.append({"kind": "action", "key": "hdr_calibrate", "text": "Calibrate display (brightness test)"})
				if DisplayCtl.hdr_supported():
					rows.append({"kind": "custom", "key": "hdr", "text": "HDR"})
					rows.append({"kind": "custom", "key": "wcg", "text": "Wide colour gamut"})
					rows.append({"kind": "custom", "key": "sdr_nits", "text": "Brightness of non-HDR content"})
				else:
					rows.append({"kind": "info", "text": "This display doesn't report HDR support."})
			else:
				rows.append({"kind": "info", "text": "Resolution, refresh rate and HDR need KDE's kscreen-doctor, which Tephra couldn't find."})
				rows.append({"kind": "choice", "slider": true, "key": "fps_cap", "text": "Frame rate limit", "values": FPS_CAPS, "names": FPS_NAMES, "default": 0})
				rows.append({"kind": "toggle", "key": "vsync", "text": "VSync", "off": "Off", "on": "On", "default": vsync_now})
				rows.append({"kind": "toggle", "key": "vsync_smooth", "text": "VSync style", "off": "Standard", "on": "Smooth (always shows the newest frame)", "default": false})
			rows.append({"kind": "header", "text": "Performance"})
			rows.append({"kind": "choice", "key": "gpu_mode", "text": "Menu power use", "values": ["saver", "normal"], "names": ["Saver (30 FPS)", "Normal"], "default": "normal"})
			rows.append({"kind": "info", "text": "Tephra already slows itself down when you're idle and stops drawing while a game runs."})
			rows.append({"kind": "header", "text": "Look"})
			rows.append({"kind": "toggle", "key": "tile_shine", "text": "Shine on the selected tile", "off": "Off", "on": "On", "default": true})
			return rows
		2:
			# Themes: pick one and Tephra restarts with it (every screen reads its colours when it is made).
			var rows: Array = []
			for g in Themes.GROUPS:
				rows.append({"kind": "header", "text": str(g[0])})
				for t in g[1]:
					var td: Dictionary = Themes.DATA[t]
					rows.append({"kind": "action", "key": "theme:" + t, "text": "%s   ·   %s" % [td["name"], td["blurb"]],
						"icon": Themes.swatch(t)})
			rows.append({"kind": "info", "text": "Choosing a theme fades the screen to black for a moment while it is put on. Channels and PS2 also change Home into their own layouts, and every theme brings its own sounds, music and font."})
			return rows
		3:
			var rows: Array = [
				{"kind": "custom", "key": "volume", "text": "Volume"},
				{"kind": "custom", "key": "mute", "text": "Sound"},
			]
			if _sinks.size() > 1:
				rows.append({"kind": "custom", "key": "sink", "text": "Output"})
			if _mic_present:
				rows.append({"kind": "custom", "key": "mic", "text": "Microphone"})
				rows.append({"kind": "custom", "key": "mic_test", "text": "Test microphone"})
			rows.append({"kind": "header", "text": "Tephra sounds"})
			rows.append({"kind": "choice", "slider": true, "key": "sfx_volume", "text": "Menu sounds", "values": SND_VALUES, "names": SND_NAMES, "default": 60})
			rows.append({"kind": "choice", "slider": true, "key": "music_volume", "text": "Background music", "values": SND_VALUES, "names": SND_NAMES, "default": 50})
			rows.append({"kind": "header", "text": "Startup"})
			rows.append({"kind": "choice", "slider": true, "key": "startup_volume", "text": "Volume when Tephra starts", "values": START_VOL_VALUES, "names": START_VOL_NAMES, "default": -1})
			return rows
		4:
			return [
				{"kind": "header", "text": "Buttons"},
				{"kind": "choice", "key": "glyph_override", "text": "Button glyphs", "values": GLYPH_CHOICES, "names": GLYPH_NAMES, "default": ""},
				{"kind": "toggle", "key": "show_hints", "text": "Button hints", "off": "Hidden", "on": "Shown", "default": true},
				{"kind": "toggle", "key": "guide_swap", "text": "PS / Guide button", "off": "Press: control center  -  Hold: home", "on": "Press: home  -  Hold: control center", "default": false},
				{"kind": "toggle", "key": "screenshot_btn", "text": "Touchpad click (Share on Xbox)", "off": "Does nothing", "on": "Screenshot (hold: record)", "default": true},
				{"kind": "toggle", "key": "touchpad_layout", "text": "Touchpad click in games", "off": "Steam's default (Select / Start)", "on": "Off (only Tephra's screenshot)", "default": true},
				{"kind": "header", "text": "Controllers"},
				{"kind": "info", "text": "P1 is the first to connect. Choose a controller to put it in charge."},
				{"kind": "pads"},
				{"kind": "header", "text": "Sticks"},
				{"kind": "choice", "slider": true, "key": "deadzone", "text": "Stick dead zone", "values": DEAD_VALUES, "names": DEAD_NAMES, "default": 0.15},
				{"kind": "action", "key": "pad_test", "text": "Test buttons, sticks and triggers"},
				{"kind": "info", "text": "Motion (gyro) controls can't be read by Tephra yet, so there is nothing to adjust for them."},
				{"kind": "header", "text": "Vibration"},
				{"kind": "choice", "slider": true, "key": "vibration", "text": "Vibration strength", "values": [0, 1, 2, 3], "names": VIB_NAMES, "default": 2},
				{"kind": "toggle", "key": "vib_nav", "text": "When browsing", "off": "Off", "on": "On", "default": true},
				{"kind": "toggle", "key": "vib_launch", "text": "When opening a game", "off": "Off", "on": "On", "default": true},
				{"kind": "action", "key": "vib_try", "text": "Try the vibration"},
				{"kind": "header", "text": "Battery"},
				{"kind": "toggle", "key": "battery_flash", "text": "Low battery alerts", "off": "Off", "on": "On", "default": true},
				{"kind": "info", "text": "The controller icon in the top bar is green above 30%, orange at 30% or less and red at 10% or less. When the battery drops to one of those levels the lightbar pulses once in that colour, with a notification if the icon isn't on screen."},
			]
		5:
			# Games: how they start and behave, then Steam, PS2 and RetroAchievements.
			return [
				{"kind": "header", "text": "Playing"},
				{"kind": "toggle", "key": "cross_opens_info", "text": "Pressing a game", "off": "Starts it", "on": "Shows its info first (Play, Unpin, Rename)", "default": false},
				{"kind": "toggle", "key": "cc_keep_running2", "text": "Game behind the control center", "off": "Paused (frozen)", "on": "Keeps running, with its sound", "default": true},
				{"kind": "toggle", "key": "capture_links", "text": "Links from games", "off": "Open in the desktop browser", "on": "Keep out of the desktop browser", "default": true},
				{"kind": "header", "text": "Steam"},
				{"kind": "toggle", "key": "auto_update", "text": "Update games automatically", "off": "No (Steam updates a game when you play it)", "on": "Yes, in the background while you're on Home", "default": true},
				{"kind": "toggle", "key": "steam_autoclose", "text": "Close Steam when no game is running", "off": "No", "on": "Yes", "default": true},
				{"kind": "action", "key": "rescan", "text": "Re-scan games"},
				{"kind": "action", "key": "close_steam", "text": "Close Steam now"},
				{"kind": "info", "text": "Family members added", "value": str(Settings.get_value("family_ids", []).size())},
				{"kind": "action", "key": "family_add", "text": "Add a Steam Family member"},
				{"kind": "action", "key": "family_clear", "text": "Remove added family members"},
				{"kind": "header", "text": "PS2 games"},
				{"kind": "info", "text": "Games folder", "value": Ps2Games.games_dir()},
				{"kind": "info", "text": "PS2 BIOS", "value": "Found" if Ps2Games.has_bios() else "Missing (put your scph*.bin in the folder above)"},
				{"kind": "action", "key": "ps2_scan", "text": "Scan for PS2 games now"},
				{"kind": "header", "text": "RetroAchievements"},
				{"kind": "info", "text": "Signed in as", "value": str(Settings.get_value("ra_user", "")) if str(Settings.get_value("ra_key", "")) != "" else "Not signed in"},
				{"kind": "action", "key": "ra_user", "text": "Set user name"},
				{"kind": "action", "key": "ra_key", "text": "Set web API key (retroachievements.org > Settings)"},
				{"kind": "action", "key": "ra_check", "text": "Check sign-in and sync now"},
				{"kind": "action", "key": "ra_out", "text": "Sign out"},
				{"kind": "info", "text": "To earn them in a game, also log in once inside PCSX2 (Settings > Achievements)."},
			]
		_:
			return [
				{"kind": "header", "text": "Interface"},
				{"kind": "choice", "slider": true, "key": "ui_scale", "text": "Interface size", "values": [90, 95, 100, 105, 110, 115], "names": ["90%", "95%", "100%", "105%", "110%", "115%"], "default": 100},
				{"kind": "info", "text": "Makes every menu, word and tile bigger or smaller. Bigger is easier to read from the couch."},
				{"kind": "header", "text": "Motion"},
				{"kind": "toggle", "key": "animations", "text": "Animations", "off": "Off (instant)", "on": "On", "default": true},
				{"kind": "toggle", "key": "bg_motion", "text": "Background", "off": "Still wallpaper", "on": "Moving", "default": true},
				{"kind": "toggle", "key": "reduce_flashing", "text": "Battery alert", "off": "Pulsing", "on": "One gentle swell", "default": false},
				{"kind": "info", "text": "The background fades slowly between still and moving. With animations off, menus and tiles switch instantly."},
			]

# ---------- Scroll bar ----------
func _update_scrollbar(delta: float) -> void:
	if _bar == null:
		return
	var view := _scroll.size.y
	var full := _list.size.y
	var want := 0.0 if full <= view else clampf(_scroll.scroll_vertical / (full - view), 0.0, 1.0)
	if absf(_bar_pos - want) > 0.0005:
		_bar_pos = lerpf(_bar_pos, want, 1.0 - exp(-delta * 18.0))  # glides with the list
		_bar.queue_redraw()

## A rounded track with a handle whose size is how much of the page fits on screen.
## Hidden when the whole page fits.
func _draw_scrollbar() -> void:
	var view := _scroll.size.y
	var full := _list.size.y
	if not _scroll.visible or full <= view + 1.0 or view <= 0.0:
		return
	var h := _bar.size.y
	var w := _bar.size.x
	_bar.draw_style_box(_pill(Themes.ink(0.08)), Rect2(0, 0, w, h))
	var hh := maxf(h * view / full, 48.0)
	_bar.draw_style_box(_pill(Themes.ink(0.6)), Rect2(0, (h - hh) * _bar_pos, w, hh))

func _pill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(Themes.r(4))
	return sb

func _build_rows() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	for i in _tab_labels.size():
		_tab_labels[i].add_theme_color_override("font_color", TEXT if i == _tab else MUTED)
		_tab_labels[i].add_theme_font_size_override("font_size", 30 if i == _tab else 24)
	for d in _definitions():
		match d["kind"]:
			"header":
				var h := _label(d["text"], 24, MUTED)
				h.custom_minimum_size.y = 40
				h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
				_list.add_child(h)
			"info":
				_list.add_child(_info_row(d))
			"pads":
				# One row per connected controller, with its icon. A to put it in charge.
				var list: Array = _home.controllers.list() if _home != null and _home.controllers != null else []
				if list.is_empty():
					_list.add_child(_info_row({"kind": "info", "text": "No controller connected."}))
				for c in list:
					var model := str(c.get("model", c["family"]))
					_list.add_child(_make_row({"kind": "custom", "key": "pad:%d" % int(c["slot"]),
						"text": "P%d   %s" % [int(c["slot"]), str(c.get("name", "Controller"))],
						"icon": Icons.texture("pad_" + model, Icons.svg_pad(model), 40)}))
			_:
				_list.add_child(_make_row(d))
	_sel = clampi(_sel, 0, maxi(_rows.size() - 1, 0))
	_refresh()

func _info_row(d: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	hb.custom_minimum_size.x = 1000
	var left := _label(d["text"], 24 if d.has("value") else 20, MUTED)
	if d.has("value"):
		left.custom_minimum_size.x = 260
		hb.add_child(left)
		var right := _label(d["value"], 24, TEXT)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.custom_minimum_size.x = 600
		hb.add_child(right)
	else:
		left.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.custom_minimum_size.x = 900
		# a wrapping label reports one line of height until it is laid out, which clips long notes
		var lines := int(ceil(float(str(d["text"]).length()) * 11.0 / 900.0))
		left.custom_minimum_size.y = lines * 30 + 8
		hb.add_child(left)
	return hb

## The player number of the controller in charge; the first listed one if the chosen one is gone.
func _boss_slot() -> int:
	var want := TephraGlyphs.in_charge_slot()
	var list: Array = _home.controllers.list() if _home != null and _home.controllers != null else []
	for c in list:
		if int(c["slot"]) == want:
			return want
	return int(list[0]["slot"]) if not list.is_empty() else want

func _make_row(d: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size.y = 76
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(Themes.r(16))
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	p.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	p.add_child(hb)
	if d.has("icon"):
		var ic := TextureRect.new()
		ic.texture = d["icon"]
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(ic)
	var name_l := _label(d["text"], 30, TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(name_l)
	var slider: Control = null
	if _is_slider(d):
		var ds := DetentSlider.new()
		if d["kind"] == "custom" and str(d["key"]) == "volume":
			ds.glide = 7.0  # slower, so muting visibly slides the volume down along with the sound
		slider = ds
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(slider)
	var val_l := _label("", 28, MUTED)
	val_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.custom_minimum_size.x = (180 if slider != null else 260) if d["kind"] != "action" else 0
	hb.add_child(val_l)
	var row: Dictionary = d.duplicate()
	row["panel"] = p
	row["style"] = sb
	row["value_label"] = val_l
	row["slider"] = slider
	_rows.append(row)
	return p

func _refresh() -> void:
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var sb: StyleBoxFlat = r["style"]
		var on := i == _sel
		sb.bg_color = Themes.ink(0.14) if on else Themes.ink(0.06)
		sb.set_border_width_all(3 if on else 0)
		sb.border_color = SELECT
		if on:
			_scroll_to(r["panel"])
		(r["value_label"] as Label).text = _value_text(r)
		if r["slider"] != null:
			var st := _slider_state(r)
			(r["slider"] as DetentSlider).set_state(st["labels"], st["usable"], int(st["index"]), on)
	var accept := "Select"
	if not _rows.is_empty() and _rows[_sel]["kind"] != "action":
		accept = "Change"
	TephraGlyphs.fill(_hints, [["accept", accept], ["dpad", "Choose"], ["l1", "Prev"], ["r1", "Next"], ["back", "Back"]], 26)

# ---------- Sliders ----------
func _is_slider(d: Dictionary) -> bool:
	return bool(d.get("slider", false)) or (d["kind"] == "custom" and str(d["key"]) in ["volume", "refresh", "sdr_nits"])

## The refresh rates drawn on the slider: the usual stops plus any extra the monitor has, in order.
func _rate_stops() -> Array:
	var stops: Array = RATE_STOPS.duplicate()
	for hz in _rates_now():
		if not stops.has(hz):
			stops.append(hz)
	stops.sort()
	return stops

## What a slider row shows: {labels, usable, index}.
func _slider_state(r: Dictionary) -> Dictionary:
	var labels: Array = []
	var usable: Array = []
	var index := 0
	var key := str(r["key"])
	if key == "refresh":
		var avail := _rates_now()
		for hz in _rate_stops():
			labels.append("%d" % hz)
			usable.append(avail.has(hz))
			if hz == _rate_hz:
				index = labels.size() - 1
	elif key == "volume":
		for i in 21:
			labels.append("0" if i == 0 else ("100" if i == 20 else ""))
			usable.append(true)
		# Muted: the handle slides down to 0 with the fade, and back to the old level on unmute.
		index = 0 if _muted else clampi(roundi(maxi(_vol, 0) / 5.0), 0, 20)
	elif key == "sdr_nits":
		var cur := DisplayCtl.sdr_brightness()
		var best := 0
		for i in NITS_STOPS.size():
			labels.append("%d" % NITS_STOPS[i])
			usable.append(true)
			if absi(NITS_STOPS[i] - cur) < absi(NITS_STOPS[best] - cur):
				best = i
		index = best
	else:
		for nm in r["names"]:
			labels.append(str(nm))
			usable.append(true)
		index = _choice_index(r)
		if key == "fps_cap" and Visuals.saver():
			for i in usable.size():
				usable[i] = i == index  # locked at 30 while Power saver is on
	return {"labels": labels, "usable": usable, "index": index}

func _value_text(r: Dictionary) -> String:
	if str(r.get("key", "")).begins_with("theme:"):
		return "In use" if str(r["key"]).substr(6) == Themes.id() else ""
	match r["kind"]:
		"toggle":
			return r["on"] if bool(Settings.get_value(r["key"], r["default"])) else r["off"]
		"choice":
			return str(r["names"][_choice_index(r)])
		"custom":
			if str(r["key"]).begins_with("pad:"):
				return "In charge" if str(r["key"]).substr(4).to_int() == _boss_slot() else ""
			match r["key"]:
				"volume":
					return "-" if _vol < 0 else ("Muted" if _muted else "%d%%" % _vol)
				"mute":
					return "Muted" if _muted else "On"
				"sink":
					for s in _sinks:
						if s["name"] == _sink:
							return str(s["desc"])
					return "-"
				"mic":
					return "Muted" if _mic_muted else "On"
				"mic_test":
					if _mic_pid < 0:
						return "Press to test"
					if _mic_muted:
						return "Microphone is muted"
					var n := clampi(roundi(_mic_level * 10.0), 0, 10)
					return "█".repeat(n) + "░".repeat(10 - n)
				"screen":
					var names := DisplayCtl.screen_names()
					var si := clampi(DisplayServer.window_get_current_screen(), 0, maxi(names.size() - 1, 0))
					return str(names[si]) if not names.is_empty() else "-"
				"resolution":
					if _res_list.is_empty():
						return "-"
					var r2: Array = _res_list[_res_i]
					var cur := DisplayCtl.current()
					var t := DisplayCtl.label(r2[0], r2[1])
					return t if (r2[0] == cur["w"] and r2[1] == cur["h"]) else t + "   <- press Accept"
				"refresh":
					if _res_list.is_empty():
						return "-"
					var same := _res_is_current() and _rate_hz == roundi(DisplayCtl.current()["hz"])
					return "%d Hz" % _rate_hz if same else "%d Hz  (Accept)" % _rate_hz
				"hdr":
					return "On" if DisplayCtl.hdr_on() else "Off"
				"wcg":
					return "On" if DisplayCtl.wcg_on() else "Off"
				"sdr_nits":
					return "%d nits" % DisplayCtl.sdr_brightness()
	return ""

static func _same(a, b) -> bool:
	if a is String or b is String:
		return str(a) == str(b)
	return absf(float(a) - float(b)) < 0.001

func _choice_index(r: Dictionary) -> int:
	var cur = Settings.get_value(r["key"], r["default"])
	var vals: Array = r["values"]
	for i in vals.size():
		if _same(vals[i], cur):
			return i
	return 0

# Keeps the selected row on screen when the list is longer than the page.
func _scroll_to(row: Control) -> void:
	await get_tree().process_frame
	# The rows may have been rebuilt (and this one freed) while we waited a frame.
	if not is_instance_valid(row) or not row.is_inside_tree():
		return
	var top := row.position.y
	var bottom := top + row.size.y
	var view := _scroll.size.y
	if top < _scroll.scroll_vertical:
		_scroll.scroll_vertical = maxi(int(top) - 60, 0)
	elif bottom > _scroll.scroll_vertical + view:
		_scroll.scroll_vertical = int(bottom - view) + 20

# ---------- Tabs ----------
func _set_tab(i: int) -> void:
	_tab = posmod(i, TABS.size())
	_sel = 0
	_scroll.scroll_vertical = 0
	match _tab:
		1:
			_read_display()
		3:
			_read_audio()
		0:
			_read_git()
	_build_rows()
	_bar.queue_redraw.call_deferred()  # the new page has a different length
	Haptics.tick()
	Motion.pop(_list, 0.97, 0.2)

# ---------- Display ----------
func _read_display() -> void:
	DisplayCtl.refresh()
	_res_list = DisplayCtl.resolutions()
	var cur := DisplayCtl.current()
	_res_i = 0
	for i in _res_list.size():
		if _res_list[i][0] == cur["w"] and _res_list[i][1] == cur["h"]:
			_res_i = i
	_sync_rate_index()

func _rates_now() -> Array:
	if _res_list.is_empty():
		return []
	return DisplayCtl.rates(_res_list[_res_i][0], _res_list[_res_i][1])

func _res_is_current() -> bool:
	if _res_list.is_empty():
		return true
	var cur := DisplayCtl.current()
	return _res_list[_res_i][0] == cur["w"] and _res_list[_res_i][1] == cur["h"]

func _sync_rate_index() -> void:
	_rate_hz = roundi(DisplayCtl.current()["hz"])

## After a different resolution is picked, keep the chosen rate if it exists there, else the closest.
func _fit_rate() -> void:
	var rates := _rates_now()
	if rates.is_empty() or rates.has(_rate_hz):
		return
	var best: int = rates[0]
	for hz in rates:
		if absi(int(hz) - _rate_hz) < absi(best - _rate_hz):
			best = int(hz)
	_rate_hz = best

## Applies the chosen resolution and refresh rate, then asks you to keep them. If you don't
## answer in 12 seconds the old mode comes back (so a mode the screen can't show never
## leaves you with a black screen).
# ---------- Fade to black around changes that blank the screen ----------
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
## After a resolution / refresh / HDR change the swap chain (the queue of finished frames waiting for the
## screen) is still timed for the OLD mode, which is what leaves the menus at 40-50 fps. Switching VSync
## off and back on makes Godot build a fresh one that is timed for the new refresh rate.
func _reset_pacing() -> void:
	var mode := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(mode)

var _busy := false  # true while the screen is fading / changing: input is ignored

## Fades the screen to black, runs `action` (which may blank the screen for a moment while the
## display changes mode), waits a beat, and fades back in. Without this the screen would
## just cut to black and back.
func _blackout(action: Callable) -> void:
	if _busy:
		return
	_busy = true
	if _fade_layer == null:
		_fade_layer = CanvasLayer.new()
		_fade_layer.layer = 120  # above everything
		add_child(_fade_layer)
		_fade_rect = ColorRect.new()
		_fade_rect.color = Color.BLACK
		_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_layer.add_child(_fade_rect)
	_fade_layer.visible = true
	_fade_rect.modulate.a = 0.0
	var t_in := create_tween()
	t_in.tween_property(_fade_rect, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t_in.finished
	# Let one fully black frame reach the screen before the display changes.
	await get_tree().process_frame
	await get_tree().process_frame
	action.call()
	# Stay black while the display settles. The window resizes and re-lays everything out, which
	# makes the first frames after a mode change stutter; a fade that starts during that stutter
	# looks like a jump. So wait until the window size has stopped changing for a few frames,
	# then wait a few more for the layout to finish, and only then fade in.
	# The monitor itself needs a moment to lock onto the new signal (often 1 to 3 seconds on which it
	# shows nothing at all). The fade back in must start AFTER that, or it plays unseen on a black
	# screen and the picture just appears. So hold black for a good while first.
	await get_tree().create_timer(3.0).timeout
	# After HDR or a mode change KWin can leave Tephra's window at the old size or offset, which shows as the
	# picture "folding" over and starting again from the other side. Leaving fullscreen and entering it again
	# (still black here) makes the window and its picture match the screen again.
	var scr := DisplayServer.window_get_current_screen()
	if DisplayServer.window_get_size() != DisplayServer.screen_get_size(scr) or DisplayServer.window_get_position() != DisplayServer.screen_get_position(scr):
		DisplayCtl.move_to_screen(scr)
	else:
		var mode := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		await get_tree().process_frame
		DisplayServer.window_set_mode(mode if mode != DisplayServer.WINDOW_MODE_WINDOWED else DisplayServer.WINDOW_MODE_FULLSCREEN)
	await get_tree().create_timer(0.5).timeout
	var last_size := DisplayServer.window_get_size()
	var stable := 0
	var waited := 0
	while stable < 10 and waited < 180:  # (at most a few seconds)
		await get_tree().process_frame
		waited += 1
		var now := DisplayServer.window_get_size()
		if now == last_size:
			stable += 1
		else:
			stable = 0
			last_size = now
	await _reset_pacing()
	await get_tree().create_timer(0.4).timeout
	var t_out := create_tween()
	t_out.tween_property(_fade_rect, "modulate:a", 0.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t_out.finished
	_fade_layer.visible = false
	_busy = false

func _apply_mode() -> void:
	if _res_list.is_empty():
		return
	var rates := _rates_now()
	if rates.is_empty():
		return
	_prev_mode = DisplayCtl.current()
	var r2: Array = _res_list[_res_i]
	var hz: int = _rate_hz
	if r2[0] == _prev_mode["w"] and r2[1] == _prev_mode["h"] and hz == roundi(_prev_mode["hz"]):
		return
	_blackout(func():
		if DisplayCtl.set_mode_safely(r2[0], r2[1], hz):
			_confirm = CONFIRM_SECONDS
			_show_confirm())

func _show_confirm() -> void:
	TephraGlyphs.fill(_hints, [["accept", "Keep these settings"], ["back", "Go back"]], 26)
	_note.visible = true

func _end_confirm(keep: bool) -> void:
	_confirm = 0.0
	_note.visible = false
	if not keep and not _prev_mode.is_empty():
		var back: Dictionary = _prev_mode
		_blackout(func():
			DisplayCtl.set_mode_safely(back["w"], back["h"], roundi(back["hz"]))
			_read_display()
			_build_rows())
		return
	_read_display()
	_build_rows()

# ---------- Audio (read and changed through wpctl / pactl, like the control center) ----------
func _cmd(path: String, args: PackedStringArray) -> String:
	var out := []
	if OS.execute(path, args, out) != 0 or out.is_empty():
		return ""
	return str(out[0])

func _read_audio() -> void:
	var vol := _cmd("wpctl", ["get-volume", "@DEFAULT_AUDIO_SINK@"])  # "Volume: 0.45 [MUTED]"
	if vol.begins_with("Volume:"):
		_vol = roundi(vol.split(" ", false)[1].to_float() * 100.0)
		_muted = vol.contains("MUTED")
	else:
		_vol = -1
	_sinks.clear()
	var sink_json := _cmd("pactl", ["-f", "json", "list", "sinks"])
	var sinks = JSON.parse_string(sink_json) if sink_json != "" else null
	if sinks is Array:
		for k in sinks:
			if k is Dictionary:
				_sinks.append({"name": str(k.get("name", "")), "desc": str(k.get("description", k.get("name", "")))})
	_sink = _cmd("pactl", ["get-default-sink"]).strip_edges()
	var src := _cmd("pactl", ["get-default-source"]).strip_edges()
	_mic_present = src != "" and not src.ends_with(".monitor")
	_mic_muted = _cmd("pactl", ["get-source-mute", "@DEFAULT_SOURCE@"]).contains("yes")

# ---------- Updates (the installer keeps the project in git) ----------
func _read_git() -> void:
	var dir := ProjectSettings.globalize_path("res://")
	_git = {
		"version": _cmd("git", ["-C", dir, "describe", "--tags", "--always"]).strip_edges(),
		"message": _cmd("git", ["-C", dir, "log", "-1", "--format=%s"]).strip_edges(),
		"date": _cmd("git", ["-C", dir, "log", "-1", "--format=%cd", "--date=format:%b %d, %Y"]).strip_edges()}
	for k in _git:
		if _git[k] == "":
			_git[k] = "Unknown"

# ---------- Log viewer ----------
func _show_log(on: bool) -> void:
	_log_mode = on
	_log_card.visible = on
	_scroll.visible = not on
	if on:
		var p := OS.get_user_data_dir() + "/logs/godot.log"
		if FileAccess.file_exists(p):
			_log_lines = FileAccess.get_file_as_string(p).split("\n")
		else:
			_log_lines = PackedStringArray(["No log file found at " + p])
		_log_off = maxi(_log_lines.size() - _log_page(), 0)
		_draw_log()
		TephraGlyphs.fill(_hints, [["dpad_v", "Scroll"], ["back", "Back"]], 26)
	elif not _rows.is_empty():
		_refresh()

func _log_page() -> int:
	var line := float(_log.get_line_height()) + float(_log.get_theme_constant("line_spacing"))
	return maxi(int((_log.size.y if _log.size.y > 100 else 600) / maxf(line, 1.0)) - 1, 10)

func _draw_log() -> void:
	var end := mini(_log_off + _log_page(), _log_lines.size())
	_log.text = "\n".join(_log_lines.slice(_log_off, end))

# ---------- Open / close ----------
func open(clock_rect := Rect2(), tab := 0) -> void:
	if is_open:
		return
	is_open = true
	if clock_rect.size != Vector2.ZERO:
		_clock.position = clock_rect.position
		_clock.size = clock_rect.size
	_show_log(false)
	_tab = clampi(tab, 0, TABS.size() - 1)
	_sel = 0
	_scroll.scroll_vertical = 0
	_confirm = 0.0
	_note.visible = false
	_read_display()
	if _tab == 3:
		_read_audio()
	elif _tab == 0:
		_read_git()
	_build_rows()
	_root.visible = true
	_root.modulate.a = 0.0
	Motion.fade_to(_root, 1.0, 0.25)
	Motion.pop(_list, 0.97, 0.25)

## Channels theme's Info button: what Settings > System says about Tephra and this PC, on its own.
func open_info(clock_rect := Rect2()) -> void:
	_info_only = true
	_title.text = "System info"
	_strip.visible = false
	open(clock_rect, 0)
	TephraGlyphs.fill(_hints, [["dpad_v", "Scroll"], ["back", "Back"]], 26)

## Opens straight into the log (kept for tools and the ui test); Back closes the screen.
func open_log(clock_rect := Rect2()) -> void:
	_log_only = true
	_title.text = "Log"
	_strip.visible = false
	open(clock_rect)
	_show_log(true)
	await get_tree().process_frame  # the card has its size now: fill it to the bottom
	if _log_mode:
		_log_off = maxi(_log_lines.size() - _log_page(), 0)
		_draw_log()

func close() -> void:
	_mic_test_stop()
	if not is_open:
		return
	is_open = false
	if _log_only:
		_log_only = false
		_title.text = "Settings"
		_strip.visible = true
	if _info_only:
		_info_only = false
		_title.text = "Settings"
		_strip.visible = true
	_home._focus_profile(false)  # back to the games, not the top bar
	if _confirm > 0.0:
		_end_confirm(true)
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, Motion.dur(0.2))
	await t.finished
	if not is_open:
		_root.visible = false

# ---------- Microphone test ----------
# Records from the default microphone into a pipe (nothing is saved or played) and shows how loud it is, live.
var _mic_pid := -1
var _mic_level := 0.0
var _mic_thread: Thread

func _mic_test_toggle() -> void:
	if _mic_pid >= 0:
		_mic_test_stop()
		return
	var pipe := OS.execute_with_pipe("parec", ["--raw", "--format=s16le", "--rate=8000", "--channels=1", "--latency-msec=40"])
	if pipe.is_empty():
		_home.dev_toast("Microphone test needs parec (pipewire-pulse or pulseaudio-utils)")
		return
	_mic_pid = int(pipe["pid"])
	_mic_level = 0.0
	var io: FileAccess = pipe["stdio"]
	_mic_thread = Thread.new()
	_mic_thread.start(func() -> void:
		while io.is_open():
			var buf := io.get_buffer(640)
			if buf.is_empty():
				break
			var peak := 0
			for i in range(0, buf.size() - 1, 2):
				peak = maxi(peak, absi(buf.decode_s16(i)))
			_mic_level = lerpf(_mic_level, clampf(float(peak) / 12000.0, 0.0, 1.0), 0.6))

func _exit_tree() -> void:
	_mic_test_stop()

func _mic_test_stop() -> void:
	if _mic_pid >= 0:
		OS.kill(_mic_pid)
		_mic_pid = -1
	if _mic_thread != null:
		_mic_thread.wait_to_finish()
		_mic_thread = null
	_mic_level = 0.0

func _process(delta: float) -> void:
	if _mic_pid >= 0:
		if not is_open or _tab != 3:
			_mic_test_stop()
		else:
			for r in _rows:
				if r.get("key", "") == "mic_test":
					(r["value_label"] as Label).text = _value_text(r)
	if is_open:
		_update_scrollbar(delta)
		_clock.text = _home.clock_label.text
		if _confirm > 0.0:
			_confirm -= delta
			_note.text = "Keep this display setting?  Going back in %d..." % ceili(maxf(_confirm, 0.0))
			if _confirm <= 0.0:
				_end_confirm(false)

## Up/down picks a row; left/right changes it.
func move(dir: Vector2i) -> void:
	if not is_open or _busy:
		return
	if _log_mode:
		_log_off = clampi(_log_off + dir.y * 6, 0, maxi(_log_lines.size() - _log_page(), 0))
		_draw_log()
		return
	if _info_only:
		_scroll.scroll_vertical = maxi(_scroll.scroll_vertical + dir.y * 140, 0)  # nothing to pick: Up / Down scroll
		return
	if _rows.is_empty():
		return
	if _confirm > 0.0:
		return
	if dir.y != 0:
		var before := _sel
		_sel = posmod(_sel + dir.y, _rows.size())
		if _sel != before:
			Haptics.tick()
		_refresh()
	elif _rows[_sel]["kind"] != "action":
		_change(dir.x)

# ---------- Changing a row ----------
func _change(step: int) -> void:
	var r: Dictionary = _rows[_sel]
	match r["kind"]:
		"toggle":
			Settings.set_value(r["key"], not bool(Settings.get_value(r["key"], r["default"])))
			_after_change(str(r["key"]))
		"choice":
			if str(r["key"]) == "fps_cap" and Visuals.saver():
				_home.dev_toast("Power saver keeps the frame limit at 30")
				return
			var vals: Array = r["values"]
			var ci := _choice_index(r) + step
			ci = clampi(ci, 0, vals.size() - 1) if r.get("slider") != null else posmod(ci, vals.size())  # sliders stop at the ends
			Settings.set_value(r["key"], vals[ci])
			_after_change(str(r["key"]))
		"custom":
			if str(r["key"]).begins_with("pad:"):
				Settings.set_value("pad_priority", str(r["key"]).substr(4))
				TephraGlyphs.detect()
				_home._refresh_all_hints()
				_refresh()
				return
			match r["key"]:
				"volume":
					if _vol >= 0:
						_vol = clampi(snappedi(_vol, 5) + 5 * step, 0, 100)
						if _muted:
							_muted = false
							OS.execute("pkill", ["-f", "tephra_audio_fade"], [])  # a mute fade still running must not win
							OS.create_process("wpctl", ["set-mute", "@DEFAULT_AUDIO_SINK@", "0"])
						OS.create_process("wpctl", ["set-volume", "@DEFAULT_AUDIO_SINK@", "%.2f" % (_vol / 100.0)])
				"mute":
					_muted = not _muted
					AudioFade.set_muted(maxf(float(_vol), 0.0) / 100.0 if _vol >= 0 else 0.5, _muted)
				"sink":
					var idx := 0
					for i in _sinks.size():
						if _sinks[i]["name"] == _sink:
							idx = i
					_sink = str(_sinks[posmod(idx + step, _sinks.size())]["name"])
					OS.create_process("pactl", ["set-default-sink", _sink])
				"mic_test":
					_mic_test_toggle()
				"mic":
					_mic_muted = not _mic_muted
					OS.create_process("pactl", ["set-source-mute", "@DEFAULT_SOURCE@", "1" if _mic_muted else "0"])
				"screen":
					var count := DisplayServer.get_screen_count()
					DisplayCtl.move_to_screen(posmod(DisplayServer.window_get_current_screen() + step, count))
					_read_display()
				"resolution":
					if not _res_list.is_empty():
						_res_i = posmod(_res_i + step, _res_list.size())
						_fit_rate()
				"refresh":
					var stops := _rate_stops()
					var avail := _rates_now()
					var i := stops.find(_rate_hz)
					var j := i
					while true:
						j += step
						if j < 0 or j >= stops.size():
							j = i
							break
						if avail.has(stops[j]):
							break
					if j >= 0 and j < stops.size():
						_rate_hz = int(stops[j])
				"hdr":
					_blackout(func():
						DisplayCtl.set_hdr(not DisplayCtl.hdr_on())
						_build_rows())
					return
				"wcg":
					_blackout(func():
						DisplayCtl.set_wcg(not DisplayCtl.wcg_on())
						_build_rows())
					return
				"sdr_nits":
					var cur_nits := DisplayCtl.sdr_brightness()
					var ni := 0
					for k in NITS_STOPS.size():
						if absi(NITS_STOPS[k] - cur_nits) < absi(NITS_STOPS[ni] - cur_nits):
							ni = k
					DisplayCtl.set_sdr_brightness(NITS_STOPS[clampi(ni + step, 0, NITS_STOPS.size() - 1)])
	if str(r["key"]) in ["hdr", "wcg", "sdr_nits", "screen"]:
		_build_rows()
		return
	_refresh()

# Settings that need something done the moment they change.
func _after_change(key: String) -> void:
	match key:
		"temp_c":
			_home.weather.fetch(true)
		"fps_cap", "vsync", "vsync_smooth":
			apply_display()
		"capture_links":
			_home._links_changed()
		"touchpad_layout":
			_home._pads_refresh()  # done now if Steam is closed, otherwise right before it next starts
		"gpu_mode":
			# Power saver and the frame limit move together: saver locks 30 (remembering the old
			# limit), and leaving saver puts the old limit back.
			if Visuals.saver():
				if not bool(Settings.get_value("saver_on", false)):
					Settings.set_value("fps_cap_before", int(Settings.get_value("fps_cap", 0)))
					Settings.set_value("saver_on", true)
				Settings.set_value("fps_cap", 30)
			elif bool(Settings.get_value("saver_on", false)):
				Settings.set_value("fps_cap", int(Settings.get_value("fps_cap_before", 0)))
				Settings.set_value("saver_on", false)
			apply_display()
			_refresh()
		"glyph_override":
			TephraGlyphs.detect()
			_home._refresh_all_hints()
		"ui_scale":
			_home.apply_ui_scale()
		"show_hints":
			_home._refresh_all_hints()
		"pad_priority":
			TephraGlyphs.detect()
			_home._refresh_all_hints()
		"deadzone":
			TephraGlyphs.apply_deadzone()
		"vibration":
			Haptics.preview()
		"lightbar_mode":
			_home.alert.apply_mode_now()
		"guide_swap":
			_home._refresh_all_hints()

func _activate() -> void:
	if _rows.is_empty():
		return
	var r: Dictionary = _rows[_sel]
	if r["kind"] != "action":
		if str(r["key"]) in ["resolution", "refresh"]:
			_apply_mode()
			return
		_change(1)
		return
	match r["key"]:
		"hdr_calibrate":
			_home.hdr_calibration.open()
		"pad_test":
			_home.controller_test.open()  # over Settings, which stays open: closing the test comes back to this row
		"vib_try":
			Haptics.pulse(1.0, 1.0, 0.6)
		"rescan":
			_home.refresh_games()
		"view_log":
			_show_log(true)
			await get_tree().process_frame  # the card has its size now: fill it to the bottom
			if _log_mode:
				_log_off = maxi(_log_lines.size() - _log_page(), 0)
				_draw_log()
		"redo_setup":
			close()
			_home.setup_screen.open(0, true)
		"clear_art":
			_home.dev_toast("Cleared %d cover images. Restart Tephra to reload them." % _clear_dir("user://art"))
		"clear_ach":
			_home.dev_toast("Cleared %d achievement files" % _clear_dir("user://ach"))
		"family_add":
			_home.keyboard.open("Steam profile link or ID (7656...)", "", false, func(text: String):
				var id := preload("res://extra_games.gd").parse_steam_id(text)
				if id == "":
					_home.dev_toast("No Steam ID found. Use the long number starting with 7656 (steamcommunity.com/profiles/7656...)")
					return
				preload("res://extra_games.gd").add_family_id(id)
				_home.library.reload_family()
				_home.dev_toast("Family member added. Their games must be Public in Steam > Game details.")
				_build_rows())
		"family_clear":
			Settings.set_value("family_ids", [])
			_home.library.reload_family()
			_build_rows()
		"close_steam":
			OS.create_process("steam", ["-shutdown"])
		"ps2_scan":
			_home.ps2_sync(true)
		"ra_user":
			_home.keyboard.open("RetroAchievements user name", str(Settings.get_value("ra_user", "")), false, func(text: String):
				Settings.set_value("ra_user", text.strip_edges())
				_build_rows())
		"ra_key":
			_home.keyboard.open("RetroAchievements web API key", "", true, func(text: String):
				Settings.set_value("ra_key", text.strip_edges())
				_build_rows())
		"ra_check":
			var why: String = await _home.retro.verify(str(Settings.get_value("ra_user", "")), str(Settings.get_value("ra_key", "")))
			if why != "":
				_home.dev_toast(why)
			else:
				_home.notify("RetroAchievements signed in", "info")
				_home.ps2_sync(false)
		"ra_out":
			Settings.set_value("ra_user", "")
			Settings.set_value("ra_key", "")
			_build_rows()
		"suspend":
			close()
			OS.create_process("systemctl", ["suspend"])
		"reboot":
			_home.power_command("reboot")
		"poweroff":
			_home.power_command("poweroff")
		"restart":
			_home.restart_tephra()
		_ when str(r["key"]).begins_with("theme:"):
			_home.apply_theme(str(r["key"]).substr(6))
		"close":
			_home.close_tephra()

func _clear_dir(path: String) -> int:
	var n := 0
	for f in DirAccess.get_files_at(path):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(path + "/" + f)) == OK:
			n += 1
	return n

func _is_tab_step(event: InputEvent, left: bool) -> bool:
	if event is InputEventJoypadButton and event.pressed:
		return event.button_index == (JOY_BUTTON_LEFT_SHOULDER if left else JOY_BUTTON_RIGHT_SHOULDER)
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed:
		return event.keycode == (KEY_Q if left else KEY_E)
	return false

## Returns true when the settings screen used the event.
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if _busy:
		return true  # the screen is changing: swallow input until it has faded back in
	if _confirm > 0.0:
		if event.is_action_pressed("ui_accept"):
			_end_confirm(true)
		elif event.is_action_pressed("ui_cancel"):
			_end_confirm(false)
		return true
	if event.is_action_pressed("ui_cancel"):
		if _log_mode and not _log_only:
			_show_log(false)
		else:
			close()
	elif _log_mode:
		pass
	elif _info_only:
		pass  # no tabs and nothing to change on the info page
	elif _is_tab_step(event, true):
		_set_tab(_tab - 1)
	elif _is_tab_step(event, false):
		_set_tab(_tab + 1)
	elif event.is_action_pressed("ui_accept"):
		_activate()
	return true
