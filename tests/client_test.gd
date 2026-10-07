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
		api.request_failed.connect(_request_failed)
		api.command_completed.connect(_command_completed)
		api.mode_changed.connect(_mode_changed)
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
	await _test_identity_switch_private_ui()
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
		_assert(client._body.size.x <= float(width - (16 if width == 390 else 24)), "The %d px body must fit inside its outer margins." % width)
		_assert(client._resource_grid.columns == 5, "Resource columns must follow real viewport width.")
		_assert(not client._sidebar_panel.visible, "The desktop sidebar must collapse on the narrow viewport.")
		_assert(not client._detail_panel.visible, "Target details must collapse on the narrow viewport.")
		_assert(client._center.get_parent() is ScrollContainer, "The main center must have an actual scroll viewport on both screen sizes.")
		for page: String in ["city", "army", "generals", "reports", "world"]:
			client._show_page(page)
			await _settle_layout()
			if client._body.size.x > float(width - (16 if width == 390 else 24)):
				print("CLIENT_LAYOUT_FAILURE page=", page, " viewport=", width, " body=", client._body.size, " center_min=", client._center.get_combined_minimum_size())
			_assert(client._body.size.x <= float(width - (16 if width == 390 else 24)), "The %s page must not push the %d px body outside the viewport." % [page, width])
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
	client._sidebar_expanded = true
	client._adapt_layout()
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
	_assert(sidebar_scroll.get_global_rect().has_point(client._status.get_global_rect().get_center()), "The %s connection status must become reachable by scrolling the expanded sidebar." % scenario)
	client._sidebar_expanded = false
	client._adapt_layout()


func _identity_health(mode: String, authority: String, actor_id: String) -> Dictionary:
	return {"ok": true, "protocol": 1, "mode": mode, "authorityId": authority, "actor": {"id": actor_id, "name": "甲私城主" if authority == "authority-a" and actor_id == "actor-a" else "乙城主"}}


func _private_ui_payload(health: Dictionary) -> Dictionary:
	var payload: Dictionary = _payload(23)
	for key: String in ["mode", "authorityId", "actor"]:
		payload[key] = health[key]
	var view: Dictionary = payload.view
	var resource_index: int = 0
	for id: String in view.res:
		view.res[id] = 9381 + resource_index
		view.caps[id] = 9000
		resource_index += 1
	view.city.name = "甲私城池"
	view.objective = {"title": "甲私目标", "description": "甲私目标说明", "reward": {"gold": 9386}, "ready": true, "action": "claimMission"}
	view.generals[0].name = "甲私将领"
	view.units[0].name = "甲私兵种"
	view.queues.build = [{"id": "甲私工事", "level": 2, "end": Time.get_unix_time_from_system() * 1000.0 + 60000.0}]
	view.marches = [{"id": "private-march", "label": "甲私行军", "status": "stationed", "count": 7}]
	view.nodes.append({"id": "private-battle", "name": "甲私战场"})
	view.battle = {"node": "private-battle", "round": 1, "player": [], "enemy": [], "log": ["甲私战斗记录"]}
	view.reports = [{"node": "private-battle", "won": true, "round": 1, "lost": {str(view.units[0].id): 7}}]
	payload.state.banner = "甲私存档"
	payload.shared = {"players": [{"id": "actor-a", "name": "甲私城主", "home": {"x": 8, "y": 12}}], "marches": [], "reports": []}
	return payload


func _ui_text(node: Node) -> String:
	# Include hidden Controls: reopening a cached dialog or widening the window
	# must not expose data left behind by the previous authenticated identity.
	var text: String = ""
	if node is Label or node is Button or node is RichTextLabel or node is TextEdit or node is LineEdit:
		text = str(node.text) + "\n"
	for child: Node in node.get_children():
		text += _ui_text(child)
	return text


