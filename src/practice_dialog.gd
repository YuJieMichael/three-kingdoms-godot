class_name KingdomPracticeDialog
extends AcceptDialog

## A separate borrowed army. Only /practice receives these battle actions.
signal campaign_requested

const BattleScript: Script = preload("res://src/battle_view.gd")
const ReviewScript: Script = preload("res://src/battle_review_view.gd")
const SCENARIOS: Dictionary = {"shield_archer": "盾护推进", "spear_cavalry": "枪护弓队", "siege_guard": "器械破门"}
var api: KingdomApi
var _scenario: OptionButton
var _intro: Label
var _status: Label
var _battle: KingdomBattleView
var _review: KingdomBattleReviewView
var _start: Button
var _retry: Button
var _end: Button
var _campaign: Button
var _session: Dictionary = {}
var _last_request: Dictionary = {}
var _busy: bool = false
var _identity: String = ""


func _ready() -> void:
	title = "借调演练 · 先学会统兵"
	ok_button_text = "返回游戏"
	wrap_controls = false
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(column)
	_scenario = OptionButton.new()
	_scenario.custom_minimum_size.y = 44
	_scenario.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id: String in SCENARIOS:
		_scenario.add_item(str(SCENARIOS[id]))
		_scenario.set_item_metadata(_scenario.item_count - 1, id)
	column.add_child(_scenario)
	_start = _button(column, "开始借调演练", _start_practice, true)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var note: Label = _label(content, "借调部队只用于演练，奖励、战损和胜场不进入城池。建设与正式行军仍按原时间推进。", "MutedLabel")
	note.name = "PracticeBoundary"
	_intro = _label(content, "选择演练，先看目标，再为全军或单队下达军令。", "MutedLabel")
	_battle = BattleScript.new() as KingdomBattleView
	_battle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_battle)
	_battle.action_requested.connect(_battle_action)
	_review = ReviewScript.new() as KingdomBattleReviewView
	content.add_child(_review)
	_status = _label(column, "", "MutedLabel")
	_status.max_lines_visible = 2
	var retry_row: HFlowContainer = HFlowContainer.new()
	column.add_child(retry_row)
	_retry = _button(retry_row, "重试原操作", _retry_request)
	var next_row: HFlowContainer = HFlowContainer.new()
	column.add_child(next_row)
	_end = _button(next_row, "结束演练", _end_practice)
	_campaign = _button(next_row, "准备自主出征", _open_campaign, true)
	get_tree().root.size_changed.connect(_fit_window)
	if api != null:
		api.practice_received.connect(_receive_practice)
		api.practice_failed.connect(_practice_error)
		api.status_changed.connect(_connection_changed)
		api.mode_changed.connect(func(_mode: String) -> void: clear_context(); hide())
	_refresh_actions()


func open_practice() -> void:
	_identity = _api_identity()
	_fit_window()
	popup_centered(size)
	_refresh_actions()
	if not _start.disabled:
		_start.grab_focus()
	elif _retry.visible and not _retry.disabled:
		_retry.grab_focus()


func _start_practice() -> void:
	var request: Dictionary = {"action": "start", "scenario": str(_scenario.get_item_metadata(_scenario.selected))}
	_add_session(request)
	_send(request)


func _battle_action(type: String, args: Array) -> void:
	if _session.is_empty() or type not in ["setBattleOrders", "setBattleOrder", "battleRound"]:
		return
	var request: Dictionary = {"action": "round" if type == "battleRound" else "order"}
	if type != "battleRound":
		request["type"] = type
		request["args"] = args.duplicate(true)
	_add_session(request)
	_send(request)


func _end_practice() -> void:
	if _session.is_empty():
		return
	var request: Dictionary = {"action": "end"}
	_add_session(request)
	_send(request)


func _add_session(request: Dictionary) -> void:
	if not _session.is_empty():
		request["sessionId"] = str(_session.get("sessionId", ""))
		request["revision"] = int(_session.get("revision", 0))


func _send(request: Dictionary, retry: bool = false) -> void:
	if _busy or api == null or not api.connected or api.mode != "local" or _api_identity() != _identity:
		return
	if not retry and not _last_request.is_empty():
		return
	if not retry:
		request["requestId"] = "practice_" + Crypto.new().generate_random_bytes(12).hex_encode()
	_last_request = request.duplicate(true)
	_busy = true
	_status.text = "正在确认演练操作…"
	_refresh_actions()
	api.request_practice(request)


