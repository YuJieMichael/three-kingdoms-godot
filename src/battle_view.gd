class_name KingdomBattleView
extends Control

## Presentation only: the canonical runtime resolves every command and round.
signal action_requested(type: String, args: Array)

const GOLD: Color = Color("c4a168")
const PLAYER: Color = Color("70c1ec")
const ENEMY: Color = Color("ef8e7f")
const PAPER: Color = Color("eee3cc")
const ANIMATION_SECONDS: float = 1.8
const MOVE_SECONDS: float = 0.65
const ATTACK_END: float = 1.2
const CHINESE_FONT: Font = preload("res://assets/fonts/UI.tres")
const FIELD_ART: Texture2D = preload("res://assets/units/terrain.png")
const TROOP_ART: Texture2D = preload("res://assets/units/troops.png")
const TROOP_CELLS: Array[String] = ["worker", "militia", "scout", "spear", "shield", "archer", "cavalry", "heavy", "wagon", "ballista", "ram", "catapult"]

class FieldCanvas:
	extends Control
	var paint: Callable
	var input: Callable
	func _draw() -> void:
		if paint.is_valid():
			paint.call(self)
	func _gui_input(event: InputEvent) -> void:
		if input.is_valid():
			input.call(event)

var _field_scroll: ScrollContainer
var _field_canvas: FieldCanvas
var _painter: CanvasItem
var _battle: Dictionary = {}
var _previous: Dictionary = {}
var _units: Dictionary = {}
var _unit_ids: Array[String] = []
var _events: Array = []
var _identity: String = ""
var _observed_round: int = -1
var _animation_elapsed: float = ANIMATION_SECONDS
var _movement_end: float = MOVE_SECONDS
var _attack_end: float = ATTACK_END
var _animation_end: float = ANIMATION_SECONDS
var _selected: String = ""
var _hit_boxes: Dictionary = {}
var _actions_enabled: bool = true
var _built: bool = false
var _feedback: Node
var _reduced_motion: bool = false
var _title: Label
var _subtitle: Label
var _summary: Label
var _commands: GridContainer
var _unit_selector: OptionButton
var _unit_commands: HBoxContainer
var _target_commands: GridContainer
var _target_selector: OptionButton
var _confirm_target: Button
var _target_drafts: Dictionary = {}
var _target_dirty: Dictionary = {}
var _paused_focus: Control
var _logs: RichTextLabel
var _buttons: Array[Button] = []

func _ready() -> void:
	custom_minimum_size = Vector2(320.0, 540.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_controls()
	_bind_feedback()
	_refresh_controls()
	_layout_controls()
	set_process(false)

func set_battle(battle: Variant, units: Dictionary = {}) -> void:
	_bind_feedback()
	_units = units.duplicate(true)
	if not battle is Dictionary or (battle as Dictionary).is_empty():
		_battle.clear()
		_previous.clear()
		_events.clear()
		_identity = ""
		_observed_round = -1
		_animation_elapsed = ANIMATION_SECONDS
		_unit_ids.clear()
		_selected = ""
		_target_drafts.clear()
		_target_dirty.clear()
		_paused_focus = null
		set_process(false)
		_refresh_controls()
		_redraw()
		return
	var next: Dictionary = (battle as Dictionary).duplicate(true)
	var next_identity: String = "%s|%s|%s|%s" % [next.get("node", ""), next.get("general", ""), next.get("sourceCity", ""), next.get("mode", "")]
	var next_round: int = int(next.get("round", 0))
	var restarted: bool = bool(_battle.get("finished", false)) and not bool(next.get("finished", false))
	var same_battle: bool = next_identity == _identity and next_round >= _observed_round and not restarted
	if not same_battle:
		_target_drafts.clear()
		_target_dirty.clear()
	if same_battle and next_round == _observed_round + 1:
		_previous = _battle.duplicate(true)
		var summary: Dictionary = next.get("currentRoundSummary", {})
		_events = summary.get("events", []).duplicate(true) if int(summary.get("round", -1)) == next_round else []
		_configure_animation()
		_animation_elapsed = 0.0 if _animation_end > 0.0 and not _reduced_motion else ANIMATION_SECONDS
		set_process(_animation_elapsed < _animation_end)
	elif not same_battle or next_round > _observed_round + 1:
		# A restored or newly opened battle seeds the baseline without replaying it.
		_previous.clear()
		_events.clear()
		_animation_elapsed = ANIMATION_SECONDS
		set_process(false)
	_battle = next
	_identity = next_identity
	_observed_round = next_round
	_unit_ids.clear()
	for side: String in ["player", "enemy"]:
		for value: Variant in _battle.get(side, []):
			if value is Dictionary:
				var id: String = str((value as Dictionary).get("id", ""))
				if not id.is_empty() and not _unit_ids.has(id):
					_unit_ids.append(id)
	if _selected.is_empty() or _row("player", _selected).is_empty() or float(_row("player", _selected).get("hp", 0)) <= 0.0:
		_selected = ""
		for value: Variant in _battle.get("player", []):
			var row: Dictionary = value
			if float(row.get("hp", 0)) > 0.0:
				_selected = str(row.get("id", ""))
				break
	_refresh_controls()
	_layout_controls()
	_redraw()

func set_actions_enabled(enabled: bool) -> void:
	if _built and _actions_enabled and not enabled and is_inside_tree():
		var focused: Control = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focused) and is_ancestor_of(focused):
			_paused_focus = focused
	_actions_enabled = enabled
	_refresh_controls()
	if enabled and is_instance_valid(_paused_focus):
		call_deferred("_restore_action_focus")

