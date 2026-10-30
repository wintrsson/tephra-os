extends Control
## The Channels theme's Home: pages of glossy game "channels" in a 4 x 3 grid, with a curved bar
## along the bottom holding the clock and date, a round Home button on the left and a round
## Settings button on the right. All original drawing; it only borrows the general idea of a
## channel menu.
##
##   Page 1      the games on your Home row (in the same order)
##   Page 2, 3…  the rest of your Library (installed or not), A-Z
##
## Everything is moved with the controller: the D-pad / stick steps between channels and runs off
## the side of a page onto the next one, L1 / R1 flip whole pages, Down from the bottom row reaches
## the round buttons, Up from the top row goes to the top bar. home.gd hands its input here.

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const Icons = preload("res://icons.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const Rounded = preload("res://rounded.gd")
const TephraGlyphs = preload("res://glyphs.gd")

const COLS := 4
const ROWS := 3
const PER_PAGE := COLS * ROWS
const TILE := Vector2(392, 186)
const GAP := 30.0
const GRID_TOP := 196.0
const RADIUS := 26.0
const BAR_TOP := 902.0      # the flat middle of the bottom bar
const BAR_RISE := 70.0      # how far it curves up around the round buttons
const BTN_R := 68.0         # round button radius
const BTN_Y := 1004.0     # low in the bar, in its corners
const BTN_X := 178.0        # distance of each button's centre from its side of the screen
const DAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

var home  # home.gd

var _items: Array = []      # one per channel: {id, title, gi (index in home.games or -1), g (Library entry)}
var _page := 0
var _sel := 0               # channel on the current page, 0..11
var _focus := "grid"        # "grid", "info" or "settings"
var _pages: Array = []      # one Control per page, side by side
var _tiles: Array = []      # per page: the 12 tile Controls
var _frames: Array = []     # per page: each tile's border style
var _hints: HBoxContainer   # button glyphs on the right of the bottom bar
var _lib_page0 := 1        # the first page of the rest of the Library (the pages before it are Home)
var _tag: Label            # "Library" on the Library pages, so they read as different from Home
var _strip: Control         # holds every page; slides sideways
var _slide: Tween
var _bar: Control
var _clock: Label
var _date: Label
var _name: Label            # the focused channel's name, just above the bar
var _btn_info: Control
var _btn_set: Control
var _arrow_l: Control
var _arrow_r: Control
var _t := 0.0
var _clock_t := 99.0
var _select_col: Color = Themes.c("select")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_name = _label("", 30, Themes.c("muted"))
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name)
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clock = _label("", 76, Themes.c("muted"))
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_clock)
	_date = _label("", 32, Themes.c("muted"))
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_date)
	_hints = HBoxContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.alignment = BoxContainer.ALIGNMENT_END
	add_child(_hints)
	TephraGlyphs.fill(_hints, [["accept", "Options"]] if home.cross_opens_info() else [["accept", "Running" if home.game_is_running(str(home.games[home._game_selected()]["id"]) if home._game_selected() >= 0 else "") else "Play"], ["north", "Options"]], 24)
	_tag = _label("Library", 38, Themes.c("select"))
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.modulate.a = 0.0
	add_child(_tag)
	_btn_info = _round_button(Icons.texture("home_ch", Icons.svg_home(), 76))
	_btn_set = _round_button(Icons.texture("gear_ch", Icons.svg_gear(), 76))
	_arrow_l = _arrow(-1)
	_arrow_r = _arrow(1)
	resized.connect(_layout)
	rebuild()

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---------- Building ----------
## Re-reads the games (Home row first, then the rest of the Library) and rebuilds the pages,
## keeping the same game focused when it is still there.
func rebuild() -> void:
	var keep_id := ""
	var cur := _current()
	if not cur.is_empty():
		keep_id = str(cur["id"])
	_items.clear()
	var seen := {}
	for i in home.games.size():
		var g: Dictionary = home.games[i]
		if home.on_home(g):
			_items.append({"id": str(g["id"]), "title": str(g["title"]), "gi": i, "g": g})
			seen[str(g["id"])] = true
	_pad_page()  # the rest of the Library starts on a fresh page
	_lib_page0 = _items.size() / PER_PAGE
	var rest: Array = []
	for g in home.library.all_games():
		var id := str(g["id"])
		if seen.has(id):
			continue
		seen[id] = true
		var gi := -1
		for i in home.games.size():
			if str(home.games[i]["id"]) == id:
				gi = i
				break
		rest.append({"id": id, "title": str(g["title"]), "gi": gi, "g": g})
	_items += rest
	_pad_page()  # empty channels fill the last page, like unused slots
	for p in _pages:
		p.queue_free()
	_pages.clear()
	_tiles.clear()
	_frames.clear()
	for p in _items.size() / PER_PAGE:
		_build_page(p)
	var pages := _items.size() / PER_PAGE
	_page = clampi(_page, 0, pages - 1)
	if keep_id != "":
		for i in _items.size():
			if str(_items[i].get("id", "")) == keep_id:
				_page = i / PER_PAGE
				_sel = i % PER_PAGE
				break
	_layout()
	_strip.position.x = -_page * size.x
	_update_tag()
	_highlight(false)

