extends SceneTree

## Real lobby Controls, keyboard-sized layout and main identity handoff.
class LobbyProbe extends "res://src/lobby_api.gd":
	var sent: Array[Dictionary] = []
	func _send() -> void:
		sent.append({"path": _path, "body": _body_text})

class GameProbe extends "res://src/game_api.gd":
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

var checks: int = 0
var failures: int = 0
var _old_dir: Variant
var _old_name: Variant
var _test_dir: String

func _initialize() -> void:
	_old_dir = ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	_old_name = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	var name: String = "ThreeKingdomsLobbyUiTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", name)
	_test_dir = OS.get_user_data_dir()
	if not _test_dir.ends_with(name):
		push_error("Refusing room UI tests outside an isolated directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_test_dir)
	call_deferred("_run")

func _assert(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _buttons(node: Node, text: String) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button and (node as Button).text == text:
		result.append(node as Button)
	for child: Node in node.get_children():
		result.append_array(_buttons(child, text))
	return result

func _result(actor_id: String = "member_one", authority: String = "authority-one", room_id: String = "room_one") -> Dictionary:
	return {"ok": true, "protocol": 1, "room": {"id": room_id, "name": "青州攻防", "capacity": 8, "members": [{"id": actor_id, "name": "城主甲", "seat": 1, "team": "blue"}]}, "actor": {"id": actor_id, "name": "城主甲"}, "authorityId": authority, "accessToken": "a".repeat(64), "recoveryKey": "b".repeat(64), "inviteCode": "c".repeat(64)}

func _complete_lobby(api: LobbyProbe, code: int, data: Dictionary, transport_result: int = HTTPRequest.RESULT_SUCCESS) -> void:
	api._on_completed(transport_result, code, PackedStringArray(), JSON.stringify(data).to_utf8_buffer())

func _complete_game(api: GameProbe, data: Dictionary, code: int = 200) -> void:
	api._current = {"path": "health", "method": HTTPClient.METHOD_GET, "body": {}}
	api._queue.clear()
	api._on_completed(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(), JSON.stringify(data).to_utf8_buffer())

func _run() -> void:
	for width: int in [1280, 390]:
		await _test_viewport(width)
	_remove_test_dir(_test_dir)
	ProjectSettings.set_setting("application/config/use_custom_user_dir", _old_dir)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", _old_name)
	print("Godot lobby UI checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)

func _remove_test_dir(path: String) -> void:
	var folder: DirAccess = DirAccess.open(path)
	if folder == null:
		return
	for name: String in folder.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in folder.get_directories():
		_remove_test_dir(path.path_join(name))
	DirAccess.remove_absolute(path)

func _take_command(api: GameProbe) -> Dictionary:
	for index: int in range(api._queue.size()):
		if api._queue[index].path == "command":
			var request: Dictionary = api._queue[index].duplicate(true)
			api._queue.remove_at(index)
			api._current = request.duplicate(true)
			return request
	_assert(false, "Expected a real canonical dispatch request")
	return {}

func _test_dispatch_failure(client: ClientProbe, game: GameProbe) -> void:
	var view: Dictionary = {"generals": [{"id": "lin", "name": "可出征将", "busy": false, "governor": false}], "units": [{"id": "cavalry", "name": "轻骑兵", "available": 40}]}
	var shared: Dictionary = {"membership": {"alliance": "blue"}, "players": [{"id": "member_one", "name": "城主甲", "alliance": "blue", "home": {"x": 26, "y": 28}}, {"id": "member_enemy", "name": "城主乙", "alliance": "red", "home": {"x": 30, "y": 28}}], "marches": [], "reports": []}
	client._view = view
	game.shared_world = shared
	client._update_pvp()
	client._pvp.show_dispatch(shared.players[1])
	var form: KingdomPvpDialog = client._pvp
	var count: SpinBox = form._counts.cavalry
	count.get_line_edit().text = "8"
	form._send.pressed.emit()
	var rejected: Dictionary = _take_command(game)
	if rejected.is_empty():
		return
	_assert(form._form_error.text == "正在核定派遣…" and form._send.disabled, "Actual main dispatch waits for canonical confirmation")
	game._on_completed(HTTPRequest.RESULT_SUCCESS, 409, PackedStringArray(), JSON.stringify({"error": {"code": "REVISION_CONFLICT", "message": "其他设备已更新进度，请重读后再试"}}).to_utf8_buffer())
	_assert(form._form_error.text == "其他设备已更新进度，请重读后再试" and client._toast.text == form._form_error.text and not form._send.disabled, "A real 409 updates both the PvP form and main feedback, then restores allowed dispatch")
	_assert(count.value == 8 and not game._has_mutation() and not FileAccess.file_exists(game._journal_path(str(rejected.body.commandId))), "A rejected command preserves the draft and releases only its confirmed failed receipt")
	form._send.pressed.emit()
	var uncertain: Dictionary = _take_command(game)
	if uncertain.is_empty():
		return
	_assert(uncertain.body.commandId != rejected.body.commandId, "After a definite rejection a newly requested dispatch gets its own original ID")
	game._fail_transport("连接中断。可重连；未确认的操作会用原编号重试")
	_assert(form._form_error.text.contains("原编号") and form._send.disabled and not count.editable, "Transport uncertainty retains reconnect guidance inside the actual dispatch form")
	_assert(game._retry.body.commandId == uncertain.body.commandId and FileAccess.file_exists(game._journal_path(str(uncertain.body.commandId))), "Uncertain dispatch retains its original authoritative operation rather than generating another")
	form._send.pressed.emit()
	_assert(game._queue.is_empty() and game._retry.body.commandId == uncertain.body.commandId, "A stale disabled submit cannot enqueue a second army after an uncertain result")
	game.retry_last()
	var result: Dictionary = _result()
	var health: Dictionary = {"ok": true, "protocol": 1, "mode": "shared", "actor": result.actor, "authorityId": result.authorityId, "room": result.room}
	_complete_game(game, health)
	var replay: Dictionary = _take_command(game)
	if replay.is_empty():
		return
	_assert(JSON.parse_string(JSON.stringify(replay.body)) == JSON.parse_string(JSON.stringify(uncertain.body)) and form._send.disabled, "Same-account reconnect retries the original wire command while another dispatch stays disabled")
	var response: Dictionary = health.duplicate(true)
	response.merge({"revision": 1, "serverTime": 1800000000000, "state": {}, "view": view, "shared": shared}, true)
	game._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(response).to_utf8_buffer())
	_assert(form._target.is_empty() and form._form.get_child_count() == 0 and not game._has_mutation(), "A verified original acknowledgement clears its submitted form and uncertainty exactly once")

func _test_viewport(width: int) -> void:
	root.size = Vector2i(width, 844)
	var game: GameProbe = GameProbe.new()
	var client: ClientProbe = ClientProbe.new()
	client.api = game
	client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(client)
	await _settle()
	game._authority = "old-local"
	game.last_snapshot = {"view": {"city": {"name": "原私人城池"}}, "revision": 9}
	game.revision = 9
	client._resources.gold.text = "黄金 99,999 · 原账号"
	var lobby_api: LobbyProbe = LobbyProbe.new()
	client._lobby_api = lobby_api
	client.add_child(lobby_api)
	client._show_lobby()
	await _settle()
	var lobby: KingdomLobbyDialog = client._lobby
	_assert(lobby.visible and lobby.size.x <= width and lobby.position.x >= 0 and lobby.position.x + lobby.size.x <= width, "Lobby window fits within the %d px viewport" % width)
	_assert(lobby._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and lobby._content.get_combined_minimum_size().x <= lobby._scroll.size.x + 1, "Lobby content has no clipped horizontal overflow at %d px" % width)
	_assert(lobby._forms[0].visible and not lobby._forms[1].visible and not lobby._forms[2].visible, "Only one enrollment form is shown at a time")
	_assert(lobby._capacity.min_value == 1 and lobby._capacity.max_value == 8 and lobby._current.text.contains("私人试玩"), "Room size and current identity are visible without changing private mode")
	_assert(_buttons(client, "联机大厅").is_empty(), "Lobby does not add redundant room UI to the map contents")
	lobby._room_name.text = "青州攻防"
	lobby._create_name.text = "城主甲"
	lobby._capacity.get_line_edit().text = "8"
	lobby._submit.pressed.emit()
	_assert(lobby_api.sent.size() == 1 and int(JSON.parse_string(lobby_api.sent[0].body).capacity) == 8, "Create applies the raw capacity editor before serializing the request")
	_assert(lobby._submit.disabled and not lobby._create_name.editable and lobby._action.disabled, "In-flight enrollment disables form editing and repeated submissions")
	_complete_lobby(lobby_api, 0, {}, HTTPRequest.RESULT_CANT_CONNECT)
	_assert(lobby._retry.visible and lobby._cancel.visible and lobby._submit.disabled and not lobby._room_name.editable, "An uncertain registration offers original retry while locking new registrations")
	_assert(lobby._status.text.contains("保持客户端窗口开启") and lobby._status.text.contains("重试信息"), "Unconfirmed enrollment explains its live-window recovery limit")
	lobby._request_close()
	await _settle()
	_assert(lobby.visible and is_instance_valid(lobby._close_notice) and lobby._close_notice.visible and lobby._close_notice.size.x <= width, "Closing an unconfirmed enrollment presents a reachable lifetime notice at %d px" % width)
	lobby._close_notice.custom_action.emit(&"hide")
	await _settle()
	_assert(not lobby.visible and lobby_api.needs_retry, "Explicitly folding the lobby preserves the original live request")
	client._show_lobby()
	lobby._room_name.text = "不应替换的房间"
	lobby._submit.pressed.emit()
	_assert(lobby_api.sent.size() == 1, "A stale submit callback cannot replace the unconfirmed request")
	lobby._retry.pressed.emit()
	_assert(lobby_api.sent.size() == 2 and lobby_api.sent[1] == lobby_api.sent[0], "The actual retry button retains the original enrollment body")
	_complete_lobby(lobby_api, 200, _result())
	await _settle()
	_assert(lobby._result_box.visible and lobby._result_key.secret and lobby._result_key.text == "b".repeat(64), "A successful own enrollment shows a masked private recovery key")
	_assert(lobby._result_invite.text == "c".repeat(64) and lobby._result_room.text == "room_one", "Shareable invitation and private-seat recovery information are separate fields")
	_assert(game.actor.is_empty() and game.last_snapshot.view.city.name == "原私人城池", "Receiving a lobby response does not bypass canonical game authentication")
	_assert(lobby._content.get_combined_minimum_size().x <= lobby._scroll.size.x + 1 and lobby._scroll.scroll_vertical > 0, "The recovery result stays within narrow layout and is scrolled into view")
	_buttons(lobby, "显示 / 隐藏恢复密钥")[0].pressed.emit()
	_assert(not lobby._result_key.secret, "The private key is revealed only by an explicit user action")
	lobby.hide()
	_assert(lobby._result_key.secret, "Closing the lobby masks the private recovery key again")
	client._show_lobby()
	lobby._enter.pressed.emit()
	_assert(game.base_url == "http://127.0.0.1:17343/api" and game.token == "a".repeat(64) and game._expected_identity == {"actorId": "member_one", "authorityId": "authority-one", "roomId": "room_one"}, "Explicit entry passes the exact lobby identity into the canonical health handshake")
	_assert(lobby._enter.disabled and game.actor.is_empty(), "Entering locks the button while health authenticates; account is not assigned optimistically")
	var result: Dictionary = _result()
	var health: Dictionary = {"ok": true, "protocol": 1, "mode": "shared", "actor": result.actor, "authorityId": result.authorityId, "room": result.room}
	var wrong: Dictionary = health.duplicate(true)
	wrong.actor.id = "unexpected-member"
	_complete_game(game, wrong)
	_assert(not game.connected and game._authority == "old-local" and client._resources.gold.text.contains("原账号") and not lobby._enter.disabled, "A failed room handoff keeps the old private UI disconnected and permits identity retry")
	lobby._enter.pressed.emit()
	_complete_game(game, health)
	_assert(game.connected and game.actor.id == "member_one" and client._resources.gold.text == "黄金  —" and client._view.is_empty(), "Accepted room identity clears all previous private resource and view data")
	_assert(lobby._result_box.visible and lobby._result_key.text == "b".repeat(64) and lobby._enter.disabled and lobby._current.text.contains("青州攻防"), "Own recovery information remains available after successful authentication")
	client._show_pvp()
	_assert(client._pvp.title.contains("青州攻防") and client._pvp._message.text.contains("1 / 8") and not lobby.visible, "Room PvP displays actual room occupancy and hides the lobby")
	_test_dispatch_failure(client, game)
	client._tasks_dialog()
	_assert(_buttons(client._dialog, "联机大厅").size() == 1, "Narrow-screen transactions provide a reachable lobby entry")
	_buttons(client._dialog, "联机大厅")[0].pressed.emit()
	_assert(lobby.visible and not client._dialog.visible, "The transaction lobby action opens a single room popup")
	_buttons(lobby, "高级连接：地址与访问令牌")[0].pressed.emit()
	_assert(not lobby.visible and client._dialog.visible and client._dialog.title == "连接规则服务", "Advanced URL/token connection remains available without duplicate open windows")
	client._show_lobby("c".repeat(64))
	_assert(lobby._action.selected == 1 and lobby._invite.text == "c".repeat(64) and lobby._forms[1].visible, "A room invite selects and fills the dedicated join form")
	game.connect_to("http://127.0.0.1:17342", "d".repeat(64))
	_complete_game(game, {"ok": true, "protocol": 1, "mode": "shared", "actor": {"id": "player-1", "name": "演练青龙"}, "authorityId": "legacy-authority"})
	_assert(lobby._result.is_empty() and lobby._result_key.text.is_empty() and lobby_api.last_result.is_empty(), "Switching to another authenticated actor removes the previous actor's private recovery information")
	client._show_pvp()
	_assert(client._pvp._message.text.contains("四账号独立进度") and game.room.is_empty(), "Legacy four-account rehearsal keeps its existing PvP description")
	root.remove_child(client)
	client.queue_free()
	await _settle()
