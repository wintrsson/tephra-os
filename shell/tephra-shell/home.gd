extends Control
## Tephra home screen (v0.3).
## Row: [Home] [games, most recently played first] [Library].
## Top left: shard, clock, Wi-Fi. Top right: your Steam name and picture.
## Press Down for game details and achievements (game_details.gd), which peek
## up from the bottom of the screen.

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const DisplayCtl = preload("res://display_ctl.gd")
const Visuals = preload("res://visuals.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Icons = preload("res://icons.gd")
const SteamAccount = preload("res://steam_account.gd")
const Achievements = preload("res://achievements.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const Rounded = preload("res://rounded.gd")
const Perf = preload("res://perf.gd")
const InGameHud = preload("res://ingame_hud.gd")
const Sessions = preload("res://sessions.gd")
const TephraBg = preload("res://tephra_bg.gd")
const Ega16 = preload("res://ega16.gd")
const FrameGraph = preload("res://frame_graph.gd")
const SteamQuiet = preload("res://steam_quiet.gd")
const TephraLinks = preload("res://tephra_links.gd")

var SELECT: Color = Themes.c("select")  # soft white outline for the selected tile
var BG: Color = Themes.c("bg")
var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
const TILE := Vector2(200, 300)
var TILE_BG: Color = Themes.c("tile")
var HOME_TILE_BG: Color = Themes.c("home_tile")
const CDN := "https://cdn.cloudflare.steamstatic.com/steam/apps/%s/%s.%s"
const StoreLookup = preload("res://store_lookup.gd")  # its static helpers; the instance is `store`
const SUMMARY_URL := "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=%s&steamids=%s"
const LOGO_MAX := Vector2(720, 170)  # largest size a game logo is shown at
const SKIP := ["Proton", "Steam Linux Runtime", "Steamworks Common"]
const ExtraGames = preload("res://extra_games.gd")
const Ps2Games = preload("res://ps2_games.gd")
const GameRes = preload("res://game_res.gd")
const GameNames = preload("res://game_names.gd")
const CoverTrim = preload("res://cover_trim.gd")
const LONG_PRESS_MS := 300  # hold PS this long to go home (a tap, which opens the control center, is shorter than this)
const AVATAR := 56
const PEEK := 56         # how much of the details section shows under the row
const DETAIL_TOP := 110  # where the details section sits once scrolled to
const CHANNELS_PAGE_DROP := 74.0  # the Channels Home page sits this much lower (below the round buttons)

var steam_dir := OS.get_environment("HOME") + "/.local/share/Steam"
var games: Array = []
var selected := 0
var playtimes := {}  # appid -> minutes played, from Steam

# Screen parts
var hero: TextureRect
var hero_back: TextureRect  # dimmed, stretched copy of the hero that fills the screen behind it
var bg_anim: Control          # Tephra's animated background (Home and Library tiles)
var title_label: Label
var logo_rect: TextureRect
var row: HBoxContainer
var scroll: ScrollContainer
var perf
var shade_a: TextureRect
var shade_b: TextureRect
var title_area: Control
var shadows: Array = []
var album  # album.gd: the screenshot album
var mods  # mods.gd: the mod manager
var shines: Array = []
var tile_game: Array = []   # per tile: index into games, or -1 (Home, Library)
var tiles: Array = []
var frames: Array = []
var clock_label: Label
var wifi_icon: TextureRect
var shard_icon: TextureRect
var profile_name: Label
var avatar_rect: TextureRect
var hints: HBoxContainer
var page: Control            # everything that scrolls up when you press Down
var details                  # game_details.gd
var channels                 # channels.gd or ps2.gd: the alternative Home of the Channels / PS2 themes (null in the others)
var detail_dim: ColorRect    # darkens the background art while details are open
var in_details := false
var _page_tween: Tween
var _scroll_tween: Tween

# Other parts of Tephra
var cc            # control center (control_center.gd)
var library       # Library app (library.gd)
var controllers   # controllers.gd
var nav           # nav.gd: D-pad, stick and keyboard steps
var profile_screen  # profile.gd
var setup_screen    # setup.gd: the first-boot setup
var phone           # phone_link.gd: the web server a phone types and saves captures through
var phone_screen    # phone_screen.gd: its QR code
var settings_screen  # settings_screen.gd
var weather  # weather.gd
var retro    # retro_ach.gd (RetroAchievements)
const TOP_ITEMS := ["wifi", "bt", "pad", "battery", "gear", "profile"]  # left to right in the top bar
var top_index := 5  # which top-bar item has the focus (index into TOP_ITEMS)
var batt_wrap: Control      # the laptop battery icon, left of the settings gear (hidden on a desktop)
var batt_icon: TextureRect
var batt_pct: Label
var _pct_shown := false
var _batt_t := 99.0
var _batt_key := ""
var bt_icon: TextureRect
var top_menu
var keyboard  # keyboard.gd: the on-screen keyboard
const Browser = preload("res://browser.gd")
var browser   # browser.gd: Firefox in kiosk mode, run like a game and driven by the pad
var browser_tabs  # browser_tabs.gd: the browser's tab list (from the Browser menu), shown over a picture of the page
var _tabs_seen := {}  # the tab list as it was when it opened: {"tabs", "current"}
var game_menu  # game_menu.gd: Triangle on a game
var sfx  # sfx.gd: Tephra's own interface sounds and background music
var _music_t := 0.0
var gear_icon: TextureRect
var profile_focus := false  # the profile picture in the top bar is highlighted
var avatar_ring: Panel
var toast         # toast.gd
var alert         # battery_alert.gd: flashes the top-bar controller icon, control center card and lightbar
var pad_icon: TextureRect   # top bar: your controller, coloured by its battery (green, orange, red)
var pad_wrap: Control       # holds the icon; this is what pulses when a battery alert fires
var strip: Panel            # the band behind the top bar
var strip_style: StyleBoxFlat
var top_shade: TextureRect     # darkness rising from the bottom while the top bar has the focus
var top_arrow: Control         # a small bobbing arrow under the top bar: "Down goes back to the games"
var controller_test         # controller_test.gd
var scene_test              # scene_test.gd: the developer 3D tests
var color_picker            # color_picker.gd
var hdr_calibration         # hdr_calibration.gd
var _idle_s := 0.0          # seconds since the last button press
var idle_cover: ColorRect   # dims the screen when idle
var rest_bg: Control        # the theme's moving background alone, over everything while resting (not for Channels)

# Launching
var launching := false
var launch_overlay: ColorRect
var launch_art: TextureRect
var launch_sharp: TextureRect  # the sharp picture of the game, over the blurred one: leaving a menu unblurs into it
var launch_label: Label
var launch_logo: TextureRect
var overlay            # overlay.gd: pause key, KWin focus, screenshot, close game
var _in_overlay := false       # a menu (control center or Home) is showing on top of a running game
var _overlay_mode := ""        # "cc" or "home"
var _overlay_busy := false     # opening or closing right now
var _overlay_live := false     # the menu is the see-through "live" kind (the game still shows behind it)
var _quit_flow := false
var _placing_perf := false     # the performance numbers are being moved with the D-pad
var _place_zone := "top-left"   # the spot being previewed
var _place_hint: PanelContainer
var _game_id := ""
var _game_title := ""
var _foreign_acc := 0.0
var _foreign_game := false     # a game is running that Tephra didn't start or lost track of (checked every 3 s)
var _game_started := false     # the game's process exists (set in _launch)
var launch_hint: HBoxContainer   # "B Cancel" at the bottom of the launch screen
var _launch_cancellable := false  # true from pressing play until the game's window process exists
var _launch_cancel := false

var input_locked := true  # no input until the boot intro has finished

# PS / Guide button
var guide_down_ms := -1  # when PS was pressed, -1 = not held
var capture_down_ms := -1  # when the Create / capture button was pressed, -1 = not held
var capture_long_fired := false
var guide_long_fired := false

# Wi-Fi (read in the background)
var _wifi_task := -1
var _wifi_reading := false

# Steam never pops up or makes a sound over Tephra (see steam_quiet.gd): the KDE settings are
# written once at start-up, and Steam's own sound streams are muted every few seconds.
var _quiet_task := -1

## Web links that games open on their own (a Discord invite, "visit our website") go to Tephra, not the desktop browser.
## Settings > System > "Links from games" switches this off. See tephra_links.gd and tephra-link.sh.
var _links_task := -1
var _links_acc := 0.0
var game_links: Array = []  # addresses a game asked for, waiting in the control center's Browser card

func _start_links() -> void:
	var on := bool(Settings.get_value("capture_links", true))
	if _links_task != -1:
		WorkerThreadPool.wait_for_task_completion(_links_task)  # flipping the switch twice must not run two at once (the older could win)
	_links_task = WorkerThreadPool.add_task(func() -> void: TephraLinks.apply(on))

func _links_changed() -> void:
	_start_links()  # the Settings switch

func _links_path() -> String:
	var run := OS.get_environment("XDG_RUNTIME_DIR")
	return (run if run != "" else "/tmp") + "/tephra-links"

func _links_poll(delta: float) -> void:
	_links_acc += delta
	if _links_acc < 1.0:
		return
	_links_acc = 0.0
	var path := _links_path()
	if not FileAccess.file_exists(path):
		return
	# Taken away before it is read: a link tephra-link.sh adds in between goes to a new file, not lost with this one.
	var taken := path + ".reading"
	if DirAccess.rename_absolute(path, taken) != OK:
		return
	var txt := FileAccess.get_file_as_string(taken)
	DirAccess.remove_absolute(taken)
	for line in txt.split("\n", false):
		var url := line.strip_edges()
		if url.begins_with("http://") or url.begins_with("https://"):
			_link_arrived(url)

func _link_arrived(url: String) -> void:
	var host := url.get_slice("://", 1).get_slice("/", 0)
	overlay.log_line("link: %s asked for %s" % [_game_title if launching else "something", url])
	if launching:
		# Nothing opens next to a game: the address waits, and the control center's Browser card can open it afterwards.
		if not game_links.has(url):
			game_links.append(url)
			while game_links.size() > 5:
				game_links.pop_front()
		notify("%s tried to open %s. It is kept for later: control center > Browser." % [_game_title, host])
	elif browser.firefox() == "":
		notify("A link to %s was kept out of the desktop browser. Tephra's browser needs Firefox." % host)
	else:
		_browser_action("open", url)  # nothing is running: Tephra's own browser opens it

func _start_steam_quiet() -> void:
	_quiet_task = WorkerThreadPool.add_task(SteamQuiet.apply)
	var t := Timer.new()
	t.wait_time = 4.0
	t.autostart = true
	add_child(t)
	t.timeout.connect(func():
		if _quiet_task == -1 or WorkerThreadPool.is_task_completed(_quiet_task):
			if _quiet_task != -1:
				WorkerThreadPool.wait_for_task_completion(_quiet_task)
			_quiet_task = WorkerThreadPool.add_task(SteamQuiet.mute_steam_sounds))

func _exit_tree() -> void:
	_vol_snap_stop()
	_tp_stop()
	if _quiet_task != -1:
		WorkerThreadPool.wait_for_task_completion(_quiet_task)
	if _links_task != -1:
		WorkerThreadPool.wait_for_task_completion(_links_task)
	# Changing the theme rebuilds Home. Any worker still running would reach into the old, freed Home
	# when it finishes and crash Tephra, so Home waits for every one of them before it goes.
	for id in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(id)
	_pending.clear()

## Background work that Home must wait for before it is freed (see _exit_tree).
var _pending := {}

func _work(c: Callable) -> int:
	var id := WorkerThreadPool.add_task(c)
	_pending[id] = true
	return id

## Called on the main thread when a worker's result has arrived.
func _work_done(id: int) -> void:
	if _pending.erase(id):
		WorkerThreadPool.wait_for_task_completion(id)

## The installed Tephra version, small in the bottom left corner, on every screen.
## Read once from git (the installer keeps the project in git and tags each update).
## Channels and PS2 themes: the row, the big game picture and the details below are hidden, and the paged
## grid of channels takes their place under the top bar (see channels.gd).
func _make_channels() -> void:
	if not Themes.layout() in ["channels", "ps2", "xmb", "neon", "planet", "pcb"]:
		return
	for c in [hero, hero_back, shade_a, shade_b, title_area, scroll, hints, details]:
		(c as CanvasItem).visible = false
	if Themes.layout() == "channels":
		gear_icon.get_parent().visible = false  # Settings is a round button at the bottom, so the top one goes
	elif not Themes.layout() in ["planet", "pcb"]:  # (Planet and Circuit keep the top bar)
		# PS2: Wi-Fi, Controllers and Settings are words in the middle of the screen, so the top icons go
		for c in [wifi_icon, bt_icon, pad_wrap, gear_icon.get_parent()]:
			(c as CanvasItem).visible = false
	channels = {"channels": preload("res://channels.gd"), "ps2": preload("res://ps2.gd"), "xmb": preload("res://xmb.gd"), "neon": preload("res://neon.gd"), "planet": preload("res://planet.gd"), "pcb": preload("res://board.gd")}[Themes.layout()].new()
	channels.home = self
	page.add_child(channels)
	page.move_child(channels, strip.get_index() + 1)  # under the top bar
	if Themes.layout() == "channels":
		# More bar below the bottom of the screen: when the Home page slides the bar up (and back down), what
		# shows under it is the bar's own colour, never the page's top edge or a gap.
		var skirt := ColorRect.new()
		skirt.color = Color(0.84, 0.86, 0.89)
		skirt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(skirt)
		page.move_child(skirt, channels.get_index() + 1)
		skirt.anchor_left = 0.0
		skirt.anchor_right = 1.0
		skirt.anchor_top = 1.0
		skirt.anchor_bottom = 1.0
		skirt.offset_top = 0.0
		skirt.offset_bottom = 1400.0

## KDE's taskbar is hidden while Tephra runs (set to hide itself, so nothing about it is lost) and comes back when
## Tephra is closed, for working on the desktop. Each panel remembers how it was set before ("tephraWas"), so
## a panel that was already auto-hiding stays that way. `tephra panel` in a terminal brings it back by hand.
const PANEL_HIDE_JS := "panels().forEach(function (p) { if (p.readConfig('tephraWas', '') == '') { p.writeConfig('tephraWas', p.hiding || 'none'); } p.hiding = 'autohide'; });"
const PANEL_SHOW_JS := "panels().forEach(function (p) { var w = p.readConfig('tephraWas', ''); p.hiding = (w == '' ? 'none' : w); p.writeConfig('tephraWas', ''); });"

static func _plasma_script(js: String, wait := false) -> void:
	var args := ["--user", "call", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript", "s", js]
	if wait:
		OS.execute("busctl", args, [])
	else:
		OS.create_process("busctl", args)

func _taskbar_shortcut() -> void:
	_plasma_script(PANEL_HIDE_JS)

## Settings > Accessibility > Interface size: everything Tephra draws is scaled by this.
func apply_ui_scale() -> void:
	get_window().content_scale_factor = clampf(float(Settings.get_value("ui_scale", 100)) / 100.0, 0.9, 1.15)

static var _version_text := ""

func _make_version_label() -> void:
	if _version_text == "":
		var out: Array = []
		OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "describe", "--tags", "--always"], out)
		_version_text = (str(out[0]) if not out.is_empty() else "").strip_edges()
	var v := _version_text
	if v == "":
		return
	var seen := str(Settings.get_value("last_version", ""))
	if seen != v:
		Settings.set_value("last_version", v)
		if seen != "":
			get_tree().create_timer(6.0).timeout.connect(func() -> void: notify("Tephra updated to %s" % v, "update"))
	var vl := CanvasLayer.new()
	vl.layer = 99  # over every screen and the in-game menu, under the boot logo (100)
	add_child(vl)
	var l := Label.new()
	l.text = "Tephra " + v
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(MUTED, 0.6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vl.add_child(l)
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = 22
	l.offset_top = -38
	l.offset_bottom = -12
	l.offset_right = 400
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

func _ready() -> void:
	preload("res://setup.gd").note_fresh_install()  # before anything saves a setting: is this the very first start?
	store = preload("res://store_lookup.gd").new()
	store.setup(self)
	add_child(store)
	phone = preload("res://phone_link.gd").new()
	phone.setup(self)
	add_child(phone)
	if Themes.font() != null:
		# The theme's typeface for every screen (the window's theme is what every label falls back to).
		var th := Theme.new()
		th.default_font = Themes.font()
		get_tree().root.theme = th
	else:
		get_tree().root.theme = null  # the last theme's font must not stay after switching to one without its own
	_base_fps = Engine.max_fps
	# Text that has no colour of its own takes the theme's text colour (Godot's default is white).
	var dt := ThemeDB.get_default_theme()
	if dt != null:
		# The control center and other panels sit on their own layers, which don't inherit the window's theme:
		# giving the default theme the same typeface makes every screen use the theme's font.
		dt.default_font = Themes.font()  # null (the theme has no font of its own) puts Godot's normal font back
		for cls in ["Label", "Button", "LineEdit", "RichTextLabel"]:
			dt.set_color("font_color", cls, Themes.c("text"))
		dt.set_color("default_color", "RichTextLabel", Themes.c("text"))
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://art"))
	TephraGlyphs.detect()
	TephraGlyphs.apply_deadzone()
	var reload := Themes.reloaded  # true when this is only the screens being rebuilt for a new theme
	Themes.reloaded = false
	if not reload:
		_apply_startup_volume()
	InGameHud.cleanup()  # MangoHud is gone: remove the settings file older versions wrote
	apply_ui_scale()
	if not reload:
		_taskbar_shortcut()
		_install_cli()
	_vol_snap_start.call_deferred()
	_tp_start.call_deferred()
	_make_version_label()
	_start_steam_quiet()
	_start_links()
	if not reload:
		_update_health()
	_pads_refresh()  # the touchpad click stays out of games (see steam_pads.py)
	# A PlayStation controller plugged in with a cable gets paired, so it reconnects wirelessly after unplugging.
	add_child(preload("res://marquee.gd").new())  # cut-off menu text scrolls
	var cable := preload("res://cable_pair.gd").new()
	add_child(cable)
	cable.paired.connect(func(n: String) -> void: notify("%s paired. Unplug it and it connects wirelessly." % (n if n != "" else "Controller")))
	_load_playtimes()
	_find_games()
	call_deferred("stop_steam_if_idle")
	_build()
	_make_launch_overlay()

	nav = preload("res://nav.gd").new()
	add_child(nav)
	nav.step.connect(_on_step)
	nav.fast_step.connect(_on_fast_step)

	controllers = preload("res://controllers.gd").new()
	add_child(controllers)
	toast = preload("res://toast.gd").new()
	add_child(toast)
	alert = preload("res://battery_alert.gd").new()
	alert.setup(controllers)
	add_child(alert)
	alert.alert_fired.connect(_on_alert)
	_setup_dev_overlay()

	cc = preload("res://control_center.gd").new()
	cc.controllers = controllers
	add_child(cc)
	cc.quit_game_requested.connect(_quit_game)
	cc.downloads_source = download_entries
	cc.download_action.connect(_on_download_action)
	cc.closed.connect(_on_cc_closed)
	cc.perf_move_requested.connect(_start_placing)
	overlay = preload("res://overlay.gd").new()
	add_child(overlay)
	overlay.start()
	controllers.changed.connect(cc.controllers_changed)
	controllers.changed.connect(func(): _player_colour_pending = true)
	controllers.changed.connect(func(): _pad_list_t = 99.0)  # show the new controller in the top bar at once

	album = preload("res://album.gd").new()
	album.setup(self)
	add_child(album)
	cc.album_requested.connect(_open_album)
	mods = preload("res://mods.gd").new()
	mods.setup(self)
	add_child(mods)
	cc.mods_requested.connect(_open_mods)
	mods.closed.connect(_on_mods_closed)
	add_child.call_deferred(preload("res://pad_gate.gd").new())  # last child: sees input first
	cc.theme_requested.connect(apply_theme)
	album.closed.connect(_on_album_closed)

	library = preload("res://library.gd").new()
	library.setup(self)
	add_child(library)
	library.launch_requested.connect(_launch_from_library)
	# Coming back from the Library lands on Home, not on the Library tile.
	library.closed.connect(func(): if not launching: _select(0))

	profile_screen = preload("res://profile.gd").new()
	profile_screen.setup(self)
	add_child(profile_screen)
	settings_screen = preload("res://settings_screen.gd").new()
	settings_screen.setup(self)
	add_child(settings_screen)
	setup_screen = preload("res://setup.gd").new()
	setup_screen.setup(self)
	add_child(setup_screen)
	top_menu = preload("res://top_menu.gd").new()
	top_menu.setup(self)
	add_child(top_menu)
	top_menu.closed.connect(_on_top_menu_closed)
	keyboard = preload("res://keyboard.gd").new()
	add_child(keyboard)
	phone_screen = preload("res://phone_screen.gd").new()
	phone_screen.setup(self)
	add_child(phone_screen)
	keyboard.phone_requested.connect(func() -> void: phone_screen.open("type"))
	keyboard.closed.connect(func(_accepted: bool) -> void:
		phone.stop_typing()
		if phone_screen.is_open and not phone_screen.sharing_captures():
			phone_screen.close())
	cc.keyboard_requested.connect(func(t: String, i: String, cb: Callable) -> void: keyboard.open(t, i, false, cb, {"max_len": 400}))
	browser = preload("res://browser.gd").new()
	add_child(browser)
	browser_tabs = preload("res://browser_tabs.gd").new()
	add_child(browser_tabs)
	browser_tabs.finished.connect(_browser_tabs_done)
	cc.browser_action.connect(_browser_action)
	sfx = preload("res://sfx.gd").new()
	add_child(sfx)
	if preload("res://frame_probe.gd").wanted():  # ~/.config/tephra/probe: log frame times (see frame_probe.gd)
		add_child(preload("res://frame_probe.gd").new())
	game_menu = preload("res://game_menu.gd").new()
	add_child(game_menu)
	game_menu.chosen.connect(_on_game_menu)
	controller_test = preload("res://controller_test.gd").new()
	controller_test.setup(self)
	add_child(controller_test)
	scene_test = preload("res://scene_test.gd").new()
	scene_test.setup(self)
	add_child(scene_test)
	color_picker = preload("res://color_picker.gd").new()
	color_picker.setup(self)
	add_child(color_picker)
	hdr_calibration = preload("res://hdr_calibration.gd").new()
	hdr_calibration.setup(self)
	add_child(hdr_calibration)
	idle_cover = ColorRect.new()
	idle_cover.color = Color.BLACK
	idle_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	idle_cover.modulate.a = 0.0
	var idle_layer := CanvasLayer.new()
	idle_layer.layer = 85
	add_child(idle_layer)
	# Resting (Settings > Screen rest): the menus fade away and only the theme's moving background stays,
	# a little dimmed. Channels has no moving background, so it just dims as before.
	if Themes.layout() != "channels":
		rest_bg = preload("res://tephra_bg.gd").new()
		rest_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rest_bg.modulate.a = 0.0
		rest_bg.visible = false
		idle_layer.add_child(rest_bg)
		rest_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	idle_layer.add_child(idle_cover)
	idle_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_make_alert_pill()
	_make_download_pill()

	Input.joy_connection_changed.connect(func(_d, _c): TephraGlyphs.detect(); _refresh_all_hints())
	_make_channels()
	if Themes.switched:
		Themes.switched = false
		sfx.play("sting")  # at once: the new theme's sound starts as it fades in
	_select(0, false)  # start on Home
	if not _theme_dissolve():
		_fade_in_from_black()
	_unlock_input_after_intro()
	_load_profile()
	_poll_wifi()
	_fetch_friends.call_deferred()
	_refresh_on_launch.call_deferred()
	var ft := Timer.new()
	ft.wait_time = 300.0
	ft.autostart = true
	ft.timeout.connect(_fetch_friends)
	add_child(ft)
	# Monitors plugged in or out while Tephra runs: move to the right one (external if present, else built-in).
	_screens_seen = DisplayServer.get_screen_count()
	var st := Timer.new()
	st.wait_time = 2.0
	st.autostart = true
	st.timeout.connect(_check_screens)
	add_child(st)
	_claim_instance.call_deferred()
	var wt := Timer.new()
	wt.wait_time = 15.0
	wt.autostart = true
	wt.timeout.connect(_poll_wifi)
	add_child(wt)

var _screens_seen := 1

# ---------- Only one Tephra at a time ----------
# The updater script, Tephra's own "reload after an update" and a hand-typed `tephra` can each start a new
# copy, and two copies fight over the screen, the controller and the GPU (that halves the frame rate). So
# every copy writes its process number into ~/.config/tephra/instance.pid when it starts. A moment later it
# looks again: if the file now holds a different, still-running process, a newer copy has started, and this
# one quits. The newest copy always wins.
func _claim_instance() -> void:
	var dir := OS.get_environment("HOME") + "/.config/tephra"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/instance.pid"
	var me := OS.get_process_id()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(str(me))
	f.close()
	for wait in [0.6, 1.2, 2.0]:
		await get_tree().create_timer(wait).timeout
		var other := FileAccess.get_file_as_string(path).strip_edges().to_int()
		if other != 0 and other != me and DirAccess.dir_exists_absolute("/proc/%d" % other):
			print("Tephra: a newer copy (%d) is running, so this one (%d) quits" % [other, me])
			get_tree().quit()
			return

func _check_screens() -> void:
	var m := Time.get_ticks_usec()
	var n := DisplayServer.get_screen_count()
	preload("res://frame_probe.gd").mark("screen check", m)
	if n == _screens_seen:
		return
	_screens_seen = n
	if _game_active or launching:
		return  # a game is running: leave the windows alone
	await get_tree().create_timer(1.5).timeout  # let the new screen settle
	DisplayCtl.place_best()

# Keep controls locked until the boot logo has faded away.
# The DualSense lightbar fades up to navy while the logo is showing.
var _music_early := false  # set near the end of the logo so the music is already fading in as it leaves

## Every start and every theme change reads the things that go stale again: the weather, the games you own and your
## Steam Family's, and the profile. (Friends are read just above; the weather is also re-read every 15 minutes.)
## Developer menu > Refresh all: all that can be fetched again without restarting Tephra. Weather, the game
## list, Steam's online data (family games, friends), pictures for non-Steam and PS2 games, and the in-memory caches
## (pictures, logos, where art files live). Nothing saved is touched.
func refresh_everything() -> void:
	dev_toast("Refreshing all...")
	weather.fetch(true)
	_art_path_memo.clear()
	_art_cache.clear()
	_art_order.clear()
	_logo_cache.clear()
	Settings.set_value("art_misses", {})
	Settings.set_value("ps2_store_art", {})
	refresh_games(false)
	library.refresh_online()
	cc._read_system_state()
	await ps2_sync()
	_prewarm_logos()
	if not launching:
		library.prewarm()
	_select(selected, false)
	_pulse_tiles()  # every cover bounces so the refresh is visible
	dev_toast("All refreshed")

func _refresh_on_launch() -> void:
	await get_tree().create_timer(2.0).timeout  # after the intro has had the screen to itself
	weather.fetch(true)
	library.refresh_online()
	_load_profile()
	ps2_sync()
	res_cleanup()  # the removed Game resolution setting: undo what it did to Steam games
	if OS.execute("pgrep", ["-f", "[p]csx2"], []) != 0:
		GameRes.pcsx2_console_setup()  # PCSX2 reads the pad and stays quiet (only while it is closed)
	refresh_games(false)  # games installed or removed while Tephra was closed or reloading: quietly, no pulse
	await get_tree().create_timer(3.0).timeout
	if not launching:
		library.prewarm()
		_prewarm_logos()

func _unlock_input_after_intro() -> void:
	var boot := get_node_or_null("/root/BootOverlay")
	if boot != null:
		var hold: float = float(boot.get("hold")) if boot.get("hold") != null else 4.0
		controllers.intro_fade(hold)
		sfx.play_intro()  # the start-up sound; the background music fades in as it rings out
		get_tree().create_timer(maxf(hold - 1.2, 0.5)).timeout.connect(func() -> void: _music_early = true)
		await boot.finished
	else:
		controllers.apply_player_lights()
	input_locked = false
	alert.enable()  # battery alerts only start once the logo has gone
	setup_screen.start_if_needed()  # a first boot (or setup that a theme restart interrupted)

# Settings > Audio > Volume when Tephra starts.
func _apply_startup_volume() -> void:
	var v := int(Settings.get_value("startup_volume", -1))
	if v >= 0:
		OS.create_process("wpctl", ["set-volume", "@DEFAULT_AUDIO_SINK@", "%.2f" % (v / 100.0)])

## The old "Game resolution" setting (removed in v0.99.32) put tephra-run (gamescope) in front of Steam games and
## turned Steam Input off for them. This takes that back out of every game, once: only while Steam is closed (Steam
## rewrites localconfig.vdf when it closes), and until it has worked tephra-run stays as a plain pass-through so those
## games still start. Runs at start-up and every time Steam has closed, until it is done.
func res_cleanup() -> void:
	if bool(Settings.get_value("res_removed", false)):
		return
	GameRes.write_passthrough()
	if _steam_running():
		return
	var res := GameRes.remove_wrapper(steam_dir)
	var err := str(res["error"])
	if err == "no localconfig":
		return  # no Steam login found yet: nothing to clean
	if err != "":
		notify(err, "info")
		Settings.set_value("res_removed", true)  # never ask again; the pass-through script stays so games still start
		return
	if int(res["changed"]) > 0:
		_install_log("Game resolution removed: took tephra-run out of %d Steam games and gave them back their Steam Input setting" % int(res["changed"]))
	GameRes.delete_files()

## PS2 discs in ~/Games/PS2 become Steam shortcuts (only while Steam is closed, because Steam rewrites that file),
## each gets a cover, the BIOS is copied where PCSX2 reads it, and RetroAchievements are read for them.
var _ps2_busy := false

func ps2_sync(manual := false) -> void:
	if _ps2_busy:
		return
	_ps2_busy = true
	if not _steam_running():
		var ps2_ids: Array = []
		for g0 in games:
			if g0.get("ps2", false):
				ps2_ids.append(str(g0["id"]))
		GameRes.input_off(steam_dir, ps2_ids)  # Steam Input would take the pad away from PCSX2
		if Ps2Games.update_launch_options(steam_dir) > 0:
			refresh_games(false)
	var bios := Ps2Games.import_bios()
	if bios != "":
		notify("PS2 BIOS imported: " + bios, "info")
	var todo := Ps2Games.missing(steam_dir)
	if not todo.is_empty():
		if _steam_running():
			if manual:
				notify("Close Steam first (Settings > Games > Close Steam now), then scan again.", "info")
		else:
			var res := Ps2Games.add_to_steam(steam_dir, todo)
			if str(res["error"]) != "":
				notify(str(res["error"]), "info")
			elif int(res["added"]) > 0:
				await _ps2_covers(todo)  # added quietly: they simply appear
				refresh_games(false)
	elif manual:
		notify("No new PS2 games found in " + Ps2Games.games_dir(), "info")
	await _ps2_covers(Ps2Games.scan())  # covers for games added earlier, or whose picture was missing before
	await store._ps2_store_art()
	# Wide pictures (Channels tiles, the game page's backdrop) made from the covers, on a worker thread.
	var done := {}
	var redo := int(Settings.get_value("wide_art_v", 1)) < 2
	Settings.set_value("wide_art_v", 2)
	var wid := _work(func() -> void:
		done["n"] = Ps2Games.make_wide_art(steam_dir, redo))
	while not done.has("n"):
		await get_tree().create_timer(0.2).timeout
	_work_done(wid)
	await store._nonsteam_art()
	if int(done["n"]) > 0 or store._art_found > 0 or redo:
		_art_path_memo.clear()
		_art_cache.clear()
		_art_order.clear()
		_logo_cache.clear()
		_prewarm_logos()
		refresh_games(false)
	_ps2_busy = false
	var ps2: Array = []
	for g in games:
		if g.get("ps2", false):
			ps2.append({"id": g["id"], "title": g["title"]})
	if retro != null and not ps2.is_empty():
		retro.sync(ps2)

func _ps2_covers(entries: Array) -> void:
	var index := Ps2Games.cached_index()
	var need := false
	for e in entries:
		var d0 := Ps2Games.cover_path(steam_dir, str(e["title"]))
		if d0 != "" and not FileAccess.file_exists(d0):
			need = true
	if need and index.is_empty():
		var ireq := HTTPRequest.new()
		ireq.timeout = 30.0
		add_child(ireq)
		if ireq.request(Ps2Games.THUMBS) == OK:
			var ires: Array = await ireq.request_completed
			if int(ires[0]) == HTTPRequest.RESULT_SUCCESS and int(ires[1]) == 200:
				index = Ps2Games.parse_index((ires[3] as PackedByteArray).get_string_from_utf8())
				if not index.is_empty():
					Ps2Games.save_index(index)
		ireq.queue_free()
	for e in entries:
		var dest := Ps2Games.cover_path(steam_dir, str(e["title"]))
		if dest == "" or FileAccess.file_exists(dest):
			continue
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var pic := Ps2Games.best_cover_name(index, str(e["title"]), str(e["stem"]))
		var urls: Array = Ps2Games.cover_urls(pic) if pic != "" else []
		for u in Ps2Games.cover_urls(str(e["stem"])):
			if u not in urls:
				urls.append(u)
		for u in urls:  # the thumbnail server first, then the GitHub mirror when it is slow or down
			var req := HTTPRequest.new()
			req.timeout = 30.0
			add_child(req)
			if req.request(u) != OK:
				req.queue_free()
				continue
			var res: Array = await req.request_completed
			req.queue_free()
			if int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200:
				var f := FileAccess.open(dest, FileAccess.WRITE)
				if f != null:
					f.store_buffer(res[3])
					break

# ---------- Store lookups, pictures for non-Steam games, adding a game ----------
## All of it lives in store_lookup.gd (home.gd keeps this one forwarding call: the Library's R1 "Add a game").
var store  # store_lookup.gd

func add_game() -> void:
	store.add_game()


# ---------- Startup fade-in ----------
func _fade_in_from_black() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var fade := ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, 0.8)
	tween.tween_callback(layer.queue_free)

# ---------- Find installed Steam games ----------
var _extra_exe := {}   # non-Steam game id -> pattern that finds its running program

func _find_games() -> void:
	games.clear()
	var libs: Array = [steam_dir]
	var vdf := FileAccess.get_file_as_string(steam_dir + "/steamapps/libraryfolders.vdf")
	var re_path := RegEx.new()
	re_path.compile("\"path\"\\s+\"([^\"]+)\"")
	for m in re_path.search_all(vdf):
		var p: String = m.get_string(1)
		if not libs.has(p):
			libs.append(p)
	var re_id := RegEx.new()
	re_id.compile("\"appid\"\\s+\"(\\d+)\"")
	var re_name := RegEx.new()
	re_name.compile("\"name\"\\s+\"([^\"]+)\"")
	var re_last := RegEx.new()
	re_last.compile("\"LastPlayed\"\\s+\"(\\d+)\"")
	var re_size := RegEx.new()
	re_size.compile("\"SizeOnDisk\"\\s+\"(\\d+)\"")
	var seen := {}
	for lib in libs:
		var dir := DirAccess.open(lib + "/steamapps")
		if dir == null:
			continue
		for f in dir.get_files():
			if not (f.begins_with("appmanifest_") and f.ends_with(".acf")):
				continue
			var txt := FileAccess.get_file_as_string(lib + "/steamapps/" + f)
			var id_m := re_id.search(txt)
			var name_m := re_name.search(txt)
			if id_m == null or name_m == null:
				continue
			var title: String = name_m.get_string(1)
			var skip := false
			for s in SKIP:
				if title.contains(s):
					skip = true
			var id := id_m.get_string(1)
			if skip or seen.has(id):
				continue
			seen[id] = true
			var last_m := re_last.search(txt)
			var last := last_m.get_string(1).to_int() if last_m != null else 0
			var size_m := re_size.search(txt)
			var size := size_m.get_string(1).to_int() if size_m != null else 0
			games.append({"id": id, "title": title, "last": last, "size": size, "playtime": playtimes.get(id, 0)})
	# Non-Steam games (a .exe added to Steam by hand, like P.T.): same kind of entry, started through Steam.
	_extra_exe.clear()
	for x in ExtraGames.nonsteam_games(steam_dir):
		if seen.has(x["id"]):
			continue
		seen[x["id"]] = true
		_extra_exe[x["id"]] = ExtraGames.process_pattern(str(x["exe"]))
		games.append(x)
	GameNames.apply(games)  # your own names for games
	var launched: Dictionary = Settings.get_value("launched_at", {})
	for lg in games:
		lg["last"] = maxi(int(lg["last"]), int(launched.get(str(lg["id"]), 0)))  # started from Tephra after Steam last wrote it
	games.sort_custom(_sort_games)
	_apply_nonsteam_sizes()

# ---------- Size of non-Steam games ----------
## A non-Steam game has no manifest, so its size is measured: the folder its program sits in (a game under
## ~/Games/<Name>/... counts the whole <Name> folder). Shared places (the home folder, Downloads, /usr/bin...) are never
## measured. The result is kept in Settings ("nonsteam_sizes": exe -> [bytes, when]) and measured again after a day,
## in the background, so opening Tephra never waits for it.
var _size_task := false

static func nonsteam_game_dir(exe: String) -> String:
	var home := OS.get_environment("HOME")
	var d := exe.get_base_dir()
	if exe == "" or d == "" or d == "/" or d == home:
		return ""
	var root := home + "/Games/"
	if exe.begins_with(root):
		var first := exe.trim_prefix(root).get_slice("/", 0)
		return (root + first) if first != "" and exe.trim_prefix(root).contains("/") else ""
	for bad in [home + "/Downloads", home + "/Desktop", home + "/Documents", home + "/bin", home + "/.local/bin", "/usr", "/bin", "/opt", "/tmp", "/home", "/mnt", "/media"]:
		if d == bad:
			return ""
	return d

func _apply_nonsteam_sizes() -> void:
	var cache: Dictionary = Settings.get_value("nonsteam_sizes", {})
	var now := Time.get_unix_time_from_system()
	var todo: Array = []  # [id, dir, exe]
	for g in games:
		if not bool(g.get("nonsteam", false)) or bool(g.get("ps2", false)):
			continue
		var exe := str(g.get("exe", ""))
		var dir := nonsteam_game_dir(exe)
		if dir == "":
			continue
		var hit = cache.get(exe, null)
		if hit is Array and hit.size() == 2:
			g["size"] = float(hit[0])
			if now - float(hit[1]) < 86400:
				continue
		todo.append([str(g["id"]), dir, exe])
	if todo.is_empty() or _size_task:
		return
	_size_task = true
	var box := {}
	box["id"] = _work(func() -> void:
		var res: Array = []
		for t in todo:
			var out := []
			if OS.execute("du", ["-sb", str(t[1])], out) == 0 and not out.is_empty():
				res.append([t[0], t[2], str(out[0]).split("\t")[0].to_int()])
		_nonsteam_sizes_done.call_deferred(box, res))

func _nonsteam_sizes_done(box: Dictionary, res: Array) -> void:
	_work_done(int(box.get("id", -1)))
	_size_task = false
	var cache: Dictionary = Settings.get_value("nonsteam_sizes", {})
	var now := Time.get_unix_time_from_system()
	for r in res:
		cache[str(r[1])] = [int(r[2]), now]
		for g in games:
			if str(g["id"]) == str(r[0]):
				g["size"] = float(r[2])
	Settings.set_value("nonsteam_sizes", cache)

# Minutes played per game, from Steam's local settings for the most recent user.
func _load_playtimes() -> void:
	var newest := ""
	var newest_time := 0
	var dir := DirAccess.open(steam_dir + "/userdata")
	if dir == null:
		return
	for u in dir.get_directories():
		var p := steam_dir + "/userdata/" + u + "/config/localconfig.vdf"
		var t := FileAccess.get_modified_time(p)
		if t > newest_time:
			newest_time = t
			newest = p
	if newest == "":
		return
	var txt := FileAccess.get_file_as_string(newest)
	var re := RegEx.new()
	re.compile("\"(\\d+)\"\\s*\\{[^{}]*?\"Playtime\"\\s+\"(\\d+)\"")
	for m in re.search_all(txt):
		playtimes[m.get_string(1)] = m.get_string(2).to_int()

# Most recently played first; never-played games after, A to Z.
func _sort_games(a: Dictionary, b: Dictionary) -> bool:
	if a["last"] != b["last"]:
		return a["last"] > b["last"]
	return a["title"].naturalnocasecmp_to(b["title"]) < 0

# ---------- Build the screen ----------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	bg_anim = preload("res://tephra_bg.gd").new()
	add_child(bg_anim)
	bg_anim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The game's picture is a wide banner (1920 x 620). Stretching it to cover the whole screen blew it up
	# 1.7x and made it blurry. Now it is drawn at its own proportions across the top (sharp), and a dimmed,
	# stretched copy behind it fills the rest, which the bottom shading then fades out.
	hero_back = TextureRect.new()
	hero_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	hero_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hero_back)
	hero = TextureRect.new()
	hero.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL  # as tall as its width allows, same shape as the picture
	hero.stretch_mode = TextureRect.STRETCH_SCALE
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hero)
	hero.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)

	# Darkening over the game's hero picture, so text stays readable. Only while a game
	# is selected: Home and the Library show the plain Tephra background.
	shade_a = _shade(Vector2(0, 0), Vector2(1, 0))
	shade_b = _shade(Vector2(0, 1), Vector2(0, 0.3))
	add_child(shade_a)
	add_child(shade_b)
	if Themes.id() == "frutiger":
		shade_b.visible = false  # no pale fade over the grass and water at the bottom
		# ...so the picture itself fades out towards its bottom edge instead of stopping in a hard line.
		var fade := ShaderMaterial.new()
		fade.shader = Shader.new()
		fade.shader.code = """shader_type canvas_item;
void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
	COLOR.a *= 1.0 - smoothstep(0.45, 1.0, UV.y);
}"""
		hero.material = fade
		hero_back.material = fade

	detail_dim = ColorRect.new()
	detail_dim.color = Color(BG, 0.25 if Themes.id() == "frutiger" else 0.7)
	detail_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_dim.modulate.a = 0.0
	add_child(detail_dim)
	detail_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	page = Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# A plain, soft band behind the top bar: it brightens a little while the top bar has the focus.
	strip = Panel.new()
	strip_style = StyleBoxFlat.new()
	strip_style.bg_color = Themes.ink(0.06)
	strip_style.border_color = Themes.ink(0.10)
	strip_style.border_width_bottom = 2
	strip.add_theme_stylebox_override("panel", strip_style)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.modulate.a = 0.5
	if Themes.id() == "ps2":
		# PS2: a darker band, still clearly there (a dark wash with a faint light edge instead of a light tint).
		strip_style.bg_color = Color(0.045, 0.06, 0.09, 0.9)
		strip_style.border_color = Themes.ink(0.16)
		strip.modulate.a = 1.0
	page.add_child(strip)
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_top = 62
	strip.offset_bottom = 154

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	page.add_child(margin)
	_make_top_shade()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 32)
	margin.add_child(vbox)

	# Top bar: shard · clock · Wi-Fi ............ name (avatar)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	top.custom_minimum_size.y = AVATAR
	vbox.add_child(top)
	shard_icon = TextureRect.new()
	var shard := shard_icon
	shard.texture = Icons.shard(52)
	shard.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	shard.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(shard)
	clock_label = _label("", 32, TEXT)
	clock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(clock_label)
	wifi_icon = TextureRect.new()
	wifi_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	wifi_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wifi_icon.custom_minimum_size = Vector2(32, 32)
	top.add_child(wifi_icon)
	_apply_wifi(true, 0)
	bt_icon = TextureRect.new()
	bt_icon.texture = Icons.texture("bluetooth", Icons.svg_bluetooth(), 32)
	bt_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	bt_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bt_icon.custom_minimum_size = Vector2(32, 32)
	bt_icon.modulate.a = 0.85
	top.add_child(bt_icon)
	# Your controller: green above 30%, orange at 30% or less, red at 10% or less.
	# One icon per connected controller (up to four), each coloured by its own battery.
	var pw := HBoxContainer.new()
	pw.add_theme_constant_override("separation", 6)
	pw.custom_minimum_size = Vector2(40, 32)
	pw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pad_wrap = pw
	top.add_child(pad_wrap)
	pad_icon = _new_pad_icon()
	pad_wrap.add_child(pad_icon)
	_pad_icons = [pad_icon]
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var bw := HBoxContainer.new()
	bw.add_theme_constant_override("separation", 6)
	bw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bw.visible = false  # shown only when this PC has a battery
	batt_wrap = bw
	top.add_child(bw)
	batt_icon = TextureRect.new()
	batt_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	batt_icon.custom_minimum_size = Vector2(66, 48)  # bigger, so it reads at a glance
	batt_icon.modulate.a = 0.85
	bw.add_child(batt_icon)
	batt_pct = _label("", 22, TEXT)  # slides open next to the icon when you press A on it
	batt_pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	batt_pct.custom_minimum_size.x = 0
	batt_pct.clip_text = true
	batt_pct.modulate.a = 0.0
	bw.add_child(batt_pct)
	var gear_box := Control.new()  # settings gear, left of your name
	gear_box.custom_minimum_size = Vector2(AVATAR - 12, AVATAR)
	gear_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(gear_box)
	gear_icon = TextureRect.new()
	gear_icon.texture = Icons.texture("gear", Icons.svg_gear(), 40)
	gear_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	gear_icon.modulate.a = 0.75
	gear_box.add_child(gear_icon)
	gear_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gear_gap := Control.new()
	gear_gap.custom_minimum_size.x = 0
	top.add_child(gear_gap)
	profile_name = _label("", 28, TEXT)
	profile_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(profile_name)
	# The picture sits in a fixed box. The selection ring is drawn OUTSIDE the
	# picture (a few pixels bigger), so it never cuts into the image.
	var avatar_box := Control.new()
	avatar_box.custom_minimum_size = Vector2(AVATAR, AVATAR)
	avatar_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(avatar_box)
	var circle := Panel.new()
	circle.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color.WHITE
	csb.set_corner_radius_all(Themes.r(AVATAR / 2))
	circle.add_theme_stylebox_override("panel", csb)
	avatar_box.add_child(circle)
	circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar_rect = TextureRect.new()
	avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	circle.add_child(avatar_rect)
	avatar_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar_ring = Panel.new()  # white outline while the profile is selected
	var asb := StyleBoxFlat.new()
	asb.draw_center = false
	asb.border_color = SELECT
	asb.set_border_width_all(4)
	asb.set_corner_radius_all(Themes.r(AVATAR / 2 + 8))
	avatar_ring.add_theme_stylebox_override("panel", asb)
	avatar_ring.visible = false
	avatar_box.add_child(avatar_ring)
	avatar_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP]:
		avatar_ring.set_offset(side, -8)
	for side in [SIDE_RIGHT, SIDE_BOTTOM]:
		avatar_ring.set_offset(side, 8)
	var ring := Panel.new()  # thin ring so the circle shows before the picture loads
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Themes.c("tile")
	rsb.set_corner_radius_all(Themes.r(AVATAR / 2))
	ring.add_theme_stylebox_override("panel", rsb)
	ring.show_behind_parent = true
	avatar_rect.add_child(ring)
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer2)

	# Fixed-height title area: logo, or the name if there's no logo.
	# The height never changes, so nothing below it jumps when switching.
	var title_box := Control.new()
	title_area = title_box
	title_box.custom_minimum_size.y = LOGO_MAX.y
	vbox.add_child(title_box)
	title_label = _label("", 72, TEXT)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.clip_text = true
	title_box.add_child(title_label)
	title_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_label.offset_right = -620  # leave room for the info card on the right
	if Themes.id() == "neon":
		# Neon Coast: cyan letters with a deep pink block behind them (like an extruded 3D title) and a dark edge.
		title_label.add_theme_color_override("font_color", Themes.c("select"))
		title_label.add_theme_color_override("font_shadow_color", Color("FF2E88"))
		title_label.add_theme_constant_override("shadow_offset_x", 6)
		title_label.add_theme_constant_override("shadow_offset_y", 6)
		title_label.add_theme_color_override("font_outline_color", Color("2A0838"))
		title_label.add_theme_constant_override("outline_size", 10)
		_neon_title = true
	logo_rect = TextureRect.new()
	logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_rect.stretch_mode = TextureRect.STRETCH_SCALE
	logo_rect.visible = false
	title_box.add_child(logo_rect)

	scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = TILE.y + 70
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = false  # let the selected tile's shadow fall below the row instead of being cut off
	vbox.add_child(scroll)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 30)
	scroll.add_child(pad)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	pad.add_child(row)
	_build_row()

	hints = HBoxContainer.new()
	hints.alignment = BoxContainer.ALIGNMENT_END  # bottom right
	vbox.add_child(hints)
	hints.z_index = 20  # always in front: the details sheet and its soft top edge must never fade the glyphs
	_refresh_all_hints()

	# Details section below the row (placed in _process).
	details = preload("res://game_details.gd").new()
	details.steam_dir = steam_dir
	details.account = Achievements.account_id(SteamAccount.steam_id(steam_dir))
	details.games = games
	details.art_loader = _load_art
	perf = preload("res://perf.gd").new()
	add_child(perf)
	details.perf = perf
	details.play_requested.connect(_play_from_today)
	retro = preload("res://retro_ach.gd").new()
	add_child(retro)
	weather = preload("res://weather.gd").new()
	add_child(weather)
	details.weather = weather
	weather.changed.connect(details.fill_weather)
	# Weather updates quietly (no notification): it is re-read every 10 minutes and whenever a screen opens or a game starts or closes.
	page.add_child(details)
	_update_titles()

