class_name KingdomUiFeedback extends Node

## Local presentation preferences are separate from canonical game progress.
## Feedback only animates color; it never delays input or changes simulation time.
signal preferences_changed

const CONFIG_VERSION: int = 1
var settings_path: String = "user://ui-preferences.cfg"
var reduced_motion: bool = false
var load_warning: String = ""
var _tracked: Dictionary = {}
var _watched: Dictionary = {}
var _effects: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ui_feedback")
	load_settings()


func load_settings() -> void:
	var candidate: bool = false
	load_warning = ""
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(settings_path)
	if error == OK:
		var version: Variant = config.get_value("meta", "version", null)
		var value: Variant = config.get_value("display", "reduced_motion", null)
		if version is int and version == CONFIG_VERSION and value is bool:
			candidate = value
		else:
			load_warning = "显示配置无效，已使用默认设置。"
	elif error != ERR_FILE_NOT_FOUND:
		load_warning = "显示配置无法读取，已使用默认设置。"
	_apply_preference(candidate)


func set_reduced_motion(value: bool) -> Error:
	var absolute_path: String = ProjectSettings.globalize_path(settings_path)
	if DirAccess.dir_exists_absolute(absolute_path):
		return ERR_FILE_CANT_WRITE
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", CONFIG_VERSION)
	config.set_value("display", "reduced_motion", value)
	# Commit the sibling first. A failed save or rename leaves the old setting
	# and its file intact, including when a valid preference already exists.
	var temporary_path: String = settings_path + ".tmp"
	var error: Error = config.save(temporary_path)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), absolute_path)
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return error
	load_warning = ""
	_apply_preference(value)
	return OK


func watch_button(button: Button) -> void:
	if not is_instance_valid(button):
		return
	var id: int = button.get_instance_id()
	if _watched.has(id):
		return
	_track(button)
	var callback: Callable = _pulse_button.bind(id)
	button.pressed.connect(callback)
	_watched[id] = callback


func notice(control: Control) -> void:
	if not is_instance_valid(control):
		return
	control.show()
	if reduced_motion or not control.is_inside_tree():
		_cancel_effect(control.get_instance_id())
		return
	_track(control)
	var base: Color = _effect_base(control)
	var start: Color = base
	start.a *= 0.65
	_animate(control, start, base, 0.16)


func _pulse_button(id: int) -> void:
	var button: Button = _control(id) as Button
	if button == null or button.disabled:
		return
	if reduced_motion or not button.is_inside_tree():
		_cancel_effect(id)
		return
	var base: Color = _effect_base(button)
	var start: Color = Color(base.r * 0.9, base.g * 0.9, base.b * 0.9, base.a)
	_animate(button, start, base, 0.12)


func _track(control: Control) -> void:
	var id: int = control.get_instance_id()
	if _tracked.has(id):
		return
	var exit_callback: Callable = _forget_control.bind(id)
	control.tree_exiting.connect(exit_callback)
	_tracked[id] = {"ref": weakref(control), "exit": exit_callback}


func _control(id: int) -> Control:
	if not _tracked.has(id):
		return null
	return (_tracked[id].ref as WeakRef).get_ref() as Control


func _effect_base(control: Control) -> Color:
	var id: int = control.get_instance_id()
	return _effects[id].base if _effects.has(id) else control.modulate


func _animate(control: Control, start: Color, base: Color, duration: float) -> void:
	var id: int = control.get_instance_id()
	_cancel_effect(id)
	control.modulate = start
	var tween: Tween = create_tween().bind_node(control)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_ignore_time_scale(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate", base, duration)
	_effects[id] = {"base": base, "tween": tween}
	tween.finished.connect(_finish_effect.bind(id, tween))


func _finish_effect(id: int, tween: Tween) -> void:
	if _effects.has(id) and _effects[id].tween == tween:
		_cancel_effect(id)


func _cancel_effect(id: int) -> void:
	if not _effects.has(id):
		return
	var effect: Dictionary = _effects[id]
	var tween: Tween = effect.tween
	if tween.is_valid():
		tween.kill()
	var control: Control = _control(id)
	if control != null:
		control.modulate = effect.base
	_effects.erase(id)


func _apply_preference(value: bool) -> void:
	var changed: bool = value != reduced_motion
	reduced_motion = value
	if reduced_motion:
		for id: int in _effects.keys():
			_cancel_effect(id)
	if changed:
		preferences_changed.emit()


func _forget_control(id: int) -> void:
	_cancel_effect(id)
	var control: Control = _control(id)
	if control is Button and _watched.has(id) and (control as Button).pressed.is_connected(_watched[id]):
		(control as Button).pressed.disconnect(_watched[id])
	if control != null and control.tree_exiting.is_connected(_tracked[id].exit):
		control.tree_exiting.disconnect(_tracked[id].exit)
	_watched.erase(id)
	_tracked.erase(id)


func _exit_tree() -> void:
	for id: int in _tracked.keys():
		_forget_control(id)
