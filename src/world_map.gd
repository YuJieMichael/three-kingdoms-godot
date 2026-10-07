extends Control
class_name KingdomWorldMap

## A viewport renderer for the authoritative world DTO. Camera positions use tile
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
const BORDER: Color = Color("756346")
const CITY_KINDS: Dictionary = {"home": true, "city": true, "county": true, "prefecture": true, "province": true, "capital": true, "yellow_city": true, "named_city": true, "town": true}
const TASK_KINDS: Dictionary = {"task": true, "quest": true, "mission": true, "chapter": true, "landmark": true}
const DECORATION_CACHE_LIMIT: int = 2048
const TREE_TRUNK: Color = Color("51432d")
const TREE_SHADOW: Color = Color(0.09, 0.13, 0.10, 0.38)
const TREE_CROWN: Color = Color("3d4a35")
const TREE_HIGHLIGHT: Color = Color("667052")
const MOUNTAIN_SHADOW: Color = Color(0.13, 0.12, 0.10, 0.28)
const MOUNTAIN_FACE: Color = Color("958672")
const MOUNTAIN_SHADE: Color = Color("665e53")
const MOUNTAIN_EDGE: Color = Color(0.89, 0.82, 0.64, 0.62)
const EARTH: Color = Color("92906b")
const FOREST_EARTH: Color = Color("677450")
const HILL_EARTH: Color = Color("85806b")
const DRY_EARTH: Color = Color("b29a71")
const WATER: Color = Color("4b6465")