func animation_events() -> Array:
	return _events.duplicate(true)

func observed_round() -> int:
	return _observed_round

func animation_phase() -> String:
	if _reduced_motion or _animation_elapsed >= _animation_end:
		return "settled"
	if _animation_elapsed < _movement_end:
		return "move"
	if _animation_elapsed < _attack_end:
		return "attack"
	return "impact"

func _configure_animation() -> void:
	var has_moves: bool = false
	var has_attacks: bool = false
	var has_impacts: bool = false
	for value: Variant in _events:
		var event: Dictionary = value
		var type: String = str(event.get("type", ""))
		has_moves = has_moves or type == "move"
		has_attacks = has_attacks or type in ["strike", "tower", "gate"]
		has_impacts = has_impacts or type == "recoil"
	_movement_end = MOVE_SECONDS if has_moves else 0.0
	_attack_end = _movement_end + (ATTACK_END - MOVE_SECONDS if has_attacks else 0.0)
	_animation_end = _attack_end + (ANIMATION_SECONDS - ATTACK_END if has_impacts else 0.0)

func _bind_feedback() -> void:
	if not is_inside_tree():
		return
	var service: Node = get_tree().get_first_node_in_group("ui_feedback")
	if service != _feedback:
		if is_instance_valid(_feedback) and _feedback.is_connected("preferences_changed", _feedback_preferences_changed):
			_feedback.disconnect("preferences_changed", _feedback_preferences_changed)
		_feedback = service
		if is_instance_valid(_feedback) and _feedback.has_signal("preferences_changed"):
			_feedback.connect("preferences_changed", _feedback_preferences_changed)
	_feedback_preferences_changed()

func _feedback_preferences_changed() -> void:
	_reduced_motion = bool(_feedback.get("reduced_motion")) if is_instance_valid(_feedback) else false
	if _reduced_motion:
		# Preferences settle presentation immediately; canonical state and commands stay live.
		_animation_elapsed = ANIMATION_SECONDS
		_previous.clear()
		set_process(false)
	_refresh_controls()
	_layout_controls()
	_redraw()

func _build_controls() -> void:
	if _built:
		return
	_built = true
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 23)
	_title.add_theme_color_override("font_color", PAPER)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_color_override("font_color", Color("aab5a5"))
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_subtitle)
	_field_scroll = ScrollContainer.new()
	_field_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_field_scroll)
	_field_canvas = FieldCanvas.new()
	_field_canvas.paint = _paint_field
	_field_canvas.input = _gui_input
	_field_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_scroll.add_child(_field_canvas)
	_commands = GridContainer.new()
	_commands.columns = 4
	_commands.add_theme_constant_override("h_separation", 8)
	_commands.add_theme_constant_override("v_separation", 8)
	add_child(_commands)
	_add_button(_commands, "全部前进", "setBattleOrders", ["advance"])
	_add_button(_commands, "全部防守", "setBattleOrders", ["hold"])
	_add_button(_commands, "全部后退", "setBattleOrders", ["fallback"])
	_add_button(_commands, "下一回合", "battleRound", [])
	_unit_selector = _make_selector("选择我军兵队，仅查看，不下达军令。")
	add_child(_unit_selector)
	_unit_selector.item_selected.connect(_select_unit)
	_unit_commands = HBoxContainer.new()
	_unit_commands.add_theme_constant_override("separation", 7)
	add_child(_unit_commands)
	for entry: Array in [["前进", "advance"], ["防守", "hold"], ["后退", "fallback"]]:
		var button: Button = Button.new()
		button.text = str(entry[0])
		button.custom_minimum_size = Vector2(70.0, 44.0)
		button.pressed.connect(_unit_order.bind(str(entry[1])))
		_unit_commands.add_child(button)
		_buttons.append(button)
	_target_commands = GridContainer.new()
	_target_commands.columns = 2
	_target_commands.add_theme_constant_override("h_separation", 8)
	_target_commands.add_theme_constant_override("v_separation", 6)
	add_child(_target_commands)
	_target_selector = _make_selector("选择待确认的攻击目标；确认后按现有射程和寻敌规则结算。")
	_target_commands.add_child(_target_selector)
	_target_selector.item_selected.connect(_select_target)
	_confirm_target = Button.new()
	_confirm_target.text = "确认攻击目标"
	_confirm_target.theme_type_variation = "UtilityButton"
	_confirm_target.custom_minimum_size.y = 44.0
	_confirm_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_target.tooltip_text = "保留此兵队当前前进／固守／后退军令，仅确认攻击目标；下回合按真实规则生效。"
	_confirm_target.pressed.connect(_send_target)
	_target_commands.add_child(_confirm_target)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", GOLD)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_logs = RichTextLabel.new()
	_logs.bbcode_enabled = false
	_logs.scroll_active = true
	_logs.selection_enabled = true
	_logs.focus_mode = Control.FOCUS_ALL
	_logs.add_theme_font_size_override("normal_font_size", 14)
	_logs.add_theme_color_override("default_color", Color("cbd1bd"))
	add_child(_logs)

