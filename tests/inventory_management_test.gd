extends SceneTree

const InventoryDialog = preload("res://src/inventory_dialog.gd")
var _dialog: KingdomInventoryDialog
var _view: Dictionary
var _requests: Array[Dictionary] = []
var _routes: Array[Array] = []
var _checks: int = 0
var _failures: int = 0


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


func _row(id: String, effect: String, kind: String = "none", targets: Array = []) -> Dictionary:
	return {"id": id, "name": id, "category": "宝物", "description": "原规则宝物说明", "effect": effect, "count": 2, "price": 999, "supported": true, "rewardOnly": false, "purchase": {"limit": 3, "costs": [7, 19, 44], "reason": "", "remaining": null}, "use": {"targetKind": kind, "targets": targets, "reason": "", "route": null, "maxLength": 12}}


func _fixture() -> Dictionary:
	var items: Array = []
	items.append(_row("box", "equipmentBox", "slot", [{"id": "weapon", "name": "兵器", "reason": ""}, {"id": "helmet", "name": "头盔", "reason": ""}]))
	items.append(_row("jewels", "jewelBox"))
	items.append(_row("speed", "speedup", "speedup", [{"key": "build:site0:original", "name": "城内1号 · 官府", "reason": "", "quote": {"workMs": 3600000, "waitMs": 0, "afterMinMs": 0, "afterMaxMs": 0, "overflow": true}}]))
	items.append(_row("politics", "politics", "hero", [{"id": "lin", "name": "林衡", "reason": ""}, {"id": "su", "name": "苏荷", "reason": ""}]))
	items.append(_row("reset", "heroReset", "hero", [{"id": "lin", "name": "林衡", "reason": "", "consume": 2}, {"id": "su", "name": "苏荷", "reason": "将领在外，请返城"}]))
	items.append(_row("rename", "rename", "text"))
	items.append(_row("material", "equipmentMaterial"))
	items[-1].use.reason = "强化宝珠在装备详情中使用"
	items[-1].use.route = {"route": "heroes", "target": "equipment", "label": "前往装备强化"}
	items.append(_row("blueprint", "blueprint"))
	items[-1].use.reason = "图纸在建筑升至 10 级时自动消耗，请在建筑页面使用"
	items[-1].use.route = {"route": "city", "target": "blueprint", "label": "前往城内建设"}
	items.append(_row("brick", "gold"))
	items[-1].purchase = {"limit": 0, "remaining": 0, "dailyLimit": 20, "costs": [], "reason": "该种金砖每日限购 20 块，今日剩余 0 块"}
	return {"inventoryManagement": {"items": items, "categories": ["宝物"], "gems": 100, "lastOpen": {"name": "铁盔", "kind": "equipment", "count": 1}}}


func _select(id: String) -> void:
	for index: int in range(_dialog._items.item_count):
		if str(_dialog._items.get_item_metadata(index)) == id:
			_dialog._items.select(index)
			_dialog._items.emit_signal("item_selected", index)
			return
	_check(false, "Fixture item must be selectable: " + id)


func _finish() -> void:
	_dialog.acknowledge_command(true, false)


func _run() -> void:
	root.size = Vector2i(1280, 844)
	_view = JSON.parse_string(JSON.stringify(_fixture()))
	_dialog = InventoryDialog.new()
	root.add_child(_dialog)
	_dialog.command_requested.connect(func(type: String, args: Array) -> void: _requests.append({"type": type, "args": args}))
	_dialog.route_requested.connect(func(route: String, target: String) -> void: _routes.append([route, target]))
	_dialog.show_section("inventory", _view)
	await _settle()
	await _boxes_and_speedup()
	await _hero_and_text()
	await _shop()
	await _layout()
	root.remove_child(_dialog)
	_dialog.queue_free()
	await process_frame
	print("INVENTORY_MANAGEMENT_TEST_CHECKS=", _checks, " failures=", _failures)
	quit(0 if _failures == 0 else 1)


