class_name KingdomWarManagementDialog
extends AcceptDialog

## This panel selects original service quotes and sends canonical commands.
signal command_requested(type: String, args: Array)
signal battle_requested()

const TITLES: Dictionary = {"hospital": "伤兵治疗", "captives": "俘虏招降", "defenses": "城防建设", "defense": "守城备战", "civic": "安民政令", "wages": "俸禄与民情"}
const RESOURCE_NAMES: Dictionary = {"food": "粮草", "wood": "木材", "stone": "石料", "iron": "铁锭", "gold": "黄金"}

var _view: Dictionary = {}
var _section: String = "hospital"
var _connected: bool = true
var _pending: bool = false
var _updating: bool = false
var _error_message: String = ""
var _scroll: ScrollContainer
var _content: VBoxContainer
var _status: Label
var _info: Label
var _preview: Label
var _choice: OptionButton
var _mode: OptionButton
var _action: Button
var _all_button: Button
var _toggle: CheckButton
var _count: SpinBox
var _choice_ids: Array[String] = []
var _rows_box: VBoxContainer
var _rows_signature: String = ""
var _row_buttons: Dictionary = {}
var _row_labels: Dictionary = {}
var _policy_buttons: Dictionary = {}
var _general: OptionButton
var _general_ids: Array[String] = []
var _army_spins: Dictionary = {}
var _army_dirty: Dictionary = {}
var _army_labels: Dictionary = {}
var _defense_mode: OptionButton
var _orders: OptionButton
var _auto_resolve: CheckButton
var _doctrine_dirty: bool = false
var _doctrine_button: Button
var _drill_button: Button
var _start_button: Button
var _round_button: Button
var _resolve_button: Button
var _end_button: Button
var _battle_info: Label
var _report_info: Label
var _preparation_info: Label


func _ready() -> void:
	dialog_text = ""
	get_ok_button().text = "关闭"
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_build_section()


func show_section(section: String, view: Dictionary) -> void:
	_view = view
	_section = section if TITLES.has(section) else "hospital"
	_error_message = ""
	_build_section()
	_fit_window()
	popup_centered()


func update_view(view: Dictionary) -> void:
	_view = view
	if not is_instance_valid(_content):
		return
	_updating = true
	match _section:
		"hospital", "captives": _update_care()
		"defenses": _update_defenses()
		"defense": _update_defense()
		"civic": _update_civic()
		"wages": _update_wages()
	_updating = false
	_status.text = _error_message if not _error_message.is_empty() else "正在结算，请稍候…" if _pending else "请先连接规则服务" if not _connected else "当前城池：%s · 操作成功后自动保存" % str(_data().get("cityName", "当前城池"))
	_status.modulate = Color("e7bc72") if not _error_message.is_empty() else Color.WHITE


func set_command_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	update_view(_view)


func show_error(message: String) -> void:
	_error_message = message
	update_view(_view)


func acknowledge_command(connected: bool, pending: bool) -> void:
	_error_message = ""
	set_command_state(connected, pending)


func _data() -> Dictionary:
	return _view.get("warManagement", {})


func _part() -> Dictionary:
	return _data().get(_section, {})


func _label(text: String = "", font_size: int = 15) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 38.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


func _select() -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size.y = 36.0
	option.clip_text = true
	return option


func _spin(maximum: int, initial: int = 0) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = 0
	spin.max_value = maximum
	spin.step = 1
	spin.rounded = true
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _gate(button: BaseButton, reason: String = "") -> void:
	button.disabled = not _connected or _pending or not reason.is_empty()
	button.tooltip_text = reason


func _send(type: String, args: Array) -> void:
	if not _connected or _pending:
		return
	_error_message = ""
	_pending = true
	update_view(_view)
	command_requested.emit(type, args.duplicate(true))


func _send_quote(quote: Dictionary) -> void:
	if not str(quote.get("reason", "")).is_empty() or int(quote.get("count", 1)) < 1:
		return
	var command: Dictionary = quote.get("command", {})
	if not command.is_empty():
		_send(str(command.get("type", "")), command.get("args", []))


