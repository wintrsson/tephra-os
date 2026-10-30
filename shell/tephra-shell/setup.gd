extends CanvasLayer
## First-boot setup: a short walk through the things a new PC needs (display and sound, Wi-Fi, Steam, game drives,
## controllers, weather, theme, a tour of the controls). It can't be skipped: every step has Continue, and nothing in a
## step is required. Opens by itself on a fresh install (never on a PC that already had Tephra), and from the Developer
## menu ("Redo first-boot setup") for testing: that only walks through the steps again (Back on the first step leaves)
## and keeps everything else.
##
## While it runs, Settings "setup_active" is true and "setup_page" is the step: choosing a theme restarts the scene,
## and home.gd opens this again at that step afterwards (see resume_if_active).

const TephraGlyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
const Settings = preload("res://settings.gd")
const Icons = preload("res://icons.gd")
const DisplayCtl = preload("res://display_ctl.gd")
const SteamAccount = preload("res://steam_account.gd")
const FilesBrowser = preload("res://files_browser.gd")
const InstallDialog = preload("res://install_dialog.gd")

const PAGES := ["welcome", "display", "network", "steam", "drives", "controllers", "weather", "theme", "controls", "done"]
const FPS_CAPS := [30, 60, 90, 120, 240, 0, -1]  # same as Settings > Display: 0 = no limit, -1 = variable
const FPS_NAMES := ["30", "60", "90", "120", "240", "No limit", "Variable"]
const REFRESH_EVERY := 1.5     # seconds between looks at things that change by themselves (Wi-Fi, pads, weather)
const HZ_CONFIRM := 10.0       # seconds to keep a new refresh rate before it goes back

var BG: Color = Themes.c("bg")
var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var SELECT: Color = Themes.c("select")
var CARD: Color = Themes.ink(0.07)
var CARD_ON: Color = Themes.ink(0.12)
var EDGE: Color = Themes.ink(0.18)   # the thin edge that makes every row read as a button, whatever the theme
var RADIUS := Themes.r(16)
var GOOD := Color("7BD88F")

static var fresh_install := false
static var _noted := false

var is_open := false
var _home  # home.gd
var _redo := false          # opened from the Developer menu: nothing is marked done at the end
var _page := 0
var _rows: Array = []       # what the step shows: {t: "info"|"choice"|"act"|"nav", text, ...}
var _sel := 0
var _nodes: Array = []      # the selectable rows' panels, same order as the selectable rows
var _sel_rows: Array = []
var _acc := 0.0
var _msg := ""              # the last thing that happened on this step ("Added ...")
var _armed := ""            # a row that needs a second press to confirm

# Display and sound
var _hz_prev := 0
var _hz_left := 0.0
var _vol := -1
var _sinks: Array = []
var _sink := ""

var _root: Control
var _step: Label
var _title: Label
var _blurb: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _hints: HBoxContainer
var _dots: HBoxContainer
var _clock: Label
var _margin: MarginContainer

# What a theme looks like while the cursor is on it (the theme step): the real look is put back when it leaves
var _look := ""                 # the theme whose look is on screen
var _bg_cache := {}             # theme -> its background (a Control), made once
var _bg_tween := {}             # background -> the fade it is in (one at a time: a second one would fight the first)
var _icon_caches := {}          # theme -> the pictures (button glyphs) made in that theme's colours
var _fps_label: Label           # "Running at N FPS right now" (display step)
var _fps_acc := 0.0

# A change you just made shows big on the right: what changed and its new value
var _banner: PanelContainer
var _banner_title: Label
var _banner_value: Label
var _banner_t := 0.0
var _flash_t := 0.0             # the row you changed lights up

# Wi-Fi step
var _wifi_has := true
var _wifi_known := false
var _wifi_on := false
var _wifi_name := ""
var _wifi_cable := ""
var _wifi_nets: Array = []
var _wifi_note := ""
var _wifi_busy := ""
var _wifi_scanning := false
var _wifi_scanned := false

# ---------- Whether this is a fresh install ----------
## Call first thing when Tephra starts, before anything has saved a setting. A PC that already has Tephra's saved
## files is not a first boot (an update must never put an existing owner through setup).
static func note_fresh_install() -> void:
	if _noted:
		return
	_noted = true
	fresh_install = not FileAccess.file_exists("user://settings.json") and not FileAccess.file_exists("user://profile.json") \
		and not FileAccess.file_exists("user://owned.json")

func setup(home) -> void:
	_home = home

## Reads the colours of the theme that is switched on right now (the real one, or a preview inside _show_look).
func _read_look() -> void:
	BG = Themes.c("bg")
	TEXT = Themes.c("text")
	MUTED = Themes.c("muted")
	SELECT = Themes.c("select")
	var card := Themes.c("card")  # each theme's own button/panel colour: solid enough to read in every theme
	CARD = Color(card, 0.9)
	CARD_ON = card.lerp(TEXT, 0.16)
	CARD_ON.a = 1.0
	EDGE = Themes.ink(0.2)
	RADIUS = Themes.r(16)

