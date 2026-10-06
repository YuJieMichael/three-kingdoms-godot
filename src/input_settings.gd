class_name KingdomInputSettings
extends RefCounted

## Desktop shortcuts are separate from game saves and Godot's built-in ui_*.
## Only physical keys are stored; a failed write never changes live bindings.
signal bindings_changed

const CONFIG_VERSION: int = 1
const DEFAULT_ACTIONS: Dictionary = {
	"tk_page_city": [KEY_1],
	"tk_page_world": [KEY_2],
	"tk_page_army": [KEY_3],
	"tk_page_generals": [KEY_4],
	"tk_page_reports": [KEY_5],
	"tk_map_left": [KEY_A, KEY_LEFT],
	"tk_map_right": [KEY_D, KEY_RIGHT],
	"tk_map_up": [KEY_W, KEY_UP],
	"tk_map_down": [KEY_S, KEY_DOWN],
	"tk_map_zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"tk_map_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"tk_map_home": [KEY_H, KEY_HOME],
	"tk_tasks": [KEY_T],
	"tk_save": [KEY_O],
	"tk_settings": [KEY_K],
}
const ACTION_LABELS: Dictionary = {
	"tk_page_city": "查看城池", "tk_page_world": "查看大地图",
	"tk_page_army": "查看军队", "tk_page_generals": "查看将领",
	"tk_page_reports": "查看战报", "tk_map_left": "地图向左",
	"tk_map_right": "地图向右", "tk_map_up": "地图向上",
	"tk_map_down": "地图向下", "tk_map_zoom_in": "地图放大",
	"tk_map_zoom_out": "地图缩小", "tk_map_home": "地图回到主城",
	"tk_tasks": "查看任务", "tk_save": "打开存档", "tk_settings": "快捷键设置",
}
const BINDING_FIELDS: Array[String] = ["physical_keycode", "ctrl", "alt", "shift", "meta"]
const MODIFIER_KEYS: Array[int] = [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]
const UI_KEYS: Array[int] = [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_TAB, KEY_BACKTAB]

var load_warning: String = ""
var _path: String
var _bindings: Dictionary = {}


func _init(storage_path: String = "user://input-settings.cfg") -> void:
	_path = storage_path


func initialize() -> void:
	load_warning = ""
	_bindings = _defaults()
	if FileAccess.file_exists(_path):
		var config: ConfigFile = ConfigFile.new()
		var error: Error = config.load(_path)
		if error != OK:
			load_warning = "快捷键配置无法读取，已使用默认按键；游戏存档不受影响。"
		else:
			var validation: String = _validate_config(config)
			if validation.is_empty():
				for action: String in actions():
					_bindings[action] = config.get_value("bindings", action).duplicate(true)
			else:
				load_warning = "快捷键配置无效，已使用默认按键：" + validation
	_install(_bindings)


func actions() -> Array[String]:
	var result: Array[String] = []
	for action: String in DEFAULT_ACTIONS:
		result.append(action)
	return result


func action_label(action: String) -> String:
	return str(ACTION_LABELS.get(action, action))


func binding_text(action: String) -> String:
	var result: PackedStringArray = []
	for binding: Dictionary in _bindings.get(action, []):
		result.append(_event(binding).as_text_physical_keycode().replace(" (Physical)", ""))
	return " / ".join(result)


func action_for_event(event: InputEvent) -> String:
	if not event is InputEventKey or (event as InputEventKey).physical_keycode == KEY_NONE:
		return ""
	var descriptor: Dictionary = _descriptor(event as InputEventKey)
	for action: String in actions():
		for binding: Dictionary in _bindings.get(action, []):
			if _same_binding(descriptor, binding):
				return action
	return ""


func movement_vector() -> Vector2:
	var vector: Vector2 = Vector2(
		float(Input.is_action_pressed("tk_map_right", true)) - float(Input.is_action_pressed("tk_map_left", true)),
		float(Input.is_action_pressed("tk_map_down", true)) - float(Input.is_action_pressed("tk_map_up", true))
	)
	return vector.normalized() if vector.length_squared() > 1.0 else vector


func rebind(action: String, event: InputEventKey) -> String:
	if not DEFAULT_ACTIONS.has(action):
		return "未知快捷键动作。"
	if event == null:
		return "请选择一个键盘按键。"
	var binding: Dictionary = _descriptor(event)
	var reason: String = _validate_binding(binding)
	if not reason.is_empty():
		return reason
	for other: String in actions():
		if other == action:
			continue
		for existing: Dictionary in _bindings.get(other, []):
			if _same_binding(binding, existing):
				return "该组合已用于「%s」，请换一个按键。" % action_label(other)
	var candidate: Dictionary = _bindings.duplicate(true)
	candidate[action] = [binding]
	return _commit(candidate)


func restore_defaults() -> String:
	return _commit(_defaults())


