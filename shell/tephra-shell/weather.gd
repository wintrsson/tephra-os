extends Node
## Weather for the Today page. Uses Open-Meteo (free, no account, no key).
##   Where you are: your city, found from your internet address (ipwho.is),
##   or a city you write in user://weather_city.txt (a name like "London").
##   What it is: Open-Meteo's forecast for those coordinates.
## Results are saved for 30 minutes, so it works offline and doesn't hammer the service.

signal changed
signal condition_changed(text: String)  # the sky changed since the last reading (clear to rain, ...)

const Settings = preload("res://settings.gd")

const CACHE_MIN := 10  # the weather is read again every 10 minutes (see _ready), and whenever Tephra asks for it (fetch(false))
const FORECAST := "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=%s&wind_speed_unit=%s&timezone=auto&forecast_days=1"
const GEOCODE := "https://geocoding-api.open-meteo.com/v1/search?name=%s&count=1&language=en&format=json"
const IP_LOOKUP := "https://ipwho.is/"

var data := {}   # city, temp, feels, code, is_day, hi, lo, rain, wind, unit_c, fetched
var _req: HTTPRequest
var _busy := false

func _ready() -> void:
	_req = HTTPRequest.new()
	add_child(_req)
	var p := "user://weather.json"
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary:
			data = d
	fetch(false)
	var again := Timer.new()
	again.wait_time = CACHE_MIN * 60.0
	again.autostart = true
	again.timeout.connect(func() -> void: fetch(true))
	add_child(again)

## Fetches fresh weather unless the saved copy is recent (and in the same unit).
func fetch(force := false) -> void:
	if _busy:
		return
	var unit_c: bool = Settings.get_value("temp_c", false)
	var fresh: bool = data.has("fetched") and data.get("unit_c", false) == unit_c and Time.get_unix_time_from_system() - float(data["fetched"]) < CACHE_MIN * 60
	if not force and fresh:
		return
	_busy = true
	var loc := await _location()
	if loc.is_empty():
		_busy = false
		return
	var url := FORECAST % [loc["lat"], loc["lon"], "celsius" if unit_c else "fahrenheit", "kmh" if unit_c else "mph"]
	var d = await _get_json(url)
	_busy = false
	if not (d is Dictionary and d.get("current") is Dictionary and d.get("daily") is Dictionary):
		return
	var cur: Dictionary = d["current"]
	var day: Dictionary = d["daily"]
	var old_kind := str(kind_for(int(data["code"]), bool(data.get("is_day", true)))) if data.has("code") else ""
	data = {
		"city": loc["city"],
		"temp": roundi(float(cur.get("temperature_2m", 0))),
		"feels": roundi(float(cur.get("apparent_temperature", 0))),
		"code": int(cur.get("weather_code", 0)),
		"is_day": int(cur.get("is_day", 1)) == 1,
		"wind": roundi(float(cur.get("wind_speed_10m", 0))),
		"hi": _first_int(day.get("temperature_2m_max", [0])),
		"lo": _first_int(day.get("temperature_2m_min", [0])),
		"rain": _first_int(day.get("precipitation_probability_max", [0])),
		"unit_c": unit_c,
		"fetched": Time.get_unix_time_from_system(),
	}
	var f := FileAccess.open("user://weather.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
	changed.emit()
	if old_kind != "" and old_kind != kind_for(int(data["code"]), bool(data["is_day"])):
		condition_changed.emit("%s: %s, %d°" % [str(data["city"]), text_for(int(data["code"]), bool(data["is_day"])), int(data["temp"])])

# First number of a list (0 if the list is empty or the value is missing).
func _first_int(a: Variant) -> int:
	if a is Array and not (a as Array).is_empty() and (a as Array)[0] != null:
		return roundi(float((a as Array)[0]))
	return 0

# One request at a time on our single HTTPRequest. Returns parsed JSON, or null.
func _get_json(url: String) -> Variant:
	if _req.request(url) != OK:
		return null
	var res: Array = await _req.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return null
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())

# {lat, lon, city}: from the city file if there is one, else from the IP address.
# The answer is saved (a city by name until you change it, an IP guess for a day).
func _location() -> Dictionary:
	var city_file := "user://weather_city.txt"
	var wanted := FileAccess.get_file_as_string(city_file).strip_edges() if FileAccess.file_exists(city_file) else ""
	var cache := "user://weather_loc.json"
	if FileAccess.file_exists(cache):
		var c = JSON.parse_string(FileAccess.get_file_as_string(cache))
		if c is Dictionary and c.get("query", "") == wanted:
			if wanted != "" or Time.get_unix_time_from_system() - float(c.get("fetched", 0)) < 86400:
				return c
	var loc := {}
	if wanted != "":
		var g = await _get_json(GEOCODE % wanted.uri_encode())
		if g is Dictionary and g.get("results") is Array and not (g["results"] as Array).is_empty():
			var r: Dictionary = g["results"][0]
			loc = {"lat": r["latitude"], "lon": r["longitude"], "city": str(r.get("name", wanted))}
	else:
		var ip = await _get_json(IP_LOOKUP)
		if ip is Dictionary and ip.get("success", false):
			loc = {"lat": ip["latitude"], "lon": ip["longitude"], "city": str(ip.get("city", ""))}
	if loc.is_empty():
		return {}
	loc["query"] = wanted
	loc["fetched"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(cache, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(loc))
	return loc

# ---------- Weather codes (WMO) ----------
static func kind_for(code: int, is_day: bool) -> String:
	if code == 0 or code == 1:
		return "sun" if is_day else "moon"
	if code == 2:
		return "partly"
	if code == 3:
		return "cloud"
	if code == 45 or code == 48:
		return "fog"
	if (code >= 51 and code <= 67) or (code >= 80 and code <= 82):
		return "rain"
	if (code >= 71 and code <= 77) or code == 85 or code == 86:
		return "snow"
	if code >= 95:
		return "storm"
	return "cloud"

static func text_for(code: int, is_day: bool) -> String:
	match kind_for(code, is_day):
		"sun": return "Sunny"
		"moon": return "Clear"
		"partly": return "Partly cloudy"
		"cloud": return "Cloudy"
		"fog": return "Foggy"
		"rain": return "Rain"
		"snow": return "Snow"
		"storm": return "Thunderstorms"
	return ""
