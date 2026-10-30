extends RefCounted
## How the game page (Library > a game) and the game's options menu look in each theme: the buttons, the panel,
## the cover's frame, the storage bar and the page's backdrop. Colours come from themes.gd; this file adds the
## shapes (round glass pills, sharp steel plates, pixel blocks with a pink shadow...).

const Themes = preload("res://themes.gd")

## A button. on = the one you're on; primary = the main action (Play / Install), tinted with the game's colour.
static func button(on: bool, primary: bool, tint: Color, danger := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var sel := Themes.c("select")
	var fill := tint if primary else Themes.ink(0.08)
	if danger:
		fill = Color(0.45, 0.2, 0.2, 0.9)
	match Themes.id():
		"neon":
			# Hard pixel blocks, leaning forward, with a pink block behind them like the title's 3D letters.
			sb.bg_color = Themes.c("accent") if on else (fill.darkened(0.2) if primary else Color(Themes.c("bg"), 0.85))
			sb.border_color = sel if on else Color(sel, 0.35)
			sb.set_border_width_all(4 if on else 2)
			sb.shadow_color = Color("FF2E88") if not on else Color("3FF5E6")
			sb.shadow_offset = Vector2(8, 8)
			sb.shadow_size = 1
			sb.skew = Vector2(0.12, 0)
			sb.set_corner_radius_all(0)
		"ps2":
			# Black glass with a thin blue edge; the chosen one glows blue.
			sb.bg_color = Color(0.05, 0.12, 0.28, 0.95) if on else Color(0.0, 0.0, 0.0, 0.9)
			sb.border_color = sel if on else Color(sel, 0.3)
			sb.set_border_width_all(2)
			if on:
				sb.shadow_color = Color(sel, 0.55)
				sb.shadow_size = 16
			sb.set_corner_radius_all(2)
		"frutiger":
			# Glossy glass pills: a bright rim on top, a soft blue shadow under.
			# The chosen one is the game's colour at full strength (not the theme's blue), the others are paler.
			sb.bg_color = tint.lightened(0.05) if on else (tint.lightened(0.35) if primary else Color(1, 1, 1, 0.55))
			sb.border_color = Color(1, 1, 1, 0.95)
			sb.border_width_top = 3
			sb.border_width_left = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.shadow_color = Color(tint.darkened(0.3), 0.5) if on else Color(0.1, 0.4, 0.7, 0.18)
			sb.shadow_size = 14 if on else 6
			sb.shadow_offset = Vector2(0, 4)
			sb.set_corner_radius_all(40)
		"channels":
			# Rounded white pills; the chosen one gets a thick blue ring.
			sb.bg_color = (tint.lightened(0.1) if primary else Color(1, 1, 1)) if not on else (tint.lightened(0.2) if primary else Color(1, 1, 1))
			sb.border_color = sel if on else Color(0.8, 0.83, 0.87)
			sb.set_border_width_all(5 if on else 2)
			sb.shadow_color = Color(0.2, 0.4, 0.6, 0.2)
			sb.shadow_size = 10 if on else 4
			sb.shadow_offset = Vector2(0, 3)
			sb.set_corner_radius_all(40)
		"sleek":
			# Brushed metal plates: a light edge on top, a dark one under; the chosen one turns graphite.
			sb.bg_color = sel if on else (tint if primary else Color(0.88, 0.9, 0.92))
			sb.border_color = Color(1, 1, 1, 0.9)
			sb.border_width_top = 2
			sb.border_width_bottom = 2
			sb.border_blend = true
			sb.shadow_color = Color(0, 0, 0, 0.18)
			sb.shadow_size = 6
			sb.shadow_offset = Vector2(0, 3)
			sb.set_corner_radius_all(10)
		"gothic":
			# Carved black stone with a thin silver edge; the chosen one turns pale, like moonlit marble.
			sb.bg_color = Color(0.86, 0.86, 0.88) if on else (Color(0.13, 0.13, 0.14) if primary else Color(0.07, 0.07, 0.08, 0.92))
			sb.border_color = Color(1, 1, 1, 0.9) if on else Color(1, 1, 1, 0.22)
			sb.set_border_width_all(2 if on else 1)
			sb.set_corner_radius_all(3)
			if on:
				sb.shadow_color = Color(1, 1, 1, 0.18)
				sb.shadow_size = 14
		"mold":
			# Damp, stained wood: dull brown-grey, a thin dirty edge; the chosen one is lit pale, as by the flashlight.
			sb.bg_color = Color(0.82, 0.78, 0.69) if on else (Color(0.16, 0.14, 0.12) if primary else Color(0.08, 0.07, 0.06, 0.92))
			sb.border_color = Color(1, 0.95, 0.85, 0.85) if on else Color(0.55, 0.5, 0.42, 0.25)
			sb.set_border_width_all(2 if on else 1)
			sb.set_corner_radius_all(4)
			if on:
				sb.shadow_color = Color(1, 0.92, 0.75, 0.14)
				sb.shadow_size = 14
		"gunmetal":
			# Machined steel: square, a hairline of light along the top, a pale edge when chosen.
			sb.bg_color = Color(0.2, 0.21, 0.23) if on else (fill.darkened(0.3) if primary else Color(0.09, 0.095, 0.1))
			sb.border_color = sel if on else Color(1, 1, 1, 0.12)
			sb.set_border_width_all(2 if on else 1)
			sb.border_width_top = 2
			sb.set_corner_radius_all(2)
		"volcanic":
			# Basalt slabs that glow orange underneath when chosen, like lava under rock.
			sb.bg_color = Color(0.16, 0.08, 0.06) if on else (fill.darkened(0.25) if primary else Color(0.08, 0.05, 0.04, 0.9))
			sb.border_color = Themes.c("glow1")
			sb.border_width_bottom = 5 if on else 2
			if on:
				sb.shadow_color = Color(Themes.c("glow1"), 0.45)
				sb.shadow_size = 14
				sb.shadow_offset = Vector2(0, 6)
			sb.set_corner_radius_all(6)
		"wave":
			# Soft see-through silk; the chosen one glows in the Wave colour.
			sb.bg_color = Color(sel, 0.35) if on else (Color(tint, 0.6) if primary else Themes.ink(0.07))
			sb.border_color = Color(1, 1, 1, 0.8 if on else 0.15)
			sb.set_border_width_all(2)
			if on:
				sb.shadow_color = Color(sel, 0.5)
				sb.shadow_size = 18
			sb.set_corner_radius_all(12)
		_:
			sb.bg_color = (fill.lightened(0.1) if on else fill.darkened(0.15)) if primary else (Themes.ink(0.22) if on else fill)
			if on:
				sb.border_color = Color(sel, 0.95)
				sb.set_border_width_all(4)
			sb.set_corner_radius_all(16)
	if danger and not on:
		sb.bg_color = Color(0.45, 0.2, 0.2, 0.9)
	return sb

## The text colour that reads on that button.
static func button_text(on: bool, primary: bool, tint: Color) -> Color:
	var sb := button(on, primary, tint)
	var bg: Color = Themes.c("bg").lerp(Color(sb.bg_color, 1.0), sb.bg_color.a)  # as it looks over the page
	return Themes.c("text") if absf(bg.get_luminance() - Themes.c("text").get_luminance()) > 0.45 else (Color(0.04, 0.06, 0.09) if bg.get_luminance() > 0.55 else Color(1, 1, 1))

## Miami shouts its words; the others leave them as written.
static func words(txt: String) -> String:
	return txt.to_upper() if Themes.id() == "neon" else txt

## The panel behind a menu (the game's options menu).
static func panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Themes.c("panel"), 0.97)
	sb.set_content_margin_all(30)
	match Themes.id():
		"neon":
			sb.set_corner_radius_all(0)
			sb.border_color = Themes.c("select")
			sb.set_border_width_all(4)
			sb.shadow_color = Themes.c("accent")
			sb.shadow_offset = Vector2(14, 14)
			sb.shadow_size = 1
		"ps2":
			sb.bg_color = Color(0, 0, 0, 0.96)
			sb.set_corner_radius_all(2)
			sb.border_color = Color(Themes.c("select"), 0.6)
			sb.set_border_width_all(2)
		"frutiger", "channels":
			sb.set_corner_radius_all(36)
			sb.border_color = Color(1, 1, 1, 0.95)
			sb.border_width_top = 3
			sb.shadow_color = Color(0.1, 0.35, 0.6, 0.25)
			sb.shadow_size = 24
			sb.shadow_offset = Vector2(0, 8)
		"mold":
			sb.set_corner_radius_all(4)
			sb.border_color = Color(0.55, 0.5, 0.42, 0.3)
			sb.set_border_width_all(1)
		"gothic":
			sb.set_corner_radius_all(3)
			sb.border_color = Color(1, 1, 1, 0.3)
			sb.set_border_width_all(1)
			sb.border_width_top = 2
		"gunmetal":
			sb.set_corner_radius_all(2)
			sb.border_color = Color(1, 1, 1, 0.14)
			sb.set_border_width_all(1)
		"volcanic":
			sb.set_corner_radius_all(8)
			sb.border_color = Color(Themes.c("glow1"), 0.8)
			sb.border_width_bottom = 4
		"wave":
			sb.bg_color = Color(Themes.c("panel"), 0.88)
			sb.set_corner_radius_all(16)
			sb.border_color = Color(1, 1, 1, 0.2)
			sb.set_border_width_all(1)
		_:
			sb.set_corner_radius_all(24)
	return sb

