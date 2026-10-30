extends Control
## The Wave theme's Home: a row of categories across the screen and a list of items under the chosen one,
## on silky blue ribbons. All original drawing; it borrows the layout idea of old console menus, nothing else.
##
##   Left / Right   change category (Profile, Settings, Games, Trophies, Album, Themes, Colours)
##   Up / Down      move through the items under it; Up from the first item goes to the top bar
##   Cross          open / start / apply the item
##
## Games lists every game: the ones on Home first, then the rest of the Library. Colours recolours the
## whole theme at once (no restart). home.gd hands its input here (the same hooks as channels.gd / ps2.gd).

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const Haptics = preload("res://haptics.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Achievements = preload("res://achievements.gd")
const SteamAccount = preload("res://steam_account.gd")

## colour name: [background top, background bottom, ribbon]
const COLORS := Themes.WAVE_COLORS
const CAT_STEP := 250.0
const ITEM_STEP := 92.0
const ITEM_GAP := 70.0

var home  # home.gd
static var _keep_ci := -1     # survives the rebuild after a colour change
static var _keep_mem := {}

var _cats: Array = []       # {name, kind, items: [{label, sub, kind, ...}]}
var _ci := 2                # category (opens on Games)
var _mem := {}              # category -> remembered item
var _cat_f := 1.0           # eased category position
var _sel_f := 0.0           # eased item position
var _art := {}              # game id -> Texture2D (or null while loading)
var _holders: Array = []
var _font: Font
var _t := 0.0
var _hints: HBoxContainer
var _trophies_loaded := false
var _dim := 1.0
var _dim_to := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_font = Themes.font("wave")
	if _font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Helvetica Neue", "Helvetica", "Arial", "Liberation Sans", "DejaVu Sans"])
		_font = sf
	_hints = HBoxContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.alignment = BoxContainer.ALIGNMENT_END
	add_child(_hints)
	_hints.anchor_left = 0.0
	_hints.anchor_right = 1.0
	_hints.anchor_top = 1.0
	_hints.anchor_bottom = 1.0
	_hints.offset_left = 80
	_hints.offset_right = -90
	_hints.offset_top = -150
	_hints.offset_bottom = -90
	TephraGlyphs.fill(_hints, [["accept", "Select"], ["dpad", "Navigate"]], 28)
	if _keep_ci >= 0:
		_ci = _keep_ci  # just recoloured: stay on the Colours category, on the colour chosen
		_mem = _keep_mem
		_keep_ci = -1
	rebuild()
	_cat_f = float(_ci)

# ---------- Building ----------
func _palette() -> Array:
	return COLORS.get(str(Settings.get_value("xmb_color", "Blue")), COLORS["Blue"])

## A game's cover changed (PS2 Original / Remake art): load it again.
func forget_art(id: String) -> void:
	_art.erase(id)

func rebuild() -> void:
	var keep := ""
	var it := _item()
	if not it.is_empty() and it.get("kind", "") == "game":
		keep = str(it["id"])
	_cats.clear()
	_cats.append({"name": "Profile", "kind": "profile", "items": [
		{"label": home.profile_name.text if home.profile_name != null and home.profile_name.text != "" else "Player", "sub": "Your profile", "kind": "profile"}]})
	var set_items: Array = []
	var tab_subs := ["Updates, time, power", "Resolution, refresh rate, HDR", "Choose a theme", "Volume and devices", "Pads, battery, lightbar", "Steam, PS2, achievements", "Motion and readability"]
	for t in home.settings_screen.TABS.size():
		set_items.append({"label": str(home.settings_screen.TABS[t]), "sub": tab_subs[t] if t < tab_subs.size() else "", "kind": "settings", "tab": t})
	set_items.append({"label": "Wi-Fi", "sub": "Networks", "kind": "wifi"})
	set_items.append({"label": "System information", "sub": "Tephra and this PC", "kind": "info"})
	_cats.append({"name": "Settings", "kind": "settings", "items": set_items})
	var games: Array = []
	var seen := {}
	for i in home.games.size():
		var g: Dictionary = home.games[i]
		if home.on_home(g):
			games.append({"label": str(g["title"]), "sub": "In Home", "kind": "game", "id": str(g["id"]), "gi": i, "g": g})
			seen[str(g["id"])] = true
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
		games.append({"label": str(g["title"]), "sub": "Installed" if gi >= 0 else "In your library", "kind": "game", "id": id, "gi": gi, "g": g})
	if games.is_empty():
		games.append({"label": "No games yet", "sub": "Install one with Steam", "kind": "none"})
	_cats.append({"name": "Games", "kind": "games", "items": games})
	_cats.append({"name": "Trophies", "kind": "trophies", "items": [
		{"label": "Trophy collection", "sub": "Your profile and achievements", "kind": "profile"}]})
	_trophies_loaded = false
	_cats.append({"name": "Album", "kind": "album", "items": [
		{"label": "Screenshots and clips", "sub": "Open the album", "kind": "album"}]})
	var themes: Array = []
	for t in Themes.ORDER:
		themes.append({"label": str(Themes.data(t)["name"]), "sub": str(Themes.data(t)["blurb"]) + ("  ·  in use" if t == Themes.id() else ""), "kind": "theme", "id": t})
	_cats.append({"name": "Themes", "kind": "themes", "items": themes})
	var cols: Array = []
	for n in COLORS:
		cols.append({"label": n, "sub": "Colour of this theme", "kind": "color", "id": n})
	_cats.append({"name": "Colours", "kind": "colors", "items": cols})
	_ci = clampi(_ci, 0, _cats.size() - 1)
	if keep != "":
		for i in games.size():
			if games[i].get("id", "") == keep:
				_mem[2] = i
	_sel_f = float(_mem.get(_ci, 0))
	if _mem.get(_ci, 0) >= _cats[_ci]["items"].size():
		_mem[_ci] = 0

func _items() -> Array:
	return _cats[_ci]["items"]

func _item() -> Dictionary:
	if _cats.is_empty():
		return {}
	var l := _items()
	var i := int(_mem.get(_ci, 0))
	return l[i] if i < l.size() else {}

func _load_trophies() -> void:
	_trophies_loaded = true
	var acc := Achievements.account_id(SteamAccount.steam_id(home.steam_dir))
	var list: Array = _cats[3]["items"]
	for a in Achievements.recent(home.steam_dir, acc, 6):
		list.append({"label": str(a["name"]), "sub": str(a["game"]), "kind": "trophy"})

func _load_cover(id: String) -> void:
	if _art.has(id):
		return
	_art[id] = null
	var pic := TextureRect.new()
	pic.visible = false
	add_child(pic)
	_holders.append(pic)
	home.load_cover(id, pic, func() -> void:
		if is_instance_valid(pic) and pic.texture != null:
			var img := pic.texture.get_image()
			if img != null and not img.is_empty():
				if img.is_compressed():
					img.decompress()
				img.generate_mipmaps()  # smooth when a big cover is drawn small
				_art[id] = ImageTexture.create_from_image(img))

# ---------- Focus (the hooks home.gd uses) ----------
func selected_gi() -> int:
	var it := _item()
	return int(it["gi"]) if it.get("kind", "") == "game" else -1

func top_column() -> float:
	return 0.3

func dim(on: bool) -> void:
	_dim_to = 0.25 if on else 1.0

## Up from the first item returns "up" (the top bar).
func move(dir: Vector2i) -> String:
	if dir.x != 0:
		var n := posmod(_ci + dir.x, _cats.size())
		if n != _ci:
			_ci = n
			if _cats[_ci]["kind"] == "trophies" and not _trophies_loaded:
				_load_trophies()
			_sel_f = float(_mem.get(_ci, 0))
			home.sfx.play("tick")
			Haptics.select()
		return ""
	var i := int(_mem.get(_ci, 0))
	if dir.y < 0:
		if i == 0:
			if home.nav != null and home.nav.repeating:
				return ""  # holding Up stops at the top item: let go and press Up again to leave the list
			return "up"
		_mem[_ci] = i - 1
	elif dir.y > 0:
		_mem[_ci] = posmod(i + 1, _items().size())  # past the last item: round to the first
	if int(_mem.get(_ci, 0)) != i:
		home.sfx.play("tick")
		Haptics.select()
	return ""

func handle_input(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return true
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		_activate()
		return true
	return false

func _activate() -> void:
	var it := _item()
	var r: Rect2 = home.clock_label.get_global_rect()
	match str(it.get("kind", "")):
		"game":
			if int(it["gi"]) >= 0:
				home.play_or_info(int(it["gi"]))
			else:
				home.library.open_game(it["g"], _art.get(str(it["id"]), null))
		"profile":
			home.profile_screen.open(r)
		"settings":
			if int(it["tab"]) < 0:
				home.settings_screen.open(r)
			else:
				home.settings_screen.open(r, int(it["tab"]))
		"info":
			home.settings_screen.open_info(r)
		"pad":
			home.top_menu.open_menu("pad", home.pad_wrap.get_global_rect())
		"wifi":
			home.top_menu.open_menu("wifi", home.wifi_icon.get_global_rect())
		"album":
			home._open_album()
		"theme":
			home.apply_theme(str(it["id"]))
		"color":
			if str(it["id"]) != str(Settings.get_value("xmb_color", "Blue")):
				Settings.set_value("xmb_color", str(it["id"]))
				home.sfx.play("open")
				Haptics.select()
				_keep_ci = _ci
				_keep_mem = _mem.duplicate()
				home.apply_theme("wave", true)  # every menu is rebuilt in the new colour (the same fade as a theme change)
		_:
			Haptics.tick()

## Triangle on a game: its page.
func info_selected(_squeeze := true) -> void:
	var it := _item()
	if it.get("kind", "") == "game":
		home.sfx.play("options")
		home.library.open_game(it["g"], _art.get(str(it["id"]), null))

# ---------- Drawing ----------
func _process(delta: float) -> void:
	if not is_visible_in_tree() or home.library.is_open:
		return
	_t += delta
	_dim = lerpf(_dim, _dim_to, 1.0 - exp(-delta * 9.0))
	var k := 1.0 - exp(-delta * 10.0)
	_cat_f = lerpf(_cat_f, float(_ci), k)
	_sel_f = lerpf(_sel_f, float(_mem.get(_ci, 0)), k)
	queue_redraw()

func _draw() -> void:
	if _cats.is_empty():
		return
	var W := size.x
	var H := size.y
	var pal := _palette()
	var top: Color = pal[0]
	var bot: Color = pal[1]
	var rib: Color = pal[2]
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([top, top, bot, bot]))
	_draw_ribbons(W, H, rib)
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, (1.0 - _dim) * 0.6))  # the top bar has the focus: everything below darkens
	var x0 := W * 0.27
	var y_cat := H * 0.25
	# categories
	for i in _cats.size():
		var d := float(i) - _cat_f
		var cx := x0 + d * CAT_STEP
		var near := clampf(1.0 - absf(d), 0.0, 1.0)
		var a := (0.45 + 0.55 * near) * _dim
		var s := 78.0 + 34.0 * near
		_glyph(str(_cats[i]["kind"]), Vector2(cx, y_cat), s, Color(1, 1, 1, a))
		if near > 0.02:
			_text(str(_cats[i]["name"]), Vector2(cx - 150, y_cat + s * 0.5 + 38), 30, Color(1, 1, 1, near * _dim), 300, true)
	# items
	var items := _items()
	var y0 := y_cat + 230.0
	for i in items.size():
		var dd := float(i) - _sel_f
		var y := y0 + dd * ITEM_STEP + clampf(dd, -1.0, 1.0) * ITEM_GAP
		if y < y_cat + 100.0 or y > H + 60.0:
			continue
		var fade := clampf((y - (y_cat + 100.0)) / 80.0, 0.0, 1.0)
		var near := clampf(1.0 - absf(dd), 0.0, 1.0)
		var a := (0.55 + 0.45 * near) * fade * _dim
		var it: Dictionary = items[i]
		var sz := 62.0 + 28.0 * near
		var c := Vector2(x0, y)
		_item_icon(it, c, sz, a)
		_text(str(it["label"]), Vector2(x0 + sz * 0.5 + 28, y + 8 - 8 * near), 34 + int(6 * near), Color(1, 1, 1, a), 1100, false)
		if near > 0.05:
			_text(str(it.get("sub", "")), Vector2(x0 + sz * 0.5 + 28, y + 42), 24, Color(1, 1, 1, near * 0.7 * fade * _dim), 1100, false)

