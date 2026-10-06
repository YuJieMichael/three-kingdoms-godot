class_name KingdomHeroDialog
extends AcceptDialog

signal command_requested(type: String, args: Array)
signal focus_requested(x: int, y: int)
signal dispatch_requested(node_id: String)

const TITLES: Dictionary = {"generals": "将领培养", "wild": "野将线索", "captives": "俘将招降", "equipment": "装备工坊"}
const RES_NAMES: Dictionary = {"gold": "黄金", "food": "粮草", "wood": "木材", "stone": "石料", "iron": "铁锭", "pearls": "强化宝珠"}
var _view: Dictionary = {}
var _section: String = "generals"
var _connected: bool = true
var _pending: bool = false
var _error_message: String = ""
var _scroll: ScrollContainer
var _content: VBoxContainer
var _body: VBoxContainer
var _status: Label
var _actions: Array[Dictionary] = []
var _labels: Array[Dictionary] = []
var _signature: String = ""
var _selected_hero: String = ""
var _selected_item: String = ""
var _selected_equipment: int = 0
var _selected_forge: String = ""
var _points: Dictionary = {}
var _drafts: Dictionary = {}
var _hero_selector: OptionButton
var _equipment_selector: OptionButton
var _forge_selector: OptionButton
var _item_selector: OptionButton
var _updating: bool = false
var _last_command: String = ""
var _last_target: String = ""


func _ready() -> void:
	dialog_text = ""
	get_ok_button().text = "关闭"
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_build()


func show_section(section: String, view: Dictionary) -> void:
	_remember_draft()
	_view = view
	_section = section if TITLES.has(section) else "generals"
	_error_message = ""
	_build()
	_fit_window()
	popup_centered()


func update_view(view: Dictionary) -> void:
	_view = view
	if not is_instance_valid(_content):
		return
	var signature: String = _structure_signature()
	if signature != _signature:
		_remember_draft()
		var position: int = _scroll.scroll_vertical
		_build()
		_scroll.set_deferred("scroll_vertical", position)
	else:
		_refresh()


func set_command_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	_refresh()


func show_error(message: String) -> void:
	_error_message = message
	_refresh()


func acknowledge_command(connected: bool, pending: bool) -> void:
	_error_message = ""
	if _last_command == "hero.allocate":
		_drafts.erase(_last_target)
		if _selected_hero == _last_target:
			for attr: String in _points:
				(_points[attr] as SpinBox).value = 0
				(_points[attr] as SpinBox).get_line_edit().text = "0"
	_last_command = ""
	_last_target = ""
	set_command_state(connected, pending)


func _data() -> Dictionary:
	return _view.get("heroes", {})


func _rows(key: String) -> Array:
	return _data().get(key, [])


func _find(key: String, id: Variant, field: String = "id") -> Dictionary:
	for row: Dictionary in _rows(key):
		if row.get(field) == id:
			return row
	return {}


func _hero() -> Dictionary:
	return _find("owned", _selected_hero)


func _structure_signature() -> String:
	var structure: Dictionary = {}
	for key: String in ["owned", "wild", "captives", "equipment", "items", "forge"]:
		var ids: Array = []
		for row: Dictionary in _rows(key):
			ids.append(str(row.get("id", row.get("line", str(row.get("slot", "")) + str(row.get("tier", ""))))))
		structure[key] = ids
	return JSON.stringify(structure)


func _fit_window() -> void:
	var available: Vector2 = Vector2(get_tree().root.size)
	if get_parent() is Control:
		available = (get_parent() as Control).size
	var width: int = mini(720, maxi(280, int(available.x) - 40))
	var height: int = mini(680, maxi(280, int(available.y) - 80))
	_scroll.custom_minimum_size = Vector2(width - 48, height - 90)
	min_size = Vector2i(width, height)
	size = min_size
	position = Vector2i((available - Vector2(size)) / 2.0)


func _label(text: String, font_size: int = 15) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 38
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


func _info(provider: Callable, parent: Node = null) -> Label:
	var label: Label = _label("")
	(parent if parent != null else _body).add_child(label)
	_labels.append({"label": label, "provider": provider})
	return label


func _action(provider: Callable, parent: Node = null) -> Button:
	var button: Button = _button("", func() -> void: _execute(provider))
	(parent if parent != null else _body).add_child(button)
	_actions.append({"button": button, "provider": provider})
	return button


func _command(label: String, type: String, args: Array, reason: String = "") -> Dictionary:
	return {"label": label, "type": type, "args": args, "reason": reason}


