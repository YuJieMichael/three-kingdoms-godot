class_name KingdomReportEconomyView extends VBoxContainer

## Read-only presentation of the bridge's canonical report economy DTO.
## This view never reconstructs receipts, prices units, or issues commands.
const RESOURCE_IDS: Array[String] = ["food", "wood", "stone", "iron", "gold"]
const RESOURCE_NAMES: Dictionary = {"food": "粮草", "wood": "木材", "stone": "石料", "iron": "铁锭", "gold": "黄金"}
const LOSS_COLOR: Color = Color("ef9c8c")
const GAIN_COLOR: Color = Color("c8d7b0")
var _economy: Dictionary = {}
var _cards: GridContainer
var _resource_rows: Dictionary = {}
var _status_label: Label


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	resized.connect(_fit_cards)


func _ready() -> void:
	if get_child_count() == 0:
		_render()
	_fit_cards()


func set_economy(economy: Dictionary) -> void:
	_economy = economy.duplicate(true)
	_render()


func _render() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_resource_rows.clear()
	_cards = null
	add_child(_label("恢复兵力预算后余额", "SectionLabel"))
	if _economy.is_empty():
		_status_label = _label("缺少收支记录，无法确认实际入库或恢复预算。", "MutedLabel")
		add_child(_status_label)
		return
	var status: String = str(_economy.get("status", "unknown"))
	_status_label = _label(_status_text(status))
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", KingdomUiTheme.GOLD if status != "delivered" else GAIN_COLOR)
	add_child(_status_label)
	var canonical: bool = str(_economy.get("basis", "")) == "current-canonical-prices"
	add_child(_label("恢复预算按当前规则估算，尚未扣款；各资源分别计算。" if canonical else "恢复预算来源未确认，不能作为当前规则报价。", "MutedLabel"))
	if str(_economy.get("scope", "")) == "defenders-total":
		add_child(_label("守方合计含盟友；恢复预算不能分摊本人。", "MutedLabel"))
	_cards = GridContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards.columns = 1
	add_child(_cards)
	for id: String in RESOURCE_IDS:
		_build_resource_card(id, status, canonical)
	var replacement: Dictionary = _dictionary(_economy.get("replacement"))
	var details: PackedStringArray = []
	if _valid_number(replacement.get("soldiers")):
		details.append("永久损失 %s 名" % _number_text(float(replacement.soldiers)))
	if _valid_number(replacement.get("people")):
		details.append("补兵需征用人口 %s" % _number_text(float(replacement.people)))
	if _valid_number(replacement.get("seconds")):
		details.append("训练估算 %s 秒" % _number_text(float(replacement.seconds)))
	if not details.is_empty():
		add_child(_label(" · ".join(details), "MutedLabel"))
	var treatment: Dictionary = _dictionary(_economy.get("treatment"))
	var wounded_caption: String = "按本战 %s 名伤兵估算" % _number_text(float(treatment.people)) if _valid_number(treatment.get("people")) else "按本战伤兵估算"
	add_child(_label("治疗预算%s，并非仍需支付；当前伤兵池另算。" % wounded_caption, "MutedLabel"))
	if not str(treatment.get("reason", "")).is_empty():
		add_child(_label(str(treatment.reason), "MutedLabel"))
	if treatment.get("available") is bool and not bool(treatment.available):
		add_child(_label("治疗预算仅供参考，不能据此确认当前可治疗数量。", "MutedLabel"))
	add_child(_label("余额是资源收入或损失扣除两项恢复预算后的估算，未执行补兵或治疗。", "MutedLabel"))
	var notes: Variant = _economy.get("notes", [])
	if notes is Array:
		for note: Variant in notes:
			if note is String and not note.is_empty():
				add_child(_label(note, "MutedLabel"))
	_fit_cards()


func _build_resource_card(id: String, status: String, canonical: bool) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "ResourcePanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)
	var name_label: Label = _label(str(RESOURCE_NAMES[id]), "SectionLabel")
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.add_theme_font_size_override("font_size", 16)
	heading.add_child(name_label)
	var net: Dictionary = _dictionary(_economy.get("net"))
	var net_resources: Variant = net.get("resources")
	var net_value: Variant = (net_resources as Dictionary).get(id, 0) if net_resources is Dictionary else null
	var net_label: Label = _label("预计余额 " + _resource_text(net_resources, id, "未提供", true) if canonical else "预计余额 来源未确认")
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	net_label.add_theme_font_size_override("font_size", 16)
	if _valid_number(net_value):
		net_label.add_theme_color_override("font_color", LOSS_COLOR if float(net_value) < 0 else GAIN_COLOR)
	heading.add_child(net_label)
	var metrics: GridContainer = GridContainer.new()
	metrics.columns = 2
	metrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	metrics.add_theme_constant_override("h_separation", 10)
	metrics.add_theme_constant_override("v_separation", 5)
	column.add_child(metrics)
	var loot_caption: String = "敌军掠走" if status == "lost" else "缴获"
	var loot: Label = _label(loot_caption + " " + _resource_text(_economy.get("loot"), id))
	var received: Label = _label("实际入库 " + _received_text(id, status))
	var replacement: Dictionary = _dictionary(_economy.get("replacement"))
	var treatment: Dictionary = _dictionary(_economy.get("treatment"))
	var replacement_label: Label = _label("补兵预算 " + (_resource_text(replacement.get("resources"), id, "未提供") if canonical else "来源未确认"))
	var treatment_label: Label = _label("治疗预算 " + (_resource_text(treatment.get("resources"), id, "未提供") if canonical else "来源未确认"))
	for label: Label in [loot, received, replacement_label, treatment_label]:
		label.add_theme_font_size_override("font_size", 14)
		metrics.add_child(label)
	_resource_rows[id] = {"panel": panel, "name": name_label, "net": net_label, "loot": loot, "received": received, "replacement": replacement_label, "treatment": treatment_label}


func _received_text(id: String, status: String) -> String:
	if status == "pending":
		return "尚未入库"
	if status == "retained":
		return "未交付"
	if status not in ["delivered", "lost"]:
		return "未确认"
	return _resource_text(_economy.get("received"), id)


func _status_text(status: String) -> String:
	match status:
		"pending": return "待返程 · 缴获尚未入库"
		"delivered": return "已确认入库 · 数额以凭据为准"
		"retained": return "驻扎保留 · 尚未交付城库"
		"lost": return "守方损失 · 敌军掠走物资"
	return "缺少入库凭据 · 实际入库未确认"


func _resource_text(resources: Variant, id: String, fallback: String = "未确认", signed: bool = false) -> String:
	if not resources is Dictionary:
		return fallback
	var value: Variant = resources.get(id, 0)
	if not _valid_number(value):
		return fallback
	var amount: float = float(value)
	return ("+" if signed and amount > 0 else "") + _number_text(amount)


func _number_text(value: float) -> String:
	var raw: String = str(int(round(value))) if is_equal_approx(value, round(value)) else String.num(value, 2)
	var sign: String = "-" if raw.begins_with("-") else ""
	if not sign.is_empty():
		raw = raw.substr(1)
	var parts: PackedStringArray = raw.split(".")
	var whole: String = parts[0]
	var formatted: String = ""
	for i: int in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0:
			formatted += ","
		formatted += whole[i]
	return sign + formatted + ("." + parts[1] if parts.size() > 1 else "")


func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _label(text: String, variation: String = "") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _fit_cards() -> void:
	if is_instance_valid(_cards):
		_cards.columns = 2 if size.x >= 680.0 else 1
