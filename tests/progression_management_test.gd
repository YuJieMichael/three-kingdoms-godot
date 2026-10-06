extends SceneTree

## Exercise actual dialog controls and polling; canonical fees are HTTP-tested.
var _checks: int = 0
var _failures: int = 0
var _dialog: KingdomProgressionDialog
var _view: Dictionary
var _commands: Array[Dictionary] = []
var _routes: Array[Dictionary] = []


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


func _reward() -> Dictionary:
	return {"resources": {"food": 5000, "wood": 4000, "stone": 3000, "iron": 2000, "gold": 1000}, "items": [{"id": "speed_build_15m", "name": "建造加速十五分钟", "count": 2}], "jewels": [{"id": "pearl", "name": "珍珠", "count": 1}], "army": [{"id": "ram", "name": "冲车", "count": 5}], "prestige": 300}


func _fixture() -> Dictionary:
	var reward: Dictionary = _reward()
	var progression: Dictionary = {"shared": false, "reason": "",
		"missions": [{"id": "house", "title": "安置百姓", "stage": "立城補给", "description": "完成一座民房，准备训练弓兵并进行首次出征。", "current": true, "claimed": false, "ready": true, "reason": "", "rewards": reward, "claim": {"type": "claimMission", "args": ["house"]}, "navigate": {"route": "inner", "target": "house"}, "navigationReason": ""}, {"id": "gift", "title": "奉诏立城", "description": "领取建城礼包", "claimed": true, "ready": false, "reason": "奖励已领取", "rewards": reward, "claim": {"type": "claimMission", "args": ["gift"]}, "navigate": {"route": "gift", "target": ""}}],
		"claimMissions": {"command": {"type": "claimReadyMissions", "args": []}, "reason": ""},
		"firstBattle": {"complete": false, "ready": false, "reason": "请先完成一次出征胜利", "archers": 0, "target": 30, "victories": 0, "requirementSteps": [{"id": "barracks", "name": "军营", "current": 1, "level": 4}, {"id": "shooting", "name": "抛射技巧", "current": 0, "level": 1}], "next": {"route": "inner", "target": "barracks"}, "finish": {"type": "completeFirstBattleGuide", "args": []}},
		"daily": {"accepted": 0, "limit": 12, "claimed": 0, "claimAll": {"command": {"type": "claimReadyDaily", "args": []}, "reason": "暂无已完成的每日任务"}, "milestones": [{"count": 3, "reason": "今日完成任务数量不足", "rewards": reward, "command": {"type": "claimDailyMilestone", "args": [3]}}], "tasks": [{"id": "daily_build_uid", "title": "修整城坊", "description": "接取后完成两项建设", "status": "available", "progress": 0, "target": 2, "route": "inner", "reason": "", "payment": {}, "rewards": reward, "accept": {"type": "acceptDaily", "args": ["daily_build_uid"]}, "acceptReason": "", "claim": {"type": "claimDaily", "args": ["daily_build_uid"]}, "claimReason": "接取后完成目标才能领取", "abandon": {"type": "abandonDaily", "args": ["daily_build_uid"]}, "abandonReason": "尚未接取"}]},
		"epic": {"countyReason": "尚未完成黄巾史诗", "copper": 80, "groups": [{"name": "捐献军资", "progress": 0.0, "detail": "五种物资各捐献100000"}], "donations": [{"kind": "resource", "id": "food", "name": "粮草", "cost": 100000, "prestige": 1000, "points": 0, "reason": "库存不足100000", "command": {"type": "donateEpic", "args": ["resource", "food"]}}], "exchanges": [{"id": "pearl", "name": "珍珠 ×1", "cost": 40, "claimed": 0, "reason": "", "command": {"type": "exchangeCopper", "args": ["pearl"]}}]},
		"honors": {"office": {"name": "平民"}, "noble": {"name": "平民"}, "prestige": 1000, "cities": 1, "cityLimit": 1, "jewels": [{"id": "pearl", "name": "珍珠", "count": 0}], "promotions": [{"kind": "office", "next": {"name": "伍长"}, "reason": "条件未满足：珍珠 ×1", "cost": {"resources": {"gold": 0}, "jewels": [{"id": "pearl", "name": "珍珠", "count": 1}]}, "command": {"type": "heritage.promote", "args": ["office"]}}], "salaries": [{"kind": "office", "reason": "晋升后才能领取俸禄", "rewards": {}, "command": {"type": "heritage.salary", "args": ["office"]}}]},
		"chapters": [{"chapter": 2, "title": "第二章", "conquered": 0, "total": 6, "claimed": 0, "reason": "先占领古渡县城", "next": null, "visibleNodes": []}, {"chapter": 3, "title": "第三章", "conquered": 0, "total": 5, "claimed": 0, "reason": "先完成第二章全部六关", "next": null, "visibleNodes": []}],
		"gifts": {"available": 1, "claimAll": {"command": {"type": "onboarding.claimAvailable", "args": []}, "reason": ""}, "levels": [{"level": 1, "title": "奉诏立城", "unlocked": true, "claimed": false, "reason": "", "rewards": reward, "command": {"type": "onboarding.claim", "args": [1]}}, {"level": 2, "title": "筹备弓营", "unlocked": false, "claimed": false, "reason": "需要官府 2 级", "rewards": reward, "command": {"type": "onboarding.claim", "args": [2]}}]}}
	return {"progression": progression}


