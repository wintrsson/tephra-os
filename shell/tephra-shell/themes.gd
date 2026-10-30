extends RefCounted
## Tephra's looks. Every screen asks this file for its colours instead of having them written in,
## so a theme is just one list of colours here (plus how the background moves, which sounds play,
## and for the Channels theme, how the Home screen is laid out).
##
##   Themes.c("text")    a colour of the current theme
##   Themes.ink(0.1)     a see-through shade for faint lines and pills: white on dark themes, dark on light ones
##   Themes.dim(0.7)     the veil behind a menu: dark on dark themes, frosted white on light ones
##   Themes.layout()     "row" (the usual Tephra Home) or "channels" (a paged grid with a bottom bar)
##
## Settings > Themes and the control center pick one. The screen fades to black for a moment while every
## screen is rebuilt with the new colours (each reads its colours when it is made), then fades back in.

const Settings = preload("res://settings.gd")

## The list, in two groups: themes that keep the normal Home row, then themes that bring their own Home layout.
const GROUPS := [
	["Home row", ["tephra", "volcanic", "sleek", "frutiger", "mold"]],
	["Own layout", ["channels", "ps2", "wave", "neon", "planet", "pcb"]],
]
const ORDER := ["tephra", "volcanic", "sleek", "frutiger", "mold", "channels", "ps2", "wave", "neon", "planet", "pcb"]

const REMOVED := ["gothic", "gunmetal", "nature", "castle", "temple"]  # taken out of the list (its files stay, unused)

