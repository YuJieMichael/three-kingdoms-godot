class_name KingdomCityView
extends Control

## Buildable inner-city parcels, projected from the authoritative city layout.
## Reflowing the scene never changes a site identity or construction rule.
signal building_selected(id: String)
signal empty_site_selected(site: int)
signal defense_selected

const GOLD: Color = Color("c6aa71")
const LABEL: Color = Color("eee3c9")
const CHINESE_FONT: Font = preload("res://assets/fonts/UI.tres")
const TAP_TRAVEL: float = 10.0
const CITY_ART_PATH: String = "res://assets/environment/city/city_rts_core_v1.png"
const CITY_ART_METADATA: String = "res://data/city-rts-art-atlas.json"
const CITY_GROUND_PATH: String = "res://assets/environment/city/city_ground_rts_v1.png"
const GRID_TOP: float = 112.0
const SITE_COUNT: int = 36
const SHORT_NAMES: Dictionary = {"hall": "官府", "house": "民房", "academy": "书院", "embassy": "鸿胪寺", "tavern": "招贤馆", "barracks": "军营", "drill": "校场", "recruit": "募兵所", "stable": "马厩", "beacon": "烽燧", "wall": "城防", "warehouse": "仓库", "smith": "铁匠铺", "workshop": "工坊", "market": "市场", "inn": "客栈", "post": "驿站"}

var _view: Dictionary = {}
var _hit_boxes: Dictionary = {}
var _hit_records: Dictionary = {}
var _lots: Array[Dictionary] = []
var _district_rects: Dictionary = {}
var _ground_texture: Texture2D
var _server_time_ms: float = 0.0
var _snapshot_tick: int = 0
var _progress_elapsed: float = 0.0
var _hover: String = ""
var _selected: String = ""
var _touch_index: int = -1
var _touch_origin: Vector2 = Vector2.ZERO
var _touch_key: String = ""
var _touch_dragged: bool = false
var _art_texture: Texture2D
var _art_textures: Dictionary = {}
var _art_sprites: Dictionary = {}
var _tier_sprites: Dictionary = {}
var _tier_definitions: Dictionary = {}
var _environment_sprites: Dictionary = {}
var _environment_records: Dictionary = {}
var _sprite_records: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(240.0, recommended_height(240.0))
	# Unaccepted press/drag events must reach the surrounding scroll view.
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "点击建筑查看升级，点击空地选择要建的建筑"
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_load_city_art()
	if _ground_texture == null:
		_ground_texture = _art_texture_at(CITY_GROUND_PATH)
	set_process(false)

func art_loaded() -> bool:
	return _art_texture != null and ["hall", "gateway", "barracks", "warehouse", "market", "house"].all(func(id: String) -> bool: return _art_sprites.has(id))

func art_regions() -> Dictionary:
	var regions: Dictionary = {}
	for id: Variant in _art_sprites:
		regions[id] = (_art_sprites[id] as AtlasTexture).region
	return regions

func sprite_draw_records() -> Dictionary:
	return _sprite_records.duplicate(true)

func art_sprite_key(id: String, level: int = 1) -> String:
	# Only completed levels choose a skin. Future queued levels are never
	# consulted; a level-zero construction remains a bare foundation.
	if level <= 0:
		return ""
	if id == "gateway" and _environment_sprites.has("gate"):
		return "environment_gate"
	var chosen: String = id if _art_sprites.has(id) else ""
	var threshold: int = 0
	for tier: Dictionary in _tier_definitions.get(id, []):
		var minimum: int = int(tier.get("minLevel", 1))
		var key: String = str(tier.get("key", ""))
		if minimum <= level and minimum > threshold and _tier_sprites.has(key):
			chosen = key
			threshold = minimum
	return chosen

func _sprite_for_key(key: String) -> AtlasTexture:
	if key.begins_with("environment_"):
		return _environment_sprites.get(key.trim_prefix("environment_")) as AtlasTexture
	return _tier_sprites.get(key, _art_sprites.get(key)) as AtlasTexture

func art_sprite_texture(id: String, level: int = 1) -> Texture2D:
	return _sprite_for_key(art_sprite_key(id, level))

func art_tier_regions() -> Dictionary:
	var regions: Dictionary = {}
	for key: Variant in _tier_sprites:
		regions[key] = (_tier_sprites[key] as AtlasTexture).region
	return regions

func environment_art_regions() -> Dictionary:
	var regions: Dictionary = {}
	for key: Variant in _environment_sprites:
		regions[key] = (_environment_sprites[key] as AtlasTexture).region
	return regions

func environment_draw_records() -> Dictionary:
	return _environment_records.duplicate(true)

func plan_geometry() -> Dictionary:
	var metrics: Dictionary = _grid_metrics(size.x)
	var result: Dictionary = metrics.duplicate(true)
	var main_column: int = int(metrics.main_after)
	var main_start: float = _column_origin(main_column + 1, metrics) - float(metrics.main_gap)
	result["main_street"] = Rect2(main_start, GRID_TOP - 5.0, float(metrics.main_gap), _grid_bottom() - GRID_TOP + 92.0)
	result["gate_axis"] = main_start + float(metrics.main_gap) * 0.5
	result["grid_bottom"] = _grid_bottom()
	return result

func parcel_draw_records() -> Array[Dictionary]:
	return _lots.duplicate(true)

func art_sprite_textures() -> Dictionary:
	var textures: Dictionary = {}
	for id: Variant in _art_sprites:
		textures[id] = ((_art_sprites[id] as AtlasTexture).atlas as Texture2D).resource_path
	return textures

func _art_texture_at(path: String) -> Texture2D:
	if _art_textures.has(path):
		return _art_textures[path] as Texture2D
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		return null
	var loaded: Resource = ResourceLoader.load(path, "Texture2D")
	if not loaded is Texture2D:
		return null
	_art_textures[path] = loaded
	return loaded as Texture2D

func _load_city_art() -> void:
	# All atlas regions and source textures are cached on entry to the scene.
	# New environment/tiers may be omitted: the base city remains usable.
	if not FileAccess.file_exists(CITY_ART_METADATA):
		return
	var file: FileAccess = FileAccess.open(CITY_ART_METADATA, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var metadata: Dictionary = parsed
	_art_texture = _art_texture_at(str(metadata.get("texture", CITY_ART_PATH)))
	var rows: Variant = metadata.get("regions", {})
	if rows is Dictionary and _art_texture != null:
		for id: Variant in rows:
			_add_art_region(str(id), rows[id], _art_texture)
	var sprites: Variant = metadata.get("sprites", [])
	if sprites is Array:
		for value: Variant in sprites:
			if value is Dictionary:
				var texture: Texture2D = _art_texture_at(str(value.get("texture", CITY_ART_PATH)))
				if texture != null:
					_add_art_region(str(value.get("id", "")), value.get("region", value.get("bounds", [])), texture)
	var ground: Variant = metadata.get("ground", CITY_GROUND_PATH)
	_ground_texture = _art_texture_at(str(ground.get("texture", CITY_GROUND_PATH)) if ground is Dictionary else str(ground))
	var environment: Variant = metadata.get("environment", {})
	if environment is Dictionary:
		var environment_texture: Texture2D = _art_texture_at(str(environment.get("texture", "")))
		var environment_regions: Variant = environment.get("regions", {})
		if environment_texture != null and environment_regions is Dictionary:
			for key: Variant in environment_regions:
				if str(key) in ["wall_segment", "courtyard", "tree", "gate"]:
					var sprite: AtlasTexture = _validated_art_region(environment_regions[key], environment_texture)
					if sprite != null:
						_environment_sprites[str(key)] = sprite
	var tiers: Variant = metadata.get("tiers", {})
	if tiers is Dictionary:
		for id: Variant in tiers:
			if not SHORT_NAMES.has(str(id)) or not tiers[id] is Array:
				continue
			var definitions: Array[Dictionary] = []
			for value: Variant in tiers[id]:
				if not value is Dictionary:
					continue
				var key: String = str(value.get("key", ""))
				var minimum: int = int(value.get("minLevel", 1))
				var texture: Texture2D = _art_texture_at(str(value.get("texture", "")))
				if key.is_empty() or _art_sprites.has(key) or minimum < 1 or texture == null:
					continue
				var sprite: AtlasTexture = _validated_art_region(value.get("region", value.get("bounds", [])), texture)
				if sprite != null:
					_tier_sprites[key] = sprite
					definitions.append({"key": key, "minLevel": minimum})
			_tier_definitions[str(id)] = definitions

func _validated_art_region(value: Variant, texture: Texture2D) -> AtlasTexture:
	var region: Rect2 = Rect2()
	if value is Array and value.size() >= 4:
		region = Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	elif value is Dictionary:
		if value.has("region") or value.has("bounds"):
			return _validated_art_region(value.get("region", value.get("bounds", [])), texture)
		region = Rect2(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("width", value.get("w", 0.0))), float(value.get("height", value.get("h", 0.0))))
	if texture == null or region.size.x <= 0.0 or region.size.y <= 0.0 or not Rect2(Vector2.ZERO, texture.get_size()).encloses(region):
		return null
	var sprite: AtlasTexture = AtlasTexture.new()
	sprite.atlas = texture
	sprite.region = region
	sprite.filter_clip = true
	return sprite

