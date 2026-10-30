extends RefCounted
## Names you give your games. Saved by game number in the settings ("game_names"); the game's real name stays
## in Steam. An empty name puts the original back.

const Settings = preload("res://settings.gd")

static func _all() -> Dictionary:
	var d = Settings.get_value("game_names", {})
	return d if d is Dictionary else {}

static func custom(id: String) -> String:
	return str(_all().get(id, ""))

## The name to show: your name if you gave one, otherwise the original.
static func shown(id: String, original: String) -> String:
	var c := custom(id)
	return c if c != "" else original

static func set_custom(id: String, name: String) -> void:
	var d := _all().duplicate()
	var n := name.strip_edges()
	if n == "":
		d.erase(id)
	else:
		d[id] = n
	Settings.set_value("game_names", d)

## Puts your names on a list of game dictionaries ({id, title}); keeps the real name in "orig_title".
static func apply(list: Array) -> void:
	var d := _all()
	for g in list:
		var id := str(g["id"])
		if not g.has("orig_title"):
			g["orig_title"] = g["title"]
		g["title"] = str(d[id]) if d.has(id) and str(d[id]) != "" else g["orig_title"]
