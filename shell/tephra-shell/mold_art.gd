extends RefCounted
## Mold theme backdrop: the downstairs corridor of an old, rotting house, seen down its length. Cinder-block walls
## gone brown with damp, a stained ceiling with roots pushing through it, a wet concrete floor with puddles, and black,
## glossy mold spreading out of every seam in thick veins and clusters, running down the walls and creeping over the
## floor. A doorway at the far end opens on an empty room lit by one dying bulb. A weak flashlight beam drifts slowly
## as if someone is holding it, and the dark closes in tight around it; water drips from the ceiling into the puddles.
## Nobody else is here. All original, drawn from code.
## The still parts are built once into shapes and drawn on their own layer only when the window changes size; the
## moving parts (drips, ripples, dust in the beam, the flicker) are a few cheap draws a frame.

var _shapes: Array = []      # [PackedVector2Array in 0..1 screen units, Color or PackedColorArray], back to front
var _lines: Array = []       # [Vector2 a, Vector2 b, Color, width in px at 1080p]
var _drips: Array = []       # {x (across), d (depth), period, phase}
var _dust: Array = []
var _shade_tex: GradientTexture2D  # clear in the middle, black at the edge: the dark around the beam

const VP := Vector2(0.56, 0.46)                 # where the corridor vanishes
const NEAR := Rect2(-0.08, -0.12, 1.16, 1.24)   # the corridor's cross-section where it meets the screen
const Z := 6.7                                  # depth 1 (the far wall) is 1 / (1 + Z) the size of the near frame
const BLOCK := Color(0.23, 0.205, 0.17)
const MORTAR := Color(0.10, 0.09, 0.075)
const MOLD := Color(0.022, 0.019, 0.016)
const SHEEN := Color(0.52, 0.5, 0.44)

## A point of the corridor: x, y across the cross-section (0..1, left to right, ceiling to floor) at depth d.
func _p(x: float, y: float, d: float) -> Vector2:
	var near := NEAR.position + Vector2(x, y) * NEAR.size
	return VP + (near - VP) / (1.0 + d * Z)

## A point on one surface: "L"/"R" walls (a = height 0 ceiling..1 floor, b = depth), "C"/"F" ceiling and floor
## (a = across, b = depth), "B" the far wall (a = across, b = height).
func _w(wall: String, a: float, b: float) -> Vector2:
	match wall:
		"L": return _p(0.0, a, b)
		"R": return _p(1.0, a, b)
		"C": return _p(a, 0.0, b)
		"F": return _p(a, 1.0, b)
	return _p(a, b, 1.0)

## How bright a surface is at depth d (the far end is in the dark).
func _lit(d: float) -> float:
	return 1.0 / (1.0 + d * 3.4)

func _add(pts: Array, col) -> void:
	var pk := PackedVector2Array(pts)
	var test := PackedVector2Array()
	for p in pk:
		test.append(p * Vector2(1920, 1080))
	if Geometry2D.triangulate_polygon(test).is_empty():
		var hull := Geometry2D.convex_hull(pk)
		if hull.size() < 4:
			return
		hull.remove_at(hull.size() - 1)
		pk = hull
		if col is PackedColorArray:
			col = (col as PackedColorArray)[0]
	_shapes.append([pk, col])

func _quad(wall: String, a0: float, a1: float, b0: float, b1: float, col: Color, shade := true) -> void:
	var cs := PackedColorArray()
	for v in [[a0, b0], [a1, b0], [a1, b1], [a0, b1]]:
		var k := _lit(float(v[1])) if shade else 1.0
		cs.append(Color(col.r * k, col.g * k, col.b * k, col.a))
	_add([_w(wall, a0, b0), _w(wall, a1, b0), _w(wall, a1, b1), _w(wall, a0, b1)], cs)

