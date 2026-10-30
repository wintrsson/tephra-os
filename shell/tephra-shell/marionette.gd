extends Node
## Tephra's line to Firefox. Firefox started with --marionette listens on 127.0.0.1:2828 and takes commands
## (run a script in the page, go to an address, go back, list the open tabs). Page view (page_view.gd) uses it to
## read the page and to press things on it. Messages are "LENGTH:json" both ways; a command is
## [0, id, name, params] and its answer is [1, id, error, result].

const PORT := 2828
const GIVE_UP_MS := 9000   # Firefox may still be starting: keep trying this long
const ANSWER_MS := 25000

var state := "idle"        # idle | connecting | ready | failed
var error := ""

var _tcp: StreamPeerTCP
var _buf := PackedByteArray()
var _next_id := 1
var _pending := {}         # id -> {"cb": Callable, "until": ms}
var _started := 0
var _retry_at := 0
var _greeted := false
var _session_id := 0
var _on_ready: Callable

## Connects and opens a session. `done(ok)` is called once it is ready (or has given up).
func open_session(done: Callable) -> void:
	close()
	state = "connecting"
	error = ""
	_on_ready = done
	_started = Time.get_ticks_msec()
	_retry_at = 0
	_tcp = null
	set_process(true)

func close() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tcp = null
	_buf = PackedByteArray()
	_greeted = false
	_session_id = 0
	for id in _pending.keys():
		var cb: Callable = _pending[id]["cb"]
		_pending.erase(id)
		if cb.is_valid():
			cb.call(false, "closed")
	if state != "failed":
		state = "idle"

func _ready() -> void:
	set_process(false)

func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	if state == "connecting":
		if _tcp == null:
			if now < _retry_at:
				return
			_tcp = StreamPeerTCP.new()
			if _tcp.connect_to_host("127.0.0.1", PORT) != OK:
				_tcp = null
				_retry_at = now + 300
				_check_give_up(now)
				return
		_tcp.poll()
		match _tcp.get_status():
			StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
				_tcp = null
				_retry_at = now + 300
				_check_give_up(now)
				return
			StreamPeerTCP.STATUS_CONNECTED:
				_read_frames()
				_check_give_up(now)
	elif state == "ready":
		_tcp.poll()
		if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			state = "failed"
			error = "The browser closed the connection."
			close()
			return
		_read_frames()
	for id in _pending.keys():
		if now > int(_pending[id]["until"]):
			var cb: Callable = _pending[id]["cb"]
			_pending.erase(id)
			if cb.is_valid():
				cb.call(false, "timeout")

func _check_give_up(now: int) -> void:
	if state != "connecting":
		return
	if now - _started > GIVE_UP_MS:
		_fail("Couldn't reach the browser. Page view needs it started in Page mode.")

func _fail(text: String) -> void:
	state = "failed"
	error = text
	var cb := _on_ready
	_on_ready = Callable()
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tcp = null
	if cb.is_valid():
		cb.call(false)

## Sends a command. `cb(ok: bool, value)` gets the result (ok) or the error text.
func command(name: String, params: Dictionary, cb: Callable) -> void:
	if _tcp == null or (state != "ready" and name != "WebDriver:NewSession"):
		if cb.is_valid():
			cb.call(false, "not connected")
		return
	var id := _next_id
	_next_id += 1
	_pending[id] = {"cb": cb, "until": Time.get_ticks_msec() + ANSWER_MS}
	_send_frame(JSON.stringify([0, id, name, params]))

## Runs a script in the page (it may `return` a value). cb(ok, value).
func script(src: String, args: Array, cb: Callable) -> void:
	command("WebDriver:ExecuteScript", {"script": src, "args": args}, func(ok: bool, v) -> void:
		if not cb.is_valid():
			return
		if ok and v is Dictionary and (v as Dictionary).has("value"):
			cb.call(true, (v as Dictionary)["value"])
		else:
			cb.call(ok, v))

func _send_frame(json: String) -> void:
	var body := json.to_utf8_buffer()
	var head := ("%d:" % body.size()).to_utf8_buffer()
	_tcp.put_data(head + body)

func _read_frames() -> void:
	var n := _tcp.get_available_bytes()
	if n > 0:
		var got := _tcp.get_data(n)
		if int(got[0]) == OK:
			_buf.append_array(got[1] as PackedByteArray)
	while true:
		var colon := _buf.find(58)  # ":"
		if colon < 1 or colon > 12:
			return
		var len_text := _buf.slice(0, colon).get_string_from_ascii()
		if not len_text.is_valid_int():
			_buf = PackedByteArray()
			return
		var length := int(len_text)
		if _buf.size() < colon + 1 + length:
			return
		var body := _buf.slice(colon + 1, colon + 1 + length).get_string_from_utf8()
		_buf = _buf.slice(colon + 1 + length)
		_frame(body)

func _frame(body: String) -> void:
	var msg = JSON.parse_string(body)
	if not _greeted and msg is Dictionary:
		_greeted = true
		command("WebDriver:NewSession", {"capabilities": {}}, _session_started)
		return
	if not msg is Array or (msg as Array).size() < 4:
		return
	var m: Array = msg
	if int(m[0]) != 1:
		return
	var id := int(m[1])
	if not _pending.has(id):
		return
	var cb: Callable = _pending[id]["cb"]
	_pending.erase(id)
	if not cb.is_valid():
		return
	if m[2] != null:
		var e = m[2]
		cb.call(false, str((e as Dictionary).get("message", "error")) if e is Dictionary else str(e))
	else:
		cb.call(true, m[3])

func _session_started(ok: bool, value) -> void:
	var cb := _on_ready
	_on_ready = Callable()
	if ok:
		state = "ready"
		_session_id = 1
	else:
		_fail("The browser wouldn't start a Page view session (%s)." % str(value))
		return
	if cb.is_valid():
		cb.call(true)
