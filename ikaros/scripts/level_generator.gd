class_name NeonLevelGenerator
extends Node2D
## Procedural anchors: adaptive distance + angle ahead of the player.

const ANCHOR_SCENE := preload("res://scenes/Anchor.tscn")
const LUX_SCENE := preload("res://scenes/LuxPickup.tscn")

@export var lux_spawn_chance: float = 0.42
@export var spawn_ahead_min: float = 380.0
@export var spawn_ahead_max: float = 620.0
@export var preload_forward_distance: float = 1500.0
@export var min_anchors_ahead: int = 2
@export var target_anchors_alive: int = 5
@export var spawn_interval_sec: float = 0.22
@export var max_lateral_step: float = 260.0
@export var min_anchor_center_gap: float = 250.0
@export var cull_behind_distance: float = 1100.0
@export var max_anchors_alive: int = 12
@export var vertical_spawn_step: float = 360.0
@export var force_spawn_jump_factor: float = 0.82

var _player = null
var _last_spawn_anchor_pos: Vector2 = Vector2.ZERO
## Match web (Netlify): climb is “up” on screen — forward is -Y, not +X.
var _forward_hint: Vector2 = Vector2.UP
var _spawn_cooldown_sec: float = 0.0
var _highest_player_y: float = 0.0
var _circles_since_lux: int = 0
var _lux_spawned_in_window: int = 0


func setup(player) -> void:
	_player = player
	_last_spawn_anchor_pos = Vector2.ZERO
	_forward_hint = Vector2.UP
	var first = spawn_anchor_at(Vector2.ZERO)
	_last_spawn_anchor_pos = first.global_position
	_highest_player_y = first.global_position.y
	_circles_since_lux = 0
	_lux_spawned_in_window = 0
	# Prewarm chain so upcoming circles exist before the player starts moving.
	for _i in range(min_anchors_ahead):
		_queue_spawn_ahead()
	_ensure_vertical_chain()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_spawn_cooldown_sec = maxf(_spawn_cooldown_sec - delta, 0.0)
	_highest_player_y = minf(_highest_player_y, _player.global_position.y)
	_ensure_vertical_chain()
	_try_spawn_ahead()
	_ensure_lux_presence()
	_cull_distant()


func spawn_anchor_at(global_pos: Vector2):
	var a = ANCHOR_SCENE.instantiate()
	a.global_position = global_pos
	if a.has_method("apply_difficulty"):
		a.call("apply_difficulty", GameManager.score)
	add_child(a)
	return a


func _queue_spawn_ahead() -> void:
	if _player == null:
		return
	var from: Vector2 = _last_spawn_anchor_pos
	var jump_distance = _estimate_jump_distance()
	var max_step = minf(520.0, maxf(280.0, jump_distance * 0.8))
	var min_step = maxf(220.0, max_step * 0.7)
	var target: Vector2 = _last_spawn_anchor_pos
	var ok := false
	for _attempt in range(6):
		var d: float = randf_range(min_step, max_step)
		var forward = _forward_hint.normalized()
		# Keep flow mostly upward with only mild sideways variation.
		var theta: float = deg_to_rad(randf_range(-18.0, 18.0))
		var dir: Vector2 = forward.rotated(theta).normalized()
		if dir.y > -0.45:
			dir = (dir + Vector2.UP * 1.9).normalized()
		target = _last_spawn_anchor_pos + dir * d
		# Cap single-step lateral shift so path doesn't zig-zag unpredictably.
		var dx = clampf(target.x - _last_spawn_anchor_pos.x, -max_lateral_step, max_lateral_step)
		target.x = _last_spawn_anchor_pos.x + dx
		var nearest_to_target := INF
		for n in get_tree().get_nodes_in_group("anchors"):
			var a := n as Node2D
			if a != null:
				nearest_to_target = minf(nearest_to_target, a.global_position.distance_to(target))
		if nearest_to_target >= min_anchor_center_gap:
			ok = true
			break
	if not ok:
		# Fallback still keeps climb moving upward even in dense fields.
		target = _last_spawn_anchor_pos + Vector2.UP * min_step
	spawn_anchor_at(target)
	_register_circle_and_lux(from, target)
	_last_spawn_anchor_pos = target


func _maybe_spawn_lux_between(from: Vector2, to: Vector2, force_spawn: bool = false) -> bool:
	if not force_spawn and randf() > lux_spawn_chance:
		return false
	var jump_vel: Vector2 = Vector2.UP * _estimate_jump_distance()
	if _player != null and _player.has_method("get_launch_velocity_hint"):
		jump_vel = _player.call("get_launch_velocity_hint") as Vector2
	var g: float = 1080.0
	if _player != null:
		var maybe_g = _player.get("dash_gravity")
		if maybe_g != null:
			g = float(maybe_g)
	var travel_time := clampf(from.distance_to(to) / maxf(220.0, jump_vel.length()), 0.28, 0.95)
	var t := randf_range(0.32, 0.68) * travel_time
	var pos: Vector2 = from + jump_vel * t + Vector2(0.0, 0.5 * g * t * t)
	pos.x = clampf(pos.x, minf(from.x, to.x) - 90.0, maxf(from.x, to.x) + 90.0)
	pos.y = minf(pos.y, maxf(from.y, to.y) - 28.0)
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as Node2D
		if a == null:
			continue
		var capture_r: float = 64.0
		var maybe_capture = a.get("capture_radius")
		if maybe_capture != null:
			capture_r = float(maybe_capture)
		if pos.distance_to(a.global_position) < capture_r + 26.0:
			return false
	var lux = LUX_SCENE.instantiate()
	lux.global_position = pos
	add_child(lux)
	return true


