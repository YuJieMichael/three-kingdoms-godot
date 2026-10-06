extends SceneTree

const DIALOG = preload("res://src/war_management_dialog.gd")
var _checks: int = 0
var _failures: int = 0
var _dialog: KingdomWarManagementDialog
var _requests: Array[Dictionary] = []
var _view: Dictionary


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


func _quote(type: String, args: Array, count: int = 1, reason: String = "") -> Dictionary:
	return {"count": count, "reason": reason, "key": "canonical-fixture-key", "gold": 480, "cost": {"gold": 100, "food": 200}, "people": 10, "command": {"type": type, "args": args}}


func _fixture() -> Dictionary:
	var hospital_all: Dictionary = _quote("healWounded", ["all", null, "heal-all-original"], 15)
	hospital_all["available"] = 15
	var hospital_full: Dictionary = _quote("healWounded", ["archer", 10, "heal-archer-original"], 10)
	var hospital_affordable: Dictionary = _quote("healWounded", ["archer", 2, "heal-affordable-original"], 2)
	hospital_affordable["gold"] = 96
	var captive_all: Dictionary = _quote("recruitAllCaptives", ["recruit-original-plan"], 8)
	var challenge: Dictionary = _quote("requestCityDefense", ["classic", 1, "challenge-original-key"])
	challenge.merge({"profile": "classic", "name": "黄巾挑战", "description": "黄巾步兵向城池进军", "level": 1, "army": {"militia": 18}, "reward": {"food": 150, "wood": 150}, "warningSeconds": 300})
	var doctrine: Dictionary = {"mode": "field", "autoResolve": false, "orders": {"archer": {"command": "hold", "target": "militia"}, "cavalry": {"command": "advance", "target": ""}}}
	var relief: Dictionary = _quote("executeCivicOrder", ["relief"])
	relief.merge({"id": "relief", "name": "赈灾", "effects": {"morale": 5, "unrest": -15, "population": 0}, "reward": {}, "enabled": true})
	var sacrifice: Dictionary = _quote("executeCivicOrder", ["sacrifice"])
	sacrifice.merge({"id": "sacrifice", "name": "祭天", "effects": {}, "reward": {}, "enabled": true})
	var salary: Dictionary = _quote("payHeroArrears", ["all", "salary-all-original"])
	salary["cost"] = 160
	var salary_single: Dictionary = _quote("payHeroArrears", ["lin", "salary-lin-original"])
	salary_single["cost"] = 100
	return {"warManagement": {"now": 1800000000000, "cityId": "capital", "cityName": "洛阳", "shared": false,
		"unitNames": {"archer": "弓箭手", "militia": "义兵", "cavalry": "轻骑兵"},
		"hospital": {"quote": hospital_all, "autoHeal": false, "lastAuto": null, "rows": [{"id": "archer", "name": "弓箭手", "count": 10, "choices": [hospital_full, hospital_affordable]}]},
		"captives": {"quote": captive_all, "rows": [{"id": "archer", "name": "弓箭手", "available": 8, "count": 8, "choices": [_quote("recruitCaptives", ["archer", 8], 8), _quote("recruitCaptives", ["archer", 3], 3)]}]},
		"defenses": {"capacity": 1000, "used": 30, "queue": [], "rows": [{"id": "tower", "name": "箭塔", "count": 10, "held": 0, "unitCost": {"food": 200, "wood": 2000, "stone": 1000, "iron": 500}, "area": 3, "baseSeconds": 180, "requirement": "", "requirementsText": "城墙 3 级、抛射技术 3 级"}]},
		"defense": {"restricted": false, "reason": "", "unlocked": true, "wins": 2, "wave": 3, "autoEnabled": false, "nextAt": 0, "doctrine": doctrine,
			"incoming": {"name": "黄巾步军", "arriveAt": 1800000030000, "types": [], "army": null}, "profiles": [{"id": "classic", "name": "黄巾步军", "quotes": [challenge]}],
			"generals": [{"id": "lin", "name": "林朔", "reason": ""}, {"id": "su", "name": "苏砚", "reason": "守将正在出征或驻守"}], "governor": "lin", "startReason": "",
			"army": [{"id": "archer", "name": "弓箭手", "available": 100}, {"id": "cavalry", "name": "轻骑兵", "available": 50}], "battle": null, "report": null},
		"civic": {"population": 300, "morale": 80, "unrest": 10, "wardUntil": 0, "blessingUntil": 0, "rows": [relief, sacrifice]},
		"wages": {"status": {"moraleTarget": 80, "warnings": ["军队缺粮时有逃兵风险"], "wages": 40, "owed": 160}, "quote": salary,
			"rows": [{"id": "lin", "name": "林朔", "wage": 20, "owed": 100, "loyalty": 65, "quote": salary_single}], "policies": {"eventsEnabled": false, "autoRelief": false}, "log": [{"text": "军民请求赈灾"}], "salaryLog": [{"text": "林朔欠饷"}]}}}


