extends CanvasLayer
## The game page of the Library: opens when you choose a game there (installed or not).
## Top: Play (or Install), Pin to Home, Rename. Below, scrolling with Up/Down: a Steam-style disk bar where the
## game's own part flashes slowly in its colour (with its size marked above it), then two columns: the store
## description on the left, your stats (time played, achievements, controller, Steam Deck) on the right.
## Nothing here is a popup.

const TephraGlyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const Rounded = preload("res://rounded.gd")
const PageSkin = preload("res://page_skin.gd")
const InstallDialog = preload("res://install_dialog.gd")
const Achievements = preload("res://achievements.gd")
const SteamAccount = preload("res://steam_account.gd")
const InfoPanel = preload("res://info_panel.gd")
const Settings = preload("res://settings.gd")

signal action(key: String, game: Dictionary)   # "play", "install", "pin", "rename", "menu" (Triangle: Options)

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
const BAD := Color("E8645A")
const OTHER := Color(0.42, 0.50, 0.58)
const STORE_URL := "https://store.steampowered.com/api/appdetails?appids=%s&filters=basic,genres,pc_requirements,release_date&l=english"
const CACHE_DAYS := 14
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const CONTENT_W := 1180
const STATS_W := 470       # the right-hand column with your stats
const BAR_TOP := 34.0      # room above the disk bar for the game's size marker
const BAR_H := 44.0

var is_open := false

var _lib   # library.gd
var _game := {}
var _id := ""
var _cover: Texture2D
var _color := Color(0.3, 0.6, 0.9)
var _sky: Gradient            # the backdrop's colours (the light themes take them from the game)
var _root: Control
var _glow: ColorRect
var _art: TextureRect
var _title: Label
var _sub: Label
var _buttons_row: HBoxContainer
var _status: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _bar: Control
var _bar_line: Label
var _bar_legend: Label
var _desc: Label
var _facts: Label
var _grid: GridContainer
var _hints: HBoxContainer
var _req: HTTPRequest
var _deck_req: HTTPRequest
var _keys: Array = []      # button keys, in order
var _sel := 0
var _scroll_tween: Tween
var _total := 0.0          # drive size in bytes
var _free := 0.0           # free bytes
var _need := 0.0           # bytes the game will take (0 = unknown)
var _dl_total := 0.0       # bytes Steam says it is downloading (0 = not yet known)
var _dl_pct := -1.0
var _info := {}            # store facts: desc, genres, dev, date, controller, deck
var _t := 0.0

func setup(lib) -> void:
	_lib = lib

