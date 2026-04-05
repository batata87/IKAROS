extends Node
## Desktop: taskbar / window icon follows OS light vs dark. Mobile launcher uses Project Settings icon (light as default).

const PATH_LIGHT := "res://icons/app_icon_light.png"
const PATH_DARK := "res://icons/app_icon_dark.png"


func _ready() -> void:
	if DisplayServer.has_signal("theme_changed"):
		DisplayServer.theme_changed.connect(apply_window_icon)
	apply_window_icon()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_THEME_CHANGED:
		call_deferred("apply_window_icon")


func apply_window_icon() -> void:
	var path: String = PATH_LIGHT
	if DisplayServer.is_dark_mode_supported() and DisplayServer.is_dark_mode():
		path = PATH_DARK
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		push_warning("AppIconTheme: could not load %s" % path)
		return
	var img: Image = tex.get_image()
	if img == null:
		return
	DisplayServer.set_icon(img)
