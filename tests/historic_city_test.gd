extends SceneTree

const CityView: GDScript = preload("res://src/city_view.gd")

var _checks: int = 0
var _failures: int = 0
var _built_events: Array[String] = []
var _empty_events: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _fresh_fixture() -> Dictionary:
	var file: FileAccess = FileAccess.open("res://tests/fixtures/godot-view.json", FileAccess.READ)
	return (JSON.parse_string(file.get_as_text()) as Dictionary).get("view", {})

func _developed_fixture() -> Dictionary:
	var view: Dictionary = _fresh_fixture().duplicate(true)
	var types: Array[String] = ["house", "house", "house", "house", "house", "house", "house", "house", "barracks", "barracks", "drill", "stable", "beacon", "wall", "barracks", "drill", "market", "inn", "post", "tavern", "market", "inn", "post", "market", "warehouse", "warehouse", "smith", "workshop", "academy", "embassy", "warehouse", "stable"]
	var index: int = 0
	for slot: Dictionary in view.buildingSlots:
		if bool(slot.reserved) or int(slot.site) == 14:
			continue
		var id: String = types[index % types.size()]
		index += 1
		slot.id = id
		slot.level = 1 + index % 4
		view.buildings.append({"id": id, "site": int(slot.site), "name": id, "level": int(slot.level), "queue": null})
	return view

func _check_geometry(city: Control, width: float) -> void:
	city.custom_minimum_size.y = city.recommended_height(width)
	city.size = Vector2(width, city.recommended_height(width))
	city._rebuild_layout()
	var keys: Array = city._hit_records.keys()
	for key: Variant in keys:
		var record: Dictionary = city._hit_records[key]
		var rect: Rect2 = city._hit_boxes[key]
		_check(rect.size.x >= 44.0 and rect.size.y >= 44.0, "Each canonical site needs a >=44px phone target: %s at %.0fpx" % [str(key), width])
		_check(Rect2(Vector2.ZERO, city.size).encloses(rect), "Canonical site must stay inside the scene: %s" % key)
		_check(city._building_at(rect.get_center()) == str(key), "A parcel center must resolve its exact site: %s" % key)
		_check(record.site >= 0 and not record.reserved, "Only actual nonreserved sites may be interactive")
	for a: int in range(keys.size()):
		for b: int in range(a + 1, keys.size()):
			_check(not (city._hit_boxes[keys[a]] as Rect2).intersects(city._hit_boxes[keys[b]]), "Repeated buildings and empty lots must not share hit geometry: %s / %s" % [keys[a], keys[b]])

func _capture_folder() -> String:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = "res://production/qa/evidence/story-016/"
	for index: int in range(arguments.size()):
		if arguments[index].begins_with("--capture-folder="):
			folder = arguments[index].trim_prefix("--capture-folder=")
		elif arguments[index] == "--capture-folder" and index + 1 < arguments.size():
			folder = arguments[index + 1]
	return folder.trim_suffix("/") + "/"

func _capture(name: String, city: Control) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	root.size = Vector2i(city.size)
	city.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var folder: String = _capture_folder()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(root.get_texture().get_image().save_png(folder + "rts-city-%s.png" % name) == OK, "Native city capture must be saved to the selected evidence folder")

func _touch(city: Control, point: Vector2, pressed: bool, index: int = 0, canceled: bool = false) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	event.index = index
	event.canceled = canceled
	city._gui_input(event)

func _drag(city: Control, point: Vector2, index: int = 0) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.position = point
	event.index = index
	city._gui_input(event)