func _add_art_region(id: String, value: Variant, texture: Texture2D) -> void:
	if not SHORT_NAMES.has(id) and id != "gateway":
		return
	var sprite: AtlasTexture = _validated_art_region(value, texture)
	if sprite != null:
		_art_sprites[id] = sprite

func set_city(view: Dictionary, server_time_ms: float = 0.0) -> void:
	var previous_city: Dictionary = _view.get("city", {})
	var next_city: Dictionary = view.get("city", {})
	if str(previous_city.get("id", previous_city.get("name", ""))) != str(next_city.get("id", next_city.get("name", ""))):
		_selected = ""
		_hover = ""
		_clear_touch()
	_view = view.duplicate(true)
	_server_time_ms = server_time_ms if server_time_ms > 0.0 else float(view.get("serverTime", Time.get_unix_time_from_system() * 1000.0))
	_snapshot_tick = Time.get_ticks_msec()
	_progress_elapsed = 0.0
	set_process((_view.get("buildings", []) as Array).any(func(row: Variant) -> bool: return row is Dictionary and row.get("queue") is Dictionary))
	_rebuild_layout()
	queue_redraw()

func select_building(id: String, site: int = -1) -> void:
	_selected = "%s#%d" % [id, site]
	queue_redraw()

func selected_site() -> int:
	var row: Dictionary = _hit_records.get(_selected, {})
	return int(row.get("site", -1))

func _activate_building(key: String) -> void:
	if key == "perimeter":
		defense_selected.emit()
		return
	var row: Dictionary = _hit_records.get(key, {})
	if row.is_empty():
		return
	_selected = key
	if bool(row.get("empty", false)):
		empty_site_selected.emit(int(row.site))
	else:
		building_selected.emit(str(row.id))
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		var needed_height: float = recommended_height(size.x)
		if not is_equal_approx(custom_minimum_size.y, needed_height):
			var previous_minimum: float = custom_minimum_size.y
			custom_minimum_size.y = needed_height
			# A standalone view can still be clamped to its previous phone
			# minimum when width changes. Release that obsolete clamp too.
			if is_equal_approx(size.y, previous_minimum):
				size.y = needed_height
		_rebuild_layout()
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	# Godot marks mouse events synthesized from touch as device -1. Handling
	# them as desktop presses would open a lot before its gesture is known.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		var next: String = _building_at((event as InputEventMouseMotion).position)
		if next != _hover:
			_hover = next
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not next.is_empty() else Control.CURSOR_ARROW
			var row: Dictionary = _hit_records.get(next, {})
			tooltip_text = "空地 · 地块 %d · 点击建设" % (int(row.site) + 1) if bool(row.get("empty", false)) else "%s · 地块 %d · %d级" % [str(row.get("name", "")), int(row.get("site", -1)) + 1, int(row.get("level", 0))] if not row.is_empty() else "点击实筑查看升级，点击空地选择建设位置"
			if next == "perimeter":
				tooltip_text = "城防 · %d级 · 点击修筑或升级" % perimeter_level()
			queue_redraw()
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			var key: String = _building_at(click.position)
			if not key.is_empty():
				_activate_building(key)
				accept_event()
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.canceled:
			if touch.index == _touch_index:
				_clear_touch()
			return
		if touch.pressed:
			if _touch_index >= 0 and touch.index != _touch_index:
				_touch_dragged = true
				return
			_touch_index = touch.index
			_touch_origin = get_global_transform_with_canvas() * touch.position
			_touch_key = _building_at(touch.position)
			_touch_dragged = false
		elif touch.index == _touch_index:
			var point: Vector2 = get_global_transform_with_canvas() * touch.position
			var key: String = _touch_key
			var tap: bool = not _touch_dragged and point.distance_to(_touch_origin) <= TAP_TRAVEL and not key.is_empty() and _building_at(touch.position) == key
			_clear_touch()
			if tap:
				_activate_building(key)
				accept_event()
	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _touch_index:
			var point: Vector2 = get_global_transform_with_canvas() * drag.position
			if point.distance_to(_touch_origin) > TAP_TRAVEL:
				_touch_dragged = true
		# Never accept a drag: the parent ScrollContainer owns scrolling.

func _clear_touch() -> void:
	_touch_index = -1
	_touch_key = ""
	_touch_dragged = false

func _building_at(point: Vector2) -> String:
	for key: Variant in _hit_boxes:
		if (_hit_boxes[key] as Rect2).has_point(point):
			return str(key)
	for rect: Rect2 in perimeter_hit_regions():
		if rect.has_point(point):
			return "perimeter"
	return ""

func _row_id(row: Dictionary) -> String:
	var value: Variant = row.get("id")
	return value if value is String else ""

func grid_columns(width: float = -1.0) -> int:
	return 3 if (size.x if width < 0.0 else width) < 600.0 else 6

func _grid_metrics(width: float) -> Dictionary:
	var columns: int = grid_columns(width)
	var plan_width: float = minf(width, 1200.0)
	var margin: float = 15.0 if columns == 3 else 34.0
	var gap: float = 4.0 if columns == 3 else 5.0
	var main_gap: float = 18.0 if columns == 3 else 26.0
	var gaps_width: float = gap * float(columns - 2) + main_gap
	var cell_width: float = maxf(56.0, (plan_width - margin * 2.0 - gaps_width) / float(columns))
	var cell_height: float = clampf(cell_width + 32.0, 142.0, 212.0)
	return {"columns": columns, "rows": ceili(float(SITE_COUNT) / float(columns)), "plan_width": plan_width, "margin": margin, "gap": gap, "main_gap": main_gap, "main_after": 1 if columns == 3 else 2, "cell": Vector2(cell_width, cell_height)}

func _column_origin(column: int, metrics: Dictionary) -> float:
	var x: float = _plan_left() + float(metrics.margin) + float(column) * ((metrics.cell as Vector2).x + float(metrics.gap))
	if column > int(metrics.main_after):
		x += float(metrics.main_gap) - float(metrics.gap)
	return x

