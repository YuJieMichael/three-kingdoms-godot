class_name KingdomRealmDialog
extends AcceptDialog

signal command_requested(type: String, args: Array)
signal quote_requested(kind: String, args: Array, request_id: String)
signal focus_requested(x: int, y: int)

const SECTIONS: Dictionary = {"cities": "城池任职", "logistics": "运输调遣", "plots": "城外建设", "holdings": "领地采集", "automation": "挂机设置"}
const SuburbScript: GDScript = preload("res://src/suburb_view.gd")
const RES_NAMES: Dictionary = {"food": "粮草", "wood": "木材", "stone": "石料", "iron": "铁锭", "gold": "黄金"}
const FIELD_NAMES: Dictionary = {"farm": "粮田", "lumber": "木场", "quarry": "石场", "mine": "铁矿"}
var _view: Dictionary = {}
var _section: String = "cities"
var _connected: bool = false
var _pending: bool = false
var _error: String = ""
var _scroll: ScrollContainer
var _content: VBoxContainer
var _status: Label
var _live: Array[Callable] = []
var _actions: Array[Dictionary] = []
var _drafts: Dictionary = {}
var _scrolls: Dictionary = {}
var _structure: String = ""
var _source: String = ""
var _quote_id: String = ""
var _quote_fingerprint: String = ""
var _quote_command: Dictionary = {}
var _quote_label: Label
var _quote_args: Callable
var _quote_kind: String = ""
var _quote_busy: bool = false
var _selected_plot: int = -1
var _templates_open: bool = false
var _plot_map_open: bool = false

func _ready() -> void:
	get_ok_button().text = "关闭"
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_build()

func show_section(section: String, view: Dictionary) -> void:
	_view = view
	section = str({"outer": "plots", "realm": "cities", "gather": "holdings"}.get(section, section))
	var next: String = section if SECTIONS.has(section) else "cities"
	if is_instance_valid(_scroll):
		_scrolls[_section] = _scroll.scroll_vertical
	_section = next
	_error = ""
	var source: String = str(_realm().get("currentCity", ""))
	if source != _source:
		_selected_plot = -1
		_templates_open = false
		_plot_map_open = false
	_source = source
	_structure = _structure_signature()
	_build()
	_fit()
	popup_centered()

func update_view(view: Dictionary) -> void:
	_view = view
	if not is_instance_valid(_content):
		return
	var source: String = str(_realm().get("currentCity", ""))
	var structure: String = _structure_signature()
	if source != _source:
		_source = source
		_drafts.clear()
		_selected_plot = -1
		_templates_open = false
		_plot_map_open = false
		_error = "已切换城池，请核对新的驻军和资源"
	if structure != _structure:
		_scrolls[_section] = _scroll.scroll_vertical
		_structure = structure
		_build()
	else:
		for refresh: Callable in _live:
			refresh.call()
	_refresh_actions()
	_status.text = _error if not _error.is_empty() else "操作正在确认…" if _pending else "连接后可操作" if not _connected else "当前城池：" + str(_view.get("city", {}).get("name", "主城"))

func set_command_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	update_view(_view)

func show_error(message: String) -> void:
	_error = message
	_quote_busy = false
	update_view(_view)

func acknowledge_command(connected: bool, pending: bool) -> void:
	_error = ""
	_invalidate_quote()
	set_command_state(connected, pending)

func receive_quote(payload: Dictionary) -> void:
	if str(payload.get("requestId", "")) != _quote_id or not visible or not _quote_args.is_valid():
		return
	_quote_busy = false
	if _quote_fingerprint != JSON.stringify([_source, _quote_args.call()]):
		_invalidate_quote()
		return
	var q: Dictionary = payload.get("quote", {})
	var reason: String = str(q.get("reason", ""))
	_quote_command = q.get("command", {}).duplicate(true) if reason.is_empty() else {}
	var lines: PackedStringArray = []
	if q.has("cost"):
		lines.append("建设费用：" + _cost(q.cost))
	if q.has("seconds"):
		lines.append("单程 %s · 粮草 %d · 运载上限 %d" % [_duration(float(q.seconds)), int(q.get("foodCost", 0)), int(q.get("carry", 0))])
	if not reason.is_empty():
		lines.append(reason)
	else:
		lines.append("条件满足，可以确认")
	_quote_label.text = "\n".join(lines)
	_refresh_actions()

