extends CanvasLayer
## Tephra Album: every screenshot taken with the touchpad click, laid out like the Library.
## Opened from the control center's Album card. Pick a photo to see it nearly full screen with a
## strip of info along the bottom (when it was taken, its size, how big the file is).
##
## Opening is instant: the grid appears straight away and the pictures fill in a moment later.
## They are made on a worker thread and kept as small JPEG copies in user://album_thumbs, so the
## second time they load almost immediately and the screen never stalls decoding big PNGs.

signal closed

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const Rounded = preload("res://rounded.gd")

var BG: Color = Themes.c("bg")
var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var SELECT: Color = Themes.c("select")
const THUMB := Vector2(400, 225)  # 16:9, like the screen
const CAPTION_H := 40.0
const GAP := 26
const EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const VIDEO_EXTENSIONS := ["mp4", "webm", "mkv", "mov"]  # recordings from ~/Videos/Tephra
const THUMB_DIR := "user://album_thumbs"
const THUMB_W := 560

var is_open := false
var _home

var _root: Control
var _count: Label
var _empty: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _hints: HBoxContainer
var _files: Array = []        # [{path, name, time, bytes}] newest first
var _tiles: Array = []
var _images: Array = []       # the TextureRect inside each tile
var _marks: Array = []        # the outline Panel on top of each picture
var _sel := 0
var _cols := 4
var _scroll_tween: Tween
var _thumbs := {}             # path -> small texture (kept while the Album is open)

# Worker thread
var _gen := 0                 # bumps each time the Album opens/closes, so late results are ignored
var _mutex := Mutex.new()
var _results: Array = []      # [gen, path, Image] waiting to become textures
var _task_ids: Array = []

# Full-size viewer
var _viewing := false
var _view: Control
var _view_pic: TextureRect
var _view_bar: Control
var _view_name: Label
var _view_meta: Label
var _view_pos: Label
var _view_hints: HBoxContainer
var _view_token := 0
var _info_on := true
var _delete_armed := ""        # path of the photo waiting for a second press of Delete
var _delete_until := 0
# Select mode (Triangle in the grid): A ticks photos, Square deletes all ticked ones at once.
var _selecting := false
var _picked := {}              # path -> true
var _checks: Array = []        # the tick badge on each tile

func setup(home) -> void:
	_home = home

static func folder() -> String:
	return OS.get_environment("HOME") + "/Pictures/Tephra"

static func video_folder() -> String:
	return OS.get_environment("HOME") + "/Videos/Tephra"

## How many screenshots and recordings there are (the control center card shows this).
static func count_files() -> int:
	var n := 0
	for d in [[folder(), EXTENSIONS], [video_folder(), VIDEO_EXTENSIONS]]:
		var dir := DirAccess.open(d[0])
		if dir == null:
			continue
		for f in dir.get_files():
			if f.get_extension().to_lower() in d[1]:
				n += 1
	return n

func _ready() -> void:
	layer = 81  # above the Library (80), below the launch screen (90) and control center (95)
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
	anim.set("plain", true)  # Temple theme: no desktop windows behind a full page
	_root.add_child(anim)
	anim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	margin.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	v.add_child(head)
	head.add_child(_label("Album", 44, TEXT))
	_count = _label("", 26, MUTED)
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_count)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	v.add_child(_scroll)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 24)
	_scroll.add_child(pad)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	pad.add_child(_grid)

	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(_hints)

	_empty = _label("Nothing here yet.\nClick the touchpad to take a screenshot, or hold it to record.", 30, MUTED)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.visible = false
	_root.add_child(_empty)
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_viewer()

func _exit_tree() -> void:
	_gen += 1  # tell the worker to stop
	for id in _task_ids:
		WorkerThreadPool.wait_for_task_completion(id)

