extends SceneTree

## Shipped relief-art contracts and visibility checks. The small DTOs below are
## isolated rendering fixtures; optional captures use the real canonical bridge.
class ArtProbe extends "res://src/world_map.gd":
	var sprite_requests: Array[Dictionary] = []
	var city_ids: Array[String] = []
	var task_ids: Array[String] = []
	var rendered_labels: Array[String] = []
	var active_tile: String = ""
	var draw_count: int = 0

	func _draw() -> void:
		draw_count += 1
		super._draw()

	func _draw_tile_landscape(tile: Dictionary, coordinates: Vector2i) -> void:
		var previous: String = active_tile
		active_tile = str(tile.get("id", ""))
		super._draw_tile_landscape(tile, coordinates)
		active_tile = previous

	func _draw_tile_features(tile: Dictionary, coordinates: Vector2i) -> void:
		var previous: String = active_tile
		active_tile = str(tile.get("id", ""))
		super._draw_tile_features(tile, coordinates)
		active_tile = previous

	func _draw_city(center: Vector2, tile: Dictionary, is_home: bool) -> void:
		city_ids.append(str(tile.get("id", "")))
		super._draw_city(center, tile, is_home)

	func _draw_task(center: Vector2, tile: Dictionary) -> void:
		task_ids.append(str(tile.get("id", "")))
		super._draw_task(center, tile)

	func _draw_map_sprite(id: String, center: Vector2, extent: Vector2) -> bool:
		var rendered: bool = super._draw_map_sprite(id, center, extent)
		sprite_requests.append({"id": id, "tile": active_tile, "center": center, "extent": extent, "rendered": rendered})
		return rendered

	func _draw_centered_text(label: String, position: Vector2, font_size: int, color: Color) -> void:
		rendered_labels.append(label)
		super._draw_centered_text(label, position, font_size, color)

	func clear_observations() -> void:
		sprite_requests.clear()
		city_ids.clear()
		task_ids.clear()
		rendered_labels.clear()


const MapScript: Script = preload("res://src/world_map.gd")
const ThemeScript: Script = preload("res://src/ui_theme.gd")
const UI_FONT: Font = preload("res://assets/fonts/UI.tres")
const METADATA_PATH: String = "res://data/world-map-art-atlas.json"
const ART_IDS: Array[String] = ["mountain_a", "mountain_b", "forest_a", "forest_b", "county", "city"]
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceWorldMapArtTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("shader_cache"))
	create_timer(60).timeout.connect(func() -> void: push_error("World-map art test timed out"); quit(1))
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame: int in range(4):
		await process_frame


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


func _test_shipped_atlas(map: ArtProbe, metadata: Dictionary) -> void:
	var path: String = str(metadata.get("texture", ""))
	var image: Image = Image.new()
	_check(FileAccess.file_exists(path), "The map metadata must identify a shipped source image.")
	if not FileAccess.file_exists(path):
		return
	_check(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK and not image.is_empty(), "The actual shipped PNG must decode independently of the texture importer.")
	if image.is_empty():
		return
	_check(image.detect_alpha() != Image.ALPHA_NONE, "The source relief atlas must contain real transparency.")
	var source_size: Array = metadata.get("size", [])
	_check(source_size.size() == 2 and Vector2i(int(source_size[0]), int(source_size[1])) == image.get_size(), "The metadata dimensions must match the actual generated source pixels.")
	var ids: Array = map.map_art_regions().keys()
	ids.sort()
	var expected: Array = ART_IDS.duplicate()
	expected.sort()
	_check(map.map_art_loaded() and ids == expected and map._map_art_sprites.size() == 6, "The renderer must cache exactly the six verified relief assets.")
	_check(map._map_art_texture != null and map._map_art_texture.get_size() == Vector2(image.get_size()), "The imported cache must use the actual source atlas.")
	var regions: Dictionary = map.map_art_regions()
	for id: String in ART_IDS:
		var sprite: AtlasTexture = map._map_art_sprites.get(id) as AtlasTexture
		var region: Rect2 = regions.get(id, Rect2())
		_check(sprite != null and sprite.atlas == map._map_art_texture and sprite.filter_clip, "Asset %s must share the single atlas and clip adjacent artwork." % id)
		_check(region.has_area() and Rect2(Vector2.ZERO, Vector2(image.get_size())).encloses(region), "Asset %s must have a positive region inside the actual source image." % id)
		if region.has_area() and Rect2(Vector2.ZERO, Vector2(image.get_size())).encloses(region):
			var samples: Vector2i = _region_samples(image, region)
			_check(samples.x > 0 and samples.y > 0, "Asset %s must contain both visible artwork and transparent surroundings." % id)
	for first: int in range(ART_IDS.size()):
		for second: int in range(first + 1, ART_IDS.size()):
			_check(not (regions.get(ART_IDS[first], Rect2()) as Rect2).intersects(regions.get(ART_IDS[second], Rect2())), "The padded regions for %s and %s must not intersect." % [ART_IDS[first], ART_IDS[second]])
	if regions.has("city"):
		var cached: Rect2 = regions["city"]
		regions["city"] = Rect2()
		_check(map.map_art_regions().get("city", Rect2()) == cached, "External region diagnostics must not corrupt the live atlas cache.")