var world: Dictionary = {"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [], "marches": []}
var camera_center: Vector2 = Vector2(32.5, 32.5)
var zoom: float = 1.05
var show_grid: bool = false
var selected_tile: Dictionary = {}
var filter_kind: String = "all"
var regions: Array = []
var _tile_index: Dictionary = {}
var _feature_coordinates: Array[Vector2i] = []
var _pending_arrival_marches: Array[Dictionary] = []
var _forest_offset_cache: Dictionary = {}
var _mountain_shift_cache: Dictionary = {}
var _map_art_image: Image
var _city_hit_regions: Array[Dictionary] = []
var _server_clock_ms: float = 0.0
var _server_clock_tick: int = 0
var _map_art_texture: Texture2D
var _map_art_sprites: Dictionary = {}
var _terrain_art_sprites: Dictionary = {}
var _hover_coordinate: Vector2i = Vector2i(-1, -1)
var _map_label_rects: Array[Rect2] = []
var _landscape_pass_complete: bool = false
var _landform_mesh: ArrayMesh
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
	_load_map_art()
	_load_terrain_art()
	mouse_exited.connect(func() -> void:
		_hover_coordinate = Vector2i(-1, -1)
		tooltip_text = ""
		queue_redraw())
	resized.connect(_on_resized)
	set_process(true)
	queue_redraw()


func _load_map_art(path: String = "res://data/world-map-art-atlas.json") -> void:
	_map_art_sprites.clear()
	_map_art_texture = null
	_map_art_image = null
	_city_hit_regions.clear()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var texture_path: String = str(parsed.get("texture", ""))
	if not ResourceLoader.exists(texture_path, "Texture2D"):
		return
	_map_art_texture = load(texture_path) as Texture2D
	if _map_art_texture == null or not parsed.get("regions", {}) is Dictionary:
		return
	_map_art_image = _map_art_texture.get_image()
	for id: Variant in parsed["regions"]:
		var values: Variant = parsed["regions"][id]
		if not values is Array or values.size() != 4:
			continue
		var region: Rect2 = Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
		if region.size.x <= 0 or region.size.y <= 0 or not Rect2(Vector2.ZERO, _map_art_texture.get_size()).encloses(region):
			continue
		var sprite: AtlasTexture = AtlasTexture.new()
		sprite.atlas = _map_art_texture
		sprite.region = region
		sprite.filter_clip = true
		_map_art_sprites[str(id)] = sprite


func map_art_loaded() -> bool:
	return _map_art_sprites.size() == 6


func _load_terrain_art() -> void:
	_terrain_art_sprites.clear()
	var path: String = "res://data/world-terrain-art-atlas.json"
	if not FileAccess.file_exists(path):
		return
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not metadata is Dictionary:
		return
	var texture_path: String = str(metadata.get("texture", ""))
	if not ResourceLoader.exists(texture_path, "Texture2D"):
		return
	var texture: Texture2D = load(texture_path) as Texture2D
	for id: Variant in metadata.get("regions", {}):
		var row: Array = metadata.regions[id]
		if row.size() != 4:
			continue
		var region: Rect2 = Rect2(float(row[0]), float(row[1]), float(row[2]), float(row[3]))
		if region.size.x <= 0 or region.size.y <= 0 or not Rect2(Vector2.ZERO, texture.get_size()).encloses(region):
			continue
		var sprite: AtlasTexture = AtlasTexture.new()
		sprite.atlas = texture
		sprite.region = region
		sprite.filter_clip = true
		_terrain_art_sprites[str(id)] = sprite


func _draw_terrain_sprite(terrain: String, center: Vector2, coordinates: Vector2i) -> bool:
	var variant: String = "a" if (coordinates.x * 17 + coordinates.y * 7) % 3 == 0 else "b"
	var normalized: String = str({"field":"plain", "farm":"plain", "food":"grass", "wood":"forest", "woods":"forest", "stone":"mountain", "iron":"mountain", "desert":"hill", "wasteland":"hill"}.get(terrain, terrain))
	var key: String = "%s_%s" % [normalized, variant]
	if not _terrain_art_sprites.has(key):
		return false
	var sprite: AtlasTexture = _terrain_art_sprites[key]
	# Small deterministic offsets break identical rows while staying inside the
	# authoritative cell: tapping the image still selects its actual location.
	var pixels: float = cell_pixels()
	var offset: Vector2 = Vector2(sin(float(coordinates.x * 29 + coordinates.y * 13)) * 0.045, 0.10 + cos(float(coordinates.x * 7 + coordinates.y * 19)) * 0.025) * pixels
	var extent: Vector2 = Vector2.ONE * pixels * (0.83 + sin(float(coordinates.x * 11 + coordinates.y * 31)) * 0.035)
	draw_texture_rect(sprite, _map_sprite_rect(sprite, center + offset, extent), false)
	return true


func set_grid_visible(enabled: bool) -> void:
	show_grid = enabled
	queue_redraw()


func map_art_regions() -> Dictionary:
	var result: Dictionary = {}
	for id: Variant in _map_art_sprites:
		result[id] = (_map_art_sprites[id] as AtlasTexture).region
	return result


func _map_sprite_rect(sprite: AtlasTexture, center: Vector2, extent: Vector2) -> Rect2:
	var scale_factor: float = minf(extent.x / sprite.get_width(), extent.y / sprite.get_height())
	var dimensions: Vector2 = sprite.get_size() * scale_factor
	return Rect2(center + Vector2(-dimensions.x * 0.5, cell_pixels() * 0.31 - dimensions.y), dimensions)


func _map_now_ms() -> float:
	if _server_clock_ms > 0.0:
		return _server_clock_ms + float(Time.get_ticks_usec() - _server_clock_tick) / 1000.0
	return Time.get_unix_time_from_system() * 1000.0


func _draw_map_sprite(id: String, center: Vector2, extent: Vector2) -> bool:
	if not _map_art_sprites.has(id):
		return false
	var sprite: AtlasTexture = _map_art_sprites[id] as AtlasTexture
	draw_texture_rect(sprite, _map_sprite_rect(sprite, center, extent), false)
	return true


static func city_tier_label(tile: Dictionary, is_home: bool = false) -> String:
	if is_home:
		return "主城"
	match str(tile.get("tier", "ordinary")):
		"county": return "县"
		"prefecture": return "郡"
		"province": return "州"
		"capital": return "都"
	return "城"


static func city_art_id(tile: Dictionary, is_home: bool = false) -> String:
	return "city" if is_home or str(tile.get("tier", "ordinary")) in ["prefecture", "province", "capital"] else "county"


static func city_art_scale(tile: Dictionary, is_home: bool = false) -> float:
	if is_home: return 1.35
	match str(tile.get("tier", "ordinary")):
		"capital": return 1.60
		"province": return 1.45
		"prefecture": return 1.30
		"county": return 1.15
	return 1.05


func set_world(next_world: Dictionary) -> void:
	var server_time: Variant = next_world.get("serverTime", null)
	_server_clock_ms = float(server_time) if (server_time is int or server_time is float) and is_finite(float(server_time)) and float(server_time) > 0 else 0.0
	_server_clock_tick = Time.get_ticks_usec()
	world = next_world.duplicate(true)
	world["width"] = maxi(1, int(world.get("width", 64)))
	world["height"] = maxi(1, int(world.get("height", 64)))
	_tile_index.clear()
	var features: Dictionary = {}
	for item: Variant in world.get("tiles", []):
		if item is Dictionary:
			var tile: Dictionary = item
			var coordinates: Vector2i = Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0)))
			_tile_index[coordinates] = tile
			if CITY_KINDS.has(str(tile.get("kind", "wild"))) or str(tile.get("id", "")).begins_with("city-") or TASK_KINDS.has(str(tile.get("kind", "wild"))) or bool(tile.get("task", false)):
				features[coordinates] = true
			else:
				features.erase(coordinates)
	var home: Dictionary = world.get("home", {})
	features[Vector2i(int(home.get("x", -1)), int(home.get("y", -1)))] = true
	_feature_coordinates.assign(features.keys())
	_feature_coordinates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	_pending_arrival_marches.clear()
	var now_ms: float = _map_now_ms()
	for item: Variant in world.get("marches", []):
		if item is Dictionary and march_fraction(item, now_ms) < 1.0:
			_pending_arrival_marches.append(item)
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
	if _march_redraw_elapsed < 0.05:
		return
	_march_redraw_elapsed = 0.0
	var moving_now: bool = false
	var arrival_visible: bool = false
	var show_marches: bool = filter_kind in ["all", "marches"]
	var now_ms: float = _map_now_ms()
	var marker_bounds: Rect2 = Rect2(Vector2(-120, -35), size + Vector2(240, 70))
	# A long frame can skip the entire visible portion of a short trip. Remember
	# pending arrivals so the destination still appears without waiting for /world.
	for index: int in range(_pending_arrival_marches.size() - 1, -1, -1):
		var march: Dictionary = _pending_arrival_marches[index]
		if march_fraction(march, now_ms) >= 1.0:
			arrival_visible = arrival_visible or (show_marches and marker_bounds.has_point(world_to_screen(march_world_position(march, now_ms))))
			_pending_arrival_marches.remove_at(index)
	if show_marches:
		for item: Variant in world.get("marches", []):
			if item is Dictionary and march_fraction(item, now_ms) < 1.0 and marker_bounds.has_point(world_to_screen(march_world_position(item, now_ms))):
				moving_now = true
				break
	if moving_now or _march_animated or arrival_visible:
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
		else:
			var point: Vector2 = screen_to_world(motion.position)
			var coordinate: Vector2i = Vector2i(floori(point.x), floori(point.y))
			if coordinate != _hover_coordinate:
				_hover_coordinate = coordinate
				var tile: Dictionary = _tile_at(coordinate)
				var visible_target: bool = not bool(tile.get("hidden", false)) and bool(tile.get("selectable", true)) and coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < int(world.width) and coordinate.y < int(world.height)
				tooltip_text = "%s\n%d级 · 点击查看详情" % [str(tile.get("name", "野地")), int(tile.get("level", 0))] if visible_target else ""
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if visible_target else Control.CURSOR_ARROW
				queue_redraw()
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
	# A raised roof may cross the tile edge. Hit only visible, opaque sprite
	# pixels and return the current canonical tile, never a neighbouring plot.
	if _map_art_image != null:
		for index: int in range(_city_hit_regions.size() - 1, -1, -1):
			var hit: Dictionary = _city_hit_regions[index]
			var rect: Rect2 = hit["rect"]
			if not rect.has_point(position): continue
			var current: Dictionary = _tile_at(hit["coordinates"])
			if str(current.get("id", "")) != str(hit["id"]) or bool(current.get("hidden", false)) or not bool(current.get("selectable", true)): continue
			var region: Rect2 = hit["region"]
			var sample: Vector2 = region.position + (position - rect.position) / rect.size * region.size
			if _map_art_image.get_pixel(clampi(int(sample.x), 0, _map_art_image.get_width() - 1), clampi(int(sample.y), 0, _map_art_image.get_height() - 1)).a < 0.35: continue
			coordinates = hit["coordinates"]
			break
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
	draw_rect(Rect2(Vector2.ZERO, size), Color("202221"))
	var map_rect: Rect2 = Rect2(world_to_screen(Vector2.ZERO), world_size() * cell_pixels())
	draw_rect(map_rect, EARTH)
	var top_left: Vector2 = screen_to_world(Vector2.ZERO)
	var bottom_right: Vector2 = screen_to_world(size)
	var min_x: int = clampi(floori(top_left.x) - 2, 0, int(world["width"]) - 1)
	var max_x: int = clampi(ceili(bottom_right.x) + 2, 0, int(world["width"]) - 1)
	var min_y: int = clampi(floori(top_left.y) - 2, 0, int(world["height"]) - 1)
	var max_y: int = clampi(ceili(bottom_right.y) + 2, 0, int(world["height"]) - 1)
	_map_label_rects.clear()
	_city_hit_regions.clear()
	_landscape_pass_complete = false
	_draw_landform(min_x, max_x, min_y, max_y)
	_draw_rivers()
	if zoom < 0.46:
		_draw_regions()
	if zoom >= 0.46:
		for y: int in range(min_y, max_y + 1):
			for x: int in range(min_x, max_x + 1):
				var coordinate: Vector2i = Vector2i(x, y)
				_draw_tile_landscape(_tile_at(coordinate), coordinate)
	_landscape_pass_complete = true
	if not selected_tile.is_empty() and not bool(selected_tile.get("hidden", false)):
		_draw_target_halo(Vector2i(int(selected_tile.get("x", 0)), int(selected_tile.get("y", 0))), true)
	if _hover_coordinate != Vector2i(-1,-1) and not bool(_tile_at(_hover_coordinate).get("hidden", false)):
		_draw_target_halo(_hover_coordinate, false)
	if zoom < 0.46:
		# At overview scale wilderness decorations are already hidden. Visit only
		# landmarks, retaining the same row order and current snapshot contents.
		for coordinates: Vector2i in _feature_coordinates:
			if coordinates.x >= min_x and coordinates.x <= max_x and coordinates.y >= min_y and coordinates.y <= max_y:
				_draw_tile_features(_tile_at(coordinates), coordinates)
	else:
		for y: int in range(min_y, max_y + 1):
			for x: int in range(min_x, max_x + 1):
				var coordinates: Vector2i = Vector2i(x, y)
				_draw_tile_features(_tile_at(coordinates), coordinates)
	if show_grid and zoom >= 0.65:
		_draw_grid(min_x, max_x, min_y, max_y)
	_landscape_pass_complete = false
	_draw_marches()
	_draw_compass()
	_draw_map_status()
	draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 1.0)