func _build_viewer() -> void:
	_view = Control.new()
	_view.visible = false
	_view.modulate.a = 0.0
	_root.add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(Themes.c("bg"), 0.97)
	_view.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The photo takes nearly the whole screen; only a slim strip is left along the bottom.
	_view_pic = TextureRect.new()
	_view_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_view_pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_view.add_child(_view_pic)
	_view_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view_pic.offset_left = 40
	_view_pic.offset_right = -40
	_view_pic.offset_top = 36
	_view_pic.offset_bottom = -118

	# The bottom strip: photo info on the left, button hints on the right.
	_view_bar = Control.new()
	_view_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_view_bar)
	_view_bar.anchor_left = 0.0
	_view_bar.anchor_right = 1.0
	_view_bar.anchor_top = 1.0
	_view_bar.anchor_bottom = 1.0
	_view_bar.offset_top = -104
	_view_bar.offset_bottom = 0
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	_view_bar.add_child(info)
	info.anchor_top = 0.5
	info.anchor_bottom = 0.5
	info.offset_left = 60
	info.offset_top = -34
	info.offset_bottom = 34
	info.offset_right = 1000
	_view_name = _label("", 28, TEXT)
	_view_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(_view_name)
	_view_meta = _label("", 22, MUTED)
	info.add_child(_view_meta)
	_view_hints = HBoxContainer.new()
	_view_hints.alignment = BoxContainer.ALIGNMENT_END
	_view_bar.add_child(_view_hints)
	_view_hints.anchor_left = 1.0
	_view_hints.anchor_right = 1.0
	_view_hints.anchor_top = 0.5
	_view_hints.anchor_bottom = 0.5
	_view_hints.offset_left = -900
	_view_hints.offset_right = -60
	_view_hints.offset_top = -30
	_view_hints.offset_bottom = 30
	# "2 of 7", small, in the top right corner of the screen
	_view_pos = _label("", 22, MUTED)
	_view.add_child(_view_pos)
	_view_pos.anchor_left = 1.0
	_view_pos.anchor_right = 1.0
	_view_pos.offset_left = -240
	_view_pos.offset_right = -50
	_view_pos.offset_top = 40
	_view_pos.offset_bottom = 80
	_view_pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

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
	is_open = true
	_viewing = false
	_view.visible = false
	_gen += 1
	_scan()
	# As many columns as fit the screen (4 on a 1920 wide screen).
	var avail := get_viewport().get_visible_rect().size.x - 160.0 - 48.0
	_cols = maxi(int((avail + GAP) / (THUMB.x + GAP)), 1)
	_grid.columns = _cols
	_build_tiles()
	_sel = clampi(_sel, 0, maxi(_files.size() - 1, 0))
	_root.visible = true
	_root.modulate.a = 0.0
	Motion.fade_to(_root, 1.0, 0.2)
	_refresh_hints()
	_highlight(false)
	_start_thumbs()  # after the screen is up: the pictures fill in on their own

func close() -> void:
	if not is_open:
		return
	is_open = false
	_viewing = false
	if _clip_pid > 0:
		_stop_clip(false)
	_gen += 1
	_delete_armed = ""
	_selecting = false
	_picked.clear()
	closed.emit()
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, Motion.dur(0.2))
	await t.finished
	if not is_open:
		_root.visible = false
		_thumbs.clear()  # give the memory back
		_mutex.lock()
		_results.clear()
		_mutex.unlock()
		for c in _grid.get_children():
			c.queue_free()
		_tiles.clear()
		_images.clear()
		_marks.clear()
		_checks.clear()

func _refresh_hints() -> void:
	var del := "Press again to delete" if _delete_armed != "" else "Delete"
	if _selecting:
		var n := _picked.size()
		var del_n := ("Press again to delete %d" % n) if _delete_armed != "" else "Delete selected"
		var items := [["dpad", "Choose"], ["accept", "Select"], ["north", "Select all" if n < _files.size() else "Clear all"]]
		if n > 0:
			items.append(["west", del_n])
		items.append(["back", "Done"])
		TephraGlyphs.fill(_hints, items, 26)
	else:
		TephraGlyphs.fill(_hints, [["dpad", "Choose"], ["accept", "View / play"], ["north", "Select"], ["west", del], ["chip:" + _phone_key(), "To phone"], ["back", "Back"]], 26)
	_update_count()
	TephraGlyphs.fill(_view_hints, [["l1", "Previous"], ["r1", "Next"], ["accept", "Info"], ["west", del], ["chip:" + _phone_key(), "To phone"], ["back", "Back"]], 24)

## The button that sends the picture or recording you are on to your phone (the phone link, phone_link.gd).
func _phone_key() -> String:
	return "P" if TephraGlyphs.family == "keyboard" else "R3"

