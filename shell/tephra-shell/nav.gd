extends Node
## One place that turns D-pad, left stick and arrow keys into the same "steps".
## A press gives one step. Keep holding and it repeats, a bit faster the longer
## you hold. Every screen listens to the `step` signal, so the D-pad, the stick
## and the keyboard always feel identical.
##
## The right stick gives `fast_step`: bigger jumps (3 at a time) for scrolling
## quickly through long lists.

signal step(dir: Vector2i)       # dir: x = -1/1 (left/right), y = -1/1 (up/down)
signal fast_step(dir: Vector2i, amount: int)

const FIRST_DELAY := 0.4   # seconds before a held direction starts repeating
const REPEAT := 0.14       # seconds between repeats
const REPEAT_FAST := 0.08  # repeat speed after holding for a while
const SPEEDUP_AFTER := 1.2 # seconds of holding before it speeds up
const FAST_AMOUNT := 3     # items per right-stick step
const FAST_REPEAT := 0.1
const FAST_THRESHOLD := 0.6

var enabled := true  # home.gd turns this off while a game is running

var _dir := Vector2i.ZERO
var repeating := false  # true while the step being sent is a repeat of a held direction (not a fresh press)
var _timer := 0.0
var _held := 0.0
var _tap := Vector2i.ZERO  # a press that started and ended between two frames

var _fast_dir := Vector2i.ZERO
var _fast_timer := 0.0

# Catches quick taps: a press and release that both land between two frames
# would never be seen by polling, so remember the press.
func _input(event: InputEvent) -> void:
	if not enabled or event.is_echo() or not event.is_pressed() or event is InputEventJoypadMotion:
		return
	if event.is_action("ui_right"):
		_tap = Vector2i(1, 0)
	elif event.is_action("ui_left"):
		_tap = Vector2i(-1, 0)
	elif event.is_action("ui_down"):
		_tap = Vector2i(0, 1)
	elif event.is_action("ui_up"):
		_tap = Vector2i(0, -1)

func _process(delta: float) -> void:
	if not enabled:
		_dir = Vector2i.ZERO
		_tap = Vector2i.ZERO
		_fast_dir = Vector2i.ZERO
		return
	_process_main(delta)
	_process_fast(delta)

func _process_main(delta: float) -> void:
	var d := _read_main()
	var tap := _tap
	_tap = Vector2i.ZERO
	if d == Vector2i.ZERO:
		_dir = Vector2i.ZERO
		if tap != Vector2i.ZERO:
			repeating = false
			step.emit(tap)  # a very quick tap
		return
	if d != _dir:
		_dir = d
		_timer = FIRST_DELAY
		_held = 0.0
		repeating = false
		step.emit(d)
		return
	_held += delta
	_timer -= delta
	if _timer <= 0.0:
		_timer = REPEAT_FAST if _held > SPEEDUP_AFTER else REPEAT
		repeating = true
		step.emit(d)

# D-pad, arrow keys and the left stick all count.
# The stick is read by hand with two thresholds (hysteresis): it must pass 0.55
# to start moving but only counts as released below 0.35. Near the edge it can
# no longer flicker on and off (which caused skipped tiles), and a stick that
# rests a little off-centre still counts as released (which caused "keeps moving").
const STICK_ON := 0.55
const STICK_OFF := 0.35

func _read_main() -> Vector2i:
	var x := 0.0
	var y := 0.0
	var px := false
	var py := false
	# Keyboard arrows.
	if Input.is_key_pressed(KEY_RIGHT): x += 1.0
	if Input.is_key_pressed(KEY_LEFT): x -= 1.0
	if Input.is_key_pressed(KEY_DOWN): y += 1.0
	if Input.is_key_pressed(KEY_UP): y -= 1.0
	for pad in Input.get_connected_joypads():
		# D-pad buttons.
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT): x += 1.0
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT): x -= 1.0
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN): y += 1.0
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP): y -= 1.0
		# Left stick, with hysteresis based on what was held last frame.
		var ax := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
		var ay := Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y)
		var tx := STICK_OFF if _dir.x != 0 else STICK_ON
		var ty := STICK_OFF if _dir.y != 0 else STICK_ON
		if absf(ax) > tx:
			x += signf(ax) * (1.0 + absf(ax))  # stick counts a little stronger than a button
		if absf(ay) > ty:
			y += signf(ay) * (1.0 + absf(ay))
	px = absf(x) > 0.01
	py = absf(y) > 0.01
	if not px and not py:
		return Vector2i.ZERO
	# Diagonal: keep the direction we were already moving in if it's still held,
	# otherwise the stronger one.
	if px and py:
		if _dir.x != 0 and signf(x) == float(_dir.x):
			return Vector2i(int(signf(x)), 0)
		if _dir.y != 0 and signf(y) == float(_dir.y):
			return Vector2i(0, int(signf(y)))
	if px and (not py or absf(x) >= absf(y)):
		return Vector2i(int(signf(x)), 0)
	return Vector2i(0, int(signf(y)))

func _process_fast(delta: float) -> void:
	var v := Vector2.ZERO
	for pad in Input.get_connected_joypads():
		var ax := Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X)
		var ay := Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y)
		if absf(ax) > absf(v.x):
			v.x = ax
		if absf(ay) > absf(v.y):
			v.y = ay
	var d := Vector2i.ZERO
	var threshold := FAST_THRESHOLD if _fast_dir == Vector2i.ZERO else FAST_THRESHOLD * 0.5
	if absf(v.y) >= absf(v.x) and absf(v.y) > threshold:
		d = Vector2i(0, int(signf(v.y)))
	elif absf(v.x) > threshold:
		d = Vector2i(int(signf(v.x)), 0)
	if d == Vector2i.ZERO:
		_fast_dir = Vector2i.ZERO
		return
	if d != _fast_dir:
		_fast_dir = d
		_fast_timer = FIRST_DELAY
		fast_step.emit(d, FAST_AMOUNT)
		return
	_fast_timer -= delta
	if _fast_timer <= 0.0:
		_fast_timer = FAST_REPEAT
		fast_step.emit(d, FAST_AMOUNT)
