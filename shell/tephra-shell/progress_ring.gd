extends Control

const Themes = preload("res://themes.gd")
## A circular progress ring with big text in the middle (e.g. "14 / 24").
## `fraction` runs 0..1 and can be tweened for a fill animation.

var fraction := 0.0:
	set(v):
		fraction = v
		queue_redraw()
var big := ""
var small := ""

var TRACK: Color = Themes.ink(0.14)
var FILL: Color = Themes.c("text")

func set_text(b: String, s: String) -> void:
	big = b
	small = s
	queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 12.0
	if r <= 0.0:
		return
	draw_arc(c, r, 0.0, TAU, 96, TRACK, 14.0, true)
	if fraction > 0.001:
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * clampf(fraction, 0.0, 1.0), 96, FILL, 14.0, true)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, c.y + 2), big, HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, FILL)
	draw_string(font, Vector2(0, c.y + 30), small, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Themes.c("muted"))
