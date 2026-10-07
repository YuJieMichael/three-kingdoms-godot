extends SceneTree

## Geometry and actual redraw regression tests. Synthetic DTOs are rendering
## fixtures only; they do not expand the canonical world or measure FPS.
class DrawProbe extends "res://src/world_map.gd":
	var route_requests: Array[Dictionary] = []
	var feature_requests: Array[Vector2i] = []
	var forest_requests: Array[Vector2i] = []
	var mountain_requests: Array[Vector2i] = []
	var field_requests: Array[Vector2i] = []
	var badge_requests: Array[Dictionary] = []

	func _draw_dashed_line(start: Vector2, target: Vector2, color: Color, width: float) -> void:
		route_requests.append({"start": start, "target": target})
		super._draw_dashed_line(start, target, color, width)

	func _draw_tile_features(tile: Dictionary, coordinates: Vector2i) -> void:
		feature_requests.append(coordinates)
		super._draw_tile_features(tile, coordinates)

	func _draw_forest(center: Vector2, coordinates: Vector2i) -> void:
		forest_requests.append(coordinates)
		super._draw_forest(center, coordinates)

	func _draw_mountain(center: Vector2, coordinates: Vector2i) -> void:
		mountain_requests.append(coordinates)
		super._draw_mountain(center, coordinates)

	func _draw_fields(center: Vector2, coordinates: Vector2i) -> void:
		field_requests.append(coordinates)
		super._draw_fields(center, coordinates)

	func _draw_badge(center: Vector2, label: String, color: Color) -> void:
		badge_requests.append({"center": center, "label": label})
		super._draw_badge(center, label, color)

