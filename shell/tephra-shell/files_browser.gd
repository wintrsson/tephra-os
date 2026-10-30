extends Control
## Files: a controller-driven file browser opened from the control center's Files card.
## The top level lists the drives (Home and anything mounted under /run/media, /media or /mnt).
## Up/Down choose, A opens, B goes up a level (and closes at the top). Hold A on a folder or file to pick it up,
## open the folder it should go to and press A to drop it there; B puts it back. The move really happens on disk.

signal closed
signal hints_changed
signal keyboard_requested(title: String, initial: String, done: Callable)

const Themes = preload("res://themes.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Icons = preload("res://icons.gd")
const Settings = preload("res://settings.gd")

const COLS := 7           # squares across
const GRID_ROWS := 3      # rows of squares shown at once; the grid scrolls a row at a time past that
const ROWS := COLS * GRID_ROWS
const TILE := Vector2(140, 140)
const GAP := 12
const HOLD_MS := 500      # how long A is held to pick something up
const DELETE_MS := 1200   # how long Triangle is held to delete (it goes to the Trash)
const Glyphs = preload("res://glyphs.gd")
const PANEL_W := 1120
const NAME_H := 48        # height of a square's name strip (two lines)
const NAME_FS := 17
const SCROLL_WAIT := 0.9  # seconds a long name rests at each end before it scrolls
const SCROLL_SPEED := 60.0  # pixels per second

var is_open := false
var _viewer: Control  # image_viewer.gd: open while a picture is shown
var _note: Control  # notepad.gd: open while a .txt file is being edited

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var SELECT: Color = Themes.c("select")

var _panel: PanelContainer
var _title: Label
var _path: Label
var _chip: PanelContainer
var _chip_label: Label
var _rows: Array = []     # the squares shown, each: {"panel", "fill", "icon", "name", "detail", "style"}
var _empty: Label
var _msg: Label
var _count: Label

var _trash := false       # the Trash is open (listing ~/.local/share/Trash/files)
var _empty_armed := false # Square was pressed once: the next press empties the Trash
var _dir := ""            # the folder open now; "" = the list of drives
var _drive_root := ""
var _drive_name := ""
var _items: Array = []    # each: {"name", "path", "kind": "drive"/"home"/"dir"/"file", "detail"}
var _sel := 0
var _top := 0             # first square shown (always the start of a row)
var _sizes := {}          # file path -> size text, read only for rows that are shown

var _carry := {}          # the item picked up: {"name", "path", "kind"}; empty when nothing is
# Choosing a file for something else (Library > Add a game): A on a file with one of these endings hands its path
# over and closes Files. Nothing can be moved, deleted or extracted meanwhile, and the Trash is not listed.
var _pick_exts: Array = []  # lower-case endings that can be chosen; empty = not choosing
var _pick_done := Callable()
var _pick_note := ""
var _pick_verb := ""
var _press_ms := -1       # when A went down (for the hold); -1 = not held
var _back_ms := -1        # when Circle went down while carrying; -1 = not held
var _del_ms := -1         # when Triangle went down; -1 = not held
var _hover_ms := 0        # when the cursor came to rest on this square (folders open by themselves while carrying)
const SPRING_MS := 1300
var _spring_armed := false  # only after the cursor was moved: a folder just opened never opens the next by itself
var _busy := false        # a move across drives is running in the background
var _task_id := -1
var _ext_jobs: Array = []   # running extractions: [{"id": task id, "src": archive path}] (they never block moving)
var _df_task := -1
var _free := {}           # drive path -> "120G free"
var _scroll_t := 0.0      # time since the chosen square changed: drives its long name scrolling
var _scroll_sel := -1
var _thumbs := {}         # file path -> its small picture (Texture2D), or null when it has none
var _thumb_task := -1
var _thumb_want: Array = []  # shown pictures and videos still waiting for their small picture

# ---------- Drives ----------
## Home plus the real drives mounted where removable and extra disks go. Pseudo filesystems are skipped:
## only mounts whose source is a block device under /dev count.
static func drives() -> Array:
	var home := OS.get_environment("HOME")
	var list: Array = [{"name": "Home", "path": home, "kind": "home", "detail": ""}]
	var f := FileAccess.open("/proc/mounts", FileAccess.READ)
	if f == null:
		return list
	var seen := {home: true}
	for line in f.get_as_text().split("\n", false):
		var p := line.split(" ", false)
		if p.size() < 3 or not p[0].begins_with("/dev/"):
			continue
		var mp := p[1].replace("\\040", " ").replace("\\011", "\t").replace("\\134", "\\")
		if not (mp.begins_with("/run/media/") or mp.begins_with("/media/") or mp.begins_with("/mnt/")):
			continue
		if seen.has(mp) or not DirAccess.dir_exists_absolute(mp):
			continue
		seen[mp] = true
		list.append({"name": mp.get_file(), "path": mp, "kind": "drive", "detail": ""})
	return list

## Every Steam "common" folder (where the games are installed): Steam's own and each extra library from libraryfolders.vdf.
static func steam_common_dirs() -> Array:
	var home := OS.get_environment("HOME")
	var roots: Array = [home + "/.local/share/Steam", home + "/.steam/steam", home + "/.var/app/com.valvesoftware.Steam/.local/share/Steam"]
	var re_path := RegEx.create_from_string("\"path\"\\s+\"([^\"]+)\"")
	for r in roots.duplicate():
		for m in re_path.search_all(FileAccess.get_file_as_string(str(r) + "/steamapps/libraryfolders.vdf")):
			roots.append(m.get_string(1))
	var out: Array = []
	var seen := {}
	for r in roots:
		var c := str(r) + "/steamapps/common"
		if not DirAccess.dir_exists_absolute(c):
			continue
		var real := []
		OS.execute("realpath", [c], real)
		var key := String(real[0]).strip_edges() if not real.is_empty() else c
		if key == "" or seen.has(key):
			continue
		seen[key] = true
		out.append(c)
	return out

# ---------- Build ----------
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Themes.c("card"), 0.96)
	sb.set_corner_radius_all(Themes.r(18))
	sb.set_content_margin_all(28)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 6)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -PANEL_W / 2.0
	_panel.offset_right = PANEL_W / 2.0
	_panel.offset_top = 104  # clear of the clock above and the cards below
	preload("res://rounded.gd").rough(_panel, 0.5)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	_title = _label("Files", 32, TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size.x = 200
	head.add_child(_title)
	# "Moving: name" chip, shown while something is picked up.
	_chip = PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(SELECT, 0.22)
	csb.border_color = SELECT
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(Themes.r(16))
	csb.content_margin_left = 16
	csb.content_margin_right = 16
	csb.content_margin_top = 4
	csb.content_margin_bottom = 4
	_chip.add_theme_stylebox_override("panel", csb)
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip.visible = false
	head.add_child(_chip)
	_chip_label = _label("", 22, TEXT)
	_chip.add_child(_chip_label)

	_path = _label("", 20, MUTED)
	_path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_path.custom_minimum_size.x = 400
	v.add_child(_path)
	var line := ColorRect.new()
	line.color = Themes.ink(0.14)
	line.custom_minimum_size.y = 2
	v.add_child(line)

	var list := Control.new()
	list.custom_minimum_size = Vector2(PANEL_W - 56, GRID_ROWS * (TILE.y + GAP))
	v.add_child(list)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	list.add_child(grid)
	grid.position = Vector2(((PANEL_W - 56) - (COLS * TILE.x + (COLS - 1) * GAP)) * 0.5, 4)
	for i in ROWS:
		grid.add_child(_make_row())
	_empty = _label("", 24, MUTED)
	_empty.position = Vector2(20, 16)
	list.add_child(_empty)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	v.add_child(foot)
	_msg = _label("", 22, TEXT)
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_msg.custom_minimum_size.x = 300
	foot.add_child(_msg)
	_count = _label("", 20, MUTED)
	foot.add_child(_count)
	_make_note()
	_viewer = preload("res://image_viewer.gd").new()
	add_child(_viewer)
	_viewer.closed.connect(func() -> void:
		_panel.visible = true
		_redraw()
		hints_changed.emit())
	_viewer.hints_changed.connect(func() -> void: hints_changed.emit())

func _make_note() -> void:
	_note = preload("res://notepad.gd").new()
	add_child(_note)
	_note.closed.connect(func() -> void:
		_panel.visible = true
		_redraw()
		hints_changed.emit())
	_note.hints_changed.connect(func() -> void: hints_changed.emit())
	_note.keyboard_requested.connect(func(t: String, i: String, cb: Callable) -> void: keyboard_requested.emit(t, i, cb))

## One square: a big icon for what it is, its name under it (two lines at most) and a small detail line.
func _make_row() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = TILE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Themes.ink(0.05)
	sb.set_corner_radius_all(Themes.r(14))
	sb.set_content_margin_all(6)
	sb.border_color = SELECT
	p.add_theme_stylebox_override("panel", sb)
	# Fills up from the bottom while A is held, so the hold to pick up shows.
	var fill := ProgressBar.new()
	fill.show_percentage = false
	fill.max_value = 1.0
	fill.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	fill.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(SELECT, 0.35)
	fsb.set_corner_radius_all(Themes.r(10))
	fill.add_theme_stylebox_override("fill", fsb)
	p.add_child(fill)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.custom_minimum_size = Vector2(64, 56)
	v.add_child(icon)
	# The name sits in a clipped strip: two wrapped lines normally, one line that scrolls sideways when chosen and too long.
	var clip := Control.new()
	clip.clip_contents = true
	clip.custom_minimum_size = Vector2(TILE.x - 16, NAME_H)
	v.add_child(clip)
	var name_l := _label("", NAME_FS, TEXT)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clip.add_child(name_l)
	var detail := _label("", 13, MUTED)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.custom_minimum_size = Vector2(TILE.x - 16, 0)
	v.add_child(detail)
	# The carried thing's icon, floating over the square it is being moved over.
	var ghost := TextureRect.new()
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ghost.visible = false
	p.add_child(ghost)
	_rows.append({"panel": p, "fill": fill, "icon": icon, "name": name_l, "detail": detail, "style": sb, "ghost": ghost, "box": v, "clip": clip})
	return p

## What kind of file this is, from its ending: picks its icon.
const KINDS := {
	"image": ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "tga", "avif", "heic"],
	"video": ["mp4", "mkv", "webm", "avi", "mov", "m4v", "wmv", "flv"],
	"audio": ["mp3", "flac", "ogg", "wav", "m4a", "opus", "aac", "wma"],
	"archive": ["zip", "7z", "rar", "tar", "gz", "xz", "zst", "bz2", "tgz"],
	"disc": ["iso", "chd", "cue", "bin", "cso", "pbp", "elf", "img", "gcm", "rvz", "wbfs", "nsp", "xci", "3ds", "nds", "gba", "gb", "gbc", "sfc", "smc", "nes", "n64", "z64"],
	"doc": ["pdf", "txt", "md", "doc", "docx", "odt", "rtf", "epub", "log", "csv", "xlsx", "ods"],
	"code": ["gd", "sh", "py", "js", "json", "cfg", "ini", "conf", "toml", "yaml", "yml", "xml", "html", "css", "c", "cpp", "h", "rs"],
	"app": ["appimage", "exe", "desktop", "deb", "rpm", "flatpakref", "msi", "bat"],
}

