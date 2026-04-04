extends CharacterBody2D
## Orbits current anchor; screen tap releases along orbit tangent; dash captures new anchors.

@export var dash_speed: float = 620.0
@export var max_offworld: float = 5200.0
@export var ghost_length: float = 220.0

var _anchor: NeonAnchor = null
var _orbit_angle: float = 0.0
var _ghost_line: Line2D

@onready var trail_particles: GPUParticles2D = $TrailParticles


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	_ghost_line = get_node_or_null("GhostLine") as Line2D
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.35, 1.0, 0.95))
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 48, Color(0.4, 1.0, 1.0, 0.9), 2.0, true)


func initialize_after_level() -> void:
	GameManager.reset_run()
	_attach_to_initial_anchor()


func _physics_process(delta: float) -> void:
	if GameManager.state == GameManager.GameState.GAMEOVER:
		velocity = Vector2.ZERO
		if _ghost_line:
			_ghost_line.clear_points()
		if trail_particles:
			trail_particles.emitting = false
		return
	match GameManager.state:
		GameManager.GameState.ORBITING:
			_physics_orbit(delta)
			_update_ghost()
		GameManager.GameState.DASHING:
			_physics_dash(delta)
		_:
			velocity = Vector2.ZERO
			if _ghost_line:
				_ghost_line.clear_points()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_on_tap()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_tap()


func _on_tap() -> void:
	if GameManager.state == GameManager.GameState.GAMEOVER:
		get_tree().reload_current_scene()
		return
	if GameManager.state != GameManager.GameState.ORBITING:
		return
	_release_dash()


func _attach_to_initial_anchor() -> void:
	var lg := get_parent().get_node_or_null("LevelGenerator") as NeonLevelGenerator
	if lg == null or lg.get_child_count() == 0:
		push_warning("Neon Pivot: LevelGenerator has no anchors yet.")
		return
	_anchor = lg.get_child(0) as NeonAnchor
	_orbit_angle = PI * 0.5
	global_position = _anchor.global_position + Vector2(_anchor.orbit_radius, 0.0).rotated(_orbit_angle)
	GameManager.set_game_state(GameManager.GameState.ORBITING)


func _physics_orbit(delta: float) -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		return
	_orbit_angle += _anchor.rotation_speed * delta
	global_position = _anchor.global_position + Vector2(_anchor.orbit_radius, 0.0).rotated(_orbit_angle)


func _release_dash() -> void:
	if _anchor == null:
		return
	var t_orbit := GameManager.get_time_in_current_orbit()
	GameManager.on_dash_started(t_orbit)
	var tangent := Vector2.RIGHT.rotated(_orbit_angle + PI * 0.5).normalized()
	velocity = tangent * dash_speed
	_anchor = null
	GameManager.set_game_state(GameManager.GameState.DASHING)
	if trail_particles:
		trail_particles.emitting = true


func _physics_dash(delta: float) -> void:
	var col := move_and_collide(velocity * delta)
	if col:
		GameManager.trigger_fail()
		return
	if global_position.length() > max_offworld:
		GameManager.trigger_fail()
		return
	_try_capture_anchor()


func _try_capture_anchor() -> void:
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as NeonAnchor
		if a == null:
			continue
		if a.contains_point_global(global_position):
			_capture_anchor(a)
			return


func _capture_anchor(a: NeonAnchor) -> void:
	var prev_pos := global_position
	GameManager.trigger_capture_haptic()
	velocity = Vector2.ZERO
	_anchor = a
	_orbit_angle = (global_position - a.global_position).angle()
	global_position = a.global_position + Vector2(a.orbit_radius, 0.0).rotated(_orbit_angle)
	GameManager.on_anchor_captured(1)
	GameManager.set_game_state(GameManager.GameState.ORBITING)
	a.play_capture_squash()
	if trail_particles:
		trail_particles.emitting = true
	var lg := get_parent().get_node_or_null("LevelGenerator") as NeonLevelGenerator
	if lg:
		lg.update_forward_hint(prev_pos, global_position)


func _update_ghost() -> void:
	if _ghost_line == null or _anchor == null:
		return
	var tangent := Vector2.RIGHT.rotated(_orbit_angle + PI * 0.5).normalized()
	_ghost_line.clear_points()
	_ghost_line.add_point(Vector2.ZERO)
	_ghost_line.add_point(tangent * ghost_length)
