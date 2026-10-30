extends Node
## The web browser: Firefox in kiosk mode (no bars, no buttons, nothing but the page), run like a game. Tephra
## drives it with the controller through a small virtual mouse and keyboard, and its own menus sit on top:
##   left stick  = move the pointer        right stick = scroll
##   Cross       = click (hold to drag)    Circle      = back
##   L3          = forward                 D-pad       = arrow keys
##   Square      = type text               Triangle    = go to an address
##   Options     = Enter                Create/Share = reload
##   L1 / R1    = the tab on the left / right (the tab list is in the menu: PS > Browser > Tabs)
##   PS          = control center (Close the browser is there, like Close game)
## Firefox keeps its own settings in ~/.local/share/tephra/browser, apart from any Firefox you use on the desktop,
## so logins (YouTube, Netflix...) stay between visits. Netflix and other DRM video need Firefox's Widevine,
## which it downloads by itself the first time (it is switched on in the settings below).

const Settings = preload("res://settings.gd")
const HOME_URL := "https://www.youtube.com/tv"
const SITES := [["YouTube", "https://www.youtube.com/tv"], ["Netflix", "https://www.netflix.com"], ["Twitch", "https://www.twitch.tv"], ["Google", "https://www.google.com"]]
const ID := "browser"
const PATTERN := "[t]ephra/browser"  # how its processes are found (the profile folder is on its command line)
const SPEED := 650.0       # pointer pixels per second with the stick all the way over
const SCROLL := 16.0       # wheel steps per second with the right stick all the way over (smooth, not in jumps)
const DEAD := 0.14

static var _plain_hinted := false
static var _marionette_on := false  # this launch has --marionette, so a click can be checked for a text box
var _probing := false
var _ptr := {}             # the virtual mouse + keyboard (python3 + /dev/uinput)
var _axes := [0.0, 0.0, 0.0, 0.0]
var _sent := ""

static func profile_dir() -> String:
	return OS.get_environment("HOME").path_join(".local/share/tephra/browser")

static func firefox() -> String:
	for p in ["firefox", "firefox-esr", "librewolf"]:
		if OS.execute("sh", ["-c", "command -v \"$0\" >/dev/null", p]) == 0:
			return p
	return ""

## What was typed as an address: a web address as it is, anything else becomes a search.
static func url_for(text: String) -> String:
	var t := text.strip_edges()
	if t.begins_with("http://") or t.begins_with("https://"):
		return t
	if not " " in t and "." in t:
		return "https://" + t
	return "https://www.google.com/search?q=" + t.uri_encode()

static func running() -> bool:
	return OS.execute("pgrep", ["-f", PATTERN], []) == 0

## The "game" Home starts for the browser (see home.gd _launch: a "cmd" is started directly, not through Steam).
static func game_entry(url: String, plain := false) -> Dictionary:
	var ff := firefox()
	_write_prefs()
	ensure_adblock()
	var cmd := [ff, "--kiosk", "--name", "tephra-browser", "--profile", profile_dir()]
	var page_mode := bool(Settings.get_value("browser_page_mode", true)) and not plain  # plain: a site that may refuse an automated browser (Nexus)
	_marionette_on = page_mode
	if page_mode:
		cmd.append("--marionette")  # lets Page view (page_view.gd) read the page; it also sets navigator.webdriver
	_forget_tabs()  # closing the browser closes every tab: it always opens fresh
	if url == "" and page_mode:
		url = _write_start_page()  # Tephra's own start page; Page view draws it in the theme
	cmd.append(url if url != "" else HOME_URL)
	return {"id": ID, "title": "Browser", "cmd": cmd, "browser": true, "plain": plain}

## Tabs from last time are not brought back: the files Firefox keeps them in are removed before it starts
## (never while it is still running).
static func _forget_tabs() -> void:
	if running():
		return
	var dir := profile_dir()
	for f in ["sessionstore.jsonlz4", "sessionstore.js", "sessionstore-backups/recovery.jsonlz4", "sessionstore-backups/recovery.baklz4", "sessionstore-backups/previous.jsonlz4"]:
		var path := dir.path_join(f)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

