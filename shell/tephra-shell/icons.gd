extends RefCounted
## Tephra's icon set. Every icon is an SVG drawn on a 48x48 grid, all original.
## texture(key, svg_body, px) renders and caches one at any pixel size.

const Themes = preload("res://themes.gd")

const DARK := "#121a24"  # used for details cut into white shapes
const ST := '<g fill="none" stroke="#fff" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round">'
const DIM := '<g fill="none" stroke="#fff" stroke-opacity="0.3" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round">'

static var _cache := {}

## Renders a 48x48 SVG body to a texture of the given pixel size (cached).
static func texture(key: String, body: String, px: int) -> Texture2D:
	var ck := "%s@%d" % [key, px]
	if _cache.has(ck):
		return _cache[ck]
	var inner := Themes.svg_ink(body)
	if Themes.id() == "frutiger" and _orb_color(key).a > 0.0:
		inner = _orb(body, _orb_color(key))  # the white icon sits on a glossy glass ball
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48" height="48">' + inner + '</svg>'
	var img := Image.new()
	if Themes.id() == "frutiger" and _orb_color(key).a > 0.0:
		# Glass balls have fine detail: drawn four times as big and shrunk, so the edges and gloss stay crisp.
		img.load_svg_from_string(svg, px * 4.0 / 48.0)
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	else:
		img.load_svg_from_string(svg, px / 48.0)
		if px <= 160 and not key.begins_with("padbig"):
			_theme_finish(img, px)
	var tex := ImageTexture.create_from_image(img)
	_cache[ck] = tex
	return tex

## Each theme's finish on the plain white icons (done once per icon, then cached):
## Miami: chunky pixels in cyan with a pink block shadow. PS2: pale blue with a blue glow. Volcanic: white-hot at the
## top cooling to ember orange. Gun metal: polished steel, bright at the top, dull grey below. Wave: a soft glow in
## the Wave colour. Sleek: graphite with a lighter top edge. Channels: a soft grey drop shadow. Tephra: as drawn.
static func _theme_finish(img: Image, px: int) -> void:
	var id := Themes.id()
	if not id in ["neon", "ps2", "volcanic", "gunmetal", "wave", "sleek", "channels", "gothic", "mold", "temple"]:
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if id == "neon":
		var block := maxi(2, px / 20)
		img.resize(maxi(1, w / block), maxi(1, h / block), Image.INTERPOLATE_BILINEAR)
		img.resize(w, h, Image.INTERPOLATE_NEAREST)
	elif id == "temple":
		# Crisp 16-colour pixel art: shrink, make every pixel fully on or off (no soft edges), then blow it up in whole
		# blocks, so the block size divides evenly and nothing is blurry.
		var block := maxi(2, int(round(float(px) / 24.0)))  # a 24 by 24 grid: enough cells for a clean shape
		var sw := maxi(1, w / block)
		var sh := maxi(1, h / block)
		img.resize(sw, sh, Image.INTERPOLATE_LANCZOS)
		for yy in sh:
			for xx in sw:
				var pc := img.get_pixel(xx, yy)
				img.set_pixel(xx, yy, Color(pc.r, pc.g, pc.b, 1.0 if pc.a > (0.2 if px < 64 else 0.33) else 0.0))
		img.resize(sw * block, sh * block, Image.INTERPOLATE_NEAREST)
		var canvas := Image.create(w, h, false, Image.FORMAT_RGBA8)
		canvas.blit_rect(img, Rect2i(0, 0, sw * block, sh * block), Vector2i((w - sw * block) / 2, (h - sh * block) / 2))
		img.copy_from(canvas)
	var src := img.duplicate() as Image
	var glow := Color(0, 0, 0, 0)
	match id:
		"ps2":
			glow = Color(0.18, 0.55, 1.0, 0.75)
		"wave":
			glow = Color(Themes.c("select"), 0.6)
	if glow.a > 0.0:
		_glow_under(img, src, maxi(2, px / 14), glow)
	var shadow_off := 0
	var shadow := Color(0, 0, 0, 0)
	if id == "neon":
		shadow_off = maxi(2, px / 20)
		shadow = Color("FF2E88")
	elif id == "gothic" or id == "mold":
		shadow_off = maxi(1, px / 36)
		shadow = Color(0, 0, 0, 0.8)
	elif id == "channels":
		shadow_off = maxi(1, px / 40)
		shadow = Color(0.45, 0.5, 0.6, 0.35)
	if shadow_off > 0:
		for y in range(h - 1, -1, -1):
			for x in range(w - 1, -1, -1):
				var sx := x - shadow_off
				var sy := y - shadow_off
				if sx < 0 or sy < 0:
					continue
				var a := src.get_pixel(sx, sy).a
				if a > 0.0 and img.get_pixel(x, y).a < 0.5:
					var under := img.get_pixel(x, y)
					img.set_pixel(x, y, Color(shadow, maxf(under.a, a * shadow.a)) if under.a < 0.05 else under.blend(Color(shadow, a * shadow.a)))
	for y in h:
		var t := float(y) / maxf(1.0, h - 1.0)
		for x in w:
			var c := src.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var lum := c.get_luminance()
			var col := c
			match id:
				"neon":
					col = Color("3FF5E6") if lum > 0.5 else c
				"ps2":
					col = Color("DCEBFF") if lum > 0.5 else c
				"volcanic":
					col = Color("FFF3E6").lerp(Color("FF7A2E"), t * t) if lum > 0.5 else c
				"gunmetal":
					col = Color("F2F4F6").lerp(Color("7E848B"), t) if lum > 0.5 else c
				"gothic":
					col = Color("FFFFFF").lerp(Color("B4B4BA"), t) if lum > 0.5 else c
				"mold":
					col = Color("E6DFCF").lerp(Color("8F8370"), t) if lum > 0.5 else c  # old paper, browning lower down
				"sleek":
					col = Color(c.r * (1.35 - 0.5 * t), c.g * (1.35 - 0.5 * t), c.b * (1.35 - 0.5 * t)).clamp() if lum < 0.5 else c
				_:
					continue
			var under2 := img.get_pixel(x, y)
			img.set_pixel(x, y, under2.blend(Color(col, c.a)) if under2.a > 0.0 and c.a < 1.0 else Color(col, c.a))

