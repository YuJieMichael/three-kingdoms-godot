class_name KingdomPresentationMenu extends AcceptDialog

signal input_requested
signal guide_requested
signal practice_requested
signal save_requested
signal connection_requested

const TabsScript: Script = preload("res://addons/maaacks_menu/paginated_tab_container.gd")
var audio: KingdomPresentationAudio
var feedback: KingdomUiFeedback
var _tabs: TabContainer
var _feedback: Label
var _reduced_motion: CheckBox
var _display_feedback: Label

func _ready() -> void:
	title = "山河策 · 菜单"
	ok_button_text = "返回游戏"
	min_size = Vector2i(280, 300)
	_tabs = TabsScript.new() as TabContainer
	_tabs.tab_focus_mode = Control.FOCUS_ALL
	add_child(_tabs)
	var general: VBoxContainer = _tab("游戏")
	var message: Label = Label.new()
	message.text = "进度自动保存。菜单打开时，建设与行军仍按时间推进。"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	general.add_child(message)
	for entry: Array in [["借调演练 · 先练一战", practice_requested], ["新手引导", guide_requested], ["按键设置", input_requested], ["存档与备份", save_requested], ["连接设置", connection_requested]]:
		var action: Signal = entry[1]
		var button: Button = Button.new()
		button.text = str(entry[0])
		button.custom_minimum_size.y = 40
		button.theme_type_variation = "PrimaryButton" if action == practice_requested else "UtilityButton"
		button.pressed.connect(func() -> void: audio.click(); hide(); action.emit())
		general.add_child(button)
		_watch_button(button)
	var sound: VBoxContainer = _tab("声音")
	for bus: String in ["Music", "Sounds", "UI"]:
		var caption: Label = Label.new()
		caption.text = {"Music": "音乐", "Sounds": "游戏音效", "UI": "界面音效"}[bus]
		sound.add_child(caption)
		var slider: HSlider = HSlider.new()
		slider.name = bus
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = float(audio.levels[bus])
		slider.custom_minimum_size.y = 35
		sound.add_child(slider)
		slider.value_changed.connect(func(value: float) -> void:
			var error: Error = audio.set_level(bus, value)
			_feedback.text = "声音设置已保存" if error == OK else "声音设置保存失败，保留原设置"
			if error != OK:
				slider.set_value_no_signal(float(audio.levels[bus]))
			_notice(_feedback))
	var test: Button = Button.new()
	test.text = "试听"
	test.custom_minimum_size.y = 40
	test.theme_type_variation = "UtilityButton"
	test.pressed.connect(audio.click)
	sound.add_child(test)
	_watch_button(test)
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sound.add_child(_feedback)
	var display: VBoxContainer = _tab("显示")
	var display_title: Label = Label.new()
	display_title.text = "界面动态效果"
	display_title.theme_type_variation = "SectionLabel"
	display.add_child(display_title)
	_reduced_motion = CheckBox.new()
	_reduced_motion.name = "ReducedMotion"
	_reduced_motion.text = "减少动态效果"
	_reduced_motion.custom_minimum_size.y = 44
	_reduced_motion.focus_mode = Control.FOCUS_ALL
	_reduced_motion.toggled.connect(_set_display_preference)
	display.add_child(_reduced_motion)
	var display_help: Label = Label.new()
	display_help.text = "开启后，界面提示立即显示，按钮与战斗反馈使用静态呈现。设置自动保存在本机。"
	display_help.theme_type_variation = "MutedLabel"
	display_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	display.add_child(display_help)
	_display_feedback = Label.new()
	_display_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	display.add_child(_display_feedback)
	_refresh_display_settings()
	if feedback != null:
		feedback.preferences_changed.connect(_refresh_display_settings)
		_display_feedback.text = feedback.load_warning
	else:
		_display_feedback.text = "显示设置暂不可用。"
	var credits: VBoxContainer = _tab("鸣谢")
	var text: Label = Label.new()
	text.text = "声音：Nathan Hoad · Sound Manager\n剧情：Nathan Hoad · Dialogue Manager\n菜单分页：Maaack · Game Template\n以上代码采用 MIT 许可证。\n当前合成音乐与提示音为项目自制，可替换为正式素材。"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.add_child(text)
	confirmed.connect(audio.click)
	get_ok_button().theme_type_variation = "UtilityButton"
	_watch_button(get_ok_button())
	get_tree().root.size_changed.connect(_fit_window)

func _tab(caption: String) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = caption
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	return column

func open_menu() -> void:
	_refresh_display_settings()
	_fit_window()
	popup_centered(size)
	get_ok_button().grab_focus()

func _fit_window() -> void:
	var viewport_size: Vector2 = get_tree().root.get_visible_rect().size
	size = Vector2i(int(minf(560.0, viewport_size.x - 24.0)), int(minf(430.0, viewport_size.y - 48.0)))
	if visible:
		position = Vector2i((viewport_size - Vector2(size)) / 2.0)

func _set_display_preference(value: bool) -> void:
	if feedback == null:
		return
	audio.click()
	var error: Error = feedback.set_reduced_motion(value)
	_refresh_display_settings()
	_display_feedback.text = "显示设置已保存" if error == OK else "显示设置保存失败，保留原设置"
	_notice(_display_feedback)

func _refresh_display_settings() -> void:
	if not is_instance_valid(_reduced_motion):
		return
	_reduced_motion.disabled = feedback == null
	if feedback != null:
		_reduced_motion.set_pressed_no_signal(feedback.reduced_motion)

func _watch_button(button: Button) -> void:
	if feedback != null:
		feedback.watch_button(button)

func _notice(label: Label) -> void:
	if feedback != null:
		feedback.notice(label)
