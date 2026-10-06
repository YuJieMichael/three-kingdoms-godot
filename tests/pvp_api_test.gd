extends SceneTree

## Exercise production identity, durable receipts and shared-mode boundaries.
## Replace only HTTP pumping; never touch a real account or local save.
class TransportProbe extends "res://src/game_api.gd":
	func _pump() -> void:
		pass

class InterleavingProbe extends TransportProbe:
	var before_write: Callable
	var before_delete: Callable
	func _write_pending(contents: String) -> bool:
		if before_write.is_valid():
			var callback: Callable = before_write
			before_write = Callable()
			callback.call()
		return super._write_pending(contents)
	func _delete_pending_at(path: String, expected_id: String) -> void:
		if before_delete.is_valid():
			var callback: Callable = before_delete
			before_delete = Callable()
			callback.call()
		super._delete_pending_at(path, expected_id)

class StorageFailureProbe extends TransportProbe:
	func _write_pending(_contents: String) -> bool:
		_pending_storage_error = "storage-QuotaExceededError"
		return false

var checks: int = 0
var failures: int = 0
var _old_custom_user_dir: Variant
var _old_custom_user_name: Variant
var _temporary_user_dir: String = ""

func _initialize() -> void:
	_old_custom_user_dir = ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	_old_custom_user_name = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	var unique_name: String = "ThreeKingdomsPvpApiTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", unique_name)
	_temporary_user_dir = OS.get_user_data_dir()
	if not _temporary_user_dir.ends_with(unique_name):
		push_error("Refusing PvP tests without an isolated temporary user directory.")
		_restore_settings()
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_temporary_user_dir)
	call_deferred("_run")

func _run() -> void:
	await _test_shared_boundaries()
	await _test_durable_identity_switch()
	await _test_snapshot_identity()
	await _test_conflict_refresh()
	await _test_storage_failure()
	await _test_shared_legacy_recovery()
	await _test_stale_acknowledgement()
	await _test_equal_revision_older_time()
	await _test_higher_revision_older_time()
	_finish()

