extends Control
## The Planet theme's Home: the games stand in an arc on a ring around a spinning world. Only the top of the world
## shows, at the bottom of the screen. Left / Right turn the world and bring the next game round (five to seven are in
## view); A plays, Y opens the game's page, Up goes to the top bar. The world itself is drawn by a shader (a
## sphere with oceans, land, moving clouds and a glowing air rim, tinted by the colours of the chosen game's cover).
## It follows the same hooks home.gd uses for the other alternative Homes (xmb.gd, neon.gd).

const Themes = preload("res://themes.gd")
const Haptics = preload("res://haptics.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Icons = preload("res://icons.gd")

const STEP := 0.21          # how far round the ring (radians) the next game stands
const REACH := 3.4          # places either side of the chosen game that are drawn
const COVER := Vector2(214, 321)   # a cover at a 1440 high screen; everything scales with the height

const PLANET_SHADER := """
shader_type canvas_item;
uniform float rot = 0.0;
uniform float r_planet = 0.6;
uniform vec3 tint = vec3(0.35, 0.6, 1.0);
uniform float dim = 1.0;

float h3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * n3(p);
		p = p * 2.02 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}
vec3 spin(vec3 n, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * n.x - s * n.y, s * n.x + c * n.y, n.z);
}
void fragment() {
	vec2 uv = (UV - 0.5) * 2.0 / r_planet;
	float r = length(uv);
	vec3 air = mix(vec3(0.35, 0.6, 1.0), tint, 0.7);
	float halo = exp(-(r - 1.0) * 5.5) * 0.6 * (1.0 - smoothstep(1.25, 1.6, r));
	vec4 col = vec4(air, halo * step(1.0, r));
	if (r < 1.02) {
		float z = sqrt(max(1.0 - r * r, 0.0));
		vec3 N = vec3(uv, z);
		vec3 P = spin(N, rot);
		float h = fbm(P * 2.4 + vec3(3.0));
		float land = smoothstep(0.50, 0.53, h);
		vec3 ocean = mix(vec3(0.02, 0.07, 0.20), vec3(0.06, 0.30, 0.46), smoothstep(0.28, 0.5, h));
		vec3 ground = mix(vec3(0.16, 0.42, 0.20), vec3(0.50, 0.40, 0.28), smoothstep(0.55, 0.72, h));
		ground = mix(ground, vec3(0.92, 0.95, 1.0), smoothstep(0.78, 0.9, h));
		vec3 surf = mix(ocean, ground, land);
		surf = mix(surf, surf * (0.6 + 0.8 * tint), 0.25);
		vec3 Q = spin(N, rot * 1.3 + 0.6);
		float cl = smoothstep(0.52, 0.80, fbm(Q * 3.4 + vec3(7.0, 1.0, 4.0)));
		surf = mix(surf, vec3(1.0), cl * 0.85);
		vec3 L = normalize(vec3(-0.35, -0.55, 0.75));
		float d = max(dot(N, L), 0.0);
		float lit = 0.10 + 0.95 * d;
		float spec = pow(max(dot(reflect(-L, N), vec3(0.0, 0.0, 1.0)), 0.0), 26.0) * (1.0 - land) * (1.0 - cl) * 0.55;
		float rim = pow(1.0 - z, 2.4);
		vec3 c = surf * lit + vec3(spec) + air * rim * (0.35 + 0.65 * d) * 1.1;
		float edge = smoothstep(1.0, 0.985, r);
		col = mix(col, vec4(c, 1.0), edge);
	}
	col.rgb *= dim;
	COLOR = col;
}
"""

var home  # home.gd

var _items: Array = []      # {label, sub, kind: game | home | library | none, id, gi, g}
var _sel := 0
var _sel_f := 1.0
var _art := {}              # game id -> Texture2D (or null: no cover)
var _tints := {}            # game id -> Color from its cover
var _asked := {}
var _holders: Array = []
var _logos := {}            # game id -> logo Texture2D
var _logo_asked := {}
var _t := 0.0
var _dim := 1.0
var _dim_to := 1.0
var _tint := Color(0.35, 0.6, 1.0)
var _planet: ColorRect
var _mat: ShaderMaterial
var _font: Font
var _hints: HBoxContainer
var _glow: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_font = Themes.font()
	if _font == null:
		_font = ThemeDB.fallback_font
	var sh := Shader.new()
	sh.code = PLANET_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_planet = ColorRect.new()
	_planet.material = _mat
	_planet.show_behind_parent = true  # the covers and words are drawn over the world
	_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_planet)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 128
	_glow.height = 128
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
	_hints.offset_top = -120
	_hints.offset_bottom = -60
	TephraGlyphs.fill(_hints, [["dpad_h", "Turn the world"], ["accept", "Play"], ["north", "Game page"]], 28)
	rebuild()
	_sel_f = float(_sel)

