extends RefCounted
## The Planet theme's sky: deep space with soft coloured nebulae drifting very slowly, a field of twinkling stars,
## a shooting star every so often and a far moon. Original drawing. It sits behind everything (tephra_bg.gd draws it);
## the world the games stand on is planet.gd's.

const STARS := 170

var _stars: Array = []
var _nebulae: Array = []
var _blob: GradientTexture2D

func make() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in STARS:
		var big := rng.randf() < 0.07
		_stars.append({
			"p": Vector2(rng.randf(), rng.randf() * 0.9),
			"r": rng.randf_range(2.6, 3.8) if big else rng.randf_range(0.8, 1.9),
			"ph": rng.randf() * TAU,
			"sp": rng.randf_range(0.4, 1.8),
			"c": [Color(0.85, 0.92, 1.0), Color(1.0, 0.95, 0.85), Color(0.75, 0.85, 1.0), Color(1.0, 0.85, 0.9)][rng.randi() % 4],
			"big": big})
	var cols := [Color(0.35, 0.25, 0.85), Color(0.85, 0.25, 0.6), Color(0.15, 0.5, 0.9), Color(0.55, 0.2, 0.75), Color(0.1, 0.35, 0.7)]
	for i in 5:
		_nebulae.append({
			"p": Vector2(rng.randf_range(0.05, 0.95), rng.randf_range(0.05, 0.6)),
			"r": rng.randf_range(0.22, 0.42),
			"c": cols[i],
			"a": rng.randf_range(0.12, 0.2),
			"ph": rng.randf() * TAU})
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	_blob = GradientTexture2D.new()
	_blob.gradient = g
	_blob.fill = GradientTexture2D.FILL_RADIAL
	_blob.fill_from = Vector2(0.5, 0.5)
	_blob.fill_to = Vector2(1.0, 0.5)
	_blob.width = 256
	_blob.height = 256

func draw(cv: CanvasItem, sz: Vector2, t: float) -> void:
	# nebulae: wide soft clouds of colour, breathing a little and drifting sideways
	for n in _nebulae:
		var r: float = float(n["r"]) * sz.x
		var c: Vector2 = (n["p"] as Vector2) * sz + Vector2(sin(t * 0.03 + float(n["ph"])) * 40.0, cos(t * 0.025 + float(n["ph"])) * 20.0)
		var a: float = float(n["a"]) * (0.85 + 0.15 * sin(t * 0.15 + float(n["ph"])))
		cv.draw_texture_rect(_blob, Rect2(c - Vector2(r, r * 0.7), Vector2(r * 2.0, r * 1.4)), false, Color(n["c"], a))
	# stars
	for s in _stars:
		var p: Vector2 = (s["p"] as Vector2) * sz
		var tw := 0.55 + 0.45 * sin(t * float(s["sp"]) + float(s["ph"]))
		var col: Color = s["c"]
		col.a = tw
		var r: float = float(s["r"])
		if bool(s["big"]):
			cv.draw_circle(p, r, col)
			var arm := r * 3.2 * tw
			cv.draw_line(p - Vector2(arm, 0), p + Vector2(arm, 0), Color(col, tw * 0.5), 1.2)
			cv.draw_line(p - Vector2(0, arm), p + Vector2(0, arm), Color(col, tw * 0.5), 1.2)
		elif r > 1.5:
			cv.draw_circle(p, r, col)
		else:
			cv.draw_rect(Rect2(p - Vector2(r, r) * 0.5, Vector2(r, r)), col)
	# a far moon, top right
	var mp := Vector2(sz.x * 0.86, sz.y * 0.2)
	var mr := sz.y * 0.035
	cv.draw_texture_rect(_blob, Rect2(mp - Vector2(mr, mr) * 3.0, Vector2(mr, mr) * 6.0), false, Color(0.7, 0.8, 1.0, 0.18))
	cv.draw_circle(mp, mr, Color(0.82, 0.86, 0.95, 0.9))
	for cr in [[-0.3, -0.25, 0.22], [0.28, 0.1, 0.17], [-0.05, 0.4, 0.13], [0.35, -0.38, 0.1]]:  # craters
		cv.draw_circle(mp + Vector2(cr[0], cr[1]) * mr, cr[2] * mr, Color(0.62, 0.67, 0.8, 0.55))
	# a shooting star: every 9 seconds one streaks across (different place each time)
	var cycle := 9.0
	var k := floorf(t / cycle)
	var ph := fposmod(t, cycle)
	if ph < 0.9:
		var rr := RandomNumberGenerator.new()
		rr.seed = int(k) * 7919 + 13
		var start := Vector2(rr.randf_range(0.1, 0.75) * sz.x, rr.randf_range(0.04, 0.3) * sz.y)
		var dir := Vector2(1.0, 0.45).normalized()
		var head := start + dir * (ph / 0.9) * sz.x * 0.28
		var fade := 1.0 - ph / 0.9
		for i in 8:
			var f := float(i) / 8.0
			var a0 := head - dir * f * sz.x * 0.07
			var a1 := head - dir * (f + 0.125) * sz.x * 0.07
			cv.draw_line(a0, a1, Color(1, 1, 1, (1.0 - f) * fade * 0.9), 3.0 * (1.0 - f) + 0.6)
