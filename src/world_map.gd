extends Control
class_name KingdomWorldMap

## A viewport renderer for the unchanged legacy world. Camera positions use tile
## coordinates; positions in the DTO denote tile centres without changing rules.
signal tile_selected(tile: Dictionary)

const BASE_CELL: float = 64.0
const MIN_ZOOM: float = 0.17
const MAX_ZOOM: float = 1.90
const DRAG_THRESHOLD: float = 9.0
const INERTIA_DECAY: float = 7.8
const KEYBOARD_PIXELS_PER_SECOND: float = 480.0
const GOLD: Color = Color("cfb579")
const TEXT: Color = Color("eee4cd")
const BORDER: Color = Color("444e48")

var world: Dictionary = {"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [], "marches": []}
var camera_center: Vector2 = Vector2(32.5, 32.5)
var zoom: float = 0.80
var selected_tile: Dictionary = {}
var filter_kind: String = "all"
var regions: Array = []
var _tile_index: Dictionary = {}
var _font: Font
var _pointer_down: bool = false
var _pointer_start: Vector2 = Vector2.ZERO
var _pointer_previous: Vector2 = Vector2.ZERO
var _dragged: bool = false
var _last_move_ms: int = 0
var _velocity: Vector2 = Vector2.ZERO
var _touches: Dictionary = {}
var _pinch_distance: float = 0.0
var _pinch_midpoint: Vector2 = Vector2.ZERO
var _touch_gesture_dragged: bool = false
var _march_redraw_elapsed: float = 0.0
var _march_animated: bool = false
var _last_hover: Vector2 = Vector2(-1, -1)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	custom_minimum_size = Vector2(260, 220)
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/UI.tres"):
		_font = load("res://assets/fonts/UI.tres") as Font
	var path: String = "res://data/map_regions.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("regions", []) is Array:
			regions = parsed.get("regions", [])
	resized.connect(_on_resized)
	set_process(true)
	queue_redraw()


func set_world(next_world: Dictionary) -> void:
	world = next_world.duplicate(true)
	world["width"] = maxi(1, int(world.get("width", 64)))
	world["height"] = maxi(1, int(world.get("height", 64)))
	_tile_index.clear()
	for item: Variant in world.get("tiles", []):
		if item is Dictionary:
			var tile: Dictionary = item
			_tile_index[Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))] = tile
	if not selected_tile.is_empty():
		selected_tile = _tile_at(Vector2i(int(selected_tile.get("x", 0)), int(selected_tile.get("y", 0))))
	camera_center = clamp_camera(camera_center, size, world_size(), cell_pixels())
	queue_redraw()


func focus_home() -> void:
	var home: Dictionary = world.get("home", {"x": 32, "y": 32})
	focus_tile(int(home.get("x", 32)), int(home.get("y", 32)))


