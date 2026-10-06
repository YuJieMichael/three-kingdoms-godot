extends SceneTree

# Real account state machine and canonical client; only HTTP transport is replaced.
class LobbyProbe extends "res://src/lobby_api.gd":
	var sent: Array[Dictionary] = []
	var accounts: Array[Dictionary] = []
	func _send() -> void:
		sent.append({"path": _path, "body": _body_text, "headers": _account_headers(_enrollment_account_id, false)})
	func _send_account(method: HTTPClient.Method, path: String, body: Dictionary = {}, session_override: String = "", expected_override: String = "") -> bool:
		if account_busy:
			return false
		account_busy = true
		accounts.append({"method": method, "path": path, "body": body.duplicate(true), "session": session_override if not session_override.is_empty() else account_session, "expected": expected_override if path == "/auth/logout" else "" if path == "/auth/login" else str(account_user.get("id", ""))})
		account_status.emit("正在核对账号服务…", true)
		return true

class GameProbe extends "res://src/game_api.gd":
	func _pump() -> void:
		pass

var checks: int = 0
var failures: int = 0
var _test_dir: String
var _old_dir: Variant
var _old_name: Variant

func _initialize() -> void:
	_old_dir = ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	_old_name = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	var name: String = "ThreeKingdomsCloudApiTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
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

func _session() -> Dictionary:
	return {"ok": true, "protocol": 1, "room": {"id": "room_cloud", "name": "在线攻防", "capacity": 2, "members": [{"id": "member_cloud", "name": "云城主", "seat": 1, "team": "blue"}]}, "actor": {"id": "member_cloud", "name": "云城主"}, "authorityId": "authority-cloud", "accessToken": "a".repeat(64), "recoveryKey": "b".repeat(64), "inviteCode": "c".repeat(64)}

func _account_complete(api: LobbyProbe, path: String, code: int, payload: Variant, transport: int = HTTPRequest.RESULT_SUCCESS) -> void:
	api._on_account_completed(path, transport, code, JSON.stringify(payload).to_utf8_buffer())

func _login(api: LobbyProbe) -> void:
	api.cloud_enabled = true
	api.login("member@example.test", "test-password")
	_account_complete(api, "/auth/login", 200, {"ok": true, "sessionToken": "d".repeat(64), "user": {"id": "account-one", "email": "member@example.test"}})
	_account_complete(api, "/lobby/mine", 200, {"ok": true, "rooms": []})

