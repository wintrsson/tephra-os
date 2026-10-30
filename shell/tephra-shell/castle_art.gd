extends RefCounted
## Gothic theme backdrop: a black castle on a cliff on a winter night, all drawn from code in black, white and greys.
## Far mountains with snowy peaks, a pale moon with a halo and slow clouds, a castle of spires, towers, battlements
## and pointed windows (a few lit by candles), snow lying on every roof and ledge, a pine wood, a snowy field with
## old gravestones and a bare tree in front, bats round the spires, mist, and snow falling in three depths.
## Everything still is built once into shapes (same castle every boot) and drawn on its own layer only when the
## window changes size; the moving parts (snow, bats, mist, clouds, candles) are a few cheap draws a frame.

var _shapes: Array = []      # [PackedVector2Array in 0..1 screen units, Color], back to front
var _lines: Array = []       # [Vector2 a, Vector2 b, Color, width in px]  (tree branches, snow on them)
var _windows: Array = []     # [Vector2 centre, half width, height, lit?, flicker phase] lit pointed windows
var _flakes: Array = []      # {x, y, d (depth 0..1), s (sway phase)}
var _bats: Array = []
var _flames: Array = []      # [Vector2 wick top, size, phase] foreground candle flames
var _aspect := 16.0 / 9.0    # width / height the shapes were made for (pointed tops are kept in proportion)

const STONE := Color(0.035, 0.035, 0.04)
const SNOW := Color(0.93, 0.93, 0.95)

func make() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1897
	_shapes.clear()
	_lines.clear()
	_windows.clear()
	_flames.clear()
	_mountains(rng)
	_far_wood(rng, 0.70, Color(0.06, 0.06, 0.07))
	# The castle and its rock are built at a modest size and then made bigger as a whole (wider across the screen and
	# taller), so it is the heart of the picture.
	var s0 := _shapes.size()
	var w0 := _windows.size()
	_far_castle(rng)
	_cliff(rng)
	_castle(rng)
	for i in range(s0, _shapes.size()):
		var pts: PackedVector2Array = _shapes[i][0]
		for k in pts.size():
			pts[k] = _grow(pts[k])
		_shapes[i][0] = pts
	for i in range(w0, _windows.size()):
		var w: Array = _windows[i]
		w[0] = _grow(w[0])
		w[1] = float(w[1]) * 1.22
		w[2] = float(w[2]) * 1.12
		w[3] = float(w[3]) * 1.12
	_field(rng)
	_tree(rng)
	_candles(rng)
	_flakes.clear()
	for i in 460:
		var d := rng.randf()
		_flakes.append({"x": rng.randf(), "y": rng.randf(), "d": d * d, "s": rng.randf() * TAU, "k": rng.randf()})
	_bats.clear()
	for i in 5:
		_bats.append({"cx": rng.randf_range(0.34, 0.64), "cy": rng.randf_range(0.10, 0.26), "rx": rng.randf_range(0.03, 0.09),
			"ry": rng.randf_range(0.015, 0.04), "sp": rng.randf_range(0.12, 0.3) * (1.0 if rng.randf() < 0.6 else -1.0), "ph": rng.randf() * TAU})

const BASE_Y := 0.712

## The castle's growth: 22% wider (from the left edge) and 12% taller (from the top of the cliff).
func _grow(p: Vector2) -> Vector2:
	var y := p.y
	if y < BASE_Y:
		y = BASE_Y - (BASE_Y - y) * 1.12
	return Vector2(p.x * 1.22 - 0.01, y)

func _add(pts: Array, col: Color) -> void:
	var pk := PackedVector2Array(pts)
	# A shape whose outline crosses itself can't be filled (Godot prints an error every time it is drawn):
	# such a shape is drawn as its outer hull instead.
	var test := PackedVector2Array()
	for p in pk:
		test.append(p * Vector2(1920, 1080))
	if Geometry2D.triangulate_polygon(test).is_empty():
		var hull := Geometry2D.convex_hull(pk)
		if hull.size() < 4:
			return
		hull.remove_at(hull.size() - 1)  # convex_hull repeats the first point at the end
		pk = hull
	_shapes.append([pk, col])

## A width in x units turned into the same length in y units (so a pointed arch is pointed on any screen).
func _wy(w: float) -> float:
	return w * _aspect

