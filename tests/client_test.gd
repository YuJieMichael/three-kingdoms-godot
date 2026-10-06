extends SceneTree

## Uses production UI/layout and pending-operation code with a transport probe.
## Only HTTP pumping is replaced: requests are inspected and real callbacks are
## delivered deterministically. No existing player data or local service is used.
class TransportProbe extends "res://src/game_api.gd":
	func _pump() -> void:
		pass


class ClientProbe extends "res://src/main.gd":
	func _ready() -> void:
		theme = _make_theme()
		_build_shell()
		add_child(api)
		api.snapshot_received.connect(_receive_snapshot)
		api.world_received.connect(_receive_world)
		api.status_changed.connect(_connection_changed)
		api.request_failed.connect(func(message: String) -> void: _pending_battle = false; _show_toast(message))
		api.command_completed.connect(_command_completed)
		_show_page("world")


var failures: int = 0
var checks: int = 0
var _old_custom_user_dir: Variant
var _old_custom_user_name: Variant
var _temporary_user_dir: String = ""
var _fixture: Dictionary = {}


func _initialize() -> void:
	_old_custom_user_dir = ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	_old_custom_user_name = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	var unique_name: String = "ThreeKingdomsClientTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", unique_name)
	_temporary_user_dir = OS.get_user_data_dir()
	if not _temporary_user_dir.ends_with(unique_name):
		push_error("Refusing client tests without a unique temporary user directory.")
		_restore_settings()
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_temporary_user_dir)
	call_deferred("_run")


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/godot-view.json"))
	if not parsed is Dictionary:
		_assert(false, "Canonical view fixture must parse before UI and command tests.")
		_finish()
		return
	_fixture = parsed
	await _test_client_layout_and_chaining()
	await _test_pending_reconnect()
	_finish()


