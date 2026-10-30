extends Control
## Prism (the developer theme): Home as a live 3D scene. The games stand as glass slabs on a glossy grid
## floor, with their covers set inside the glass; the one in focus steps forward, turns gently and glows.
## Under them is a dock of 3D glass icons (Profile, Library, Album, Wi-Fi, Controllers, Settings, Themes,
## System information). Light motes drift up through the room and two coloured lights circle it.
##   Left / Right   move along the row (it loops)
##   Down / Up      games row and icon dock; Up from the games goes to the top bar
##   Cross          play the game / open the icon; Triangle: the game's page
## Uses the same hooks as the other alternative Homes (see channels.gd): rebuild, move, handle_input,
## selected_gi, top_column, dim, info_selected.

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const Haptics = preload("res://haptics.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Kit = preload("res://prism_kit.gd")

const CARD := Vector2(1.0, 1.5)     # cover size in metres (2:3 like Steam's library art)
const STEP := 1.3                   # distance between neighbouring slabs
const DOCK_STEP := 1.05
const CARD_Y := 0.55
const DOCK_Y := -1.05
const SHOW := 7                     # slabs drawn either side of the focus

var home  # home.gd
var _ct: SubViewportContainer
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _lights: Array = []
var _far: Array = []      # the big dim shards far back
var _floor: MeshInstance3D
var _cards: Array = []   # {node, cover, cover_mat, halo_mat, item}
var _dock: Array = []    # {node, core, item}
var _items: Array = []
var _dock_items: Array = []
var _row := 0            # 0 = games, 1 = icon dock
var _gi := 0
var _di := 0
var _gf := 0.0           # eased positions
var _df := 0.0
var _rowf := 0.0
var _t := 0.0
var _dim := 1.0
var _dim_to := 1.0
var _veil: ColorRect
var _title: Label
var _sub: Label
var _hints: HBoxContainer
var _art := {}
var _holders: Array = []
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = Themes.font("prism")
	_ct = SubViewportContainer.new()
	_ct.stretch = true
	_ct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ct)
	_ct.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_ct.add_child(_vp)
	_build_world()
	_veil = ColorRect.new()
	_veil.color = Color(0, 0, 0, 0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title = _label(58)
	_title.position = Vector2(110, 0)
	add_child(_title)
	_sub = _label(28)
	_sub.modulate = Color(0.7, 0.85, 1.0, 0.85)
	add_child(_sub)
	_hints = HBoxContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.alignment = BoxContainer.ALIGNMENT_END
	add_child(_hints)
	_hints.anchor_left = 0.0
	_hints.anchor_right = 1.0
	_hints.anchor_top = 1.0
	_hints.anchor_bottom = 1.0
	_hints.offset_left = 80
	_hints.offset_right = -90
	_hints.offset_top = -110
	_hints.offset_bottom = -50
	TephraGlyphs.fill(_hints, [["accept", "Options"], ["dpad", "Navigate"]] if home.cross_opens_info() else [["accept", "Select"], ["north", "Options"], ["dpad", "Navigate"]], 28)
	rebuild()
	_gf = float(_gi)

func _label(fs: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0))
	l.add_theme_color_override("font_shadow_color", Color(0, 0.05, 0.2, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 3)
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---------- The room ----------
func _build_world() -> void:
	_world = Node3D.new()
	_vp.add_child(_world)
	var we := WorldEnvironment.new()
	we.environment = Kit.environment()
	_world.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 46.0
	_cam.position = Vector3(0, 0.35, 6.2)
	_world.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-28), 0)
	key.light_energy = 1.1
	key.light_color = Color(0.85, 0.9, 1.0)
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_world.add_child(key)
	for c in [Color(0.2, 0.75, 1.0), Color(0.85, 0.35, 1.0), Color(0.3, 1.0, 0.8)]:
		var o := OmniLight3D.new()
		o.light_color = c
		o.light_energy = 3.0
		o.omni_range = 7.0
		_world.add_child(o)
		_lights.append(o)
	_floor = Kit.floor_node(-1.75)
	_world.add_child(_floor)
	var m := Kit.motes(160, Vector3(10, 4, 6))
	m.position = Vector3(0, 0.5, -1)
	_world.add_child(m)
	# Far back: a few huge, dim glass shards hanging in the dark, for depth.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 9:
		var s := MeshInstance3D.new()
		s.mesh = Kit.shard_mesh(rng.randf_range(3.0, 7.0), rng.randf_range(0.6, 1.4))
		s.material_override = Kit.glass(Color(0.4, 0.6, 1.0), 0.08)
		s.position = Vector3(rng.randf_range(-14, 14), rng.randf_range(-0.5, 4.5), rng.randf_range(-16, -9))
		s.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		s.set_meta("spin", rng.randf_range(-0.05, 0.05))
		_far.append(s)
		_world.add_child(s)

