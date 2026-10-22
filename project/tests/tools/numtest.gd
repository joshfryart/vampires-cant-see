extends SceneTree
func _init() -> void:
	var f := FileAccess.open("res://../out/numtest/nums.json", FileAccess.READ)
	var arr: Array = JSON.parse_string(f.get_as_text())
	var bad_str := 0
	var bad_json := 0
	var ex: Array = []
	for p in arr:
		var v: float = p[0]
		var want: String = p[1]
		if str(v) != want:
			bad_str += 1
			if ex.size() < 6: ex.append([want, str(v), JSON.stringify(v)])
		if JSON.stringify(v) != want:
			bad_json += 1
	print("NUMTEST total=", arr.size(), " bad_str=", bad_str, " bad_json=", bad_json, " ex=", ex)
	quit()