func _fit_window() -> void:
	var available: Vector2 = Vector2(get_tree().root.size)
	if get_parent() is Control:
		available = (get_parent() as Control).size
	var width: int = mini(740, maxi(280, int(available.x) - 40))
	var height: int = mini(720, maxi(280, int(available.y) - 80))
	_scroll.custom_minimum_size = Vector2(float(width - 48), float(height - 90))
	min_size = Vector2i(width, height)
	size = min_size
	position = Vector2i((available - Vector2(size)) / 2.0)


func _build_section() -> void:
	if not is_instance_valid(_content):
		return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_choice_ids.clear()
	_general_ids.clear()
	_army_spins.clear()
	_army_dirty.clear()
	_army_labels.clear()
	_row_buttons.clear()
	_row_labels.clear()
	_policy_buttons.clear()
	_rows_signature = ""
	_doctrine_dirty = false
	title = str(TITLES[_section])
	var navigation: GridContainer = GridContainer.new()
	navigation.columns = 3
	_content.add_child(navigation)
	for key: String in TITLES:
		var section: String = key
		var button: Button = _button(str(TITLES[key]), func() -> void: show_section(section, _view))
		button.disabled = key == _section
		navigation.add_child(button)
	_status = _label("", 13)
	_content.add_child(_status)
	_info = _label()
	_content.add_child(_info)
	match _section:
		"hospital", "captives": _build_care()
		"defenses": _build_defenses()
		"defense": _build_defense()
		"civic": _build_civic()
		"wages": _build_wages()
	update_view(_view)


func _format(values: Dictionary, names: Dictionary = RESOURCE_NAMES) -> String:
	var pieces: PackedStringArray = []
	for key: String in values:
		if int(values[key]) != 0:
			pieces.append("%s %d" % [str(names.get(key, key)), int(values[key])])
	return "、".join(pieces) if not pieces.is_empty() else "无"


func _unit_names() -> Dictionary:
	return _data().get("unitNames", {})


func _remaining(at: float) -> String:
	var seconds: int = maxi(0, int(ceil((at - float(_data().get("now", 0))) / 1000.0)))
	return "%d分%02d秒" % [seconds / 60, seconds % 60]


func _sync_choices(rows: Array) -> void:
	var ids: Array[String] = []
	for row: Dictionary in rows:
		ids.append(str(row.get("id", "")))
	if ids == _choice_ids:
		return
	var previous: String = _choice_ids[_choice.selected] if _choice.selected >= 0 and _choice.selected < _choice_ids.size() else ""
	_choice.clear()
	_choice_ids = ids
	for row: Dictionary in rows:
		_choice.add_item(str(row.get("name", row.get("id", ""))))
	if ids.has(previous):
		_choice.select(ids.find(previous))
	elif not ids.is_empty():
		_choice.select(0)


func _selected_row() -> Dictionary:
	var rows: Array = _part().get("rows", [])
	return rows[_choice.selected] if _choice.selected >= 0 and _choice.selected < rows.size() else {}


func _care_quote() -> Dictionary:
	var choices: Array = _selected_row().get("choices", [])
	return choices[_mode.selected] if _mode.selected >= 0 and _mode.selected < choices.size() else {}


func _build_care() -> void:
	_choice = _select()
	_content.add_child(_choice)
	_choice.item_selected.connect(func(_index: int) -> void: update_view(_view))
	_mode = _select()
	_mode.add_item("全部本类")
	_mode.add_item("当前可负担方案")
	_content.add_child(_mode)
	_mode.item_selected.connect(func(_index: int) -> void: update_view(_view))
	_preview = _label()
	_content.add_child(_preview)
	_action = _button("治疗本类" if _section == "hospital" else "招降本类", func() -> void: _send_quote(_care_quote()))
	_content.add_child(_action)
	_all_button = _button("全部伤兵一键治疗" if _section == "hospital" else "可招降俘虏一键招降", func() -> void: _send_quote(_part().get("quote", {})))
	_content.add_child(_all_button)
	if _section == "hospital":
		_toggle = CheckButton.new()
		_toggle.text = "自动治疗（黄金足够时逐类治疗）"
		_toggle.toggled.connect(func(enabled: bool) -> void:
			if not _updating: _send("setAutoHeal", [enabled]))
		_content.add_child(_toggle)
	else:
		_content.add_child(_label("招降士卒需满足兵种条件、空闲人口及资源。俘虏将领请到将领页面处理。", 13))