func _file_kind(name: String) -> String:
	var ext := name.get_extension().to_lower()
	for k in KINDS:
		if ext in KINDS[k]:
			return k
	return "file"

func _icon_for(it: Dictionary) -> Texture2D:
	match str(it["kind"]):
		"home":
			return Icons.texture("home", Icons.svg_home(), 56)
		"drive":
			return Icons.texture("drive", Icons.svg_drive(), 56)
		"trash":
			return Icons.texture("trash", Icons.svg_trash(), 56)
		"dir":
			var nm := str(it["name"])
			if str(it["path"]).get_base_dir() == OS.get_environment("HOME") and nm.to_lower() in ["music", "pictures", "downloads", "documents", "videos", "desktop", "games"]:
				return Icons.texture("folder_" + nm.to_lower(), Icons.svg_folder_named(nm), 56)
			return Icons.texture("folder", Icons.svg_folder(), 56)
		"up":
			return Icons.texture("fx_up", Icons.svg_file_up(), 56)
	var k := _file_kind(str(it["name"]))
	return Icons.texture("fx_" + k, Icons.svg_file_kind(k), 56)

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

# ---------- Open / close ----------
func open() -> void:
	is_open = true
	visible = true
	_carry = {}
	_pick_exts = []
	_pick_done = Callable()
	_press_ms = -1
	_msg.text = ""
	_show_drives()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	hints_changed.emit()