func _draw_target_halo(coordinates: Vector2i, selected: bool) -> void:
	var center: Vector2 = world_to_screen(Vector2(coordinates) + Vector2(0.5, 0.68))
	var ring: PackedVector2Array = PackedVector2Array()
	for i: int in range(33):
		var angle: float = TAU * float(i) / 32.0
		ring.append(center + Vector2(cos(angle) * 0.43, sin(angle) * 0.24) * cell_pixels())
	if selected:
		draw_colored_polygon(ring, Color(GOLD, 0.14))
	draw_polyline(ring, GOLD if selected else Color(TEXT, 0.45), 2.5 if selected else 1.2, true)


func _draw_landform(min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	var pixels: float = cell_pixels()
	var columns: int = max_x - min_x + 1
	var rows: int = max_y - min_y + 1
	var terrain_columns: int = columns + 2
	var terrain_colors: PackedColorArray = PackedColorArray()
	# Sample each current terrain tile once, including the neighbour margin.
	# Colors remain redraw-local so changed snapshots cannot leave stale art.
	for y: int in range(min_y - 1, max_y + 2):
		for x: int in range(min_x - 1, max_x + 2):
			var coordinate: Vector2i = Vector2i(clampi(x, 0, int(world["width"]) - 1), clampi(y, 0, int(world["height"]) - 1))
			var color: Color = EARTH
			match _terrain_at(coordinate):
				"forest", "wood", "woods":
					color = FOREST_EARTH
				"mountain", "stone", "iron", "hill":
					color = HILL_EARTH
				"water", "lake", "river":
					color = WATER
				"desert", "wasteland":
					color = DRY_EARTH
			terrain_colors.append(color)
	var vertices: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var vertex_columns: int = columns + 1
	var vertex_count: int = vertex_columns * (rows + 1)
	vertices.resize(vertex_count)
	colors.resize(vertex_count)
	var half_viewport: Vector2 = size * 0.5
	for y: int in range(min_y, max_y + 2):
		for x: int in range(min_x, max_x + 2):
			var index: int = (y - min_y) * vertex_columns + x - min_x
			var terrain_index: int = (y - min_y) * terrain_columns + x - min_x
			var blended: Color = (terrain_colors[terrain_index] + terrain_colors[terrain_index + 1] + terrain_colors[terrain_index + terrain_columns] + terrain_colors[terrain_index + terrain_columns + 1]) * 0.25
			var light: float = sin(float(x) * 0.16 + float(y) * 0.10) * 0.035 + cos(float(y) * 0.28 - float(x) * 0.07) * 0.018
			vertices[index] = (Vector2(x, y) - camera_center) * pixels + half_viewport
			colors[index] = Color(blended.r + light, blended.g + light, blended.b + light, 1.0)
	# One colored mesh avoids triangulating a separate polygon for every cell.
	# Shared vertices keep adjoining terrain edges continuous at every scale.
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize(columns * rows * 6)
	for y: int in range(rows):
		for x: int in range(columns):
			var vertex: int = y * vertex_columns + x
			var index: int = (y * columns + x) * 6
			indices[index] = vertex
			indices[index + 1] = vertex + 1
			indices[index + 2] = vertex + vertex_columns + 1
			indices[index + 3] = vertex
			indices[index + 4] = vertex + vertex_columns + 1
			indices[index + 5] = vertex + vertex_columns
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	# The canvas command stores the RID, so retain the resource through rendering.
	if _landform_mesh == null:
		_landform_mesh = ArrayMesh.new()
	else:
		_landform_mesh.clear_surfaces()
	_landform_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	draw_mesh(_landform_mesh, null)


func _river_world_x(y: float) -> float:
	# Match the legacy world's stable lake corridor without altering tile rules.
	return 15.0 + sin(y / 7.0) * 4.0


func _draw_rivers() -> void:
	var river: PackedVector2Array = PackedVector2Array()
	var tributary: PackedVector2Array = PackedVector2Array()
	var top_left: Vector2 = screen_to_world(Vector2.ZERO)
	var bottom_right: Vector2 = screen_to_world(size)
	var height: int = int(world["height"])
	var last_step: int = height * 3
	# Retain neighbouring samples and the original sampling grid. Widths and
	# anti-aliased ends fit inside the extra world-cell margin.
	var first_y: int = clampi(floori((top_left.y - 1.0) * 3.0) - 1, 0, last_step)
	var last_y: int = clampi(ceili((bottom_right.y + 1.0) * 3.0) + 1, 0, last_step)
	for step: int in range(first_y, last_y + 1):
		var y: float = float(step) / 3.0
		river.append(world_to_screen(Vector2(_river_world_x(y), y)))
	var x_spacing: float = world_size().x / float(last_step)
	var first_x: int = clampi(floori((top_left.x - 1.0) / x_spacing) - 1, 0, last_step)
	var last_x: int = clampi(ceili((bottom_right.x + 1.0) / x_spacing) + 1, 0, last_step)
	for step: int in range(first_x, last_x + 1):
		var x: float = float(step) / float(last_step) * world_size().x
		tributary.append(world_to_screen(Vector2(x, 41.0 + sin(x * 0.10) * 3.5)))
	if river.size() >= 2:
		draw_polyline(river, Color("746e55"), maxf(3.0, cell_pixels() * 0.56), true)
		draw_polyline(river, WATER, maxf(2.0, cell_pixels() * 0.36), true)
		draw_polyline(river, Color(0.67, 0.76, 0.72, 0.26), maxf(1.0, cell_pixels() * 0.07), true)
	if tributary.size() >= 2:
		draw_polyline(tributary, WATER, maxf(2.0, cell_pixels() * 0.24), true)
	# A dry road follows the principal valley; all routes remain visual overlays.
	var road: PackedVector2Array = PackedVector2Array()
	var first_road: int = clampi(floori(top_left.y - 1.0) - 1, 0, height)
	var last_road: int = clampi(ceili(bottom_right.y + 1.0) + 1, 0, height)
	for step: int in range(first_road, last_road + 1):
		var y: float = float(step)
		road.append(world_to_screen(Vector2(_river_world_x(y) + 2.2, y)))
	if road.size() >= 2:
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
	# A future task remains an unmarked landscape even if a DTO contains a name.
	if bool(tile.get("hidden", false)):
		return
	var center: Vector2 = world_to_screen(Vector2(coordinates) + Vector2.ONE * 0.5)
	var terrain: String = str(tile["terrain"]) if tile.has("terrain") else _terrain_at(coordinates)
	var tile_kind: String = str(tile.get("kind", "wild"))
	var tile_id: String = str(tile.get("id", ""))
	var home: Dictionary = world.get("home", {})
	var is_home: bool = coordinates.x == int(home.get("x", -1)) and coordinates.y == int(home.get("y", -1))
	var is_city: bool = is_home or CITY_KINDS.has(tile_kind) or tile_id.begins_with("city-")
	var is_task: bool = TASK_KINDS.has(tile_kind) or bool(tile.get("task", false))
	if not _landscape_pass_complete:
		_draw_tile_landscape(tile, coordinates)
	if is_city:
		if filter_kind in ["all", "cities", "marches"] or is_home:
			_draw_city(center, tile, is_home)
	elif is_task and zoom >= 0.43 and filter_kind in ["all", "tasks"]:
		_draw_task(center, tile)
	elif tile_kind == "wild" and zoom >= 0.70 and filter_kind in ["all", "resources"]:
		var names: Dictionary = {"plain":"平地", "grass":"草原", "forest":"森林", "hill":"荒漠", "mountain":"山地", "lake":"湖泊", "swamp":"沼泽"}
		var active: bool = str(tile.get("id", "")) == str(selected_tile.get("id", ""))
		if active:
			var caption: String = "%s · %d级" % [names.get(terrain, "野地"), int(tile.get("level", 0))]
			var half_width: float = _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x * 0.5 + 9
			var point: Vector2 = center + Vector2(0, cell_pixels() * 0.50 + 12)
			point.x = clampf(point.x, half_width, maxf(half_width, size.x - half_width))
			point.y = clampf(point.y, 24, maxf(24, size.y - 42))
			_draw_map_label(caption, point, 14, GOLD, true)
		elif show_grid or filter_kind == "resources":
			var name: String = str(names.get(terrain, "野地"))
			if filter_kind == "resources":
				name = str({"forest":"木", "hill":"石", "mountain":"铁"}.get(terrain, "粮"))
			_draw_map_label("%s·%d" % [name, int(tile.get("level", 0))], center + Vector2(0, cell_pixels() * 0.35), 12, TEXT)
		if bool(tile.get("owned", false)):
			var flag: Vector2 = center + Vector2(cell_pixels() * 0.28, -cell_pixels() * 0.16)
			draw_line(flag, flag + Vector2(0, 15), GOLD, 1.5)
			draw_colored_polygon(PackedVector2Array([flag, flag + Vector2(10, 3), flag + Vector2(0, 7)]), GOLD)



func _draw_tile_landscape(tile: Dictionary, coordinates: Vector2i) -> void:
	if bool(tile.get("hidden", false)) or zoom < 0.46:
		return
	var home: Dictionary = world.get("home", {})
	if CITY_KINDS.has(str(tile.get("kind", "wild"))) or str(tile.get("id", "")).begins_with("city-") or (coordinates.x == int(home.get("x", -1)) and coordinates.y == int(home.get("y", -1))):
		return
	var center: Vector2 = world_to_screen(Vector2(coordinates) + Vector2.ONE * 0.5)
	var terrain: String = str(tile.get("terrain", _terrain_at(coordinates)))
	if _draw_terrain_sprite(terrain, center, coordinates):
		return
	if bool(world.get("wildRefresh", {}).get("enabled", false)):
		if terrain in ["lake", "swamp"]:
			_draw_wild_water(center, coordinates, terrain == "swamp")
			return
		if terrain == "hill":
			var unit: float = cell_pixels() * 0.35
			draw_colored_polygon(PackedVector2Array([center + Vector2(-unit, unit * 0.3), center + Vector2(-unit * 0.2, -unit * 0.4), center + Vector2(unit, unit * 0.15), center + Vector2(unit * 0.5, unit * 0.5)]), Color("bca16e"))
			draw_line(center + Vector2(-unit * 0.2, -unit * 0.4), center + Vector2(unit, unit * 0.15), Color("dcc08a"), 2.0, true)
			return
	match terrain:
		"forest", "wood", "woods": _draw_forest(center, coordinates)
		"mountain", "stone", "iron", "hill": _draw_mountain(center, coordinates)
		"plain", "farm", "food", "grass":
			if zoom >= 0.75: _draw_fields(center, coordinates)


func _draw_wild_water(center: Vector2, coordinates: Vector2i, swamp: bool) -> void:
	var unit: float = cell_pixels() * 0.38
	var edge: PackedVector2Array = PackedVector2Array()
	for i: int in range(20):
		var angle: float = TAU * float(i) / 20.0
		var radius: float = unit * (1.0 + sin(angle * 3.0 + float(coordinates.x + coordinates.y)) * 0.12)
		edge.append(center + Vector2(cos(angle), sin(angle) * 0.65) * radius)
	draw_colored_polygon(edge, Color("60796b") if swamp else Color("477c8a"))
	var border: PackedVector2Array = edge.duplicate()
	border.append(edge[0])
	draw_polyline(border, Color("a0aa7c") if swamp else Color("8aa7a1"), 1.5, true)
	for row: int in range(3):
		var point: Vector2 = center + Vector2(float(row - 1) * unit * 0.45, float(row % 2) * unit * 0.15)
		if swamp:
			draw_line(point + Vector2(0, unit * 0.15), point + Vector2(-unit * 0.1, -unit * 0.25), Color("a5af70"), 1.5, true)
			draw_line(point + Vector2(0, unit * 0.15), point + Vector2(unit * 0.1, -unit * 0.2), Color("8e9858"), 1.5, true)
		else:
			draw_line(point - Vector2(unit * 0.14, 0), point + Vector2(unit * 0.14, 0), Color("92b2b4"), 1.0, true)


func _draw_forest(center: Vector2, coordinates: Vector2i) -> void:
	var pixels: float = cell_pixels()
	var grove_offset: Vector2 = _forest_offsets(coordinates)[0] * pixels * 0.55
	var variant_id: String = "forest_a" if (coordinates.x * 3 + coordinates.y * 7) % 2 == 0 else "forest_b"
	var variation: float = 1.24 + sin(float(coordinates.x * 17 + coordinates.y * 31)) * 0.12
	if _draw_map_sprite(variant_id, center + grove_offset, Vector2(pixels * variation, pixels * 1.24)):
		return
	for normalized_offset: Vector2 in _forest_offsets(coordinates):
		var radius: float = pixels * (0.105 + normalized_offset.x * 0.055)
		var offset: Vector2 = normalized_offset * pixels
		var point: Vector2 = center + offset
		draw_circle(point + Vector2(radius * 0.30, radius * 0.42), radius * 1.2, TREE_SHADOW)
		draw_line(point + Vector2(0, radius * 0.4), point + Vector2(0, radius * 1.35), TREE_TRUNK, maxf(1.0, zoom))
		draw_circle(point, radius, TREE_CROWN)
		draw_circle(point + Vector2(-radius * 0.30, -radius * 0.32), radius * 0.60, Color(TREE_HIGHLIGHT, 0.75))


func _forest_offsets(coordinates: Vector2i) -> PackedVector2Array:
	if _forest_offset_cache.has(coordinates):
		return _forest_offset_cache[coordinates]
	var offsets: PackedVector2Array = PackedVector2Array()
	for tree: int in range(5):
		var seed_value: float = float(coordinates.x * 37 + coordinates.y * 17 + tree * 29)
		offsets.append(Vector2(sin(seed_value) * 0.34, cos(seed_value * 1.7) * 0.27))
	# Pure coordinate geometry survives world snapshots and zoom changes. Bound
	# the lazy cache so visiting additional provinces cannot grow it forever.
	if _forest_offset_cache.size() >= DECORATION_CACHE_LIMIT:
		_forest_offset_cache.clear()
	_forest_offset_cache[coordinates] = offsets
	return offsets


func _mountain_shift(coordinates: Vector2i) -> float:
	if _mountain_shift_cache.has(coordinates):
		return _mountain_shift_cache[coordinates]
	var shift: float = sin(float(coordinates.x * 11 + coordinates.y * 3)) * 0.35
	if _mountain_shift_cache.size() >= DECORATION_CACHE_LIMIT:
		_mountain_shift_cache.clear()
	_mountain_shift_cache[coordinates] = shift
	return shift


func _draw_mountain(center: Vector2, coordinates: Vector2i) -> void:
	var variant_id: String = "mountain_a" if (coordinates.x * 7 + coordinates.y * 3) % 2 == 0 else "mountain_b"
	var pixels: float = cell_pixels()
	var variation: float = 1.30 + _mountain_shift(coordinates) * 0.26
	var ridge_offset: Vector2 = Vector2(_mountain_shift(coordinates) * 0.32, sin(float(coordinates.x * 7 + coordinates.y * 13)) * 0.18) * pixels
	if _draw_map_sprite(variant_id, center + ridge_offset, Vector2(pixels * variation, pixels * 1.30)):
		return
	var unit: float = cell_pixels() * 0.42
	var shift: float = _mountain_shift(coordinates) * unit
	var ridge_center: Vector2 = center + Vector2(shift * 0.65, sin(float(coordinates.x * 7 + coordinates.y * 13)) * unit * 0.15)
	var height: float = 0.69 + cos(float(coordinates.x * 5 + coordinates.y * 11)) * 0.18
	var left: Vector2 = ridge_center + Vector2(-unit, unit * 0.36)
	var shoulder: Vector2 = ridge_center + Vector2(-unit * 0.58, -unit * 0.18)
	var saddle: Vector2 = ridge_center + Vector2(-unit * 0.31, -unit * 0.03)
	var peak: Vector2 = ridge_center + Vector2(shift * 0.65, -unit * height)
	var right_shoulder: Vector2 = ridge_center + Vector2(unit * 0.62, -unit * 0.08)
	var right: Vector2 = ridge_center + Vector2(unit, unit * 0.36)
	var ridge: PackedVector2Array = PackedVector2Array([left, shoulder, saddle, peak, right_shoulder, right])
	var shadow: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in ridge:
		shadow.append(point + Vector2(unit * 0.15, unit * 0.16))
	draw_colored_polygon(shadow, MOUNTAIN_SHADOW)
	draw_colored_polygon(ridge, MOUNTAIN_FACE)
	draw_colored_polygon(PackedVector2Array([peak, ridge_center + Vector2(shift * 0.65 - unit * 0.09, unit * 0.28), right, right_shoulder]), MOUNTAIN_SHADE)
	draw_colored_polygon(PackedVector2Array([shoulder, saddle, ridge_center + Vector2(-unit * 0.35, unit * 0.32), left]), Color("7b735f"))
	draw_polyline(PackedVector2Array([left, shoulder, saddle, peak]), MOUNTAIN_EDGE, maxf(1.0, zoom), true)


func _draw_fields(center: Vector2, coordinates: Vector2i) -> void:
	if (coordinates.x * 3 + coordinates.y * 7) % 5 != 0:
		return
	var unit: float = cell_pixels() * 0.18
	for row: int in range(3):
		var offset: float = float(row - 1) * unit * 0.45
		draw_line(center + Vector2(-unit, offset + unit * 0.30), center + Vector2(unit, offset - unit * 0.30), Color(0.37, 0.29, 0.18, 0.26), maxf(1.0, zoom))


func _draw_city(center: Vector2, tile: Dictionary, is_home: bool) -> void:
	var marker_size: float = clampf(cell_pixels() * 0.30, 6.0, 19.0)
	var flag_color: Color = city_flag_color(tile, is_home)
	var art_extent: Vector2 = Vector2.ONE * minf(116.0, cell_pixels() * city_art_scale(tile, is_home))
	if zoom < 0.46 or not _draw_map_sprite(city_art_id(tile, is_home), center, art_extent):
		draw_circle(center + Vector2(marker_size * 0.18, marker_size * 0.37), marker_size * 1.10, Color(0.13, 0.11, 0.09, 0.38))
		var fort: Rect2 = Rect2(center + Vector2(-marker_size * 0.90, -marker_size * 0.25), Vector2(marker_size * 1.80, marker_size * 0.98))
		draw_rect(fort, Color("82735d"))
		draw_rect(Rect2(fort.position, Vector2(fort.size.x, marker_size * 0.14)), Color("d0b994"))
		if zoom >= 0.46:
			# Light falls from the upper left: shaded returns and a gatehouse make the
			# same compact marker read as a walled settlement instead of a flat badge.
			draw_colored_polygon(PackedVector2Array([fort.position + Vector2(fort.size.x, 0), fort.position + Vector2(fort.size.x + marker_size * 0.22, -marker_size * 0.16), fort.end + Vector2(marker_size * 0.22, -marker_size * 0.16), fort.end]), Color("5f5344"))
			for side: float in [-1.0, 1.0]:
				var tower: Rect2 = Rect2(center + Vector2(side * marker_size * 0.78 - marker_size * 0.20, -marker_size * 0.54), Vector2(marker_size * 0.40, marker_size * 1.26))
				draw_rect(tower, Color("b39d7b") if side < 0 else Color("998464"))
				draw_rect(Rect2(tower.position + Vector2(marker_size * 0.26, 0), Vector2(marker_size * 0.14, tower.size.y)), Color("766249"))
				for crenel: int in range(2):
					draw_rect(Rect2(tower.position + Vector2(float(crenel) * marker_size * 0.25, -marker_size * 0.12), Vector2(marker_size * 0.15, marker_size * 0.18)), Color("d0b994"))
			var gatehouse: Rect2 = Rect2(center + Vector2(-marker_size * 0.37, -marker_size * 0.61), Vector2(marker_size * 0.74, marker_size * 1.35))
			draw_rect(gatehouse, Color("b59b75"))
			draw_colored_polygon(PackedVector2Array([center + Vector2(-marker_size * 0.54, -marker_size * 0.61), center + Vector2(-marker_size * 0.31, -marker_size * 0.88), center + Vector2(marker_size * 0.31, -marker_size * 0.88), center + Vector2(marker_size * 0.54, -marker_size * 0.61)]), Color("5e4432"))
			draw_line(center + Vector2(-marker_size * 0.54, -marker_size * 0.61), center + Vector2(marker_size * 0.54, -marker_size * 0.61), Color("caac77"), maxf(1.0, zoom))
			draw_circle(center + Vector2(0, marker_size * 0.29), marker_size * 0.22, Color("302d26"))
			draw_rect(Rect2(center + Vector2(-marker_size * 0.22, marker_size * 0.29), Vector2(marker_size * 0.44, marker_size * 0.45)), Color("302d26"))
		else:
			draw_rect(Rect2(center + Vector2(-marker_size * 0.21, marker_size * 0.18), Vector2(marker_size * 0.42, marker_size * 0.56)), Color("302d26"))
			for crenel: int in range(3):
				draw_rect(Rect2(fort.position + Vector2(float(crenel) * marker_size * 0.70, -marker_size * 0.23), Vector2(marker_size * 0.33, marker_size * 0.31)), Color("c8b08b"))
	if zoom >= 0.46 and _map_art_sprites.has(city_art_id(tile, is_home)):
		var sprite: AtlasTexture = _map_art_sprites[city_art_id(tile, is_home)] as AtlasTexture
		_city_hit_regions.append({"id": str(tile.get("id", "")), "coordinates": Vector2i(int(tile.get("x", 0)), int(tile.get("y", 0))), "rect": _map_sprite_rect(sprite, center, art_extent), "region": sprite.region})
	var pole_top: Vector2 = center + Vector2(marker_size * 0.55, -marker_size * 1.55)
	draw_line(center + Vector2(marker_size * 0.55, -marker_size * 0.17), pole_top, Color("3e3427"), maxf(1.0, zoom))
	draw_line(center + Vector2(marker_size * 0.52, -marker_size * 0.17), pole_top - Vector2(marker_size * 0.03, 0), GOLD, 1.0)
	draw_colored_polygon(PackedVector2Array([pole_top, pole_top + Vector2(marker_size * 0.93, marker_size * 0.08), pole_top + Vector2(marker_size * 0.70, marker_size * 0.53), pole_top + Vector2(0, marker_size * 0.46)]), flag_color)
	var faction_glyph: String = city_flag_glyph(tile, is_home)
	if zoom >= 1.05 and not faction_glyph.is_empty():
		_draw_centered_text(faction_glyph, pole_top + Vector2(marker_size * 0.35, marker_size * 0.40), 9, Color("302b22"))
	if zoom >= 0.50 or is_home or str(tile.get("tier", "")) in ["province", "capital"]:
		var name: String = str(tile.get("name", "主城" if is_home else "城池"))
		_draw_map_label(name, center + Vector2(0, marker_size + 15), 14 if zoom >= 0.8 else 12, TEXT, is_home or tile == selected_tile)
	if zoom >= 1.00:
		_draw_map_label("%s · Lv.%d" % [city_tier_label(tile, is_home), int(tile.get("level", 1))], center + Vector2(0, marker_size + 41), 11, Color(TEXT, 0.85))


static func city_flag_glyph(tile: Dictionary, is_home: bool = false) -> String:
	if is_home or bool(tile.get("owned", false)): return "我"
	if str(tile.get("relation", "")) in ["allied", "friendly", "ally"]: return "盟"
	if str(tile.get("relation", "")) in ["enemy", "hostile"]: return "敌"
	match str(tile.get("faction", "")):
		"yellow_turban": return "黄"
		"local_warlord": return "军"
	var glyph: String = str(tile.get("faction", "")).left(1)
	if not glyph.is_empty() and glyph.unicode_at(0) >= 0x3400 and glyph.unicode_at(0) <= 0x9fff:
		return glyph
	return ""


static func city_flag_color(tile: Dictionary, is_home: bool) -> Color:
	# Keep the established ownership and relationship colors independent of art.
	if is_home or bool(tile.get("owned", false)):
		return Color("e2c181")
	if str(tile.get("relation", "")) in ["allied", "friendly", "ally"]:
		return Color("75afba")
	if str(tile.get("relation", "")) in ["enemy", "hostile"]:
		return Color("c9715e")
	if str(tile.get("kind", "")) == "yellow_city" or str(tile.get("faction", "")) == "yellow_turban":
		return Color("d3b447")
	return Color("b78053")


func _draw_task(center: Vector2, tile: Dictionary) -> void:
	if str(tile.get("terrain", "")) in ["camp", "fort"] and _draw_terrain_sprite("camp", center, Vector2i(int(tile.get("x",0)), int(tile.get("y",0)))):
		if zoom >= 0.75:
			_draw_map_label(str(tile.get("name", "任务据点")), center + Vector2(0, cell_pixels() * 0.37 + 15), 14, TEXT, tile == selected_tile)
		return
	var radius: float = clampf(cell_pixels() * 0.16, 5.0, 12.0)
	var flag: Vector2 = center + Vector2(cell_pixels() * 0.23, -radius)
	draw_line(flag, flag + Vector2(0, radius * 2), Color("6a5036"), 2)
	draw_colored_polygon(PackedVector2Array([flag, flag + Vector2(radius, radius * 0.27), flag + Vector2(0, radius * 0.62)]), Color("d7b575"))
	if zoom >= 0.75:
		_draw_map_label(str(tile.get("name", "任务据点")), center + Vector2(0, radius + 15), 12, TEXT, tile == selected_tile)


func _draw_grid(min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	var grid_color: Color = Color(0.88, 0.85, 0.69, 0.11)
	for x: int in range(min_x, max_x + 2):
		draw_line(world_to_screen(Vector2(x, min_y)), world_to_screen(Vector2(x, max_y + 1)), grid_color, 1.0)
	for y: int in range(min_y, max_y + 2):
		draw_line(world_to_screen(Vector2(min_x, y)), world_to_screen(Vector2(max_x + 1, y)), grid_color, 1.0)


static func march_route_color(march: Dictionary) -> Color:
	if str(march.get("status", "")) in ["return", "returning"]: return Color("7bafb4")
	if bool(march.get("incoming", false)) and str(march.get("type", march.get("kind", ""))) == "pvp": return Color("c9715e")
	if str(march.get("type", march.get("kind", ""))) == "aid": return Color("75afba")
	return Color("ccb37c")


func _draw_marches() -> void:
	if not filter_kind in ["all", "marches"]:
		return
	var now_ms: float = _map_now_ms()
	for item: Variant in world.get("marches", []):
		if not item is Dictionary:
			continue
		var march: Dictionary = item
		var from_data: Dictionary = march.get("from", {})
		var to_data: Dictionary = march.get("to", {})
		var start: Vector2 = world_to_screen(Vector2(float(from_data.get("x", 0)) + 0.5, float(from_data.get("y", 0)) + 0.5))
		var target: Vector2 = world_to_screen(Vector2(float(to_data.get("x", 0)) + 0.5, float(to_data.get("y", 0)) + 0.5))
		var position: Vector2 = world_to_screen(march_world_position(march, now_ms))
		var route_color: Color = march_route_color(march)
		if zoom >= 0.36:
			_draw_dashed_line(start, target, Color(route_color, 0.90), 1.5)
		if not Rect2(Vector2(-120, -35), size + Vector2(240, 70)).has_point(position):
			continue
		draw_circle(position, 7.0, Color("292824"))
		draw_arc(position, 7.0, 0.0, TAU, 16, route_color, 1.5, true)
		var direction: Vector2 = (target - start).normalized()
		if str(march.get("status", "")) in ["stationed", "garrison", "gathering"] or direction.is_zero_approx():
			draw_rect(Rect2(position - Vector2(3, 3), Vector2(6, 6)), route_color)
		else:
			var side: Vector2 = direction.orthogonal()
			draw_colored_polygon(PackedVector2Array([position + direction * 5, position - direction * 3 + side * 3.5, position - direction * 3 - side * 3.5]), route_color)
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
	var bounds: Rect2 = Rect2(Vector2(-16, -16), size + Vector2(32, 32))
	var steps: Vector2i = visible_dash_range(start, target, bounds)
	for step: int in range(steps.x, steps.y):
		var point: Vector2 = start + direction * float(step) * 15.0
		draw_line(point, start + direction * minf(length, float(step) * 15.0 + 8.0), Color("292824", 0.65), width + 2.5, true)
		draw_line(point, start + direction * minf(length, float(step) * 15.0 + 8.0), color, width, true)


static func segment_visible_interval(start: Vector2, target: Vector2, bounds: Rect2) -> Vector2:
	var fractions: PackedFloat64Array = _segment_visible_fractions(start, target, bounds)
	return Vector2(fractions[0], fractions[1]) if not fractions.is_empty() else Vector2(-1, -1)


static func _segment_visible_fractions(start: Vector2, target: Vector2, bounds: Rect2) -> PackedFloat64Array:
	var direction: Vector2 = target - start
	var entry: float = 0.0
	var exit: float = 1.0
	for axis: int in range(2):
		if is_zero_approx(direction[axis]):
			if start[axis] < bounds.position[axis] or start[axis] > bounds.end[axis]:
				return PackedFloat64Array()
			continue
		var near: float = (bounds.position[axis] - start[axis]) / direction[axis]
		var far: float = (bounds.end[axis] - start[axis]) / direction[axis]
		if near > far:
			var swap: float = near
			near = far
			far = swap
		entry = maxf(entry, near)
		exit = minf(exit, far)
		if entry > exit:
			return PackedFloat64Array()
	return PackedFloat64Array([entry, exit])


static func visible_dash_range(start: Vector2, target: Vector2, bounds: Rect2) -> Vector2i:
	var length: float = start.distance_to(target)
	if length < 1.0:
		return Vector2i.ZERO
	# Keep clipping fractions in doubles: storing them in a standard Vector2
	# rounds enough on very long routes to lose a dash touching the viewport edge.
	var interval: PackedFloat64Array = _segment_visible_fractions(start, target, bounds)
	if interval.is_empty():
		return Vector2i.ZERO
	# Indices are relative to the original route, so camera motion does not
	# restart the pattern. Include a dash whose tail touches the clipped entry.
	var first: int = maxi(0, ceili((interval[0] * length - 8.0 - 0.00001) / 15.0))
	var end: int = mini(ceili(length / 15.0), floori((interval[1] * length + 0.00001) / 15.0) + 1)
	return Vector2i(first, end) if first < end else Vector2i.ZERO


func _draw_compass() -> void:
	var center: Vector2 = Vector2(size.x - 31, 37)
	draw_circle(center, 22.0, Color(0.10, 0.10, 0.09, 0.78))
	draw_arc(center, 22.0, 0.0, TAU, 32, Color(GOLD, 0.60), 1.0, true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -16), center + Vector2(5, 9), center, center + Vector2(-5, 9)]), GOLD)
	_draw_centered_text("北", center + Vector2(0, -24), 11, TEXT)