func _ready() -> void:
	layer = 82  # above the Library (80), below the launch screen (90)
	set_process(false)
	_root = Control.new()
	_root.visible = false
	if Themes.id() == "neon":
		# Miami: the whole page is drawn PIX times smaller and blown up with no smoothing, so every letter, the cover
		# and the buttons come out in the same chunky pixels as the Miami menu.
		_pix_vp = SubViewport.new()
		_pix_vp.transparent_bg = true
		_pix_vp.disable_3d = true
		_pix_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		_pix_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_pix_vp)
		_pix_vp.add_child(_root)
		var view := TextureRect.new()
		_pix_view = view
		view.visible = false
		view.texture = _pix_vp.get_texture()
		view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_SCALE
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pix_fit()
		get_viewport().size_changed.connect(_pix_fit)
	else:
		_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_root)
	var bg := ColorRect.new()
	bg.color = Themes.c("bg")
	_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sky = PageSkin.backdrop(_root)  # each theme's own sky, sun, glow or haze behind the page
	# A wash of the game's own colour at the top.
	_glow = ColorRect.new()
	_root.add_child(_glow)
	_glow.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_glow.offset_bottom = 640
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, PageSkin.wash()))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 256
	var wash := TextureRect.new()
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.color = Color(0, 0, 0, 0)
	_glow.set_meta("wash", wash)

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.position = Vector2(110, 150)
	_art.size = Vector2(340, 510)
	if Themes.id() == "neon":
		# Miami: a pink block behind the cover, like the title's 3D letters
		var block := ColorRect.new()
		block.color = Color("FF2E88")
		block.position = _art.position + Vector2(14, 14)
		block.size = _art.size
		_root.add_child(block)
	elif Themes.id() == "ps2":
		var edge := ColorRect.new()
		edge.color = Color(Themes.c("select"), 0.6)
		edge.position = _art.position - Vector2(2, 2)
		edge.size = _art.size + Vector2(4, 4)
		_root.add_child(edge)
	if PageSkin.cover_radius() > 0.0:
		Rounded.apply(_art, Vector2(340, 510), PageSkin.cover_radius())
	_root.add_child(_art)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	_root.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 520
	col.offset_right = -110
	col.offset_top = 130
	col.offset_bottom = -120
	_title = _label("", 58, TEXT)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	_miami(_title, 12)
	if Themes.id() == "neon":  # Miami: cyan letters with a pink block behind, like the menu
		_title.add_theme_color_override("font_color", Themes.c("select"))
		_title.add_theme_color_override("font_shadow_color", Color("FF2E88"))
		_title.add_theme_constant_override("shadow_offset_x", 5)
		_title.add_theme_constant_override("shadow_offset_y", 5)
		_title.add_theme_color_override("font_outline_color", Themes.c("bg"))
		_title.add_theme_constant_override("outline_size", 10)
	col.add_child(_title)
	_sub = _label("", 24, MUTED)
	col.add_child(_sub)
	_buttons_row = HBoxContainer.new()
	_buttons_row.add_theme_constant_override("separation", 16)
	col.add_child(_buttons_row)
	_status = _label("", 24, MUTED)
	col.add_child(_status)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	col.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 22)
	_content.custom_minimum_size.x = CONTENT_W
	_scroll.add_child(_content)

	_content.add_child(_section("Storage"))
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(CONTENT_W - 20, BAR_TOP + BAR_H + 44)
	_bar.draw.connect(_draw_bar)
	_content.add_child(_bar)
	_bar_line = _label("", 28, TEXT)
	_content.add_child(_bar_line)
	_bar_legend = _label("", 22, MUTED)
	_content.add_child(_bar_legend)

	# Two columns under the storage bar: About on the left (it gets all the height it needs),
	# your stats on the right, so they are on screen without scrolling.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	_content.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.x = CONTENT_W - STATS_W - 48
	cols.add_child(left)
	left.add_child(_section("About"))
	_facts = _label("", 22, MUTED)
	_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_facts)
	_desc = _label("", 26, TEXT.lerp(MUTED, 0.3))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_constant_override("line_spacing", 6)
	left.add_child(_desc)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.custom_minimum_size.x = STATS_W
	cols.add_child(right)
	right.add_child(_section("Your stats"))
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 28)
	_grid.add_theme_constant_override("v_separation", 14)
	right.add_child(_grid)
	var pad := Control.new()
	pad.custom_minimum_size.y = 200
	_content.add_child(pad)

	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(_hints)
	_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hints.offset_top = -100
	_hints.offset_bottom = -40
	_hints.offset_right = -110

	_req = HTTPRequest.new()
	_req.timeout = 10.0
	add_child(_req)
	_req.request_completed.connect(_on_store)
	_deck_req = HTTPRequest.new()
	_deck_req.timeout = 10.0
	add_child(_deck_req)
	_deck_req.request_completed.connect(_on_deck)

const PIX := 2.0   # Miami: how big each pixel of the page is
var _pix_vp: SubViewport
var _pix_view: TextureRect

# Miami: draw the page only while it shows (a stopped viewport would keep its last picture up, so it hides too).
func _pix_on(on: bool) -> void:
	if _pix_vp == null:
		return
	_pix_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_pix_view.visible = on

func _pix_fit() -> void:
	var sz := get_viewport().get_visible_rect().size
	_pix_vp.size = Vector2i((sz / PIX).ceil())
	_root.size = sz
	_root.scale = Vector2.ONE / PIX

## Miami's chunky font for the big words (title, buttons, headings); the long text keeps the plain font so it reads.
func _miami(l: Label, outline := 6) -> void:
	if Themes.id() != "neon" or Themes.font("neon") == null:
		return
	l.add_theme_font_override("font", Themes.font("neon"))
	l.add_theme_color_override("font_outline_color", Themes.c("bg"))
	l.add_theme_constant_override("outline_size", outline)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _section(text: String) -> Control:
	var l := _label(text.to_upper(), 22, PageSkin.heading(_color))
	_miami(l, 4)
	l.add_theme_constant_override("line_spacing", 0)
	return l

# ---------- Open / close ----------
func open(game: Dictionary, cover: Texture2D) -> void:
	_game = game
	_id = str(game["id"])
	_cover = cover
	_sel = 0
	_info = {}
	_need = 0.0
	_dl_total = 0.0
	_dl_pct = -1.0
	_art.texture = cover
	_ensure_cover()
	_color = _color_of(cover, _id)
	_apply_color()
	_scroll.scroll_vertical = 0
	_status.text = ""
	var dir: String = _lib._home.steam_dir
	var sz := _drive(dir)
	_total = sz.x
	_free = sz.y
	if _lib._home.details != null and _lib._home.details.has_method("_scan_storage") and not _lib._home.details._store.has("proton"):
		_lib._home.details._scan_storage()  # Proton / Workshop sizes for the bar's breakdown
	_load_cached()
	refresh()
	is_open = true
	_root.visible = true
	_pix_on(true)
	_root.modulate.a = 0.0
	Motion.fade_to(_root, 1.0, 0.22)
	Motion.pop(_art, 0.96, 0.25)
	set_process(true)
	_fetch()