func _run() -> void:
	await _test_accounts()
	await _test_cloud_registration()
	await _test_account_precondition()
	await _test_canonical_handoff()
	_assert(DirAccess.get_files_at(_test_dir).is_empty(), "Account login, session and enrollment must never create credential files")
	_remove_dir(_test_dir)
	ProjectSettings.set_setting("application/config/use_custom_user_dir", _old_dir)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", _old_name)
	print("Godot cloud lobby API checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)

func _dispose(node: Node) -> void:
	root.remove_child(node)
	node.queue_free()
	await process_frame

func _test_accounts() -> void:
	var api: LobbyProbe = LobbyProbe.new()
	root.add_child(api)
	for url: String in ["https://game.example.test", "https://game.example.test:443", "https://127.0.0.1:17343", "http://localhost:17343", "http://[::1]:17343"]:
		_assert(KingdomLobbyApi.valid_service_url(url), "Secure remote or local service origin is accepted: " + url)
	for url: String in ["http://game.example.test", "https://user:password@game.example.test", "https://game.example.test/api", "https://game.example.test?key=private", "https://game.example.test#token", "https://game.example.test:0", "https://game.example.test:65536", "https://"]:
		_assert(not KingdomLobbyApi.valid_service_url(url), "Unsafe/non-origin account address is rejected: " + url)
	_assert(api.configure_url("https://game.example.test/"), "Native explicitly selects HTTPS origin")
	_assert(api.cloud_enabled and api.account_session.is_empty(), "Selecting remote origin never invents account identity")
	_assert(api.inspect_service() and api.accounts[-1].path == "/auth/config", "Account capability is discovered independently from game health")
	_account_complete(api, "/auth/config", 200, {"enabled": true})
	_assert(api.accounts[-1].path == "/auth/me" and api.account_busy, "Cloud detection checks existing cookie/account session")
	_account_complete(api, "/auth/me", 401, {"error": {"message": "not signed in"}})
	_assert(api.account_user.is_empty() and api.account_session.is_empty(), "An unauthenticated browser cannot adopt a room from health alone")
	_assert(not api.create_room("房间", 2, "云城主") and api.sent.is_empty(), "Online signup requires a verified account")
	_assert(not api.login("invalid", "x") and not api.login("member@example.test", ""), "Incomplete login stays away from transport")
	_assert(api.login(" member@example.test ", "test-password"), "Valid account credentials start login")
	_assert(api.accounts[-1].body == {"email": "member@example.test", "password": "test-password"} and api._body_text.is_empty(), "Password login is separate from replayable registration memory")
	_account_complete(api, "/auth/login", 200, {"ok": true, "sessionToken": "short", "user": {"id": "account-one", "email": "member@example.test"}})
	_assert(api.account_user.is_empty() and api.account_session.is_empty(), "Incomplete token cannot replace account identity")
	_assert(api.login("member@example.test", "test-password"), "Failed login can be retried with freshly supplied password")
	_account_complete(api, "/auth/login", 200, {"ok": true, "sessionToken": "d".repeat(64), "user": {"id": "account-one", "email": "member@example.test"}})
	_assert(api.account_user.id == "account-one" and api.account_session == "d".repeat(64), "Only validated account response becomes in-memory session")
	_assert(api.accounts[-1].path == "/lobby/mine" and api.accounts[-1].session == "d".repeat(64), "Login automatically lists rooms with the account session")
	var member: Dictionary = _session()
	var entry: Dictionary = {"room": member.room, "seat": 1, "actor": member.actor, "authorityId": member.authorityId}
	_account_complete(api, "/lobby/mine", 200, {"ok": true, "rooms": [entry]})
	_assert(api.account_rooms.size() == 1 and api.account_rooms[0].actor.id == "member_cloud", "Only verified own-room list is exposed")
	var corrupt: Dictionary = entry.duplicate(true)
	corrupt.seat = 2
	_assert(not KingdomLobbyApi.valid_room_list({"ok": true, "rooms": [corrupt]}), "Room-list seat must match its actor roster")
	_assert(not KingdomLobbyApi.valid_room_list({"ok": true, "rooms": [entry, entry]}), "Duplicate room slots are rejected")
	var previous: Array = api.account_rooms.duplicate(true)
	api.refresh_rooms()
	_account_complete(api, "/lobby/mine", 200, {"ok": true, "rooms": [corrupt]})
	_assert(api.account_rooms == previous, "Corrupt refresh cannot replace verified rooms")
	api.refresh_rooms()
	_account_complete(api, "/lobby/mine", 401, {})
	_assert(api.account_user.is_empty() and api.account_rooms.is_empty() and api.account_session.is_empty(), "Expired account revokes all remembered rooms and credentials")
	_login(api)
	var signed_out: Array[bool] = []
	api.account_signed_out.connect(func() -> void: signed_out.append(true))
	api.logout()
	_assert(signed_out.size() == 1 and api.account_user.is_empty() and api.last_result.is_empty(), "Logout disconnects immediately, before remote confirmation")
	_assert(api.accounts[-1].path == "/auth/logout" and api.accounts[-1].session == "d".repeat(64) and api.account_session.is_empty(), "Remote revoke uses old session without keeping it as active identity")
	_account_complete(api, "/auth/logout", 503, {})
	_assert(api.account_user.is_empty() and api.account_session.is_empty(), "Lost logout confirmation never restores account locally")
	await _dispose(api)

func _test_cloud_registration() -> void:
	var api: LobbyProbe = LobbyProbe.new()
	root.add_child(api)
	_login(api)
	_assert(not api.resume_room("room_cloud", "b".repeat(64)) and api.sent.is_empty(), "Cloud cannot restore a member with recovery key")
	_assert(api.create_room("在线攻防", 2, "云城主"), "Signed-in native can create room")
	var original: Dictionary = api.sent[-1].duplicate(true)
	var body: Dictionary = JSON.parse_string(original.body)
	_assert(original.headers.has("X-Account-Session: " + "d".repeat(64)) and not body.has("accountId") and not body.has("sessionToken"), "Verified account header accompanies room registration; client cannot choose account")
	api._on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	_assert(api.needs_retry and api.account_session == "d".repeat(64), "Unknown enrollment retains session and original registration")
	_assert(api.retry_pending() and api.sent[-1] == original, "Online enrollment retry preserves exact body and nonce")
	api._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(_session()).to_utf8_buffer())
	_assert(api.last_result.actor.id == "member_cloud" and api._body_text.is_empty(), "Verified own room completes signup without durable credentials")
	_assert(api.resume_account_room("room_cloud"), "Logged-in account can restore occupied own seat")
	_assert(JSON.parse_string(api.sent[-1].body) == {"roomId": "room_cloud"} and api.sent[-1].path == "account-resume", "Account resume transmits only room ID, not another player's key or identity")
	api._on_completed(HTTPRequest.RESULT_SUCCESS, 401, PackedStringArray(), JSON.stringify({"error": {"message": "账号过期"}}).to_utf8_buffer())
	_assert(api.account_user.is_empty() and api.account_session.is_empty() and api.last_result.is_empty(), "Room authorization expiry clears account rather than encouraging key bypass")
	await _dispose(api)