func make() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2017
	_shapes.clear()
	_lines.clear()
	_surfaces(rng)
	_stains(rng)
	_puddles(rng)
	for c in [["L", 0.97, 0.15, 1.0], ["L", 0.95, 0.55, 0.7], ["R", 0.96, 0.08, 1.2], ["R", 0.4, 0.12, 1.4],
			["R", 0.03, 0.3, 0.8], ["L", 0.04, 0.25, 0.9], ["C", 0.05, 0.4, 0.7], ["C", 0.92, 0.6, 0.6],
			["F", 0.06, 0.3, 0.8], ["F", 0.95, 0.5, 0.7], ["B", 0.3, 0.6, 0.8], ["B", 0.72, 0.3, 0.7], ["L", 0.6, 0.06, 0.8]]:
		_cluster(rng, c[0], float(c[1]), float(c[2]), float(c[3]))
	# More, everywhere: along every seam, over the walls, round the door, across the floor.
	for i in 30:
		var wall: String = ["L", "R", "C", "F", "B"][i % 5]
		var a := rng.randf() if wall in ["C", "F", "B"] else (rng.randf_range(0.82, 1.0) if i % 3 == 0 else (rng.randf_range(0.0, 0.18) if i % 3 == 1 else rng.randf()))
		_cluster(rng, wall, a, rng.randf_range(0.05, 0.95) if wall != "B" else rng.randf(), rng.randf_range(0.4, 1.3))
	_runs(rng)
	for i in 70:
		var wall: String = ["L", "R", "C", "F", "R", "L"][i % 6]
		_vein(rng, wall, rng.randf_range(0.0, 1.0) if wall in ["C", "F"] else (rng.randf_range(0.85, 1.0) if i % 2 == 0 else rng.randf_range(0.0, 0.12)),
			rng.randf_range(0.05, 0.9), rng.randf_range(4.0, 7.0), 0)
	_roots(rng)
	_sign()
	_drips.clear()
	for i in 6:
		_drips.append({"x": rng.randf_range(0.15, 0.85), "d": rng.randf_range(0.08, 0.8), "period": rng.randf_range(2.2, 4.5), "phase": rng.randf() * 5.0})
	_dust.clear()
	for i in 90:
		_dust.append({"x": rng.randf(), "y": rng.randf(), "s": rng.randf() * TAU, "k": rng.randf()})
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.98)])
	_shade_tex = GradientTexture2D.new()
	_shade_tex.gradient = g
	_shade_tex.fill = GradientTexture2D.FILL_RADIAL
	_shade_tex.fill_from = Vector2(0.5, 0.5)
	_shade_tex.fill_to = Vector2(1.0, 0.5)
	_shade_tex.width = 256
	_shade_tex.height = 256

# ---------- The corridor ----------
func _depth_at(j: float) -> float:
	return j / 22.0  # 22 blocks down the length