func _update_care() -> void:
	var part: Dictionary = _part()
	var all: Dictionary = part.get("quote", {})
	var rows: Array = part.get("rows", [])
	_sync_choices(rows)
	var quote: Dictionary = _care_quote()
	var row: Dictionary = _selected_row()
	var count: int = int(quote.get("count", 0))
	var cost: Dictionary = {"gold": quote.get("gold", 0)} if _section == "hospital" else quote.get("cost", {})
	var total_cost: Dictionary = {"gold": all.get("gold", 0)} if _section == "hospital" else all.get("cost", {})
	_info.text = "待治疗 %d 人 · 全部治疗：%s" % [int(all.get("available", 0)), _format(total_cost)] if _section == "hospital" else "一键可招降 %d 人 · 占用人口 %d · 费用：%s" % [int(all.get("count", 0)), int(all.get("people", 0)), _format(total_cost)]
	if not str(all.get("reason", "")).is_empty(): _info.text += "\n一键操作：" + str(all.reason)
	var reason: String = str(quote.get("reason", "")) if not quote.is_empty() else "当前没有可处理的士卒"
	if count < 1 and reason.is_empty():
		reason = "当前可处理人数为 0"
	_preview.text = "%s：本类共 %d 人，本次 %d 人\n费用：%s%s" % [str(row.get("name", "士卒")), int(row.get("count", 0) if _section == "hospital" else row.get("available", 0)), count, _format(cost), "\n" + reason if not reason.is_empty() else ""]
	_gate(_action, reason)
	_gate(_all_button, str(all.get("reason", "暂无可处理士卒")))
	_choice.disabled = _pending or not _connected or rows.is_empty()
	_mode.disabled = _choice.disabled
	if _section == "hospital":
		_toggle.set_pressed_no_signal(bool(part.get("autoHeal", false)))
		_gate(_toggle)
		var last: Variant = part.get("lastAuto")
		if last is Dictionary:
			_info.text += "\n最近自动治疗 %d 人，花费黄金 %d，剩余伤兵 %d" % [int(last.get("healed", 0)), int(last.get("gold", 0)), int(last.get("remaining", 0))]


func _build_defenses() -> void:
	_choice = _select()
	_content.add_child(_choice)
	_choice.item_selected.connect(func(_index: int) -> void: update_view(_view))
	_count = _spin(10000, 1)
	_count.min_value = 1
	_content.add_child(_label("建设数量（1–10000）", 13))
	_content.add_child(_count)
	_preview = _label()
	_content.add_child(_preview)
	_action = _button("提交城防建设", func() -> void:
		var row: Dictionary = _selected_row()
		if not str(row.get("requirement", "")).is_empty() or not _part().get("queue", []).is_empty(): return
		_send("buildDefense", [str(row.get("id", "")), _draft_int(_count)]))
	_content.add_child(_action)
	_content.add_child(_label("这里显示手册的单个工事消耗和前置条件；所选数量的资源、空间和工时由原规则服务最终校验。", 13))


func _draft_int(spin: SpinBox) -> int:
	var raw: String = spin.get_line_edit().text.strip_edges()
	var amount: int = int(float(raw)) if raw.is_valid_float() else int(spin.value)
	return clampi(amount, int(spin.min_value), int(spin.max_value))