func _pad_page() -> void:
	var want := maxi(ceili(_items.size() / float(PER_PAGE)), 1) * PER_PAGE
	while _items.size() < want:
		_items.append({})

func _build_page(p: int) -> void:
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(page)
	_pages.append(page)
	var tiles: Array = []
	var frames: Array = []
	for k in PER_PAGE:
		var it: Dictionary = _items[p * PER_PAGE + k]
		var t := _make_tile(it)
		page.add_child(t)
		tiles.append(t)
		frames.append(t.get_meta("frame"))
	_tiles.append(tiles)
	_frames.append(frames)

func _make_tile(it: Dictionary) -> Control:
	var holder := Control.new()
	holder.size = TILE
	holder.pivot_offset = TILE / 2.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Body: a soft white rounded box with a light grey rim and a faint shadow.
	var body := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Themes.c("tile") if not it.is_empty() else Color(Themes.c("tile"), 0.55)
	sb.set_corner_radius_all(Themes.r(int(RADIUS)))
	sb.border_color = Color(0.78, 0.80, 0.84) if Themes.light() else Themes.ink(0.2)
	sb.set_border_width_all(3)
	sb.shadow_color = Color(0, 0, 0, 0.10)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	body.add_theme_stylebox_override("panel", sb)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size = TILE
	holder.add_child(body)
	if not it.is_empty():
		var inset := 7.0
		var art_size := TILE - Vector2(inset, inset) * 2.0
		var title_l := _label(str(it["title"]), 26, Themes.c("text"))
		title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title_l.position = Vector2(20, 10)
		title_l.size = TILE - Vector2(40, 20)
		holder.add_child(title_l)  # shows until the picture arrives (and stays if there is none)
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.position = Vector2(inset, inset)
		pic.size = art_size
		pic.modulate.a = 0.0
		holder.add_child(pic)
		Rounded.apply(pic, art_size, RADIUS - inset)
		if it.get("gi", -1) < 0:
			pic.self_modulate = Color(0.82, 0.83, 0.86)  # not installed: a little greyed
		var shown := func() -> void:
			if is_instance_valid(pic):
				title_l.visible = false
				create_tween().tween_property(pic, "modulate:a", 1.0, Motion.dur(0.25))
		home._load_art(str(it["id"]), "header", pic, "jpg", shown)

	# Gloss: light across the top half, like a shiny plastic cover.
	var gloss := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.48, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	gloss.texture = gt
	gloss.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gloss.stretch_mode = TextureRect.STRETCH_SCALE
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gloss.size = TILE
	holder.add_child(gloss)
	Rounded.apply(gloss, TILE, RADIUS)
	# Focus frame: drawn just outside the tile in the theme's blue.
	var frame := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.draw_center = false
	fsb.border_color = _select_col
	fsb.set_border_width_all(0)
	fsb.set_corner_radius_all(Themes.r(int(RADIUS) + 6))
	frame.add_theme_stylebox_override("panel", fsb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = Vector2(-6, -6)
	frame.size = TILE + Vector2(12, 12)
	holder.add_child(frame)
	holder.set_meta("frame", fsb)
	return holder

func _round_button(icon: Texture2D) -> Control:
	var b := Control.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size = Vector2(BTN_R, BTN_R) * 2.0
	b.pivot_offset = b.size / 2.0
	b.set_meta("icon", icon)
	b.set_meta("on", false)
	b.draw.connect(func():
		var c := b.size / 2.0
		var on: bool = b.get_meta("on")
		b.draw_circle(c + Vector2(0, 4), BTN_R, Color(0, 0, 0, 0.08))
		b.draw_circle(c, BTN_R, Color(0.98, 0.985, 0.99))
		b.draw_circle(c - Vector2(0, BTN_R * 0.35), BTN_R * 0.7, Color(1, 1, 1, 0.55))  # gloss
		var ring := _select_col if on else Color(0.74, 0.77, 0.82)
		b.draw_arc(c, BTN_R - 3.0, 0.0, TAU, 64, ring, 6.0 if on else 4.0, true)
		var tex: Texture2D = b.get_meta("icon")
		b.draw_texture(tex, c - tex.get_size() / 2.0, _select_col if on else Themes.c("muted")))
	add_child(b)
	return b

func _arrow(dir: int) -> Control:
	var a := Control.new()
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.size = Vector2(56, 96)
	a.draw.connect(func():
		var w := a.size
		var pts := PackedVector2Array([Vector2(w.x * 0.3, 8), Vector2(w.x * 0.78, w.y / 2.0), Vector2(w.x * 0.3, w.y - 8)]) if dir > 0 \
			else PackedVector2Array([Vector2(w.x * 0.7, 8), Vector2(w.x * 0.22, w.y / 2.0), Vector2(w.x * 0.7, w.y - 8)])
		a.draw_polyline(pts, Color(1, 1, 1, 0.9), 16.0, true)
		a.draw_polyline(pts, _select_col, 9.0, true))
	add_child(a)
	return a

# ---------- Layout and drawing ----------
func _layout() -> void:
	var w := size.x
	var gw := COLS * TILE.x + (COLS - 1) * GAP
	var left := (w - gw) / 2.0
	for p in _pages.size():
		var page: Control = _pages[p]
		page.position = Vector2(p * w, 0)
		for k in PER_PAGE:
			var t: Control = _tiles[p][k]
			t.position = Vector2(left + (k % COLS) * (TILE.x + GAP), GRID_TOP + (k / COLS) * (TILE.y + GAP))
	_name.position = Vector2(0, GRID_TOP + ROWS * (TILE.y + GAP) - 6)
	_name.size = Vector2(w, 40)
	_clock.position = Vector2(0, BAR_TOP + 14)
	_clock.size = Vector2(w, 90)
	_date.position = Vector2(0, BAR_TOP + 104)
	_date.size = Vector2(w, 44)
	_tag.size = Vector2(w, 50)
	_tag.position = Vector2(0, 112)  # in the middle, above the grid: out of the way of the tiles but still easy to read
	_hints.size = Vector2(520, 50)
	_hints.position = Vector2(w - BTN_X - BTN_R - 40 - 520, BAR_TOP + 62)
	_btn_info.position = Vector2(BTN_X - BTN_R, BTN_Y - BTN_R)
	_btn_set.position = Vector2(w - BTN_X - BTN_R, BTN_Y - BTN_R)
	_arrow_l.position = Vector2(26, GRID_TOP + (ROWS * (TILE.y + GAP)) / 2.0 - 60)
	_arrow_r.position = Vector2(w - 26 - _arrow_r.size.x, _arrow_l.position.y)
	_bar.queue_redraw()

## The bottom bar: flat across the middle, curving up at both ends around the round buttons,
## with a thin line of the theme's blue along its top edge.
func _draw_bar() -> void:
	var w := size.x
	var h := size.y
	var top := PackedVector2Array()
	var steps := 96
	for i in steps + 1:
		var x := w * i / steps
		top.append(Vector2(x, _bar_y(x, w)))
	var poly := top.duplicate()
	poly.append(Vector2(w, h))
	poly.append(Vector2(0, h))
	var cols := PackedColorArray()
	for p in poly:
		var k := clampf((p.y - (BAR_TOP - BAR_RISE)) / (h - BAR_TOP + BAR_RISE), 0.0, 1.0)
		cols.append(Color(0.93, 0.94, 0.955).lerp(Color(0.84, 0.86, 0.89), k))
	_bar.draw_polygon(poly, cols)
	_bar.draw_polyline(top, Color(1, 1, 1, 0.9), 6.0, true)
	_bar.draw_polyline(top, Color(_select_col, 0.85), 3.0, true)

func _bar_y(x: float, w: float) -> float:
	var d := minf(x, w - x)  # distance from the nearest side
	var k := 1.0 - smoothstep(BTN_X + BTN_R * 0.4, BTN_X + BTN_R * 2.6, d)
	return BAR_TOP - BAR_RISE * k

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_clock_t += delta
	if _clock_t >= 1.0:
		_clock_t = 0.0
		_clock.text = Settings.clock_text()
		var d := Time.get_datetime_dict_from_system()
		_date.text = "%s %d/%d" % [DAYS[int(d["weekday"])], d["month"], d["day"]]
	# The Home page (Today / Performance) slides its tabs up under the clock: the date and the grid's
	# Play / Options buttons fade away meanwhile, so nothing sits on top of the tabs.
	var on_page: bool = home.in_details
	var want := 0.0 if on_page else 1.0
	_date.modulate.a = move_toward(_date.modulate.a, want, delta * 5.0)
	# The control center has its own hints in the same place: these go while it is open.
	var hint_want := 0.0 if on_page or (home.cc != null and home.cc.is_open) else 1.0
	_hints.modulate.a = move_toward(_hints.modulate.a, hint_want, delta * 8.0)
	# The focus frame breathes gently.
	if _focus == "grid" and _page < _frames.size():
		var fsb: StyleBoxFlat = _frames[_page][_sel]
		fsb.border_color = Color(_select_col, 0.75 + 0.25 * sin(_t * 4.0))
	var pages := _pages.size()
	var bob := 6.0 * sin(_t * 3.0)
	_arrow_l.visible = _page > 0
	_arrow_r.visible = _page < pages - 1
	_arrow_l.position.x = 26 - bob
	_arrow_r.position.x = size.x - 26 - _arrow_r.size.x + bob

# ---------- Focus ----------
func _current() -> Dictionary:
	var i := _page * PER_PAGE + _sel
	return _items[i] if _focus == "grid" and i < _items.size() else {}

## The focused channel's index in home.games (-1 for an empty channel, a game that isn't
## installed, or a round button). home.gd uses it for Triangle (the game menu) and launching.
func selected_gi() -> int:
	return int(_current().get("gi", -1))

func _highlight(animate: bool) -> void:
	for p in _tiles.size():
		for k in PER_PAGE:
			var on := _focus == "grid" and p == _page and k == _sel
			var t: Control = _tiles[p][k]
			(_frames[p][k] as StyleBoxFlat).set_border_width_all(6 if on else 0)
			t.z_index = 1 if on else 0
			if animate and p == _page:
				Motion.scale_to(t, 1.07 if on else 1.0, 0.16)
			else:
				t.scale = Vector2.ONE * (1.07 if on else 1.0)
	for b in [_btn_info, _btn_set]:
		var on: bool = (_focus == "info" and b == _btn_info) or (_focus == "settings" and b == _btn_set)
		b.set_meta("on", on)
		b.queue_redraw()
		if animate:
			Motion.scale_to(b, 1.1 if on else 1.0, 0.16)
		else:
			b.scale = Vector2.ONE * (1.1 if on else 1.0)
	var cur := _current()
	if _focus == "info":
		_name.text = "Home"
	elif _focus == "settings":
		_name.text = "Settings"
	else:
		_name.text = str(cur.get("title", ""))
	var pages := _pages.size()
	if pages > 1 and _focus == "grid":
		_name.text += ("   ·   " if _name.text != "" else "") + "Page %d of %d" % [_page + 1, pages]

func _go_page(p: int, keep_col := -1) -> void:
	var pages := _pages.size()
	if p < 0 or p >= pages or p == _page:
		return
	_page = p
	if keep_col >= 0:
		_sel = (_sel / COLS) * COLS + keep_col
	if _slide != null and _slide.is_running():
		_slide.kill()
	_slide = create_tween()
	_slide.tween_property(_strip, "position:x", -_page * size.x, Motion.dur(0.32)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	home.sfx.play("page")
	Haptics.select()
	_update_tag()

## "Library" shows in the corner on the pages that are the Library, not Home.
func _update_tag() -> void:
	if _tag != null:
		Motion.fade_to(_tag, 1.0 if _page >= _lib_page0 else 0.0, 0.25)

## D-pad / stick. Returns "up" when Up leaves the top row (home.gd then goes to the top bar).
func move(dir: Vector2i) -> String:
	if _focus != "grid":
		if dir.x != 0:
			_focus = "settings" if _focus == "info" else "info"
		elif dir.y < 0:
			_sel = (ROWS - 1) * COLS + (0 if _focus == "info" else COLS - 1)
			_focus = "grid"
		_highlight(true)
		return ""
	var col := _sel % COLS
	var row := _sel / COLS
	if dir.x != 0:
		var nc := col + dir.x
		if nc < 0:
			if _pages.size() > 1:
				_go_page(posmod(_page - 1, _pages.size()), COLS - 1)  # first page: round to the last
			else:
				_sel = row * COLS + COLS - 1
		elif nc >= COLS:
			if _pages.size() > 1:
				_go_page(posmod(_page + 1, _pages.size()), 0)
			else:
				_sel = row * COLS
		else:
			_sel = row * COLS + nc
	elif dir.y < 0:
		if row == 0:
			return "up"
		_sel -= COLS
	elif dir.y > 0:
		if row == ROWS - 1:
			_focus = "info" if col < COLS / 2 else "settings"
		else:
			_sel += COLS
	_highlight(true)
	return ""

## The top bar column above the focused channel (so Up lands near where you were).
func top_column() -> float:
	return float(_sel % COLS) / float(COLS - 1)

var _rstick_latched := false  # the right stick flips one page per push

## A, L1 / R1, and the right stick (push left or right to flip a whole page). Returns true when used.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_RIGHT_X:
		var v: float = event.axis_value
		if _rstick_latched:
			if absf(v) < 0.3:
				_rstick_latched = false  # back near the middle: ready for the next push
		elif absf(v) > 0.6:
			_rstick_latched = true
			_focus = "grid"
			_go_page(_page + (1 if v > 0.0 else -1))
			_highlight(true)
		return true
	var l1: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_LEFT_SHOULDER) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q and not event.ctrl_pressed)
	var r1: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_SHOULDER) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E)
	if l1 or r1:
		if _focus != "grid":
			_focus = "grid"
		_go_page(posmod(_page + (1 if r1 else -1), maxi(_pages.size(), 1)))  # round the ends
		_highlight(true)
		return true
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		_activate()
		return true
	return false

