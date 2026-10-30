extends Node
## Tephra's own sounds and background music. Nothing is loaded from a file: every sound is calculated
## here as a list of numbers and handed to Godot as audio. That keeps the update to plain .gd files
## and lets us tune a sound by changing a few numbers.
##
##   Sfx.play("tick")            a short interface sound (tick, confirm, back, open, launch)
##   Sfx.set_music("home", true) a slow background pad; "" or false fades it out
##
##   Sfx.set_distant(true)       the music steps back (softer and duller), e.g. behind the control center
##
## Volumes come from Settings (sfx_volume and music_volume, 0 to 100) and can be changed any time.
## Every sound is made to peak at the same level (PEAK), so the sliders alone decide how loud they are,
## and 50-60% sits clearly under a game instead of needing 100%.

const Settings = preload("res://settings.gd")
const Themes = preload("res://themes.gd")

const RATE := 44100        # sample rate of the short sounds
const MUSIC_RATE := 22050  # the music is soft, so half the rate is plenty (and half the work)
const LOOP_SECONDS := 16   # length of one music loop
const PEAK := 0.7          # every sound and the music loop are scaled so their loudest moment is this
const MUSIC_DEFAULT := 50
const SFX_DEFAULT := 60
# "Distant" music (control center open): this much quieter, and with the highs rolled off like music
# heard from the next room. DISTANT_SECONDS is how long the step back (and forward again) takes.
const DISTANT_DB := -9.0
const DISTANT_CUTOFF := 1400.0
const NEAR_CUTOFF := 20000.0
const DISTANT_SECONDS := 0.6

var _sfx := {}             # name -> AudioStreamWAV
var _sfx_building := false  # the effects are being made on a worker thread: play() stays silent until then
var _sfx_task := -1
var _themes := {}          # theme name -> a seamless loop (made here, or your own file)
var _pool: Array = []      # a few players, so quick sounds can overlap
var _pool_i := 0
var _music: AudioStreamPlayer
var _theme := ""           # the theme that is playing (or fading in)
var _want_theme := ""
var _building := {}        # theme name -> worker task id while it is being calculated
var _tween: Tween
var _distant := false
var _distant_k := 0.0       # 0 = right here, 1 = fully stepped back; glides between the two
var _bus := -1              # the "Music" audio bus (with the low-pass filter on it)
var _lowpass: AudioEffectLowPassFilter

# Each theme is a slow chord loop: four chords of four seconds, each a list of note frequencies in Hz.
const THEMES := {
	# Home: calm and a little dreamy (D minor 9, B-flat major 7, G minor 7, A suspended).
	"home": [
		[73.42, 146.83, 220.00, 261.63, 329.63],
		[58.27, 116.54, 174.61, 233.08, 293.66],
		[49.00, 98.00, 146.83, 196.00, 233.08],
		[55.00, 110.00, 164.81, 220.00, 293.66],
	],
	# Library: brighter, like opening a door (C major 9, A minor 7, F major 7, G 6).
	"library": [
		[65.41, 130.81, 196.00, 246.94, 293.66],
		[55.00, 110.00, 164.81, 196.00, 261.63],
		[43.65, 87.31, 130.81, 164.81, 220.00],
		[49.00, 98.00, 146.83, 196.00, 246.94],
	],
}

func _ready() -> void:
	_migrate_volumes()
	_make_bus()
	prepare_intro()
	_prune_cache()
	if _load_sfx_cache():
		_apply_capture_files()
	else:
		# Made once per theme, then kept on disk, so changing theme doesn't make them again. The first time
		# it is made on a worker thread, so switching to a theme never stops the screen to calculate sounds
		# (the effects stay silent for the few seconds it takes).
		_sfx_building = true
		_sfx_task = WorkerThreadPool.add_task(func() -> void:
			_make_sfx()
			_sfx_made.call_deferred())
	_build_theme(Themes.music())  # start calculating the song now so it is ready when the menu is
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -60.0
	_music.bus = "Music"
	add_child(_music)

## v0.23.0 made every sound louder at the same slider value. Anyone who had to turn the sliders up to
## 100% would now be blasted, so the two sliders are set back to the new middle values once.
func _migrate_volumes() -> void:
	if int(Settings.get_value("audio_levels", 1)) >= 2:
		return
	Settings.set_value("music_volume", MUSIC_DEFAULT)
	Settings.set_value("sfx_volume", SFX_DEFAULT)
	Settings.set_value("audio_levels", 2)

func _sfx_made() -> void:
	WorkerThreadPool.wait_for_task_completion(_sfx_task)
	_sfx_task = -1
	_sfx_building = false
	_save_sfx_cache()
	_apply_capture_files()  # after saving: the cache keeps the made sounds

## A bus of its own for the music, so it can be made "distant" without touching the other sounds.
func _make_bus() -> void:
	_bus = AudioServer.get_bus_index("Music")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "Music")
		AudioServer.set_bus_send(_bus, "Master")
	# The bus outlives this node (changing theme rebuilds every screen), so its filter is reused.
	if AudioServer.get_bus_effect_count(_bus) > 0 and AudioServer.get_bus_effect(_bus, 0) is AudioEffectLowPassFilter:
		_lowpass = AudioServer.get_bus_effect(_bus, 0)
	else:
		_lowpass = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(_bus, _lowpass)
	_lowpass.cutoff_hz = NEAR_CUTOFF
	AudioServer.set_bus_volume_db(_bus, 0.0)

## true: the music steps back (softer, duller); false: it comes forward again. Both glide.
func set_distant(on: bool) -> void:
	_distant = on

## Scales a sound so its loudest sample is PEAK.
func _normalize(a: PackedFloat32Array) -> PackedFloat32Array:
	var pk := 0.0
	for x in a:
		pk = maxf(pk, absf(x))
	if pk > 0.0:
		var k := PEAK / pk
		for i in a.size():
			a[i] *= k
	return a

