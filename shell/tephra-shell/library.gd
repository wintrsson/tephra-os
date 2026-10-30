extends CanvasLayer
const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const SteamAccount = preload("res://steam_account.gd")
const Icons = preload("res://icons.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const Rounded = preload("res://rounded.gd")
const InstallDialog = preload("res://install_dialog.gd")
const LibraryGame = preload("res://library_game.gd")
const GameNames = preload("res://game_names.gd")
const ExtraGames = preload("res://extra_games.gd")
## Tephra Library: every game you own on Steam, installed or not.
## Owned games come from the Steam Web API (key in ~/.config/tephra/steam.cfg).
## Installed games can be played from here. Games you don't have can be
## installed: Tephra asks Steam to install, then shows a progress bar on the tile.

signal launch_requested(appid: String)
signal closed

var BG: Color = Themes.c("bg")
var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var SELECT: Color = Themes.c("select")
const TILE := Vector2(180, 270)
const GAP := 28
const OWNED_URL := "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=%s&steamid=%s&include_appinfo=1&include_played_free_games=1&format=json"
const CDN := "https://cdn.cloudflare.steamstatic.com/steam/apps/%s/%s.jpg"
const MAX_DOWNLOADS := 6

var is_open := false
var _home  # home.gd, for installed games and art helpers

var _root: Control
var _title: Label
var _count: Label
var _status: Label
var _clock: Label
var _shard: TextureRect
var _scroll: ScrollContainer
var _content: Control  # the Library's own list; hidden when a game page is opened straight from Channels
var _grid: GridContainer
var _hints: HBoxContainer
var _cols := 8

var _owned: Array = []      # [{id, title, playtime}] from Steam
var _family: Array = []     # games other people in your Steam Family share with you (same shape)
var _freq: HTTPRequest
var _family_todo: Array = []  # Steam IDs still to ask
var _shown: Array = []      # what the grid is showing right now
var _tiles: Array = []
var _frames: Array = []
var _sel := 0
var _installed_only := false
var _req: HTTPRequest
var _art_queue: Array = []  # [[id, kind, cover, banner, name_label], ...]
var _scroll_tween: Tween
var _art_active := 0
var _toast_token := 0
var _installing := {}   # appid -> {title, started, seen} while Steam downloads it
var _poll := 0.0
var _page  # library_game.gd: the game page (info, disk bar, Play / Install)
var _statline: Label
var _direct := false  # opened by open_game(): closing the page closes the Library too

func setup(home) -> void:
	_home = home

func _ready() -> void:
	layer = 80  # above home, below the launch screen (90) and control center (95)
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
	_content = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	margin.add_child(v)

	var top_gap := Control.new()  # the clock row, shared with home (see open())
	top_gap.custom_minimum_size.y = 56
	v.add_child(top_gap)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	v.add_child(head)
	head.add_child(_label("Library", 36, TEXT))
	_count = _label("", 26, MUTED)
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_count)
	_title = _label("", 48, TEXT)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	v.add_child(_title)

	_statline = _label("", 26, MUTED)
	v.add_child(_statline)

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

	_status = _label("", 26, MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status)
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_top = -170
	_status.offset_bottom = -130

	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END  # bottom right, like home
	v.add_child(_hints)
	refresh_hints()

	_clock = _label("", 32, TEXT)
	_root.add_child(_clock)
	_shard = TextureRect.new()
	_shard.texture = Icons.shard(52)
	_root.add_child(_shard)

	_req = HTTPRequest.new()
	add_child(_req)
	_req.request_completed.connect(_on_owned)
	_freq = HTTPRequest.new()
	add_child(_freq)
	_freq.request_completed.connect(_on_family)
	_page = LibraryGame.new()
	_page.setup(self)
	add_child(_page)
	_page.action.connect(_on_page_action)

