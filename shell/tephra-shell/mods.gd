extends CanvasLayer
## Tephra Mod Manager. Opened from the control center's Mods card. Fluffy Mod Manager's window is never shown:
## Tephra does the installing itself, in the same folders Fluffy uses.
##
## The games are the folders in ~/Games with a Mods folder inside (~/Games/RE3R/Mods, ~/Games/RE7/Mods...). Add a game
## makes one. Those Mods folders are the one place mods live:
##   - Adding a mod unpacks a .zip / .7z / .rar into <Game>/Mods/<name>.
##   - Switching a mod on copies its files into the game (setting aside any original it replaces); off takes them
##     out and puts the originals back. For RE Engine games a loose-file mod's entries in the .pak tables are hidden
##     too (see "RE Engine .pak tables"), and a .pak mod goes in as the next re_chunk_000.pak.patch_NNN.pak.
##   - Mods Fluffy installed earlier are read from its record (installed.ini) and shown as "On (Fluffy)".
## The game's install folder comes from Steam (matched by name), from Fluffy's own settings, or from the player
## choosing the game's .exe once. Tephra's own notes (which mods it switched on, the originals it set aside) are kept
## in ~/.local/share/tephra/mods/games/<game>/, never inside the game folders in ~/Games.

signal closed

const Themes = preload("res://themes.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const FilesBrowser = preload("res://files_browser.gd")

var BG: Color = Themes.c("bg")
var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var SELECT: Color = Themes.c("select")
const ROW_H := 84.0
const ARCHIVE_EXTS := ["zip", "7z", "rar", "tar", "gz", "xz", "zst", "bz2", "tgz"]
const MOD_ARCHIVES := ["zip", "7z", "rar"]  # archives Fluffy itself takes in a Mods folder

## The games Fluffy Mod Manager supports (from its own game list), by the name of their folder in ~/Games:
## normalized folder name -> [name shown, how it is found among the Steam games, the folder name itself].
## The second entry is a word or words the Steam title contains, or "=title" for an exact title; "" for games
## that are not on Steam (the 1996-1999 originals).
const ALIASES := {
	"re0hd": ["Resident Evil 0 HD", "=resident evil 0", "RE0HD"],
	"rehd": ["Resident Evil HD Remaster", "=resident evil", "REHD"],
	"re1": ["Resident Evil 1 (1996)", "", "RE1"],
	"re2": ["Resident Evil 2 (1998)", "", "RE2"],
	"re3": ["Resident Evil 3 (1999)", "", "RE3"],
	"re2r": ["Resident Evil 2 Remake", "=resident evil 2", "RE2R"],
	"re2rdemo": ["Resident Evil 2 Remake R.P.D. Demo", "rpd demo", "RE2R_Demo"],
	"re3r": ["Resident Evil 3 Remake", "=resident evil 3", "RE3R"],
	"re3rdemo": ["Resident Evil 3 Remake Demo", "raccoon city demo", "RE3R_Demo"],
	"re4": ["Resident Evil 4 HD", "resident evil 4 2005", "RE4"],
	"re4r": ["Resident Evil 4 Remake", "=resident evil 4", "RE4R"],
	"re4rdemo": ["Resident Evil 4 Remake Chainsaw Demo", "chainsaw demo", "RE4R_Demo"],
	"re5": ["Resident Evil 5", "resident evil 5", "RE5"],
	"re6": ["Resident Evil 6", "resident evil 6", "RE6"],
	"re7": ["Resident Evil 7 Biohazard", "=resident evil 7 biohazard", "RE7"],
	"re7demo": ["Resident Evil 7 Teaser: Beginning Hour", "beginning hour", "RE7_Demo"],
	"re8": ["Resident Evil 8 Village", "=resident evil village", "RE8"],
	"re8demo": ["Resident Evil 8 Village Demo", "village gameplay demo", "RE8_Demo"],
	"re9": ["Resident Evil 9 Requiem", "=resident evil requiem", "RE9"],
	"re9demo": ["Resident Evil 9 Requiem Demo", "requiem demo", "RE9_Demo"],
	"rev": ["Resident Evil Revelations", "=resident evil revelations", "REV"],
	"rev2": ["Resident Evil Revelations 2", "revelations 2", "REV2"],
	"resistance": ["Resident Evil Resistance", "resident evil resistance", "Resistance"],
	"reverse": ["Resident Evil Re:Verse", "re verse", "ReVerse"],
	"dmc123": ["Devil May Cry HD Collection", "devil may cry hd collection", "DMC123"],
	"dmc4": ["Devil May Cry 4", "=devil may cry 4", "DMC4"],
	"dmc4se": ["Devil May Cry 4 Special Edition", "devil may cry 4 special edition", "DMC4SE"],
	"dmc5": ["Devil May Cry 5", "devil may cry 5", "DMC5"],
	"dmc": ["DmC Devil May Cry", "dmc devil may cry", "DmC"],
	"ddda": ["Dragon's Dogma: Dark Arisen", "dark arisen", "DDDA"],
	"dragonsdogma2": ["Dragon's Dogma 2", "=dragons dogma 2", "DragonsDogma2"],
	"dragonsdogma2chara": ["Dragon's Dogma 2: Character Creator", "dogma 2 character creator", "DragonsDogma2_Chara"],
	"mhw": ["Monster Hunter World", "monster hunter world", "MHW"],
	"mhrise": ["Monster Hunter Rise", "=monster hunter rise", "MHRISE"],
	"mhrisedemo": ["Monster Hunter Rise Demo", "monster hunter rise demo", "MHRISE_Demo"],
	"mhwilds": ["Monster Hunter Wilds", "=monster hunter wilds", "mhwilds"],
	"mhwildsbench": ["Monster Hunter Wilds Benchmark", "monster hunter wilds benchmark", "mhwildsbench"],
	"mhstories3": ["Monster Hunter Stories 3", "=monster hunter stories 3", "mhstories3"],
	"sf5": ["Street Fighter V", "=street fighter v", "SF5"],
	"sf6": ["Street Fighter 6", "=street fighter 6", "SF6"],
	"sf6demo": ["Street Fighter 6 Demo", "street fighter 6 demo", "SF6_Demo"],
	"onimusha2": ["Onimusha 2: Samurai's Destiny", "onimusha 2", "Onimusha2"],
	"onimushawots": ["Onimusha: Way of the Sword", "=onimusha way of the sword", "OnimushaWotS"],
	"onimushawotsdemo": ["Onimusha: Way of the Sword Demo", "way of the sword demo", "OnimushaWotS_Demo"],
	"pragmata": ["Pragmata", "=pragmata", "PRAGMATA"],
	"pragmatademo": ["Pragmata Demo", "pragmata demo", "PRAGMATA_Demo"],
}

var is_open := false
var _home

var _root: Control
var _title: Label
var _sub: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _msg: Label
var _hints: HBoxContainer
var _poll: Timer

var _mode := "games"           # "games" | "mods" | "add" | "pick" | "name"
var _rows: Array = []          # [{"key", "text", "value", "data", "panel"}]
var _sel := 0
var _game: Dictionary = {}     # {"dir", "key", "title", "install", "exe", "appid"}
var _busy := false
var _importing := false       # an import is running on its worker thread (it can be cancelled with Back)
var _import_token := 0
var _import_cancelled := -1   # the token of an import that was cancelled: its result is thrown away
var _task := -1
var _status_task := -1
var _snap_note := ""  # what the clean-copy check found, shown once on the Mods page
var _status: Dictionary = {}   # mod name -> "on" | "fluffy" | "off" (read from the game folder)
var _delete_armed := ""
var _pick_path := ""
var _pick_mod := false         # the picker is choosing a mod (any file or folder), not the game's .exe
var _delete_until := 0
var _scroll_tween: Tween
var _reported := false
var _direct := false           # opened on one game from its page: Back leaves the mod manager
var _adding_game := false      # the picker is choosing the .exe of a game that is not in the Add a game list

func setup(home) -> void:
	_home = home

static func root_dir() -> String:
	return OS.get_environment("HOME") + "/.local/share/tephra/mods"

## Keeps the REFramework menu closed in every game that has one: before a launch, each "*_fw_config.txt" in a Steam game
## folder, or in a game folder the Mods page knows, gets MenuOpen=0 and RememberMenuState=1 (a line that is missing is
## added). The file is rewritten only when something differs. The key names are from memory, not checked on a real config.
static func quiet_reframework(libs: Array) -> void:
	var dirs: Array = []
	for lib in libs:
		var common: String = str(lib) + "/steamapps/common"
		for d in DirAccess.get_directories_at(common):
			dirs.append(common + "/" + d)
	var gdir := root_dir() + "/games"
	for k in (DirAccess.get_directories_at(gdir) if DirAccess.dir_exists_absolute(gdir) else PackedStringArray()):
		var conf: Dictionary = _read_json(gdir + "/" + k + "/game.json", {})
		var inst := str(conf.get("install", ""))
		if inst != "" and not dirs.has(inst):
			dirs.append(inst)
	for dir in dirs:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with("_fw_config.txt"):
				continue
			var path: String = dir + "/" + f
			var txt := FileAccess.get_file_as_string(path)
			var out := txt
			for pair in [["MenuOpen", "0"], ["RememberMenuState", "1"]]:
				var re := RegEx.create_from_string("(?m)^" + pair[0] + "=[^\\r\\n]*")
				if re.search(out) != null:
					out = re.sub(out, pair[0] + "=" + pair[1])
				else:
					out += ("" if out.ends_with("\n") or out == "" else "\n") + pair[0] + "=" + pair[1] + "\n"
			if out != txt:
				var fa := FileAccess.open(path, FileAccess.WRITE)
				if fa != null:
					fa.store_string(out)

static func games_root() -> String:
	return OS.get_environment("HOME") + "/Games"

static func fmm_dir() -> String:
	return games_root() + "/fmm"

## Tephra's notes about a game (game.json, state.json, backup/).
func _gdir() -> String:
	return root_dir() + "/games/" + str(_game["key"])

func _mods_dir() -> String:
	return str(_game["mods"])

static func _norm(t: String) -> String:
	var out := ""
	for c in t.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out

## "Resident Evil 3" -> "re3" (Fluffy's short folder names).
static func _acronym(t: String) -> String:
	var out := ""
	for w in t.split(" ", false):
		var n := _norm(w)
		if n == "":
			continue
		out += n if n.is_valid_int() else n.left(1)
	return out

## Runs a shell script with its own arguments. (When its output is read, Godot hands the command to a shell as one
## line, which would mangle a script passed with -c, so the script goes through a file.)
static func _run_sh(script: String, args: Array, output: Array) -> int:
	var dir := OS.get_environment("HOME") + "/.cache/tephra"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("mods-%s.sh" % script.md5_text().substr(0, 10))
	if not FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return -1
		f.store_string(script)
		f.close()
	return OS.execute("sh", [path] + args, output)

static func _read_json(path: String, fallback):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fallback
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == typeof(fallback) else fallback

static func _write_json(path: String, data) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))

