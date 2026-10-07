class_name KingdomProgressionDialog
extends AcceptDialog

## All prices, eligibility and command arguments are service projections.
## Stable keyed cards preserve the chosen section/filter and scroll on polling.
signal command_requested(type: String, args: Array)
signal route_requested(route: String, target: String)

const TITLES: Dictionary = {"missions": "主线任务", "daily": "每日任务", "epic": "黄巾史诗", "honors": "官职爵位", "preparation": "晋升筹备", "chapters": "征战章节", "campaign": "战役军令", "gifts": "十阶礼包"}
const RES_NAMES: Dictionary = {"food": "粮草", "wood": "木材", "stone": "石料", "iron": "铁锭", "gold": "黄金"}
var _view: Dictionary = {}
var _section: String = "missions"
var _connected: bool = true
var _pending: bool = false
var _error_message: String = ""
var _scroll: ScrollContainer
var _content: VBoxContainer
var _cards: VBoxContainer
var _status: Label
var _filter: OptionButton
var _filters: Dictionary = {}
var _rows: Dictionary = {}
var _records: Dictionary = {}
var _order: Array[String] = []


func _ready() -> void:
	dialog_text = ""
	get_ok_button().text = "关闭"
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_build_section()


func show_section(section: String, view: Dictionary) -> void:
	_view = view
	var aliases: Dictionary = {"tasks": "missions", "task": "missions", "gift": "gifts", "rank": "honors"}
	section = str(aliases.get(section, section))
	var selected: String = section if TITLES.has(section) else "missions"
	if _section != selected or not is_instance_valid(_cards):
		_section = selected
		_build_section()
	_error_message = ""
	update_view(view)
	_fit_window()
	popup_centered()


func update_view(view: Dictionary) -> void:
	_view = view
	if not is_instance_valid(_cards):
		return
	var progression: Dictionary = _view.get("progression", {})
	var records: Array[Dictionary] = []
	if progression.is_empty():
		records.append(_record("loading", "正在读取任务与进程", "连接规则服务后显示当前目标、礼包和晋升条件。"))
	else:
		if not str(progression.get("reason", "")).is_empty():
			records.append(_record("mode", "共享房间能力", str(progression.reason)))
		match _section:
			"missions": _mission_records(progression, records)
			"daily": _daily_records(progression, records)
			"epic": _epic_records(progression, records)
			"honors": _honor_records(progression, records)
			"preparation": _preparation_records(progression, records)
			"campaign": _campaign_records(records)
			"chapters": _chapter_records(progression, records)
			"gifts": _gift_records(progression, records)
	_sync_rows(records)
	_update_status()


func select_filter(index: int) -> void:
	if not is_instance_valid(_filter) or index < 0 or index >= _filter.item_count: return
	_filters[_section] = index
	_filter.select(index)
	update_view(_view)


func set_command_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	if is_instance_valid(_cards):
		_refresh_buttons()
		_update_status()


func show_error(message: String) -> void:
	_error_message = message
	_update_status()


func acknowledge_command(connected: bool, pending: bool) -> void:
	_error_message = ""
	set_command_state(connected, pending)


func _update_status() -> void:
	if not is_instance_valid(_status):
		return
	_status.text = _error_message if not _error_message.is_empty() else "操作已发出，等待确认…" if _pending else "请先连接规则服务" if not _connected else "奖励、捐献和晋升成功后自动保存"
	_status.modulate = Color("e7bc72") if not _error_message.is_empty() else Color.WHITE


func _fit_window() -> void:
	var available: Vector2 = Vector2(get_tree().root.size)
	if get_parent() is Control:
		available = (get_parent() as Control).size
	var width: int = mini(720, maxi(280, int(available.x) - 40))
	var height: int = mini(680, maxi(280, int(available.y) - 80))
	_scroll.custom_minimum_size = Vector2(float(width - 48), float(height - 90))
	min_size = Vector2i(width, height)
	size = min_size
	position = Vector2i((available - Vector2(size)) / 2.0)