func _test_city_semantics() -> void:
	var tiers: Array = [
		{"tier": "ordinary", "label": "城", "art": "county"},
		{"tier": "county", "label": "县", "art": "county"},
		{"tier": "prefecture", "label": "郡", "art": "city"},
		{"tier": "province", "label": "州", "art": "city"},
		{"tier": "capital", "label": "都", "art": "city"}
	]
	var previous_scale: float = 0.0
	for row: Dictionary in tiers:
		var baseline: Dictionary = {"kind": "city", "tier": row["tier"], "level": 1}
		_check(MapScript.city_tier_label(baseline) == row["label"] and MapScript.city_art_id(baseline) == row["art"], "The explicit canonical %s tier must choose its administrative label and silhouette." % row["tier"])
		_check(MapScript.city_art_scale(baseline) > previous_scale, "Higher explicit administrative tiers must remain visually distinguishable.")
		previous_scale = MapScript.city_art_scale(baseline)
		for level: int in [0, 10, 999]:
			var different_level: Dictionary = baseline.duplicate(true)
			different_level["level"] = level
			_check(MapScript.city_tier_label(different_level) == row["label"] and MapScript.city_art_id(different_level) == row["art"] and is_equal_approx(MapScript.city_art_scale(different_level), MapScript.city_art_scale(baseline)), "Building level %d must not promote or demote the explicit %s city tier." % [level, row["tier"]])
	for tile: Dictionary in [{"kind": "capital", "level": 999}, {"kind": "city", "namedCity": true, "level": 10}, {"tier": "unknown", "level": 100}]:
		_check(MapScript.city_tier_label(tile) == "城" and MapScript.city_art_id(tile) == "county", "Absent or unknown administrative tiers must not invent a province or capital.")
	_check(MapScript.city_tier_label({"tier": "county"}, true) == "主城" and MapScript.city_art_id({"tier": "county"}, true) == "city", "The actual home remains a home marker regardless of its administrative field.")
	_check(MapScript.city_flag_color({"faction": "yellow_turban"}, false).is_equal_approx(Color("d3b447")), "A canonical yellow_turban faction must use the established Yellow Turban flag.")
	_check(MapScript.city_flag_color({"kind": "yellow_city"}, false).is_equal_approx(Color("d3b447")), "The existing Yellow Turban city-kind compatibility must remain supported.")
	_check(MapScript.city_flag_color({"faction": "yellow_turban", "relation": "enemy", "owned": true}, false).is_equal_approx(Color("e2c181")), "Authoritative ownership must take priority over faction and stale hostile relation.")
	_check(MapScript.city_flag_color({"faction": "yellow_turban", "relation": "enemy"}, true).is_equal_approx(Color("e2c181")), "Home ownership must take priority over a hostile faction.")
	for relation: String in ["ally", "allied", "friendly"]:
		_check(MapScript.city_flag_color({"faction": "yellow_turban", "relation": relation}, false).is_equal_approx(Color("75afba")), "An explicit %s relationship must take priority over a Yellow Turban faction." % relation)
	for relation: String in ["enemy", "hostile"]:
		_check(MapScript.city_flag_color({"faction": "yellow_turban", "relation": relation}, false).is_equal_approx(Color("c9715e")), "An explicit %s relationship must take priority over a Yellow Turban faction." % relation)
	_check(MapScript.city_flag_color({"faction": "unknown"}, false) == MapScript.city_flag_color({}, false), "Unknown factions must not fabricate alliance or hostility.")
	_check(MapScript.city_flag_glyph({"faction": "yellow_turban"}) == "黄" and MapScript.city_flag_glyph({"faction": "local_warlord"}) == "军", "Canonical faction keys must use readable Chinese flag glyphs.")
	_check(MapScript.city_flag_glyph({"owned": true, "relation": "enemy", "faction": "yellow_turban"}) == "我" and MapScript.city_flag_glyph({"relation": "allied", "faction": "yellow_turban"}) == "盟", "Flag glyphs must preserve the same authoritative relationship priorities as color.")
	_check(MapScript.city_flag_glyph({"faction": "unrecognized_key"}).is_empty() and MapScript.city_flag_glyph({"faction": "蜀汉"}) == "蜀", "Unknown ASCII keys must not produce misleading initials, while supplied Chinese faction names remain readable.")


