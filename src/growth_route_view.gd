class_name KingdomGrowthRouteView
extends PanelContainer

## A stable, read-only route card. The host owns its modal and all navigation.
signal navigate_requested(route: String, target: String)

var _view: Dictionary = {}
var _connected: bool = true
var _pending: bool = false
var _expanded: bool = false
var _stage: Label
var _title: Label
var _description: Label
var _gaps: Label
var _more: Button
var _current: Button
var _speedup: Label
var _speedup_action: Button
var _advice: Array[Label] = []
var _advice_actions: Array[Button] = []
var _status: Label


func _ready() -> void:
	theme_type_variation = "InsetPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(content)
	_stage = _label(content, "成长路线", "SectionLabel")
	_title = _label(content, "正在读取成长路线")
	_description = _label(content, "连接规则服务后显示当前一步。", "MutedLabel")
	_gaps = _label(content, "", "MutedLabel")
	_more = _button(content, "展开其余前置")
	_more.pressed.connect(func() -> void:
		_expanded = not _expanded
		_render())
	_current = _button(content, "前往当前一步", true)
	_current.pressed.connect(_navigate.bind(_current))
	content.add_child(HSeparator.new())
	_speedup = _label(content, "", "MutedLabel")
	_speedup_action = _button(content, "查看已入库加速")
	_speedup_action.pressed.connect(_navigate.bind(_speedup_action))
	for index: int in range(2):
		var label: Label = _label(content, "", "MutedLabel")
		_advice.append(label)
		var action: Button = _button(content, "查看建议")
		action.pressed.connect(_navigate.bind(action))
		_advice_actions.append(action)
	_status = _label(content, "", "MutedLabel")
	_render()


func update_view(view: Dictionary) -> void:
	_view = view
	if is_instance_valid(_stage):
		_render()


func set_navigation_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	if is_instance_valid(_stage):
		_render()


func focus_current() -> void:
	if is_instance_valid(_current) and _current.is_visible_in_tree() and not _current.disabled:
		_current.grab_focus()


func _render() -> void:
	var growth: Dictionary = _view.get("growth", {})
	var shared: bool = growth.get("shared", false)
	var stage: Dictionary = growth.get("stage", {})
	_stage.text = str(stage.get("title", "成长路线"))
	if int(stage.get("total", 0)) > 1:
		_stage.text += " · %d / %d" % [int(stage.get("progress", 0)), int(stage.get("total", 0))]
	var step: Dictionary = growth.get("current", {}) if growth.get("current") is Dictionary else {}
	_title.text = "私人路线暂不可用" if shared else str(step.get("title", "正在读取成长路线"))
	_description.text = str(growth.get("reason", "")) if shared else str(step.get("description", "连接规则服务后显示当前一步。"))
	var reason: String = str(step.get("reason", ""))
	if not reason.is_empty() and not _description.text.contains(reason):
		_description.text += "\n" + reason
	var rows: Array = growth.get("gaps", [])
	var pieces: PackedStringArray = []
	var limit: int = rows.size() if _expanded else mini(3, rows.size())
	for index: int in range(limit):
		var row: Dictionary = rows[index]
		pieces.append("%s %s / %s%s · 还缺 %s%s" % [str(row.get("label", "前置")), _number(row.get("current", 0)),
			_number(row.get("required", 0)), str(row.get("unit", "")), _number(row.get("missing", 0)), str(row.get("unit", ""))])
	_gaps.text = "真实前置\n" + "\n".join(pieces)
	_gaps.visible = not shared and not rows.is_empty()
	_more.visible = not shared and rows.size() > 3
	_more.text = "收起完整前置" if _expanded else "展开其余 %d 项前置" % maxi(0, rows.size() - 3)
	_more.disabled = false
	_set_navigation(_current, step.get("navigate", {}), not shared and not step.is_empty())
	_render_speedup(growth.get("speedup", {}), shared)
	var advice: Array = growth.get("advice", [])
	for index: int in range(_advice.size()):
		var record: Dictionary = advice[index] if index < advice.size() and not shared else {}
		_advice[index].text = str(record.get("text", ""))
		_advice[index].visible = not record.is_empty()
		_set_navigation(_advice_actions[index], record.get("navigate", {}), not record.is_empty())
	_status.text = "正在确认操作，路线在确认后更新。" if _pending else "连接后可前往当前一步。" if not _connected else "此页只提供路线与预览，费用在办理页面确认。"
	_status.visible = not shared
	_wire_focus()


