extends Control
## The Miami theme's Home (theme id "neon"). All original drawing; it only borrows the feeling of a retrowave game's title menu.
##
##   Menu     the palm-tree sky behind (tephra_bg's "palms"), a big chunky ТЕФРА at the top drawn as a 3D block
##            (cyan face, a pink extrusion stacked down and to the right, rendered small and blown up so it is
##            pixelated), gently rocking. Under it the words: START GAME, CHAPTERS, CONTROLS, SETTINGS, EXIT GAME.
##            The chosen word is hot pink, bigger, tilting and shimmering; the others are cyan with a dark edge.
##   Games    START GAME: your Home games; CHAPTERS: every installed game (then FULL LIBRARY). A row of covers,
##            "ACT ONE, ACT TWO..." above and the chosen game's title below in pixel letters. Cross starts it (or opens
##            its page, by the setting), Down its stats, Triangle its page, Circle back.
##
## The controller's lightbar follows the sky's colour.
## home.gd hands its input here (the same hooks as channels.gd / ps2.gd).

const Themes = preload("res://themes.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Icons = preload("res://icons.gd")
const Settings = preload("res://settings.gd")

const MENU := ["START GAME", "CHAPTERS", "CONTROLS", "SETTINGS", "EXIT GAME"]
const CYAN := Color("3FF5E6")
const PINK := Color("FF2E88")
const INK := Color("2A0838")
const ORANGE := Color("FF6A2E")
const TITLE := "ТЕФРА"
## How blocky each part is: drawn this many times smaller, then blown up with no smoothing. Covers at 3 is
## the chosen look.
const PIX_PARTS := {"title": 4, "words": 3, "text": 3, "covers": 3}
var _tpix := 4                  # the title is drawn this many times smaller, then blown up: chunky pixels
var _title_fs := 60
var _title_art: Control
var _title_text_h := 70.0       # the title letters' height in the little picture
const COVER := Vector2(250, 375)

var home  # home.gd

var _state := "menu"            # "menu" or "games"
var _mi := 0
var _mi_f := 0.0                # the highlight, eased between words
var _items: Array = []          # {id, title, gi, g}: the Home games, most recently played first
var _sel := 0
var _sel_f := 0.0               # the row's scroll, eased
var _art := {}                  # game id -> cover texture
var _asked := {}
var _font: Font                 # the words
var _tfont: Font                # the title
var _script: Font               # "Act One" (Pacifico)
var _t := 0.0
var _press := 0.0               # the chosen word squeezes when pressed
var _bar_t := 0.0               # lightbar update clock

var _menu_view: Control
var _games_view: Control
var _words: Control
var _pix_layers: Array = []    # [SubViewport, Control]: the pixelated text layers, sized to the screen in _place
var _gtext: Control             # the games row's pixel text: "ACT ONE" above, the game's title below
var _list := "home"             # START GAME: "home" (your Home games); CHAPTERS: "all" (every installed game)
var _row: Control
var _title_vp: SubViewport
var _title_rect: TextureRect
var _title_ghost: TextureRect   # a pink copy just off the title, for the colour-split shimmer
var _sub: Label
var _logo: TextureRect
var _name: Label
var _hint_menu: HBoxContainer
var _hint_games: HBoxContainer
var _empty: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_font = Themes.font("neon")
	_tfont = _load_font("res://assets/fonts/rubikmono.ttf")
	_script = _load_font("res://assets/fonts/pacifico.ttf")  # "Act One": a curvy script, still pixelated
	if _tfont == null:
		_tfont = _font
	_menu_view = _blank()
	add_child(_menu_view)
	_make_title()
	# The menu words are drawn a few times smaller into their own little screen, then blown up with no smoothing,
	# so they come out in chunky pixels like the title.
	_words = _pixel_layer(_menu_view, _draw_words, "words")
	_hint_menu = _hints_box()
	_menu_view.add_child(_hint_menu)
	TephraGlyphs.fill(_hint_menu, [["accept", "Select"], ["dpad_v", "Navigate"]], 28)
	# The games row.
	_games_view = _blank()
	_games_view.visible = false
	_games_view.modulate.a = 0.0
	add_child(_games_view)
	_row = _pixel_layer(_games_view, _draw_row, "covers")
	_gtext = _pixel_layer(_games_view, _draw_gtext, "text")
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_games_view.add_child(_logo)
	_logo.visible = false  # the title is drawn in pixel letters under the covers instead (_draw_gtext)
	_name = _label("", 64, CYAN)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_neon_label(_name, 6)
	_games_view.add_child(_name)
	_name.visible = false
	_empty = _label("No games played yet. Open CHAPTERS to find one.", 36, CYAN)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_neon_label(_empty, 3)
	_games_view.add_child(_empty)
	_hint_games = _hints_box()
	_games_view.add_child(_hint_games)
	resized.connect(_place)
	rebuild()
	_place()

func _load_font(path: String) -> Font:
	var f := FontFile.new()
	return f if f.load_dynamic_font(path) == OK else null

static func pix(part: String) -> int:
	return int(PIX_PARTS[part])

## A layer drawn pix(part) times smaller and blown up with no smoothing (chunky pixels). fn draws on the returned
## Control in full-screen coordinates.
func _pixel_layer(parent: Control, fn: Callable, part: String) -> Control:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	parent.add_child(vp)
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn)
	vp.add_child(c)
	var r := TextureRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture = vp.get_texture()
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(r)
	_pix_layers.append([vp, c, part, r])
	return c

