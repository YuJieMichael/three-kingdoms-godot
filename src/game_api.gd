extends Node
class_name KingdomApi

const LobbyApiScript: Script = preload("res://src/lobby_api.gd")

signal snapshot_received(payload: Dictionary)
signal world_received(payload: Dictionary)
signal status_changed(message: String, connected: bool)
signal request_failed(message: String)
signal export_received(snapshot: Dictionary)
signal command_completed(type: String, payload: Dictionary)
signal mode_changed(mode: String)
signal quote_received(payload: Dictionary)
signal practice_received(payload: Dictionary)
signal practice_failed(message: String, code: String)

var base_url: String = "http://127.0.0.1:17337"
var token: String = ""
# Account session is RAM only; it never enters pending-command journals.
var account_session: String = ""
var revision: int = 0
var connected: bool = false
var last_snapshot: Dictionary = {}
var mode: String = "local"
var actor: Dictionary = {}
var room: Dictionary = {}
var shared_world: Dictionary = {}
var _expected_identity: Dictionary = {}
var _http: HTTPRequest
var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _retry: Dictionary = {}
var _poll: Timer
var _world_elapsed: float = 5.0
var _local_pid: int = -1
var _ready_file: String = ""
var _boot_wait: float = 0.0
var _authority: String = ""
var _pending_authority: String = ""
var _pending_mode: String = "local"
var _pending_actor_id: String = ""
var _pending_command_id: String = ""
const PENDING_PATH: String = "user://pending-command.json"
var _pending_path: String = PENDING_PATH
var _pending_storage_error: String = ""
var _pending_namespace: String = ""
var _pending_replays: Array[Dictionary] = []
var _last_world_time: float = 0.0
# Shared arrival/battle settlement belongs to the server, even while players
# are offline. Prepared army tactics remain available through setTactic.
const SHARED_FORBIDDEN_COMMANDS: PackedStringArray = ["dispatch", "scout", "dispatchScout", "shared.settle", "startBattle", "battleRound", "setBattleOrder", "setBattleOrders", "dismissBattle", "submitBattleTactic", "cancelBattleTactic", "requestCityDefense", "setAutoCityDefense", "startCityDefense", "cityDefenseRound", "resolveCityDefense", "endDefenseDrill"]

func _ready() -> void:
	_load_pending()
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	add_child(_http)
	_http.request_completed.connect(_on_completed)
	_poll = Timer.new()
	_poll.wait_time = 2.0
	_poll.timeout.connect(_poll_state)
	add_child(_poll)

func connect_to(url: String, access_token: String = "", expected_identity: Dictionary = {}, session: String = "") -> void:
	base_url = url.trim_suffix("/")
	token = access_token
	account_session = session
	_expected_identity = expected_identity.duplicate(true)
	_stash_unconfirmed()
	_queue.clear()
	_poll.stop()
	if not _current.is_empty():
		_http.cancel_request()
		_current.clear()
	connected = false
	status_changed.emit("正在连接规则服务…", false)
	_enqueue("health", HTTPClient.METHOD_GET)

func start_local() -> void:
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		connect_to(str(origin) + "/api", _web_access_token())
		return
	var root: String = ProjectSettings.globalize_path("res://")
	var bundle_root: String = OS.get_executable_path().get_base_dir()
	var bridge_path: String = root.path_join("bridge/server.mjs")
	var node_path: String = OS.get_environment("TK_NODE")
	if not OS.has_feature("editor"):
		bridge_path = bundle_root.path_join("rule-service/bridge/server.mjs")
		if OS.has_feature("windows"):
			node_path = bundle_root.path_join("runtime/node.exe")
		elif OS.has_feature("macos"):
			node_path = bundle_root.path_join("runtime/node")
	if node_path.is_empty():
		var candidates: Array[String] = [root.path_join("runtime/node"), "/usr/local/bin/node", "/opt/homebrew/bin/node"]
		for candidate: String in candidates:
			if FileAccess.file_exists(candidate):
				node_path = candidate
				break
	if node_path.is_empty() or not FileAccess.file_exists(bridge_path):
		status_changed.emit("规则服务未找到，请在设置中连接服务", false)
		return
	token = Crypto.new().generate_random_bytes(24).hex_encode()
	_ready_file = OS.get_user_data_dir().path_join("bridge-" + str(OS.get_process_id()) + ".json")
	var args: PackedStringArray = PackedStringArray([bridge_path, "--port", "0", "--data-dir", OS.get_user_data_dir().path_join("progress"), "--token", token, "--ready-file", _ready_file])
	_local_pid = OS.create_process(node_path, args, false)
	if _local_pid < 0:
		status_changed.emit("无法启动本地规则服务", false)
		return
	_boot_wait = 0.0
	status_changed.emit("正在启动本地进度…", false)
	set_process(true)

