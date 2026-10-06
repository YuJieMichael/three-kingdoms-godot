extends AcceptDialog
class_name KingdomLobbyDialog

signal connection_requested(url: String, access_token: String, expected_identity: Dictionary)
signal advanced_requested()
signal reconnect_requested()

var _api: KingdomLobbyApi
var _scroll: ScrollContainer
var _content: VBoxContainer
var _current: Label
var _status: Label
var _server: LineEdit
var _action: OptionButton
var _forms: Array[VBoxContainer] = []
var _room_name: LineEdit
var _capacity: SpinBox
var _create_name: LineEdit
var _invite: LineEdit
var _join_name: LineEdit
var _resume_room: LineEdit
var _resume_key: LineEdit
var _submit: Button
var _retry: Button
var _cancel: Button
var _result_box: VBoxContainer
var _result_title: Label
var _result_room: LineEdit
var _result_invite: LineEdit
var _result_key: LineEdit
var _enter: Button
var _result: Dictionary = {}
var _result_url: String = ""
var _form_controls: Array[Control] = []
var _entry_sent: bool = false
var _close_notice: AcceptDialog
var _allow_hide: bool = false
var _intro: Label
var _auth_box: VBoxContainer
var _email: LineEdit
var _password: LineEdit
var _login: Button
var _logout: Button
var _account_label: Label
var _rooms_box: VBoxContainer
var _key_controls: Array[Control] = []
var _join_hint: Label
var _result_hint: Label
var _room_heading: Label
var _inspected_url: String = ""
var _account_was_signed_in: bool = false