func _button_at(id: String, index: int = 0) -> Button:
	return _dialog._rows[id].actions.get_child(index) as Button


func _run() -> void:
	root.size = Vector2i(390, 844)
	var host: Control = Control.new()
	host.size = Vector2(390, 844)
	root.add_child(host)
	_dialog = load("res://src/progression_dialog.gd").new() as KingdomProgressionDialog
	host.add_child(_dialog)
	_dialog.command_requested.connect(func(type: String, args: Array) -> void: _commands.append({"type": type, "args": args}))
	_dialog.route_requested.connect(func(route: String, target: String) -> void: _routes.append({"route": route, "target": target}))
	_view = _fixture()
	_view.progression.daily.milestones[0].count = 3.0
	_view.progression.chapters[0].conquered = 0.0
	_dialog.show_section("missions", _view)
	await _settle()
	_check(_dialog.size.x <= 350, "390-width layout must fit within the host window.")
	_check(_dialog._scroll.get_h_scroll_bar().max_value <= _dialog._scroll.get_h_scroll_bar().page + 1.0, "Long reward descriptions must wrap without horizontal scrolling.")
	_check(_dialog._rows["mission-house"].body.text.contains("冲车 ×5") and _dialog._rows["mission-house"].body.text.contains("珍珠 ×1"), "Mission rewards must show unit and jewel awards alongside resources/items.")
	_check(_button_at("guide", 1).disabled, "Unmet canonical first-battle requirements must disable completion.")
	_button_at("guide").emit_signal("pressed")
	_check(_routes.back() == {"route": "inner", "target": "barracks"}, "First-battle next-step navigation must use the quoted building target.")
	var original_filter: OptionButton = _dialog._filter
	_dialog._filter.select(2)
	_dialog._filter.emit_signal("item_selected", 2)
	_check(_dialog._rows.has("mission-gift"), "Selecting the all-task filter must apply on the first selection.")
	var original_row: Node = _dialog._rows["mission-house"].container
	_dialog._scroll.scroll_vertical = 80
	await _settle()
	var scroll_position: int = _dialog._scroll.scroll_vertical
	var polled: Dictionary = _view.duplicate(true)
	polled.progression.firstBattle.archers = 1
	# A transitional snapshot may lack current for a newly introduced outer
	# prerequisite; the guide must still render and keep the task list alive.
	polled.progression.firstBattle.requirementSteps.append({"id": "mine", "name": "铁矿", "level": 3})
	_dialog.update_view(polled)
	await _settle()
	_check(_dialog._rows["guide"].body.text.contains("铁矿 0 / 3"), "Missing transitional prerequisite values must default safely without breaking task rendering.")
	_check(_dialog._filter == original_filter and _dialog._filter.selected == 2, "Polling must preserve the filter control and selection.")
	_check(_dialog._rows["mission-house"].container == original_row and _dialog._scroll.scroll_vertical == scroll_position, "Polling must reuse task controls and retain scroll position.")
	_button_at("mission-house").emit_signal("pressed")
	_button_at("mission-house").emit_signal("pressed")
	_check(_commands.size() == 1 and _commands[0] == {"type": "claimMission", "args": ["house"]}, "A claim must send canonical ID exactly once and immediately lock duplicate clicks.")
	_dialog.update_view(polled)
	_check(_button_at("mission-house").disabled, "A polled snapshot must not unlock an unconfirmed action.")
	_dialog.show_error("连接中断，等待确认")
	_dialog.set_command_state(false, true)
	_check(_dialog._status.text.contains("等待确认") and _button_at("mission-house").disabled, "Unconfirmed transport failure must keep the action blocked and show the failure.")
	_dialog.acknowledge_command(true, false)
	_check(not _button_at("mission-house").disabled, "An acknowledged action must restore the live quote state.")
	_dialog.show_section("daily", _view)
	_check(_dialog._rows["milestone-3.0"].heading.text == "今日完成 3 项", "A JSON float milestone count must display as an integer.")
	_button_at("daily-daily_build_uid").emit_signal("pressed")
	_check(_commands.back() == {"type": "acceptDaily", "args": ["daily_build_uid"]}, "Daily acceptance must retain the canonical task UID.")
	_dialog.acknowledge_command(true, false)
	var accepted: Dictionary = _view.duplicate(true)
	accepted.progression.daily.tasks[0].status = "accepted"
	accepted.progression.daily.tasks[0].abandonReason = ""
	_dialog.update_view(accepted)
	_check(_button_at("daily-daily_build_uid").disabled, "An accepted but incomplete daily task cannot claim its reward.")
	_button_at("daily-daily_build_uid", 1).emit_signal("pressed")
	_check(_commands.back() == {"type": "abandonDaily", "args": ["daily_build_uid"]}, "Daily abandonment must use the live canonical UID.")
	_dialog.acknowledge_command(true, false)
	_dialog.show_section("honors", _view)
	_check(_button_at("promotion-office").disabled and _dialog._rows["promotion-office"].body.text.contains("珍珠 ×1"), "Prestige alone must not enable promotion when the jewel quote is unmet.")
	_dialog.show_section("epic", _view)
	_check(_button_at("donation-resource-food").disabled and _dialog._rows["donation-resource-food"].body.text.contains("100000"), "Donation costs and insufficient resource reasons must stay visible.")
	_dialog._filter.select(3)
	_dialog._filter.emit_signal("item_selected", 3)
	_check(_dialog._rows.has("exchange-pearl"), "Selecting copper exchange must apply immediately.")
	_button_at("exchange-pearl").emit_signal("pressed")
	_check(_commands.back() == {"type": "exchangeCopper", "args": ["pearl"]}, "Copper exchange must send the service item ID.")
	_dialog.acknowledge_command(true, false)
	_dialog.show_section("gifts", _view)
	_check(not _button_at("gift-1").disabled and _button_at("gift-2").disabled, "Ten-tier rewards must follow their canonical unlocked/claimed state.")
	_button_at("gift-all").emit_signal("pressed")
	_check(_commands.back() == {"type": "onboarding.claimAvailable", "args": []}, "Gift batch must call the existing canonical batch command.")
	_dialog.acknowledge_command(true, false)
	_dialog.show_section("chapters", _view)
	_check(_dialog._rows["chapter-3"].body.text.contains("六关") and _dialog._rows["chapter-3"].actions.get_child_count() == 0, "The third chapter must show its gate without revealing a locked target.")
	var shared: Dictionary = _view.duplicate(true)
	shared.progression.shared = true
	shared.progression.reason = "共享演练尚未接入私人据点主线"
	shared.progression.firstBattle.navigationReason = shared.progression.reason
	shared.progression.firstBattle.reason = shared.progression.reason
	shared.progression.claimMissions.reason = shared.progression.reason
	for mission: Dictionary in shared.progression.missions:
		mission.reason = shared.progression.reason
		mission.navigationReason = shared.progression.reason
	_dialog.show_section("missions", shared)
	_check(_button_at("mission-house").disabled and _button_at("mission-house", 1).disabled and _button_at("guide").disabled, "Shared mode must block private mainline claims and NPC navigation with explicit reasons.")
	print("PROGRESSION_UI_TEST checks=", _checks, " failures=", _failures)
	host.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)
