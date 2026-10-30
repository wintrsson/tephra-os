extends Node
## Steam store lookups and everything built on them: finding a game's pictures by its name (non-Steam games, PS2 games
## that have a remake on Steam), adding a non-Steam game from a program file (Library > Add a game, R1), and the
## download helpers the cover-art code in home.gd uses. Moved out of home.gd; it reaches Home through `home`.

const CDN := "https://cdn.cloudflare.steamstatic.com/steam/apps/%s/%s.%s"
const Icons = preload("res://icons.gd")
const Ps2Games = preload("res://ps2_games.gd")
const Settings = preload("res://settings.gd")

var home  # home.gd

func setup(h) -> void:
	home = h

# ---------- Pictures for other non-Steam games, found by name ----------
## A non-Steam game with no pictures (one added from Settings > Games) is looked up by its name in the Steam store; when
## a game of the same name is there, its cover, wide picture, backdrop and logo are saved to Steam's grid folder for it,
## where Steam shows them too. Names that found nothing are not asked again for a week.
var _art_found := 0

func _nonsteam_art() -> void:
	_art_found = 0
	var cfg := Ps2Games._config_dir(home.steam_dir)
	if cfg == "":
		return
	var misses: Dictionary = Settings.get_value("art_misses", {})
	var now := Time.get_unix_time_from_system()
	for g in home.games.duplicate():
		if not bool(g.get("nonsteam", false)) or bool(g.get("ps2", false)):
			continue
		var id := str(g["id"])
		if home._grid_art(id, "library_600x900") != "":
			continue
		var title := str(g.get("orig_title", g["title"]))
		if now - float(misses.get(title, 0)) < 6 * 3600:
			continue
		var appid := ""
		var tried: Array = home._name_variants(title)
		for v in tried:
			appid = await _store_find(str(v))
			if appid != "":
				break
		if appid == "":
			misses[title] = now
			home._install_log("art: no store game found for the non-Steam game \"%s\" (tried: %s)" % [title, ", ".join(PackedStringArray(tried))])
			continue
		DirAccess.make_dir_recursive_absolute(cfg + "/grid")
		var got := 0
		for k in [["library_600x900", "p.jpg"], ["header", ".jpg"], ["library_hero", "_hero.jpg"], ["logo", "_logo.png"]]:
			var ext := "png" if str(k[0]) == "logo" else "jpg"
			if await _fetch_to(CDN % [appid, k[0], ext], "%s/grid/%s%s" % [cfg, id, k[1]]):
				got += 1
		if got > 0:
			_art_found += 1
			home._install_log("art: %s found as Steam app %s (%d pictures)" % [title, appid, got])
		else:
			misses[title] = now
	Settings.set_value("art_misses", misses)

# ---------- Adding a game (Library > Add a game) ----------
## R1 in the Library: Files opens to choose a game's program. Its name is worked out from the file and its folder
## (add_game.py), corrected to the Steam store's spelling when the store has the game, and it is written into Steam as a
## non-Steam game (a .exe is set to run with Proton). Its cover, wide picture, backdrop and logo then come from the
## store like any other non-Steam game's (_nonsteam_art). Steam has to be closed for this, so Tephra closes it first.
const ADD_EXTS := ["exe", "sh", "appimage", "x86_64"]  # keep in step with EXTS in add_game.py
var _adding := false
var _store_last_name := ""  # the store's own name for the game _store_find() last matched

func add_game() -> void:
	if _adding or home.launching:
		return
	home._open_cc()
	home.cc.pick_file("Choose the game's program: a .exe (Windows games, run with Proton), .sh, .AppImage or .x86_64.",
		ADD_EXTS, "Add this game", _add_game_from)