func _test_server_clock(map: ArtProbe) -> void:
	# Deliberately far from the development machine's date. Never change the OS
	# clock; only the supplied server timestamp may govern this map's trip.
	var server_time: float = 1000000.0
	var trip: Dictionary = {"id": "server-trip", "from": {"x": 10, "y": 10}, "to": {"x": 30, "y": 10}, "start": server_time - 10000.0, "arrive": server_time + 10000.0, "status": "march"}
	var dto: Dictionary = {"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [], "marches": [trip], "serverTime": server_time}
	map.set_process(false)
	map.set_world(dto)
	var first: float = map._map_now_ms()
	_check(first >= server_time and first < server_time + 250.0, "A supplied server timestamp must anchor map time regardless of the machine's calendar date.")
	_check(absf(first - Time.get_unix_time_from_system() * 1000.0) > 60000.0 and map._pending_arrival_marches.size() == 1, "A distant client calendar must not prematurely finish a valid server-clock journey.")
	_check(absf(MapScript.march_fraction(trip, first) - 0.5) < 0.02 and absf(MapScript.march_world_position(trip, first).x - 20.5) < 0.4, "The known halfway server trip must stay near its actual tile-center midpoint.")
	var tick_before: int = Time.get_ticks_usec()
	await create_timer(0.03).timeout
	var second: float = map._map_now_ms()
	var elapsed: float = float(Time.get_ticks_usec() - tick_before) / 1000.0
	_check(second > first and absf((second - first) - elapsed) < 20.0, "Map time must advance with elapsed monotonic time after the server snapshot.")
	var resynchronized: Dictionary = dto.duplicate(true)
	resynchronized["serverTime"] = server_time + 2000.0
	map.set_world(resynchronized)
	_check(map._map_now_ms() >= server_time + 2000.0 and map._map_now_ms() < server_time + 2250.0, "A replacement server snapshot must resynchronize the clock to its new authoritative timestamp.")
	for invalid: Variant in [null, "1000000", true, -100.0, 0, NAN, INF]:
		var fallback: Dictionary = dto.duplicate(true)
		fallback["serverTime"] = invalid
		map.set_world(fallback)
		var before: float = Time.get_unix_time_from_system() * 1000.0
		var actual: float = map._map_now_ms()
		var after: float = Time.get_unix_time_from_system() * 1000.0
		_check(is_finite(actual) and actual >= before - 1.0 and actual <= after + 1.0, "A null, malformed, nonpositive or nonfinite server clock must safely use the actual system clock.")
	var absent: Dictionary = dto.duplicate(true)
	absent.erase("serverTime")
	map.set_world(absent)
	_check(absf(map._map_now_ms() - Time.get_unix_time_from_system() * 1000.0) < 100.0, "A DTO with no serverTime must preserve the existing local preview clock fallback.")


func _visibility_fixture() -> Dictionary:
	return {"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [
		{"id": "home", "x": 32, "y": 32, "name": "青溪城", "kind": "city", "owned": true, "tier": "ordinary"},
		{"id": "visible-county", "x": 31, "y": 32, "name": "可见县城", "kind": "city", "tier": "county", "level": 1},
		{"id": "visible-forest", "x": 30, "y": 32, "kind": "wild", "terrain": "forest"},
		{"id": "visible-mountain", "x": 30, "y": 33, "kind": "wild", "terrain": "mountain"},
		{"id": "visible-task", "x": 33, "y": 31, "name": "当前据点", "kind": "landmark", "terrain": "plain"},
		{"id": "hidden-capital", "x": 34, "y": 32, "name": "SECRET_CAPITAL", "kind": "city", "tier": "capital", "faction": "祕", "hidden": true, "selectable": false},
		{"id": "hidden-task", "x": 34, "y": 33, "name": "SECRET_TASK", "kind": "landmark", "terrain": "mountain", "hidden": true, "selectable": false},
		{"id": "hidden-forest-task", "x": 35, "y": 33, "name": "SECRET_FOREST", "kind": "landmark", "terrain": "forest", "hidden": true, "selectable": false}
	], "marches": []}


