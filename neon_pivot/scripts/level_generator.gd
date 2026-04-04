class_name NeonLevelGenerator
extends Node2D
## Procedural anchors: adaptive distance + angle ahead of the player.

const ANCHOR_SCENE := preload("res://scenes/Anchor.tscn")

@export var spawn_ahead_min: float = 380.0
@export var spawn_ahead_max: float = 620.0
@export var cull_behind_distance: float = 1100.0
@export var max_anchors_alive: int = 12

var _player: Node2D
var _last_spawn_anchor_pos: Vector2 = Vector2.ZERO
var _forward_hint: Vector2 = Vector2.RIGHT
var _spawn_cooldown_sec: float = 0.0


func setup(player: Node2D) -> void:
	_player = player
	_last_spawn_anchor_pos = Vector2.ZERO
	_forward_hint = Vector2.RIGHT
	var first: NeonAnchor = spawn_anchor_at(Vector2.ZERO)
	_last_spawn_anchor_pos = first.global_position
	# Second anchor ahead so there is always a target after first dash
	_queue_spawn_ahead()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_spawn_cooldown_sec = maxf(_spawn_cooldown_sec - delta, 0.0)
	if _spawn_cooldown_sec <= 0.0:
		_try_spawn_ahead()
	_cull_distant()


func spawn_anchor_at(global_pos: Vector2) -> NeonAnchor:
	var a: NeonAnchor = ANCHOR_SCENE.instantiate()
	a.global_position = global_pos
	a.apply_difficulty(GameManager.score)
	add_child(a)
	return a


func _queue_spawn_ahead() -> void:
	if _player == null:
		return
	var score: int = GameManager.score
	var d: float = randf_range(spawn_ahead_min, spawn_ahead_max) + score * 0.35
	var theta: float = deg_to_rad(randf_range(-38.0, 38.0))
	var dir: Vector2 = _forward_hint.rotated(theta).normalized()
	var target: Vector2 = _last_spawn_anchor_pos + dir * d
	spawn_anchor_at(target)
	_last_spawn_anchor_pos = target


func _try_spawn_ahead() -> void:
	var anchors := get_tree().get_nodes_in_group("anchors")
	if anchors.size() >= max_anchors_alive:
		return
	var furthest := 0.0
	for n in anchors:
		if n is Node2D:
			furthest = maxf(furthest, n.global_position.distance_to(_player.global_position))
	if furthest < spawn_ahead_min * 0.85:
		_queue_spawn_ahead()
		_spawn_cooldown_sec = 0.5


func _cull_distant() -> void:
	for child in get_children():
		if child is NeonAnchor:
			if child.global_position.distance_to(_player.global_position) > cull_behind_distance:
				child.queue_free()


func update_forward_hint(from: Vector2, to: Vector2) -> void:
	var v := to - from
	if v.length_squared() > 0.0001:
		_forward_hint = v.normalized()