func _blank() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _neon_label(l: Label, depth: int) -> void:
	l.add_theme_color_override("font_shadow_color", PINK)
	l.add_theme_constant_override("shadow_offset_x", depth)
	l.add_theme_constant_override("shadow_offset_y", depth)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 2 * depth)

func _hints_box() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 60)
	return h

# ---------- The title ----------
## ТЕФРА is drawn once into a small picture (a 3D block: the pink sides stacked behind the cyan face), which is then
## shown several times bigger with no smoothing, so it comes out in chunky pixels. Only the rocking moves every frame.
func _make_title() -> void:
	_title_vp = SubViewport.new()
	_title_vp.transparent_bg = true
	_title_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_title_vp)
	var art := Control.new()
	_title_art = art
	art.draw.connect(func() -> void:
		var fs := _title_fs
		var depth := _title_depth()
		var pad := _title_pad()
		var asc := _tfont.get_ascent(fs)
		var base := Vector2(pad, pad + asc)
		for k in range(depth, 0, -1):  # the extrusion, darkest at the back
			var c := PINK.darkened(0.55 * float(k) / depth)
			art.draw_string(_tfont, base + Vector2(k, k), TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		art.draw_string_outline(_tfont, base, TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, INK)
		art.draw_string(_tfont, base, TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CYAN)
		# a light band across the top of the letters
		art.draw_string(_tfont, base + Vector2(0, -1), TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.18)))
	_title_vp.add_child(art)
	_size_title()
	_title_ghost = _title_tex(Color(1.0, 0.25, 0.6, 0.35))
	_title_rect = _title_tex(Color.WHITE)
	_sub = _label("TEPHRA", 34, ORANGE)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_color_override("font_outline_color", INK)
	_sub.add_theme_constant_override("outline_size", 8)
	_sub.add_theme_constant_override("shadow_offset_x", 3)
	_sub.add_theme_constant_override("shadow_offset_y", 3)
	_sub.add_theme_color_override("font_shadow_color", Color("8A1030"))
	_menu_view.add_child(_sub)

# The title's little picture is sized for its pixel level; the bigger the pixels, the smaller the picture.
func _size_title() -> void:
	_tpix = pix("title")
	_title_fs = maxi(8, int(240.0 / _tpix))
	var ts := _tfont.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, _title_fs)
	_title_vp.size = Vector2i(int(ts.x) + _title_depth() + _title_pad() * 2, int(ts.y) + _title_depth() + _title_pad() * 2)
	_title_text_h = ts.y
	_title_art.size = Vector2(_title_vp.size)
	_title_art.queue_redraw()
	_title_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

# The title's 3D depth and edge in little-picture pixels: the same size on screen at every pixel level.
func _title_depth() -> int:
	return maxi(1, roundi(28.0 / _tpix))

func _title_pad() -> int:
	return maxi(1, roundi(24.0 / _tpix))