## Runs add_game.py on a worker thread (it reads and writes Steam's files) and returns the JSON line it printed.
func _add_game_py(args: Array) -> Dictionary:
	var box := {}
	var id = home._work(func() -> void:
		var out: Array = []
		OS.execute("python3", ["-I", ProjectSettings.globalize_path("res://add_game.py")] + args, out, true)
		box["out"] = str(out[0]) if not out.is_empty() else "")
	while not box.has("out"):
		await get_tree().create_timer(0.05).timeout
	home._work_done(id)
	var lines := str(box["out"]).strip_edges().split("\n")
	var d = JSON.parse_string(lines[lines.size() - 1]) if lines.size() > 0 else null
	return d if d is Dictionary else {"error": "Couldn't add the game: python3 gave no answer."}

## "RESIDENT EVIL 4™" -> "RESIDENT EVIL 4": the store's name without the trademark signs.
static func _tidy_store_name(name: String) -> String:
	return name.replace("™", "").replace("®", "").replace("©", "").strip_edges()

func _add_game_from(path: String) -> void:
	if _adding:
		return
	_adding = true
	var info := Icons.texture("info", Icons.svg_info(), 40)
	var guess: Dictionary = await _add_game_py(["guess", path])
	var title := str(guess.get("title", path.get_file().get_basename()))
	home.toast.show_toast(info, "Adding %s..." % title, false)
	# The store knows the proper spelling ("Hades2" is "Hades II"): its name is used when it has the game.
	_store_last_name = ""
	var store_id: String = await _store_find(title)
	if store_id != "" and _tidy_store_name(_store_last_name) != "":
		title = _tidy_store_name(_store_last_name)
	# Steam reads its list of games when it starts and writes it back when it closes, so it must be closed first.
	if home._steam_running():
		if home._any_game_running():
			home.notify("A game is running. Close it, then add %s again." % title, "info")
			_adding = false
			return
		if not home.library._installing.is_empty():
			home.notify("A game is downloading, and adding %s would stop it. Add it again once the download is done." % title, "info")
			_adding = false
			return
		# Only updates (or nothing) going on: Steam can close. Updates carry on by themselves afterwards.
		home._au_active = false
		await home._dl_close_steam()
		if home._steam_running():
			home.notify("Steam didn't close, so %s wasn't added. Try again in a moment." % title, "info")
			_adding = false
			return
	var res: Dictionary = await _add_game_py(["add", path, title])
	if res.has("error"):
		home.notify(str(res["error"]), "info")
		_adding = false
		return
	title = str(res.get("title", title))
	if bool(res.get("exists", false)):
		home.toast.show_toast(info, "%s is already in your games" % title, false)
		_adding = false
		return
	home._install_log("added non-Steam game %s from %s (id %s, Proton: %s)" % [title, path, str(res.get("id", "")), str(res.get("proton", "")) if str(res.get("proton", "")) != "" else "not needed"])
	if res.has("warning"):
		home.notify(str(res["warning"]), "info")
	home.refresh_games(false)  # it is in Steam's list now: Home and the Library pick it up
	home._pads_refresh()  # and it gets Tephra's layout (no touchpad click) while Steam is still closed
	await _nonsteam_art()  # its pictures from the Steam store, when the store has the game
	home._art_path_memo.clear()
	home._art_cache.clear()
	home._art_order.clear()
	home._logo_cache.clear()
	home._prewarm_logos()
	home.refresh_games(false)
	if home.library.is_open:
		home.library._rebuild()
	home.toast.show_toast(Icons.texture("check", Icons.svg_check(), 40), "Added %s" % title, false)
	_adding = false

## Library > a non-Steam game's page > Remove from Library: asks, closes Steam (it rewrites its list when it closes),
## then takes the game out of Steam's list of non-Steam games. The program's own files are not touched.
func remove_game(id: String, title: String) -> bool:
	if _adding or home.launching:
		return false
	var yes: bool = await home.overlay.ask("Remove %s?" % title, "It leaves your Library and Steam's list of games. The game's own files stay on the drive, and you can add it again with Add a game.", "Remove")
	if not yes or home.launching:
		return false
	_adding = true
	if home._steam_running():
		if not home.library._installing.is_empty():
			home.notify("A game is downloading, and removing %s would stop it. Try again once the download is done." % title, "info")
			_adding = false
			return false
		home._au_active = false
		await home._dl_close_steam()
		if home._steam_running():
			home.notify("Steam didn't close, so %s wasn't removed. Try again in a moment." % title, "info")
			_adding = false
			return false
	var res: Dictionary = await _add_game_py(["remove", id])
	_adding = false
	if res.has("error"):
		home.notify(str(res["error"]), "info")
		return false
	home._install_log("removed non-Steam game %s (id %s)" % [title, id])
	var hidden: Array = Settings.get_value("hidden_games", []).duplicate()
	hidden.erase(id)
	Settings.set_value("hidden_games", hidden)
	home.refresh_games(false)
	home.toast.show_toast(Icons.texture("check", Icons.svg_check(), 40), "Removed %s" % title, false)
	return true

