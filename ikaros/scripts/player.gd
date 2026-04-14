extends CharacterBody2D

enum PlayerState { IDLE, ATTACHED, LAUNCHED, FALLING, DEAD }

@export var launch_speed: float = 900.0
@export var gravity: float = 1250.0
@export var max_air_speed: float = 1400.0
@export var orbit_angular_speed: float = 1.8

var state: PlayerState = PlayerState.IDLE
var _anchor: NeonAnchor = null
var _ignore_anchor: NeonAnchor = null
var _orbit_angle: float = PI * 0.5
var _left_wall: StaticBody2D
var _right_wall: StaticBody2D
var _kill_floor: StaticBody2D
var _left_rail: Line2D
var _right_rail: Line2D
var _last_fail_reason: String = ""

@onready var _cam: Camera2D = $Camera2D
@onready var _ghost_line: Line2D = $GhostLine
@onready var _trail: GPUParticles2D = $TrailParticles

var _fill_color := Color(0.0, 0.95, 0.996, 0.95)
var _ring_color := Color(0.0, 0.95, 0.996, 0.95)


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 8
	_setup_boundaries()
	_setup_rails()
	if _ghost_line:
		_ghost_line.visible = false
	if _trail:
		_trail.emitting = false
	ItemDatabase.equipped_changed.connect(_on_equipped_theme)
	var c := ItemDatabase.peek_equipped_theme()
	_on_equipped_theme(c[0], c[1], c[2], c[3])
	queue_redraw()


func initialize_after_level() -> void:
	GameManager.reset_run()
	_last_fail_reason = ""
	_attach_to_first_anchor()


func _input(event: InputEvent) -> void:
	if state != PlayerState.ATTACHED:
		return
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		_launch_from_anchor()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
			_launch_from_anchor()


func _physics_process(delta: float) -> void:
	_update_boundaries_and_rails()
	_update_camera_lock()
	if state == PlayerState.DEAD:
		velocity = Vector2.ZERO
		return
	match state:
		PlayerState.ATTACHED:
			_update_orbit(delta)
		PlayerState.LAUNCHED:
			_update_air(delta, false)
		PlayerState.FALLING:
			_update_air(delta, true)
		_:
			pass
	_never_stuck_rule()
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 14.0, _fill_color)
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 48, _ring_color, 2.4, true)


func _on_equipped_theme(pf: Color, pr: Color, _ar: Color, _ac: Color) -> void:
	_fill_color = pf
	_ring_color = pr
	queue_redraw()


func _attach_to_first_anchor() -> void:
	var lg := get_parent().get_node_or_null("LevelGenerator") as NeonLevelGenerator
	if lg == null:
		_die("no_level_generator")
		return
	var first := _first_anchor()
	if first == null:
		_die("no_anchor")
		return
	_attach_anchor(first)


func _first_anchor() -> NeonAnchor:
	var best: NeonAnchor = null
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as NeonAnchor
		if a == null or not is_instance_valid(a):
			continue
		if best == null or a.global_position.y > best.global_position.y:
			best = a
	return best


func _attach_anchor(a: NeonAnchor) -> void:
	if _anchor != null and is_instance_valid(_anchor):
		_anchor.set_active_orbit_anchor(false)
	_anchor = a
	_anchor.set_active_orbit_anchor(true)
	if not _anchor.countdown_finished.is_connected(_on_anchor_expired):
		_anchor.countdown_finished.connect(_on_anchor_expired)
	_orbit_angle = (global_position - _anchor.global_position).angle()
	if state == PlayerState.IDLE:
		_orbit_angle = PI * 0.5
	global_position = _anchor.global_position + Vector2.RIGHT.rotated(_orbit_angle) * _anchor.orbit_radius
	velocity = Vector2.ZERO
	_ignore_anchor = null
	state = PlayerState.ATTACHED
	GameManager.set_game_state(GameManager.GameState.ORBITING)


func _on_anchor_expired(a: NeonAnchor) -> void:
	if _anchor == null or a != _anchor:
		return
	_anchor = null
	state = PlayerState.FALLING
	GameManager.set_game_state(GameManager.GameState.FALLING)


func _launch_from_anchor() -> void:
	if _anchor == null:
		return
	var tangent := Vector2.RIGHT.rotated(_orbit_angle + PI * 0.5).normalized()
	var launch_dir := tangent.rotated(-PI * 0.25).normalized()
	_ignore_anchor = _anchor
	_anchor.set_active_orbit_anchor(false)
	_anchor = null
	velocity = launch_dir * launch_speed
	state = PlayerState.LAUNCHED
	GameManager.on_dash_started(GameManager.get_time_in_current_orbit())
	GameManager.set_game_state(GameManager.GameState.DASHING)


func _update_orbit(delta: float) -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		state = PlayerState.FALLING
		GameManager.set_game_state(GameManager.GameState.FALLING)
		return
	_orbit_angle += orbit_angular_speed * delta * signf(_anchor.rotation_speed)
	global_position = _anchor.global_position + Vector2.RIGHT.rotated(_orbit_angle) * _anchor.orbit_radius