func _title_tex(tint: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _title_vp.get_texture()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate = tint
	_menu_view.add_child(r)
	return r

func _place() -> void:
	var sz := size
	for l in _pix_layers:
		var px := float(pix(l[2]))
		var vp: SubViewport = l[0]
		vp.size = Vector2i((sz / px).ceil()).max(Vector2i.ONE)
		# smooth parts (1) keep normal filtering, so covers aren't left jagged when they're shrunk
		var smooth := px <= 1.0
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR if smooth else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		(l[3] as TextureRect).texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if smooth else CanvasItem.TEXTURE_FILTER_NEAREST
		(l[1] as Control).scale = Vector2.ONE / px
		(l[1] as Control).size = sz
	if sz.x < 10:
		return
	var tsz := Vector2(_title_vp.size) * _tpix
	var k := minf(1.0, sz.x * 0.62 / tsz.x)
	tsz *= k
	for r in [_title_ghost, _title_rect]:
		r.size = tsz
		r.pivot_offset = tsz * 0.5
		r.position = Vector2((sz.x - tsz.x) * 0.5, sz.y * 0.12)
	_sub.size = Vector2(sz.x, 50)
	_sub.position = Vector2(0, sz.y * 0.12 + (_title_pad() + _title_text_h * 0.86) * _tpix * k)  # just under the letters
	_hint_menu.size = Vector2(1200, 60)
	_hint_menu.position = Vector2((sz.x - 1200) * 0.5, sz.y - 110)
	_hint_games.size = Vector2(1200, 60)
	_hint_games.position = Vector2((sz.x - 1200) * 0.5, sz.y - 110)
	_logo.size = Vector2(720, 200)
	_logo.position = Vector2((sz.x - 720) * 0.5, sz.y * 0.2)
	_name.size = Vector2(sz.x - 200, 200)
	_name.position = Vector2(100, sz.y * 0.2)
	_empty.size = Vector2(sz.x, 60)
	_empty.position = Vector2(0, sz.y * 0.5)

# ---------- The words ----------
func _word_y(i: float) -> float:
	return size.y * 0.47 + i * size.y * 0.088

func _draw_words() -> void:
	if _font == null:
		return
	var fs := 64
	for i in MENU.size():
		var on := 1.0 - clampf(absf(_mi_f - i), 0.0, 1.0)  # 1 on the chosen word, easing as the highlight moves
		var txt: String = MENU[i]
		var s := 1.0 + 0.16 * on - 0.06 * _press * on
		var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var c := Vector2(size.x * 0.5, _word_y(i))
		var rot := (0.05 * sin(_t * 2.2) + 0.015 * sin(_t * 5.3)) * on + 0.012 * sin(_t * 0.9 + i) * (1.0 - on)
		_words.draw_set_transform(c, rot, Vector2(s, s))
		var p := Vector2(-ts.x * 0.5, ts.y * 0.3)
		var face := CYAN.lerp(PINK, on)
		var side := PINK.lerp(Color("5A0FA0"), on)
		for d in [4, 3, 2, 1]:
			_words.draw_string(_font, p + Vector2(d, d) * 1.5, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, side.darkened(0.12 * d))
		_words.draw_string_outline(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, INK)
		_words.draw_string(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, face)
		if on > 0.5:
			# the shimmer: the chosen word glows softly
			_words.draw_string(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.85, 0.95, 0.25 * on * (0.5 + 0.5 * sin(_t * 9.0))))
	_words.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------- The games row ----------
## A game's cover changed (PS2 Original / Remake art): load it again.
func forget_art(id: String) -> void:
	_art.erase(id)
	_asked.erase(id)

func rebuild() -> void:
	var keep := ""
	if _sel < _items.size():
		keep = str(_items[_sel]["id"])
	_items.clear()
	if _list == "home":
		for i in home.games.size():
			var g: Dictionary = home.games[i]
			if home.on_home(g):
				_items.append({"id": str(g["id"]), "title": str(g["title"]), "gi": i, "g": g})
	else:
		# CHAPTERS: the rest of your library: installed games hidden from Home, then games that aren't installed.
		var later: Array = []
		for g in home.library.all_games():
			var id := str(g["id"])
			var gi := -1
			for i in home.games.size():
				if str(home.games[i]["id"]) == id:
					gi = i
					break
			if gi >= 0 and home.on_home(home.games[gi]):
				continue
			var it := {"id": id, "title": str(g["title"]), "gi": gi, "g": g if gi < 0 else home.games[gi]}
			if gi >= 0:
				_items.append(it)
			else:
				later.append(it)
		_items.append_array(later)
		_items.append({"id": "", "title": "FULL LIBRARY", "gi": -1, "more": true})  # the Library, with search and installs
	_sel = 0
	for i in _items.size():
		if str(_items[i]["id"]) == keep:
			_sel = i
	_sel_f = float(_sel)
	for it in _items:
		if not it.has("more"):
			_load_cover(str(it["id"]))
	_update_game_texts()

