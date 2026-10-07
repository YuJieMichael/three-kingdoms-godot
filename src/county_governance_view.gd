class_name KingdomCountyGovernanceView
extends VBoxContainer

## Actor-owned city presentation. Costs, development conditions and commands
## come from the current canonical DTO; navigation never switches a city here.
signal route_requested(section: String, target: String)
signal command_requested(type: String, args: Array)

const RESOURCE_NAMES: Dictionary = {"food": "粮草", "wood": "木材", "stone": "石料", "iron": "铁锭", "gold": "黄金"}
const CHECK_NAMES: Dictionary = {"hall": "官府等级", "morale": "民心", "population": "人口", "plots": "已建设资源田"}
const NAMED_TIERS: Array[String] = ["county", "prefecture", "province", "capital"]

var _view: Dictionary = {}
var _connected: bool = false
var _pending: bool = false
var _built: bool = false
var _title: Label
var _empty_info: Label
var _empty_action: Button
var _body: VBoxContainer
var _identity_info: Label
var _development_info: Label
var _claim: Button
var _relief_info: Label
var _relief: Button
var _levy_info: Label
var _levy: Button
var _supply_info: Label
var _status: Label
var _empty_route: String = "cities"
var _empty_target: String = ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_title = _label(self, "县城治理", "TitleLabel")
	_empty_info = _label(self, "等待当前城池信息…")
	_empty_action = _button(self, "查看己方城池", func() -> void: route_requested.emit(_empty_route, _empty_target))
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	add_child(_body)
	var identity: VBoxContainer = _section("本城身份")
	_identity_info = _label(identity, "")
	_button(identity, "任命城守／调整税率", func() -> void: route_requested.emit("governance", _current_city_id()))
	var development: VBoxContainer = _section("稳定发展")
	_development_info = _label(development, "")
	_claim = _button(development, "领取发展奖励", _claim_development)
	var relief: VBoxContainer = _section("安民：赈灾")
	_relief_info = _label(relief, "")
	_relief = _button(relief, "确认赈灾", _execute_civic.bind("relief"))
	_button(relief, "其他安民与征收", func() -> void: route_requested.emit("civic", _current_city_id()))
	var levy: VBoxContainer = _section("征粮")
	_levy_info = _label(levy, "")
	_levy = _button(levy, "确认征粮", _execute_civic.bind("levy_food"))
	var supply: VBoxContainer = _section("补给与驻军")
	_supply_info = _label(supply, "")
	_button(supply, "安排运输／调遣", func() -> void: route_requested.emit("logistics", _current_city_id()))
	_button(supply, "查看己方城池", func() -> void: route_requested.emit("cities", ""))
	_status = _label(self, "", "MutedLabel")
	_built = true
	_render()


func update_view(view: Dictionary) -> void:
	_view = view.duplicate(true)
	if _built:
		_render()


func set_command_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	if _built:
		_render()


func _current_city_id() -> String:
	return str(_dictionary(_view.get("city")).get("id", ""))


func _current_city() -> Dictionary:
	var city_id: String = _current_city_id()
	var realm: Dictionary = _dictionary(_view.get("realmManagement"))
	if city_id.is_empty() or str(realm.get("currentCity", "")) != city_id or bool(realm.get("shared", false)):
		return {}
	for row: Dictionary in realm.get("cities", []):
		if str(row.get("id", "")) == city_id:
			return row
	return {}


func _has_identity(city: Dictionary) -> bool:
	var identity: Dictionary = _dictionary(city.get("identity"))
	return bool(identity.get("owned", false)) and str(identity.get("id", "")) == str(city.get("node", "")) and str(identity.get("tier", "")) in NAMED_TIERS


