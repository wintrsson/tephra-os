extends Control
## The section below the game row. Its top edge peeks out at the bottom of the
## home screen; pressing Down scrolls the screen up to it (home.gd does the scrolling).
##
## A game has three pages, switched with L1 / R1 (Q / E on a keyboard):
##     Stats   <   Description   >   Achievements
## The Home tile has no pages: it just lists your newest achievements.

const Achievements = preload("res://achievements.gd")
const Themes = preload("res://themes.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Ring = preload("res://progress_ring.gd")
const Icons = preload("res://icons.gd")
const Weather = preload("res://weather.gd")
const Settings = preload("res://settings.gd")
const Motion = preload("res://motion.gd")
const Rounded = preload("res://rounded.gd")
const Sessions = preload("res://sessions.gd")
const Haptics = preload("res://haptics.gd")

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var SELECT: Color = Themes.c("select")
var CARD_BG: Color = Color(Themes.c("card"), 0.84)
const ICON := 64
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const MAX_DOWNLOADS := 4
const PAGES := ["Overview"]  # a game: its stats, description and achievements on one page, top to bottom
const HOME_PAGES := ["Today", "Performance"]  # Today also lists the recent achievements, under its cards
const FILTERS := ["Most recent", "Rarest", "Not earned"]
const GLOBAL_URL := "https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=%s&format=json"
const GLOBAL_DAYS := 7

var steam_dir := ""
var account := ""       # Steam account number (for the achievement files)
var titles := {}        # appid -> game title, for the recent list
var has_content := false

var about: PanelContainer   # info_panel.gd, the Description page
var hints: HBoxContainer

var _mode := "game"         # "game" (Stats/Description/Achievements) or "home" (Today/Achievements)
var art_loader := Callable()  # home.gd: (appid, kind, TextureRect) loads cover art
var games: Array = []         # home.gd's installed games, newest played first
var _page := 1              # 0 Stats, 1 Description, 2 Achievements
var _filter := 0            # index into FILTERS
var _appid := ""
var _game: Dictionary = {}
var _data: Dictionary = {}  # Achievements.for_game() of the current game
var _global := {}           # achievement api name -> % of players who have it

var _strip: HBoxContainer
var _arrow: Control
var _arrow_box: Control
var _entered := false
var hide_arrow := false   # home.gd: true while the control center is open or the top bar has the focus
var _tab_labels: Array = []
var _page_stats: Control
var _page_ach: Control
var _ach_top := 0.0  # where the achievements card starts under the cards above it
var _focus_tween: Tween
var _page_today: Control
var _page_perf: Control
var _perf_rows: VBoxContainer
var _pc_rows: VBoxContainer
var perf   # perf.gd, set by home.gd
var _recent_games: Array = []
var _today_sel := 0
var _recent_thumbs: Array = []
signal play_requested(appid: String)
var _today_cover: TextureRect
var _today_name: Label
var _today_sub: Label
var _today_ach_icon: TextureRect
var _today_ach_name: Label
var _today_ach_sub: Label
var _store_chart: Control
var _store := {}            # bytes: total, avail, games, proton, workshop
var _store_scan_at := -9999.0
var _store_scanning := false
var _store_task := -1
var weather: Node             # weather.gd, set by home.gd
var _week := {}
var _wk_total: Label
var _wk_chart: Control
var _wk_sub: Label
var _sg_cover: TextureRect
var _sg_name: Label
var _sg_sub: Label
var _fr_card: PanelContainer
var _fr_title: Label
var _fr_sub: Label
var _wx_icon: TextureRect
var _wx_temp: Label
var _wx_text: Label
var _wx_sub: Label
var _earned_total := 0
var _ring
var _t_play: Label
var _t_last: Label
var _t_size: Label
var _next_icon: TextureRect
var _next_name: Label
var _next_desc: Label
var _title: Label
var _count: Label
var _bar: ProgressBar
var _chips: HBoxContainer
var _chip_styles: Array = []
var _chip_labels: Array = []
var _scroll: ScrollContainer
var _sheet: ColorRect
var _list: VBoxContainer
var _empty: Label
var _rows: Array = []       # [{panel, style}]
var _pending: Array = []    # rows not built yet (a long list is built a few rows per frame)
const FIRST_ROWS := 8
const ROWS_PER_FRAME := 3
static var _tex_cache := {} # icon path -> texture, so a game is not decoded from disk twice
var _sel := -1              # highlighted achievement, -1 = none (screen is on the row)
var _scroll_tween: Tween
var _icon_queue: Array = [] # [url, path, TextureRect]
var _icon_active := 0
var _greq: HTTPRequest
var _gid := ""              # app the global request is for

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ach"))
	# A dark sheet behind the whole section, so the games row doesn't show through.
	var sheet := ColorRect.new()
	sheet.color = Color(Themes.c("sheet"), 0.55 if Themes.id() == "frutiger" else 0.97)  # Frutiger: the fish still show through
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet = sheet
	add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Soft top edge: the games row fades out into the sheet instead of ending in a hard line.
	var edge_grad := Gradient.new()
	edge_grad.offsets = PackedFloat32Array([0.0, 1.0])
	edge_grad.colors = PackedColorArray([Color(sheet.color, 0.0), sheet.color])
	var edge_tex := GradientTexture2D.new()
	edge_tex.gradient = edge_grad
	edge_tex.fill_from = Vector2(0, 0)
	edge_tex.fill_to = Vector2(0, 1)
	edge_tex.width = 4
	edge_tex.height = 128
	var edge_fade := TextureRect.new()
	edge_fade.texture = edge_tex
	edge_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	edge_fade.stretch_mode = TextureRect.STRETCH_SCALE
	edge_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge_fade)
	edge_fade.anchor_right = 1.0
	edge_fade.offset_top = -50 if Themes.id() == "frutiger" else -200  # Frutiger: short, so the grass along the bottom stays visible
	edge_fade.offset_bottom = 0
	# Not on Frutiger (the grass) or Channels: there the sheet is only shown while open, so the fade would pop up white
	# along the bottom of the screen for a moment each time the Home page opens or closes.
	edge_fade.visible = not Themes.id() in ["frutiger", "channels"]
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	margin.add_child(v)

	# Page strip: [L1] Stats · Description · Achievements [R1]. It's the first thing
	# in the section, so it's what peeks out under the row.
	_strip = HBoxContainer.new()
	_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_strip.add_theme_constant_override("separation", 36)
	_strip.custom_minimum_size.y = 40
	v.add_child(_strip)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(stack)

	_build_stats_page(stack)
	_build_today_page(stack)
	_build_perf_page(stack)

	about = preload("res://info_panel.gd").new()
	about.wide = true
	about.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stack.add_child(about)
	about.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)

	_build_achievements_page(stack)

	hints = HBoxContainer.new()
	hints.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(hints)

	# While the screen is still on the games row, the page strip is hidden and a small
	# arrow under the row says "press Down" instead (the strip crowds the button hints).
	var arrow_box := Control.new()
	arrow_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(arrow_box)
	arrow_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	arrow_box.offset_bottom = 60
	# Drawn the same way, and the same size, as the arrow under the top bar (home.gd, _make_top_shade).
	_arrow = Control.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.modulate.a = 0.75
	_arrow.draw.connect(func() -> void:
		_arrow.draw_polyline(PackedVector2Array([Vector2(4, 4), Vector2(22, 18), Vector2(40, 4)]), Themes.ink(0.85), 4.0, true))
	arrow_box.add_child(_arrow)
	_arrow.size = Vector2(44, 24)
	_arrow.position = Vector2(0, 4)
	_arrow_box = arrow_box
	_strip.modulate.a = 0.0

	_greq = HTTPRequest.new()
	add_child(_greq)
	_greq.request_completed.connect(_on_global)
	_build_strip()
	refresh_hints()

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _card(radius := 20, margin := 26) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.set_corner_radius_all(Themes.r(radius))
	sb.set_content_margin_all(margin)
	return sb