func _surfaces(rng: RandomNumberGenerator) -> void:
	# behind everything: the mortar colour, so the gaps between blocks show it
	for wall in ["L", "R"]:
		_quad(wall, 0.0, 1.0, 0.0, 1.0, MORTAR)
	# cinder blocks, 13 courses high, each course offset by half a block, every block a little different
	for wall in ["L", "R"]:
		for r in 13:
			var a0 := r / 13.0 + 0.004
			var a1 := (r + 1) / 13.0 - 0.004
			var off := 0.5 if r % 2 == 1 else 0.0
			for j in range(-1, 22):
				var b0 := maxf(_depth_at(j + off) + 0.002, 0.0)
				var b1 := minf(_depth_at(j + 1 + off) - 0.002, 1.0)
				if b1 <= b0:
					continue
				var damp := smoothstep(0.55, 1.0, a1) * 0.35 + rng.randf() * 0.12  # darker low down, where the water rises
				var col := BLOCK.darkened(damp).lerp(Color(0.2, 0.19, 0.15), rng.randf() * 0.25)
				_quad(wall, a0, a1, b0, b1, col)
	# the ceiling: old plaster boards, sagging, with beams across
	_quad("C", 0.0, 1.0, 0.0, 1.0, Color(0.20, 0.185, 0.155))
	for j in 7:
		var b := 0.04 + j * 0.15
		_quad("C", 0.0, 1.0, b, b + 0.025, Color(0.12, 0.10, 0.08))
	# the floor: wet concrete, darker in the middle where people walked
	var fc := PackedColorArray()
	for v in [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]:
		var k := _lit(float(v[1]))
		fc.append(Color(0.15 * k, 0.142 * k, 0.125 * k))
	_add([_w("F", 0.0, 0.0), _w("F", 1.0, 0.0), _w("F", 1.0, 1.0), _w("F", 0.0, 1.0)], fc)
	for j in 12:
		var b := j / 12.0
		_lines.append([_w("F", 0.0, b), _w("F", 1.0, b), Color(0.06, 0.055, 0.05, 0.5), 1.5])  # slab joints
	# the far wall and its doorway onto the dark room
	_quad("B", 0.0, 1.0, 0.0, 1.0, Color(0.075, 0.068, 0.058), false)
	for r in 13:
		_lines.append([_w("B", 0.0, r / 13.0), _w("B", 1.0, r / 13.0), Color(0.04, 0.035, 0.03, 0.8), 1.0])
	_add([_w("B", 0.37, 0.24), _w("B", 0.63, 0.24), _w("B", 0.63, 1.0), _w("B", 0.37, 1.0)], Color(0.012, 0.011, 0.01))
	for e in [[0.36, 0.37], [0.63, 0.64]]:
		_add([_w("B", e[0], 0.22), _w("B", e[1], 0.22), _w("B", e[1], 1.0), _w("B", e[0], 1.0)], Color(0.11, 0.09, 0.07))  # the door frame
	_add([_w("B", 0.36, 0.22), _w("B", 0.64, 0.22), _w("B", 0.64, 0.245), _w("B", 0.36, 0.245)], Color(0.11, 0.09, 0.07))
	# the seams where the walls meet the floor and the ceiling, darker
	for wall in ["L", "R"]:
		for a in [0.0, 1.0]:
			_lines.append([_w(wall, a, 0.0), _w(wall, a, 1.0), Color(0.02, 0.018, 0.015, 0.9), 5.0])

## Water stains running down from the ceiling, and rust-brown tide marks low on the walls.
func _stains(rng: RandomNumberGenerator) -> void:
	for i in 34:
		var wall: String = "L" if i % 2 == 0 else "R"
		var b := rng.randf_range(0.0, 0.95)
		var len := rng.randf_range(0.15, 0.7)
		var w := rng.randf_range(4.0, 14.0) * _lit(b) * 2.0
		_lines.append([_w(wall, 0.0, b), _w(wall, len, b), Color(0.08, 0.06, 0.04, 0.35), w])
	for i in 16:
		var c := Vector2(rng.randf(), rng.randf())
		var r := rng.randf_range(0.03, 0.09)
		var pts := []
		for k in 14:
			var ang := TAU * k / 14.0
			pts.append(_w("C", c.x + cos(ang) * r * rng.randf_range(0.7, 1.2), c.y + sin(ang) * r * 0.6 * rng.randf_range(0.7, 1.2)))
		_add(pts, Color(0.10, 0.08, 0.055, 0.5))

func _puddles(rng: RandomNumberGenerator) -> void:
	for i in 9:
		var c := Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.02, 0.85))
		var r := rng.randf_range(0.06, 0.18)
		var pts := []
		for k in 18:
			var ang := TAU * k / 18.0
			pts.append(_w("F", c.x + cos(ang) * r * rng.randf_range(0.75, 1.15), c.y + sin(ang) * r * 0.35 * rng.randf_range(0.75, 1.15)))
		var k2 := _lit(c.y)
		_add(pts, Color(0.32 * k2, 0.31 * k2, 0.29 * k2, 0.55))

