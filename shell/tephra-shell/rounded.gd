extends RefCounted
## Smooth rounded corners for tile art.
## Godot's "clip children" gives hard, stair-stepped corners. This puts a shader on the
## picture instead: it fades the pixels along the rounded edge, so the corners are
## anti-aliased (and stay sharp when the tile is scaled up).

const CODE := """
shader_type canvas_item;
uniform vec2 box_size = vec2(180.0, 270.0);
uniform float radius = 16.0;
varying vec2 local;
void vertex() {
	local = VERTEX;
}
void fragment() {
	vec2 p = local - box_size * 0.5;
	vec2 q = abs(p) - (box_size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float w = max(fwidth(d), 0.0001);
	COLOR.a *= clamp(0.5 - d / w, 0.0, 1.0);
}
"""

## Gothic: instead of a clean rounded corner, the edge is rough and burnt, like old paper held to a candle. The edge is
## bitten in by noise (deepest at the corners), a band of char darkens the picture just inside it, and a thin line
## of ember glows along the burnt edge. A faint grain roughens the whole surface.
const ROUGH := """
shader_type canvas_item;
uniform vec2 box_size = vec2(180.0, 270.0);
uniform float radius = 6.0;
uniform float seed = 0.0;
uniform float burn = 1.0;
uniform float scorch = 1.0;   // how much char and ember (0 for a selection frame: it only gets the rough edge)
varying vec2 local;
void vertex() {
	local = VERTEX;
}
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { return vn(p) * 0.55 + vn(p * 2.13) * 0.3 + vn(p * 4.37) * 0.15; }
void fragment() {
	vec2 p = local - box_size * 0.5;
	vec2 q = abs(p) - (box_size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	vec2 e = box_size * 0.5 - abs(p);
	float reach = 0.28 * min(box_size.x, box_size.y) + 24.0;
	float corner = 1.0 - smoothstep(0.0, reach, length(e));
	vec2 s = local + vec2(seed * 97.0, seed * 53.0);
	float n = fbm(s / 7.0);
	float bite = burn * (1.5 + 4.5 * n + corner * (8.0 + 22.0 * fbm(s / 19.0)));
	float dd = d + bite;
	float w = max(fwidth(d), 0.0001);
	float a = clamp(0.5 - dd / w, 0.0, 1.0);
	float inside = -dd;
	vec3 c = COLOR.rgb;
	float char_k = 1.0 - smoothstep(0.0, 7.0 + 12.0 * corner, inside);
	c = mix(c, vec3(0.045, 0.032, 0.022), char_k * 0.88 * scorch);
	float ember = (1.0 - smoothstep(0.0, 2.0, inside)) * (0.35 + 0.65 * n) * scorch;
	c += vec3(0.95, 0.42, 0.12) * ember * 0.6;
	c *= 0.92 + 0.08 * vn(local / 2.2);
	COLOR = vec4(c, COLOR.a * a);
}
"""

static var _shader: Shader = null
static var _rough: Shader = null

static func _rough_material(sz: Vector2) -> ShaderMaterial:
	if _rough == null:
		_rough = Shader.new()
		_rough.code = ROUGH
	var m := ShaderMaterial.new()
	m.shader = _rough
	m.set_shader_parameter("box_size", sz)
	m.set_shader_parameter("seed", randf() * 10.0)
	return m

## Gothic only: gives a panel, card or button the burnt, rough edge (it follows the control's size as it changes).
## Every other theme is left as it is.
static func rough(c: Control, scorch := 1.0) -> void:
	if preload("res://themes.gd").id() != "gothic":
		return
	var m := _rough_material(c.size)
	m.set_shader_parameter("scorch", scorch)
	c.material = m
	c.resized.connect(func() -> void: m.set_shader_parameter("box_size", c.size))

## Gothic: a selection frame (a border only) gets a lightly ragged edge, without char, so it still reads as a highlight.
static func rough_frame(c: CanvasItem, sz: Vector2) -> void:
	if preload("res://themes.gd").id() != "gothic":
		return
	var m := _rough_material(sz)
	m.set_shader_parameter("burn", 0.3)
	m.set_shader_parameter("scorch", 0.0)
	c.material = m

## Rounds the corners of a control that fills a tile of the given size.
static func apply(c: CanvasItem, tile_size: Vector2, radius: float) -> void:
	if preload("res://themes.gd").id() == "gothic":
		c.material = _rough_material(tile_size)
		return
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("box_size", tile_size)
	m.set_shader_parameter("radius", maxf(float(preload("res://themes.gd").r(radius)), 0.5))  # Gun metal: sharp
	c.material = m
