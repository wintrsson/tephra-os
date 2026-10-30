extends RefCounted
## PS2 games that live as disc images in ~/Games/PS2 (.iso, .chd, .cso, .bin). Tephra finds them and writes them into
## Steam as non-Steam shortcuts that start PCSX2 (the Flatpak), so they behave like every other game: they are listed
## in Home and the Library, started through Steam, tracked, and quit from Tephra. extra_games.gd already reads those
## shortcuts; this file only adds the missing ones (and a cover for each one).
##
## Steam keeps shortcuts in userdata/<you>/config/shortcuts.vdf and rewrites it when it closes, so it is only ever
## written while Steam is not running (see home.gd, ps2_sync). A copy of the old file is kept next to it first.
## Nothing here has been run on a real Steam yet.

const ExtraGames = preload("res://extra_games.gd")
const SteamAccount = preload("res://steam_account.gd")

const EXTS := ["iso", "chd", "cso", "bin", "gz", "zso"]
const LAUNCHER := "/usr/bin/flatpak"
## --env=...: Steam tells games launched through it to ignore the real controller (it hands them its own virtual one),
## and with Steam Input off for PCSX2 that virtual one is never there, so PCSX2 saw no pad at all. This undoes that.
const FLATPAK_ARGS := "run --env=SDL_GAMECONTROLLER_IGNORE_DEVICES= --env=SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT= net.pcsx2.PCSX2 -batch -nogui -fullscreen -- "
const BIOS_DIR := "/.var/app/net.pcsx2.PCSX2/config/PCSX2/bios"

static func games_dir() -> String:
	return OS.get_environment("HOME") + "/Games/PS2"

## The disc images in the games folder (one level of sub-folders too): [{path, title, stem}]
static func scan() -> Array:
	var out: Array = []
	_scan_into(games_dir(), out, 0)
	out.sort_custom(func(a, b): return str(a["title"]).naturalnocasecmp_to(str(b["title"])) < 0)
	return out

static func _scan_into(dir_path: String, out: Array, depth: int) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.get_extension().to_lower() in EXTS and not f.to_lower().begins_with("scph"):
			if f.get_extension().to_lower() == "bin" and FileAccess.get_file_as_bytes(dir_path + "/" + f).size() < 100000000:
				continue  # a small .bin is a BIOS or a memory file, not a disc
			var stem := f.get_basename()
			out.append({"path": dir_path + "/" + f, "title": clean_title(stem), "stem": stem})
	if depth < 1:
		for d in dir.get_directories():
			if d.to_lower() in ["bios", "covers", "memcards", "snaps"]:
				continue
			_scan_into(dir_path + "/" + d, out, depth + 1)

## "Gran Turismo 4 (USA) (En,Fr) [!]" -> "Gran Turismo 4"
static func clean_title(stem: String) -> String:
	var t := RegEx.create_from_string("\\s*[\\(\\[][^\\)\\]]*[\\)\\]]").sub(stem, "", true).strip_edges()
	t = t.replace("_", " ")
	return t if t != "" else stem

# ---------- Which Steam account ----------
static func _config_dir(steam_dir: String) -> String:
	var id := SteamAccount.steam_id(steam_dir)
	var acc := str(id.to_int() - 76561197960265728) if id.length() >= 16 and id.is_valid_int() else ""
	if acc == "":
		return ""
	return steam_dir + "/userdata/" + acc + "/config"

static func shortcut_id(title: String) -> int:
	return (ExtraGames.crc32("\"" + LAUNCHER + "\"" + title) | 0x80000000) & 0xFFFFFFFF

## The images from the games folder that are not in Steam's shortcuts yet.
static func missing(steam_dir: String) -> Array:
	var cfg := _config_dir(steam_dir)
	if cfg == "":
		return []
	var have := {}
	for g in ExtraGames.nonsteam_games(steam_dir):
		have[str(g["title"]).to_lower()] = true
	var out: Array = []
	for e in scan():
		if not have.has(str(e["title"]).to_lower()):
			out.append(e)
	return out

