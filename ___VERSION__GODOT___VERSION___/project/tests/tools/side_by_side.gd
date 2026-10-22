extends SceneTree
## Compose Godot shots and JS reference shots into side-by-side PNGs (Godot left, JS right, both 640x360).
## Usage: godot --headless --path project -s res://tests/tools/side_by_side.gd -- <outDir> <godotPng:jsPng> [<godotPng:jsPng> ...]
## Paths are absolute. Output file names: sbs_<index>.png


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- <outDir> <godotPng:jsPng> ...")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	for i in range(1, args.size()):
		var pair := String(args[i]).rsplit("|", true, 1)
		if pair.size() != 2:
			print("bad pair: ", args[i])
			continue
		var a := Image.load_from_file(pair[0])
		var b := Image.load_from_file(pair[1])
		if a == null or b == null:
			print("cannot load: ", args[i])
			continue
		a.convert(Image.FORMAT_RGBA8)
		b.convert(Image.FORMAT_RGBA8)
		a.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		b.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		var o := Image.create(1290, 360, false, Image.FORMAT_RGBA8)
		o.fill(Color(0.2, 0.2, 0.25, 1.0))
		o.blit_rect(a, Rect2i(0, 0, 640, 360), Vector2i(0, 0))
		o.blit_rect(b, Rect2i(0, 0, 640, 360), Vector2i(650, 0))
		var path := "%s/sbs_%d.png" % [out_dir, i]
		o.save_png(path)
		print("wrote ", path)
	quit(0)