# ---------- The mold ----------
## A clump of mold: a dark heart of overlapping blobs, smaller ones scattered round it, a brown halo of mildew,
## and a wet shine on the bigger blobs. On a surface, centred at (a, b), `r` across.
func _cluster(rng: RandomNumberGenerator, wall: String, a: float, b: float, r: float) -> void:
	r *= 0.12
	var squash := {"L": 0.32, "R": 0.32, "C": 0.5, "F": 0.5, "B": 1.6}.get(wall, 1.0) as float  # so a blob is round on screen
	for i in 6:
		_blob(rng, wall, a + rng.randf_range(-r, r) * 1.6, b + rng.randf_range(-r, r) * 1.6 * squash, r * rng.randf_range(0.7, 1.3), squash, Color(0.09, 0.07, 0.045, 0.35), false)
	for i in 16:
		var spread := pow(rng.randf(), 1.5) * r * 1.8
		var ang := rng.randf() * TAU
		_blob(rng, wall, a + cos(ang) * spread, b + sin(ang) * spread * squash, r * (0.55 - spread / (r * 4.0)) * rng.randf_range(0.6, 1.2), squash, MOLD, true)
	for i in 5:
		_vein(rng, wall, a, b, rng.randf_range(2.0, 4.0), 1)

func _blob(rng: RandomNumberGenerator, wall: String, a: float, b: float, r: float, squash: float, col: Color, shine: bool) -> void:
	if r <= 0.002:
		return
	var pts := []
	var n := 16
	for k in n:
		var ang := TAU * k / n
		var rr := r * (0.75 + 0.35 * rng.randf())
		pts.append(_w(wall, a + cos(ang) * rr, b + sin(ang) * rr * squash))
	_add(pts, col)
	if shine and r > 0.012:
		var hl := []
		for k in 5:
			var ang := -2.4 + k * 0.25
			hl.append(_w(wall, a + cos(ang) * r * 0.55, b + sin(ang) * r * 0.55 * squash))
		for k in 4:
			_lines.append([hl[k], hl[k + 1], Color(SHEEN, 0.45), 1.6])

## A vein of mold creeping along a surface, thinning as it goes and forking now and then.
func _vein(rng: RandomNumberGenerator, wall: String, a: float, b: float, width: float, depth: int) -> void:
	var heading := rng.randf() * TAU
	var squash := {"L": 0.32, "R": 0.32, "C": 0.5, "F": 0.5, "B": 1.6}.get(wall, 1.0) as float
	var p := Vector2(a, b)
	var steps := rng.randi_range(8, 18)
	for i in steps:
		heading += rng.randf_range(-0.6, 0.6)
		var q := p + Vector2(cos(heading), sin(heading) * squash) * 0.025
		q.x = clampf(q.x, 0.0, 1.0)
		q.y = clampf(q.y, 0.0, 1.0)
		var w := width * (1.0 - float(i) / steps) * 1.6 * _lit(q.y if wall != "B" else 1.0) + 0.6
		_lines.append([_w(wall, p.x, p.y), _w(wall, q.x, q.y), MOLD, w])
		if w > 3.0:
			_lines.append([_w(wall, p.x, p.y), _w(wall, q.x, q.y), Color(SHEEN, 0.18), 1.0])
		if depth < 2 and rng.randf() < 0.12:
			_vein(rng, wall, q.x, q.y, width * 0.5, depth + 1)
		p = q

## Roots and tendrils hanging down from the ceiling, swollen with mold where they come through.
func _roots(rng: RandomNumberGenerator) -> void:
	for i in 14:
		var x := rng.randf_range(0.05, 0.95)
		var d := rng.randf_range(0.02, 0.8)
		var top := _w("C", x, d)
		var s := 1.0 / (1.0 + d * Z)
		var len := rng.randf_range(0.08, 0.3) * s * NEAR.size.y
		var p := top
		var sway := rng.randf_range(-1.0, 1.0)
		var seg := 7
		for k in seg:
			var t := float(k + 1) / seg
			var q := top + Vector2(sway * 0.03 * s * sin(t * 3.0 + i), len * t)
			_lines.append([p, q, Color(0.035, 0.03, 0.024), (7.0 * (1.0 - t) + 1.0) * s * 2.2])
			p = q
		_blob(rng, "C", x, d, 0.02 + rng.randf() * 0.02, 0.5, MOLD, true)