## How round the cover's corners are.
static func cover_radius() -> float:
	match Themes.id():
		"neon", "ps2":
			return 0.0
		"gunmetal", "gothic":
			return 2.0
		"mold":
			return 4.0
		"frutiger", "channels":
			return 26.0
		"volcanic":
			return 8.0
	return 18.0

## The storage bar's corner rounding.
static func bar_radius() -> float:
	match Themes.id():
		"neon", "ps2", "gunmetal":
			return 0.0
		"frutiger", "channels":
			return 22.0
	return 12.0

## Section headings ("STORAGE", "ABOUT"): each theme's own accent.
static func heading(tint := Color(0, 0, 0, 0)) -> Color:
	match Themes.id():
		"neon":
			return Color("FF2E88")
		"frutiger":
			return tint.darkened(0.45) if tint.a > 0.0 else Themes.c("select")  # the game's colour, deep enough to read on its pale sky
		"ps2", "wave", "channels":
			return Themes.c("select")
		"volcanic":
			return Themes.c("glow1")
	return Themes.c("muted")

## How strongly the game's own colour washes over the top of the page.
static func wash() -> float:
	match Themes.id():
		"ps2", "gunmetal":
			return 0.14
		"neon":
			return 0.0
		"frutiger", "channels", "sleek":
			return 0.22
	return 0.34