## Writes the missing games into shortcuts.vdf. Steam must NOT be running. Returns {added, error}.
static func add_to_steam(steam_dir: String, entries: Array) -> Dictionary:
	var cfg := _config_dir(steam_dir)
	if cfg == "":
		return {"added": 0, "error": "Couldn't find your Steam account."}
	DirAccess.make_dir_recursive_absolute(cfg)
	var path := cfg + "/shortcuts.vdf"
	var root := {"shortcuts": {}}
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			var parsed := ExtraGames._parse_map(bytes, 0)
			root = parsed["map"]
			if not root.has("shortcuts") or not (root["shortcuts"] is Dictionary):
				return {"added": 0, "error": "shortcuts.vdf has a layout Tephra does not know. Nothing was changed."}
			# Only touch the file if Tephra can write back exactly what it read; otherwise something in it would be lost.
			var check := PackedByteArray()
			_write_map(check, root)
			check.append(8)
			if check != bytes:
				return {"added": 0, "error": "shortcuts.vdf has parts Tephra can't copy safely. Nothing was changed. Add the PS2 games with Steam ROM Manager instead."}
			DirAccess.copy_absolute(path, path + ".tephra-backup")
	var list: Dictionary = root["shortcuts"]
	var next := 0
	for k in list:
		next = maxi(next, int(str(k)) + 1)
	var added := 0
	for e in entries:
		var title := str(e["title"])
		list[str(next)] = {
			"appid": shortcut_id(title),
			"AppName": title,
			"Exe": "\"" + LAUNCHER + "\"",
			"StartDir": "\"" + str(e["path"]).get_base_dir() + "\"",
			"icon": "",
			"ShortcutPath": "",
			"LaunchOptions": FLATPAK_ARGS + "\"" + str(e["path"]) + "\"",
			"IsHidden": 0,
			"AllowDesktopConfig": 1,
			"AllowOverlay": 1,
			"OpenVR": 0,
			"Devkit": 0,
			"DevkitGameID": "",
			"DevkitOverrideAppID": 0,
			"LastPlayTime": 0,
			"FlatpakAppID": "",
			"tags": {},
		}
		next += 1
		added += 1
	root["shortcuts"] = list
	var out := PackedByteArray()
	_write_map(out, root)
	out.append(8)  # the end of the file
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"added": 0, "error": "Couldn't write shortcuts.vdf."}
	f.store_buffer(out)
	f.close()
	return {"added": added, "error": ""}

## Shortcuts Tephra wrote with older start options get the current ones (-nogui keeps PCSX2's game list window from
## flashing up). Steam must NOT be running. Returns how many were changed.
static func update_launch_options(steam_dir: String) -> int:
	var cfg := _config_dir(steam_dir)
	var path := cfg + "/shortcuts.vdf"
	if cfg == "" or not FileAccess.file_exists(path):
		return 0
	var bytes := FileAccess.get_file_as_bytes(path)
	var root: Dictionary = ExtraGames._parse_map(bytes, 0)["map"]
	if not root.has("shortcuts") or not (root["shortcuts"] is Dictionary):
		return 0
	var check := PackedByteArray()
	_write_map(check, root)
	check.append(8)
	if check != bytes:
		return 0
	var changed := 0
	for k in root["shortcuts"]:
		var e = root["shortcuts"][k]
		if not (e is Dictionary):
			continue
		for key in e.keys():
			if str(key).to_lower() == "launchoptions":
				var lo := str(e[key])
				if (lo.begins_with("run net.pcsx2.PCSX2") or lo.begins_with("run --env=SDL_")) and not lo.begins_with(FLATPAK_ARGS):
					var at := lo.find("-- ")
					if at >= 0:
						e[key] = FLATPAK_ARGS + lo.substr(at + 3)
						changed += 1
	if changed == 0:
		return 0
	DirAccess.copy_absolute(path, path + ".tephra-backup")
	var out := PackedByteArray()
	_write_map(out, root)
	out.append(8)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return 0
	f.store_buffer(out)
	f.close()
	return changed

static func _write_map(out: PackedByteArray, m: Dictionary) -> void:
	for k in m:
		var v = m[k]
		if v is Dictionary:
			out.append(0)
			out.append_array(str(k).to_utf8_buffer())
			out.append(0)
			_write_map(out, v)
			out.append(8)
		elif v is int:
			out.append(2)
			out.append_array(str(k).to_utf8_buffer())
			out.append(0)
			var n := int(v) & 0xFFFFFFFF
			out.append(n & 0xFF)
			out.append((n >> 8) & 0xFF)
			out.append((n >> 16) & 0xFF)
			out.append((n >> 24) & 0xFF)
		else:
			out.append(1)
			out.append_array(str(k).to_utf8_buffer())
			out.append(0)
			out.append_array(str(v).to_utf8_buffer())
			out.append(0)

