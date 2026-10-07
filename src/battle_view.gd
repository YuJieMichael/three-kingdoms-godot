class_name KingdomBattleView
extends Control

## Presentation only: the canonical runtime resolves every command and round.
signal action_requested(type: String, args: Array)

const GOLD: Color = Color("c4a168")
const PLAYER: Color = Color("96b6ad")
const ENEMY: Color = Color("d3947c")
const PAPER: Color = Color("eee3cc")
const ANIMATION_SECONDS: float = 0.95
const MOVE_SECONDS: float = 0.32
const ATTACK_END: float = 0.62
const CHINESE_FONT: Font = preload("res://assets/fonts/UI.tres")

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
var _unit_commands: HBoxContainer
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
		set_process(false)
		_refresh_controls()
		queue_redraw()
		return
	var next: Dictionary = (battle as Dictionary).duplicate(true)
	var next_identity: String = "%s|%s|%s|%s" % [next.get("node", ""), next.get("general", ""), next.get("sourceCity", ""), next.get("mode", "")]
	var next_round: int = int(next.get("round", 0))
	var restarted: bool = bool(_battle.get("finished", false)) and not bool(next.get("finished", false))
	var same_battle: bool = next_identity == _identity and next_round >= _observed_round and not restarted
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
	queue_redraw()

func set_actions_enabled(enabled: bool) -> void:
	_actions_enabled = enabled
	_refresh_controls()

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
	queue_redraw()

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
	_commands = GridContainer.new()
	_commands.columns = 4
	_commands.add_theme_constant_override("h_separation", 8)
	_commands.add_theme_constant_override("v_separation", 8)
	add_child(_commands)
	_add_button(_commands, "全部前进", "setBattleOrders", ["advance"])
	_add_button(_commands, "全部固守", "setBattleOrders", ["hold"])
	_add_button(_commands, "全部后退", "setBattleOrders", ["fallback"])
	_add_button(_commands, "下一回合", "battleRound", [])
	_unit_commands = HBoxContainer.new()
	_unit_commands.add_theme_constant_override("separation", 7)
	add_child(_unit_commands)
	for entry: Array in [["前进", "advance"], ["固守", "hold"], ["后退", "fallback"]]:
		var button: Button = Button.new()
		button.text = str(entry[0])
		button.custom_minimum_size = Vector2(70.0, 44.0)
		button.pressed.connect(_unit_order.bind(str(entry[1])))
		_unit_commands.add_child(button)
		_buttons.append(button)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", GOLD)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_logs = RichTextLabel.new()
	_logs.bbcode_enabled = false
	_logs.scroll_active = true
	_logs.selection_enabled = true
	_logs.add_theme_font_size_override("normal_font_size", 14)
	_logs.add_theme_color_override("default_color", Color("cbd1bd"))
	add_child(_logs)

func _add_button(parent: GridContainer, text: String, action: String, args: Array) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(86.0, 44.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_request.bind(action, args))
	parent.add_child(button)
	_buttons.append(button)