# A soft glow of the icon's shape, laid under it.
static func _glow_under(img: Image, src: Image, rad: int, col: Color) -> void:
	var small := src.duplicate() as Image
	var w := img.get_width()
	var h := img.get_height()
	small.resize(maxi(1, w / rad), maxi(1, h / rad), Image.INTERPOLATE_BILINEAR)
	small.resize(w, h, Image.INTERPOLATE_BILINEAR)
	for y in h:
		for x in w:
			var a := small.get_pixel(x, y).a * col.a
			if a > 0.01:
				img.set_pixel(x, y, Color(col, a).blend(src.get_pixel(x, y)))

## Frutiger Aero: these icons are drawn as glossy glass balls, each in its own colour (the icon stays white).
const ORBS := {
	"home": Color("2A8FE8"), "library": Color("3DBE4B"), "gear": Color("3F86DA"), "album": Color("19B5B0"),
	"power": Color("E0402B"), "quit": Color("E0402B"), "perf": Color("F0902A"), "palette": Color("8A45D1"),
	"info": Color("2A8FE8"), "check": Color("3DBE4B"), "no": Color("E0402B"), "sun": Color("F0A82A"),
	"bluetooth": Color("2A6FE8"),
}

## The ball's colour for an icon key (transparent: it gets no ball). Top-bar icons all share the blue and aqua
## family so the row reads as one set.
static func _orb_color(key: String) -> Color:
	if ORBS.has(key):
		return ORBS[key]
	if key.begins_with("wifi"):
		return Color("2A8FE8")
	if key.begins_with("pad_"):
		return Color("19B5B0")
	return Color(0, 0, 0, 0)

static func _orb(body: String, base: Color) -> String:
	var dk := base.darkened(0.45).to_html(false)
	var lo := base.lightened(0.5).to_html(false)
	var md := base.to_html(false)
	var rim := base.darkened(0.6).to_html(false)
	var s := '<defs><linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#%s"/><stop offset="0.55" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient>' % [dk, md, lo]
	s += '<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.9"/><stop offset="1" stop-color="#fff" stop-opacity="0.05"/></linearGradient>'
	s += '<radialGradient id="r" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#fff" stop-opacity="0.55"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs>'
	s += '<circle cx="24" cy="24" r="22" fill="url(#b)" stroke="#%s" stroke-width="1.6"/>' % rim
	s += '<ellipse cx="24" cy="39" rx="14" ry="7" fill="url(#r)"/>'
	s += '<g transform="translate(7.7 8.7) scale(0.68)">' + body + '</g>'
	s += '<ellipse cx="24" cy="12.5" rx="16.5" ry="9.5" fill="url(#g)"/>'
	return s