# ---------- Landscape ----------
func _mountains(rng: RandomNumberGenerator) -> void:
	for layer in 2:
		var base := 0.70
		var pts := [Vector2(0, base)]
		var peaks: Array = []
		var x := 0.0
		var y := 0.52 + 0.06 * layer
		while x < 1.0:
			x += rng.randf_range(0.03, 0.08)
			var up := rng.randf() < 0.5
			y = clampf(y + rng.randf_range(-0.06, 0.06), 0.40 + 0.08 * layer, 0.64)
			pts.append(Vector2(x, y))
			if up and y < 0.56 + 0.05 * layer:
				peaks.append(Vector2(x, y))
		pts.append(Vector2(1.0, base))
		var col := Color(0.11, 0.11, 0.12) if layer == 0 else Color(0.075, 0.075, 0.085)
		_add(pts, col)
		# snow on the peaks: a pale cap following the slopes down a little way, with a ragged lower edge
		for i in range(1, pts.size() - 1):
			var p: Vector2 = pts[i]
			if p.y > 0.58:
				continue
			var l: Vector2 = pts[i - 1]
			var r: Vector2 = pts[i + 1]
			var k := rng.randf_range(0.28, 0.45)
			var a := p.lerp(l, k)
			var b := p.lerp(r, k)
			var mid := (a + b) * 0.5 + Vector2(rng.randf_range(-0.004, 0.004), rng.randf_range(-0.012, 0.004))
			_add([p, a, Vector2(lerpf(a.x, mid.x, 0.5), mid.y + 0.006), mid, Vector2(lerpf(mid.x, b.x, 0.5), mid.y + 0.004), b],
				Color(0.62, 0.62, 0.66, 0.55 if layer == 0 else 0.4))

func _far_wood(rng: RandomNumberGenerator, line: float, col: Color) -> void:
	var x := -0.01
	while x < 1.01:
		var h := rng.randf_range(0.03, 0.065)
		var w := h * rng.randf_range(0.18, 0.26)
		var by := line + rng.randf_range(-0.005, 0.01)
		_pine(Vector2(x, by), w, h, col)
		x += w * rng.randf_range(0.7, 1.2)

## A fir tree: three stacked tiers, each with snow along its top edge.
func _pine(foot: Vector2, w: float, h: float, col: Color) -> void:
	_add([Vector2(foot.x - w * 0.08, foot.y), Vector2(foot.x + w * 0.08, foot.y), Vector2(foot.x + w * 0.08, foot.y - h * 0.2), Vector2(foot.x - w * 0.08, foot.y - h * 0.2)], col)
	for tier in 3:
		var tb := foot.y - h * (0.12 + 0.27 * tier)
		var tw := w * (1.0 - 0.27 * tier)
		var tt := tb - h * 0.42
		_add([Vector2(foot.x - tw * 0.5, tb), Vector2(foot.x + tw * 0.5, tb), Vector2(foot.x, tt)], col)
		_add([Vector2(foot.x, tt), Vector2(foot.x - tw * 0.32, tt + (tb - tt) * 0.62), Vector2(foot.x - tw * 0.1, tt + (tb - tt) * 0.45)], Color(SNOW, 0.5))

func _cliff(rng: RandomNumberGenerator) -> void:
	var top: Array = []
	var x := 0.03
	top.append(Vector2(0.0, 0.86))
	top.append(Vector2(0.02, 0.78))
	while x < 0.70:
		top.append(Vector2(x, 0.705 + rng.randf_range(-0.006, 0.006)))
		x += rng.randf_range(0.02, 0.04)
	top.append(Vector2(0.72, 0.74))
	top.append(Vector2(0.74, 0.79))
	top.append(Vector2(0.77, 0.83))
	top.append(Vector2(0.80, 0.90))
	var pts := top.duplicate()
	pts.append(Vector2(0.82, 1.0))
	pts.append(Vector2(0.0, 1.0))
	_add(pts, Color(0.05, 0.05, 0.055))
	# rock faces: darker slabs, and snow caught on the ledges
	for i in 16:
		var p := Vector2(rng.randf_range(0.06, 0.6), rng.randf_range(0.76, 0.87))
		var w := rng.randf_range(0.015, 0.04)
		var h := rng.randf_range(0.015, 0.035)
		_add([p, p + Vector2(w, rng.randf_range(-0.003, 0.003)), p + Vector2(w * 0.8, h), p + Vector2(w * 0.1, h * 0.9)], Color(0.038, 0.038, 0.043))
		_add([p + Vector2(0.002, -0.001), p + Vector2(w * 0.8, -0.002), p + Vector2(w * 0.6, 0.002), p + Vector2(w * 0.25, 0.0025)], Color(SNOW, rng.randf_range(0.2, 0.4)))
	# deep snow along the top of the cliff
	var snow: Array = []
	for p: Vector2 in top:
		snow.append(p + Vector2(0, -0.006))
	for i in range(top.size() - 1, -1, -1):
		var p2: Vector2 = top[i]
		snow.append(p2 + Vector2(0, rng.randf_range(0.004, 0.014)))
	_add(snow, Color(0.86, 0.86, 0.89))

