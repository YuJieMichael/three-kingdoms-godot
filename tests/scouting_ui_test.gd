extends SceneTree

## Prepared actor-safe DTO fixtures; no API, runtime, save, or game mutation.
const ScoutScript: Script = preload("res://src/scouting_dialog.gd")
const IntelScript: Script = preload("res://src/intel_panel.gd")
const UI_FONT: Font = preload("res://assets/fonts/UI.tres")
const NOW: float = 1800000000000.0
var _checks: int = 0
var _failures: int = 0
var _requests: Array[Dictionary] = []
var _commands: Array[Dictionary] = []
var _dialog: Variant
var _host: Control


func _initialize() -> void:
	var previous_cache: String = OS.get_user_data_dir().path_join("shader_cache")
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceScoutingUiTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("shader_cache"))
	# Native rendering initializes before SceneTree. Copy only cache directory
	# names, never player settings/save files, into this isolated user://.
	if DirAccess.dir_exists_absolute(previous_cache):
		for shader: String in DirAccess.get_directories_at(previous_cache):
			for version: String in DirAccess.get_directories_at(previous_cache.path_join(shader)):
				DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("shader_cache").path_join(shader).path_join(version))
	root.gui_embed_subwindows = true
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for _frame: int in range(5):
		await process_frame


func _units() -> Array:
	return [{"id": "scout", "name": "斥候"}, {"id": "archer", "name": "弓箭兵"}, {"id": "spear", "name": "长枪兵"}]


func _target(id: String = "field") -> Dictionary:
	return {"id": id, "name": "河畔荒田" if id == "field" else "山间营地", "selectable": true, "hidden": false, "owned": false}


func _fixture() -> Dictionary:
	return {"serverTime": NOW, "city": {"id": "capital", "name": "青溪城"}, "res": {"food": 50000}, "units": _units(),
		"techs": [{"id": "scouting", "level": 2}], "nodes": [_target(), _target("camp")],
		"scouting": {"supported": true, "available": 50, "queueUsed": 1, "queueLimit": 3, "intelByNode": {
			"field": {"precision": "bands", "at": NOW - 60000, "expiresAt": NOW + 900000, "bands": {"archer": {"min": 100, "max": 199}},
				"types": ["archer"], "army": {"archer": 777777}, "lost": 2, "survivors": 18}}}}


func _reply(request: Dictionary, reason: String = "") -> Dictionary:
	var args: Array = request.args
	var key: String = "fixture-key-%d" % _requests.size()
	return {"requestId": request.requestId, "kind": "scout", "sourceCity": _dialog._source, "serverTime": NOW,
		"quote": {"seconds": 25.5, "returnSeconds": 25.5, "cost": {"food": 123}, "precision": "exact", "expectedLost": 2,
			"ttlMs": 900000, "quality": 3, "reason": reason, "key": key,
			"command": {"type": "dispatchScout", "args": [args[0], args[1], key], "sourceCity": _dialog._source}}}


func _preview(reason: String = "") -> Dictionary:
	var before: int = _requests.size()
	_dialog._request_quote()
	_check(_requests.size() == before + 1, "A usable preview emits exactly one read-only quote request.")
	if _requests.size() == before:
		return {}
	var payload: Dictionary = _reply(_requests.back(), reason)
	_dialog.receive_quote(payload)
	return payload


func _type_count(text: String) -> void:
	var editor: LineEdit = _dialog._count.get_line_edit()
	editor.text = text
	editor.text_changed.emit(text)


func _restore(view: Dictionary = {}) -> void:
	_dialog.clear_context()
	_dialog.configure_target(_target())
	_dialog.update_view(_fixture() if view.is_empty() else view)
	_dialog.set_command_state(true, false)
	if not _dialog.visible:
		_dialog.popup_centered()


func _bounds(width: int) -> void:
	_check(_dialog.size.x <= width - 30 and _dialog.position.x >= 0 and _dialog.position.x + _dialog.size.x <= width, "Scouting modal fits %dpx including its full popup bounds." % width)
	_check(_dialog.size.y <= root.size.y - 40 and _dialog.position.y >= 0 and _dialog.position.y + _dialog.size.y <= root.size.y, "Scouting modal stays within the viewport height at %dpx." % width)
	_check(absi(_dialog.position.x - (width - _dialog.size.x) / 2) <= 1, "Scouting modal remains centered when the host resizes to %dpx." % width)
	_check(_dialog._scroll.get_h_scroll_bar().max_value <= _dialog._scroll.get_h_scroll_bar().page + 1.0, "Scouting text wraps without horizontal scrolling at %dpx." % width)
	for button: Button in [_dialog._preview, _dialog._confirm]:
		_check(button.size.x <= _dialog.size.x - 20 and button.size.y >= 44, "Scouting action remains inside the modal and touch-sized at %dpx." % width)
	for label: Label in [_dialog._intro, _dialog._availability, _dialog._quote_label, _dialog._status, _dialog._intel._details]:
		_check(label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and label.size.x <= _dialog.size.x - 20, "Scouting labels have bounded wrapped layout at %dpx." % width)


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var folder: String = "res://production/qa/evidence/story-011/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(root.get_texture().get_image().save_png(folder + name + ".png") == OK, "Prepared scouting fixture screenshot saves.")