# ---------- Building the pages ----------
func _build_strip() -> void:
	for c in _strip.get_children():
		_strip.remove_child(c)
		c.queue_free()
	_tab_labels.clear()
	var names := _names()
	if names.size() > 1:
		_strip.add_child(TephraGlyphs.glyph("l1", 34))
	for i in names.size():
		var l := _label(names[i], 26, MUTED)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_strip.add_child(l)
		_tab_labels.append(l)
	if names.size() > 1:
		_strip.add_child(TephraGlyphs.glyph("r1", 34))
	_update_strip()

func _names() -> Array:
	return HOME_PAGES if _mode == "home" else PAGES

## What the current page shows: "stats", "desc", "ach" or "today".
func _kind() -> String:
	if _mode == "home":
		return ["today", "perf"][_page]
	return "game"

func _update_strip() -> void:
	for i in _tab_labels.size():
		var on := i == _page
		_tab_labels[i].add_theme_color_override("font_color", TEXT if on else MUTED)
		_tab_labels[i].add_theme_font_size_override("font_size", 30 if on else 24)

# Stats page: progress ring on the left, big tiles on the right.
func _build_stats_page(stack: Control) -> void:
	_page_stats = HBoxContainer.new()
	_page_stats.add_theme_constant_override("separation", 32)
	stack.add_child(_page_stats)
	_page_stats.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)

	var ring_card := PanelContainer.new()
	ring_card.add_theme_stylebox_override("panel", _card())
	Rounded.rough(ring_card)
	ring_card.custom_minimum_size = Vector2(300, 300)
	_page_stats.add_child(ring_card)
	_ring = Ring.new()
	_ring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ring_card.add_child(_ring)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 24)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_stats.add_child(right)
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 24)
	right.add_child(tiles)
	_t_play = _tile(tiles, "Played")
	_t_last = _tile(tiles, "Last played")
	_t_size = _tile(tiles, "On disk")

	# "Next up": the easiest achievement you don't have yet.
	var nu := PanelContainer.new()
	nu.add_theme_stylebox_override("panel", _card())
	Rounded.rough(nu)
	right.add_child(nu)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	nu.add_child(vb)
	vb.add_child(_label("Next up", 20, MUTED))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	vb.add_child(h)
	_next_icon = TextureRect.new()
	_next_icon.custom_minimum_size = Vector2(ICON, ICON)
	_next_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_next_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(_next_icon)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	_next_name = _label("", 26, TEXT)
	_next_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(_next_name)
	_next_desc = _label("", 19, MUTED)
	_next_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(_next_desc)

