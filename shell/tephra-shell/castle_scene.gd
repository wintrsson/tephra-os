extends RefCounted
## Castle: a calm kingdom landscape that follows the real time of day (set TEPHRA_HOUR=14.5 to look at another time):
## the sky changes from dawn to noon to sunset to a starry night, the sun and moon cross it, clouds drift, two tall
## stone castles stand on green hills with flags, torches, a guard on the wall and chimney smoke, a windmill turns on a
## hill, birds fly by day and fireflies drift at night. Smooth vector drawing, original. draw() is called each frame.

var _stars: Array = []
var _clouds: Array = []
var _pines: Array = []

func make() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for i in 90:
		_stars.append([rng.randf(), rng.randf() * 0.6, rng.randf() * TAU, rng.randf_range(1.0, 2.6)])
	for i in 7:
		_clouds.append([rng.randf(), rng.randf_range(0.07, 0.36), rng.randf_range(0.7, 1.5), rng.randf_range(0.004, 0.011)])
	for i in 16:
		_pines.append([rng.randf_range(0.36, 0.72) + (0.3 if i % 2 == 0 else 0.0), rng.randf_range(0.7, 1.2)])

static func hour() -> float:
	var o := OS.get_environment("TEPHRA_HOUR")
	if o != "":
		return o.to_float()
	var d := Time.get_time_dict_from_system()
	return float(d["hour"]) + float(d["minute"]) / 60.0 + float(d["second"]) / 3600.0

func _hill_y(sz: Vector2, base: float, amp: float, ph: float, f: float, x: float) -> float:
	var u := x / sz.x
	return sz.y * (base - amp * (0.5 + 0.5 * sin(u * f + ph)) - amp * 0.35 * sin(u * f * 2.3 + ph * 2.0))

