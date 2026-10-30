extends CanvasLayer
## Developer 3D tests (dev menu > 3D and particle tests): a small live 3D scene on its own screen to check that
## the graphics work on this PC and how they perform. Left / Right (or L1 / R1) change the test, A restarts
## its animation, B leaves. The numbers at the top are the frame rate and the number of things being drawn.

const Themes = preload("res://themes.gd")
const TephraGlyphs = preload("res://glyphs.gd")
const Haptics = preload("res://haptics.gd")

const TESTS := ["Cubes", "Spheres and lights", "Particles", "Animation", "Glass and materials", "Many objects"]

var is_open := false
var _home
var _ct: SubViewportContainer
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _title: Label
var _stats: Label
var _hints: HBoxContainer
var _bg: ColorRect
var _i := 0
var _t := 0.0
var _spin: Array = []     # nodes that turn: [node, axis, speed]
var _bob: Array = []      # nodes that bob: [node, base y, phase]

func setup(home) -> void:
	_home = home

func _ready() -> void:
	layer = 88
	visible = false
	set_process(false)
	_bg = ColorRect.new()
	_bg.color = Color(0.02, 0.04, 0.09)
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ct = SubViewportContainer.new()
	_ct.stretch = true
	add_child(_ct)
	_ct.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.handle_input_locally = false
	_ct.add_child(_vp)
	_title = _label(46)
	_title.position = Vector2(80, 50)
	add_child(_title)
	_stats = _label(26)
	_stats.position = Vector2(80, 112)
	_stats.modulate = Color(1, 1, 1, 0.7)
	add_child(_stats)
	_hints = HBoxContainer.new()
	_hints.alignment = BoxContainer.ALIGNMENT_END
	add_child(_hints)
	_hints.anchor_left = 0.0
	_hints.anchor_right = 1.0
	_hints.anchor_top = 1.0
	_hints.anchor_bottom = 1.0
	_hints.offset_left = 80
	_hints.offset_right = -90
	_hints.offset_top = -120
	_hints.offset_bottom = -60
	TephraGlyphs.fill(_hints, [["dpad_h", "Change test"], ["accept", "Restart"], ["back", "Back"]], 28)

func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func open() -> void:
	is_open = true
	visible = true
	_i = 0
	_build()
	set_process(true)

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	set_process(false)
	_clear()

func move(dir: Vector2i) -> void:
	if is_open and dir.x != 0:
		_i = posmod(_i + dir.x, TESTS.size())  # round the ends
		Haptics.select()
		_build()

func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if event is InputEventJoypadMotion:
		return true
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_build()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_LEFT_SHOULDER:
		move(Vector2i(-1, 0))
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		move(Vector2i(1, 0))
	return true

func _clear() -> void:
	if _world != null:
		_vp.remove_child(_world)
		_world.queue_free()
		_world = null
	_spin.clear()
	_bob.clear()

# ---------- Building the tests ----------
func _mat(c: Color, metal := 0.0, rough := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m

func _mesh(shape: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = shape
	mi.material_override = mat
	mi.position = pos
	_world.add_child(mi)
	return mi

func _build() -> void:
	_clear()
	_t = 0.0
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.04, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.55, 0.75)
	e.ambient_light_energy = 0.6
	env.environment = e
	_world.add_child(env)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 2.2, 7)
	_cam.rotation_degrees = Vector3(-14, 0, 0)
	_world.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	_world.add_child(sun)
	var floor_mi := _mesh(PlaneMesh.new(), _mat(Color(0.08, 0.12, 0.22), 0.2, 0.35), Vector3(0, -1.2, 0))
	(floor_mi.mesh as PlaneMesh).size = Vector2(30, 30)
	match _i:
		0: _t_cubes()
		1: _t_spheres()
		2: _t_particles()
		3: _t_animation()
		4: _t_glass()
		5: _t_many()
	_title.text = "%d / %d   %s" % [_i + 1, TESTS.size(), TESTS[_i]]

func _t_cubes() -> void:
	for x in 5:
		for z in 3:
			var c := Color.from_hsv(float(x * 3 + z) / 15.0, 0.6, 0.95)
			var m := _mesh(BoxMesh.new(), _mat(c, 0.1, 0.4), Vector3((x - 2) * 1.8, 0.0, (z - 1) * 1.8))
			_spin.append([m, Vector3(1, 1, 0).normalized(), 0.6 + 0.2 * float(x + z)])