# Today page (Home tile): Continue (with free space), weather, latest achievement.
func _build_today_page(stack: Control) -> void:
	_page_today = HBoxContainer.new()
	_page_today.add_theme_constant_override("separation", 28)
	stack.add_child(_page_today)
	_page_today.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)

	var cont := PanelContainer.new()
	cont.add_theme_stylebox_override("panel", _card())
	Rounded.rough(cont)
	cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_today.add_child(cont)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	cont.add_child(col)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 22)
	col.add_child(ch)
	# The cover sits in a rounded box of fixed 2:3 shape, so it is never stretched or cut off.
	var clip := Panel.new()
	clip.custom_minimum_size = Vector2(110, 165)
	clip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var csb := StyleBoxFlat.new()
	csb.bg_color = Themes.c("panel")
	csb.set_corner_radius_all(Themes.r(12))
	clip.add_theme_stylebox_override("panel", csb)
	ch.add_child(clip)
	_today_cover = TextureRect.new()
	_today_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_today_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_today_cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	Rounded.apply(_today_cover, Vector2(110, 165), 12.0)
	clip.add_child(_today_cover)
	_today_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 6)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(cv)
	cv.add_child(_label("Continue", 20, MUTED))
	_today_name = _label("", 30, TEXT)
	_today_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_today_name.max_lines_visible = 2
	cv.add_child(_today_name)
	_today_sub = _label("", 20, MUTED)
	_today_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_today_sub)
	# Recently played: pick one with left/right, press A to play it.
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 14)
	col.add_child(rr)
	for i in 5:
		var tc := Panel.new()
		tc.custom_minimum_size = Vector2(62, 93)
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Themes.c("panel")
		tsb.set_corner_radius_all(Themes.r(10))
		tc.add_theme_stylebox_override("panel", tsb)
		var tt := TextureRect.new()
		tt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tt.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		Rounded.apply(tt, Vector2(62, 93), 10.0)
		tc.add_child(tt)
		tt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var fr := Panel.new()
		var fsb := StyleBoxFlat.new()
		fsb.draw_center = false
		fsb.border_color = SELECT
		fsb.set_corner_radius_all(Themes.r(10))
		fr.add_theme_stylebox_override("panel", fsb)
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tc.add_child(fr)
		fr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rr.add_child(tc)
		_recent_thumbs.append({"panel": tc, "tex": tt, "frame": fsb})
	# Storage on the Steam drive, along the bottom of this card: one bar split by what uses the space.
	_store_chart = Control.new()
	_store_chart.custom_minimum_size = Vector2(0, 46)
	_store_chart.draw.connect(_draw_store)
	col.add_child(_store_chart)

	# Middle column: this week's playtime, and a game you haven't tried yet.
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 20)
	mid.custom_minimum_size.x = 360
	_page_today.add_child(mid)
	var wk := PanelContainer.new()
	wk.add_theme_stylebox_override("panel", _card())
	Rounded.rough(wk)
	mid.add_child(wk)
	var wkv := VBoxContainer.new()
	wkv.add_theme_constant_override("separation", 8)
	wk.add_child(wkv)
	wkv.add_child(_label("This week", 18, MUTED))
	_wk_total = _label("", 30, TEXT)
	wkv.add_child(_wk_total)
	_wk_chart = Control.new()
	_wk_chart.custom_minimum_size = Vector2(0, 92)
	_wk_chart.draw.connect(_draw_week)
	wkv.add_child(_wk_chart)
	_wk_sub = _label("", 17, MUTED)
	_wk_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	wkv.add_child(_wk_sub)
	var sg := PanelContainer.new()
	sg.add_theme_stylebox_override("panel", _card())
	Rounded.rough(sg)
	mid.add_child(sg)
	var sgh := HBoxContainer.new()
	sgh.add_theme_constant_override("separation", 16)
	sg.add_child(sgh)
	var sgbox := Panel.new()
	sgbox.custom_minimum_size = Vector2(66, 99)
	sgbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sgsb := StyleBoxFlat.new()
	sgsb.bg_color = Themes.c("panel")
	sgsb.set_corner_radius_all(Themes.r(10))
	sgbox.add_theme_stylebox_override("panel", sgsb)
	sgh.add_child(sgbox)
	_sg_cover = TextureRect.new()
	_sg_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sg_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_sg_cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	Rounded.apply(_sg_cover, Vector2(66, 99), 10.0)
	sgbox.add_child(_sg_cover)
	_sg_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sgv := VBoxContainer.new()
	sgv.alignment = BoxContainer.ALIGNMENT_CENTER
	sgv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sgv.add_theme_constant_override("separation", 4)
	sgh.add_child(sgv)
	sgv.add_child(_label("Try something new", 18, MUTED))
	_sg_name = _label("", 22, TEXT)
	_sg_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sg_name.max_lines_visible = 2
	sgv.add_child(_sg_name)
	_sg_sub = _label("", 17, MUTED)
	sgv.add_child(_sg_sub)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 20)
	right.custom_minimum_size.x = 400
	_page_today.add_child(right)

	# Weather card.
	var wp := PanelContainer.new()
	wp.add_theme_stylebox_override("panel", _card())
	Rounded.rough(wp)
	right.add_child(wp)
	var wh := HBoxContainer.new()
	wh.add_theme_constant_override("separation", 18)
	wp.add_child(wh)
	_wx_icon = TextureRect.new()
	_wx_icon.custom_minimum_size = Vector2(72, 72)
	_wx_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wx_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wx_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wh.add_child(_wx_icon)
	var wv := VBoxContainer.new()
	wv.alignment = BoxContainer.ALIGNMENT_CENTER
	wv.add_theme_constant_override("separation", 2)
	wv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wh.add_child(wv)
	_wx_temp = _label("", 38, TEXT)
	wv.add_child(_wx_temp)
	_wx_text = _label("", 20, TEXT)
	_wx_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	wv.add_child(_wx_text)
	_wx_sub = _label("", 17, MUTED)
	_wx_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	wv.add_child(_wx_sub)

	# Latest achievement card: not shown any more, the recent achievements list sits under the Today cards.
	var ap := PanelContainer.new()
	ap.add_theme_stylebox_override("panel", _card())
	Rounded.rough(ap)
	ap.visible = false
	right.add_child(ap)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 10)
	ap.add_child(av)
	av.add_child(_label("Latest achievement", 18, MUTED))
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", 16)
	av.add_child(ah)
	_today_ach_icon = TextureRect.new()
	_today_ach_icon.custom_minimum_size = Vector2(56, 56)
	_today_ach_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_today_ach_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ah.add_child(_today_ach_icon)
	var at := VBoxContainer.new()
	at.alignment = BoxContainer.ALIGNMENT_CENTER
	at.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ah.add_child(at)
	_today_ach_name = _label("", 22, TEXT)
	_today_ach_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	at.add_child(_today_ach_name)
	_today_ach_sub = _label("", 17, MUTED)
	_today_ach_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	at.add_child(_today_ach_sub)

	# Friends card (hidden until Steam answers, or if your friends list is private).
	_fr_card = PanelContainer.new()
	_fr_card.add_theme_stylebox_override("panel", _card())
	Rounded.rough(_fr_card)
	_fr_card.visible = false
	right.add_child(_fr_card)
	var frv := VBoxContainer.new()
	frv.add_theme_constant_override("separation", 4)
	_fr_card.add_child(frv)
	frv.add_child(_label("Friends", 18, MUTED))
	_fr_title = _label("", 24, TEXT)
	frv.add_child(_fr_title)
	_fr_sub = _label("", 17, MUTED)
	_fr_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	frv.add_child(_fr_sub)

# ---------- This week, Try something new, Friends ----------
func _draw_week() -> void:
	var w: Dictionary = _week
	if w.is_empty():
		return
	var days: Array = w["days"]
	var peak := 60.0
	for m in days:
		peak = maxf(peak, float(m))
	var sz := _wk_chart.size
	var slot := sz.x / 7.0
	var font := ThemeDB.fallback_font
	var today_dow := int(Time.get_datetime_dict_from_system()["weekday"])  # 0 = Sunday
	for i in 7:
		var bar_h := (sz.y - 24.0) * float(days[i]) / peak
		var x := slot * i + slot * 0.2
		var on := i == 6
		_wk_chart.draw_rect(Rect2(x, sz.y - 24.0 - maxf(bar_h, 3.0), slot * 0.6, maxf(bar_h, 3.0)), Themes.ink(0.9 if on else (0.5 if float(days[i]) > 0.0 else 0.14)))
		var letter: String = "SMTWTFS"[posmod(today_dow - (6 - i), 7)]
		_wk_chart.draw_string(font, Vector2(slot * i, sz.y - 4.0), letter, HORIZONTAL_ALIGNMENT_CENTER, slot, 16, TEXT if on else MUTED)

func fill_week() -> void:
	_week = Sessions.week()
	var total := float(_week["total"])
	_wk_total.text = ("%.1f h" % (total / 60.0)) if total >= 60.0 else ("%d min" % roundi(total))
	var bits: Array = []
	if int(_week["streak"]) >= 2:
		bits.append("%d-day streak" % int(_week["streak"]))
	if str(_week["top_id"]) != "":
		bits.append("most: " + str(titles.get(str(_week["top_id"]), "?")))
	_wk_sub.text = "  ·  ".join(bits) if not bits.is_empty() else "Play something to start your week."
	_wk_chart.queue_redraw()

