extends SceneTree

## Real controls and main-scene integration, without network or player saves.
## Canonical prices/room requirements are separately verified over HTTP.
class CommandProbe extends "res://src/game_api.gd":
	var requests: Array[Dictionary] = []
	var in_flight: bool = false
	func _ready() -> void:
		pass
	func _has_mutation() -> bool:
		return in_flight
	func command(type: String, args: Array = [], source_city: String = "") -> void:
		if not connected or in_flight:
			request_failed.emit("等待连接或当前操作完成")
			return
		requests.append({"type": type, "args": args, "sourceCity": source_city})
		in_flight = true
	func finish(type: String, payload: Dictionary) -> void:
		in_flight = false
		snapshot_received.emit(payload)
		command_completed.emit(type, payload)

class ClientProbe extends "res://src/main.gd":
	func _ready() -> void:
		theme = _make_theme()
		_build_shell()
		add_child(api)
		api.snapshot_received.connect(_receive_snapshot)
		api.status_changed.connect(_connection_changed)
		api.request_failed.connect(_request_failed)
		api.command_completed.connect(_command_completed)
		_show_page("city")

var _checks: int = 0
var _failures: int = 0
var _client: ClientProbe
var _api: CommandProbe
var _view: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _fixture() -> Dictionary:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/godot-view.json"))
	var view: Dictionary = parsed.get("view", {}).duplicate(true)
	view.res = {"food": 10000, "wood": 5000, "stone": 5000, "iron": 5000, "gold": 50000}
	view.caps = {"food": 10000, "wood": 10000, "stone": 10000, "iron": 10000, "gold": 1000000}
	view.objective = {"title": "兴建城池并训练首次出征的弓箭手部队", "description": "扩建官府、储备物资并完成兵种训练，准备首次出征。", "reward": {"food": 150000, "wood": 100000, "stone": 100000, "iron": 50000, "gold": 100000}, "ready": false}
	view.market = {"level": 2, "resources": []}
	for resource: String in ["food", "wood", "stone", "iron"]:
		view.market.resources.append({"id": resource, "name": resource,
			"buy": {"limit": 50000, "scale": 200000, "room": 0 if resource == "food" else 5000, "stock": 50000, "reason": "", "warning": "该资源已满仓，仍可购买；成交后暂时超仓。" if resource == "food" else "购买超过仓储空位时可暂时超仓。"},
			"sell": {"limit": 10000 if resource == "food" else 5000, "scale": 200000, "room": 950000, "stock": 10000 if resource == "food" else 5000, "reason": "", "warning": ""}})
	view.governance = {"governorId": "su", "population": 200, "maxPopulation": 300, "freePopulation": 200, "morale": 80, "unrest": 10, "tax": 20, "targetMorale": 70, "goldPerMinute": 4, "productionBoost": 1.68, "constructionFactor": 1.68,
		"candidates": [{"id": "su", "name": "苏荷", "pol": 68, "governor": true, "busy": false, "reason": ""}, {"id": "lin", "name": "林衡", "pol": 45, "governor": false, "busy": false, "reason": ""}, {"id": "busy", "name": "外出将领", "pol": 80, "governor": false, "busy": true, "reason": "该武将正在出征或驻守"}]}
	view.inn = {"level": 2, "capacity": 4, "used": 2, "remaining": 2, "refreshReason": "", "candidates": [{"id": "local_1800000000000", "name": "魏衡", "level": 2, "atk": 73, "def": 50, "pol": 81, "wis": 62, "lead": 20, "price": 2000, "affordable": true, "reason": ""}]}
	return view

func _run() -> void:
	root.size = Vector2i(1280, 844)
	_view = _fixture()
	_client = ClientProbe.new()
	_api = CommandProbe.new()
	_api.connected = true
	_client.api = _api
	_client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_client)
	_client._receive_snapshot({"view": _view, "state": {}})
	await _settle()
	await _test_market()
	await _test_governance()
	await _test_inn()
	await _test_layout()
	root.remove_child(_client)
	_client.queue_free()
	await process_frame
	print("MANAGEMENT_TEST_CHECKS=", _checks, " failures=", _failures)
	quit(0 if _failures == 0 else 1)