# Game titles by id, so the recent list can name games Steam's files don't.
func _update_titles() -> void:
	for g in games:
		details.titles[str(g["id"])] = g["title"]

func _shade(from: Vector2, to: Vector2) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, Color(BG, 0.95))
	grad.set_color(1, Color(BG, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = from
	gtex.fill_to = to
	var rect := TextureRect.new()
	rect.texture = gtex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

## Rebuilds every hint bar, e.g. after switching from a DualSense to an Xbox pad.
var _hint_key := ""

## True when this game is the one running right now (its tile reads "Running" instead of "Play").
func game_is_running(id: String) -> bool:
	return launching and _game_started and id == _game_id

## Stepping from game to game changes nothing about the button bars, so they are only rebuilt when what they show changes.
func _hint_sig() -> String:
	var gi := _game_selected()
	var running := gi >= 0 and game_is_running(str(games[gi]["id"]))
	return "%s|%s|%s|%s|%s|%s|%s" % [profile_focus, _library_selected(), gi >= 0, cross_opens_info(), running, _guide_label(), TephraGlyphs.family]

func _refresh_hints_if_changed() -> void:
	if _hint_sig() == _hint_key:
		return
	_refresh_all_hints()

func _refresh_all_hints() -> void:
	_hint_key = _hint_sig()
	var items: Array = []
	if profile_focus:
		items.append(["accept", {"wifi": "Wi-Fi", "bt": "Bluetooth", "pad": "Controllers", "battery": "Show / hide percentage", "gear": "Open settings", "profile": "Open profile"}[TOP_ITEMS[top_index]]])
		items.append(["dpad_h", "Switch"])
		items.append(["dpad_v", "Back to games"])
		items.append(["guide", _guide_label()])
		TephraGlyphs.fill(hints, items, 26)
		return
	if _library_selected():
		items.append(["accept", "Open"])
	elif _game_selected() >= 0:
		var gi_h := _game_selected()
		if game_is_running(str(games[gi_h]["id"])):
			items.append(["accept", "Resume"])  # the game being played: Cross goes straight back into it
		else:
			items.append(["accept", "Options" if cross_opens_info() else "Play"])
	items.append(["dpad_h", "Browse"])
	if not _library_selected():
		items.append(["dpad_v", "More"])
	var gi_n := _game_selected()
	if gi_n >= 0 and (not cross_opens_info() or game_is_running(str(games[gi_n]["id"]))):
		items.append(["north", "Options"])  # the running game always has its menu on Triangle
	items.append(["guide", _guide_label()])
	TephraGlyphs.fill(hints, items, 26)
	if details != null:
		details.refresh_hints()
	if cc != null:
		cc.refresh_hints()
	if library != null:
		library.refresh_hints()
	if setup_screen != null:
		setup_screen.refresh_hints()
	if phone_screen != null:
		phone_screen.refresh_hints()

# ---------- Tiles ----------
# Row = Home tile, one tile per installed game, Library tile.
func _build_row() -> void:
	for t in tiles:
		row.remove_child(t)
		t.queue_free()
	tiles.clear()
	frames.clear()
	shadows.clear()
	shines.clear()
	tile_game.clear()
	var hidden: Array = Settings.get_value("hidden_games", [])
	_make_icon_tile(Icons.texture("home", Icons.svg_home(), 120), HOME_TILE_BG)
	tile_game.append(-1)
	for i in games.size():
		if not on_home(games[i]):
			continue  # not on the home row (it is always still in the Library)
		_make_game_tile(games[i])
		tile_game.append(i)
	_make_icon_tile(Icons.texture("library", Icons.svg_library(), 96), TILE_BG)
	tile_game.append(-1)
	_dl_apply()

## Is this game on the Home row? Ordinary games are, unless you hid them. Non-Steam games (and other extras)
## only are when you pinned them.
func on_home(g: Dictionary) -> bool:
	var id := str(g["id"])
	if bool(g.get("extra", false)):
		return Settings.get_value("home_pinned", []).has(id)
	return not Settings.get_value("hidden_games", []).has(id)

## Pin a game to Home (true) or take it off the row (false). The game itself stays in the Library either way.
func set_on_home(g: Dictionary, on: bool) -> void:
	var id := str(g["id"])
	var pinned: Array = Settings.get_value("home_pinned", []).duplicate()
	var hidden: Array = Settings.get_value("hidden_games", []).duplicate()
	if on:
		if not pinned.has(id):
			pinned.append(id)
		hidden.erase(id)
	else:
		pinned.erase(id)
		if not bool(g.get("extra", false)) and not hidden.has(id):
			hidden.append(id)
	Settings.set_value("home_pinned", pinned)
	Settings.set_value("hidden_games", hidden)

# Re-reads installed games (after an install finishes) and rebuilds the row,
# keeping the same game selected.
var _neon_title := false
var _neon_t := 0.0
var _covered: Array = []  # Home's layers hidden while a full-screen page (the Library) is over them

func cover_home(on: bool) -> void:
	if on:
		for c in [bg_anim, hero_back, hero, shade_a, shade_b, page]:
			if (c as CanvasItem).visible:
				(c as CanvasItem).visible = false
				_covered.append(c)
	else:
		for c in _covered:
			(c as CanvasItem).visible = true
		_covered.clear()
		if bg_anim.modulate.a <= 0.01:
			bg_anim.visible = false  # it was fading out when covered

func refresh_games(pulse := true) -> void:
	var keep_id := ""
	var gi := _game_selected()
	if gi >= 0:
		keep_id = str(games[gi]["id"])
	_find_games()
	_update_titles()
	_build_row()
	for g in games:
		var gid := str(g["id"])
		if gid.is_valid_int() and int(gid) <= 0x7FFFFFFF and _find_local_art(gid, "library_600x900") == "" and not FileAccess.file_exists("user://art/%s_library_600x900.jpg" % gid):
			prefetch_art(gid)  # an installed game Steam has no cover for (newer games keep theirs in a hashed folder)
	if channels != null:
		channels.rebuild()
	var idx := selected
	for j in tile_game.size():
		if tile_game[j] >= 0 and str(games[tile_game[j]]["id"]) == keep_id:
			idx = j
	_select(clampi(idx, 0, tiles.size() - 1), false)
	if pulse:
		_pulse_tiles()
	if library != null and library.is_open:
		library.games_changed()  # a game was uninstalled / renamed / pinned from a menu: the Library follows

# Every tile shrinks for a moment and springs back, so you can see the games were reloaded.
func _pulse_tiles() -> void:
	if not Motion.on():
		return
	await get_tree().process_frame  # let the new row lay out first
	for j in tiles.size():
		var tile: Control = tiles[j]
		if not is_instance_valid(tile):
			continue
		var rest: float = tile.scale.x  # the selected tile is a bit bigger than the rest
		var tw := create_tween()
		tw.tween_property(tile, "scale", Vector2.ONE * rest * 0.8, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(tile, "scale", Vector2.ONE * rest, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Steam's own windows (loading popups, dialogs) are kept behind Tephra by a KDE
# window rule. Installing needs its popup visible, so the rule is switched off
# while an install is being confirmed and on again otherwise. We edit the rule
# in ~/.config/kwinrulesrc ourselves (a line `Enabled=false` under its header)
# and ask KWin to re-read it.
const STEAM_RULE := "4045d3eb-fa74-42e5-97eb-743f5622ba7f"

func steam_rule(hidden: bool) -> void:
	var path := OS.get_environment("HOME") + "/.config/kwinrulesrc"
	if not FileAccess.file_exists(path):
		return
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var out: PackedStringArray = []
	var in_rule := false
	var changed := false
	for ln in lines:
		if ln.begins_with("["):
			in_rule = (ln == "[" + STEAM_RULE + "]")
			out.append(ln)
			if in_rule and not hidden:
				out.append("Enabled=false")  # rule off: Steam windows show normally
				changed = true
			continue
		if in_rule and ln.strip_edges() == "Enabled=false":
			if hidden:
				changed = true  # drop the line: rule on again
			continue
		out.append(ln)
	if not changed:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\n".join(out))
	f.close()
	OS.execute("qdbus6", ["org.kde.KWin", "/KWin", "reconfigure"])

# Raw text of a game's appmanifest from any Steam library ("" if none yet).
func manifest_text(id: String) -> String:
	var libs: Array = [steam_dir]
	var re_path := RegEx.new()
	re_path.compile("\"path\"\\s+\"([^\"]+)\"")
	for m in re_path.search_all(FileAccess.get_file_as_string(steam_dir + "/steamapps/libraryfolders.vdf")):
		if not libs.has(m.get_string(1)):
			libs.append(m.get_string(1))
	for lib in libs:
		var p: String = lib + "/steamapps/appmanifest_" + id + ".acf"
		if FileAccess.file_exists(p):
			return FileAccess.get_file_as_string(p)
	return ""

# ---------- Downloads (control center) ----------
func _steam_libs() -> Array:
	var libs: Array = [steam_dir]
	var re_path := RegEx.create_from_string("\"path\"\\s+\"([^\"]+)\"")
	for m in re_path.search_all(FileAccess.get_file_as_string(steam_dir + "/steamapps/libraryfolders.vdf")):
		if not libs.has(m.get_string(1)):
			libs.append(m.get_string(1))
	return libs

func _acf_value(txt: String, key: String) -> String:
	var m := RegEx.create_from_string("\"" + key + "\"\\s+\"([^\"]*)\"").search(txt)
	return m.get_string(1) if m != null else ""

# ---------- Tephra updates from GitHub (self_update.gd) ----------
## Ten seconds after start, then every minute, Tephra quietly looks for a newer version (git runs on a worker thread,
## and never while a game is running, so nothing stutters). Nothing is said unless
## there is one: then, once per version, a notification "Update available". A on it in the control center opens the
## Downloads panel, where the update is installed (Tephra restarts by itself).
var _upd_acc := 0.0

var _update_toast_later := false

## Right after an update the launcher (tephra-run.sh) watches this start: if it crashes or hangs, the old version comes
## back. Ten seconds of running fine keeps the new one. If the old one had to come back, it says so (once).
func _update_health() -> void:
	var su := preload("res://self_update.gd")
	var msg: String = su.rollback_notice()
	if msg != "":
		get_tree().create_timer(4.0).timeout.connect(func() -> void: notify(msg))
	get_tree().create_timer(10.0).timeout.connect(func() -> void: su.mark_healthy())

func _update_poll(delta: float) -> void:
	if _update_toast_later and not _game_active and not launching:
		_update_toast_later = false
		sfx.play("update")
		toast.show_toast(Icons.texture("bell", Icons.svg_bell(), 40), "Update available: Tephra %s" % preload("res://self_update.gd").remote, false, false)
	_upd_acc += delta
	if _upd_acc < 10.0 or (launching and not _game_started):
		return  # not while a game is starting up
	_upd_acc = 0.0
	var su := preload("res://self_update.gd")
	su.check(self, func(result: String) -> void:
		if result == "ready" and str(Settings.get_value("update_told", "")) != su.remote:
			Settings.set_value("update_told", su.remote)
			if _game_active:
				# in a game or the browser: kept in Notifications now, and popped up when Tephra comes back
				preload("res://notifications.gd").push("Update available: Tephra %s" % su.remote, "tephra_update")
				_update_toast_later = true
			else:
				notify("Update available: Tephra %s" % su.remote, "tephra_update"))

# ---------- Games installing, on the Home row ----------
## Every 2 s a worker reads Steam's manifests (download_entries); each game tile on Home that Steam is downloading
## (a new install or an update) gets a dl_overlay.gd: its cover fills up, its border fills up and it shows the
## percentage. When a new install finishes, the row is made again so the game gets its real picture.
var _dl := {}            # game id -> {pct, state, installed}
var _dl_acc := 1.6
var _dl_task := -1
var _dl_seen := {}

## Before (and as) a game installs, its pictures are fetched from Steam's servers into Tephra's own cache, so its tile,
## its page, the Library and every layout show the real cover, backdrop and logo from the first moment (Steam only puts
## them in its own folder once the game is installed, and sometimes only a blank placeholder).
var _art_fetched := {}

## Games whose pictures were found by the game's name: appid -> the Steam app that lent them (kept between runs).
var _borrowed: Dictionary = {}
var _borrowed_loaded := false

func _borrowed_map() -> Dictionary:
	if not _borrowed_loaded:
		_borrowed_loaded = true
		var d = JSON.parse_string(FileAccess.get_file_as_string("user://art/borrowed.json"))
		if d is Dictionary:
			_borrowed = d
	return _borrowed

func _save_borrowed() -> void:
	DirAccess.make_dir_recursive_absolute("user://art")
	var f := FileAccess.open("user://art/borrowed.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_borrowed))

## True when the game has a real tall cover somewhere (not a blank, wide or tiny placeholder).
func _real_cover(appid: String) -> bool:
	for p in ["user://art/%s_library_600x900.jpg" % appid, _find_local_art(appid, "library_600x900")]:
		if str(p) != "" and FileAccess.file_exists(str(p)):
			var img := Image.load_from_file(str(p))
			if image_cover_ok(img):
				return true
	return false

## The store names a game may be listed under: its own, then without edition words, without demo / teaser / beta words and
## subtitles, and without "biohazard" (RESIDENT EVIL 7 biohazard Demo -> RESIDENT EVIL 7 biohazard -> RESIDENT EVIL 7).
static func _name_variants(title: String) -> Array:
	var out: Array = []
	var t: String = title.strip_edges()
	if t.to_lower().ends_with(".exe"):
		t = t.left(t.length() - 4).strip_edges()  # a game added by its file name: "re7.exe"
	var c: String = StoreLookup._clean_title(t)
	var re := RegEx.new()
	re.compile("(?i)\\b(demo|teaser|trial|beta|benchmark|playtest|prologue|test|free)\\b|beginning hour")
	var d: String = re.sub(c, " ", true)
	while d.contains("  "):
		d = d.replace("  ", " ")
	d = d.strip_edges().trim_suffix(":").trim_suffix("-").strip_edges()
	var re2 := RegEx.new()
	re2.compile("(?i)\\bbio ?hazard\\b")
	var e: String = re2.sub(d, " ", true)
	while e.contains("  "):
		e = e.replace("  ", " ")
	e = e.strip_edges()
	var sub := d
	for sep in [":", " - "]:
		if sub.contains(sep):
			sub = sub.get_slice(sep, 0).strip_edges()
	var short := RegEx.new()
	short.compile("(?i)^re[ _-]?(\\d)( ?(r|remake|demo))?$")
	var sm := short.search(t)
	var spelled: Array = []
	if sm != null:
		spelled = ["Resident Evil " + sm.get_string(1), "RESIDENT EVIL %s biohazard" % sm.get_string(1)]  # "RE7" is not what the store calls it
	for v in [t, c, d, e, sub] + spelled:
		if str(v).length() >= 3 and not out.has(v):
			out.append(v)
	return out

func _game_title_for_art(appid: String) -> String:
	for g in games:
		if str(g["id"]) == appid:
			return str(g.get("orig_title", g["title"]))
	if library != null:
		for g in library._shown:
			if str(g.get("id", "")) == appid:
				return str(g.get("orig_title", g.get("title", "")))
	return ""

func prefetch_art(appid: String) -> void:
	if not appid.is_valid_int() or int(appid) > 0x7FFFFFFF:
		return
	# -1: done. Otherwise the time (ms) before which it is not tried again: a failed try (no network, the store down)
	# is repeated a few minutes later instead of never.
	if _art_fetched.has(appid) and (int(_art_fetched[appid]) == -1 or Time.get_ticks_msec() < int(_art_fetched[appid])):
		return
	_art_fetched[appid] = Time.get_ticks_msec() + 600000  # while this runs
	var got := false
	var assets := {}  # newer games keep their pictures under a hashed folder: Steam's store data says where
	var asked := false
	var keys := {"library_600x900": "library_capsule", "library_hero": "library_hero", "logo": "library_logo", "header": "header"}
	for k in [["library_600x900", "jpg"], ["library_hero", "jpg"], ["logo", "png"], ["header", "jpg"]]:
		var cached := "user://art/%s_%s.%s" % [appid, k[0], k[1]]
		if FileAccess.file_exists(cached):
			continue
		if await store._fetch_to(CDN % [appid, k[0], k[1]], cached):
			got = true
			continue
		if not asked:
			asked = true
			assets = await store._store_assets(appid)
		var url := str(assets.get(keys[k[0]], ""))
		if url != "" and await store._fetch_to(url, cached):
			got = true
	# Still no real cover (a demo, a test build, a game Steam keeps no library art for, or only a blank placeholder):
	# the store game with the same name lends its pictures.
	if not _real_cover(appid):
		var title := _game_title_for_art(appid)
		var other := ""
		var tried: Array = []
		if title != "":
			tried = _name_variants(title)
			for v in tried:
				other = await store._store_find(str(v))
				if other != "":
					break
		if other != "" and other != appid:
			var lent := false
			for k in [["library_600x900", "jpg"], ["library_hero", "jpg"], ["logo", "png"], ["header", "jpg"]]:
				var cached2 := "user://art/%s_%s.%s" % [appid, k[0], k[1]]
				var fresh := cached2 + ".new"
				if await store._fetch_to(CDN % [other, k[0], k[1]], fresh):
					if k[0] == "library_600x900" and not image_cover_ok(Image.load_from_file(fresh)):
						DirAccess.remove_absolute(fresh)
						continue
					DirAccess.remove_absolute(cached2)
					DirAccess.rename_absolute(fresh, cached2)
					lent = true
			if lent:
				_borrowed_map()[appid] = other
				_save_borrowed()
				_art_path_memo.clear()
				got = true
				_install_log("art: %s had no real cover, borrowed the pictures of Steam app %s by name" % [title, other])
		if not _real_cover(appid):
			_install_log("art: no cover found for %s (%s) by name (tried: %s)" % [appid, title, ", ".join(PackedStringArray(tried))])
	_art_fetched[appid] = -1 if _real_cover(appid) else Time.get_ticks_msec() + 180000
	if got:
		_art_path_memo.clear()
		_art_cache.clear()
		_art_order.clear()
		_logo_cache.clear()
		_build_row()
		_select(clampi(selected, 0, tiles.size() - 1), false)
		if channels != null:
			if channels.has_method("forget_art"):
				channels.forget_art(appid)
			channels.rebuild()
		if library != null and library.has_method("forget_art"):
			library.forget_art(appid)

func _dl_poll(delta: float) -> void:
	_dl_acc += delta
	if _dl_acc < 2.0 or _dl_task >= 0:
		return
	_dl_acc = 0.0
	_dl_task = _work(func() -> void:
		var list := download_entries()
		_dl_arrived.call_deferred(list))

func _dl_arrived(list: Array) -> void:
	_work_done(_dl_task)
	_dl_task = -1
	var now := {}
	for e in list:
		now[str(e["id"])] = e
	var finished := false
	for id in _dl:
		if not now.has(id) and not bool(_dl[id].get("installed", false)):
			finished = true  # a new game is ready to play
	var added := false
	for id in now:
		if not bool(now[id].get("installed", false)):
			prefetch_art(id)
		if not _dl.has(id) and not _dl_seen.has(id):
			_dl_seen[id] = true  # once per game: Steam's own tools (Proton and such) never get a tile
			added = true
	_dl = now
	if finished or (added and not _dl_ids_known()):
		refresh_games(false)  # (also picks up a game Steam only just started, so its tile is there to fill)
	_dl_apply()

## True when every game being downloaded is already in the games list (its tile may still be hidden from Home).
func _dl_ids_known() -> bool:
	var have := {}
	for g in games:
		have[str(g["id"])] = true
	for id in _dl:
		if not have.has(id):
			return false
	return true

## Puts the progress over each downloading tile, updates it, and takes it off tiles that are done.
func _dl_apply() -> void:
	for j in tiles.size():
		var holder: Control = tiles[j]
		var gi: int = tile_game[j] if j < tile_game.size() else -1
		var id := str(games[gi]["id"]) if gi >= 0 else ""
		var ov: Control = holder.get_node_or_null("Downloading")
		if id != "" and _dl.has(id):
			if ov == null:
				ov = preload("res://dl_overlay.gd").new()
				ov.name = "Downloading"
				ov.radius = float(Themes.r(16))
				ov.pct = float(_dl[id]["pct"])
				Rounded.apply(ov, TILE, 16.0)
				holder.add_child(ov)
				holder.move_child(ov, mini(2, holder.get_child_count() - 1))  # over the tile, under the shine
				ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ov.pct = float(_dl[id]["pct"])
			ov.state = str(_dl[id]["state"])
		elif ov != null:
			ov.queue_free()

## Games Steam has started but not finished: [{id, title, pct (0..1), state "Downloading" / "Queued" / "Paused"}].
func download_entries() -> Array:
	var out: Array = []
	var running := _steam_running()
	for lib in _steam_libs():
		var dir := DirAccess.open(str(lib) + "/steamapps")
		if dir == null:
			continue
		for f in dir.get_files():
			if not (f.begins_with("appmanifest_") and f.ends_with(".acf")):
				continue
			var txt := FileAccess.get_file_as_string(str(lib) + "/steamapps/" + f)
			var flags := _acf_value(txt, "StateFlags").to_int()
			var total := _acf_value(txt, "BytesToDownload").to_float()
			var done := _acf_value(txt, "BytesDownloaded").to_float()
			var incomplete := (flags & 4) == 0 or ((flags & 2) != 0 and total > 0.0 and done < total)
			if not incomplete or (flags & 64) != 0:
				continue
			var id := f.trim_prefix("appmanifest_").trim_suffix(".acf")
			if not id.is_valid_int():
				continue
			var state := "Paused"
			if running:
				state = "Downloading" if (flags & (256 | 1024 | 1048576 | 2097152 | 4194304)) != 0 else "Queued"
			if (flags & 4) != 0:
				# An update of an installed game: it happens by itself (_auto_update_tick). Shown while it downloads, and
				# while Tephra has Steam open to update, so you can see what is going on; not just because one is waiting.
				if state == "Downloading":
					state = "Updating"
				elif running and _au_active:
					state = "Update starting"
				else:
					continue
			out.append({"id": id, "title": _acf_value(txt, "name"), "pct": clampf(done / total, 0.0, 1.0) if total > 0.0 else 0.0, "state": state, "lib": str(lib), "installed": (flags & 4) != 0})
	out.sort_custom(func(a, b): return a["state"] == "Downloading" and b["state"] != "Downloading")
	return out

func _on_download_action(action: String, id: String) -> void:
	match action:
		"pause_all":
			await _dl_close_steam()
			notify("Downloads paused. Steam is closed.", "info")
		"resume_all":
			for d in download_entries():
				_dl_start(str(d["id"]), str(d["title"]))
		"start":
			for d in download_entries():
				if str(d["id"]) == id:
					_dl_start(id, str(d["title"]))
		"stop":
			await _dl_stop(id)

## While Steam is only downloading, the PS button must stay Tephra's. Steam still reads the controller and opens Big
## Picture on PS (with its intro sound), so for a few seconds Steam's sound is muted and Big Picture is closed again.
const HUSH_STEAM := """
ids() { pactl list sink-inputs 2>/dev/null | awk '/^Sink Input #/{id=substr($3,2)} /application.process.binary = "(steam|steamwebhelper)"/{print id}'; }
for i in $(seq 1 20); do
  for id in $(ids); do pactl set-sink-input-mute "$id" 1; done
  [ "$i" = 3 ] || [ "$i" = 8 ] && steam steam://close/bigpicture >/dev/null 2>&1 &
  sleep 0.3
done
sleep 2
for id in $(ids); do pactl set-sink-input-mute "$id" 0; done
"""

func _hush_steam() -> void:
	if _steam_virtual:
		OS.create_process("env", ["-u", "WAYLAND_DISPLAY", "DISPLAY=" + VDISPLAY, "bash", "-c", HUSH_STEAM])
	else:
		OS.create_process("bash", ["-c", HUSH_STEAM])

func _dl_close_steam() -> void:
	if launching or _any_game_running():
		notify("A game is running, so Steam can't be closed.", "info")
		return
	library._installing.clear()
	_steam_stopping = true
	_steam_cmd(["-shutdown"])
	var waited := 0.0
	while _steam_running() and waited < 40.0:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	_steam_stopping = false

func _dl_start(id: String, title: String) -> void:
	if launching:
		notify("Close the game first to download.", "info")
		return
	if library._installing.has(id):
		return
	if _is_installed_id(id):
		_run_updates([id])  # an update: steam://install does nothing for an installed game
		return
	library._installing[id] = {"title": title, "started": Time.get_ticks_msec(), "seen": false}
	var hidden: bool = await steam_install_hidden(id)
	if not hidden:
		steam_rule(false)
		steam_open("steam://install/" + id, true)
	steam_confirm_install(id)

## Removes a half-downloaded game: Steam is closed first (it would write the files back), then the manifest and the
## partial download go. Games that are fully installed are never touched.
func _dl_stop(id: String) -> void:
	if not id.is_valid_int():
		return
	var entry := {}
	for d in download_entries():
		if str(d["id"]) == id:
			entry = d
	if entry.is_empty():
		return
	if bool(entry["installed"]):
		notify("%s is installed already, this is an update. Only new downloads can be stopped." % str(entry["title"]), "info")
		return
	await _dl_close_steam()
	if _steam_running():
		return
	var base := str(entry["lib"]) + "/steamapps"
	DirAccess.remove_absolute(base + "/appmanifest_" + id + ".acf")
	OS.execute("rm", ["-rf", base + "/downloading/" + id, base + "/temp/" + id])
	library._installing.erase(id)
	notify("Download stopped: " + str(entry["title"]), "info")
	if is_instance_valid(library) and library.is_open:
		library._rebuild()

func _home_selected() -> bool:
	return selected == 0 and channels == null

func _library_selected() -> bool:
	return selected == tiles.size() - 1 and tiles.size() > 1 and channels == null

## Index into games for the selected tile, or -1 for Home/Library.
func _game_selected() -> int:
	if channels != null:
		return channels.selected_gi()
	return tile_game[selected] if selected >= 0 and selected < tile_game.size() else -1

func _new_tile(color: Color) -> Panel:
	var tile := Panel.new()
	tile.custom_minimum_size = TILE
	tile.pivot_offset = TILE / 2
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(Themes.r(16))
	if Themes.id() == "frutiger":
		# Glass: a bright rim and a soft aqua glow around each tile.
		sb.border_color = Color(1, 1, 1, 0.9)
		sb.set_border_width_all(3)
		sb.shadow_color = Color(0.1, 0.45, 0.8, 0.28)
		sb.shadow_size = 14
		sb.shadow_offset = Vector2(0, 5)
	tile.add_theme_stylebox_override("panel", sb)
	if Themes.id() == "gothic":
		Rounded.apply(tile, TILE, 16.0)  # the tile itself is burnt at the edges too, under its picture
	return tile

func _sheen() -> TextureRect:
	# A glossy look: a little light at the top of the tile, a little darkness at the bottom.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.0), Color(0, 0, 0, 0.28)])
	if Themes.id() == "frutiger":
		# A glass reflection: bright across the top half with a crisp edge, clear below.
		g.offsets = PackedFloat32Array([0.0, 0.47, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.62), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.0), Color(0.6, 0.9, 1.0, 0.18)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _finish_tile(tile: Panel) -> void:
	var sheen := _sheen()
	Rounded.apply(sheen, TILE, 16.0)
	tile.add_child(sheen)
	sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.draw_center = false
	fsb.border_color = Color(1, 1, 1, 0.0)
	fsb.set_corner_radius_all(Themes.r(16))
	frame.add_theme_stylebox_override("panel", fsb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Rounded.rough_frame(frame, TILE)
	# The holder lets the shadow and the shine draw outside the tile's clipped edge.
	var holder := Control.new()
	holder.custom_minimum_size = TILE
	holder.pivot_offset = TILE / 2
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow := Panel.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0, 0, 0, 0.5)
	ssb.set_corner_radius_all(Themes.r(16))
	ssb.shadow_size = 34
	ssb.shadow_color = Color(0, 0, 0, 0.6)
	ssb.shadow_offset = Vector2(0, 18)
	shadow.add_theme_stylebox_override("panel", ssb)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.modulate.a = 0.3
	holder.add_child(shadow)
	shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(tile)
	tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shine = preload("res://tile_shine.gd").new()
	holder.add_child(shine)
	shine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(holder)
	tiles.append(holder)
	frames.append(fsb)
	shadows.append(shadow)
	shines.append(shine)

func _make_icon_tile(tex: Texture2D, color: Color) -> void:
	var tile := _new_tile(color)
	var icon := TextureRect.new()
	icon.texture = tex
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	tile.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_finish_tile(tile)

func _make_game_tile(g: Dictionary) -> void:
	# A game with no cover gets a tidy card: a colour picked from its name, a big faint
	# initial, and the title set neatly at the bottom.
	var hue := float(hash(str(g["title"])) % 360) / 360.0
	var tile := _new_tile(Color.from_hsv(hue, 0.35, 0.30))
	var cover := TextureRect.new()
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	Rounded.apply(cover, TILE, 16.0)
	cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tile.add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var banner := TextureRect.new()
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.visible = false
	tile.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 40
	banner.offset_bottom = 40 + TILE.x * 215.0 / 460.0
	var initial := _label(str(g["title"]).substr(0, 1).to_upper(), 170, Themes.ink(0.13))
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.visible = false
	tile.add_child(initial)
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial.offset_top = -30
	var name_lbl := _label(g["title"], 24, TEXT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_lbl.max_lines_visible = 4
	name_lbl.add_theme_constant_override("outline_size", 6)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	name_lbl.visible = false
	tile.add_child(name_lbl)
	name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_lbl.offset_left = 16
	name_lbl.offset_right = -16
	name_lbl.offset_bottom = -22
	var id: String = g["id"]
	var no_cover := func() -> void:
		cover.texture = null
		prefetch_art(id)  # no real cover: its pictures are fetched, or found by the game's name (the tile refills itself)
		_load_art(id, "header", banner, "jpg", func():
			banner.visible = true
			name_lbl.visible = true,
		func():
			initial.visible = true
			name_lbl.visible = true)
	# A real cover shows no name. Steam sometimes caches a blank, wide or tiny placeholder
	# as the "cover": that counts as no cover, so the name is shown.
	var cover_done := func() -> void:
		if not cover_ok(cover.texture):
			no_cover.call()
	_load_art(id, "library_600x900", cover, "jpg", cover_done, no_cover)
	_finish_tile(tile)

## True if a texture looks like real tall cover art (right shape, big enough, not a flat colour).
func cover_ok(tex: Texture2D) -> bool:
	if tex == null:
		return false
	return image_cover_ok(tex.get_image())

## The same check on a decoded picture.
static func image_cover_ok(img: Image) -> bool:
	if img == null or img.is_empty():
		return false
	var w := img.get_width()
	var h := img.get_height()
	if w < 200 or h < 300:
		return false
	var aspect := float(w) / float(h)
	if aspect < 0.55 or aspect > 0.8:
		return false
	img = img.duplicate()
	img.resize(12, 18, Image.INTERPOLATE_NEAREST)
	var sum := 0.0
	var vals: Array = []
	for y in 18:
		for x in 12:
			var c := img.get_pixel(x, y)
			var v := (c.r + c.g + c.b) / 3.0
			vals.append(v)
			sum += v
	var mean := sum / vals.size()
	var var_sum := 0.0
	for v in vals:
		var_sum += (v - mean) * (v - mean)
	return sqrt(var_sum / vals.size()) > 0.02

# ---------- Cover art and backgrounds ----------
# Loads art from Steam's cache, Tephra's cache, or Steam's servers (in that order).
# "done" runs once the texture is set, "fail" if there is no such art. Each target
# remembers which art it wants last, so a slow download for a game you've already
# scrolled past is ignored.
func _load_art(appid: String, kind: String, target: TextureRect, ext := "jpg", done := Callable(), fail := Callable()) -> void:
	var want := appid + "/" + kind
	target.set_meta("want", want)
	var path := _find_local_art(appid, kind, ext)
	var cached := "user://art/%s_%s.%s" % [appid, kind, ext]
	if FileAccess.file_exists(cached) and (path == "" or _dl.has(appid)):
		path = cached  # a game still installing: Steam's own copy may be a blank placeholder
	if path != "":
		# Decoding a big image on the main thread is what made scrolling covers stutter: it happens on a
		# worker thread now, and pictures already seen come straight from a small memory cache.
		_tex_async(path, func(tex: Texture2D) -> void:
			if not is_instance_valid(target):
				return
			if tex != null:
				if target.get_meta("want", "") != want:
					return  # the player has moved on to another game
				target.texture = tex
				if done.is_valid():
					done.call()
			else:
				_download_art(appid, kind, target, ext, done, fail, want, cached))
		return
	_download_art(appid, kind, target, ext, done, fail, want, cached)

## The tall cover for a layout that has no wide fallback (Miami, XMB, Profile): a blank or wrong-shaped placeholder
## counts as no cover (the texture is cleared and `fail` runs), and a game whose art Steam keeps under a hashed
## folder gets its pictures fetched from the store data (once), after which the layouts refresh themselves.
func load_cover(id: String, target: TextureRect, done := Callable(), fail := Callable()) -> void:
	var miss := func() -> void:
		if not is_instance_valid(target):
			return
		target.texture = null
		prefetch_art(id)
		if fail.is_valid():
			fail.call()
	_load_art(id, "library_600x900", target, "jpg", func() -> void:
		if not is_instance_valid(target):
			return
		if not cover_ok(target.texture):
			miss.call()
		elif done.is_valid():
			done.call(), miss)

func _download_art(appid: String, kind: String, target: TextureRect, ext: String, done: Callable, fail: Callable, want: String, cached: String) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.download_file = cached
	req.request_completed.connect(_on_art_done.bind(req, cached, target, want, done, fail))
	if req.request(CDN % [appid, kind, ext]) != OK:
		req.queue_free()
		if fail.is_valid():
			fail.call()

func _on_art_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, req: HTTPRequest, path: String, target: TextureRect, want: String, done: Callable, fail: Callable) -> void:
	req.queue_free()
	if not is_instance_valid(target):
		return
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if not ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		prefetch_art(want.get_slice("/", 0))  # newer games: the store data knows where Steam keeps their pictures (once per game)
		if target.get_meta("want", "") == want and fail.is_valid():
			fail.call()
		return
	_tex_async(path, func(tex: Texture2D) -> void:
		if not is_instance_valid(target):
			return
		if tex == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if target.get_meta("want", "") == want and fail.is_valid():
				fail.call()
			return
		if target.get_meta("want", "") != want:
			return
		target.texture = tex
		if done.is_valid():
			done.call())

# Pictures decoded so far (newest last), so scrolling back and forth costs nothing.
var _art_cache := {}
var _art_order: Array = []
const ART_CACHE_MAX := 40
var _logo_cache := {}  # path -> texture: every game's logo stays in memory (they are small)
# Decodes waiting on a worker thread: path -> callbacks to run when it is ready.
var _art_pending := {}

func _art_remember(path: String, tex: Texture2D) -> void:
	_art_cache[path] = tex
	_art_order.erase(path)
	_art_order.append(path)
	while _art_order.size() > ART_CACHE_MAX:
		_art_cache.erase(_art_order.pop_front())

## Calls cb(texture) (null if the file is missing/bad) - at once if cached, else after a worker thread decoded it.
func _tex_async(path: String, cb: Callable) -> void:
	if _logo_cache.has(path):
		cb.call(_logo_cache[path])
		return
	if _art_cache.has(path):
		_art_order.erase(path)
		_art_order.append(path)
		cb.call(_art_cache[path])
		return
	if _art_pending.has(path):
		_art_pending[path].append(cb)
		return
	_art_pending[path] = [cb]
	var box := {}
	box["id"] = _work(func() -> void:
		var img: Image = null
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
			if img != null and not img.is_empty():
				if path.contains("600x900") or path.contains("library_capsule"):
					img = CoverTrim.trim(img)  # covers with a frame drawn in (like Portal's) lose it
				if Themes.id() == "temple" and (path.contains("600x900") or path.contains("library_capsule")):
					img = Ega16.convert(img, 110)  # Temple: sixteen colours, chunky pixels
				elif Themes.id() == "temple" and (path.contains("library_hero") or path.contains("header")):
					img = Ega16.convert(img, 200)
				if path.contains("library_hero") and img.get_width() > 2048:
					img.resize(2048, int(round(2048.0 * img.get_height() / img.get_width())), Image.INTERPOLATE_BILINEAR)  # a background: no need for 4K, and it uploads 3x faster
				img.generate_mipmaps()
			else:
				img = null
		box["img"] = img
		_art_decoded.call_deferred(path, box))

func _art_decoded(path: String, box: Dictionary) -> void:
	_work_done(int(box["id"]))
	var img: Image = box.get("img", null)
	var tex: Texture2D = null
	if img != null:
		tex = ImageTexture.create_from_image(img)
		_art_remember(path, tex)
	var cbs: Array = _art_pending.get(path, [])
	_art_pending.erase(path)
	for cb in cbs:
		cb.call(tex)

## Warms the cache for the covers/heroes next to the selected game so scrolling shows them at once.
var _prefetch_ticket := 0

## Only once the cursor has rested for a moment, and only the next heroes: while you are flicking through games every step
## used to look up and decode pictures for four neighbours, and that is what dragged the frame rate down.
func _prefetch_around(i: int) -> void:
	_prefetch_ticket += 1
	var ticket := _prefetch_ticket
	await get_tree().create_timer(0.3).timeout
	if ticket != _prefetch_ticket:
		return
	for j in [i - 1, i + 1]:
		if j < 0 or j >= games.size():
			continue
		var p := _find_local_art(games[j]["id"], "library_hero")
		if p != "":
			_tex_async(p, func(_t): pass)

var _art_path_memo := {}  # "appid/kind/ext" -> where the picture is (looking through Steam's folders is slow, so only once)

func _find_local_art(appid: String, kind: String, ext := "jpg") -> String:
	# A game Steam has no real pictures for (a demo, a test build, a blank placeholder) uses the ones Tephra found by
	# the game's name: every layout and menu asks here, so they all show the same cover.
	if _borrowed_map().has(appid):
		var lent := "user://art/%s_%s.%s" % [appid, kind, ext]
		if FileAccess.file_exists(lent):
			return lent
	var key := appid + "/" + kind + "/" + ext
	if _art_path_memo.has(key) and FileAccess.file_exists(str(_art_path_memo[key])):
		return _art_path_memo[key]
	var cache := steam_dir + "/appcache/librarycache"
	var flat := "%s/%s_%s.%s" % [cache, appid, kind, ext]
	var found := flat if FileAccess.file_exists(flat) else _search_dir(cache + "/" + appid, kind)
	if found == "" and appid.is_valid_int() and int(appid) > 0x7FFFFFFF:
		found = _grid_art(appid, kind)
	if found != "":
		_art_path_memo[key] = found
	return found

## Custom pictures for non-Steam games (the PS2 covers): userdata/<you>/config/grid/<id>p.png (tall), _hero, _logo, <id>.png (wide)
func _grid_art(appid: String, kind: String) -> String:
	var udir := DirAccess.open(steam_dir + "/userdata")
	if udir == null:
		return ""
	var suffix := {"library_600x900": "p", "library_hero": "_hero", "library_logo": "_logo", "logo": "_logo"}.get(kind, "") as String
	var original := ps2_art_original(appid)
	if original and suffix == "_logo":
		return ""  # the original look: the game's name, not the remake's logo
	if kind == "header" and not original:
		for u1 in udir.get_directories():  # "Art: Remake" on wide tiles (Channels): the remake's store backdrop
			var hp := "%s/userdata/%s/config/grid/%s_hero.jpg" % [steam_dir, u1, appid]
			if FileAccess.file_exists(hp):
				return hp
	if kind == "library_600x900" and not original:
		for u0 in udir.get_directories():  # "Art: Remake": the remake's own cover, borrowed from its store page
			var rp := "%s/userdata/%s/config/grid/%sp_remake.jpg" % [steam_dir, u0, appid]
			if FileAccess.file_exists(rp):
				return rp
	for u in udir.get_directories():
		# A real backdrop (.jpg, borrowed from the store) beats one made from the cover (.png), unless the original look is chosen.
		for ext in (["jpg", "png"] if kind == "library_hero" and not original else ["png", "jpg"]):
			var p := "%s/userdata/%s/config/grid/%s%s.%s" % [steam_dir, u, appid, suffix, ext]
			if FileAccess.file_exists(p):
				return p
	return ""

## PS2 games whose name is also on Steam can show the remake's backdrop and logo (the default) or the original
## look made from the PS2 box. Chosen per game on its page.
func ps2_art_original(appid: String) -> bool:
	return Settings.get_value("ps2_art_original", []).has(appid)

func ps2_has_remake_art(appid: String) -> bool:
	var cfg := Ps2Games._config_dir(steam_dir)
	return cfg != "" and FileAccess.file_exists("%s/grid/%s_hero.jpg" % [cfg, appid])

func set_ps2_art_original(appid: String, on: bool) -> void:
	var list: Array = Settings.get_value("ps2_art_original", []).duplicate()
	list.erase(appid)
	if on:
		list.append(appid)
	Settings.set_value("ps2_art_original", list)
	_art_path_memo.clear()
	_art_cache.clear()
	_art_order.clear()
	_logo_cache.clear()
	_prewarm_logos()
	# The Home row's tiles keep the picture they were made with: make them again with the new cover.
	var keep := selected
	_build_row()
	_select(clampi(keep, 0, tiles.size() - 1), false)
	if channels != null:
		if channels.has_method("forget_art"):
			channels.forget_art(appid)
		channels.rebuild()
	if library != null and library.has_method("forget_art"):
		library.forget_art(appid)

func _search_dir(path: String, kind: String) -> String:
	var dir := DirAccess.open(path)
	if dir == null:
		return ""
	for f in dir.get_files():
		if f.begins_with(kind):
			return path + "/" + f
	for d in dir.get_directories():
		var found := _search_dir(path + "/" + d, kind)
		if found != "":
			return found
	return ""

func _tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	if path.contains("600x900") or path.contains("library_capsule"):
		img = CoverTrim.trim(img)
		if Themes.id() == "temple":
			img = Ega16.convert(img, 110)
	img.generate_mipmaps()  # smooth when a big cover is drawn small (no jagged, shimmering art)
	return ImageTexture.create_from_image(img)

# ---------- Selecting ----------
func _select(i: int, animate := true) -> void:
	var before := selected
	selected = clampi(i, 0, tiles.size() - 1)
	if channels != null:
		_refresh_all_hints()
		return  # the Channels Home has its own focus (channels.gd); the row is hidden
	if animate and selected != before:
		Haptics.select()
	for j in tiles.size():
		var on := j == selected
		if animate and not on and j != before:
			continue  # untouched tiles are already in their resting look: no need to start two more tweens on each of them every step
		var fsb: StyleBoxFlat = frames[j]
		fsb.set_border_width_all(0)
		shines[j].active = on
		var sh: Panel = shadows[j]
		if Themes.id() == "volcanic":  # selected tile glows like hot metal
			var vsb := sh.get_theme_stylebox("panel") as StyleBoxFlat
			if vsb != null:
				vsb.shadow_color = Color(1.0, 0.38, 0.06, 0.75) if on else Color(0, 0, 0, 0.6)
				vsb.shadow_offset = Vector2.ZERO if on else Vector2(0, 18)
				vsb.shadow_size = 46 if on else 34
		var target := Vector2.ONE * (1.1 if on else 1.0)
		if animate:
			Motion.fade_to(sh, 1.0 if on else 0.3, 0.2)
			Motion.scale_to(tiles[j], target.x, 0.15)
		else:
			sh.modulate.a = 1.0 if on else 0.3
			tiles[j].scale = target
	_smooth_scroll.call_deferred(selected, animate)
	_refresh_hints_if_changed()
	title_label.visible = true
	title_label.modulate.a = 1.0
	logo_rect.visible = false
	logo_rect.texture = null
	logo_rect.set_meta("want", "")  # ignore any logo still downloading
	_art_ticket += 1
	hero.texture = null
	hero.set_meta("want", "")
	var gi := _game_selected()
	var shade_target := 0.0 if gi < 0 else 1.0
	if not animate or shade_target != _last_shade_target:  # stepping from game to game: the fades are already where they need to be
		_last_shade_target = shade_target
		_fade_bg(gi < 0, animate)
		for sh in [shade_a, shade_b]:
			if animate:
				create_tween().tween_property(sh, "modulate:a", shade_target, Motion.dur(0.4))
			else:
				sh.modulate.a = shade_target
	if gi < 0:
		if _home_selected():
			_queue_details("recent", -1, animate)
		else:
			_cancel_details()
			details.hide_all()
		if _home_selected():
			title_label.text = "Home"
		else:
			title_label.text = "Library"
		return
	var g: Dictionary = games[gi]
	title_label.text = g["title"]
	_queue_details("game", gi, animate)
	_load_logo_now(gi)
	if not animate:
		_load_selected_art(gi)
		return
	# Big artwork is only loaded once the cursor rests for a moment, so fast stepping stays cheap.
	_art_ticket += 1
	var at := _art_ticket
	await get_tree().create_timer(0.08).timeout
	if at != _art_ticket or _game_selected() != gi:
		return
	_load_selected_art(gi)
	hero.modulate.a = 0.0
	create_tween().tween_property(hero, "modulate:a", 1.0, Motion.dur(0.4))

var _last_shade_target := -1.0
var _art_ticket := 0

## The logo is asked for at once (not after the rest pause like the big backdrop). Logos are kept in memory, so it is
## usually there in the same frame; the plain name only shows when the game has no logo, or it hasn't come after 0.6 s.
var _logo_ticket := 0

func _load_logo_now(gi: int) -> void:
	_logo_ticket += 1
	var lt := _logo_ticket
	title_label.modulate.a = 0.0
	var gid := str(games[gi]["id"])
	_load_art(gid, "logo", logo_rect, "png", _show_logo, func() -> void:
		if lt == _logo_ticket:
			_name_instead())
	await get_tree().create_timer(0.6).timeout
	if lt == _logo_ticket and not logo_rect.visible:
		_name_instead()

func _name_instead() -> void:
	if logo_rect.visible or title_label.modulate.a > 0.0:
		return
	create_tween().tween_property(title_label, "modulate:a", 1.0, Motion.dur(0.25))

## Every game's logo, decoded into memory a little after start, so moving along the row never waits on one.
func _prewarm_logos() -> void:
	for g in games:
		var path := _find_local_art(str(g["id"]), "logo", "png")
		if path == "" and FileAccess.file_exists("user://art/%s_logo.png" % g["id"]):
			path = "user://art/%s_logo.png" % g["id"]
		if path != "" and not _logo_cache.has(path):
			_tex_async(path, func(t: Texture2D) -> void:
				if t != null:
					_logo_cache[path] = t)
			await get_tree().create_timer(0.05).timeout

func _load_selected_art(gi: int) -> void:
	var g: Dictionary = games[gi]
	var am := Time.get_ticks_usec()
	_load_art(g["id"], "library_hero", hero)
	_prefetch_around(gi)
	preload("res://frame_probe.gd").mark("select: artwork", am)

# ---------- Details below the row (achievements, stats, Today) ----------
# Building a game's details page means reading its achievement files and creating a row for every
# achievement. That took 80 to 130 ms, and it used to happen on every single step of the cursor, which
# is what made scrolling through games stutter. The page is only looked at after pressing Down, so it is
# now built once the cursor has rested on a tile for a moment (or at once when Down is pressed).
var _details_job := ""      # what is waiting to be built: "game", "recent", or "" for nothing
var _details_gi := -1
var _details_ticket := 0    # each new selection cancels the one before it

func _queue_details(job: String, gi: int, animate: bool) -> void:
	_details_job = job
	_details_gi = gi
	_details_ticket += 1
	var ticket := _details_ticket
	if not animate:
		_flush_details()   # the very first selection (no scrolling yet): build it straight away
		return
	await get_tree().create_timer(0.22).timeout
	if ticket == _details_ticket:
		_flush_details()

func _cancel_details() -> void:
	_details_job = ""
	_details_ticket += 1

## Builds the waiting details page now, if there is one.
func _flush_details() -> void:
	var job := _details_job
	_details_job = ""
	var dm := Time.get_ticks_usec()
	if job == "game" and _details_gi >= 0 and _details_gi < games.size():
		details.show_game(games[_details_gi])
	elif job == "recent":
		details.show_recent()
	if job != "":
		preload("res://frame_probe.gd").mark("details build", dm)

# Tephra's moving background shows behind the Home and Library tiles.
func _fade_bg(on: bool, animate: bool) -> void:
	var target := 1.0 if on else 0.0
	if _bg_tween != null:
		_bg_tween.kill()
	# Hidden once faded out: a see-through background still cost a full-screen draw on every frame behind the game art.
	if on:
		bg_anim.visible = true
	if animate:
		_bg_tween = create_tween()
		_bg_tween.tween_property(bg_anim, "modulate:a", target, Motion.dur(0.4))
		if not on:
			_bg_tween.tween_callback(func() -> void: bg_anim.visible = false)
	else:
		bg_anim.modulate.a = target
		bg_anim.visible = on

var _bg_tween: Tween

# Glides the row so the selected tile is fully on screen (instead of snapping).
func _smooth_scroll(index: int, animate: bool) -> void:
	if index < 0 or index >= tiles.size():
		return
	var tile: Control = tiles[index]
	var x := tile.position.x + 30.0  # 30 = the row's padding
	var edge := 50.0  # room for the bigger selected tile
	var view := scroll.size.x
	var target := float(scroll.scroll_horizontal)
	if x - edge < target:
		target = x - edge
	elif x + TILE.x + edge > target + view:
		target = x + TILE.x + edge - view
	else:
		return
	target = maxf(target, 0.0)
	if _scroll_tween != null:
		_scroll_tween.kill()
	if not animate:
		scroll.scroll_horizontal = int(target)
		return
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(scroll, "scroll_horizontal", int(target), Motion.dur(0.22)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Swaps the title text for the logo once it has loaded,
# scaled to fit LOGO_MAX and sitting on the bottom-left of the title area.
func _show_logo() -> void:
	var tex := logo_rect.texture
	if tex == null:
		return
	var s := tex.get_size()
	var k := minf(LOGO_MAX.x / s.x, LOGO_MAX.y / s.y)
	logo_rect.size = s * k
	logo_rect.position = Vector2(0, LOGO_MAX.y - logo_rect.size.y)
	title_label.visible = false
	logo_rect.visible = true
	logo_rect.modulate.a = 0.0
	create_tween().tween_property(logo_rect, "modulate:a", 1.0, Motion.dur(0.12))

# ---------- Top bar: Wi-Fi and profile ----------
func _poll_wifi() -> void:
	if _wifi_reading:
		return
	_wifi_reading = true
	_wifi_task = _work(_wifi_task_run)

func _wifi_task_run() -> void:
	var radio := []
	OS.execute("nmcli", ["-t", "-f", "WIFI", "radio"], radio)
	var list := []
	OS.execute("nmcli", ["-t", "-f", "ACTIVE,SIGNAL", "dev", "wifi"], list)
	var on := radio.size() > 0 and str(radio[0]).strip_edges() == "enabled"
	var sig := -1
	if list.size() > 0:
		for line in str(list[0]).split("\n"):
			if line.begins_with("yes:"):
				sig = line.get_slice(":", 1).to_int()
	_wifi_done.call_deferred(on, sig)

func _wifi_done(on: bool, sig: int) -> void:
	_work_done(_wifi_task)
	_wifi_reading = false
	_apply_wifi(on, sig)

## sig = signal 0-100, or -1 when not connected.
func _apply_wifi(on: bool, sig: int) -> void:
	var bars := 0
	if on and sig >= 0:
		bars = 1 if sig < 40 else (2 if sig < 70 else 3)
	wifi_icon.texture = Icons.texture("wifi%d%s" % [bars, on], Icons.svg_wifi(bars, on), 32)

# Name and picture: shown from the saved copy first, then refreshed from Steam.
func _load_profile() -> void:
	var sid := SteamAccount.steam_id(steam_dir)
	var saved := FileAccess.get_file_as_string("user://profile.json") if FileAccess.file_exists("user://profile.json") else ""
	var p = JSON.parse_string(saved) if saved != "" else null
	if p is Dictionary:
		profile_name.text = str(p.get("name", ""))
	if profile_name.text == "" and sid != "":
		profile_name.text = SteamAccount.persona_name(steam_dir, sid)
	var pic := "user://avatar.jpg"
	if not FileAccess.file_exists(pic) and sid != "":
		pic = SteamAccount.cached_avatar(steam_dir, sid)
	if pic != "":
		var t := _tex(pic)
		if t != null:
			avatar_rect.texture = t
	var key := SteamAccount.api_key()
	if key == "" or sid == "":
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_profile.bind(req))
	req.request(SUMMARY_URL % [key, sid])

func _on_profile(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary and d.get("response") is Dictionary):
		return
	var players = d["response"].get("players", [])
	if not (players is Array) or players.is_empty():
		return
	var pl: Dictionary = players[0]
	profile_name.text = str(pl.get("personaname", profile_name.text))
	var f := FileAccess.open("user://profile.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"name": profile_name.text, "since": int(pl.get("timecreated", 0))}))
	var url := str(pl.get("avatarfull", ""))
	if url == "":
		return
	var pic := HTTPRequest.new()
	add_child(pic)
	pic.download_file = "user://avatar_new.jpg"
	pic.request_completed.connect(func(r: int, c: int, _hh, _b):
		pic.queue_free()
		if r == HTTPRequest.RESULT_SUCCESS and c == 200:
			var t := _tex("user://avatar_new.jpg")
			if t != null:
				DirAccess.rename_absolute(ProjectSettings.globalize_path("user://avatar_new.jpg"), ProjectSettings.globalize_path("user://avatar.jpg"))
				avatar_rect.texture = t)
	pic.request(url)

# ---------- Friends (Today page) ----------
# Asks Steam for your friends list, then for what each one is doing. Needs your Steam web API key
# and a public friends list; if either is missing the Friends card stays hidden.
func _fetch_friends() -> void:
	var key := SteamAccount.api_key()
	var sid := SteamAccount.steam_id(steam_dir)
	if key == "" or sid == "" or launching:
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_friend_list.bind(req, key))
	req.request("https://api.steampowered.com/ISteamUser/GetFriendList/v1/?key=%s&steamid=%s&relationship=friend" % [key, sid])

func _on_friend_list(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, req: HTTPRequest, key: String) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary and d.get("friendslist") is Dictionary):
		return
	var ids: Array = []
	for f in d["friendslist"].get("friends", []):
		ids.append(str(f.get("steamid", "")))
	if ids.is_empty():
		return
	var req2 := HTTPRequest.new()
	add_child(req2)
	req2.request_completed.connect(_on_friend_status.bind(req2, ids.size()))
	req2.request(SUMMARY_URL % [key, ",".join(ids.slice(0, 100))])

func _on_friend_status(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, req: HTTPRequest, total: int) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary and d.get("response") is Dictionary):
		return
	var online := 0
	var playing: Array = []
	for p in d["response"].get("players", []):
		if int(p.get("personastate", 0)) > 0:
			online += 1
		if str(p.get("gameextrainfo", "")) != "":
			playing.append([str(p.get("personaname", "?")), str(p["gameextrainfo"])])
	if details != null:
		details.fill_friends({"ok": true, "online": online, "total": total, "playing": playing})

# ---------- Controllers ----------
func _guide_label() -> String:
	return "Home" if bool(Settings.get_value("guide_swap", false)) else "Control center"

# True while the controller icon in the top bar is on screen (so it does the flashing and
# no notification is needed).
func _top_bar_visible() -> bool:
	return not (launching or cc.is_open or library.is_open or profile_screen.is_open \
		or settings_screen.is_open or top_menu.is_open or setup_screen.is_open or in_details)

var alert_pill: PanelContainer
var alert_pill_icon: TextureRect
var alert_pill_label: Label
var alert_pill_style: StyleBoxFlat
var _pill_left := 0.0
var _pill_y := 76.0

func _make_alert_pill() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 97
	add_child(layer)
	alert_pill = PanelContainer.new()
	alert_pill_style = StyleBoxFlat.new()
	alert_pill_style.bg_color = Themes.c("panel")  # solid: the top bar must not show through
	alert_pill_style.set_corner_radius_all(Themes.r(26))
	alert_pill_style.set_border_width_all(2)
	alert_pill_style.border_color = Themes.ink(0.15)
	alert_pill_style.content_margin_left = 22
	alert_pill_style.content_margin_right = 26
	alert_pill_style.content_margin_top = 12
	alert_pill_style.content_margin_bottom = 12
	alert_pill.add_theme_stylebox_override("panel", alert_pill_style)
	alert_pill.modulate.a = 0.0
	alert_pill.visible = false
	alert_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(alert_pill)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	alert_pill.add_child(hb)
	alert_pill_icon = TextureRect.new()
	alert_pill_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	alert_pill_icon.custom_minimum_size = Vector2(40, 40)
	hb.add_child(alert_pill_icon)
	alert_pill_label = _label("", 24, TEXT)
	alert_pill_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(alert_pill_label)

# The battery alert fired. On screens where the top-bar controller icon is visible it flashes
# by itself; everywhere else (in a game, Library, details...) a notification does the flashing.
func _on_alert(level: int, pct: int, family: String) -> void:
	preload("res://notifications.gd").push("Controller battery %s, %d%%" % [alert.level_text(level), pct], "battery")
	if launching and _game_started:
		# Tephra isn't on screen during a game, so the notice goes through KDE's own notifications.
		_desktop_notice("Controller battery %s - %d%%" % [alert.level_text(level), pct], level >= 2)
		return
	if _top_bar_visible() and not (launching):
		return
	var model := TephraGlyphs.pad_model()
	alert_pill_icon.texture = Icons.texture("pad_" + model, Icons.svg_pad(model), 40)
	alert_pill_label.text = "Controller battery %s - %d%%" % [alert.level_text(level), pct]
	alert_pill.visible = true
	alert_pill.reset_size()
	_pill_y = 108.0 - alert_pill.size.y / 2.0  # the middle of the top bar band
	alert_pill.position = Vector2((size.x - alert_pill.size.x) / 2.0, _pill_y - 18.0)
	_pill_left = PERIOD_TOTAL + 0.8

const PERIOD_TOTAL := 3.75  # battery_alert: 3 pulses of 1.25 s

func _update_alert_pill(delta: float) -> void:
	if alert_pill == null or not alert_pill.visible:
		return
	_pill_left -= delta
	var col: Color = alert.band_color(alert.flash_level)
	var k: float = alert.k if alert.flashing else 0.0
	alert_pill_icon.modulate = Color.WHITE.lerp(col, k)
	alert_pill_style.border_color = Themes.ink(0.15).lerp(col, k)
	var want := 1.0 if _pill_left > 0.4 else 0.0
	alert_pill.modulate.a = move_toward(alert_pill.modulate.a, want, delta * 5.0)
	alert_pill.position.y = _pill_y - 18.0 * (1.0 - alert_pill.modulate.a)  # drops in from above as it fades in
	if _pill_left <= 0.0 and alert_pill.modulate.a <= 0.0:
		alert_pill.visible = false

# ---------- Launching ----------
func _make_launch_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	launch_overlay = ColorRect.new()
	launch_overlay.color = Color.BLACK
	launch_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	launch_overlay.modulate.a = 0.0
	launch_overlay.visible = false
	layer.add_child(launch_overlay)
	launch_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	launch_art = TextureRect.new()
	launch_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	launch_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	launch_art.modulate.a = 0.35
	launch_art.visible = false
	launch_overlay.add_child(launch_art)
	launch_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	launch_sharp = TextureRect.new()
	launch_sharp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	launch_sharp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	launch_sharp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	launch_sharp.visible = false
	launch_overlay.add_child(launch_sharp)
	launch_sharp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The game's own logo, above "Preparing...", when it has one.
	launch_logo = TextureRect.new()
	launch_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	launch_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	launch_logo.visible = false
	launch_overlay.add_child(launch_logo)
	launch_logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	launch_logo.offset_left = -400
	launch_logo.offset_right = 400
	launch_logo.offset_top = -270
	launch_logo.offset_bottom = -50

	launch_label = _label("", 32, MUTED)
	launch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	launch_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	launch_overlay.add_child(launch_label)
	launch_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# A thin bar under "Preparing ...": it moves while Steam starts and the game loads, and fills once the game is up.
	launch_bar = Panel.new()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.16)  # the launch screen is always black: a white bar on every theme
	track.set_corner_radius_all(Themes.r(3))
	launch_bar.add_theme_stylebox_override("panel", track)
	launch_bar.visible = false
	launch_overlay.add_child(launch_bar)
	launch_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	launch_bar.offset_left = -260
	launch_bar.offset_right = 260
	launch_bar.offset_top = 50
	launch_bar.offset_bottom = 56
	_launch_fill = Panel.new()
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.WHITE
	fill.set_corner_radius_all(Themes.r(3))
	_launch_fill.add_theme_stylebox_override("panel", fill)
	launch_bar.add_child(_launch_fill)
	_launch_fill.position = Vector2.ZERO
	_launch_fill.size = Vector2(0, 6)

	# Small jokes under the bar, changing every few seconds.
	launch_quip = _label("", 20, MUTED)
	launch_quip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	launch_quip.modulate.a = 0.0
	launch_quip.visible = false
	launch_overlay.add_child(launch_quip)
	launch_quip.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	launch_quip.offset_left = -520
	launch_quip.offset_right = 520
	launch_quip.offset_top = 70
	launch_quip.offset_bottom = 110

	# Always shown (even with button hints off in Settings): the only way out of a stuck launch.
	launch_hint = HBoxContainer.new()
	launch_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	launch_hint.add_theme_constant_override("separation", 14)
	launch_hint.visible = false
	launch_overlay.add_child(launch_hint)
	launch_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	launch_hint.offset_top = -120
	launch_hint.offset_bottom = -50

## Lines of Steam's own logs that mention this game (updates, missing files, runtime downloads, launch errors).
func _steam_log_lines(id: String, count: int) -> Array:
	var home_dir := OS.get_environment("HOME")
	var res: Array = []
	for rel in ["/.steam/steam/logs/content_log.txt", "/.steam/steam/logs/console-linux.txt", "/.steam/steam/logs/compat_log.txt", "/.steam/steam/logs/bootstrap_log.txt"]:
		var f := FileAccess.open(home_dir + rel, FileAccess.READ)
		if f == null:
			continue
		var lines: PackedStringArray = f.get_as_text().split("\n")
		f.close()
		var keep: Array = []
		for ln in lines:
			if ln.find("AppID " + id) >= 0 or ln.find("appid " + id) >= 0 or ln.find("gameid " + id) >= 0 or ln.find("rungameid/" + id) >= 0 or ln.find("steamrt") >= 0 or ln.find("Steam Linux Runtime") >= 0 or ln.find("pressure-vessel") >= 0 or ln.find("Failed") >= 0 or ln.find("error") >= 0:
				keep.append(rel.get_file() + ": " + ln.strip_edges())
		res += keep.slice(maxi(keep.size() - count, 0))
	return res

## "" when Steam is not busy with this game; otherwise a short note saying what it is doing (shown on the launch screen).
func _steam_busy_with(id: String) -> String:
	var recent := _steam_log_lines(id, 6)
	for i in range(recent.size() - 1, -1, -1):
		var ln: String = recent[i]
		if ln.find("content_log") >= 0 and ln.find("AppID " + id) >= 0:
			if ln.find("Update Required") >= 0 or ln.find("Updating") >= 0 or ln.find("Update Queued") >= 0 or ln.find("Update Running") >= 0 or ln.find("Fully Installed,Update Started") >= 0:
				return "Steam is updating it first"
			break
	for ln in recent:
		if str(ln).find("Steam Linux Runtime") >= 0 and (str(ln).find("Update") >= 0 or str(ln).find("download") >= 0):
			return "Steam is downloading its compatibility runtime"
	return ""

func _write_launch_log(id: String, title: String) -> void:
	var dir := OS.get_environment("HOME") + "/.config/tephra"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/launch.log", FileAccess.WRITE)
	if f == null:
		return
	f.store_line("Tephra could not start %s (%s) at %s" % [title, id, Time.get_datetime_string_from_system()])
	f.store_line("Steam running: %s   game process: %s" % [str(_steam_running()), str(_game_running(id))])
	var link := "steam://rungameid/" + id
	for gg in games:
		if str(gg["id"]) == id:
			link = _game_url(gg)
	f.store_line("Link sent: " + link)
	var out := []
	OS.execute("sh", ["-c", "pgrep -af 'steam|reaper|SteamLaunch' | head -20"], out)
	f.store_line("--- processes ---")
	for l in out:
		f.store_line(str(l).strip_edges())
	f.store_line("--- Steam's logs about this game ---")
	for l in _steam_log_lines(id, 25):
		f.store_line(str(l))
	f.close()

## A game that started and then closed within a minute or so (a crash, or something it needed was missing): what
## Tephra and Steam know is saved to ~/.config/tephra/launch.log, so there is something to go on.
func _write_early_exit_log(id: String, title: String, secs: int) -> void:
	var dir := OS.get_environment("HOME") + "/.config/tephra"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/launch.log", FileAccess.WRITE)
	if f == null:
		return
	f.store_line("%s (%s) closed %d seconds after it started, at %s" % [title, id, secs, Time.get_datetime_string_from_system()])
	f.store_line("It was not closed from Tephra's menu, so the game itself ended (a crash, or something it needs is missing).")
	f.store_line("--- Steam's logs about this game ---")
	for l in _steam_log_lines(id, 40):
		f.store_line(str(l))
	var home := OS.get_environment("HOME")
	for name in ["compat_log.txt", "stderr.txt"]:
		for base in [home + "/.local/share/Steam/logs/", home + "/.steam/steam/logs/"]:
			if FileAccess.file_exists(base + name):
				var out := []
				OS.execute("tail", ["-n", "25", base + name], out)
				f.store_line("--- end of " + name + " ---")
				for l in out:
					f.store_line(str(l).strip_edges(false, true))
				break
	f.close()

# True while Steam's launcher process for this game exists.
# "[S]team" matches "Steam" but not itself, so pgrep can't
# match the shell that runs it (which would always be "running").
func _game_running(id: String) -> bool:
	var output := []
	if OS.execute("pgrep", ["-f", "[S]teamLaunch AppId=" + id + " "], output) == 0:
		return true
	# A non-Steam game: if Steam's launcher cannot be found by its number, look for the program itself.
	var pat: String = str(_extra_exe.get(id, ""))
	return pat != "" and OS.execute("pgrep", ["-f", pat], output) == 0

## The link that makes Steam start a game: the game's number, or for non-Steam games their own long number.
func _game_url(g: Dictionary) -> String:
	return str(g.get("url", "steam://rungameid/" + str(g["id"])))

# ---------- Steam only runs when needed ----------
# Steam Input (and Steam in general) fights with Tephra's own controller
# handling, so Steam is only open while a game is running or downloading.
# Launching a game or an install starts it; this closes it again.
func _steam_running() -> bool:
	return OS.execute("pgrep", ["-x", "steam"], []) == 0

func _any_game_running() -> bool:
	return OS.execute("pgrep", ["-f", "[S]teamLaunch AppId="], []) == 0

# Steam is always started quietly: no window, and no Big Picture start-up movie or
# sound. (-silent = start hidden; -nobigpicture = never switch to Big Picture.)
const STEAM_ARGS := ["-silent", "-nobigpicture"]
var _steam_stopping := false
var _steam_sent_at := 0.0

# Opens a steam:// link. If Steam is in the middle of shutting down, wait for it
# to finish first; a link sent to a Steam that's closing is lost.
func steam_open(url: String, keep_virtual := false) -> void:
	while _steam_stopping:
		await get_tree().create_timer(0.5).timeout
	if _steam_virtual and not keep_virtual:
		await _steam_leave_virtual()  # a game needs the real screen: close the hidden Steam first
	_steam_sent_at = Time.get_ticks_msec() / 1000.0
	_steam_cmd(STEAM_ARGS + [url])

# ---------- Installing on a hidden screen ----------
# Steam's install popup can't be clicked reliably on a Wayland desktop with two monitors (the pointer
# lands somewhere else), and it would show up on screen. So installs run Steam on a separate, invisible
# X display (Xvfb, :99). The popup opens there, where clicking is exact and nobody sees it. When the
# download is done (or a game is launched) that Steam is closed and the next one starts normally.
# Needs the `xorg-server-xvfb` package; without it, or with a ~/.config/tephra/no_virtual file,
# the older way is used.
const VDISPLAY := ":99"
var _steam_virtual := false

func _virtual_ok() -> bool:
	if FileAccess.file_exists(OS.get_environment("HOME") + "/.config/tephra/no_virtual"):
		return false
	return OS.execute("which", ["Xvfb"], []) == 0 and OS.execute("which", ["xdotool"], []) == 0

# Runs the steam command on the right display (hidden one while installing).
func _steam_cmd(args: Array) -> void:
	if not args.has("-shutdown") and not _steam_running():
		_pads_before_steam()  # Steam is about to start: its layouts must already be right
	if _steam_virtual:
		# Steam started only to download: asked to leave PlayStation and Xbox pads alone (an SDL setting; Steam may
		# ignore it, so _hush_steam is the backstop).
		OS.create_process("env", ["-u", "WAYLAND_DISPLAY", "DISPLAY=" + VDISPLAY,
			"SDL_GAMECONTROLLER_IGNORE_DEVICES=0x054c/0x0ce6,0x054c/0x0df2,0x054c/0x05c4,0x054c/0x09cc,0x045e/0x0b12,0x045e/0x0b13,0x045e/0x02ea,0x045e/0x0b20",
			"steam"] + args)
	else:
		# On a laptop with an Intel chip and an NVIDIA card, Steam and every game would otherwise run on the
		# weak Intel chip (the "PRIME offload" variables fix that). MangoHud is never switched on (v0.23.0):
		# "-u" also drops it if Tephra itself was started with it.
		var env: Array = ["-u", "MANGOHUD", "-u", "MANGOHUD_CONFIGFILE", "-u", "MANGOHUD_DLSYM"] + Perf.gpu_env()
		OS.create_process("env", env + ["steam"] + args)

# ---------- The touchpad click stays out of games ----------
# Steam's own PlayStation layouts send the touchpad click to games as Select (left half) and Start (right half). In
# Tephra the touchpad click is the screenshot / record button, so every screenshot also opened a game's map or pause
# menu. steam_pads.py empties what the click sends in every PlayStation layout Steam has on this PC; Create and
# Options stay Select and Start. Steam only reads its layouts when it starts, may write its copies back when it
# closes, and puts its own templates back when it updates, so this runs while Steam is closed: at boot, after Steam
# closes, and right before Steam starts (that last run only does something if the others missed it).
# Settings > Controller > "Touchpad click in games" turns it off, which puts Steam's own layouts back.
var _pads_mode := ""  # what has been done to Steam's layouts since Steam last ran: "free", "steam", or "" (not known)
var _pads_task := -1
var _pads_gen := 0    # goes up each time Steam starts: a background run that finishes after that is out of date

func _pads_wanted() -> String:
	return "free" if bool(Settings.get_value("touchpad_layout", true)) else "steam"

## Runs steam_pads.py ("steam" = put Steam's own layouts back) and returns what it printed. It waits for the script
## (well under a second), so it is run on a worker thread whenever possible.
static func _run_steam_pads(mode: String) -> String:
	var out: Array = []
	var args: Array = ["-I", ProjectSettings.globalize_path("res://steam_pads.py")]
	if mode == "steam":
		args.append("--restore")
	OS.execute("python3", args, out, true)
	return str(out[0]).strip_edges() if not out.is_empty() else "python3 gave no answer"

## In the background, while Steam is closed. Also called when the setting changes.
func _pads_refresh() -> void:
	if _pads_task != -1 or _steam_running():
		return
	var mode := _pads_wanted()
	var gen := _pads_gen
	var box := {}
	box["id"] = _work(func() -> void:
		var report := _run_steam_pads(mode)
		_pads_done.call_deferred(box, mode, gen, report))  # the id is read later, on the main thread: it may not be set yet here
	_pads_task = int(box["id"])

func _pads_done(box: Dictionary, mode: String, gen: int, report: String) -> void:
	var id := int(box["id"])
	_work_done(id)
	if _pads_task == id:
		_pads_task = -1
	_pads_log(report)
	if gen == _pads_gen and not _steam_running():
		_pads_mode = mode  # Steam has not started since: its layouts are as wanted

## Right before Steam starts. Usually the background run already did the work and this only takes note that
## Steam is about to run; otherwise (it was still busy, or the setting just changed) the script runs now.
func _pads_before_steam() -> void:
	var wanted := _pads_wanted()
	var already := _pads_mode == wanted and _pads_task == -1
	if _pads_task != -1:
		_work_done(_pads_task)  # a background run is under way: let it finish first (it is quick)
		_pads_task = -1
	_pads_gen += 1    # anything still arriving from before this moment no longer counts
	_pads_mode = ""   # Steam is about to run and may change its layouts: look again once it has closed
	if not already:
		_pads_log(_run_steam_pads(wanted))
	_pads_fixed_ms = Time.get_ticks_msec()  # the Steam that starts next reads layouts that are as wanted
	_pads_fixed_mode = wanted

# Steam reads its layouts only when it starts. If it was already open before the layouts were fixed (Tephra was
# restarted, for example by an update, while Steam stayed open), it keeps using Steam's own layouts until it closes,
# and a game started now would still get Select / Start from the touchpad. This is what happened the first time.
var _pads_fixed_ms := 0       # when the layouts were last made right just before Steam started (0 = not in this session)
var _pads_fixed_mode := ""

## How long the running Steam has been open, in seconds (-1 if it isn't running).
func _steam_age_s() -> int:
	var out: Array = []
	if OS.execute("ps", ["-o", "etimes=", "-C", "steam"], out) != 0 or out.is_empty():
		return -1
	var oldest := -1
	for line in str(out[0]).split("\n", false):
		oldest = maxi(oldest, line.strip_edges().to_int())  # Steam has a few processes named "steam": the oldest is the client
	return oldest

## True when Tephra's own layout (steam_pads.py: Steam's Gamepad without the touchpad click) isn't in Steam's templates.
func _pads_look_unfixed() -> bool:
	return DirAccess.dir_exists_absolute(steam_dir + "/controller_base/templates") \
			and not FileAccess.file_exists(steam_dir + "/controller_base/templates/tephra_controller_ps5.vdf")

## Does Steam's layout index point this game at Tephra's layout? key: a Steam game's number, or a non-Steam game's
## name in lower case (that is how Steam lists those).
func _pads_game_ok(key: String) -> bool:
	var out: Array = []
	OS.execute("python3", ["-I", ProjectSettings.globalize_path("res://steam_pads.py"), "--check", key], out, true)
	return not out.is_empty() and str(out[0]).strip_edges() == "ok"

## Before a game starts: if the open Steam began before the layouts were set (Tephra restarted while Steam stayed open),
## Tephra's own layout is missing, or this game isn't pointed at it yet (installed while Steam was open), close Steam, so
## steam_open() starts it fresh, and that start sets the layouts first (_steam_cmd).
## Never while Steam is busy with a game, a download or an install, and at most once per game per session.
var _pads_restarted_for := {}

func _pads_ready_for_game(key: String) -> void:
	if _pads_restarted_for.has(key) or _steam_virtual or not _steam_running():
		return  # a Steam that is not open yet gets the layouts as it starts
	var wanted := _pads_wanted()
	var age := _steam_age_s()
	var started_after := _pads_fixed_ms > 0 and _pads_fixed_mode == wanted and age >= 0 \
			and age <= (Time.get_ticks_msec() - _pads_fixed_ms) / 1000 + 2
	if started_after and (wanted != "free" or (not _pads_look_unfixed() and _pads_game_ok(key))):
		return
	if _any_game_running() or not library._installing.is_empty() or _steam_downloading(_steam_libs()):
		return
	_pads_restarted_for[key] = true
	_install_log("touchpad layout: Steam was open without it for %s (open %d s), restarting Steam once" % [key, age])
	_steam_stopping = true
	_steam_cmd(["-shutdown"])
	var waited := 0.0
	while _steam_running() and waited < 30.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	_steam_stopping = false

## What the script did, for ~/.config/tephra/steam_pads.log (only when it changed something or had a problem).
func _pads_log(report: String) -> void:
	if report.ends_with("done: 0 layout(s) changed") or report.ends_with("done: 0 layout(s) restored"):
		return
	var dir := OS.get_environment("HOME") + "/.config/tephra"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/steam_pads.log", FileAccess.WRITE)
	if f != null:
		f.store_line(Time.get_datetime_string_from_system())
		f.store_line(report)
		f.close()

func _kill_xvfb() -> void:
	OS.execute("pkill", ["-f", "^Xvfb " + VDISPLAY], [])  # "^": only the real Xvfb, not a shell line mentioning it

func _steam_leave_virtual() -> void:
	_steam_stopping = true
	_steam_cmd(["-shutdown"])
	var waited := 0.0
	while _steam_running() and waited < 40.0:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	_steam_stopping = false
	_kill_xvfb()
	_steam_virtual = false
	_install_log("hidden Steam closed")

## Starts the install on the hidden display. Returns false if that isn't possible (then use the old way).
## update_only: just start Steam there (it then fetches its queued updates by itself), no install link.
func steam_install_hidden(id: String, update_only := false) -> bool:
	if not _virtual_ok():
		return false
	while _steam_stopping:
		await get_tree().create_timer(0.5).timeout
	if _steam_running() and not _steam_virtual:
		# Steam is open on the real screen: close it first, or the popup would open there.
		_steam_stopping = true
		OS.create_process("steam", ["-shutdown"])
		var waited := 0.0
		while _steam_running() and waited < 40.0:
			await get_tree().create_timer(1.0).timeout
			waited += 1.0
		_steam_stopping = false
		if _steam_running():
			_install_log("install %s: Steam would not close, using the visible way" % id)
			return false
	if OS.execute("env", ["DISPLAY=" + VDISPLAY, "xdotool", "getdisplaygeometry"], []) != 0:
		# Not running yet. -ac: any local program may connect (nothing else is on this private display).
		OS.create_process("Xvfb", [VDISPLAY, "-screen", "0", "1280x1024x24", "-ac", "-nolisten", "tcp"])
	# Wait until the display really answers, up to 15 s (the keyboard layout takes a few seconds to compile). Steam started too early says "Unable to open a connection to X".
	var ready := false
	for i in 60:
		if OS.execute("env", ["DISPLAY=" + VDISPLAY, "xdotool", "getdisplaygeometry"], []) == 0:
			ready = true
			break
		await get_tree().create_timer(0.25).timeout
	if not ready:
		_install_log("install %s: hidden display %s did not start, using the visible way" % [id, VDISPLAY])
		_kill_xvfb()
		return false
	_steam_virtual = true
	_steam_sent_at = Time.get_ticks_msec() / 1000.0
	_steam_cmd(STEAM_ARGS + ([] if update_only else ["steam://install/" + id]))
	_install_log("%s %s: Steam started on the hidden display %s" % ["updates" if update_only else "install", id, VDISPLAY])
	return true

# ---------- Updating games by themselves ----------
## Steam only updates games while it is open, and Tephra keeps it closed whenever nothing needs it, so updates sat
## "Queued" for ever (Steam also puts off updates of games not played lately, or until they are launched). Every
## couple of minutes on Home, with Steam closed and no game running: if an installed game has an update waiting, its
## manifest is set to "update now" (high priority, nothing scheduled) and Steam is started on the hidden display.
## It fetches the updates there, and the Steam sweep closes it again once nothing is left to download. Starting a
## game meanwhile closes that hidden Steam first (steam_open), so updates never hold up play; Steam itself doesn't
## download while a game runs. Settings > System > "Update games automatically".
const AUTO_UPDATE_EVERY := 120.0
var _au_acc := 0.0
var _au_busy := false
var _au_tried := {}  # manifest path -> when Steam was last opened to update it
var _au_active := false  # Steam is open because Tephra opened it to update games

func _auto_update_tick(delta: float) -> void:
	_au_acc += delta
	if _au_acc < AUTO_UPDATE_EVERY:
		return
	_au_acc = 0.0
	if _au_busy or not bool(Settings.get_value("auto_update", true)) or launching or _game_active or _steam_stopping \
			or not library._installing.is_empty() or _ps2_busy or _steam_running():
		return
	# An update that is still waiting 30 minutes after Steam was opened for it (no internet, Steam signed out) is left
	# alone for a while, so Steam isn't opened and closed again every two minutes.
	var now := Time.get_ticks_msec() / 1000.0
	var ids: Array = []
	for p in _updates_waiting():
		if now - float(_au_tried.get(p, -100000.0)) > 1800.0:
			ids.append(p)
	if not ids.is_empty():
		for p in ids:
			_au_tried[p] = now
		_run_updates(ids)

func _is_installed_id(id: String) -> bool:
	for lib in _steam_libs():
		var p := str(lib) + "/steamapps/appmanifest_" + id + ".acf"
		if FileAccess.file_exists(p):
			return (_acf_value(FileAccess.get_file_as_string(p), "StateFlags").to_int() & 4) != 0
	return false

## Installed games (and Steam's tools) whose manifest says an update is needed: [manifest path, ...].
func _updates_waiting() -> Array:
	var out: Array = []
	for lib in _steam_libs():
		var dir := DirAccess.open(str(lib) + "/steamapps")
		if dir == null:
			continue
		for f in dir.get_files():
			if f.begins_with("appmanifest_") and f.ends_with(".acf"):
				var p := str(lib) + "/steamapps/" + f
				var flags := _acf_value(FileAccess.get_file_as_string(p), "StateFlags").to_int()
				if (flags & 4) != 0 and (flags & 2) != 0:
					out.append(p)
	return out

## ids: manifest paths from _updates_waiting(), or game numbers (the Start button on a queued update).
func _run_updates(ids: Array) -> void:
	if _au_busy or launching:
		return
	_au_busy = true
	if _steam_running():
		if _any_game_running() or _steam_virtual or not library._installing.is_empty():
			_au_busy = false
			return  # a game is on (it updates after), or Steam is already at work (the hidden one, or an install)
		await _dl_close_steam()  # its manifests can only be changed while it is closed
		if _steam_running():
			_au_busy = false
			return
	var names: Array = []
	for x in ids:
		var p := str(x)
		if not p.ends_with(".acf"):
			for lib in _steam_libs():
				if FileAccess.file_exists(str(lib) + "/steamapps/appmanifest_" + p + ".acf"):
					p = str(lib) + "/steamapps/appmanifest_" + p + ".acf"
		if not FileAccess.file_exists(p):
			continue
		var txt := FileAccess.get_file_as_string(p)
		names.append(_acf_value(txt, "name"))
		# High priority and nothing scheduled: Steam starts the update as soon as it is open, instead of "later".
		var out := RegEx.create_from_string("(\"AutoUpdateBehavior\"\\s+)\"\\d+\"").sub(txt, "$1\"2\"")
		out = RegEx.create_from_string("(\"ScheduledAutoUpdate\"\\s+)\"\\d+\"").sub(out, "$1\"0\"")
		if out != txt:
			var fw := FileAccess.open(p, FileAccess.WRITE)
			if fw != null:
				fw.store_string(out)
				fw.close()
	if names.is_empty():
		_au_busy = false
		return
	_install_log("updates: starting Steam to update " + ", ".join(PackedStringArray(names)))
	var hidden: bool = await steam_install_hidden("updates", true)
	if not hidden and not launching and not _steam_running():
		_steam_sent_at = Time.get_ticks_msec() / 1000.0
		_steam_cmd(STEAM_ARGS)  # no hidden display here: Steam starts silently (no window) and updates all the same
	_au_active = true
	_au_busy = false

# Steam's install popup ("Install - <game>": options, then the agreement, then Finish) is clicked
# through for you by sending Return to it. It only works on X11 with xdotool; elsewhere (or if
# nothing happens) Steam's own popup stays on screen and can be used normally. Stops as soon as
# Steam has written the game's manifest, i.e. the download is accepted, or after 45 s.
# ---------- Timing log ----------
## ~/.config/tephra/timing.log: each step of starting and closing a game, with the seconds since the button press,
## so a slow start shows exactly where the time went.
var _tl_t0 := 0

func _tl_start(what: String) -> void:
	_tl_t0 = Time.get_ticks_msec()
	_tl_write("---- " + what)

func _tl(step: String) -> void:
	_tl_write("%6.1f s  %s" % [(Time.get_ticks_msec() - _tl_t0) / 1000.0, step])

func _tl_write(line: String) -> void:
	var path := OS.get_environment("HOME") + "/.config/tephra/timing.log"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	if f.get_length() > 200000:  # keep it small: start over
		f.close()
		f = FileAccess.open(path, FileAccess.WRITE)
	f.seek_end()
	f.store_line("%s  %s" % [Time.get_datetime_string_from_system().substr(11), line])
	f.close()

func _install_log(msg: String) -> void:
	var dir := OS.get_environment("HOME") + "/.config/tephra"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/install.log", FileAccess.READ_WRITE if FileAccess.file_exists(dir + "/install.log") else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s  %s" % [Time.get_datetime_string_from_system(), msg])
	f.close()

func _xdo(args: Array) -> String:
	var out := []
	var rc := 0
	if _steam_virtual:
		rc = OS.execute("env", ["-u", "WAYLAND_DISPLAY", "DISPLAY=" + VDISPLAY, "xdotool"] + args, out)
	else:
		rc = OS.execute("xdotool", args, out)
	if rc != 0 or out.is_empty():
		return ""
	return str(out[0]).strip_edges()

# Steam windows right now: [{id, title, x, y, w, h}] (the install popup is one of them).
# Finding them takes dozens of xdotool calls (Steam has many windows), each starting a program. Done on
# Tephra's own thread that froze the screen for a moment every second or so while a game installed
# (the FPS drop), so it runs on a worker thread and the caller just waits for the answer without
# holding up a single frame. Use it as: `for w in await _steam_windows():`
func _steam_windows(visible_only := false) -> Array:
	var box := {"done": false, "list": []}
	var id := _work(func() -> void:
		box["list"] = _steam_windows_now(visible_only)
		box["done"] = true)
	while not box["done"]:
		await get_tree().process_frame
	_work_done(id)
	return box["list"]

func _steam_windows_now(visible_only := false) -> Array:
	var found: Array = []
	var seen := {}
	for cls in ["steamwebhelper", "steam"]:
		for wid in _xdo((["search", "--onlyvisible", "--class", cls] if visible_only else ["search", "--class", cls])).split("\n"):
			wid = wid.strip_edges()
			if wid == "" or seen.has(wid):
				continue
			seen[wid] = true
			var title := _xdo(["getwindowname", wid])
			var geo := {}
			for ln in _xdo(["getwindowgeometry", "--shell", wid]).split("\n"):
				var kv := ln.split("=")
				if kv.size() == 2:
					geo[kv[0]] = kv[1].to_int()
			found.append({"id": wid, "title": title, "x": geo.get("X", 0), "y": geo.get("Y", 0), "w": geo.get("WIDTH", 0), "h": geo.get("HEIGHT", 0)})
	return found

# Steam's install popup is one window ("Install"): the game, two shortcut options, the drive, and
# an Install button to the left of Cancel. It ignores keys sent from outside, so Tephra clicks the
# Install button, a few nearby heights in turn (Cancel is further right, so it is never hit).
# Stops as soon as the popup closes or Steam has written the game's manifest.
const INSTALL_CLICK_X := 0.40
# Pixels above the popup's bottom edge, measured on a popup 540 px wide: 45. Scaled by the real popup
# width, so a bigger popup (other monitor, other UI scale) gets a bigger offset. It counts from the
# bottom because the popup is taller for games with more in it.
const INSTALL_CLICK_UP := [45, 38, 52, 31, 60, 24]
const INSTALL_REF_WIDTH := 540.0

# Makes a window fully see-through. It still sits there and still gets clicks, you just can't see
# it. (Uses the X11 opacity hint, which KDE honours for Steam's window, also under Wayland.)
func _hide_window(wid: String) -> void:
	if FileAccess.file_exists(OS.get_environment("HOME") + "/.config/tephra/no_hide"):
		_install_log("hide popup: skipped (no_hide file), popup stays visible")
		return
	if OS.execute("which", ["xprop"], []) != 0:
		_install_log("hide popup: xprop is not installed (pacman -S xorg-xprop), popup stays visible")
		return
	# Not quite 0: KDE may stop sending clicks to a window that is completely transparent,
	# so it is left at about 1% (50331648 of 4294967295), which cannot be seen.
	var rc := OS.execute("xprop", ["-id", wid, "-f", "_NET_WM_WINDOW_OPACITY", "32c", "-set", "_NET_WM_WINDOW_OPACITY", "50331648"], [])
	_install_log("hide popup %s: opacity set to ~1%% (exit %d)" % [wid, rc])

## While a game is starting, Steam can put up a small dialog of its own (for example "this game doesn't support
## controller input") and wait for an answer. Tephra keeps Steam out of sight, so nobody could ever press it and the
## game never started. This looks for such a dialog (a small visible Steam window that is not the main one), writes it
## to ~/.config/tephra/install.log, and answers it: Enter first, then a click where the main button usually is.
func _dismiss_steam_dialogs(id: String) -> void:
	if OS.execute("which", ["xdotool"], []) != 0:
		return
	var tries := {}
	var logged := {}
	await get_tree().create_timer(2.0).timeout
	while launching and not _game_started and not _launch_cancel:
		for w in await _steam_windows(true):
			var wid := str(w["id"])
			var ww: int = int(w["w"])
			var hh: int = int(w["h"])
			var title := str(w["title"])
			if ww < 260 or ww > 1000 or hh < 120 or hh > 700 or title in ["Steam", "Friends List"]:
				continue
			if not logged.has(wid):
				logged[wid] = true
				_install_log("launch %s: Steam dialog %s \"%s\" %dx%d at %d,%d" % [id, wid, title, ww, hh, int(w["x"]), int(w["y"])])
			var n: int = int(tries.get(wid, 0))
			if n >= 4:
				continue
			tries[wid] = n + 1
			_xdo(["windowfocus", wid] if _steam_virtual else ["windowactivate", "--sync", wid])
			if n == 0:
				_xdo(["key", "--window", wid, "Return"])
			else:
				var scale := float(ww) / INSTALL_REF_WIDTH
				var fx := 0.4 if n == 1 else (0.5 if n == 2 else 0.6)
				_xdo(["mousemove", str(int(w["x"]) + int(float(ww) * fx)), str(int(w["y"]) + hh - int(45.0 * scale))])
				await get_tree().create_timer(0.3).timeout
				_xdo(["click", "1"])
			_install_log("launch %s: answered Steam dialog %s (try %d)" % [id, wid, n + 1])
		await get_tree().create_timer(2.0).timeout

func steam_confirm_install(id: String) -> void:
	var have := OS.execute("which", ["xdotool"], []) == 0
	_install_log("install %s: asked Steam (xdotool %s)" % [id, "found" if have else "MISSING"])
	if not have:
		return
	if FileAccess.file_exists(OS.get_environment("HOME") + "/.config/tephra/no_autoconfirm"):
		_install_log("install %s: auto-confirm is switched off (no_autoconfirm file); leaving Steam's popup to you" % id)
		return
	_install_log("install %s: screen %s" % [id, _xdo(["getdisplaygeometry"])])
	var waited := 0.0
	var tries := 0
	var seen_at := -1.0
	var logged := {}
	await get_tree().create_timer(1.5).timeout
	while waited < 60.0 and tries < INSTALL_CLICK_UP.size() and manifest_text(id) == "":
		var popup := {}
		for w in await _steam_windows():
			var key := "%s|%s|%dx%d" % [w["id"], w["title"], w["w"], w["h"]]
			if not logged.has(key):
				logged[key] = true
				_install_log("install %s: window %s \"%s\" at %d,%d size %dx%d" % [id, w["id"], w["title"], w["x"], w["y"], w["w"], w["h"]])
			if str(w["title"]) == "Install" and int(w["w"]) >= 300 and int(w["h"]) >= 300:
				popup = w
				break
		if popup.is_empty():
			if tries > 0:
				break  # it was there and now it's gone: accepted (or cancelled)
		else:
			if seen_at < 0.0:
				seen_at = waited  # give the page a moment to draw its button before clicking
				if not _steam_virtual:
					_hide_window(str(popup["id"]))
			if waited - seen_at >= 2.0:
				var scale: float = float(popup["w"]) / INSTALL_REF_WIDTH
				var cx: int = int(popup["x"]) + int(float(popup["w"]) * INSTALL_CLICK_X)
				var cy: int = int(popup["y"]) + int(popup["h"]) - int(float(INSTALL_CLICK_UP[tries]) * scale)
				# A tall popup can run off the bottom of the screen with its button on it: slide it up.
				var dims := _xdo(["getdisplaygeometry"]).split(" ")
				var screen_h: int = dims[1].to_int() if dims.size() >= 2 else 0
				if screen_h > 0 and cy > screen_h - 4 and int(popup["h"]) < screen_h - 8:
					var ny: int = maxi(0, screen_h - int(popup["h"]) - 8)
					_install_log("install %s: button would be off screen (y=%d of %d); moving popup to y=%d" % [id, cy, screen_h, ny])
					_xdo(["windowmove", popup["id"], str(popup["x"]), str(ny)])
					await get_tree().create_timer(0.6).timeout
					waited += 0.6
					continue
				var before := _xdo(["getmouselocation", "--shell"])
				_xdo(["windowfocus", popup["id"]] if _steam_virtual else ["windowactivate", "--sync", popup["id"]])
				_install_log("install %s: clicking Install at %d,%d (try %d)" % [id, cx, cy, tries + 1])
				# Like a hand: move onto the button, let the page notice the hover, then press and release.
				_xdo(["mousemove", str(cx - 6), str(cy - 3)])
				await get_tree().create_timer(0.25).timeout
				_xdo(["mousemove", str(cx), str(cy)])
				await get_tree().create_timer(0.45).timeout
				_xdo(["mousedown", "1"])
				await get_tree().create_timer(0.15).timeout
				_xdo(["mouseup", "1"])
				# Put the pointer back where it was.
				var mx := 0
				var my := 0
				for ln in before.split("\n"):
					if ln.begins_with("X="):
						mx = ln.substr(2).to_int()
					elif ln.begins_with("Y="):
						my = ln.substr(2).to_int()
				_xdo(["mousemove", str(mx), str(my)])
				tries += 1
				await get_tree().create_timer(1.5).timeout
				waited += 1.5
		var step := 0.2 if seen_at < 0.0 else 1.0
		await get_tree().create_timer(step).timeout
		waited += step
	_install_log("install %s: done waiting (clicks=%d, manifest=%s)" % [id, tries, "yes" if manifest_text(id) != "" else "no"])
	await _accept_eula(id)

# Some games (Capcom's, for one) make Steam show the publisher's own license window ("EULA") after the
# Install popup, and nothing downloads until it is accepted. This watches for it and clicks Accept.
# Accept sits left of Cancel at the bottom: measured on a 648 px wide window, its middle is 66% of the
# way across and 42 px above the bottom edge (scaled by the real width, like the Install button).
const EULA_ACCEPT_X := 0.664
const EULA_ACCEPT_UP := [42, 36, 48, 30]
const EULA_REF_WIDTH := 648.0
# Steam usually draws the license as an overlay INSIDE its main window (no window of its own), centred.
# Measured on a 1280x960 main window: Accept's middle is 106 px right of and 333 px below the window's
# centre. Scaled by the window's width, so it also holds at other sizes.
const EULA_INPAGE_DX := 106.0
const EULA_INPAGE_DY := 333.0
const EULA_INPAGE_REF_WIDTH := 1280.0

func _accept_eula(id: String) -> void:
	var waited := 0.0
	var clicks := 0
	var page_clicks := 0
	var last_page_click := -100.0
	var seen := false
	var logged := {}
	while waited < 50.0 and clicks < EULA_ACCEPT_UP.size() and page_clicks < 3:
		var eula := {}
		var main := {}
		for w in await _steam_windows():
			var key := "%s|%s|%dx%d" % [w["id"], w["title"], w["w"], w["h"]]
			if not logged.has(key):
				logged[key] = true
				_install_log("install %s: window %s \"%s\" at %d,%d size %dx%d" % [id, w["id"], w["title"], w["x"], w["y"], w["w"], w["h"]])
			if str(w["title"]).to_lower().contains("eula") and int(w["w"]) >= 300 and int(w["h"]) >= 300:
				eula = w
			elif str(w["title"]) == "Steam" and int(w["w"]) >= 800 and int(w["h"]) >= 500:
				main = w
		if manifest_text(id) != "" and waited >= 4.0:
			break  # the download is going: nothing (more) to accept
		if not eula.is_empty():
			if not seen:
				seen = true
				_install_log("install %s: license (EULA) window found, accepting it" % id)
				await get_tree().create_timer(2.0).timeout
				waited += 2.0
				continue
			var scale: float = float(eula["w"]) / EULA_REF_WIDTH
			var cx: int = int(eula["x"]) + int(float(eula["w"]) * EULA_ACCEPT_X)
			var cy: int = int(eula["y"]) + int(eula["h"]) - int(float(EULA_ACCEPT_UP[clicks]) * scale)
			_install_log("install %s: clicking Accept at %d,%d (try %d)" % [id, cx, cy, clicks + 1])
			await _click_at(str(eula["id"]), cx, cy)
			clicks += 1
			await get_tree().create_timer(2.0).timeout
			waited += 2.0
			continue
		# No separate license window, and still no download a few seconds after Install was clicked:
		# the license is probably the overlay inside Steam's main window.
		if not main.is_empty() and waited >= 8.0 and waited - last_page_click >= 7.0:
			var s2: float = float(main["w"]) / EULA_INPAGE_REF_WIDTH
			var px: int = int(main["x"]) + int(float(main["w"]) / 2.0 + EULA_INPAGE_DX * s2)
			var py: int = int(main["y"]) + int(float(main["h"]) / 2.0 + EULA_INPAGE_DY * s2)
			_install_log("install %s: no download yet; clicking Accept inside Steam's window at %d,%d (try %d)" % [id, px, py, page_clicks + 1])
			await _click_at(str(main["id"]), px, py)
			page_clicks += 1
			last_page_click = waited
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	_install_log("install %s: license step done (window=%s, clicks=%d, in-window clicks=%d, manifest=%s)" % [id, str(seen), clicks, page_clicks, "yes" if manifest_text(id) != "" else "no"])

# One hand-like click: focus the window, hover the spot, press and release, put the pointer back.
func _click_at(wid: String, cx: int, cy: int) -> void:
	var before := _xdo(["getmouselocation", "--shell"])
	_xdo(["windowfocus", wid] if _steam_virtual else ["windowactivate", "--sync", wid])
	_xdo(["mousemove", str(cx - 6), str(cy - 3)])
	await get_tree().create_timer(0.25).timeout
	_xdo(["mousemove", str(cx), str(cy)])
	await get_tree().create_timer(0.45).timeout
	_xdo(["mousedown", "1"])
	await get_tree().create_timer(0.15).timeout
	_xdo(["mouseup", "1"])
	var mx := 0
	var my := 0
	for ln in before.split("\n"):
		if ln.begins_with("X="):
			mx = ln.substr(2).to_int()
		elif ln.begins_with("Y="):
			my = ln.substr(2).to_int()
	_xdo(["mousemove", str(mx), str(my)])

# Re-sends the link if Steam isn't running 20+ seconds after we asked.
func steam_resend_if_dead(url: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not _steam_stopping and not _steam_running() and now - _steam_sent_at > 20.0:
		_steam_sent_at = now
		_steam_cmd(STEAM_ARGS + [url])

## True while Steam still has anything to download in these library folders (queued downloads, updates): the
## "downloading" folder holds something, or a game's manifest says it has more to fetch.
static var _tool_wait_since := -1.0

static func _steam_downloading(libs: Array) -> bool:
	var tool_pending := false
	for lib in libs:
		var dl := DirAccess.open(str(lib) + "/steamapps/downloading")
		if dl != null and (not dl.get_directories().is_empty() or not dl.get_files().is_empty()):
			return true
		var sa := DirAccess.open(str(lib) + "/steamapps")
		if sa == null:
			continue
		for f in sa.get_files():
			if f.begins_with("appmanifest_") and f.ends_with(".acf"):
				var txt := FileAccess.get_file_as_string(str(lib) + "/steamapps/" + f)
				var re := RegEx.create_from_string("\"(StateFlags|BytesToDownload|BytesDownloaded)\"\\s+\"(\\d+)\"")
				var v := {}
				for m in re.search_all(txt):
					v[m.get_string(1)] = m.get_string(2).to_int()
				var flags: int = v.get("StateFlags", 4)
				if (flags & (2 | 256 | 1024 | 2048)) != 0 and int(v.get("BytesToDownload", 0)) > int(v.get("BytesDownloaded", 0)):
					return true
				# Steam's own tools (Proton, the Linux runtimes, Steamworks Common) are always updated by Steam itself. One that
				# is waiting for an update, even if it has not started fetching yet, keeps Steam open until it is done. A stuck
				# one (no network, say) is given up on after 15 minutes so Steam is not held open for ever.
				if (flags & (2 | 256 | 1024 | 2048 | 1048576 | 2097152 | 4194304)) != 0 and (flags & 64) == 0:
					var nm := RegEx.create_from_string("\"name\"\\s+\"([^\"]*)\"").search(txt)
					if nm != null:
						for t in SKIP:
							if nm.get_string(1).contains(t):
								tool_pending = true
	if tool_pending:
		var now := Time.get_ticks_msec() / 1000.0
		if _tool_wait_since < 0.0:
			_tool_wait_since = now
		return now - _tool_wait_since < 900.0
	_tool_wait_since = -1.0
	return false

# Closes Steam if nothing needs it: no game running, nothing installing.
func stop_steam_if_idle() -> void:
	if not bool(Settings.get_value("steam_autoclose", true)):
		return
	if launching or not library._installing.is_empty() or _any_game_running() or _steam_downloading(_steam_libs()):
		return
	if not _steam_running():
		return
	_steam_stopping = true
	_steam_cmd(["-shutdown"])
	# Wait (up to 40 s) for Steam to finish saving and exit...
	var waited := 0.0
	while _steam_running() and waited < 40.0:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	_steam_stopping = false
	if _steam_virtual:
		_kill_xvfb()
		_steam_virtual = false
	_pads_refresh()  # Steam is closed: the moment to put Tephra's touchpad fix back on its layouts (see steam_pads.py)
	res_cleanup()  # also the moment to take the old Game resolution wrapper out of Steam games
	# ...then pick up the playtime it just wrote.
	playtimes.clear()
	_load_playtimes()
	for g in games:
		g["playtime"] = playtimes.get(str(g["id"]), g["playtime"])

# ---------- Steam sweep ----------
## Every few seconds: if Steam is open and nothing needs it, close it straight away. Steam is left alone while a game
## runs, while something downloads or installs, and for 90 seconds after Tephra asked it for something (a game
## starting needs Steam). The check runs off the main thread so Tephra never stutters for it.
const SWEEP_EVERY := 4.0
const SWEEP_GRACE := 90.0
var _sweep_acc := 0.0
var _sweep_id := -1
var _sweeping := false

func _steam_sweep(delta: float) -> void:
	_sweep_acc += delta
	if _sweep_acc < SWEEP_EVERY or _sweeping:
		return
	_sweep_acc = 0.0
	if not _steam_needed_free():
		return
	_sweeping = true
	var libs := _steam_libs()
	_sweep_id = _work(func() -> void:
		var idle := OS.execute("pgrep", ["-x", "steam"], []) == 0 and OS.execute("pgrep", ["-f", "[S]teamLaunch AppId="], []) != 0
		if idle and _steam_downloading(libs):
			idle = false  # Steam is still fetching queued games: leave it open until they are all done
		_steam_sweep_result.call_deferred(idle))

func _steam_sweep_result(idle: bool) -> void:
	_work_done(_sweep_id)
	_sweeping = false
	if idle and _steam_needed_free():
		_steam_close_now()

# Nothing of Tephra's needs Steam right now.
func _steam_needed_free() -> bool:
	return bool(Settings.get_value("steam_autoclose", true)) and not launching and not _game_active and not _steam_stopping \
		and library._installing.is_empty() and not _ps2_busy \
		and Time.get_ticks_msec() / 1000.0 - _steam_sent_at > SWEEP_GRACE

# Asks Steam to quit (so it saves), and if it is still there 6 seconds later, ends it.
func _steam_close_now() -> void:
	_au_active = false
	_steam_stopping = true
	_steam_cmd(["-shutdown"])
	var waited := 0.0
	while waited < 6.0:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
		if OS.execute("pgrep", ["-x", "steam"], []) != 0:
			break
	if OS.execute("pgrep", ["-x", "steam"], []) == 0:
		OS.execute("pkill", ["-x", "steam"], [])
		await get_tree().create_timer(1.5).timeout
		if OS.execute("pgrep", ["-x", "steam"], []) == 0:
			OS.execute("pkill", ["-9", "-x", "steam"], [])
	_steam_stopping = false
	if _steam_virtual:
		_kill_xvfb()
		_steam_virtual = false
	playtimes.clear()
	_load_playtimes()
	for g in games:
		g["playtime"] = playtimes.get(str(g["id"]), g["playtime"])

func _pop(tile: Control, big: float) -> void:
	Haptics.launch() if tile != tiles[tiles.size() - 1] else Haptics.tick()
	if tile != tiles[tiles.size() - 1]:
		sfx.play("launch")
	var pop := create_tween()
	if not Motion.on():
		tile.scale = Vector2.ONE * big
		return
	pop.tween_property(tile, "scale", Vector2.ONE * 1.04, 0.08).set_trans(Tween.TRANS_SINE)
	pop.tween_property(tile, "scale", Vector2.ONE * big, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await pop.finished

func _launch(force_gi := -1, force_game := {}) -> void:
	if launching:
		if not force_game.is_empty():
			toast.show_toast(Icons.texture("info", Icons.svg_info(), 40), "Quit %s first" % _game_title, false)
			return
		# Home is showing over a paused game: its own tile resumes it, nothing else starts.
		if _in_overlay and _overlay_mode == "home" and not _overlay_busy:
			var gi0 := force_gi if force_gi >= 0 else _game_selected()
			if force_gi < 0 and _library_selected():
				await _pop(tiles[selected], 1.1)
				library.open(clock_label.get_global_rect())
				return
			if gi0 >= 0 and str(games[gi0]["id"]) == _game_id:
				_overlay_close()  # it is the game being played: straight back into it, fading in (Close game is in the control center)
			elif gi0 >= 0:
				if _from_library:
					_from_library = false
					_switch_game(gi0)  # Play on its page: ask, then close this game and start that one
				else:
					library.open_game(games[gi0], null)  # its page first, with Play
		return
	var direct := not force_game.is_empty()  # the browser: a program started by Tephra itself, not a Steam game
	if not direct and force_gi < 0 and _home_selected():
		return
	if not direct and force_gi < 0 and _library_selected():
		await _pop(tiles[selected], 1.1)
		library.open(clock_label.get_global_rect())
		return
	var gi := force_gi if force_gi >= 0 else _game_selected()
	if gi < 0 and not direct:
		return
	var g: Dictionary = force_game if direct else games[gi]
	if not direct:
		preload("res://mods.gd").quiet_reframework(_steam_libs())  # REFramework's menu stays closed
	launching = true
	_au_active = false  # the game comes first: updates pause and pick up again later
	_last_launch_id = str(g["id"])
	_tl_start("launch " + str(g["id"]) + " " + str(g["title"]) + (" (Steam already open)" if _steam_running() else " (Steam closed, cold start)"))
	sfx.set_music("", false)  # the music fades out as the game starts
	var id: String = str(g["id"])
	cc.game_running = true
	if direct and g.has("pattern"):
		_extra_exe[id] = str(g["pattern"])
	if force_gi < 0 and not direct:
		await _pop(tiles[selected], 1.18)  # "click" feedback before the fade
	# The loading screen (artwork, name, logo) is set up first and fades in as one picture over the cover's
	# click animation: no stop on black or on the Home background in between.
	launch_art.texture = null if direct else hero.texture
	launch_art.modulate = Color(1, 1, 1, 0.35)
	launch_art.visible = true
	launch_label.text = "Preparing " + g["title"] + "..."
	launch_label.modulate.a = 1.0
	launch_logo.texture = null
	launch_logo.modulate.a = 0.0
	launch_logo.visible = true
	launch_overlay.modulate.a = 0.0
	launch_overlay.visible = true
	var fade := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(launch_overlay, "modulate:a", 1.0, Motion.dur(0.5))
	_load_art(id, "logo", launch_logo, "png", func() -> void:
		if launching and launch_label.text.begins_with("Preparing "):
			launch_label.text = "Preparing..."  # the logo already says which game
		create_tween().tween_property(launch_logo, "modulate:a", 1.0, 0.5))
	await fade.finished
	steam_rule(true)  # keep Steam's loading popups behind Tephra
	overlay.hold_loading(true)  # the game opens under the loading screen, which then fades into it
	DisplayCtl.send_games_here(true)  # the game opens on the screen Tephra is on
	_launch_cancel = false
	_launch_cancellable = true
	_show_launch_hint()
	_bar_show(true)
	_bar_to(0.08)
	if direct:
		var cmd: Array = g["cmd"]
		OS.create_process(str(cmd[0]), cmd.slice(1))
		_tl("started " + str(cmd[0]))
		if g.get("browser", false):
			browser.start()
			browser.unmute_later()
	else:
		# A Steam that is already open without Tephra's layout for this game is restarted (once). Non-Steam games are
		# listed in Steam's layout index by their own name in lower case.
		await _pads_ready_for_game(str(g.get("orig_title", g["title"])).to_lower() if bool(g.get("nonsteam", false)) else str(g["id"]))
		await steam_open(_game_url(g))
		_tl("link sent to Steam")
		_apply_game_fix(id)  # starts watching for the game window right away
		_dismiss_steam_dialogs(id)  # answers a dialog Steam may put up (and nobody could see)
	_bar_to(0.25)  # Steam is up and has the game

	# Wait up to 3 minutes for the game to start (first runs can be slow).
	var waited := 0.0
	var started := false
	var resends := 0
	var busy_note := ""
	var steam_seen := -1.0   # when Steam's process showed up
	var ui_seen := -1.0      # when Steam's window helper showed up: from then on it really takes links
	var last_send := 0.0
	while waited < 180.0 or (busy_note != "" and waited < 900.0):  # a game or Steam runtime that is still downloading gets up to 15 minutes
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		if _launch_cancel:
			break
		if _game_running(id):
			started = true
			_tl("game process running")
			break
		if steam_seen < 0.0 and _steam_running():
			steam_seen = waited
			_tl("Steam process up")
		if ui_seen < 0.0 and steam_seen >= 0.0 and OS.execute("pgrep", ["-x", "steamwebhelper"], []) == 0:
			ui_seen = waited
			_tl("Steam finished loading (steamwebhelper up)")
		# No real percentage comes from Steam, so the bar creeps on and slows down the longer it takes (never full).
		_bar_to(0.25 + 0.65 * (1.0 - exp(-waited / 14.0)))
		if direct:
			if waited >= 60.0:
				break  # it never started
			continue
		steam_resend_if_dead(_game_url(g))
		# A link sent while Steam was still starting up is often dropped (Steam is running, nothing happens).
		# Sending it again once Steam is up is what makes games like Portal or Hotline Miami start.
		# Re-sent 4 s after Steam has finished loading (not 25 s blind), then every 15 s, at most 3 times.
		var due := ui_seen >= 0.0 and waited - maxf(ui_seen, last_send) >= (4.0 if resends == 0 else 15.0)
		if resends < 3 and (due or (ui_seen < 0.0 and waited >= 30.0 * (resends + 1))) and _steam_running() and not _steam_stopping:
			last_send = waited
			busy_note = _steam_busy_with(id)
			if busy_note == "":
				resends += 1
				_install_log("launch %s: nothing started after %d s, sending the link again (%d)" % [id, int(waited), resends])
				_steam_cmd(STEAM_ARGS + [_game_url(g)])
				_tl("link sent again (%d)" % resends)
		if int(waited * 2.0) % 10 == 0:
			busy_note = _steam_busy_with(id)
			launch_label.text = ("Preparing " + g["title"] + "...") if busy_note == "" else (str(g["title"]) + ": " + busy_note)
	_launch_cancellable = false
	if _launch_cancel:
		await get_tree().create_timer(0.35).timeout  # let the Cancel button's press show
	launch_hint.visible = false
	if started:
		_bar_to(1.0)
		await get_tree().create_timer(0.5).timeout
		_release_hold_later(id)
	else:
		overlay.let_go()  # no game window to fade into: just stop keeping Tephra on top, no fade
	_bar_show(false)
	if _launch_cancel:
		await _cancel_launch(id, str(g["title"]))
		return
	if not started:
		_write_launch_log(id, str(g["title"]))
		await _launch_message("Couldn't start " + g["title"] + ". Details: ~/.config/tephra/launch.log")
		return
	_remember_launch(g)  # just played: goes to the front of the row now, not only after the game has ended
	_game_id = id
	_game_title = str(g["title"])
	_game_started = true
	_game_started_ms = Time.get_ticks_msec()
	_quit_now = false
	weather.fetch(false)  # fresh for when the player comes back
	cc.game_id = id
	overlay.log_line("game %s is running; PS opens the menu (virtual keyboard %s, KWin script %s)" % [id, str(overlay.vkey_ok), str(overlay.kwin_ok)])
	var play_started := Time.get_ticks_msec()
	perf.start(id, str(g["title"]))
	# The "Preparing" screen melts into plain black while Tephra is still drawing, then Home is hidden and a
	# couple of black frames are drawn before drawing stops. Whatever the desktop shows of Tephra's window
	# while the game's window takes over is that black frame, never Home or a half-faded picture.
	if Motion.on():
		var out := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		out.tween_property(launch_art, "modulate:a", 0.0, 0.5)
		out.tween_property(launch_label, "modulate:a", 0.0, 0.5)
		out.tween_property(launch_logo, "modulate:a", 0.0, 0.5)
		await out.finished
	launch_label.text = ""
	launch_label.modulate.a = 1.0
	launch_art.visible = false
	launch_logo.visible = false
	launch_overlay.visible = true
	launch_overlay.modulate.a = 1.0
	visible = false
	_trim_gpu_memory()
	# Five frames, not three: the GPU only really frees what was let go of a few frames later, and once the
	# render loop is switched off (next line) nothing would be freed until the next menu.
	for _f in 5:
		await RenderingServer.frame_post_draw
	_set_game_active(true)  # nothing of Tephra needs the GPU while the game runs
	# Stay black behind the game until it exits, or until the player closes it: then Home comes back at once and
	# the game is shut down behind it (see _quit_game), so nobody waits on a "Closing" screen.
	_tl("game on screen")
	_lag_probe(id)
	while _game_running(id) and not _quit_now:
		for _k in 4:
			await get_tree().create_timer(0.25).timeout
			if _quit_now:
				break
		if not _quit_now and not _game_running(id):
			# Some games start through a small launcher that hands over to the real game a moment later (Steam's
			# process for it is gone for a few seconds). Only a game that stays gone for 15 s has really exited.
			for _g in 30:
				await get_tree().create_timer(0.5).timeout
				if _quit_now or _game_running(id):
					break
	var played_secs := (Time.get_ticks_msec() - play_started) / 1000
	var closed_early := not _quit_now and played_secs < 90
	_tl_start("close " + id + (" (Quit game)" if _quit_now else " (the game exited)"))
	perf.stop()
	_tl("game gone, Tephra coming back")
	Sessions.add(id, float(Time.get_ticks_msec() - play_started) / 60000.0)
	if closed_early:
		_write_early_exit_log(id, str(g["title"]), played_secs)
	details.fill_perf()
	DisplayServer.window_move_to_foreground()
	if overlay.kwin_ok:
		overlay.reveal_tephra()  # never leave Tephra see-through
	if Themes.id() == "neon":
		# Miami: a sunset score screen (made-up stats, the real play time, always an A+) before Home comes back.
		var score := preload("res://miami_score.gd").new()
		add_child(score)
		await score.run(float(Time.get_ticks_msec() - play_started) / 60000.0, sfx)
		_tl("Miami score screen done")
	_return_home()
	if closed_early:
		# No more silent returns to the menu: say what happened, and where the details are.
		notify("%s closed %d seconds after starting. Details: ~/.config/tephra/launch.log" % [str(g["title"]), played_secs])

## A game that has started is the most recently played one: it moves to the first slot of the Home row right away, so
## Home shown over the paused game (and every later visit) has it first. The time is also kept in Tephra's own settings,
## because Steam only writes a non-Steam game's last-played time much later, and a reload of the games would put it back.
func _remember_launch(g: Dictionary) -> void:
	if not games.has(g):
		return  # the browser and other programs Tephra starts itself are not games on the row
	var now := int(Time.get_unix_time_from_system())
	g["last"] = now
	var seen: Dictionary = Settings.get_value("launched_at", {}).duplicate()
	seen[str(g["id"])] = now
	Settings.set_value("launched_at", seen)
	games.sort_custom(_sort_games)
	_build_row()
	var t := 1 if tiles.size() > 2 else 0
	for j in tile_game.size():
		if tile_game[j] >= 0 and str(games[tile_game[j]]["id"]) == str(g["id"]):
			t = j
	_select(t, false)
	if channels != null:
		channels.rebuild()  # the theme's own Home reads the order too

## Lets go of the pictures Tephra only keeps so that scrolling back and forth is instant: the art cache holds up
## to 40 big hero and cover images, and almost none of them are on screen. A 4 GB card has
## little room to spare for a heavy game, so they go as a game starts. What is on screen keeps its own copy, and
## anything else is decoded again, on a worker thread, the next time it is needed (_tex_async does that).
func _trim_gpu_memory() -> void:
	var n := _art_cache.size()
	_art_cache.clear()
	_art_order.clear()
	overlay.log_line("game starting: let go of %d cached pictures to leave the GPU's memory to the game" % n)

var _probe_task := -1

## Developer aid for "this game runs worse through Tephra than from Steam": when the file ~/.config/tephra/lag_probe
## exists, Tephra writes nvidia-smi's full report (which programs hold how much GPU memory) to
## ~/.config/tephra/overlay.log once, 30 s into the game. Only one call, so the game feels at most one small hitch.
func _lag_probe(id: String) -> void:
	if _probe_task != -1 or not FileAccess.file_exists(OS.get_environment("HOME") + "/.config/tephra/lag_probe"):
		return
	await get_tree().create_timer(30.0).timeout
	if not _game_started or _game_id != id or _in_overlay or _probe_task != -1:
		return
	_probe_task = _work(func() -> void:
		var out: Array = []
		OS.execute("nvidia-smi", [], out)
		_lag_probe_done.call_deferred(id, str(out[0]) if not out.is_empty() else "nvidia-smi gave no answer"))

func _lag_probe_done(id: String, report: String) -> void:
	_work_done(_probe_task)
	_probe_task = -1
	overlay.log_line("lag probe, %s, 30 s into the game:\n%s" % [id, report])

var launch_bar: Panel
var _launch_fill: Panel
var _bar_target := 0.0
var _bar_shown := 0.0

## Moves the launch bar towards p (0..1). It always glides, never jumps, and never goes backwards.
func _bar_to(p: float) -> void:
	_bar_target = maxf(_bar_target, clampf(p, 0.0, 1.0))

const QUIPS := [
	"Loading loading screens...", "Loading your patience...", "Deleting save data...", "Killing innocent NPCs...",
	"Finding more reasons to load...", "Wondering if this loading bar is purely decorative...", "Deleting all games in library...",
	"Also try Steam!", "Wondering why RAM is so overpriced...", "Downgrading to update 0.01...", "Fix your posture.....",
	"Downloading spyware...", "Downloading free RAM...", "Uncooking spaghetti code...", "Burning pixels into your screen...",
	"Considering crashing...", "Fatal system error...", "sudo rm -rd /", "Deleting System32...", "Watching out for enemies...",
	"Counting every loading tip twice...", "Asking the game nicely...",
	"Reticulating splines...", "Teaching the NPCs to blink...", "Polishing the polygons...", "Inflating the loading bar...",
	"Bribing the graphics card...", "Convincing the shaders to compile...", "Feeding the hamsters that run the server...",
	"Looking for the any key...", "Turning it off and on again...", "Blowing into the cartridge...", "Rewinding the tape...",
	"Defragmenting the floppy disk...", "Downloading more storage...", "Asking Clippy for advice...",
	"Spawning the spawn point...", "Respawning the respawn timer...", "Calibrating the fun...", "Adding extra lag, just in case...",
	"Hiding the secret level...", "Dusting off the achievements...", "Untangling the controller cable...",
	"Charging the controller (it's wireless, we checked)...", "Pretending to do something useful...",
	"Generating a witty loading message...", "Loading the loading message...", "Almost there. Probably...",
	"Still loading. Still better than a mobile ad...", "Warming up the textures...", "Sharpening the pixels...",
	"Telling the boss fight to wait outside...", "Moving the crates around...", "Looking for a save point...",
	"Stirring the RNG...", "Checking if the cake is a lie...", "Thinking of a good tip...", "Skipping leg day for the framerate...",
	"Waking up the final boss...", "Lowering the difficulty by 0.0001%...", "Crunching a very small number...",
	"Loading... please don't blink", "Counting the polygons in Lara's hair...", "Looking behind the couch for the disc...",
	"Putting the fun in fundamentals...", "Reversing the polarity...", "Updating the update that updates updates...",
	"Reading the manual (nobody does)...", "Hitting the loading bar with a hammer...", "Searching for lost frames...",
	"Making the grass greener...", "Buffering the buffer...", "Shuffling the loot table...", "Rolling for initiative...",
	"Mining some virtual diamonds...", "Petting the loading cat...", "Applying the finishing touches to the start screen...",
]
const QUIP_LOST := ["homework", "memories", "tax records", "passwords", "family photos", "cookie recipes", "save files",
	"vacation plans", "browser history", "your high score", "the good ending"]
var launch_quip: Label
var _quip_t := 99.0
var _quip_last := ""
var _quip_next_counts := false  # the joke just picked is the error counter
var _quip_counting := false     # the error counter is on screen: its number keeps climbing
var _quip_errs := 0.0
var _quip_hold := 3.8           # how long the joke on screen stays (the error counter gets a second more)

## The next joke: mostly from the list, now and then the error counter (it climbs with the bar) or something "important" deleted.
func _next_quip() -> String:
	var r := randi() % 8
	_quip_next_counts = false
	if r == 0:
		_quip_next_counts = true
		return "Writing %d error codes..." % (1000 + int(_bar_shown * 99000.0))
	if r == 1:
		return "Deleting important %s..." % QUIP_LOST[randi() % QUIP_LOST.size()]
	var q: String = QUIPS[randi() % QUIPS.size()]
	return q if q != _quip_last else QUIPS[(QUIPS.find(q) + 1) % QUIPS.size()]

func _bar_step(delta: float) -> void:
	if launch_bar == null or not launch_bar.visible:
		return
	_quip_t += delta
	if _quip_t >= _quip_hold and launch_quip != null:
		_quip_t = 0.0
		_quip_counting = false
		_quip_last = _next_quip()
		var counts := _quip_next_counts
		_quip_hold = 4.8 if counts else 3.8
		var qt := create_tween()
		qt.tween_property(launch_quip, "modulate:a", 0.0, 0.25)
		qt.tween_callback(func() -> void:
			launch_quip.text = _quip_last
			_quip_errs = float(1000 + int(_bar_shown * 99000.0))
			_quip_counting = counts)
		qt.tween_property(launch_quip, "modulate:a", 0.8, 0.35)
	if _quip_counting:
		# The number climbs while it is on screen: always at least as far as the bar has got, and ticking up on its own.
		_quip_errs = maxf(_quip_errs + delta * (200.0 + _bar_shown * 700.0), 1000.0 + _bar_shown * 99000.0)
		launch_quip.text = "Writing %d error codes..." % int(_quip_errs)
	_bar_shown = lerpf(_bar_shown, _bar_target, 1.0 - exp(-delta * 4.0))
	_launch_fill.size = Vector2(launch_bar.size.x * _bar_shown, launch_bar.size.y)

func _bar_show(on: bool) -> void:
	if on:
		_bar_target = 0.0
		_bar_shown = 0.0
		_launch_fill.size.x = 0.0
		launch_bar.modulate.a = 0.0
		launch_bar.visible = true
		create_tween().tween_property(launch_bar, "modulate:a", 1.0, 0.8)
		_quip_t = 99.0  # the first joke comes straight away
		_quip_counting = false
		_quip_hold = 3.8
		launch_quip.text = ""
		launch_quip.visible = true
	elif launch_bar.visible:
		var tw := create_tween()
		tw.tween_property(launch_bar, "modulate:a", 0.0, 0.5)
		tw.parallel().tween_property(launch_quip, "modulate:a", 0.0, 0.5)
		tw.tween_callback(func() -> void:
			launch_bar.visible = false
			launch_quip.visible = false)

# The Cancel button on the launch screen shrinks and springs back when pressed, like the tiles do.
func _pulse_cancel() -> void:
	if launch_hint.get_child_count() == 0:
		return
	var g: Control = launch_hint.get_child(0)
	g.pivot_offset = g.size / 2.0
	var tw := create_tween()
	tw.tween_property(g, "scale", Vector2.ONE * 0.78, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "scale", Vector2.ONE * 1.15, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)

func _show_launch_hint() -> void:
	for c in launch_hint.get_children():
		launch_hint.remove_child(c)
		c.queue_free()
	launch_hint.add_child(TephraGlyphs.glyph("back", 44))
	var l := _label("Cancel", 30, TEXT)
	launch_hint.add_child(l)
	launch_hint.modulate.a = 0.0
	launch_hint.visible = true
	create_tween().tween_property(launch_hint, "modulate:a", 1.0, 0.8)

# B on the launch screen: stop the launch and go back Home. Steam may already have started the game's
# own processes, or may be about to (first-run setup), so for a few seconds anything that belongs to
# this game is stopped as it shows up. Steam itself is closed afterwards unless it is downloading.
func _cancel_launch(id: String, title: String) -> void:
	_install_log("launch %s: cancelled by the player" % id)
	_cancel_flow = true
	overlay.let_go()
	# Cancelling looks like starting: the game's picture and logo stay, the words change, and the bar fills again
	# while Steam lets go of the game. Then it all fades back Home.
	var out := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	out.tween_property(launch_label, "modulate:a", 0.0, Motion.dur(0.3))
	await out.finished
	launch_label.text = "Cancelling..." if launch_logo.visible and launch_logo.texture != null else "Cancelling " + title + "..."
	create_tween().tween_property(launch_label, "modulate:a", 1.0, Motion.dur(0.35))
	await get_tree().create_timer(0.55).timeout  # the old bar has faded out
	_bar_show(true)
	var pat := "net.pcsx2.PCSX2" if _game_is_ps2(id) else str(_extra_exe.get(id, ""))
	_kill_late(id, pat)  # Steam can still start a game it had queued after this: watched for a while longer
	for i in 12:
		OS.execute("pkill", ["-f", "[S]teamLaunch AppId=" + id + " "], [])
		if pat != "":
			OS.execute("pkill", ["-f", pat], [])
		_bar_to(float(i + 1) / 12.0)
		await get_tree().create_timer(0.5).timeout
	_bar_to(1.0)
	await get_tree().create_timer(0.4).timeout
	_bar_show(false)
	var swap := create_tween().set_trans(Tween.TRANS_SINE)
	swap.tween_property(launch_label, "modulate:a", 0.0, Motion.dur(0.25))
	await swap.finished
	launch_label.text = "Cancelled."
	swap = create_tween().set_trans(Tween.TRANS_SINE)
	swap.tween_property(launch_label, "modulate:a", 1.0, Motion.dur(0.3))
	await get_tree().create_timer(0.8).timeout
	var fade := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(launch_art, "modulate:a", 0.0, Motion.dur(0.5))
	fade.tween_property(launch_logo, "modulate:a", 0.0, Motion.dur(0.5))
	fade.tween_property(launch_label, "modulate:a", 0.0, Motion.dur(0.5))
	await fade.finished
	launch_art.visible = false
	launch_logo.visible = false
	launch_label.text = ""
	launch_label.modulate.a = 1.0
	await _return_home(1.2)
	_close_leftovers()
	_cancel_flow = false

## After a cancel, for 45 s: if the game (or its emulator / program) starts anyway, it is closed at once.
## Non-Steam games are handed to Steam, which can start them several seconds after the cancel.
var _cancel_flow := false

func _kill_late(id: String, pat: String) -> void:
	var until := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < until:
		await get_tree().create_timer(1.0).timeout
		if launching and not _cancel_flow:
			return  # a new launch (maybe this same game, on purpose) takes over
		var hit := OS.execute("pgrep", ["-f", "[S]teamLaunch AppId=" + id + " "], []) == 0 or (pat != "" and OS.execute("pgrep", ["-f", pat], []) == 0)
		if hit:
			_install_log("launch %s: started after it was cancelled, closing it" % id)
			overlay.quit_game(id, pat)
			await get_tree().create_timer(9.0).timeout

# ---------- Menus over a running game ----------
# PS (short) while a game runs: take a picture of the game, freeze it (it stops exactly where it is, sound
# and all), bring Tephra to the front and show the control center over a blurred copy of that picture.
# PS again (or B) unfreezes the game and gives the screen back. PS (held) does the same but shows
# Home, where the game's own tile resumes it. Nothing here ever closes the game: only the Quit game
# card does that, after asking.
func _overlay_power(menu_visible: bool) -> void:
	_menu_boost = false  # the menu is up (normal rate) or the game has the screen again (idle rate)
	_game_active = not menu_visible
	RenderingServer.render_loop_enabled = menu_visible  # drawing only while a menu is up
	if not menu_visible and dev_layer != null:
		dev_layer.visible = false
	_power_apply()

func _overlay_open(mode: String) -> void:
	if not _game_started or _overlay_busy:
		return
	browser.halt()  # the pointer stops while a menu is open
	if _in_overlay:
		# Already paused: just change what is showing.
		if cc.is_open:
			cc.close(true)
		_overlay_mode = mode
		if mode == "home":
			_show_overlay_home()
		else:
			overlay.mute_game(_game_id, false)
		return
	_overlay_busy = true
	var id := _game_id
	overlay.log_line("opening the %s menu over %s" % [mode, id])
	var t0 := Time.get_ticks_msec()
	# The control center sits over a blurred picture of the game. The Home menu (held PS) has its own
	# background and needs none. The picture is taken first, then the game is frozen.
	var live := false  # the "live game" background option is gone (it never worked well); the menu always uses a picture
	var tex: Texture2D = null
	_overlay_shot = null
	launch_sharp.texture = null
	launch_sharp.visible = false
	var picture_later := mode == "cc" and not live
	if mode == "kbd" and not live:
		# The keyboard sits over the page itself, sharp, so it waits a moment for the picture. (The control center
		# never waits: it opens over the plain dark screen and the picture slides in behind it, see _shot_behind_menu.)
		var shot: Image = await overlay.screenshot(SHOT_WAIT_MS)
		overlay.log_line("menu timing: picture ready after %d ms" % (Time.get_ticks_msec() - t0))
		if shot != null:
			_overlay_shot = shot  # kept sharp, for a photo taken while the menu is open
			tex = ImageTexture.create_from_image(shot) if mode == "kbd" else _blurred(ImageTexture.create_from_image(shot))  # the keyboard sits over the page itself, sharp
		else:
			tex = _game_art_backdrop(id)
			_late_shot()  # the frozen game slides in behind the menu the moment its picture is ready
	# Settings > System > Games: the game is paused (frozen) behind the menu, or keeps running with its sound.
	# PCSX2 keeps reading the controller even behind the menu, so a PS2 game is always paused.
	if mode == "kbd" or (mode != "page" and (not bool(Settings.get_value("cc_keep_running2", true)) or _game_is_ps2(id))):
		overlay.freeze_game(id, _game_pattern())
	_overlay_live = live
	if live:
		# The black launch screen must go, or the see-through menu would sit on black instead of the game.
		launch_overlay.visible = false
		launch_overlay.modulate.a = 0.0
	launch_art.texture = tex
	launch_art.modulate = Color(0.78, 0.8, 0.84, 1.0)  # a touch darker, so the cards stand out
	launch_art.visible = tex != null
	launch_label.text = ""
	launch_hint.visible = false
	_overlay_power(true)
	# No black flash: Tephra comes to the front almost invisible (the game still shows), draws a few
	# frames, and only then becomes visible: fully, or "glass" (see-through) in live mode.
	# The menu is built and drawn first, then one call into the desktop raises Tephra and shows it at once
	# (it used to be two calls, raise nearly invisible and then reveal, and each one can take a few hundred
	# ms while a game is busy on the GPU). Two drawn frames make sure the window never shows an old picture.
	_in_overlay = true
	_overlay_mode = mode
	if mode == "home":
		_show_overlay_home()
	elif mode == "tabs":
		browser_tabs.open(_tabs_seen.get("tabs", []), int(_tabs_seen.get("current", 0)))
	elif mode == "kbd":
		pass  # the caller opens the keyboard over the frozen page
	else:
		_open_cc()
	overlay.log_line("menu timing: built after %d ms" % (Time.get_ticks_msec() - t0))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	overlay.log_line("menu timing: drawn after %d ms" % (Time.get_ticks_msec() - t0))
	if picture_later:
		_pic_ready = false
		_pic_instant = true
		_shot_behind_menu(mode, t0)
		# The menu shows up with the game's picture already behind it when that is only a moment away: showing it first
		# over plain black and fading the picture in a little later looked like a black flash. A late picture still
		# never holds the menu up for longer than PICTURE_WAIT_MS.
		# It also never shows before the picture has been taken at all (overlay.shot_taken): a menu that came up first
		# was itself in the picture, black, which is what a quick tap of PS used to give.
		var until := Time.get_ticks_msec() + PICTURE_WAIT_MS
		while not _pic_ready:
			var now := Time.get_ticks_msec()
			if now - t0 >= SHOT_TAKEN_MAX_MS or (now >= until and overlay.shot_taken()):
				break
			await get_tree().process_frame
		overlay.log_line("menu timing: picture %s when the menu was shown (%d ms)" % ["there" if _pic_ready else "not there yet", Time.get_ticks_msec() - t0])
	_pic_instant = false  # from here on the menu may be on screen: a picture that arrives now fades in
	await overlay.run_shortcuts(["TephraShowGlass" if live else "TephraShow"])
	DisplayServer.window_move_to_foreground()  # a second, polite ask
	overlay.log_line("menu timing: revealed (%s) after %d ms" % ["live" if live else "picture", Time.get_ticks_msec() - t0])
	_overlay_busy = false
	overlay.log_line("menu timing: menu showing after %d ms" % (Time.get_ticks_msec() - t0))

func _late_shot() -> void:
	var shot: Image = await overlay.screenshot_late(5000)
	if shot == null or not _in_overlay or _overlay_live:
		return
	_overlay_shot = shot
	var tex := _blurred(ImageTexture.create_from_image(shot))
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(launch_art, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func() -> void:
		launch_art.texture = tex
		launch_art.visible = true)
	tw.tween_property(launch_art, "modulate:a", 1.0, 0.3)

const UNBLUR_S := 0.24     # leaving a menu: the blur melts into the sharp picture of the game
const FADE_BACK_S := 0.2   # then Tephra's window melts away into the live game
const SHOT_TAKEN_MAX_MS := 1000  # if Spectacle never takes the picture, the menu still shows after this long
const PICTURE_WAIT_MS := 140  # longest the control center waits, once it is drawn, for the game's picture to be behind it
var _pic_ready := false
var _pic_instant := false  # the menu is not on screen yet, so the picture can simply be there
const SHOT_WAIT_MS := 1100  # longest the menu waits for the game's picture (from the PS button going down); the grab takes about 0.75 s here
var _overlay_shot: Image     # the sharp picture of the game behind the open menu

## When the game's picture is late: its big artwork, blurred the same way, behind the menu.
func _game_art_backdrop(id: String) -> Texture2D:
	var path := _find_local_art(id, "library_hero")
	if path == "" and FileAccess.file_exists("user://art/%s_library_hero.jpg" % id):
		path = "user://art/%s_library_hero.jpg" % id
	var t := _tex(path) if path != "" else null
	return _blurred(t) if t != null else null

## The game's picture slides in behind the open control center once it is ready, blurred on a worker thread, so
## neither the grab nor the blur ever holds the menu up.
func _shot_behind_menu(mode: String, t0: int) -> void:
	var shot: Image = await overlay.screenshot(3000)
	if shot == null:
		shot = await overlay.screenshot_late(3000)
	if not _in_overlay or _overlay_mode != mode:
		_pic_ready = true
		return
	if shot == null:
		# No picture at all: the menu stays on its dark background. The game's store artwork was used here for a while,
		# but a cover where the game should be looked wrong, and a new grab now would only catch Tephra's own window.
		overlay.log_line("menu background: no picture of the game arrived, staying dark")
		_pic_ready = true
		return
	_overlay_shot = shot  # kept sharp, for a photo taken while the menu is open
	var box := {}
	var src := shot.duplicate() as Image
	var id := _work(func() -> void:
		var out := _blur_image(src, false)
		box["img"] = out)  # last: the loop below waits for this one
	while not box.has("img"):
		await get_tree().process_frame
	_work_done(id)
	if not _in_overlay or _overlay_mode != mode:
		_pic_ready = true
		return
	if box["img"] == null:
		_pic_ready = true
		return
	launch_art.texture = ImageTexture.create_from_image(box["img"])
	launch_art.visible = true
	launch_sharp.texture = ImageTexture.create_from_image(shot)  # ready for the unblur when the menu closes
	launch_sharp.visible = false
	if _pic_instant:
		launch_art.modulate = Color(0.78, 0.8, 0.84, 1.0)  # the menu is not showing yet: it appears with the picture already there
	else:
		launch_art.modulate = Color(0.78, 0.8, 0.84, 0.0)  # a touch darker, so the cards stand out
		_fade_in_backdrop()
	_pic_ready = true
	overlay.log_line("menu timing: picture behind the menu after %d ms%s" % [Time.get_ticks_msec() - t0, " (before the menu showed)" if _pic_instant else ""])

## A picture that arrives after the menu is already showing melts in slowly out of the dark, so it never reads as a snap.
const BACKDROP_FADE_S := 0.45

func _fade_in_backdrop() -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(launch_art, "modulate:a", 1.0, Motion.dur(BACKDROP_FADE_S))

# A soft blur of a picture, made by shrinking it in halves (each half averages 2x2 pixels) and
# stretching it back up smoothly. Touches no scene, so it can also run on a worker thread.
static func _blur_image(src: Image, upsize := true) -> Image:
	if src == null or src.is_empty():
		return null
	var img := src
	var w := img.get_width()
	var h := img.get_height()
	img.convert(Image.FORMAT_RGB8)
	while img.get_width() > 320:  # smaller = blurrier (it was 160)
		img.resize(maxi(img.get_width() / 2, 1), maxi(img.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
	if not upsize:
		return img  # the screen stretches the small picture smoothly itself: one step less before the menu can show it
	var w2 := mini(w, 1280)
	img.resize(w2, maxi(roundi(float(h) * w2 / maxf(w, 1.0)), 1), Image.INTERPOLATE_CUBIC)
	return img

func _blurred(tex: Texture2D) -> Texture2D:
	var img := tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		return tex
	var out := _blur_image(img)
	return ImageTexture.create_from_image(out) if out != null else tex

func _show_overlay_home() -> void:
	# The black screen melts away instead of vanishing.
	if launch_overlay.visible and launch_overlay.modulate.a > 0.01:
		var melt := create_tween()
		melt.tween_property(launch_overlay, "modulate:a", 0.0, Motion.dur(0.35))
		melt.tween_callback(func():
			if _in_overlay:
				launch_overlay.visible = false)
	else:
		launch_overlay.visible = false
		launch_overlay.modulate.a = 0.0
	TephraBg.paused = false
	visible = true
	overlay.mute_game(_game_id, true, _game_pattern())  # Home is silent; the game's own control center is not
	overlay.freeze_game(_game_id, _game_pattern())  # and the game is paused (frozen) until you resume it
	var t := 1 if not games.is_empty() else 0
	for i in games.size():
		if str(games[i]["id"]) == _game_id and tile_game.find(i) >= 0:
			t = tile_game.find(i)
	_select(t, false)
	toast.show_toast(Icons.texture("info", Icons.svg_info(), 40), "%s is paused. Choose it to resume." % _game_title, false)

func _overlay_close() -> void:
	if not _in_overlay or _overlay_busy:
		return
	_overlay_busy = true
	var id := _game_id
	sfx.set_music("", false)  # back to the game: the menu music fades out
	_placing_perf = false
	if _place_hint != null:
		_place_hint.visible = false
	if overlay.kwin_ok and Motion.on() and not _overlay_live:
		# Crossfade back into the game: it is woken (and its sound let through) first, so it is already moving again
		# underneath while Tephra's window melts away over it. The menu stays as it is until it is fully gone.
		_in_overlay = false
		if _game_id == browser.ID:
			browser.unmute_later()
		overlay.wake_game()  # running (and heard) again right away, off Tephra's frames
		if launch_sharp.texture != null and launch_art.visible:
			# The blur melts into the sharp, full-quality picture of the game, drawn by Tephra itself at full frame rate,
			# while the menu fades. Only then does the window hand over to the live game, which looks almost the same.
			_boost_for_menu()
			launch_sharp.modulate = Color(0.78, 0.8, 0.84, 0.0)
			launch_sharp.visible = true
			var un := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			un.tween_property(launch_sharp, "modulate", Color.WHITE, Motion.dur(UNBLUR_S))
			await un.finished
		await overlay.fade_into_game(FADE_BACK_S)
		if cc.is_open:
			cc.close(true)
		if browser_tabs.is_open:
			browser_tabs.close("_quiet")
		if album.is_open:
			album.close()
		if mods.is_open:
			mods.close()
		launch_overlay.visible = true
		launch_overlay.modulate.a = 1.0
		visible = false
		launch_art.visible = false
		launch_art.modulate = Color.WHITE
		launch_sharp.visible = false
		launch_sharp.texture = null  # the game gets that memory back
		launch_label.text = ""
		TephraBg.paused = true
		_overlay_power(false)
		_overlay_busy = false
		overlay.log_line("resumed %s (unblurred and faded back in)" % id)
		return
	if cc.is_open:
		cc.close(true)
	if browser_tabs.is_open:
		browser_tabs.close("_quiet")
	if album.is_open:
		album.close()
	if mods.is_open:
		mods.close()
	if _overlay_mode == "home":
		# Fade to black first, so going back into the game is smooth instead of a cut.
		launch_overlay.visible = true
		launch_overlay.modulate.a = 0.0
		var to_black := create_tween()
		to_black.tween_property(launch_overlay, "modulate:a", 1.0, Motion.dur(0.3))
		await to_black.finished
	if _overlay_live and _overlay_mode != "home":
		# Live menu: the game is right behind it, so just let the menu fade and hand the game back (no black).
		await get_tree().create_timer(Motion.dur(0.18)).timeout
	elif _overlay_mode != "home":
		# Picture menu: ease into black instead of cutting to it.
		launch_overlay.visible = true
		var to_black2 := create_tween()
		to_black2.tween_property(launch_overlay, "modulate:a", 1.0, Motion.dur(0.2))
		await to_black2.finished
	launch_overlay.visible = not _overlay_live or _overlay_mode == "home"
	launch_overlay.modulate.a = 1.0 if launch_overlay.visible else 0.0
	visible = false
	_in_overlay = false
	overlay.mute_game(_game_id, false)
	overlay.thaw_game()  # the game carries on from the frame it stopped on
	if _game_id == browser.ID:
		browser.unmute_later()
	await overlay.run_shortcuts(["TephraReturn"])
	launch_art.visible = false
	launch_art.modulate = Color.WHITE
	launch_label.text = ""
	TephraBg.paused = true
	_overlay_power(false)
	_overlay_busy = false
	overlay.log_line("resumed %s" % id)

# The game ended (or was quit) while a menu may have been open: put everything back.
func _overlay_reset() -> void:
	_placing_perf = false
	launch_sharp.visible = false
	launch_sharp.texture = null
	if _place_hint != null:
		_place_hint.visible = false
	if overlay.confirm_open:
		overlay.cancel_confirm()
	if cc.is_open:
		cc.close(true)
	if browser_tabs.is_open:
		browser_tabs.close("_quiet")
	if album.is_open:
		album.close()
	if mods.is_open:
		mods.close()
	_game_started = false
	_game_id = ""
	_in_overlay = false
	_overlay_mode = ""
	_overlay_busy = false
	overlay.mute_game("", false)
	overlay.thaw_game()
	_quit_flow = false
	_launch_cancellable = false
	cc.game_id = ""

# The Album sits above everything while a game's menu is up (the black launch screen would hide it
# otherwise), and the control center comes back when it is closed.
func _open_album() -> void:
	album.layer = 96 if _in_overlay else 81
	album.open()

## The Album's player. mpv plays fullscreen with its own keys off and listens on a small socket (its JSON IPC), so the
## Album decides what each button does. A game paused behind the menu stays frozen: Tephra only steps aside (like
## resuming) and comes back when the last clip is closed.
var _clip_aside := false

const CLIP_SEND_PY := "import socket,sys\ns=socket.socket(socket.AF_UNIX)\ns.settimeout(1)\ns.connect(sys.argv[1])\ns.sendall((sys.argv[2]+'\\n').encode())"

func clip_start(path: String) -> Dictionary:
	if OS.execute("sh", ["-c", "command -v mpv >/dev/null"]) != 0:
		notify("Playing recordings needs a video player. Install one with: sudo pacman -S mpv")
		return {}
	var run := OS.get_environment("XDG_RUNTIME_DIR")
	var sock := (run if run != "" else "/tmp") + "/tephra-mpv.sock"
	OS.execute("rm", ["-f", "--", sock])
	if launching and _game_started and _in_overlay and not _overlay_busy and not _clip_aside:
		_clip_aside = true
		await overlay.run_shortcuts(["TephraReturn"])
		await get_tree().create_timer(0.3).timeout
	var args := PackedStringArray(["--fs", "--force-window=immediate", "--keep-open=yes", "--hwdec=auto-safe", "--no-input-default-bindings",
		"--no-input-gamepad", "--input-ipc-server=" + sock, "--osd-level=1", "--osd-bar=yes", "--no-osc",
		"--log-file=" + OS.get_environment("HOME") + "/.config/tephra/video.log", path])
	var pid := OS.create_process("mpv", args)
	if pid <= 0:
		return {}
	return {"pid": pid, "fifo": sock}

## One command for the player (mpv's own command words, e.g. "cycle pause"), sent over its socket by a tiny python call.
func clip_send(clip: Dictionary, line: String) -> void:
	if clip.is_empty():
		return
	var json := JSON.stringify({"command": Array(line.split(" ", false))})
	OS.create_process("python3", ["-I", "-c", CLIP_SEND_PY, str(clip["fifo"]), json])

## Ends a clip. restore = false when another clip follows at once (Tephra stays out of the way).
func clip_stop(clip: Dictionary, restore := true) -> void:
	if not clip.is_empty():
		var pid := int(clip["pid"])
		if OS.is_process_running(pid):
			OS.kill(pid)
		OS.execute("rm", ["-f", "--", str(clip["fifo"])])
	if restore and _clip_aside:
		_clip_aside = false
		DisplayServer.window_move_to_foreground()
		await get_tree().create_timer(0.2).timeout
		overlay.raise_tephra()
		overlay.reveal_tephra()

## The Mods page's "Get mods from Nexus": the browser opens on Nexus Mods (searching for the game), as plain Firefox so the
## site sees an ordinary browser. You sign in once (the login is kept) and download; the zip lands in Downloads, where
## "Add mods" lists it.
## The game's own Nexus mods page when its address is known, else a search for the title.
const NEXUS_SLUGS := [
	["resident evil 7", "residentevil7"], ["biohazard 7", "residentevil7"], ["re7", "residentevil7"],
	["resident evil 2", "residentevil22019"], ["re2", "residentevil22019"],
	["resident evil 3", "residentevil32020"], ["re3", "residentevil32020"],
	["resident evil 4", "residentevil42023"], ["re4", "residentevil42023"],
	["resident evil zero", "residentevil0biohazard0hdremaster"], ["resident evil 0", "residentevil0biohazard0hdremaster"],
	["resident evil hd", "residentevilbiohazardhdremaster"],
	["skyrim special", "skyrimspecialedition"], ["skyrim", "skyrim"], ["fallout 4", "fallout4"],
	["fallout new vegas", "newvegas"], ["cyberpunk", "cyberpunk2077"], ["stardew", "stardewvalley"],
	["baldur", "baldursgate3"], ["witcher 3", "witcher3"], ["starfield", "starfield"], ["oblivion", "oblivion"],
	["elden ring", "eldenring"], ["dark souls iii", "darksouls3"], ["monster hunter world", "monsterhunterworld"],
]

func _nexus_url(title: String) -> String:
	var t := title.to_lower().replace(":", " ").replace("™", "").replace("®", "")
	for e in NEXUS_SLUGS:
		if t.contains(e[0]):
			return "https://www.nexusmods.com/games/%s/mods" % e[1]
	return "https://www.nexusmods.com/search?keyword=" + title.uri_encode()

func open_nexus_for(title: String) -> void:
	if launching or _game_active:
		notify("Quit the running game first to open the browser.", "info")
		return
	if browser.firefox() == "":
		notify("The browser needs Firefox. Install it with: sudo pacman -S firefox")
		return
	var g: Dictionary = browser.game_entry(_nexus_url(title), true)
	g["pattern"] = browser.PATTERN
	_launch(-1, g)

func _open_mods() -> void:
	mods.layer = 97 if _in_overlay else 82
	mods.open()

## The Mods button on a game's page or in its menu: the mod manager opens on that game's mods folder, above the page.
func open_mods_for(g: Dictionary) -> void:
	if mods.is_open:
		return
	mods.layer = 97 if _in_overlay else 83
	mods.open_for(g)

func _on_mods_closed() -> void:
	if _in_overlay and _overlay_mode == "cc" and not _overlay_busy and not _placing_perf:
		await get_tree().create_timer(0.2).timeout
		if _in_overlay and not cc.is_open and not mods.is_open:
			_open_cc()

func _on_album_closed() -> void:
	if _in_overlay and _overlay_mode == "cc" and not _overlay_busy and not _placing_perf:
		await get_tree().create_timer(0.2).timeout
		if _in_overlay and not cc.is_open and not album.is_open:
			_open_cc()

func _on_cc_closed(resume: bool) -> void:
	if resume and _in_overlay and _overlay_mode == "cc" and not _overlay_busy and not _quit_flow:
		_overlay_close()

func _launch_message(msg: String) -> void:
	launch_art.visible = false
	launch_label.text = msg
	await get_tree().create_timer(3.0).timeout
	_return_home()

var _last_launch_id := ""  # the game the last launch was for (picked again on Home after it ends)

func _return_home(fade_secs := 0.8) -> void:
	print("Tephra: returning home")
	if overlay.kwin_ok:
		overlay.reveal_tephra()  # Tephra's window is left see-through after fading into a game: always visible again here
	browser.halt()
	_overlay_reset()
	_quit_now = false
	weather.fetch(false)
	_set_game_active(false)
	DisplayServer.window_move_to_foreground()
	games.sort_custom(_sort_games)
	_build_row()  # re-sorted, so the game just played is first
	# Select the game that was just played (or cancelled) by its id: the indices all moved with the re-sort.
	var t := 1 if tiles.size() > 2 else 0
	for j in tile_game.size():
		if tile_game[j] >= 0 and str(games[tile_game[j]]["id"]) == _last_launch_id:
			t = j
	_select(t, false)
	if channels != null:
		channels.rebuild()  # the theme's own Home re-reads the order too, so its tiles point at the right games
	launch_label.text = ""
	launch_art.visible = false
	launch_logo.visible = false
	# Fade the black launch screen away to reveal home. It starts fully black (even if a live menu had
	# hidden it), so leaving a game is always black -> Home, never a cut.
	launch_overlay.visible = true
	launch_overlay.modulate.a = 1.0
	var fade := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(launch_overlay, "modulate:a", 0.0, Motion.dur(fade_secs))
	await fade.finished
	_tl("Home is back")
	launch_overlay.visible = false
	cc.game_running = false
	launching = false  # allow the next launch
	# Steam is closed later, not now: the player may pick another game straight away, and a game that is still
	# shutting down behind Home keeps it open anyway (stop_steam_if_idle checks).
	await get_tree().create_timer(20.0).timeout
	if not launching:
		stop_steam_if_idle()

# Today page: play the chosen recent game. Slide the details away first.
func _play_from_today(appid: String) -> void:
	_leave_details()
	await get_tree().create_timer(0.45).timeout
	_launch_from_library(appid)

# Library: play an installed game. Close the library, select it, launch it.
## Settings > Games > "Pressing a game": off = Cross starts it, on = Cross opens its page, which has
## Play, Pin / Unpin and Rename, so nothing starts without a second press).
func cross_opens_info() -> bool:
	return bool(Settings.get_value("cross_opens_info", false))

## Cross on a game in the Channels / PS2 Home.
func play_or_info(gi: int) -> void:
	if cross_opens_info() and not launching and not _overlay_busy and gi >= 0:
		library.open_game(games[gi], null)
	else:
		_launch(gi)

var _from_library := false  # Play was pressed on a game's page (see _launch)
var _switching := false

## A game is running and another one was chosen: ask, close the running one, then start the new one.
func _switch_game(gi: int) -> void:
	if _switching or _quit_flow or _overlay_busy or gi < 0 or gi >= games.size():
		return
	_switching = true
	var title := str(games[gi]["title"])
	var yes: bool = await overlay.ask("Start %s?" % title, "Starting it will close %s. Anything you haven't saved in it is lost." % _game_title, "Start game")
	if not yes or not launching:
		_switching = false
		if launching and _in_overlay and _overlay_mode == "home":
			library.open_game(games[gi], null)
		return
	_close_fast("Closing %s..." % _game_title)
	var waited := 0.0
	while launching and waited < 30.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	await get_tree().create_timer(1.0).timeout  # Home has faded back in
	_switching = false
	if not launching and gi < games.size() and str(games[gi]["title"]) == title:
		_launch(gi)

func _launch_from_library(appid: String) -> void:
	_from_library = true
	for i in games.size():
		if str(games[i]["id"]) == appid:
			library.close()
			# A game hidden from Home still launches from the Library.
			var t := tile_game.find(i)
			if t >= 0:
				_select(t, false)
				_launch()
			else:
				_launch(i)
			_from_library = false  # _launch has read it by now (it only matters while a game runs)
			return

# Used by the control center's "Quit game" card once the control center
# works on top of games (next step). For now it only reports the request.
func _quit_game() -> void:
	if not _game_started or _quit_flow:
		return
	_quit_flow = true
	var yes: bool = await overlay.ask("Quit %s?" % _game_title, "The game will be closed. Anything you haven't saved in it is lost.", "Quit game")
	if not yes:
		_quit_flow = false
		if _in_overlay and _overlay_mode == "cc":
			_open_cc()
		return
	_close_fast("Closing %s..." % _game_title)

## A game whose window KWin doesn't know as a game (some non-Steam programs) never triggers the fade by itself:
## after 10 s the loading screen fades away anyway.
func _release_hold_later(id: String) -> void:
	await get_tree().create_timer(10.0).timeout
	if launching and _game_id == id:
		overlay.hold_loading(false)

## Closing a game: Home fades back in after a moment and the game (PCSX2, Steam) is shut down behind it, without waiting.
var _quit_now := false

func _close_fast(text: String) -> void:
	launch_label.text = text
	launch_label.modulate.a = 1.0
	overlay.quit_game(_game_id, _game_pattern())  # not awaited: it carries on in the background
	await get_tree().create_timer(0.6).timeout
	_quit_now = true  # the wait loop in _launch sees this and returns Home

## What finds the running game's programs besides Steam's launcher (PCSX2 for PS2 games, the program for other non-Steam ones).
func _game_pattern() -> String:
	return "net.pcsx2.PCSX2" if _game_is_ps2(_game_id) else str(_extra_exe.get(_game_id, ""))

func _game_is_ps2(id: String) -> bool:
	for g in games:
		if str(g["id"]) == id:
			return bool(g.get("ps2", false))
	return false

# ---------- Game options (Triangle) ----------
var _menu_gi := -1

## The actions menu of an installed game by its id (Triangle in the Library or on a game's page).
func open_game_menu_for_id(id: String) -> void:
	for i in games.size():
		if str(games[i]["id"]) == id:
			_open_game_menu(i)
			return

func _open_game_menu(gi_arg := -1) -> void:
	var gi := gi_arg if gi_arg >= 0 else _game_selected()
	if gi < 0 or in_details or _overlay_busy:
		return
	sfx.play("options")  # its own sound, not the one that starts a game
	var g: Dictionary = games[gi]
	var id := str(g["id"])
	var running := launching and _game_started and id == _game_id
	var items: Array = []
	if running and _in_overlay:
		items.append(["resume", "Resume", false])
		items.append(["close", "Close game", false])
	items.append(["unpin" if on_home(g) else "pin", "Unpin from Home" if on_home(g) else "Pin to Home", false])
	if not launching:
		items.append(["rename", "Rename", false])
	if not bool(g.get("ps2", false)):
		items.append(["mods", "Mods", false])
	if not launching and not bool(g.get("nonsteam", false)):
		items.append(["uninstall", "Uninstall", true])
	_menu_gi = gi
	Haptics.confirm()
	sfx.play("open")
	game_menu.open(str(g["title"]), items)

func _on_game_menu(key: String) -> void:
	var gi := _menu_gi
	if gi < 0 or gi >= games.size():
		return
	var g: Dictionary = games[gi]
	var id := str(g["id"])
	match key:
		"resume":
			_overlay_close()
		"close":
			_quit_game()
		"pin", "unpin":
			set_on_home(g, key == "pin")
			refresh_games()
		"rename":
			var orig := str(g.get("orig_title", g["title"]))
			keyboard.open("Rename game", str(g["title"]), false, func(text: String):
				GameNames.set_custom(id, text)
				refresh_games(),
				{"max_len": 48, "hint": "Leave it empty to use \"%s\" again" % orig})
		"mods":
			open_mods_for(g)
		"uninstall":
			_uninstall(id, str(g["title"]))

## Removes an installed game: asks first, makes sure Steam is not holding it, then deletes the game's
## files and its manifest (the game stays in your Steam account and can be installed again).
func _uninstall(id: String, title: String) -> void:
	if launching:
		return
	var yes: bool = await overlay.ask("Uninstall %s?" % title, "The game's files are deleted from this PC. Your saves in Steam Cloud and the game itself stay in your account.", "Uninstall")
	if not yes or launching:
		return
	input_locked = true
	toast.show_toast(Icons.texture("info", Icons.svg_info(), 40), "Uninstalling %s..." % title, false)
	# Steam must not be running, or it keeps (and rewrites) its own list of installed games.
	if _steam_running():
		_steam_stopping = true
		_steam_cmd(["-shutdown"])
		var waited := 0.0
		while _steam_running() and waited < 40.0:
			await get_tree().create_timer(1.0).timeout
			waited += 1.0
		_steam_stopping = false
		if _steam_virtual:
			_kill_xvfb()
			_steam_virtual = false
	var removed := _delete_install(id)
	var hidden: Array = Settings.get_value("hidden_games", []).duplicate()
	hidden.erase(id)
	Settings.set_value("hidden_games", hidden)
	input_locked = false
	refresh_games()
	toast.show_toast(Icons.texture("info", Icons.svg_info(), 40), ("%s was uninstalled" % title) if removed else "Could not uninstall %s" % title, false)

## Deletes the manifest and the install folder named in it. True when the manifest is gone.
func _delete_install(id: String) -> bool:
	var libs: Array = [steam_dir]
	var re_path := RegEx.new()
	re_path.compile("\"path\"\\s+\"([^\"]+)\"")
	for m in re_path.search_all(FileAccess.get_file_as_string(steam_dir + "/steamapps/libraryfolders.vdf")):
		if not libs.has(m.get_string(1)):
			libs.append(m.get_string(1))
	for lib in libs:
		var mp: String = lib + "/steamapps/appmanifest_" + id + ".acf"
		if not FileAccess.file_exists(mp):
			continue
		var re_dir := RegEx.new()
		re_dir.compile("\"installdir\"\\s+\"([^\"]+)\"")
		var m := re_dir.search(FileAccess.get_file_as_string(mp))
		if m != null:
			var folder: String = m.get_string(1)
			# Only a plain folder name inside steamapps/common: never a path that could point elsewhere.
			if folder != "" and not folder.contains("/") and not folder.contains("..") and folder != ".":
				var dir: String = lib + "/steamapps/common/" + folder
				if DirAccess.dir_exists_absolute(dir):
					OS.create_process("rm", ["-rf", dir])
		return DirAccess.remove_absolute(mp) == OK
	return false

# ---------- Input ----------
# Every direction (D-pad, left stick, arrow keys) arrives here as a "step" from
# nav.gd, with hold-to-repeat already handled. The right stick sends "fast steps"
# of several items at once. Whatever is on top gets the step.
## In Home, the Library and every menu Tephra stays above all other windows, so nothing (a game that was left
## running, a stray window) can cover it. Once a game is launched Tephra steps back so the game can be seen.
var _top_acc := 0.0
var _kept_on_top := false

var _tp_acc := 25.0
var _nature_night_seen := Themes.nature_night()

## Turns off the controller touchpad as a mouse (it is the screenshot / record button): at start and every 30 s, so a
## controller connected later is covered too (see touchpad-off.sh).
func _touchpad_off(delta: float) -> void:
	_tp_acc += delta
	if _tp_acc < 30.0:
		return
	_tp_acc = 0.0
	# Nature turns to its night version at 7 pm and back to day at 5 am: redo the colours when that happens.
	if Themes.id() == "nature" and Themes.nature_night() != _nature_night_seen and not launching and not input_locked:
		_nature_night_seen = Themes.nature_night()
		apply_theme("nature", true)
	var sh := ProjectSettings.globalize_path("res://touchpad-off.sh")
	if FileAccess.file_exists(sh):
		OS.create_process("bash", [sh])
	var dc := ProjectSettings.globalize_path("res://desktop-clean.sh")
	if FileAccess.file_exists(dc):
		OS.create_process("bash", [dc])  # no icons on the desktop behind Tephra, ever

var _under_applied := false

## Developer option "Keep Tephra under all apps": the window sits below everything (KWin keep-below) and is never
## pushed on top, so whatever is running above it can be looked at while troubleshooting.
func apply_under_apps() -> void:
	var under := bool(Settings.get_value("dev_under", false))
	_under_applied = under
	if under:
		_kept_on_top = false
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	overlay.run_shortcuts(["TephraSink" if under else "TephraUnsink"])

var _player_colour_pending := true

## Steam only takes a sign-in in its own window. steam_sign_in() starts Steam normally with its window allowed to show,
## and Tephra goes underneath until the sign-in has happened (loginusers.vdf is written again), or 5 minutes have passed.
var _steam_login := false
const STEAM_LOGIN_WAIT := 300.0

func steam_signing_in() -> bool:
	return _steam_login

func steam_sign_in() -> void:
	if _steam_login or launching or _any_game_running():
		return
	_steam_login = true
	var vdf := steam_dir + "/config/loginusers.vdf"
	var since := Time.get_unix_time_from_system()
	notify("Sign in to Steam in the window that opened. Tephra comes back by itself when you're done.")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	_kept_on_top = false
	overlay.run_shortcuts(["TephraSink"])
	steam_rule(false)  # Steam's windows may show for a while
	if _steam_running():
		OS.create_process("steam", ["-shutdown"])
		var closing := 0.0
		while _steam_running() and closing < 20.0:
			await get_tree().create_timer(1.0).timeout
			closing += 1.0
	_steam_cmd([])  # normally, not -silent: the sign-in window shows
	var waited := 0.0
	var signed_in := false
	while waited < STEAM_LOGIN_WAIT:
		await get_tree().create_timer(2.0).timeout
		waited += 2.0
		if FileAccess.file_exists(vdf) and float(FileAccess.get_modified_time(vdf)) > since and SteamAccount.steam_id(steam_dir) != "":
			signed_in = true
			break
	steam_rule(true)
	if signed_in:
		await get_tree().create_timer(4.0).timeout  # let Steam finish settling in before it is closed again
		OS.create_process("steam", ["-shutdown"])
	_steam_login = false
	apply_under_apps()  # Tephra back on top (or under, if that developer option is on)
	DisplayServer.window_move_to_foreground()
	if signed_in:
		refresh_games(false)
		notify("Signed in to Steam.")
	else:
		notify("Steam sign-in wasn't finished. You can try again from setup or Settings.")

## Two or more controllers: the selection colour is the colour of the pad in charge (DualSense blue, Switch red,
## Xbox green); one controller: the theme's own. The screen is redrawn with it when nothing is open.
func _player_colour_check() -> void:
	if not _player_colour_pending or launching or input_locked or _in_overlay or _overlay_busy:
		return
	if keyboard.is_open or game_menu.is_open or cc.is_open or library.is_open or album.is_open or mods.is_open \
			or profile_screen.is_open or settings_screen.is_open or top_menu.is_open or setup_screen.is_open or in_details:
		return
	_player_colour_pending = false
	var pads := Input.get_connected_joypads().filter(func(p): return TephraGlyphs.family_for_device(p) != "")
	var want := Color(0, 0, 0, 0)
	if pads.size() >= 2:
		match TephraGlyphs.family_for_device(TephraGlyphs.primary_device()):
			"ps": want = Color(0.28, 0.55, 1.0)
			"nintendo": want = Color(1.0, 0.27, 0.32)
			_: want = Color(0.3, 0.85, 0.38)
	if want != Themes.select_override:
		Themes.select_override = want
		apply_theme(Themes.id(), true)

func _keep_on_top(delta: float) -> void:
	_player_colour_check()
	_touchpad_off(delta)
	_top_acc += delta
	if _top_acc < 1.0:
		return
	_top_acc = 0.0
	if _fix_win != "" or get_window().mode == Window.MODE_MINIMIZED:
		return
	var under := bool(Settings.get_value("dev_under", false))
	if under != _under_applied:
		apply_under_apps()
	var want := not launching and not _quit_flow and not under and not _steam_login
	if want != _kept_on_top:
		_kept_on_top = want
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, want)
	if want and _foreign_game and not get_window().has_focus():
		DisplayServer.window_move_to_foreground()

## The control center is open over the loading screen: it takes the steps (the loading screen itself takes none).
func _cc_over_loading() -> bool:
	return launching and not _game_started and cc.is_open and not _overlay_busy

func _on_step(dir: Vector2i, n := 1) -> void:
	if (launching and not _in_overlay and not _cc_over_loading()) or input_locked or overlay.confirm_open or _overlay_busy:
		return
	var hm := Time.get_ticks_usec()
	Haptics.tick()  # every move of the cursor, anywhere, buzzes at the Vibration setting
	preload("res://frame_probe.gd").mark("step: buzz", hm)
	hm = Time.get_ticks_usec()
	sfx.play("tick")
	preload("res://frame_probe.gd").mark("step: sound", hm)
	if phone_screen.is_open:
		return
	if keyboard.is_open:
		keyboard.move(dir)
		return
	if game_menu.is_open:
		game_menu.move(dir.y)
		return
	if _placing_perf:
		_place_move(dir, n)
		return
	if color_picker.is_open:
		color_picker.move(dir)
		return
	if hdr_calibration.is_open:
		hdr_calibration.move(dir)
		return
	if controller_test.is_open:
		return
	if scene_test.is_open:
		scene_test.move(dir)
		return
	if mods.is_open and not cc.is_open:
		mods.move(dir)
		return
	if album.is_open and not cc.is_open:  # the control center on top of the Album gets the pad, not the Album
		album.move(dir)
		return
	if profile_screen.is_open and not cc.is_open:
		return
	if settings_screen.is_open and not cc.is_open:
		settings_screen.move(dir)
		return
	if top_menu.is_open and not cc.is_open:
		top_menu.move(dir)
		return
	if setup_screen.is_open and not cc.is_open:
		setup_screen.move(dir)
		return
	if profile_focus and not cc.is_open:
		if dir.y > 0:
			_focus_profile(false)  # back down to the games
		elif dir.x != 0:
			var nodes := {"wifi": wifi_icon, "bt": bt_icon, "pad": pad_wrap, "battery": batt_wrap, "gear": gear_icon, "profile": avatar_rect}
			var ni := top_index
			for _k in TOP_ITEMS.size():
				ni = posmod(ni + dir.x, TOP_ITEMS.size())  # round the ends of the bar
				if (nodes[TOP_ITEMS[ni]] as Control).is_visible_in_tree():  # skip icons that are not there (no battery, hidden by the theme)
					_set_top_index(ni)
					break
		return
	if cc.is_open:
		if dir.x != 0:
			cc.move(dir.x)
		else:
			cc.held = nav.repeating
			cc.vertical(dir.y)
	elif library.is_open:
		for i in n:
			library.move(dir.x, dir.y)
	elif in_details:
		if dir.y != 0:
			_details_vertical(dir.y, n)
		elif dir.x != 0:
			details.filter_step(dir.x)  # Achievements page: change the filter
	elif channels != null:
		if channels.move(dir) == "up":
			var x: float = lerpf(shard_icon.get_global_rect().get_center().x, avatar_rect.get_global_rect().get_center().x, channels.top_column())
			_focus_profile(true, _top_index_near(x))
	elif dir.x != 0:
		# one step wraps round the ends (a held stick, n > 1, still stops at them)
		_select(posmod(selected + dir.x, tiles.size()) if n == 1 and tiles.size() > 0 else selected + dir.x * n)
	elif dir.y > 0:
		_enter_details()
	elif dir.y < 0 and not library.is_open:
		_focus_profile(true, _top_index_for_tile())  # Up goes to the top-bar icon above the selected tile

func _on_fast_step(dir: Vector2i, n: int) -> void:
	if keyboard.is_open:
		return  # the right stick moves the keyboard around, it doesn't pick keys
	if _channels_active():
		return  # on the Channels Home the right stick flips pages instead (channels.gd)
	_on_step(dir, n)

## The Channels Home is showing and nothing is open on top of it.
func _channels_active() -> bool:
	return channels != null and not (keyboard.is_open or game_menu.is_open or color_picker.is_open or hdr_calibration.is_open \
		or controller_test.is_open or scene_test.is_open or album.is_open or mods.is_open or profile_screen.is_open or settings_screen.is_open \
		or top_menu.is_open or setup_screen.is_open or cc.is_open or library.is_open or profile_focus or _placing_perf)

# ---------- Profile (press Up from the games) ----------
func _set_top_index(i: int) -> void:
	top_index = i
	avatar_ring.visible = profile_focus and TOP_ITEMS[i] == "profile"
	_update_gear()
	_refresh_all_hints()

# The icons in the top bar have no outline: when selected, one brightens and grows a little.
var _top_pulse: Tween

func _update_gear() -> void:
	var icons := {"wifi": wifi_icon, "bt": bt_icon, "pad": pad_wrap, "battery": batt_wrap, "gear": gear_icon}
	for key in icons:
		var ic: Control = icons[key]
		var on: bool = profile_focus and TOP_ITEMS[top_index] == key
		Motion.scale_to(ic, 1.3 if on else 1.0, 0.14)
		if key != "pad" and key != "battery":  # their brightness is handled with their own icon update
			Motion.fade_to(ic, 1.0 if on else (0.75 if key == "gear" else 0.85), 0.14)
	# The selected icon breathes (grows and shrinks, glowing a little brighter) so it is easy to spot.
	if _top_pulse != null:
		_top_pulse.kill()
		_top_pulse = null
	if profile_focus and Motion.on():
		var tgt: Control = avatar_ring if TOP_ITEMS[top_index] == "profile" else icons.get(TOP_ITEMS[top_index], null)
		if tgt != null:
			tgt.pivot_offset = tgt.size / 2.0
			var base := 1.0 if tgt == avatar_ring else 1.3
			_top_pulse = create_tween().set_loops()
			_top_pulse.tween_interval(0.16)
			_top_pulse.tween_property(tgt, "scale", Vector2.ONE * (base + 0.22), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_top_pulse.parallel().tween_property(tgt, "modulate", Color(1.6, 1.6, 1.6, 1.0) if not Themes.light() else Color(1.12, 1.12, 1.12, 1.0), 0.45).set_trans(Tween.TRANS_SINE)
			_top_pulse.tween_property(tgt, "scale", Vector2.ONE * base, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_top_pulse.parallel().tween_property(tgt, "modulate", Color(1, 1, 1, 1.0), 0.45).set_trans(Tween.TRANS_SINE)

# Which top-bar icon sits above the selected tile: the Home tile goes to the Tephra
# (developer) icon; any other tile goes to the icon nearest to it, left to right.
func _top_index_for_tile() -> int:
	if selected <= 0 or selected >= tiles.size():
		return 0
	return _top_index_near((tiles[selected] as Control).get_global_rect().get_center().x)

## The top-bar item closest to this x position on screen.
func _top_index_near(x: float) -> int:
	var icons: Array = [wifi_icon, bt_icon, pad_wrap, batt_wrap, gear_icon, avatar_rect]
	var best := TOP_ITEMS.size() - 1
	var best_d := INF
	for i in icons.size():
		if not (icons[i] as Control).is_visible_in_tree():
			continue
		var d := absf((icons[i] as Control).get_global_rect().get_center().x - x)
		if d < best_d:
			best_d = d
			best = i
	return best

## After a menu from the top bar (Wi-Fi, Bluetooth, controllers) closes, the cursor stays on the icon
## that opened it; Down goes back to the games, as usual.
func _on_top_menu_closed() -> void:
	if profile_focus and not launching:
		_focus_profile(true, top_index)

func _focus_profile(on: bool, idx := -1) -> void:
	profile_focus = on
	top_index = idx if idx >= 0 else TOP_ITEMS.size() - 1  # default: the profile picture
	avatar_ring.visible = on and TOP_ITEMS[top_index] == "profile"
	_update_gear()
	# Dim the games while the top bar has the focus, and let darkness rise from the bottom of the
	# screen, so it's plain at a glance that you are up in the top bar (Down goes back to the games).
	Motion.fade_to(scroll, 0.35 if on else 1.0, 0.25)
	Motion.fade_to(title_area, 0.35 if on else 1.0, 0.25)
	Motion.fade_to(strip, 1.0 if on else 0.5, 0.25)  # (the shade below is what darkens the games)
	Motion.fade_to(top_shade, 1.0 if on else 0.0, 0.3)
	Motion.fade_to(top_arrow, 0.9 if on else 0.0, 0.3)
	if channels != null:
		channels.dim(on)
	_refresh_all_hints()

func _make_top_shade() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Themes.dim(0.0), Themes.dim(0.62), Themes.dim(0.97)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	top_shade = TextureRect.new()
	top_shade.texture = gt
	top_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_shade.stretch_mode = TextureRect.STRETCH_SCALE
	top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_shade.modulate.a = 0.0
	page.add_child(top_shade)
	top_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_shade.offset_top = 156  # starts just under the top bar, which stays bright
	top_arrow = Control.new()
	top_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_arrow.modulate.a = 0.0
	top_arrow.custom_minimum_size = Vector2(44, 24)
	top_arrow.draw.connect(func() -> void:
		var bob := 4.0 * sin(Time.get_ticks_msec() / 1000.0 * TAU / 1.6)
		var pts := PackedVector2Array([Vector2(4, 4 + bob), Vector2(22, 18 + bob), Vector2(40, 4 + bob)])
		top_arrow.draw_polyline(pts, Themes.ink(0.85), 4.0, true))
	page.add_child(top_arrow)
	top_arrow.anchor_left = 0.5
	top_arrow.anchor_right = 0.5
	top_arrow.offset_left = -22
	top_arrow.offset_right = 22
	top_arrow.offset_top = 172
	top_arrow.offset_bottom = 200

func _open_profile() -> void:
	var r := clock_label.get_global_rect()
	r.position.y -= page.position.y
	match TOP_ITEMS[top_index]:
		"gear":
			weather.fetch(false)
			settings_screen.open(r)
		"profile":
			profile_screen.open(r)
		"wifi":
			top_menu.open_menu("wifi", wifi_icon.get_global_rect())
		"bt":
			top_menu.open_menu("bt", bt_icon.get_global_rect())
		"pad":
			top_menu.open_menu("pad", pad_wrap.get_global_rect())
		"battery":
			_toggle_batt_pct()

## Settings > System > Help > View log: the log viewer lives on the Settings screen.
func open_log() -> void:
	var r := clock_label.get_global_rect()
	r.position.y -= page.position.y
	settings_screen.open_log(r)

# ---------- Per-game fixes ----------
# Some games start in a small window and only go fullscreen with their own key
# (Undertale: F4). After such a game starts, Tephra sends that key for you.
# Add more in ~/.local/share/godot/app_userdata/<Tephra>/game_keys.json as
# {"<appid>": "F11"}. Needs `xdotool` (sudo pacman -S xdotool).
const GAME_KEYS := {"391540": "F4"}
# Window title to wait for, so the key is sent the moment the game appears
# instead of after a fixed delay. Games not listed here wait 5 seconds.
const GAME_WINDOWS := {"391540": "UNDERTALE"}

# Writes what the fullscreen fix did to ~/.local/share/godot/app_userdata/<Tephra>/game_fix.log
func _fix_log(msg: String) -> void:
	print("Tephra: ", msg)
	var f := FileAccess.open("user://game_fix.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://game_fix.log") else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(Time.get_datetime_string_from_system() + "  " + msg)

# The key to press for this game ("" = none): built-in list, then game_keys.json.
func _game_key(id: String) -> String:
	var key: String = GAME_KEYS.get(id, "")
	var p := "user://game_keys.json"
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary and d.has(id):
			key = str(d[id])
	return key

# Keeps Tephra's black screen in front of the game while the fix runs, so the small
# window is never seen, then lets the game through (focus goes to the game window).
func _apply_game_fix(id: String) -> void:
	if _game_key(id) == "":
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	_fix_log("covering the game with Tephra")
	_fix_win = ""
	await _game_fix_body(id)
	await get_tree().create_timer(0.4).timeout  # let the fullscreen switch finish
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	if _fix_win != "":
		OS.execute("xdotool", ["windowactivate", _fix_win], [])
	_fix_log("uncovered")

var _fix_win := ""

func _game_fix_body(id: String) -> void:
	var key := _game_key(id)
	if key == "":
		return
	if OS.execute("which", ["xdotool"], []) != 0:
		_fix_log("xdotool not installed, can't send " + key)
		return
	var title: String = GAME_WINDOWS.get(id, "")
	var win := ""
	if title == "":
		var w := 0
		while w < 720 and not _game_running(id):  # wait for the game to start
			await get_tree().create_timer(0.25).timeout
			w += 1
		await get_tree().create_timer(5.0).timeout
		if not _game_running(id):
			return
	else:
		# Check for the window every quarter second (up to 25 s).
		var tries := 0
		while tries < 400 and win == "":  # up to ~100 s; the first start can be slow
			var out := []
			if OS.execute("xdotool", ["search", "--name", "^" + title + "$"], out) == 0 and out.size() > 0:
				win = str(out[0]).strip_edges().get_slice("\n", 0)
			else:
				await get_tree().create_timer(0.25).timeout
				tries += 1
		await get_tree().create_timer(0.4).timeout  # let the game finish setting up its window
	_fix_win = win
	_fix_log("window search for '" + title + "' found: '" + win + "'")
	if win != "":
		# The key only reaches the game if the game window has focus.
		var act := OS.execute("xdotool", ["windowactivate", "--sync", win], [])
		_fix_log("windowactivate exit code " + str(act))
		await get_tree().create_timer(0.1).timeout
	# The game ignores the key until it has finished starting. So: press it, and if the
	# window's size didn't change, press again (up to 12 tries). Once the size changes the
	# toggle worked, so stop (pressing again would switch fullscreen back off).
	var screen_w := DisplayServer.screen_get_size().x
	for attempt in 12:
		var before := _window_width(win) if win != "" else 0
		if attempt == 0 and before >= screen_w * 0.9:
			_fix_log("already fullscreen")
			return
		var kc := OS.execute("xdotool", ["key", "--clearmodifiers", key], [])
		_fix_log("sent %s (window width %d), exit code %d" % [key, before, kc])
		if win == "":
			return  # no window to check; one press only
		await get_tree().create_timer(0.7).timeout
		var after := _window_width(win)
		if after != before:
			_fix_log("window width changed %d -> %d, done" % [before, after])
			return
	_fix_log("gave up: the window size never changed")

func _window_width(win: String) -> int:
	var out := []
	if OS.execute("xdotool", ["getwindowgeometry", win], out) != 0 or out.is_empty():
		return 0
	var m := RegEx.create_from_string("Geometry: (\\d+)x(\\d+)").search(str(out[0]))
	return int(m.get_string(1)) if m != null else 0

# ---------- Developer overlay ----------
var dev_layer: CanvasLayer
var dev_label: Label
var _dev_t := 0.0

var dev_pill: PanelContainer
var dev_box: BoxContainer
var dev_style: StyleBoxFlat
var _dev_placeholder := false
var dev_graph: Control
var _dev_gpu := {"util": -1.0, "temp": -1.0}
var _dev_gpu_t := 99.0

func _perf_on(key: String) -> bool:
	for it in Perf.ITEMS:
		if it[0] == key:
			return bool(Settings.get_value(key, it[2]))
	return false

func _perf_any() -> bool:
	for it in Perf.ITEMS:
		if bool(Settings.get_value(it[0], it[2])):
			return true
	return false

# The performance line: one neat strip in the middle at the bottom. It shows the numbers picked in
# the control center's Performance card, while the control center is open (or everywhere, if
# "Show on every screen" is on).
# Resolution as people say it: 4K, 2K, 1080p (by the height of the picture).
static func _res_name(sz: Vector2i) -> String:
	if sz.y >= 2160:
		return "4K"
	if sz.y >= 1440:
		return "2K"
	return "%dp" % sz.y

func _setup_dev_overlay() -> void:
	dev_layer = CanvasLayer.new()
	dev_layer.layer = 96  # above the control center (95)
	add_child(dev_layer)
	dev_pill = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Themes.c("panel"), 0.84)
	sb.set_corner_radius_all(Themes.r(18))
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	sb.border_color = SELECT
	dev_style = sb
	dev_pill.add_theme_stylebox_override("panel", sb)
	dev_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dev_layer.add_child(dev_pill)
	dev_box = BoxContainer.new()  # a row, or a column in the side spots (set in _update_dev_overlay)
	dev_box.add_theme_constant_override("separation", 10)
	dev_pill.add_child(dev_box)
	var hb := dev_box
	dev_label = Label.new()
	dev_label.add_theme_font_size_override("font_size", 17)
	dev_label.add_theme_color_override("font_color", TEXT)
	dev_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dev_label)
	dev_graph = FrameGraph.new()
	hb.add_child(dev_graph)
	dev_layer.visible = false

# "shown", "hidden" (hidden with Triangle in the control center) or "empty" (no numbers picked).
func _bar_state() -> String:
	if not _perf_any():
		return "empty"
	return "hidden" if InGameHud.hidden() else "shown"

func _update_dev_overlay(delta: float) -> void:
	var st := _bar_state()
	if st != "shown":
		# Still drawn in the control center, dimmed, so it can be selected and brought back.
		dev_graph.visible = false
		dev_box.vertical = false
		var msg := "Info bar hidden" if st == "hidden" else "No numbers chosen"
		if dev_label.text != msg:
			dev_label.text = msg
		dev_label.visible = true
		if not _dev_placeholder:
			_dev_placeholder = true
			dev_label.add_theme_color_override("font_color", Color(TEXT, 0.55))
		return
	if _dev_placeholder:
		_dev_placeholder = false
		dev_label.add_theme_color_override("font_color", TEXT)
		_dev_t = 1.0
	var show_graph := _perf_on("perf_graph")
	dev_graph.visible = show_graph
	if show_graph:
		var hz := DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
		dev_graph.budget_ms = 1000.0 / (hz if hz > 20.0 else 60.0)
		dev_graph.push(delta * 1000.0)
	_dev_t += delta
	if _dev_t < 0.5:
		return
	_dev_t = 0.0
	# Short words only ("120 FPS", "CPU 6%", "2K"), so the bar stays narrow, and in the side spots
	# it is a true column: one number per line with the frame-time graph underneath.
	var parts: Array = []
	if _perf_on("perf_fps"):
		parts.append("%d FPS" % Engine.get_frames_per_second())
	if _perf_on("perf_res"):
		parts.append(_res_name(get_window().size))
	if _perf_on("perf_refresh"):
		var hz2 := DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
		if hz2 > 0.0:
			parts.append("%d Hz" % roundi(hz2))
	var live: Dictionary = perf.live()
	if _perf_on("perf_cpu") and float(live.get("cpu", -1.0)) >= 0.0:
		parts.append("CPU %d%%" % int(live["cpu"]))
	_dev_gpu_t += 0.5
	if (_perf_on("perf_gpu") or _perf_on("perf_temps")) and _dev_gpu_t >= 2.0:
		_dev_gpu_t = 0.0
		_poll_gpu()  # asks the driver (it may start nvidia-smi), so it runs on a worker thread, every 2 seconds
	if _perf_on("perf_gpu") and float(_dev_gpu.get("util", -1.0)) >= 0.0:
		parts.append("GPU %d%%" % int(_dev_gpu["util"]))
	if _perf_on("perf_ram"):
		parts.append("RAM %.1fG" % float(live.get("ram_gb", 0.0)))
	if _perf_on("perf_temps"):
		var ct: float = Perf.cpu_temp()
		if ct >= 0.0:
			parts.append("CPU %d\u00b0" % roundi(ct))
		if float(_dev_gpu.get("temp", -1.0)) >= 0.0:
			parts.append("GPU %d\u00b0" % roundi(float(_dev_gpu["temp"])))
	var zone := _current_zone()
	var stacked: bool = zone != "" and InGameHud.vertical(zone)
	dev_box.vertical = stacked
	dev_box.add_theme_constant_override("separation", 8 if stacked else 18)
	dev_graph.custom_minimum_size = Vector2(84, 20) if stacked else Vector2(120, 24)  # a short graph
	dev_label.text = ("\n" if stacked else "   \u00b7   ").join(parts)
	dev_label.visible = not parts.is_empty()

# Which game's spot the info bar uses: the running game's (in its menus) or the general one ("").
func _hud_id() -> String:
	return _game_id if (_in_overlay and _game_id != "") else ""

# Where the info bar sits for one of the 8 spots.
# In the control center it keeps clear of the top bar and the button hints.
func _zone_pos(zone: String) -> Vector2:
	var m := float(InGameHud.MARGIN)
	var top := 96.0 if cc.is_open else m
	var bottom := 8.0 if cc.is_open else m
	var c: Vector2i = InGameHud.CELLS[zone]
	var x := m if c.x == 0 else (size.x - dev_pill.size.x - m if c.x == 2 else (size.x - dev_pill.size.x) / 2.0)
	var y := top if c.y == 0 else (size.y - dev_pill.size.y - bottom if c.y == 2 else (size.y - dev_pill.size.y) / 2.0)
	return Vector2(x, y)

# The spot the bar is showing at.
func _current_zone() -> String:
	if _placing_perf:
		return _place_zone
	return InGameHud.zone_for(_hud_id())

func _place_dev_overlay() -> void:
	dev_pill.reset_size()
	var target := _zone_pos(_current_zone())
	if _placing_perf and dev_pill.position.distance_to(target) > 1.0:
		dev_pill.position = dev_pill.position.lerp(target, 0.35)  # slides into the new spot
	else:
		dev_pill.position = target

# ---------- Moving the info bar (control center: Down to select it, then Square) ----------
# The bar can sit in 8 spots (see ingame_hud.gd): the four corners and the middle of each edge.
func _start_placing() -> void:
	if _placing_perf or _overlay_busy or not cc.is_open:
		return
	_place_zone = InGameHud.zone_for(_hud_id())
	_placing_perf = true
	_dev_t = 1.0
	_show_place_hint()

func _show_place_hint() -> void:
	if _place_hint == null:
		_place_hint = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Themes.c("panel"), 0.90)
		sb.set_corner_radius_all(Themes.r(18))
		sb.content_margin_left = 24
		sb.content_margin_right = 24
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		_place_hint.add_theme_stylebox_override("panel", sb)
		_place_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dev_layer.add_child(_place_hint)
	var old := _place_hint.get_child(0) if _place_hint.get_child_count() > 0 else null
	if old != null:
		_place_hint.remove_child(old)
		old.queue_free()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_place_hint.add_child(hb)
	var items := [["dpad", "Choose a spot"], ["accept", "Place here"], ["west", "Back to default"], ["back", "Cancel"]]
	var first := true
	for it in items:
		if not first:
			var gap := Control.new()
			gap.custom_minimum_size.x = 22
			hb.add_child(gap)
		first = false
		hb.add_child(TephraGlyphs.glyph(it[0], 34))
		hb.add_child(_label(it[1], 24, TEXT))
	_place_hint.visible = true
	_place_hint.reset_size()
	_place_hint.position = Vector2((size.x - _place_hint.size.x) / 2.0, 36)

func _place_move(dir: Vector2i, n: int) -> void:
	for i in maxi(n, 1):
		_place_zone = InGameHud.neighbour(_place_zone, dir)
	_dev_t = 1.0  # redraw the pill's text now (it is stacked in the side spots)

func _place_input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		InGameHud.save_zone(_hud_id(), _place_zone)
		toast.show_toast(Icons.texture("info", Icons.svg_info(), 40), "Info bar moved: %s" % InGameHud.zone_name(_place_zone), false)
		_end_placing()
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_end_placing()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.west_button():
		InGameHud.save_zone(_hud_id(), "")
		_end_placing()

func _end_placing() -> void:
	_placing_perf = false
	_dev_t = 1.0
	if _place_hint != null:
		_place_hint.visible = false

# The top-bar controller icons: one for every connected controller (up to four), each green above 30%,
# orange at 30% or less and red at 10% or less. They all swell in time with the lightbar when an alert fires.
var _pad_icons: Array = []
var _pad_list: Array = []
var _pad_list_t := 99.0

func _new_pad_icon() -> TextureRect:
	var r := TextureRect.new()
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.custom_minimum_size = Vector2(40, 32)
	r.modulate.a = 0.85
	return r

## The picture model of one connected controller (or the forced one from the Developer menu).
func _pad_model_of(device: int) -> String:
	var o := str(Settings.get_value("glyph_override", ""))
	if o == "ds5" or o == "ds4" or o == "xbox" or o == "nintendo":
		return o
	return TephraGlyphs.model_for_device(device)

func _update_battery_icon(delta: float) -> void:
	if alert == null or pad_icon == null:
		return
	_pad_list_t += delta
	if _pad_list_t >= 2.0:
		_pad_list_t = 0.0
		_pad_list = controllers.list() if controllers != null else []  # reads battery files: not every frame
	# What to show: one entry per controller, or one grey icon when none is connected.
	var want: Array = []
	for c in _pad_list.slice(0, 4):
		want.append({"model": _pad_model_of(int(c["device"])), "pct": int(c["battery"]), "charging": bool(c["charging"])})
	if want.is_empty():
		want.append({"model": TephraGlyphs.pad_model(), "pct": -1, "charging": false})
	while _pad_icons.size() < want.size():
		var ic := _new_pad_icon()
		pad_wrap.add_child(ic)
		_pad_icons.append(ic)
	while _pad_icons.size() > want.size():
		var gone: TextureRect = _pad_icons.pop_back()
		pad_wrap.remove_child(gone)
		gone.queue_free()
	pad_icon = _pad_icons[0]
	var selected_here: bool = profile_focus and TOP_ITEMS[top_index] == "pad"
	for i in want.size():
		var ic2: TextureRect = _pad_icons[i]
		var w: Dictionary = want[i]
		var model: String = w["model"]
		if str(ic2.get_meta("model", "")) != model:
			ic2.set_meta("model", model)
			ic2.texture = Icons.texture("pad_" + model, Icons.svg_pad(model), 32)
		var col := Color(0.62, 0.66, 0.68)  # no battery information (wired, or not connected)
		var pct: int = w["pct"]
		if pct >= 0:
			var band := 0
			if not bool(w["charging"]):
				band = 2 if pct <= 10 else (1 if pct <= 30 else 0)
			col = alert.band_color(band)
			if Themes.id() == "frutiger" and band < 2:
				col = Themes.c("accent")  # Frutiger: the theme's blue, not green or orange; red still warns at 10%
		ic2.modulate = Color(col.r, col.g, col.b, 1.0 if selected_here else 0.88)
	pad_wrap.pivot_offset = pad_wrap.size / 2.0
	if not selected_here:
		var k: float = alert.k if alert.flashing else 0.0
		pad_wrap.scale = Vector2.ONE * (1.0 + 0.28 * k)

# The laptop's own battery, in the top bar left of the gear. Nothing shows on a desktop PC.
# Reading the battery means about seven reads of the laptop's power controller, and each one can take
# a couple of milliseconds (10 to 17 ms in all on a laptop). Done on the main thread that is a visible
# stutter every 5 seconds, so the reading happens on a worker thread and only the result comes back.
var _batt_task := -1

func _update_laptop_battery(delta: float) -> void:
	_batt_t += delta
	if _batt_t < 5.0:
		return
	_batt_t = 0.0
	if _batt_task >= 0:
		return  # the last reading is still running
	_batt_task = _work(func() -> void:
		var reading: Dictionary = Perf.laptop_battery()
		_apply_laptop_battery.call_deferred(reading))

func _apply_laptop_battery(b: Dictionary) -> void:
	_work_done(_batt_task)
	_batt_task = -1
	batt_wrap.visible = bool(b["has"])
	if not bool(b["has"]):
		return
	batt_pct.text = "%d%%" % int(b["pct"])
	if _pct_shown != bool(Settings.get_value("battery_pct", false)):
		_apply_batt_pct(false)
	var level := roundi(maxi(int(b["pct"]), 0) / 20.0)
	var key := "bat%d%s" % [level, bool(b["charging"])]
	if key != _batt_key:
		_batt_key = key
		batt_icon.texture = Icons.texture(key, Icons.svg_battery(level / 5.0, bool(b["charging"])), 48)
	# Same colours as the controller icon: green above 30%, orange at 30% or less, red at 10% or less.
	# Plugged in (charging or full) is always green.
	var pct := int(b["pct"])
	var band := 0
	if not (bool(b["charging"]) or bool(b["full"])):
		band = 2 if pct <= 10 else (1 if pct <= 30 else 0)
	var lband := 0
	if not (bool(b["charging"]) or bool(b["full"])):
		lband = 2 if pct <= 10 else (1 if pct <= 20 else 0)
	if lband > _laptop_band and bool(Settings.get_value("battery_flash", true)) and not input_locked:
		_laptop_alert(lband, pct)
	_laptop_band = lband
	var col: Color = alert.band_color(band)
	var sel: bool = profile_focus and TOP_ITEMS[top_index] == "battery"
	batt_icon.modulate = Color(col.r, col.g, col.b, 1.0 if sel else 0.88)

# This PC's own battery: a notice when it drops to 20% (low) and again at 10% (critically low).
var _laptop_band := 0

func _laptop_alert(level: int, pct: int) -> void:
	var text := "Battery %s - %d%%. Plug in the charger." % ["critically low" if level >= 2 else "low", pct]
	if launching and _game_started:
		_desktop_notice(text, level >= 2)
	else:
		toast.show_toast(Icons.texture("bat0False", Icons.svg_battery(0.1, false), 40), text, false)
		sfx.play("open")

## During a game: no desktop popup (KDE's notifications are all switched off, see steam_quiet.gd). The notice is kept
## in the Control center's Notifications, where PS shows it.
func _desktop_notice(text: String, _urgent: bool) -> void:
	preload("res://notifications.gd").push(text, "battery")

# Pressing A on the battery icon slides the percentage open or closed (no pop-up).
func _toggle_batt_pct() -> void:
	Settings.set_value("battery_pct", not bool(Settings.get_value("battery_pct", false)))
	_apply_batt_pct(true)

func _apply_batt_pct(animate: bool) -> void:
	_pct_shown = bool(Settings.get_value("battery_pct", false))
	var width := 56.0 if _pct_shown else 0.0
	if animate and Motion.on():
		var tw := create_tween().set_parallel(true)
		tw.tween_property(batt_pct, "custom_minimum_size:x", width, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(batt_pct, "modulate:a", 1.0 if _pct_shown else 0.0, 0.25)
	else:
		batt_pct.custom_minimum_size.x = width
		batt_pct.modulate.a = 1.0 if _pct_shown else 0.0

# Fake events for testing (Developer menu).
func dev_fake_toast() -> void:
	toast.show_toast(Icons.texture("check", Icons.svg_check(), 40), "Test notification", false)

## Developer menu: send a pretend low (1) or critical (2) battery alert, or stop it (0).
func dev_battery_test(level: int) -> void:
	alert.dev_test(level)

func dev_toast(text: String) -> void:
	toast.show_toast(Icons.texture("check", Icons.svg_check(), 40), text, false, false)

## A notice that pops up on screen and is kept in the Control center's Notifications.
func notify(text: String, kind := "info") -> void:
	if kind == "tephra_update":
		sfx.play("update")  # the same sound in every theme
	toast.show_toast(Icons.texture("bell", Icons.svg_bell(), 40), text, false, false)
	preload("res://notifications.gd").push(text, kind)
	if launching and _game_active and not _in_overlay:
		# A game has the screen (Tephra draws nothing behind it): the sound still plays, and KDE shows the banner.
		sfx.play("update")
		var icon := ProjectSettings.globalize_path("res://assets/shard_logo.png")
		OS.create_process("notify-send", ["-a", "Tephra", "-t", "5000", "-i", icon if FileAccess.file_exists("res://assets/shard_logo.png") else "dialog-information",
			"-h", "string:desktop-entry:tephra", "Tephra", text])

## Developer menu: the loading screen shown on its own (artwork, bar and the changing messages), with no game behind
## it, to look at the messages. The bar creeps up to 90% over a minute; Back ends it.
var _fake_loading := false

func dev_fake_loading() -> void:
	if launching or _fake_loading:
		return
	_fake_loading = true
	input_locked = true
	launch_art.texture = hero.texture
	launch_art.modulate = Color(1, 1, 1, 0.35)
	launch_art.visible = hero.texture != null
	launch_label.text = "Preparing a test game..."
	launch_label.modulate.a = 1.0
	launch_logo.texture = null
	launch_logo.visible = false
	launch_overlay.modulate.a = 0.0
	launch_overlay.visible = true
	create_tween().tween_property(launch_overlay, "modulate:a", 1.0, Motion.dur(0.4))
	_show_launch_hint()
	_bar_show(true)
	var t := 0.0
	while _fake_loading and t < 180.0:
		_bar_to(minf(0.9, 0.05 + t / 70.0))
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	_fake_loading = false
	_bar_show(false)
	launch_hint.visible = false
	var out := create_tween()
	out.tween_property(launch_overlay, "modulate:a", 0.0, Motion.dur(0.4))
	await out.finished
	launch_overlay.visible = false
	launch_art.visible = false
	launch_label.text = ""
	input_locked = false

# Close or restart Tephra (used by the Settings screen).
## Everything Tephra opened goes with it: games, PCSX2, the browser (all its tabs) and Steam.
func close_tephra() -> void:
	fade_out(0.35)  # the screen fades to black first
	await get_tree().create_timer(0.4).timeout
	_plasma_script(PANEL_SHOW_JS, true)  # the taskbar comes back for the desktop
	OS.create_process("setsid", ["sh", "-c", _close_games_script()])
	get_tree().quit()

## Puts on a theme: saved, then the screen fades out and Tephra restarts with the new look.
func apply_theme(theme: String, recolour := false) -> void:
	if (theme == Themes.id() and not recolour) or not Themes.DATA.has(theme):
		return
	if launching:
		toast.show_toast(Icons.texture("info", Icons.svg_info(), 40), "Quit the game first to change the theme", false)
		return
	Themes.choose(theme)
	Themes.reloaded = true
	Themes.switched = not recolour  # the new Home plays this theme's own sound as it fades in (not for a new colour)
	input_locked = true
	# A still picture of the screen as it is now is laid over the whole window (not over Home), so it stays up while
	# every screen is rebuilt underneath it. The new Home is then revealed by dissolving that picture away
	# (see _theme_dissolve), instead of going through black.
	var snap_layer := CanvasLayer.new()
	snap_layer.layer = 125
	snap_layer.name = "ThemeSnap"
	var shot := get_viewport().get_texture().get_image()
	var snap := TextureRect.new()
	snap.texture = ImageTexture.create_from_image(shot)
	snap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	snap.stretch_mode = TextureRect.STRETCH_SCALE
	snap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snap_layer.add_child(snap)
	snap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The new theme's colours fade in over the old screen first, while everything still runs smoothly. The heavy
	# rebuild then happens behind a plain, already-new backdrop, so a pause there reads as a calm moment, not a freeze.
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Themes.c("bg_top"), Themes.c("bg_bottom")])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0.5, 0.0)
	gtex.fill_to = Vector2(0.5, 1.0)
	gtex.width = 8
	gtex.height = 256
	var cover := TextureRect.new()
	cover.name = "Cover"
	cover.texture = gtex
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_SCALE
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.modulate.a = 0.0
	snap_layer.add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(snap_layer)
	var fade_in := create_tween()
	fade_in.tween_property(cover, "modulate:a", 1.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_in.finished
	snap.visible = false
	await get_tree().process_frame
	# Pictures and colours remembered from the old theme are forgotten, so they are made again.
	Icons._cache.clear()
	Themes._swatches.clear()
	TephraGlyphs._cache.clear()
	TephraGlyphs.TEXT = Themes.c("text")
	TephraGlyphs.MUTED = Themes.c("muted")
	preload("res://controllers.gd").NAVY = Themes.c("accent")
	preload("res://battery_alert.gd").THEME = Themes.c("accent")
	# Safety net: whatever happens while the screens are rebuilt, the covering picture never stays up for good
	# (a plain coloured screen). The timer belongs to the tree, so it survives the scene being reloaded.
	var tree := get_tree()
	tree.create_timer(7.0).timeout.connect(func() -> void:
		var stuck := tree.root.get_node_or_null("ThemeSnap")
		if stuck != null:
			stuck.queue_free())
	get_tree().reload_current_scene.call_deferred()

## After a theme change: the picture of the old screen melts away (it swells a little and fades) to show the new
## Home, which has had a moment to be built and drawn once. Returns true if there was a picture to dissolve.
func _theme_dissolve() -> bool:
	var snap_layer := get_tree().root.get_node_or_null("ThemeSnap")
	if snap_layer == null:
		return false
	var cover: Control = snap_layer.get_node_or_null("Cover")
	if cover == null:
		snap_layer.queue_free()
		return false
	var t := cover.create_tween()
	t.tween_property(cover, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(snap_layer.queue_free)
	return true

## Everything game related, closed before Tephra restarts: the running game, PCSX2, and Steam (asked politely first,
## then stopped). Tephra starts fresh with nothing left over from before. tools/install-update.sh does the same.
const CLOSE_GAMES_SH := """
# Everything Steam starts for a game, non-Steam shortcuts included, carries SteamGameId (or STEAM_COMPAT_APP_ID) in
# its environment: the game, the program it hands over to, Proton, Wine and its wineserver. Steam itself never does.
game_pids() {
  for e in /proc/[0-9]*/environ; do
    p=${e#/proc/}; p=${p%/environ}
    [ "$p" = "$$" ] && continue
    grep -qzE '^(SteamGameId|STEAM_COMPAT_APP_ID)=' "$e" 2>/dev/null && echo "$p"
  done
}
pids=$(game_pids); [ -n "$pids" ] && kill $pids 2>/dev/null
pkill -f '[t]ephra/browser' 2>/dev/null
pkill -INT -f '[g]pu-screen-recorder' 2>/dev/null
pkill -f '[S]teamLaunch AppId=' 2>/dev/null
pkill -f '[s]teamapps/common/' 2>/dev/null
pkill -x gamescope 2>/dev/null
flatpak kill net.pcsx2.PCSX2 2>/dev/null; pkill -f '[p]csx2' 2>/dev/null
if pgrep -x steam >/dev/null; then
  steam -shutdown >/dev/null 2>&1 &
  for i in $(seq 1 20); do pgrep -x steam >/dev/null || break; sleep 0.5; done
  pkill -x steam 2>/dev/null; pkill -f steamwebhelper 2>/dev/null
fi
pkill -f 'Xvfb :99' 2>/dev/null
if [ -n "$(game_pids)" ] || pgrep -f '[s]teamapps/common/|[S]teamLaunch AppId=' >/dev/null; then
  sleep 1
  pids=$(game_pids); [ -n "$pids" ] && kill -9 $pids 2>/dev/null
  pkill -9 -f '[s]teamapps/common/' 2>/dev/null; pkill -9 -f '[S]teamLaunch AppId=' 2>/dev/null
fi
"""

## The script above plus every non-Steam program Tephra knows about (their patterns are written so the script never
## matches itself). Used whenever Tephra closes or restarts, so nothing keeps running without it.
## close-all.sh does it all when it is there: it wakes games paused behind a menu (a paused game can't close, which
## is why restarting from the control center left non-Steam games running), then closes every game, Proton, Wine,
## Steam and anything Steam or Tephra started, and forces whatever is left. Its log: ~/.config/tephra/close-all.log
func _close_games_script() -> String:
	var all := ProjectSettings.globalize_path("res://close-all.sh")
	if FileAccess.file_exists(all):
		return "bash '%s'\n" % all.replace("'", "")
	var sh := ""
	for v in _extra_exe.values():
		if str(v) != "":
			sh += "pkill -f '%s' 2>/dev/null\n" % str(v).replace("'", "")
	return sh + CLOSE_GAMES_SH

## Closing Tephra's window by any other way than its own menu (the window's close button, a logout) closes the games and
## Steam too. A restart or an update has done it already, and a second Tephra quitting for a newer copy never gets here.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _restarting:
		OS.create_process("setsid", ["sh", "-c", _close_games_script()])

## After a cancelled launch: anything the game left behind (its launcher, PCSX2, Steam and its hidden screen) is closed
## in the background. Steam is kept only while something is downloading.
func _close_leftovers() -> void:
	var sh := CLOSE_GAMES_SH
	if not library._installing.is_empty():
		sh = "pkill -f '[S]teamLaunch AppId=' 2>/dev/null\nflatpak kill net.pcsx2.PCSX2 2>/dev/null; pkill -f '[p]csx2' 2>/dev/null\n"
	for v in _extra_exe.values():  # non-Steam programs Tephra knows how to find
		if str(v) != "":
			sh += "pkill -f '%s' 2>/dev/null\n" % str(v).replace("'", "")
	OS.create_process("sh", ["-c", sh])

## Something that could be holding a game's files open: a running game or app, Gamescope or Steam.
func anything_running() -> bool:
	if launching or _game_active:
		return true
	for args in [["-x", "steam"], ["-x", "gamescope"], ["-f", "[g]amescope"], ["-f", "[S]teamLaunch AppId="], ["-f", "[p]csx2"], ["-f", "[t]ephra/browser"]]:
		if OS.execute("pgrep", args, []) == 0:
			return true
	for v in _extra_exe.values():
		if str(v) != "" and OS.execute("pgrep", ["-f", str(v).replace("'", "")], []) == 0:
			return true
	return false

## Closes every game and app, Gamescope and Steam (the mod manager does this before it installs or removes a mod).
## Done when nothing is left, or after about 40 seconds.
func close_everything() -> void:
	if launching:
		_close_fast("Closing everything...")
		var w := 0.0
		while launching and w < 25.0:
			await get_tree().create_timer(0.5).timeout
			w += 0.5
	var sh := CLOSE_GAMES_SH + "pkill -x gamescope 2>/dev/null; pkill -f '[g]amescope' 2>/dev/null\n"
	for v in _extra_exe.values():
		if str(v) != "":
			sh += "pkill -f '%s' 2>/dev/null\n" % str(v).replace("'", "")
	sh += "sleep 1\npkill -9 -x gamescope 2>/dev/null; pkill -9 -f '[S]teamLaunch AppId=' 2>/dev/null\n"
	_steam_stopping = true
	var id := WorkerThreadPool.add_task(func() -> void: OS.execute("sh", ["-c", sh], [], true))
	while not WorkerThreadPool.is_task_completed(id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(id)
	_steam_stopping = false
	if _steam_virtual:
		_kill_xvfb()
		_steam_virtual = false

var _restarting := false

# ---------- Bluetooth headphones and speakers going away ----------
## When Bluetooth audio (headphones, a speaker, never a controller) disconnects, PipeWire moves the sound to the
## next output, so a game would suddenly play out loud. Tephra mutes that output instead, and unmutes it again when
## the Bluetooth device comes back. Checked every 2 s on a worker thread.
var _bt_acc := 0.0
var _bt_busy := false
var _bt_sink := ""        # the Bluetooth output that was the default last time
var _bt_muted := ""       # the output Tephra muted when it went away

func _bt_audio_poll(delta: float) -> void:
	_bt_acc += delta
	if _bt_acc < 2.0 or _bt_busy:
		return
	_bt_acc = 0.0
	_bt_busy = true
	var box := {}
	box["id"] = _work(func() -> void:
		var out := []
		var info := ""
		if OS.execute("pactl", ["get-default-sink"], out) == 0 and not out.is_empty():
			info = str(out[0]).strip_edges()
		var sinks := []
		var out2 := []
		if OS.execute("pactl", ["list", "short", "sinks"], out2) == 0 and not out2.is_empty():
			for l in str(out2[0]).split("\n"):
				var parts := l.split("\t")
				if parts.size() > 1:
					sinks.append(parts[1])
		_bt_audio_done.call_deferred(box, info, sinks))

func _bt_audio_done(box: Dictionary, default_sink: String, sinks: Array) -> void:
	_work_done(int(box["id"]))
	_bt_busy = false
	if default_sink == "" or sinks.is_empty():
		return
	if default_sink.begins_with("bluez_"):
		if _bt_muted != "" and _bt_muted != default_sink:
			OS.execute("pactl", ["set-sink-mute", _bt_muted, "0"])  # the speakers are unmuted again
			_bt_muted = ""
		_bt_sink = default_sink
		return
	if _bt_sink != "" and not sinks.has(_bt_sink):
		# the Bluetooth output is gone (disconnected, not just switched away from): silence the output now playing
		OS.execute("pactl", ["set-sink-mute", default_sink, "1"])
		_bt_muted = default_sink
		_bt_sink = ""
		notify("Bluetooth audio disconnected. Sound is muted.", "info")

## Restart or turn off the PC: the screen fades to black first.
func power_command(what: String) -> void:
	fade_out(0.5)
	await get_tree().create_timer(0.55).timeout
	OS.create_process("systemctl", [what])

## The whole screen fades to black (over everything, the boot logo included) and back: used when updating and restarting.
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect

func fade_out(t := 0.6) -> void:
	if _fade_layer == null:
		_fade_layer = CanvasLayer.new()
		_fade_layer.layer = 120
		_fade_rect = ColorRect.new()
		_fade_rect.color = Color.BLACK
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_fade_rect.modulate.a = 0.0
		_fade_layer.add_child(_fade_rect)
		add_child(_fade_layer)
	_fade_rect.visible = true
	create_tween().tween_property(_fade_rect, "modulate:a", 1.0, t)

func fade_in(t := 0.4) -> void:
	if _fade_rect == null:
		return
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 0.0, t)
	tw.tween_callback(func() -> void: _fade_rect.visible = false)

func restart_tephra() -> void:
	if _restarting:
		return  # already on its way (an update and the file watcher can both ask)
	_restarting = true
	fade_out(0.35)
	await get_tree().create_timer(0.4).timeout
	# The new Tephra must not belong to this one, or it goes down with it. setsid leaves this one's session, and
	# systemd-run --scope moves it out of this one's group of processes: Plasma starts Tephra in its own systemd
	# scope, which can be stopped (with everything in it) the moment this Tephra quits.
	# Best is a separate systemd service: nothing about this Tephra (its session, its scope) can take it down.
	# It gets this Tephra's screen, sound and desktop settings handed over (a service starts with almost none).
	# Started by tephra-run.sh (the launcher): leave it a note and quit, and it starts the new Tephra itself.
	if OS.get_environment("TEPHRA_SUPERVISED") == "1":
		var flag := OS.get_environment("XDG_RUNTIME_DIR")
		flag = (flag if flag != "" else "/tmp") + "/tephra-restart"
		var nf := FileAccess.open(flag, FileAccess.WRITE)
		if nf != null:
			nf.store_string("restart")
			nf.close()
			OS.execute("sh", ["-c", _close_games_script()])
			get_tree().quit()
			return
	# Not under the launcher (an old autostart entry): start the launcher, so every restart after this one is safe.
	var launcher := ProjectSettings.globalize_path("res://tephra-run.sh")
	var script := _close_games_script() + "sleep 1; exec \"$0\" --path \"$1\" --fullscreen"
	var args := ["sh", "-c", script, OS.get_executable_path(), ProjectSettings.globalize_path("res://")]
	if FileAccess.file_exists(launcher):
		OS.execute("chmod", ["+x", launcher])
		args = ["sh", "-c", _close_games_script() + "sleep 1; exec \"$0\"", launcher]
	if OS.execute("sh", ["-c", "command -v systemd-run >/dev/null"]) == 0:
		var run := ["systemd-run", "--user", "--collect", "--quiet", "--unit=tephra-restart-%d" % int(Time.get_unix_time_from_system())]
		for v in ["WAYLAND_DISPLAY", "DISPLAY", "XDG_RUNTIME_DIR", "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP",
				"DBUS_SESSION_BUS_ADDRESS", "HOME", "USER", "PATH", "LANG", "XAUTHORITY", "KDE_FULL_SESSION", "QT_QPA_PLATFORM", "PULSE_SERVER"]:
			if OS.has_environment(v):
				run.append("--setenv=%s=%s" % [v, OS.get_environment(v)])
		args = run + args
	OS.create_process("setsid", args)
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()

# ---------- Details section (press Down) ----------
func _details_vertical(dir: int, n := 1) -> void:
	if in_details:
		if n > 1:
			details.scroll_by(dir * n)  # fast scroll never leaves the section
		elif not details.move(dir):
			_leave_details()  # Up on the first achievement goes back to the games
	elif dir > 0:
		_enter_details()

func _enter_details() -> void:
	_flush_details()  # Down was pressed before the cursor "rested": build the page now
	if in_details or not details.has_content or _library_selected():
		return
	in_details = true
	details.enter()
	_glide_page(-(size.y - PEEK - DETAIL_TOP))

## The Channels theme's Home button: the Home page (storage, stats, newest achievements...) slides up over the channels.
func open_home_page() -> void:
	details.visible = true
	_queue_details("recent", -1, false)
	_enter_details()
	details.modulate.a = 0.0  # it fades in as it slides up (see _process), so its top edge never shows as a strip

func _leave_details() -> void:
	if not in_details:
		return
	in_details = false
	details.leave()
	_glide_page(0.0)
	if channels != null:
		# Channels: the page fades out quickly while the bar slides back down (see _process), so none of it is
		# left peeking out under the bar for the last moments of the slide.
		get_tree().create_timer(0.5).timeout.connect(func():
			if not in_details:
				details.visible = false)  # hidden again in the Channels theme: its Home button brings it back

# Slides everything (top bar, row, details) up or down together, and darkens
# the game art behind the details so the text is easy to read.
func _glide_page(y: float) -> void:
	if _page_tween != null:
		_page_tween.kill()
	_page_tween = create_tween().set_parallel()
	_page_tween.tween_property(page, "position:y", y, Motion.dur(0.4)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_page_tween.tween_property(detail_dim, "modulate:a", 1.0 if y < 0.0 else 0.0, Motion.dur(0.4))

# PS / Guide button (F1 on a keyboard for testing).
# Quick press = control center, hold = home (swap in Settings > Controller).
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventKey or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		var was_idle := _idle_s > 10.0
		_idle_s = 0.0
		if was_idle:
			_power_apply()  # wake up to full speed right away
	# Switch button glyphs to match whichever controller (or keyboard) was used.
	if TephraGlyphs.update_from_event(event):
		_refresh_all_hints()
	# A game is running that Tephra isn't following, and it has the screen: the pad belongs to the game. Only PS still
	# reaches Tephra (holding it takes the game on and pauses it).
	if _foreign_game and not launching and not get_window().has_focus() \
			and not (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_GUIDE):
		get_viewport().set_input_as_handled()
		return
	# The controller test reads the pad itself: no button does anything else meanwhile (no sounds, no PS, no screenshots).
	if controller_test.is_open:
		get_viewport().set_input_as_handled()
		return
	# Capture button: the touchpad click on PlayStation pads, Share on Xbox pads, Capture on Switch pads (Share and Capture
	# arrive as MISC1). A press takes a screenshot (on release), holding it ~1.5 s starts or stops recording. Back/Select is
	# left alone, so games that use Select + Start (Xbox layouts) always get both.
	# A DualSense's Create also arrives as MISC1, but Create is the game's Select (Steam passes it on as Select), so on a
	# PlayStation pad it is never a capture button: one press used to open the game's map AND take a screenshot.
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_MISC1 and TephraGlyphs.family_for_device(event.device) == "ps":
		return
	if event is InputEventJoypadButton and bool(Settings.get_value("screenshot_btn", true)) \
			and (event.button_index == JOY_BUTTON_MISC1 or event.button_index == JOY_BUTTON_TOUCHPAD):
		_capture_edge(event.pressed)
		return
	var is_guide: bool = event is InputEventJoypadButton and event.button_index == JOY_BUTTON_GUIDE
	var is_f1: bool = event is InputEventKey and event.keycode == KEY_F1
	# The browser has the screen: the pad moves its pointer, clicks and scrolls (PS still opens the menu).
	if not (is_guide or is_f1) and _game_id == browser.ID and _game_started and not _in_overlay and not _overlay_busy \
			and not keyboard.is_open and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		if browser.handle_input(event, self):
			get_viewport().set_input_as_handled()
		return
	if not (is_guide or is_f1):
		return
	get_viewport().set_input_as_handled()
	if input_locked or event.is_echo():
		return
	if event.is_pressed():
		guide_down_ms = Time.get_ticks_msec()
		if (not library._installing.is_empty() or _steam_virtual) and not _game_started and _steam_running():
			_hush_steam()
		guide_long_fired = false
		if launching and _game_started and not _in_overlay and not _overlay_busy:
			# Only the preparation starts now: the game's picture is grabbed and the frame rate goes up, so that by
			# the time PS comes back up (a tap) the menu opens at once. The menu itself waits for the release, because
			# a press that goes on past LONG_PRESS_MS is "Home", and opening the control center first only to swap it
			# for Home a moment later was what made going Home so awkward.
			overlay.prefetch_shot()
			_boost_for_menu()
	elif guide_down_ms >= 0:
		guide_down_ms = -1
		if not guide_long_fired:
			_on_guide_short()

# The Create button saves a screenshot of Tephra to ~/Pictures/Tephra.
func _take_screenshot() -> void:
	var dir := OS.get_environment("HOME") + "/Pictures/Tephra"
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/Tephra_%s.png" % [dir, stamp]
	sfx.play("shutter")
	if launching and _game_started:
		_take_game_photo(path)
		return
	# Only grabbing the picture has to happen now. Writing a 2560x1440 PNG and making the album thumbnail take
	# a few hundred milliseconds, which froze the screen, so both happen on a worker thread.
	var img := get_viewport().get_texture().get_image()
	if img == null:
		toast.show_toast(Icons.texture("no", Icons.svg_no(), 40), "Couldn't save screenshot", false)
		return
	var box := {}
	box["id"] = _work(func() -> void:
		var ok := img.save_png(path) == OK
		var thumb := img.duplicate() as Image
		thumb.resize(640, maxi(int(640.0 * thumb.get_height() / maxf(thumb.get_width(), 1.0)), 1), Image.INTERPOLATE_BILINEAR)
		_shot_saved.call_deferred(box, path, ok, thumb))

## A photo while a game is running. Tephra's own screen only shows its menus, so the picture comes from
## the real screen: the sharp picture already taken when the menu is open over the game, or a fresh
## full-resolution grab of the screen while the game is showing. Saved as PNG (no quality loss).
func _take_game_photo(path: String) -> void:
	var img: Image = _overlay_shot if _in_overlay else null
	if img == null and not _in_overlay:
		var ok: bool = await overlay.capture_screen(path)
		if not ok:
			_screenshot_done(path, false, null)
			return
		img = Image.load_from_file(path)
		if img == null or img.is_empty():
			_screenshot_done(path, false, null)
			return
		var thumb0 := img.duplicate() as Image
		thumb0.resize(640, maxi(int(640.0 * thumb0.get_height() / maxf(thumb0.get_width(), 1.0)), 1), Image.INTERPOLATE_BILINEAR)
		_screenshot_done(path, true, thumb0)
		return
	if img == null:
		_screenshot_done(path, false, null)
		return
	var shot := img.duplicate() as Image
	var box := {}
	box["id"] = _work(func() -> void:
		var ok := shot.save_png(path) == OK
		var thumb := shot.duplicate() as Image
		thumb.resize(640, maxi(int(640.0 * thumb.get_height() / maxf(thumb.get_width(), 1.0)), 1), Image.INTERPOLATE_BILINEAR)
		_shot_saved.call_deferred(box, path, ok, thumb))

func _shot_saved(box: Dictionary, path: String, ok: bool, thumb: Image) -> void:
	_work_done(int(box["id"]))
	_screenshot_done(path, ok, thumb)

func _screenshot_done(path: String, ok: bool, thumb: Image) -> void:
	if ok:
		toast.show_toast(Icons.texture("check", Icons.svg_check(), 40), "Screenshot saved", false)
		album.photo_added(path, thumb)  # if the Album is open, the new photo glides into it
		print("Tephra: screenshot saved to ", path)
	else:
		toast.show_toast(Icons.texture("no", Icons.svg_no(), 40), "Couldn't save screenshot", false)

func _on_guide_short() -> void:
	if bool(Settings.get_value("guide_swap", false)):
		_go_home()
	else:
		_toggle_cc()

# Home = everything closed, back on the Home tile.
func _on_guide_long() -> void:
	if bool(Settings.get_value("guide_swap", false)):
		_toggle_cc()
	else:
		_go_home()

func _toggle_cc() -> void:
	if launching and not _game_started and not _overlay_busy:
		# On the loading screen: the control center opens over it (it sits above the launch screen).
		if cc.is_open:
			cc.close()
		else:
			_open_cc()
		return
	if launching:
		# In a game: PS pauses it and opens the control center; PS again goes back to the game.
		if _game_started and not _quit_flow:
			if _in_overlay and _overlay_mode == "home" and not _overlay_busy:
				# Home over the paused game: PS opens the control center on top of it (the game stays muted).
				if cc.is_open:
					cc.close()
				else:
					_open_cc()
			elif _in_overlay:
				_overlay_close()
			else:
				_overlay_open("cc")
		return
	if cc.is_open:
		cc.close()
	else:
		_open_cc()

func _open_cc() -> void:
	sfx.play("panel")
	_leave_details()
	# Where the clock sits once the page has slid back down.
	var r := clock_label.get_global_rect()
	r.position.y -= page.position.y
	var sr := shard_icon.get_global_rect()
	sr.position.y -= page.position.y
	var wr := wifi_icon.get_global_rect()
	wr.position.y -= page.position.y
	cc.hud_status = ""
	cc.open(r, shard_icon.texture, sr, wifi_icon.texture, wr)
	cc.match_clock(clock_label, r)

## Holding PS while Home is meant to be up: always pull Tephra to the front again and make sure the game is paused
## and silent, whatever got out of step.
func _reassert_home() -> void:
	overlay.log_line("hold PS: bringing Home back to the front")
	overlay.mute_game(_game_id, true, _game_pattern())
	overlay.freeze_game(_game_id, _game_pattern())
	visible = true
	await overlay.run_shortcuts(["TephraRaise"])
	DisplayServer.window_move_to_foreground()
	await overlay.run_shortcuts(["TephraReveal"])

## A Steam game is running but Tephra isn't following it (it lost track, or the game was started some other way).
## Tephra takes it on as if it had launched it, so holding PS can pause it and Home can resume or quit it.
## Returns false when no game is running.
func _adopt_running_game() -> bool:
	var out := []
	if OS.execute("pgrep", ["-af", "[S]teamLaunch AppId="], out) != 0 or out.is_empty():
		return false
	var m := RegEx.create_from_string("AppId=(\\d+)").search(String(out[0]))
	if m == null:
		return false
	var id := m.get_string(1)
	var title := "Your game"
	for g in games:
		if str(g["id"]) == id:
			title = str(g["title"])
	overlay.log_line("taking on game %s, which was running without Tephra following it" % id)
	launching = true
	_game_id = id
	_game_title = title
	_game_started = true
	_game_started_ms = Time.get_ticks_msec()
	_quit_now = false
	cc.game_id = id
	cc.game_running = true
	launch_overlay.visible = true
	launch_overlay.modulate.a = 1.0
	_set_game_active(true)
	_watch_adopted(id)
	return true

func _watch_adopted(id: String) -> void:
	while _game_running(id) and not _quit_now:
		await get_tree().create_timer(1.0).timeout
	if _game_id != id:
		return
	DisplayServer.window_move_to_foreground()
	if overlay.kwin_ok:
		overlay.reveal_tephra()
	_return_home()

func _go_home() -> void:
	if launching:
		# In a game: holding PS pauses it and shows Home. The game stays suspended until you
		# resume it from its tile (or quit it from the control center).
		if _game_started and not _quit_flow:
			if _in_overlay and _overlay_mode == "home":
				_reassert_home()  # Tephra thinks Home is up, but the game may have taken the screen back
			elif not _overlay_busy:
				_overlay_open("home")
			else:
				# PS went down, the control center is still opening, and PS is still held: Home as soon as it is up.
				var waited := 0
				while _overlay_busy and waited < 120:
					await get_tree().process_frame
					waited += 1
				if launching and _in_overlay and _overlay_mode != "home":
					_overlay_open("home")
		return
	if _adopt_running_game():
		_overlay_open("home")  # a game Tephra had lost track of: pause it and show Home over it
		return
	if color_picker.is_open:
		color_picker.close()
	if hdr_calibration.is_open:
		hdr_calibration.close()
	if controller_test.is_open:
		controller_test.close()
	if scene_test.is_open:
		scene_test.close()
	if top_menu.is_open:
		top_menu.close()
	if cc.is_open:
		cc.close()
	if library.is_open:
		library.close()
	if album.is_open:
		album.close()
	if mods.is_open:
		mods.close()
	if profile_screen.is_open:
		profile_screen.close()
	if settings_screen.is_open:
		settings_screen.close()
	_focus_profile(false)
	_leave_details()
	_select(0)
	if channels != null and channels.has_method("go_home"):
		channels.go_home()  # the themes with a Home icon of their own (Circuit, Planet) move onto it

func _unhandled_input(event: InputEvent) -> void:
	if _fake_loading:
		if event.is_action_pressed("ui_cancel") and not event.is_echo():
			_fake_loading = false  # the loop in dev_fake_loading() sees this and fades the screen out
		return
	if launching and _launch_cancellable and not cc.is_open and event.is_action_pressed("ui_cancel") and not event.is_echo():
		Haptics.tick()
		sfx.play("back")  # cancelling the loading screen has its own little sound
		_launch_cancel = true
		_pulse_cancel()
		return
	if launching and not _game_started and cc.is_open and not _overlay_busy:
		if cc.handle_input(event):
			return
	if (launching and not _in_overlay) or input_locked or _overlay_busy:
		return
	if overlay.handle_input(event):
		return
	if phone_screen.handle_input(event):
		return
	if keyboard.handle_input(event):
		return
	if game_menu.handle_input(event):
		return
	if _placing_perf:
		_place_input(event)
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		Haptics.confirm()  # pressing A on anything
		sfx.play("confirm")
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		Haptics.tick()  # going back
		sfx.play("back")
	if color_picker.handle_input(event):
		return
	if hdr_calibration.handle_input(event):
		return
	if controller_test.handle_input(event):
		return
	if scene_test.handle_input(event):
		return
	if cc.handle_input(event):
		return
	if not cc.is_open and mods.handle_input(event):
		return
	if not cc.is_open and album.handle_input(event):
		return
	if profile_screen.handle_input(event):
		return
	if settings_screen.handle_input(event):
		return
	if top_menu.handle_input(event):
		return
	if not cc.is_open and setup_screen.handle_input(event):
		return
	if library.handle_input(event):
		return
	if profile_focus:
		if event.is_action_pressed("ui_accept"):
			_open_profile()
		elif event.is_action_pressed("ui_cancel"):
			_focus_profile(false)
		return
	if channels != null and not in_details and event is InputEventJoypadMotion and event.axis == JOY_AXIS_RIGHT_X:
		channels.handle_input(event)  # Channels: the right stick flips pages
		return
	if event is InputEventJoypadMotion:
		return  # directions come from nav.gd
	if in_details:
		if event.is_action_pressed("ui_accept") and details.on_today():
			details.today_activate()
		elif event.is_action_pressed("ui_cancel"):
			_leave_details()
		elif (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_LEFT_SHOULDER) \
				or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q and not event.ctrl_pressed):
			details.page_step(-1)  # L1: previous page
		elif (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_SHOULDER) \
				or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E):
			details.page_step(1)  # R1: next page
		return
	if channels != null and channels.handle_input(event):
		return
	if event.is_action_pressed("ui_accept"):
		var gi_acc := _game_selected()
		if cross_opens_info() and gi_acc >= 0 and not launching and not _overlay_busy:
			library.open_game(games[gi_acc], null)  # Settings > Games: Cross shows the game's page first
		else:
			_launch()
	elif (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.north_button()) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Y):
		var gi_tri := _game_selected()
		if launching and _in_overlay and gi_tri >= 0 and str(games[gi_tri]["id"]) == _game_id:
			_open_game_menu(gi_tri)  # the game being played: Resume, Close game, Unpin, Mods (Cross goes straight back in)
		elif cross_opens_info():
			pass  # "info first" mode: Triangle does nothing, Cross opens the page
		elif channels != null and not launching and not _overlay_busy:
			channels.info_selected()  # Channels / PS2: Triangle opens the game's page, like pressing A on it in the Library
		else:
			_open_game_menu()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q and event.ctrl_pressed and event.alt_pressed:
		close_tephra()  # developer exit: Ctrl+Alt+Q (Esc no longer quits)

# A small card at the bottom left while Steam is installing a game, so progress is visible
# on every screen (the Library tile also shows its own bar).
var dl_pill: PanelContainer
var dl_label: Label
var dl_bar: ProgressBar
var _dl_t := 0.0

func _make_download_pill() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 96
	add_child(layer)
	dl_pill = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Themes.c("panel"), 0.92)
	sb.set_corner_radius_all(Themes.r(16))
	sb.set_content_margin_all(16)
	dl_pill.add_theme_stylebox_override("panel", sb)
	dl_pill.modulate.a = 0.0
	dl_pill.visible = false
	dl_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dl_pill)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	dl_pill.add_child(vb)
	dl_label = _label("", 22, TEXT)
	vb.add_child(dl_label)
	dl_bar = ProgressBar.new()
	dl_bar.show_percentage = false
	dl_bar.min_value = 0.0
	dl_bar.max_value = 1.0
	dl_bar.custom_minimum_size = Vector2(380, 12)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Themes.ink(0.18)
	bgs.set_corner_radius_all(Themes.r(6))
	var fill := StyleBoxFlat.new()
	fill.bg_color = SELECT
	fill.set_corner_radius_all(Themes.r(6))
	dl_bar.add_theme_stylebox_override("background", bgs)
	dl_bar.add_theme_stylebox_override("fill", fill)
	vb.add_child(dl_bar)