func close() -> void:
	if not is_open:
		return
	if _viewer.is_open:
		_viewer.close()
	if _note.is_open:
		_note._save_and_close()  # leaving Files while editing still saves
	is_open = false
	visible = false
	_carry = {}
	_press_ms = -1
	_pick_exts = []  # backed out without choosing: nothing is handed over
	_pick_done = Callable()
	closed.emit()

## Opens Files to choose one file whose ending is in exts (lower case, no dot). done(path) is called with it, after
## Files has closed. Backing out of the list of drives closes Files without calling it.
func pick(note: String, exts: Array, verb: String, done: Callable) -> void:
	open()
	_pick_exts = exts
	_pick_done = done
	_pick_note = note
	_pick_verb = verb
	_show_drives()  # again, now without the Trash
	_msg.text = note
	hints_changed.emit()

func _picking() -> bool:
	return not _pick_exts.is_empty()

func _can_pick(it: Dictionary) -> bool:
	return _picking() and str(it.get("kind", "")) == "file" and str(it.get("path", "")).get_extension().to_lower() in _pick_exts

## The hint bar's items while the browser is open (the control center draws them).
func hints() -> Array:
	if _viewer != null and _viewer.is_open:
		return _viewer.hints()
	if _note != null and _note.is_open:
		return _note.hints()
	var it := _cur()
	var kind: String = it.get("kind", "")
	if _picking():
		var pick_items: Array = [["dpad", "Choose"]]
		if _can_pick(it):
			pick_items.append(["accept", _pick_verb])
		elif kind != "file" and not it.is_empty():
			pick_items.append(["accept", "Open"])
		pick_items.append(["back", "Close" if _dir == "" else "Up"])
		return pick_items
	if not _carry.is_empty():
		var target := _drop_target()
		var acc := "Put it here"
		if target != _dir and target != "":
			acc = "Put it in " + (str(it["name"]) if kind != "up" else "the folder above")
		return [["dpad", "Move it"], ["accept", acc], ["back", "Up"], ["back", "Hold to put it back"]]
	var items: Array = [["dpad", "Choose"]]
	if _trash:
		if not it.is_empty():
			items.append(["accept", "Put back"])
			items.append(["north", "Hold to delete"])
		items.append(["west", "Empty Trash"])
		items.append(["back", "Up"])
		return items
	if (kind != "file" or str(it.get("path", "")).get_extension().to_lower() in NOTE_EXTS or _viewer.is_image(str(it.get("path", "")))) and not it.is_empty():
		items.append(["accept", "Open"])
	if _dir != "" and not it.is_empty():
		items.append(["accept", "Hold to move"])
		if kind == "file" and _is_archive(str(it["name"])):
			items.append(["west", "Extract"])
		if not _protected(str(it["path"])):
			items.append(["north", "Hold to delete"])
	items.append(["back", "Close" if _dir == "" else "Up"])
	return items

# ---------- Listing ----------
func _show_drives(select_path := "") -> void:
	_dir = ""
	_trash = false
	_empty_armed = false
	_drive_root = ""
	_drive_name = ""
	_items = drives()
	var sc := steam_common_dirs()
	for i in sc.size():
		_items.append({"name": "Steam games" if i == 0 else "Steam games %d" % (i + 1), "path": sc[i], "kind": "drive", "detail": ""})
	if bool(Settings.get_value("files_show_all", false)):
		_items.append({"name": "System", "path": "/", "kind": "drive", "detail": ""})  # the whole disk, from the top
	if not _picking():
		_items.append({"name": "Trash", "path": _trash_dir(), "kind": "trash", "detail": ""})
	for d in _items:
		d["detail"] = _free.get(d["path"], "")
	_sel = 0
	for i in _items.size():
		if _items[i]["path"] == select_path:
			_sel = i
	_top = 0
	_read_free_space()
	_redraw()

func _open_dir(path: String, select_name := "") -> void:
	var d := DirAccess.open(path)
	if d == null:
		_msg.text = "Can't open %s" % path.get_file()
		return
	_dir = path
	var show_all := bool(Settings.get_value("files_show_all", false))  # Developer menu > Show hidden folders in Files
	d.include_hidden = show_all
	var dirs: Array = []
	var files: Array = []
	for n: String in d.get_directories():
		if show_all or not n.begins_with("."):
			dirs.append(n)
	for n: String in d.get_files():
		if _picking() and not (n.get_extension().to_lower() in _pick_exts):
			continue  # choosing a file: only the ones that can be chosen are listed
		if show_all or not n.begins_with("."):
			files.append(n)
	var by_name := func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0
	dirs.sort_custom(by_name)
	files.sort_custom(by_name)
	_items = []
	for n: String in dirs:
		_items.append({"name": n, "path": path.path_join(n), "kind": "dir", "detail": "Folder"})
	for n: String in files:
		_items.append({"name": n, "path": path.path_join(n), "kind": "file", "detail": ""})
	_add_carry_tiles()
	_sel = 1 if not _carry.is_empty() and _items.size() > 1 else 0  # carrying: start on the first real square, not Back
	for i in _items.size():
		if _items[i]["name"] == select_name:
			_sel = i
	_top = 0
	_sizes.clear()
	_redraw()

## While something is carried, the first two squares of a folder are "Move here" and "Cancel".
## While something is carried, the first square of a folder is "Back": drop it on Back to move it up a level, or
## rest on it to go up and keep looking.
func _add_carry_tiles() -> void:
	if _carry.is_empty() or _dir == "":
		return
	var up := "" if _dir == _drive_root else _dir.get_base_dir()
	_items.push_front({"name": "Back", "path": up, "kind": "up", "detail": "Up a level" if up != "" else "Drives"})

# ---------- Protected places ----------
## Things Files never moves or deletes: Tephra itself, Steam and its game libraries, emulator and system folders,
## the drives themselves and the standard folders in Home (their contents are fine).
## Plain-text files that open in the Notepad (Cross on them).
const NOTE_EXTS := ["txt", "md", "log", "cfg", "ini", "conf", "csv"]

const KEEP_HOME := ["tephra", "Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos", "Games", "Public", "Templates"]

