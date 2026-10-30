extends Node
## Records how hard the PC works while a game runs, and describes the PC itself.
## While a game is running Tephra takes a sample every few seconds (CPU use, GPU use,
## memory, temperatures) and keeps running totals per game in user://perf.json.
## Nothing here needs a game to cooperate, so it works for every Steam game.

const PATH := "user://perf.json"
const INTERVAL := 10.0  # a game must never feel this: one cheap look every 10 s

## What the performance info can show. [setting key, label, on by default]
## Settings > the control center's Performance card toggles these.
const ITEMS := [
	["perf_fps", "FPS", true],
	["perf_graph", "Frame-time graph", true],
	["perf_res", "Resolution", false],
	["perf_refresh", "Refresh rate", false],
	["perf_cpu", "CPU usage", true],
	["perf_gpu", "GPU usage", true],
	["perf_ram", "RAM", false],
	["perf_temps", "Temperatures", false],
]

static func _sline(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_line().strip_edges() if f != null else ""

## CPU package temperature in degrees C, or -1.
static func cpu_temp() -> float:
	if DirAccess.dir_exists_absolute("/sys/class/hwmon"):
		for d in DirAccess.get_directories_at("/sys/class/hwmon"):
			var nm := _sline("/sys/class/hwmon/" + d + "/name")
			if nm == "coretemp" or nm == "k10temp" or nm == "zenpower":
				var t := _sline("/sys/class/hwmon/" + d + "/temp1_input")
				if t != "":
					return float(t.to_int()) / 1000.0
	if DirAccess.dir_exists_absolute("/sys/class/thermal"):
		for d in DirAccess.get_directories_at("/sys/class/thermal"):
			if d.begins_with("thermal_zone") and _sline("/sys/class/thermal/" + d + "/type") == "x86_pkg_temp":
				return float(_sline("/sys/class/thermal/" + d + "/temp").to_int()) / 1000.0
	return -1.0

## The laptop's own battery (not a controller's): {has, pct, charging, full, minutes (-1 unknown)}.
static func laptop_battery() -> Dictionary:
	var out := {"has": false, "pct": -1, "charging": false, "full": false, "minutes": -1}
	if not DirAccess.dir_exists_absolute("/sys/class/power_supply"):
		return out
	for d in DirAccess.get_directories_at("/sys/class/power_supply"):
		var base := "/sys/class/power_supply/" + d
		if _sline(base + "/type") != "Battery" or _sline(base + "/scope") == "Device":
			continue  # a controller's battery says scope "Device"
		out["has"] = true
		out["pct"] = _sline(base + "/capacity").to_int()
		var st := _sline(base + "/status")
		out["charging"] = st == "Charging"
		out["full"] = st == "Full"
		var now := _sline(base + "/energy_now").to_float()
		var full := _sline(base + "/energy_full").to_float()
		var rate := _sline(base + "/power_now").to_float()
		if now <= 0.0:
			now = _sline(base + "/charge_now").to_float()
			full = _sline(base + "/charge_full").to_float()
			rate = _sline(base + "/current_now").to_float()
		if rate > 0.0:
			if out["charging"]:
				out["minutes"] = roundi((full - now) / rate * 60.0)
			elif st == "Discharging":
				out["minutes"] = roundi(now / rate * 60.0)
		return out
	return out

var _appid := ""
var _title := ""
var _timer := 0.0
var _last_total := 0
var _last_idle := 0
var _data := {}
var _loaded := false
var _info := {}

func _ready() -> void:
	set_process(false)

func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_data = d

func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_data))

## Reads a whole text file. Files under /proc and /sys report a size of 0, so
## FileAccess.get_file_as_string() returns "" for them; reading line by line works.
func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var lines := PackedStringArray()
	while not f.eof_reached():
		lines.append(f.get_line())
	return "\n".join(lines)

## Forget everything recorded so far (Developer menu).
func reset() -> void:
	_load()
	_data = {}
	_save()

# ---------- Recording ----------
func start(appid: String, title: String) -> void:
	_load()
	_appid = appid
	_title = title
	_timer = 0.0
	_read_cpu()  # first reading: nothing to compare with yet
	set_process(true)