## A game you own and have never played; the pick changes once a day.
func fill_suggestion() -> void:
	var fresh: Array = []
	for g in games:
		if int(g.get("playtime", 0)) == 0:
			fresh.append(g)
	_sg_cover.texture = null
	if fresh.is_empty():
		_sg_name.text = "You've tried them all"
		_sg_sub.text = "Nothing unplayed here."
		return
	var pick: Dictionary = fresh[Sessions.day_of(int(Time.get_unix_time_from_system())) % fresh.size()]
	_sg_name.text = str(pick["title"])
	_sg_sub.text = "Never played"
	if art_loader.is_valid():
		art_loader.call(str(pick["id"]), "library_600x900", _sg_cover)

## Called by home.gd with what Steam says about your friends: {ok, online, total, playing: [[name, game]]}.
func fill_friends(d: Dictionary) -> void:
	_fr_card.visible = bool(d.get("ok", false))
	if not _fr_card.visible:
		return
	var online := int(d.get("online", 0))
	_fr_title.text = "%d online" % online if online > 0 else "No one online"
	var playing: Array = d.get("playing", [])
	if playing.is_empty():
		_fr_sub.text = "%d friends" % int(d.get("total", 0))
	else:
		var bits: Array = []
		for p in playing.slice(0, 2):
			bits.append("%s: %s" % [p[0], p[1]])
		_fr_sub.text = "  ·  ".join(bits)

# Performance page: how your games ran, and what this PC is.
func _build_perf_page(stack: Control) -> void:
	_page_perf = HBoxContainer.new()
	_page_perf.add_theme_constant_override("separation", 28)
	stack.add_child(_page_perf)
	_page_perf.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _card())
	Rounded.rough(left)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_perf.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	left.add_child(lv)
	lv.add_child(_label("How your games ran", 20, MUTED))
	_perf_rows = VBoxContainer.new()
	_perf_rows.add_theme_constant_override("separation", 14)
	lv.add_child(_perf_rows)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", _card())
	Rounded.rough(right)
	right.custom_minimum_size.x = 400
	_page_perf.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	rv.add_child(_label("This PC", 20, MUTED))
	_pc_rows = VBoxContainer.new()
	_pc_rows.add_theme_constant_override("separation", 8)
	rv.add_child(_pc_rows)

func _mini_bar(value: float, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0
	b.max_value = 100
	b.value = value
	b.custom_minimum_size = Vector2(96, 8)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Themes.ink(0.14)
	bg.set_corner_radius_all(Themes.r(4))
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(Themes.r(4))
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b

func fill_perf() -> void:
	if _perf_rows == null or perf == null:
		return
	for c in _perf_rows.get_children():
		_perf_rows.remove_child(c)
		c.queue_free()
	for c in _pc_rows.get_children():
		_pc_rows.remove_child(c)
		c.queue_free()
	var list: Array = perf.summaries(4)
	if list.is_empty():
		var e := _label("Play a game and Tephra will record how hard your PC works. Averages for each game show up here.", 20, MUTED)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size.x = 480
		_perf_rows.add_child(e)
	for s in list:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var top := HBoxContainer.new()
		var name := _label(str(s["title"]), 22, TEXT)
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.custom_minimum_size.x = 120
		top.add_child(name)
		var mins := int(s["minutes"])
		top.add_child(_label(("%.1f h tracked" % (mins / 60.0)) if mins >= 60 else ("%d min tracked" % mins), 17, MUTED))
		row.add_child(top)
		var bars := HBoxContainer.new()
		bars.add_theme_constant_override("separation", 8)
		bars.add_child(_label("CPU", 17, MUTED))
		bars.add_child(_mini_bar(float(s["cpu"]), TEXT))
		bars.add_child(_label("%d%%" % roundi(float(s["cpu"])), 17, TEXT))
		bars.add_child(_label("GPU", 17, MUTED))
		bars.add_child(_mini_bar(maxf(float(s["gpu"]), 0.0), Color("9FB4D0")))
		bars.add_child(_label(("%d%%" % roundi(float(s["gpu"]))) if float(s["gpu"]) >= 0.0 else "-", 17, TEXT))
		var extra := "%.1f GB" % float(s["ram_gb"])
		if float(s["cpu_t"]) > 0.0:
			extra += "  ·  %d°C" % roundi(float(s["cpu_t"]))
		bars.add_child(_label(extra, 17, MUTED))
		row.add_child(bars)
		_perf_rows.add_child(row)
	for pair in perf.system_info(steam_dir):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var k := _label(pair[0], 17, MUTED)
		k.custom_minimum_size.x = 92
		k.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		line.add_child(k)
		var v := _label(str(pair[1]), 19, TEXT)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.custom_minimum_size.x = 200
		line.add_child(v)
		_pc_rows.add_child(line)

# Fills the weather card from weather.gd's data.
func fill_weather() -> void:
	if _wx_icon == null:
		return
	var d: Dictionary = weather.data if weather != null else {}
	if d.is_empty():
		_wx_icon.texture = Icons.texture("wx_cloud", Icons.svg_weather("cloud"), 72)
		_wx_icon.modulate.a = 0.4
		_wx_temp.text = "Weather"
		_wx_text.text = "Loading..."
		_wx_sub.text = "Needs an internet connection."
		return
	var kind := Weather.kind_for(int(d["code"]), bool(d["is_day"]))
	_wx_icon.modulate.a = 1.0
	_wx_icon.texture = Icons.texture("wx_" + kind, Icons.svg_weather(kind), 72)
	var unit := "°C" if d.get("unit_c", false) else "°F"
	_wx_temp.text = "%d%s" % [d["temp"], unit]
	_wx_text.text = "%s  ·  %s" % [Weather.text_for(int(d["code"]), bool(d["is_day"])), d.get("city", "")]
	_wx_sub.text = "H %d°  L %d°  ·  Rain %d%%" % [d["hi"], d["lo"], d["rain"]]

func _tile(parent: Control, caption: String) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _card())
	Rounded.rough(p)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var big := _label("", 40, TEXT)
	vb.add_child(big)
	vb.add_child(_label(caption, 18, MUTED))
	return big