const DATA := {
	# The original: deep navy, soft white, drifting glass shards and ash.
	"tephra": {
		"name": "Tephra", "blurb": "Deep navy with drifting ash",
		"light": false, "layout": "row", "sounds": "tephra", "music": "home", "backdrop": "shards",
		"bg": Color("070C14"), "text": Color("EEF2F0"), "muted": Color("9AA7A4"), "select": Color("E6E9EC"),
		"on_select": Color("0B1116"), "accent": Color("0D124C"),
		"card": Color(0.04, 0.065, 0.11, 0.94), "panel": Color(0.035, 0.06, 0.10), "sheet": Color(0.03, 0.05, 0.085),
		"tile": Color("132029"), "home_tile": Color(0.045, 0.075, 0.14),
		"bg_top": Color(0.030, 0.050, 0.097), "bg_bottom": Color(0.017, 0.030, 0.056),
		"glow1": Color(0.30, 0.42, 0.75), "glow2": Color(0.55, 0.40, 0.75), "sheen": Color(0.8, 0.88, 1.0),
		"shard": Color(0.75, 0.82, 0.95), "ash": Color(0.85, 0.88, 0.92),
		"swatch": [Color("070C14"), Color("0D124C"), Color("EEF2F0")],
	},
	# Volcanic: near-black basalt, embers rising, a glow of lava underneath.
	"volcanic": {
		"name": "Volcanic", "blurb": "Black basalt and rising embers",
		"light": false, "layout": "row", "sounds": "tephra", "music": "volcanic", "backdrop": "embers",
		"bg": Color("0B0807"), "text": Color("F3ECE7"), "muted": Color("A8978E"), "select": Color("F4E3D8"),
		"on_select": Color("140A06"), "accent": Color("B33A12"),
		"card": Color(0.075, 0.048, 0.038, 0.94), "panel": Color(0.085, 0.055, 0.045), "sheet": Color(0.06, 0.04, 0.032),
		"tile": Color("221512"), "home_tile": Color(0.11, 0.05, 0.035),
		"bg_top": Color(0.055, 0.035, 0.03), "bg_bottom": Color(0.11, 0.04, 0.025),
		"glow1": Color(0.95, 0.36, 0.10), "glow2": Color(0.75, 0.16, 0.06), "sheen": Color(1.0, 0.72, 0.5),
		"shard": Color(0.50, 0.40, 0.36), "ash": Color(1.0, 0.56, 0.22),
		"swatch": [Color("0B0807"), Color("B33A12"), Color("F3ECE7")],
	},
	# Sleek: brushed metal and clean glass. Cool greys, a graphite focus colour, panes of glass that
	# drift very slowly across a silver gradient. Calm and a little cold, not cheerful.
	"sleek": {
		"name": "Sleek", "blurb": "Polished steel and chrome",
		"light": true, "layout": "row", "sounds": "tephra", "music": "sleek", "backdrop": "glass",
		"bg": Color("E9ECEF"), "text": Color("1C222B"), "muted": Color("5F6874"), "select": Color("2B3440"),
		"on_select": Color("FFFFFF"), "accent": Color("2B3A52"),
		"card": Color(0.97, 0.975, 0.98, 0.9), "panel": Color(0.96, 0.965, 0.97), "sheet": Color(0.93, 0.937, 0.945),
		"tile": Color("DADFE5"), "home_tile": Color(0.82, 0.845, 0.88),
		"bg_top": Color(0.90, 0.912, 0.928), "bg_bottom": Color(0.56, 0.592, 0.635),
		"glow1": Color(1, 1, 1), "glow2": Color(0.55, 0.64, 0.76), "sheen": Color(1, 1, 1),
		"shard": Color(0.20, 0.25, 0.33), "ash": Color(0.20, 0.25, 0.33),
		"swatch": [Color("D5D9DF"), Color("2B3440"), Color("1C222B")],
	},
	# Channels: glossy and light, a page of game channels with a curved bar along the bottom.
	"channels": {
		"name": "Channels", "blurb": "Glossy, light and playful",
		"light": true, "layout": "channels", "sounds": "soft", "music": "channels", "backdrop": "lines",
		"bg": Color("EDEFF2"), "text": Color("3A404D"), "muted": Color("878E9A"), "select": Color("33A5E8"),
		"on_select": Color("FFFFFF"), "accent": Color("0D124C"),
		"card": Color(1, 1, 1, 0.95), "panel": Color(1, 1, 1), "sheet": Color(0.96, 0.965, 0.975),
		"tile": Color("F6F7F9"), "home_tile": Color(0.90, 0.93, 0.97),
		"bg_top": Color(0.975, 0.978, 0.985), "bg_bottom": Color(0.90, 0.91, 0.925),
		"glow1": Color(0.55, 0.80, 0.98), "glow2": Color(0.70, 0.90, 1.0), "sheen": Color(1, 1, 1),
		"shard": Color(0.20, 0.60, 0.90), "ash": Color(0.20, 0.62, 0.92),
		"swatch": [Color("EDEFF2"), Color("33A5E8"), Color("3A404D")],
	},
	# PS2: black, glowing blue dots and drifting glass cubes, with a plain list of menu words. All
	# original drawing; it only borrows the feeling of a certain old console's start-up menu.
	"ps2": {
		"name": "Retro", "blurb": "Near-black, blue light and a tumbling ring",
		"light": false, "layout": "ps2", "sounds": "tephra", "music": "ps2", "backdrop": "cubes",
		"bg": Color("000000"), "text": Color("DCEBFF"), "muted": Color("5E7FA8"), "select": Color("2FD0FF"),
		"on_select": Color("03121C"), "accent": Color("0A2A6B"),
		"card": Color(0.035, 0.04, 0.05, 0.94), "panel": Color(0.0, 0.0, 0.0), "sheet": Color(0.0, 0.0, 0.0),
		"tile": Color("0B1630"), "home_tile": Color(0.03, 0.07, 0.16),
		"bg_top": Color(0.0, 0.0, 0.0), "bg_bottom": Color(0.0, 0.0, 0.006),
		"glow1": Color(0.10, 0.35, 0.90), "glow2": Color(0.20, 0.55, 1.0), "sheen": Color(0.5, 0.8, 1.0),
		"shard": Color(0.45, 0.72, 1.0), "ash": Color(0.55, 0.85, 1.0),
		"swatch": [Color("02040C"), Color("2FD0FF"), Color("DCEBFF")],
	},
	# Frutiger Aero: sky blue and fresh green, glossy glass, water bubbles and sunlight.
	"frutiger": {
		"name": "Aero", "blurb": "Sky, water, fish, grass and glossy glass",
		"light": true, "layout": "row", "sounds": "aero", "music": "frutiger", "backdrop": "aero",
		"bg": Color("9ED4F5"), "text": Color("0B3560"), "muted": Color("46739A"), "select": Color("1E9BE8"),
		"on_select": Color("FFFFFF"), "accent": Color("1B6FB5"),
		"card": Color(0.93, 0.98, 1.0, 0.96), "panel": Color(0.94, 0.98, 1.0, 0.94), "sheet": Color(0.90, 0.96, 1.0),
		"tile": Color("D4ECFA"), "home_tile": Color(0.70, 0.88, 0.99),
		"bg_top": Color(0.30, 0.62, 0.95), "bg_bottom": Color(0.62, 0.88, 0.66),
		"glow1": Color(1.0, 1.0, 0.85), "glow2": Color(0.45, 1.0, 0.65), "sheen": Color(1, 1, 1),
		"shard": Color(1, 1, 1), "ash": Color(1, 1, 1),
		"swatch": [Color("4D9EF2"), Color("1E9BE8"), Color("9EE0A6")],
	},
	# Wave: deep blue silk ribbons, a row of categories and a list under each (colours are chosen in its
	# own Colours category). All original drawing; it borrows only the layout idea of old console menus.
	"wave": {
		"name": "Wave", "blurb": "Blue silk, categories and lists",
		"light": false, "layout": "xmb", "sounds": "wave", "music": "wave", "backdrop": "cubes",
		"bg": Color("03133F"), "text": Color("EAF3FF"), "muted": Color("8FB0E0"), "select": Color("5CB8FF"),
		"on_select": Color("02102E"), "accent": Color("0A3A9A"),
		"card": Color(0.02, 0.09, 0.28, 0.94), "panel": Color(0.02, 0.08, 0.24), "sheet": Color(0.02, 0.07, 0.21),
		"tile": Color("0B2A6B"), "home_tile": Color(0.04, 0.16, 0.42),
		"bg_top": Color(0.02, 0.06, 0.22), "bg_bottom": Color(0.04, 0.30, 0.78),
		"glow1": Color(0.30, 0.60, 1.0), "glow2": Color(0.50, 0.80, 1.0), "sheen": Color(0.7, 0.9, 1.0),
		"shard": Color(0.55, 0.80, 1.0), "ash": Color(0.6, 0.85, 1.0),
		"swatch": [Color("04184D"), Color("5CB8FF"), Color("EAF3FF")],
	},
	# Gun metal: dark, shiny and quiet. Blue-black steel with a wet shine, rain streaking down behind everything, small
	# ripples at the bottom, and low, soft sounds (every sound is a raindrop or a dull metal tap).
	"gunmetal": {
		"name": "Gun metal", "blurb": "Hard grey steel, rain and quiet",
		"light": false, "layout": "row", "sounds": "gunmetal", "music": "gunmetal", "backdrop": "rain",
		"bg": Color("0B0B0C"), "text": Color("D6D8DA"), "muted": Color("7B7F84"), "select": Color("C3C8CE"),
		"on_select": Color("0B0B0C"), "accent": Color("3C3F44"),
		"card": Color(0.075, 0.077, 0.082, 0.94), "panel": Color(0.08, 0.082, 0.088), "sheet": Color(0.06, 0.062, 0.066),
		"tile": Color("1B1D20"), "home_tile": Color(0.105, 0.11, 0.118),
		"bg_top": Color(0.035, 0.036, 0.04), "bg_bottom": Color(0.125, 0.13, 0.138),
		"glow1": Color(0.62, 0.64, 0.68), "glow2": Color(0.42, 0.44, 0.47), "sheen": Color(0.9, 0.92, 0.95),
		"shard": Color(0.72, 0.75, 0.8), "ash": Color(0.78, 0.82, 0.88),
		"swatch": [Color("0B0B0C"), Color("C3C8CE"), Color("5A5E64")],
	},
	# Neon Coast: an 80s night drive. The sky slowly shifts between magenta, hot pink, teal and purple, palm trees drawn
	# in big pixels turn slowly around you, scanlines over everything, chunky cyan letters and chill synth music.
	# Original drawing and sound, made in the spirit of retro neon game menus.
	"neon": {
		"name": "Miami '89", "blurb": "Pink and teal nights, pixel palms, synths",
		"light": false, "layout": "neon", "sounds": "neon", "music": "neon", "backdrop": "palms",
		"bg": Color("2A0838"), "text": Color("F2FFFD"), "muted": Color("D9A3DE"), "select": Color("3FF5E6"),
		"on_select": Color("2A0838"), "accent": Color("FF2E88"),
		"card": Color(0.16, 0.03, 0.22, 0.9), "panel": Color(0.17, 0.04, 0.23), "sheet": Color(0.13, 0.03, 0.18),
		"tile": Color("3A0E4A"), "home_tile": Color(0.30, 0.06, 0.36),
		"bg_top": Color(0.23, 0.04, 0.27), "bg_bottom": Color(0.82, 0.10, 0.48),
		"glow1": Color(0.25, 0.96, 0.90), "glow2": Color(1.0, 0.18, 0.53), "sheen": Color(1.0, 0.7, 0.9),
		"shard": Color(1.0, 0.45, 0.75), "ash": Color(0.25, 0.96, 0.90),
		"swatch": [Color("D01A7A"), Color("3FF5E6"), Color("2A0838")],
	},
	# Gothic: a black castle on a cliff on a winter night, spires and pointed windows against a pale moon, snow falling
	# in depth and settling on every ledge. Black and white only. Organ, choir and bells. All drawn from code.
	"gothic": {
		"name": "Gothic", "blurb": "A castle in the snow, black and white",
		"light": false, "layout": "row", "sounds": "gothic", "music": "gothic", "backdrop": "castle",
		"bg": Color("08080A"), "text": Color("ECECEE"), "muted": Color("8C8C92"), "select": Color("F4F4F6"),
		"on_select": Color("08080A"), "accent": Color("4A4A50"),
		"card": Color(0.06, 0.06, 0.07, 0.92), "panel": Color(0.07, 0.07, 0.08), "sheet": Color(0.05, 0.05, 0.06),
		"tile": Color("16161A"), "home_tile": Color(0.11, 0.11, 0.12),
		"bg_top": Color(0.015, 0.015, 0.02), "bg_bottom": Color(0.20, 0.20, 0.22),
		"glow1": Color(0.85, 0.86, 0.9), "glow2": Color(0.5, 0.5, 0.54), "sheen": Color(0.95, 0.95, 0.97),
		"shard": Color(0.9, 0.9, 0.92), "ash": Color(0.97, 0.97, 1.0),
		"swatch": [Color("08080A"), Color("F4F4F6"), Color("6A6A70")],
	},
	# Mold: the downstairs corridor of an old house gone to rot, seen by flashlight. Damp cinder blocks, black glossy
	# mold in every seam, water dripping into puddles, and something standing in the far room. Low drones and drips.
	# Original drawing and sound.
	"mold": {
		"name": "Mold", "blurb": "A rotting house by flashlight",
		"light": false, "layout": "row", "sounds": "mold", "music": "mold", "backdrop": "basement",
		"bg": Color("0E0C0A"), "text": Color("D9D2C3"), "muted": Color("8A8174"), "select": Color("E4DCCB"),
		"on_select": Color("14110E"), "accent": Color("4A3F33"),
		"card": Color(0.075, 0.065, 0.055, 0.92), "panel": Color(0.085, 0.074, 0.062), "sheet": Color(0.06, 0.052, 0.045),
		"tile": Color("1E1A16"), "home_tile": Color(0.13, 0.115, 0.098),
		"bg_top": Color(0.03, 0.026, 0.022), "bg_bottom": Color(0.09, 0.08, 0.066),
		"glow1": Color(0.6, 0.55, 0.45), "glow2": Color(0.4, 0.36, 0.3), "sheen": Color(0.85, 0.8, 0.7),
		"shard": Color(0.7, 0.64, 0.54), "ash": Color(0.8, 0.76, 0.68),
		"swatch": [Color("14110E"), Color("D9D2C3"), Color("4A3F33")],
	},
	# Wood: a sunny day in a green meadow with blue sky, clouds, trees and flowers. Warm cream and oak brown, leaf green, light falling through the leaves.
	# Calm sounds of wood, a flute and birdsong, all in daylight. Original drawing and sound.
	"nature": {
		"name": "Nature", "blurb": "A sunny meadow by day, a moonlit one at night",
		"light": true, "layout": "row", "sounds": "wood", "music": "wood", "backdrop": "forest",
		"bg": Color("EADFC6"), "text": Color("2D2217"), "muted": Color("76664E"), "select": Color("5A3E24"),
		"on_select": Color("F6EEDC"), "accent": Color("6B8E4E"),
		"card": Color(0.96, 0.93, 0.85, 0.92), "panel": Color(0.95, 0.91, 0.83), "sheet": Color(0.92, 0.88, 0.80),
		"tile": Color("D9C7A3"), "home_tile": Color(0.80, 0.70, 0.52),
		"bg_top": Color(0.36, 0.64, 0.93), "bg_bottom": Color(0.78, 0.92, 1.0),
		"glow1": Color(1.0, 0.95, 0.7), "glow2": Color(0.6, 0.78, 0.45), "sheen": Color(1.0, 1.0, 0.85),
		"shard": Color(0.45, 0.33, 0.2), "ash": Color(0.45, 0.33, 0.2),
		"swatch": [Color("EADFC6"), Color("5A3E24"), Color("6B8E4E")],
	},
	# Retro: an old 8-bit console. Chunky pixels in a few bright colours, a stepped sky with a sun and moon that rise
	# and set with the real time of day, two small stone castles and a lone traveller. Chiptune beeps and a slow,
	# lonely little tune. Original drawing and sound.
	"castle": {
		"name": "Castle", "blurb": "Two castles, a windmill and the real sky",
		"light": false, "layout": "row", "sounds": "tephra", "music": "library", "backdrop": "kingdom",
		"bg": Color("10162B"), "text": Color("F6F2E8"), "muted": Color("BDB7A6"), "select": Color("F4D77A"),
		"on_select": Color("1A1408"), "accent": Color("C9A227"),
		"card": Color(0.07, 0.09, 0.16, 0.9), "panel": Color(0.07, 0.09, 0.15), "sheet": Color(0.055, 0.07, 0.12),
		"tile": Color("1F2A44"), "home_tile": Color(0.15, 0.2, 0.36),
		"bg_top": Color(0.05, 0.08, 0.2), "bg_bottom": Color(0.1, 0.16, 0.34),
		"glow1": Color(1.0, 0.85, 0.5), "glow2": Color(0.5, 0.6, 0.9), "sheen": Color(1.0, 0.95, 0.8),
		"shard": Color(0.9, 0.85, 0.6), "ash": Color(0.95, 0.9, 0.7),
		"swatch": [Color("10162B"), Color("C9A227"), Color("F6F2E8")],
	},
	# Planet: deep space. The games stand on a ring around a spinning world, only its top showing; turning the world
	# brings the next ones round. A starfield with soft nebulae, shooting stars and a far moon. Original drawing and sound.
	"planet": {
		"name": "Planet", "blurb": "Games orbit a spinning world",
		"light": false, "layout": "planet", "sounds": "wave", "music": "cosmos", "backdrop": "cosmos",
		"bg": Color("05061A"), "text": Color("EAF1FF"), "muted": Color("9AA6CE"), "select": Color("8FD0FF"),
		"on_select": Color("04061A"), "accent": Color("5B7CFF"),
		"card": Color(0.05, 0.07, 0.16, 0.9), "panel": Color(0.05, 0.065, 0.15), "sheet": Color(0.035, 0.045, 0.11),
		"tile": Color("15204A"), "home_tile": Color(0.12, 0.17, 0.42),
		"bg_top": Color(0.012, 0.014, 0.06), "bg_bottom": Color(0.07, 0.04, 0.17),
		"glow1": Color(0.45, 0.55, 1.0), "glow2": Color(0.7, 0.4, 0.9), "sheen": Color(0.8, 0.9, 1.0),
		"shard": Color(0.7, 0.8, 1.0), "ash": Color(0.8, 0.85, 1.0),
		"swatch": [Color("05061A"), Color("8FD0FF"), Color("5B7CFF")],
	},
	# Circuit: a green printed circuit board. Every game is a black chip on it with gold pins, the covers tinted dark in
	# the chip body until chosen, traces joining them. Original drawing and sound.
	"pcb": {
		"name": "Circuit", "blurb": "Games as chips on a circuit board",
		"light": false, "layout": "pcb", "sounds": "tephra", "music": "pcb", "backdrop": "pcb",
		"bg": Color("07261A"), "text": Color("EEF6EA"), "muted": Color("9EC2A4"), "select": Color("F2C94C"),
		"on_select": Color("0B1A10"), "accent": Color("C99A2E"),
		"card": Color(0.03, 0.12, 0.08, 0.92), "panel": Color(0.03, 0.11, 0.075), "sheet": Color(0.02, 0.09, 0.06),
		"tile": Color("0E3A28"), "home_tile": Color(0.07, 0.22, 0.15),
		"bg_top": Color(0.03, 0.2, 0.12), "bg_bottom": Color(0.055, 0.3, 0.18),
		"glow1": Color(0.95, 0.8, 0.35), "glow2": Color(0.3, 0.7, 0.45), "sheen": Color(0.95, 0.95, 0.7),
		"shard": Color(0.85, 0.7, 0.3), "ash": Color(0.8, 0.8, 0.5),
		"swatch": [Color("07261A"), Color("F2C94C"), Color("0E3A28")],
	},
	# Temple: a homage to a very old 16-colour screen (white pages, double blue frames, red links, a turning yellow cross).
	# Original drawing and text. Sounds are the church-organ set.
	"temple": {
		"name": "Temple", "blurb": "Sixteen colours and a turning cross",
		"light": true, "layout": "row", "sounds": "gothic", "music": "gothic", "backdrop": "temple",
		"bg": Color("FFFFFF"), "text": Color("0000AA"), "muted": Color("555555"), "select": Color("0000AA"),
		"on_select": Color("FFFFFF"), "accent": Color("AA0000"),
		"card": Color(1.0, 1.0, 1.0, 0.97), "panel": Color("FFFFFF"), "sheet": Color("F4F4F4"),
		"tile": Color("55FFFF"), "home_tile": Color("FFFF55"),
		"bg_top": Color("FFFFFF"), "bg_bottom": Color("FFFFFF"),
		"glow1": Color("FFFFFF"), "glow2": Color("FFFFFF"), "sheen": Color("FFFFFF"),
		"shard": Color("0000AA"), "ash": Color("0000AA"),
		"swatch": [Color("FFFFFF"), Color("0000AA"), Color("AA0000")],
	},
}

