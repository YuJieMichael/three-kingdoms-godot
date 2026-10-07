class_name KingdomReportLootView
extends VBoxContainer

## Read-only report receipts. Names come from the service's item/equipment metadata.
## Navigation opens management screens; this view never grants or claims a reward.
signal navigate_requested(section: String)

var _report: Dictionary = {}
var _view: Dictionary = {}
var _connected: bool = true
var _pending: bool = false
var _buttons: Array[Button] = []


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)


func _ready() -> void:
	_render()


func set_report(report: Dictionary, view: Dictionary = {}) -> void:
	_report = report.duplicate(true)
	_view = view.duplicate(true)
	if is_inside_tree():
		_render()


func set_navigation_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	for button: Button in _buttons:
		button.disabled = not _connected or _pending


func _render() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_label("战利品与俘将", "SectionLabel")
	_label("资源交付见战后收支；当前物品、装备与将领状态可从下方查看。", "MutedLabel")
	_render_counts("itemDrops", "缴获道具", "item")
	_render_counts("jewelDrops", "获得珠宝", "jewel")
	_render_equipment()
	_render_general()
	_render_capacity()
	var prestige: Variant = _report.get("prestigeDelta")
	if _is_integer(prestige):
		_label("声望 %s%d" % ["+" if float(prestige) >= 0.0 else "", int(prestige)])
	_button("查看背包", "inventory")
	if _has_equipment() or _positive_count(_report.get("equipmentDiscarded")):
		_button("查看装备工坊", "equipment")
	var wild: Variant = _report.get("wildGeneral")
	if wild is Dictionary and str(wild.get("status", "")) == "captured":
		_button("查看俘将招降", "hero_captives")
	if _has_captures() or _positive_count(_report.get("captureDiscarded")):
		_button("查看士兵俘虏", "soldier_captives")
	set_navigation_state(_connected, _pending)


func _render_counts(field: String, title: String, kind: String) -> void:
	_label(title, "SectionLabel")
	var drops: Variant = _report.get(field)
	if not drops is Dictionary:
		_label("共享战报未提供此项记录。" if bool(_report.get("shared", false)) else "此战报未记录此项奖励。", "MutedLabel")
		return
	var shown: bool = false
	var invalid: bool = false
	for id: Variant in drops:
		var count: Variant = drops[id]
		if not _is_count(count):
			invalid = true
			continue
		if float(count) <= 0.0:
			continue
		_label("%s ×%d" % [_reward_name(str(id), kind), int(count)])
		shown = true
	if invalid:
		_label("部分奖励数量无法确认。", "MutedLabel")
	elif not shown:
		_label("本战没有" + title + "。", "MutedLabel")


func _render_equipment() -> void:
	_label("缴获装备", "SectionLabel")
	var drops: Variant = _report.get("equipmentDrops")
	if not drops is Array:
		_label("共享战报未提供装备记录。" if bool(_report.get("shared", false)) else "此战报未记录装备奖励。", "MutedLabel")
		return
	if drops.is_empty():
		_label("本战没有缴获装备。", "MutedLabel")
		return
	for value: Variant in drops:
		if value is Dictionary and not value.is_empty():
			_label(_equipment_name(value) + " ×1")
		else:
			_label("一项装备记录无法确认。", "MutedLabel")


func _render_general() -> void:
	_label("俘将结果", "SectionLabel")
	if not _report.has("wildGeneral"):
		_label("共享战报未提供野将记录。" if bool(_report.get("shared", false)) else "此战报未记录野将结果。", "MutedLabel")
		return
	var value: Variant = _report.get("wildGeneral")
	if value == null:
		_label("本战没有野将俘获记录。", "MutedLabel")
		return
	if not value is Dictionary:
		_label("野将结果无法确认。", "MutedLabel")
		return
	var name: String = str(value.get("name", "野将"))
	var reason: String = str(value.get("reason", ""))
	match str(value.get("status", "")):
		"captured":
			var loyalty: Variant = value.get("loyalty")
			_label("本战俘获 %s%s；当前招降状态见俘将页面。" % [name, " · 忠诚 %d" % int(loyalty) if _is_count(loyalty) else ""])
		"portrait_required": _label("未俘获 " + name + ("：" + reason if not reason.is_empty() else " · 需要画像"), "MutedLabel")
		"released": _label("已释放 " + name + ("：" + reason if not reason.is_empty() else ""), "MutedLabel")
		_: _label(name + " · 此战报的俘获状态无法确认。", "MutedLabel")