func _send_to_phone() -> void:
	if _files.is_empty() or _home == null:
		return
	_home.phone_screen.open("captures", str(_files[_sel]["name"]))

func _update_count() -> void:
	if _selecting:
		_count.text = "%d of %d selected" % [_picked.size(), _files.size()]
	else:
		_count.text = "%d item%s" % [_files.size(), "" if _files.size() == 1 else "s"]

# ---------- The photos ----------
func _scan() -> void:
	_files.clear()
	for d in [[folder(), EXTENSIONS, false], [video_folder(), VIDEO_EXTENSIONS, true]]:
		var dir := DirAccess.open(d[0])
		if dir == null:
			continue
		for f in dir.get_files():
			if f.get_extension().to_lower() in d[1]:
				var p: String = d[0] + "/" + f
				_files.append({"path": p, "name": f, "time": FileAccess.get_modified_time(p), "bytes": _file_size(p), "video": d[2]})
	_files.sort_custom(func(a, b): return a["time"] > b["time"])  # newest first

var _poll_t := 0.0

## While the Album is open, a new recording (or a deleted file) shows up by itself: the folders are looked at every 2 s
## and the tiles are rebuilt only when something changed. The tile you were on stays selected.
func refresh_files() -> void:
	if not is_open or _viewing or _clip_pid > 0:
		return
	var before := _files.duplicate()
	var keep := str(_files[_sel]["path"]) if _sel < _files.size() else ""
	_scan()
	if _files.size() == before.size():
		var same := true
		for i in _files.size():
			if _files[i]["path"] != before[i]["path"] or (int(_files[i]["bytes"]) > 0) != (int(before[i]["bytes"]) > 0):
				same = false
				break
		if same:
			return
	_sel = 0
	for i in _files.size():
		if _files[i]["path"] == keep:
			_sel = i
	_build_tiles()
	_start_thumbs()
	_sel = clampi(_sel, 0, maxi(_files.size() - 1, 0))
	_highlight(false)
	_refresh_hints()

func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0

func _make_tile(i: int) -> Control:
	var f: Dictionary = _files[i]
	var holder := Control.new()
	holder.custom_minimum_size = THUMB + Vector2(0, CAPTION_H)
	holder.pivot_offset = THUMB / 2
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Themes.c("tile")
	bsb.set_corner_radius_all(Themes.r(14))
	back.add_theme_stylebox_override("panel", bsb)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.size = THUMB
	holder.add_child(back)
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size = THUMB
	holder.add_child(pic)
	Rounded.apply(pic, THUMB, 14.0)
	if _thumbs.get(f["path"]) != null:
		pic.texture = _thumbs[f["path"]]
	else:
		pic.modulate.a = 0.0  # fades in when its picture arrives
	var mark := Panel.new()
	var msb := StyleBoxFlat.new()
	msb.draw_center = false
	msb.border_color = SELECT
	msb.set_border_width_all(0)
	msb.set_corner_radius_all(Themes.r(14))
	mark.add_theme_stylebox_override("panel", msb)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.size = THUMB
	holder.add_child(mark)
	if f.get("video", false):
		var badge := Panel.new()
		var bsb2 := StyleBoxFlat.new()
		bsb2.bg_color = Color(0, 0, 0, 0.55)
		bsb2.set_corner_radius_all(34)
		badge.add_theme_stylebox_override("panel", bsb2)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size = Vector2(68, 68)
		badge.position = (THUMB - badge.size) / 2
		var tri := Label.new()
		tri.text = "▶"
		tri.add_theme_font_size_override("font_size", 32)
		tri.add_theme_color_override("font_color", Color.WHITE)
		tri.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tri.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(tri)
		tri.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(badge)
	# Tick badge for select mode: a round dot in the top right corner.
	var check := Panel.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Themes.c("accent")
	csb.border_color = SELECT
	csb.set_border_width_all(3)
	csb.set_corner_radius_all(Themes.r(22))
	check.add_theme_stylebox_override("panel", csb)
	check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check.size = Vector2(44, 44)
	check.position = Vector2(THUMB.x - 56, 12)
	var tick := Label.new()
	tick.text = "✓"
	tick.add_theme_font_size_override("font_size", 28)
	tick.add_theme_color_override("font_color", Color.WHITE)
	tick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check.add_child(tick)
	tick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check.visible = _selecting
	_style_check(check, _picked.has(f["path"]))
	if _selecting and not _picked.has(f["path"]):
		pic.self_modulate = Color(0.6, 0.62, 0.66)
	holder.add_child(check)
	var cap := _label(_short_when(int(f["time"])), 21, MUTED)
	cap.position = Vector2(6, THUMB.y + 8)
	cap.size = Vector2(THUMB.x - 12, CAPTION_H - 8)
	cap.clip_text = true
	holder.add_child(cap)
	_tiles.append(holder)
	_images.append(pic)
	_marks.append(mark)
	_checks.append(check)
	return holder