func _assert(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _health(id: String = "player-1", authority: String = "server-one:player-1") -> Dictionary:
	return {"ok": true, "protocol": 1, "mode": "shared", "authorityId": authority, "actor": {"id": id, "name": "演练甲"}}

func _snapshot(revision_value: int, id: String = "player-1", authority: String = "server-one:player-1") -> Dictionary:
	return {"mode": "shared", "authorityId": authority, "actor": {"id": id, "name": "演练甲"}, "revision": revision_value, "state": {"res": {"food": 100}}, "view": {"city": {"id": "capital"}}, "shared": {"cities": [{"id": "enemy-county", "ownerId": "player-2"}]}}

func _complete(api: TransportProbe, code: int, payload: Dictionary) -> void:
	api._on_completed(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(), JSON.stringify(payload).to_utf8_buffer())

func _take(api: TransportProbe, path: String) -> Dictionary:
	for index: int in range(api._queue.size()):
		if str(api._queue[index].get("path", "")) == path:
			api._current = api._queue[index].duplicate(true)
			api._queue.remove_at(index)
			return api._current.duplicate(true)
	_assert(false, "Expected queued %s request." % path)
	return {}

func _count(api: TransportProbe, path: String) -> int:
	var result: int = 0
	for request: Dictionary in api._queue:
		if str(request.get("path", "")) == path:
			result += 1
	return result

func _new_api() -> TransportProbe:
	var api: TransportProbe = TransportProbe.new()
	root.add_child(api)
	return api

func _connect(api: TransportProbe, health: Dictionary) -> void:
	api.connect_to("http://127.0.0.1:9998/api", "fixture-secret-never-persist")
	_take(api, "health")
	_complete(api, 200, health)

func _dispose(api: TransportProbe, clear_pending: bool = true) -> void:
	if clear_pending:
		api._clear_pending()
	root.remove_child(api)
	api.queue_free()
	await process_frame

func _test_shared_boundaries() -> void:
	var api: TransportProbe = _new_api()
	var messages: Array[String] = []
	api.status_changed.connect(func(message: String, _connected: bool) -> void: messages.append(message))
	_connect(api, _health())
	_assert(api.connected and api.mode == "shared" and api.actor.get("id", "") == "player-1", "Authenticated health must expose the active shared player.")
	_assert(messages[-1] == "已连接共享演练 · 演练甲 · 自动结算", "Shared connection status must identify the player and automatic settlement.")
	_take(api, "state")
	_complete(api, 200, _snapshot(7))
	_assert(api.revision == 7 and api.shared_world.get("cities", []).size() == 1, "Actor state must expose authoritative revision and shared rendering data.")
	api._queue.clear()
	api.import_snapshot({"res": {"food": 999999}})
	api.fetch_export()
	_assert(api._queue.is_empty() and not FileAccess.file_exists(api._pending_path), "Shared import/export must be rejected before transport and before a durable command is created.")
	for type: String in KingdomApi.SHARED_FORBIDDEN_COMMANDS:
		api.command(type, [0])
		_assert(_count(api, "command") == 0 and not FileAccess.file_exists(api._pending_path), "%s cannot control shared battle settlement from the client." % type)
	api.command("setTactic", ["archer", "hold"])
	var tactics: Dictionary = _take(api, "command")
	_assert(tactics.get("body", {}).get("type", "") == "setTactic", "Prepared army tactics remain available in shared mode.")
	_assert(not tactics.get("body", {}).has("serverTime") and not tactics.get("body", {}).has("now"), "Clients must never supply a settlement clock.")
	_complete(api, 200, _snapshot(8))
	_assert(_count(api, "world") == 1, "Acknowledging a shared command must promptly enqueue world refresh.")
	_assert(not FileAccess.file_exists(api._pending_path), "A matching shared acknowledgement clears the durable receipt.")
	await _dispose(api)

func _test_durable_identity_switch() -> void:
	var api: TransportProbe = _new_api()
	_connect(api, _health())
	api._queue.clear()
	api.last_snapshot = _snapshot(12)
	api.revision = 12
	api.command("shared.raid", ["enemy-county"])
	var original: Dictionary = _take(api, "command")
	var original_id: String = str(original.get("body", {}).get("commandId", ""))
	var first_path: String = api._pending_path
	api._fail_transport("Test: acknowledgement lost.")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(first_path))
	_assert(first_path != KingdomApi.PENDING_PATH and record.get("mode", "") == "shared" and record.get("actorId", "") == "player-1", "Shared pending receipts must use an account-specific namespace.")
	_assert(not FileAccess.get_file_as_string(first_path).contains("fixture-secret"), "Pending receipts must never persist bearer credentials.")
	await _dispose(api, false)
	api = _new_api()
	_assert(api._retry.is_empty() and FileAccess.file_exists(first_path), "Startup must defer loading shared receipts until the actor authenticates.")
	api.connect_to("http://127.0.0.1:9998/api", "wrong-secret")
	_take(api, "health")
	_complete(api, 401, {"error": {"code": "UNAUTHORIZED"}})
	_assert(not api.connected and FileAccess.file_exists(first_path), "Wrong credentials must preserve the unconfirmed account receipt.")
	api.connect_to("http://127.0.0.1:9998/api", "fixture-secret-never-persist")
	_take(api, "health")
	_complete(api, 500, {"error": {"code": "TEMPORARY"}})
	_assert(not api.connected and FileAccess.file_exists(first_path), "Server health errors cannot discard pending identity or operation ID.")
	var incomplete_health: Dictionary = _health()
	incomplete_health.erase("actor")
	_connect(api, incomplete_health)
	_assert(not api.connected and FileAccess.file_exists(first_path), "Malformed health cannot erase an unconfirmed command.")
	_connect(api, _health("player-2", "server-one:player-2"))
	_assert(_count(api, "command") == 0 and api._retry.is_empty() and FileAccess.file_exists(first_path), "Switching players must retain the old receipt without replaying it.")
	_assert(api.last_snapshot.is_empty() and api.shared_world.is_empty(), "A newly authenticated player starts without stale private data from another account.")
	api._queue.clear()
	api.command("train", ["archer", 5])
	var second_request: Dictionary = _take(api, "command")
	var second_path: String = api._pending_path
	_assert(first_path != second_path and FileAccess.file_exists(first_path) and FileAccess.file_exists(second_path), "A second account can operate without overwriting the first account's pending receipt.")
	_complete(api, 200, _snapshot(1, "player-2", "server-one:player-2"))
	_assert(FileAccess.file_exists(first_path) and not FileAccess.file_exists(second_path), "Acknowledging account two must never delete account one's pending operation.")
	_connect(api, _health("player-1", "server-two:player-1"))
	_assert(_count(api, "command") == 0 and FileAccess.file_exists(first_path), "The same player on a different authoritative server cannot replay the pending operation.")
	_connect(api, _health("player-2", "server-one:player-1"))
	_assert(_count(api, "command") == 0, "Even a reused server authority cannot replay an operation for the wrong actor.")
	_connect(api, _health())
	var replay: Dictionary = _take(api, "command")
	_assert(replay.get("body", {}).get("commandId", "") == original_id, "Returning to the exact shared identity replays the original command ID.")
	_assert(JSON.parse_string(JSON.stringify(replay.get("body", {}))) == JSON.parse_string(JSON.stringify(original.get("body", {}))), "Replay retains the original wire arguments, source city and expected revision.")
	_complete(api, 200, _snapshot(13))
	_assert(api.revision == 13 and api._retry.is_empty() and not FileAccess.file_exists(first_path), "Confirmed original-player replay takes the server revision and removes its receipt.")
	_assert(not second_request.is_empty(), "The independent second-account operation was actually submitted.")
	await _dispose(api)
	await _test_same_origin_tabs()

