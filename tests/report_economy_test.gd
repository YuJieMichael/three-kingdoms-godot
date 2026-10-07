extends SceneTree

const EconomyScript: Script = preload("res://src/report_economy_view.gd")
const UI_FONT: Font = preload("res://assets/fonts/UI.tres")
var _checks: int = 0
var _failures: int = 0
var _view: KingdomReportEconomyView
var _scroll: ScrollContainer
var _capture_enabled: bool = false


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceReportEconomyTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	_capture_enabled = OS.get_cmdline_user_args().has("--capture")
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for i: int in 5:
		await process_frame


func _text(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child: Node in node.get_children():
		result += _text(child)
	return result


func _fixture() -> Dictionary:
	# Explicit DTO fixture: no game API, canonical simulation, or player save is
	# initialized. Bridge tests separately establish the actual rule derivation.
	return {"basis": "current-canonical-prices", "status": "delivered",
		"loot": {"food": 1200, "wood": 90, "stone": 20, "iron": 10},
		"received": {"food": 1000, "wood": 90, "stone": 20},
		"permanentLoss": {"militia": 20},
		"replacement": {"resources": {"food": 1200, "wood": 200, "iron": 80, "gold": 50}, "people": 30, "soldiers": 20, "seconds": 90},
		"treatment": {"resources": {"gold": 75}, "people": 5, "available": true, "reason": "本战伤兵可能部分或全部已治疗。"},
		"net": {"resources": {"food": -200, "wood": -110, "stone": 20, "iron": -80, "gold": -125}, "kind": "projected"},
		"notes": ["Fixture：仅用于战报界面验证，不代表玩家进度。"]}


func _build_shell() -> void:
	var shell: Control = Control.new()
	shell.theme = KingdomUiTheme.create(UI_FONT)
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shell)
	var background: ColorRect = ColorRect.new()
	background.color = KingdomUiTheme.INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	shell.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	margin.add_child(column)
	var title: Label = Label.new()
	title.text = "战报收支 · Fixture"
	title.theme_type_variation = "TitleLabel"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_scroll.add_child(_view)


func _check_horizontal_bounds(node: Node, right_edge: float) -> void:
	if node is Control:
		var control: Control = node as Control
		_check(control.get_global_rect().end.x <= right_edge + 1, "%s stays inside the horizontal report viewport" % control.get_class())
	for child: Node in node.get_children():
		_check_horizontal_bounds(child, right_edge)


func _button_count(node: Node) -> int:
	var count: int = 1 if node is BaseButton else 0
	for child: Node in node.get_children():
		count += _button_count(child)
	return count


func _capture(name: String) -> void:
	if not _capture_enabled:
		return
	await RenderingServer.frame_post_draw
	var folder: String = "res://production/qa/evidence/story-010/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(root.get_texture().get_image().save_png(folder + name + ".png") == OK, "Report fixture screenshot saves")