func _test_visibility_and_reuse(map: ArtProbe) -> void:
	var dto: Dictionary = _visibility_fixture()
	var original: Dictionary = dto.duplicate(true)
	map.size = Vector2(1000, 600)
	map.set_process(false)
	map.set_world(dto)
	map.focus_home()
	var cached_texture: Texture2D = map._map_art_texture
	var cached_sprites: Dictionary = map._map_art_sprites.duplicate()
	var selections: Array = []
	map.tile_selected.connect(func(tile: Dictionary) -> void: selections.append(tile))
	for scale: float in [0.25, 0.80, 1.20]:
		for filter_name: String in ["all", "cities", "tasks", "resources", "marches"]:
			map.clear_observations()
			map.set_filter(filter_name)
			map._zoom_at(map.size * 0.5, scale)
			await _settle()
			_check(not map.city_ids.has("hidden-capital") and not map.task_ids.has("hidden-task") and not map.task_ids.has("hidden-forest-task"), "Hidden targets must not dispatch settlement/task renderers at %.0f%% with %s filter." % [scale * 100.0, filter_name])
			var secret_sprites: Array = map.sprite_requests.filter(func(row: Dictionary) -> bool: return str(row["tile"]).begins_with("hidden-"))
			_check(secret_sprites.is_empty(), "Hidden targets must not request atlas art in either landscape or feature pass at %.0f%% with %s filter." % [scale * 100.0, filter_name])
			_check(not map.rendered_labels.has("SECRET_CAPITAL") and not map.rendered_labels.has("SECRET_TASK") and not map.rendered_labels.has("SECRET_FOREST") and not map.rendered_labels.has("祕"), "New map labels and faction glyphs must not reveal hidden targets.")
			_check(map.city_ids.has("home"), "The true home must remain visible in every filter and scale.")
			if scale >= 0.46 and filter_name == "all":
				for id: String in ["home", "visible-county", "visible-forest", "visible-mountain"]:
					_check(map.sprite_requests.any(func(row: Dictionary) -> bool: return str(row["tile"]) == id and bool(row["rendered"])), "Visible %s must use its real imported relief sprite." % id)
			_check(map._map_art_texture == cached_texture and map._map_art_sprites.size() == cached_sprites.size(), "Changing scale and filter must reuse the single source texture and fixed sprite cache.")
			for id: String in ART_IDS:
				_check(map._map_art_sprites.get(id) == cached_sprites.get(id), "Changing scale and filter must reuse AtlasTexture %s by identity." % id)
	map._select_at(map.world_to_screen(Vector2(34.5, 32.5)))
	map._select_at(map.world_to_screen(Vector2(34.5, 33.5)))
	_check(selections.is_empty(), "Selecting a hidden capital or task must emit no actionable target.")
	map._select_at(map.world_to_screen(Vector2(31.5, 32.5)))
	_check(selections.size() == 1 and str(selections[0].get("id", "")) == "visible-county", "Relief artwork must retain the real tile-coordinate selection identity.")
	_check(dto == original and map.world == original, "Rendering and selecting relief art must not rewrite input or copied world DTOs.")
	var replacement: Dictionary = dto.duplicate(true)
	replacement["tiles"][1]["owned"] = true
	replacement["tiles"][2]["terrain"] = "mountain"
	map.set_filter("all")
	map.set_world(replacement)
	map.clear_observations()
	map.queue_redraw()
	await _settle()
	_check(map._map_art_texture == cached_texture, "Replacing world ownership and terrain must reuse the source texture.")
	for id: String in ART_IDS:
		_check(map._map_art_sprites.get(id) == cached_sprites.get(id), "Replacing the world DTO must reuse AtlasTexture %s by identity." % id)
	_check(map.sprite_requests.any(func(row: Dictionary) -> bool: return str(row["tile"]) == "visible-forest" and str(row["id"]).begins_with("mountain") and bool(row["rendered"])), "A changed terrain at a cached coordinate must immediately use the new mountain artwork.")
	_check(not map.sprite_requests.any(func(row: Dictionary) -> bool: return str(row["tile"]) == "visible-forest" and str(row["id"]).begins_with("forest")), "Replacing a forest tile must not retain a stale forest sprite request.")
	_check(bool(map._tile_at(Vector2i(31, 32)).get("owned", false)) and map.world == replacement and dto == original, "Texture reuse must preserve current authoritative ownership without changing the old input DTO.")