static var _id := ""
static var reloaded := false  # a theme change restarts the scene: start-up jobs that are already done are skipped
static var switched := false  # set when a theme was just put on: the new Home plays the theme's sound

static func id() -> String:
	if _id == "":
		_id = str(Settings.get_value("theme", "tephra"))
		if _id == "wood":
			_id = "nature"  # renamed
		elif _id == "retro":
			_id = "castle"  # remade as the Castle theme
		if not DATA.has(_id) or _id in REMOVED:
			_id = "tephra"
	return _id

static func data(theme := "") -> Dictionary:
	var k := theme if DATA.has(theme) else id()
	if k == "nature" and nature_night():
		return _nature_night()
	return DATA[k]

## Nature has a night version between 7 pm and 5 am: the same meadow under the moon, with a dark set of colours.
## (TEPHRA_HOUR=22 shows another time.)
static func nature_night() -> bool:
	var o := OS.get_environment("TEPHRA_HOUR")
	var h: float
	if o != "":
		h = o.to_float()
	else:
		h = float(Time.get_time_dict_from_system()["hour"])
	return h >= 19.0 or h < 5.0

static var _night_cache := {}
static func _nature_night() -> Dictionary:
	if _night_cache.is_empty():
		var d: Dictionary = DATA["nature"].duplicate()
		d.merge({
			"light": false,
			"bg": Color("0F1B33"), "text": Color("F2EEDC"), "muted": Color("B5B9C6"), "select": Color("F2E3A0"),
			"on_select": Color("1A2210"), "accent": Color("8FB86A"),
			"card": Color(0.08, 0.12, 0.2, 0.9), "panel": Color(0.09, 0.13, 0.2), "sheet": Color(0.07, 0.1, 0.17),
			"tile": Color("1F3050"), "home_tile": Color(0.13, 0.22, 0.35),
			"bg_top": Color(0.04, 0.07, 0.18), "bg_bottom": Color(0.1, 0.18, 0.3),
			"glow1": Color(0.9, 0.95, 0.7), "glow2": Color(0.4, 0.55, 0.8), "sheen": Color(0.9, 0.95, 1.0),
			"swatch": [Color("0F1B33"), Color("F2E3A0"), Color("8FB86A")],
		}, true)
		_night_cache = d
	return _night_cache

