extends RefCounted
## Wood: a sunny summer day in a green meadow. A blue sky with slow white clouds and a bright sun, rolling grass hills,
## round-crowned trees, flowers in the grass, birds, butterflies and floating seeds. Original drawing (shapes only).
## draw_still() is drawn once per window size, draw_moving() every frame.

var _clouds: Array = []    # {y, x, s, v, a}
var _trees: Array = []     # {x, row, s, hue}
var _flowers: Array = []
var _blades: Array = []
var _seeds: Array = []
var _birds: Array = []
var _stars: Array = []
var night := false         # between 7 pm and 5 am: the same meadow by moonlight

const SKY_TOP := Color(0.36, 0.64, 0.93)
const SKY_LOW := Color(0.78, 0.92, 1.0)

func make() -> void:
	night = preload("res://themes.gd").nature_night()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 6:
		_clouds.append({"y": rng.randf_range(0.06, 0.40), "x": rng.randf(), "s": rng.randf_range(0.6, 1.5), "v": rng.randf_range(0.004, 0.012), "a": rng.randf_range(0.75, 0.95)})
	# Trees stand on the hills: row 0 far (small, pale), row 1 middle, row 2 near the left edge.
	for i in 7:
		_trees.append({"x": rng.randf_range(0.30, 0.98), "row": 0, "s": rng.randf_range(0.6, 0.9), "hue": rng.randf()})
	for i in 4:
		_trees.append({"x": rng.randf_range(0.45, 0.95), "row": 1, "s": rng.randf_range(0.9, 1.2), "hue": rng.randf()})
	_trees.append({"x": 0.10, "row": 2, "s": 1.9, "hue": 0.3})
	for i in 36:
		_flowers.append({"x": rng.randf(), "y": rng.randf_range(0.84, 0.985), "r": rng.randf_range(0.004, 0.008),
			"col": [Color(1.0, 0.95, 0.4), Color(1.0, 1.0, 1.0), Color(0.98, 0.55, 0.7), Color(0.75, 0.6, 0.95), Color(1.0, 0.7, 0.3)][rng.randi() % 5], "ph": rng.randf() * TAU})
	for i in 90:
		_blades.append({"x": rng.randf(), "h": rng.randf_range(0.03, 0.10), "lean": rng.randf_range(-0.3, 0.3), "ph": rng.randf() * TAU,
			"col": Color(0.2, 0.5, 0.16).lerp(Color(0.6, 0.82, 0.28), rng.randf())})
	for i in 12:
		_seeds.append({"x": rng.randf(), "y": rng.randf(), "v": rng.randf_range(0.006, 0.016), "ph": rng.randf() * TAU, "r": rng.randf_range(1.5, 3.2)})
	for i in 70:
		_stars.append([rng.randf(), rng.randf() * 0.7, rng.randf() * TAU, rng.randf_range(1.0, 2.4)])
	for i in 3:
		_birds.append({"y": rng.randf_range(0.12, 0.32), "ph": rng.randf(), "v": rng.randf_range(0.012, 0.02), "s": rng.randf_range(0.8, 1.2)})