func _retry_request() -> void:
	if not _last_request.is_empty():
		_send(_last_request.duplicate(true), true)


func _receive_practice(payload: Dictionary) -> void:
	if str(payload.get("requestId", "")) != str(_last_request.get("requestId", "")) or _api_identity() != _identity:
		return
	_busy = false
	_last_request.clear()
	var value: Variant = payload.get("practice")
	if value is Dictionary:
		_session = value.duplicate(true)
		_intro.text = str(_session.get("description", "")) + "\n目标：" + str(_session.get("objective", ""))
		_battle.set_battle(_session.get("battle"), _session.get("units", {}))
		_review.set_review(_session.get("review", {}))
		_status.text = "演练已结束，可换军令重开比较；正式城池未获得奖励。" if _session.get("battle", {}).get("finished", false) else "军令下回合生效；演练可手动推进下一回合。"
	else:
		clear_context()
		_status.text = "演练已结束。"
	_status.tooltip_text = _status.text
	_refresh_actions()


func _practice_error(message: String, code: String) -> void:
	if not _busy and not visible:
		return
	_busy = false
	if code == "PRACTICE_EXPIRED":
		clear_context()
		_status.text = message + "\n旧会话已失效，可重新借调。"
	elif code == "PRACTICE_REVISION_CONFLICT" and not _session.is_empty():
		_last_request.clear()
		var request: Dictionary = {"action": "sync"}
		_add_session(request)
		_send(request)
		return
	elif code in ["INTERNAL_ERROR", "UNCONFIRMED_IDENTITY", "CLIENT_PRACTICE_PENDING"]:
		_status.text = message + "\n先重试原操作，收到确认前不会发送新回合。"
	else:
		# A structured rejection did not commit a candidate. Keep the known
		# session ID/revision so restarting reuses it instead of leaking slots.
		_last_request.clear()
		_status.text = message + "\n可调整军令，或重新借调此会话。"
	_status.tooltip_text = _status.text
	_refresh_actions()


func _connection_changed(_message: String, connected: bool) -> void:
	if not connected:
		_busy = false
		_status.text = "连接中断。正式进度由原服务保存；演练会话可能需要重新开始。"
	_refresh_actions()


func _open_campaign() -> void:
	if _busy:
		return
	hide()
	campaign_requested.emit()


func clear_context() -> void:
	_session.clear()
	_last_request.clear()
	_busy = false
	if is_instance_valid(_battle):
		_battle.set_battle(null)
		_review.set_review({})
	_refresh_actions()


func _refresh_actions() -> void:
	if not is_instance_valid(_start):
		return
	var available: bool = api != null and api.connected and api.mode == "local" and not api._has_mutation() and _api_identity() == _identity
	var unconfirmed: bool = not _last_request.is_empty()
	_status.tooltip_text = _status.text
	_start.text = "重新借调演练" if not _session.is_empty() else "开始借调演练"
	_start.disabled = not available or _busy or unconfirmed
	_scenario.disabled = _busy or unconfirmed
	_end.visible = not _session.is_empty()
	_end.disabled = not available or _busy or unconfirmed
	_retry.visible = not _last_request.is_empty() and not _busy
	_retry.disabled = not available or _busy
	_campaign.disabled = _busy
	_battle.set_actions_enabled(available and not _busy and not unconfirmed)


func set_command_state(_connected: bool, _pending: bool) -> void:
	_refresh_actions()


func _api_identity() -> String:
	return api.base_url + "|" + api._authority + "|" + api.mode if api != null else ""


func _fit_window() -> void:
	var viewport: Vector2 = get_tree().root.get_visible_rect().size
	min_size = Vector2i(280, 340)
	size = Vector2i(int(minf(880.0, viewport.x - 24.0)), int(minf(800.0, viewport.y - 54.0)))
	if visible:
		position = Vector2i((viewport - Vector2(size)) / 2.0)


func _label(parent: Node, text: String, variation: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable, primary: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.theme_type_variation = "PrimaryButton" if primary else "UtilityButton"
	button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