func _ready() -> void:
	_read_look()
	layer = 82  # above Library / Profile / Settings (80), below the menus it opens (85) and the keyboard (98)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)
	_look = Themes.id()
	var real_bg := _make_bg()
	_bg_cache[_look] = real_bg
	_root.add_child(real_bg)

	var margin := MarginContainer.new()
	_margin = margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	margin.add_child(v)

	_step = _label("", 24, MUTED)
	v.add_child(_step)
	_title = _label("", 60, TEXT)
	v.add_child(_title)
	_blurb = _label("", 26, MUTED)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size.x = 900
	v.add_child(_blurb)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.custom_minimum_size.x = 1000
	_scroll.add_child(_list)

	var foot := HBoxContainer.new()
	v.add_child(foot)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 10)
	_dots.alignment = BoxContainer.ALIGNMENT_BEGIN
	_dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_dots)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	foot.add_child(_hints)

	_banner = PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(GOOD, 0.16)
	bsb.border_color = GOOD
	bsb.set_border_width_all(3)
	bsb.set_corner_radius_all(Themes.r(24))
	bsb.set_content_margin_all(28)
	_banner.add_theme_stylebox_override("panel", bsb)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 4)
	_banner.add_child(bv)
	_banner_title = _label("", 26, MUTED)
	bv.add_child(_banner_title)
	_banner_value = _label("", 72, GOOD)
	bv.add_child(_banner_value)
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_banner.offset_left = -640
	_banner.offset_right = -90
	_banner.offset_top = -120
	_banner.offset_bottom = 60

	_clock = _label("", 32, TEXT)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_clock)
	_clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_clock.offset_left = -340
	_clock.offset_right = -80
	_clock.offset_top = 28
	refresh_hints()

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func refresh_hints() -> void:
	if _hints == null:
		return
	var items: Array = [["accept", "Select"], ["dpad", "Choose"]]
	if _page > 0:
		items.append(["back", "Previous step"])
	elif _redo:
		items.append(["back", "Leave setup"])
	# The hint colours follow the look on screen (a preview of a light theme over a dark one still reads).
	var keep_text := TephraGlyphs.TEXT
	var keep_muted := TephraGlyphs.MUTED
	var keep_id := Themes._id
	var keep_icons: Dictionary = Icons._cache
	TephraGlyphs.TEXT = TEXT
	TephraGlyphs.MUTED = MUTED
	if _look != "" and _look != Themes.id():
		# The button pictures are drawn in the theme's colours and kept: a preview gets its own set, so they are
		# neither invisible on its background nor left behind in the real theme afterwards.
		Themes._id = _look
		Icons._cache = _icon_caches.get(_look, {})
	TephraGlyphs.fill(_hints, items, 26)
	if _look != "" and Themes._id != keep_id:
		_icon_caches[_look] = Icons._cache
		Icons._cache = keep_icons
		Themes._id = keep_id
	TephraGlyphs.TEXT = keep_text
	TephraGlyphs.MUTED = keep_muted

# ---------- The look of a theme, to show while the cursor is on it ----------
## One theme's background: its colour with the animated backdrop on it. Made with the theme's own colours and style.
func _make_bg() -> Control:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.color = Themes.c("bg")
	holder.add_child(fill)
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var anim = (preload("res://xmb_bg.gd") if Themes.layout() == "xmb" else preload("res://tephra_bg.gd")).new()
	anim.set("plain", true)
	holder.add_child(anim)
	anim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return holder

## Fades a background in or out. Each one has at most one fade running, so quickly going back and forth
## between themes can't leave the one you are on hidden by an older fade-out that was still finishing.
func _fade_bg(h: Control, in_: bool) -> void:
	var old: Tween = _bg_tween.get(h)
	if old != null and old.is_valid():
		old.kill()
	var t := create_tween()
	t.tween_property(h, "modulate:a", 1.0 if in_ else 0.0, 0.25)
	if not in_:
		t.tween_callback(h.hide)
	_bg_tween[h] = t

## Puts the look of `theme` on this screen (background, colours, typeface) without choosing it. "" = the real theme.
## Everything that reads the theme is made while it is switched on for an instant, so nothing else ever sees it.
func _show_look(theme: String) -> void:
	var key := theme if theme != "" and Themes.DATA.has(theme) else Themes.id()
	if key == _look:
		return
	_look = key
	var saved := Themes._id
	Themes._id = key
	_read_look()
	var holder: Control = _bg_cache.get(key)
	if holder == null:
		holder = _make_bg()
		_bg_cache[key] = holder
	var font := Themes.font()
	Themes._id = saved
	var th := Theme.new()
	th.default_font = font if font != null else ThemeDB.fallback_font
	_root.theme = th
	# The new background fades in over the old one; the old ones are hidden (kept, so coming back is instant).
	for k in _bg_cache:
		var h: Control = _bg_cache[k]
		if h != holder and h.visible:
			_fade_bg(h, false)
	# The backgrounds sit first in _root (the page content comes after them). A background shown again later is
	# already there: it goes on top of the other backgrounds, never past the page content (that is what hid every
	# button when you went back to a theme you had already looked at).
	var holders := 0
	for k in _bg_cache:
		if (_bg_cache[k] as Control).get_parent() == _root:
			holders += 1
	if holder.get_parent() == null:
		_root.add_child(holder)
		_root.move_child(holder, holders)
	else:
		_root.move_child(holder, holders - 1)
	holder.visible = true
	holder.modulate.a = 0.0
	_fade_bg(holder, true)
	_step.add_theme_color_override("font_color", MUTED)
	_title.add_theme_color_override("font_color", TEXT)
	_blurb.add_theme_color_override("font_color", MUTED)
	_banner_title.add_theme_color_override("font_color", MUTED)
	_clock.add_theme_color_override("font_color", TEXT)
	_build()
	refresh_hints()

# ---------- Open / close ----------
## redo = from the Developer menu (for testing): finishing changes nothing but this walk-through.
func open(page := 0, redo := false) -> void:
	if is_open:
		return
	is_open = true
	_redo = redo
	_page = clampi(page, 0, PAGES.size() - 1)
	_sel = 0
	_msg = ""
	_armed = ""
	Settings.set_value("setup_active", true)
	_root.visible = true
	_banner_t = 0.0
	_go(_page)
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.3)

## Home calls this when it starts: setup was in the middle of something (a theme restart), or this is a first boot.
func start_if_needed() -> void:
	if bool(Settings.get_value("setup_active", false)):
		open(int(Settings.get_value("setup_page", 0)), bool(Settings.get_value("setup_redo", false)))
		return
	if bool(Settings.get_value("setup_done", false)):
		return
	if fresh_install:
		open(0, false)
	else:
		Settings.set_value("setup_done", true)  # a PC that had Tephra before: nothing to set up