# ---------- The castle ----------
func _castle(rng: RandomNumberGenerator) -> void:
	var base := 0.712
	# curtain wall with battlements, end to end along the cliff
	_wall(0.08, 0.66, base, 0.62, rng)
	# great hall (like a cathedral nave): steep roof, a rose window and tall pointed windows
	_hall(0.42, 0.56, base, 0.47, 0.37)
	# the keep: a tall block with a steep roof and the highest spire
	_block(0.29, 0.42, base, 0.38, 0.29)
	_spire(0.355, 0.012, 0.29, 0.10)
	for k in 3:
		_arch(Vector2(0.31 + 0.04 * k + 0.012, 0.44), 0.007, 0.05, k == 1)
		_arch(Vector2(0.31 + 0.04 * k + 0.012, 0.55), 0.006, 0.04, k == 2)
	# towers: [x, width, top, roof top, kind]
	for t in [[0.11, 0.045, 0.52, 0.42, "cone"], [0.19, 0.035, 0.45, 0.33, "cone"], [0.245, 0.03, 0.41, 0.27, "spire"],
			[0.47, 0.026, 0.37, 0.22, "spire"], [0.555, 0.04, 0.49, 0.40, "cone"], [0.615, 0.03, 0.55, 0.47, "battle"],
			[0.15, 0.022, 0.58, 0.52, "cone"]]:
		_tower(float(t[0]), float(t[1]), base, float(t[2]), float(t[3]), str(t[4]), rng)
	# a gate in the wall, and a little bridge-like stair down the cliff
	_arch(Vector2(0.24, 0.67), 0.012, 0.045, true, Color(0.0, 0.0, 0.0))  # the gate, a lantern burning inside

## Further towers behind the castle, paler in the cold air, so it reads as a great castle with depth, not one wall.
func _far_castle(rng: RandomNumberGenerator) -> void:
	var col := Color(0.085, 0.085, 0.095)
	for t in [[0.16, 0.03, 0.47, 0.36], [0.25, 0.026, 0.42, 0.30], [0.34, 0.05, 0.47, 0.37], [0.39, 0.03, 0.33, 0.20],
			[0.51, 0.034, 0.41, 0.30], [0.60, 0.03, 0.47, 0.38]]:
		var x := float(t[0])
		var w := float(t[1])
		var top := float(t[2])
		_add([Vector2(x, BASE_Y), Vector2(x + w, BASE_Y), Vector2(x + w, top), Vector2(x, top)], col)
		_add([Vector2(x - 0.004, top), Vector2(x + w + 0.004, top), Vector2(x + w * 0.5, float(t[3]))], col)
		_add([Vector2(x + w * 0.5, float(t[3])), Vector2(x - 0.004, top), Vector2(x + 0.002, top - 0.004)], Color(SNOW, 0.35))
		for k in 3:
			if rng.randf() < 0.5:
				var c := Vector2(x + w * 0.5, top + 0.04 + 0.05 * k)
				_add([c + Vector2(-0.002, 0), c + Vector2(0.002, 0), c + Vector2(0.002, 0.012), c + Vector2(-0.002, 0.012)], Color(0.55, 0.42, 0.24, 0.6))

func _block(x0: float, x1: float, base: float, top: float, roof: float) -> void:
	_add([Vector2(x0, base), Vector2(x1, base), Vector2(x1, top), Vector2(x0, top)], STONE)
	var m := (x0 + x1) * 0.5
	_add([Vector2(x0 - 0.006, top), Vector2(x1 + 0.006, top), Vector2(m, roof)], STONE)
	_roof_snow(Vector2(x0 - 0.006, top), Vector2(m, roof), Vector2(x1 + 0.006, top))
	# pinnacles on the corners
	for cx in [x0, x1]:
		_spire(cx, 0.004, top, top - 0.04)

