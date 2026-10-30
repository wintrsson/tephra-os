extends RefCounted
## Where Tephra's info bar (the performance numbers) sits: 8 spots, the four corners and the middle of
## each edge. Picked in the control center (select the bar, then Square). The numbers are only drawn
## in Tephra's own menus; nothing is put inside games any more (MangoHud was removed in v0.23.0).

const Settings = preload("res://settings.gd")

## The 8 spots, as the control center's picker lays them out (3 x 3, the middle is the game itself).
const ZONES := ["top-left", "top-center", "top-right", "middle-left", "middle-right", "bottom-left", "bottom-center", "bottom-right"]
const CELLS := {
	"top-left": Vector2i(0, 0), "top-center": Vector2i(1, 0), "top-right": Vector2i(2, 0),
	"middle-left": Vector2i(0, 1), "middle-right": Vector2i(2, 1),
	"bottom-left": Vector2i(0, 2), "bottom-center": Vector2i(1, 2), "bottom-right": Vector2i(2, 2),
}
const DEFAULT_ZONE := "bottom-center"
const MARGIN := 24

## Tephra used to start Steam with MangoHud for numbers over games. That is gone; this removes the
## settings file it left behind, so nothing points MangoHud at Tephra any more.
static func cleanup() -> void:
	var old := OS.get_environment("HOME") + "/.config/tephra/mangohud.conf"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)

## The spot for a game: its own if one was chosen while playing it, else the one chosen on the control
## center outside games, else the bottom edge. id "" means "outside games".
static func zone_for(id: String) -> String:
	if id != "":
		var own := str(Settings.get_value("hud_zone_" + id, ""))
		if ZONES.has(own):
			return own
	var general := str(Settings.get_value("hud_zone", ""))
	return general if ZONES.has(general) else DEFAULT_ZONE

## Remembers a spot for a game (id "" = for every game without its own). "" as zone forgets it.
static func save_zone(id: String, zone: String) -> void:
	Settings.set_value("hud_zone_" + id if id != "" else "hud_zone", zone)

## The info bar can be hidden from the control center (Triangle); it then stays off over games too.
static func hidden() -> bool:
	return bool(Settings.get_value("perf_hidden", false))

## The zone one D-pad step away (skipping the middle). Stays put at the edge of the grid.
static func neighbour(zone: String, dir: Vector2i) -> String:
	var c: Vector2i = CELLS.get(zone, CELLS[DEFAULT_ZONE])
	var n := Vector2i(clampi(c.x + dir.x, 0, 2), clampi(c.y + dir.y, 0, 2))
	if n == Vector2i(1, 1):  # the middle is the game: jump over it
		n = Vector2i(clampi(n.x + dir.x, 0, 2), clampi(n.y + dir.y, 0, 2))
	for z in CELLS:
		if CELLS[z] == n:
			return z
	return zone

## A tall, narrow box (one number per line) only at the middle of the left and right sides. In the corners
## and along the top and bottom a single strip is used.
static func vertical(zone: String) -> bool:
	return zone == "middle-left" or zone == "middle-right"

## Words for the picker ("top left").
static func zone_name(zone: String) -> String:
	return zone.replace("-", " ")
