extends RefCounted
## Updating Tephra from inside Tephra. New versions are pushed to a branch of Tephra's GitHub repo; Tephra fetches that
## branch with the git login the installer already set up (never asking for a password: it fails quietly instead),
## reads the VERSION file there, and when it is newer than the one running offers to install it. Installing saves
## the current state in git first (so any update can be undone), takes the shell files from the branch, records them
## as a new version, pushes, and restarts Tephra. Runs git on a worker thread; results come back on the main thread.
## A new version that doesn't start is undone by the launcher (tephra-run.sh): installing leaves update-pending (the
## commit to go back to, and the version), Tephra deletes it after running fine for a few seconds (mark_healthy), and if
## the launcher still finds it after a crash or a hang, it puts the old files back and writes update-failed. That version
## is not offered again; the next one after it is.

const BRANCH := "claude/project-thread-kou0vz"   # the development copy; a public copy names its own in UPDATE_BRANCH
const SHELL := "shell/tephra-shell"

static var state := "idle"     # "idle", "checking", "ready" (a newer version is there), "current", "offline", "installing", "failed"
static var remote := ""        # the version on GitHub, once checked
static var checked_ms := -1

static func cfg_dir() -> String:
	return OS.get_environment("HOME").path_join(".config/tephra")

static func pending_path() -> String:
	return cfg_dir().path_join("update-pending")

static func failed_path() -> String:
	return cfg_dir().path_join("update-failed")

## The version the launcher had to go back from because it didn't start ("" if none).
static func failed_version() -> String:
	return FileAccess.get_file_as_string(failed_path()).get_slice("\n", 0).strip_edges()

## Called once Tephra has been running fine for a while after an update: the new version is kept.
static func mark_healthy() -> void:
	if FileAccess.file_exists(pending_path()):
		DirAccess.remove_absolute(pending_path())

## What to tell the player when the launcher went back to the old version (once), "" otherwise.
static func rollback_notice() -> String:
	var fv := failed_version()
	if fv == "":
		return ""
	if not newer(fv, local_version()):
		DirAccess.remove_absolute(failed_path())  # a version past it is running now
		return ""
	var lines := FileAccess.get_file_as_string(failed_path()).split("\n")
	if lines.size() < 2 or lines[1].strip_edges() != "new":
		return ""
	var f := FileAccess.open(failed_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(fv + "\nseen\n")
		f.close()
	return "Tephra %s didn't start, so Tephra went back to %s. It won't offer %s again." % [fv, local_version(), fv]

## The branch updates come from: the one-line UPDATE_BRANCH file next to VERSION if there is one (the public copy has
## "main"), else BRANCH.
static func branch() -> String:
	var b := FileAccess.get_file_as_string("res://UPDATE_BRANCH").strip_edges() if FileAccess.file_exists("res://UPDATE_BRANCH") else ""
	return b if b != "" else BRANCH

static func repo() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../..").simplify_path()

static func local_version() -> String:
	return FileAccess.get_file_as_string("res://VERSION").strip_edges()

## True if version a is newer than b ("0.44.1" > "0.44.0").
static func newer(a: String, b: String) -> bool:
	var x := a.split(".")
	var y := b.split(".")
	for i in maxi(x.size(), y.size()):
		var p := x[i].to_int() if i < x.size() else 0
		var q := y[i].to_int() if i < y.size() else 0
		if p != q:
			return p > q
	return false

static func _git(args: Array) -> Array:
	var out: Array = []
	# No password window ever (KDE Wallet / ksshaskpass): without a saved GitHub login git just fails quietly.
	var full: Array = ["-u", "SSH_ASKPASS", "GIT_TERMINAL_PROMPT=0", "GIT_ASKPASS=true", "git", "-C", repo()]
	full.append_array(args)
	var code := OS.execute("env", PackedStringArray(full), out, true)
	return [code, (str(out[0]) if not out.is_empty() else "").strip_edges()]

## Looks on GitHub for a newer version. `done` is called on the main thread with the new state.
static func check(home, done := Callable()) -> void:
	if state in ["checking", "installing"]:
		return
	var before := state
	state = "checking"
	var box := {}
	box["id"] = home._work(func() -> void:
		var r := _git(["fetch", "-q", "origin", branch()])
		var result := "offline"
		var ver := ""
		if int(r[0]) == 0:
			var v := _git(["show", "FETCH_HEAD:" + SHELL + "/VERSION"])
			ver = str(v[1]) if int(v[0]) == 0 else ""
			var fv := failed_version()
			result = "ready" if ver != "" and newer(ver, local_version()) and (fv == "" or newer(ver, fv)) else "current"
		(func() -> void:
			home._work_done(box["id"])
			if result == "offline" and before == "ready":
				result = "ready"  # a failed look must not take back an update that was already found (it is still fetched)
				ver = remote
			state = result
			remote = ver
			checked_ms = Time.get_ticks_msec()
			if done.is_valid():
				done.call(result)).call_deferred())

## Installs what was fetched, then restarts Tephra. `done` gets "failed" if it couldn't (nothing is changed then).
static func install(home, done := Callable()) -> void:
	if state == "installing":
		return
	state = "installing"
	var ver := remote
	home.fade_out(0.6)  # the screen fades to black while it installs; Tephra comes back faded in
	var box := {}
	box["id"] = home._work(func() -> void:
		var ok := int(_git(["fetch", "-q", "origin", branch()])[0]) == 0
		if ok:
			_git(["add", "-A"])
			_git(["commit", "-qm", "Snapshot before " + ("v" + ver if ver != "" else "update")])
			var before := _git(["rev-parse", "HEAD"])
			if int(before[0]) == 0 and str(before[1]) != "":
				DirAccess.make_dir_recursive_absolute(cfg_dir())
				var pf := FileAccess.open(pending_path(), FileAccess.WRITE)  # what the launcher goes back to if the new version won't start
				if pf != null:
					pf.store_string("%s\n%s\n" % [before[1], ver])
					pf.close()
			ok = int(_git(["checkout", "FETCH_HEAD", "--", SHELL, "tools/install-update.sh"])[0]) == 0
		if ok:
			_git(["add", "-A"])
			_git(["commit", "-qm", ("v%s: " % ver if ver != "" else "") + "updated from inside Tephra"])
			if ver != "" and int(_git(["rev-parse", "-q", "--verify", "refs/tags/v" + ver])[0]) != 0:
				_git(["tag", "-a", "v" + ver, "-m", "Updated from inside Tephra"])
			_git(["push", "-q", "--follow-tags", "origin", "HEAD"])  # fine if this fails: it goes up next time
		if not ok:
			mark_healthy()  # nothing was installed: nothing to go back from
		(func() -> void:
			home._work_done(box["id"])
			state = "idle" if ok else "failed"
			if not ok:
				home.fade_in(0.4)
			if done.is_valid():
				done.call("installed" if ok else "failed")
			if ok:
				home._code_stamp = home._code_modified()  # the file watcher must not restart it a second time
				home.restart_tephra()).call_deferred())
