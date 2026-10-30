extends Node
const TephraGlyphs = preload("res://glyphs.gd")
const Themes = preload("res://themes.gd")
const Motion = preload("res://motion.gd")
## Everything Tephra needs to show its menus on top of a running game:
##  - a virtual keyboard (so Tephra can press Esc for the game, which makes the game pause itself),
##  - a small KWin script (so Tephra can come to the front, and hand the screen back to the game),
##  - a picture of the paused game (Spectacle), shown behind the menu,
##  - closing the game when you ask for that and nothing else.
## Home (home.gd) decides when each of these happens. Everything is logged to
## ~/.config/tephra/overlay.log, so when something doesn't work the log says which step.

signal confirm_done(yes: bool)

var TEXT: Color = Themes.c("text")
var MUTED: Color = Themes.c("muted")

var vkey_ok := false
var kwin_ok := false
var confirm_open := false

var _vkey := {}
var _confirm_root: Control
var _confirm_title: Label
var _confirm_body: Label
var _confirm_hints: HBoxContainer

# A tiny virtual keyboard made with /dev/uinput (no extra packages needed). It stays running and
# reads "key esc" lines. Needs the one-time permission setup (70-tephra-uinput.rules).
const VKEY_PY := """import os, sys, struct, fcntl, time
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_SETUP = 0x405c5503
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502
KEYS = {"esc": 1, "enter": 28, "space": 57, "p": 25, "tab": 15, "pause": 119, "f10": 68}
try:
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
except OSError as e:
    print("cannot open /dev/uinput: %s" % e, file=sys.stderr)
    sys.exit(2)
fcntl.ioctl(fd, UI_SET_EVBIT, 1)
for code in KEYS.values():
    fcntl.ioctl(fd, UI_SET_KEYBIT, code)
fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack("<HHHH80sI", 3, 0x1209, 0x7e01, 1, b"Tephra virtual keyboard", 0))
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(0.6)

def emit(t, c, v):
    os.write(fd, struct.pack("<qqHHi", 0, 0, t, c, v))

def tap(code):
    emit(1, code, 1)
    emit(0, 0, 0)
    time.sleep(0.06)
    emit(1, code, 0)
    emit(0, 0, 0)

print("ready", flush=True)
for line in sys.stdin:
    parts = line.split()
    if not parts:
        continue
    if parts[0] == "key" and len(parts) > 1 and parts[1] in KEYS:
        tap(KEYS[parts[1]])
    elif parts[0] == "quit":
        break
fcntl.ioctl(fd, UI_DEV_DESTROY)
"""

