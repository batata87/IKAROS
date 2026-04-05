extends Node
## Main-menu feedback → Netlify Forms (AJAX-style POST). Set `netlify_form_url` in the inspector.

## Deploy root URL of the Netlify site (usually ends with /), same origin as your published game.
@export var netlify_form_url: String = ""

const FORM_NAME := "ikaros-feedback"

@onready var _http: HTTPRequest = $HTTPRequest
@onready var _menu: Control = get_node("../CanvasLayer/MainMenu")

var _btn: Button
var _modal: Control
var _name_edit: LineEdit
var _msg_edit: TextEdit
var _submit: Button
var _close: Button
var _status: Label


func _ready() -> void:
	_btn = _menu.get_node("BtnFeedback") as Button
	_modal = _menu.get_node("FeedbackModal") as Control
	var vb := _modal.get_node("Center/Panel/Margin/VBox")
	_name_edit = vb.get_node("NameEdit") as LineEdit
	_msg_edit = vb.get_node("MessageEdit") as TextEdit
	_submit = vb.get_node("SubmitBtn") as Button
	_close = vb.get_node("CloseBtn") as Button
	_status = vb.get_node("StatusLabel") as Label

	_btn.pressed.connect(_open_modal)
	_close.pressed.connect(_close_modal)
	_submit.pressed.connect(_on_submit)
	_http.request_completed.connect(_on_request_completed)

	var dim := _modal.get_node("Dim") as Control
	dim.gui_input.connect(_on_dim_gui_input)


func _open_modal() -> void:
	_modal.visible = true
	_status.text = ""
	_submit.disabled = false


func _close_modal() -> void:
	_modal.visible = false


func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_modal()


func _on_submit() -> void:
	var msg := _msg_edit.text.strip_edges()
	if msg.is_empty():
		_status.text = "Please enter a message."
		return

	var url := netlify_form_url.strip_edges()
	if url.is_empty():
		_status.text = "Set Netlify URL on FeedbackSystem node."
		return

	var name_s := _name_edit.text.strip_edges()
	var body := "form-name=%s&message=%s" % [FORM_NAME.uri_encode(), msg.uri_encode()]
	if not name_s.is_empty():
		body += "&name=%s" % name_s.uri_encode()

	var headers := PackedStringArray([
		"Content-Type: application/x-www-form-urlencoded",
	])

	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_status.text = "Could not start request."
		return

	_submit.disabled = true
	_status.text = "Sending..."


func _on_request_completed(_result: int, response_code: int, _response_headers: PackedStringArray, _body: PackedByteArray) -> void:
	_submit.disabled = false

	if _result != HTTPRequest.RESULT_SUCCESS:
		_status.text = "Network error."
		return

	if response_code >= 200 and response_code < 400:
		_status.text = "Thank you!"
		_msg_edit.text = ""
		_name_edit.text = ""
	else:
		_status.text = "Something went wrong (%d)." % response_code
