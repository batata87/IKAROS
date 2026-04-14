class_name NeonLevelGenerator
extends Node2D

const ANCHOR_SCENE := preload("res://scenes/Anchor.tscn")
const LUX_SCENE := preload("res://scenes/LuxPickup.tscn")
const MAX_OBJECTS := 10

@export var min_anchors_ahead: int = 5
@export var vertical_step: float = 290.0
@export var lane_span: float = 180.0
@export var lux_spawn_chance: float = 0.45

var _player: Node2D = null
var _last_spawn_y: float = 0.0
var _next_side: int = 1
var _spawn_count: int = 0
var _delete_count: int = 0
var _spawn_order: Array[Node2D] = []


func setup(player) -> void:
	hard_reset_layout(player)


func hard_reset_layout(player) -> void:
	_player = player
	for c in get_children():
		c.queue_free()
	_spawn_order.clear()
	_spawn_count = 0
	_delete_count = 0
	var vp_size := get_viewport().get_visible_rect().size
	var center_x := vp_size.x * 0.5
	var safe_start := [
		Vector2(center_x, 0.0),
		Vector2(center_x + 170.0, -280.0),
		Vector2(center_x - 170.0, -560.0),
	]
	for pos in safe_start:
		_spawn_anchor(pos)
	_last_spawn_y = safe_start[safe_start.size() - 1].y
	_next_side = 1
	while _count_anchors_ahead() < min_anchors_ahead:
		_spawn_next()


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	while _count_anchors_ahead() < min_anchors_ahead:
		_spawn_next()
	_enforce_object_cap()


func update_forward_hint(_from: Vector2, _to: Vector2) -> void:
	pass


func get_debug_snapshot() -> Dictionary:
	return {
		"ahead": _count_anchors_ahead(),
		"spawned": _spawn_count,
		"deleted": _delete_count,
		"last_y": _last_spawn_y,
		"next_side": "R" if _next_side > 0 else "L",
	}


func _spawn_next() -> void:
	var y := _last_spawn_y - vertical_step
	var x := float(_next_side) * lane_span + randf_range(-36.0, 36.0)
	var a := _spawn_anchor(Vector2(x, y))
	_last_spawn_y = a.global_position.y
	_next_side *= -1
	if randf() <= lux_spawn_chance:
		_spawn_lux_between(a.global_position + Vector2(0.0, vertical_step), a.global_position)


func _spawn_anchor(pos: Vector2) -> NeonAnchor:
	var a := ANCHOR_SCENE.instantiate() as NeonAnchor
	a.global_position = pos
	a.apply_difficulty(GameManager.score)
	add_child(a)
	_track_spawn(a)
	return a


func _spawn_lux_between(from: Vector2, to: Vector2) -> void:
	var lux := LUX_SCENE.instantiate() as LuxPickup
	lux.global_position = from.lerp(to, 0.5) + Vector2(randf_range(-36.0, 36.0), randf_range(-20.0, 20.0))
	add_child(lux)
	_track_spawn(lux)


func _count_anchors_ahead() -> int:
	var count := 0
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as Node2D
		if a != null and is_instance_valid(a) and a.global_position.y < _player.global_position.y:
			count += 1
	return count


func _track_spawn(n: Node2D) -> void:
	_spawn_count += 1
	_spawn_order.append(n)
	_enforce_object_cap()


func _enforce_object_cap() -> void:
	# 10-Object Rule: anchors + lux combined never exceed 10.
	var alive: Array[Node2D] = []
	for n in _spawn_order:
		if n != null and is_instance_valid(n):
			alive.append(n)
	_spawn_order = alive
	while _spawn_order.size() > MAX_OBJECTS:
		var oldest: Node2D = _spawn_order.pop_front() as Node2D
		if oldest != null and is_instance_valid(oldest):
			oldest.queue_free()
			_delete_count += 1