func _boxes_and_speedup() -> void:
	_select("box")
	_dialog._target.select(1)
	_dialog._target.emit_signal("item_selected", 1)
	_dialog._apply.emit_signal("pressed")
	_check(_requests.back() == {"type": "onboarding.openItem", "args": ["box", "helmet"]}, "Equipment boxes send the selected canonical slot, never a targetless useItem.")
	var count: int = _requests.size()
	_dialog._apply.emit_signal("pressed")
	_dialog.update_view(_view)
	_check(_requests.size() == count and _dialog._apply.disabled, "Pending mutations remain blocked across button presses and polling.")
	_finish()
	_select("jewels")
	_dialog._apply.emit_signal("pressed")
	_check(_requests.back() == {"type": "onboarding.openItem", "args": ["jewels"]}, "Jewel boxes keep the original random-open command.")
	_finish()
	_select("speed")
	_check(_dialog._quote.text.contains("3600") and _dialog._quote.text.contains("超出"), "Acceleration displays canonical time preview and overflow.")
	_dialog._apply.emit_signal("pressed")
	_check(_requests.back() == {"type": "useSpeedup", "args": ["speed", "build:site0:original"]}, "Acceleration uses the original task key.")
	_finish()
	var removed: Dictionary = _view.duplicate(true)
	removed.inventoryManagement.items[2].use.targets = [{"key": "build:site1:new", "name": "新任务", "reason": "", "quote": {"workMs": 10000}}]
	_dialog.update_view(removed)
	_check(_dialog._target_id == "build:site0:original" and _dialog._apply.disabled, "An ended acceleration target stays selected and blocked; polling cannot silently pick another queue.")
	_dialog.update_view(_view)
	_select("material")
	_check(_dialog._apply.disabled and _dialog._route.visible, "Equipment materials explain their usage and offer the correct route.")
	_dialog._route.emit_signal("pressed")
	_check(_routes.back() == ["heroes", "equipment"], "Material route points to equipment operations.")
	_select("blueprint")
	_dialog._route.emit_signal("pressed")
	_check(_routes.back() == ["city", "blueprint"], "Blueprints route to existing building consumption.")


func _hero_and_text() -> void:
	_select("politics")
	_dialog._target.select(1)
	_dialog._target.emit_signal("item_selected", 1)
	_dialog.update_view(_view.duplicate(true))
	_dialog._apply.emit_signal("pressed")
	_check(_requests.back() == {"type": "useItem", "args": ["politics", "su"]}, "Targeted treasure preserves the selected owned hero across polling.")
	_finish()
	_select("reset")
	_check(_dialog._quote.text.contains("洗髓丹 ×2"), "Reset displays the isolated canonical preview cost.")
	_dialog._target.select(1)
	_dialog._target.emit_signal("item_selected", 1)
	_check(_dialog._apply.disabled and _dialog._quote.text.contains("返城"), "Busy reset targets display their original failure reason.")
	_select("rename")
	_dialog._text.text = "山河城主"
	_dialog._text.emit_signal("text_changed", "山河城主")
	_dialog.update_view(_view.duplicate(true))
	_check(_dialog._text.text == "山河城主", "Text drafts are retained on snapshots.")
	_dialog._apply.emit_signal("pressed")
	_check(_requests.back() == {"type": "useItem", "args": ["rename", "", "山河城主"]}, "Rename supplies the original third positional text parameter.")
	_dialog.set_command_state(true, false)
	_dialog.show_error("名称长度不合适")
	_check(_dialog.visible and _dialog._text.text == "山河城主" and _dialog._status.text.contains("名称长度"), "Failure keeps the modal, exact text draft and service error.")
	_finish()
	_dialog._search.text = "rename"
	_dialog._search.emit_signal("text_changed", "rename")
	_dialog.update_view(_view.duplicate(true))
	_check(_dialog._search.text == "rename" and _dialog._items.item_count == 1, "Search filters persist across polling.")
	_dialog._search.text = ""
	_dialog._search.emit_signal("text_changed", "")


func _shop() -> void:
	_dialog.show_section("shop", _view)
	_select("politics")
	_dialog._count.get_line_edit().text = "2"
	_dialog._count.get_line_edit().emit_signal("text_changed", "2")
	_dialog.update_view(_view.duplicate(true))
	_check(_dialog._count.get_line_edit().text == "2" and _dialog._quote.text.contains("元宝 ×19"), "Shop polling retains typed quantities and reads the service total cost table.")
	_dialog._count.get_line_edit().text = "999999"
	_dialog._count.get_line_edit().emit_signal("text_changed", "999999")
	_check(_dialog._apply.text.contains("3") and _dialog._quote.text.contains("元宝 ×44"), "Oversized purchase input previews the clamped canonical limit.")
	_dialog._apply.emit_signal("pressed")
	_check(_requests.back() == {"type": "buyItem", "args": ["politics", 3]}, "Bulk purchases commit the clamped integer count.")
	_finish()
	_select("brick")
	_check(_dialog._apply.disabled and _dialog._quote.text.contains("今日剩余 0"), "Daily-limit purchases must show the remaining count and block submission.")
	_dialog.set_command_state(false, false)
	_select("politics")
	_check(_dialog._apply.disabled, "Disconnected stores cannot buy.")
	_dialog.set_command_state(true, false)


func _layout() -> void:
	root.size = Vector2i(390, 844)
	for section: String in ["inventory", "shop"]:
		_dialog.show_section(section, _view)
		for id: String in ["box", "speed", "reset", "rename", "material", "politics"]:
			_select(id)
			await _settle()
			_check(_dialog.size.x <= 350 and _dialog._content.size.x <= _dialog.size.x, section + "/" + id + " fits a 390px viewport.")
			_check(_dialog._description.size.x <= _dialog.size.x and _dialog._apply.size.x <= _dialog.size.x, "Details and actions must not overflow horizontally.")
