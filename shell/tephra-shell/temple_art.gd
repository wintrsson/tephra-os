extends RefCounted
## Temple: a homage to a very old kind of computer screen. A fixed 16-colour palette (the classic EGA colours), big
## square pixels, white windows in double blue frames, red underlined hyperlinks, a blue status bar with the time and
## frame rate, a picture window with a slowly turning yellow cross, and a box that says a few calm words.
## Everything is original drawing and text; nothing here is taken from any real system. draw() is called every frame
## that the background moves.

const WHITE := Color("FFFFFF")
const BLUE := Color("0000AA")
const CYAN := Color("55FFFF")
const GREEN := Color("00AA00")
const RED := Color("AA0000")
const YELLOW := Color("FFFF55")
const BROWN := Color("AA5500")
const BLACK := Color("000000")
const MAGENTA := Color("AA00AA")

const Glyphs = preload("res://glyphs.gd")

var _font: Font

func make() -> void:
	_font = preload("res://themes.gd").font("temple")

func _r(cv: CanvasItem, cell: float, x: float, y: float, w: float, h: float, col: Color) -> void:
	cv.draw_rect(Rect2(floorf(x) * cell, floorf(y) * cell, ceilf(w) * cell, ceilf(h) * cell), col)

func _width(s: String, rows: float) -> float:
	if _font == null:
		return 0.0
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(rows * 10.0)).x / 10.0  # in cells

func _text(cv: CanvasItem, cell: float, x: float, y: float, s: String, col: Color, rows := 5.0) -> float:
	if _font == null:
		return 0.0
	var size := int(rows * cell)
	cv.draw_string(_font, Vector2(x * cell, y * cell + size * 0.8), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / cell

# A window: a white page in a double blue frame with a blue title bar that carries a [X] at its right end.
func _window(cv: CanvasItem, cell: float, x: float, y: float, w: float, h: float, title: String, fill: Color) -> void:
	_r(cv, cell, x, y, w, h, BLUE)
	_r(cv, cell, x + 1, y + 4, w - 2, h - 5, fill)
	_r(cv, cell, x + 1, y + 4, w - 2, 1, BLUE)
	_text(cv, cell, x + 2, y + 0.0, title, WHITE, 4.0)
	_r(cv, cell, x + w - 7, y + 0.5, 5, 3, WHITE)
	_text(cv, cell, x + w - 6, y - 0.2, "X", BLUE, 4.0)

func _cross(cv: CanvasItem, cell: float, cx: float, cy: float, scale: float, t: float) -> void:
	# Two boxes make the cross: a tall beam and a crossbar. Turn them about the vertical axis and draw the faces that
	# face us, far to near, in yellow (lit) or brown (shaded).
	var ca := cos(t * 0.7)
	var sa := sin(t * 0.7)
	var tilt := 0.18
	var ct := cos(tilt)
	var st := sin(tilt)
	var faces: Array = []
	for box in [[Vector3(0, 0, 0), Vector3(0.16, 1.0, 0.16)], [Vector3(0, -0.33, 0), Vector3(0.58, 0.16, 0.16)]]:
		var c: Vector3 = box[0]
		var e: Vector3 = box[1]
		var v: Array = []
		for i in 8:
			var p := c + Vector3(e.x * (1 if i & 1 else -1), e.y * (1 if i & 2 else -1), e.z * (1 if i & 4 else -1))
			var x := p.x * ca + p.z * sa
			var z := -p.x * sa + p.z * ca
			var y := p.y * ct - z * st
			z = p.y * st + z * ct
			v.append(Vector3(x, y, z))
		for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6]]:
			var a: Vector3 = v[f[0]]
			var b: Vector3 = v[f[1]]
			var d: Vector3 = v[f[3]]
			var n := (b - a).cross(d - a)
			if n.z >= 0.0:
				continue  # faces away from us
			var depth := 0.0
			var pts := PackedVector2Array()
			for k in 4:
				var q: Vector3 = v[f[k]]
				depth += q.z
				pts.append(Vector2(floorf((cx + q.x * scale) ), floorf((cy + q.y * scale))) * cell)
			var lit := absf(n.normalized().dot(Vector3(-0.4, -0.5, -0.75).normalized()))
			faces.append([depth, pts, YELLOW if lit > 0.55 else BROWN])
	faces.sort_custom(func(p, q): return p[0] > q[0])
	for f in faces:
		cv.draw_colored_polygon(f[1], f[2])
		var pl: PackedVector2Array = f[1]
		pl.append(pl[0])
		cv.draw_polyline(pl, BLACK, maxf(cell * 0.5, 1.0))

