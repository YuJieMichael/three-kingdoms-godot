extends SceneTree

class LobbyProbe extends "res://src/lobby_api.gd":
	var sent: Array[Dictionary] = []
	var accounts: Array[Dictionary] = []
	func _send() -> void:
		sent.append({"path": _path, "body": _body_text, "headers": _account_headers(_enrollment_account_id, false)})
	func _send_account(method: HTTPClient.Method, path: String, body: Dictionary = {}, session_override: String = "", expected_override: String = "") -> bool:
		if account_busy:
			return false
		account_busy = true
		accounts.append({"path": path, "body": body.duplicate(true), "session": session_override if not session_override.is_empty() else account_session, "method": method, "expected": expected_override if path == "/auth/logout" else "" if path == "/auth/login" else str(account_user.get("id", ""))})
		account_status.emit("正在核对账号服务…", true)
		return true

class GameProbe extends "res://src/game_api.gd":
	func _pump() -> void:
		pass

class ClientProbe extends "res://src/main.gd":
	func _new_lobby_service() -> KingdomLobbyApi:
		return LobbyProbe.new()
	func _ready() -> void:
		theme = _make_theme()
		_build_shell()
		add_child(api)
		api.snapshot_received.connect(_receive_snapshot)
		api.world_received.connect(_receive_world)
		api.status_changed.connect(_connection_changed)
		api.request_failed.connect(_request_failed)
		api.mode_changed.connect(_mode_changed)
		_show_page("world")

var checks: int = 0
var failures: int = 0
var _test_dir: String
var _old_dir: Variant
var _old_name: Variant

func _initialize() -> void:
	_old_dir = ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	_old_name = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	var name: String = "ThreeKingdomsCloudUiTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", name)
	_test_dir = OS.get_user_data_dir()
	if not _test_dir.ends_with(name):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_test_dir)
	call_deferred("_run")

