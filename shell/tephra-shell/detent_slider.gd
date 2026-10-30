extends Control

const Themes = preload("res://themes.gd")
## A slider with evenly spaced stops: -o-o-o-o-. Each dot is one value, in order, all the same
## distance apart (not to scale). Dimmed dots can't be picked. Used by Settings.

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")

var labels: Array = []   # text under each stop ("" for none)
var usable: Array = []   # per stop: false = dimmed and skipped
var index := 0
var focused := false
var glide := 22.0  # how fast the handle catches up (higher = quicker)
var _shown := -1.0  # where the handle is drawn right now; it glides to `index`

func _init() -> void:
	custom_minimum_size = Vector2(560, 60)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_state(new_labels: Array, new_usable: Array, new_index: int, is_focused: bool) -> void:
	labels = new_labels
	usable = new_usable
	index = clampi(new_index, 0, maxi(labels.size() - 1, 0))
	focused = is_focused
	if _shown < 0.0:
		_shown = float(index)  # first time: start in place instead of sliding in from the left
	queue_redraw()

func _process(delta: float) -> void:
	if _shown < 0.0 or is_equal_approx(_shown, float(index)):
		return
	# Ease towards the target (about 60 ms to cover most of the distance), so a step glides
	# instead of jumping. It stops redrawing once it arrives.
	_shown = lerpf(_shown, float(index), 1.0 - exp(-delta * glide))
	if absf(_shown - float(index)) < 0.005:
		_shown = float(index)
	queue_redraw()

func _x(i: float) -> float:
	var n := labels.size()
	var pad := 22.0
	return pad + (size.x - pad * 2.0) * (float(i) / float(n - 1) if n > 1 else 0.0)

func _draw() -> void:
	var n := labels.size()
	if n == 0:
		return
	var y := 20.0
	var dots := n <= 10
	draw_line(Vector2(_x(0), y), Vector2(_x(n - 1), y), Themes.ink(0.2), 4.0, true)
	var pos := _shown if _shown >= 0.0 else float(index)
	draw_line(Vector2(_x(0), y), Vector2(_x(pos), y), TEXT if focused else Themes.ink(0.6), 4.0, true)
	if dots:
		for i in n:
			var ok: bool = i >= usable.size() or bool(usable[i])
			var passed := float(i) <= pos + 0.01
			var col := (TEXT if passed else Themes.ink(0.45)) if ok else Themes.ink(0.14)
			_disc(Vector2(_x(i), y), 6.5 if ok else 4.5, col)
	# The handle: a dark ring around a light disc, both anti-aliased (smooth edges, no pixel steps).
	var hx := _x(pos)
	_disc(Vector2(hx, y), 13.5 if focused else 10.5, Themes.c("panel"))
	_disc(Vector2(hx, y), 10.5 if focused else 8.0, TEXT)
	# Labels under the stops (all of them when it's a short list, else the ends only)
	var font := ThemeDB.fallback_font
	for i in n:
		var t := str(labels[i])
		if t == "" or (not dots and i != 0 and i != n - 1):
			continue
		var ok2: bool = i >= usable.size() or bool(usable[i])
		var col2 := (TEXT if i == index else MUTED) if ok2 else Themes.ink(0.22)
		draw_string(font, Vector2(_x(i) - 40.0, y + 34.0), t, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 17, col2)

## A filled circle with smooth edges. (draw_circle alone is not anti-aliased, which is what made the
## handle look pixelated.)
func _disc(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r, col, true, -1.0, true)
	draw_arc(c, r - 0.5, 0.0, TAU, 48, col, 1.2, true)  # a thin anti-aliased rim finishes the edge
