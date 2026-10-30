extends Control
## Drawn over a game tile on Home while Steam is downloading it (or an update for it). The cover fills up with colour
## from the bottom as the download goes (the part still to come is dimmed), a bright line marks how far it has got,
## the tile's border fills up clockwise from the top, and the percentage sits in the middle. "Paused" or "Queued"
## shows under it when it isn't moving.

const Themes = preload("res://themes.gd")

var pct := 0.0          # 0..1, what Steam says
var state := "Downloading"
var _shown := 0.0       # what is drawn: follows pct smoothly
var _t := 0.0
var _font: Font
var radius := 16.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Themes.font()
	if _font == null:
		_font = ThemeDB.fallback_font
	_shown = pct

func _process(delta: float) -> void:
	_t += delta
	_shown = move_toward(_shown, pct, delta * maxf(0.05, absf(pct - _shown) * 2.0))
	queue_redraw()

## The tile's outline as one path, starting at the top middle and going clockwise.
func _outline(r: float, inset: float) -> PackedVector2Array:
	var w := size.x - inset * 2.0
	var h := size.y - inset * 2.0
	var o := Vector2(inset, inset)
	r = minf(r, minf(w, h) * 0.5)
	var pts := PackedVector2Array([o + Vector2(w * 0.5, 0)])
	var corners := [[Vector2(w - r, r), -PI * 0.5], [Vector2(w - r, h - r), 0.0], [Vector2(r, h - r), PI * 0.5], [Vector2(r, r), PI]]
	for c in corners:
		for k in 9:
			var a: float = float(c[1]) + PI * 0.5 * k / 8.0
			pts.append(o + (c[0] as Vector2) + Vector2(cos(a), sin(a)) * r)
	pts.append(o + Vector2(w * 0.5, 0))
	return pts

func _draw() -> void:
	var sel: Color = Themes.c("select")
	var p := clampf(_shown, 0.0, 1.0)
	var fill_y := size.y * (1.0 - p)
	# the part still to download is dimmed and drained of colour
	draw_rect(Rect2(0, 0, size.x, fill_y), Color(0.0, 0.0, 0.0, 0.62))
	draw_rect(Rect2(0, fill_y, size.x, size.y - fill_y), Color(0.0, 0.0, 0.0, 0.12))
	# the filling line, with a soft shimmer running along it while it moves
	if p > 0.0 and p < 1.0:
		var moving := state == "Downloading"
		draw_line(Vector2(0, fill_y), Vector2(size.x, fill_y), Color(sel, 0.85 if moving else 0.4), 2.0)
		if moving:
			var sx := fposmod(_t * 160.0, size.x + 80.0) - 40.0
			draw_line(Vector2(maxf(sx - 40.0, 0.0), fill_y), Vector2(minf(sx + 40.0, size.x), fill_y), Color(1, 1, 1, 0.9), 3.0)
	# the border filling clockwise from the top
	var path := _outline(radius, 2.5)
	draw_polyline(path, Color(sel, 0.18), 5.0, true)
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	var want := total * p
	var done := PackedVector2Array([path[0]])
	var acc := 0.0
	for i in range(1, path.size()):
		var seg := path[i].distance_to(path[i - 1])
		if acc + seg >= want:
			done.append(path[i - 1].lerp(path[i], (want - acc) / maxf(seg, 0.001)))
			break
		done.append(path[i])
		acc += seg
	if done.size() > 1:
		draw_polyline(done, sel, 5.0, true)
		draw_circle(done[done.size() - 1], 4.5, Color(1, 1, 1, 0.9))
	# the number in the middle, and what Steam is doing if it isn't downloading
	var txt := "%d%%" % int(floor(p * 100.0))
	var fs := 46
	var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var c := Vector2(size.x * 0.5, size.y * 0.4)
	draw_string_outline(_font, Vector2(c.x - tw * 0.5, c.y + fs * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, 0.6))
	draw_string(_font, Vector2(c.x - tw * 0.5, c.y + fs * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))
	var sub := "Installing" if state == "Downloading" else state
	var ss := 20
	var sw := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
	draw_string_outline(_font, Vector2(c.x - sw * 0.5, c.y + fs * 0.32 + 34.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, 6, Color(0, 0, 0, 0.6))
	draw_string(_font, Vector2(c.x - sw * 0.5, c.y + fs * 0.32 + 34.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(1, 1, 1, 0.85))
