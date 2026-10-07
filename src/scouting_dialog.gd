class_name KingdomScoutingDialog
extends AcceptDialog

## The host supplies safe DTOs and executes the exact quoted command.
signal quote_requested(kind: String, args: Array, request_id: String)
signal command_requested(type: String, args: Array, source_city: String)

const IntelScript: Script = preload("res://src/intel_panel.gd")
var _view: Dictionary = {}
var _target: Dictionary = {}
var _source: String = ""
var _connected: bool = false
var _pending: bool = false
var _supported: bool = false
var _available: int = 0
var _queue_used: int = 0
var _queue_limit: int = 0
var _now_ms: float = 0.0
var _context_signature: String = ""
var _quote_id: String = ""
var _quote_fingerprint: String = ""
var _quote_command: Dictionary = {}
var _quote: Dictionary = {}
var _quote_busy: bool = false
var _setting_count: bool = false
var _count_initialized: bool = false
var _error: String = ""
var _scroll: ScrollContainer
var _content: VBoxContainer
var _intro: Label
var _availability: Label
var _status: Label
var _count: SpinBox
var _preview: Button
var _confirm: Button
var _quote_label: Label
var _intel: PanelContainer


func _ready() -> void:
	title = "战前侦察"
	get_ok_button().text = "关闭"
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	_scroll.add_child(_content)
	_intro = _label("", "SectionLabel")
	_intel = IntelScript.new()
	_content.add_child(_intel)
	_availability = _label("")
	_label("派遣斥候数量", "SectionLabel")
	_count = SpinBox.new()
	_count.min_value = 0.0
	_count.max_value = 0.0
	_count.step = 1.0
	_count.custom_minimum_size = Vector2(0, 44)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_count)
	_count.value_changed.connect(func(_value: float) -> void: _quantity_changed())
	_count.get_line_edit().text_changed.connect(func(_text: String) -> void: _quantity_changed())
	_preview = _button("预览侦察", false)
	_preview.pressed.connect(_request_quote)
	_quote_label = _label("先预览粮草、往返耗时与侦察精度。", "MutedLabel")
	_confirm = _button("确认派遣斥候", true)
	_confirm.pressed.connect(_submit)
	_status = _label("", "MutedLabel")
	_label("侦察无需将领。斥候出发后按实际行军返回；本轮没有取消或召回侦察的规则。", "MutedLabel")
	visibility_changed.connect(_visibility_changed)
	_render()
	_fit_window()


func configure_target(node: Dictionary) -> void:
	var changed: bool = str(_target.get("id", "")) != str(node.get("id", ""))
	_target = node.duplicate(true)
	if changed:
		_invalidate_quote("目标已变化，请重新预览。")
		_error = ""
	if is_instance_valid(_intro):
		_render()
		_fit_window()


func update_view(view: Dictionary) -> void:
	if view.is_empty():
		clear_context()
		return
	var scouting: Dictionary = _dictionary(view.get("scouting"))
	var previous_gate: String = _target_gate()
	var source: String = str(view.get("city", {}).get("id", ""))
	var supported: bool = bool(scouting.get("supported", false))
	var available: int = maxi(0, int(scouting.get("available", 0)))
	var signature: String = JSON.stringify([source, scouting.get("queueUsed", 0), scouting.get("queueLimit", 0), supported, _scouting_level(view)])
	if (not _source.is_empty() and source != _source) or not supported:
		_target.erase("intel")
		_target.erase("army")
		_invalidate_quote("已切换城池，请核对新城池的斥候和情报。" if supported else "当前模式不支持本机侦察。")
	elif (not _context_signature.is_empty() and signature != _context_signature) or available < _available:
		_invalidate_quote("斥候或派遣条件已变化，请重新预览。")
	_view = view.duplicate(true)
	_source = source
	_supported = supported
	_available = available
	_queue_used = maxi(0, int(scouting.get("queueUsed", 0)))
	_queue_limit = maxi(0, int(scouting.get("queueLimit", 0)))
	_context_signature = signature
	if previous_gate != _target_gate():
		_invalidate_quote("目标可用性或公开情报已变化，请重新预览。")
	_now_ms = float(view.get("serverTime", scouting.get("serverTime", Time.get_unix_time_from_system() * 1000.0)))
	if is_instance_valid(_count):
		_setting_count = true
		# Do not reassign unchanged Range values: preserve uncommitted raw input.
		if not is_equal_approx(_count.max_value, _quantity_limit()):
			_count.max_value = _quantity_limit()
			var raw: String = _count.get_line_edit().text.strip_edges()
			if raw.is_valid_int() and int(raw) > _quantity_limit():
				_count.value = _quantity_limit()
				_count.get_line_edit().text = str(_quantity_limit())
		if not _count_initialized and _available > 0:
			_count.value = 1.0
			# SpinBox refreshes its editor later; action gating needs the same
			# initial value immediately, without rebuilding controls on polling.
			_count.get_line_edit().text = "1"
			_count_initialized = true
		_setting_count = false
		if not _quote.is_empty() and float(_view.get("res", {}).get("food", 0)) < float(_quote.get("cost", {}).get("food", 0)):
			_invalidate_quote("粮草已不足，请重新预览。")
		_render()