func recommended_height(width: float) -> float:
	var metrics: Dictionary = _grid_metrics(width)
	return GRID_TOP + float(metrics.rows) * (metrics.cell as Vector2).y + float(int(metrics.rows) - 1) * float(metrics.gap) + 172.0

func _plan_width() -> float:
	return minf(size.x, 1200.0)

func _plan_left() -> float:
	return (size.x - _plan_width()) * 0.5

func _grid_bottom() -> float:
	var metrics: Dictionary = _grid_metrics(size.x)
	return GRID_TOP + float(metrics.rows) * (metrics.cell as Vector2).y + float(int(metrics.rows) - 1) * float(metrics.gap)

func _parcel_rects() -> Array[Dictionary]:
	var metrics: Dictionary = _grid_metrics(size.x)
	var cell: Vector2 = metrics.cell
	var result: Array[Dictionary] = []
	for site: int in range(SITE_COUNT):
		var column: int = site % int(metrics.columns)
		var row: int = floori(float(site) / float(metrics.columns))
		var origin: Vector2 = Vector2(_column_origin(column, metrics), GRID_TOP + float(row) * (cell.y + float(metrics.gap)))
		result.append({"district": "official" if site in [14, 15, 20, 21] else "city", "row": row, "column": column, "rect": Rect2(origin, cell)})
	return result

func _parcel_for_site(site: int) -> int:
	return site if site >= 0 and site < SITE_COUNT else -1

func _process(delta: float) -> void:
	_progress_elapsed += delta
	if _progress_elapsed >= 1.0:
		_progress_elapsed = 0.0
		queue_redraw()

func _queue_progress(queue: Dictionary) -> Dictionary:
	var started: float = float(queue.get("start", 0.0))
	var ended: float = float(queue.get("end", 0.0))
	var now: float = _server_time_ms + float(Time.get_ticks_msec() - _snapshot_tick)
	var progress: float = clampf((now - started) / maxf(ended - started, 1.0), 0.0, 1.0)
	var remaining: int = maxi(0, ceili((ended - now) / 1000.0))
	return {"progress": progress, "seconds": remaining}

func _rebuild_layout() -> void:
	_hit_boxes.clear()
	_hit_records.clear()
	_lots.clear()
	if size.x < 10.0 or size.y < 10.0:
		return
	var parcels: Array[Dictionary] = _parcel_rects()
	var sites: Dictionary = {}
	var built: Dictionary = {}
	for value: Variant in _view.get("buildingSlots", []):
		if value is Dictionary:
			var slot: Dictionary = value
			sites[int(slot.get("site", -1))] = slot.duplicate(true)
	for value: Variant in _view.get("buildings", []):
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		var site: int = int(row.get("site", -1))
		var id: String = _row_id(row)
		if _parcel_for_site(site) < 0 or id.is_empty() or id == "reserved" or built.has(site):
			continue
		var slot: Dictionary = sites.get(site, {})
		if bool(slot.get("reserved", false)) or _row_id(slot) == "reserved":
			continue
		built[site] = row.duplicate(true)
		if not sites.has(site):
			sites[site] = {"site": site, "id": id}
	var ordered_sites: Array = sites.keys()
	ordered_sites.sort()
	for value: Variant in ordered_sites:
		var site: int = int(value)
		var parcel: int = _parcel_for_site(site)
		if parcel < 0:
			continue
		var slot: Dictionary = sites[site]
		if bool(slot.get("reserved", false)) or _row_id(slot) == "reserved":
			_register_lot(slot, parcels[parcel], false, true)
		elif built.has(site):
			_register_lot(built[site], parcels[parcel], false, false)
		else:
			# An occupied slot missing its DTO is left bare and nonselectable.
			_register_lot(slot, parcels[parcel], _row_id(slot).is_empty(), not _row_id(slot).is_empty())

func _register_lot(row: Dictionary, parcel: Dictionary, empty: bool, reserved: bool) -> void:
	var record: Dictionary = row.duplicate(true)
	record["rect"] = parcel.rect
	record["district"] = parcel.district
	record["row"] = parcel.row
	record["column"] = parcel.column
	record["empty"] = empty
	record["reserved"] = reserved
	record["id"] = "" if empty or reserved else _row_id(row)
	var key: String = "%s#%d" % ["empty" if empty else str(record.id), int(record.get("site", -1))]
	record["key"] = key
	_lots.append(record)
	if not reserved:
		_hit_boxes[key] = parcel.rect
		_hit_records[key] = record

func _draw() -> void:
	if size.x < 10.0 or size.y < 10.0:
		return
	_sprite_records.clear()
	_environment_records.clear()
	_draw_landscape()
	_draw_plan()
	_draw_ramparts(false)
	for lot: Dictionary in _lots:
		if bool(lot.reserved):
			_draw_reserved_lot(lot)
		elif bool(lot.empty):
			_draw_empty_lot(lot)
		else:
			_draw_building(lot)
	_draw_ramparts(true)
	_draw_gate(Vector2(float(plan_geometry().gate_axis), _grid_bottom() + 117.0))
	var meta: Dictionary = _view.get("city", {})
	_text(Vector2(_plan_left() + 17.0, 31.0), str(meta.get("name", "城池")), 23, LABEL)
	_text(Vector2(_plan_left() + 17.0, 54.0), "城防 %d级 · 点击围墙修筑 / 空地建设" % perimeter_level(), 12, Color("d1c7a9"))
	var heading_x: float = _plan_left() + _plan_width() - 26.0
	_text(Vector2(heading_x - 5.0, 29.0), "北", 12, GOLD)
	draw_line(Vector2(heading_x, 35.0), Vector2(heading_x, 50.0), GOLD, 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(heading_x - 4.0, 39.0), Vector2(heading_x, 34.0), Vector2(heading_x + 4.0, 39.0)]), GOLD)
	var caption: String = "空地可自选建筑 · 官署留地不可建设"
	var chosen: Dictionary = _hit_records.get(_selected, {})
	if not chosen.is_empty():
		caption = "地块 %02d · 选择要建的建筑" % (int(chosen.site) + 1) if bool(chosen.empty) else "%s · 地块 %02d · %d级%s" % [str(SHORT_NAMES.get(chosen.id, chosen.get("name", chosen.id))), int(chosen.site) + 1, int(chosen.get("level", 0)), " · 施工中" if chosen.get("queue") is Dictionary else ""]
	_text(Vector2(_plan_left() + 15.0, _grid_bottom() + 156.0), caption, 11, GOLD)

func _draw_landscape() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("81775a"))
	if _ground_texture != null:
		# Keep the original texture intact while reducing its gravel contrast;
		# the packed-earth base carries the town, buildings carry the detail.
		draw_texture_rect(_ground_texture, Rect2(Vector2.ZERO, size), true, Color(1.0, 1.0, 1.0, 0.30))
	# The quiet header reads above the city, without covering the land.
	draw_rect(Rect2(0.0, 0.0, size.x, 67.0), Color(0.12, 0.17, 0.13, 0.91))
	draw_line(Vector2(0.0, 66.0), Vector2(size.x, 66.0), Color("968263"), 1.0)