func stop() -> void:
	if _appid == "":
		return
	set_process(false)
	_save()
	_appid = ""

func _process(delta: float) -> void:
	_timer += delta
	if _timer < INTERVAL:
		return
	_timer = 0.0
	_sample()

func _sample() -> void:
	var e: Dictionary = _data.get(_appid, {"title": _title, "n": 0, "cpu": 0.0, "ram": 0.0, "cpu_t": 0.0, "n_cpu_t": 0,
		"gpu": 0.0, "n_gpu": 0, "gpu_t": 0.0, "n_gpu_t": 0, "peak_cpu": 0.0, "peak_ram": 0.0, "last": 0})
	e["title"] = _title
	var cpu := _read_cpu()
	var ram := _read_ram_mb()
	if cpu >= 0.0:
		e["n"] = int(e["n"]) + 1
		e["cpu"] = float(e["cpu"]) + cpu
		e["peak_cpu"] = maxf(float(e["peak_cpu"]), cpu)
		e["ram"] = float(e["ram"]) + ram
		e["peak_ram"] = maxf(float(e["peak_ram"]), ram)
		var ct := _cpu_temp()
		if ct > 0.0:
			e["cpu_t"] = float(e["cpu_t"]) + ct
			e["n_cpu_t"] = int(e["n_cpu_t"]) + 1
		# nvidia-smi wakes the whole NVIDIA driver up and can make a game hitch, so the GPU is only asked once a minute.
		var g := _gpu() if int(e["n"]) % 6 == 1 or not nvidia_ready() else {"util": -1.0, "temp": -1.0}
		if g["util"] >= 0.0:
			e["gpu"] = float(e["gpu"]) + g["util"]
			e["n_gpu"] = int(e["n_gpu"]) + 1
		if g["temp"] > 0.0:
			e["gpu_t"] = float(e["gpu_t"]) + g["temp"]
			e["n_gpu_t"] = int(e["n_gpu_t"]) + 1
	e["last"] = int(Time.get_unix_time_from_system())
	_data[_appid] = e
	if int(e["n"]) % 6 == 0:
		_save()

# CPU use since the last reading, 0-100 (-1 on the first reading).
func _read_cpu() -> float:
	var line := _read_file("/proc/stat").split("\n")[0]
	var p := line.split(" ", false)
	if p.size() < 5:
		return -1.0
	var total := 0
	for i in range(1, p.size()):
		total += int(p[i])
	var idle := int(p[4]) + (int(p[5]) if p.size() > 5 else 0)
	var usage := -1.0
	if _last_total > 0 and total > _last_total:
		usage = 100.0 * (1.0 - float(idle - _last_idle) / float(total - _last_total))
	_last_total = total
	_last_idle = idle
	return clampf(usage, -1.0, 100.0)

func _read_ram_mb() -> float:
	var total := 0
	var avail := 0
	for line in _read_file("/proc/meminfo").split("\n"):
		if line.begins_with("MemTotal:"):
			total = int(line.get_slice(":", 1).strip_edges().split(" ")[0])
		elif line.begins_with("MemAvailable:"):
			avail = int(line.get_slice(":", 1).strip_edges().split(" ")[0])
	return float(total - avail) / 1024.0

func _cpu_temp() -> float:
	for d in DirAccess.get_directories_at("/sys/class/hwmon"):
		var base := "/sys/class/hwmon/" + d
		var n := _read_file(base + "/name").strip_edges()
		if n == "k10temp" or n == "coretemp" or n == "zenpower":
			var t := _read_file(base + "/temp1_input").strip_edges()
			if t != "":
				return float(t.to_int()) / 1000.0
	return -1.0