func _build_section() -> void:
	if not is_instance_valid(_content):
		return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_rows.clear()
	_records.clear()
	_order.clear()
	_filter = null
	title = str(TITLES[_section])
	var tabs: GridContainer = GridContainer.new()
	tabs.columns = 3
	_content.add_child(tabs)
	for section: String in TITLES:
		var tab: Button = _button(str(TITLES[section]), func() -> void: show_section(section, _view))
		tab.disabled = section == _section
		tabs.add_child(tab)
	_status = _label("", 13)
	_content.add_child(_status)
	var filter_names: Array[String] = []
	match _section:
		"missions": filter_names.assign(["未领取", "可领取", "全部任务"])
		"daily": filter_names.assign(["全部任务", "已接取", "可接取"])
		"epic": filter_names.assign(["捐献资源", "捐献部队", "进献珍宝", "铜钱兑换"])
		"campaign": filter_names.assign(["野战破阵", "攻坚拔寨", "精锐会战", "军功兑换"])
	if not filter_names.is_empty():
		_filter = OptionButton.new()
		_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for filter_name: String in filter_names:
			_filter.add_item(filter_name)
		_filter.select(int(_filters.get(_section, 0)))
		_filter.item_selected.connect(func(index: int) -> void: _filters[_section] = index; update_view(_view))
		_content.add_child(_filter)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 12)
	_content.add_child(_cards)
	update_view(_view)


func _label(text: String, font_size: int = 16) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 44.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


func _record(id: String, heading: String, body: String, actions: Array = []) -> Dictionary:
	return {"id": id, "heading": heading, "body": body, "actions": actions}


func _action(label: String, command: Dictionary, reason: String = "") -> Dictionary:
	return {"label": label, "command": command, "reason": reason}


func _navigate(label: String, route: String, target: String = "", reason: String = "") -> Dictionary:
	return {"label": label, "route": route, "target": target, "reason": reason}