func _ready() -> void:
	layer = 82  # above the Album (81)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BG
	_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var anim = preload("res://tephra_bg.gd").new()
	anim.set("plain", true)
	_root.add_child(anim)
	anim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	margin.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	v.add_child(head)
	_title = _label("Mods", 44, TEXT)
	head.add_child(_title)
	_sub = _label("", 26, MUTED)
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_sub)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	v.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	pad.add_child(_list)

	_msg = _label("", 24, MUTED)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_msg)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(_hints)

	# While a game's mods are shown they are checked again now and then, so a change made in Fluffy shows up.
	_poll = Timer.new()
	_poll.wait_time = 4.0
	_poll.timeout.connect(func() -> void:
		if is_open and _mode == "mods" and not _busy and _game.get("install", "") != "":
			_refresh_status())
	add_child(_poll)

func _exit_tree() -> void:
	for t in [_task, _status_task]:
		if t != -1:
			WorkerThreadPool.wait_for_task_completion(t)

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

# ---------- Open / close ----------
func open() -> void:
	if is_open:
		return
	_direct = false
	is_open = true
	_busy = false
	_root.visible = true
	_root.modulate.a = 0.0
	Motion.fade_to(_root, 1.0, 0.2)
	_cleanup_old_folders()
	_show_games()
	_poll.start()
	if not _reported:
		_reported = true
		_write_fluffy_report()

## Opens straight on one game's mods (the Mods button on a game's page). g is a Steam game from Home: its id and title.
## A game in ~/Games that Fluffy knows is used as it is; for any other, its folder is made there first.
func open_for(g: Dictionary) -> void:
	if is_open:
		return
	open()
	var id := str(g["id"])
	var found: Dictionary = {}
	for x in _scan_games():
		if str(x["appid"]) == id:
			found = x
			break
	var exe := str(g.get("exe", ""))
	if found.is_empty():
		# Fluffy's short names win over anything made up from the title: RE7, RE3R... An existing ~/Games folder is
		# used first, then a name Fluffy knows. "re3" is looked up as RE3R first, because it is the remake that is installed.
		var cands: Array = []
		for t in [exe.get_file().get_basename(), str(g.get("title", "")), str(g.get("orig_title", ""))]:
			if str(t) == "":
				continue
			for c in [_norm(str(t)), _acronym(str(t))]:
				if c != "" and not cands.has(c):
					cands.append(c)
		var want: Array = []
		for c in cands:
			want.append(c + "r")
		want.append_array(cands)
		for w in want:
			for x in _scan_games():
				if _norm(str(x["dir"]).get_file()) == w:
					found = x
					break
			if not found.is_empty():
				break
		if found.is_empty():
			for w in want:
				if ALIASES.has(w):
					if _name_chosen(str(ALIASES[w][2])):
						if exe != "":
							_exe_chosen(exe)
						_direct = true
					return
	if found.is_empty() and bool(g.get("nonsteam", false)) and exe != "":
		_other_game_chosen(exe)
		_direct = true
		return
	if found.is_empty():
		var folder := ""
		for k in ALIASES:
			var a: Array = ALIASES[k]
			var steam := _match_steam(str(k), a)
			if not steam.is_empty() and str(steam["id"]) == id:
				folder = str(a[2])
				break
		if folder == "":
			for c in str(g["title"]).strip_edges():
				if not c in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
					folder += c
		if folder == "" or folder == "." or folder == "..":
			folder = id
		if not _name_chosen(folder):
			return
		_direct = true
		return
	_game = found
	_status = {}
	_msg.text = ""
	_show_mods()
	_direct = true

func close() -> void:
	if not is_open:
		return
	is_open = false
	_poll.stop()
	closed.emit()
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, Motion.dur(0.2))
	await t.finished
	if not is_open:
		_root.visible = false

# ---------- Fluffy's games ----------
## Every folder in ~/Games (and in Fluffy's own Games folder) that has a Mods folder inside is a game.
func _scan_games() -> Array:
	var out: Array = []
	var seen := {}
	for base in [games_root(), fmm_dir() + "/Games"]:
		var d := DirAccess.open(base)
		if d == null:
			continue
		var names := Array(d.get_directories())
		names.sort_custom(func(a, b): return str(a).to_lower() < str(b).to_lower())
		for n in names:
			var name := str(n)
			if name.begins_with(".") or name == "PS2" or name.to_lower() == "fmm":
				continue
			var dir: String = base + "/" + name
			var mods := ""
			for m in ["Mods", "mods"]:
				if DirAccess.dir_exists_absolute(dir + "/" + m):
					mods = dir + "/" + m
					break
			if mods == "" or seen.has(_norm(name)):
				continue
			if base != games_root() and _mod_entries(mods).is_empty() and not DirAccess.dir_exists_absolute(dir + "/Logo"):
				continue  # an empty game folder in Fluffy's own Games folder: not one that is used
			seen[_norm(name)] = true
			out.append(_resolve_game(dir, mods))
	return out

## Works out the game's name and where it is installed.
func _resolve_game(dir: String, mods: String) -> Dictionary:
	var folder := dir.get_file()
	var key := _norm(folder) + "_" + dir.md5_text().substr(0, 6)
	var g := {"dir": dir, "mods": mods, "key": key, "title": folder, "install": "", "exe": "", "appid": "", "how": ""}
	var alias: Array = ALIASES.get(_norm(folder), [])
	if not alias.is_empty():
		g["title"] = alias[0]
	var steam := _match_steam(folder, alias)
	if not steam.is_empty():
		g["title"] = str(steam["title"])
		g["appid"] = str(steam["id"])
	var conf: Dictionary = _read_json(root_dir() + "/games/" + key + "/game.json", {})
	if str(conf.get("install", "")) != "" and DirAccess.dir_exists_absolute(str(conf["install"])):
		g["install"] = str(conf["install"])
		g["exe"] = str(conf.get("exe", ""))
		g["how"] = "chosen"
	elif g["appid"] != "":
		var inst := _install_dir(str(g["appid"]))
		if inst != "":
			g["install"] = inst
			g["exe"] = _main_exe(inst)
			g["how"] = "steam"
	if g["install"] == "":
		var exe := _fluffy_exe_for(folder, str(g["title"]))
		if exe != "":
			g["install"] = exe.get_base_dir()
			g["exe"] = exe
			g["how"] = "fluffy"
	return g

## The Steam game a Fluffy folder belongs to: by its short name ("RE3R" -> "Resident Evil 3"), else by name.
func _match_steam(folder: String, alias: Array) -> Dictionary:
	if _home == null:
		return {}
	var fn := _norm(folder)
	var best := {}
	for gm in _home.games:
		var id := str(gm["id"])
		if not id.is_valid_int() or int(id) > 0x7FFFFFFF:
			continue  # Steam games only
		var tn := _norm(str(gm["title"]))
		var hit := false
		if alias.size() > 1:
			# A game Fluffy knows is found by its own words only ("" = not a Steam game).
			var w := str(alias[1])
			if w != "":
				hit = (tn == _norm(w.substr(1))) if w.begins_with("=") else tn.contains(_norm(w))
		else:
			hit = tn == fn or _acronym(str(gm["title"])) == fn or _acronym(str(gm["title"])) + "r" == fn
		if hit and (best.is_empty() or tn.length() < _norm(str(best["title"])).length()):
			best = gm  # the shortest name wins: "Resident Evil 3" over "Resident Evil 3: Raccoon City Demo"
	return best

## Where a Steam game lives on disk: steamapps/common/<installdir> from its manifest.
func _install_dir(id: String) -> String:
	if _home == null:
		return ""
	var steam: String = _home.steam_dir
	var libs: Array = [steam]
	var re_path := RegEx.new()
	re_path.compile("\"path\"\\s+\"([^\"]+)\"")
	for m in re_path.search_all(FileAccess.get_file_as_string(steam + "/steamapps/libraryfolders.vdf")):
		if not libs.has(m.get_string(1)):
			libs.append(m.get_string(1))
	var re_dir := RegEx.new()
	re_dir.compile("\"installdir\"\\s+\"([^\"]+)\"")
	for lib in libs:
		var mp: String = lib + "/steamapps/appmanifest_" + id + ".acf"
		if not FileAccess.file_exists(mp):
			continue
		var m := re_dir.search(FileAccess.get_file_as_string(mp))
		if m == null:
			return ""
		var folder: String = m.get_string(1)
		if folder == "" or folder.contains("/") or folder.contains(".."):
			return ""
		var dir: String = lib + "/steamapps/common/" + folder
		return dir if DirAccess.dir_exists_absolute(dir) else ""
	return ""

## The game's own .exe in its folder: the biggest one that is not a helper (crash reporter, uninstaller...).
static func _main_exe(dir: String) -> String:
	var best := ""
	var best_size := -1
	for f in DirAccess.get_files_at(dir):
		var low := str(f).to_lower()
		if low.get_extension() != "exe":
			continue
		var skip := false
		for bad in ["crash", "unins", "setup", "redist", "vc_", "dxsetup", "report", "launcher", "helper", "dotnet"]:
			if low.contains(bad):
				skip = true
		if skip:
			continue
		var fa := FileAccess.open(dir + "/" + str(f), FileAccess.READ)
		var size := fa.get_length() if fa != null else 0
		if size > best_size:
			best_size = size
			best = dir + "/" + str(f)
	return best

## Game .exe paths written in Fluffy's settings files (as Z:\home\...\game.exe), read once per opening.
var _fluffy_exes_cache: Array = []
var _fluffy_exes_read := false

