extends Control
## The Circuit theme's Home: the games are black chips on a green circuit board. Each game's cover sits in a chip
## body (tinted dark until chosen) with pins along its edges, upright or lying down, spread over the board in columns
## with a little drift so it looks laid out by a designer and not by a ruler. Copper traces join the chips in order,
## and a pulse runs along the traces of the chosen chip. Left and Right walk the chain of chips in order (the traces
## show the way), A plays, Y opens the game's page, Up goes to the top bar. The board slides sideways to keep the chosen chip in view. Same hooks as xmb.gd, neon.gd and planet.gd.

const Themes = preload("res://themes.gd")
const Haptics = preload("res://haptics.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Icons = preload("res://icons.gd")

const D := 1440.0                    # the board is laid out for a 1440 high screen and scaled to fit
const TALL := Vector2(230, 345)
const WIDE := Vector2(350, 164)
const SQUARE := Vector2(220, 220)
const PIN := Vector2(15, 9)
const PITCH := 27.0

const COPPER := Color(0.82, 0.66, 0.3)
const GOLD := Color(0.95, 0.78, 0.32)

var home  # home.gd

var _items: Array = []     # {label, kind: game | home | library, id, gi, g, wide, pos, size, tag}
var _sel := 0
var _cam := 0.0
var _art := {}             # game id -> {"tall": Texture2D, "wide": Texture2D}
var _asked := {}
var _holders: Array = []
var _links: Array = []     # {a, b, pts: PackedVector2Array}
var _buses: Array = []     # decorative traces that run past the chips
var _grow: Array = []      # eased 0..1 "chosen" amount of each chip
var _world_w := 2000.0
var _t := 0.0
var _dim := 1.0
var _dim_to := 1.0
var _font: Font
var _hints: HBoxContainer
var _body: StyleBoxFlat
var _ring: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_font = Themes.font()
	if _font == null:
		_font = ThemeDB.fallback_font
	_body = StyleBoxFlat.new()
	_body.bg_color = Color(0.025, 0.027, 0.03)
	_body.border_color = Color(0.16, 0.17, 0.19)
	_body.set_border_width_all(3)
	_body.set_corner_radius_all(11)
	_ring = StyleBoxFlat.new()
	_ring.draw_center = false
	_ring.border_color = GOLD
	_ring.set_border_width_all(4)
	_ring.set_corner_radius_all(13)
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
	_hints.offset_top = -110
	_hints.offset_bottom = -50
	TephraGlyphs.fill(_hints, [["dpad", "Next chip"], ["accept", "Play"], ["north", "Game page"]], 28)
	rebuild()
	_cam = _target_cam()

# ---------- Building ----------
func forget_art(id: String) -> void:
	_art.erase(id)
	_asked.erase(id)

static func _hash(s: String) -> int:
	return absi(s.hash())

func rebuild() -> void:
	var keep := ""
	if _sel >= 0 and _sel < _items.size() and _items[_sel].get("kind", "") == "game":
		keep = str(_items[_sel]["id"])
	_items.clear()
	_items.append({"label": "Home", "sub": "Your stats and trophies", "kind": "home"})
	var seen := {}
	for i in home.games.size():
		var g: Dictionary = home.games[i]
		if home.on_home(g):
			_items.append({"label": str(g["title"]), "kind": "game", "id": str(g["id"]), "gi": i, "g": g})
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
		_items.append({"label": str(g["title"]), "kind": "game", "id": id, "gi": gi, "g": g})
	_items.append({"label": "Library", "sub": "Everything you own", "kind": "library"})
	_layout()
	if keep != "":
		for i in _items.size():
			if _items[i].get("id", "") == keep:
				_sel = i
	_sel = clampi(_sel, 0, _items.size() - 1)
	if keep == "":
		_sel = 0  # opens on Home
	_grow.clear()
	for i in _items.size():
		_grow.append(1.0 if i == _sel else 0.0)
	_ensure_art()

## Puts every chip on the board: columns left to right (one, then pairs, with the odd single), each chip's size
## and drift taken from its id so the board looks the same every time.
func _layout() -> void:
	var pattern := [1, 2, 2, 1, 2, 2, 2, 1]
	var col := 0
	var x := 330.0
	var i := 0
	var n := _items.size()
	var pi := 0
	while i < n:
		var per: int = pattern[pi % pattern.size()]
		if i == 0 or i == n - 1:
			per = 1  # Home and Library each get a column of their own
		per = mini(per, n - i - (1 if i < n - 1 and i + per >= n else 0))
		per = maxi(per, 1)
		var group_w := 0.0
		for j in per:
			var it: Dictionary = _items[i + j]
			var kind := str(it["kind"])
			var h := _hash(str(it.get("id", kind)))
			it["wide"] = kind == "game" and h % 100 < 40
			it["size"] = SQUARE if kind != "game" else (WIDE if bool(it["wide"]) else TALL)
			group_w = maxf(group_w, (it["size"] as Vector2).x)
		for j in per:
			var it: Dictionary = _items[i + j]
			var h := _hash(str(it.get("id", it["kind"])))
			var sz: Vector2 = it["size"]
			var dx := float((h >> 3) % 61) - 30.0
			var dy := float((h >> 9) % 49) - 24.0
			var y := 760.0
			if per == 2:
				y = 545.0 if j == 0 else 985.0
			it["pos"] = Vector2(x + group_w * 0.5 + dx, y + dy)
			it["tag"] = "U%d" % (i + j + 1)
		x += group_w + 150.0
		i += per
		pi += 1
		col += 1
	_world_w = x + 200.0
	_links.clear()
	for k in n - 1:
		_links.append({"a": k, "b": k + 1, "pts": _route(k, k + 1)})
	# traces that only decorate: a few buses running across the whole board, behind the chips
	_buses.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for b in 7:
		var yy := rng.randf_range(230.0, 1250.0)
		var pts := PackedVector2Array()
		var xx := -60.0
		while xx < _world_w + 100.0:
			pts.append(Vector2(xx, yy))
			xx += rng.randf_range(160.0, 420.0)
			pts.append(Vector2(xx, yy))
			var dy := rng.randf_range(-90.0, 90.0)
			xx += absf(dy)
			yy = clampf(yy + dy, 200.0, 1280.0)
		_buses.append(pts)

## A copper trace from one chip to the next: out of a side, one diagonal jog, into the other.
func _route(a: int, b: int) -> PackedVector2Array:
	var ia: Dictionary = _items[a]
	var ib: Dictionary = _items[b]
	var pa: Vector2 = ia["pos"]
	var pb: Vector2 = ib["pos"]
	var sa: Vector2 = ia["size"]
	var sb: Vector2 = ib["size"]
	if absf(pb.x - pa.x) < 120.0:
		# stacked: from the bottom of the upper chip to the top of the lower one
		var up := pa.y < pb.y
		var s := Vector2(pa.x, pa.y + (sa.y * 0.5 + 28.0 if up else -sa.y * 0.5 - 28.0))
		var e := Vector2(pb.x, pb.y + (-sb.y * 0.5 - 28.0 if up else sb.y * 0.5 + 28.0))
		var gap := e.y - s.y
		if absf(e.x - s.x) < 8.0 or absf(gap) < 40.0:
			return PackedVector2Array([s, e])
		var m1 := Vector2(s.x, s.y + gap * 0.3)
		var m2 := Vector2(e.x, s.y + gap * 0.7)
		return PackedVector2Array([s, m1, m2, e])
	var start := Vector2(pa.x + sa.x * 0.5 + PIN.x + 8.0, pa.y)
	var end := Vector2(pb.x - sb.x * 0.5 - PIN.x - 8.0, pb.y)
	var mid := (start.x + end.x) * 0.5
	var dyv := absf(end.y - start.y) * 0.5
	return PackedVector2Array([start, Vector2(mid - dyv, start.y), Vector2(mid + dyv, end.y), end])

## Covers for the chips near the chosen one: upright and lying down are both asked for once.
func _ensure_art() -> void:
	for d in range(-6, 7):
		var i := _sel + d
		if i < 0 or i >= _items.size() or _items[i].get("kind", "") != "game":
			continue
		var id := str(_items[i]["id"])
		if _asked.has(id):
			continue
		_asked[id] = true
		_art[id] = {"tall": null, "wide": null}
		var tall := TextureRect.new()
		tall.visible = false
		add_child(tall)
		_holders.append(tall)
		home.load_cover(id, tall, func() -> void:
			if is_instance_valid(tall) and tall.texture != null:
				_art[id]["tall"] = tall.texture)
		if bool(_items[i]["wide"]):
			var wide := TextureRect.new()
			wide.visible = false
			add_child(wide)
			_holders.append(wide)
			home._load_art(id, "header", wide, "jpg", func() -> void:
				if is_instance_valid(wide) and wide.texture != null:
					_art[id]["wide"] = wide.texture)

# ---------- Focus (the hooks home.gd uses) ----------
func _cur() -> Dictionary:
	return _items[_sel] if _sel >= 0 and _sel < _items.size() else {}

## Holding PS: back onto the Home icon.
func go_home() -> void:
	if _items.is_empty() or _sel == 0:
		return
	_sel = 0
	home.sfx.play("tick")
	_ensure_art()

func selected_gi() -> int:
	var it := _cur()
	return int(it["gi"]) if it.get("kind", "") == "game" else -1

func top_column() -> float:
	return 0.4

func dim(on: bool) -> void:
	_dim_to = 0.3 if on else 1.0

## The chips are one chain, joined by the traces in order (Home, then the games, then the Library): Left goes to the
## chip before, Right to the one after, round to the other end past the last. Up goes to the top bar; Down does nothing.
func move(dir: Vector2i) -> String:
	if _items.is_empty():
		return ""
	if dir.x == 0:
		if dir.y < 0:
			if home.nav != null and home.nav.repeating:
				return ""
			return "up"
		if dir.y > 0 and _cur().get("kind", "") == "home" and not (home.nav != null and home.nav.repeating):
			home.sfx.play("tick")
			home.open_home_page()  # Down on the Home chip: your stats and trophies
		return ""
	var n := posmod(_sel + dir.x, _items.size())
	if n != _sel:
		_sel = n
		home.sfx.play("tick")
		Haptics.select()
		_ensure_art()
	return ""

func handle_input(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return true
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		_activate()
		return true
	return false

func _activate() -> void:
	var it := _cur()
	match str(it.get("kind", "")):
		"game":
			if int(it["gi"]) >= 0:
				home.play_or_info(int(it["gi"]))
			else:
				home.library.open_game(it["g"], _art.get(str(it["id"]), {}).get("tall", null))
		"home":
			home.open_home_page()
		"library":
			home.library.open(home.clock_label.get_global_rect())
		_:
			Haptics.tick()

func info_selected(_squeeze := true) -> void:
	var it := _cur()
	if it.get("kind", "") == "game":
		home.sfx.play("options")
		home.library.open_game(it["g"], _art.get(str(it["id"]), {}).get("tall", null))

# ---------- Drawing ----------
func _target_cam() -> float:
	if _items.is_empty():
		return 0.0
	var view := size.x * D / maxf(size.y, 1.0)
	var x: float = (_items[_sel]["pos"] as Vector2).x
	return clampf(x - view * 0.5, 0.0, maxf(_world_w - view, 0.0))

func _process(delta: float) -> void:
	if not is_visible_in_tree() or home.library.is_open:
		return
	_t += delta
	_dim = lerpf(_dim, _dim_to, 1.0 - exp(-delta * 9.0))
	_cam = lerpf(_cam, _target_cam(), 1.0 - exp(-delta * 7.0))
	for i in _grow.size():
		_grow[i] = lerpf(_grow[i], 1.0 if i == _sel else 0.0, 1.0 - exp(-delta * 12.0))
	queue_redraw()

func _shadow_text(s: String, p: Vector2, fs: int, col: Color, w := -1.0, al := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(_font, p + Vector2(2, 3), s, al, w, fs, Color(0, 0, 0, col.a * 0.55))
	draw_string(_font, p, s, al, w, fs, col)

func _point_on(pts: PackedVector2Array, f: float) -> Vector2:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var want := total * f
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		if want <= l:
			return pts[i].lerp(pts[i + 1], want / maxf(l, 0.001))
		want -= l
	return pts[pts.size() - 1]

func _draw() -> void:
	if _items.is_empty():
		return
	var k := size.y / D
	var view := size.x / k
	draw_set_transform(Vector2(-_cam * k, 0.0), 0.0, Vector2(k, k))
	var lo := _cam - 400.0
	var hi := _cam + view + 400.0
	# decorative buses
	for pts in _buses:
		draw_polyline(pts, Color(0.0, 0.06, 0.03, 0.4 * _dim), 9.0, true)
		draw_polyline(pts, Color(COPPER, 0.22 * _dim), 4.0, true)
	# traces between neighbouring chips; the chosen chip's run lit, with a pulse travelling along
	for l in _links:
		var pts: PackedVector2Array = l["pts"]
		if pts[0].x > hi and pts[pts.size() - 1].x > hi:
			continue
		if pts[pts.size() - 1].x < lo and pts[0].x < lo:
			continue
		var live: bool = int(l["a"]) == _sel or int(l["b"]) == _sel
		draw_polyline(pts, Color(0.0, 0.06, 0.03, 0.7 * _dim), 11.0, true)
		draw_polyline(pts, Color(GOLD if live else COPPER, (0.95 if live else 0.6) * _dim), 6.0, true)
		draw_circle(pts[0], 8, Color(GOLD if live else COPPER, _dim))
		draw_circle(pts[pts.size() - 1], 8, Color(GOLD if live else COPPER, _dim))
		draw_circle(pts[0], 3.5, Color(0.02, 0.1, 0.06, _dim))
		draw_circle(pts[pts.size() - 1], 3.5, Color(0.02, 0.1, 0.06, _dim))
		if live:
			for ph in 2:
				var f := fposmod(_t * 0.45 + float(ph) * 0.5, 1.0)
				if int(l["b"]) == _sel:
					f = 1.0 - f
				var p := _point_on(pts, f)
				draw_circle(p, 16, Color(1, 0.95, 0.7, 0.16 * _dim))
				draw_circle(p, 7, Color(1, 0.97, 0.8, 0.95 * _dim))
	# chips: the chosen one is drawn last so it sits on top
	var order: Array = []
	for i in _items.size():
		var p: Vector2 = _items[i]["pos"]
		var half: float = (_items[i]["size"] as Vector2).x * 0.5 + 60.0
		if p.x + half < lo or p.x - half > hi:
			continue
		if i != _sel:
			order.append(i)
	order.append(_sel)
	for i in order:
		_draw_chip(i)
	# the chosen game's name, bottom left (in screen units)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var cur := _cur()
	var label := str(cur.get("label", ""))
	var sub := str(cur.get("sub", ""))
	if cur.get("kind", "") == "game":
		sub = ("Press %s to play" % TephraGlyphs.btn("accept")) if int(cur["gi"]) >= 0 else ("Not installed. Press %s to open its page" % TephraGlyphs.btn("accept"))
	var fs := int(56 * k)
	_shadow_text(label, Vector2(80 * k + 20, size.y - 200 * k), fs, Color(0.96, 0.98, 0.94, _dim), size.x * 0.62)
	if sub != "":
		_shadow_text(sub, Vector2(80 * k + 20, size.y - 200 * k + 52 * k), int(26 * k), Color(0.8, 0.9, 0.78, 0.85 * _dim))
	if cur.get("kind", "") == "home":
		var ay := size.y - 200 * k + 108 * k + 4.0 * k * sin(_t * 3.0)
		var ax := 80 * k + 52
		var aw := 24.0 * k
		draw_polyline(PackedVector2Array([Vector2(ax - aw, ay), Vector2(ax, ay + aw * 0.7), Vector2(ax + aw, ay)]), Color(0.96, 0.98, 0.94, 0.85 * _dim), maxf(4.0 * k, 3.0), true)

func _draw_chip(i: int) -> void:
	var it: Dictionary = _items[i]
	var g: float = _grow[i] if i < _grow.size() else 0.0
	var sz: Vector2 = it["size"]
	var p: Vector2 = it["pos"]
	var s := 1.0 + 0.07 * g
	var body := Rect2(p - sz * 0.5 * s, sz * s)
	# pins: down the two long sides of an upright chip, along the top and bottom of one lying down
	var upright := sz.y >= sz.x
	var pin_col := Color(0.72, 0.68, 0.55).lerp(Color(1.0, 0.9, 0.5), g)
	if upright:
		var n := int((body.size.y - 40.0) / PITCH)
		var y0 := body.position.y + (body.size.y - float(n - 1) * PITCH) * 0.5
		for q in n:
			var y := y0 + float(q) * PITCH
			draw_rect(Rect2(body.position.x - PIN.x, y - PIN.y * 0.5, PIN.x + 4, PIN.y), Color(pin_col, _dim))
			draw_rect(Rect2(body.end.x - 4, y - PIN.y * 0.5, PIN.x + 4, PIN.y), Color(pin_col, _dim))
	else:
		var n2 := int((body.size.x - 40.0) / PITCH)
		var x0 := body.position.x + (body.size.x - float(n2 - 1) * PITCH) * 0.5
		for q in n2:
			var x := x0 + float(q) * PITCH
			draw_rect(Rect2(x - PIN.y * 0.5, body.position.y - PIN.x, PIN.y, PIN.x + 4), Color(pin_col, _dim))
			draw_rect(Rect2(x - PIN.y * 0.5, body.end.y - 4, PIN.y, PIN.x + 4), Color(pin_col, _dim))
	# shadow and black body
	draw_rect(Rect2(body.position + Vector2(7, 11), body.size), Color(0, 0, 0, 0.4 * _dim))
	_body.bg_color = Color(0.025, 0.027, 0.03, _dim)
	draw_style_box(_body, body)
	# the picture inside, tinted dark like the plastic until the chip is chosen
	var inner := body.grow(-13)
	var tint := 0.52 + 0.48 * g
	var tex: Texture2D = null
	if it["kind"] == "game":
		var a: Dictionary = _art.get(str(it["id"]), {})
		tex = a.get("wide", null) if bool(it["wide"]) else a.get("tall", null)
		if tex == null:
			tex = a.get("tall", null)
	if tex != null:
		var ts := tex.get_size()
		var fit := maxf(inner.size.x / ts.x, inner.size.y / ts.y)  # fills the window, cropped
		var src_w := inner.size.x / fit
		var src_h := inner.size.y / fit
		var src := Rect2((ts.x - src_w) * 0.5, (ts.y - src_h) * 0.5, src_w, src_h)
		draw_texture_rect_region(tex, inner, src, Color(tint, tint, tint * 1.02, _dim))
	else:
		draw_rect(inner, Color(0.07, 0.09, 0.1, _dim))
		if it["kind"] == "home":
			var ic := Icons.texture("home", Icons.svg_home(), 120)
			draw_texture_rect(ic, Rect2(inner.get_center() - Vector2(60, 60), Vector2(120, 120)), false, Color(1, 1, 1, tint * _dim))
		elif it["kind"] == "library":
			var ic2 := Icons.texture("library", Icons.svg_library(), 96)
			draw_texture_rect(ic2, Rect2(inner.get_center() - Vector2(48, 48), Vector2(96, 96)), false, Color(1, 1, 1, tint * _dim))
		else:
			draw_string(_font, inner.position + Vector2(10, inner.size.y * 0.5 + 10), str(it["label"]), HORIZONTAL_ALIGNMENT_CENTER, inner.size.x - 20, 26, Color(0.9, 0.95, 0.9, tint * _dim))
	# a glassy edge along the top, like moulded plastic
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 3)), Color(1, 1, 1, 0.1 * _dim))
	# pin-1 dot and the silkscreen name under the chip
	draw_circle(body.position + Vector2(20, 20), 5.5, Color(0.7, 0.72, 0.7, 0.8 * _dim))
	draw_string(_font, Vector2(body.position.x, body.end.y + 34), str(it["tag"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.96, 0.9, (0.4 + 0.4 * g) * _dim))
	# the chosen chip glows gold
	if g > 0.02:
		var pulse := 0.8 + 0.2 * sin(_t * 3.0)
		for r in 4:
			var grow := float(r) * 7.0 + 4.0
			_ring.border_color = Color(GOLD, (0.5 - float(r) * 0.11) * g * pulse * _dim)
			_ring.set_border_width_all(4)
			draw_style_box(_ring, body.grow(grow))