func _t_spheres() -> void:
	for k in 5:
		var s := SphereMesh.new()
		var m := _mesh(s, _mat(Color.from_hsv(float(k) / 5.0, 0.2 + 0.15 * k, 0.95), float(k) / 4.0, 0.9 - 0.2 * k), Vector3((k - 2) * 1.9, 0.0, 0.0))
		_bob.append([m, 0.0, float(k) * 0.7])
	for lc in [[Color(1, 0.3, 0.3), Vector3(-4, 1.5, 2)], [Color(0.3, 1, 0.4), Vector3(0, 2.5, 3)], [Color(0.3, 0.5, 1), Vector3(4, 1.5, 2)]]:
		var l := OmniLight3D.new()
		l.light_color = lc[0]
		l.position = lc[1]
		l.omni_range = 9.0
		l.light_energy = 2.0
		_world.add_child(l)

func _t_particles() -> void:
	var fire := CPUParticles3D.new()
	fire.position = Vector3(-3, -1.1, 0)
	fire.amount = 220
	fire.lifetime = 1.4
	fire.direction = Vector3(0, 1, 0)
	fire.spread = 18.0
	fire.initial_velocity_min = 2.0
	fire.initial_velocity_max = 3.4
	fire.gravity = Vector3(0, 0.6, 0)
	fire.scale_amount_min = 0.5
	fire.scale_amount_max = 1.0
	var qm := SphereMesh.new()
	qm.radius = 0.08
	qm.height = 0.16
	fire.mesh = qm
	var fm := _mat(Color(1, 0.6, 0.15))
	fm.emission_enabled = true
	fm.emission = Color(1, 0.45, 0.1)
	fm.emission_energy_multiplier = 3.0
	fire.material_override = fm
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 0.95, 0.5), Color(1, 0.35, 0.05), Color(0.3, 0.05, 0.0, 0.0)])
	fire.color_ramp = g
	_world.add_child(fire)
	var fountain := CPUParticles3D.new()
	fountain.position = Vector3(0, -1.1, 0)
	fountain.amount = 300
	fountain.lifetime = 2.2
	fountain.direction = Vector3(0, 1, 0)
	fountain.spread = 14.0
	fountain.initial_velocity_min = 5.0
	fountain.initial_velocity_max = 6.5
	fountain.gravity = Vector3(0, -7.0, 0)
	var dm := SphereMesh.new()
	dm.radius = 0.06
	dm.height = 0.12
	fountain.mesh = dm
	var wm := _mat(Color(0.5, 0.8, 1.0))
	wm.emission_enabled = true
	wm.emission = Color(0.3, 0.6, 1.0)
	wm.emission_energy_multiplier = 1.6
	fountain.material_override = wm
	_world.add_child(fountain)
	var burst := CPUParticles3D.new()
	burst.position = Vector3(3, 0.3, 0)
	burst.amount = 140
	burst.lifetime = 1.6
	burst.one_shot = false
	burst.explosiveness = 0.9
	burst.direction = Vector3(0, 1, 0)
	burst.spread = 180.0
	burst.initial_velocity_min = 2.0
	burst.initial_velocity_max = 4.5
	burst.gravity = Vector3(0, -2.0, 0)
	burst.mesh = dm
	var bm := _mat(Color(0.9, 0.5, 1.0))
	bm.emission_enabled = true
	bm.emission = Color(0.8, 0.3, 1.0)
	bm.emission_energy_multiplier = 2.0
	burst.material_override = bm
	_world.add_child(burst)

