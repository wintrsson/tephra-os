extends Node
## Controller battery and lights.
##
## Battery bands (for the controller icon in the top bar):
##     green  - above 30%        orange - 30% or less        red - 10% or less
## The controller only lights up when the battery DROPS into a band: it pulses that
## colour a few times, then settles back to its normal Tephra colour. At the same moment
## a notification appears (only on screens where the top-bar icon isn't visible) and the
## top-bar icon pulses. Everything that pulses follows the one value `k` (0..1), so the
## lightbar, the icon and the notification are always in step.
##
## Developer menu: "Lightbar colour" can follow the theme (default), the battery, or a
## custom colour from the colour picker.

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")

signal alert_fired(level: int, pct: int, family: String)

const ORANGE_AT := 30
const RED_AT := 10
const GREEN := Color("46D17B")
const ORANGE := Color("FF9A1F")
const RED := Color("FF0000")      # pure red: any green/blue in it makes the lightbar look pink
const FrameProbe = preload("res://frame_probe.gd")
static var THEME: Color = Themes.c("accent")    # the Tephra lightbar colour
const PERIOD := 1.25              # seconds per pulse
const PULSES := 3

var controllers          # controllers.gd, set by home.gd
var enabled := false     # off until the boot intro has finished
var force_level := 0     # Developer menu test: 0 off, 1 low, 2 critical
var status := {"connected": false, "pct": -1, "charging": false, "band": 0, "family": "generic", "count": 0}
var flashing := false
var flash_level := 0
var k := 0.0             # 0..1: how bright the current pulse is (shared by lightbar, icon, notification)

var _bands := {}         # controller slot -> band last seen
var _scan_t := 0.0
var _flash_t := 0.0
var _base := Color.BLACK # the lightbar colour before a pulse starts
var _light_t := 0.0
var _mode_t := 0.0
var _preview := Color.BLACK
var _has_preview := false
var _last_written := Color(-1, -1, -1)
var _leds: Array = []
var _leds_t := -10.0

func setup(c) -> void:
	controllers = c

## Called once the boot logo has gone: from now on, alerts may fire.
func enable() -> void:
	enabled = true
	_bands.clear()
	_scan()

func band_color(band: int) -> Color:
	return RED if band >= 2 else (ORANGE if band == 1 else GREEN)

func level_text(level: int) -> String:
	return "critically low" if level >= 2 else "low"

# ---------- Reading the batteries ----------
func _scan() -> void:
	var pads := Input.get_connected_joypads()
	var best_pct := -1
	var charging := false
	var family := "generic"
	var count := 0
	var fire_level := 0
	var fire_pct := -1
	if controllers != null:
		for c in controllers.list():
			count += 1
			var pct: int = int(c.get("battery", -1))
			var chg: bool = bool(c.get("charging", false))
			var slot: int = int(c.get("slot", 0))
			family = str(c.get("family", family))
			var band := 0
			if pct >= 0 and not chg:
				band = 2 if pct <= RED_AT else (1 if pct <= ORANGE_AT else 0)
			if pct >= 0 and (best_pct < 0 or pct < best_pct):
				best_pct = pct
				charging = chg
			# A new, worse band for this controller: that is an alert.
			if enabled and bool(Settings.get_value("battery_flash", true)) and band > int(_bands.get(slot, 0)) and band > fire_level:
				fire_level = band
				fire_pct = pct
			_bands[slot] = band
	var band_now := 0
	if best_pct >= 0 and not charging:
		band_now = 2 if best_pct <= RED_AT else (1 if best_pct <= ORANGE_AT else 0)
	status = {"connected": not pads.is_empty(), "pct": best_pct, "charging": charging, "band": band_now, "family": family, "count": count}
	if force_level > 0:
		status["band"] = force_level
		status["pct"] = 25 if force_level == 1 else 8
		status["charging"] = false
	if fire_level > 0 and force_level == 0:
		fire(fire_level, fire_pct)

## Developer menu: show an alert (1 low, 2 critical) or stop it (0).
func dev_test(level: int) -> void:
	force_level = level
	_scan()
	if level > 0:
		fire(level, 25 if level == 1 else 8)

## Starts the pulses and tells the rest of Tephra (the notification, the top-bar icon).
func fire(level: int, pct: int) -> void:
	flash_level = level
	flashing = true
	_flash_t = 0.0
	_base = _mode_color()
	alert_fired.emit(level, pct, str(status.get("family", "generic")))

