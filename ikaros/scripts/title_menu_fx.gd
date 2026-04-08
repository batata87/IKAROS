extends Control
## Title screen polish to better match web look-and-feel.

@export var orbit_speed: float = 0.92
@export var orbit_radius: float = 28.0

var _phase: float = 0.0
var _title: Label
var _tap: Label
var _lux_hint: Label


func _ready() -> void:
	_title = get_node_or_null("Center/VBox/Title") as Label
	var btn_play := get_node_or_null("Center/VBox/BtnPlay") as Button
	if btn_play:
		btn_play.visible = false
	var box := get_node_or_null("Center/VBox") as VBoxContainer
	if box and _title:
		_tap = Label.new()
		_tap.name = "TapHint"
		_tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tap.add_theme_color_override("font_color", Color(0.0, 1.0, 0.97, 0.78))
		_tap.add_theme_font_size_override("font_size", 36)
		_tap.text = "Tap to ascend"
		box.add_child(_tap)
		box.move_child(_tap, box.get_child_count() - 2)
		_lux_hint = Label.new()
		_lux_hint.name = "LuxHint"
		_lux_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lux_hint.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55, 0.8))
		_lux_hint.add_theme_font_size_override("font_size", 22)
		_lux_hint.text = "Collect golden LUX between the stars"
		box.add_child(_lux_hint)
		box.move_child(_lux_hint, box.get_child_count() - 2)
	set_process(true)


func _process(delta: float) -> void:
	_phase += delta
	if _tap:
		var a := 0.58 + 0.36 * (0.5 + 0.5 * sin(_phase * 1.5))
		_tap.modulate.a = a
	queue_redraw()


func _draw() -> void:
	if _title == null or not _title.visible:
		return
	var center := _title.position + _title.size * 0.5
	var dot_center := center + Vector2(cos(_phase * orbit_speed), sin(_phase * orbit_speed) * 0.58) * orbit_radius
	draw_circle(dot_center, 6.0, Color(1.0, 0.22, 0.9, 0.98))
	draw_circle(dot_center, 11.0, Color(1.0, 0.0, 0.8, 0.25))
