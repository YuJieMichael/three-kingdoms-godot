class_name KingdomInputSettingsDialog
extends AcceptDialog

## This window consumes capture input before controls or page shortcuts see it.
const UI_FONT: Font = preload("res://assets/fonts/UI.tres")
var _settings: KingdomInputSettings
var _scroll: ScrollContainer
var _content: VBoxContainer
var _rows: GridContainer
var _status: Label
var _buttons: Dictionary = {}
var _capture: String = ""
var _eat_key_release: int = KEY_NONE


func _ready() -> void:
	# Window has its own viewport; retain the parent's Chinese UI theme.
	if get_parent() is Control and (get_parent() as Control).theme != null:
		theme = (get_parent() as Control).theme
	else:
		theme = Theme.new()
		theme.default_font = UI_FONT
	title = "快捷键设置"
	dialog_text = ""
	get_ok_button().text = "关闭"
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)
	_content.add_child(_label("点击右侧按键，然后按下新组合。地图快捷键在大地图中生效；输入文字时暂停页面快捷键。", 14))
	_status = _label("", 14)
	_content.add_child(_status)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_rows)
	_build_rows()
	var defaults_button: Button = Button.new()
	defaults_button.text = "恢复默认快捷键"
	defaults_button.custom_minimum_size.y = 40
	defaults_button.pressed.connect(_restore_defaults)
	_content.add_child(defaults_button)
	_content.add_child(_label("固定操作：Tab 切换焦点 · Enter 确认 · Esc 取消改键或关闭窗口。\n快捷键配置单独保存，不会修改游戏存档。", 13))
	visibility_changed.connect(func() -> void:
		if not visible:
			cancel_capture())
	_update_bindings()


func setup(settings: KingdomInputSettings) -> void:
	if _settings != null and _settings.bindings_changed.is_connected(_update_bindings):
		_settings.bindings_changed.disconnect(_update_bindings)
	_settings = settings
	_settings.bindings_changed.connect(_update_bindings)
	if is_instance_valid(_rows):
		_build_rows()


func _build_rows() -> void:
	if not is_instance_valid(_rows):
		return
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_buttons.clear()
	if _settings == null:
		return
	for action: String in _settings.actions():
		var label: Label = _label(_settings.action_label(action), 15)
		_rows.add_child(label)
		var button: Button = Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(130, 38)
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_begin_capture.bind(action))
		_rows.add_child(button)
		_buttons[action] = button
	_update_bindings()


func show_settings() -> void:
	_eat_key_release = KEY_NONE
	cancel_capture()
	_fit_window()
	if _settings != null:
		_status.text = _settings.load_warning if not _settings.load_warning.is_empty() else "选择一个动作，修改后自动保存。"
		_status.modulate = Color("e7bc72") if not _settings.load_warning.is_empty() else Color.WHITE
	_update_bindings()
	popup_centered()


func capturing_action() -> String:
	return _capture


func cancel_capture() -> void:
	_capture = ""
	_update_bindings()


func _fit_window() -> void:
	var available: Vector2 = Vector2(get_tree().root.size)
	if get_parent() is Control:
		available = (get_parent() as Control).size
	var width: int = mini(660, maxi(280, int(available.x) - 40))
	var height: int = mini(670, maxi(280, int(available.y) - 80))
	min_size = Vector2i(width, height)
	size = min_size
	_scroll.custom_minimum_size = Vector2(float(width - 48), float(height - 90))
	# Resizing an open popup must retain capture state and keep it reachable.
	position = Vector2i(
		clampi(position.x, 20, maxi(20, int(available.x) - size.x - 20)),
		clampi(position.y, 30, maxi(30, int(available.y) - size.y - 20))
	)


func _begin_capture(action: String) -> void:
	if _settings == null or not action in _settings.actions():
		return
	_capture = action
	_status.text = "正在修改「%s」：请按新组合；Esc 取消。" % _settings.action_label(action)
	_status.modulate = Color("e7bc72")
	_update_bindings()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if int(key.physical_keycode) == _eat_key_release:
		get_viewport().set_input_as_handled()
		if not key.pressed:
			_eat_key_release = KEY_NONE
		return
	if _capture.is_empty():
		return
	get_viewport().set_input_as_handled()
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		_eat_key_release = KEY_ESCAPE
		cancel_capture()
		_status.text = "已取消修改，原按键保持不变。"
		_status.modulate = Color.WHITE
		return
	var action: String = _capture
	var reason: String = _settings.rebind(action, key)
	if not reason.is_empty():
		_status.text = reason + "\n请重试，或按 Esc 取消。"
		_status.modulate = Color("e7bc72")
		return
	_eat_key_release = int(key.physical_keycode)
	_capture = ""
	_update_bindings()
	_status.text = "「%s」已改为 %s，并已保存。" % [_settings.action_label(action), _settings.binding_text(action)]
	_status.modulate = Color.WHITE


func _restore_defaults() -> void:
	cancel_capture()
	var reason: String = _settings.restore_defaults()
	_status.text = "已恢复并保存默认快捷键。" if reason.is_empty() else reason
	_status.modulate = Color.WHITE if reason.is_empty() else Color("e7bc72")


func _update_bindings() -> void:
	if _settings == null:
		return
	for action: String in _buttons:
		var button: Button = _buttons[action]
		button.text = "等待按键…" if action == _capture else _settings.binding_text(action).replace(" (Physical)", "")
		button.tooltip_text = _settings.binding_text(action)


func _label(text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label