func _reward_text(reward: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in reward.get("resources", {}):
		var count: int = int(reward.resources[id])
		if count > 0:
			parts.append(str(RES_NAMES.get(id, id)) + " " + str(count))
	for kind: String in ["items", "army", "jewels"]:
		for entry: Dictionary in reward.get(kind, []):
			parts.append(str(entry.get("name", entry.get("id", ""))) + " ×" + str(int(entry.get("count", 0))))
	for extra: Array in [["prestige", "声望"], ["copper", "铜钱"]]:
		if int(reward.get(extra[0], 0)) > 0:
			parts.append(str(extra[1]) + " " + str(int(reward[extra[0]])))
	return "、".join(parts) if not parts.is_empty() else "无"


func _guide_record(progression: Dictionary) -> Dictionary:
	var guide: Dictionary = progression.get("firstBattle", {})
	var steps: Array[String] = []
	for step: Dictionary in guide.get("requirementSteps", []):
		steps.append(str(step.get("name", step.get("id", "前置条件"))) + " " + str(int(step.get("current", 0))) + " / " + str(int(step.get("level", 0))) + " 级")
	steps.append("城内弓箭兵 " + str(int(guide.get("archers", 0))) + " / " + str(int(guide.get("target", 30))))
	steps.append("出征胜利 " + str(int(guide.get("victories", 0))) + " 场")
	var next: Dictionary = guide.get("next", {})
	var actions: Array = []
	if not bool(guide.get("complete", false)):
		actions.append(_navigate("前往下一步", str(next.get("route", "army")), str(next.get("target", "archer")), str(guide.get("navigationReason", ""))))
		actions.append(_action("完成首战引导", guide.get("finish", {}), "" if bool(guide.get("ready", false)) else str(guide.get("reason", "条件尚未达成"))))
	var reason: String = str(guide.get("reason", ""))
	return _record("guide", "首战准备 · 以弓兵为主力", "\n".join(steps) + "\n" + (reason if not reason.is_empty() else "首战条件已满足，可完成引导"), actions)


func _mission_records(progression: Dictionary, records: Array[Dictionary]) -> void:
	records.append(_guide_record(progression))
	var claim: Dictionary = progression.get("claimMissions", {})
	records.append(_record("mission-all", "任务奖励", "领取所有当前已达成的任务；尚未开放的据点随推进显示。", [_action("一键领取任务", claim.get("command", {}), str(claim.get("reason", "")))]))
	var filter_index: int = int(_filters.get("missions", 0))
	var shown: int = 0
	for mission: Dictionary in progression.get("missions", []):
		if filter_index == 0 and bool(mission.get("claimed", false)) or filter_index == 1 and not bool(mission.get("ready", false)):
			continue
		shown += 1
		var state: String = "已领取" if mission.get("claimed", false) else "可领取" if mission.get("ready", false) else "进行中"
		var body: String = str(mission.get("stage", "")) + " · " + state + "\n" + str(mission.get("description", ""))
		if not str(mission.get("currentStatus", "")).is_empty():
			body += "\n" + str(mission.currentStatus)
		body += "\n奖励：" + _reward_text(mission.get("rewards", {}))
		var reason: String = str(mission.get("reason", ""))
		if not reason.is_empty() and bool(progression.get("shared", false)):
			body += "\n" + reason
		var navigate: Dictionary = mission.get("navigate", {})
		records.append(_record("mission-" + str(mission.id), ("当前 · " if mission.get("current", false) else "") + str(mission.title), body,
			[_action("领取奖励", mission.get("claim", {}), reason), _navigate("前往目标", str(navigate.get("route", "city")), str(navigate.get("target", "")), str(mission.get("navigationReason", "")))]))
	if shown == 0:
		records.append(_record("empty", "当前没有符合筛选的任务", "可切换筛选，或继续城池建设与征战。"))


func _daily_records(progression: Dictionary, records: Array[Dictionary]) -> void:
	var daily: Dictionary = progression.get("daily", {})
	var claim: Dictionary = daily.get("claimAll", {})
	records.append(_record("daily-summary", "每日任务", "已接取 %d / %d · 今日完成 %d\n北京时间05:00刷新；接取后的行动才计入任务进度。资源交付任务会扣除所需库存。" % [int(daily.get("accepted", 0)), int(daily.get("limit", 0)), int(daily.get("claimed", 0))], [_action("一键领取已完成", claim.get("command", {}), str(claim.get("reason", "")))]))
	for milestone: Dictionary in daily.get("milestones", []):
		records.append(_record("milestone-" + str(milestone.count), "今日完成 " + str(int(milestone.count)) + " 项", "奖励：" + _reward_text(milestone.get("rewards", {})) + "\n" + str(milestone.get("reason", "")), [_action("领取里程碑", milestone.get("command", {}), str(milestone.get("reason", "")))]))
	var filter_index: int = int(_filters.get("daily", 0))
	for task: Dictionary in daily.get("tasks", []):
		var accepted: bool = str(task.get("status", "")) == "accepted"
		if filter_index == 1 and not accepted or filter_index == 2 and accepted:
			continue
		var body: String = ("已接取" if accepted else "可接取") + " · %d / %d\n" % [int(task.get("progress", 0)), int(task.get("target", 0))] + str(task.description) + "\n奖励：" + _reward_text(task.get("rewards", {}))
		if not task.get("payment", {}).is_empty():
			body += "\n交付：" + _reward_text({"resources": task.payment})
		if not str(task.get("reason", "")).is_empty():
			body += "\n" + str(task.reason)
		var actions: Array = [_action("领取奖励" if accepted else "接取任务", task.get("claim", {}) if accepted else task.get("accept", {}), str(task.get("claimReason", "")) if accepted else str(task.get("acceptReason", "")))]
		if accepted:
			actions.append(_action("放弃任务", task.get("abandon", {}), str(task.get("abandonReason", ""))))
		actions.append(_navigate("前往办理", str(task.get("route", "city")), "", str(task.get("reason", ""))))
		records.append(_record("daily-" + str(task.id), str(task.title), body, actions))


func _epic_records(progression: Dictionary, records: Array[Dictionary]) -> void:
	var epic: Dictionary = progression.get("epic", {})
	var groups: Array[String] = []
	for group: Dictionary in epic.get("groups", []):
		groups.append(("已达成 · " if float(group.get("progress", 0)) >= 1.0 else "未完成 · ") + str(group.get("name", "")) + "\n" + str(group.get("detail", "")))
	groups.append("县城占领：" + (str(epic.get("countyReason", "")) if not str(epic.get("countyReason", "")).is_empty() else "条件已满足"))
	records.append(_record("epic-summary", "黄巾史诗 · 进军县城", "\n".join(groups), [_navigate("查看官爵", "honors"), _navigate("前往舆图", "world", "fort", str(progression.get("reason", "")))]))
	var filter_index: int = int(_filters.get("epic", 0))
	if filter_index == 3:
		records.append(_record("copper", "铜钱 " + str(int(epic.get("copper", 0))), "每日任务获得铜钱；可兑换珍珠和当日宝物。县城筹备珊瑚共限5枚，不随每日刷新。"))
		for offer: Dictionary in epic.get("exchanges", []):
			var period: String = str(offer.get("period", "daily"))
			var limit_text: String = ("全存档" if period == "save" else "本次晋升" if period == "rank" else "今日") + "已兑 %d / %d · 剩余 %d" % [int(offer.get("claimed", 0)), int(offer.get("limit", 0)), int(offer.get("remaining", 0))]
			records.append(_record("exchange-" + str(offer.id), str(offer.name), "费用：铜钱 %d · %s\n%s" % [int(offer.get("cost", 0)), limit_text, str(offer.get("reason", ""))], [_action("兑换", offer.get("command", {}), str(offer.get("reason", "")))]))
		return
	var kinds: Array[String] = ["resource", "troop", "jewel"]
	for donation: Dictionary in epic.get("donations", []):
		if str(donation.get("kind", "")) != kinds[filter_index]:
			continue
		var body: String = "交付 %s ×%d\n声望 +%d" % [str(donation.name), int(donation.get("cost", 0)), int(donation.get("prestige", 0))]
		if int(donation.get("points", 0)) > 0:
			body += " · 史诗进度 +" + str(int(donation.points))
		body += "\n" + ("捐献后部队将离开你的军队。\n" if str(donation.kind) == "troop" else "") + str(donation.get("reason", ""))
		records.append(_record("donation-" + str(donation.kind) + "-" + str(donation.id), str(donation.name), body, [_action("确认进献", donation.get("command", {}), str(donation.get("reason", "")))]))


func _honor_records(progression: Dictionary, records: Array[Dictionary]) -> void:
	var honors: Dictionary = progression.get("honors", {})
	var jewels: Array[String] = []
	for jewel: Dictionary in honors.get("jewels", []):
		jewels.append(str(jewel.name) + " " + str(int(jewel.count)))
	records.append(_record("honor-summary", "官职与爵位", "官职 %s · 爵位 %s\n声望 %d · 城池 %d / %d\n珍宝：%s" % [str(honors.get("office", {}).get("name", "")), str(honors.get("noble", {}).get("name", "")), int(honors.get("prestige", 0)), int(honors.get("cities", 0)), int(honors.get("cityLimit", 0)), "、".join(jewels)], [_navigate("打开宝物", "inventory"), _navigate("铜钱与史诗", "epic")]))
	for promotion: Dictionary in honors.get("promotions", []):
		var kind: String = str(promotion.kind)
		var next: Dictionary = promotion.get("next") if promotion.get("next") is Dictionary else {}
		var body: String = "已达最高级别" if next.is_empty() else "下一阶：" + str(next.get("name", "")) + "\n消耗：" + _reward_text(promotion.get("cost", {})) + "\n" + (str(promotion.get("reason", "")) if not str(promotion.get("reason", "")).is_empty() else "晋升条件已满足")
		if kind == "noble" and not next.is_empty():
			body += "\n晋升后城池上限 " + str(int(next.get("city_count", 0)))
		records.append(_record("promotion-" + kind, "晋升官职" if kind == "office" else "晋升爵位", body, [_action("确认晋升", promotion.get("command", {}), str(promotion.get("reason", "")))]))
	for salary: Dictionary in honors.get("salaries", []):
		records.append(_record("salary-" + str(salary.kind), "官职俸禄" if str(salary.kind) == "office" else "封邑俸禄", "领取：" + _reward_text(salary.get("rewards", {})) + "\n" + str(salary.get("reason", "")), [_action("领取俸禄", salary.get("command", {}), str(salary.get("reason", "")))]))


func _chapter_records(progression: Dictionary, records: Array[Dictionary]) -> void:
	records.append(_record("chapter-rule", "章节推进", "占领古渡县城开启第二章；第二章全部六关占领后开启第三章。掠夺获胜不算章节通关。", [_navigate("黄巾史诗门槛", "epic"), _navigate("官爵城池上限", "honors")]))
	for chapter: Dictionary in progression.get("chapters", []):
		var body: String = "占领 %d / %d · 任务已领 %d\n%s" % [int(chapter.get("conquered", 0)), int(chapter.get("total", 0)), int(chapter.get("claimed", 0)), str(chapter.get("reason", ""))]
		var actions: Array = []
		var next: Dictionary = chapter.get("next") if chapter.get("next") is Dictionary else {}
		if not next.is_empty():
			body += "\n下一据点：" + str(next.name)
			actions.append(_navigate("定位下一据点", "world", str(next.id)))
		for node: Dictionary in chapter.get("visibleNodes", []):
			body += "\n" + str(node.name) + (" · 已占领" if node.get("conquered", false) else " · 当前开放")
		records.append(_record("chapter-" + str(chapter.chapter), str(chapter.title), body, actions))


func _campaign_records(records: Array[Dictionary]) -> void:
	var campaign: Dictionary = _view.get("campaign", {})
	var summary: String = "可用军功 %d · 累计获得 %d\n首次普通通关获得双倍军功；战术挑战首次达标另有奖励。军功可选择用于将领专长或兑换宝物。" % [int(campaign.get("merit", 0)), int(campaign.get("earned", 0))]
	if not campaign.get("unlocked", false):
		records.append(_record("campaign-locked", "长期征战", str(campaign.get("reason", "正在读取战役军令")), [_navigate("查看章节目标", "chapters")]))
		return
	records.append(_record("campaign-summary", "三条军令路线", summary, [_navigate("将领专长训练", "specialization")]))
	var filter_index: int = int(_filters.get("campaign", 0))
	if filter_index == 3:
		for offer: Dictionary in campaign.get("offers", []):
			records.append(_record("merit-" + str(offer.id), str(offer.name), "军功 %d · 背包持有 %d\n%s\n%s" % [int(offer.cost), int(offer.get("owned", 0)), str(offer.get("description", "")), str(offer.get("reason", ""))], [_action("确认兑换1件", offer.get("command", {}), str(offer.get("reason", "")))]))
		return
	var routes: Array = campaign.get("routes", [])
	if filter_index >= routes.size():
		return
	var route: Dictionary = routes[filter_index]
	records.append(_record("route-" + str(route.id), str(route.name), "已通关 %d / %d 阶 · 胜利 %d 次\n整军剩余 %d 秒\n%s\n本路线队伍返城后可再出征；军令讨伐不会取得领地。" % [int(route.get("cleared", 0)), int(route.get("max", 0)), int(route.get("wins", 0)), int(route.get("recoverySeconds", 0)), str(route.get("hint", ""))]))
	var targets: Array = route.get("targets", []).duplicate()
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_order: int = 0 if a.get("first", false) else 2 if a.get("completed", false) else 1
		var b_order: int = 0 if b.get("first", false) else 2 if b.get("completed", false) else 1
		return int(a.get("orderTier", 0)) < int(b.get("orderTier", 0)) if a_order == b_order else a_order < b_order)
	for target: Dictionary in targets:
		var body: String = ("已达成" if target.get("completed", false) else "待挑战") + " · 胜利军功 %d" % int(target.get("points", 0))
		if int(target.get("bonus", 0)) > 0:
			body += " · 首次达标额外 +%d" % int(target.bonus)
		body += "\n" + str(target.get("condition", "")) + "\n" + str(target.get("hint", ""))
		if target.get("intel", {}).get("public", false):
			var enemies: PackedStringArray = []
			for unit_id: String in target.get("army", {}):
				if int(target.army[unit_id]) <= 0:
					continue
				var unit_name: String = unit_id
				for unit: Dictionary in _view.get("units", []):
					if str(unit.get("id", "")) == unit_id:
						unit_name = str(unit.get("name", unit_id))
				enemies.append(unit_name + " ×" + str(int(target.army[unit_id])))
			body += "\n公开守军：" + "、".join(enemies)
		var gate: Variant = target.get("gate")
		if gate is Dictionary:
			body += "\n%s · 耐久 %d" % [str(gate.get("name", "门墙")), int(gate.get("hp", 0))]
		var attempt: Variant = target.get("lastAttempt")
		if attempt is Dictionary:
			body += "\n上次 %d 回合 · 永久损失 %d / 出征 %d · %s" % [int(attempt.get("round", 0)), int(attempt.get("lost", 0)), int(attempt.get("deployed", 0)), "战术达标" if attempt.get("met", false) else "战术未达标"]
		body += "\n" + str(target.get("reason", ""))
		records.append(_record("order-" + str(target.id), str(target.name), body, [_navigate("配兵讨伐", "campaign", str(target.id), str(target.get("reason", "")))]))