func _text(s: String, p: Vector2, fs: int, col: Color, w: float, centre: bool) -> void:
	# a soft shadow keeps white words readable over the bright ribbons
	var al := HORIZONTAL_ALIGNMENT_CENTER if centre else HORIZONTAL_ALIGNMENT_LEFT
	draw_string(_font, p + Vector2(2, 3), s, al, w, fs, Color(0, 0, 0, col.a * 0.35))
	draw_string(_font, p, s, al, w, fs, col)

func _draw_ribbons(W: float, H: float, rib: Color) -> void:
	var n := 56
	for b in 4:
		var up := PackedVector2Array()
		var dn := PackedVector2Array()
		var ph := _t * (0.22 + 0.07 * b) + b * 1.7
		var base := H * (0.50 + 0.05 * b)
		for i in n + 1:
			var x := W * float(i) / n
			var u := float(i) / n
			var y := base + sin(u * 4.2 + ph) * H * 0.07 + sin(u * 9.0 - ph * 1.3) * H * 0.015
			var th := (16.0 + 46.0 * sin(u * 3.0 + b)) * (0.6 + 0.4 * sin(ph + u * 2.0)) + 30.0
			up.append(Vector2(x, y - th))
			dn.append(Vector2(x, y + th * 0.6))
		var poly := up.duplicate()
		for i in range(dn.size() - 1, -1, -1):
			poly.append(dn[i])
		draw_colored_polygon(poly, Color(rib.r, rib.g, rib.b, 0.07 + 0.02 * b))
		draw_polyline(up, Color(rib.r, rib.g, rib.b, 0.38 - 0.06 * b), 2.0, true)
		draw_polyline(dn, Color(rib.r, rib.g, rib.b, 0.16), 1.5, true)
	for i in 70:
		var h1 := fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var h2 := fposmod(sin(float(i) * 78.233) * 12543.123, 1.0)
		var tw := 0.5 + 0.5 * sin(_t * (0.6 + h1) + h2 * 6.28)
		draw_circle(Vector2(h1 * W, h2 * H), 1.2 + h2 * 1.4, Color(1, 1, 1, 0.10 + 0.35 * tw * h2))

