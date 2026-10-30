extends Node
## Tracks connected controllers: player numbers (1, 2, 3... in connection order,
## kept when others disconnect), controller family, battery, and DualSense lights.
## Lights are written through Linux's LED files, which need the udev rule from
## the setup steps; without it everything else still works, just no lights.

signal changed  # a controller connected, disconnected, or its battery changed
signal low_battery(slot: int, pct: int, family: String)

const Glyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
static var NAVY: Color = Themes.c("accent")  # Tephra lightbar colour #0D124C
const RED := Color8(255, 30, 20)
const LOW_WARN := [15, 5]  # battery levels that trigger a warning
# DualSense player lights (5 dots, left to right) for players 1 to 5.
const PLAYER_DOTS := [[0, 0, 1, 0, 0], [0, 1, 0, 1, 0], [1, 0, 1, 0, 1], [1, 1, 0, 1, 1], [1, 1, 1, 1, 1]]

var slots := {}         # Godot device id -> player number
var _warned := {}       # player number -> lowest warning level already shown
var _hid_cache := {}    # family -> Array of hid info dictionaries
var _light_tweens := {} # hid path -> Tween
var _can_write := true

func _ready() -> void:
	Glyphs.slots = slots  # the same dictionary: Tephra's controller priority uses the player numbers
	Input.joy_connection_changed.connect(_on_connection)
	var pads := Input.get_connected_joypads()
	pads.sort()
	for d in pads:
		_assign(d)
	_scan_hid()
	var t := Timer.new()
	t.wait_time = 30.0
	t.autostart = true
	t.timeout.connect(_check_batteries)
	add_child(t)

## Connected controllers, sorted by player number:
## [{slot, device, family, battery (-1 = unknown), charging}]
func list() -> Array:
	var out: Array = []
	var by_family := {}
	var devices := slots.keys()
	devices.sort()
	for d in devices:
		var fam := Glyphs.family_for_device(d)
		var idx: int = by_family.get(fam, 0)
		by_family[fam] = idx + 1
		var bat := -1
		var charging := false
		var hids: Array = _hid_cache.get(fam, [])
		if idx < hids.size():
			bat = _read_int(hids[idx]["battery"] + "/capacity")
			charging = _read(hids[idx]["battery"] + "/status") == "Charging"
		out.append({"slot": slots[d], "device": d, "family": fam, "model": Glyphs.model_for_device(d),
			"name": Glyphs.pretty_name(d), "battery": bat, "charging": charging})
	out.sort_custom(func(a, b): return a["slot"] < b["slot"])
	return out

# ---------- Player numbers ----------
func _assign(device: int) -> void:
	if slots.has(device) or Glyphs.family_for_device(device) == "":
		return  # already numbered, or Steam's virtual pad
	var used := slots.values()
	var n := 1
	while used.has(n):
		n += 1
	slots[device] = n

func _on_connection(device: int, connected: bool) -> void:
	if connected:
		_assign(device)
	else:
		slots.erase(device)
	await get_tree().create_timer(1.0).timeout  # give Linux a moment to add the LED files
	_scan_hid()
	apply_player_lights()
	changed.emit()

# ---------- Linux device files ----------
# Finds controllers that report battery/lights through the kernel, grouped by family,
# in connection order (the HID number after the dot grows with each new device).
func _scan_hid() -> void:
	_hid_cache = {}
	var dir := DirAccess.open("/sys/class/power_supply")
	if dir == null:
		return
	var names := Array(dir.get_directories()) + Array(dir.get_files())
	for n: String in names:
		var fam := ""
		if n.begins_with("ps-controller-battery"):
			fam = "ps"
		elif n.begins_with("nintendo_switch_controller_battery"):
			fam = "nintendo"
		elif n.begins_with("xpadneo") or n.begins_with("gip"):
			fam = "xbox"
		if fam == "":
			continue
		var bat := "/sys/class/power_supply/" + n
		var dev := _realpath(bat + "/device")
		var seq := dev.get_file().get_extension().hex_to_int() if dev != "" else 0
		var info := {"battery": bat, "device": dev, "seq": seq, "rgb": "", "players": []}
		var leds := DirAccess.open(dev + "/leds")
		if leds != null:
			var led_names := Array(leds.get_directories()) + Array(leds.get_files())
			led_names.sort()
			for l: String in led_names:
				if l.ends_with(":rgb:indicator"):
					info["rgb"] = dev + "/leds/" + l
				elif l.contains(":white:player-"):
					info["players"].append(dev + "/leds/" + l)
		if not _hid_cache.has(fam):
			_hid_cache[fam] = []
		_hid_cache[fam].append(info)
	for fam in _hid_cache:
		_hid_cache[fam].sort_custom(func(a, b): return a["seq"] < b["seq"])