func _load_cover(id: String) -> void:
	if _art.has(id) or _asked.has(id):
		return
	_asked[id] = true
	var pic := TextureRect.new()
	pic.visible = false
	add_child(pic)
	home.load_cover(id, pic, func() -> void:
		if is_instance_valid(pic):
			_art[id] = pic.texture
			_row.queue_redraw())

func _update_game_texts() -> void:
	_empty.visible = _items.is_empty()
	_gtext.queue_redraw()
	_row.queue_redraw()

const ONES := ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve",
	"Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
const TENS := ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]

## A number in words, never digits: 17 = "Seventeen", 40 = "Forty", 400 = "Four Hundred", 1234 = "One Thousand Two
## Hundred Thirty Four".
static func number_words(n: int) -> String:
	if n <= 0:
		return "Zero"
	var parts: PackedStringArray = []
	for big in [[1000000, "Million"], [1000, "Thousand"]]:
		if n >= big[0]:
			parts.append(number_words(n / big[0]) + " " + big[1])
			n %= big[0]
	if n >= 100:
		parts.append(ONES[n / 100] + " Hundred")
		n %= 100
	if n >= 20:
		parts.append(TENS[n / 10] + ((" " + ONES[n % 10]) if n % 10 > 0 else ""))
	elif n > 0:
		parts.append(ONES[n])
	return " ".join(parts)

func _act_name(i: int) -> String:
	return "Act " + number_words(i + 1)

## "ACT ONE" above the covers and the chosen game's title big under them, in the same chunky letters as the menu.
func _draw_gtext() -> void:
	if _font == null or _items.is_empty():
		return
	var it: Dictionary = _items[_sel]
	var wob := 0.03 * sin(_t * 1.7)
	var act := "Extras" if it.has("more") else _act_name(_sel)
	_pixel_word(act, 64, Vector2(size.x * 0.5, size.y * 0.17), wob - 0.06, CYAN, Color("0E6E68"), _script if _script != null else _font)
	var title := str(it["title"]).to_upper()
	var fs := 104
	while fs > 40 and _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x * 0.88:
		fs -= 4
	_pixel_word(title, fs, Vector2(size.x * 0.5, size.y * 0.8), -wob, CYAN, PINK)
	_gtext.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_down_arrow()

## A chunky pixel arrow under the title that nods up and down: press Down for the game's info.
func _draw_down_arrow() -> void:
	var u := 5.0  # small: it is only a hint
	var cx := size.x * 0.5
	var by := size.y * 0.866 + 3.0 * sin(_t * 3.0)
	for pass_i in 3:
		var off := Vector2.ZERO
		var col := CYAN
		var grow := 0.0
		if pass_i == 0:
			col = INK
			grow = 2.0
		elif pass_i == 1:
			col = PINK
			off = Vector2(2.5, 2.5)
		for i in 5:
			var y := by + i * u
			var lx := cx - 5.0 * u + i * u
			var rx := cx + 3.0 * u - i * u
			_gtext.draw_rect(Rect2(Vector2(lx, y) + off - Vector2(grow, grow), Vector2(2.0 * u, u) + Vector2(grow, grow) * 2.0), col)
			_gtext.draw_rect(Rect2(Vector2(rx, y) + off - Vector2(grow, grow), Vector2(2.0 * u, u) + Vector2(grow, grow) * 2.0), col)

func _pixel_word(txt: String, fs: int, c: Vector2, rot: float, face: Color, side: Color, font: Font = null) -> void:
	var f: Font = font if font != null else _font
	var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	_gtext.draw_set_transform(c, rot, Vector2.ONE)
	var p := Vector2(-ts.x * 0.5, ts.y * 0.3)
	for d in [5, 4, 3, 2, 1]:
		_gtext.draw_string(f, p + Vector2(d, d) * 1.6, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, side.darkened(0.1 * d))
	_gtext.draw_string_outline(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, INK)
	_gtext.draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, face)