# ---------- Covers ----------
const THUMBS := "https://thumbnails.libretro.com/Sony%20-%20PlayStation%202/Named_Boxarts/"

## Where Steam looks for a shortcut's custom cover: userdata/<you>/config/grid/<number>p.png (the tall one).
static func cover_path(steam_dir: String, title: String) -> String:
	var cfg := _config_dir(steam_dir)
	return "" if cfg == "" else "%s/grid/%dp.png" % [cfg, shortcut_id(title)]

## The address of a game's box picture on libretro's free thumbnail server, from the disc image's own file name
## (those use the same names as the pictures, such as "Gran Turismo 4 (USA)").
static func cover_url(stem: String) -> String:
	var name := stem
	for ch in ["&", "*", "/", ":", "`", "<", ">", "?", "\\", "|", "\""]:
		name = name.replace(ch, "_")
	return THUMBS + name.uri_encode() + ".png"

## "Silent Hill 2 (USA) (En,Fr)" -> "silenthill2": lower case, no brackets, no punctuation, no leading "the"
static func norm(title: String) -> String:
	var t := RegEx.create_from_string("\\s*[\\(\\[][^\\)\\]]*[\\)\\]]").sub(title, "", true).to_lower()
	t = RegEx.create_from_string("[^a-z0-9]").sub(t.replace("&", "and"), "", true)
	return t.trim_prefix("the")

const INDEX_PATH := "user://ps2_boxart_index.json"

## The names of every box picture on libretro's server (an HTML directory page), kept for 30 days.
static func parse_index(html: String) -> Array:
	var out: Array = []
	for m in RegEx.create_from_string("href=\"([^\"]+)\\.png\"").search_all(html):
		out.append(m.get_string(1).uri_decode())
	return out

static func cached_index() -> Array:
	if FileAccess.file_exists(INDEX_PATH) and Time.get_unix_time_from_system() - FileAccess.get_modified_time(INDEX_PATH) < 30.0 * 86400.0:
		var d = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
		if d is Array:
			return d
	return []

static func save_index(names: Array) -> void:
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(names))

## The picture name that best matches a game, ignoring region, punctuation and case. USA first, then Europe, then the rest.
static func best_cover_name(index: Array, title: String, stem: String) -> String:
	var want := norm(title)
	var want2 := norm(stem)
	var best := ""
	var best_score := -1
	for n in index:
		var k := norm(str(n))
		if k != want and k != want2:
			continue
		var score := 1
		if str(n).contains("(USA"):
			score = 3
		elif str(n).contains("(Europe"):
			score = 2
		if score > best_score:
			best = str(n)
			best_score = score
	return best

const MIRROR := "https://raw.githubusercontent.com/libretro-thumbnails/Sony_-_PlayStation_2/master/Named_Boxarts/"

## Both places a box picture can come from (same names on each), the faster-to-update one first.
static func cover_urls(stem: String) -> Array:
	var u := cover_url(stem)
	return [u, MIRROR + u.get_file()]

# ---------- BIOS ----------
static func bios_dir() -> String:
	return OS.get_environment("HOME") + BIOS_DIR

static func has_bios() -> bool:
	var dir := DirAccess.open(bios_dir())
	if dir == null:
		return false
	for f in dir.get_files():
		if f.get_extension().to_lower() in ["bin", "rom0"] and FileAccess.get_file_as_bytes(bios_dir() + "/" + f).size() >= 3000000:
			return true
	return false

## Looks for a BIOS file on plugged-in drives and in ~/Games, and copies it where PCSX2 reads it. Returns its name,
## or "" if there was none to import. (The BIOS is not shipped: it has to come from your own console.)
static func import_bios() -> String:
	if has_bios():
		return ""
	var homedir := OS.get_environment("HOME")
	var places: Array = [homedir + "/Games/PS2", homedir + "/Games/PS2/bios", homedir + "/Games/bios", homedir + "/Downloads"]
	var media := DirAccess.open("/run/media/" + OS.get_environment("USER"))
	if media != null:
		for d in media.get_directories():
			var base := "/run/media/" + OS.get_environment("USER") + "/" + d
			places.append(base)
			places.append(base + "/bios")
			places.append(base + "/BIOS")
			places.append(base + "/PS2")
			places.append(base + "/PS2/bios")
	for p in places:
		var dir := DirAccess.open(p)
		if dir == null:
			continue
		for f in dir.get_files():
			var low := f.to_lower()
			if not (low.begins_with("scph") or low.contains("bios")) or low.get_extension() not in ["bin"]:
				continue
			var size := FileAccess.get_file_as_bytes(p + "/" + f).size()
			if size < 3000000 or size > 5000000:
				continue
			DirAccess.make_dir_recursive_absolute(bios_dir())
			if DirAccess.copy_absolute(p + "/" + f, bios_dir() + "/" + f) == OK:
				return f
	return ""

