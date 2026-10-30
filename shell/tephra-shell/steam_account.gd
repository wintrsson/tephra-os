extends RefCounted
## Your Steam account: the API key from ~/.config/tephra/steam.cfg and the
## SteamID of whoever last signed in to Steam on this PC.

const CFG_PATH := "/.config/tephra/steam.cfg"

## Reads key=value lines from the config file.
static func read_cfg() -> Dictionary:
	var cfg := {}
	var f := FileAccess.open(OS.get_environment("HOME") + CFG_PATH, FileAccess.READ)
	if f == null:
		return cfg
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("#") or not line.contains("="):
			continue
		var kv := line.split("=", true, 1)
		cfg[kv[0].strip_edges()] = kv[1].strip_edges()
	return cfg

static func api_key() -> String:
	return read_cfg().get("api_key", "")

## steam_id from the config file, or the most recent Steam login on this PC.
static func steam_id(steam_dir: String) -> String:
	var cfg := read_cfg()
	if cfg.has("steam_id"):
		return cfg["steam_id"]
	var txt := FileAccess.get_file_as_string(steam_dir + "/config/loginusers.vdf")
	var re := RegEx.new()
	re.compile("\"(7656\\d{13})\"\\s*\\{([^}]*)\\}")
	var first := ""
	var recent := RegEx.new()
	recent.compile("\"MostRecent\"\\s+\"1\"")
	for m in re.search_all(txt):
		if first == "":
			first = m.get_string(1)
		if recent.search(m.get_string(2)) != null:
			return m.get_string(1)
	return first

## Your Steam name as saved on this PC (works offline).
static func persona_name(steam_dir: String, sid: String) -> String:
	var txt := FileAccess.get_file_as_string(steam_dir + "/config/loginusers.vdf")
	var re := RegEx.new()
	re.compile("\"" + sid + "\"\\s*\\{[^}]*?\"PersonaName\"\\s+\"([^\"]*)\"")
	var m := re.search(txt)
	return m.get_string(1) if m != null else ""

## Steam's own saved copy of your avatar, if it has one (works offline).
static func cached_avatar(steam_dir: String, sid: String) -> String:
	var p := steam_dir + "/config/avatarcache/" + sid + ".png"
	return p if FileAccess.file_exists(p) else ""
