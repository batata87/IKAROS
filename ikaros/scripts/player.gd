extends CharacterBody2D
## Orbits current anchor; screen tap releases along orbit tangent; dash captures new anchors.
## Arcade Overdrive: centrifugal launch charge, coyote emergency dash, camera zoom, score pops.

const SCORE_POP := preload("res://scenes/ScorePop.tscn")
const COYOTE_BURST := preload("res://scenes/CoyoteBurst.tscn")

const MAX_CENTRIFUGAL_REVS: int = 8
const CENTRIFUGAL_MULT_PER_REV: float = 0.25
const MAX_LAUNCH_MULT: float = 3.0

@export var dash_speed: float = 715.0
@export var dash_gravity: float = 1080.0
@export var max_offworld: float = 5200.0
@export var ghost_length: float = 200.0
@export var jump_arc_sec: float = 0.56
@export var zoom_tight: float = 0.92
@export var zoom_wide: float = 0.68
@export var zoom_speed_ref: float = 920.0
@export var launch_power: float = 980.0
@export var max_air_speed: float = 1300.0

var _anchor: NeonAnchor = null
var _orbit_angle: float = 0.0
var _ghost_line: Line2D

@onready var trail_particles: GPUParticles2D = $TrailParticles
@onready var _cam: Camera2D = $Camera2D
@onready var _charge_blip: AudioStreamPlayer = $ChargeBlip
@onready var _charge_hum: AudioStreamPlayer = $ChargeHum

var _fill_color: Color = Color(0.0, 0.95, 0.996, 0.98)
var _ring_color: Color = Color(0.0, 0.95, 0.996, 0.9)

## Radians traveled on current anchor (for partial revolution visual + audio steps).
var _orbit_path_accum: float = 0.0
## Full 2π laps completed while on this anchor (capped).
var _centrifugal_revs: int = 0
var _vib_phase: float = 0.0

var _coyote_armed: bool = false
var _coyote_used: bool = false
var _hum_phase: float = 0.0
var _last_tap_msec: int = -1000
var _pointer_was_down: bool = false
var _ignore_capture_anchor: NeonAnchor = null
var _input_lock_until_msec: int = 0
var _dash_time_sec: float = 0.0
var _stuck_time_sec: float = 0.0
var _last_launch_velocity: Vector2 = Vector2.UP * 715.0
var _capture_blend_from: Vector2 = Vector2.ZERO
var _capture_blend_t: float = 1.0
var _timer_fail_lock: bool = false
var _capture_tween: Tween
var _capture_tween_active: bool = false
var _air_still_sec: float = 0.0
var _launch_count: int = 0
var _capture_count: int = 0
var _last_fail_reason: String = ""
var _left_wall: StaticBody2D = null
var _right_wall: StaticBody2D = null
var _kill_floor: StaticBody2D = null


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 0
	_ghost_line = get_node_or_null("GhostLine") as Line2D
	if _ghost_line != null:
		_ghost_line.queue_free()
		_ghost_line = null
	_setup_screen_safe_container()
	_setup_ghost_line_style()
	if _charge_hum and _charge_hum.stream == null:
		var g := AudioStreamGenerator.new()
		g.mix_rate = 24000.0
		_charge_hum.stream = g
		_charge_hum.volume_db = -24.0
	ItemDatabase.equipped_changed.connect(_on_equipped_theme)
	var c: Array = ItemDatabase.peek_equipped_theme()
	_on_equipped_theme(c[0], c[1], c[2], c[3])
	_configure_trail_performance()
	if _cam != null:
		_cam.position_smoothing_enabled = false
		_cam.position_smoothing_speed = 5.0
	if trail_particles != null:
		trail_particles.z_index = -5
		trail_particles.amount = mini(trail_particles.amount, 16)
	queue_redraw()


func _on_equipped_theme(pf: Color, pr: Color, _ar: Color, _ac: Color) -> void:
	_fill_color = pf
	_ring_color = pr
	if trail_particles and trail_particles.process_material is ParticleProcessMaterial:
		var pm := trail_particles.process_material as ParticleProcessMaterial
		pm.color = Color(pr.r, pr.g, pr.b, 0.55)
	queue_redraw()


