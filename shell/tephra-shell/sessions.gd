extends RefCounted
## A small log of when you played what, kept by Tephra (user://sessions.json). It feeds the
## "This week" card on the Today page. It starts empty and fills as you play from now on.

const PATH := "user://sessions.json"
const KEEP := 600

static func _all() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return d if d is Array else []

## Records a finished play session.
static func add(appid: String, minutes: float) -> void:
	if minutes < 0.5:
		return  # ignore launches that closed straight away
	var list := _all()
	list.append({"t": int(Time.get_unix_time_from_system()), "id": appid, "m": snappedf(minutes, 0.1)})
	if list.size() > KEEP:
		list = list.slice(list.size() - KEEP)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(list))

## The day number (local time) of a unix time.
static func day_of(t: int) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return int(floor(float(t + bias * 60) / 86400.0))

## The last 7 days, oldest first (today is last): {days: [minutes x7], total, top_id, top_min, streak}.
static func week() -> Dictionary:
	var today := day_of(int(Time.get_unix_time_from_system()))
	var days: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var per_game := {}
	var played := {}  # day number -> true (for the streak)
	for e in _all():
		var d := day_of(int(e.get("t", 0)))
		played[d] = true
		var back := today - d
		if back >= 0 and back < 7:
			days[6 - back] += float(e.get("m", 0.0))
			per_game[str(e.get("id", ""))] = float(per_game.get(str(e.get("id", "")), 0.0)) + float(e.get("m", 0.0))
	var total := 0.0
	for m in days:
		total += float(m)
	var top_id := ""
	var top_min := 0.0
	for id in per_game:
		if float(per_game[id]) > top_min:
			top_min = float(per_game[id])
			top_id = str(id)
	# Streak: days in a row ending today (or yesterday, if you haven't played yet today).
	var streak := 0
	var d2 := today if played.has(today) else today - 1
	while played.has(d2):
		streak += 1
		d2 -= 1
	return {"days": days, "total": total, "top_id": top_id, "top_min": top_min, "streak": streak, "today": today}