func keyboard_pan(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx() or _pointer_down or not _touches.is_empty():
		return
	_velocity = Vector2.ZERO
	var distance: Vector2 = direction.limit_length(1.0) * KEYBOARD_PIXELS_PER_SECOND * clampf(delta, 0.0, 0.1)
	camera_center = clamp_camera(camera_center + distance / cell_pixels(), size, world_size(), cell_pixels())
	queue_redraw()


func keyboard_zoom(factor: float) -> void:
	if factor <= 0.0 or _pointer_down or not _touches.is_empty():
		return
	_zoom_at(size * 0.5, zoom * factor)


func focus_tile(x: int, y: int) -> void:
	_velocity = Vector2.ZERO
	camera_center = clamp_camera(Vector2(float(x) + 0.5, float(y) + 0.5), size, world_size(), cell_pixels())
	selected_tile = _tile_at(Vector2i(clampi(x, 0, int(world["width"]) - 1), clampi(y, 0, int(world["height"]) - 1)))
	queue_redraw()


func set_filter(kind: String) -> void:
	filter_kind = kind if kind in ["all", "cities", "resources", "marches", "tasks"] else "all"
	queue_redraw()


func world_size() -> Vector2:
	return Vector2(float(world.get("width", 64)), float(world.get("height", 64)))


func cell_pixels() -> float:
	return BASE_CELL * zoom


func world_to_screen(position: Vector2) -> Vector2:
	return (position - camera_center) * cell_pixels() + size * 0.5


func screen_to_world(position: Vector2) -> Vector2:
	return camera_center + (position - size * 0.5) / cell_pixels()


static func clamp_camera(center: Vector2, viewport: Vector2, dimensions: Vector2, pixels: float) -> Vector2:
	var half: Vector2 = viewport / maxf(1.0, pixels) * 0.5
	var result: Vector2 = center
	result.x = dimensions.x * 0.5 if half.x * 2.0 >= dimensions.x else clampf(center.x, half.x, dimensions.x - half.x)
	result.y = dimensions.y * 0.5 if half.y * 2.0 >= dimensions.y else clampf(center.y, half.y, dimensions.y - half.y)
	return result


static func anchored_camera(center: Vector2, anchor: Vector2, viewport: Vector2, before_pixels: float, after_pixels: float) -> Vector2:
	var offset: Vector2 = anchor - viewport * 0.5
	return center + offset / maxf(1.0, before_pixels) - offset / maxf(1.0, after_pixels)


static func march_fraction(march: Dictionary, now_ms: float) -> float:
	var start_value: Variant = march.get("start", 0.0)
	var arrive_value: Variant = march.get("arrive", null)
	if not (arrive_value is int or arrive_value is float):
		return 1.0
	var start_ms: float = float(start_value) if start_value is int or start_value is float else 0.0
	var arrive_ms: float = float(arrive_value)
	if arrive_ms <= start_ms:
		return 1.0
	return clampf((now_ms - start_ms) / (arrive_ms - start_ms), 0.0, 1.0)


static func march_world_position(march: Dictionary, now_ms: float) -> Vector2:
	var origin: Dictionary = march.get("from", {})
	var target: Dictionary = march.get("to", {})
	var from_position: Vector2 = Vector2(float(origin.get("x", 0)) + 0.5, float(origin.get("y", 0)) + 0.5)
	var to_position: Vector2 = Vector2(float(target.get("x", 0)) + 0.5, float(target.get("y", 0)) + 0.5)
	return from_position.lerp(to_position, march_fraction(march, now_ms))


static func format_eta(seconds: float) -> String:
	var remaining: int = maxi(0, ceili(seconds))
	if remaining >= 3600:
		return "%d时%02d分" % [remaining / 3600, (remaining % 3600) / 60]
	if remaining >= 60:
		return "%d分%02d秒" % [remaining / 60, remaining % 60]
	return "%d秒" % remaining


func _on_resized() -> void:
	camera_center = clamp_camera(camera_center, size, world_size(), cell_pixels())
	queue_redraw()


func _process(delta: float) -> void:
	if not _pointer_down and _touches.is_empty() and _velocity.length_squared() > 0.05:
		var before: Vector2 = camera_center
		camera_center = clamp_camera(camera_center + _velocity * delta, size, world_size(), cell_pixels())
		_velocity *= exp(-INERTIA_DECAY * delta)
		if is_equal_approx(camera_center.x, before.x):
			_velocity.x = 0.0
		if is_equal_approx(camera_center.y, before.y):
			_velocity.y = 0.0
		queue_redraw()
	_march_redraw_elapsed += delta
	var moving_now: bool = false
	var now_ms: float = Time.get_unix_time_from_system() * 1000.0
	for item: Variant in world.get("marches", []):
		if item is Dictionary and march_fraction(item, now_ms) < 1.0:
			moving_now = true
			break
	if (moving_now and _march_redraw_elapsed >= 0.05) or (_march_animated and not moving_now):
		_march_redraw_elapsed = 0.0
		queue_redraw()
	_march_animated = moving_now


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_at(button.position, zoom * 1.12)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_at(button.position, zoom / 1.12)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			# Ignore the compatibility mouse event generated by real touch input.
			if not _touches.is_empty() or button.device == -1:
				return
			if button.pressed:
				_begin_pointer(button.position)
			else:
				_end_pointer(button.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		_last_hover = motion.position
		if _pointer_down:
			_move_pointer(motion.position)
			accept_event()
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_touches[touch.index] = touch.position
			_velocity = Vector2.ZERO
			if _touches.size() == 1:
				_touch_gesture_dragged = false
				_begin_pointer(touch.position)
			elif _touches.size() == 2:
				_pointer_down = false
				_touch_gesture_dragged = true
				_begin_pinch()
		else:
			var was_pinch: bool = _touch_gesture_dragged
			_touches.erase(touch.index)
			if _touches.is_empty():
				if not was_pinch:
					_end_pointer(touch.position)
				_pointer_down = false
				_pinch_distance = 0.0
			elif _touches.size() == 1:
				_begin_pointer(Vector2(_touches.values()[0]))
				_dragged = true
				_touch_gesture_dragged = true
		accept_event()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		_touches[drag.index] = drag.position
		if _touches.size() >= 2:
			_update_pinch()
		elif _pointer_down:
			_move_pointer(drag.position)
		accept_event()
	elif event is InputEventMagnifyGesture:
		var magnify: InputEventMagnifyGesture = event
		_zoom_at(magnify.position, zoom * magnify.factor)
		accept_event()
	elif event is InputEventPanGesture:
		var pan: InputEventPanGesture = event
		camera_center = clamp_camera(camera_center + pan.delta * 18.0 / cell_pixels(), size, world_size(), cell_pixels())
		queue_redraw()
		accept_event()


func _begin_pointer(position: Vector2) -> void:
	if is_inside_tree():
		grab_focus()
	_pointer_down = true
	_pointer_start = position
	_pointer_previous = position
	_dragged = false
	_velocity = Vector2.ZERO
	_last_move_ms = Time.get_ticks_msec()


func _move_pointer(position: Vector2) -> void:
	var now: int = Time.get_ticks_msec()
	var elapsed: float = maxf(0.008, float(now - _last_move_ms) / 1000.0)
	if position.distance_to(_pointer_start) >= DRAG_THRESHOLD:
		_dragged = true
	if _dragged:
		var offset: Vector2 = (position - _pointer_previous) / cell_pixels()
		camera_center = clamp_camera(camera_center - offset, size, world_size(), cell_pixels())
		_velocity = _velocity.lerp(-offset / elapsed, 0.55)
		_velocity = _velocity.limit_length(35.0)
		queue_redraw()
	_pointer_previous = position
	_last_move_ms = now


func _end_pointer(position: Vector2) -> void:
	if not _pointer_down:
		return
	_pointer_down = false
	if not _dragged:
		_velocity = Vector2.ZERO
		_select_at(position)
	elif Time.get_ticks_msec() - _last_move_ms > 120:
		_velocity = Vector2.ZERO


func _begin_pinch() -> void:
	var positions: Array = _touches.values()
	_pinch_midpoint = (Vector2(positions[0]) + Vector2(positions[1])) * 0.5
	_pinch_distance = Vector2(positions[0]).distance_to(Vector2(positions[1]))


func _update_pinch() -> void:
	var positions: Array = _touches.values()
	var midpoint: Vector2 = (Vector2(positions[0]) + Vector2(positions[1])) * 0.5
	var distance: float = Vector2(positions[0]).distance_to(Vector2(positions[1]))
	if _pinch_distance > 4.0 and distance > 4.0:
		var next_zoom: float = clampf(zoom * distance / _pinch_distance, MIN_ZOOM, MAX_ZOOM)
		var old_pixels: float = cell_pixels()
		var old_anchor_world: Vector2 = screen_to_world(_pinch_midpoint)
		zoom = next_zoom
		camera_center = old_anchor_world - (midpoint - size * 0.5) / cell_pixels()
		camera_center = clamp_camera(camera_center, size, world_size(), cell_pixels())
		if old_pixels > 0.0:
			queue_redraw()
	_pinch_midpoint = midpoint
	_pinch_distance = distance


func _zoom_at(anchor: Vector2, next_zoom: float) -> void:
	var bounded: float = clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	camera_center = anchored_camera(camera_center, anchor, size, cell_pixels(), BASE_CELL * bounded)
	zoom = bounded
	camera_center = clamp_camera(camera_center, size, world_size(), cell_pixels())
	_velocity = Vector2.ZERO
	queue_redraw()


func _select_at(position: Vector2) -> void:
	var location: Vector2 = screen_to_world(position)
	var coordinates: Vector2i = Vector2i(floori(location.x), floori(location.y))
	if coordinates.x < 0 or coordinates.y < 0 or coordinates.x >= int(world["width"]) or coordinates.y >= int(world["height"]):
		return
	var tile: Dictionary = _tile_at(coordinates)
	if not bool(tile.get("selectable", true)) or bool(tile.get("hidden", false)):
		return
	selected_tile = tile
	tile_selected.emit(selected_tile.duplicate(true))
	queue_redraw()


func _tile_at(coordinates: Vector2i) -> Dictionary:
	if _tile_index.has(coordinates):
		return _tile_index[coordinates]
	return {"id": "wild-%d-%d" % [coordinates.x, coordinates.y], "x": coordinates.x, "y": coordinates.y, "name": "未勘察野地", "terrain": _terrain_at(coordinates), "kind": "wild", "level": 1, "owned": false}


func _terrain_at(coordinates: Vector2i) -> String:
	if _tile_index.has(coordinates):
		return str(_tile_index[coordinates].get("terrain", "plain"))
	var ridge: float = sin(float(coordinates.x) * 0.15 + cos(float(coordinates.y) * 0.11) * 2.6)
	var forest: float = sin(float(coordinates.x) * 0.23) * cos(float(coordinates.y) * 0.18)
	if ridge > 0.82:
		return "mountain"
	if forest > 0.35:
		return "forest"
	return "plain"


func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color("171f20"))
	var map_rect: Rect2 = Rect2(world_to_screen(Vector2.ZERO), world_size() * cell_pixels())
	draw_rect(map_rect, Color("6b7152"))
	var top_left: Vector2 = screen_to_world(Vector2.ZERO)
	var bottom_right: Vector2 = screen_to_world(size)
	var min_x: int = clampi(floori(top_left.x) - 2, 0, int(world["width"]) - 1)
	var max_x: int = clampi(ceili(bottom_right.x) + 2, 0, int(world["width"]) - 1)
	var min_y: int = clampi(floori(top_left.y) - 2, 0, int(world["height"]) - 1)
	var max_y: int = clampi(ceili(bottom_right.y) + 2, 0, int(world["height"]) - 1)
	_draw_landform(min_x, max_x, min_y, max_y)
	_draw_rivers()
	if zoom < 0.46:
		_draw_regions()
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var coordinates: Vector2i = Vector2i(x, y)
			var tile: Dictionary = _tile_at(coordinates)
			_draw_tile_features(tile, coordinates)
	if zoom >= 1.05:
		_draw_grid(min_x, max_x, min_y, max_y)
	if not selected_tile.is_empty():
		var selected_position: Vector2 = Vector2(float(selected_tile.get("x", 0)), float(selected_tile.get("y", 0)))
		var rectangle: Rect2 = Rect2(world_to_screen(selected_position) + Vector2(3, 3), Vector2.ONE * cell_pixels() - Vector2(6, 6))
		draw_rect(rectangle, Color(GOLD, 0.12), true)
		draw_rect(rectangle, GOLD, false, 2.0)
	_draw_marches()
	_draw_compass()
	_draw_map_status()
	draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 1.0)