func close() -> void:
	if not is_open:
		return
	is_open = false
	Settings.set_value("setup_active", false)
	Settings.set_value("setup_redo", false)
	_show_look("")  # the real theme's look comes back (it matters when this was left on a preview)
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.3)
	await t.finished
	if not is_open:
		_root.visible = false

func _finish() -> void:
	if not _redo:
		Settings.set_value("setup_done", true)
	_home._refresh_all_hints()
	close()

# ---------- Steps ----------
func _go(i: int) -> void:
	_show_look("")  # leaving the theme step: back to the real look
	_page = clampi(i, 0, PAGES.size() - 1)
	Settings.set_value("setup_page", _page)
	Settings.set_value("setup_redo", _redo)
	_sel = 0
	_msg = ""
	_armed = ""
	_enter(PAGES[_page])
	_build()
	refresh_hints()

func _next() -> void:
	if _page < PAGES.size() - 1:
		_go(_page + 1)

func _prev() -> void:
	if _page > 0:
		_go(_page - 1)
	elif _redo:
		close()  # leaving a test run from the Developer menu

## Things read once when a step opens.
func _enter(id: String) -> void:
	match id:
		"display":
			DisplayCtl.refresh()
			_read_audio()
			# No frame limit chosen yet: follow the screen (the highest of the usual limits it can show).
			if Settings.get_value("fps_cap", null) == null and DisplayCtl.available():
				_set_cap(_suggest_cap(roundi(float(DisplayCtl.current()["hz"]))))
		"network":
			_wifi_known = false
			_wifi_scanned = false
			_wifi_note = ""
			_wifi_busy = ""
			_wifi_read()
		"theme":
			var i := 0
			for g in Themes.GROUPS:
				for t in g[1]:
					if t == Themes.id():
						_sel = i  # the current theme is where the cursor starts (also after the restart a choice causes)
					i += 1

func _blurb_for(id: String) -> Array:
	match id:
		"welcome": return ["Welcome to Tephra", "A few quick steps get this PC ready. Everything here can be changed later in Settings."]
		"display": return ["Display and sound", "How the picture and sound run. The frame rate limit follows the refresh rate by default."]
		"network": return ["Wi-Fi", "Connect to the internet for game updates, covers, weather and Tephra updates. A cable works too."]
		"steam": return ["Steam", "Tephra shows and starts your Steam games, so Steam needs to be signed in on this PC."]
		"drives": return ["Game drives", "Where your games live. A drive that already holds Steam games can be added so they show up here."]
		"controllers": return ["Controllers", "Connect controllers, and choose the one in charge (the others can move around, only that one can select)."]
		"weather": return ["Weather", "Shown on the Today page. Tephra finds your city from your internet address, or you can type one."]
		"theme": return ["Theme", "Move over a theme to see its look. Pressing A on one restarts Tephra with it, and setup carries on."]
		"controls": return ["The controls", "The few things worth knowing before you start."]
		"done": return ["You're all set", "Everything here can be changed later in Settings. Enjoy."]
	return ["", ""]

func _build() -> void:
	var id: String = PAGES[_page]
	var tb := _blurb_for(id)
	_step.text = "Step %d of %d" % [_page + 1, PAGES.size()]
	_title.text = tb[0]
	_blurb.text = tb[1]
	_rows = _rows_for(id)
	_sel_rows = _rows.filter(func(r): return r["t"] != "info" and r["t"] != "tour")
	_sel = clampi(_sel, 0, maxi(_sel_rows.size() - 1, 0))
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_nodes.clear()
	_fps_label = null
	for r in _rows:
		_list.add_child(_make_row(r))
	for c in _dots.get_children():
		_dots.remove_child(c)
		c.queue_free()
	for i in PAGES.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(12, 12)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		d.color = TEXT if i == _page else Color(MUTED.r, MUTED.g, MUTED.b, 0.4)
		_dots.add_child(d)
	_style_rows()

