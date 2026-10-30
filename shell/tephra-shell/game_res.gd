extends RefCounted
## Steam and PCSX2 settings files that Tephra edits.
## "Game resolution" (one resolution for every game through gamescope) was removed in v0.99.32: games choose their
## own resolution. It used to put tephra-run in front of every Steam game's launch command and turn Steam Input off
## for them, which left Proton games (RE9) without a controller. remove_wrapper() undoes that, once, while Steam is
## closed; until then tephra-run is kept as a plain pass-through so wrapped games still start normally.
## Also here: Steam Input off for the PS2 shortcuts (input_off) and PCSX2's controller setup (pcsx2_console_setup).
## Steam's localconfig.vdf is backed up first and only written if Tephra can write back exactly the text it read.

const Settings = preload("res://settings.gd")
const Ps2Games = preload("res://ps2_games.gd")

const PCSX2_INI := "/.var/app/net.pcsx2.PCSX2/config/PCSX2/inis/PCSX2.ini"

static func home() -> String:
	return OS.get_environment("HOME")

static func cfg_path() -> String:
	return home() + "/.config/tephra/game-display.cfg"

static func run_path() -> String:
	return home() + "/.local/share/tephra/tephra-run"

## While games may still have tephra-run in their launch options, it must exist (or they would not start), but it no
## longer does anything: it just starts the game.
static func write_passthrough() -> void:
	if not FileAccess.file_exists(run_path()):
		return
	var s := FileAccess.open(run_path(), FileAccess.WRITE)
	if s != null:
		s.store_string("#!/bin/bash\n# Left over from Tephra's removed Game resolution setting: starts the game as it is.\nexec \"$@\"\n")
		s.close()
		OS.execute("chmod", ["+x", run_path()])

## Once no game uses tephra-run any more: the script, its settings file and the old saved values go.
static func delete_files() -> void:
	DirAccess.remove_absolute(run_path())
	DirAccess.remove_absolute(cfg_path())
	# Back to empty values (Settings has no "erase", and a stored null would break code that expects a Dictionary).
	Settings.set_value("game_res", 0)
	Settings.set_value("res_orig", {})
	Settings.set_value("res_skip", [])
	Settings.set_value("res_removed", true)

# ---------- Steam launch options ----------
## A tiny reader and writer for Steam's text files: [[key, value]] where value is a String or an Array of the same.
static func _parse(text: String) -> Variant:
	var pos := [0]
	var items = _parse_block(text, pos, true)
	return items

static func _tok(text: String, pos: Array) -> Variant:
	var i: int = pos[0]
	while i < text.length() and text[i] in [" ", "\t", "\n", "\r"]:
		i += 1
	if i >= text.length():
		pos[0] = i
		return null
	var c := text[i]
	if c == "{" or c == "}":
		pos[0] = i + 1
		return [c]  # a brace is a one-item array so it can't be mistaken for a string
	if c != "\"":
		return false
	i += 1
	var out := ""
	while i < text.length() and text[i] != "\"":
		if text[i] == "\\" and i + 1 < text.length():
			i += 1
			match text[i]:
				"n": out += "\n"
				"t": out += "\t"
				_: out += text[i]
		else:
			out += text[i]
		i += 1
	pos[0] = i + 1
	return out

static func _parse_block(text: String, pos: Array, top: bool) -> Variant:
	var items: Array = []
	while true:
		var k = _tok(text, pos)
		if k == null:
			return items if top else false
		if k is bool:
			return false
		if k is Array:
			if k[0] == "}" and not top:
				return items
			return false
		var v = _tok(text, pos)
		if v == null or v is bool:
			return false
		if v is Array:
			if v[0] != "{":
				return false
			var kids = _parse_block(text, pos, false)
			if kids is bool:
				return false
			items.append([k, kids])
		else:
			items.append([k, v])
	return false

