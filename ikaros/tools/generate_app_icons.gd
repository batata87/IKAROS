@tool
extends EditorScript
## Run once from the script editor (File → Run): creates res://icons/*.png.
## PNG-only pipeline for iOS icons and storyboard launch images.

const OUT_DIR := "res://icons"


func _run() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	# Generate only two master images, then resize copies.
	# (Huge direct renders like 3072*4 can freeze the editor.)
	var base_light := _raster_icon(1024, false)
	var base_dark := _raster_icon(1024, true)

	# App icon base files.
	_save_png(base_light, OUT_DIR + "/app_icon_light.png")
	_save_png(base_dark, OUT_DIR + "/app_icon_dark.png")

	# iOS export field-friendly names (Icons section).
	_save_png(base_light, OUT_DIR + "/icon_1024x1024.png")
	_save_png(base_dark, OUT_DIR + "/icon_1024x1024_dark.png")
	_save_png(base_light, OUT_DIR + "/icon_1024x1024_tinted.png")
	_save_png(base_light, OUT_DIR + "/app_store_1024x1024.png")
	_save_png(base_dark, OUT_DIR + "/app_store_1024x1024_dark.png")
	_save_png(base_light, OUT_DIR + "/app_store_1024x1024_tinted.png")

	# Required small settings icon slot.
	_save_png(_scaled_copy(base_light, 58), OUT_DIR + "/settings_58x58.png")
	_save_png(_scaled_copy(base_light, 58), OUT_DIR + "/ios_settings_58.png")

	# iOS launch storyboard images (explicit 2x/3x).
	_save_png(_scaled_copy(base_light, 2048), OUT_DIR + "/custom_image_2x.png")
	_save_png(_scaled_copy(base_light, 3072), OUT_DIR + "/custom_image_3x.png")
	_save_png(_scaled_copy(base_light, 2048), OUT_DIR + "/launch_image_2x.png")
	_save_png(_scaled_copy(base_light, 3072), OUT_DIR + "/launch_image_3x.png")

	get_editor_interface().get_resource_filesystem().scan()
	print(
		"App assets written to ", OUT_DIR,
		" — iOS export mapping: ",
		"Icon 1024x1024=res://icons/icon_1024x1024.png, ",
		"Icon 1024x1024 Dark=res://icons/icon_1024x1024_dark.png, ",
		"Icon 1024x1024 Tinted=res://icons/icon_1024x1024_tinted.png, ",
		"App Store 1024x1024=res://icons/app_store_1024x1024.png, ",
		"App Store 1024x1024 Dark=res://icons/app_store_1024x1024_dark.png, ",
		"App Store 1024x1024 Tinted=res://icons/app_store_1024x1024_tinted.png, ",
		"settings_58x58=res://icons/settings_58x58.png, ",
		"storyboard/custom_image@2x=res://icons/custom_image_2x.png, ",
		"storyboard/custom_image@3x=res://icons/custom_image_3x.png"
	)


func _save_png(img: Image, res_path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(res_path))
	if err != OK:
		push_error("save_png failed %s: %s" % [res_path, str(err)])


func _scaled_copy(src: Image, size: int) -> Image:
	var out := src.duplicate()
	out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return out


func _raster_icon(size: int, dark: bool) -> Image:
	# Supersample then downscale for smoother icon edges on iOS.
	var ss := 4
	var work_size := size * ss
	var img := Image.create(work_size, work_size, false, Image.FORMAT_RGBA8)
	var bg := Color(0.05, 0.05, 0.08, 1.0) if dark else Color.BLACK
	img.fill(bg)

	var s := float(work_size)
	var cx := 0.5 * s
	var cy := 0.5 * s
	var r_ring := 36.0 / 128.0 * s
	var stroke := maxf(1.0, 4.0 / 128.0 * s) * 0.5
	var ring_col := Color(0.0, 0.75, 0.75, 1.0) if dark else Color(0.0, 1.0, 1.0, 1.0)
	var dot_cx := 92.0 / 128.0 * s
	var dot_r := 10.0 / 128.0 * s
	var dot_col := Color(0.85, 0.0, 0.85, 1.0) if dark else Color(1.0, 0.0, 1.0, 1.0)

	for y in work_size:
		for x in work_size:
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var dx := px - cx
			var dy := py - cy
			var d := sqrt(dx * dx + dy * dy)
			if absf(d - r_ring) <= stroke:
				img.set_pixel(x, y, ring_col)
				continue
			var dx2 := px - dot_cx
			var dy2 := py - cy
			if dx2 * dx2 + dy2 * dy2 <= dot_r * dot_r:
				img.set_pixel(x, y, dot_col)

	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return img