func _update_defenses() -> void:
	var part: Dictionary = _part()
	var rows: Array = part.get("rows", [])
	_sync_choices(rows)
	var row: Dictionary = _selected_row()
	var queue: Array = part.get("queue", [])
	_info.text = "城防空间 %d / %d" % [int(part.get("used", 0)), int(part.get("capacity", 0))]
	for job: Dictionary in queue:
		_info.text += "\n工队：%s ×%d，剩余 %s" % [str(job.get("id", "")), int(job.get("count", 0)), _remaining(float(job.get("end", 0)))]
	var reason: String = str(row.get("requirement", ""))
	if not queue.is_empty(): reason = "城防工队正在忙碌"
	if row.is_empty(): reason = "暂无城防资料"
	_preview.text = "%s：现有 %d，守城战中 %d\n单个成本：%s\n单个空间：%d · 基础工时：%d秒\n前置条件：%s%s" % [str(row.get("name", "城防")), int(row.get("count", 0)), int(row.get("held", 0)), _format(row.get("unitCost", {})), int(row.get("area", 0)), int(row.get("baseSeconds", 0)), str(row.get("requirementsText", "无")), "\n" + reason if not reason.is_empty() else ""]
	_gate(_action, reason)
	_choice.disabled = _pending or not _connected
	_count.editable = not _pending and _connected


func _build_defense() -> void:
	_choice = _select()
	for profile: Dictionary in _part().get("profiles", []):
		_choice_ids.append(str(profile.get("id", "")))
		_choice.add_item(str(profile.get("name", "黄巾挑战")))
	_content.add_child(_choice)
	_choice.item_selected.connect(func(_index: int) -> void: _sync_levels(); update_view(_view))
	_mode = _select()
	_content.add_child(_mode)
	_mode.item_selected.connect(func(_index: int) -> void: update_view(_view))
	_sync_levels()
	_preview = _label()
	_content.add_child(_preview)
	_action = _button("发起黄巾挑战", func() -> void:
		if not _private_block().is_empty(): return
		_send_quote(_challenge_quote()))
	_content.add_child(_action)
	_toggle = CheckButton.new()
	_toggle.text = "开启周期黄巾来袭"
	_toggle.toggled.connect(func(enabled: bool) -> void:
		if not _updating and _private_block().is_empty(): _send("setAutoCityDefense", [enabled]))
	_content.add_child(_toggle)
	_content.add_child(_label("守城预设（共享房间也用于抵御玩家进攻）", 17))
	_defense_mode = _select()
	_defense_mode.add_item("驻军出城迎战")
	_defense_mode.add_item("驻军留城，工事先战")
	_defense_mode.item_selected.connect(func(_index: int) -> void: _doctrine_dirty = true)
	_content.add_child(_defense_mode)
	_auto_resolve = CheckButton.new()
	_auto_resolve.text = "本机守城开始后自动结算全部回合"
	_auto_resolve.toggled.connect(func(_enabled: bool) -> void:
		if not _updating: _doctrine_dirty = true)
	_content.add_child(_auto_resolve)
	_orders = _select()
	for text: String in ["保留各兵种命令", "全部前进", "全部固守", "全部后退"]:
		_orders.add_item(text)
	_orders.item_selected.connect(func(_index: int) -> void: _doctrine_dirty = true)
	_content.add_child(_orders)
	_doctrine_button = _button("保存守城预设", _save_doctrine)
	_content.add_child(_doctrine_button)
	_general = _select()
	_content.add_child(_label("守将（城守可参战，任职主将或军师需先卸任）", 13))
	_content.add_child(_general)
	_general.item_selected.connect(func(_index: int) -> void: update_view(_view))
	var army_grid: GridContainer = GridContainer.new()
	army_grid.columns = 2
	_content.add_child(army_grid)
	for row: Dictionary in _part().get("army", []):
		var id: String = str(row.get("id", ""))
		var label: Label = _label()
		_army_labels[id] = label
		army_grid.add_child(label)
		var spin: SpinBox = _spin(int(row.get("available", 0)), int(row.get("available", 0)))
		spin.custom_minimum_size.x = 90
		_army_spins[id] = spin
		army_grid.add_child(spin)
		spin.value_changed.connect(func(_value: float) -> void:
			if not _updating: _army_dirty[id] = true)
		spin.get_line_edit().text_changed.connect(func(_text: String) -> void:
			if not _updating: _army_dirty[id] = true)
	_preparation_info = _label("", 13)
	_content.add_child(_preparation_info)
	_drill_button = _button("开始守城演练（不消耗兵力物资）", func() -> void: _start_defense(true))
	_content.add_child(_drill_button)
	_start_button = _button("敌军抵达后开始守城", func() -> void: _start_defense(false))
	_content.add_child(_start_button)
	_battle_info = _label()
	_content.add_child(_battle_info)
	_round_button = _button("推进守城下一回合", func() -> void: _defense_command("cityDefenseRound"))
	_content.add_child(_round_button)
	_resolve_button = _button("自动结算剩余守城回合", func() -> void: _defense_command("resolveCityDefense"))
	_content.add_child(_resolve_button)
	_end_button = _button("退出演练", func() -> void:
		var battle: Variant = _part().get("battle")
		if battle is Dictionary and bool(battle.get("drill", false)): _defense_command("endDefenseDrill"))
	_content.add_child(_end_button)
	_report_info = _label()
	_content.add_child(_report_info)