func _request(action: String, args: Array) -> void:
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
	_title.text = "%s · 第 %d / 30 回合" % [_battle.get("nodeName", _battle.get("node", "战场")), int(_battle.get("round", 0))] if exists else "军令与战场"
	if exists and size.x < 480.0:
		_title.text = "%s · 第 %d 回合" % [_battle.get("nodeName", _battle.get("node", "战场")), int(_battle.get("round", 0))]
	if finished:
		_title.text = "%s · 战斗%s" % [_battle.get("nodeName", _battle.get("node", "战场")), "胜利" if bool((_battle.get("result", {}) as Dictionary).get("won", false)) else "失利"]
	_subtitle.text = "点选我军看射程 · 改令下回合生效" if exists else "在舆图选择据点，派遣将领与部队；抵达后交战。"
	match animation_phase():
		"move": _subtitle.text = "① 正在移动 → ② 攻击 → ③ 伤亡"
		"attack": _subtitle.text = "① 已布阵 → ② 正在攻击 → ③ 伤亡"
		"impact": _subtitle.text = "① 已布阵 → ② 已命中 → ③ 伤亡"
	if finished and animation_phase() == "settled":
		_subtitle.text = "战斗已结算 · 战损、伤兵与去向见下方"
	_commands.visible = exists and not bool(_battle.get("finished", false))
	_unit_commands.visible = _commands.visible and not _selected.is_empty()
	for button: Button in _buttons:
		button.disabled = not _actions_enabled or bool(_battle.get("finished", false))
	_summary.visible = exists
	_logs.visible = exists
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
	var narrow: bool = size.x < 480.0
	_commands.columns = 2 if narrow else 4
	_title.add_theme_font_size_override("font_size", 21 if narrow else 23)
	_title.position = Vector2(18.0, 10.0)
	var content_width: float = maxf(1.0, size.x - 36.0)
	_title.size = Vector2(content_width, 30.0)
	_title.size.y = maxf(30.0, _title.get_minimum_size().y)
	_subtitle.position = Vector2(18.0, _title.position.y + _title.size.y + 2.0)
	_subtitle.size = Vector2(content_width, 20.0)
	_subtitle.size.y = maxf(20.0, _subtitle.get_minimum_size().y)
	_commands.position = Vector2(18.0, _subtitle.position.y + _subtitle.size.y + 6.0)
	_commands.size = Vector2(size.x - 36.0, _commands.get_combined_minimum_size().y)
	_unit_commands.position = Vector2(18.0, _commands.position.y + _commands.size.y + 6.0)
	_unit_commands.size = Vector2(size.x - 36.0, _unit_commands.get_combined_minimum_size().y)
	var summary_height: float = 42.0 if narrow else 26.0
	var minimum_height: float = maxf(540.0, _field_top() + 132.0 + 12.0 + summary_height + 6.0 + 88.0 + 12.0)
	if not is_equal_approx(custom_minimum_size.y, minimum_height):
		custom_minimum_size.y = minimum_height
	var field: Rect2 = _field_rect()
	_summary.position = Vector2(18.0, field.end.y + 12.0)
	_summary.size = Vector2(size.x - 36.0, 42.0 if narrow else 26.0)
	_logs.position = Vector2(18.0, _summary.position.y + _summary.size.y + 6.0)
	_logs.size = Vector2(content_width, maxf(88.0, size.y - _logs.position.y - 12.0))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_controls()
		_layout_controls()
		queue_redraw()

func _process(delta: float) -> void:
	var previous_phase: String = animation_phase()
	_animation_elapsed = minf(_animation_end, _animation_elapsed + delta)
	if previous_phase != animation_phase():
		_refresh_controls()
		_layout_controls()
	if _animation_elapsed >= _animation_end:
		_previous.clear()
	queue_redraw()
	if _animation_elapsed >= _animation_end:
		set_process(false)

func _field_rect() -> Rect2:
	var narrow: bool = size.x < 480.0
	var top: float = _field_top()
	var summary_height: float = 42.0 if narrow else 26.0
	var available_height: float = maxf(132.0, size.y - top - 12.0 - summary_height - 6.0 - 88.0 - 12.0)
	var field_height: float = minf(clampf(size.y * 0.35, 132.0, 520.0), available_height)
	return Rect2(Vector2(78.0, top), Vector2(maxf(180.0, size.x - 114.0), field_height))