func _update_download_pill(delta: float) -> void:
	if dl_pill == null:
		return
	_dl_t += delta
	if _dl_t >= 0.5:
		_dl_t = 0.0
		var list: Array = library.downloads() if library != null else []
		if list.is_empty():
			dl_pill.set_meta("active", false)
		else:
			dl_pill.set_meta("active", true)
			var d: Dictionary = list[0]
			var pct := float(d["pct"])
			dl_label.visible = false  # only the bar: no game names or percentages popping up on Home
			dl_bar.value = maxf(pct, 0.0)
			dl_pill.reset_size()
			dl_pill.position = Vector2(80, size.y - dl_pill.size.y - 64)
	var want: bool = bool(dl_pill.get_meta("active", false)) and not launching and not cc.is_open
	if want:
		dl_pill.visible = true
	dl_pill.modulate.a = move_toward(dl_pill.modulate.a, 1.0 if want else 0.0, delta * 4.0)
	if not want and dl_pill.modulate.a <= 0.0:
		dl_pill.visible = false

# ---------- Power: use as little GPU as possible ----------
# Tephra slows to 60 FPS after a while
# with no input, and stops drawing altogether while a game runs (a hidden screen costs nothing;
# a covered one is still rendered by Godot).
var _base_fps := 0
var _game_active := false
var _power_t := 0.0
# True from the moment PS goes down over a running game until the menu is up. Tephra idles at 20 fps behind a
# game (nothing is drawn), which made every step of opening the menu wait up to 50 ms for the next frame:
# the PS press itself, waiting for the picture of the game, and the two frames before the menu shows.
var _menu_boost := false
var _menu_boost_id := 0