# ---------- Tephra shard ----------
## The shard from the boot logo (cut out of assets/shard_logo.png), at a given height.
## Falls back to a drawn shard if the logo can't be cut out.
static func shard(px: int) -> Texture2D:
	var ck := "shard_vec@%d" % px
	if _cache.has(ck):
		return _cache[ck]
	# The logo's shard redrawn as lines (the picture it came from is only ~220 pixels tall, which is what made
	# it soft). Drawn like this it is sharp at any size. Points were measured from the logo.
	const W := 124.0
	const H := 166.0
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="84 52 %d %d" width="%d" height="%d">' % [int(W), int(H), int(W), int(H)]
	svg += '<g fill="none" stroke="#C9CEDA" stroke-width="5.4" stroke-linecap="round" stroke-linejoin="round">'
	svg += '<path d="M149.5 57 L202 106.5 L182 212.5 L106 200 L89.5 116 Z"/>'
	svg += '<path d="M149.5 57 L139.5 137 L89.5 116 M139.5 137 L182 212.5"/></g></svg>'
	var img := Image.new()
	img.load_svg_from_string(svg, float(px) / H)
	var tex := ImageTexture.create_from_image(img)
	_cache[ck] = tex
	return tex

## The full boot logo (shard + TEPHRA), for the Home tile's title area.
static func full_logo() -> Texture2D:
	if _cache.has("full_logo"):
		return _cache["full_logo"]
	if not ResourceLoader.exists("res://assets/shard_logo.png"):
		return null
	var tex: Texture2D = load("res://assets/shard_logo.png")
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var used := img.get_used_rect()  # trim the empty space around the logo
		if used.size.x > 0 and used.size.y > 0:
			tex = ImageTexture.create_from_image(img.get_region(used))
	_cache["full_logo"] = tex
	return tex

# ---------- System ----------
static func svg_volume(level: int, muted: bool) -> String:
	var s := '<path d="M7 18 H15 L25 9 V39 L15 30 H7 Z" fill="#fff"/>'
	if muted:
		return s + ST + '<path d="M32 18 L43 30 M43 18 L32 30"/></g>'
	var waves := ['<path d="M30 19 A7 7 0 0 1 30 29"/>', '<path d="M34 14 A14 14 0 0 1 34 34"/>', '<path d="M38 9 A21 21 0 0 1 38 39"/>']
	for i in 3:
		s += (ST if i < level else DIM) + waves[i] + '</g>'
	return s

static func svg_wifi(bars: int, on: bool) -> String:
	var s := '<circle cx="24" cy="38" r="3" fill="#fff" %s/>' % ('' if bars > 0 else 'fill-opacity="0.3"')
	var radii := [10.0, 18.0, 26.0]
	for i in 3:
		var r: float = radii[i]
		var k := r * 0.7071
		s += (ST if i < bars else DIM) + '<path d="M%.1f %.1f A%.0f %.0f 0 0 1 %.1f %.1f"/></g>' % [24 - k, 38 - k, r, r, 24 + k, 38 - k]
	if not on:
		s += ST + '<path d="M9 9 L39 39"/></g>'
	return s

## A gauge: used by the control center's Performance card.
static func svg_perf() -> String:
	return ST + '<path d="M7 34 A18 18 0 1 1 41 34"/><path d="M24 30 L32 18"/></g><circle cx="24" cy="31" r="3" fill="#fff"/>'

## A photo: frame, sun and a hill. Used by the control center's Album card.
## Themes: an artist's palette with three paint dots.
static func svg_palette() -> String:
	return ST + '<path d="M24 5 C13 5 5 13 5 23 C5 33 13 42 23 42 C27 42 28 39 26 36 C24 33 26 30 30 30 H34 C39 30 43 26 43 21 C43 12 34 5 24 5 Z"/></g>' \
		+ '<circle cx="15" cy="20" r="3.2" fill="#fff"/><circle cx="23" cy="13" r="3.2" fill="#fff"/><circle cx="33" cy="16" r="3.2" fill="#fff"/>'

static func svg_bell() -> String:
	return ST + '<path d="M12 33 H36 L33 28 V21 A9 9 0 0 0 15 21 V28 Z"/><path d="M20 38 A4.5 4.5 0 0 0 28 38"/></g>'

