class_name KingdomGrowthRouteView
extends PanelContainer

## A stable route card. The host owns navigation and confirmation; this card spends nothing.
signal navigate_requested(route: String, target: String)
signal speedup_requested(item_id: String, target_key: String)

# Immediate supplies and resource recovery are useful before spending on a gap.
# This only orders the service's advice; it never derives a reward or a rule.
const ADVICE_PRIORITY: Array[String] = ["unclaimed-gifts", "earned-rewards", "resource-recovery", "county-preparation"]

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
var _speedup_confirm: Button
var _speedup_action: Button
var _advice_content: VBoxContainer
var _advice_heading: Label
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
	_speedup_confirm = _button(content, "确认使用这件加速", true)
	_speedup_confirm.tooltip_text = "打开加速预览，核对消耗和剩余时间后再确认。"
	_speedup_confirm.pressed.connect(_request_speedup)
	_speedup_action = _button(content, "查看已入库加速")
	_speedup_action.pressed.connect(_navigate.bind(_speedup_action))
	_advice_content = VBoxContainer.new()
	_advice_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_advice_content)
	_advice_heading = _label(_advice_content, "", "SectionLabel")
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
	_render_advice(growth.get("advice", []), shared)
	_status.text = "正在确认操作，路线在确认后更新。" if _pending else "连接后可前往当前一步并预览加速。" if not _connected else "推荐加速先预览消耗与剩余时间，再由你确认使用。"
	_status.visible = not shared
	_wire_focus()


func _render_advice(source: Array, shared: bool) -> void:
	var records: Array[Dictionary] = []
	if not shared:
		# Keep all advice discoverable. Priority is presentation only and ties retain
		# the canonical projection's order; new advice IDs remain visible as well.
		for id: String in ADVICE_PRIORITY:
			for value: Variant in source:
				if value is Dictionary and str(value.get("id", "")) == id:
					records.append(value)
		for value: Variant in source:
			if value is Dictionary and not ADVICE_PRIORITY.has(str(value.get("id", ""))):
				records.append(value)
	# Reuse controls on refresh so polling does not discard focus or scroll state.
	while _advice.size() < records.size():
		_advice.append(_label(_advice_content, "", "MutedLabel"))
		var action: Button = _button(_advice_content, "查看建议")
		action.pressed.connect(_navigate.bind(action))
		_advice_actions.append(action)
	_advice_content.visible = not records.is_empty()
	_advice_heading.text = "可用建议 · %d 项" % records.size()
	for index: int in range(_advice.size()):
		var record: Dictionary = records[index] if index < records.size() else {}
		_advice[index].text = str(record.get("text", ""))
		_advice[index].visible = not record.is_empty()
		_set_navigation(_advice_actions[index], record.get("navigate", {}), not record.is_empty())


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
	var usable: Dictionary = _speedup_suggestion()
	_speedup_confirm.visible = not shared and count > 0 and not usable.is_empty()
	_speedup_confirm.disabled = not _connected or _pending or shared or usable.is_empty()
	var navigate: Dictionary = suggestion.get("navigate", {"route": "inventory", "target": "", "label": "查看已入库加速"})
	_set_navigation(_speedup_action, navigate, not shared and count > 0)


func _speedup_suggestion() -> Dictionary:
	var growth: Dictionary = _view.get("growth", {}) if _view.get("growth") is Dictionary else {}
	if bool(growth.get("shared", false)):
		return {}
	var speedup: Dictionary = growth.get("speedup", {}) if growth.get("speedup") is Dictionary else {}
	var suggestion: Dictionary = speedup.get("suggestion", {}) if speedup.get("suggestion") is Dictionary else {}
	var item_id: Variant = suggestion.get("itemId")
	var target_key: Variant = suggestion.get("targetKey")
	var held: Variant = suggestion.get("count")
	if not item_id is String or str(item_id).strip_edges().is_empty() or not target_key is String or str(target_key).strip_edges().is_empty():
		return {}
	if not (held is int or held is float) or not is_finite(float(held)) or float(held) <= 0.0 or float(held) != floor(float(held)):
		return {}
	if not str(suggestion.get("reason", "")).is_empty():
		return {}
	return suggestion


func _request_speedup() -> void:
	if not _connected or _pending or not is_instance_valid(_speedup_confirm) or _speedup_confirm.disabled or not _speedup_confirm.is_visible_in_tree():
		return
	# Resolve the latest projection again; the host must quote and confirm the
	# exact canonical item/queue key before issuing any consuming command.
	var suggestion: Dictionary = _speedup_suggestion()
	if not suggestion.is_empty():
		speedup_requested.emit(str(suggestion.itemId), str(suggestion.targetKey))


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
	var candidates: Array[Button] = [_more, _current, _speedup_confirm, _speedup_action]
	candidates.append_array(_advice_actions)
	for button: Button in candidates:
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
	button.custom_minimum_size = Vector2(0, 44)
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