func set_command_state(connected: bool, pending: bool) -> void:
	if not connected or pending:
		_invalidate_quote("操作正在确认，不能重复派遣。" if pending else "连接中断，请重连后重新预览。")
	_connected = connected
	_pending = pending
	if is_instance_valid(_status):
		_refresh_actions()


func receive_quote(payload: Dictionary) -> void:
	if _quote_id.is_empty() or str(payload.get("requestId", "")) != _quote_id or not visible or not _usable():
		return
	if _quote_fingerprint != _fingerprint():
		_invalidate_quote("数量或目标已变化，请重新预览。")
		_refresh_actions()
		return
	_quote_busy = false
	_quote = _dictionary(payload.get("quote")).duplicate(true)
	if payload.get("serverTime") is int or payload.get("serverTime") is float:
		_now_ms = float(payload.serverTime)
	var command: Dictionary = _dictionary(_quote.get("command"))
	_quote_command = command.duplicate(true) if str(_quote.get("reason", "")).is_empty() and _valid_command(command) else {}
	var lines: PackedStringArray = []
	lines.append("粮草费用 %s" % _amount(_dictionary(_quote.get("cost")).get("food")))
	lines.append("单程 %s · 返程 %s" % [_duration(_quote.get("seconds")), _duration(_quote.get("returnSeconds"))])
	lines.append("预期精度：" + _precision_text(str(_quote.get("precision", ""))))
	lines.append("预计斥候损失 %s 人" % _amount(_quote.get("expectedLost")))
	lines.append("情报有效期：%s（自抵达获得情报起）" % _duration(float(_quote.ttlMs) / 1000.0 if _number(_quote.get("ttlMs")) else null))
	var reason: String = str(_quote.get("reason", ""))
	lines.append(reason if not reason.is_empty() else "点击确认后才扣除斥候与粮草。" if not _quote_command.is_empty() else "报价缺少合法派遣命令，请重新预览。")
	_quote_label.text = "\n".join(lines)
	_error = ""
	_render_intel()
	_refresh_actions()


func show_error(message: String) -> void:
	_invalidate_quote(message)
	_error = message
	if is_instance_valid(_status):
		_refresh_actions()


func acknowledge_command(connected: bool, pending: bool) -> void:
	_error = ""
	_invalidate_quote()
	set_command_state(connected, pending)


func clear_context() -> void:
	_target.clear()
	_view.clear()
	_source = ""
	_connected = false
	_pending = false
	_supported = false
	_available = 0
	_queue_used = 0
	_queue_limit = 0
	_now_ms = 0.0
	_context_signature = ""
	_count_initialized = false
	_error = ""
	_invalidate_quote("请选择当前进度中已开放的目标。")
	if is_instance_valid(_count):
		_setting_count = true
		_count.value = 0.0
		_count.max_value = 0.0
		_count.get_line_edit().text = "0"
		_setting_count = false
		_render()