## The page always shows a cover: when the tile had none (or only a wide banner), the tall Steam picture is
## looked up, downloaded (also through Steam's store data for newer games) and swapped in; the wide header
## picture is the last resort.
func _ensure_cover() -> void:
	var home = _lib._home
	if _cover != null and home.cover_ok(_cover):
		return
	var id := _id
	var recolor := func() -> void:
		if _id == id:
			_recolor()
	var fallback := func() -> void:
		if _id != id:
			return
		home._load_art(id, "header", _art, "jpg", recolor)
	var retry := func() -> void:
		home._art_fetched.erase(id)
		await home.prefetch_art(id)
		if _id != id:
			return
		home._load_art(id, "library_600x900", _art, "jpg", recolor, fallback)
	home._load_art(id, "library_600x900", _art, "jpg", recolor, retry)

## The page colour comes from the picture on show. When the cover is looked up or downloaded after the page opened
## (so there was none to read at first), this runs once it arrives: otherwise the colours stay a made-up one.
func _recolor() -> void:
	if _art == null or _art.texture == null:
		return
	_color = _color_of(_art.texture, _id)
	_apply_color()
	refresh()  # buttons, section headings and the bar are all drawn with the colour

## Puts the game's colour on the wash at the top and, on the light themes, on the whole sky behind the page.
func _apply_color() -> void:
	(_glow.get_meta("wash") as TextureRect).modulate = _color
	if _sky != null and PageSkin.tints_sky():
		var sky := PageSkin.sky_colors(_color)
		_sky.set_color(0, sky[0])
		_sky.set_color(1, sky[1])

func close() -> void:
	if not is_open:
		return
	is_open = false
	set_process(false)
	_req.cancel_request()
	_deck_req.cancel_request()
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, Motion.dur(0.18))
	await t.finished
	if not is_open:
		_root.visible = false
		_pix_on(false)

## Closes at once (the Library itself is closing).
func hide_now() -> void:
	is_open = false
	set_process(false)
	_root.visible = false
	_pix_on(false)

## Call when the game's state changed (installed, renamed, pinned).
func refresh(game := {}) -> void:
	if not game.is_empty():
		_game = game
		_id = str(game["id"])
	_title.text = str(_game["title"])
	var orig := str(_game.get("orig_title", _game["title"]))
	_sub.text = _stats_line() if orig == _title.text else ("%s   ·   %s" % [orig, _stats_line()])
	_build_buttons()
	_fill_info()
	_fill_stats()
	_update_bar_text()
	_bar.queue_redraw()
	_refresh_hints()

## Steam started the download: pct 0..1 (-1 = not known yet), total = bytes it will fetch (0 = not known yet).
func set_progress(pct: float, total: float) -> void:
	_dl_pct = pct
	if total > 0.0:
		_dl_total = total
	if is_open:
		_build_buttons()
		_update_bar_text()

func set_status(text: String) -> void:
	_status.text = text

func finish() -> void:
	_status.text = "Download started. The bar shows its size and you can follow it on the tile."

# ---------- Buttons ----------
func _installed() -> bool:
	return _lib._is_installed(_id)

func _downloading() -> bool:
	return _lib._installing.has(_id)

func _room_ok() -> bool:
	return not (_need > 0.0 and _free > 0.0 and _need > _free)