func _protected(path: String) -> bool:
	var home := OS.get_environment("HOME")
	path = path.simplify_path()
	if path == "" or path == "/" or path == home:
		return true
	for d in drives():
		if path == str(d["path"]):
			return true
	if path.get_base_dir() == home and path.get_file() in KEEP_HOME:
		return true
	var res := ProjectSettings.globalize_path("res://").simplify_path()
	if path == res or res.begins_with(path + "/") or path.begins_with(res + "/"):
		return true  # Tephra's own files (and every folder they sit in)
	for bit in ["/tephra/", "/.steam", "/Steam/", "/steamapps", "/SteamLibrary", "/compatdata", "/Proton", "/.var/app/", "/pcsx2", "/PCSX2", "/bios", "/BIOS"]:
		if (path + "/").contains(bit):
			return true
	for sys in ["/usr", "/etc", "/boot", "/bin", "/sbin", "/lib", "/lib64", "/opt", "/var", "/proc", "/sys", "/dev", "/run", "/root", "/srv", "/tmp"]:
		if path == sys or (path.begins_with(sys + "/") and not path.begins_with("/run/media/")):
			return true
	return false

## Deleting sends things to the Trash (gio trash, the desktop's own), so a mistake can be undone from there.
func _delete() -> void:
	var it := _cur()
	if it.is_empty() or not str(it["kind"]) in ["dir", "file"]:
		return
	var path := str(it["path"])
	var nm := str(it["name"])
	if _trash:
		_purge([it], "Deleted %s for good." % nm)
		return
	if _protected(path):
		_msg.text = "%s is protected and can't be deleted." % nm
		return
	_busy = true
	_msg.text = "Deleting %s..." % nm
	var sel := _sel
	_task_id = WorkerThreadPool.add_task(func() -> void:
		var out := []
		var ok := OS.execute("gio", ["trash", "--", path], out, true) == 0
		if not ok:
			ok = OS.execute("kioclient", ["move", path, "trash:/"], out, true) == 0
		ok = ok and not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path))
		_delete_done.call_deferred(ok, nm, sel))

# ---------- Trash ----------
func _trash_dir() -> String:
	return OS.get_environment("HOME") + "/.local/share/Trash/files"

## Puts a trashed item back where it came from (read from its .trashinfo), then removes the info file.
func _restore(it: Dictionary) -> void:
	var nm := str(it["name"])
	var info := _trash_dir().get_base_dir().path_join("info/" + nm + ".trashinfo")
	var dest := ""
	var f := FileAccess.open(info, FileAccess.READ)
	if f != null:
		for line in f.get_as_text().split("\n"):
			if line.begins_with("Path="):
				dest = line.substr(5).strip_edges().uri_decode()
	if dest == "":
		dest = OS.get_environment("HOME").path_join(nm)
	if FileAccess.file_exists(dest) or DirAccess.dir_exists_absolute(dest):
		dest = dest.get_base_dir().path_join("Restored " + dest.get_file())
	var src := str(it["path"])
	_busy = true
	_msg.text = "Putting back %s..." % nm
	var sel := _sel
	_task_id = WorkerThreadPool.add_task(func() -> void:
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var out := []
		var ok := OS.execute("mv", ["--", src, dest], out, true) == 0
		if ok:
			DirAccess.remove_absolute(info)
		_trash_done.call_deferred(ok, "Put %s back in %s." % [nm, dest.get_base_dir().get_file()], sel))

## Deletes the given trashed items for good (also used to empty the whole Trash).
func _purge(list: Array, done_text: String) -> void:
	var paths: Array = []
	for it in list:
		paths.append([str(it["path"]), _trash_dir().get_base_dir().path_join("info/" + str(it["name"]) + ".trashinfo")])
	_busy = true
	_msg.text = "Deleting..."
	var sel := _sel
	_task_id = WorkerThreadPool.add_task(func() -> void:
		var ok := true
		for pr in paths:
			var out := []
			if OS.execute("rm", ["-rf", "--", pr[0]], out, true) != 0:
				ok = false
			DirAccess.remove_absolute(pr[1])
		_trash_done.call_deferred(ok, done_text, sel))

func _trash_done(ok: bool, text: String, sel: int) -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	_busy = false
	_empty_armed = false
	if not is_open:
		return
	_open_dir(_dir)
	_sel = clampi(sel, 0, maxi(_items.size() - 1, 0))
	_msg.text = text if ok else "Something couldn't be removed."
	_redraw()

func _delete_done(ok: bool, nm: String, sel: int) -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	_busy = false
	if not is_open:
		return
	_open_dir(_dir)
	_sel = clampi(sel, 0, maxi(_items.size() - 1, 0))
	_msg.text = ("Moved %s to the Trash." % nm) if ok else "Couldn't delete %s." % nm
	_redraw()

func _cur() -> Dictionary:
	return _items[_sel] if _sel >= 0 and _sel < _items.size() else {}

func _here_name() -> String:
	return _drive_name if _dir == _drive_root else _dir.get_file()