static func _esc(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t")

static func _write(items: Array, depth: int, out: PackedStringArray) -> void:
	var t := "\t".repeat(depth)
	for p in items:
		if p[1] is Array:
			out.append(t + "\"" + _esc(p[0]) + "\"")
			out.append(t + "{")
			_write(p[1], depth + 1, out)
			out.append(t + "}")
		else:
			out.append(t + "\"" + _esc(p[0]) + "\"\t\t\"" + _esc(p[1]) + "\"")

static func _text(items: Array) -> String:
	var out := PackedStringArray()
	_write(items, 0, out)
	return "\n".join(out) + "\n"

static func _child(items: Array, key: String, create: bool) -> Variant:
	for p in items:
		if str(p[0]).to_lower() == key.to_lower() and p[1] is Array:
			return p[1]
	if not create:
		return null
	var kids: Array = []
	items.append([key, kids])
	return kids

static func _idx(items: Array, key: String) -> int:
	for i in items.size():
		if str(items[i][0]).to_lower() == key.to_lower() and items[i][1] is String:
			return i
	return -1

static func _put(items: Array, key: String, value: String) -> void:
	var i := _idx(items, key)
	if i >= 0:
		items[i][1] = value
	else:
		items.append([key, value])

static func _local_path(steam_dir: String) -> String:
	var cfg := Ps2Games._config_dir(steam_dir)
	return "" if cfg == "" else cfg + "/localconfig.vdf"

## Takes tephra-run out of every Steam game's launch options and gives each one back the Steam Input setting it had
## before (saved in res_orig; with none saved, Steam's own default). Steam must NOT be running: it rewrites
## localconfig.vdf when it closes. Returns {changed, error}; changed == 0 and no error means nothing uses it any more.
static func remove_wrapper(steam_dir: String) -> Dictionary:
	var path := _local_path(steam_dir)
	if path == "" or not FileAccess.file_exists(path):
		return {"changed": 0, "error": "no localconfig"}
	var text := FileAccess.get_file_as_string(path)
	var root = _parse(text)
	if root is bool or _text(root) != text:
		return {"changed": 0, "error": "Steam's localconfig.vdf has parts Tephra can't copy safely, so the old Game resolution launch options were left in place."}
	var orig: Dictionary = Settings.get_value("res_orig", {})
	var run := "\"" + run_path() + "\""
	var changed := 0
	var store = _child(root, "UserLocalConfigStore", false)
	var node = store
	for k in ["Software", "Valve", "Steam"]:
		node = _child(node, k, false) if node != null else null
	if node == null:
		return {"changed": 0, "error": "Steam's localconfig.vdf has an unexpected layout."}
	var apps = _child(node, "apps", false)
	if apps == null:
		return {"changed": 0, "error": ""}
	for entry in apps:
		if not (entry[1] is Array):
			continue
		var app: Array = entry[1]
		var li := _idx(app, "LaunchOptions")
		if li < 0 or not str(app[li][1]).contains("tephra-run"):
			continue
		var opts := str(app[li][1]).replace(run + " ", "").replace(run, "")
		opts = opts.replace(run_path() + " ", "").replace(run_path(), "").strip_edges()  # in case it was written unquoted
		if opts == "%command%":
			opts = ""
		if opts == "":
			app.remove_at(li)
		else:
			app[li][1] = opts
		var sid := str(entry[0])
		var was := str(orig.get(sid, ""))
		var si := _idx(app, "UseSteamControllerConfig")
		if was == "":
			if si >= 0:
				app.remove_at(si)  # back to Steam's own default for this game
		else:
			_put(app, "UseSteamControllerConfig", was)
		changed += 1
	if changed == 0:
		return {"changed": 0, "error": ""}
	DirAccess.copy_absolute(path, path + ".tephra-backup")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"changed": 0, "error": "Couldn't write Steam's localconfig.vdf."}
	f.store_string(_text(root))
	f.close()
	return {"changed": changed, "error": ""}

## Turns Steam Input off for these games (the PS2 shortcuts), so the pad reaches the emulator itself. Same safety as stamp().
## The key name is inferred, and for non-Steam shortcuts the localconfig entry name (their number) is a guess too.
static func input_off(steam_dir: String, ids: Array) -> int:
	var path := _local_path(steam_dir)
	if path == "" or not FileAccess.file_exists(path):
		return 0
	var text := FileAccess.get_file_as_string(path)
	var root = _parse(text)
	if root is bool or _text(root) != text:
		return 0
	var store = _child(root, "UserLocalConfigStore", false)
	var node = store
	for k in ["Software", "Valve", "Steam"]:
		node = _child(node, k, false) if node != null else null
	if node == null:
		return 0
	# Steam keeps this setting either right under UserLocalConfigStore or with the launch options; written in both.
	var changed := 0
	for apps in [_child(store, "apps", true), _child(node, "apps", true)]:
		for id in ids:
			var app: Array = _child(apps, str(id), true)
			var si := _idx(app, "UseSteamControllerConfig")
			if si >= 0 and str(app[si][1]) == "0":
				continue
			_put(app, "UseSteamControllerConfig", "0")
			changed += 1
	if changed == 0:
		return 0
	DirAccess.copy_absolute(path, path + ".tephra-backup")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return 0
	f.store_string(_text(root))
	f.close()
	return changed