# ---------- Turning numbers into audio ----------
## A list of samples between -1 and 1 becomes an AudioStreamWAV (16-bit, mono).
func _to_stream(samples: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	return _bytes_stream(_to_bytes(samples), rate, loop)

## 16-bit sound data for samples between -1 and 1 (slow for a whole song: done on a worker thread there).
static func _to_bytes(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return bytes

static func _bytes_stream(bytes: PackedByteArray, rate: int, loop := false) -> AudioStreamWAV:
	var samples_n := bytes.size() / 2
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = bytes
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = samples_n
	return st

# ---------- Sound cache ----------
# Every sound and song is calculated from code, which takes a few seconds (the music most of all). The results
# are kept in user://sound_cache, one set per theme, so the next start or theme change just reads them back.
# The names carry sfx.gd's modified time: an update that changes the sounds makes them fresh again.
const CACHE_DIR := "user://sound_cache/"

static func _stamp() -> int:
	return FileAccess.get_modified_time("res://sfx.gd")

func _cache_path(what: String) -> String:
	return CACHE_DIR + "%s-%s-%d.bin" % [what, Themes.id(), _stamp()]

## Sounds made by an older sfx.gd are deleted.
func _prune_cache() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var tag := "-%d.bin" % _stamp()
	for f in DirAccess.get_files_at(CACHE_DIR):
		if not f.ends_with(tag):
			DirAccess.remove_absolute(CACHE_DIR + f)

static func _read_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

static func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()

func _load_sfx_cache() -> bool:
	var raw := _read_bytes(_cache_path("sfx"))
	if raw.is_empty():
		return false
	var d = bytes_to_var(raw)
	if not d is Dictionary or d.is_empty():
		return false
	for k in d:
		var e: Array = d[k]
		var st := _bytes_stream(e[1], int(e[0]), int(e[2]) != AudioStreamWAV.LOOP_DISABLED)
		_sfx[k] = st
	return true

func _save_sfx_cache() -> void:
	var d := {}
	for k in _sfx:
		var st = _sfx[k]
		if not st is AudioStreamWAV or (st as AudioStreamWAV).format != AudioStreamWAV.FORMAT_16_BITS or (st as AudioStreamWAV).stereo:
			return  # something unusual in the set: leave it uncached rather than store it wrong
		d[k] = [st.mix_rate, st.data, st.loop_mode]
	_write_bytes(_cache_path("sfx"), var_to_bytes(d))

## A sine wave where one full turn is a phase of 1.0 (so frequency * seconds is the phase).
func _lookup(phase: float) -> float:
	return sin(TAU * phase)

## One soft "bell" note: a fundamental plus a quieter octave, with a quick start and a smooth fade.
## Written into `out` starting at second `at`, so notes can be chained into a little tune.
func _bell(out: PackedFloat32Array, at: float, freq: float, length: float, level: float, decay: float) -> void:
	var start := int(at * RATE)
	var n := int(length * RATE)
	for i in n:
		var j := start + i
		if j >= out.size():
			return
		var t := float(i) / RATE
		var env := minf(t / 0.004, 1.0) * exp(-decay * t)
		var ph := freq * t
		out[j] += level * env * (_lookup(ph) + 0.3 * _lookup(ph * 2.0) + 0.08 * _lookup(ph * 3.0))

func _blank(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(seconds * RATE))
	return a

func _make_sfx() -> void:
	# tick: a tiny dry click, the cursor moving.
	var tick := _blank(0.045)
	for i in tick.size():
		var t := float(i) / RATE
		tick[i] = 0.30 * exp(-110.0 * t) * _lookup(1500.0 * t) + 0.08 * exp(-200.0 * t) * _lookup(3100.0 * t)
	_sfx["tick"] = _to_stream(_normalize(tick), RATE)

	# confirm: two rising notes.
	var conf := _blank(0.38)
	_bell(conf, 0.0, 660.0, 0.14, 0.26, 18.0)
	_bell(conf, 0.07, 990.0, 0.30, 0.26, 12.0)
	_sfx["confirm"] = _to_stream(_normalize(conf), RATE)

	# back: two falling notes.
	var back := _blank(0.30)
	_bell(back, 0.0, 740.0, 0.12, 0.24, 20.0)
	_bell(back, 0.06, 494.0, 0.22, 0.24, 14.0)
	_sfx["back"] = _to_stream(_normalize(back), RATE)

	# open: one soft bell, for menus and notifications.
	var open := _blank(0.5)
	_bell(open, 0.0, 880.0, 0.45, 0.20, 7.0)
	_bell(open, 0.0, 1318.5, 0.35, 0.10, 9.0)
	_sfx["open"] = _to_stream(_normalize(open), RATE)

	# panel: a quick rising three-note shimmer, for the control center opening.
	var panel := _blank(0.55)
	_bell(panel, 0.0, 587.3, 0.3, 0.17, 10.0)
	_bell(panel, 0.055, 880.0, 0.32, 0.13, 9.0)
	_bell(panel, 0.11, 1174.7, 0.4, 0.10, 8.0)
	_sfx["panel"] = _to_stream(_normalize(panel), RATE)

	# shutter: two dry mechanical clicks (a short burst of noise with a ring in it), like a camera.
	var shut := _blank(0.16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in shut.size():
		var t := float(i) / RATE
		var n1 := rng.randf_range(-1.0, 1.0)
		var s1 := exp(-420.0 * t) * (0.55 * n1 + 0.45 * _lookup(2300.0 * t))
		var t2 := t - 0.062
		var s2 := 0.0
		if t2 >= 0.0:
			s2 = exp(-300.0 * t2) * (0.5 * rng.randf_range(-1.0, 1.0) + 0.5 * _lookup(1400.0 * t2))
		shut[i] = 0.5 * (s1 + 0.85 * s2)
	_sfx["shutter"] = _to_stream(_normalize(shut), RATE)

	# trash: paper being crumpled and dropped in the bin. Lots of tiny random crackles (short bursts
	# of bright, high-passed noise, thick in the middle and thinning out), then a soft dull landing.
	var trash := _blank(0.5)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 11
	var gate := PackedFloat32Array()
	gate.resize(trash.size())
	for c in 70:
		var at := rng2.randf_range(0.0, 0.34)
		if rng2.randf() < 0.5:
			at = 0.17 + (at - 0.17) * 0.55  # bunch them up in the middle of the crumple
		var amp := rng2.randf_range(0.25, 1.0)
		var blen := rng2.randf_range(0.002, 0.012)
		var i0 := int(at * RATE)
		for j in int(blen * 3.0 * RATE):
			if i0 + j < gate.size():
				gate[i0 + j] += amp * exp(-float(j) / (blen * RATE))
	var lo := 0.0
	var lo2 := 0.0
	var prev := 0.0
	for i in trash.size():
		var t := float(i) / RATE
		var n := rng2.randf_range(-1.0, 1.0)
		lo += 0.55 * (n - lo)                # take the harshest fizz off the top
		var hp := lo - prev                  # and the rumble off the bottom: crisp, papery
		prev = lo
		var bed := 0.12 * minf(t / 0.03, 1.0) * maxf(1.0 - t / 0.36, 0.0)  # a faint rustle under it all
		var s := hp * (minf(gate[i], 1.4) + bed)
		var tb := t - 0.38
		if tb >= 0.0:
			lo2 += 0.06 * (n - lo2)          # the landing: dull, soft noise
			s += 2.2 * lo2 * minf(tb / 0.006, 1.0) * exp(-30.0 * tb)
		trash[i] = s
	_sfx["trash"] = _to_stream(_normalize(trash), RATE)

	# launch: a rising swell, for starting a game. The pitch climbs smoothly; the phase is the running total
	# (integral) of the pitch, which is what keeps a sweep free of clicks.
	var launch := _blank(0.9)
	var k := 1.6 / 0.9  # octaves climbed per second
	for i in launch.size():
		var t := float(i) / RATE
		var rise := t / 0.9
		var env := sin(PI * minf(rise, 1.0)) * (0.3 + 0.7 * rise)
		var ph := 220.0 * (pow(2.0, k * t) - 1.0) / (k * log(2.0))
		launch[i] = 0.22 * env * (_lookup(ph) + 0.6 * _lookup(ph * 1.5) + 0.4 * _lookup(ph * 2.0))
	_sfx["launch"] = _to_stream(_normalize(launch), RATE)

	# options: Triangle on a game. A small "tk" then one bright bell, like a card being flipped over.
	var opt := _blank(0.36)
	_click(opt, 0.0, 2600.0, 0.4)
	_bell(opt, 0.03, 1174.7, 0.3, 0.2, 11.0)
	_bell(opt, 0.03, 1760.0, 0.2, 0.07, 14.0)
	_sfx["options"] = _to_stream(_normalize(opt), RATE)
	if Themes.sounds() == "soft":
		_make_soft_sfx()
	elif Themes.sounds() == "aero":
		_make_aero_sfx()
	elif Themes.sounds() == "wave":
		_make_wave_sfx()
	elif Themes.sounds() == "gunmetal":
		_make_gunmetal_sfx()
	elif Themes.sounds() == "neon":
		_make_neon_sfx()
	elif Themes.sounds() == "gothic":
		_make_gothic_sfx()
	elif Themes.sounds() == "mold":
		_make_mold_sfx()
	elif Themes.sounds() == "wood":
		_make_wood_sfx()
	elif Themes.sounds() == "retro":
		_make_retro_sfx()
	_make_sting()
	_make_update_sfx()
	_make_capture_sfx()

## Recording sounds, the same in every theme, and each clearly not the screenshot "shutter":
##   rec_start: a soft low thump, then two quick rising beeps (like a camcorder starting).
##   rec_stop:  the same two beeps falling, then a soft click (the tape stopping).
func _make_capture_sfx() -> void:
	var start := _blank(0.42)
	_bop(start, 0.0, 110.0, 0.18, 0.30)
	_bop(start, 0.07, 880.0, 0.12, 0.30)
	_bop(start, 0.19, 1318.5, 0.22, 0.30)
	_sfx["rec_start"] = _to_stream(_normalize(start), RATE)
	var stop := _blank(0.42)
	_bop(stop, 0.0, 1318.5, 0.12, 0.28)
	_bop(stop, 0.12, 880.0, 0.20, 0.28)
	var click := int(0.30 * RATE)
	for i in int(0.03 * RATE):
		if click + i < stop.size():
			var t := float(i) / RATE
			stop[click + i] += 0.35 * exp(-260.0 * t) * _lookup(1900.0 * t)
	_sfx["rec_stop"] = _to_stream(_normalize(stop), RATE)

## Your own capture sounds win over the ones made here: in ~/.config/tephra/sounds/, screenshot, record-start and
## record-stop (.ogg, .wav or .mp3). Loaded after the made sounds are cached, so the cache keeps the made ones.
const CAPTURE_FILES := {"shutter": "screenshot", "rec_start": "record-start", "rec_stop": "record-stop"}

func _apply_capture_files() -> void:
	for key in CAPTURE_FILES:
		var base := OS.get_environment("HOME") + INTRO_DIR + str(CAPTURE_FILES[key]) + "."
		if FileAccess.file_exists(base + "ogg"):
			_sfx[key] = AudioStreamOggVorbis.load_from_file(base + "ogg")
		elif FileAccess.file_exists(base + "wav"):
			_sfx[key] = AudioStreamWAV.load_from_file(base + "wav")
		elif FileAccess.file_exists(base + "mp3"):
			_sfx[key] = AudioStreamMP3.load_from_file(base + "mp3")

## The "Update available" sound: the same in every theme. A calm, rising four-note chime (C, E, G, C) with a warm low
## note under it. To use your own, put update.ogg, update.wav or update.mp3 in ~/.config/tephra/sounds/.
func _make_update_sfx() -> void:
	var base := OS.get_environment("HOME") + INTRO_DIR + "update."
	if FileAccess.file_exists(base + "ogg"):
		_sfx["update"] = AudioStreamOggVorbis.load_from_file(base + "ogg")
		return
	if FileAccess.file_exists(base + "wav"):
		_sfx["update"] = AudioStreamWAV.load_from_file(base + "wav")
		return
	if FileAccess.file_exists(base + "mp3"):
		_sfx["update"] = AudioStreamMP3.load_from_file(base + "mp3")
		return
	var up := _blank(1.4)
	_bop(up, 0.0, 130.8, 1.1, 0.16)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for k in notes.size():
		var last: bool = k == notes.size() - 1
		_bop(up, 0.1 + k * 0.17, notes[k], 0.9 if last else 0.4, 0.26)
		_bop(up, 0.1 + k * 0.17, notes[k] * 2.0, 0.5 if last else 0.2, 0.05)
	_sfx["update"] = _to_stream(_normalize(up), RATE)

## The sound a theme makes as it is put on (Settings > Themes, or the control center).
func _make_sting() -> void:
	var st := _blank(1.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	match Themes.id():
		"volcanic":
			# A rising rumble you can hear on laptop speakers (mid-low, not just sub-bass), then three heavy stone
			# knocks with a hollow ring. Nothing hissy.
			for i in st.size():
				var t := float(i) / RATE
				var env := smoothstep(0.0, 0.45, t) * exp(-maxf(t - 0.45, 0.0) * 1.6)
				st[i] += 0.2 * env * (_lookup(98.0 * t) + 0.8 * _lookup(147.0 * t) + 0.6 * _lookup(196.0 * t) + 0.35 * _lookup(293.7 * t))
			for k in [[0.45, 0.7], [0.85, 0.5], [1.2, 0.35]]:
				var at: float = k[0]
				_stone(st, RATE, at, float(k[1]))
				for i in int(0.5 * RATE):
					var t2 := float(i) / RATE
					var j := int(at * RATE) + i
					if j < st.size():
						st[j] += float(k[1]) * 0.5 * exp(-t2 * 9.0) * minf(t2 / 0.003, 1.0) * (_lookup(130.8 * t2) + 0.5 * _lookup(261.6 * t2) + 0.25 * _lookup(392.0 * t2))
		"sleek":
			# A glass tap and a thin metallic ring that dies away: cold and clean.
			for i in st.size():
				var t := float(i) / RATE
				st[i] = 0.2 * smoothstep(0.0, 0.004, t) * exp(-t * 3.0) * (_lookup(2093.0 * t) + 0.5 * _lookup(3136.0 * t + 0.1))
			_bell(st, 0.3, 1568.0, 1.4, 0.1, 3.0)
		"ps2":
			# A low swell, then a few glassy pings falling away.
			for i in st.size():
				var t := float(i) / RATE
				st[i] += 0.2 * smoothstep(0.0, 0.5, t) * exp(-maxf(t - 0.5, 0.0) * 2.0) * (_lookup(73.42 * t) + 0.6 * _lookup(110.0 * t))
			for k in [[0.4, 1568.0], [0.6, 2093.0], [0.8, 1760.0], [1.0, 1175.0]]:
				_bell(st, float(k[0]), float(k[1]), 1.0, 0.16, 3.0)
		"frutiger":
			# A breath of air and four clean steady tones rising (no bloops, no slides).
			_air(st, 0.0, 0.9, 0.3, 0.05, 0.4)
			var notes := [784.0, 988.0, 1175.0, 1568.0]
			for k in notes.size():
				_pip(st, k * 0.1, float(notes[k]), 0.4 if k == 3 else 0.2, 0.18)
		"wave":
			# Silk: a wide Lydian chord opening out, then three bells drifting down.
			for i in int(1.4 * RATE):
				var t := float(i) / RATE
				var env := smoothstep(0.0, 0.5, t) * exp(-maxf(t - 0.5, 0.0) * 1.8)
				st[i] += 0.07 * env * (_lookup(146.83 * t) + _lookup(220.0 * t) + 0.7 * _lookup(369.99 * t) + 0.6 * _lookup(554.37 * t))
			for k in [[0.25, 739.99], [0.55, 554.37], [0.9, 369.99]]:
				_soft(st, float(k[0]), float(k[1]), 1.4, 0.16)
		"gunmetal":
			# The slide racked, then one heavy steel ring over a low, gritty chord.
			_grng.seed = 5
			for i in int(1.5 * RATE):
				var t := float(i) / RATE
				var env := smoothstep(0.0, 0.25, t) * exp(-maxf(t - 0.25, 0.0) * 2.4)
				st[i] += 0.12 * env * tanh(2.5 * (_lookup(55.0 * t) + 0.7 * _lookup(82.41 * t) + 0.4 * _lookup(110.0 * t)))
			_snap(st, 0.0, 0.7)
			_snap(st, 0.15, 1.0)
			_steel(st, 0.18, 233.08, 0.35, 3.0)
			_steel(st, 0.18, 698.0, 0.12, 6.0)
		"gothic":
			# One deep cathedral bell over a low organ chord in D minor, its hum hanging in the cold air.
			for f in [73.42, 146.83, 174.61, 220.0, 293.66]:
				_organ(st, 0.0, f, 1.7, 0.09, RATE, false)
			_toll(st, 0.0, 146.83, 1.8, 0.5, RATE, false)
		"wood":
			# A morning: a flute phrase, a few marimba notes, a small bird and one hollow knock.
			_flute(st, 0.0, _hz(69), 0.6, 0.25)
			_flute(st, 0.35, _hz(74), 0.9, 0.25)
			for k in 4:
				_marimba(st, 0.5 + k * 0.14, _hz(74 + [0, 4, 7, 12][k]), 1.0, 0.2)
			_chirp(st, 1.2, 3200.0, 4300.0, 0.08, 3)
			_knock(st, 0.0, 200.0, 0.4)
		"retro":
			# The start-up jingle: a short rising run of square beeps and a long bright note.
			for k in 5:
				_sq(st, k * 0.09, _hz(60 + [0, 4, 7, 12, 16][k]), 0.1, 0.26, 0.5)
			_sq(st, 0.5, _hz(79), 0.9, 0.26, 0.25)
			_tri(st, 0.5, _hz(43), 0.9, 0.3)
		"mold":
			# A low, uneasy swell (two notes rubbing a half step apart), a door-creak bend, and one drip into the quiet.
			for i in st.size():
				var t := float(i) / RATE
				var env := smoothstep(0.0, 0.6, t) * exp(-maxf(t - 0.6, 0.0) * 2.2)
				st[i] += 0.16 * env * (_lookup(55.0 * t) + 0.8 * _lookup(58.27 * t) + 0.4 * _lookup(110.0 * t))
			_creak(st, 0.15, 0.8, 0.18)
			_plip(st, 1.1, 0.35)
		"neon":
			# A big 80s hit: kick and gated snare under a wide synth chord, and a quick arpeggio climbing over it.
			_grng.seed = 6
			_kick80(st, 0.0, 0.9)
			_snare80(st, 0.0, 0.6)
			for f in [174.61, 349.23, 415.30, 523.25, 622.25]:
				_syn(st, 0.0, f, 1.5, 0.22, 0.5, false, 0.02)
			for k in 6:
				_syn(st, 0.12 + k * 0.09, [698.46, 830.61, 1046.5, 1244.5, 1396.9, 1661.2][k], 0.16, 0.18, 0.7, true)
		"channels":
			# An easy, unhurried climb through an F major 7 chord, landing softly.
			var run := [349.23, 440.0, 523.25, 659.25]
			for k in run.size():
				_bop(st, k * 0.11, run[k], 0.4, 0.16)
			for f in [523.25, 659.25, 880.0]:
				_bop(st, 0.5, f, 1.1, 0.09)
		_:
			# Tephra: the start of the intro, short: a wide soft chord and two falling bell notes.
			for i in int(1.2 * RATE):
				var t := float(i) / RATE
				var env := smoothstep(0.0, 0.25, t) * exp(-t * 2.0)
				st[i] = 0.08 * env * (_lookup(146.83 * t) + _lookup(220.0 * t) + 0.6 * _lookup(329.63 * t) + 0.6 * _lookup(369.99 * t))
			_bell(st, 0.15, 1174.66, 1.4, 0.2, 3.0)
			_bell(st, 0.35, 880.0, 1.4, 0.18, 3.0)
	_sfx["sting"] = _to_stream(_normalize(st), RATE)

## The Channels theme's sounds: rounder, softer and a little quicker. Pure sine "bops" that drop a
## touch in pitch as they start (like a soft plastic button), and short happy chimes.
func _bop(out: PackedFloat32Array, at: float, freq: float, length: float, level: float) -> void:
	var start := int(at * RATE)
	for i in int(length * RATE):
		var j := start + i
		if j >= out.size():
			return
		var t := float(i) / RATE
		var env := minf(t / 0.003, 1.0) * exp(-t * 6.0 / length)
		var f := freq * (1.0 + 0.25 * exp(-t * 90.0))  # starts a little high and settles: a soft "bop"
		out[j] += level * env * (_lookup(f * t) + 0.12 * _lookup(f * 2.0 * t))

## A switch click: a very short bright tick on top of a small, dull thock. No ringing.
func _click(out: PackedFloat32Array, at: float, freq: float, level: float) -> void:
	var start := int(at * RATE)
	for i in int(0.04 * RATE):
		var j := start + i
		if j >= out.size():
			return
		var t := float(i) / RATE
		out[j] += level * (exp(-t * 700.0) * _lookup(freq * t) + 0.8 * exp(-t * 170.0) * _lookup(240.0 * t))

## One soft round note: a sine with a faint second harmonic, a slow-ish attack (no "tink") and a smooth fade.
func _soft(out: PackedFloat32Array, at: float, freq: float, length: float, level: float) -> void:
	var start := int(at * RATE)
	for i in int(length * RATE):
		var j := start + i
		if j >= out.size():
			return
		var t := float(i) / RATE
		var env := smoothstep(0.0, 0.018, t) * exp(-t * 4.5 / length)
		out[j] += level * env * (_lookup(freq * t) + 0.14 * _lookup(freq * 2.0 * t))

## Wave's sounds: soft, round and warm, like a finger pressing a cushion of glass. No sharp attacks, nothing high.
func _make_wave_sfx() -> void:
	var tick := _blank(0.2)
	_soft(tick, 0.0, 523.25, 0.18, 0.2)
	_sfx["tick"] = _to_stream(_normalize(tick), RATE)
	var conf := _blank(0.55)
	_soft(conf, 0.0, 392.0, 0.45, 0.2)
	_soft(conf, 0.07, 587.33, 0.45, 0.16)
	_sfx["confirm"] = _to_stream(_normalize(conf), RATE)
	var back := _blank(0.45)
	_soft(back, 0.0, 587.33, 0.35, 0.18)
	_soft(back, 0.08, 440.0, 0.4, 0.18)
	_sfx["back"] = _to_stream(_normalize(back), RATE)
	var open := _blank(0.8)
	_swell(open, [196.0, 293.66, 392.0], 0.05, 0.3)
	_soft(open, 0.08, 659.25, 0.6, 0.15)
	_soft(open, 0.16, 987.77, 0.5, 0.07)
	_sfx["open"] = _to_stream(_normalize(open), RATE)
	var page := _blank(0.3)
	_soft(page, 0.0, 698.46, 0.25, 0.15)
	_soft(page, 0.06, 523.25, 0.25, 0.12)
	_sfx["page"] = _to_stream(_normalize(page), RATE)
	var panel := _blank(0.7)
	for k in 3:
		_soft(panel, k * 0.08, [392.0, 587.33, 783.99][k], 0.5, 0.15)
	_sfx["panel"] = _to_stream(_normalize(panel), RATE)
	var launch := _blank(1.2)
	_swell(launch, [196.0, 293.66, 392.0], 0.05, 0.5)
	for k in 4:
		_soft(launch, k * 0.1, [293.66, 392.0, 587.33, 783.99][k], 0.8, 0.16)
	_sfx["launch"] = _to_stream(_normalize(launch), RATE)
	var opt := _blank(0.5)
	_soft(opt, 0.0, 659.25, 0.4, 0.16)
	_soft(opt, 0.08, 987.77, 0.35, 0.08)
	_sfx["options"] = _to_stream(_normalize(opt), RATE)

## A soft low thump (no click): a sine that starts at 90 Hz and sinks, for impacts that are felt more than heard.
func _thump(out: PackedFloat32Array, at: float, level: float) -> void:
	var start := int(at * RATE)
	var ph := 0.0
	for i in int(0.9 * RATE):
		var j := start + i
		if j >= out.size():
			return
		var t := float(i) / RATE
		ph += (40.0 + 50.0 * exp(-t * 7.0)) / RATE
		out[j] += level * 0.4 * smoothstep(0.0, 0.01, t) * exp(-t * 4.5) * _lookup(ph)

## A glass tone: soft attack, with a quiet "air" partial that fades quickly.
func _crystal(out: PackedFloat32Array, at: float, freq: float, length: float, level: float) -> void:
	_soft(out, at, freq, length, level)
	_soft(out, at + 0.004, freq * 3.0, length * 0.35, level * 0.12)

## One raindrop: a short soft sine that drops a little in pitch, with a faint ring after it.
func _drop(out: PackedFloat32Array, at: float, freq: float, level: float) -> void:
	var start := int(at * RATE)
	var ph := 0.0
	for i in int(0.35 * RATE):
		var j := start + i
		if j >= out.size():
			return
		var t := float(i) / RATE
		ph += freq * (1.0 - 0.22 * (1.0 - exp(-t * 28.0))) / RATE
		out[j] += level * smoothstep(0.0, 0.004, t) * exp(-t * 16.0) * _lookup(ph)
	_soft(out, at + 0.01, freq * 0.5, 0.5, level * 0.35)

# ---------- Neon Coast: 80s synths ----------
## One synth note: two slightly detuned saws (or squares) through a soft low-pass that closes as the note fades, like an
## analog poly synth. cut = brightness (0..1). Wraps round the end when `wrap` (music loops).
func _syn(out: PackedFloat32Array, at: float, freq: float, length: float, level: float, cut := 0.5, square := false, \
		attack := 0.005, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var n := out.size()
	var p1 := 0.0
	var p2 := 0.37
	var lp := 0.0
	var lp2 := 0.0
	for i in int(length * rate):
		var j := start + i
		if j >= n:
			if not wrap:
				return
			j %= n
		var t := float(i) / rate
		p1 = fposmod(p1 + freq * 1.004 / rate, 1.0)
		p2 = fposmod(p2 + freq * 0.996 / rate, 1.0)
		var v: float
		if square:
			v = (1.0 if p1 < 0.5 else -1.0) + (1.0 if p2 < 0.5 else -1.0)
		else:
			v = (2.0 * p1 - 1.0) + (2.0 * p2 - 1.0)
		var env := minf(t / attack, 1.0) * (1.0 - smoothstep(length * 0.55, length, t))
		var k := clampf(cut * (0.35 + 0.65 * env) * 0.5, 0.01, 0.95)
		lp += k * (v - lp)
		lp2 += k * (lp - lp2)   # two poles: warm, not buzzy
		out[j] += level * 0.5 * env * lp2

## A drum-machine snare with a long, gated tail (the big 80s snare) or a soft kick.
func _snare80(out: PackedFloat32Array, at: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var n := out.size()
	var lp := 0.0
	for i in int(0.32 * rate):
		var j := start + i
		if j >= n:
			if not wrap:
				return
			j %= n
		var t := float(i) / rate
		lp += 0.45 * (_grng.randf_range(-1.0, 1.0) - lp)
		var gate := 1.0 - smoothstep(0.2, 0.3, t)
		out[j] += level * (0.55 * lp * (0.35 + 0.65 * exp(-t * 18.0)) * gate + 0.5 * exp(-t * 30.0) * _lookup(185.0 * t))

func _kick80(out: PackedFloat32Array, at: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var n := out.size()
	var ph := 0.0
	for i in int(0.4 * rate):
		var j := start + i
		if j >= n:
			if not wrap:
				return
			j %= n
		var t := float(i) / rate
		ph += (45.0 + 110.0 * exp(-t * 35.0)) / rate
		out[j] += level * exp(-t * 7.0) * _lookup(ph)

## Neon Coast's sounds: soft synth blips and chords, a little echo, nothing harsh.
func _make_neon_sfx() -> void:
	_grng.seed = 31
	# tick: a short, rounder blip a step lower than before, with a faint octave on top and a softer echo.
	var tick := _blank(0.12)
	_syn(tick, 0.0, 1174.66, 0.055, 0.5, 0.75, true)
	_syn(tick, 0.004, 2349.3, 0.03, 0.12, 0.8, true)
	_sfx["tick"] = _to_stream(_normalize(_echo(tick, 0.07, 0.18)), RATE)
	var conf := _blank(0.5)
	_syn(conf, 0.0, 880.0, 0.12, 0.5, 0.6, true)
	_syn(conf, 0.07, 1318.5, 0.25, 0.5, 0.6, true)
	_sfx["confirm"] = _to_stream(_normalize(_echo(conf, 0.11, 0.3)), RATE)
	var back := _blank(0.45)
	_syn(back, 0.0, 1318.5, 0.1, 0.5, 0.6, true)
	_syn(back, 0.07, 880.0, 0.22, 0.5, 0.5, true)
	_sfx["back"] = _to_stream(_normalize(_echo(back, 0.11, 0.3)), RATE)
	var open := _blank(1.0)
	for f in [349.23, 440.0, 523.25, 659.25]:
		_syn(open, 0.0, f, 0.7, 0.3, 0.45, false, 0.04)
	_sfx["open"] = _to_stream(_normalize(_echo(open, 0.16, 0.3)), RATE)
	var page := _blank(0.25)
	_syn(page, 0.0, 987.77, 0.06, 0.5, 0.7, true)
	_syn(page, 0.05, 1174.66, 0.08, 0.4, 0.7, true)
	_sfx["page"] = _to_stream(_normalize(_echo(page, 0.08, 0.25)), RATE)
	var panel := _blank(0.7)
	for k in 4:
		_syn(panel, k * 0.05, [523.25, 659.25, 783.99, 1046.5][k], 0.18, 0.4, 0.6, true)
	_sfx["panel"] = _to_stream(_normalize(_echo(panel, 0.12, 0.3)), RATE)
	var launch := _blank(1.6)
	_kick80(launch, 0.0, 0.8)
	_snare80(launch, 0.0, 0.5)
	for f in [174.61, 349.23, 440.0, 523.25, 698.46]:
		_syn(launch, 0.0, f, 1.2, 0.28, 0.5, false, 0.01)
	_sfx["launch"] = _to_stream(_normalize(_echo(launch, 0.2, 0.3)), RATE)
	var opt := _blank(0.35)
	_syn(opt, 0.0, 783.99, 0.08, 0.5, 0.6, true)
	_syn(opt, 0.06, 1567.98, 0.12, 0.35, 0.6, true)
	_sfx["options"] = _to_stream(_normalize(_echo(opt, 0.09, 0.25)), RATE)

# ---------- Gothic: organ, choir and bells ----------
## A pipe organ note: the pipe's fundamental with its octave, twelfth and fifteenth stops drawn, a soft "chiff" as the
## air speaks, a slow swell and a gentle tremulant. `wrap` loops it round the end of `out` (for the music).
func _organ(out: PackedFloat32Array, at: float, f: float, length: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var n := int((length + 0.35) * rate)
	var size := out.size()
	for i in n:
		var t := float(i) / rate
		var env := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(length, length + 0.35, t))
		var trem := 1.0 + 0.06 * sin(TAU * 5.2 * t)
		var v := _lookup(f * t) + 0.55 * _lookup(2.0 * f * t) + 0.3 * _lookup(3.0 * f * t) + 0.22 * _lookup(4.0 * f * t) + 0.08 * _lookup(6.0 * f * t)
		v += 0.25 * exp(-t * 40.0) * _lookup(8.0 * f * t)  # the chiff
		var j := start + i
		if wrap:
			j = j % size
		elif j >= size:
			break
		out[j] += level * env * trem * v

## A big bell: the hum note an octave down, the strike note, a minor third, a fifth and the bright partials, each dying
## at its own pace (low ones last longest), so it sounds cast in bronze and far away.
func _toll(out: PackedFloat32Array, at: float, f: float, length: float, level: float, rate := RATE, wrap := false) -> void:
	var parts := [[0.5, 1.0, 0.6], [1.0, 0.8, 1.2], [1.19, 0.5, 1.8], [1.5, 0.35, 2.4], [2.0, 0.3, 3.0], [2.51, 0.18, 4.0], [3.0, 0.12, 5.5]]
	var start := int(at * rate)
	var n := int(length * rate)
	var size := out.size()
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for pp in parts:
			v += float(pp[1]) * exp(-t * float(pp[2])) * _lookup(f * float(pp[0]) * t)
		var j := start + i
		if wrap:
			j = j % size
		elif j >= size:
			break
		out[j] += level * minf(t / 0.002, 1.0) * v

## A choir "ah": a few voices on one note, each with its own slow vibrato, warmed by the vowel's first two formants
## (simple resonant boosts of the harmonics near 700 Hz and 1100 Hz).
func _choir(out: PackedFloat32Array, at: float, f: float, length: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var n := int((length + 0.6) * rate)
	var size := out.size()
	var gains := []
	for h in range(1, 9):
		var hf := f * h
		gains.append((1.0 / h) * (1.0 + 2.5 * exp(-pow((hf - 700.0) / 180.0, 2.0)) + 1.6 * exp(-pow((hf - 1100.0) / 220.0, 2.0))))
	for i in n:
		var t := float(i) / rate
		var env := smoothstep(0.0, 0.5, t) * (1.0 - smoothstep(length, length + 0.6, t))
		var v := 0.0
		for voice in 3:
			var vib := 1.0 + 0.004 * sin(TAU * (4.6 + voice * 0.4) * t + voice) + (voice - 1) * 0.0025
			for h in range(1, 9, 1 if voice == 0 else 2):
				v += float(gains[h - 1]) * _lookup(f * vib * h * t + voice * 0.3)
		var j := start + i
		if wrap:
			j = j % size
		elif j >= size:
			break
		out[j] += level * env * v * 0.33

func _make_gothic_sfx() -> void:
	# tick: a small, dry knock on old wood with a faint ring.
	var tick := _blank(0.12)
	for i in tick.size():
		var t := float(i) / RATE
		tick[i] = 0.4 * exp(-t * 90.0) * (_lookup(420.0 * t) + 0.4 * _lookup(1260.0 * t)) + 0.05 * exp(-t * 30.0) * _lookup(1760.0 * t)
	_sfx["tick"] = _to_stream(_normalize(tick), RATE)
	var conf := _blank(1.2)
	_toll(conf, 0.0, 587.33, 1.2, 0.4)
	_toll(conf, 0.09, 880.0, 1.0, 0.3)
	_sfx["confirm"] = _to_stream(_normalize(_echo(conf, 0.13, 0.25)), RATE)
	var back := _blank(1.0)
	_toll(back, 0.0, 880.0, 0.9, 0.35)
	_toll(back, 0.08, 587.33, 0.9, 0.3)
	_sfx["back"] = _to_stream(_normalize(_echo(back, 0.13, 0.25)), RATE)
	var open := _blank(1.4)
	for f in [293.66, 349.23, 440.0]:
		_organ(open, 0.0, f, 0.7, 0.18)
	_sfx["open"] = _to_stream(_normalize(_echo(open, 0.17, 0.3)), RATE)
	var page := _blank(0.6)
	_toll(page, 0.0, 1174.66, 0.6, 0.3)
	_sfx["page"] = _to_stream(_normalize(page), RATE)
	var panel := _blank(1.2)
	for k in 3:
		_toll(panel, k * 0.07, [587.33, 698.46, 880.0][k], 1.0, 0.25)
	_sfx["panel"] = _to_stream(_normalize(_echo(panel, 0.15, 0.25)), RATE)
	var launch := _blank(2.2)
	for f in [73.42, 146.83, 220.0, 293.66, 349.23]:
		_organ(launch, 0.0, f, 1.6, 0.12)
	_toll(launch, 0.0, 293.66, 2.0, 0.45)
	_sfx["launch"] = _to_stream(_normalize(launch), RATE)
	var opt := _blank(0.7)
	_toll(opt, 0.0, 698.46, 0.7, 0.3)
	_sfx["options"] = _to_stream(_normalize(opt), RATE)

## Gothic: slow, cold and grand, in D minor at a walking pace. A pipe organ holds four chords (D minor, B-flat,
## G minor, A major: the dark turn back home), a quiet choir sings "ah" on the top notes, a deep bell tolls at the start
## of each half, and a soft organ line walks underneath. Notes that ring past the end wrap round, so the loop is seamless.
func _render_gothic() -> PackedFloat32Array:
	var r := MUSIC_RATE
	var n := r * LOOP_SECONDS
	var out := PackedFloat32Array()
	out.resize(n)
	var chords := [
		[73.42, [146.83, 174.61, 220.0, 293.66], 293.66],   # D minor
		[58.27, [116.54, 146.83, 174.61, 233.08], 293.66],  # B-flat
		[49.0, [98.0, 116.54, 146.83, 196.0], 233.08],      # G minor
		[55.0, [110.0, 138.59, 164.81, 220.0], 277.18],     # A major
	]
	for c in 4:
		var at := c * 4.0
		_organ(out, at, float(chords[c][0]), 3.9, 0.10, r, true)  # the pedal note
		for f in chords[c][1]:
			_organ(out, at, float(f), 3.9, 0.055, r, true)
		_choir(out, at + 0.1, float(chords[c][2]), 3.7, 0.05, r, true)
		# a slow walking line in the tenor, two notes a beat
		var line: Array = [chords[c][1][1], chords[c][1][2], chords[c][1][1], chords[c][1][0]]
		for k in 4:
			_organ(out, at + k * 1.0, float(line[k]) * 2.0, 0.85, 0.02, r, true)
	_toll(out, 0.0, 73.42, 7.5, 0.22, r, true)
	_toll(out, 8.0, 73.42, 7.5, 0.18, r, true)
	# A little warmth and space: a soft low-pass and two long echoes, as in a stone hall.
	var lp := 0.0
	for i in n:
		lp += 0.35 * (out[i] - lp)
		out[i] = lp
	var hall := out.duplicate()
	for d in [int(0.37 * r), int(0.61 * r)]:
		for i in n:
			hall[i] += 0.22 * out[(i - d + n) % n]
	return _normalize(hall)

# ---------- Mold: a rotting house ----------
## A drop of water landing in a puddle: a tiny pure tone that quickly bends up (the bubble), then gone.
func _plip(out: PackedFloat32Array, at: float, level: float, f0 := 900.0, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var size := out.size()
	var ph := 0.0
	for i in int(0.09 * rate):
		var t := float(i) / rate
		var f := f0 * (1.0 + 1.6 * minf(t / 0.03, 1.0))
		ph += f / rate
		var j := start + i
		if wrap:
			j = j % size
		elif j >= size:
			break
		out[j] += level * minf(t / 0.0015, 1.0) * exp(-t * 55.0) * sin(TAU * ph)

## An old door or floorboard creaking: a low buzzy tone that bends slowly and wavers, softened at both ends.
func _creak(out: PackedFloat32Array, at: float, length: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var size := out.size()
	var ph := 0.0
	for i in int(length * rate):
		var t := float(i) / rate
		var f := 140.0 + 70.0 * sin(PI * t / length) + 9.0 * sin(TAU * 13.0 * t)
		ph += f / rate
		var env := sin(PI * t / length)
		var v := sin(TAU * ph) + 0.45 * sin(TAU * ph * 2.0) + 0.25 * sin(TAU * ph * 3.0) + 0.12 * sin(TAU * ph * 5.0)
		var j := start + i
		if wrap:
			j = j % size
		elif j >= size:
			break
		out[j] += level * env * env * v * (0.7 + 0.3 * sin(TAU * 31.0 * t))

## A wet squelch: a low tone that dives and wobbles, like something soft being pressed. No noise.
func _squelch(out: PackedFloat32Array, at: float, level: float, f0 := 240.0, f1 := 70.0, length := 0.16, rate := RATE) -> void:
	var start := int(at * rate)
	var ph := 0.0
	for i in int(length * rate):
		var t := float(i) / rate
		var k := t / length
		var f := lerpf(f0, f1, k) * (1.0 + 0.25 * sin(TAU * 38.0 * t))
		ph += f / rate
		var j := start + i
		if j < out.size():
			out[j] += level * sin(PI * minf(k * 1.2, 1.0)) * (1.0 - k) * (_lookup(ph) + 0.5 * _lookup(ph * 2.3 + 0.2 * sin(TAU * 61.0 * t)))

## A cluster of small bubbles popping: short, rising blips at uneven times.
func _bubbles(out: PackedFloat32Array, at: float, count: int, level: float, rate := RATE) -> void:
	var seed_f := 0.37
	for b in count:
		seed_f = fposmod(seed_f * 3.7 + 0.21, 1.0)
		var t0 := at + float(b) * 0.045 + seed_f * 0.03
		var f0 := 280.0 + 520.0 * seed_f
		var ph := 0.0
		for i in int(0.05 * rate):
			var t := float(i) / rate
			ph += f0 * (1.0 + 4.0 * t / 0.05) / rate
			var j := int(t0 * rate) + i
			if j < out.size():
				out[j] += level * sin(PI * t / 0.05) * _lookup(ph)

## An insect-like chitter: a quick run of tiny high ticks that fall in pitch.
func _chitter(out: PackedFloat32Array, at: float, level: float, rate := RATE) -> void:
	for k in 7:
		var t0 := at + float(k) * 0.028
		var f := 3400.0 - 180.0 * k
		for i in int(0.012 * rate):
			var t := float(i) / rate
			var j := int(t0 * rate) + i
			if j < out.size():
				out[j] += level * (1.0 - t / 0.012) * _lookup(f * t)

func _make_mold_sfx() -> void:
	# tick: a tiny wet squelch.
	var tick := _blank(0.14)
	_squelch(tick, 0.0, 0.5, 520.0, 220.0, 0.07)
	_sfx["tick"] = _to_stream(_normalize(tick), RATE)
	# confirm: a thick squelch and a few bubbles bursting.
	var conf := _blank(0.5)
	_squelch(conf, 0.0, 0.5, 260.0, 60.0, 0.2)
	_bubbles(conf, 0.12, 5, 0.25)
	_sfx["confirm"] = _to_stream(_normalize(conf), RATE)
	# back: the squelch pulled the other way, with a chitter.
	var back := _blank(0.4)
	_squelch(back, 0.0, 0.45, 90.0, 300.0, 0.15)
	_chitter(back, 0.12, 0.2)
	_sfx["back"] = _to_stream(_normalize(back), RATE)
	# open: something slowly peeling open, wet and long, with bubbles.
	var open := _blank(1.0)
	_squelch(open, 0.0, 0.4, 150.0, 45.0, 0.5)
	_squelch(open, 0.3, 0.3, 200.0, 70.0, 0.4)
	_bubbles(open, 0.45, 8, 0.2)
	_sfx["open"] = _to_stream(_normalize(_echo(open, 0.13, 0.2)), RATE)
	var page := _blank(0.3)
	_chitter(page, 0.0, 0.3)
	_squelch(page, 0.08, 0.3, 330.0, 150.0, 0.08)
	_sfx["page"] = _to_stream(_normalize(page), RATE)
	# panel: a wet slump and a low, bubbling gurgle.
	var panel := _blank(0.9)
	_squelch(panel, 0.0, 0.5, 120.0, 40.0, 0.4)
	_bubbles(panel, 0.25, 9, 0.22)
	_sfx["panel"] = _to_stream(_normalize(panel), RATE)
	var launch := _blank(2.0)
	for k in 6:
		_squelch(launch, k * 0.22, 0.4, 200.0 - 20.0 * k, 50.0, 0.3)
	_bubbles(launch, 0.9, 14, 0.2)
	_chitter(launch, 1.4, 0.25)
	_sfx["launch"] = _to_stream(_normalize(_echo(launch, 0.15, 0.2)), RATE)
	var opt := _blank(0.3)
	_chitter(opt, 0.0, 0.3)
	_bubbles(opt, 0.1, 3, 0.25)
	_sfx["options"] = _to_stream(_normalize(opt), RATE)

# ---------- Wood and Retro: the new themes' sounds ----------
## Pitch of a MIDI note number (69 = A4 = 440 Hz).
func _hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

## One hollow knock on wood: a short round "tok" (a falling sine with a hollow overtone). No noise.
func _knock(out: PackedFloat32Array, at: float, freq: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var size := out.size()
	for i in int(0.22 * rate):
		var t := float(i) / rate
		var f := freq * (1.0 + 0.5 * exp(-t * 60.0))
		var s := level * minf(t / 0.0015, 1.0) * (exp(-t * 32.0) * _lookup(f * t) + 0.45 * exp(-t * 55.0) * _lookup(f * 2.45 * t) + 0.2 * exp(-t * 80.0) * _lookup(f * 4.1 * t))
		var j := start + i
		if wrap:
			out[j % size] += s
		elif j < size:
			out[j] += s

## A marimba / kalimba note: a warm sine with a short bright overtone, ringing a little.
func _marimba(out: PackedFloat32Array, at: float, freq: float, length: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var size := out.size()
	for i in int(length * rate):
		var t := float(i) / rate
		var env := minf(t / 0.004, 1.0) * exp(-t * 5.5 / length)
		var s := level * env * (_lookup(freq * t) + 0.3 * exp(-t * 18.0) * _lookup(freq * 4.0 * t) + 0.12 * exp(-t * 30.0) * _lookup(freq * 9.2 * t))
		var j := start + i
		if wrap:
			out[j % size] += s
		elif j < size:
			out[j] += s

## A wooden flute note: breathy-soft, a slow start, a little vibrato once it has settled.
func _flute(out: PackedFloat32Array, at: float, freq: float, length: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var size := out.size()
	var ph := 0.0
	for i in int(length * rate):
		var t := float(i) / rate
		var env := smoothstep(0.0, 0.09, t) * (1.0 - smoothstep(length - 0.18, length, t))
		var vib := 1.0 + 0.006 * sin(TAU * 5.0 * t) * smoothstep(0.15, 0.5, t)
		ph += freq * vib / rate
		var s := level * env * (_lookup(ph) + 0.22 * _lookup(ph * 2.0) + 0.08 * _lookup(ph * 3.0))
		var j := start + i
		if wrap:
			out[j % size] += s
		elif j < size:
			out[j] += s

## A small bird: a quick rising or falling sweep of a pure tone, twice or three times.
func _chirp(out: PackedFloat32Array, at: float, f0: float, f1: float, level: float, count := 2, rate := RATE, wrap := false) -> void:
	var size := out.size()
	for c in count:
		var start := int((at + c * 0.13) * rate)
		var ph := 0.0
		for i in int(0.09 * rate):
			var t := float(i) / rate
			var k := t / 0.09
			ph += lerpf(f0, f1, k * k) / rate
			var s := level * sin(PI * k) * _lookup(ph)
			var j := start + i
			if wrap:
				out[j % size] += s
			elif j < size:
				out[j] += s

func _make_wood_sfx() -> void:
	var tick := _blank(0.12)
	_knock(tick, 0.0, 720.0, 0.5)
	_sfx["tick"] = _to_stream(_normalize(tick), RATE)
	var conf := _blank(0.6)
	_knock(conf, 0.0, 440.0, 0.45)
	_marimba(conf, 0.02, _hz(67), 0.5, 0.3)
	_marimba(conf, 0.1, _hz(74), 0.5, 0.28)
	_sfx["confirm"] = _to_stream(_normalize(_echo(conf, 0.18, 0.2)), RATE)
	var back := _blank(0.5)
	_knock(back, 0.0, 330.0, 0.4)
	_marimba(back, 0.03, _hz(72), 0.35, 0.25)
	_marimba(back, 0.1, _hz(65), 0.4, 0.25)
	_sfx["back"] = _to_stream(_normalize(back), RATE)
	var open := _blank(0.9)
	_flute(open, 0.0, _hz(69), 0.5, 0.3)
	_flute(open, 0.22, _hz(76), 0.6, 0.3)
	_sfx["open"] = _to_stream(_normalize(_echo(open, 0.2, 0.25)), RATE)
	var page := _blank(0.3)
	_knock(page, 0.0, 600.0, 0.35)
	_knock(page, 0.09, 820.0, 0.3)
	_sfx["page"] = _to_stream(_normalize(page), RATE)
	var panel := _blank(1.0)
	_flute(panel, 0.0, _hz(62), 0.55, 0.25)
	_marimba(panel, 0.25, _hz(81), 0.7, 0.2)
	_sfx["panel"] = _to_stream(_normalize(_echo(panel, 0.2, 0.25)), RATE)
	var launch := _blank(1.4)
	for k in 5:
		_marimba(launch, k * 0.11, _hz(62 + [0, 4, 7, 12, 16][k]), 0.8, 0.26)
	_chirp(launch, 0.6, 3000.0, 4200.0, 0.1, 3)
	_sfx["launch"] = _to_stream(_normalize(_echo(launch, 0.2, 0.25)), RATE)
	var opt := _blank(0.4)
	_knock(opt, 0.0, 520.0, 0.35)
	_marimba(opt, 0.04, _hz(86), 0.3, 0.2)
	_sfx["options"] = _to_stream(_normalize(opt), RATE)

## Wood: a bright morning, slow and open. D major pentatonic. A warm pad that opens up on each chord, a marimba playing
## quiet broken chords with gaps, a wooden flute phrase every eight seconds, a few small birds far apart and one soft
## hollow knock every four seconds. 32 seconds, no noise.
func _render_wood() -> PackedFloat32Array:
	var r := MUSIC_RATE
	var L := 32
	var n := r * L
	var out := PackedFloat32Array()
	out.resize(n)
	var chords := [
		[38, [50, 57, 61, 64]],   # D major 9 (D A C# E)
		[43, [55, 59, 62, 66]],   # G major 7 (G B D F#)
		[35, [47, 54, 59, 62]],   # B minor 7
		[45, [52, 57, 61, 64]],   # A (sus/add 9)
	]
	for c in 8:                    # 8 chords of 4 seconds each
		var ch: Array = chords[c % 4]
		var at := c * 4.0
		for f in ch[1]:
			for i in int(5.2 * r):
				var t := float(i) / r
				var env := smoothstep(0.0, 1.4, t) * (1.0 - smoothstep(3.0, 5.2, t))
				out[(int(at * r) + i) % n] += 0.07 * env * (_lookup(_hz(float(f)) * t) + 0.18 * _lookup(_hz(float(f)) * 2.0 * t))
		for i in int(5.4 * r):
			var t2 := float(i) / r
			out[(int(at * r) + i) % n] += 0.13 * smoothstep(0.0, 0.9, t2) * (1.0 - smoothstep(3.4, 5.4, t2)) * _lookup(_hz(float(ch[0])) * t2)
		# marimba: broken chord, 8 notes of 0.5 s with gaps
		var pat := [0, 2, 1, 3, 2, 1, 3, 2]
		var rest := [false, false, true, false, false, true, false, true]
		for k in 8:
			if rest[(k + c) % 8] and k % 2 == 1:
				continue
			_marimba(out, at + k * 0.5, _hz(float(ch[1][pat[k]]) + 12.0), 1.0, 0.1, r, true)
	# the flute: four notes every 8 seconds, then a rest
	var tunes := [[74, 1.2, 0.0], [73, 0.8, 1.4], [69, 1.8, 2.4], [66, 1.6, 4.4], [71, 1.0, 16.0], [74, 1.4, 17.2], [78, 2.2, 18.8], [76, 1.8, 21.2], [74, 3.0, 24.0]]
	for tn in tunes:
		_flute(out, float(tn[2]), _hz(float(tn[0])), float(tn[1]), 0.12, r, true)
	for b in [[3.1, 3300.0, 4400.0, 3], [11.7, 4200.0, 3300.0, 2], [19.5, 3000.0, 4600.0, 4], [27.3, 4500.0, 3500.0, 3]]:
		_chirp(out, float(b[0]), float(b[1]), float(b[2]), 0.035, int(b[3]), r, true)
	for k in 8:
		_knock(out, k * 4.0 + 2.0, 190.0, 0.07, r, true)
	var lp := 0.0
	for i in n:
		lp += 0.25 * (out[i] - lp)
		out[i] = lp
	var hall := out.duplicate()
	for d in [int(0.31 * r), int(0.57 * r)]:
		for i in n:
			hall[i] += 0.22 * out[(i - d + n) % n]
	return _normalize(hall)

# --- Retro (8-bit) ---
## A square-wave beep: no filtering, like the old chips, only a quick start and a short fade so it does not click.
func _sq(out: PackedFloat32Array, at: float, freq: float, length: float, level: float, duty := 0.5, rate := RATE, wrap := false, glide := 0.0) -> void:
	var start := int(at * rate)
	var size := out.size()
	var ph := 0.0
	for i in int(length * rate):
		var t := float(i) / rate
		ph += (freq + glide * t) / rate
		var env := minf(t / 0.004, 1.0) * (1.0 - smoothstep(length - 0.03, length, t))
		var s := level * env * (1.0 if fposmod(ph, 1.0) < duty else -1.0)
		var j := start + i
		if wrap:
			out[j % size] += s
		elif j < size:
			out[j] += s

## A triangle-wave note (the console's bass voice): softer than a square.
func _tri(out: PackedFloat32Array, at: float, freq: float, length: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var size := out.size()
	for i in int(length * rate):
		var t := float(i) / rate
		var env := minf(t / 0.006, 1.0) * (1.0 - smoothstep(length - 0.05, length, t))
		var s := level * env * (4.0 * absf(fposmod(freq * t, 1.0) - 0.5) - 1.0)
		var j := start + i
		if wrap:
			out[j % size] += s
		elif j < size:
			out[j] += s

func _smooth(a: PackedFloat32Array, k: float) -> void:
	var lp := 0.0
	for i in a.size():
		lp += k * (a[i] - lp)
		a[i] = lp

func _make_retro_sfx() -> void:
	var tick := _blank(0.06)
	_sq(tick, 0.0, 1320.0, 0.045, 0.3, 0.25)
	_smooth(tick, 0.5)
	_sfx["tick"] = _to_stream(_normalize(tick), RATE)
	var conf := _blank(0.3)
	_sq(conf, 0.0, _hz(76), 0.07, 0.3, 0.5)
	_sq(conf, 0.07, _hz(83), 0.2, 0.3, 0.5)
	_smooth(conf, 0.5)
	_sfx["confirm"] = _to_stream(_normalize(conf), RATE)
	var back := _blank(0.25)
	_sq(back, 0.0, _hz(79), 0.07, 0.3, 0.5)
	_sq(back, 0.07, _hz(72), 0.14, 0.3, 0.5)
	_smooth(back, 0.5)
	_sfx["back"] = _to_stream(_normalize(back), RATE)
	var open := _blank(0.4)
	for k in 4:
		_sq(open, k * 0.05, _hz(64 + [0, 4, 7, 12][k]), 0.09, 0.28, 0.25)
	_smooth(open, 0.5)
	_sfx["open"] = _to_stream(_normalize(open), RATE)
	var page := _blank(0.12)
	_sq(page, 0.0, 1760.0, 0.03, 0.28, 0.125)
	_sq(page, 0.04, 2200.0, 0.04, 0.28, 0.125)
	_smooth(page, 0.5)
	_sfx["page"] = _to_stream(_normalize(page), RATE)
	var panel := _blank(0.4)
	_sq(panel, 0.0, _hz(60), 0.12, 0.28, 0.5)
	_sq(panel, 0.1, _hz(67), 0.12, 0.28, 0.5)
	_sq(panel, 0.2, _hz(72), 0.18, 0.28, 0.5)
	_smooth(panel, 0.5)
	_sfx["panel"] = _to_stream(_normalize(panel), RATE)
	var launch := _blank(0.9)
	for k in 8:
		_sq(launch, k * 0.07, _hz(60 + [0, 4, 7, 12, 16, 19, 24, 28][k]), 0.12, 0.26, 0.5)
	_tri(launch, 0.0, _hz(36), 0.6, 0.35)
	_smooth(launch, 0.5)
	_sfx["launch"] = _to_stream(_normalize(launch), RATE)
	var opt := _blank(0.25)
	_sq(opt, 0.0, _hz(84), 0.05, 0.28, 0.125)
	_sq(opt, 0.05, _hz(91), 0.12, 0.28, 0.125)
	_smooth(opt, 0.5)
	_sfx["options"] = _to_stream(_normalize(opt), RATE)

## Retro: a slow, lonely tune on an old console. A square lead plays a sparse melody in A minor with long rests, a
## triangle bass walks under it, a very quiet narrow-pulse arpeggio ticks along, and the lead echoes. 12 bars of 90
## beats a minute (32 seconds). No noise.
func _render_retro() -> PackedFloat32Array:
	var r := MUSIC_RATE
	var beat := 60.0 / 90.0
	var bars := 12
	var n := int(round(float(bars) * 4.0 * beat * r))
	var out := PackedFloat32Array()
	out.resize(n)
	var roots := [45, 41, 48, 43, 45, 41, 48, 43, 50, 45, 41, 40]
	var tones := [[57, 60, 64, 69], [53, 57, 60, 65], [55, 60, 64, 67], [55, 59, 62, 67], [57, 60, 64, 69], [53, 57, 60, 65], [55, 60, 64, 67], [55, 59, 62, 67], [57, 62, 65, 69], [57, 60, 64, 69], [53, 57, 60, 65], [56, 59, 64, 68]]
	var mel := [
		[[0, 76, 1.5], [1.5, 72, 0.5], [2, 69, 2.0]],
		[[0, 72, 1.0], [1, 77, 1.5], [2.5, 76, 0.5], [3, 72, 1.0]],
		[[0, 79, 1.5], [1.5, 76, 0.5], [2, 72, 2.0]],
		[[0, 74, 1.0], [1, 71, 1.0], [2, 67, 2.0]],
		[[0, 76, 1.0], [1, 81, 1.5], [2.5, 79, 0.5], [3, 76, 1.0]],
		[[0, 77, 1.5], [1.5, 76, 0.5], [2, 72, 1.0], [3, 69, 1.0]],
		[[0, 72, 0.5], [0.5, 76, 0.5], [1, 79, 1.0], [2, 84, 2.0]],
		[[0, 83, 1.0], [1, 79, 1.0], [2, 74, 2.0]],
		[[0, 74, 1.5], [1.5, 77, 0.5], [2, 81, 2.0]],
		[[0, 76, 1.0], [1, 72, 1.0], [2, 69, 1.0], [3, 72, 1.0]],
		[[0, 77, 1.0], [1, 72, 1.0], [2, 69, 1.0], [3, 65, 1.0]],
		[[0, 68, 1.0], [1, 71, 1.0], [2, 76, 2.0]],
	]
	var lead := PackedFloat32Array()
	lead.resize(n)
	for b in bars:
		var at := float(b) * 4.0 * beat
		# bass: root on beats 1 and 3, the fifth on the "and" of 2
		_tri(out, at, _hz(float(roots[b])), beat * 1.6, 0.32, r, true)
		_tri(out, at + 2.0 * beat, _hz(float(roots[b])), beat * 1.2, 0.3, r, true)
		_tri(out, at + 3.0 * beat, _hz(float(roots[b]) + 7.0), beat * 0.8, 0.24, r, true)
		# arpeggio: eighth notes through the chord, very quiet
		for k in 8:
			_sq(out, at + k * beat * 0.5, _hz(float(tones[b][[0, 1, 2, 3, 2, 1, 3, 2][k]]) + 12.0), beat * 0.4, 0.035, 0.125, r, true)
		for m in mel[b]:
			_sq(lead, at + float(m[0]) * beat, _hz(float(m[1])), float(m[2]) * beat * 0.92, 0.12, 0.5, r, true)
	# the lead and its echo
	for i in n:
		out[i] += lead[i]
	var d := int(0.75 * beat * r)
	for i in n:
		out[i] += 0.32 * lead[(i - d + n) % n]
	_smooth(out, 0.45)
	return _normalize(out)

## Mold: the house breathing. A deep drone on A that slowly beats against itself, a second voice a half step up
## fading in and out (the unease), a faint high tone hanging like a ringing in the ears, drips falling into puddles at
## uneven times, and once a loop a far-off creak. No beat, no melody, no noise. Notes that ring past the end wrap round.
func _render_mold() -> PackedFloat32Array:
	var r := MUSIC_RATE
	var n := r * LOOP_SECONDS
	var out := PackedFloat32Array()
	out.resize(n)
	var L := float(LOOP_SECONDS)
	for i in n:
		var t := float(i) / r
		var slow := 0.5 - 0.5 * cos(TAU * t / L)            # once per loop, so it joins up
		var drone := _lookup(55.0 * t) + 0.9 * _lookup(55.0 * t + 0.25 * sin(TAU * t / 8.0)) + 0.35 * _lookup(110.0 * t)
		var rub := (0.3 + 0.5 * slow) * (_lookup(58.27 * t) + 0.3 * _lookup(116.54 * t))
		var low := 0.5 * _lookup(41.2 * t) * (0.6 + 0.4 * sin(TAU * t / 4.0))
		var ring := 0.035 * (0.5 + 0.5 * sin(TAU * t / (L / 2.0))) * _lookup(1760.0 * t)
		out[i] = 0.12 * (drone + rub + low) + ring
	var lp := 0.0
	for i in n:
		lp += 0.12 * (out[i] - lp)
		out[i] = lp
	for k in [[0.7, 980.0, 0.22], [2.9, 1210.0, 0.14], [3.35, 860.0, 0.1], [6.2, 1040.0, 0.2], [9.8, 930.0, 0.16], [10.1, 1150.0, 0.09], [13.4, 1000.0, 0.18]]:
		_plip(out, float(k[0]), float(k[2]), float(k[1]), r, true)
	_creak(out, 11.5, 1.6, 0.06, r, true)
	var hall := out.duplicate()
	for d in [int(0.29 * r), int(0.53 * r)]:
		for i in n:
			hall[i] += 0.25 * out[(i - d + n) % n]
	return _normalize(hall)

## A simple echo (delay with feedback) on a short sound.
func _echo(a: PackedFloat32Array, secs: float, fb: float) -> PackedFloat32Array:
	var d := int(secs * RATE)
	for i in range(d, a.size()):
		a[i] += fb * a[i - d]
	return a

# ---------- Gun metal: the sounds of a gun ----------
# Small hard pieces of steel: a click is a 1 ms burst of noise ringing two high, unrelated metal tones that die in a few
# milliseconds; a snap is the slide going home (a noise rasp, then a heavy clack with lower tones); rubber is the grip,
# a dull low knock with no ring at all. `rate` and `wrap` let the music use them too (wrap = loop round the end).
var _grng := RandomNumberGenerator.new()

func _gclick(out: PackedFloat32Array, at: float, level: float, bright := 1.0, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var n := out.size()
	var f1 := 3100.0 * bright
	var f2 := 5230.0 * bright
	var hp := 0.0
	var prev := 0.0
	for i in int(0.03 * rate):
		var j := start + i
		if j >= n:
			if not wrap:
				return
			j %= n
		var t := float(i) / rate
		var nz := _grng.randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + nz - prev)  # high-passed: a tick, not a thud
		prev = nz
		var burst := hp * exp(-t * 2200.0)
		var ring := exp(-t * 260.0) * (0.6 * _lookup(f1 * t) + 0.4 * _lookup(f2 * t + 0.3))
		out[j] += level * (0.8 * burst + 0.55 * ring)

func _snap(out: PackedFloat32Array, at: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var n := out.size()
	var bp := 0.0
	for i in int(0.16 * rate):
		var j := start + i
		if j >= n:
			if not wrap:
				return
			j %= n
		var t := float(i) / rate
		var nz := _grng.randf_range(-1.0, 1.0)
		bp += 0.35 * (nz - bp)
		var rasp := bp * smoothstep(0.0, 0.004, t) * (1.0 - smoothstep(0.012, 0.03, t)) * 0.5
		var tc := t - 0.028  # the clack, just after the rasp
		var clack := 0.0
		if tc >= 0.0:
			clack = exp(-tc * 55.0) * (0.5 * _lookup(1420.0 * tc) + 0.35 * _lookup(2310.0 * tc + 0.2) + 0.25 * _lookup(3870.0 * tc + 0.6)) \
				+ exp(-tc * 900.0) * nz * 0.8
		out[j] += level * (rasp + clack)

func _rubber(out: PackedFloat32Array, at: float, level: float, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var n := out.size()
	var ph := 0.0
	var lp := 0.0
	for i in int(0.12 * rate):
		var j := start + i
		if j >= n:
			if not wrap:
				return
			j %= n
		var t := float(i) / rate
		ph += (75.0 + 85.0 * exp(-t * 60.0)) / rate
		lp += 0.08 * (_grng.randf_range(-1.0, 1.0) - lp)
		out[j] += level * smoothstep(0.0, 0.002, t) * exp(-t * 38.0) * (0.8 * _lookup(ph) + 1.2 * lp)

## A struck steel part: inharmonic partials (like a bar, not a bell), a short hard ring.
func _steel(out: PackedFloat32Array, at: float, freq: float, level: float, decay := 9.0, rate := RATE, wrap := false) -> void:
	var start := int(at * rate)
	var n := out.size()
	for i in int(minf(6.0 / decay, 1.5) * rate):
		var j := start + i
		if j >= n:
			if not wrap:
				return
			j %= n
		var t := float(i) / rate
		var e := minf(t / 0.001, 1.0)
		out[j] += level * e * (exp(-t * decay) * _lookup(freq * t) + 0.5 * exp(-t * decay * 1.7) * _lookup(freq * 2.76 * t) \
			+ 0.3 * exp(-t * decay * 2.6) * _lookup(freq * 5.40 * t + 0.2))

## Gun metal's sounds: clicks, snaps, metal and rubber. Hard and short, nothing soft.
func _make_gunmetal_sfx() -> void:
	_grng.seed = 11
	var tick := _blank(0.05)
	_gclick(tick, 0.0, 0.6)                           # a trigger resetting
	_sfx["tick"] = _to_stream(_normalize(tick), RATE)
	var conf := _blank(0.3)
	_gclick(conf, 0.0, 0.5, 0.8)                      # the hammer cocks...
	_snap(conf, 0.06, 0.9)                            # ...and drops
	_sfx["confirm"] = _to_stream(_normalize(conf), RATE)
	var back := _blank(0.2)
	_rubber(back, 0.0, 0.9)                           # set down on the grip
	_gclick(back, 0.03, 0.25, 0.7)
	_sfx["back"] = _to_stream(_normalize(back), RATE)
	var open := _blank(0.6)
	_snap(open, 0.0, 0.6)                             # slide back...
	_snap(open, 0.14, 1.0)                            # ...and home
	_steel(open, 0.17, 880.0, 0.12, 12.0)
	_sfx["open"] = _to_stream(_normalize(open), RATE)
	var page := _blank(0.12)
	_gclick(page, 0.0, 0.5, 0.9)
	_gclick(page, 0.045, 0.4, 0.75)                   # a selector switch, two detents
	_sfx["page"] = _to_stream(_normalize(page), RATE)
	var panel := _blank(0.3)
	_rubber(panel, 0.0, 0.6)
	_gclick(panel, 0.05, 0.55, 0.85)                  # the safety
	_sfx["panel"] = _to_stream(_normalize(panel), RATE)
	var launch := _blank(1.1)
	_snap(launch, 0.0, 0.7)
	_snap(launch, 0.16, 1.0)                          # chambered
	_thump(launch, 0.2, 0.9)
	_steel(launch, 0.2, 196.0, 0.25, 4.0)
	_steel(launch, 0.2, 587.0, 0.1, 7.0)
	_sfx["launch"] = _to_stream(_normalize(launch), RATE)
	var opt := _blank(0.2)
	_gclick(opt, 0.0, 0.5, 1.1)
	_rubber(opt, 0.04, 0.5)
	_sfx["options"] = _to_stream(_normalize(opt), RATE)

## A soft breath of air sweeping up or down (filtered noise), like glass sliding past.
func _air(out: PackedFloat32Array, at: float, length: float, level: float, from_k: float, to_k: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var start := int(at * RATE)
	var lp := 0.0
	var lp2 := 0.0
	for i in int(length * RATE):
		var j := start + i
		if j >= out.size():
			return
		var u := float(i) / (length * RATE)
		var k := lerpf(from_k, to_k, smoothstep(0.0, 1.0, u))   # how open the filter is (0..1)
		lp += k * (rng.randf_range(-1.0, 1.0) - lp)
		lp2 += k * (lp - lp2)
		var env := sin(PI * u)
		out[j] += level * env * (lp - lp2) * 2.0

## Frutiger Aero: clean and curvy. Every sound is a smooth glide or a breath of air, no bells or piano.
func _make_aero_sfx() -> void:
	var tick := _blank(0.06)
	_pip(tick, 0.0, 1175.0, 0.05, 0.22)
	_sfx["tick"] = _to_stream(_normalize(tick), RATE)
	var conf := _blank(0.26)
	_pip(conf, 0.0, 784.0, 0.12, 0.28)
	_pip(conf, 0.06, 1175.0, 0.16, 0.2)
	_air(conf, 0.0, 0.18, 0.15, 0.1, 0.35)
	_sfx["confirm"] = _to_stream(_normalize(conf), RATE)
	var back := _blank(0.22)
	_pip(back, 0.0, 988.0, 0.1, 0.26)
	_pip(back, 0.05, 659.0, 0.14, 0.2)
	_sfx["back"] = _to_stream(_normalize(back), RATE)
	var open := _blank(0.36)
	_air(open, 0.0, 0.3, 0.3, 0.06, 0.4)
	_pip(open, 0.04, 880.0, 0.22, 0.18)
	_pip(open, 0.04, 1320.0, 0.18, 0.08)
	_sfx["open"] = _to_stream(_normalize(open), RATE)
	var page := _blank(0.12)
	_pip(page, 0.0, 1320.0, 0.06, 0.18)
	_air(page, 0.0, 0.1, 0.15, 0.2, 0.45)
	_sfx["page"] = _to_stream(_normalize(page), RATE)
	var panel := _blank(0.4)
	_air(panel, 0.0, 0.34, 0.3, 0.06, 0.32)
	_pip(panel, 0.03, 784.0, 0.22, 0.16)
	_pip(panel, 0.08, 1175.0, 0.22, 0.1)
	_sfx["panel"] = _to_stream(_normalize(panel), RATE)
	var launch := _blank(0.7)
	_air(launch, 0.0, 0.6, 0.35, 0.04, 0.45)
	for k in 3:
		_pip(launch, k * 0.08, [659.0, 988.0, 1320.0][k], 0.4 if k == 2 else 0.18, 0.2)
	_sfx["launch"] = _to_stream(_normalize(launch), RATE)
	var opt := _blank(0.24)
	_pip(opt, 0.0, 1047.0, 0.08, 0.22)
	_pip(opt, 0.06, 1397.0, 0.12, 0.14)
	_sfx["options"] = _to_stream(_normalize(opt), RATE)

## A short, clean round tone at one steady pitch: soft start, smooth quick fade, no ring and no bend.
func _pip(out: PackedFloat32Array, at: float, freq: float, length: float, level: float) -> void:
	var start := int(at * RATE)
	for i in int(length * RATE):
		var j := start + i
		if j >= out.size():
			return
		var t := float(i) / RATE
		var u := t / length
		var env := smoothstep(0.0, 0.08, u) * pow(1.0 - u, 2.0)
		out[j] += level * env * (_lookup(freq * t) + 0.06 * _lookup(freq * 2.0 * t))

func _make_soft_sfx() -> void:
	var tick := _blank(0.06)
	_bop(tick, 0.0, 1046.5, 0.05, 0.3)
	_sfx["tick"] = _to_stream(_normalize(tick), RATE)
	var conf := _blank(0.28)
	_bop(conf, 0.0, 784.0, 0.12, 0.3)
	_bop(conf, 0.05, 1174.7, 0.22, 0.3)
	_sfx["confirm"] = _to_stream(_normalize(conf), RATE)
	var back := _blank(0.22)
	_bop(back, 0.0, 880.0, 0.1, 0.3)
	_bop(back, 0.045, 659.3, 0.17, 0.28)
	_sfx["back"] = _to_stream(_normalize(back), RATE)
	var open := _blank(0.4)
	_bop(open, 0.0, 1318.5, 0.35, 0.22)
	_bop(open, 0.0, 1975.5, 0.25, 0.08)
	_sfx["open"] = _to_stream(_normalize(open), RATE)
	# page: turning a page is a small switch click, "tk-tk", with no ring to it.
	var page := _blank(0.12)
	_click(page, 0.0, 2300.0, 0.5)
	_click(page, 0.05, 1500.0, 0.32)
	_sfx["page"] = _to_stream(_normalize(page), RATE)
	var panel := _blank(0.42)
	_bop(panel, 0.0, 784.0, 0.18, 0.2)
	_bop(panel, 0.04, 987.8, 0.2, 0.18)
	_bop(panel, 0.08, 1174.7, 0.3, 0.16)
	_sfx["panel"] = _to_stream(_normalize(panel), RATE)
	# launch: a quick happy run up a major chord.
	var launch := _blank(0.8)
	var run := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for k in run.size():
		_bop(launch, k * 0.065, run[k], 0.45 if k == run.size() - 1 else 0.2, 0.24)
	_sfx["launch"] = _to_stream(_normalize(launch), RATE)
	var opt := _blank(0.3)
	_click(opt, 0.0, 2600.0, 0.3)
	_bop(opt, 0.03, 1568.0, 0.22, 0.26)
	_bop(opt, 0.07, 2093.0, 0.18, 0.12)
	_sfx["options"] = _to_stream(_normalize(opt), RATE)

# ---------- Playing ----------
## Slider (0 to 100) to loudness. The power of 1.5 makes equal slider steps sound like equal steps.
static func _curve(pct: float) -> float:
	var v := clampf(pct / 100.0, 0.0, 1.0)
	return pow(v, 1.5)

## Menu sounds sit well under the music (about 10 dB at the default settings): heard, never louder than it.
func _sfx_gain() -> float:
	return _curve(float(Settings.get_value("sfx_volume", SFX_DEFAULT))) * 0.5

## Plays one of the short sounds ("tick", "confirm", "back", "open", "launch").
func play(sound: String) -> void:
	var g := _sfx_gain()
	if g <= 0.0 or _sfx_building or not _sfx.has(sound):
		return
	var p: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = _sfx[sound]
	p.volume_db = linear_to_db(g)
	p.play()

# ---------- Intro ----------
# Plays once at start-up while the Tephra logo shows, then the background music fades in under its tail.
# To use your own sound, put intro.ogg, intro.wav or intro.mp3 in ~/.config/tephra/sounds/ (the file
# wins over the placeholder made here). It plays at the Menu sounds volume.
const INTRO_SECONDS := 6.5
const INTRO_DIR := "/.config/tephra/sounds/"
var _intro: AudioStreamPlayer
var _intro_stream: AudioStream
var _intro_wanted := false
var _intro_task := -1

## Called at start-up, before the logo: your own file is loaded, or the placeholder starts being made
## on a worker thread (it takes about a second), so it is ready when the logo shows.
func prepare_intro() -> void:
	_intro_stream = _intro_file()
	if _intro_stream != null:
		return
	var path := _cache_path("intro")
	_intro_task = WorkerThreadPool.add_task(func() -> void:
		var bytes := _read_bytes(path)
		if bytes.is_empty():
			bytes = _to_bytes(_render_intro())
			_write_bytes(path, bytes)
		_intro_ready.call_deferred(bytes))

func play_intro() -> void:
	if _intro_stream != null:
		_start_intro(_intro_stream)
	else:
		_intro_wanted = true  # plays the moment the placeholder is ready

func _intro_ready(bytes: PackedByteArray) -> void:
	WorkerThreadPool.wait_for_task_completion(_intro_task)
	_intro_task = -1
	_intro_stream = _bytes_stream(bytes, RATE)
	if _intro_wanted:
		_intro_wanted = false
		_start_intro(_intro_stream)

func _intro_file() -> AudioStream:
	var base := OS.get_environment("HOME") + INTRO_DIR + "intro."
	if FileAccess.file_exists(base + "ogg"):
		return AudioStreamOggVorbis.load_from_file(base + "ogg")
	if FileAccess.file_exists(base + "wav"):
		return AudioStreamWAV.load_from_file(base + "wav")
	if FileAccess.file_exists(base + "mp3"):
		return AudioStreamMP3.load_from_file(base + "mp3")
	return null

func _start_intro(st: AudioStream) -> void:
	var g := _sfx_gain()
	if g <= 0.0 or st == null:
		return
	if _intro == null:
		_intro = AudioStreamPlayer.new()
		add_child(_intro)
	_intro.stream = st
	_intro.volume_db = -40.0
	_intro.play()
	# Fades in, so it rises out of the silence with the logo.
	create_tween().tween_property(_intro, "volume_db", linear_to_db(g), 1.0).set_trans(Tween.TRANS_SINE)

## Placeholder intro: a slow swell of a wide chord (D, A, E, F-sharp), then a falling sparkle of bell
## notes that rings out as the music arrives. Echoes give it some space.
func _render_intro() -> PackedFloat32Array:
	if Themes.id() != "tephra":
		return _render_theme_intro(Themes.id())
	var out := _blank(INTRO_SECONDS)
	var n := out.size()
	var pad := [73.42, 110.0, 146.83, 220.0, 329.63, 369.99]
	for i in n:
		var t := float(i) / RATE
		var env := smoothstep(0.0, 2.2, t) * (1.0 - smoothstep(3.2, INTRO_SECONDS, t))
		var s := 0.0
		for k in pad.size():
			var f: float = pad[k] * (1.0 + 0.0015 * sin(TAU * 0.3 * t + k))  # a slow shimmer
			s += (1.0 if k < 2 else 0.6) * _lookup(f * t)
		out[i] = 0.12 * env * s
	var bells := [[1.6, 1174.66], [1.85, 880.0], [2.1, 739.99], [2.35, 587.33], [2.9, 1318.51]]
	for b in bells:
		_bell(out, float(b[0]), float(b[1]), 3.0, 0.22, 2.2)
	# Two soft echoes.
	var dry := out.duplicate()
	for d in [[0.32, 0.35], [0.64, 0.18]]:
		var off := int(float(d[0]) * RATE)
		for i in range(off, n):
			out[i] += float(d[1]) * dry[i - off]
	return _normalize(out)


## A slow swell of a chord (the frequencies in `freqs`) that rises over `rise` seconds and fades out by the end.
func _swell(out: PackedFloat32Array, freqs: Array, level: float, rise: float) -> void:
	var n := out.size()
	for i in n:
		var t := float(i) / RATE
		var env := smoothstep(0.0, rise, t) * (1.0 - smoothstep(rise + 0.8, INTRO_SECONDS, t))
		var sm := 0.0
		for k in freqs.size():
			var f: float = freqs[k] * (1.0 + 0.0015 * sin(TAU * 0.3 * t + k))
			sm += (1.0 if k < 2 else 0.6) * _lookup(f * t)
		out[i] += level * env * sm

## The start-up sound of each theme other than Tephra (your own intro file still wins over all of them).
func _render_theme_intro(theme: String) -> PackedFloat32Array:
	var out := _blank(INTRO_SECONDS)
	var n := out.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	match theme:
		"volcanic":
			# A deep chord swelling out of the ground, heavy stone knocks, and a long dark bell.
			_swell(out, [55.0, 82.41, 110.0, 164.81], 0.18, 2.4)
			for k in [[2.2, 0.6], [2.9, 0.3], [3.6, 0.4], [4.6, 0.22]]:
				_stone(out, RATE, float(k[0]), float(k[1]))
			_bell(out, 2.6, 196.0, 3.5, 0.16, 1.4)
		"sleek":
			# Cool and bare: an open fifth fading in, a glass tap and a thin metallic ring.
			_swell(out, [130.81, 196.0, 261.63, 392.0], 0.08, 2.0)
			_bell(out, 1.7, 2093.0, 3.5, 0.18, 2.2)
			_bell(out, 1.7, 3136.0, 2.5, 0.07, 3.0)
			_bell(out, 2.5, 1568.0, 3.5, 0.12, 2.0)
		"wave":
			# Silk: a long Lydian chord breathing in, then slow glass bells falling like light on water.
			_swell(out, [73.42, 110.0, 146.83, 220.0, 369.99], 0.12, 2.8)
			_swell(out, [293.66, 440.0, 554.37], 0.07, 3.6)
			for k in [[1.8, 739.99], [2.5, 554.37], [3.2, 739.99], [3.9, 440.0], [4.7, 369.99]]:
				_soft(out, float(k[0]), float(k[1]), 2.6, 0.14)
		"gunmetal":
			# Steel waking up: a dark, gritty chord rising, a few hard clicks, the slide racked as the logo lands,
			# and a long low steel ring that dies away.
			_grng.seed = 9
			for i in n:
				var t := float(i) / RATE
				var env := smoothstep(0.0, 2.2, t) * (1.0 - smoothstep(3.2, INTRO_SECONDS, t))
				out[i] += 0.1 * env * tanh(3.0 * (_lookup(41.2 * t) + 0.8 * _lookup(61.74 * t) + 0.5 * _lookup(82.41 * t) + 0.25 * _lookup(123.47 * t)))
			for k in [0.45, 0.9, 1.25, 1.55]:
				_gclick(out, k, 0.35, 0.8 + 0.1 * k)
			_snap(out, 1.85, 0.6)
			_snap(out, 2.0, 1.0)
			_thump(out, 2.02, 0.9)
			_steel(out, 2.02, 110.0, 0.3, 1.6)
			_steel(out, 2.02, 329.6, 0.12, 3.0)
		"neon":
			# A night drive starting: a soft synth pad swells in, an arpeggio rises with it, and a kick and big gated snare
			# land with the logo, the pad opening up after them.
			_grng.seed = 8
			for f in [87.31, 174.61, 207.65, 261.63, 311.13]:
				_syn(out, 0.0, f, INTRO_SECONDS - 0.2, 0.14, 0.4, false, 1.8)
			for k in 16:
				_syn(out, 0.2 + k * 0.12, [349.23, 415.30, 523.25, 622.25][k % 4] * (2.0 if k >= 8 else 1.0), 0.14, 0.12, 0.65, true)
			_kick80(out, 2.15, 0.9)
			_snare80(out, 2.15, 0.6)
			for f in [174.61, 349.23, 440.0, 523.25, 659.25]:
				_syn(out, 2.15, f, 2.4, 0.16, 0.6, false, 0.02)
		"wood":
			# Morning in the forest: a low warm chord opening, birds, a flute phrase and marimba notes settling.
			_swell(out, [146.83, 220.0, 293.66, 369.99], 0.12, 2.2)
			_chirp(out, 0.8, 3300.0, 4400.0, 0.05, 3)
			_chirp(out, 1.6, 4200.0, 3300.0, 0.04, 2)
			for k in [[1.8, 69, 0.8], [2.4, 74, 0.8], [3.0, 73, 0.6], [3.5, 69, 1.8]]:
				_flute(out, float(k[0]), _hz(float(k[1])), float(k[2]), 0.2)
			for k in 4:
				_marimba(out, 3.4 + k * 0.2, _hz(74 + [0, 4, 7, 12][k]), 1.6, 0.2)
			_knock(out, 3.4, 200.0, 0.3)
		"retro":
			# A console powering on: a rising run of beeps, a pause, then the little start-up tune.
			for k in 8:
				_sq(out, 0.4 + k * 0.08, _hz(48 + k * 3), 0.07, 0.24, 0.5)
			for k in [[1.6, 69, 0.3], [1.9, 72, 0.3], [2.2, 76, 0.3], [2.5, 81, 0.9]]:
				_sq(out, float(k[0]), _hz(float(k[1])), float(k[2]), 0.26, 0.5)
			_tri(out, 1.6, _hz(45), 1.8, 0.3)
		"channels":
			# Soft and cheerful: a gentle chord and a few round bops.
			_swell(out, [174.61, 220.0, 261.63, 329.63], 0.09, 1.6)
			for k in [[1.4, 523.25], [1.6, 659.25], [1.8, 783.99], [2.1, 1046.5]]:
				_bop(out, float(k[0]), float(k[1]), 0.5, 0.2)
		"ps2":
			# A deep drone swelling from nothing, a rising whoosh, then glassy pings falling like the dots of a ring.
			_swell(out, [36.71, 55.0, 73.42, 110.0], 0.16, 2.8)
			var hp := 0.0
			for i in n:
				var t := float(i) / RATE
				hp += 0.2 * (rng.randf_range(-1.0, 1.0) - hp)
				out[i] += 0.35 * hp * smoothstep(0.0, 2.0, t) * exp(-maxf(t - 2.0, 0.0) * 3.0) * (0.4 + 0.6 * smoothstep(0.0, 2.0, t))
			for k in [[2.0, 1568.0], [2.25, 2093.0], [2.5, 1760.0], [2.8, 2349.0], [3.3, 1175.0]]:
				_bell(out, float(k[0]), float(k[1]), 3.6, 0.18, 1.8)
		"frutiger":
			# Water and sky: a clean airy chord and a breath of air.
			_swell(out, [261.63, 392.0, 587.33, 659.25], 0.09, 1.8)
			_air(out, 0.6, 2.4, 0.3, 0.02, 0.35)

	var dry := out.duplicate()
	for d in [[0.32, 0.30], [0.64, 0.16]]:
		var off := int(float(d[0]) * RATE)
		for i in range(off, n):
			out[i] += float(d[1]) * dry[i - off]
	return _normalize(out)

# ---------- Music ----------
## The music's loudness from the setting. It used to be far quieter than games, so going from Home into a game
## was a jump in volume: now the music is near full level (about -2 dB at the default 50%), closer to a game's.
func _music_db() -> float:
	var g := clampf(clampf(float(Settings.get_value("music_volume", MUSIC_DEFAULT)) / 100.0, 0.0, 1.0) * 1.6, 0.0, 1.0)
	return linear_to_db(maxf(g, 0.0001))

## Your own music for a theme: ~/.config/tephra/sounds/music-<theme>.ogg, .wav or .mp3 (theme = home,
## library, volcanic, sleek, channels, ps2 or frutiger). It loops, and wins over the music made here.
func _music_file(theme: String) -> AudioStream:
	var base := OS.get_environment("HOME") + INTRO_DIR + "music-" + theme + "."
	var st: AudioStream = null
	if FileAccess.file_exists(base + "ogg"):
		var o := AudioStreamOggVorbis.load_from_file(base + "ogg")
		if o != null:
			o.loop = true
		st = o
	elif FileAccess.file_exists(base + "wav"):
		var w := AudioStreamWAV.load_from_file(base + "wav")
		if w != null:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		st = w
	elif FileAccess.file_exists(base + "mp3"):
		var m := AudioStreamMP3.load_from_file(base + "mp3")
		if m != null:
			m.loop = true
		st = m
	return st

func _render_music(theme: String) -> PackedFloat32Array:
	match theme:
		"channels":
			return _render_bouncy()
		"volcanic":
			return _render_volcanic()
		"ps2":
			return _render_ps2()
		"wave":
			return _render_wave()
		"gunmetal":
			return _render_gunmetal()
		"neon":
			return _render_neon()
		"gothic":
			return _render_gothic()
		"mold":
			return _render_mold()
		"wood":
			return _render_wood()
		"retro":
			return _render_retro()
		"cosmos":
			return _render_cosmos()
		"pcb":
			return _render_pcb()
		"frutiger":
			return _render_frutiger()
	return _render_sleek()

## Makes a song about four times longer so it repeats less: the loop is played four times in a row (about a
## minute), and over those minutes only the colour changes, smoothly and in the same key and tempo: a soft
## echo comes and goes twice, the sound gets darker and warmer twice (in between), and the whole thing swells
## slowly. Nothing is added to the music itself, so each theme keeps its own vibe, and the end of the long
## loop joins its start as smoothly as the short one did.
func _long(base: PackedFloat32Array) -> PackedFloat32Array:
	var m := base.size()
	if m == 0:
		return base
	var reps := 4 if m <= MUSIC_RATE * 20 else 2
	var n := m * reps
	var src := PackedFloat32Array()
	src.resize(n)
	for i in n:
		src[i] = base[i % m]
	var out := PackedFloat32Array()
	out.resize(n)
	var d1 := int(0.43 * MUSIC_RATE)
	var d2 := int(0.86 * MUSIC_RATE)
	var lp := 0.0
	for pass_i in 2:  # the first pass only warms the filter up, so the loop point has no seam
		for i in n:
			var p := float(i) / n
			var echo := 0.5 - 0.5 * cos(TAU * p * 2.0)                 # two humps over the long loop
			var dark := 0.5 - 0.5 * cos(TAU * (p * 2.0 - 0.5))         # two humps, between the echo ones
			var x := src[i] + echo * (0.30 * src[(i - d1 + n) % n] + 0.16 * src[(i - d2 + n) % n])
			var k := lerpf(0.9, 0.22, dark)                             # 1 = bright, small = warm and dark
			lp += k * (x - lp)
			var y := lerpf(x, lp, dark * 0.85)
			y *= 1.0 + 0.07 * sin(TAU * p * 3.0)
			if pass_i == 1:
				out[i] = y
	return _normalize(out)

## Starts building a theme on a worker thread (it takes a few seconds, so it must not freeze the screen).
func _build_theme(theme: String) -> void:
	if not _themes.has(theme):
		var own := _music_file(theme)
		if own != null:
			_themes[theme] = own
			return
	if _themes.has(theme) or _building.has(theme) or not (THEMES.has(theme) or theme in ["channels", "volcanic", "sleek", "ps2", "frutiger", "wave", "gunmetal", "neon", "gothic", "mold", "wood", "retro", "cosmos", "pcb"]):
		return
	var path := _cache_path("music-" + theme)
	if theme in ["channels", "volcanic", "sleek", "ps2", "frutiger", "wave", "gunmetal", "neon", "gothic", "mold", "wood", "retro", "cosmos", "pcb"]:
		_building[theme] = WorkerThreadPool.add_task(func() -> void:
			var bytes := _read_bytes(path)
			if bytes.is_empty():
				bytes = _to_bytes(_long(_render_music(theme)))
				_write_bytes(path, bytes)
			_theme_ready.call_deferred(theme, bytes))
		return
	var chords: Array = THEMES[theme]
	_building[theme] = WorkerThreadPool.add_task(func() -> void:
		var bytes := _read_bytes(path)
		if bytes.is_empty():
			bytes = _to_bytes(_long(_render_theme(chords)))
			_write_bytes(path, bytes)
		_theme_ready.call_deferred(theme, bytes))

## The Channels theme's music: the little tune in F major at 120 beats a minute, 16 seconds that loop,
## played laid-back rather than bouncy: the melody an octave lower on a soft vibraphone with a lazy swing,
## warm seventh chords underneath (F major 7, D minor 7, B-flat major 7, C with a suspended fourth), a
## round bass on the first and third beats and a quiet brush on the second and fourth. Calm, still bright.
## Notes that ring past the end of the loop wrap around to the start, so it joins up with no gap.
const TUNE_CHORDS := [
	{"root": 87.31, "pad": [174.61, 220.00, 261.63, 329.63]},   # F major 7
	{"root": 73.42, "pad": [146.83, 174.61, 220.00, 261.63]},   # D minor 7
	{"root": 58.27, "pad": [116.54, 146.83, 174.61, 220.00]},   # B-flat major 7
	{"root": 65.41, "pad": [130.81, 174.61, 196.00, 233.08]},   # C suspended (C F G B-flat)
]
# The melody, one MIDI note per eighth (-1 = hold the note before / rest), eight bars.
const TUNE := [
	81, -1, 84, 81, 77, -1, 79, 81,   79, 77, -1, 74, 77, -1, -1, -1,
	74, 77, 81, -1, 79, 77, 76, 77,   81, -1, -1, 79, 77, -1, 74, -1,
	82, -1, 86, 82, 77, -1, 79, 82,   81, 79, 77, -1, 74, 77, 79, -1,
	84, -1, 81, 79, 76, -1, 79, 81,   79, -1, 76, -1, 72, 74, 76, 79,
]

func _pluck(out: PackedFloat32Array, at: float, freq: float, length: float, level: float, bright: float) -> void:
	var n := out.size()
	var start := int(at * MUSIC_RATE)
	for i in int(length * MUSIC_RATE):
		var t := float(i) / MUSIC_RATE
		var env := minf(t / 0.004, 1.0) * exp(-t * 5.0 / length)
		var ph := freq * t
		out[(start + i) % n] += level * env * (_lookup(ph) + bright * _lookup(ph * 4.0) * exp(-t * 30.0))

func _midi(n: int) -> float:
	return 440.0 * pow(2.0, (n - 69) / 12.0)

## A soft mallet note (a vibraphone, roughly): a round tone with a gentle shimmer that fades.
func _mallet(out: PackedFloat32Array, at: float, freq: float, length: float, level: float) -> void:
	var n := out.size()
	var start := int(at * MUSIC_RATE)
	for i in int(length * MUSIC_RATE):
		var t := float(i) / MUSIC_RATE
		var env := minf(t / 0.006, 1.0) * exp(-t * 2.6) * minf((length - t) / 0.05, 1.0)
		var trem := 1.0 + 0.12 * sin(TAU * 5.5 * t)
		var ph := freq * t
		out[(start + i) % n] += level * env * trem * (_lookup(ph) + 0.18 * _lookup(ph * 4.0) * exp(-t * 12.0))

func _render_bouncy() -> PackedFloat32Array:
	var n := MUSIC_RATE * LOOP_SECONDS
	var out := PackedFloat32Array()
	out.resize(n)
	var beat := 0.5
	var eighth := beat / 2.0
	var swing := 0.05  # the eighth after each beat comes a little late: relaxed, not bouncy
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# Pad: each chord swells in and out over its two bars (4 seconds), overlapping the next a little.
	for c in 4:
		var ch: Dictionary = TUNE_CHORDS[c]
		var t0 := c * 4.0
		for f in ch["pad"]:
			var start := int(t0 * MUSIC_RATE)
			for i in int(4.6 * MUSIC_RATE):
				var t := float(i) / MUSIC_RATE
				var env := sin(PI * minf(t / 4.6, 1.0))
				out[(start + i) % n] += 0.045 * env * (_lookup(float(f) * t) + 0.2 * _lookup(float(f) * 2.0 * t))
	# Bass: root on beat one, fifth on beat three, long and round.
	for bar in 8:
		var root: float = TUNE_CHORDS[bar / 2]["root"]
		_pluck(out, bar * 2.0, root, 0.95, 0.40, 0.0)
		_pluck(out, bar * 2.0 + 2.0 * beat, root * 1.5, 0.95, 0.30, 0.0)
	# Brush: a soft, dark swish on beats two and four.
	for e in 16:
		var start2 := int((e * 2.0 * beat + beat) * MUSIC_RATE)
		var lp := 0.0
		var prev := 0.0
		for i in int(0.12 * MUSIC_RATE):
			var x := rng.randf_range(-1.0, 1.0)
			lp += 0.35 * (x - lp)
			var hp := lp - prev
			prev = lp
			var t := float(i) / MUSIC_RATE
			out[(start2 + i) % n] += 0.05 * hp * minf(t / 0.01, 1.0) * exp(-t * 28.0)
	# Melody, an octave down: each note rings until the next one starts.
	for k in TUNE.size():
		var note: int = TUNE[k]
		if note < 0:
			continue
		var held := 1
		while k + held < TUNE.size() and TUNE[k + held] < 0 and held < 4:
			held += 1
		var at := k * eighth + (swing if k % 2 == 1 else 0.0)
		_mallet(out, at, _midi(note - 12), held * eighth + 0.35, 0.34)
	return _normalize(out)

## Calculates one seamless loop. Four chords each get a smooth window (Hann) that is centred on its own
## four seconds and overlaps its neighbours, so the chords melt into each other and the end of the loop
## joins the start with no click. Every note is rounded to a whole number of cycles per loop for the same reason.
func _render_theme(chords: Array) -> PackedFloat32Array:
	var n := MUSIC_RATE * LOOP_SECONDS
	var out := PackedFloat32Array()
	out.resize(n)
	var seg := float(LOOP_SECONDS) / chords.size()  # seconds per chord
	var base := 1.0 / LOOP_SECONDS                   # frequencies must be multiples of this
	for c in chords.size():
		var centre := (c + 0.5) * seg
		var notes: Array = chords[c]
		var freqs: Array = []
		for f in notes:
			freqs.append(roundf(float(f) / base) * base)
		for i in n:
			var t := float(i) / MUSIC_RATE
			# Distance to this chord's centre, wrapping around the loop.
			var d := absf(t - centre)
			d = minf(d, LOOP_SECONDS - d)
			if d >= seg:
				continue
			var w := 0.5 + 0.5 * cos(PI * d / seg)  # 1 at the centre, 0 one chord away
			var s := 0.0
			for fi in freqs.size():
				var f: float = freqs[fi]
				var lvl := 1.0 if fi < 2 else 0.7
				s += lvl * _lookup(f * t)
				if fi >= 2:
					s += 0.25 * _lookup(f * t * 2.0 + 0.13 * fi)  # a quiet octave on the upper notes
			out[i] += w * w * s
	# A slow swell (two full breaths per loop) and a gentle overall level.
	for i in n:
		var t2 := float(i) / MUSIC_RATE
		out[i] *= 0.85 + 0.15 * sin(TAU * t2 * 2.0 / LOOP_SECONDS)
	return _normalize(out)

## A heavy stone knock: a low thud whose pitch drops, with a short hollow "tok" on top. No noise in it.
## `rate` is the sample rate of `out` (the music and the short sounds differ).
func _stone(out: PackedFloat32Array, rate: int, at: float, level: float) -> void:
	var n := out.size()
	var start := int(at * rate)
	for i in int(0.7 * rate):
		var t := float(i) / rate
		var f := 44.0 + 40.0 * exp(-t * 14.0)
		var s := exp(-t * 6.0) * minf(t / 0.004, 1.0) * _lookup(f * t)
		s += 0.35 * exp(-t * 40.0) * _lookup(196.0 * t)          # the hollow knock
		s += 0.18 * exp(-t * 55.0) * _lookup(311.0 * t)          # and a stone-like overtone
		out[(start + i) % n] += level * s

## One long, warm note of the lava line: it slides up or down from the note before, swells in and
## melts away into the next one.
func _flow_note(out: PackedFloat32Array, at: float, freq: float, from: float, length: float, level: float) -> void:
	var n := out.size()
	var start := int(at * MUSIC_RATE)
	var ph := 0.0
	for i in int(length * MUSIC_RATE):
		var t := float(i) / MUSIC_RATE
		var f := lerpf(from, freq, smoothstep(0.0, 0.9, t)) * (1.0 + 0.004 * sin(TAU * 4.5 * t))
		ph += f / MUSIC_RATE
		var env := smoothstep(0.0, 0.6, t) * smoothstep(0.0, 1.2, length - t)
		out[(start + i) % n] += level * env * (_lookup(ph) + 0.5 * _lookup(ph * 2.0) + 0.25 * _lookup(ph * 3.0) + 0.1 * _lookup(ph * 4.0))

## Volcanic: slow, heavy and warm. Deep stone knocks, a long molten bass line that slides from note to
## note like lava creeping downhill, a dark pad under it, and now and then a slow bubble rising in the
## lava. Nothing in it is noise or crackle.
func _render_volcanic() -> PackedFloat32Array:
	var chords := [
		[73.42, 110.0, 146.83, 174.61],   # D minor
		[58.27, 116.54, 146.83, 174.61],  # B-flat
		[49.0, 98.0, 146.83, 233.08],     # G minor
		[55.0, 110.0, 164.81, 220.0],     # A, open
	]
	var out := _render_theme(chords)
	var n := out.size()
	for i in n:
		out[i] = 0.7 * out[i] + 0.3 * out[i] * out[i] * signf(out[i])  # a touch of warmth
	# The lava line: a long note every two seconds, each sliding up from the one before.
	var line := [73.42, 87.31, 82.41, 73.42, 58.27, 65.41, 73.42, 55.0]
	for k in 8:
		var prev: float = line[(k + 7) % 8]
		_flow_note(out, k * 2.0, float(line[k]) * 2.0, prev * 2.0, 3.0, 0.20)
	# The rock: slow heavy knocks in every four seconds, a soft one answering.
	for c in 4:
		var t0 := c * 4.0
		_stone(out, MUSIC_RATE, t0, 0.55)
		_stone(out, MUSIC_RATE, t0 + 1.5, 0.22)
		_stone(out, MUSIC_RATE, t0 + 2.0, 0.38)
		_stone(out, MUSIC_RATE, t0 + 3.25, 0.18)
	# Lava bubbles: a soft "bloop" that rises a little in pitch, a few times a loop.
	for at in [1.2, 5.6, 7.3, 10.4, 13.1, 15.0]:
		var start := int(float(at) * MUSIC_RATE)
		for i in int(0.22 * MUSIC_RATE):
			var t := float(i) / MUSIC_RATE
			var f := 70.0 + 110.0 * t / 0.22
			out[(start + i) % n] += 0.12 * sin(PI * t / 0.22) * _lookup(f * t)
	return _normalize(out)

## A struck glass or metal note: a pure tone with a quick, higher, out-of-tune overtone that dies first.
func _glass(out: PackedFloat32Array, at: float, freq: float, length: float, level: float, attack := 0.003) -> void:
	var n := out.size()
	var start := int(at * MUSIC_RATE)
	for i in int(length * MUSIC_RATE):
		var t := float(i) / MUSIC_RATE
		var env := smoothstep(0.0, attack, t) * exp(-t * 3.2 / length * 2.0)
		out[(start + i) % n] += level * env * (_lookup(freq * t) + 0.35 * _lookup(freq * 2.76 * t) * exp(-t * 14.0))

## Sleek: cool, still and smooth, like polished metal. Open, bare chords (no happy thirds) breathing very slowly
## over a deep swell. Nothing else: no dings.
func _render_sleek() -> PackedFloat32Array:
	var chords := [
		[110.0, 164.81, 220.0, 293.66],   # A, E, A, D
		[98.0, 146.83, 196.0, 293.66],    # G, D, G, D
		[87.31, 130.81, 174.61, 261.63],  # F, C, F, C
		[98.0, 146.83, 220.0, 293.66],    # G, D, A, D
	]
	var out := _render_theme(chords)
	var n := out.size()
	# Polished: the pads rounded off with a soft low-pass so nothing pokes out, and a slow, deep swell under them
	# (the root an octave down, breathing in and out once a chord). No noise.
	var lp := 0.0
	var roots := [55.0, 49.0, 43.65, 49.0]
	for i in n:
		lp += 0.2 * (out[i] - lp)
		var t := float(i) / MUSIC_RATE
		var c := int(t / 4.0) % 4
		var swell := 0.5 - 0.5 * cos(TAU * fmod(t, 4.0) / 4.0)
		out[i] = lp * 0.6 + 0.09 * swell * _lookup(float(roots[c]) * t)
	# No glass notes or dings: just the smooth, slow pad flow.
	return _normalize(out)

## PS2: slow, soft and a little robotic, like a 2000s console menu: calm minor-ninth pads under a low filter,
## nothing else. No beeps, no noise, no drums.
func _render_ps2() -> PackedFloat32Array:
	var chords := [
		[73.42, 146.83, 220.0, 261.63, 329.63],   # D minor 9
		[58.27, 116.54, 174.61, 220.0, 293.66],   # B flat major 7
		[49.0, 98.0, 146.83, 233.08, 293.66],     # G minor 9
		[55.0, 110.0, 164.81, 246.94, 329.63],    # A minor (sus 9)
	]
	var out := _render_theme(chords)
	var n := out.size()
	# Soften the pad: a gentle low-pass, so it sits back like a warm machine hum.
	var lp := 0.0
	for i in n:
		lp += 0.18 * (out[i] - lp)
		out[i] = lp * 0.55
	return _normalize(out)

## Wave: slow silk. Wide Lydian chords drifting into each other, a soft low pulse under them, and a few long
## glass notes far apart, like light moving over water.
## Planet: slow and wide. Four soft chords (E minor 9, C major 7 sharp 11, G with a sixth, D suspended) drift under a
## high, glassy sparkle that rings and fades into a long echo, like the dark between stars. Nothing sharp, no beat.
func _render_cosmos() -> PackedFloat32Array:
	var chords := [
		[82.41, 123.47, 196.0, 246.94, 369.99],    # E minor 9
		[65.41, 130.81, 196.0, 246.94, 370.0],     # C major 7 (sharp 11)
		[98.0, 146.83, 196.0, 246.94, 329.63],     # G (sixth)
		[73.42, 146.83, 220.0, 329.63, 440.0],     # D sus
	]
	var out := _render_theme(chords)
	var lp := 0.0
	for i in out.size():
		lp += 0.18 * (out[i] - lp)  # dull and round
		out[i] = lp * 0.6
	var notes := [
		[1318.51, 987.77, 1174.66, 739.99],
		[1046.5, 1318.51, 987.77, 1479.98],
		[1174.66, 987.77, 1567.98, 1174.66],
		[880.0, 1174.66, 1108.73, 1318.51],
	]
	for c in 4:
		for k in 4:
			_glass(out, c * 4.0 + 0.4 + k * 0.95, float(notes[c][k]) * 0.5, 4.2, 0.07 if k % 2 == 0 else 0.05)
	# A long soft echo (a third and two thirds of a second back) makes it wide.
	var n := out.size()
	var d1 := int(0.37 * MUSIC_RATE)
	var d2 := int(0.83 * MUSIC_RATE)
	var wide := out.duplicate()
	for pass_i in 2:
		for i in n:
			wide[i] = out[i] + 0.34 * wide[(i - d1 + n) % n] * 0.6 + 0.2 * wide[(i - d2 + n) % n] * 0.6
	return _normalize(wide)

## Circuit: calm and electric. Four warm chords (A minor 9, F major 7, C add 9, G sus) under a quiet pattern of
## glassy plinks that runs like a little program, one note every eighth of a bar, softened so nothing is sharp.
func _render_pcb() -> PackedFloat32Array:
	var chords := [
		[55.0, 110.0, 164.81, 261.63, 329.63],     # A minor 9
		[87.31, 130.81, 164.81, 220.0, 261.63],    # F major 7
		[65.41, 130.81, 196.0, 261.63, 329.63],    # C (add 9)
		[98.0, 146.83, 196.0, 293.66, 329.63],     # G sus
	]
	var out := _render_theme(chords)
	var lp := 0.0
	for i in out.size():
		lp += 0.22 * (out[i] - lp)
		out[i] = lp * 0.55
	var scale := [880.0, 987.77, 1174.66, 1318.51, 1479.98, 1760.0]
	var pattern := [0, 2, 4, 2, 5, 3, 1, 3, 4, 2, 0, 2, 3, 5, 4, 1]
	for c in 4:
		for q in 16:
			var f: float = scale[(int(pattern[q]) + c) % scale.size()] * 0.5
			_glass(out, float(c) * 4.0 + float(q) * 0.25, f, 1.2, 0.045 if q % 4 == 0 else 0.028)
	return _normalize(out)

func _render_wave() -> PackedFloat32Array:
	var chords := [
		[73.42, 146.83, 220.0, 293.66, 369.99],    # D major 9 (add #11)
		[98.0, 146.83, 246.94, 293.66, 440.0],     # G major 7 (add 9)
		[82.41, 123.47, 185.0, 246.94, 329.63],    # E minor 9
		[110.0, 164.81, 220.0, 277.18, 415.3],     # A major (sus)
	]
	var out := _render_theme(chords)
	var lp := 0.0
	for i in out.size():
		lp += 0.30 * (out[i] - lp)  # rounded off: nothing sharp
		out[i] = lp * 0.55
	var motifs := [
		[880.0, 739.99, 1108.73],
		[987.77, 783.99, 1174.66],
		[1108.73, 987.77, 830.61],
		[1174.66, 1108.73, 880.0],
	]
	for c in 4:
		for k in 3:
			_glass(out, c * 4.0 + 0.6 + k * 1.2, motifs[c][k] * 0.5, 3.8, 0.08 if k == 0 else 0.06)  # an octave down and quiet: soft, not tinkly
	return _normalize(out)

## Gun metal: hard and dark. A gritty, overdriven low chord (D minor, B-flat, G minor, A) that swells up and back once
## per chord over a low hum, and one long steel ring as each chord starts. No beat, no clicks. Loops with no seam.
func _render_gunmetal() -> PackedFloat32Array:
	var chords := [
		[36.71, 73.42, 110.0, 146.83],
		[29.14, 58.27, 87.31, 116.54],
		[32.70, 65.41, 98.0, 130.81],
		[27.5, 55.0, 82.41, 110.0],
	]
	var out := _render_theme(chords)
	var lp := 0.0
	for i in out.size():
		lp += 0.2 * (out[i] - lp)
		out[i] = tanh(lp * 3.2) * 0.32  # driven hard: grit instead of softness
	var n := out.size()
	var r := MUSIC_RATE
	# No beat: the gritty chord just breathes, swelling up and back once per chord, with a low hum under it.
	var roots := [36.71, 29.14, 32.70, 27.5]
	for i in n:
		var t := float(i) / r
		var c := int(t / 4.0) % 4
		var swell := 0.75 + 0.25 * sin(TAU * (fmod(t, 4.0) / 4.0) - PI * 0.5)
		out[i] = out[i] * swell + 0.06 * _lookup(float(roots[c]) * t)
	for c in 4:
		_steel(out, c * 4.0 + 0.02, [146.83, 116.54, 98.0, 110.0][c], 0.07, 1.4, r, true)
	# Far off in the rain: a police siren wailing past, very quiet, rising and fading (a two-tone wail, softened).
	var sir := PackedFloat32Array()
	sir.resize(n)
	var sph := 0.0
	for i in int(6.0 * r):
		var t := float(i) / r
		var wail := 0.5 + 0.5 * sin(TAU * t / 1.4)
		sph += (620.0 + 520.0 * wail) / r
		var env := sin(PI * t / 6.0)
		env *= env
		sir[(int(7.0 * r) + i) % n] += 0.55 * env * (_lookup(sph) + 0.25 * _lookup(sph * 2.0))
	var slp := 0.0
	for i in n:
		slp += 0.12 * (sir[i] - slp)
		out[i] += 0.07 * slp
	# A gun being reloaded somewhere in the dark: magazine out, magazine in, then the slide.
	_snap(out, 2.3, 0.12, r, true)
	_steel(out, 2.35, 392.0, 0.035, 5.0, r, true)
	_gclick(out, 3.0, 0.12, 0.7, r, true)
	_steel(out, 3.02, 523.25, 0.03, 6.0, r, true)
	_snap(out, 3.4, 0.2, r, true)
	_snap(out, 3.46, 0.16, r, true)
	_steel(out, 12.1, 311.13, 0.04, 4.0, r, true)
	_gclick(out, 12.12, 0.1, 0.6, r, true)
	return _normalize(out)

## Neon Coast: chill retrowave at 120 beats a minute, played half-time (a soft kick on 1, a big gated snare on 3), so it
## feels slow. Warm detuned-saw chords (F minor 9, D-flat major 7, A-flat major 7, E-flat with an added 6th), a round
## bass pulsing in eighths, a quiet arpeggio in sixteenths with an echo, and soft hats. Everything wraps round the
## loop's end, so it joins with no seam.
func _render_neon() -> PackedFloat32Array:
	var r := MUSIC_RATE
	var n := r * LOOP_SECONDS
	var out := PackedFloat32Array()
	out.resize(n)
	_grng.seed = 41
	var chords := [
		[43.65, [174.61, 207.65, 261.63, 311.13, 392.0]],    # F minor 9
		[34.65, [138.59, 174.61, 207.65, 261.63, 349.23]],   # D-flat major 7
		[51.91, [207.65, 261.63, 311.13, 392.0, 415.30]],    # A-flat major 7
		[38.89, [155.56, 196.0, 233.08, 261.63, 311.13]],    # E-flat 6
	]
	var beat := 0.5  # 120 bpm: 32 beats in the 16 s loop, 8 per chord
	for c in 4:
		var at := c * 4.0
		var root: float = chords[c][0]
		for f in chords[c][1]:
			_syn(out, at, f, 4.25, 0.11, 0.32, false, 0.35, r, true)   # the pad, overlapping the next chord a touch
		for e in 8 * 2:
			_syn(out, at + e * beat * 0.5, root * 2.0, beat * 0.45, 0.32, 0.25, false, 0.004, r, true)   # bass eighths
		var arp: Array = chords[c][1]
		for q in 32:
			var f2: float = float(arp[[0, 2, 4, 2, 1, 3, 4, 3][q % 8]]) * 2.0
			_syn(out, at + q * beat * 0.25, f2, 0.11, 0.055, 0.6, true, 0.003, r, true)
	for b in 32:
		var t0 := b * beat
		if b % 4 == 0:
			_kick80(out, t0, 0.55, r, true)
		if b % 4 == 2:
			_snare80(out, t0, 0.35, r, true)
		for h in 2:
			var hs := int((t0 + h * beat * 0.5) * r)
			for i in int(0.03 * r):
				var t := float(i) / r
				out[(hs + i) % n] += 0.05 * (0.6 if h == 1 else 1.0) * exp(-t * 160.0) * _grng.randf_range(-1.0, 1.0)
	# a long, soft echo over everything (3/8 of a bar), wrapped
	var dry := out.duplicate()
	var dl := int(0.75 * r)
	for i in n:
		out[i] += 0.28 * dry[(i - dl + n) % n] + 0.12 * dry[(i - 2 * dl + 2 * n) % n]
	return _normalize(out)

## Frutiger: slow, smooth and glassy. Soft major-seventh chords that melt into each other, and over them
## just three struck-glass notes per chord, far apart, ringing out. Nothing else.
## Frutiger Aero: clean and smooth. A soft, airy pad of open major chords that melt into each other, a round sub
## bass breathing under each chord. No bells, no piano and no sliding notes.
func _render_frutiger() -> PackedFloat32Array:
	var chords := [
		[130.81, 196.0, 293.66, 329.63],   # C (add 9)
		[87.31, 174.61, 261.63, 392.0],    # F (add 9)
		[110.0, 164.81, 246.94, 329.63],   # A minor 9
		[98.0, 146.83, 220.0, 293.66],     # G sus 2
	]
	var out := _render_theme(chords)
	for i in out.size():
		out[i] *= 0.45
	var n := out.size()
	var seg := float(LOOP_SECONDS) / 4.0
	var base := 1.0 / LOOP_SECONDS
	var roots := [65.41, 43.65, 55.0, 49.0]
	for c in 4:
		var f := roundf(roots[c] / base) * base
		for i in int(seg * MUSIC_RATE):
			var t := float(i) / MUSIC_RATE
			var env := smoothstep(0.0, 0.8, t) * (1.0 - smoothstep(seg - 1.4, seg, t))
			var j := (int(c * seg * MUSIC_RATE) + i) % n
			out[j] += 0.22 * env * _lookup(f * (c * seg + t))
	return _normalize(out)

func _exit_tree() -> void:
	if _sfx_task != -1:
		WorkerThreadPool.wait_for_task_completion(_sfx_task)
	if _intro_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_intro_task)
		_intro_task = -1
	for t in _building:
		WorkerThreadPool.wait_for_task_completion(_building[t])  # never quit while a theme is still being made
	_building.clear()

func _theme_ready(theme: String, bytes: PackedByteArray) -> void:
	if not _building.has(theme):
		return
	WorkerThreadPool.wait_for_task_completion(_building[theme])
	_building.erase(theme)
	_themes[theme] = _bytes_stream(bytes, MUSIC_RATE, true)

## Chooses the background music. theme "" (or on == false) fades it out.
func set_music(theme: String, on: bool) -> void:
	if theme != "" and Themes.music() != "home":
		theme = Themes.music()  # every other theme has its own version of the Tephra song, for every menu
	_want_theme = theme if on else ""
	if _want_theme != "":
		_build_theme(_want_theme)

func _process(delta: float) -> void:
	# Step back from the music (or forward again): the whole bus gets quieter and duller.
	var want_k := 1.0 if _distant else 0.0
	if _distant_k != want_k and _bus >= 0:
		_distant_k = move_toward(_distant_k, want_k, delta / DISTANT_SECONDS)
		var e := _distant_k * _distant_k * (3.0 - 2.0 * _distant_k)  # smoothstep: eases in and out
		AudioServer.set_bus_volume_db(_bus, DISTANT_DB * e)
		# The cutoff moves on a log scale, which is how the ear hears pitch.
		_lowpass.cutoff_hz = exp(lerpf(log(NEAR_CUTOFF), log(DISTANT_CUTOFF), e))
	# Follow the wanted theme: wait until it is calculated, then fade out the old one and in the new one.
	var target_db := _music_db()
	if _want_theme == "" or _music_db() <= -79.0:
		if _music.playing and _theme != "":
			_theme = ""
			_fade_music(-60.0, 0.8, true)
		return
	if _theme == _want_theme:
		if _music.playing and (_tween == null or not _tween.is_running()):
			_music.volume_db = lerpf(_music.volume_db, target_db, 0.1)  # follows the setting live
		return
	if not _themes.has(_want_theme):
		return  # still being calculated
	# Switch themes.
	_theme = _want_theme
	var st: AudioStream = _themes[_theme]
	var swap := func() -> void:
		_music.stream = st
		_music.volume_db = -60.0
		_music.play()
		_fade_music(target_db, 1.5, false)
	if _music.playing:
		_fade_music(-60.0, 0.6, true, swap)
	else:
		swap.call()

func _fade_music(db: float, seconds: float, stop_after: bool, then := Callable()) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_music, "volume_db", db, seconds)
	if stop_after:
		_tween.tween_callback(func() -> void:
			if _theme == "":
				_music.stop())
	if then.is_valid():
		_tween.tween_callback(then)
