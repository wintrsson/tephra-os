extends RefCounted
## Prism (the developer theme): the shared 3D pieces. Glass and glow materials, the night environment,
## the reflective grid floor, floating light motes, and the 3D glass icons. Used by the Prism Home
## (prism.gd), the backdrop behind every other screen (prism_bg.gd) and the start-up intro (intro3d.gd).
## Everything is built from Godot's own meshes in code, so the theme needs no model files.

const FLOOR_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec4 base : source_color = vec4(0.012, 0.016, 0.04, 1.0);
uniform vec4 line : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform float strength = 0.7;
uniform float t = 0.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = wp.xz * 0.5;
	vec2 g = abs(fract(uv) - 0.5) / max(fwidth(uv), vec2(0.0001));
	float l = 1.0 - min(min(g.x, g.y), 1.0);
	float d = length(wp.xz);
	float fade = exp(-d * 0.16);
	float pulse = 0.55 + 0.45 * sin(d * 1.3 - t * 1.6);
	ALBEDO = base.rgb;
	METALLIC = 0.75;
	ROUGHNESS = 0.14;
	EMISSION = line.rgb * l * fade * strength * pulse;
}
"""

## See-through glass with a bright rim and a clear coat. tint sets its colour, alpha how much of it shows.
static func glass(tint: Color, alpha := 0.16) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	m.metallic = 0.15
	m.metallic_specular = 1.0
	m.roughness = 0.04
	m.rim_enabled = true
	m.rim = 1.0
	m.rim_tint = 0.4
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.03
	return m

## A light that glows (the bloom in the environment picks it up).
static func glow(col: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

## A shiny solid surface (for the darker parts of the icons).
static func gloss(col: Color, metal := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.12
	m.clearcoat_enabled = true
	m.clearcoat = 0.8
	return m

## Deep night sky, soft bloom on everything bright, filmic colour, and a little depth haze.
static func environment(top := Color(0.015, 0.02, 0.06), horizon := Color(0.07, 0.09, 0.22), reflections := true) -> Environment:
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = top
	sm.sky_horizon_color = horizon
	sm.ground_horizon_color = horizon.darkened(0.3)
	sm.ground_bottom_color = Color(0.005, 0.006, 0.015)
	sm.sun_angle_max = 0.01
	sm.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.8)
	env.set_glow_level(5, 0.5)
	env.fog_enabled = true
	env.fog_light_color = horizon
	env.fog_density = 0.018
	env.fog_sky_affect = 0.0
	if reflections:
		env.ssr_enabled = true  # reflections of the glass in the floor (Vulkan only; ignored otherwise)
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.2
		env.ssr_fade_out = 2.0
	return env

## The glossy black floor with a faint grid of light that fades into the distance and pulses outward.
static func floor_node(y: float, line := Color(0.35, 0.65, 1.0)) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("line", line)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Floating specks of light drifting slowly upward through the scene.
static func motes(amount := 140, extent := Vector3(9, 4, 5), col := Color(0.6, 0.85, 1.0)) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extent
	p.direction = Vector3(0, 1, 0)
	p.spread = 30.0
	p.gravity = Vector3(0, 0.02, 0)
	p.initial_velocity_min = 0.03
	p.initial_velocity_max = 0.12
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.2, 1))
	curve.add_point(Vector2(0.8, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var sm := SphereMesh.new()
	sm.radius = 0.014
	sm.height = 0.028
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = glow(col, 4.0)
	p.mesh = sm
	return p

static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

static func _sphere(r: float, seg := 24) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 2)
	return s

static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 32
	t.ring_segments = 12
	return t

static func _cyl(top: float, bottom: float, h: float, seg := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

## The colour each icon glows with.
const ICON_COLORS := {
	"profile": Color(0.45, 0.85, 1.0), "library": Color(0.55, 0.65, 1.0), "album": Color(1.0, 0.55, 0.85),
	"wifi": Color(0.35, 1.0, 0.85), "pad": Color(0.75, 0.55, 1.0), "settings": Color(0.7, 0.85, 1.0),
	"themes": Color(1.0, 0.75, 0.4), "info": Color(0.5, 0.95, 1.0), "power": Color(1.0, 0.45, 0.45),
}

## A 3D glass icon, about one unit across, facing the camera (+Z). Each one has a glass body and a
## glowing heart, so it reads in the dark and blooms when selected. Returns [node, glowing material].
static func icon(kind: String) -> Array:
	var root := Node3D.new()
	var col: Color = ICON_COLORS.get(kind, Color(0.6, 0.8, 1.0))
	var gl := glass(col, 0.22)
	var core := glow(col, 2.2)
	match kind:
		"profile":
			_mesh(root, _sphere(0.17), gl, Vector3(0, 0.2, 0))
			_mesh(root, _sphere(0.08), core, Vector3(0, 0.2, 0))
			var body := CapsuleMesh.new()
			body.radius = 0.26
			body.height = 0.62
			_mesh(root, body, gl, Vector3(0, -0.22, 0), Vector3.ZERO, Vector3(1, 0.55, 0.7))
			_mesh(root, _torus(0.2, 0.24), core, Vector3(0, -0.08, 0), Vector3(PI / 2, 0, 0), Vector3(1, 1, 0.5))
		"library":
			for k in 3:
				var tilt := -0.28 if k == 2 else 0.0
				_mesh(root, _box(0.15, 0.56, 0.4), gl, Vector3(-0.2 + k * 0.19 + (0.05 if k == 2 else 0.0), -0.02 * k, 0), Vector3(0, 0, tilt))
				_mesh(root, _box(0.155, 0.04, 0.405), core, Vector3(-0.2 + k * 0.19 + (0.05 if k == 2 else 0.0), 0.12, 0), Vector3(0, 0, tilt))
			_mesh(root, _box(0.75, 0.04, 0.46), gloss(Color(0.08, 0.1, 0.2)), Vector3(0, -0.32, 0))
		"album":
			_mesh(root, _box(0.66, 0.5, 0.08), gl)
			_mesh(root, _box(0.54, 0.38, 0.02), glow(col.darkened(0.35), 1.2), Vector3(0, 0, 0.03))
			_mesh(root, _sphere(0.06), glow(Color(1, 0.95, 0.8), 4.0), Vector3(0.14, 0.08, 0.06))
			var hill := PrismMesh.new()
			hill.size = Vector3(0.36, 0.2, 0.02)
			_mesh(root, hill, glow(col.lightened(0.2), 2.0), Vector3(-0.08, -0.08, 0.05))
		"wifi":
			for k in 3:
				var r := 0.14 + k * 0.13
				_mesh(root, _torus(r - 0.035, r), gl if k != 1 else core, Vector3(0, -0.22, 0), Vector3(PI / 2, 0, 0))
			_mesh(root, _sphere(0.06), core, Vector3(0, -0.22, 0))
		"pad":
			var body := CapsuleMesh.new()
			body.radius = 0.17
			body.height = 0.78
			_mesh(root, body, gl, Vector3.ZERO, Vector3(0, 0, PI / 2))
			_mesh(root, _sphere(0.17), gl, Vector3(-0.27, -0.1, 0))
			_mesh(root, _sphere(0.17), gl, Vector3(0.27, -0.1, 0))
			_mesh(root, _cyl(0.05, 0.05, 0.08), core, Vector3(-0.12, -0.02, 0.15), Vector3(PI / 2, 0, 0))
			_mesh(root, _cyl(0.05, 0.05, 0.08), core, Vector3(0.12, -0.02, 0.15), Vector3(PI / 2, 0, 0))
			for k in 4:
				var a := k * PI / 2
				_mesh(root, _sphere(0.025, 8), glow(col.lightened(0.3), 3.0), Vector3(0.27 + cos(a) * 0.07, 0.07 + sin(a) * 0.07, 0.14))
		"settings":
			_mesh(root, _torus(0.17, 0.3), gl, Vector3.ZERO, Vector3(PI / 2, 0, 0))
			for k in 8:
				var a := k * TAU / 8.0
				_mesh(root, _box(0.11, 0.11, 0.13), gl, Vector3(cos(a) * 0.34, sin(a) * 0.34, 0), Vector3(0, 0, a))
			_mesh(root, _cyl(0.1, 0.1, 0.16), core, Vector3.ZERO, Vector3(PI / 2, 0, 0))
		"themes":
			_mesh(root, _cyl(0.2, 0.36, 0.14, 8), gl, Vector3(0, 0.14, 0))
			_mesh(root, _cyl(0.36, 0.0, 0.44, 8), gl, Vector3(0, -0.15, 0))
			_mesh(root, _sphere(0.1, 8), core, Vector3(0, 0.02, 0))
		"info":
			_mesh(root, _sphere(0.34), gl)
			_mesh(root, _box(0.07, 0.24, 0.07), core, Vector3(0, -0.06, 0))
			_mesh(root, _sphere(0.05, 12), core, Vector3(0, 0.15, 0))
		"power":
			_mesh(root, _torus(0.22, 0.29), gl, Vector3.ZERO, Vector3(PI / 2, 0, 0))
			_mesh(root, _box(0.07, 0.3, 0.07), core, Vector3(0, 0.12, 0))
		_:
			_mesh(root, _box(0.5, 0.5, 0.5), gl)
			_mesh(root, _sphere(0.12), core)
	return [root, core]

## A thin long glass shard (for the intro and the backdrop): a stretched, faceted prism.
static func shard_mesh(len: float, w: float) -> Mesh:
	var p := PrismMesh.new()
	p.size = Vector3(w, len, w * 0.35)
	return p