# ---------- PCSX2 ----------
## Sets key = value in [section] of an ini text (adding the section or the key if needed); only_if_missing keeps the
## player's own value.
static func _ini_set(lines: PackedStringArray, section: String, key: String, value: String, only_if_missing := false) -> PackedStringArray:
	var sec_at := -1
	var end := lines.size()
	for i in lines.size():
		var l := lines[i].strip_edges()
		if l.begins_with("["):
			if sec_at >= 0:
				end = i
				break
			if l == "[" + section + "]":
				sec_at = i
	if sec_at < 0:
		lines.append("")
		lines.append("[" + section + "]")
		lines.append(key + " = " + value)
		return lines
	for i in range(sec_at + 1, end):
		var l := lines[i].strip_edges()
		if l.begins_with(key + " ") or l.begins_with(key + "="):
			if not only_if_missing:
				lines[i] = key + " = " + value
			return lines
	# after the last non-empty line of the section
	var at := end
	while at - 1 > sec_at and lines[at - 1].strip_edges() == "":
		at -= 1
	lines.insert(at, key + " = " + value)
	return lines

## The first controller as PCSX2's pad 1 (only buttons the player hasn't bound themselves), no "are you sure?" box
## when a game is closed, and no message pop-ups over the game. PCSX2 must be closed. The key names are PCSX2 2.x's,
## from memory: unchecked against a real PCSX2.ini.
const PAD1 := [
	["Type", "DualShock2"], ["Up", "SDL-0/DPadUp"], ["Right", "SDL-0/DPadRight"], ["Down", "SDL-0/DPadDown"],
	["Left", "SDL-0/DPadLeft"], ["Triangle", "SDL-0/FaceNorth"], ["Circle", "SDL-0/FaceEast"], ["Cross", "SDL-0/FaceSouth"],
	["Square", "SDL-0/FaceWest"], ["Select", "SDL-0/Back"], ["Start", "SDL-0/Start"], ["L1", "SDL-0/LeftShoulder"],
	["L2", "SDL-0/+LeftTrigger"], ["R1", "SDL-0/RightShoulder"], ["R2", "SDL-0/+RightTrigger"], ["L3", "SDL-0/LeftStick"],
	["R3", "SDL-0/RightStick"], ["LUp", "SDL-0/-LeftY"], ["LRight", "SDL-0/+LeftX"], ["LDown", "SDL-0/+LeftY"],
	["LLeft", "SDL-0/-LeftX"], ["RUp", "SDL-0/-RightY"], ["RRight", "SDL-0/+RightX"], ["RDown", "SDL-0/+RightY"],
	["RLeft", "SDL-0/-RightX"], ["LargeMotor", "SDL-0/LargeMotor"], ["SmallMotor", "SDL-0/SmallMotor"],
]

static func pcsx2_console_setup() -> bool:
	var path := home() + PCSX2_INI
	if not FileAccess.file_exists(path):
		return false
	var before := FileAccess.get_file_as_string(path)
	var lines := before.split("\n")
	lines = _ini_set(lines, "InputSources", "SDL", "true")
	for b in PAD1:
		lines = _ini_set(lines, "Pad1", b[0], b[1], true)
	lines = _ini_set(lines, "UI", "ConfirmShutdown", "false")
	lines = _ini_set(lines, "EmuCore/GS", "OsdShowMessages", "false")
	lines = _ini_set(lines, "Achievements", "Notifications", "false")
	lines = _ini_set(lines, "Achievements", "LeaderboardNotifications", "false")
	var out := "\n".join(lines)
	if out == before:
		return true
	DirAccess.copy_absolute(path, path + ".tephra-backup")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(out)
	f.close()
	return true
