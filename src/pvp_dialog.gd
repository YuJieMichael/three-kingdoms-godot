extends AcceptDialog
class_name KingdomPvpDialog

signal command_requested(type: String, args: Array)
signal focus_requested(x: int, y: int)
signal report_requested(report: Dictionary)

var _view: Dictionary = {}
var _shared: Dictionary = {}
var _actor: Dictionary = {}
var _allowed: bool = false
var _server_offset: float = 0.0
var _list: VBoxContainer
var _form: VBoxContainer
var _message: Label
var _signature: String = ""
var _target: Dictionary = {}
var _send: Button
var _eta_labels: Array[Label] = []
var _timer: Timer
var _command_buttons: Array[Button] = []
var _counts: Dictionary = {}
var _count_labels: Dictionary = {}
var _generals: OptionButton
var _form_error: Label
var _general_signature: String = ""
var _scroll: ScrollContainer

func _ready() -> void:
	title = "玩家战争 · 共享演练"
	get_ok_button().text = "关闭"
	var scroll: ScrollContainer = ScrollContainer.new()
	_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 14.0
	scroll.offset_right = -14.0
	scroll.offset_top = 12.0
	scroll.offset_bottom = -54.0
	add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	_message = _label("")
	content.add_child(_message)
	_form = VBoxContainer.new()
	content.add_child(_form)
	_list = VBoxContainer.new()
	content.add_child(_list)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_refresh_eta)
	add_child(_timer)
	_timer.start()
	visibility_changed.connect(func() -> void:
		if not visible:
			_target.clear()
			_clear_form())

func update_data(view: Dictionary, shared: Dictionary, actor: Dictionary, server_time: float, allowed: bool, room: Dictionary = {}) -> void:
	var changed_actor: bool = str(actor.get("id", "")) != str(_actor.get("id", ""))
	_view = view
	_shared = shared
	_actor = actor
	_allowed = allowed
	_server_offset = server_time - Time.get_unix_time_from_system() * 1000.0
	if room.is_empty():
		title = "玩家战争 · 共享演练"
		_message.text = "%s · 四账号独立进度\n演练预置兵力和战争状态。抵达后自动结算，返程后资源入库。" % str(actor.get("name", "共享世界"))
	else:
		title = "玩家战争 · " + str(room.get("name", "房间"))
		_message.text = "%s · %s · %d / %d 个城主\n房间演练预置兵力和战争状态。抵达后自动结算，返程后资源入库。" % [str(room.get("name", "房间")), str(actor.get("name", "城主")), room.get("members", []).size(), int(room.get("capacity", 1))]
	var signature: String = JSON.stringify([shared.get("players", []), shared.get("membership"), shared.get("marches", []), shared.get("reports", [])])
	if signature != _signature or changed_actor:
		_signature = signature
		_render_list()
	if changed_actor:
		_target.clear()
		_clear_form()
	for button: Button in _command_buttons:
		if is_instance_valid(button):
			button.disabled = not _allowed
	if is_instance_valid(_send):
		_send.disabled = not _allowed
	_refresh_form_availability()
	_refresh_eta()

func show_world() -> void:
	var viewport: Vector2i = Vector2i(get_tree().root.get_visible_rect().size)
	min_size = Vector2i(mini(760, maxi(300, viewport.x - 40)), mini(560, maxi(240, viewport.y - 60)))
	popup_centered(min_size)
	_render_list()

func show_dispatch(player: Dictionary) -> void:
	show_world()
	_dispatch(player)

func acknowledge_command_success(type: String) -> void:
	if type not in ["shared.attackPlayer", "shared.raid", "shared.aid"]:
		return
	_target.clear()
	_clear_form()
	_message.text = "派遣已确认。请在行军与驻扎中查看部队，抵达后由服务器自动结算。"

func show_request_error(message: String) -> void:
	if is_instance_valid(_form_error):
		_form_error.text = message
	if is_instance_valid(_send):
		# Allowed already reflects the canonical connection and pending receipt.
		# An uncertain transport failure keeps dispatch disabled until reconnect.
		_send.disabled = not _allowed

func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _clear_form() -> void:
	_clear(_form)
	_counts.clear()
	_count_labels.clear()
	_generals = null
	_form_error = null
	_send = null
	_general_signature = ""

func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.disabled = disabled
	button.custom_minimum_size.y = 38.0
	button.pressed.connect(callback)
	return button