func _draw_row() -> void:
	if _items.is_empty():
		return
	var cy := size.y * 0.48
	var gap := COVER.x + 60.0
	for i in _items.size():
		var dx := (float(i) - _sel_f) * gap
		var x := size.x * 0.5 + dx
		if x < -COVER.x or x > size.x + COVER.x:
			continue
		var on := 1.0 - clampf(absf(_sel_f - i), 0.0, 1.0)
		var s := 1.0 + 0.22 * on - 0.08 * _press * on
		var sz := COVER * s
		var r := Rect2(-sz * 0.5, sz)
		_row.draw_set_transform(Vector2(x, cy + 8.0 * sin(_t * 1.4 + i)), 0.05 * sin(_t * 1.1 + i * 1.7) * (0.4 + 0.6 * on), Vector2.ONE)
		# a pink block behind, like the title's extrusion
		_row.draw_rect(Rect2(r.position + Vector2(10, 10) * (0.4 + on), r.size), PINK.darkened(0.3 + 0.3 * (1.0 - on)))
		var tex: Texture2D = _art.get(str(_items[i]["id"]), null)
		if _items[i].has("more"):
			_row.draw_rect(r, INK.lightened(0.1))
			var plus := r.get_center()
			_row.draw_rect(Rect2(plus - Vector2(40, 8), Vector2(80, 16)), Color(CYAN, 0.6 + 0.4 * on))
			_row.draw_rect(Rect2(plus - Vector2(8, 40), Vector2(16, 80)), Color(CYAN, 0.6 + 0.4 * on))
		elif tex != null:
			_row.draw_texture_rect(tex, r, false, Color(1, 1, 1, 0.55 + 0.45 * on))
		else:
			_row.draw_rect(r, INK.lightened(0.1))
			_cover_title(r, str(_items[i]["title"]).to_upper(), on)
		if on > 0.01:
			_row.draw_rect(r.grow(6), Color(CYAN, on), false, 5.0)
	_row.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# A cover with no picture: the whole title, wrapped onto lines and shrunk until it fits inside.
func _cover_title(r: Rect2, txt: String, on: float) -> void:
	var w := r.size.x - 36.0
	var fs := 34
	var sz := _font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs)
	while fs > 14 and (sz.x > w + 1.0 or sz.y > r.size.y - 40.0 or _longest_word(txt, fs) > w):
		fs -= 2
		sz = _font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs)
	var p := Vector2(r.position.x + 18.0, r.get_center().y - sz.y * 0.5 + _font.get_ascent(fs))
	var col := Color(CYAN, 0.6 + 0.4 * on)
	_row.draw_multiline_string_outline(_font, p, txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, -1, 6, INK)
	_row.draw_multiline_string(_font, p, txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, -1, col)