func _quantity_changed() -> void:
	if _setting_count:
		return
	_invalidate_quote("数量已变化，请重新预览。")
	_error = ""
	_refresh_actions()


func _quantity() -> int:
	var raw: String = _count.get_line_edit().text.strip_edges()
	return clampi(int(raw), 0, _quantity_limit()) if raw.is_valid_int() else -1


func _quantity_limit() -> int:
	return mini(_available, 1000)


func _normalize_quantity() -> int:
	var quantity: int = _quantity()
	if quantity < 0:
		show_error("请输入有效的整数斥候数量。")
		return -1
	_setting_count = true
	_count.value = quantity
	_count.get_line_edit().text = str(quantity)
	_setting_count = false
	return quantity


func _fingerprint() -> String:
	return JSON.stringify([_source, str(_target.get("id", "")), _quantity(), _context_signature])


func _usable() -> bool:
	var node: Dictionary = _current_node()
	return _connected and not _pending and _supported and not _source.is_empty() and not str(node.get("id", "")).is_empty() and not node.get("hidden", false) and node.get("selectable", true) and not node.get("shared", false) and not node.get("player", false) and not node.get("owned", false) and not _public_target()


func _public_target() -> bool:
	var intel: Dictionary = _dictionary(_current_node().get("intel"))
	return str(intel.get("precision", "")) != "expired" and (str(intel.get("precision", "")) == "public" or bool(intel.get("public", false)))


func _current_node() -> Dictionary:
	if not _supported or _target.is_empty():
		return {}
	var node: Dictionary = _target.duplicate(true)
	# configure_target may contain an earlier projected report. Every poll rebuilds
	# derived intel from the current safe DTO, including explicit map removal.
	node.erase("intel")
	node.erase("army")
	var found: bool = false
	for current: Dictionary in _view.get("nodes", []):
		if str(current.get("id", "")) == str(node.get("id", "")):
			node = current.duplicate(true)
			found = true
			break
	if not found:
		node["selectable"] = false
	var by_node: Dictionary = _dictionary(_dictionary(_view.get("scouting")).get("intelByNode"))
	if found and by_node.has(str(node.get("id", ""))):
		node["intel"] = _dictionary(by_node[str(node.id)]).duplicate(true)
	return node


func _target_gate() -> String:
	var node: Dictionary = _current_node()
	return JSON.stringify([node.get("id", ""), node.get("hidden", false), node.get("selectable", false), node.get("shared", false), node.get("player", false), node.get("owned", false), _public_target()])


func _request_quote() -> void:
	if not visible or not _usable() or _quote_busy:
		return
	var quantity: int = _normalize_quantity()
	if quantity < 1:
		if quantity == 0:
			show_error("请选择至少1名可用斥候。")
		return
	_invalidate_quote("正在预览侦察…")
	_error = ""
	_quote_busy = true
	_quote_id = "scout_" + Crypto.new().generate_random_bytes(8).hex_encode()
	_quote_fingerprint = _fingerprint()
	_refresh_actions()
	quote_requested.emit("scout", [str(_target.id), quantity], _quote_id)


func _valid_command(command: Dictionary) -> bool:
	var args: Variant = command.get("args")
	return str(command.get("type", "")) == "dispatchScout" and str(command.get("sourceCity", "")) == _source and args is Array and args.size() == 3 and str(args[0]) == str(_target.get("id", "")) and _number(args[1]) and float(args[1]) == float(int(args[1])) and int(args[1]) == _quantity() and str(args[2]) == str(_quote.get("key", "")) and not str(args[2]).is_empty()


func _submit() -> void:
	if not visible or not _usable() or _quote_busy or _quote_command.is_empty() or _quote_fingerprint != _fingerprint():
		return
	var command: Dictionary = _quote_command.duplicate(true)
	if _normalize_quantity() < 1 or not _valid_command(command):
		show_error("派遣条件已变化，请重新预览。")
		return
	_pending = true
	_invalidate_quote("派遣已提交，等待实际回执。")
	_error = ""
	_refresh_actions()
	command_requested.emit(str(command.type), command.args.duplicate(true), str(command.sourceCity))