func _ally(player: Dictionary) -> bool:
	var alliance: String = str(_shared.get("membership", {}).get("alliance", "")) if _shared.get("membership") is Dictionary else ""
	return not alliance.is_empty() and str(player.get("alliance", "")) == alliance

func _player_name(id: String) -> String:
	for player: Dictionary in _shared.get("players", []):
		if str(player.get("id", "")) == id:
			return str(player.get("name", "城主"))
	return "城主"

func _render_list() -> void:
	if not is_instance_valid(_list):
		return
	_clear(_list)
	_eta_labels.clear()
	_command_buttons.clear()
	_list.add_child(_label("共享城池"))
	for player: Dictionary in _shared.get("players", []):
		var own: bool = str(player.get("id", "")) == str(_actor.get("id", ""))
		var ally: bool = _ally(player)
		var home: Dictionary = player.get("home", {})
		_list.add_child(_label("%s · %s · (%d,%d)" % [str(player.get("name", "城主")), "自己" if own else "同盟" if ally else "敌方", int(home.get("x", 0)), int(home.get("y", 0))]))
		var actions: HBoxContainer = HBoxContainer.new()
		_list.add_child(actions)
		actions.add_child(_button("地图定位", func() -> void:
			focus_requested.emit(int(home.get("x", 0)), int(home.get("y", 0)))))
		if not own:
			var dispatch: Button = _button("派遣援军" if ally else "配兵掠夺", _dispatch.bind(player), not _allowed)
			actions.add_child(dispatch)
			_command_buttons.append(dispatch)
	_list.add_child(HSeparator.new())
	_list.add_child(_label("行军与驻扎"))
	for march: Dictionary in _shared.get("marches", []):
		var own: bool = str(march.get("source", "")) == str(_actor.get("id", ""))
		var title: String = ("援军" if march.get("kind") == "aid" else "讨伐") + " · " + _player_name(str(march.get("source", ""))) + " → " + _player_name(str(march.get("target", "")))
		var label: Label = _label(title)
		label.set_meta("march", march)
		label.set_meta("heading", title)
		_list.add_child(label)
		_eta_labels.append(label)
		if own and march.get("kind") == "aid" and march.get("status") == "stationed":
			var recall: Button = _button("召回驻扎援军", func() -> void:
				if _allowed:
					command_requested.emit("shared.recallAid", [{"id": march.id}]), not _allowed)
			_list.add_child(recall)
			_command_buttons.append(recall)
	if _shared.get("marches", []).is_empty():
		_list.add_child(_label("暂无共享行军。选择敌城掠夺，或向盟友派遣援军。"))
	_list.add_child(HSeparator.new())
	_list.add_child(_label("共享战报"))
	for report: Dictionary in _shared.get("reports", []):
		var text: String = _player_name(str(report.get("source", ""))) + " → " + _player_name(str(report.get("target", ""))) + " · " + ("攻方胜利" if report.get("won", false) else "守方守住")
		_list.add_child(_button(text, func() -> void:
			var copy: Dictionary = report.duplicate(true)
			copy["shared"] = true
			report_requested.emit(copy)))
	if _shared.get("reports", []).is_empty():
		_list.add_child(_label("交战后双方均可查看同一份自动战报。"))
	_refresh_eta()