func _t_animation() -> void:
	var cube := _mesh(BoxMesh.new(), _mat(Color(0.95, 0.4, 0.3), 0.2, 0.3), Vector3(-3, 0, 0))
	var sph := _mesh(SphereMesh.new(), _mat(Color(0.3, 0.8, 0.5), 0.2, 0.3), Vector3(0, 0, 0))
	var cyl := _mesh(CylinderMesh.new(), _mat(Color(0.35, 0.55, 1.0), 0.2, 0.3), Vector3(3, 0, 0))
	# one AnimationPlayer drives all three (position, rotation and scale tracks), looping
	var ap := AnimationPlayer.new()
	_world.add_child(ap)
	var anim := Animation.new()
	anim.length = 2.4
	anim.loop_mode = Animation.LOOP_LINEAR
	var lib := AnimationLibrary.new()
	for pair in [[cube, "position", Vector3(-3, 0, 0), Vector3(-3, 1.6, 0)], [sph, "scale", Vector3.ONE, Vector3(1.5, 0.6, 1.5)], [cyl, "rotation", Vector3.ZERO, Vector3(0, TAU, 0)]]:
		var tr := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(tr, NodePath(str(_world.get_path_to(pair[0])) + ":" + str(pair[1])))
		anim.track_insert_key(tr, 0.0, pair[2])
		anim.track_insert_key(tr, 1.2, pair[3])
		anim.track_insert_key(tr, 2.4, pair[2])
		anim.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC)
	lib.add_animation("loop", anim)
	ap.add_animation_library("", lib)
	ap.play("loop")
	# and a tween on a ring of small cubes
	for k in 8:
		var a := TAU * float(k) / 8.0
		var m := _mesh(BoxMesh.new(), _mat(Color.from_hsv(float(k) / 8.0, 0.7, 1.0)), Vector3(cos(a) * 2.2, 2.3, sin(a) * 2.2 - 1.0))
		m.scale = Vector3.ONE * 0.4
		var tw := m.create_tween().set_loops()
		tw.tween_property(m, "scale", Vector3.ONE * 0.8, 0.5 + 0.05 * k).set_trans(Tween.TRANS_SINE)
		tw.tween_property(m, "scale", Vector3.ONE * 0.3, 0.5 + 0.05 * k).set_trans(Tween.TRANS_SINE)

func _t_glass() -> void:
	for k in 4:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(float(k) / 4.0, 0.5, 1.0, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.1
		m.metallic = 0.0
		var s := _mesh(SphereMesh.new(), m, Vector3((k - 1.5) * 1.7, 0.2, 0.5 * (k % 2)))
		_bob.append([s, 0.2, float(k)])
	var gold := _mesh(TorusMesh.new(), _mat(Color(1.0, 0.8, 0.3), 1.0, 0.2), Vector3(0, 1.8, -1))
	_spin.append([gold, Vector3(1, 0.3, 0).normalized(), 0.9])
	var chrome := _mesh(BoxMesh.new(), _mat(Color(0.9, 0.95, 1.0), 1.0, 0.05), Vector3(-3.5, 1.4, -1))
	_spin.append([chrome, Vector3(0, 1, 0.4).normalized(), 0.7])
	var emit := StandardMaterial3D.new()
	emit.albedo_color = Color(0.1, 0.1, 0.1)
	emit.emission_enabled = true
	emit.emission = Color(0.3, 1.0, 0.7)
	emit.emission_energy_multiplier = 2.5
	var eb := _mesh(CapsuleMesh.new(), emit, Vector3(3.5, 1.4, -1))
	_spin.append([eb, Vector3(0, 0, 1), 0.8])

func _t_many() -> void:
	# 600 small cubes on one shared mesh: a quick check of how many objects this PC draws smoothly
	var shape := BoxMesh.new()
	shape.size = Vector3.ONE * 0.28
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = shape
	mm.instance_count = 600
	for k in 600:
		var a := float(k) * 0.37
		var r := 0.6 + float(k % 60) * 0.05
		mm.set_instance_transform(k, Transform3D(Basis.from_euler(Vector3(a, a * 0.5, 0)), Vector3(cos(a) * r, -1.0 + float(k) / 600.0 * 4.5, sin(a) * r - 1.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat(Color(0.45, 0.75, 1.0), 0.3, 0.35)
	_world.add_child(mmi)
	_spin.append([mmi, Vector3(0, 1, 0), 0.5])

# ---------- Each frame ----------
func _process(delta: float) -> void:
	_t += delta
	for s in _spin:
		var n: Node3D = s[0]
		if is_instance_valid(n):
			n.rotate(s[1], float(s[2]) * delta)
	for b in _bob:
		var n: Node3D = b[0]
		if is_instance_valid(n):
			n.position.y = float(b[1]) + 0.5 * sin(_t * 1.8 + float(b[2]))
	if _cam != null:
		var a := sin(_t * 0.25) * 0.35
		_cam.position = Vector3(sin(a) * 7.0, 2.2, cos(a) * 7.0)
		_cam.look_at(Vector3(0, 0.2, 0))
	_stats.text = "%d fps    %d objects drawn    %s" % [Engine.get_frames_per_second(), int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)), RenderingServer.get_current_rendering_method()]
