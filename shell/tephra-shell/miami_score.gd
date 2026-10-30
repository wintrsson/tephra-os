extends CanvasLayer
## Miami theme: the score screen after a game, before Home comes back. A pixel sunset over the sea, a list of
## (made up, always flattering) stats counting up, the real play time, and an A+ stamped on at the end.
## All original drawing; it only borrows the feeling of a retro arcade's level-end screen.
##
## Use: var s := MiamiScore.new(); add_child(s); await s.run(minutes, sfx)

signal done

const Themes = preload("res://themes.gd")
const Motion = preload("res://motion.gd")

const PIX := 3.0                    # drawn this many times smaller, then blown up with no smoothing: chunky pixels
const CYAN := Color("3FF5E6")
const PINK := Color("FF2E88")
const INK := Color("2A0838")
const SUN_TOP := Color("FFD23A")
const SUN_LOW := Color("FF3A2E")
const STATS := ["FOCUS", "COMBO", "STYLE", "NERVE", "TIME BONUS", "LOYALTY", "SPECIAL"]

var _vp: SubViewport
var _c: Control
var _view: TextureRect
var _font: Font
var _rows: Array = []     # [label, value]
var _shown := 0.0         # rows shown so far (fractional while one counts up)
var _grade := 0.0         # 0..1, the A+ stamp landing
var _t := 0.0
var _minutes := 0.0
var _total := 0
var _target := 0
var _skip := false
var _sfx

func _ready() -> void:
	layer = 95  # above the black launch screen
	_font = Themes.font("neon")
	_vp = SubViewport.new()
	_vp.disable_3d = true
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_c = Control.new()
	_c.draw.connect(_draw_all)
	_vp.add_child(_c)
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.modulate.a = 0.0
	add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fit()
	get_viewport().size_changed.connect(_fit)

func _fit() -> void:
	var sz := _view.get_viewport_rect().size
	_vp.size = Vector2i((sz / PIX).ceil())
	_c.size = Vector2(_vp.size)

## Shows the screen, counts the stats up, stamps the A+, waits a moment (or a button), then fades out.
func run(minutes: float, sfx) -> void:
	_minutes = minutes
	_sfx = sfx
	_total = 0
	for s in STATS:
		var v := (randi_range(8, 160) * 100) if s != "TIME BONUS" else int(clampf(minutes, 1.0, 600.0) * 37.0) * 10
		_rows.append([s, v])
		_total += v
	_target = int(_total * randf_range(0.35, 0.55) / 1000.0) * 1000
	var tw := create_tween()
	tw.tween_property(_view, "modulate:a", 1.0, Motion.dur(0.5))
	await tw.finished
	for i in _rows.size():
		if _skip:
			break
		_play("tick")
		var k := create_tween()
		k.tween_property(self, "_shown", float(i + 1), 0.22 if Motion.on() else 0.0)
		await k.finished
	_shown = _rows.size()
	if not _skip:
		await get_tree().create_timer(0.35).timeout
	_play("confirm")
	var g := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	g.tween_property(self, "_grade", 1.0, 0.35 if Motion.on() else 0.0)
	await g.finished
	_skip = false
	var wait := 0.0
	while wait < 3.5 and not _skip:
		await get_tree().process_frame
		wait += get_process_delta_time()
	var out := create_tween()
	out.tween_property(_view, "modulate:a", 0.0, Motion.dur(0.5))
	await out.finished
	done.emit()
	queue_free()

func _play(sound: String) -> void:
	if _sfx != null:
		_sfx.play(sound)

# Cross or Circle hurries it along; nothing else reaches Home underneath while it shows.
func _input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo():
		if event is InputEventJoypadButton or event is InputEventKey:
			_skip = true
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if Motion.on():
		_t += delta
	_c.queue_redraw()