func _field_top() -> float:
	if _battle.is_empty():
		return 111.0
	if not _built:
		return 254.0 if size.x < 480.0 else 185.0
	var controls_end: float = _subtitle.position.y + _subtitle.size.y
	if _commands.visible:
		controls_end = _commands.position.y + _commands.size.y
	if _unit_commands.visible:
		controls_end = _unit_commands.position.y + _unit_commands.size.y
		# Two status lines sit below the order buttons on every screen size;
		# leave the distance ruler its own space above the battlefield.
		return controls_end + 72.0
	return controls_end + (42.0 if size.x < 480.0 else 30.0)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("1b2928"))
	var field: Rect2 = _field_rect()
	draw_rect(field.grow(13.0), Color("354238"))
	for i: int in range(9):
		var x: float = field.position.x + field.size.x * float(i) / 8.0
		draw_line(Vector2(x, field.position.y), Vector2(x, field.end.y), Color(0.67, 0.70, 0.55, 0.08), 1.0)
		if not _battle.is_empty():
			_text(Vector2(x - 10.0, field.position.y - 12.0), str(roundi(float(_battle.get("length", 1000)) * float(i) / 8.0)), 11, Color("8e9a86"))
	for i: int in range(26):
		var p: Vector2 = Vector2(field.position.x + fmod(float(i) * 109.3, field.size.x), field.position.y + fmod(float(i) * 67.1, field.size.y))
		draw_line(p, p + Vector2(-3.0, -7.0), Color(0.27, 0.35, 0.26, 0.65), 1.0)
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
		draw_rect(Rect2(Vector2(left, lane - row_height * 0.26), Vector2(maxf(1.0, right - left), row_height * 0.51)), Color(0.34, 0.60, 0.49, 0.18))
	for index: int in range(_unit_ids.size()):
		var id: String = _unit_ids[index]
		var y: float = field.position.y + (float(index) + 0.5) * row_height
		draw_line(Vector2(field.position.x, y + row_height * 0.5), Vector2(field.end.x, y + row_height * 0.5), Color(0.55, 0.59, 0.47, 0.09), 1.0)
		_text(Vector2(10.0, y + 5.0), _unit_name(id), 12, Color("b5bd9f"))
		for side: String in ["player", "enemy"]:
			var row: Dictionary = _row(side, id)
			if row.is_empty():
				continue
			if float(row.get("hp", 0)) <= 0.0 and animation_phase() == "settled":
				continue
			_draw_formation(side, row, row_height)
	_draw_gate()
	_draw_effects()
	if not selection.is_empty() and _unit_commands.visible:
		var stats: Dictionary = selection.get("stats", {})
		var orders: Dictionary = _battle.get("orders", {})
		var selected_order: Dictionary = orders.get(_selected, {})
		var order_names: Dictionary = {"advance": "前进", "hold": "固守", "fallback": "后退"}
		var caption: String = "军令 %s · %s · 射程 %d" % [order_names.get(selected_order.get("command", ""), "未提供"), _unit_name(_selected), int(stats.get("range", 0))]
		if size.x >= 720.0:
			caption += " · 位置 %d" % int(selection.get("pos", 0))
		var caption_position: Vector2 = Vector2(18.0, _unit_commands.position.y + _unit_commands.size.y + 18.0)
		_draw_caption_line(caption_position, caption)
		_draw_caption_line(caption_position + Vector2(0.0, 18.0), "目标：" + _order_target_text(selected_order.get("target")))

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
	draw_string(CHINESE_FONT, point, text, HORIZONTAL_ALIGNMENT_LEFT, width, 13, PLAYER)

