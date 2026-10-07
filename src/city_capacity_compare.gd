class_name KingdomCityCapacityCompare
extends VBoxContainer

## Presentation of rule-produced capacity alternatives. This control never queues work.
signal upgrade_requested(id: String, site: int)

var _body: VBoxContainer
var _toggle: Button
var _comparison: Dictionary = {}
var _selected_site: int = -1
var _selected_upgrade_site: int = -1
var _cost_formatter: Callable
var _time_formatter: Callable

func configure(comparison: Dictionary, selected_site: int, cost_formatter: Callable, time_formatter: Callable, selected_upgrade_site: int = -1) -> void:
	_comparison = comparison.duplicate(true)
	_selected_site = selected_site
	_selected_upgrade_site = selected_upgrade_site
	_cost_formatter = cost_formatter
	_time_formatter = time_formatter
	for child: Node in get_children():
		child.queue_free()
	_toggle = Button.new()
	_toggle.text = "比较新建与升级 · 已建 %d 座" % int(comparison.get("count", 0))
	_toggle.custom_minimum_size.y = 44.0
	_toggle.theme_type_variation = "UtilityButton"
	add_child(_toggle)
	_body = VBoxContainer.new()
	_body.visible = false
	add_child(_body)
	_toggle.pressed.connect(func() -> void:
		_body.visible = not _body.visible
		_toggle.text = ("收起收益对照" if _body.visible else "比较新建与升级 · 已建 %d 座" % int(_comparison.get("count", 0))))
	_render_comparison()

## Snapshots may change capacity while this read-only panel remains open.
## Keep the player's expansion and selected sites; never replace their quotation.
func refresh(comparison: Dictionary) -> bool:
	if _comparison == comparison:
		return false
	_comparison = comparison.duplicate(true)
	_toggle.text = "收起收益对照" if _body.visible else "比较新建与升级 · 已建 %d 座" % int(_comparison.get("count", 0))
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_render_comparison()
	return true

func _render_comparison() -> void:
	_body.add_child(_label("当前%s：%s · 施工中 %d 座" % [str(_comparison.get("capacityLabel", "容量")), _capacity_number(_comparison.get("currentCapacity")), int(_comparison.get("pendingCount", 0))]))
	var notice: String = str(_comparison.get("notice", ""))
	if not notice.is_empty():
		_body.add_child(_label(notice, Color("d9bd7d")))
	var new_quote: Variant = _comparison.get("new")
	if new_quote is Dictionary:
		var site: int = _selected_site if _selected_site >= 0 else int(new_quote.get("site", -1))
		_add_candidate(new_quote, "新建 1级 · 地块 %d" % (site + 1), false)
	else:
		_body.add_child(_label("本城暂无可建设的空地"))
	for candidate: Dictionary in _comparison.get("upgrades", []):
		var current: int = int(candidate.get("level", 0))
		var target: Variant = candidate.get("targetLevel")
		var caption: String = "%d级 · %s · 地块 %d" % [current, "已满级" if current >= 10 else "查看条件", int(candidate.get("site", -1)) + 1] if target == null else "升级 %d→%d级 · 地块 %d" % [current, int(target), int(candidate.get("site", -1)) + 1]
		if int(candidate.get("site", -1)) == _selected_upgrade_site:
			caption = "当前选择 · " + caption
		_add_candidate(candidate, caption, true)

func _label(text: String, color: Color = Color("c3bcaa")) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", 14)
	result.add_theme_color_override("font_color", color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

func _capacity_number(value: Variant) -> String:
	if value == null:
		return "—"
	if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)):
		return str(int(value))
	return str(value)

func _add_candidate(candidate: Dictionary, title: String, upgrade: bool) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = "InsetPanel"
	card.set_meta("capacity_candidate_site", int(candidate.get("site", -1)))
	_body.add_child(card)
	var rows: VBoxContainer = VBoxContainer.new()
	card.add_child(rows)
	rows.add_child(_label(title, Color("f1ead9")))
	var effect: Variant = candidate.get("effectDelta")
	if effect != null:
		rows.add_child(_label("%s +%s · 完成后 %s" % [str(_comparison.get("capacityLabel", "容量")), _capacity_number(effect), _capacity_number(candidate.get("capacityAfter"))], Color("b2c9a4")))
	var cost: Dictionary = candidate.get("cost", {})
	if not cost.is_empty():
		rows.add_child(_label("消耗 " + str(_cost_formatter.call(cost))))
		rows.add_child(_label("工期 " + str(_time_formatter.call(float(candidate.get("seconds", candidate.get("time", 0)))))))
	var reason: String = str(candidate.get("reason", ""))
	if reason.is_empty() and candidate.get("requirement") != null:
		reason = str(candidate.requirement)
	if not reason.is_empty():
		rows.add_child(_label(reason, Color("e1b073")))
	if upgrade:
		var action: Button = Button.new()
		action.text = "查看地块 %d 升级" % (int(candidate.get("site", -1)) + 1)
		action.custom_minimum_size.y = 44.0
		action.pressed.connect(func() -> void: upgrade_requested.emit(str(candidate.get("id", _comparison.get("id", ""))), int(candidate.get("site", -1))))
		rows.add_child(action)
