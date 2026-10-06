class_name KingdomManagementDialog
extends AcceptDialog

## Quotes come from the rule service. This view only selects, clamps and sends
## canonical commands; it never grants resources or generates candidates.
signal command_requested(type: String, args: Array)

const TITLES: Dictionary = {"market": "市场交易", "governance": "城守与税率", "inn": "客栈招募"}
const RES_NAMES: Dictionary = {"food": "粮草", "wood": "木材", "stone": "石料", "iron": "铁锭"}

var _view: Dictionary = {}
var _section: String = "market"
var _connected: bool = true
var _pending: bool = false
var _content: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _resource: OptionButton
var _mode: OptionButton
var _count: SpinBox
var _market_info: Label
var _market_preview: Label
var _market_warning: Label
var _trade_button: Button
var _population_info: Label
var _governor_info: Label
var _governor: OptionButton
var _governor_button: Button
var _tax: SpinBox
var _tax_info: Label
var _tax_button: Button
var _tax_dirty: bool = false
var _count_dirty: bool = false
var _updating: bool = false
var _inn_info: Label
var _inn_refresh: Button
var _inn_candidates: VBoxContainer
var _candidate_signature: String = ""
var _governor_ids: Array[String] = []
var _governor_signature: String = ""
var _error_message: String = ""


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
	_section = section if TITLES.has(section) else "market"
	_tax_dirty = false
	_error_message = ""
	_build_section()
	_fit_window()
	popup_centered()


func update_view(view: Dictionary) -> void:
	_view = view
	if not is_instance_valid(_content):
		return
	match _section:
		"market": _update_market()
		"governance": _update_governance()
		"inn": _update_inn()


func set_command_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	if is_instance_valid(_status):
		_status.text = _error_message if not _error_message.is_empty() else "正在结算，请稍候…" if _pending else "请先连接规则服务" if not _connected else "成交和任命后自动保存"
		update_view(_view)


func show_error(message: String) -> void:
	_error_message = message
	_status.text = message
	_status.modulate = Color("e7bc72")


func acknowledge_command(connected: bool, pending: bool) -> void:
	_tax_dirty = false
	_error_message = ""
	_status.modulate = Color.WHITE
	set_command_state(connected, pending)


func _fit_window() -> void:
	var available: Vector2 = Vector2(get_tree().root.size)
	if get_parent() is Control:
		available = (get_parent() as Control).size
	var width: int = mini(700, maxi(280, int(available.x) - 40))
	var height: int = mini(620, maxi(280, int(available.y) - 80))
	min_size = Vector2i(width, height)
	size = min_size
	_scroll.custom_minimum_size = Vector2(float(width - 48), float(height - 90))


func _build_section() -> void:
	if not is_instance_valid(_content):
		return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_candidate_signature = ""
	_governor_signature = ""
	_governor_ids.clear()
	title = str(TITLES[_section])
	var sections: GridContainer = GridContainer.new()
	sections.columns = 3
	_content.add_child(sections)
	for entry: Array in [["market", "市场"], ["governance", "内政"], ["inn", "客栈"]]:
		var section: String = str(entry[0])
		var button: Button = _button(str(entry[1]), func() -> void: show_section(section, _view))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = section == _section
		sections.add_child(button)
	_status = _label("", 13)
	_content.add_child(_status)
	match _section:
		"market": _build_market()
		"governance": _build_governance()
		"inn": _build_inn()
	set_command_state(_connected, _pending)


func _label(text: String, font_size: int = 16) -> Label:
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
	button.pressed.connect(callback)
	return button


func _build_market() -> void:
	var selectors: GridContainer = GridContainer.new()
	selectors.columns = 2
	_content.add_child(selectors)
	_resource = OptionButton.new()
	_resource.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id: String in RES_NAMES:
		_resource.add_item(str(RES_NAMES[id]))
	selectors.add_child(_resource)
	_resource.item_selected.connect(func(_index: int) -> void: _update_market())
	_mode = OptionButton.new()
	_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode.add_item("买入")
	_mode.add_item("卖出")
	selectors.add_child(_mode)
	_mode.item_selected.connect(func(_index: int) -> void: _update_market())
	_market_info = _label("")
	_content.add_child(_market_info)
	_content.add_child(_label("交易数量 · 1 单位资源 = 1 黄金", 14))
	_count = SpinBox.new()
	_count.step = 1.0
	_count.rounded = true
	_count.min_value = 0.0
	_count.max_value = 100000.0
	_count.value = 1000.0
	_count_dirty = false
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_count)
	_count.value_changed.connect(func(_value: float) -> void: _update_market_preview())
	_count.get_line_edit().text_changed.connect(func(_text: String) -> void: _count_dirty = true; _update_market_preview())
	_count.get_line_edit().text_submitted.connect(func(_text: String) -> void: _count.apply(); _count_dirty = false; _update_market_preview())
	_market_preview = _label("")
	_content.add_child(_market_preview)
	_market_warning = _label("", 14)
	_market_warning.modulate = Color("e7bc72")
	_content.add_child(_market_warning)
	_trade_button = _button("确认交易", _trade)
	_content.add_child(_trade_button)


