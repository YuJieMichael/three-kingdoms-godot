class_name KingdomDispatchDialog
extends KingdomScoutingDialog

## One actor-safe PvE window. Every consumption command comes from a current quote.
var _layout: VBoxContainer
var _tabs: TabContainer
var _march_scroll: ScrollContainer
var _march_content: VBoxContainer
var _march_footer: VBoxContainer
var _scout_footer: VBoxContainer
var _march_intro: Label
var _march_intel: KingdomIntelPanel
var _general: OptionButton
var _general_signature: String = ""
var _army_rows: VBoxContainer
var _army_inputs: Dictionary = {}
var _army_labels: Dictionary = {}
var _army_details: Dictionary = {}
var _army_stock: Dictionary = {}
var _mode: OptionButton
var _occupy_return: CheckBox
var _march_preview: Button
var _march_confirm: Button
var _march_quote_label: Label
var _march_status: Label
var _march_signature: String = ""
var _march_quote_id: String = ""
var _march_quote_fingerprint: String = ""
var _march_quote: Dictionary = {}
var _march_command: Dictionary = {}
var _march_busy: bool = false
var _march_setting: bool = false
var _march_error: String = ""
var _fit_scheduled: bool = false


func _ready() -> void:
	super._ready()
	title = "战前准备"
	# Fixed viewport-sized shell; inactive wrapped tab labels must not grow
	# the Window before their container receives its final width.
	wrap_controls = false
	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 10)
	add_child(_layout)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.add_child(_tabs)
	_march_scroll = ScrollContainer.new()
	_march_scroll.name = "出征"
	_march_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_march_scroll.follow_focus = true
	_tabs.add_child(_march_scroll)
	_march_content = VBoxContainer.new()
	_march_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_march_content.add_theme_constant_override("separation", 12)
	_march_scroll.add_child(_march_content)
	_march_intro = _march_label(_march_content, "请选择目标", "SectionLabel")
	_march_intel = IntelScript.new() as KingdomIntelPanel
	_march_content.add_child(_march_intel)
	var scout_link: Button = _march_button(_march_content, "先侦察目标", false)
	scout_link.pressed.connect(show_tab.bind("scout"))
	_march_label(_march_content, "将领与兵力", "SectionLabel")
	_march_label(_march_content, "按兵种填写派遣人数，填0则不携带。较慢兵种会影响整队行军，实际耗时以预览为准。", "MutedLabel")
	_general = OptionButton.new()
	_general.custom_minimum_size.y = 44
	_general.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_march_content.add_child(_general)
	_general.item_selected.connect(func(_index: int) -> void: _march_input_changed())
	_army_rows = VBoxContainer.new()
	_army_rows.add_theme_constant_override("separation", 8)
	_march_content.add_child(_army_rows)
	_march_label(_march_content, "出征方式", "SectionLabel")
	_mode = OptionButton.new()
	_mode.add_item("掠夺")
	_mode.add_item("占领")
	_mode.custom_minimum_size.y = 44
	_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_march_content.add_child(_mode)
	_mode.item_selected.connect(func(_index: int) -> void: _march_input_changed())
	_occupy_return = CheckBox.new()
	_occupy_return.text = "占领后返回（不选则驻扎）"
	_occupy_return.custom_minimum_size.y = 44
	_occupy_return.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_march_content.add_child(_occupy_return)
	_occupy_return.toggled.connect(func(_value: bool) -> void: _march_input_changed())
	_march_label(_march_content, "未知守军不表示没有守军。出征预览不推算胜率；抵达后按实际战斗结果结算。", "MutedLabel")
	# Retain the proven scout component, but move its actions out of the scroll.
	_scroll.reparent(_tabs)
	_scroll.name = "侦察"
	_scroll.custom_minimum_size = Vector2.ZERO
	_scout_footer = VBoxContainer.new()
	_scout_footer.add_theme_constant_override("separation", 8)
	_layout.add_child(_scout_footer)
	_quote_label.reparent(_scout_footer)
	var scout_actions: HBoxContainer = HBoxContainer.new()
	_scout_footer.add_child(scout_actions)
	_preview.reparent(scout_actions)
	_confirm.reparent(scout_actions)
	_confirm.text = "派遣斥候"
	_status.reparent(_scout_footer)
	_march_footer = VBoxContainer.new()
	_march_footer.add_theme_constant_override("separation", 8)
	_layout.add_child(_march_footer)
	_march_quote_label = _march_label(_march_footer, "先预览当前粮草费用、行军耗时与抵达时间。", "MutedLabel")
	var march_actions: HBoxContainer = HBoxContainer.new()
	_march_footer.add_child(march_actions)
	_march_preview = _march_button(march_actions, "预览出征", false)
	_march_preview.pressed.connect(_request_march_quote)
	_march_confirm = _march_button(march_actions, "确认派遣", true)
	_march_confirm.pressed.connect(_submit_march)
	_march_status = _march_label(_march_footer, "", "MutedLabel")
	_tabs.tab_changed.connect(_tab_changed)
	_sync_march_inputs()
	_tab_changed(0)
	_render_march()
	_fit_window()