func _redraw() -> void:
	_sel = clampi(_sel, 0, maxi(_items.size() - 1, 0))
	var row := _sel / COLS
	if row < _top / COLS:
		_top = row * COLS
	elif row >= _top / COLS + GRID_ROWS:
		_top = (row - GRID_ROWS + 1) * COLS
	if _dir == "":
		_title.text = "Files"
		_path.text = "Drives"
	else:
		var rel := _dir.substr(_drive_root.length()).trim_prefix("/")
		_title.text = _drive_name + ("" if rel == "" else "  ›  " + "  ›  ".join(rel.split("/", false)))
		var home := OS.get_environment("HOME")
		_path.text = "~" + _dir.substr(home.length()) if _dir == home or _dir.begins_with(home + "/") else _dir
	for i in ROWS:
		var r: Dictionary = _rows[i]
		var idx := _top + i
		var p: Control = r["panel"]
		p.visible = idx < _items.size()
		if not p.visible:
			continue
		var it: Dictionary = _items[idx]
		var on := idx == _sel
		var carried := not _carry.is_empty() and str(it["path"]) == str(_carry["path"])
		var st: StyleBoxFlat = r["style"]
		st.bg_color = Themes.ink(0.16) if on else Themes.ink(0.05)
		st.set_border_width_all(3 if on else 0)
		var nl: Label = r["name"]
		nl.text = str(it["name"])
		nl.add_theme_color_override("font_color", TEXT if on else MUTED)
		var long_name := _name_too_long(nl)
		_name_layout(nl, on and long_name, long_name)
		var kind: String = it["kind"]
		var icon: TextureRect = r["icon"]
		icon.texture = _icon_for(it)
		if kind == "file" and _file_kind(str(it["name"])) in ["image", "video"]:
			var pth := str(it["path"])
			if _thumbs.get(pth) != null:
				icon.texture = _thumbs[pth]
			elif not _thumbs.has(pth) and not pth in _thumb_want:
				_thumb_want.append(pth)
		icon.modulate = Color(1, 1, 1, 0.35 if carried else (1.0 if on else 0.75))
		var det: Label = r["detail"]
		det.text = "Moving" if carried else (_size_text(str(it["path"])) if kind == "file" else str(it["detail"]))
		(r["fill"] as ProgressBar).value = 0.0
		((r["fill"] as ProgressBar).get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(SELECT, 0.35)
		# While carrying: the carried icon floats over the chosen square, and the square's own content steps back.
		var ghost: TextureRect = r["ghost"]
		ghost.visible = on and not _carry.is_empty()
		if ghost.visible:
			ghost.texture = _carry["icon"]
		(r["box"] as Control).modulate.a = 0.35 if ghost.visible else 1.0
		if not ghost.visible:
			ghost.rotation = 0.0
		if not carried:
			(r["box"] as Control).rotation = 0.0
	_load_thumbs()
	if _scroll_sel != _sel:
		_scroll_sel = _sel
		_scroll_t = 0.0
	_empty.visible = _items.is_empty()
	_empty.text = ("The Trash is empty." if _trash else "This folder is empty.") if _dir != "" else "No drives found."
	_count.text = "%d / %d" % [_sel + 1, _items.size()] if _items.size() > ROWS else ""
	_chip.visible = not _carry.is_empty()
	if _chip.visible:
		var cn := str(_carry["name"])
		_chip_label.text = "Moving: " + (cn if cn.length() <= 32 else cn.left(30) + "…")
	hints_changed.emit()

# File sizes are read only for the rows on screen, and kept until the folder changes.
func _size_text(path: String) -> String:
	if _sizes.has(path):
		return _sizes[path]
	var t := ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		t = String.humanize_size(f.get_length())
	_sizes[path] = t
	return t

# Free space comes from df, in the background, so the list never waits on a slow or sleeping disk.
func _read_free_space() -> void:
	if _df_task != -1:
		return
	var paths: Array = []
	for d in _items:
		paths.append(str(d["path"]))
	_df_task = WorkerThreadPool.add_task(func() -> void:
		var res := {}
		for p: String in paths:
			var out := []
			if OS.execute("df", ["-h", "--output=avail", p], out) == 0 and not out.is_empty():
				var lines := str(out[0]).strip_edges().split("\n", false)
				if lines.size() >= 2:
					res[p] = lines[1].strip_edges() + " free"
		_free_done.call_deferred(res))

func _free_done(res: Dictionary) -> void:
	WorkerThreadPool.wait_for_task_completion(_df_task)
	_df_task = -1
	_free.merge(res, true)
	if is_open and _dir == "":
		for d in _items:
			d["detail"] = _free.get(d["path"], "")
		_redraw()

func _exit_tree() -> void:
	if _thumb_task != -1:
		WorkerThreadPool.wait_for_task_completion(_thumb_task)
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
	if _df_task != -1:
		WorkerThreadPool.wait_for_task_completion(_df_task)
	for j in _ext_jobs:
		WorkerThreadPool.wait_for_task_completion(int(j["id"]))

# ---------- Input (from control_center.gd) ----------
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if _viewer.is_open:
		return _viewer.handle_input(event)
	if _note.is_open:
		return _note.handle_input(event)
	if _busy:
		return true  # a move is running: wait for it
	if _picking():
		if event.is_action_pressed("ui_cancel"):
			_go_up()
		elif event.is_action_pressed("ui_accept"):
			_enter(_cur())
		return true
	var north_down: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == Glyphs.north_button()) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Y)
	var north_up: bool = (event is InputEventJoypadButton and not event.pressed and event.button_index == Glyphs.north_button()) \
		or (event is InputEventKey and not event.pressed and event.keycode == KEY_Y)
	var west_down: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == Glyphs.west_button()) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X)
	if west_down:
		if _trash:
			if _items.is_empty():
				_msg.text = "The Trash is already empty."
			elif _empty_armed:
				_purge(_items.duplicate(), "The Trash is empty.")
			else:
				_empty_armed = true
				_msg.text = "Press %s again to empty the whole Trash." % TephraGlyphs.btn("west")
		elif _carry.is_empty() and _dir != "":
			_extract()
		return true
	if north_down:
		if _carry.is_empty() and _dir != "" and str(_cur().get("kind", "")) in ["dir", "file"]:
			if _protected(str(_cur()["path"])):
				_msg.text = "%s is protected and can't be deleted." % str(_cur()["name"])
			else:
				_del_ms = Time.get_ticks_msec()
				_msg.text = "Keep holding to delete %s." % str(_cur()["name"])
		return true
	if north_up:
		if _del_ms >= 0:
			_del_ms = -1
			_msg.text = ""
			_redraw()
		return true
	if event.is_action_pressed("ui_cancel"):
		_press_ms = -1
		if not _carry.is_empty():
			_back_ms = Time.get_ticks_msec()  # carrying: a press goes up a folder, a hold puts it back (see _process)
		else:
			_go_up()
	elif event.is_action_released("ui_cancel"):
		if _back_ms >= 0:
			_back_ms = -1
			if not _carry.is_empty() and _dir != "":
				_go_up()  # (on the list of drives there is no further up: it stays open)
	elif event.is_action_pressed("ui_accept"):
		if not _carry.is_empty():
			var to := _drop_target()
			if to != "":
				_drop(to)
		elif _dir == "":
			_enter(_cur())  # drives can't be picked up: open straight away
		else:
			_press_ms = Time.get_ticks_msec()  # a short press opens (on release), a long one picks up
	elif event.is_action_released("ui_accept"):
		if _press_ms >= 0:
			_press_ms = -1
			_enter(_cur())
	return true

## Up/Down: a row up or down the grid. dir = -1 for up.
func vertical(dir: int) -> void:
	if _viewer.is_open:
		_viewer.vertical(dir)
		return
	if _note.is_open:
		_note.vertical(dir)
		return
	if _items.is_empty() or _busy:
		return
	_press_ms = -1
	var to := _sel + dir * COLS
	if to < 0:
		return
	if to >= _items.size():
		if _sel / COLS == (_items.size() - 1) / COLS:
			return
		to = _items.size() - 1  # the last row is short: go to its last square
	_sel = to
	_hover_ms = Time.get_ticks_msec()
	_spring_armed = true
	_redraw()

