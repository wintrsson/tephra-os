extends RefCounted
## Controller vibration. Small taps when you browse, a bigger rumble when a game opens.
## Strength and on/off are in Settings > Controller. Which controller buzzes follows
## Settings > Controller > Controller priority.

const Settings = preload("res://settings.gd")
const TephraGlyphs = preload("res://glyphs.gd")

# Off, Low, Medium, High. Wide gaps on purpose: Low is a faint tick, High is a hard thump.
const LEVELS := [0.0, 0.22, 0.55, 1.0]

static func level() -> float:
	return LEVELS[clampi(int(Settings.get_value("vibration", 2)), 0, LEVELS.size() - 1)]

# Taps that arrive within a few milliseconds of each other (a menu that moves AND a screen
# that reports the move) count as one, so a single step never buzzes twice.
static var _last_tap_ms := -1000

static func _tap_ok() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms < 45:
		return false
	_last_tap_ms = now
	return bool(Settings.get_value("vib_nav", true))

## A light tap: moving between items, icons, tabs, sliders. Low / Medium / High changes how
## hard AND how long it is, so the three levels are easy to tell apart.
static func tick() -> void:
	if _tap_ok():
		pulse(1.0, 0.8, 0.03 + 0.05 * level())

## Selecting a game or scrolling through a list.
static func select() -> void:
	if _tap_ok():
		pulse(1.0, 0.9, 0.04 + 0.06 * level())

## Pressing A on something: a little firmer than moving.
static func confirm() -> void:
	if _tap_ok():
		pulse(1.0, 1.0, 0.05 + 0.07 * level())

## Opening a game: a long, heavy rumble.
static func launch() -> void:
	if bool(Settings.get_value("vib_launch", true)):
		pulse(1.0, 1.0, 0.5)

## The Vibration setting just changed: one buzz at the new strength (Low short and faint, High long and hard),
## nothing for Off. Menu taps are held back for a moment so they don't cut the buzz short.
static func preview() -> void:
	stop()
	var lv := level()
	if lv <= 0.0:
		return
	var secs := 0.12 + 0.25 * lv
	_last_tap_ms = Time.get_ticks_msec() + int(secs * 1000.0)
	pulse(1.0, 1.0, secs)

## weak = the light high-frequency motor, strong = the heavy one. Both are scaled by the
## Vibration setting.
static func pulse(weak: float, strong: float, seconds: float) -> void:
	var lv := level()
	if lv <= 0.0:
		return
	var dev := TephraGlyphs.primary_device()
	if dev < 0:
		return
	Input.start_joy_vibration(dev, clampf(weak * lv, 0.0, 1.0), clampf(strong * lv, 0.0, 1.0), seconds)

## Used by the controller test: ignores the Vibration setting so you can feel every level.
static func raw(weak: float, strong: float, seconds: float) -> void:
	var dev := TephraGlyphs.primary_device()
	if dev >= 0:
		Input.start_joy_vibration(dev, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), seconds)

static func stop() -> void:
	var dev := TephraGlyphs.primary_device()
	if dev >= 0:
		Input.stop_joy_vibration(dev)
