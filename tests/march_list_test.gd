extends SceneTree

## Exercise production march rows and command callbacks with safe DTOs only.
## The probes never initialize a bridge, connect to a service, or write a save.
class ApiProbe extends "res://src/game_api.gd":
	var pending: bool = false
	var commands: Array[Dictionary] = []
	var quotes: Array[Dictionary] = []
	var explicit_sources: Array[String] = []
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _has_mutation() -> bool:
		return pending
	func command(type: String, args: Array = [], source: String = "") -> void:
		if not connected or pending:
			return
		explicit_sources.append(source)
		# Match the real API's source default, so an omitted row source is caught.
		if source.is_empty():
			source = str(last_snapshot.get("view", {}).get("city", {}).get("id", "capital"))
		commands.append({"type": type, "args": args.duplicate(true), "sourceCity": source})
		pending = true
	func request_quote(kind: String, args: Array, request: String) -> void:
		quotes.append({"kind": kind, "args": args.duplicate(true), "requestId": request})
	func acknowledge(type: String) -> void:
		pending = false
		command_completed.emit(type, {"ok": true})
	func fail(message: String) -> void:
		pending = false
		request_failed.emit(message)

class ClientProbe extends "res://src/main.gd":
	func _ready() -> void:
		_smoke = true
		_initialize_inputs()
		theme = _make_theme()
		_build_shell()
		add_child(api)
		api.command_completed.connect(_command_completed)
		api.request_failed.connect(_request_failed)
		_show_page("world")
	func _check_smoke() -> void:
		pass

var checks: int = 0
var failures: int = 0
var client: ClientProbe
var api: ApiProbe
var payload: Dictionary


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceMarchListTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	root.gui_embed_subwindows = true
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _settle() -> void:
	for frame: int in 4:
		await process_frame


func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + 60000.0


func _expedition(source: String, node: String, start: int, name: String) -> Dictionary:
	return {"id": "expedition:%s:%s:%d" % [source, node, start], "sourceCity": source, "node": node,
		"label": name, "general": "lin", "status": "march", "start": start,
		"arrive": _server_now() + 90000.0, "count": 20, "canStartBattle": false,
		"selectCommand": {"type": "selectExpedition", "args": [node], "sourceCity": source}}


func _fixture() -> Array[Dictionary]:
	return [
		_expedition("north", "field", 1000, "北城弓军"),
		_expedition("south", "field", 2000, "南城弓军"),
		_expedition("north", "hill", 3000, "北城山岭军"),
		{"id": "garrison:capital:camp", "label": "本城营地驻军", "node": "camp", "sourceCity": "capital", "status": "stationed", "arrive": null, "count": 10,
			"recallCommand": {"type": "recallGarrison", "args": ["camp"], "sourceCity": "capital"}},
		{"id": "garrison:north:fort", "label": "北城堡垒驻军", "node": "fort", "sourceCity": "north", "status": "return", "arrive": _server_now() - 1.0, "returnAt": _server_now() + 30000.0, "count": 8,
			"recallCommand": {"type": "recallGarrison", "args": ["fort"], "sourceCity": "north"}},
		{"id": "scout:north:1", "label": "河畔斥候", "type": "scout", "sourceCity": "north", "status": "return", "arrive": _server_now() + 90000.0,
			"returnAt": _server_now() + 30000.0, "count": 18, "sentCount": 20, "lost": 2},
		{"id": "logistics:1", "label": "跨城物资运输", "sourceCity": "north", "status": "outbound", "arrive": _server_now() + 45000.0, "count": 12},
		{"id": "shared:incoming", "label": "讨伐 · 来军", "sourceCity": "capital", "status": "march", "shared": true, "incoming": true, "arrive": _server_now() + 120000.0, "count": null}]


func _snapshot(rows: Array, city: String = "capital") -> void:
	payload["serverTime"] = _server_now()
	payload.view.city = {"id": city, "name": "北原城" if city == "north" else "南江城" if city == "south" else "青溪城"}
	payload.view.marches = rows.duplicate(true)
	api.last_snapshot = payload.duplicate(true)
	client._receive_snapshot(payload)


