class_name KingdomRaidTargetsView
extends VBoxContainer

## Filters a read-only server projection; only the host can open a target.
signal target_requested(id: String)

var _projection: Dictionary = {}
var _connected: bool = true
var _pending: bool = false
var _source_city: String = ""
var _selected_resource: String = ""
var _manual_resource: bool = false
var _setting: bool = false
var _resource_ids: Array[String] = []
var _choice: OptionButton
var _gap: Label
var _reference: Label
var _scope: Label
var _notice: Label
var _empty: Label
var _row_panels: Array[PanelContainer] = []
var _row_labels: Array[Label] = []
var _row_buttons: Array[Button] = []
var _notes: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_label(self, "寻找掠夺补给", "SectionLabel")
	_choice = OptionButton.new()
	_choice.custom_minimum_size.y = 44
	_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_choice)
	_choice.item_selected.connect(func(index: int) -> void:
		if not _setting and index >= 0 and index < _resource_ids.size():
			_selected_resource = _resource_ids[index]
			_manual_resource = true
			_render())
	_gap = _label(self, "", "SectionLabel")
	_reference = _label(self, "", "MutedLabel")
	_scope = _label(self, "", "MutedLabel")
	_notice = _label(self, "", "MutedLabel")
	_empty = _label(self, "", "MutedLabel")
	for index: int in range(5):
		var panel: PanelContainer = PanelContainer.new()
		panel.theme_type_variation = "InsetPanel"
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(panel)
		_row_panels.append(panel)
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(column)
		_row_labels.append(_label(column, ""))
		var button: Button = Button.new()
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = "UtilityButton"
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_open_target.bind(index))
		column.add_child(button)
		_row_buttons.append(button)
	_notes = _label(self, "", "MutedLabel")
	_render()


func update_view(view: Dictionary) -> void:
	var next: Variant = view.get("raidTargets", {})
	_projection = next if next is Dictionary else {}
	var source: String = str(_projection.get("sourceCity", ""))
	if source != _source_city:
		_source_city = source
		_selected_resource = ""
		_manual_resource = false
	if is_instance_valid(_choice):
		_render()


func set_navigation_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	if is_instance_valid(_choice):
		_render()


func _render() -> void:
	var supported: bool = bool(_projection.get("supported", false))
	_choice.visible = supported
	_gap.visible = supported
	_reference.visible = supported
	_scope.visible = supported
	_notice.visible = supported
	_sync_choices()
	var resource: Dictionary = _resource()
	var name: String = str(resource.get("name", _selected_resource))
	var gap: Variant = resource.get("gap", 0)
	_gap.text = "%s还缺 %s，查看可补充该资源的目标。" % [name, _amount(gap)] if _positive(gap) else "%s当前没有成长缺口，可切换资源寻找补给。" % name
	var reference: Dictionary = _dictionary(_projection.get("referenceArmy"))
	_reference.text = "城内参考兵力 %s 人 · 全部兵力理论运力 %s · 单队上限 %s 人\n%s" % [_amount(reference.get("count")), _amount(reference.get("capacity")), _amount(reference.get("limit")), str(reference.get("reason", ""))]
	_scope.text = "有限范围推荐：当前城横纵各%s格及已开放据点；未知金额须先精确侦察。\n点击后查看目标与配兵，收益预览以获胜为前提，不能视为已入库库存。" % _amount(_projection.get("radius"))
	_notice.text = "正在确认操作，完成后可查看目标。" if _pending else "连接后可打开目标。" if not _connected else ""
	_notice.visible = supported and not _notice.text.is_empty()
	var lists: Dictionary = _dictionary(_projection.get("lists"))
	var rows: Variant = lists.get(_selected_resource, [])
	var records: Array = rows if rows is Array else []
	for index: int in range(_row_panels.size()):
		var row: Dictionary = records[index] if index < records.size() and records[index] is Dictionary and supported else {}
		_row_panels[index].visible = not row.is_empty()
		_row_labels[index].text = _target_text(row, name)
		_row_buttons[index].text = "查看目标与配兵" if row.get("rewardKnown", false) else "查看目标与侦察"
		_row_buttons[index].set_meta("target", str(row.get("id", "")))
		_row_buttons[index].disabled = not _connected or _pending or str(row.get("id", "")).is_empty()
	_empty.visible = not supported or records.is_empty()
	_empty.text = "本机进度连接后可查看掠夺目标。" if _projection.is_empty() else "共享房间尚未开放私人野地掠夺推荐。" if not supported else "基础掠夺不含黄金，可通过任务、民政和金砖兑换筹备。" if _selected_resource == "gold" else "搜索范围内暂无符合条件的目标，可切换资源或在舆图继续查看。"
	var notes: Variant = _projection.get("notes", [])
	var lines: PackedStringArray = []
	if notes is Array:
		for line: Variant in notes:
			if line is String:
				lines.append(line)
	_notes.text = "\n".join(lines)
	_wire_focus()


