extends Control
## The moving picture behind the start-up logo. Each theme has its own (see boot_overlay.gd):
##   "embers"   Volcanic: a lava glow breathing at the bottom, sparks and grey ash rising
##   "glass"    Sleek: a sheet of light sweeping across brushed metal
##   "tiles"    Channels: soft rings of light spreading from the logo, a blue line along the bottom
##   "bubbles"  Frutiger Aero: glossy bubbles floating up and shafts of sunlight
##   "ps2"      PS2: long grey pillars flying past in the dark and thin bright comets (the logo comes in after)
## All of it is drawn from a clock, so it needs no pictures.

var style := ""
var rays := false
var words: Array = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _p: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if style == "palms" or style == "castle" or style == "basement" or style == "forest" or style == "kingdom" or style == "temple" or style == "cosmos" or style == "pcb":
		# Neon Coast / Gothic: the theme's own sky (turning palms, or the castle in the snow) behind the logo.
		var sky = preload("res://tephra_bg.gd").new()
		add_child(sky)
		sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 11
	for i in 80:
		_p.append({"x": _rng.randf(), "y": _rng.randf(), "v": _rng.randf_range(0.04, 0.16), "r": _rng.randf_range(0.5, 1.0),
			"s": _rng.randf() * TAU, "a": _rng.randf_range(0.3, 1.0)})

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var sz := size
	match style:
		"embers":
			var pulse := 0.75 + 0.25 * sin(_t * 1.6)
			for k in 10:
				var h := sz.y * (0.55 - 0.05 * k)
				draw_rect(Rect2(0, sz.y - h, sz.x, h), Color(0.95, 0.30, 0.05, 0.018 * pulse))
			for p in _p:
				var y := fposmod(float(p["y"]) - _t * float(p["v"]) * 2.0, 1.0)
				var x := float(p["x"]) + 0.02 * sin(_t * 0.8 + float(p["s"]))
				var hot := clampf(y * 1.3, 0.0, 1.0)  # near the bottom: white-hot, higher: dull orange, then grey ash
				var col := Color(1.0, 0.75, 0.35).lerp(Color(0.55, 0.52, 0.5), hot)
				if float(p["r"]) > 0.7:
					col = col.lerp(Color(1.0, 0.45, 0.1), 0.5 * (1.0 - hot))
				draw_circle(Vector2(x, y) * sz, 1.5 + 3.5 * float(p["r"]), Color(col, float(p["a"]) * (1.0 - hot * 0.6)))
		"glass":
			var sweep := fposmod(_t * 0.28, 1.6) - 0.3
			for k in 3:
				var x0 := (sweep - 0.06 * k) * sz.x
				var pts := PackedVector2Array([Vector2(x0 + sz.y * 0.4, 0), Vector2(x0 + sz.y * 0.4 + 140.0, 0), Vector2(x0 + 140.0, sz.y), Vector2(x0, sz.y)])
				draw_colored_polygon(pts, Color(1, 1, 1, 0.22 - 0.06 * k))
		"rain":
			# Gun metal: thin rain falling at a slight slant (no ripples).
			for p in _p:
				var sp := 0.5 + 0.6 * float(p["r"])
				var y := fposmod(float(p["y"]) + _t * sp * 0.6, 1.2) - 0.1
				var x := float(p["x"]) - y * 0.08
				var ln := 26.0 + 50.0 * float(p["r"])
				var a := 0.12 + 0.22 * float(p["a"])
				var top := Vector2(x, y) * sz
				draw_line(top, top + Vector2(-ln * 0.12, ln), Color(0.82, 0.86, 0.92, a), 1.5, true)
		"silk":
			# Wave: slow blue silk ribbons drifting across, like the theme's own background, and a little dust.
			for b in 4:
				var up := PackedVector2Array()
				var dn := PackedVector2Array()
				var ph := _t * (0.35 + 0.1 * b) + b * 1.7
				var base := sz.y * (0.46 + 0.06 * b)
				for i in 49:
					var u := float(i) / 48.0
					var y := base + sin(u * 4.2 + ph) * sz.y * 0.07 + sin(u * 9.0 - ph * 1.3) * sz.y * 0.015
					var th := (16.0 + 46.0 * sin(u * 3.0 + b)) * (0.6 + 0.4 * sin(ph + u * 2.0)) + 30.0
					up.append(Vector2(sz.x * u, y - th))
					dn.append(Vector2(sz.x * u, y + th * 0.6))
				var poly := up.duplicate()
				for i in range(dn.size() - 1, -1, -1):
					poly.append(dn[i])
				draw_colored_polygon(poly, Color(0.6, 0.82, 1.0, 0.09 + 0.02 * b))
				draw_polyline(up, Color(0.7, 0.88, 1.0, 0.4 - 0.07 * b), 2.0, true)
			for p in _p:
				var x: float = float(p["x"])
				var y: float = fposmod(float(p["y"]) - float(p["v"]) * _t * 0.3, 1.0)
				draw_circle(Vector2(x, y) * sz, 1.2 + 1.6 * float(p["r"]), Color(1, 1, 1, float(p["a"]) * 0.35))
		"tiles":
			# Channels: kept simple. Three soft rings of pale blue light spread out from the logo one after the
			# other, and a thin blue line curves along the bottom with one small dot gliding along it.
			var mid := sz * 0.5 - Vector2(0, sz.y * 0.02)
			for k in 3:
				var rk := clampf((_t - 0.2 - k * 0.45) / 1.6, 0.0, 1.0)
				if rk > 0.0 and rk < 1.0:
					var e := 1.0 - pow(1.0 - rk, 3.0)
					draw_arc(mid, sz.y * (0.12 + 0.5 * e), 0.0, TAU, 96, Color(0.45, 0.72, 0.95, 0.55 * (1.0 - rk)), 3.0, true)
					draw_circle(mid, sz.y * (0.12 + 0.5 * e), Color(0.7, 0.86, 1.0, 0.05 * (1.0 - rk)))
			var line_k := clampf((_t - 0.4) / 1.0, 0.0, 1.0)
			var pts2 := PackedVector2Array()
			for i in 41:
				var x := sz.x * i / 40.0
				var u := absf(x / sz.x - 0.5) * 2.0
				pts2.append(Vector2(x, sz.y * 0.9 - sz.y * 0.05 * smoothstep(0.62, 1.0, u)))
			draw_polyline(pts2, Color(0.35, 0.68, 0.95, 0.9 * line_k), 3.0, true)
			var sx := fposmod(_t * 0.35, 1.4) - 0.2
			draw_circle(Vector2(sz.x * sx, sz.y * 0.9 - sz.y * 0.05 * smoothstep(0.62, 1.0, absf(sx - 0.5) * 2.0)), 7.0, Color(1, 1, 1, 0.9 * line_k))
		"bubbles":
			if rays:
				for k in 4:
					var rx := sz.x * (0.0 + 0.25 * k)
					draw_colored_polygon(PackedVector2Array([Vector2(rx, 0), Vector2(rx + 160.0, 0), Vector2(rx + 700.0, sz.y), Vector2(rx + 380.0, sz.y)]), Color(1, 1, 1, 0.07 + 0.02 * sin(_t + k)))
			for p in _p:
				var y := fposmod(1.1 - float(p["y"]) * 0.0 - (_t * float(p["v"]) * 1.4 + float(p["y"])), 1.2) - 0.1
				var c := Vector2(float(p["x"]) + 0.015 * sin(_t * 0.9 + float(p["s"])), y) * sz
				var r := 12.0 + 40.0 * float(p["r"])
				draw_circle(c, r, Color(1, 1, 1, 0.12))
				draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.75), 2.5, true)
				draw_circle(c - Vector2(r, r) * 0.4, r * 0.18, Color(1, 1, 1, 0.95))
		"ps2":
			# Long grey pillars flying past out of the dark, a few see-through squares drifting, and thin bright
			# comets curving across a blue haze. The logo comes in after (see boot_overlay.gd).
			var vp := sz * Vector2(0.5, 0.5)
			var haze := Color(0.08, 0.18, 0.55, 0.0)
			for k in 6:
				draw_circle(vp, sz.y * (0.62 - 0.08 * k), Color(0.10, 0.22, 0.62, 0.035))
			# It opens with a flash of blue-white light in the middle that blooms out and fades.
			var fl := clampf(1.0 - _t / 0.9, 0.0, 1.0)
			if fl > 0.0:
				for k in 5:
					draw_circle(vp, (40.0 + 260.0 * (1.0 - fl)) * (1.0 + k * 0.6), Color(0.6, 0.8, 1.0, 0.12 * fl * fl))
			# When the pillars have gone, a ring of light opens around where the logo lands and a soft glow stays behind it.
			var land := clampf((_t - 1.7) / 1.4, 0.0, 1.0)
			if land > 0.0:
				var ring := 90.0 + 520.0 * land
				draw_arc(vp, ring, 0.0, TAU, 96, Color(0.55, 0.8, 1.0, 0.55 * (1.0 - land)), 3.0 + 6.0 * (1.0 - land), true)
				for k in 6:
					draw_circle(vp, 220.0 - k * 28.0, Color(0.35, 0.6, 1.0, 0.035 * smoothstep(0.0, 0.5, land)))
			var f := sz.y * 0.9
			var lanes := [
				Vector2(-1.5, -0.55), Vector2(-1.1, 0.35), Vector2(-0.8, -0.25), Vector2(-1.7, 0.7), Vector2(-0.6, 0.62),
				Vector2(1.4, -0.6), Vector2(1.0, 0.45), Vector2(0.75, -0.3), Vector2(1.7, 0.55), Vector2(0.62, 0.7),
				Vector2(-0.3, -0.85), Vector2(0.4, -0.9), Vector2(-0.25, 0.9), Vector2(0.35, 0.95),
			]
			var order: Array = []
			for i in lanes.size():
				var zf := fposmod(1.2 + i * 0.77 - _t * (0.5 + 0.04 * (i % 4)), 6.0) + 1.0
				order.append([zf, i])
			order.sort_custom(func(p, q): return p[0] > q[0])  # far ones first
			for o in order:
				var i: int = o[1]
				var z1: float = o[0]
				var z2 := z1 + 4.0 + 1.0 * (i % 3)
				var lane: Vector2 = lanes[i]
				var h := 0.09 + 0.03 * (i % 3)
				var fade := clampf(1.0 - (z1 - 1.0) / 5.6, 0.0, 1.0) * 0.9 * clampf((_t - 0.1 * i * 0.3) / 0.8, 0.0, 1.0)
				fade *= clampf((z1 - 1.0) / 0.4, 0.0, 1.0)  # dissolves just before it would pass the screen
				fade *= 1.0 - smoothstep(1.3, 2.3, _t)  # the pillars clear the stage before the logo lands
				var xin := lane.x - h if lane.x > 0.0 else lane.x + h
				var yin := lane.y - h if lane.y > 0.0 else lane.y + h
				var px := func(x: float, y: float, z: float) -> Vector2: return vp + Vector2(x, y) * f / z
				var fx := PackedVector2Array([px.call(xin, lane.y - h, z1), px.call(xin, lane.y + h, z1), px.call(xin, lane.y + h, z2), px.call(xin, lane.y - h, z2)])
				draw_colored_polygon(fx, Color(0.38, 0.45, 0.64, 0.95 * fade))
				var fy := PackedVector2Array([px.call(lane.x - h, yin, z1), px.call(lane.x + h, yin, z1), px.call(lane.x + h, yin, z2), px.call(lane.x - h, yin, z2)])
				draw_colored_polygon(fy, Color(0.55, 0.62, 0.80, 0.95 * fade))
				var cap := PackedVector2Array([px.call(lane.x - h, lane.y - h, z1), px.call(lane.x + h, lane.y - h, z1), px.call(lane.x + h, lane.y + h, z1), px.call(lane.x - h, lane.y + h, z1)])
				draw_colored_polygon(cap, Color(0.72, 0.78, 0.93, 0.98 * fade))
			for k in 10:
				var p: Dictionary = _p[k]
				var c := Vector2(fposmod(float(p["x"]) + _t * 0.006 * (k % 3 + 1), 1.0), fposmod(float(p["y"]) + _t * 0.004, 1.0)) * sz
				var u := 16.0 + 26.0 * float(p["r"])
				var al := 0.10 + 0.07 * sin(_t * 0.9 + float(p["s"]))
				draw_rect(Rect2(c - Vector2(u, u) / 2.0, Vector2(u, u)), Color(0.55, 0.65, 0.9, al))
			var cols := [Color(0.3, 1.0, 0.4), Color(0.95, 0.35, 0.95), Color(1.0, 0.25, 0.25), Color(0.45, 0.5, 1.0)]
			for k in 4:
				var ph := fposmod(_t * 0.32 + k * 0.27, 1.0)
				var start := Vector2(sz.x * [0.30, 0.55, 0.70, 0.62][k], sz.y * [0.52, 0.28, 0.45, 0.62][k])
				var end := start + Vector2([240.0, 330.0, 260.0, -120.0][k], [-30.0, 70.0, 90.0, -210.0][k])
				var ctl := (start + end) / 2.0 + Vector2(0.0, -70.0 if k != 3 else 40.0)
				var prev := start
				for s in range(1, 26):
					var u2 := float(s) / 25.0
					var q := start.lerp(ctl, u2).lerp(ctl.lerp(end, u2), u2)
					var vis := clampf((ph * 1.4 - u2 * 0.55), 0.0, 1.0) * (1.0 - clampf(ph * 1.4 - 1.0, 0.0, 1.0))
					if u2 < ph * 1.1 and u2 > ph * 1.1 - 0.45:
						var tail := 1.0 - (ph * 1.1 - u2) / 0.45
						draw_line(prev, q, Color(cols[k], 0.8 * tail), 2.0, true)
					prev = q
				var head := start.lerp(ctl, ph * 1.1).lerp(ctl.lerp(end, ph * 1.1), ph * 1.1)
				if ph * 1.1 < 1.0:
					draw_circle(head, 6.0, Color(cols[k], 0.25))
					draw_circle(head, 2.6, Color(1, 1, 1, 0.95))