func _ready() -> void:
	if get_parent() is Control and (get_parent() as Control).theme != null:
		theme = (get_parent() as Control).theme
	title = "联机大厅 · 本机房间演练"
	dialog_hide_on_ok = false
	get_ok_button().text = "关闭"
	confirmed.connect(_request_close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 14.0
	_scroll.offset_right = -14.0
	_scroll.offset_top = 12.0
	_scroll.offset_bottom = -54.0
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	_scroll.add_child(_content)
	_intro = _label("创建或加入 1～8 人的独立房间。本机演练无需账号；在线服务需使用内测账号登录。")
	_content.add_child(_intro)
	_current = _label("尚未连接房间")
	_content.add_child(_current)
	_content.add_child(_button("重连当前城主", func() -> void: reconnect_requested.emit()))
	_content.add_child(_label("房间服务地址"))
	_server = _field(_content, "http://127.0.0.1:17343")
	_form_controls.erase(_server)
	_server.editable = not OS.has_feature("web")
	_content.add_child(_button("检查服务 / 切换地址", func() -> void:
		if _api != null and _api.configure_url(_server.text):
			_clear_result()
			_api.inspect_service()))
	_auth_box = VBoxContainer.new()
	_content.add_child(_auth_box)
	_account_label = _label("在线内测：请输入已开通的账号，当前不能自行注册。")
	_auth_box.add_child(_account_label)
	_email = _field(_auth_box, "内测账号邮箱", 254)
	_password = _field(_auth_box, "密码", 4096)
	_password.secret = true
	_form_controls.erase(_email)
	_form_controls.erase(_password)
	_login = _button("登录内测账号", func() -> void:
		if _api != null:
			_api.login(_email.text, _password.text)
		_password.clear())
	_auth_box.add_child(_login)
	_logout = _button("退出账号并停止游戏连接", func() -> void:
		_password.clear()
		if _api != null:
			_api.logout())
	_auth_box.add_child(_logout)
	_auth_box.add_child(_button("刷新我的房间", func() -> void:
		if _api != null:
			_api.refresh_rooms()))
	_rooms_box = VBoxContainer.new()
	_auth_box.add_child(_rooms_box)
	_auth_box.hide()
	_action = OptionButton.new()
	for text: String in ["创建房间", "邀请码加入", "恢复自己的席位"]:
		_action.add_item(text)
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action.custom_minimum_size.y = 38
	_content.add_child(_action)
	_form_controls.append(_action)
	_action.item_selected.connect(func(_index: int) -> void: _update_form())
	var create_form: VBoxContainer = VBoxContainer.new()
	_forms.append(create_form)
	_content.add_child(create_form)
	create_form.add_child(_label("房间名称"))
	_room_name = _field(create_form, "我的攻防演练", KingdomLobbyApi.ROOM_NAME_MAX)
	create_form.add_child(_label("人数上限 · 1～8 人"))
	_capacity = SpinBox.new()
	_capacity.min_value = 1
	_capacity.max_value = 8
	_capacity.step = 1
	_capacity.value = 4
	_capacity.custom_minimum_size.y = 38
	_capacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_form.add_child(_capacity)
	_form_controls.append(_capacity)
	create_form.add_child(_label("你的城主名"))
	_create_name = _field(create_form, "请输入城主名", KingdomLobbyApi.PLAYER_NAME_MAX)
	var join_form: VBoxContainer = VBoxContainer.new()
	_forms.append(join_form)
	_content.add_child(join_form)
	join_form.add_child(_label("邀请码"))
	_invite = _field(join_form, "由房间创建者提供", 128)
	join_form.add_child(_label("你的城主名"))
	_join_name = _field(join_form, "加入会分配一个新席位", KingdomLobbyApi.PLAYER_NAME_MAX)
	_join_hint = _label("邀请码用于新城主加入。返回已有城池请使用自己的恢复密钥。", 14)
	join_form.add_child(_join_hint)
	var resume_form: VBoxContainer = VBoxContainer.new()
	_forms.append(resume_form)
	_content.add_child(resume_form)
	resume_form.add_child(_label("房间编号"))
	_resume_room = _field(resume_form, "创建或加入时显示的房间编号", 160)
	resume_form.add_child(_label("你自己的恢复密钥"))
	_resume_key = _field(resume_form, "私密信息，请勿分享给其他玩家", 512)
	_resume_key.secret = true
	_status = _label("创建或加入后，请自行保存恢复密钥。客户端不会保存登录密钥。", 14)
	_content.add_child(_status)
	_submit = _button("创建房间", _submit_form)
	_content.add_child(_submit)
	_retry = _button("重试原请求", func() -> void:
		if _api != null:
			_api.retry_pending())
	_content.add_child(_retry)
	_cancel = _button("放弃本次未确认请求", func() -> void:
		if _api != null:
			_api.cancel_pending())
	_content.add_child(_cancel)
	_retry.hide()
	_cancel.hide()
	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 10)
	_content.add_child(_result_box)
	_result_box.add_child(HSeparator.new())
	_result_title = _label("你的房间席位", 20)
	_result_box.add_child(_result_title)
	_room_heading = _label("房间编号 · 恢复席位时需要")
	_result_box.add_child(_room_heading)
	_result_room = _field(_result_box, "")
	_result_room.editable = false
	_result_box.add_child(_label("邀请码 · 可交给其他城主加入"))
	_result_invite = _field(_result_box, "")
	_result_invite.editable = false
	_result_box.add_child(_button("复制邀请码", func() -> void: DisplayServer.clipboard_set(_result_invite.text)))
	var key_heading: Label = _label("你的恢复密钥 · 仅自己保存")
	_result_box.add_child(key_heading)
	_key_controls.append(key_heading)
	_result_key = _field(_result_box, "")
	_result_key.editable = false
	_result_key.secret = true
	_key_controls.append(_result_key)
	_result_box.add_child(_button("显示 / 隐藏恢复密钥", func() -> void: _result_key.secret = not _result_key.secret))
	_result_box.add_child(_button("复制房间编号与自己的密钥", func() -> void:
		DisplayServer.clipboard_set(_result_room.text + "\n" + _result_key.text)
		_status.text = "已复制自己的恢复信息，请保存到私人位置；不要交给其他玩家"))
	# The two recovery buttons and heading must never be exposed in cloud mode.
	_key_controls.append(_result_box.get_child(_result_box.get_child_count() - 1))
	_key_controls.append(_result_box.get_child(_result_box.get_child_count() - 2))
	_result_hint = _label("关闭客户端或刷新网页后，需要房间编号＋自己的恢复密钥才能回到原城池。共享邀请码不能恢复已有席位。", 14)
	_result_box.add_child(_result_hint)
	_enter = _button("保存恢复信息后进入房间", _enter_room)
	_result_box.add_child(_enter)
	_result_box.hide()
	_content.add_child(HSeparator.new())
	_content.add_child(_button("高级连接：地址与访问令牌", func() -> void: advanced_requested.emit()))
	_update_form()
	visibility_changed.connect(func() -> void:
		if not visible:
			_result_key.secret = true
			_resume_key.secret = true
			if not _allow_hide and _api != null and _api.needs_retry:
				call_deferred("_unconfirmed_close_notice"))