func _hall(x0: float, x1: float, base: float, top: float, roof: float) -> void:
	_add([Vector2(x0, base), Vector2(x1, base), Vector2(x1, top), Vector2(x0, top)], STONE)
	var m := (x0 + x1) * 0.5
	_add([Vector2(x0 - 0.008, top), Vector2(x1 + 0.008, top), Vector2(m, roof)], STONE)
	_roof_snow(Vector2(x0 - 0.008, top), Vector2(m, roof), Vector2(x1 + 0.008, top))
	# buttresses down the side, each with a small pinnacle and a cap of snow
	for k in 4:
		var bx := lerpf(x0, x1, float(k) / 3.0)
		_add([Vector2(bx - 0.004, base), Vector2(bx + 0.004, base), Vector2(bx + 0.003, top + 0.03), Vector2(bx - 0.003, top + 0.03)], Color(0.05, 0.05, 0.055))
		_spire(bx, 0.003, top + 0.01, top - 0.025)
	# the rose window: rings and spokes, faintly lit from inside
	var c := Vector2(m, top + 0.07)
	var rr := 0.022
	_ring(c, rr, Color(0.12, 0.12, 0.13), 28)
	_ring(c, rr * 0.82, Color(0.55, 0.53, 0.48, 0.55), 28)
	for k in 8:
		var a := TAU * k / 8.0
		var p := c + Vector2(cos(a) * rr * 0.8, sin(a) * _wy(rr) * 0.8)
		_add([c + Vector2(cos(a + 0.5) * 0.002, sin(a + 0.5) * 0.003), c + Vector2(cos(a - 0.5) * 0.002, sin(a - 0.5) * 0.003), p], Color(0.07, 0.07, 0.08))
	_ring(c, rr * 0.25, Color(0.07, 0.07, 0.08), 12)
	# tall pointed windows between the buttresses
	for k in 3:
		var wx := lerpf(x0, x1, (k + 0.5) / 3.0)
		_arch(Vector2(wx, top + 0.16), 0.008, 0.08, k != 1)

func _ring(c: Vector2, r: float, col: Color, n: int) -> void:
	var pts: Array = []
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r, sin(a) * _wy(r)))
	_add(pts, col)

func _wall(x0: float, x1: float, base: float, top: float, rng: RandomNumberGenerator) -> void:
	_add([Vector2(x0, base), Vector2(x1, base), Vector2(x1, top), Vector2(x0, top)], Color(0.045, 0.045, 0.05))
	var mw := 0.008
	var x := x0
	while x < x1 - mw:
		_add([Vector2(x, top), Vector2(x + mw, top), Vector2(x + mw, top - 0.014), Vector2(x, top - 0.014)], Color(0.045, 0.045, 0.05))
		_add([Vector2(x - 0.0005, top - 0.014), Vector2(x + mw + 0.0005, top - 0.014), Vector2(x + mw, top - 0.011), Vector2(x, top - 0.011)], Color(SNOW, 0.8))
		x += mw * 2.0
	_add([Vector2(x0, top), Vector2(x1, top), Vector2(x1, top + 0.004), Vector2(x0, top + 0.004)], Color(SNOW, 0.55))
	# loopholes
	for i in 10:
		var lx := rng.randf_range(x0 + 0.01, x1 - 0.01)
		_add([Vector2(lx, top + 0.02), Vector2(lx + 0.0025, top + 0.02), Vector2(lx + 0.0025, top + 0.045), Vector2(lx, top + 0.045)], Color(0, 0, 0))

func _tower(x: float, w: float, base: float, top: float, roof: float, kind: String, rng: RandomNumberGenerator) -> void:
	var x1 := x + w
	_add([Vector2(x, base), Vector2(x1, base), Vector2(x1, top), Vector2(x, top)], STONE)
	# a corbelled ring under the top, slightly wider
	_add([Vector2(x - 0.003, top), Vector2(x1 + 0.003, top), Vector2(x1 + 0.003, top + 0.012), Vector2(x1, top + 0.02), Vector2(x, top + 0.02), Vector2(x - 0.003, top + 0.012)], STONE)
	var m := x + w * 0.5
	match kind:
		"cone":
			_add([Vector2(x - 0.006, top), Vector2(x1 + 0.006, top), Vector2(m, roof)], STONE)
			_roof_snow(Vector2(x - 0.006, top), Vector2(m, roof), Vector2(x1 + 0.006, top))
			_spire(m, 0.0015, roof + 0.004, roof - 0.03)  # the finial
		"spire":
			_add([Vector2(x - 0.004, top), Vector2(x1 + 0.004, top), Vector2(m, roof)], STONE)
			_roof_snow(Vector2(x - 0.004, top), Vector2(m, roof), Vector2(x1 + 0.004, top))
			_spire(m, 0.0012, roof + 0.004, roof - 0.035)
		"battle":
			var mw := w / 5.0
			for k in 3:
				var bx := x - 0.003 + k * mw * 2.0
				_add([Vector2(bx, top), Vector2(bx + mw, top), Vector2(bx + mw, top - 0.016), Vector2(bx, top - 0.016)], STONE)
				_add([Vector2(bx, top - 0.016), Vector2(bx + mw, top - 0.016), Vector2(bx + mw, top - 0.012), Vector2(bx, top - 0.012)], Color(SNOW, 0.85))
	# snow on the corbel ledge
	_add([Vector2(x - 0.0035, top + 0.012), Vector2(x1 + 0.0035, top + 0.012), Vector2(x1 + 0.002, top + 0.016), Vector2(x - 0.002, top + 0.016)], Color(SNOW, 0.75))
	# windows up the tower
	var n := int((base - top) / 0.07)
	for k in n:
		var wy := top + 0.05 + k * 0.07
		if wy > base - 0.04:
			break
		_arch(Vector2(m, wy), w * 0.14, 0.03, rng.randf() < 0.55)

