extends RefCounted
const Icons = preload("res://icons.gd")
const Themes = preload("res://themes.gd")
const Settings = preload("res://settings.gd")
## Controller-aware button glyphs for hint bars.
## Shows PlayStation shapes, Xbox letters, Nintendo letters, or keyboard keys,
## depending on what was used last. All drawn by Tephra (no brand logos).

static var TEXT: Color = Themes.c("text")
static var MUTED: Color = Themes.c("muted")

## Test overrides (Developer menu): force one glyph family, or hide the hint bars.
static func override_family() -> String:
	var o := str(Settings.get_value("glyph_override", ""))
	return "ps" if (o == "ds5" or o == "ds4") else o  # both PlayStation pads use the same button shapes

static func hints_visible() -> bool:
	return bool(Settings.get_value("show_hints", true))

static var family := "keyboard"  # "ps", "xbox", "nintendo" or "keyboard"
static var _cache := {}
static var slots := {}       # device id -> player number (filled in by controllers.gd)
static var last_device := -1  # the controller that was used last (for vibration and priority)

## Which controller is "in charge" when several are connected. Players are numbered in the order the
## controllers connect (first one is P1). The one in charge is picked from the list of connected
## controllers (top bar controller menu, or Settings > Controllers) and saved as its player number.
## Older choices ("last" used, "first" connected) count as P1.
static func primary_device() -> int:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return -1
	var mode := str(Settings.get_value("pad_priority", "1"))
	# A player number (1 to 4): that controller if it is connected, else the first one that is.
	if mode.is_valid_int():
		for p in pads:
			if int(slots.get(p, 0)) == mode.to_int():
				return p
	# "First connected" (and the fallback for everything else): the lowest player number.
	var best := -1
	var best_slot := 9999
	for p in pads:
		if family_for_device(p) == "":
			continue  # Steam's virtual pad comes last
		var sl := int(slots.get(p, 9998))
		if sl < best_slot:
			best_slot = sl
			best = p
	if best >= 0:
		return best
	return pads[0]

## The player number of the controller in charge (1 if none was picked).
static func in_charge_slot() -> int:
	var mode := str(Settings.get_value("pad_priority", "1"))
	return mode.to_int() if mode.is_valid_int() else 1

## A short, friendly name for a controller: "DualSense", "Xbox controller", ...
static func pretty_name(device: int) -> String:
	match model_for_device(device):
		"ds5": return "DualSense"
		"ds4": return "DualShock 4"
		"xbox": return "Xbox controller"
		"nintendo": return "Switch Pro controller"
	var n := Input.get_joy_name(device).strip_edges()
	return n if n != "" else "Controller"

## Reads a USB id that Godot reports either as "0x054c" or as plain decimal.
static func _id(v) -> int:
	var t := str(v).strip_edges().to_lower()
	return t.hex_to_int() if t.begins_with("0x") else t.to_int()

## Which exact controller a pad is: "ds5" (DualSense), "ds4" (DualShock 4), or its family.
## Linux often names both Sony pads just "Wireless Controller", so the USB ids decide.
static func model_for_device(device: int) -> String:
	var info := Input.get_joy_info(device)
	if _id(info.get("vendor_id", 0)) == 0x054c:
		var pid := _id(info.get("product_id", 0))
		if pid == 0x0ce6 or pid == 0x0df2:
			return "ds5"
		if pid == 0x05c4 or pid == 0x09cc or pid == 0x081f or pid == 0x0ba0:
			return "ds4"
	var n := Input.get_joy_name(device).to_lower()
	if n.contains("dualsense") or n.contains("ps5"):
		return "ds5"
	if n.contains("dualshock") or n.contains("ps4"):
		return "ds4"
	if n.contains("wireless controller"):
		# Unknown Sony-style pad: a DualSense has an RGB lightbar LED, a DualShock 4 does not.
		return "ds5" if _has_rgb_lightbar() else "ds4"
	var f := family_for_device(device)
	return f if f != "" else "generic"

static func _has_rgb_lightbar() -> bool:
	if not DirAccess.dir_exists_absolute("/sys/class/leds"):
		return false
	for d in DirAccess.get_directories_at("/sys/class/leds"):
		if d.ends_with(":rgb:indicator"):
			return true
	return false

## The icon shape for the controller in use ("ds5", "ds4", "xbox", "nintendo" or "generic").
## Settings > Controller > Button glyphs can force one.
static func pad_model() -> String:
	var o := str(Settings.get_value("glyph_override", ""))
	if o == "ds5" or o == "ds4" or o == "xbox" or o == "nintendo":
		return o
	var d := primary_device()
	if o == "ps":
		return model_for_device(d) if d >= 0 and family_for_device(d) == "ps" else "ds5"
	return model_for_device(d) if d >= 0 else "generic"

