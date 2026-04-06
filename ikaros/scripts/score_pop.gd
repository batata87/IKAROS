extends Node2D
## Floating +1 / combo text after anchor capture.

@onready var _lbl: Label = $Label


func start(text: String, combo_gold: bool) -> void:
	if _lbl == null:
		return
	_lbl.text = text
	if combo_gold:
		_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25, 1.0))
		_lbl.add_theme_color_override("font_outline_color", Color(1.0, 0.45, 0.1, 0.95))
	else:
		_lbl.add_theme_color_override("font_color", Color(0.85, 1.0, 1.0, 1.0))
		_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.6, 0.85, 0.9))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position:y", global_position.y - 96.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_lbl, "modulate:a", 0.0, 0.85).set_delay(0.2)
	tw.chain().tween_callback(queue_free)
