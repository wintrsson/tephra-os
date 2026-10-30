extends Control
## The PS2 theme's Home. All original drawing; it only borrows the feeling of an old console's start-up menus.
##
##   Menu     black, a ring of glowing dots on the left that slides to the chosen word, the menu words
##            centred on the right (Games, Library, Controllers, Wi-Fi, Settings, Info). The selected word
##            is blue, the others grey. The top bar's Wi-Fi, controller and settings icons are hidden:
##            these words are where they live now.
##   Home     a "memory card" style browser: your Home games first, then a divider, then the rest of the
##            Library, as small 3D game cases turning in a grid, the focused one lit from below and turning, its name in yellow
##            top right, a blue arrow when there are more rows. A / B / Triangle hints along the bottom.
##
## The cases are drawn by hand (a box turned in 3D and flattened, the cover stretched on its front), so
## there are no 3D scenes to load. home.gd hands its input here (the same hooks as channels.gd).

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const TephraGlyphs = preload("res://glyphs.gd")

const MENU := ["Home", "PS2 Games", "Controllers", "Wi-Fi", "Bluetooth", "Settings", "Info"]
const MENU_FONT := 56
const MENU_CX := 1280.0     # the words are centred on this x
const MENU_W := 640.0
const MENU_TOP := 350.0
const MENU_STEP := 76.0
const RING_X := 790.0
const RING_R := 84.0
const COLS := 5
const ROWS := 2
const CELL := Vector2(300, 330)
const GRID_TOP := 250.0
const CASE_H := 268.0

var home  # home.gd

