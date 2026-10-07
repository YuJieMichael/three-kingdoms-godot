class_name KingdomNotificationCenter
extends Control

## Presentation only: short notices and a bounded, actor-scoped session history.
## It never consumes input, saves game data or infers unconfirmed rewards.
signal history_changed(count: int)

const HISTORY_LIMIT: int = 30
var _history: Array[Dictionary] = []
var _card: PanelContainer
var _heading: Label
var _message: Label
var _timer: Timer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.theme_type_variation = "SectionPanel"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(column)
	_heading = Label.new()
	_heading.theme_type_variation = "SectionLabel"
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_heading)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.max_lines_visible = 4
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_message)
	_card.hide()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.ignore_time_scale = true
	_timer.timeout.connect(_card.hide)
	add_child(_timer)
	resized.connect(_fit_notice)
	_card.resized.connect(_position_notice)
	_fit_notice()


func push_notice(message: String, error: bool = false) -> void:
	if message.strip_edges().is_empty():
		return
	_history.push_front({"message": message, "error": error, "time": Time.get_time_string_from_system()})
	while _history.size() > HISTORY_LIMIT:
		_history.pop_back()
	history_changed.emit(_history.size())
	_heading.text = "请核对操作状态 · 消息中查看详情" if error else "操作提示"
	_heading.add_theme_color_override("font_color", Color("edb68f") if error else Color("d9bd7d"))
	_message.text = message
	_card.show()
	_fit_notice()
	_timer.start(7.0 if error else 5.0)
	var feedback: Node = get_tree().get_first_node_in_group("ui_feedback")
	if feedback != null and feedback.has_method("notice"):
		feedback.notice(_card)


func records() -> Array[Dictionary]:
	return _history.duplicate(true)


func clear_context() -> void:
	_history.clear()
	if is_instance_valid(_timer):
		_timer.stop()
	if is_instance_valid(_card):
		_card.hide()
		_message.text = ""
	history_changed.emit(0)


func _fit_notice() -> void:
	if not is_instance_valid(_card):
		return
	var width: float = maxf(1.0, minf(460.0, size.x - 24.0))
	_card.custom_minimum_size.x = width
	_card.size.x = width
	_card.reset_size()
	_position_notice()


func _position_notice() -> void:
	if not is_instance_valid(_card):
		return
	# Leave the bottom navigation and status controls available on narrow screens.
	var bottom_space: float = 164.0 if size.x < 760.0 else 96.0
	_card.position = Vector2(maxf(12.0, size.x - _card.size.x - 12.0), maxf(12.0, size.y - _card.size.y - bottom_space))
