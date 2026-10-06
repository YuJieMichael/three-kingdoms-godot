extends SceneTree

const MAP_SCRIPT: Script = preload("res://src/world_map.gd")
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_camera_bounds()
	_test_zoom_anchor()
	_test_march_clock()
	_test_visible_world_selection()
	await _test_render_loop()
	print("World map mathematical checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)


func _assert(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _test_camera_bounds() -> void:
	var bounded: Vector2 = MAP_SCRIPT.clamp_camera(Vector2(-20, 200), Vector2(640, 480), Vector2(64, 64), 64.0)
	_assert(bounded.is_equal_approx(Vector2(5, 60.25)), "The camera must clamp to map bounds using actual viewport size.")
	var overview: Vector2 = MAP_SCRIPT.clamp_camera(Vector2(-20, 200), Vector2(1600, 1000), Vector2(64, 64), 10.0)
	_assert(overview.is_equal_approx(Vector2(32, 32)), "A viewport larger than the map must center the map on both axes.")
	var one_large_axis: Vector2 = MAP_SCRIPT.clamp_camera(Vector2(-20, 50), Vector2(1000, 300), Vector2(64, 64), 10.0)
	_assert(one_large_axis.is_equal_approx(Vector2(32, 49)), "Clamping must work independently on each axis.")


func _test_zoom_anchor() -> void:
	var camera: Vector2 = Vector2(32.5, 30.5)
	var viewport: Vector2 = Vector2(1000, 700)
	var anchor: Vector2 = Vector2(740, 220)
	var before_pixels: float = 51.2
	var after_pixels: float = 96.0
	var anchor_before: Vector2 = camera + (anchor - viewport * 0.5) / before_pixels
	var next_camera: Vector2 = MAP_SCRIPT.anchored_camera(camera, anchor, viewport, before_pixels, after_pixels)
	var anchor_after: Vector2 = next_camera + (anchor - viewport * 0.5) / after_pixels
	_assert(anchor_before.is_equal_approx(anchor_after), "Wheel/pinch zoom must retain the world location under its anchor.")
	_assert(MAP_SCRIPT.anchored_camera(camera, viewport * 0.5, viewport, 50.0, 100.0).is_equal_approx(camera), "Zooming at the viewport center must not move the camera.")


func _test_march_clock() -> void:
	var march: Dictionary = {"from": {"x": 10, "y": 20}, "to": {"x": 30, "y": 40}, "start": 1000, "arrive": 5000}
	_assert(is_equal_approx(MAP_SCRIPT.march_fraction(march, 0.0), 0.0), "Future departures remain at their origin.")
	_assert(is_equal_approx(MAP_SCRIPT.march_fraction(march, 3000.0), 0.5), "Half the marching time means half the visual distance.")
	_assert(MAP_SCRIPT.march_world_position(march, 3000.0).is_equal_approx(Vector2(20.5, 30.5)), "March interpolation must use tile centers.")
	_assert(MAP_SCRIPT.march_world_position(march, 6000.0).is_equal_approx(Vector2(30.5, 40.5)), "Late frames must stop at the destination.")
	_assert(is_equal_approx(MAP_SCRIPT.march_fraction({"start": 100, "arrive": 100}, 100.0), 1.0), "Zero-length travel must not divide by zero.")
	_assert(is_equal_approx(MAP_SCRIPT.march_fraction({"start": 100, "arrive": null, "status": "stationed"}, 100.0), 1.0), "Stationed troops use a null arrival timestamp and must stay at their destination.")
	_assert(MAP_SCRIPT.format_eta(59.1) == "1分00秒", "ETA rounds up seconds without losing the minute carry.")
	_assert(MAP_SCRIPT.format_eta(-10.0) == "0秒", "ETA never renders negative time.")


func _test_visible_world_selection() -> void:
	var map: Variant = MAP_SCRIPT.new()
	map.size = Vector2(800, 600)
	map.set_world({"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [{"id": "home", "x": 32, "y": 32, "name": "主城", "kind": "home", "owned": true}], "marches": []})
	map.focus_home()
	_assert(map.selected_tile.get("id", "") == "home", "Home focus must find the DTO tile without creating a different world.")
	var sample: Vector2 = Vector2(33.25, 30.75)
	_assert(map.screen_to_world(map.world_to_screen(sample)).is_equal_approx(sample), "Screen/world transforms must round trip at the same zoom.")
	map.focus_tile(-20, 900)
	_assert(int(map.selected_tile.get("x", -1)) == 0 and int(map.selected_tile.get("y", -1)) == 63, "Focus requests outside the save world must clamp safely.")
	map.set_filter("unknown")
	_assert(map.filter_kind == "all", "Unknown filters should recover to a usable all view.")
	map.focus_home()
	var camera_before: Vector2 = map.camera_center
	map._begin_pointer(Vector2(400, 300))
	map._move_pointer(Vector2(464, 300))
	_assert(is_equal_approx(map.camera_center.x, camera_before.x - 64.0 / map.cell_pixels()), "Dragging must change the camera during pointer movement, not on release.")
	var received: Array = []
	map.tile_selected.connect(func(tile: Dictionary) -> void: received.append(tile))
	map._end_pointer(Vector2(464, 300))
	_assert(received.is_empty(), "Releasing a drag must not select or activate a map tile.")
	map._begin_pointer(Vector2(400, 300))
	map._end_pointer(Vector2(400, 300))
	_assert(received.size() == 1, "A short tap must emit one tile selection.")
	map._touches = {0: Vector2(200, 200), 1: Vector2(400, 200)}
	map._begin_pinch()
	var pinch_anchor: Vector2 = map.screen_to_world(Vector2(300, 200))
	map._touches = {0: Vector2(180, 220), 1: Vector2(580, 220)}
	map._update_pinch()
	_assert(map.screen_to_world(Vector2(380, 220)).is_equal_approx(pinch_anchor), "Pinch zoom must follow the moving midpoint while retaining its world anchor.")
	_assert(is_equal_approx(map.zoom, 1.60), "Two fingers doubling their distance must double the zoom.")
	map._touches.clear()
	map.set_world({"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [{"id": "hidden-future", "x": 32, "y": 32, "hidden": true, "selectable": false}], "marches": []})
	map.focus_home()
	map._select_at(map.world_to_screen(Vector2(32.5, 32.5)))
	_assert(received.size() == 1, "Future hidden task locations must not produce actionable selections.")
	map.free()


func _test_render_loop() -> void:
	var map: Variant = MAP_SCRIPT.new()
	var draws: Array = [0]
	map.draw.connect(func() -> void: draws[0] += 1)
	root.add_child(map)
	map.size = Vector2(960, 600)
	var now: float = Time.get_unix_time_from_system() * 1000.0
	map.set_world({"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [
		{"id": "home", "x": 32, "y": 32, "name": "青溪城", "kind": "city", "owned": true},
		{"id": "camp", "x": 34, "y": 31, "name": "黄巾营寨", "kind": "landmark", "terrain": "camp"},
		{"id": "wood", "x": 33, "y": 33, "name": "青竹林", "kind": "wild", "terrain": "forest"},
		{"id": "mountain", "x": 35, "y": 32, "name": "白石隘口", "kind": "wild", "terrain": "mountain"}
	], "marches": [
		{"id": "moving", "label": "林默部队", "from": {"x": 32, "y": 32}, "to": {"x": 35, "y": 32}, "start": now - 20000, "arrive": now + 20000, "status": "march"},
		{"id": "garrison", "label": "驻扎部队", "from": {"x": 33, "y": 33}, "to": {"x": 33, "y": 33}, "start": now, "arrive": null, "status": "stationed"}
	]})
	map.focus_home()
	await process_frame
	await process_frame
	map._zoom_at(Vector2(480, 300), 0.20)
	await process_frame
	await process_frame
	map._zoom_at(Vector2(480, 300), 1.30)
	map.set_filter("resources")
	await process_frame
	await process_frame
	_assert(int(draws[0]) >= 3, "The real draw loop must execute the normal, overview and close-up render layers.")
	map.queue_free()
	await process_frame