func _longest_word(txt: String, fs: int) -> float:
	var most := 0.0
	for word in txt.split(" ", false):
		most = maxf(most, _font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return most

# ---------- Every frame ----------
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not Motion.on():
		# Animations off (or Power saver): no rocking or shimmer, and only redrawn when something changes.
		if _mi_f != float(_mi) or _sel_f != float(_sel):
			_mi_f = float(_mi)
			_sel_f = float(_sel)
			_words.queue_redraw()
			_row.queue_redraw()
			_gtext.queue_redraw()
		return
	_t += delta
	_mi_f = lerpf(_mi_f, float(_mi), 1.0 - exp(-delta * 14.0))
	_sel_f = lerpf(_sel_f, float(_sel), 1.0 - exp(-delta * 12.0))
	if _state == "menu":
		var rock := 0.035 * sin(_t * 0.8)
		var bob := 1.0 + 0.025 * sin(_t * 1.3)
		_title_rect.rotation = rock
		_title_rect.scale = Vector2(bob, bob)
		_title_ghost.rotation = rock + 0.01 * sin(_t * 3.1)
		_title_ghost.scale = Vector2(bob, bob) * 1.012
		_title_ghost.position.x = _title_rect.position.x + 6.0 * sin(_t * 2.3)
		_sub.rotation = -0.5 * rock
		_words.queue_redraw()
	else:
		_row.queue_redraw()
		_gtext.queue_redraw()
		_logo.rotation = 0.02 * sin(_t * 1.1)
		_logo.pivot_offset = _logo.size * 0.5
	# The lightbar follows the sky behind the menu (the same clock, so pink on screen is pink on the pad). 30 times a second, in small steps so it never jumps. Only while
	# Tephra's Home is up, never during a game.
	_bar_t += delta
	if _bar_t >= 1.0 / 30.0 and not home.launching and home.controllers != null:
		_bar_t = 0.0
		home.controllers.set_lightbar(bar_color())

## The lightbar's colour right now. It walks around the colour wheel in step with the sky (magenta, hot pink, purple
## into blue, teal, back through violet), always at full strength, so it never passes through a washed-out or
## random colour on the way.
const BAR_HUES := [0.92, 0.96, 0.62, 0.70, 0.80]  # pink, hot pink, blue, indigo, purple: nothing green or teal  # one for each sky colour in tephra_bg NEON_SKY, same order

static func bar_color() -> Color:
	var f := fposmod(Time.get_ticks_msec() / 9000.0, float(BAR_HUES.size()))
	var i := int(f)
	var k := smoothstep(0.0, 1.0, f - i)
	var a: float = BAR_HUES[i]
	var b: float = BAR_HUES[(i + 1) % BAR_HUES.size()]
	return Color.from_hsv(fposmod(lerpf(a, b, k), 1.0), 0.9, 1.0)

# ---------- Focus and input ----------
func selected_gi() -> int:
	return int(_items[_sel]["gi"]) if _state == "games" and _sel < _items.size() else -1  # -1 on FULL LIBRARY too

func top_column() -> float:
	return 0.5

func move(dir: Vector2i) -> String:
	if _state == "menu":
		if dir.y < 0:
			if _mi == 0:
				return "up"
			_mi -= 1
		elif dir.y > 0:
			_mi = (_mi + 1) % MENU.size()
		else:
			return ""
		Haptics.select()
		return ""
	if dir.y < 0:
		return "up"
	if dir.y > 0:
		# Down: the game's stats, achievements and description slide up, as on the other Homes.
		var gi := selected_gi()
		if gi >= 0:
			home.details.visible = true
			home._queue_details("game", gi, false)
			home._enter_details()
		return ""
	if dir.x != 0 and not _items.is_empty():
		# Holding Left / Right stops at the end of the row; a fresh press there wraps round to the other end.
		var held: bool = home.nav != null and home.nav.repeating
		var k := _sel + dir.x
		if k < 0 or k >= _items.size():
			k = (posmod(k, _items.size()) if not held else clampi(k, 0, _items.size() - 1))
			if not held:
				_sel_f = float(k) - float(dir.x)  # slide in from just past the edge, not across the whole row
		if k != _sel:
			_sel = k
			Haptics.select()
			_update_game_texts()
	return ""

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

func _squeeze() -> void:
	_press = 0.0
	var tw := create_tween()
	tw.tween_property(self, "_press", 1.0, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "_press", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished

func _activate() -> void:
	if _state == "games":
		if _sel < _items.size() and _items[_sel].has("more"):
			await _squeeze()
			home.library.open(home.clock_label.get_global_rect())
		elif _sel < _items.size() and int(_items[_sel]["gi"]) < 0:
			await _squeeze()
			home.library.open_game(_items[_sel]["g"], _art.get(str(_items[_sel]["id"]), null))  # not installed: its page, to install it
		elif _sel < _items.size():
			await _squeeze()
			home.play_or_info(int(_items[_sel]["gi"]))
		return
	await _squeeze()
	var r: Rect2 = home.clock_label.get_global_rect()
	match MENU[_mi]:
		"START GAME":
			_list = "home"
			rebuild()
			_show("games")
		"CHAPTERS":
			_list = "all"  # every installed game in the same row; its last tile opens the full Library
			rebuild()
			_show("games")
		"CONTROLS":
			home.top_menu.open_menu("pad", home.pad_wrap.get_global_rect())
		"SETTINGS":
			home.settings_screen.open(r)
		"EXIT GAME":
			if home._game_started:
				home._quit_game()
			else:
				home.toast.show_toast(Icons.texture("info", Icons.svg_info(), 40), "No game is running", false)

func _show(state: String) -> void:
	_state = state
	home.sfx.play("open")
	Haptics.select()
	if state == "games":
		_games_view.visible = true
		TephraGlyphs.fill(_hint_games, [["accept", "Play"], ["dpad_v", "Stats"], ["back", "Back"]] if home.cross_opens_info() else [["accept", "Play"], ["dpad_v", "Stats"], ["back", "Back"], ["north", "Options"]], 30)
		_update_game_texts()
	else:
		_menu_view.visible = true
	create_tween().tween_property(_games_view, "modulate:a", 0.0 if state == "menu" else 1.0, 0.3)
	create_tween().tween_property(_menu_view, "modulate:a", 1.0 if state == "menu" else 0.0, 0.3)
	await get_tree().create_timer(0.32).timeout
	_games_view.visible = _state == "games"
	_menu_view.visible = _state == "menu"

func info_selected(squeeze := true) -> void:
	if _state == "games" and _sel < _items.size() and not _items[_sel].has("more"):
		if squeeze:
			home.sfx.play("options")
			await _squeeze()
		var it: Dictionary = _items[_sel]
		home.library.open_game(it["g"], _art.get(str(it["id"]), null))

func dim(on: bool) -> void:
	Motion.fade_to(_menu_view if _state == "menu" else _games_view, 0.25 if on else 1.0, 0.25)
