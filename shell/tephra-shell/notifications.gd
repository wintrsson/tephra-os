extends RefCounted
## The notification list (Control center > Notifications). Everything that pops up on screen is also kept
## here (the toast, the battery pill, a new version, the weather changing...), newest first, so it can be
## read again later. Saved in user://notifications.json; at most KEEP are kept.

const KEEP := 40
const PATH := "user://notifications.json"

static var _list: Array = []   # [{text, time (unix), kind, read}]
static var _loaded := false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Array:
			_list = d

static func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_list))

## Adds a notification at the top. kind is only a label for now: "info", "update", "weather", "battery".
static func push(text: String, kind := "info") -> void:
	_load()
	if not _list.is_empty() and str(_list[0].get("text", "")) == text and Time.get_unix_time_from_system() - float(_list[0].get("time", 0)) < 30.0:
		return  # the same thing twice in a row
	if kind in ["update", "tephra_update"]:
		# a newer version: the notices about older ones (available or installed) go
		_list = _list.filter(func(e) -> bool: return not str(e.get("kind", "")) in ["update", "tephra_update"] \
				or (kind == "update" and _pending_update(e)))  # "updated to X" keeps a notice about an even newer one
	_list.push_front({"text": text, "time": Time.get_unix_time_from_system(), "kind": kind, "read": false})
	all()  # a waiting update goes back on top, so trimming never drops it
	while _list.size() > KEEP:
		_list.pop_back()
	_save()

## An "Update available: Tephra X" notice stays (it can't be cleared or removed) until Tephra is on X or newer.
static func _pending_update(e: Dictionary) -> bool:
	if str(e.get("kind", "")) != "tephra_update":
		return false
	var v := str(e.get("text", "")).get_slice("Tephra ", 1).strip_edges()
	return v != "" and preload("res://self_update.gd").newer(v, preload("res://self_update.gd").local_version())

## Newest first, with a waiting Tephra update always on top. Update notices for versions already installed go.
static func all() -> Array:
	_load()
	var keep: Array = []
	var rest: Array = []
	var changed := false
	for e in _list:
		if str(e.get("kind", "")) == "tephra_update" and not _pending_update(e):
			changed = true  # installed now: the notice has done its job
		elif _pending_update(e):
			if keep.is_empty():
				keep.append(e)
			else:
				changed = true  # only the newest update notice is kept
		else:
			rest.append(e)
	if changed or (not keep.is_empty() and not _list.is_empty() and _list[0] != keep[0]):
		_list = keep + rest
		_save()
	return _list

static func unread() -> int:
	_load()
	var n := 0
	for e in _list:
		if not bool(e.get("read", false)):
			n += 1
	return n

static func mark_read() -> void:
	_load()
	var changed := false
	for e in _list:
		if not bool(e.get("read", false)):
			e["read"] = true
			changed = true
	if changed:
		_save()

static func clear() -> void:
	_load()
	_list = _list.filter(func(e) -> bool: return _pending_update(e))
	_save()

static func remove(i: int) -> void:
	_load()
	if i >= 0 and i < _list.size() and not _pending_update(_list[i]):
		_list.remove_at(i)
		_save()

## "12:04 AM" for today, "Mon 12:04 AM" for older ones.
static func when(t: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(t) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	var now := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	var h12: int = int(d["hour"]) % 12
	if h12 == 0:
		h12 = 12
	var clock := "%d:%02d %s" % [h12, int(d["minute"]), "AM" if int(d["hour"]) < 12 else "PM"]
	if d["day"] == now["day"] and d["month"] == now["month"]:
		return clock
	return "%d/%d  %s" % [int(d["month"]), int(d["day"]), clock]