func _selection_snapshot(rows: Array, city: String, node: String, phase: String = "march") -> void:
	# This is the selected expedition from a successful canonical response,
	# distinct from the flat UI marching rows.
	payload.state["expedition"] = {"node": node, "phase": phase}
	_snapshot(rows, city)


func _visible_action(id: String) -> bool:
	var button: Button = client._march_action_buttons.get(id)
	return is_instance_valid(button) and button.visible


func _visible_row(id: String) -> bool:
	var label: Label = client._march_labels.get(id)
	return is_instance_valid(label) and label.visible


func _run() -> void:
	root.size = Vector2i(1280, 844)
	payload = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/godot-view.json"))
	payload.view.cityList = [{"id": "capital", "name": "青溪城"}, {"id": "north", "name": "北原城"}, {"id": "south", "name": "南江城"}]
	# A private-save selection must never decide which normalized row is recalled.
	payload.state["expedition"] = {"node": "wrong-save-selection", "phase": "march"}
	api = ApiProbe.new()
	api.connected = true
	client = ClientProbe.new()
	client.api = api
	client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(client)
	var rows: Array[Dictionary] = _fixture()
	_snapshot(rows)
	client._receive_world(payload.worldSample)
	client._marches_dialog()
	await _settle()
	_check(client._march_labels.size() == rows.size(), "All-city expedition, garrison, scout, logistics and shared rows each appear once")
	_check(api.commands.is_empty() and api.quotes.is_empty(), "Opening and refreshing the list is read only")
	_check(_visible_action("expedition:north:field:1000") and _visible_action("garrison:capital:camp"), "Canonical expedition and stationed descriptors expose recall")
	_check(not _visible_action("garrison:north:fort"), "Returning garrison descriptor cannot leave a recall action")
	_check(not _visible_action("logistics:1") and not _visible_action("shared:incoming") and not _visible_action("scout:north:1"), "Rows without a safe recall descriptor never fall back to the selected army")
	var scout_label: Label = client._march_labels["scout:north:1"]
	_check(scout_label.text.contains("斥候返程") and scout_label.text.contains("北原城") and scout_label.text.contains("18人") and scout_label.text.contains("损失 2人"), "Scout row retains its own source, actual surviving count and known loss")
	_check(scout_label.text.contains("0分30秒"), "Return countdown uses returnAt and authoritative offset rather than stale arrival or wall time")

	var south_label: Label = client._march_labels["expedition:south:field:2000"]
	var south_action: Button = client._march_action_buttons["expedition:south:field:2000"]
	var north_label: Label = client._march_labels["expedition:north:field:1000"]
	var north_action: Button = client._march_action_buttons["expedition:north:field:1000"]
	south_action.grab_focus()
	_snapshot(rows)
	_check(client._march_labels["expedition:south:field:2000"] == south_label and client._march_action_buttons["expedition:south:field:2000"] == south_action, "Polling keeps existing row controls")
	_check(client._dialog.get_viewport().gui_get_focus_owner() == south_action, "Polling preserves keyboard focus in the list")
	rows[0].id = "expedition:north:field:9000"
	rows[0].start = 9000
	rows[0].status = "return"
	rows[0].returnAt = _server_now() + 30000.0
	rows[0].label = "北城归军"
	_snapshot(rows)
	_check(not client._march_labels.has("expedition:north:field:1000") and client._march_labels.get("expedition:north:field:9000") == north_label, "Canonical start-based ID changes rekey the same expedition row")
	_check(client._march_action_buttons.get("expedition:north:field:9000") == north_action and north_label.text.contains("北城归军") and north_label.text.contains("返城"), "Rekey updates label and action identity without claiming the army ended")
	_check(client._march_labels.get("expedition:south:field:2000") == south_label and south_label.text.contains("南城弓军"), "Same target in another city cannot be merged into the returning army")
	_check(not north_action.visible and client._dialog.get_viewport().gui_get_focus_owner() == south_action, "Return drops recall while preserving another row's focus")
	north_action.pressed.emit()
	_check(api.commands.is_empty(), "A retained return button cannot send a stale recall")
	rows[0].returnAt = _server_now() - 1.0
	rows[5].returnAt = _server_now() - 1.0
	_snapshot(rows)
	client._refresh_clock()
	_check(north_label.text.contains("待服务器结算") and scout_label.text.contains("待服务器结算"), "Expired normal and scout returns await server settlement without inventing arrival")
	_check(client._march_labels.get("expedition:north:field:9000") == north_label and rows[0].count == 20, "Clock expiry neither removes the return row nor zeros its army")
	var added: Dictionary = _expedition("south", "ridge", 4000, "新抵达列表的南军")
	rows.append(added)
	_snapshot(rows)
	_check(_visible_row(str(added.id)) and _visible_action(str(added.id)), "An open list adds a newly visible server march")
	_check(client._march_labels.size() == rows.size() and client._march_action_buttons["expedition:south:field:2000"] == south_action, "New rows do not duplicate groups or rebuild existing controls")
	_check(client._dialog.get_viewport().gui_get_focus_owner() == south_action, "Adding rows keeps the previously focused action")

	# The stationed filter follows current phase, including a descriptor retained
	# by the canonical DTO while a recalled garrison travels home.
	client._marches_dialog("stationed")
	await _settle()
	_check(_visible_row("garrison:capital:camp") and not _visible_row("garrison:north:fort") and not _visible_row("expedition:south:field:2000"), "Stationed navigation includes only currently stationed groups")
	var garrison_action: Button = client._march_action_buttons["garrison:capital:camp"]
	rows[3].status = "return"
	rows[3].returnAt = _server_now() + 20000.0
	_snapshot(rows)
	_check(not _visible_row("garrison:capital:camp") and not _visible_action("garrison:capital:camp"), "Stationed group leaves the filter immediately when its server phase becomes return")
	garrison_action.pressed.emit()
	_check(api.commands.is_empty(), "Hidden returning garrison descriptor cannot be activated")
	rows.append({"id": "garrison:south:ridge", "label": "新驻扎南军", "node": "ridge", "sourceCity": "south", "status": "stationed", "count": 15,
		"recallCommand": {"type": "recallGarrison", "args": ["ridge"], "sourceCity": "south"}})
	_snapshot(rows)
	_check(_visible_row("garrison:south:ridge") and _visible_action("garrison:south:ridge"), "New stationed groups enter an already open filter")
	_check(not _visible_row("garrison:capital:camp"), "Adding a stationed row cannot revive a returned garrison")
	var direct: Button = client._march_action_buttons["garrison:south:ridge"]
	direct.pressed.emit()
	direct.pressed.emit()
	_check(api.commands.size() == 1 and api.commands[0] == rows[-1].recallCommand, "Current garrison descriptor sends its exact source once")
	api.acknowledge("recallGarrison")
	api.commands.clear()

	# Bind through the production row button, then change the active city while
	# selection is awaiting its authoritative acknowledgment.
	rows = _fixture()
	_snapshot(rows)
	client._marches_dialog()
	await _settle()
	var chain_action: Button = client._march_action_buttons["expedition:north:hill:3000"]
	chain_action.pressed.emit()
	chain_action.pressed.emit()
	_check(api.commands.size() == 1 and api.commands[0] == rows[2].selectCommand, "Recall first selects the clicked city's exact expedition rather than the saved selection")
	_snapshot(rows, "south")
	_selection_snapshot(rows, "north", "hill")
	api.acknowledge("selectExpedition")
	_check(api.commands.size() == 2 and api.commands[1] == {"type": "recall", "args": [], "sourceCity": "north"}, "Matching selection acknowledgment recalls exactly the intended army")
	_check(api.explicit_sources[-1] == "north", "Chained recall explicitly binds its original source city")
	client._command_completed("selectExpedition", {})
	chain_action.pressed.emit()
	_check(api.commands.size() == 2, "Duplicate selection completion and pending clicks cannot repeat recall")
	api.acknowledge("recall")
	_check(api.commands.size() == 2 and api.quotes.is_empty(), "Recall chain consists of exactly select plus recall without a preview or extra mutation")
	api.commands.clear()
	for mismatch: Dictionary in [{"city": "south", "node": "hill", "phase": "march"}, {"city": "north", "node": "field", "phase": "march"}, {"city": "north", "node": "hill", "phase": "return"}]:
		chain_action.pressed.emit()
		_check(api.commands.size() == 1, "Mismatch case starts with a single target selection")
		_selection_snapshot(rows, str(mismatch.city), str(mismatch.node), str(mismatch.phase))
		api.acknowledge("selectExpedition")
		_check(api.commands.size() == 1, "Wrong selected city, target or phase revokes recall: " + JSON.stringify(mismatch))
		client._command_completed("selectExpedition", {})
		_check(api.commands.size() == 1, "Rejected selection cannot leave a recall chain for another acknowledgment")
		api.commands.clear()

	# Rekey an actionable row, proving that its retained callback resolves the
	# current ID metadata instead of retaining the original callback ID.
	var original_hill_label: Label = client._march_labels["expedition:north:hill:3000"]
	rows[2].id = "expedition:north:hill:7000"
	rows[2].start = 7000
	rows[2].label = "更新后的北城山岭军"
	_snapshot(rows)
	_check(client._march_labels.get("expedition:north:hill:7000") == original_hill_label and client._march_action_buttons.get("expedition:north:hill:7000") == chain_action, "Actionable ID rekey keeps existing controls")
	chain_action.pressed.emit()
	_check(api.commands.size() == 1 and api.commands[0] == rows[2].selectCommand, "Retained action resolves its latest row identity")
	api.fail("隔离测试：选择失败")
	api.acknowledge("selectExpedition")
	_check(api.commands.size() == 1, "Failed selection cancels its pending recall chain")
	api.commands.clear()

	api.pending = true
	client._refresh_clock()
	_check(chain_action.disabled, "Other pending mutation disables row actions")
	chain_action.pressed.emit()
	_check(api.commands.is_empty(), "Synthetic button signals cannot bypass a pending mutation")
	api.pending = false
	api.connected = false
	client._connection_changed("隔离测试：离线", false)
	client._refresh_clock()
	_check(chain_action.disabled, "Disconnected list retains known data with actions disabled")
	chain_action.pressed.emit()
	_check(api.commands.is_empty(), "Disconnected stale controls cannot send commands")
	api.connected = true
	client._connection_changed("隔离测试：已连接", true)
	client._refresh_clock()
	chain_action.pressed.emit()
	_check(api.commands.size() == 1, "Reconnection with a current row permits one fresh selection")
	api.connected = false
	client._connection_changed("隔离测试：选择中断线", false)
	_selection_snapshot(rows, "north", "hill")
	api.acknowledge("selectExpedition")
	_check(api.commands.size() == 1, "Selection acknowledgment cannot send recall across disconnection")
	api.connected = true
	client._connection_changed("隔离测试：重新连接", true)
	api.acknowledge("selectExpedition")
	_check(api.commands.size() == 1, "Reconnect cannot revive an already cancelled recall chain")
	api.commands.clear()

	# A retained control must consult the latest server array at activation.
	var removed: Dictionary = rows.pop_at(2)
	_snapshot(rows)
	chain_action.pressed.emit()
	_check(api.commands.is_empty() and not _visible_action(str(removed.id)), "A row removed by the server cannot execute its old descriptor")
	rows.append(removed)
	_snapshot(rows)
	client._march_action_buttons[str(removed.id)].pressed.emit()
	_check(api.commands.size() == 1, "Restored current row can start a new isolated selection")
	client._mode_changed("private")
	api.acknowledge("selectExpedition")
	_check(api.commands.size() == 1 and client._march_labels.is_empty() and client._march_action_buttons.is_empty(), "Identity change clears row controls and revokes a previous actor's pending recall")
	_check(client._view.is_empty(), "Identity change immediately removes old army names and deadlines")
	client.queue_free()
	await process_frame
	print("MARCH_LIST_CHECKS=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