# Achievements page: title, white "14 / 24" bar, filter chips, scrolling list.
func _build_achievements_page(stack: Control) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card())
	Rounded.rough(card)
	stack.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_ach = card
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 14)
	card.add_child(cv)
	var head := HBoxContainer.new()
	cv.add_child(head)
	_title = _label("Achievements", 30, TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_count = _label("", 32, TEXT)
	head.add_child(_count)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 14
	var bbg := StyleBoxFlat.new()
	bbg.bg_color = Themes.ink(0.14)
	bbg.set_corner_radius_all(Themes.r(7))
	var bfill := StyleBoxFlat.new()
	bfill.bg_color = TEXT
	bfill.set_corner_radius_all(Themes.r(7))
	_bar.add_theme_stylebox_override("background", bbg)
	_bar.add_theme_stylebox_override("fill", bfill)
	cv.add_child(_bar)

	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 12)
	cv.add_child(_chips)
	for i in FILTERS.size():
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(Themes.r(20))
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		chip.add_theme_stylebox_override("panel", sb)
		var l := _label(FILTERS[i], 22, TEXT)
		chip.add_child(l)
		_chips.add_child(chip)
		_chip_styles.append(sb)
		_chip_labels.append(l)
	_update_chips()

	_empty = _label("", 22, MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_empty)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	cv.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

func _update_chips() -> void:
	for i in _chip_styles.size():
		var on: bool = i == _filter
		_chip_styles[i].bg_color = SELECT if on else Themes.ink(0.1)
		_chip_labels[i].add_theme_color_override("font_color", Themes.c("on_select") if on else TEXT)

func refresh_hints() -> void:
	# Short labels: the hint bar must fit the screen width.
	var items: Array = [["l1", "Prev"], ["r1", "Next"]] if _names().size() > 1 else []
	if _kind() in ["ach", "game"] and _mode == "game":
		items.append(["dpad_h", "Filter"])
	if on_today():
		items.append(["dpad_h", "Choose"])
		items.append(["accept", "Play"])
	if _kind() in ["ach", "game"] or (_mode == "home" and _kind() == "today"):
		items.append(["dpad_v", "Scroll"])
	items.append(["back", "Back"])
	TephraGlyphs.fill(hints, items, 24)

# ---------- Filling ----------
## A game: the three pages.
func show_game(g: Dictionary) -> void:
	_mode = "game"
	_build_strip()
	_game = g
	_appid = str(g["id"])
	_filter = 0
	_update_chips()
	_global = {}
	about.show_game(g)
	_data = Achievements.for_game(steam_dir, account, _appid)
	_fill_stats(g)
	_rebuild_list()
	_load_global(_appid)
	_set_page(0, false)
	has_content = true

## Home: two pages, Today and Achievements (your newest unlocks across every game).
func show_recent() -> void:
	_mode = "home"
	_build_strip()
	about.hide_panel()
	_title.text = "Recent achievements"
	_clear()
	_bar.visible = false  # filled below: how much of the recently played games' achievements you have
	_chips.visible = false
	_earned_total = Achievements.total_unlocked(steam_dir, account)
	_count.text = "%d earned" % _earned_total if _earned_total > 0 else ""
	var recent := Achievements.recent(steam_dir, account, 12)
	_empty.visible = recent.is_empty()
	_empty.text = "Achievements you unlock will show up here."
	var seen := {}
	var got := 0
	var all := 0
	for r in recent:
		var game: String = titles.get(r["appid"], r["game"])
		_add_row(r["icon"], r["name"], r["desc"], game + "\n" + _date(r["time"]), true, r["appid"])
		if not seen.has(r["appid"]):
			seen[r["appid"]] = true
			var fg := Achievements.for_game(steam_dir, account, str(r["appid"]))
			got += int(fg.get("unlocked", 0))
			all += int(fg.get("total", 0))
	if all > 0:
		_bar.visible = true
		_bar.max_value = all
		_bar.value = got
		_count.text = "%d / %d" % [got, all]
	_fill_today(recent)
	fill_weather()
	fill_perf()
	fill_week()
	fill_suggestion()
	_set_page(0, false)
	has_content = true

# The Today page: last played game, newest achievement, free space.
func _fill_today(recent: Array) -> void:
	_recent_games = games.slice(0, 5)
	_today_sel = 0
	for i in _recent_thumbs.size():
		var th: Dictionary = _recent_thumbs[i]
		(th["panel"] as Control).visible = i < _recent_games.size() and _recent_games.size() > 1
		(th["tex"] as TextureRect).texture = null
		if i < _recent_games.size() and art_loader.is_valid():
			art_loader.call(str(_recent_games[i]["id"]), "library_600x900", th["tex"])
	_show_continue()
	if recent.is_empty():
		_today_ach_name.text = "None yet"
		_today_ach_sub.text = "Unlock one and it shows here."
		_today_ach_icon.texture = null
	else:
		var r: Dictionary = recent[0]
		_today_ach_name.text = r["name"]
		_today_ach_sub.text = "%s  ·  %s" % [titles.get(r["appid"], r["game"]), _short_date(int(r["time"]))]
		_today_ach_icon.texture = null
		load_icon(r["icon"], r["appid"], _today_ach_icon)
	# Storage on the drive Steam lives on.
	var out: Array = []
	if OS.execute("df", ["-B1", "--output=avail,size", steam_dir], out) == 0 and out.size() > 0:
		var lines := String(out[0]).strip_edges().split("\n")
		if lines.size() >= 2:
			var parts := lines[1].strip_edges().split(" ", false)
			if parts.size() >= 2:
				_store["avail"] = float(parts[0])
				_store["total"] = float(parts[1])
	var games_bytes := 0.0
	for g in games:
		games_bytes += float(g.get("size", 0))
	_store["games"] = games_bytes
	_scan_storage()
	_store_chart.queue_redraw()

## Measuring Proton data and Workshop files means reading a lot of folders, so it happens on a
## background thread, at most every 10 minutes.
func _scan_storage() -> void:
	if _store_scanning or Time.get_unix_time_from_system() - _store_scan_at < 600.0:
		return
	_store_scanning = true
	var base := steam_dir + "/steamapps"
	_store_task = WorkerThreadPool.add_task(func():
		var res := {}
		for k in ["compatdata", "shadercache", "workshop"]:
			var o: Array = []
			OS.execute("du", ["-sb", base + "/" + k], o)
			res[k] = float(str(o[0]).split("\t")[0].to_int()) if o.size() > 0 else 0.0
		res["home_games"] = _home_game_bytes()
		_store_scanned.call_deferred(res))

## Games kept outside Steam in a folder called "game" or "games" (any capitals) in your home folder,
## like ~/Games/P.T. They count as Games on the storage bar instead of Other. Only folders on the same
## drive as Steam count (the bar is about that drive), and never one that holds Steam itself.
func _home_game_bytes() -> float:
	var home := OS.get_environment("HOME")
	var dir := DirAccess.open(home)
	if dir == null:
		return 0.0
	var steam_dev := _device_of(steam_dir)
	var total := 0.0
	for d in dir.get_directories():
		var low := d.to_lower()
		if low != "game" and low != "games":
			continue
		var path := home + "/" + d
		if steam_dir.begins_with(path + "/") or _device_of(path) != steam_dev:
			continue
		var o: Array = []
		OS.execute("du", ["-sb", path], o)
		total += float(str(o[0]).split("\t")[0].to_int()) if o.size() > 0 else 0.0
	return total