## Left/Right: the square before or after.
func move(dir: int) -> void:
	if _viewer.is_open:
		_viewer.move(dir)
		return
	if _note.is_open:
		_note.move(dir)
		return
	if _items.is_empty() or _busy:
		return
	_press_ms = -1
	_sel = clampi(_sel + dir, 0, _items.size() - 1)
	_hover_ms = Time.get_ticks_msec()
	_spring_armed = true
	_redraw()

## Where Cross would put the carried thing: into the folder (or drive) it hovers over, up a level on Back, otherwise
## into the folder that is open. "" = nowhere (the list of drives itself).
func _drop_target() -> String:
	var it := _cur()
	match str(it.get("kind", "")):
		"dir", "home", "drive":
			if str(it["path"]) != str(_carry.get("path", "")):
				return str(it["path"])
		"up":
			return str(it["path"])
	return _dir

func _cancel_move() -> void:
	var from := str(_carry.get("path", ""))
	_carry = {}
	_msg.text = ""
	if from != "" and from.get_base_dir() != _dir and DirAccess.dir_exists_absolute(from.get_base_dir()):
		if not (from.begins_with(_drive_root + "/")):
			_drive_root = from.get_base_dir()
			_drive_name = _drive_root.get_file()
		_open_dir(from.get_base_dir(), from.get_file())  # back to where it was
	else:
		_refresh_listing()
		if from != "":
			for i in _items.size():
				if str(_items[i]["path"]) == from:
					_sel = i
			_redraw()

## The same folder (or the drives) again, keeping the selection on the same thing.
func _refresh_listing() -> void:
	var keep := str(_cur().get("name", ""))
	if _dir == "":
		_show_drives()
	else:
		_open_dir(_dir, keep)

func _process(delta: float) -> void:
	if not is_open:
		return
	_scroll_name(delta)
	var now := Time.get_ticks_msec()
	if _back_ms >= 0 and now - _back_ms >= HOLD_MS:
		_back_ms = -1
		if not _carry.is_empty():
			_cancel_move()  # held Circle: back where it was
			return
	if not _carry.is_empty():
		# Carrying: the icon wiggles like apps being rearranged on a phone, and resting on a folder opens it.
		var t := now / 1000.0
		for i in ROWS:
			var r: Dictionary = _rows[i]
			var idx := _top + i
			if idx >= _items.size():
				continue
			var ghost: TextureRect = r["ghost"]
			if ghost.visible:
				ghost.pivot_offset = ghost.size * 0.5
				ghost.rotation = deg_to_rad(4.0) * sin(t * 22.0)
				ghost.scale = Vector2.ONE * (1.12 + 0.02 * sin(t * 11.0))
			if str(_items[idx]["path"]) == str(_carry["path"]):
				var box: Control = r["box"]
				box.pivot_offset = box.size * 0.5
				box.rotation = deg_to_rad(2.5) * sin(t * 20.0 + 1.0)
		var kind := str(_cur().get("kind", ""))
		var row := _sel - _top
		var opens := _spring_armed and kind in ["dir", "up", "home", "drive"] and str(_cur().get("path", "")) != str(_carry["path"])
		var k := clampf(float(now - _hover_ms) / SPRING_MS, 0.0, 1.0) if opens else 0.0
		if row >= 0 and row < ROWS:
			(_rows[row]["fill"] as ProgressBar).value = maxf(k - 0.25, 0.0) / 0.75  # shows after a short pause
		if opens and k >= 1.0:
			_hover_ms = now
			_spring_armed = false
			if kind == "up":
				_go_up()
			else:
				_enter(_cur())
		return
	if _del_ms >= 0:
		var dk := clampf(float(now - _del_ms) / DELETE_MS, 0.0, 1.0)
		var drow := _sel - _top
		if drow >= 0 and drow < ROWS:
			var r: Dictionary = _rows[drow]
			(r["fill"] as ProgressBar).value = dk
			((r["fill"] as ProgressBar).get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.9, 0.2, 0.18, 0.5)
			var box: Control = r["box"]
			box.pivot_offset = box.size * 0.5
			box.rotation = deg_to_rad(3.0 * dk) * sin(now / 1000.0 * 30.0)  # shakes harder as it gets close
		if dk >= 1.0:
			_del_ms = -1
			_delete()
		return
	if _press_ms < 0:
		return
	var held := now - _press_ms
	var row := _sel - _top
	if row >= 0 and row < ROWS and _dir != "" and str(_cur().get("kind", "")) in ["dir", "file"]:
		(_rows[row]["fill"] as ProgressBar).value = clampf(float(held) / HOLD_MS, 0.0, 1.0)
	if held >= HOLD_MS:
		_press_ms = -1
		_pick_up()

func _enter(it: Dictionary) -> void:
	if it.is_empty():
		return
	if _trash and str(it["kind"]) in ["dir", "file"]:
		_restore(it)
		return
	match str(it["kind"]):
		"trash":
			DirAccess.make_dir_recursive_absolute(_trash_dir())
			_trash = true
			_empty_armed = false
			_drive_root = _trash_dir()
			_drive_name = "Trash"
			_open_dir(_drive_root)
		"home", "drive":
			_drive_root = str(it["path"])
			_drive_name = str(it["name"])
			_msg.text = _pick_note if _picking() else ("" if _carry.is_empty() else _msg.text)
			_open_dir(_drive_root)
		"dir":
			_open_dir(str(it["path"]))
		_:
			if _picking():
				if _can_pick(it):
					var cb := _pick_done
					var chosen := str(it["path"])
					close()
					cb.call(chosen)
				else:
					_msg.text = "%s can't be chosen. %s" % [str(it["name"]), _pick_note]
				return
			if _carry.is_empty() and _viewer.is_image(str(it["path"])):
				if _viewer.open_file(str(it["path"])):
					_panel.visible = false
				else:
					_msg.text = "Can't open %s." % str(it["name"])
				return
			if _carry.is_empty() and str(it["path"]).get_extension().to_lower() in NOTE_EXTS:
				if _note.open_file(str(it["path"])):
					_panel.visible = false  # the Notepad takes the whole place
				else:
					_msg.text = "Can't open %s (too big or not readable)." % str(it["name"])
				return
			_msg.text = "Hold to pick up a file and move it." if _carry.is_empty() else _msg.text
			_redraw()