var _state := "menu"        # "menu" or "games" (the Home browser)
var _mi := 0                # menu item
var _items: Array = []      # {id, title, gi, g} per game: the Home games, empty slots up to a whole row, then the rest of the Library
var _home_n := 0            # how many Home games there are
var _sep_at := 0            # index of the first Library game (the divider row sits just before it)
var _has_lib := false       # is there a Library part (and so a divider)?
var _mem := Vector2i.ZERO   # where you were in the browser: focused game and first row
var _sel := 0               # focused game
var _row0 := 0              # first row shown
var _art := {}              # game id -> {tex, portrait}
var _asked := {}            # game ids whose cover is being loaded
var _ring_y := 540.0        # the ring stays put in the middle and just spins
var _foc := PackedFloat32Array()  # 0..1 per game: how much it is the focused one (eased, so changes glide)
var _ang := PackedFloat32Array() # each case's turn
var _row_f := 0.0           # the scrolled row, eased
var _pulse := 0.0           # the focused case squeezes when pressed
var _holders: Array = []    # hidden TextureRects the art is loaded into
var _labels: Array = []
var _menu_view: Control
var _games_view: Control
var _grid: Control
var _fx: Control
var _backdrop: TextureRect
var _tint: TextureRect
var _tint_c := Color(0.2, 0.25, 0.4)   # the colour showing now, easing towards the focused game's
var _hints: HBoxContainer
var _title_l: Label
var _sub_l: Label
var _name_l: Label
var _num_l: Label
var _empty_l: Label
var _hint_l: HBoxContainer
var _hint_r: HBoxContainer
var _glow: GradientTexture2D
var _font: Font
var _t := 0.0
var _select_col := Color("38C4F4")
var _yellow := Color("F2E24A")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_font = Themes.font("ps2")
	if _font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Helvetica Neue", "Helvetica", "Arial", "Liberation Sans", "DejaVu Sans"])
		_font = sf
	var gg := Gradient.new()
	gg.offsets = PackedFloat32Array([0.0, 1.0])
	gg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = gg
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 256
	_glow.height = 256
	# The menu: ring of dots, orbiting glass cubes, the words.
	_menu_view = _blank()
	_fx = _blank()
	_fx.draw.connect(_draw_menu_fx)
	_menu_view.add_child(_fx)
	for i in MENU.size():
		var l := _label(MENU[i], MENU_FONT, Color(0.62, 0.62, 0.64))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(MENU_CX - MENU_W / 2.0, MENU_TOP + i * MENU_STEP)
		l.size = Vector2(MENU_W, MENU_STEP)
		_menu_view.add_child(l)
		_labels.append(l)
	_hint_l = HBoxContainer.new()  # one centred bar under the words, both glyphs together
	_hint_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_l.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint_l.add_theme_constant_override("separation", 60)
	_hint_l.position = Vector2(MENU_CX - 600, 1230)
	_hint_l.size = Vector2(1200, 60)
	_menu_view.add_child(_hint_l)
	_hint_r = null
	TephraGlyphs.fill(_hint_l, [["accept", "Select"], ["dpad_v", "Navigate"]], 28)
	# The games browser.
	_games_view = _blank()
	_games_view.visible = false
	_games_view.modulate.a = 0.0
	add_child(_games_view)
	_backdrop = TextureRect.new()
	var bg := Gradient.new()
	bg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	bg.colors = PackedColorArray([Color(0.24, 0.24, 0.27), Color(0.09, 0.09, 0.11), Color(0.0, 0.0, 0.0)])
	var bt := GradientTexture2D.new()
	bt.gradient = bg
	bt.fill = GradientTexture2D.FILL_RADIAL
	bt.fill_from = Vector2(0.5, 0.42)
	bt.fill_to = Vector2(1.05, 1.0)
	bt.width = 512
	bt.height = 288
	_backdrop.texture = bt
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_games_view.add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A wash of the focused game's main colour over the backdrop (eased in _process).
	_tint = TextureRect.new()
	_tint.texture = _glow
	_tint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tint.stretch_mode = TextureRect.STRETCH_SCALE
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.modulate = Color(0.2, 0.25, 0.4, 0.0)
	_games_view.add_child(_tint)
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid = _blank()
	_grid.draw.connect(_draw_grid)
	_games_view.add_child(_grid)
	_title_l = _label("Games", 58, Color(1, 1, 1))
	_title_l.position = Vector2(150, 150)
	_games_view.add_child(_title_l)
	_sub_l = _label("", 32, Color(1, 1, 1, 0.85))
	_sub_l.position = Vector2(150, 214)
	_games_view.add_child(_sub_l)
	_num_l = _label("", 58, _yellow)
	_num_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_num_l.position = Vector2(1000, 150)
	_num_l.size = Vector2(770, 70)
	_games_view.add_child(_num_l)
	_name_l = _label("", 50, _yellow)
	_name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name_l.position = Vector2(900, 214)
	_name_l.size = Vector2(870, 64)
	_name_l.clip_text = true
	_games_view.add_child(_name_l)
	_empty_l = _label("No games on Home yet. Pin some from the Library.", 40, Color(1, 1, 1, 0.8))
	_empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_l.position = Vector2(0, 520)
	_empty_l.size = Vector2(1920, 60)
	_games_view.add_child(_empty_l)
	_hints = HBoxContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_hints.position = Vector2(MENU_CX - 600, 1230)
	_hints.size = Vector2(1200, 60)
	_games_view.add_child(_hints)
	add_child(_menu_view)
	move_child(_menu_view, 0)
	rebuild()
	_highlight()

func _blank() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---------- Building ----------
## Re-reads the games: Home games first, then a divider, then the rest of the Library. Keeps the same game focused.
var _only_ps2 := false  # the "PS2 Games" tab shows only the emulated games

## A game's cover changed (PS2 Original / Remake art): load it again.
func forget_art(id: String) -> void:
	_art.erase(id)
	_asked.erase(id)

func rebuild() -> void:
	var keep := ""
	if _sel < _items.size() and not _items[_sel].is_empty():
		keep = str(_items[_sel]["id"])
	_items.clear()
	var seen := {}
	if _only_ps2:
		for g in home.library.all_games():
			if not g.get("ps2", false):
				continue
			var id2 := str(g["id"])
			var gi2 := -1
			for i in home.games.size():
				if str(home.games[i]["id"]) == id2:
					gi2 = i
					break
			_items.append({"id": id2, "title": str(g["title"]), "gi": gi2, "g": g})
		_home_n = 0
		_sep_at = 0
		_has_lib = false
		_sel = 0
		for i in _items.size():
			if keep != "" and str(_items[i]["id"]) == keep:
				_sel = i
		_row0 = clampi(_row_of(_sel) - ROWS + 1, 0, maxi(_rows() - ROWS, 0)) if _row_of(_sel) >= ROWS else 0
		_update_texts()
		return
	for i in home.games.size():
		var g: Dictionary = home.games[i]
		if home.on_home(g):
			_items.append({"id": str(g["id"]), "title": str(g["title"]), "gi": i, "g": g})
			seen[str(g["id"])] = true
	_home_n = _items.size()
	while _items.size() % COLS != 0:
		_items.append({})  # empty slots finish the Home row, so the Library starts on a fresh row
	_sep_at = _items.size()
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
		_items.append({"id": id, "title": str(g["title"]), "gi": gi, "g": g})
	_has_lib = _items.size() > _sep_at
	_sel = _first_real()
	for i in _items.size():
		if keep != "" and not _items[i].is_empty() and str(_items[i]["id"]) == keep:
			_sel = i
	_row0 = clampi(_row_of(_sel) - ROWS + 1, 0, maxi(_rows() - ROWS, 0)) if _row_of(_sel) >= ROWS else 0
	_update_texts()