func _test_same_origin_tabs() -> void:
	var first: TransportProbe = _new_api()
	var second: TransportProbe = _new_api()
	_connect(first, _health())
	_connect(second, _health("player-2", "server-one:player-2"))
	first._queue.clear()
	second._queue.clear()
	first.command("train", ["archer", 5])
	second.command("train", ["archer", 7])
	_take(first, "command")
	_take(second, "command")
	_assert(first._pending_path != second._pending_path and FileAccess.file_exists(first._pending_path) and FileAccess.file_exists(second._pending_path), "Two simultaneous same-origin clients retain separate actor receipts.")
	_complete(first, 200, _snapshot(1))
	_assert(not FileAccess.file_exists(first._pending_path) and FileAccess.file_exists(second._pending_path), "A response in one tab cannot remove another actor tab's pending file.")
	_complete(second, 200, _snapshot(1, "player-2", "server-one:player-2"))
	await _dispose(first)
	await _dispose(second)
	await _test_same_account_journal()

func _test_same_account_journal() -> void:
	var first: InterleavingProbe = InterleavingProbe.new()
	root.add_child(first)
	var second: TransportProbe = _new_api()
	var third: TransportProbe = _new_api()
	for api: TransportProbe in [first, second, third]:
		_connect(api, _health())
		api._queue.clear()
		api.revision = 10
		api.last_snapshot = _snapshot(10)
	# Actual second writer executes after first writer's existence check but
	# before its durable write, the exact old single-key lost-ID race.
	first.before_write = func() -> void: second.command("train", ["archer", 7])
	first.command("train", ["archer", 5])
	var one: Dictionary = _take(first, "command")
	var two: Dictionary = _take(second, "command")
	var first_path: String = first._pending_path
	var second_path: String = second._pending_path
	_assert(first_path != second_path and FileAccess.file_exists(first_path) and FileAccess.file_exists(second_path), "Interleaved same-account writers preserve both original command IDs in distinct real durable entries.")
	_assert(first._journal_paths().size() == 2, "The account journal contains every command even when another window wrote between check and save.")
	_assert(JSON.parse_string(FileAccess.get_file_as_string(first_path)).request.body.commandId == one.body.commandId and JSON.parse_string(FileAccess.get_file_as_string(second_path)).request.body.commandId == two.body.commandId, "Both journal entries retain the exact operation bodies rather than a mutable account-wide head.")
	# A third live window starts another operation just as the first older
	# response begins cleanup. It must not be removed by that cleanup.
	first.before_delete = func() -> void: third.command("train", ["archer", 9])
	_complete(first, 200, _snapshot(11))
	var three: Dictionary = _take(third, "command")
	var third_path: String = third._pending_path
	_assert(not FileAccess.file_exists(first_path) and FileAccess.file_exists(second_path) and FileAccess.file_exists(third_path), "Exact-ID cleanup cannot delete another window's concurrent or newer journal entry.")
	var recovery: TransportProbe = _new_api()
	_connect(recovery, _health())
	var recovered: Array[String] = []
	for request: Dictionary in recovery._queue:
		if request.path == "command":
			recovered.append(str(request.body.commandId))
	_assert(recovered.size() == 2 and recovered.has(str(two.body.commandId)) and recovered.has(str(three.body.commandId)), "Restart recovery replays every unresolved command ID in the same-account journal.")
	_assert(not recovered.has(str(one.body.commandId)), "Already acknowledged commands are not replayed during journal recovery.")
	await _dispose(recovery, false)
	_complete(second, 409, {"error": {"code": "REVISION_CONFLICT"}})
	_assert(not FileAccess.file_exists(second_path) and FileAccess.file_exists(third_path), "A definitive rejection only removes its own journal entry.")
	_complete(third, 200, _snapshot(12))
	_assert(third._journal_paths().is_empty(), "The journal is empty only after every original command is individually resolved.")
	for api: TransportProbe in [first, second, third]:
		await _dispose(api)

