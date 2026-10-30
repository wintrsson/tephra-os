extends RefCounted
## Tephra's saved settings (user://settings.json) and small helpers that read them.
## Values are cached after the first read so any screen can ask cheaply.

const PATH := "user://settings.json"

static var _data := {}
static var _loaded := false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if d is Dictionary:
		_data = d

static func get_value(key: String, default: Variant) -> Variant:
	_load()
	return _data.get(key, default)

static func set_value(key: String, value: Variant) -> void:
	_load()
	_data[key] = value
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_data))

## The time shown in every clock: "7:05 PM" or "19:05" depending on the setting.
static func clock_text() -> String:
	var t := Time.get_datetime_dict_from_system()
	if get_value("clock_24h", false):
		return "%02d:%02d" % [t["hour"], t["minute"]]
	var h: int = t["hour"] % 12
	if h == 0:
		h = 12
	return "%d:%02d %s" % [h, t["minute"], "PM" if t["hour"] >= 12 else "AM"]
