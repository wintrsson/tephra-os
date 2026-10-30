extends RefCounted
## Achievements from Steam's own cache on this PC (no API key, no internet).
##
## Steam keeps two files per game in Steam/appcache/stats:
##   UserGameStatsSchema_<appid>.bin           the achievement list (names, descriptions, icons)
##   UserGameStats_<account>_<appid>.bin       which ones you've unlocked, and when
## Both are in Valve's "binary KeyValues" format, decoded by parse_kv() below.

const RetroAch = preload("res://retro_ach.gd")

const ID64_BASE := 76561197960265728  # SteamID64 minus this = the account number in file names
const ICON_URL := "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/%s/%s"

static var _schemas := {}  # appid -> [file modified time, parsed schema]

## Account number used in the file names, from a SteamID64 ("7656119...").
static func account_id(steam_id: String) -> String:
	if steam_id.length() >= 16 and steam_id.is_valid_int():
		return str(steam_id.to_int() - ID64_BASE)
	return ""

## Everything about one game's achievements, or {} if Steam has no data for it:
## {game, total, unlocked, list: [{name, desc, hidden, unlocked, time, icon}]}
## The list has unlocked ones first (newest first), then locked ones.
static func for_game(steam_dir: String, account: String, appid: String) -> Dictionary:
	var ra := RetroAch.cached(appid)  # a PS2 game: its RetroAchievements (same shape, "source": "retro")
	if not ra.is_empty():
		return ra
	var schema := _schema(steam_dir, appid)
	var game: Dictionary = schema.get(appid, {})
	var blocks = game.get("stats", {})
	if not (blocks is Dictionary):
		return {}
	var mine := _user_stats(steam_dir, account, appid)
	var list: Array = []
	var unlocked := 0
	for block_id in blocks:
		var block = blocks[block_id]
		# Achievement blocks have "bits": each bit of a 32-bit number is one achievement.
		if not (block is Dictionary and block.get("bits") is Dictionary):
			continue
		var my_block = mine.get(block_id, {})
		var data := 0
		var times := {}
		if my_block is Dictionary:
			data = int(my_block.get("data", 0)) & 0xFFFFFFFF
			if my_block.get("AchievementTimes") is Dictionary:
				times = my_block["AchievementTimes"]
		for bit in block["bits"]:
			var a = block["bits"][bit]
			if not (a is Dictionary):
				continue
			var disp: Dictionary = a.get("display", {}) if a.get("display") is Dictionary else {}
			var got := (data >> int(bit)) & 1 == 1
			if got:
				unlocked += 1
			list.append({
				"api": str(a.get("name", "")),  # Steam's internal id, used for global rarity
				"name": _text(disp.get("name", a.get("name", ""))),
				"desc": _text(disp.get("desc", "")),
				"hidden": int(disp.get("hidden", 0)) == 1,
				"unlocked": got,
				"time": int(times.get(bit, 0)),
				"icon": ICON_URL % [appid, disp.get("icon" if got else "icon_gray", "")],
			})
	if list.is_empty():
		return {}
	list.sort_custom(func(x, y):
		if x["unlocked"] != y["unlocked"]:
			return x["unlocked"]
		return x["time"] > y["time"])
	var gname := str(game.get("gamename", ""))
	if gname.begins_with("ValveTestApp"):
		gname = ""  # placeholder name some games ship with; use your own title instead
	return {"game": gname, "total": list.size(), "unlocked": unlocked, "list": list}

## Your most recent unlocks across every game, newest first:
## [{appid, game, name, desc, time, icon}]
static func recent(steam_dir: String, account: String, count := 5) -> Array:
	var out := _steam_recent(steam_dir, account, count) + RetroAch.recent(count)
	out.sort_custom(func(x, y): return x["time"] > y["time"])
	return out.slice(0, count)

