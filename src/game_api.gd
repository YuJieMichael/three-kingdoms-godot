extends Node
class_name KingdomApi

signal snapshot_received(payload: Dictionary)
signal world_received(payload: Dictionary)
signal status_changed(message: String, connected: bool)
signal request_failed(message: String)
signal export_received(snapshot: Dictionary)
signal command_completed(type: String, payload: Dictionary)

var base_url: String = "http://127.0.0.1:17337"
var token: String = ""
var revision: int = 0
var connected: bool = false
var last_snapshot: Dictionary = {}
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
const PENDING_PATH: String = "user://pending-command.json"

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

func connect_to(url: String, access_token: String = "") -> void:
	base_url = url.trim_suffix("/")
	token = access_token
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
		connect_to(str(origin) + "/api")
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
	if _has_mutation():
		request_failed.emit("请等待当前操作完成")
		return
	_enqueue("import", HTTPClient.METHOD_POST, {"commandId": "gd_" + Crypto.new().generate_random_bytes(12).hex_encode(), "expectedRevision": revision, "state": snapshot})

func fetch_export() -> void:
	_enqueue("export", HTTPClient.METHOD_GET)

func refresh() -> void:
	_enqueue("state", HTTPClient.METHOD_GET)
	_enqueue("world", HTTPClient.METHOD_GET)

func retry_last() -> void:
	# Re-check authority before replaying the exact original operation.
	connect_to(base_url, token)

func _load_pending() -> void:
	if not FileAccess.file_exists(PENDING_PATH):
		return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PENDING_PATH))
	if value is Dictionary and value.get("request") is Dictionary:
		var request: Dictionary = value.request
		if str(request.get("path", "")) in ["command", "import"] and request.get("body") is Dictionary:
			_retry = request
			_pending_authority = str(value.get("authority", ""))

func _save_pending(request: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(PENDING_PATH, FileAccess.WRITE)
	if file == null:
		request_failed.emit("无法保存操作回执，操作未发送")
		return false
	file.store_string(JSON.stringify({"authority": _authority, "request": request}))
	file.close()
	_pending_authority = _authority
	return true

func _clear_pending() -> void:
	_retry.clear()
	_pending_authority = ""
	if FileAccess.file_exists(PENDING_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_PATH))

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
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var body: String = "" if _current.body.is_empty() else JSON.stringify(_current.body)
	var error: Error = _http.request(base_url + "/" + str(_current.path), headers, _current.method, body)
	if error != OK:
		_fail_transport("请求无法开始：" + str(error))

func _on_completed(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
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
			_clear_pending()
		var detail: Variant = payload.get("error", {})
		var message: String = str(detail.get("message", "操作失败")) if detail is Dictionary else str(detail)
		request_failed.emit(message)
		if code == 409:
			_enqueue("state", HTTPClient.METHOD_GET)
		_pump()
		return
	match str(request.path):
		"health":
			_authority = str(payload.get("authorityId", ""))
			connected = true
			status_changed.emit("已连接 · 进度自动保存", true)
			_poll.start()
			if not _retry.is_empty():
				if _authority.is_empty() or _authority != _pending_authority:
					request_failed.emit("未确认操作属于另一份存档，请返回原服务确认")
				else:
					_queue.push_front(_retry.duplicate(true))
					_retry.clear()
			refresh()
		"world":
			world_received.emit(payload)
		"export":
			export_received.emit(payload)
		"state", "command", "import":
			if str(request.path) in ["command", "import"]:
				_clear_pending()
			revision = int(payload.get("revision", revision))
			last_snapshot = payload
			snapshot_received.emit(payload)
			if not connected:
				connected = true
				_poll.start()
				status_changed.emit("已重连 · 操作已确认", true)
			if str(request.path) == "command":
				command_completed.emit(str(request.body.get("type", "")), payload)
			if str(request.path) != "state":
				_enqueue("world", HTTPClient.METHOD_GET)
	_pump()

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
