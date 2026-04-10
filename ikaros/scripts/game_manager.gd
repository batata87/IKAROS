extends Node
## Autoload singleton: run state, score, multiplier, combo, high score.
## Offline-first — no network calls.

enum GameState {
	IDLE,
	ORBITING,
	DASHING,
	FALLING,
	GAMEOVER,
}

signal state_changed(new_state: GameState)
signal score_changed(new_score: int)
signal multiplier_changed(value: float)
signal combo_changed(count: int)

const COMBO_ORBIT_MAX_SEC: float = 0.5
const MAX_MULTIPLIER_STACK: int = 10
const MULT_PER_COMBO: float = 0.2
const REVIEW_SCORE_THRESHOLD: int = 50
const SAVE_PATH := "user://ikaros_save.cfg"
const SAVE_SEC := "game"

var state: GameState = GameState.IDLE
var score: int = 0
var high_score: int = 0
var multiplier: float = 1.0
var combo_count: int = 0

var _orbit_time_sec: float = 0.0
## Lifetime: after first run reaching REVIEW_SCORE_THRESHOLD, OS store review was requested once.
var store_review_prompted: bool = false


func _ready() -> void:
	load_high_score()
	_apply_mobile_fps_target()


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
	_maybe_request_store_review_first_time()


func trigger_fail() -> void:
	trigger_haptic(80, 0.85)
	set_game_state(GameState.GAMEOVER)


func trigger_capture_haptic() -> void:
	## Short pulse every anchor catch — Taptic on iOS; amplitude on Android.
	trigger_haptic(28, 0.62)


func trigger_haptic(duration_ms: int, amplitude: float = -1.0) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return
	# iOS may log haptic engine errors on unsupported hardware/runtime states.
	# Keep gameplay clean by only using vibrate_handheld on Android.
	if OS.has_feature("ios"):
		return
	if OS.has_feature("android") and amplitude >= 0.0:
		Input.vibrate_handheld(duration_ms, clampf(amplitude, 0.0, 1.0))
	else:
		Input.vibrate_handheld(duration_ms)


func get_time_in_current_orbit() -> float:
	return _orbit_time_sec


func _apply_mobile_fps_target() -> void:
	if not OS.has_feature("mobile"):
		Engine.max_fps = 0
		return
	var hz: float = DisplayServer.screen_get_refresh_rate()
	if hz <= 0.0:
		Engine.max_fps = 60
	elif hz >= 119.0:
		Engine.max_fps = 120
	else:
		Engine.max_fps = 60


func _maybe_request_store_review_first_time() -> void:
	if store_review_prompted:
		return
	if score < REVIEW_SCORE_THRESHOLD:
		return
	store_review_prompted = true
	_save_review_flag()
	if OS.has_feature("ios") or OS.has_feature("android"):
		call_deferred("_deferred_request_store_review")


func _deferred_request_store_review() -> void:
	if not (OS.has_feature("ios") or OS.has_feature("android")):
		return
	if OS.has_method("request_review"):
		OS.call("request_review")


func _save_review_flag() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value(SAVE_SEC, "store_review_prompted_v1", store_review_prompted)
	cf.save(SAVE_PATH)


func _save_high_score_if_needed() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(SAVE_PATH)
	if err != OK:
		pass
	cf.set_value(SAVE_SEC, "high_score", high_score)
	cf.save(SAVE_PATH)


func load_high_score() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	high_score = int(cf.get_value(SAVE_SEC, "high_score", 0))
	store_review_prompted = bool(cf.get_value(SAVE_SEC, "store_review_prompted_v1", false))