func _draw_landform(min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var position: Vector2 = world_to_screen(Vector2(x, y))
			var terrain: String = _terrain_at(Vector2i(x, y))
			var wave: float = sin(float(x) * 0.16 + float(y) * 0.10) * 0.026
			var color: Color = Color(0.43 + wave, 0.46 + wave, 0.33 + wave)
			if terrain in ["forest", "wood", "woods"]:
				color = Color(0.29 + wave, 0.38 + wave, 0.29 + wave)
			elif terrain in ["mountain", "stone", "iron", "hill"]:
				color = Color(0.43 + wave, 0.44 + wave, 0.39 + wave)
			elif terrain in ["water", "lake", "river"]:
				color = Color("4f7173")
			elif terrain in ["desert", "wasteland"]:
				color = Color(0.56 + wave, 0.49 + wave, 0.35 + wave)
			draw_rect(Rect2(position, Vector2.ONE * (cell_pixels() + 1.0)), color)
			# Rounded overlapping shadows connect terrain across tile boundaries.
			if terrain in ["forest", "wood", "woods"]:
				draw_circle(position + Vector2.ONE * cell_pixels() * 0.5, cell_pixels() * 0.72, Color(0.20, 0.30, 0.24, 0.16))
			elif terrain in ["mountain", "stone", "iron", "hill"]:
				draw_circle(position + Vector2.ONE * cell_pixels() * 0.5, cell_pixels() * 0.70, Color(0.27, 0.28, 0.27, 0.10))


func _river_world_x(y: float) -> float:
	# Match the legacy world's stable lake corridor without altering tile rules.
	return 15.0 + sin(y / 7.0) * 4.0


func _draw_rivers() -> void:
	var river: PackedVector2Array = PackedVector2Array()
	var tributary: PackedVector2Array = PackedVector2Array()
	for step: int in range(int(world["height"]) * 3 + 1):
		var y: float = float(step) / 3.0
		river.append(world_to_screen(Vector2(_river_world_x(y), y)))
		var x: float = float(step) / float(int(world["height"]) * 3) * world_size().x
		tributary.append(world_to_screen(Vector2(x, 41.0 + sin(x * 0.10) * 3.5)))
	draw_polyline(river, Color("566c60"), maxf(3.0, cell_pixels() * 0.56), true)
	draw_polyline(river, Color("527b82"), maxf(2.0, cell_pixels() * 0.36), true)
	draw_polyline(river, Color(0.58, 0.73, 0.72, 0.22), maxf(1.0, cell_pixels() * 0.07), true)
	draw_polyline(tributary, Color("527477"), maxf(2.0, cell_pixels() * 0.24), true)
	# A dry road follows the principal valley; all routes remain visual overlays.
	var road: PackedVector2Array = PackedVector2Array()
	for step: int in range(int(world["height"]) + 1):
		var y: float = float(step)
		road.append(world_to_screen(Vector2(_river_world_x(y) + 2.2, y)))
	draw_polyline(road, Color(0.75, 0.65, 0.43, 0.44), maxf(1.0, cell_pixels() * 0.055), true)


func _draw_regions() -> void:
	for value: Variant in regions:
		if not value is Dictionary:
			continue
		var region: Dictionary = value
		var bounds: Array = region.get("bounds", [0, 0, 1, 1])
		var position: Vector2 = Vector2(float(bounds[0]), float(bounds[1]))
		var dimensions: Vector2 = Vector2(float(bounds[2]), float(bounds[3]))
		var rect: Rect2 = Rect2(world_to_screen(position), dimensions * cell_pixels())
		if not rect.intersects(Rect2(Vector2.ZERO, size)):
			continue
		var color: Color = Color(str(region.get("color", "8c937d")))
		draw_rect(rect.grow(-3.0), Color(color, 0.06), true)
		draw_rect(rect.grow(-3.0), Color(GOLD, 0.40), false, 1.0)
		var center: Vector2 = world_to_screen(position + dimensions * 0.5)
		_draw_centered_text(str(region.get("name", "")), center, 27, Color(TEXT, 0.88))
		_draw_centered_text("试玩分区", center + Vector2(0, 22), 11, Color(TEXT, 0.55))


func _draw_tile_features(tile: Dictionary, coordinates: Vector2i) -> void:
	var center: Vector2 = world_to_screen(Vector2(coordinates) + Vector2.ONE * 0.5)
	var terrain: String = str(tile.get("terrain", _terrain_at(coordinates)))
	var tile_kind: String = str(tile.get("kind", "wild"))
	var tile_id: String = str(tile.get("id", ""))
	var home: Dictionary = world.get("home", {})
	var is_home: bool = coordinates.x == int(home.get("x", -1)) and coordinates.y == int(home.get("y", -1))
	var is_city: bool = is_home or tile_kind in ["home", "city", "county", "prefecture", "province", "capital", "yellow_city", "named_city", "town"] or tile_id.begins_with("city-")
	var is_task: bool = tile_kind in ["task", "quest", "mission", "chapter", "landmark"] or bool(tile.get("task", false))
	if zoom >= 0.46 and not is_city:
		if terrain in ["forest", "wood", "woods"]:
			_draw_forest(center, coordinates)
		elif terrain in ["mountain", "stone", "iron", "hill"]:
			_draw_mountain(center, coordinates)
		elif zoom >= 0.75 and terrain in ["plain", "farm", "food", "grass"]:
			_draw_fields(center, coordinates)
	if is_city:
		if filter_kind in ["all", "cities", "marches"] or is_home:
			_draw_city(center, tile, is_home)
	elif is_task and zoom >= 0.43 and filter_kind in ["all", "tasks"]:
		_draw_task(center, tile)
	elif zoom >= 0.80 and filter_kind == "resources":
		var short_label: String = "粮"
		if terrain in ["forest", "wood", "woods"]:
			short_label = "木"
		elif terrain in ["mountain", "stone", "hill"]:
			short_label = "石"
		elif terrain == "iron":
			short_label = "铁"
		_draw_badge(center + Vector2(0, -3), short_label, Color("394a40"))


func _draw_forest(center: Vector2, coordinates: Vector2i) -> void:
	var radius: float = cell_pixels() * 0.075
	for tree: int in range(5):
		var seed_value: float = float(coordinates.x * 37 + coordinates.y * 17 + tree * 29)
		var offset: Vector2 = Vector2(sin(seed_value) * 0.34, cos(seed_value * 1.7) * 0.27) * cell_pixels()
		var point: Vector2 = center + offset
		draw_line(point + Vector2(0, radius), point + Vector2(0, radius * 2.0), Color("554b35"), maxf(1.0, zoom))
		draw_circle(point + Vector2(1, 2), radius * 1.22, Color(0.09, 0.18, 0.15, 0.32))
		draw_circle(point, radius, Color("314c3a"))
		draw_circle(point + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.62, Color("48604a"))


func _draw_mountain(center: Vector2, coordinates: Vector2i) -> void:
	var unit: float = cell_pixels() * 0.25
	var shift: float = sin(float(coordinates.x * 11 + coordinates.y * 3)) * unit * 0.35
	var left: Vector2 = center + Vector2(-unit, unit * 0.45)
	var peak: Vector2 = center + Vector2(shift, -unit * 0.70)
	var right: Vector2 = center + Vector2(unit, unit * 0.45)
	draw_colored_polygon(PackedVector2Array([left + Vector2(2, 2), peak + Vector2(2, 2), right + Vector2(2, 2)]), Color(0.11, 0.13, 0.13, 0.25))
	draw_colored_polygon(PackedVector2Array([left, peak, right]), Color("696e62"))
	draw_colored_polygon(PackedVector2Array([peak, center + Vector2(shift * 0.3, unit * 0.45), right]), Color("4d574e"))
	draw_line(left, peak, Color(0.83, 0.81, 0.66, 0.42), maxf(1.0, zoom))


func _draw_fields(center: Vector2, coordinates: Vector2i) -> void:
	if (coordinates.x * 3 + coordinates.y * 7) % 5 != 0:
		return
	var unit: float = cell_pixels() * 0.18
	for row: int in range(3):
		var offset: float = float(row - 1) * unit * 0.45
		draw_line(center + Vector2(-unit, offset + unit * 0.30), center + Vector2(unit, offset - unit * 0.30), Color(0.79, 0.71, 0.43, 0.27), maxf(1.0, zoom))


func _draw_city(center: Vector2, tile: Dictionary, is_home: bool) -> void:
	var marker_size: float = clampf(cell_pixels() * 0.30, 6.0, 19.0)
	var flag_color: Color = Color("b78053")
	if is_home or bool(tile.get("owned", false)):
		flag_color = Color("e2c181")
	elif str(tile.get("relation", "")) in ["allied", "friendly", "ally"]:
		flag_color = Color("75afba")
	elif str(tile.get("relation", "")) in ["enemy", "hostile"]:
		flag_color = Color("c9715e")
	elif str(tile.get("kind", "")) == "yellow_city":
		flag_color = Color("d3b447")
	draw_circle(center + Vector2(1, marker_size * 0.25), marker_size * 1.10, Color(0.08, 0.10, 0.09, 0.32))
	var fort: Rect2 = Rect2(center + Vector2(-marker_size * 0.85, -marker_size * 0.25), Vector2(marker_size * 1.70, marker_size * 1.02))
	draw_rect(fort, Color("777a69"))
	draw_rect(fort, Color("c4bea0"), false, maxf(1.0, zoom))
	for crenel: int in range(3):
		var crenel_position: Vector2 = fort.position + Vector2(marker_size * 0.12 + float(crenel) * marker_size * 0.58, -marker_size * 0.20)
		draw_rect(Rect2(crenel_position, Vector2(marker_size * 0.30, marker_size * 0.31)), Color("c0bda3"))
	draw_rect(Rect2(center + Vector2(-marker_size * 0.18, marker_size * 0.18), Vector2(marker_size * 0.36, marker_size * 0.59)), Color("343e38"))
	var pole_top: Vector2 = center + Vector2(marker_size * 0.57, -marker_size * 1.55)
	draw_line(center + Vector2(marker_size * 0.57, -marker_size * 0.17), pole_top, GOLD, maxf(1.0, zoom))
	draw_colored_polygon(PackedVector2Array([pole_top, pole_top + Vector2(marker_size * 0.93, marker_size * 0.08), pole_top + Vector2(marker_size * 0.70, marker_size * 0.53), pole_top + Vector2(0, marker_size * 0.46)]), flag_color)
	if zoom >= 0.50 or is_home:
		var name: String = str(tile.get("name", "主城" if is_home else "城池"))
		_draw_label(name, center + Vector2(0, marker_size + 15), 14 if zoom >= 0.8 else 12, TEXT)
	if zoom >= 1.00:
		_draw_centered_text("Lv.%d" % int(tile.get("level", 1)), center + Vector2(0, marker_size + 31), 11, Color(TEXT, 0.70))


func _draw_task(center: Vector2, tile: Dictionary) -> void:
	var radius: float = clampf(cell_pixels() * 0.16, 5.0, 12.0)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0)]), Color("aa8452"))
	draw_polyline(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0), center + Vector2(0, -radius)]), GOLD, 1.0, true)
	if zoom >= 0.75:
		_draw_label(str(tile.get("name", "任务据点")), center + Vector2(0, radius + 15), 12, TEXT)