func _private_block() -> String:
	return str(_part().get("reason", "私人守城不可用")) if bool(_part().get("restricted", false)) else ""


func _profile() -> Dictionary:
	var profiles: Array = _part().get("profiles", [])
	return profiles[_choice.selected] if _choice.selected >= 0 and _choice.selected < profiles.size() else {}


func _sync_levels() -> void:
	if not is_instance_valid(_mode): return
	var previous: int = maxi(0, _mode.selected)
	_mode.clear()
	for quote: Dictionary in _profile().get("quotes", []):
		_mode.add_item("难度 %d" % int(quote.get("level", 0)))
	if _mode.item_count > 0: _mode.select(mini(previous, _mode.item_count - 1))


func _challenge_quote() -> Dictionary:
	var quotes: Array = _profile().get("quotes", [])
	return quotes[_mode.selected] if _mode.selected >= 0 and _mode.selected < quotes.size() else {}


func _save_doctrine() -> void:
	if _part().get("battle") is Dictionary: return
	var doctrine: Dictionary = _part().get("doctrine", {}).duplicate(true)
	doctrine["mode"] = "inside" if _defense_mode.selected == 1 else "field"
	doctrine["autoResolve"] = _auto_resolve.button_pressed
	if _orders.selected > 0:
		var selected: String = ["", "advance", "hold", "fallback"][_orders.selected]
		for id: String in doctrine.get("orders", {}):
			doctrine["orders"][id]["command"] = selected
	_send("setDefenseDoctrine", [doctrine])


func _general_reason() -> String:
	var generals: Array = _part().get("generals", [])
	return str(generals[_general.selected].get("reason", "")) if _general.selected >= 0 and _general.selected < generals.size() else "请选择已招募的守将"


func _start_defense(drill: bool) -> void:
	if not _private_block().is_empty() or not str(_part().get("startReason", "")).is_empty() or not _general_reason().is_empty(): return
	if not drill:
		var incoming: Variant = _part().get("incoming")
		if not incoming is Dictionary or float(incoming.get("arriveAt", 0)) > float(_data().get("now", 0)): return
	var army: Dictionary = {}
	for id: String in _army_spins:
		army[id] = _draft_int(_army_spins[id])
	_send("startCityDefense", [drill, _general_ids[_general.selected], army])


func _defense_command(type: String) -> void:
	if _private_block().is_empty() and _part().get("battle") is Dictionary:
		_send(type, [])


