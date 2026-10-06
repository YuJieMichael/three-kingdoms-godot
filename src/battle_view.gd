class_name KingdomBattleView
extends Control

## Presentation only: the canonical runtime resolves every command and round.
signal action_requested(type: String, args: Array)

const GOLD: Color = Color("c4a168")
const PLAYER: Color = Color("96b6ad")
const ENEMY: Color = Color("d3947c")
const PAPER: Color = Color("eee3cc")
const ANIMATION_SECONDS: float = 0.95
const CHINESE_FONT: Font = preload("res://assets/fonts/UI.tres")

var _battle: Dictionary = {}
var _previous: Dictionary = {}
var _units: Dictionary = {}
var _unit_ids: Array[String] = []
var _events: Array = []
var _identity: String = ""
var _observed_round: int = -1
var _animation_elapsed: float = ANIMATION_SECONDS
var _selected: String = ""
var _hit_boxes: Dictionary = {}
var _actions_enabled: bool = true
var _built: bool = false
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
	_refresh_controls()
	_layout_controls()
	set_process(false)

func set_battle(battle: Variant, units: Dictionary = {}) -> void:
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
		_animation_elapsed = 0.0 if not _events.is_empty() else ANIMATION_SECONDS
		set_process(not _events.is_empty())
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

func _build_controls() -> void:
	if _built:
		return
	_built = true
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 23)
	_title.add_theme_color_override("font_color", PAPER)
	_title.clip_text = true
	add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_color_override("font_color", Color("aab5a5"))
	_subtitle.clip_text = true
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
		button.custom_minimum_size = Vector2(70.0, 34.0)
		button.pressed.connect(_unit_order.bind(str(entry[1])))
		_unit_commands.add_child(button)
		_buttons.append(button)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", GOLD)
	_summary.clip_text = true
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
	button.custom_minimum_size = Vector2(86.0, 36.0)
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
	_title.text = "%s · 第 %d / 30 回合" % [_battle.get("nodeName", _battle.get("node", "战场")), int(_battle.get("round", 0))] if exists else "军令与战场"
	_subtitle.text = "点击我军兵队查看射程 · 改令从下一回合生效" if exists else "在大地图选择据点，派遣将领与部队；抵达后开始战斗。"
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
	_title.position = Vector2(18.0, 10.0)
	_title.size = Vector2(size.x - 36.0, 30.0)
	_subtitle.position = Vector2(18.0, 43.0)
	_subtitle.size = Vector2(size.x - 36.0, 22.0)
	_commands.position = Vector2(18.0, 74.0)
	_commands.size = Vector2(size.x - 36.0, _commands.get_combined_minimum_size().y)
	_unit_commands.position = Vector2(18.0, _commands.position.y + _commands.size.y + 6.0)
	_unit_commands.size = Vector2(size.x - 36.0, _unit_commands.get_combined_minimum_size().y)
	var summary_height: float = 42.0 if narrow else 26.0
	var minimum_height: float = maxf(600.0 if narrow else 540.0, _field_top() + 150.0 + 15.0 + summary_height + 8.0 + 104.0 + 16.0)
	if not is_equal_approx(custom_minimum_size.y, minimum_height):
		custom_minimum_size.y = minimum_height
	var field: Rect2 = _field_rect()
	_summary.position = Vector2(18.0, field.end.y + 15.0)
	_summary.size = Vector2(size.x - 36.0, 42.0 if narrow else 26.0)
	_logs.position = Vector2(18.0, _summary.position.y + _summary.size.y + 8.0)
	_logs.size = Vector2(size.x - 36.0, maxf(104.0, size.y - _logs.position.y - 16.0))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_controls()
		queue_redraw()

func _process(delta: float) -> void:
	_animation_elapsed = minf(ANIMATION_SECONDS, _animation_elapsed + delta)
	queue_redraw()
	if _animation_elapsed >= ANIMATION_SECONDS:
		set_process(false)

func _field_rect() -> Rect2:
	var narrow: bool = size.x < 480.0
	var top: float = _field_top()
	var summary_height: float = 42.0 if narrow else 26.0
	var available_height: float = maxf(150.0, size.y - top - 15.0 - summary_height - 8.0 - 104.0 - 16.0)
	var field_height: float = minf(clampf(size.y * 0.35, 150.0, 520.0), available_height)
	return Rect2(Vector2(78.0, top), Vector2(maxf(180.0, size.x - 114.0), field_height))

