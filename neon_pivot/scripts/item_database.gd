extends Node
## Autoload: static item defs from res://data/items.json + user unlock / equip (user://).

signal equipped_changed(
	player_fill: Color,
	player_ring: Color,
	anchor_ring: Color,
	anchor_core: Color,
)

const ITEMS_JSON := "res://data/items.json"
const USER_PATH := "user://vault_items.cfg"
const SEC := "vault"
const KEY_UNLOCKED := "unlocked_ids"
const KEY_EQUIPPED := "equipped_id"

var _items: Array = []
## id -> bool
var _unlocked: Dictionary = {}
var equipped_id: String = "skin_default"


func _ready() -> void:
	_load_json()
	_load_user()
	_apply_equipped_theme()


func _load_json() -> void:
	var f := FileAccess.open(ITEMS_JSON, FileAccess.READ)
	if f == null:
		push_error("ItemDatabase: missing %s" % ITEMS_JSON)
		return
	var txt := f.get_as_text()
	var data = JSON.parse_string(txt)
	if data == null or not data is Array:
		push_error("ItemDatabase: invalid JSON")
		return
	_items = data


func _load_user() -> void:
	var cf := ConfigFile.new()
	if cf.load(USER_PATH) != OK:
		_seed_defaults()
		return
	var raw: Variant = cf.get_value(SEC, KEY_UNLOCKED, [])
	if raw is PackedStringArray:
		for id in raw:
			_unlocked[str(id)] = true
	elif raw is Array:
		for id in raw:
			_unlocked[str(id)] = true
	equipped_id = str(cf.get_value(SEC, KEY_EQUIPPED, "skin_default"))
	if not is_unlocked(equipped_id):
		equipped_id = "skin_default"


func _seed_defaults() -> void:
	for it in _items:
		if not it is Dictionary:
			continue
		var id: String = str(it.get("id", ""))
		if bool(it.get("unlocked_default", false)):
			_unlocked[id] = true
	equipped_id = "skin_default"
	save_user()


func save_user() -> void:
	var cf := ConfigFile.new()
	cf.load(USER_PATH)
	var ids: PackedStringArray = PackedStringArray()
	for k in _unlocked.keys():
		if _unlocked[k]:
			ids.append(str(k))
	cf.set_value(SEC, KEY_UNLOCKED, ids)
	cf.set_value(SEC, KEY_EQUIPPED, equipped_id)
	cf.save(USER_PATH)


func get_items() -> Array:
	return _items


func get_item(id: String) -> Dictionary:
	for it in _items:
		if it is Dictionary and str(it.get("id", "")) == id:
			return it
	return {}


func is_unlocked(id: String) -> bool:
	return _unlocked.get(id, false)


func unlock(id: String) -> void:
	_unlocked[id] = true
	save_user()


func equip(id: String) -> void:
	if not is_unlocked(id):
		return
	equipped_id = id
	save_user()
	_apply_equipped_theme()


func _color_from_arr(arr: Variant, fallback: Color) -> Color:
	if arr is Array and arr.size() >= 4:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
	return fallback


func peek_equipped_theme() -> Array:
	var it := get_item(equipped_id)
	return [
		_color_from_arr(it.get("player_fill", null), Color(1, 0.35, 1, 0.95)),
		_color_from_arr(it.get("player_ring", null), Color(0.4, 1, 1, 0.9)),
		_color_from_arr(it.get("anchor_ring", null), Color(0, 1, 1, 0.85)),
		_color_from_arr(it.get("anchor_core", null), Color(1, 0, 1, 0.35)),
	]


func _apply_equipped_theme() -> void:
	var c: Array = peek_equipped_theme()
	equipped_changed.emit(c[0], c[1], c[2], c[3])


func try_buy_skin(id: String) -> bool:
	var it := get_item(id)
	if it.is_empty():
		return false
	if is_unlocked(id):
		return true
	var price: int = int(it.get("price", 999999))
	if price <= 0:
		unlock(id)
		return true
	if not CurrencyManager.try_spend(price):
		return false
	unlock(id)
	return true