func _dispatch(player: Dictionary) -> void:
	var known: bool = false
	for entry: Dictionary in _shared.get("players", []):
		if str(entry.get("id", "")) == str(player.get("id", "")):
			known = true
			break
	if not known or str(player.get("id", "")).is_empty() or str(player.get("id", "")) == str(_actor.get("id", "")):
		_message.text = "请选择其他玩家的城池。"
		return
	_target = player.duplicate(true)
	_clear_form()
	var ally: bool = _ally(player)
	_form.add_child(HSeparator.new())
	_form.add_child(_label(("援助 · " if ally else "掠夺 · ") + str(player.get("name", "城主"))))
	_form.add_child(_label("派遣时扣除兵力与粮草。援军抵达后驻扎；讨伐抵达后自动交战并返城。主城不可占领。"))
	var generals: OptionButton = OptionButton.new()
	_generals = generals
	for general: Dictionary in _view.get("generals", []):
		if general.get("busy", false) or general.get("governor", false):
			continue
		generals.add_item(str(general.get("name", "将领")))
		generals.set_item_metadata(generals.item_count - 1, str(general.get("id", "")))
	_form.add_child(generals)
	generals.item_selected.connect(func(_index: int) -> void:
		if is_instance_valid(_form_error):
			_form_error.text = "")
	for unit: Dictionary in _view.get("units", []):
		if int(unit.get("available", 0)) <= 0:
			continue
		var row: HBoxContainer = HBoxContainer.new()
		_form.add_child(row)
		var quantity: Label = _label(str(unit.get("name", "士兵")) + " · 可用 " + str(unit.get("available", 0)))
		row.add_child(quantity)
		var count: SpinBox = SpinBox.new()
		count.max_value = float(unit.get("available", 0))
		count.step = 1.0
		count.custom_minimum_size.x = 120.0
		row.add_child(count)
		_counts[str(unit.id)] = count
		_count_labels[str(unit.id)] = quantity
	var error: Label = _label("")
	_form_error = error
	_form.add_child(error)
	_send = _button("派遣援军" if ally else "出征掠夺", func() -> void:
		if not _allowed:
			return
		if generals.item_count == 0 or generals.selected < 0:
			error.text = "没有可出征将领，请先召回或招募。"
			return
		var army: Dictionary = {}
		var total: int = 0
		for id: String in _counts:
			var count: SpinBox = _counts[id]
			count.apply()
			var value: int = int(count.value)
			if value > 0:
				army[id] = value
				total += value
		if total == 0:
			error.text = "请选择至少一名士兵。"
			return
		_send.disabled = true
		error.text = "正在核定派遣…"
		# A synchronous validation/storage failure may update this form during
		# the signal. Do not overwrite its error after the handler returns.
		command_requested.emit("shared.aid" if ally else "shared.attackPlayer", [{"targetId": str(player.id), "targetCity": "capital", "mode": "raid", "general": str(generals.get_item_metadata(generals.selected)), "army": army}]), not _allowed)
	_form.add_child(_send)
	_refresh_form_availability()
	_scroll.scroll_vertical = 0

func _refresh_form_availability() -> void:
	if not is_instance_valid(_generals) or _target.is_empty():
		return
	var units: Dictionary = {}
	for unit: Dictionary in _view.get("units", []):
		units[str(unit.get("id", ""))] = unit
	for id: String in _counts:
		var unit: Dictionary = units.get(id, {})
		var count: SpinBox = _counts[id]
		var available_count: float = maxi(0, int(unit.get("available", 0)))
		if not is_equal_approx(count.max_value, available_count):
			count.max_value = available_count
		var editable: bool = _allowed and count.max_value > 0
		if count.editable != editable:
			count.editable = editable
		(_count_labels[id] as Label).text = str(unit.get("name", "士兵")) + " · 可用 " + str(int(count.max_value))
	var available: Array[Dictionary] = []
	for general: Dictionary in _view.get("generals", []):
		if not general.get("busy", false) and not general.get("governor", false):
			available.append({"id": str(general.get("id", "")), "name": str(general.get("name", "将领"))})
	var signature: String = JSON.stringify(available)
	if signature != _general_signature:
		_general_signature = signature
		var selected: String = str(_generals.get_item_metadata(_generals.selected)) if _generals.selected >= 0 else ""
		_generals.clear()
		var index: int = -1
		for general: Dictionary in available:
			_generals.add_item(general.name)
			_generals.set_item_metadata(_generals.item_count - 1, general.id)
			if general.id == selected:
				index = _generals.item_count - 1
		_generals.select(index)
		if not selected.is_empty() and index < 0 and is_instance_valid(_form_error):
			_form_error.text = "原将领已不可出征，请重新选择。"
	_generals.disabled = not _allowed

func _refresh_eta() -> void:
	var now: float = Time.get_unix_time_from_system() * 1000.0 + _server_offset
	for label: Label in _eta_labels:
		if not is_instance_valid(label):
			continue
		var march: Dictionary = label.get_meta("march", {})
		var status: String = str(march.get("status", "march"))
		if status == "stationed":
			label.text = str(label.get_meta("heading", "部队")) + "\n驻扎中"
			continue
		var deadline: Variant = march.get("returnAt", 0) if status == "return" else march.get("arrive", 0)
		var end: float = float(deadline) if deadline is float or deadline is int else 0.0
		var seconds: int = maxi(0, int(ceil((end - now) / 1000.0)))
		var eta: String = "待服务器结算" if seconds == 0 else ("返城 " if status == "return" else "抵达 ") + "%d分%02d秒" % [seconds / 60, seconds % 60]
		label.text = str(label.get_meta("heading", "部队")) + "\n" + eta