func _update_defense() -> void:
	var part: Dictionary = _part()
	var blocked: String = _private_block()
	var quote: Dictionary = _challenge_quote()
	var incoming: Variant = part.get("incoming")
	_info.text = blocked if not blocked.is_empty() else "已守城获胜 %d 次 · 黄巾波次 %d" % [int(part.get("wins", 0)), int(part.get("wave", 0))]
	if incoming is Dictionary:
		_info.text += "\n%s：%s" % [str(incoming.get("name", "敌军")), "已抵达，可开始守城" if float(incoming.get("arriveAt", 0)) <= float(_data().get("now", 0)) else "距抵达 " + _remaining(float(incoming.get("arriveAt", 0)))]
		if incoming.get("army") is Dictionary:
			var details: PackedStringArray = []
			for id: String in incoming.army:
				var n: Variant = incoming.army[id]
				details.append("%s %s" % [str(_unit_names().get(id, id)), "%d–%d" % [int(n.get("min", 0)), int(n.get("max", 0))] if n is Dictionary else str(int(n))])
			_info.text += "\n烽火台情报：" + "、".join(details)
		elif not incoming.get("types", []).is_empty():
			var types: PackedStringArray = []
			for id: String in incoming.types: types.append(str(_unit_names().get(id, id)))
			_info.text += "\n烽火台发现兵种：" + "、".join(types)
		else: _info.text += "\n烽火台尚未获知敌军兵种与数量"
	elif float(part.get("nextAt", 0)) > 0 and bool(part.get("autoEnabled", false)):
		_info.text += "\n下次周期来袭：" + _remaining(float(part.get("nextAt", 0)))
	var challenge_reason: String = blocked if not blocked.is_empty() else str(quote.get("reason", "暂无可用挑战"))
	_preview.text = "%s\n挑战兵力：%s\n费用：%s · 胜利奖励：%s\n预警 %d 秒%s" % [str(quote.get("description", "")), _format(quote.get("army", {}), _unit_names()), _format(quote.get("cost", {})), _format(quote.get("reward", {})), int(quote.get("warningSeconds", 0)), "\n" + challenge_reason if not challenge_reason.is_empty() else ""]
	_gate(_action, challenge_reason)
	_choice.disabled = _pending or not _connected or not blocked.is_empty()
	_mode.disabled = _choice.disabled
	_toggle.set_pressed_no_signal(bool(part.get("autoEnabled", false)))
	_gate(_toggle, blocked if not blocked.is_empty() else "需官府 2 级并赢得一次出征" if not bool(part.get("unlocked", false)) and not _toggle.button_pressed else "")
	var battle: Variant = part.get("battle")
	var active: bool = battle is Dictionary
	var doctrine: Dictionary = part.get("doctrine", {})
	if not _doctrine_dirty:
		_defense_mode.select(1 if doctrine.get("mode", "field") == "inside" else 0)
		_auto_resolve.set_pressed_no_signal(bool(doctrine.get("autoResolve", true)))
	var edit_reason: String = "请先结束正在进行的守城战" if active else ""
	_gate(_doctrine_button, edit_reason)
	_gate(_auto_resolve, edit_reason)
	_defense_mode.disabled = _doctrine_button.disabled
	_orders.disabled = _doctrine_button.disabled
	var generals: Array = part.get("generals", [])
	var ids: Array[String] = []
	for general: Dictionary in generals: ids.append(str(general.get("id", "")))
	if ids != _general_ids:
		var previous: String = _general_ids[_general.selected] if _general.selected >= 0 and _general.selected < _general_ids.size() else str(part.get("governor", ""))
		_general.clear()
		_general_ids = ids
		for general: Dictionary in generals: _general.add_item(str(general.get("name", "将领")))
		if ids.has(previous): _general.select(ids.find(previous))
	var start_reason: String = blocked if not blocked.is_empty() else str(part.get("startReason", ""))
	if start_reason.is_empty(): start_reason = _general_reason()
	_preparation_info.text = start_reason if not start_reason.is_empty() else "所选驻军参加守城，未选部队留城。预设修改后请先保存，再开始。"
	_gate(_drill_button, start_reason)
	_gate(_start_button, start_reason if not start_reason.is_empty() else "敌军尚未抵达" if not incoming is Dictionary or float(incoming.get("arriveAt", 0)) > float(_data().get("now", 0)) else "")
	_general.disabled = _pending or not _connected or active or not blocked.is_empty()
	for row: Dictionary in part.get("army", []):
		var id: String = str(row.get("id", ""))
		if not _army_spins.has(id): continue
		var spin: SpinBox = _army_spins[id]
		var raw: String = spin.get_line_edit().text
		spin.max_value = int(row.get("available", 0))
		if _army_dirty.has(id): spin.get_line_edit().text = raw
		else: spin.value = int(row.get("available", 0))
		spin.editable = not _general.disabled
		(_army_labels[id] as Label).text = "%s（留城 %d）" % [str(row.get("name", id)), int(row.get("available", 0))]
	var round_reason: String = blocked if not blocked.is_empty() else "当前没有守城战" if not active else ""
	_gate(_round_button, round_reason)
	_gate(_resolve_button, round_reason)
	_gate(_end_button, round_reason if not round_reason.is_empty() else "正式守城战需完成结算" if not bool(battle.get("drill", false)) else "")
	_battle_info.text = ""
	if active:
		_battle_info.text = "%s · 第 %d 回合 · 城门耐久 %d / %d\n%s" % ["演练" if bool(battle.get("drill", false)) else "正式守城", int(battle.get("round", 0)), int(battle.get("gateHp", 0)), int(battle.get("gateMax", 0)), "\n".join(PackedStringArray(battle.get("log", [])))]
	var report: Variant = part.get("report")
	_report_info.text = ""
	if report is Dictionary:
		_report_info.text = "%s%s · %d 回合\n阵亡：%s\n伤兵：%s\n返回驻军：%s\n城防损失：%s\n被掠夺：%s" % ["演练结果 · " if bool(report.get("drill", false)) else "战后结算 · ", "胜利" if bool(report.get("won", false)) else "失守", int(report.get("round", 0)), _format(report.get("lost", {}), _unit_names()), _format(report.get("wounded", {}), _unit_names()), _format(report.get("back", {}), _unit_names()), _format(report.get("defenseLost", {})), _format(report.get("robbed", {}))]
		var receipt: Variant = report.get("resourceReceipt")
		if receipt is Dictionary:
			_report_info.text += "\n实际入库：" + _format(receipt.get("received", {}))
			if not _format(receipt.get("overflow", {})) == "无": _report_info.text += "\n仓满未入库：" + _format(receipt.get("overflow", {}))