## Ticked: filled navy with a tick. Not ticked: an empty ring, so you can see it can be picked.
func _style_check(check: Panel, on: bool) -> void:
	var sb := check.get_theme_stylebox("panel") as StyleBoxFlat
	sb.bg_color = Themes.c("accent") if on else Color(0, 0, 0, 0.35)
	(check.get_child(0) as Label).visible = on

func _refresh_checks() -> void:
	for i in mini(_checks.size(), _files.size()):
		var c: Panel = _checks[i]
		c.visible = _selecting
		var on := _picked.has(_files[i]["path"])
		_style_check(c, on)
		(_images[i] as TextureRect).self_modulate = Color(0.6, 0.62, 0.66) if _selecting and not on else Color.WHITE

func _build_tiles() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_tiles.clear()
	_images.clear()
	_marks.clear()
	_checks.clear()
	_update_count()
	_empty.visible = _files.is_empty()
	for i in _files.size():
		_grid.add_child(_make_tile(i))
	_refresh_checks()

# ---------- Thumbnails (worker thread) ----------
func _start_thumbs() -> void:
	var todo: Array = []
	for f in _files:
		if _thumbs.get(f["path"]) == null:
			todo.append({"path": f["path"], "time": f["time"], "video": f.get("video", false)})
	if todo.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(THUMB_DIR)
	var gen := _gen
	_task_ids.append(WorkerThreadPool.add_task(_thumb_worker.bind(gen, todo)))

func _thumb_worker(gen: int, todo: Array) -> void:
	for it in todo:
		if gen != _gen:
			return  # the Album was closed or reopened
		var img := _load_thumb(str(it["path"]), int(it["time"]), bool(it.get("video", false)))
		_mutex.lock()
		_results.append([gen, it["path"], img])
		_mutex.unlock()

## A small copy of the photo: from the cache if it's there, otherwise made from the full picture
## (and saved to the cache for next time).
func _load_thumb(path: String, mtime: int, video := false) -> Image:
	var cache := "%s/%s_%d.jpg" % [THUMB_DIR, path.get_file().get_basename(), mtime]
	if FileAccess.file_exists(cache):
		var c := Image.load_from_file(cache)
		if c != null and not c.is_empty():
			c.generate_mipmaps()
			return c
	if video:
		# A frame one second in (or the first frame for very short clips), made by ffmpeg.
		for ss in ["1", "0"]:
			OS.execute("ffmpeg", ["-y", "-loglevel", "error", "-ss", ss, "-i", path, "-frames:v", "1", "-vf", "scale=%d:-2" % THUMB_W, "-q:v", "3", ProjectSettings.globalize_path(cache)])
			if FileAccess.file_exists(cache):
				break
		var v := Image.load_from_file(cache) if FileAccess.file_exists(cache) else null
		if v == null or v.is_empty():
			return null
		v.generate_mipmaps()
		return v
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	img.resize(THUMB_W, maxi(int(float(THUMB_W) * img.get_height() / maxf(img.get_width(), 1.0)), 1), Image.INTERPOLATE_LANCZOS)
	img.save_jpg(cache, 0.9)
	img.generate_mipmaps()
	return img

func _process(_delta: float) -> void:
	if not is_open:
		return
	if _clip_pid > 0:
		_clip_tick(_delta)
	else:
		_poll_t += _delta
		if _poll_t >= 2.0:
			_poll_t = 0.0
			refresh_files()
	# Turn the finished pictures into textures, a couple per frame.
	for k in 2:
		_mutex.lock()
		var r = _results.pop_front() if not _results.is_empty() else null
		_mutex.unlock()
		if r == null:
			return
		if int(r[0]) != _gen:
			continue
		var path: String = r[1]
		var img: Image = r[2]
		var tex: ImageTexture = ImageTexture.create_from_image(img) if img != null else null
		_thumbs[path] = tex
		_apply_thumb(path, tex)