func _test_snapshot_identity() -> void:
	for missing_field: String in ["actor", "authorityId", "mode", "wrong-actor", "wrong-authority"]:
		var api: TransportProbe = _new_api()
		_connect(api, _health())
		api._queue.clear()
		api.revision = 2
		api.last_snapshot = _snapshot(2)
		api.command("train", ["archer", 10])
		var original: Dictionary = _take(api, "command")
		var invalid: Dictionary = _snapshot(99)
		if missing_field == "wrong-actor":
			invalid["actor"]["id"] = "player-2"
		elif missing_field == "wrong-authority":
			invalid["authorityId"] = "server-two:player-1"
		else:
			invalid.erase(missing_field)
		_complete(api, 200, invalid)
		_assert(not api.connected and api.revision == 2, "A shared acknowledgement with invalid %s must not merge its revision." % missing_field)
		_assert(api._retry.get("body", {}).get("commandId", "") == original.get("body", {}).get("commandId", "") and FileAccess.file_exists(api._pending_path), "Malformed identity cannot acknowledge or erase an unconfirmed command.")
		await _dispose(api)
	for path: String in ["state", "world"]:
		var api: TransportProbe = _new_api()
		_connect(api, _health())
		api._queue.clear()
		api.last_snapshot = _snapshot(4)
		api.revision = 4
		var emitted: Array[Dictionary] = []
		api.snapshot_received.connect(func(payload: Dictionary) -> void: emitted.append(payload))
		api.world_received.connect(func(payload: Dictionary) -> void: emitted.append(payload))
		api._current = {"path": path, "method": HTTPClient.METHOD_GET, "body": {}}
		_complete(api, 200, _snapshot(50, "player-2", "server-one:player-2"))
		_assert(not api.connected and emitted.is_empty() and api.revision == 4, "Wrong-player %s responses must never reach production UI or change revision." % path)
		_assert(api.last_snapshot.get("actor", {}).get("id", "") == "player-1", "Wrong-player response cannot replace the last validated snapshot.")
		await _dispose(api)
	var api: TransportProbe = _new_api()
	var invalid_health: Dictionary = _health()
	invalid_health.erase("actor")
	_connect(api, invalid_health)
	_assert(not api.connected and _count(api, "state") == 0, "Shared health without an actor cannot authenticate or fetch player data.")
	await _dispose(api)

