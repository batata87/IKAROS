extends CharacterBody2D
## Orbits current anchor; screen tap releases along orbit tangent; dash captures new anchors.
## Arcade Overdrive: centrifugal launch charge, coyote emergency dash, camera zoom, score pops.

const SCORE_POP := preload("res://scenes/ScorePop.tscn")
const COYOTE_BURST := preload("res://scenes/CoyoteBurst.tscn")

const MAX_CENTRIFUGAL_REVS: int = 8
const CENTRIFUGAL_MULT_PER_REV: float = 0.25
const MAX_LAUNCH_MULT: float = 3.0

@export var dash_speed: float = 620.0
@export var max_offworld: float = 5200.0
@export var ghost_length: float = 220.0
@export var zoom_tight: float = 0.92
@export var zoom_wide: float = 0.68
@export var zoom_speed_ref: float = 920.0

var _anchor: NeonAnchor = null
var _orbit_angle: float = 0.0
var _ghost_line: Line2D

@onready var trail_particles: GPUParticles2D = $TrailParticles
@onready var _cam: Camera2D = $Camera2D
@onready var _charge_blip: AudioStreamPlayer = $ChargeBlip
@onready var _charge_hum: AudioStreamPlayer = $ChargeHum

var _fill_color: Color = Color(1.0, 0.35, 1.0, 0.95)
var _ring_color: Color = Color(0.4, 1.0, 1.0, 0.9)

## Radians traveled on current anchor (for partial revolution visual + audio steps).
var _orbit_path_accum: float = 0.0
## Full 2π laps completed while on this anchor (capped).
var _centrifugal_revs: int = 0
var _vib_phase: float = 0.0

var _coyote_armed: bool = false
var _coyote_used: bool = false
var _hum_phase: float = 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 0
	_ghost_line = get_node_or_null("GhostLine") as Line2D
	if _charge_hum and _charge_hum.stream == null:
		var g := AudioStreamGenerator.new()
		g.mix_rate = 24000.0
		_charge_hum.stream = g
		_charge_hum.volume_db = -24.0
	ItemDatabase.equipped_changed.connect(_on_equipped_theme)
	var c: Array = ItemDatabase.peek_equipped_theme()
	_on_equipped_theme(c[0], c[1], c[2], c[3])
	queue_redraw()


func _on_equipped_theme(pf: Color, pr: Color, _ar: Color, _ac: Color) -> void:
	_fill_color = pf
	_ring_color = pr
	if trail_particles and trail_particles.process_material is ParticleProcessMaterial:
		var pm := trail_particles.process_material as ParticleProcessMaterial
		pm.color = Color(pr.r, pr.g, pr.b, 0.55)
	queue_redraw()


func get_overdrive_speed_hint() -> float:
	if GameManager.state == GameManager.GameState.GAMEOVER:
		return 0.0
	if GameManager.state == GameManager.GameState.DASHING:
		return velocity.length()
	if GameManager.state == GameManager.GameState.ORBITING and _anchor != null and is_instance_valid(_anchor):
		return absf(_anchor.rotation_speed * _anchor.orbit_radius)
	return 0.0


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
	_attach_to_initial_anchor()


func _physics_process(delta: float) -> void:
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
			_update_ghost()
			_update_charge_audio()
		GameManager.GameState.DASHING:
			_physics_dash(delta)
			if _charge_hum and _charge_hum.playing:
				_charge_hum.stop()
		_:
			velocity = Vector2.ZERO
			if _ghost_line:
				_ghost_line.clear_points()
			if _charge_hum and _charge_hum.playing:
				_charge_hum.stop()
	_update_camera_zoom(delta)
	queue_redraw()


func _update_camera_zoom(delta: float) -> void:
	if _cam == null:
		return
	var spd := get_overdrive_speed_hint()
	var t := clampf(spd / zoom_speed_ref, 0.0, 1.0)
	var z_tgt := lerpf(zoom_tight, zoom_wide, t)
	var zz := lerpf(_cam.zoom.x, z_tgt, 1.0 - exp(-4.2 * delta))
	_cam.zoom = Vector2(zz, zz)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_on_tap()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_tap()


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
	var lg := get_parent().get_node_or_null("LevelGenerator") as NeonLevelGenerator
	if lg == null or lg.get_child_count() == 0:
		push_warning("Neon Pivot: LevelGenerator has no anchors yet.")
		return
	_anchor = lg.get_child(0) as NeonAnchor
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
	global_position = _anchor.global_position + Vector2(_anchor.orbit_radius, 0.0).rotated(_orbit_angle)


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
	var t_orbit := GameManager.get_time_in_current_orbit()
	GameManager.on_dash_started(t_orbit)
	var tangent := Vector2.RIGHT.rotated(_orbit_angle + PI * 0.5).normalized()
	var mult := _centrifugal_launch_mult()
	velocity = tangent * dash_speed * mult
	_reset_centrifugal()
	_anchor = null
	_coyote_used = false
	_coyote_armed = velocity.y > 0.0
	GameManager.set_game_state(GameManager.GameState.DASHING)
	if trail_particles:
		trail_particles.emitting = true


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
	_orbit_angle = (global_position - a.global_position).angle()
	global_position = a.global_position + Vector2(a.orbit_radius, 0.0).rotated(_orbit_angle)
	GameManager.on_anchor_captured(1)
	GameManager.set_game_state(GameManager.GameState.ORBITING)
	_reset_centrifugal()
	_coyote_armed = false
	_coyote_used = false
	a.play_capture_squash()
	if trail_particles:
		trail_particles.emitting = true
	var lg := get_parent().get_node_or_null("LevelGenerator") as NeonLevelGenerator
	if lg:
		lg.update_forward_hint(prev_pos, global_position)
	_spawn_score_pop(prev_pos, pts, combo_style)


func _update_ghost() -> void:
	if _ghost_line == null or _anchor == null:
		return
	var tangent := Vector2.RIGHT.rotated(_orbit_angle + PI * 0.5).normalized()
	_ghost_line.clear_points()
	_ghost_line.add_point(Vector2.ZERO)
	_ghost_line.add_point(tangent * ghost_length * _draw_visual_scale())
