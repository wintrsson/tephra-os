extends Control
## A small frame-time graph (like RivaTuner's): one point per frame, newest on the right.
## Green = on budget, orange = a bit slow, red = a stutter. The grey line is the budget
## (the display's refresh time).

const SAMPLES := 120

var _ms: PackedFloat32Array = PackedFloat32Array()
var budget_ms := 16.7

func _init() -> void:
	custom_minimum_size = Vector2(200, 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ms.resize(SAMPLES)

func push(ms: float) -> void:
	_ms.remove_at(0)
	_ms.append(ms)
	queue_redraw()

func _draw() -> void:
	var top := maxf(budget_ms * 2.4, 12.0)  # the top of the graph
	var w := size.x
	var h := size.y
	var by := h - h * clampf(budget_ms / top, 0.0, 1.0)
	draw_line(Vector2(0, by), Vector2(w, by), Color(1, 1, 1, 0.22), 1.0)
	var prev := Vector2.ZERO
	for i in SAMPLES:
		var v := float(_ms[i])
		var p := Vector2(w * float(i) / float(SAMPLES - 1), h - h * clampf(v / top, 0.0, 1.0))
		if i > 0 and v > 0.0:
			var col := Color("46D17B") if v <= budget_ms * 1.25 else (Color("FF9A1F") if v <= budget_ms * 2.0 else Color("FF4B3A"))
			draw_line(prev, p, col, 2.0, true)
		prev = p
