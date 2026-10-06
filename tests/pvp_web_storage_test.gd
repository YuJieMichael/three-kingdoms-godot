extends Node

## Export this script as a standalone Node scene for real JavaScriptBridge QA.
## All keys are unique test namespaces; no real account, token or progress.
class StorageProbe extends "res://src/game_api.gd":
	var before_write: Callable
	var before_delete: Callable
	func _ready() -> void:
		pass
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

var checks: int = 0
var failures: int = 0
var _output: Label

func _ready() -> void:
	_output = Label.new()
	_output.position = Vector2(24, 24)
	_output.size = Vector2(900, 600)
	_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_output)
	call_deferred("_run")

func _assert(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		_output.text += "FAIL: " + message + "\n"
		push_error(message)

func _request(id: String) -> Dictionary:
	return {"path": "command", "method": HTTPClient.METHOD_POST, "body": {"commandId": id, "type": "train", "args": ["archer", 5], "expectedRevision": 0, "sourceCity": "capital"}}

func _probe(suffix: String) -> StorageProbe:
	var api: StorageProbe = StorageProbe.new()
	api.mode = "shared"
	api.actor = {"id": "web-storage-test-" + suffix}
	api._authority = "isolated-web-test"
	api._pending_namespace = "user://pending-commands-shared-test-" + str(Time.get_ticks_usec()) + "-" + suffix
	api._pending_path = api._legacy_shared_path()
	add_child(api)
	return api

func _run() -> void:
	if not OS.has_feature("web"):
		_output.text = "This diagnostic must run in the exported Web build."
		return
	var first: StorageProbe = _probe("one")
	var second: StorageProbe = _probe("two")
	var third: StorageProbe = _probe("three")
	var other_actor: StorageProbe = _probe("other-actor")
	for api: StorageProbe in [second, third]:
		api.actor = first.actor.duplicate(true)
		api._pending_namespace = first._pending_namespace
		api._pending_path = first._legacy_shared_path()
	first.before_write = func() -> void:
		_assert(second._save_pending(_request("gd_web_test_two")), "The second real browser writer commits between the first writer's check and save.")
	_assert(first._save_pending(_request("gd_web_test_one")), "Real JavaScriptBridge must persist the first original receipt: " + first._pending_storage_error)
	var first_path: String = first._pending_path
	var second_path: String = second._pending_path
	_assert(first._pending_exists() and second._pending_exists(), "Interleaved same-account browser writes preserve both pending entries.")
	_assert(first._web_pending_key() != second._web_pending_key() and first._journal_paths().size() == 2, "A separate localStorage key per original ID prevents the account-wide check/write race.")
	var one: Variant = JSON.parse_string(first._read_pending())
	var two: Variant = JSON.parse_string(second._read_pending())
	_assert(one is Dictionary and two is Dictionary and one.request.body.commandId == "gd_web_test_one" and two.request.body.commandId == "gd_web_test_two", "Both exact original command bodies remain durable after the interleaving.")
	_assert(other_actor._save_pending(_request("gd_web_other_actor")), "Another actor independently persists an entry.")
	first.before_delete = func() -> void:
		_assert(third._save_pending(_request("gd_web_test_three")), "A third window can commit another original ID during acknowledgement cleanup.")
	first._clear_pending("gd_web_test_one")
	var third_path: String = third._pending_path
	_assert(not first._pending_exists_at(first_path) and first._pending_exists_at(second_path) and first._pending_exists_at(third_path), "Exact-ID cleanup preserves concurrent same-account operations.")
	_assert(other_actor._pending_exists(), "Acknowledging one account never deletes another actor's receipt.")
	var recovery: StorageProbe = _probe("recovery")
	recovery.actor = first.actor.duplicate(true)
	recovery._pending_namespace = first._pending_namespace
	recovery._pending_path = first._legacy_shared_path()
	recovery._load_pending()
	var recovered: Array[String] = []
	for request: Dictionary in recovery._pending_replays:
		recovered.append(str(request.body.commandId))
	_assert(recovered.size() == 2 and recovered.has("gd_web_test_two") and recovered.has("gd_web_test_three"), "Real browser restart recovery discovers all unresolved original IDs without a mutable head key.")
	recovery._queue_pending_replays()
	_assert(recovery._queue.size() == 2, "Recovery queues both exact original requests for authoritative idempotent replay.")
	second._clear_pending("gd_web_wrong_ack")
	_assert(second._pending_exists_at(second_path) and second._pending_exists_at(third_path), "A wrong acknowledgement ID removes no real browser journal entry.")
	_assert(third._save_pending(_request("gd_web_test_three")), "Saving the same original request remains idempotent and does not rewrite the entry.")
	var reused: Dictionary = _request("gd_web_test_three")
	reused.body.args = ["archer", 999]
	_assert(not third._save_pending(reused), "Reusing an existing command ID for a different body cannot replace its journal entry.")
	second._clear_pending("gd_web_test_two")
	_assert(not second._pending_exists_at(second_path) and second._pending_exists_at(third_path), "Acknowledging the second ID clears only its own entry.")
	third._clear_pending("gd_web_test_three")
	_assert(first._journal_paths().is_empty(), "The same-account journal empties only when all its individual operations are resolved.")
	other_actor._clear_pending("gd_web_other_actor")
	_assert(not other_actor._pending_exists(), "Cleanup removes the test-only other actor receipt.")
	_output.text += "WEB_PVP_STORAGE_CHECKS: %d passed, %d failed" % [checks - failures, failures]
	print("WEB_PVP_STORAGE_CHECKS: %d passed, %d failed" % [checks - failures, failures])
	for api: StorageProbe in [first, second, third, other_actor, recovery]:
		api.queue_free()