func _realpath(path: String) -> String:
	var out := []
	if OS.execute("readlink", ["-f", path], out) != 0 or out.is_empty():
		return ""
	return str(out[0]).strip_edges()

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_line().strip_edges() if f != null else ""

func _read_int(path: String) -> int:
	var s := _read(path)
	return s.to_int() if s.is_valid_int() else -1

func _write(path: String, value: String) -> void:
	if not _can_write:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_can_write = false
		print("Tephra: can't change controller lights (udev rule not installed?)")
		return
	f.store_string(value)

# ---------- Lights ----------
## The DualSense info for a player number, or {} if it isn't a DualSense.
func _hid_for_slot(slot: int) -> Dictionary:
	for c in list():
		if c["slot"] == slot and c["family"] == "ps":
			var ps_list: Array = []
			for d in list():
				if d["family"] == "ps":
					ps_list.append(d["slot"])
			var idx := ps_list.find(slot)
			var hids: Array = _hid_cache.get("ps", [])
			if idx >= 0 and idx < hids.size():
				return hids[idx]
	return {}

func _set_rgb(hid: Dictionary, c: Color) -> void:
	if hid.get("rgb", "") == "":
		return
	_write(hid["rgb"] + "/multi_intensity", "%d %d %d" % [c.r8, c.g8, c.b8])
	_write(hid["rgb"] + "/brightness", "255")

## Boot: every DualSense lightbar fades from off up to Tephra navy.
func intro_fade(seconds: float) -> void:
	for info in _hid_cache.get("ps", []):
		var tw := create_tween()
		tw.tween_method(func(k: float): _set_rgb(info, Color.BLACK.lerp(NAVY, k)), 0.0, 1.0, seconds)
		_light_tweens[info["rgb"]] = tw
	apply_player_lights()

## Player dots match each controller's number; lightbars stay navy.
func apply_player_lights() -> void:
	for c in list():
		var hid := _hid_for_slot(c["slot"])
		if hid.is_empty():
			continue
		var dots: Array = PLAYER_DOTS[clampi(c["slot"] - 1, 0, PLAYER_DOTS.size() - 1)]
		var players: Array = hid["players"]
		for i in mini(players.size(), 5):
			_write(players[i] + "/brightness", "1" if dots[i] == 1 else "0")
		if not _light_tweens.has(hid["rgb"]) or not _light_tweens[hid["rgb"]].is_running():
			_set_rgb(hid, NAVY)

## Every DualSense lightbar to this colour (Neon Coast's sky). Skipped while a lightbar is busy (boot fade,
## battery or red flash), and only written when the colour really changed, so it costs nearly nothing.
var _bar_last := {}

func set_lightbar(c: Color) -> void:
	NAVY = c  # anything that puts the lightbar "back to normal" goes back to this colour
	for info in _hid_cache.get("ps", []):
		var key: String = info.get("rgb", "")
		if key == "" or (_light_tweens.has(key) and _light_tweens[key].is_running()):
			continue
		var was: Color = _bar_last.get(key, Color(-1, -1, -1))
		if absi(was.r8 - c.r8) + absi(was.g8 - c.g8) + absi(was.b8 - c.b8) < 2:
			continue
		_bar_last[key] = c
		_set_rgb(info, c)

## Flashes a controller's lightbar red a few times, then back to navy.
func flash_red(slot: int) -> void:
	var hid := _hid_for_slot(slot)
	if hid.is_empty() or hid["rgb"] == "":
		return
	var tw := create_tween()
	for i in 4:
		tw.tween_callback(_set_rgb.bind(hid, RED))
		tw.tween_interval(0.25)
		tw.tween_callback(_set_rgb.bind(hid, Color.BLACK))
		tw.tween_interval(0.2)
	tw.tween_callback(_set_rgb.bind(hid, NAVY))
	_light_tweens[hid["rgb"]] = tw

# ---------- Battery warnings ----------
func _check_batteries() -> void:
	_scan_hid()
	for c in list():
		var pct: int = c["battery"]
		var slot: int = c["slot"]
		if pct < 0:
			continue
		if c["charging"] or pct > 20:
			_warned.erase(slot)  # reset once charging or recovered
			continue
		for level in LOW_WARN:
			if pct <= level and _warned.get(slot, 101) > level:
				_warned[slot] = level
				low_battery.emit(slot, pct, c["family"])
				flash_red(slot)
				break
	changed.emit()