## The start page: a few big links, as a plain local page (Page view turns the links into tiles).
static func _write_start_page() -> String:
	var path := OS.get_environment("HOME").path_join(".local/share/tephra/browser-start.html")
	var html := "<!doctype html><html><head><meta charset=utf-8><title>Browser</title></head><body><h1>Where to?</h1><p>Pick a site, or press " + TephraGlyphs.btn("north") + " to type an address or a search.</p>"
	for s in SITES:
		html += '<p><a href="%s">%s</a></p>' % [s[1], s[0]]
	html += '<p><a href="https://en.wikipedia.org">Wikipedia</a></p><p><a href="https://www.reddit.com">Reddit</a></p></body></html>'
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(html)
	return "file://" + path

## Firefox settings for a console: no first-run pages, no "restore session?" question, no popups about default
## browser or updates, links open in the same page (there are no tabs to switch to), DRM video allowed.
static func _write_prefs() -> void:
	DirAccess.make_dir_recursive_absolute(profile_dir())
	var prefs := {
		"browser.shell.checkDefaultBrowser": false,
		"browser.startup.homepage_override.mstone": "\"ignore\"",
		"browser.aboutwelcome.enabled": false,
		"browser.startup.page": 1,  # always a fresh start: tabs are not restored (sign-ins are kept, they are cookies)
		"browser.sessionstore.resume_from_crash": false,
		"browser.sessionstore.max_tabs_undo": 0,
		"browser.sessionstore.max_windows_undo": 0,
		"browser.tabs.warnOnClose": false,
		"browser.link.open_newwindow": 1,
		"browser.link.open_newwindow.restriction": 0,
		"datareporting.policy.dataSubmissionEnabled": false,
		"toolkit.telemetry.reportingpolicy.firstRun": false,
		"app.update.auto": false,
		"media.eme.enabled": true,
		"media.gmp-widevinecdm.enabled": true,
		"media.gmp-widevinecdm.visible": true,
		"media.autoplay.default": 0,
		"full-screen-api.warning.timeout": 0,
		"full-screen-api.transition-duration.enter": "\"0 0\"",
		"full-screen-api.transition-duration.leave": "\"0 0\"",
		"ui.key.menuAccessKeyFocuses": false,
		"browser.download.useDownloadDir": true,
		# History is wiped every time the browser closes; sign-ins (cookies and site data) are kept. Newer Firefox reads the
		# "_v2" names, older ones the plain names, so both are set.
		"privacy.sanitize.sanitizeOnShutdown": true,
		"privacy.clearOnShutdown.history": true,
		"privacy.clearOnShutdown.formdata": true,
		"privacy.clearOnShutdown.downloads": true,
		"privacy.clearOnShutdown.cache": true,
		"privacy.clearOnShutdown.cookies": false,
		"privacy.clearOnShutdown.offlineApps": false,
		"privacy.clearOnShutdown.sessions": false,  # this one is logins (HTTP auth), not tabs
		"privacy.clearOnShutdown_v2.historyFormDataAndDownloads": true,
		"privacy.clearOnShutdown_v2.cache": true,
		"privacy.clearOnShutdown_v2.cookiesAndStorage": false,
		"places.history.enabled": true,
		"signon.rememberSignons": false,  # no "save this password?" box over the page
		"signon.autofillForms": false,
		"identity.fxaccounts.enabled": false,  # no Firefox sign-in
		"extensions.pocket.enabled": false,
		"dom.webnotifications.enabled": false,  # sites can't ask to send notifications
		"permissions.default.desktop-notification": 2,
		"permissions.default.geo": 2,
		"permissions.default.camera": 2,
		"permissions.default.microphone": 2,
		"cookiebanners.service.mode": 1,  # "reject all" on cookie banners where Firefox can
		"cookiebanners.service.mode.privateBrowsing": 1,
		"privacy.popups.showBrowserMessage": false,
		"browser.messaging-system.whatsNewPanel.enabled": false,
		"browser.translations.automaticallyPopup": false,
		"browser.sessionstore.interval": 1000,  # the open tabs are written down every second: Tephra's tab list reads them
		"browser.tabs.closeWindowWithLastTab": false,  # closing the last tab leaves the browser open (Tephra shows "New tab")
		"browser.newtabpage.enabled": false,
		"extensions.autoDisableScopes": 0,  # the ad blocker in the profile's extensions folder switches on by itself
		"extensions.enabledScopes": 15,
		"marionette.port": 2828,
		"layout.css.devPixelsPerPx": "\"1.5\"",  # bigger page text, for the TV distance
	}
	var lines := PackedStringArray()
	for k in prefs:
		var v = prefs[k]
		lines.append('user_pref("%s", %s);' % [k, str(v).to_lower() if v is bool else str(v)])
	var f := FileAccess.open(profile_dir().path_join("user.js"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")

## uBlock Origin, put into the browser's own profile (extensions/<id>.xpi, which Firefox installs on its own). It is
## downloaded once from Mozilla's add-on site in the background, so it is there from the next time the browser opens.
const ADBLOCK_ID := "uBlock0@raymondhill.net"
const ADBLOCK_URL := "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"

static func ensure_adblock() -> void:
	var dir := profile_dir().path_join("extensions")
	var xpi := dir.path_join(ADBLOCK_ID + ".xpi")
	if FileAccess.file_exists(xpi):
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var tmp := xpi + ".part"
	OS.create_process("sh", ["-c", "curl -fsSL -m 90 -o \"$1\" \"$2\" && mv \"$1\" \"$3\" || rm -f \"$1\"", "sh", tmp, ADBLOCK_URL, xpi])

# ---------- The virtual mouse and keyboard ----------
const PTR_PY := """import os, sys, struct, fcntl, time, threading
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_RELBIT = 0x40045564, 0x40045565, 0x40045566
UI_DEV_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405c5503, 0x5501, 0x5502
EV_SYN, EV_KEY, EV_REL = 0, 1, 2
REL_X, REL_Y, REL_HWHEEL, REL_WHEEL = 0, 1, 6, 8
REL_WHEEL_HI, REL_HWHEEL_HI = 11, 12  # smooth scrolling: 120 of these are one wheel notch
BTN = {"left": 272, "right": 273, "middle": 274}
K = {"esc": 1, "back": 158, "forward": 159, "enter": 28, "tab": 15, "backspace": 14, "space": 57,
     "up": 103, "down": 108, "left": 105, "right": 106, "ctrl": 29, "shift": 42, "alt": 56, "f5": 63, "f11": 87}
CH = {}
for i, c in enumerate("qwertyuiop"): CH[c] = (16 + i, False)
for i, c in enumerate("asdfghjkl"): CH[c] = (30 + i, False)
for i, c in enumerate("zxcvbnm"): CH[c] = (44 + i, False)
for i, c in enumerate("1234567890"): CH[c] = (2 + i, False)
for i, c in enumerate("!@#$%^&*()"): CH[c] = (2 + i, True)
for c in list(CH.keys()):
    if c.isalpha(): CH[c.upper()] = (CH[c][0], True)
CH.update({" ": (57, False), "-": (12, False), "_": (12, True), "=": (13, False), "+": (13, True),
    "[": (26, False), "{": (26, True), "]": (27, False), "}": (27, True), ";": (39, False), ":": (39, True),
    "'": (40, False), '"': (40, True), "`": (41, False), "~": (41, True), "\\\\": (43, False), "|": (43, True),
    ",": (51, False), "<": (51, True), ".": (52, False), ">": (52, True), "/": (53, False), "?": (53, True)})
try:
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
except OSError as e:
    print("cannot open /dev/uinput: %s" % e, file=sys.stderr); sys.exit(2)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_REL)
for code in list(BTN.values()) + list(K.values()) + [v[0] for v in CH.values()]:
    fcntl.ioctl(fd, UI_SET_KEYBIT, code)
for code in (REL_X, REL_Y, REL_HWHEEL, REL_WHEEL, REL_WHEEL_HI, REL_HWHEEL_HI):
    fcntl.ioctl(fd, UI_SET_RELBIT, code)
fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack("<HHHH80sI", 3, 0x1209, 0x7e02, 1, b"Tephra virtual pointer", 0))
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(0.6)
lock = threading.Lock()
def emit(t, c, v): os.write(fd, struct.pack("<qqHHi", 0, 0, t, c, v))
def syn(): emit(EV_SYN, 0, 0)
def press(code, down):
    with lock: emit(EV_KEY, code, 1 if down else 0); syn()
def tap(code, shift=False, ctrl=False):
    if ctrl: press(29, True)
    if shift: press(42, True)
    press(code, True); time.sleep(0.02); press(code, False)
    if shift: press(42, False)
    if ctrl: press(29, False)
    time.sleep(0.015)
vel = [0.0, 0.0, 0.0, 0.0]
acc = [0.0, 0.0, 0.0, 0.0]
sm = [0.0, 0.0]   # the scroll speed, eased so it never jerks
hi = [0.0, 0.0]   # smooth scroll units not sent yet
notch = [0, 0]    # the same in whole wheel notches, for programs that only read those
def mover():
    last = time.time()
    while True:
        time.sleep(1 / 125.0)
        now = time.time(); dt = now - last; last = now
        out = []
        for i in range(2):
            acc[i] += vel[i] * dt
            n = int(acc[i]); acc[i] -= n; out.append(n)
        wheel = []
        for k in range(2):
            tgt = vel[2 + k]
            rate = 24.0 if abs(tgt) < abs(sm[k]) else 14.0  # stops quickly, starts without a jerk
            sm[k] += (tgt - sm[k]) * min(1.0, dt * rate)
            if abs(sm[k]) < 0.4 and tgt == 0.0: sm[k] = 0.0
            hi[k] += sm[k] * 120.0 * dt
            n = int(hi[k]); hi[k] -= n
            notch[k] += n
            legacy = int(notch[k] / 120.0); notch[k] -= legacy * 120
            wheel.append((n, legacy))
        if any(out) or any(w[0] or w[1] for w in wheel):
            with lock:
                if out[0]: emit(EV_REL, REL_X, out[0])
                if out[1]: emit(EV_REL, REL_Y, out[1])
                if wheel[0][0]: emit(EV_REL, REL_HWHEEL_HI, wheel[0][0])
                if wheel[0][1]: emit(EV_REL, REL_HWHEEL, wheel[0][1])
                if wheel[1][0]: emit(EV_REL, REL_WHEEL_HI, -wheel[1][0])
                if wheel[1][1]: emit(EV_REL, REL_WHEEL, -wheel[1][1])
                syn()
threading.Thread(target=mover, daemon=True).start()
print("ready", flush=True)
for line in sys.stdin:
    p = line.rstrip("\\n").split(" ", 1)
    cmd, arg = p[0], (p[1] if len(p) > 1 else "")
    try:
        if cmd == "vel":
            v = [float(x) for x in arg.split()]
            for i in range(4): vel[i] = v[i]
        elif cmd == "btn":
            name, down = arg.split()
            press(BTN[name], down == "1")
        elif cmd == "key":
            tap(K[arg])
        elif cmd == "combo":
            names = arg.split()
            mods = [K[n] for n in names[:-1]]
            last = K[names[-1]] if names[-1] in K else CH[names[-1]][0]
            for m in mods: press(m, True)
            press(last, True); time.sleep(0.02); press(last, False)
            for m in reversed(mods): press(m, False)
            time.sleep(0.015)
        elif cmd == "ctrl":
            tap(CH[arg][0], False, True)
        elif cmd == "type":
            for c in arg:
                if c in CH: tap(CH[c][0], CH[c][1])
        elif cmd == "quit":
            break
    except Exception as e:
        print("bad command %r: %s" % (line, e), file=sys.stderr)
for i in range(4): vel[i] = 0.0
fcntl.ioctl(fd, UI_DEV_DESTROY)
"""

func start() -> void:
	if not _ptr.is_empty() and OS.is_process_running(int(_ptr["pid"])):
		return
	_ptr = OS.execute_with_pipe("python3", ["-c", PTR_PY])
	_logged_input = false
	await get_tree().create_timer(1.5).timeout
	if _ptr.is_empty() or not OS.is_process_running(int(_ptr["pid"])):
		var err := "" if _ptr.is_empty() else (_ptr["stderr"] as FileAccess).get_as_text().strip_edges()
		_log("browser pointer: NOT running (%s)" % err)
		_ptr = {}
	else:
		_log("browser pointer: ready")

var _logged_input := false

## Written to ~/.config/tephra/overlay.log with everything else about running games.
func _log(msg: String) -> void:
	var h = get_parent()
	if h != null and h.get("overlay") != null:
		h.overlay.log_line(msg)

func stop() -> void:
	if _ptr.is_empty():
		return
	_send("quit")
	OS.kill(int(_ptr["pid"]))
	_ptr = {}

func _exit_tree() -> void:
	stop()

func _send(line: String) -> void:
	if _ptr.is_empty() or not OS.is_process_running(int(_ptr["pid"])):
		return
	var io := _ptr["stdio"] as FileAccess
	io.store_line(line)
	io.flush()

## Stops the pointer and scrolling (when a menu opens over the browser, or it closes).
func halt() -> void:
	_axes = [0.0, 0.0, 0.0, 0.0]
	_sent = ""
	_send("vel 0 0 0 0")

func key(name: String) -> void:
	_send("key " + name)

## Types text into the page, then presses Enter if asked (an address: Ctrl+L first picks Firefox's hidden address bar).
func type_text(text: String, address := false) -> void:
	if address:
		_send("ctrl l")
		await get_tree().create_timer(0.15).timeout
	_send("type " + text.replace("\n", " "))
	if address:
		_send("key enter")

## After a click: if the page now has a text box in focus, Tephra's keyboard opens for it. Needs the web overlay
## setting (it is what starts Firefox with Marionette); a short one-off connection asks the page what has focus.
const FOCUS_JS := "var e=document.activeElement,n=0; while(e&&n++<6){ if(e.shadowRoot&&e.shadowRoot.activeElement){e=e.shadowRoot.activeElement;continue;} if(e.tagName==='IFRAME'||e.tagName==='FRAME'){try{var d=e.contentDocument; if(d&&d.activeElement&&d.activeElement!==d.body){e=d.activeElement;continue;}}catch(x){}} break; } if(!e) return false; if(e.isContentEditable) return true; if(e.tagName==='TEXTAREA') return !e.readOnly; if(e.tagName!=='INPUT') return false; return !e.readOnly && !e.disabled && /^(text|search|email|url|tel|number|password|)$/i.test(e.type||'text');"

## The check runs up to three times after a click (0.3 s, then 0.6 s after each miss): search boxes that slide open (X, YouTube)
## take focus a moment after the click, and the first try used to find nothing. Each attempt is written to
## ~/.config/tephra/overlay.log, so a keyboard that doesn't come up shows why (no connection to Firefox, or no text box).
func _probe_text_field(home, attempt := 0) -> void:
	if _probing or not _marionette_on:
		return
	_probing = true
	await get_tree().create_timer(0.3 if attempt == 0 else 0.6).timeout  # the click has landed and the page has moved focus
	var mar: Node = preload("res://marionette.gd").new()
	add_child(mar)
	mar.open_session(func(ok: bool) -> void:
		if not ok:
			_log("browser: text box check %d: no connection to Firefox (%s)" % [attempt + 1, str(mar.error)])
			mar.queue_free()
			_probing = false
			if attempt < 2:
				_probe_text_field(home, attempt + 1)
			return
		mar.script(FOCUS_JS, [], func(ok2: bool, v) -> void:
			mar.close()
			mar.queue_free()
			_probing = false
			if ok2 and v == true:
				if not home.keyboard.is_open and not home._in_overlay:
					_log("browser: text box in focus (check %d), opening the keyboard" % (attempt + 1))
					home.browser_keyboard(false)
			else:
				_log("browser: text box check %d: %s" % [attempt + 1, "no text box has focus" if ok2 else "the page did not answer (%s)" % str(v)])
				if attempt < 2:
					_probe_text_field(home, attempt + 1)))

## The controller while the browser has the screen. Returns true when the event was used.
func handle_input(event: InputEvent, home) -> bool:
	if not _logged_input:
		_logged_input = true
		_log("browser: controller input arriving (pointer %s)" % ("running" if not _ptr.is_empty() else "missing"))
	if _ptr.is_empty():
		start()  # it died or never started: try again
	if event is InputEventJoypadMotion:
		var a: int = event.axis
		if a > 3:
			return true
		_axes[a] = event.axis_value
		var v := []
		for i in 4:
			var x: float = _axes[i]
			var m := maxf(absf(x) - DEAD, 0.0) / (1.0 - DEAD)
			# the pointer keeps its fine control (squared); scrolling uses a gentler curve so it starts at once
			v.append(signf(x) * (m * m * SPEED if i < 2 else pow(m, 1.4) * SCROLL))
		var line := "vel %d %d %.1f %.1f" % [v[0], v[1], v[2], v[3]]
		if line != _sent:
			_sent = line
			_send(line)
		return true
	if not event is InputEventJoypadButton:
		return false
	var b: int = event.button_index
	var down: bool = event.pressed
	match b:
		JOY_BUTTON_A:
			_send("btn left %d" % int(down))
			if not down:
				if _marionette_on:
					_probe_text_field(home)  # a click on a text box opens Tephra's keyboard
				elif not _plain_hinted:
					_plain_hinted = true
					home.notify("This site runs without the web overlay, so the keyboard doesn't open by itself. Press Square to type.", "info")
		JOY_BUTTON_B:
			if down:
				key("back")
		JOY_BUTTON_LEFT_SHOULDER:
			if down:
				_send("combo ctrl shift tab")  # the tab on the left
		JOY_BUTTON_RIGHT_SHOULDER:
			if down:
				_send("combo ctrl tab")  # the tab on the right
		JOY_BUTTON_LEFT_STICK:
			if down:
				key("forward")
		JOY_BUTTON_DPAD_UP:
			if down:
				key("up")
		JOY_BUTTON_DPAD_DOWN:
			if down:
				key("down")
		JOY_BUTTON_DPAD_LEFT:
			if down:
				key("left")
		JOY_BUTTON_DPAD_RIGHT:
			if down:
				key("right")
		JOY_BUTTON_START:
			if down:
				key("enter")
		JOY_BUTTON_BACK:
			if down:
				key("f5")  # Create / Share / View: reload the page
		JOY_BUTTON_RIGHT_STICK:
			_send("btn right %d" % int(down))
		_:
			if b == TephraGlyphs.west_button() and down:
				home.browser_keyboard(false)
			elif b == TephraGlyphs.north_button() and down:
				home.browser_keyboard(true)
	return true

const TephraGlyphs = preload("res://glyphs.gd")

# ---------- Tabs ----------
## Firefox's open tabs, read from the file it writes them to (sessionstore-backups/recovery.jsonlz4):
## {"tabs": [{"title", "url"}], "current": index}. Empty when it can't be read. Safe on a worker thread.
static func read_tabs() -> Dictionary:
	var path := profile_dir().path_join("sessionstore-backups/recovery.jsonlz4")
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() < 12 or raw.slice(0, 8).get_string_from_ascii() != "mozLz40":
		return {}
	var size := raw.decode_u32(8)
	var text := _lz4_block(raw.slice(12), size).get_string_from_utf8()
	var data = JSON.parse_string(text)
	if not data is Dictionary or not data.has("windows") or (data["windows"] as Array).is_empty():
		return {}
	var wins: Array = data["windows"]
	var w: Dictionary = wins[clampi(int(data.get("selectedWindow", 1)) - 1, 0, wins.size() - 1)]
	var tabs: Array = []
	for t in w.get("tabs", []):
		var entries: Array = t.get("entries", [])
		if entries.is_empty():
			tabs.append({"title": "New tab", "url": ""})
			continue
		var e: Dictionary = entries[clampi(int(t.get("index", entries.size())) - 1, 0, entries.size() - 1)]
		var url := str(e.get("url", ""))
		var title := str(e.get("title", ""))
		tabs.append({"title": title if title != "" else ("New tab" if url.begins_with("about:") else url), "url": url})
	return {"tabs": tabs, "current": clampi(int(w.get("selected", 1)) - 1, 0, maxi(tabs.size() - 1, 0))}

## LZ4 block decompression (the format inside Firefox's .jsonlz4 files).
static func _lz4_block(src: PackedByteArray, out_size: int) -> PackedByteArray:
	var dst := PackedByteArray()
	dst.resize(out_size)
	var i := 0
	var o := 0
	var n := src.size()
	while i < n:
		var token := src[i]
		i += 1
		var lit := token >> 4
		if lit == 15:
			while i < n:
				var b := src[i]
				i += 1
				lit += b
				if b != 255:
					break
		for k in lit:
			if o >= out_size or i >= n:
				return dst
			dst[o] = src[i]
			o += 1
			i += 1
		if i + 1 >= n:
			break  # the last literals: no match after them
		var off := src[i] | (src[i + 1] << 8)
		i += 2
		var mlen := (token & 15) + 4
		if (token & 15) == 15:
			while i < n:
				var b2 := src[i]
				i += 1
				mlen += b2
				if b2 != 255:
					break
		var from := o - off
		if from < 0:
			return dst
		for k in mlen:
			if o >= out_size:
				return dst
			dst[o] = dst[from + k]
			o += 1
	return dst

## Moves Firefox to tab `to` from tab `from` (Ctrl+Tab steps; Ctrl+1..8 jumps when it can).
func switch_tab(from: int, to: int) -> void:
	if to == from:
		return
	if to < 8:
		_send("combo ctrl %d" % (to + 1))
		return
	var step := "combo ctrl tab" if to > from else "combo ctrl shift tab"
	for k in absi(to - from):
		_send(step)

func close_tab() -> void:
	_send("combo ctrl w")

## A new tab with this address (or search) in it.
func new_tab(text: String) -> void:
	_send("combo ctrl t")
	await get_tree().create_timer(0.3).timeout
	type_text(text, true)

# ---------- Sound ----------
## Makes sure the browser can be heard. Tephra mutes a game's sound while Home is open over it, and PipeWire
## remembers a muted Firefox for next time, so Firefox could start silent. Every Firefox stream is unmuted
## now and again a few seconds later (a page only gets a stream once it plays something).
func unmute_later() -> void:
	for wait in [0.5, 4.0, 12.0]:
		await get_tree().create_timer(wait).timeout
		unmute()

static func unmute() -> void:
	var out := []
	if OS.execute("pactl", ["list", "sink-inputs"], out) != 0 or out.is_empty():
		return
	var cur := ""
	var muted := false
	for line in String(out[0]).split("\n"):
		var l := line.strip_edges()
		if l.begins_with("Sink Input #"):
			cur = l.trim_prefix("Sink Input #")
			muted = false
		elif l.begins_with("Mute:"):
			muted = l.ends_with("yes")
		elif cur != "" and muted and (l.begins_with("application.process.binary") or l.begins_with("application.name")) \
				and ("firefox" in l.to_lower() or "librewolf" in l.to_lower()):
			OS.execute("pactl", ["set-sink-input-mute", cur, "0"], [])
			muted = false