func _process(delta: float) -> void:
	if _ready_file.is_empty():
		return
	_boot_wait += delta
	if FileAccess.file_exists(_ready_file):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_ready_file))
		if data is Dictionary and data.has("url") and int(data.get("pid", -1)) == _local_pid:
			_ready_file = ""
			connect_to(str(data.url), token)
	if not _ready_file.is_empty() and _boot_wait > 15.0:
		_ready_file = ""
		status_changed.emit("规则服务启动超时，请检查运行环境", false)

func command(type: String, args: Array = [], source_city: String = "") -> void:
	if not connected:
		request_failed.emit("请先连接规则服务")
		return
	if mode == "shared" and type in SHARED_FORBIDDEN_COMMANDS:
		request_failed.emit("共享演练请向玩家城池派兵；抵达和战斗由服务器自动结算")
		return
	if _has_mutation():
		request_failed.emit("上一项操作正在结算，请稍候")
		return
	var data: Dictionary = {"commandId": "gd_" + Crypto.new().generate_random_bytes(12).hex_encode(), "expectedRevision": revision, "type": type, "args": args}
	if source_city.is_empty():
		source_city = str(last_snapshot.get("view", {}).get("city", {}).get("id", "capital"))
	if not source_city.is_empty():
		data["sourceCity"] = source_city
	_enqueue("command", HTTPClient.METHOD_POST, data)

func import_snapshot(snapshot: Dictionary) -> void:
	if mode == "shared":
		request_failed.emit("共享演练不能导入个人存档")
		return
	if _has_mutation():
		request_failed.emit("请等待当前操作完成")
		return
	_enqueue("import", HTTPClient.METHOD_POST, {"commandId": "gd_" + Crypto.new().generate_random_bytes(12).hex_encode(), "expectedRevision": revision, "state": snapshot})

func request_quote(kind: String, args: Array, request_id: String) -> void:
	if not connected or _has_mutation():
		request_failed.emit("请先连接并等待当前操作完成，再预览")
		return
	_enqueue("quote", HTTPClient.METHOD_POST, {"kind": kind, "args": args, "requestId": request_id,
		"sourceCity": str(last_snapshot.get("view", {}).get("city", {}).get("id", "capital"))})

func fetch_export() -> void:
	if mode == "shared":
		request_failed.emit("共享演练进度由服务器保存，不能导出个人存档")
		return
	_enqueue("export", HTTPClient.METHOD_GET)

func request_practice(input: Dictionary) -> void:
	# Practice uses a separate RAM-only session and never enters the campaign
	# journal. The caller retains the exact request ID for an explicit retry.
	if mode != "local" or not connected:
		practice_failed.emit("请连接本机进度后开启借调演练。", "CLIENT_UNAVAILABLE")
		return
	if _has_mutation():
		practice_failed.emit("请等待正式城池操作确认后再演练。", "CLIENT_CAMPAIGN_PENDING")
		return
	if str(_current.get("path", "")) == "practice" or _queue.any(func(row: Dictionary) -> bool: return str(row.get("path", "")) == "practice"):
		practice_failed.emit("上一项演练操作正在确认。", "CLIENT_PRACTICE_PENDING")
		return
	_enqueue("practice", HTTPClient.METHOD_POST, input.duplicate(true))