## The page's backdrop, under everything: the theme's own sky (top colour to bottom colour), plus scanlines and a
## sunset strip on Miami, and an ember glow along the bottom on Volcanic.
static func backdrop(parent: Control) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Themes.c("bg_top"))
	g.set_color(1, Themes.c("bg_bottom"))
	if Themes.id() == "neon":
		g.set_color(0, Color("12031C"))
		g.set_color(1, Color("5A0A4A"))
	elif Themes.id() == "ps2":
		g.set_color(1, Color(0.0, 0.02, 0.07))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 256
	var r := TextureRect.new()
	r.texture = gt
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Themes.id() in ["neon", "volcanic", "ps2"]:
		var d := Control.new()
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(d)
		d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		d.draw.connect(_extras.bind(d))
		d.resized.connect(d.queue_redraw)
	return g

## The light themes (Aero, Channels, Sleek) have a pale sky of their own; on the game page it is made from the
## game's colour instead (a pastel of it, so the dark words stay readable). The dark themes already get the
## game's colour from the wash over their top.
static func tints_sky() -> bool:
	return Themes.id() in ["frutiger", "channels", "sleek"]

## Top and bottom colours of that sky for a game colour.
static func sky_colors(c: Color) -> Array:
	return [c.lerp(Color(1, 1, 1), 0.38), c.lerp(Color(1, 1, 1), 0.84)]

static func _extras(d: Control) -> void:
	var sz := d.size
	match Themes.id():
		"neon":
			# A low pixel sun sitting on the bottom edge, cut into strips, and scanlines over the whole page.
			var c := Vector2(sz.x * 0.86, sz.y + 60.0)
			var rad := sz.y * 0.28
			var px := 6.0
			var y := -rad
			while y < 0.0:
				var w := sqrt(maxf(rad * rad - y * y, 0.0))
				var k := (y + rad) / rad
				if not (k > 0.45 and int((y + rad) / px) % 4 == 0):
					d.draw_rect(Rect2(snappedf(c.x - w, px), c.y + y, snappedf(w * 2.0, px), px), Color("FFD23A").lerp(Color("FF3A2E"), k) * Color(1, 1, 1, 0.55))
				y += px
			for sy in range(0, int(sz.y), 4):
				d.draw_rect(Rect2(0, sy, sz.x, 1), Color(0, 0, 0, 0.16))
		"volcanic":
			for i in 12:
				var k := float(i) / 12.0
				d.draw_rect(Rect2(0, sz.y * (0.8 + 0.2 * k), sz.x, sz.y * 0.2 / 12.0 + 1.0), Color(Themes.c("glow1"), 0.02 + 0.1 * k * k))
		"ps2":
			# a faint blue haze along the floor
			for i in 10:
				var k := float(i) / 10.0
				d.draw_rect(Rect2(0, sz.y * (0.75 + 0.25 * k), sz.x, sz.y * 0.025 + 1.0), Color(0.1, 0.3, 0.9, 0.01 + 0.05 * k))
