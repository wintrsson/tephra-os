extends CanvasLayer
## Tephra Page view: the web page drawn by Tephra, in the theme, instead of Firefox's own picture of it.
## Firefox stays the engine (it loads the page, runs its scripts, keeps the tabs and the logins). Tephra asks it for
## the page's text, links, pictures and buttons (assets/page_extract.js, over marionette.gd), draws them itself, and
## presses things on the real page when you choose them. Heavy sites and video: "Back to the live page" in the menu.
##
## Up/Down: next/previous thing you can press. Left/Right: the next link in a line. Right stick: scroll.
## Cross: press. Circle: back (or close on the first page). Triangle: address. Square: menu. L1/R1: tabs.
## Start: the live page. Rules (blocked and allowed sites) live in ~/.config/tephra/browser_rules.json.

signal closed(to_live: bool)

const Themes = preload("res://themes.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Motion = preload("res://motion.gd")
const Haptics = preload("res://haptics.gd")
const Icons = preload("res://icons.gd")
const Marionette = preload("res://marionette.gd")

const COL_W := 1180.0
const FONT := 28
const MAX_IMAGES := 40
const MAX_PARALLEL := 3
const DEFAULT_BLOCK := ["doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
	"googletagmanager.com", "adnxs.com", "taboola.com", "outbrain.com", "scorecardresearch.com", "criteo.com",
	"adsrvr.org", "pubmatic.com", "rubiconproject.com", "amazon-adsystem.com", "moatads.com", "quantserve.com"]
const UA := "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"

var is_open := false
var _home
var _mar: Node
var _root: Control
var _tab_row: HBoxContainer
var _site: Label
var _page_title: Label
var _scroll: ScrollContainer
var _col: VBoxContainer
var _status: Label
var _hints: HBoxContainer
var _menu_box: PanelContainer
var _menu_list: VBoxContainer

var _page: Dictionary = {}
var _items: Array = []            # per block: {"block", "ctl", "panel", "style", "rtl", "links": [ids], "runs"}
var _stops: Array = []            # indexes into _items that can be pressed
var _focus := -1                  # index in _stops
var _link := 0                    # which link inside the focused block
var _busy := false
var _gen := 0                     # bumps whenever the page changes: late answers for an older page are dropped
var _handles: Array = []
var _tab := 0
var _titles := {}                 # handle -> {"title", "url"}
var _depth := {}                  # handle -> how many pages Page view has gone forward (so Back knows)
var _extract_src := ""
var _menu_open := false
var _menu_rows: Array = []
var _menu_sel := 0
var _rules := {"block": [], "allow_only": false, "allow": []}
var _img_cache := {}              # url -> Texture2D (or null for "can't")
var _img_queue: Array = []        # [{url, rect, holder}]
var _img_active := 0
var _img_count := 0
var _scroll_tween: Tween

func setup(home) -> void:
	_home = home

# ---------- Building ----------
func _ready() -> void:
	layer = 82
	_mar = Marionette.new()
	add_child(_mar)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Themes.c("bg")
	_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var anim = preload("res://tephra_bg.gd").new()
	anim.set("plain", true)
	_root.add_child(anim)
	anim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 36)
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margin.add_child(v)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 10)
	v.add_child(_tab_row)
	var addr := HBoxContainer.new()
	addr.add_theme_constant_override("separation", 22)
	v.add_child(addr)
	_site = _label("", 36, Themes.c("text"))
	_site.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_site.custom_minimum_size.x = 520
	addr.add_child(_site)
	_page_title = _label("", 24, Themes.c("muted"))
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	addr.add_child(_page_title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	v.add_child(_scroll)
	var wrap := MarginContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("margin_top", 10)
	wrap.add_theme_constant_override("margin_bottom", 200)
	_scroll.add_child(wrap)
	_col = VBoxContainer.new()
	_col.custom_minimum_size.x = COL_W
	_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_col.add_theme_constant_override("separation", 16)
	wrap.add_child(_col)
	_status = _label("", 24, Themes.c("muted"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(_hints)
	# the menu (Square)
	_menu_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Themes.c("card"), 0.98)
	sb.border_color = Themes.c("select")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(Themes.r(18))
	sb.set_content_margin_all(24)
	_menu_box.add_theme_stylebox_override("panel", sb)
	_menu_box.visible = false
	_root.add_child(_menu_box)
	_menu_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu_list = VBoxContainer.new()
	_menu_list.add_theme_constant_override("separation", 6)
	_menu_box.add_child(_menu_list)

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# ---------- Rules ----------
static func rules_path() -> String:
	return OS.get_environment("HOME") + "/.config/tephra/browser_rules.json"

func _load_rules() -> void:
	_rules = {"block": [], "allow_only": false, "allow": []}
	var f := FileAccess.open(rules_path(), FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_rules["block"] = (d.get("block", []) as Array).duplicate() if d.get("block") is Array else []
		_rules["allow"] = (d.get("allow", []) as Array).duplicate() if d.get("allow") is Array else []
		_rules["allow_only"] = bool(d.get("allow_only", false))

func _save_rules() -> void:
	DirAccess.make_dir_recursive_absolute(rules_path().get_base_dir())
	var f := FileAccess.open(rules_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_rules, "\t"))

static func host_of(url: String) -> String:
	var s := url.get_slice("://", 1) if "://" in url else url
	s = s.get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	if "@" in s:
		s = s.get_slice("@", 1)
	s = s.get_slice(":", 0).to_lower()
	return s.trim_prefix("www.")

static func _host_in(host: String, list: Array) -> bool:
	for d in list:
		var dom := str(d).to_lower().trim_prefix("www.")
		if dom != "" and (host == dom or host.ends_with("." + dom)):
			return true
	return false

## Why this address may not be opened ("" = fine). about: pages and blank are always fine.
func blocked_reason(url: String) -> String:
	if url == "" or url.begins_with("about:") or url.begins_with("data:"):
		return ""
	var h := host_of(url)
	if h == "":
		return ""
	if _host_in(h, _rules["block"]) or _host_in(h, DEFAULT_BLOCK):
		return "%s is blocked." % h
	if bool(_rules["allow_only"]) and not _host_in(h, _rules["allow"]):
		return "%s isn't on your allowed list." % h
	return ""

# ---------- Open / close ----------
func open() -> void:
	if is_open:
		return
	is_open = true
	_menu_open = false
	_menu_box.visible = false
	_load_rules()
	_busy = true
	_root.visible = true
	_root.modulate.a = 0.0
	Motion.fade_to(_root, 1.0, 0.2)
	_clear_page()
	_site.text = "Page view"
	_page_title.text = ""
	_set_status("Connecting to the browser...")
	_refresh_hints()
	if _extract_src == "":
		_extract_src = FileAccess.get_file_as_string("res://assets/page_extract.js")
	_mar.open_session(_session_ready)

func close(to_live := false) -> void:
	if not is_open:
		return
	is_open = false
	_gen += 1
	_mar.close()
	_img_queue.clear()
	closed.emit(to_live)
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, Motion.dur(0.2))
	await t.finished
	if not is_open:
		_root.visible = false
		_clear_page()

func _session_ready(ok: bool) -> void:
	if not is_open:
		return
	if not ok:
		_busy = false
		_set_status(str(_mar.error) + " Press " + TephraGlyphs.btn("back") + ", then choose Close browser in the Browser card and open it again.")
		return
	_mar.command("WebDriver:GetWindowHandles", {}, func(ok2: bool, v) -> void:
		if not is_open:
			return
		_handles = _as_list(v) if ok2 else []
		_mar.command("WebDriver:GetWindowHandle", {}, func(ok3: bool, cur) -> void:
			if ok3:
				var h := _as_text(cur)
				var i := _handles.find(h)
				_tab = maxi(i, 0)
			_extract(0, true)))

static func _as_list(v) -> Array:
	if v is Array:
		return v
	if v is Dictionary and (v as Dictionary).get("value") is Array:
		return (v as Dictionary)["value"]
	return []

static func _as_text(v) -> String:
	if v is Dictionary:
		return str((v as Dictionary).get("value", ""))
	return str(v)

func _handle() -> String:
	return str(_handles[_tab]) if _tab >= 0 and _tab < _handles.size() else ""

# ---------- Reading the page ----------
func _set_status(text: String) -> void:
	_status.text = text

## Waits for the page to finish loading, then reads it. keep = keep the place on the page (same page, new state).
func _extract(attempt: int, fresh := false, keep := false) -> void:
	if not is_open:
		return
	_busy = true
	var gen := _gen
	_set_status("Loading..." if attempt > 0 or fresh else "")
	_mar.script("return document.readyState + '|' + location.href;", [], func(ok: bool, v) -> void:
		if not is_open or gen != _gen:
			return
		var state := str(v).get_slice("|", 0) if ok else ""
		if (not ok or state == "loading" or (state == "interactive" and attempt < 4) or (state != "complete" and state != "interactive")) and attempt < 18:
			await get_tree().create_timer(0.5).timeout
			_extract(attempt + 1, fresh, keep)
			return
		var url := str(v).get_slice("|", 1) if ok else ""
		var why := blocked_reason(url)
		if why != "":
			_blocked_page(url, why)
			return
		_mar.script(_extract_src, [], func(ok2: bool, res) -> void:
			if not is_open or gen != _gen:
				return
			if not ok2:
				_busy = false
				_set_status("Couldn't read this page (%s). The live page still works." % str(res))
				return
			var d = JSON.parse_string(str(res))
			if not d is Dictionary:
				_busy = false
				_set_status("Couldn't read this page. The live page still works.")
				return
			# Pages that build themselves with scripts are often empty at first: look once more.
			if (d["b"] as Array).size() < 4 and attempt < 14 and not keep:
				await get_tree().create_timer(1.0).timeout
				_extract(attempt + 6, fresh, keep)
				return
			_show_page(d, keep)))

func _blocked_page(url: String, why: String) -> void:
	_busy = false
	_show_page({"u": url, "t": "Blocked", "b": [{"t": "h", "l": 2, "r": [[why, 0]]},
		{"t": "note", "x": TephraGlyphs.btn("west") + " > Unblock puts it back. " + TephraGlyphs.btn("back") + " goes back."}], "n": 0, "x": 0}, false)

func _show_page(d: Dictionary, keep: bool) -> void:
	var old_url := str(_page.get("u", ""))
	var same := keep and old_url == str(d.get("u", ""))
	var old_scroll := _scroll.scroll_vertical
	var old_focus := _focus
	_page = d
	var h := _handle()
	if h != "":
		_titles[h] = {"title": str(d.get("t", "")), "url": str(d.get("u", ""))}
	_build_blocks()
	_site.text = host_of(str(d.get("u", ""))) if str(d.get("u", "")) != "" else "Page view"
	_page_title.text = str(d.get("t", ""))
	_draw_tabs()
	_busy = false
	var note := ""
	if int(d.get("x", 0)) == 1:
		note = "This page is long: Tephra shows the first part. The live page has the rest."
	_set_status(note)
	_focus = -1
	if not _stops.is_empty():
		_focus = clampi(old_focus, 0, _stops.size() - 1) if same and old_focus >= 0 else 0
		_link = 0
		_apply_focus(false)
	await get_tree().process_frame
	await get_tree().process_frame
	if same:
		_scroll.scroll_vertical = old_scroll
	else:
		_scroll.scroll_vertical = 0
	_refresh_hints()

func _clear_page() -> void:
	for c in _col.get_children():
		c.queue_free()
	_items.clear()
	_stops.clear()
	_focus = -1
	_img_queue.clear()
	_img_count = 0

# ---------- Drawing the blocks ----------
static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")

func _bb(runs: Array, focus_link: int, color: Color) -> String:
	var sel := Themes.c("select")
	var out := ""
	for r in runs:
		var t := _esc(str(r[0]))
		var id := int(r[1])
		if id == 0:
			out += t
		elif id == focus_link:
			out += "[bgcolor=#%s][color=#%s]%s[/color][/bgcolor]" % [sel.to_html(false), Themes.c("bg").to_html(false), t]
		else:
			out += "[color=#%s][u]%s[/u][/color]" % [sel.lightened(0.25).to_html(false), t]
	return out

func _rtl(runs: Array, size: int, color: Color) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_size_override("normal_font_size", size)
	rt.add_theme_font_size_override("bold_font_size", size)
	rt.add_theme_color_override("default_color", color)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.text = _bb(runs, 0, color)
	return rt

func _panel(focusable: bool) -> Array:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Themes.c("select")
	sb.set_corner_radius_all(Themes.r(12))
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8 if focusable else 2
	sb.content_margin_bottom = 8 if focusable else 2
	p.add_theme_stylebox_override("panel", sb)
	return [p, sb]

func _build_blocks() -> void:
	_clear_page()
	var text := Themes.c("text")
	var muted := Themes.c("muted")
	var blocks: Array = _page.get("b", [])
	if blocks.is_empty():
		_col.add_child(_label("Nothing to show on this page. " + TephraGlyphs.btn("west") + " > Back to the live page.", FONT, muted))
	for b in blocks:
		var t := str(b["t"])
		var pr := _panel(false)
		var panel: PanelContainer = pr[0]
		var sb: StyleBoxFlat = pr[1]
		var item := {"block": b, "panel": panel, "style": sb, "links": [], "runs": [], "rtl": null, "kind": t, "color": text}
		match t:
			"h":
				var lvl := int(b.get("l", 2))
				var size: int = [48, 42, 36, 32, 30, 28][clampi(lvl - 1, 0, 5)]
				item["runs"] = b["r"]
				var rt := _rtl(b["r"], size, text)
				rt.add_theme_constant_override("line_separation", 2)
				panel.add_child(rt)
				item["rtl"] = rt
				item["size"] = size
			"p", "row":
				item["runs"] = b["r"]
				var col := muted if b.has("q") else text
				item["color"] = col
				item["size"] = FONT if t == "p" else FONT - 4
				var rt2 := _rtl(b["r"], int(item["size"]), col)
				if b.has("q"):
					var hb := HBoxContainer.new()
					var bar := ColorRect.new()
					bar.color = Themes.c("select")
					bar.custom_minimum_size.x = 5
					hb.add_child(bar)
					var sp := Control.new()
					sp.custom_minimum_size.x = 14
					hb.add_child(sp)
					hb.add_child(rt2)
					panel.add_child(hb)
				else:
					panel.add_child(rt2)
				item["rtl"] = rt2
			"li":
				item["runs"] = b["r"]
				item["size"] = FONT
				var hb2 := HBoxContainer.new()
				hb2.add_theme_constant_override("separation", 10)
				var ind := Control.new()
				ind.custom_minimum_size.x = 30.0 * float(b.get("d", 0))
				hb2.add_child(ind)
				var mark := _label(("%d." % int(b["n"])) if int(b.get("n", 0)) > 0 else "•", FONT, Themes.c("select"))
				mark.vertical_alignment = VERTICAL_ALIGNMENT_TOP
				hb2.add_child(mark)
				var rt3 := _rtl(b["r"], FONT, text)
				hb2.add_child(rt3)
				panel.add_child(hb2)
				item["rtl"] = rt3
			"img":
				var w := float(b.get("w", 400))
				var hh := float(b.get("h", 300))
				var dw := minf(w, 1000.0)
				var dh := minf(dw * hh / maxf(w, 1.0), 640.0)
				dw = minf(dw, dh * w / maxf(hh, 1.0))
				var holder := PanelContainer.new()
				holder.custom_minimum_size = Vector2(maxf(dw, 60.0), maxf(dh, 40.0))
				holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				var hs := StyleBoxFlat.new()
				hs.bg_color = Color(Themes.c("card"), 0.6)
				hs.set_corner_radius_all(Themes.r(10))
				holder.add_theme_stylebox_override("panel", hs)
				var alt := _label(str(b.get("a", "")), 20, muted)
				alt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				alt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				alt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				holder.add_child(alt)
				var tr := TextureRect.new()
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				holder.add_child(tr)
				panel.add_child(holder)
				if int(b.get("id", 0)) > 0:
					item["links"] = [int(b["id"])]
				_queue_image(str(b.get("s", "")), tr, alt)
			"b":
				sb.bg_color = Color(Themes.c("tile"), 1.0)
				sb.set_content_margin_all(14)
				sb.content_margin_left = 30
				sb.content_margin_right = 30
				panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				panel.add_child(_label(str(b["x"]), FONT, text))
				item["links"] = [int(b["id"])]
			"in":
				sb.bg_color = Color(Themes.c("tile"), 1.0)
				sb.set_content_margin_all(14)
				sb.content_margin_left = 22
				sb.content_margin_right = 22
				panel.custom_minimum_size.x = 760
				panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				var hb3 := HBoxContainer.new()
				hb3.add_theme_constant_override("separation", 18)
				var lab := str(b.get("x", ""))
				if lab != "":
					var ll := _label(lab, FONT - 6, muted)
					ll.custom_minimum_size.x = 200
					ll.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					hb3.add_child(ll)
				var val := str(b.get("v", ""))
				var vl := _label(val if val != "" else "Type here", FONT, text if val != "" else muted)
				vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				vl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				hb3.add_child(vl)
				panel.add_child(hb3)
				item["links"] = [int(b["id"])]
			"sel":
				sb.bg_color = Color(Themes.c("tile"), 1.0)
				sb.set_content_margin_all(14)
				sb.content_margin_left = 22
				sb.content_margin_right = 22
				panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				var lab2 := str(b.get("x", ""))
				panel.add_child(_label(("%s   %s  v" % [lab2, str(b.get("v", ""))]).strip_edges(), FONT, text))
				item["links"] = [int(b["id"])]
			"pre":
				sb.bg_color = Color(0, 0, 0, 0.35)
				sb.set_content_margin_all(16)
				var pl := _label(str(b["x"]), 22, text)
				var mono := SystemFont.new()
				mono.font_names = PackedStringArray(["monospace"])
				pl.add_theme_font_override("font", mono)
				pl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
				panel.add_child(pl)
			"hr":
				var line := ColorRect.new()
				line.color = Color(muted, 0.5)
				line.custom_minimum_size.y = 2
				panel.add_child(line)
			"note":
				var nl := _label(str(b["x"]), 22, muted)
				nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				panel.add_child(nl)
			_:
				continue
		# the links in this block, in order
		if item["links"].is_empty():
			var seen := {}
			for r in item["runs"]:
				var id := int(r[1])
				if id > 0 and not seen.has(id):
					seen[id] = true
					(item["links"] as Array).append(id)
		_col.add_child(panel)
		_items.append(item)
		if not (item["links"] as Array).is_empty():
			_stops.append(_items.size() - 1)

# ---------- Pictures ----------
func _queue_image(url: String, rect: TextureRect, alt: Label) -> void:
	if url == "" or _img_count >= MAX_IMAGES:
		return
	if blocked_reason(url) != "":
		alt.text = "(blocked)"
		return
	_img_count += 1
	_img_queue.append({"url": url, "rect": rect, "alt": alt, "gen": _gen})
	_pump_images()

func _pump_images() -> void:
	while _img_active < MAX_PARALLEL and not _img_queue.is_empty():
		var job: Dictionary = _img_queue.pop_front()
		var url: String = job["url"]
		if _img_cache.has(url):
			_set_image(job, _img_cache[url])
			continue
		if url.begins_with("data:"):
			var tex := _decode(_data_bytes(url))
			_img_cache[url] = tex
			_set_image(job, tex)
			continue
		if not (url.begins_with("http://") or url.begins_with("https://")):
			continue
		_img_active += 1
		var req := HTTPRequest.new()
		req.timeout = 15.0
		req.body_size_limit = 8000000
		add_child(req)
		req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			_img_active -= 1
			req.queue_free()
			var tex2: Texture2D = null
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				tex2 = _decode(body)
			_img_cache[url] = tex2
			if is_open:
				_set_image(job, tex2)
				_pump_images())
		var err := req.request(url, PackedStringArray(["User-Agent: " + UA, "Referer: " + str(_page.get("u", "")), "Accept: image/png,image/jpeg,image/webp,image/svg+xml,*/*;q=0.5"]))
		if err != OK:
			_img_active -= 1
			req.queue_free()