func _wanted_fps() -> int:
	var cap := int(Settings.get_value("fps_cap", _base_fps))
	var fps := maxi(cap, 0)  # -1 is "Variable": no limit (the sync mode is set in settings_screen.apply_display)
	if Visuals.saver():
		fps = 30  # Power saver locks the frame limit at 30 and keeps it there
	if _game_active:
		# Nothing is drawn (see _set_game_active), so a fast loop costs next to nothing. 20 fps is plenty while
		# the PS button is not being used; 120 while a menu is on its way up keeps every wait down to a few ms.
		return 120 if _menu_boost else 20
	if not Visuals.saver() and _idle_s > 25.0 and (fps == 0 or fps > 60):
		fps = 60  # nobody is touching the controller: settle at 60 (never lower) until they do
	return fps

var _gpu_task := -1

## Reads the GPU load and temperature without stopping the screen: nvidia-smi takes 20-40 ms to answer,
## which on the main thread was a visible hitch every 2 seconds.
func _poll_gpu() -> void:
	if _gpu_task != -1:
		return  # the last read has not finished yet
	_gpu_task = _work(func() -> void:
		var d: Dictionary = perf.gpu_now()
		_gpu_done.call_deferred(d))

func _gpu_done(d: Dictionary) -> void:
	_work_done(_gpu_task)
	_gpu_task = -1
	_dev_gpu = d