func _realm() -> Dictionary:
	return _view.get("realmManagement", {})

func _structure_signature() -> String:
	return JSON.stringify([_realm().get("currentCity", ""), _realm().get("cities", []).map(func(c: Dictionary) -> String: return str(c.id)), _realm().get("generals", []).map(func(g: Dictionary) -> Array: return [g.id, g.get("busy", false)]), _view.get("plots", []).map(func(p: Dictionary) -> Array: return [p.get("index"), p.get("id"), p.get("level"), p.get("unlocked")]), _view.get("plotOptions", []).map(func(p: Dictionary) -> Array: return [p.get("id"), p.get("name")]), _realm().get("holdings", []).map(func(h: Dictionary) -> Array: return [h.id, h.get("gathering") != null, h.get("garrison") != null]), _realm().get("logistics", []).map(func(j: Dictionary) -> String: return str(j.id))])

func _fit() -> void:
	var available: Vector2 = (get_parent() as Control).size if get_parent() is Control else Vector2(get_tree().root.size)
	var target_size: Vector2i = Vector2i(mini(730, maxi(280, int(available.x) - 40)), mini(700, maxi(280, int(available.y) - 80)))
	_scroll.custom_minimum_size = Vector2(target_size.x - 48, target_size.y - 90)
	min_size = target_size
	size = min_size
	position = Vector2i((available - Vector2(size)) / 2.0)

func _build() -> void:
	if not is_instance_valid(_content):
		return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_live.clear()
	_actions.clear()
	_quote_args = Callable()
	_quote_label = null
	_invalidate_quote()
	title = str(SECTIONS[_section])
	var tabs: GridContainer = GridContainer.new()
	tabs.columns = 3
	_content.add_child(tabs)
	for section: String in SECTIONS:
		var tab: Button = Button.new()
		tab.text = str(SECTIONS[section])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.disabled = section == _section
		tab.pressed.connect(func() -> void: show_section(section, _view))
		tabs.add_child(tab)
	_status = _label("")
	_content.add_child(_status)
	if _realm().is_empty():
		_content.add_child(_label("连接规则服务后显示城池、领地与建设安排。"))
	else:
		match _section:
			"cities": _build_cities()
			"logistics": _build_logistics()
			"plots": _build_plots()
			"holdings": _build_holdings()
			"automation": _build_automation()
	call_deferred("_restore_scroll")
	_refresh_actions()

func _restore_scroll() -> void:
	_scroll.scroll_vertical = int(_scrolls.get(_section, 0))

func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _live_label(reader: Callable) -> Label:
	var label: Label = _label(str(reader.call()))
	_content.add_child(label)
	_live.append(func() -> void: label.text = str(reader.call()))
	return label

func _heading(text: String) -> void:
	_content.add_child(HSeparator.new())
	var label: Label = _label(text)
	label.add_theme_font_size_override("font_size", 20)
	_content.add_child(label)

func _action(text: String, callback: Callable, reason: Callable = Callable()) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		if button.disabled or _pending or not _connected:
			return
		callback.call())
	_content.add_child(button)
	_actions.append({"button": button, "reason": reason})
	return button

func _refresh_actions() -> void:
	for entry: Dictionary in _actions:
		var reason: String = str(entry.reason.call()) if entry.reason.is_valid() else ""
		(entry.button as Button).disabled = _pending or not _connected or not reason.is_empty()
		(entry.button as Button).tooltip_text = reason