func _clear_row(list: Array) -> void:
	for c in list:
		(c["node"] as Node).queue_free()
	list.clear()

func rebuild() -> void:
	var keep := ""
	if _gi < _items.size():
		keep = str(_items[_gi].get("id", ""))
	_items.clear()
	for i in home.games.size():
		var g: Dictionary = home.games[i]
		if home.on_home(g):
			_items.append({"label": str(g["title"]), "sub": "In Home", "kind": "game", "id": str(g["id"]), "gi": i, "g": g})
	_items.append({"label": "Library", "sub": "Every game you own", "kind": "library", "id": ""})
	_dock_items = [
		{"label": home.profile_name.text if home.profile_name != null and home.profile_name.text != "" else "Profile", "sub": "Your profile and trophies", "kind": "profile"},
		{"label": "Library", "sub": "Every game you own", "kind": "library"},
		{"label": "Album", "sub": "Screenshots and clips", "kind": "album"},
		{"label": "Wi-Fi", "sub": "Networks", "kind": "wifi"},
		{"label": "Controllers", "sub": "Pads, battery, lightbar", "kind": "pad"},
		{"label": "Settings", "sub": "Everything else", "kind": "settings"},
		{"label": "Themes", "sub": "Change the whole look", "kind": "themes"},
		{"label": "System information", "sub": "Tephra and this PC", "kind": "info"},
	]
	_clear_row(_cards)
	_clear_row(_dock)
	for it in _items:
		_cards.append(_make_card(it))
	for it in _dock_items:
		var made: Array = Kit.icon(str(it["kind"]))
		var n: Node3D = made[0]
		_world.add_child(n)
		_dock.append({"node": n, "core": made[1], "item": it})
	_gi = 0
	for i in _items.size():
		if keep != "" and str(_items[i].get("id", "")) == keep:
			_gi = i
	_gi = clampi(_gi, 0, _items.size() - 1)
	_update_text()

func _make_card(it: Dictionary) -> Dictionary:
	var n := Node3D.new()
	_world.add_child(n)
	var cover := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = CARD
	cover.mesh = q
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.1, 0.14, 0.3) if it["kind"] == "game" else Color(0.08, 0.12, 0.3)
	cm.roughness = 0.35
	cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	cm.emission_enabled = true
	cm.emission = Color(0, 0, 0)
	cm.emission_energy_multiplier = 0.25
	cover.material_override = cm
	n.add_child(cover)
	var slab := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(CARD.x + 0.1, CARD.y + 0.1, 0.12)
	slab.mesh = b
	slab.material_override = Kit.glass(Color(0.6, 0.8, 1.0), 0.1)
	slab.position.z = 0.02
	n.add_child(slab)
	# a soft glowing frame behind the slab, lit up on the one in focus
	var halo := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = CARD + Vector2(0.22, 0.22)
	halo.mesh = hq
	var hm := Kit.glow(Color(0.35, 0.7, 1.0), 0.0)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color = Color(0.35, 0.7, 1.0, 0.0)
	halo.material_override = hm
	halo.position.z = -0.08
	n.add_child(halo)
	if it["kind"] == "library":
		var made: Array = Kit.icon("library")
		var ic: Node3D = made[0]
		ic.position = Vector3(0, 0.1, 0.12)
		ic.scale = Vector3.ONE * 0.9
		n.add_child(ic)
	var lab := Label3D.new()
	lab.text = str(it["label"]) if it["kind"] == "library" else ""
	lab.font_size = 64
	lab.pixel_size = 0.0028
	lab.position = Vector3(0, -0.52, 0.1)
	lab.modulate = Color(0.85, 0.93, 1.0)
	lab.outline_size = 0
	if _font != null:
		lab.font = _font
	n.add_child(lab)
	return {"node": n, "cover": cover, "cover_mat": cm, "halo_mat": hm, "item": it, "loaded": false}