func _fluffy_exes() -> Array:
	if _fluffy_exes_read:
		return _fluffy_exes_cache
	_fluffy_exes_read = true
	var out: Array = []
	var got := []
	# Settings files can be saved as UTF-16 (every other byte 0): the zero bytes are dropped before looking.
	var sh := "find \"$1\" -maxdepth 4 -type f -size -4M \\( -iname '*.ini' -o -iname '*.xml' -o -iname '*.cfg' -o -iname '*.json' -o -iname '*.txt' -o -iname '*.bin' -o -iname '*.dat' \\) -not -path '*/Mods/*' -not -path '*/TmpDownload/*' -print0 2>/dev/null | head -z -n 200 | xargs -0 -r cat 2>/dev/null | tr -d '\\000' | grep -a -o -i -E '[a-z]:[\\\\/][^\"<>|*?[:cntrl:]]{1,300}\\.exe' | sort -u | head -100"
	_run_sh(sh, [fmm_dir()], got)
	for line in str(got[0] if got.size() > 0 else "").split("\n", false):
		var l := str(line).strip_edges()
		if l.length() < 4 or l.left(1).to_lower() != "z":
			continue  # only Z: is the Linux file system under Wine
		var p := "/" + l.substr(2).replace("\\", "/").simplify_path().lstrip("/")
		if FileAccess.file_exists(p) and not out.has(p):
			out.append(p)
	_fluffy_exes_cache = out
	return out

func _fluffy_exe_for(folder: String, title: String) -> String:
	var keys := {_norm(folder): true, _norm(folder).trim_suffix("r"): true, _norm(title): true, _acronym(title): true}
	keys.erase("")
	for p in _fluffy_exes():
		var exe := str(p)
		if keys.has(_norm(exe.get_file().get_basename())) or keys.has(_norm(exe.get_base_dir().get_file())) or keys.has(_acronym(exe.get_base_dir().get_file())):
			return exe
	return ""

## Folders the previous Tephra version made in Fluffy's Games folder are removed again while they are empty.
func _cleanup_old_folders() -> void:
	var mp := root_dir() + "/fmm_map.json"
	var map: Dictionary = _read_json(mp, {})
	if map.is_empty():
		return
	for id in map:
		var d := fmm_dir() + "/Games/" + str(map[id])
		if str(map[id]) == "" or not DirAccess.dir_exists_absolute(d):
			continue
		var st: Dictionary = _read_json(d + "/Tephra/state.json", {})
		if st.get("enabled", {}) is Dictionary and (st.get("enabled", {}) as Dictionary).is_empty():
			DirAccess.remove_absolute(d + "/Tephra/state.json")
		for sub in ["Tephra/backup", "Tephra", "Mods", "Presets"]:
			DirAccess.remove_absolute(d + "/" + sub)  # only removed when empty
		DirAccess.remove_absolute(d)
	DirAccess.remove_absolute(mp)

# ---------- Reading what is on disk ----------
func _state() -> Dictionary:
	var d: Dictionary = _read_json(_gdir() + "/state.json", {})
	if typeof(d.get("enabled")) != TYPE_DICTIONARY:
		return {"enabled": {}}
	return d

func _save_state(st: Dictionary) -> void:
	_write_json(_gdir() + "/state.json", st)

## The mods in a Mods folder: its folders and the archives dropped straight in (Fluffy takes both).
static func _mod_entries(mods_dir: String) -> Array:
	var out: Array = []
	if mods_dir == "":
		return out
	var d := DirAccess.open(mods_dir)
	if d != null:
		for n in d.get_directories():
			if not n.begins_with("."):
				out.append(n)
		for n in d.get_files():
			if not n.begins_with(".") and n.get_extension().to_lower() in MOD_ARCHIVES:
				out.append(n)
	out.sort_custom(func(a, b): return a.to_lower() < b.to_lower())
	return out

## Files in a mod that are about the mod (Fluffy's modinfo.ini, its picture, a readme), not for the game.
static func _is_meta(rel: String) -> bool:
	var low := rel.to_lower()
	if low.get_file() == "modinfo.ini":
		return true
	if low.contains("natives/") or low.contains("reframework/"):
		return false
	return low.get_extension() in ["png", "jpg", "jpeg", "webp", "bmp", "gif", "txt", "md", "url", "nfo", "pdf", "rtf", "htm", "html"]

## A mod's game files with their sizes: [[relative path, bytes], ...] (from a folder, or listed inside an archive).
static func _mod_files(path: String) -> Array:
	var out: Array = []
	if DirAccess.dir_exists_absolute(path):
		for rel in _list_files(path):
			if _is_meta(str(rel)):
				continue
			var fa := FileAccess.open(path.path_join(str(rel)), FileAccess.READ)
			out.append([str(rel), fa.get_length() if fa != null else -1])
		return out
	var lines := []
	if OS.execute("7z", ["l", "-slt", "--", path], lines) != 0:
		return _mod_files_plain(path)
	var after := false
	var cur := {}
	for line in (str(lines[0]) + "\n\n").split("\n"):
		var l := str(line).strip_edges()
		if l.begins_with("----------"):
			after = true
			continue
		if not after:
			continue
		if l == "":
			if cur.has("Path") and str(cur.get("Folder", "-")) != "+" and not str(cur.get("Attributes", "")).begins_with("D"):
				var rel := str(cur["Path"]).replace("\\", "/")
				if not _is_meta(rel):
					out.append([rel, int(cur.get("Size", "-1"))])
			cur = {}
			continue
		var eq := l.find(" = ")
		if eq > 0:
			cur[l.left(eq)] = l.substr(eq + 3)
	return out

## Without 7-Zip: bsdtar (always there on Arch) or unzip lists the archive as "size ... name" lines.
static func _mod_files_plain(path: String) -> Array:
	var out: Array = []
	var lines := []
	if OS.execute("bsdtar", ["-tvf", path], lines) == 0:
		for line in str(lines[0]).split("\n", false):
			var f := str(line).split(" ", false, 8)
			if f.size() >= 9 and not str(f[0]).begins_with("d"):
				var rel := str(f[8]).replace("\\", "/")
				if not _is_meta(rel) and not rel.ends_with("/"):
					out.append([rel, int(f[4])])
		return out
	lines = []
	if path.get_extension().to_lower() == "zip" and OS.execute("unzip", ["-l", "--", path], lines) == 0:
		for line in str(lines[0]).split("\n", false):
			var f := str(line).strip_edges().split(" ", false, 3)
			if f.size() == 4 and str(f[0]).is_valid_int() and str(f[1]).contains("-"):
				var rel := str(f[3])
				if not _is_meta(rel) and not rel.ends_with("/"):
					out.append([rel, int(f[0])])
	return out

## RE Engine games load extra .pak files named re_chunk_000.pak.patch_NNN.pak: their numbers -> sizes.
static func _patch_paks(install: String) -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("^re_chunk_000\\.pak\\.patch_(\\d+)\\.pak$")
	for f in DirAccess.get_files_at(install):
		var m := re.search(str(f).to_lower())
		if m != null:
			var fa := FileAccess.open(install + "/" + str(f), FileAccess.READ)
			out[int(m.get_string(1))] = fa.get_length() if fa != null else -1
	return out

## True when the file is in the game: at its own place (or with a wrapper folder or two taken off the front), or
## for a .pak, as one of the patch paks with the same size.
static func _present(install: String, rel: String, size: int, pak_sizes: Dictionary) -> bool:
	if rel.get_extension().to_lower() == "pak" and pak_sizes.has(size):
		return true
	var parts := rel.split("/", false)
	for k in mini(3, parts.size()):
		var p := install.path_join("/".join(parts.slice(k)))
		var fa := FileAccess.open(p, FileAccess.READ)
		if fa != null and (size < 0 or fa.get_length() == size):
			return true
	return false

## One "known good" copy of each game's .pak table bytes (header + entry table, a few MB), taken only while the game is
## clean: no Fluffy mods recorded, no mods of Tephra's on, no loose natives folder. It is taken once per game version
## (the .pak sizes are the version: when they change the old copy is dropped), checked with a checksum before any use,
## and never added to. Returns a short note for the Mods page, or "" when there is nothing to say.
static func _snapshot_job(gdir: String, game_dir: String, data: String, tephra_on: Dictionary) -> String:
	var sizes := {}
	for pak in _game_paks(gdir, []):
		var fa := FileAccess.open(pak, FileAccess.READ)
		if fa != null:
			sizes[pak.trim_prefix(gdir)] = fa.get_length()
	if sizes.is_empty():
		return ""
	var dir := data + "/snapshot"
	var meta_path := dir + "/snapshot.json"
	var meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path)) if FileAccess.file_exists(meta_path) else null
	if meta is Dictionary:
		var same: bool = (meta.get("sizes", {}) as Dictionary).size() == sizes.size()
		for k in sizes:
			if int((meta.get("sizes", {}) as Dictionary).get(k, -1)) != int(sizes[k]):
				same = false
		if same:
			return ""  # already have the good copy of this game version
		OS.execute("rm", ["-rf", "--", dir])  # the game was updated: the old copy no longer fits
	elif DirAccess.dir_exists_absolute(dir):
		OS.execute("rm", ["-rf", "--", dir])  # half-written earlier: start over
	var modded: bool = not tephra_on.is_empty() or not (_fluffy_installed(game_dir)["mods"] as Dictionary).is_empty()
	if not modded and DirAccess.dir_exists_absolute(gdir + "/natives"):
		modded = not _list_files(gdir + "/natives").is_empty()
	if modded:
		return "Mods are installed, so Tephra hasn't saved a clean copy of the game's tables yet. Remove all mods (or verify the game in Steam) and open this page again."
	DirAccess.make_dir_recursive_absolute(dir)
	var sums := {}
	for pak in _game_paks(gdir, []):
		var lay := _pak_layout(pak)
		if lay.is_empty() or lay.get("locked", false):
			continue
		var f := FileAccess.open(pak, FileAccess.READ)
		var tbl := f.get_buffer(16 + int(lay["count"]) * int(lay["entry"]))
		f.close()
		var rel: String = pak.trim_prefix(gdir).trim_prefix("/").replace("/", "__") + ".tbl"
		var out := FileAccess.open(dir + "/" + rel, FileAccess.WRITE)
		if out == null:
			OS.execute("rm", ["-rf", "--", dir])
			return ""
		out.store_buffer(tbl)
		out.close()
		sums[rel] = FileAccess.get_sha256(dir + "/" + rel)
	var mf := FileAccess.open(meta_path, FileAccess.WRITE)  # written last: no file means no (complete) snapshot
	if mf == null:
		OS.execute("rm", ["-rf", "--", dir])
		return ""
	mf.store_string(JSON.stringify({"sizes": sizes, "sums": sums}))
	mf.close()
	return "Saved a clean copy of this game's .pak tables."

