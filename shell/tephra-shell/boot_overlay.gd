extends CanvasLayer
## Tephra boot overlay: matches the Plymouth splash (navy gradient + shard),
## fades logo and navy to black together, then fades black into the home screen.
## The Tephra theme keeps exactly that. Every other theme has its own colours and moving picture
## behind the logo (see intro_art.gd), chosen by LOOKS below.

signal finished  # emitted once the intro has fully faded out

const TOP_COLOR := Color(0.043, 0.071, 0.125)     # same as tephra.script
const BOTTOM_COLOR := Color(0.027, 0.043, 0.071)  # same as tephra.script
const DisplayCtl = preload("res://display_ctl.gd")
const Themes = preload("res://themes.gd")
const IntroArt = preload("res://intro_art.gd")
const LOGO := preload("res://assets/shard_logo.png")
# theme: [top colour, bottom colour, logo colour, moving picture]
const LOOKS := {
	"volcanic": [Color(0.03, 0.02, 0.02), Color(0.30, 0.08, 0.02), Color(1.0, 0.66, 0.40), "embers"],
	"sleek": [Color(0.94, 0.95, 0.97), Color(0.63, 0.67, 0.73), Color(0.13, 0.16, 0.22), "glass"],
	"channels": [Color(0.97, 0.985, 1.0), Color(0.78, 0.89, 0.98), Color(0.20, 0.62, 0.92), "tiles"],
	"ps2": [Color(0.0, 0.0, 0.02), Color(0.0, 0.025, 0.09), Color(0.65, 0.88, 1.0), "ps2"],
	"gunmetal": [Color(0.012, 0.012, 0.014), Color(0.115, 0.12, 0.13), Color(0.80, 0.83, 0.87), "rain"],
	"neon": [Color(0.23, 0.04, 0.27), Color(0.82, 0.10, 0.48), Color(0.25, 0.96, 0.90), "palms"],
	"gothic": [Color(0.015, 0.015, 0.02), Color(0.20, 0.20, 0.22), Color(0.96, 0.96, 0.98), "castle"],
	"mold": [Color(0.02, 0.018, 0.015), Color(0.09, 0.08, 0.066), Color(0.88, 0.84, 0.76), "basement"],
	"nature": [Color(0.42, 0.68, 0.94), Color(0.8, 0.93, 1.0), Color(0.12, 0.3, 0.1), "forest"],
	"temple": [Color(1, 1, 1), Color(1, 1, 1), Color(0.0, 0.0, 0.67), "temple"],
	"pcb": [Color(0.02, 0.14, 0.08), Color(0.06, 0.3, 0.18), Color(0.95, 0.8, 0.35), "pcb"],
	"planet": [Color(0.01, 0.012, 0.05), Color(0.07, 0.04, 0.17), Color(0.6, 0.8, 1.0), "cosmos"],
	"castle": [Color(0.05, 0.08, 0.2), Color(0.1, 0.16, 0.34), Color(0.96, 0.9, 0.7), "kingdom"],
	"wave": [Color(0.02, 0.06, 0.22), Color(0.04, 0.30, 0.78), Color(0.85, 0.94, 1.0), "silk"],
	"frutiger": [Color(0.28, 0.60, 0.95), Color(0.66, 0.90, 0.72), Color(1.0, 1.0, 1.0), "bubbles"],
}
const HOLD_TIME := 4.0   # seconds the logo stays fully visible
const TO_BLACK := 0.6    # seconds for logo + navy to fade to black
const TO_HOME := 0.6     # seconds for black to fade into the home screen
var hold := HOLD_TIME    # how long the intro holds; home.gd reads it

func _ready() -> void:
	layer = 100  # draw on top of everything else
	# Before anything is shown: open on the right screen (an external monitor if one is plugged in,
	# otherwise the laptop's own screen) and fill it, instead of starting small in a corner.
	DisplayCtl.place_best()

	# Bottom layer: plain black, revealed when the splash fades.
	var black := ColorRect.new()
	black.color = Color.BLACK
	_fill(black)
	add_child(black)

	# Splash group: navy gradient + logo, faded together.
	var splash := Control.new()
	_fill(splash)
	add_child(splash)

	var look: Array = LOOKS.get(Themes.id(), [])
	var gradient := Gradient.new()
	gradient.set_color(0, look[0] if not look.is_empty() else TOP_COLOR)
	gradient.set_color(1, look[1] if not look.is_empty() else BOTTOM_COLOR)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.height = 512
	tex.fill_from = Vector2(0, 0)  # top
	tex.fill_to = Vector2(0, 1)    # bottom
	var bg := TextureRect.new()
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	_fill(bg)
	splash.add_child(bg)

	hold = HOLD_TIME
	if not look.is_empty():
		var art := IntroArt.new()
		art.style = look[3]
		art.rays = Themes.id() == "frutiger"
		art.words = ["Library", "Controllers", "Wi-Fi", "Settings", "Info"]
		splash.add_child(art)

	var logo := TextureRect.new()
	logo.texture = LOGO
	if not look.is_empty():
		var lc: Color = look[2]
		logo.modulate = Color(lc.r * 1.4, lc.g * 1.4, lc.b * 1.4, 1.0)  # the logo is light grey, so it needs lifting
	logo.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_fill(logo)
	splash.add_child(logo)
	# Every theme: the logo only grows (it never shrinks again), as ONE smooth curve worked out from the clock each
	# frame (no tweens handing over to each other, no overshoot), so a slow frame never makes it jump or restart.
	_logo = logo
	_t0 = Time.get_ticks_usec()
	logo.pivot_offset = get_viewport().get_visible_rect().size / 2.0
	logo.scale = Vector2.ONE * 0.9
	if Themes.id() == "ps2":
		# The pillars have the stage first; the logo arrives once they have passed.
		logo.modulate.a = 0.0
		var lt := create_tween()
		lt.tween_interval(1.7)
		lt.tween_property(logo, "modulate:a", 1.0, 0.9)

	await get_tree().create_timer(hold).timeout
	var tween := create_tween()
	tween.tween_property(splash, "modulate:a", 0.0, TO_BLACK)
	tween.tween_property(black, "modulate:a", 0.0, TO_HOME)
	await tween.finished
	finished.emit()
	queue_free()

var _logo: TextureRect
var _t0 := 0

func _process(_delta: float) -> void:
	if _logo == null:
		return
	var t := (Time.get_ticks_usec() - _t0) / 1000000.0
	# One slow growth, always getting bigger and never shrinking back: fast at first, then easing to a stop.
	var grow := 1.0 - pow(1.0 - clampf(t / 7.0, 0.0, 1.0), 2.0)
	_logo.scale = Vector2.ONE * (0.9 + 0.13 * grow)

# Makes a node cover the whole screen and ignore mouse clicks.
func _fill(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