func _load_cover(c: Dictionary) -> void:
	if c["loaded"] or c["item"]["kind"] != "game":
		return
	c["loaded"] = true
	var id := str(c["item"]["id"])
	var pic := TextureRect.new()
	pic.visible = false
	add_child(pic)
	_holders.append(pic)
	var mat: StandardMaterial3D = c["cover_mat"]
	home._load_art(id, "library_600x900", pic, "jpg", func() -> void:
		if is_instance_valid(pic) and pic.texture != null:
			var img := pic.texture.get_image()
			if img != null and not img.is_empty():
				if img.is_compressed():
					img.decompress()
				img.generate_mipmaps()
				var tex := ImageTexture.create_from_image(img)
				_art[id] = tex
				mat.albedo_texture = tex
				mat.albedo_color = Color(1, 1, 1)
				mat.emission_texture = tex
				mat.emission = Color(1, 1, 1))

# ---------- Focus (the hooks home.gd uses) ----------
func selected_gi() -> int:
	if _row != 0 or _gi >= _items.size():
		return -1
	var it: Dictionary = _items[_gi]
	return int(it["gi"]) if it["kind"] == "game" else -1

func top_column() -> float:
	return 0.5

func dim(on: bool) -> void:
	_dim_to = 0.3 if on else 1.0

func move(dir: Vector2i) -> String:
	if dir.y < 0:
		if _row == 0:
			return "up"
		_row = 0
	elif dir.y > 0:
		_row = 1
	elif dir.x != 0:
		if _row == 0:
			_gi = posmod(_gi + dir.x, _items.size())
		else:
			_di = posmod(_di + dir.x, _dock_items.size())
	home.sfx.play("tick")
	Haptics.select()
	_update_text()
	return ""