func _request_close() -> void:
	if _api != null and _api.needs_retry:
		_unconfirmed_close_notice()
	else:
		hide()

func _unconfirmed_close_notice() -> void:
	if _api == null or not _api.needs_retry:
		return
	_fit_window()
	if not visible:
		popup_centered(size)
	if not is_instance_valid(_close_notice):
		_close_notice = AcceptDialog.new()
		_close_notice.title = "房间登记尚未确认"
		_close_notice.dialog_autowrap = true
		_close_notice.get_ok_button().text = "重试原请求"
		_close_notice.dialog_text = "请保持客户端窗口开启。关闭客户端或刷新网页会失去原请求的重试信息，已登记的席位可能无法找回。\n收起大厅不会清除请求，可从联机入口再次打开。"
		_close_notice.add_button("暂时收起", false, "hide")
		_close_notice.custom_action.connect(func(action: StringName) -> void:
			if action == &"hide":
				_close_notice.hide()
				_allow_hide = true
				hide()
				_allow_hide = false)
		add_child(_close_notice)
	_close_notice.min_size = Vector2i(mini(480, maxi(260, size.x - 20)), 200)
	_close_notice.popup_centered(_close_notice.min_size)

func setup(service: KingdomLobbyApi) -> void:
	if _api != null:
		_api.request_succeeded.disconnect(_received_result)
		_api.status_changed.disconnect(_lobby_status)
		_api.request_failed.disconnect(_show_error)
		_api.account_changed.disconnect(_account_changed)
		_api.account_status.disconnect(_account_status)
		_api.rooms_received.disconnect(_rooms_received)
	_api = service
	_api.request_succeeded.connect(_received_result)
	_api.status_changed.connect(_lobby_status)
	_api.request_failed.connect(_show_error)
	_api.account_changed.connect(_account_changed)
	_api.account_status.connect(_account_status)
	_api.rooms_received.connect(_rooms_received)
	_account_changed(_api.account_user, _api.cloud_enabled)
	_server.text = _api.base_url
	_lobby_status("创建或加入后，请自行保存恢复密钥；客户端不会保存密钥", _api.busy, _api.needs_retry)

func show_lobby(actor: Dictionary = {}, room: Dictionary = {}, connected: bool = false, invite_code: String = "") -> void:
	_update_current(actor, room, connected)
	if not invite_code.is_empty() and (_api == null or not _api.busy and not _api.needs_retry):
		_invite.text = invite_code
		_action.select(1)
		_update_form()
	_fit_window()
	popup_centered(size)
	if _api != null and _inspected_url != _api.base_url:
		_inspected_url = _api.base_url
		_api.inspect_service()

func _fit_window() -> void:
	var available: Vector2 = Vector2(get_tree().root.get_visible_rect().size)
	if get_parent() is Control:
		available = (get_parent() as Control).size
	min_size = Vector2i(mini(620, maxi(280, int(available.x) - 40)), mini(690, maxi(280, int(available.y) - 70)))
	size = min_size
	position = Vector2i(clampi(position.x, 10, maxi(10, int(available.x) - size.x - 10)), clampi(position.y, 25, maxi(25, int(available.y) - size.y - 20)))