func _configure_trail_performance() -> void:
	if trail_particles == null:
		return
	var hz: float = DisplayServer.screen_get_refresh_rate()
	if hz <= 0.0:
		hz = 60.0
	var high_refresh := hz >= 90.0
	var mobile := OS.has_feature("mobile")
	if mobile:
		trail_particles.amount = mini(trail_particles.amount, 26)
		trail_particles.fixed_fps = 45 if high_refresh else 30
	else:
		trail_particles.amount = mini(trail_particles.amount, 34)
		trail_particles.fixed_fps = 60 if high_refresh else 0


func get_overdrive_speed_hint() -> float:
	if GameManager.state == GameManager.GameState.GAMEOVER:
		return 0.0
	if GameManager.state == GameManager.GameState.DASHING:
		return velocity.length()
	if GameManager.state == GameManager.GameState.ORBITING and _anchor != null and is_instance_valid(_anchor):
		return absf(_anchor.rotation_speed * _anchor.orbit_radius)
	return 0.0


func get_jump_distance_hint() -> float:
	var speed := dash_speed
	if GameManager.state == GameManager.GameState.ORBITING:
		speed = dash_speed * _centrifugal_launch_mult()
	elif GameManager.state == GameManager.GameState.DASHING:
		speed = maxf(speed, velocity.length())
	return speed * jump_arc_sec


func get_launch_velocity_hint() -> Vector2:
	if GameManager.state == GameManager.GameState.DASHING and velocity.length_squared() > 1.0:
		return velocity
	if _last_launch_velocity.length_squared() > 1.0:
		return _last_launch_velocity
	return Vector2.UP * dash_speed


func _centrifugal_charge_t() -> float:
	return clampf(
		(float(_centrifugal_revs) + _orbit_path_accum / TAU) / float(MAX_CENTRIFUGAL_REVS),
		0.0,
		1.0,
	)


func _draw_visual_scale() -> float:
	return lerpf(1.0, 1.5, _centrifugal_charge_t())


func _reset_centrifugal() -> void:
	_orbit_path_accum = 0.0
	_centrifugal_revs = 0


func _draw() -> void:
	var ct := _centrifugal_charge_t()
	var amp: float = ct * 3.2
	var ox: float = sin(_vib_phase) * amp + sin(_vib_phase * 2.17) * amp * 0.35
	var oy: float = cos(_vib_phase * 1.13) * amp + cos(_vib_phase * 1.9) * amp * 0.28
	var r0: float = 14.0 * _draw_visual_scale()
	var off := Vector2(ox, oy)
	draw_circle(off, r0, _fill_color)
	draw_arc(off, r0, 0.0, TAU, 48, _ring_color, 2.0, true)


func initialize_after_level() -> void:
	GameManager.reset_run()
	_reset_centrifugal()
	_coyote_armed = false
	_coyote_used = false
	# Prevent the menu tap from immediately triggering a gameplay release on mobile.
	var now := Time.get_ticks_msec()
	_input_lock_until_msec = now + 220
	_last_tap_msec = now
	_pointer_was_down = (Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT) != 0
	_dash_time_sec = 0.0
	_stuck_time_sec = 0.0
	_timer_fail_lock = false
	_capture_blend_t = 1.0
	_capture_tween_active = false
	_air_still_sec = 0.0
	_launch_count = 0
	_capture_count = 0
	_last_fail_reason = ""
	_attach_to_initial_anchor()


