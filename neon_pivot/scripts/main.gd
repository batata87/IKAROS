extends Node2D
## Bootstraps LevelGenerator + Player and wires minimalist HUD to GameManager.

@onready var level_gen: NeonLevelGenerator = $LevelGenerator
@onready var player: CharacterBody2D = $Player
@onready var lbl_hi: Label = $CanvasLayer/HUD/HighScore
@onready var lbl_mul: Label = $CanvasLayer/HUD/Multiplier


func _ready() -> void:
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.multiplier_changed.connect(_on_multiplier_changed)
	level_gen.setup(player)
	player.initialize_after_level()
	_refresh_hud()


func _on_score_changed(_new_score: int) -> void:
	_refresh_hud()


func _on_multiplier_changed(_v: float) -> void:
	lbl_mul.text = "x%.1f" % GameManager.multiplier


func _refresh_hud() -> void:
	lbl_hi.text = "HI: %d" % GameManager.high_score
	lbl_mul.text = "x%.1f" % GameManager.multiplier