func _apply_thumb(path: String, tex: Texture2D) -> void:
	for i in _files.size():
		if _files[i]["path"] == path and i < _images.size():
			var pic: TextureRect = _images[i]
			pic.texture = tex
			if tex != null:
				create_tween().tween_property(pic, "modulate:a", 1.0, Motion.dur(0.25))
			return

# ---------- A new screenshot arrives while the Album is open ----------
## home.gd calls this right after saving a screenshot. If the Album is open, the new photo
## fades and pops into the first spot (it already has its picture: it was just taken).
func photo_added(path: String, img: Image) -> void:
	if not is_open:
		return
	var thumb := img.duplicate() as Image
	thumb.resize(THUMB_W, maxi(int(float(THUMB_W) * thumb.get_height() / maxf(thumb.get_width(), 1.0)), 1), Image.INTERPOLATE_LANCZOS)
	thumb.generate_mipmaps()
	_thumbs[path] = ImageTexture.create_from_image(thumb)
	_files.push_front({"path": path, "name": path.get_file(), "time": FileAccess.get_modified_time(path), "bytes": _file_size(path)})
	_sel += 1  # stay on the photo you were on
	_update_count()
	_empty.visible = false
	# Rebuild the tiles with the new photo first (the others reuse their pictures).
	_tiles.clear()
	_images.clear()
	_marks.clear()
	_checks.clear()
	for c in _grid.get_children():
		c.queue_free()
	for i in _files.size():
		_grid.add_child(_make_tile(i))
	if _viewing:
		_view_pos.text = "%d of %d" % [_sel + 1, _files.size()]
	else:
		_sel = clampi(_sel, 0, _files.size() - 1)
		_highlight(false)
	var fresh: Control = _tiles[0]
	fresh.modulate.a = 0.0
	fresh.scale = Vector2.ONE * 0.8
	var t := create_tween().set_parallel(true)
	t.tween_property(fresh, "modulate:a", 1.0, 0.35)
	t.tween_property(fresh, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------- Moving and picking ----------
## Called by home.gd for the D-pad and left stick.
func move(dir: Vector2i) -> void:
	if not is_open or _files.is_empty() or _clip_pid > 0:
		return
	if _viewing:
		if dir.x != 0:
			_show(posmod(_sel + dir.x, _files.size()))
		return
	var i := _sel + dir.x + dir.y * _cols
	if dir.x != 0 and (i < 0 or i >= _files.size()):
		i = posmod(i, _files.size())  # round the ends
	elif dir.y > 0 and i >= _files.size():
		i = _sel % _cols if _sel / _cols == (_files.size() - 1) / _cols else _files.size() - 1
	elif dir.y < 0 and i < 0:
		var last := ((_files.size() - 1) / _cols) * _cols + _sel % _cols
		i = last if last < _files.size() else _files.size() - 1
	if i != _sel:
		_sel = i
		Haptics.select()
		_highlight(true)

func _highlight(animate: bool) -> void:
	for i in _tiles.size():
		var on := i == _sel
		((_marks[i] as Panel).get_theme_stylebox("panel") as StyleBoxFlat).set_border_width_all(4 if on else 0)
		if animate:
			Motion.scale_to(_tiles[i], 1.04 if on else 1.0, 0.14)
		else:
			(_tiles[i] as Control).scale = Vector2.ONE * (1.04 if on else 1.0)
	_scroll_to_selected(animate)

func _scroll_to_selected(animate: bool) -> void:
	if _tiles.is_empty():
		return
	await get_tree().process_frame
	if not is_open or _sel >= _tiles.size():
		return
	var tile: Control = _tiles[_sel]
	var target := clampf(tile.position.y + 24.0 + THUMB.y / 2.0 - _scroll.size.y / 2.0, 0.0, 100000.0)
	if _scroll_tween != null and _scroll_tween.is_running():
		_scroll_tween.kill()
	if animate:
		_scroll_tween = create_tween()
		_scroll_tween.tween_property(_scroll, "scroll_vertical", int(target), Motion.dur(0.22)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_scroll.scroll_vertical = int(target)

## Returns true when the Album used the event.
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if _clip_pid > 0:
		return true  # a clip is playing: the pad is read in _clip_tick, nothing else may react to it
	if event is InputEventJoypadButton and event.pressed and not _selecting and not _files.is_empty() \
			and (event.button_index == JOY_BUTTON_LEFT_SHOULDER or event.button_index == JOY_BUTTON_RIGHT_SHOULDER) and (_viewing or _files[_sel].get("video", false)):
		_step(-1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
		return true
	if event is InputEventJoypadMotion:
		return true  # the stick goes through move()
	if not _selecting and ((event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_STICK) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P)):
		_send_to_phone()
		return true
	var del_pressed: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.west_button()) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE)
	var north_pressed: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.north_button()) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Y)
	if north_pressed and not _viewing and not _files.is_empty():
		if not _selecting:
			_set_selecting(true)
		else:
			# Select all, or clear all when everything is already ticked.
			if _picked.size() < _files.size():
				for f in _files:
					_picked[f["path"]] = true
			else:
				_picked.clear()
			_delete_armed = ""
			Haptics.tick()
			_refresh_checks()
			_refresh_hints()
	elif del_pressed:
		if _selecting:
			_delete_selected_pressed()
		else:
			_delete_pressed()
	elif event.is_action_pressed("ui_cancel"):
		if _delete_armed != "":
			_delete_armed = ""  # backing out of the question
			_refresh_hints()
		elif _selecting:
			_set_selecting(false)
		elif _viewing:
			_close_viewer()
		else:
			close()
	elif event.is_action_pressed("ui_accept") and not _files.is_empty():
		if not _selecting and _files[_sel].get("video", false):
			_start_clip(_sel)
		elif _viewing:
			_info_on = not _info_on
			Motion.fade_to(_view_bar, 1.0 if _info_on else 0.0, 0.18)
		elif _selecting:
			var path: String = _files[_sel]["path"]
			if _picked.has(path):
				_picked.erase(path)
			else:
				_picked[path] = true
			_delete_armed = ""
			Haptics.select()
			if _home != null and _home.sfx != null:
				_home.sfx.play("tick")
			Motion.pop(_tiles[_sel], 0.96, 0.18)
			_refresh_checks()
			_refresh_hints()
		else:
			_open_viewer()
	return true