# ---------- Building ----------
func forget_art(id: String) -> void:
	_art.erase(id)
	_asked.erase(id)
	_tints.erase(id)

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
			_items.append({"label": str(g["title"]), "sub": "", "kind": "game", "id": str(g["id"]), "gi": i, "g": g})
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
		_items.append({"label": str(g["title"]), "sub": "", "kind": "game", "id": id, "gi": gi, "g": g})
	_items.append({"label": "Library", "sub": "Everything you own", "kind": "library"})
	if keep != "":
		for i in _items.size():
			if _items[i].get("id", "") == keep:
				_sel = i
	_sel = clampi(_sel, 0, _items.size() - 1)
	if keep == "":
		_sel = 0  # opens on Home
	_ensure_art()

## Covers for the games near the chosen one (a few either side), asked for once.
func _ensure_art() -> void:
	for d in range(-5, 6):
		var i := _sel + d
		if i < 0 or i >= _items.size() or _items[i].get("kind", "") != "game":
			continue
		var id := str(_items[i]["id"])
		if _asked.has(id):
			continue
		_asked[id] = true
		var pic := TextureRect.new()
		pic.visible = false
		add_child(pic)
		_holders.append(pic)
		home.load_cover(id, pic, func() -> void:
			if is_instance_valid(pic) and pic.texture != null:
				_art[id] = pic.texture
				_tints[id] = _cover_colour(pic.texture), func() -> void:
			_art[id] = null)
	_ensure_logo()

func _ensure_logo() -> void:
	var it := _cur()
	if it.get("kind", "") != "game":
		return
	var id := str(it["id"])
	if _logo_asked.has(id):
		return
	_logo_asked[id] = true
	var path: String = home._find_local_art(id, "logo", "png")
	if path == "" and FileAccess.file_exists("user://art/%s_logo.png" % id):
		path = "user://art/%s_logo.png" % id
	if path == "":
		return
	home._tex_async(path, func(t: Texture2D) -> void:
		if t != null:
			_logos[id] = t)

## The colour that covers most of a picture (a quick 8 by 12 look), a little brightened, for the air round the world.
func _cover_colour(tex: Texture2D) -> Color:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return Color(0.35, 0.6, 1.0)
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.resize(8, 12, Image.INTERPOLATE_BILINEAR)
	var sum := Color(0, 0, 0)
	var w := 0.0
	for y in 12:
		for x in 8:
			var c := img.get_pixel(x, y)
			var k := 0.15 + c.s * c.v
			sum += Color(c.r * k, c.g * k, c.b * k)
			w += k
	if w <= 0.0:
		return Color(0.35, 0.6, 1.0)
	var out := Color(sum.r / w, sum.g / w, sum.b / w)
	return out.lerp(Color(1, 1, 1), 0.2)

# ---------- Focus (the hooks home.gd uses) ----------
func _cur() -> Dictionary:
	return _items[_sel] if _sel >= 0 and _sel < _items.size() else {}

## Holding PS: back onto the Home icon.
## A little arrow that bobs: Down opens the Home page.
func _down_arrow(at: Vector2, k: float) -> void:
	var y := at.y + 4.0 * k * sin(_t * 3.0)
	var w := 24.0 * k
	var col := Color(1, 1, 1, 0.8 * _dim)
	draw_polyline(PackedVector2Array([Vector2(at.x - w, y), Vector2(at.x, y + w * 0.7), Vector2(at.x + w, y)]), col, maxf(4.0 * k, 3.0), true)

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

func move(dir: Vector2i) -> String:
	if dir.x != 0 and not _items.is_empty():
		_sel = posmod(_sel + dir.x, _items.size())
		home.sfx.play("tick")
		Haptics.select()
		_ensure_art()
		return ""
	if dir.y < 0:
		if home.nav != null and home.nav.repeating:
			return ""
		return "up"
	if dir.y > 0 and _cur().get("kind", "") == "home" and not (home.nav != null and home.nav.repeating):
		home.sfx.play("tick")
		home.open_home_page()  # Down on the Home icon: your stats and trophies
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
				home.library.open_game(it["g"], _art.get(str(it["id"]), null))
		"home":
			home.open_home_page()
		"library":
			home.library.open(home.clock_label.get_global_rect())
		_:
			Haptics.tick()

## Y on a game: its page.
func info_selected(_squeeze := true) -> void:
	var it := _cur()
	if it.get("kind", "") == "game":
		home.sfx.play("options")
		home.library.open_game(it["g"], _art.get(str(it["id"]), null))

# ---------- Drawing ----------
func _process(delta: float) -> void:
	if not is_visible_in_tree() or home.library.is_open:
		return
	_t += delta
	_dim = lerpf(_dim, _dim_to, 1.0 - exp(-delta * 9.0))
	_sel_f = lerpf(_sel_f, float(_sel), 1.0 - exp(-delta * 9.0))
	if absf(_sel_f - float(_sel)) < 0.002:
		_sel_f = float(_sel)
	var it := _cur()
	var want := Color(0.35, 0.6, 1.0)
	if it.get("kind", "") == "game" and _tints.has(str(it["id"])):
		want = _tints[str(it["id"])]
	_tint = _tint.lerp(want, 1.0 - exp(-delta * 3.0))
	var H := size.y
	var R := H * 0.9
	var ro := R + H * 0.12
	var cy := H * 0.5 + ro
	var span := R * 2.0 / 0.6
	_planet.position = Vector2(size.x * 0.5 - span * 0.5, cy - span * 0.5)
	_planet.size = Vector2(span, span)
	_mat.set_shader_parameter("rot", -_sel_f * STEP + _t * 0.012)
	_mat.set_shader_parameter("tint", Vector3(_tint.r, _tint.g, _tint.b))
	_mat.set_shader_parameter("dim", _dim)
	queue_redraw()