func draw(cv: CanvasItem, sz: Vector2, t: float, plain := false) -> void:
	var cell := maxf(floorf(sz.y / 240.0), 3.0)
	var gw := int(ceilf(sz.x / cell)) + 1
	var gh := int(ceilf(sz.y / cell)) + 1
	_r(cv, cell, 0, 0, gw, gh, WHITE)
	# The status bar along the top: time, a frame counter, like a very old dashboard.
	_r(cv, cell, 0, 0, gw, 7, BLUE)
	var d := Time.get_datetime_dict_from_system()
	var days := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var stamp := "%s %02d/%02d %02d:%02d:%02d" % [days[int(d["weekday"])], int(d["month"]), int(d["day"]), int(d["hour"]), int(d["minute"]), int(d["second"])]
	_text(cv, cell, gw - 70, 0.5, "Tephra  %s  FPS:%d" % [stamp, int(Engine.get_frames_per_second())], WHITE, 5.0)
	# The big double frame round the whole screen.
	_r(cv, cell, 0, 7, gw, 2, BLUE)
	_r(cv, cell, 0, gh - 2, gw, 2, BLUE)
	_r(cv, cell, 0, 7, 2, gh, BLUE)
	_r(cv, cell, gw - 2, 7, 2, gh, BLUE)
	_r(cv, cell, 3, 10, gw - 6, 1, BLUE)
	_r(cv, cell, 3, gh - 4, gw - 6, 1, BLUE)
	_r(cv, cell, 3, 10, 1, gh - 14, BLUE)
	_r(cv, cell, gw - 4, 10, 1, gh - 14, BLUE)
	if plain:
		return  # a full page (Library, Settings...) is drawn on top: only the frame stays, so nothing overlaps
	# Row of three windows under the top bar: controls (left), a tip (middle), the picture window (right).
	var wy := 40.0
	var wh := gh * 0.24
	var hx := 7.0
	var hw := gw * 0.37
	_window(cv, cell, hx, wy, hw, wh, "Controls", WHITE)
	var ver := FileAccess.get_file_as_string("res://VERSION").strip_edges()
	var acc := Glyphs.btn("accept")
	var nor := Glyphs.btn("north")
	var rows := [
		["D-pad", "choose"],
		[acc, "play or open"],
		[nor, "options"],
		["PS", "control center"],
		["Hold PS", "back to Home"],
	]
	for i in rows.size():
		var ry := wy + 6.0 + float(i) * 8.0
		_text(cv, cell, hx + 3, ry, str(rows[i][0]), RED, 6.0)
		_text(cv, cell, hx + 30, ry, str(rows[i][1]), BLACK, 6.0)
	_text(cv, cell, hx + hw - 30.0, wy + wh - 8.0, "Tephra " + ver, Color("555555"), 4.5)
	var mx := gw * 0.42
	var mw := gw * 0.21
	_window(cv, cell, mx, wy, mw, wh, "Tip", WHITE)
	var tips := [
		"Hold PS to come back to Home from anywhere.",
		"PS opens the control center: Wi-Fi, volume, downloads and more.",
		"Press %s on a game to see its options." % nor,
		"Down on a game shows its details and trophies.",
		"Each game's page has a Mods button for mod games.",
		"The Browser card opens the web, with an ad blocker.",
		"Click the touchpad to take a screenshot. Hold it to record.",
		"Themes live in the Themes card in the control center.",
	]
	var tip: String = tips[int(t / 8.0) % tips.size()]
	var line := ""
	var ty := wy + 7.0
	var max_w := mw - 6.0
	for word in tip.split(" "):
		var trial := word if line == "" else line + " " + word
		if _width(trial, 6.0) > max_w and line != "":
			_text(cv, cell, mx + 3, ty, line, BLUE, 6.0)
			ty += 8.0
			line = word
		else:
			line = trial
	if line != "":
		_text(cv, cell, mx + 3, ty, line, BLUE, 6.0)
	var px := gw * 0.65
	var pw := gw * 0.30
	_window(cv, cell, px, wy, pw, wh, "Cross.pic", CYAN)
	_cross(cv, cell, px + pw / 2.0, wy + 4.0 + (wh - 4.0) / 2.0, minf(pw, wh) * 0.38, t)
	# The games window: the row of covers sits inside it.
	var gy := gh * 0.45  # high enough that the "Home" name drawn over the row sits inside the window, under its title bar
	var gh2 := gh * 0.41
	_window(cv, cell, 7.0, gy, gw - 14.0, gh2, "C:/Home/Games.DD", WHITE)