## Worker thread: which mods are in the game right now.
## When Fluffy keeps a record (installed.ini) it decides which mods Fluffy installed; otherwise the files are compared.
static func _status_job(mods_dir: String, install: String, names: Array, tephra_on: Dictionary, fluffy: Dictionary = {}) -> Dictionary:
	var out := {}
	var record: bool = bool(fluffy.get("found", false))
	var fluffy_on: Dictionary = fluffy.get("mods", {})
	var paks := _patch_paks(install)
	var pak_sizes := {}
	for n in paks:
		pak_sizes[paks[n]] = true
	for name in names:
		var n := str(name)
		var bare := n.get_basename() if n.get_extension().to_lower() in MOD_ARCHIVES else n
		if record and not tephra_on.has(name):
			out[name] = "fluffy" if fluffy_on.has(bare) else "off"
			continue
		var files := _mod_files(mods_dir.path_join(str(name)))
		var on := not files.is_empty()
		# Files another switched-on mod was put over (the hold-to-override) belong to that one now: they can't count against this mod.
		var taken := {}
		if tephra_on.has(name):
			for other in tephra_on:
				if other != name:
					for rel in tephra_on[other]:
						taken[str(rel)] = true
		var checked := 0
		for f in files:
			if taken.has(str(f[0])) and str(f[0]).get_extension().to_lower() != "pak":
				continue
			checked += 1
			if not _present(install, str(f[0]), int(f[1]), pak_sizes):
				on = false
				break
		if checked == 0 and tephra_on.has(name):
			on = true  # every file of it was overridden by another mod: it is still switched on, just under it
		out[name] = ("on" if tephra_on.has(name) else "fluffy") if on else "off"
	return out

func _refresh_status() -> void:
	if _status_task != -1 or _game.is_empty() or str(_game.get("install", "")) == "":
		return
	var mods_dir := _mods_dir()
	var install := str(_game["install"])
	var names := _mod_entries(mods_dir)
	var tephra_on: Dictionary = _state()["enabled"].duplicate()
	var key := str(_game["key"])
	var game_dir := str(_game["dir"])
	var data_dir := _gdir()
	_status_task = WorkerThreadPool.add_task(func() -> void:
		var res := _status_job(mods_dir, install, names, tephra_on, _fluffy_installed(game_dir))
		_snap_note = _snapshot_job(install, game_dir, data_dir, tephra_on)
		_status_done.call_deferred(res, key, names))

func _status_done(res: Dictionary, key: String, names: Array) -> void:
	WorkerThreadPool.wait_for_task_completion(_status_task)
	_status_task = -1
	if not is_open or _mode != "mods" or str(_game.get("key", "")) != key or _busy:
		return
	# A mod Tephra switched on that is no longer in the game (Fluffy or a game update took it out) is forgotten.
	var st := _state()
	var changed := false
	for n in st["enabled"].keys():
		if res.get(n, "off") == "off" and names.has(n):
			st["enabled"].erase(n)
			changed = true
	if changed:
		_save_state(st)
	var shown: Array = []
	for r in _rows:
		if r["key"] == "mod":
			shown.append(str(r["data"]["name"]))
	_status = res
	if _snap_note != "":
		_msg.text = _snap_note
		_snap_note = ""
	if shown != names:
		var keep := str(_rows[_sel]["data"].get("name", "")) if _sel < _rows.size() else ""
		_show_mods(keep, false)
		return
	for r in _rows:
		if r["key"] == "mod":
			r["value"] = str(res.get(str(r["data"]["name"]), "off"))
			_style_value(r)
	_refresh_hints()

# ---------- Fluffy ----------
## A plain report of Fluffy's folders (what is where, sizes, settings files), so Fluffy's own record of which mods
## are on can be matched exactly later. Written in the background to ~/.config/tephra/fluffy-report.txt.
func _write_fluffy_report() -> void:
	if not DirAccess.dir_exists_absolute(fmm_dir()):
		return
	var out := OS.get_environment("HOME") + "/.config/tephra/fluffy-report.txt"
	var installs: Array = []
	for g in _scan_games():
		installs.append(str(g["dir"]))
		installs.append(str(g["install"]) if str(g["install"]) != "" else "-")
	var sh := """
F="$1"; O="$2"; shift 2
mkdir -p "$(dirname "$O")"
{
echo "Tephra Fluffy report $(date)"
echo "== Fluffy folder"
find "$F" -maxdepth 3 -not -path '*/TmpDownload/*' -printf '%y %12s %TY-%Tm-%Td %TH:%TM %p\\n' 2>/dev/null | head -500
while [ $# -ge 2 ]; do
  D="$1"; I="$2"; shift 2
  echo; echo "== Game folder $D"
  find "$D" -maxdepth 3 -printf '%y %12s %TY-%Tm-%Td %TH:%TM %p\\n' 2>/dev/null | head -400
  if [ "$I" != "-" ]; then
    echo "-- install $I"
    ls -la --time-style=long-iso "$I" 2>/dev/null | head -80
  fi
  for B in "$D"/*.bin; do [ -f "$B" ] || continue
    echo "-- $B (first bytes)"; head -c 768 "$B" | od -A x -t x1z | head -50
    echo "-- $B (text in it)"; grep -a -o '[[:print:]]\\{5,\\}' "$B" | head -120
  done
done
echo; echo "== Settings files"
find "$F" -maxdepth 4 -type f -size -256k \\( -iname '*.ini' -o -iname '*.xml' -o -iname '*.cfg' -o -iname '*.json' -o -iname '*.txt' \\) -not -path '*/Mods/*' -not -path '*/TmpDownload/*' -not -path '*/Legalese/*' 2>/dev/null | head -60 | while read -r f; do
  echo "--- $f"; head -c 6000 "$f" | tr -d '\\000'; echo
done
find "$F" -maxdepth 4 -type f -iname '*.bin' -size -4M -not -path '*/Mods/*' 2>/dev/null | head -20 | while read -r f; do
  echo "--- $f (first bytes)"; head -c 512 "$f" | od -A x -t x1z | head -34
  echo "--- $f (text in it)"; grep -a -o '[[:print:]]\\{5,\\}' "$f" | head -80
done
} > "$O" 2>&1
"""
	OS.create_process("sh", ["-c", sh, "sh", fmm_dir(), out] + installs)

# ---------- The lists ----------
func _show_games() -> void:
	_pick_mod = false
	_mode = "games"
	_title.text = "Mods"
	_sub.text = "Choose a game"
	_fluffy_exes_read = false
	var list: Array = []
	for g in _scan_games():
		var n := _mod_entries(str(g["mods"])).size()
		var val := ("%d mod%s" % [n, "" if n == 1 else "s"]) if n > 0 else "No mods yet"
		if str(g["install"]) == "":
			val = "Choose its .exe"
		list.append({"key": "game", "text": str(g["title"]), "value": val, "data": g})
	list.append({"key": "addgame", "text": "Add a game...", "value": "", "data": {}})
	_set_rows(list, 0)
	if list.size() == 1:
		_msg.text = "No games yet. Choose Add a game: Tephra makes its folder in %s with a Mods folder inside." % games_root()
	else:
		_msg.text = ""
	_refresh_hints()

func _show_mods(keep := "", recheck := true) -> void:
	_pick_mod = false
	_mode = "mods"
	_title.text = "Mods"
	_sub.text = "%s · %s" % [str(_game["title"]), _mods_dir().replace(OS.get_environment("HOME"), "~")]
	if str(_game["install"]) == "":
		_set_rows([{"key": "findexe", "text": "Choose %s's .exe..." % str(_game["title"]), "value": "", "data": {}}], 0)
		_msg.text = "Tephra needs to know where the game is installed before mods can be added. Find the game's folder and choose its .exe."
		_refresh_hints()
		return
	var list: Array = [{"key": "add", "text": "Add mods...", "value": "", "data": {}}, {"key": "nexus", "text": "Get mods from Nexus Mods", "value": "", "data": {}}]
	for n in _mod_entries(_mods_dir()):
		list.append({"key": "mod", "text": n.get_basename() if n.get_extension().to_lower() in MOD_ARCHIVES else n, "value": str(_status.get(n, "wait")), "data": {"name": n}})
	list.append({"key": "findexe", "text": "Change where the game is installed...", "value": str(_game["install"]).get_file(), "data": {}})
	var sel := 0
	for i in list.size():
		if keep != "" and list[i]["data"].get("name", "") == keep:
			sel = i
	if keep == "" and list.size() > 3:
		sel = 2
	_set_rows(list, sel)
	if list.size() <= 3:
		_msg.text = "No mods yet. Choose Add mods to pick a .zip, .7z or .rar."
	elif _msg.text == "" or recheck:
		_msg.text = "Installed in %s" % str(_game["install"]) if str(_game["how"]) != "" else ""
	_refresh_hints()
	if recheck:
		_refresh_status()