func _set_image(job: Dictionary, tex: Texture2D) -> void:
	var rect = job["rect"]
	var alt = job["alt"]
	if not is_instance_valid(rect) or int(job["gen"]) != _gen:
		return
	if tex != null:
		(rect as TextureRect).texture = tex
		(alt as Label).visible = false

static func _data_bytes(url: String) -> PackedByteArray:
	var comma := url.find(",")
	if comma < 0:
		return PackedByteArray()
	var head := url.substr(0, comma)
	var payload := url.substr(comma + 1)
	if "base64" in head:
		return Marshalls.base64_to_raw(payload)
	return payload.uri_decode().to_utf8_buffer()

static func _decode(b: PackedByteArray) -> Texture2D:
	if b.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if b[0] == 0x89 and b[1] == 0x50:
		err = img.load_png_from_buffer(b)
	elif b[0] == 0xFF and b[1] == 0xD8:
		err = img.load_jpg_from_buffer(b)
	elif b[0] == 0x52 and b[1] == 0x49 and b[8] == 0x57:
		err = img.load_webp_from_buffer(b)
	else:
		var head := b.slice(0, 200).get_string_from_utf8().to_lower()
		if "<svg" in head:
			err = img.load_svg_from_buffer(b, 1.5)
	if err != OK or img.is_empty():
		return null
	if img.get_width() > 1500:
		img.resize(1500, int(float(img.get_height()) * 1500.0 / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)

# ---------- Focus ----------
func _apply_focus(animate := true) -> void:
	for i in _items.size():
		var it: Dictionary = _items[i]
		var on: bool = _focus >= 0 and _focus < _stops.size() and _stops[_focus] == i
		var sb: StyleBoxFlat = it["style"]
		var kind: String = it["kind"]
		var boxed := kind in ["b", "in", "sel"]
		if on:
			if boxed:
				sb.set_border_width_all(4)
			else:
				sb.set_border_width_all(0)
				sb.border_width_left = 6
				sb.bg_color = Color(Themes.c("card"), 0.75)
		else:
			sb.set_border_width_all(0)
			if not boxed:
				sb.bg_color = Color(0, 0, 0, 0)
		if it["rtl"] != null:
			var rt: RichTextLabel = it["rtl"]
			rt.text = _bb(it["runs"], int(it["links"][_link]) if on and not (it["links"] as Array).is_empty() and _link < (it["links"] as Array).size() else 0, it["color"])
	_scroll_to_focus(animate)
	_refresh_hints()

func _scroll_to_focus(animate: bool) -> void:
	if _focus < 0 or _focus >= _stops.size():
		return
	await get_tree().process_frame
	if not is_open or _focus < 0 or _focus >= _stops.size():
		return
	var p: Control = _items[_stops[_focus]]["panel"]
	var top := p.position.y + 10.0
	var view := _scroll.size.y
	var cur := float(_scroll.scroll_vertical)
	var target := cur
	if top < cur + 80.0 or top + p.size.y > cur + view - 120.0:
		target = clampf(top + p.size.y * 0.5 - view * 0.4, 0.0, 1000000.0)
	if absf(target - cur) < 1.0:
		return
	if _scroll_tween != null and _scroll_tween.is_running():
		_scroll_tween.kill()
	if animate:
		_scroll_tween = create_tween()
		_scroll_tween.tween_property(_scroll, "scroll_vertical", int(target), Motion.dur(0.2)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_scroll.scroll_vertical = int(target)

func move(dir: Vector2i) -> void:
	if not is_open:
		return
	if _menu_open:
		if dir.y != 0 and not _menu_rows.is_empty():
			_menu_sel = posmod(_menu_sel + dir.y, _menu_rows.size())
			_draw_menu()
		return
	if _busy:
		return
	if dir.y != 0:
		if _stops.is_empty():
			_scroll.scroll_vertical += dir.y * 260
			return
		var to := clampi(_focus + dir.y, 0, _stops.size() - 1)
		if to != _focus:
			_focus = to
			_link = 0
			Haptics.select()
			_apply_focus(true)
		elif dir.y > 0:
			_scroll.scroll_vertical += 260
	elif dir.x != 0 and _focus >= 0:
		var it: Dictionary = _items[_stops[_focus]]
		var links: Array = it["links"]
		if str(it["kind"]) == "sel":
			_select_option(int(links[0]), dir.x)
		elif links.size() > 1:
			_link = clampi(_link + dir.x, 0, links.size() - 1)
			_apply_focus(false)

func _process(dt: float) -> void:
	if not is_open or _menu_open or _keyboard_up():
		return
	var dev := TephraGlyphs.primary_device()
	var y := Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)
	if absf(y) > 0.2:
		_scroll.scroll_vertical += int(signf(y) * (absf(y) - 0.2) * 1500.0 * dt)

func _keyboard_up() -> bool:
	return _home != null and _home.keyboard.is_open

# ---------- Doing things on the page ----------
func _link_id() -> int:
	if _focus < 0 or _focus >= _stops.size():
		return 0
	var links: Array = _items[_stops[_focus]]["links"]
	return int(links[clampi(_link, 0, links.size() - 1)])

func _accept() -> void:
	if _busy or _focus < 0 or _focus >= _stops.size():
		return
	var it: Dictionary = _items[_stops[_focus]]
	var id := _link_id()
	var kind := str(it["kind"])
	Haptics.tick()
	match kind:
		"in":
			var b: Dictionary = it["block"]
			var secret := str(b.get("k", "")) == "password"
			_home.keyboard.open(str(b.get("x", "")) if str(b.get("x", "")) != "" else "Type", "" if secret else str(b.get("v", "")), secret, func(text: String) -> void:
				_set_input(id, text), {"max_len": 400})
		"sel":
			_select_option(id, 1)
		_:
			_press(id)

func _press(id: int) -> void:
	var gen := _gen
	_busy = true
	_set_status("")
	# First the address of a link is looked at, so a blocked site is never opened.
	_mar.script("var e=document.querySelector('[data-tp=\"' + arguments[0] + '\"]'); if(!e) return 'gone'; return (e.tagName==='A' ? e.href : '') || '';", [id], func(ok: bool, href) -> void:
		if not is_open or gen != _gen:
			return
		if ok and str(href) == "gone":
			_busy = false
			_set_status("That has changed. Reading the page again...")
			_extract(0, false, true)
			return
		var why := blocked_reason(str(href)) if ok else ""
		if why != "":
			_busy = false
			_set_status(why + " (" + TephraGlyphs.btn("west") + " > Unblock)")
			return
		var before := str(_page.get("u", ""))
		_mar.script("var e=document.querySelector('[data-tp=\"' + arguments[0] + '\"]'); if(!e) return 'gone'; if(e.tagName==='A'){e.removeAttribute('target');} try{e.scrollIntoView({block:'center'});}catch(x){} e.click(); return 'ok';", [id], func(ok2: bool, _r) -> void:
			if not is_open or gen != _gen:
				return
			if not ok2:
				_busy = false
				_set_status("That didn't work. " + TephraGlyphs.btn("west") + " > Back to the live page.")
				return
			await get_tree().create_timer(0.8).timeout
			_after_action(before)))

func _after_action(before: String) -> void:
	if not is_open:
		return
	_mar.script("return location.href;", [], func(ok: bool, now) -> void:
		if not is_open:
			return
		var moved := ok and str(now) != before and not (str(now).split("#")[0] == before.split("#")[0])
		if moved:
			var h := _handle()
			_depth[h] = int(_depth.get(h, 0)) + 1
		_extract(0, false, not moved))

func _set_input(id: int, text: String) -> void:
	if not is_open:
		return
	var gen := _gen
	_busy = true
	var before := str(_page.get("u", ""))
	var js := """var e=document.querySelector('[data-tp="' + arguments[0] + '"]'); if(!e) return 'gone';
e.focus(); e.value=arguments[1];
var a=document.createEvent('Event'); a.initEvent('input',true,true); e.dispatchEvent(a);
var c=document.createEvent('Event'); c.initEvent('change',true,true); e.dispatchEvent(c);
var f=e.form; var t=(e.type||'').toLowerCase();
if(f){ var n=0; for(var i=0;i<f.elements.length;i++){var x=f.elements[i]; if(x.tagName==='INPUT' && /^(text|search|email|url|tel|number|password|)$/i.test(x.type||'text')) n++;}
  if(t==='search' || (n===1 && t!=='password')){ if(f.requestSubmit){f.requestSubmit();}else{f.submit();} return 'submitted'; } }
return 'ok';"""
	_mar.script(js, [id, text], func(ok: bool, r) -> void:
		if not is_open or gen != _gen:
			return
		await get_tree().create_timer(0.8 if ok and str(r) == "submitted" else 0.2).timeout
		_after_action(before))

func _select_option(id: int, step: int) -> void:
	if _busy:
		return
	var gen := _gen
	_busy = true
	var js := """var e=document.querySelector('[data-tp="' + arguments[0] + '"]'); if(!e||!e.options) return 'gone';
var n=e.options.length; if(!n) return 'ok'; e.selectedIndex=(e.selectedIndex+arguments[1]+n)%n;
var a=document.createEvent('Event'); a.initEvent('input',true,true); e.dispatchEvent(a);
var c=document.createEvent('Event'); c.initEvent('change',true,true); e.dispatchEvent(c); return 'ok';"""
	var before := str(_page.get("u", ""))
	_mar.script(js, [id, step], func(_ok: bool, _r) -> void:
		if not is_open or gen != _gen:
			return
		await get_tree().create_timer(0.5).timeout
		_after_action(before))

func go(url: String) -> void:
	if not is_open:
		return
	var why := blocked_reason(url)
	if why != "":
		_set_status(why + " (" + TephraGlyphs.btn("west") + " > Unblock)")
		return
	_gen += 1
	_busy = true
	_set_status("Loading...")
	var h := _handle()
	_depth[h] = int(_depth.get(h, 0)) + 1
	_mar.command("WebDriver:Navigate", {"url": url}, func(_ok: bool, _v) -> void:
		_extract(0, true))

func _go_back() -> void:
	var h := _handle()
	if int(_depth.get(h, 0)) <= 0:
		close(false)
		return
	_depth[h] = int(_depth[h]) - 1
	_gen += 1
	_busy = true
	_set_status("Loading...")
	_mar.command("WebDriver:Back", {}, func(_ok: bool, _v) -> void:
		await get_tree().create_timer(0.3).timeout
		_extract(0, true))

# ---------- Tabs ----------
func _draw_tabs() -> void:
	for c in _tab_row.get_children():
		c.queue_free()
	var count := _handles.size()
	if count == 0:
		return
	var first := clampi(_tab - 2, 0, maxi(count - 5, 0))
	for i in range(first, mini(count, first + 5)):
		var h := str(_handles[i])
		var info: Dictionary = _titles.get(h, {})
		var title := str(info.get("title", ""))
		if title == "":
			title = host_of(str(info.get("url", ""))) if info.has("url") else "Tab %d" % (i + 1)
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(Themes.c("card"), 1.0 if i == _tab else 0.55)
		sb.set_corner_radius_all(Themes.r(12))
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		if i == _tab:
			sb.border_color = Themes.c("select")
			sb.set_border_width_all(3)
		p.add_theme_stylebox_override("panel", sb)
		var l := _label(title, 22, Themes.c("text") if i == _tab else Themes.c("muted"))
		l.custom_minimum_size.x = 200
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		p.add_child(l)
		_tab_row.add_child(p)

func _switch_tab(step: int) -> void:
	if _busy or _handles.size() < 2:
		return
	_tab = posmod(_tab + step, _handles.size())
	_to_tab()

func _to_tab() -> void:
	_gen += 1
	_busy = true
	_set_status("Loading...")
	_mar.command("WebDriver:SwitchToWindow", {"handle": _handle(), "focus": true}, func(_ok: bool, _v) -> void:
		_extract(0, true))

func _new_tab(url: String) -> void:
	_gen += 1
	_busy = true
	_mar.command("WebDriver:NewWindow", {"type": "tab"}, func(ok: bool, v) -> void:
		if not ok:
			_busy = false
			_set_status("Couldn't open a new tab.")
			return
		var h := str((v as Dictionary).get("handle", "")) if v is Dictionary else ""
		if h == "":
			_busy = false
			return
		_handles.append(h)
		_tab = _handles.size() - 1
		_depth[h] = 0
		_mar.command("WebDriver:SwitchToWindow", {"handle": h, "focus": true}, func(_ok2: bool, _v2) -> void:
			if url == "":
				go("https://www.google.com")
			else:
				go(url)))

func _close_tab() -> void:
	if _handles.size() <= 1:
		# The last tab is never closed (that would end the browser): it goes back to the start page instead.
		go(preload("res://browser.gd")._write_start_page())
		return
	_gen += 1
	_busy = true
	var gone := _handle()
	_mar.command("WebDriver:CloseWindow", {}, func(ok: bool, v) -> void:
		var rest := _as_list(v) if ok else []
		if rest.is_empty():
			close(true)  # the last tab closed: the browser goes with it
			return
		_handles = rest
		_titles.erase(gone)
		_tab = clampi(_tab, 0, _handles.size() - 1)
		_to_tab())

# ---------- The menu (Square) ----------
func _open_menu() -> void:
	var url := str(_page.get("u", ""))
	var host := host_of(url)
	_menu_rows = [
		{"k": "new", "t": "New tab"},
		{"k": "address", "t": "Go to an address or search"},
		{"k": "reload", "t": "Reload the page"},
		{"k": "reread", "t": "Read the page again"},
		{"k": "closetab", "t": "Close this tab"},
	]
	if host != "" and not host.begins_with("about"):
		if _host_in(host, _rules["block"]):
			_menu_rows.append({"k": "unblock", "t": "Unblock %s" % host, "d": host})
		else:
			_menu_rows.append({"k": "block", "t": "Block %s" % host, "d": host})
		if _host_in(host, _rules["allow"]):
			_menu_rows.append({"k": "unallow", "t": "Remove %s from allowed sites" % host, "d": host})
		else:
			_menu_rows.append({"k": "allow", "t": "Allow %s" % host, "d": host})
	_menu_rows.append({"k": "allowonly", "t": "Only allowed sites: %s" % ("On" if bool(_rules["allow_only"]) else "Off")})
	var n := 0
	for d in _rules["block"]:
		if n >= 6:
			break
		_menu_rows.append({"k": "unblock", "t": "Unblock %s" % str(d), "d": str(d)})
		n += 1
	_menu_rows.append({"k": "live", "t": "Back to the live page"})
	_menu_rows.append({"k": "exit", "t": "Close Page view"})
	_menu_sel = 0
	_menu_open = true
	_menu_box.visible = true
	_draw_menu()

func _draw_menu() -> void:
	for c in _menu_list.get_children():
		c.queue_free()
	for i in _menu_rows.size():
		var l := _label(str(_menu_rows[i]["t"]), 28, Themes.c("text") if i == _menu_sel else Themes.c("muted"))
		l.custom_minimum_size.x = 620
		if i == _menu_sel:
			var p := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(Themes.c("select"), 0.28)
			sb.set_corner_radius_all(Themes.r(10))
			sb.content_margin_left = 12
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			p.add_theme_stylebox_override("panel", sb)
			p.add_child(l)
			_menu_list.add_child(p)
		else:
			var q := MarginContainer.new()
			q.add_theme_constant_override("margin_left", 12)
			q.add_theme_constant_override("margin_top", 4)
			q.add_theme_constant_override("margin_bottom", 4)
			q.add_child(l)
			_menu_list.add_child(q)
	_refresh_hints()

func _menu_accept() -> void:
	var r: Dictionary = _menu_rows[_menu_sel]
	_menu_open = false
	_menu_box.visible = false
	_refresh_hints()
	var d := str(r.get("d", ""))
	match str(r["k"]):
		"new":
			_home.keyboard.open("New tab: address or search", "", false, func(text: String) -> void:
				var t := text.strip_edges()
				_new_tab(preload("res://browser.gd").url_for(t) if t != "" else ""), {"max_len": 400})
		"address":
			_ask_address()
		"reload":
			_gen += 1
			_busy = true
			_mar.command("WebDriver:Refresh", {}, func(_ok: bool, _v) -> void: _extract(0, true))
		"reread":
			_extract(0, false, true)
		"closetab":
			_close_tab()
		"block":
			if not (_rules["block"] as Array).has(d):
				(_rules["block"] as Array).append(d)
			_save_rules()
			go("about:blank")
			_set_status("%s is blocked now." % d)
		"unblock":
			_rules["block"] = (_rules["block"] as Array).filter(func(x): return str(x) != d)
			_save_rules()
			_set_status("%s is unblocked." % d)
		"allow":
			if not (_rules["allow"] as Array).has(d):
				(_rules["allow"] as Array).append(d)
			_save_rules()
			_set_status("%s is on your allowed list." % d)
		"unallow":
			_rules["allow"] = (_rules["allow"] as Array).filter(func(x): return str(x) != d)
			_save_rules()
			_set_status("%s is off your allowed list." % d)
		"allowonly":
			_rules["allow_only"] = not bool(_rules["allow_only"])
			_save_rules()
			_set_status("Only allowed sites: %s" % ("on" if bool(_rules["allow_only"]) else "off"))
		"live":
			close(true)
		"exit":
			close(false)

func _ask_address() -> void:
	_home.keyboard.open("Address or search", str(_page.get("u", "")), false, func(text: String) -> void:
		var t := text.strip_edges()
		if t != "":
			go(preload("res://browser.gd").url_for(t)), {"max_len": 600})

# ---------- Hints and input ----------
func _refresh_hints() -> void:
	var items: Array = []
	if _menu_open:
		items = [["dpad_v", "Choose"], ["accept", "Select"], ["back", "Close menu"]]
	else:
		items = [["dpad", "Move"]]
		var kind := ""
		if _focus >= 0 and _focus < _stops.size():
			kind = str(_items[_stops[_focus]]["kind"])
		items.append(["accept", "Type" if kind == "in" else ("Change" if kind == "sel" else ("Press" if kind != "" else "Scroll"))])
		items.append(["north", "Address"])
		items.append(["west", "Menu"])
		items.append(["back", "Back" if int(_depth.get(_handle(), 0)) > 0 else "Close"])
	TephraGlyphs.fill(_hints, items, 26)

func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event is InputEventJoypadMotion:
		return true
	if _keyboard_up():
		return false
	var west: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.west_button()) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M)
	var north: bool = (event is InputEventJoypadButton and event.pressed and event.button_index == TephraGlyphs.north_button()) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L)
	if _menu_open:
		if event.is_action_pressed("ui_cancel") or west:
			_menu_open = false
			_menu_box.visible = false
			_refresh_hints()
		elif event.is_action_pressed("ui_accept") and _menu_sel < _menu_rows.size():
			_menu_accept()
		return true
	if west:
		_open_menu()
	elif north:
		_ask_address()
	elif event.is_action_pressed("ui_cancel"):
		_go_back()
	elif event.is_action_pressed("ui_accept"):
		_accept()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_LEFT_SHOULDER:
		_switch_tab(-1)
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		_switch_tab(1)
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		close(true)
	return true
