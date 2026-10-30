extends RefCounted
## Games that are not ordinary installed Steam games:
##   1. Non-Steam games: the ones added in Steam with "Add a Non-Steam Game" (a .exe such as P.T., an emulator, a
##      launcher). Steam keeps them in userdata/<you>/config/shortcuts.vdf. Tephra reads that list and starts each one
##      through Steam itself, exactly like any other game, so Steam's compatibility layer (Proton) and its controller
##      handling keep working.
##   2. Family games: games another person in your Steam Family shares with you. The ones you have installed are
##      found like any other game. The ones you have not installed are found through their owner's Steam ID
##      (see family_ids), so they can be installed from the Library.

# ---------- Non-Steam games ----------
## All non-Steam games of the Steam accounts on this PC, as the same dictionaries Tephra uses for every game:
## {id, title, last, size, playtime, nonsteam: true, extra: true, url, exe}
static func nonsteam_games(steam_dir: String) -> Array:
	var out: Array = []
	var seen := {}
	var dir := DirAccess.open(steam_dir + "/userdata")
	if dir == null:
		return out
	for u in dir.get_directories():
		var path := steam_dir + "/userdata/" + u + "/config/shortcuts.vdf"
		if not FileAccess.file_exists(path):
			continue
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			continue
		var parsed := _parse_map(bytes, 0)
		var root: Dictionary = parsed["map"]
		var list: Dictionary = {}
		for k in root:
			if str(k).to_lower() == "shortcuts" and root[k] is Dictionary:
				list = root[k]
		for key in list:
			var e = list[key]
			if not (e is Dictionary):
				continue
			var g := _entry_to_game(e)
			if g.is_empty() or seen.has(g["id"]):
				continue
			seen[g["id"]] = true
			out.append(g)
	return out

static func _field(e: Dictionary, name: String, fallback = ""):
	for k in e:
		if str(k).to_lower() == name:
			return e[k]
	return fallback

static func _entry_to_game(e: Dictionary) -> Dictionary:
	var title := str(_field(e, "appname"))
	var exe := str(_field(e, "exe"))
	if title == "" or exe == "":
		return {}
	# Steam's own number for the shortcut. Newer Steam versions save it; older ones leave it out and it is
	# worked out from the program path and the name (this is the same recipe Steam uses).
	var id32: int
	var raw = _field(e, "appid", null)
	if raw is int:
		id32 = int(raw) & 0xFFFFFFFF
	else:
		id32 = (crc32(exe + title) | 0x80000000) & 0xFFFFFFFF
	var last := int(_field(e, "lastplaytime", 0))
	var launch := str(_field(e, "launchoptions"))
	return {
		"ps2": (exe + " " + launch).to_lower().contains("pcsx2"),
		"id": str(id32), "title": title, "last": last, "size": 0, "playtime": 0,
		"nonsteam": true, "extra": true, "url": "steam://rungameid/" + u64_string(id32, 0x02000000),
		"exe": exe.trim_prefix("\"").trim_suffix("\""),
	}

## Pattern (for pgrep -f) that matches the running program of a non-Steam game, as a fallback when Steam's own
## launcher process cannot be found by its number. The first letter is put in brackets so pgrep never matches itself.
static func process_pattern(exe: String) -> String:
	var base := exe.get_file()
	if base == "":
		return ""
	var esc := RegEx.create_from_string("([.^$*+?()\\[\\]{}|\\\\])").sub(base.substr(1), "\\$1", true)
	return "[" + base.substr(0, 1) + "]" + esc

## 64-bit game number of a non-Steam game: (shortcut number << 32) | 0x02000000, written in decimal.
## Godot's integers are signed, and this number does not fit when the shortcut number is above 2^31, so it is
## worked out in two decimal pieces.
static func u64_string(hi: int, lo: int) -> String:
	# hi * 2^32 = hi * 4 * 10^9 + hi * 294967296
	var a := hi * 294967296 + lo
	var carry := a / 1000000000
	var low9 := a % 1000000000
	var high := hi * 4 + carry
	if high == 0:
		return str(low9)
	return str(high) + "%09d" % low9