func _ack() -> void:
	_dialog.acknowledge_command(true, false)


func _last(type: String, args: Array) -> void:
	_check(not _requests.is_empty(), "command must be emitted")
	if not _requests.is_empty():
		_check(_requests.back().type == type, "canonical type expected %s got %s" % [type, _requests.back().type])
		_check(_requests.back().args == args, "canonical args expected %s got %s" % [str(args), str(_requests.back().args)])


func _run() -> void:
	root.size = Vector2i(1280, 800)
	_view = _fixture()
	_view.warManagement.hospital.quote.gold = 480.0
	_view.warManagement.defenses.rows[0].unitCost = JSON.parse_string('{"food":200,"wood":2000,"stone":1000,"iron":500}')
	_dialog = DIALOG.new()
	root.add_child(_dialog)
	_dialog.command_requested.connect(func(type: String, args: Array) -> void: _requests.append({"type": type, "args": args}))
	_dialog.show_section("hospital", _view)
	await _settle()
	_check(_dialog.title == "伤兵治疗", "hospital title")
	_check(_dialog._info.text.contains("15"), "hospital native total displayed")
	_check(_dialog._preview.text.contains("480"), "hospital native gold displayed")
	_dialog._action.pressed.emit()
	_last("healWounded", ["archer", 10, "heal-archer-original"])
	var emitted: int = _requests.size()
	_dialog._action.pressed.emit()
	_dialog._all_button.pressed.emit()
	_check(_requests.size() == emitted, "pending blocks duplicate treatment")
	_ack()
	_dialog._mode.select(1)
	_dialog._mode.item_selected.emit(1)
	_check(_dialog._preview.text.contains("96"), "affordable native quote displayed")
	_dialog._action.pressed.emit()
	_last("healWounded", ["archer", 2, "heal-affordable-original"])
	_ack()
	_dialog._all_button.pressed.emit()
	_last("healWounded", ["all", null, "heal-all-original"])
	_ack()
	_dialog._toggle.toggled.emit(true)
	_last("setAutoHeal", [true])
	_ack()
	_dialog.set_command_state(false, false)
	emitted = _requests.size()
	_dialog._all_button.pressed.emit()
	_check(_dialog._all_button.disabled and _requests.size() == emitted, "disconnect blocks treatment")
	_dialog.set_command_state(true, false)
	_dialog.show_section("captives", _view)
	_dialog._action.pressed.emit()
	_last("recruitCaptives", ["archer", 8])
	_ack()
	_dialog._all_button.pressed.emit()
	_last("recruitAllCaptives", ["recruit-original-plan"])
	_ack()
	_dialog.show_section("defenses", _view)
	_dialog._count.get_line_edit().text = "99999"
	_dialog._count.get_line_edit().text_changed.emit("99999")
	_dialog.update_view(_view.duplicate(true))
	_check(_dialog._count.get_line_edit().text == "99999", "poll preserves raw fortification amount")
	_dialog._action.pressed.emit()
	_last("buildDefense", ["tower", 10000])
	_ack()
	_dialog._count.get_line_edit().text = "7"
	_dialog.show_error("城防资源不足")
	_check(_dialog._status.text == "城防资源不足", "server error visible")
	_check(_dialog._count.get_line_edit().text == "7", "error preserves quantity")
	var queued: Dictionary = _view.duplicate(true)
	queued.warManagement.defenses.queue = [{"id": "tower", "count": 4, "end": 1800000060000}]
	_dialog.update_view(queued)
	_check(_dialog._action.disabled and _dialog._info.text.contains("工队"), "queue blocks duplicate construction")
	_dialog.show_section("defense", _view)
	await _settle()
	_check(_dialog._start_button.disabled, "formal defense disabled before arrival")
	_check(_dialog._info.text.contains("尚未获知"), "warning respects unknown beacon intelligence")
	_dialog._action.pressed.emit()
	_last("requestCityDefense", ["classic", 1, "challenge-original-key"])
	_ack()
	_dialog._toggle.toggled.emit(true)
	_last("setAutoCityDefense", [true])
	_ack()
	_dialog._orders.select(3)
	_dialog._orders.item_selected.emit(3)
	_dialog._defense_mode.select(1)
	_dialog._defense_mode.item_selected.emit(1)
	_dialog._auto_resolve.set_pressed_no_signal(true)
	_dialog._doctrine_button.pressed.emit()
	_check(_requests.back().type == "setDefenseDoctrine", "doctrine canonical command")
	var doctrine: Dictionary = _requests.back().args[0]
	_check(doctrine.mode == "inside" and doctrine.autoResolve, "doctrine mode and automatic resolution")
	_check(doctrine.orders.archer.command == "fallback" and doctrine.orders.cavalry.command == "fallback", "all retreat applies to every unit")
	_check(doctrine.orders.archer.target == "militia", "all orders preserve original targets")
	_check(_view.warManagement.defense.doctrine.orders.archer.command == "hold", "doctrine does not mutate DTO")
	_ack()
	var army_spin: SpinBox = _dialog._army_spins.archer
	army_spin.get_line_edit().text = "40"
	army_spin.get_line_edit().text_changed.emit("40")
	_dialog.update_view(_view.duplicate(true))
	_check(army_spin.get_line_edit().text == "40", "poll preserves selected stationed army")
	_check(_dialog._orders.selected == 3 and _dialog._defense_mode.selected == 1, "poll preserves unsent doctrine choices")
	_dialog._general.select(1)
	_dialog._general.item_selected.emit(1)
	_check(_dialog._drill_button.disabled, "busy general cannot start drill")
	_dialog._general.select(0)
	_dialog._general.item_selected.emit(0)
	_dialog._drill_button.pressed.emit()
	_last("startCityDefense", [true, "lin", {"archer": 40, "cavalry": 50}])
	_ack()
	var arrived: Dictionary = _view.duplicate(true)
	arrived.warManagement.now = 1800000030000
	_dialog.update_view(arrived)
	_check(not _dialog._start_button.disabled, "arrival enables formal defense")
	_dialog._start_button.pressed.emit()
	_last("startCityDefense", [false, "lin", {"archer": 40, "cavalry": 50}])
	_ack()
	var fighting: Dictionary = arrived.duplicate(true)
	fighting.warManagement.defense.battle = {"drill": true, "round": 3, "gateHp": 2800, "gateMax": 3000, "log": ["弓箭手射击义兵，敌军损失 6 人"]}
	fighting.warManagement.defense.startReason = "已有守城战或演练正在进行"
	_dialog.update_view(fighting)
	_check(_dialog._doctrine_button.disabled and _dialog._drill_button.disabled, "active battle freezes doctrine and preparation")
	_check(_dialog._battle_info.text.contains("损失 6"), "native round feedback displayed")
	_dialog._round_button.pressed.emit()
	_last("cityDefenseRound", [])
	_ack()
	_dialog._resolve_button.pressed.emit()
	_last("resolveCityDefense", [])
	_ack()
	_dialog._end_button.pressed.emit()
	_last("endDefenseDrill", [])
	_ack()
	fighting.warManagement.defense.battle.drill = false
	_dialog.update_view(fighting)
	_check(_dialog._end_button.disabled, "formal defense cannot be cancelled")
	emitted = _requests.size()
	_dialog._end_button.pressed.emit()
	_check(_requests.size() == emitted, "formal-defense exit callback also guarded")
	var shared: Dictionary = fighting.duplicate(true)
	shared.warManagement.shared = true
	shared.warManagement.defense.restricted = true
	shared.warManagement.defense.reason = "共享房间使用玩家攻防，私人黄巾挑战和演练不可用"
	_dialog.update_view(shared)
	_check(_dialog._info.text.contains("共享房间"), "shared private-NPC restriction visible")
	_check(_dialog._action.disabled and _dialog._toggle.disabled and _dialog._round_button.disabled, "shared disables private NPC mutations")
	emitted = _requests.size()
	_dialog._round_button.pressed.emit()
	_dialog._action.pressed.emit()
	_dialog._toggle.toggled.emit(true)
	_check(_requests.size() == emitted, "shared NPC callbacks guarded")
	shared.warManagement.defense.battle = null
	shared.warManagement.defense.startReason = ""
	_dialog.update_view(shared)
	_check(not _dialog._doctrine_button.disabled, "shared own defensive doctrine remains available for PVP")
	_dialog._doctrine_button.pressed.emit()
	_check(_requests.back().type == "setDefenseDoctrine", "shared defensive doctrine sends canonical command")
	_ack()
	_dialog.show_section("hospital", shared)
	_check(not _dialog._all_button.disabled, "own healing remains available in shared rooms")
	_dialog.show_section("civic", _view)
	_dialog._row_buttons.relief.pressed.emit()
	_last("executeCivicOrder", ["relief"])
	_ack()
	_dialog._row_buttons.sacrifice.pressed.emit()
	_last("executeCivicOrder", ["sacrifice"])
	_ack()
	var cooled: Dictionary = _view.duplicate(true)
	cooled.warManagement.civic.rows[0].enabled = false
	cooled.warManagement.civic.rows[0].reason = "安抚冷却中"
	_dialog.update_view(cooled)
	_check(_dialog._row_buttons.relief.disabled and _dialog._row_labels.relief.text.contains("冷却"), "native civic cooldown reason displayed")
	_dialog.show_section("wages", _view)
	_check(_dialog._info.text.contains("160") and _dialog._preview.text.contains("林朔欠饷"), "arrears and salary logs displayed")
	_dialog._row_buttons.lin.pressed.emit()
	_last("payHeroArrears", ["lin", "salary-lin-original"])
	_ack()
	_dialog._all_button.pressed.emit()
	_last("payHeroArrears", ["all", "salary-all-original"])
	_ack()
	_dialog._policy_buttons.autoRelief.toggled.emit(true)
	_last("setGovernancePolicy", ["autoRelief", true])
	_ack()
	root.size = Vector2i(390, 844)
	for section: String in DIALOG.TITLES:
		_dialog.show_section(section, _view)
		await _settle()
		_check(_dialog.size.x <= 350, "narrow %s panel remains within viewport" % section)
		_check(_dialog._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "narrow %s does not horizontally scroll" % section)
		_check(_dialog._content.get_combined_minimum_size().x <= _dialog.size.x, "narrow %s content minimum fits" % section)
	_dialog.queue_free()
	await _settle()
	print("WAR_MANAGEMENT_TEST_CHECKS=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