func refresh_hints() -> void:
	var items: Array = []
	var installed := _sel < _shown.size() and _is_installed(_shown[_sel]["id"])
	var quick: bool = installed and not _home.cross_opens_info()  # Cross starts installed games; Triangle shows the page
	var info_mode: bool = _home.cross_opens_info()
	items = [["accept", "Options" if (info_mode and installed) else ("Play" if quick else "Open")], ["dpad", "Browse"], ["west", "All games" if _installed_only else "Installed only"]]
	if quick:
		items.append(["north", "Info"])
	items.append(["r1", "Add a game"])
	items.append(["back", "Back"])
	TephraGlyphs.fill(_hints, items)

# ---------- Open / close ----------
var _fetched_at := -1

func open(clock_rect := Rect2(), light := false) -> void:
	if is_open:
		return
	is_open = true
	if clock_rect.size != Vector2.ZERO:
		_clock.position = clock_rect.position
		_clock.size = clock_rect.size
		_shard.position = Vector2(80, clock_rect.get_center().y - _shard.texture.get_height() / 2.0)
	_load_owned_cache()
	if not light:
		# Building the grid (a tile per game) is what made opening the Library hitch, so the grid from last time is kept
		# when nothing in it changed, and it is built ahead of time after Tephra starts (prewarm).
		if _tiles.is_empty() or _grid_sig() != _built_sig:
			_rebuild()
		else:
			_select(clampi(_sel, 0, maxi(_shown.size() - 1, 0)), false)
	_content.modulate.a = 1.0
	_root.visible = true
	_root.modulate.a = 0.0
	Motion.fade_to(_root, 1.0, 0.25)
	Motion.pop(_grid, 0.97, 0.25)
	if not light and (_fetched_at < 0 or Time.get_ticks_msec() - _fetched_at > 600000):
		_fetched_at = Time.get_ticks_msec()
		_fetch_owned()  # at most every 10 minutes: Steam's list hardly changes, and each answer cost a rebuild
	if not light:
		# Once the Library covers the screen, Home underneath stops drawing (its moving background and art cost frames).
		await get_tree().create_timer(0.3).timeout
		if is_open:
			_home.cover_home(true)

## Reads what you own (and your Steam Family's games) from Steam again without opening the Library, so a fresh start
## or a new theme begins with an up to date list.
func refresh_online() -> void:
	if SteamAccount.api_key() == "" or SteamAccount.steam_id(_home.steam_dir) == "":
		return
	_load_owned_cache()
	_fetched_at = Time.get_ticks_msec()
	_fetch_owned()

func close() -> void:
	if not is_open:
		return
	is_open = false
	_home.cover_home(false)
	var was_direct := _direct
	_direct = false
	if _page.is_open or not was_direct:
		_page.hide_now()  # (a page already fading out is left to finish, so it does not cut)
	closed.emit()
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, Motion.dur(0.2))
	await t.finished
	if not is_open:
		_root.visible = false

func _process(delta: float) -> void:
	if not _installing.is_empty():
		_poll += delta
		if _poll >= 2.0:
			_poll = 0.0
			_check_installs()
	if is_open:
		_clock.text = preload("res://settings.gd").clock_text()
		_fade_bottom()

# Tiles near the bottom edge of the grid fade out smoothly instead of being cut off.
func _fade_bottom() -> void:
	var edge := _scroll.get_global_rect().end.y
	for t in _tiles:
		if not is_instance_valid(t):
			continue
		var top: float = (t as Control).get_global_rect().position.y
		var k := clampf((edge - top - 20.0) / 240.0, 0.0, 1.0)
		t.modulate.a = k * k * (3.0 - 2.0 * k)  # smoothstep

# ---------- Data ----------
## The installed game with this number (empty if it is not installed).
func _home_game(id: String) -> Dictionary:
	for g in _home.games:
		if str(g["id"]) == id:
			return g
	return {}

## True when the game is installed but not on the Home row.
func _is_hidden(id: String) -> bool:
	var g := _home_game(id)
	return not g.is_empty() and not _home.on_home(g)

## Home reloaded the games (one was uninstalled, renamed or pinned): rebuild the grid and the page if open.
func games_changed() -> void:
	_rebuild_keep()
	refresh_hints()
	if _page.is_open:
		_page.refresh()