func show_tab(tab: String) -> void:
	if is_instance_valid(_tabs):
		_tabs.current_tab = 1 if tab == "scout" else 0
		_tab_changed(_tabs.current_tab)


func configure_target(node: Dictionary) -> void:
	var was_order: bool = not str(_target.get("orderRoute", "")).is_empty()
	if str(_target.get("id", "")) != str(node.get("id", "")):
		_invalidate_march("目标已变化，请重新预览。")
		_march_error = ""
	super.configure_target(node)
	if was_order and str(node.get("orderRoute", "")).is_empty() and is_instance_valid(_mode):
		_mode.select(0)
	if is_instance_valid(_march_intro):
		_render_march()


func update_view(view: Dictionary) -> void:
	if view.is_empty():
		clear_context()
		return
	var old_source: String = _source
	var old_gate: String = _march_gate()
	super.update_view(view)
	var stock: Array = []
	for unit: Dictionary in _view.get("units", []):
		stock.append([str(unit.get("id", "")), maxi(0, int(unit.get("available", 0))), unit.get("stats", {})])
	var generals: Array = []
	for general: Dictionary in _view.get("generals", []):
		var record: Dictionary = general.duplicate(true)
		record.erase("name")
		record.erase("loyalty")
		generals.append(record)
	var levels: Array = []
	for building: Dictionary in _view.get("buildings", []):
		levels.append([building.get("id", ""), building.get("site", ""), building.get("level", 0)])
	var techs: Array = []
	for tech: Dictionary in _view.get("techs", []):
		techs.append([tech.get("id", ""), tech.get("level", 0)])
	var marches: Array = []
	for march: Dictionary in _view.get("marches", []):
		marches.append([march.get("id", ""), march.get("node", ""), march.get("general", ""), march.get("sourceCity", ""), march.get("status", "")])
	var signature: String = JSON.stringify([_source, stock, generals, levels, techs, marches])
	if not old_source.is_empty() and old_source != _source:
		_invalidate_march("已切换城池，请重新选择将领与兵力。")
		_clear_army_inputs()
		_general_signature = ""
	elif (not _march_signature.is_empty() and signature != _march_signature) or old_gate != _march_gate():
		_invalidate_march("兵力、将领或目标条件已变化，请重新预览。")
	_march_signature = signature
	if not _march_quote.is_empty() and float(_view.get("res", {}).get("food", 0)) < float(_march_quote.get("foodCost", 0)):
		_invalidate_march("粮草已不足，请重新预览。")
	if is_instance_valid(_march_intro):
		_sync_march_inputs()
		_render_march()


func set_command_state(connected: bool, pending: bool) -> void:
	if not connected or pending:
		_invalidate_march("操作正在确认，不能重复派遣。" if pending else "连接中断，请重连后重新预览。")
	super.set_command_state(connected, pending)
	if is_instance_valid(_march_status):
		_refresh_march_actions()