func _draw_plan() -> void:
	var metrics: Dictionary = _grid_metrics(size.x)
	var cell: Vector2 = metrics.cell
	var left: float = _column_origin(0, metrics)
	var right: float = _column_origin(int(metrics.columns) - 1, metrics) + cell.x
	# Narrow services lanes share the soil's value. Only the main street
	# has a larger footprint; land remains a continuous town surface.
	for row: int in range(1, int(metrics.rows)):
		var y: float = GRID_TOP + float(row) * cell.y + float(row - 1) * float(metrics.gap)
		_draw_earth_road(Rect2(left - 3.0, y, right - left + 6.0, float(metrics.gap)), false)
	for column: int in range(1, int(metrics.columns)):
		var main: bool = column - 1 == int(metrics.main_after)
		var width: float = float(metrics.main_gap) if main else float(metrics.gap)
		var x: float = _column_origin(column, metrics) - width
		_draw_earth_road(Rect2(x, GRID_TOP - 5.0, width, _grid_bottom() - GRID_TOP + 91.0 if main else _grid_bottom() - GRID_TOP + 9.0), main)
	_draw_earth_road(Rect2(left - 4.0, _grid_bottom() + 4.0, right - left + 8.0, 20.0), true)
	# Grass gathers by the wall, rather than covering every building pad.
	for side: int in [-1, 1]:
		var x: float = _plan_left() + (4.0 if side < 0 else _plan_width() - float(metrics.margin) + 1.0)
		var verge: Rect2 = Rect2(x, GRID_TOP - 5.0, maxf(4.0, float(metrics.margin) - 7.0), _grid_bottom() - GRID_TOP + 25.0)
		draw_rect(verge, Color(0.28, 0.36, 0.18, 0.13))
		_ground_grain(verge, int(metrics.rows) * 3)
		if _environment_sprites.has("tree") and int(metrics.columns) == 6:
			for row: int in range(0, int(metrics.rows), 2):
				var tree_y: float = GRID_TOP + float(row) * (cell.y + float(metrics.gap)) + 12.0
				_draw_environment_sprite("tree", Rect2(x - 4.0, tree_y, float(metrics.margin) + 3.0, 51.0), "verge_%d_%d" % [side, row])

func _draw_earth_road(rect: Rect2, main: bool) -> void:
	# The larger entrance street is worn smooth and lighter than its lots;
	# narrow service paths remain quieter, retaining the grid's readability.
	var color: Color = Color(0.678, 0.608, 0.459, 0.82) if main else Color(0.592, 0.529, 0.396, 0.58)
	draw_rect(rect, color)
	if main:
		var horizontal: bool = rect.size.x > rect.size.y
		var first: Vector2 = rect.position + Vector2(0.0, rect.size.y * 0.3) if horizontal else rect.position + Vector2(rect.size.x * 0.3, 0.0)
		var second: Vector2 = first + Vector2(rect.size.x, 0.0) if horizontal else first + Vector2(0.0, rect.size.y)
		draw_line(first, second, Color(0.35, 0.30, 0.21, 0.17), 1.0)
		first = rect.position + Vector2(0.0, rect.size.y * 0.7) if horizontal else rect.position + Vector2(rect.size.x * 0.7, 0.0)
		second = first + Vector2(rect.size.x, 0.0) if horizontal else first + Vector2(0.0, rect.size.y)
		draw_line(first, second, Color(0.62, 0.54, 0.39, 0.15), 1.0)

func _ground_grain(rect: Rect2, count: int) -> void:
	for i: int in range(count):
		var point: Vector2 = rect.position + Vector2(float((i * 73 + 19) % 211) / 211.0 * rect.size.x, float((i * 41 + 7) % 149) / 149.0 * rect.size.y)
		draw_line(point, point + Vector2(3.0, 0.7), Color(0.26, 0.25, 0.17, 0.12), 0.8)

func perimeter_level() -> int:
	for row: Dictionary in _view.get("buildings", []):
		if str(row.get("id", "")) == "wall":
			return clampi(int(row.get("level", 0)), 0, 10)
	return 0

func perimeter_height() -> float:
	return 8.0 if perimeter_level() == 0 else 22.0 + float(perimeter_level() - 1) * (2.5 if grid_columns() == 3 else 3.0)

func perimeter_hit_regions() -> Array[Rect2]:
	var left: float = _plan_left()
	var width: float = _plan_width()
	var bottom: float = _grid_bottom() + 83.0
	return [Rect2(left, 65.0, width, 44.0), Rect2(left, 109.0, 15.0, bottom - 109.0), Rect2(left + width - 15.0, 109.0, 15.0, bottom - 109.0), Rect2(left, bottom - 44.0, width, 90.0)]

func _draw_ramparts(front: bool) -> void:
	var left: float = _plan_left() + 3.0
	var right: float = _plan_left() + _plan_width() - 3.0
	var top: float = 77.0
	var bottom: float = _grid_bottom() + 83.0
	var wall_height: float = perimeter_height()
	var wall: Color = Color("7c765e")
	var stone: Color = Color("a49a7e")
	if front:
		var axis: float = float(plan_geometry().gate_axis)
		var gate_half: float = clampf(_plan_width() * 0.065, 28.0, 63.0)
		for side: int in range(2):
			var start: float = left if side == 0 else axis + gate_half
			var end: float = axis - gate_half if side == 0 else right
			_draw_wall_span(Rect2(start, bottom - wall_height, end - start, wall_height), "south_%d" % side)
		return
	_draw_wall_span(Rect2(left, 107.0 - wall_height, right - left, wall_height), "north")
	# Side walls have a top and a raised face. Horizontal art is never
	# rotated upright: that would rotate its roofs and lighting too.
	for side: int in [0, 1]:
		var x: float = left if side == 0 else right - 8.0
		if perimeter_level() <= 1:
			for y: int in range(int(top + 22.0), int(bottom), 10):
				draw_line(Vector2(x, y), Vector2(x + 7.0, y - perimeter_height() * 0.5), Color("80603d"), 4.0)
			continue
		draw_rect(Rect2(x + 3.0, top + 10.0, 9.0, bottom - top), Color(0.14, 0.18, 0.12, 0.24))
		draw_rect(Rect2(x, top + 9.0, 8.0, bottom - top - 4.0), wall)
		draw_rect(Rect2(x - 1.0, top + 7.0, 4.0, bottom - top - 4.0), stone)
		for course: int in range(ceili((bottom - top) / 22.0)):
			var y: float = top + 18.0 + float(course) * 22.0
			draw_line(Vector2(x + 1.0, y), Vector2(x + 7.0, y), wall.darkened(0.18), 1.0)

func _draw_wall_span(rect: Rect2, key: String) -> void:
	if rect.size.x <= 0.0:
		return
	draw_rect(Rect2(rect.position + Vector2(4.0, rect.size.y - 5.0), Vector2(rect.size.x, 10.0)), Color(0.14, 0.17, 0.12, 0.25))
	if perimeter_level() <= 1:
		_draw_palisade(rect)
		return
	if _environment_sprites.has("wall_segment"):
		var sprite: AtlasTexture = _environment_sprites.wall_segment as AtlasTexture
		var source_size: Vector2 = sprite.get_size()
		var width: float = source_size.x / source_size.y * rect.size.y
		var count: int = ceili(rect.size.x / width)
		for part: int in range(count):
			var x: float = rect.position.x + float(part) * width
			var remaining: float = minf(width, rect.end.x - x)
			var destination: Rect2 = Rect2(x, rect.position.y, remaining, rect.size.y)
			var source: Rect2 = Rect2(Vector2.ZERO, Vector2(source_size.x * remaining / width, source_size.y))
			draw_texture_rect_region(sprite, destination, source)
			_environment_records["wall_%s_%d" % [key, part]] = {"id": "wall_segment", "key": key, "rect": destination, "region": Rect2(sprite.region.position + source.position, source.size), "texture": sprite.atlas.resource_path}
		return
	# Solid shaded masonry remains legible without generated environment art.
	draw_rect(rect, Color("7f775e"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 7.0)), Color("aaa082"))
	for row: int in range(1, 4):
		var y: float = rect.position.y + 6.0 + float(row) * (rect.size.y - 6.0) / 4.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.24, 0.23, 0.17, 0.36), 1.0)