func _power_apply() -> void:
	# Hands off until the intro has finished, so the first frames are never throttled.
	if input_locked:
		return
	var fps := _wanted_fps()
	if Engine.max_fps != fps:
		Engine.max_fps = fps
	# Low-processor mode is deliberately NOT used: on some GPU/window setups it left the
	# window white because nothing asked for a redraw after the intro. The FPS limiter alone
	# gives most of the saving.

## PS went down over a running game: speed the main loop up until the menu is showing (see _menu_boost).
func _boost_for_menu() -> void:
	_menu_boost = true
	_menu_boost_id += 1
	var mine := _menu_boost_id
	_power_apply()
	await get_tree().create_timer(4.0).timeout
	# The press ended without opening a menu (or it never got going): back to the slow, cheap rate.
	if mine == _menu_boost_id and _menu_boost and not _in_overlay and not _overlay_busy:
		_menu_boost = false
		_power_apply()

func _set_game_active(on: bool) -> void:
	_menu_boost = false
	_game_active = on
	TephraBg.paused = on
	visible = not on  # a hidden screen isn't rendered at all
	RenderingServer.render_loop_enabled = not on  # no frames at all while a game owns the screen
	if on and dev_layer != null:
		dev_layer.visible = false
	_power_apply()

# Dim the screen after a few minutes without input (Settings > System > Screen rest).
func _update_idle(delta: float) -> void:
	_idle_s += delta
	_power_t += delta
	if _power_t >= 0.5:
		_power_t = 0.0
		_power_apply()
	var mins := int(Settings.get_value("idle_minutes", 0))
	var rest: bool = mins > 0 and _idle_s > mins * 60.0 and not launching
	if rest_bg == null:
		idle_cover.modulate.a = move_toward(idle_cover.modulate.a, 0.82 if rest else 0.0, delta * (0.4 if rest else 4.0))
		return
	idle_cover.modulate.a = move_toward(idle_cover.modulate.a, 0.35 if rest else 0.0, delta * (0.25 if rest else 4.0))
	rest_bg.modulate.a = move_toward(rest_bg.modulate.a, 1.0 if rest else 0.0, delta * (0.5 if rest else 4.0))
	rest_bg.visible = rest_bg.modulate.a > 0.0

