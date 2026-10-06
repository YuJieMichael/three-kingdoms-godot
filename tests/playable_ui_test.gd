extends SceneTree

class ApiProbe extends "res://src/game_api.gd":
	var requests: Array[Dictionary] = []
	var quotations: Array[Dictionary] = []
	var pending: bool = false
	func _ready() -> void:
		pass
	func _has_mutation() -> bool:
		return pending
	func command(type: String, args: Array = [], source_city: String = "") -> void:
		if not connected or pending:
			return
		requests.append({"type": type, "args": args, "sourceCity": source_city})
		pending = true
	func request_quote(kind: String, args: Array, request_id: String) -> void:
		quotations.append({"kind": kind, "args": args, "requestId": request_id})

class ClientProbe extends "res://src/main.gd":
	func _ready() -> void:
		theme = _make_theme()
		_build_shell()
		add_child(api)
		api.snapshot_received.connect(_receive_snapshot)
		api.command_completed.connect(_command_completed)
		api.status_changed.connect(_connection_changed)
		api.request_failed.connect(_request_failed)
		api.quote_received.connect(_receive_quote)
		_show_page("world")

var _checks: int = 0
var _failures: int = 0
var _fixture: Dictionary
var _client: ClientProbe
var _api: ApiProbe

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

func _button(node: Node, text: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and child.text == text:
			return child
		var found: Button = _button(child, text)
		if found != null:
			return found
	return null

func _run() -> void:
	var node: String = OS.get_environment("TK_NODE")
	var output: Array = []
	if node.is_empty() or OS.execute(node, [ProjectSettings.globalize_path("res://tests/helpers/playable-view.mjs")], output) != 0:
		push_error("TK_NODE must provide the isolated canonical fixture")
		quit(1)
		return
	_fixture = JSON.parse_string(str(output[0]))
	_client = ClientProbe.new()
	_api = ApiProbe.new()
	_api.connected = true
	_api.last_snapshot = _fixture
	_client.api = _api
	_client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_client)
	_client._receive_snapshot(_fixture)
	_client._receive_world(_fixture.worldSample)
	await _settle()
	_check(_client._objective_text.text.contains("奖励"), "The sidebar must show a real current objective")
	for width: int in [1280, 390]:
		root.size = Vector2i(width, 844)
		for group: Array in [["_show_progression", "_progression", ["missions", "daily", "epic", "honors", "chapters", "gifts"]], ["_show_heroes", "_heroes", ["generals", "wild", "captives", "equipment"]], ["_show_war_management", "_war_management", ["hospital", "captives", "defenses", "defense", "civic", "wages"]], ["_show_realm", "_realm", ["cities", "logistics", "plots", "holdings", "automation"]], ["_show_inventory", "_inventory", ["inventory", "shop"]]]:
			for section: String in group[2]:
				_client.call(str(group[0]), section)
				await _settle()
				var panel: Window = _client.get(str(group[1]))
				var scroll: ScrollContainer = panel.get("_scroll")
				var content: Control = panel.get("_content")
				_check(panel.visible and panel.size.x <= width - 24, "Real %s/%s panel must fit %dpx" % [group[1], section, width])
				_check(content.get_combined_minimum_size().x <= scroll.size.x, "Real %s/%s content must not overflow %dpx" % [group[1], section, width])
		_client._tasks_dialog()
		await _settle()
		for label: String in ["宝物与物资", "城外资源", "研究", "领地采集", "运输调遣"]:
			var expected: String = "城池与运输" if label == "运输调遣" else label
			_check(_button(_client._dialog, expected) != null, "The narrow transactions hub must expose " + expected)
		_check(_client._dialog.size.x <= width - 24, "The transaction hub must fit the viewport")
		_client._dialog.hide()
	_client._tasks_dialog()
	var hub: Window = _client._dialog
	var next_snapshot: Dictionary = _fixture.duplicate(true)
	next_snapshot.view.objective = {"title": "筑屋安民", "description": "建设民房", "route": "inner", "target": "house", "ready": false, "reward": {"wood": 180}}
	_client._receive_snapshot(next_snapshot)
	_check(_client._dialog == hub and _client._tasks_labels[0].text == "筑屋安民" and _client._tasks_action.text == "前往当前目标", "A confirmed mission must refresh the open hub without replacing its scroll container")
	_api.pending = true
	_client._connection_changed("等待确认", true)
	_check(_client._tasks_action.disabled, "The hub objective action must lock while a command is pending")
	_api.pending = false
	_client._command_completed("claimMission", {})
	_check(not _client._tasks_action.disabled, "The hub must unlock after a confirmed receipt")
	_client._receive_snapshot(_fixture)
	_client._route_objective("wildGenerals", "")
	_check(_client._heroes.visible and _client._heroes._section == "wild", "Wild-general objective must navigate to the actual lead interface")
	_client._route_objective("heroes", "equipment")
	_check(_client._heroes._section == "equipment", "Material navigation must reach equipment")
	_client._route_objective("honors", "")
	_check(_client._progression.visible and not _client._heroes.visible, "Only the chosen feature modal may remain open")
	_client._route_objective("army", "archer")
	_check(_client._dialog.visible and _button(_client._dialog, "开始训练") != null, "Archer objective must open the actual training dialog")
	_client._route_objective("outer", "")
	_check(_client._realm.visible and _client._realm._section == "plots", "Outdoor objective must open resource plots")
	root.size = Vector2i(1280, 844)
	await _settle()
	_client._show_inventory("inventory")
	root.size = Vector2i(390, 844)
	await _settle()
	_check(_client._inventory.visible and _client._inventory.size.x <= 366, "An open feature panel must refit after the viewport becomes narrow")
	_client._route_objective("city", "blueprint")
	_check(_client._dialog.visible and _client._dialog.title == "城内建筑", "Blueprint navigation must reach the building overview")
	_client._dispatch_node("field")
	await _settle()
	var preview: Button = _button(_client._dialog, "预览出征")
	var confirm: Button = _button(_client._dialog, "确认派遣部队")
	_check(preview != null and confirm.disabled, "Dispatch must require a successful quotation first")
	preview.emit_signal("pressed")
	var quote: Dictionary = _api.quotations.back()
	_api.quote_received.emit({"requestId": quote.requestId, "quote": {"reason": "", "seconds": 90, "returnSeconds": 45, "foodCost": 180, "carry": 1000, "command": {"type": "dispatch", "args": quote.args}}})
	_check(not confirm.disabled, "A matching successful quotation must enable dispatch")
	for child: Node in _client._dialog.find_children("*", "SpinBox", true, false):
		child.get_line_edit().text = "0"
		child.get_line_edit().emit_signal("text_changed", "0")
		break
	_check(confirm.disabled, "Unsubmitted soldier text must invalidate the former quotation")
	preview.emit_signal("pressed")
	quote = _api.quotations.back()
	_api.quote_received.emit({"requestId": "older_quotation", "quote": {"reason": "", "command": {"type": "dispatch", "args": []}}})
	_check(confirm.disabled, "An old quotation must not authorize a changed army")
	_api.quote_received.emit({"requestId": quote.requestId, "quote": {"reason": "至少选择 1 名士兵"}})
	_check(confirm.disabled, "Canonical failed quotations must block dispatch")
	_client._show_inventory("inventory")
	_client._show_progression("missions")
	_api.connected = false
	_client._connection_changed("断线", false)
	_check(not _client._progression._connected and not _client._inventory._connected, "Connection changes must lock both visible and cached panels")
	_client._mode_changed("shared")
	_check(_client._heroes == null and _client._progression == null and _client._war_management == null and _client._realm == null and _client._inventory == null, "Identity change must destroy every private feature panel and its drafts")
	_check(_client._dispatch_quote_id.is_empty() and not _client._dispatch_preview.is_valid(), "Identity change must clear any former quotation")
	root.remove_child(_client)
	_client.queue_free()
	await process_frame
	print("PLAYABLE_UI_TEST checks=", _checks, " failures=", _failures)
	quit(0 if _failures == 0 else 1)