func handle_input(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return true
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		_activate()
		return true
	return false

func _current() -> Dictionary:
	if _row == 0:
		return _items[_gi] if _gi < _items.size() else {}
	return _dock_items[_di] if _di < _dock_items.size() else {}

func _activate() -> void:
	var it := _current()
	var r: Rect2 = home.clock_label.get_global_rect()
	match str(it.get("kind", "")):
		"game":
			home.play_or_info(int(it["gi"]))
		"library":
			home.sfx.play("open")
			home.library.open(r)
		"profile":
			home.profile_screen.open(r)
		"album":
			home._open_album()
		"wifi":
			home.top_menu.open_menu("wifi", home.wifi_icon.get_global_rect())
		"pad":
			home.top_menu.open_menu("pad", home.pad_wrap.get_global_rect())
		"settings":
			home.settings_screen.open(r)
		"themes":
			home.settings_screen.open(r, 2)
		"info":
			home.settings_screen.open_info(r)
		_:
			Haptics.tick()

func info_selected(_squeeze := true) -> void:
	var it := _current()
	if it.get("kind", "") == "game":
		home.sfx.play("options")
		home.library.open_game(it["g"], _art.get(str(it["id"]), null))

func _update_text() -> void:
	var it := _current()
	_title.text = str(it.get("label", ""))
	_sub.text = str(it.get("sub", ""))

# ---------- Every frame ----------
func _covered() -> bool:
	return home.library.is_open or home.settings_screen.is_open or home.profile_screen.is_open

func _process(delta: float) -> void:
	var live := is_visible_in_tree() and not _covered()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	if not live:
		return
	_t += delta
	var k := 1.0 - exp(-delta * 9.0)
	_gf = _wrap_lerp(_gf, float(_gi), _items.size(), k)
	_df = _wrap_lerp(_df, float(_di), _dock_items.size(), k)
	_rowf = lerpf(_rowf, float(_row), 1.0 - exp(-delta * 7.0))
	_dim = lerpf(_dim, _dim_to, 1.0 - exp(-delta * 9.0))
	_veil.color.a = (1.0 - _dim) * 0.75
	var ui_a := _dim
	_title.modulate.a = ui_a
	_sub.modulate.a = 0.85 * ui_a
	_hints.modulate.a = ui_a
	_title.position = Vector2(110, 150)
	_sub.position = Vector2(112, 228)
	# camera: a slow breathing sway, and it tilts down to the dock
	_cam.position = Vector3(sin(_t * 0.23) * 0.25, 0.35 - _rowf * 0.55 + sin(_t * 0.31) * 0.06, 6.2 - _rowf * 0.3)
	_cam.look_at(Vector3(0, lerpf(CARD_Y - 0.15, DOCK_Y + 0.2, _rowf), 0), Vector3.UP)
	for i in _lights.size():
		var a := _t * (0.25 + 0.08 * i) + i * TAU / 3.0
		(_lights[i] as OmniLight3D).position = Vector3(cos(a) * 4.0, 1.2 + sin(a * 1.3) * 0.8, sin(a) * 2.5 + 1.0)
	(_floor.material_override as ShaderMaterial).set_shader_parameter("t", _t)
	for s in _far:
		(s as Node3D).rotate_y(float(s.get_meta("spin")) * delta)
	_place_cards(delta)
	_place_dock()

func _wrap_lerp(cur: float, target: float, n: int, k: float) -> float:
	if n <= 1:
		return lerpf(cur, target, k)
	var d := fposmod(target - cur + n * 0.5, float(n)) - n * 0.5  # the short way round
	return fposmod(cur + d * k, float(n))

func _offset(i: int, f: float, n: int) -> float:
	var d := float(i) - f
	if n > 1:
		d = fposmod(d + n * 0.5, float(n)) - n * 0.5
	return d

func _place_cards(_delta: float) -> void:
	var n := _cards.size()
	for i in n:
		var c: Dictionary = _cards[i]
		var node: Node3D = c["node"]
		var d := _offset(i, _gf, n)
		if absf(d) > SHOW:
			node.visible = false
			continue
		node.visible = true
		if absf(d) < 4.0:
			_load_cover(c)
		var near := clampf(1.0 - absf(d), 0.0, 1.0)
		var focus := near * (1.0 - _rowf * 0.6)
		var side := signf(d) * minf(absf(d), 1.0)
		var x := d * STEP + side * 0.35
		var z := -absf(d) * 0.55 + focus * 0.9
		var y := CARD_Y + focus * 0.08 + sin(_t * 1.2 + i) * 0.015
		node.position = Vector3(x, y, z)
		node.rotation = Vector3(0, -side * 0.42 + focus * sin(_t * 0.6) * 0.06, 0)
		node.scale = Vector3.ONE * (0.92 + 0.18 * focus)
		var hm: StandardMaterial3D = c["halo_mat"]
		var pulse := 0.75 + 0.25 * sin(_t * 3.0)
		hm.albedo_color.a = focus * 0.55 * pulse
		hm.emission_energy_multiplier = focus * 2.4 * pulse
		var cm: StandardMaterial3D = c["cover_mat"]
		cm.emission_energy_multiplier = 0.12 + 0.3 * focus

func _place_dock() -> void:
	var n := _dock.size()
	for i in n:
		var c: Dictionary = _dock[i]
		var node: Node3D = c["node"]
		var d := _offset(i, _df, n)
		var near := clampf(1.0 - absf(d), 0.0, 1.0)
		var focus := near * _rowf
		node.visible = absf(d) <= 4.6
		node.position = Vector3(d * DOCK_STEP, DOCK_Y + focus * 0.18 + sin(_t * 1.6 + i) * 0.03, -absf(d) * 0.25 + focus * 0.5)
		var spin := _t * 0.9 if focus > 0.5 else sin(_t * 0.7 + i) * 0.35
		node.rotation = Vector3(sin(_t * 0.5 + i) * 0.08, spin * focus + sin(_t * 0.7 + i) * 0.35 * (1.0 - focus), 0)
		node.scale = Vector3.ONE * (0.62 + 0.38 * focus + 0.08 * near)
		var core: StandardMaterial3D = c["core"]
		core.emission_energy_multiplier = 1.0 + 3.5 * focus * (0.8 + 0.2 * sin(_t * 4.0))