func _hill(cv: CanvasItem, sz: Vector2, base: float, amp: float, phase: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var u := float(i) / 40.0
		pts.append(Vector2(u * sz.x, sz.y * (base - amp * (0.5 + 0.5 * sin(u * 5.2 + phase)) - 0.6 * amp * sin(u * 11.0 + phase * 2.0) * 0.3)))
	pts.append(Vector2(sz.x, sz.y))
	pts.append(Vector2(0, sz.y))
	cv.draw_colored_polygon(pts, col)

func _ground_y(sz: Vector2, base: float, amp: float, phase: float, x: float) -> float:
	var u := x
	return sz.y * (base - amp * (0.5 + 0.5 * sin(u * 5.2 + phase)) - 0.6 * amp * sin(u * 11.0 + phase * 2.0) * 0.3)

func _tree(cv: CanvasItem, sz: Vector2, x: float, ground: float, s: float, hue: float, far: bool) -> void:
	var h := sz.y * 0.16 * s
	var px := x * sz.x
	var trunk_w := maxf(h * 0.09, 3.0)
	var leaf := Color(0.28, 0.58, 0.2).lerp(Color(0.5, 0.74, 0.25), hue)
	if far:
		leaf = leaf.lerp(Color(0.62, 0.82, 0.7), 0.45)
	cv.draw_rect(Rect2(px - trunk_w * 0.5, ground - h * 0.55, trunk_w, h * 0.6), Color(0.45, 0.3, 0.18) if not far else Color(0.5, 0.42, 0.32))
	var c := Vector2(px, ground - h * 0.78)
	var r := h * 0.46
	cv.draw_circle(c + Vector2(-r * 0.5, r * 0.2), r * 0.72, leaf.darkened(0.08))
	cv.draw_circle(c + Vector2(r * 0.55, r * 0.2), r * 0.7, leaf.darkened(0.05))
	cv.draw_circle(c, r, leaf)
	cv.draw_circle(c + Vector2(-r * 0.25, -r * 0.35), r * 0.55, leaf.lightened(0.14))
	cv.draw_circle(c + Vector2(r * 0.3, -r * 0.45), r * 0.3, leaf.lightened(0.2))

func draw_still(cv: CanvasItem, sz: Vector2) -> void:
	# Far hills, pale with distance haze, then the near meadow.
	_hill(cv, sz, 0.66, 0.05, 0.5, Color(0.58, 0.78, 0.66))
	for t in _trees:
		if int(t["row"]) == 0:
			_tree(cv, sz, float(t["x"]), _ground_y(sz, 0.66, 0.05, 0.5, float(t["x"])) + 6.0, float(t["s"]), float(t["hue"]), true)
	_hill(cv, sz, 0.76, 0.06, 2.0, Color(0.42, 0.7, 0.34))
	for t in _trees:
		if int(t["row"]) == 1:
			_tree(cv, sz, float(t["x"]), _ground_y(sz, 0.76, 0.06, 2.0, float(t["x"])) + 8.0, float(t["s"]), float(t["hue"]), false)
	_hill(cv, sz, 0.88, 0.05, 4.0, Color(0.34, 0.62, 0.24))
	cv.draw_rect(Rect2(0, sz.y * 0.93, sz.x, sz.y * 0.07), Color(0.28, 0.54, 0.2, 0.8))
	# A winding path of pale earth through the meadow.
	cv.draw_colored_polygon(PackedVector2Array([Vector2(sz.x * 0.52, sz.y * 0.86), Vector2(sz.x * 0.56, sz.y * 0.86), Vector2(sz.x * 0.72, sz.y), Vector2(sz.x * 0.40, sz.y)]), Color(0.78, 0.68, 0.46, 0.55))
	# The big tree at the left, in the foreground: a thick trunk, wide leafy crown, a little shade under it.
	var tx := sz.x * 0.10
	var ground := sz.y * 0.93
	cv.draw_colored_polygon(PackedVector2Array([Vector2(tx - sz.x * 0.05, ground + 20.0), Vector2(tx - sz.x * 0.018, ground - sz.y * 0.22), Vector2(tx - sz.x * 0.012, sz.y * 0.42), Vector2(tx + sz.x * 0.012, sz.y * 0.42), Vector2(tx + sz.x * 0.02, ground - sz.y * 0.22), Vector2(tx + sz.x * 0.06, ground + 20.0)]), Color(0.43, 0.29, 0.17))
	for k in 8:
		cv.draw_line(Vector2(tx - sz.x * 0.006 + (k % 3) * sz.x * 0.006, sz.y * (0.46 + 0.06 * k)), Vector2(tx - sz.x * 0.004 + (k % 3) * sz.x * 0.006, sz.y * (0.51 + 0.06 * k)), Color(0.25, 0.16, 0.09, 0.5), 3.0, true)
	cv.draw_line(Vector2(tx, sz.y * 0.56), Vector2(tx + sz.x * 0.09, sz.y * 0.44), Color(0.4, 0.27, 0.16), 12.0, true)
	var cc := Vector2(tx + sz.x * 0.02, sz.y * 0.28)
	var cr := sz.y * 0.27
	var base := Color(0.3, 0.6, 0.2)
	cv.draw_circle(cc + Vector2(-cr * 0.7, cr * 0.2), cr * 0.65, base.darkened(0.1))
	cv.draw_circle(cc + Vector2(cr * 0.8, cr * 0.25), cr * 0.62, base.darkened(0.06))
	cv.draw_circle(cc, cr, base)
	cv.draw_circle(cc + Vector2(-cr * 0.25, -cr * 0.35), cr * 0.6, base.lightened(0.12))
	cv.draw_circle(cc + Vector2(cr * 0.35, -cr * 0.5), cr * 0.36, base.lightened(0.2))
	cv.draw_circle(cc + Vector2(-cr * 0.65, -cr * 0.1), cr * 0.3, base.lightened(0.16))
	# A few red apples in the crown.
	for a in [Vector2(-0.4, 0.15), Vector2(0.1, 0.3), Vector2(0.55, 0.05), Vector2(-0.1, -0.1)]:
		cv.draw_circle(cc + (a as Vector2) * cr, 7.0, Color(0.88, 0.2, 0.18))
		cv.draw_circle(cc + (a as Vector2) * cr + Vector2(-2, -2), 2.0, Color(1, 0.7, 0.65, 0.8))
	# A wooden fence post line at the right, small and warm.
	for k in 6:
		var fx := sz.x * (0.80 + 0.034 * k)
		var fy := sz.y * 0.895 + sz.y * 0.004 * k
		cv.draw_rect(Rect2(fx, fy - sz.y * 0.06, sz.x * 0.008, sz.y * 0.07), Color(0.6, 0.45, 0.28))
	cv.draw_rect(Rect2(sz.x * 0.80, sz.y * 0.855, sz.x * 0.17, sz.y * 0.006), Color(0.62, 0.47, 0.3))
	cv.draw_rect(Rect2(sz.x * 0.80, sz.y * 0.875, sz.x * 0.17, sz.y * 0.006), Color(0.62, 0.47, 0.3))

func _cloud(cv: CanvasItem, p: Vector2, s: float, a: float) -> void:
	var w := 150.0 * s
	var col := Color(0.32, 0.38, 0.58, a * 0.8) if night else Color(1, 1, 1, a)
	cv.draw_circle(p, w * 0.28, col)
	cv.draw_circle(p + Vector2(w * 0.28, w * 0.04), w * 0.24, col)
	cv.draw_circle(p + Vector2(-w * 0.3, w * 0.07), w * 0.2, col)
	cv.draw_circle(p + Vector2(w * 0.55, w * 0.1), w * 0.16, col)
	cv.draw_circle(p + Vector2(-w * 0.52, w * 0.11), w * 0.14, col)
	for k in 7:  # a flat, soft underside made of round puffs
		cv.draw_circle(p + Vector2(w * (-0.5 + 0.18 * k), w * 0.15), w * 0.11, col)

## The sky behind everything: the blue gradient, the sun, drifting clouds and birds.
func draw_sky(cv: CanvasItem, sz: Vector2, t: float, glow: Texture2D) -> void:
	var bands := 20
	var top := SKY_TOP
	var low := SKY_LOW
	if night:
		top = Color(0.03, 0.06, 0.18)
		low = Color(0.14, 0.22, 0.42)
	for k in bands:
		var u := float(k) / float(bands - 1)
		cv.draw_rect(Rect2(0, sz.y * u * 0.78, sz.x, sz.y * 0.78 / bands + 2.0), top.lerp(low, pow(u, 0.8)))
	if night:
		for s in _stars:
			var a := 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 1.3 + float(s[2])))
			cv.draw_circle(Vector2(float(s[0]) * sz.x, float(s[1]) * sz.y), float(s[3]), Color(1, 1, 0.92, a))
		var moon := Vector2(sz.x * 0.80, sz.y * 0.16)
		cv.draw_texture_rect(glow, Rect2(moon.x - 280.0, moon.y - 280.0, 560.0, 560.0), false, Color(0.75, 0.85, 1.0, 0.4))
		cv.draw_circle(moon, 48.0, Color(0.95, 0.96, 1.0))
		cv.draw_circle(moon + Vector2(-14, -8), 8.0, Color(0.82, 0.86, 0.95))
		cv.draw_circle(moon + Vector2(12, 14), 6.0, Color(0.84, 0.88, 0.96))
	else:
		# The sun, with a warm glow and slowly turning rays.
		var sun := Vector2(sz.x * 0.80, sz.y * 0.16)
		cv.draw_texture_rect(glow, Rect2(sun.x - 340.0, sun.y - 340.0, 680.0, 680.0), false, Color(1.0, 0.96, 0.7, 0.55))
		for i in 8:
			var a2 := TAU * float(i) / 8.0 + t * 0.03
			var d := Vector2(cos(a2), sin(a2))
			var n := Vector2(-d.y, d.x)
			cv.draw_colored_polygon(PackedVector2Array([sun + d * 80.0 + n * 8.0, sun + d * (200.0 + 40.0 * sin(t * 0.5 + i)), sun + d * 80.0 - n * 8.0]), Color(1.0, 0.97, 0.7, 0.28))
		cv.draw_circle(sun, 64.0, Color(1.0, 0.98, 0.78))
		cv.draw_circle(sun, 54.0, Color(1.0, 0.93, 0.5))
	# Clouds drift slowly to the right and come round again.
	for c in _clouds:
		var x := fposmod(float(c["x"]) + t * float(c["v"]), 1.3) - 0.15
		_cloud(cv, Vector2(x * sz.x, float(c["y"]) * sz.y), float(c["s"]), float(c["a"]))
	# Birds: two curved strokes that flap, crossing the sky.
	for b in ([] if night else _birds):
		var x := fposmod(float(b["ph"]) + t * float(b["v"]), 1.2) - 0.1
		var y: float = float(b["y"]) * sz.y + 14.0 * sin(t * 0.7 + float(b["ph"]) * 9.0)
		var s: float = float(b["s"]) * 14.0
		var flap := sin(t * 6.0 + float(b["ph"]) * 20.0) * s * 0.5
		var p := Vector2(x * sz.x, y)
		cv.draw_polyline(PackedVector2Array([p + Vector2(-s, flap), p + Vector2(-s * 0.4, -s * 0.2), p]), Color(0.2, 0.25, 0.3, 0.8), 2.5, true)
		cv.draw_polyline(PackedVector2Array([p, p + Vector2(s * 0.4, -s * 0.2), p + Vector2(s, flap)]), Color(0.2, 0.25, 0.3, 0.8), 2.5, true)

