class_name KingdomIntelPanel
extends PanelContainer

## Only actor-safe projected intelligence is accepted. No game/save lookup.
var _node: Dictionary = {}
var _names: Dictionary = {}
var _now_ms: float = 0.0
var _heading: Label
var _precision: Label
var _details: Label
var _validity: Label
var _outcome: Label


func _ready() -> void:
	theme_type_variation = "InsetPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(column)
	_heading = _label(column, "战前情报", "SectionLabel")
	_precision = _label(column, "", "SectionLabel")
	_details = _label(column, "")
	_validity = _label(column, "", "MutedLabel")
	_outcome = _label(column, "", "MutedLabel")
	_render()


func set_intel(node: Dictionary, units: Array, now_ms: float) -> void:
	_node = node.duplicate(true)
	_names.clear()
	for unit: Dictionary in units:
		_names[str(unit.get("id", ""))] = str(unit.get("name", unit.get("id", "士兵")))
	_now_ms = now_ms
	if is_instance_valid(_precision):
		_render()


func _render() -> void:
	_heading.text = "战前情报" + (" · " + str(_node.get("name", "目标")) if not _node.is_empty() else "")
	var intel: Dictionary = _dictionary(_node.get("intel"))
	var precision: String = str(intel.get("precision", "unknown"))
	if _node.get("hidden", false) or _node.get("selectable", true) == false:
		precision = "unknown"
		intel = {}
	elif precision != "expired" and intel.get("public", false):
		precision = "public"
	var expires: float = float(intel.get("expiresAt", 0)) if _number(intel.get("expiresAt")) else 0.0
	if precision != "public" and expires > 0.0 and _now_ms > 0.0 and _now_ms >= expires:
		precision = "expired"
	var lines: PackedStringArray = []
	match precision:
		"public", "exact":
			_precision.text = "公开守军情报" if precision == "public" else "精确侦察情报"
			var army: Dictionary = _dictionary(intel.get("army"))
			if army.is_empty():
				army = _dictionary(_node.get("army"))
			for id: String in army:
				if _number(army[id]) and float(army[id]) >= 0:
					lines.append("%s %d 人" % [_unit_name(id), int(army[id])])
			if lines.is_empty():
				lines.append("守军数量尚未提供，不能按零守军判断。")
		"bands":
			_precision.text = "区间侦察情报"
			for id: String in _dictionary(intel.get("bands")):
				var band: Dictionary = _dictionary(intel.bands[id])
				if _number(band.get("min")) and _number(band.get("max")) and float(band.min) >= 0 and float(band.max) >= float(band.min):
					lines.append("%s %d–%d 人" % [_unit_name(id), int(band.min), int(band.max)])
			if lines.is_empty():
				lines.append("此次情报未提供兵力区间。")
		"types":
			_precision.text = "兵种侦察情报 · 数量未知"
			var types: Variant = intel.get("types", [])
			if types is Array:
				for id: Variant in types:
					if id is String:
						lines.append(_unit_name(id))
			if lines.is_empty():
				lines.append("此次情报未提供兵种明细。")
		"failed":
			_precision.text = "侦察失败"
			lines.append("本次未获得有效守军情报，可调整斥候数量后重新预览。")
		"expired":
			_precision.text = "情报已过期"
			lines.append("旧守军数量不再显示，请重新侦察。")
		"legacy":
			_precision.text = "旧制情报 · 精度未确认"
			lines.append("旧记录不能确认当前守军数量，建议重新侦察。")
		_:
			_precision.text = "未侦察 · 守军未知"
			lines.append("派遣斥候后按实际情报配兵；未知不表示没有守军。")
	_details.text = "\n".join(lines)
	_validity.text = "公示情报无需侦察有效期。" if precision == "public" else "有效期已结束。" if precision == "expired" else ""
	if precision in ["exact", "bands", "types"]:
		var age: String = ""
		if _number(intel.get("at")) and _now_ms >= float(intel.at):
			age = "获得于 %s前" % _duration((_now_ms - float(intel.at)) / 1000.0)
		var lifetime: String = "有效期尚未提供"
		if expires > 0.0 and _now_ms > 0.0:
			lifetime = "有效期剩余 " + _duration((expires - _now_ms) / 1000.0)
		_validity.text = (age + " · " if not age.is_empty() else "") + lifetime
	_validity.visible = not _validity.text.is_empty()
	var outcome: PackedStringArray = []
	if _number(intel.get("lost")) and float(intel.lost) >= 0:
		outcome.append("本次斥候损失 %d 人" % int(intel.lost))
	if _number(intel.get("survivors")) and float(intel.survivors) >= 0:
		outcome.append("返程斥候 %d 人" % int(intel.survivors))
	_outcome.text = " · ".join(outcome)
	_outcome.visible = not outcome.is_empty()


func _unit_name(id: String) -> String:
	return str(_names.get(id, id))


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _duration(value: float) -> String:
	var seconds: int = maxi(0, ceili(value))
	return "%d时%02d分" % [seconds / 3600, (seconds % 3600) / 60] if seconds >= 3600 else "%d分%02d秒" % [seconds / 60, seconds % 60]


func _label(parent: Node, text: String, variation: String = "") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