func refresh() -> void:
	_enqueue("state", HTTPClient.METHOD_GET)
	_enqueue("world", HTTPClient.METHOD_GET)

func retry_last() -> void:
	# Re-check authority before replaying the exact original operation.
	connect_to(base_url, token, _expected_identity, account_session)

func _load_pending() -> void:
	if mode == "shared" and not _pending_namespace.is_empty():
		_reset_pending_memory()
		var paths: Array[String] = _journal_paths()
		var legacy_path: String = _legacy_shared_path()
		if _pending_exists_at(legacy_path):
			paths.append(legacy_path)
		var seen: Dictionary = {}
		for path: String in paths:
			var value: Variant = JSON.parse_string(_read_pending_at(path))
			if not _valid_pending_record(value):
				continue
			if str(value.get("mode", "local")) != "shared" or str(value.get("authority", "")) != _authority or str(value.get("actorId", "")) != str(actor.get("id", "")):
				continue
			var id: String = str(value.request.body.get("commandId", ""))
			if seen.has(id):
				continue
			seen[id] = true
			_pending_replays.append(value.request.duplicate(true))
			if _retry.is_empty():
				_adopt_pending(value, path)
		return
	if not _pending_exists():
		return
	var value: Variant = JSON.parse_string(_read_pending())
	if _valid_pending_record(value):
		_adopt_pending(value, _pending_path)

func _valid_pending_record(value: Variant) -> bool:
	return value is Dictionary and value.get("request") is Dictionary and str(value.request.get("path", "")) in ["command", "import"] and value.request.get("body") is Dictionary and value.request.body.get("commandId") is String and not str(value.request.body.commandId).is_empty() and str(value.request.body.commandId).is_valid_filename()

func _adopt_pending(value: Dictionary, path: String) -> void:
	_retry = value.request.duplicate(true)
	_pending_authority = str(value.get("authority", ""))
	_pending_mode = str(value.get("mode", "local"))
	_pending_actor_id = str(value.get("actorId", ""))
	_pending_command_id = str(value.request.body.get("commandId", ""))
	_pending_path = path

func _save_pending(request: Dictionary) -> bool:
	var command_id: String = str(request.get("body", {}).get("commandId", ""))
	if mode == "shared":
		# Every original operation has a distinct immutable journal entry. Two
		# windows can write concurrently without replacing each other's IDs.
		if _pending_namespace.is_empty() or command_id.is_empty() or not command_id.is_valid_filename():
			request_failed.emit("操作身份未确认，操作未发送")
			return false
		_pending_path = _journal_path(command_id)
	if _pending_exists():
		var stored: Variant = JSON.parse_string(_read_pending())
		if not _valid_pending_record(stored) or str(stored.request.body.get("commandId", "")) != command_id or (mode == "shared" and JSON.parse_string(JSON.stringify(stored.request)) != JSON.parse_string(JSON.stringify(request))):
			_load_pending()
			request_failed.emit("未确认操作已存在，请重连原账号核对")
			return false
		if mode == "shared":
			# Journal entries are immutable; a replay need not rewrite its entry.
			_pending_authority = _authority
			_pending_mode = mode
			_pending_actor_id = str(actor.get("id", ""))
			_pending_command_id = command_id
			return true
	var contents: String = JSON.stringify({"authority": _authority, "mode": mode, "actorId": str(actor.get("id", "")), "request": request})
	if not _write_pending(contents):
		request_failed.emit("无法保存操作回执，操作未发送" + ("（" + _pending_storage_error + "）" if not _pending_storage_error.is_empty() else ""))
		return false
	_pending_authority = _authority
	_pending_mode = mode
	_pending_actor_id = str(actor.get("id", ""))
	_pending_command_id = command_id
	return true

