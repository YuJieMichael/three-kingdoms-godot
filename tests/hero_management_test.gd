extends SceneTree

const HeroDialog = preload("res://src/hero_dialog.gd")
var _checks: int = 0
var _failures: int = 0
var _dialog: KingdomHeroDialog
var _view: Dictionary
var _requests: Array[Dictionary] = []
var _focus: Array[Vector2i] = []
var _dispatches: Array[String] = []


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


func _button(text: String) -> Button:
	for action: Dictionary in _dialog._actions:
		if (action.button as Button).text == text: return action.button
	return null


func _fixture() -> Dictionary:
	var rewards: Array = [{"method": "gold", "current": 80, "next": 90, "cost": {"gold": 2000, "jewels": {}}, "reason": "", "key": "reward-gold-original"}, {"method": "jewels", "current": 80, "next": 90, "cost": {"gold": 0, "jewels": {"pearl": 1}}, "reason": "", "key": "reward-jewel-original"}]
	var owned: Array = [{"id": "lin", "name": "林衡", "level": 2, "loyalty": 80, "points": 3, "atk": 70, "def": 50, "pol": 60, "wis": 55, "lead": 20, "reason": "", "drill": {"used": 0, "cost": 2000, "xp": 80, "reason": ""}, "rewards": rewards, "salary": {"cost": 500, "reason": "", "key": "salary-original"}}, {"id": "busy", "name": "外出将领", "level": 2, "loyalty": 80, "points": 3, "reason": "将领出征或驻守中，请返城后调整", "drill": {"used": 0, "cost": 2000, "xp": 80, "reason": "将领在外，请返城"}, "rewards": [{"method": "gold", "reason": "将领在外，请返城"}, {"method": "jewels", "reason": "将领在外，请返城"}], "salary": {"cost": 0, "reason": "这位将领没有欠饷"}}]
	var wild: Array = [{"line": "wanderer", "name": "陈岚", "title": "山林游侠", "region": "近郊", "status": "active", "reason": "", "portrait": {"price": 10, "reason": "", "key": "portrait-original"}, "node": {"id": "wild_28_34", "name": "近郊草原", "x": 28, "y": 34}, "dispatchReason": "请先购买画像，才能俘获这名将领"}]
	var captives: Array = [{"id": "local_1", "name": "陈岚", "level": 2, "loyalty": 40, "kind": "wild", "quotes": [{"method": "gold", "cost": {"gold": 6000, "jewels": {}}, "reason": "", "key": "recruit-gold-original"}, {"method": "jewels", "cost": {"gold": 0, "jewels": {"pearl": 1}}, "reason": "珍珠不足", "key": "recruit-jewel-original"}], "release": {"key": "release-original"}}]
	var equipment: Array = [{"id": 1, "name": "精铁长枪", "quality": "普通", "enhanceLevel": 0, "requiredLevel": 1, "stats": {"atk": 8, "lead": 2}, "wearerName": "", "equip": [{"id": "lin", "reason": ""}, {"id": "busy", "reason": "将领出征或驻守中，请返城后调整"}], "unequipReason": "装备未穿戴", "enhance": {"gold": 1000, "pearls": 1, "reason": ""}, "salvageReason": ""}]
	return {"heroes": {"owned": owned, "wild": wild, "captives": captives, "equipment": equipment, "forge": [{"slot": "armor", "tier": 2, "name": "锁子甲", "smith": 3, "cost": {"wood": 4000, "stone": 3200, "iron": 8000, "gold": 12000}, "reason": ""}], "items": [{"id": "politics", "name": "内政宝物", "count": 2, "description": "提升内政"}], "attrs": {"atk": "勇武", "def": "统御", "pol": "内政", "wis": "智谋", "lead": "统率"}, "jewels": {"pearl": "珍珠"}, "used": 3, "capacity": 6, "equipmentCapacity": 50, "smithLevel": 3, "discoverReason": "", "giftReason": "", "expansions": [{"id": "rack", "name": "武器架", "count": 0, "reason": "没有武器架"}]}}