func _test_account_precondition() -> void:
	var api: LobbyProbe = LobbyProbe.new()
	root.add_child(api)
	_login(api)
	_assert(api._account_headers().has("X-Expected-Account: account-one"), "Verified account accompanies protected requests as consistency precondition")
	api.create_room("云演练", 2, "云城主")
	var original: Dictionary = api.sent[-1].duplicate(true)
	api._on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	_assert(api._enrollment_account_id == "account-one" and not api.login("other@example.test", "password"), "Uncertain registration captures account and blocks fresh same-window sign-in")
	# A shared-cookie tab can change the transport account without changing this
	# window. Even a changed live user dictionary must not rewrite the retry.
	api.account_user = {"id": "account-other", "email": "other@example.test"}
	api.account_session = ""
	api.retry_pending()
	_assert(api.sent[-1].headers.has("X-Expected-Account: account-one") and not api.sent[-1].headers.has("X-Expected-Account: account-other") and api.sent[-1].body == original.body, "Retry keeps original account ID and nonce instead of manufacturing a room for another tab's account")
	api._on_completed(HTTPRequest.RESULT_SUCCESS, 401, PackedStringArray(), JSON.stringify({"error": {"code": "ACCOUNT_CHANGED", "message": "账号已改变，请重新登录"}}).to_utf8_buffer())
	_assert(api.last_result.is_empty() and api.account_user.is_empty() and not api.needs_retry and api._enrollment_account_id.is_empty(), "Account-changed rejection adopts no room and releases stale registration")
	_login(api)
	api.join_room("c".repeat(64), "云城主")
	api._on_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	api.check_account()
	_assert(api.accounts[-1].expected == "account-one", "Cookie account verification remains bound to the window's verified account")
	var disconnects: Array[bool] = []
	api.account_signed_out.connect(func() -> void: disconnects.append(true))
	_account_complete(api, "/auth/me", 200, {"ok": true, "user": {"id": "account-other", "email": "other@example.test"}})
	_assert(disconnects.size() == 1 and api.account_user.is_empty() and api.last_result.is_empty() and api._body_text.is_empty() and not api.needs_retry, "Unexpected successful auth-me for another account clears old pending seat and signals game disconnect")
	_login(api)
	api.logout()
	_assert(api.accounts[-1].expected == "account-one" and api.account_user.is_empty(), "Logout captures original account before clearing the UI/session")
	_account_complete(api, "/auth/logout", 401, {"error": {"code": "ACCOUNT_CHANGED"}})
	_assert(api.account_user.is_empty(), "Rejected cross-tab logout keeps this client signed out and never adopts another account")
	await _dispose(api)