func _make_selector(hint: String) -> OptionButton:
	var selector: OptionButton = OptionButton.new()
	selector.custom_minimum_size.y = 44.0
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.focus_mode = Control.FOCUS_ALL
	selector.theme_type_variation = "UtilityButton"
	selector.fit_to_longest_item = false
	selector.clip_text = true
	selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selector.tooltip_text = hint
	return selector

func _living_ids(side: String) -> Array[String]:
	var ids: Array[String] = []
	for value: Variant in _battle.get(side, []):
		if value is Dictionary:
			var row: Dictionary = value
			var id: String = str(row.get("id", ""))
			if not id.is_empty() and float(row.get("hp", 0)) > 0.0 and not ids.has(id):
				ids.append(id)
	return ids

func _target_ids() -> Array[String]:
	var ids: Array[String] = [""]
	var gate: Variant = _battle.get("gate")
	if gate is Dictionary and float(gate.get("hp", 0)) > 0.0:
		ids.append("gate")
	ids.append_array(_living_ids("enemy"))
	return ids

func _selector_ids(selector: OptionButton) -> Array[String]:
	var ids: Array[String] = []
	for index: int in range(selector.item_count):
		ids.append(str(selector.get_item_metadata(index)))
	return ids

func _formation_choice(side: String, id: String) -> String:
	var row: Dictionary = _row(side, id)
	var stats: Dictionary = row.get("stats", {})
	var count: int = ceili(float(row.get("hp", 0)) / maxf(1.0, float(stats.get("hp", 1))))
	return "%s · %s · %d 人" % ["我军" if side == "player" else "敌军", _unit_name(id), count]

func _sync_selector(selector: OptionButton, ids: Array[String], side: String, selected: String) -> void:
	# Keep the Control itself and unchanged item lists alive across polling and rounds.
	if _selector_ids(selector) != ids:
		selector.clear()
		for id: String in ids:
			selector.add_item("")
			selector.set_item_metadata(selector.item_count - 1, id)
	for index: int in range(ids.size()):
		var id: String = ids[index]
		var text: String = _formation_choice(side, id)
		if side == "enemy" and id.is_empty():
			text = "目标 · 自动寻敌"
		elif side == "enemy" and id == "gate":
			text = "目标 · 城门 · 耐久 %d" % int((_battle.get("gate", {}) as Dictionary).get("hp", 0))
		selector.set_item_text(index, text)
		selector.set_item_tooltip(index, text)
	if not ids.is_empty():
		selector.select(maxi(0, ids.find(selected)))

func _refresh_selectors() -> void:
	var own: Array[String] = _living_ids("player")
	if not own.has(_selected):
		_selected = own[0] if not own.is_empty() else ""
	_sync_selector(_unit_selector, own, "player", _selected)
	var targets: Array[String] = _target_ids()
	var order: Dictionary = (_battle.get("orders", {}) as Dictionary).get(_selected, {})
	var actual: String = str(order.get("target", ""))
	if not bool(_target_dirty.get(_selected, false)) or not _target_drafts.has(_selected):
		_target_drafts[_selected] = actual
	var draft: String = str(_target_drafts.get(_selected, ""))
	if not targets.has(draft):
		draft = ""
		_target_drafts[_selected] = draft
	_target_dirty[_selected] = draft != actual
	_sync_selector(_target_selector, targets, "enemy", draft)
	_target_selector.tooltip_text = "已下达：%s\n待确认：%s\n选择目标仅预览；按“确认攻击目标”后下达。" % [_order_target_text(actual), _order_target_text(draft)]

func _select_unit(index: int) -> void:
	if _unit_selector.disabled or index < 0 or index >= _unit_selector.item_count:
		return
	var id: String = str(_unit_selector.get_item_metadata(index))
	if not _living_ids("player").has(id):
		return
	_selected = id
	_refresh_controls()
	_layout_controls()
	_redraw()

func _select_target(index: int) -> void:
	if _target_selector.disabled or _selected.is_empty() or index < 0 or index >= _target_selector.item_count:
		return
	var target: String = str(_target_selector.get_item_metadata(index))
	if _target_ids().has(target):
		_target_drafts[_selected] = target
		_target_dirty[_selected] = true
		_refresh_selectors()

func _send_target() -> void:
	if _confirm_target.disabled or not _living_ids("player").has(_selected):
		return
	var target: String = str(_target_drafts.get(_selected, ""))
	var order: Dictionary = (_battle.get("orders", {}) as Dictionary).get(_selected, {})
	var command: String = str(order.get("command", ""))
	if _target_ids().has(target) and command in ["advance", "hold", "fallback"]:
		_request("setBattleOrder", [_selected, command, target])

func _restore_action_focus() -> void:
	if not _actions_enabled or not is_inside_tree() or not is_visible_in_tree():
		return
	var target: Control = _paused_focus
	_paused_focus = null
	var focused: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and not is_ancestor_of(focused):
		return
	if is_instance_valid(target) and target.is_visible_in_tree() and not (target is BaseButton and (target as BaseButton).disabled):
		target.grab_focus()
	elif _logs.visible:
		_logs.grab_focus()

