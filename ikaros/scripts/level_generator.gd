class_name NeonLevelGenerator
extends Node2D
## Procedural anchors: adaptive distance + angle ahead of the player.

const ANCHOR_SCENE := preload("res://scenes/Anchor.tscn")
const LUX_SCENE := preload("res://scenes/LuxPickup.tscn")

@export var lux_spawn_chance: float = 0.42
@export var spawn_ahead_min: float = 380.0
@export var spawn_ahead_max: float = 620.0
@export var preload_forward_distance: float = 1500.0
@export var min_anchors_ahead: int = 4
@export var max_lateral_step: float = 260.0
@export var cull_behind_distance: float = 1100.0
@export var max_anchors_alive: int = 12

var _player: Node2D
var _last_spawn_anchor_pos: Vector2 = Vector2.ZERO
## Match web (Netlify): climb is “up” on screen — forward is -Y, not +X.
var _forward_hint: Vector2 = Vector2.UP
var _spawn_cooldown_sec: float = 0.0


func setup(player: Node2D) -> void:
	_player = player
	_last_spawn_anchor_pos = Vector2.ZERO
	_forward_hint = Vector2.UP
	var first: NeonAnchor = spawn_anchor_at(Vector2.ZERO)
	_last_spawn_anchor_pos = first.global_position
	# Prewarm chain so upcoming circles exist before the player starts moving.
	for _i in range(min_anchors_ahead):
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
	var from: Vector2 = _last_spawn_anchor_pos
	var jump_distance := _estimate_jump_distance()
	var max_step := maxf(220.0, jump_distance * 0.9) # anti-trap cap: always within 90% jump distance
	var min_step := maxf(150.0, max_step * 0.62)
	var d: float = randf_range(min_step, max_step)
	var forward := _forward_hint.normalized()
	# Keep flow mostly upward with only mild sideways variation.
	var theta: float = deg_to_rad(randf_range(-22.0, 22.0))
	var dir: Vector2 = forward.rotated(theta).normalized()
	if dir.y > -0.35:
		dir = (dir + Vector2.UP * 1.7).normalized()
	var target: Vector2 = _last_spawn_anchor_pos + dir * d
	# Cap single-step lateral shift so path doesn't zig-zag unpredictably.
	var dx := clampf(target.x - _last_spawn_anchor_pos.x, -max_lateral_step, max_lateral_step)
	target.x = _last_spawn_anchor_pos.x + dx
	spawn_anchor_at(target)
	_maybe_spawn_lux_between(from, target)
	_last_spawn_anchor_pos = target


func _maybe_spawn_lux_between(from: Vector2, to: Vector2) -> void:
	if randf() > lux_spawn_chance:
		return
	var t: float = randf_range(0.22, 0.78)
	var pos: Vector2 = from.lerp(to, t)
	pos += Vector2(randf_range(-72.0, 72.0), randf_range(-56.0, 56.0))
	var lux: LuxPickup = LUX_SCENE.instantiate()
	lux.global_position = pos
	add_child(lux)


func _try_spawn_ahead() -> void:
	var anchors := get_tree().get_nodes_in_group("anchors")
	if anchors.size() >= max_anchors_alive:
		return
	# Spawn when the *nearest* anchor is farther than this — player has outrun the chain
	# (using max distance was inverted: once you move ahead, "furthest" stays huge and nothing spawned).
	var nearest := INF
	for n in anchors:
		if n is Node2D:
			nearest = minf(nearest, n.global_position.distance_to(_player.global_position))
	var need_more := nearest > spawn_ahead_min * 0.85
	var ahead_count := 0
	for n in anchors:
		if n is Node2D:
			var to_anchor: Vector2 = n.global_position - _player.global_position
			if to_anchor.dot(_forward_hint) > 0.0:
				ahead_count += 1
	var dist_to_frontier := _player.global_position.distance_to(_last_spawn_anchor_pos)
	if not need_more and ahead_count < min_anchors_ahead:
		need_more = true
	if not need_more and dist_to_frontier < preload_forward_distance:
		need_more = true
	if need_more:
		_queue_spawn_ahead()
		_spawn_cooldown_sec = 0.3


func _cull_distant() -> void:
	for child in get_children():
		if child is NeonAnchor or child is LuxPickup:
			# Upward game: anything far below player is safe to cull.
			var far_below := child.global_position.y > _player.global_position.y + cull_behind_distance
			var far_away := child.global_position.distance_to(_player.global_position) > cull_behind_distance * 1.4
			if far_below or far_away:
				child.queue_free()


func update_forward_hint(from: Vector2, to: Vector2) -> void:
	var v := to - from
	if v.length_squared() > 0.0001:
		var next := v.normalized()
		# Bias to upward direction to avoid right-left drift over long runs.
		_forward_hint = (next + Vector2.UP * 1.5).normalized()


func _estimate_jump_distance() -> float:
	if _player != null and _player.has_method("get_jump_distance_hint"):
		return maxf(280.0, float(_player.call("get_jump_distance_hint")))
	return spawn_ahead_max