## A wide picture made from a tall box cover: the cover itself in the middle, over a blurred, darkened copy of it filling
## the width. Used as the wide "header" (Channels tiles) and the big backdrop (_hero) of a PS2 game.
static func wide_from_cover(cover: Image, w: int, h: int) -> Image:
	var src := cover.duplicate() as Image
	src.convert(Image.FORMAT_RGBA8)
	if w > h * 2:
		# A backdrop: the artwork itself, filling the width. The PS2 banner along the top and the title and
		# ratings along the bottom are cut off, so it reads as a wide scene, not a box.
		var top := int(src.get_height() * 0.16)
		var art := src.get_region(Rect2i(0, top, src.get_width(), int(src.get_height() * 0.5)))
		var k2 := float(w) / maxf(art.get_width(), 1.0)
		art.resize(w, maxi(int(art.get_height() * k2), h), Image.INTERPOLATE_LANCZOS)
		return art.get_region(Rect2i(0, int((art.get_height() - h) * 0.4), w, h))
	var bg := src.duplicate() as Image
	var k := float(w) / maxf(bg.get_width(), 1.0)
	bg.resize(w, maxi(int(bg.get_height() * k), h), Image.INTERPOLATE_BILINEAR)
	bg = bg.get_region(Rect2i(0, (bg.get_height() - h) / 2, w, h))
	bg.resize(maxi(w / 24, 1), maxi(h / 24, 1), Image.INTERPOLATE_BILINEAR)
	bg.resize(w, h, Image.INTERPOLATE_CUBIC)
	var shade := Image.create(w, h, false, Image.FORMAT_RGBA8)
	shade.fill(Color(0, 0, 0, 0.5))
	bg.blend_rect(shade, Rect2i(0, 0, w, h), Vector2i.ZERO)
	var fh := int(h * 0.9)
	var fw := int(src.get_width() * float(fh) / maxf(src.get_height(), 1.0))
	src.resize(maxi(fw, 1), maxi(fh, 1), Image.INTERPOLATE_LANCZOS)
	bg.blend_rect(src, Rect2i(0, 0, fw, fh), Vector2i((w - fw) / 2, (h - fh) / 2))
	return bg

## Makes the wide header (<id>.png) and backdrop (<id>_hero.png) for every PS2 game that has a cover but not those yet.
## Returns how many games got new pictures.
static func make_wide_art(steam_dir: String, redo_heroes := false) -> int:
	var cfg := _config_dir(steam_dir)
	if cfg == "":
		return 0
	if redo_heroes:  # the backdrops used to be the box on a blur: make them again from the artwork
		for e in scan():
			DirAccess.remove_absolute("%s/grid/%d_hero.png" % [cfg, shortcut_id(str(e["title"]))])
	var made := 0
	for e in scan():
		var id := shortcut_id(str(e["title"]))
		var cover := "%s/grid/%dp.png" % [cfg, id]
		var head := "%s/grid/%d.png" % [cfg, id]
		var hero := "%s/grid/%d_hero.png" % [cfg, id]
		# The backdrop made from the box (.png) is always made, even when a remake's backdrop (.jpg) was borrowed:
		# "Art: Original" shows the .png, and without it the game had no backdrop at all.
		if not FileAccess.file_exists(cover) or (FileAccess.file_exists(head) and FileAccess.file_exists(hero)):
			continue
		var img := Image.load_from_file(cover)
		if img == null or img.is_empty():
			continue
		if not FileAccess.file_exists(head):
			wide_from_cover(img, 920, 430).save_png(head)
		if not FileAccess.file_exists(hero):
			wide_from_cover(img, 1920, 620).save_png(hero)
		made += 1
	return made
