extends RefCounted
## Keeps Steam out of sight and silent. Steam has three ways to pop up over Tephra:
##   1. Its own notification toasts (a small Steam window in the corner, with a sound).
##      A KDE window rule makes that window invisible, keeps it below everything, and never
##      lets it take the focus.
##   2. Desktop notifications. KDE shows none at all while Tephra runs: Do Not Disturb is switched on for good
##      (critical ones included), every app and service KDE knows of has its popups off, and KDE's own battery
##      warnings are silenced at the source. Tephra shows its own notices instead.
##   3. Its sounds. Any sound stream from the Steam client itself (not from games) is muted.
## Steps 1 and 2 are written once at start-up and only change KDE settings files.

const TOAST_RULE := "7e4c2a1d-5b9f-4d1e-9a3c-tephra-toasts"

## Run once at start-up (off the main thread: it calls a few small commands).
static func apply() -> void:
	# Once per login (and again after an update changes this file): a theme change restarts Tephra, and running
	# the forty-odd small commands again each time would only slow it down.
	var run := OS.get_environment("XDG_RUNTIME_DIR")
	var mark := (run if run != "" else "/tmp") + "/tephra-quiet-%d" % FileAccess.get_modified_time("res://steam_quiet.gd")
	if FileAccess.file_exists(mark):
		return
	_quiet_notifications()
	_toast_rule()
	var f := FileAccess.open(mark, FileAccess.WRITE)
	if f != null:
		f.close()

static func _kw(file: String, groups: Array, key: String, value: String) -> void:
	var args: Array = ["--file", file]
	for g in groups:
		args += ["--group", g]
	args += ["--key", key, "--notify", value]
	OS.execute("kwriteconfig6", args, [])

static func _kr(file: String, groups: Array, key: String) -> String:
	var args: Array = ["--file", file]
	for g in groups:
		args += ["--group", g]
	args += ["--key", key]
	var out: Array = []
	OS.execute("kreadconfig6", args, out)
	return (str(out[0]) if not out.is_empty() else "").strip_edges()

# KDE notification settings (~/.config/plasmanotifyrc): no popups, sounds or history entries
# from Steam, and no popups from KDE's power manager (Tephra warns about the battery itself).
static func _quiet_notifications() -> void:
	for app in ["steam", "Steam", "com.valvesoftware.Steam"]:
		for k in ["ShowPopups", "ShowPopupsInDndMode", "ShowInHistory", "ShowBadges"]:
			_kw("plasmanotifyrc", ["Applications", app], k, "false")
	for svc in ["powerdevil", "org_kde_powerdevil", "org.kde.powerdevil"]:
		for k in ["ShowPopups", "ShowPopupsInDndMode"]:
			_kw("plasmanotifyrc", ["Services", svc], k, "false")
	# Every other app and service already listed in KDE's settings: popups off too.
	for kind in ["Applications", "Services"]:
		for name in _groups("plasmanotifyrc", kind):
			for k in ["ShowPopups", "ShowPopupsInDndMode"]:
				_kw("plasmanotifyrc", [kind, name], k, "false")
	# Do Not Disturb until the year 2099, and no critical popups or sounds in it either.
	_kw("plasmanotifyrc", ["DoNotDisturb"], "Until", "2099,12,31,0,0,0")
	_kw("plasmanotifyrc", ["DoNotDisturb"], "NotificationSoundsMuted", "true")
	for k in ["CriticalPopupsInDoNotDisturbMode", "CriticalInDndMode"]:
		_kw("plasmanotifyrc", ["Notifications"], k, "false")
	# KDE's power manager: its battery events (laptop and controllers) do nothing at all.
	for ev in ["lowbattery", "criticalbattery", "lowperipheralbattery", "lowvisiblebattery", "pluggedin", "unplugged",
			"fullbattery", "criticalbatteryaction"]:
		_kw("powerdevil.notifyrc", ["Event/" + ev], "Action", "")