func _wire_focus() -> void:
	if not is_inside_tree():
		return
	var controls: Array[Control] = []
	for control: Control in [_unit_selector, _target_selector, _confirm_target, _logs]:
		control.focus_previous = NodePath()
		control.focus_next = NodePath()
		control.focus_neighbor_top = NodePath()
		control.focus_neighbor_bottom = NodePath()
	for button: Button in _buttons:
		button.focus_previous = NodePath()
		button.focus_next = NodePath()
		button.focus_neighbor_top = NodePath()
		button.focus_neighbor_bottom = NodePath()
	for button: Button in _buttons.slice(0, 4):
		if button.is_visible_in_tree() and not button.disabled:
			controls.append(button)
	if _unit_selector.is_visible_in_tree() and not _unit_selector.disabled:
		controls.append(_unit_selector)
	for button: Button in _buttons.slice(4):
		if button.is_visible_in_tree() and not button.disabled:
			controls.append(button)
	for control: Control in [_target_selector, _confirm_target, _logs]:
		if control.is_visible_in_tree() and not (control is BaseButton and (control as BaseButton).disabled):
			controls.append(control)
	for index: int in range(controls.size()):
		var control: Control = controls[index]
		control.focus_previous = controls[index - 1].get_path() if index > 0 else NodePath()
		control.focus_next = controls[index + 1].get_path() if index + 1 < controls.size() else NodePath()
		control.focus_neighbor_top = control.focus_previous
		control.focus_neighbor_bottom = control.focus_next

func _add_button(parent: GridContainer, text: String, action: String, args: Array) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(86.0, 44.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_request.bind(action, args))
	parent.add_child(button)
	_buttons.append(button)

func _request(action: String, args: Array) -> void:
	if action == "battleRound" and animation_phase() != "settled":
		return
	if _actions_enabled and not _battle.is_empty() and not bool(_battle.get("finished", false)):
		action_requested.emit(action, args.duplicate(true))

func _unit_order(command: String) -> void:
	if not _selected.is_empty():
		_request("setBattleOrder", [_selected, command])

func _refresh_controls() -> void:
	if not _built:
		return
	var exists: bool = not _battle.is_empty()
	var finished: bool = bool(_battle.get("finished", false))
	if finished and is_inside_tree():
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused is BaseButton and is_ancestor_of(focused):
			_paused_focus = focused
	_title.text = "%s · 第 %d / 30 回合" % [_battle.get("nodeName", _battle.get("node", "战场")), int(_battle.get("round", 0))] if exists else "军令与战场"
	if exists and size.x < 480.0:
		_title.text = "%s · 第 %d 回合" % [_battle.get("nodeName", _battle.get("node", "战场")), int(_battle.get("round", 0))]
	if finished:
		_title.text = "%s · 战斗%s" % [_battle.get("nodeName", _battle.get("node", "战场")), "胜利" if bool((_battle.get("result", {}) as Dictionary).get("won", false)) else "失利"]
	_subtitle.text = "蓝色我军 / 红色敌军 · 点击兵种图下军令 · 数字为当前人数 · 下一回合结算移动与攻击" if exists else "在舆图选择据点，派遣将领与部队；抵达后交战。"
	match animation_phase():
		"move": _subtitle.text = "① 正在移动 → ② 攻击 → ③ 伤亡"
		"attack": _subtitle.text = "① 已布阵 → ② 正在攻击 → ③ 伤亡"
		"impact": _subtitle.text = "① 已布阵 → ② 已命中 → ③ 伤亡"
	if finished and animation_phase() == "settled":
		_subtitle.text = "战斗已结算 · 战损、伤兵与去向见下方"
	_commands.visible = exists and not bool(_battle.get("finished", false))
	_refresh_selectors()
	_unit_selector.visible = _commands.visible and not _selected.is_empty()
	_unit_commands.visible = _commands.visible and not _selected.is_empty()
	_target_commands.visible = _unit_commands.visible
	var can_command: bool = exists and _actions_enabled and not finished and not _selected.is_empty()
	_unit_selector.disabled = not can_command
	_target_selector.disabled = not can_command
	_confirm_target.disabled = not can_command
	for button: Button in _buttons:
		button.disabled = not can_command
	if _buttons.size() >= 4:
		_buttons[3].disabled = not can_command or animation_phase() != "settled"
	_summary.visible = exists
	_logs.visible = exists
	_wire_focus()
	if finished and _actions_enabled and is_instance_valid(_paused_focus):
		call_deferred("_restore_action_focus")
	if not exists:
		return
	var round_summary: Dictionary = _battle.get("currentRoundSummary", {})
	var own_down: int = 0
	var enemy_down: int = 0
	var summary_lines: Array[String] = []
	if int(round_summary.get("round", -1)) == int(_battle.get("round", 0)):
		for value: Variant in round_summary.get("events", []):
			var event: Dictionary = value
			if str(event.get("type", "")) in ["strike", "tower", "gate"]:
				if str(event.get("type", "")) != "gate":
					if str(event.get("side", "")) == "player":
						enemy_down += int(event.get("killed", 0))
					else:
						own_down += int(event.get("killed", 0))
				summary_lines.append(_event_text(event))
	_summary.text = "本回合我军倒下 %d · 敌军倒下 %d · 战后判定伤兵" % [own_down, enemy_down]
	var lines: Array[String] = []
	if bool(_battle.get("finished", false)):
		lines.append(_result_text(_battle.get("result", {})))
	if not summary_lines.is_empty():
		lines.append("本回合攻击经过\n" + "\n".join(summary_lines))
	var canonical_logs: Array[String] = []
	for line: Variant in _battle.get("log", []):
		canonical_logs.append(str(line))
	lines.append("完整战斗日志\n" + "\n".join(canonical_logs))
	_logs.text = "\n\n".join(lines)

