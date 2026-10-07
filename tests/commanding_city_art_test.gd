extends SceneTree

## Check the shipped art and its real scene integration, never a substitute texture.
const CityView: GDScript = preload("res://src/city_view.gd")
const CORE_ART_IDS: Array[String] = ["hall", "gateway", "barracks", "warehouse", "market", "house"]

var _checks: int = 0
var _failures: int = 0
var _selections: Array[int] = []
var _art_ids: Array[String] = []

func _initialize() -> void:
	create_timer(40).timeout.connect(func() -> void: push_error("Commanding city art test timed out"); quit(1))
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in range(4):
		await process_frame

func _set_city_size(city: Control, width: float) -> void:
	city.custom_minimum_size.y = city.recommended_height(width)
	city.size = Vector2(width, city.recommended_height(width))

func _fixture() -> Dictionary:
	var node: String = OS.get_environment("TK_NODE")
	_check(not node.is_empty(), "Atlas scene integration requires the canonical prepared fixture through TK_NODE.")
	if node.is_empty():
		return {}
	var output: Array = []
	var result: int = OS.execute(node, [ProjectSettings.globalize_path("res://tests/helpers/historic-city-view.mjs")], output)
	_check(result == 0 and not output.is_empty(), "The actual canonical game bridge must prepare the all-building fixture.")
	if result != 0 or output.is_empty():
		return {}
	return (JSON.parse_string(str(output[0])) as Dictionary).get("view", {}).duplicate(true)

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
	await _settle()
	await RenderingServer.frame_post_draw
	var folder: String = _capture_folder()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(root.get_texture().get_image().save_png(folder + "rts-city-mixed-state-%s.png" % name) == OK, "The actual mixed-state city scene must capture to the selected story evidence folder.")

func _region_samples(image: Image, region: Rect2) -> Vector2i:
	var transparent: int = 0
	var visible: int = 0
	for y: int in range(20):
		for x: int in range(20):
			var pixel: Vector2i = Vector2i(region.position + region.size * Vector2((float(x) + 0.5) / 20.0, (float(y) + 0.5) / 20.0))
			var alpha: float = image.get_pixel(pixel.x, pixel.y).a
			if alpha < 0.01:
				transparent += 1
			if alpha > 0.1:
				visible += 1
	return Vector2i(transparent, visible)

func _check_draw_records(city: Control, view: Dictionary, phone: bool) -> void:
	var records: Dictionary = city.sprite_draw_records()
	var expected: Array[String] = []
	if city.perimeter_level() > 1:
		expected.append("gateway")
	for building: Dictionary in view.buildings:
		if str(building.id) in _art_ids and str(building.id) != "wall" and int(building.level) > 0:
			expected.append("%s#%d" % [str(building.id), int(building.site)])
	var actual: Array = records.keys()
	expected.sort()
	actual.sort()
	_check(actual == expected, "Only actual positive-level canonical buildings and the decorative gateway may draw atlas art.")
	for key: String in expected:
		if not records.has(key):
			continue
		var row: Dictionary = records[key]
		var destination: Rect2 = row.rect
		var region: Rect2 = row.region
		var parcel: Rect2 = row.parcel_rect
		_check(destination.has_area() and parcel.grow(0.1).encloses(destination), "Sprite %s must stay inside its own canonical parcel." % key)
		_check(is_equal_approx(destination.size.x / destination.size.y, region.size.x / region.size.y), "Sprite %s must preserve the actual source perspective/aspect rather than stretching." % key)
		if key == "gateway":
			_check(not city._hit_records.has(key) and city._building_at(destination.get_center()) == "perimeter", "Gate opens defenses without introducing a new canonical site.")
		else:
			var hit: Dictionary = city._hit_records.get(key, {})
			_check(not hit.is_empty() and str(hit.id) == str(row.id) and int(hit.site) == int(row.site) and city._building_at(destination.get_center()) == key, "Atlas sprite %s must keep its exact canonical building and site identity." % key)
			_check(destination.end.y <= (row.label_rect as Rect2).position.y, "Sprite %s must leave room for its level label." % key)
			if phone:
				_check(parcel.size.x >= 44.0 and parcel.size.y >= 44.0, "Phone atlas rendering must retain a 44px canonical tap target.")
	var houses: Array = view.buildings.filter(func(row: Dictionary) -> bool: return str(row.id) == "house" and int(row.level) > 0)
	if records.has("hall#14") and not houses.is_empty():
		var house_key: String = "house#%d" % int(houses[0].site)
		_check((records["hall#14"].parcel_rect as Rect2).size.is_equal_approx((records[house_key].parcel_rect as Rect2).size), "The actual hall remains in one uniform canonical grid cell rather than covering reserved neighbors.")