func _preparation_records(progression: Dictionary, records: Array[Dictionary]) -> void:
	var honors: Dictionary = progression.get("honors", {})
	var stocks: Dictionary = {}
	var names: Dictionary = {}
	for jewel: Dictionary in honors.get("jewels", []):
		stocks[str(jewel.id)] = int(jewel.get("count", 0))
		names[str(jewel.id)] = str(jewel.get("name", jewel.id))
	records.append(_record("prepare-summary", "晋升筹备 · 铜钱 %d" % int(progression.get("epic", {}).get("copper", 0)), "每天完成小任务获得铜钱。珍珠可每日固定兑换；各类晋升珍宝也可按当前阶段的有限份额筹备。新增筹备价格为试玩设定。\n兑换的珍宝进入共同库存，请为晋升保留所需数量。", [_navigate("接取每日任务", "daily"), _navigate("查看野地采集", "holdings")]))
	if progression.get("shared", false):
		records.append(_record("prepare-shared", "房间进度", "阶段筹备用于本机进度；当前房间保留原有每日兑换。"))
	for promotion: Dictionary in honors.get("promotions", []):
		var next: Variant = promotion.get("next")
		if not next is Dictionary:
			continue
		var kind: String = str(promotion.kind)
		var rule: Dictionary = promotion.get("rule", {})
		var gold_required: int = int(rule.get("gold", 0))
		var gold_owned: int = int(_view.get("res", {}).get("gold", 0))
		var lines: PackedStringArray = ["声望需要 %d · 当前 %d" % [int(rule.get("prestige", 0)), int(honors.get("prestige", 0))], "黄金 %d / %d · 还缺 %d" % [gold_owned, gold_required, maxi(0, gold_required - gold_owned)]]
		for jewel: String in rule.get("jewels", {}):
			var required: int = int(rule.jewels[jewel])
			var owned: int = int(stocks.get(jewel, 0))
			lines.append("%s %d / %d · 还缺 %d" % [str(names.get(jewel, jewel)), owned, required, maxi(0, required - owned)])
		lines.append(str(promotion.get("reason", "")))
		records.append(_record("prepare-" + kind, "下一" + ("官职" if kind == "office" else "爵位") + " · " + str(next.get("name", "")), "\n".join(lines), [_navigate("核对并晋升", "honors")]))
		for offer: Dictionary in progression.get("epic", {}).get("exchanges", []):
			var is_pearl: bool = str(offer.id) == "pearl" and rule.get("jewels", {}).has("pearl")
			var is_first_coral: bool = str(offer.id) == "growth_coral" and kind == "noble" and int(next.get("id", 0)) == 1
			var is_stage: bool = str(offer.get("kind", "")) == kind and int(offer.get("rank", 0)) == int(next.get("id", -1))
			if not is_pearl and not is_first_coral and not is_stage:
				continue
			var label: String = "今日" if str(offer.get("period", "")) == "daily" else "全存档" if str(offer.get("period", "")) == "save" else "本次晋升"
			var body: String = "固定获得1枚 · 铜钱 %d\n%s已兑 %d / %d · 剩余 %d\n%s" % [int(offer.get("cost", 0)), label, int(offer.get("claimed", 0)), int(offer.get("limit", 0)), int(offer.get("remaining", 0)), str(offer.get("reason", ""))]
			var reason: String = str(offer.get("reason", ""))
			if is_first_coral and int(stocks.get("coral", 0)) >= int(rule.get("jewels", {}).get("coral", 0)):
				reason = "本次晋升所需珊瑚已备齐"
			records.append(_record("prepare-offer-" + kind + "-" + str(offer.id), str(offer.name), body, [_action("确认兑换1枚", offer.get("command", {}), reason)]))