func _toggle_hidden_id(id: String) -> void:
	if not _is_installed(id):
		return
	_home.set_on_home(_home_game(id), _is_hidden(id))  # pinned if it was off Home, unpinned if it was on
	var keep := _sel
	_home.refresh_games()  # the Home row now skips (or shows) it
	_rebuild()
	_sel = clampi(keep, 0, _shown.size() - 1)
	_select(_sel)
	refresh_hints()

func _is_installed(id: String) -> bool:
	for g in _home.games:
		if str(g["id"]) == id:
			return true
	return false

## Owned games plus anything installed that Steam didn't list (e.g. demos).
func _all_games() -> Array:
	var list: Array = []
	var seen := {}
	for g in _owned:
		list.append(g)
		seen[g["id"]] = true
	for g in _family:
		if not seen.has(g["id"]):
			list.append(g)
			seen[g["id"]] = true
	for g in _home.games:
		var id := str(g["id"])
		if not seen.has(id):
			list.append({"id": id, "title": g["title"], "orig_title": g.get("orig_title", g["title"]), "playtime": 0, "nonsteam": bool(g.get("nonsteam", false)), "ps2": bool(g.get("ps2", false))})
	GameNames.apply(list)
	list.sort_custom(func(a, b): return a["title"].naturalnocasecmp_to(b["title"]) < 0)
	return list

var _built_sig := ""

## What the grid shows: when this is the same as when it was built, the grid needs no rebuilding.
func _grid_sig() -> String:
	var parts := PackedStringArray([str(_installed_only)])
	for g in _all_games():
		var id := str(g["id"])
		parts.append("%s/%s/%s/%s" % [id, str(g["title"]), str(_is_installed(id)), str(_is_hidden(id))])
	return "|".join(parts)

## Builds the grid while the Library is closed (a few seconds after start), so the first open is instant too.
func prewarm() -> void:
	if is_open:
		return
	_load_owned_cache()
	if _tiles.is_empty() or _grid_sig() != _built_sig:
		_rebuild()

func _rebuild() -> void:
	_built_sig = _grid_sig()
	for t in _tiles:
		_grid.remove_child(t)
		t.queue_free()
	_tiles.clear()
	_frames.clear()
	_art_queue.clear()
	var vw := _root.get_viewport_rect().size.x
	_cols = maxi(3, int((vw - 160 - 48 + GAP) / (TILE.x + GAP)))
	_grid.columns = _cols
	_shown = []
	for g in _all_games():
		if _installed_only and not _is_installed(g["id"]):
			continue
		_shown.append(g)
	for g in _shown:
		_make_tile(g)
	var installed := 0
	for g in _shown:
		if _is_installed(g["id"]):
			installed += 1
	_count.text = "%d games  ·  %d installed" % [_shown.size(), installed]
	_select(clampi(_sel, 0, maxi(_shown.size() - 1, 0)), false)