func _draw_palisade(rect: Rect2) -> void:
	var spacing: float = 9.0 if perimeter_level() > 0 else 26.0
	for index: int in range(ceili(rect.size.x / spacing)):
		var x: float = rect.position.x + float(index) * spacing
		var w: float = minf(7.0, rect.end.x - x)
		var y: float = rect.position.y + float(index % 3)
		draw_colored_polygon(PackedVector2Array([Vector2(x, rect.end.y), Vector2(x, y + 5.0), Vector2(x + w * 0.5, y), Vector2(x + w, y + 5.0), Vector2(x + w, rect.end.y)]), Color("876342"))
		draw_line(Vector2(x + 2.0, y + 5.0), Vector2(x + 2.0, rect.end.y), Color("b79664"), 1.0)
	if perimeter_level() > 0:
		draw_line(rect.position + Vector2(0.0, rect.size.y * 0.65), Vector2(rect.end.x, rect.position.y + rect.size.y * 0.65), Color("5c4431"), 2.0)

func _draw_environment_sprite(id: String, area: Rect2, key: String) -> bool:
	if not _environment_sprites.has(id):
		return false
	var sprite: AtlasTexture = _environment_sprites[id] as AtlasTexture
	var source_size: Vector2 = sprite.get_size()
	var scale: float = minf(area.size.x / source_size.x, area.size.y / source_size.y)
	var dimensions: Vector2 = source_size * scale
	var destination: Rect2 = Rect2(area.position + Vector2((area.size.x - dimensions.x) * 0.5, area.size.y - dimensions.y), dimensions)
	draw_texture_rect(sprite, destination, false)
	_environment_records[key] = {"id": id, "rect": destination, "parcel_rect": area, "region": sprite.region, "texture": sprite.atlas.resource_path}
	return true

func _draw_parcel_ground(lot: Dictionary, reserved: bool = false) -> void:
	var rect: Rect2 = lot.rect
	var patch: Rect2 = rect.grow(-1.0)
	var earth: Color = Color(0.47, 0.43, 0.31, 0.12 if bool(lot.get("empty", false)) else 0.06)
	if reserved:
		earth = Color(0.48, 0.45, 0.34, 0.13)
	draw_rect(patch, earth)
	# Low-contrast surveyed boundaries preserve each hit target without
	# surrounding every structure with a bright table-cell rectangle.
	draw_rect(patch, Color(0.33, 0.30, 0.21, 0.25), false, 0.8)
	for corner: Vector2 in [patch.position, Vector2(patch.end.x, patch.position.y), patch.end, Vector2(patch.position.x, patch.end.y)]:
		draw_line(corner, corner - Vector2(0.0, 2.0), Color(0.71, 0.63, 0.44, 0.65), 1.2)
	draw_rect(Rect2(rect.position + Vector2(4.0, 3.0), Vector2(25.0, 17.0)), Color(0.16, 0.20, 0.15, 0.66))
	_text(rect.position + Vector2(8.0, 16.0), "%02d" % (int(lot.site) + 1), 11, Color("e6d8b4"))

func _draw_reserved_lot(lot: Dictionary) -> void:
	var rect: Rect2 = lot.rect
	_draw_parcel_ground(lot, true)
	var official: bool = int(lot.site) in [15, 20, 21]
	if official:
		var area: Rect2 = Rect2(rect.position + Vector2(5.0, 22.0), Vector2(rect.size.x - 10.0, rect.size.y - 49.0))
		var has_court: bool = _draw_environment_sprite("courtyard", area, "courtyard#%d" % int(lot.site))
		if not has_court:
			_draw_courtyard_fallback(area)
		# A small full-shadow tree joins a paved court, never flat circles.
		var tree_area: Rect2 = Rect2(area.position + Vector2(0.0, -1.0), Vector2(area.size.x * 0.38, area.size.y * 0.58))
		if not _draw_environment_sprite("tree", tree_area, "tree#%d" % int(lot.site)) and not has_court:
			_draw_cypress(tree_area.get_center(), minf(20.0, area.size.y * 0.3))
	_center_text(Vector2(rect.get_center().x, rect.end.y - 12.0), "官署庭院" if official else "待同步", 11, Color("ddd0ae"))

func _draw_courtyard_fallback(area: Rect2) -> void:
	var paving: Rect2 = Rect2(area.position + area.size * Vector2(0.08, 0.26), area.size * Vector2(0.84, 0.66))
	draw_rect(paving, Color(0.53, 0.52, 0.42, 0.55))
	for row: int in range(4):
		var y: float = paving.position.y + float(row) * paving.size.y / 4.0
		draw_line(Vector2(paving.position.x, y), Vector2(paving.end.x, y), Color(0.34, 0.35, 0.28, 0.33), 1.0)
	for column: int in range(3):
		var x: float = paving.position.x + float(column) * paving.size.x / 3.0
		draw_line(Vector2(x, paving.position.y), Vector2(x, paving.end.y), Color(0.34, 0.35, 0.28, 0.25), 0.7)
	_draw_cypress(area.position + area.size * Vector2(0.78, 0.38), minf(15.0, area.size.y * 0.25))

func _draw_cypress(point: Vector2, height: float) -> void:
	var shadow: PackedVector2Array = PackedVector2Array([point + Vector2(-height * 0.24, height * 0.27), point + Vector2(height * 0.55, height * 0.44), point + Vector2(height * 0.65, height * 0.22), point + Vector2(height * 0.02, height * 0.07)])
	draw_colored_polygon(shadow, Color(0.15, 0.22, 0.13, 0.24))
	draw_line(point, point + Vector2(0.0, height * 0.32), Color("665039"), 2.0)
	var canopy: PackedVector2Array = PackedVector2Array([point + Vector2(-height * 0.30, height * 0.15), point + Vector2(-height * 0.20, -height * 0.25), point + Vector2(-height * 0.11, -height * 0.57), point + Vector2(0.0, -height), point + Vector2(height * 0.16, -height * 0.52), point + Vector2(height * 0.28, -height * 0.17), point + Vector2(height * 0.31, height * 0.13)])
	draw_colored_polygon(canopy, Color("4f6040"))
	draw_polyline(PackedVector2Array([point + Vector2(0.0, -height * 0.85), point + Vector2(height * 0.14, -height * 0.27), point + Vector2(height * 0.18, height * 0.07)]), Color(0.43, 0.49, 0.31, 0.8), 1.4)

func _draw_garden(rect: Rect2) -> void:
	if not _draw_environment_sprite("courtyard", rect.grow(-5.0), "garden"):
		_draw_courtyard_fallback(rect.grow(-5.0))

func _draw_empty_lot(lot: Dictionary) -> void:
	var rect: Rect2 = lot.rect
	_draw_parcel_ground(lot)
	var yard: Rect2 = rect.grow(-11.0)
	_ground_grain(yard, 12)
	# A surveyed construction plot, with a direct and legible action.
	for corner: Vector2 in [yard.position, Vector2(yard.end.x, yard.position.y), yard.end, Vector2(yard.position.x, yard.end.y)]:
		draw_line(corner, corner - Vector2(0.0, 4.0), Color("c1b084"), 2.0)
	var center: Vector2 = rect.get_center() - Vector2(0.0, 7.0)
	draw_circle(center, 15.0, Color(0.20, 0.27, 0.18, 0.72))
	draw_line(center - Vector2(6.0, 0.0), center + Vector2(6.0, 0.0), Color("e4d4a7"), 1.8)
	draw_line(center - Vector2(0.0, 6.0), center + Vector2(0.0, 6.0), Color("e4d4a7"), 1.8)
	_center_text(center + Vector2(0.0, 35.0), "建造", 13, Color("eee0bb"))
	if lot.key == _selected or lot.key == _hover:
		_selection(rect)

