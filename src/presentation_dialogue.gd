class_name KingdomPresentationDialogue extends AcceptDialog

var intro: DialogueResource
var audio: KingdomPresentationAudio
var _body: VBoxContainer
var _busy: bool = false
var _generation: int = 0

func _ready() -> void:
	intro = load("res://data/dialogue/intro.dialogue") as DialogueResource
	title = "新手引导"
	ok_button_text = "关闭"
	min_size = Vector2i(280, 220)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)
	visibility_changed.connect(func() -> void:
		if not visible:
			_generation += 1
			_busy = false)
	get_tree().root.size_changed.connect(_fit_window)

func start() -> void:
	_generation += 1
	_busy = false
	_fit_window()
	popup_centered(size)
	advance("start")

func advance(cue: String) -> void:
	if _busy or not visible:
		return
	_busy = true
	var generation: int = _generation
	var line: DialogueLine = await intro.get_next_dialogue_line(cue)
	if generation != _generation or not visible:
		return
	_busy = false
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	if line == null:
		hide()
		return
	var label: Label = Label.new()
	label.text = line.character + "：\n" + line.text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)
	for response: DialogueResponse in line.responses:
		if response.is_allowed:
			_add_choice(response.text, response.next_id)
	if line.responses.is_empty():
		_add_choice("继续", line.next_id)
	var first: Button = _body.get_child(1) as Button if _body.get_child_count() > 1 else get_ok_button()
	first.grab_focus()

func _add_choice(text: String, cue: String) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.pressed.connect(func() -> void: audio.click(); advance(cue))
	_body.add_child(button)

func _fit_window() -> void:
	var viewport_size: Vector2 = get_tree().root.get_visible_rect().size
	size = Vector2i(int(minf(620.0, viewport_size.x - 24.0)), int(minf(340.0, viewport_size.y - 48.0)))
	if visible:
		position = Vector2i((viewport_size - Vector2(size)) / 2.0)