func _set_selecting(on: bool) -> void:
	_selecting = on
	_picked.clear()
	_delete_armed = ""
	if on:
		_picked[_files[_sel]["path"]] = true  # start with the photo you're on
	if _home != null and _home.sfx != null:
		_home.sfx.play("confirm" if on else "back")
	_refresh_checks()
	_refresh_hints()

# ---------- Deleting ----------
# Square once asks ("Press again to delete"), a second press within 4 seconds deletes the photo for good.
func _delete_pressed() -> void:
	if _files.is_empty() or _sel >= _files.size():
		return
	var path: String = _files[_sel]["path"]
	if _delete_armed == path and Time.get_ticks_msec() < _delete_until:
		_delete_photo(path)
		return
	_delete_armed = path
	_delete_until = Time.get_ticks_msec() + 4000
	_refresh_hints()
	Haptics.tick()
	await get_tree().create_timer(4.1).timeout
	if _delete_armed == path and Time.get_ticks_msec() >= _delete_until:
		_delete_armed = ""
		if is_open:
			_refresh_hints()

# In select mode: Square once asks, a second press within 4 seconds deletes every ticked photo.
func _delete_selected_pressed() -> void:
	if _picked.is_empty():
		return
	if _delete_armed == "*" and Time.get_ticks_msec() < _delete_until:
		_delete_many(_picked.keys())
		return
	_delete_armed = "*"
	_delete_until = Time.get_ticks_msec() + 4000
	_refresh_hints()
	Haptics.tick()
	await get_tree().create_timer(4.1).timeout
	if _delete_armed == "*" and Time.get_ticks_msec() >= _delete_until:
		_delete_armed = ""
		if is_open:
			_refresh_hints()

