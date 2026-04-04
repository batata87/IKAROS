extends GPUParticles2D
## One-shot pink burst for emergency dash.


func _ready() -> void:
	one_shot = true
	finished.connect(queue_free)
	restart()