func _first_real() -> int:
	for i in _items.size():
		if not _items[i].is_empty():
			return i
	return 0

## The display row a game sits on (the divider takes a row of its own between Home and the Library).
func _row_of(k: int) -> int:
	return k / COLS + (1 if _has_lib and k >= _sep_at else 0)

func _div_row() -> int:
	return _sep_at / COLS

## Makes the focused game's row visible (and the divider above the first Library row, so you see the separation).
func _scroll_to_sel() -> void:
	var r := _row_of(_sel)
	if r < _row0:
		_row0 = r
	elif r >= _row0 + ROWS:
		_row0 = r - ROWS + 1
	if _has_lib and r == _div_row() + 1 and _row0 > _div_row():
		_row0 = _div_row()
	_row0 = clampi(_row0, 0, maxi(_rows() - ROWS, 0))

## The tall cover; a game without one falls back to its wide header picture (cropped to fit).
## Only asked for when its row is about to show, so a big Library does not load all at once.
func _load_cover(id: String) -> void:
	if _art.has(id) or _asked.has(id):
		return
	_asked[id] = true
	var pic := TextureRect.new()
	pic.visible = false
	add_child(pic)
	_holders.append(pic)
	home._load_art(id, "library_600x900", pic, "jpg", func() -> void:
		if is_instance_valid(pic):
			_art[id] = {"tex": pic.texture, "portrait": true, "col": _main_color(pic.texture)}, func() -> void:
		if is_instance_valid(pic):
			home._load_art(id, "header", pic, "jpg", func() -> void:
				if is_instance_valid(pic):
					_art[id] = {"tex": pic.texture, "portrait": false, "col": _main_color(pic.texture)}))

## The cover's main colour: the average of its more colourful pixels, a little deepened, for the case's plastic.
func _main_color(tex: Texture2D) -> Color:
	if tex == null:
		return Color(0.2, 0.25, 0.4)
	var img := tex.get_image()
	if img == null or img.is_empty():
		return Color(0.2, 0.25, 0.4)
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	# The colour covering the MOST of the cover wins, by area (not by how bright or vivid it is): Silent Hill 2's
	# pale green art beats its small, very red banner. Greys and near-black don't count.
	var sums: Array = []
	var weights: Array = []
	for i in 12:
		sums.append(Color(0, 0, 0))
		weights.append(0.0)
	var grey := Color(0, 0, 0)
	var gw := 0.0
	for y in 32:
		for x in 32:
			var c := img.get_pixel(x, y)
			if c.s < 0.1 or c.v < 0.12:
				grey += Color(c.r, c.g, c.b)
				gw += 1.0
				continue
			var wt := 0.75 + 0.25 * c.s
			var bin := mini(int(c.h * 12.0), 11)
			sums[bin] += Color(c.r * wt, c.g * wt, c.b * wt)
			weights[bin] += wt
	var best := -1
	var best_w := 0.0
	for i in 12:
		var near: float = float(weights[i]) + 0.5 * (float(weights[(i + 1) % 12]) + float(weights[(i + 11) % 12]))  # neighbours help a hue
		if near > best_w:
			best_w = near
			best = i
	if best < 0 or float(weights[best]) < 40.0:  # under ~4% of the cover in colour: a grey or black cover
		return Color(0.25, 0.27, 0.33) if gw <= 0.0 else Color(grey.r / gw, grey.g / gw, grey.b / gw).lerp(Color(0.25, 0.27, 0.33), 0.5)
	var w: float = weights[best]
	var m := Color(sums[best].r / w, sums[best].g / w, sums[best].b / w)
	return Color.from_hsv(m.h, clampf(maxf(m.s * 1.3, 0.55), 0.0, 0.9), clampf(m.v, 0.4, 0.85))