# A KWin script. KWin is the part of Plasma that decides which window is on top, and on Wayland an
# app is not allowed to raise itself, so Tephra asks KWin through two named shortcuts:
#   TephraRaise  : remember the window that has focus (the game), then focus Tephra.
#                  Tephra comes up almost see-through (the game still shows through), so the moment
#                  before its first picture is drawn is never a black flash.
#   TephraReveal : make Tephra fully visible again.
#   TephraReturn : give focus back to that window.
#   TephraCloseGame : ask that window to close (the polite way).
const FOCUS_JS := """var prev = null;
function allWindows() {
    if (workspace.windowList) { return workspace.windowList(); }
    return workspace.clientList();
}
function isTephra(w) {
    var c = String(w.resourceClass).toLowerCase();
    var n = String(w.resourceName).toLowerCase();
    var t = String(w.caption).toLowerCase();
    return c.indexOf("godot") >= 0 || c.indexOf("tephra") >= 0 || n.indexOf("godot") >= 0 || n.indexOf("tephra") >= 0 || t.indexOf("tephra") >= 0;
}
function isGame(w) {
    var c = String(w.resourceClass).toLowerCase();
    var n = String(w.resourceName).toLowerCase();
    var list = ["steam_app_", "pcsx2", "net.pcsx2", "retroarch", "dolphin", "cemu", "tephra-browser", "firefox",
                "mpv", "vlc", "io.github.celluloid_player", "celluloid", "org.kde.haruna", "haruna", "org.gnome.totem", "totem", "modmanager.exe"];
    for (var i = 0; i < list.length; i++) {
        if (c.indexOf(list[i]) === 0 || n.indexOf(list[i]) === 0) { return true; }
    }
    return false;
}
function gameWindow() {
    if (prev) { return prev; }
    var all = allWindows();
    var found = null;
    for (var i = 0; i < all.length; i++) {
        if (isGame(all[i])) { found = all[i]; }
    }
    return found;
}
function setOpacity(w, v) {
    try { w.opacity = v; } catch (e) { print("tephra-focus: could not set opacity: " + e); }
}
function setActive(w) {
    if (workspace.activeWindow !== undefined) { workspace.activeWindow = w; } else { workspace.activeClient = w; }
}
registerShortcut("TephraRaise", "Tephra: show over the game", "", function () {
    var a = workspace.activeWindow !== undefined ? workspace.activeWindow : workspace.activeClient;
    if (a && !isTephra(a)) { prev = a; }
    var all = allWindows();
    for (var i = 0; i < all.length; i++) {
        if (isTephra(all[i])) { setOpacity(all[i], 0.02); setActive(all[i]); print("tephra-focus: raised Tephra, game window = " + (prev ? prev.caption : "none")); return; }
    }
    print("tephra-focus: Tephra window not found");
});
// Raise Tephra over the game and show it in one go (the menu over a running game opens with a single call).
function showTephra(op) {
    var a = workspace.activeWindow !== undefined ? workspace.activeWindow : workspace.activeClient;
    if (a && !isTephra(a)) { prev = a; }
    var all = allWindows();
    for (var i = 0; i < all.length; i++) {
        if (isTephra(all[i])) {
            try { workspace.raiseWindow(all[i]); } catch (e) {}
            setActive(all[i]); setOpacity(all[i], op);
            print("tephra-focus: Tephra shown over " + (prev ? prev.caption : "nothing"));
            return;
        }
    }
}
// Developer option: keep Tephra's window under every other app (to see what is going on above it).
registerShortcut("TephraSink", "Tephra: stay under all apps", "", function () {
    var t = tephraWindow();
    if (!t) { return; }
    try { t.keepAbove = false; t.keepBelow = true; } catch (e) {}
    print("tephra-focus: Tephra kept under all apps");
});
registerShortcut("TephraUnsink", "Tephra: stop staying under all apps", "", function () {
    var t = tephraWindow();
    if (!t) { return; }
    try { t.keepBelow = false; } catch (e) {}
    print("tephra-focus: Tephra no longer kept under all apps");
});
registerShortcut("TephraShow", "Tephra: show over the game at once", "", function () { showTephra(1.0); });
registerShortcut("TephraShowGlass", "Tephra: show over the game, see-through", "", function () { showTephra(0.84); });
registerShortcut("TephraReveal", "Tephra: show fully", "", function () {
    var all = allWindows();
    for (var i = 0; i < all.length; i++) {
        if (isTephra(all[i])) { setOpacity(all[i], 1.0); print("tephra-focus: Tephra fully visible"); return; }
    }
});
registerShortcut("TephraGlass", "Tephra: show as a see-through menu", "", function () {
    var all = allWindows();
    for (var i = 0; i < all.length; i++) {
        if (isTephra(all[i])) { setOpacity(all[i], 0.84); print("tephra-focus: Tephra see-through over the game"); return; }
    }
});
registerShortcut("TephraReturn", "Tephra: back to the game", "", function () {
    var g = gameWindow();
    if (g) { setActive(g); print("tephra-focus: back to " + g.caption); } else { print("tephra-focus: no game window to return to"); }
});
registerShortcut("TephraCloseGame", "Tephra: close the game window", "", function () {
    var g = gameWindow();
    if (g) { g.closeWindow(); print("tephra-focus: asked " + g.caption + " to close"); prev = null; }
});
// Starting a game: Tephra's loading screen is held above everything (TephraHold), so the game's window can open
// underneath it. Once the game has shown its first frames, the loading screen fades away over it and lets go,
// instead of the game popping up all at once. TephraRelease does the same fade at any time; it also lets go by
// itself after 4 minutes, so Tephra can never get stuck on top.
var holding = null;
var holdId = 0;
function tephraWindow() {
    var all = allWindows();
    for (var i = 0; i < all.length; i++) { if (isTephra(all[i])) { return all[i]; } }
    return null;
}
function later(ms, fn) {
    try { var tm = new QTimer(); tm.singleShot = true; tm.interval = ms; tm.timeout.connect(fn); tm.start(); }
    catch (e) { fn(); }
}
function letGo() {
    var t = holding;
    holding = null;
    if (!t) { return; }
    try { t.keepAbove = false; } catch (e) {}
    setOpacity(t, 1.0);
    print("tephra-focus: let go of the loading screen (no fade)");
}
function fadeAway(g) {
    var t = holding;
    if (!t) { return; }
    if (!g && !gameWindow()) { letGo(); return; }  // nothing to fade into: fading would only show the desktop
    holding = null;
    var steps = 24;
    var k = 0;
    function step() {
        k += 1;
        if (k >= steps) {
            setOpacity(t, 0.0);
            try { t.keepAbove = false; } catch (e) {}
            var game = g || gameWindow();
            if (game) {
                try { workspace.raiseWindow(game); } catch (e) {}
                setActive(game);
            }
            later(400, function () { setOpacity(t, 1.0); });
            print("tephra-focus: faded into the game");
            return;
        }
        setOpacity(t, 1.0 - k / steps);
        later(30, step);
    }
    step();
}
registerShortcut("TephraHold", "Tephra: hold the loading screen over the game", "", function () {
    var t = tephraWindow();
    if (!t) { return; }
    try { t.keepAbove = true; } catch (e) {}
    setOpacity(t, 1.0);
    holding = t;
    holdId += 1;
    var mine = holdId;
    later(240000, function () { if (holding && holdId === mine) { fadeAway(null); } });
    print("tephra-focus: holding the loading screen");
});
// Steam's own popups (the controller "Battery low" one, friends, downloads) are windows named "notificationtoasts...".
// Steam has no switch for some of them, so they are made invisible and kept under everything.
function hideSteamToast(w) {
    try {
        if (!w) { return; }
        var cls = String(w.resourceClass).toLowerCase();
        var small = false;
        try { small = (cls === "steam" || cls === "steamwebhelper") && w.frameGeometry.width <= 520 && w.frameGeometry.height <= 170; } catch (e2) {}
        if (String(w.caption).indexOf("notificationtoasts") !== 0 && !small) { return; }
        setOpacity(w, 0.0);
        w.keepAbove = false; w.keepBelow = true; w.skipTaskbar = true; w.skipSwitcher = true;
        print("tephra-focus: hid a Steam popup: " + w.caption + " / " + w.resourceClass);
    } catch (e) {}
}
registerShortcut("TephraRelease", "Tephra: fade into the game", "", function () { fadeAway(null); });
// Back to the game from a menu. Tephra steps its own window's opacity down with TephraOp00..TephraOp50 (0-100 % in 2 %
// steps; KWin 6 scripts have no timer of their own, so tephra-fade.py paces the fade from outside, about one step per
// frame), then TephraFadeDone hands the screen to the game, which is already running again underneath.
for (var opi = 0; opi <= 50; opi++) {
    (function (v) {
        var nm = "TephraOp" + (v < 10 ? "0" : "") + v;
        registerShortcut(nm, "Tephra: window opacity " + (v * 2) + "%", "", function () {
            var t = tephraWindow();
            if (t) { try { t.keepAbove = false; } catch (e) {} setOpacity(t, v / 50); }
        });
    })(opi);
}
registerShortcut("TephraFadeDone", "Tephra: faded out, back to the game", "", function () {
    var t = tephraWindow();
    var g = gameWindow();
    if (g) {
        try { workspace.raiseWindow(g); } catch (e) {}
        setActive(g);
    }
    // Tephra stays fully see-through. Making it visible again here (it was meant to be under the game by now) showed it
    // on top for a moment while KWin was still bringing the game forward: the blurred picture alone, as a blurry image
    // between the menu and the game. Every way back (TephraShow, TephraReveal, TephraHold) sets its opacity again.
    if (!g && t) { setOpacity(t, 1.0); }  // no game to show: never leave Tephra invisible over nothing
    print("tephra-focus: faded back into " + (g ? g.caption : "nothing (no game window)"));
});
registerShortcut("TephraLetGo", "Tephra: stop holding the loading screen, no fade", "", function () { letGo(); });
// A game (or emulator) window that opens takes focus and is remembered, so Tephra can always hand focus back to it.
// (Emulators from Flatpak often open without becoming the active window, which left the pad going to Tephra.)
var added = workspace.windowAdded !== undefined ? workspace.windowAdded : workspace.clientAdded;
if (added) {
    added.connect(function (w) {
        hideSteamToast(w);
        try { w.captionChanged.connect(function () { hideSteamToast(w); }); } catch (e) {}
        if (w && !isTephra(w) && isGame(w)) {
            prev = w; setActive(w); print("tephra-focus: new game window " + w.caption);
            if (holding) { later(900, function () { fadeAway(w); }); }  // its first frames are drawn under the loading screen
        }
    });
}
var removed = workspace.windowRemoved !== undefined ? workspace.windowRemoved : workspace.clientRemoved;
if (removed) {
    removed.connect(function (w) { if (prev === w) { prev = null; } });
}
print("tephra-focus: loaded");
"""

