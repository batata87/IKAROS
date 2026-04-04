extends Node
## Autoload singleton: run state, score, multiplier, combo, high score.
## Offline-first — no network calls.

enum GameState {
	IDLE,
	ORBITING,
	DASHING,
	GAMEOVER,
}

signal state_changed(new_state: GameState)
signal score_changed(new_score: int)
signal multiplier_changed(value: float)
signal combo_changed(count: int)

const COMBO_ORBIT_MAX_SEC: float = 0.5
const MAX_MULTIPLIER_STACK: int = 10
const MULT_PER_COMBO: float = 0.2

var state: GameState = GameState.IDLE
var score: int = 0
var high_score: int = 0
var multiplier: float = 1.0
var combo_count: int = 0

var _orbit_time_sec: float = 0.0


func _ready() -> void:
	load_high_score()


func _process(delta: float) -> void:
	if state == GameState.ORBITING:
		_orbit_time_sec += delta


func set_game_state(next: GameState) -> void:
	if state == next:
		return
	state = next
	state_changed.emit(next)
	match next:
		GameState.ORBITING:
			_orbit_time_sec = 0.0
		GameState.GAMEOVER:
			_save_high_score_if_needed()


func reset_run() -> void:
	score = 0
	multiplier = 1.0
	combo_count = 0
	_orbit_time_sec = 0.0
	score_changed.emit(score)
	multiplier_changed.emit(multiplier)
	combo_changed.emit(combo_count)
	set_game_state(GameState.IDLE)


func on_dash_started(time_in_orbit_sec: float) -> void:
	## Call when player releases from an orbit. Used for combo rules (quick hops ≤ 0.5s).
	if time_in_orbit_sec <= COMBO_ORBIT_MAX_SEC:
		combo_count = mini(combo_count + 1, MAX_MULTIPLIER_STACK)
	else:
		combo_count = 0
	multiplier = 1.0 + combo_count * MULT_PER_COMBO
	multiplier_changed.emit(multiplier)
	combo_changed.emit(combo_count)


func on_anchor_captured(points: int = 1) -> void:
	score += int(round(points * multiplier))
	score_changed.emit(score)
	if score > high_score:
		high_score = score
		_save_high_score_if_needed()


func trigger_fail() -> void:
	trigger_haptic(80)
	set_game_state(GameState.GAMEOVER)


func trigger_capture_haptic() -> void:
	trigger_haptic(35)


func trigger_haptic(duration_ms: int) -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		Input.vibrate_handheld(duration_ms)


func get_time_in_current_orbit() -> float:
	return _orbit_time_sec


func _save_high_score_if_needed() -> void:
	var path := "user://neon_pivot_save.cfg"
	var cf := ConfigFile.new()
	var err := cf.load(path)
	if err != OK:
		pass
	cf.set_value("game", "high_score", high_score)
	cf.save(path)


func load_high_score() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://neon_pivot_save.cfg") != OK:
		return
	high_score = int(cf.get_value("game", "high_score", 0))
