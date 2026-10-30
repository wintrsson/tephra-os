extends Node
## Test-only autoload that tools/ui-test.sh adds to a temporary copy of the project (never part of the real one):
## runs a timeline from the file in $SHOT_PLAN inside the real Tephra and writes screenshots to $SHOT_DIR.
## The plan is JSON, a list of [seconds, action, ...]:
##   [12, "shot", "name"]                    save $SHOT_DIR/name.png
##   [13, "key", 4194309]                    press and release a key (Enter 4194309, Esc 4194305, E 69,
##                                           Up 4194320, Down 4194322, Left 4194319, Right 4194321)
##   [14, "call", "setup_screen", "open", 0, true]   call a method on one of home.gd's members
##   [15, "dump", "name", "phone", "base_url"]   write what home.gd's member (or "" for Home itself).method() returns to
##                                           $SHOT_DIR/name.txt (extra values after the method are its arguments)
##   [20, "quit"]
var t := 0.0
var i := 0
var plan: Array = []
var out := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	out = OS.get_environment("SHOT_DIR")
	plan = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SHOT_PLAN")))

func _key(code: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)

func _process(d: float) -> void:
	t += d
	while i < plan.size() and t >= float(plan[i][0]):
		var a: Array = plan[i]
		i += 1
		match str(a[1]):
			"shot":
				get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, str(a[2])])
			"key":
				_key(int(a[2]))
			"call":
				var target = get_tree().current_scene.get(str(a[2]))
				if target != null:
					target.callv(str(a[3]), a.slice(4))
			"dump":
				var scene := get_tree().current_scene
				var holder = scene if str(a[3]) == "" else scene.get(str(a[3]))
				var f := FileAccess.open("%s/%s.txt" % [out, str(a[2])], FileAccess.WRITE)
				if f != null and holder != null:
					f.store_string(str(holder.callv(str(a[4]), a.slice(5))))
					f.close()
			"quit":
				get_tree().quit()