func _run() -> void:
	root.size = Vector2i(1280, 844)
	_view = _fixture()
	# Mirror JSON number fields without changing the typed command fixtures.
	_view.heroes.merge(JSON.parse_string('{"used":3,"capacity":6,"equipmentCapacity":50,"smithLevel":3}'), true)
	_view.heroes.owned[0].merge(JSON.parse_string('{"level":2,"loyalty":80,"atk":70,"def":50,"pol":60,"wis":55,"lead":20,"points":3}'), true)
	_dialog = HeroDialog.new()
	root.add_child(_dialog)
	_dialog.command_requested.connect(func(type: String, args: Array) -> void: _requests.append({"type": type, "args": args}))
	_dialog.focus_requested.connect(func(x: int, y: int) -> void: _focus.append(Vector2i(x, y)))
	_dialog.dispatch_requested.connect(func(id: String) -> void: _dispatches.append(id))
	await _generals()
	await _wild()
	await _captives()
	await _equipment()
	await _layout()
	root.remove_child(_dialog)
	_dialog.queue_free()
	await process_frame
	print("HERO_MANAGEMENT_TEST_CHECKS=", _checks, " failures=", _failures)
	quit(0 if _failures == 0 else 1)


func _generals() -> void:
	_check(_dialog._attribute(64.0) == "64" and _dialog._attribute(64.5) == "64.5", "Integral attributes must omit JSON decimals while real buff fractions remain visible.")
	_dialog.show_section("generals", _view)
	await _settle()
	var spin: SpinBox = _dialog._points.atk
	spin.get_line_edit().text = "2"
	spin.get_line_edit().emit_signal("text_changed", "2")
	_dialog.update_view(_view.duplicate(true))
	_check(spin.get_line_edit().text == "2", "Polling must preserve an uncommitted growth draft.")
	_button("确认加点 · 2 点").emit_signal("pressed")
	_check(_requests.back().type == "hero.allocate" and _requests.back().args == ["lin", {"atk": 2, "def": 0, "pol": 0, "wis": 0, "lead": 0}], "Growth submits exactly the five selected native attributes.")
	var count: int = _requests.size()
	_button("演练").emit_signal("pressed")
	_check(_requests.size() == count, "Pending commands must block duplicate and unrelated mutations.")
	_dialog.update_view(_view)
	_check(_button("演练").disabled, "Polling cannot unlock an unconfirmed mutation.")
	_dialog.acknowledge_command(true, false)
	_check(int(spin.value) == 0 and spin.get_line_edit().text == "0", "Confirmed allocation clears only the submitted growth form.")
	_button("奖励黄金").emit_signal("pressed")
	_check(_requests.back().args == ["lin", "gold", "reward-gold-original"], "Loyalty reward must send the original server key.")
	_dialog.acknowledge_command(true, false)
	_button("补付欠饷").emit_signal("pressed")
	_check(_requests.back().type == "payHeroArrears" and _requests.back().args == ["lin", "salary-original"], "Salary uses the original keyed quotation.")
	_dialog.acknowledge_command(true, false)
	_button("赠送所选宝物").emit_signal("pressed")
	_check(_requests.back().type == "useItem" and _requests.back().args == ["politics", "lin"], "Treasure must preserve the selected hero target.")
	_dialog.acknowledge_command(true, false)
	_dialog._hero_selector.select(1)
	_dialog._hero_selector.emit_signal("item_selected", 1)
	_check(_button("演练").disabled and _button("奖励黄金").disabled, "A busy hero cannot train or receive a loyalty reward.")
	_dialog._hero_selector.select(0)
	_dialog._hero_selector.emit_signal("item_selected", 0)
	(_dialog._points.pol as SpinBox).get_line_edit().text = "2"
	var changed: Dictionary = _view.duplicate(true)
	changed.heroes.items.append({"id": "valor", "name": "勇武宝物", "count": 1})
	_dialog.update_view(changed)
	_check(_dialog._selected_hero == "lin" and (_dialog._points.pol as SpinBox).get_line_edit().text == "2", "A structural inventory update preserves hero selection and typed drafts.")
	(_dialog._points.pol as SpinBox).get_line_edit().text = "100"
	(_dialog._points.pol as SpinBox).get_line_edit().emit_signal("text_changed", "100")
	_check(_button("确认加点 · 100 点").disabled, "A draft beyond the original available points cannot submit.")


