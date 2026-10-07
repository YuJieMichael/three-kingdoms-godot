class_name KingdomPresentationAudio extends Node

## Presentation only. No commands, save data or timers for game rules.
var settings_path: String = "user://presentation-audio.cfg"
var levels: Dictionary = {"Music": 0.55, "Sounds": 0.65, "UI": 0.35}
var _streams: Dictionary = {}
var _started: bool = false
var manager: Node
var _context: String = "city"

func _ready() -> void:
	manager = Engine.get_singleton("SoundManager") as Node
	for bus: String in levels:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	manager.set_default_sound_bus("Sounds")
	manager.set_default_ui_sound_bus("UI")
	manager.set_default_music_bus("Music")
	load_settings()
	_streams["click"] = _tone([660.0], 0.06)
	_streams["success"] = _tone([523.25, 659.25, 783.99], 0.12)
	_streams["march"] = _tone([196.0, 293.66], 0.12)
	_streams["battle"] = _drum()
	_streams["city_music"] = load("res://assets/audio/city.mp3")
	_streams["battle_music"] = load("res://assets/audio/battle.mp3")
	for key: String in ["city_music", "battle_music"]:
		var music: AudioStreamMP3 = _streams[key] as AudioStreamMP3
		music.loop = true
	if not OS.has_feature("web"):
		call_deferred("start_music")

func load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(settings_path) == OK:
		for bus: String in levels:
			var value: Variant = config.get_value("audio", bus, levels[bus])
			if (value is float or value is int) and is_finite(float(value)):
				levels[bus] = clampf(float(value), 0.0, 1.0)
	_apply_levels()

func set_level(bus: String, value: float) -> Error:
	if not levels.has(bus) or not is_finite(value):
		return ERR_INVALID_PARAMETER
	var config: ConfigFile = ConfigFile.new()
	for name: String in levels:
		config.set_value("audio", name, clampf(value, 0.0, 1.0) if name == bus else levels[name])
	var error: Error = config.save(settings_path)
	if error == OK:
		levels[bus] = clampf(value, 0.0, 1.0)
		_apply_levels()
	return error

func _apply_levels() -> void:
	for bus: String in levels:
		var index: int = AudioServer.get_bus_index(bus)
		AudioServer.set_bus_mute(index, float(levels[bus]) <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, float(levels[bus]))))

func click() -> void:
	# Web audio begins from a deliberate button/keyboard gesture.
	start_music()
	manager.play_ui_sound(_streams["click"], "UI")

func start_music() -> void:
	if not _started:
		_started = true
		manager.play_music(_streams[_context + "_music"], 0.8, "Music")

func set_context(battle: bool) -> void:
	var next: String = "battle" if battle else "city"
	if next == _context:
		return
	_context = next
	if _started:
		manager.play_music(_streams[_context + "_music"], 1.2, "Music")

func _drum() -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data: PackedByteArray = PackedByteArray()
	data.resize(6600 * 2)
	for i: int in range(6600):
		var t: float = float(i) / 22050.0
		var hit: float = sin(TAU * (65.0 * t + 22.0 * (1.0 - exp(-t * 28.0)) / 28.0)) * exp(-t * 16.0)
		var attack: float = sin(float(i) * 1.618) * exp(-t * 90.0) * 0.3
		data.encode_s16(i * 2, int((hit + attack) * 12000.0))
	stream.data = data
	return stream

func confirmed(command: String) -> void:
	if not _started:
		return
	var cue: String = "success"
	if command in ["dispatch", "recall"]:
		cue = "march"
	elif command in ["battleRound", "startBattle"]:
		cue = "battle"
	manager.play_sound(_streams[cue], "Sounds")

func _tone(notes: Array, seconds: float, loop: bool = false) -> AudioStreamWAV:
	# Original low-volume synthesized cues; replace these streams with final art.
	var rate: int = 22050
	var count: int = int(seconds * rate)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * notes.size() * 2)
	for n: int in notes.size():
		for i: int in count:
			var t: float = float(i) / rate
			var envelope: float = minf(t / 0.015, 1.0) * pow(1.0 - float(i) / count, 2.0)
			var sample: int = int(sin(TAU * float(notes[n]) * t) * envelope * 4000.0)
			bytes.encode_s16((n * count + i) * 2, sample)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count * notes.size()
	return stream
