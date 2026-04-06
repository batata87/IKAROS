extends ColorRect
## Fullscreen chromatic pass; strength follows player speed (orbit tangent or dash).

@export var max_aberration: float = 0.012
@export var speed_ref: float = 880.0


func _process(_delta: float) -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	var p := get_tree().get_first_node_in_group("player")
	var spd: float = 0.0
	if p != null and p.has_method("get_overdrive_speed_hint"):
		spd = float(p.call("get_overdrive_speed_hint"))
	var t: float = clampf(spd / speed_ref, 0.0, 1.0)
	mat.set_shader_parameter("aberration_strength", max_aberration * t)