func _test_canonical_handoff() -> void:
	var game: GameProbe = GameProbe.new()
	root.add_child(game)
	var member: Dictionary = _session()
	game.connect_to("https://game.example.test/api", str(member.accessToken), {"actorId": "member_cloud", "authorityId": "authority-cloud", "roomId": "room_cloud", "accountId": "account-one"}, "d".repeat(64))
	_assert(game.account_session == "d".repeat(64) and not game.connected and game.actor.is_empty(), "Native handoff preserves session without optimistic actor assignment")
	_assert(game._request_headers().has("Authorization: Bearer " + "a".repeat(64)) and game._request_headers().has("X-Account-Session: " + "d".repeat(64)), "Game health and mutations require both room and account headers")
	_assert(game._request_headers().has("X-Expected-Account: account-one"), "Canonical native requests retain account consistency condition as well as room token")
	game.retry_last()
	_assert(game.account_session == "d".repeat(64) and game._expected_identity.roomId == "room_cloud", "Reconnect keeps same account and expected room identity")
	var health: Dictionary = {"ok": true, "protocol": 1, "mode": "shared", "actor": member.actor, "authorityId": member.authorityId, "room": member.room}
	game._current = {"path": "health", "method": HTTPClient.METHOD_GET, "body": {}}
	game._queue.clear()
	game._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(health).to_utf8_buffer())
	_assert(game.connected and game.actor.id == "member_cloud", "Canonical authenticated health still controls identity adoption")
	game.last_snapshot = {"state": {"gold": 999}, "view": {"city": {"name": "旧账号城池"}}}
	game.command("shared.dispatch", [{"targetPlayerId": "member_enemy", "generalId": "lin", "troops": {"cavalry": 20}}])
	var command_id: String = ""
	for request: Dictionary in game._queue:
		if request.path == "command":
			command_id = str(request.body.commandId)
	var journal_path: String = game._journal_path(command_id)
	_assert(not command_id.is_empty() and FileAccess.file_exists(journal_path), "Canonical command still creates its original durable operation receipt")
	var journal: String = FileAccess.get_file_as_string(journal_path)
	_assert(not journal.contains("d".repeat(64)) and not journal.contains("a".repeat(64)) and not journal.contains("member@example.test") and not journal.contains("account_session"), "Canonical durable receipt excludes all account/room credentials and email")
	game.disconnect_account()
	_assert(FileAccess.get_file_as_string(journal_path) == journal and str(game._retry.body.commandId) == command_id, "Logout preserves original unconfirmed operation receipt without mixing account session")
	_assert(not game.connected and game.actor.is_empty() and game.room.is_empty() and game.last_snapshot.is_empty() and game.shared_world.is_empty(), "Logout removes every live account-derived view")
	_assert(game.token.is_empty() and game.account_session.is_empty() and game._queue.is_empty() and game._current.is_empty() and game._poll.is_stopped(), "Logout stops polling and drops RAM headers without writing credentials")
	game._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(health).to_utf8_buffer())
	_assert(game.actor.is_empty() and not game.connected, "Late response after logout cannot resurrect previous account")
	game.connect_to("http://127.0.0.1:17343/api", "local-token")
	_assert(game.account_session.is_empty() and not game._request_headers().has("X-Account-Session: " + "d".repeat(64)), "Returning to local rehearsal never forwards cloud session")
	game._clear_pending(command_id)
	await _dispose(game)

func _remove_dir(path: String) -> void:
	var folder: DirAccess = DirAccess.open(path)
	if folder == null:
		return
	for name: String in folder.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in folder.get_directories():
		_remove_dir(path.path_join(name))
	DirAccess.remove_absolute(path)