func _draw_building(lot: Dictionary) -> void:
	var rect: Rect2 = lot.rect
	var id: String = str(lot.id)
	var level: int = int(lot.get("level", 0))
	var queued: bool = lot.get("queue") is Dictionary
	var active: bool = lot.key == _selected or lot.key == _hover
	_draw_parcel_ground(lot)
	var ground: Rect2 = rect.grow(-5.0)
	var yard: Rect2 = Rect2(ground.position + Vector2(0.0, 17.0), Vector2(ground.size.x, maxf(13.0, ground.size.y - 45.0)))
	if level <= 0:
		_draw_foundation(yard)
	elif id == "wall":
		_pavilion(Rect2(yard.position + yard.size * Vector2(0.18, 0.20), yard.size * Vector2(0.64, 0.60)), Color("626553"), Color("a28c64"))
		_banner(yard.position + yard.size * Vector2(0.80, 0.25))
	elif _draw_city_sprite(lot, yard):
		pass
	elif id == "hall":
		_draw_official(yard)
	elif id == "house":
		draw_rect(Rect2(yard.position + yard.size * Vector2(0.08, 0.50), yard.size * Vector2(0.82, 0.48)), Color("91866a"))
		_pavilion(Rect2(yard.position + Vector2(yard.size.x * 0.05, 1.0), yard.size * Vector2(0.55, 0.58)), Color("646653"), Color("ab9a73"))
		_pavilion(Rect2(yard.position + yard.size * Vector2(0.70, 0.14), yard.size * Vector2(0.25, 0.50)), Color("797151"), Color("a99a71"))
		_pavilion(Rect2(yard.position + yard.size * Vector2(0.08, 0.66), yard.size * Vector2(0.25, 0.28)), Color("737155"), Color("ad9b75"))
		draw_line(Vector2(yard.position.x + 2.0, yard.end.y), Vector2(yard.end.x - 5.0, yard.end.y), Color("b0a17c"), 1.0)
	elif id == "market":
		_draw_market(yard)
	elif id == "drill":
		_draw_drill(yard)
	elif id == "warehouse":
		_draw_store(yard)
	elif id == "stable":
		_pavilion(Rect2(yard.position + Vector2(1.0, 1.0), yard.size * Vector2(0.96, 0.46)), Color("757455"), Color("a89970"))
		for i: int in range(3):
			var p: Vector2 = yard.position + yard.size * Vector2(0.18 + float(i) * 0.28, 0.75)
			draw_line(p, p + Vector2(6.0, 0.0), Color("564e39"), 3.0)
			draw_line(p + Vector2(5.0, 0.0), p + Vector2(6.0, -4.0), Color("564e39"), 2.0)
	elif id == "barracks" or id == "recruit":
		_pavilion(Rect2(yard.position + Vector2(1.0, 0.0), yard.size * Vector2(0.49, 0.66)), Color("555e55"), Color("a0916a"))
		var tent: Rect2 = Rect2(yard.position + yard.size * Vector2(0.65, 0.11), yard.size * Vector2(0.29, 0.55))
		draw_colored_polygon(PackedVector2Array([Vector2(tent.position.x, tent.end.y), Vector2(tent.get_center().x, tent.position.y), tent.end]), Color("b4a07b"))
		draw_colored_polygon(PackedVector2Array([Vector2(tent.get_center().x, tent.end.y), Vector2(tent.get_center().x, tent.position.y), tent.end]), Color("968568"))
		draw_line(Vector2(tent.get_center().x, tent.end.y), Vector2(tent.get_center().x, tent.position.y + tent.size.y * 0.45), Color("625841"), 1.0)
		for i: int in range(3):
			var rack: Vector2 = yard.position + yard.size * Vector2(0.14 + float(i) * 0.17, 0.85)
			draw_line(rack, rack - Vector2(0.0, 4.0), Color("78684b"), 1.0)
		_banner(yard.position + Vector2(yard.size.x * 0.55, yard.size.y * 0.72))
	elif id in ["smith", "workshop"]:
		_pavilion(Rect2(yard.position + Vector2(1.0, 0.0), yard.size * Vector2(0.62, 0.83)), Color("666658"), Color("9c8d66"))
		var kiln: Vector2 = yard.position + yard.size * Vector2(0.84, 0.51)
		draw_circle(kiln, minf(5.0, yard.size.y * 0.19), Color("615744"))
		draw_circle(kiln + Vector2(0.0, 1.0), 2.0, Color("b07946"))
	elif id == "beacon":
		var tower: Rect2 = Rect2(yard.position + yard.size * Vector2(0.30, 0.16), yard.size * Vector2(0.40, 0.72))
		draw_rect(tower, Color("aa9470"))
		draw_rect(Rect2(tower.position - Vector2(3.0, 0.0), Vector2(tower.size.x + 6.0, 4.0)), Color("c1aa7b"))
		draw_line(tower.position + Vector2(3.0, 6.0), tower.end - Vector2(3.0, 3.0), Color("706446"), 2.0)
		_banner(Vector2(tower.end.x, tower.position.y - 1.0))
	elif id == "wall":
		draw_rect(Rect2(yard.position + Vector2(0.0, yard.size.y * 0.29), Vector2(yard.size.x, yard.size.y * 0.62)), Color("98815a"))
		draw_rect(Rect2(yard.position + Vector2(0.0, yard.size.y * 0.23), Vector2(yard.size.x, 4.0)), Color("b6a076"))
		for i: int in range(4):
			draw_rect(Rect2(yard.position + Vector2(float(i) * yard.size.x / 4.0, 1.0), Vector2(yard.size.x * 0.12, yard.size.y * 0.29)), Color("b5a074"))
	elif id in ["academy", "embassy", "tavern"]:
		_pavilion(Rect2(yard.position + Vector2(yard.size.x * 0.08, 0.0), yard.size * Vector2(0.84, 0.73)), Color("52635c"), Color("b09f79"))
		draw_line(Vector2(yard.position.x + 3.0, yard.end.y), Vector2(yard.end.x - 3.0, yard.end.y), Color("c0ac81"), 2.0)
	else:
		# Inns and post stations have a main hall and an open guest/relay yard.
		_pavilion(Rect2(yard.position + Vector2(1.0, 0.0), yard.size * Vector2(0.70, 0.79)), Color("63665a"), Color("b2a078"))
		_pavilion(Rect2(yard.position + yard.size * Vector2(0.79, 0.27), yard.size * Vector2(0.19, 0.55)), Color("747050"), Color("a08e66"))
	if queued and level > 0:
		_scaffold(yard)
	var label: String = "城防营署" if id == "wall" else str(SHORT_NAMES.get(id, lot.get("name", id)))
	var font_size: int = 12 if grid_columns() == 3 else 13
	var strip: Rect2 = Rect2(rect.position.x + 3.0, rect.end.y - 25.0, rect.size.x - 6.0, 22.0)
	draw_rect(strip, Color(0.14, 0.20, 0.14, 0.82))
	_center_text(Vector2(rect.get_center().x, rect.end.y - 9.0), "%s · %d级" % [label, level], font_size, LABEL)
	if active:
		_selection(rect)
	if queued:
		var progress: Dictionary = _queue_progress(lot.queue)
		var seconds: int = int(progress.seconds)
		var remaining: String = "%d分%02d秒" % [floori(float(seconds) / 60.0), seconds % 60] if seconds >= 60 else "%d秒" % seconds
		var state_text: String = "待完工" if seconds <= 0 else remaining
		var badge: Rect2 = Rect2(rect.end.x - minf(rect.size.x - 36.0, 87.0) - 3.0, rect.position.y + 3.0, minf(rect.size.x - 36.0, 87.0), 17.0)
		draw_rect(badge, Color(0.29, 0.24, 0.13, 0.91))
		_center_text(Vector2(badge.get_center().x, badge.end.y - 4.0), state_text, 10, Color("f2d78b"))
		var bar: Rect2 = Rect2(rect.position.x + 3.0, rect.end.y - 3.0, rect.size.x - 6.0, 3.0)
		draw_rect(bar, Color("403b2b"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(progress.progress), bar.size.y)), GOLD)