# {util: 0-100 or -1, temp: °C or -1}. NVIDIA through nvidia-smi, AMD through sysfs.
func _gpu() -> Dictionary:
	var out := {"util": -1.0, "temp": -1.0}
	var cards: PackedStringArray = DirAccess.get_directories_at("/sys/class/drm") if DirAccess.dir_exists_absolute("/sys/class/drm") else PackedStringArray()
	for card in cards:
		if not card.begins_with("card") or card.contains("-"):
			continue
		var dev := "/sys/class/drm/" + card + "/device"
		var busy := _read_file(dev + "/gpu_busy_percent").strip_edges()
		if busy != "":
			out["util"] = float(busy.to_int())
			if DirAccess.dir_exists_absolute(dev + "/hwmon"):
				for h in DirAccess.get_directories_at(dev + "/hwmon"):
					var t := _read_file(dev + "/hwmon/" + h + "/temp1_input").strip_edges()
					if t != "":
						out["temp"] = float(t.to_int()) / 1000.0
			return out
	var res := []
	if OS.execute("nvidia-smi", ["--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"], res) == 0 and res.size() > 0:
		var p := str(res[0]).strip_edges().split(",")
		if p.size() >= 2:
			out["util"] = float(p[0].strip_edges().to_int())
			out["temp"] = float(p[1].strip_edges().to_int())
	return out

# ---------- A quick look right now (the live info bar) ----------
var _live_total := 0
var _live_idle := 0

## CPU use since the last call (0-100, -1 the first time) and RAM in use (GB).
func live() -> Dictionary:
	var p := _read_file("/proc/stat").split("\n")[0].split(" ", false)
	var usage := -1.0
	if p.size() >= 5:
		var total := 0
		for i in range(1, p.size()):
			total += int(p[i])
		var idle := int(p[4]) + (int(p[5]) if p.size() > 5 else 0)
		if _live_total > 0 and total > _live_total:
			usage = clampf(100.0 * (1.0 - float(idle - _live_idle) / float(total - _live_total)), 0.0, 100.0)
		_live_total = total
		_live_idle = idle
	return {"cpu": usage, "ram_gb": _read_ram_mb() / 1024.0}

## GPU use and temperature right now. Slow (it may start nvidia-smi): call from a worker thread.
func gpu_now() -> Dictionary:
	return _gpu()

# ---------- Reading back ----------
## Summaries for games with data, most recently played first.
## Each: {appid, title, minutes, cpu, gpu (or -1), ram_gb, cpu_t (or -1), gpu_t (or -1), peak_cpu}
func summaries(limit := 6) -> Array:
	_load()
	var list: Array = []
	for id in _data:
		var e: Dictionary = _data[id]
		var n := int(e.get("n", 0))
		if n < 2:
			continue
		list.append({
			"appid": id, "title": str(e.get("title", id)), "last": int(e.get("last", 0)),
			"minutes": roundi(n * INTERVAL / 60.0), "cpu": float(e["cpu"]) / n,
			"gpu": (float(e["gpu"]) / int(e["n_gpu"])) if int(e.get("n_gpu", 0)) > 0 else -1.0,
			"ram_gb": float(e["ram"]) / n / 1024.0,
			"cpu_t": (float(e["cpu_t"]) / int(e["n_cpu_t"])) if int(e.get("n_cpu_t", 0)) > 0 else -1.0,
			"gpu_t": (float(e["gpu_t"]) / int(e["n_gpu_t"])) if int(e.get("n_gpu_t", 0)) > 0 else -1.0,
			"peak_cpu": float(e.get("peak_cpu", 0.0))})
	list.sort_custom(func(a, b): return a["last"] > b["last"])
	return list.slice(0, limit)

