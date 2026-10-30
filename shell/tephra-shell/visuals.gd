extends RefCounted
## Menu power use, in one place. Settings > System > Menu power use picks one of:
##   saver  - 30 FPS lock (the frame limit follows it), still background, no shine
##   normal - the usual Tephra

const Settings = preload("res://settings.gd")

static func mode() -> String:
	var m := str(Settings.get_value("gpu_mode", "normal"))
	if m == "enhanced":
		Settings.set_value("gpu_mode", "normal")  # the old Enhanced mode no longer exists
		m = "normal"
	return "saver" if m == "saver" else "normal"

static func saver() -> bool:
	return mode() == "saver"