func _draw_city_sprite(lot: Dictionary, yard: Rect2) -> bool:
	var id: String = str(lot.id)
	var level: int = int(lot.get("level", 1))
	var key: String = art_sprite_key(id, level)
	var sprite: AtlasTexture = _sprite_for_key(key)
	if sprite == null:
		return false
	var source_size: Vector2 = sprite.get_size()
	var scale: float = minf(yard.size.x / source_size.x, yard.size.y / source_size.y)
	var skin_scale: float = 1.0
	if id in ["hall", "barracks"]:
		skin_scale = 0.84 if level < 4 else 0.94 if level < 8 else 1.0
	elif id == "house":
		skin_scale = 0.89
	scale *= skin_scale
	var drawn_size: Vector2 = source_size * scale
	# Ground the base in the parcel, keeping the eaves and its entire shadow
	# within the same site. Labels and queued-state marks are drawn afterward.
	var destination: Rect2 = Rect2(yard.position + Vector2((yard.size.x - drawn_size.x) * 0.5, yard.size.y - drawn_size.y), drawn_size)
	draw_texture_rect(sprite, destination, false, Color.WHITE)
	var parcel: Rect2 = lot.get("rect", yard)
	var label_rect: Rect2 = Rect2(parcel.position.x, parcel.end.y - 25.0, parcel.size.x, 25.0)
	if id == "gateway":
		label_rect.position.y = yard.end.y + 2.0
	_sprite_records[str(lot.get("key", id))] = {"id": id, "site": int(lot.get("site", -1)), "level": level, "tierKey": key, "skinScale": skin_scale, "texture": sprite.atlas.resource_path, "region": sprite.region, "rect": destination, "parcel_rect": parcel, "label_rect": label_rect}
	return true

func _draw_official(yard: Rect2) -> void:
	var court: Rect2 = Rect2(yard.position + yard.size * Vector2(0.14, 0.66), yard.size * Vector2(0.72, 0.33))
	draw_rect(court, Color("b0a483"))
	draw_line(Vector2(court.position.x, court.end.y), Vector2(court.end.x, court.end.y), Color("c9b792"), 2.0)
	_pavilion(Rect2(yard.position + yard.size * Vector2(0.09, 0.01), yard.size * Vector2(0.82, 0.65)), Color("485b58"), Color("b8a278"))
	for side: float in [0.02, 0.87]:
		_pavilion(Rect2(yard.position + yard.size * Vector2(side, 0.67), yard.size * Vector2(0.11, 0.29)), Color("59655a"), Color("ac986f"))
	for i: int in range(3):
		draw_line(Vector2(court.get_center().x - court.size.x * 0.13, court.position.y + float(i) * 3.0), Vector2(court.get_center().x + court.size.x * 0.13, court.position.y + float(i) * 3.0), Color("93876a"), 1.5)
	_banner(yard.position + yard.size * Vector2(0.08, 0.54))
	_banner(yard.position + yard.size * Vector2(0.92, 0.54))

func _draw_market(yard: Rect2) -> void:
	# A gated market yard and raised watch/drum post distinguish commerce
	# from domestic courts, even at the small phone footprint.
	draw_line(yard.position, Vector2(yard.position.x, yard.end.y), Color("baaa7f"), 1.2)
	draw_line(Vector2(yard.end.x, yard.position.y), yard.end, Color("baaa7f"), 1.2)
	for i: int in range(3):
		var stall: Rect2 = Rect2(yard.position + Vector2(float(i) * yard.size.x / 3.0 + 1.0, 1.0), Vector2(yard.size.x * 0.28, yard.size.y * 0.48))
		draw_rect(stall, Color("bda27b") if i % 2 == 0 else Color("87745b"))
		draw_line(stall.position, Vector2(stall.position.x, stall.end.y + 3.0), Color("65533c"), 1.5)
		draw_line(Vector2(stall.end.x, stall.position.y), stall.end + Vector2(0.0, 3.0), Color("65533c"), 1.5)
		for item: int in range(2):
			draw_circle(Vector2(stall.position.x + 3.0 + float(item) * 5.0, stall.end.y + 4.0), 2.0, Color("baa46e"))
	var gate: Vector2 = Vector2(yard.get_center().x, yard.end.y - 1.0)
	draw_line(Vector2(yard.position.x, yard.end.y), gate - Vector2(5.0, 0.0), Color("baaa7f"), 1.2)
	draw_line(gate + Vector2(5.0, 0.0), yard.end, Color("baaa7f"), 1.2)
	draw_rect(Rect2(gate - Vector2(3.0, 7.0), Vector2(6.0, 6.0)), Color("867452"))
	_roof(Rect2(gate - Vector2(5.0, 9.0), Vector2(10.0, 5.0)), Color("5e6856"))

func _draw_drill(yard: Rect2) -> void:
	draw_rect(yard.grow(-1.0), Color("a19873"))
	for row: int in range(2):
		for column: int in range(3):
			var p: Vector2 = yard.position + yard.size * Vector2(0.24 + float(column) * 0.27, 0.33 + float(row) * 0.39)
			draw_circle(p, 2.0, Color("6b5340"))
			draw_line(p + Vector2(0.0, 2.0), p + Vector2(0.0, 5.0), Color("6b5340"), 1.5)
	_banner(yard.position + Vector2(yard.size.x - 3.0, 1.0))

func _draw_store(yard: Rect2) -> void:
	# Raised grain bins with conical thatch caps and a separate long store
	# have a different silhouette from tiled houses and military tents.
	for i: int in range(2):
		var diameter: float = minf(yard.size.x * 0.23, maxf(9.0, yard.size.y * 0.62))
		var p: Vector2 = yard.position + yard.size * Vector2(0.17 + float(i) * 0.27, 0.56)
		draw_rect(Rect2(p - Vector2(diameter * 0.44, diameter * 0.25), Vector2(diameter * 0.88, diameter * 0.49)), Color("b6a16e"))
		for leg: float in [-0.31, 0.31]:
			draw_line(p + Vector2(diameter * leg, diameter * 0.16), p + Vector2(diameter * leg, diameter * 0.36), Color("78684b"), 1.5)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-diameter * 0.56, -diameter * 0.22), p - Vector2(0.0, diameter * 0.80), p + Vector2(diameter * 0.56, -diameter * 0.22)]), Color("96905e"))
		draw_line(p - Vector2(0.0, diameter * 0.73), p + Vector2(diameter * 0.45, -diameter * 0.23), Color("b0a579"), 1.0)
	_pavilion(Rect2(yard.position + yard.size * Vector2(0.66, 0.17), yard.size * Vector2(0.31, 0.59)), Color("7b7554"), Color("b29d70"))
	for i: int in range(3):
		draw_circle(yard.position + yard.size * Vector2(0.61 + float(i) * 0.12, 0.89), 2.3, Color("c2b07e"))