func receive_quote(payload: Dictionary) -> void:
	if _march_quote_id.is_empty() or str(payload.get("requestId", "")) != _march_quote_id:
		super.receive_quote(payload)
		_fit_window()
		_schedule_fit()
		return
	if not _march_active() or not _march_usable():
		return
	if _march_quote_fingerprint != _march_fingerprint():
		_invalidate_march("选项或派遣条件已变化，请重新预览。")
		_refresh_march_actions()
		return
	_march_busy = false
	if payload.has("error"):
		show_error(str(payload.error))
		return
	_march_quote = _dictionary(payload.get("quote")).duplicate(true)
	if _number(payload.get("serverTime")):
		_now_ms = float(payload.serverTime)
	var command: Dictionary = _dictionary(_march_quote.get("command"))
	var reason: String = str(_march_quote.get("reason", ""))
	_march_command = command.duplicate(true) if reason.is_empty() and _valid_march_command(command) and _valid_march_terms() else {}
	var lines: PackedStringArray = []
	lines.append("粮草费用 %s · 运载能力 %s" % [_amount(_march_quote.get("foodCost")), _amount(_march_quote.get("carry"))])
	lines.append("行军 %s · 返城 %s" % [_duration(_march_quote.get("seconds")), _duration(_march_quote.get("returnSeconds"))])
	lines.append("最慢兵种 %s · 速度 %s" % [_quoted_slowest_name(), _stat_text(_march_quote.get("speed"))])
	lines.append("预计抵达：" + _arrival_text(_march_quote.get("seconds")))
	lines.append(reason if not reason.is_empty() else "确认后扣除粮草并派遣，抵达后进入战斗。" if not _march_command.is_empty() else "预览缺少合法命令或费用，请重新预览。")
	_march_quote_label.text = "\n".join(lines)
	_march_error = ""
	_render_march_intel()
	_refresh_march_actions()
	_fit_window()
	_schedule_fit()


func show_error(message: String) -> void:
	if is_instance_valid(_tabs) and _tabs.current_tab == 0:
		_invalidate_march(message)
		_march_error = message
		_refresh_march_actions()
	else:
		super.show_error(message)


func acknowledge_command(connected: bool, pending: bool) -> void:
	_march_error = ""
	_invalidate_march()
	super.acknowledge_command(connected, pending)


func clear_context() -> void:
	_invalidate_march("请选择当前进度中已开放的目标。")
	_march_signature = ""
	_general_signature = ""
	_march_error = ""
	_clear_army_inputs()
	if is_instance_valid(_mode):
		_march_setting = true
		_mode.select(0)
		_occupy_return.button_pressed = false
		_march_setting = false
	super.clear_context()
	if is_instance_valid(_march_intro):
		_sync_march_inputs()
		_render_march()


func _request_quote() -> void:
	if is_instance_valid(_tabs) and _tabs.current_tab != 1:
		return
	super._request_quote()


func _submit() -> void:
	if is_instance_valid(_tabs) and _tabs.current_tab != 1:
		return
	super._submit()


func _sync_march_inputs() -> void:
	if not is_instance_valid(_general):
		return
	_march_setting = true
	var selected: String = _selected_general()
	var eligible: Array[Dictionary] = []
	for general: Dictionary in _view.get("generals", []):
		if not general.get("busy", false) and not general.get("governor", false):
			eligible.append(general)
	var general_signature: String = JSON.stringify(eligible)
	if general_signature != _general_signature:
		_general.clear()
		for general: Dictionary in eligible:
			_general.add_item(str(general.get("name", general.get("id", "将领"))))
			var index: int = _general.item_count - 1
			_general.set_item_metadata(index, str(general.get("id", "")))
			if str(general.get("id", "")) == selected:
				_general.select(index)
		_general_signature = general_signature
	var present: Array[String] = []
	for unit: Dictionary in _view.get("units", []):
		var id: String = str(unit.get("id", ""))
		if id.is_empty():
			continue
		present.append(id)
		var available: int = maxi(0, int(unit.get("available", 0)))
		_army_stock[id] = available
		if not _army_inputs.has(id):
			var row: VBoxContainer = VBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			_army_rows.add_child(row)
			_army_labels[id] = _march_label(row, "")
			_army_details[id] = _march_label(row, "", "MutedLabel")
			var count: SpinBox = SpinBox.new()
			count.min_value = 0
			count.max_value = available
			count.step = 1
			count.value = available
			count.custom_minimum_size.y = 44
			count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(count)
			count.get_line_edit().text = str(available)
			count.value_changed.connect(func(_value: float) -> void: _march_input_changed())
			count.get_line_edit().text_changed.connect(func(_text: String) -> void: _march_input_changed())
			_army_inputs[id] = count
		var spin: SpinBox = _army_inputs[id]
		_army_labels[id].text = str(unit.get("name", id)) + " · 可分配 %d 人" % available
		_army_details[id].text = _unit_decision_text(unit)
		spin.tooltip_text = "填写本次派遣的%s人数；0表示不携带，最多%d人。" % [str(unit.get("name", id)), available]
		# Only stock changes touch Range. Unchanged polling retains raw typing/focus.
		if not is_equal_approx(spin.max_value, available):
			var raw: String = spin.get_line_edit().text.strip_edges()
			spin.max_value = available
			if raw.is_valid_int() and int(raw) > available:
				spin.value = available
				spin.get_line_edit().text = str(available)
	for id: String in _army_inputs.keys():
		if not present.has(id):
			_army_inputs[id].get_parent().queue_free()
			_army_inputs.erase(id)
			_army_labels.erase(id)
			_army_details.erase(id)
			_army_stock.erase(id)
	_march_setting = false