func _test_market() -> void:
	_client._show_management("market")
	await _settle()
	var dialog: KingdomManagementDialog = _client._management
	_check(not dialog._trade_button.disabled, "A full resource warehouse must still allow a quoted purchase.")
	_check(dialog._market_warning.text.contains("超仓") and dialog._market_preview.text.contains("11000"), "A full warehouse purchase must preview the entire deposit and overflow.")
	dialog._count.get_line_edit().text = "999999"
	dialog._count.get_line_edit().emit_signal("text_changed", "999999")
	_check(dialog._market_preview.text.contains("60000") and dialog._trade_button.text.contains("50000"), "An oversized typed draft must show the clamped transaction preview before submission.")
	dialog._trade_button.emit_signal("pressed")
	_check(_api.requests.size() == 1 and _api.requests[0].type == "trade" and _api.requests[0].args == ["food", 50000, true], "Typing above the limit and directly clicking buy must commit and clamp before sending.")
	_check(dialog._trade_button.disabled, "A dispatched trade must immediately block duplicate clicks.")
	dialog._trade_button.emit_signal("pressed")
	_check(_api.requests.size() == 1, "An in-flight trade must never create a second request.")
	_client._receive_snapshot({"view": _view, "state": {}})
	_check(dialog._trade_button.disabled, "Polling snapshots must not unlock an unconfirmed trade.")
	_api.finish("trade", {"view": _view, "state": {}})
	_check(not dialog._trade_button.disabled, "An acknowledged trade must restore quote-based actions.")
	dialog._mode.select(1)
	dialog._mode.emit_signal("item_selected", 1)
	_check(dialog._count.value == 10000.0 and dialog._count.max_value == 10000.0, "Switching to sell must clamp the retained quantity to the canonical sell limit.")
	dialog._count.value = 0
	_check(dialog._trade_button.disabled, "Zero quantity must initially disable a transaction.")
	dialog._count.get_line_edit().text = "10000"
	dialog._count.get_line_edit().emit_signal("text_changed", "10000")
	_check(not dialog._trade_button.disabled and dialog._market_preview.text.contains("60000"), "Typing a valid sell draft from zero must enable its button and preview immediately.")
	dialog._trade_button.emit_signal("pressed")
	_check(_api.requests.back().args == ["food", 10000, false], "Sell must send the resource and canonical direction flag.")
	_api.finish("trade", {"view": _view, "state": {}})
	_client._request_failed("黄金不足，请重新核对报价")
	_check(dialog._status.text.contains("黄金不足"), "A command failure must be visible inside the open modal.")
	var blocked: Dictionary = _view.duplicate(true)
	blocked.market.resources[0].sell = {"limit": 0, "reason": "黄金已满仓，当前不能卖出", "warning": ""}
	dialog.update_view(blocked)
	_check(dialog._trade_button.disabled and dialog._market_warning.text.contains("黄金已满仓"), "A canonical blocked sale must show its reason and disable execution.")
	dialog.update_view(_view)
	dialog._mode.select(0)
	dialog._mode.emit_signal("item_selected", 0)
	dialog._count.value = 777
	var poll: Dictionary = _view.duplicate(true)
	poll.res.gold = 50100
	dialog.update_view(poll)
	_check(dialog._count.value == 777.0, "Resource polling must preserve an affordable quantity draft.")
	dialog._count.get_line_edit().text = "2345"
	dialog._count.get_line_edit().emit_signal("text_changed", "2345")
	dialog.update_view(poll)
	_check(dialog._count.get_line_edit().text == "2345", "Resource polling must preserve text which is still being edited.")
	var no_budget: Dictionary = poll.duplicate(true)
	no_budget.market.resources[0].buy = {"limit": 0, "reason": "黄金不足", "warning": ""}
	dialog.update_view(no_budget)
	_check(dialog._count.get_line_edit().text == "2345" and dialog._trade_button.disabled, "A zero-limit quote must preserve the edited text but disable purchase.")
	dialog.update_view(poll)
	_check(not dialog._trade_button.disabled, "A later affordable quote must restore a valid retained text draft.")
	dialog._count.get_line_edit().text = "1.9"
	dialog._count.get_line_edit().emit_signal("text_changed", "1.9")
	_check(dialog._trade_button.text.contains("2"), "The draft preview must use the native integer rounding of SpinBox.")
	dialog._trade_button.emit_signal("pressed")
	_check(_api.requests.back().args == ["food", 2, true], "Submitting a decimal draft must match the rounded preview.")
	_api.in_flight = false
	_api.request_failed.emit("成交失败，黄金不足")
	_check(dialog._status.text.contains("成交失败") and not dialog._trade_button.disabled, "A definitive failure must show its reason and unlock eligible actions.")
	_api.connected = false
	_api.in_flight = true
	_api.request_failed.emit("连接中断，未确认操作等待重连")
	_check(dialog._status.text.contains("等待重连") and dialog._trade_button.disabled, "An unconfirmed transport failure must remain blocked and visible inside the modal.")
	_api.connected = true
	_api.finish("trade", {"view": _view, "state": {}})
	dialog.hide()