func _build_civic() -> void:
	_rows_box = VBoxContainer.new()
	_content.add_child(_rows_box)
	_rebuild_civic()


func _rebuild_civic() -> void:
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_row_buttons.clear()
	_row_labels.clear()
	var ids: PackedStringArray = []
	for row: Dictionary in _part().get("rows", []):
		var id: String = str(row.get("id", ""))
		ids.append(id)
		var label: Label = _label()
		_row_labels[id] = label
		_rows_box.add_child(label)
		var button: Button = _button(str(row.get("name", id)), func() -> void: _send_civic(id))
		_row_buttons[id] = button
		_rows_box.add_child(button)
	_rows_signature = "|".join(ids)


func _send_civic(id: String) -> void:
	for row: Dictionary in _part().get("rows", []):
		if str(row.get("id", "")) == id and bool(row.get("enabled", false)):
			_send_quote(row)
			return


func _update_civic() -> void:
	var part: Dictionary = _part()
	_info.text = "人口 %d · 民心 %d · 民怨 %d" % [int(part.get("population", 0)), int(part.get("morale", 0)), int(part.get("unrest", 0))]
	if float(part.get("wardUntil", 0)) > float(_data().get("now", 0)): _info.text += "\n祭天灾害减免剩余：" + _remaining(float(part.wardUntil))
	if float(part.get("blessingUntil", 0)) > float(_data().get("now", 0)): _info.text += "\n祭天民心加护剩余：" + _remaining(float(part.blessingUntil))
	var ids: PackedStringArray = []
	for row: Dictionary in part.get("rows", []): ids.append(str(row.get("id", "")))
	if "|".join(ids) != _rows_signature: _rebuild_civic()
	for row: Dictionary in part.get("rows", []):
		var id: String = str(row.get("id", ""))
		var effects: Dictionary = row.get("effects", {})
		var reason: String = str(row.get("reason", ""))
		(_row_labels[id] as Label).text = "%s · 费用：%s\n获得：%s · 民心 %+d / 民怨 %+d / 人口 %+d%s" % [str(row.get("name", id)), _format(row.get("cost", {})), _format(row.get("reward", {})), int(effects.get("morale", 0)), int(effects.get("unrest", 0)), int(effects.get("population", 0)), "\n" + reason if not reason.is_empty() else ""]
		_gate(_row_buttons[id], reason if not reason.is_empty() else "当前不可执行" if not bool(row.get("enabled", false)) else "")