func _clear_army_inputs() -> void:
	for spin: SpinBox in _army_inputs.values():
		spin.get_parent().queue_free()
	_army_inputs.clear()
	_army_labels.clear()
	_army_details.clear()
	_army_stock.clear()


func _unit_decision_text(unit: Dictionary) -> String:
	var stats: Dictionary = _dictionary(unit.get("stats"))
	var role: Variant = unit.get("role")
	var role_text: String = role.strip_edges() if role is String else ""
	return "定位：%s\n射程 %s · 速度 %s" % [role_text if not role_text.is_empty() else "未提供", _stat_text(stats.get("range")), _stat_text(stats.get("speed"))]


func _stat_text(value: Variant) -> String:
	# Only format the supplied statistic. Do not infer a missing value, convert
	# its unit, or calculate a second version of the server's march rules.
	if not _number(value) or float(value) < 0.0:
		return "未提供"
	return str(int(value)) if float(value) == float(int(value)) else str(value)


func _quoted_slowest_name() -> String:
	var slowest: Variant = _march_quote.get("slowest")
	if not slowest is String or slowest.strip_edges().is_empty():
		return "未提供"
	for unit: Dictionary in _view.get("units", []):
		if str(unit.get("id", "")) == slowest:
			var name: String = str(unit.get("name", "")).strip_edges()
			return name if not name.is_empty() else slowest + "（名称未提供）"
	return slowest + "（名称未提供）"


func _selected_general() -> String:
	return str(_general.get_item_metadata(_general.selected)) if is_instance_valid(_general) and _general.item_count > 0 and _general.selected >= 0 else ""


func _collect_march() -> Array:
	var army: Dictionary = {}
	for id: String in _army_inputs:
		var raw: String = _army_inputs[id].get_line_edit().text.strip_edges()
		army[id] = clampi(int(raw), 0, int(_army_stock.get(id, 0))) if raw.is_valid_int() else -1
	var order: bool = not str(_target.get("orderRoute", "")).is_empty()
	return [str(_target.get("id", "")), _selected_general(), army, "occupy" if order else "raid" if not is_instance_valid(_mode) or _mode.selected == 0 else "occupy", order or is_instance_valid(_occupy_return) and _occupy_return.button_pressed]


func _normalize_march() -> bool:
	var army: Dictionary = _collect_march()[2]
	for id: String in army:
		if int(army[id]) < 0:
			show_error("请输入有效的整数兵力。")
			return false
	_march_setting = true
	for id: String in army:
		_army_inputs[id].value = int(army[id])
		_army_inputs[id].get_line_edit().text = str(army[id])
	_march_setting = false
	return true


func _march_node() -> Dictionary:
	for current: Dictionary in _view.get("nodes", []):
		if not str(_target.get("id", "")).is_empty() and str(current.get("id", "")) == str(_target.get("id", "")):
			var node: Dictionary = current.duplicate(true)
			var intel: Dictionary = _dictionary(_dictionary(_view.get("scouting")).get("intelByNode"))
			if intel.has(str(node.id)):
				node["intel"] = _dictionary(intel[str(node.id)]).duplicate(true)
			return node
	return {}


func _march_gate() -> String:
	var node: Dictionary = _march_node()
	var intel: Dictionary = _dictionary(node.get("intel"))
	var expired: bool = str(intel.get("precision", "")) != "public" and _number(intel.get("expiresAt")) and _now_ms >= float(intel.expiresAt)
	return JSON.stringify([node.get("id", ""), node.get("hidden", false), node.get("selectable", true), node.get("owned", false), node.get("shared", false), node.get("player", false), node.get("playerId", ""), intel, expired])


func _march_usable() -> bool:
	var node: Dictionary = _march_node()
	return _connected and not _pending and not _source.is_empty() and not node.is_empty() and not node.get("hidden", false) and node.get("selectable", true) and not node.get("owned", false) and not node.get("shared", false) and not node.get("player", false) and not node.has("playerId")