static func _steam_recent(steam_dir: String, account: String, count: int) -> Array:
	var dir := DirAccess.open(steam_dir + "/appcache/stats")
	if dir == null or account == "":
		return []
	var prefix := "UserGameStats_%s_" % account
	var found: Array = []  # [time, appid]
	for f in dir.get_files():
		if not (f.begins_with(prefix) and f.ends_with(".bin")):
			continue
		var appid := f.trim_prefix(prefix).trim_suffix(".bin")
		var mine := _user_stats(steam_dir, account, appid)
		for block_id in mine:
			var b = mine[block_id]
			if b is Dictionary and b.get("AchievementTimes") is Dictionary:
				for t in b["AchievementTimes"].values():
					found.append([int(t), appid])
	found.sort_custom(func(x, y): return x[0] > y[0])
	var out: Array = []
	var done := {}
	for entry in found:
		var appid: String = entry[1]
		if done.has(appid):
			continue
		# entry[0] is this game's newest unlock. Once that's older than everything
		# we already have, no remaining game can make the list.
		if out.size() >= count:
			out.sort_custom(func(x, y): return x["time"] > y["time"])
			if entry[0] <= out[count - 1]["time"]:
				break
		done[appid] = true
		var info := for_game(steam_dir, account, appid)
		for a in info.get("list", []):
			if a["unlocked"]:
				out.append({"appid": appid, "game": info["game"], "name": a["name"], "desc": a["desc"], "time": a["time"], "icon": a["icon"]})
	out.sort_custom(func(x, y): return x["time"] > y["time"])
	return out.slice(0, count)

## Total achievements unlocked across every game Steam has data for on this PC.
## Each unlocked achievement has an unlock time, so counting those is enough.
static func total_unlocked(steam_dir: String, account: String) -> int:
	return _steam_total(steam_dir, account) + RetroAch.total_unlocked()

static func _steam_total(steam_dir: String, account: String) -> int:
	var dir := DirAccess.open(steam_dir + "/appcache/stats")
	if dir == null or account == "":
		return 0
	var prefix := "UserGameStats_%s_" % account
	var total := 0
	for f in dir.get_files():
		if not (f.begins_with(prefix) and f.ends_with(".bin")):
			continue
		var mine := _user_stats(steam_dir, account, f.trim_prefix(prefix).trim_suffix(".bin"))
		for block_id in mine:
			var b = mine[block_id]
			if b is Dictionary and b.get("AchievementTimes") is Dictionary:
				total += b["AchievementTimes"].size()
	return total

# ---------- Files ----------
static func _schema(steam_dir: String, appid: String) -> Dictionary:
	var path := steam_dir + "/appcache/stats/UserGameStatsSchema_%s.bin" % appid
	if not FileAccess.file_exists(path):
		return {}
	var mtime := FileAccess.get_modified_time(path)
	if _schemas.has(appid) and _schemas[appid][0] == mtime:
		return _schemas[appid][1]
	var d := parse_kv(FileAccess.get_file_as_bytes(path))
	_schemas[appid] = [mtime, d]
	return d

static func _user_stats(steam_dir: String, account: String, appid: String) -> Dictionary:
	var path := steam_dir + "/appcache/stats/UserGameStats_%s_%s.bin" % [account, appid]
	if not FileAccess.file_exists(path):
		return {}
	var d := parse_kv(FileAccess.get_file_as_bytes(path))
	return d.get("cache", d) if d.get("cache", d) is Dictionary else {}

# Names can be plain text or a list of translations ({"english": ..., "french": ...}).
static func _text(v) -> String:
	if v is Dictionary:
		return str(v.get("english", v.get("token", "")))
	return str(v)

# ---------- Binary KeyValues ----------
# Each entry: 1 byte type, a key ending in a 0 byte, then the value.
# Types: 0 = section (nested entries until an 8), 1 = text, 2 = whole number,
# 3 = decimal, 7 = big whole number, 8 = end of section.
static func parse_kv(b: PackedByteArray) -> Dictionary:
	var pos := [0]  # an Array so the helpers below can move it forward
	return _parse(b, pos)

static func _parse(b: PackedByteArray, pos: Array) -> Dictionary:
	var out := {}
	while pos[0] < b.size():
		var t: int = b[pos[0]]
		pos[0] += 1
		if t == 8:
			return out
		var key := _cstr(b, pos)
		match t:
			0:
				out[key] = _parse(b, pos)
			1:
				out[key] = _cstr(b, pos)
			2, 4, 6:
				if pos[0] + 4 > b.size():
					return out
				out[key] = b.decode_s32(pos[0])
				pos[0] += 4
			3:
				if pos[0] + 4 > b.size():
					return out
				out[key] = b.decode_float(pos[0])
				pos[0] += 4
			7:
				if pos[0] + 8 > b.size():
					return out
				out[key] = b.decode_u64(pos[0])
				pos[0] += 8
			_:
				return out  # unknown type: stop rather than read garbage
	return out

static func _cstr(b: PackedByteArray, pos: Array) -> String:
	var start: int = pos[0]
	var end := start
	while end < b.size() and b[end] != 0:
		end += 1
	pos[0] = end + 1
	return b.slice(start, end).get_string_from_utf8()