func _test_missing_metadata(map: ArtProbe) -> void:
	var missing_path: String = "res://data/world-map-art-missing-test.json"
	_check(not FileAccess.file_exists(missing_path), "The fallback fixture must actually exercise missing metadata.")
	var before: Dictionary = map.world.duplicate(true)
	map._load_map_art(missing_path)
	_check(not map.map_art_loaded() and map._map_art_sprites.is_empty() and map._map_art_texture == null, "A missing metadata file must leave no fabricated atlas resources.")
	map.clear_observations()
	var draws_before: int = map.draw_count
	map.queue_redraw()
	await _settle()
	_check(map.draw_count > draws_before and map.city_ids.has("home") and map.city_ids.has("visible-county"), "Missing art metadata must still execute the actual procedural city renderer.")
	_check(not map.sprite_requests.is_empty() and map.sprite_requests.all(func(row: Dictionary) -> bool: return not bool(row["rendered"])), "Missing atlas artwork must consistently return false to the procedural fallback.")
	_check(map.world == before and str(map.selected_tile.get("id", "")) == "visible-county", "Art fallback must preserve real world data and selection.")
	map._load_map_art()
	map.queue_redraw()
	await _settle()
	_check(map.map_art_loaded() and map._map_art_sprites.size() == 6 and map.world == before, "Restoring real metadata must recover the six cached sprites without changing rules.")


func _hit_fixture() -> Dictionary:
	var tiles: Array = []
	for y: int in range(29, 36):
		for x: int in range(29, 36):
			tiles.append({"id": "ground-%d-%d" % [x, y], "x": x, "y": y, "kind": "wild", "terrain": "plain", "selectable": true})
	tiles.append({"id": "roof-city", "x": 32, "y": 32, "kind": "city", "tier": "capital", "name": "测试都城", "level": 1, "selectable": true})
	return {"width": 64, "height": 64, "home": {"x": 16, "y": 16}, "tiles": tiles, "marches": []}


func _source_hit_sample(map: ArtProbe, image: Image, hit: Dictionary, opaque: bool) -> Dictionary:
	var rect: Rect2 = hit["rect"]
	var region: Rect2 = hit["region"]
	var coordinates: Vector2i = hit["coordinates"]
	# Search actual source alpha independently of the runtime hit test. Require
	# the candidate to project into a neighbouring tile, where the raised roof
	# and transparent corner have different selection semantics.
	for y: int in range(80):
		for x: int in range(80):
			var fraction: Vector2 = Vector2((float(x) + 0.5) / 80.0, (float(y) + 0.5) / 80.0)
			var pixel: Vector2i = Vector2i(region.position + fraction * region.size)
			var alpha: float = image.get_pixel(pixel.x, pixel.y).a
			if (opaque and alpha <= 0.7) or (not opaque and alpha >= 0.01):
				continue
			var point: Vector2 = rect.position + fraction * rect.size
			var world_point: Vector2 = map.screen_to_world(point)
			var underlying: Vector2i = Vector2i(floori(world_point.x), floori(world_point.y))
			if underlying != coordinates and Rect2(Vector2.ZERO, map.size).has_point(point):
				return {"point": point, "coordinates": underlying, "id": str(map._tile_at(underlying).get("id", ""))}
	return {}


