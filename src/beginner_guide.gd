class_name KingdomBeginnerGuide
extends PanelContainer

## Guided navigation uses live rule projections; no simulated completion or rewards.
signal navigate_requested(route: String, target: String)
signal reward_requested
signal details_requested
var _title: Label
var _body: Label
var _action: Button
var _route: Dictionary = {}
var _claim: bool = false

func _ready() -> void:
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	margin.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color("f3d28f"))
	column.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 14)
	column.add_child(_body)
	var row: HFlowContainer = HFlowContainer.new()
	column.add_child(row)
	_action = Button.new()
	_action.custom_minimum_size = Vector2(180, 40)
	_action.theme_type_variation = "PrimaryButton"
	row.add_child(_action)
	_action.pressed.connect(func() -> void:
		if _claim:
			reward_requested.emit()
		else:
			navigate_requested.emit(str(_route.get("route", "growth")), str(_route.get("target", ""))))
	var detail: Button = Button.new()
	detail.text = "完整步骤与缺口"
	detail.custom_minimum_size.y = 40
	row.add_child(detail)
	detail.pressed.connect(func() -> void: details_requested.emit())

func update_view(view: Dictionary, connected: bool, pending: bool) -> void:
	if not is_instance_valid(_title):
		return
	var growth: Dictionary = view.get("growth", {})
	var step: Dictionary = growth.get("current", {}) if growth.get("current") is Dictionary else {}
	var objective: Dictionary = view.get("objective", {})
	_claim = bool(objective.get("ready", false))
	_route = step.get("navigate", {}).duplicate(true)
	_title.text = "新手指导 · " + (str(objective.get("title", "领取任务奖励")) if _claim else str(step.get("title", "正在读取城池")))
	var message: String = "建设 → 研究 → 募兵 → 出征 → 返城。每步完成后，这里会自动提示下一步。"
	if _claim:
		message = "任务已达成。先领取奖励，再用所得物资继续建设。"
	elif not step.is_empty():
		message = str(step.get("description", ""))
		if not str(step.get("reason", "")).is_empty():
			message += "\n" + str(step.reason)
		var gaps: Array[String] = []
		for gap: Dictionary in growth.get("gaps", []):
			if float(gap.get("missing", 0)) > 0 and gaps.size() < 3:
				gaps.append("%s还差%d%s" % [gap.get("label", "条件"), ceili(float(gap.missing)), gap.get("unit", "")])
		if not gaps.is_empty():
			message += "\n" + " · ".join(gaps)
	_body.text = message
	_action.text = "领取当前任务奖励" if _claim else str(_route.get("label", "查看下一步"))
	_action.disabled = not connected or pending or (not _claim and step.is_empty())