func connection_status(message: String, connected: bool, actor: Dictionary, room: Dictionary, authority: String) -> void:
	_update_current(actor, room, connected)
	if _entry_sent:
		_status.text = message
		if not connected and message == "正在连接规则服务…":
			_enter.disabled = true
			return
		if connected and str(actor.get("id", "")) == str(_result.get("actor", {}).get("id", "")) and str(room.get("id", "")) == str(_result.get("room", {}).get("id", "")) and authority == str(_result.get("authorityId", "")):
			_enter.text = "已进入房间 · 可关闭大厅"
			_enter.disabled = true
		else:
			_enter.disabled = false
			_enter.text = "重新核对身份并进入"

func clear_other_identity(actor: Dictionary, room: Dictionary, authority: String) -> void:
	if not _result.is_empty() and (str(actor.get("id", "")) != str(_result.get("actor", {}).get("id", "")) or str(room.get("id", "")) != str(_result.get("room", {}).get("id", "")) or authority != str(_result.get("authorityId", ""))):
		_clear_result()
		if _api != null:
			_api.last_result.clear()

func _update_current(actor: Dictionary, room: Dictionary, connected: bool) -> void:
	if not room.is_empty():
		_current.text = "当前：%s · %s · %s\n%d / %d 个城主" % [str(room.get("name", "房间")), str(actor.get("name", "城主")), "已连接" if connected else "连接中断", room.get("members", []).size(), int(room.get("capacity", 1))]
	elif not actor.is_empty():
		_current.text = "当前：四账号共享演练 · %s · %s" % [str(actor.get("name", "城主")), "已连接" if connected else "连接中断"]
	else:
		_current.text = "当前：私人试玩；房间进度与私人存档分开"

func _update_form() -> void:
	for index: int in range(_forms.size()):
		_forms[index].visible = index == _action.selected
	_submit.text = ["创建房间", "加入新席位", "恢复自己的城池"][_action.selected]

func _submit_form() -> void:
	if _api == null or _api.busy or _api.needs_retry:
		return
	if not _api.configure_url(_server.text):
		return
	var accepted: bool = false
	match _action.selected:
		0:
			_capacity.apply()
			accepted = _api.create_room(_room_name.text, int(_capacity.value), _create_name.text)
		1:
			accepted = _api.join_room(_invite.text, _join_name.text)
		2:
			accepted = _api.resume_room(_resume_room.text, _resume_key.text)
	if accepted:
		_clear_result()

func _clear_result() -> void:
	_result.clear()
	_result_url = ""
	_entry_sent = false
	_result_room.clear()
	_result_invite.clear()
	_result_key.clear()
	_result_key.secret = true
	_result_box.hide()

func _received_result(payload: Dictionary) -> void:
	_result = payload.duplicate(true)
	_result_url = _api.base_url + "/api"
	_entry_sent = false
	var own_seat: int = _own_seat(payload)
	_result_title.text = "%s · %s · 席位 %d\n%s" % [str(payload.room.name), str(payload.actor.name), own_seat, "初始青组" if own_seat % 2 == 1 else "初始赤组"]
	_result_room.text = str(payload.room.id)
	_result_invite.text = str(payload.inviteCode)
	_result_key.text = "" if _api.cloud_enabled else str(payload.recoveryKey)
	_resume_key.clear()
	_result_key.secret = true
	_enter.text = "进入自己的房间" if _api.cloud_enabled else "保存恢复信息后进入房间"
	_enter.disabled = false
	_result_box.show()
	call_deferred("_scroll_to_result")

func _scroll_to_result() -> void:
	if is_instance_valid(_scroll) and _result_box.visible:
		_scroll.scroll_vertical = int(_result_box.position.y)

func _own_seat(payload: Dictionary) -> int:
	for member: Dictionary in payload.room.members:
		if str(member.id) == str(payload.actor.id):
			return int(member.seat)
	return 0

func _enter_room() -> void:
	if _result.is_empty() or _api == null or _api.busy or _api.needs_retry:
		return
	_entry_sent = true
	_enter.disabled = true
	_status.text = "正在核对自己的房间身份…"
	var identity: Dictionary = {"actorId": str(_result.actor.id), "authorityId": str(_result.authorityId), "roomId": str(_result.room.id)}
	if _api.cloud_enabled and not _api.account_user.is_empty():
		identity["accountId"] = str(_api.account_user.id)
	connection_requested.emit(_result_url, str(_result.accessToken), identity)