static func _device_of(path: String) -> String:
	var o: Array = []
	OS.execute("stat", ["-L", "-c", "%d", path], o)
	return str(o[0]).strip_edges() if o.size() > 0 else ""

func _exit_tree() -> void:
	if _store_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_store_task)  # never quit while the folder scan is still running

func _store_scanned(res: Dictionary) -> void:
	_store_scanning = false
	_store_scan_at = Time.get_unix_time_from_system()
	_store["proton"] = float(res.get("compatdata", 0.0)) + float(res.get("shadercache", 0.0))
	_store["workshop"] = float(res.get("workshop", 0.0))
	_store["home_games"] = float(res.get("home_games", 0.0))
	if _store_chart != null:
		_store_chart.queue_redraw()

func _draw_store() -> void:
	var total := float(_store.get("total", 0.0))
	if total <= 0.0:
		return
	var avail := float(_store.get("avail", 0.0))
	var games_b := float(_store.get("games", 0.0)) + float(_store.get("home_games", 0.0))  # Steam's and ~/Games
	var proton := float(_store.get("proton", 0.0))
	var workshop := float(_store.get("workshop", 0.0))
	var other := maxf(total - avail - games_b - proton - workshop, 0.0)
	var segs := [
		["Games", games_b, Color("3D8BFF")],
		["Proton", proton, Color("8B6CFF")],
		["Workshop", workshop, Color("46D17B")],
		["Other", other, Color("FFC857")],
		["Free", avail, Themes.ink(0.16)],
	]
	var w := _store_chart.size.x
	var x := 0.0
	for sg in segs:
		var sw := w * float(sg[1]) / total
		if sw < 1.0:
			continue
		_store_chart.draw_rect(Rect2(x, 0, maxf(sw - 2.0, 1.0), 10), sg[2])
		x += sw
	# One line of legend underneath: a coloured dot, the name and the size.
	var font := ThemeDB.fallback_font
	var lx := 0.0
	for sg in segs:
		if float(sg[1]) < 52428800.0 and sg[0] != "Free":  # under 50 MB: not worth a label
			continue
		var gb := float(sg[1]) / 1073741824.0
		var label := "%s %s" % [sg[0], ("%.1f GB" % gb) if gb < 10.0 else ("%d GB" % roundi(gb))]
		_store_chart.draw_circle(Vector2(lx + 5.0, 32.0), 5.0, MUTED if sg[0] == "Free" else sg[2])
		_store_chart.draw_string(font, Vector2(lx + 16.0, 38.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MUTED)
		lx += 16.0 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 22.0

# The Continue card follows the recent game that is selected.
func _show_continue() -> void:
	if _recent_games.is_empty():
		_today_name.text = "No games yet"
		_today_sub.text = "Install one from the Library."
		_today_cover.texture = null
	else:
		var g: Dictionary = _recent_games[_today_sel]
		_today_name.text = g["title"]
		var bits: Array = []
		if int(g.get("last", 0)) > 0:
			bits.append("Last played " + _short_date(int(g["last"])))
		var mins := int(g.get("playtime", 0))
		if mins > 0:
			bits.append(("%.1f h played" % (mins / 60.0)) if mins >= 60 else ("%d min played" % mins))
		_today_sub.text = "\n".join(bits)
		_today_cover.texture = null
		if art_loader.is_valid():
			art_loader.call(str(g["id"]), "library_600x900", _today_cover)
	for i in _recent_thumbs.size():
		var th: Dictionary = _recent_thumbs[i]
		(th["frame"] as StyleBoxFlat).set_border_width_all(3 if (_entered and i == _today_sel) else 0)
		(th["panel"] as Control).modulate.a = 1.0 if (not _entered or i == _today_sel) else 0.55

## Today page: left/right picks a recent game, A plays it.
func today_move(d: int) -> void:
	if _recent_games.size() < 2:
		return
	_today_sel = posmod(_today_sel + d, _recent_games.size())
	_show_continue()

func today_activate() -> void:
	if not _recent_games.is_empty():
		play_requested.emit(str(_recent_games[_today_sel]["id"]))

func on_today() -> bool:
	return _mode == "home" and _kind() == "today" and not _recent_games.is_empty()

func hide_all() -> void:
	has_content = false
	about.hide_panel()

# The Stats page: ring + tiles + "Next up".
func _fill_stats(g: Dictionary) -> void:
	var mins := int(g.get("playtime", 0))
	_t_play.text = ("%.1f h" % (mins / 60.0)) if mins >= 60 else ("%d min" % mins if mins > 0 else "-")
	var last := int(g.get("last", 0))
	_t_last.text = _short_date(last) if last > 0 else "Never"
	var size := float(g.get("size", 0))
	if size >= 1073741824.0:
		_t_size.text = "%d GB" % maxi(1, roundi(size / 1073741824.0))
	elif size > 0:
		_t_size.text = "%d MB" % roundi(size / 1048576.0)
	else:
		_t_size.text = "-"
	if _data.is_empty():
		_ring.fraction = 0.0
		_ring.set_text("-", "no achievements")
	else:
		_ring.set_text("%d / %d" % [_data["unlocked"], _data["total"]], "achievements")
		_ring.fraction = 0.0
		create_tween().tween_property(_ring, "fraction", float(_data["unlocked"]) / maxf(float(_data["total"]), 1.0), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_update_next_up()

func _update_next_up() -> void:
	var locked := _locked_by_ease()
	if locked.is_empty():
		_next_icon.texture = null
		_next_name.text = "All done!" if not _data.is_empty() else "No achievements"
		_next_desc.text = "You have every achievement." if not _data.is_empty() else ""
		return
	var a: Dictionary = locked[0]
	if a["hidden"]:
		_next_name.text = "Hidden achievement"
		_next_desc.text = "Keep playing to find out."
	else:
		_next_name.text = a["name"]
		var pct := _percent(a)
		_next_desc.text = a["desc"] + ("   (%.1f%% of players)" % pct if pct >= 0.0 else "")
	_next_icon.texture = null
	load_icon(a["icon"], _appid, _next_icon)

# ---------- Achievement list ----------
func _percent(a: Dictionary) -> float:
	return float(_global.get(a.get("api", ""), -1.0))

# Locked achievements, the ones most players have first (the easy ones).
func _locked_by_ease() -> Array:
	var out: Array = []
	for a in _data.get("list", []):
		if not a["unlocked"]:
			out.append(a)
	if not _global.is_empty():
		out.sort_custom(func(x, y): return _percent(x) > _percent(y))
	return out

func _rebuild_list() -> void:
	_title.text = "Achievements" + ("  ·  RetroAchievements" if str(_data.get("source", "")) == "retro" else "")
	_chips.visible = true
	_clear()
	if _data.is_empty():
		_count.text = ""
		_bar.visible = false
		_empty.text = "No achievements found on this PC for this game yet." if _filter != 2 \
			else "Steam hasn't saved this game's achievement list on this PC yet, so the ones you haven't earned can't be shown. Start the game once and they'll appear here."
		_empty.visible = true
		return
	_count.text = "%d / %d" % [_data["unlocked"], _data["total"]]
	_bar.visible = true
	_bar.max_value = _data["total"]
	_bar.value = _data["unlocked"]
	_empty.visible = false
	var list: Array = _data["list"].duplicate()
	match _filter:
		1:  # rarest first (needs Steam's global numbers; unknown ones go last)
			list.sort_custom(func(x, y):
				var px := _percent(x)
				var py := _percent(y)
				return (px if px >= 0.0 else 999.0) < (py if py >= 0.0 else 999.0))
		2:  # not earned
			list = _locked_by_ease()
	for a in list:
		var right := ""
		var pct := _percent(a)
		if _filter == 0:
			right = _date(a["time"]) if a["unlocked"] else "Locked"
		else:
			right = ("%.1f%% of players" % pct) if pct >= 0.0 else ""
			if a["unlocked"]:
				right += ("\n" if right != "" else "") + _date(a["time"])
		var name: String = a["name"]
		var desc: String = a["desc"]
		if a["hidden"] and not a["unlocked"]:
			name = "Hidden achievement"
			desc = "Keep playing to find out."
		_pending.append([a["icon"], name, desc, right, a["unlocked"], _appid])
	_build_pending(FIRST_ROWS)
	if list.is_empty():
		_empty.visible = true
		_empty.text = "Nothing here - you have every achievement!" if _filter == 2 else ""

## Builds up to n of the waiting rows.
func _build_pending(n: int) -> void:
	var made := 0
	while made < n and not _pending.is_empty():
		var r: Array = _pending.pop_front()
		_add_row(r[0], r[1], r[2], r[3], r[4], r[5])
		made += 1

func _clear() -> void:
	_pending.clear()
	if _scroll_tween != null:
		_scroll_tween.kill()  # an old scroll animation must not move the new list
	for r in _rows:
		# Take the old rows out of the list right away: queue_free alone leaves them
		# in place for the rest of the frame, and the new rows would be laid out after them.
		_list.remove_child(r["panel"])
		r["panel"].queue_free()
	_rows.clear()
	_icon_queue.clear()
	_sel = -1
	_scroll.scroll_vertical = 0

func _add_row(icon_url: String, name: String, desc: String, right: String, unlocked: bool, appid: String) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.0)
	sb.border_color = SELECT
	sb.set_corner_radius_all(Themes.r(14))
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	p.add_child(h)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(icon)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(tv)
	var n := _label(name, 24, TEXT)
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(n)
	var d := _label(desc, 19, MUTED)
	d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(d)
	var r := _label(right, 19, MUTED)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(r)
	if not unlocked:
		h.modulate = Color(1, 1, 1, 0.5)  # locked: faded
	_list.add_child(p)
	_rows.append({"panel": p, "style": sb})
	load_icon(icon_url, appid, icon)

func _date(t: int) -> String:
	if t <= 0:
		return ""
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%s %d, %d" % [MONTHS[int(d["month"]) - 1], d["day"], d["year"]]

func _short_date(t: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%s %d" % [MONTHS[int(d["month"]) - 1], d["day"]]

# ---------- Global rarity (Steam's public numbers, no key needed) ----------
func _load_global(appid: String) -> void:
	var path := "user://ach/%s_global.json" % appid
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and d.get("p") is Dictionary:
			_global = d["p"]
			if Time.get_unix_time_from_system() - float(d.get("fetched", 0)) < GLOBAL_DAYS * 86400:
				_update_next_up()
				if _filter != 0:
					_rebuild_list()  # only the other filters show rarity; the list is already right
				return
	if _data.is_empty():
		return
	_gid = appid
	_greq.cancel_request()
	_greq.request(GLOBAL_URL % appid)

func _on_global(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary and d.get("achievementpercentages") is Dictionary):
		return
	var p := {}
	for a in d["achievementpercentages"].get("achievements", []):
		p[str(a.get("name", ""))] = float(a.get("percent", 0))
	if p.is_empty():
		return
	var f := FileAccess.open("user://ach/%s_global.json" % _gid, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"fetched": Time.get_unix_time_from_system(), "p": p}))
	if _gid == _appid:
		_global = p
		_update_next_up()
		var keep := _sel
		_rebuild_list()
		if keep >= 0:
			_select(mini(keep, _rows.size() - 1))

