extends Node
class_name KingdomLobbyApi

## Room enrollment is separate from canonical game commands. Its request secret,
## session token and recovery key live only in this process, never in a save.
signal request_succeeded(payload: Dictionary)
signal status_changed(message: String, busy: bool, needs_retry: bool)
signal request_failed(message: String)

const ROOM_NAME_MAX: int = 40
const PLAYER_NAME_MAX: int = 20

var base_url: String = "http://127.0.0.1:17343"
var busy: bool = false
var needs_retry: bool = false
var last_result: Dictionary = {}
var _path: String = ""
var _body_text: String = ""
var _http: HTTPRequest
var _generation: int = 0

func _ready() -> void:
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if origin is String:
			base_url = origin
		JavaScriptBridge.eval("(() => { if (window.__tkLobbyUnloadGuard) return; window.__tkLobbyUnloadGuard = true; window.addEventListener('beforeunload', event => { if (window.__tkLobbyEnrollmentPending) { event.preventDefault(); event.returnValue = ''; } }); })()", true)

func configure_url(value: String) -> bool:
	if busy or needs_retry:
		request_failed.emit("请先重试或放弃当前未确认请求")
		return false
	value = value.strip_edges().trim_suffix("/")
	if not valid_service_url(value):
		request_failed.emit("房间演练仅支持本机 HTTP 服务地址")
		return false
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if not origin is String or value != origin:
			request_failed.emit("网页端请使用当前房间服务的页面")
			return false
	base_url = value
	return true

func create_room(room_name: String, capacity: int, player_name: String) -> bool:
	room_name = room_name.strip_edges()
	player_name = player_name.strip_edges()
	if not _text(room_name, ROOM_NAME_MAX) or not _text(player_name, PLAYER_NAME_MAX) or capacity < 1 or capacity > 8:
		request_failed.emit("请填写房间名、城主名，人数请选择 1～8")
		return false
	return _start("create", {"requestId": Crypto.new().generate_random_bytes(32).hex_encode(), "roomName": room_name, "capacity": capacity, "playerName": player_name})

func join_room(invite_code: String, player_name: String) -> bool:
	invite_code = invite_code.strip_edges()
	player_name = player_name.strip_edges()
	if not valid_secret(invite_code) or not _text(player_name, PLAYER_NAME_MAX):
		request_failed.emit("请填写邀请码与自己的城主名")
		return false
	return _start("join", {"requestId": Crypto.new().generate_random_bytes(32).hex_encode(), "inviteCode": invite_code, "playerName": player_name})

func resume_room(room_id: String, recovery_key: String) -> bool:
	room_id = room_id.strip_edges()
	recovery_key = recovery_key.strip_edges()
	if not _text(room_id, 160) or not valid_secret(recovery_key):
		request_failed.emit("请填写房间编号和自己的恢复密钥")
		return false
	return _start("resume", {"roomId": room_id, "recoveryKey": recovery_key})

func retry_pending() -> bool:
	if busy or not needs_retry or _path.is_empty() or _body_text.is_empty():
		return false
	needs_retry = false
	busy = true
	status_changed.emit("正在核对原请求…", true, false)
	_send()
	return true

func cancel_pending() -> void:
	_generation += 1
	if is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
		_http = null
	_clear_request()
	status_changed.emit("已放弃本次请求；若服务已登记席位，它仍会保留", false, false)

func _start(path: String, body: Dictionary) -> bool:
	if busy or needs_retry:
		request_failed.emit("上一项房间请求尚未确认，请重试或放弃后再操作")
		return false
	if not valid_service_url(base_url):
		request_failed.emit("请先填写有效的本机房间服务地址")
		return false
	_path = path
	# Keep the exact encoded body, not a mutable reference to form fields.
	_body_text = JSON.stringify(body)
	last_result.clear()
	busy = true
	_web_pending_notice(true)
	status_changed.emit("正在登记自己的席位…", true, false)
	_send()
	return true

func _send() -> void:
	_generation += 1
	var generation: int = _generation
	if is_instance_valid(_http):
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	add_child(_http)
	_http.request_completed.connect(func(result: int, code: int, headers: PackedStringArray, bytes: PackedByteArray) -> void:
		if generation == _generation:
			_on_completed(result, code, headers, bytes))
	var error: Error = _http.request(base_url + "/lobby/" + _path, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, _body_text)
	if error != OK:
		_uncertain("房间服务未确认请求，请重试同一请求")