static func svg_download() -> String:
	return ST + '<path d="M24 8 V29"/><path d="M15 21 L24 30 L33 21"/><path d="M9 39 H39"/></g>'

static func svg_album() -> String:
	return ST + '<rect x="5" y="9" width="38" height="30" rx="5"/><path d="M5 33 L16 22 L25 31 L31 25 L43 36"/></g><circle cx="32" cy="17" r="3.2" fill="#fff"/>'

static func svg_mods() -> String:
	return ST + '<path d="M7 14 H41 M7 24 H41 M7 34 H41"/></g><circle cx="17" cy="14" r="4.2" fill="#fff"/><circle cx="31" cy="24" r="4.2" fill="#fff"/><circle cx="20" cy="34" r="4.2" fill="#fff"/>'

static func svg_battery(level: float, charging: bool) -> String:
	var s := ST + '<rect x="4" y="14" width="36" height="20" rx="4"/></g><rect x="41" y="20" width="4" height="8" rx="1.5" fill="#fff"/>'
	s += '<rect x="8" y="18" width="%.1f" height="12" rx="1.5" fill="#fff" fill-opacity="%s"/>' % [28.0 * clampf(level, 0.0, 1.0), "0.4" if charging else "1"]
	if charging:
		s += '<path d="M25 8 L15 26 H23 L20 40 L31 21 H23 Z" fill="#fff" stroke="%s" stroke-width="2" stroke-linejoin="round"/>' % DARK
	return s

## A house: roof, walls and a door gap. Used for the Home tile and the system-button glyph.
static func svg_home() -> String:
	return ST + '<path d="M5 23 L24 6 L43 23"/><path d="M10 20 V41 H20 V29 H28 V41 H38 V20"/></g>'

static func svg_power() -> String:
	return ST + '<path d="M15 14 A14 14 0 1 0 33 14"/><path d="M24 7 V23"/></g>'

## Settings gear: a chunky six-tooth cog. Each tooth is a four-point shape
## (two points on the body, two on the tip); the points are placed with sin/cos.
static func svg_gear() -> String:
	var pts := ""
	for i in 6:
		var a := TAU * i / 6.0
		for p in [[-0.28, 15.0], [-0.18, 20.0], [0.18, 20.0], [0.28, 15.0]]:
			var ang: float = a + p[0]
			pts += "%.2f,%.2f " % [24 + p[1] * cos(ang), 24 + p[1] * sin(ang)]
	return ST + '<polygon points="%s"/><circle cx="24" cy="24" r="6.5"/></g>' % pts.strip_edges()

## Weather icons: sun, moon, partly, cloud, fog, rain, snow, storm. Original line drawings.
static func svg_weather(kind: String) -> String:
	const CLOUD := '<path d="M14 36 H34 A8 8 0 0 0 35 20 A11 11 0 0 0 14.5 22 A7 7 0 0 0 14 36 Z"/>'
	match kind:
		"sun":
			var rays := ""
			for i in 8:
				var a := i * PI / 4.0
				rays += '<path d="M%.1f %.1f L%.1f %.1f"/>' % [24 + cos(a) * 13, 24 + sin(a) * 13, 24 + cos(a) * 19, 24 + sin(a) * 19]
			return ST + '<circle cx="24" cy="24" r="8"/>' + rays + '</g>'
		"moon":
			return ST + '<path d="M32 8 A17 17 0 1 0 40 30 A14 14 0 0 1 32 8 Z"/></g>'
		"partly":
			return ST + '<circle cx="17" cy="16" r="6"/><path d="M17 4 V6 M5 16 H7 M8.5 7.5 L10 9 M25.5 7.5 L24 9"/><path d="M17 40 H35 A7 7 0 0 0 36 26 A10 10 0 0 0 18 28 A6 6 0 0 0 17 40 Z"/></g>'
		"cloud":
			return ST + CLOUD + '</g>'
		"fog":
			return ST + '<path d="M8 16 H40 M12 25 H44 M8 34 H36"/></g>'
		"rain":
			return ST + '<path d="M14 28 H34 A7 7 0 0 0 35 14 A10 10 0 0 0 15 16 A6 6 0 0 0 14 28 Z"/><path d="M17 34 L14 42 M26 34 L23 42 M35 34 L32 42"/></g>'
		"snow":
			return ST + '<path d="M14 28 H34 A7 7 0 0 0 35 14 A10 10 0 0 0 15 16 A6 6 0 0 0 14 28 Z"/><path d="M16 36 V36.1 M25 40 V40.1 M34 36 V36.1 M20.5 33.5 V33.6"/></g>'
		"storm":
			return ST + '<path d="M14 28 H34 A7 7 0 0 0 35 14 A10 10 0 0 0 15 16 A6 6 0 0 0 14 28 Z"/><path d="M26 28 L20 37 H28 L22 46"/></g>'
	return ST + CLOUD + '</g>'