func _send(type: String, args: Array) -> void:
	if _pending or not _connected:
		return
	_pending = true
	_error = ""
	_refresh_actions()
	_status.text = "操作正在确认…"
	command_requested.emit(type, args)

func _cost(values: Dictionary) -> String:
	var pieces: PackedStringArray = []
	for id: String in values:
		if float(values[id]) > 0:
			pieces.append(str(RES_NAMES.get(id, FIELD_NAMES.get(id, id))) + " " + str(int(values[id])))
	return " · ".join(pieces) if not pieces.is_empty() else "无"

func _duration(seconds: float) -> String:
	var total: int = maxi(0, int(ceil(seconds)))
	return "%d时%02d分" % [total / 3600, (total % 3600) / 60] if total >= 3600 else "%d分%02d秒" % [total / 60, total % 60]

func _spin(id: String, label: String, maximum: float, initial: float = 0) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	_content.add_child(row)
	var title_label: Label = _label(label)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var spin: SpinBox = SpinBox.new()
	spin.max_value = maxf(0, maximum)
	spin.value = float(_drafts.get(id, initial))
	spin.custom_minimum_size.x = 100
	row.add_child(spin)
	spin.value_changed.connect(func(value: float) -> void: _drafts[id] = int(value); _invalidate_quote())
	spin.set_meta("draft_id", id)
	spin.get_line_edit().text_changed.connect(func(text: String) -> void:
		_drafts[id + "_text"] = text
		_invalidate_quote())
	if _drafts.has(id + "_text"):
		spin.get_line_edit().text = str(_drafts[id + "_text"])
	return spin

func _picker(id: String, entries: Array, placeholder: String = "") -> OptionButton:
	var picker: OptionButton = OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not placeholder.is_empty():
		picker.add_item(placeholder)
		picker.set_item_metadata(0, "")
	for entry: Dictionary in entries:
		picker.add_item(str(entry.get("name", entry.id)))
		picker.set_item_metadata(picker.item_count - 1, str(entry.id))
	var selected: String = str(_drafts.get(id, ""))
	for index: int in picker.item_count:
		if str(picker.get_item_metadata(index)) == selected:
			picker.select(index)
	picker.item_selected.connect(func(index: int) -> void: _drafts[id] = str(picker.get_item_metadata(index)); _invalidate_quote())
	_content.add_child(picker)
	return picker

func _choice(picker: OptionButton) -> String:
	return str(picker.get_item_metadata(picker.selected)) if picker.item_count > 0 and picker.selected >= 0 else ""

func _find(collection: String, id: String) -> Dictionary:
	for row: Dictionary in _realm().get(collection, []):
		if str(row.id) == id:
			return row
	return {}

func _build_cities() -> void:
	_live_label(func() -> String: return "城池 %d / %d · 提升爵位可增加城池数量" % [_realm().get("cities", []).size(), int(_realm().get("cityLimit", 1))])
	for city: Dictionary in _realm().get("cities", []):
		var id: String = str(city.id)
		_heading(str(city.name))
		_live_label(func() -> String:
			var row: Dictionary = _find("cities", id)
			return "坐标 %d,%d · 人口 %d · 驻军 %d\n%s" % [int(row.get("x", 0)), int(row.get("y", 0)), int(row.get("population", 0)), _army_total(row.get("army", {})), _cost(row.get("res", {}))])
		_action("切换到此城", func() -> void: _send("switchCity", [id]), func() -> String: return "已在此城" if id == _source else "")
	_heading("城池任职")
	_content.add_child(_label("城守管理建设和生产，主将影响训练，军师参与研究。一人只能担任一个职位；任职将领留守城内。"))
	var candidates: Array = _realm().get("generals", []).filter(func(g: Dictionary) -> bool: return not g.get("busy", false))
	var choices: Dictionary = {}
	for role: String in ["governor", "commander", "counsellor"]:
		var row: Dictionary = _realm().get("roles", {}).get(role, {})
		_content.add_child(_label(str(row.get("name", role))))
		var key: String = "role_" + role
		if not _drafts.has(key):
			_drafts[key] = row.get("hero", "")
		choices[role] = _picker(key, candidates, "选择将领" if role == "governor" else "暂不任命")
	_action("保存任职", func() -> void: _send("heritage.assign", [_choice(choices.governor), _choice(choices.commander), _choice(choices.counsellor)]))

