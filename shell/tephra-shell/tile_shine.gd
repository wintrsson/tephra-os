extends Control
## Drawn over a game tile when it's selected: a soft white outline with a glow
## (no moving highlight).

const Settings = preload("res://settings.gd")
const Visuals = preload("res://visuals.gd")
const RADIUS := 16.0
const POINTS := 120

var active := false
var _strength := 0.0
var _t := 0.0
var _pts := PackedVector2Array()
var _pts_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	var on := active and bool(Settings.get_value("tile_shine", true)) and not Visuals.saver()
	var before := _strength
	_strength = move_toward(_strength, 1.0 if on else 0.0, delta * (4.0 if Settings.get_value("animations", true) else 1000.0))
	if _strength != before:  # the outline is still once it has faded in, so only redraw while it changes
		queue_redraw()

# Evenly spaced points around a rounded rectangle, clockwise from the top-left corner.
func _perimeter(r: Rect2, rad: float) -> PackedVector2Array:
	var dense := PackedVector2Array()
	var steps := 8
	var corners := [
		[Vector2(r.position.x + r.size.x - rad, r.position.y + rad), -PI / 2.0],
		[Vector2(r.position.x + r.size.x - rad, r.position.y + r.size.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.position.y + r.size.y - rad), PI / 2.0],
		[Vector2(r.position.x + rad, r.position.y + rad), PI]]
	for c in corners:
		for i in steps + 1:
			var a: float = c[1] + (PI / 2.0) * i / steps
			dense.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	dense.append(dense[0])
	var lens := [0.0]
	for i in range(1, dense.size()):
		lens.append(lens[i - 1] + dense[i].distance_to(dense[i - 1]))
	var total: float = lens[lens.size() - 1]
	var out := PackedVector2Array()
	var seg := 1
	for k in POINTS:
		var target := total * k / POINTS
		while seg < lens.size() - 1 and lens[seg] < target:
			seg += 1
		var span: float = maxf(lens[seg] - lens[seg - 1], 0.0001)
		out.append(dense[seg - 1].lerp(dense[seg], clampf((target - lens[seg - 1]) / span, 0.0, 1.0)))
	return out

func _draw() -> void:
	if _strength <= 0.01:
		return
	if _pts_size != size:
		_pts = _perimeter(Rect2(Vector2(3, 3), size - Vector2(6, 6)), maxf(float(preload("res://themes.gd").r(RADIUS)) - 2.0, 0.5))
		_pts_size = size
	var loop := _pts.duplicate()
	loop.append(_pts[0])
	# Soft outline: a wide faint glow and a thin brighter line.
	draw_polyline(loop, Color(1, 1, 1, 0.10 * _strength), 10.0, true)
	draw_polyline(loop, Color(1, 1, 1, 0.55 * _strength), 3.0, true)
