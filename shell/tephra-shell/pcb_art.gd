extends RefCounted
## The Circuit theme's board: a dark green printed circuit board seen from above. Bundles of copper traces with
## diagonal jogs, round pads and vias, little resistors and capacitors, white silkscreen words, mounting holes in
## the corners and a few LEDs breathing slowly. Original drawing. tephra_bg.gd draws it behind everything; the chips the
## games sit on (and the traces joining them) are board.gd's.

var _vias: Array = []
var _parts: Array = []
var _buses: Array = []
var _words: Array = []
var _leds: Array = []

const WORDS := ["GND", "VCC", "3V3", "SDA", "SCL", "CLK", "RST", "TX", "RX", "D0", "D1", "A7", "IO", "PWR", "OUT", "EN"]

func make() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for i in 130:
		_vias.append({"p": Vector2(rng.randf(), rng.randf()), "r": rng.randf_range(3.0, 6.5), "hole": rng.randf() < 0.7})
	for i in 46:
		var horiz := rng.randf() < 0.5
		_parts.append({
			"p": Vector2(rng.randf(), rng.randf()), "h": horiz, "kind": rng.randi() % 3,
			"s": rng.randf_range(0.8, 1.3), "tag": "%s%d" % [["R", "C", "L"][rng.randi() % 3], rng.randi_range(1, 48)]})
	for b in 9:
		var y := rng.randf_range(0.05, 0.95)
		var lanes := rng.randi_range(2, 4)
		var pts: Array = []
		var x := -0.05
		var yy := y
		while x < 1.1:
			pts.append(Vector2(x, yy))
			x += rng.randf_range(0.08, 0.22)
			pts.append(Vector2(x, yy))
			var dy := rng.randf_range(-0.07, 0.07)
			x += absf(dy)
			yy += dy
		_buses.append({"pts": pts, "lanes": lanes})
	for i in 22:
		_words.append({"p": Vector2(rng.randf(), rng.randf()), "w": WORDS[rng.randi() % WORDS.size()], "rot": rng.randf() < 0.3})
	for i in 7:
		_leds.append({"p": Vector2(rng.randf_range(0.04, 0.96), rng.randf_range(0.06, 0.94)), "c": [Color(1, 0.25, 0.2), Color(0.3, 1, 0.45), Color(1, 0.8, 0.25)][rng.randi() % 3], "ph": rng.randf() * TAU})

func draw(cv: CanvasItem, sz: Vector2, t: float) -> void:
	var cu := Color(0.78, 0.62, 0.28, 0.2)  # copper, faint (this is only the backdrop)
	var shade := Color(0.0, 0.07, 0.04, 0.35)
	# trace bundles
	for b in _buses:
		var pts: Array = b["pts"]
		for lane in int(b["lanes"]):
			var off := Vector2(0, (float(lane) - float(b["lanes"]) * 0.5) * 11.0)
			var line := PackedVector2Array()
			for p in pts:
				line.append((p as Vector2) * sz + off)
			cv.draw_polyline(line, shade, 7.0, true)
			cv.draw_polyline(line, cu, 3.5, true)
	# vias and pads
	for v in _vias:
		var p: Vector2 = (v["p"] as Vector2) * sz
		var r: float = float(v["r"])
		cv.draw_circle(p, r + 2.0, shade)
		cv.draw_circle(p, r, Color(0.82, 0.68, 0.34, 0.3))
		if bool(v["hole"]):
			cv.draw_circle(p, r * 0.45, Color(0.01, 0.06, 0.03, 0.9))
	# small parts: resistors, capacitors, inductors
	for q in _parts:
		var p: Vector2 = (q["p"] as Vector2) * sz
		var s: float = float(q["s"])
		var size := Vector2(34, 16) * s if bool(q["h"]) else Vector2(16, 34) * s
		var r := Rect2(p - size * 0.5, size)
		var body: Color = [Color(0.08, 0.08, 0.09, 0.85), Color(0.55, 0.42, 0.22, 0.8), Color(0.2, 0.2, 0.24, 0.85)][int(q["kind"])]
		cv.draw_rect(r.grow(2), shade)
		cv.draw_rect(r, body)
		var cap := size * (Vector2(0.22, 1.0) if bool(q["h"]) else Vector2(1.0, 0.22))
		cv.draw_rect(Rect2(r.position, cap), Color(0.78, 0.78, 0.74, 0.7))
		cv.draw_rect(Rect2(r.end - cap, cap), Color(0.78, 0.78, 0.74, 0.7))
	# silkscreen: tags and signal names
	var font := ThemeDB.fallback_font
	for q in _parts:
		var p: Vector2 = (q["p"] as Vector2) * sz + Vector2(-14, 32)
		cv.draw_string(font, p, str(q["tag"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.92, 0.96, 0.9, 0.22))
	for w in _words:
		var p: Vector2 = (w["p"] as Vector2) * sz
		cv.draw_string(font, p, str(w["w"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.92, 0.96, 0.9, 0.2))
	# mounting holes in the four corners
	for c in [Vector2(46, 46), Vector2(sz.x - 46, 46), Vector2(46, sz.y - 46), Vector2(sz.x - 46, sz.y - 46)]:
		cv.draw_circle(c, 26, Color(0.82, 0.68, 0.34, 0.35))
		cv.draw_circle(c, 18, Color(0.0, 0.05, 0.03, 0.9))
		cv.draw_arc(c, 32, 0, TAU, 28, Color(0.92, 0.96, 0.9, 0.25), 2.0)
	# LEDs
	for l in _leds:
		var p: Vector2 = (l["p"] as Vector2) * sz
		var a := 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 1.3 + float(l["ph"])))
		var col: Color = l["c"]
		cv.draw_circle(p, 16, Color(col, 0.12 * a))
		cv.draw_circle(p, 8, Color(col, 0.35 * a))
		cv.draw_circle(p, 4, Color(1, 1, 1, 0.25 + 0.6 * a))