# ---------- Reload after an update ----------
# The updater script replaces the .gd files while Tephra is running. Every couple of
# seconds Tephra compares their modified times; when they change it waits until no game
# is running, then restarts itself so the new version loads. (Does nothing in a packaged build.)
var _code_stamp := -1
var _code_check := 0.0

func _code_modified() -> int:
	var newest := 0
	for f in DirAccess.get_files_at("res://"):
		if f.ends_with(".gd"):
			newest = maxi(newest, int(FileAccess.get_modified_time("res://" + f)))
	return newest

func _check_for_update(delta: float) -> void:
	_code_check += delta
	if _code_check < 2.0:
		return
	_code_check = 0.0
	var now := _code_modified()
	if _code_stamp < 0:
		_code_stamp = now
	elif now != _code_stamp and not launching and library._installing.is_empty() and preload("res://self_update.gd").state != "installing":
		_code_stamp = now
		if OS.execute("pgrep", ["-f", "install-update[.]sh"], []) == 0:
			return  # the install script restarts Tephra itself when it is done: two restarts at once can leave none running
		await get_tree().create_timer(1.5).timeout  # let the updater finish copying all files
		if _code_modified() == now and bool(Settings.get_value("auto_restart_update", true)):
			restart_tephra()

var _esc_hold := 0.0
var _game_started_ms := 0