# ---------- Drawing (in the small, pixel-sized space) ----------
func _draw_all() -> void:
	var sz := _c.size
	var hz := sz.y * 0.52  # the horizon
	# Sky: black at the top, burning red down at the horizon.
	var bands := 24
	for i in bands:
		var k := float(i) / bands
		_c.draw_rect(Rect2(0, hz * k, sz.x, hz / bands + 1), Color(0.02, 0.0, 0.02).lerp(Color("B0101E"), k * k))
	# The sun, with slits cut across its lower half.
	var sc := Vector2(sz.x * 0.5, hz - 4)
	var r := sz.y * 0.22
	for y in range(int(-r), 1):
		var w := sqrt(maxf(r * r - y * y, 0.0))
		var k := float(y + r) / r
		if y > -r * 0.45 and posmod(y + int(_t * 6.0), 7) < 2:
			continue
		_c.draw_rect(Rect2(sc.x - w, sc.y + y, w * 2.0, 1), SUN_TOP.lerp(SUN_LOW, k))
	# Palms along the horizon.
	for i in 14:
		var px := fposmod(i * 53.0 + 17.0, sz.x)
		var ph := 10.0 + float((i * 7) % 9)
		var pc := Color("3A0610")
		_c.draw_rect(Rect2(px, hz - ph, 1, ph), pc)
		for f in [-1.0, 1.0]:
			_c.draw_line(Vector2(px, hz - ph), Vector2(px + f * 5.0, hz - ph + 3.0), pc, 1.0)
			_c.draw_line(Vector2(px, hz - ph), Vector2(px + f * 3.0, hz - ph - 1.0), pc, 1.0)
	# The sea: dark, with the sun's broken reflection rippling in it.
	_c.draw_rect(Rect2(0, hz, sz.x, sz.y - hz), Color("1A0408"))
	for y in range(0, int(sz.y - hz), 2):
		var k := float(y) / (sz.y - hz)
		var w := r * (1.0 - k * 0.6) * (0.8 + 0.2 * sin(_t * 3.0 + y * 0.7))
		var off := 3.0 * sin(_t * 2.0 + y * 0.4)
		_c.draw_rect(Rect2(sc.x - w + off, hz + y, w * 2.0, 1), Color(SUN_LOW, 0.55 * (1.0 - k)))
		_c.draw_rect(Rect2(0, hz + y, sz.x, 1), Color(0.3, 0.05, 0.1, 0.08))

	if _font == null:
		return
	# The stats, left column names, right column values counting up.
	var fs := 16
	var lx := sz.x * 0.07
	var rx := sz.x * 0.93
	for i in _rows.size():
		var vis := clampf(_shown - i, 0.0, 1.0)
		if vis <= 0.0:
			break
		var y := sz.y * 0.13 + i * 19.0
		var wob := 1.5 * sin(_t * 3.0 + i)
		var name: String = _rows[i][0]
		var val := str(int(_rows[i][1] * vis))
		_shadow_text(Vector2(lx - (1.0 - vis) * 40.0, y + wob), name, fs, CYAN, vis)
		var vw := _font.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_shadow_text(Vector2(rx - vw, y - wob), val, fs, CYAN, vis)
	# Grade, score, and the real play time.
	if _grade > 0.0:
		var gy := sz.y * 0.82
		_shadow_text(Vector2(lx, gy), "GRADE", 22, CYAN, 1.0)
		var s := lerpf(3.0, 1.0, _grade)
		var gp := Vector2(lx + 120, gy - 4)
		_c.draw_set_transform(gp, -0.12 + 0.03 * sin(_t * 4.0), Vector2(s, s))
		_c.draw_string_outline(_font, Vector2.ZERO, "A+", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 4, Color(INK, _grade))
		_c.draw_string(_font, Vector2.ZERO, "A+", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(Color("E0102A"), _grade))
		_c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var score := "%d/%d" % [_total, _target]
		var sw := _font.get_string_size(score, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var tw := _font.get_string_size("LEVEL SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_shadow_text(Vector2(rx - tw, gy - 22), "LEVEL SCORE", 20, Color("FFE14A"), 1.0)
		_shadow_text(Vector2(rx - sw, gy), score, 20, Color("6CFF5A"), 1.0)
		var secs := int(_minutes * 60.0)
		var tt := "TOTAL TIME: %02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60]
		var ttw := _font.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_c.draw_string(_font, Vector2(rx - ttw, gy + 14), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("D07CFF"))

# Text with a pink copy just behind it and a dark edge, like a slightly misaligned arcade screen.
func _shadow_text(p: Vector2, txt: String, fs: int, col: Color, a: float) -> void:
	_c.draw_string(_font, p + Vector2(2, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(PINK, 0.9 * a))
	_c.draw_string_outline(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(INK, a))
	_c.draw_string(_font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))
