extends SubViewportContainer
## Prism's start-up intro, in real 3D (shown by boot_overlay.gd). About six seconds:
##   0.0 s  darkness; specks of light drift up and the grid floor glows in under the camera
##   0.3 s  140 glass shards fly in from all around, tumbling, while the camera swings round
##   3.0 s  the last shard lands: they form one tall crystal, its heart lights up with a flash,
##          a burst of sparks and three rings of light spreading out
##   3.6 s  the name appears under the crystal, which keeps turning and breathing
## The sound (sfx.gd, "prism" in _render_theme_intro) is timed to the same moments.

const Kit = preload("res://prism_kit.gd")

const N := 140
const IMPACT := 3.0

var _vp: SubViewport
var _cam: Camera3D
var _crystal: Node3D
var _shards: Array = []   # {node, from, to, q0, q1, start, dur}
var _core_mat: StandardMaterial3D
var _core_light: OmniLight3D
var _burst: CPUParticles3D
var _rings: Array = []    # {node, mat, at, tilt}
var _floor: MeshInstance3D
var _name: Label3D
var _t := 0.0
var _burst_done := false

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.gui_disable_input = true
	add_child(_vp)
	var w := Node3D.new()
	_vp.add_child(w)
	var we := WorldEnvironment.new()
	var env := Kit.environment(Color(0.0, 0.0, 0.01), Color(0.02, 0.03, 0.09), false)
	env.glow_intensity = 1.1
	env.fog_density = 0.03
	we.environment = env
	w.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	w.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-30), deg_to_rad(40), 0)
	key.light_energy = 0.8
	key.light_color = Color(0.75, 0.85, 1.0)
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	w.add_child(key)
	for c in [[Color(0.2, 0.7, 1.0), Vector3(-4, 2, 3)], [Color(0.85, 0.35, 1.0), Vector3(4, -1, 2)]]:
		var o := OmniLight3D.new()
		o.light_color = c[0]
		o.light_energy = 2.5
		o.omni_range = 10.0
		o.position = c[1]
		w.add_child(o)
	_floor = Kit.floor_node(-3.0)
	(_floor.material_override as ShaderMaterial).set_shader_parameter("strength", 0.0)
	w.add_child(_floor)
	var m := Kit.motes(180, Vector3(12, 6, 10))
	w.add_child(m)

	_crystal = Node3D.new()
	w.add_child(_crystal)
	var core := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 0.3
	cs.height = 0.6
	core.mesh = cs
	core.scale = Vector3(1, 2.2, 1)
	_core_mat = Kit.glow(Color(0.5, 0.8, 1.0), 0.0)
	core.material_override = _core_mat
	_crystal.add_child(core)
	_core_light = OmniLight3D.new()
	_core_light.light_color = Color(0.55, 0.8, 1.0)
	_core_light.light_energy = 0.0
	_core_light.omni_range = 9.0
	_crystal.add_child(_core_light)

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var mats := [Kit.glass(Color(0.55, 0.8, 1.0), 0.2), Kit.glass(Color(0.75, 0.6, 1.0), 0.2), Kit.glass(Color(0.5, 1.0, 0.95), 0.18)]
	# The crystal is a tall double point (an octahedron stretched upward): every shard gets a spot on
	# one of its eight faces and lies flat against it.
	var tip := Vector3(0, 2.3, 0)
	var foot := Vector3(0, -2.3, 0)
	var ring := [Vector3(1.25, 0, 0), Vector3(0, 0, 1.25), Vector3(-1.25, 0, 0), Vector3(0, 0, -1.25)]
	for i in N:
		var face := i % 8
		var apex: Vector3 = tip if face < 4 else foot
		var a: Vector3 = ring[face % 4]
		var b: Vector3 = ring[(face + 1) % 4]
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var p: Vector3 = apex + (a - apex) * u + (b - apex) * v
		var normal: Vector3 = ((a - apex).cross(b - apex)).normalized()
		if normal.dot(p) < 0.0:
			normal = -normal
		var to := p + normal * 0.02
		var basis_to := Basis.looking_at(-normal, (apex - p).normalized() if (apex - p).length() > 0.01 else Vector3.UP)
		basis_to = basis_to.rotated(normal, rng.randf_range(-0.6, 0.6))
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var from := dir * rng.randf_range(10.0, 17.0)
		var s := MeshInstance3D.new()
		s.mesh = Kit.shard_mesh(rng.randf_range(0.45, 0.9), rng.randf_range(0.28, 0.5))
		s.material_override = mats[i % 3]
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = from
		_crystal.add_child(s)
		var dur := rng.randf_range(0.9, 1.4)
		var start := rng.randf_range(0.3, IMPACT - dur)
		var q0 := Quaternion.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		_shards.append({"node": s, "from": from, "to": to, "q0": q0, "q1": basis_to.get_rotation_quaternion(),
			"start": start, "dur": dur, "spin": rng.randf_range(2.0, 5.0), "n": normal})

	_burst = CPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.explosiveness = 1.0
	_burst.amount = 320
	_burst.lifetime = 2.4
	_burst.direction = Vector3(0, 1, 0)
	_burst.spread = 180.0
	_burst.gravity = Vector3(0, -0.6, 0)
	_burst.initial_velocity_min = 2.0
	_burst.initial_velocity_max = 7.5
	_burst.damping_min = 1.5
	_burst.damping_max = 3.0
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(1, 0))
	_burst.scale_amount_curve = fade
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = Kit.glow(Color(0.7, 0.9, 1.0), 6.0)
	_burst.mesh = sm
	w.add_child(_burst)

	for k in 3:
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.97
		tm.outer_radius = 1.0
		tm.rings = 64
		tm.ring_segments = 6
		r.mesh = tm
		var rm := Kit.glow([Color(0.4, 0.8, 1.0), Color(0.8, 0.5, 1.0), Color(0.45, 1.0, 0.9)][k], 4.0)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		r.material_override = rm
		r.visible = false
		w.add_child(r)
		_rings.append({"node": r, "mat": rm, "at": IMPACT + k * 0.22, "tilt": Vector3([0.0, 0.5, -0.45][k], 0, [0.0, 0.3, -0.25][k])})

	_name = Label3D.new()
	_name.text = "T E P H R A"
	_name.font_size = 96
	_name.pixel_size = 0.006
	_name.position = Vector3(0, -3.2, 0.6)
	_name.modulate = Color(0.85, 0.94, 1.0, 0.0)
	_name.outline_size = 0
	_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var f = load("res://themes.gd").font("prism")
	if f != null:
		_name.font = f
	w.add_child(_name)
	_place_camera()