func _march_selection_ready() -> bool:
	if _selected_general().is_empty():
		return false
	var total: int = 0
	for count: Variant in _collect_march()[2].values():
		if int(count) < 0:
			return false
		total += int(count)
	return total > 0


func _march_active() -> bool:
	return visible and is_instance_valid(_tabs) and _tabs.current_tab == 0


func _march_fingerprint() -> String:
	return JSON.stringify([_collect_march(), _source, _march_signature, _march_gate()])


func _march_input_changed() -> void:
	if _march_setting:
		return
	_invalidate_march("选项已变化，请重新预览。")
	_march_error = ""
	_refresh_march_actions()


func _request_march_quote() -> void:
	if not _march_active() or not _march_usable() or not _march_selection_ready() or _march_busy or not _normalize_march():
		return
	_invalidate_march("正在读取当前出征费用…")
	_march_error = ""
	_march_busy = true
	_march_quote_id = "dispatch_march_" + Crypto.new().generate_random_bytes(8).hex_encode()
	_march_quote_fingerprint = _march_fingerprint()
	_refresh_march_actions()
	quote_requested.emit("march", _collect_march(), _march_quote_id)


func _valid_march_terms() -> bool:
	return _number(_march_quote.get("foodCost")) and float(_march_quote.foodCost) >= 0 and _number(_march_quote.get("seconds")) and float(_march_quote.seconds) >= 0 and _number(_march_quote.get("returnSeconds")) and float(_march_quote.returnSeconds) >= 0 and float(_view.get("res", {}).get("food", 0)) >= float(_march_quote.foodCost)


func _valid_march_command(command: Dictionary) -> bool:
	var args: Variant = command.get("args")
	if str(command.get("type", "")) != "dispatch" or str(command.get("sourceCity", "")) != _source or not args is Array or args.size() != 5:
		return false
	var selected: Array = _collect_march()
	if not args[0] is String or not args[1] is String or args[0] != selected[0] or args[1] != selected[1] or not args[2] is Dictionary or args[3] != selected[3] or not args[4] is bool or args[4] != selected[4]:
		return false
	if args[2].size() != selected[2].size():
		return false
	for id: String in selected[2]:
		if not args[2].has(id) or not _number(args[2][id]) or float(args[2][id]) != float(int(args[2][id])) or int(args[2][id]) != int(selected[2][id]):
			return false
	return true


func _submit_march() -> void:
	if not _march_active() or not _march_usable() or _march_busy or _march_command.is_empty() or _march_quote_fingerprint != _march_fingerprint():
		return
	var command: Dictionary = _march_command.duplicate(true)
	if not _normalize_march() or not _valid_march_command(command) or not _valid_march_terms():
		show_error("派遣条件已变化，请重新预览。")
		return
	_pending = true
	_invalidate_quote("派遣已提交，等待实际回执。")
	_invalidate_march("派遣已提交，等待实际回执。")
	_march_error = ""
	_refresh_march_actions()
	command_requested.emit(str(command.type), command.args.duplicate(true), str(command.sourceCity))


func _invalidate_march(message: String = "先预览当前粮草费用、行军耗时与抵达时间。") -> void:
	_march_quote_id = ""
	_march_quote_fingerprint = ""
	_march_quote.clear()
	_march_command.clear()
	_march_busy = false
	if is_instance_valid(_march_quote_label):
		_march_quote_label.text = message
	if is_instance_valid(_march_confirm):
		_march_confirm.disabled = true


func _render_march() -> void:
	_march_intro.text = str(_target.get("name", "请选择目标")) + " · 从" + str(_view.get("city", {}).get("name", "当前城池")) + "出发"
	_render_march_intel()
	_refresh_march_actions()


func _render_march_intel() -> void:
	_march_intel.set_intel(_march_node(), _view.get("units", []), _now_ms)


