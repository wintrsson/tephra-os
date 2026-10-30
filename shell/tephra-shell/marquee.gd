extends Node
## Any menu text that is too long for its space (the "..." ones) rests a few seconds, then slides along so the whole
## text can be read, rests at the end and starts over. It works on every label in the shell by itself: twice a second it
## looks for visible labels that are cut off, and while one scrolls it shows a sliding window of the text that fits.

const DWELL := 2.5  # seconds a cut-off text stays put before it scrolls
const CPS := 9.0    # letters per second while scrolling
const HOLD := 1.3   # seconds it rests at the end

var _st := {}  # label instance id -> {orig, ours, t, scrolling, idx, maxi}
var _scan_in := 0.0

func _process(delta: float) -> void:
	_scan_in -= delta
	if _scan_in <= 0.0:
		_scan_in = 0.4
		_scan()
	for id in _st.keys():
		_tick(id, delta)

func _scan() -> void:
	var found := {}
	_walk(get_tree().root, found)
	for id in _st.keys():
		if not found.has(id):
			_release(id)

func _walk(n: Node, found: Dictionary) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is CanvasLayer and not (n as CanvasLayer).visible:
		return
	if n is Label:
		_consider(n as Label, found)
	for c in n.get_children():
		_walk(c, found)

func _consider(l: Label, found: Dictionary) -> void:
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.text == "" or "\n" in l.text or l.size.x < 24.0:
		return
	if l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and not l.clip_text:
		return
	var id := l.get_instance_id()
	var st = _st.get(id)
	if st != null and (l.text == st["ours"] or l.text == st["orig"]):
		found[id] = true
		return
	_st.erase(id)  # the text was changed by its menu: start over
	if _width(l, l.text) > l.size.x + 1.0:
		_st[id] = {"orig": l.text, "ours": l.text, "t": 0.0, "scrolling": false, "idx": -1, "maxi": 0}
		found[id] = true

func _width(l: Label, s: String) -> float:
	var font: Font = l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	if l.label_settings != null:
		if l.label_settings.font != null:
			font = l.label_settings.font
		fs = l.label_settings.font_size
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

func _release(id: int) -> void:
	var st: Dictionary = _st[id]
	var l := instance_from_id(id) as Label
	if l != null and is_instance_valid(l) and l.text == st["ours"]:
		l.text = st["orig"]
	_st.erase(id)

func _tick(id: int, delta: float) -> void:
	if not _st.has(id):
		return
	var st: Dictionary = _st[id]
	var l := instance_from_id(id) as Label
	if l == null or not is_instance_valid(l):
		_st.erase(id)
		return
	st["t"] += delta
	var orig: String = st["orig"]
	var avail := l.size.x - 2.0
	if not st["scrolling"]:
		if st["t"] < DWELL:
			return
		# the first start whose rest of the text fits (the text gets shorter as the start moves on)
		var lo := 0
		var hi := orig.length() - 1
		while lo < hi:
			var mid := (lo + hi) / 2
			if _width(l, orig.substr(mid)) <= avail:
				hi = mid
			else:
				lo = mid + 1
		if lo <= 0:
			_st.erase(id)
			return
		st["maxi"] = lo
		st["scrolling"] = true
		st["t"] = 0.0
		return
	var idx := mini(int(st["t"] * CPS), int(st["maxi"]))
	if idx != int(st["idx"]):
		st["idx"] = idx
		var tail := orig.substr(idx)
		var a := 1
		var b := tail.length()
		while a < b:  # the longest piece from here that still fits
			var m := (a + b + 1) / 2
			if _width(l, tail.substr(0, m)) <= avail:
				a = m
			else:
				b = m - 1
		st["ours"] = tail.substr(0, a)
		l.text = st["ours"]
	if idx >= int(st["maxi"]) and st["t"] > float(st["maxi"]) / CPS + HOLD:
		l.text = orig
		st["ours"] = orig
		st["scrolling"] = false
		st["t"] = 0.0
		st["idx"] = -1