## A steep spire: a thin needle from y0 up to y1.
func _spire(x: float, half_w: float, y0: float, y1: float) -> void:
	_add([Vector2(x - half_w, y0), Vector2(x + half_w, y0), Vector2(x, y1)], STONE)
	_add([Vector2(x, y1 + (y0 - y1) * 0.35), Vector2(x - half_w * 0.9, y0 - 0.002), Vector2(x - half_w * 0.3, y0 - 0.002)], Color(SNOW, 0.45))

## Snow lying on a roof: a band down the left slope (the side the wind drives it onto) and a thin line on the right,
## with a few drips of snow hanging over the eaves.
func _roof_snow(l: Vector2, apex: Vector2, r: Vector2) -> void:
	var th := 0.004
	_add([apex, l, l + Vector2(0.004, th * 2.2), apex + Vector2(0.0, th * 2.5)], Color(SNOW, 0.92))
	_add([apex, r, r + Vector2(-0.002, th * 0.9), apex + Vector2(0.0, th)], Color(SNOW, 0.5))
	for k in 3:
		var p := l.lerp(r, 0.15 + 0.3 * k)
		_add([p + Vector2(-0.003, 0), p + Vector2(0.003, 0), p + Vector2(0.0, 0.007 + 0.003 * k)], Color(SNOW, 0.7))

## A pointed (Gothic) window at `c` (the middle of its top), half width hw, height h. Lit ones glow candle white.
func _arch(c: Vector2, hw: float, h: float, lit: bool, col := Color(0.012, 0.012, 0.014)) -> void:
	var peak := _wy(hw) * 1.6
	var pts := [Vector2(c.x - hw, c.y + h), Vector2(c.x + hw, c.y + h), Vector2(c.x + hw, c.y),
		Vector2(c.x + hw * 0.7, c.y - peak * 0.55), Vector2(c.x, c.y - peak), Vector2(c.x - hw * 0.7, c.y - peak * 0.55), Vector2(c.x - hw, c.y)]
	_add(pts, col)
	if lit:
		_windows.append([c, hw, h, peak, randf() * TAU])
	# a sill of snow
	_add([Vector2(c.x - hw * 1.4, c.y + h), Vector2(c.x + hw * 1.4, c.y + h), Vector2(c.x + hw * 1.2, c.y + h + 0.003), Vector2(c.x - hw * 1.2, c.y + h + 0.003)], Color(SNOW, 0.7))

# ---------- Foreground ----------
func _field(rng: RandomNumberGenerator) -> void:
	var pts := [Vector2(0, 1.0)]
	for i in 21:
		var x := float(i) / 20.0
		pts.append(Vector2(x, 0.905 + 0.018 * sin(x * 7.0 + 1.3) + 0.008 * sin(x * 19.0) + rng.randf_range(-0.002, 0.002)))
	pts.append(Vector2(1.0, 1.0))
	_add(pts, Color(0.70, 0.70, 0.73))
	var lit := [Vector2(0, 1.0)]
	for i in 21:
		var x := float(i) / 20.0
		lit.append(Vector2(x, 0.912 + 0.018 * sin(x * 7.0 + 1.3) + 0.008 * sin(x * 19.0)))
	lit.append(Vector2(1.0, 1.0))
	_add(lit, Color(0.82, 0.82, 0.85))
	# a few drift shadows
	for i in 6:
		var x := rng.randf_range(0.02, 0.95)
		var y := rng.randf_range(0.94, 0.985)
		var w := rng.randf_range(0.06, 0.14)
		_add([Vector2(x, y), Vector2(x + w * 0.5, y - 0.008), Vector2(x + w, y), Vector2(x + w * 0.5, y + 0.004)], Color(0.6, 0.6, 0.64, 0.6))
	# old gravestones and crosses, half buried, each with snow on its top
	for g in [[0.06, 0.93, "stone"], [0.11, 0.945, "cross"], [0.17, 0.94, "stone"], [0.72, 0.935, "cross"], [0.78, 0.95, "stone"], [0.83, 0.94, "stone"]]:
		_grave(Vector2(float(g[0]), float(g[1])), str(g[2]), rng)

