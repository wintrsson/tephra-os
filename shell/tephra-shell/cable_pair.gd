extends Node
## Plug in to pair, like a PS5: a PlayStation controller plugged in with a cable is paired with this PC's Bluetooth,
## so after you unplug it, pressing its PS button connects it wirelessly, every time.
## Linux's Bluetooth service (BlueZ, its "sixaxis" part) already writes this PC's address into a plugged-in
## controller, but then asks the desktop to allow it, which would be a KDE popup. So while that happens Tephra is the
## one asked: it answers yes by itself, and marks the controller trusted so it can always reconnect.
## Checks every 3 s on a worker thread (reading a few small files); does nothing for controllers already paired.

signal paired(name: String)

var _done := {}      # controller Bluetooth address -> true once handled this session
var _task := -1
var _acc := 0.0

func _process(delta: float) -> void:
	_acc += delta
	if _acc < 3.0 or _task != -1:
		return
	_acc = 0.0
	var skip := _done.duplicate()
	_task = WorkerThreadPool.add_task(func() -> void:
		var found := _usb_pads(skip)
		var result: Array = []
		for p in found:
			if _pair(str(p["mac"])):
				result.append(p)
		_finished.call_deferred(found, result))

func _finished(found: Array, ok: Array) -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	for p in found:
		_done[str(p["mac"])] = true
	for p in ok:
		paired.emit(str(p["name"]))

func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)

## PlayStation controllers on USB right now, with their own Bluetooth address (the kernel reports it as HID_UNIQ).
static func _usb_pads(skip: Dictionary) -> Array:
	var out: Array = []
	var dir := DirAccess.open("/sys/class/hidraw")
	if dir == null:
		return out
	for n in Array(dir.get_directories()) + Array(dir.get_files()):
		var ev := FileAccess.get_file_as_string("/sys/class/hidraw/%s/device/uevent" % n)
		var id := ""
		var mac := ""
		var name := ""
		for line in ev.split("\n"):
			if line.begins_with("HID_ID="):
				id = line.substr(7).to_upper()
			elif line.begins_with("HID_UNIQ="):
				mac = line.substr(9).strip_edges().to_upper()
			elif line.begins_with("HID_NAME="):
				name = line.substr(9).strip_edges()
		# bus 0003 = USB, vendor 054C = Sony
		if not id.begins_with("0003:0000054C") or mac.length() != 17 or skip.has(mac):
			continue
		out.append({"mac": mac, "name": name})
	return out

static func _info(mac: String) -> String:
	var out: Array = []
	OS.execute("bluetoothctl", ["info", mac], out)
	return str(out[0]) if not out.is_empty() else ""

## Pairs and trusts one controller. Returns true when it is now set to reconnect by itself.
static func _pair(mac: String) -> bool:
	var info := _info(mac)
	if info.contains("Paired: yes") and info.contains("Trusted: yes"):
		return false  # already done before: nothing to say
	if info.contains("Paired: yes") or info.contains("Bonded: yes"):
		OS.execute("bluetoothctl", ["trust", mac], [])
		return _info(mac).contains("Trusted: yes")
	# Not paired yet: be the one BlueZ asks for a moment, answer yes, then trust it.
	var proc := OS.execute_with_pipe("bluetoothctl", [], false)
	if proc.is_empty():
		return false
	var io: FileAccess = proc["stdio"]
	io.store_string("agent NoInputNoOutput\ndefault-agent\n")
	io.flush()
	var ok := false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 20000:
		OS.delay_msec(250)
		var buf := io.get_buffer(8192)
		var txt := buf.get_string_from_utf8()
		if txt.contains("(yes/no)") or txt.contains("Authorize"):
			io.store_string("yes\n")
			io.flush()
		var now := _info(mac)
		if now.contains("Paired: yes") or now.contains("Bonded: yes") or now.contains("Device " + mac):
			io.store_string("trust %s\n" % mac)
			io.flush()
			OS.delay_msec(800)
			if _info(mac).contains("Trusted: yes"):
				ok = true
				break
	io.store_string("quit\n")
	io.flush()
	OS.delay_msec(300)
	OS.kill(int(proc["pid"]))
	return ok