## A floor number painted on a little plate on the left wall.
var _sign_rect := PackedVector2Array()
func _sign() -> void:
	_sign_rect = PackedVector2Array([_w("L", 0.3, 0.42), _w("L", 0.3, 0.5), _w("L", 0.4, 0.5), _w("L", 0.4, 0.42)])
	var cs := PackedColorArray()
	for i in 4:
		cs.append(Color(0.42, 0.39, 0.32))
	_add(Array(_sign_rect), cs)

func draw_still(cv: CanvasItem, sz: Vector2) -> void:
	var k := sz.y / 1080.0
	for s in _shapes:
		var pts: PackedVector2Array = s[0]
		var px := PackedVector2Array()
		px.resize(pts.size())
		for i in pts.size():
			px[i] = pts[i] * sz
		if s[1] is PackedColorArray:
			cv.draw_polygon(px, s[1])
		else:
			cv.draw_colored_polygon(px, s[1])
	for l in _lines:
		cv.draw_line((l[0] as Vector2) * sz, (l[1] as Vector2) * sz, l[2], float(l[3]) * k, true)
	if _sign_rect.size() == 4:
		var c := (_sign_rect[0] + _sign_rect[2]) * 0.5 * sz
		var h := (_sign_rect[1].y - _sign_rect[0].y) * sz.y
		var font := ThemeDB.fallback_font
		var fs := int(h * 0.7)
		var tw := font.get_string_size("1F", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		cv.draw_string(font, c + Vector2(-tw * 0.5, fs * 0.35), "1F", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.06, 0.05, 0.85))

## Where the flashlight points: it drifts slowly, like a hand that is not quite steady.
func beam_centre(t: float) -> Vector2:
	return Vector2(0.56 + 0.07 * sin(t * 0.21) + 0.02 * sin(t * 0.67 + 1.0), 0.53 + 0.05 * sin(t * 0.29 + 2.0) + 0.012 * sin(t * 1.3))

## The moving parts: the far room's light and what stands in it, drips and their ripples, dust in the beam,
## and then the dark closing in around the beam (every frame; all cheap).
func draw_moving(cv: CanvasItem, sz: Vector2, t: float, glow: Texture2D) -> void:
	var k := sz.y / 1080.0
	# the far room: a weak bulb somewhere inside, now and then stuttering
	var fl := 0.8 + 0.2 * sin(t * 1.7)
	if fposmod(t, 11.0) > 10.4:
		fl *= 0.3 + 0.7 * (1.0 if fposmod(t * 23.0, 1.0) >= 0.5 else 0.0)
	var door := PackedVector2Array([_w("B", 0.37, 0.245) * sz, _w("B", 0.63, 0.245) * sz, _w("B", 0.63, 1.0) * sz, _w("B", 0.37, 1.0) * sz])
	var top_c := Color(0.05 * fl, 0.04 * fl, 0.025 * fl)
	var low_c := Color(0.11 * fl, 0.09 * fl, 0.055 * fl)
	cv.draw_polygon(door, PackedColorArray([top_c, top_c, low_c, low_c]))
	# drips falling from the ceiling, and the ring each one leaves in the water
	for d in _drips:
		var period: float = d["period"]
		var ph := fposmod(t + float(d["phase"]), period)
		var top := _p(float(d["x"]), 0.0, float(d["d"])) * sz
		var floor_p := _p(float(d["x"]), 1.0, float(d["d"])) * sz
		var s := 1.0 / (1.0 + float(d["d"]) * Z)
		var fall := 0.55
		if ph < fall:
			var f := ph / fall
			var y := lerpf(top.y, floor_p.y, f * f)
			cv.draw_line(Vector2(top.x, y - 10.0 * s * k * (1.0 + 2.0 * f)), Vector2(top.x, y), Color(0.75, 0.78, 0.8, 0.45), 2.0 * s * k + 0.8)
		else:
			var rt := (ph - fall) / 1.4
			if rt < 1.0:
				var rw := (20.0 + 160.0 * rt) * s * k
				var ring := PackedVector2Array()
				for i in 21:
					var ang := TAU * i / 20.0
					ring.append(floor_p + Vector2(cos(ang) * rw, sin(ang) * rw * 0.22))
				cv.draw_polyline(ring, Color(0.7, 0.72, 0.72, 0.3 * (1.0 - rt)), 1.2, true)
		# a bead of water gathering where the next drop will fall
		cv.draw_circle(top + Vector2(0, 3.0 * s * k), 2.5 * s * k + 0.6, Color(0.6, 0.62, 0.62, 0.4))
	# dust floating in the beam
	var bc := beam_centre(t) * sz
	for p in _dust:
		var pos := Vector2(fposmod(float(p["x"]) + t * 0.004 * (0.5 + float(p["k"])), 1.0) * sz.x,
			fposmod(float(p["y"]) + sin(t * 0.3 + float(p["s"])) * 0.01 + t * 0.002, 1.0) * sz.y)
		var near_beam := 1.0 - clampf(pos.distance_to(bc) / (sz.y * 0.32), 0.0, 1.0)
		if near_beam > 0.0:
			cv.draw_rect(Rect2(pos, Vector2.ONE * (1.0 + 1.5 * float(p["k"])) * k), Color(0.9, 0.85, 0.75, 0.35 * near_beam))
	# the dark: only what the beam reaches can be seen
	var r := sz.y * 0.75
	cv.draw_texture_rect(_shade_tex, Rect2(bc - Vector2(r, r) * Vector2(1.25, 1.0), Vector2(r * 2.5, r * 2.0)), false)
	cv.draw_rect(Rect2(0, 0, maxf(bc.x - r * 1.25, 0.0), sz.y), Color(0, 0, 0, 0.98))
	cv.draw_rect(Rect2(bc.x + r * 1.25, 0, sz.x, sz.y), Color(0, 0, 0, 0.98))