func _grave(foot: Vector2, kind: String, rng: RandomNumberGenerator) -> void:
	var lean := rng.randf_range(-0.003, 0.003)
	var col := Color(0.06, 0.06, 0.065)
	if kind == "cross":
		var h := 0.075
		_add([foot + Vector2(-0.003, 0), foot + Vector2(0.003, 0), foot + Vector2(0.003 + lean, -h), foot + Vector2(-0.003 + lean, -h)], col)
		var arm := foot + Vector2(lean * 0.7, -h * 0.72)
		_add([arm + Vector2(-0.013, -0.004), arm + Vector2(0.013, -0.004), arm + Vector2(0.013, 0.005), arm + Vector2(-0.013, 0.005)], col)
		_add([arm + Vector2(-0.014, -0.005), arm + Vector2(0.014, -0.005), arm + Vector2(0.012, -0.002), arm + Vector2(-0.012, -0.002)], Color(SNOW, 0.95))
		_add([foot + Vector2(-0.004 + lean, -h - 0.002), foot + Vector2(0.004 + lean, -h - 0.002), foot + Vector2(0.003 + lean, -h + 0.003), foot + Vector2(-0.003 + lean, -h + 0.003)], Color(SNOW, 0.95))
	else:
		var w := rng.randf_range(0.014, 0.02)
		var h2 := rng.randf_range(0.04, 0.06)
		var pts: Array = [foot + Vector2(-w, 0), foot + Vector2(w, 0), foot + Vector2(w + lean, -h2)]
		for i in 9:
			var a := PI * float(i) / 8.0
			pts.append(foot + Vector2(lean + cos(a) * w, -h2 - sin(a) * _wy(w) * 0.6))
		pts.append(foot + Vector2(-w + lean, -h2))
		_add(pts, col)
		var cap: Array = []
		for i in 9:
			var a2 := PI * float(i) / 8.0
			cap.append(foot + Vector2(lean + cos(a2) * w * 1.05, -h2 - sin(a2) * _wy(w) * 0.6 - 0.003))
		for i in range(8, -1, -1):
			var a3 := PI * float(i) / 8.0
			cap.append(foot + Vector2(lean + cos(a3) * w * 0.8, -h2 - sin(a3) * _wy(w) * 0.6 * (0.55 if absf(cos(a3)) < 0.7 else 0.9)))
		_add(cap, Color(SNOW, 0.95))

## Candles in the bottom corners, close to us: tall and short, with wax run down their sides. Their flames are drawn
## with the moving parts.
func _candles(rng: RandomNumberGenerator) -> void:
	for c in [[0.022, 0.016, 0.20], [0.05, 0.013, 0.13], [0.074, 0.011, 0.09], [0.968, 0.015, 0.17], [0.988, 0.012, 0.11]]:
		var x := float(c[0])
		var hw := float(c[1]) * 0.5
		var h := float(c[2])
		var top := 1.02 - h
		var wax := Color(0.80, 0.77, 0.70)
		_add([Vector2(x - hw, 1.02), Vector2(x + hw, 1.02), Vector2(x + hw, top + 0.006), Vector2(x + hw * 0.4, top), Vector2(x - hw * 0.5, top + 0.004), Vector2(x - hw, top + 0.01)], wax)
		_add([Vector2(x + hw * 0.25, 1.02), Vector2(x + hw, 1.02), Vector2(x + hw, top + 0.006), Vector2(x + hw * 0.4, top + 0.004)], Color(0.55, 0.52, 0.47))  # the shaded side
		for k in rng.randi_range(2, 4):  # drips
			var dx := rng.randf_range(-hw * 0.9, hw * 0.7)
			var dl := rng.randf_range(0.015, 0.06)
			_add([Vector2(x + dx - 0.0018, top + 0.004), Vector2(x + dx + 0.0018, top + 0.004), Vector2(x + dx + 0.0014, top + dl), Vector2(x + dx, top + dl + 0.004), Vector2(x + dx - 0.0014, top + dl)], Color(0.88, 0.85, 0.78))
		_add([Vector2(x - 0.0007, top + 0.002), Vector2(x + 0.0007, top + 0.002), Vector2(x + 0.0004, top - 0.008), Vector2(x - 0.0004, top - 0.008)], Color(0.05, 0.04, 0.03))  # the wick
		_flames.append([Vector2(x, top - 0.006), float(c[1]) * 1.6, rng.randf() * TAU])

## A bare old tree on the right, its branches split again and again, with a line of snow on top of each.
func _tree(rng: RandomNumberGenerator) -> void:
	_branch(Vector2(0.905, 0.93), -PI / 2.0 - 0.1, 0.17, 16.0, 0, rng)