static func svg_quit() -> String:
	return ST + '<path d="M21 9 H10 V39 H21"/><path d="M18 24 H41 M33 16 L41 24 L33 32"/></g>'

## Brightness: the same sun at four strengths (0 darkest ... 3 brightest): a small bare disc, then more and longer rays.
static func svg_sun_level(level: int) -> String:
	var s := '<circle cx="24" cy="24" r="%.1f" fill="#fff"/>' % [5.0 + 1.5 * level] + ST
	var rays: int = [0, 4, 8, 8][level]
	for i in rays:
		var a: float = i * TAU / maxi(rays, 1)
		var r0 := 13.0 + 0.5 * level
		var r1 := r0 + 3.0 + 2.0 * level
		s += '<path d="M%.1f %.1f L%.1f %.1f"/>' % [24 + cos(a) * r0, 24 + sin(a) * r0, 24 + cos(a) * r1, 24 + sin(a) * r1]
	return s + '</g>'

static func svg_library() -> String:
	return '<rect x="6" y="6" width="15" height="15" rx="3" fill="#fff"/><rect x="27" y="6" width="15" height="15" rx="3" fill="#fff"/>' \
		+ '<rect x="6" y="27" width="15" height="15" rx="3" fill="#fff"/><rect x="27" y="27" width="15" height="15" rx="3" fill="#fff" fill-opacity="0.45"/>'

static func svg_mic(muted: bool) -> String:
	var s := '<rect x="18" y="5" width="12" height="22" rx="6" fill="#fff"/>' + ST + '<path d="M11 22 A13 13 0 0 0 37 22 M24 35 V43 M17 43 H31"/></g>'
	if muted:
		s += '<path d="M8 8 L40 40" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % DARK + ST + '<path d="M8 8 L40 40"/></g>'
	return s

# ---------- Controllers ----------
# Every pad is ONE slim outline (a gently arched top, a narrow waist and two rounded grips that curve down and
# outwards), with the details laid out the way a real pad has them: PlayStation pads have a touchpad on top,
# two sticks side by side below it, the D-pad on the left and the four buttons on the right; Xbox and Nintendo pads
# have the left stick high on the left, the D-pad low in the middle, the right stick low on the right and the buttons
# high on the right. The same numbers (pad_layout) are used by the Controller test screen, so everything that lights
# up there sits exactly on the icon. All coordinates are in a 48 x 48 box.
static func pad_layout(model: String) -> Dictionary:
	var common := {
		"face_r": 1.35, "dpad_w": 1.05, "dpad_tip": 3.7,  # the D-pad: half an arm's width, centre to tip
		"l1": Rect2(9.5, 7.6, 8.0, 2.2), "r1": Rect2(30.5, 7.6, 8.0, 2.2),
		"l2": Rect2(10.0, 4.0, 7.0, 2.4), "r2": Rect2(31.0, 4.0, 7.0, 2.4),
	}
	match model:
		"ds5", "ps", "ds4":
			common.merge({
				"shape": "ps", "touch": Rect2(17.8, 12.4 if model == "ds4" else 12.0, 12.4, 6.0 if model == "ds4" else 6.4),
				"stick_l": Vector2(17.4, 26.2), "stick_r": Vector2(30.6, 26.2), "stick_r_px": 3.2,
				"dpad": Vector2(11.4, 18.8), "face": Vector2(36.6, 18.8), "face_gap": 2.9,
				"select": Vector2(15.0, 14.4), "start": Vector2(33.0, 14.4), "guide": Vector2(24.0, 22.6),
				"lightbar": model == "ds4",
			}, true)
			return common
		_:  # "xbox", "nintendo", "generic": left stick high, d-pad low, right stick low, face buttons high
			common.merge({
				"shape": "xbox", "touch": Rect2(),
				"stick_l": Vector2(14.0, 18.2), "stick_r": Vector2(29.6, 26.2), "stick_r_px": 3.2,
				"dpad": Vector2(18.6, 26.2), "face": Vector2(35.4, 18.2), "face_gap": 2.9,
				"select": Vector2(20.8, 17.6), "start": Vector2(27.2, 17.6), "guide": Vector2(24.0, 13.8),
				"lightbar": false,
			}, true)
			return common