func _wild() -> void:
	_dialog.show_section("wild", _view)
	await _settle()
	_button("地图定位").emit_signal("pressed")
	_check(_focus == [Vector2i(28, 34)], "Map focus sends only discovered lead coordinates.")
	_check(_button("选择部队出征").disabled, "A portrait is required before capture dispatch.")
	_button("购买画像").emit_signal("pressed")
	_check(_requests.back().type == "wild.buyPortrait" and _requests.back().args == ["wanderer", "portrait-original"], "Portrait purchase uses the current canonical key.")
	_dialog.acknowledge_command(true, false)
	var purchased: Dictionary = _view.duplicate(true)
	purchased.heroes.wild[0].portrait.reason = "已永久拥有这名将领的画像"
	purchased.heroes.wild[0].dispatchReason = ""
	_dialog.update_view(purchased)
	_check(_button("购买画像").disabled, "An owned portrait cannot be purchased again.")
	_button("选择部队出征").emit_signal("pressed")
	_check(_dispatches == ["wild_28_34"], "Dispatch requests the original node through the existing army chooser.")
	purchased.heroes.wild[0].dispatchReason = "共享房间暂不开放私人野将出征"
	_dialog.update_view(purchased)
	_check(_button("选择部队出征").disabled, "Shared rooms must disable private wild dispatch with its service reason.")
	_dialog.set_command_state(false, false)
	_check(_button("在客栈打听线索").disabled, "Disconnected dialogs cannot issue an inquiry.")
	_dialog.set_command_state(true, false)


func _captives() -> void:
	_dialog.show_section("captives", _view)
	await _settle()
	_check(_button("珍宝招降").disabled and _button("珍宝招降").tooltip_text == "珍珠不足", "The service recruitment shortage must be visible and block the action.")
	_button("黄金招降").emit_signal("pressed")
	_check(_requests.back().type == "wild.recruit" and _requests.back().args == ["local_1", "gold", "recruit-gold-original"], "Wild recruitment sends its canonical method and key.")
	_dialog.set_command_state(true, false)
	_dialog.show_error("黄金不足，请重新核对报价")
	_check(_dialog.visible and _dialog._status.text.contains("黄金不足"), "Failed resource commands keep the panel and visible reason.")
	var defeated: Dictionary = _view.duplicate(true)
	defeated.heroes.captives[0].kind = "defeated"
	defeated.heroes.captives[0].release = null
	_dialog.show_section("captives", defeated)
	_button("黄金招降").emit_signal("pressed")
	_check(_requests.back().type == "recruitDefeatedHero", "Defeated heroes use the existing governance recruitment command.")
	_dialog.acknowledge_command(true, false)


func _equipment() -> void:
	_dialog.show_section("equipment", _view)
	await _settle()
	_check(_button("卸下装备").disabled, "An unworn item cannot be unequipped.")
	_button("穿戴到所选将领").emit_signal("pressed")
	_check(_requests.back().type == "hero.equip" and _requests.back().args == [1, "lin"], "Equipment IDs stay numeric and the selected hero is preserved.")
	_dialog.acknowledge_command(true, false)
	_button("强化装备").emit_signal("pressed")
	_check(_requests.back().type == "hero.enhance" and _requests.back().args == [1], "Enhancement sends the existing item command.")
	_dialog.acknowledge_command(true, false)
	_button("打造所选装备").emit_signal("pressed")
	_check(_requests.back().type == "hero.forge" and _requests.back().args == ["armor", 2], "Forge submits the existing slot and quality tier.")
	_dialog.acknowledge_command(true, false)
	_dialog._hero_selector.select(1)
	_dialog._hero_selector.emit_signal("item_selected", 1)
	_check(_button("穿戴到所选将领").disabled, "The server busy equip reason cannot be bypassed with selection.")
	_dialog._hero_selector.select(0)
	_dialog._hero_selector.emit_signal("item_selected", 0)


func _layout() -> void:
	root.size = Vector2i(390, 844)
	for section: String in ["generals", "wild", "captives", "equipment"]:
		_dialog.show_section(section, _view)
		await _settle()
		_check(_dialog.size.x <= 350, section + " dialog fits the narrow viewport.")
		_check(_dialog._content.size.x <= _dialog.size.x, section + " content cannot introduce horizontal overflow.")
		for action: Dictionary in _dialog._actions:
			_check((action.button as Button).size.x <= _dialog.size.x, section + " actions fit the narrow dialog.")
