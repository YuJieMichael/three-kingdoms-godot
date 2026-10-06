class_name KingdomPresentationAudio extends Node

## Presentation only. No commands, save data or timers for game rules.
var settings_path: String = "user://presentation-audio.cfg"
var levels: Dictionary = {"Music": 0.25, "Sounds": 0.65, "UI": 0.5}
var _streams: Dictionary = {}
var _started: bool = false
var manager: Node

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
	_streams["battle"] = _tone([130.81, 98.0], 0.16)
	_streams["music"] = _tone([261.63, 293.66, 329.63, 392.0, 329.63, 293.66, 261.63, 196.0], 0.8, true)

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
	if not _started:
		_started = true
		manager.play_music(_streams["music"], 0, "Music")
	manager.play_ui_sound(_streams["click"], "UI")

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