func _army_total(army: Dictionary) -> int:
	var total: int = 0
	for value: Variant in army.values():
		total += int(value)
	return total

func _build_logistics() -> void:
	_content.add_child(_label("运输将物资送入另一座己方城池，护送部队随后返回；调遣将兵力和带队将领驻入目标城。"))
	var destinations: Array = _realm().get("cities", []).filter(func(city: Dictionary) -> bool: return str(city.id) != _source)
	if destinations.is_empty():
		_content.add_child(_label("拥有第二座城池后可运输和调遣。先在官爵中提升爵位，再占领县城或占领平地建城。"))
	else:
		var destination: OptionButton = _picker("destination", destinations)
		var kind: OptionButton = _picker("logistics_kind", [{"id": "transport", "name": "运输物资（护送部队返城）"}, {"id": "redeploy", "name": "调遣驻军（留在目标城）"}])
		var available: Array = _realm().get("generals", []).filter(func(g: Dictionary) -> bool: return not g.get("busy", false) and not _assigned(str(g.id)))
		var general: OptionButton = _picker("logistics_general", available, "不指定将领")
		var soldiers: Dictionary = {}
		_heading("派遣兵力")
		for unit: Dictionary in _view.get("units", []):
			soldiers[str(unit.id)] = _spin("army_" + str(unit.id), str(unit.name) + " · 可用 " + str(int(unit.available)), float(unit.available))
			var unit_id: String = str(unit.id)
			var spin: SpinBox = soldiers[unit_id]
			_live.append(func() -> void:
				for current: Dictionary in _view.get("units", []):
					if str(current.id) == unit_id:
						_set_live_max(spin, float(current.available)))
		_heading("携带物资（调遣时忽略此项）")
		var cargo: Dictionary = {}
		for resource: String in RES_NAMES:
			cargo[resource] = _spin("cargo_" + resource, str(RES_NAMES[resource]), float(_view.get("res", {}).get(resource, 0)))
			var spin: SpinBox = cargo[resource]
			_live.append(func() -> void: _set_live_max(spin, float(_view.get("res", {}).get(resource, 0))))
		_quote_args = func() -> Array:
			var army: Dictionary = _counts(soldiers)
			return [_choice(destination), army, _counts(cargo), _choice(general)] if _choice(kind) == "transport" else [_choice(destination), army, _choice(general)]
		_quote_kind = _choice(kind)
		kind.item_selected.connect(func(_index: int) -> void: _quote_kind = _choice(kind))
		_build_quote_controls("确认派遣")
	_heading("运输与调遣队列")
	for job: Dictionary in _realm().get("logistics", []):
		var id: String = str(job.id)
		_live_label(func() -> String:
			var row: Dictionary = _find("logistics", id)
			return "%s → %s · %s · %s" % [_city_name(str(row.get("sourceCity", ""))), _city_name(str(row.get("destinationCity", ""))), "运输" if row.get("kind") == "transport" else "调遣", _duration((float(row.get("end", 0)) - float(_realm().get("serverTime", 0))) / 1000)])
		_action("召回途中部队", func() -> void: _send("recallLogistics", [id]), func() -> String: return "已在返程" if _find("logistics", id).get("phase", "") != "outbound" else "")

func _assigned(hero_id: String) -> bool:
	for role: Dictionary in _realm().get("roles", {}).values():
		if str(role.get("hero", "")) == hero_id:
			return true
	return false