func _physics_process(delta: float) -> void:
	_update_screen_safe_container()
	_poll_mobile_pointer_tap()
	if GameManager.state == GameManager.GameState.GAMEOVER:
		velocity = Vector2.ZERO
		if _ghost_line:
			_ghost_line.clear_points()
		if trail_particles:
			trail_particles.emitting = false
		if _charge_hum and _charge_hum.playing:
			_charge_hum.stop()
		_update_camera_zoom(delta)
		return
	match GameManager.state:
		GameManager.GameState.ORBITING:
			_physics_orbit(delta)
			_update_charge_audio()
		GameManager.GameState.DASHING:
			_physics_dash(delta)
			if _ghost_line:
				_ghost_line.clear_points()
			if _charge_hum and _charge_hum.playing:
				_charge_hum.stop()
		GameManager.GameState.FALLING:
			_physics_fall(delta)
			if _ghost_line:
				_ghost_line.clear_points()
			if _charge_hum and _charge_hum.playing:
				_charge_hum.stop()
		_:
			velocity = Vector2.ZERO
			if _ghost_line:
				_ghost_line.clear_points()
			if _charge_hum and _charge_hum.playing:
				_charge_hum.stop()
	_update_camera_zoom(delta)
	_enforce_viewport_bounce()
	_update_air_still_fallback(delta)
	queue_redraw()


func _poll_mobile_pointer_tap() -> void:
	if not OS.has_feature("mobile"):
		return
	if Time.get_ticks_msec() < _input_lock_until_msec:
		_pointer_was_down = (Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT) != 0
		return
	var pointer_down := (Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT) != 0
	if (not pointer_down) and _pointer_was_down:
		var now := Time.get_ticks_msec()
		if now - _last_tap_msec >= 80:
			_last_tap_msec = now
			_on_tap()
	_pointer_was_down = pointer_down


func _update_camera_zoom(delta: float) -> void:
	if _cam == null:
		return
	var spd := get_overdrive_speed_hint()
	var t := clampf(spd / zoom_speed_ref, 0.0, 1.0)
	var z_tgt := lerpf(zoom_tight, zoom_wide, t)
	var zz := lerpf(_cam.zoom.x, z_tgt, 1.0 - exp(-4.2 * delta))
	_cam.zoom = Vector2(zz, zz)
	var off_tgt := Vector2(0.0, -180.0 if GameManager.state == GameManager.GameState.DASHING else -140.0)
	_cam.offset = _cam.offset.lerp(off_tgt, 1.0 - exp(-5.0 * delta))


func _input(event: InputEvent) -> void:
	if not _is_tap_event(event):
		return
	if Time.get_ticks_msec() < _input_lock_until_msec:
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap_msec < 80:
		return
	_last_tap_msec = now
	_on_tap()
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func _is_tap_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return not st.pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		return not DisplayServer.is_touchscreen_available()
	return false


func _on_tap() -> void:
	if GameManager.state == GameManager.GameState.GAMEOVER:
		get_tree().reload_current_scene()
		return
	if GameManager.state == GameManager.GameState.DASHING:
		if _coyote_armed and not _coyote_used and velocity.y > 0.0:
			_emergency_dash_to_nearest_anchor()
		return
	if GameManager.state != GameManager.GameState.ORBITING:
		return
	_release_dash()


func _attach_to_initial_anchor() -> void:
	var parent := get_parent()
	if parent == null:
		push_warning("IKAROS: Player has no parent node.")
		return
	var lg := parent.get_node_or_null("LevelGenerator") as NeonLevelGenerator
	if lg == null or lg.get_child_count() == 0:
		push_warning("IKAROS: LevelGenerator has no anchors yet.")
		return
	_anchor = lg.get_child(0) as NeonAnchor
	if _anchor:
		_anchor.set_active_orbit_anchor(true)
		_bind_anchor_events(_anchor)
	_orbit_angle = PI * 0.5
	global_position = _anchor.global_position + Vector2(_anchor.orbit_radius, 0.0).rotated(_orbit_angle)
	_reset_centrifugal()
	GameManager.set_game_state(GameManager.GameState.ORBITING)