func _layout_controls() -> void:
	if not _built:
		return
	var narrow: bool = size.x < 600.0
	_commands.columns = 2 if narrow else 4
	_target_commands.columns = 1 if narrow else 2
	var content_width: float = maxf(1.0, size.x - 36.0)
	_title.position = Vector2(18, 10)
	_title.size = Vector2(content_width, 32)
	_subtitle.position = Vector2(18, 46)
	_subtitle.size = Vector2(content_width, 40 if narrow else 22)
	_field_canvas.custom_minimum_size = Vector2(240, maxf(320, float(_unit_ids.size()) * 124))
	_field_scroll.position = Vector2(0, _field_top())
	_field_scroll.size = Vector2(size.x, 420)
	_summary.position = Vector2(18, _field_scroll.position.y + _field_scroll.size.y + 8)
	_summary.size = Vector2(content_width, 42 if narrow else 28)
	_commands.position = Vector2(18, _summary.position.y + _summary.size.y + 6)
	_commands.size = Vector2(content_width, _commands.get_combined_minimum_size().y)
	_unit_selector.position = Vector2(18, _commands.position.y + _commands.size.y + 6)
	_unit_selector.size = Vector2(content_width if narrow else content_width * 0.55, 44)
	_unit_commands.position = Vector2(18 if narrow else 26 + content_width * 0.55, _unit_selector.position.y + (50 if narrow else 0))
	_unit_commands.size = Vector2(content_width if narrow else content_width * 0.45 - 8, 44)
	_target_commands.position = Vector2(18, _unit_commands.position.y + 50)
	_target_commands.size = Vector2(content_width, _target_commands.get_combined_minimum_size().y)
	_logs.position = Vector2(18, _target_commands.position.y + _target_commands.size.y + 48)
	_logs.size = Vector2(content_width, 140)
	var min_height: float = _logs.position.y + _logs.size.y + 12
	if not is_equal_approx(custom_minimum_size.y, min_height):
		custom_minimum_size.y = min_height

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_controls()
		_layout_controls()
		_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and _built:
		_wire_focus()

func _process(delta: float) -> void:
	var previous_phase: String = animation_phase()
	_animation_elapsed = minf(_animation_end, _animation_elapsed + delta)
	if previous_phase != animation_phase():
		_refresh_controls()
		_layout_controls()
	if _animation_elapsed >= _animation_end:
		_previous.clear()
	_redraw()
	if _animation_elapsed >= _animation_end:
		set_process(false)

func _field_rect() -> Rect2:
	var field_height: float = maxf(280, _field_canvas.size.y - 30)
	return Rect2(Vector2(90, 22), Vector2(maxf(180, _field_canvas.size.x - 152), field_height))

func _field_top() -> float:
	return 104.0 if size.x < 600.0 else 90.0

func _redraw() -> void:
	queue_redraw()
	if is_instance_valid(_field_canvas):
		_field_canvas.queue_redraw()

func _draw() -> void:
	_painter = self
	_painter.draw_rect(Rect2(Vector2.ZERO, size), Color("28251f"))
	var selection: Dictionary = _row("player", _selected)
	if not selection.is_empty() and _unit_commands.visible:
		var stats: Dictionary = selection.get("stats", {})
		var orders: Dictionary = _battle.get("orders", {})
		var selected_order: Dictionary = orders.get(_selected, {})
		var order_names: Dictionary = {"advance": "前进", "hold": "防守", "fallback": "后退"}
		var caption: String = "军令 %s · %s · 射程 %d" % [order_names.get(selected_order.get("command", ""), "未提供"), _unit_name(_selected), int(stats.get("range", 0))]
		if size.x >= 720.0:
			caption += " · 位置 %d · 速度 %d" % [int(selection.get("pos", 0)), int(stats.get("speed", 0))]
		var caption_position: Vector2 = Vector2(18.0, _target_commands.position.y + _target_commands.size.y + 18.0)
		_draw_caption_line(caption_position, caption)
		_draw_caption_line(caption_position + Vector2(0.0, 18.0), "目标：" + _order_target_text(selected_order.get("target")))