func _draw_map_status() -> void:
	var district: String = ""
	for value: Variant in regions:
		if value is Dictionary:
			var bounds: Array = value.get("bounds", [])
			if bounds.size() == 4 and Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3])).has_point(camera_center):
				district = str(value.get("name", ""))
				break
	if not district.is_empty():
		_draw_label(district + " · 试玩分区", Vector2(83, 24), 12, Color(TEXT, 0.88))
	var mode: String = "近景" if zoom >= 1.05 else ("区域" if zoom >= 0.46 else "分区")
	var label: String = "%s · %.0f%% · (%d,%d)" % [mode, zoom * 100.0, floori(camera_center.x), floori(camera_center.y)]
	var panel: Rect2 = Rect2(Vector2(12, size.y - 35), Vector2(235, 24))
	draw_rect(panel, Color(0.10, 0.10, 0.09, 0.88))
	draw_string(_font, panel.position + Vector2(8, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(TEXT, 0.85))
	if size.x > 650:
		_draw_label("拖动浏览 · 滚轮缩放 · 双指缩放", Vector2(size.x - 144, size.y - 19), 12, Color(TEXT, 0.65))


func _draw_badge(center: Vector2, label: String, color: Color) -> void:
	draw_circle(center, 11.0, Color(0.13, 0.12, 0.10, 0.45))
	draw_circle(center, 9.0, color)
	_draw_centered_text(label, center + Vector2(0, 4), 12, TEXT)


func _draw_centered_text(label: String, position: Vector2, font_size: int, color: Color) -> void:
	var width: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(_font, position - Vector2(width * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_map_label(label: String, position: Vector2, font_size: int, color: Color, priority: bool = false) -> void:
	var text_size: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var rect: Rect2 = Rect2(position - Vector2(text_size.x * 0.5 + 6, font_size), Vector2(text_size.x + 12, font_size + 8))
	if not priority:
		for used: Rect2 in _map_label_rects:
			if rect.intersects(used.grow(2.0)):
				return
	_map_label_rects.append(rect)
	_draw_label(label, position, font_size, color)


func _draw_label(label: String, position: Vector2, font_size: int, color: Color) -> void:
	var text_size: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var rectangle: Rect2 = Rect2(position - Vector2(text_size.x * 0.5 + 5, font_size - 2), Vector2(text_size.x + 10, font_size + 6))
	draw_rect(rectangle, Color(0.10, 0.10, 0.09, 0.84))
	_draw_centered_text(label, position, font_size, color)
