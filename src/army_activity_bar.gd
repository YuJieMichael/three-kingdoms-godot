class_name KingdomArmyActivityBar
extends PanelContainer

## Read-only activity HUD. The host supplies a normalized snapshot and the
## corrected server clock; this control only requests navigation.
signal route_requested(section: String)

const SECTIONS: Array[String] = ["training", "marches", "stationed", "reports"]
const CAPTIONS: Dictionary = {"training": "训练", "marches": "行军", "stationed": "驻扎", "reports": "战报"}

var _view: Dictionary = {}
var _connected: bool = true
var _has_context: bool = false
var _compact: bool = false
var _now_ms: float = 0.0
var _buttons: Dictionary = {}
var _row: GridContainer
var _summary: Label
var _training: Array[Dictionary] = []
var _marches: Array[Dictionary] = []
var _stationed: Array[Dictionary] = []
var _reports: Array[Dictionary] = []
var _timed_items: Array[Dictionary] = []
var _outbound_count: int = 0
var _return_count: int = 0
var _battle_count: int = 0


func _ready() -> void:
	theme_type_variation = "InsetPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Keep the HUD shallow enough to leave the map visible on a phone.
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color("1e201e")
	panel_style.border_color = Color("70634e")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(3)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 5
	panel_style.content_margin_bottom = 5
	add_theme_stylebox_override("panel", panel_style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(column)
	_row = GridContainer.new()
	_row.columns = 4
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_theme_constant_override("h_separation", 4)
	column.add_child(_row)
	for section: String in SECTIONS:
		var button: Button = Button.new()
		button.name = section.capitalize() + "Activity"
		button.theme_type_variation = "UtilityButton"
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_navigate.bind(section))
		_row.add_child(button)
		_buttons[section] = button
	_summary = Label.new()
	_summary.theme_type_variation = "MutedLabel"
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_summary.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_summary)
	_wire_focus()
	_render_snapshot()


func update_view(view: Dictionary, now_ms: float) -> void:
	_view = view.duplicate(true)
	_has_context = not _view.is_empty()
	_now_ms = now_ms
	_project_snapshot()
	if is_instance_valid(_summary):
		_render_snapshot()


func refresh_clock(now_ms: float) -> void:
	_now_ms = now_ms
	if is_instance_valid(_summary):
		_render_clock()


func set_connected(connected: bool) -> void:
	_connected = connected
	if is_instance_valid(_summary):
		_render_snapshot()


func set_compact(compact: bool) -> void:
	_compact = compact
	if is_instance_valid(_summary):
		_render_snapshot()


func clear_context() -> void:
	_view.clear()
	_has_context = false
	_now_ms = 0.0
	_project_snapshot()
	if is_instance_valid(_summary):
		_render_snapshot()


func _project_snapshot() -> void:
	_training = _rows(_dictionary(_view.get("queues")).get("train"))
	_marches.clear()
	_stationed.clear()
	_reports = _rows(_view.get("reports"))
	_timed_items.clear()
	_outbound_count = 0
	_return_count = 0
	_battle_count = 0
	for job: Dictionary in _training:
		_timed_items.append({"label": "%s训练 · %s" % [_current_city_name(), _training_name(job)], "deadline": _number(job.get("end"))})
	# view.marches is already flattened across cities and shared/local sources.
	# Do not add realm logistics, shared marches, or city scout queues a second time.
	var seen: Dictionary = {}
	for march: Dictionary in _rows(_view.get("marches")):
		if march.has("id"):
			var identity: String = JSON.stringify([march.get("shared", false), march.id])
			if seen.has(identity):
				continue
			seen[identity] = true
		var status: String = str(march.get("status", ""))
		if status == "stationed":
			_stationed.append(march)
		elif status in ["march", "outbound", "return", "battle"]:
			_marches.append(march)
			if status == "return":
				_return_count += 1
			elif status == "battle":
				_battle_count += 1
			else:
				_outbound_count += 1
			if status != "battle":
				_timed_items.append({"label": _march_name(march) + " · " + _phase_text(status), "deadline": _march_deadline(march)})
	_timed_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.deadline == null:
			return false
		if b.deadline == null:
			return true
		return float(a.deadline) < float(b.deadline))