func _selected_resource() -> String:
	if not is_instance_valid(_resource):
		return "food"
	return str(RES_NAMES.keys()[maxi(0, _resource.selected)])


func _market_quote() -> Dictionary:
	for resource: Dictionary in _view.get("market", {}).get("resources", []):
		if str(resource.get("id", "")) == _selected_resource():
			return resource.get("buy" if _mode.selected == 0 else "sell", {})
	return {"limit": 0, "reason": "正在读取市场报价"}


func _update_market() -> void:
	var quote: Dictionary = _market_quote()
	var draft: String = _count.get_line_edit().text
	_count.max_value = maxf(0.0, float(quote.get("limit", 0)))
	_count.value = minf(_count.value, _count.max_value)
	if _count_dirty:
		_count.get_line_edit().text = draft
	var resource: String = _selected_resource()
	_market_info.text = "%s库存 %s / 上限 %s\n黄金 %s · 本次最多 %s" % [RES_NAMES[resource], _number(float(_view.get("res", {}).get(resource, 0))), _number(float(_view.get("caps", {}).get(resource, 0))), _number(float(_view.get("res", {}).get("gold", 0))), _number(_count.max_value)]
	_update_market_preview()


func _update_market_preview() -> void:
	if not is_instance_valid(_market_preview):
		return
	var resource: String = _selected_resource()
	var buy: bool = _mode.selected == 0
	var draft: Dictionary = _spin_draft(_count, _count_dirty)
	var count: int = int(draft.value)
	var quote: Dictionary = _market_quote()
	var current: float = float(_view.get("res", {}).get(resource, 0))
	var gold: float = float(_view.get("res", {}).get("gold", 0))
	var after: float = current + float(count if buy else -count)
	_market_preview.text = "成交预览\n%s %s → %s\n黄金 %s → %s" % [RES_NAMES[resource], _number(current), _number(after), _number(gold), _number(gold + float(-count if buy else count))]
	var reason: String = str(quote.get("reason", ""))
	var overflow: float = maxf(0.0, after - float(_view.get("caps", {}).get(resource, 0)))
	_market_warning.text = reason if not reason.is_empty() else str(quote.get("warning", ""))
	if buy and overflow > 0 and count > 0:
		_market_warning.text += ("\n" if not _market_warning.text.is_empty() else "") + "成交后超仓 " + _number(overflow) + "，本次资源全部入库。"
	_trade_button.text = ("买入 " if buy else "卖出 ") + _number(count) + " " + str(RES_NAMES[resource])
	_trade_button.disabled = not _connected or _pending or not draft.valid or count < 1 or not reason.is_empty()


func _trade() -> void:
	if not _spin_draft(_count, _count_dirty).valid:
		return
	_count.apply()
	_count_dirty = false
	_update_market_preview()
	if _trade_button.disabled:
		return
	_send("trade", [_selected_resource(), int(_count.value), _mode.selected == 0])


func _build_governance() -> void:
	_population_info = _label("")
	_content.add_child(_population_info)
	_content.add_child(HSeparator.new())
	_content.add_child(_label("城守", 19))
	_governor = OptionButton.new()
	_governor.fit_to_longest_item = false
	_governor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_governor)
	_governor.item_selected.connect(func(_index: int) -> void: _update_governor_action())
	_governor_info = _label("", 14)
	_content.add_child(_governor_info)
	_governor_button = _button("任命城守", _appoint_governor)
	_content.add_child(_governor_button)
	_content.add_child(HSeparator.new())
	_content.add_child(_label("税率（0–100%）", 19))
	_tax = SpinBox.new()
	_tax.min_value = 0.0
	_tax.max_value = 100.0
	_tax.step = 1.0
	_tax.rounded = true
	_tax.suffix = "%"
	_tax.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_tax)
	_tax.value_changed.connect(func(_value: float) -> void:
		if not _updating:
			_tax_dirty = true
		_update_tax_action())
	_tax.get_line_edit().text_changed.connect(func(_text: String) -> void:
		_tax_dirty = true
		_update_tax_action())
	_tax_info = _label("", 14)
	_content.add_child(_tax_info)
	_tax_button = _button("调整税率", _change_tax)
	_content.add_child(_tax_button)