func _assert(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _member() -> Dictionary:
	return {"ok": true, "protocol": 1, "room": {"id": "room_cloud", "name": "在线攻防", "capacity": 2, "members": [{"id": "member_cloud", "name": "云城主", "seat": 1, "team": "blue"}]}, "actor": {"id": "member_cloud", "name": "云城主"}, "authorityId": "authority-cloud", "accessToken": "a".repeat(64), "recoveryKey": "b".repeat(64), "inviteCode": "c".repeat(64)}

func _complete(api: LobbyProbe, path: String, payload: Variant, code: int = 200) -> void:
	api._on_account_completed(path, HTTPRequest.RESULT_SUCCESS, code, JSON.stringify(payload).to_utf8_buffer())

func _run() -> void:
	for width: int in [1280, 390]:
		await _test_viewport(width)
	_assert(DirAccess.get_files_at(_test_dir).is_empty(), "Native cloud UI never creates account/password/key files")
	DirAccess.remove_absolute(_test_dir)
	ProjectSettings.set_setting("application/config/use_custom_user_dir", _old_dir)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", _old_name)
	print("Godot cloud lobby UI checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)

func _test_viewport(width: int) -> void:
	root.size = Vector2i(width, 844)
	var game: GameProbe = GameProbe.new()
	var client: ClientProbe = ClientProbe.new()
	client.api = game
	client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(client)
	await _settle()
	game._authority = "private-old"
	game.last_snapshot = {"view": {"city": {"name": "旧私人城池"}}}
	client._resources.gold.text = "黄金 99,999 · 原私人"
	client._show_lobby("", "https://game.example.test")
	await _settle()
	var lobby: KingdomLobbyDialog = client._lobby
	var service: LobbyProbe = client._lobby_api as LobbyProbe
	_assert(lobby.visible and lobby.size.x <= width and lobby.position.x >= 0 and lobby.position.x + lobby.size.x <= width, "Actual native cloud lobby fits %d px viewport" % width)
	_assert(service.accounts[-1].path == "/auth/config", "Opening remote native lobby checks advertised account capability")
	_complete(service, "/auth/config", {"enabled": true})
	_complete(service, "/auth/me", {}, 401)
	await _settle()
	_assert(lobby._auth_box.visible and lobby._email.visible and lobby._password.secret and lobby._login.visible and not lobby._logout.visible, "Cloud initial screen clearly requests private account login")
	_assert(lobby._action.is_item_disabled(2) and lobby._submit.disabled and not lobby._forms[2].visible, "Cloud offers no recovery-key bypass before login")
	_assert(lobby._content.get_combined_minimum_size().x <= lobby._scroll.size.x + 1, "Cloud login has no horizontal clipping at %d px" % width)
	_assert(game.last_snapshot.view.city.name == "旧私人城池", "Failed account check leaves previously selected private city until explicit account transition")
	lobby._email.text = "member@example.test"
	lobby._password.text = "private-test-password"
	lobby._login.pressed.emit()
	_assert(lobby._password.text.is_empty() and lobby._login.disabled and not lobby._email.editable, "Login immediately clears password UI and disables duplicate account requests")
	_assert(service.accounts[-1].body == {"email": "member@example.test", "password": "private-test-password"}, "Native form passes credentials only to dedicated account transport")
	_complete(service, "/auth/login", {"ok": true, "sessionToken": "short", "user": {"id": "account-one", "email": "member@example.test"}})
	_assert(service.account_user.is_empty() and lobby._login.visible and lobby._status.text.contains("不完整"), "Corrupt login keeps form usable without adopting account")
	lobby._password.text = "private-test-password"
	lobby._login.pressed.emit()
	_complete(service, "/auth/login", {"ok": true, "sessionToken": "d".repeat(64), "user": {"id": "account-one", "email": "member@example.test"}})
	_assert(service.accounts[-1].path == "/lobby/mine" and lobby._logout.visible and not lobby._password.visible and not lobby._login.visible, "Successful account login automatically fetches rooms and removes password entry")
	var member: Dictionary = _member()
	_complete(service, "/lobby/mine", {"ok": true, "rooms": [{"room": member.room, "seat": 1, "actor": member.actor, "authorityId": member.authorityId}]})
	await _settle()
	_assert(lobby._account_label.text.contains("member@example.test") and not lobby._submit.disabled, "Verified own account identity is visible and room operations unlock")
	var resume_button: Button = lobby._rooms_box.get_child(1) as Button
	_assert(resume_button != null and resume_button.text.contains("云城主"), "Own occupied-room button is shown after login")
	resume_button.pressed.emit()
	_assert(service.sent[-1].path == "account-resume" and JSON.parse_string(service.sent[-1].body) == {"roomId": "room_cloud"}, "Actual room button restores account-bound seat without key or actor body")
	service._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(member).to_utf8_buffer())
	await _settle()
	_assert(lobby._result_box.visible and lobby._result_key.text.is_empty() and not lobby._result_key.visible, "Cloud result never exposes recovery key supplied by legacy-shaped server response")
	for control: Control in lobby._key_controls:
		_assert(not control.visible, "Every key reveal/copy control is hidden in cloud")
	_assert(lobby._enter.text == "进入自己的房间" and lobby._result_hint.text.contains("绑定账号"), "Cloud result explains account restore instead of asking to save a key")
	_assert(game.actor.is_empty() and game.account_session.is_empty(), "Lobby result alone cannot bypass canonical health identity handshake")
	lobby._enter.pressed.emit()
	_assert(game._request_headers().has("X-Expected-Account: account-one"), "Actual main cloud handoff binds subsequent game requests to verified account")
	_assert(game.account_session == "d".repeat(64) and game.token == "a".repeat(64) and game._expected_identity.roomId == "room_cloud", "Main passes own RAM session alongside room token and expected identity")
	var health: Dictionary = {"ok": true, "protocol": 1, "mode": "shared", "actor": member.actor, "authorityId": member.authorityId, "room": member.room}
	game._queue.clear()
	game._current = {"path": "health", "method": HTTPClient.METHOD_GET, "body": {}}
	game._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(health).to_utf8_buffer())
	_assert(game.connected and lobby._enter.disabled and lobby._current.text.contains("云城主"), "Canonical verified own identity completes actual UI handoff")
	client._resources.gold.text = "黄金 999,999 · 云账号"
	client._view = {"city": {"name": "云城主城池"}}
	game.last_snapshot = {"view": client._view.duplicate(true)}
	lobby._logout.pressed.emit()
	_assert(service.accounts[-1].expected == "account-one", "Actual logout button keeps prior account precondition after clearing its controls")
	await _settle()
	_assert(not game.connected and game.account_session.is_empty() and game.token.is_empty() and game.last_snapshot.is_empty(), "Actual logout button immediately stops canonical game connection")
	_assert(client._view.is_empty() and client._resources.gold.text == "黄金  —" and client._objective_button.disabled, "Logout clears previous account-derived main UI even without replacement snapshot")
	_assert(service.account_user.is_empty() and lobby._result.is_empty() and lobby._rooms_box.get_child_count() == 2 and not lobby._logout.visible and lobby._login.visible, "Logout removes own room result/list and returns to login screen")
	_complete(service, "/auth/logout", {"ok": true})
	_assert(lobby._status.text.contains("已退出") and game.actor.is_empty(), "Remote confirmation reports safe signed-out status without resurrecting identity")
	_assert(lobby._content.get_combined_minimum_size().x <= lobby._scroll.size.x + 1, "Post-logout cloud layout remains reachable at %d px" % width)
	root.remove_child(client)
	client.queue_free()
	await _settle()