## Which family a joypad belongs to, from its name. "" for Steam's virtual pad.
static func family_for_device(device: int) -> String:
	var n := Input.get_joy_name(device).to_lower()
	if n.contains("steam virtual"):
		return ""
	if _id(Input.get_joy_info(device).get("vendor_id", 0)) == 0x054c:
		return "ps"
	if n.contains("wireless controller") or n.contains("dualsense") or n.contains("ps5") or n.contains("ps4") or n.contains("dualshock") or n.contains("playstation") or n.contains("sony"):
		return "ps"
	if n.contains("nintendo") or n.contains("switch") or n.contains("joy-con") or n.contains("pro controller"):
		return "nintendo"
	return "xbox"

## Picks a family from whatever controller is plugged in (used at startup).
static func detect() -> void:
	if override_family() != "":
		family = override_family()
		apply_layout()
		return
	var pd := primary_device()
	if pd >= 0 and family_for_device(pd) != "":
		family = family_for_device(pd)
		apply_layout()
		return
	for pad in Input.get_connected_joypads():
		var f := family_for_device(pad)
		if f != "":
			family = f
			apply_layout()
			return
	family = "keyboard"
	apply_layout()

## Call with every input event. Returns true if the family changed.
static func update_from_event(event: InputEvent) -> bool:
	if override_family() != "":
		var changed := family != override_family()
		family = override_family()
		apply_layout()
		return changed
	var f := family
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		last_device = event.device
		var g := family_for_device(event.device)
		# Whichever controller sends input sets the glyphs, even when another one is in charge (that one only decides
		# who can press Select, see pad_gate.gd): with a DualSense and a Pro controller both in use they flip with each press.
		if g != "":
			f = g
	elif event is InputEventKey and event.pressed:
		f = "keyboard"
	if f == family:
		return false
	family = f
	apply_layout()
	return true

## Applies Settings > Controller > Stick dead zone to the menu directions.
static func apply_deadzone() -> void:
	var dz := clampf(float(Settings.get_value("deadzone", 0.15)), 0.0, 0.5)
	for a in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		if InputMap.has_action(a):
			InputMap.action_set_deadzone(a, maxf(dz, 0.05))

# ---------- Nintendo layout ----------
# Nintendo pads have A on the right and B at the bottom (Xbox is the other way round),
# and X on top with Y on the left (Xbox: Y on top, X on the left). Tephra always uses the
# same letters for the same jobs on every pad: A = Select, B = Back, X = the left-hand
# action, Y = the top action. On a Nintendo pad that means the physical buttons swap
# places, so the glyph you see is the button you press. Godot names pad buttons by
# position (JOY_BUTTON_A is always the bottom one), so we re-point the UI actions here
# and give screens west_button() / north_button() for the X and Y actions.
static var _layout := ""

static func apply_layout() -> void:
	var want := "nintendo" if family == "nintendo" else "standard"
	if want == _layout:
		return
	_layout = want
	_set_pad_button("ui_accept", JOY_BUTTON_B if want == "nintendo" else JOY_BUTTON_A)
	_set_pad_button("ui_cancel", JOY_BUTTON_A if want == "nintendo" else JOY_BUTTON_B)

static func _set_pad_button(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e.button_index == JOY_BUTTON_A or e.button_index == JOY_BUTTON_B):
			InputMap.action_erase_event(action, e)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button as JoyButton
	InputMap.action_add_event(action, ev)

## The pad button for the "X" action (Library: Installed only / All games).
static func west_button() -> int:
	return JOY_BUTTON_Y if family == "nintendo" else JOY_BUTTON_X

## The pad button for the "Y" action (Library: Hide from Home).
static func north_button() -> int:
	return JOY_BUTTON_X if family == "nintendo" else JOY_BUTTON_Y

## What the button for an action is called on the pad in use, for sentences ("Press Cross to play"):
## accept, back, west, north, l1, r1, l2, r2.
static func btn(action: String) -> String:
	var table := {
		"ps": {"accept": "Cross", "back": "Circle", "west": "Square", "north": "Triangle", "l1": "L1", "r1": "R1", "l2": "L2", "r2": "R2"},
		"xbox": {"accept": "A", "back": "B", "west": "X", "north": "Y", "l1": "LB", "r1": "RB", "l2": "LT", "r2": "RT"},
		"nintendo": {"accept": "A", "back": "B", "west": "X", "north": "Y", "l1": "L", "r1": "R", "l2": "ZL", "r2": "ZR"},
		"keyboard": {"accept": "Enter", "back": "Esc", "west": "X", "north": "Y", "l1": "Q", "r1": "E", "l2": "Z", "r2": "C"},
	}
	return str((table.get(family, table["keyboard"]) as Dictionary).get(action, action))

## Fills a hint bar. items = [["accept", "Play"], ["dpad_h", "Browse"], ...]
## Actions: accept, back, dpad_h, dpad_v, dpad, guide, hold_guide, west, north
static func fill(bar: HBoxContainer, items: Array, font_size := 24) -> void:
	for c in bar.get_children():
		bar.remove_child(c)
		c.queue_free()
	bar.add_theme_constant_override("separation", 14)
	var first := true
	for item in items:
		if not first:
			var gap := Control.new()
			gap.custom_minimum_size.x = 26
			bar.add_child(gap)
		first = false
		var action: String = item[0]
		if action == "hold_guide":
			bar.add_child(_text("Hold", font_size, MUTED))
			action = "guide"
		bar.add_child(glyph(action, font_size + 12))
		bar.add_child(_text(item[1], font_size, MUTED))
	# Hints switched off: the bar is still built but see-through, so it keeps its height and nothing
	# above it (game covers, icons) moves when the setting changes.
	if not hints_visible():
		for c in bar.get_children():
			c.modulate.a = 0.0