func _render() -> void:
	var city: Dictionary = _current_city()
	var named: bool = _has_identity(city)
	_body.visible = named
	_empty_info.visible = not named
	_empty_action.visible = not named
	_status.text = "正在确认操作，请等待实际回执。" if _pending else "连接后可确认本城治理操作。" if not _connected else "政令与领奖均需手动确认；运输往返，调遣驻城。"
	if not named:
		_render_empty()
		_claim.disabled = true
		_relief.disabled = true
		_levy.disabled = true
		return
	var identity: Dictionary = city.identity
	var strategy: Dictionary = _dictionary(city.get("strategy"))
	_title.text = str(city.get("name", "当前城池")) + " · " + str(identity.get("tierName", "名城"))
	var identity_lines: PackedStringArray = [
		"资源田最高 %s 级 · 本城黄金税收系数 ×%s" % [_number_text(identity.get("plotMax")), _number_text(identity.get("goldFactor"))],
		"定位：" + str(strategy.get("name", "未提供")),
		str(strategy.get("description", "")),
		"人口 %s · 民心 %s · 民怨 %s" % [_number_text(_view.get("population")), _number_text(_view.get("morale")), _number_text(_view.get("unrest"))],
	]
	_identity_info.text = "\n".join(identity_lines)
	_render_development(city)
	_render_civic("relief", _relief_info, _relief)
	_render_civic("levy_food", _levy_info, _levy)
	var army: Dictionary = _dictionary(city.get("army"))
	var soldiers: int = 0
	for count: Variant in army.values():
		if _number(count) and float(count) >= 0.0:
			soldiers += int(count)
	var soldier_text: String = "%d 人" % soldiers if not army.is_empty() else "未提供"
	_supply_info.text = "本城驻军 %s · 粮草 %s\n运输会将物资送入本城，护送部队返回；调遣会把兵力与带队将领留在目标城。出发城、数量、粮耗和耗时请在派遣前预览。" % [soldier_text, _number_text(_dictionary(_view.get("res")).get("food"))]
	if not army.is_empty() and soldiers > 0:
		var food_seconds: Variant = city.get("foodSeconds")
		if _number(food_seconds):
			_supply_info.text += "\n当前净耗粮下，粮草可维持 %s 秒。" % _number_text(food_seconds)


func _render_empty() -> void:
	_title.text = "县城治理"
	_empty_route = "cities"
	_empty_target = ""
	_empty_action.text = "查看己方城池"
	var realm: Dictionary = _dictionary(_view.get("realmManagement"))
	if _view.is_empty():
		_empty_info.text = "等待当前城池信息…"
	elif bool(realm.get("shared", false)):
		_empty_info.text = "当前房间尚未提供私人县城治理报价，可在己方城池中查看实际进度。"
	else:
		var owned_names: PackedStringArray = []
		for city: Dictionary in realm.get("cities", []):
			if _has_identity(city): owned_names.append(str(city.get("name", city.get("id", ""))))
		if not owned_names.is_empty():
			_empty_info.text = "请切换到已占领的城池查看本城治理：" + "、".join(owned_names) + "。"
		else:
			_empty_info.text = "取得县城归属后，可管理新城民心、粮草和驻军，完成本城发展目标。攻城获胜且尚未易主时，仍需继续占领攻城。"
			_empty_route = "growth"
			_empty_action.text = "查看当前成长目标"
			for node: Dictionary in _view.get("nodes", []):
				if str(node.get("id", "")) == "fort" and not bool(node.get("hidden", false)) and bool(node.get("selectable", true)):
					_empty_route = "world"
					_empty_target = "fort"
					_empty_action.text = "查看古渡县城"
					break
	_empty_action.disabled = not _connected


func _render_development(city: Dictionary) -> void:
	var quote: Dictionary = _dictionary(city.get("development"))
	var lines: PackedStringArray = []
	if quote.is_empty():
		lines.append("当前城池的发展目标尚未提供。")
	else:
		for check: Dictionary in quote.get("checks", []):
			lines.append("%s · %s %s / %s" % ["已达成" if bool(check.get("complete", false)) else "待完成", str(CHECK_NAMES.get(str(check.get("id", "")), check.get("id", "目标"))), _number_text(check.get("current")), _number_text(check.get("required"))])
		lines.append("原规则奖励：" + _resources_text(quote.get("reward")))
		lines.append("本城发展奖励已领取。" if bool(quote.get("claimed", false)) else str(quote.get("reason", "")) if not str(quote.get("reason", "")).is_empty() else "目标达成后可手动领取一次。")
	_development_info.text = "\n".join(lines)
	_claim.text = "发展奖励已领取" if bool(quote.get("claimed", false)) else "领取发展奖励"
	_claim.disabled = not _connected or _pending or _development_command().is_empty()


