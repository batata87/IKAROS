class_name NeonAnchor
extends Node2D
## Static anchor: visual ring + capture radius. Difficulty scaled by LevelGenerator.
signal countdown_finished(anchor: NeonAnchor)

@export var capture_radius: float = 110.0
@export var visual_radius: float = 48.0
@export var orbit_radius: float = 90.0
@export var rotation_speed: float = 1.2
@export var shrink_enabled: bool = true
@export var countdown_sec: float = 4.6
@export var min_orbit_radius: float = 54.0
@export var danger_ring_color: Color = Color(1.0, 0.22, 0.22, 0.95)
@export var timer_ring_color: Color = Color(1.0, 0.9, 0.15, 0.95)
@export var ring_color: Color = Color(1.0, 0.0, 0.5, 0.9) # #FF007F-like
@export var core_color: Color = Color(1.0, 0.0, 0.5, 0.4)

var _pulse_tween: Tween
var _danger_tween: Tween
var _active_orbit_anchor: bool = false
var _active_start_orbit_radius: float = 90.0
var _target_reachable: bool = false
var _countdown_started: bool = false
var _remaining_sec: float = 4.6
var _danger_t: float = 0.0
var _expiring: bool = false


func _ready() -> void:
	add_to_group("anchors")
	ItemDatabase.equipped_changed.connect(_on_equipped_theme)
	var c: Array = ItemDatabase.peek_equipped_theme()
	_on_equipped_theme(c[0], c[1], c[2], c[3])
	queue_redraw()


func _on_equipped_theme(_player_fill: Color, _player_ring: Color, ar: Color, ac: Color) -> void:
	ring_color = ar
	core_color = ac
	queue_redraw()


func _draw() -> void:
	var remaining_t := clampf(_remaining_sec / maxf(countdown_sec, 0.001), 0.0, 1.0)
	var danger_t := 1.0 - remaining_t
	var ring_now: Color = ring_color
	if _active_orbit_anchor:
		ring_now = ring_color.lerp(danger_ring_color, maxf(danger_t, _danger_t))
	draw_arc(Vector2.ZERO, visual_radius, 0.0, TAU, 64, ring_now, 3.0, true)
	if _active_orbit_anchor:
		var timer_radius := visual_radius * 0.74
		var timer_span := TAU * remaining_t
		draw_arc(Vector2.ZERO, timer_radius, -PI * 0.5, -PI * 0.5 + timer_span, 48, timer_ring_color, 2.5, true)
	draw_circle(Vector2.ZERO, visual_radius * 0.12, core_color)


func _process(delta: float) -> void:
	if _expiring:
		return
	if not shrink_enabled or not _active_orbit_anchor:
		return
	if not _countdown_started and not _target_reachable:
		_stop_danger_tween()
		return
	_countdown_started = true
	_resume_danger_tween()
	_remaining_sec = maxf(0.0, _remaining_sec - delta)
	var progress := 1.0 - (_remaining_sec / maxf(countdown_sec, 0.001))
	var next_orbit := lerpf(_active_start_orbit_radius, min_orbit_radius, progress)
	if not is_equal_approx(next_orbit, orbit_radius):
		orbit_radius = next_orbit
		capture_radius = orbit_radius + 28.0
		visual_radius = orbit_radius * 0.52
	if _remaining_sec > 0.0:
		queue_redraw()
		return
	_stop_danger_tween()
	countdown_finished.emit(self)
	_expire_with_pop()


func _stop_danger_tween() -> void:
	if _danger_tween and _danger_tween.is_valid():
		_danger_tween.kill()


func _resume_danger_tween() -> void:
	if _danger_tween and _danger_tween.is_valid():
		return
	var rem_ratio := clampf(_remaining_sec / maxf(countdown_sec, 0.001), 0.0, 1.0)
	var rem := maxf(0.01, countdown_sec * rem_ratio)
	_danger_tween = create_tween()
	_danger_tween.tween_property(self, "_danger_t", 1.0, rem)


func _set_countdown_for_active_anchor() -> void:
	_remaining_sec = maxf(countdown_sec, 0.01)
	_danger_t = 0.0
	_target_reachable = false
	_countdown_started = false
	queue_redraw()


func apply_difficulty(score: int) -> void:
	var t: float = clamp(float(score) / 500.0, 0.0, 1.0)
	orbit_radius = lerpf(95.0, 55.0, t)
	capture_radius = orbit_radius + 28.0
	visual_radius = orbit_radius * 0.52
	rotation_speed = lerpf(1.0, 2.6, t)


func play_capture_squash() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	scale = Vector2.ONE
	_pulse_tween.tween_property(self, "scale", Vector2(1.18, 0.82), 0.06)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, 0.12)


func contains_point_global(p: Vector2) -> bool:
	return p.distance_to(global_position) <= capture_radius * 1.2


func set_active_orbit_anchor(active: bool) -> void:
	_active_orbit_anchor = active
	if active:
		_active_start_orbit_radius = maxf(orbit_radius, min_orbit_radius + 0.001)
		_set_countdown_for_active_anchor()
	else:
		_stop_danger_tween()
	queue_redraw()


func set_target_reachable(reachable: bool) -> void:
	_target_reachable = reachable


func _expire_with_pop() -> void:
	if _expiring:
		return
	_expiring = true
	rotation_speed = 0.0
	set_process(false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.18, 0.82), 0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.07)
	tw.tween_property(self, "scale", Vector2(0.02, 0.02), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.finished.connect(func() -> void:
		queue_free()
	)