func _branch(from: Vector2, ang: float, length: float, width: float, depth: int, rng: RandomNumberGenerator) -> void:
	var to := from + Vector2(cos(ang) * length / _aspect, sin(ang) * length)
	_lines.append([from, to, Color(0.02, 0.02, 0.025), width])
	if width > 2.5 and cos(ang) != 0.0:
		_lines.append([from + Vector2(0, -0.002), to + Vector2(0, -0.002), Color(SNOW, 0.55), maxf(1.0, width * 0.25)])
	if depth >= 6 or length < 0.02:
		return
	var n := 2 if depth < 2 else rng.randi_range(2, 3)
	for i in n:
		var spread := rng.randf_range(0.3, 0.75) * (1.0 if i % 2 == 0 else -1.0)
		_branch(to, ang + spread, length * rng.randf_range(0.58, 0.75), width * 0.62, depth + 1, rng)

# ---------- Drawing ----------
## The still picture: landscape, castle, field, tree. Drawn only when the window changes size.
func draw_still(cv: CanvasItem, sz: Vector2) -> void:
	for s in _shapes:
		var pts: PackedVector2Array = s[0]
		var px := PackedVector2Array()
		px.resize(pts.size())
		for i in pts.size():
			px[i] = pts[i] * sz
		cv.draw_colored_polygon(px, s[1])
	for l in _lines:
		cv.draw_line((l[0] as Vector2) * sz, (l[1] as Vector2) * sz, l[2], float(l[3]) * sz.y / 1080.0, true)

## The sky behind everything: the moon, its halo and slow clouds (redrawn a few times a second).
func draw_sky(cv: CanvasItem, sz: Vector2, t: float, glow: Texture2D) -> void:
	var mc := Vector2(0.76, 0.2) * sz
	var mr := sz.y * 0.075
	cv.draw_texture_rect(glow, Rect2(mc - Vector2.ONE * mr * 6.0, Vector2.ONE * mr * 12.0), false, Color(1, 1, 1, 0.07))
	cv.draw_texture_rect(glow, Rect2(mc - Vector2.ONE * mr * 2.6, Vector2.ONE * mr * 5.2), false, Color(1, 1, 1, 0.13))
	cv.draw_circle(mc, mr, Color(0.74, 0.74, 0.76))
	for c in [[Vector2(-0.3, -0.2), 0.28], [Vector2(0.25, 0.1), 0.2], [Vector2(-0.05, 0.38), 0.16], [Vector2(0.4, -0.35), 0.12], [Vector2(-0.45, 0.25), 0.1]]:
		cv.draw_circle(mc + (c[0] as Vector2) * mr, float(c[1]) * mr, Color(0.72, 0.72, 0.76, 0.6))
	cv.draw_arc(mc, mr * 0.98, 0, TAU, 64, Color(1, 1, 1, 0.35), 2.0, true)
	# clouds: long soft streaks drifting past the moon
	for k in 4:
		var y := sz.y * (0.12 + 0.07 * k)
		var w := sz.x * (0.35 + 0.1 * (k % 2))
		var x := fposmod(sz.x * (0.2 * k) + t * (6.0 + 3.0 * k), sz.x + w * 2.0) - w
		cv.draw_texture_rect(glow, Rect2(x, y - sz.y * 0.03, w, sz.y * 0.06), false, Color(0.55, 0.55, 0.6, 0.10 + 0.04 * (k % 2)))
		cv.draw_texture_rect(glow, Rect2(x + w * 0.2, y - sz.y * 0.015, w * 0.6, sz.y * 0.03), false, Color(0.06, 0.06, 0.07, 0.35))