func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _place_camera() -> void:
	var k := _ease_out(_t / 4.5)
	var ang := lerpf(-0.9, 0.35, k) + 0.03 * _t
	var dist := lerpf(15.0, 8.6, k)
	_cam.position = Vector3(sin(ang) * dist, lerpf(2.5, 0.4, k), cos(ang) * dist)
	_cam.look_at(Vector3(0, lerpf(0.0, -0.35, k), 0), Vector3.UP)

func _process(delta: float) -> void:
	_t += delta
	_place_camera()
	(_floor.material_override as ShaderMaterial).set_shader_parameter("t", _t)
	(_floor.material_override as ShaderMaterial).set_shader_parameter("strength", 0.7 * smoothstep(0.3, 2.2, _t))
	var after := maxf(_t - IMPACT, 0.0)
	var breathe := 1.0 + 0.04 * sin(after * 2.4) * smoothstep(0.0, 0.6, after)
	for s in _shards:
		var node: Node3D = s["node"]
		var x := (_t - float(s["start"])) / float(s["dur"])
		var e := _ease_out(x)
		var to: Vector3 = s["to"]
		var pos: Vector3 = (s["from"] as Vector3).lerp(to, e)
		if x >= 1.0:
			pos = to * breathe + (s["n"] as Vector3) * 0.25 * exp(-after * 5.0) * smoothstep(0.0, 0.05, after)  # the flash pushes them out a touch
		node.position = pos
		var q0: Quaternion = s["q0"]
		var spun := q0 * Quaternion(Vector3.UP, (1.0 - e) * float(s["spin"]))
		node.quaternion = spun.slerp(s["q1"], e)
	_crystal.rotation.y = 0.15 * _t + 0.5 * _ease_out(after / 2.5)
	# the heart lights up as the last shards land, flashes, then glows steadily
	var glow := smoothstep(IMPACT - 0.5, IMPACT, _t) * (1.0 + 4.0 * exp(-after * 3.0) * smoothstep(0.0, 0.02, after))
	_core_mat.emission_energy_multiplier = glow * 3.0
	_core_mat.albedo_color = Color(0.5, 0.8, 1.0) * minf(glow, 1.0)  # dark until it lights up
	_core_light.light_energy = glow * 3.5
	if _t >= IMPACT and not _burst_done:
		_burst_done = true
		_burst.restart()
		_burst.emitting = true
	for r in _rings:
		var node: MeshInstance3D = r["node"]
		var rt := _t - float(r["at"])
		node.visible = rt >= 0.0 and rt < 2.0
		if node.visible:
			var k := _ease_out(rt / 1.8)
			node.scale = Vector3.ONE * (0.6 + 7.0 * k)
			node.rotation = r["tilt"]
			(r["mat"] as StandardMaterial3D).albedo_color.a = 1.0 - k
			(r["mat"] as StandardMaterial3D).emission_energy_multiplier = 4.0 * (1.0 - k)
	_name.modulate.a = smoothstep(IMPACT + 0.6, IMPACT + 1.4, _t)
