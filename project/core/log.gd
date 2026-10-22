class_name Log
extends RefCounted
## Ports js/log.js: a ring buffer of the last lines (level, tag, message) for the error screen, the F9 panel and "Copy report".
## Everything also goes to the Godot output when verbose (or for warnings and errors).

const MAX_LINES := 400
const LEVELS := ["debug", "info", "warn", "error"]

static var lines: Array = []
static var verbose: bool = false
static var start_ms: int = Time.get_ticks_msec()


static func add(level: String, tag: String, msg: String) -> void:
	lines.append({"t": (Time.get_ticks_msec() - start_ms) / 1000.0, "level": level, "tag": tag, "msg": msg})
	if lines.size() > MAX_LINES:
		lines.pop_front()
	if verbose or level == "warn" or level == "error":
		var text := "[%s] %s: %s" % [level, tag, msg]
		if level == "error" or level == "warn":
			printerr(text)
		else:
			print(text)


static func debug(tag: String, msg: String) -> void:
	add("debug", tag, msg)


static func info(tag: String, msg: String) -> void:
	add("info", tag, msg)


static func warn(tag: String, msg: String) -> void:
	add("warn", tag, msg)


static func error(tag: String, msg: String) -> void:
	add("error", tag, msg)


## The whole buffer as text, with an engine and platform header, for pasting into a bug report.
static func report(extra: String = "") -> String:
	var out := PackedStringArray()
	out.append("Vampires Can't See (Godot port)")
	out.append("Godot %s, %s, %s" % [Engine.get_version_info()["string"], OS.get_name(), RenderingServer.get_video_adapter_name()])
	if extra != "":
		out.append(extra)
	out.append("")
	for l in lines:
		out.append("%8.2f %-5s %-10s %s" % [l["t"], l["level"], l["tag"], l["msg"]])
	return "\n".join(out)
