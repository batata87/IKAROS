class_name NeonAnchor
extends Node2D

signal countdown_finished(anchor: NeonAnchor)

@export var capture_radius: float = 112.0
@export var visual_radius: float = 42.0
@export var orbit_radius: float = 88.0
@export var rotation_speed: float = 1.5
@export var countdown_sec: float = 4.0
@export var ring_color: Color = Color(0.0, 0.95, 0.996, 0.95)
@export var core_color: Color = Color(0.0, 0.95, 0.996, 0.25)

var _remaining_sec: float = 0.0
var _active: bool = false
var _expiring: bool = false
var _pulse_tween: Tween


func _ready() -> void:
	add_to_group("anchors")
	ItemDatabase.equipped_changed.connect(_on_equipped_theme)
	var c := ItemDatabase.peek_equipped_theme()
	_on_equipped_theme(c[0], c[1], c[2], c[3])
	queue_redraw()


func _process(delta: float) -> void:
	if not _active or _expiring:
		return
	_remaining_sec = maxf(0.0, _remaining_sec - delta)
	queue_redraw()
	if _remaining_sec <= 0.0:
		countdown_finished.emit(self)
		_expire_with_pop()


func _draw() -> void:
	var timer_t := 0.0 if countdown_sec <= 0.0 else clampf(_remaining_sec / countdown_sec, 0.0, 1.0)
	draw_circle(Vector2.ZERO, visual_radius, core_color)
	draw_arc(Vector2.ZERO, visual_radius, 0.0, TAU, 64, ring_color, 4.0, true)
	if _active:
		draw_arc(
			Vector2.ZERO,
			visual_radius + 9.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * timer_t,
			48,
			Color(1.0, 0.82, 0.2, 0.95),
			3.0,
			true
		)


func _on_equipped_theme(_pf: Color, _pr: Color, ar: Color, ac: Color) -> void:
	ring_color = ar
	core_color = ac
	queue_redraw()


func apply_difficulty(score: int) -> void:
	var t := clampf(float(score) / 700.0, 0.0, 1.0)
	rotation_speed = lerpf(1.2, 2.2, t)
	orbit_radius = lerpf(92.0, 70.0, t)
	capture_radius = orbit_radius + 24.0
	visual_radius = orbit_radius * 0.5
	queue_redraw()


func play_capture_squash() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	scale = Vector2.ONE
	_pulse_tween.tween_property(self, "scale", Vector2(1.15, 0.86), 0.05)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, 0.1)


func contains_point_global(p: Vector2) -> bool:
	return p.distance_to(global_position) <= capture_radius


func set_active_orbit_anchor(active: bool) -> void:
	_active = active
	if _active:
		_remaining_sec = countdown_sec
	queue_redraw()


func set_target_reachable(_reachable: bool) -> void:
	pass


func _expire_with_pop() -> void:
	if _expiring:
		return
	_expiring = true
	set_process(false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 0.85), 0.04)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.08)
	tw.tween_property(self, "scale", Vector2(0.02, 0.02), 0.06)
	tw.finished.connect(func() -> void:
		queue_free()
	)