func _build_wages() -> void:
	_all_button = _button("一键补发全部欠薪", func() -> void: _send_quote(_part().get("quote", {})))
	_content.add_child(_all_button)
	for entry: Array in [["eventsEnabled", "启用民情事件"], ["autoRelief", "资源足够时自动赈济"]]:
		var kind: String = str(entry[0])
		var button: CheckButton = CheckButton.new()
		button.text = str(entry[1])
		button.toggled.connect(func(enabled: bool) -> void:
			if not _updating: _send("setGovernancePolicy", [kind, enabled]))
		_policy_buttons[kind] = button
		_content.add_child(button)
	_rows_box = VBoxContainer.new()
	_content.add_child(_rows_box)
	_rebuild_wages()
	_preview = _label()
	_content.add_child(_preview)


func _rebuild_wages() -> void:
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_row_buttons.clear()
	_row_labels.clear()
	var ids: PackedStringArray = []
	for row: Dictionary in _part().get("rows", []):
		var id: String = str(row.get("id", ""))
		ids.append(id)
		var label: Label = _label()
		_row_labels[id] = label
		_rows_box.add_child(label)
		var button: Button = _button("补发「%s」欠薪" % str(row.get("name", id)), func() -> void: _send_salary(id))
		_row_buttons[id] = button
		_rows_box.add_child(button)
	_rows_signature = "|".join(ids)


func _send_salary(id: String) -> void:
	for row: Dictionary in _part().get("rows", []):
		if str(row.get("id", "")) == id:
			_send_quote(row.get("quote", {}))
			return


func _log_text(rows: Array) -> String:
	var result: PackedStringArray = []
	for row: Variant in rows.slice(maxi(0, rows.size() - 5)):
		result.append(str(row.get("text", row.get("message", row))) if row is Dictionary else str(row))
	return "\n".join(result)


func _update_wages() -> void:
	var part: Dictionary = _part()
	var status: Dictionary = part.get("status", {})
	var quote: Dictionary = part.get("quote", {})
	_info.text = "每小时薪俸 %d 黄金 · 累计欠薪 %d 黄金\n民心目标 %d%s" % [int(status.get("wages", 0)), int(status.get("owed", 0)), int(status.get("moraleTarget", 0)), "\n" + "\n".join(PackedStringArray(status.get("warnings", []))) if not status.get("warnings", []).is_empty() else ""]
	_info.text += "\n本次一键补发：%d 黄金%s" % [int(quote.get("cost", 0)), "\n" + str(quote.reason) if not str(quote.get("reason", "")).is_empty() else ""]
	_gate(_all_button, str(quote.get("reason", "没有待补发薪俸")))
	for kind: String in _policy_buttons:
		var button: CheckButton = _policy_buttons[kind]
		button.set_pressed_no_signal(bool(part.get("policies", {}).get(kind, false)))
		_gate(button)
	var ids: PackedStringArray = []
	for row: Dictionary in part.get("rows", []): ids.append(str(row.get("id", "")))
	if "|".join(ids) != _rows_signature: _rebuild_wages()
	for row: Dictionary in part.get("rows", []):
		var id: String = str(row.get("id", ""))
		var row_quote: Dictionary = row.get("quote", {})
		(_row_labels[id] as Label).text = "%s · 每小时 %d 黄金 · 欠薪 %d · 忠诚 %d\n本次补发：%d 黄金%s" % [str(row.get("name", id)), int(row.get("wage", 0)), int(row.get("owed", 0)), int(row.get("loyalty", 0)), int(row_quote.get("cost", 0)), "\n" + str(row_quote.reason) if not str(row_quote.get("reason", "")).is_empty() else ""]
		_gate(_row_buttons[id], str(row.get("quote", {}).get("reason", "没有待补发薪俸")))
	_preview.text = "民情记录\n%s\n薪俸记录\n%s" % [_log_text(part.get("log", [])), _log_text(part.get("salaryLog", []))]