func _dir() -> String:
	return OS.get_environment("HOME") + "/.config/tephra"

func log_line(msg: String) -> void:
	DirAccess.make_dir_recursive_absolute(_dir())
	var path := _dir() + "/overlay.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s  %s" % [Time.get_datetime_string_from_system(), msg])
	f.close()

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()

func _exit_tree() -> void:
	for id in _shortcut_tasks.keys():
		WorkerThreadPool.wait_for_task_completion(id)  # never free this while a shortcut is still running
	_shortcut_tasks.clear()
	thaw_game()  # never leave a game frozen behind a closed Tephra
	if not _vkey.is_empty() and OS.is_process_running(int(_vkey["pid"])):
		OS.kill(int(_vkey["pid"]))

# ---------- Start-up ----------
func start() -> void:
	DirAccess.make_dir_recursive_absolute(_dir())
	_write(_dir() + "/tephra-vkey.py", VKEY_PY)
	_write(_dir() + "/tephra-focus.js", FOCUS_JS)
	_start_vkey()
	_load_kwin_script()
	start_spectacle()

func _start_vkey() -> void:
	_vkey = OS.execute_with_pipe("python3", [_dir() + "/tephra-vkey.py"])
	if _vkey.is_empty():
		log_line("virtual keyboard: could not start python3")
		return
	await get_tree().create_timer(1.4).timeout
	vkey_ok = OS.is_process_running(int(_vkey["pid"]))
	if vkey_ok:
		log_line("virtual keyboard: ready")
	else:
		var err := (_vkey["stderr"] as FileAccess).get_as_text().strip_edges()
		log_line("virtual keyboard: NOT running (%s). Games will be frozen instead of paused until this is set up." % err)

