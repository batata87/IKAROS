extends Node
## Autoload: persistent LUX balance (user://).

signal lux_changed(new_balance: int)

const SAVE_PATH := "user://vault_lux.cfg"
const SECTION := "vault"
const KEY_LUX := "lux"

var lux: int = 0


func _ready() -> void:
	load_lux()


func add_lux(amount: int) -> void:
	if amount <= 0:
		return
	lux += amount
	lux_changed.emit(lux)
	save_lux()


func try_spend(amount: int) -> bool:
	if amount > lux:
		return false
	lux -= amount
	lux_changed.emit(lux)
	save_lux()
	return true


func save_lux() -> void:
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value(SECTION, KEY_LUX, lux)
	cf.save(SAVE_PATH)


func load_lux() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		lux = 0
		return
	lux = int(cf.get_value(SECTION, KEY_LUX, 0))
	lux = maxi(lux, 0)
	lux_changed.emit(lux)


func play_lux_pickup_chime() -> void:
	call_deferred("_play_lux_pickup_chime")


func _play_lux_pickup_chime() -> void:
	var root := get_tree().root
	var player := AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 24000.0
	player.stream = gen
	player.volume_db = -6.0
	root.add_child(player)
	player.play()
	await get_tree().process_frame
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		player.queue_free()
		return
	var sr := int(gen.mix_rate)
	var dur := 0.11
	var hz := 1240.0
	var nframes: int = maxi(64, int(sr * dur))
	var buf := PackedVector2Array()
	buf.resize(nframes)
	for i in range(nframes):
		var t := float(i) / float(sr)
		var env := exp(-t * 18.0)
		var s := sin(TAU * hz * t) * env * 0.42
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)
	await get_tree().create_timer(dur + 0.08).timeout
	player.queue_free()
