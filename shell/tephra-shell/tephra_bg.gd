extends Control
## Tephra's own animated background for the Home tile: the navy gradient from
## the boot logo, faint shards drifting and turning, and fine "ash" rising slowly.

var TOP: Color = Themes.c("bg_top")
var BOTTOM: Color = Themes.c("bg_bottom")
const SHARD := [Vector2(0, -1), Vector2(0.54, -0.58), Vector2(0.42, 0.62), Vector2(-0.08, 0.92), Vector2(-0.54, 0.46), Vector2(-0.5, -0.42)]
const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")
const Visuals = preload("res://visuals.gd")
const SHARD_COUNT := 14
const ASH_COUNT := 70

# Draws the navy gradient per pixel with a tiny bit of grain (dithering),
# so the dark blues fade smoothly instead of showing blocky steps.
# The whole backdrop (gradient, the two drifting lights, the sweeping sheen) is worked out
# per pixel IN THE SHADER with a little noise added before the colour is rounded to 8 bits.
# Soft glows drawn as separate semi-transparent layers each get rounded on their own, which
# is what made visible colour bands; doing it in one place with dithering hides them.
const GRADIENT_SHADER := """
shader_type canvas_item;
uniform vec4 top_color : source_color;
uniform vec4 bottom_color : source_color;
uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform vec2 l1 = vec2(500.0, 400.0);
uniform vec2 l2 = vec2(1400.0, 600.0);
uniform float sheen_x = -500.0;
uniform vec4 glow1 : source_color = vec4(0.30, 0.42, 0.75, 1.0);
uniform vec4 glow2 : source_color = vec4(0.55, 0.40, 0.75, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.8, 0.88, 1.0, 1.0);
uniform float glow_k = 1.0;
uniform float stripes = 0.0;
uniform float brushed = 0.0;   // gun metal: fine brushed grain, a hard band of light, dark corners
uniform float vig = 0.0;
uniform float grime = 0.0;
uniform float metal = 0.0;     // Sleek: polished steel, a fine brushed grain and a soft light sliding across it
uniform float burnt = 0.0;     // Gothic: the corners of the picture charred like old paper, an ember line along the edge
uniform float scan = 0.0;      // Neon Coast: dark scanlines and a soft tube-like curve of light     // gun metal: oily stains, dirt gathered low down, pits and fine scratches
float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 px = UV * rect_size;
	vec3 c = mix(top_color.rgb, bottom_color.rgb, UV.y);
	c = mix(c, glow1.rgb, smoothstep(0.0, 1.0, 1.0 - length(px - l1) / 520.0) * 0.16 * glow_k);
	c = mix(c, glow2.rgb, smoothstep(0.0, 1.0, 1.0 - length(px - l2) / 440.0) * 0.10 * glow_k);
	float u = px.x + 260.0 * px.y / rect_size.y;
	c = mix(c, sheen_color.rgb, smoothstep(0.0, 1.0, 1.0 - abs(u - sheen_x) / 220.0) * 0.045);
	// Channels theme: fine light lines across the screen, like brushed glossy plastic.
	c = mix(c, vec3(1.0), stripes * step(mod(px.y, 7.0), 2.0));
	if (metal > 0.0) {
		float g = vn(vec2(px.x / 700.0, px.y * 1.1)) - 0.5;                    // long brushed streaks, side to side
		float g2 = ign(vec2(floor(px.x / 48.0), floor(px.y))) - 0.5;
		float sx = px.x - sheen_x * 1.2 + px.y * 0.35;
		c += metal * (g * 0.03 + g2 * 0.01);
		c += metal * (0.09 * exp(-pow(sx / 420.0, 2.0)) + 0.05 * exp(-pow(sx / 70.0, 2.0)));  // the light on the steel
		c *= 1.0 - metal * 0.09 * smoothstep(0.5, 0.72, UV.y) * (1.0 - smoothstep(0.72, 0.98, UV.y)); // a dark reflected band
	}
	if (brushed > 0.0) {
		float row = ign(vec2(7.0, floor(px.y)));
		float grain = (row - 0.5) * 0.07 + (ign(vec2(floor(px.x * 0.25), floor(px.y * 0.5))) - 0.5) * 0.025;
		float band = smoothstep(0.0, 1.0, 1.0 - abs(u - sheen_x * 1.6 - 300.0) / 120.0);
		c += brushed * (grain * (0.35 + c.r * 3.0) + band * 0.10);
	}
	if (grime > 0.0) {
		float g = vn(px / 260.0) * 0.55 + vn(px / 90.0) * 0.3 + vn(px / 23.0) * 0.15;
		float stain = smoothstep(0.48, 0.85, g);
		c *= 1.0 - grime * stain * 0.5;
		c *= 1.0 - grime * 0.4 * smoothstep(0.5, 1.0, UV.y) * vn(px / 55.0);
		c *= 1.0 - grime * step(0.986, h21(floor(px / 2.0))) * 0.4;
		vec2 q = vec2(px.x * 0.94 + px.y * 0.34, px.y * 0.94 - px.x * 0.34);
		float lane = floor(q.y / 3.0);
		c += grime * step(0.993, h21(vec2(lane, 3.0))) * step(0.62, vn(vec2(q.x / 140.0, lane))) * 0.04;
	}
	if (scan > 0.0) {
		c *= 1.0 - scan * 0.22 * step(2.0, mod(FRAGCOORD.y, 4.0));
		c *= 1.0 - scan * 0.035 * step(0.5, fract(FRAGCOORD.x / 3.0)) ;
	}
	c *= 1.0 - vig * pow(clamp(length((UV - 0.5) * vec2(1.25, 1.0)) * 1.35, 0.0, 1.0), 2.4);
	if (burnt > 0.0) {
		vec2 cq = min(UV, 1.0 - UV) * rect_size;               // distance to the nearest left/right and top/bottom edge
		float cd = length(max(vec2(260.0) - cq, vec2(0.0)));   // how deep into a corner this pixel is
		float edge = min(cq.x, cq.y);
		float nb = vn(px / 38.0) * 0.6 + vn(px / 11.0) * 0.4;
		float burn_line = cd * 0.55 - 60.0 + (20.0 - edge) * 0.6 - nb * 70.0;   // > 0: burnt away; only reaches into the corners
		float charred = smoothstep(-70.0, 0.0, burn_line);
		c = mix(c, vec3(0.03, 0.02, 0.015), charred * burnt);
		c += vec3(0.95, 0.45, 0.12) * (1.0 - smoothstep(0.0, 7.0, abs(burn_line + 4.0))) * 0.35 * burnt;
		c *= 1.0 - burnt * step(0.0, burn_line) * 0.85;
	}
	float n = ign(FRAGCOORD.xy) + ign(FRAGCOORD.xy + vec2(47.0, 17.0)) - 1.0;  // triangular noise
	COLOR = vec4(c + n / 255.0, 1.0);
}
"""
var _style: String = Themes.backdrop()   # "shards", "embers", "lines", "glass", "aero" or "cubes" (see themes.gd)
var _lit: bool = Themes.light()   # read once, so a preview of another theme (setup.gd) keeps its own look
var _shard_col: Color = Themes.c("shard")
var _ash_col: Color = Themes.c("ash")
var _shards: Array = []
var _ash: Array = []
var _t := 0.0
var _drawn_still := false
var _glow_tex: GradientTexture2D
var _mat: ShaderMaterial
var _rain: Array = []   # gun metal: drops in three depths
var _city_layer: Control
var _rain_layer: Control
var _city_acc := 0.0