func _render_snapshot() -> void:
	var counts: Dictionary = {"training": _training.size(), "marches": _marches.size(), "stationed": _stationed.size(), "reports": _reports.size()}
	for section: String in SECTIONS:
		var button: Button = _buttons[section]
		button.disabled = not _connected or not _has_context
		button.add_theme_font_size_override("font_size", 14 if _compact else 15)
		button.text = str(CAPTIONS[section]) + (str(counts[section]) if _has_context else "—")
		if not _compact and _has_context:
			match section:
				"training": button.text = "本城训练 %d" % _training.size()
				"marches": button.text = "全域行军 %d · 出%d返%d" % [_marches.size(), _outbound_count, _return_count]
				"stationed": button.text = "全域驻扎 %d组" % _stationed.size()
				"reports": button.text = "战报 %d" % _reports.size()
	_render_clock()


func _render_clock() -> void:
	if not _has_context:
		_summary.text = "连接后显示军队动态"
		_summary.tooltip_text = _summary.text
		for section: String in SECTIONS:
			(_buttons[section] as Button).tooltip_text = "连接后查看" + str(CAPTIONS[section])
		return
	var prefix: String = "离线 · " if not _connected else ""
	if not _timed_items.is_empty():
		var next: Dictionary = _timed_items[0]
		_summary.text = prefix + str(next.label) + " · " + _remaining(next.deadline)
	elif _battle_count > 0:
		_summary.text = prefix + "全域 %d组交战中 · 查看行军" % _battle_count
	elif not _reports.is_empty():
		_summary.text = prefix + "最新战报 · " + _latest_report_text()
	else:
		_summary.text = prefix + _current_city_name() + "无训练队列 · 全域驻扎 %d组" % _stationed.size()
	_summary.tooltip_text = _summary.text + "\n" + _training_tooltip() + "\n" + _marches_tooltip()
	if not _reports.is_empty():
		_summary.tooltip_text += "\n最新战报 · " + _latest_report_text()
	(_buttons.training as Button).tooltip_text = _training_tooltip()
	(_buttons.marches as Button).tooltip_text = _marches_tooltip()
	var stationed_text: String = "全域驻扎 %d组（只计已驻扎，返程列入行军）" % _stationed.size()
	for march: Dictionary in _stationed:
		stationed_text += "\n" + _march_name(march) + " · " + _owned_count_text(march)
	(_buttons.stationed as Button).tooltip_text = stationed_text
	(_buttons.reports as Button).tooltip_text = "当前战报 %d份" % _reports.size() + ("\n最新 · " + _latest_report_text() if not _reports.is_empty() else "\n暂无战报")


func _training_tooltip() -> String:
	var result: String = "本城训练 · %s · %d项（其他城池训练不在本表）" % [_current_city_name(), _training.size()]
	for job: Dictionary in _training:
		result += "\n" + _training_name(job) + " · " + _remaining(_number(job.get("end")))
	return result


func _marches_tooltip() -> String:
	var result: String = "全域行军 %d组 · 出发%d · 返程%d · 交战%d（含可见来军）" % [_marches.size(), _outbound_count, _return_count, _battle_count]
	for march: Dictionary in _marches:
		var status: String = str(march.get("status", ""))
		result += "\n%s · %s · %s" % [_march_name(march), _phase_text(status), _owned_count_text(march)]
		if status != "battle":
			result += " · " + _remaining(_march_deadline(march))
	return result


