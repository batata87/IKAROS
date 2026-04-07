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

	# iOS launch storyboard images (explicit 2x/3x) — procedural fallback.
	_save_png(_scaled_copy(base_light, 2048), OUT_DIR + "/custom_image_2x.png")
	_save_png(_scaled_copy(base_light, 3072), OUT_DIR + "/custom_image_3x.png")
	_save_png(_scaled_copy(base_light, 2048), OUT_DIR + "/launch_image_2x.png")
	_save_png(_scaled_copy(base_light, 3072), OUT_DIR + "/launch_image_3x.png")

	var storyboard_note := ""
	if _export_storyboard_from_netlify_splash():
		storyboard_note = "Storyboard PNGs from res://assets/splash_loading.jpg or .png (Netlify art). "
	else:
		storyboard_note = "Storyboard PNGs from procedural icon (no usable splash_loading.jpg/.png). "

	get_editor_interface().get_resource_filesystem().scan()
	print(
		storyboard_note,
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


## If splash art exists (same as Netlify), use it for iOS storyboard slots.
## Supports `.jpg` or `.png` (some exports accidentally save JPEG bytes with a `.png` name).
func _export_storyboard_from_netlify_splash() -> bool:
	for res_path in ["res://assets/splash_loading.jpg", "res://assets/splash_loading.png"]:
		var img := _load_splash_image(res_path)
		if img != null:
			_write_storyboard_sizes(img)
			return true
	push_warning(
		"IKAROS: No usable splash at res://assets/splash_loading.jpg (or .png). "
		+ "If you see 'Not a PNG', the file may be JPEG — use .jpg extension or a real PNG."
	)
	return false


func _write_storyboard_sizes(img: Image) -> void:
	var i2 := img.duplicate()
	i2.resize(828, 1792, Image.INTERPOLATE_LANCZOS)
	_save_png(i2, OUT_DIR + "/custom_image_2x.png")
	_save_png(i2, OUT_DIR + "/launch_image_2x.png")
	_save_png(i2, OUT_DIR + "/storyboard_custom_2x.png")
	var i3 := img.duplicate()
	i3.resize(1242, 2688, Image.INTERPOLATE_LANCZOS)
	_save_png(i3, OUT_DIR + "/custom_image_3x.png")
	_save_png(i3, OUT_DIR + "/launch_image_3x.png")
	_save_png(i3, OUT_DIR + "/storyboard_custom_3x.png")


func _load_splash_image(res_path: String) -> Image:
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	if ResourceLoader.exists(res_path):
		var res: Resource = ResourceLoader.load(res_path)
		if res is Texture2D:
			var tex := res as Texture2D
			var im := tex.get_image()
			if im != null:
				return im.duplicate()
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return null
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 12:
		return null
	var img := Image.new()
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		if img.load_png_from_buffer(bytes) == OK:
			return img
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		if img.load_jpg_from_buffer(bytes) == OK:
			return img
	push_warning("IKAROS: Could not decode splash bytes for %s (use PNG or JPEG)" % res_path)
	return null


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
