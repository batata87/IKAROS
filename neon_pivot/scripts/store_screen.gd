extends Control
## The Vault: skins list + mock IAP. Emits vault_closed when dismissed.

signal vault_closed

@onready var _lux_label: Label = $Margin/VBox/LuxRow/LuxLabel
@onready var _item_list: VBoxContainer = $Margin/VBox/Scroll/ItemList


func _ready() -> void:
	visible = false
	CurrencyManager.lux_changed.connect(_on_lux_changed)
	ItemDatabase.equipped_changed.connect(_on_equipped_changed)
	_on_lux_changed(CurrencyManager.lux)


func open_vault() -> void:
	visible = true
	_rebuild_list()
	_on_lux_changed(CurrencyManager.lux)


func _on_back() -> void:
	visible = false
	vault_closed.emit()


func _on_lux_changed(balance: int) -> void:
	_lux_label.text = "LUX: %d" % balance


func _on_equipped_changed(_a, _b, _c, _d) -> void:
	if visible:
		_rebuild_list()


func _rebuild_list() -> void:
	for c in _item_list.get_children():
		c.queue_free()
	for raw in ItemDatabase.get_items():
		if not raw is Dictionary:
			continue
		var it: Dictionary = raw
		if str(it.get("category", "")) != "skin":
			continue
		_item_list.add_child(_make_skin_row(it))


func _make_skin_row(it: Dictionary) -> Control:
	var id: String = str(it.get("id", ""))
	var name_str: String = str(it.get("name", id))
	var price: int = int(it.get("price", 0))

	var row := MarginContainer.new()
	row.add_theme_constant_override("margin_top", 4)
	row.add_theme_constant_override("margin_bottom", 4)

	var panel := PanelContainer.new()
	row.add_child(panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)

	var lbl := Label.new()
	lbl.text = "%s\n%d LUX" % [name_str, price] if price > 0 else "%s\nFree" % name_str
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(lbl)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 44)
	btn.focus_mode = Control.FOCUS_NONE

	var equipped: bool = ItemDatabase.equipped_id == id
	var unlocked: bool = ItemDatabase.is_unlocked(id)
	var bal: int = CurrencyManager.lux

	if equipped:
		btn.text = "EQUIPPED"
		btn.disabled = true
	elif unlocked:
		btn.text = "EQUIP"
		btn.disabled = false
		btn.pressed.connect(func() -> void:
			ItemDatabase.equip(id)
			_rebuild_list()
		)
	elif price <= 0:
		btn.text = "BUY"
		btn.pressed.connect(func() -> void:
			ItemDatabase.try_buy_skin(id)
			_rebuild_list()
		)
	elif bal >= price:
		btn.text = "BUY"
		btn.pressed.connect(func() -> void:
			ItemDatabase.try_buy_skin(id)
			_rebuild_list()
		)
	else:
		btn.text = "BUY"
		btn.disabled = true
		btn.tooltip_text = "Need %d LUX" % price

	h.add_child(btn)
	return row


func _on_iap_099() -> void:
	print("Initiating IAP...")


func _on_iap_499() -> void:
	print("Initiating IAP...")


func _on_iap_999() -> void:
	print("Initiating IAP...")