func _intel_checks() -> void:
	var panel: Variant = IntelScript.new()
	panel.size = Vector2(320, 240)
	_host.add_child(panel)
	var node: Dictionary = _target()
	node["army"] = {"archer": 777777}
	for precision: String in ["unknown", "failed", "expired", "legacy", "types", "bands"]:
		node["intel"] = {"precision": precision, "army": {"archer": 777777}, "bands": {"archer": {"min": 10, "max": 19}}, "types": ["archer"], "lost": 2, "survivors": 18}
		var original: String = JSON.stringify(node)
		panel.set_intel(node, _units(), NOW)
		_check(not panel._details.text.contains("777777"), "Precision %s never exposes unapproved exact enemy counts." % precision)
		_check(JSON.stringify(node) == original, "Intel rendering never mutates input DTO for %s." % precision)
		_check(panel._outcome.text.contains("损失 2 人") and panel._outcome.text.contains("返程斥候 18 人"), "Own scout outcome remains distinct from enemy intel for %s." % precision)
		if precision == "types":
			_check(panel._precision.text.contains("数量未知") and panel._details.text == "弓箭兵", "Types intel gives names only, never pseudo counts.")
		if precision == "bands":
			_check(panel._details.text == "弓箭兵 10–19 人", "Bands intel gives only the canonical inclusive interval.")
	node["intel"] = {"precision": "exact", "at": NOW - 60000, "expiresAt": NOW + 120000, "army": {"archer": 123}}
	panel.set_intel(node, _units(), NOW)
	_check(panel._details.text == "弓箭兵 123 人" and panel._validity.text.contains("1分00秒前") and panel._validity.text.contains("2分00秒"), "Fresh exact intel uses its projected counts and canonical timestamps.")
	panel.set_intel(node, _units(), NOW + 120000)
	_check(panel._precision.text.contains("过期") and not panel._details.text.contains("123"), "The expiry boundary hides exact enemy counts immediately.")
	node["intel"] = {"precision": "public", "expiresAt": NOW - 1, "army": {"archer": 321}}
	panel.set_intel(node, _units(), NOW)
	_check(panel._details.text == "弓箭兵 321 人" and panel._precision.text.contains("公开"), "Public node intel remains public independently of scout TTL.")
	node.erase("army")
	node["intel"] = {"precision": "public", "army": {}}
	panel.set_intel(node, _units(), NOW)
	_check(panel._details.text.contains("尚未提供") and not panel._details.text.contains("0 人"), "Missing public counts are unknown, never fabricated zero defenders.")
	node["intel"] = {"precision": "exact", "army": {"archer": 123}}
	node["hidden"] = true
	panel.set_intel(node, _units(), NOW)
	_check(panel._precision.text.contains("未知") and not panel._details.text.contains("123"), "Hidden targets cannot show even a stale exact DTO.")
	node.erase("hidden")
	node["intel"] = {"precision": "expired", "public": true, "army": {"archer": 123}}
	panel.set_intel(node, _units(), NOW)
	_check(panel._precision.text.contains("过期") and not panel._details.text.contains("123"), "Explicit expired precision cannot be revived by a stale public flag.")
	panel.free()