## Stuck on a black screen after starting a game? Holding Circle for 1.5 s (within the first 3 minutes) closes it and
## goes back Home. Only works while Tephra still has the pad, which is exactly the stuck case.
func _escape_hold_check(delta: float) -> void:
	var stuck_window := launching and _game_started and not _in_overlay and not _quit_flow and Time.get_ticks_msec() - _game_started_ms < 180000
	if stuck_window and Input.is_action_pressed("ui_cancel"):
		_esc_hold += delta
		if _esc_hold >= 1.5:
			_esc_hold = -1000.0
			_install_log("escape: Circle held while the game was loading, closing it")
			_quit_flow = true
			_close_fast("Going back...")
	elif _esc_hold > -500.0:
		_esc_hold = 0.0
	elif not Input.is_action_pressed("ui_cancel"):
		_esc_hold = 0.0

func _process(delta: float) -> void:
	_escape_hold_check(delta)
	_bar_step(delta)
	if _game_active:
		# A game owns the screen: nothing of Tephra is drawn, so none of the upkeep below runs
		# (battery, Wi-Fi, downloads, overlays). Only holding PS still has to be noticed.
		_guide_hold_check()
		_capture_hold_check()  # holding the touchpad still starts or stops a recording in a game
		_update_poll(delta)  # updates are still looked for during a game or the browser (the check runs on a worker)
		_links_poll(delta)
		_bt_audio_poll(delta)
		return
	if _neon_title:
		# the title rocks and breathes slowly, the way retro menus wobble
		_neon_t += delta
		title_label.pivot_offset = Vector2(0, title_label.size.y)
		title_label.rotation = 0.035 * sin(_neon_t * 1.1)
		title_label.scale = Vector2.ONE * (1.0 + 0.025 * sin(_neon_t * 1.7))
	_foreign_acc += delta
	if _foreign_acc >= 3.0:
		_foreign_acc = 0.0
		_foreign_game = not launching and _any_game_running()
	_steam_sweep(delta)
	_dl_poll(delta)
	_auto_update_tick(delta)  # games update by themselves while you are on Home
	_update_poll(delta)
	_links_poll(delta)
	_bt_audio_poll(delta)
	var pr := preload("res://frame_probe.gd")  # timing marks for the frame probe (no-ops unless it is on)
	var m := Time.get_ticks_usec()
	_check_for_update(delta)
	pr.mark("update check", m)
	m = Time.get_ticks_usec()
	_update_battery_icon(delta)
	pr.mark("controller icon", m)
	m = Time.get_ticks_usec()
	_update_laptop_battery(delta)
	pr.mark("laptop battery", m)
	m = Time.get_ticks_usec()
	_update_alert_pill(delta)
	_update_download_pill(delta)
	pr.mark("pills", m)
	m = Time.get_ticks_usec()
	_update_idle(delta)
	pr.mark("idle/power", m)
	if dev_layer != null:
		# The info bar is always part of the control center (dimmed when hidden or empty). Elsewhere it only
		# shows when "Performance info on every screen" is on and the bar isn't hidden.
		var want_perf: bool = (cc.is_open or _placing_perf or (bool(Settings.get_value("dev_overlay", false)) and _bar_state() == "shown")) and (not launching or _in_overlay)
		dev_layer.visible = want_perf
		if want_perf:
			_update_dev_overlay(delta)
			_place_dev_overlay()
			dev_style.set_border_width_all(3 if (cc.is_open and cc.bar_selected) or _placing_perf else 0)
			cc.bar_rect = dev_pill.get_global_rect()
			if not _placing_perf:
				cc.bar_zone = _current_zone()
	# The control center has its own clock and hints, so fade the home ones out
	# under it. Fading (not hiding) keeps the layout still, so nothing jumps.
	var target := 0.0 if cc.is_open else 1.0
	clock_label.modulate.a = move_toward(clock_label.modulate.a, target, delta * 6.0)
	# The details section has its own hints, so the row's hints fade out there.
	var screen_open: bool = library.is_open or profile_screen.is_open or settings_screen.is_open or top_menu.is_open or setup_screen.is_open
	var hint_target := 0.0 if cc.is_open or in_details or screen_open else 1.0
	hints.modulate.a = move_toward(hints.modulate.a, hint_target, delta * 6.0)
	details.hide_arrow = cc.is_open or screen_open or profile_focus or channels != null  # Channels / PS2: the Home button opens that page, not Down  # it fades out while you are up in the top bar
	# Screens opened from home (Library, Profile, Settings) hide their own hints under the
	# control center, which has its own, so two sets of glyphs never overlap.
	var under_cc := 0.0 if cc.is_open else 1.0
	for scr in [library, profile_screen, settings_screen, top_menu, setup_screen]:
		var hb: HBoxContainer = scr._hints
		hb.modulate.a = move_toward(hb.modulate.a, under_cc, delta * 6.0)
	# Details: top edge peeks out under the row; fills the screen once scrolled to.
	# Background music: in every menu, but never while a game is starting or running (not even in the
	# control center over a game: you hear the game, or nothing while it is paused), nor during the boot
	# logo. Checked twice a second. With the control center open the music steps back (softer, duller).
	_music_t += delta
	if _music_t >= 0.5:
		_music_t = 0.0
		var music_on: bool = bool(Settings.get_value("music_on", true)) and not launching and not album.clip_playing() and (not input_locked or _music_early)
		sfx.set_music("home", music_on)
	sfx.set_distant(cc.is_open)
	if top_arrow != null and top_arrow.modulate.a > 0.01:
		top_arrow.queue_redraw()  # it bobs gently while the top bar has the focus
	# The stretched copy behind the hero follows it (same picture, same fade), but dim.
	if hero_back.texture != hero.texture:
		hero_back.texture = hero.texture
	hero_back.modulate = Color(1, 1, 1, hero.modulate.a * 0.3) if Themes.light() else Color(0.42, 0.44, 0.5, hero.modulate.a)
	m = Time.get_ticks_usec()
	# Channels: the Home page sits lower, so the round Home and Settings buttons (which slide up with the bar) show in full
	# above it instead of being half covered by the page.
	var drop := CHANNELS_PAGE_DROP if channels != null else 0.0
	details.position = Vector2(0, size.y - PEEK + drop)
	details.size = Vector2(size.x, size.y - DETAIL_TOP - drop)
	pr.mark("details layout", m)
	var show_details: bool = details.has_content and not _library_selected()
	if channels != null:
		details.modulate.a = move_toward(details.modulate.a, 1.0 if in_details else 0.0, delta * (4.0 if in_details else 14.0))
	else:
		details.modulate.a = move_toward(details.modulate.a, 1.0 if show_details else 0.0, delta * 5.0)
	nav.enabled = (not launching or _in_overlay or _cc_over_loading()) and not input_locked and not overlay.confirm_open and not _overlay_busy
	_guide_hold_check()
	_capture_hold_check()
	_keep_on_top(delta)
	m = Time.get_ticks_usec()
	clock_label.text = Settings.clock_text()
	pr.mark("clock text", m)