func _delete_many(paths: Array) -> void:
	_delete_armed = ""
	if _home != null and _home.sfx != null:
		_home.sfx.play("trash")
	var first := _files.size()
	for i in range(_files.size() - 1, -1, -1):
		var f: Dictionary = _files[i]
		if not paths.has(f["path"]):
			continue
		DirAccess.remove_absolute(f["path"])
		var cache := "%s/%s_%d.jpg" % [THUMB_DIR, str(f["path"]).get_file().get_basename(), int(f["time"])]
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache))
		_thumbs.erase(f["path"])
		_files.remove_at(i)
		first = i
	_selecting = false
	_picked.clear()
	_sel = clampi(first, 0, maxi(_files.size() - 1, 0))
	_empty.visible = _files.is_empty()
	_build_tiles()
	_refresh_hints()
	_highlight(false)

func _delete_photo(path: String) -> void:
	_delete_armed = ""
	if _home != null and _home.sfx != null:
		_home.sfx.play("trash")
	DirAccess.remove_absolute(path)
	var cache := "%s/%s_%d.jpg" % [THUMB_DIR, path.get_file().get_basename(), int(_files[_sel]["time"])]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache))
	_thumbs.erase(path)
	_files.remove_at(_sel)
	_sel = clampi(_sel, 0, maxi(_files.size() - 1, 0))
	_update_count()
	_empty.visible = _files.is_empty()
	_tiles.clear()
	_images.clear()
	_marks.clear()
	_checks.clear()
	for c in _grid.get_children():
		c.queue_free()
	for i in _files.size():
		_grid.add_child(_make_tile(i))
	if _viewing:
		if _files.is_empty():
			_close_viewer()
		else:
			_show(_sel)  # on to the next photo
	_refresh_hints()
	_highlight(false)

# ---------- Full-size viewer ----------
func _open_viewer() -> void:
	_viewing = true
	_view.visible = true
	_view.modulate.a = 0.0
	_view_bar.modulate.a = 1.0 if _info_on else 0.0
	Motion.fade_to(_view, 1.0, 0.2)
	Motion.pop(_view_pic, 0.96, 0.25)
	_show(_sel)

func _close_viewer() -> void:
	_viewing = false
	_view_token += 1  # a photo still loading is no longer wanted
	var t := create_tween()
	t.tween_property(_view, "modulate:a", 0.0, Motion.dur(0.15))
	await t.finished
	if not _viewing:
		_view.visible = false
		_view_pic.texture = null  # drop the big picture
	_highlight(false)

func _show(i: int) -> void:
	if i != _sel:
		Haptics.tick()
	_sel = i
	var f: Dictionary = _files[i]
	_view_name.text = str(f["name"])
	_view_meta.text = "%s   ·   %s" % [_when_text(int(f["time"])), _size_text(int(f["bytes"]))]
	_view_pos.text = "%d of %d" % [i + 1, _files.size()]
	# Show the small copy at once, then swap in the full picture when the worker has loaded it.
	_view_pic.texture = _thumbs.get(f["path"])
	_view_token += 1
	var token := _view_token
	var path: String = f["path"]
	_task_ids.append(WorkerThreadPool.add_task(func():
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
		_full_ready.call_deferred(token, path, img)))

func _full_ready(token: int, path: String, img: Image) -> void:
	if token != _view_token or not _viewing or img == null or img.is_empty():
		return
	_view_pic.texture = ImageTexture.create_from_image(img)
	var f: Dictionary = _files[_sel]
	if f["path"] == path:
		_view_meta.text = "%d × %d   ·   %s   ·   %s" % [img.get_width(), img.get_height(), _when_text(int(f["time"])), _size_text(int(f["bytes"]))]

func _local(unix: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)

func _clock_text(d: Dictionary) -> String:
	if bool(Settings.get_value("clock_24h", false)):
		return "%02d:%02d" % [d["hour"], d["minute"]]
	var h12: int = (int(d["hour"]) + 11) % 12 + 1
	return "%d:%02d %s" % [h12, d["minute"], "AM" if int(d["hour"]) < 12 else "PM"]

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func _when_text(unix: int) -> String:
	if unix <= 0:
		return "Unknown date"
	var d := _local(unix)
	return "%s %d, %d  %s" % [MONTHS[int(d["month"]) - 1], d["day"], d["year"], _clock_text(d)]

func _short_when(unix: int) -> String:
	if unix <= 0:
		return ""
	var d := _local(unix)
	return "%s %d  ·  %s" % [MONTHS[int(d["month"]) - 1], d["day"], _clock_text(d)]