# ---------- Every frame ----------
func _process(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= 2.0:
		_scan_t = 0.0
		var m := Time.get_ticks_usec()
		_scan()
		FrameProbe.mark("battery scan", m)
	if flashing:
		_flash_t += delta
		var total := PERIOD * PULSES
		if _flash_t >= total:
			flashing = false
			k = 0.0
			_write(_mode_color(), true)
			return
		if bool(Settings.get_value("reduce_flashing", false)):
			k = clampf(sin(PI * _flash_t / total) * 1.3, 0.0, 1.0)  # one slow swell instead of pulses
		else:
			k = 0.5 - 0.5 * cos(TAU * _flash_t / PERIOD)
		_light_t += delta
		if _light_t >= 0.033:  # 30 writes a second at most
			_light_t = 0.0
			_write(_base.lerp(band_color(flash_level), k))
		return
	k = 0.0
	_mode_t += delta
	if _mode_t >= 1.0:
		_mode_t = 0.0
		var m2 := Time.get_ticks_usec()
		_apply_mode()
		FrameProbe.mark("lightbar check", m2)
	if _has_preview:
		_write(_preview)

# ---------- Lightbar modes ----------
func _mode() -> String:
	return "theme"  # the lightbar is always Tephra's colour until themes arrive

func custom_color() -> Color:
	return Color.html(str(Settings.get_value("lightbar_custom", "#0D124C")))

func _mode_color() -> Color:
	match _mode():
		"battery":
			return band_color(int(status.get("band", 0)))
		"custom":
			return custom_color()
	return THEME

## Applies the chosen mode right now (the Developer menu calls this when you change it).
func apply_mode_now() -> void:
	_last_written = Color(-1, -1, -1)
	_apply_mode()

func _apply_mode() -> void:
	if flashing or _has_preview or not enabled:
		return
	match _mode():
		"battery":
			_write(band_color(int(status.get("band", 0))))
		"custom":
			_write(custom_color())
		_:
			# Tephra theme: keep the lightbar at #0D124C (if something else changed it, put it back).
			var cur := _read()
			if cur.a > 0.0 and (roundi(cur.r * 255.0) != roundi(THEME.r * 255.0) or roundi(cur.g * 255.0) != roundi(THEME.g * 255.0) or roundi(cur.b * 255.0) != roundi(THEME.b * 255.0)):
				_write(THEME, true)

## Colour picker: show a colour on the lightbar while you choose it.
func set_preview(c: Color) -> void:
	_has_preview = true
	_preview = c
	_write(c)

func clear_preview() -> void:
	_has_preview = false
	apply_mode_now()

# ---------- Lightbars ----------
# A DualSense has one LED called "inputN:rgb:indicator" (write "R G B" to multi_intensity).
# A DualShock 4 has three LEDs, "...:red", "...:green" and "...:blue" (write 0-255 to brightness).
var _triples: Array = []  # [[red_dir, green_dir, blue_dir], ...]

func _led_paths() -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _leds_t > 3.0:
		_leds_t = now
		_leds.clear()
		_triples.clear()
		if DirAccess.dir_exists_absolute("/sys/class/leds"):
			for d in DirAccess.get_directories_at("/sys/class/leds"):
				if d.ends_with(":rgb:indicator"):
					_leds.append("/sys/class/leds/" + d)
				elif d.ends_with(":red"):
					var pre := d.trim_suffix(":red")
					if DirAccess.dir_exists_absolute("/sys/class/leds/" + pre + ":green") and DirAccess.dir_exists_absolute("/sys/class/leds/" + pre + ":blue"):
						_triples.append(["/sys/class/leds/" + d, "/sys/class/leds/" + pre + ":green", "/sys/class/leds/" + pre + ":blue"])
	return _leds

func _read() -> Color:
	for base in _led_paths():
		var f := FileAccess.open(str(base) + "/multi_intensity", FileAccess.READ)
		if f != null:
			var p := f.get_line().strip_edges().split(" ", false)
			if p.size() >= 3:
				return Color(p[0].to_float() / 255.0, p[1].to_float() / 255.0, p[2].to_float() / 255.0)
	for t in _triples:
		var v: Array = []
		for dir in t:
			var f2 := FileAccess.open(str(dir) + "/brightness", FileAccess.READ)
			v.append(f2.get_line().strip_edges().to_float() / 255.0 if f2 != null else 0.0)
		return Color(v[0], v[1], v[2])
	return Color(0, 0, 0, 0)

func _write(c: Color, force := false) -> void:
	if not force and _last_written.is_equal_approx(c):
		return
	_last_written = c
	for base in _led_paths():
		var f := FileAccess.open(str(base) + "/multi_intensity", FileAccess.WRITE)
		if f != null:
			f.store_string("%d %d %d" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)])
			f.close()
	for t in _triples:
		var vals := [c.r, c.g, c.b]
		for i in 3:
			var f3 := FileAccess.open(str(t[i]) + "/brightness", FileAccess.WRITE)
			if f3 != null:
				f3.store_string(str(roundi(float(vals[i]) * 255.0)))
				f3.close()