func _try_spawn_ahead() -> void:
	var anchors = get_tree().get_nodes_in_group("anchors")
	if anchors.size() >= max_anchors_alive:
		return
	if not _has_anchor_in_jump_range():
		_force_spawn_on_path()
		return
	var above_player := 0
	for n in anchors:
		var a := n as Node2D
		if a != null and a.global_position.y < _player.global_position.y - 8.0:
			above_player += 1
	if above_player < 2:
		_queue_spawn_ahead()
		_spawn_cooldown_sec = 0.0
		return
	if anchors.size() < _target_anchors_alive_for_score():
		_queue_spawn_ahead()
		_spawn_cooldown_sec = 0.0
		return
	# Spawn when the *nearest* anchor is farther than this — player has outrun the chain
	# (using max distance was inverted: once you move ahead, "furthest" stays huge and nothing spawned).
	var nearest = INF
	for n in anchors:
		var a := n as Node2D
		if a != null:
			nearest = minf(nearest, a.global_position.distance_to(_player.global_position))
	var need_more = nearest > spawn_ahead_min * 0.85
	var ahead_count = 0
	for n in anchors:
		var a := n as Node2D
		if a != null:
			var to_anchor: Vector2 = a.global_position - _player.global_position
			if to_anchor.dot(_forward_hint) > 0.0:
				ahead_count += 1
	var dist_to_frontier = _player.global_position.distance_to(_last_spawn_anchor_pos)
	if not need_more and ahead_count < min_anchors_ahead:
		need_more = true
	if not need_more and dist_to_frontier < preload_forward_distance:
		need_more = true
	if need_more:
		_queue_spawn_ahead()
		_spawn_cooldown_sec = 0.3


func _ensure_vertical_chain() -> void:
	if _player == null:
		return
	var guard := 0
	while _last_spawn_anchor_pos.y > _highest_player_y - vertical_spawn_step and guard < 5:
		_queue_spawn_ahead()
		guard += 1


func _has_anchor_in_jump_range() -> bool:
	if _player == null:
		return true
	var jump_distance := _estimate_jump_distance()
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as Node2D
		if a == null:
			continue
		if a.global_position.y >= _player.global_position.y - 2.0:
			continue
		if a.global_position.distance_to(_player.global_position) <= jump_distance:
			return true
	return false


func _force_spawn_on_path() -> void:
	if _player == null:
		return
	var jump_distance: float = _estimate_jump_distance()
	var target: Vector2 = _player.global_position + Vector2.UP * maxf(220.0, jump_distance * force_spawn_jump_factor)
	target.x = lerpf(_player.global_position.x, _last_spawn_anchor_pos.x, 0.25)
	var from: Vector2 = _last_spawn_anchor_pos
	var a = spawn_anchor_at(target)
	_register_circle_and_lux(from, a.global_position)
	_last_spawn_anchor_pos = a.global_position


func _register_circle_and_lux(from: Vector2, to: Vector2) -> void:
	_circles_since_lux += 1
	var must_spawn := false
	if _circles_since_lux == 2 and _lux_spawned_in_window < 1:
		must_spawn = true
	if _circles_since_lux >= 3 and _lux_spawned_in_window < 2:
		must_spawn = true
	var spawned := _maybe_spawn_lux_between(from, to, must_spawn)
	if spawned:
		_lux_spawned_in_window += 1
	if _circles_since_lux >= 3:
		_circles_since_lux = 0
		_lux_spawned_in_window = 0


func _cull_distant() -> void:
	for child in get_children():
		var c := child as Node2D
		if c != null:
			# Upward game: anything far below player is safe to cull.
			var far_below: bool = c.global_position.y > _player.global_position.y + cull_behind_distance
			if far_below:
				c.queue_free()


func update_forward_hint(from: Vector2, to: Vector2) -> void:
	var v := to - from
	if v.length_squared() > 0.0001:
		var next_dir: Vector2 = v.normalized()
		# Bias to upward direction to avoid right-left drift over long runs.
		_forward_hint = (next_dir + Vector2.UP * 1.5).normalized()


func _estimate_jump_distance() -> float:
	if _player != null and _player.has_method("get_jump_distance_hint"):
		return maxf(280.0, float(_player.call("get_jump_distance_hint")))
	return spawn_ahead_max


func _target_anchors_alive_for_score() -> int:
	var s := GameManager.score
	if s < 10:
		return 3
	if s < 30:
		return 4
	return target_anchors_alive


func _ensure_lux_presence() -> void:
	if _player == null:
		return
	for c in get_children():
		if c is LuxPickup:
			return
	var pos: Vector2 = _player.global_position + Vector2(0.0, -200.0)
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as Node2D
		if a == null:
			continue
		var capture_r: float = 64.0
		var maybe_capture = a.get("capture_radius")
		if maybe_capture != null:
			capture_r = float(maybe_capture)
		if pos.distance_to(a.global_position) < capture_r + 30.0:
			pos.x += capture_r + 42.0
	var lux = LUX_SCENE.instantiate()
	lux.global_position = pos
	add_child(lux)