func _field_top() -> float:
	if _battle.is_empty():
		return 111.0
	if not _built:
		return 254.0 if size.x < 480.0 else 185.0
	return _unit_commands.position.y + _unit_commands.size.y + (60.0 if size.x < 480.0 else 35.0)

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
			if float(row.get("hp", 0)) <= 0.0 and _animation_elapsed >= ANIMATION_SECONDS:
				continue
			_draw_formation(side, row, row_height)
	_draw_gate()
	_draw_effects()
	if not selection.is_empty():
		var stats: Dictionary = selection.get("stats", {})
		var orders: Dictionary = _battle.get("orders", {})
		var selected_order: Dictionary = orders.get(_selected, {})
		var order_names: Dictionary = {"advance": "前进", "hold": "固守", "fallback": "后退"}
		var caption: String = "%s · %s · 位置 %d · 射程 %d" % [_unit_name(_selected), order_names.get(selected_order.get("command", "hold"), ""), int(selection.get("pos", 0)), int(stats.get("range", 0))] if size.x >= 720.0 else "%s · 射程 %d" % [_unit_name(_selected), int(stats.get("range", 0))]
		var caption_position: Vector2 = Vector2(18.0, _unit_commands.position.y + _unit_commands.size.y + 23.0) if size.x < 480.0 else Vector2(260.0, _unit_commands.position.y + _unit_commands.size.y * 0.65)
		_text(caption_position, caption, 13, PLAYER)

func _draw_formation(side: String, row: Dictionary, row_height: float) -> void:
	var id: String = str(row.get("id", ""))
	var pos: float = _animated_position(side, id, float(row.get("pos", 0)))
	var p: Vector2 = Vector2(_battle_x(pos), _lane_y(id, side))
	var color: Color = PLAYER if side == "player" else ENEMY
	var active_hit: bool = false
	if _animation_elapsed < ANIMATION_SECONDS:
		for value: Variant in _events:
			var event: Dictionary = value
			if event.get("type", "") == "recoil" and event.get("side", "") == side and event.get("unit", "") == id:
				active_hit = true
				p.x += sin(_animation_elapsed * 43.0) * 3.0 * (1.0 - _animation_elapsed / ANIMATION_SECONDS)
	var scale: float = clampf(row_height / 58.0, 0.52, 1.0)
	var hp: float = float(row.get("hp", 0))
	if hp <= 0.0:
		color.a = 0.35
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
		draw_arc(p, 22.0 * scale, -0.5, 1.8, 12, Color(1.0, 0.58, 0.38, 1.0 - _animation_elapsed / ANIMATION_SECONDS), 3.0, true)

func _draw_gate() -> void:
	var gate_value: Variant = _battle.get("gate", null)
	if not gate_value is Dictionary:
		return
	var gate: Dictionary = gate_value
	var p: Vector2 = Vector2(_field_rect().end.x, _field_rect().position.y + 9.0)
	draw_rect(Rect2(p - Vector2(10.0, 6.0), Vector2(20.0, 30.0)), Color("747d6c") if float(gate.get("hp", 0)) > 0.0 else Color("434c3e"))
	_text(p - Vector2(72.0, 9.0), "城防 %d" % int(gate.get("hp", 0)), 12, GOLD)

func _draw_effects() -> void:
	if _animation_elapsed >= ANIMATION_SECONDS:
		return
	var progress: float = _animation_elapsed / ANIMATION_SECONDS
	for index: int in range(_events.size()):
		var event: Dictionary = _events[index]
		var type: String = str(event.get("type", ""))
		var side: String = str(event.get("side", "player"))
		var unit: String = str(event.get("unit", ""))
		var target: String = str(event.get("target", ""))
		if type in ["strike", "tower", "gate"]:
			var opposite: String = "enemy" if side == "player" else "player"
			var a: Vector2 = Vector2(_battle_x(float(event.get("from", 0))), _lane_y(unit, side))
			var b: Vector2 = Vector2(_battle_x(float(event.get("to", 0))), _lane_y(target, opposite))
			var local: float = clampf((progress - float(index % 5) * 0.035) / 0.75, 0.0, 1.0)
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
		elif type == "recoil" and int(event.get("killed", 0)) > 0:
			var p: Vector2 = Vector2(_battle_x(float(event.get("to", 0))), _lane_y(unit, side))
			_text(p + Vector2(8.0, -26.0 - progress * 18.0), "−%d" % int(event.get("killed", 0)), 16, Color(1.0, 0.64, 0.44, 1.0 - progress))

func _animated_position(side: String, id: String, final_position: float) -> float:
	if _animation_elapsed >= ANIMATION_SECONDS or _previous.is_empty():
		return final_position
	var previous: Dictionary = _row(side, id, _previous)
	if previous.is_empty():
		return final_position
	var progress: float = clampf(_animation_elapsed / (ANIMATION_SECONDS * 0.72), 0.0, 1.0)
	return lerpf(float(previous.get("pos", final_position)), final_position, ease(progress, -2.0))

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
	var title: String = "旌旗报捷" if bool(result.get("won", false)) else "整军再战"
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
