class_name KingdomBattleReviewView
extends VBoxContainer

## Presentation of read-only bridge evidence. It never reconstructs combat.
var _review: Dictionary = {}


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)


func _ready() -> void:
	_render()


func set_review(review: Dictionary) -> void:
	# Unchanged polling snapshots must retain the same labels and layout.
	if review == _review:
		return
	_review = review.duplicate(true)
	if is_inside_tree():
		_render()


func _render() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_label(str(_review.get("title", "本战关键原因")), "SectionLabel")
	if _review.is_empty():
		_label("此战报没有战术证据记录；无法确认本战的关键交锋。", "MutedLabel")
		return
	_label("证据范围 · " + str(_review.get("scope", "未提供")), "MutedLabel")
	var findings: Variant = _review.get("findings", [])
	if findings is Array:
		for value: Variant in findings:
			if not value is Dictionary:
				continue
			var row: Dictionary = value
			var text: String = str(row.get("text", ""))
			if text.is_empty():
				continue
			var label: Label = _label(str(row.get("label", "记录")) + "\n" + text)
			match str(row.get("kind", "evidence")):
				"rule", "gap":
					label.theme_type_variation = "MutedLabel"
				"warning":
					label.add_theme_color_override("font_color", Color("efb77f"))
	var actions: Variant = _review.get("actions", [])
	if actions is Array and not actions.is_empty():
		_label("下次可尝试", "SectionLabel")
		for value: Variant in actions:
			if value is Dictionary and not str(value.get("label", "")).is_empty():
				_label("• " + str(value.label), "MutedLabel")


func _label(text: String, variation: String = "") -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
