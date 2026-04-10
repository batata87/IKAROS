class_name NeonLevelGenerator
extends Node2D
## Vertical Track generator: alternating sides + fixed vertical steps.

const ANCHOR_SCENE := preload("res://scenes/Anchor.tscn")
const LUX_SCENE := preload("res://scenes/LuxPickup.tscn")

@export var lux_spawn_chance: float = 0.42
@export var min_anchors_ahead: int = 3
@export var cull_behind_distance: float = 1000.0
@export var max_anchors_alive: int = 16
@export var vertical_step: float = 350.0

var _player = null
var _last_spawn_anchor_pos: Vector2 = Vector2.ZERO
var _next_on_right: bool = true


func setup(player) -> void:
	_player = player
	_last_spawn_anchor_pos = Vector2.ZERO
	var first = spawn_anchor_at(Vector2.ZERO)
	_last_spawn_anchor_pos = first.global_position
	_next_on_right = first.global_position.x <= _screen_mid_x_world()
	_ensure_track_ahead()


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_ensure_track_ahead()
	_cull_distant()


func spawn_anchor_at(global_pos: Vector2):
	var a = ANCHOR_SCENE.instantiate()
	a.global_position = global_pos
	if a.has_method("apply_difficulty"):
		a.call("apply_difficulty", GameManager.score)
	add_child(a)
	print("[spawn] circle at ", a.global_position)
	cleanup_old_circles()
	return a


func _spawn_next_track_anchor() -> void:
	if _player == null:
		return
	var from: Vector2 = _last_spawn_anchor_pos
	var target: Vector2 = Vector2(_lane_x(_next_on_right, from.x), _last_spawn_anchor_pos.y - vertical_step)
	spawn_anchor_at(target)
	_spawn_lux_midpoint(from, target)
	_last_spawn_anchor_pos = target
	_next_on_right = not _next_on_right


func _cull_distant() -> void:
	cleanup_old_circles()


func update_forward_hint(_from: Vector2, _to: Vector2) -> void:
	pass


func _ensure_track_ahead() -> void:
	if _player == null:
		return
	if _count_reachable_ahead() < min_anchors_ahead:
		_spawn_next_track_anchor()


func _count_reachable_ahead() -> int:
	var count := 0
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as Node2D
		if a != null and a.global_position.y < _player.global_position.y - 2.0:
			count += 1
	return count


func _spawn_lux_midpoint(from: Vector2, to: Vector2) -> void:
	if randf() > lux_spawn_chance:
		return
	var dir: Vector2 = to - from
	if dir.length_squared() < 0.001:
		return
	var perp: Vector2 = Vector2(-dir.y, dir.x).normalized()
	var pos: Vector2 = (from + to) * 0.5 + perp * randf_range(-50.0, 50.0)
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as Node2D
		if a == null:
			continue
		var capture_r: float = 64.0
		var maybe_capture = a.get("capture_radius")
		if maybe_capture != null:
			capture_r = float(maybe_capture)
		if pos.distance_to(a.global_position) < capture_r + 50.0:
			var away_dir: Vector2 = (pos - a.global_position).normalized()
			if away_dir.length_squared() < 0.001:
				away_dir = perp
			pos = a.global_position + away_dir * (capture_r + 56.0)
	var lux = LUX_SCENE.instantiate()
	lux.global_position = pos
	add_child(lux)


func cleanup_old_circles() -> void:
	if _player == null:
		return
	for child in get_children():
		var c := child as Node2D
		if c == null:
			continue
		if c.is_in_group("anchors") and c.global_position.y > _player.global_position.y + cull_behind_distance:
			print("[cleanup] delete circle at ", c.global_position)
			c.queue_free()


func _screen_mid_x_world() -> float:
	var vp := get_viewport()
	var rect := vp.get_visible_rect()
	var screen_mid := Vector2(rect.size.x * 0.5, rect.size.y * 0.5)
	var world_mid := vp.get_canvas_transform().affine_inverse() * screen_mid
	return world_mid.x


func _lane_x(on_right: bool, prev_x: float) -> float:
	var vp := get_viewport()
	var rect := vp.get_visible_rect()
	var left_world := vp.get_canvas_transform().affine_inverse() * Vector2(0.0, rect.size.y * 0.5)
	var right_world := vp.get_canvas_transform().affine_inverse() * Vector2(rect.size.x, rect.size.y * 0.5)
	var mid_x := (left_world.x + right_world.x) * 0.5
	var min_x: float
	var max_x: float
	if on_right:
		min_x = mid_x + 28.0
		max_x = minf(mid_x + 100.0, prev_x + 200.0)
		if max_x < min_x:
			max_x = min_x
		return randf_range(min_x, max_x)
	max_x = mid_x - 28.0
	min_x = maxf(mid_x - 100.0, prev_x - 200.0)
	if min_x > max_x:
		min_x = max_x
	return randf_range(min_x, max_x)