func _lobby_status(message: String, busy: bool, needs_retry: bool) -> void:
	_status.text = message
	_submit.disabled = busy or needs_retry or _api != null and _api.cloud_enabled and _api.account_user.is_empty()
	_retry.visible = needs_retry
	_cancel.visible = needs_retry
	_retry.disabled = busy
	_cancel.disabled = busy
	_server.editable = not busy and not needs_retry and not OS.has_feature("web")
	for control: Control in _form_controls:
		if control is LineEdit:
			(control as LineEdit).editable = not busy and not needs_retry
		elif control is SpinBox:
			(control as SpinBox).editable = not busy and not needs_retry
		elif control is OptionButton:
			(control as OptionButton).disabled = busy or needs_retry

func _show_error(message: String) -> void:
	_status.text = message

func _label(text: String, font_size: int = 16) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _field(parent: Node, placeholder: String, maximum: int = 512) -> LineEdit:
	var field: LineEdit = LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = maximum
	field.custom_minimum_size.y = 38
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	if parent != _result_box:
		_form_controls.append(field)
	return field

func _button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.pressed.connect(callback)
	return button

func _account_changed(user: Dictionary, cloud: bool) -> void:
	title = "联机大厅 · 在线内测" if cloud else "联机大厅 · 本机房间演练"
	_auth_box.visible = cloud
	_action.set_item_disabled(2, cloud)
	if cloud and _action.selected == 2:
		_action.select(0)
	_update_form()
	_join_hint.text = "邀请码用于加入房间。已有城池请登录原账号，从我的房间恢复。" if cloud else "邀请码用于新城主加入。返回已有城池请使用自己的恢复密钥。"
	_result_hint.text = "在线进度绑定账号。下次登录原账号，在我的房间恢复城池；客户端不会保存密码和会话。" if cloud else "关闭客户端或刷新网页后，需要房间编号＋自己的恢复密钥才能回到原城池。共享邀请码不能恢复已有席位。"
	_room_heading.text = "房间编号" if cloud else "房间编号 · 恢复席位时需要"
	for control: Control in _key_controls:
		control.visible = not cloud
	var signed_in: bool = not user.is_empty()
	_account_label.text = "已登录：%s · 会话仅保存在本次运行内存" % str(user.get("email", "")) if signed_in else "在线内测：请输入已开通的账号，当前不能自行注册。"
	_email.visible = not signed_in
	_password.visible = not signed_in
	_login.visible = not signed_in
	_logout.visible = signed_in
	if not signed_in:
		if cloud or _account_was_signed_in:
			_clear_result()
		_rooms_received([])
	_account_was_signed_in = signed_in
	_lobby_status("请登录内测账号" if cloud and not signed_in else "请选择房间操作", _api.busy if _api != null else false, _api.needs_retry if _api != null else false)

func _account_status(message: String, busy: bool) -> void:
	_login.disabled = busy
	_email.editable = not busy
	_password.editable = not busy
	_logout.disabled = busy
	if _api != null and not _api.busy and not _api.needs_retry:
		_status.text = message

func _rooms_received(rooms: Array) -> void:
	for child: Node in _rooms_box.get_children():
		_rooms_box.remove_child(child)
		child.queue_free()
	_rooms_box.add_child(_label("我的房间 · 登录原账号恢复原城主"))
	if rooms.is_empty():
		_rooms_box.add_child(_label("暂无已有房间，可创建房间或用邀请码加入。", 14))
	for entry: Dictionary in rooms:
		var room_id: String = str(entry.room.id)
		var button: Button = _button("%s · %s · 席位 %d" % [str(entry.room.name), str(entry.actor.name), int(entry.seat)], func() -> void:
			if _api != null and _api.resume_account_room(room_id):
				_clear_result())
		_rooms_box.add_child(button)