func _update_governance() -> void:
	var governance: Dictionary = _view.get("governance", {})
	_population_info.text = "人口 %s / %s · 空闲 %s\n民心 %s · 民怨 %s\n当前税率 %d%% · 黄金收入 %.2f/分钟" % [_number(float(governance.get("population", _view.get("population", 0)))), _number(float(governance.get("maxPopulation", _view.get("maxPopulation", 0)))), _number(float(governance.get("freePopulation", _view.get("freePopulation", 0)))), _number(float(governance.get("morale", _view.get("morale", 0)))), _number(float(governance.get("unrest", _view.get("unrest", 0)))), int(governance.get("tax", _view.get("tax", 0))), float(governance.get("goldPerMinute", 0))]
	var candidates: Array = governance.get("candidates", [])
	var signature: String = JSON.stringify(candidates)
	if signature != _governor_signature:
		var previous: String = _governor_ids[_governor.selected] if _governor.selected >= 0 and _governor.selected < _governor_ids.size() else str(governance.get("governorId", ""))
		_governor_signature = signature
		_governor.clear()
		_governor_ids.clear()
		for candidate: Dictionary in candidates:
			var id: String = str(candidate.get("id", ""))
			_governor_ids.append(id)
			var text: String = str(candidate.get("name", "将领")) + " · 内政 " + str(int(candidate.get("pol", 0)))
			if candidate.get("governor", false): text += " · 现任"
			elif not str(candidate.get("reason", "")).is_empty(): text += " · 出征/驻守"
			_governor.add_item(text)
			_governor.set_item_disabled(_governor.item_count - 1, not str(candidate.get("reason", "")).is_empty())
			_governor.set_item_tooltip(_governor.item_count - 1, _candidate_location(candidate) + ("\n" + str(candidate.get("reason", "")) if not str(candidate.get("reason", "")).is_empty() else ""))
		_governor.select(maxi(0, _governor_ids.find(previous)))
	_updating = true
	if not _tax_dirty:
		_tax.value = float(governance.get("tax", _view.get("tax", 0)))
	_updating = false
	_update_governor_action()
	_update_tax_action()


func _governor_candidate() -> Dictionary:
	if _governor.selected < 0 or _governor.selected >= _governor_ids.size():
		return {}
	for candidate: Dictionary in _view.get("governance", {}).get("candidates", []):
		if str(candidate.get("id", "")) == _governor_ids[_governor.selected]:
			return candidate
	return {}


func _update_governor_action() -> void:
	var candidate: Dictionary = _governor_candidate()
	var governance: Dictionary = _view.get("governance", {})
	var reason: String = str(candidate.get("reason", ""))
	_governor_info.text = "当前城外生产城守系数 ×%.2f\n当前建造效率 ×%.2f（含建造科技）\n内政影响城外生产和建设；每项建筑完成后，城守获得经验。" % [float(governance.get("productionBoost", 1)), float(governance.get("constructionFactor", 1))]
	if not reason.is_empty(): _governor_info.text += "\n" + reason
	_governor_button.disabled = not _connected or _pending or candidate.is_empty() or not reason.is_empty() or str(candidate.get("id", "")) == str(governance.get("governorId", ""))


func _update_tax_action() -> void:
	if not is_instance_valid(_tax_info):
		return
	var draft: Dictionary = _spin_draft(_tax, _tax_dirty)
	var tax: int = int(draft.value)
	_tax_info.text = "当前民心目标 %s。提高税率可增加税收，也会降低民心和人口增长。" % _number(float(_view.get("governance", {}).get("targetMorale", 0)))
	_tax_button.disabled = not _connected or _pending or not _view.has("governance") or not draft.valid or tax == int(_view.get("governance", {}).get("tax", _view.get("tax", 0)))


func _appoint_governor() -> void:
	_update_governor_action()
	if not _governor_button.disabled:
		_send("setGovernor", [str(_governor_candidate().get("id", ""))])


func _change_tax() -> void:
	if not _spin_draft(_tax, _tax_dirty).valid:
		return
	_tax.apply()
	_update_tax_action()
	if not _tax_button.disabled:
		_send("setTax", [int(_tax.value)])
	else:
		_tax_dirty = false