func _item_icon(it: Dictionary, c: Vector2, s: float, a: float) -> void:
	var kind := str(it.get("kind", ""))
	if kind == "game":
		_load_cover(str(it["id"]))
		var tex: Texture2D = _art.get(str(it["id"]), null)
		var r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
		var rad := s * 0.22
		# a dark glass tile with a bright rim, the picture set inside it with rounded corners, and a soft gloss on top
		var frame := _rrect(r.grow(5.0), rad + 4.0)
		draw_colored_polygon(frame, Color(0.02, 0.05, 0.14, 0.78 * a))
		draw_polyline(_close(frame), Color(1, 1, 1, 0.55 * a), 2.0, true)
		var inner := _rrect(r, rad)
		if tex != null:
			var ts := tex.get_size()
			var side := minf(ts.x, ts.y)
			var sy := clampf((ts.y - side) * 0.3, 0.0, maxf(ts.y - side, 0.0))
			var src := Rect2((ts.x - side) * 0.5, sy, side, side)
			var uvs := PackedVector2Array()
			for pt in inner:
				var u := (pt - r.position) / r.size
				uvs.append((src.position + u * src.size) / ts)
			draw_colored_polygon(inner, Color(1, 1, 1, a), uvs, tex)
		else:
			draw_colored_polygon(inner, Color(1, 1, 1, 0.14 * a))
		draw_polyline(_close(inner), Color(0.02, 0.05, 0.14, 0.9 * a), 1.6, true)  # smooths the picture's rounded edge
		var gloss := _rrect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, r.size.y * 0.42)), rad - 2.0)
		draw_colored_polygon(gloss, Color(1, 1, 1, 0.13 * a))
	elif kind == "color":
		var col: Color = COLORS[it["id"]][1].lerp(COLORS[it["id"]][2], 0.35)
		draw_circle(c, s * 0.5, Color(col, a))
		draw_arc(c, s * 0.5, 0.0, TAU, 32, Color(1, 1, 1, 0.8 * a), 2.5, true)
		if str(it["id"]) == str(Settings.get_value("xmb_color", "Blue")):
			draw_circle(c, s * 0.14, Color(1, 1, 1, a))
	else:
		draw_circle(c, s * 0.62, Color(1, 1, 1, 0.09 * a))  # a faint glass disc behind the symbol
		draw_arc(c, s * 0.62, 0.0, TAU, 40, Color(1, 1, 1, 0.35 * a), 2.0, true)
		_glyph({"profile": "profile", "settings": "settings", "info": "info", "pad": "games", "wifi": "wifi",
			"album": "album", "theme": "themes", "trophy": "trophies"}.get(kind, "info"), c, s, Color(1, 1, 1, a))