func _make_tile(g: Dictionary) -> void:
	var tile := Panel.new()
	tile.custom_minimum_size = TILE
	tile.pivot_offset = TILE / 2
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.from_hsv(float(hash(str(g["title"])) % 360) / 360.0, 0.35, 0.30)  # a colour per game, shown when it has no cover
	sb.set_corner_radius_all(Themes.r(14))
	tile.add_theme_stylebox_override("panel", sb)
	# Tall cover art. If a game has none, its wide store banner is shown
	# instead with the name under it; the name only shows when there's no cover.
	var cover := TextureRect.new()
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	Rounded.apply(cover, TILE, 14.0)  # smooth, anti-aliased corners
	cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tile.add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var banner := TextureRect.new()
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tile.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 40
	banner.offset_bottom = 40 + TILE.x * 215.0 / 460.0
	var name_lbl := _label(g["title"], 22, TEXT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_lbl.max_lines_visible = 4
	name_lbl.add_theme_constant_override("outline_size", 6)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	name_lbl.visible = false
	tile.add_child(name_lbl)
	name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_lbl.offset_left = 14
	name_lbl.offset_right = -14
	name_lbl.offset_bottom = -20
	if not _is_installed(g["id"]):
		# Not installed: darker, not see-through.
		cover.modulate = Color(0.42, 0.42, 0.42)
		banner.modulate = Color(0.42, 0.42, 0.42)
		name_lbl.modulate = Color(0.7, 0.7, 0.7)
	if _is_hidden(str(g["id"])) and not bool(_home_game(str(g["id"])).get("extra", false)):
		var badge := _label("Hidden from Home", 16, Color("121a24"))
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(1, 1, 1, 0.85)
		bsb.set_corner_radius_all(Themes.r(10))
		bsb.content_margin_left = 10
		bsb.content_margin_right = 10
		bsb.content_margin_top = 2
		bsb.content_margin_bottom = 2
		badge.add_theme_stylebox_override("normal", bsb)
		var badge_row := CenterContainer.new()  # centred on the tile
		badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(badge_row)
		badge_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		badge_row.offset_top = 10
		badge_row.add_child(badge)
	var frame := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.draw_center = false
	fsb.border_color = SELECT
	fsb.set_corner_radius_all(Themes.r(14))
	frame.add_theme_stylebox_override("panel", fsb)
	tile.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Download bar along the bottom of the tile (only visible while installing).
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.visible = false
	tile.add_child(bar_bg)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar_bg.offset_top = -14
	var bar := ColorRect.new()
	bar.color = SELECT
	bar_bg.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.anchor_right = 0.0
	tile.set_meta("bar_bg", bar_bg)
	tile.set_meta("bar", bar)
	_grid.add_child(tile)
	_tiles.append(tile)
	_frames.append(fsb)
	if bool(g.get("nonsteam", false)):
		# not a Steam game: nothing to download, but a cover saved in Steam's grid folder (the PS2 covers) is used; else the name is the tile
		var local: String = _home._find_local_art(str(g["id"]), "library_600x900")
		var tex: Texture2D = _home._tex(local) if local != "" else null
		if tex != null and _home.cover_ok(tex):
			cover.texture = tex
		else:
			name_lbl.visible = true
		return
	_queue_art(g["id"], "library_600x900", cover, banner, name_lbl)

# ---------- Steam Web API ----------
func _fetch_owned() -> void:
	var key := SteamAccount.api_key()
	var sid := SteamAccount.steam_id(_home.steam_dir)
	if key == "":
		_toast("Add your Steam Web API key to ~/.config/tephra/steam.cfg to see games you haven't installed.", 0)
		return
	if sid == "":
		_toast("Couldn't find your Steam account. Sign in to Steam once.", 0)
		return
	_req.cancel_request()
	_req.request(OWNED_URL % [key, sid])

func _on_owned(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_toast("Couldn't reach Steam (error %d). Showing saved list." % code, 4.0)
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary and d.get("response") is Dictionary):
		return
	var games = d["response"].get("games", [])
	if games.is_empty():
		_toast("Steam returned no games. Set Steam Profile > Game details to Public, or check the key.", 6.0)
		return
	var list: Array = []
	for g in games:
		list.append({"id": str(int(g["appid"])), "title": str(g.get("name", g["appid"])), "playtime": int(g.get("playtime_forever", 0))})
	_owned = list
	var f := FileAccess.open("user://owned.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(list))
	if is_open:
		_rebuild_keep()
	_fetch_family()

## Rebuilds the grid but stays on the same game.
## A game's cover changed (PS2 Original / Remake art): the tiles are made again with the new picture (now if the
## Library is open, as it is when the art is changed from a game's page in it, otherwise on the next open).
func forget_art(_id: String) -> void:
	_built_sig = ""
	if is_open:
		_rebuild_keep()

func _rebuild_keep() -> void:
	if not _tiles.is_empty() and _grid_sig() == _built_sig:
		return  # Steam sent the same list as last time: nothing to rebuild (rebuilding is what made opening lag)
	var keep := ""
	if _sel < _shown.size():
		keep = _shown[_sel]["id"]
	_rebuild()
	for i in _shown.size():
		if _shown[i]["id"] == keep:
			_select(i, false)

# ---------- Family games ----------
## Asks again right away (after the family list in Settings changed).
func reload_family() -> void:
	if _freq != null and not SteamAccount.api_key().is_empty():
		_freq.cancel_request()
		_fetch_family()

## Asks Steam for the games of everyone you share a family with, one person after another.
func _fetch_family() -> void:
	var sid := SteamAccount.steam_id(_home.steam_dir)
	_family_todo = Array(ExtraGames.family_ids(_home.steam_dir, sid))
	_family_new = []
	if _family_todo.is_empty() and _family.is_empty():
		_toast("No Steam Family members found. Put their Steam IDs (7656...) in ~/.config/tephra/family.txt, one per line, and set their Game details to Public.", 8.0)
	_next_family()

var _family_new: Array = []
var _family_asked := ""

func _next_family() -> void:
	if _family_todo.is_empty():
		if not _family_new.is_empty() or _family.is_empty():
			var before := _family.size()
			_family = _family_new
			if is_open and _family.size() > before:
				_toast("Added %d Steam Family games to the Library." % (_family.size() - before), 4.0)  # only when there are new ones
			var f := FileAccess.open("user://family.json", FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(_family))
			if is_open:
				_rebuild_keep()
		return
	_family_asked = str(_family_todo.pop_front())
	_freq.request(OWNED_URL % [SteamAccount.api_key(), _family_asked])

func _on_family(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var d = JSON.parse_string(body.get_string_from_utf8())
		var games = d["response"].get("games", []) if d is Dictionary and d.get("response") is Dictionary else []
		var mine := {}
		for g in _owned:
			mine[g["id"]] = true
		for g in games:
			var id := str(int(g["appid"]))
			if mine.has(id):
				continue
			var dup := false
			for x in _family_new:
				if x["id"] == id:
					dup = true
					break
			if not dup:
				_family_new.append({"id": id, "title": str(g.get("name", id)), "playtime": 0, "family": true})
		if games.is_empty():
			_toast("Couldn't see the games of %s. Their Steam profile > Game details must be Public." % _family_asked, 6.0)
	_next_family()

func _load_owned_cache() -> void:
	var txt := FileAccess.get_file_as_string("user://owned.json") if FileAccess.file_exists("user://owned.json") else ""
	var d = JSON.parse_string(txt) if txt != "" else null
	if d is Array:
		_owned = d
	var ft := FileAccess.get_file_as_string("user://family.json") if FileAccess.file_exists("user://family.json") else ""
	var fd = JSON.parse_string(ft) if ft != "" else null
	if fd is Array:
		_family = fd

# ---------- Cover art (a few downloads at a time) ----------
# kind is "library_600x900" (tall cover) or "header" (wide banner fallback).
func _queue_art(id: String, kind: String, cover: TextureRect, banner: TextureRect, name_lbl: Label) -> void:
	var local: String = _home._find_local_art(id, kind)
	var cached := "user://art/%s_%s.jpg" % [id, kind]
	if local == "" and FileAccess.file_exists(cached):
		local = cached
	if local != "":
		_show_art(id, kind, _home._tex(local), cover, banner, name_lbl)
		return
	_art_queue.append([id, kind, cover, banner, name_lbl])
	_pump_art()

func _show_art(id: String, kind: String, tex: Texture2D, cover: TextureRect, banner: TextureRect, name_lbl: Label) -> void:
	if kind == "header":
		banner.texture = tex
		name_lbl.visible = true
	elif _home.cover_ok(tex):
		cover.texture = tex
	else:
		# A blank, wide or tiny "cover" from Steam's cache is not real cover art: show the
		# banner and the name instead.
		cover.texture = null
		_queue_art(id, "header", cover, banner, name_lbl)

func _pump_art() -> void:
	while _art_active < MAX_DOWNLOADS and not _art_queue.is_empty():
		var job: Array = _art_queue.pop_front()
		if not is_instance_valid(job[2]):
			continue
		_art_active += 1
		var path := "user://art/%s_%s.jpg" % [job[0], job[1]]
		var req := HTTPRequest.new()
		add_child(req)
		req.download_file = path
		req.request_completed.connect(_on_art.bind(req, path, job))
		req.request(CDN % [job[0], job[1]])

func _on_art(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray, req: HTTPRequest, path: String, job: Array) -> void:
	req.queue_free()
	_art_active -= 1
	if not is_instance_valid(job[2]):
		_pump_art()
		return
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_show_art(job[0], job[1], _home._tex(path), job[2], job[3], job[4])
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if job[1] == "library_600x900":
			_queue_art(job[0], "header", job[2], job[3], job[4])  # try the wide banner
		else:
			job[4].visible = true  # no art at all: just the name
	_pump_art()

# ---------- Navigation ----------
func _select(i: int, animate := true) -> void:
	if _shown.is_empty():
		_title.text = "No games yet"
		refresh_hints()
		return
	var before := _sel
	_sel = clampi(i, 0, _shown.size() - 1)
	if animate and _sel != before:
		Haptics.select()
	for j in _tiles.size():
		var on := j == _sel
		var fsb: StyleBoxFlat = _frames[j]
		fsb.set_border_width_all(5 if on else 0)
		var target := Vector2.ONE * (1.08 if on else 1.0)
		if animate:
			Motion.scale_to(_tiles[j], target.x, 0.13)
		else:
			_tiles[j].scale = target
	_smooth_scroll.call_deferred(_tiles[_sel], animate)
	var g: Dictionary = _shown[_sel]
	_title.text = g["title"] + ("" if _is_installed(g["id"]) else "   (not installed)")
	_statline.text = "   ·   ".join(LibraryGame.stats_parts(g, _home.steam_dir, _home_game(str(g["id"]))))
	refresh_hints()

# Glides the grid so the selected tile is fully on screen (instead of snapping).
func _smooth_scroll(tile: Control, animate: bool) -> void:
	var tr := tile.get_global_rect()
	var sr := _scroll.get_global_rect()
	var target := _scroll.scroll_vertical
	if tr.position.y < sr.position.y + 30:
		target -= int(sr.position.y + 30 - tr.position.y)
	elif tr.end.y > sr.end.y - 30:
		target += int(tr.end.y - (sr.end.y - 30))
	else:
		return
	target = maxi(target, 0)
	if _scroll_tween != null:
		_scroll_tween.kill()
	if not animate:
		_scroll.scroll_vertical = target
		return
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_scroll, "scroll_vertical", target, Motion.dur(0.22)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## dx/dy: -1, 0 or 1. Used by the D-pad and by home.gd for the left stick.
func move(dx: int, dy: int) -> void:
	if _page.is_open:
		_page.move(dx, dy)
		return
	if _shown.is_empty():
		return
	var i := _sel + dx + dy * _cols
	if dx != 0 and (i < 0 or i >= _shown.size()):
		i = posmod(i, _shown.size())  # round the ends
	elif dy > 0 and i >= _shown.size():
		i = _sel % _cols if _sel / _cols == (_shown.size() - 1) / _cols else _shown.size() - 1  # last row: back to the top of the column
	elif dy < 0 and i < 0:
		var last := ((_shown.size() - 1) / _cols) * _cols + _sel % _cols  # first row: on to the bottom of the column
		i = last if last < _shown.size() else _shown.size() - 1
	_select(i)

## Returns true when the library used the event.
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if _page.is_open:
		var used: bool = _page.handle_input(event)
		if _direct and not _page.is_open:
			close()  # opened straight onto the page (Channels theme): back out to the channels
		return used
	if event is InputEventJoypadMotion:
		return true  # the stick goes through move()
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("ui_accept"):
		_activate()
	elif (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.west_button()) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X):
		_installed_only = not _installed_only
		_sel = 0
		_rebuild()
	elif (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.north_button()) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Y):
		if not _home.cross_opens_info():
			_activate(true)  # Triangle: the game's page (Cross starts the game)
		# "info first" mode: Cross does everything, Triangle does nothing
	elif (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_SHOULDER) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N):
		_home.add_game()  # R1: add a game that isn't from Steam (a .exe and the like), see home.gd
	return true