func _on_completed(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	if not busy:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code == 0 or code >= 500:
		_uncertain("连接中断或服务未确认。请重试原请求，避免重复登记")
		return
	var parser: JSON = JSON.new()
	var parsed: Variant = parser.data if parser.parse(bytes.get_string_from_utf8()) == OK else null
	if code >= 400:
		_clear_request()
		var message: String = "房间请求被拒绝，请检查邀请码、剩余席位或恢复密钥"
		if parsed is Dictionary and parsed.get("error") is Dictionary:
			var error_message: Variant = parsed.error.get("message", "")
			if error_message is String and _text(error_message, 240):
				message = error_message
		status_changed.emit(message, false, false)
		request_failed.emit(message)
		return
	if not valid_result(parsed):
		_uncertain("房间身份响应不完整，请重试原请求核对；原城池仍保留")
		return
	last_result = parsed.duplicate(true)
	_clear_request()
	status_changed.emit("已取得自己的席位。请保存恢复密钥，再进入房间", false, false)
	request_succeeded.emit(last_result.duplicate(true))

func _uncertain(message: String) -> void:
	message += "。未确认时请保持客户端窗口开启；关闭或刷新会失去原请求的重试信息"
	busy = false
	needs_retry = true
	status_changed.emit(message, false, true)
	request_failed.emit(message)

func _clear_request() -> void:
	busy = false
	needs_retry = false
	_path = ""
	_body_text = ""
	_web_pending_notice(false)

func _web_pending_notice(pending: bool) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__tkLobbyEnrollmentPending = " + ("true" if pending else "false") + ";", true)

static func _text(value: Variant, maximum: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value)) and int(value) >= minimum and int(value) <= maximum

static func valid_secret(value: Variant) -> bool:
	if not value is String:
		return false
	var pattern: RegEx = RegEx.new()
	pattern.compile("^[a-f0-9]{64}$")
	return pattern.search(value) != null

static func valid_service_url(value: String) -> bool:
	var pattern: RegEx = RegEx.new()
	pattern.compile("^http://(127\\.0\\.0\\.1|localhost|\\[::1\\])(?::([0-9]{1,5}))?$")
	var found: RegExMatch = pattern.search(value)
	return found != null and (found.get_string(2).is_empty() or int(found.get_string(2)) >= 1 and int(found.get_string(2)) <= 65535)

static func valid_room(value: Variant, actor_id: String = "") -> bool:
	if not value is Dictionary or not _text(value.get("id"), 160) or not _text(value.get("name"), ROOM_NAME_MAX) or not _integer(value.get("capacity"), 1, 8) or not value.get("members") is Array:
		return false
	var members: Array = value.members
	if members.is_empty() or members.size() > int(value.capacity):
		return false
	var ids: Dictionary = {}
	var seats: Dictionary = {}
	var actor_seat: int = 0
	for member: Variant in members:
		if not member is Dictionary or not _text(member.get("id"), 160) or not _text(member.get("name"), PLAYER_NAME_MAX) or not _integer(member.get("seat"), 1, int(value.capacity)) or member.get("team") not in ["blue", "red"]:
			return false
		if ids.has(member.id) or seats.has(int(member.seat)):
			return false
		ids[member.id] = true
		seats[int(member.seat)] = true
		if str(member.id) == actor_id:
			actor_seat = int(member.seat)
	if not actor_id.is_empty() and actor_seat == 0:
		return false
	if value.has("seat") and (not _integer(value.seat, 1, int(value.capacity)) or not actor_id.is_empty() and int(value.seat) != actor_seat):
		return false
	return true

static func valid_result(value: Variant) -> bool:
	if not value is Dictionary or value.get("ok") != true or not _integer(value.get("protocol"), 1, 1) or not value.get("actor") is Dictionary:
		return false
	var actor: Dictionary = value.actor
	if not _text(actor.get("id"), 160) or not _text(actor.get("name"), PLAYER_NAME_MAX) or not _text(value.get("authorityId"), 160) or not valid_secret(value.get("accessToken")) or not valid_secret(value.get("recoveryKey")) or not valid_secret(value.get("inviteCode")) or not valid_room(value.get("room"), str(actor.id)):
		return false
	for member: Dictionary in value.room.members:
		if str(member.id) == str(actor.id) and str(member.name) != str(actor.name):
			return false
	return true