## Wave's colour choices (its Colours category): name -> [background top, background bottom, ribbon].
const WAVE_COLORS := {
	"Blue": [Color(0.02, 0.06, 0.22), Color(0.04, 0.30, 0.78), Color(0.55, 0.80, 1.0)],
	"Teal": [Color(0.0, 0.07, 0.10), Color(0.02, 0.38, 0.45), Color(0.45, 0.95, 0.90)],
	"Violet": [Color(0.07, 0.03, 0.20), Color(0.34, 0.14, 0.62), Color(0.78, 0.65, 1.0)],
	"Crimson": [Color(0.14, 0.01, 0.03), Color(0.62, 0.08, 0.14), Color(1.0, 0.62, 0.62)],
	"Amber": [Color(0.12, 0.05, 0.0), Color(0.68, 0.34, 0.03), Color(1.0, 0.85, 0.50)],
	"Green": [Color(0.0, 0.08, 0.03), Color(0.07, 0.45, 0.20), Color(0.60, 1.0, 0.70)],
	"Graphite": [Color(0.02, 0.02, 0.03), Color(0.20, 0.22, 0.27), Color(0.78, 0.82, 0.90)],
}
static var _wave_name := ""
static var _wave := {}

## Wave with a colour other than Blue: every screen's colours (menus, control center, performance bar...) are worked out
## from that colour, so they all match the ribbons.
static func _wave_palette() -> Dictionary:
	var name := str(Settings.get_value("xmb_color", "Blue"))
	if name == "Blue" or not WAVE_COLORS.has(name):
		return {}
	if name != _wave_name:
		_wave_name = name
		var top: Color = WAVE_COLORS[name][0]
		var bot: Color = WAVE_COLORS[name][1]
		var rib: Color = WAVE_COLORS[name][2]
		var card := top.lerp(bot, 0.15)
		_wave = {
			"bg": top, "bg_top": top, "bg_bottom": bot, "select": rib, "on_select": top.darkened(0.2),
			"muted": rib.lerp(Color(0.55, 0.58, 0.62), 0.35), "accent": bot.darkened(0.45),
			"card": Color(card.r, card.g, card.b, 0.94), "panel": top.lerp(bot, 0.12), "sheet": top.lerp(bot, 0.08),
			"tile": top.lerp(bot, 0.35), "home_tile": top.lerp(bot, 0.42),
			"glow1": rib.darkened(0.3), "glow2": rib, "sheen": rib.lightened(0.3), "shard": rib, "ash": rib,
			"swatch": [top, rib, Color("EAF3FF")],
		}
	return _wave