func _physics_orbit(delta: float) -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		return
	var step := absf(_anchor.rotation_speed * delta)
	_orbit_path_accum += step
	while _orbit_path_accum >= TAU:
		_orbit_path_accum -= TAU
		if _centrifugal_revs < MAX_CENTRIFUGAL_REVS:
			_centrifugal_revs += 1
			_play_charge_blip()
	var ct := _centrifugal_charge_t()
	_vib_phase += delta * (72.0 + 140.0 * ct)
	_orbit_angle += _anchor.rotation_speed * delta
	var target := _anchor.global_position + Vector2(_anchor.orbit_radius, 0.0).rotated(_orbit_angle)
	if _capture_tween_active:
		# Tween drives position during capture smoothing.
		pass
	elif _capture_blend_t < 1.0:
		_capture_blend_t = minf(1.0, _capture_blend_t + delta / 0.1)
		global_position = _capture_blend_from.lerp(target, _capture_blend_t)
	else:
		global_position = target
	_update_active_anchor_reachability()
	if trail_particles:
		trail_particles.emitting = false


func _update_active_anchor_reachability() -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		return
	var jump_distance := get_jump_distance_hint()
	var has_target := false
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as NeonAnchor
		if a == null or not is_instance_valid(a) or a == _anchor:
			continue
		# Prefer "upward" targets for fairness in the climb direction.
		if a.global_position.y >= _anchor.global_position.y - 2.0:
			continue
		var d := global_position.distance_to(a.global_position)
		if d <= jump_distance + a.capture_radius:
			has_target = true
			break
	_anchor.set_target_reachable(has_target)


func _bind_anchor_events(a: NeonAnchor) -> void:
	if a == null:
		return
	if not a.countdown_finished.is_connected(_on_anchor_countdown_finished):
		a.countdown_finished.connect(_on_anchor_countdown_finished)


func _on_anchor_countdown_finished(anchor: NeonAnchor) -> void:
	if _anchor == null or anchor != _anchor or _timer_fail_lock:
		return
	_timer_fail_lock = true
	var fall_v := velocity
	_anchor = null
	_ignore_capture_anchor = null
	_capture_blend_t = 1.0
	if absf(fall_v.y) < 30.0:
		fall_v = Vector2(0.0, 380.0)
	velocity = fall_v
	_last_fail_reason = "anchor_timeout_fall"
	GameManager.set_game_state(GameManager.GameState.FALLING)


func _play_charge_blip() -> void:
	if _charge_blip != null and _charge_blip.stream != null:
		_charge_blip.pitch_scale = lerpf(1.0, 1.85, _centrifugal_charge_t())
		_charge_blip.play()


func _fill_charge_hum_buffer() -> void:
	if _charge_hum == null or not _charge_hum.playing:
		return
	var pb := _charge_hum.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var gen := _charge_hum.stream as AudioStreamGenerator
	if gen == null:
		return
	var avail := pb.get_frames_available()
	if avail <= 0:
		return
	var hz := lerpf(95.0, 420.0, _centrifugal_charge_t())
	var sr := float(gen.mix_rate)
	var n := mini(int(avail), 768)
	var buf := PackedVector2Array()
	buf.resize(n)
	var inc := TAU * hz / sr
	for i in range(n):
		var s := sin(_hum_phase) * 0.11
		_hum_phase = fmod(_hum_phase + inc, TAU * 1000.0)
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)


func _update_charge_audio() -> void:
	if _charge_hum == null or _charge_hum.stream == null:
		return
	var ct := _centrifugal_charge_t()
	if _charge_hum.stream is AudioStreamGenerator:
		if ct > 0.02 and GameManager.state == GameManager.GameState.ORBITING:
			if not _charge_hum.playing:
				_charge_hum.play()
			_fill_charge_hum_buffer()
		else:
			if _charge_hum.playing:
				_charge_hum.stop()
		return
	if ct > 0.02 and GameManager.state == GameManager.GameState.ORBITING:
		if not _charge_hum.playing:
			_charge_hum.play()
		_charge_hum.pitch_scale = lerpf(0.82, 2.05, ct)
	else:
		if _charge_hum.playing:
			_charge_hum.stop()


func _centrifugal_launch_mult() -> float:
	return minf(MAX_LAUNCH_MULT, 1.0 + CENTRIFUGAL_MULT_PER_REV * float(_centrifugal_revs))


