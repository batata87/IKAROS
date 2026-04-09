extends Control
## Title screen polish to better match web look-and-feel.

@export var orbit_speed: float = 0.92
@export var orbit_radius: float = 28.0

var _phase: float = 0.0
var _title: Label
var _box: VBoxContainer
var _vault: Button
var _tap: Label
var _lux_hint: Label
var _build_stamp: Label
var _tap_tween: Tween


func _ready() -> void:
	_title = get_node_or_null("Center/VBox/Title") as Label
	_box = get_node_or_null("Center/VBox") as VBoxContainer
	_vault = get_node_or_null("Center/VBox/BtnVault") as Button
	var btn_play := get_node_or_null("Center/VBox/BtnPlay") as Button
	if btn_play:
		btn_play.visible = false
	if _box and _title:
		_tap = Label.new()
		_tap.name = "TapHint"
		_tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tap.add_theme_color_override("font_color", Color(0.0, 0.98, 0.9, 0.93))
		_tap.text = "Tap to ascend"
		_tap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_box.add_child(_tap)
		_box.move_child(_tap, _box.get_child_count() - 2)
		_lux_hint = Label.new()
		_lux_hint.name = "LuxHint"
		_lux_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lux_hint.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78, 0.9))
		_lux_hint.text = "Collect golden LUX between the stars"
		_lux_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_lux_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(_lux_hint)
		_box.move_child(_lux_hint, _box.get_child_count() - 2)
		_start_tap_pulse()
	_build_stamp = Label.new()
	_build_stamp.name = "BuildStamp"
	_build_stamp.anchors_preset = PRESET_BOTTOM_LEFT
	_build_stamp.anchor_top = 1.0
	_build_stamp.anchor_bottom = 1.0
	_build_stamp.offset_left = 12.0
	_build_stamp.offset_top = -28.0
	_build_stamp.offset_right = 290.0
	_build_stamp.offset_bottom = -8.0
	_build_stamp.add_theme_font_size_override("font_size", 12)
	_build_stamp.add_theme_color_override("font_color", Color(0.55, 0.65, 0.72, 0.92))
	add_child(_build_stamp)
	_load_build_stamp()
	_apply_responsive_layout()
	set_process(true)


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _draw() -> void:
	_draw_menu_vignette()
	if _title == null or not _title.visible:
		return
	var center := _title.position + _title.size * 0.5
	var dot_center := center + Vector2(cos(_phase * orbit_speed), sin(_phase * orbit_speed) * 0.58) * orbit_radius
	draw_circle(dot_center, 6.0, Color(1.0, 0.22, 0.9, 0.98))
	draw_circle(dot_center, 11.0, Color(1.0, 0.0, 0.8, 0.25))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_responsive_layout()


func _draw_menu_vignette() -> void:
	var size := get_viewport_rect().size
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var center := size * 0.5
	var max_r := size.length() * 0.62
	for i in range(6):
		var t := float(i) / 5.0
		var r := lerpf(max_r * 0.2, max_r, t)
		var a := lerpf(0.1, 0.0, t)
		draw_circle(center, r, Color(0.18, 0.5, 0.45, a))
	# baseline dark veil keeps OLED-like deep blacks.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.16), true)


func _start_tap_pulse() -> void:
	if _tap == null:
		return
	if _tap_tween and _tap_tween.is_valid():
		_tap_tween.kill()
	_tap.scale = Vector2.ONE
	_tap.modulate.a = 0.84
	_tap_tween = create_tween()
	_tap_tween.set_loops()
	_tap_tween.tween_property(_tap, "scale", Vector2(1.05, 1.05), 0.95)
	_tap_tween.parallel().tween_property(_tap, "modulate:a", 1.0, 0.95)
	_tap_tween.tween_property(_tap, "scale", Vector2.ONE, 0.95)
	_tap_tween.parallel().tween_property(_tap, "modulate:a", 0.78, 0.95)


func _apply_responsive_layout() -> void:
	var size := get_viewport_rect().size
	if size.x <= 1.0 or _title == null or _box == null or _tap == null or _lux_hint == null:
		return
	var available_w := maxf(220.0, size.x - 88.0)
	var title_size := clampi(int(size.x * 0.165), 56, 102)
	var tap_size := clampi(int(float(title_size) * 0.44), 28, 44)
	var hint_size := clampi(int(float(title_size) * 0.28), 16, 26)
	_title.add_theme_font_size_override("font_size", title_size)
	_tap.add_theme_font_size_override("font_size", tap_size)
	_lux_hint.add_theme_font_size_override("font_size", hint_size)
	_title.custom_minimum_size.x = available_w
	_tap.custom_minimum_size.x = available_w
	_lux_hint.custom_minimum_size.x = available_w
	_box.add_theme_constant_override("separation", clampi(int(size.y * 0.06), 42, 72))
	_box.custom_minimum_size.x = available_w
	_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if _vault:
		_vault.custom_minimum_size = Vector2(minf(available_w, 340.0), 62.0)


func _load_build_stamp() -> void:
	if _build_stamp == null:
		return
	var p := "res://build/build_info.txt"
	if not FileAccess.file_exists(p):
		_build_stamp.text = "build: dev"
		return
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		_build_stamp.text = "build: dev"
		return
	var txt := f.get_as_text().strip_edges()
	f.close()
	_build_stamp.text = txt if txt != "" else "build: dev"
