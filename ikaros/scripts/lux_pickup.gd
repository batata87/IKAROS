class_name LuxPickup
extends Node2D
## Small LUX collectible spawned between anchors; touch = balance + chime.

@export var pickup_radius: float = 22.0
@export var value: int = 1


func _physics_process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p == null:
		return
	if global_position.distance_to(p.global_position) <= pickup_radius * 1.2:
		CurrencyManager.add_lux(value)
		CurrencyManager.play_lux_pickup_chime()
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.5, Color(1.0, 1.0, 0.92, 0.98))
	draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 28, Color(1.0, 0.95, 0.55, 0.55), 2.2, true)
