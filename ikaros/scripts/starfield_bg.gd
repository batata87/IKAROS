extends Node2D
## Lightweight procedural starfield with score-based tint progression.

@export var star_count: int = 180
@export var spread: Vector2 = Vector2(2200.0, 3400.0)
@export var near_color: Color = Color(0.62, 0.88, 1.0, 0.95)
@export var far_color: Color = Color(0.95, 0.75, 1.0, 0.75)
@export var deep_space_color: Color = Color(0.03, 0.03, 0.08, 1.0)
@export var mid_space_color: Color = Color(0.02, 0.01, 0.12, 1.0)
@export var high_space_color: Color = Color(0.00, 0.00, 0.03, 1.0)

var _stars: PackedVector2Array = PackedVector2Array()
var _radii: PackedFloat32Array = PackedFloat32Array()
var _phase: float = 0.0
var _score_t: float = 0.0


func _ready() -> void:
	z_index = -50
	_generate_stars()
	GameManager.score_changed.connect(_on_score_changed)
	_on_score_changed(GameManager.score)
	set_process(true)


func _process(delta: float) -> void:
	_phase += delta * 0.9
	queue_redraw()


func _draw() -> void:
	var bg := deep_space_color.lerp(mid_space_color, _score_t).lerp(high_space_color, _score_t * 0.65)
	draw_rect(Rect2(Vector2(-2500.0, -4000.0), Vector2(5000.0, 8000.0)), bg, true)
	for i in range(_stars.size()):
		var p := _stars[i]
		var tw := 0.68 + 0.32 * sin(_phase * (0.7 + float(i % 5) * 0.21) + float(i) * 0.17)
		var c := near_color.lerp(far_color, float(i % 7) / 6.0)
		c.a *= tw
		draw_circle(p, _radii[i], c)


func _generate_stars() -> void:
	_stars.resize(star_count)
	_radii.resize(star_count)
	for i in range(star_count):
		var p := Vector2(
			randf_range(-spread.x * 0.5, spread.x * 0.5),
			randf_range(-spread.y * 0.5, spread.y * 0.5)
		)
		_stars[i] = p
		_radii[i] = randf_range(0.8, 2.0)


func _on_score_changed(score: int) -> void:
	_score_t = clampf(float(score) / 80.0, 0.0, 1.0)