func _release_dash() -> void:
	if _anchor == null:
		return
	var launch_v := _solve_launch_velocity()
	_anchor.set_active_orbit_anchor(false)
	_ignore_capture_anchor = _anchor
	var t_orbit := GameManager.get_time_in_current_orbit()
	GameManager.on_dash_started(t_orbit)
	velocity = launch_v
	_launch_count += 1
	_last_launch_velocity = velocity
	_reset_centrifugal()
	_anchor = null
	_dash_time_sec = 0.0
	_stuck_time_sec = 0.0
	_coyote_used = false
	_coyote_armed = velocity.y > 0.0
	GameManager.set_game_state(GameManager.GameState.DASHING)
	if trail_particles:
		trail_particles.restart()
		trail_particles.emitting = true


func _release_capture_ignore_if_exited() -> void:
	if _ignore_capture_anchor == null or not is_instance_valid(_ignore_capture_anchor):
		_ignore_capture_anchor = null
		return
	if not _ignore_capture_anchor.contains_point_global(global_position):
		_ignore_capture_anchor = null


func _emergency_dash_to_nearest_anchor() -> void:
	var best: NeonAnchor = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as NeonAnchor
		if a == null or not is_instance_valid(a):
			continue
		var d := global_position.distance_squared_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	if best == null:
		return
	var dir := best.global_position - global_position
	if dir.length_squared() < 4.0:
		return
	velocity = dir.normalized() * dash_speed * 1.08
	_coyote_used = true
	_coyote_armed = false
	_spawn_coyote_fx()
	if trail_particles:
		trail_particles.emitting = true


func _spawn_coyote_fx() -> void:
	var par := get_parent()
	if par == null:
		return
	var fx: Node = COYOTE_BURST.instantiate()
	par.add_child(fx)
	fx.global_position = global_position


func _physics_dash(delta: float) -> void:
	_dash_time_sec += delta
	_release_capture_ignore_if_exited()
	velocity.y += dash_gravity * delta
	_apply_subtle_magnet(delta)
	_cap_air_velocity()
	var col = move_and_collide(velocity * delta)
	if col:
		if _handle_air_collision(col):
			return
		_last_fail_reason = "dash_collision"
		GameManager.trigger_fail()
		return
	if _dash_time_sec > 3.2:
		_last_fail_reason = "dash_timeout"
		GameManager.trigger_fail()
		return
	if global_position.length() > max_offworld:
		_last_fail_reason = "dash_offworld"
		GameManager.trigger_fail()
		return
	_try_capture_anchor()


func _physics_fall(delta: float) -> void:
	velocity.y += dash_gravity * delta
	_apply_subtle_magnet(delta)
	_cap_air_velocity()
	var col := move_and_collide(velocity * delta)
	if col:
		if _handle_air_collision(col):
			return
		_last_fail_reason = "fall_collision"
		die()
		return
	if global_position.length() > max_offworld:
		_last_fail_reason = "fall_offworld"
		die()
		return
	_try_capture_anchor()


func apply_emergency_gravity(delta: float) -> void:
	if GameManager.state != GameManager.GameState.FALLING and GameManager.state != GameManager.GameState.DASHING:
		GameManager.set_game_state(GameManager.GameState.FALLING)
	velocity.y += dash_gravity * 1.15 * delta


func die() -> void:
	if _last_fail_reason == "":
		_last_fail_reason = "die_called"
	GameManager.trigger_fail()


func _safe_play_bounds() -> Rect2:
	var vp := get_viewport()
	var screen_rect := vp.get_visible_rect()
	var screen_top_left_world := _screen_to_world(Vector2(0.0, 0.0))
	var screen_top_right_world := _screen_to_world(Vector2(screen_rect.size.x, 0.0))
	var screen_bottom_left_world := _screen_to_world(Vector2(0.0, screen_rect.size.y))
	return Rect2(
		screen_top_left_world,
		Vector2(screen_top_right_world.x - screen_top_left_world.x, screen_bottom_left_world.y - screen_top_left_world.y)
	)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _enforce_viewport_bounce() -> void:
	# Physics container (screen walls + kill floor) owns boundary behavior.
	return