## The D-pad's pieces in picture units: [name, rect] for the centre and the four arms (the arms overlap the centre, so
## the cross has no seams). The Controller test lights the same rects.
static func dpad_parts(lay: Dictionary) -> Array:
	var d: Vector2 = lay["dpad"]
	var w: float = lay["dpad_w"]
	var e: float = lay["dpad_tip"]
	return [
		["centre", Rect2(d.x - w, d.y - w, w * 2.0, w * 2.0)],
		# the arms start where the centre square ends, so no two parts overlap
		["Up", Rect2(d.x - w, d.y - e, w * 2.0, e - w)],
		["Down", Rect2(d.x - w, d.y + w, w * 2.0, e - w)],
		["Left", Rect2(d.x - e, d.y - w, e - w, w * 2.0)],
		["Right", Rect2(d.x + w, d.y - w, e - w, w * 2.0)],
	]

## A small arrow near the tip of each arm, pointing outwards.
static func dpad_arrows(lay: Dictionary) -> Array:
	var d: Vector2 = lay["dpad"]
	var w: float = lay["dpad_w"]
	var e: float = lay["dpad_tip"]
	var a := w * 0.55
	var out: Array = []
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var side := Vector2(dir.y, dir.x)
		var tip: Vector2 = d + dir * (e - 0.55)
		var base: Vector2 = d + dir * (e - 0.55 - a * 1.2)
		out.append([tip, base + side * a, base - side * a])
	return out

## The white body, as one smooth path. Used by the icons and, big, by the Controller test.
static func pad_silhouette() -> String:
	return '<path fill="#fff" d="M13 10.5 C16 9.5 32 9.5 35 10.5 C40 11 43.5 15 45 22 C46.2 28 46.4 34 43.6 37.2 ' \
		+ 'C41.2 40 37.5 39 35.6 35.4 C34 32.6 32.5 30.8 29.5 30.8 L18.5 30.8 C15.5 30.8 14 32.6 12.4 35.4 ' \
		+ 'C10.5 39 6.8 40 4.4 37.2 C1.6 34 1.8 28 3 22 C4.5 15 8 11 13 10.5 Z"/>'

static func svg_pad(family: String) -> String:
	if family == "ds5":
		family = "ps"
	var lay := pad_layout(family)
	var body := pad_silhouette()
	var dk := DARK
	if bool(lay["lightbar"]):
		body += '<rect x="19" y="10.9" width="10" height="1.1" rx="0.55" fill="%s"/>' % dk
	if lay["touch"] != Rect2():
		var t: Rect2 = lay["touch"]
		body += '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="1.8" fill="%s"/>' % [t.position.x, t.position.y, t.size.x, t.size.y, dk]
	# Sticks: a dark ring with a white cap, so they read as sticks and not as holes.
	var r: float = lay["stick_r_px"]
	for k in ["stick_l", "stick_r"]:
		var c: Vector2 = lay[k]
		body += '<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/><circle cx="%.2f" cy="%.2f" r="%.2f" fill="#fff" fill-opacity="0.22"/>' % [c.x, c.y, r, dk, c.x, c.y, r * 0.55]
	# D-pad: a clear plus sign, four arms with rounded tips and a small arrow on each, like a real pad's cross.
	for rr in dpad_parts(lay):
		var q: Rect2 = rr[1]
		body += '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="0.35" fill="%s"/>' % [q.position.x, q.position.y, q.size.x, q.size.y, dk]
	for tri in dpad_arrows(lay):
		body += '<path d="M%.2f %.2f L%.2f %.2f L%.2f %.2f Z" fill="#fff" fill-opacity="0.35"/>' % [tri[0].x, tri[0].y, tri[1].x, tri[1].y, tri[2].x, tri[2].y]
	# Face buttons: four dots in a diamond.
	var f: Vector2 = lay["face"]
	var g: float = lay["face_gap"]
	for o in [Vector2(0, g), Vector2(g, 0), Vector2(-g, 0), Vector2(0, -g)]:
		body += '<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>' % [f.x + o.x, f.y + o.y, lay["face_r"], dk]
	# Small buttons.
	for k in ["select", "start"]:
		var c2: Vector2 = lay[k]
		body += '<circle cx="%.2f" cy="%.2f" r="0.7" fill="%s"/>' % [c2.x, c2.y, dk]
	var gd: Vector2 = lay["guide"]
	body += '<circle cx="%.2f" cy="%.2f" r="1.1" fill="%s"/>' % [gd.x, gd.y, dk]
	return body

