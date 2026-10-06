extends Node
class_name KingdomLobbyApi

## Room enrollment is separate from canonical game commands. Its request secret,
## session token and recovery key live only in this process, never in a save.
signal request_succeeded(payload: Dictionary)
signal status_changed(message: String, busy: bool, needs_retry: bool)
signal request_failed(message: String)
signal account_changed(user: Dictionary, cloud: bool)
signal account_status(message: String, busy: bool)
signal rooms_received(rooms: Array)
signal account_signed_out()

const ROOM_NAME_MAX: int = 40
const PLAYER_NAME_MAX: int = 20

var base_url: String = "http://127.0.0.1:17343"
var busy: bool = false
var needs_retry: bool = false
var last_result: Dictionary = {}
var _path: String = ""
var _body_text: String = ""
var _enrollment_account_id: String = ""
var _http: HTTPRequest
var _generation: int = 0
# These account credentials are deliberately excluded from canonical journals.
var cloud_enabled: bool = false
var account_session: String = ""
var account_user: Dictionary = {}
var account_rooms: Array = []
var account_busy: bool = false
var _account_http: HTTPRequest
var _account_generation: int = 0

func _ready() -> void:
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if origin is String:
			base_url = origin
		JavaScriptBridge.eval("(() => { if (window.__tkLobbyUnloadGuard) return; window.__tkLobbyUnloadGuard = true; window.addEventListener('beforeunload', event => { if (window.__tkLobbyEnrollmentPending) { event.preventDefault(); event.returnValue = ''; } }); })()", true)

func configure_url(value: String) -> bool:
	if busy or needs_retry or account_busy and value.strip_edges().trim_suffix("/") != base_url:
		request_failed.emit("请先完成账号请求，或重试、放弃当前未确认请求")
		return false
	value = value.strip_edges().trim_suffix("/")
	if not valid_service_url(value):
		request_failed.emit("请使用 HTTPS 服务根地址；本机演练可使用 HTTP")
		return false
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if not origin is String or value != origin:
			request_failed.emit("网页端请使用当前房间服务的页面")
			return false
	if value != base_url:
		_clear_account()
		cloud_enabled = value.begins_with("https://")
		account_changed.emit({}, cloud_enabled)
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
	if cloud_enabled:
		request_failed.emit("在线房间请登录账号，从我的房间恢复城池")
		return false
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
		request_failed.emit("请先填写有效的房间服务根地址")
		return false
	if cloud_enabled and account_user.is_empty():
		request_failed.emit("请先登录内测账号")
		return false
	_path = path
	_enrollment_account_id = str(account_user.get("id", "")) if cloud_enabled else ""
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
	var error: Error = _http.request(base_url + "/lobby/" + _path, _account_headers(_enrollment_account_id, false), HTTPClient.METHOD_POST, _body_text)
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
		if cloud_enabled and code in [401, 403]:
			_clear_account()
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
	status_changed.emit("已取得自己的席位。可以进入房间" if cloud_enabled else "已取得自己的席位。请保存恢复密钥，再进入房间", false, false)
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
	_enrollment_account_id = ""
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
	# Origin only. Never permit credentials, paths or token-bearing queries.
	var pattern: RegEx = RegEx.new()
	pattern.compile("^(https?)://([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?|\\[::1\\])(?::([0-9]{1,5}))?$")
	var found: RegExMatch = pattern.search(value)
	if found == null or not found.get_string(3).is_empty() and (int(found.get_string(3)) < 1 or int(found.get_string(3)) > 65535):
		return false
	var host: String = found.get_string(2).to_lower()
	return found.get_string(1) == "https" or host in ["127.0.0.1", "localhost", "[::1]"]

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

func _account_headers(expected_id: String = "", use_current: bool = true) -> PackedStringArray:
	var headers: PackedStringArray = ["Content-Type: application/json"]
	if not account_session.is_empty():
		headers.append("X-Account-Session: " + account_session)
	if use_current:
		expected_id = str(account_user.get("id", ""))
	if not expected_id.is_empty():
		headers.append("X-Expected-Account: " + expected_id)
	return headers

func inspect_service() -> bool:
	if account_busy or busy or needs_retry:
		return false
	return _send_account(HTTPClient.METHOD_GET, "/auth/config")

func login(email: String, password: String) -> bool:
	if not cloud_enabled or account_busy or busy or needs_retry:
		request_failed.emit("请先检查在线服务，完成当前请求后再登录")
		return false
	email = email.strip_edges()
	if not _text(email, 254) or not email.contains("@") or password.is_empty() or password.length() > 4096:
		request_failed.emit("请输入内测账号邮箱和密码")
		return false
	return _send_account(HTTPClient.METHOD_POST, "/auth/login", {"email": email, "password": password})

func check_account() -> bool:
	return _send_account(HTTPClient.METHOD_GET, "/auth/me") if cloud_enabled and not account_busy else false

func refresh_rooms() -> bool:
	if not cloud_enabled or account_user.is_empty() or account_busy:
		return false
	return _send_account(HTTPClient.METHOD_GET, "/lobby/mine")

func resume_account_room(room_id: String) -> bool:
	if not cloud_enabled or not _text(room_id, 160):
		return false
	return _start("account-resume", {"roomId": room_id})

func logout() -> void:
	# Revoke remotely with the old session; local identity becomes unsafe now.
	if account_busy:
		_account_generation += 1
		if is_instance_valid(_account_http):
			_account_http.cancel_request()
		account_busy = false
	cancel_pending()
	var old_session: String = account_session
	var old_account_id: String = str(account_user.get("id", ""))
	_clear_account(true)
	_send_account(HTTPClient.METHOD_POST, "/auth/logout", {}, old_session, old_account_id)

