class_name AudioDirector
extends Node
## Audio entry points the game calls (js VCS.Audio). Slice step 1: the calls are recorded in `log` (used by tests and
## the scenario runner) and nothing is played yet; the baked-sample players, echo queue and reverb buses replace the
## bodies in the audio step without changing the signatures.

const MAX_LOG := 512

## Each entry: {t: float, kind: String, opts: Dictionary}. Oldest entries are dropped past MAX_LOG.
var log: Array = []


func _record(kind: String, opts: Dictionary) -> void:
	log.append({"kind": kind, "opts": opts})
	if log.size() > MAX_LOG:
		log.pop_front()


## js Audio.play(kind, opts).
func play(kind: String, opts: Dictionary = {}) -> void:
	_record(kind, opts)


## The click ping and its echoes for pulse `lp` heard from `player` in `world` (js pulse() audio section).
func ping(lp: Sonar.Pulse, _player: Player, _world: World, _game: Node) -> void:
	_record("ping", {"gen": lp.gen if lp != null else 0})


## Audible echo of a person snapshot (js personEcho): only the player's own ping returns as an echo.
func person_echo(e: People.Echo, sonar: Sonar) -> void:
	if e.kind != "" and e.kind != "ping":
		return
	var amp: float = clampf(Acoustics.person_amp(e.dist, e.theta), 0.1, 0.7)
	_record("echo", {"delay": clampf(e.dist / sonar.speed, 0.0, 6.0), "amp": amp, "pan": e.pan, "voice": "person"})