## PS2 games whose name is also on Steam (a remaster or remake, like Silent Hill 2) borrow its real wide backdrop and
## logo. The PS2 box stays the cover. Names that found nothing are asked again after a week.
func _ps2_store_art() -> void:
	var cfg := Ps2Games._config_dir(home.steam_dir)
	if cfg == "":
		return
	var tried: Dictionary = Settings.get_value("ps2_store_art", {})
	var now := Time.get_unix_time_from_system()
	var got := 0
	for e in Ps2Games.scan():
		var id := str(Ps2Games.shortcut_id(str(e["title"])))
		var title := str(e["title"])
		var have_hero := FileAccess.file_exists("%s/grid/%s_hero.jpg" % [cfg, id])
		var have_cover := FileAccess.file_exists("%s/grid/%sp_remake.jpg" % [cfg, id])
		if (have_hero and have_cover) or (not have_hero and now - float(tried.get(title, 0)) < 7 * 86400) \
				or (have_hero and now - float(tried.get(title + "#cover", 0)) < 86400):
			continue
		tried[title + ("#cover" if have_hero else "")] = now
		var appid := ""
		var names: Array = home._name_variants(title)
		for v in names:
			appid = await _store_find(str(v))
			if appid != "":
				break
		if appid == "":
			home._install_log("art: no store game found for the PS2 game \"%s\" (tried: %s)" % [title, ", ".join(PackedStringArray(names))])
			continue
		DirAccess.make_dir_recursive_absolute(cfg + "/grid")
		if not have_hero and await _fetch_to(CDN % [appid, "library_hero", "jpg"], "%s/grid/%s_hero.jpg" % [cfg, id]):
			got += 1
		if not FileAccess.file_exists("%s/grid/%s_logo.png" % [cfg, id]):
			await _fetch_to(CDN % [appid, "logo", "png"], "%s/grid/%s_logo.png" % [cfg, id])
		# The remake's tall cover too, for "Art: Remake" (the PS2 box stays the cover for "Art: Original").
		if await _fetch_to(CDN % [appid, "library_600x900", "jpg"], "%s/grid/%sp_remake.jpg" % [cfg, id]):
			got += 1
		home._install_log("art: PS2 %s borrowed Steam app %s's backdrop" % [title, appid])
	Settings.set_value("ps2_store_art", tried)
	if got > 0:
		home._art_path_memo.clear()

## The Steam store number of the game with this name, or "" when nothing matches closely enough.
func _store_find(title: String) -> String:
	var tries: Array = [title]
	var clean := _clean_title(title)
	if clean != title and clean != "":
		tries.append(clean)
	for t in tries:
		var id := await _store_find_once(str(t))
		if id != "":
			return id
	return ""

## A game's name without what the store doesn't use: (2005), [GOG], ™, .exe, "Launcher", "Definitive Edition"...
static func _clean_title(title: String) -> String:
	var t := title.replace("_", " ").replace("™", "").replace("®", "").replace("©", "")
	var re := RegEx.new()
	re.compile("\\([^)]*\\)|\\[[^\\]]*\\]|\\.exe$|(?i)\\b(launcher|game of the year|goty|definitive|deluxe|complete|remastered|edition|enhanced)\\b")
	t = re.sub(t, " ", true)
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t.strip_edges(true, true).trim_suffix(":").trim_suffix("-").strip_edges()