func _build_buttons() -> void:
	for c in _buttons_row.get_children():
		_buttons_row.remove_child(c)
		c.queue_free()
	_keys.clear()
	var items: Array = []
	if _installed():
		items.append(["play", "Running" if _lib._home.game_is_running(_id) else "Play"])
		items.append(["pin", "Pin to Home" if _lib._is_hidden(_id) else "Unpin from Home"])
	elif _downloading():
		items.append(["wait", "Downloading %d%%" % roundi(_dl_pct * 100.0) if _dl_pct >= 0.0 else "Starting..."])
	elif _room_ok():
		items.append(["install", "Install"])
	else:
		items.append(["noroom", "Not enough room"])
	items.append(["rename", "Rename"])
	if bool(_game.get("ps2", false)) and _lib._home.ps2_has_remake_art(_id):
		items.append(["art", "Art: Original" if _lib._home.ps2_art_original(_id) else "Art: Remake"])
	if _installed() and not bool(_game.get("ps2", false)):
		items.append(["mods", "Mods"])
	if _installed() and not bool(_game.get("nonsteam", false)) and not _lib._home.launching:
		items.append(["uninstall", "Uninstall"])
	if bool(_game.get("nonsteam", false)) and not bool(_game.get("ps2", false)) and not _lib._home.launching:
		items.append(["remove", "Remove from Library"])  # a non-Steam game (Add a game, or added in Steam)
	_sel = clampi(_sel, 0, items.size() - 1)
	for i in items.size():
		_keys.append(items[i][0])
		var on := i == _sel
		var p := PanelContainer.new()
		var primary := i == 0
		var sb := PageSkin.button(on, primary, _color, primary and items[i][0] == "noroom")
		sb.content_margin_left = 34
		sb.content_margin_right = 34
		sb.content_margin_top = 14
		sb.content_margin_bottom = 14
		p.add_theme_stylebox_override("panel", sb)
		Rounded.rough(p)
		var l := _label(PageSkin.words(items[i][1]), 26 if Themes.id() == "neon" else 30, PageSkin.button_text(on, primary, _color))
		_miami(l, 4)
		p.add_child(l)
		_buttons_row.add_child(p)

# ---------- Input ----------
func move(dx: int, dy: int) -> void:
	if dx != 0:
		var n := posmod(_sel + dx, _keys.size()) if not _keys.is_empty() else 0
		if n != _sel:
			_sel = n
			Haptics.select()
			_build_buttons()
			_refresh_hints()
	elif dy != 0:
		_scroll_by(dy * 260)

func _scroll_by(px: int) -> void:
	var max_v := int(maxf(0.0, _content.size.y - _scroll.size.y))
	var target := clampi(_scroll.scroll_vertical + px, 0, max_v)
	if _scroll_tween != null:
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_scroll, "scroll_vertical", target, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event is InputEventJoypadMotion:
		return true
	if event.is_action_pressed("ui_cancel"):
		Haptics.tick()
		close()
	elif (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.north_button()) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Y):
		if _installed() and not _lib._home.cross_opens_info():
			Haptics.tick()
			action.emit("menu", _game)  # Pin / Unpin, Rename, Uninstall
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		var key: String = _keys[_sel] if _sel < _keys.size() else ""
		match key:
			"play":
				if not _lib._home.game_is_running(_id) and not _lib._home.launching:
					await _pulse_cover()  # the same grow-and-settle as a tile on Home, then the game starts
				action.emit(key, _game)
			"install", "pin", "rename", "uninstall", "mods", "remove":
				action.emit(key, _game)
			"art":
				# Original look (from the PS2 box) or the remake's pictures, borrowed from its Steam page.
				var orig: bool = not _lib._home.ps2_art_original(_id)
				_lib._home.set_ps2_art_original(_id, orig)
				_lib._home._load_art(_id, "library_600x900", _art)  # the page's own cover changes straight away
				Haptics.confirm()
				_build_buttons()
				_lib._home.dev_toast(("Original art" if orig else "Remake art") + ". You can change this at any time.")
			_:
				Haptics.tick()
	return true