func _shadow_text(s: String, p: Vector2, fs: int, col: Color, w: float) -> void:
	draw_string(_font, p + Vector2(2, 3), s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0, 0, 0, col.a * 0.5))
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)

func _draw() -> void:
	if _items.is_empty():
		return
	var H := size.y
	var k := H / 1440.0
	var R := H * 0.9
	var ro := R + H * 0.12
	var c := Vector2(size.x * 0.5, H * 0.5 + ro)
	var order: Array = []
	for i in _items.size():
		var d := float(i) - _sel_f
		if absf(d) <= REACH:
			order.append(i)
	order.sort_custom(func(a, b): return absf(float(a) - _sel_f) > absf(float(b) - _sel_f))  # far first, the chosen one on top
	for i in order:
		var d := float(i) - _sel_f
		var th := d * STEP
		var p := c + Vector2(sin(th), -cos(th)) * ro
		var near := clampf(1.0 - absf(d), 0.0, 1.0)
		var a := clampf(1.0 - (absf(d) - 2.5) / 0.9, 0.0, 1.0) * _dim
		if a <= 0.01:
			continue
		var s := (1.0 + 0.32 * near) * k
		var w := COVER.x * s
		var h := COVER.y * s
		var it: Dictionary = _items[i]
		var rect := Rect2(-w * 0.5, -h * 0.5, w, h)
		# a soft light under the chosen one
		if near > 0.05:
			var gr := h * 0.95
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_texture_rect(_glow, Rect2(p - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(_tint, 0.35 * near * _dim))
		draw_set_transform(p, th, Vector2.ONE)
		var tex: Texture2D = _art.get(str(it.get("id", "")), null) if it.get("kind", "") == "game" else null
		if tex != null:
			draw_texture_rect(tex, rect, false, Color(1, 1, 1, a))
		else:
			var tile: Color = Themes.c("home_tile") if it.get("kind", "") != "game" else Themes.c("tile")
			draw_rect(rect, Color(tile, a))
			if it.get("kind", "") == "home":
				var ic := Icons.texture("home", Icons.svg_home(), 120)
				draw_texture_rect(ic, Rect2(-60 * s, -60 * s, 120 * s, 120 * s), false, Color(1, 1, 1, a))
			elif it.get("kind", "") == "library":
				var ic2 := Icons.texture("library", Icons.svg_library(), 96)
				draw_texture_rect(ic2, Rect2(-48 * s, -48 * s, 96 * s, 96 * s), false, Color(1, 1, 1, a))
			else:
				var lbl := str(it["label"])
				draw_string(_font, Vector2(-w * 0.5 + 10 * s, 8 * s), lbl, HORIZONTAL_ALIGNMENT_CENTER, w - 20 * s, int(30 * s), Color(Themes.c("text"), a))
		if near > 0.4:
			draw_rect(rect.grow(2), Color(1, 1, 1, near * a), false, 4.0 * k)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the chosen one's name (or logo) on the world below
	var cur := _cur()
	var base := H * 0.5 + COVER.y * k * 0.66 + H * 0.085
	var label := str(cur.get("label", ""))
	var logo: Texture2D = _logos.get(str(cur.get("id", "")), null) if cur.get("kind", "") == "game" else null
	var sub_y := base + 70 * k
	if logo != null:
		var ls := logo.get_size()
		var f := minf(H * 0.5 / ls.x * 1.0, H * 0.11 / ls.y)
		var lw := ls.x * f
		var lh := ls.y * f
		sub_y = base + lh * 0.5 + 44 * k  # always under the logo, whatever its height
		draw_texture_rect(logo, Rect2(c.x - lw * 0.5, base - lh * 0.5, lw, lh), false, Color(1, 1, 1, _dim))
	else:
		_shadow_text(label, Vector2(c.x - size.x * 0.4, base + 14 * k), int(54 * k), Color(1, 1, 1, _dim), size.x * 0.8)
	var sub := str(cur.get("sub", ""))
	if cur.get("kind", "") == "game":
		sub = ("Press %s to play" % TephraGlyphs.btn("accept")) if int(cur["gi"]) >= 0 else ("Not installed. Press %s to open its page" % TephraGlyphs.btn("accept"))
	if sub != "":
		_shadow_text(sub, Vector2(c.x - size.x * 0.4, sub_y), int(26 * k), Color(0.85, 0.9, 1.0, 0.8 * _dim), size.x * 0.8)
	if cur.get("kind", "") == "home":
		_down_arrow(Vector2(c.x, base + 112 * k), k)