## Facts about this PC, as [label, value] pairs. Read once and kept.
func system_info(steam_dir: String) -> Array:
	if not _info.is_empty():
		_info["uptime"] = _uptime()
		return _pairs()
	var cpu := ""
	for line in _read_file("/proc/cpuinfo").split("\n"):
		if line.begins_with("model name"):
			cpu = line.get_slice(":", 1).strip_edges()
			break
	cpu = cpu.replace("(R)", "").replace("(TM)", "").replace("  ", " ")
	var cores := 0
	for line in _read_file("/proc/cpuinfo").split("\n"):
		if line.begins_with("processor"):
			cores += 1
	# Every graphics chip, not just the first one lspci lists. On a laptop with two (Intel + NVIDIA) the
	# first is the weak one, so the strong one is shown first and the other in brackets.
	var gpu := ""
	var out := []
	var gpus: Array = []
	if OS.execute("lspci", ["-mm"], out) == 0 and out.size() > 0:
		for line in str(out[0]).split("\n"):
			if line.contains("VGA compatible") or line.contains("3D controller") or line.contains("Display controller"):
				var q := line.split("\"")
				if q.size() >= 6:
					var name := q[5]
					if q[3].contains("NVIDIA") and not name.contains("NVIDIA"):
						name = "NVIDIA " + name
					elif q[3].contains("AMD") and not name.contains("AMD"):
						name = "AMD " + name
					elif q[3].contains("Intel") and not name.contains("Intel"):
						name = "Intel " + name
					gpus.append(name)
	gpus.sort_custom(func(a, b): return _gpu_rank(str(a)) < _gpu_rank(str(b)))
	if not gpus.is_empty():
		gpu = str(gpus[0])
		if gpus.size() > 1:
			gpu += " (+ " + str(gpus[1]) + ")"
	var mem_kb := 0
	for line in _read_file("/proc/meminfo").split("\n"):
		if line.begins_with("MemTotal:"):
			mem_kb = int(line.get_slice(":", 1).strip_edges().split(" ")[0])
	var os_name := ""
	for line in _read_file("/etc/os-release").split("\n"):
		if line.begins_with("PRETTY_NAME="):
			os_name = line.get_slice("=", 1).replace("\"", "")
	var kernel := []
	OS.execute("uname", ["-r"], kernel)
	var disk := []
	var disk_text := ""
	if OS.execute("df", ["-B1", "--output=avail,size", steam_dir], disk) == 0 and disk.size() > 0:
		var lines := str(disk[0]).strip_edges().split("\n")
		if lines.size() >= 2:
			var parts := lines[1].strip_edges().split(" ", false)
			if parts.size() >= 2:
				disk_text = "%d GB free of %d GB" % [roundi(float(parts[0]) / 1073741824.0), roundi(float(parts[1]) / 1073741824.0)]
	_info = {"cpu": "%s (%d threads)" % [cpu, cores] if cpu != "" else "-", "gpu": gpu if gpu != "" else "-",
		"ram": "%d GB" % roundi(mem_kb / 1048576.0), "os": os_name if os_name != "" else "Linux",
		"kernel": str(kernel[0]).strip_edges() if kernel.size() > 0 else "-", "disk": disk_text if disk_text != "" else "-",
		"uptime": _uptime()}
	return _pairs()

## Lower = stronger: a separate NVIDIA/AMD card comes before the Intel chip built into the processor.
func _gpu_rank(name: String) -> int:
	if name.contains("NVIDIA") or name.contains("AMD"):
		return 0
	return 1

## True when an NVIDIA card is installed and its driver is loaded (so games can be sent to it).
static func nvidia_ready() -> bool:
	return FileAccess.file_exists("/proc/driver/nvidia/version")

## Environment that makes a program use the NVIDIA card on a laptop that also has an Intel chip
## ("PRIME render offload"). Empty on a PC without it, or when ~/.config/tephra/no_gpu_offload exists.
static func gpu_env() -> Array:
	if not nvidia_ready() or FileAccess.file_exists(OS.get_environment("HOME") + "/.config/tephra/no_gpu_offload"):
		return []
	return ["__NV_PRIME_RENDER_OFFLOAD=1", "__GLX_VENDOR_LIBRARY_NAME=nvidia", "__VK_LAYER_NV_optimus=NVIDIA_only"]

func _pairs() -> Array:
	return [["Processor", _info["cpu"]], ["Graphics", _info["gpu"]], ["Memory", _info["ram"]], ["Storage", _info["disk"]],
		["System", _info["os"]], ["Kernel", _info["kernel"]], ["Up for", _info["uptime"]]]

func _uptime() -> String:
	var s := int(float(_read_file("/proc/uptime").split(" ")[0]))
	var h := s / 3600
	var m := (s % 3600) / 60
	return ("%d h %d min" % [h, m]) if h > 0 else ("%d min" % m)
