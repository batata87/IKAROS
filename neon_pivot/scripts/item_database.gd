extends Node
## Autoload: static item defs from res://data/items.json + user unlock / equip (user://).
## Full `skin` sets both pilot + anchors; `dot_skin` / `ring_skin` mix independently.

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
## Legacy single slot (migrated once to dot + ring).
const KEY_EQUIPPED_LEGACY := "equipped_id"
const KEY_EQUIPPED_DOT := "equipped_dot_id"
const KEY_EQUIPPED_RING := "equipped_ring_id"

var _items: Array = []
## id -> bool
var _unlocked: Dictionary = {}
var equipped_dot_id: String = "skin_default"
var equipped_ring_id: String = "skin_default"


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

	if cf.has_section_key(SEC, KEY_EQUIPPED_DOT):
		equipped_dot_id = str(cf.get_value(SEC, KEY_EQUIPPED_DOT, "skin_default"))
		equipped_ring_id = str(cf.get_value(SEC, KEY_EQUIPPED_RING, "skin_default"))
	else:
		var legacy := str(cf.get_value(SEC, KEY_EQUIPPED_LEGACY, "skin_default"))
		equipped_dot_id = legacy
		equipped_ring_id = legacy

	if not is_unlocked(equipped_dot_id):
		equipped_dot_id = "skin_default"
	if not is_unlocked(equipped_ring_id):
		equipped_ring_id = "skin_default"


func _seed_defaults() -> void:
	for it in _items:
		if not it is Dictionary:
			continue
		var id: String = str(it.get("id", ""))
		if bool(it.get("unlocked_default", false)):
			_unlocked[id] = true
	equipped_dot_id = "skin_default"
	equipped_ring_id = "skin_default"
	save_user()


func save_user() -> void:
	var cf := ConfigFile.new()
	cf.load(USER_PATH)
	var ids: PackedStringArray = PackedStringArray()
	for k in _unlocked.keys():
		if _unlocked[k]:
			ids.append(str(k))
	cf.set_value(SEC, KEY_UNLOCKED, ids)
	cf.set_value(SEC, KEY_EQUIPPED_DOT, equipped_dot_id)
	cf.set_value(SEC, KEY_EQUIPPED_RING, equipped_ring_id)
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
	var it := get_item(id)
	if it.is_empty():
		return
	var cat := str(it.get("category", "skin"))
	match cat:
		"dot_skin":
			equipped_dot_id = id
		"ring_skin":
			equipped_ring_id = id
		_:
			equipped_dot_id = id
			equipped_ring_id = id
	save_user()
	_apply_equipped_theme()


func _color_from_arr(arr: Variant, fallback: Color) -> Color:
	if arr is Array and arr.size() >= 4:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
	return fallback


func peek_equipped_theme() -> Array:
	var def := get_item("skin_default")
	var dot := get_item(equipped_dot_id)
	var ring := get_item(equipped_ring_id)
	var pf := _color_from_arr(dot.get("player_fill", null), _color_from_arr(def.get("player_fill", null), Color(1, 0.35, 1, 0.95)))
	var pr := _color_from_arr(dot.get("player_ring", null), _color_from_arr(def.get("player_ring", null), Color(0.4, 1, 1, 0.9)))
	var ar := _color_from_arr(ring.get("anchor_ring", null), _color_from_arr(def.get("anchor_ring", null), Color(0, 1, 1, 0.85)))
	var ac := _color_from_arr(ring.get("anchor_core", null), _color_from_arr(def.get("anchor_core", null), Color(1, 0, 1, 0.35)))
	return [pf, pr, ar, ac]


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