func _layer(fn: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(func() -> void:
		_canvas = c
		fn.call()
		_canvas = self)
	return c
var _water_layer: Control
var _castle = null            # Gothic: castle_art.gd
var _castle_layer: Control
var _mold = null              # Mold: mold_art.gd
var _mold_layer: Control
var plain := false             # a full page (Library, Settings...) sits on it: no windows on the Temple desktop
var _temple = null            # Temple: temple_art.gd
var _cosmos = null            # Planet: cosmos_art.gd
var _pcb = null               # Circuit: pcb_art.gd
var _wood = null              # Wood: wood_art.gd
var _wood_sky: Control
var _wood_fx: Control
var _wood_acc := 0.0
var _wood_sky_acc := 0.0
var _scene = null              # Castle: castle_scene.gd
var _light_layer: Control
var _snow_layer: Control
var _fish_layer: Control
var _water_acc := 0.0
var _fish_acc := 0.0
var _canvas: CanvasItem = self  # where the gun metal city and rain draw (their own layers)
var _fish: Array = []  # Frutiger: fish pictures (drawn from SVG, so they stay sharp)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = GRADIENT_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("top_color", TOP)
	mat.set_shader_parameter("bottom_color", BOTTOM)
	mat.set_shader_parameter("glow1", Themes.c("glow1"))
	mat.set_shader_parameter("glow2", Themes.c("glow2"))
	mat.set_shader_parameter("sheen_color", Themes.c("sheen"))
	# Light themes need a stronger glow to show at all; embers glow the most.
	mat.set_shader_parameter("glow_k", {"embers": 1.8, "lines": 1.4, "glass": 1.3, "aero": 1.5, "cubes": 0.12, "rain": 1.3}.get(_style, 1.6 if Themes.light() else 1.0))
	mat.set_shader_parameter("brushed", 1.0 if _style == "rain" else 0.0)
	mat.set_shader_parameter("vig", 0.75 if _style == "rain" else 0.0)
	mat.set_shader_parameter("grime", 1.0 if _style == "rain" else 0.0)
	mat.set_shader_parameter("scan", 1.0 if _style == "palms" else 0.0)
	if _style == "palms":
		mat.set_shader_parameter("vig", 0.55)
	if _style == "basement" or _style == "forest" or _style == "kingdom" or _style == "temple" or _style == "cosmos" or _style == "pcb":
		mat.set_shader_parameter("glow_k", 0.0)
	if _style == "castle":
		mat.set_shader_parameter("vig", 0.75)
		mat.set_shader_parameter("burnt", 1.0)
		mat.set_shader_parameter("glow_k", 0.0)
	mat.set_shader_parameter("stripes", {"lines": 0.35}.get(_style, 0.0))
	mat.set_shader_parameter("metal", 1.0 if _style == "glass" else 0.0)
	_mat = mat
	var grad := ColorRect.new()
	grad.material = mat
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grad.show_behind_parent = true  # under the shards and ash drawn below
	add_child(grad)
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Soft round glow, reused for the drifting lights.
	var gg := Gradient.new()
	gg.offsets = PackedFloat32Array([0.0, 1.0])
	gg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = gg
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 256
	_glow_tex.height = 256
	if _style == "aero":
		for v in FISH:
			_fish.append(_fish_parts(v[0], v[1], v[2], v[3]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # same layout every boot
	for i in SHARD_COUNT:
		# One rock per cell of a 5x3 grid (14 of 15), jittered, so they spread over the whole
		# screen, including the empty space above the games.
		var cell := Vector2(i % 5, i / 5)
		_shards.append({
			"pos": (cell + Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9))) / Vector2(5, 3), "size": rng.randf_range(80, 230),
			"rot": rng.randf() * TAU, "spin": rng.randf_range(-0.05, 0.05),
			"drift": Vector2(rng.randf_range(-0.004, 0.004), rng.randf_range(-0.006, -0.002)),
			"alpha": rng.randf_range(0.07, 0.13)})
	if _style == "rain":
		for i in 340:
			var d := rng.randf()
			_rain.append({"x": rng.randf() * 1.2, "y": rng.randf(), "d": d * d, "k": rng.randf()})
		_make_city(rng)
		# The city and the rain are drawn on two plain layers over the background. The background's shader (brushed
		# metal, grime) used to run again under every raindrop and every window, every frame: that is what cost the
		# frame rate. Now the shader redraws slowly like the other themes, the city 4 times a second, and only the
		# rain (one batched draw) every frame.
		_cloud_layer = _layer(func() -> void: _draw_rain_clouds(size))  # under the city: heavy clouds sliding across the sky
		_city_layer = _layer(func() -> void: _draw_city(size, size.y * 0.88))
		_rain_layer = _layer(func() -> void: _draw_rain(size))
	if _style == "castle":
		# Gothic: the castle and its land are drawn once on their own layer (again only when the window changes size),
		# the snow, bats, mist and candles on another every frame; the moon and clouds go with the slow background.
		_castle = preload("res://castle_art.gd").new()
		_castle.make()
		_castle_layer = _layer(func() -> void: _castle.draw_still(_canvas, size))
		_castle_layer.resized.connect(_castle_layer.queue_redraw)
		_snow_layer = _layer(func() -> void: _castle.draw_moving(_canvas, size, _t, _glow_tex))
	if _style == "basement":
		# Mold: the corridor is drawn once on its own layer (again only when the window changes size); the drips,
		# the figure and the dark round the beam on another every frame, and the beam's light on a third that adds.
		_mold = preload("res://mold_art.gd").new()
		_mold.make()
		_mold_layer = _layer(func() -> void: _mold.draw_still(_canvas, size))
		_mold_layer.resized.connect(_mold_layer.queue_redraw)
		_snow_layer = _layer(func() -> void: _mold.draw_moving(_canvas, size, _t, _glow_tex))
		_light_layer = _layer(func() -> void: _mold.draw_light(_canvas, size, _t, _glow_tex))
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_light_layer.material = add
	if _style == "forest":
		# Wood: the trees and ground are drawn once on their own layer; the light, leaves, pollen, butterflies and grass
		# move on another.
		_wood = preload("res://wood_art.gd").new()
		_wood.make()
		_wood_sky = _layer(func() -> void: _wood.draw_sky(_canvas, size, _t, _glow_tex))
		_castle_layer = _layer(func() -> void: _wood.draw_still(_canvas, size))
		_castle_layer.resized.connect(_castle_layer.queue_redraw)
		_snow_layer = _layer(func() -> void: _wood.draw_moving(_canvas, size, _t, _glow_tex))
		if _wood.night:
			# By moonlight: the trees, hills and grass are the day picture dimmed to a cool blue.
			_castle_layer.modulate = Color(0.26, 0.34, 0.6)
			_snow_layer.modulate = Color(0.3, 0.38, 0.62)
			_wood_fx = _layer(func() -> void: _wood.draw_fx(_canvas, size, _t, _glow_tex))
	if _style == "kingdom":
		_scene = preload("res://castle_scene.gd").new()
		_scene.make()
	if _style == "temple":
		_temple = preload("res://temple_art.gd").new()
		_temple.make()
	if _style == "cosmos":
		_cosmos = preload("res://cosmos_art.gd").new()
		_cosmos.make()
	if _style == "pcb":
		_pcb = preload("res://pcb_art.gd").new()
		_pcb.make()
	if _style == "aero":
		# Same idea for Frutiger: the shader background redraws slowly, the light and water 20 times a second
		# (they drift), and only the fish and grass every frame. Redrawing it all every frame, shader included,
		# is what made it heavy.
		_water_layer = _layer(func() -> void: _draw_water_slow(size))
		_fish_layer = _layer(func() -> void: _draw_water_fast(size))
	if _style == "palms":
		for i in 18:
			_palms.append({"a": TAU * float(i) / 18.0 + rng.randf_range(-0.12, 0.12), "r": rng.randf_range(0.85, 1.25),
				"lean": rng.randf_range(-0.35, 0.35), "h": rng.randf_range(0.85, 1.15), "ph": rng.randf() * TAU})
	for i in ASH_COUNT:
		_ash.append({"pos": Vector2(rng.randf(), rng.randf()), "speed": rng.randf_range(0.004, 0.015),
			"sway": rng.randf() * TAU, "r": rng.randf_range(1.0, 2.6), "alpha": rng.randf_range(0.08, 0.28)})

# Every screen has its own copy of this background. To keep them all in step, nothing
# here is stepped frame by frame per copy: every position is worked out from ONE shared
# clock that all copies read. The clock's speed eases between 0 (still) and 1 (moving), so
# turning the wallpaper still (Settings > Accessibility) slows it to a stop instead of snapping.
static var _clock := 0.0
static var _speed := 1.0
static var _frame := -1
static var _started := false
static var paused := false  # true while a game is running: nothing here may use the GPU

static func _advance(delta: float) -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return  # another copy already moved the clock this frame
	_frame = f
	var moving: bool = bool(Settings.get_value("bg_motion", true)) and bool(Settings.get_value("animations", true)) \
		and not Visuals.saver()
	var target := 1.0 if moving else 0.0
	if not _started:
		_started = true
		_speed = target
	_speed = move_toward(_speed, target, delta / 1.5)
	_clock += delta * _speed

var _acc := 0.0
static var _seen := {}  # instance id -> the last frame it was visible and running (every screen has its own copy)

## How many copies are on screen right now. Frutiger's water is costly, so with Home and the Library both
## up, each copy redraws less often: the total stays what one copy costs.
func _copies() -> int:
	var f := Engine.get_process_frames()
	_seen[get_instance_id()] = f
	var n := 0
	for k in _seen.keys():
		if f - int(_seen[k]) > 3:
			_seen.erase(k)
		else:
			n += 1
	return maxi(n, 1)

func _process(delta: float) -> void:
	if paused or not is_visible_in_tree() or modulate.a <= 0.01:
		return
	_advance(delta)
	_acc += delta
	# The motion is very slow, so 25 redraws a second look identical to 60 and cost far less.
	if _speed > 0.0:
		var every := 0.04
		if _style == "aero":
			_t = _clock
			_fish_acc += delta
			if _fish_acc >= (1.0 / 60.0) * minf(float(_copies()), 3.0):  # the fish need smooth motion
				_fish_acc = 0.0
				_fish_layer.queue_redraw()
			_water_acc += delta
			if _water_acc >= 0.05:
				_water_acc = 0.0
				_water_layer.queue_redraw()
		elif _style == "rain":
			_t = _clock
			if _cloud_layer != null:
				_cloud_layer.queue_redraw()
			_rain_layer.queue_redraw()  # rain falls fast: every frame, or it stutters (it is one cheap draw)
			_city_acc += delta
			if _city_acc >= 0.25:
				_city_acc = 0.0
				_city_layer.queue_redraw()
		elif _style == "basement":
			_t = _clock
			_water_acc += delta
			if _water_acc >= 1.0 / 24.0:  # drips and the beam at 24 steps a second: slow things, a third of the GPU work
				_water_acc = 0.0
				_snow_layer.queue_redraw()
				_light_layer.queue_redraw()
			every = 0.5  # the background behind the corridor is hidden anyway
		elif _style == "castle":
			_t = _clock
			_snow_layer.queue_redraw()  # falling snow: every frame, or it stutters
			every = 0.1  # the moon and clouds barely move
		elif _style == "forest":
			_t = _clock
			# Light on the graphics card: the grass and flowers sway at 30 steps a second, the sky (clouds, birds) at 15.
			_wood_acc += delta
			if _wood_acc >= 1.0 / 30.0:
				_wood_acc = 0.0
				_snow_layer.queue_redraw()
				if _wood_fx != null:
					_wood_fx.queue_redraw()
			_wood_sky_acc += delta
			if _wood_sky_acc >= 1.0 / 15.0:
				_wood_sky_acc = 0.0
				_wood_sky.queue_redraw()
			every = 0.5  # the shader sky behind the trees is hidden anyway
		elif _style == "pcb":
			every = 1.0 / 12.0  # a still board with slowly breathing LEDs
		elif _style == "cosmos":
			every = 1.0 / 30.0  # stars twinkle slowly; a shooting star needs smooth motion
		elif _style == "temple":
			every = 1.0 / 20.0  # a slowly turning cross, and a 16-colour screen: 20 steps a second is plenty
		elif _style == "kingdom":
			every = 1.0 / 30.0
		elif _style == "palms":
			every = 1.0 / 30.0  # pixel art: 30 steps a second is the look, and half the cost
		if _acc >= every:
			_acc = 0.0
			_t = _clock
			queue_redraw()
			_drawn_still = false
	elif not _drawn_still:
		_t = _clock
		queue_redraw()
		_drawn_still = true

func _wrap(p: Vector2) -> Vector2:
	return Vector2(fposmod(p.x + 0.2, 1.4) - 0.2, fposmod(p.y + 0.2, 1.4) - 0.2)

# Frutiger fish: [top colour, middle, belly, fin colour]. Two goldfish, a yellow tang, a blue one.
const FISH := [
	["C8440E", "FF8A1E", "FFD27A", "FF9A3C"],
	["E2580F", "FFA040", "FFE2A0", "FFB060"],
	["D9A400", "FFD21E", "FFF2A0", "FFE45A"],
	["2F5E9A", "5F95D0", "DCEBFA", "8CB8E6"],
]

## A glossy fish, side on, facing right, drawn as THREE pictures so it can swim properly: the body (with its back fin),
## the tail (swung from the joint at the body's rear) and a side fin (fluttered). All three share one 220 x 130 frame.
## Returns [body, tail, side fin].
static func _fish_parts(top: String, mid: String, belly: String, fin: String) -> Array:
	var head := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 220 130" width="660" height="390"><defs>'
	head += '<linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#%s"/><stop offset="0.45" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient>' % [top, mid, belly]
	head += '<linearGradient id="h" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#000" stop-opacity="0.22"/><stop offset="0.35" stop-color="#000" stop-opacity="0"/><stop offset="0.8" stop-color="#fff" stop-opacity="0.10"/></linearGradient>'
	head += '<linearGradient id="t" x1="1" y1="0" x2="0" y2="0"><stop offset="0" stop-color="#%s" stop-opacity="0.95"/><stop offset="0.6" stop-color="#%s" stop-opacity="0.55"/><stop offset="1" stop-color="#%s" stop-opacity="0.18"/></linearGradient>' % [fin, fin, fin]
	head += '<radialGradient id="e" cx="0.38" cy="0.35" r="0.65"><stop offset="0" stop-color="#6a5a3a"/><stop offset="0.45" stop-color="#1a1208"/><stop offset="1" stop-color="#000"/></radialGradient>'
	head += '<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.75"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient></defs>'
	# --- body ---
	var body := head
	body += '<path d="M104,36 C112,12 140,6 160,32 C142,30 122,32 104,36 Z" fill="url(#t)"/>'                       # back fin
	body += '<path d="M120,92 C118,106 130,114 142,108 C136,102 132,96 132,92 Z" fill="url(#t)"/>'                  # belly fin
	body += '<path d="M70,65 C76,40 110,28 148,32 C180,36 204,52 208,66 C204,80 182,94 148,98 C110,102 76,92 70,65 Z" fill="url(#b)"/>'
	body += '<path d="M70,65 C76,40 110,28 148,32 C180,36 204,52 208,66 C204,80 182,94 148,98 C110,102 76,92 70,65 Z" fill="url(#h)"/>'
	for r in 4:      # scales: rows of little arcs, brighter in the middle
		for c in 7:
			var sx := 92 + c * 14 + (r % 2) * 7
			var sy := 48 + r * 10
			body += '<path d="M%d,%d q7,8 14,0" stroke="#ffffff" stroke-opacity="0.20" stroke-width="1.1" fill="none"/>' % [sx, sy]
	body += '<path d="M84,66 C120,60 160,60 200,66" stroke="#000000" stroke-opacity="0.12" stroke-width="1.5" fill="none"/>'  # side line
	body += '<path d="M168,40 Q156,66 168,92" stroke="#000000" stroke-opacity="0.2" stroke-width="2.2" fill="none"/>'        # gill
	body += '<path d="M104,34 C130,30 170,34 196,52" stroke="#ffffff" stroke-opacity="0.55" stroke-width="2" fill="none" stroke-linecap="round"/>'
	body += '<ellipse cx="140" cy="46" rx="48" ry="8" fill="url(#g)"/>'                                                     # gloss along the back
	body += '<ellipse cx="150" cy="86" rx="34" ry="5" fill="#ffffff" fill-opacity="0.16"/>'                                   # soft light on the belly
	body += '<circle cx="188" cy="58" r="9.5" fill="#ffffff"/><circle cx="189.5" cy="58.5" r="6.8" fill="url(#e)"/><circle cx="186.5" cy="55.5" r="2.4" fill="#ffffff"/><circle cx="191" cy="61" r="1.1" fill="#ffffff" fill-opacity="0.8"/>'
	body += '<path d="M205,68 q-5,4 -11,2" stroke="#000000" stroke-opacity="0.35" stroke-width="1.6" fill="none" stroke-linecap="round"/>'
	body += '</svg>'
	# --- tail: a long, ruffled, see-through fan with rays ---
	var tail := head
	tail += '<path d="M80,65 C60,44 36,14 10,12 C20,28 28,40 26,52 C30,58 30,72 26,78 C28,90 20,102 10,118 C36,116 60,86 80,65 Z" fill="url(#t)"/>'
	for k in 7:
		var yy := 16 + k * 16
		tail += '<path d="M78,65 Q44,%d 14,%d" stroke="#ffffff" stroke-opacity="0.30" stroke-width="1.1" fill="none"/>' % [65 + (yy - 65) / 2, yy]
	tail += '<path d="M10,12 C20,28 28,40 26,52 C30,58 30,72 26,78 C28,90 20,102 10,118" stroke="#ffffff" stroke-opacity="0.35" stroke-width="1.4" fill="none"/>'
	tail += '</svg>'
	# --- side fin ---
	var sidefin := head
	sidefin += '<path d="M150,70 C164,72 176,82 174,92 C166,92 154,86 150,70 Z" fill="url(#t)"/><path d="M152,72 Q164,78 172,90" stroke="#ffffff" stroke-opacity="0.35" stroke-width="1" fill="none"/>'
	sidefin += '</svg>'
	var out: Array = []
	for svg in [body, tail, sidefin]:
		var img := Image.new()
		img.load_svg_from_string(svg, 1.0)
		img.generate_mipmaps()
		out.append(ImageTexture.create_from_image(img))
	return out

static func _h(i: int, s: float) -> float:
	return fposmod(sin(i * 12.9898 + s * 78.233) * 43758.5453, 1.0)

## Frutiger: a pool of clear water filling the lower part of the screen (a rippling surface, slow patches of
## light on the water, a few fish swimming by) and green grass swaying along the bottom.
func _draw_water_slow(sz: Vector2) -> void:
	var sy := sz.y * 0.30
	# shafts of sunlight from the top left
	for k in 4:
		var rx := sz.x * (0.05 + 0.2 * k) + 10.0 * sin(_t * 0.2 + k)
		var rp := PackedVector2Array([Vector2(rx, 0), Vector2(rx + 120.0 + 40.0 * k, 0), Vector2(rx + sz.x * 0.35 + 120.0, sz.y), Vector2(rx + sz.x * 0.35 - 80.0, sz.y)])
		_canvas.draw_colored_polygon(rp, Color(1, 1, 1, 0.045 + 0.012 * sin(_t * 0.5 + k * 1.7)))
	# clouds in the sky above the water: soft white puffs drifting slowly to the right
	for k in 5:
		var cx := fposmod(_h(k, 21.0) * (sz.x + 700.0) + _t * (5.0 + 4.0 * _h(k, 22.0)), sz.x + 700.0) - 350.0
		var cy := sz.y * (0.06 + 0.16 * _h(k, 23.0))
		var cw := 220.0 + 200.0 * _h(k, 24.0)
		for j in 7:
			var u := float(j) / 6.0
			var px := cx + (u - 0.5) * cw
			var r := cw * (0.22 + 0.16 * sin(u * PI)) * (0.85 + 0.3 * _h(k * 7 + j, 25.0))
			var py := cy - sin(u * PI) * cw * 0.12
			_canvas.draw_texture_rect(_glow_tex, Rect2(px - r, py - r * 0.75, r * 2.0, r * 1.5), false, Color(1, 1, 1, 0.55))
			_canvas.draw_texture_rect(_glow_tex, Rect2(px - r * 0.6, py - r * 0.55, r * 1.2, r * 0.9), false, Color(1, 1, 1, 0.5))
	# the water: a deeper blue body under the surface
	for k in 12:
		var y0 := sy + (sz.y - sy) * k / 12.0
		_canvas.draw_rect(Rect2(0, y0, sz.x, (sz.y - sy) / 12.0 + 1.0), Color(0.05, 0.35, 0.75, 0.05 + 0.012 * k))
	# the surface: two slow ripple lines, white and light blue
	for L in 2:
		var pts := PackedVector2Array()
		for i in 49:
			var x := sz.x * i / 48.0
			pts.append(Vector2(x, sy + 9.0 * sin(x * 0.006 + _t * (0.8 + 0.3 * L) + L * 2.0) + 4.0 * sin(x * 0.017 - _t * 1.1)))
		_canvas.draw_polyline(pts, Color(1, 1, 1, 0.7 - 0.3 * L), 3.0 - L, true)
		if L == 0:
			var below := pts.duplicate()
			for i in range(below.size() - 1, -1, -1):
				below.append(Vector2(pts[i].x, pts[i].y + 22.0))
			_canvas.draw_colored_polygon(PackedVector2Array(pts) + PackedVector2Array([Vector2(sz.x, sy + 26.0), Vector2(0, sy + 26.0)]), Color(1, 1, 1, 0.16))
	# light on the water: soft wavering bands that drift
	for k in 9:
		var cx := fposmod(_h(k, 1.0) * sz.x + _t * (6.0 + 5.0 * _h(k, 2.0)), sz.x + 400.0) - 200.0
		var cy := sy + 60.0 + _h(k, 3.0) * (sz.y - sy) * 0.6
		var w := 140.0 + 160.0 * _h(k, 4.0)
		var pts2 := PackedVector2Array()
		for i in 13:
			var u := float(i) / 12.0
			pts2.append(Vector2(cx + (u - 0.5) * w * 2.0, cy + 7.0 * sin(u * TAU + _t * 0.9 + k)))
		_canvas.draw_polyline(pts2, Color(1, 1, 1, 0.10 + 0.05 * sin(_t * 0.6 + k)), 3.0, true)
## Frutiger, the moving part: fish and grass (redrawn smoothly, on their own layer).
func _draw_water_fast(sz: Vector2) -> void:
	var sy := sz.y * 0.30
	# fish: they swim in lively, wandering paths: speeding up and slowing, drifting up and down, pitching their nose
	# to follow the path, swinging the tail (faster when they swim faster), fluttering a side fin, and blowing bubbles.
	for k in 6:
		if _fish.is_empty():
			break
		var parts: Array = _fish[k % _fish.size()]
		var dir := 1.0 if k % 2 == 0 else -1.0
		var speed := 34.0 + 26.0 * _h(k, 5.0)
		var span := sz.x + 500.0
		var surge := sin(_t * (0.5 + 0.2 * _h(k, 14.0)) + k * 2.1)          # -1 to 1: slow down, speed up
		var run := _t * speed + 55.0 * surge
		var x := fposmod(_h(k, 6.0) * span + dir * run, span) - 250.0
		var ybase := sy + 130.0 + _h(k, 7.0) * (sz.y - sy) * 0.45
		var y := ybase + 34.0 * sin(_t * 0.45 + k * 1.9) + 12.0 * sin(_t * 1.15 + k * 0.7)
		var dydt := 34.0 * 0.45 * cos(_t * 0.45 + k * 1.9) + 12.0 * 1.15 * cos(_t * 1.15 + k * 0.7)
		var dxdt := dir * (speed + 55.0 * (0.5 + 0.2 * _h(k, 14.0)) * cos(_t * (0.5 + 0.2 * _h(k, 14.0)) + k * 2.1))
		var pitch := clampf(atan2(dydt, maxf(absf(dxdt), 8.0)) * 0.9, -0.5, 0.5)
		var s := 0.42 + 0.3 * _h(k, 8.0)
		var fs: Vector2 = (parts[0] as Texture2D).get_size() / 3.0 * s * 2.0   # textures are drawn at 3x for sharpness
		var effort := 0.6 + 0.5 * (0.5 + 0.5 * surge)
		var wag := sin(_t * (4.2 + 2.6 * effort) + k * 1.3)
		var base := Transform2D(0.0, Vector2(x, y)) * Transform2D(pitch * dir, Vector2.ZERO) * Transform2D(Vector2(dir * (1.0 + 0.018 * wag), 0.0), Vector2(0.0, 1.0 + 0.02 * sin(_t * 2.0 + k)), Vector2.ZERO)
		var joint := Vector2(76.0 / 220.0 * fs.x - fs.x / 2.0, 0.0)
		_canvas.draw_set_transform_matrix(base * Transform2D(0.0, joint) * Transform2D(0.38 * wag, Vector2.ZERO) * Transform2D(0.0, -joint))
		_canvas.draw_texture_rect(parts[1], Rect2(-fs / 2.0, fs), false)       # tail
		_canvas.draw_set_transform_matrix(base)
		_canvas.draw_texture_rect(parts[0], Rect2(-fs / 2.0, fs), false)       # body
		var fj := Vector2(150.0 / 220.0 * fs.x - fs.x / 2.0, 70.0 / 130.0 * fs.y - fs.y / 2.0)
		_canvas.draw_set_transform_matrix(base * Transform2D(0.0, fj) * Transform2D(0.25 * sin(_t * 5.0 + k * 0.9), Vector2.ZERO) * Transform2D(0.0, -fj))
		_canvas.draw_texture_rect(parts[2], Rect2(-fs / 2.0, fs), false)       # side fin
		_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# a little string of bubbles from the mouth every few seconds
		var mouth := Vector2(x + dir * fs.x * 0.46, y - 2.0)
		for bi in 3:
			var life := fposmod(_t * 0.28 + _h(k, 30.0) + bi * 0.12, 1.0)
			if life < 0.55:
				var bp := mouth + Vector2(dir * life * 18.0 + 5.0 * sin(life * 14.0 + bi), -life * 150.0)
				var br := (3.0 + 2.5 * _h(bi, 31.0 + k)) * (0.6 + life)
				_canvas.draw_circle(bp, br, Color(1, 1, 1, 0.14 * (1.0 - life * 1.6)))
				_canvas.draw_arc(bp, br, 0.0, TAU, 14, Color(1, 1, 1, 0.65 * (1.0 - life * 1.7)), 1.2)
	# grass along the bottom, in two rows: the back row paler, the front row deeper
	for row in 2:
		var n := 70
		for i in n:
			var bx := (float(i) + _h(i + row * 100, 9.0)) / n * (sz.x + 60.0) - 30.0
			var hgt := (90.0 + 120.0 * _h(i + row * 100, 10.0)) * (1.0 if row == 1 else 0.8)
			var wid := 9.0 + 8.0 * _h(i + row * 100, 11.0)
			var sw := sin(_t * (0.9 + 0.4 * _h(i, 12.0)) + i * 0.7 + row) * 16.0 + sin(_t * 0.4 + i) * 6.0
			var base_y := sz.y + 4.0 + (14.0 if row == 0 else 0.0)
			var g := Color(0.42, 0.82, 0.30) if row == 0 else Color(0.20, 0.62, 0.22)
			g = g.lerp(Color(0.7, 0.92, 0.35), _h(i + row * 100, 13.0) * 0.4)
			var mid := Vector2(bx + sw * 0.4, base_y - hgt * 0.5)
			var tip := Vector2(bx + sw, base_y - hgt)
			_canvas.draw_colored_polygon(PackedVector2Array([Vector2(bx - wid, base_y), Vector2(mid.x - wid * 0.55, mid.y), tip, Vector2(mid.x + wid * 0.55, mid.y), Vector2(bx + wid, base_y)]), Color(g, 0.95))
			_canvas.draw_line(Vector2(bx, base_y), tip, Color(1, 1, 1, 0.22), 1.5)

## Gun metal city: three rows of buildings against the rain-lit sky. The far row is tall and pale, lost in the rain;
## the middle row is darker with its windows in grids; the near row is almost black but caught by a cold edge of light,
## with fire escapes, water towers, cornices and street lamps. Made once (same skyline every boot).
var _city: Array = []   # [far, mid, near]; each block {x, w, h, cols, rows, lit: [[col, row, warm?]], wins, extras...}
var _cloud_layer: Control
var _cars: Array = []   # parked old cars on the wet street: {x, len, col, flip}

func _make_city(rng: RandomNumberGenerator) -> void:
	_city.clear()
	for layer in 3:
		var blocks: Array = []
		var x := -0.03
		while x < 1.03:
			var w: float = [rng.randf_range(0.04, 0.08), rng.randf_range(0.05, 0.10), rng.randf_range(0.07, 0.14)][layer]
			var h: float = [rng.randf_range(0.30, 0.58), rng.randf_range(0.20, 0.40), rng.randf_range(0.10, 0.26)][layer]
			var cols := maxi(2, int(w * 1920.0 / [16.0, 20.0, 26.0][layer]))
			var rows := maxi(2, int(h * 1080.0 / [18.0, 22.0, 28.0][layer]))
			var lit: Array = []
			var wins: Array = []
			var chance: float = [0.16, 0.2, 0.24][layer]
			for r in rows:
				for c in cols:
					if rng.randf() < chance:
						var warm := rng.randf() < 0.45
						lit.append([c, r, warm])
						wins.append(Vector2((c + 0.5) / cols, (r + 0.5) / rows))
			blocks.append({"x": x, "w": w, "h": h, "cols": cols, "rows": rows, "lit": lit, "wins": wins,
				"mast": rng.randf() < 0.25, "tank": layer > 0 and rng.randf() < 0.3, "step": rng.randf() < 0.35,
				"escape": layer == 2 and rng.randf() < 0.55, "flick": rng.randf() * 10.0})
			x += w + rng.randf_range(0.0, 0.01)
		_city.append(blocks)
	_cars.clear()
	for c in [[0.05, 0.105, Color(0.21, 0.22, 0.24), false], [0.47, 0.12, Color(0.27, 0.15, 0.12), true], [0.78, 0.098, Color(0.15, 0.20, 0.18), false]]:
		_cars.append({"x": c[0], "len": c[1], "col": c[2], "flip": c[3]})

## Low, heavy storm clouds: wide dark-grey soft banks sliding slowly to the right at different speeds.
func _draw_rain_clouds(sz: Vector2) -> void:
	for i in 7:
		var w := sz.x * (0.5 + 0.35 * _h(i, 41.0))
		var h := sz.y * (0.16 + 0.1 * _h(i, 42.0))
		var x := fposmod(_h(i, 43.0) * (sz.x + w) + _t * (4.0 + 5.0 * _h(i, 44.0)), sz.x + w * 2.0) - w
		var y := sz.y * (0.02 + 0.3 * _h(i, 45.0))
		var shade := 0.10 + 0.08 * _h(i, 46.0)
		_canvas.draw_texture_rect(_glow_tex, Rect2(x, y, w, h), false, Color(shade, shade + 0.01, shade + 0.025, 0.55))
		_canvas.draw_texture_rect(_glow_tex, Rect2(x + w * 0.2, y + h * 0.35, w * 0.55, h * 0.5), false, Color(0.02, 0.022, 0.026, 0.4))

func _draw_city(sz: Vector2, floor_y: float) -> void:
	var cv := _canvas
	var k := sz.y / 1080.0
	for layer in 3:
		var shade: Color = [Color(0.17, 0.18, 0.20, 0.9), Color(0.095, 0.10, 0.11, 0.96), Color(0.04, 0.042, 0.047, 1.0)][layer]
		var glass: Color = [Color(0.2, 0.21, 0.235, 0.9), Color(0.115, 0.12, 0.135), Color(0.06, 0.063, 0.07)][layer]
		var rim := Color(0.62, 0.68, 0.76, [0.10, 0.16, 0.26][layer])
		var haze: float = [0.55, 0.8, 1.0][layer]
		var drift := 5.0 * sin(_t * 0.03) * (1.0 + layer)  # a touch of depth as the rain moves
		for b in _city[layer]:
			var bx := float(b["x"]) * sz.x + drift
			var bw := float(b["w"]) * sz.x
			var bh := float(b["h"]) * sz.y
			var top := floor_y - bh
			# the body, a little lighter at the top where the sky glow catches it
			var top_col := shade.lightened(0.08 if layer < 2 else 0.04)
			cv.draw_polygon(PackedVector2Array([Vector2(bx, top), Vector2(bx + bw, top), Vector2(bx + bw, floor_y), Vector2(bx, floor_y)]),
				PackedColorArray([top_col, top_col, shade, shade]))
			if b["step"]:
				cv.draw_rect(Rect2(bx + bw * 0.18, top - 22.0 * k * (1 + layer), bw * 0.64, 22.0 * k * (1 + layer)), shade)
				cv.draw_line(Vector2(bx + bw * 0.18, top - 22.0 * k * (1 + layer)), Vector2(bx + bw * 0.82, top - 22.0 * k * (1 + layer)), rim, 1.0)
			# cornice and the cold edge of light down one side
			cv.draw_rect(Rect2(bx - 2.0, top, bw + 4.0, 4.0 * k * (1 + layer)), shade.lightened(0.05))
			cv.draw_line(Vector2(bx, top), Vector2(bx + bw, top), rim, 1.5)
			cv.draw_line(Vector2(bx + bw - 1.0, top), Vector2(bx + bw - 1.0, floor_y), Color(rim, rim.a * 0.6), 1.0)
			# rooftop and wall details: ledges, a vent box, a pipe down the side, and an aerial with a blinking red light
			if layer > 0:
				var hk := _h(int(float(b["x"]) * 1000.0), 3.0 + layer)
				for ledge in range(1, 5):
					var ly := top + bh * float(ledge) * 0.2
					cv.draw_line(Vector2(bx, ly), Vector2(bx + bw, ly), Color(rim, rim.a * 0.35), 1.0)
				if hk > 0.4:
					cv.draw_rect(Rect2(bx + bw * 0.62, top - 9.0 * k * (1 + layer), bw * 0.2, 9.0 * k * (1 + layer)), shade.lightened(0.03))
					cv.draw_rect(Rect2(bx + bw * 0.66, top - 13.0 * k * (1 + layer), bw * 0.04, 4.0 * k * (1 + layer)), shade.darkened(0.2))
				if hk > 0.55:
					cv.draw_line(Vector2(bx + bw * 0.88, top - 4.0 * k), Vector2(bx + bw * 0.88, top - (34.0 + 26.0 * hk) * k * (0.6 + 0.4 * layer)), Color(rim, 0.55), 1.5)
					var blink := 0.5 + 0.5 * sin(_t * 2.2 + hk * 20.0)
					cv.draw_circle(Vector2(bx + bw * 0.88, top - (34.0 + 26.0 * hk) * k * (0.6 + 0.4 * layer)), 2.5 * k, Color(1.0, 0.15, 0.1, 0.25 + 0.7 * blink))
				if layer == 2 and hk > 0.2:
					cv.draw_line(Vector2(bx + 6.0, top + 6.0), Vector2(bx + 6.0, floor_y), Color(0.0, 0.0, 0.0, 0.5), 3.0 * k)
					cv.draw_line(Vector2(bx + 6.0 + 2.0 * k, top + 6.0), Vector2(bx + 6.0 + 2.0 * k, floor_y), Color(rim, 0.18), 1.0)
			# window grid: dark glass everywhere, some lit (warm lamps or cold screens)
			var cols: int = b["cols"]
			var rows: int = b["rows"]
			var cw := bw / cols
			var rh := (bh - 10.0 * k) / rows
			var ww := cw * 0.5
			var wh := rh * 0.55
			if layer > 0:
				for r in rows:
					for c in cols:
						cv.draw_rect(Rect2(bx + c * cw + (cw - ww) * 0.5, top + 10.0 * k + r * rh, ww, wh), glass)
			for l in b["lit"]:
				var on := fposmod(float(b["flick"]) * 3.0 + float(l[0]) * 0.37 + float(l[1]) * 0.71 + _t * 0.002, 1.0) > 0.08
				if on:
					var lc := Color(1.0, 0.82, 0.55) if l[2] else Color(0.72, 0.8, 0.9)
					cv.draw_rect(Rect2(bx + float(l[0]) * cw + (cw - ww) * 0.5, top + 10.0 * k + float(l[1]) * rh, ww, wh), Color(lc, 0.22 + 0.3 * haze))
			if b["mast"]:
				cv.draw_line(Vector2(bx + bw * 0.7, top), Vector2(bx + bw * 0.7, top - 56.0 * k), shade, 2.0)
				cv.draw_line(Vector2(bx + bw * 0.62, top - 30.0 * k), Vector2(bx + bw * 0.78, top - 30.0 * k), shade, 1.5)
				if fposmod(_t + float(b["flick"]), 2.4) < 1.1:
					cv.draw_rect(Rect2(bx + bw * 0.7 - 2.0, top - 58.0 * k, 4.0, 4.0), Color(0.9, 0.12, 0.1, 0.65))  # the warning light
			if b["tank"]:
				# a wooden water tower on legs
				var tx := bx + bw * 0.3
				var tw := 26.0 * k * (0.7 + 0.3 * layer)
				var th := 30.0 * k * (0.7 + 0.3 * layer)
				for lx in [0.1, 0.9]:
					cv.draw_line(Vector2(tx + tw * lx, top), Vector2(tx + tw * lx, top - th * 0.5), shade, 2.0)
				cv.draw_rect(Rect2(tx, top - th * 1.4, tw, th * 0.9), shade)
				cv.draw_colored_polygon(PackedVector2Array([Vector2(tx - 2.0, top - th * 1.4), Vector2(tx + tw * 0.5, top - th * 1.85), Vector2(tx + tw + 2.0, top - th * 1.4)]), shade)
				cv.draw_line(Vector2(tx + tw, top - th * 1.4), Vector2(tx + tw, top - th * 0.5), rim, 1.0)
			if b["escape"]:
				# a fire escape zig-zagging down the face: landings with rails and the stairs between them
				var ex := bx + bw * 0.12
				var ew := bw * 0.5
				var col := Color(0.0, 0.0, 0.0, 0.85)
				var y := top + 26.0 * k
				var left := true
				while y < floor_y - 60.0 * k:
					cv.draw_line(Vector2(ex, y), Vector2(ex + ew, y), col, 3.0)
					cv.draw_line(Vector2(ex, y - 12.0 * k), Vector2(ex + ew, y - 12.0 * k), col, 1.0)
					for rx in 6:
						cv.draw_line(Vector2(ex + ew * rx / 5.0, y), Vector2(ex + ew * rx / 5.0, y - 12.0 * k), col, 1.0)
					var ny := y + 48.0 * k
					cv.draw_line(Vector2(ex + (ew * 0.15 if left else ew * 0.85), y), Vector2(ex + (ew * 0.85 if left else ew * 0.15), ny), col, 2.0)
					cv.draw_line(Vector2(ex, y), Vector2(ex + ew, y), Color(rim, 0.2), 1.0)
					left = not left
					y = ny
		# rain haze between the rows, thickest at street level
		cv.draw_rect(Rect2(0, floor_y - sz.y * 0.16, sz.x, sz.y * 0.16), Color(0.5, 0.53, 0.58, 0.03))
	# street lamps along the kerb, each with a cone of light in the rain
	for lx in [0.2, 0.62, 0.93]:
		var px := float(lx) * sz.x
		var lamp_top := floor_y - 150.0 * k
		cv.draw_line(Vector2(px, floor_y), Vector2(px, lamp_top), Color(0.02, 0.02, 0.025), 4.0 * k)
		cv.draw_line(Vector2(px, lamp_top), Vector2(px + 26.0 * k, lamp_top + 6.0 * k), Color(0.02, 0.02, 0.025), 3.0 * k)
		var lc := Vector2(px + 28.0 * k, lamp_top + 10.0 * k)
		cv.draw_colored_polygon(PackedVector2Array([lc + Vector2(-5, 0) * k, lc + Vector2(5, 0) * k, lc + Vector2(60, 140) * k, lc + Vector2(-60, 140) * k]), Color(1.0, 0.86, 0.62, 0.05))
		cv.draw_texture_rect(_glow_tex, Rect2(lc - Vector2(40, 40) * k, Vector2(80, 80) * k), false, Color(1.0, 0.85, 0.6, 0.35))
		cv.draw_circle(lc, 3.5 * k, Color(1.0, 0.92, 0.75, 0.9))

## One old car seen from the side, long and boxy (an original late-70s sedan shape): body, the glass house, chrome
## bumpers and trim, wheels, lights, and its shimmer in the wet street. `base` is where the tyres meet the road.
const CAR := [Vector2(0.02, -0.12), Vector2(0.0, -0.3), Vector2(0.03, -0.44), Vector2(0.24, -0.5), Vector2(0.31, -0.8),
	Vector2(0.67, -0.82), Vector2(0.77, -0.52), Vector2(0.97, -0.47), Vector2(1.0, -0.3), Vector2(0.98, -0.12)]
const CAR_GLASS := [[Vector2(0.34, -0.54), Vector2(0.39, -0.76), Vector2(0.515, -0.77), Vector2(0.515, -0.54)],
	[Vector2(0.535, -0.54), Vector2(0.535, -0.77), Vector2(0.655, -0.76), Vector2(0.735, -0.54)]]

func _draw_car(cv: CanvasItem, x: float, base: float, length: float, col: Color, flip: bool, lights := false) -> void:
	var h := length * 0.3
	var f := func(p: Vector2) -> Vector2:
		return Vector2(x + (1.0 - p.x if flip else p.x) * length, base + p.y * h)
	var body := PackedVector2Array()
	var refl := PackedVector2Array()
	for p in CAR:
		body.append(f.call(p))
		refl.append(f.call(Vector2(p.x, -p.y * 0.7)))
	cv.draw_colored_polygon(refl, Color(col.lightened(0.15), 0.16))  # mirrored in the wet road, squashed and faint
	cv.draw_colored_polygon(body, col)
	cv.draw_polyline(PackedVector2Array([f.call(CAR[3]), f.call(CAR[4]), f.call(CAR[5]), f.call(CAR[6])]), Color(0.7, 0.75, 0.82, 0.3), 1.2, true)  # rain on the roof line
	for g in CAR_GLASS:
		var gp := PackedVector2Array()
		for p in g:
			gp.append(f.call(p))
		cv.draw_colored_polygon(gp, Color(0.16, 0.18, 0.21, 0.95))
		cv.draw_line(gp[1], gp[2], Color(0.75, 0.8, 0.88, 0.35), 1.0)
	cv.draw_line(f.call(Vector2(0.03, -0.38)), f.call(Vector2(0.98, -0.36)), Color(0.8, 0.84, 0.9, 0.35), 1.2)  # chrome trim
	cv.draw_line(f.call(Vector2(-0.01, -0.2)), f.call(Vector2(0.1, -0.2)), Color(0.85, 0.88, 0.92, 0.6), 2.5)    # bumpers
	cv.draw_line(f.call(Vector2(0.9, -0.2)), f.call(Vector2(1.01, -0.2)), Color(0.85, 0.88, 0.92, 0.6), 2.5)
	for wx in [0.2, 0.8]:
		var c: Vector2 = f.call(Vector2(wx, -0.0)) + Vector2(0, -length * 0.06)
		cv.draw_circle(c, length * 0.075, Color(0.01, 0.01, 0.012))
		cv.draw_circle(c, length * 0.074, Color(0.015, 0.015, 0.018))
		cv.draw_circle(c, length * 0.035, Color(0.5, 0.53, 0.58, 0.6))  # hubcap
	var tail: Vector2 = f.call(Vector2(0.01, -0.33))
	var head: Vector2 = f.call(Vector2(0.99, -0.33))
	cv.draw_rect(Rect2(tail - Vector2(2, 3), Vector2(4, 6)), Color(0.8, 0.08, 0.06, 0.9 if lights else 0.45))
	cv.draw_rect(Rect2(head - Vector2(2, 3), Vector2(4, 6)), Color(0.95, 0.92, 0.8, 0.95 if lights else 0.25))
	if lights:
		var dir := -1.0 if flip else 1.0
		cv.draw_colored_polygon(PackedVector2Array([head, head + Vector2(dir * length * 1.4, -length * 0.08), head + Vector2(dir * length * 1.4, length * 0.16)]), Color(1.0, 0.95, 0.8, 0.07))
		cv.draw_texture_rect(_glow_tex, Rect2(head - Vector2(18, 18), Vector2(36, 36)), false, Color(1.0, 0.95, 0.8, 0.5))
		cv.draw_texture_rect(_glow_tex, Rect2(tail - Vector2(14, 14), Vector2(28, 28)), false, Color(1.0, 0.1, 0.05, 0.45))
		cv.draw_rect(Rect2(head.x - 3.0, base + 4.0, 6.0, length * 0.25), Color(1.0, 0.95, 0.8, 0.06))  # its lights smeared in the road

## Gun metal: a city in the rain. The drops fall in depth (far ones short, thin and slow; near ones long and fast),
## each a streak that fades towards its top, so the motion reads as smooth. They hit a wet street with a hard edge of
## light and the city's windows smeared in it. No rings: a landing drop only throws two tiny specks up.
func _draw_rain(sz: Vector2) -> void:
	var cv := _canvas
	var col := Color(0.82, 0.86, 0.92)
	var floor_y := sz.y * 0.88
	var lean := 0.2
	var tops := PackedVector2Array()
	# Two batches (thin far drops, thicker near ones), each a single draw call. A drop is two pieces, faint tail and
	# brighter head, which reads as the same streak fading towards its top.
	var far_p := PackedVector2Array()
	var far_c := PackedColorArray()
	var near_p := PackedVector2Array()
	var near_c := PackedColorArray()
	var dirv := Vector2(-lean, 1.0).normalized()
	for dr in _rain:
		var d: float = dr["d"]
		var spd := 0.5 + 1.4 * d
		var y := fposmod(float(dr["y"]) + _t * spd * 0.6, 1.1) - 0.08
		var x := float(dr["x"]) - 0.1 - y * lean * sz.y / sz.x
		var ln := 14.0 + 90.0 * d
		var head := Vector2(x * sz.x, y * sz.y)
		var land := floor_y + 26.0 * d
		if head.y > land:
			if d > 0.45 and head.y < land + 40.0:
				tops.append(Vector2(head.x, land))
			continue
		var a := 0.06 + 0.34 * d * (0.6 + 0.4 * float(dr["k"]))
		var tail := head - dirv * ln
		var mid := head - dirv * ln * 0.45
		var pts := far_p if d < 0.4 else near_p
		var cs := far_c if d < 0.4 else near_c
		pts.append_array([tail, mid, mid, head])
		cs.append_array([Color(col, a * 0.3), Color(col, a)])
	if not far_p.is_empty():
		cv.draw_multiline_colors(far_p, far_c, -1.0)
	if not near_p.is_empty():
		cv.draw_multiline_colors(near_p, near_c, 2.0)
	# The wet street: darker, with the lit windows smeared down in it, and a thin hard edge where it starts.
	cv.draw_rect(Rect2(0, floor_y, sz.x, sz.y - floor_y), Color(0.008, 0.009, 0.011, 0.6))
	if _city.size() > 2:
		for b in _city[2]:
			if (b["wins"] as Array).size() > 3:
				var rx := float(b["x"]) * sz.x + float(b["w"]) * sz.x * 0.5
				var wob := 3.0 * sin(_t * 1.3 + rx)
				cv.draw_rect(Rect2(rx - 3.0 + wob, floor_y + 6.0, 6.0, (sz.y - floor_y) * 0.7), Color(col, 0.035))
	cv.draw_line(Vector2(0, floor_y), Vector2(sz.x, floor_y), Color(col, 0.4), 1.5)
	cv.draw_line(Vector2(0, floor_y + 2.0), Vector2(sz.x, floor_y + 2.0), Color(0, 0, 0, 0.5), 2.0)
	# Old cars: one drives very slowly past on the far lane every 110 s or so, lights on; three sit parked at the kerb.
	var k := sz.y / 1080.0
	var drive := fposmod(_t, 110.0) / 110.0
	_draw_car(cv, sz.x * (1.1 - drive * 1.4), floor_y + 34.0 * k, 150.0 * k, Color(0.14, 0.15, 0.17), true, true)
	for c in _cars:
		_draw_car(cv, float(c["x"]) * sz.x, floor_y + 70.0 * k, float(c["len"]) * sz.x, c["col"], c["flip"])
	# Landing drops: two specks hop up and fall back, nothing more.
	for p in tops:
		var ph := fposmod(p.x * 0.013 + _t * 3.0, 1.0)
		var hop := 10.0 * ph * (1.0 - ph) * 4.0
		cv.draw_rect(Rect2(p.x - 3.0 - 6.0 * ph, p.y - hop, 1.5, 1.5), Color(col, 0.45 * (1.0 - ph)))
		cv.draw_rect(Rect2(p.x + 2.0 + 5.0 * ph, p.y - hop * 0.7, 1.5, 1.5), Color(col, 0.4 * (1.0 - ph)))

# ---------- Neon Coast ----------
## The sky's colours, top and bottom, and the palms' colour for each: it drifts from one to the next (about 9 s each).
const NEON_SKY := [
	[Color("3A0B45"), Color("D01A7A"), Color("FF6CB8")],   # purple to magenta
	[Color("6E0A4A"), Color("FF2E7E"), Color("FF9ACB")],   # hot pink
	[Color("10124A"), Color("2A5BD8"), Color("FF5AA8")],   # deep blue, pink palms
	[Color("0B3540"), Color("1D8E9C"), Color("E2505E")],   # teal, red palms
	[Color("2A0838"), Color("8A1A7A"), Color("FF74C4")],   # violet
]
var _palms: Array = []   # {a: angle around you, r: distance, lean, h: height, ph: sway phase}

## The sky's colours [top, horizon, palms] at this moment. Driven by the clock, not by each background's own
## time, so every copy (and the controller's lightbar) shows the same colour at once.
static func neon_sky() -> Array:
	var f := fposmod(Time.get_ticks_msec() / 9000.0, float(NEON_SKY.size()))
	var i := int(f)
	var k := smoothstep(0.0, 1.0, f - i)
	var a: Array = NEON_SKY[i]
	var b: Array = NEON_SKY[(i + 1) % NEON_SKY.size()]
	return [(a[0] as Color).lerp(b[0], k), (a[1] as Color).lerp(b[1], k), (a[2] as Color).lerp(b[2], k)]

func _neon_colors() -> Array:
	return neon_sky()

## Palm trees standing in a ring around you, the view slowly turning (and gently rolling), drawn in chunky pixels.
## Trees near the edges of the view are closer, so bigger, like a wide lens.
func _draw_palms(sz: Vector2) -> void:
	var cols := _neon_colors()
	if _mat != null:
		_mat.set_shader_parameter("top_color", cols[0])
		_mat.set_shader_parameter("bottom_color", cols[1])
	var palm: Color = cols[2]
	var yaw := _t * 0.07
	var c := sz * 0.5
	draw_set_transform(c, 0.05 * sin(_t * 0.23), Vector2.ONE)  # the roll: everything tilts a little, back and forth
	var vis: Array = []
	for p in _palms:
		var phi := wrapf(float(p["a"]) - yaw, -PI, PI)
		var cz := cos(phi)
		if cz < 0.32:
			continue
		var z := float(p["r"]) * cz
		vis.append([z, p, float(p["r"]) * sin(phi)])
	vis.sort_custom(func(x, y): return x[0] > y[0])  # far first
	var px := maxf(round(sz.y / 180.0), 4.0)  # one "pixel" of the art
	for v in vis:
		var z: float = v[0]
		var p: Dictionary = v[1]
		var k := clampf(1.0 / z, 0.6, 3.2)
		var sx := float(v[2]) / z * sz.x * 0.42
		var fog := clampf((k - 0.6) / 1.6, 0.0, 1.0)
		var col := Color(cols[1], 1.0).lerp(palm, 0.45 + 0.55 * fog)
		var b := px * clampf(round(k), 1.0, 3.0)
		var h := sz.y * 0.42 * k * float(p["h"])
		var base := Vector2(sx, sz.y * 0.62)
		var sway := sin(_t * 0.6 + float(p["ph"])) * 0.04
		var lean: float = float(p["lean"]) + sway
		# trunk: stacked blocks, bending with the lean, a little thinner towards the top
		var steps := int(h / b)
		var top := base
		for i in steps:
			var u := float(i) / maxf(steps, 1)
			var x := base.x + lean * u * u * h * 0.5
			var y := base.y - u * h
			var w := b * (3.0 - u * 1.3) * clampf(k * 0.7, 1.0, 2.0)
			draw_rect(Rect2(_snap(x - w * 0.5, b), _snap(y, b), _snap(w, b) + b, b), col)
			if i % 3 == 0:
				draw_rect(Rect2(_snap(x - w * 0.5, b), _snap(y, b), _snap(w, b) + b, b * 0.5), col.darkened(0.25))  # the trunk's rings
			top = Vector2(x, y)
		# fronds: drooping arcs of blocks with leaflets hanging off them
		for f in 7:
			var ang := lerpf(-PI * 0.95, -PI * 0.05, float(f) / 6.0) + sway * 2.0
			var ln := h * (0.32 + 0.06 * float(f % 2))
			var n := int(ln / b)
			for j in n:
				var u2 := float(j) / maxf(n, 1)
				var q := top + Vector2(cos(ang), sin(ang)) * u2 * ln + Vector2(0, u2 * u2 * ln * 0.75)
				var th := b * (2.0 if u2 < 0.6 else 1.0)  # the frond is thicker near the crown
				draw_rect(Rect2(_snap(q.x, b), _snap(q.y, b), b, th), col)
				if u2 > 0.12:
					draw_rect(Rect2(_snap(q.x, b), _snap(q.y + th, b), b, b * roundf(1.0 + 3.0 * (1.0 - u2) * (0.6 + 0.4 * float(j % 2)))), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _snap(v: float, b: float) -> float:
	return floor(v / b) * b

func _draw() -> void:
	var sz := size
	# The gradient, both lights and the sheen are drawn by the shader (see above); here they
	# only get their positions for this moment.
	var l1 := Vector2(sz.x * (0.30 + 0.12 * sin(_t * 0.07)), sz.y * (0.35 + 0.10 * cos(_t * 0.05)))
	var l2 := Vector2(sz.x * (0.75 + 0.10 * cos(_t * 0.06)), sz.y * (0.55 + 0.12 * sin(_t * 0.04)))
	if _mat != null:
		_mat.set_shader_parameter("rect_size", sz)
		_mat.set_shader_parameter("l1", l1)
		_mat.set_shader_parameter("l2", l2)
		_mat.set_shader_parameter("sheen_x", fposmod(_t * 18.0, sz.x + 900.0) - 450.0)
	var lit := _lit
	if _style == "glass":
		# Sleek: two thin chrome blades leaning across the steel, drifting very slowly, each lit along one edge and
		# shaded on the other, and one hairline of light across the screen like a polished trim.
		for k in 2:
			var w := sz.x * (0.014 + 0.008 * k)
			var x0 := fposmod(sz.x * (0.3 + 0.37 * k) + 9.0 * _t * (1.0 + 0.4 * k), sz.x + sz.y) - sz.y * 0.5
			var lean := sz.y * 0.5
			var pts := PackedVector2Array([Vector2(x0 + lean, 0), Vector2(x0 + lean + w, 0), Vector2(x0 + w, sz.y), Vector2(x0, sz.y)])
			draw_polygon(pts, PackedColorArray([Color(1, 1, 1, 0.55), Color(0.35, 0.4, 0.47, 0.25), Color(0.35, 0.4, 0.47, 0.25), Color(1, 1, 1, 0.55)]))
			draw_line(pts[0], pts[3], Color(1, 1, 1, 0.8), 1.5, true)
		# A faint grid of hairlines, like the seams of steel panels, with a slow glint travelling along each long seam.
		for gi in 5:
			var gy := sz.y * (0.14 + 0.17 * gi)
			draw_line(Vector2(0, gy), Vector2(sz.x, gy), Color(0.3, 0.34, 0.4, 0.07), 1.0)
			var gx := fposmod(_t * (60.0 + 25.0 * gi) + 410.0 * gi, sz.x + 600.0) - 300.0
			for q in 12:
				var a := 0.16 * (1.0 - q / 12.0)
				draw_line(Vector2(gx - q * 22.0, gy), Vector2(gx - q * 22.0 - 22.0, gy), Color(1, 1, 1, a), 2.0)
		for gi in 7:
			var gxx := sz.x * (0.08 + 0.14 * gi)
			draw_line(Vector2(gxx, 0), Vector2(gxx, sz.y), Color(0.3, 0.34, 0.4, 0.045), 1.0)
		# Glass discs drifting up very slowly: a pale fill, a bright rim on top and a shaded one underneath.
		for oi in 6:
			var ph := float(oi) * 1.7
			var r := sz.y * (0.07 + 0.045 * fmod(oi * 0.37, 1.0) + 0.02 * float(oi % 3))
			var ox := sz.x * (0.12 + 0.16 * oi) + 26.0 * sin(_t * 0.11 + ph)
			var oy := sz.y * 1.2 - fposmod(_t * (7.0 + 2.0 * oi) + sz.y * 0.35 * oi, sz.y * 1.4)
			var oc := Vector2(ox, oy)
			draw_circle(oc, r, Color(1, 1, 1, 0.07))
			draw_arc(oc, r, deg_to_rad(200), deg_to_rad(340), 32, Color(1, 1, 1, 0.5), 2.0, true)
			draw_arc(oc, r, deg_to_rad(20), deg_to_rad(160), 32, Color(0.3, 0.34, 0.4, 0.18), 2.0, true)
			draw_circle(oc + Vector2(-r * 0.35, -r * 0.4), r * 0.1, Color(1, 1, 1, 0.45))
		# Fine dust of light in the air.
		for di in 40:
			var dx := fposmod(sz.x * fmod(di * 0.6180339, 1.0) + 14.0 * sin(_t * 0.2 + di), sz.x)
			var dy := sz.y - fposmod(_t * (6.0 + fmod(di * 3.7, 9.0)) + sz.y * fmod(di * 0.7548, 1.0), sz.y)
			var tw := 0.5 + 0.5 * sin(_t * 1.3 + di * 2.1)
			draw_circle(Vector2(dx, dy), 1.4 + fmod(di, 3.0) * 0.6, Color(1, 1, 1, 0.12 + 0.3 * tw))
		draw_line(Vector2(0, sz.y * 0.64), Vector2(sz.x, sz.y * 0.64), Color(1, 1, 1, 0.35), 1.0)
		draw_line(Vector2(0, sz.y * 0.64 + 1.0), Vector2(sz.x, sz.y * 0.64 + 1.0), Color(0.3, 0.34, 0.4, 0.18), 1.0)
		return
	if _style == "aero":
		return  # the light, the water, the fish and the grass have their own layers (see _layer)
	if _style == "rain":
		return  # the city and rain have their own layers (see _layer)
	if _style == "basement":
		return  # the corridor has its own layers
	if _style == "forest":
		return  # the trees and light have their own layers
	if _style == "kingdom":
		_scene.draw(self, sz, _t, _glow_tex)
		return
	if _style == "temple":
		_temple.draw(self, sz, _t, plain)
		return
	if _style == "cosmos":
		_cosmos.draw(self, sz, _t)
		return
	if _style == "pcb":
		_pcb.draw(self, sz, _t)
		return
	if _style == "castle":
		_castle.draw_sky(self, sz, _t, _glow_tex)  # the castle and the snow have their own layers
		return
	if _style == "palms":
		_draw_palms(sz)
		return
	if _style == "cubes":
		# PS2: nearly black, with only a fine dust of blue light (the cubes belong to the intro).
		for a in _ash:
			var p0: Vector2 = a["pos"]
			var ap := Vector2(p0.x, p0.y - float(a["speed"]) * 0.8 * _t)
			draw_circle(_wrap(ap) * sz, float(a["r"]) * 0.9, Color(_ash_col, float(a["alpha"]) * 0.8))
		return
	if _style == "lines":
		# Channels: no rocks, just soft round bubbles floating up a little faster.
		for a in _ash:
			var p0: Vector2 = a["pos"]
			var sway: float = a["sway"]
			var bp := Vector2(p0.x + 0.03 * (cos(sway) - cos(_t * 0.6 + sway)), p0.y - float(a["speed"]) * 1.8 * _t)
			var rr: float = float(a["r"]) * 9.0
			var bc := Color(_ash_col, float(a["alpha"]) * 0.22)
			draw_circle(_wrap(bp) * sz, rr, bc)
			draw_arc(_wrap(bp) * sz, rr, 0.0, TAU, 32, Color(1, 1, 1, float(a["alpha"]) * 1.4), 2.0, true)
		return
	for s in _shards:
		var pts := PackedVector2Array()
		var center: Vector2 = _wrap(s["pos"] + s["drift"] * _t) * sz
		var rot: float = s["rot"] + s["spin"] * _t
		for v: Vector2 in SHARD:
			pts.append(center + v.rotated(rot) * s["size"])
		var c := Color(_shard_col, float(s["alpha"]) * (0.55 if lit else 1.0))
		draw_colored_polygon(pts, Color(c, s["alpha"] * 0.5))
		pts.append(pts[0])
		draw_polyline(pts, c, 2.5, true)
	for a in _ash:
		var p0: Vector2 = a["pos"]
		var sway: float = a["sway"]
		var ap := Vector2(p0.x + 0.06 * (cos(sway) - cos(_t * 0.4 + sway)), p0.y - float(a["speed"]) * _t)
		if _style == "embers":
			# Embers: brighter, warmer, rising faster and flickering.
			var flick := 0.6 + 0.4 * sin(_t * 3.0 + sway * 5.0)
			var ep := Vector2(ap.x, p0.y - float(a["speed"]) * 1.6 * _t)
			draw_circle(_wrap(ep) * sz, float(a["r"]) * 1.2, Color(_ash_col, minf(float(a["alpha"]) * 2.2 * flick, 0.8)))
		else:
			draw_circle(_wrap(ap) * sz, a["r"], Color(_ash_col, float(a["alpha"]) * (0.6 if lit else 1.0)))
	if _style == "embers":
		_draw_lava(sz)

## Volcanic: glowing cracks in the floor along the bottom of the screen, and sparks that pop out of the dark and
## streak upward, each for a moment (the crackle). All drawn from the clock, so nothing is stored.
func _draw_lava(sz: Vector2) -> void:
	var glow := 0.65 + 0.35 * sin(_t * 1.7)
	for c in 3:
		var y0 := sz.y * (0.93 + 0.025 * float(c))
		var pts := PackedVector2Array()
		var x := -20.0
		var k := 0
		while x < sz.x + 40.0:
			var jag := sin(float(k) * 12.9898 + float(c) * 78.233) * 43758.5453
			jag = jag - floorf(jag)
			pts.append(Vector2(x, y0 + (jag - 0.5) * sz.y * 0.03))
			x += sz.x * (0.035 + 0.05 * jag)
			k += 1
		var a := (0.55 - 0.12 * float(c)) * glow
		draw_polyline(pts, Color(1.0, 0.3, 0.05, 0.16 * a), 9.0, true)
		draw_polyline(pts, Color(1.0, 0.55, 0.12, 0.55 * a), 3.5, true)
		draw_polyline(pts, Color(1.0, 0.9, 0.55, 0.7 * a), 1.2, true)
	for i in 26:
		var seed_f := float(i) * 1.6180339
		var life := 1.1 + 0.9 * fposmod(seed_f * 3.7, 1.0)  # seconds between pops
		var ph := fposmod(_t / life + fposmod(seed_f, 1.0), 1.0)
		if ph > 0.3:
			continue  # dark: nothing to see until the next pop
		var f := ph / 0.3
		var cyc := floorf(_t / life + fposmod(seed_f, 1.0))
		var hx := fposmod(sin((seed_f + cyc * 7.31) * 12.9898) * 43758.5453, 1.0)
		var hy := fposmod(sin((seed_f + cyc * 3.17) * 78.233) * 43758.5453, 1.0)
		var base := Vector2(hx * sz.x, sz.y * (0.55 + 0.42 * hy))
		var dir := Vector2(sin(seed_f * 9.0 + cyc) * 0.5, -1.0).normalized()
		var head := base + dir * f * sz.y * 0.09
		var tail := base + dir * maxf(f - 0.35, 0.0) * sz.y * 0.09
		var fade := 1.0 - f
		draw_line(tail, head, Color(1.0, 0.6, 0.15, 0.7 * fade), 2.4, true)
		draw_circle(head, 2.6 + 3.0 * (1.0 - f), Color(1.0, 0.95, 0.6, 0.85 * fade))