func _test_conflict_refresh() -> void:
	var api: TransportProbe = _new_api()
	_connect(api, _health())
	api._queue.clear()
	api.revision = 20
	api.last_snapshot = _snapshot(20)
	api.command("shared.raid", ["enemy-county"])
	_take(api, "command")
	_complete(api, 409, {"error": {"code": "REVISION_CONFLICT", "message": "状态已更新"}, "revision": 21})
	_assert(not FileAccess.file_exists(api._pending_path) and api._retry.is_empty(), "Definitive revision rejection clears the rejected operation.")
	_assert(_count(api, "command") == 0, "CAS conflicts must not create a new attack or silently retry with a fresh ID.")
	_assert(_count(api, "state") == 1 and _count(api, "world") == 1, "CAS conflicts refresh both private state and the shared world exactly once.")
	_take(api, "state")
	_complete(api, 200, _snapshot(21))
	_assert(api.revision == 21 and _count(api, "command") == 0, "Conflict recovery takes fresh authoritative state without sending another operation.")
	await _dispose(api)

func _test_storage_failure() -> void:
	var api: StorageFailureProbe = StorageFailureProbe.new()
	root.add_child(api)
	_connect(api, _health())
	api._queue.clear()
	var failures_received: Array[String] = []
	api.request_failed.connect(func(message: String) -> void: failures_received.append(message))
	api.command("train", ["archer", 5])
	_assert(_count(api, "command") == 0 and api._current.is_empty(), "A receipt storage failure blocks sending the mutation, even with a working connection.")
	_assert(not FileAccess.file_exists(api._pending_path) and api._retry.is_empty(), "Storage failure does not pretend there is a durable operation to retry.")
	_assert(failures_received.size() == 1 and failures_received[0].contains("QuotaExceededError") and not failures_received[0].contains("fixture-secret"), "Storage failure reports a safe browser error name without exposing credentials.")
	await _dispose(api)

func _test_shared_legacy_recovery() -> void:
	var api: TransportProbe = _new_api()
	_connect(api, _health())
	api._queue.clear()
	var legacy_path: String = api._legacy_shared_path()
	var request: Dictionary = {"path": "command", "method": HTTPClient.METHOD_POST, "body": {"commandId": "gd_legacy_shared_operation", "type": "train", "args": ["archer", 6], "expectedRevision": 3, "sourceCity": "capital"}}
	var file: FileAccess = FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"authority": "server-one:player-1", "mode": "shared", "actorId": "player-1", "request": request}))
	file.close()
	_connect(api, _health())
	var replay: Dictionary = _take(api, "command")
	_assert(replay.body.commandId == request.body.commandId, "Actor-scoped receipts from the previous build remain recoverable with their original ID.")
	_complete(api, 200, _snapshot(4))
	_assert(not FileAccess.file_exists(legacy_path) and api._journal_paths().is_empty(), "Acknowledging a previous-format receipt clears only that exact legacy command.")
	await _dispose(api)