func _go_up() -> void:
	if _dir == "":
		close()
		return
	if _dir == _drive_root:
		_show_drives(_drive_root)
		return
	var from := _dir.get_file()
	_open_dir(_dir.get_base_dir(), from)

# ---------- Moving ----------
func _pick_up() -> void:
	var it := _cur()
	if it.is_empty() or _dir == "" or _trash:
		return
	if not str(it["kind"]) in ["dir", "file"]:
		return
	if _protected(str(it["path"])):
		_msg.text = "%s is protected and can't be moved." % str(it["name"])
		return
	_carry = {"name": it["name"], "path": it["path"], "kind": it["kind"], "icon": _icon_for(it)}
	_msg.text = "Move it over a folder and press %s. %s goes up a folder, hold %s to put it back." % [TephraGlyphs.btn("accept"), TephraGlyphs.btn("back"), TephraGlyphs.btn("back")]
	_hover_ms = Time.get_ticks_msec()
	_refresh_listing()

func _drop(to := "") -> void:
	if to == "":
		to = _dir
	var src: String = _carry["path"]
	var nm: String = _carry["name"]
	var dst := to.path_join(nm)
	if src.get_base_dir() == to:
		_cancel_move()  # placed back where it was: nothing to do
		return
	if _carry["kind"] == "dir" and (to == src or to.begins_with(src + "/")):
		_msg.text = "A folder can't go inside itself."
		return
	if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
		_msg.text = "There's already a %s here." % nm
		return
	if not FileAccess.file_exists(src) and not DirAccess.dir_exists_absolute(src):
		_msg.text = "%s is gone." % nm
		_carry = {}
		_redraw()
		return
	if DirAccess.rename_absolute(src, dst) == OK:
		_moved(true, nm, to)
		return
	# Another drive: rename can't cross filesystems, so mv copies it over in the background.
	_busy = true
	_msg.text = "Moving %s..." % nm
	var target := to
	_task_id = WorkerThreadPool.add_task(func() -> void:
		var out := []
		var code := OS.execute("mv", ["-n", "--", src, target + "/"], out, true)
		var ok := code == 0 and not (FileAccess.file_exists(src) or DirAccess.dir_exists_absolute(src))
		_move_done.call_deferred(ok, nm, target))

func _move_done(ok: bool, nm: String, target: String) -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	_busy = false
	if is_open:
		_moved(ok, nm, target)
	else:
		_carry = {}

func _moved(ok: bool, nm: String, to := "") -> void:
	_carry = {}
	if to == "" or not ok:
		to = _dir
	if not (to == _drive_root or to.begins_with(_drive_root + "/")):
		_drive_root = to  # dropped on another drive: that drive is the root now
		_drive_name = to.get_file()
	_open_dir(to, nm)  # follow it to where it went
	_msg.text = ("Moved %s to %s." % [nm, _here_name()]) if ok else "Couldn't move %s." % nm
	_redraw()

# ---------- Long names ----------
func _name_too_long(l: Label) -> bool:
	var f := l.get_theme_font("font")
	var w := TILE.x - 16
	if f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS).x > w * 1.85:
		return true  # more than two lines' worth
	for word in l.text.split(" ", false):
		if f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS).x > w:
			return true  # one word wider than the square gets cut mid-word
	return false

## Two centred, wrapped lines (cut off with "…"), or one line ready to scroll.
func _name_layout(l: Label, scroll: bool, long_name := false) -> void:
	l.set_meta("scroll", scroll)
	if scroll:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.max_lines_visible = 1
		var tw := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS).x
		l.size = Vector2(tw + 4, NAME_H)
		l.position = Vector2.ZERO
	else:
		# Breaks between words only; a name too long for two lines (or one huge word) is one line ending in "…".
		l.autowrap_mode = TextServer.AUTOWRAP_OFF if long_name and not " " in l.text else TextServer.AUTOWRAP_WORD
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.max_lines_visible = 2
		l.position = Vector2.ZERO
		l.size = Vector2(TILE.x - 16, NAME_H)

## The chosen square's long name slides left to show its end, rests, then jumps back to the start.
func _scroll_name(delta: float) -> void:
	var row := _sel - _top
	if row < 0 or row >= ROWS or _sel >= _items.size():
		return
	var l: Label = _rows[row]["name"]
	if not bool(l.get_meta("scroll", false)):
		return
	_scroll_t += delta
	var extra := maxf(l.size.x - (TILE.x - 16), 0.0)
	var run := extra / SCROLL_SPEED
	var cycle := SCROLL_WAIT * 2.0 + run
	var t := fmod(_scroll_t, cycle)
	l.position.x = -clampf((t - SCROLL_WAIT) * SCROLL_SPEED, 0.0, extra)

# ---------- Extracting ----------
const ARCHIVE_ENDS := [".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz", ".tbz2", ".txz", ".zip", ".rar", ".7z", ".tar", ".gz", ".xz", ".bz2", ".zst"]

static func _archive_end(name: String) -> String:
	var low := name.to_lower()
	for e in ARCHIVE_ENDS:
		if low.ends_with(e):
			return e
	return ""

static func _is_archive(name: String) -> bool:
	return _archive_end(name) != ""

## Square on a .zip / .rar / .7z / .tar... unpacks it into a folder with the archive's name and then removes the archive.
## It runs in the background, so you can keep browsing and moving things meanwhile (and extract several at once).
## A single folder inside the archive is not nested: its contents go straight into the named folder.
func _extract() -> void:
	var it := _cur()
	if it.is_empty() or str(it["kind"]) != "file" or not _is_archive(str(it["name"])):
		return
	var src := str(it["path"])
	var nm := str(it["name"])
	for j in _ext_jobs:
		if j["src"] == src:
			_msg.text = "%s is already being extracted." % nm
			return
	_msg.text = "Extracting %s... you can keep going." % nm
	var job := {"id": -1, "src": src}
	_ext_jobs.append(job)
	job["id"] = WorkerThreadPool.add_task(func() -> void:
		var res := _extract_job(src)
		_extract_done.call_deferred(res, nm, job))
	_redraw()

func _extract_done(res: Dictionary, nm: String, job: Dictionary) -> void:
	WorkerThreadPool.wait_for_task_completion(int(job["id"]))
	_ext_jobs.erase(job)
	if not is_open:
		return
	if bool(res["ok"]):
		_msg.text = "Extracted %s into %s." % [nm, str(res["out"]).get_file()]
	else:
		_msg.text = str(res["err"])
	if _dir != "" and _dir == str(job["src"]).get_base_dir() and _carry.is_empty() and not _busy:
		_refresh_listing()
	else:
		_redraw()

