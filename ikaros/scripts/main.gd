extends Node2D
## Bootstraps menu, LevelGenerator + Player, HUD, and The Vault.

@onready var level_gen: Node2D = $LevelGenerator
@onready var player: CharacterBody2D = $Player
@onready var lbl_hi: Label = $CanvasLayer/HUD/HighScore
@onready var lbl_mul: Label = $CanvasLayer/HUD/Multiplier
@onready var lbl_lux: Label = $CanvasLayer/HUD/LuxBalance
@onready var lbl_build: Label = $CanvasLayer/HUD/BuildInfo
@onready var main_menu: Control = $CanvasLayer/MainMenu
@onready var store_screen = $CanvasLayer/StoreScreen
@onready var btn_vault: Button = $CanvasLayer/MainMenu/Center/VBox/BtnVault
@onready var btn_feedback: Button = $CanvasLayer/MainMenu/BtnFeedback
var _run_started: bool = false


func _ready() -> void:
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.multiplier_changed.connect(_on_multiplier_changed)
	CurrencyManager.lux_changed.connect(_on_lux_changed)
	store_screen.vault_closed.connect(_on_vault_closed)

	main_menu.get_node("Center/VBox/BtnPlay").pressed.connect(_on_play_pressed)
	main_menu.get_node("Center/VBox/BtnVault").pressed.connect(_on_vault_pressed)

	level_gen.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_DISABLED

	main_menu.visible = true

	_refresh_hud()
	_on_lux_changed(CurrencyManager.lux)
	_load_build_label()


func _input(event: InputEvent) -> void:
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
		get_viewport().set_input_as_handled()


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


func _on_lux_changed(balance: int) -> void:
	lbl_lux.text = "LUX: %d" % balance


func _on_score_changed(_new_score: int) -> void:
	_refresh_hud()


func _on_multiplier_changed(_v: float) -> void:
	lbl_mul.text = "x%.1f" % GameManager.multiplier


func _refresh_hud() -> void:
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