func _click_sprite(city: Control, key: String) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_MOUSE
	event.position = (city.sprite_draw_records()[key].rect as Rect2).get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	city._gui_input(event)

func _run() -> void:
	_check(FileAccess.file_exists(CityView.CITY_ART_PATH) and FileAccess.file_exists(CityView.CITY_ART_METADATA), "The actual generated atlas and its checked-in region metadata must exist.")
	if _failures > 0:
		quit(1)
		return
	var file: FileAccess = FileAccess.open(CityView.CITY_ART_METADATA, FileAccess.READ)
	var metadata: Dictionary = JSON.parse_string(file.get_as_text())
	var images: Dictionary = {}
	for source: Dictionary in metadata.get("sources", []):
		var path: String = str(source.texture)
		var image: Image = Image.new()
		_check(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK and not image.is_empty() and image.detect_alpha() != Image.ALPHA_NONE, "Every actual shipped atlas must decode with real transparency.")
		_check(Vector2i(int(source.size[0]), int(source.size[1])) == image.get_size() and str(source.sha256) == FileAccess.get_sha256(path), "Each atlas source must match its recorded pixel dimensions and source hash.")
		images[path] = image
	_check(str(metadata.get("texture", "")) == CityView.CITY_ART_PATH and Vector2i(int(metadata.size[0]), int(metadata.size[1])) == (images[CityView.CITY_ART_PATH] as Image).get_size(), "Primary metadata must describe the actual shipped image path and size.")
	_check(str(metadata.get("sourceSha256", "")) == FileAccess.get_sha256(CityView.CITY_ART_PATH), "The atlas metadata must identify the generated source pixels exactly.")
	var entries: Dictionary = {}
	for id: String in metadata.get("regions", {}):
		entries[id] = {"texture": CityView.CITY_ART_PATH, "region": metadata.regions[id]}
	for sprite: Dictionary in metadata.get("sprites", []):
		entries[str(sprite.id)] = sprite
	for id: String in entries:
		_art_ids.append(id)
	_check(entries.size() == 17, "The final artwork supplies sixteen real building types and one decorative gateway.")
	var city: Control = CityView.new()
	root.add_child(city)
	_set_city_size(city, 1000.0)
	var view: Dictionary = _fixture()
	if view.is_empty():
		city.queue_free()
		quit(1)
		return
	var original: Dictionary = view.duplicate(true)
	city.set_city(view)
	city.building_selected.connect(func(_id: String) -> void: _selections.append(city.selected_site()))
	await _settle()
	_check(city.art_loaded(), "The production city must load all required core AtlasTexture regions.")
	if not city.art_loaded():
		city.queue_free()
		quit(1)
		return
	var regions: Dictionary = city.art_regions()
	var sprite_textures: Dictionary = city.art_sprite_textures()
	var used_paths: Dictionary = {}
	for entry: Dictionary in entries.values():
		used_paths[str(entry.texture)] = true
	var paths: Array = used_paths.keys()
	var source_paths: Array = images.keys()
	paths.sort()
	source_paths.sort()
	_check(regions.size() == entries.size() and sprite_textures.size() == entries.size() and paths == source_paths, "All seventeen imported sprites use the metadata's current atlas and isolated texture paths.")
	var canonical_ids: Array = view.buildings.map(func(row: Dictionary) -> String: return str(row.id))
	_check(canonical_ids.all(func(id: String) -> bool: return entries.has(id)) and _art_ids.all(func(id: String) -> bool: return id == "gateway" or canonical_ids.has(id)), "The artwork covers exactly actual canonical building types plus the decorative gate.")
	for id: String in _art_ids:
		var path: String = str(entries[id].texture)
		var image: Image = images[path]
		var source: Array = entries[id].region
		var expected_region: Rect2 = Rect2(float(source[0]), float(source[1]), float(source[2]), float(source[3]))
		var region: Rect2 = regions.get(id, Rect2())
		_check(region == expected_region and Rect2(Vector2.ZERO, Vector2(image.get_size())).encloses(region), "Atlas region %s must use its actual padded metadata bounds." % id)
		var sprite: AtlasTexture = city._art_sprites[id] as AtlasTexture
		_check(sprite != null and sprite.atlas == city._art_textures[path] and str(sprite_textures[id]) == path and sprite.region == region and sprite.filter_clip, "Atlas region %s must reference its correct imported source atlas and clip neighboring art." % id)
		var samples: Vector2i = _region_samples(image, region)
		_check(samples.x > 0 and samples.y > 0, "Each atlas region must contain both visible art and transparent surroundings: %s." % id)
	var no_overlap: bool = true
	for a: int in range(_art_ids.size()):
		for b: int in range(a + 1, _art_ids.size()):
			if str(entries[_art_ids[a]].texture) == str(entries[_art_ids[b]].texture) and (regions[_art_ids[a]] as Rect2).intersects(regions[_art_ids[b]]):
				no_overlap = false
	_check(no_overlap, "Distinct regions on each source atlas must not bleed into each other.")
	_check(str(sprite_textures.hall) == str(entries.hall.texture) and str(sprite_textures.house) == str(entries.house.texture), "Hall and house IDs retain their declared source paths without assuming equal grid coordinates.")
	_check_draw_records(city, view, false)
	_check(not city._hit_records.values().any(func(row: Dictionary) -> bool: return str(row.id) == "recruit") and not city.sprite_draw_records().values().any(func(row: Dictionary) -> bool: return str(row.id) == "recruit"), "Cached artwork absent from the canonical view must not fabricate a recruitment building or action.")
	_set_city_size(city, 390.0)
	await _settle()
	_check_draw_records(city, view, true)
	var houses: Array = view.buildings.filter(func(row: Dictionary) -> bool: return str(row.id) == "house")
	_check(houses.size() >= 2, "The real prepared fixture must exercise repeated houses.")
	var first_house: int = int(houses[0].site)
	var second_house: int = int(houses[1].site)
	var first_key: String = "house#%d" % first_house
	_click_sprite(city, first_key)
	_click_sprite(city, "house#%d" % second_house)
	_check(_selections == [first_house, second_house], "Repeated houses sharing one art region must remain independently selectable by their true site.")
	var safe_records: Dictionary = city.sprite_draw_records()
	var hall_rect: Rect2 = safe_records["hall#14"].rect
	safe_records["hall#14"].rect = Rect2()
	regions.hall = Rect2()
	_check(city.sprite_draw_records()["hall#14"].rect == hall_rect and (city.art_regions().hall as Rect2).has_area(), "External art diagnostics must not corrupt the live atlas or hit geometry.")
	var hits: Dictionary = city._hit_boxes.duplicate(true)
	city._art_sprites.erase("house")
	var house_path: String = str(entries.house.texture)
	var house_image: Image = images[house_path]
	city._add_art_region("house", [-10, 0, house_image.get_width(), house_image.get_height()], city._art_textures[house_path])
	_check(not city._art_sprites.has("house"), "An out-of-bounds atlas region must be rejected rather than displaying unrelated art.")
	city.queue_redraw()
	await _settle()
	_check(not city.sprite_draw_records().has(first_key) and city._hit_boxes == hits and city._building_at((hits[first_key] as Rect2).get_center()) == first_key, "A rejected/missing art region must leave the procedural fallback and real canonical actions intact.")
	city._add_art_region("house", entries.house.region, city._art_textures[house_path])
	var queued: Dictionary = view.duplicate(true)
	for building: Dictionary in queued.buildings:
		if int(building.site) == first_house:
			building.id = "market"
			building.level = 0
			building.queue = {"site": first_house, "id": "market", "level": 1, "start": 1800000000000, "end": 1800000030000}
		elif int(building.site) == second_house:
			building.queue = {"site": second_house, "id": "house", "level": int(building.level) + 1, "start": 1800000000000, "end": 1800000060000}
	for slot: Dictionary in queued.buildingSlots:
		if int(slot.site) == first_house:
			slot.id = "market"
			slot.level = 0
	queued.queues.build = queued.buildings.filter(func(row: Dictionary) -> bool: return row.get("queue") != null).map(func(row: Dictionary) -> Dictionary: return row.queue)
	city.set_city(queued, 1800000015000.0)
	await _settle()
	var zero_key: String = "market#%d" % first_house
	_check(city._hit_records.has(zero_key) and int(city._hit_records[zero_key].level) == 0 and not city.sprite_draw_records().has(zero_key), "A canonical level-zero construction stays a foundation rather than showing completed atlas art.")
	_check(city.sprite_draw_records().has("house#%d" % second_house) and city._hit_records["house#%d" % second_house].queue != null, "An upgrading positive-level building keeps its real sprite while retaining its canonical queue state.")
	_set_city_size(city, 900.0)
	await _settle()
	_check_draw_records(city, queued, false)
	await _capture("desktop", city)
	_set_city_size(city, 390.0)
	await _settle()
	_check_draw_records(city, queued, true)
	await _capture("phone", city)
	_check(view == original, "Loading and drawing atlas art must not mutate the canonical DTO.")
	city.queue_free()
	await process_frame
	print("COMMANDING_CITY_ART_CHECKS=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