func _refresh() -> void:
	if not is_instance_valid(_status) or _updating:
		return
	_updating = true
	_status.text = _error_message if not _error_message.is_empty() else "正在结算，请稍候…" if _pending else "请先连接规则服务" if not _connected else "操作确认后自动保存"
	_status.modulate = Color("e7bc72") if not _error_message.is_empty() else Color.WHITE
	for entry: Dictionary in _labels:
		(entry.label as Label).text = str(entry.provider.call())
	for entry: Dictionary in _actions:
		var quote: Dictionary = entry.provider.call()
		var reason: String = str(quote.get("reason", ""))
		var button: Button = entry.button
		button.text = str(quote.get("label", "操作"))
		button.disabled = not _connected or _pending or not reason.is_empty()
		button.tooltip_text = reason
	_updating = false


func _execute(provider: Callable) -> void:
	if not _connected or _pending:
		return
	var quote: Dictionary = provider.call()
	if not str(quote.get("reason", "")).is_empty():
		show_error(str(quote.reason))
		return
	match str(quote.get("type", "")):
		"focus":
			focus_requested.emit(int(quote.args[0]), int(quote.args[1]))
		"dispatch":
			dispatch_requested.emit(str(quote.args[0]))
		_:
			_error_message = ""
			_pending = true
			_last_command = str(quote.type)
			_last_target = str(quote.args[0]) if _last_command == "hero.allocate" else ""
			_refresh()
			command_requested.emit(str(quote.type), quote.get("args", []))


func _build() -> void:
	if not is_instance_valid(_content):
		return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_actions.clear()
	_labels.clear()
	_points.clear()
	_hero_selector = null
	_item_selector = null
	_equipment_selector = null
	_forge_selector = null
	title = str(TITLES[_section])
	var tabs: GridContainer = GridContainer.new()
	tabs.columns = 2
	_content.add_child(tabs)
	for section: String in TITLES:
		var button: Button = _button(str(TITLES[section]), func() -> void: show_section(section, _view))
		button.disabled = section == _section
		tabs.add_child(button)
	_status = _label("", 13)
	_content.add_child(_status)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_body)
	match _section:
		"wild": _build_wild()
		"captives": _build_captives()
		"equipment": _build_equipment()
		_: _build_generals()
	_signature = _structure_signature()
	_refresh()


func _selector(rows: Array, selected: Variant, changed: Callable) -> OptionButton:
	var control: OptionButton = OptionButton.new()
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.clip_text = true
	control.custom_minimum_size.y = 38
	for row: Dictionary in rows:
		control.add_item(str(row.name))
		control.set_item_metadata(control.item_count - 1, row.id)
		if row.id == selected:
			control.select(control.item_count - 1)
	_body.add_child(control)
	control.item_selected.connect(func(index: int) -> void: changed.call(control.get_item_metadata(index)))
	return control


func _hero_control() -> void:
	_hero_selector = _selector(_rows("owned"), _selected_hero, func(id: Variant) -> void:
		_remember_draft()
		_selected_hero = str(id)
		_build())
	if _hero_selector.item_count > 0:
		_selected_hero = str(_hero_selector.get_item_metadata(_hero_selector.selected))
	else:
		_selected_hero = ""


