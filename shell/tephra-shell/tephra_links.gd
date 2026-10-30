extends RefCounted
## Web links that a game (or Steam) opens on its own, like a Discord invite or "visit our website", must not land in
## the desktop browser over the game. Tephra makes itself the default for http and https links: tephra-link.sh passes
## each one to Tephra (see home.gd _links_poll), which keeps it out of the way during a game and can open it in its
## own browser afterwards. The browser that was the default before is remembered, and gets the links again when this is
## switched off, or when Tephra is not running.

const DESKTOP := "tephra-link.desktop"

static func _apps_dir() -> String:
	return OS.get_environment("HOME").path_join(".local/share/applications")

static func _prev_file() -> String:
	return OS.get_environment("HOME").path_join(".config/tephra/previous-browser")

static func _default_for(scheme: String) -> String:
	var out: Array = []
	if OS.execute("xdg-mime", ["query", "default", "x-scheme-handler/" + scheme], out) == 0 and not out.is_empty():
		return str(out[0]).strip_edges()
	return ""

## Run off the main thread (a few small commands). on = Tephra takes the links, off = the earlier browser has them again.
static func apply(on: bool) -> void:
	if OS.execute("sh", ["-c", "command -v xdg-mime >/dev/null"]) != 0:
		return
	if on:
		var script := ProjectSettings.globalize_path("res://tephra-link.sh")
		if not FileAccess.file_exists(script):
			return
		var cur := _default_for("https")
		if cur != "" and cur != DESKTOP:
			DirAccess.make_dir_recursive_absolute(OS.get_environment("HOME").path_join(".config/tephra"))
			var pf := FileAccess.open(_prev_file(), FileAccess.WRITE)
			if pf != null:
				pf.store_string(cur)
				pf.close()
		DirAccess.make_dir_recursive_absolute(_apps_dir())
		var entry := "[Desktop Entry]\nType=Application\nName=Tephra links\nComment=Keeps web links out of the desktop browser while Tephra runs\nExec=sh \"%s\" %%u\nNoDisplay=true\nMimeType=x-scheme-handler/http;x-scheme-handler/https;\n" % script
		var path := _apps_dir().path_join(DESKTOP)
		if FileAccess.get_file_as_string(path) != entry:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				return
			f.store_string(entry)
			f.close()
			OS.execute("update-desktop-database", [_apps_dir()], [])
			OS.execute("kbuildsycoca6", [], [])
		if _default_for("https") != DESKTOP or _default_for("http") != DESKTOP:
			OS.execute("xdg-mime", ["default", DESKTOP, "x-scheme-handler/http", "x-scheme-handler/https"], [])
	else:
		var prev := FileAccess.get_file_as_string(_prev_file()).strip_edges()
		if prev != "" and _default_for("https") == DESKTOP:
			OS.execute("xdg-mime", ["default", prev, "x-scheme-handler/http", "x-scheme-handler/https"], [])