func _make_row(r: Dictionary) -> Control:
	if r["t"] == "info":
		var l := _label(str(r["text"]), 24, MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 960
		if r.get("live") == "fps":
			_fps_label = l
		return l
	if r["t"] == "tour":
		return _tour_row(r)
	var p := PanelContainer.new()
	p.custom_minimum_size.y = 64
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	p.add_child(hb)
	if r.get("icon") != null:
		var tr := TextureRect.new()
		tr.texture = r["icon"]
		tr.custom_minimum_size = Vector2(84, 44)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(tr)
	var name_lbl := _label(str(r["text"]), 28, TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(name_lbl)
	var val := _label("", 26, MUTED)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(val)
	r["_panel"] = p
	r["_value"] = val
	_nodes.append(p)
	return p

## A line of the controls tour: the button, and what it does.
func _tour_row(r: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	hb.alignment = BoxContainer.ALIGNMENT_BEGIN
	var slot := HBoxContainer.new()
	slot.custom_minimum_size = Vector2(190, 48)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_theme_constant_override("separation", 8)
	hb.add_child(slot)
	var glyphs: Array = r["glyphs"]
	for g in glyphs:
		var node: Control
		if str(g).begins_with("text:"):
			node = _label(str(g).substr(5), 26, TEXT)
		else:
			node = TephraGlyphs.glyph(str(g), 44)
		node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.add_child(node)
	var l := _label(str(r["text"]), 26, TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 760
	hb.add_child(l)
	return hb

func _style_rows() -> void:
	var si := 0
	var flash := clampf(_flash_t / 0.9, 0.0, 1.0)
	for r in _rows:
		if r["t"] == "info" or r["t"] == "tour":
			continue
		var p: PanelContainer = r["_panel"]
		var on := si == _sel
		var lit := on and flash > 0.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = CARD_ON if on else CARD
		if lit:
			sb.bg_color = CARD_ON.lerp(Color(GOOD, 0.45), flash)
		sb.set_corner_radius_all(RADIUS)
		sb.content_margin_left = 24
		sb.content_margin_right = 24
		sb.border_color = EDGE
		sb.set_border_width_all(2)
		if on:
			sb.border_color = GOOD.lerp(SELECT, 1.0 - flash) if lit else SELECT
			sb.set_border_width_all(3 + (3 if lit else 0))
		p.add_theme_stylebox_override("panel", sb)
		var val: Label = r["_value"]
		val.text = _value_of(r)
		val.add_theme_color_override("font_color", GOOD if lit else (TEXT if on else MUTED))
		val.add_theme_font_size_override("font_size", 34 if lit else 26)
		si += 1
	if not _nodes.is_empty() and _sel < _nodes.size():
		_scroll.ensure_control_visible.call_deferred(_nodes[_sel])

## A change you just made: it shows large on the right (what, and its new value) and the row lights up.
func _notify_change(title: String, value: String) -> void:
	_banner_title.text = title.to_upper()
	_banner_value.text = value
	_banner_t = 3.2
	_flash_t = 0.9
	_banner.modulate.a = 1.0
	_style_rows()

func _value_of(r: Dictionary) -> String:
	var getter: Callable = r.get("get", Callable())
	var s := str(getter.call()) if getter.is_valid() else ""
	if r["t"] == "choice" and s != "":
		return "‹  %s  ›" % s
	return s

# ---------- Input ----------
func move(dir: Vector2i) -> void:
	if _sel_rows.is_empty():
		return
	if dir.y != 0:
		_sel = posmod(_sel + dir.y, _sel_rows.size())
		_armed = ""
		_style_rows()
		if PAGES[_page] == "theme":
			_show_look(str(_sel_rows[_sel].get("theme", "")))  # the cursor on a theme shows what it looks like
	elif dir.x != 0:
		var r: Dictionary = _sel_rows[_sel]
		if r["t"] == "choice":
			(r["step"] as Callable).call(dir.x)
			_style_rows()

func _is_shoulder(event: InputEvent, left: bool) -> bool:
	if event is InputEventJoypadButton and event.pressed:
		return event.button_index == (JOY_BUTTON_LEFT_SHOULDER if left else JOY_BUTTON_RIGHT_SHOULDER)
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed:
		return event.keycode == (KEY_Q if left else KEY_E)
	return false

## Returns true when setup used the event (while it is open it uses all of them, except what the menus and the
## keyboard on top of it take first).
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if _home.top_menu.is_open or _home.keyboard.is_open:
		return false
	if event.is_action_pressed("ui_cancel"):
		_prev()
	elif event.is_action_pressed("ui_accept"):
		_activate()
	elif _is_shoulder(event, true):
		_prev()
	return true

func _activate() -> void:
	if _sel_rows.is_empty():
		return
	var r: Dictionary = _sel_rows[_sel]
	if r["t"] == "choice":
		(r["step"] as Callable).call(1)
	else:
		(r["do"] as Callable).call()
	_style_rows()

func _process(delta: float) -> void:
	if not is_open:
		return
	_clock.text = _home.clock_label.text
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0) if _banner_t < 0.6 else 1.0
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		_style_rows()
	if _fps_label != null:
		_fps_acc += delta
		if _fps_acc >= 0.4:
			_fps_acc = 0.0
			_fps_label.text = "Tephra is running at %d FPS right now" % roundi(Engine.get_frames_per_second())
	if _hz_left > 0.0:
		_hz_left -= delta
		if _hz_left <= 0.0:
			_hz_revert()
		else:
			_style_rows()
	_acc += delta
	if _acc < REFRESH_EVERY or _home.keyboard.is_open or _home.top_menu.is_open:
		return
	_acc = 0.0
	var id: String = PAGES[_page]
	if id in ["steam", "controllers", "weather", "drives"] or (id == "display" and _hz_left > 0.0):
		_build()  # these change by themselves (a pad connects, the weather arrives, the countdown)

# ---------- Rows for each step ----------
func _nav(text: String, to_next := true) -> Dictionary:
	return {"t": "nav", "text": text, "do": _next if to_next else _finish}

func _info(text: String) -> Dictionary:
	return {"t": "info", "text": text}

func _act(text: String, fn: Callable, value := Callable(), icon: Texture2D = null) -> Dictionary:
	return {"t": "act", "text": text, "do": fn, "get": value, "icon": icon}

func _rows_for(id: String) -> Array:
	match id:
		"welcome":
			return [_nav("Start")]
		"display":
			return _rows_display()
		"network":
			return _rows_network()
		"steam":
			return _rows_steam()
		"drives":
			return _rows_drives()
		"controllers":
			return _rows_controllers()
		"weather":
			return _rows_weather()
		"theme":
			return _rows_theme()
		"controls":
			return _rows_controls()
		"done":
			return [_nav("Finish", false)]
	return []

# ----- Display and sound -----
func _suggest_cap(hz: int) -> int:
	var best := 30
	for c in [30, 60, 90, 120, 240]:
		if c <= hz:
			best = c
	return best

func _set_cap(cap: int) -> void:
	Settings.set_value("fps_cap", cap)
	_home.settings_screen.apply_display()

func _cap_text() -> String:
	var cap = Settings.get_value("fps_cap", 0)
	var i := FPS_CAPS.find(int(cap))
	return FPS_NAMES[i] if i >= 0 else str(cap)

func _read_audio() -> void:
	_vol = -1
	var out := []
	if OS.execute("wpctl", ["get-volume", "@DEFAULT_AUDIO_SINK@"], out) == 0 and not out.is_empty():
		var line := str(out[0])
		if line.begins_with("Volume:"):
			_vol = roundi(line.split(" ", false)[1].to_float() * 100.0)
	_sinks.clear()
	var o2 := []
	if OS.execute("pactl", ["-f", "json", "list", "sinks"], o2) == 0 and not o2.is_empty():
		var sinks = JSON.parse_string(str(o2[0]))
		if sinks is Array:
			for k in sinks:
				if k is Dictionary:
					_sinks.append({"name": str(k.get("name", "")), "desc": str(k.get("description", k.get("name", "")))})
	var o3 := []
	_sink = str(o3[0]).strip_edges() if OS.execute("pactl", ["get-default-sink"], o3) == 0 and not o3.is_empty() else ""

func _rows_display() -> Array:
	var rows: Array = []
	if DisplayCtl.available():
		var cur := DisplayCtl.current()
		rows.append(_info("%s: %s at %d Hz" % [DisplayCtl.output_name(), DisplayCtl.label(int(cur["w"]), int(cur["h"])), roundi(float(cur["hz"]))]))
		var rates := DisplayCtl.rates(int(cur["w"]), int(cur["h"]))
		if _hz_left > 0.0:
			rows.append(_info("Keep this refresh rate? It goes back by itself in %d seconds." % ceili(_hz_left)))
			rows.append({"t": "nav", "text": "Keep it", "do": _hz_keep})
			rows.append(_act("Go back", _hz_revert))
			return rows
		if rates.size() > 1:
			rows.append({"t": "choice", "text": "Refresh rate", "get": _hz_text, "step": _step_hz.bind(int(cur["w"]), int(cur["h"]), rates)})
	else:
		rows.append(_info("Screen settings aren't available on this PC (they need kscreen-doctor), so they stay as they are."))
	rows.append({"t": "choice", "text": "Frame rate limit", "get": _cap_text, "step": _step_cap})
	rows.append({"t": "info", "text": "Tephra is running at %d FPS right now" % roundi(Engine.get_frames_per_second()), "live": "fps"})
	if _vol >= 0:
		rows.append({"t": "choice", "text": "Volume", "get": _vol_text, "step": _step_vol})
	if _sinks.size() > 1:
		rows.append({"t": "choice", "text": "Sound output", "get": _sink_text, "step": _step_sink})
	rows.append(_nav("Continue"))
	return rows

func _hz_text() -> String:
	return "%d Hz" % roundi(float(DisplayCtl.current()["hz"]))

func _step_hz(d: int, w: int, h: int, rates: Array) -> void:
	var i := rates.find(roundi(float(DisplayCtl.current()["hz"])))
	# the rates are listed highest first: right = higher
	var j := clampi((i if i >= 0 else 0) - d, 0, rates.size() - 1)
	if j != i:
		_hz_try(w, h, int(rates[j]))

func _hz_keep() -> void:
	_hz_left = 0.0
	var hz := roundi(float(DisplayCtl.current()["hz"]))
	_set_cap(_suggest_cap(hz))
	_build()
	_notify_change("Refresh rate kept", "%d Hz" % hz)

func _step_cap(d: int) -> void:
	var i := FPS_CAPS.find(int(Settings.get_value("fps_cap", 0)))
	var j := posmod((i if i >= 0 else 0) + d, FPS_CAPS.size())
	_set_cap(FPS_CAPS[j])
	_notify_change("Frame rate limit", FPS_NAMES[j] + (" FPS" if FPS_CAPS[j] > 0 else ""))

func _vol_text() -> String:
	return "%d%%" % _vol

func _step_vol(d: int) -> void:
	_vol = clampi(roundi(_vol / 5.0) * 5 + d * 5, 0, 100)
	OS.create_process("wpctl", ["set-mute", "@DEFAULT_AUDIO_SINK@", "0"])
	OS.create_process("wpctl", ["set-volume", "@DEFAULT_AUDIO_SINK@", "%.2f" % (_vol / 100.0)])
	_notify_change("Volume", "%d%%" % _vol)

func _sink_text() -> String:
	for s in _sinks:
		if s["name"] == _sink:
			return str(s["desc"])
	return "Default"

func _step_sink(d: int) -> void:
	var i := 0
	for k in _sinks.size():
		if _sinks[k]["name"] == _sink:
			i = k
	_sink = str(_sinks[posmod(i + d, _sinks.size())]["name"])
	OS.create_process("pactl", ["set-default-sink", _sink])

func _hz_try(w: int, h: int, hz: int) -> void:
	_hz_prev = roundi(float(DisplayCtl.current()["hz"]))
	if DisplayCtl.set_mode_safely(w, h, hz):
		_hz_left = HZ_CONFIRM
		_build()
		_notify_change("Refresh rate", "%d Hz" % hz)
	else:
		_msg = "The screen wouldn't switch to %d Hz." % hz
		_build()

func _hz_revert() -> void:
	_hz_left = 0.0
	var cur := DisplayCtl.current()
	if _hz_prev > 0:
		DisplayCtl.set_mode_safely(int(cur["w"]), int(cur["h"]), _hz_prev)
	_build()
	_notify_change("Refresh rate", "back to %d Hz" % _hz_prev)

# ----- Wi-Fi: the step itself is the list of networks (no popup). The same nmcli calls as the Wi-Fi menu in top_menu.gd -----
func _rows_network() -> Array:
	var rows: Array = []
	if not _wifi_has:
		rows.append(_info("Network settings aren't available on this PC (they need NetworkManager), so they stay as they are."))
		rows.append(_nav("Continue"))
		return rows
	var status := "Checking..."
	if _wifi_busy != "":
		status = _wifi_busy
	elif _wifi_known:
		if _wifi_name != "":
			status = "Connected to Wi-Fi: " + _wifi_name
		elif _wifi_cable != "":
			status = "Connected by cable."
		else:
			status = "Not connected yet." if _wifi_on else "Wi-Fi is off."
	rows.append(_info(status))
	if _wifi_note != "":
		rows.append(_info(_wifi_note))
	if _wifi_known:
		rows.append(_act("Wi-Fi", _wifi_toggle, _wifi_onoff_text))
	if _wifi_on:
		rows.append(_act("Look for networks", _wifi_scan, _wifi_scan_text))
		if _wifi_nets.is_empty():
			rows.append(_info("None found yet." if _wifi_scanned else "Looking..."))
		for n in _wifi_nets:
			rows.append(_act(str(n["ssid"]), _wifi_pick.bind(n), _wifi_net_text.bind(n)))
		rows.append(_act("Other network...", _wifi_hidden, _wifi_hidden_text))
	rows.append(_nav("Continue"))
	return rows

func _wifi_onoff_text() -> String:
	return "On" if _wifi_on else "Off"

func _wifi_scan_text() -> String:
	return "Scanning..." if _wifi_scanning else ""

func _wifi_hidden_text() -> String:
	return "Hidden or not listed"

func _wifi_net_text(n: Dictionary) -> String:
	return _home.top_menu._net_value(n)

## Runs `work` on a worker thread, then hands what it returned to `done` on the main thread (if setup is still open).
func _wifi_run(work: Callable, done: Callable) -> void:
	var box := {}
	box["id"] = _home._work(func() -> void:
		var res = work.call()
		(func() -> void:
			_home._work_done(box["id"])
			if is_open:
				done.call(res)).call_deferred())

func _wifi_job_read() -> Dictionary:
	var o := {"has": true, "on": false, "cable": "", "nets": [], "name": ""}
	var out := []
	if OS.execute("nmcli", ["-t", "-f", "TYPE,STATE,CONNECTION", "device"], out) != 0:
		o["has"] = false
		return o
	for line in (str(out[0]).split("\n", false) if not out.is_empty() else PackedStringArray()):
		var p := line.split(":")
		if p.size() >= 3 and p[1] == "connected" and p[0] == "ethernet":
			o["cable"] = p[2]
	var radio := []
	OS.execute("nmcli", ["-t", "-f", "WIFI", "radio"], radio)
	o["on"] = radio.size() > 0 and str(radio[0]).strip_edges() == "enabled"
	if o["on"]:
		o["nets"] = _home.top_menu._list_networks()  # the list NetworkManager already has
		for n in o["nets"]:
			if n["active"]:
				o["name"] = n["ssid"]
	return o

func _wifi_read() -> void:
	_wifi_run(_wifi_job_read, _wifi_read_done)

func _wifi_read_done(o: Dictionary) -> void:
	_wifi_has = bool(o["has"])
	_wifi_known = true
	_wifi_on = bool(o["on"])
	_wifi_cable = str(o["cable"])
	_wifi_name = str(o["name"])
	_wifi_nets = o["nets"] if _wifi_on else []
	if PAGES[_page] == "network":
		_build()
		if _wifi_on and not _wifi_scanned:
			_wifi_scan()  # the cached list is up; now ask for a fresh one

func _wifi_job_scan() -> Dictionary:
	OS.execute("nmcli", ["dev", "wifi", "rescan"], [], true)
	OS.delay_msec(3500)
	var nets: Array = _home.top_menu._list_networks()
	var name := ""
	for n in nets:
		if n["active"]:
			name = n["ssid"]
	return {"nets": nets, "name": name}

func _wifi_scan() -> void:
	if _wifi_scanning or not _wifi_on:
		return
	_wifi_scanning = true
	_wifi_scanned = true
	_build()
	_wifi_run(_wifi_job_scan, _wifi_scan_done)

func _wifi_scan_done(o: Dictionary) -> void:
	_wifi_scanning = false
	_wifi_nets = o["nets"]
	_wifi_name = str(o["name"])
	if PAGES[_page] == "network":
		_build()

func _wifi_toggle() -> void:
	_wifi_on = not _wifi_on
	OS.create_process("nmcli", ["radio", "wifi", "on" if _wifi_on else "off"])
	_wifi_nets = []
	_wifi_name = ""
	_wifi_note = ""
	_wifi_scanned = false
	_build()
	await get_tree().create_timer(2.0).timeout  # the card needs a moment to come up
	if is_open and PAGES[_page] == "network":
		_wifi_read()

func _wifi_pick(n: Dictionary) -> void:
	if _wifi_busy != "":
		return
	var ssid: String = n["ssid"]
	_wifi_note = ""
	if n["active"]:
		_wifi_busy = "Disconnecting from %s..." % ssid
		_build()
		_wifi_run(_wifi_job_down.bind(str(n["profile"])), _wifi_after)
	elif n["saved"]:
		_wifi_join(ssid, "", false, true, str(n["profile"]))
	elif not n["secure"]:
		_wifi_join(ssid, "", false, false)
	elif str(n["security"]).contains("802.1X"):
		_wifi_note = "%s needs a work or school login, which Tephra can't enter yet." % ssid
		_build()
	else:
		_wifi_ask_password(ssid, "", "", str(n["security"]).contains("WEP"))

func _wifi_job_down(profile: String) -> int:
	return OS.execute("nmcli", ["connection", "down", "id", profile], [], true)

func _wifi_after(_res = null) -> void:
	_wifi_busy = ""
	_wifi_read()

func _wifi_ask_password(ssid: String, typed: String, problem: String, wep := false) -> void:
	_home.keyboard.open("Password for %s" % ssid, typed, true, _wifi_password.bind(ssid),
		{"min_len": 5 if wep else 8, "hint": problem if problem != "" else "Type the Wi-Fi password (or use the Phone key)"})

func _wifi_password(pw: String, ssid: String) -> void:
	_wifi_join(ssid, pw, false, false)

func _wifi_hidden() -> void:
	if _wifi_busy != "":
		return
	_home.keyboard.open("Network name", "", false, _wifi_hidden_name, {"min_len": 1, "hint": "The exact name of the network, capital letters count"})

func _wifi_hidden_name(net_name: String) -> void:
	_home.keyboard.open("Password for %s" % net_name, "", true, _wifi_hidden_password.bind(net_name), {"min_len": 0, "hint": "Leave empty for an open network"})

func _wifi_hidden_password(pw: String, net_name: String) -> void:
	_wifi_join(net_name, pw, true, false)

func _wifi_join(ssid: String, password: String, hidden: bool, saved: bool, profile := "") -> void:
	_wifi_busy = "Connecting to %s..." % ssid
	_wifi_note = ""
	_build()
	_wifi_run(_wifi_job_join.bind(ssid, password, hidden, saved, profile), _wifi_join_done.bind(ssid, password, hidden, saved))

func _wifi_job_join(ssid: String, password: String, hidden: bool, saved: bool, profile: String) -> Dictionary:
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
	return {"rc": rc, "text": text}

func _wifi_join_done(res: Dictionary, ssid: String, password: String, hidden: bool, saved: bool) -> void:
	_wifi_busy = ""
	if int(res["rc"]) == 0:
		_wifi_note = "Connected to %s" % ssid
		_notify_change("Wi-Fi", "Connected")
	else:
		var low := str(res["text"]).to_lower()
		var wrong := low.contains("secrets were required") or low.contains("password") or low.contains("(7)") or low.contains("timeout") or low.contains("(4)") or low.contains("(3)")
		if saved:
			_wifi_note = "Couldn't join %s. If its password changed, forget it in Settings and join again." % ssid
		elif wrong and password != "":
			_wifi_note = "Wrong password for %s" % ssid
			_wifi_ask_password(ssid, password, "That password didn't work. Check it and try again")
		else:
			var first := str(res["text"]).get_slice("\n", 0)
			_wifi_note = "Couldn't join %s%s" % [ssid, (": " + first) if first != "" else ""]
	_wifi_read()

func _open_menu(kind: String) -> void:
	_home.top_menu.open_menu(kind, Rect2(Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 60.0, 140.0), Vector2(120, 44)))

# ----- Steam -----
func _rows_steam() -> Array:
	var sid := SteamAccount.steam_id(_home.steam_dir)
	var rows: Array = []
	if _home.steam_signing_in():
		rows.append(_info("Steam's sign-in window is open. Tephra comes back by itself when you're done (or after 5 minutes)."))
		return rows
	if sid == "":
		rows.append(_info("Steam isn't signed in on this PC yet. Tephra opens Steam's own sign-in window and waits; use the controller or keyboard in that window, then Tephra returns."))
		rows.append(_act("Sign in to Steam", _home.steam_sign_in))
	else:
		var nm := SteamAccount.persona_name(_home.steam_dir, sid)
		rows.append(_info("Signed in as %s." % (nm if nm != "" else "your Steam account")))
		rows.append(_info("%d games found on this PC." % _home.games.size()))
	rows.append(_act("Check again", _steam_recheck))
	rows.append(_nav("Continue"))
	return rows

func _steam_recheck() -> void:
	_home.refresh_games(false)
	_build()

# ----- Game drives -----
func _library_paths() -> Array:
	var libs: Array = [_home.steam_dir]
	var re := RegEx.create_from_string("\"path\"\\s+\"([^\"]+)\"")
	for m in re.search_all(FileAccess.get_file_as_string(_home.steam_dir + "/steamapps/libraryfolders.vdf")):
		var p := m.get_string(1)
		if not libs.has(p):
			libs.append(p)
	return libs

## A folder on a drive that looks like a Steam library (has steamapps in it), or "".
func _library_on(drive: String) -> String:
	for c in [drive.path_join("SteamLibrary"), drive, drive.path_join("Steam"), drive.path_join("steam")]:
		if DirAccess.dir_exists_absolute(c.path_join("steamapps")):
			return c
	return ""

func _free_text(path: String) -> String:
	var out := []
	if OS.execute("df", ["-B1", "--output=avail", path], out) != 0 or out.is_empty():
		return ""
	var lines: PackedStringArray = str(out[0]).strip_edges().split("\n")
	var b := float(lines[lines.size() - 1].strip_edges().to_int()) if lines.size() > 1 else 0.0
	return InstallDialog.fmt_bytes(b) + " free" if b > 0.0 else ""

func _rows_drives() -> Array:
	var rows: Array = []
	var libs := _library_paths()
	for l in libs:
		rows.append(_info("Games are read from %s   %s" % [str(l).replace(OS.get_environment("HOME"), "~"), _free_text(str(l))]))
	var found := 0
	for d in FilesBrowser.drives():
		if str(d["kind"]) != "drive":
			continue
		var root := _library_on(str(d["path"]))
		if root == "":
			continue
		var known := false
		for l in libs:
			if str(l) == root:
				known = true
		if known:
			continue
		found += 1
		var drive_path := str(d["path"])
		var label := "Use the games on %s" % str(d["name"]) if _armed != drive_path else "Press again to add %s" % str(d["name"])
		rows.append(_act(label, _drive_press.bind(drive_path, root), _free_text.bind(drive_path)))
	if found == 0:
		rows.append(_info("No other drives with Steam games were found. Plug one in and come back to this step, or add it later from Steam."))
	if _msg != "":
		rows.append(_info(_msg))
	rows.append(_nav("Continue"))
	return rows

func _drive_press(drive_path: String, root: String) -> void:
	if _armed != drive_path:
		_armed = drive_path
		_msg = "Steam will be closed for a moment while its list of game folders is updated."
		_build()
	else:
		_add_library(drive_path, root)

## Adds a Steam library to Steam's list of game folders (libraryfolders.vdf). Steam rewrites that file while it
## runs, so it is closed first; the original is kept next to it.
func _add_library(drive: String, root: String) -> void:
	_armed = ""
	var vdf_path: String = _home.steam_dir + "/steamapps/libraryfolders.vdf"
	var txt := FileAccess.get_file_as_string(vdf_path)
	if txt == "":
		_msg = "Steam's list of game folders wasn't found. Start Steam once and try again."
		_build()
		return
	if _home._steam_running():
		_msg = "Closing Steam..."
		_build()
		OS.create_process("steam", ["-shutdown"])
		var waited := 0.0
		while _home._steam_running() and waited < 30.0:
			await get_tree().create_timer(1.0).timeout
			waited += 1.0
		if _home._steam_running():
			_msg = "Steam wouldn't close. Close it, then try again."
			_build()
			return
		txt = FileAccess.get_file_as_string(vdf_path)  # Steam wrote it while closing
	if txt.contains("\"" + root + "\""):
		_msg = "That folder is already in Steam's list."
		_build()
		return
	var idx := -1
	for m in RegEx.create_from_string("(?m)^\\t\"(\\d+)\"\\s*$").search_all(txt):
		idx = maxi(idx, m.get_string(1).to_int())
	var end := txt.rfind("}")
	if end < 0:
		_msg = "Steam's list of game folders looks unusual, so it was left alone."
		_build()
		return
	var backup := FileAccess.open(vdf_path + ".tephra-backup", FileAccess.WRITE)
	if backup != null:
		backup.store_string(txt)
		backup.close()
	var block := "\t\"%d\"\n\t{\n\t\t\"path\"\t\t\"%s\"\n\t\t\"label\"\t\t\"\"\n\t\t\"contentid\"\t\t\"0\"\n\t\t\"totalsize\"\t\t\"0\"\n\t\t\"update_clean_bytes_tally\"\t\t\"0\"\n\t\t\"time_last_update_corruption\"\t\t\"0\"\n\t\t\"apps\"\n\t\t{\n\t\t}\n\t}\n" % [idx + 1, root]
	var f := FileAccess.open(vdf_path, FileAccess.WRITE)
	if f == null:
		_msg = "Couldn't write Steam's list of game folders."
		_build()
		return
	f.store_string(txt.substr(0, end) + block + txt.substr(end))
	f.close()
	_home.refresh_games(false)
	_msg = "Added. Its games will show up here once Steam has looked at them."
	_build()

# ----- Controllers -----
func _rows_controllers() -> Array:
	var rows: Array = []
	var list: Array = _home.controllers.list() if _home.controllers != null else []
	if list.is_empty():
		rows.append(_info("No controller connected. Plug one in, or pair one over Bluetooth below."))
	var charge: int = TephraGlyphs.in_charge_slot()
	for c in list:
		var slot := int(c["slot"])
		rows.append(_act("P%d   %s" % [slot, str(c.get("name", "Controller"))], _pad_pick.bind(slot), _pad_state.bind(slot == charge)))
	rows.append(_act("Bluetooth devices...", _open_menu.bind("bt")))
	rows.append(_nav("Continue"))
	return rows

func _pad_pick(slot: int) -> void:
	Settings.set_value("pad_priority", str(slot))
	TephraGlyphs.detect()
	_home._refresh_all_hints()
	_build()

func _pad_state(in_charge: bool) -> String:
	return "In charge" if in_charge else "Make in charge"

# ----- Weather -----
func _city_file() -> String:
	return "user://weather_city.txt"

func _rows_weather() -> Array:
	var rows: Array = []
	var d: Dictionary = _home.weather.data if _home.weather != null else {}
	if d.has("city"):
		rows.append(_info("Right now: %s, %d°" % [str(d["city"]), int(d.get("temp", 0))]))
	else:
		rows.append(_info("Looking up the weather... (it needs the internet)"))
	var typed := FileAccess.get_file_as_string(_city_file()).strip_edges() if FileAccess.file_exists(_city_file()) else ""
	rows.append(_act("City", _ask_city.bind(typed), _city_text.bind(typed)))
	rows.append({"t": "choice", "text": "Temperature", "get": _unit_text, "step": _step_unit})
	rows.append(_nav("Continue"))
	return rows

func _city_text(typed: String) -> String:
	return typed if typed != "" else "Automatic"

func _ask_city(typed: String) -> void:
	_home.keyboard.open("City (leave empty to find it automatically)", typed, false, _city_typed)

func _city_typed(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_city_file()))
	else:
		var f := FileAccess.open(_city_file(), FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	_home.weather.fetch(true)
	_build()

func _unit_text() -> String:
	return "Celsius" if bool(Settings.get_value("temp_c", false)) else "Fahrenheit"

func _step_unit(_d: int) -> void:
	Settings.set_value("temp_c", not bool(Settings.get_value("temp_c", false)))
	_home.weather.fetch(true)

# ----- Theme -----
func _rows_theme() -> Array:
	var rows: Array = []
	for g in Themes.GROUPS:
		for t in g[1]:
			var td: Dictionary = Themes.DATA[t]
			var theme: String = t
			var row := _act("%s   ·   %s" % [td["name"], td["blurb"]], _theme_pick.bind(theme), _theme_state.bind(theme), Themes.swatch(theme))
			row["theme"] = theme  # the cursor on this row shows the theme's look (see move)
			rows.append(row)
	rows.append(_nav("Keep the current theme"))
	return rows

func _theme_state(theme: String) -> String:
	return "Current" if theme == Themes.id() else ""

func _theme_pick(theme: String) -> void:
	if theme == Themes.id():
		_next()
	else:
		_home.apply_theme(theme)  # restarts the scene; start_if_needed brings setup back to this step

# ----- Controls -----
func _rows_controls() -> Array:
	var rows: Array = []
	rows.append({"t": "tour", "glyphs": ["dpad"], "text": "Move around with the D-pad or the left stick."})
	rows.append({"t": "tour", "glyphs": ["accept", "back"], "text": "%s selects, %s goes back." % [TephraGlyphs.btn("accept"), TephraGlyphs.btn("back")]})
	rows.append({"t": "tour", "glyphs": ["north"], "text": "%s on a game: its options (pin, rename, mods, uninstall)." % TephraGlyphs.btn("north")})
	rows.append({"t": "tour", "glyphs": ["guide"], "text": "Tap the guide button (PS / Xbox / Home): the control center with sound, downloads, notifications and more. Hold it to go back to Home, also from inside a game."})
	rows.append({"t": "tour", "glyphs": ["text:Touchpad"], "text": "Click the touchpad for a screenshot, hold it still to start or stop a recording (PlayStation controllers)."})
	rows.append({"t": "tour", "glyphs": ["l1", "r1"], "text": "The shoulder buttons flip between pages and tabs."})
	rows.append(_nav("Continue"))
	return rows
