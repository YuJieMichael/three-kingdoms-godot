extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _selected: Array[int] = []
var _suburb: KingdomSuburbView

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

func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> InputEventScreenTouch:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	return event

func _drag(index: int, position: Vector2) -> InputEventScreenDrag:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = position
	return event

func _fixture() -> Dictionary:
	return {"city": {"id": "capital", "name": "主城"}, "plots": [
		{"index": 2, "id": "farm", "name": "农田", "level": 7, "unlocked": true, "queue": null},
		{"index": 11, "id": "lumber", "name": "林场", "level": 4, "unlocked": true, "queue": null},
		{"index": 15, "id": "quarry", "name": "采石场", "level": 3, "unlocked": true, "queue": null},
		{"index": 21, "id": "mine", "name": "铁矿", "level": 2, "unlocked": true, "queue": null},
		{"index": 30, "id": null, "name": "空地", "level": 0, "unlocked": true, "queue": null},
		{"index": 35, "id": "farm", "name": "农田", "level": 9, "unlocked": false, "queue": null}]}

func _large_fixture(unlocked_count: int) -> Dictionary:
	var plots: Array[Dictionary] = []
	var kinds: Array[String] = ["farm", "lumber", "quarry", "mine"]
	var names: Array[String] = ["农田", "林场", "采石场", "铁矿"]
	for i: int in range(39):
		plots.append({"index": i, "id": kinds[i % 4], "name": names[i % 4], "level": 4, "unlocked": i < unlocked_count, "queue": null})
	return {"city": {"id": "large", "name": "主城"}, "plots": plots}

func _scene_fixture() -> Dictionary:
	var view: Dictionary = _large_fixture(12)
	view.city.id = "capture_city"
	for i: int in range(8):
		view.plots[i].id = "farm"
		view.plots[i].name = "农田"
	view.plots[8].id = "lumber"
	view.plots[8].name = "林场"
	view.plots[9].id = "quarry"
	view.plots[9].name = "采石场"
	view.plots[10].id = "mine"
	view.plots[10].name = "铁矿"
	view.plots[11].id = null
	view.plots[11].name = "空地"
	view.plots[11].level = 0
	return view

func _check_geometry(width: float) -> void:
	_check(_suburb._hit_boxes.size() == 5, "Only five actual unlocked parcels may have hit areas.")
	var keys: Array = _suburb._hit_boxes.keys()
	for i: int in range(keys.size()):
		var rect: Rect2 = _suburb._hit_boxes[keys[i]]
		_check(rect.size.x >= 44.0 and rect.size.y >= 44.0, "Parcel %d needs a phone-size touch target." % int(keys[i]))
		_check(rect.position.x >= 0.0 and rect.end.x <= width and rect.position.y >= 65.0 and rect.end.y <= _suburb.size.y - 45.0, "Parcel %d must fit inside the scene." % int(keys[i]))
		_check(_suburb._plot_at(rect.get_center()) == int(keys[i]), "Hit testing must return the actual sparse canonical parcel index.")
		for j: int in range(i + 1, keys.size()):
			_check(not rect.intersects(_suburb._hit_boxes[keys[j]]), "Parcel hit areas must not overlap on a narrow phone.")

