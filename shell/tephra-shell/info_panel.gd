extends PanelContainer
const TephraGlyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
const Achievements = preload("res://achievements.gd")
const SteamAccount = preload("res://steam_account.gd")
const Ps2Games = preload("res://ps2_games.gd")
## Game info card on the home screen: Steam Deck rating, controller support,
## short description, last played, playtime and install size.
## Store info comes from Steam's public store and is cached for a week.

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
const CACHE_DAYS := 7
const DECK_URL := "https://store.steampowered.com/saleaction/ajaxgetdeckappcompatibilityreport?nAppID=%s&l=english"
const STORE_URL := "https://store.steampowered.com/api/appdetails?appids=%s&l=english"
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var panel_width := 520
var wide := false   # game_details.gd sets this: the Description page is a wide, full-width card
var _id := ""
var _badges: HBoxContainer
var _desc: Label
var _stats: Label
var _deck_req: HTTPRequest
var _store_req: HTTPRequest
var _pending := {}  # info being fetched for _pending["id"]
var _token := 0
var _steam_dir := OS.get_environment("HOME") + "/.local/share/Steam"
var _account := ""  # Steam account number, for reading achievements

func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Themes.c("panel"), 0.74)
	sb.set_corner_radius_all(Themes.r(20))
	sb.set_content_margin_all(26)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size.x = 0 if wide else panel_width
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	add_child(v)
	_badges = HBoxContainer.new()
	_badges.add_theme_constant_override("separation", 12)
	v.add_child(_badges)
	_desc = _label("", 28 if wide else 22, TEXT)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.max_lines_visible = 12 if wide else 5
	_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_desc)
	_stats = _label("", 20, MUTED)
	v.add_child(_stats)

	_deck_req = HTTPRequest.new()
	add_child(_deck_req)
	_deck_req.request_completed.connect(_on_deck)
	_store_req = HTTPRequest.new()
	add_child(_store_req)
	_store_req.request_completed.connect(_on_store)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://info"))
	modulate.a = 0.0
	_account = Achievements.account_id(SteamAccount.steam_id(_steam_dir))

## Shows a game. g needs: id, last (unix time), size (bytes), playtime (minutes).
func show_game(g: Dictionary) -> void:
	_id = str(g["id"])
	_name = str(g.get("orig_title", g.get("title", "")))
	_ps2 = bool(g.get("ps2", false))
	_stats.text = _stats_text(g) if not wide else ""  # the wide page shows these on the Stats page
	var info := _load_cache(_id)
	_apply(info)
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	if info.is_empty() or Time.get_unix_time_from_system() - float(info.get("fetched", 0)) > CACHE_DAYS * 86400:
		_fetch(_id)

func hide_panel() -> void:
	_id = ""
	_token += 1
	create_tween().tween_property(self, "modulate:a", 0.0, 0.2)

# ---------- Showing ----------
func _apply(info: Dictionary) -> void:
	for c in _badges.get_children():
		_badges.remove_child(c)
		c.queue_free()
	if info.is_empty():
		_desc.text = ""
		return
	match int(info.get("deck", 0)):
		3:
			_badges.add_child(_badge("deck_ok", _svg_check(), "Verified"))
		2:
			_badges.add_child(_badge("deck_play", _svg_info(), "Playable"))
		1:
			_badges.add_child(_badge("deck_no", _svg_no(), "Unsupported"))
	match str(info.get("controller", "")):
		"full":
			_badges.add_child(_badge("pad", _svg_pad(), "Full controller"))
		"partial":
			_badges.add_child(_badge("pad", _svg_pad(), "Partial controller"))
	_desc.text = str(info.get("desc", ""))

func _stats_text(g: Dictionary) -> String:
	var parts: Array = []
	var last := int(g.get("last", 0))
	if last > 0:
		var d := Time.get_datetime_dict_from_unix_time(last)
		parts.append("Last played %s %d" % [MONTHS[int(d["month"]) - 1], d["day"]])
	var mins := int(g.get("playtime", 0))
	if mins > 0:
		parts.append("%.1f h played" % (mins / 60.0) if mins >= 60 else "%d min played" % mins)
	# Achievements straight from Steam's cache on this PC, e.g. "8 / 35 achievements".
	var ach := Achievements.for_game(_steam_dir, _account, str(g.get("id", "")))
	if not ach.is_empty():
		parts.append("%d / %d achievements" % [ach["unlocked"], ach["total"]])
	# Whole numbers: "4 GB", or "52 MB" for small games.
	var size := float(g.get("size", 0))
	if size > 0:
		parts.append("%d GB" % maxi(1, roundi(size / 1073741824.0)) if size >= 1073741824.0 else "%d MB" % roundi(size / 1048576.0))
	return "   ·   ".join(parts)

