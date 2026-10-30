extends SubViewport
## Prism's backdrop behind every screen (Settings, the Library, the profile...): a slow 3D room of glass
## shards turning over a glowing grid floor. Every screen shows the same picture, so it is rendered ONCE,
## here, at a lower resolution (the bloom makes it soft anyway), and each backdrop copy (tephra_bg.gd)
## just draws this texture. It stops rendering the moment no screen shows it, and while a game runs.

const Kit = preload("res://prism_kit.gd")
const TephraBg = preload("res://tephra_bg.gd")

static var _inst: SubViewport = null
static var _touched := -1

## The shared picture (made on first use). Call touch() every frame it is on screen.
static func texture(from: Node) -> ViewportTexture:
	if _inst == null or not is_instance_valid(_inst):
		_inst = preload("res://prism_bg.gd").new()
		from.get_tree().root.add_child.call_deferred(_inst)
	return _inst.get_texture()

static func touch() -> void:
	_touched = Engine.get_process_frames()

var _t := 0.0
var _cam: Camera3D
var _cluster: Node3D
var _shards: Array = []
var _floor: MeshInstance3D
var _lights: Array = []

func _init() -> void:
	own_world_3d = true
	size = Vector2i(1280, 720)
	msaa_3d = Viewport.MSAA_DISABLED
	screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	gui_disable_input = true

func _ready() -> void:
	var win := get_tree().root.size
	if win.x > 0:
		size = Vector2i(maxi(win.x / 2, 640), maxi(win.y / 2, 360))
	var w := Node3D.new()
	add_child(w)
	var we := WorldEnvironment.new()
	we.environment = Kit.environment(Color(0.01, 0.015, 0.05), Color(0.06, 0.08, 0.2), false)
	w.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	w.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(30), 0)
	key.light_energy = 0.9
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	w.add_child(key)
	for c in [Color(0.25, 0.7, 1.0), Color(0.8, 0.35, 1.0)]:
		var o := OmniLight3D.new()
		o.light_color = c
		o.light_energy = 2.5
		o.omni_range = 9.0
		w.add_child(o)
		_lights.append(o)
	_floor = Kit.floor_node(-2.2)
	(_floor.material_override as ShaderMaterial).set_shader_parameter("strength", 0.45)
	w.add_child(_floor)
	var m := Kit.motes(110, Vector3(12, 5, 8))
	w.add_child(m)
	# a loose ring of glass shards turning slowly around the middle of the room
	_cluster = Node3D.new()
	_cluster.position = Vector3(3.5, 0.6, -6.0)
	w.add_child(_cluster)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mats := [Kit.glass(Color(0.5, 0.75, 1.0), 0.14), Kit.glass(Color(0.75, 0.55, 1.0), 0.14), Kit.glass(Color(0.4, 1.0, 0.9), 0.12)]
	for i in 26:
		var s := MeshInstance3D.new()
		s.mesh = Kit.shard_mesh(rng.randf_range(0.6, 2.2), rng.randf_range(0.2, 0.5))
		s.material_override = mats[i % 3]
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.5, 4.0)
		s.position = Vector3(cos(a) * r, rng.randf_range(-1.2, 2.2), sin(a) * r)
		s.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		s.set_meta("spin", Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3), 0))
		_cluster.add_child(s)
		_shards.append(s)
	var heart := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.35
	hs.height = 0.7
	heart.mesh = hs
	heart.material_override = Kit.glow(Color(0.45, 0.75, 1.0), 3.0)
	_cluster.add_child(heart)

func _process(delta: float) -> void:
	var live := not TephraBg.paused and Engine.get_process_frames() - _touched <= 3
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
	if not live:
		return
	_t += delta
	_cam.position = Vector3(sin(_t * 0.05) * 1.5, 0.8 + sin(_t * 0.07) * 0.3, 6.0)
	_cam.look_at(Vector3(1.2, 0.3, -4.0), Vector3.UP)
	_cluster.rotation.y = _t * 0.06
	for s in _shards:
		var sp: Vector3 = s.get_meta("spin")
		(s as Node3D).rotation += sp * delta
	for i in _lights.size():
		var a := _t * (0.15 + 0.05 * i) + i * PI
		(_lights[i] as OmniLight3D).position = Vector3(3.5 + cos(a) * 5.0, 1.5, -6.0 + sin(a) * 4.0)
	(_floor.material_override as ShaderMaterial).set_shader_parameter("t", _t)
