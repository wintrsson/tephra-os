extends RefCounted
## Muting and unmuting the main volume with a short fade, so the sound doesn't snap off or on.
## The fade runs in a small shell script (a series of wpctl volume steps), so nothing waits on the screen.
## A new fade first stops the one still running.

const SINK := "@DEFAULT_AUDIO_SINK@"
const STEPS := 14
const SECONDS := 0.45

## volume: the level to come back to (0 to 1). mute: true fades out and mutes, false unmutes and fades in.
static func set_muted(volume: float, mute: bool) -> void:
	volume = clampf(volume, 0.0, 1.0)
	var lines := PackedStringArray()
	var gap := SECONDS / STEPS
	if mute:
		for i in range(1, STEPS + 1):
			var k := 1.0 - float(i) / STEPS
			lines.append("wpctl set-volume %s %.3f; sleep %.3f" % [SINK, volume * k * k, gap])  # squared: an even-sounding fade
		lines.append("wpctl set-mute %s 1" % SINK)
		lines.append("wpctl set-volume %s %.3f" % [SINK, volume])  # remembered for the next unmute (it is muted, so silent)
	else:
		lines.append("wpctl set-volume %s 0" % SINK)
		lines.append("wpctl set-mute %s 0" % SINK)
		for i in range(1, STEPS + 1):
			var k2 := float(i) / STEPS
			lines.append("wpctl set-volume %s %.3f; sleep %.3f" % [SINK, volume * k2 * k2, gap])
		lines.append("wpctl set-volume %s %.3f" % [SINK, volume])
	OS.execute("pkill", ["-f", "tephra_audio_fade"])
	OS.create_process("sh", ["-c", "\n".join(lines), "tephra_audio_fade"])
