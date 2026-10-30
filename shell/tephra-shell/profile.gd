extends CanvasLayer
## Your Steam profile inside Tephra: picture, name, level, a few stats, and what
## you played recently. Opened from the top bar (press Up from the games, then ✕).
## Everything except the level comes from files already on this PC, so it works
## offline and without an API key.

const TephraGlyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
const Icons = preload("res://icons.gd")
const SteamAccount = preload("res://steam_account.gd")
const Achievements = preload("res://achievements.gd")

var BG: Color = Themes.c("bg")
var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var CARD: Color = Themes.ink(0.07)
const LEVEL_URL := "https://api.steampowered.com/IPlayerService/GetSteamLevel/v1/?key=%s&steamid=%s"
const AVATAR := 170
const COVER := Vector2(150, 225)
const COVERS := 8

var is_open := false
var _home  # home.gd

var _root: Control
var _clock: Label
var _avatar: TextureRect
var _name: Label
var _sub: Label
var _stats: HBoxContainer
var _covers: HBoxContainer
var _hints: HBoxContainer
var _req: HTTPRequest
var _level := 0

func setup(home) -> void:
	_home = home

func _ready() -> void:
	layer = 80
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BG
	_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var anim = (preload("res://xmb_bg.gd") if Themes.layout() == "xmb" else preload("res://tephra_bg.gd")).new()
	anim.set("plain", true)  # Temple theme: no desktop windows behind a full page
	_root.add_child(anim)
	anim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 34)
	margin.add_child(v)

	var top_gap := Control.new()  # same row as the home clock (placed in open())
	top_gap.custom_minimum_size.y = 56
	v.add_child(top_gap)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 40)
	v.add_child(head)
	var circle := Panel.new()
	circle.custom_minimum_size = Vector2(AVATAR, AVATAR)
	circle.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color.WHITE
	csb.set_corner_radius_all(Themes.r(AVATAR / 2))
	circle.add_theme_stylebox_override("panel", csb)
	head.add_child(circle)
	_avatar = TextureRect.new()
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	circle.add_child(_avatar)
	_avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 6)
	head.add_child(names)
	_name = _label("", 60, TEXT)
	names.add_child(_name)
	_sub = _label("", 26, MUTED)
	names.add_child(_sub)

	_stats = HBoxContainer.new()
	_stats.add_theme_constant_override("separation", 24)
	v.add_child(_stats)

	v.add_child(_label("Recently played", 30, TEXT))
	_covers = HBoxContainer.new()
	_covers.add_theme_constant_override("separation", 24)
	v.add_child(_covers)

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grow)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(_hints)
	refresh_hints()

	_clock = _label("", 32, TEXT)
	_root.add_child(_clock)

	_req = HTTPRequest.new()
	add_child(_req)
	_req.request_completed.connect(_on_level)

func refresh_hints() -> void:
	TephraGlyphs.fill(_hints, [["back", "Back"], ["guide", "Control center"]], 26)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# ---------- Open / close ----------
func open(clock_rect := Rect2()) -> void:
	if is_open:
		return
	is_open = true
	if clock_rect.size != Vector2.ZERO:
		_clock.position = clock_rect.position
		_clock.size = clock_rect.size
	_fill()
	_root.visible = true
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.25)
	_fetch_level()

func close() -> void:
	if not is_open:
		return
	is_open = false
	_home._focus_profile(false)  # back to the games, not the top bar
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.2)
	await t.finished
	if not is_open:
		_root.visible = false

func _process(_delta: float) -> void:
	if is_open:
		_clock.text = _home.clock_label.text

## Returns true when the profile screen used the event.
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event.is_action_pressed("ui_cancel"):
		close()
	return true

# ---------- Content ----------
func _fill() -> void:
	_avatar.texture = _home.avatar_rect.texture
	_name.text = _home.profile_name.text if _home.profile_name.text != "" else "Steam profile"
	_update_sub()

	var owned := _owned_games()
	var minutes := 0
	var top_title := "-"
	var top_minutes := 0
	var source: Array = owned if not owned.is_empty() else _home.games
	for g in source:
		var m := int(g.get("playtime", 0))
		minutes += m
		if m > top_minutes:
			top_minutes = m
			top_title = str(g["title"])
	var account := Achievements.account_id(SteamAccount.steam_id(_home.steam_dir))
	var unlocked := Achievements.total_unlocked(_home.steam_dir, account)
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	_stat(str(source.size()), "Games")
	_stat("%d h" % roundi(minutes / 60.0), "Played")
	_stat(str(unlocked), "Achievements")
	_stat(top_title, "Most played", true)

	for c in _covers.get_children():
		_covers.remove_child(c)
		c.queue_free()
	var recent: Array = []
	for g in _home.games:
		if int(g["last"]) > 0:
			recent.append(g)
	recent.sort_custom(func(a, b): return a["last"] > b["last"])
	for g in recent.slice(0, COVERS):
		_cover(g)
	if recent.is_empty():
		_covers.add_child(_label("Games you play will show up here.", 24, MUTED))

# "Level 31 · Member since 2016", whichever parts are known.
func _update_sub() -> void:
	var parts: Array = []
	if _level > 0:
		parts.append("Level %d" % _level)
	var saved := FileAccess.get_file_as_string("user://profile.json") if FileAccess.file_exists("user://profile.json") else ""
	var p = JSON.parse_string(saved) if saved != "" else null
	if p is Dictionary and int(p.get("since", 0)) > 0:
		parts.append("Member since %d" % int(Time.get_datetime_dict_from_unix_time(int(p["since"]))["year"]))
	_sub.text = "   ·   ".join(parts) if not parts.is_empty() else "Steam"

func _owned_games() -> Array:
	var txt := FileAccess.get_file_as_string("user://owned.json") if FileAccess.file_exists("user://owned.json") else ""
	var d = JSON.parse_string(txt) if txt != "" else null
	return d if d is Array else []

func _stat(value: String, caption: String, small := false) -> void:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.set_corner_radius_all(Themes.r(20))
	sb.set_content_margin_all(24)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var big := _label(value, 32 if small else 52, TEXT)
	big.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	big.custom_minimum_size.y = 62
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(big)
	v.add_child(_label(caption, 22, MUTED))
	_stats.add_child(p)

func _cover(g: Dictionary) -> void:
	var tile := Panel.new()
	tile.custom_minimum_size = COVER
	tile.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var sb := StyleBoxFlat.new()
	sb.bg_color = Themes.c("tile")
	sb.set_corner_radius_all(Themes.r(14))
	tile.add_theme_stylebox_override("panel", sb)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tile.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var name_lbl := _label(g["title"], 18, TEXT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(name_lbl)
	name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_covers.add_child(tile)
	# The name shows only while there's no cover.
	_home.load_cover(str(g["id"]), art, func(): name_lbl.visible = false)

# ---------- Steam level (needs your API key; skipped without one) ----------
func _fetch_level() -> void:
	var key := SteamAccount.api_key()
	var sid := SteamAccount.steam_id(_home.steam_dir)
	if key == "" or sid == "":
		return
	_req.cancel_request()
	_req.request(LEVEL_URL % [key, sid])

func _on_level(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if d is Dictionary and d.get("response") is Dictionary:
		_level = int(d["response"].get("player_level", 0))
		_update_sub()