## One button glyph as a Control.
static func glyph(action: String, px := 36) -> Control:
	if action.begins_with("chip:"):
		return _keycap(action.substr(5), px)  # a button that has no picture of its own (R3, ...)
	if family == "keyboard":
		var key := {"accept": "Enter", "back": "Esc", "guide": "F1", "west": "X", "north": "Y"}
		if key.has(action):
			return _keycap(key[action], px)
	match action:
		"dpad_h":
			return _svg_rect("dpad_h", _svg_dpad(false, true), px)
		"dpad_v":
			return _svg_rect("dpad_v", _svg_dpad(true, false), px)
		"dpad":
			return _svg_rect("dpad", _svg_dpad(true, true), px)
		"guide":
			return _guide(px)
		"l1", "r1":
			return _shoulder(action == "l1", px)
		"l2", "r2":
			return _shoulder(action == "l2", px, true)
	if family == "ps":
		match action:
			"accept":
				return _svg_rect("ps_cross", _RING + '<path d="M17 17 L31 31 M31 17 L17 31" stroke="#fff" stroke-width="4" stroke-linecap="round"/>', px)
			"back":
				return _svg_rect("ps_circle", _RING + '<circle cx="24" cy="24" r="8.5" fill="none" stroke="#fff" stroke-width="4"/>', px)
			"west":
				return _svg_rect("ps_square", _RING + '<rect x="16" y="16" width="16" height="16" rx="1.5" fill="none" stroke="#fff" stroke-width="4"/>', px)
			"north":
				return _svg_rect("ps_triangle", _RING + '<path d="M24 14.5 L33 30.5 H15 Z" fill="none" stroke="#fff" stroke-width="4" stroke-linejoin="round"/>', px)
	# Xbox and Nintendo both use letters, the same letters for the same jobs (see the
	# Nintendo layout note above: on a Nintendo pad the physical buttons are swapped to match).
	var letters := {"accept": "A", "back": "B", "west": "X", "north": "Y"}
	return _letter(letters.get(action, "?"), px)

# ---------- Pieces ----------
const _RING := '<circle cx="24" cy="24" r="21" fill="none" stroke="#fff" stroke-width="3"/>'

static func _text(t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

static func _svg_rect(key: String, body: String, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = svg_texture(key, body, px)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	return r

static func _letter(ch: String, px: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(px, px)
	var ring := _svg_rect("ring", _RING, px)
	box.add_child(ring)
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var l := _text(ch, int(px * 0.52), TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return box

## Shoulder button (L1/R1, LB/RB, L/R) as a rounded label; Q / E on a keyboard.
static func _shoulder(left: bool, px: int, trigger := false) -> Control:
	var label: String = "Q" if left else "E"
	if family != "keyboard":
		var names := {"ps": ["L1", "R1"], "xbox": ["LB", "RB"], "nintendo": ["L", "R"]}
		if trigger:
			names = {"ps": ["L2", "R2"], "xbox": ["LT", "RT"], "nintendo": ["ZL", "ZR"]}
		var pair: Array = names.get(family, ["L1", "R1"])
		label = pair[0 if left else 1]
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = TEXT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(px * 0.3))
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(px if family == "keyboard" else px * 1.3, px)
	var l := _text(label, int(px * 0.45), TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

static func _keycap(t: String, px: int) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = TEXT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(px, px)
	var l := _text(t, int(px * 0.45), TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

static func _svg_dpad(vertical: bool, horizontal: bool) -> String:
	var on := 'fill="#fff"'
	var off := 'fill="#fff" fill-opacity="0.45"'
	return '<rect x="18" y="3" width="12" height="15" rx="2.5" %s/>' % (on if vertical else off) \
		+ '<rect x="18" y="30" width="12" height="15" rx="2.5" %s/>' % (on if vertical else off) \
		+ '<rect x="3" y="18" width="15" height="12" rx="2.5" %s/>' % (on if horizontal else off) \
		+ '<rect x="30" y="18" width="15" height="12" rx="2.5" %s/>' % (on if horizontal else off) \
		+ '<rect x="18" y="18" width="12" height="12" fill="#fff" fill-opacity="0.3"/>'

# The system button: a house (Home) inside a circle.
static func _guide(px: int) -> Control:
	# The Home button: just a house, no ring.
	var house := TextureRect.new()
	house.texture = Icons.texture("home", Icons.svg_home(), roundi(px * 0.9))
	house.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	house.custom_minimum_size = Vector2(px, px)
	return house

## Renders a 48x48 SVG body to a texture of the given pixel size (cached).
static func svg_texture(key: String, body: String, px: int) -> Texture2D:
	return Icons.texture(key, body, px)