func _gift_records(progression: Dictionary, records: Array[Dictionary]) -> void:
	var gifts: Dictionary = progression.get("gifts", {})
	var claim: Dictionary = gifts.get("claimAll", {})
	records.append(_record("gift-all", "按官府等级领取 · 共十阶", "当前可领 %d 阶；礼包每阶仅领取一次，后期含珠宝盒与装备盒。" % int(gifts.get("available", 0)), [_action("一键领取已解锁", claim.get("command", {}), str(claim.get("reason", ""))), _navigate("使用加速与开箱", "inventory")]))
	for gift: Dictionary in gifts.get("levels", []):
		var state: String = "已领取" if gift.get("claimed", false) else "可领取" if gift.get("unlocked", false) else "未解锁"
		records.append(_record("gift-" + str(gift.level), "%d阶 · %s" % [int(gift.level), str(gift.title)], state + "\n奖励：" + _reward_text(gift.get("rewards", {})) + "\n" + str(gift.get("reason", "")), [_action("领取这一阶", gift.get("command", {}), str(gift.get("reason", "")))]))


func _sync_rows(records: Array[Dictionary]) -> void:
	var new_order: Array[String] = []
	for record: Dictionary in records:
		var id: String = str(record.id)
		new_order.append(id)
		_records[id] = record
		if not _rows.has(id):
			var container: VBoxContainer = VBoxContainer.new()
			container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_cards.add_child(container)
			var heading: Label = _label("", 19)
			container.add_child(heading)
			var body: Label = _label("", 14)
			container.add_child(body)
			var actions: GridContainer = GridContainer.new()
			actions.columns = 2
			container.add_child(actions)
			_rows[id] = {"container": container, "heading": heading, "body": body, "actions": actions}
		var row: Dictionary = _rows[id]
		row.heading.text = str(record.heading)
		row.body.text = str(record.body)
		var action_records: Array = record.get("actions", [])
		var grid: GridContainer = row.actions
		while grid.get_child_count() > action_records.size():
			var child: Node = grid.get_child(grid.get_child_count() - 1)
			grid.remove_child(child)
			child.queue_free()
		while grid.get_child_count() < action_records.size():
			var index: int = grid.get_child_count()
			grid.add_child(_button("", _activate.bind(id, index)))
		_update_row_buttons(id)
	for id: String in _order:
		if not new_order.has(id):
			var container: Node = _rows[id].container
			_cards.remove_child(container)
			container.queue_free()
			_rows.erase(id)
			_records.erase(id)
	for index: int in new_order.size():
		_cards.move_child(_rows[new_order[index]].container, index)
	_order = new_order


