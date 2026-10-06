extends SceneTree

## Production PvP dialog, real Controls and command signals. No server or save.
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _assert(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _buttons(node: Node, text: String = "") -> Array[Button]:
	var result: Array[Button] = []
	if node is Button and (text.is_empty() or (node as Button).text == text):
		result.append(node as Button)
	for child: Node in node.get_children():
		result.append_array(_buttons(child, text))
	return result

func _view() -> Dictionary:
	return {"generals": [{"id": "free-hero", "name": "可出征将", "busy": false, "governor": false}, {"id": "busy-hero", "name": "行军将", "busy": true}, {"id": "governor", "name": "城守", "governor": true}], "units": [{"id": "cavalry", "name": "轻骑兵", "available": 40}, {"id": "archer", "name": "弓箭兵", "available": 25}, {"id": "spear", "name": "长枪兵", "available": 0}]}

func _shared(now: float) -> Dictionary:
	return {"membership": {"alliance": "alliance-a"}, "players": [{"id": "player-1", "name": "演练甲", "alliance": "alliance-a", "home": {"x": 8, "y": 12}}, {"id": "player-2", "name": "演练乙", "alliance": "alliance-a", "home": {"x": 10, "y": 12}}, {"id": "player-3", "name": "演练丙", "alliance": "alliance-b", "home": {"x": 52, "y": 51}}], "marches": [{"id": "own-aid", "kind": "aid", "source": "player-1", "target": "player-2", "status": "stationed", "arrive": null}, {"id": "foreign-aid", "kind": "aid", "source": "player-2", "target": "player-1", "status": "stationed", "arrive": null}, {"id": "own-raid", "kind": "raid", "source": "player-1", "target": "player-3", "status": "march", "arrive": now + 61000}, {"id": "own-return", "kind": "aid", "source": "player-1", "target": "player-2", "status": "return", "returnAt": now + 121000}], "reports": [{"id": "same-report", "source": "player-1", "target": "player-3", "won": true, "loot": {"food": 100}}]}

func _run() -> void:
	var dialog: KingdomPvpDialog = preload("res://src/pvp_dialog.gd").new()
	root.add_child(dialog)
	var commands: Array[Dictionary] = []
	var reports: Array[Dictionary] = []
	var focus: Array[Vector2i] = []
	dialog.command_requested.connect(func(type: String, args: Array) -> void: commands.append({"type": type, "args": args}))
	dialog.report_requested.connect(func(report: Dictionary) -> void: reports.append(report))
	dialog.focus_requested.connect(func(x: int, y: int) -> void: focus.append(Vector2i(x, y)))
	var now: float = Time.get_unix_time_from_system() * 1000.0
	var view: Dictionary = _view()
	var shared: Dictionary = _shared(now)
	var actor: Dictionary = {"id": "player-1", "name": "演练甲"}
	dialog.update_data(view, shared, actor, now, true)
	dialog.show_world()
	await _settle()
	_assert(_buttons(dialog._list, "派遣援军").size() == 1 and _buttons(dialog._list, "配兵掠夺").size() == 1, "Only allied and enemy players get the corresponding deployment action; own city gets neither.")
	_assert(_buttons(dialog._list, "召回驻扎援军").size() == 1, "Only the actor's own stationed aid can be recalled.")
	var recall: Button = _buttons(dialog._list, "召回驻扎援军")[0]
	recall.pressed.emit()
	_assert(commands.size() == 1 and commands[0].type == "shared.recallAid" and commands[0].args[0].id == "own-aid", "Recall emits the server aid command with the exact owned march ID.")
	commands.clear()
	_buttons(dialog._list, "地图定位")[1].pressed.emit()
	_assert(focus == [Vector2i(10, 12)], "Map focus uses the shared player's actual coordinates.")
	_assert(dialog._eta_labels[0].text.contains("驻扎中") and dialog._eta_labels[2].text.contains("抵达") and dialog._eta_labels[3].text.contains("返城"), "Army labels distinguish stationing, outbound time and returning time.")
	var report_buttons: Array[Button] = _buttons(dialog._list, "演练甲 → 演练丙 · 攻方胜利")
	_assert(report_buttons.size() == 1, "The actual shared report is reachable from the list.")
	report_buttons[0].pressed.emit()
	_assert(reports.size() == 1 and reports[0].get("shared", false) and not shared.reports[0].has("shared"), "Opening a shared report marks a copy without mutating public data.")
	dialog.update_data(view, shared, actor, now, false)
	for button: Button in dialog._command_buttons:
		_assert(button.disabled, "Every list mutation action disables when the connection is unavailable or an operation is pending.")
	recall.pressed.emit()
	_assert(commands.is_empty(), "A stale recall callback cannot issue a command after the connection becomes unavailable.")
	dialog.update_data(view, shared, actor, now, true)
	for button: Button in dialog._command_buttons:
		_assert(not button.disabled, "Mutation actions become usable after a confirmed refresh.")
	dialog._dispatch(shared.players[0])
	_assert(dialog._form.get_child_count() == 0, "The deployment form refuses the actor's own city.")
	dialog._dispatch({"id": "npc-field", "name": "野地"})
	_assert(dialog._form.get_child_count() == 0, "The shared deployment form refuses a private NPC target.")
	dialog.show_dispatch(shared.players[2])
	await _settle()
	_assert(dialog._generals.item_count == 1 and dialog._generals.get_item_metadata(0) == "free-hero", "Deployment excludes both busy generals and the governor.")
	_assert(dialog._counts.has("cavalry") and dialog._counts.has("archer") and not dialog._counts.has("spear"), "Only available troops appear in the initial deployment form.")
	dialog._send.pressed.emit()
	_assert(commands.is_empty() and dialog._form_error.text.contains("至少"), "Zero selected soldiers cannot issue an attack.")
	var cavalry: SpinBox = dialog._counts.cavalry
	var form_general: OptionButton = dialog._generals
	cavalry.value = 12
	var changed_shared: Dictionary = shared.duplicate(true)
	changed_shared["reports"].append({"id": "new-report", "source": "player-3", "target": "player-2", "won": false})
	dialog.update_data(view, changed_shared, actor, now, true)
	_assert(dialog._counts.cavalry == cavalry and cavalry.value == 12 and dialog._generals == form_general, "Polling new reports must preserve the actual typed army draft and selected general controls.")
	cavalry.get_line_edit().text = "1200"
	dialog.update_data(view, changed_shared, actor, now, true)
	_assert(cavalry.get_line_edit().text == "1200", "Identical polling preserves uncommitted raw numeric text rather than resetting it through unchanged Range setters.")
	cavalry.get_line_edit().text = "12"
	dialog._send.pressed.emit()
	_assert(commands.size() == 1 and commands[0].type == "shared.attackPlayer", "Enemy deployment emits the shared player attack action.")
	var input: Dictionary = commands[0].args[0]
	_assert(input.targetId == "player-3" and input.targetCity == "capital" and input.mode == "raid" and input.general == "free-hero" and input.army == {"cavalry": 12}, "Attack payload retains the chosen target, general and exact troops without an occupation or result override.")
	_assert(cavalry.value == 12 and cavalry.get_line_edit().text == "12", "Submission applies the current raw troop text before building the command payload.")
	_assert(not input.has("now") and not input.has("serverTime") and not input.has("result"), "Deployment never supplies a clock or battle result.")
	dialog.show_request_error("其他设备已更新进度，请重读后再试")
	_assert(dialog._form_error.text.contains("其他设备已更新") and not dialog._send.disabled and dialog._counts.cavalry == cavalry and cavalry.value == 12, "A definite rejected dispatch replaces the pending message, enables only allowed actions and preserves its draft")
	dialog.update_data(view, changed_shared, actor, now, false)
	dialog.show_request_error("连接中断。可重连；未确认的操作会用原编号重试")
	_assert(dialog._form_error.text.contains("原编号") and dialog._send.disabled and not cavalry.editable, "An uncertain transport result presents reconnect guidance without permitting another dispatch")
	dialog.update_data(view, changed_shared, actor, now, true)
	var reject_synchronously: Callable = func(_type: String, _args: Array) -> void:
		dialog.show_request_error("无法保存操作回执，操作未发送")
	dialog.command_requested.connect(reject_synchronously)
	dialog._send.pressed.emit()
	_assert(dialog._form_error.text.contains("操作未发送") and not dialog._send.disabled, "A synchronous request rejection cannot be overwritten by the dispatch callback's pending message")
	dialog.command_requested.disconnect(reject_synchronously)
	dialog.acknowledge_command_success("train")
	_assert(not dialog._target.is_empty(), "Acknowledging an unrelated management action preserves the current army draft.")
	dialog.acknowledge_command_success("shared.attackPlayer")
	_assert(dialog._target.is_empty() and dialog._form.get_child_count() == 0 and dialog._message.text.contains("派遣已确认"), "Successful shared deployment clears its submitted form before the busy general refresh can leave a misleading warning.")
	commands.clear()
	dialog.show_dispatch(shared.players[1])
	(dialog._counts.archer as SpinBox).get_line_edit().text = "9"
	dialog._send.pressed.emit()
	_assert(commands.size() == 1 and commands[0].type == "shared.aid" and commands[0].args[0].targetId == "player-2", "Allied deployment emits aid rather than an attack.")
	commands.clear()
	dialog.update_data(view, shared, actor, now, false)
	dialog._send.pressed.emit()
	_assert(commands.is_empty() and dialog._send.disabled and not (dialog._counts.archer as SpinBox).editable, "An unavailable connection disables submission and troop editing, even through a stale button callback.")
	var reduced: Dictionary = view.duplicate(true)
	reduced.units[1].available = 4
	reduced.generals[0].busy = true
	dialog.update_data(reduced, shared, actor, now, true)
	_assert((dialog._counts.archer as SpinBox).value <= 4 and (dialog._counts.archer as SpinBox).max_value == 4, "A confirmed availability change clamps an existing army draft to actual remaining troops.")
	_assert(dialog._generals.item_count == 0 and dialog._form_error.text.contains("不可出征"), "A general who becomes busy is removed from the preserved deployment form.")
	dialog._send.pressed.emit()
	_assert(commands.is_empty() and dialog._form_error.text.contains("没有可出征"), "A stale general selection cannot issue a deployment.")
	dialog.update_data(view, shared, {"id": "player-2", "name": "演练乙"}, now, true)
	_assert(dialog._target.is_empty() and dialog._form.get_child_count() == 0 and dialog._counts.is_empty(), "Switching accounts clears the previous player's deployment draft.")
	dialog.update_data(view, shared, actor, now, true)
	for width: int in [1280, 390, 400]:
		root.size = Vector2i(width, 844)
		dialog.show_dispatch(shared.players[2])
		await _settle()
		_assert(dialog.size.x <= width and dialog.position.x >= 0 and dialog.position.x + dialog.size.x <= width, "The production PvP dialog stays inside the %d px viewport." % width)
		var scroll: ScrollContainer = dialog._form.get_parent().get_parent() as ScrollContainer
		_assert(scroll != null and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "The shared dialog uses a vertically scrollable narrow layout.")
		_assert(dialog._form.get_parent().get_combined_minimum_size().x <= scroll.size.x + 1.0, "The %d px deployment content does not require clipped horizontal scrolling." % width)
		_assert(dialog._form.get_index() < dialog._list.get_index() and scroll.scroll_vertical == 0, "Selecting a player shows the deployment form above the list at the top of its scroll viewport.")
		_assert(scroll.get_global_rect().intersects(dialog._generals.get_global_rect()), "The %d px player-selection form starts with its general picker visible." % width)
	dialog.hide()
	_assert(dialog._target.is_empty() and dialog._form.get_child_count() == 0, "Closing the dialog clears the draft before it can be reused for another target.")
	root.remove_child(dialog)
	dialog.queue_free()
	await process_frame
	print("Godot PvP UI checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)