func _paint_field(canvas: CanvasItem) -> void:
	_painter = canvas
	var field: Rect2 = _field_rect()
	_painter.draw_rect(field.grow(13.0), Color("566047"))
	var tile_size: Vector2 = FIELD_ART.get_size() / Vector2(4, 3)
	var crop_height: float = minf(tile_size.y, tile_size.x * field.size.y / field.size.x)
	var source: Rect2 = Rect2(Vector2(2 * tile_size.x, tile_size.y + (tile_size.y - crop_height) * 0.5), Vector2(tile_size.x, crop_height))
	_painter.draw_texture_rect_region(FIELD_ART, field, source, Color(0.72, 0.72, 0.65))
	for i: int in range(9):
		var x: float = field.position.x + field.size.x * float(i) / 8.0
		_painter.draw_line(Vector2(x, field.position.y), Vector2(x, field.end.y), Color(0.67, 0.70, 0.55, 0.08), 1.0)
		if not _battle.is_empty():
			_text(Vector2(x - 10.0, field.position.y - 8.0), str(roundi(float(_battle.get("length", 1000)) * float(i) / 8.0)), 13, Color("e5d7b7"))
	for i: int in range(26):
		var p: Vector2 = Vector2(field.position.x + fmod(float(i) * 109.3, field.size.x), field.position.y + fmod(float(i) * 67.1, field.size.y))
		_painter.draw_line(p, p + Vector2(-3.0, -7.0), Color(0.27, 0.35, 0.26, 0.65), 1.0)
	if _battle.is_empty():
		_text(Vector2(field.position.x + 18.0, field.position.y + 90.0), "暂无交战军队", 25, PAPER)
		_text(Vector2(field.position.x + 8.0, field.position.y + 123.0), "训练部队后，前往舆图出征", 14, GOLD)
		return
	_hit_boxes.clear()
	var row_height: float = field.size.y / float(maxi(1, _unit_ids.size()))
	var selection: Dictionary = _row("player", _selected)
	if not selection.is_empty() and float(selection.get("hp", 0)) > 0.0:
		var stats: Dictionary = selection.get("stats", {})
		var range_value: float = float(stats.get("range", (_units.get(_selected, {}) as Dictionary).get("range", 0)))
		var pos: float = _animated_position("player", _selected, float(selection.get("pos", 0)))
		var left: float = _battle_x(maxf(0.0, pos - range_value))
		var right: float = _battle_x(minf(float(_battle.get("length", 1000)), pos + range_value))
		var lane: float = _lane_y(_selected, "player")
		_painter.draw_rect(Rect2(Vector2(left, lane - row_height * 0.26), Vector2(maxf(1.0, right - left), row_height * 0.51)), Color(0.34, 0.60, 0.49, 0.18))
	for index: int in range(_unit_ids.size()):
		var id: String = _unit_ids[index]
		var y: float = field.position.y + (float(index) + 0.5) * row_height
		_painter.draw_line(Vector2(field.position.x, y + row_height * 0.5), Vector2(field.end.x, y + row_height * 0.5), Color(0.55, 0.59, 0.47, 0.09), 1.0)
		_text(Vector2(10.0, y + 5.0), _unit_name(id), 14, PAPER)
		for side: String in ["player", "enemy"]:
			var row: Dictionary = _row(side, id)
			if row.is_empty():
				continue
			_draw_formation(side, row, row_height)
	_draw_gate()
	_draw_effects()

func _order_target_text(value: Variant) -> String:
	if not value is String:
		return "未提供"
	if value.is_empty():
		return "自动选择"
	if value == "gate":
		return "城门"
	return _unit_name(value)

func _draw_caption_line(point: Vector2, caption: String) -> void:
	var width: float = maxf(1.0, size.x - point.x - 18.0)
	var text: String = caption
	if CHINESE_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x > width:
		while not text.is_empty() and CHINESE_FONT.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x > width:
			text = text.left(text.length() - 1)
		text += "…"
	_painter.draw_string(CHINESE_FONT, point, text, HORIZONTAL_ALIGNMENT_LEFT, width, 13, PLAYER)

func _draw_formation(side: String, row: Dictionary, _row_height: float) -> void:
	var id: String = str(row.get("id", ""))
	var pos: float = _animated_position(side, id, float(row.get("pos", 0)))
	var p: Vector2 = Vector2(_battle_x(pos), _lane_y(id, side))
	p.x = clampf(p.x, _field_rect().position.x + 60, _field_rect().end.x - 60)
	var color: Color = PLAYER if side == "player" else ENEMY
	var hp: float = _visual_hp(side, id, float(row.get("hp", 0)))
	var stats: Dictionary = row.get("stats", {})
	var count: int = ceili(hp / maxf(1, float(stats.get("hp", 1))))
	var card: Rect2 = Rect2(p - Vector2(58, 33), Vector2(116, 66))
	_painter.draw_rect(card.grow(2), GOLD if side == "player" and id == _selected else color)
	_painter.draw_rect(card, Color("20251e"))
	var cell: int = TROOP_CELLS.find(id)
	if cell >= 0:
		var source_size: Vector2 = TROOP_ART.get_size() / Vector2(4, 3)
		var source: Rect2 = Rect2(Vector2(cell % 4, floori(float(cell) / 4.0)) * source_size, source_size)
		_painter.draw_texture_rect_region(TROOP_ART, Rect2(card.position + Vector2(4, 4), Vector2(48, 48)), source, Color(1, 1, 1, 1 if hp > 0 else 0.3))
	_text(card.position + Vector2(56, 20), _unit_name(id), 14, color)
	_text(card.position + Vector2(56, 48), str(count), 23 if count < 10000 else 17, PAPER)
	_painter.draw_rect(Rect2(card.position + Vector2(4, 58), Vector2(108, 5)), Color("111810"))
	_painter.draw_rect(Rect2(card.position + Vector2(4, 58), Vector2(108 * clampf(hp / maxf(1, float(row.get("maxHp", hp))), 0, 1), 5)), color)
	if side == "player":
		_hit_boxes[id] = card.grow(4)
	if animation_phase() == "impact":
		for value: Variant in _events:
			var event: Dictionary = value
			if event.get("type") == "recoil" and event.get("side") == side and event.get("unit") == id:
				_painter.draw_rect(card, Color(1, 0.65, 0.3, 0.3 * (1 - _impact_progress())))
				break