func _draw_formation(side: String, row: Dictionary, row_height: float) -> void:
	var id: String = str(row.get("id", ""))
	var pos: float = _animated_position(side, id, float(row.get("pos", 0)))
	var p: Vector2 = Vector2(_battle_x(pos), _lane_y(id, side))
	var color: Color = PLAYER if side == "player" else ENEMY
	var active_hit: bool = false
	var impact_progress: float = _impact_progress()
	if animation_phase() == "impact":
		for value: Variant in _events:
			var event: Dictionary = value
			if event.get("type", "") == "recoil" and event.get("side", "") == side and event.get("unit", "") == id:
				active_hit = true
				p.x += sin(impact_progress * TAU * 2.0) * 3.0 * pow(1.0 - impact_progress, 2.0)
				break
	var scale: float = clampf(row_height / 58.0, 0.52, 1.0)
	var hp: float = _visual_hp(side, id, float(row.get("hp", 0)))
	if hp <= 0.0:
		color.a = 0.35 * (1.0 - impact_progress)
	draw_circle(p + Vector2(0.0, 6.0), 17.0 * scale, Color(0.06, 0.09, 0.07, 0.50))
	for soldier: int in range(5):
		var soldier_point: Vector2 = p + Vector2((float(soldier % 3) - 1.0) * 10.0 * scale, float(soldier / 3) * 9.0 * scale)
		draw_line(soldier_point + Vector2(0.0, -3.0 * scale), soldier_point + Vector2(0.0, 7.0 * scale), Color("404c45"), 5.0 * scale)
		draw_circle(soldier_point + Vector2(0.0, -7.0 * scale), 3.0 * scale, color)
		draw_line(soldier_point + Vector2(5.0 * scale, -15.0 * scale), soldier_point + Vector2(4.0 * scale, 6.0 * scale), Color("acaa8e"), 1.0)
	var banner: Vector2 = p + Vector2(-12.0 * scale, -22.0 * scale)
	draw_line(banner, banner + Vector2(0.0, 24.0 * scale), GOLD, 1.5)
	draw_colored_polygon(PackedVector2Array([banner, banner + Vector2(22.0 * scale, 3.0 * scale), banner + Vector2(17.0 * scale, 13.0 * scale), banner + Vector2(0.0, 12.0 * scale)]), Color("375d53") if side == "player" else Color("804637"))
	var stats: Dictionary = row.get("stats", {})
	var count: int = ceili(hp / maxf(1.0, float(stats.get("hp", 1))))
	var max_hp: float = maxf(1.0, float(row.get("maxHp", hp)))
	draw_rect(Rect2(p + Vector2(-22.0, 14.0 * scale), Vector2(44.0, 4.0)), Color("182720"))
	draw_rect(Rect2(p + Vector2(-22.0, 14.0 * scale), Vector2(44.0 * clampf(hp / max_hp, 0.0, 1.0), 4.0)), color)
	_text(p + Vector2(-15.0, 31.0 * scale), str(count), 12, PAPER)
	if side == "player":
		_hit_boxes[id] = Rect2(p - Vector2(25.0, 27.0), Vector2(50.0, 60.0))
		if id == _selected:
			draw_arc(p, 25.0 * scale, 0.0, TAU, 32, GOLD, 1.5, true)
	if active_hit:
		draw_arc(p, 22.0 * scale, -0.5, 1.8, 12, Color(1.0, 0.58, 0.38, 1.0 - impact_progress), 3.0, true)

func _draw_gate() -> void:
	var gate_value: Variant = _battle.get("gate", null)
	if not gate_value is Dictionary:
		return
	var gate: Dictionary = gate_value
	var hp: float = float(gate.get("hp", 0))
	if animation_phase() in ["move", "attack"] and _previous.get("gate", null) is Dictionary:
		hp = float((_previous.get("gate") as Dictionary).get("hp", hp))
	var p: Vector2 = Vector2(_field_rect().end.x, _field_rect().position.y + 9.0)
	draw_rect(Rect2(p - Vector2(10.0, 6.0), Vector2(20.0, 30.0)), Color("747d6c") if hp > 0.0 else Color("434c3e"))
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
				draw_line(arrow - direction * 18.0, arrow, color, 2.0, true)
				draw_line(arrow, arrow - direction.rotated(0.6) * 6.0, color, 2.0, true)
				draw_line(arrow, arrow - direction.rotated(-0.6) * 6.0, color, 2.0, true)
			else:
				var impact: Vector2 = a.lerp(b, local)
				draw_line(impact + Vector2(-7.0, 9.0), impact + Vector2(7.0, -9.0), color, 3.0, true)
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
	return field.position.y + (float(index) + (0.31 if side == "player" else 0.69)) * field.size.y / float(maxi(1, _unit_ids.size()))

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
			_selected = str(value)
			queue_redraw()
			accept_event()
			return

func _text(point: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(CHINESE_FONT, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