# ---------- Info badges ----------
static func svg_moon() -> String:
	return ST + '<path d="M33 31 A15 15 0 1 1 20 9 A12 12 0 0 0 33 31 Z"/></g>'

static func svg_refresh() -> String:
	return ST + '<path d="M38 24 A14 14 0 1 1 33.5 13.5"/><path d="M36 6 V15 H27"/></g>'

static func svg_restart() -> String:
	return ST + '<path d="M38 24 A14 14 0 1 1 33.5 13.5"/><path d="M36 6 V15 H27"/><path d="M24 17 V25"/></g>'

static func svg_close() -> String:
	return ST + '<path d="M13 13 L35 35 M35 13 L13 35"/></g>'

static func svg_bluetooth() -> String:
	return ST + '<path d="M13 16 L35 33 L24 42 V6 L35 15 L13 32"/></g>'

static func svg_check() -> String:
	return '<circle cx="24" cy="24" r="20" fill="#fff"/><path d="M14 24.5 L21 31.5 L34 17" fill="none" stroke="%s" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>' % DARK

static func svg_info() -> String:
	return '<circle cx="24" cy="24" r="20" fill="#fff"/><circle cx="24" cy="15" r="2.8" fill="%s"/><path d="M24 22 V34" stroke="%s" stroke-width="4.5" stroke-linecap="round"/>' % [DARK, DARK]

static func svg_no() -> String:
	return ST + '<circle cx="24" cy="24" r="18"/><path d="M11.5 36.5 L36.5 11.5"/></g>'

## Files: a folder with a tab, a sheet of paper with a folded corner, and a drive (a slab with a light).
static func svg_globe() -> String:
	return ST + '<circle cx="24" cy="24" r="17"/><ellipse cx="24" cy="24" rx="7.5" ry="17"/><path d="M7 24 H41 M10 15 H38 M10 33 H38"/></g>'

static func svg_folder() -> String:
	return ST + '<path d="M5 15 A4 4 0 0 1 9 11 H19 L23 16 H39 A4 4 0 0 1 43 20 V35 A4 4 0 0 1 39 39 H9 A4 4 0 0 1 5 35 Z"/></g>'

static func svg_trash() -> String:
	return ST + '<path d="M10 13 H38 M18 13 V9 H30 V13 M13 13 L15 41 H33 L35 13 M20 20 V34 M28 20 V34"/></g>'

## Folders in Home with a known purpose get their own picture (Music, Pictures, Downloads...).
static func svg_folder_named(name: String) -> String:
	var base := '<path d="M5 15 A4 4 0 0 1 9 11 H19 L23 16 H39 A4 4 0 0 1 43 20 V35 A4 4 0 0 1 39 39 H9 A4 4 0 0 1 5 35 Z"/>'
	match name.to_lower():
		"music":
			return ST + base + '<path d="M21 33 V22 L30 20 V31"/></g><circle cx="19" cy="33" r="2.6" fill="#fff"/><circle cx="28" cy="31" r="2.6" fill="#fff"/>'
		"pictures":
			return ST + base + '<path d="M13 34 L20 26 L25 31 L29 27 L36 34"/></g><circle cx="31" cy="22" r="2.4" fill="#fff"/>'
		"downloads":
			return ST + base + '<path d="M24 21 V33 M19 28 L24 33 L29 28"/></g>'
		"documents":
			return ST + base + '<path d="M16 24 H32 M16 29 H32 M16 34 H26"/></g>'
		"videos":
			return ST + base + '<path d="M20 22 L30 28 L20 34 Z"/></g>'
		"desktop":
			return ST + base + '<rect x="14" y="21" width="20" height="12" rx="2"/></g>'
		"games":
			return ST + base + '<path d="M14 30 H22 M18 26 V34 M29 28 H30 M33 31 H34"/></g>'
	return ST + base + '</g>'