func _run() -> void:
	root.size = Vector2i(1280, 844)
	_view = EconomyScript.new() as KingdomReportEconomyView
	var fixture: Dictionary = _fixture()
	var original: String = JSON.stringify(fixture)
	_view.set_economy(fixture)
	_build_shell()
	await _settle()
	_check(JSON.stringify(fixture) == original, "Economy view leaves the original DTO unchanged")
	_check(_view._resource_rows.size() == 5, "Each resource receives an independent presentation row")
	_check(_view._resource_rows.food.loot.text == "缴获 1,200", "Loot uses the report's explicit resource amount")
	_check(_view._resource_rows.food.received.text == "实际入库 1,000", "Confirmed income comes from receipts rather than loot")
	_check(_view._status_label.text == "已确认入库 · 数额以凭据为准", "Confirmed receipts do not imply every private battle waited for a return march")
	_check(_view._resource_rows.food.replacement.text == "补兵预算 1,200", "Replacement budget uses the supplied canonical resource amount")
	_check(_view._resource_rows.gold.treatment.text == "治疗预算 75", "Historical treatment budget retains its own resource amount")
	_check(_view._resource_rows.food.net.text == "预计余额 -200", "A budget shortfall carries a visible minus sign")
	_check(_view._resource_rows.food.net.get_theme_color("font_color") == KingdomReportEconomyView.LOSS_COLOR, "A budget shortfall also uses the loss color")
	_check(_view._resource_rows.stone.net.text == "预计余额 +20", "Positive resource balance remains separate with its own sign")
	_check(_text(_view).contains("尚未扣款") and _text(_view).contains("各资源分别计算"), "Budget presentation discloses estimate and per-resource accounting")
	_check(_text(_view).contains("补兵需征用人口 30") and _text(_view).contains("本战 5 名伤兵"), "Replacement population and historical wounded count retain distinct meanings")
	_check(not _text(_view).contains("医馆"), "Historical treatment estimates do not invent a hospital prerequisite")
	_check(_button_count(_view) == 0, "The economy component cannot send treatment or game commands")
	fixture.received.food = 999999
	_check(_view._resource_rows.food.received.text == "实际入库 1,000", "Later caller mutations cannot silently change displayed receipts")
	fixture = _fixture()
	for width: int in [1280, 390]:
		root.size = Vector2i(width, 844)
		_view.set_economy(fixture)
		await _settle()
		_check(_view.size.x <= width - 32, "Economy view fits the actual %d-pixel SceneTree viewport" % width)
		_check(_view._cards.columns == (2 if width == 1280 else 1), "Resource cards adapt to a %d-pixel viewport" % width)
		for id: String in KingdomReportEconomyView.RESOURCE_IDS:
			_check(_view._resource_rows[id].name.get_line_count() == 1, "%s heading remains horizontal in a %d-pixel viewport" % [id, width])
		_check_horizontal_bounds(_view, _scroll.get_global_rect().end.x)
		await _capture("01-report-economy-delivered-fixture-%d" % width)
	var pending: Dictionary = _fixture()
	pending.status = "pending"
	pending.received = {"food": 5000}
	pending.net.resources = {"food": 0, "wood": -110, "stone": 20, "iron": -70, "gold": -125}
	pending.notes = ["Fixture：返程尚未抵达；入库以返回后的凭据为准。"]
	_view.set_economy(pending)
	await _settle()
	_check(_view._resource_rows.food.received.text == "实际入库 尚未入库", "Pending return never presents tentative resources as stored")
	_check(_view._status_label.text.contains("待返程"), "Pending delivery has an explicit status")
	_check(not _text(_view).contains("5,000"), "A pending report does not expose a stale confirmed-looking receipt")
	await _capture("02-report-economy-pending-fixture-390")
	pending.status = "retained"
	_view.set_economy(pending)
	_check(_view._resource_rows.food.received.text == "实际入库 未交付", "Retained cargo is distinct from city storage")
	var unknown: Dictionary = _fixture()
	unknown.status = "unknown"
	unknown.received = null
	_view.set_economy(unknown)
	_check(_view._resource_rows.food.received.text == "实际入库 未确认", "Missing receipt evidence remains unknown rather than being invented")
	_check(_view._status_label.text.contains("缺少入库凭据"), "Older reports explain missing receipt evidence")
	unknown.status = "delivered"
	_view.set_economy(unknown)
	_check(_view._resource_rows.food.received.text == "实际入库 未确认", "Delivery status alone is insufficient to reconstruct stored amounts")
	unknown.received = {}
	_view.set_economy(unknown)
	_check(_view._resource_rows.food.received.text == "实际入库 0", "An explicit empty delivered receipt confirms zero resources")
	var stale_treatment: Dictionary = _fixture()
	stale_treatment.treatment.available = false
	stale_treatment.treatment.reason = "本战伤兵已治疗，当前伤兵池没有可治疗士兵。"
	_view.set_economy(stale_treatment)
	_check(_view._resource_rows.gold.treatment.text == "治疗预算 75", "Historical treatment budget is not recalculated from today's wounded pool")
	_check(_text(_view).contains("并非仍需支付") and _text(_view).contains("当前伤兵池另算"), "Historical estimates explain that healing may already be complete")
	_check(_text(_view).contains("本战伤兵已治疗") and _text(_view).contains("不能据此确认当前可治疗数量"), "Unavailable current treatment retains the bridge reason and safe wording")
	var lost: Dictionary = _fixture()
	lost.status = "lost"
	lost.scope = "defenders-total"
	lost.received = {}
	lost.net.resources = {"food": -2400, "wood": -290, "stone": -20, "iron": -90, "gold": -125}
	lost.notes = ["Fixture：守方合计含盟友，恢复预算不能分摊本人。"]
	_view.set_economy(lost)
	await _settle()
	_check(_view._resource_rows.food.loot.text == "敌军掠走 1,200", "Defender report labels enemy loot as a loss")
	_check(_view._resource_rows.food.received.text == "实际入库 0", "Defender receipt confirms no resource income")
	_check(_text(_view).contains("守方合计含盟友") and _text(_view).contains("不能分摊本人"), "Aggregate defender budgets are not attributed to one player")
	_check(not _text(_view).contains("净利润"), "Estimated recovery balance is not called real profit")
	await _capture("03-report-economy-defenders-fixture-390")
	_scroll.scroll_vertical = int(_view.size.y)
	await _settle()
	await _capture("04-report-economy-defenders-notes-fixture-390")
	_view.set_economy({"basis": "current-canonical-prices", "status": "unknown"})
	_check(_view._resource_rows.food.loot.text == "缴获 未确认", "Missing loot does not manufacture a zero amount")
	_check(_view._resource_rows.food.replacement.text == "补兵预算 未提供", "Missing replacement budget is visible")
	_check(_view._resource_rows.food.treatment.text == "治疗预算 未提供", "Missing treatment budget is visible")
	_check(_view._resource_rows.food.net.text == "预计余额 未提供", "Missing net budget is not recomputed in the UI")
	_check(not _text(_view).contains("Fixture：守方"), "Replacing a report removes stale notes immediately")
	_view.set_economy({"basis": "unsupported", "status": "delivered", "received": {"food": "bad"}, "replacement": [], "treatment": "bad", "net": {"resources": {"food": NAN}}, "notes": [false, "有效说明"]})
	_check(_view._resource_rows.food.received.text == "实际入库 未确认", "Malformed receipt data cannot become a confirmed number")
	_check(_view._resource_rows.food.replacement.text.contains("来源未确认"), "Unknown price basis cannot be called a canonical budget")
	_check(_text(_view).contains("有效说明"), "Malformed optional notes do not hide valid text notes")
	_view.set_economy({})
	_check(_view._resource_rows.is_empty() and _text(_view).contains("缺少收支记录"), "No economy DTO produces a compact explicit fallback")
	_check(_button_count(_view) == 0, "All fallback variants remain read-only")
	await _settle()
	print("REPORT_ECONOMY_TEST_CHECKS=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures else 0)