func _update_air(delta: float, apply_gravity: bool) -> void:
	if apply_gravity:
		velocity.y += gravity * delta
	if velocity.length() > max_air_speed:
		velocity = velocity.normalized() * max_air_speed
	var col := move_and_collide(velocity * delta)
	if col != null and _handle_collision(col):
		return
	if _check_kill_zone():
		return
	_release_ignored_anchor_if_exited()
	_try_hook_anchor()


func _handle_collision(col: KinematicCollision2D) -> bool:
	var n := col.get_collider() as Node
	if n == null:
		return false
	if n.is_in_group("screen_wall"):
		velocity.x = -velocity.x
		return true
	if n.is_in_group("screen_kill_zone"):
		_die("kill_zone")
		return true
	return false


func _check_kill_zone() -> bool:
	var cam_y := _cam.global_position.y if _cam != null else global_position.y
	if global_position.y > cam_y + 600.0:
		_die("kill_zone_height")
		return true
	return false


func _try_hook_anchor() -> void:
	var best: NeonAnchor = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as NeonAnchor
		if a == null or not is_instance_valid(a):
			continue
		if a == _anchor:
			continue
		if _ignore_anchor != null and a == _ignore_anchor:
			continue
		if a.contains_point_global(global_position):
			var d := global_position.distance_squared_to(a.global_position)
			if d < best_d:
				best_d = d
				best = a
	if best == null:
		return
	GameManager.on_anchor_captured(1)
	GameManager.trigger_capture_haptic()
	best.play_capture_squash()
	_attach_anchor(best)


func _release_ignored_anchor_if_exited() -> void:
	if _ignore_anchor == null or not is_instance_valid(_ignore_anchor):
		_ignore_anchor = null
		return
	if not _ignore_anchor.contains_point_global(global_position):
		_ignore_anchor = null


func _never_stuck_rule() -> void:
	if state == PlayerState.LAUNCHED or state == PlayerState.FALLING:
		if velocity.length() < 10.0:
			_die("never_stuck")


func _die(reason: String) -> void:
	if state == PlayerState.DEAD:
		return
	_last_fail_reason = reason
	state = PlayerState.DEAD
	GameManager.trigger_fail()


func _setup_boundaries() -> void:
	var p := get_parent()
	_left_wall = _make_boundary("LeftWall", p, "screen_wall")
	_right_wall = _make_boundary("RightWall", p, "screen_wall")
	_kill_floor = _make_boundary("KillFloor", p, "screen_kill_zone")


func _make_boundary(name: String, parent: Node, group_name: String) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.name = name
	b.collision_layer = 8
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.8
	pm.friction = 0.0
	b.physics_material_override = pm
	var cs := CollisionShape2D.new()
	cs.shape = WorldBoundaryShape2D.new()
	b.add_child(cs)
	b.add_to_group(group_name)
	parent.add_child(b)
	return b


func _setup_rails() -> void:
	var p := get_parent()
	_left_rail = Line2D.new()
	_right_rail = Line2D.new()
	for ln in [_left_rail, _right_rail]:
		ln.width = 2.0
		ln.default_color = Color(0.0, 0.949, 0.996, 0.1)
		ln.antialiased = true
		ln.z_index = -20
		p.add_child(ln)


func _update_boundaries_and_rails() -> void:
	if _left_wall == null or _right_wall == null or _kill_floor == null:
		return
	var rect := get_viewport().get_visible_rect()
	var left_x := _screen_to_world(Vector2(0.0, rect.size.y * 0.5)).x
	var right_x := _screen_to_world(Vector2(rect.size.x, rect.size.y * 0.5)).x
	var cam_y := _cam.global_position.y if _cam != null else global_position.y
	var floor_y := cam_y + 600.0
	var left_shape := (_left_wall.get_child(0) as CollisionShape2D).shape as WorldBoundaryShape2D
	var right_shape := (_right_wall.get_child(0) as CollisionShape2D).shape as WorldBoundaryShape2D
	var floor_shape := (_kill_floor.get_child(0) as CollisionShape2D).shape as WorldBoundaryShape2D
	left_shape.normal = Vector2.RIGHT
	left_shape.distance = left_x
	right_shape.normal = Vector2.LEFT
	right_shape.distance = -right_x
	floor_shape.normal = Vector2.UP
	floor_shape.distance = -floor_y
	var top_y := cam_y - 900.0
	var bot_y := cam_y + 900.0
	_left_rail.clear_points()
	_left_rail.add_point(Vector2(left_x, top_y))
	_left_rail.add_point(Vector2(left_x, bot_y))
	_right_rail.clear_points()
	_right_rail.add_point(Vector2(right_x, top_y))
	_right_rail.add_point(Vector2(right_x, bot_y))


func _update_camera_lock() -> void:
	if _cam == null:
		return
	# Camera moves upward with gameplay; no horizontal drift.
	_cam.position = Vector2(-global_position.x, 0.0)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func get_debug_snapshot() -> Dictionary:
	var nearest := INF
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as NeonAnchor
		if a == null or not is_instance_valid(a):
			continue
		nearest = minf(nearest, global_position.distance_to(a.global_position))
	return {
		"state": str(state),
		"spd": snappedf(velocity.length(), 0.1),
		"vy": snappedf(velocity.y, 0.1),
		"nearest": -1.0 if nearest == INF else snappedf(nearest, 0.1),
		"launches": 0,
		"captures": GameManager.score,
		"fail": _last_fail_reason,
	}