func _test_governance() -> void:
	_client._show_management("governance")
	await _settle()
	var dialog: KingdomManagementDialog = _client._management
	_check(dialog._governor_button.disabled, "Reappointing the current governor must not create an unnecessary command.")
	_check(dialog._governor.is_item_disabled(2), "Busy or stationed candidates must be disabled using the canonical reason.")
	dialog._governor.select(2)
	dialog._governor.emit_signal("item_selected", 2)
	_check(dialog._governor_button.disabled and dialog._governor_info.text.contains("出征或驻守"), "Even a forced busy selection must stay unappointable.")
	dialog._governor.select(1)
	dialog._governor.emit_signal("item_selected", 1)
	dialog._governor_button.emit_signal("pressed")
	_check(_api.requests.back().type == "setGovernor" and _api.requests.back().args == ["lin"], "Governor appointment must send the chosen canonical ID.")
	_api.finish("setGovernor", {"view": _view, "state": {}})
	_check(dialog._governor_info.text.contains("城外生产城守系数") and dialog._governor_info.text.contains("含建造科技"), "Production and construction explanations must preserve their actual scope.")
	_check(dialog._tax_info.text.contains("70"), "The morale target must use the service quote including unrest.")
	_check(dialog._tax_button.disabled, "The initial unchanged tax action must be disabled.")
	dialog._tax.get_line_edit().text = "30"
	dialog._tax.get_line_edit().emit_signal("text_changed", "30")
	_check(not dialog._tax_button.disabled, "Typing a first tax draft must enable its button before losing input focus.")
	dialog._tax_button.emit_signal("pressed")
	_check(_api.requests.back().type == "setTax" and _api.requests.back().args == [30], "A first typed tax draft must be accepted with one direct click.")
	_api.finish("setTax", {"view": _view, "state": {}})
	var fractional: Dictionary = _view.duplicate(true)
	fractional.governance.goldPerMinute = 0.47
	dialog.update_view(fractional)
	_check(dialog._population_info.text.contains("0.47/分钟"), "Small canonical gold rates must not be misleadingly rounded to zero.")
	dialog._tax.value = 35
	dialog.update_view(_view)
	_check(dialog._tax.value == 35.0, "Polling must preserve an edited tax draft until it is submitted.")
	dialog._tax.get_line_edit().text = "125"
	dialog._tax_button.emit_signal("pressed")
	_check(_api.requests.back().type == "setTax" and _api.requests.back().args == [100], "Typed tax above 100 must commit and clamp before sending.")
	_api.finish("setTax", {"view": _view, "state": {}})
	_check(dialog._tax.value == 20.0, "The next acknowledged snapshot must replace a submitted tax draft.")
	dialog.hide()

