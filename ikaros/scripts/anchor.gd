class_name NeonAnchor
extends Node2D
## Static anchor: visual ring + capture radius. Difficulty scaled by LevelGenerator.

@export var capture_radius: float = 110.0
@export var visual_radius: float = 48.0
@export var orbit_radius: float = 90.0
@export var rotation_speed: float = 1.2
@export var ring_color: Color = Color(0.0, 1.0, 1.0, 0.85)
@export var core_color: Color = Color(1.0, 0.0, 1.0, 0.35)

var _pulse_tween: Tween


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
	draw_arc(Vector2.ZERO, visual_radius, 0.0, TAU, 64, ring_color, 3.0, true)
	draw_circle(Vector2.ZERO, visual_radius * 0.12, core_color)


func apply_difficulty(score: int) -> void:
	var t: float = clamp(float(score) / 500.0, 0.0, 1.0)
	orbit_radius = lerpf(95.0, 55.0, t)
	capture_radius = orbit_radius + 28.0
	rotation_speed = lerpf(1.0, 2.6, t)


func play_capture_squash() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	scale = Vector2.ONE
	_pulse_tween.tween_property(self, "scale", Vector2(1.18, 0.82), 0.06)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, 0.12)


func contains_point_global(p: Vector2) -> bool:
	return p.distance_to(global_position) <= capture_radius
