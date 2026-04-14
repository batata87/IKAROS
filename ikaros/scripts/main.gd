extends Node2D
## Bootstraps menu, LevelGenerator + Player, HUD, and The Vault.
static var _auto_start_after_reload: bool = false

@onready var level_gen: Node2D = $LevelGenerator
@onready var player: CharacterBody2D = $Player
@onready var lbl_hi: Label = $CanvasLayer/HUD/HighScore
@onready var lbl_mul: Label = $CanvasLayer/HUD/Multiplier
@onready var lbl_lux: Label = $CanvasLayer/HUD/LuxBalance
@onready var lbl_score: Label = $CanvasLayer/HUD/Score
@onready var lbl_build: Label = $CanvasLayer/HUD/BuildInfo
@onready var main_menu: Control = $CanvasLayer/MainMenu
@onready var store_screen = $CanvasLayer/StoreScreen
@onready var btn_vault: Button = $CanvasLayer/MainMenu/Center/VBox/BtnVault
@onready var btn_feedback: Button = $CanvasLayer/MainMenu/BtnFeedback
@onready var game_over_modal: Control = $CanvasLayer/GameOverModal
@onready var game_over_score: Label = $CanvasLayer/GameOverModal/Center/Panel/Margin/VBox/ScoreLabel
@onready var btn_try_again: Button = $CanvasLayer/GameOverModal/Center/Panel/Margin/VBox/BtnTryAgain
@onready var btn_return_home: Button = $CanvasLayer/GameOverModal/Center/Panel/Margin/VBox/BtnReturnHome
@onready var chromatic_overlay: CanvasItem = $ScreenJuiceLayer/ChromaticOverlay
@onready var world_env: WorldEnvironment = $WorldEnvironment
var _run_started: bool = false
var _debug_label: Label = null
var _debug_overlay_enabled: bool = true


func _ready() -> void:
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.multiplier_changed.connect(_on_multiplier_changed)
	GameManager.state_changed.connect(_on_game_state_changed)
	ItemDatabase.world_theme_changed.connect(_on_world_theme_changed)
	CurrencyManager.lux_changed.connect(_on_lux_changed)
	store_screen.vault_closed.connect(_on_vault_closed)

	main_menu.get_node("Center/VBox/BtnPlay").pressed.connect(_on_play_pressed)
	main_menu.get_node("Center/VBox/BtnVault").pressed.connect(_on_vault_pressed)
	btn_try_again.pressed.connect(_on_try_again_pressed)
	btn_return_home.pressed.connect(_on_return_home_pressed)

	level_gen.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_DISABLED

	main_menu.visible = true
	main_menu.process_mode = Node.PROCESS_MODE_INHERIT
	game_over_modal.visible = false
	game_over_modal.process_mode = Node.PROCESS_MODE_DISABLED

	_refresh_hud()
	_on_lux_changed(CurrencyManager.lux)
	_load_build_label()
	if lbl_build:
		lbl_build.visible = false
	if chromatic_overlay != null:
		chromatic_overlay.visible = false
		chromatic_overlay.process_mode = Node.PROCESS_MODE_DISABLED
	_on_world_theme_changed(ItemDatabase.peek_world_theme())
	_ensure_debug_overlay()
	set_process(true)
	if _auto_start_after_reload:
		_auto_start_after_reload = false
		call_deferred("_start_run")


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_F3:
			_debug_overlay_enabled = not _debug_overlay_enabled
			if _debug_label:
				_debug_label.visible = _debug_overlay_enabled
			return
	if not main_menu.visible:
		return
	if _run_started:
		return
	if store_screen != null and store_screen.visible:
		return
	if event is InputEventScreenTouch:
		var p_touch: Vector2 = (event as InputEventScreenTouch).position
		if btn_vault and btn_vault.get_global_rect().has_point(p_touch):
			return
		if btn_feedback and btn_feedback.get_global_rect().has_point(p_touch):
			return
	elif event is InputEventMouseButton:
		var p_mouse: Vector2 = (event as InputEventMouseButton).position
		if btn_vault and btn_vault.get_global_rect().has_point(p_mouse):
			return
		if btn_feedback and btn_feedback.get_global_rect().has_point(p_mouse):
			return
	if _is_tap_event(event):
		_start_run()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


func _is_tap_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return false


func _start_run() -> void:
	if _run_started:
		return
	_run_started = true
	main_menu.visible = false
	main_menu.process_mode = Node.PROCESS_MODE_DISABLED
	game_over_modal.visible = false
	game_over_modal.process_mode = Node.PROCESS_MODE_DISABLED
	level_gen.process_mode = Node.PROCESS_MODE_INHERIT
	player.process_mode = Node.PROCESS_MODE_INHERIT
	level_gen.call("setup", player)
	player.initialize_after_level()
	_refresh_hud()