func _assert(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _settle_layout() -> void:
	await process_frame
	await process_frame
	await process_frame


func _payload(revision_value: int, source_city: String = "capital") -> Dictionary:
	var result: Dictionary = _fixture.duplicate(true)
	result["revision"] = revision_value
	result["view"]["city"]["id"] = source_city
	return result


func _complete(api: TransportProbe, code: int, payload: Dictionary) -> void:
	api._on_completed(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(), JSON.stringify(payload).to_utf8_buffer())


func _take_request(api: TransportProbe, path: String) -> Dictionary:
	for index: int in range(api._queue.size()):
		if str(api._queue[index].get("path", "")) == path:
			var request: Dictionary = api._queue[index].duplicate(true)
			api._queue.remove_at(index)
			api._current = request
			return request
	_assert(false, "The client must queue the expected %s request." % path)
	return {}


func _find_mutation(api: TransportProbe) -> Dictionary:
	for request: Dictionary in api._queue:
		if str(request.get("path", "")) in ["command", "import"]:
			return request
	return {}


func _test_client_layout_and_chaining() -> void:
	var client: ClientProbe = ClientProbe.new()
	var api: TransportProbe = TransportProbe.new()
	client.api = api
	client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(client)
	await _test_desktop_short_window(client, "startup objective")
	var text_server: TextServer = TextServerManager.get_primary_interface()
	var coordinates: Dictionary = text_server.font_get_variation_coordinates(client.theme.default_font.get_rids()[0])
	var actual_weight: float = float(coordinates.get(text_server.name_to_tag("wght"), coordinates.get("weight", 0.0)))
	_assert(is_equal_approx(actual_weight, 500.0), "The actual rendering font must use medium weight instead of silently falling back to Thin 100.")
	client._receive_snapshot(_fixture)
	client._receive_world(_fixture.get("worldSample", {}))
	await _test_desktop_short_window(client, "fixture objective")
	for width: int in [1280, 390]:
		root.size = Vector2i(width, 844)
		await _settle_layout()
		var margin: Control = client.get_child(1)
		_assert(margin.get_combined_minimum_size().x <= float(width), "The %d px fixture shell must not force horizontal overflow." % width)
		_assert(client._body.size.x <= float(width - 32), "The %d px body must fit inside its outer margins." % width)
		_assert(client._resource_grid.columns == (3 if width == 390 else 5), "Resource columns must follow real viewport width.")
		_assert(client._sidebar_panel.visible == (width == 1280), "The desktop sidebar must collapse on the narrow viewport.")
		_assert(client._detail_panel.visible == (width == 1280), "Target details must collapse on the narrow viewport.")
		_assert(client._center.get_parent() is ScrollContainer, "The main center must have an actual scroll viewport on both screen sizes.")
		for page: String in ["city", "army", "generals", "reports", "world"]:
			client._show_page(page)
			await _settle_layout()
			if client._body.size.x > float(width - 32):
				print("CLIENT_LAYOUT_FAILURE page=", page, " viewport=", width, " body=", client._body.size, " center_min=", client._center.get_combined_minimum_size())
			_assert(client._body.size.x <= float(width - 32), "The %s page must not push the %d px body outside the viewport." % [page, width])
			if width == 390 and page == "army":
				await _test_army_scroll(client)
		if width == 390:
			var top: HBoxContainer = margin.get_child(0).get_child(0)
			var transactions_found: bool = false
			for child: Node in top.get_children():
				if child is Button and (child as Button).text == "事务":
					transactions_found = true
			_assert(transactions_found, "Narrow layouts must retain a reachable transactions entry.")
			client._tasks_dialog()
			await _settle_layout()
			var dialog_buttons: PackedStringArray = _button_labels(client._dialog)
			for required_label: String in ["领取已解锁礼包", "城外资源", "研究", "宝物与物资"]:
				_assert(dialog_buttons.has(required_label), "The mobile transactions menu must expose %s." % required_label)
			client._dialog.hide()
	var original_map: Variant = client._map
	original_map.focus_tile(36, 34)
	original_map._zoom_at(Vector2(120, 180), 1.12)
	var camera_before: Vector2 = original_map.camera_center
	var zoom_before: float = original_map.zoom
	var updated: Dictionary = _fixture.duplicate(true)
	updated["view"]["res"]["food"] = float(updated["view"]["res"]["food"]) + 250.0
	client._receive_snapshot(updated)
	client._receive_world(_fixture.get("worldSample", {}))
	_assert(client._map == original_map, "A resource/state refresh must reuse the active map Control.")
	_assert(client._map.camera_center.is_equal_approx(camera_before) and is_equal_approx(client._map.zoom, zoom_before), "State/world refresh must preserve the map camera and zoom.")
	api.connected = true
	api._authority = "authority-fixture-a"
	api.revision = 6
	api.last_snapshot = _payload(6, "county-fixture")
	api._current = {"path": "command", "method": HTTPClient.METHOD_POST, "body": {"type": "selectExpedition", "args": ["field"], "commandId": "client-test-select", "expectedRevision": 6, "sourceCity": "county-fixture"}}
	api._save_pending(api._current)
	client._pending_battle = true
	_complete(api, 200, _payload(7, "county-fixture"))
	var chained: Dictionary = _find_mutation(api)
	_assert(chained.get("body", {}).get("type", "") == "startBattle", "Selecting an arrived expedition must chain the production startBattle action.")
	_assert(int(chained.get("body", {}).get("expectedRevision", -1)) == 7, "The chained action must use the newly acknowledged revision.")
	_assert(chained.get("body", {}).get("sourceCity", "") == "county-fixture", "The chained action must retain the expedition source city.")
	var pending: Variant = JSON.parse_string(FileAccess.get_file_as_string(KingdomApi.PENDING_PATH))
	_assert(pending is Dictionary and pending.get("request", {}).get("body", {}).get("type", "") == "startBattle", "Acknowledging the first action must not erase the chained action's pending record.")
	_take_request(api, "command")
	_complete(api, 200, _payload(8, "county-fixture"))
	_assert(not FileAccess.file_exists(KingdomApi.PENDING_PATH), "A confirmed chained action must clear its durable pending record.")
	root.remove_child(client)
	client.queue_free()
	await process_frame


func _button_labels(node: Node) -> PackedStringArray:
	var result: PackedStringArray = []
	if node is Button:
		result.append((node as Button).text)
	for child: Node in node.get_children():
		result.append_array(_button_labels(child))
	return result


func _test_army_scroll(client: ClientProbe) -> void:
	var center_scroll: ScrollContainer = client._center.get_parent() as ScrollContainer
	if center_scroll == null:
		return
	_assert(center_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED, "The army center must permit vertical scrolling on the 390 px viewport.")
	var targets: Array[Button] = []
	for child: Node in client._center.get_children():
		if child is Button and (child as Button).text in ["训练与驻军", "行军与驻扎部队"]:
			targets.append(child as Button)
	_assert(targets.size() == 2, "The production army page must include both training and marching actions.")
	center_scroll.scroll_vertical = 0
	await _settle_layout()
	var scrollbar: VScrollBar = center_scroll.get_v_scroll_bar()
	_assert(scrollbar.max_value > scrollbar.page, "The 390 px army fixture must create a real scrollable range below its battle panel.")
	if targets.size() == 2:
		var viewport_rect: Rect2 = center_scroll.get_global_rect()
		_assert(not viewport_rect.has_point(targets[1].get_global_rect().get_center()), "The final army action must initially require scrolling in this narrow fixture.")
		center_scroll.scroll_vertical = ceili(scrollbar.max_value)
		await _settle_layout()
		viewport_rect = center_scroll.get_global_rect()
		for button: Button in targets:
			var button_rect: Rect2 = button.get_global_rect()
			_assert(viewport_rect.has_point(button_rect.get_center()) and button_rect.end.y <= viewport_rect.end.y + 1.0, "Scrolling must bring %s into the visible army viewport." % button.text)


func _test_desktop_short_window(client: ClientProbe, scenario: String) -> void:
	root.size = Vector2i(1280, 720)
	await _settle_layout()
	var margin: Control = client.get_child(1)
	var visible_height: float = root.get_visible_rect().size.y
	_assert(is_equal_approx(visible_height, 720.0), "The short desktop check must use an actual 720 px logical viewport.")
	_assert(margin.get_combined_minimum_size().y <= visible_height, "The %s desktop shell minimum height must fit 1280×720." % scenario)
	var footer_rect: Rect2 = client._toast.get_global_rect()
	_assert(footer_rect.position.y >= 0.0 and footer_rect.end.y <= visible_height + 1.0, "The %s footer must remain completely inside the short desktop viewport." % scenario)
	var sidebar_scroll: ScrollContainer = client._side.get_parent() as ScrollContainer
	_assert(sidebar_scroll != null, "The %s sidebar must have an actual scroll viewport." % scenario)
	if sidebar_scroll == null:
		return
	_assert(sidebar_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED, "The %s sidebar must allow vertical scrolling." % scenario)
	var scrollbar: VScrollBar = sidebar_scroll.get_v_scroll_bar()
	_assert(scrollbar.max_value > scrollbar.page, "The %s sidebar fixture must produce a real scroll range instead of expanding the outer shell." % scenario)
	sidebar_scroll.scroll_vertical = ceili(scrollbar.max_value)
	await _settle_layout()
	_assert(sidebar_scroll.get_global_rect().has_point(client._status.get_global_rect().get_center()), "The %s connection status must become reachable by scrolling the sidebar." % scenario)


func _test_pending_reconnect() -> void:
	var api: TransportProbe = TransportProbe.new()
	root.add_child(api)
	api.connected = true
	api._authority = "authority-original"
	api.revision = 11
	api.last_snapshot = _payload(11)
	api.command("train", ["archer", 20])
	var original: Dictionary = _take_request(api, "command").duplicate(true)
	var original_id: String = str(original.get("body", {}).get("commandId", ""))
	_assert(not original_id.is_empty() and FileAccess.file_exists(KingdomApi.PENDING_PATH), "A mutation must persist its operation ID before transport.")
	api._fail_transport("Test: response was lost after send.")
	_assert(api._retry.get("body", {}).get("commandId", "") == original_id, "A lost response must retain the exact original operation ID.")
	root.remove_child(api)
	api.queue_free()
	await process_frame
	api = TransportProbe.new()
	root.add_child(api)
	_assert(api._retry.get("body", {}).get("commandId", "") == original_id and api._pending_authority == "authority-original", "A new client process must recover its pending operation and authority from the isolated user directory.")
	api.connect_to("http://127.0.0.1:9999", "fixture-token")
	_assert(api._retry.get("body", {}).get("commandId", "") == original_id, "Regular reconnect must preserve the unconfirmed operation.")
	_take_request(api, "health")
	_complete(api, 200, {"ok": true, "authorityId": "authority-other"})
	_assert(_find_mutation(api).is_empty(), "A different authority must never replay an operation belonging to another save.")
	_assert(not api._retry.is_empty() and FileAccess.file_exists(KingdomApi.PENDING_PATH), "Authority mismatch must retain the original operation for recovery.")
	api.connect_to("http://127.0.0.1:9998", "fixture-token")
	_take_request(api, "health")
	_complete(api, 200, {"ok": true, "authorityId": "authority-original"})
	var replay: Dictionary = _find_mutation(api)
	_assert(replay.get("body", {}).get("commandId", "") == original_id, "Matching authority health must replay the original ID.")
	var wire_original: Variant = JSON.parse_string(JSON.stringify(original.get("body", {})))
	var wire_replay: Variant = JSON.parse_string(JSON.stringify(replay.get("body", {})))
	_assert(wire_replay == wire_original, "Replay must preserve all original args, source city and revision after JSON numeric normalization.")
	_take_request(api, "command")
	_complete(api, 200, _payload(12))
	_assert(api._retry.is_empty() and api._pending_authority.is_empty(), "A successful replay must clear retry state.")
	_assert(not FileAccess.file_exists(KingdomApi.PENDING_PATH), "A successful replay must delete only the isolated pending file.")
	_assert(api.revision == 12, "A successful replay must take the authoritative acknowledged revision.")
	api._queue.clear()
	api._current = {"path": "command", "method": HTTPClient.METHOD_POST, "body": {"type": "train", "commandId": "client-test-cas", "expectedRevision": 12}}
	api._save_pending(api._current)
	_complete(api, 409, {"error": {"code": "REVISION_CONFLICT", "message": "refresh required"}, "revision": 13})
	_assert(not FileAccess.file_exists(KingdomApi.PENDING_PATH) and _find_mutation(api).is_empty(), "A definitive CAS rejection must not replay a rejected mutation.")
	var state_found: bool = false
	for request: Dictionary in api._queue:
		state_found = state_found or request.get("path", "") == "state"
	_assert(state_found, "A CAS rejection must request the fresh authoritative state.")
	api._queue.clear()
	api._current.clear()
	api.connected = true
	api._authority = "authority-original"
	api.command("train", ["archer", 10])
	var in_flight: Dictionary = _take_request(api, "command").duplicate(true)
	var in_flight_id: String = str(in_flight.get("body", {}).get("commandId", ""))
	api.connect_to("http://127.0.0.1:9998", "fixture-token")
	_take_request(api, "health")
	_complete(api, 200, {"ok": true, "authorityId": "authority-original"})
	_assert(_find_mutation(api).get("body", {}).get("commandId", "") == in_flight_id, "Reconnect during an in-flight mutation must still replay its original operation ID.")
	api._queue.clear()
	api._current = in_flight.duplicate(true)
	_complete(api, 401, {"error": {"code": "UNAUTHORIZED", "message": "Token changed"}})
	_assert(FileAccess.file_exists(KingdomApi.PENDING_PATH) and api._retry.get("body", {}).get("commandId", "") == in_flight_id, "An authentication failure cannot discard an operation whose earlier result is still unconfirmed.")
	api._clear_pending()
	api._queue.clear()
	api._current = {"path": "state", "method": HTTPClient.METHOD_GET, "body": {}}
	api.connected = true
	api.command("train", ["archer", 5])
	var queued_id: String = str(_find_mutation(api).get("body", {}).get("commandId", ""))
	api.connect_to("http://127.0.0.1:9998", "fixture-token")
	_take_request(api, "health")
	_complete(api, 200, {"ok": true, "authorityId": "authority-original"})
	_assert(_find_mutation(api).get("body", {}).get("commandId", "") == queued_id, "Reconnect during a state fetch must retain the mutation queued behind it.")
	api._clear_pending()
	root.remove_child(api)
	api.queue_free()
	await process_frame


func _restore_settings() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", _old_custom_user_dir)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", _old_custom_user_name)


func _finish() -> void:
	var pending_path: String = _temporary_user_dir.path_join("pending-command.json")
	if FileAccess.file_exists(pending_path):
		DirAccess.remove_absolute(pending_path)
	DirAccess.remove_absolute(_temporary_user_dir)
	_restore_settings()
	print("Godot client checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)