func _test_stale_acknowledgement() -> void:
	var api: TransportProbe = _new_api()
	_connect(api, _health())
	api._queue.clear()
	api.revision = 30
	var latest: Dictionary = _snapshot(30)
	latest["state"]["res"]["food"] = 777
	latest["shared"]["reports"] = [{"id": "latest-report"}]
	api.last_snapshot = latest.duplicate(true)
	api.shared_world = latest.shared.duplicate(true)
	var request: Dictionary = {"path": "command", "method": HTTPClient.METHOD_POST, "body": {"commandId": "gd_cached_old_ack", "type": "train", "args": ["archer", 6], "expectedRevision": 24, "sourceCity": "capital"}}
	api._save_pending(request)
	var receipt_path: String = api._pending_path
	api._current = request.duplicate(true)
	var snapshots: Array[Dictionary] = []
	var completions: Array[Dictionary] = []
	api.snapshot_received.connect(func(payload: Dictionary) -> void: snapshots.append(payload))
	api.command_completed.connect(func(_type: String, payload: Dictionary) -> void: completions.append(payload))
	var cached: Dictionary = _snapshot(25)
	cached["replayed"] = true
	_complete(api, 200, cached)
	_assert(not FileAccess.file_exists(receipt_path) and completions.size() == 1, "A stale replay acknowledgement still confirms and clears its exact command ID once.")
	_assert(api.revision == 30 and api.last_snapshot == latest and api.shared_world == latest.shared, "A cached older acknowledgement never regresses the known revision, private resources or shared reports.")
	_assert(snapshots.is_empty(), "Old receipt state is never emitted to the UI as a current snapshot.")
	_assert(_count(api, "state") == 1 and _count(api, "world") == 1 and _count(api, "command") == 0, "Stale acknowledgement recovery refreshes state and world without creating a new mutation.")
	_take(api, "state")
	_complete(api, 200, _snapshot(31))
	_assert(api.revision == 31 and snapshots.size() == 1, "A fresh later snapshot is accepted after the old receipt was acknowledged.")
	await _dispose(api)

func _test_equal_revision_older_time() -> void:
	var api: TransportProbe = _new_api()
	_connect(api, _health())
	api._queue.clear()
	api.revision = 40
	var state: Dictionary = _snapshot(40)
	state["serverTime"] = 1000
	state["state"]["res"]["food"] = 777
	api.last_snapshot = state.duplicate(true)
	var snapshots: Array[Dictionary] = []
	var worlds: Array[Dictionary] = []
	var completions: Array[Dictionary] = []
	api.snapshot_received.connect(func(payload: Dictionary) -> void: snapshots.append(payload))
	api.world_received.connect(func(payload: Dictionary) -> void: worlds.append(payload))
	api.command_completed.connect(func(_type: String, payload: Dictionary) -> void: completions.append(payload))
	var world: Dictionary = _snapshot(40)
	world["serverTime"] = 2000
	world["shared"]["reports"] = [{"id": "another-player-new-report"}]
	api._current = {"path": "world", "method": HTTPClient.METHOD_GET, "body": {}}
	_complete(api, 200, world)
	_assert(api.shared_world == world.shared and worlds.size() == 1, "A newer public world is accepted even when the actor's private revision has not changed.")
	var request: Dictionary = {"path": "command", "method": HTTPClient.METHOD_POST, "body": {"commandId": "gd_equal_revision_old_ack", "type": "train", "args": ["archer", 5], "expectedRevision": 39, "sourceCity": "capital"}}
	api._save_pending(request)
	var pending_path: String = api._pending_path
	api._current = request
	var cached: Dictionary = _snapshot(40)
	cached["serverTime"] = 1500
	cached["replayed"] = true
	_complete(api, 200, cached)
	_assert(not FileAccess.file_exists(pending_path) and completions.size() == 1, "Same-revision cached receipts still acknowledge their exact command.")
	_assert(api.last_snapshot == state and api.shared_world == world.shared and snapshots.is_empty(), "An older serverTime cannot resurrect private view or public world data at the same actor revision.")
	_assert(_count(api, "state") == 1 and _count(api, "world") == 1, "Same-revision old-time receipts request a fresh state and world.")
	var fresh: Dictionary = _snapshot(40)
	fresh["serverTime"] = 2100
	fresh["shared"]["reports"] = [{"id": "fresh-report"}]
	_take(api, "state")
	_complete(api, 200, fresh)
	_assert(api.revision == 40 and api.last_snapshot.get("serverTime", 0) == 2100 and snapshots.size() == 1, "A newer-time state is accepted without requiring a higher actor revision.")
	_take(api, "world")
	_complete(api, 200, world)
	_assert(api.shared_world == fresh.shared and worlds.size() == 1, "A delayed older world response never reaches the map or replaces newer reports.")
	await _dispose(api)