func _on_play_pressed() -> void:
	_start_run()


func _on_vault_pressed() -> void:
	store_screen.open_vault()
	main_menu.visible = false
	main_menu.process_mode = Node.PROCESS_MODE_DISABLED


func _on_vault_closed() -> void:
	main_menu.visible = true
	main_menu.process_mode = Node.PROCESS_MODE_INHERIT
	_run_started = false


func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	if new_state != GameManager.GameState.GAMEOVER:
		return
	if not _run_started:
		return
	_run_started = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	level_gen.process_mode = Node.PROCESS_MODE_DISABLED
	if game_over_score:
		game_over_score.text = "Score: %d   High Score: %d" % [GameManager.score, GameManager.high_score]
	game_over_modal.visible = true
	game_over_modal.process_mode = Node.PROCESS_MODE_INHERIT


func _on_try_again_pressed() -> void:
	_auto_start_after_reload = true
	get_tree().reload_current_scene()


func _on_return_home_pressed() -> void:
	_auto_start_after_reload = false
	get_tree().reload_current_scene()


func _on_lux_changed(balance: int) -> void:
	lbl_lux.text = "LUX: %d" % balance


func _on_world_theme_changed(theme: Dictionary) -> void:
	if world_env == null or world_env.environment == null:
		return
	world_env.environment.glow_intensity = float(theme.get("glow_intensity", world_env.environment.glow_intensity))
	world_env.environment.glow_strength = float(theme.get("glow_strength", world_env.environment.glow_strength))


func _on_score_changed(_new_score: int) -> void:
	_refresh_hud()


func _on_multiplier_changed(_v: float) -> void:
	lbl_mul.text = "x%.1f" % GameManager.multiplier


func _refresh_hud() -> void:
	lbl_score.text = "Score: %d" % GameManager.score
	lbl_hi.text = "HI: %d" % GameManager.high_score
	lbl_mul.text = "x%.1f" % GameManager.multiplier


func _load_build_label() -> void:
	if lbl_build == null:
		return
	var p := "res://build/build_info.txt"
	if not FileAccess.file_exists(p):
		lbl_build.text = "build: dev"
		return
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		lbl_build.text = "build: dev"
		return
	var txt := f.get_as_text().strip_edges()
	f.close()
	if txt == "":
		lbl_build.text = "build: dev"
	else:
		lbl_build.text = txt


func _process(_delta: float) -> void:
	_publish_web_qa_snapshot()
	if _debug_label == null:
		return
	_debug_label.visible = _debug_overlay_enabled and _run_started and not main_menu.visible
	if not _debug_label.visible:
		return
	var fps := Engine.get_frames_per_second()
	var p_snap: Dictionary = {}
	var l_snap: Dictionary = {}
	if player != null and player.has_method("get_debug_snapshot"):
		p_snap = player.call("get_debug_snapshot")
	if level_gen != null and level_gen.has_method("get_debug_snapshot"):
		l_snap = level_gen.call("get_debug_snapshot")
	_debug_label.text = "FPS:%d S:%s V:%.1f vy:%.1f N:%.1f\nL:%d C:%d F:%s | A:%d Sp:%d Del:%d Next:%s" % [
		fps,
		str(p_snap.get("state", "?")),
		float(p_snap.get("spd", 0.0)),
		float(p_snap.get("vy", 0.0)),
		float(p_snap.get("nearest", -1.0)),
		int(p_snap.get("launches", 0)),
		int(p_snap.get("captures", 0)),
		str(p_snap.get("fail", "")),
		int(l_snap.get("ahead", 0)),
		int(l_snap.get("spawned", 0)),
		int(l_snap.get("deleted", 0)),
		str(l_snap.get("next_side", "?")),
	]


func _ensure_debug_overlay() -> void:
	if _debug_label != null:
		return
	_debug_label = Label.new()
	_debug_label.name = "DebugOverlay"
	_debug_label.anchors_preset = Control.PRESET_TOP_LEFT
	_debug_label.offset_left = 16.0
	_debug_label.offset_top = 90.0
	_debug_label.offset_right = 640.0
	_debug_label.offset_bottom = 200.0
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.75, 0.96))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	_debug_label.text = ""
	$CanvasLayer/HUD.add_child(_debug_label)


func _publish_web_qa_snapshot() -> void:
	if not OS.has_feature("web"):
		return
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	var payload := {
		"runStarted": _run_started,
		"mainMenuVisible": main_menu.visible if main_menu != null else false,
		"gameOverVisible": game_over_modal.visible if game_over_modal != null else false,
		"score": GameManager.score,
		"state": int(GameManager.state),
	}
	if player != null and player.has_method("get_debug_snapshot"):
		payload["player"] = player.call("get_debug_snapshot")
	JavaScriptBridge.eval("window.__ikarosQaSnapshot = " + JSON.stringify(payload) + ";", true)