func _render_capacity() -> void:
	var rows: Array[String] = []
	for entry: Array in [["lootDiscarded", "运力不足，未装载基础资源", "份"], ["bonusDiscarded", "运力不足，未装载额外资源", "份"], ["captureDiscarded", "押解或收容名额不足，释放士兵", "人"], ["equipmentDiscarded", "装备库已满，未收取装备", "件"]]:
		var value: Variant = _report.get(str(entry[0]))
		if _positive_count(value):
			rows.append("%s %d %s" % [str(entry[1]), int(value), str(entry[2])])
	if not rows.is_empty():
		_label("未能收取", "SectionLabel")
		for row: String in rows:
			var label: Label = _label(row)
			label.add_theme_color_override("font_color", Color("efb77f"))


func _reward_name(id: String, kind: String) -> String:
	if kind == "item":
		for key: String in ["inventoryManagement", "shop", "inventory"]:
			var source: Variant = _view.get(key, [])
			var rows: Variant = source.get("items", []) if source is Dictionary else source
			if rows is Array:
				for row: Variant in rows:
					if row is Dictionary and str(row.get("id", "")) == id and not str(row.get("name", "")).is_empty():
						return str(row.name)
	else:
		var heroes: Dictionary = _dictionary(_view.get("heroes"))
		var jewels: Dictionary = _dictionary(heroes.get("jewels"))
		if jewels.has(id) and jewels[id] is String and not str(jewels[id]).is_empty():
			return str(jewels[id])
		var progression: Dictionary = _dictionary(_view.get("progression"))
		var honors: Dictionary = _dictionary(progression.get("honors"))
		var rows: Variant = honors.get("jewels", [])
		if rows is Array:
			for row: Variant in rows:
				if row is Dictionary and str(row.get("id", "")) == id and not str(row.get("name", "")).is_empty():
					return str(row.name)
	return ("道具" if kind == "item" else "珠宝") + "（" + id + "）"


func _equipment_name(equipment: Dictionary) -> String:
	var name: String = str(equipment.get("name", ""))
	var heroes: Dictionary = _dictionary(_view.get("heroes"))
	var forge: Variant = heroes.get("forge", [])
	if name.is_empty() and forge is Array:
		for row: Variant in forge:
			if row is Dictionary and str(row.get("slot", "")) == str(equipment.get("slot", "")) and row.get("tier") == equipment.get("tier"):
				name = str(row.get("name", ""))
				var quality: String = str(row.get("quality", ""))
				if not quality.is_empty():
					name = quality + " · " + name
				break
	if name.is_empty():
		name = "装备（%s）" % str(equipment.get("id", "未知记录"))
	var enhance: Variant = equipment.get("enhance")
	if _positive_count(enhance):
		name += " · 强化 +%d" % int(enhance)
	return name


func _has_equipment() -> bool:
	var drops: Variant = _report.get("equipmentDrops")
	return drops is Array and not drops.is_empty()


func _has_captures() -> bool:
	var captures: Variant = _report.get("captures")
	if captures is Dictionary:
		for count: Variant in captures.values():
			if _positive_count(count):
				return true
	return false


func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and absf(float(value)) <= 9007199254740991.0


func _is_count(value: Variant) -> bool:
	return _is_integer(value) and float(value) >= 0.0


func _positive_count(value: Variant) -> bool:
	return _is_count(value) and float(value) > 0.0


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _label(text: String, variation: String = "") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
	return label


func _button(text: String, section: String) -> void:
	var button: Button = Button.new()
	button.text = text
	button.theme_type_variation = "UtilityButton"
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(func() -> void:
		if _connected and not _pending:
			navigate_requested.emit(section))
	add_child(button)
	_buttons.append(button)