func _store_find_once(title: String) -> String:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	var url := "https://store.steampowered.com/api/storesearch/?term=%s&cc=us&l=en" % title.uri_encode()
	if req.request(url) != OK:
		req.queue_free()
		return ""
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return ""
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (d is Dictionary and d.get("items") is Array):
		return ""
	var want := Ps2Games.norm(title)
	for it in d["items"]:
		if not it is Dictionary:
			continue
		var name := Ps2Games.norm(str(it.get("name", "")))
		if name == want or (want.length() >= 4 and (name.begins_with(want) or want.begins_with(name)) and minf(name.length(), want.length()) / maxf(name.length(), want.length()) > 0.7):
			_store_last_name = str(it.get("name", ""))
			return str(int(it.get("id", 0)))
	# Nothing that close: the first result, when one name holds the other ("Resident Evil 3" in "RESIDENT EVIL 3").
	for it in d["items"]:
		if it is Dictionary:
			var name2 := Ps2Games.norm(str(it.get("name", "")))
			if want.length() >= 5 and name2.length() >= 5 and (name2.contains(want) or want.contains(name2)) and minf(name2.length(), want.length()) / maxf(name2.length(), want.length()) > 0.5:
				_store_last_name = str(it.get("name", ""))
				return str(int(it.get("id", 0)))
			break
	return ""

## Where a newer game's pictures live, from Steam's store data: {"library_capsule": full URL, "library_hero": ...}.
## Empty if the store can't be reached. (The tall 600x900 cover is the "library_capsule".)
func _store_assets(appid: String) -> Dictionary:
	var out := {}
	var input := JSON.stringify({"ids": [{"appid": int(appid)}], "context": {"language": "english", "country_code": "US"}, "data_request": {"include_assets": true}})
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	if req.request("https://api.steampowered.com/IStoreBrowseService/GetItems/v1?input_json=" + input.uri_encode()) != OK:
		req.queue_free()
		return out
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200:
		var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("response")) == TYPE_DICTIONARY:
			var items = data["response"].get("store_items", [])
			if items is Array and not items.is_empty() and typeof(items[0]) == TYPE_DICTIONARY and typeof(items[0].get("assets")) == TYPE_DICTIONARY:
				var a: Dictionary = items[0]["assets"]
				var fmt := str(a.get("asset_url_format", ""))
				if fmt != "":
					for key in ["library_capsule", "library_hero", "library_logo", "header"]:
						if str(a.get(key, "")) != "":
							out[key] = "https://shared.akamai.steamstatic.com/store_item_assets/" + fmt.replace("${FILENAME}", str(a[key]))
	if not out.is_empty():
		return out
	# Fallback: the store page's header picture shows the hashed folder; the others sit next to it.
	var base := await _hashed_art_base(appid)
	if base != "":
		out = {"library_capsule": base + "/library_600x900.jpg", "library_hero": base + "/library_hero.jpg", "library_logo": base + "/logo.png", "header": base + "/header.jpg"}
	return out

## Where a newer game's pictures live: the folder of the header picture in Steam's store data ("" if it can't be told).
func _hashed_art_base(appid: String) -> String:
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	if req.request("https://store.steampowered.com/api/appdetails?appids=%s&filters=basic" % appid) != OK:
		req.queue_free()
		return ""
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return ""
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not data.has(appid) or typeof(data[appid]) != TYPE_DICTIONARY:
		return ""
	var d: Dictionary = data[appid].get("data", {}) if typeof(data[appid].get("data", {})) == TYPE_DICTIONARY else {}
	var hdr := str(d.get("header_image", ""))
	var cut := hdr.rfind("/")
	return hdr.substr(0, cut) if cut > 8 and hdr.contains("/steam/apps/%s/" % appid) and hdr.split("/steam/apps/%s/" % appid)[1].contains("/") else ""

func _fetch_to(url: String, dest: String) -> bool:
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		return false
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200 or (res[3] as PackedByteArray).size() < 1000:
		return false
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(res[3])
	return true