static func svg_drive() -> String:
	return ST + '<rect x="5" y="15" width="38" height="18" rx="4"/></g><circle cx="35" cy="24" r="2.6" fill="#fff"/>'

## File icons by kind (Files in the control center): a page with a small picture of what is inside.
static func svg_file_kind(kind: String) -> String:
	var page := '<path d="M12 5 H28 L37 14 V43 H12 Z"/><path d="M28 5 V14 H37"/>'
	match kind:
		"image":
			return ST + page + '<path d="M16 37 L21 30 L25 34 L28 31 L33 37"/><circle cx="19.5" cy="23" r="2.2"/></g>'
		"video":
			return ST + page + '<path d="M20 22 L30 28.5 L20 35 Z"/></g>'
		"audio":
			return ST + page + '<path d="M22 35 V22 L31 20 V32"/><circle cx="19.5" cy="35" r="2.6"/><circle cx="28.5" cy="32" r="2.6"/></g>'
		"archive":
			return ST + page + '<path d="M22 9 H25 M22 14 H25 M22 19 H25 M22 24 H25"/><rect x="20" y="28" width="8" height="8" rx="1.5"/></g>'
		"doc":
			return ST + page + '<path d="M17 22 H32 M17 28 H32 M17 34 H27"/></g>'
		"code":
			return ST + page + '<path d="M21 23 L16.5 28.5 L21 34 M28 23 L32.5 28.5 L28 34"/></g>'
		"disc":
			return ST + '<circle cx="24" cy="24" r="17"/><circle cx="24" cy="24" r="4"/><path d="M24 11 A13 13 0 0 1 37 24"/></g>'
		"app":
			return ST + '<rect x="7" y="7" width="34" height="34" rx="9"/><path d="M20 17 L31 24 L20 31 Z"/></g>'
	return ST + page + '</g>'

## "Back" in Files while moving something: a folder with an arrow pointing up out of it.
static func svg_file_up() -> String:
	return ST + '<path d="M5 15 A4 4 0 0 1 9 11 H19 L23 16 H39 A4 4 0 0 1 43 20 V35 A4 4 0 0 1 39 39 H9 A4 4 0 0 1 5 35 Z"/><path d="M24 34 V22 M18.5 27 L24 21.5 L29.5 27"/></g>'

## Bluetooth device icons (the Bluetooth screen): what kind of thing each device is.
static func svg_bt_kind(kind: String) -> String:
	match kind:
		"headphones":
			return ST + '<path d="M9 30 V24 A15 15 0 0 1 39 24 V30"/><rect x="7" y="28" width="8" height="12" rx="3"/><rect x="33" y="28" width="8" height="12" rx="3"/></g>'
		"earbuds":
			return ST + '<path d="M14 12 A6 6 0 0 1 20 18 V34"/><circle cx="14" cy="17" r="5"/><path d="M34 12 A6 6 0 0 0 28 18 V34"/><circle cx="34" cy="17" r="5"/></g>'
		"speaker":
			return ST + '<rect x="12" y="5" width="24" height="38" rx="5"/><circle cx="24" cy="29" r="7"/><circle cx="24" cy="14" r="2.5"/></g>'
		"keyboard":
			return ST + '<rect x="4" y="14" width="40" height="22" rx="4"/><path d="M10 21 H12 M17 21 H19 M24 21 H26 M31 21 H33 M38 21 H38.5 M10 28 H12 M38 28 H38.5 M17 30 H31"/></g>'
		"mouse":
			return ST + '<rect x="14" y="6" width="20" height="36" rx="10"/><path d="M24 6 V18"/></g>'
		"phone":
			return ST + '<rect x="14" y="4" width="20" height="40" rx="4"/><path d="M21 38 H27"/></g>'
		"computer":
			return ST + '<rect x="8" y="9" width="32" height="22" rx="2.5"/><path d="M4 38 H44 M8 31 L4 38 M40 31 L44 38"/></g>'
		"tv":
			return ST + '<rect x="4" y="8" width="40" height="26" rx="3"/><path d="M17 41 H31 M24 34 V41"/></g>'
		"watch":
			return ST + '<rect x="13" y="13" width="22" height="22" rx="6"/><path d="M17 13 L19 5 H29 L31 13 M17 35 L19 43 H29 L31 35 M24 19 V24 L28 27"/></g>'
	return svg_bluetooth()
