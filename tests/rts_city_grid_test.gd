extends SceneTree

## Rule-produced fixtures; no player's save, network, or replacement economy.
const CityView: GDScript = preload("res://src/city_view.gd")
const FIXTURE_TIME_MS: float = 1800000000000.0

var checks: int = 0
var failures: int = 0
var events: Array[Dictionary] = []
var catalog: Array = []

func _initialize() -> void:
	create_timer(70).timeout.connect(func() -> void: push_error("RTS_CITY_GRID_TIMEOUT"); quit(1))
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in 4:
		await process_frame

func _fixtures() -> Dictionary:
	var node: String = OS.get_environment("TK_NODE")
	_check(not node.is_empty(), "TK_NODE supplies the authoritative fixture runtime")
	if node.is_empty():
		return {}
	# Reuse the established prepared fixture; capture its stdout rather than
	# copying its setup or duplicating canonical building/repeat rules.
	var script: String = """const {createGameRuntime} = await import(process.argv[1]);
const {gameView} = await import(process.argv[2]);
const now = 1800000000000;
const runtime = createGameRuntime({now});
const fresh = gameView(runtime.Game, now, runtime);
const catalog = [...runtime.Game.cityIds];
const write = process.stdout.write.bind(process.stdout);
let prepared = '';
process.stdout.write = chunk => { prepared += String(chunk); return true; };
try { await import(process.argv[3]); } finally { process.stdout.write = write; }
write(JSON.stringify({fresh, prepared: JSON.parse(prepared).view, catalog}).replace(/[^\\x00-\\x7F]/g, c => String.fromCharCode(92, 117) + c.charCodeAt(0).toString(16).padStart(4, String.fromCharCode(48))));
"""
	var arguments: Array[String] = ["--input-type=module", "-e", script]
	for path: String in ["vendor/legacy/online/runtime.mjs", "bridge/dto.mjs", "tests/helpers/historic-city-view.mjs"]:
		arguments.append("file:///" + ProjectSettings.globalize_path("res://" + path).trim_prefix("/"))
	var output: Array = []
	var status: int = OS.execute(node, arguments, output, true)
	_check(status == 0 and not output.is_empty(), "Fresh and prepared grids come from the actual canonical bridge")
	if status != 0 or output.is_empty():
		push_error(str(output))
		return {}
	var parsed: Variant = JSON.parse_string(str(output[0]))
	_check(parsed is Dictionary, "Canonical fixture output remains valid JSON across UTF-8 pipe chunks")
	return parsed if parsed is Dictionary else {}

func _parcel_map(city: Control) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in city.parcel_draw_records():
		result[int(row.site)] = row
	return result

func _key(row: Dictionary) -> String:
	return "%s#%d" % ["empty" if row.get("id") == null or str(row.get("id", "")).is_empty() else str(row.id), int(row.site)]

func _check_grid(city: Control, view: Dictionary, width: float) -> Dictionary:
	city.custom_minimum_size.y = city.recommended_height(width)
	city.size = Vector2(width, city.recommended_height(width))
	city.set_city(view)
	await _settle()
	var columns: int = city.grid_columns(width)
	_check(columns == (3 if width < 600.0 else 6), "The grid adapts columns without changing its 36 canonical site identities")
	var parcels: Dictionary = _parcel_map(city)
	_check(parcels.size() == 36, "All canonical slots, including reserved cells, have one visible grid parcel")
	var uniform: bool = true
	var no_overlap: bool = true
	var expected_hits: int = 0
	var first_size: Vector2 = (parcels.get(0, {}).get("rect", Rect2()) as Rect2).size
	for slot: Dictionary in view.buildingSlots:
		var site: int = int(slot.site)
		if not parcels.has(site):
			_check(false, "Missing canonical parcel %d" % site)
			continue
		var row: Dictionary = parcels[site]
		var rect: Rect2 = row.rect
		_check(int(row.row) == int(float(site) / float(columns)) and int(row.column) == site % columns, "Site %d stays in canonical row/column order" % site)
		_check(Rect2(Vector2.ZERO, city.size).encloses(rect) and rect.has_area(), "Site %d stays inside the scrollable scene" % site)
		uniform = uniform and rect.size.is_equal_approx(first_size)
		if width <= 390.0:
			_check(rect.size.x >= 44.0 and rect.size.y >= 44.0, "Phone parcel %d remains at least 44px in both dimensions" % site)
		if bool(slot.reserved):
			_check(bool(row.reserved) and city._building_at(rect.get_center()).is_empty(), "Reserved site %d cannot produce a build or upgrade action" % site)
		else:
			expected_hits += 1
			var key: String = _key(slot)
			_check(city._hit_records.has(key) and int(city._hit_records[key].site) == site and city._building_at(rect.get_center()) == key, "Grid cell %d resolves its exact current building/empty site" % site)
		if site >= columns and parcels.has(site - columns):
			var above: Rect2 = parcels[site - columns].rect
			_check(is_equal_approx(rect.position.x, above.position.x) and rect.position.y > above.end.y - 0.01, "Columns have a clear vertical cell boundary at site %d" % site)
		for other: int in range(site):
			if parcels.has(other) and rect.intersects(parcels[other].rect):
				no_overlap = false
	_check(uniform and no_overlap, "Every site is one uniform, non-overlapping grid cell, including the hall")
	_check(city._hit_records.size() == expected_hits, "Only actual nonreserved slots have interactive grid identities")
	return city._hit_boxes.duplicate(true)