## Play: the cover grows with a little spring, like a game tile on Home does, with the launch sound and rumble.
func _pulse_cover() -> void:
	Haptics.launch()
	_lib._home.sfx.play("launch")
	if not Motion.on() or _art == null:
		return
	_art.pivot_offset = _art.size / 2.0
	var pop := create_tween()
	pop.tween_property(_art, "scale", Vector2.ONE * 1.04, 0.08).set_trans(Tween.TRANS_SINE)
	pop.tween_property(_art, "scale", Vector2.ONE * 1.12, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await pop.finished
	create_tween().tween_property(_art, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE).set_delay(0.3)

func _refresh_hints() -> void:
	var key: String = _keys[_sel] if _sel < _keys.size() else ""
	var label: String = {"play": "Running" if _lib._home.game_is_running(_id) else "Play", "install": "Install", "pin": "Pin / Unpin", "rename": "Rename", "uninstall": "Uninstall", "mods": "Mods", "remove": "Remove", "art": "Switch art"}.get(key, "OK")
	var hints: Array = [["accept", label], ["dpad", "Choose / Scroll"]]
	if _installed() and not _lib._home.cross_opens_info():
		hints.append(["north", "Options"])
	hints.append(["back", "Back"])
	TephraGlyphs.fill(_hints, hints, 28)

# ---------- Colour ----------
func _color_of(tex: Texture2D, id: String) -> Color:
	return cover_color(tex, id)

## The colour a cover is mostly about: bright, colourful pixels vote for their hue, the hue with the most votes wins,
## and the colour is the average of the pixels in it. (Averaging all the pixels together turned a red and teal cover
## into green.) A cover that is nearly grey, or has no picture, gets a colour made from the game's number.
static func cover_color(tex: Texture2D, id: String) -> Color:
	var fallback := Color.from_hsv(float(hash(id) % 360) / 360.0, 0.62, 0.92)
	if tex == null:
		return fallback
	var img := tex.get_image()
	if img == null or img.is_empty():
		return fallback
	img = img.duplicate()
	if img.is_compressed():
		if img.decompress() != OK:
			return fallback
	img.resize(16, 24, Image.INTERPOLATE_BILINEAR)
	const BINS := 24
	var votes := PackedFloat32Array()
	votes.resize(BINS)
	var sums: Array = []
	for _i in BINS:
		sums.append(Vector3.ZERO)
	var total := 0.0
	for y in 24:
		for x in 16:
			var c := img.get_pixel(x, y)
			var w := c.s * c.s * c.v   # colourful and bright counts most; grey and dark pixels hardly vote
			if w < 0.02:
				continue
			var bin := int(c.h * BINS) % BINS
			votes[bin] += w
			sums[bin] += Vector3(c.r, c.g, c.b) * w
			total += w
	if total <= 0.0:
		return fallback
	# The winning hue, counting its two neighbours so one hue split across a bin edge is not lost.
	var best := 0
	var best_v := -1.0
	for i in BINS:
		var v := votes[i] + 0.5 * (votes[(i + 1) % BINS] + votes[(i + BINS - 1) % BINS])
		if v > best_v:
			best_v = v
			best = i
	var sum := Vector3.ZERO
	var wsum := 0.0
	for d in [-1, 0, 1]:
		var j: int = (best + d + BINS) % BINS
		sum += sums[j]
		wsum += votes[j]
	if wsum <= 0.0:
		return fallback
	var avg := Color(sum.x / wsum, sum.y / wsum, sum.z / wsum)
	if avg.s < 0.12:
		return fallback
	return Color.from_hsv(avg.h, clampf(avg.s * 1.15, 0.55, 0.92), clampf(avg.v * 1.2, 0.78, 1.0))

# ---------- Disk bar ----------
static func _drive(path: String) -> Vector2:
	var out := []
	if OS.execute("df", ["-B1", "--output=size,avail", path], out) != 0 or out.is_empty():
		return Vector2.ZERO
	var lines: PackedStringArray = str(out[0]).strip_edges().split("\n")
	if lines.size() < 2:
		return Vector2.ZERO
	var parts := lines[lines.size() - 1].strip_edges().split(" ", false)
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(float(parts[0].to_int()), float(parts[1].to_int()))

func _game_bytes() -> float:
	if _installed():
		return float(_lib._home_game(_id).get("size", 0))
	if _dl_total > 0.0:
		return _dl_total
	return _need

## The game's part of the bar always pulses slowly, installed or not, so it is easy to spot.
func _flashing() -> bool:
	return true

func _draw_bar() -> void:
	var w := _bar.size.x
	var h := BAR_H
	var y0 := BAR_TOP
	var r := PageSkin.bar_radius()
	var back := StyleBoxFlat.new()
	back.bg_color = Themes.ink(0.07)
	back.set_corner_radius_all(Themes.r(int(r)))
	_bar.draw_style_box(back, Rect2(0, y0, w, h))
	if _total <= 0.0:
		return
	var gb := _game_bytes()
	var installed := _installed()
	var used := _total - _free
	var others := maxf(0.0, used - (gb if installed else 0.0))
	var ow := clampf(others / _total, 0.0, 1.0) * w
	var gw := clampf(gb / _total, 0.0, 1.0) * w
	if gb > 0.0:
		gw = maxf(gw, 18.0)  # even a small game gets a part you can see
	# What else fills the drive, when the Home page has measured it: other games, Proton, Workshop and the rest.
	var st: Dictionary = {}
	if _lib._home.details != null:
		st = _lib._home.details._store
	var parts: Array = []
	if st.has("proton"):
		var og := maxf(float(st.get("games", 0.0)) + float(st.get("home_games", 0.0)) - (gb if installed else 0.0), 0.0)
		var pr := float(st.get("proton", 0.0))
		var wk := float(st.get("workshop", 0.0))
		var known := og + pr + wk
		if known > others and known > 0.0:
			var f := others / known
			og *= f
			pr *= f
			wk *= f
			known = others
		parts = [["Other games", og, Color("3D8BFF").darkened(0.35)], ["Proton", pr, Color("8B6CFF")], ["Workshop", wk, Color("46D17B")], ["Other", maxf(others - known, 0.0), OTHER]]
	else:
		parts = [["Other", others, OTHER]]
	var px := 0.0
	var first := true
	for pt in parts:
		var pw := clampf(float(pt[1]) / _total, 0.0, 1.0) * w
		if pw < 1.0:
			continue
		var ps := StyleBoxFlat.new()
		ps.bg_color = pt[2]
		ps.set_corner_radius_all(0)
		if first:
			ps.corner_radius_top_left = Themes.r(r)
			ps.corner_radius_bottom_left = Themes.r(r)
			first = false
		_bar.draw_style_box(ps, Rect2(px, y0, pw, h))
		px += pw
	# One line of legend under the bar: a coloured dot, the name and the size, for every part.
	var lfont := ThemeDB.fallback_font
	var lx := 0.0
	var ly := y0 + h + 30.0
	# The names follow the bar from left to right: the other parts first, then this game, then the free space.
	var legend: Array = []
	legend.append_array(parts)
	legend.append(["This game", gb, _color])
	legend.append(["Free", _free, Themes.ink(0.4)])
	for lg in legend:
		if float(lg[1]) < 52428800.0 and lg[0] != "Free" and lg[0] != "This game":
			continue
		var lt := "%s %s" % [lg[0], InstallDialog.fmt_bytes(float(lg[1]))]
		_bar.draw_circle(Vector2(lx + 6.0, ly - 7.0), 6.0, lg[2])
		_bar.draw_string(lfont, Vector2(lx + 18.0, ly), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Themes.c("muted"))
		lx += 18.0 + lfont.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24.0
	if gw > 0.0:
		var c := _color
		var k := 0.5 + 0.5 * sin(_t * TAU / 2.8)   # one slow pulse every 2.8 s
		if _flashing():
			c = _color.darkened(0.6 * (1.0 - k)).lightened(0.15 * k)
		var seg := StyleBoxFlat.new()
		seg.bg_color = c
		seg.set_corner_radius_all(Themes.r(0))
		if ow <= 0.5:
			seg.corner_radius_top_left = Themes.r(r)
			seg.corner_radius_bottom_left = Themes.r(r)
		if ow + gw >= w - 0.5:
			seg.corner_radius_top_right = Themes.r(r)
			seg.corner_radius_bottom_right = Themes.r(r)
		# A glow around the game's part that breathes with it.
		var gx := ow
		var gwid := minf(gw, w - ow)
		for i in 3:
			var grow := 3.0 + 4.0 * i
			var halo := StyleBoxFlat.new()
			halo.bg_color = Color(0, 0, 0, 0)
			halo.border_color = Color(_color.r, _color.g, _color.b, (0.22 - 0.06 * i) * k)
			halo.set_border_width_all(4)
			halo.set_corner_radius_all(Themes.r(int(r + grow)))
			_bar.draw_style_box(halo, Rect2(gx - grow, y0 - grow, gwid + grow * 2.0, h + grow * 2.0))
		_bar.draw_style_box(seg, Rect2(gx, y0, gwid, h))
		# The game's size above its part, with a small pointer down to it.
		var font := ThemeDB.fallback_font
		var txt := InstallDialog.fmt_bytes(gb)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var cx := gx + gwid / 2.0
		var tx := clampf(cx - tw / 2.0, 0.0, w - tw)
		_bar.draw_string(font, Vector2(tx, y0 - 14.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(_color.r, _color.g, _color.b).lightened(0.25))
		_bar.draw_colored_polygon(PackedVector2Array([Vector2(cx - 7, y0 - 9), Vector2(cx + 7, y0 - 9), Vector2(cx, y0 - 2)]), _color)

func _update_bar_text() -> void:
	if _installed():
		var sz := float(_lib._home_game(_id).get("size", 0))
		_bar_line.text = ("Takes up " + InstallDialog.fmt_bytes(sz) + " on this drive") if sz > 0.0 else "Installed"
		_bar_line.add_theme_color_override("font_color", TEXT)
	elif _downloading():
		if _dl_total > 0.0:
			_bar_line.text = "Downloading: will take up " + InstallDialog.fmt_bytes(_dl_total)
		else:
			_bar_line.text = "Downloading. The size shows once Steam has started."
		_bar_line.add_theme_color_override("font_color", TEXT)
	elif _need > 0.0:
		if _room_ok():
			_bar_line.text = "Once downloaded this will take up about " + InstallDialog.fmt_bytes(_need)
			_bar_line.add_theme_color_override("font_color", TEXT)
		else:
			_bar_line.text = "About %s needed, only %s free. Make room first." % [InstallDialog.fmt_bytes(_need), InstallDialog.fmt_bytes(_free)]
			_bar_line.add_theme_color_override("font_color", BAD)
	else:
		_bar_line.text = "Steam shows the size once the download starts."
		_bar_line.add_theme_color_override("font_color", MUTED)
	if _total > 0.0:
		var after := _free - (0.0 if _installed() else _game_bytes())
		_bar_legend.text = "Drive %s   ·   Free %s%s" % [InstallDialog.fmt_bytes(_total), InstallDialog.fmt_bytes(_free),
			"" if _installed() or _game_bytes() <= 0.0 else ("   ·   Free afterwards " + InstallDialog.fmt_bytes(maxf(after, 0.0)))]
	else:
		_bar_legend.text = ""

func _process(delta: float) -> void:
	_t += delta
	if _flashing() and _bar.is_visible_in_tree():
		_bar.queue_redraw()

# ---------- Facts and stats ----------
func _stats_line() -> String:
	return "   ·   ".join(stats_parts(_game, _lib._home.steam_dir, _lib._home_game(_id)))

## The one-line summary shown in the Library under the game's name and on this page: last played, hours, achievements, size.
static func stats_parts(g: Dictionary, steam_dir: String, installed: Dictionary) -> Array:
	var parts: Array = []
	var last := int(installed.get("last", g.get("last", 0)))
	if last > 0:
		var d := Time.get_datetime_dict_from_unix_time(last)
		parts.append("Last played %s %d" % [MONTHS[int(d["month"]) - 1], d["day"]])
	var mins := maxi(int(g.get("playtime", 0)), int(installed.get("playtime", 0)))
	if mins > 0:
		parts.append(("%.1f h played" % (mins / 60.0)) if mins >= 60 else ("%d min played" % mins))
	var id := str(g.get("id", ""))
	if not bool(g.get("nonsteam", false)) or bool(g.get("ps2", false)):  # PS2 games carry RetroAchievements
		var acc := Achievements.account_id(SteamAccount.steam_id(steam_dir))
		var ach := Achievements.for_game(steam_dir, acc, id)
		if not ach.is_empty():
			parts.append("%d / %d achievements" % [ach["unlocked"], ach["total"]])
	var size := float(installed.get("size", 0))
	if size > 0.0:
		parts.append(InstallDialog.fmt_bytes(size))
	if parts.is_empty():
		parts.append("Not played yet")
	return parts

func _fill_info() -> void:
	var bits: Array = []
	var genres: Array = _info.get("genres", [])
	if not genres.is_empty():
		bits.append(", ".join(genres))
	if str(_info.get("dev", "")) != "":
		bits.append(str(_info["dev"]))
	if str(_info.get("date", "")) != "":
		bits.append(str(_info["date"]))
	_facts.text = "   ·   ".join(bits)
	_facts.visible = not bits.is_empty()
	if bool(_game.get("nonsteam", false)):
		_desc.text = ("A PS2 game, played in PCSX2. " if bool(_game.get("ps2", false)) else "") + "A non-Steam game you added to Steam. Tephra starts it through Steam, so its controller settings and compatibility layer apply."
	elif str(_info.get("desc", "")) != "":
		_desc.text = str(_info["desc"])
	else:
		_desc.text = "Loading the store page..." if _info.is_empty() else "The store has no description for this game."

func _fill_stats() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var rows: Array = []
	var inst: Dictionary = _lib._home_game(_id)
	var mins := maxi(int(_game.get("playtime", 0)), int(inst.get("playtime", 0)))
	rows.append(["Time played", (("%.1f hours" % (mins / 60.0)) if mins >= 60 else ("%d minutes" % mins)) if mins > 0 else "Not played yet"])
	# The ones you look for first (time, achievements, controller, Steam Deck) come first.
	var last := int(inst.get("last", 0))
	var last_row: Array = []
	if last > 0:
		var d := Time.get_datetime_dict_from_unix_time(last)
		last_row = ["Last played", "%s %d, %d" % [MONTHS[int(d["month"]) - 1], d["day"], d["year"]]]
	if not bool(_game.get("nonsteam", false)) or bool(_game.get("ps2", false)):
		var acc := Achievements.account_id(SteamAccount.steam_id(_lib._home.steam_dir))
		var ach := Achievements.for_game(_lib._home.steam_dir, acc, _id)
		if not ach.is_empty():
			rows.append(["Achievements", "%d of %d" % [ach["unlocked"], ach["total"]]])
	match str(_info.get("controller", "")):
		"full": rows.append(["Controller", "Full support"])
		"partial": rows.append(["Controller", "Partial support"])
	match int(_info.get("deck", 0)):
		3: rows.append(["Steam Deck", "Verified"])
		2: rows.append(["Steam Deck", "Playable"])
		1: rows.append(["Steam Deck", "Unsupported"])
	if not last_row.is_empty():
		rows.append(last_row)
	var size := float(inst.get("size", 0))
	if size > 0.0:
		rows.append(["Size on disk", InstallDialog.fmt_bytes(size)])
	if _lib._home.perf != null:
		for s in _lib._home.perf.summaries(60):
			if str(s["appid"]) == _id:
				rows.append(["Average load", "CPU %d%%%s\n%.1f GB RAM" % [roundi(s["cpu"]), ("  ·  GPU %d%%" % roundi(s["gpu"])) if s["gpu"] >= 0.0 else "", s["ram_gb"]]])
				rows.append(["Measured for", "%d min" % int(s["minutes"])])
	for r in rows:
		var k := _label(r[0], 24, MUTED)
		k.custom_minimum_size.x = 190
		_grid.add_child(k)
		var v := _label(r[1], 28, TEXT)
		v.custom_minimum_size.x = STATS_W - 190 - 28
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_grid.add_child(v)

# ---------- Store ----------
func _cache_path() -> String:
	return "user://info/%s_page.json" % _id

func _load_cached() -> void:
	var p := _cache_path()
	if not FileAccess.file_exists(p):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if d is Dictionary:
		_info = d
		_need = float(d.get("need", 0.0))
	# The Deck and controller badges the details panel already saved.
	var p2 := "user://info/%s.json" % _id
	if FileAccess.file_exists(p2):
		var e = JSON.parse_string(FileAccess.get_file_as_string(p2))
		if e is Dictionary:
			_info["deck"] = int(e.get("deck", 0))
			if str(_info.get("controller", "")) == "":
				_info["controller"] = str(e.get("controller", ""))

func _fetch() -> void:
	if bool(_game.get("nonsteam", false)):
		return
	var fetched := float(_info.get("fetched", 0))
	if fetched > 0.0 and Time.get_unix_time_from_system() - fetched < CACHE_DAYS * 86400.0:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://info"))
	_req.cancel_request()
	_req.request(STORE_URL % _id)
	if not _info.has("deck"):
		_deck_req.cancel_request()
		_deck_req.request(InfoPanel.DECK_URL % _id)

func _on_store(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not is_open:
		if is_open and _info.is_empty():
			_info = {"desc": ""}
			refresh()
		return
	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text)
	var entry = data.get(_id) if data is Dictionary else null
	var info := {"fetched": Time.get_unix_time_from_system()}
	if entry is Dictionary and entry.get("success", false) and entry.get("data") is Dictionary:
		var d: Dictionary = entry["data"]
		info["desc"] = _clean(str(d.get("about_the_game", d.get("short_description", ""))), 3000)
		if str(info["desc"]) == "":
			info["desc"] = _clean(str(d.get("short_description", "")), 3000)
		var genres: Array = []
		for gd in d.get("genres", []):
			if gd is Dictionary:
				genres.append(str(gd.get("description", "")))
		info["genres"] = genres
		var devs = d.get("developers", [])
		info["dev"] = str(devs[0]) if devs is Array and not devs.is_empty() else ""
		var rd = d.get("release_date", {})
		info["date"] = str(rd.get("date", "")) if rd is Dictionary else ""
		info["controller"] = str(d.get("controller_support", ""))
		info["need"] = InstallDialog.need_from_store_json(text, _id)
	for k in info:
		_info[k] = info[k]
	_need = float(_info.get("need", _need))
	_save_cache()
	refresh()

func _on_deck(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not is_open:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if d is Dictionary and d.get("results") is Dictionary:
		_info["deck"] = int(d["results"].get("resolved_category", 0))
		_save_cache()
		_fill_stats()

func _save_cache() -> void:
	var f := FileAccess.open(_cache_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_info))

## Store text has HTML in it: tags go, line breaks stay, entities become characters.
static func _clean(s: String, max_len: int) -> String:
	s = s.replace("<br>", "\n").replace("<br />", "\n").replace("</p>", "\n").replace("</li>", "\n").replace("</h2>", "\n")
	var re := RegEx.new()
	re.compile("<[^>]+>")
	s = re.sub(s, "", true)
	for pair in [["&quot;", "\""], ["&#39;", "'"], ["&amp;", "&"], ["&lt;", "<"], ["&gt;", ">"], ["&nbsp;", " "]]:
		s = s.replace(pair[0], pair[1])
	var multi := RegEx.new()
	multi.compile("\\n{3,}")
	s = multi.sub(s.strip_edges(), "\n\n", true)
	if s.length() > max_len:
		s = s.substr(0, max_len).strip_edges() + "..."
	return s
