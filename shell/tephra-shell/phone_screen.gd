extends CanvasLayer
## The QR code for the phone link (phone_link.gd): scan it with a phone on the same Wi-Fi and its browser opens Tephra's
## small page. Two uses: "type" (opened by the on-screen keyboard's Phone key; it closes by itself once the phone has
## connected, and the phone then types into the keyboard) and "captures" (opened from the Album; a screenshot or
## recording, or all of them, can be saved on the phone; the link stops when this closes).

const TephraGlyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
const QR = preload("res://qr.gd")
const PhoneLink = preload("res://phone_link.gd")

const QR_PX := 520.0   # the code is drawn about this big

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")
var GOOD := Color("7BD88F")

var is_open := false
var _home
var _mode := ""
var _root: Control
var _title: Label
var _sub: Label
var _qr: TextureRect
var _qr_back: PanelContainer
var _url: Label
var _status: Label
var _hints: HBoxContainer
var _connected_t := -1.0   # seconds since the phone connected (type mode closes a moment after)
var _waited := 0.0         # seconds since it was opened

func setup(home) -> void:
	_home = home

func _ready() -> void:
	layer = 99  # above the on-screen keyboard (98) and below the boot logo (100)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	_root.modulate.a = 0.0
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Themes.c("bg").lerp(Color.WHITE, 0.08)
	sb.set_corner_radius_all(Themes.r(32))
	sb.set_content_margin_all(40)
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	_title = _label("", 46, TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_sub = _label("", 24, MUTED)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size.x = 760
	v.add_child(_sub)
	_qr_back = PanelContainer.new()
	var wb := StyleBoxFlat.new()
	wb.bg_color = Color.WHITE
	wb.set_corner_radius_all(Themes.r(20))
	_qr_back.add_theme_stylebox_override("panel", wb)
	_qr_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_qr_back)
	_qr = TextureRect.new()
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_qr.stretch_mode = TextureRect.STRETCH_KEEP
	_qr_back.add_child(_qr)
	_url = _label("", 22, MUTED)
	_url.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_url)
	_status = _label("", 28, TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_hints)
	refresh_hints()

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func refresh_hints() -> void:
	if _hints != null:
		TephraGlyphs.fill(_hints, [["back", "Close"]], 26)

## True while the Album's link is being shared (the typing link must not stop it).
func sharing_captures() -> bool:
	return is_open and _mode == "captures"

# ---------- Open / close ----------
## mode "type" or "captures"; file = one capture's name to open the phone's page at (captures).
func open(mode: String, file := "") -> void:
	if is_open:
		return
	if not _home.phone.start(mode == "type"):
		_home.notify("The phone link couldn't start (no free network port).")
		return
	_mode = mode
	_connected_t = -1.0
	_waited = 0.0
	var url: String = _home.phone.file_url(file) if file != "" else _home.phone.base_url()
	if _home.phone.seen_phone:
		_connected_t = 0.0
	if url == "":
		_title.text = "Connect to Wi-Fi first"
		_sub.text = "The phone link works over your home network. Connect this PC to Wi-Fi or a cable, then try again."
		_qr.texture = null
		_qr_back.visible = false
		_url.text = ""
		_status.text = ""
		_home.phone.stop()
	else:
		_qr_back.visible = true
		_title.text = "Type with your phone" if mode == "type" else "Send to your phone"
		_sub.text = ("Scan this with your phone's camera (same Wi-Fi as this PC). Whatever you type on the phone appears in the box here."
			if mode == "type" else "Scan this with your phone's camera (same Wi-Fi as this PC). Your screenshots and recordings show up there to save." + (" The one you picked is highlighted." if file != "" else ""))
		var n := QR.matrix(url).size()
		var px := maxi(4, int(QR_PX / float(n + 8)))
		var tex := QR.texture(url, px, 4)
		_qr.texture = tex
		_qr.custom_minimum_size = tex.get_size() if tex != null else Vector2.ZERO
		_url.text = url.get_slice("?", 0)
		_status.text = "Waiting for your phone..."
		_status.add_theme_color_override("font_color", MUTED)
	is_open = true
	_root.visible = true
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.2)

func close() -> void:
	if not is_open:
		return
	is_open = false
	if _mode == "captures":
		_home.phone.stop()  # the link only lives while this is shown
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.2)
	await t.finished
	if not is_open:
		_root.visible = false

func move(_dir: Vector2i) -> void:
	pass

## Modal: while it is open it takes every event (Back or A closes it).
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
	return true

func _process(delta: float) -> void:
	if not is_open:
		return
	_waited += delta
	if _connected_t < 0.0 and _home.phone.seen_phone:
		_connected_t = 0.0
	if _connected_t < 0.0 and _waited > 25.0:
		_status.text = "Nothing yet? The phone must be on the same Wi-Fi as this PC."
	if _connected_t >= 0.0:
		_connected_t += delta
		_status.text = "Phone connected" + ("" if _mode == "type" else ". Close this when you are done.")
		_status.add_theme_color_override("font_color", GOOD)
		if _mode == "type" and _connected_t > 1.2:
			close()  # back to the keyboard, which the phone now types into
