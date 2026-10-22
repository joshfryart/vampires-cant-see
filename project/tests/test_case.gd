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


## Deep comparison: same dictionary key sets, same array sizes, numbers within eps, everything else equal (key order is irrelevant).
func deep(got: Variant, want: Variant, lbl: String, eps: float = 1e-9) -> void:
	checks += 1
	if want is Dictionary:
		if not (got is Dictionary):
			failures.append("%s: want dict, got %s" % [lbl, str(got).left(120)])
			return
		var wk: Array = want.keys()
		var gk: Array = got.keys()
		wk.sort()
		gk.sort()
		if wk != gk:
			failures.append("%s: keys got %s want %s" % [lbl, str(gk).left(200), str(wk).left(200)])
			return
		for k in want:
			deep(got[k], want[k], lbl + "." + str(k), eps)
	elif want is Array:
		if not (got is Array or got is PackedFloat64Array or got is PackedFloat32Array) or got.size() != want.size():
			failures.append("%s: array size got %s want %d" % [lbl, str(got).left(160), want.size()])
			return
		for i in want.size():
			deep(got[i], want[i], "%s[%d]" % [lbl, i], eps)
	elif (want is float or want is int) and (got is float or got is int):
		if absf(float(got) - float(want)) > eps:
			failures.append("%s: got %s want %s" % [lbl, str(got), str(want)])
	elif want == null:
		if got != null:
			failures.append("%s: want null, got %s" % [lbl, str(got).left(120)])
	elif got != want:
		failures.append("%s: got %s want %s" % [lbl, str(got).left(120), str(want).left(120)])