static func _has(tool: String) -> bool:
	return OS.execute("sh", ["-c", "command -v \"$0\" >/dev/null", tool]) == 0

static func _unique(path: String) -> String:
	if not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
		return path
	var n := 2
	while FileAccess.file_exists("%s (%d)" % [path, n]) or DirAccess.dir_exists_absolute("%s (%d)" % [path, n]):
		n += 1
	return "%s (%d)" % [path, n]

## Runs on a worker thread. Tries the unpackers in turn (bsdtar comes with every Arch system, so it is the last resort).
static func _extract_job(src: String, hoist := true, remove_src := true) -> Dictionary:
	var base := src.get_base_dir()
	var fname := src.get_file()
	var end := _archive_end(fname)
	var stem := fname.left(fname.length() - end.length())
	if stem.to_lower().ends_with(".part1"):
		stem = stem.left(stem.length() - 6)
	if stem == "":
		stem = "Extracted"
	if not DirAccess.dir_exists_absolute(base) or OS.execute("test", ["-w", base]) != 0:
		return {"ok": false, "err": "Can't write in this folder."}
	var tmp := base.path_join(".tephra-extract-%d" % Time.get_ticks_usec())
	if DirAccess.make_dir_absolute(tmp) != OK:
		return {"ok": false, "err": "Can't write in this folder."}
	var tries: Array = []
	var bsd := ["bsdtar", "-xf", src, "-C", tmp]
	var sz := ["7z", "x", "-y", "-aos", "-o" + tmp, src]
	match end:
		".rar":
			tries = [["unrar", "x", "-o-", "-y", src, tmp + "/"], sz, bsd]
		".zip":
			tries = [["unzip", "-q", "-n", src, "-d", tmp], sz, bsd]
		".7z":
			tries = [sz, ["7za", "x", "-y", "-aos", "-o" + tmp, src], bsd]
		".gz", ".xz", ".bz2", ".zst":
			var tool: String = {".gz": "gzip", ".xz": "xz", ".bz2": "bzip2", ".zst": "zstd"}[end]
			tries = [["sh", "-c", "\"$0\" -dc -- \"$1\" > \"$2\"", tool, src, tmp.path_join(stem)], bsd]
		_:
			tries = [["tar", "-xf", src, "-C", tmp], bsd]
	var ran := false
	var ok := false
	for t in tries:
		var prog: String = t[0] if t[0] != "sh" else t[3]
		if not _has(prog):
			continue
		ran = true
		var out := []
		var code := OS.execute(t[0], t.slice(1), out, true)
		var entries := _entries(tmp)
		if code == 0 and not entries.is_empty():
			ok = true
			break
		OS.execute("rm", ["-rf", "--", tmp])  # a half-done try: clean out and let the next tool have a go
		DirAccess.make_dir_absolute(tmp)
	if not ok:
		OS.execute("rm", ["-rf", "--", tmp])
		if not ran:
			return {"ok": false, "err": "No unpacker for %s is installed (install 7zip or unrar)." % end.trim_prefix(".")}
		return {"ok": false, "err": "Couldn't extract %s. It may be damaged or need a password." % fname}
	var entries := _entries(tmp)
	var final := _unique(base.path_join(stem))
	if hoist and entries.size() == 1 and DirAccess.dir_exists_absolute(tmp.path_join(entries[0])):
		# One folder inside: it becomes the named folder itself (no folder-in-a-folder).
		if DirAccess.rename_absolute(tmp.path_join(entries[0]), final) != OK:
			OS.execute("rm", ["-rf", "--", tmp])
			return {"ok": false, "err": "Couldn't finish extracting %s." % fname}
		DirAccess.remove_absolute(tmp)
	elif DirAccess.rename_absolute(tmp, final) != OK:
		OS.execute("rm", ["-rf", "--", tmp])
		return {"ok": false, "err": "Couldn't finish extracting %s." % fname}
	if remove_src:
		DirAccess.remove_absolute(src)  # the archive is replaced by its folder
	return {"ok": true, "out": final}

static func _entries(dir: String) -> Array:
	var d := DirAccess.open(dir)
	if d == null:
		return []
	d.include_hidden = true
	return Array(d.get_directories()) + Array(d.get_files())

# ---------- Small pictures ----------
const THUMB := Vector2i(120, 56)
const THUMB_DIRECT := ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga"]  # pictures Godot can open itself

## Loads the small pictures for the squares shown, in the background, a screenful at a time.
func _load_thumbs() -> void:
	if _thumb_task != -1 or _thumb_want.is_empty():
		return
	var batch := _thumb_want.duplicate()
	_thumb_want.clear()
	if _thumbs.size() > 400:
		_thumbs.clear()  # keep memory small after long browsing
	_thumb_task = WorkerThreadPool.add_task(func() -> void:
		var got := {}
		for pth in batch:
			got[pth] = _thumb_image(pth)
		_thumbs_done.call_deferred(got))

func _thumbs_done(got: Dictionary) -> void:
	WorkerThreadPool.wait_for_task_completion(_thumb_task)
	_thumb_task = -1
	for pth in got:
		var img: Image = got[pth]
		_thumbs[pth] = ImageTexture.create_from_image(img) if img != null else null
	if is_open:
		_redraw()

## A file's picture shrunk to fit a square: from the desktop's thumbnail cache when it made one (videos too),
## otherwise read from the picture itself.
static func _thumb_image(pth: String) -> Image:
	var img: Image = null
	var parts: Array = []
	for seg in pth.split("/"):
		parts.append(seg.uri_encode())
	var key := ("file://" + "/".join(parts)).md5_text() + ".png"
	var cache := OS.get_environment("HOME").path_join(".cache/thumbnails")
	for size_dir in ["large", "x-large", "normal"]:
		var f := cache.path_join(size_dir).path_join(key)
		if FileAccess.file_exists(f):
			img = Image.load_from_file(f)
			if img != null:
				break
	if img == null and pth.get_extension().to_lower() in THUMB_DIRECT:
		var fa := FileAccess.open(pth, FileAccess.READ)
		if fa != null and fa.get_length() < 60 * 1024 * 1024:
			fa.close()
			img = Image.load_from_file(pth)
	if img == null or img.is_empty():
		return null
	var k := minf(float(THUMB.x) / img.get_width(), float(THUMB.y) / img.get_height())
	img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	return img
