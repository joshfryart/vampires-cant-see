class_name TestCase
extends RefCounted
## Base class for tests. Methods named test_* are run by run_tests.gd.

## Set by run_tests.gd so tests can build nodes (the Game) in the tree.
static var tree: SceneTree = null

var failures: Array[String] = []
var checks: int = 0


func ok(cond: bool, msg: String = "") -> void:
	checks += 1
	if not cond:
		failures.append(msg if msg != "" else "assertion failed")


func eq(a: Variant, b: Variant, msg: String = "") -> void:
	checks += 1
	if a != b:
		failures.append("%s: %s != %s" % [msg, str(a), str(b)])


func near(a: float, b: float, eps: float = 1e-9, msg: String = "") -> void:
	checks += 1
	if not (absf(a - b) <= eps):
		failures.append("%s: %s vs %s (eps %s)" % [msg, str(a), str(b), str(eps)])


func load_fixture(name: String) -> Variant:
	var f := FileAccess.open("res://tests/fixtures/%s.json" % name, FileAccess.READ)
	if f == null:
		failures.append("missing fixture %s" % name)
		return null
	return JSON.parse_string(f.get_as_text())
