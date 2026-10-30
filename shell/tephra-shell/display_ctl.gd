extends RefCounted
## Reads and changes the monitor's resolution, refresh rate and HDR through KDE's
## kscreen-doctor (Tephra runs on KDE). Everything here fails quietly when
## kscreen-doctor is missing: available() is then false and Settings shows a note.

static var _data := {}

## Re-reads the monitor list. Call before showing the rows.
static func refresh() -> void:
	_read_outputs()

## Reads kscreen-doctor's list. Returns its exit code (-1 = kscreen-doctor isn't installed).
static func _read_outputs() -> int:
	_data = {}
	var out := []
	var code := OS.execute("kscreen-doctor", ["-j"], out)
	if code != 0 or out.is_empty():
		return code
	var d = JSON.parse_string(str(out[0]))
	if d is Dictionary:
		_data = d
	return code

static func available() -> bool:
	return not output().is_empty()

## The monitor Tephra is on: the one at the window's screen position, else the first enabled one.
static func output() -> Dictionary:
	var outs: Array = _data.get("outputs", [])
	var first := {}
	var screen := DisplayServer.window_get_current_screen()
	var pos := DisplayServer.screen_get_position(screen)
	for o in outs:
		if not (o is Dictionary) or not bool(o.get("enabled", false)):
			continue
		if first.is_empty():
			first = o
		var p = o.get("pos", {})
		if p is Dictionary and int(p.get("x", -1)) == pos.x and int(p.get("y", -1)) == pos.y:
			return o
	return first

static func output_name() -> String:
	return str(output().get("name", ""))

## Every mode of this monitor as {id, w, h, hz}.
static func modes() -> Array:
	var list: Array = []
	for m in output().get("modes", []):
		var s = m.get("size", {})
		list.append({"id": str(m.get("id", "")), "w": int(s.get("width", 0)), "h": int(s.get("height", 0)), "hz": float(m.get("refreshRate", 0.0))})
	return list

static func current() -> Dictionary:
	var id := str(output().get("currentModeId", ""))
	for m in modes():
		if m["id"] == id:
			return m
	return {"id": "", "w": 0, "h": 0, "hz": 0.0}

## Resolutions this monitor can do, biggest first, as [w, h].
static func resolutions() -> Array:
	var seen := {}
	var list: Array = []
	for m in modes():
		var key := "%dx%d" % [m["w"], m["h"]]
		if not seen.has(key) and m["w"] >= 640:
			seen[key] = true
			list.append([m["w"], m["h"]])
	list.sort_custom(func(a, b): return a[0] * a[1] > b[0] * b[1])
	return list

## Refresh rates (rounded to whole Hz) available at a resolution, highest first.
static func rates(w: int, h: int) -> Array:
	var list: Array = []
	for m in modes():
		if m["w"] == w and m["h"] == h:
			var hz := roundi(m["hz"])
			if not list.has(hz):
				list.append(hz)
	list.sort_custom(func(a, b): return a > b)
	return list

## Switches to a resolution and refresh rate. Returns false if kscreen-doctor refused.
static func set_mode(w: int, h: int, hz: int) -> bool:
	var best := {}
	for m in modes():
		if m["w"] == w and m["h"] == h:
			if best.is_empty() or absf(m["hz"] - hz) < absf(float(best["hz"]) - hz):
				best = m
	if best.is_empty():
		return false
	var code := OS.execute("kscreen-doctor", ["output.%s.mode.%s" % [output_name(), best["id"]]], [])
	refresh()
	return code == 0

## Like set_mode, but with HDR switched off while the monitor changes mode, and back on afterwards. Changing the
## resolution or refresh rate with HDR (10-bit colour) on makes the monitor re-negotiate the link at the highest
## colour depth, and at some rates that leaves the picture folded or shifted. Doing it in 8-bit first is gentler.
static func set_mode_safely(w: int, h: int, hz: int) -> bool:
	var hdr := hdr_supported() and hdr_on()
	var wcg := wcg_on()
	if hdr:
		OS.execute("kscreen-doctor", ["output.%s.hdr.disable" % output_name()], [])
		OS.delay_msec(900)
	var ok := set_mode(w, h, hz)
	if hdr:
		OS.delay_msec(1600)  # let the monitor lock onto the new signal before asking for HDR again
		OS.execute("kscreen-doctor", ["output.%s.hdr.enable" % output_name()], [])
		if wcg:
			OS.execute("kscreen-doctor", ["output.%s.wcg.enable" % output_name()], [])
		refresh()
	return ok

## "1080p", "1440p", "4K" ... for the usual sizes.
static func label(w: int, h: int) -> String:
	var tag := ""
	match h:
		720: tag = "720p"
		900: tag = "900p"
		1080: tag = "1080p"
		1200: tag = "1200p"
		1440: tag = "1440p"
		1600: tag = "1600p"
		2160: tag = "4K"
	return "%d x %d%s" % [w, h, ("  (" + tag + ")") if tag != "" else ""]

# ---------- HDR ----------
## Whether this monitor reports HDR support to kscreen-doctor.
static func hdr_supported() -> bool:
	return output().has("hdr")

static func hdr_on() -> bool:
	return bool(output().get("hdr", false))

static func wcg_on() -> bool:
	return bool(output().get("wcg", false))

static func sdr_brightness() -> int:
	return int(output().get("sdr-brightness", output().get("sdrBrightness", 200)))

static func set_hdr(on: bool) -> bool:
	var code := OS.execute("kscreen-doctor", ["output.%s.hdr.%s" % [output_name(), "enable" if on else "disable"]], [])
	refresh()
	return code == 0