func _city_name(id: String) -> String:
	return str(_find("cities", id).get("name", id))

func _counts(controls: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for id: String in controls:
		var spin: SpinBox = controls[id]
		var draft_id: String = str(spin.get_meta("draft_id", ""))
		var raw: String = str(_drafts.get(draft_id + "_text", spin.get_line_edit().text)).strip_edges()
		counts[id] = clampi(int(raw), int(spin.min_value), int(spin.max_value)) if raw.is_valid_int() else -1
	return counts

func _set_live_max(spin: SpinBox, maximum: float) -> void:
	var draft_id: String = str(spin.get_meta("draft_id", ""))
	var raw: String = str(_drafts.get(draft_id + "_text", ""))
	spin.max_value = maxf(0, maximum)
	if _drafts.has(draft_id + "_text"):
		spin.get_line_edit().text = raw

func _invalidate_quote() -> void:
	_quote_id = ""
	_quote_command.clear()
	_quote_busy = false
	if is_instance_valid(_quote_label):
		_quote_label.text = "调整选项后，先预览费用和耗时"
	_refresh_actions()

func _build_quote_controls(confirm_text: String) -> void:
	_quote_label = _label("调整选项后，先预览费用和耗时")
	_content.add_child(_quote_label)
	_action("预览费用与时间", func() -> void:
		_quote_id = "quote_" + Crypto.new().generate_random_bytes(8).hex_encode()
		_quote_fingerprint = JSON.stringify([_source, _quote_args.call()])
		_quote_busy = true
		_quote_label.text = "正在预览…"
		_refresh_actions()
		quote_requested.emit(_quote_kind, _quote_args.call(), _quote_id), func() -> String: return "正在预览" if _quote_busy else "")
	_action(confirm_text, func() -> void:
		if not _quote_command.is_empty() and _quote_fingerprint == JSON.stringify([_source, _quote_args.call()]):
			_send(str(_quote_command.type), _quote_command.get("args", [])), func() -> String: return "请先预览并满足条件" if _quote_command.is_empty() or _quote_fingerprint != JSON.stringify([_source, _quote_args.call()]) else "")

func _plot(index: int) -> Dictionary:
	for row: Dictionary in _view.get("plots", []):
		if int(row.get("index", -1)) == index:
			return row
	return {}

func select_plot(index: int) -> void:
	if not bool(_plot(index).get("unlocked", false)):
		return
	_selected_plot = index
	if _section == "plots":
		_scrolls[_section] = _scroll.scroll_vertical
		_build()

func _plot_reason(index: int, expected_id: Variant) -> String:
	var current: Dictionary = _plot(index)
	if not bool(current.get("unlocked", false)):
		return "这处地块尚未开放"
	if current.get("id") != expected_id:
		return "地块已变化，请重新选择"
	if current.get("queue") != null:
		return "施工中"
	var limit: int = int(_view.get("queueLimits", {}).get("build", 0))
	if limit > 0:
		var queues: Variant = _view.get("queues", {})
		var build_jobs: Array = queues.get("build", []) if queues is Dictionary else []
		if build_jobs.size() >= limit:
			return "建造队正在忙碌"
	return str(current.get("requirement", "")) if current.get("requirement") != null and expected_id != null else ""

func _plot_option(id: String) -> Dictionary:
	for option: Dictionary in _view.get("plotOptions", []):
		if str(option.get("id", "")) == id:
			return option
	return {}

func _plot_option_reason(index: int, id: String) -> String:
	var parcel_reason: String = _plot_reason(index, null)
	if not parcel_reason.is_empty():
		return parcel_reason
	var option: Dictionary = _plot_option(id)
	if not option.has("cost") or not option.has("seconds") or not option.has("requirement") or not option.has("affordable"):
		return "首级建设报价尚未同步"
	if option.get("requirement") != null and not str(option.requirement).is_empty():
		return str(option.requirement)
	if not bool(option.affordable):
		return "资源不足，等待物资积累"
	return ""

func _plot_option_text(index: int, id: String) -> String:
	var option: Dictionary = _plot_option(id)
	if not option.has("cost") or not option.has("seconds"):
		return str(option.get("name", id)) + " · 正在读取首级建设报价"
	var reason: String = _plot_option_reason(index, id)
	return "%s · 1级 · 工期 %s\n费用 %s · %s" % [str(option.get("name", id)), _duration(float(option.seconds)), _cost(option.get("cost", {})), reason if not reason.is_empty() else "条件满足"]

func _develop_selected_plot(index: int, id: String, expected_id: Variant, source: String) -> void:
	if source != _source:
		show_error("城池或地块已变化，请重新选择")
		return
	var reason: String = _plot_option_reason(index, id) if expected_id == null else _plot_reason(index, expected_id)
	if not reason.is_empty():
		show_error(reason)
		return
	_send("developPlot", [index, id])

func _toggle_plot_templates() -> void:
	_templates_open = not _templates_open
	_scrolls[_section] = _scroll.scroll_vertical
	_build()

func _toggle_plot_map() -> void:
	_plot_map_open = not _plot_map_open
	_scrolls[_section] = _scroll.scroll_vertical
	_build()

func _build_plots() -> void:
	if not bool(_plot(_selected_plot).get("unlocked", false)):
		_selected_plot = -1
		for row: Dictionary in _view.get("plots", []):
			if bool(row.get("unlocked", false)):
				_selected_plot = int(row.index)
				break
	var selector: OptionButton = OptionButton.new()
	for row: Dictionary in _view.get("plots", []):
		if not bool(row.get("unlocked", false)):
			continue
		selector.add_item("%d号 %s%s" % [int(row.index) + 1, str(row.get("name", "空地")), " · %d级" % int(row.get("level", 0)) if row.get("id") != null else ""], int(row.index))
		if int(row.index) == _selected_plot:
			selector.select(selector.item_count - 1)
	selector.item_selected.connect(func(position: int) -> void: select_plot(selector.get_item_id(position)))
	_content.add_child(selector)
	var plot: Dictionary = _plot(_selected_plot)
	if not plot.is_empty():
		var index: int = _selected_plot
		var expected_id: Variant = plot.get("id")
		var source: String = _source
		_heading("%d号 %s%s" % [index + 1, str(plot.get("name", "空地")), " · %d级" % int(plot.get("level", 0)) if expected_id != null else ""])
		if expected_id != null:
			_live_label(func() -> String:
				var current: Dictionary = _plot(index)
				return "升级费用 " + _cost(current.get("cost", {})) + " · 工期 " + _duration(float(current.get("seconds", 0))) + ("\n施工中" if current.get("queue") != null else ""))
			_action("升级当前地块", _develop_selected_plot.bind(index, str(expected_id), expected_id, source), _plot_reason.bind(index, expected_id))
		else:
			_content.add_child(_label("选择这处空地的用途。农田供给军粮，木场、石场与铁矿供给建设和造兵。"))
			for option: Dictionary in _view.get("plotOptions", []):
				var id: String = str(option.id)
				var quote_label: Label = _live_label(_plot_option_text.bind(index, id))
				quote_label.set_meta("plot_quote_id", id)
				_action("建设" + str(option.name), _develop_selected_plot.bind(index, id, null, source), _plot_option_reason.bind(index, id))
	else:
		_content.add_child(_label("提升官府等级后开放更多城外地块。"))
	var map_toggle: Button = Button.new()
	map_toggle.text = "收起地块图" if _plot_map_open else "展开地块图"
	map_toggle.pressed.connect(_toggle_plot_map)
	_content.add_child(map_toggle)
	if _plot_map_open:
		var scene: KingdomSuburbView = SuburbScript.new() as KingdomSuburbView
		_content.add_child(scene)
		scene.custom_minimum_size.x = 240.0
		scene.set_view(_view)
		scene.select_plot(_selected_plot)
		scene.plot_selected.connect(select_plot)
		_live.append(func() -> void: scene.set_view(_view))
	var toggle: Button = Button.new()
	toggle.text = "收起城外样板" if _templates_open else "展开城外样板"
	toggle.pressed.connect(_toggle_plot_templates)
	_content.add_child(toggle)
	if not _templates_open:
		return
	_live_label(func() -> String: return str(_realm().get("plotStatus", "")))
	_content.add_child(_label("补齐空地保留已有建筑。替换布局会将改建的田地重建为 1 级；匹配样板的高等级田地保留。资源不足时等待积累。"))
	for template: Dictionary in _realm().get("templates", []):
		var id: String = str(template.id)
		_heading(str(template.name))
		_content.add_child(_label(str(template.get("desc", ""))))
		for mode: String in ["fill", "replace"]:
			var confirmed: CheckBox = null
			if mode == "replace":
				confirmed = CheckBox.new()
				confirmed.text = "同意将改建地块重置为 1 级"
				_content.add_child(confirmed)
				confirmed.toggled.connect(func(_on: bool) -> void: _refresh_actions())
			_live_label(func() -> String:
				var q: Dictionary = _template_quote(id, mode)
				return ("补齐空地" if mode == "fill" else "替换布局") + " · " + _cost(q.get("projectedCounts", q.get("counts", {}))) + "\n待安排 %s 块 · 总费用 %s\n%s" % [str(q.get("tasks", []).size()), _cost(q.get("cost", {})), str(q.get("reason", ""))])
			_action("按样板补齐空地" if mode == "fill" else "确认替换布局", func() -> void: _send("applyPlotTemplate", [id, mode]), func() -> String: return "请先确认等级重置" if mode == "replace" and not confirmed.button_pressed else str(_template_quote(id, mode).get("error", "")))
	_action("暂停样板建设", func() -> void: _send("pausePlotTemplate", []))

func _template_quote(id: String, mode: String) -> Dictionary:
	for quote: Dictionary in _find("templates", id).get("quotes", []):
		if str(quote.get("mode", "")) == mode:
			return quote
	return {}

func _build_holdings() -> void:
	if bool(_realm().get("shared", false)):
		_content.add_child(_label(str(_realm().get("gatheringReason", ""))))
		return
	for holding: Dictionary in _realm().get("holdings", []):
		var id: String = str(holding.id)
		_heading(str(holding.name))
		_live_label(func() -> String:
			var row: Dictionary = _find("holdings", id)
			var q: Dictionary = row.get("gatherQuote", {}) if row.get("gatherQuote") != null else {}
			return "坐标 %d,%d · 驻军 %d\n%s" % [int(row.get("x", 0)), int(row.get("y", 0)), _army_total(row.get("garrison", {}).get("army", {}) if row.get("garrison") != null else {}), "已采集 %s · 可入库 %s · 超仓 %d" % [_duration(float(q.get("elapsed", 0)) / 1000), _cost({str(q.get("resource", "food")): q.get("received", 0)}), int(q.get("overCapacity", 0))] if not q.is_empty() else str(row.get("gatherReason", ""))])
		_action("定位领地", func() -> void: focus_requested.emit(int(holding.x), int(holding.y)))
		_action("开始采集", func() -> void: _send("heritage.startGather", [id]), func() -> String: return str(_find("holdings", id).get("gatherReason", "")))
		_action("收获资源和珍宝", func() -> void: _send("heritage.collectGather", [id]), func() -> String:
			var q: Variant = _find("holdings", id).get("gatherQuote")
			return "至少采集 1 小时才能收获" if not q is Dictionary or not q.get("ready", false) else "")
		_action("取消采集", func() -> void: _send("heritage.cancelGather", [id]), func() -> String: return "尚未开始采集" if _find("holdings", id).get("gathering") == null else "")
		_action("召回驻军", func() -> void: _send("recallGarrison", [id]), func() -> String:
			var row: Dictionary = _find("holdings", id)
			return "先收获或取消采集" if row.get("gathering") != null else "没有驻守军队" if row.get("garrison") == null or row.garrison.get("phase") != "stationed" else "")
	if _realm().get("holdings", []).is_empty():
		_content.add_child(_label("占领野地并驻扎军队后，可在这里查看采集进度。平地可以建城；其他 1 级以上野地可以采集。"))
	var plains: Array = _realm().get("holdings", []).filter(func(h: Dictionary) -> bool: return h.get("type") == "plain")
	if not plains.is_empty():
		_heading("占领平地建城")
		var land: OptionButton = _picker("found_land", plains)
		var name_input: LineEdit = LineEdit.new()
		name_input.max_length = 12
		name_input.text = str(_drafts.get("found_name", "新城"))
		name_input.placeholder_text = "城池名称（最多 12 字）"
		_content.add_child(name_input)
		name_input.text_changed.connect(func(value: String) -> void: _drafts.found_name = value; _invalidate_quote())
		_quote_kind = "foundCity"
		_quote_args = func() -> Array: return [_choice(land), name_input.text]
		_build_quote_controls("确认建城")

func _build_automation() -> void:
	_live_label(func() -> String: return "自动建设：" + str(_realm().get("autoUpgradeStatus", "")) + "\n自动研究：" + str(_realm().get("autoResearchStatus", "")))
	_action("开启自动升级", func() -> void: _send("setAutoUpgrade", [true]))
	_action("暂停自动升级", func() -> void: _send("setAutoUpgrade", [false]))
	_action("开启自动研究", func() -> void: _send("setAutoResearch", [true]))
	_action("暂停自动研究", func() -> void: _send("setAutoResearch", [false]))
	_heading("资源保留与研究方向")
	_content.add_child(_label("自动建设和研究只能使用保留额度以外的资源。已开始的工程仍会完成。"))
	var settings: Dictionary = _realm().get("automation", {})
	if not _drafts.has("focus"):
		_drafts.focus = settings.get("researchFocus", "balanced")
	var focus: OptionButton = _picker("focus", [{"id": "balanced", "name": "均衡研究"}, {"id": "economy", "name": "经济优先"}, {"id": "military", "name": "军事优先"}])
	if not _drafts.has("priority"):
		_drafts.priority = settings.get("researchPriority", "")
	var priority: OptionButton = _picker("priority", _view.get("techs", []), "不指定优先科技")
	var reserve: Dictionary = {}
	for resource: String in RES_NAMES:
		reserve[resource] = _spin("reserve_" + resource, str(RES_NAMES[resource]) + "保留", 1000000000, float(settings.get("reserve", {}).get(resource, 0)))
	var notify: CheckBox = CheckBox.new()
	notify.text = "记录完成提醒"
	notify.button_pressed = bool(_drafts.get("notify", settings.get("notify", true)))
	_content.add_child(notify)
	notify.toggled.connect(func(on: bool) -> void: _drafts.notify = on)
	_action("保存挂机设置", func() -> void: _send("setAutomationSettings", [{"researchFocus": _choice(focus), "researchPriority": _choice(priority), "reserve": _counts(reserve), "notify": notify.button_pressed}]))
	_heading("近期完成")
	_live_label(func() -> String:
		var notices: PackedStringArray = []
		for notice: Dictionary in _realm().get("automation", {}).get("notices", []):
			notices.append(("● " if not notice.get("read", false) else "✓ ") + str(notice.get("text", "")))
		return "\n".join(notices) if not notices.is_empty() else "暂无完成提醒")
	_action("标记已读", func() -> void: _send("readAutomationNotices", []))