func _draw_gate() -> void:
	var gate_value: Variant = _battle.get("gate", null)
	if not gate_value is Dictionary:
		return
	var gate: Dictionary = gate_value
	var hp: float = float(gate.get("hp", 0))
	if animation_phase() in ["move", "attack"] and _previous.get("gate", null) is Dictionary:
		hp = float((_previous.get("gate") as Dictionary).get("hp", hp))
	var p: Vector2 = Vector2(_field_rect().end.x, _field_rect().position.y + 9.0)
	_painter.draw_rect(Rect2(p - Vector2(10.0, 6.0), Vector2(20.0, 30.0)), Color("747d6c") if hp > 0.0 else Color("434c3e"))
	_text(p - Vector2(72.0, 9.0), "城防 %d" % int(hp), 12, GOLD)

func _draw_effects() -> void:
	var phase: String = animation_phase()
	if phase in ["move", "settled"]:
		return
	var progress: float = _impact_progress() if phase == "impact" else clampf((_animation_elapsed - _movement_end) / (ATTACK_END - MOVE_SECONDS), 0.0, 1.0)
	var recoil_counts: Dictionary = {}
	for value: Variant in _events:
		var event: Dictionary = value
		var type: String = str(event.get("type", ""))
		var side: String = str(event.get("side", "player"))
		var unit: String = str(event.get("unit", ""))
		var target: String = str(event.get("target", ""))
		if phase == "attack" and type in ["strike", "tower", "gate"]:
			var opposite: String = "enemy" if side == "player" else "player"
			var a: Vector2 = Vector2(_battle_x(float(event.get("from", 0))), _lane_y(unit, side))
			var b: Vector2 = Vector2(_battle_x(float(event.get("to", 0))), _lane_y(target, opposite))
			var local: float = 1.0 - pow(1.0 - progress, 2.0)
			var color: Color = GOLD if side == "player" else ENEMY
			color.a = 1.0 - local * 0.55
			if bool(event.get("ranged", false)):
				var arrow: Vector2 = a.lerp(b, local)
				var direction: Vector2 = (b - a).normalized()
				_painter.draw_line(arrow - direction * 18.0, arrow, color, 2.0, true)
				_painter.draw_line(arrow, arrow - direction.rotated(0.6) * 6.0, color, 2.0, true)
				_painter.draw_line(arrow, arrow - direction.rotated(-0.6) * 6.0, color, 2.0, true)
			else:
				var impact: Vector2 = a.lerp(b, local)
				_painter.draw_line(impact + Vector2(-7.0, 9.0), impact + Vector2(7.0, -9.0), color, 3.0, true)
		elif phase == "impact" and type == "recoil":
			var p: Vector2 = Vector2(_battle_x(float(event.get("to", 0))), _lane_y(unit, side))
			var killed: int = int(event.get("killed", 0))
			var caption: String = "−%d 人" % killed if killed > 0 else "伤害 %d" % int(event.get("damage", 0))
			var rise: float = 1.0 - pow(1.0 - progress, 3.0)
			var recoil_key: String = side + "|" + unit
			var offset_y: float = float(recoil_counts.get(recoil_key, 0)) * 18.0
			recoil_counts[recoil_key] = int(recoil_counts.get(recoil_key, 0)) + 1
			var font_size: int = 15
			var text_width: float = CHINESE_FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
			var text_x: float = clampf(p.x + 8.0, _field_rect().position.x, maxf(_field_rect().position.x, size.x - 18.0 - text_width))
			_text(Vector2(text_x, p.y - 20.0 - rise * 16.0 - offset_y), caption, font_size, Color(1.0, 0.64, 0.44, minf(1.0, (1.0 - progress) * 2.0)))

func _animated_position(side: String, id: String, final_position: float) -> float:
	if animation_phase() != "move":
		return final_position
	var moves: Array[Dictionary] = []
	for value: Variant in _events:
		var event: Dictionary = value
		if event.get("type", "") == "move" and event.get("side", "") == side and event.get("unit", "") == id:
			moves.append(event)
	if moves.is_empty():
		return final_position
	var progress: float = clampf(_animation_elapsed / MOVE_SECONDS, 0.0, 1.0) * float(moves.size())
	var index: int = mini(int(progress), moves.size() - 1)
	var local: float = clampf(progress - float(index), 0.0, 1.0)
	return lerpf(float(moves[index].get("from", final_position)), float(moves[index].get("to", final_position)), 1.0 - pow(1.0 - local, 3.0))

func _impact_progress() -> float:
	return clampf((_animation_elapsed - _attack_end) / (ANIMATION_SECONDS - ATTACK_END), 0.0, 1.0)

func _visual_hp(side: String, id: String, final_hp: float) -> float:
	if animation_phase() not in ["move", "attack"] or _previous.is_empty():
		return final_hp
	return float(_row(side, id, _previous).get("hp", final_hp))

func _battle_x(position_value: float) -> float:
	var field: Rect2 = _field_rect()
	return field.position.x + field.size.x * clampf(position_value / maxf(1.0, float(_battle.get("length", 1000))), 0.0, 1.0)

