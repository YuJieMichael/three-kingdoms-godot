class_name KingdomPostBattleActions
extends PanelContainer

## Navigation only. Original losses are not treated as today's missing troops.
## The host routes to the current owned city; this panel never queues recovery.
signal route_requested(section: String)

var _report: Dictionary = {}
var _view: Dictionary = {}
var _connected: bool = false
var _pending: bool = false
var _summary: Label
var _context: Label
var _buttons: Dictionary = {}


func _ready() -> void:
	theme_type_variation = "InsetPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(column)
	var title: Label = _label(column, "战后整备", "SectionLabel")
	title.name = "RecoveryTitle"
	_summary = _label(column, "", "MutedLabel")
	_context = _label(column, "", "MutedLabel")
	for entry: Array in [["hospital", "查看当前伤兵"], ["training", "前往补兵训练"], ["cities", "选择原出发／驻守城池"], ["growth", "查看当前成长目标"]]:
		var section: String = str(entry[0])
		var button: Button = Button.new()
		button.text = str(entry[1])
		button.theme_type_variation = "UtilityButton"
		button.custom_minimum_size.y = 44.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(button)
		button.pressed.connect(func() -> void:
			if not button.disabled and button.is_visible_in_tree():
				route_requested.emit(section))
		_buttons[section] = button
	_render()


func update_context(report: Dictionary, view: Dictionary, connected: bool, pending: bool) -> void:
	_report = report.duplicate(true)
	_view = view.duplicate(true)
	_connected = connected
	_pending = pending
	if is_instance_valid(_summary):
		_render()


func set_navigation_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	if is_instance_valid(_summary):
		_render()


func source_city() -> String:
	return str(_dictionary(_report.get("economy")).get("cityId", ""))


func _render() -> void:
	var economy: Dictionary = _dictionary(_report.get("economy"))
	var city_id: String = source_city()
	var current: Dictionary = _dictionary(_view.get("city"))
	var at_source: bool = not city_id.is_empty() and city_id == str(current.get("id", ""))
	var owned_name: String = str(current.get("name", "当前城池")) if at_source else ""
	for city: Variant in _view.get("cityList", []):
		if city is Dictionary and str(city.get("id", "")) == city_id:
			owned_name = str(city.get("name", city_id))
	var defenders: bool = str(economy.get("scope", "")) == "defenders-total"
	var treatment: Dictionary = _dictionary(economy.get("treatment"))
	var pool: Dictionary = _dictionary(treatment.get("currentPool"))
	var pieces: PackedStringArray = []
	if not defenders and _valid_count(pool.get("people")) and _valid_count(pool.get("gold")):
		pieces.append("原城当前伤兵池 %d 人 · 治疗报价黄金 %d" % [int(pool.people), int(pool.gold)])
	pieces.append("查看后自行确认治疗或训练；不会自动补兵。")
	_summary.text = "\n".join(pieces)
	if city_id.is_empty():
		_context.text = "这份旧战报没有可确认的原城记录。可从城池列表选择自己的城池。"
	elif owned_name.is_empty():
		_context.text = "原出发／驻守城池已不在当前城池列表；请先选择仍拥有的城池。"
	elif not at_source:
		_context.text = "这份战报对应「%s」，当前查看「%s」。先在城池列表选择原城，再处理该城伤兵和训练。" % [owned_name, str(current.get("name", "当前城池"))]
	else:
		_context.text = "当前城池「%s」；旧战报的损失数不代表今天仍需补充的兵力。" % owned_name
	if defenders:
		_context.text += "\n守方合计包含盟友；以下入口查看本人当前城池的军队。"
	_buttons.hospital.visible = at_source
	_buttons.training.visible = at_source
	_buttons.cities.visible = not at_source
	_buttons.growth.visible = not bool(_report.get("shared", false))
	for button: Button in _buttons.values():
		button.disabled = not _connected or _pending or _view.is_empty()


func _label(parent: Node, text: String, variation: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _valid_count(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) == floor(float(value))