# ---------- Icons (downloaded once, then cached) ----------
## Shows an achievement icon from Tephra's cache, or downloads it from Steam.
func load_icon(url: String, appid: String, target: TextureRect) -> void:
	if url.ends_with("/"):
		return  # this achievement has no icon
	var path := "user://ach/%s_%s" % [appid, url.get_file()]
	if FileAccess.file_exists(path):
		target.texture = _tex(path)
		return
	_icon_queue.append([url, path, target])
	_pump()

func _pump() -> void:
	while _icon_active < MAX_DOWNLOADS and not _icon_queue.is_empty():
		var job: Array = _icon_queue.pop_front()
		if not is_instance_valid(job[2]):
			continue
		_icon_active += 1
		var req := HTTPRequest.new()
		add_child(req)
		req.download_file = job[1]
		req.request_completed.connect(func(result: int, code: int, _h, _b):
			req.queue_free()
			_icon_active -= 1
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				if is_instance_valid(job[2]):
					job[2].texture = _tex(job[1])
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(job[1]))
			_pump())
		if req.request(job[0]) != OK:
			req.queue_free()
			_icon_active -= 1

func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	if _tex_cache.size() > 400:
		_tex_cache.clear()
	var t := _tex_load(path)
	if t != null:
		_tex_cache[path] = t
	return t

func _tex_load(path: String) -> Texture2D:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)