static var _crc_table: PackedInt64Array = PackedInt64Array()

static func crc32(text: String) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for i in 256:
			var c := i
			for _k in 8:
				c = ((c >> 1) ^ 0xEDB88320) if (c & 1) == 1 else (c >> 1)
			_crc_table[i] = c
	var crc := 0xFFFFFFFF
	for b in text.to_utf8_buffer():
		crc = _crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8)
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF

# ---------- Steam's binary list format (shortcuts.vdf) ----------
## A map is a run of: type byte, name (ends with a zero byte), value. Types: 0 = a nested map, 1 = text (ends with a
## zero byte), 2 = a 32-bit number, 8 = the end of this map. Returns {map, pos}.
static func _parse_map(b: PackedByteArray, start: int) -> Dictionary:
	var map := {}
	var pos := start
	var n := b.size()
	while pos < n:
		var t := int(b[pos])
		pos += 1
		if t == 8:
			break
		var name_end := pos
		while name_end < n and b[name_end] != 0:
			name_end += 1
		var key := b.slice(pos, name_end).get_string_from_utf8()
		pos = name_end + 1
		match t:
			0:
				var sub := _parse_map(b, pos)
				map[key] = sub["map"]
				pos = int(sub["pos"])
			1:
				var end := pos
				while end < n and b[end] != 0:
					end += 1
				map[key] = b.slice(pos, end).get_string_from_utf8()
				pos = end + 1
			2:
				if pos + 4 > n:
					break
				map[key] = int(b.decode_u32(pos))
				pos += 4
			7:
				pos += 8
			3, 4, 6:
				pos += 4
			_:
				break  # something this reader does not know: stop here and keep what was read so far
	return {"map": map, "pos": pos}

# ---------- Family games ----------
## Steam IDs of the people whose games you can borrow. They come from two places:
##  - installed games that belong to someone else: their appmanifest says who owns them (LastOwner), and
##  - ~/.config/tephra/family.txt, one Steam ID (the long number starting with 7656) per line, for the rest.
static func family_ids(steam_dir: String, my_id: String) -> PackedStringArray:
	var ids := PackedStringArray()
	var re := RegEx.create_from_string("\"LastOwner\"\\s+\"(7656\\d{13})\"")
	var libs: Array = [steam_dir]
	var re_path := RegEx.create_from_string("\"path\"\\s+\"([^\"]+)\"")
	for m in re_path.search_all(FileAccess.get_file_as_string(steam_dir + "/steamapps/libraryfolders.vdf")):
		if not libs.has(m.get_string(1)):
			libs.append(m.get_string(1))
	for lib in libs:
		var dir := DirAccess.open(lib + "/steamapps")
		if dir == null:
			continue
		for f in dir.get_files():
			if not (f.begins_with("appmanifest_") and f.ends_with(".acf")):
				continue
			var m := re.search(FileAccess.get_file_as_string(lib + "/steamapps/" + f))
			if m != null and m.get_string(1) != my_id and not ids.has(m.get_string(1)):
				ids.append(m.get_string(1))
	for sv in preload("res://settings.gd").get_value("family_ids", []):
		var si := str(sv)
		if si != my_id and not ids.has(si):
			ids.append(si)
	var path := OS.get_environment("HOME") + "/.config/tephra/family.txt"
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var s := line.strip_edges()
			if s.begins_with("7656") and s.length() == 17 and s != my_id and not ids.has(s):
				ids.append(s)
	return ids

## Pulls a Steam ID (7656 and 13 more digits) out of whatever was typed: the number itself or a profile link ending in it.
static func parse_steam_id(text: String) -> String:
	var m := RegEx.create_from_string("7656\\d{13}").search(text)
	return m.get_string() if m != null else ""

## Remembers a family member's Steam ID (Settings > System > Games). Returns false if it was already there.
static func add_family_id(id: String) -> bool:
	var S = preload("res://settings.gd")
	var list: Array = S.get_value("family_ids", []).duplicate()
	if list.has(id):
		return false
	list.append(id)
	S.set_value("family_ids", list)
	return true