func _show_add() -> void:
	_mode = "add"
	_sub.text = "Add a mod to %s" % str(_game["title"])
	var found: Array = []
	for dir in [OS.get_environment("HOME") + "/Downloads", root_dir() + "/inbox"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.get_extension().to_lower() in ARCHIVE_EXTS:
				var p: String = dir + "/" + f
				found.append({"key": "archive", "text": f, "value": _size_text(p), "data": {"path": p}, "time": FileAccess.get_modified_time(p)})
	found.sort_custom(func(a, b): return a["time"] > b["time"])
	found.append({"key": "browse", "text": "All files...", "value": "Pick anything, anywhere", "data": {}, "time": 0})
	_set_rows(found, 0)
	_msg.text = "" if found.size() > 1 else "No archives in Downloads. Use All files to look anywhere."
	_refresh_hints()

## The picker: folders one level at a time, with mod files (adding a mod) or .exe files (finding the game).
func _show_pick(path: String) -> void:
	_mode = "pick"
	_pick_path = path.simplify_path()
	if _pick_path.length() > 1:
		_pick_path = _pick_path.trim_suffix("/")
	_sub.text = _pick_path
	var list: Array = []
	if _pick_mod:
		list.append({"key": "usemod", "text": "Add this whole folder as a mod", "value": "", "data": {}})
	if _pick_path != "/":
		list.append({"key": "up", "text": "..", "value": "Up", "data": {}})
	var d := DirAccess.open(_pick_path)
	if d != null:
		var dirs: Array = Array(d.get_directories()).filter(func(n): return not str(n).begins_with("."))
		dirs.sort_custom(func(a, b): return str(a).to_lower() < str(b).to_lower())
		for n in dirs:
			list.append({"key": "dir", "text": str(n), "value": "", "data": {"path": _pick_path.path_join(str(n))}})
		var fl: Array = Array(d.get_files()).filter(func(n): return not str(n).begins_with(".") and (_pick_mod or str(n).get_extension().to_lower() == "exe"))
		fl.sort_custom(func(a, b): return str(a).to_lower() < str(b).to_lower())
		for n in fl:
			var p := _pick_path.path_join(str(n))
			if _pick_mod:
				list.append({"key": "file", "text": str(n), "value": _size_text(p), "data": {"path": p}})
			else:
				list.append({"key": "exe", "text": str(n), "value": "This is the game", "data": {"path": p}})
	_set_rows(list, 0)
	_msg.text = "Choose a file to add it as a mod (a .zip, .7z or .rar is unpacked), or add this whole folder." if _pick_mod else "Find the folder %s is installed in and choose its .exe." % str(_game.get("title", "the game"))
	_refresh_hints()

func _start_exe_pick() -> void:
	_pick_mod = false
	var start := OS.get_environment("HOME")
	if _home != null and DirAccess.dir_exists_absolute(str(_home.steam_dir) + "/steamapps/common"):
		start = str(_home.steam_dir) + "/steamapps/common"
	elif DirAccess.dir_exists_absolute(games_root()):
		start = games_root()
	_show_pick(start)

func _exe_chosen(exe: String) -> void:
	_write_json(_gdir() + "/game.json", {"install": exe.get_base_dir(), "exe": exe})
	_game["install"] = exe.get_base_dir()
	_game["exe"] = exe
	_game["how"] = "chosen"
	_status = {}
	_link_fluffy(str(_game["dir"]), exe.get_base_dir())
	_show_mods()
	_say("%s is installed in %s. Mods can be added now." % [str(_game["title"]), exe.get_base_dir()])

## Tells Fluffy where the game is installed: the GameInstallPath line at the top of the game folder's installed.ini
## (Fluffy's own record, where it also lists the mods it installed). The rest of the file is kept as it was.
static func _link_fluffy(dir: String, install: String) -> bool:
	if dir == "" or install == "":
		return false
	var path := dir.path_join("installed.ini")
	var wine := "Z:" + install.simplify_path().replace("/", "\\")
	var old := FileAccess.get_file_as_string(path).replace(char(0), "") if FileAccess.file_exists(path) else ""
	var eol := "\n" if old != "" and not old.contains("\r\n") else "\r\n"
	var lines: Array = []
	for l in old.split("\n"):
		lines.append(str(l).trim_suffix("\r"))
	while not lines.is_empty() and str(lines[-1]) == "":
		lines.pop_back()
	var done := false
	var first_section := lines.size()
	for i in lines.size():
		var l := str(lines[i])
		if l.begins_with("[") and first_section == lines.size():
			first_section = i
		if i < first_section and l.to_lower().begins_with("gameinstallpath="):
			lines[i] = "GameInstallPath=" + wine
			done = true
	if not done:
		var head: Array = ["GameInstallPath=" + wine]
		var has_service := false
		for i in first_section:
			if str(lines[i]).to_lower().begins_with("gameinstallservice="):
				has_service = true
		if not has_service:
			head.push_front("GameInstallService=N/A")
		for i in head.size():
			lines.insert(i, head[i])
		if first_section < lines.size() - head.size() and str(lines[head.size()]).begins_with("["):
			lines.insert(head.size(), "")
	DirAccess.make_dir_recursive_absolute(dir)
	var tmp := path + ".tephra-tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(eol.join(PackedStringArray(lines)) + eol)
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK

## Fluffy's record of the mods it installed in this game: the [section] names in installed.ini (a mod's folder or
## archive name, without .zip/.7z/.rar). Empty with "found" false when Fluffy has no record here yet.
static func _fluffy_installed(dir: String) -> Dictionary:
	var out := {"found": false, "mods": {}}
	var path := dir.path_join("installed.ini")
	if dir == "" or not FileAccess.file_exists(path):
		return out
	out["found"] = true
	for l in FileAccess.get_file_as_string(path).replace(char(0), "").split("\n"):
		var t := str(l).strip_edges()
		if t.begins_with("[") and t.ends_with("]") and t.length() > 2:
			out["mods"][t.substr(1, t.length() - 2)] = true
	return out

# ---------- Adding a game ----------
## The games that can be added: the short names mod folders use (RE7, RE3R...), installed Steam games first. A game
## already in the list is left out. Choosing one makes ~/Games/<NAME>/Mods and opens it.
func _show_names() -> void:
	_mode = "name"
	_title.text = "Mods"
	_sub.text = "Add a game"
	var have := {}
	for g in _scan_games():
		if str(g["dir"]).get_base_dir() == games_root():
			have[_norm(str(g["dir"]).get_file())] = g
	var added: Array = []
	var installed: Array = []
	var rest: Array = []
	for k in ALIASES:
		var a: Array = ALIASES[k]
		if have.has(str(k)):
			var g: Dictionary = have[str(k)]
			added.append({"key": "gamename", "text": str(g["dir"]).get_file(), "value": str(g["title"]) + " · already added", "data": {"name": str(g["dir"]).get_file()}})
			have.erase(str(k))
			continue
		var steam := _match_steam(str(k), a)
		var on_disk := not steam.is_empty() and _install_dir(str(steam["id"])) != ""
		var row := {"key": "gamename", "text": str(a[2]), "value": str(a[0]) + (" · installed" if on_disk else ""), "data": {"name": str(a[2])}}
		if on_disk:
			installed.append(row)
		else:
			rest.append(row)
	installed.sort_custom(func(x, y): return str(x["text"]) < str(y["text"]))
	for k in have:  # game folders that are not one of the names above
		var g: Dictionary = have[k]
		added.append({"key": "gamename", "text": str(g["dir"]).get_file(), "value": str(g["title"]) + " · already added", "data": {"name": str(g["dir"]).get_file()}})
	var other := [{"key": "othergame", "text": "Other game...", "value": "Choose its .exe", "data": {}}]
	_set_rows(installed + added + rest + other, 0)
	_msg.text = "Choose the game. Its mods folder is %s/<name>/Mods. For a game not listed, choose Other game." % games_root()
	_refresh_hints()

## Other game: its folder in ~/Games is named after the folder the game is installed in.
func _other_game_chosen(exe: String) -> void:
	_adding_game = false
	var name := ""
	for c in exe.get_base_dir().get_file().strip_edges():
		if not c in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
			name += c
	if name == "" or name == "." or name == ".." or name.to_lower() == "fmm":
		name = exe.get_file().get_basename()
	if _name_chosen(name):
		_exe_chosen(exe)

func _name_chosen(name: String) -> bool:
	var dir := games_root().path_join(name)
	var mods := dir + "/Mods"
	if DirAccess.dir_exists_absolute(dir + "/mods") and not DirAccess.dir_exists_absolute(mods):
		mods = dir + "/mods"
	if DirAccess.make_dir_recursive_absolute(mods) != OK and not DirAccess.dir_exists_absolute(mods):
		_say("Couldn't make %s." % mods)
		return false
	_game = _resolve_game(dir, mods)
	_status = {}
	_msg.text = ""
	_show_mods()
	_say("Added %s. Its mods go in %s." % [str(_game["title"]), mods.replace(OS.get_environment("HOME"), "~")])
	return true

static func _size_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	var b := f.get_length() if f != null else 0
	return ("%.1f MB" % (b / 1048576.0)) if b >= 1048576 else ("%d KB" % maxi(roundi(b / 1024.0), 1))

func _set_rows(list: Array, sel: int) -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows = list
	_sel = clampi(sel, 0, maxi(list.size() - 1, 0))
	_delete_armed = ""
	for r in _rows:
		var p := PanelContainer.new()
		p.custom_minimum_size.y = ROW_H
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Themes.c("tile")
		sb.border_color = SELECT
		sb.set_corner_radius_all(Themes.r(14))
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		p.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 20)
		p.add_child(h)
		var name := _label(str(r["text"]), 30, TEXT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(name)
		var val := _label(str(r["value"]), 26, MUTED)
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		val.name = "Value"
		h.add_child(val)
		r["panel"] = p
		r["label"] = val
		_list.add_child(p)
		_style_value(r)
	_highlight(false)

func _style_value(r: Dictionary) -> void:
	var l: Label = r["label"]
	if r["key"] == "mod":
		var v := str(r["value"])
		# Green when the mod is in the game, red when it is not; grey while it is still being checked.
		l.add_theme_color_override("font_color", Color("46D17B") if v == "on" or v == "fluffy" else (Color("FF5A5F") if v == "off" else MUTED))
		l.text = {"on": "● On", "fluffy": "● On (Fluffy)", "off": "● Off"}.get(v, "…")
	else:
		l.text = str(r["value"])

func _highlight(animate: bool) -> void:
	for i in _rows.size():
		var p: PanelContainer = _rows[i]["panel"]
		(p.get_theme_stylebox("panel") as StyleBoxFlat).set_border_width_all(4 if i == _sel else 0)
	_scroll_to_selected(animate)

func _scroll_to_selected(animate: bool) -> void:
	if _rows.is_empty():
		return
	await get_tree().process_frame
	if not is_open or _sel >= _rows.size():
		return
	var p: Control = _rows[_sel]["panel"]
	var target := clampf(p.position.y + 10.0 + ROW_H / 2.0 - _scroll.size.y / 2.0, 0.0, 100000.0)
	if _scroll_tween != null and _scroll_tween.is_running():
		_scroll_tween.kill()
	if animate:
		_scroll_tween = create_tween()
		_scroll_tween.tween_property(_scroll, "scroll_vertical", int(target), Motion.dur(0.2)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_scroll.scroll_vertical = int(target)

func _refresh_hints() -> void:
	var items: Array = [["dpad_v", "Choose"]]
	var k: String = _rows[_sel]["key"] if _sel < _rows.size() else ""
	match _mode:
		"games":
			if k == "game":
				items.append(["accept", "Open"])
			elif k == "addgame":
				items.append(["accept", "Add a game"])
		"pick":
			items.append(["accept", "Choose" if k == "exe" or k == "file" else "Open"])
		"mods":
			if k == "add":
				items.append(["accept", "Add mods"])
			elif k == "findexe":
				items.append(["accept", "Find the game"])
			elif k == "nexus":
				items.append(["accept", "Open Nexus"])
			elif k == "mod":
				items.append(["accept", "Switch on / off"])
				items.append(["west", "Press again to delete" if _delete_armed != "" else "Delete"])
			items.append(["north", "Reload"])
		"add":
			items.append(["accept", "Add"])
		"name":
			items.append(["accept", "Choose"])
	if _importing and _busy:
		items = [["back", "Cancel"]]
	else:
		items.append(["back", "Back"])
	TephraGlyphs.fill(_hints, items, 26)

# ---------- Input ----------
func move(dir: Vector2i) -> void:
	if not is_open or _rows.is_empty() or _busy or dir.y == 0:
		return
	var i := posmod(_sel + dir.y, _rows.size())
	if i != _sel:
		_sel = i
		_delete_armed = ""
		Haptics.select()
		_highlight(true)
		_refresh_hints()

func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event is InputEventJoypadMotion:
		return true
	if _busy:
		if _importing and event.is_action_pressed("ui_cancel"):
			_cancel_import()
		return true
	var west: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.west_button()) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE)
	var north: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.north_button()) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_Y, KEY_F5])
	if west:
		if _mode == "mods" and _sel < _rows.size() and _rows[_sel]["key"] == "mod":
			_delete_pressed()
	elif north:
		if _mode == "mods":
			_reload()
	elif event.is_action_pressed("ui_cancel"):
		if _delete_armed != "":
			_delete_armed = ""
			_refresh_hints()
		elif _mode == "pick":
			if _pick_path == "/" or _pick_path == OS.get_environment("HOME"):
				if _pick_mod:
					_pick_mod = false
					_show_add()
				elif _adding_game:
					_adding_game = false
					_show_names()
				else:
					_show_mods()
			else:
				_show_pick(_pick_path.get_base_dir())
		elif _mode == "add":
			_show_mods()
		elif _mode == "name":
			_show_games()
		elif _mode == "mods":
			if _direct:
				close()
			else:
				_show_games()
		else:
			close()
	elif event.is_action_pressed("ui_accept") and _sel < _rows.size():
		_accept(_rows[_sel])
		# Blocked by an overlap? Holding the button on that mod for a second puts it over the other one.
		if _mode == "mods" and _override_name != "" and _rows[_sel]["key"] == "mod" and str(_rows[_sel]["data"]["name"]) == _override_name:
			_hold_override(_override_name)
	elif event.is_action_released("ui_accept"):
		_accept_down = false
	return true