func _development_command() -> Dictionary:
	var city: Dictionary = _current_city()
	if not _has_identity(city): return {}
	var quote: Dictionary = _dictionary(city.get("development"))
	var command: Dictionary = _dictionary(quote.get("command"))
	var args: Variant = command.get("args")
	var quote_id: Variant = quote.get("id")
	var quote_key: Variant = quote.get("key")
	if not bool(quote.get("ready", false)) or bool(quote.get("claimed", false)) or not str(quote.get("reason", "")).is_empty(): return {}
	if not quote_id is String or not quote_key is String or quote_key.is_empty(): return {}
	if str(quote.get("city", "")) != _current_city_id() or quote_id != str(city.get("node", "")) or not quote.get("reward") is Dictionary or not quote.get("checks") is Array: return {}
	if str(command.get("type", "")) != "claimNamedCityDevelopment" or not args is Array or args != [quote_id, quote_key]: return {}
	return command


func _claim_development() -> void:
	if not _connected or _pending: return
	var command: Dictionary = _development_command()
	if command.is_empty(): return
	_pending = true
	_render()
	command_requested.emit(str(command.type), (command.args as Array).duplicate(true))


func _civic_row(id: String) -> Dictionary:
	if not _has_identity(_current_city()): return {}
	var war: Dictionary = _dictionary(_view.get("warManagement"))
	if str(war.get("cityId", "")) != _current_city_id(): return {}
	for row: Dictionary in _dictionary(war.get("civic")).get("rows", []):
		if str(row.get("id", "")) == id: return row
	return {}


func _civic_command(id: String) -> Dictionary:
	var row: Dictionary = _civic_row(id)
	var command: Dictionary = _dictionary(row.get("command"))
	var args: Variant = command.get("args")
	if not bool(row.get("enabled", false)) or not str(row.get("reason", "")).is_empty(): return {}
	if not row.get("cost") is Dictionary or not row.get("reward") is Dictionary or not row.get("effects") is Dictionary: return {}
	if str(command.get("type", "")) != "executeCivicOrder" or not args is Array or args != [id]: return {}
	return command


func _render_civic(id: String, info: Label, button: Button) -> void:
	var row: Dictionary = _civic_row(id)
	if row.is_empty():
		info.text = "当前城池的政令报价尚未提供，请刷新后查看。"
	else:
		var effects: Dictionary = _dictionary(row.get("effects"))
		var lines: PackedStringArray = [
			"费用：" + _resources_text(row.get("cost")),
			"获得：" + _resources_text(row.get("reward")),
			"民心 %s · 民怨 %s · 人口 %s" % [_signed_text(effects.get("morale")), _signed_text(effects.get("unrest")), _signed_text(effects.get("population"))],
		]
		var end: Variant = row.get("cooldownEnd")
		var now: Variant = _dictionary(_view.get("warManagement")).get("now")
		if _number(end) and _number(now) and float(end) > float(now):
			lines.append("冷却剩余：%d 秒" % ceili((float(end) - float(now)) / 1000.0))
		var reason: String = str(row.get("reason", ""))
		if not reason.is_empty(): lines.append(reason)
		elif not bool(row.get("enabled", false)): lines.append("当前不可执行。")
		elif _civic_command(id).is_empty(): lines.append("报价资料未完整提供，请刷新后确认。")
		info.text = "\n".join(lines)
	button.disabled = not _connected or _pending or _civic_command(id).is_empty()


func _execute_civic(id: String) -> void:
	if not _connected or _pending: return
	var command: Dictionary = _civic_command(id)
	if command.is_empty(): return
	_pending = true
	_render()
	command_requested.emit(str(command.type), (command.args as Array).duplicate(true))


func _resources_text(value: Variant) -> String:
	if not value is Dictionary: return "未提供"
	var rows: PackedStringArray = []
	for id: String in RESOURCE_NAMES:
		if value.has(id) and _number(value[id]) and float(value[id]) > 0.0:
			rows.append("%s ×%s" % [str(RESOURCE_NAMES[id]), _number_text(value[id])])
	return "、".join(rows) if not rows.is_empty() else "无"


func _number_text(value: Variant) -> String:
	if not _number(value): return "未提供"
	return str(int(value)) if float(value) == float(int(value)) else "%.2f" % float(value)


func _signed_text(value: Variant) -> String:
	if not _number(value): return "未提供"
	return ("+" if float(value) >= 0.0 else "") + _number_text(value)


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _section(title: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "SectionPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_label(column, title, "SectionLabel")
	return column


func _label(parent: Node, text: String, variation: String = "") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