## The outline of a rounded rectangle as a polygon (clockwise from the top left corner).
func _rrect(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [[r.position + Vector2(r.size.x - rad, rad), -PI * 0.5], [r.position + Vector2(r.size.x - rad, r.size.y - rad), 0.0],
		[r.position + Vector2(rad, r.size.y - rad), PI * 0.5], [r.position + Vector2(rad, rad), PI]]
	for cn in corners:
		for i in 7:
			var an: float = float(cn[1]) + (PI * 0.5) * float(i) / 6.0
			pts.append(cn[0] + Vector2(cos(an), sin(an)) * rad)
	return pts

func _close(pts: PackedVector2Array) -> PackedVector2Array:
	var o := pts.duplicate()
	o.append(pts[0])
	return o

## Small symbols, drawn from SVG once at a high resolution and then scaled smoothly, so their lines are never jagged.
const GLYPH_SVG := {
	"profile": '<circle cx="50" cy="34" r="17"/><path d="M18,86 C18,62 82,62 82,86"/>',
	"settings": '<circle cx="50" cy="50" r="14"/><circle cx="50" cy="50" r="30"/><path d="M50,8 V20 M50,80 V92 M8,50 H20 M80,50 H92 M20,20 L28,28 M72,72 L80,80 M80,20 L72,28 M28,72 L20,80"/>',
	"games": '<rect x="10" y="30" width="80" height="44" rx="12"/><path d="M28,42 V62 M18,52 H38"/><circle cx="62" cy="48" r="4" fill="WHITE"/><circle cx="74" cy="58" r="4" fill="WHITE"/>',
	"trophies": '<path d="M28,18 H72 V40 C72,56 62,64 50,64 C38,64 28,56 28,40 Z"/><path d="M28,26 H16 C16,40 22,46 30,48 M72,26 H84 C84,40 78,46 70,48"/><path d="M50,64 V78 M36,86 H64"/>',
	"album": '<rect x="10" y="28" width="80" height="54" rx="9"/><circle cx="50" cy="55" r="15"/><path d="M32,28 L38,18 H62 L68,28"/>',
	"themes": '<path d="M50,10 L84,50 L50,90 L16,50 Z"/><path d="M16,50 H84"/>',
	"colors": '<circle cx="36" cy="60" r="22"/><circle cx="64" cy="60" r="22"/><circle cx="50" cy="36" r="22"/>',
	"wifi": '<path d="M16,44 C36,26 64,26 84,44 M28,57 C42,45 58,45 72,57 M40,70 C46,65 54,65 60,70"/><circle cx="50" cy="82" r="4" fill="WHITE"/>',
	"info": '<circle cx="50" cy="50" r="38"/><path d="M50,46 V70"/><circle cx="50" cy="31" r="4" fill="WHITE"/>',
}
var _glyph_tex := {}

func _glyph(kind: String, c: Vector2, s: float, col: Color) -> void:
	if not GLYPH_SVG.has(kind):
		kind = "info"
	if not _glyph_tex.has(kind):
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="400" height="400"><g fill="none" stroke="white" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % GLYPH_SVG[kind].replace("WHITE", "white")
		var img := Image.new()
		img.load_svg_from_string(svg, 1.0)
		img.generate_mipmaps()
		_glyph_tex[kind] = ImageTexture.create_from_image(img)
	draw_texture_rect(_glyph_tex[kind], Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, col)