func _training_name(job: Dictionary) -> String:
	var id: String = str(job.get("id", "兵种"))
	var unit_name: String = id
	for unit: Dictionary in _rows(_view.get("units")):
		if str(unit.get("id", "")) == id:
			unit_name = str(unit.get("name", id))
			break
	var count: Variant = _number(job.get("count"))
	return unit_name + (" ×%d" % int(count) if count != null else " · 数量待同步")


func _march_name(march: Dictionary) -> String:
	var label: String = str(march.get("label", "部队"))
	if str(march.get("type", "")) == "scout" and not label.contains("斥候"):
		label = "斥候 · " + label
	if bool(march.get("incoming", false)) and not label.contains("来军"):
		label = "来军 · " + label
	return label + " · " + _city_name(str(march.get("sourceCity", "")))


func _march_deadline(march: Dictionary) -> Variant:
	var next: Variant = _number(march.get("nextArrival"))
	if next != null:
		return next
	if str(march.get("status", "")) == "return":
		var returning: Variant = _number(march.get("returnAt"))
		if returning != null:
			return returning
	return _number(march.get("arrive"))


func _owned_count_text(march: Dictionary) -> String:
	var count: Variant = _number(march.get("count"))
	return "%d人" % int(count) if count != null else "兵力未公开"


func _phase_text(status: String) -> String:
	return "返程" if status == "return" else "交战中" if status == "battle" else "出发"


func _latest_report_text() -> String:
	# Both local and shared projections expose newest reports first. Do not
	# interpret numeric/string IDs as timestamps or invent an unread counter.
	var latest: Dictionary = _reports[0]
	for report: Dictionary in _reports:
		var at: Variant = _number(report.get("at"))
		var latest_at: Variant = _number(latest.get("at"))
		if at != null and latest_at != null and float(at) > float(latest_at):
			latest = report
	var title: String = str(latest.get("title", latest.get("label", latest.get("nodeName", ""))))
	if title.is_empty():
		var node_id: String = str(latest.get("node", ""))
		for node: Dictionary in _rows(_view.get("nodes")):
			if str(node.get("id", "")) == node_id:
				title = str(node.get("name", node_id))
				break
		if title.is_empty():
			title = node_id if not node_id.is_empty() else "战斗结果"
	if latest.get("won") is bool:
		title += " · " + ("胜利" if bool(latest.won) else "失利")
	return title


func _remaining(deadline: Variant) -> String:
	if deadline == null:
		return "时间待同步"
	var seconds: int = maxi(0, int(ceil((float(deadline) - _now_ms) / 1000.0)))
	if seconds == 0:
		return "待结算"
	if seconds >= 3600:
		return "%d时%02d分" % [seconds / 3600, (seconds % 3600) / 60]
	return "%d分%02d秒" % [seconds / 60, seconds % 60]


func _current_city_name() -> String:
	return str(_dictionary(_view.get("city")).get("name", "当前城池"))


func _city_name(id: String) -> String:
	if id.is_empty():
		return "出发城待同步"
	if str(_dictionary(_view.get("city")).get("id", "")) == id:
		return _current_city_name()
	for city: Dictionary in _rows(_view.get("cityList")):
		if str(city.get("id", "")) == id:
			return str(city.get("name", id))
	return id


func _navigate(section: String) -> void:
	if _connected and _has_context and SECTIONS.has(section):
		route_requested.emit(section)


func _wire_focus() -> void:
	for index: int in range(SECTIONS.size()):
		var button: Button = _buttons[SECTIONS[index]]
		var previous: Button = _buttons[SECTIONS[(index + SECTIONS.size() - 1) % SECTIONS.size()]]
		var next: Button = _buttons[SECTIONS[(index + 1) % SECTIONS.size()]]
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(next)
		button.focus_neighbor_left = button.focus_previous
		button.focus_neighbor_right = button.focus_next


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _rows(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for row: Variant in value:
			if row is Dictionary:
				result.append(row)
	return result


func _number(value: Variant) -> Variant:
	return float(value) if (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 else null