static func set_wcg(on: bool) -> bool:
	var code := OS.execute("kscreen-doctor", ["output.%s.wcg.%s" % [output_name(), "enable" if on else "disable"]], [])
	refresh()
	return code == 0

static func set_sdr_brightness(nits: int) -> bool:
	var code := OS.execute("kscreen-doctor", ["output.%s.sdr-brightness.%d" % [output_name(), nits]], [])
	refresh()
	return code == 0

# ---------- Which display Tephra is on ----------
static func screen_names() -> Array:
	var list: Array = []
	for i in DisplayServer.get_screen_count():
		var sz := DisplayServer.screen_get_size(i)
		var hz := DisplayServer.screen_get_refresh_rate(i)
		var t := "Display %d  -  %d x %d" % [i + 1, sz.x, sz.y]
		if hz > 0.0:
			t += " @ %d Hz" % roundi(hz)
		list.append(t)
	return list

# ---------- Choosing the right screen ----------
## Built-in laptop panels: their connector names start with one of these (eDP-1, LVDS-1, DSI-1).
const INTERNAL_PREFIXES := ["edp", "lvds", "dsi"]

static func is_internal(output_name_text: String) -> bool:
	var n := output_name_text.to_lower()
	for p in INTERNAL_PREFIXES:
		if n.begins_with(p):
			return true
	return false

## The Godot screen number whose top-left corner is at x, y (or -1).
static func _screen_at(screens: Array, x: int, y: int) -> int:
	for i in screens.size():
		var p: Vector2i = screens[i]["pos"]
		if p.x == x and p.y == y:
			return i
	return -1

## Every Godot screen as {pos, size}.
static func _screens() -> Array:
	var list: Array = []
	for i in DisplayServer.get_screen_count():
		list.append({"pos": DisplayServer.screen_get_position(i), "size": DisplayServer.screen_get_size(i)})
	return list

## Which screen Tephra belongs on:
##   1. an external monitor or TV if one is connected (the primary one if there are several),
##   2. otherwise the built-in laptop screen.
## It asks KDE (kscreen-doctor) which outputs are built-in. Without it, it falls back to the
## biggest screen, since a laptop panel is almost always smaller than a monitor or TV.
## `data` and `screens` are only for testing; normally the real ones are read.
static func best_screen(data := {}, screens := []) -> int:
	if screens.is_empty():
		screens = _screens()
	var count := screens.size()
	if count <= 1:
		return 0
	if data.is_empty():
		# The desktop may still be starting up (autologin), so give kscreen a few tries.
		for attempt in 6:
			var code := _read_outputs()
			if code == -1 or not _data.is_empty():
				break  # got an answer, or kscreen-doctor isn't there at all (not KDE): don't wait
			OS.delay_msec(250)
		data = _data
	var external: Array = []   # [priority, screen]
	var internal := -1
	for o in data.get("outputs", []):
		if not (o is Dictionary) or not bool(o.get("enabled", false)) or not bool(o.get("connected", true)):
			continue
		var p = o.get("pos", {})
		if not (p is Dictionary):
			continue
		var s := _screen_at(screens, int(p.get("x", -99999)), int(p.get("y", -99999)))
		if s < 0:
			continue
		if is_internal(str(o.get("name", ""))):
			internal = s
		else:
			external.append([int(o.get("priority", 99)), s])
	if not external.is_empty():
		external.sort_custom(func(a, b): return a[0] < b[0])
		return int(external[0][1])
	if internal >= 0:
		return internal
	# No kscreen answer: the biggest screen wins.
	var best := 0
	var best_area := 0
	for i in count:
		var sz: Vector2i = screens[i]["size"]
		var area := sz.x * sz.y
		if area > best_area:
			best_area = area
			best = i
	return best

## Makes the screen Tephra is on the one games open on. Steam games (and Proton/Wine ones) start on
## KDE's primary screen, and KDE puts new windows on the screen the mouse is on, so this sets that
## screen as primary and moves the pointer onto it. Does nothing if kscreen-doctor is missing.
static func send_games_here(move_mouse := false) -> void:
	_read_outputs()
	var o := output()  # the output under Tephra's window
	if o.is_empty():
		return
	if int(o.get("priority", 1)) != 1:
		OS.execute("kscreen-doctor", ["output.%s.primary" % str(o.get("name", ""))], [])
	if move_mouse and OS.execute("which", ["xdotool"], []) == 0:
		var screen := DisplayServer.window_get_current_screen()
		var c := DisplayServer.screen_get_position(screen) + DisplayServer.screen_get_size(screen) / 2
		OS.execute("xdotool", ["mousemove", str(c.x), str(c.y)], [])

## Puts Tephra, fullscreen, on the right screen (see best_screen). Does nothing if it is already there.
static func place_best() -> void:
	var i := best_screen()
	if not (i == DisplayServer.window_get_current_screen() and DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]):
		move_to_screen(i)
	send_games_here()  # and make that screen the one games open on

## Moves Tephra to another display and makes it fullscreen there.
static func move_to_screen(i: int) -> void:
	if i < 0 or i >= DisplayServer.get_screen_count():
		return
	var mode := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(i)
	DisplayServer.window_set_position(DisplayServer.screen_get_position(i))
	DisplayServer.window_set_mode(mode if mode != DisplayServer.WINDOW_MODE_MINIMIZED else DisplayServer.WINDOW_MODE_FULLSCREEN)