func _check_touch_gestures(city: Control, fresh: Dictionary) -> void:
	var point: Vector2 = (city._hit_boxes["empty#0"] as Rect2).get_center()
	var built_before: int = _built_events.size()
	var empty_before: int = _empty_events.size()
	_check(city.mouse_filter == Control.MOUSE_FILTER_PASS, "Scene must allow unaccepted touch/drag events to reach the parent scroll container")
	_check(InputEvent.DEVICE_ID_EMULATION == -1, "Use the documented emulation device id, not a physical mouse id")
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.position = point
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_LEFT
	city._gui_input(mouse)
	_check(_built_events.size() == built_before and _empty_events.size() == empty_before, "Emulated mouse press must not select before the real touch gesture is known")
	_touch(city, point, true)
	_check(_empty_events.size() == empty_before, "Finger-down must not activate a parcel before it can become a scroll gesture")
	_drag(city, point + Vector2(3.0, 4.0))
	_touch(city, point + Vector2(3.0, 4.0), false)
	_check(_empty_events.size() == empty_before + 1 and _empty_events.back() == 0, "A released tap with small travel must activate the original true empty site exactly once")
	city._gui_input(mouse)
	_check(_empty_events.size() == empty_before + 1, "Mouse synthesized after touch must not open a second selection")
	var count: int = _empty_events.size()
	_touch(city, point, true)
	_drag(city, point + Vector2(0.0, 40.0))
	_drag(city, point)
	_touch(city, point, false)
	_check(_empty_events.size() == count and city._touch_index == -1, "A scroll drag must never activate even when its finger returns to the original parcel")
	_touch(city, point, true, 3)
	_touch(city, point, false, 3, true)
	_check(_empty_events.size() == count and city._touch_index == -1, "A canceled touch must clear its gesture without activating")
	_touch(city, point, false, 3)
	_check(_empty_events.size() == count, "A release without a tracked press must not select")
	_touch(city, point, true, 2)
	_touch(city, point, false, 5)
	_check(city._touch_index == 2 and _empty_events.size() == count, "Another finger's release must not finish the tracked gesture")
	_touch(city, point, true, 5)
	_touch(city, point, false, 2)
	_check(_empty_events.size() == count and city._touch_index == -1, "A multiple-finger gesture must not become a parcel tap")
	_touch(city, point, true, 4)
	_touch(city, point + Vector2(0.0, 15.0), false, 4)
	_check(_empty_events.size() == count, "Large release travel must reject taps even when intermediate drag events were absent")
	_touch(city, point, true)
	var other: Dictionary = fresh.duplicate(true)
	other.city.id = "gesture_other_city"
	city.set_city(other)
	_touch(city, point, false)
	_check(_empty_events.size() == count and city._touch_index == -1, "Changing source city during a gesture must cancel the pending tap")
	city.set_city(fresh)
	mouse.device = InputEvent.DEVICE_ID_MOUSE
	city._gui_input(mouse)
	_check(_empty_events.size() == count + 1 and city.selected_site() == 0, "A physical desktop mouse press must retain direct selection")