func _lane_y(id: String, side: String) -> float:
	var field: Rect2 = _field_rect()
	if id in ["gate", "tower"]:
		return field.position.y + 10.0
	var index: int = maxi(0, _unit_ids.find(id))
	return field.position.y + (float(index) + (0.22 if side == "player" else 0.78)) * field.size.y / float(maxi(1, _unit_ids.size()))

func _row(side: String, id: String, source: Dictionary = {}) -> Dictionary:
	var state: Dictionary = _battle if source.is_empty() else source
	for value: Variant in state.get(side, []):
		if value is Dictionary and str((value as Dictionary).get("id", "")) == id:
			return value
	return {}

func _unit_name(id: String) -> String:
	if id == "gate":
		return "城防"
	if id == "tower":
		return "箭楼"
	var unit: Dictionary = _units.get(id, {})
	return str(unit.get("name", id))

func _event_text(event: Dictionary) -> String:
	var side: String = "我军" if event.get("side", "") == "player" else "敌军"
	var target_side: String = "敌军" if event.get("side", "") == "player" else "我军"
	var verb: String = "反击" if bool(event.get("counter", false)) else "射击" if bool(event.get("ranged", false)) else "攻击"
	return "%s%s %s → %s%s · 伤害 %d%s" % [side, _unit_name(str(event.get("unit", ""))), verb, target_side, _unit_name(str(event.get("target", ""))), int(event.get("damage", 0)), " · 倒下 %d 人" % int(event.get("killed", 0)) if event.get("type", "") != "gate" else ""]

func _result_text(result: Dictionary) -> String:
	if result.get("practice", false):
		var simulated: String = "借调演练胜利" if result.get("won", false) else "借调演练失利"
		simulated += "\n模拟损失 %d · 模拟伤兵 %d · 幸存 %d" % [_army_total(result.get("lost", {})), _army_total(result.get("wounded", {})), _army_total(result.get("back", {}))]
		return simulated + "\n" + str(result.get("summary", "演练战损和奖励不进入正式进度。"))
	var title: String = "战斗胜利 · 旌旗报捷" if bool(result.get("won", false)) else "战斗失利 · 整军再战"
	var lines: Array[String] = [title, "永久损失 %d · 伤兵 %d · 将领经验 +%d" % [_army_total(result.get("lost", {})), _army_total(result.get("wounded", {})), int(result.get("xp", 0))]]
	if result.has("cargoLoaded"):
		lines.append("实际装载 %d / 运力 %d · 运力不足弃置 %d" % [int(result.get("cargoLoaded", 0)), int(result.get("cargoCapacity", 0)), int(result.get("lootDiscarded", 0)) + int(result.get("bonusDiscarded", 0))])
	var receipts: Dictionary = result.get("resourceReceipt", {})
	var received: Dictionary = {}
	for key: String in ["base", "bonus"]:
		var receipt: Dictionary = receipts.get(key, {})
		var resources: Dictionary = receipt.get("received", {})
		for resource: Variant in resources.keys():
			received[resource] = float(received.get(resource, 0)) + float(resources[resource])
	var resource_names: Dictionary = {"food": "粮草", "wood": "木材", "stone": "石料", "iron": "铁锭", "gold": "黄金"}
	var resources_text: Array[String] = []
	for resource: Variant in received.keys():
		if float(received[resource]) > 0.0:
			resources_text.append("%s %d" % [resource_names.get(resource, str(resource)), int(received[resource])])
	if not resources_text.is_empty():
		lines.append("实际入库：" + " · ".join(resources_text))
	if float(result.get("overCapacity", 0)) > 0.0:
		lines.append("其中 %d 资源超出仓库容量，已按战利品规则入库。" % int(result.get("overCapacity", 0)))
	if bool(result.get("stationed", false)):
		lines.append("部队已驻扎，可在军队与领地中查看。")
	elif result.has("back"):
		lines.append("幸存 %d 人已开始返程，行军时间以军队面板为准。" % _army_total(result.get("back", {})))
	var failure_value: Variant = result.get("failure", null)
	if failure_value is Dictionary:
		var failure: Dictionary = failure_value
		var reason_names: Dictionary = {"retreat": "主动撤退", "army": "我军失去战斗力", "gate": "城防未破", "enemy": "守军尚未歼灭", "gate_and_enemy": "城防未破且守军尚在"}
		lines.append("失利原因：%s%s" % [reason_names.get(failure.get("reason", ""), "见回合日志"), "；部分固守兵队未进入射程" if bool(failure.get("outOfRange", false)) else ""])
	return "\n".join(lines)

func _army_total(army: Dictionary) -> int:
	var total: int = 0
	for value: Variant in army.values():
		total += int(value)
	return total

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			_select_at(click.position)
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_select_at(touch.position)

func _select_at(point: Vector2) -> void:
	for value: Variant in _hit_boxes.keys():
		var rect: Rect2 = _hit_boxes[value]
		if rect.has_point(point):
			var id: String = str(value)
			if not _living_ids("player").has(id):
				continue
			_selected = id
			_refresh_controls()
			_layout_controls()
			_redraw()
			accept_event()
			return

func _text(point: Vector2, text: String, font_size: int, color: Color) -> void:
	_painter.draw_string(CHINESE_FONT, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
