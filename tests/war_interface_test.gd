extends SceneTree

## Production shell with isolated safe DTOs; no save, networking or consumption.
class ApiProbe extends "res://src/game_api.gd":
	var pending: bool = false
	var commands: Array[Dictionary] = []
	var quotes: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func _has_mutation() -> bool:
		return pending
	func command(type: String, args: Array = [], source: String = "") -> void:
		if connected and not pending:
			commands.append({"type": type, "args": args.duplicate(true), "sourceCity": source})
			pending = true
	func request_quote(kind: String, args: Array, request: String) -> void:
		quotes.append({"kind": kind, "args": args.duplicate(true), "requestId": request})

class ClientProbe extends "res://src/main.gd":
	func _ready() -> void:
		_smoke = true
		_initialize_inputs()
		theme = _make_theme()
		_build_shell()
		add_child(api)
		api.quote_received.connect(_receive_quote)
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
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceWarInterfaceTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	root.gui_embed_subwindows = true
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 6:
		await process_frame

func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var path: String = "res://production/qa/evidence/story-012/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	_check(root.get_texture().get_image().save_png(path + name + ".png") == OK, "Integrated UI fixture capture saved")

func _run() -> void:
	payload = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/godot-view.json"))
	payload.view.res.food = 123456
	payload.view.caps.food = 10000
	payload.view.rates.food = -2
	payload.view.generals = [{"id": "lin", "name": "林将军", "busy": false, "governor": false}]
	payload.view.units = [{"id": "archer", "name": "弓箭兵", "available": 20}, {"id": "scout", "name": "斥候", "available": 3}]
	payload.view.scouting = {"supported": true, "available": 3, "queueUsed": 0, "queueLimit": 2, "intelByNode": {}}
	var target: Dictionary = {"id": "field", "name": "河畔荒田", "x": 34, "y": 33, "level": 1, "hidden": false, "owned": false, "selectable": true, "army": {}}
	payload.view.nodes = [target]
	payload.view.marches = [{"id": "march-1", "label": "弓军", "status": "march", "arrive": Time.get_unix_time_from_system() * 1000 + 100000, "count": 20}, {"id": "station-1", "label": "驻守军", "status": "stationed", "count": 10}]
	client = ClientProbe.new()
	api = ApiProbe.new()
	api.connected = true
	client.api = api
	client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(client)
	client._receive_snapshot(payload)
	client._receive_world(payload.worldSample)
	for width: int in [1280, 800, 390]:
		root.size = Vector2i(width, 844)
		await _settle()
		_check(not client._sidebar_panel.visible and client._compact_objective_panel.visible, "Initial task rail is folded but objective stays reachable")
		_check(not client._detail_panel.visible, "Empty target never occupies a side column")
		_check(client._resource_grid.columns == 5, "Resources occupy one row")
		_check(client._shell_margin.get_combined_minimum_size().x <= width, "Shell has no forced horizontal overflow")
		_check(client._body.size.y >= root.size.y * 0.5, "Map body retains over half the viewport height")
		_check(client._activity_bar.is_visible_in_tree(), "Activity HUD remains visible on both screens")
		_check((client._nav.get_index() == client._shell_root.get_child_count() - 1) == (width == 390), "Phone navigation is last in shell; desktop is near top")
		for id: String in client._resource_buttons:
			_check(client._resource_buttons[id].size.y >= 44, "Resource details have touch targets")
			_check(client._resources[id].get_combined_minimum_size().y <= client._resource_buttons[id].size.y, "Both resource text lines fit inside the compact button")
		client._resource_buttons.food.grab_focus()
		client._resource_dialog("food")
		await _settle()
		_check(client._resource_detail_labels.food.text.contains("123456") and client._resource_detail_labels.food.text.contains("10000"), "Resource details use exact amount and capacity")
		_check(client._resource_detail_labels.food.text.contains("-120.0") and client._resource_detail_labels.food.text.contains("超仓"), "Net production and overflow remain explicit")
		var modal: AcceptDialog = client._dialog
		var label: Label = client._resource_detail_labels.food
		client._dialog.get_ok_button().grab_focus()
		payload.view.res.food += 1
		client._receive_snapshot(payload)
		_check(client._dialog == modal and client._resource_detail_labels.food == label, "Polling retains resource controls")
		_check(client._dialog.get_viewport().gui_get_focus_owner() == client._dialog.get_ok_button(), "Polling retains focus")
		api.connected = false
		client._connection_changed("断线", false)
		_check(client._resource_status.text.contains("最后收到"), "Disconnected details disclose stale snapshot")
		api.connected = true
		client._connection_changed("已连接", true)
		client._dialog.hide()
		await _settle()
		if width == 1280:
			client._toggle_task_sidebar()
			await _settle()
			_check(client._sidebar_panel.visible and not client._compact_objective_panel.visible, "Desktop task rail expands on request")
			client._toggle_task_sidebar()
			client._select_tile(target)
			await _settle()
			_check(client._detail_panel.visible, "Selected desktop target opens detail")
			var camera: Vector2 = client._map.camera_center
			var zoom: float = client._map.zoom
			client._dismiss_target()
			_check(target.get("id", "") == "field", "Closing selection does not mutate the safe target dictionary")
			_check(not client._detail_panel.visible and client._map.camera_center == camera and client._map.zoom == zoom, "Closing target preserves map camera")
		else:
			client._select_tile(target)
			_check(client._scouting.visible, "All screens without target sidebar open reachable unified target actions")
			client._scouting.hide()
			client._dismiss_target()
			client._toggle_task_sidebar()
			_check(client._dialog.title == "城池事务" and client._dialog.visible, "Phone task action opens reachable task hub")
			client._dialog.hide()
		await _settle()
		await _capture("war-shell-fixture-%d" % width)
		client._route_army_activity("stationed")
		_check(client._dialog.title == "驻扎部队" and client._dialog.get_children().size() > 0, "Stationed HUD opens filtered army window")
		client._dialog.hide()
		client._route_army_activity("reports")
		_check(client._page == "reports", "Report HUD opens report page")
		client._show_page("world")
		_check(api.commands.is_empty() and api.quotes.is_empty(), "Read-only HUD/resources/navigation never consume or preview")
		payload.view.res.food = 123456
	client._marches_dialog()
	var live_label: Label = client._march_labels["march-1"]
	var live_action: Button = client._march_action_buttons["march-1"]
	client._intel_server_offset = 60000
	payload.view.marches[0].status = "return"
	payload.view.marches[0].returnAt = client._intel_now() + 30000
	client._receive_snapshot(payload)
	client._intel_server_offset = 60000
	client._refresh_clock()
	_check(client._march_labels["march-1"] == live_label and live_label.text.contains("返城"), "Open normal army row updates phase without replacement")
	_check(not live_action.visible, "Return cannot retain stale recall action")
	payload.view.marches[0].returnAt = client._intel_now() - 1
	client._receive_snapshot(payload)
	client._intel_server_offset = 60000
	client._refresh_clock()
	_check(live_label.text.contains("待服务器结算"), "Army destination list shares corrected clock and honest expiry")
	client._dialog.hide()
	client._intel_server_offset = 0
	# Check production signal path, exact quote and command, then identity revocation.
	client._dispatch_dialog(target)
	await _settle()
	var flow: Variant = client._scouting
	flow._army_inputs.archer.get_line_edit().text = "20"
	flow._army_inputs.archer.get_line_edit().text_changed.emit("20")
	flow._march_preview.pressed.emit()
	_check(api.quotes.size() == 1 and api.quotes[0].kind == "march", "Main connects march preview to canonical quote API")
	if api.quotes.size() == 1:
		var request: Dictionary = api.quotes[0]
		var command: Dictionary = {"type": "dispatch", "args": request.args.duplicate(true), "sourceCity": "capital"}
		api.quote_received.emit({"requestId": request.requestId, "kind": "march", "sourceCity": "capital", "serverTime": Time.get_unix_time_from_system() * 1000, "quote": {"seconds": 25, "returnSeconds": 40, "foodCost": 137, "carry": 91, "reason": "", "command": command}})
		_check(not flow._march_confirm.disabled, "Production quote callback enables matching march")
		flow._march_confirm.pressed.emit()
		flow._march_confirm.pressed.emit()
		_check(api.commands.size() == 1 and api.commands[0] == command, "Main forwards the exact quoted march descriptor only once")
	client._show_scouting(target)
	_check(client._scouting == flow and flow._tabs.current_tab == 1, "Scout switch reuses the same production window")
	client._mode_changed("private")
	await _settle()
	_check(client._view.is_empty() and client._selected.is_empty() and not is_instance_valid(client._scouting), "Identity switch frees actor-derived dispatch controls")
	_check(client._resource_detail_labels.is_empty() and not client._activity_bar._has_context, "Identity switch clears resource and activity data immediately")
	client._resource_dialog("food")
	_check(client._resource_detail_labels.food.text.contains("等待") and not client._resource_detail_labels.food.text.contains("容量 0"), "Post-clear direct detail call keeps data unknown rather than inventing zero")
	for id: String in client._resources:
		_check(client._resources[id].text.contains("—") and client._resource_buttons[id].tooltip_text.is_empty() and client._resource_buttons[id].disabled, "Identity switch clears resource HUD and exact tooltip")
	client.queue_free()
	await process_frame
	print("WAR_INTERFACE_CHECKS=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