func _draw_grid(min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	var grid_color: Color = Color(0.88, 0.85, 0.69, 0.11)
	for x: int in range(min_x, max_x + 2):
		draw_line(world_to_screen(Vector2(x, min_y)), world_to_screen(Vector2(x, max_y + 1)), grid_color, 1.0)
	for y: int in range(min_y, max_y + 2):
		draw_line(world_to_screen(Vector2(min_x, y)), world_to_screen(Vector2(max_x + 1, y)), grid_color, 1.0)


func _draw_marches() -> void:
	if not filter_kind in ["all", "marches"]:
		return
	var now_ms: float = Time.get_unix_time_from_system() * 1000.0
	for item: Variant in world.get("marches", []):
		if not item is Dictionary:
			continue
		var march: Dictionary = item
		var from_data: Dictionary = march.get("from", {})
		var to_data: Dictionary = march.get("to", {})
		var start: Vector2 = world_to_screen(Vector2(float(from_data.get("x", 0)) + 0.5, float(from_data.get("y", 0)) + 0.5))
		var target: Vector2 = world_to_screen(Vector2(float(to_data.get("x", 0)) + 0.5, float(to_data.get("y", 0)) + 0.5))
		var position: Vector2 = world_to_screen(march_world_position(march, now_ms))
		var route_color: Color = Color("7bafb4") if str(march.get("status", "")) in ["return", "returning"] else Color("ccb37c")
		if zoom >= 0.36:
			_draw_dashed_line(start, target, Color(route_color, 0.65), 1.5)
		if not Rect2(Vector2(-120, -35), size + Vector2(240, 70)).has_point(position):
			continue
		draw_circle(position, 7.0, Color("202b2b"))
		draw_arc(position, 7.0, 0.0, TAU, 16, route_color, 1.5, true)
		draw_colored_polygon(PackedVector2Array([position + Vector2(0, -4), position + Vector2(4, 3), position + Vector2(-4, 3)]), route_color)
		if zoom >= 0.40:
			var status: String = str(march.get("status", "moving"))
			var arrive_value: Variant = march.get("arrive", null)
			var arrival: float = float(arrive_value) if arrive_value is int or arrive_value is float else now_ms
			var remaining: float = maxf(0.0, (arrival - now_ms) / 1000.0)
			var eta: String = "已抵达" if remaining <= 0.0 else format_eta(remaining)
			if status in ["stationed", "garrison", "gathering"]:
				eta = "采集中" if status == "gathering" else "驻扎"
			_draw_label("%s · %s" % [str(march.get("label", "行军部队")), eta], position + Vector2(0, -15), 12, route_color)


func _draw_dashed_line(start: Vector2, target: Vector2, color: Color, width: float) -> void:
	var direction: Vector2 = target - start
	var length: float = direction.length()
	if length < 1.0:
		return
	direction /= length
	# Clip iteration to the visible portion even for long routes offscreen.
	var steps: int = mini(600, ceili(length / 15.0))
	for step: int in range(steps):
		var point: Vector2 = start + direction * float(step) * 15.0
		if Rect2(Vector2(-16, -16), size + Vector2(32, 32)).has_point(point):
			draw_line(point, start + direction * minf(length, float(step) * 15.0 + 8.0), color, width, true)


func _draw_compass() -> void:
	var center: Vector2 = Vector2(size.x - 31, 37)
	draw_circle(center, 22.0, Color(0.07, 0.10, 0.10, 0.68))
	draw_arc(center, 22.0, 0.0, TAU, 32, Color(GOLD, 0.60), 1.0, true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -16), center + Vector2(5, 9), center, center + Vector2(-5, 9)]), GOLD)
	_draw_centered_text("北", center + Vector2(0, -24), 11, TEXT)