func _metadata_entries(metadata: Dictionary) -> Dictionary:
	var entries: Dictionary = {}
	for id: String in metadata.get("regions", {}):
		entries[id] = {"texture": metadata.get("texture", CityView.CITY_ART_PATH), "region": metadata.regions[id]}
	for row: Dictionary in metadata.get("sprites", []):
		_check(not entries.has(str(row.id)), "Atlas metadata does not replace a previously assigned building ID")
		entries[str(row.id)] = row
	return entries

func _check_art(city: Control, view: Dictionary) -> void:
	_check(FileAccess.file_exists(CityView.CITY_ART_METADATA), "The RTS atlas metadata is shipped in the project")
	if not FileAccess.file_exists(CityView.CITY_ART_METADATA):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CityView.CITY_ART_METADATA))
	_check(parsed is Dictionary, "RTS atlas metadata is valid JSON")
	if not parsed is Dictionary:
		return
	var metadata: Dictionary = parsed
	var entries: Dictionary = _metadata_entries(metadata)
	var expected: Array = catalog.duplicate()
	expected.append("gateway")
	expected.sort()
	var actual: Array = entries.keys()
	actual.sort()
	_check(actual == expected and actual.size() == 17, "Only the current sixteen canonical building types and the decorative gate are supplied")
	var images: Dictionary = {}
	_check(not metadata.get("sources", []).is_empty(), "Every RTS texture source is recorded in metadata")
	for source: Dictionary in metadata.get("sources", []):
		var path: String = str(source.texture)
		var image: Image = Image.new()
		var status: int = image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		_check(status == OK and not image.is_empty() and image.detect_alpha() != Image.ALPHA_NONE, "Atlas %s decodes with actual transparency" % path)
		if status != OK or image.is_empty():
			continue
		_check(str(source.sha256) == FileAccess.get_sha256(path) and image.get_size() == Vector2i(int(source.size[0]), int(source.size[1])), "Atlas %s matches its declared dimensions and source SHA" % path)
		images[path] = image
	var used_sources: Dictionary = {}
	for id: String in entries:
		used_sources[str(entries[id].texture)] = true
	var declared_paths: Array = images.keys()
	var used_paths: Array = used_sources.keys()
	declared_paths.sort()
	used_paths.sort()
	_check(declared_paths == used_paths, "Recorded source textures cover exactly the current regions, allowing isolated assets without forced atlas grids")
	var regions: Dictionary = city.art_regions()
	_check(city.art_loaded() and regions.size() == entries.size(), "The production grid actually imports the complete RTS art set")
	var no_overlap: bool = true
	for id: String in entries:
		var entry: Dictionary = entries[id].duplicate(true)
		# Selector now exposes actual level-one tiers and the matching gate,
		# while base regions remain separately audited for missing-art fallback.
		if id in ["hall", "barracks"]:
			entry = (metadata.tiers[id][0] as Dictionary).duplicate(true)
		elif id == "gateway":
			entry = {"texture":metadata.environment.texture,"region":metadata.environment.regions.gate}
		var path: String = str(entry.texture)
		var texture: Texture2D = city.art_sprite_texture(id)
		if not images.has(path):
			var variant_image: Image = Image.new()
			_check(variant_image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK, "Tier/environment source decodes with transparent pixels")
			images[path] = variant_image
		_check(texture is AtlasTexture, "The actual grid/chooser thumbnail for %s uses its imported region" % id)
		if not texture is AtlasTexture or not images.has(path):
			continue
		var sprite: AtlasTexture = texture as AtlasTexture
		var bounds: Array = entry.region
		var region: Rect2 = Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3]))
		_check(sprite.region == region and sprite.filter_clip and sprite.atlas.resource_path == path and Rect2(Vector2.ZERO, Vector2((images[path] as Image).get_size())).encloses(region), "Building %s clips its correct source bounds rather than a neighboring sprite" % id)
		var transparent: bool = false
		var visible: bool = false
		for y: int in 16:
			for x: int in 16:
				var pixel: Vector2i = Vector2i(region.position + region.size * Vector2((float(x) + 0.5) / 16.0, (float(y) + 0.5) / 16.0))
				var alpha: float = (images[path] as Image).get_pixel(pixel.x, pixel.y).a
				transparent = transparent or alpha < 0.01
				visible = visible or alpha > 0.1
		_check(transparent and visible, "Region %s contains visible architecture and transparent surroundings" % id)
		for other: String in entries:
			if id >= other or str(entries[other].texture) != path:
				continue
			var values: Array = entries[other].region
			if region.intersects(Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))):
				no_overlap = false
	_check(no_overlap, "Source regions do not overlap on any of the three atlases")
	var records: Dictionary = city.sprite_draw_records()
	var expected_keys: Array[String] = []
	if city.perimeter_level() > 1:
		expected_keys.append("gateway")
	for building: Dictionary in view.buildings:
		if int(building.level) > 0 and str(building.id) != "wall":
			expected_keys.append(_key(building))
	expected_keys.sort()
	var keys: Array = records.keys()
	keys.sort()
	_check(keys == expected_keys, "Only actual positive-level buildings and the decorative gate draw completed art")
	for key: String in expected_keys:
		if not records.has(key):
			continue
		var row: Dictionary = records[key]
		var rect: Rect2 = row.rect
		var region: Rect2 = row.region
		_check(rect.has_area() and (row.parcel_rect as Rect2).grow(0.1).encloses(rect) and is_equal_approx(rect.size.x / rect.size.y, region.size.x / region.size.y), "Sprite %s preserves source perspective and stays within its own parcel" % key)
		if key == "gateway":
			_check(city._building_at(rect.get_center()) == "perimeter" and not city._hit_records.has(key), "Gate opens perimeter defenses without fabricating a canonical site")
		else:
			_check(city._building_at(rect.get_center()) == key and rect.end.y <= (row.label_rect as Rect2).position.y, "Sprite %s remains clickable as its exact site and leaves its label readable" % key)