func _invalidate_quote(message: String = "先预览粮草、往返耗时与侦察精度。") -> void:
	_quote_id = ""
	_quote_fingerprint = ""
	_quote_command.clear()
	_quote.clear()
	_quote_busy = false
	if is_instance_valid(_quote_label):
		_quote_label.text = message
	if is_instance_valid(_confirm):
		_confirm.disabled = true


func _render() -> void:
	_intro.text = str(_target.get("name", "请选择目标"))
	if _public_target():
		_intro.text += "\n此目标守军已公开，无需侦察。"
	_availability.text = "当前城池：%s · 可用斥候 %d 人\n侦察队列 %d / %d" % [str(_view.get("city", {}).get("name", "未连接")), _available, _queue_used, _queue_limit]
	if _available == 0 and _supported:
		_availability.text += "\n城内没有可用斥候；可在“军队→训练与驻军→斥候”训练，或等待外出斥候返回。"
	_render_intel()
	_refresh_actions()


func _render_intel() -> void:
	_intel.set_intel(_current_node(), _view.get("units", []), _now_ms)


func _refresh_actions() -> void:
	_count.editable = _usable() and _available > 0
	_preview.disabled = not _usable() or _quote_busy or _quantity() < 1
	_confirm.disabled = not _usable() or _quote_busy or _quote_command.is_empty() or _quote_fingerprint != _fingerprint()
	_status.text = _error if not _error.is_empty() else "正在确认派遣，不能重复消费。" if _pending else "连接后可预览侦察。" if not _connected else "共享或当前模式不支持本机侦察。" if not _supported else "此目标守军已公开，无需侦察。" if _public_target() else "正在读取原规则报价…" if _quote_busy else "预览不扣费；确认派遣以实际回执为准。"
	var editor: LineEdit = _count.get_line_edit()
	editor.focus_next = _preview.get_path()
	_preview.focus_previous = editor.get_path()
	_preview.focus_next = _confirm.get_path() if not _confirm.disabled else get_ok_button().get_path()
	_confirm.focus_previous = _preview.get_path()
	_confirm.focus_next = get_ok_button().get_path()


func _visibility_changed() -> void:
	if visible:
		_fit_window()
		call_deferred("_focus_close")
	else:
		_invalidate_quote()


func _focus_close() -> void:
	if is_inside_tree() and visible:
		get_ok_button().grab_focus()


func _fit_window() -> void:
	var available: Vector2 = (get_parent() as Control).size if get_parent() is Control else Vector2(get_tree().root.size)
	var target_size: Vector2i = Vector2i(mini(680, maxi(280, int(available.x) - 40)), mini(660, maxi(280, int(available.y) - 80)))
	min_size = target_size
	_scroll.custom_minimum_size = Vector2(target_size.x - 48, target_size.y - 90)
	size = target_size
	position = Vector2i((available - Vector2(size)) / 2.0)


func _scouting_level(view: Dictionary) -> Variant:
	for row: Dictionary in view.get("techs", []):
		if row.get("id", "") == "scouting":
			return row.get("level", 0)
	return null


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _amount(value: Variant) -> String:
	return str(int(value)) if _number(value) and float(value) >= 0 else "未提供"


func _duration(value: Variant) -> String:
	if not _number(value) or float(value) < 0:
		return "未提供"
	var seconds: int = ceili(float(value))
	return "%d时%02d分" % [seconds / 3600, (seconds % 3600) / 60] if seconds >= 3600 else "%d分%02d秒" % [seconds / 60, seconds % 60]


func _precision_text(precision: String) -> String:
	return str({"failed": "失败，无法获得有效情报", "types": "兵种，数量未知", "bands": "兵力区间", "exact": "精确兵力"}.get(precision, "未提供"))


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _label(text: String, variation: String = "") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(label)
	return label


func _button(text: String, primary: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.theme_type_variation = "PrimaryButton" if primary else "UtilityButton"
	button.custom_minimum_size.y = 44
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(button)
	return button