func _hill(cv: CanvasItem, sz: Vector2, base: float, amp: float, ph: float, f: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var x := sz.x * float(i) / 48.0
		pts.append(Vector2(x, _hill_y(sz, base, amp, ph, f, x)))
	pts.append(Vector2(sz.x, sz.y))
	pts.append(Vector2(0, sz.y))
	cv.draw_colored_polygon(pts, col)

func draw(cv: CanvasItem, sz: Vector2, t: float, glow: Texture2D) -> void:
	var h := hour()
	var u := (h - 6.0) / 12.0                                   # 0 sunrise ... 1 sunset
	var sun_up := u > -0.05 and u < 1.05
	var el := maxf(sin(clampf(u, 0.0, 1.0) * PI), 0.0) if sun_up else 0.0
	var day := smoothstep(0.0, 0.3, el)
	var twil := clampf(1.0 - el * 4.0, 0.0, 1.0) if sun_up else 0.0
	var night := 1.0 - day
	var top := Color(0.03, 0.04, 0.17).lerp(Color(0.30, 0.56, 0.95), day).lerp(Color(0.32, 0.24, 0.55), twil * 0.8)
	var bot := Color(0.08, 0.10, 0.30).lerp(Color(0.72, 0.88, 1.0), day).lerp(Color(1.0, 0.62, 0.30), twil * 0.85)
	var horizon := sz.y * 0.80
	var bands := 48
	for i in bands:
		var f := float(i) / float(bands - 1)
		cv.draw_rect(Rect2(0, horizon * float(i) / bands, sz.x, horizon / bands + 2.0), top.lerp(bot, f))
	# stars
	if night > 0.3:
		for s in _stars:
			var tw := 0.5 + 0.5 * sin(t * 1.5 + float(s[2]))
			var a := clampf((night - 0.3) * 1.4, 0.0, 1.0) * (0.35 + 0.65 * tw)
			cv.draw_circle(Vector2(float(s[0]) * sz.x, float(s[1]) * horizon), float(s[3]), Color(1, 1, 0.9, a))
	# sun, with a soft glow
	if sun_up:
		var su := clampf(u, 0.0, 1.0)
		var sp := Vector2(lerpf(0.06, 0.94, su) * sz.x, horizon - sin(su * PI) * horizon * 0.78 + 30.0)
		var sc := Color(1.0, 0.96, 0.7).lerp(Color(1.0, 0.55, 0.2), twil)
		cv.draw_texture_rect(glow, Rect2(sp.x - 330.0, sp.y - 330.0, 660.0, 660.0), false, Color(sc, 0.6))
		cv.draw_circle(sp, 56.0, Color(sc, 0.35))
		cv.draw_circle(sp, 46.0, sc.lerp(Color(1, 1, 1), 0.35))
	# moon (a crescent)
	var nh := fposmod(h - 18.0, 24.0) / 12.0
	if nh < 1.0:
		var mp := Vector2(lerpf(0.06, 0.94, nh) * sz.x, horizon - sin(nh * PI) * horizon * 0.72 + 40.0)
		cv.draw_texture_rect(glow, Rect2(mp.x - 160.0, mp.y - 160.0, 320.0, 320.0), false, Color(0.7, 0.8, 1.0, 0.35 * night))
		cv.draw_circle(mp, 36.0, Color(0.93, 0.95, 1.0))
		cv.draw_circle(mp + Vector2(-10, -6), 6.0, Color(0.8, 0.84, 0.94))
		cv.draw_circle(mp + Vector2(9, 11), 4.5, Color(0.82, 0.86, 0.95))
	# clouds
	var cc := Color(1, 1, 1).lerp(Color(0.3, 0.32, 0.55), night * 0.85).lerp(Color(1.0, 0.8, 0.7), twil * 0.5)
	for c in _clouds:
		var x := fposmod(float(c[0]) + t * float(c[3]), 1.3) * sz.x - 0.15 * sz.x
		var p := Vector2(x, float(c[1]) * sz.y)
		var w := 130.0 * float(c[2])
		for k in 6:
			cv.draw_circle(p + Vector2(w * (-0.45 + 0.18 * k), w * (0.1 - 0.12 * sin(float(k) * 0.9 + 0.5))), w * (0.13 + 0.06 * sin(float(k) * 1.4 + 1.0)), Color(cc, 0.92))
	# far mountains and hills
	var lit := lerpf(0.34, 1.0, day)
	var warm := Color(1.0, 0.82, 0.72)
	var mt := (Color(0.46, 0.55, 0.72) * lit).lerp(Color(0.5, 0.4, 0.6) * lit, twil * 0.6)
	mt.a = 1.0
	var mp2 := PackedVector2Array([Vector2(0, horizon), Vector2(sz.x * 0.12, horizon - sz.y * 0.10), Vector2(sz.x * 0.26, horizon - sz.y * 0.04), Vector2(sz.x * 0.42, horizon - sz.y * 0.15), Vector2(sz.x * 0.58, horizon - sz.y * 0.05), Vector2(sz.x * 0.74, horizon - sz.y * 0.13), Vector2(sz.x * 0.90, horizon - sz.y * 0.06), Vector2(sz.x, horizon - sz.y * 0.09), Vector2(sz.x, horizon), ])
	cv.draw_colored_polygon(mp2, mt)
	var g1 := (Color(0.20, 0.52, 0.30) * lit).lerp(Color(0.20, 0.52, 0.30) * lit * warm, twil)
	g1.a = 1.0
	var g2 := (Color(0.25, 0.62, 0.22) * lit).lerp(Color(0.25, 0.62, 0.22) * lit * warm, twil)
	g2.a = 1.0
	_hill(cv, sz, 0.84, 0.06, 0.6, 5.0, g1)
	# pines on the far hills
	for p in _pines:
		var px := float(p[0]) * sz.x
		var py := _hill_y(sz, 0.84, 0.06, 0.6, 5.0, px) + 6.0
		var ph := sz.y * 0.07 * float(p[1])
		var pc := g1.darkened(0.35)
		for k in 3:
			var ww := ph * (0.38 - 0.08 * k)
			var yy := py - ph * (0.25 + 0.3 * k)
			cv.draw_colored_polygon(PackedVector2Array([Vector2(px - ww, yy), Vector2(px + ww, yy), Vector2(px, yy - ph * 0.5)]), pc)
	# the windmill on the right hill
	_windmill(cv, Vector2(sz.x * 0.60, _hill_y(sz, 0.84, 0.06, 0.6, 5.0, sz.x * 0.60) + 4.0), sz.y / 135.0, lit, t)
	# the castles
	var unit := sz.y / 135.0
	_castle(cv, sz.x * 0.20, sz.y * 0.865, 1.0, unit, lit, twil, night, t)
	_castle(cv, sz.x * 0.82, sz.y * 0.85, 0.78, unit, lit, twil, night, t)
	_hill(cv, sz, 0.93, 0.045, 3.0, 4.0, g2)
	# birds by day
	if night < 0.6:
		for b in 4:
			var bx := fposmod(float(b) * 0.27 + t * (0.012 + 0.003 * b), 1.2) * sz.x - 0.1 * sz.x
			var by := sz.y * (0.12 + 0.05 * b) + 10.0 * sin(t * 0.8 + b)
			var fl := sin(t * 5.0 + b * 2.0) * 6.0
			cv.draw_polyline(PackedVector2Array([Vector2(bx - 12, by + fl), Vector2(bx - 5, by - 2), Vector2(bx, by)]), Color(0.12, 0.12, 0.2, 0.85), 2.2, true)
			cv.draw_polyline(PackedVector2Array([Vector2(bx, by), Vector2(bx + 5, by - 2), Vector2(bx + 12, by + fl)]), Color(0.12, 0.12, 0.2, 0.85), 2.2, true)
	# fireflies at night
	if night > 0.5:
		for f in 16:
			var fa := 0.5 + 0.5 * sin(t * 1.3 + f * 1.7)
			var fp := Vector2(fposmod(f * 0.071 + 0.01 * sin(t * 0.3 + f), 1.0) * sz.x, sz.y * (0.84 + 0.1 * fposmod(f * 0.37, 1.0)) + 6.0 * sin(t * 0.7 + f))
			cv.draw_texture_rect(glow, Rect2(fp.x - 14, fp.y - 14, 28, 28), false, Color(0.9, 1.0, 0.4, fa * 0.8))

func _windmill(cv: CanvasItem, base: Vector2, u: float, lit: float, t: float) -> void:
	var body := Color(0.86, 0.78, 0.62) * lit
	body.a = 1.0
	var roof := Color(0.55, 0.22, 0.16) * lit
	roof.a = 1.0
	var w0 := 9.0 * u
	var w1 := 6.0 * u
	var hgt := 22.0 * u
	cv.draw_colored_polygon(PackedVector2Array([base + Vector2(-w0, 0), base + Vector2(w0, 0), base + Vector2(w1, -hgt), base + Vector2(-w1, -hgt)]), body)
	cv.draw_colored_polygon(PackedVector2Array([base + Vector2(-w1 - 1.5 * u, -hgt), base + Vector2(w1 + 1.5 * u, -hgt), base + Vector2(0, -hgt - 8.0 * u)]), roof)
	var hub := base + Vector2(0, -hgt + 3.0 * u)
	var a0 := t * 0.5
	for k in 4:
		var a := a0 + k * PI * 0.5
		var d := Vector2(cos(a), sin(a))
		var n := Vector2(-d.y, d.x)
		var tip := hub + d * 20.0 * u
		cv.draw_colored_polygon(PackedVector2Array([hub + n * 0.8 * u, tip + n * 0.8 * u, tip + n * 4.5 * u, hub + d * 5.0 * u + n * 4.5 * u]), Color(0.95, 0.93, 0.88) * lit)
		cv.draw_line(hub, tip, Color(0.4, 0.28, 0.18) * lit, 1.5 * u, true)
	cv.draw_circle(hub, 1.8 * u, Color(0.3, 0.2, 0.12))

func _arch(cv: CanvasItem, x: float, y: float, w: float, h: float, col: Color) -> void:
	cv.draw_rect(Rect2(x - w / 2.0, y + w / 2.0, w, h - w / 2.0), col)
	cv.draw_circle(Vector2(x, y + w / 2.0), w / 2.0, col)

func _castle(cv: CanvasItem, cx: float, base: float, s: float, u: float, lit: float, twil: float, night: float, t: float) -> void:
	var stone := Color(0.60, 0.60, 0.66) * lit
	stone.a = 1.0
	stone = stone.lerp(stone * Color(1.0, 0.82, 0.72), twil)
	var dark := stone.darkened(0.28)
	var light := stone.lightened(0.2)
	var kw := 26.0 * s * u
	var kh := 34.0 * s * u
	var tw := 9.0 * s * u
	var th := 58.0 * s * u
	var dw := 11.0 * s * u
	var dh := 76.0 * s * u
	var x0 := cx - kw / 2.0
	var roof_a := Color(0.72, 0.16, 0.16) * lit
	roof_a.a = 1.0
	var roof_b := Color(0.18, 0.28, 0.72) * lit
	roof_b.a = 1.0
	var glow := Color(1.0, 0.82, 0.3) if night > 0.5 else Color(0.1, 0.1, 0.18)
	# keep
	cv.draw_rect(Rect2(x0, base - kh, kw, kh), stone)
	var mer := 2.0 * s * u
	for i in int(kw / (mer * 2.0)) + 1:
		cv.draw_rect(Rect2(x0 + i * mer * 2.0, base - kh - mer, mer, mer), stone)
	for yy in range(1, int(kh / (4.0 * s * u))):
		cv.draw_line(Vector2(x0, base - kh + yy * 4.0 * s * u), Vector2(x0 + kw, base - kh + yy * 4.0 * s * u), Color(dark, 0.45), 1.2)
	cv.draw_rect(Rect2(x0, base - kh, 1.5 * s * u, kh), light)
	# the donjon
	var dx := cx - dw / 2.0
	cv.draw_rect(Rect2(dx, base - dh, dw, dh - kh + 2.0), stone)
	for yy in range(1, int((dh - kh) / (4.0 * s * u))):
		cv.draw_line(Vector2(dx, base - dh + yy * 4.0 * s * u), Vector2(dx + dw, base - dh + yy * 4.0 * s * u), Color(dark, 0.45), 1.2)
	cv.draw_rect(Rect2(dx, base - dh, 1.5 * s * u, dh - kh), light)
	var rh := 14.0 * s * u
	cv.draw_colored_polygon(PackedVector2Array([Vector2(dx - 1.5 * u, base - dh), Vector2(dx + dw + 1.5 * u, base - dh), Vector2(cx, base - dh - rh)]), roof_b)
	for k in 3:
		var wy := base - dh + 8.0 * s * u + k * 14.0 * s * u
		if wy < base - kh - 6.0 * u:
			_arch(cv, cx, wy, 3.0 * s * u, 6.0 * s * u, glow)
	# corner towers
	for side in 2:
		var tx := x0 - tw + 1.0 * u if side == 0 else x0 + kw - 1.0 * u
		cv.draw_rect(Rect2(tx, base - th, tw, th), stone)
		for yy in range(1, int(th / (4.0 * s * u))):
			cv.draw_line(Vector2(tx, base - th + yy * 4.0 * s * u), Vector2(tx + tw, base - th + yy * 4.0 * s * u), Color(dark, 0.45), 1.2)
		cv.draw_rect(Rect2(tx, base - th, 1.2 * s * u, th), light)
		var trh := 12.0 * s * u
		cv.draw_colored_polygon(PackedVector2Array([Vector2(tx - 1.5 * u, base - th), Vector2(tx + tw + 1.5 * u, base - th), Vector2(tx + tw / 2.0, base - th - trh)]), roof_a)
		for k in 2:
			_arch(cv, tx + tw / 2.0, base - th + 8.0 * s * u + k * 16.0 * s * u, 2.6 * s * u, 5.5 * s * u, glow)
	# the gate with torches
	var gw := 8.0 * s * u
	var gh := 12.0 * s * u
	_arch(cv, cx, base - gh, gw, gh, Color(0.1, 0.05, 0.03))
	for k in 3:
		cv.draw_line(Vector2(cx - gw / 2.0 + gw * (k + 1) / 4.0, base - gh + gw / 2.0), Vector2(cx - gw / 2.0 + gw * (k + 1) / 4.0, base), Color(0.4, 0.34, 0.28) * lit, 1.5)
	var gp := (night * 0.9 + 0.2)
	for side in 2:
		var fx := cx - gw / 2.0 - 4.0 * u if side == 0 else cx + gw / 2.0 + 4.0 * u
		var fl := 0.8 + 0.2 * sin(t * 9.0 + side * 2.0)
		cv.draw_line(Vector2(fx, base - 3.0 * u), Vector2(fx, base - 7.0 * u), Color(0.4, 0.25, 0.1), 2.0)
		cv.draw_circle(Vector2(fx, base - 8.5 * u), 2.2 * u * fl, Color(1.0, 0.7, 0.15))
		cv.draw_circle(Vector2(fx, base - 9.0 * u), 1.2 * u * fl, Color(1.0, 0.95, 0.6))
		cv.draw_circle(Vector2(fx, base - 8.5 * u), 7.0 * u, Color(1.0, 0.6, 0.1, 0.12 * gp))
	# keep windows
	_arch(cv, x0 + 5.0 * s * u, base - kh + 8.0 * s * u, 2.6 * s * u, 5.5 * s * u, glow)
	_arch(cv, x0 + kw - 5.0 * s * u, base - kh + 8.0 * s * u, 2.6 * s * u, 5.5 * s * u, glow)
	# a guard walks the wall
	var gx := x0 + 2.0 + fposmod(t * 6.0 * s + cx * 0.01, kw - 4.0)
	var gy := base - kh - mer
	cv.draw_rect(Rect2(gx - 1.5 * u * s, gy - 4.0 * u * s, 3.0 * u * s, 4.0 * u * s), Color(0.75, 0.12, 0.12))
	cv.draw_circle(Vector2(gx, gy - 5.5 * u * s), 1.4 * u * s, Color(0.98, 0.8, 0.62))
	cv.draw_line(Vector2(gx + 2.0 * u * s, gy), Vector2(gx + 2.0 * u * s, gy - 9.0 * u * s), Color(0.85, 0.85, 0.9), 1.6)
	# flags waving
	var fy := base - dh - rh
	_flag(cv, Vector2(cx, fy), 11.0 * s * u, Color(0.88, 0.12, 0.12), t)
	_flag(cv, Vector2(x0 - tw / 2.0 + 1.0 * u, base - th - 12.0 * s * u), 8.0 * s * u, Color(0.96, 0.8, 0.12), t + 1.0)
	_flag(cv, Vector2(x0 + kw + tw / 2.0 - 1.0 * u, base - th - 12.0 * s * u), 8.0 * s * u, Color(0.2, 0.4, 0.9), t + 2.0)
	# smoke from the keep
	for k in 6:
		var ph := fposmod(t * 0.12 + float(k) / 6.0, 1.0)
		cv.draw_circle(Vector2(x0 + kw - 3.0 * u + ph * 14.0 * u + sin(ph * 6.0 + k) * 2.0 * u, base - kh - 3.0 * u - ph * 30.0 * u), (0.9 + ph * 2.2) * u, Color(0.85, 0.85, 0.9, (1.0 - ph) * 0.28))

func _flag(cv: CanvasItem, p: Vector2, len: float, col: Color, t: float) -> void:
	cv.draw_line(p, p + Vector2(0, -len * 1.3), Color(0.75, 0.75, 0.78), 2.0)
	var pts := PackedVector2Array()
	for i in 7:
		var f := float(i) / 6.0
		pts.append(p + Vector2(f * len, -len * 1.3 + sin(t * 3.0 + f * 4.0) * 3.0 * f))
	for i in 7:
		var f2 := 1.0 - float(i) / 6.0
		pts.append(p + Vector2(f2 * len, -len * 0.7 + sin(t * 3.0 + f2 * 4.0) * 3.0 * f2))
	cv.draw_colored_polygon(pts, col)