func _mouse(city: Control, key: String, device: int = InputEvent.DEVICE_ID_MOUSE) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.device = device
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = (city._hit_boxes[key] as Rect2).get_center()
	city._gui_input(event)

func _touch(city: Control, point: Vector2, pressed: bool, index: int = 0, canceled: bool = false) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	event.index = index
	event.canceled = canceled
	city._gui_input(event)

func _drag(city: Control, point: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.position = point
	event.index = 0
	city._gui_input(event)

func _check_gestures(city: Control, fresh: Dictionary) -> void:
	city.set_city(fresh)
	var point: Vector2 = (city._hit_boxes["empty#35"] as Rect2).get_center()
	var count: int = events.size()
	_check(city.mouse_filter == Control.MOUSE_FILTER_PASS, "Raw touch/drag and emulated mouse can reach the parent ScrollContainer")
	_mouse(city, "empty#35", InputEvent.DEVICE_ID_EMULATION)
	_touch(city, point, true)
	_check(events.size() == count, "A touch or emulated mouse press never opens the last grid parcel")
	_touch(city, point, false)
	_check(events.size() == count + 1 and events.back().site == 35 and events.back().empty, "A released phone tap selects actual final site35 exactly once")
	count = events.size()
	_touch(city, point, true)
	_drag(city, point + Vector2(0.0, 40.0))
	_drag(city, point)
	_touch(city, point, false)
	_check(events.size() == count, "A scroll drag returning to the same cell cannot become a building tap")
	_touch(city, point, true, 2)
	_touch(city, point, false, 2, true)
	_check(events.size() == count, "Canceled touch does not select a grid parcel")
	_touch(city, point, true)
	city.position = Vector2(0.0, -20.0)
	_drag(city, point)
	_touch(city, point, false)
	city.position = Vector2.ZERO
	_check(events.size() == count, "Canvas movement during scrolling rejects a tap even when local finger coordinates match")
	_touch(city, point, true)
	_touch(city, point, true, 3)
	_touch(city, point, false)
	_check(events.size() == count, "A second finger cannot turn a multiple-touch gesture into construction")
	_touch(city, point, true)
	var other: Dictionary = fresh.duplicate(true)
	other.city.id = "rts_other_source"
	city.set_city(other)
	_touch(city, point, false)
	_check(events.size() == count and city.selected_site() == -1, "Changing source city clears its selected site and unfinished touch")
	city.set_city(fresh)
	_mouse(city, "empty#35")
	_check(events.size() == count + 1 and city.selected_site() == 35, "A physical mouse click still selects the exact final cell")

func _capture(name: String, city: Control) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	var folder: String = "res://production/qa/evidence/story-016/"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-folder="):
			folder = argument.trim_prefix("--capture-folder=").trim_suffix("/") + "/"
	root.size = Vector2i(city.size)
	city.queue_redraw()
	await _settle()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(root.get_texture().get_image().save_png(folder + name + ".png") == OK, "RTS grid native evidence is saved")

func _run() -> void:
	var fixtures: Dictionary = _fixtures()
	if fixtures.is_empty():
		quit(1)
		return
	catalog = fixtures.catalog
	var fresh: Dictionary = fixtures.fresh
	var developed: Dictionary = fixtures.prepared
	var original: Dictionary = developed.duplicate(true)
	_check(fresh.buildingSlots.size() == 36 and fresh.buildings.size() == 1 and fresh.buildings[0].id == "hall" and int(fresh.buildings[0].site) == 14, "Fresh fixture preserves the authoritative 36-site layout and hall14")
	_check(fresh.buildingSlots.filter(func(row: Dictionary) -> bool: return bool(row.reserved)).map(func(row: Dictionary) -> int: return int(row.site)) == [15, 20, 21], "Fresh canonical reserved slots are exactly 15/20/21")
	var city: Control = CityView.new()
	root.add_child(city)
	city.building_selected.connect(func(id: String) -> void: events.append({"id": id, "site": city.selected_site(), "empty": false}))
	city.empty_site_selected.connect(func(site: int) -> void: events.append({"id": "", "site": site, "empty": true}))
	await _check_grid(city, fresh, 390.0)
	_check_art(city, fresh)
	await _capture("rts-city-grid-fresh-phone", city)
	await _check_grid(city, fresh, 358.0)
	_check_gestures(city, fresh)
	for width: float in [900.0, 390.0]:
		var layout: Dictionary = await _check_grid(city, developed, width)
		_check_art(city, developed)
		var reordered: Dictionary = developed.duplicate(true)
		reordered.buildingSlots.reverse()
		reordered.buildings.reverse()
		city.set_city(reordered)
		await _settle()
		_check(city._hit_boxes == layout, "Polling and DTO array order do not move canonical grid parcels")
	var houses: Array = developed.buildings.filter(func(row: Dictionary) -> bool: return str(row.id) == "house")
	_check(houses.size() >= 2, "Prepared canonical fixture has independently selectable repeated houses")
	if houses.size() >= 2:
		var count: int = events.size()
		_mouse(city, _key(houses[0]))
		_mouse(city, _key(houses[1]))
		_check(events.size() == count + 2 and events[count].site == int(houses[0].site) and events[count + 1].site == int(houses[1].site), "Sharing one house sprite does not merge the identities of repeated buildings")
		var mixed: Dictionary = developed.duplicate(true)
		var first_site: int = int(houses[0].site)
		var second_site: int = int(houses[1].site)
		for building: Dictionary in mixed.buildings:
			if int(building.site) == first_site:
				building.level = 0
				building.queue = {"site": first_site, "id": "house", "level": 1, "start": FIXTURE_TIME_MS, "end": FIXTURE_TIME_MS + 60000.0}
			elif int(building.site) == second_site:
				building.queue = {"site": second_site, "id": "house", "level": int(building.level) + 1, "start": FIXTURE_TIME_MS - 30000.0, "end": FIXTURE_TIME_MS + 30000.0}
		for slot: Dictionary in mixed.buildingSlots:
			if int(slot.site) == first_site:
				slot.level = 0
		mixed.queues.build = mixed.buildings.filter(func(row: Dictionary) -> bool: return row.get("queue") is Dictionary).map(func(row: Dictionary) -> Dictionary: return row.queue)
		city.set_city(mixed, FIXTURE_TIME_MS)
		await _settle()
		_check(not city.sprite_draw_records().has(_key(houses[0])) and int(city._hit_records[_key(houses[0])].level) == 0, "Level-zero construction remains an actual foundation instead of completed art")
		_check(city.sprite_draw_records().has(_key(houses[1])) and city._hit_records[_key(houses[1])].queue != null, "Upgrading houses retain their current sprite, level and queue identity")
		var progress: Dictionary = city._queue_progress(city._hit_records[_key(houses[1])].queue)
		_check(float(progress.progress) >= 0.5 and float(progress.progress) < 0.6 and int(progress.seconds) > 20 and int(progress.seconds) <= 30, "Construction progress follows its explicit server-time anchor rather than the machine's wall clock")
		_check_art(city, mixed)
		await _capture("rts-city-grid-mixed-phone", city)
	var recreated: Control = CityView.new()
	root.add_child(recreated)
	recreated.size = city.size
	recreated.set_city(developed)
	await _settle()
	city.set_city(developed)
	await _settle()
	_check(recreated._hit_boxes == city._hit_boxes and developed == original, "Recreating the scene preserves site positions without mutating its authoritative DTO")
	recreated.queue_free()
	await _check_grid(city, developed, 900.0)
	await _capture("rts-city-grid-developed-desktop", city)
	city.queue_free()
	await process_frame
	print("RTS_CITY_GRID_CHECKS=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