func _rows() -> int:
	return maxi(ceili(_items.size() / float(COLS)) + (1 if _has_lib else 0), 1)

func _update_texts() -> void:
	_title_l.text = "PS2 Games" if _only_ps2 else "Home"
	if _only_ps2:
		_sub_l.text = "%d PS2 game%s" % [_items.size(), "" if _items.size() == 1 else "s"]
		_empty_l.text = "No PS2 games yet. Put disc images in ~/Games/PS2."
	else:
		_sub_l.text = "%d game%s on Home" % [_home_n, "" if _home_n == 1 else "s"]
		_empty_l.text = "No games on Home yet. Pin some from the Library."
	_empty_l.visible = _items.is_empty()
	if _sel < _items.size() and not _items[_sel].is_empty():
		var real := 0
		var total := 0
		for i in _items.size():
			if not _items[i].is_empty():
				total += 1
				if i <= _sel:
					real += 1
		_num_l.text = "%d / %d" % [real, total]
		_name_l.text = str(_items[_sel]["title"])
	else:
		_num_l.text = ""
		_name_l.text = ""

# ---------- Drawing ----------
func _process(delta: float) -> void:
	if not is_visible_in_tree() or home.library.is_open:
		return  # nothing is redrawn while a game page is open over this (that is what cost frames)
	_t += delta
	if _foc.size() != _items.size():
		_foc.resize(_items.size())
		_ang.resize(_items.size())
		for k in _items.size():
			_foc[k] = 1.0 if k == _sel else 0.0
			_ang[k] = -0.5
		_row_f = float(_row0)
	var ease_k := 1.0 - exp(-delta * 9.0)
	for k in _items.size():
		_foc[k] = lerpf(_foc[k], 1.0 if k == _sel else 0.0, ease_k)
		var f: float = _foc[k]
		_ang[k] += 1.1 * f * delta  # turns while focused,
		_ang[k] = lerp_angle(_ang[k], -0.5, (1.0 - f) * ease_k * 0.9)  # and eases back to its rest angle when let go
	_row_f = lerpf(_row_f, float(_row0), 1.0 - exp(-delta * 8.0))
	if _state != "menu":
		var want := Color(0.2, 0.25, 0.4)
		if _sel < _items.size() and not _items[_sel].is_empty():
			want = (_art.get(str(_items[_sel]["id"]), {}) as Dictionary).get("col", want)
		_tint_c = _tint_c.lerp(want, 1.0 - exp(-delta * 3.0))
		_tint.modulate = Color(_tint_c.r, _tint_c.g, _tint_c.b, 0.75)
	if _state == "menu":
		_fx.queue_redraw()
	else:
		_grid.queue_redraw()

## Where the middle of menu word `i` is.
func _word_y(i: int) -> float:
	return MENU_TOP + i * MENU_STEP + MENU_STEP / 2.0