# Holding the capture button (the touchpad click) starts a screen recording, and holding it again stops it. A quick
# press takes a screenshot on release, so the hold only has to be clearly longer than a tap.
const REC_HOLD_MS := 600
var _rec_pid := -1
var _rec_path := ""
var _rec_dot: CanvasLayer

func _capture_hold_check() -> void:
	if capture_down_ms >= 0 and not capture_long_fired and Time.get_ticks_msec() - capture_down_ms >= REC_HOLD_MS:
		capture_long_fired = true  # also keeps the release from taking a screenshot
		Haptics.tick()
		_toggle_recording()

func _recording() -> bool:
	return _rec_pid > 0 and OS.is_process_running(_rec_pid)

func _toggle_recording() -> void:
	if _recording():
		OS.execute("kill", ["-INT", str(_rec_pid)])  # the recorder finishes the file when it is interrupted
		var path := _rec_path
		_rec_pid = -1
		_show_rec(false)
		sfx.play("rec_stop")
		toast.show_toast(Icons.texture("check", Icons.svg_check(), 40), "Recording saved", false)
		print("Tephra: recording saved to ", path)
		return
	var gpu := OS.execute("sh", ["-c", "command -v gpu-screen-recorder >/dev/null"]) == 0
	var spec := OS.execute("sh", ["-c", "command -v spectacle >/dev/null"]) == 0
	if not gpu and not spec:
		toast.show_toast(Icons.texture("no", Icons.svg_no(), 40), "Recording needs gpu-screen-recorder or spectacle installed", false)
		print("Tephra: recording needs gpu-screen-recorder (AUR) or spectacle (Arch: sudo pacman -S spectacle)")
		return
	var dir := OS.get_environment("HOME") + "/Videos/Tephra"
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	# Recorders to try in turn: each one's messages go to ~/.config/tephra/recording.log, and when one quits
	# straight away (no GPU access, no audio device, no permission) the next one is tried.
	var tries: Array = []
	if gpu:
		var mp4 := "%s/Tephra_%s.mp4" % [dir, stamp]
		tries.append({"path": mp4, "bin": "gpu-screen-recorder", "args": ["-w", "screen", "-f", "60", "-a", "default_output", "-o", mp4]})
		tries.append({"path": mp4, "bin": "gpu-screen-recorder", "args": ["-w", "screen", "-f", "60", "-o", mp4]})  # without sound
	if spec:
		var webm := "%s/Tephra_%s.webm" % [dir, stamp]
		tries.append({"path": webm, "bin": "spectacle", "args": ["--background", "--record=screen", "--output", webm]})
	var log_path := OS.get_environment("HOME") + "/.config/tephra/recording.log"
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	sfx.play("rec_start")
	toast.show_toast(Icons.texture("check", Icons.svg_check(), 40), "Starting recording...", false)
	_show_rec(true)
	for t in tries:
		var lf := FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
		if lf != null:
			lf.seek_end()
			lf.store_line("--- %s %s" % [t["bin"], " ".join(PackedStringArray(t["args"]))])
			lf.close()
		_rec_path = str(t["path"])
		_rec_pid = OS.create_process("sh", ["-c", "exec \"$@\" >>\"$0\" 2>&1", log_path, str(t["bin"])] + (t["args"] as Array))
		await get_tree().create_timer(2.5).timeout
		if _recording():
			toast.show_toast(Icons.texture("check", Icons.svg_check(), 40), "Recording. Hold the touchpad again to stop", false)
			return
		_rec_pid = -1
	_show_rec(false)
	var why := ""
	var lines := FileAccess.get_file_as_string(log_path).strip_edges().split("\n")
	for i in range(lines.size() - 1, -1, -1):
		if not str(lines[i]).begins_with("---") and str(lines[i]).strip_edges() != "":
			why = str(lines[i]).strip_edges()
			break
	toast.show_toast(Icons.texture("no", Icons.svg_no(), 40), "Couldn't start recording" + ((": " + why.left(90)) if why != "" else ""), false)
	print("Tephra: recording failed; see ", log_path)

## A small red "REC" in the top corner while recording.
func _show_rec(on: bool) -> void:
	if _rec_dot == null:
		_rec_dot = CanvasLayer.new()
		_rec_dot.layer = 98
		var l := Label.new()
		l.text = "● REC"
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
		l.position = Vector2(48, 20)
		_rec_dot.add_child(l)
		add_child(_rec_dot)
	_rec_dot.visible = on

func _guide_hold_check() -> void:
	if guide_down_ms >= 0 and not guide_long_fired and Time.get_ticks_msec() - guide_down_ms >= LONG_PRESS_MS:
		guide_long_fired = true
		_on_guide_long()

# ---------- Browser ----------
## The control center's Browser card: open a site, type an address or text, reload.
func _browser_action(action: String, arg: String) -> void:
	match action:
		"open":
			game_links.erase(arg)
			if browser.firefox() == "":
				notify("The browser needs Firefox. Install it with: sudo pacman -S firefox")
				return
			if _game_id == browser.ID and _game_started:
				# Already open: go back to it and load the page there.
				await _overlay_close()
				await get_tree().create_timer(0.4).timeout
				browser.type_text(arg, true)
				return
			if cc.is_open:
				cc.close(true)
			var g: Dictionary = browser.game_entry(arg)
			g["pattern"] = browser.PATTERN
			_launch(-1, g)
		"ask":
			if cc.is_open:
				cc.close(true)
			keyboard.open("Address or search", "", false, func(text: String) -> void:
				var t := text.strip_edges()
				if t != "":
					_browser_action("open", Browser.url_for(t)))
		"address":
			browser_keyboard(true)
		"type":
			browser_keyboard(false)
		"resume":
			_overlay_close()
		"tabs":
			if cc.is_open:
				cc.close(true)
			_tabs_seen = Browser.read_tabs()
			if _tabs_seen.is_empty():
				_tabs_seen = {"tabs": [], "current": 0}
			_overlay_mode = "tabs"
			browser_tabs.open(_tabs_seen["tabs"], int(_tabs_seen["current"]))
		"reload":
			await _overlay_close()
			await get_tree().create_timer(0.4).timeout
			browser.key("f5")
		"close":
			# Closes the browser and every tab: Home fades back in, the same way as quitting a game.
			if not _game_started or _quit_flow or _game_id != browser.ID:
				return
			_quit_flow = true
			if cc.is_open:
				cc.close(true)
			_close_fast("Closing browser...")

## Square / Triangle in the browser: Tephra's keyboard comes up over it, and what is typed goes into the page
## (Triangle: an address, or words to search for).
func browser_keyboard(address: bool) -> void:
	if not _in_overlay:
		await _overlay_open("kbd")  # the page is frozen and shown as it is (sharp), with the keyboard on top
	if cc.is_open:
		cc.close(true)
	keyboard.closed.connect(_keyboard_back_to_browser, CONNECT_ONE_SHOT)
	keyboard.open("Address or search" if address else "Type", "", false, func(text: String) -> void:
		var t := text.strip_edges()
		await _overlay_close()
		await get_tree().create_timer(0.4).timeout
		if t != "":
			browser.type_text(t, address))

# ---------- Volume in steps of 5 ----------
## Whatever changes the volume (headphone buttons, a volume dial, media keys, another app), it is put on the next step of
## 5 without a sound or a message: a rise goes up to the next 5, a fall down to the previous 5, so every press moves it,
## up to 100. It is event driven (pactl subscribe tells when the sound server changes something), so nothing runs
## while the volume is left alone.
var _vol_proc := {}
var _vol_thread: Thread
var _vol_last := -1
var _vol_check_queued := false

## A press or release of the capture button (from the pad, or from the touchpad watcher below).
func _capture_edge(pressed: bool) -> void:
	if not bool(Settings.get_value("screenshot_btn", true)):
		return
	if pressed and not input_locked:
		capture_down_ms = Time.get_ticks_msec()
		capture_long_fired = false
	elif not pressed and capture_down_ms >= 0:
		capture_down_ms = -1
		if not capture_long_fired and not input_locked:
			_take_screenshot()

# ---------- DualSense touchpad click ----------
## Linux gives the DualSense touchpad its own input device whose click is a mouse button, so the game controller
## input Godot sees never has it. This small python watcher reads that device (/dev/input/event*) and prints D when the
## click goes down and U when it comes up; Tephra turns those into the capture button. Needs read access to
## /dev/input (the "input" group); without it the watcher says so in ~/.config/tephra/touchpad.log and the touchpad
## stays unused. The KDE pointer from the touchpad is switched off separately (touchpad-off.sh).
const TP_PY := """
import os, select, struct, sys, time
FMT = "llHHi"; SZ = struct.calcsize(FMT)
KEYS = ("Wireless Controller", "DualSense", "DualShock", "Sony", "PS4", "PS5")
fds = {}; warned = False; last = 0
while True:
    if time.time() - last > 3:
        last = time.time()
        try:
            for n in os.listdir("/sys/class/input"):
                if not n.startswith("event"):
                    continue
                try:
                    name = open("/sys/class/input/%s/device/name" % n).read().strip()
                except OSError:
                    continue
                if "Touchpad" in name and any(k in name for k in KEYS) and ("/dev/input/" + n) not in fds.values():
                    try:
                        fds[os.open("/dev/input/" + n, os.O_RDONLY | os.O_NONBLOCK)] = "/dev/input/" + n
                    except OSError as e:
                        if not warned:
                            print("E cannot open /dev/input/%s: %s" % (n, e), flush=True); warned = True
        except OSError:
            pass
    if not fds:
        time.sleep(1); continue
    r, _, _ = select.select(list(fds), [], [], 1.0)
    for fd in r:
        try:
            data = os.read(fd, SZ * 32)
        except OSError:
            os.close(fd); del fds[fd]; continue
        for i in range(0, len(data) - SZ + 1, SZ):
            _, _, t, c, v = struct.unpack(FMT, data[i:i + SZ])
            if t == 1 and c == 0x110 and v in (0, 1):
                print("D" if v else "U", flush=True)
"""
var _tp_proc := {}
var _tp_thread: Thread

func _tp_start() -> void:
	if not _tp_proc.is_empty() or OS.execute("sh", ["-c", "command -v python3 >/dev/null"]) != 0:
		return
	_tp_proc = OS.execute_with_pipe("python3", ["-c", TP_PY], false)
	if _tp_proc.is_empty():
		return
	var pipe: FileAccess = _tp_proc["stdio"]
	_tp_thread = Thread.new()
	_tp_thread.start(func() -> void:
		while pipe.is_open():
			var line := pipe.get_line()
			if line == "" and pipe.get_error() != OK:
				break
			if line == "D":
				_capture_edge.call_deferred(true)
			elif line == "U":
				_capture_edge.call_deferred(false)
			elif line.begins_with("E"):
				_tp_log.call_deferred(line))

func _tp_log(line: String) -> void:
	var dir := OS.get_environment("HOME") + "/.config/tephra"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/touchpad.log", FileAccess.WRITE)
	if f != null:
		f.store_line(line + " (add yourself to the input group: sudo usermod -aG input $USER, then log out and in)")
		f.close()

func _tp_stop() -> void:
	if not _tp_proc.is_empty():
		OS.kill(int(_tp_proc["pid"]))
		_tp_proc = {}
	if _tp_thread != null:
		_tp_thread.wait_to_finish()
		_tp_thread = null

func _vol_snap_start() -> void:
	if not _vol_proc.is_empty() or OS.execute("sh", ["-c", "command -v pactl >/dev/null && command -v wpctl >/dev/null"]) != 0:
		return
	_vol_proc = OS.execute_with_pipe("pactl", ["subscribe"], false)
	if _vol_proc.is_empty():
		return
	var pipe: FileAccess = _vol_proc["stdio"]
	_vol_thread = Thread.new()
	_vol_thread.start(func() -> void:
		while pipe.is_open():
			var line := pipe.get_line()
			if line == "" and pipe.get_error() != OK:
				break
			if line.contains("'change' on sink ") or line.contains("'new' on sink "):
				_vol_event.call_deferred())
	_vol_event.call_deferred()

func _vol_snap_stop() -> void:
	if not _vol_proc.is_empty():
		OS.kill(int(_vol_proc["pid"]))
		_vol_proc = {}
	if _vol_thread != null:
		_vol_thread.wait_to_finish()
		_vol_thread = null

func _vol_event() -> void:
	if _vol_check_queued:
		return
	_vol_check_queued = true
	await get_tree().create_timer(0.25).timeout  # a dial sends many small changes: look once, when it settles
	_vol_check_queued = false
	var box := {}
	box["id"] = _work(func() -> void:
		var out := []
		var pct := -1
		if OS.execute("wpctl", ["get-volume", "@DEFAULT_AUDIO_SINK@"], out) == 0 and not out.is_empty():
			var m := RegEx.create_from_string("Volume:\\s*([0-9.]+)").search(str(out[0]))
			if m != null:
				pct = roundi(m.get_string(1).to_float() * 100.0)
		_vol_checked.call_deferred(box, pct))

func _vol_checked(box: Dictionary, pct: int) -> void:
	_work_done(int(box.get("id", -1)))
	if pct < 0:
		return
	if pct % 5 == 0:
		_vol_last = pct
		return
	var target := mini(((pct / 5) + (1 if _vol_last < 0 or pct > _vol_last else 0)) * 5, 100)
	_vol_last = target
	OS.create_process("wpctl", ["set-volume", "@DEFAULT_AUDIO_SINK@", "%.2f" % (target / 100.0)])

## The `tephra` terminal command (tephra clear, tephra update...): ~/.local/bin/tephra points at tephra-cli.sh,
## and that folder is added to the terminal's search path once if it isn't there yet.
func _install_cli() -> void:
	var home_dir := OS.get_environment("HOME")
	_fix_autostart(home_dir)
	var script := ProjectSettings.globalize_path("res://tephra-cli.sh")
	if not FileAccess.file_exists(script):
		return
	var bin := home_dir.path_join(".local/bin")
	DirAccess.make_dir_recursive_absolute(bin)
	OS.execute("chmod", ["+x", script])
	OS.execute("ln", ["-sfn", script, bin.path_join("tephra")])
	if ":%s:" % bin in ":%s:" % OS.get_environment("PATH"):
		return
	const LINE := 'export PATH="$HOME/.local/bin:$PATH"  # added by Tephra (the tephra command)'
	for rc in [".bashrc", ".zshrc"]:
		var p := home_dir.path_join(rc)
		if rc == ".zshrc" and not FileAccess.file_exists(p):
			continue
		var text := FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
		if ".local/bin" in text:
			continue
		var f := FileAccess.open(p, FileAccess.READ_WRITE if FileAccess.file_exists(p) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_string(("" if text.ends_with("\n") or text == "" else "\n") + LINE + "\n")
	var fish := home_dir.path_join(".config/fish")
	if DirAccess.dir_exists_absolute(fish):
		DirAccess.make_dir_recursive_absolute(fish.path_join("conf.d"))
		var ff := FileAccess.open(fish.path_join("conf.d/tephra.fish"), FileAccess.WRITE)
		if ff != null:
			ff.store_string("fish_add_path $HOME/.local/bin  # added by Tephra (the tephra command)\n")

## Autostart entries that start Godot on Tephra directly are pointed at tephra-run.sh, the launcher that
## brings Tephra back after updates and crashes.
func _fix_autostart(home_dir: String) -> void:
	var launcher := ProjectSettings.globalize_path("res://tephra-run.sh")
	if not FileAccess.file_exists(launcher):
		return
	OS.execute("chmod", ["+x", launcher])
	var dir := home_dir.path_join(".config/autostart")
	if not DirAccess.dir_exists_absolute(dir):
		return
	for n in DirAccess.get_files_at(dir):
		if not n.ends_with(".desktop"):
			continue
		var p := dir.path_join(n)
		var text := FileAccess.get_file_as_string(p)
		var lines := text.split("\n")
		var changed := false
		for i in lines.size():
			if lines[i].begins_with("Exec=") and "tephra-shell" in lines[i] and not "tephra-run.sh" in lines[i]:
				lines[i] = "Exec=" + launcher
				changed = true
		if changed:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_string("\n".join(lines))
				print("Tephra: autostart now uses the launcher (%s)" % n)

## The Browser menu's Tabs row: the tab list comes up over a picture of the page.
func browser_tabs_open() -> void:
	if _in_overlay or _overlay_busy:
		return
	_tabs_seen = Browser.read_tabs()
	if _tabs_seen.is_empty():
		_tabs_seen = {"tabs": [], "current": 0}
	var shown: Array = _tabs_seen.get("tabs", [])
	if shown.size() == 1 and str(shown[0].get("url", "")) in ["", "about:blank", "about:newtab", "about:home"]:
		_tabs_seen = {"tabs": [], "current": 0}  # only an empty page is left: nothing to list, "New tab" is selected
	await _overlay_open("tabs")

func _browser_tabs_done(action: String, index: int) -> void:
	if action == "_quiet":
		return  # closed by the menu going away (PS): nothing else to do
	if action == "new":
		keyboard.closed.connect(_keyboard_back_to_browser, CONNECT_ONE_SHOT)
		keyboard.open("New tab: address or search", "", false, func(text: String) -> void:
			var t := text.strip_edges()
			await _overlay_close()
			await get_tree().create_timer(0.4).timeout
			if t != "":
				browser.new_tab(Browser.url_for(t)))
		return
	if action == "":
		_overlay_close()
		return
	await _overlay_close()
	await get_tree().create_timer(0.4).timeout
	match action:
		"switch":
			browser.switch_tab(int(_tabs_seen.get("current", 0)), index)
		"close":
			browser.switch_tab(int(_tabs_seen.get("current", 0)), index)
			await get_tree().create_timer(0.2).timeout
			browser.close_tab()
			# The list comes back (Firefox writes its tab list about once a second). The browser is never closed with
			# the last tab: with no pages left, the selection sits on "New tab".
			await get_tree().create_timer(1.5).timeout
			if _game_id == browser.ID and _game_started and not _in_overlay and not _overlay_busy:
				await browser_tabs_open()

## The keyboard was closed without typing anything: straight back to the page.
func _keyboard_back_to_browser(accepted: bool) -> void:
	if not accepted and _in_overlay:
		_overlay_close()
