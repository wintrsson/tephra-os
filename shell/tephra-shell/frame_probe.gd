extends Node
## A frame-time probe, to find out WHY Tephra's frame rate is what it is. Off unless the file
## ~/.config/tephra/probe exists (create it with:  touch ~/.config/tephra/probe ).
##
## Every 2 seconds it adds one line to ~/.config/tephra/frametime.log:
##   fps          frames per second right now
##   scripts      time all of Tephra's scripts took per frame (average and worst)
##   frame        how long a whole frame really lasted (average and worst), including any waiting
##   render cpu   time spent preparing drawing commands for the graphics card
##   render gpu   time the graphics card spent drawing the frame
##   draws        how many separate drawing commands were sent
## Whichever of these is largest is what holds the frame rate back. At 120 fps every number has to
## stay under 8.3 ms, at 60 fps under 16.7 ms.

var _t := 0.0
var _vp: RID
# Script time is measured with two small helper nodes: one that runs before every other node's _process
# (very low priority number) and one that runs after all of them. The difference between their clocks is
# the time all scripts took in that frame, and nothing else (no drawing, no waiting for the screen).
var _first: Node
var _last: Node
var _t0 := 0
var _script_sum := 0.0
var _script_max := 0.0
var _frame_sum := 0.0
var _frame_max := 0.0
var _frames := 0

## Sections of code can report how long they took: FrameProbe.mark("name", start_usec). Only the slowest
## call of each 2-second window is kept, and the log shows which section it was. Costs nothing when the probe is off.
static var on := false
static var _sections := {}   # section name -> its slowest call in this 2-second window

static func mark(section: String, start_usec: int) -> void:
	if not on:
		return
	var ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	if ms > float(_sections.get(section, 0.0)):
		_sections[section] = ms

static func wanted() -> bool:
	return FileAccess.file_exists(OS.get_environment("HOME") + "/.config/tephra/probe")

func _ready() -> void:
	on = true
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)  # asks the renderer to time itself (small cost)
	_first = Node.new()
	_first.process_priority = -100000
	_first.set_script(preload("res://frame_probe_tick.gd"))
	_first.probe = self
	_first.is_first = true
	add_child(_first)
	_last = Node.new()
	_last.process_priority = 100000
	_last.set_script(preload("res://frame_probe_tick.gd"))
	_last.probe = self
	_last.is_first = false
	add_child(_last)

func tick_first() -> void:
	_t0 = Time.get_ticks_usec()

func tick_last(delta: float) -> void:
	var ms := (Time.get_ticks_usec() - _t0) / 1000.0
	_script_sum += ms
	_script_max = maxf(_script_max, ms)
	_frame_sum += delta * 1000.0
	_frame_max = maxf(_frame_max, delta * 1000.0)
	_frames += 1

func _process(delta: float) -> void:
	_t += delta
	if _t < 2.0:
		return
	_t = 0.0
	var n := maxi(_frames, 1)
	# The four slowest sections of this window, slowest first.
	var names: Array = _sections.keys()
	names.sort_custom(func(a, b): return float(_sections[a]) > float(_sections[b]))
	var parts: PackedStringArray = []
	for i in mini(4, names.size()):
		parts.append("%s %.1f" % [names[i], float(_sections[names[i]])])
	var slow := "slowest: " + (" | ".join(parts) if not parts.is_empty() else "-") + " (ms)"
	_sections.clear()
	var extra := "scripts avg %.2f / max %.2f ms | frame avg %.2f / max %.2f ms | %s" % [_script_sum / n, _script_max, _frame_sum / n, _frame_max, slow]
	_script_sum = 0.0
	_script_max = 0.0
	_frame_sum = 0.0
	_frame_max = 0.0
	_frames = 0
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_vp)
	var line := "%s  fps %d | %s | render cpu %.2f ms | render gpu %.2f ms | draws %d | objects %d | window %s" % [
		Time.get_time_string_from_system(), Engine.get_frames_per_second(), extra, cpu, gpu,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		str(DisplayServer.window_get_size())]
	var path := OS.get_environment("HOME") + "/.config/tephra/frametime.log"
	var wm := Time.get_ticks_usec()  # the probe's own log write is timed too, in case it is the hitch
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(line)
		f.close()
		mark("probe log write", wm)