func _render_speedup(speedup: Dictionary, shared: bool) -> void:
	var count: int = int(speedup.get("ownedCount", 0))
	_speedup.visible = not shared and count > 0
	var suggestion: Dictionary = speedup.get("suggestion", {}) if speedup.get("suggestion") is Dictionary else {}
	var text: String = "已入库可用加速 %d 件" % count
	if not suggestion.is_empty():
		text += "\n%s · 库存 %d 件 · %s" % [str(suggestion.get("itemName", "加速")), int(suggestion.get("count", 0)), str(suggestion.get("targetName", "当前队列"))]
		text += "\n本项工作剩余 %s，可缩短 %s；使用后还需 %s（含排队 %s）。" % [
			_duration(suggestion.get("workSeconds", 0)), _range(suggestion.get("shortenMinSeconds", 0), suggestion.get("shortenMaxSeconds", 0)),
			_range(suggestion.get("remainingMinSeconds", 0), suggestion.get("remainingMaxSeconds", 0)), _duration(suggestion.get("waitSeconds", 0))]
		if float(suggestion.get("wasteMaxSeconds", 0)) > 0.0:
			text += "\n超出工作时间的 %s 不保留。" % _range(suggestion.get("wasteMinSeconds", 0), suggestion.get("wasteMaxSeconds", 0))
		if suggestion.get("conserve", false):
			text += "\n这项只剩 %s，建议等待并保留大加速给长工程；也可自行选择使用。" % _duration(suggestion.get("workSeconds", 0))
	else:
		text += "\n当前一步尚无可推荐的合法队列。先安排建设、研究或练兵，再选择对应加速。"
	_speedup.text = text
	var navigate: Dictionary = suggestion.get("navigate", {"route": "inventory", "target": "", "label": "查看已入库加速"})
	_set_navigation(_speedup_action, navigate, not shared and count > 0)


func _set_navigation(button: Button, navigate: Dictionary, show: bool) -> void:
	button.visible = show and not str(navigate.get("route", "")).is_empty()
	button.text = str(navigate.get("label", "前往办理"))
	button.set_meta("navigate", navigate.duplicate(true))
	button.disabled = not _connected or _pending or not str(navigate.get("reason", "")).is_empty()


func _navigate(button: Button) -> void:
	if button.disabled or not button.is_visible_in_tree() or not _connected or _pending:
		return
	var record: Dictionary = button.get_meta("navigate", {})
	var route: String = str(record.get("route", ""))
	if not route.is_empty():
		navigate_requested.emit(route, str(record.get("target", "")))


func _wire_focus() -> void:
	var buttons: Array[Button] = []
	for button: Button in [_more, _current, _speedup_action, _advice_actions[0], _advice_actions[1]]:
		if button.visible and not button.disabled:
			buttons.append(button)
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		button.focus_neighbor_top = buttons[maxi(0, index - 1)].get_path()
		button.focus_neighbor_bottom = buttons[mini(buttons.size() - 1, index + 1)].get_path()
		button.focus_previous = buttons[maxi(0, index - 1)].get_path()
		button.focus_next = buttons[mini(buttons.size() - 1, index + 1)].get_path()


func _label(parent: Node, text: String, variation: String = "") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.theme_type_variation = "PrimaryButton" if primary else "UtilityButton"
	button.custom_minimum_size = Vector2(0, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(button)
	return button


func _number(value: Variant) -> String:
	return str(int(ceil(float(value))))


func _duration(value: Variant) -> String:
	var seconds: int = maxi(0, int(ceil(float(value))))
	if seconds >= 3600:
		return "%d时%02d分" % [seconds / 3600, (seconds % 3600) / 60]
	if seconds >= 60:
		return "%d分%02d秒" % [seconds / 60, seconds % 60]
	return "%d秒" % seconds


func _range(minimum: Variant, maximum: Variant) -> String:
	return _duration(minimum) if is_equal_approx(float(minimum), float(maximum)) else _duration(minimum) + "～" + _duration(maximum)
