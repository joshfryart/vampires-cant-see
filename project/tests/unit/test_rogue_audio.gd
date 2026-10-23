extends TestCase
## Baked roguelike sounds (tools/bake-rogue-audio.mjs): every manifest id has a sane, non-silent, non-clipping WAV.
## Reads the PCM straight from the file so it does not depend on the editor import cache.

const MANIFEST := "res://data/rogue/sounds_rogue.json"
const REQUIRED := ["rg_drip_cave", "rg_drip_pool", "rg_drip_gutter", "rg_splash_step_a", "rg_bat_squeak", "rg_bat_flutter", "rg_rat_skitter", "rg_rat_squeak", "rg_hare_thump", "rg_owl_hoot", "rg_wolf_howl", "rg_cricket_loop", "rg_wind_loop", "rg_creek_loop", "rg_fountain_loop", "rg_hearth_crackle", "rg_crow_caw", "rg_sheep_bleat", "rg_hen_cluck", "rg_coffin_creak", "rg_soil_chime", "rg_upgrade_sting", "rg_stage_arrival", "rg_dawn_bell", "rg_dawn_birds", "rg_laid_to_rest"]


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return {}
	return JSON.parse_string(f.get_as_text())


func test_manifest_and_files() -> void:
	var m := _manifest()
	ok(not m.is_empty(), "manifest loads")
	var ids := {}
	var total := 0
	for s in m.get("sounds", []):
		var id: String = s["id"]
		ok(id.begins_with("rg_"), "prefix " + id)
		ok(not ids.has(id), "unique " + id)
		ids[id] = true
		ok(float(s["gain"]) > 0.0 and float(s["gain"]) <= 1.0, "gain " + id)
		var bytes := FileAccess.get_file_as_bytes(str(m["dir"]) + str(s["file"]))
		total += bytes.size()
		ok(bytes.size() > 44, "file present " + id)
		if bytes.size() <= 44:
			continue
		eq(bytes.slice(0, 4).get_string_from_ascii(), "RIFF", "riff " + id)
		eq(bytes.decode_u16(22), 1, "mono " + id)
		eq(bytes.decode_u32(24), int(m["rate"]), "rate " + id)
		eq(bytes.decode_u16(34), 16, "16 bit " + id)
		var n := (bytes.size() - 44) / 2
		var secs := float(n) / float(m["rate"])
		ok(secs >= 0.1 and secs <= 8.0, "length %s %.2f" % [id, secs])
		eq(int(round(secs * 1000.0)), int(s["ms"]), "ms matches " + id)
		var peak := 0
		var sq := 0.0
		for i in n:
			var v := bytes.decode_s16(44 + i * 2)
			peak = maxi(peak, absi(v))
			sq += float(v) * float(v)
		var pk := float(peak) / 32768.0
		var rms := sqrt(sq / float(n)) / 32768.0
		ok(pk > 0.5, "not quiet %s peak %.3f" % [id, pk])
		ok(pk <= 0.95, "not clipping %s peak %.3f" % [id, pk])
		ok(rms > 0.003, "not silent %s rms %.4f" % [id, rms])
		if bool(s["loop"]):
			# seamless loop: the jump from the last sample to the first must be small
			var edge := absf(float(bytes.decode_s16(44)) - float(bytes.decode_s16(44 + (n - 1) * 2))) / 32768.0
			ok(edge < 0.35, "loop seam %s %.3f" % [id, edge])
	for id in REQUIRED:
		ok(ids.has(id), "manifest has " + id)
	ok(total < 5 * 1024 * 1024, "total size under 5 MB (%d)" % total)