func _refresh_buttons() -> void:
	for id: String in _rows:
		_update_row_buttons(id)


func _update_row_buttons(id: String) -> void:
	var grid: GridContainer = _rows[id].actions
	var actions: Array = _records[id].get("actions", [])
	for index: int in actions.size():
		var action: Dictionary = actions[index]
		var button: Button = grid.get_child(index) as Button
		button.text = str(action.label)
		button.tooltip_text = str(action.get("reason", ""))
		button.disabled = not str(action.get("reason", "")).is_empty() or (action.has("command") and (not _connected or _pending or action.command.is_empty()))


func _activate(id: String, index: int) -> void:
	if not _records.has(id):
		return
	var actions: Array = _records[id].get("actions", [])
	if index < 0 or index >= actions.size():
		return
	var action: Dictionary = actions[index]
	if not str(action.get("reason", "")).is_empty():
		show_error(str(action.reason))
		return
	if action.has("route"):
		route_requested.emit(str(action.route), str(action.get("target", "")))
		return
	if not _connected or _pending:
		return
	var command: Dictionary = action.get("command", {})
	if str(command.get("type", "")).is_empty():
		return
	_error_message = ""
	_pending = true
	_refresh_buttons()
	_update_status()
	command_requested.emit(str(command.type), command.get("args", []))