func _draw_map_status() -> void:
	var mode: String = "近景" if zoom >= 1.05 else ("区域" if zoom >= 0.46 else "分区")
	var label: String = "%s · %.0f%% · (%d,%d)" % [mode, zoom * 100.0, floori(camera_center.x), floori(camera_center.y)]
	var panel: Rect2 = Rect2(Vector2(12, size.y - 35), Vector2(235, 24))
	draw_rect(panel, Color(0.07, 0.10, 0.10, 0.80))
	draw_string(_font, panel.position + Vector2(8, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(TEXT, 0.85))
	if size.x > 650:
		_draw_label("拖动浏览 · 滚轮缩放 · 双指缩放", Vector2(size.x - 144, size.y - 19), 12, Color(TEXT, 0.65))


func _draw_badge(center: Vector2, label: String, color: Color) -> void:
	draw_circle(center, 11.0, Color(0.10, 0.13, 0.12, 0.40))
	draw_circle(center, 9.0, color)
	_draw_centered_text(label, center + Vector2(0, 4), 12, TEXT)


func _draw_centered_text(label: String, position: Vector2, font_size: int, color: Color) -> void:
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(_font, position - Vector2(width * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_label(label: String, position: Vector2, font_size: int, color: Color) -> void:
	var text_size: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var rectangle: Rect2 = Rect2(position - Vector2(text_size.x * 0.5 + 5, font_size - 2), Vector2(text_size.x + 10, font_size + 6))
	draw_rect(rectangle, Color(0.07, 0.10, 0.10, 0.72))
	_draw_centered_text(label, position, font_size, color)
