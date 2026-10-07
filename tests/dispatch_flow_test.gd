extends SceneTree

## Isolated safe DTOs; no API, save, player settings, or game consumption.
const DispatchScript: Script = preload("res://src/dispatch_dialog.gd")
const ThemeScript: Script = preload("res://src/ui_theme.gd")
const UI_FONT: Font = preload("res://assets/fonts/UI.tres")
const NOW: float = 1800000000000.0
var _checks: int = 0
var _failures: int = 0
var _host: Control
var _dialog: Variant
var _requests: Array[Dictionary] = []
var _commands: Array[Dictionary] = []


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceDispatchFlowTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
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


func _node(id: String = "field") -> Dictionary:
	return {"id": id, "name": "河畔荒田" if id == "field" else "山间营地", "selectable": true, "hidden": false, "owned": false}


func _fixture() -> Dictionary:
	return {"serverTime": NOW, "city": {"id": "capital", "name": "青溪城"}, "res": {"food": 50000},
		"buildings": [{"id": "drill", "level": 2}], "marches": [],
		"generals": [{"id": "lin", "name": "林将军", "busy": false, "governor": false}, {"id": "bo", "name": "伯将军", "busy": false, "governor": false}, {"id": "busy", "name": "外出将军", "busy": true}, {"id": "governor", "name": "守城将军", "governor": true}],
		"units": [{"id": "archer", "name": "弓箭兵", "available": 20}, {"id": "spear", "name": "长枪兵", "available": 8}, {"id": "scout", "name": "斥候", "available": 3}],
		"nodes": [_node(), _node("camp")], "techs": [{"id": "scouting", "level": 1}],
		"scouting": {"supported": true, "available": 3, "queueUsed": 0, "queueLimit": 2, "intelByNode": {}}}


func _reply(request: Dictionary, reason: String = "") -> Dictionary:
	return {"requestId": request.requestId, "kind": "march", "sourceCity": "capital", "serverTime": NOW,
		"quote": {"seconds": 25.5, "returnSeconds": 40.1, "foodCost": 137, "carry": 91, "reason": reason,
			"command": {"type": "dispatch", "args": request.args.duplicate(true), "sourceCity": "capital"}}}


func _preview(reason: String = "") -> Dictionary:
	var before: int = _requests.size()
	_dialog._request_march_quote()
	_check(_requests.size() == before + 1, "A valid preview emits exactly one quote request.")
	if _requests.size() == before:
		return {}
	var reply: Dictionary = _reply(_requests.back(), reason)
	_dialog.receive_quote(reply)
	return reply


func _type(id: String, text: String) -> void:
	var editor: LineEdit = _dialog._army_inputs[id].get_line_edit()
	editor.text = text
	editor.text_changed.emit(text)


func _restore(view: Dictionary = {}) -> void:
	_dialog.clear_context()
	_dialog.configure_target(_node())
	_dialog.update_view(_fixture() if view.is_empty() else view)
	_dialog.set_command_state(true, false)
	_dialog.show_tab("march")
	if not _dialog.visible:
		_dialog.popup()
	_dialog._fit_window()


func _bounds(width: int, tab: String) -> void:
	_check(_dialog.size.x <= width - 24 and _dialog.position.x >= 0 and _dialog.position.x + _dialog.size.x <= width, "Dispatch fits viewport width %d." % width)
	_check(_dialog.position.y >= 0 and _dialog.position.y + _dialog.size.y <= root.size.y, "Dispatch fits viewport height at %d." % width)
	_check(_dialog.position.x + _dialog.size.x == width - 12, "Desktop drawer/phone window keeps a 12px right margin.")
	var scroll: ScrollContainer = _dialog._march_scroll if tab == "march" else _dialog._scroll
	_check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page + 1, "Content wraps without horizontal scrolling.")
	var footer: VBoxContainer = _dialog._march_footer if tab == "march" else _dialog._scout_footer
	_check(footer.get_global_rect().end.y <= _dialog.size.y - 30, "The fixed action footer fits above Close.")
	var buttons: Array = [_dialog._march_preview, _dialog._march_confirm] if tab == "march" else [_dialog._preview, _dialog._confirm]
	for button: Button in buttons:
		_check(button.size.y >= 44 and button.get_global_rect().end.x <= _dialog.size.x - 8, "Actions remain touch-sized and within the window.")
	var before: Vector2 = buttons[1].global_position
	scroll.scroll_vertical = 500
	await _settle()
	_check(buttons[1].global_position == before, "Scrolling input leaves confirmation at the same fixed position.")


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var folder: String = "res://production/qa/evidence/story-012/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(root.get_texture().get_image().save_png(folder + name + ".png") == OK, "Prepared dispatch screenshot saves.")