func _candidate_location(candidate: Dictionary) -> String:
	var id: String = str(candidate.get("city", ""))
	for city: Dictionary in _view.get("cityList", []):
		if str(city.get("id", "")) == id:
			return "所在城池：" + str(city.get("name", id))
	return "所在城池：" + id if not id.is_empty() else ""


func _build_inn() -> void:
	_inn_info = _label("")
	_content.add_child(_inn_info)
	_inn_refresh = _button("打听游士 · 免费刷新", _refresh_inn)
	_content.add_child(_inn_refresh)
	_inn_candidates = VBoxContainer.new()
	_inn_candidates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_inn_candidates)


func _update_inn() -> void:
	var inn: Dictionary = _view.get("inn", {})
	var reason: String = str(inn.get("refreshReason", "正在读取客栈"))
	_inn_info.text = "客栈 %d级 · 招贤馆房间 %d / %d\n房间包含已招募及被俘将领；黄金 %s。" % [int(inn.get("level", 0)), int(inn.get("used", 0)), int(inn.get("capacity", 0)), _number(float(_view.get("res", {}).get("gold", 0)))]
	if not reason.is_empty(): _inn_info.text += "\n" + reason
	_inn_refresh.disabled = not _connected or _pending or not reason.is_empty()
	var candidates: Array = inn.get("candidates", [])
	var signature: String = JSON.stringify([candidates, _connected, _pending])
	if signature == _candidate_signature:
		return
	_candidate_signature = signature
	for child: Node in _inn_candidates.get_children():
		_inn_candidates.remove_child(child)
		child.queue_free()
	if candidates.is_empty():
		_inn_candidates.add_child(_label("客栈落成后，打听游士即可查看可招募的将领。", 14))
	for candidate: Dictionary in candidates:
		var card: VBoxContainer = VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_inn_candidates.add_child(card)
		card.add_child(HSeparator.new())
		card.add_child(_label(str(candidate.get("name", "游士")) + " · " + str(int(candidate.get("level", 1))) + "级", 19))
		var stats: GridContainer = GridContainer.new()
		stats.columns = 2
		card.add_child(stats)
		for stat: Array in [["atk", "武勇"], ["def", "防御"], ["pol", "内政"], ["wis", "智谋"]]:
			var value: int = int(candidate.get(str(stat[0]), 0))
			var label: Label = _label(str(stat[1]) + " " + str(value))
			label.modulate = Color("e7bc5c") if value >= 90 else Color("b49ce0") if value >= 80 else Color("81bfe0") if value >= 70 else Color.WHITE
			stats.add_child(label)
		var candidate_reason: String = str(candidate.get("reason", ""))
		if not candidate_reason.is_empty(): card.add_child(_label(candidate_reason, 14))
		var candidate_id: String = str(candidate.get("id", ""))
		var button: Button = _button("招募 · 黄金 " + _number(float(candidate.get("price", 0))), _recruit.bind(candidate_id))
		button.disabled = not _connected or _pending or not candidate_reason.is_empty() or not candidate.get("affordable", false)
		card.add_child(button)


func _refresh_inn() -> void:
	if not _inn_refresh.disabled:
		_send("refreshInn", [])


func _recruit(id: String) -> void:
	for candidate: Dictionary in _view.get("inn", {}).get("candidates", []):
		if str(candidate.get("id", "")) == id and candidate.get("affordable", false) and str(candidate.get("reason", "")).is_empty():
			_send("recruit", [id])
			return


func _send(type: String, args: Array) -> void:
	if not _connected or _pending:
		return
	_error_message = ""
	_status.modulate = Color.WHITE
	set_command_state(_connected, true)
	command_requested.emit(type, args)


func _spin_draft(spin: SpinBox, edited: bool) -> Dictionary:
	if not edited:
		return {"valid": true, "value": clampf(spin.value, spin.min_value, spin.max_value)}
	# Match SpinBox's mathematical input without applying/reformatting a field
	# while the player is still typing. Final submission still uses SpinBox.apply.
	var input: String = spin.get_line_edit().text.strip_edges().trim_prefix(spin.prefix).trim_suffix(spin.suffix).strip_edges()
	var expression: Expression = Expression.new()
	if input.is_empty() or expression.parse(input) != OK:
		return {"valid": false, "value": 0.0}
	var value: Variant = expression.execute([], null, false)
	if expression.has_execute_failed() or not (value is int or value is float) or not is_finite(float(value)):
		return {"valid": false, "value": 0.0}
	return {"valid": true, "value": clampf(roundf(float(value)), spin.min_value, spin.max_value)}


func _number(value: float) -> String:
	return str(int(floor(value)))