func _clear_account(force_disconnect: bool = false) -> void:
	var had_account: bool = not account_user.is_empty() or not account_session.is_empty()
	# A request registered for another account must not survive sign-out/change.
	_generation += 1
	if is_instance_valid(_http):
		_http.cancel_request()
	_clear_request()
	account_session = ""
	account_user.clear()
	account_rooms.clear()
	last_result.clear()
	if had_account or force_disconnect:
		account_signed_out.emit()
	account_changed.emit({}, cloud_enabled)

func _send_account(method: HTTPClient.Method, path: String, body: Dictionary = {}, session_override: String = "", expected_override: String = "") -> bool:
	if account_busy or not valid_service_url(base_url):
		return false
	_account_generation += 1
	var generation: int = _account_generation
	if is_instance_valid(_account_http):
		_account_http.queue_free()
	_account_http = HTTPRequest.new()
	_account_http.timeout = 12.0
	add_child(_account_http)
	_account_http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
		if generation == _account_generation:
			_on_account_completed(path, result, code, bytes))
	account_busy = true
	account_status.emit("正在核对账号服务…", true)
	var headers: PackedStringArray = _account_headers()
	if path == "/auth/login":
		headers = PackedStringArray(["Content-Type: application/json"])
	elif path == "/auth/logout":
		headers = PackedStringArray(["Content-Type: application/json"])
		if not session_override.is_empty():
			headers.append("X-Account-Session: " + session_override)
		if not expected_override.is_empty():
			headers.append("X-Expected-Account: " + expected_override)
	# Password exists only for this transport call. It is never retained for retry.
	var error: Error = _account_http.request(base_url + path, headers, method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if error != OK:
		account_busy = false
		account_status.emit("账号服务连接失败，请重新登录或检查服务地址", false)
	return error == OK

func _on_account_completed(path: String, result: int, code: int, bytes: PackedByteArray) -> void:
	account_busy = false
	var parser: JSON = JSON.new()
	var payload: Variant = parser.data if parser.parse(bytes.get_string_from_utf8()) == OK else null
	if path == "/auth/logout":
		account_status.emit("已退出账号；本客户端已停止读取游戏进度" if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 else "本客户端已停止游戏连接；服务未确认退出，请重新登录后再次退出", false)
		return
	if result != HTTPRequest.RESULT_SUCCESS or code == 0 or code >= 500:
		account_status.emit("账号服务连接失败，请检查地址后重试；密码不会保留", false)
		return
	if code >= 400:
		if code == 401 or code == 403:
			_clear_account()
		account_status.emit("请登录有效的内测账号" if code in [401, 403] else "账号请求被拒绝，请检查输入", false)
		return
	if not payload is Dictionary:
		account_status.emit("账号响应不完整，未采用新的身份", false)
		return
	match path:
		"/auth/config":
			if not payload.get("enabled") is bool:
				account_status.emit("服务未返回有效的账号配置", false)
				return
			cloud_enabled = payload.enabled
			account_changed.emit(account_user.duplicate(true), cloud_enabled)
			account_status.emit("请登录内测账号" if cloud_enabled else "本机房间演练，无需账号登录", false)
			if cloud_enabled:
				check_account()
		"/auth/login", "/auth/me":
			if payload.get("ok") != true or not valid_user(payload.get("user")) or path == "/auth/login" and not valid_secret(payload.get("sessionToken")):
				account_status.emit("账号身份响应不完整，未采用新的身份", false)
				return
			if path == "/auth/me" and not account_user.is_empty() and str(account_user.id) != str(payload.user.id):
				_clear_account(true)
				account_status.emit("浏览器账号已改变，已停止旧城主连接；请重新登录", false)
				return
			if path == "/auth/login":
				if not account_user.is_empty() and str(account_user.id) != str(payload.user.id):
					_clear_account()
				account_session = payload.sessionToken
			account_user = payload.user.duplicate(true)
			account_changed.emit(account_user.duplicate(true), true)
			account_status.emit("已登录，正在读取自己的房间…", false)
			refresh_rooms()
		"/lobby/mine":
			if not valid_room_list(payload):
				account_status.emit("房间列表响应不完整，未显示未经核对的席位", false)
				return
			account_rooms = payload.rooms.duplicate(true)
			rooms_received.emit(account_rooms.duplicate(true))
			account_status.emit("已读取自己的房间；可恢复原城池或创建、加入房间", false)

static func valid_user(value: Variant) -> bool:
	return value is Dictionary and _text(value.get("id"), 160) and _text(value.get("email"), 254)

static func valid_room_list(value: Variant) -> bool:
	if not value is Dictionary or value.get("ok") != true or not value.get("rooms") is Array:
		return false
	var seen: Dictionary = {}
	for entry: Variant in value.rooms:
		if not entry is Dictionary or not entry.get("actor") is Dictionary or not _text(entry.actor.get("id"), 160) or not _text(entry.actor.get("name"), PLAYER_NAME_MAX) or not _text(entry.get("authorityId"), 160) or not valid_room(entry.get("room"), str(entry.actor.id)) or not _integer(entry.get("seat"), 1, int(entry.room.capacity)) or seen.has(entry.room.id):
			return false
		var found: bool = false
		for member: Dictionary in entry.room.members:
			if str(member.id) == str(entry.actor.id) and int(member.seat) == int(entry.seat) and str(member.name) == str(entry.actor.name):
				found = true
		if not found:
			return false
		seen[entry.room.id] = true
	return true