func _run() -> void:
	root.size = Vector2i(390, 844)
	var host: Control = Control.new()
	host.size = Vector2(390, 844)
	root.add_child(host)
	_suburb = load("res://src/suburb_view.gd").new() as KingdomSuburbView
	host.add_child(_suburb)
	_suburb.plot_selected.connect(func(index: int) -> void: _selected.append(index))
	_suburb.set_view(_fixture())
	_suburb.size = Vector2(302, _suburb.custom_minimum_size.y)
	await _settle()
	_check_geometry(302)
	_check(not _suburb._hit_boxes.has(35) and not _suburb._hit_records.has(35), "A locked populated parcel must never appear as an active site or action target.")
	_check(_suburb._hit_records[30].id == null, "Unbuilt land retains its actual null identity.")
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.position = (_suburb._hit_boxes[30] as Rect2).get_center()
	touch.pressed = true
	_suburb._gui_input(touch)
	_check(_selected.is_empty() and _suburb.selected_plot() == -1, "A touch press must wait for tap recognition before opening parcel actions.")
	touch.pressed = false
	touch.position += Vector2(3, 2)
	_suburb._gui_input(touch)
	_check(_selected == [30] and _suburb.selected_plot() == 30, "A short released tap on unbuilt land selects its exact canonical index.")
	var touch_target: Vector2 = (_suburb._hit_boxes[11] as Rect2).get_center()
	_suburb._gui_input(_touch(1, touch_target, true))
	_suburb._gui_input(_drag(1, touch_target + Vector2(0, -55)))
	_suburb._gui_input(_touch(1, touch_target + Vector2(0, -55), false))
	_check(_selected == [30] and _suburb.selected_plot() == 30, "A scroll drag starting on a built parcel must never select it.")
	_suburb._gui_input(_touch(1, touch_target, true))
	_suburb._gui_input(_drag(1, touch_target + Vector2(8, 0)))
	_suburb._gui_input(_drag(1, touch_target))
	_suburb._gui_input(_touch(1, touch_target, false))
	_check(_selected == [30], "A gesture that travels out and back past the tap limit remains a drag.")
	var original_position: Vector2 = _suburb.position
	_suburb._gui_input(_touch(1, touch_target, true))
	for step: int in range(4):
		_suburb.position -= Vector2(0, 4)
		_suburb._gui_input(_drag(1, touch_target))
	_suburb._gui_input(_touch(1, touch_target, false))
	_suburb.position = original_position
	_check(_selected == [30], "Small drags accumulate in canvas coordinates even when parent scrolling keeps the finger at the same local parcel position.")
	_suburb._gui_input(_touch(1, touch_target, true))
	_suburb._gui_input(_touch(1, touch_target, false, true))
	_check(_selected == [30] and _suburb._touches.is_empty(), "A canceled touch clears the gesture without selecting a parcel.")
	_suburb._gui_input(_touch(1, touch_target, true))
	_suburb._gui_input(_touch(2, touch_target + Vector2(10, 0), true))
	_suburb._gui_input(_touch(2, touch_target + Vector2(10, 0), false))
	_suburb._gui_input(_touch(1, touch_target, false))
	_check(_selected == [30] and _suburb._touches.is_empty(), "A multiple-finger gesture cannot turn into a tap after one finger releases.")
	var emulated: InputEventMouseButton = InputEventMouseButton.new()
	emulated.position = touch_target
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	_suburb._gui_input(emulated)
	emulated.pressed = false
	_suburb._gui_input(emulated)
	_check(_selected == [30], "Godot compatibility mouse events from native touch must not open or duplicate parcel actions.")
	_suburb._gui_input(_touch(4, touch_target, true))
	var gesture_city: Dictionary = _fixture()
	gesture_city.city.id = "gesture_city"
	_suburb.set_view(gesture_city)
	await _settle()
	_suburb._gui_input(_touch(4, touch_target, false))
	_check(_selected == [30] and _suburb._touches.is_empty(), "Switching source city cancels an unfinished touch gesture.")
	_suburb.set_view(_fixture())
	await _settle()
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.position = (_suburb._hit_boxes[11] as Rect2).get_center()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	_suburb._gui_input(mouse)
	_check(_selected == [30, 11] and _suburb.selected_plot() == 11, "Mouse selection must identify a sparse resource parcel rather than its array position.")
	var positions: Dictionary = _suburb._site_positions.duplicate()
	var update: Dictionary = _fixture()
	update.plots[1].id = "farm"
	update.plots[1].name = "农田"
	update.plots[1].level = 1
	update.plots[1].queue = {"end": 1800000030000}
	update["res"] = {"food": 1001}
	update.plots.reverse()
	_suburb.set_view(update)
	await _settle()
	_check(_suburb.selected_plot() == 11, "Selection persists through polling, row reorder and a resource type replacement.")
	_check(_suburb._site_positions == positions, "A parcel's physical site remains stable through resource type and tick changes.")
	_check(_suburb._hit_records[11].id == "farm", "A stable site's displayed record updates to the canonical replacement type.")
	var recreated: KingdomSuburbView = load("res://src/suburb_view.gd").new() as KingdomSuburbView
	host.add_child(recreated)
	recreated.set_view(update)
	recreated.size = _suburb.size
	await _settle()
	_check(recreated._site_positions == positions, "Recreating the scene after a resource replacement preserves the same actual-index parcel locations.")
	recreated.queue_free()
	_suburb.select_plot(35)
	_check(_suburb.selected_plot() == -1, "Programmatic selection cannot make a locked parcel active.")
	_suburb.select_plot(2)
	update.plots[update.plots.size() - 1].unlocked = false
	_suburb.set_view(update)
	await _settle()
	_check(_suburb.selected_plot() == -1 and not _suburb._hit_boxes.has(2), "If the selected parcel becomes unavailable, its selection and action area clear.")
	_suburb.set_view(_fixture())
	_suburb.size = Vector2(680, 480)
	await _settle()
	_check_geometry(680)
	_check(_suburb._hit_records[11].id == "lumber" and _suburb._hit_records[15].id == "quarry" and _suburb._hit_records[21].id == "mine", "Fixed parcel geometry must preserve the actual current type for timber, stone and iron landscape details.")
	_suburb.select_plot(30)
	var other_city: Dictionary = _fixture()
	other_city.city.id = "other_city"
	_suburb.set_view(other_city)
	_check(_suburb.selected_plot() == -1, "A different city does not inherit a parcel selection from the previous city.")
	_suburb.set_view(_large_fixture(12))
	_suburb.size = Vector2(302, _suburb.custom_minimum_size.y)
	await _settle()
	_check(_suburb._capacity == 12 and _suburb._hit_boxes.size() == 12, "Thirty-nine DTO rows must allocate scene parcels only for the twelve currently unlocked sites.")
	_suburb.set_view(_large_fixture(39))
	_suburb.size = Vector2(302, _suburb.custom_minimum_size.y)
	await _settle()
	_check(_suburb._hit_boxes.size() == 39, "All actual unlocked sites remain individually selectable at the largest canonical parcel count.")
	var large_keys: Array = _suburb._hit_boxes.keys()
	for i: int in range(large_keys.size()):
		var rect: Rect2 = _suburb._hit_boxes[large_keys[i]]
		_check(rect.size.x >= 44.0 and rect.size.y >= 44.0, "Large parcel counts must retain phone touch targets.")
		_check(_suburb._plot_at(rect.get_center()) == int(large_keys[i]), "Large parcel layouts preserve exact canonical index mapping.")
		for j: int in range(i + 1, large_keys.size()):
			_check(not rect.intersects(_suburb._hit_boxes[large_keys[j]]), "All thirty-nine unlocked parcel touch targets must stay separate.")
	if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--capture"):
		_suburb.set_view(_scene_fixture())
		_suburb.select_plot(2)
		_suburb.size = Vector2(680, _suburb.recommended_minimum_height(680))
		_suburb.size = Vector2(680, _suburb.recommended_minimum_height(680))
		root.size = Vector2i(720, 560)
		await _settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://historic_suburb_desktop.png")
		_suburb.size = Vector2(302, _suburb.recommended_minimum_height(302))
		root.size = Vector2i(390, 720)
		await _settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://historic_suburb_phone.png")
		_suburb.set_view(_large_fixture(39))
		_suburb.size = Vector2(302, _suburb.recommended_minimum_height(302))
		root.size = Vector2i(390, 960)
		await _settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://historic_suburb_39_phone.png")
	print("historic_suburb_test: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