## Cross: starts an installed game (or opens the page of one that is not installed, or always, in "info" mode).
## Triangle in the quick mode comes here too, with `info` set: always the page.
func _activate(info := false) -> void:
	if _shown.is_empty():
		return
	var g: Dictionary = _shown[_sel]
	var tile: Control = _tiles[_sel]
	var pop := create_tween()
	pop.tween_property(tile, "scale", Vector2.ONE * 1.02, 0.08).set_trans(Tween.TRANS_SINE)
	pop.tween_property(tile, "scale", Vector2.ONE * 1.08, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await pop.finished
	if not info and not _home.cross_opens_info() and _is_installed(g["id"]):
		_page.hide_now()
		launch_requested.emit(str(g["id"]))
		return
	var cover: Texture2D = (tile.get_child(0) as TextureRect).texture
	_page.open(g, cover)

## Channels theme: every game listed here, for its paged Home (installed and not, Steam Family too).
func all_games() -> Array:
	_load_owned_cache()
	return _all_games()

## Channels theme: opens straight onto one game's page (Info, or a game that isn't installed).
## Backing out of the page leaves the Library open on that game; B again goes back to the channels.
func open_game(g: Dictionary, cover: Texture2D) -> void:
	if cover == null:
		var local: String = _home._find_local_art(str(g["id"]), "library_600x900")
		if local != "":
			var t: Texture2D = _home._tex(local)
			if t != null and _home.cover_ok(t):
				cover = t
	open(Rect2(), true)
	_direct = true
	_content.modulate.a = 0.0  # only the page fades in, not the Library list behind it
	for i in _shown.size():
		if str(_shown[i]["id"]) == str(g["id"]):
			_sel = i
			_select(i, false)
			g = _shown[i]
			break
	_page.open(g, cover)

func _on_page_action(key: String, g: Dictionary) -> void:
	var id := str(g["id"])
	match key:
		"play":
			_page.hide_now()
			launch_requested.emit(id)
		"install":
			_install(g)
		"pin":
			_toggle_hidden_id(id)
			_page.refresh()
		"menu":
			_home.open_game_menu_for_id(id)
		"mods":
			_home.open_mods_for(g)
		"remove":
			if await _home.store.remove_game(id, str(g["title"])):
				_page.hide_now()
				_rebuild()
		"uninstall":
			await _home._uninstall(id, str(g["title"]))
			if not _is_installed(id):
				_page.hide_now()
				_rebuild()
		"rename":
			var orig := str(g.get("orig_title", g["title"]))
			_home.keyboard.open("Rename game", str(g["title"]), false, func(text: String):
				GameNames.set_custom(id, text)
				_after_rename(id),
				{"max_len": 48, "hint": "Leave it empty to use \"%s\" again" % orig})

func _after_rename(id: String) -> void:
	if _is_installed(id):
		_home.refresh_games()
	_rebuild()
	for i in _shown.size():
		if str(_shown[i]["id"]) == id:
			_select(i, false)
			if _page.is_open:
				_page.refresh(_shown[i])
			break

# ---------- Installing ----------
# Steam does the downloading. We ask it to install, then watch the game's
# appmanifest file in steamapps: it appears once Steam accepts the install and
# is updated with how many bytes are done.
func _install(g: Dictionary) -> void:
	var id: String = g["id"]
	if _home.launching:
		# Starting Steam's installer would disturb the running game.
		_toast("Close %s first to install games." % _home._game_title, 4.0)
		return
	if _installing.has(id):
		_toast("%s is already downloading." % g["title"], 3.0)
		return
	_installing[id] = {"title": g["title"], "started": Time.get_ticks_msec(), "seen": false}
	_home.prefetch_art(id)  # its pictures, before Steam has any
	_toast("Starting the download...", 6.0)
	_page.set_status("Starting Steam...")
	# Preferably on a hidden display, so Steam's popup is never on screen; otherwise the old way.
	var hidden: bool = await _home.steam_install_hidden(id)
	if not hidden:
		_home.steam_rule(false)  # Steam's install window must be allowed to exist for a moment
		_home.steam_open("steam://install/" + id, true)
	_home.steam_confirm_install(id)  # clicks Install in Steam's popup for you

func _manifest_value(txt: String, key: String) -> int:
	var re := RegEx.new()
	re.compile("\"" + key + "\"\\s+\"(\\d+)\"")
	var m := re.search(txt)
	return m.get_string(1).to_int() if m != null else 0

func _check_installs() -> void:
	var finished := false
	for id in _installing.keys():
		var info: Dictionary = _installing[id]
		var txt: String = _home.manifest_text(id)
		var pct := -1.0
		if txt == "":
			_home.steam_resend_if_dead("steam://install/" + id)
			var waited := (Time.get_ticks_msec() - int(info["started"])) / 1000
			if waited > 25:
				_page.set_status("Still waiting on Steam...")
			elif waited > 6:
				_page.set_status("Waiting for Steam to accept the install...")
			# No manifest yet. If it never shows up the install was cancelled.
			if (Time.get_ticks_msec() - int(info["started"])) > 240000 and not info["seen"]:
				_installing.erase(id)
				_home.steam_rule(true)
				_home.stop_steam_if_idle()
				_page.set_status("")
				_toast("Install cancelled.", 3.0)
			_show_progress(id, -1.0)
			continue
		if not info["seen"]:
			_page.finish()
			# Steam accepted the install (dialog confirmed): bring Tephra back on top.
			DisplayServer.window_move_to_foreground()
			_home.steam_rule(true)
		info["seen"] = true
		var flags := _manifest_value(txt, "StateFlags")
		var total := _manifest_value(txt, "BytesToDownload")
		var done := _manifest_value(txt, "BytesDownloaded")
		if (flags & 4) != 0 and (total == 0 or done >= total):
			_installing.erase(id)
			_show_progress(id, -1.0)
			finished = true
			_toast("%s is ready to play." % info["title"], 5.0)
			continue
		if total > 0:
			pct = clampf(float(done) / float(total), 0.0, 1.0)
		else:
			pct = 0.0
		_show_progress(id, pct)
	if finished:
		_home.stop_steam_if_idle()
		_home.refresh_games()
		if is_open:
			_rebuild()
			if _page.is_open:
				_page.refresh()
	elif not _installing.is_empty():
		_toast_progress()

## What is downloading right now, for the progress card on Home: [{title, pct}] (pct -1 = starting).
func downloads() -> Array:
	var list: Array = []
	for id in _installing:
		list.append({"title": str(_installing[id]["title"]), "pct": float(_installing[id].get("pct", -1.0))})
	return list

func _show_progress(id: String, pct: float) -> void:
	if _installing.has(id):
		_installing[id]["pct"] = pct
		if _page.is_open and str(_page._id) == id:
			var txt: String = _home.manifest_text(id)
			var total := float(_manifest_value(txt, "BytesToDownload")) if txt != "" else 0.0
			_page.set_progress(pct, total)
	for i in _shown.size():
		if _shown[i]["id"] == id and i < _tiles.size():
			var bg: Control = _tiles[i].get_meta("bar_bg")
			var bar: Control = _tiles[i].get_meta("bar")
			bg.visible = pct >= 0.0
			bar.anchor_right = maxf(pct, 0.0)

func _toast_progress() -> void:
	if _status.text != "" and not _status.text.begins_with("Downloading"):
		return  # don't overwrite a message that's still showing
	var parts: Array = []
	for id in _installing.keys():
		parts.append(_installing[id]["title"])
	_status.text = "Downloading " + ", ".join(parts) + "..."

func _toast(msg: String, seconds: float) -> void:
	_toast_token += 1
	var t := _toast_token
	_status.text = msg
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout
	if t == _toast_token:
		_status.text = ""

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