## The light of the beam itself, added on top (this layer blends by adding light).
func draw_light(cv: CanvasItem, sz: Vector2, t: float, glow: Texture2D) -> void:
	var bc := beam_centre(t) * sz
	var flick := 1.0
	if fposmod(t, 17.0) > 16.6:
		flick = 0.4 + 0.6 * (1.0 if fposmod(t * 19.0, 1.0) >= 0.4 else 0.0)  # the batteries are not what they were
	var r := sz.y * 0.55
	cv.draw_texture_rect(glow, Rect2(bc - Vector2(r, r * 0.85), Vector2(r * 2.0, r * 1.7)), false, Color(0.26, 0.23, 0.18, 0.42 * flick))
	r = sz.y * 0.22
	cv.draw_texture_rect(glow, Rect2(bc - Vector2(r, r * 0.85), Vector2(r * 2.0, r * 1.7)), false, Color(0.32, 0.30, 0.25, 0.5 * flick))

## Mold running down the walls in long black streaks from the ceiling seam, thick at the top and thinning out, some
## reaching the floor where it pools.
func _runs(rng: RandomNumberGenerator) -> void:
	for i in 40:
		var wall: String = "L" if i % 2 == 0 else "R"
		var b := rng.randf_range(0.0, 0.95)
		var len := rng.randf_range(0.2, 1.0)
		var w := rng.randf_range(5.0, 16.0)
		var a := 0.0
		var steps := 8
		for k in steps:
			var a2 := len * float(k + 1) / steps
			var b2 := b + rng.randf_range(-0.004, 0.004)
			var ww := w * (1.0 - 0.8 * float(k) / steps) * _lit(b) * 2.0 + 0.8
			_lines.append([_w(wall, a, b), _w(wall, a2, b2), MOLD, ww])
			if ww > 4.0:
				_lines.append([_w(wall, a, b), _w(wall, a2, b2), Color(SHEEN, 0.12), 1.0])
			a = a2
			b = b2
		if len > 0.9:
			_blob(rng, "F", 0.02 if wall == "L" else 0.98, b, 0.03, 0.5, MOLD, true)
