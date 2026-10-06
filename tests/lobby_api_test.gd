extends SceneTree

## Production request serialization, enrollment retry and health identity checks.
## Transport only is replaced; no real room or existing user save is accessed.
class LobbyProbe extends "res://src/lobby_api.gd":
	var sent: Array[Dictionary] = []
	func _send() -> void:
		sent.append({"url": base_url, "path": _path, "body": _body_text})

class GameProbe extends "res://src/game_api.gd":
	func _pump() -> void:
		pass

var checks: int = 0
var failures: int = 0
var _old_custom_dir: Variant
var _old_custom_name: Variant
var _temporary_dir: String

func _initialize() -> void:
	_old_custom_dir = ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	_old_custom_name = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	var name: String = "ThreeKingdomsLobbyApiTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", name)
	_temporary_dir = OS.get_user_data_dir()
	if not _temporary_dir.ends_with(name):
		push_error("Refusing room tests outside an isolated temporary user directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_temporary_dir)
	call_deferred("_run")

func _assert(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _result(actor_id: String = "member_one", room_id: String = "room_one", authority: String = "authority-one") -> Dictionary:
	return {"ok": true, "protocol": 1, "room": {"id": room_id, "name": "青州攻防", "capacity": 4, "members": [{"id": actor_id, "name": "城主甲", "seat": 1, "team": "blue"}], "seat": 1}, "actor": {"id": actor_id, "name": "城主甲"}, "authorityId": authority, "accessToken": "a".repeat(64), "recoveryKey": "b".repeat(64), "inviteCode": "c".repeat(64)}

func _complete(api: LobbyProbe, code: int, payload: Variant, result: int = HTTPRequest.RESULT_SUCCESS) -> void:
	api._on_completed(result, code, PackedStringArray(), JSON.stringify(payload).to_utf8_buffer())

func _new_lobby() -> LobbyProbe:
	var api: LobbyProbe = LobbyProbe.new()
	root.add_child(api)
	return api

func _dispose(node: Node) -> void:
	root.remove_child(node)
	node.queue_free()
	await process_frame

func _run() -> void:
	await _test_enrollment_retry()
	await _test_validation()
	await _test_health_handoff()
	var leftovers: PackedStringArray = DirAccess.get_files_at(_temporary_dir)
	_assert(leftovers.is_empty(), "Lobby signup/session secrets must not create files in user data")
	DirAccess.remove_absolute(_temporary_dir)
	ProjectSettings.set_setting("application/config/use_custom_user_dir", _old_custom_dir)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", _old_custom_name)
	print("Godot lobby API checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)

func _test_enrollment_retry() -> void:
	var api: LobbyProbe = _new_lobby()
	var succeeded: Array[Dictionary] = []
	api.request_succeeded.connect(func(payload: Dictionary) -> void: succeeded.append(payload))
	_assert(api.configure_url("http://127.0.0.1:17343/"), "Native lobby accepts and normalizes the loopback service origin")
	_assert(api.create_room(" 青州攻防 ", 4, " 城主甲 "), "Valid create form starts a standalone room request")
	var first: Dictionary = api.sent[0].duplicate(true)
	var body: Dictionary = JSON.parse_string(first.body)
	_assert(first.path == "create" and first.url == "http://127.0.0.1:17343", "Room registration uses the lobby path, separate from game commands")
	var nonce: RegEx = RegEx.new()
	nonce.compile("^[a-f0-9]{64}$")
	_assert(nonce.search(str(body.get("requestId", ""))) != null, "Registration uses a 32-byte unpredictable request secret")
	_assert(body.roomName == "青州攻防" and body.playerName == "城主甲" and int(body.capacity) == 4, "Create serializes trimmed form values and requested capacity")
	_assert(not body.has("actorId") and not body.has("state") and not body.has("authorityId"), "Client registration never chooses actor identity or game state")
	_assert(not api.join_room("c".repeat(64), "另一城主") and api.sent.size() == 1, "Another registration cannot replace an in-flight enrollment")
	_complete(api, 0, {}, HTTPRequest.RESULT_CANT_CONNECT)
	_assert(api.needs_retry and not api.busy and succeeded.is_empty(), "Lost enrollment response is explicitly unconfirmed")
	_assert(not api.configure_url("http://localhost:17344") and api.base_url == first.url, "Unconfirmed enrollment cannot silently move to another service")
	_assert(not api.create_room("另一个房间", 8, "另一个城主") and api.sent.size() == 1, "Changed form values cannot create a fresh request while the original is unconfirmed")
	_assert(api.retry_pending() and api.sent.size() == 2 and api.sent[1] == first, "Retry sends the identical serialized body and original request secret")
	_complete(api, 503, {"error": {"code": "SERVICE_BUSY"}})
	_assert(api.needs_retry and succeeded.is_empty(), "A service failure cannot discard the enrollment receipt")
	_assert(api.retry_pending(), "The original registration remains retryable after service failure")
	_complete(api, 200, _result())
	_assert(succeeded.size() == 1 and not api.needs_retry and not api.busy, "Verified room identity completes enrollment once")
	_assert(api._body_text.is_empty() and api._path.is_empty(), "A verified result releases its registration request secret")
	_assert(api.last_result.actor.id == "member_one" and api.last_result.recoveryKey == "b".repeat(64), "Only the authenticated own enrollment result is held in live memory")
	succeeded[0].actor.id = "modified-ui-copy"
	_assert(api.last_result.actor.id == "member_one", "Signals expose a copy rather than writable identity storage")
	_assert(api.join_room("c".repeat(64), "城主乙"), "A completed enrollment permits a later independent join")
	var second: Dictionary = JSON.parse_string(api.sent[-1].body)
	_assert(second.requestId != body.requestId and second.has("inviteCode") and not second.has("roomName"), "Every new registration gets a fresh secret and correct join fields")
	_complete(api, 409, {"error": {"code": "ROOM_FULL", "message": "房间席位已满"}})
	_assert(not api.needs_retry and not api.busy and api._body_text.is_empty(), "A definite full-room rejection releases the failed enrollment")
	_assert(api.resume_room("room_one", "b".repeat(64)), "Restoring an occupied seat uses the member recovery key")
	var resume: Dictionary = JSON.parse_string(api.sent[-1].body)
	_assert(resume == {"roomId": "room_one", "recoveryKey": "b".repeat(64)}, "Recovery never sends an invitation or caller-selected actor")
	api.cancel_pending()
	_assert(not api.busy and not api.needs_retry and api._body_text.is_empty(), "Explicit abandonment clears only the live registration request")
	_complete(api, 200, _result("late-actor"))
	_assert(succeeded.size() == 1, "A response received after abandonment cannot enter a stale actor")
	await _dispose(api)

func _test_validation() -> void:
	var api: LobbyProbe = _new_lobby()
	for url: String in ["https://127.0.0.1:17343", "http://example.com:17343", "http://127.0.0.1:0", "http://127.0.0.1:70000", "http://127.0.0.1:17343/api", "http://127.0.0.1:17343/?token=secret", "http://user:password@localhost:17343"]:
		_assert(not api.configure_url(url), "Room rehearsal rejects unsafe/non-local service URL: " + url)
	_assert(api.configure_url("http://[::1]:17343"), "Native IPv6 loopback origin is accepted")
	_assert(not api.create_room("", 4, "甲") and not api.create_room("房间", 9, "甲") and not api.create_room("房间", 1, "") and api.sent.is_empty(), "Incomplete create forms cannot reach the service")
	_assert(not api.join_room("", "甲") and not api.resume_room("room_one", "short") and api.sent.is_empty(), "Empty invitation and incomplete private recovery info are rejected before transport")
	var valid: Dictionary = _result()
	_assert(KingdomLobbyApi.valid_result(valid), "A consistent 1–8 person room identity is accepted")
	var mutations: Array[Dictionary] = []
	for field: String in ["actor", "authorityId", "accessToken", "recoveryKey", "inviteCode", "room", "protocol"]:
		var missing: Dictionary = valid.duplicate(true)
		missing.erase(field)
		mutations.append(missing)
	var missing_own: Dictionary = valid.duplicate(true)
	missing_own.room.members[0].id = "other-member"
	mutations.append(missing_own)
	var duplicate: Dictionary = valid.duplicate(true)
	duplicate.room.members.append(duplicate.room.members[0].duplicate(true))
	mutations.append(duplicate)
	var fractional: Dictionary = valid.duplicate(true)
	fractional.room.capacity = 4.5
	mutations.append(fractional)
	var wrong_seat: Dictionary = valid.duplicate(true)
	wrong_seat.room.seat = 2
	mutations.append(wrong_seat)
	var wrong_name: Dictionary = valid.duplicate(true)
	wrong_name.actor.name = "另一个人"
	mutations.append(wrong_name)
	var wrong_team: Dictionary = valid.duplicate(true)
	wrong_team.room.members[0].team = "unrecognized-team"
	mutations.append(wrong_team)
	for index: int in range(mutations.size()):
		_assert(not KingdomLobbyApi.valid_result(mutations[index]), "Malformed enrollment identity %d cannot enter a room" % index)
	api.join_room("c".repeat(64), "甲")
	_complete(api, 200, missing_own)
	_assert(api.needs_retry and api.last_result.is_empty(), "An incomplete success response retains the exact enrollment for recovery")
	var original: String = api._body_text
	api.retry_pending()
	api._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "not-json".to_utf8_buffer())
	_assert(api.needs_retry and api._body_text == original, "An invalid JSON success cannot discard or rewrite the original request")
	api.cancel_pending()
	await _dispose(api)

func _game_complete(api: GameProbe, path: String, payload: Dictionary, code: int = 200) -> void:
	api._current = {"path": path, "method": HTTPClient.METHOD_GET, "body": {}}
	api._queue.clear()
	api._on_completed(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(), JSON.stringify(payload).to_utf8_buffer())

func _test_health_handoff() -> void:
	var api: GameProbe = GameProbe.new()
	root.add_child(api)
	var changes: Array[String] = []
	api.mode_changed.connect(func(mode: String) -> void: changes.append(mode))
	api._authority = "old-local"
	api.last_snapshot = {"revision": 11, "view": {"city": {"name": "原私人城池"}}}
	api.revision = 11
	var result: Dictionary = _result()
	var expectation: Dictionary = {"actorId": result.actor.id, "authorityId": result.authorityId, "roomId": result.room.id}
	var health: Dictionary = {"ok": true, "protocol": 1, "mode": "shared", "actor": result.actor, "authorityId": result.authorityId, "room": result.room}
	api.connect_to("http://127.0.0.1:17343/api", str(result.accessToken), expectation)
	_assert(api.actor.is_empty() and api.last_snapshot.view.city.name == "原私人城池", "Lobby selection cannot optimistically replace game identity or private UI before health authenticates")
	var wrong: Dictionary = health.duplicate(true)
	wrong.authorityId = "different-authority"
	_game_complete(api, "health", wrong)
	_assert(not api.connected and api._authority == "old-local" and changes.is_empty() and api.last_snapshot.view.city.name == "原私人城池", "Mismatched lobby handoff health keeps the old account intact and disconnected")
	api.connect_to("http://127.0.0.1:17343/api", str(result.accessToken), expectation)
	_game_complete(api, "health", health)
	_assert(api.connected and api.room.id == "room_one" and api.actor.id == "member_one" and api.last_snapshot.is_empty() and changes.size() == 1, "Verified room health switches identity and clears old private state through the existing handshake")
	var state: Dictionary = health.duplicate(true)
	state.merge({"revision": 1, "serverTime": 200, "view": {"city": {"name": "城主甲城"}}, "shared": {"players": []}}, true)
	_game_complete(api, "state", state)
	_assert(api.last_snapshot.view.city.name == "城主甲城" and api._connected_status().contains("青州攻防"), "Room state and status retain the authenticated room and own city")
	var latest: Dictionary = state.duplicate(true)
	latest.serverTime = 300
	latest.room.members.append({"id": "member_two", "name": "城主乙", "seat": 2, "team": "red"})
	_game_complete(api, "world", latest)
	_assert(api.room.members.size() == 2, "A fresh authoritative world updates the public room roster")
	_game_complete(api, "state", state)
	_assert(api.room.members.size() == 2 and api.last_snapshot.view.city.name == "城主甲城", "Older private responses cannot rewind accepted room membership")
	var foreign: Dictionary = state.duplicate(true)
	foreign.room.id = "other-room"
	_game_complete(api, "state", foreign)
	_assert(not api.connected and api.room.id == "room_one" and api.last_snapshot.view.city.name == "城主甲城", "Another room envelope cannot leak into the accepted account")
	api.connect_to("http://127.0.0.1:17342", "d".repeat(64))
	_game_complete(api, "health", {"ok": true, "protocol": 1, "mode": "shared", "actor": {"id": "player-1", "name": "演练青龙"}, "authorityId": "legacy-authority"})
	_assert(api.connected and api.room.is_empty() and api.actor.id == "player-1", "The original four-account rehearsal remains compatible without room metadata")
	api.connect_to("http://127.0.0.1:17337", "local-secret")
	_game_complete(api, "health", {"ok": true, "protocol": 1, "mode": "local", "authorityId": "local-authority"})
	_assert(api.connected and api.mode == "local" and api.room.is_empty() and api.actor.is_empty(), "Returning to private mode clears room and actor metadata")
	await _dispose(api)