func _hold_override(name: String) -> void:
	_hold_token += 1
	var tok := _hold_token
	_accept_down = true
	await get_tree().create_timer(1.0).timeout
	if _accept_down and tok == _hold_token and is_open and not _busy and _override_name == name:
		_accept_down = false
		_toggle(name, true)

## Triangle: Tephra rereads what Fluffy wrote for this game (its installed.ini) and looks at the game's files again. Every
## row gives a small shrink-and-grow, one after another, so it is plain that something happened.
func _reload() -> void:
	if _busy or _game.is_empty() or str(_game["install"]) == "":
		return
	_status = {}
	_delete_armed = ""
	_show_mods("", true)
	Haptics.tick()
	await get_tree().process_frame  # the new rows get their size first
	if not is_open:
		return
	for i in _rows.size():
		var p: Control = _rows[i]["panel"]
		p.pivot_offset = p.size / 2.0
		var t := create_tween()
		t.tween_interval(0.035 * i)
		t.tween_property(p, "scale", Vector2(0.94, 0.94), Motion.dur(0.09)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(p, "scale", Vector2(1.03, 1.03), Motion.dur(0.12)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(p, "scale", Vector2.ONE, Motion.dur(0.12)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _accept(r: Dictionary) -> void:
	match str(r["key"]):
		"game":
			_game = r["data"]
			_status = {}
			_msg.text = ""
			_show_mods()
		"findexe":
			if _mode == "mods" and not (_state()["enabled"] as Dictionary).is_empty():
				_say("Switch this game's mods off first, then change where it is installed.")
			else:
				_start_exe_pick()
		"add":
			_show_add()
		"nexus":
			var title := str(_game["title"])
			close()
			_home.open_nexus_for(title)
		"browse":
			_pick_mod = true
			var dl := OS.get_environment("HOME") + "/Downloads"
			_show_pick(dl if DirAccess.dir_exists_absolute(dl) else OS.get_environment("HOME"))
		"usemod", "file":
			_import(_pick_path if str(r["key"]) == "usemod" else str(r["data"]["path"]))
		"exe":
			if _adding_game:
				_other_game_chosen(str(r["data"]["path"]))
			else:
				_exe_chosen(str(r["data"]["path"]))
		"addgame":
			_show_names()
		"othergame":
			_adding_game = true
			_game = {"title": "the game"}
			_start_exe_pick()
		"gamename":
			_name_chosen(str(r["data"]["name"]))
		"up":
			_show_pick(_pick_path.get_base_dir())
		"dir":
			_show_pick(str(r["data"]["path"]))
		"archive":
			_import(str(r["data"]["path"]))
		"mod":
			_toggle(str(r["data"]["name"]))

func _say(text: String) -> void:
	_msg.text = text

# ---------- Closing a running game first ----------
## Mods are only changed while nothing is running: every game and app, Gamescope and Steam are closed first (after
## asking, when something is open). True once everything is closed.
func _ensure_closed() -> bool:
	if _home == null or not _home.anything_running():
		return true
	var yes: bool = await _home.overlay.ask("Close everything?", "To change mods safely, Tephra closes all games and apps, Gamescope and Steam first. Anything you haven't saved is lost.", "Close all")
	if not yes:
		return false
	_say("Closing games, apps and Steam...")
	await _home.close_everything()
	return not _home.launching

# ---------- Switching a mod on or off ----------
static func _patch_num(rel: String) -> int:
	var re := RegEx.new()
	re.compile("^re_chunk_000\\.pak\\.patch_(\\d+)\\.pak$")
	var m := re.search(rel.to_lower())
	return int(m.get_string(1)) if m != null else -1

var _override_name := ""  # a mod blocked by an overlap: holding accept on it switches it on anyway
var _accept_down := false
var _hold_token := 0

func _toggle(name: String, force := false) -> void:
	_override_name = ""
	var gdir := str(_game["install"])
	if gdir == "" or not DirAccess.dir_exists_absolute(gdir):
		_say("Couldn't find %s's folder. Is it installed?" % str(_game["title"]))
		return
	var st := _state()
	var now := str(_status.get(name, "wait"))
	if now == "wait":
		_say("Still checking %s. Try again in a moment." % name)
		return
	if now == "fluffy":
		_say("%s was installed by Fluffy Mod Manager, not by Tephra, so Tephra can't take it out safely." % name.get_basename())
		return
	var turning_on: bool = now == "off"
	var files: Array = []
	if turning_on:
		# Two mods must not both write the same file.
		var mine := _list_files(_mods_dir() + "/" + name) if DirAccess.dir_exists_absolute(_mods_dir() + "/" + name) else []
		for other in st["enabled"]:
			var shared: Array = []
			for rel in st["enabled"][other]:
				if rel in mine and _patch_num(str(rel)) < 0:
					shared.append(str(rel))
			if not shared.is_empty() and not force:
				_override_name = name
				_say("%s and %s both change %s (for example %s). Only one can win: switch %s off first, or hold %s to put %s over it." % [_nice(name), _nice(str(other)), _files_word(shared.size()), str(shared[0]).get_file(), _nice(str(other)), TephraGlyphs.btn("accept"), _nice(name)])
				return
		_warn = _warnings_for(name, mine, _fluffy_files(str(_game["dir"])))
	else:
		_warn = ""
		files = st["enabled"].get(name, [])
		# RE Engine games stop loading patch paks after a missing number, so only the newest ones can come out.
		var mine_nums: Array = []
		for rel in files:
			if _patch_num(str(rel)) >= 0:
				mine_nums.append(_patch_num(str(rel)))
		if not mine_nums.is_empty():
			var lowest: int = mine_nums.min()
			for n in _patch_paks(gdir):
				if int(n) > lowest and not mine_nums.has(int(n)):
					_say("A mod switched on after %s uses a newer .pak. Switch that one off first." % name)
					return
	_busy = true
	var ok: bool = await _ensure_closed()
	if not ok:
		_busy = false
		_say("Left as it was." if not _home.launching else "Still closing. Try again in a moment.")
		return
	_say(("Switching on %s..." if turning_on else "Switching off %s...") % name.get_basename())
	var key := str(_game["key"])
	var mods_dir := _mods_dir()
	var data := _gdir()
	var job := {"id": -1}
	job["id"] = WorkerThreadPool.add_task(func() -> void:
		var res: Dictionary
		if turning_on:
			res = _enable_job(gdir, mods_dir, name, data)
		else:
			res = _disable_job(gdir, files, data + "/backup/" + name)
		_toggle_done.call_deferred(res, name, turning_on, key, data, job))

var _warn := ""   # warnings found before switching a mod on, shown after it is on

func _nice(name: String) -> String:
	return name.get_basename() if name.get_extension().to_lower() in MOD_ARCHIVES else name

static func _files_word(n: int) -> String:
	return "1 file" if n == 1 else "%d files" % n

## A mod's file as Fluffy writes it, compared with Tephra's: lower case, forward slashes, from "natives/" on.
static func _norm_path(rel: String) -> String:
	var p := rel.strip_edges().replace("\\", "/").to_lower()
	var i := p.find("natives/")
	return p.substr(i) if i >= 0 else p

## The files of each mod Fluffy installed here (its file= lines in installed.ini): {mod name: [normalized paths]}.
static func _fluffy_files(dir: String) -> Dictionary:
	var out := {}
	var path := dir.path_join("installed.ini")
	if dir == "" or not FileAccess.file_exists(path):
		return out
	var cur := ""
	for l in FileAccess.get_file_as_string(path).replace(char(0), "").split("\n"):
		var t := str(l).strip_edges()
		if t.begins_with("[") and t.ends_with("]") and t.length() > 2:
			cur = t.substr(1, t.length() - 2)
			out[cur] = []
		elif cur != "" and t.to_lower().begins_with("file="):
			(out[cur] as Array).append(_norm_path(t.substr(5)))
	return out

## Warnings shown after a mod is switched on (they never stop it): a name that says which game version it is for, and
## files that a mod installed by Fluffy also changes (Tephra can't switch those off, and the one done last wins).
static func _warnings_for(name: String, files: Array, fluffy: Dictionary) -> String:
	var out := ""
	var low := _nice_static(name).to_lower()
	var re := RegEx.create_from_string("(^|[^a-z0-9])(non[ _-]?rt|no[ _-]?rt|nort)([^a-z0-9]|$)")
	if re.search(low) != null:
		out += "\nIts name says it is for the version without ray tracing (non-RT). If your game is the RT version, it may not work or may look wrong."
	elif RegEx.create_from_string("(^|[^a-z0-9])rt([^a-z0-9]|$)|ray[ _-]?trac").search(low) != null:
		out += "\nIts name says it is for the ray tracing (RT) version. If your game is the non-RT version, it may not work or may look wrong."
	var mine := {}
	for rel in files:
		mine[_norm_path(str(rel))] = true
	for other in fluffy:
		if _nice_static(name) == other:
			continue
		var n := 0
		for rel in fluffy[other]:
			if mine.has(rel):
				n += 1
		if n > 0:
			out += "\nIt changes %s that %s (installed with Fluffy) also changes. The one switched on last wins. Fluffy has to switch that one off." % [_files_word(n), other]
	return out

static func _nice_static(name: String) -> String:
	return name.get_basename() if name.get_extension().to_lower() in MOD_ARCHIVES else name

## When the game's .pak files list none of a mod's loose files, it is probably for another version of the game.
static func _mismatch_text(res: Dictionary) -> String:
	var n := int(res.get("natives", 0))
	if n >= 3 and int(res.get("matched", -1)) == 0:
		return "\nNone of its %d game files match this game's own files. It may be for another version of the game (for example ray tracing or not), so it may do nothing. Switch it off if you see no change." % n
	return ""

func _toggle_done(res: Dictionary, name: String, turned_on: bool, key: String, data: String, job: Dictionary) -> void:
	WorkerThreadPool.wait_for_task_completion(int(job["id"]))
	_busy = false
	var shown := str(res.get("name", name))
	var txt := ("%s is on and installed in the game." % shown.get_basename()) if turned_on else ("%s is off and taken out of the game." % shown.get_basename())
	if bool(res["ok"]):
		# The state is saved against the game it belongs to, even if the page moved on.
		var st: Dictionary = _read_json(data + "/state.json", {})
		if typeof(st.get("enabled")) != TYPE_DICTIONARY:
			st = {"enabled": {}}
		if turned_on:
			st["enabled"][shown] = res["files"]
		else:
			st["enabled"].erase(name)
		_write_json(data + "/state.json", st)
	else:
		txt = str(res["err"])
	if is_open and _mode == "mods" and str(_game.get("key", "")) == key:
		if bool(res["ok"]):
			_status[shown] = "on" if turned_on else "off"
		_show_mods(shown)
		if turned_on and bool(res["ok"]):
			txt += _warn + _mismatch_text(res)
		_say(txt)
	elif _home != null:
		_home.notify(txt)

## All files in a folder as paths relative to it.
static func _list_files(dir: String, rel := "") -> Array:
	var out: Array = []
	var d := DirAccess.open(dir.path_join(rel) if rel != "" else dir)
	if d == null:
		return out
	for f in d.get_files():
		out.append(rel.path_join(f) if rel != "" else f)
	for sub in d.get_directories():
		out.append_array(_list_files(dir, rel.path_join(sub) if rel != "" else sub))
	return out

## Worker thread: copy a mod's files into the game, setting aside any original it replaces. A mod still packed as an
## archive in the Mods folder is unpacked into a folder there first (the archive is kept in Tephra's notes). A .pak at
## the mod's top level goes in as the next re_chunk_000.pak.patch_NNN.pak, the way RE Engine games load them.
static func _enable_job(gdir: String, mods_dir: String, name: String, data: String) -> Dictionary:
	if OS.execute("test", ["-w", gdir]) != 0:
		return {"ok": false, "err": "Can't write in the game's folder."}
	var moddir := mods_dir.path_join(name)
	if not DirAccess.dir_exists_absolute(moddir):
		var res := _import_job(moddir, gdir, mods_dir, data)
		if not bool(res["ok"]):
			return res
		DirAccess.make_dir_recursive_absolute(data + "/archives")
		OS.execute("mv", ["-f", "--", moddir, data + "/archives/"])
		name = str(res["name"])
		moddir = mods_dir.path_join(name)
	var files: Array = _list_files(moddir).filter(func(r): return not _is_meta(str(r)))
	if files.is_empty():
		return {"ok": false, "err": "This mod has no game files in it."}
	var bdir := data + "/backup/" + name
	var uses_patches := FileAccess.file_exists(gdir + "/re_chunk_000.pak")
	var next := 0
	for n in _patch_paks(gdir):
		next = maxi(next, int(n))
	var done: Array = []
	for rel in files:
		var to := str(rel)
		if uses_patches and to.get_extension().to_lower() == "pak" and not to.contains("/"):
			next += 1
			to = "re_chunk_000.pak.patch_%03d.pak" % next
		var dest: String = gdir.path_join(to)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		if FileAccess.file_exists(dest):
			var b: String = bdir.path_join(to)
			DirAccess.make_dir_recursive_absolute(b.get_base_dir())
			if DirAccess.rename_absolute(dest, b) != OK and OS.execute("mv", ["-f", "--", dest, b]) != 0:
				_disable_job(gdir, done, bdir)
				return {"ok": false, "err": "Couldn't set aside the original %s." % to.get_file()}
		if OS.execute("cp", ["--reflink=auto", "-f", "--", moddir.path_join(str(rel)), dest]) != 0:
			done.append(to)
			_disable_job(gdir, done, bdir)
			return {"ok": false, "err": "Couldn't copy %s into the game (disk full?). Nothing was changed." % str(rel).get_file()}
		done.append(to)
	# RE Engine games: the .pak entries of the mod's loose files are hidden, or the game never reads them.
	var natives: Array = done.filter(func(r): return str(r).to_lower().begins_with("natives/"))
	var matched := -1  # how many of the mod's loose files the game's .pak files list (-1: not checked)
	if uses_patches and not natives.is_empty():
		var hid := _pak_hide(gdir, natives, done, bdir + "/" + PAK_RECORD)
		if not bool(hid["ok"]):
			_disable_job(gdir, done, bdir)
			return {"ok": false, "err": str(hid["err"])}
		matched = int(hid.get("hidden", 0))
	return {"ok": true, "files": done, "name": name, "natives": natives.size(), "matched": matched}

## Worker thread: take a mod's files back out and put the originals back.
static func _disable_job(gdir: String, files: Array, bdir: String) -> Dictionary:
	if FileAccess.file_exists(bdir + "/" + PAK_RECORD) and not _pak_restore(bdir + "/" + PAK_RECORD):
		return {"ok": false, "err": "Couldn't put the game's .pak back as it was, so the mod was left on. Is the game's folder writable?"}
	for rel in files:
		var dest: String = gdir.path_join(rel)
		if FileAccess.file_exists(dest):
			DirAccess.remove_absolute(dest)
		var b: String = bdir.path_join(rel)
		if FileAccess.file_exists(b):
			if DirAccess.rename_absolute(b, dest) != OK:
				OS.execute("mv", ["-f", "--", b, dest])
		# Folders the mod made are removed again when they are empty (a folder with anything in it stays).
		var d: String = dest.get_base_dir()
		while d.length() > gdir.length() and d.begins_with(gdir):
			if DirAccess.remove_absolute(d) != OK:
				break
			d = d.get_base_dir()
	OS.execute("rm", ["-rf", "--", bdir])
	return {"ok": true}

# ---------- RE Engine .pak tables ----------
## An RE Engine game only reads a loose file in natives/ when none of its .pak files lists that path. Switching on a
## loose-file mod therefore hides those paths' entries in the .pak tables (their two name hashes are flipped), the way
## Fluffy does it. Only entries whose hashes are exactly the mod's paths are touched, the original bytes are saved in
## the mod's backup folder before anything is written, and switching the mod off writes them back.
const PAK_RECORD := ".tephra-pak.json"

static func _mul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF

static func _rotl32(x: int, r: int) -> int:
	return ((x << r) | (x >> (32 - r))) & 0xFFFFFFFF

## MurmurHash3 (x86, 32 bit).
static func _murmur3(data: PackedByteArray, seed: int) -> int:
	var h := seed & 0xFFFFFFFF
	var n := data.size()
	var i := 0
	while i + 4 <= n:
		var k := data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)
		k = _mul32(_rotl32(_mul32(k, 0xcc9e2d51), 15), 0x1b873593)
		h = (_mul32(_rotl32(h ^ k, 13), 5) + 0xe6546b64) & 0xFFFFFFFF
		i += 4
	var rem := n - i
	if rem > 0:
		var k1 := 0
		if rem >= 3:
			k1 ^= data[i + 2] << 16
		if rem >= 2:
			k1 ^= data[i + 1] << 8
		k1 ^= data[i]
		h ^= _mul32(_rotl32(_mul32(k1, 0xcc9e2d51), 15), 0x1b873593)
	h ^= n
	h = _mul32(h ^ (h >> 16), 0x85ebca6b)
	h = _mul32(h ^ (h >> 13), 0xc2b2ae35)
	return h ^ (h >> 16)

## The two hashes an RE Engine .pak lists a path under: of its lower case and upper case UTF-16 text.
static func _pak_hashes(rel: String) -> Array:
	var p := rel.replace("\\", "/")
	return [_murmur3(p.to_lower().to_utf16_buffer(), 0xFFFFFFFF), _murmur3(p.to_upper().to_utf16_buffer(), 0xFFFFFFFF)]

## A .pak's table layout: {"count", "entry" (bytes per entry), "hash_at" (where the two hashes are in an entry)},
## {"locked": true} when the table is encrypted, or {} when it is not a .pak this knows.
static func _pak_layout(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 16:
		return {}
	var head := f.get_buffer(16)
	if head.slice(0, 4).get_string_from_ascii() != "KPKA":
		return {}
	if head.decode_u16(6) & 8:
		return {"locked": true}
	var count := head.decode_u32(8)
	match head[4]:
		4:
			return {"count": count, "entry": 48, "hash_at": 0}
		2:
			return {"count": count, "entry": 24, "hash_at": 16}
	return {}

## The game's .pak files (the main one, its patches, DLC), minus those that came with the mod itself.
static func _game_paks(gdir: String, skip: Array) -> Array:
	var out: Array = []
	for sub in ["", "dlc"]:
		var d := gdir if sub == "" else gdir.path_join(sub)
		for f in DirAccess.get_files_at(d):
			var rel: String = str(f) if sub == "" else sub + "/" + str(f)
			if str(f).to_lower().ends_with(".pak") and not skip.has(rel):
				out.append(d.path_join(str(f)))
	return out

static func _pak_hide(gdir: String, rels: Array, skip: Array, record: String) -> Dictionary:
	var wanted := {}  # lower hash -> [upper hash, ...]
	for rel in rels:
		var h := _pak_hashes(str(rel))
		if not wanted.has(h[0]):
			wanted[h[0]] = []
		wanted[h[0]].append(h[1])
	var changes: Array = []
	var locked := false
	for pak in _game_paks(gdir, skip):
		var lay := _pak_layout(pak)
		if lay.get("locked", false):
			locked = true
			continue
		if lay.is_empty():
			continue
		var f := FileAccess.open(pak, FileAccess.READ)
		var entry: int = lay["entry"]
		f.seek(16)
		var buf := f.get_buffer(int(lay["count"]) * entry)
		f.close()
		for j in buf.size() / entry:
			var at: int = j * entry + int(lay["hash_at"])
			var lo := buf.decode_u32(at)
			if wanted.has(lo):
				var up := buf.decode_u32(at + 4)
				if (wanted[lo] as Array).has(up):
					changes.append({"pak": pak, "at": 16 + at, "lo": lo, "up": up})
	if changes.is_empty():
		if locked:
			return {"ok": false, "err": "This game's .pak files are encrypted, so Tephra can't switch on loose-file mods for it yet."}
		return {"ok": true}  # the mod only adds new files: nothing to hide
	# Saved before anything is written, so it can always be undone.
	DirAccess.make_dir_recursive_absolute(record.get_base_dir())
	var rf := FileAccess.open(record, FileAccess.WRITE)
	if rf == null:
		return {"ok": false, "err": "Couldn't save a backup of the game's .pak table."}
	rf.store_string(JSON.stringify(changes))
	rf.close()
	for c in changes:
		var pf := FileAccess.open(str(c["pak"]), FileAccess.READ_WRITE)
		if pf == null:
			_pak_restore(record)
			return {"ok": false, "err": "Couldn't write in %s. Nothing was changed." % str(c["pak"]).get_file()}
		pf.seek(int(c["at"]))
		pf.store_32(~int(c["lo"]) & 0xFFFFFFFF)
		pf.store_32(~int(c["up"]) & 0xFFFFFFFF)
		pf.close()
	return {"ok": true, "hidden": changes.size()}

## Writes the saved .pak table bytes back. An entry is only written when it still holds what Tephra put there.
static func _pak_restore(record: String) -> bool:
	var changes = JSON.parse_string(FileAccess.get_file_as_string(record))
	if not changes is Array:
		return false
	var ok := true
	for c in changes:
		var pf := FileAccess.open(str(c["pak"]), FileAccess.READ_WRITE)
		if pf == null:
			ok = ok and not FileAccess.file_exists(str(c["pak"]))  # a .pak a game update removed is fine
			continue
		var lo := int(c["lo"])
		var up := int(c["up"])
		pf.seek(int(c["at"]))
		var cur_lo := pf.get_32()
		var cur_up := pf.get_32()
		if cur_lo == (~lo & 0xFFFFFFFF) and cur_up == (~up & 0xFFFFFFFF):
			pf.seek(int(c["at"]))
			pf.store_32(lo)
			pf.store_32(up)
		pf.close()
	if ok:
		DirAccess.remove_absolute(record)
	return ok

# ---------- Deleting a mod ----------
func _delete_pressed() -> void:
	var name := str(_rows[_sel]["data"]["name"])
	if _delete_armed == name and Time.get_ticks_msec() < _delete_until:
		_delete_mod(name)
		return
	if str(_status.get(name, "")) == "fluffy":
		_say("%s was installed by Fluffy Mod Manager. It has to be taken out there before it can be deleted." % name.get_basename())
		return
	_delete_armed = name
	_delete_until = Time.get_ticks_msec() + 4000
	_say("Press again to delete %s for good." % name.get_basename())
	_refresh_hints()
	Haptics.tick()
	await get_tree().create_timer(4.1).timeout
	if _delete_armed == name and Time.get_ticks_msec() >= _delete_until:
		_delete_armed = ""
		if is_open:
			_refresh_hints()

func _delete_mod(name: String) -> void:
	_delete_armed = ""
	var st := _state()
	var was_on: bool = st["enabled"].has(name)
	var gdir := str(_game["install"])
	if was_on and gdir == "":
		_say("Couldn't find the game's folder to switch %s off first." % name)
		return
	_busy = true
	if was_on:
		var ok: bool = await _ensure_closed()
		if not ok:
			_busy = false
			_say("Left as it was.")
			return
	var files: Array = st["enabled"].get(name, [])
	var moddir := _mods_dir() + "/" + name
	var bdir := _gdir() + "/backup/" + name
	var key := str(_game["key"])
	var data := _gdir()
	var job := {"id": -1}
	job["id"] = WorkerThreadPool.add_task(func() -> void:
		if was_on:
			var off := _disable_job(gdir, files, bdir)
			if not bool(off["ok"]):
				_delete_done.call_deferred(name, key, data, job, str(off["err"]))
				return
		OS.execute("rm", ["-rf", "--", moddir])
		_delete_done.call_deferred(name, key, data, job))

func _delete_done(name: String, key: String, data: String, job: Dictionary, err := "") -> void:
	WorkerThreadPool.wait_for_task_completion(int(job["id"]))
	_busy = false
	if err != "":
		if is_open and _mode == "mods" and str(_game.get("key", "")) == key:
			_say(err)
		return
	var st: Dictionary = _read_json(data + "/state.json", {})
	if typeof(st.get("enabled")) == TYPE_DICTIONARY:
		st["enabled"].erase(name)
		_write_json(data + "/state.json", st)
	_status.erase(name)
	if _home != null and _home.sfx != null:
		_home.sfx.play("trash")
	if is_open and _mode == "mods" and str(_game.get("key", "")) == key:
		_show_mods()
		_say("%s was deleted." % name.get_basename())

# ---------- Adding a mod ----------
func _cancel_import() -> void:
	_import_cancelled = _import_token
	_busy = false
	if _home != null and _home.sfx != null:
		_home.sfx.play("back")
	_show_mods()
	_say("Cancelled. Nothing was added.")

func _import(path: String) -> void:
	if _importing:
		_say("Still stopping the last one. Try again in a moment.")
		return
	var gdir := str(_game["install"])
	_import_token += 1
	var token := _import_token
	_importing = true
	_refresh_hints()
	_busy = true
	_say("Adding %s... Press Back to cancel." % path.get_file())
	var mods_dir := _mods_dir()
	var data := _gdir()
	var key := str(_game["key"])
	var job := {"id": -1}
	job["id"] = WorkerThreadPool.add_task(func() -> void:
		var res := _import_job(path, gdir, mods_dir, data)
		_import_done.call_deferred(res, key, mods_dir, job, token))

func _import_done(res: Dictionary, key: String, mods_dir: String, job: Dictionary, token: int) -> void:
	WorkerThreadPool.wait_for_task_completion(int(job["id"]))
	_importing = false
	if token == _import_cancelled:
		# Cancelled while it ran: what it unpacked is removed again.
		if bool(res["ok"]):
			OS.create_process("rm", ["-rf", "--", mods_dir + "/" + str(res["name"])])
		return
	_busy = false
	if not is_open or str(_game.get("key", "")) != key:
		return
	if bool(res["ok"]):
		_status[str(res["name"])] = "off"
		_show_mods(str(res["name"]))
		_say("Added %s to %s. Fluffy sees it too. Choose it to switch it on." % [str(res["name"]), mods_dir])
	else:
		_say(str(res["err"]))

## Folder names that are the game's own layout, never a wrapper to strip.
const ROOT_NAMES := ["natives", "reframework", "bepinex", "mods", "data", "bin", "content", "paks", "plugins", "scripts", "engine", "steamapps"]

## Worker thread: unpack a copy of the archive, drop wrapper folders, and move the result to Mods/<name>.
static func _import_job(src: String, gdir: String, mods_dir: String, data: String) -> Dictionary:
	var is_dir := DirAccess.dir_exists_absolute(src)
	var is_archive := src.get_extension().to_lower() in ARCHIVE_EXTS
	var stem := src.get_file()
	if not is_dir:
		stem = stem.left(stem.length() - (stem.get_extension().length() + 1)) if stem.get_extension() != "" else stem
	if stem.to_lower().ends_with(".tar"):
		stem = stem.left(stem.length() - 4)
	var inc := data + "/.incoming"
	OS.execute("rm", ["-rf", "--", inc])
	DirAccess.make_dir_recursive_absolute(inc)
	var out := ""
	if is_dir or not is_archive:
		# A folder or a loose file (a .dll, a .pak...): copied as it is, no unpacking.
		DirAccess.make_dir_recursive_absolute(inc + "/m")
		if OS.execute("cp", ["-r", "--reflink=auto", "--", src, inc + "/m/"]) != 0:
			OS.execute("rm", ["-rf", "--", inc])
			return {"ok": false, "err": "Couldn't read %s." % src.get_file()}
		out = inc + "/m"
	else:
		if OS.execute("cp", ["--", src, inc + "/"]) != 0:
			return {"ok": false, "err": "Couldn't read %s." % src.get_file()}
		var res := FilesBrowser._extract_job(inc + "/" + src.get_file(), false)
		if not bool(res["ok"]):
			OS.execute("rm", ["-rf", "--", inc])
			return {"ok": false, "err": str(res["err"])}
		out = str(res["out"])
	# A wrapper folder ("CoolMod-v2/natives/...") is dropped, but a real game folder ("natives/...") stays.
	for i in 4:
		var entries := FilesBrowser._entries(out)
		if entries.size() != 1 or not DirAccess.dir_exists_absolute(out.path_join(entries[0])):
			break
		var e: String = entries[0]
		var inner := FilesBrowser._entries(out.path_join(e))
		var wrapper := false
		if e.to_lower() == stem.to_lower():
			wrapper = true
		elif not (e.to_lower() in ROOT_NAMES) and (gdir == "" or not DirAccess.dir_exists_absolute(gdir.path_join(e))):
			for c in inner:
				if c.to_lower() in ROOT_NAMES or c.to_lower() == "modinfo.ini" or c.get_extension().to_lower() == "pak" \
						or (gdir != "" and (DirAccess.dir_exists_absolute(gdir.path_join(c)) or FileAccess.file_exists(gdir.path_join(c)))):
					wrapper = true
		if not wrapper:
			break
		out = out.path_join(e)
	DirAccess.make_dir_recursive_absolute(mods_dir)
	var name := stem
	var n := 2
	while DirAccess.dir_exists_absolute(mods_dir.path_join(name)):
		name = "%s (%d)" % [stem, n]
		n += 1
	var final := mods_dir.path_join(name)
	if DirAccess.rename_absolute(out, final) != OK and OS.execute("mv", ["--", out, final]) != 0:
		OS.execute("rm", ["-rf", "--", inc])
		return {"ok": false, "err": "Couldn't store the mod."}
	OS.execute("rm", ["-rf", "--", inc])
	if _list_files(final).is_empty():
		OS.execute("rm", ["-rf", "--", final])
		return {"ok": false, "err": "%s had no files in it." % src.get_file()}
	return {"ok": true, "name": name}