func _size_text(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MB" % (bytes / 1048576.0)
	return "%d KB" % maxi(roundi(bytes / 1024.0), 1)


# ---------- Playing a recording ----------
## A recording plays in a fullscreen mpv on top, and Tephra drives it through a small command pipe, reading the pad
## itself (so nothing else in Tephra reacts meanwhile): L1 / R1 go to the previous / next photo or recording, the left
## stick scrubs, the D-pad skips 5 s back and forth, Cross pauses, Circle leaves. Not tried on a real pad yet.
var _clip := {}
var _clip_pid := -1
var _clip_edge := {}
var _clip_acc := 0.0

## True while a recording is playing: Tephra's own music fades out meanwhile (home.gd checks this).
func clip_playing() -> bool:
	return _clip_pid > 0 or _clip_starting

var _clip_starting := false

func _start_clip(i: int) -> void:
	if _home == null or not _home.has_method("clip_start"):
		return
	_sel = i
	_highlight(false)
	_clip_starting = true
	var r: Dictionary = await _home.clip_start(str(_files[i]["path"]))
	_clip_starting = false
	if r.is_empty() or not is_open:
		return
	_clip = r
	_clip_pid = int(r["pid"])
	_clip_acc = 0.0
	_clip_edge = {}

func _stop_clip(restore := true) -> void:
	if _clip_pid <= 0:
		return
	var c := _clip
	_clip_pid = -1
	_clip = {}
	await _home.clip_stop(c, restore)

## L1 / R1: the next or previous item, photo or recording, one after the other.
func _step(d: int) -> void:
	if _files.is_empty():
		return
	var i := posmod(_sel + d, _files.size())
	var next_video: bool = _files[i].get("video", false)
	if _clip_pid > 0:
		await _stop_clip(not next_video)  # going on to another recording: Tephra stays out of the way
	elif _viewing and next_video:
		_viewing = false
		_view.visible = false
		_view_pic.texture = null
	Haptics.tick()
	if next_video:
		await _start_clip(i)
	else:
		_sel = i
		_highlight(false)
		if _viewing:
			_show(i)
		else:
			_open_viewer()

func _clip_pressed(key: String, dev: int, button: int, keycode: int) -> bool:
	var down: bool = (dev >= 0 and Input.is_joy_button_pressed(dev, button)) or Input.is_key_pressed(keycode)
	var was: bool = bool(_clip_edge.get(key, false))
	_clip_edge[key] = down
	return down and not was

func _clip_tick(delta: float) -> void:
	if not OS.is_process_running(_clip_pid):
		_clip_pid = -1  # mpv closed by itself
		_stop_clip(true)
		_clip = {}
		return
	var dev := TephraGlyphs.primary_device()
	if Input.is_action_just_pressed("ui_cancel"):
		_stop_clip(true)
		return
	if Input.is_action_just_pressed("ui_accept"):
		_home.clip_send(_clip, "cycle pause")
		_home.clip_send(_clip, "show-progress")
	if _clip_pressed("l1", dev, JOY_BUTTON_LEFT_SHOULDER, KEY_PAGEUP):
		_step(-1)
		return
	if _clip_pressed("r1", dev, JOY_BUTTON_RIGHT_SHOULDER, KEY_PAGEDOWN):
		_step(1)
		return
	if _clip_pressed("dl", dev, JOY_BUTTON_DPAD_LEFT, KEY_LEFT):
		_home.clip_send(_clip, "osd-msg-bar seek -5 exact")
	if _clip_pressed("dr", dev, JOY_BUTTON_DPAD_RIGHT, KEY_RIGHT):
		_home.clip_send(_clip, "osd-msg-bar seek 5 exact")
	# The left stick scrubs: the further it is pushed, the faster (up to 20 s per second).
	var ax := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X) if dev >= 0 else 0.0
	if absf(ax) > 0.25:
		_clip_acc += delta
		if _clip_acc >= 0.1:
			var speed := signf(ax) * (absf(ax) - 0.25) / 0.75 * 20.0 * _clip_acc
			_clip_acc = 0.0
			_home.clip_send(_clip, "osd-msg-bar seek %.2f exact" % speed)
	else:
		_clip_acc = 0.0