func _badge(key: String, svg: String, text: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Themes.ink(0.1)
	sb.set_corner_radius_all(Themes.r(16))
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var icon := TextureRect.new()
	icon.texture = TephraGlyphs.svg_texture(key, svg, 26)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	h.add_child(icon)
	var l := _label(text, 20, TEXT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return p

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# ---------- Fetching ----------
## A non-Steam game (or PS2 game) has no store page of its own: it is looked up in the Steam store by its name,
## and the description of the game with that name is used. For PS2 games that is often the remaster or remake
## (Silent Hill 2 finds the 2024 remake): the story is the same, but the Deck and controller badges would describe
## the PC version, so they are left out for them.
var _name := ""
var _ps2 := false

func _fetch(id: String) -> void:
	_token += 1
	var t := _token
	await get_tree().create_timer(0.4).timeout  # wait until scrolling settles
	if t != _token or id != _id:
		return
	var sid := id
	if id.is_valid_int() and int(id) > 0x7FFFFFFF:
		sid = await _store_id(_name)
		if t != _token or id != _id:
			return
		if sid == "":
			_pending = {"id": id, "deck": 0, "desc": "", "controller": ""}
			_maybe_done()
			return
	_pending = {"id": id, "sid": sid}
	_deck_req.cancel_request()
	_store_req.cancel_request()
	if _ps2:
		_pending["deck"] = 0
	else:
		_deck_req.request(DECK_URL % sid)
	_store_req.request(STORE_URL % sid)

## The Steam store number of the game with this name ("" when nothing matches closely).
func _store_id(title: String) -> String:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	if req.request("https://store.steampowered.com/api/storesearch/?term=%s&cc=us&l=en" % title.uri_encode()) != OK:
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
		if it is Dictionary:
			var n := Ps2Games.norm(str(it.get("name", "")))
			if n == want or (want.length() >= 4 and (n.begins_with(want) or want.begins_with(n)) and minf(n.length(), want.length()) / maxf(n.length(), want.length()) > 0.7):
				return str(int(it.get("id", 0)))
	return ""

func _on_deck(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var cat := 0
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var d = JSON.parse_string(body.get_string_from_utf8())
		if d is Dictionary and d.get("results") is Dictionary:
			cat = int(d["results"].get("resolved_category", 0))
	_pending["deck"] = cat
	_maybe_done()

func _on_store(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var desc := ""
	var controller := ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var d = JSON.parse_string(body.get_string_from_utf8())
		var entry = d.get(str(_pending.get("sid", _pending.get("id", "")))) if d is Dictionary else null
		if entry is Dictionary and entry.get("success", false) and entry.get("data") is Dictionary:
			desc = _clean(str(entry["data"].get("short_description", "")))
			controller = "" if _ps2 else str(entry["data"].get("controller_support", ""))
	_pending["desc"] = desc
	_pending["controller"] = controller
	_maybe_done()

func _maybe_done() -> void:
	if not (_pending.has("deck") and _pending.has("desc")):
		return
	var id: String = _pending["id"]
	var info := {"deck": _pending["deck"], "desc": _pending["desc"], "controller": _pending["controller"], "fetched": Time.get_unix_time_from_system()}
	var f := FileAccess.open("user://info/%s.json" % id, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(info))
	if id == _id:
		_apply(info)

func _load_cache(id: String) -> Dictionary:
	var p := "user://info/%s.json" % id
	var txt := FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
	var d = JSON.parse_string(txt) if txt != "" else null
	return d if d is Dictionary else {}

# Store descriptions can contain HTML tags and entities like &quot;.
func _clean(s: String) -> String:
	var re := RegEx.new()
	re.compile("<[^>]+>")
	s = re.sub(s, "", true)
	for pair in [["&quot;", "\""], ["&#39;", "'"], ["&amp;", "&"], ["&lt;", "<"], ["&gt;", ">"], ["&nbsp;", " "]]:
		s = s.replace(pair[0], pair[1])
	return s.strip_edges()

# ---------- Badge icons ----------
const _ST := '<g fill="none" stroke="#fff" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round">'

func _svg_check() -> String:
	return '<circle cx="24" cy="24" r="20" fill="#fff"/><path d="M14 24.5 L21 31.5 L34 17" fill="none" stroke="#121a24" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>'

func _svg_info() -> String:
	return '<circle cx="24" cy="24" r="20" fill="#fff"/><circle cx="24" cy="15" r="2.8" fill="#121a24"/><path d="M24 22 V34" stroke="#121a24" stroke-width="4.5" stroke-linecap="round"/>'

func _svg_no() -> String:
	return _ST + '<circle cx="24" cy="24" r="18"/><path d="M11.5 36.5 L36.5 11.5"/></g>'

func _svg_pad() -> String:
	return '<path d="M15 13 H33 C39 13 43 19 44.5 27 C46 35 42 39 37.5 36.5 L32 31 H16 L10.5 36.5 C6 39 2 35 3.5 27 C5 19 9 13 15 13 Z" fill="#fff"/>' \
		+ '<path d="M14 19 V27 M10 23 H18" stroke="#121a24" stroke-width="3" stroke-linecap="round"/>' \
		+ '<circle cx="32" cy="20.5" r="2.3" fill="#121a24"/><circle cx="36.5" cy="25" r="2.3" fill="#121a24"/>'