func _run() -> void:
	root.size = Vector2i(390, 844)
	_host = Control.new()
	_host.size = Vector2(390, 844)
	_host.theme = ThemeScript.create(UI_FONT)
	root.add_child(_host)
	var background: ColorRect = ColorRect.new()
	background.color = Color("101918")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.add_child(background)
	_dialog = DispatchScript.new()
	_host.add_child(_dialog)
	_dialog.quote_requested.connect(func(kind: String, args: Array, request_id: String) -> void: _requests.append({"kind": kind, "args": args.duplicate(true), "requestId": request_id}))
	_dialog.command_requested.connect(func(type: String, args: Array, source: String) -> void: _commands.append({"type": type, "args": args.duplicate(true), "sourceCity": source}))
	var view: Dictionary = _fixture()
	var original: String = JSON.stringify(view)
	_dialog.configure_target(_node())
	_dialog.update_view(view)
	_dialog.set_command_state(true, false)
	_check(not _dialog.visible and _requests.is_empty() and _commands.is_empty(), "Configuration/polling never opens, previews, or consumes.")
	_dialog.popup()
	_dialog._fit_window()
	await _settle()
	_check(_dialog._general.item_count == 2, "Busy and appointed generals are excluded.")
	_check(_dialog._march_intel._precision.text.contains("未知") and _dialog._march_intel._details.text.contains("未知不表示"), "Unscouted defenders are unknown, never empty.")
	_check(_dialog._march_confirm.disabled and not _dialog._march_preview.disabled, "Explicit preview is required before consumption.")
	_check(not _dialog._occupy_return.visible, "Raid hides the occupation return choice.")
	var reply: Dictionary = _preview()
	_check(_requests.back().kind == "march" and _requests.back().args == ["field", "lin", {"archer": 20, "spear": 8, "scout": 3}, "raid", false], "Canonical march request includes exact target, general, army, mode, boolean.")
	_check(_commands.is_empty(), "Preview emits no consuming command.")
	_check(not _dialog._march_confirm.disabled and _dialog._march_quote_label.text.contains("粮草费用 137") and _dialog._march_quote_label.text.contains("运载能力 91") and _dialog._march_quote_label.text.contains("0分26秒") and _dialog._march_quote_label.text.contains("0分41秒") and _dialog._march_quote_label.text.contains("预计抵达：01-15 08:00:26"), "Quote displays canonical cost, carry, both durations and server-time arrival.")
	await _settle()
	await _capture("dispatch-390-intel-top")
	await _bounds(390, "march")
	await _capture("dispatch-390-fixed-footer")
	var editor: LineEdit = _dialog._army_inputs.archer.get_line_edit()
	var spin: SpinBox = _dialog._army_inputs.archer
	editor.grab_focus()
	var scroll: int = _dialog._march_scroll.scroll_vertical
	_dialog.update_view(view.duplicate(true))
	await _settle()
	var irrelevant: Dictionary = view.duplicate(true)
	irrelevant.buildings[0]["affordable"] = true
	_dialog.update_view(irrelevant)
	_check(not _dialog._march_confirm.disabled, "Polling presentation-only affordability keeps valid march quote.")
	_check(_dialog._army_inputs.archer == spin and _dialog.get_viewport().gui_get_focus_owner() == editor and _dialog._march_scroll.scroll_vertical == scroll and not _dialog._march_confirm.disabled, "Unchanged polling preserves controls, focus, scroll and a valid quote.")
	_type("archer", "07")
	_dialog.update_view(view.duplicate(true))
	_check(editor.text == "07" and _dialog._march_confirm.disabled, "Raw input survives polling and invalidates consumption.")
	_dialog.receive_quote(reply)
	_check(_dialog._march_confirm.disabled, "A late quote cannot revive edited input.")
	reply = _preview()
	_check(editor.text == "7" and _requests.back().args[2].archer == 7, "Preview normalizes raw integers exactly.")
	_type("archer", "999")
	reply = _preview()
	_check(_requests.back().args[2].archer == 20 and editor.text == "20", "Input clamps to current available stock.")
	_type("archer", "invalid")
	var before: int = _requests.size()
	_dialog._request_march_quote()
	_check(_requests.size() == before and _dialog._march_confirm.disabled, "Malformed raw input cannot request or consume.")
	_type("archer", "4")
	_dialog._mode.select(1)
	_dialog._mode.item_selected.emit(1)
	_dialog._occupy_return.button_pressed = true
	reply = _preview()
	_check(_requests.back().args[3] == "occupy" and _requests.back().args[4] == true and _dialog._occupy_return.visible, "Occupation quotes the explicit return choice.")
	await _settle()
	await _capture("dispatch-390-occupy-return-quote")
	var command: Dictionary = reply.quote.command.duplicate(true)
	_dialog._submit_march()
	_dialog._submit_march()
	_check(_commands.size() == 1 and _commands.back() == command, "Confirmation emits the exact descriptor once, including source city.")
	_check(_dialog._march_confirm.disabled and _dialog._march_preview.disabled, "Pending command blocks duplicate previews and confirmation.")
	_restore()
	reply = _preview()
	var wrong: Dictionary = reply.duplicate(true)
	wrong.requestId = "unrelated"
	wrong.quote.command.sourceCity = "other"
	_dialog.receive_quote(wrong)
	_check(not _dialog._march_confirm.disabled, "Unrelated quote cannot replace a valid descriptor.")
	for mutation: String in ["source", "type", "target", "general", "army", "mode", "return", "cost", "duration"]:
		wrong = reply.duplicate(true)
		match mutation:
			"source": wrong.quote.command.sourceCity = "other"
			"type": wrong.quote.command.type = "dispatchScout"
			"target": wrong.quote.command.args[0] = "camp"
			"general": wrong.quote.command.args[1] = "busy"
			"army": wrong.quote.command.args[2].archer = 21
			"mode": wrong.quote.command.args[3] = "occupy"
			"return": wrong.quote.command.args[4] = 1
			"cost": wrong.quote.erase("foodCost")
			"duration": wrong.quote.seconds = -1
		_dialog.receive_quote(wrong)
		_check(_dialog._march_confirm.disabled, "Reject mismatched command/terms: " + mutation)
		_dialog.receive_quote(reply)
	for change: String in ["stock_less", "stock_more", "general_busy", "general_role", "city", "target_hidden", "target_removed", "target_owned", "target_player", "intel", "food"]:
		_restore()
		reply = _preview()
		var changed: Dictionary = _fixture()
		match change:
			"stock_less": changed.units[0].available = 19
			"stock_more": changed.units[0].available = 21
			"general_busy": changed.generals[0].busy = true
			"general_role": changed.generals[0].governor = true
			"city": changed.city.id = "other-city"
			"target_hidden": changed.nodes[0].hidden = true
			"target_removed": changed.nodes.remove_at(0)
			"target_owned": changed.nodes[0].owned = true
			"target_player": changed.nodes[0].playerId = "opponent"
			"intel": changed.scouting.intelByNode.field = {"precision": "types", "types": ["archer"]}
			"food": changed.res.food = 136
		_dialog.update_view(changed)
		_dialog.receive_quote(reply)
		_check(_dialog._march_confirm.disabled, "Current DTO change revokes quoted dispatch: " + change)
	_restore()
	reply = _preview("校场派遣队伍已满")
	_check(_dialog._march_confirm.disabled and _dialog._march_quote_label.text.contains("校场派遣队伍已满"), "Canonical rejection is displayed without enabling confirmation.")
	_restore()
	reply = _preview()
	_dialog.set_command_state(false, false)
	_dialog.receive_quote(reply)
	_check(_dialog._march_confirm.disabled, "Disconnection revokes quote; late reply cannot revive it.")
	_restore()
	reply = _preview()
	_dialog.set_command_state(true, true)
	_dialog.receive_quote(reply)
	_check(_dialog._march_confirm.disabled, "External pending command revokes quote.")
	_restore()
	reply = _preview()
	_dialog.hide()
	_dialog.receive_quote(reply)
	_dialog.popup()
	_dialog._fit_window()
	_check(_dialog._march_confirm.disabled, "Hide discards quote and ignores a late response.")
	_restore()
	reply = _preview()
	_dialog.configure_target(_node("camp"))
	_dialog.receive_quote(reply)
	_check(_dialog._march_confirm.disabled, "Target switch revokes quote.")
	_restore()
	reply = _preview()
	_dialog.show_tab("scout")
	_dialog.receive_quote(reply)
	_check(_dialog._march_confirm.disabled and _dialog._tabs.current_tab == 1 and _dialog.visible, "Scout opens in the same window and discards the old march quote.")
	_check(_dialog._scroll.get_parent() == _dialog._tabs and _dialog._march_scroll.get_parent() == _dialog._tabs and _dialog._preview.get_parent().get_parent() == _dialog._scout_footer, "Both sections share one window with a separate fixed scout footer.")
	before = _requests.size()
	_dialog._request_quote()
	_check(_requests.size() == before + 1 and _requests.back().kind == "scout" and _requests.back().args == ["field", 1], "Inherited scout quote flow remains available in its own tab.")
	var scout_request: Dictionary = _requests.back()
	_dialog.receive_quote({"requestId": scout_request.requestId, "kind": "scout", "serverTime": NOW, "quote": {"seconds": 20, "returnSeconds": 20, "cost": {"food": 33}, "precision": "types", "expectedLost": 0, "ttlMs": 600000, "key": "safe-fixture", "reason": "", "command": {"type": "dispatchScout", "args": ["field", 1, "safe-fixture"], "sourceCity": "capital"}}})
	_check(not _dialog._confirm.disabled and _dialog._quote_label.text.contains("粮草费用 33"), "Scout fixed footer shows its current canonical preview.")
	await _settle()
	await _bounds(390, "scout")
	await _capture("dispatch-scout-390-same-window")
	_dialog.show_tab("march")
	_check(_dialog._quote_id.is_empty(), "Leaving scout tab discards its in-flight quote.")
	_restore()
	view = _fixture()
	view.scouting.supported = false
	_dialog.update_view(view)
	_check(not _dialog._march_preview.disabled, "PvE dispatch does not depend on scouting support or stock.")
	root.size = Vector2i(1280, 800)
	_host.size = Vector2(1280, 800)
	_dialog._fit_window()
	_dialog.show_tab("march")
	await _settle()
	await _bounds(1280, "march")
	_check(_dialog.size.x == 480 and _dialog.position.x > 700, "Desktop dispatch is a narrow right-side drawer.")
	await _capture("dispatch-1280-right-drawer")
	_check(JSON.stringify(_fixture()) == original, "Prepared DTO fixture remains unchanged.")
	_dialog.clear_context()
	_check(_dialog._march_confirm.disabled and _dialog._march_preview.disabled and _dialog._march_command.is_empty(), "Context clearing disables all consuming actions.")
	print("Dispatch flow checks: %d; failures: %d" % [_checks, _failures])
	_dialog.queue_free()
	_host.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)
