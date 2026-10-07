extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _dialog: KingdomRealmDialog
var _view: Dictionary
var _commands: Array[Dictionary] = []
var _quotes: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _fixture() -> Dictionary:
	var res: Dictionary = {"food": 10000, "wood": 5000, "stone": 5000, "iron": 5000, "gold": 5000}
	var realm: Dictionary = {"shared": false, "currentCity": "capital", "cityLimit": 2, "serverTime": 1800000000000,
		"cities": [{"id": "capital", "name": "主城", "x": 32, "y": 32, "res": res, "army": {"archer": 20}}, {"id": "city_test", "name": "分城", "x": 31, "y": 30, "res": res, "army": {}}],
		"generals": [{"id": "su", "name": "苏衡", "busy": false}, {"id": "lin", "name": "林岳", "busy": false}],
		"roles": {"governor": {"name": "城守", "hero": "su"}, "commander": {"name": "主将", "hero": ""}, "counsellor": {"name": "军师", "hero": ""}},
		"logistics": [{"id": "logistics_1", "sourceCity": "capital", "destinationCity": "city_test", "kind": "transport", "phase": "outbound", "end": 1800000060000}],
		"holdings": [{"id": "wild_31_31", "name": "已占平地", "x": 31, "y": 31, "type": "plain", "garrison": null, "gathering": null, "gatherQuote": null, "gatherReason": "平地不能采集", "foundReason": ""}],
		"templates": [{"id": "army", "name": "兵城", "desc": "木铁石各一块，其余种粮。", "quotes": [{"mode": "fill", "projectedCounts": {"farm": 9, "lumber": 1, "mine": 1, "quarry": 1}, "tasks": [{"index": 3}], "cost": {"wood": 1000}, "reason": ""}, {"mode": "replace", "projectedCounts": {"farm": 9, "lumber": 1, "mine": 1, "quarry": 1}, "tasks": [{"index": 1}], "cost": {"wood": 2000}, "reason": ""}]}],
		"plotStatus": "等待资源积累或降低保留额度", "autoUpgradeStatus": "已暂停", "autoResearchStatus": "已暂停", "automation": {"reserve": res, "researchFocus": "balanced", "researchPriority": "", "notify": true, "notices": []}}
	return {"realmManagement": realm, "city": {"name": "主城"}, "res": res, "units": [{"id": "archer", "name": "弓箭兵", "available": 20}, {"id": "wagon", "name": "辎重车", "available": 2}], "plots": [{"index": 0, "id": "farm", "name": "农田", "level": 8, "unlocked": true, "queue": null, "requirement": null}], "plotOptions": [{"id": "farm", "name": "农田"}], "techs": [{"id": "shooting", "name": "抛射技巧"}]}

func _button(text: String) -> Button:
	for entry: Node in _dialog._content.find_children("*", "Button", true, false):
		if (entry as Button).text == text:
			return entry as Button
	return null

func _spin(id: String) -> SpinBox:
	for entry: Node in _dialog._content.find_children("*", "SpinBox", true, false):
		if str(entry.get_meta("draft_id", "")) == id:
			return entry as SpinBox
	return null

func _text(spin: SpinBox, value: String) -> void:
	spin.get_line_edit().text = value
	spin.get_line_edit().emit_signal("text_changed", value)

func _preview_payload(request: Dictionary) -> Dictionary:
	return {"requestId": request.id, "sourceCity": "capital", "quote": {"reason": "", "seconds": 100, "foodCost": 30, "carry": 2000, "command": {"type": "sendTransport", "args": request.args + ["canonical_quote_key"], "sourceCity": "capital"}}}