## The [kind][name] groups in a KDE settings file (read straight from ~/.config).
static func _groups(file: String, kind: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(OS.get_environment("HOME") + "/.config/" + file, FileAccess.READ)
	if f == null:
		return out
	var head := "[" + kind + "]["
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with(head) and line.ends_with("]"):
			var name := line.substr(head.length(), line.length() - head.length() - 1)
			if not "][" in name and not out.has(name):
				out.append(name)
	return out

# KWin rules for Steam (~/.config/kwinrulesrc), written here so a new PC has them without copying any file:
#   - the toast window ("notificationtoasts_..."): fully see-through, below every other window, never focused, and
#     kept out of the task switcher (first in the list, so it wins over any other Steam rule);
#   - "Hide Steam behind Tephra": every Steam window stays below Tephra, out of the taskbar and the switcher, and
#     cannot steal the focus (home.gd's steam_rule() switches this one off while an install needs its popup);
#   - "Hide Steam Startup Windows": the small window Steam shows while it starts.
static func _toast_rule() -> void:
	var changed := _ensure_rule(TOAST_RULE, {
		"Description": "Tephra: hide Steam notification toasts",
		"wmclass": "steam", "wmclassmatch": "2", "wmclasscomplete": "false",
		"title": "notificationtoasts", "titlematch": "2",
		"opacityactive": "0", "opacityactiverule": "2",
		"opacityinactive": "0", "opacityinactiverule": "2",
		"below": "true", "belowrule": "2",
		"acceptfocus": "false", "acceptfocusrule": "2",
		"skiptaskbar": "true", "skiptaskbarrule": "2",
		"skipswitcher": "true", "skipswitcherrule": "2",
		"skippager": "true", "skippagerrule": "2",
	}, true)
	var hide := {
		"below": "true", "belowrule": "2",
		"fsplevel": "4", "fsplevelrule": "2",
		"skipswitcher": "true", "skipswitcherrule": "2",
		"skiptaskbar": "true", "skiptaskbarrule": "2",
	}
	var behind := hide.duplicate()
	behind.merge({"Description": "Hide Steam behind Tephra", "wmclass": "^[Ss]team$", "wmclassmatch": "3"})
	var startup := hide.duplicate()
	startup.merge({"Description": "Hide Steam Startup Windows", "title": "Steam", "titlematch": "1"})
	changed = _ensure_rule("4045d3eb-fa74-42e5-97eb-743f5622ba7f", behind, false) or changed
	changed = _ensure_rule("ecbc4e87-e358-4371-9302-896086d486e5", startup, false) or changed
	if changed:
		OS.execute("qdbus6", ["org.kde.KWin", "/KWin", "reconfigure"], [])

## Makes sure one rule exists with these settings and is in KWin's list (first or last). True if anything changed.
static func _ensure_rule(id: String, props: Dictionary, first: bool) -> bool:
	var g := [id]
	var changed := false
	for k in props:
		if _kr("kwinrulesrc", g, k) != props[k]:
			_kw("kwinrulesrc", g, k, props[k])
			changed = true
	var list: Array = []
	for r in _kr("kwinrulesrc", ["General"], "rules").split(",", false):
		list.append(r)
	if not list.has(id):
		if first:
			list.push_front(id)
		else:
			list.append(id)
		_kw("kwinrulesrc", ["General"], "rules", ",".join(list))
		_kw("kwinrulesrc", ["General"], "count", str(list.size()))
		changed = true
	return changed

## Mutes every sound stream that belongs to the Steam client (its notification and UI sounds).
## Games are separate programs, so their sound is never touched. Call it every few seconds.
static func mute_steam_sounds() -> void:
	var out: Array = []
	if OS.execute("pactl", ["-f", "json", "list", "sink-inputs"], out) != 0 or out.is_empty():
		return
	var data = JSON.parse_string(str(out[0]))
	if not (data is Array):
		return
	for s in data:
		if not (s is Dictionary):
			continue
		var p: Dictionary = s.get("properties", {})
		var bin := str(p.get("application.process.binary", "")).to_lower()
		var name := str(p.get("application.name", "")).to_lower()
		var steamy := bin in ["steam", "steamwebhelper", "steamwebhelper.sh"] or name in ["steam", "steamwebhelper"]
		if steamy and not bool(s.get("mute", false)):
			OS.execute("pactl", ["set-sink-input-mute", str(s.get("index", "")), "1"], [])