func _test_raised_roof_selection(map: ArtProbe, metadata: Dictionary) -> void:
	var dto: Dictionary = _hit_fixture()
	var original: Dictionary = dto.duplicate(true)
	map.size = Vector2(1000, 600)
	map.set_filter("all")
	map.set_world(dto)
	map._zoom_at(map.size * 0.5, 1.20)
	map.focus_tile(32, 32)
	await _settle()
	var hits: Array = map._city_hit_regions.filter(func(hit: Dictionary) -> bool: return str(hit["id"]) == "roof-city")
	_check(hits.size() == 1 and map._map_art_image != null, "The actual visible raised city must register one alpha-backed hit region.")
	if hits.size() != 1 or map._map_art_image == null:
		return
	var source: Image = Image.new()
	_check(source.load_png_from_buffer(FileAccess.get_file_as_bytes(str(metadata["texture"]))) == OK, "Roof-hit validation must read the original shipped alpha pixels.")
	if source.is_empty():
		return
	var roof: Dictionary = _source_hit_sample(map, source, hits[0], true)
	var corner: Dictionary = _source_hit_sample(map, source, hits[0], false)
	_check(not roof.is_empty(), "The source city must expose an actual opaque roof beyond its own coordinate tile.")
	_check(not corner.is_empty(), "The source city must expose a transparent atlas corner above a neighbouring coordinate tile.")
	if roof.is_empty() or corner.is_empty():
		return
	var selections: Array = []
	map.tile_selected.connect(func(tile: Dictionary) -> void: selections.append(tile))
	map._select_at(roof["point"])
	_check(selections.size() == 1 and str(selections[0].get("id", "")) == "roof-city" and Vector2i(int(selections[0]["x"]), int(selections[0]["y"])) == Vector2i(32, 32), "Clicking the opaque roof beyond the tile edge must select the true city rather than neighbouring ground.")
	selections.clear()
	map._select_at(corner["point"])
	_check(selections.size() == 1 and str(selections[0].get("id", "")) == str(corner["id"]), "Transparent atlas corners must pass through to the actual underlying ground tile.")
	for filter_name: String in ["resources", "tasks"]:
		map.set_filter(filter_name)
		await _settle()
		selections.clear()
		map._select_at(roof["point"])
		_check(not map._city_hit_regions.any(func(hit: Dictionary) -> bool: return str(hit["id"]) == "roof-city") and selections.size() == 1 and str(selections[0].get("id", "")) == str(roof["id"]), "A %s filter hiding this city must remove its extended roof hit area." % filter_name)
	map.set_filter("all")
	for replacement_kind: String in ["hidden", "unselectable", "different-id"]:
		map.set_world(dto)
		await _settle()
		_check(map._city_hit_regions.any(func(hit: Dictionary) -> bool: return str(hit["id"]) == "roof-city"), "The pre-replacement fixture must contain the original city roof hit area.")
		var next: Dictionary = dto.duplicate(true)
		var city: Dictionary = next["tiles"][-1]
		if replacement_kind == "hidden":
			city["hidden"] = true
		elif replacement_kind == "unselectable":
			city["selectable"] = false
		else:
			city["id"] = "replacement-city"
		map.set_world(next)
		# Intentionally click before the scheduled redraw clears the old hit list.
		selections.clear()
		map._select_at(roof["point"])
		_check(selections.size() == 1 and str(selections[0].get("id", "")) == str(roof["id"]), "A %s DTO replacement must not reuse the stale roof hit to leak the previous city." % replacement_kind)
		await _settle()
	_check(dto == original, "Alpha hit testing and DTO replacements must never rewrite the original world fixture.")


func _canonical_world() -> Dictionary:
	var node: String = OS.get_environment("TK_NODE")
	_check(not node.is_empty(), "TK_NODE is required to read the real canonical map DTO without player saves.")
	if node.is_empty():
		return {}
	var output: Array = []
	var result: int = OS.execute(node, [ProjectSettings.globalize_path("res://tests/helpers/playable-view.mjs")], output)
	_check(result == 0 and not output.is_empty(), "The canonical bridge helper must produce a fresh isolated world.")
	if result != 0 or output.is_empty():
		return {}
	var fixture: Variant = JSON.parse_string(str(output[0]))
	_check(fixture is Dictionary and fixture.get("worldSample", {}) is Dictionary, "The canonical world helper must return a valid map DTO.")
	return fixture.get("worldSample", {}).duplicate(true) if fixture is Dictionary else {}