func _pick_next_target_anchor() -> NeonAnchor:
	var best: NeonAnchor = null
	var best_d2 := INF
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as NeonAnchor
		if a == null or not is_instance_valid(a) or a == _anchor:
			continue
		if a.global_position.y >= global_position.y - 2.0:
			continue
		var d2 := global_position.distance_squared_to(a.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = a
	return best


func _solve_launch_velocity() -> Vector2:
	var direction_vector := Vector2.RIGHT.rotated(_orbit_angle + PI * 0.5).normalized()
	return direction_vector * launch_power


func _update_air_still_fallback(delta: float) -> void:
	if _anchor != null:
		_air_still_sec = 0.0
		return
	if velocity.length() < 10.0:
		_air_still_sec += delta
		if _air_still_sec >= 0.1:
			apply_emergency_gravity(delta)
	else:
		_air_still_sec = 0.0


func _apply_subtle_magnet(delta: float) -> void:
	var best: NeonAnchor = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as NeonAnchor
		if a == null or not is_instance_valid(a):
			continue
		if _ignore_capture_anchor != null and a == _ignore_capture_anchor:
			continue
		var d := global_position.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	if best != null and best_d <= 50.0:
		var dir := (best.global_position - global_position).normalized()
		velocity += dir * 220.0 * delta


func _cap_air_velocity() -> void:
	if velocity.length() > max_air_speed:
		velocity = velocity.normalized() * max_air_speed


func _try_capture_anchor() -> void:
	var best: NeonAnchor = null
	var best_d2 := INF
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as NeonAnchor
		if a == null or not is_instance_valid(a):
			continue
		if _ignore_capture_anchor != null and a == _ignore_capture_anchor:
			continue
		# Enforce upward-only valid captures.
		if a.global_position.y >= global_position.y - 2.0:
			continue
		if a.contains_point_global(global_position):
			var d2 := global_position.distance_squared_to(a.global_position)
			if d2 < best_d2:
				best_d2 = d2
				best = a
	if best != null:
		_capture_anchor(best)


func _spawn_score_pop(at: Vector2, points: int, combo_style: bool) -> void:
	var par := get_parent()
	if par == null:
		return
	var pop := SCORE_POP.instantiate()
	par.add_child(pop)
	pop.global_position = at
	var txt := "!! COMBO !!" if combo_style else "+%d" % maxi(1, points)
	pop.call_deferred("start", txt, combo_style)


func _capture_anchor(a: NeonAnchor) -> void:
	var prev_pos := global_position
	var pts := int(round(GameManager.multiplier))
	var combo_style := GameManager.multiplier > 1.0001
	GameManager.trigger_capture_haptic()
	velocity = Vector2.ZERO
	_anchor = a
	_anchor.set_active_orbit_anchor(true)
	_bind_anchor_events(_anchor)
	_orbit_angle = (global_position - a.global_position).angle()
	_capture_blend_from = global_position
	_capture_blend_t = 0.0
	if _capture_tween and _capture_tween.is_valid():
		_capture_tween.kill()
	var target_pos := a.global_position + Vector2(a.orbit_radius, 0.0).rotated(_orbit_angle)
	_capture_tween_active = true
	_capture_tween = create_tween()
	_capture_tween.tween_property(self, "global_position", target_pos, 0.1)
	_capture_tween.finished.connect(func() -> void:
		_capture_tween_active = false
	)
	GameManager.on_anchor_captured(1)
	_capture_count += 1
	GameManager.set_game_state(GameManager.GameState.ORBITING)
	_dash_time_sec = 0.0
	_stuck_time_sec = 0.0
	_timer_fail_lock = false
	_reset_centrifugal()
	_coyote_armed = false
	_coyote_used = false
	a.play_capture_squash()
	if trail_particles:
		trail_particles.emitting = true
	var parent := get_parent()
	if parent == null:
		_spawn_score_pop(prev_pos, pts, combo_style)
		return
	var lg := parent.get_node_or_null("LevelGenerator") as NeonLevelGenerator
	if lg:
		lg.update_forward_hint(prev_pos, global_position)
	_spawn_score_pop(prev_pos, pts, combo_style)


func get_debug_snapshot() -> Dictionary:
	var nearest := INF
	for n in get_tree().get_nodes_in_group("anchors"):
		var a := n as NeonAnchor
		if a == null or not is_instance_valid(a):
			continue
		if _anchor != null and a == _anchor:
			continue
		nearest = minf(nearest, global_position.distance_to(a.global_position))
	return {
		"state": str(GameManager.state),
		"spd": snappedf(velocity.length(), 0.1),
		"vy": snappedf(velocity.y, 0.1),
		"nearest": -1.0 if nearest == INF else snappedf(nearest, 0.1),
		"launches": _launch_count,
		"captures": _capture_count,
		"fail": _last_fail_reason,
	}


func _update_ghost() -> void:
	if _ghost_line == null or _anchor == null:
		return
	if not _is_pointer_down():
		_ghost_line.clear_points()
		return
	var tangent := Vector2.RIGHT.rotated(_orbit_angle + PI * 0.5).normalized()
	_ghost_line.clear_points()
	_ghost_line.add_point(Vector2.ZERO)
	_ghost_line.add_point(tangent * ghost_length * _draw_visual_scale())


func _is_pointer_down() -> bool:
	return (Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT) != 0


func _setup_ghost_line_style() -> void:
	if _ghost_line == null:
		return
	_ghost_line.width = 4.0
	_ghost_line.antialiased = true
	_ghost_line.default_color = Color(0.0, 0.95, 0.996, 0.96)
	var g := Gradient.new()
	g.add_point(0.0, Color(0.0, 0.95, 0.996, 0.98))
	g.add_point(1.0, Color(0.0, 0.95, 0.996, 0.0))
	_ghost_line.gradient = g
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for x in range(16):
		var on := x < 9
		img.set_pixel(x, 0, Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0))
	var tex := ImageTexture.create_from_image(img)
	_ghost_line.texture = tex
	_ghost_line.texture_mode = Line2D.LINE_TEXTURE_TILE