# ---------- Pages ----------
func _set_page(i: int, animate := true) -> void:
	_page = clampi(i, 0, _names().size() - 1)
	var kind := _kind()
	if _focus_tween != null:
		_focus_tween.kill()
	for c in [_page_today, _page_stats, about]:
		c.modulate.a = 1.0
	_strip.visible = true
	_page_stats.visible = kind == "stats"
	about.visible = kind == "desc"
	var home_today := _mode == "home" and kind == "today"
	_page_ach.visible = kind == "ach" or home_today or kind == "game"
	_page_today.visible = kind == "today"
	_page_stats.visible = kind == "game"
	about.visible = kind == "game"
	if home_today or kind == "game":
		_place_home_ach.call_deferred()
	else:
		_page_ach.offset_top = 0
	_page_perf.visible = kind == "perf"
	var shown: Control = {"stats": _page_stats, "desc": about, "ach": _page_ach, "today": _page_today, "perf": _page_perf, "game": _page_stats}[kind]
	if animate:
		Motion.pop(shown, 0.97, 0.22)
		Haptics.tick()
	else:
		shown.modulate.a = 1.0
	_update_strip()
	refresh_hints()

## Home's Today page: the recent achievements card starts under the Today cards.
func _place_home_ach() -> void:
	if _mode == "home" and _kind() == "today":
		_ach_top = _page_today.size.y + 24.0
		_ach_focus(_sel >= 0, false)
	elif _kind() == "game":
		# A game's page, top to bottom: the stats, the description, then the achievements filling the rest.
		about.offset_top = _page_stats.size.y + 20.0
		about.offset_bottom = about.offset_top + about.get_combined_minimum_size().y
		_ach_top = about.offset_bottom + 20.0
		_ach_focus(_sel >= 0, false)

## Walking into the achievements list: the cards above fade out and the list slides up
## to fill the page, so every row can be seen. Up past the first row brings them back.
func _ach_focus(on: bool, animate := true) -> void:
	var above: Array = [_page_today] if _kind() == "today" else [_page_stats, about]
	var top := 0.0 if on else _ach_top
	if _focus_tween != null:
		_focus_tween.kill()
	if not animate or not Motion.on():
		_page_ach.offset_top = top
		for c in above:
			c.modulate.a = 0.0 if on else 1.0
		return
	_focus_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(_page_ach, "offset_top", top, 0.25)
	for c in above:
		_focus_tween.tween_property(c, "modulate:a", 0.0 if on else 1.0, 0.2)

## L1 / R1: previous or next page (games only).
func page_step(d: int) -> void:
	var np := posmod(_page + d, _names().size())  # L1 / R1 loop round the pages
	if np == _page:
		return
	_set_page(np)
	_select(0 if (_kind() == "ach" and not _rows.is_empty()) else -1)

## D-pad Left/Right on the Achievements page: change the filter.
func filter_step(d: int) -> void:
	if _mode == "home" and _kind() == "today":
		today_move(d)
		return
	if _mode != "game" or not _kind() in ["ach", "game"]:
		return
	_filter = posmod(_filter + d, FILTERS.size())
	_update_chips()
	_rebuild_list()
	_select(0 if not _rows.is_empty() else -1)

# ---------- Navigation (called by home.gd) ----------
## Strip (inside the section) or arrow (on the row): only one is visible at a time.
func _show_strip(on: bool) -> void:
	_entered = on

# Every frame: fade the strip / arrow, and bob the arrow gently (by position, so it stays smooth).
func _process(delta: float) -> void:
	if not _pending.is_empty():
		_build_pending(ROWS_PER_FRAME)
	if Themes.id() == "frutiger":
		_sheet.modulate.a = move_toward(_sheet.modulate.a, 1.0 if _entered else 0.0, delta * 5.0)  # nothing white under the row: the grass stays whole
	_strip.modulate.a = move_toward(_strip.modulate.a, 1.0 if _entered else 0.0, delta * 5.0)
	var arrow_target := 0.0 if (_entered or hide_arrow) else 0.75
	_arrow.modulate.a = move_toward(_arrow.modulate.a, arrow_target, delta * 5.0)
	_arrow_box.position.x = 0
	_arrow.position = Vector2((_arrow_box.size.x - 44) / 2.0, 14.0 + 6.0 * sin(Time.get_ticks_msec() / 1000.0 * 4.0))

## The screen has scrolled down to this section.
func enter() -> void:
	_show_strip(true)
	_show_continue()
	_select(0 if (_kind() == "ach" and not _rows.is_empty()) else -1)

## The screen is going back up to the row.
func leave() -> void:
	_show_strip(false)
	_show_continue()
	_select(-1)
	_glide_to(0)
	# Once the section has slid away, go back to the first page, so it opens fresh next time.
	await get_tree().create_timer(0.5).timeout
	if not _entered and has_content:
		_set_page(0, false)

## Up/down. On the achievements list it moves through the rows. Returns false when
## Up is pressed at the top (or on the Stats/Description pages): "go back up to the games".
func move(dir: int) -> bool:
	if ((_mode == "home" and _kind() == "today") or _kind() == "game") and not _rows.is_empty():
		# Down walks from the Today cards into the recent achievements; Up walks back, then leaves.
		if dir < 0 and _sel < 0:
			return false
		_select(clampi(_sel + dir, -1, _rows.size() - 1))
		return true
	if _kind() != "ach" or _rows.is_empty():
		return dir > 0
	if _sel <= 0 and dir < 0:
		return false
	_select(clampi(_sel + dir, 0, _rows.size() - 1))
	return true

## Fast scroll (right stick): jump several rows, stopping at the ends.
func scroll_by(n: int) -> void:
	if (_kind() != "ach" and _kind() != "game" and not (_mode == "home" and _kind() == "today")) or _rows.is_empty():
		return
	_select(clampi(_sel + n, 0, _rows.size() - 1))

func _select(i: int) -> void:
	var was := _sel
	_sel = i
	if ((_mode == "home" and _kind() == "today") or _kind() == "game") and (was >= 0) != (i >= 0):
		_ach_focus(i >= 0)
	for j in _rows.size():
		var sb: StyleBoxFlat = _rows[j]["style"]
		var on := j == _sel
		sb.set_border_width_all(3 if on else 0)
		sb.bg_color = Themes.ink(0.07 if on else 0.0)
	if _sel >= 0:
		_keep_visible.call_deferred(_rows[_sel]["panel"])

# Glides the list so the highlighted achievement stays on screen.
func _keep_visible(row: Control) -> void:
	if not is_instance_valid(row):
		return
	var top := row.position.y
	var bottom := top + row.size.y
	var view := _scroll.size.y
	var target := float(_scroll.scroll_vertical)
	if top < target:
		target = top
	elif bottom > target + view:
		target = bottom - view
	else:
		return
	_glide_to(target)

func _glide_to(target: float) -> void:
	if _scroll_tween != null:
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_scroll, "scroll_vertical", int(target), 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