func _commit(candidate: Dictionary) -> String:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", CONFIG_VERSION)
	for action: String in actions():
		config.set_value("bindings", action, candidate[action])
	# Write to a sibling first, so an unsuccessful write leaves both the old
	# settings file and InputMap intact. Rename replaces a prior settings file.
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_path)):
		return "快捷键配置路径是文件夹，无法保存；已保留原按键。"
	var temporary_path: String = _path + ".tmp"
	var error: Error = config.save(temporary_path)
	if error != OK:
		return "无法写入快捷键配置（%s），已保留原按键。" % error_string(error)
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(_path))
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		return "无法保存快捷键配置（%s），已保留原按键。" % error_string(error)
	_bindings = candidate
	load_warning = ""
	_install(_bindings)
	bindings_changed.emit()
	return ""


func _defaults() -> Dictionary:
	var result: Dictionary = {}
	for action: String in actions():
		var bindings: Array = []
		for key: int in DEFAULT_ACTIONS[action]:
			bindings.append({"physical_keycode": key, "ctrl": false, "alt": false, "shift": false, "meta": false})
		result[action] = bindings
	return result


func _install(bindings: Dictionary) -> void:
	for action: String in actions():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for binding: Dictionary in bindings.get(action, []):
			InputMap.action_add_event(action, _event(binding))


func _descriptor(event: InputEventKey) -> Dictionary:
	return {"physical_keycode": int(event.physical_keycode), "ctrl": event.ctrl_pressed, "alt": event.alt_pressed, "shift": event.shift_pressed, "meta": event.meta_pressed}


func _event(binding: Dictionary) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = int(binding.physical_keycode)
	event.ctrl_pressed = bool(binding.ctrl)
	event.alt_pressed = bool(binding.alt)
	event.shift_pressed = bool(binding.shift)
	event.meta_pressed = bool(binding.meta)
	return event


func _same_binding(first: Dictionary, second: Dictionary) -> bool:
	for field: String in BINDING_FIELDS:
		if first.get(field) != second.get(field):
			return false
	return true


func _validate_binding(binding: Dictionary) -> String:
	if binding.size() != BINDING_FIELDS.size():
		return "按键数据字段无效。"
	for field: String in BINDING_FIELDS:
		if not binding.has(field):
			return "按键数据字段不完整。"
	if not binding.physical_keycode is int:
		return "物理键码必须为整数。"
	for modifier: String in ["ctrl", "alt", "shift", "meta"]:
		if not binding[modifier] is bool:
			return "修饰键数据必须为布尔值。"
	var key: int = int(binding.physical_keycode)
	var key_name: String = OS.get_keycode_string(key)
	if key <= 0 or key_name.is_empty() or int(OS.find_keycode_from_string(key_name)) != key:
		return "请选择有效的物理键盘按键。"
	if key in MODIFIER_KEYS:
		return "不能单独绑定修饰键或锁定键，请同时按下一个普通按键。"
	if key in UI_KEYS:
		return "Esc、Enter 和 Tab 保留给关闭、确认和切换焦点。"
	if bool(binding.ctrl) or bool(binding.meta):
		if key in [KEY_R, KEY_W, KEY_Q, KEY_TAB]:
			return "该组合保留给浏览器或系统操作，请选择其他按键。"
	if bool(binding.alt) and key == KEY_F4:
		return "Alt + F4 会关闭窗口，不能设为游戏快捷键。"
	return ""


func _validate_config(config: ConfigFile) -> String:
	var sections: PackedStringArray = config.get_sections()
	if sections.size() != 2 or not config.has_section("meta") or not config.has_section("bindings"):
		return "配置段落无效。"
	if config.get_section_keys("meta").size() != 1 or not config.has_section_key("meta", "version"):
		return "配置版本字段无效。"
	var version: Variant = config.get_value("meta", "version")
	if not version is int or version != CONFIG_VERSION:
		return "配置版本不支持。"
	var keys: PackedStringArray = config.get_section_keys("bindings")
	if keys.size() != DEFAULT_ACTIONS.size():
		return "动作列表不完整或包含未知动作。"
	var seen: Array[Dictionary] = []
	for action: String in keys:
		if not DEFAULT_ACTIONS.has(action):
			return "包含未知动作。"
		var value: Variant = config.get_value("bindings", action)
		if not value is Array or value.is_empty() or value.size() > 2:
			return "每个动作需要一至两个按键。"
		for raw_binding: Variant in value:
			if not raw_binding is Dictionary:
				return "按键数据格式无效。"
			var binding: Dictionary = raw_binding
			var reason: String = _validate_binding(binding)
			if not reason.is_empty():
				return reason
			for previous: Dictionary in seen:
				if _same_binding(previous, binding):
					return "多个动作使用了重复按键。"
			seen.append(binding)
	return ""