func _cost(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in cost:
		if key == "jewels" and cost[key] is Dictionary:
			for jewel: String in cost[key]:
				if int(cost[key][jewel]) > 0:
					parts.append(str(_data().get("jewels", {}).get(jewel, jewel)) + " ×" + str(int(cost[key][jewel])))
		elif (cost[key] is int or cost[key] is float) and int(cost[key]) > 0:
			parts.append(str(RES_NAMES.get(key, key)) + " ×" + str(int(cost[key])))
	return "、".join(parts) if not parts.is_empty() else "无需消耗"


func _note(quote: Dictionary) -> String:
	return "\n" + str(quote.reason) if not str(quote.get("reason", "")).is_empty() else ""


func _attribute(value: Variant) -> String:
	# Buffs and leadership technology can produce real fractional attributes.
	return str(int(value)) if float(value) == float(int(value)) else str(value)


func _build_generals() -> void:
	_info(func() -> String: return "招贤馆 %d / %d（包含俘将）" % [int(_data().get("used", 0)), int(_data().get("capacity", 0))])
	_hero_control()
	if _hero().is_empty():
		_body.add_child(_label("暂时没有将领，请前往客栈招募。"))
		return
	_info(func() -> String:
		var h: Dictionary = _hero()
		return "%s · %d级 · 忠诚 %d\n勇武 %s · 统御 %s · 内政 %s · 智谋 %s · 统率 %s\n可分配属性点 %d%s" % [h.get("name", ""), int(h.get("level", 1)), int(h.get("loyalty", 80)), _attribute(h.get("atk", 0)), _attribute(h.get("def", 0)), _attribute(h.get("pol", 0)), _attribute(h.get("wis", 0)), _attribute(h.get("lead", 0)), int(h.get("points", 0)), _note(h)])
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	_body.add_child(grid)
	var saved: Dictionary = _drafts.get(_selected_hero, {})
	for attr: String in _data().get("attrs", {}):
		grid.add_child(_label(str(_data().attrs[attr]), 14))
		var spin: SpinBox = SpinBox.new()
		spin.min_value = 0
		spin.max_value = maxi(0, int(_hero().get("points", 0)))
		spin.step = 1
		spin.rounded = true
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(spin)
		_points[attr] = spin
		if saved.has(attr):
			spin.get_line_edit().text = str(saved[attr])
		spin.value_changed.connect(func(_value: float) -> void: _refresh())
		spin.get_line_edit().text_changed.connect(func(_text: String) -> void: _refresh())
	_action(func() -> Dictionary:
		var h: Dictionary = _hero()
		var points: Dictionary = _point_values()
		var total: int = 0
		for amount: int in points.values(): total += amount
		var reason: String = str(h.get("reason", ""))
		if reason.is_empty() and (total < 1 or total > int(h.get("points", 0))): reason = "可分配属性点不足，请调整加点"
		return _command("确认加点 · %s 点" % total, "hero.allocate", [_selected_hero, points], reason))
	_info(func() -> String:
		var q: Dictionary = _hero().get("drill", {})
		return "演练：黄金 ×%d，经验 +%d · 今日已用 %d 次%s" % [int(q.get("cost", 0)), int(q.get("xp", 0)), int(q.get("used", 0)), _note(q)])
	_action(func() -> Dictionary: return _command("演练", "hero.drill", [_selected_hero], str(_hero().get("drill", {}).get("reason", "请选择将领"))))
	for method: String in ["gold", "jewels"]:
		_info(func() -> String:
			var q: Dictionary = _reward(method)
			return "忠诚 %d → %d · %s%s" % [int(q.get("current", 0)), int(q.get("next", 0)), _cost(q.get("cost", {})), _note(q)])
		_action(func() -> Dictionary:
			var q: Dictionary = _reward(method)
			return _command("奖励黄金" if method == "gold" else "赠送珍宝", "wild.reward", [_selected_hero, method, q.get("key", "")], str(q.get("reason", "请选择将领"))))
	_info(func() -> String:
		var q: Dictionary = _hero().get("salary", {})
		return "补付欠饷：黄金 ×%d%s" % [int(q.get("cost", 0)), _note(q)])
	_action(func() -> Dictionary:
		var q: Dictionary = _hero().get("salary", {})
		return _command("补付欠饷", "payHeroArrears", [_selected_hero, q.get("key", "")], str(q.get("reason", "请选择将领"))))
	_body.add_child(_label("将领宝物", 17))
	_item_selector = _selector(_rows("items"), _selected_item, func(id: Variant) -> void: _selected_item = str(id); _refresh())
	_selected_item = str(_item_selector.get_item_metadata(_item_selector.selected)) if _item_selector.item_count > 0 else ""
	_info(func() -> String:
		var item: Dictionary = _find("items", _selected_item)
		return "%s ×%d\n%s" % [item.get("name", "暂无可赠送宝物"), int(item.get("count", 0)), item.get("description", "")])
	_action(func() -> Dictionary: return _command("赠送所选宝物", "useItem", [_selected_item, _selected_hero], "没有可赠送宝物" if _find("items", _selected_item).is_empty() else ""))


func _remember_draft() -> void:
	if _points.is_empty() or _selected_hero.is_empty(): return
	var values: Dictionary = {}
	for attr: String in _points:
		if is_instance_valid(_points[attr]): values[attr] = (_points[attr] as SpinBox).get_line_edit().text
	_drafts[_selected_hero] = values


func _point_values() -> Dictionary:
	var values: Dictionary = {}
	for attr: String in _points:
		var spin: SpinBox = _points[attr]
		var text: String = spin.get_line_edit().text.strip_edges()
		values[attr] = maxi(0, roundi(float(text))) if text.is_valid_float() else int(spin.value)
	return values


func _reward(method: String) -> Dictionary:
	for q: Dictionary in _hero().get("rewards", []):
		if q.get("method") == method: return q
	return {"reason": "请选择将领"}


func _build_wild() -> void:
	_body.add_child(_label("客栈打听 → 购买画像 → 定位出征 → 击败守军 → 招降。首次近郊目标适合骑兵快速抵达；无画像不能俘获。", 14))
	_info(func() -> String: return str(_data().get("discoverReason", "")))
	_action(func() -> Dictionary: return _command("在客栈打听线索", "wild.discover", [], str(_data().get("discoverReason", "请先连接规则服务"))))
	for entry: Dictionary in _rows("wild"):
		var line: String = str(entry.line)
		var card: VBoxContainer = _card()
		_info(func() -> String:
			var row: Dictionary = _find("wild", line, "line")
			var state_names: Dictionary = {"undiscovered": "尚未发现", "active": "线索有效", "captive": "已俘获，等待招降", "recruited": "已经归顺", "released": "已释放，可重新打听"}
			return "%s · %s · %s\n%s%s" % [row.get("name", ""), row.get("title", ""), row.get("region", ""), state_names.get(row.get("status", ""), ""), _note(row)], card)
		_info(func() -> String:
			var q: Dictionary = _find("wild", line, "line").get("portrait", {})
			return "画像：元宝 ×%d%s" % [int(q.get("price", 0)), _note(q)], card)
		_action(func() -> Dictionary:
			var q: Dictionary = _find("wild", line, "line").get("portrait", {})
			return _command("购买画像", "wild.buyPortrait", [line, q.get("key", "")], str(q.get("reason", "没有可用报价"))), card)
		_info(func() -> String:
			var row: Dictionary = _find("wild", line, "line")
			var node: Dictionary = row.get("node") if row.get("node") is Dictionary else {}
			return "%s（%d,%d）\n%s" % [node.get("name", "未知驻地"), int(node.get("x", 0)), int(node.get("y", 0)), row.get("dispatchReason", "")] if not node.is_empty() else "打听成功后显示驻地", card)
		_action(func() -> Dictionary:
			var node: Dictionary = _find("wild", line, "line").get("node") if _find("wild", line, "line").get("node") is Dictionary else {}
			return _command("地图定位", "focus", [node.get("x", 0), node.get("y", 0)], "尚无线索" if node.is_empty() else ""), card)
		_action(func() -> Dictionary:
			var row: Dictionary = _find("wild", line, "line")
			var node: Dictionary = row.get("node") if row.get("node") is Dictionary else {}
			return _command("选择部队出征", "dispatch", [node.get("id", "")], str(row.get("dispatchReason", "尚无线索"))), card)


func _card() -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var card: VBoxContainer = VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(card)
	return card


func _captive_quote(id: String, method: String) -> Dictionary:
	for q: Dictionary in _find("captives", id).get("quotes", []):
		if q.get("method") == method: return q
	return {"reason": "没有可用招降报价"}


func _build_captives() -> void:
	_info(func() -> String: return "招贤馆 %d / %d（包含俘将）\n战败俘将需要及时招降；容量、爵位与费用按当前报价核对。" % [int(_data().get("used", 0)), int(_data().get("capacity", 0))])
	if _rows("captives").is_empty(): _body.add_child(_label("暂无俘将。购买画像并击败驻地守军后，可在这里招降。"))
	for entry: Dictionary in _rows("captives"):
		var id: String = str(entry.id)
		var card: VBoxContainer = _card()
		_info(func() -> String:
			var row: Dictionary = _find("captives", id)
			return "%s · %d级 · 忠诚 %d\n%s" % [row.get("name", ""), int(row.get("level", 1)), int(row.get("loyalty", 40)), "野将俘虏" if row.get("kind") == "wild" else "战败俘将"], card)
		for method: String in ["gold", "jewels"]:
			_info(func() -> String:
				var q: Dictionary = _captive_quote(id, method)
				return "%s%s" % [_cost(q.get("cost", {})), _note(q)], card)
			_action(func() -> Dictionary:
				var q: Dictionary = _captive_quote(id, method)
				var type: String = "wild.recruit" if _find("captives", id).get("kind") == "wild" else "recruitDefeatedHero"
				return _command("黄金招降" if method == "gold" else "珍宝招降", type, [id, method, q.get("key", "")], str(q.get("reason", "没有可用报价"))), card)
		if entry.get("release") is Dictionary:
			_action(func() -> Dictionary:
				var q: Dictionary = _find("captives", id).get("release", {})
				return _command("释放俘将", "wild.release", [id, q.get("key", "")], "俘将状态已变化" if q.is_empty() else ""), card)


func _build_equipment() -> void:
	_info(func() -> String: return "装备 %d / %d · 铁匠铺 %d级\n穿戴、强化和回收均以当前规则报价为准。" % [_rows("equipment").size(), int(_data().get("equipmentCapacity", 50)), int(_data().get("smithLevel", 0))])
	_info(func() -> String: return str(_data().get("giftReason", "")))
	_action(func() -> Dictionary: return _command("领取将领装备礼包", "hero.gift", [], str(_data().get("giftReason", "没有可用报价"))))
	for expansion: Dictionary in _data().get("expansions", []):
		var item: String = str(expansion.id)
		_action(func() -> Dictionary:
			var row: Dictionary = {}
			for candidate: Dictionary in _data().get("expansions", []):
				if candidate.get("id") == item: row = candidate
			return _command("%s扩容 · 持有 %d" % [row.get("name", "武器架"), int(row.get("count", 0))], "hero.expand", [item], str(row.get("reason", "没有武器架"))))
	_equipment_selector = _selector(_rows("equipment"), _selected_equipment, func(id: Variant) -> void: _selected_equipment = int(id); _refresh())
	_selected_equipment = int(_equipment_selector.get_item_metadata(_equipment_selector.selected)) if _equipment_selector.item_count > 0 else 0
	_hero_control()
	_info(func() -> String:
		var e: Dictionary = _find("equipment", _selected_equipment)
		if e.is_empty(): return "暂无装备；可以领取礼包或打造。"
		var stats: PackedStringArray = []
		for attr: String in e.get("stats", {}): stats.append(str(_data().get("attrs", {}).get(attr, attr)) + " +" + str(int(e.stats[attr])))
		return "%s · %s +%d · 需要%d级\n%s\n穿戴：%s" % [e.get("name", ""), e.get("quality", ""), int(e.get("enhanceLevel", 0)), int(e.get("requiredLevel", 1)), "、".join(stats), e.get("wearerName", "") if not str(e.get("wearerName", "")).is_empty() else "未穿戴"])
	_info(func() -> String:
		var q: Dictionary = _find("equipment", _selected_equipment).get("enhance", {})
		return "强化消耗：%s%s" % [_cost(q), _note(q)] if not q.is_empty() else "")
	for operation: String in ["equip", "unequip", "enhance", "salvage"]:
		_action(func() -> Dictionary:
			var e: Dictionary = _find("equipment", _selected_equipment)
			var reason: String = "请选择装备" if e.is_empty() else ""
			if not e.is_empty():
				match operation:
					"equip":
						reason = "请选择将领"
						for q: Dictionary in e.get("equip", []):
							if q.get("id") == _selected_hero: reason = str(q.get("reason", ""))
					"unequip": reason = str(e.get("unequipReason", ""))
					"enhance": reason = str(e.get("enhance", {}).get("reason", ""))
					"salvage": reason = str(e.get("salvageReason", ""))
			var labels: Dictionary = {"equip": "穿戴到所选将领", "unequip": "卸下装备", "enhance": "强化装备", "salvage": "回收装备（消耗此件装备）"}
			return _command(str(labels[operation]), "hero." + operation, [_selected_equipment, _selected_hero] if operation == "equip" else [_selected_equipment], reason))
	_body.add_child(_label("打造装备", 17))
	var forge_options: Array = []
	for q: Dictionary in _rows("forge"): forge_options.append({"id": str(q.slot) + ":" + str(q.tier), "name": q.name})
	_forge_selector = _selector(forge_options, _selected_forge, func(id: Variant) -> void: _selected_forge = str(id); _refresh())
	_selected_forge = str(_forge_selector.get_item_metadata(_forge_selector.selected)) if _forge_selector.item_count > 0 else ""
	_info(func() -> String:
		var q: Dictionary = _forge_quote()
		return "需要铁匠铺 %d级 · %s%s" % [int(q.get("smith", 0)), _cost(q.get("cost", {})), _note(q)])
	_action(func() -> Dictionary:
		var q: Dictionary = _forge_quote()
		return _command("打造所选装备", "hero.forge", [q.get("slot", ""), q.get("tier", 0)], str(q.get("reason", "请选择装备"))))


func _forge_quote() -> Dictionary:
	for q: Dictionary in _rows("forge"):
		if str(q.slot) + ":" + str(q.tier) == _selected_forge: return q
	return {"reason": "请选择装备"}