func _refresh_march_actions() -> void:
	var usable: bool = _march_usable()
	_general.disabled = not usable or _general.item_count == 0
	_mode.disabled = not usable
	var order: bool = not str(_target.get("orderRoute", "")).is_empty()
	_mode.set_item_disabled(0, order)
	_mode.set_item_text(1, "讨伐军令（胜利后返城）" if order else "占领")
	if order:
		_mode.select(1)
	_mode.tooltip_text = "军令使用讨伐模式，胜利后返城；本场不取得领地。" if order else "选择掠夺资源或占领目标。"
	_occupy_return.visible = _mode.selected == 1 and not order
	_occupy_return.disabled = not usable
	for id: String in _army_inputs:
		_army_inputs[id].editable = usable and int(_army_stock.get(id, 0)) > 0
	_march_preview.disabled = not usable or _march_busy or not _march_selection_ready()
	_march_confirm.disabled = not usable or _march_busy or _march_command.is_empty() or _march_quote_fingerprint != _march_fingerprint()
	_march_status.text = _march_error if not _march_error.is_empty() else "正在确认派遣，不能重复消费。" if _pending else "连接后可预览出征。" if not _connected else "请选择已开放的城外目标；玩家城池使用玩家战争。" if not usable else "暂无可出征将领，请等待归城或调整任职。" if _general.item_count == 0 else "请选择至少1名士兵。" if not _march_selection_ready() else "正在读取原规则报价…" if _march_busy else "预览不扣费；确认以实际回执为准。"
	var previous: Control = _general
	for spin: SpinBox in _army_inputs.values():
		var editor: LineEdit = spin.get_line_edit()
		previous.focus_next = editor.get_path()
		editor.focus_previous = previous.get_path()
		previous = editor
	previous.focus_next = _mode.get_path()
	_mode.focus_previous = previous.get_path()
	_mode.focus_next = _occupy_return.get_path() if _occupy_return.visible else _march_preview.get_path()
	_occupy_return.focus_previous = _mode.get_path()
	_occupy_return.focus_next = _march_preview.get_path()
	_march_preview.focus_previous = _occupy_return.get_path() if _occupy_return.visible else _mode.get_path()
	_march_preview.focus_next = _march_confirm.get_path() if not _march_confirm.disabled else get_ok_button().get_path()
	_march_confirm.focus_previous = _march_preview.get_path()
	_march_confirm.focus_next = get_ok_button().get_path()
	get_ok_button().focus_previous = _march_confirm.get_path() if not _march_confirm.disabled else _march_preview.get_path()


func _arrival_text(seconds: Variant) -> String:
	if not _number(seconds) or _now_ms <= 0:
		return "未提供"
	var arrival: Dictionary = Time.get_datetime_dict_from_unix_time(int(ceil(_now_ms / 1000.0 + float(seconds))))
	return "%02d-%02d %02d:%02d:%02d（服务器时间 UTC）" % [arrival.month, arrival.day, arrival.hour, arrival.minute, arrival.second]


func _tab_changed(index: int) -> void:
	_invalidate_quote()
	_invalidate_march()
	if is_instance_valid(_scout_footer):
		_scout_footer.visible = index == 1
		_march_footer.visible = index == 0
		_fit_window()
		_schedule_fit()


func _visibility_changed() -> void:
	super._visibility_changed()
	if not visible:
		_invalidate_march()
	else:
		_schedule_fit()


func _schedule_fit() -> void:
	if _fit_scheduled or not is_inside_tree():
		return
	_fit_scheduled = true
	# Wrapped labels in a newly visible tab finish measuring after containers.
	for _frame: int in range(3):
		await get_tree().process_frame
	_fit_scheduled = false
	if visible:
		_fit_window()


func _fit_window() -> void:
	if not is_instance_valid(_layout):
		return
	var available: Vector2 = (get_parent() as Control).size if get_parent() is Control else Vector2(get_tree().root.size)
	var target_size: Vector2i = Vector2i(mini(480, maxi(280, int(available.x) - 24)), mini(760, maxi(280, int(available.y) - 64)))
	min_size = target_size
	_layout.custom_minimum_size = Vector2(target_size.x - 36, target_size.y - 80)
	_scroll.custom_minimum_size = Vector2.ZERO
	# Window.wrap_controls also observes current child bounds. Shrink the
	# existing content before the popup, after wrapped labels have settled.
	_layout.size = Vector2(target_size.x - 28, target_size.y - 76)
	size = target_size
	position = Vector2i(int(available.x) - size.x - 12, (int(available.y) - size.y) / 2)


func _march_label(parent: Node, text: String, variation: String = "") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _march_button(parent: Node, text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.theme_type_variation = "PrimaryButton" if primary else "UtilityButton"
	button.custom_minimum_size.y = 44
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button
