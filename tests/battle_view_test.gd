extends SceneTree

const BattleView: GDScript = preload("res://src/battle_view.gd")
const CityView: GDScript = preload("res://src/city_view.gd")

class FeedbackStub extends Node:
	signal preferences_changed
	var reduced_motion: bool = false

	func set_reduced_motion(value: bool) -> void:
		reduced_motion = value
		preferences_changed.emit()

var _failures: int = 0
var _checks: int = 0
var _requests: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _request(action: String, args: Array) -> void:
	_requests.append({"action": action, "args": args})

func _capture(name: String, view: Control) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	view.set_process(false)
	view._refresh_controls()
	view._layout_controls()
	root.size = Vector2i(view.size)
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local"))
	image.save_png("res://.local/battle-feedback-%s.png" % name)

func _fixture(round_value: int) -> Dictionary:
	return {"node": "wild_33_32", "general": "lin", "sourceCity": "capital", "mode": "raid", "length": 1200, "round": round_value, "finished": false,
		"player": [{"id": "archer", "pos": 0, "hp": 1000, "maxHp": 1000, "stats": {"hp": 10, "range": 600}}],
		"enemy": [{"id": "militia", "pos": 1200, "hp": 500, "maxHp": 500, "stats": {"hp": 10, "range": 30}}],
		"orders": {"archer": {"command": "advance", "target": ""}},
		"currentRoundSummary": {"round": round_value, "events": []}, "log": ["两军交锋"]}