func _reset_pending_memory() -> void:
	_retry.clear()
	_pending_replays.clear()
	_pending_authority = ""
	_pending_mode = "local"
	_pending_actor_id = ""
	_pending_command_id = ""

func _clear_pending(expected_id: String = "") -> void:
	if expected_id.is_empty():
		expected_id = _pending_command_id
	if mode == "shared" and not _pending_namespace.is_empty():
		if not expected_id.is_empty() and expected_id.is_valid_filename():
			_delete_pending_at(_journal_path(expected_id), expected_id)
			# Previous builds wrote one actor-scoped receipt. New builds never
			# write that legacy key/file, but recover and acknowledge it safely.
			_delete_pending_at(_legacy_shared_path(), expected_id)
		_reset_pending_memory()
		_pending_path = _legacy_shared_path()
		_load_pending()
		return
	_reset_pending_memory()
	if _pending_exists():
		var stored: Variant = JSON.parse_string(_read_pending())
		if not expected_id.is_empty() and _valid_pending_record(stored) and str(stored.request.body.get("commandId", "")) == expected_id:
			_delete_pending(expected_id)
		else:
			_load_pending()

func _switch_pending_identity() -> void:
	var next_path: String = PENDING_PATH
	var next_namespace: String = ""
	if mode == "shared":
		var identity: String = JSON.stringify([_authority, str(actor.get("id", ""))])
		var hash: String = identity.sha256_text()
		next_namespace = "user://pending-commands-shared-" + hash
		next_path = "user://pending-command-shared-" + hash + ".json"
	if next_namespace != _pending_namespace or (mode != "shared" and next_path != _pending_path):
		_reset_pending_memory()
		_pending_path = next_path
		_pending_namespace = next_namespace
	_load_pending()

func _legacy_shared_path() -> String:
	return "user://pending-command-shared-" + _pending_namespace.trim_prefix("user://pending-commands-shared-") + ".json"

func _journal_path(command_id: String) -> String:
	return _pending_namespace.path_join(command_id + ".json")

func _journal_paths() -> Array[String]:
	var paths: Array[String] = []
	if OS.has_feature("web"):
		var prefix: String = "three-kingdoms:pvp-receipt:" + _pending_namespace.get_file() + ":"
		var value: Variant = JavaScriptBridge.eval("(() => { try { const prefix = " + JSON.stringify(prefix) + "; return JSON.stringify(Object.keys(window.localStorage).filter(key => key.startsWith(prefix)).map(key => key.slice(prefix.length)).sort()); } catch (_) { return '[]'; } })()", true)
		var names: Variant = JSON.parse_string(str(value)) if value is String else []
		if names is Array:
			for name: Variant in names:
				if name is String and name.is_valid_filename() and name.ends_with(".json"):
					paths.append(_pending_namespace.path_join(name))
	else:
		var directory: DirAccess = DirAccess.open(_pending_namespace)
		if directory != null:
			for name: String in directory.get_files():
				if name.ends_with(".json"):
					paths.append(_pending_namespace.path_join(name))
	paths.sort()
	return paths

func _queue_pending_replays() -> void:
	if mode != "shared":
		if not _retry.is_empty() and _pending_matches_identity():
			_queue.push_front(_retry.duplicate(true))
			_retry.clear()
		return
	for request: Dictionary in _pending_replays:
		var id: String = str(request.body.get("commandId", ""))
		var queued: bool = str(_current.get("body", {}).get("commandId", "")) == id
		for item: Dictionary in _queue:
			queued = queued or str(item.get("body", {}).get("commandId", "")) == id
		if not queued:
			_queue.append(request.duplicate(true))
	_retry.clear()
	_pending_replays.clear()

func _uses_web_pending() -> bool:
	return OS.has_feature("web") and mode == "shared"

func _web_pending_key(path: String = "") -> String:
	if path.is_empty():
		path = _pending_path
	if path.get_base_dir().get_file().begins_with("pending-commands-shared-"):
		return "three-kingdoms:pvp-receipt:" + path.get_base_dir().get_file() + ":" + path.get_file()
	return "three-kingdoms:pvp-receipt:" + path.get_file()