func _run() -> void:
	root.size = Vector2i(390, 844)
	var host: Control = Control.new()
	host.size = Vector2(390, 844)
	root.add_child(host)
	_dialog = load("res://src/realm_dialog.gd").new() as KingdomRealmDialog
	host.add_child(_dialog)
	_dialog.command_requested.connect(func(type: String, args: Array) -> void: _commands.append({"type": type, "args": args}))
	_dialog.quote_requested.connect(func(kind: String, args: Array, request_id: String) -> void: _quotes.append({"kind": kind, "args": args, "id": request_id}))
	_view = JSON.parse_string(JSON.stringify(_fixture()))
	_dialog.set_command_state(true, false)
	_dialog.show_section("logistics", _view)
	await _settle()
	_check(_dialog.size.x <= 350, "Realm controls must fit in a 390-wide host.")
	_check(_dialog._scroll.get_h_scroll_bar().max_value <= _dialog._scroll.get_h_scroll_bar().page + 1.0, "Realm form labels/selectors must not need horizontal scrolling.")
	_check(not _button("召回途中部队").disabled, "Canonical outbound logistics must permit recall.")
	_check(_button("确认派遣").disabled, "Logistics cannot commit before a successful quote.")
	_text(_spin("army_archer"), "999999")
	_text(_spin("cargo_wood"), "1234")
	var spin_before: SpinBox = _spin("cargo_wood")
	var poll: Dictionary = _view.duplicate(true)
	poll.res.wood = 4000
	_dialog.update_view(poll)
	_check(_spin("cargo_wood") == spin_before and _spin("cargo_wood").get_line_edit().text == "1234", "A resource poll must preserve the raw unfinished quantity and control identity.")
	_text(_spin("cargo_wood"), "")
	_dialog.update_view(poll)
	_check(_spin("cargo_wood").get_line_edit().text.is_empty(), "An intentionally empty quantity draft must survive polling.")
	_text(_spin("cargo_wood"), "1234")
	poll.plots[0].level = 9
	_dialog.update_view(poll)
	await _settle()
	_check(_spin("cargo_wood").get_line_edit().text == "1234", "A real construction-completion rebuild must preserve an unsubmitted quantity.")
	_button("预览费用与时间").emit_signal("pressed")
	_check(_quotes.size() == 1 and _quotes[0].args[1].archer == 20 and _quotes[0].args[2].wood == 1234, "Direct preview must use typed drafts, clamp oversized army counts and retain cargo.")
	var old_request: Dictionary = _quotes.back()
	_text(_spin("cargo_wood"), "1000")
	_dialog.receive_quote(_preview_payload(old_request))
	_check(_button("确认派遣").disabled, "A stale quotation after an input edit must never enable dispatch.")
	_button("预览费用与时间").emit_signal("pressed")
	_dialog.receive_quote(_preview_payload(_quotes.back()))
	_check(not _button("确认派遣").disabled and _dialog._quote_label.text.contains("30"), "A matching live quote must show its canonical food fee and permit dispatch.")
	_button("确认派遣").emit_signal("pressed")
	_button("确认派遣").emit_signal("pressed")
	_check(_commands.size() == 1 and _commands[0].args.back() == "canonical_quote_key", "Dispatch must retain the canonical quote key and block duplicate clicks.")
	_dialog.update_view(poll)
	_check(_button("确认派遣").disabled, "Polling cannot unlock an unconfirmed dispatch.")
	_dialog.show_error("进度变化，请重新预览")
	_dialog.set_command_state(true, false)
	_check(_dialog._status.text.contains("重新预览"), "Quote/command errors must remain visible in the open form.")
	_dialog.acknowledge_command(true, false)
	_check(_button("确认派遣").disabled, "After acknowledgement a consumed quote must not be reused.")
	_dialog.show_section("holdings", _view)
	var name_input: LineEdit
	for entry: Node in _dialog._content.find_children("*", "LineEdit", true, false):
		name_input = entry as LineEdit
	name_input.text = "尚未提交的新城"
	name_input.emit_signal("text_changed", name_input.text)
	var changed: Dictionary = _view.duplicate(true)
	changed.realmManagement.logistics.clear()
	_dialog.update_view(changed)
	await _settle()
	var name_after: LineEdit
	for entry: Node in _dialog._content.find_children("*", "LineEdit", true, false):
		name_after = entry as LineEdit
	_check(name_after.text == "尚未提交的新城", "A queue-completion rebuild must retain a drafted city name.")
	_dialog.show_section("plots", _view)
	_check(_button("确认替换布局") == null and _button("升级当前地块") != null, "Plots start with the selected site and folded templates.")
	_button("展开城外样板").emit_signal("pressed")
	_check(_button("确认替换布局").disabled, "Plot replacement must require an explicit level-reset acknowledgement.")
	var consent: CheckBox
	for entry: Node in _dialog._content.find_children("*", "CheckBox", true, false):
		if (entry as CheckBox).text.contains("重置"):
			consent = entry as CheckBox
	consent.button_pressed = true
	_check(not _button("确认替换布局").disabled, "Acknowledging the level reset must enable replacement.")
	_button("确认替换布局").emit_signal("pressed")
	_check(_commands.back() == {"type": "applyPlotTemplate", "args": ["army", "replace"]}, "Replacement must preserve the canonical template ID/mode.")
	_dialog.acknowledge_command(true, false)
	_dialog.show_section("automation", _view)
	_text(_spin("reserve_gold"), "5432")
	_dialog.update_view(_view)
	_check(_spin("reserve_gold").get_line_edit().text == "5432", "Automation polling must retain resource-reserve edits.")
	_button("保存挂机设置").emit_signal("pressed")
	_check(_commands.back().type == "setAutomationSettings" and _commands.back().args[0].reserve.gold == 5432, "Saving automation must include the typed reserve value.")
	_dialog.acknowledge_command(true, false)
	var shared: Dictionary = _view.duplicate(true)
	shared.realmManagement.shared = true
	shared.realmManagement.gatheringReason = "共享演练尚未开放私人野地采集"
	_dialog.show_section("holdings", shared)
	_check(_button("开始采集") == null and _button("确认建城") == null, "Shared rooms must not expose private gathering/founding controls.")
	print("REALM_UI_TEST checks=", _checks, " failures=", _failures)
	host.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)