func _run() -> void:
	root.size = Vector2i(390, 844)
	_host = Control.new()
	_host.size = Vector2(390, 844)
	_host.theme = KingdomUiTheme.create(UI_FONT)
	root.add_child(_host)
	var background: ColorRect = ColorRect.new()
	background.color = KingdomUiTheme.INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.add_child(background)
	_intel_checks()
	_dialog = ScoutScript.new()
	_host.add_child(_dialog)
	_dialog.quote_requested.connect(func(kind: String, args: Array, request_id: String) -> void: _requests.append({"kind": kind, "args": args.duplicate(true), "requestId": request_id}))
	_dialog.command_requested.connect(func(type: String, args: Array, source: String) -> void: _commands.append({"type": type, "args": args.duplicate(true), "sourceCity": source}))
	var view: Dictionary = _fixture()
	var supplied_view: Dictionary = view
	var original: String = JSON.stringify(view)
	_dialog.configure_target(_target())
	_dialog.update_view(view)
	_dialog.set_command_state(true, false)
	_check(not _dialog.visible and _requests.is_empty() and _commands.is_empty(), "Configuring and polling never opens the modal, quotes, or consumes.")
	_dialog.popup_centered()
	await _settle()
	_check(_dialog.get_viewport().gui_get_focus_owner() == _dialog.get_ok_button(), "The modal initially focuses its safe close action.")
	_check(_dialog._count.value == 1 and _dialog._count.max_value == 50, "New target starts with one scout and respects current city stock.")
	_check(_dialog._intel._details.text == "弓箭兵 100–199 人" and not _dialog._intel._details.text.contains("777777"), "Modal renders safe bands without leaking attached exact army.")
	_check(_dialog._intel._validity.text.contains("15分00秒"), "Modal uses injected serverTime for intelligence lifetime.")
	_check(_dialog._confirm.disabled and not _dialog._preview.disabled, "Sending requires a distinct, valid preview.")
	_bounds(390)
	var reply: Dictionary = _preview()
	_check(_requests.back().kind == "scout" and _requests.back().args == ["field", 1] and _commands.is_empty(), "Preview has only node and count, with no general or consumption command.")
	_check(not _dialog._confirm.disabled and _dialog._quote_label.text.contains("粮草费用 123") and _dialog._quote_label.text.contains("0分26秒") and _dialog._quote_label.text.contains("精确兵力") and _dialog._quote_label.text.contains("损失 2 人") and _dialog._quote_label.text.contains("15分00秒"), "Preview discloses canonical cost, both journeys, precision, expected loss, and TTL.")
	await _settle()
	_bounds(390)
	await _capture("scouting-390-top")
	var editor: LineEdit = _dialog._count.get_line_edit()
	editor.grab_focus()
	_dialog._scroll.scroll_vertical = 130
	await _settle()
	var scroll_position: int = _dialog._scroll.scroll_vertical
	var count_control: SpinBox = _dialog._count
	var preview_control: Button = _dialog._preview
	_dialog.update_view(view.duplicate(true))
	await _settle()
	_check(_dialog._count == count_control and _dialog._preview == preview_control and _dialog.get_viewport().gui_get_focus_owner() == editor, "Same-revision polling preserves controls and keyboard focus.")
	_check(_dialog._scroll.scroll_vertical == scroll_position and not _dialog._confirm.disabled, "Same-revision polling preserves scroll and a valid quote.")
	await _capture("scouting-390-quote")
	_type_count("07")
	_dialog.update_view(view.duplicate(true))
	_check(editor.text == "07" and _dialog._confirm.disabled, "Polling preserves raw uncommitted input and quantity edits invalidate a quote.")
	_dialog.receive_quote(reply)
	_check(_dialog._confirm.disabled, "A response to the earlier count cannot revive confirmation.")
	reply = _preview()
	_check(_requests.back().args == ["field", 7] and editor.text == "7", "Preview normalizes raw integer input to exactly seven scouts.")
	var wrong: Dictionary = reply.duplicate(true)
	wrong.requestId = "other-request"
	wrong.quote.command.args[0] = "camp"
	_dialog.receive_quote(wrong)
	_check(not _dialog._confirm.disabled and _dialog._quote_command.args == reply.quote.command.args, "Unrelated request IDs cannot overwrite a valid quote.")
	wrong = reply.duplicate(true)
	wrong.quote.command.sourceCity = "other-city"
	_dialog.receive_quote(wrong)
	_check(_dialog._confirm.disabled, "Even matching requests cannot enable a command for a different source city.")
	wrong = reply.duplicate(true)
	wrong.quote.command.args[0] = "camp"
	_dialog.receive_quote(wrong)
	_check(_dialog._confirm.disabled, "A command quoting another node is rejected.")
	wrong = reply.duplicate(true)
	wrong.quote.command.args[1] = 7.5
	_dialog.receive_quote(wrong)
	_check(_dialog._confirm.disabled, "Fractional command counts cannot bypass the integer spinner.")
	_dialog.receive_quote(reply)
	_check(not _dialog._confirm.disabled, "A correctly correlated exact command can enable confirmation.")
	var blocked: Dictionary = _preview("侦察队列已满")
	_dialog._submit()
	_check(_dialog._confirm.disabled and _dialog._quote_label.text.contains("队列已满") and _dialog._quote_label.text.contains("粮草费用 123") and _commands.is_empty(), "A canonical blocking reason is visible with costs and cannot be sent.")
	_dialog.configure_target(_target("camp"))
	_dialog.receive_quote(blocked)
	_check(_dialog._confirm.disabled and _dialog._quote_id.is_empty(), "Changing target revokes cached and in-flight quotes.")
	_restore()
	reply = _preview()
	view = _fixture()
	view.city = {"id": "other-city", "name": "白石城"}
	view.scouting.intelByNode = {}
	_dialog.update_view(view)
	_dialog.receive_quote(reply)
	_check(_dialog._source == "other-city" and _dialog._confirm.disabled and _dialog._intel._precision.text.contains("未知"), "City switch revokes the old source quote and old city intelligence.")
	_restore()
	reply = _preview()
	view = _fixture()
	view.scouting.available = 3
	_dialog.update_view(view)
	_dialog.receive_quote(reply)
	_check(_dialog._count.max_value == 3 and _dialog._quote_id.is_empty() and _dialog._confirm.disabled, "Reduced stock clamps max and revokes an earlier quote even when its count still fits.")
	_type_count("999")
	reply = _preview()
	_check(_requests.back().args[1] == 3 and editor.text == "3", "Over-stock raw input is clamped to actual inventory before quoting.")
	view.scouting.available = 5000
	_dialog.update_view(view)
	_type_count("5000")
	reply = _preview()
	_check(_dialog._count.max_value == 1000 and _requests.back().args[1] == 1000 and editor.text == "1000", "5000 owned scouts still respect the original rule's 1000-per-dispatch hard limit.")
	for bad: String in ["-5", "1.5", "invalid"]:
		var before: int = _requests.size()
		_type_count(bad)
		_dialog._request_quote()
		_check(_requests.size() == before and _dialog._confirm.disabled, "Invalid or non-positive input '%s' emits no quote or command." % bad)
	_restore()
	reply = _preview()
	view = _fixture()
	view.scouting.queueUsed = 2
	_dialog.update_view(view)
	_check(_dialog._quote_id.is_empty(), "Queue changes revoke the old quote.")
	reply = _preview()
	view.techs[0].level = 3
	_dialog.update_view(view)
	_check(_dialog._confirm.disabled, "Changes to scout research revoke precision-dependent quotes.")
	reply = _preview()
	view.res.food = 122
	_dialog.update_view(view)
	_check(_dialog._quote_id.is_empty() and _dialog._quote_label.text.contains("粮草已不足"), "A quote is revoked when actual current food falls below its cost.")
	_restore()
	_dialog._request_quote()
	reply = _reply(_requests.back())
	_dialog.set_command_state(false, false)
	_dialog.receive_quote(reply)
	_dialog._submit()
	_check(_dialog._preview.disabled and _dialog._confirm.disabled and _commands.is_empty(), "Disconnect ignores in-flight responses and synthetic submission.")
	_dialog.set_command_state(true, false)
	_check(not _dialog._preview.disabled and _dialog._confirm.disabled, "Reconnection restores preview without resurrecting the old quote.")
	reply = _preview()
	_dialog.set_command_state(true, true)
	_dialog.receive_quote(reply)
	_dialog._submit()
	_check(_dialog._count.editable == false and _dialog._confirm.disabled and _commands.is_empty(), "Pending mutation locks count and prevents stale confirmation.")
	_dialog.acknowledge_command(true, false)
	_check(not _dialog._preview.disabled and _dialog._confirm.disabled and _commands.is_empty(), "Acknowledgement unlocks a new preview without replaying a command.")
	reply = _preview()
	_dialog.show_error("实际服务拒绝了派遣")
	_dialog._submit()
	_check(_dialog._quote_id.is_empty() and _dialog._status.text.contains("实际服务拒绝") and _commands.is_empty(), "Service errors revoke the quote and disclose the real failure.")
	_restore()
	reply = _preview()
	_dialog._submit()
	_dialog._submit()
	_check(_commands.size() == 1 and _commands[0] == reply.quote.command and _dialog._pending and _dialog._confirm.disabled, "Explicit confirmation emits the exact canonical command once, then locks against duplicates.")
	_dialog.acknowledge_command(true, false)
	_check(_commands.size() == 1 and _dialog._quote_id.is_empty() and not _dialog._preview.disabled, "Dispatch acknowledgement neither repeats nor recaches the consumed command.")
	_dialog._request_quote()
	reply = _reply(_requests.back())
	_dialog.hide()
	_dialog.receive_quote(reply)
	_dialog.popup_centered()
	await _settle()
	_check(_dialog._quote_id.is_empty() and _dialog._confirm.disabled, "Closing and reopening cannot accept a late quote from a hidden modal.")
	_restore()
	view = _fixture()
	view.scouting.intelByNode.field = {"precision": "exact", "army": {"archer": 123456}, "at": NOW, "expiresAt": NOW + 900000}
	_dialog.configure_target({"id": "field", "name": "河畔荒田", "selectable": true, "intel": view.scouting.intelByNode.field, "army": {"archer": 123456}})
	_dialog.update_view(view)
	_check(_dialog._intel._details.text.contains("123456"), "Returned exact intel appears in the already-open modal.")
	view.scouting.intelByNode = {}
	_dialog.update_view(view)
	_check(_dialog._intel._precision.text.contains("未知") and not _dialog._intel._details.text.contains("123456"), "Removing intelByNode in the same revision removes configure_target's stale army and intel.")
	view.scouting.intelByNode.field = {"precision": "public", "army": {"archer": 321}}
	_dialog.update_view(view)
	var before: int = _requests.size()
	_dialog._request_quote()
	_check(_dialog._preview.disabled and _dialog._intro.text.contains("守军已公开，无需侦察") and _requests.size() == before, "Public intel explains that scouting is unnecessary and does not invite spending food.")
	view.scouting.intelByNode = {}
	_dialog.update_view(view)
	_check(not _dialog._preview.disabled and not _dialog._intro.text.contains("守军已公开") and _dialog._intel._precision.text.contains("未知"), "Removing public intel clears stale public status and restores a fresh preview.")
	view.nodes = [_target("camp")]
	_dialog.update_view(view)
	_check(_dialog._preview.disabled and _dialog._intel._precision.text.contains("未知"), "A node removed from safe current nodes cannot retain intelligence or accept scouting.")
	_restore()
	view = _fixture()
	view.scouting.supported = false
	_dialog.update_view(view)
	before = _requests.size()
	_dialog._request_quote()
	_dialog._submit()
	_check(_dialog._preview.disabled and _requests.size() == before and _commands.size() == 1 and _dialog._intel._node.is_empty(), "Shared/unsupported mode clears private intel and cannot request or consume.")
	for flag: String in ["shared", "player", "owned", "hidden"]:
		view = _fixture()
		view.nodes[0][flag] = true
		_restore(view)
		before = _requests.size()
		_dialog._request_quote()
		_check(_dialog._preview.disabled and _requests.size() == before, "Scouting excludes the canonical forbidden target flag %s." % flag)
	view = _fixture()
	view.scouting.available = 0
	_restore(view)
	_check(_dialog._preview.disabled and _dialog._availability.text.contains("军队→训练与驻军→斥候") and _commands.size() == 1, "No-scout state gives the training route without navigation or automatic consumption.")
	_restore()
	_dialog._request_quote()
	reply = _reply(_requests.back())
	_dialog.clear_context()
	_dialog.receive_quote(reply)
	_check(_dialog._target.is_empty() and _dialog._view.is_empty() and _dialog._source.is_empty() and _dialog._intel._node.is_empty() and _dialog._quote_id.is_empty() and _dialog._preview.disabled, "Identity cleanup clears target, source, input data, private intel, and pending quotes.")
	_check(JSON.stringify(supplied_view) == original, "The actual supplied snapshot remains unchanged by UI rendering, quoting, cleanup, and confirmation.")
	_restore()
	reply = _preview("斥候数量不足：当前可用50名，请先在军队训练与驻军中训练斥候；本预览未扣除资源。")
	root.size = Vector2i(1280, 844)
	_host.size = Vector2(1280, 844)
	_dialog.hide()
	_dialog.popup_centered()
	_dialog._scroll.scroll_vertical = 0
	# Hiding invalidates quotes; prepare a fresh preview in the resized window.
	reply = _preview("斥候数量不足：当前可用50名，请先在军队训练与驻军中训练斥候；本预览未扣除资源。")
	await _settle()
	_bounds(1280)
	await _capture("scouting-1280")
	root.size = Vector2i(390, 844)
	_host.size = Vector2(390, 844)
	_dialog._fit_window()
	await _settle()
	_bounds(390)
	_check(_dialog._confirm.disabled and _dialog._quote_label.text.contains("未扣除资源"), "Visible resize preserves the quoted canonical blocking reason.")
	_check(_commands.size() == 1, "All read-only, navigation-free checks emit no extra mutation commands.")
	print("SCOUTING_UI_TEST_CHECKS=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures else 0)