func _run() -> void:
	var view: Control = BattleView.new()
	var game_theme: Theme = Theme.new()
	game_theme.default_font = preload("res://assets/fonts/NotoSansSC.ttf")
	game_theme.default_font_size = 16
	var button_style: StyleBoxFlat = StyleBoxFlat.new()
	button_style.content_margin_left = 12.0
	button_style.content_margin_right = 12.0
	button_style.content_margin_top = 10.0
	button_style.content_margin_bottom = 10.0
	game_theme.set_stylebox("normal", "Button", button_style)
	view.theme = game_theme
	if OS.get_cmdline_user_args().has("--capture"):
		var theme_script: Script = load("res://src/ui_theme.gd")
		view.theme = theme_script.create(preload("res://assets/fonts/UI.tres"))
	root.add_child(view)
	view.size = Vector2(1100.0, 800.0)
	view.action_requested.connect(_request)
	await process_frame
	var units: Dictionary = {"archer": {"name": "弓箭手", "range": 600}, "militia": {"name": "义兵"}}
	var restored: Dictionary = _fixture(4)
	restored.currentRoundSummary.events = [{"type": "move", "side": "player", "unit": "archer", "from": 0, "to": 100}]
	view.set_battle(restored, units)
	_check(view.observed_round() == 4, "Restored snapshot must seed the observed round")
	_check(view.animation_events().is_empty(), "Opening a restored battle must not animate historical events")
	var live: Dictionary = _fixture(5)
	live.player[0].pos = 200
	live.enemy[0].hp = 430
	live.currentRoundSummary.events = [
		{"type": "move", "side": "player", "unit": "archer", "from": 0, "to": 200},
		{"type": "strike", "side": "player", "unit": "archer", "target": "militia", "from": 200, "to": 1200, "damage": 70, "killed": 7, "ranged": true},
		{"type": "recoil", "side": "enemy", "unit": "militia", "target": "archer", "from": 1200, "to": 1200, "damage": 70, "killed": 7}]
	view.set_battle(live, units)
	_check(view.animation_events().size() == 3, "A live new round must use the canonical event list")
	_check(view.animation_phase() == "move", "A new round must present movement before attack")
	_check(not view._reduced_motion, "Without a feedback service, ordinary motion must remain the default")
	_check(is_equal_approx(view._animated_position("player", "archer", 200.0), 0.0), "Movement must begin at the canonical move event origin")
	_check(is_equal_approx(view._animated_position("enemy", "militia", 1200.0), 1200.0), "An unrecorded movement must not be invented from snapshots")
	_check(is_equal_approx(view._visual_hp("enemy", "militia", 430.0), 500.0), "Casualties must not appear before the attack lands")
	view._animation_elapsed = view.MOVE_SECONDS * 0.5
	await _capture("move", view)
	_check(view._animated_position("player", "archer", 200.0) > 100.0 and view._animated_position("player", "archer", 200.0) < 200.0, "Movement should ease out within its own phase")
	view._animation_elapsed = view.MOVE_SECONDS - 0.01
	view._process(0.01)
	_check(view.animation_phase() == "attack" and is_equal_approx(view._animated_position("player", "archer", 200.0), 200.0), "Attack phase must start only after movement reaches its canonical endpoint")
	_check(view._subtitle.text.contains("正在攻击"), "Entering the attack phase must refresh its readable status")
	_check(is_equal_approx(view._visual_hp("enemy", "militia", 430.0), 500.0), "The attack trace must precede loss feedback")
	view._animation_elapsed = view.MOVE_SECONDS + 0.15
	await _capture("attack", view)
	view._animation_elapsed = view.ATTACK_END
	await _capture("impact", view)
	_check(view.animation_phase() == "impact" and is_equal_approx(view._visual_hp("enemy", "militia", 430.0), 430.0), "Impact phase must display the authoritative resulting health")
	var canonical_before_finish: Dictionary = view._battle.duplicate(true)
	view._process(view.ANIMATION_SECONDS)
	_check(view.animation_phase() == "settled" and not view.is_processing() and view._previous.is_empty(), "Finishing presentation must restore the final state and stop processing")
	_check(view._battle == canonical_before_finish and is_equal_approx(Engine.time_scale, 1.0), "Feedback must neither mutate canonical results nor change global time scale")
	_check(view._summary.text.contains("敌军倒下 7"), "Strike and recoil must not count the same casualties twice")
	_check(view._logs.text.contains("弓箭手 射击 → 敌军义兵"), "Attack feedback must identify real attacker and target")
	live.enemy[0].hp = 10
	_check(float(view._battle.enemy[0].hp) == 430.0, "View must own its snapshot and never mutate bridge DTOs")
	var events_copy: Array = view.animation_events()
	events_copy.clear()
	_check(view.animation_events().size() == 3, "Animation event access must not expose mutable internal state")
	view._animation_elapsed = 0.43
	view.set_battle(view._battle, units)
	_check(is_equal_approx(view._animation_elapsed, 0.43), "Timer/selection refresh of the same round must not restart animation")
	view._buttons[0].emit_signal("pressed")
	_check(_requests.size() == 1 and _requests[0] == {"action": "setBattleOrders", "args": ["advance"]}, "All-advance button must send canonical action only")
	view._unit_order("hold")
	_check(_requests[1] == {"action": "setBattleOrder", "args": ["archer", "hold"]}, "Individual order must retain selected canonical unit ID")
	view.set_actions_enabled(false)
	view._buttons[3].emit_signal("pressed")
	_check(_requests.size() == 2, "An in-flight/disabled UI must not send another round command")
	view.set_actions_enabled(true)
	var finished: Dictionary = _fixture(6)
	finished.finished = true
	finished.enemy[0].hp = 0
	finished.result = {"won": true, "lost": {"archer": 3}, "wounded": {"archer": 2}, "back": {"archer": 95}, "xp": 45, "cargoLoaded": 900, "cargoCapacity": 1000, "lootDiscarded": 100, "bonusDiscarded": 0,
		"resourceReceipt": {"base": {"received": {"food": 700, "wood": 100}}, "bonus": {"received": {"food": 100}}}, "overCapacity": 400}
	view.set_battle(finished, units)
	_check(view._logs.text.contains("粮草 800") and view._logs.text.contains("木材 100"), "Result must combine actual receipt values, not reconstruct loot")
	_check(view._logs.text.contains("永久损失 3") and view._logs.text.contains("伤兵 2"), "Result must separate permanent losses from wounded")
	_check(not view._commands.visible, "Resolved battle must not require a confirmation to settle")
	_check(view._title.text.contains("战斗胜利") and view._logs.text.contains("战斗胜利"), "A won battle must expose an explicit victory state")
	await _capture("victory", view)
	view._request("battleRound", [])
	_check(_requests.size() == 2, "Finished battle must reject extra presentation commands")
	finished.result.won = false
	finished.player[0].hp = 0
	finished.enemy[0].hp = 500
	view.set_battle(finished, units)
	_check(view._title.text.contains("战斗失利") and view._logs.text.contains("战斗失利"), "A lost battle must expose an explicit defeat state")
	var new_battle: Dictionary = _fixture(0)
	view.set_battle(new_battle, units)
	_check(view.animation_events().is_empty(), "A restarted round counter must reset animation baseline")
	var skipped_round: Dictionary = _fixture(3)
	skipped_round.currentRoundSummary.events = [{"type": "move", "side": "player", "unit": "archer", "from": 100, "to": 200}]
	view.set_battle(skipped_round, units)
	_check(view.animation_events().is_empty(), "A skipped snapshot must not pretend the latest events cover previous unknown rounds")
	var ended: Dictionary = _fixture(3)
	ended.finished = true
	ended.result = {"won": true}
	view.set_battle(ended, units)
	var restarted_same_target: Dictionary = _fixture(4)
	restarted_same_target.currentRoundSummary.events = skipped_round.currentRoundSummary.events
	view.set_battle(restarted_same_target, units)
	_check(view.animation_events().is_empty(), "A new active battle after a resolved battle must seed a new baseline even at a higher round")
	var feedback: FeedbackStub = FeedbackStub.new()
	feedback.add_to_group("ui_feedback")
	root.add_child(feedback)
	var reduced_round: Dictionary = _fixture(5)
	reduced_round.player[0].pos = 200
	reduced_round.enemy[0].hp = 430
	reduced_round.currentRoundSummary.events = live.currentRoundSummary.events.duplicate(true)
	view.set_battle(reduced_round, units)
	_check(view.animation_phase() == "move", "A late feedback service must bind without changing the next round's presentation")
	view._animation_elapsed = view.ATTACK_END + 0.08
	feedback.set_reduced_motion(true)
	_check(view.animation_phase() == "settled" and not view.is_processing() and view._previous.is_empty(), "Enabling reduced motion during impact must immediately settle every visual effect")
	_check(is_equal_approx(view._animated_position("player", "archer", 200.0), 200.0) and is_equal_approx(view._visual_hp("enemy", "militia", 430.0), 430.0), "Reduced motion must show canonical positions and health immediately")
	_check(view._logs.text.contains("倒下 7 人") and view.animation_events().size() == 3, "Reduced motion must preserve readable round evidence and canonical events")
	await _capture("reduced", view)
	feedback.set_reduced_motion(false)
	view.set_battle(reduced_round, units)
	_check(view.animation_phase() == "settled", "Turning motion back on must not replay the observed round")
	var next_reduced: Dictionary = _fixture(6)
	next_reduced.player[0].pos = 250
	next_reduced.currentRoundSummary.events = [{"type": "move", "side": "player", "unit": "archer", "from": 200, "to": 250}]
	feedback.set_reduced_motion(true)
	view.set_battle(next_reduced, units)
	_check(view.observed_round() == 6 and view.animation_phase() == "settled" and not view.is_processing(), "A new reduced-motion round must update data without starting an animation")
	feedback.set_reduced_motion(false)
	var another_battle: Dictionary = _fixture(7)
	another_battle.node = "wild_34_32"
	another_battle.currentRoundSummary.events = next_reduced.currentRoundSummary.events
	view.set_battle(another_battle, units)
	_check(view.animation_events().is_empty() and view.animation_phase() == "settled", "A new battle identity must not animate the previous battle's events")
	var move_only: Dictionary = another_battle.duplicate(true)
	move_only.round = 8
	move_only.currentRoundSummary = {"round": 8, "events": next_reduced.currentRoundSummary.events.duplicate(true)}
	view.set_battle(move_only, units)
	_check(view.animation_phase() == "move", "A movement-only round should still animate its recorded movement")
	view._process(view.MOVE_SECONDS)
	_check(view.animation_phase() == "settled" and not view.is_processing(), "A movement-only round must skip nonexistent attack and casualty phases")
	var attack_only: Dictionary = move_only.duplicate(true)
	attack_only.round = 9
	attack_only.enemy[0].hp = 430
	attack_only.currentRoundSummary = {"round": 9, "events": [live.currentRoundSummary.events[1], live.currentRoundSummary.events[2]]}
	view.set_battle(attack_only, units)
	_check(view.animation_phase() == "attack", "An attack-only round must not invent a preceding movement phase")
	view._process(view.ATTACK_END - view.MOVE_SECONDS)
	_check(view.animation_phase() == "impact", "An attack-only round must still show impact after the shot")
	view._process(view.ANIMATION_SECONDS)
	_check(view.animation_phase() == "settled" and not view.is_processing(), "An attack-only round must restore the canonical final presentation")
	var fatal_hit: Dictionary = attack_only.duplicate(true)
	fatal_hit.round = 10
	fatal_hit.enemy[0].hp = 0
	fatal_hit.currentRoundSummary = {"round": 10, "events": [
		{"type": "strike", "side": "player", "unit": "archer", "target": "militia", "from": 200, "to": 1200, "damage": 430, "killed": 43, "ranged": true},
		{"type": "recoil", "side": "enemy", "unit": "militia", "target": "archer", "from": 1200, "to": 1200, "damage": 430, "killed": 43}]}
	view.set_battle(fatal_hit, units)
	_check(view._visual_hp("enemy", "militia", 0.0) > 0.0, "A destroyed formation must remain visible until its recorded attack lands")
	view._process(view.ATTACK_END - view.MOVE_SECONDS)
	_check(is_zero_approx(view._visual_hp("enemy", "militia", 0.0)), "A fatal impact must show zero authoritative health")
	view._process(view.ANIMATION_SECONDS)
	_check(view.animation_phase() == "settled" and view._previous.is_empty(), "The destroyed formation must not retain a visual baseline after completion")
	feedback.queue_free()
	await process_frame
	view.set_battle(null, units)
	_check(view.observed_round() == -1 and not view._logs.visible, "No battle must restore the departure empty state")
	view.size = Vector2(500.0, 570.0)
	view._layout_controls()
	_check(view._logs.position.y + view._logs.size.y <= 570.0, "Desktop compact layout must keep logs inside the available 570px")
	view.set_battle(_fixture(0), units)
	view.size = Vector2(358.0, 600.0)
	view._layout_controls()
	await process_frame
	_check(view._commands.columns == 2, "Phone content width must use two command columns")
	_check(view._commands.size.x <= 358.0 - 36.0, "Command grid must stay inside narrow content")
	for command_button: Button in view._commands.get_children():
		_check(command_button.position.x + command_button.size.x <= view._commands.size.x + 1.0, "All four native command buttons must fit the two-column grid")
		_check(command_button.size.y >= 44.0, "Every narrow command must retain a 44px touch target")
	for unit_button: Button in view._unit_commands.get_children():
		_check(unit_button.size.y >= 44.0, "Every selected-unit command must retain a 44px touch target")
	_check(not view._title.clip_text and not view._subtitle.clip_text and not view._summary.clip_text, "Battle labels must wrap instead of clipping text")
	_check(view.custom_minimum_size.y <= 570.0, "Touch targets should not force a large increase over the compact 540px battle layout")
	_check(view._unit_commands.position.y >= view._commands.position.y + view._commands.size.y, "Unit commands must move below the wrapped global commands")
	_check(view._field_rect().position.y > view._unit_commands.position.y + view._unit_commands.size.y + 30.0, "Battlefield must leave room for the narrow unit caption")
	_check(view._logs.size.y >= 88.0 and view._logs.position.y + view._logs.size.y <= view.size.y, "Phone battle log must retain readable height without clipping")
	await _capture("narrow", view)
	view.size = Vector2(900.0, 600.0)
	view._layout_controls()
	await process_frame
	_check(view._commands.columns == 4, "Desktop resize must restore a single four-column command row")
	var last_unit_button: Button = view._unit_commands.get_child(2)
	_check(last_unit_button.position.x + last_unit_button.size.x < 242.0, "Desktop selected-unit commands must leave clear space for the range caption")
	var city: Control = CityView.new()
	root.add_child(city)
	city.size = Vector2(1000.0, 570.0)
	var fixture_file: FileAccess = FileAccess.open("res://tests/fixtures/godot-view.json", FileAccess.READ)
	if fixture_file != null:
		var city_fixture: Dictionary = JSON.parse_string(fixture_file.get_as_text())
		city.set_city(city_fixture.get("view", {}))
		_check(city._view.get("queues", {}) is Dictionary, "Native city must accept the canonical grouped queue DTO")
	else:
		_check(false, "Canonical bridge city fixture must be available")
	await process_frame
	city.queue_free()
	view.queue_free()
	await process_frame
	print("City / battle presentation: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