## With several controllers connected the selection colour shows whose pad is in charge (alpha 0 = the theme's own).
static var select_override := Color(0, 0, 0, 0)

static func c(key: String) -> Color:
	if key == "select" and select_override.a > 0.0:
		return select_override
	if id() == "wave":
		var w := _wave_palette()
		if w.has(key) and w[key] is Color:
			return w[key]
	return data().get(key, Color.MAGENTA)

static func light() -> bool:
	return bool(data()["light"])

static func layout() -> String:
	return str(data()["layout"])

static func sounds() -> String:
	return str(data()["sounds"])

static func music() -> String:
	return str(data()["music"])

static func backdrop() -> String:
	return str(data()["backdrop"])

## Each theme's typeface (assets/fonts, all free to share: SIL Open Font License or Apache 2.0, see LICENSE.txt).
## They are look-alikes chosen for the feel, not the consoles' own fonts. Tephra keeps Godot's default.
const FONTS := {"volcanic": "barlow", "sleek": "exo2", "channels": "rounded", "ps2": "arimo", "frutiger": "hind", "wave": "hind", "gunmetal": "exo2", "neon": "bungee", "gothic": "cinzel", "mold": "elite", "nature": "lora", "castle": "cinzel", "temple": "vt323", "planet": "exo2", "pcb": "exo2"}
static var _font_cache := {}