func _setup_screen_safe_container() -> void:
	var parent := get_parent()
	if parent == null:
		return
	_left_wall = _make_boundary_body("LeftWall", parent, "screen_wall")
	_right_wall = _make_boundary_body("RightWall", parent, "screen_wall")
	_kill_floor = _make_boundary_body("KillFloor", parent, "screen_kill_zone")
	collision_mask = 8


func _make_boundary_body(name: String, parent: Node, group_name: String) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.name = name
	b.collision_layer = 8
	b.collision_mask = 0
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


func _update_screen_safe_container() -> void:
	if _left_wall == null or _right_wall == null or _kill_floor == null:
		return
	var rect := get_viewport().get_visible_rect()
	var left_w := _screen_to_world(Vector2(0.0, rect.size.y * 0.5)).x
	var right_w := _screen_to_world(Vector2(rect.size.x, rect.size.y * 0.5)).x
	var floor_y := global_position.y + 500.0
	var left_shape := (_left_wall.get_child(0) as CollisionShape2D).shape as WorldBoundaryShape2D
	var right_shape := (_right_wall.get_child(0) as CollisionShape2D).shape as WorldBoundaryShape2D
	var floor_shape := (_kill_floor.get_child(0) as CollisionShape2D).shape as WorldBoundaryShape2D
	if left_shape != null:
		left_shape.plane = Plane(Vector3(1.0, 0.0, 0.0), left_w)
	if right_shape != null:
		right_shape.plane = Plane(Vector3(-1.0, 0.0, 0.0), -right_w)
	if floor_shape != null:
		floor_shape.plane = Plane(Vector3(0.0, -1.0, 0.0), -floor_y)


func _handle_air_collision(col: KinematicCollision2D) -> bool:
	if col == null:
		return false
	var collider := col.get_collider()
	if collider is Node:
		var n := collider as Node
		if n.is_in_group("screen_wall"):
			velocity.x = -velocity.x
			return true
		if n.is_in_group("screen_kill_zone"):
			_last_fail_reason = "kill_zone"
			die()
			return true
	return false