func _run() -> void:
	var city: Control = CityView.new()
	root.add_child(city)
	city.custom_minimum_size.y = city.recommended_height(900.0)
	city.size = Vector2(900.0, city.recommended_height(900.0))
	city.building_selected.connect(func(id: String) -> void: _built_events.append(id))
	city.empty_site_selected.connect(func(site: int) -> void: _empty_events.append(site))
	var fresh: Dictionary = _fresh_fixture()
	var original: Dictionary = fresh.duplicate(true)
	city.set_city(fresh)
	_check(city._hit_records.size() == 33, "All 33 canonical nonreserved sites must be selectable before the first draw")
	_check(city._hit_records.has("hall#14"), "The grid must retain the actual canonical hall site14")
	_check(city._hit_records["hall#14"].district == "official", "The hall retains its official identity without being sorted to another cell")
	var built_count: int = 0
	var empty_count: int = 0
	for record: Dictionary in city._hit_records.values():
		if bool(record.empty):
			empty_count += 1
		else:
			built_count += 1
	_check(built_count == 1 and empty_count == 32, "A fresh city must draw one real hall and 32 bare sites, not build-option ghost buildings")
	for reserved_site: int in [15, 20, 21]:
		_check(not city._hit_records.values().any(func(row: Dictionary) -> bool: return int(row.site) == reserved_site), "Reserved canonical site%d must never be an empty/built action" % reserved_site)
		var garden: Dictionary = {}
		for row: Dictionary in city._lots:
			if int(row.site) == reserved_site:
				garden = row
		_check(not garden.is_empty() and city._building_at((garden.rect as Rect2).get_center()).is_empty(), "Reserved circulation land must not steal a neighboring hit")
	var empty_rect: Rect2 = city._hit_boxes["empty#0"]
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = empty_rect.get_center()
	city._gui_input(click)
	_check(_empty_events == [0] and _built_events.is_empty(), "Empty plot click must emit the true site0 only")
	_check(city.selected_site() == 0, "Empty selection must expose the exact canonical site")
	city.select_building("hall", 14)
	_check(city.selected_site() == 14, "Programmatic building selection must expose canonical site14")
	city._activate_building("hall#14")
	_check(_built_events == ["hall"] and _empty_events == [0], "Constructed selection must emit only its real building id")
	var layout: Dictionary = city._hit_boxes.duplicate(true)
	var reordered: Dictionary = fresh.duplicate(true)
	reordered.buildingSlots.reverse()
	reordered.buildings.reverse()
	city.set_city(reordered)
	_check(city._hit_boxes == layout and city.selected_site() == 14, "Polling/reordering the same city must not move plots or lose selected site")
	_check(fresh == original, "Rendering and layout must not mutate the bridge DTO")
	_check_geometry(city, 390.0)
	await _capture("fresh-phone", city)
	_check_geometry(city, 358.0)
	_check_touch_gestures(city, fresh)
	var developed: Dictionary = _developed_fixture()
	city.set_city(developed)
	_check(city._hit_records.size() == 33, "All 33 real developed sites must remain selectable, including repeated IDs")
	var seen: Dictionary = {}
	for row: Dictionary in developed.buildings:
		var key: String = "%s#%d" % [str(row.id), int(row.site)]
		_check(city._hit_records.has(key), "Every actual DTO building must have its own identity: %s" % key)
		seen[key] = true
	_check(seen.size() == city._hit_records.size(), "No extra options or made-up buildings may be introduced")
	var first_house: Dictionary = {}
	var second_house: Dictionary = {}
	for row: Dictionary in city._hit_records.values():
		if row.id == "house":
			if first_house.is_empty(): first_house = row
			elif second_house.is_empty(): second_house = row
	_check(not (first_house.rect as Rect2).intersects(second_house.rect), "Repeated houses must have distinct actual footprints")
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = (second_house.rect as Rect2).get_center()
	var selected_before_touch: int = city.selected_site()
	city._gui_input(touch)
	_check(city.selected_site() == selected_before_touch, "A building touch press must wait for release to distinguish scrolling")
	touch.pressed = false
	city._gui_input(touch)
	_check(city.selected_site() == int(second_house.site) and _built_events.back() == "house", "Released tap on the second repeated house must retain its exact site")
	_check_geometry(city, 390.0)
	await _capture("developed-phone", city)
	_check_geometry(city, 900.0)
	await _capture("developed-desktop", city)
	var queued: Dictionary = fresh.duplicate(true)
	queued.buildings.append({"id": "house", "name": "民房", "site": 0, "level": 0, "queue": {"site": 0, "level": 1}})
	queued.buildingSlots[0].id = "house"
	city.set_city(fresh)
	var chosen_lot: Rect2 = city._hit_boxes["empty#0"]
	city.set_city(queued)
	_check(city._hit_boxes["house#0"] == chosen_lot, "Building on chosen vacant site must preserve its physical parcel")
	var recreated: Control = CityView.new()
	root.add_child(recreated)
	recreated.size = city.size
	recreated.set_city(queued)
	_check(recreated._hit_boxes["house#0"] == chosen_lot, "Scene recreation must retain canonical site-to-parcel projection")
	recreated.queue_free()
	_check(city._hit_records.has("house#0") and not city._hit_records.has("empty#0"), "Real level0 construction must have an actual building hit, not vacant state")
	_check(int(city._hit_records["house#0"].level) == 0, "Construction foundation must preserve the canonical zero level")
	city.select_building("house", 0)
	var other_city: Dictionary = queued.duplicate(true)
	other_city.city.id = "other_city"
	city.set_city(other_city)
	_check(city.selected_site() == -1 and city._selected.is_empty(), "Changing source city must clear stale site selection")
	var incomplete: Dictionary = fresh.duplicate(true)
	incomplete.buildingSlots[0].id = "house"
	city.set_city(incomplete)
	_check(not city._hit_records.has("house#0") and not city._hit_records.has("empty#0"), "An occupied slot without a building DTO must not fabricate a building or a vacant action")
	await process_frame
	city.queue_free()
	await process_frame
	print("Commanding historical city: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