func _draw_foundation(yard: Rect2) -> void:
	draw_rect(yard.grow(-2.0), Color("a08d69"), false, 2.0)
	_scaffold(yard)
	for i: int in range(3):
		draw_line(yard.position + Vector2(5.0, 6.0 + float(i) * 3.0), yard.position + Vector2(yard.size.x * 0.60, 6.0 + float(i) * 3.0), Color("c1a676"), 2.0)

func _scaffold(yard: Rect2) -> void:
	for x: float in [yard.position.x + 2.0, yard.end.x - 2.0]:
		draw_line(Vector2(x, yard.position.y - 1.0), Vector2(x, yard.end.y), GOLD, 1.2)
	draw_line(yard.position + Vector2(2.0, 1.0), Vector2(yard.end.x - 2.0, yard.position.y + 1.0), GOLD, 1.0)
	draw_line(yard.position + Vector2(2.0, 1.0), yard.end - Vector2(2.0, 1.0), GOLD, 1.0)

func _pavilion(rect: Rect2, roof: Color, timber: Color) -> void:
	var p: Vector2 = rect.position
	var dimensions: Vector2 = rect.size
	# Upper-left light, deep verandah, pillars and a stepped raised base.
	draw_rect(Rect2(p + dimensions * Vector2(0.08, 0.88), dimensions * Vector2(0.91, 0.12)), Color(0.11, 0.14, 0.11, 0.33))
	draw_rect(Rect2(p + dimensions * Vector2(0.04, 0.79), dimensions * Vector2(0.92, 0.16)), Color("b5aa87"))
	draw_rect(Rect2(p + dimensions * Vector2(0.06, 0.85), dimensions * Vector2(0.88, 0.10)), Color("8d856b"))
	draw_rect(Rect2(p + dimensions * Vector2(0.09, 0.38), dimensions * Vector2(0.82, 0.45)), timber)
	draw_rect(Rect2(p + dimensions * Vector2(0.12, 0.46), dimensions * Vector2(0.76, 0.34)), timber.darkened(0.36))
	draw_rect(Rect2(p + dimensions * Vector2(0.45, 0.50), dimensions * Vector2(0.15, 0.33)), Color("27382f"))
	for column: float in [0.14, 0.31, 0.68, 0.86]:
		draw_line(p + dimensions * Vector2(column, 0.38), p + dimensions * Vector2(column, 0.82), Color("af8f65"), clampf(dimensions.x * 0.025, 1.0, 3.0))
		draw_line(p + dimensions * Vector2(column - 0.012, 0.45), p + dimensions * Vector2(column - 0.012, 0.79), Color("d0b98e"), 0.7)
	_roof(Rect2(p, dimensions * Vector2(1.0, 0.58)), roof)

func _roof(rect: Rect2, color: Color) -> void:
	var top: Vector2 = rect.position
	var w: float = rect.size.x
	var h: float = rect.size.y
	var ridge_left: Vector2 = top + Vector2(w * 0.17, h * 0.12)
	var ridge_right: Vector2 = top + Vector2(w * 0.83, h * 0.12)
	var eave_left: Vector2 = top + Vector2(0.0, h * 0.79)
	var eave_right: Vector2 = top + Vector2(w, h * 0.79)
	var front_left: Vector2 = top + Vector2(w * 0.19, h * 0.94)
	var front_right: Vector2 = top + Vector2(w * 0.81, h * 0.94)
	draw_colored_polygon(PackedVector2Array([top + Vector2(w * 0.03, h * 0.43), ridge_left, ridge_right, top + Vector2(w * 0.97, h * 0.43), eave_right, front_right, front_left, eave_left]), color.darkened(0.12))
	draw_colored_polygon(PackedVector2Array([ridge_left, ridge_right, eave_right, front_right, front_left, eave_left]), color.lightened(0.06))
	draw_line(ridge_left, ridge_right, color.lightened(0.30), 1.4)
	draw_polyline(PackedVector2Array([eave_left, front_left, front_right, eave_right]), color.darkened(0.35), 2.0, true)
	var courses: int = clampi(int(w / 7.0), 4, 16)
	for i: int in range(1, courses):
		var fraction: float = float(i) / float(courses)
		draw_line(ridge_left.lerp(ridge_right, fraction), front_left.lerp(front_right, fraction), color.darkened(0.13), 0.65)
	for row: float in [0.36, 0.62]:
		draw_line(ridge_left.lerp(front_left, row), ridge_right.lerp(front_right, row), color.lightened(0.11), 0.6)

func _draw_gate(base: Vector2) -> void:
	var w: float = clampf(_plan_width() * 0.23, 76.0, 192.0)
	var height: float = 104.0 if _plan_width() >= 650.0 else 80.0
	var available: Rect2 = Rect2(base - Vector2(w * 0.5, height), Vector2(w, height))
	var lot: Dictionary = {"id": "gateway", "site": -1, "key": "gateway", "rect": available}
	if perimeter_level() <= 1:
		base.y -= 34.0
		_draw_palisade(Rect2(base - Vector2(w * 0.35, 25.0), Vector2(w * 0.22, 25.0)))
		_draw_palisade(Rect2(base + Vector2(w * 0.13, -25.0), Vector2(w * 0.22, 25.0)))
		draw_line(base + Vector2(-w * 0.35, -19.0), base + Vector2(w * 0.35, -19.0), Color("795936"), 4.0)
	elif not _draw_city_sprite(lot, available):
		draw_rect(Rect2(base - Vector2(w * 0.44, 40.0), Vector2(w * 0.88, 41.0)), Color("aa946c"))
		draw_rect(Rect2(base + Vector2(w * 0.28, -40.0), Vector2(w * 0.16, 41.0)), Color("817155"))
		draw_rect(Rect2(base - Vector2(w * 0.16, 26.0), Vector2(w * 0.32, 28.0)), Color("29392e"))
		_pavilion(Rect2(base - Vector2(w * 0.49, 79.0), Vector2(w * 0.98, 47.0)), Color("4d5f57"), Color("a08b61"))
		_banner(base + Vector2(w * 0.34, -74.0))
		_banner(base + Vector2(-w * 0.34, -74.0))
	_center_text(base + Vector2(0.0, 12.0), "南门 · 城防", 10, LABEL)

func _banner(point: Vector2) -> void:
	draw_line(point, point + Vector2(0.0, 13.0), Color("c2ae7e"), 1.0)
	draw_colored_polygon(PackedVector2Array([point, point + Vector2(7.0, 1.0), point + Vector2(6.0, 6.0), point + Vector2(0.0, 5.0)]), Color("7d4437"))

func _draw_tree(point: Vector2, radius: float) -> void:
	draw_line(point, point + Vector2(0.0, radius + 2.0), Color("61573f"), 1.2)
	draw_circle(point + Vector2(1.0, 1.0), radius + 1.0, Color("4c5e43"))
	draw_circle(point + Vector2(-1.0, -1.0), radius, Color("697952"))

func _selection(rect: Rect2) -> void:
	draw_rect(rect, Color(0.82, 0.70, 0.43, 0.11))
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var direction: Vector2 = Vector2(1.0 if corner.x == rect.position.x else -1.0, 1.0 if corner.y == rect.position.y else -1.0)
		draw_line(corner, corner + Vector2(direction.x * 8.0, 0.0), GOLD, 2.0)
		draw_line(corner, corner + Vector2(0.0, direction.y * 8.0), GOLD, 2.0)

func _center_text(point: Vector2, text: String, font_size: int, color: Color) -> void:
	var width: float = CHINESE_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_text(point - Vector2(width * 0.5, 0.0), text, font_size, color)

func _text(point: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(CHINESE_FONT, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