func _bus(args: Array) -> Array:
	var out := []
	var rc := OS.execute("busctl", ["--user", "call"] + args, out, true)
	var text := ""
	for o in out:
		text += str(o)
	return [rc, text.strip_edges()]

func _load_kwin_script() -> void:
	var path := _dir() + "/tephra-focus.js"
	_bus(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", "unloadScript", "s", "tephra-focus"])
	var r := _bus(["org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", "loadScript", "ss", path, "tephra-focus"])
	var re := RegEx.new()
	re.compile("(\\d+)")
	var m := re.search(str(r[1]))
	if int(r[0]) != 0 or m == null:
		log_line("KWin script: could not load (exit %d: %s)" % [int(r[0]), r[1]])
		return
	var sid := m.get_string(1)
	var r2 := _bus(["org.kde.KWin", "/Scripting/Script" + sid, "org.kde.kwin.Script", "run"])
	kwin_ok = int(r2[0]) == 0
	log_line("KWin script: loaded as %s, run exit %d %s" % [sid, int(r2[0]), r2[1]])

# ---------- The game's own pause ----------
## Presses a key on the virtual keyboard (the game has focus when this is called).
func key(keyname: String) -> bool:
	if _vkey.is_empty() or not OS.is_process_running(int(_vkey["pid"])):
		vkey_ok = false
		log_line("key %s: no virtual keyboard" % keyname)
		return false
	var io := _vkey["stdio"] as FileAccess
	io.store_line("key " + keyname)
	io.flush()
	log_line("key %s sent" % keyname)
	return true

# ---------- Windows ----------
func _shortcut(shortcut_name: String) -> bool:
	var r := _bus(["org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component", "invokeShortcut", "s", shortcut_name])
	log_line("%s -> exit %d %s" % [shortcut_name, int(r[0]), r[1]])
	return int(r[0]) == 0

## Runs KWin shortcuts one after another on a worker thread, so the slow D-Bus calls (they can take a
## few hundred ms while a game is hogging the GPU) never freeze Tephra's own frames. Await it.
func run_shortcuts(names: Array, gap_ms := 0) -> void:
	var id := WorkerThreadPool.add_task(func() -> void:
		for i in names.size():
			_shortcut(str(names[i]))
			if gap_ms > 0 and i < names.size() - 1:
				OS.delay_msec(gap_ms))
	_shortcut_tasks[id] = true
	while not WorkerThreadPool.is_task_completed(id):
		await get_tree().process_frame
	if _shortcut_tasks.erase(id):
		WorkerThreadPool.wait_for_task_completion(id)

var _shortcut_tasks := {}

func raise_tephra() -> bool:
	var ok := _shortcut("TephraRaise")
	DisplayServer.window_move_to_foreground()  # a second, polite ask
	return ok

## Fades Tephra's window out over the game (eased in and out), then gives the game the screen and the focus. The steps
## run in one shell on a worker thread, so a slow D-Bus answer while the game is busy never holds up Tephra's frames.
const FADE_STEPS := 14

var _py_ok := -1  # python3 is there (1) or not (0); -1 = not looked yet

## Wakes the paused game and lets its sound through, in the background (returns at once).
func wake_game() -> void:
	var sh := _wake_script()
	if sh != "":
		OS.create_process("sh", ["-c", sh])

func _wake_script() -> String:
	var sh := ""
	if not _frozen.is_empty():
		sh += "kill -CONT %s 2>/dev/null\n" % " ".join(_frozen)
		log_line("unfroze %d processes" % _frozen.size())
		_frozen = PackedStringArray()
	if not _muted.is_empty():
		var un := ""
		for si in _muted:
			un += "pactl set-sink-input-mute %s 0 2>/dev/null; " % si
		sh += "( %s) &\n" % un
		_muted = PackedStringArray()
	return sh

func fade_into_game(secs := 0.36, before := "") -> void:
	# tephra-fade.py keeps one connection to the bus and sends a step about every frame: smooth. If it can't run, the same
	# fade in fewer, coarser steps, each its own busctl call.
	var py := ProjectSettings.globalize_path("res://tephra-fade.py")
	var call := "busctl --user call org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component invokeShortcut s"
	var sh := before
	if _py_ok < 0:
		_py_ok = 1 if OS.execute("sh", ["-c", "command -v python3 >/dev/null"]) == 0 else 0
	if FileAccess.file_exists(py) and _py_ok == 1:
		sh += "python3 -I '%s' %.3f && exit 0\n" % [py.replace("'", ""), secs]
	for k in range(1, FADE_STEPS):
		var v := 0.5 + 0.5 * cos(PI * float(k) / FADE_STEPS)
		sh += "%s TephraOp%02d >/dev/null 2>&1; sleep %.3f\n" % [call, roundi(v * 50.0), secs / FADE_STEPS]
	sh += "%s TephraOp00 >/dev/null 2>&1\n%s TephraFadeDone >/dev/null 2>&1\n" % [call, call]
	var t0 := Time.get_ticks_msec()
	var id := WorkerThreadPool.add_task(func() -> void: OS.execute("sh", ["-c", sh], [], true))
	while not WorkerThreadPool.is_task_completed(id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(id)
	log_line("faded back into the game in %d ms" % (Time.get_ticks_msec() - t0))

## Makes Tephra fully visible after raise_tephra() (which brings it up nearly transparent).
## glass = leave it a little see-through, so the live game still shows dimly behind the menu.
func reveal_tephra(glass := false) -> bool:
	return _shortcut("TephraGlass" if glass else "TephraReveal")

## Starting a game: the loading screen stays on top while the game opens under it, then fades into it.
func hold_loading(on: bool) -> void:
	run_shortcuts(["TephraHold" if on else "TephraRelease"])

## Stops holding Tephra on top without fading it (a cancelled or failed launch: there is no game to fade into).
func let_go() -> void:
	run_shortcuts(["TephraLetGo"])

func close_game_window() -> bool:
	return _shortcut("TephraCloseGame")

# ---------- Picture of the paused game ----------
## Takes a picture of the game (the active window) with Spectacle. Spectacle can stay running for
## a few seconds after it has saved the file, so this waits for the file, not for the program.
## Returns null (black background) when Spectacle isn't installed or fails.
# Spectacle takes a while to start (most of the wait before the menu shows), so home.gd starts it the
# moment the PS button goes DOWN (prefetch_shot); by the time the button comes back up and the menu is
# wanted, the picture is usually ready or nearly so.
const SHOT_PATH := "/tmp/tephra-overlay-shot.jpg"
var _shot_t0 := -1

func _spectacle_ok() -> bool:
	if OS.execute("which", ["spectacle"], []) != 0:
		log_line("screenshot: spectacle is not installed (pacman -S spectacle)")
		return false
	return true

## Starting Spectacle takes about 0.75 s, which was most of the wait before the menu showed. So Spectacle is started
## once, at boot, in its background mode (`spectacle --dbus`): it then sits idle and answers a request on the desktop
## message bus (D-Bus) in a fraction of that. It saves the picture into its own screenshots folder and sends a
## "ScreenshotTaken" signal; Tephra cannot listen for signals, so it watches that folder for the new file instead.
## If the running Spectacle does not answer in time, the old way (start Spectacle for each picture) takes over, and
## after two misses in a row the running one is not asked again this session.
## Turn it off by creating ~/.config/tephra/no_spectacle_service.
const SVC_PATIENCE_MS := 900  # how long the running Spectacle gets before the old way is started as well
var _spec_dir := ""
var _spec_known := {}       # file names already in the folder when a grab started: anything else is the new picture
var _spec_fail := 0
var _shot_svc := false      # the grab now under way was asked of the running Spectacle
var _shot_src := SHOT_PATH  # where the finished picture of the last wait is

func _spec_enabled() -> bool:
	return _spec_fail < 2 and not FileAccess.file_exists(_dir() + "/no_spectacle_service")

## Run once at boot. Harmless if one is already running: only one Spectacle can own the bus name.
func start_spectacle() -> void:
	if not _spec_enabled() or not _spectacle_ok():
		return
	OS.create_process("spectacle", ["--dbus"])
	log_line("screenshot: started Spectacle in background mode (it saves into %s)" % _spec_folder())

## Where Spectacle saves its pictures (its own setting; the usual default if that cannot be read).
func _spec_folder() -> String:
	if _spec_dir != "":
		return _spec_dir
	var home := OS.get_environment("HOME")
	var out: Array = []
	var d := ""
	if OS.execute("kreadconfig6", ["--file", "spectaclerc", "--group", "Save", "--key", "defaultSaveLocation"], out) == 0 and not out.is_empty():
		d = str(out[0]).strip_edges().trim_prefix("file://").replace("%20", " ")
	if d.begins_with("~"):
		d = home + d.substr(1)
	if d == "" or not d.begins_with("/"):
		d = home + "/Pictures/Screenshots"
	_spec_dir = d
	return d

## Asks the running Spectacle for a picture of the active window (the game). Returns false if it cannot be asked.
func _spec_ask() -> bool:
	if not _spec_enabled():
		return false
	_spec_known.clear()
	for f in DirAccess.get_files_at(_spec_folder()):
		_spec_known[f] = true
	# ActiveWindow(include decorations, include mouse pointer, include shadow): none of the three, the game at its own
	# size. When Tephra's own (invisible) window has the focus, the "active window" would be Tephra and come out black,
	# so then CurrentScreen (no mouse pointer) takes what is showing on the screen instead.
	# The call itself does not wait for the picture (the method has no reply).
	if _grab_screen:
		OS.create_process("busctl", ["--user", "call", "org.kde.Spectacle", "/", "org.kde.Spectacle", "CurrentScreen", "i", "0"])
	else:
		OS.create_process("busctl", ["--user", "call", "org.kde.Spectacle", "/", "org.kde.Spectacle", "ActiveWindow", "iii", "0", "0", "0"])
	return true

var _grab_screen := false  # this grab takes the whole screen (Tephra had the focus), not the active window

## Has the picture of the grab under way actually been taken? Its file showing up is the sign (it is written after the
## picture is taken). The menu must not come up before that: Spectacle takes the picture a moment after it is asked,
## and a quick PS tap used to bring Tephra's window up first, so the picture was of Tephra's own black window.
## True as well when no grab is under way.
func shot_taken() -> bool:
	if _shot_t0 < 0:
		return true
	if _shot_svc:
		return _spec_new_file() != ""
	return FileAccess.file_exists(SHOT_PATH)

## The new picture in Spectacle's folder, or "" if it has not appeared yet.
func _spec_new_file() -> String:
	var dir := _spec_folder()
	for f in DirAccess.get_files_at(dir):
		if not _spec_known.has(f) and f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			return dir.path_join(f)
	return ""

## The running Spectacle did not answer: start the old way too, and count the miss.
func _spec_give_up() -> void:
	_spec_fail += 1
	_shot_svc = false
	log_line("screenshot: the running Spectacle did not answer in %d ms (miss %d), starting it the old way" % [SVC_PATIENCE_MS, _spec_fail])
	DirAccess.remove_absolute(SHOT_PATH)
	OS.create_process("spectacle", ["-m" if _grab_screen else "-a", "-b", "-n", "-o", SHOT_PATH])

## Starts grabbing the game's window in the background (no window, no notification).
func prefetch_shot() -> void:
	if _shot_t0 >= 0 and Time.get_ticks_msec() - _shot_t0 < 3000:
		return  # one is already on its way
	if not _spectacle_ok():
		return
	DirAccess.remove_absolute(SHOT_PATH)
	_shot_t0 = Time.get_ticks_msec()
	_grab_screen = DisplayServer.window_is_focused()
	log_line("screenshot: grabbing %s" % ("the whole screen (Tephra's window had the focus)" if _grab_screen else "the game's window"))
	_shot_svc = _spec_ask()
	if not _shot_svc:
		OS.create_process("spectacle", ["-m" if _grab_screen else "-a", "-b", "-n", "-o", SHOT_PATH])

## Waits for the picture of the current grab to be complete (its size stops changing), and sets _shot_src to where
## it is. Checks every frame. Works for both ways of grabbing (the running Spectacle, or one started just now).
func _await_shot(t0: int, max_ms: int) -> bool:
	var last := -1
	var stable := 0
	var seen := ""
	while Time.get_ticks_msec() - t0 < max_ms:
		await get_tree().process_frame
		var path := SHOT_PATH
		if _shot_svc:
			path = _spec_new_file()
			if path == "":
				if Time.get_ticks_msec() - t0 > SVC_PATIENCE_MS:
					_spec_give_up()
				continue
		if not FileAccess.file_exists(path):
			continue
		if path != seen:
			seen = path
			last = -1
			stable = 0
		var f := FileAccess.open(path, FileAccess.READ)
		var sz := f.get_length() if f != null else 0
		f = null
		if sz > 0 and sz == last:
			stable += 1
			if stable >= 2:
				_shot_src = path
				if _shot_svc:
					_spec_fail = 0  # it answered: a miss earlier on does not count against it
				return true
		else:
			stable = 0
		last = sz
	_shot_src = SHOT_PATH
	return not _shot_svc and FileAccess.file_exists(SHOT_PATH)

## Waits for a file Spectacle is writing to be complete (its size stops changing). Checks every frame.
func _await_file(path: String, t0: int, max_ms: int) -> bool:
	var last := -1
	var stable := 0
	while Time.get_ticks_msec() - t0 < max_ms:
		await get_tree().process_frame
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		var sz := f.get_length() if f != null else 0
		f = null
		if sz > 0 and sz == last:
			stable += 1
			if stable >= 2:
				return true
		else:
			stable = 0
		last = sz
	return FileAccess.file_exists(path)

## The picture of the game for behind the menu. Gives up after max_ms (from when the grab started), so the
## menu never waits long; home.gd then uses the game's artwork instead.
func screenshot(max_ms := 6000) -> Image:
	if _shot_t0 < 0 or Time.get_ticks_msec() - _shot_t0 > 3000:
		prefetch_shot()
	if _shot_t0 < 0:
		return null
	var t0 := _shot_t0
	var done: bool = await _await_shot(t0, max_ms)
	_shot_t0 = -1
	var ms := Time.get_ticks_msec() - t0
	if not done:
		log_line("screenshot: not ready after %d ms, using the game's artwork until it is" % ms)
		_late_t0 = t0  # still coming: screenshot_late() picks it up
		return null
	var img := Image.load_from_file(_shot_src)
	DirAccess.remove_absolute(_shot_src)  # the running Spectacle's own copy too: nothing piles up in Pictures
	if img == null or img.is_empty():
		log_line("screenshot: could not read the picture")
		return null
	log_line("screenshot: ok %dx%d in %d ms" % [img.get_width(), img.get_height(), ms])
	return img

var _late_t0 := -1

## The picture that was too slow for screenshot(): waits a little longer for it (null if it never comes).
func screenshot_late(max_ms := 5000) -> Image:
	if _late_t0 < 0:
		return null
	var t0 := _late_t0
	_late_t0 = -1
	if not await _await_shot(t0, max_ms):
		return null
	var img := Image.load_from_file(_shot_src)
	DirAccess.remove_absolute(_shot_src)
	if img == null or img.is_empty():
		return null
	log_line("screenshot: arrived late, %dx%d after %d ms" % [img.get_width(), img.get_height(), Time.get_ticks_msec() - t0])
	return img

## A full-quality photo of the game's window, as a PNG at its own resolution (for the Create
## button while a game is showing). Returns true when the file was written.
func capture_screen(path: String) -> bool:
	if not _spectacle_ok():
		return false
	var t0 := Time.get_ticks_msec()
	# The game's own window, at its own resolution, when it has the focus. When Tephra's (invisible) window has it
	# instead, an "active window" picture would be black, so the whole screen is taken.
	var mode := "-m" if DisplayServer.window_is_focused() else "-a"
	OS.create_process("spectacle", [mode, "-b", "-n", "-o", path])
	var ok: bool = await _await_file(path, t0, 8000)
	log_line("photo: %s in %d ms" % ["saved" if ok else "failed", Time.get_ticks_msec() - t0])
	return ok

# ---------- Finding and closing the game ----------
## Process ids of the game (Steam's launcher process for this app and everything below it).
func game_pids(id: String) -> PackedStringArray:
	var out := []
	OS.execute("ps", ["-eo", "pid=,ppid=,args="], out)
	var re := RegEx.new()
	re.compile("^\\s*(\\d+)\\s+(\\d+)\\s+(.*)$")
	var kids := {}
	var roots: Array = []
	var me := str(OS.get_process_id())
	for line in String(out[0] if not out.is_empty() else "").split("\n"):
		var m := re.search(line)
		if m == null:
			continue
		var pid := m.get_string(1)
		var ppid := m.get_string(2)
		var args := m.get_string(3)
		if pid == me:
			continue
		if not kids.has(ppid):
			kids[ppid] = []
		kids[ppid].append(pid)
		if args.contains("SteamLaunch AppId=" + id + " ") and not args.begins_with("ps "):
			roots.append(pid)
	var result := PackedStringArray()
	var queue := roots.duplicate()
	while not queue.is_empty():
		var p: String = queue.pop_front()
		if result.has(p):
			continue
		result.append(p)
		for c in kids.get(p, []):
			queue.append(c)
	return result

# ---------- Freezing the game while a menu is open ----------
# Instead of pressing Esc for the game's own pause menu, the game is frozen in place: every one of its
# processes gets SIGSTOP (it simply stops running, sound included) and SIGCONT when you go back, so it
# carries on from the exact frame it was on. Nothing in the game is told about it.
var _frozen := PackedStringArray()

func freeze_game(id: String, pattern := "") -> void:
	if not _frozen.is_empty():
		return
	_frozen = _quit_pids(id, pattern)  # pattern: programs Steam's launcher doesn't own (PCSX2 from Flatpak)
	if _frozen.is_empty():
		log_line("freeze: found no processes for %s" % id)
		return
	OS.execute("kill", PackedStringArray(["-STOP"]) + _frozen, [])
	log_line("froze %s (%d processes)" % [id, _frozen.size()])

## Mutes (or unmutes) the game's sound streams, found by the game's processes, through PipeWire's Pulse layer (pactl).
## Home over a paused game is silent; the game's own control center lets its sound through.
var _muted := PackedStringArray()   # sink inputs Tephra muted

func mute_game(id: String, on: bool, pattern := "") -> void:
	if not on:
		for si in _muted:
			OS.execute("pactl", ["set-sink-input-mute", si, "0"], [])
		_muted = PackedStringArray()
		return
	var pids := _quit_pids(id, pattern)
	if pids.is_empty():
		return
	var out := []
	if OS.execute("pactl", ["list", "sink-inputs"], out) != 0 or out.is_empty():
		return
	var cur := ""
	for line in String(out[0]).split("\n"):
		var l := line.strip_edges()
		if l.begins_with("Sink Input #"):
			cur = l.trim_prefix("Sink Input #")
		elif cur != "" and l.begins_with("application.process.id = "):
			var pid := l.trim_prefix("application.process.id = ").replace("\"", "")
			if pids.has(pid) and not _muted.has(cur):
				OS.execute("pactl", ["set-sink-input-mute", cur, "1"], [])
				_muted.append(cur)
	log_line("sound: muted %d game streams" % _muted.size())

func thaw_game() -> void:
	if _frozen.is_empty():
		return
	OS.execute("kill", PackedStringArray(["-CONT"]) + _frozen, [])
	log_line("unfroze %d processes" % _frozen.size())
	_frozen = PackedStringArray()

## Closes the game: the polite way first (the game's window is asked to close), then a normal
## stop signal, and only if it still hasn't gone after a good while, a hard stop.
## Closes a game without anyone waiting on it: asks its window to close, then stops it (TERM, then KILL) if it is
## still there a few seconds later. `pattern` also finds programs Steam's launcher doesn't own (PCSX2 in flatpak).
func quit_game(id: String, pattern := "") -> void:
	log_line("quit requested for %s" % id)
	thaw_game()  # a frozen game can't close itself
	close_game_window()
	var waited := 0.0
	while waited < 3.0 and not _quit_pids(id, pattern).is_empty():
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var left := _quit_pids(id, pattern)
	if left.is_empty():
		return
	log_line("quit: still running after 3 s, sending stop signal")
	OS.execute("kill", PackedStringArray(["-TERM"]) + left, [])
	waited = 0.0
	while waited < 5.0 and not _quit_pids(id, pattern).is_empty():
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	left = _quit_pids(id, pattern)
	if not left.is_empty():
		log_line("quit: hard stop")
		OS.execute("kill", PackedStringArray(["-KILL"]) + left, [])

func _quit_pids(id: String, pattern: String) -> PackedStringArray:
	var pids := game_pids(id)
	if pattern != "":
		var out := []
		OS.execute("pgrep", ["-f", pattern], out)
		var me := str(OS.get_process_id())
		for p in String(out[0] if not out.is_empty() else "").split("\n", false):
			if p.strip_edges() != me and not pids.has(p.strip_edges()):
				pids.append(p.strip_edges())
	return pids

# ---------- A small yes/no card ----------
func _build_confirm() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 98
	add_child(layer)
	_confirm_root = Control.new()
	_confirm_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_root.visible = false
	layer.add_child(_confirm_root)
	var dim := ColorRect.new()
	dim.color = Themes.dim(0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Themes.c("panel")
	sb.set_corner_radius_all(Themes.r(22))
	sb.border_color = Themes.ink(0.10)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 40
	panel.add_theme_stylebox_override("panel", sb)
	_confirm_root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -170
	panel.offset_bottom = 170
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 44
	col.offset_right = -44
	col.offset_top = 40
	col.offset_bottom = -30
	_confirm_title = _lbl("", 42, TEXT)
	_confirm_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_confirm_title)
	_confirm_body = _lbl("", 24, MUTED)
	_confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_confirm_body)
	_confirm_hints = HBoxContainer.new()
	_confirm_hints.alignment = BoxContainer.ALIGNMENT_END
	_confirm_hints.add_theme_constant_override("separation", 14)
	col.add_child(_confirm_hints)

func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Shows the card and waits for A (true) or B (false).
func ask(title: String, body: String, yes_text: String) -> bool:
	if _confirm_root == null:
		_build_confirm()
	_confirm_title.text = title
	_confirm_body.text = body
	for c in _confirm_hints.get_children():
		_confirm_hints.remove_child(c)
		c.queue_free()
	_confirm_hints.add_child(TephraGlyphs.glyph("accept", 44))
	_confirm_hints.add_child(_lbl(yes_text, 30, TEXT))
	var gap := Control.new()
	gap.custom_minimum_size.x = 34
	_confirm_hints.add_child(gap)
	_confirm_hints.add_child(TephraGlyphs.glyph("back", 44))
	_confirm_hints.add_child(_lbl("Cancel", 30, TEXT))
	_confirm_root.visible = true
	_confirm_root.modulate.a = 0.0
	Motion.fade_to(_confirm_root, 1.0, 0.15)
	confirm_open = true
	var yes: bool = await confirm_done
	return yes

## The game ended while the card was up: close it as "no".
func cancel_confirm() -> void:
	if confirm_open:
		_finish_confirm(false)

func _finish_confirm(yes: bool) -> void:
	confirm_open = false
	_confirm_root.visible = false
	confirm_done.emit(yes)

## Called by home.gd first, so the card gets A and B while it is open.
func handle_input(event: InputEvent) -> bool:
	if not confirm_open:
		return false
	if event is InputEventJoypadMotion:
		return true
	if event.is_action_pressed("ui_accept"):
		_finish_confirm(true)
	elif event.is_action_pressed("ui_cancel"):
		_finish_confirm(false)
	return true