## The menu's ring of eight dots, each a bright white core in a blue halo that swells and fades in turn,
## with faint threads of light falling from them. It stays in the middle and just spins.
func _draw_menu_fx() -> void:
	# A ring of eight bright dots that tumbles slowly in 3D: now a full circle, now tipped over into an
	# ellipse, now edge-on as a glowing line, turning and flipping as it goes. A soft blue glow
	# sweeps round it, swelling the dots it passes.
	var rc := Vector2(RING_X, _ring_y)
	var r := RING_R * 1.35
	var ax := 0.9 + 1.1 * sin(_t * 0.42)           # tip towards / away from the viewer
	var ay := 0.8 * sin(_t * 0.31 + 1.0)           # lean to the side
	var az := _t * 0.3                              # spin in the plane of the screen
	var head := _t * 2.6                            # where the sweeping glow is, on the ring
	var pts: Array = []
	for i in 8:
		var a := TAU * i / 8.0 + _t * 0.5
		var v := Vector3(cos(a), sin(a), 0.0)
		# turn about X, then Y, then Z
		var y1 := v.y * cos(ax) - v.z * sin(ax)
		var z1 := v.y * sin(ax) + v.z * cos(ax)
		var x2 := v.x * cos(ay) + z1 * sin(ay)
		var z2 := -v.x * sin(ay) + z1 * cos(ay)
		var x3 := x2 * cos(az) - y1 * sin(az)
		var y3 := x2 * sin(az) + y1 * cos(az)
		var d := absf(wrapf(a - head, -PI, PI))
		var bump := exp(-pow(d / 0.85, 2.0))
		pts.append({"p": rc + Vector2(x3, y3) * r, "z": z2, "bump": bump})
	pts.sort_custom(func(m, n): return m["z"] < n["z"])  # far dots first
	for q in pts:
		var p0: Vector2 = q["p"]
		var near := 0.5 + 0.5 * float(q["z"])  # 0 far .. 1 near
		var k: float = (0.3 + 0.7 * float(q["bump"])) * (0.6 + 0.4 * near)
		var s := 0.8 + 0.4 * near
		_fx.draw_texture_rect(_glow, Rect2(p0 - Vector2(110, 110) * s, Vector2(220, 220) * s), false, Color(0.2, 0.55, 1.0, 0.55 * k))
		_fx.draw_texture_rect(_glow, Rect2(p0 - Vector2(60, 60) * s, Vector2(120, 120) * s), false, Color(0.45, 0.8, 1.0, 0.8 * k))
		_fx.draw_circle(p0, 8.0 * s, Color(1, 1, 1, 0.55 + 0.45 * near))

