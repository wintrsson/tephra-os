extends Node
## RetroAchievements next to Steam's. Sign in under Settings > System > RetroAchievements (your user name and your
## web API key from retroachievements.org > Settings). For every PS2 game in the library Tephra finds the matching
## RetroAchievements game by its title, reads your progress and keeps it in user://ra/. Achievements.for_game() then
## returns it in the same shape as Steam's, so the game page, the Library page, Home and the profile show both
## (with the source marked "retro"). Reading works with the API key; UNLOCKING while you play is done by PCSX2
## itself and needs you to log in to RetroAchievements once inside PCSX2 (Settings > Achievements).
## None of this has been run against the real server yet.

const Settings = preload("res://settings.gd")
const Notifications = preload("res://notifications.gd")

const API := "https://retroachievements.org/API/"
const BADGE := "https://media.retroachievements.org/Badge/%s.png"
const PS2_CONSOLE := 21
const DIR := "user://ra"

signal synced

var _busy := false

static func user() -> String:
	return str(Settings.get_value("ra_user", ""))

static func key() -> String:
	return str(Settings.get_value("ra_key", ""))

static func signed_in() -> bool:
	return user() != "" and key() != ""

# ---------- What is saved (read by achievements.gd) ----------
static func cached(appid: String) -> Dictionary:
	var path := "%s/game_%s.json" % [DIR, appid]
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

static func _all_cached() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("game_") and f.ends_with(".json"):
			var d = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + f))
			if d is Dictionary:
				d["appid"] = f.trim_prefix("game_").trim_suffix(".json")
				out.append(d)
	return out

static func total_unlocked() -> int:
	var n := 0
	for d in _all_cached():
		n += int(d.get("unlocked", 0))
	return n

## Newest unlocks across every game, in the same shape as Achievements.recent(): [{appid, game, name, desc, time, icon}]
static func recent(count: int) -> Array:
	var out: Array = []
	for d in _all_cached():
		for a in d.get("list", []):
			if bool(a.get("unlocked", false)) and int(a.get("time", 0)) > 0:
				out.append({"appid": d["appid"], "game": str(d.get("game", "")), "name": a["name"], "desc": a["desc"],
					"time": int(a["time"]), "icon": a["icon"], "source": "retro"})
	out.sort_custom(func(x, y): return int(x["time"]) > int(y["time"]))
	return out.slice(0, count)

# ---------- Talking to the server ----------
func _api(path: String, params: Dictionary) -> Variant:
	var q: PackedStringArray = []
	for k in params:
		q.append("%s=%s" % [k, str(params[k]).uri_encode()])
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	var err := req.request(API + path + "?" + "&".join(q))
	if err != OK:
		req.queue_free()
		return null
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return null
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())

## Checks a user name and key against the server. Returns "" if they work, else a short reason.
func verify(u: String, k: String) -> String:
	var d = await _api("API_GetUserSummary.php", {"z": u, "y": k, "u": u, "g": 0})
	if d == null:
		return "Couldn't reach RetroAchievements, or the name or key was refused."
	if d is Dictionary and d.has("User"):
		return ""
	return "RetroAchievements didn't know that user name and key."

static func _norm(title: String) -> String:
	var t := RegEx.create_from_string("\\s*[\\(\\[][^\\)\\]]*[\\)\\]]").sub(title, "", true).to_lower()
	t = RegEx.create_from_string("[^a-z0-9]").sub(t, "", true)
	return t.trim_prefix("the")

func _game_list() -> Array:
	var path := DIR + "/gamelist_ps2.json"
	DirAccess.make_dir_recursive_absolute(DIR)
	if FileAccess.file_exists(path) and Time.get_unix_time_from_system() - FileAccess.get_modified_time(path) < 7.0 * 86400.0:
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Array:
			return d
	var d2 = await _api("API_GetGameList.php", {"z": user(), "y": key(), "i": PS2_CONSOLE, "f": 1})
	if not (d2 is Array):
		return []
	var slim: Array = []
	for g in d2:
		if g is Dictionary:
			slim.append({"id": int(g.get("ID", 0)), "t": str(g.get("Title", ""))})
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(slim))
	return slim

## Reads your progress for these PS2 games: [{id (Tephra's game id), title}]. Quiet when not signed in.
func sync(games: Array) -> void:
	if _busy or not signed_in() or games.is_empty():
		return
	_busy = true
	var list := await _game_list()
	if list.is_empty():
		_busy = false
		return
	var by_name := {}
	for g in list:
		by_name[_norm(str(g["t"]))] = int(g["id"])
	var before := total_unlocked()
	for g in games:
		var ra_id := int(by_name.get(_norm(str(g["title"])), 0))
		if ra_id == 0:
			for k in by_name:
				if k.begins_with(_norm(str(g["title"]))) and _norm(str(g["title"])).length() >= 6:
					ra_id = int(by_name[k])
					break
		if ra_id == 0:
			continue  # RetroAchievements has no set for this game (or it is named differently)
		await _fetch_game(str(g["id"]), ra_id)
	var gained := total_unlocked() - before
	_busy = false
	if gained > 0:
		Notifications.push("%d new RetroAchievements" % gained, "info")
	synced.emit()

func _fetch_game(tephra_id: String, ra_id: int) -> void:
	var d = await _api("API_GetGameInfoAndUserProgress.php", {"z": user(), "y": key(), "u": user(), "g": ra_id, "a": 1})
	if not (d is Dictionary) or not (d.get("Achievements") is Dictionary):
		return
	var list: Array = []
	var unlocked := 0
	for id in d["Achievements"]:
		var a = d["Achievements"][id]
		if not (a is Dictionary):
			continue
		var earned := str(a.get("DateEarnedHardcore", "")) if a.get("DateEarnedHardcore") != null else ""
		if earned == "" and a.get("DateEarned") != null:
			earned = str(a.get("DateEarned"))
		var got := earned != ""
		if got:
			unlocked += 1
		var badge := str(a.get("BadgeName", ""))
		list.append({
			"api": "ra" + str(id), "name": str(a.get("Title", "")), "desc": str(a.get("Description", "")),
			"hidden": false, "unlocked": got,
			"time": int(Time.get_unix_time_from_datetime_string(earned.replace(" ", "T"))) if got else 0,
			"icon": BADGE % (badge if got else badge + "_lock"),
			"points": int(a.get("Points", 0)),
		})
	if list.is_empty():
		return
	list.sort_custom(func(x, y):
		if x["unlocked"] != y["unlocked"]:
			return x["unlocked"]
		return x["time"] > y["time"])
	var out := {"game": str(d.get("Title", "")), "total": list.size(), "unlocked": unlocked, "list": list, "source": "retro"}
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open("%s/game_%s.json" % [DIR, tephra_id], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out))