const MAP_SCRIPT: Script = preload("res://src/world_map.gd")
const VIEW_BOUNDS: Rect2 = Rect2(0, 0, 100, 100)
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_segment_clipping()
	_test_dash_selection()
	_test_drag_preserves_world_and_phase()
	_test_coordinate_geometry_cache()
	await _test_actual_redraws()
	await _test_skipped_arrival_frames()
	await _test_overview_feature_selection()
	await _test_terrain_dispatch()
	print("MAP_RENDER_TEST_CHECKS=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _interval(start: Vector2, target: Vector2, expected: Vector2, message: String) -> void:
	var actual: Vector2 = MAP_SCRIPT.segment_visible_interval(start, target, VIEW_BOUNDS)
	_check(actual.is_equal_approx(expected), message)
	if actual.x >= 0.0:
		_check(actual.x <= actual.y and actual.x >= 0.0 and actual.y <= 1.0, "Clipped entry/exit must remain ordered fractions of the original segment.")
		_check(_inside_inclusive(start.lerp(target, actual.x), VIEW_BOUNDS) and _inside_inclusive(start.lerp(target, actual.y), VIEW_BOUNDS), "Both clipped endpoints must lie in the visible rectangle, including its border.")


func _test_segment_clipping() -> void:
	_interval(Vector2(25, 25), Vector2(75, 25), Vector2(0, 1), "A fully visible segment retains its complete original interval.")
	_interval(Vector2(-50, 50), Vector2(150, 50), Vector2(0.25, 0.75), "Horizontal crossing clips both offscreen endpoints.")
	_interval(Vector2(150, 50), Vector2(-50, 50), Vector2(0.25, 0.75), "Reverse routes preserve entry-to-exit order along their original direction.")
	_interval(Vector2(50, -50), Vector2(50, 150), Vector2(0.25, 0.75), "Vertical clipping must work without dividing by a horizontal component.")
	_interval(Vector2(-50, -50), Vector2(150, 150), Vector2(0.25, 0.75), "Diagonal clipping retains the same geometric screen intersection.")
	_interval(Vector2(0, 10), Vector2(0, 90), Vector2(0, 1), "A route running along the left border remains visible.")
	_interval(Vector2(100, 10), Vector2(100, 90), Vector2(0, 1), "A route running along the right border remains visible.")
	_interval(Vector2(-50, 50), Vector2(50, -50), Vector2(0.5, 0.5), "A route touching exactly one corner retains that boundary contact.")
	_interval(Vector2(-50, -1), Vector2(150, -1), Vector2(-1, -1), "A parallel route completely above the viewport has no visible interval.")
	_interval(Vector2(101, 10), Vector2(101, 90), Vector2(-1, -1), "A parallel route beyond the right edge has no visible interval.")
	_interval(Vector2(-50, 25), Vector2(-25, 75), Vector2(-1, -1), "A route entirely to one side must not produce a false intersection.")
	_interval(Vector2(50, 50), Vector2(50, 50), Vector2(0, 1), "An internal point segment is geometrically visible without division by zero.")
	_interval(Vector2(150, 50), Vector2(150, 50), Vector2(-1, -1), "An offscreen point segment is rejected.")
	_interval(Vector2(100, 100), Vector2(100, 100), Vector2(0, 1), "A point at the bottom-right border is included consistently.")
	var long_interval: Vector2 = MAP_SCRIPT.segment_visible_interval(Vector2(-10000, 50), Vector2(10000, 50), VIEW_BOUNDS)
	_check(long_interval.is_equal_approx(Vector2(0.5, 0.505)), "A route whose origin is more than 9000 pixels offscreen must still cross the viewport.")


func _dash_range(start: Vector2, target: Vector2, expected: Vector2i, message: String) -> void:
	var actual: Vector2i = MAP_SCRIPT.visible_dash_range(start, target, VIEW_BOUNDS)
	_check(actual == expected, message)


func _test_dash_selection() -> void:
	_dash_range(Vector2(25, 25), Vector2(75, 25), Vector2i(0, 4), "A short visible route retains all four dashes at the original origin phase.")
	_dash_range(Vector2(-7, 50), Vector2(100, 50), Vector2i(0, 8), "An eight-pixel dash beginning before the screen must keep its visible final pixel.")
	_dash_range(Vector2(-8, 50), Vector2(100, 50), Vector2i(0, 8), "A dash exactly touching the entry border is included.")
	_dash_range(Vector2(-9, 50), Vector2(100, 50), Vector2i(1, 8), "A fully clipped first dash must not restart its phase at the screen boundary.")
	_dash_range(Vector2(-10000, 50), Vector2(10000, 50), Vector2i(667, 674), "Long crossing routes start at the original dash index beyond the old 600-step limit.")
	_dash_range(Vector2(10000, 50), Vector2(-10000, 50), Vector2i(660, 667), "Reverse long routes preserve their own starting phase and visible index range.")
	_dash_range(Vector2(-1000000, 50), Vector2(1000000, 50), Vector2i(66667, 66674), "A two-million-pixel route emits only the seven dashes intersecting this viewport.")
	_dash_range(Vector2(-1000028, 50), Vector2(999972, 50), Vector2i(66668, 66676), "A long route must retain original dash 66668 whose tail touches the entry border exactly, despite fractional clipping precision.")
	_dash_range(Vector2(-999950, 50), Vector2(1000050, 50), Vector2i(66663, 66671), "A long route must retain original dash 66670 starting exactly on the exit border, despite fractional clipping precision.")
	_dash_range(Vector2(-50, -1), Vector2(150, -1), Vector2i.ZERO, "Completely offscreen routes have an empty dash range.")
	_dash_range(Vector2(50, 50), Vector2(50.5, 50), Vector2i.ZERO, "Routes shorter than one pixel preserve the existing no-draw behavior.")
	_dash_range(Vector2(50, 50), Vector2(50, 50), Vector2i.ZERO, "Point routes do not emit a meaningless dash.")
	_dash_range(Vector2(-10, 50), Vector2(-2, 50), Vector2i.ZERO, "An offscreen eight-pixel route has no dash candidates.")
	_dash_range(Vector2(-10, 50), Vector2(2, 50), Vector2i.ZERO, "A visible part lying entirely in the seven-pixel gap does not create a new dash.")

	# Independently intersect each short original dash with the rectangle edges.
	# This oracle enumerates geometry; it does not reproduce the clipping/index
	# formulas used by the production helper.
	var routes: Array = [
		[Vector2(-50, 50), Vector2(150, 50)],
		[Vector2(150, 50), Vector2(-50, 50)],
		[Vector2(50, -50), Vector2(50, 150)],
		[Vector2(50, 150), Vector2(50, -50)],
		[Vector2(-50, -50), Vector2(150, 150)],
		[Vector2(150, 150), Vector2(-50, -50)],
		[Vector2(-50, 50), Vector2(50, -50)],
		[Vector2(0, -23), Vector2(0, 144)],
		[Vector2(100, -23), Vector2(100, 144)],
		[Vector2(-34, 78), Vector2(139, 7)],
		[Vector2(-8, 40), Vector2(100, 40)],
		[Vector2(-9, 40), Vector2(100, 40)],
		[Vector2(-10, 40), Vector2(2, 40)],
		[Vector2(-17, 30), Vector2(-1, 30)]
	]
	for route: Array in routes:
		var start: Vector2 = route[0]
		var target: Vector2 = route[1]
		var expected: Vector2i = _enumerate_intersecting_dashes(start, target, VIEW_BOUNDS)
		var actual: Vector2i = MAP_SCRIPT.visible_dash_range(start, target, VIEW_BOUNDS)
		_check(actual == expected, "Dash candidates must agree with independent segment/rectangle intersections: %s -> %s." % [start, target])


func _inside_inclusive(point: Vector2, bounds: Rect2) -> bool:
	return point.x >= bounds.position.x - 0.001 and point.x <= bounds.end.x + 0.001 and point.y >= bounds.position.y - 0.001 and point.y <= bounds.end.y + 0.001


func _intersects_bounds(start: Vector2, target: Vector2, bounds: Rect2) -> bool:
	if _inside_inclusive(start, bounds) or _inside_inclusive(target, bounds):
		return true
	var corners: Array[Vector2] = [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	for edge: int in range(4):
		if Geometry2D.segment_intersects_segment(start, target, corners[edge], corners[(edge + 1) % 4]) != null:
			return true
	return false


func _enumerate_intersecting_dashes(start: Vector2, target: Vector2, bounds: Rect2) -> Vector2i:
	var length: float = start.distance_to(target)
	if length < 1.0:
		return Vector2i.ZERO
	var direction: Vector2 = (target - start).normalized()
	var first: int = -1
	var end: int = 0
	var offset: float = 0.0
	var index: int = 0
	while offset < length:
		if _intersects_bounds(start + direction * offset, start + direction * minf(offset + 8.0, length), bounds):
			if first < 0:
				first = index
			end = index + 1
		offset += 15.0
		index += 1
	return Vector2i.ZERO if first < 0 else Vector2i(first, end)


func _test_drag_preserves_world_and_phase() -> void:
	var map: Variant = MAP_SCRIPT.new()
	map.size = Vector2(640, 360)
	map.set_world({"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [], "marches": [{"id": "unchanged-route", "from": {"x": 1, "y": 32}, "to": {"x": 62, "y": 32}, "start": 1000, "arrive": 9000}]})
	map.focus_home()
	var world_before: Dictionary = map.world.duplicate(true)
	var start_before: Vector2 = map.world_to_screen(Vector2(1.5, 32.5))
	var target_before: Vector2 = map.world_to_screen(Vector2(62.5, 32.5))
	map._begin_pointer(Vector2(200, 180))
	map._move_pointer(Vector2(237, 180))
	map._end_pointer(Vector2(237, 180))
	var start_after: Vector2 = map.world_to_screen(Vector2(1.5, 32.5))
	var target_after: Vector2 = map.world_to_screen(Vector2(62.5, 32.5))
	_check(map.world == world_before, "Pointer panning must preserve route data and world rules.")
	_check(start_after.is_equal_approx(start_before + Vector2(37, 0)) and target_after.is_equal_approx(target_before + Vector2(37, 0)), "A drag translates both screen route endpoints by the same pointer distance.")
	var direction_before: Vector2 = (target_before - start_before).normalized()
	var direction_after: Vector2 = (target_after - start_after).normalized()
	var common_dash: int = 115
	_check((start_after + direction_after * float(common_dash) * 15.0).is_equal_approx(start_before + direction_before * float(common_dash) * 15.0 + Vector2(37, 0)), "Panning must translate existing dash positions without anchoring their phase to the new viewport edge.")
	var dash_range: Vector2i = MAP_SCRIPT.visible_dash_range(start_after, target_after, Rect2(Vector2.ZERO, map.size))
	_check(dash_range == _enumerate_intersecting_dashes(start_after, target_after, Rect2(Vector2.ZERO, map.size)), "Visible dash selection after a drag must still match the unchanged route's original geometry.")
	map.free()


func _offsets_equal(actual: PackedVector2Array, expected: PackedVector2Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in range(actual.size()):
		if not actual[index].is_equal_approx(expected[index]):
			return false
	return true


func _test_coordinate_geometry_cache() -> void:
	# Frozen visual geometry from the previous renderer, independently evaluated
	# with Python math before introducing the caches. These are normalized values,
	# not viewport positions; one forest always contains the same five trees.
	var golden: Array = [
		{"at": Vector2i(0, 0), "offsets": PackedVector2Array([Vector2(0.0, 0.27), Vector2(-0.225635521, 0.153635456), Vector2(0.337576700, -0.095156643), Vector2(-0.279418064, -0.261927560), Vector2(0.080464874, -0.202927507)]), "shift": 0.0},
		{"at": Vector2i(32, 32), "offsets": PackedVector2Array([Vector2(0.042065714, -0.264019342), Vector2(-0.255369499, -0.196704803), Vector2(0.339996440, 0.040161327), Vector2(-0.253304294, 0.242410016), Vector2(0.038975930, 0.235711068)]), "shift": 0.331895400},
		{"at": Vector2i(17, 29), "offsets": PackedVector2Array([Vector2(-0.148323685, -0.242736656), Vector2(0.313987668, -0.235347402), Vector2(-0.321437995, -0.025098198), Vector2(0.166920556, 0.206784638), Vector2(0.071705637, 0.260427473)]), "shift": -0.220468992},
		{"at": Vector2i(-9, 73), "offsets": PackedVector2Array([Vector2(-0.027077154, -0.127732975), Vector2(0.245174125, -0.268292461), Vector2(-0.339731547, -0.177594688), Vector2(0.263103358, 0.066182529), Vector2(-0.053901349, 0.252913080)]), "shift": 0.203213914},
		{"at": Vector2i(4096, 2048), "offsets": PackedVector2Array([Vector2(0.219291068, -0.172545976), Vector2(0.008389400, 0.072591876), Vector2(-0.231842576, 0.255158464), Vector2(0.338473769, 0.217788769), Vector2(-0.274553127, -0.007306044)]), "shift": -0.348025460}
	]
	var map: Variant = MAP_SCRIPT.new()
	for sample: Dictionary in golden:
		var coordinates: Vector2i = sample["at"]
		var actual: PackedVector2Array = map._forest_offsets(coordinates)
		var expected: PackedVector2Array = sample["offsets"]
		_check(actual.size() == 5, "Cached forest geometry must retain exactly five trees at %s." % coordinates)
		for index: int in range(expected.size()):
			_check(index < actual.size() and actual[index].is_equal_approx(expected[index]), "Normalized tree %d at %s must match the frozen visual geometry." % [index, coordinates])
		_check(is_equal_approx(map._mountain_shift(coordinates), float(sample["shift"])), "Cached mountain shift at %s must match the frozen visual geometry." % coordinates)
	var anchor: Vector2i = Vector2i(32, 32)
	var forest_before: PackedVector2Array = map._forest_offsets(anchor).duplicate()
	var mountain_before: float = map._mountain_shift(anchor)
	var forest_count: int = map._forest_offset_cache.size()
	var mountain_count: int = map._mountain_shift_cache.size()
	map.size = Vector2(640, 360)
	map.zoom = 1.4
	map.camera_center = Vector2(49, 11)
	_check(_offsets_equal(map._forest_offsets(anchor), forest_before) and is_equal_approx(map._mountain_shift(anchor), mountain_before), "Camera and zoom changes must not rescale or translate normalized cached geometry.")
	_check(map._forest_offset_cache.size() == forest_count and map._mountain_shift_cache.size() == mountain_count, "Looking up existing geometry after zoom/pan must reuse the same coordinate entries.")
	var next_world: Dictionary = {"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [{"x": 32, "y": 32, "id": "changed-terrain", "terrain": "mountain", "kind": "wild"}], "marches": []}
	map.set_world(next_world)
	_check(_offsets_equal(map._forest_offsets(anchor), forest_before) and is_equal_approx(map._mountain_shift(anchor), mountain_before), "Replacing world terrain must not contaminate coordinate-only geometry with the previous terrain type.")
	_check(map.world == next_world, "Geometry caching must preserve the current world DTO exactly.")

	map._forest_offset_cache.clear()
	map._mountain_shift_cache.clear()
	var bounded: bool = true
	var complete: bool = true
	var limit: int = MAP_SCRIPT.DECORATION_CACHE_LIMIT
	_check(limit == 2048, "Lazy decoration geometry must use the agreed 2048-coordinate memory budget.")
	for index: int in range(limit * 2 + 17):
		var coordinates: Vector2i = Vector2i(1000 + index, 7)
		var offsets: PackedVector2Array = map._forest_offsets(coordinates)
		var shift: float = map._mountain_shift(coordinates)
		bounded = bounded and map._forest_offset_cache.size() <= limit and map._mountain_shift_cache.size() <= limit
		complete = complete and offsets.size() == 5 and absf(shift) <= 0.350001
	_check(bounded, "Visiting more than twice the cache capacity must never exceed either coordinate budget.")
	_check(complete, "Every cache miss and overflow must still produce complete forest and mountain geometry.")
	_check(_offsets_equal(map._forest_offsets(anchor), forest_before) and is_equal_approx(map._mountain_shift(anchor), mountain_before), "Revisiting an evicted coordinate must reconstruct the same visual geometry.")
	_check(map._forest_offset_cache.size() <= limit and map._mountain_shift_cache.size() <= limit, "Reconstruction after eviction must also respect both cache budgets.")
	map.free()


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _apply_marches(map: DrawProbe, marches: Array) -> void:
	map.set_world({"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [], "marches": marches})
	map.focus_home()
	map._velocity = Vector2.ZERO
	map._march_redraw_elapsed = 0.0
	map._march_animated = false
	map.route_requests.clear()
	await _settle()


func _step_animation(map: DrawProbe, count: int) -> void:
	for step: int in range(count):
		map._process(0.051)
		await _settle()


func _test_actual_redraws() -> void:
	var map: DrawProbe = DrawProbe.new()
	var draws: Array[int] = [0]
	map.draw.connect(func() -> void: draws[0] += 1)
	root.add_child(map)
	map.size = Vector2(640, 360)
	map.set_process(false)
	var now: float = Time.get_unix_time_from_system() * 1000.0
	var visible: Dictionary = {"id": "visible", "label": "可见行军", "from": {"x": 32, "y": 32}, "to": {"x": 34, "y": 32}, "start": now - 60000, "arrive": now + 60000, "status": "march"}
	await _apply_marches(map, [visible])
	var before: int = draws[0]
	map._process(0.02)
	await _settle()
	_check(draws[0] == before, "A visible march must not redraw before the 50ms animation interval.")
	map._process(0.031)
	await _settle()
	_check(draws[0] == before + 1, "A visible march must redraw when the animation interval elapses.")
	before = draws[0]
	await _step_animation(map, 6)
	_check(draws[0] == before + 6, "A visible moving marker must keep animating in the actual SceneTree draw loop.")
	_check(not map.route_requests.is_empty(), "The actual draw loop must dispatch visible marching routes to the production dashed renderer.")

	var offscreen: Array = []
	for index: int in range(100):
		offscreen.append({"id": "offscreen-%d" % index, "from": {"x": 0, "y": 0}, "to": {"x": 2, "y": 2}, "start": now - 60000, "arrive": now + 60000, "status": "march"})
	await _apply_marches(map, offscreen)
	before = draws[0]
	await _step_animation(map, 8)
	_check(draws[0] == before, "One hundred offscreen moving markers must not cause repeated map redraws.")
	_check(not map._march_animated, "Completely offscreen marching troops must not leave the visible-animation flag enabled.")

	var crossing: Dictionary = {"id": "long-crossing", "label": "远途行军", "from": {"x": -300, "y": 32}, "to": {"x": 300, "y": 32}, "start": now - 1000, "arrive": now + 1000000, "status": "march"}
	await _apply_marches(map, [crossing])
	_check(map.route_requests.size() == 1, "A crossing route is still drawn even when its moving marker is offscreen.")
	if not map.route_requests.is_empty():
		var request: Dictionary = map.route_requests[0]
		var range_visible: Vector2i = MAP_SCRIPT.visible_dash_range(request["start"], request["target"], Rect2(Vector2.ZERO, map.size).grow(16.0))
		_check(range_visible.x > 600 and range_visible.y > range_visible.x, "A real draw dispatch must retain crossing dashes beyond the previous 600-step cap.")
		_check(range_visible.y - range_visible.x <= 47, "The actual long-route candidate count remains bounded by this viewport, not world distance.")
	before = draws[0]
	await _step_animation(map, 6)
	_check(draws[0] == before, "A static crossing route with an offscreen marker must not animate the entire map repeatedly.")

	var stationary: Array = []
	for status: String in ["stationed", "garrison", "gathering"]:
		stationary.append({"id": status, "label": status, "from": {"x": 30, "y": 32}, "to": {"x": 32, "y": 32}, "start": now, "arrive": null, "status": status})
	await _apply_marches(map, stationary)
	before = draws[0]
	await _step_animation(map, 6)
	_check(draws[0] == before and not map._march_animated, "Visible stationed, garrisoned and gathering troops with null arrivals must remain static.")
	_check(map._pending_arrival_marches.is_empty(), "Null-arrival stationed and gathering troops must not enter the pending-arrival animation list.")

	var margin_position: Vector2 = map.screen_to_world(Vector2(-80, 180)) - Vector2.ONE * 0.5
	var label_edge: Dictionary = {"id": "label-edge", "label": "边缘行军", "from": {"x": margin_position.x, "y": margin_position.y}, "to": {"x": margin_position.x + 0.2, "y": margin_position.y}, "start": now - 60000, "arrive": now + 60000, "status": "returning"}
	await _apply_marches(map, [label_edge])
	before = draws[0]
	await _step_animation(map, 3)
	_check(draws[0] == before + 3, "A moving marker inside the existing 120-pixel label margin must keep its visible-label animation.")

	await _apply_marches(map, [visible])
	for filter_name: String in ["resources", "cities", "tasks"]:
		map.set_filter(filter_name)
		await _settle()
		# Permit the one existing animation-to-static transition, then verify the
		# stable filtered view never keeps rendering hidden troop animations.
		map._process(0.051)
		await _settle()
		before = draws[0]
		await _step_animation(map, 4)
		_check(draws[0] == before, "The %s filter must stop redraws caused by hidden marching markers." % filter_name)
	for filter_name: String in ["marches", "all"]:
		map.set_filter(filter_name)
		await _settle()
		before = draws[0]
		await _step_animation(map, 3)
		_check(draws[0] == before + 3, "The %s filter must resume visible marching animation." % filter_name)
	map.queue_free()
	await _settle()


func _test_skipped_arrival_frames() -> void:
	var map: DrawProbe = DrawProbe.new()
	var draws: Array[int] = [0]
	map.draw.connect(func() -> void: draws[0] += 1)
	root.add_child(map)
	map.size = Vector2(640, 360)
	map.set_process(false)
	for large_stall: bool in [false, true]:
		var now: float = Time.get_unix_time_from_system() * 1000.0
		var short_trip: Dictionary = {"id": "short-trip", "label": "短途抵达", "from": {"x": 0, "y": 0}, "to": {"x": 32, "y": 32}, "start": now, "arrive": now + 200.0, "status": "march"}
		await _apply_marches(map, [short_trip])
		_check(not map._march_animated, "No visible-animation scan has armed the short journey before its first simulated tick.")
		_check(map._pending_arrival_marches.size() == 1, "A short future arrival must be tracked even while the map animation has never armed.")
		var before: int = draws[0]
		# Let actual Unix time pass without processing the map, representing a
		# short trip completing between animation scans or during one long frame.
		await create_timer(0.25).timeout
		map._process(0.8 if large_stall else 0.051)
		await _settle()
		_check(draws[0] == before + 1, "A completed short trip must draw its visible destination on the next tick without waiting for a world refresh (large stall=%s)." % large_stall)
		_check(map._pending_arrival_marches.is_empty() and not map._march_animated, "A completed arrival must be consumed and leave the map in a static state.")
		_check(MAP_SCRIPT.march_world_position(map.world["marches"][0], Time.get_unix_time_from_system() * 1000.0).is_equal_approx(Vector2(32.5, 32.5)), "The final rendered redraw must use the original trip's destination tile center.")
		before = draws[0]
		await _step_animation(map, 4)
		_check(draws[0] == before, "A completed visible arrival must not cause recurring finish redraws.")

	var now: float = Time.get_unix_time_from_system() * 1000.0
	await _apply_marches(map, [{"id": "offscreen-finish", "from": {"x": 60, "y": 60}, "to": {"x": 62, "y": 62}, "start": now, "arrive": now + 200.0, "status": "march"}])
	var before: int = draws[0]
	await create_timer(0.25).timeout
	map._process(0.8)
	await _settle()
	_check(draws[0] == before and map._pending_arrival_marches.is_empty(), "An arrival whose destination remains offscreen must be consumed without redrawing the map.")
	await _step_animation(map, 3)
	_check(draws[0] == before, "An offscreen finish must not leave recurring pending-arrival redraws.")

	map.set_filter("resources")
	now = Time.get_unix_time_from_system() * 1000.0
	await _apply_marches(map, [{"id": "filtered-finish", "from": {"x": 0, "y": 0}, "to": {"x": 32, "y": 32}, "start": now, "arrive": now + 200.0, "status": "march"}])
	before = draws[0]
	await create_timer(0.25).timeout
	map._process(0.8)
	await _settle()
	_check(draws[0] == before and map._pending_arrival_marches.is_empty(), "A filter hiding marches must consume completed arrivals without drawing hidden troops.")
	map.set_filter("all")
	await _settle()
	_check(draws[0] == before + 1, "Reopening the all view must show the completed destination through the filter's normal redraw.")
	before = draws[0]
	await _step_animation(map, 3)
	_check(draws[0] == before, "Reopening completed arrivals must not restart moving animations.")
	map.queue_free()
	await _settle()


func _test_overview_feature_selection() -> void:
	var map: DrawProbe = DrawProbe.new()
	root.add_child(map)
	map.size = Vector2(640, 360)
	map.set_process(false)
	var tiles: Array = []
	var expected_cities: Array[Vector2i] = []
	var city_kinds: Array[String] = ["home", "city", "county", "prefecture", "province", "capital", "yellow_city", "named_city", "town"]
	for index: int in range(city_kinds.size()):
		var coordinates: Vector2i = Vector2i(26 + index, 30)
		expected_cities.append(coordinates)
		tiles.append({"id": "feature-%d" % index, "x": coordinates.x, "y": coordinates.y, "kind": city_kinds[index], "owned": false, "name": "测试城市"})
	var compatibility_city: Vector2i = Vector2i(36, 30)
	tiles.append({"id": "city-compatible", "x": 36, "y": 30, "kind": "wild", "name": "兼容城市"})
	expected_cities.append(compatibility_city)
	var expected_tasks: Array[Vector2i] = []
	var task_kinds: Array[String] = ["task", "quest", "mission", "chapter", "landmark"]
	for index: int in range(task_kinds.size()):
		var coordinates: Vector2i = Vector2i(26 + index, 33)
		expected_tasks.append(coordinates)
		tiles.append({"id": "task-feature-%d" % index, "x": coordinates.x, "y": coordinates.y, "kind": task_kinds[index], "name": "测试任务"})
	var flagged_task: Vector2i = Vector2i(31, 33)
	tiles.append({"id": "flagged-task", "x": 31, "y": 33, "kind": "wild", "task": true, "name": "兼容任务"})
	expected_tasks.append(flagged_task)
	var ordinary_wild: Vector2i = Vector2i(29, 34)
	tiles.append({"id": "ordinary-wood", "x": 29, "y": 34, "kind": "wild", "terrain": "forest"})
	tiles.append({"id": "ordinary-owned", "x": 31, "y": 34, "kind": "wild", "owned": true, "terrain": "plain"})
	tiles.append({"id": "far-city", "x": 0, "y": 0, "kind": "city", "name": "视口之外"})
	var dto: Dictionary = {"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": tiles, "marches": []}
	var original: Dictionary = dto.duplicate(true)
	map.set_world(dto)
	map.zoom = 0.17
	map.focus_home()
	map.feature_requests.clear()
	await _settle()
	for coordinates: Vector2i in expected_cities:
		_check(map.feature_requests.has(coordinates), "Overview must retain the original city classification for coordinate %s." % coordinates)
	_check(map.feature_requests.has(Vector2i(32, 32)), "Overview must draw the home marker even when the home tile has no DTO entry.")
	_check(not map.feature_requests.has(ordinary_wild) and not map.feature_requests.has(Vector2i(31, 34)), "Overview must skip ordinary wild-feature calls, including owned resource tiles.")
	_check(not map.feature_requests.has(Vector2i(0, 0)), "A sparse city outside the overview viewport must not request feature drawing.")
	_check(map.feature_requests.size() == expected_cities.size() + expected_tasks.size() + 1, "Overview dispatches only sparse city/task/home coordinates, rather than every visible wild tile.")
	_check(map.world == original and dto == original, "Sparse overview indexing must not rewrite the input DTO or the canonical world copy.")
	var ordered: bool = true
	for index: int in range(1, map.feature_requests.size()):
		var previous: Vector2i = map.feature_requests[index - 1]
		var current: Vector2i = map.feature_requests[index]
		if current.y < previous.y or (current.y == previous.y and current.x <= previous.x):
			ordered = false
	_check(ordered, "Sparse overview drawing preserves the original row-by-row ordering without duplicate home coordinates.")

	map.zoom = 0.43
	map.feature_requests.clear()
	map.queue_redraw()
	await _settle()
	for coordinates: Vector2i in expected_tasks:
		_check(map.feature_requests.has(coordinates), "Overview at 43% must still dispatch every visible task whose original draw threshold is 43%.")
	_check(not map.feature_requests.has(ordinary_wild), "The sparse path still excludes wild-feature dispatch below the 46% detail threshold.")

	map.zoom = 0.46
	map.feature_requests.clear()
	map.queue_redraw()
	await _settle()
	_check(map.feature_requests.has(ordinary_wild), "At 46% the normal tile loop retains existing visible forest/wild details.")
	_check(map.feature_requests.size() > expected_cities.size() + expected_tasks.size() + 1, "The detailed view retains normal per-tile dispatch instead of reusing sparse overview selection.")

	var replacement: Dictionary = {"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [
		{"id": "former-city-now-wild", "x": 26, "y": 30, "kind": "wild", "owned": true},
		{"id": "fresh-city", "x": 33, "y": 31, "kind": "county", "owned": true, "name": "新领地"}
	], "marches": []}
	map.zoom = 0.17
	map.set_world(replacement)
	map.focus_home()
	map.feature_requests.clear()
	await _settle()
	_check(map.feature_requests == [Vector2i(33, 31), Vector2i(32, 32)], "Replacing the DTO must remove former city/task features and retain only the new city plus fallback home in draw order.")
	_check(map._tile_at(Vector2i(26, 30)).get("id", "") == "former-city-now-wild" and bool(map._tile_at(Vector2i(26, 30)).get("owned", false)), "A removed sparse city remains the current owned wild tile for selection, without stale cached identity.")
	_check(map._tile_at(Vector2i(33, 31)).get("id", "") == "fresh-city", "The new sparse city remains backed by the current selection DTO.")
	_check(map.world == replacement, "Replacing sparse features preserves current ownership and world data exactly.")
	map.queue_free()
	await _settle()


func _reset_decoration_requests(map: DrawProbe) -> void:
	map.forest_requests.clear()
	map.mountain_requests.clear()
	map.field_requests.clear()
	map.badge_requests.clear()


func _has_badge(map: DrawProbe, coordinates: Vector2i, label: String) -> bool:
	var expected_center: Vector2 = map.world_to_screen(Vector2(coordinates) + Vector2.ONE * 0.5) + Vector2(0, -3)
	for request: Dictionary in map.badge_requests:
		if str(request["label"]) == label and Vector2(request["center"]).is_equal_approx(expected_center):
			return true
	return false


func _test_terrain_dispatch() -> void:
	var map: DrawProbe = DrawProbe.new()
	root.add_child(map)
	map.size = Vector2(640, 360)
	map.set_process(false)
	var aliases: Array = [
		{"terrain": "forest", "decoration": "forest", "badge": "木"},
		{"terrain": "wood", "decoration": "forest", "badge": "木"},
		{"terrain": "woods", "decoration": "forest", "badge": "木"},
		# Canonical TerrainData: mountain mines iron; hill quarries stone.
		{"terrain": "mountain", "decoration": "mountain", "badge": "铁"},
		{"terrain": "stone", "decoration": "mountain", "badge": "石"},
		{"terrain": "iron", "decoration": "mountain", "badge": "铁"},
		{"terrain": "hill", "decoration": "mountain", "badge": "石"},
		{"terrain": "plain", "decoration": "field", "badge": "粮"},
		{"terrain": "farm", "decoration": "field", "badge": "粮"},
		{"terrain": "food", "decoration": "field", "badge": "粮"},
		{"terrain": "grass", "decoration": "field", "badge": "粮"},
		{"terrain": "water", "decoration": "none", "badge": "粮"},
		{"terrain": "lake", "decoration": "none", "badge": "粮"},
		{"terrain": "river", "decoration": "none", "badge": "粮"},
		{"terrain": "desert", "decoration": "none", "badge": "粮"},
		{"terrain": "wasteland", "decoration": "none", "badge": "粮"},
		{"terrain": "unrecognized", "decoration": "none", "badge": "粮"}
	]
	var tiles: Array = []
	for index: int in range(aliases.size()):
		var coordinates: Vector2i = Vector2i(26 + index % 8, 29 + floori(float(index) / 8.0))
		aliases[index]["at"] = coordinates
		tiles.append({"id": "terrain-%d" % index, "x": coordinates.x, "y": coordinates.y, "kind": "wild", "terrain": aliases[index]["terrain"]})
	var city_coordinates: Vector2i = Vector2i(35, 33)
	tiles.append({"id": "decoration-city", "x": 35, "y": 33, "kind": "city", "terrain": "forest"})
	var dto: Dictionary = {"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": tiles, "marches": []}
	map.set_world(dto)
	map.zoom = 0.80
	map.focus_home()
	map.set_filter("resources")
	_reset_decoration_requests(map)
	await _settle()
	for sample: Dictionary in aliases:
		var coordinates: Vector2i = sample["at"]
		var forest: bool = map.forest_requests.has(coordinates)
		var mountain: bool = map.mountain_requests.has(coordinates)
		var field: bool = map.field_requests.has(coordinates)
		var decoration: String = str(sample["decoration"])
		_check(forest == (decoration == "forest") and mountain == (decoration == "mountain") and field == (decoration == "field"), "Terrain alias %s must retain its previous forest/mountain/field dispatch in the real draw loop." % sample["terrain"])
		_check(_has_badge(map, coordinates, str(sample["badge"])), "Terrain alias %s must retain its previous resource badge." % sample["terrain"])
	_check(not map.forest_requests.has(city_coordinates), "A city on forest terrain must keep its city rendering instead of receiving wild-tree decorations.")

	var changed_coordinates: Vector2i = aliases[0]["at"]
	var forest_geometry: PackedVector2Array = map._forest_offsets(changed_coordinates).duplicate()
	var replacement: Dictionary = {"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [
		{"id": "same-coordinate-new-hill", "x": changed_coordinates.x, "y": changed_coordinates.y, "kind": "wild", "terrain": "hill", "owned": true},
		{"id": "new-coordinate-new-forest", "x": 36, "y": 33, "kind": "wild", "terrain": "woods", "owned": true}
	], "marches": []}
	map.set_world(replacement)
	map.focus_home()
	_reset_decoration_requests(map)
	await _settle()
	_check(map.mountain_requests.has(changed_coordinates) and not map.forest_requests.has(changed_coordinates), "Changing a cached forest coordinate to hill must immediately draw mountain geometry, without stale terrain routing.")
	_check(map.forest_requests.has(Vector2i(36, 33)) and _has_badge(map, Vector2i(36, 33), "木"), "A new forest coordinate in a replacement world must draw trees and the current resource badge.")
	_check(_has_badge(map, changed_coordinates, "石"), "Changing terrain at an existing coordinate must update its resource badge in the same redraw.")
	_check(_offsets_equal(map._forest_offsets(changed_coordinates), forest_geometry), "A terrain change may reuse coordinate geometry but must not modify its normalized tree layout.")
	_check(map.world == replacement and bool(map._tile_at(changed_coordinates).get("owned", false)), "Terrain-decoration caching must preserve the replacement world's ownership and selection data.")
	map.queue_free()
	await _settle()