## The grid of cases, `ROWS` rows at a time. The focused one turns slowly and has a pool of light under it.
func _draw_grid() -> void:
	var left := (size.x - COLS * CELL.x) / 2.0
	for k in _items.size():
		if not _items[k].is_empty() and _row_of(k) == _row0 + ROWS:
			_load_cover(str(_items[k]["id"]))  # the next row, so it is ready when you scroll
	if _has_lib:
		var dy := float(_div_row()) - _row_f
		if dy > -1.0 and dy < ROWS:
			# The divider between Home and the Library: a label and a fine line.
			var dc := GRID_TOP + dy * CELL.y + CELL.y / 2.0 + 10.0
			var da := clampf(minf(dy + 1.0, ROWS - dy), 0.0, 1.0)
			_grid.draw_string(_font, Vector2(left + 24.0, dc + 14.0), "Library", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(1, 1, 1, 0.9 * da))
			var tw := _font.get_string_size("Library", HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
			_grid.draw_line(Vector2(left + 24.0 + tw + 24.0, dc), Vector2(left + COLS * CELL.x - 24.0, dc), Color(0.5, 0.75, 1.0, 0.55 * da), 2.0, true)
	for k in _items.size():
		if _items[k].is_empty():
			continue
		var row_f := float(_row_of(k)) - _row_f
		if row_f < -1.0 or row_f > ROWS:
			continue
		var c := Vector2(left + (k % COLS) * CELL.x + CELL.x / 2.0, GRID_TOP + row_f * CELL.y + CELL.y / 2.0 + 10.0)
		var foc: float = _foc[k] if k < _foc.size() else 0.0
		_load_cover(str(_items[k]["id"]))
		var art: Dictionary = _art.get(str(_items[k]["id"]), {})
		var yaw: float = (_ang[k] if k < _ang.size() else -0.5) + 0.05 * sin(_t * 0.7 + k) * (1.0 - foc)
		var h := CASE_H * (1.0 + 0.12 * foc) * (1.0 - 0.07 * _pulse * foc)
		var edge := clampf(minf(row_f + 1.0, ROWS - row_f), 0.0, 1.0)  # fades while it scrolls in or out
		if foc > 0.01:
			# The light under the focused case.
			var lit: Color = _tint_c.lerp(Color.WHITE, 0.45)  # the light takes the cover's colour
			_grid.draw_texture_rect(_glow, Rect2(c + Vector2(-190, h * 0.28), Vector2(380, 140)), false, Color(lit.r, lit.g, lit.b, 0.8 * foc * edge))
			_grid.draw_texture_rect(_glow, Rect2(c + Vector2(-120, -h * 0.5), Vector2(240, h)), false, Color(lit.r, lit.g, lit.b, 0.12 * foc * edge))
		_draw_case(c, h, yaw, art, foc, edge)
	# Arrows: more rows above or below.
	if _row0 > 0:
		_grid.draw_colored_polygon(PackedVector2Array([Vector2(930, 232), Vector2(990, 232), Vector2(960, 206)]), Color(0.25, 0.4, 0.95))
	if _row0 + ROWS < _rows():
		_grid.draw_colored_polygon(PackedVector2Array([Vector2(930, 928), Vector2(990, 928), Vector2(960, 956)]), Color(0.25, 0.4, 0.95))

## One game case: a flat box (cover on the front, plain spine and back).
func _draw_case(c: Vector2, h: float, yaw: float, art: Dictionary, foc: float, edge := 1.0) -> void:
	var tex: Texture2D = art.get("tex", null)
	var portrait: bool = art.get("portrait", true)
	var plastic: Color = art.get("col", Color(0.2, 0.25, 0.4))
	_draw_box(_grid, c, h * 0.34, h * 0.5, h * 0.07, yaw, 0.18, tex, portrait, (0.82 + 0.18 * foc) * (0.25 + 0.75 * edge), 0.0, plastic)

## A box turned `yaw` about its upright axis and tipped `tilt` towards the viewer, flattened onto the screen
## (no perspective, which suits something this small). a, b, d are half the width, height and depth. With a
## texture, the front face wears it (the back and sides are plain); without one the box is clear glass.
func _draw_box(canvas: Control, c: Vector2, a: float, b: float, d: float, yaw: float, tilt: float, tex: Texture2D, portrait: bool, bright: float, glass_alpha := 0.0, plastic := Color(0.16, 0.18, 0.26)) -> void:
	var sy := sin(yaw)
	var cy := cos(yaw)
	var st := sin(tilt)
	var ct := cos(tilt)
	var is_glass := tex == null
	if is_glass:
		glass_alpha = bright
	# The eight corners, turned and flattened.
	var pts := {}
	for sx in [-1, 1]:
		for sy2 in [-1, 1]:
			for sz in [-1, 1]:
				var x: float = sx * a
				var y: float = sy2 * b
				var z: float = sz * d
				var x1 := x * cy + z * sy
				var z1 := -x * sy + z * cy
				var y2 := y * ct - z1 * st
				var z2 := y * st + z1 * ct
				pts[Vector3i(sx, sy2, sz)] = Vector3(c.x + x1, c.y + y2, z2)
	# Faces: corner order round the face, its outward direction, and its colour.
	var faces := [
		[[Vector3i(-1, -1, 1), Vector3i(1, -1, 1), Vector3i(1, 1, 1), Vector3i(-1, 1, 1)], Vector3(0, 0, 1), "front"],
		[[Vector3i(1, -1, -1), Vector3i(-1, -1, -1), Vector3i(-1, 1, -1), Vector3i(1, 1, -1)], Vector3(0, 0, -1), "back"],
		[[Vector3i(1, -1, 1), Vector3i(1, -1, -1), Vector3i(1, 1, -1), Vector3i(1, 1, 1)], Vector3(1, 0, 0), "side"],
		[[Vector3i(-1, -1, -1), Vector3i(-1, -1, 1), Vector3i(-1, 1, 1), Vector3i(-1, 1, -1)], Vector3(-1, 0, 0), "side"],
		[[Vector3i(-1, -1, -1), Vector3i(1, -1, -1), Vector3i(1, -1, 1), Vector3i(-1, -1, 1)], Vector3(0, -1, 0), "top"],
		[[Vector3i(-1, 1, 1), Vector3i(1, 1, 1), Vector3i(1, 1, -1), Vector3i(-1, 1, -1)], Vector3(0, 1, 0), "bottom"],
	]
	var order: Array = []
	for f in faces:
		var n: Vector3 = f[1]
		# Turn the outward direction the same way as the corners, to see which way it faces.
		var nx := n.x * cy + n.z * sy
		var nz1 := -n.x * sy + n.z * cy
		var ny := n.y * ct - nz1 * st
		var nz := n.y * st + nz1 * ct
		if nz <= 0.02:
			continue  # facing away
		order.append([f, nz, Vector3(nx, ny, nz)])
	order.sort_custom(func(p, q): return p[1] < q[1])
	for o in order:
		var f: Array = o[0]
		var nz: float = o[1]
		var poly := PackedVector2Array()
		for k in f[0]:
			var v: Vector3 = pts[k]
			poly.append(Vector2(v.x, v.y))
		var kind: String = f[2]
		var shade := clampf(0.55 + 0.45 * nz, 0.0, 1.0) * bright
		if is_glass:
			var col := Color(0.55, 0.75, 1.0, glass_alpha * (0.35 if kind == "top" else 0.22))
			canvas.draw_colored_polygon(poly, col)
			var edge := poly.duplicate()
			edge.append(poly[0])
			canvas.draw_polyline(edge, Color(0.8, 0.92, 1.0, glass_alpha * 0.9), 1.6, true)
			continue
		if (kind == "front" or kind == "back") and tex != null:
			var u0 := 0.0
			var u1 := 1.0
			var v0 := 0.0
			var v1 := 1.0
			if not portrait:
				var ar := tex.get_size().x / maxf(tex.get_size().y, 1.0)
				var want := 0.68
				var uw := clampf(want / ar, 0.05, 1.0)
				u0 = 0.5 - uw / 2.0
				u1 = 0.5 + uw / 2.0
			var uvs := PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
			var cols := PackedColorArray([Color(shade, shade, shade), Color(shade, shade, shade), Color(shade, shade, shade), Color(shade, shade, shade)])
			canvas.draw_polygon(poly, cols, uvs, tex)
		else:
			# The case's plastic wears the cover's main colour: lighter on the top and bottom, deeper on the sides.
			var base := plastic.darkened(0.55)
			if kind == "top" or kind == "bottom":
				base = plastic.lightened(0.1)
			elif kind == "side":
				base = plastic.darkened(0.25)
			canvas.draw_colored_polygon(poly, Color(base.r * shade, base.g * shade, base.b * shade))
		var ring := poly.duplicate()
		ring.append(poly[0])
		canvas.draw_polyline(ring, Color(1, 1, 1, 0.28 * bright), 1.5, true)

# ---------- Focus ----------
## The focused game's index in home.games (-1 in the menu).
func selected_gi() -> int:
	return int(_items[_sel]["gi"]) if _state != "menu" and _sel < _items.size() and not _items[_sel].is_empty() else -1

## The top bar column above the focus (the menu sits in the middle).
func top_column() -> float:
	return 0.5

func _highlight() -> void:
	for i in _labels.size():
		(_labels[i] as Label).add_theme_color_override("font_color", _select_col if i == _mi else Color(0.62, 0.62, 0.64))
	_update_texts()
	_grid.queue_redraw()
	_fx.queue_redraw()

func _step_menu(to: int) -> void:
	if to == _mi:
		return
	_mi = to
	_highlight()

## D-pad / stick. Returns "up" when Up leaves the top (home.gd then goes to the top bar).
func move(dir: Vector2i) -> String:
	if _state == "menu":
		if dir.y < 0:
			if _mi == 0:
				return "up"
			_step_menu(_mi - 1)
		elif dir.y > 0:
			_step_menu((_mi + 1) % MENU.size())  # past the last word: round to the first
		return ""
	if _items.is_empty():
		return "up" if dir.y < 0 else ""
	if dir.x != 0:
		var k := _sel + dir.x
		while k >= 0 and k < _items.size() and _items[k].is_empty():
			k += dir.x
		if k >= 0 and k < _items.size() and k / COLS == _sel / COLS:
			_sel = k
		else:
			# off the end of the row: round to the other end (the last real game of a short row)
			var rs := (_sel / COLS) * COLS
			var re := mini(rs + COLS, _items.size()) - 1
			k = rs if dir.x > 0 else re
			while k >= rs and k <= re and _items[k].is_empty():
				k += 1 if dir.x > 0 else -1
			if k >= rs and k <= re:
				_sel = k
	elif dir.y < 0:
		var t := _sel - COLS
		if t < 0:
			return "up"  # nothing above: on to the top bar
		if _items[t].is_empty():
			t = _real_in_row(t / COLS, t)
			if t < 0:
				return "up"
		_sel = t
	elif dir.y > 0:
		var t := _sel + COLS
		if t >= _items.size():
			var last := _items.size() - 1
			if last / COLS > _sel / COLS:
				t = last  # the last row is short: land on its last game
			else:
				t = _sel % COLS  # past the bottom: round to the top, same column
		if _items[t].is_empty():
			t = _real_in_row(t / COLS, t)
			if t < 0:
				return ""
		_sel = t
	_scroll_to_sel()
	_highlight()
	return ""

## A game in the same row as index `at`, looking left from it (rows can end in empty slots). -1 if none.
func _real_in_row(row_idx: int, at: int) -> int:
	var rs := row_idx * COLS
	for k in range(mini(at, _items.size() - 1), rs - 1, -1):
		if not _items[k].is_empty():
			return k
	return -1

func handle_input(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return true
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and _state != "menu":
		_show("menu")
		return true
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		_activate()
		return true
	return false

## The focused case squeezes and springs back, like a tile being pressed in the other themes.
func _press() -> void:
	_pulse = 0.0
	var tw := create_tween()
	tw.tween_property(self, "_pulse", 1.0, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "_pulse", 0.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished

func _activate() -> void:
	if _state != "menu":
		if _sel < _items.size() and not _items[_sel].is_empty():
			await _press()
			var it: Dictionary = _items[_sel]
			if int(it["gi"]) >= 0:
				home.play_or_info(int(it["gi"]))
			else:
				info_selected(false)  # not installed: its page has the Install button
		return
	var r: Rect2 = home.clock_label.get_global_rect()
	match MENU[_mi]:
		"Home":
			_only_ps2 = false
			rebuild()
			_show("games")
		"PS2 Games":
			_only_ps2 = true
			rebuild()
			_show("games")
		"Controllers":
			home.top_menu.open_menu("pad", home.pad_wrap.get_global_rect())
		"Wi-Fi":
			home.top_menu.open_menu("wifi", home.wifi_icon.get_global_rect())
		"Bluetooth":
			home.top_menu.open_menu("bt", home.bt_icon.get_global_rect())
		"Settings":
			home.settings_screen.open(r)
		"Info":
			home.settings_screen.open_info(r)

## Switches between the menu and a browser (Games or Library) with a short cross-fade.
func _show(state: String) -> void:
	_foc.resize(0)  # the focus easing starts afresh for the list now shown
	if _state != "menu":
		_mem = Vector2i(_sel, _row0)  # the browser remembers where you were
	_state = state
	home.sfx.play("open")
	Haptics.select()
	if state != "menu":
		_sel = clampi(_mem.x, 0, maxi(_items.size() - 1, 0))
		if not _items.is_empty() and _items[_sel].is_empty():
			_sel = _first_real()
		_row0 = clampi(_mem.y, 0, maxi(_rows() - ROWS, 0))
		_games_view.visible = true
		TephraGlyphs.fill(_hints, [["accept", "Enter"], ["back", "Back"]] if home.cross_opens_info() else [["accept", "Enter"], ["back", "Back"], ["north", "Options"]], 34)
	create_tween().tween_property(_games_view, "modulate:a", 0.0 if state == "menu" else 1.0, 0.3)
	create_tween().tween_property(_menu_view, "modulate:a", 1.0 if state == "menu" else 0.0, 0.3)
	if state == "menu":
		await get_tree().create_timer(0.32).timeout
		if _state == "menu":
			_games_view.visible = false
	_highlight()

## Triangle on a game: its page, the same one A opens in the Library.
func info_selected(squeeze := true) -> void:
	if _state != "menu" and _sel < _items.size() and not _items[_sel].is_empty():
		if squeeze:
			home.sfx.play("options")
			await _press()
		var it: Dictionary = _items[_sel]
		var art: Dictionary = _art.get(str(it["id"]), {})
		var cover: Texture2D = art.get("tex", null) if bool(art.get("portrait", false)) else null
		home.library.open_game(it["g"], cover)

## The top bar took the focus (true) or gave it back (false).
func dim(on: bool) -> void:
	Motion.fade_to(_menu_view if _state == "menu" else _games_view, 0.25 if on else 1.0, 0.25)
