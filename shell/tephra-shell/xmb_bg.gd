extends Control
## The Wave theme's backdrop (blue silk ribbons and twinkles) as a stand-alone control,
## so other screens such as the profile can sit on the same background as the Wave Home.

const Settings = preload("res://settings.gd")

var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	var W := size.x
	var H := size.y
	var pal: Array = preload("res://xmb.gd").COLORS.get(str(Settings.get_value("xmb_color", "Blue")), preload("res://xmb.gd").COLORS["Blue"])
	var top: Color = pal[0]
	var bot: Color = pal[1]
	var rib: Color = pal[2]
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([top, top, bot, bot]))
	var n := 56
	for b in 4:
		var up := PackedVector2Array()
		var dn := PackedVector2Array()
		var ph := _t * (0.22 + 0.07 * b) + b * 1.7
		var base := H * (0.50 + 0.05 * b)
		for i in n + 1:
			var x := W * float(i) / n
			var u := float(i) / n
			var y := base + sin(u * 4.2 + ph) * H * 0.07 + sin(u * 9.0 - ph * 1.3) * H * 0.015
			var th := (16.0 + 46.0 * sin(u * 3.0 + b)) * (0.6 + 0.4 * sin(ph + u * 2.0)) + 30.0
			up.append(Vector2(x, y - th))
			dn.append(Vector2(x, y + th * 0.6))
		var poly := up.duplicate()
		for i in range(dn.size() - 1, -1, -1):
			poly.append(dn[i])
		draw_colored_polygon(poly, Color(rib.r, rib.g, rib.b, 0.07 + 0.02 * b))
		draw_polyline(up, Color(rib.r, rib.g, rib.b, 0.38 - 0.06 * b), 2.0, true)
		draw_polyline(dn, Color(rib.r, rib.g, rib.b, 0.16), 1.5, true)
	for i in 70:
		var h1 := fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var h2 := fposmod(sin(float(i) * 78.233) * 12543.123, 1.0)
		var tw := 0.5 + 0.5 * sin(_t * (0.6 + h1) + h2 * 6.28)
		draw_circle(Vector2(h1 * W, h2 * H), 1.2 + h2 * 1.4, Color(1, 1, 1, 0.10 + 0.35 * tw * h2))