static func font(theme := "") -> Font:
	var key: String = FONTS.get(theme if theme != "" else id(), "")
	if key == "":
		return null
	if not _font_cache.has(key):
		var f := FontFile.new()
		if f.load_dynamic_font("res://assets/fonts/%s.ttf" % key) != OK:
			return null
		_font_cache[key] = f
	return _font_cache[key]

## Faint lines, pills and tracks: white on dark themes, the text colour on light ones.
## Corner rounding for this theme: Gun metal is machined steel, so every corner is (almost) sharp.
static func r(px: float) -> int:
	return 0 if id() == "temple" else (mini(int(px), 2) if id() == "gunmetal" else int(px))

static func ink(alpha: float) -> Color:
	var base := c("text") if light() else Color(1, 1, 1)
	return Color(base, alpha)

## The veil laid over the screen behind a menu.
static func dim(alpha: float) -> Color:
	return Color(0.86, 0.88, 0.91, alpha * 0.85) if light() else Color(0, 0, 0, alpha)

## Saves the choice. home.gd then rebuilds every screen behind a short fade to black.
static func choose(theme: String) -> void:
	if DATA.has(theme):
		Settings.set_value("theme", theme)
		_id = theme

## Icons are drawn white. On a light theme they are drawn in the text colour instead (and the
## small dark details cut into them become white), so they show on the light background.
static func svg_ink(body: String) -> String:
	if not light():
		return body
	var ink_hex := "#" + c("text").to_html(false)
	return body.replace("#121a24", "#@@").replace("#fff\"", ink_hex + "\"").replace("#FFF\"", ink_hex + "\"") \
		.replace("#ffffff\"", ink_hex + "\"").replace("#@@", "#ffffff")

static var _swatches := {}

## A small preview of a theme: its background, accent and text colours side by side in a rounded chip.
static func swatch(theme: String, w := 84, h := 44) -> Texture2D:
	var key := "%s@%dx%d" % [theme, w, h]
	if _swatches.has(key):
		return _swatches[key]
	var cols: Array = data(theme)["swatch"]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := 10.0
	for y in h:
		for x in w:
			# Rounded corners: skip pixels outside the corner circles.
			var cx := clampf(x + 0.5, r, w - r)
			var cy := clampf(y + 0.5, r, h - r)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if d > r:
				continue
			var band := 0 if x < w * 0.5 else (1 if x < w * 0.78 else 2)
			var col: Color = cols[band]
			img.set_pixel(x, y, Color(col, clampf(r - d + 0.5, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_swatches[key] = tex
	return tex
