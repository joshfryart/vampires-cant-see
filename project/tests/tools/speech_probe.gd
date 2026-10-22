extends SceneTree
## Times SpeechSynth.render on a few lines and checks the PCM is finite and non-silent.


func _init() -> void:
	var dd := VoiceData.d()
	for case in [["chat", "calm", 5, null], ["argue", "argue", 9, null], ["struggle", "worried", 3, 0.8], ["hum", "calm", 2, null]]:
		var syls := VoiceData.line(case[2], case[0], case[1], case[3])
		var voice := VoiceData.for_person(case[2], "man")
		var params := {"syls": syls, "voice": voice, "mood": dd["MOODS"][case[1]], "weak": VoiceData.weak_of(case[3]), "vowels": dd["VOWELS"], "consonants": dd["CONSONANTS"], "seed": case[2]}
		var t0 := Time.get_ticks_usec()
		var r: Dictionary = SpeechSynth.render(params)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var peak := 0.0
		var bad := 0
		for v in r["pcm"]:
			if is_nan(v) or is_inf(v):
				bad += 1
			peak = maxf(peak, absf(v))
		print("SPEECH %s/%s: %.0f ms to synthesise %.2f s of audio, peak %.3f, bad samples %d" % [case[0], case[1], ms, float(r["total"]), peak, bad])
	quit()