func _test_inn() -> void:
	_client._show_management("inn")
	await _settle()
	var dialog: KingdomManagementDialog = _client._management
	_check(dialog._inn_info.text.contains("2 / 4") and dialog._inn_info.text.contains("被俘将领"), "Inn capacity must explain that captured generals occupy rooms too.")
	dialog._recruit("local_1800000000000")
	_check(_api.requests.back().type == "recruit" and _api.requests.back().args == ["local_1800000000000"], "Recruitment must send the actual candidate ID.")
	var count: int = _api.requests.size()
	dialog._recruit("local_1800000000000")
	_check(_api.requests.size() == count, "A pending recruitment must reject duplicate commands.")
	var recruited: Dictionary = _view.duplicate(true)
	recruited.inn.used = 3
	recruited.inn.remaining = 1
	recruited.inn.candidates = []
	_api.finish("recruit", {"view": recruited, "state": {}})
	_check(dialog._inn_info.text.contains("3 / 4") and not _button_labels(dialog._inn_candidates).has("招募 · 黄金 2000"), "Acknowledging recruitment must remove the candidate and refresh room usage.")
	dialog._inn_refresh.emit_signal("pressed")
	_check(_api.requests.back().type == "refreshInn" and _api.requests.back().args == [], "Inn refresh must use the existing free canonical command.")
	_api.finish("refreshInn", {"view": _view, "state": {}})
	var full: Dictionary = _view.duplicate(true)
	full.inn.used = 4
	full.inn.remaining = 0
	full.inn.candidates[0].reason = "招贤馆没有空闲房间（包含被俘将领）"
	dialog.update_view(full)
	dialog._recruit("local_1800000000000")
	_check(_api.requests.back().type == "refreshInn", "A full room quote must block recruitment even when directly invoked.")
	var missing: Dictionary = _view.duplicate(true)
	missing.inn.refreshReason = "请先建造客栈"
	dialog.update_view(missing)
	_check(dialog._inn_refresh.disabled and dialog._inn_info.text.contains("请先建造客栈"), "Missing inn prerequisites must be visible and disable refresh.")
	dialog.hide()

func _test_layout() -> void:
	for width: int in [1280, 390]:
		root.size = Vector2i(width, 844)
		await _settle()
		_client._receive_snapshot({"view": _view, "state": {}})
		_client._show_page("city")
		await _settle()
		_check(_client._body.size.x <= float(width - (16 if width == 390 else 24)), "City management buttons must fit the %d px shell." % width)
		var city_buttons: PackedStringArray = _button_labels(_client._center)
		for label: String in ["城内", "城外田庄", "城务"]:
			_check(city_buttons.has(label), "The city scene must expose %s on the %d px layout." % [label, width])
		_client._city_affairs_dialog()
		await _settle()
		var affairs: PackedStringArray = _button_labels(_client._dialog)
		for label: String in ["市场交易", "城守税率", "客栈招募"]:
			_check(affairs.has(label), "City affairs must expose %s on the %d px layout." % [label, width])
		_client._tasks_dialog()
		await _settle()
		_check(_client._dialog.size.x <= width - 24, "A five-resource reward and long title must not widen the %d px tasks popup." % width)
		_check(_client._dialog.position.x >= 0 and _client._dialog.position.x + _client._dialog.size.x <= width, "The tasks popup must keep both horizontal edges inside the %d px viewport." % width)
		var mobile_buttons: PackedStringArray = _button_labels(_client._dialog)
		for label: String in ["市场交易", "城守与税率", "客栈招募"]:
			_check(mobile_buttons.has(label), "The transactions menu must expose %s on the %d px layout." % [label, width])
		_client._dialog.hide()
		for section: String in ["market", "governance", "inn"]:
			_client._show_management(section)
			await _settle()
			var dialog: KingdomManagementDialog = _client._management
			_check(dialog.size.x <= width - 24 and dialog.size.y <= 844 - 40, "The %s dialog must fit the %d px viewport." % [section, width])
			_check(dialog._content.get_combined_minimum_size().x <= dialog._scroll.size.x, "The %s content must fit its narrow scroll viewport without horizontal clipping." % section)
			_check(dialog._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Management sections must use a vertical scroll layout.")
			dialog.hide()
	_client._show_page("generals")
	await _settle()
	var general_buttons: PackedStringArray = _button_labels(_client._center)
	_check(general_buttons.has("招募将领") and general_buttons.has("任命城守"), "The generals roster must provide recruitment and governor actions.")

func _button_labels(node: Node) -> PackedStringArray:
	var result: PackedStringArray = []
	for child: Node in node.get_children():
		if child is Button:
			result.append((child as Button).text)
		result.append_array(_button_labels(child))
	return result