func _test_identity_switch_private_ui() -> void:
	var settings: KingdomInputSettings = preload("res://src/input_settings.gd").new()
	settings.initialize()
	var shortcut: InputEventKey = InputEventKey.new()
	shortcut.physical_keycode = KEY_F6
	_assert(settings.rebind("tk_page_reports", shortcut).is_empty(), "The identity regression must create a real local key binding in its isolated user directory.")
	var binding_before: String = settings.binding_text("tk_page_reports")
	var scenarios: Array[Dictionary] = [
		{"mode": "local", "next_mode": "local", "next_authority": "authority-b", "next_actor": ""},
		{"mode": "shared", "next_mode": "shared", "next_authority": "authority-a", "next_actor": "actor-b"},
		{"mode": "shared", "next_mode": "shared", "next_authority": "authority-b", "next_actor": "actor-a"},
		{"mode": "local", "next_mode": "shared", "next_authority": "authority-b", "next_actor": "actor-b"},
	]
	for width: int in [1280, 390]:
		root.size = Vector2i(width, 844)
		for scenario: Dictionary in scenarios:
			var client: ClientProbe = ClientProbe.new()
			var api: TransportProbe = TransportProbe.new()
			client.api = api
			client.input_settings = settings
			client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			root.add_child(client)
			var health_a: Dictionary = _identity_health(scenario.mode, "authority-a", "actor-a" if scenario.mode == "shared" else "")
			api.connect_to("http://127.0.0.1:9999", "token-a")
			_take_request(api, "health")
			_complete(api, 200, health_a)
			_take_request(api, "state")
			var private_payload: Dictionary = _private_ui_payload(health_a)
			_complete(api, 200, private_payload)
			var world_a: Dictionary = _fixture.worldSample.duplicate(true)
			for key: String in ["mode", "authorityId", "actor"]:
				world_a[key] = health_a[key]
			_take_request(api, "world")
			_complete(api, 200, world_a)
			client._show_page("city")
			_assert(client._city._view.city.name == "甲私城池", "A's private city must reach the production canvas before switching identity.")
			client._show_page("generals")
			_assert(_ui_text(client._center).contains("甲私将领"), "A's private general must render before switching identity.")
			client._show_page("reports")
			_assert(_ui_text(client._center).contains("甲私战场"), "A's private report must render before switching identity.")
			client._tasks_dialog()
			_assert(_ui_text(client._dialog).contains("共享攻防演练" if scenario.mode == "shared" else "甲私目标说明"), "The task entry must match A's current private or shared objective before switching identity.")
			client._show_management("inn")
			if scenario.mode == "shared":
				client._show_pvp()
			client._report_dialog(private_payload.view.reports[0])
			client._show_page("army")
			await _settle_layout()
			client._marches_dialog()
			_assert(_ui_text(client._battle).contains("甲私战斗记录") and _ui_text(client._dialog).contains("甲私行军"), "A's private battle and marching army must render before switching identity.")
			_assert(str(client._resources.food.text).contains("9381") and client._resources.food.modulate != Color.WHITE, "A's private resource amount and over-cap styling must render before switching identity.")
			if scenario.mode == "local":
				_assert(client._objective_title.text == "甲私目标" and client._objective_button.text == "领取奖励", "A's private sidebar goal must render before switching authority.")
			api.connect_to("http://127.0.0.1:9999", "rejected-token")
			_take_request(api, "health")
			_complete(api, 401, {"error": {"message": "unauthorized"}})
			_assert(not api.connected and str(api.last_snapshot.get("authorityId", "")) == "authority-a" and str(client._resources.food.text).contains("9381"), "Rejected authentication must remain disconnected and retain the original authenticated snapshot under the existing reconnect contract.")
			client._show_toast("甲私目标消息")
			var health_b: Dictionary = _identity_health(scenario.next_mode, scenario.next_authority, scenario.next_actor)
			api.connect_to("http://127.0.0.1:9999", "token-b")
			_take_request(api, "health")
			_complete(api, 200, health_b)
			_assert(client._view.is_empty() and client._state.is_empty() and client._world.is_empty() and client._selected.is_empty(), "Accepted identity or authority changes must immediately discard A's private data, before the replacement state response.")
			_assert(not _ui_text(client).contains("甲私"), "Accepted replacement health must clear A's private Controls and toast immediately, without relying on a state response.")
			_take_request(api, "state")
			_complete(api, 503, {"error": {"message": "state unavailable"}})
			await _settle_layout()
			var old_resource_visible: bool = false
			var styles_reset: bool = true
			for label: Label in client._resources.values():
				old_resource_visible = old_resource_visible or label.text.contains("9000")
				for old_amount: int in range(9381, 9386):
					old_resource_visible = old_resource_visible or label.text.contains(str(old_amount))
				styles_reset = styles_reset and label.modulate == Color.WHITE
			_assert(not old_resource_visible and styles_reset, "The %d px resource bar must discard every A amount, cap and over-cap highlight when B's state fails." % width)
			_assert(not _ui_text(client).contains("甲私") and not client._objective_text.text.contains("9386") and client._objective_button.disabled, "The %d px shell, sidebar and cached dialogs must retain no A private goal, city, army, report or reward after the failed refresh." % width)
			_assert(client._page == "army" and client.input_settings == settings and settings.binding_text("tk_page_reports") == binding_before, "Identity clearing must preserve local page selection and customized input settings.")
			_assert(not client._visible_popup(client), "Identity changes must close A's private dialogs before the replacement snapshot arrives.")
			for page: String in ["city", "army", "generals", "reports", "world"]:
				client._show_page(page)
				await _settle_layout()
				_assert(not _ui_text(client).contains("甲私"), "Reopening the %s page at %d px after the failed identity refresh must not show A's private data." % [page, width])
			client._tasks_dialog()
			await _settle_layout()
			_assert(not _ui_text(client._dialog).contains("甲私"), "The narrow-layout task menu must open from empty data after identity change.")
			client._dialog.hide()
			api.connect_to("http://127.0.0.1:9999", "token-b")
			_take_request(api, "health")
			_complete(api, 200, health_b)
			_take_request(api, "state")
			var payload_b: Dictionary = _payload(24)
			for key: String in ["mode", "authorityId", "actor"]:
				payload_b[key] = health_b[key]
			payload_b.view.res.food = 3210
			payload_b.view.city.name = "乙城池"
			payload_b.view.objective.title = "乙目标"
			_complete(api, 200, payload_b)
			client._tasks_dialog()
			await _settle_layout()
			_assert(client._resources.food.text.contains("3210") and not client._objective_button.disabled and _ui_text(client._dialog).contains("共享攻防演练" if scenario.next_mode == "shared" else "乙目标") and not _ui_text(client).contains("甲私"), "A successful later B refresh must replace placeholders and re-enable goals without restoring A's data.")
			root.remove_child(client)
			client.queue_free()
			await process_frame


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
	var input_path: String = _temporary_user_dir.path_join("input-settings.cfg")
	if FileAccess.file_exists(input_path):
		DirAccess.remove_absolute(input_path)
	DirAccess.remove_absolute(_temporary_user_dir)
	_restore_settings()
	print("Godot client checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)