## The moving parts in front: candles, bats, mist and falling snow (every frame; all cheap).
func draw_moving(cv: CanvasItem, sz: Vector2, t: float, glow: Texture2D) -> void:
	# candle-lit windows flicker softly
	for w in _windows:
		var c: Vector2 = w[0]
		var f := 0.75 + 0.15 * sin(t * 2.3 + float(w[4])) + 0.1 * sin(t * 7.1 + float(w[4]) * 3.0)
		var hw: float = w[1]
		var h: float = w[2]
		var peak: float = w[3]
		var col := Color(1.0, 0.74, 0.38, 0.9 * f)  # candlelight
		var pts := PackedVector2Array([Vector2(c.x - hw * 0.7, c.y + h * 0.95), Vector2(c.x + hw * 0.7, c.y + h * 0.95), Vector2(c.x + hw * 0.7, c.y),
			Vector2(c.x, c.y - peak * 0.8), Vector2(c.x - hw * 0.7, c.y)])
		for i in pts.size():
			pts[i] *= sz
		cv.draw_colored_polygon(pts, col)
		var cc := Vector2(c.x, c.y + h * 0.4) * sz
		cv.draw_texture_rect(glow, Rect2(cc - Vector2(46, 46) * sz.y / 1080.0, Vector2(92, 92) * sz.y / 1080.0), false, Color(1.0, 0.62, 0.25, 0.16 * f))
		cv.draw_line(Vector2(c.x, c.y - peak * 0.6) * sz, Vector2(c.x, c.y + h * 0.95) * sz, Color(0, 0, 0, 0.8), maxf(1.0, sz.y / 1080.0))  # the mullion
	# the candles in the corners: a warm pool of light around each, and a flame that sways and flickers
	var k_px := sz.y / 1080.0
	for fl in _flames:
		var wick: Vector2 = (fl[0] as Vector2) * sz
		var ph: float = fl[2]
		var f2 := 0.85 + 0.1 * sin(t * 9.0 + ph) + 0.05 * sin(t * 23.0 + ph * 2.0)
		var lean := 3.0 * sin(t * 1.7 + ph) * k_px
		var fw := float(fl[1]) * sz.x * 0.5
		var fh := fw * 3.2 * f2
		cv.draw_texture_rect(glow, Rect2(wick - Vector2(1, 1) * fh * 7.0, Vector2(2, 2) * fh * 7.0), false, Color(1.0, 0.6, 0.22, 0.10 * f2))
		cv.draw_texture_rect(glow, Rect2(wick - Vector2(1, 1) * fh * 2.2, Vector2(2, 2) * fh * 2.2), false, Color(1.0, 0.7, 0.35, 0.22 * f2))
		var tip := wick + Vector2(lean, -fh)
		cv.draw_colored_polygon(PackedVector2Array([wick + Vector2(-fw, 0), wick + Vector2(-fw * 0.7, -fh * 0.45), tip, wick + Vector2(fw * 0.7, -fh * 0.45), wick + Vector2(fw, 0),
			wick + Vector2(fw * 0.5, fw * 0.7), wick + Vector2(-fw * 0.5, fw * 0.7)]), Color(1.0, 0.62, 0.2, 0.85))
		cv.draw_colored_polygon(PackedVector2Array([wick + Vector2(-fw * 0.5, fw * 0.2), wick + Vector2(lean * 0.5, -fh * 0.6), wick + Vector2(fw * 0.5, fw * 0.2), wick + Vector2(0, fw * 0.5)]), Color(1.0, 0.95, 0.8, 0.95))
	# bats circling the spires
	for b in _bats:
		var a := t * float(b["sp"]) + float(b["ph"])
		var p := Vector2(float(b["cx"]) + cos(a) * float(b["rx"]), float(b["cy"]) + sin(a * 1.3) * float(b["ry"])) * sz
		var s := sz.y * 0.008
		var flap := sin(t * 14.0 + float(b["ph"]) * 5.0)
		var tip := -s * (0.2 + 0.9 * flap)
		var bat := Color(0.01, 0.01, 0.012)
		for side in [-1.0, 1.0]:  # each wing a triangle from the body out to its tip, flapping up and down
			cv.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 0.25), p + Vector2(side * s * 1.7, tip), p + Vector2(side * s * 0.8, s * 0.25)]), bat)
		cv.draw_circle(p, s * 0.32, bat)
	# mist drifting along the foot of the cliff
	for k in 3:
		var w2 := sz.x * 0.7
		var x2 := fposmod(sz.x * 0.3 * k + t * (9.0 + 4.0 * k) * (1.0 if k % 2 == 0 else -1.0), sz.x + w2 * 2.0) - w2
		cv.draw_texture_rect(glow, Rect2(x2, sz.y * (0.80 + 0.03 * k), w2, sz.y * 0.12), false, Color(0.85, 0.85, 0.9, 0.07))
	# snow in three depths: far flakes small, slow and faint, near ones big and quick, all swaying in the wind
	var far := PackedVector2Array()
	var far_c := PackedColorArray()
	var wind := 0.04
	for fl in _flakes:
		var d: float = fl["d"]
		var spd := 0.025 + 0.11 * d
		var y := fposmod(float(fl["y"]) + t * spd, 1.06) - 0.03
		var x := fposmod(float(fl["x"]) + t * wind * (0.4 + d) + 0.012 * (0.5 + d) * sin(t * (0.6 + float(fl["k"])) + float(fl["s"])), 1.04) - 0.02
		var p2 := Vector2(x, y) * sz
		var a2 := 0.35 + 0.6 * d
		if d < 0.3:
			var r := (0.8 + 1.6 * d) * sz.y / 1080.0
			far.append_array([p2 - Vector2(r, 0), p2 + Vector2(r, 0)])
			far_c.append(Color(1, 1, 1, a2 * 0.8))
		else:
			cv.draw_circle(p2, (1.2 + 3.6 * d) * sz.y / 1080.0, Color(1, 1, 1, a2))
	if not far.is_empty():
		cv.draw_multiline_colors(far, far_c, 2.0 * sz.y / 1080.0)