func _pending_exists() -> bool:
	return _pending_exists_at(_pending_path)

func _pending_exists_at(path: String) -> bool:
	if _uses_web_pending():
		var value: Variant = JavaScriptBridge.eval("(() => { try { return window.localStorage.getItem(" + JSON.stringify(_web_pending_key(path)) + ") !== null ? 'present' : 'absent'; } catch (_) { return 'unavailable'; } })()", true)
		return value is String and value == "present"
	return FileAccess.file_exists(path)

func _read_pending() -> String:
	return _read_pending_at(_pending_path)

func _read_pending_at(path: String) -> String:
	if _uses_web_pending():
		var value: Variant = JavaScriptBridge.eval("(() => { try { return window.localStorage.getItem(" + JSON.stringify(_web_pending_key(path)) + ") || ''; } catch (_) { return ''; } })()", true)
		return str(value) if value is String else ""
	return FileAccess.get_file_as_string(path)

func _write_pending(contents: String) -> bool:
	_pending_storage_error = ""
	if _uses_web_pending():
		# One atomic localStorage key per original command, never a mutable
		# account-wide head/list; browser windows cannot lose each other's IDs.
		var value: Variant = JavaScriptBridge.eval("(() => { try { const key = " + JSON.stringify(_web_pending_key()) + "; const text = " + JSON.stringify(contents) + "; const old = window.localStorage.getItem(key); if (old !== null && old !== text) return 'entry-conflict'; window.localStorage.setItem(key, text); return window.localStorage.getItem(key) === text ? 'saved' : 'readback-failed'; } catch (error) { return 'storage-' + String(error.name || 'Error'); } })()", true)
		if value is String and value == "saved":
			return true
		_pending_storage_error = str(value) if value is String else "浏览器未确认保存 · 类型 " + str(typeof(value))
		return false
	if mode == "shared":
		var folder: String = ProjectSettings.globalize_path(_pending_path.get_base_dir())
		if DirAccess.make_dir_recursive_absolute(folder) != OK:
			return false
		# Unique temporary files and atomic rename prevent recovery reading a
		# partial receipt. Different original command IDs have different targets.
		var temporary: String = _pending_path + "." + Crypto.new().generate_random_bytes(12).hex_encode() + ".tmp"
		var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(contents)
		file.flush()
		var succeeded: bool = file.get_error() == OK
		file.close()
		if succeeded:
			succeeded = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(_pending_path)) == OK
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return succeeded
	var file: FileAccess = FileAccess.open(_pending_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	var succeeded: bool = file.get_error() == OK
	file.close()
	return succeeded

func _delete_pending(expected_id: String) -> void:
	_delete_pending_at(_pending_path, expected_id)

func _delete_pending_at(path: String, expected_id: String) -> void:
	if expected_id.is_empty() or not _pending_exists_at(path):
		return
	if _uses_web_pending():
		JavaScriptBridge.eval("(() => { try { const key = " + JSON.stringify(_web_pending_key(path)) + "; const record = JSON.parse(window.localStorage.getItem(key) || 'null'); if (record?.request?.body?.commandId === " + JSON.stringify(expected_id) + ") window.localStorage.removeItem(key); } catch (_) {} })()", true)
		return
	var stored: Variant = JSON.parse_string(_read_pending_at(path))
	if _valid_pending_record(stored) and str(stored.request.body.get("commandId", "")) == expected_id:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _stash_unconfirmed() -> void:
	if str(_current.get("path", "")) in ["command", "import"]:
		_retry = _current.duplicate(true)
		return
	for request: Dictionary in _queue:
		if str(request.get("path", "")) in ["command", "import"]:
			_retry = request.duplicate(true)
			return

func _poll_state() -> void:
	if not connected or _has_mutation():
		return
	_enqueue("state", HTTPClient.METHOD_GET)
	_world_elapsed += 2.0
	if _world_elapsed >= 6.0:
		_world_elapsed = 0.0
		_enqueue("world", HTTPClient.METHOD_GET)

func _has_mutation() -> bool:
	if str(_current.get("path", "")) in ["command", "import"]:
		return true
	for request: Dictionary in _queue:
		if str(request.path) in ["command", "import"]:
			return true
	return not _retry.is_empty()

func _enqueue(path: String, method: int, body: Dictionary = {}) -> void:
	if method == HTTPClient.METHOD_GET:
		if str(_current.get("path", "")) == path:
			return
		for request: Dictionary in _queue:
			if str(request.path) == path:
				return
	var request: Dictionary = {"path": path, "method": method, "body": body}
	if path in ["command", "import"] and not _save_pending(request):
		return
	_queue.append(request)
	_pump()

func _pump() -> void:
	if not _current.is_empty() or _queue.is_empty():
		return
	_current = _queue.pop_front()
	var headers: PackedStringArray = _request_headers()
	var body: String = "" if _current.body.is_empty() else JSON.stringify(_current.body)
	var error: Error = _http.request(base_url + "/" + str(_current.path), headers, _current.method, body)
	if error != OK:
		_fail_transport("请求无法开始：" + str(error))

func _on_completed(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	if _current.is_empty():
		return
	var request: Dictionary = _current.duplicate(true)
	if result != HTTPRequest.RESULT_SUCCESS or code == 0:
		_fail_transport("连接中断。可重连；未确认的操作会用原编号重试")
		return
	_current.clear()
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		_current = request
		_fail_transport("规则服务返回了无效数据，可重连后核对操作")
		return
	var payload: Dictionary = parsed
	if str(request.path) == "practice" and code >= 400 and code not in [401, 403]:
		var detail: Variant = payload.get("error", {})
		practice_failed.emit(str(detail.get("message", "演练请求未确认")) if detail is Dictionary else str(detail), str(detail.get("code", "INTERNAL_ERROR")) if detail is Dictionary else "INTERNAL_ERROR")
		_pump()
		return
	if code >= 500:
		_current = request
		_fail_transport("规则服务未确认操作，可重连后核对")
		return
	if code >= 400:
		if code == 401 or code == 403:
			_current = request
			_fail_transport("连接未获授权，请检查设置后重连")
			return
		if str(request.path) in ["command", "import"]:
			_clear_pending(str(request.body.get("commandId", "")))
			if mode == "shared":
				_queue_pending_replays()
		var detail: Variant = payload.get("error", {})
		var message: String = str(detail.get("message", "操作失败")) if detail is Dictionary else str(detail)
		request_failed.emit(message)
		if code == 409:
			refresh()
		_pump()
		return
	match str(request.path):
		"practice":
			if mode != "local" or not _accept_snapshot_identity(payload) or str(payload.get("requestId", "")) != str(request.body.get("requestId", "")):
				practice_failed.emit("演练身份或回执已变化，请重新连接本机进度。", "UNCONFIRMED_IDENTITY")
			else:
				practice_received.emit(payload)
		"health":
			if not _accept_health(payload):
				return
			connected = true
			status_changed.emit(_connected_status(), true)
			_poll.start()
			if not _retry.is_empty():
				if not _pending_matches_identity():
					request_failed.emit("未确认操作属于另一账号或存档，请返回原账号和服务确认")
				else:
					_queue_pending_replays()
			refresh()
		"world":
			if not _accept_snapshot_identity(payload):
				_current = request
				_fail_transport("共享世界身份不一致，请重连原账号核对")
				return
			if _payload_is_stale(payload) or (_server_time(payload) > 0.0 and _server_time(payload) < _last_world_time):
				refresh()
				_pump()
				return
			_update_shared_world(payload)
			world_received.emit(payload)
		"export":
			export_received.emit(payload)
		"quote":
			if not _accept_snapshot_identity(payload):
				request_failed.emit("预览身份已变化，请重新连接自己的城池")
			elif int(payload.get("revision", -1)) < revision:
				request_failed.emit("进度已变化，请重新预览")
			else:
				quote_received.emit(payload)
		"state", "command", "import":
			if not _accept_snapshot_identity(payload):
				_current = request
				_fail_transport("游戏进度身份不一致，请重连原账号核对")
				return
			if str(request.path) in ["command", "import"]:
				_clear_pending(str(request.body.get("commandId", "")))
				if mode == "shared":
					_queue_pending_replays()
			if _payload_is_stale(payload):
				# A cached receipt confirms its command, not the current world.
				if str(request.path) == "command":
					command_completed.emit(str(request.body.get("type", "")), payload)
				refresh()
				_pump()
				return
			_update_shared_world(payload)
			revision = int(payload.get("revision", revision))
			last_snapshot = payload
			snapshot_received.emit(payload)
			if not connected:
				connected = true
				_poll.start()
				status_changed.emit(_connected_status(), true)
			if str(request.path) == "command":
				command_completed.emit(str(request.body.get("type", "")), payload)
			if str(request.path) != "state":
				_enqueue("world", HTTPClient.METHOD_GET)
	_pump()

func _web_access_token() -> String:
	# Credentials never enter query parameters, localStorage or pending receipts.
	# Remove the fragment before the first network request or subsequent sharing.
	var value: Variant = JavaScriptBridge.eval("(() => { const hash = window.location.hash; if (!hash.startsWith('#pvp-token=')) return ''; let value = ''; try { value = decodeURIComponent(hash.slice(11)); } catch (_) {} window.history.replaceState(window.history.state, '', window.location.pathname + window.location.search); return /^[A-Za-z0-9._~-]{8,512}$/.test(value) ? value : ''; })()", true)
	return str(value) if value is String else ""

func _accept_health(payload: Dictionary) -> bool:
	var next_mode: String = str(payload.get("mode", "local"))
	if next_mode not in ["local", "shared"]:
		_fail_transport("规则服务模式无效，请检查连接地址")
		return false
	var next_actor: Variant = payload.get("actor", {})
	var next_authority: String = str(payload.get("authorityId", ""))
	if next_mode == "shared" and (int(payload.get("protocol", 0)) != 1 or not bool(payload.get("ok", false)) or next_authority.is_empty() or not next_actor is Dictionary or str(next_actor.get("id", "")).is_empty()):
		_fail_transport("共享演练身份未确认，请检查账号密钥后重连")
		return false
	var next_room: Variant = payload.get("room", {})
	if payload.has("room") and (next_mode != "shared" or not LobbyApiScript.valid_room(next_room, str(next_actor.get("id", "")))):
		_fail_transport("房间身份未确认，请重新核对自己的恢复信息")
		return false
	if not _expected_identity.is_empty() and (next_mode != "shared" or str(next_actor.get("id", "")) != str(_expected_identity.get("actorId", "")) or next_authority != str(_expected_identity.get("authorityId", "")) or not next_room is Dictionary or str(next_room.get("id", "")) != str(_expected_identity.get("roomId", ""))):
		_fail_transport("房间服务返回了不同城主，请重连原席位核对")
		return false
	if next_mode == "local":
		next_actor = {}
		next_room = {}
	var changed: bool = mode != next_mode or str(actor.get("id", "")) != str(next_actor.get("id", "")) or _authority != next_authority or str(room.get("id", "")) != str(next_room.get("id", ""))
	mode = next_mode
	actor = next_actor.duplicate(true) if mode == "shared" else {}
	room = next_room.duplicate(true) if next_room is Dictionary else {}
	_authority = next_authority
	_switch_pending_identity()
	if changed:
		# A newly authenticated player never sees the previous player's snapshot.
		last_snapshot.clear()
		shared_world.clear()
		_last_world_time = 0.0
		revision = 0
		mode_changed.emit(mode)
	return true

func _pending_matches_identity() -> bool:
	if _authority.is_empty() or _authority != _pending_authority or mode != _pending_mode:
		return false
	return mode != "shared" or (not _pending_actor_id.is_empty() and _pending_actor_id == str(actor.get("id", "")))

func _accept_snapshot_identity(payload: Dictionary) -> bool:
	if mode != "shared":
		# Older local envelopes/fixtures omit identity; a present identity must
		# nevertheless agree with the health handshake.
		return str(payload.get("mode", "local")) != "shared" and (not payload.has("authorityId") or str(payload.authorityId) == _authority)
	var response_actor: Variant = payload.get("actor")
	var identity_matches: bool = str(payload.get("mode", "")) == "shared" and str(payload.get("authorityId", "")) == _authority and not _authority.is_empty() and response_actor is Dictionary and not str(actor.get("id", "")).is_empty() and str(response_actor.get("id", "")) == str(actor.id)
	if not identity_matches:
		return false
	if not room.is_empty():
		var response_room: Variant = payload.get("room")
		if not LobbyApiScript.valid_room(response_room, str(actor.id)) or str(response_room.get("id", "")) != str(room.get("id", "")):
			return false
	elif payload.has("room"):
		return false
	return true

func _update_shared_world(payload: Dictionary) -> void:
	if mode == "shared" and payload.get("shared") is Dictionary:
		var timestamp: float = _server_time(payload)
		if timestamp > 0.0 and timestamp < _last_world_time:
			return
		shared_world = payload.shared.duplicate(true)
		_last_world_time = maxf(_last_world_time, timestamp)
		if payload.get("room") is Dictionary:
			room = payload.room.duplicate(true)

func _server_time(payload: Dictionary) -> float:
	var value: Variant = payload.get("serverTime", 0)
	return float(value) if value is int or value is float else 0.0

func _payload_is_stale(payload: Dictionary) -> bool:
	var incoming_revision: int = int(payload.get("revision", revision))
	if incoming_revision < revision:
		return true
	# A newer public world may reveal a later settlement before private polling.
	# Cached command receipts must not resurrect that older view, even if their
	# actor revision is higher than the last private snapshot we received.
	if mode == "shared" or incoming_revision == revision:
		var timestamp: float = _server_time(payload)
		var known_time: float = maxf(_server_time(last_snapshot), _last_world_time)
		return timestamp > 0.0 and timestamp < known_time
	return false

func _connected_status() -> String:
	if mode == "shared":
		if not room.is_empty():
			return "已连接房间 · %s · %s · 自动结算" % [str(room.get("name", "房间")), str(actor.get("name", actor.get("id", "玩家")))]
		return "已连接共享演练 · %s · 自动结算" % str(actor.get("name", actor.get("id", "玩家")))
	return "已连接 · 进度自动保存"

func _fail_transport(message: String) -> void:
	_stash_unconfirmed()
	_current.clear()
	_queue.clear()
	connected = false
	_poll.stop()
	status_changed.emit(message, false)
	request_failed.emit(message)

func _exit_tree() -> void:
	if _local_pid > 0:
		OS.kill(_local_pid)

func disconnect_account() -> void:
	_stash_unconfirmed()
	_http.cancel_request()
	_current.clear()
	_queue.clear()
	_poll.stop()
	token = ""
	account_session = ""
	_expected_identity.clear()
	connected = false
	actor.clear()
	room.clear()
	last_snapshot.clear()
	shared_world.clear()
	revision = 0
	_authority = ""
	mode_changed.emit(mode)
	status_changed.emit("账号已退出，请重新登录后选择自己的房间", false)

func _request_headers() -> PackedStringArray:
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	if not account_session.is_empty():
		headers.append("X-Account-Session: " + account_session)
	if not str(_expected_identity.get("accountId", "")).is_empty():
		headers.append("X-Expected-Account: " + str(_expected_identity.accountId))
	return headers