func _activate() -> void:
	if _focus == "settings":
		await _press(_btn_set)
		home.settings_screen.open(home.clock_label.get_global_rect())
		return
	if _focus == "info":
		await _press(_btn_info)
		home.open_home_page()
		return
	var it := _current()
	if it.is_empty():
		return
	var t: Control = _tiles[_page][_sel]
	await _press(t)
	if int(it["gi"]) >= 0:
		home.play_or_info(int(it["gi"]))
	else:
		_open_info(it)  # not installed: its page has the Install button

## A little squeeze and spring, so a press is felt before anything opens.
func _press(c: Control) -> void:
	var rest := c.scale.x
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * rest * 0.94, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE * rest, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished

## Triangle: the focused channel's page (the same one A opens in the Library), installed or not.
func info_selected() -> void:
	var it := _current()
	if it.is_empty():
		return
	home.sfx.play("options")
	if _focus == "grid" and _page < _tiles.size() and _sel < _tiles[_page].size():
		await _press(_tiles[_page][_sel])  # the same click as starting a game
	_open_info(it)

func _open_info(it: Dictionary) -> void:
	if it.is_empty():
		home._open_profile()
		return
	var g: Dictionary = it["g"]
	var cover: Texture2D = null
	var p := _page * PER_PAGE + _sel
	if _focus == "grid" and p < _items.size():
		var pic := _tiles[_page][_sel].get_child(2) as TextureRect if _tiles[_page][_sel].get_child_count() > 2 else null
		if pic != null:
			cover = pic.texture
	home.library.open_game(g, cover)

## The top bar took the focus (true) or gave it back (false).
func dim(on: bool) -> void:
	Motion.fade_to(_strip, 0.25 if on else 1.0, 0.25)
	if on:
		_focus = "grid"
	for f in _frames[_page] if _page < _frames.size() else []:
		(f as StyleBoxFlat).set_border_width_all(0)
	if not on:
		_highlight(false)