func _test_higher_revision_older_time() -> void:
	var api: TransportProbe = _new_api()
	_connect(api, _health())
	api._queue.clear()
	api.revision = 5
	var state: Dictionary = _snapshot(5)
	state["serverTime"] = 100
	state["view"]["marches"] = []
	api.last_snapshot = state.duplicate(true)
	var snapshots: Array[Dictionary] = []
	var worlds: Array[Dictionary] = []
	var completions: Array[Dictionary] = []
	api.snapshot_received.connect(func(payload: Dictionary) -> void: snapshots.append(payload))
	api.world_received.connect(func(payload: Dictionary) -> void: worlds.append(payload))
	api.command_completed.connect(func(_type: String, payload: Dictionary) -> void: completions.append(payload))
	var world: Dictionary = _snapshot(7)
	world["serverTime"] = 200
	world["shared"]["marches"] = []
	world["shared"]["reports"] = [{"id": "settled-march"}]
	api._current = {"path": "world", "method": HTTPClient.METHOD_GET, "body": {}}
	_complete(api, 200, world)
	_assert(api.revision == 5 and api.shared_world == world.shared and worlds.size() == 1, "Public settlement polling can advance the world before the private revision.")
	var request: Dictionary = {"path": "command", "method": HTTPClient.METHOD_POST, "body": {"commandId": "gd_higher_revision_old_time_ack", "type": "shared.attack", "args": [{"target": "enemy-county"}], "expectedRevision": 5, "sourceCity": "capital"}}
	api._save_pending(request)
	var pending_path: String = api._pending_path
	api._current = request
	var cached: Dictionary = _snapshot(6)
	cached["serverTime"] = 150
	cached["replayed"] = true
	cached["view"]["marches"] = [{"id": "old-outbound", "status": "outbound"}]
	_complete(api, 200, cached)
	_assert(not FileAccess.file_exists(pending_path) and completions.size() == 1, "A higher-revision old-time cached receipt acknowledges only its original command.")
	_assert(api.revision == 5 and api.last_snapshot == state and api.shared_world == world.shared and snapshots.is_empty(), "A cached receipt older than the public settlement cannot resurrect an outbound army or regress resources, even with a higher private revision.")
	_assert(_count(api, "state") == 1 and _count(api, "world") == 1 and _count(api, "command") == 0, "Higher-revision old-time acknowledgement recovery requests fresh DTOs without resubmitting the action.")
	var fresh: Dictionary = _snapshot(7)
	fresh["serverTime"] = 210
	fresh["view"]["marches"] = []
	fresh["shared"]["reports"] = [{"id": "settled-march"}]
	_take(api, "state")
	_complete(api, 200, fresh)
	_assert(api.revision == 7 and api.last_snapshot == JSON.parse_string(JSON.stringify(fresh)) and snapshots.size() == 1, "A current higher-revision state is accepted after the stale acknowledgement is cleared.")
	await _dispose(api)

func _restore_settings() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", _old_custom_user_dir)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", _old_custom_user_name)

func _finish() -> void:
	var directory: DirAccess = DirAccess.open(_temporary_user_dir)
	if directory != null:
		for filename: String in directory.get_files():
			if filename.begins_with("pending-command") and filename.ends_with(".json"):
				DirAccess.remove_absolute(_temporary_user_dir.path_join(filename))
	if directory != null:
		for folder: String in directory.get_directories():
			if folder.begins_with("pending-commands-shared-"):
				var nested: DirAccess = DirAccess.open(_temporary_user_dir.path_join(folder))
				if nested != null:
					for filename: String in nested.get_files():
						DirAccess.remove_absolute(_temporary_user_dir.path_join(folder).path_join(filename))
				DirAccess.remove_absolute(_temporary_user_dir.path_join(folder))
	DirAccess.remove_absolute(_temporary_user_dir)
	_restore_settings()
	print("Godot PvP API checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)