func _capture_folder() -> String:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(arguments.size()):
		if arguments[index].begins_with("--capture-folder="):
			return arguments[index].trim_prefix("--capture-folder=").trim_suffix("/") + "/"
		if arguments[index] == "--capture-folder" and index + 1 < arguments.size():
			return arguments[index + 1].trim_suffix("/") + "/"
	return "res://production/qa/evidence/story-015/"


func _capture_canonical() -> void:
	var dto: Dictionary = _canonical_world()
	if dto.is_empty():
		return
	var original: Dictionary = dto.duplicate(true)
	# JSON numbers arrive as floats; set_world has always normalised the two
	# dimension fields to positive ints while preserving the input dictionary.
	var rendered_world: Dictionary = dto.duplicate(true)
	rendered_world["width"] = int(dto["width"])
	rendered_world["height"] = int(dto["height"])
	_check(int(dto.get("width", 0)) == 64 and int(dto.get("height", 0)) == 64 and dto.get("tiles", []).size() == 4096, "The actual canonical DTO must remain the unchanged 64×64 world, including masked targets.")
	var cities: Array = dto.get("tiles", []).filter(func(tile: Dictionary) -> bool: return not bool(tile.get("hidden", false)) and str(tile.get("kind", "")) == "city")
	_check(not cities.is_empty() and cities.all(func(tile: Dictionary) -> bool: return tile.has("tier") and tile.has("tierName")), "Visible actual cities must carry explicit administrative presentation fields from the canonical bridge.")
	var shell: PanelContainer = PanelContainer.new()
	shell.theme = ThemeScript.create(UI_FONT)
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shell)
	var column: VBoxContainer = VBoxContainer.new()
	shell.add_child(column)
	var title: Label = Label.new()
	title.text = "天下舆图 · 当前可见据点"
	title.theme_type_variation = "TitleLabel"
	column.add_child(title)
	var map: ArtProbe = ArtProbe.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(map)
	map.set_world(dto)
	var hint: Label = Label.new()
	hint.text = "拖动浏览 · 缩放查看 · 点击真实目标"
	hint.theme_type_variation = "MutedLabel"
	column.add_child(hint)
	var capture: bool = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	var folder: String = _capture_folder()
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(390, 844)]:
		root.size = dimensions
		await _settle()
		map.focus_home()
		map._zoom_at(map.size * 0.5, 0.80)
		map.clear_observations()
		map.queue_redraw()
		await _settle()
		_check(map.map_art_loaded() and not map.sprite_requests.is_empty(), "The actual canonical %dpx map must render through the shipped atlas." % dimensions.x)
		_check(map.world == rendered_world and dto == original, "Rendering the actual %dpx map must preserve canonical data with existing integer dimensions." % dimensions.x)
		if capture:
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(folder + "world-map-relief-%d.png" % dimensions.x) == OK, "Native canonical %dpx map evidence must save to this story folder." % dimensions.x)
	root.size = Vector2i(1280, 800)
	await _settle()
	map.focus_home()
	map._zoom_at(map.size * 0.5, 0.25)
	await _settle()
	_check(map.map_art_loaded() and map.world == rendered_world and dto == original, "Sparse overview must retain the same cached atlas and canonical world.")
	if capture:
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(folder + "world-map-relief-overview.png") == OK, "Native canonical overview evidence must save without overwriting earlier stories.")
	shell.queue_free()
	await _settle()


func _run() -> void:
	_check(FileAccess.file_exists(METADATA_PATH), "The shipped world-map art metadata must exist.")
	if not FileAccess.file_exists(METADATA_PATH):
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(METADATA_PATH))
	_check(parsed is Dictionary, "The shipped world-map art metadata must parse.")
	if not parsed is Dictionary:
		quit(1)
		return
	var map: ArtProbe = ArtProbe.new()
	root.add_child(map)
	map.size = Vector2(1000, 600)
	await _settle()
	_test_shipped_atlas(map, parsed)
	_test_city_semantics()
	await _test_server_clock(map)
	await _test_visibility_and_reuse(map)
	await _test_missing_metadata(map)
	await _test_raised_roof_selection(map, parsed)
	map.queue_free()
	await _settle()
	await _capture_canonical()
	print("WORLD_MAP_ART_CHECKS=%d failures=%d native=%s" % [_checks, _failures, str(DisplayServer.get_name() != "headless")])
	quit(1 if _failures else 0)