func draw_moving(cv: CanvasItem, sz: Vector2, t: float, _glow: Texture2D) -> void:
	# Floating seeds and pollen, glowing in the sunlight.
	for m in (_seeds if not night else []):
		var y := fposmod(float(m["y"]) - t * float(m["v"]), 1.0)
		var x := fposmod(float(m["x"]) + t * 0.004 + 0.02 * sin(t * 0.5 + float(m["ph"])), 1.0)
		var tw := 0.5 + 0.5 * sin(t * 1.4 + float(m["ph"]) * 3.0)
		cv.draw_circle(Vector2(x * sz.x, y * sz.y * 0.9), float(m["r"]), Color(1.0, 1.0, 0.9, 0.35 + 0.4 * tw))
	# Butterflies over the flowers.
	for b in (0 if night else 3):
		var bt := t * (0.07 + 0.02 * b) + b * 2.3
		var bp := Vector2(sz.x * (0.25 + 0.6 * (0.5 + 0.5 * sin(bt * 1.3 + b))), sz.y * (0.80 + 0.07 * sin(bt * 2.1)))
		var flap := absf(sin(t * 14.0 + b)) * 7.0 + 1.5
		var col := [Color(1.0, 0.8, 0.2), Color(0.55, 0.7, 1.0), Color(1.0, 0.6, 0.75)][b] as Color
		cv.draw_colored_polygon(PackedVector2Array([bp, bp + Vector2(-flap, -7), bp + Vector2(-flap * 0.9, 4)]), col)
		cv.draw_colored_polygon(PackedVector2Array([bp, bp + Vector2(flap, -7), bp + Vector2(flap * 0.9, 4)]), col)
	# Flowers bobbing in the grass.
	for f in _flowers:
		var x := float(f["x"]) * sz.x + 3.0 * sin(t * 1.2 + float(f["ph"]))
		var y := float(f["y"]) * sz.y
		var r := float(f["r"]) * sz.y
		cv.draw_line(Vector2(x, y + r * 3.0), Vector2(x, y), Color(0.2, 0.5, 0.18), 2.0, true)
		for k in 5:
			var a := TAU * float(k) / 5.0
			cv.draw_circle(Vector2(x, y) + Vector2(cos(a), sin(a)) * r, r * 0.7, f["col"])
		cv.draw_circle(Vector2(x, y), r * 0.55, Color(1.0, 0.85, 0.2))
	# Grass swaying in front.
	for g in _blades:
		var x := float(g["x"]) * sz.x
		var h := float(g["h"]) * sz.y
		var sway := sin(t * 1.1 + float(g["ph"]) + x * 0.004) * 6.0
		var base := Vector2(x, sz.y * 0.995)
		cv.draw_line(base, base + Vector2(float(g["lean"]) * h * 0.3 + sway, -h), g["col"], 3.0, true)

## Fireflies (night only), drawn on a layer that is not dimmed.
func draw_fx(cv: CanvasItem, sz: Vector2, t: float, glow: Texture2D) -> void:
	if not night:
		return
	for f in 14:
		var fa := 0.5 + 0.5 * sin(t * 1.3 + f * 1.7)
		var fp := Vector2(fposmod(f * 0.073 + 0.012 * sin(t * 0.3 + f), 1.0) * sz.x, sz.y * (0.70 + 0.26 * fposmod(f * 0.37, 1.0)) + 8.0 * sin(t * 0.7 + f))
		cv.draw_texture_rect(glow, Rect2(fp.x - 18, fp.y - 18, 36, 36), false, Color(0.9, 1.0, 0.4, fa * 0.85))