func _sync_choices() -> void:
	var rows: Variant = _projection.get("resources", [])
	var records: Array = rows if rows is Array else []
	var next_ids: Array[String] = []
	for value: Variant in records:
		if value is Dictionary and not str(value.get("id", "")).is_empty():
			next_ids.append(str(value.id))
	_setting = true
	if next_ids != _resource_ids:
		_choice.clear()
		_resource_ids = next_ids
		for id: String in _resource_ids:
			_choice.add_item(id)
	if not _manual_resource or not _resource_ids.has(_selected_resource):
		_selected_resource = str(_projection.get("defaultResource", "food"))
	if not _resource_ids.has(_selected_resource) and not _resource_ids.is_empty():
		_selected_resource = _resource_ids[0]
	for index: int in range(_resource_ids.size()):
		var resource: Dictionary = _resource(_resource_ids[index])
		var gap: Variant = resource.get("gap", 0)
		_choice.set_item_text(index, str(resource.get("name", _resource_ids[index])) + (" · 缺 " + _amount(gap) if _positive(gap) else ""))
		if _resource_ids[index] == _selected_resource:
			_choice.select(index)
	_setting = false


func _resource(id: String = "") -> Dictionary:
	var selected: String = _selected_resource if id.is_empty() else id
	var rows: Variant = _projection.get("resources", [])
	if rows is Array:
		for row: Variant in rows:
			if row is Dictionary and str(row.get("id", "")) == selected:
				return row
	return {}


func _target_text(row: Dictionary, resource_name: String) -> String:
	if row.is_empty():
		return ""
	var distance: Variant = row.get("distance")
	var position: String = "（%s,%s）" % [_amount(row.get("x")), _amount(row.get("y"))]
	var text: String = "%s %s · %s级\n距当前城 %s 格" % [str(row.get("name", "目标")), position, _amount(row.get("level")), "%.1f" % float(distance) if _number(distance) else "未知"]
	if bool(row.get("rewardKnown", false)):
		text += " · 公开情报" if str(row.get("intelPrecision", "")) == "public" else " · 精确情报"
		text += "\n获胜基础%s %s" % [resource_name, _amount(row.get("potential"))]
		if _number(row.get("carried")):
			text += " · 参考可装载 %s\n全部资源参考装载 %s · 运力不足弃置 %s" % [_amount(row.get("carried")), _amount(row.get("cargoLoaded")), _amount(row.get("cargoDiscarded"))]
		else:
			text += "\n请先选择合法队伍，再核对运力与收益。"
	else:
		text += "\n地形对应%s资源；守军和可掠夺金额待精确侦察。" % resource_name
	if bool(row.get("repeated", false)):
		text += "\n此处已经掠夺，已知数值包含重复掠夺影响。" if bool(row.get("rewardKnown", false)) else "\n此处已经掠夺，收益会受重复掠夺影响。"
	return text


func _open_target(index: int) -> void:
	if index < 0 or index >= _row_buttons.size() or not _connected or _pending:
		return
	var button: Button = _row_buttons[index]
	var target: String = str(button.get_meta("target", ""))
	if button.is_visible_in_tree() and not button.disabled and not target.is_empty():
		target_requested.emit(target)


func _wire_focus() -> void:
	var buttons: Array[Control] = []
	if _choice.visible:
		buttons.append(_choice)
	for index: int in range(_row_buttons.size()):
		if _row_panels[index].visible and not _row_buttons[index].disabled:
			buttons.append(_row_buttons[index])
	for index: int in range(buttons.size()):
		buttons[index].focus_neighbor_top = buttons[maxi(0, index - 1)].get_path()
		buttons[index].focus_neighbor_bottom = buttons[mini(buttons.size() - 1, index + 1)].get_path()
		buttons[index].focus_previous = buttons[maxi(0, index - 1)].get_path()
		buttons[index].focus_next = buttons[mini(buttons.size() - 1, index + 1)].get_path()


func _label(parent: Node, text: String, variation: String = "") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0


func _positive(value: Variant) -> bool:
	return _number(value) and float(value) > 0.0


func _amount(value: Variant) -> String:
	return str(int(ceil(float(value)))) if _number(value) else "未知"
