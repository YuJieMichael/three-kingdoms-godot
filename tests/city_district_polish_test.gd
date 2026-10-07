extends "res://tests/rts_city_grid_test.gd"

## Uses the established canonical fixtures; checks actual imported skins and scene geometry.
func _asset(path: String, expected: Dictionary) -> Image:
	var result: Image = Image.new()
	_check(result.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK, "New city art decodes: " + path)
	_check(result.get_size() == Vector2i(int(expected.size[0]), int(expected.size[1])) and FileAccess.get_sha256(path) == str(expected.sha256), "Original source pixels and declared dimensions agree: " + path)
	return result

func _check_new_art(city: Control, metadata: Dictionary) -> void:
	var source: Dictionary = metadata.tierSources[0]
	var image: Image = _asset(str(source.texture), source)
	var all_regions: Array[Rect2] = []
	for id: String in ["hall", "barracks"]:
		var skins: Array = metadata.tiers[id]
		_check(skins.size() == 3, "Three complete architecture variants exist for " + id)
		for index: int in range(3):
			var definition: Dictionary = skins[index]
			var bounds: Array = definition.region
			var region: Rect2 = Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3]))
			_check(Rect2(Vector2.ZERO, Vector2(image.get_size())).encloses(region), "Tier region is wholly inside the saved source")
			_check(not all_regions.any(func(other: Rect2) -> bool: return region.intersects(other)), "Tier source rectangles never include another building")
			all_regions.append(region)
			var texture: AtlasTexture = city.art_sprite_texture(id, int(definition.minLevel)) as AtlasTexture
			_check(texture != null and texture.region == region and texture.atlas.resource_path == str(source.texture) and texture.filter_clip, "Production imports this tier from its declared source, with clipping")
		for row: Array in [[1,"low"],[3,"low"],[4,"mid"],[7,"mid"],[8,"high"],[10,"high"]]:
			_check(city.art_sprite_key(id, int(row[0])) == id + "_" + str(row[1]), "Skin boundary uses completed level %d for %s" % [int(row[0]), id])
		_check(city.art_sprite_texture(id, 0) == null and city.art_sprite_key(id, 0).is_empty(), "Level-zero construction has no complete architecture sprite")
	var environment: Dictionary = metadata.environment
	var env_image: Image = _asset(str(environment.texture), environment)
	var env_regions: Dictionary = city.environment_art_regions()
	_check(env_regions.size() == 4, "The production scene imports wall, courtyard, tree and gate")
	all_regions.clear()
	for id: String in ["wall_segment", "courtyard", "tree", "gate"]:
		var region: Rect2 = env_regions[id]
		_check(Rect2(Vector2.ZERO, Vector2(env_image.get_size())).encloses(region) and not all_regions.any(func(other: Rect2) -> bool: return region.intersects(other)), "Each environment region is isolated inside the source")
		all_regions.append(region)
	_check(city.art_sprite_key("gateway") == "environment_gate", "The decorative gate uses matching wall material")
	_asset(str(metadata.ground.texture), metadata.ground)
	_check(city._ground_texture.resource_path == str(metadata.ground.texture), "The actual scene uses the calmer new soil texture")

func _check_plan(city: Control, view: Dictionary, width: float) -> void:
	city.custom_minimum_size.y = city.recommended_height(width)
	city.size = Vector2(width, city.recommended_height(width))
	city.set_city(view, FIXTURE_TIME_MS)
	await _settle()
	var plan: Dictionary = city.plan_geometry()
	var lots: Array[Dictionary] = city.parcel_draw_records()
	_check(lots.size() == 36 and int(plan.columns) == (3 if width < 600 else 6), "Street hierarchy keeps all36 canonical plots at the appropriate column count")
	_check(float(plan.main_gap) > float(plan.gap) * 3.0 and is_equal_approx((plan.main_street as Rect2).get_center().x, float(plan.gate_axis)), "One wide main street aligns exactly with the gate axis")
	for lot: Dictionary in lots:
		var rect: Rect2 = lot.rect
		_check(rect.size.x >= 44 and rect.size.y >= 44 and Rect2(Vector2.ZERO, city.size).encloses(rect), "Plots stay within scrollable city and retain44px touch targets")
		_check(not rect.intersects(plan.main_street), "No site overlaps the main street or changes selection identity")
		if bool(lot.reserved):
			_check(city._building_at(rect.get_center()).is_empty(), "Official court is never a new selectable building")
	var decorative: Dictionary = city.environment_draw_records()
	for site: int in [15,20,21]:
		_check(decorative.has("courtyard#%d" % site) and decorative.has("tree#%d" % site), "Official reserved lot renders its actual courtyard and tree art")
	if city.perimeter_level() > 1:
		_check(decorative.keys().any(func(key: Variant) -> bool: return str(key).begins_with("wall_north")) and decorative.keys().any(func(key: Variant) -> bool: return str(key).begins_with("wall_south")), "Both north and south wall spans use the matching masonry sprite")
	for row: Dictionary in decorative.values():
		var rect: Rect2 = row.rect
		var region: Rect2 = row.region
		_check(rect.has_area() and is_equal_approx(rect.size.x / rect.size.y, region.size.x / region.size.y), "Environment is scaled or clipped without warping source aspect")
	if city.perimeter_level() > 1:
		var gate: Dictionary = city.sprite_draw_records().gateway
		_check(is_equal_approx((gate.rect as Rect2).get_center().x, float(plan.gate_axis)) and city._building_at((gate.rect as Rect2).get_center()) == "perimeter", "Matching gate is aligned but not buildable")

func _run() -> void:
	var fixtures: Dictionary = _fixtures()
	if fixtures.is_empty():
		quit(1)
		return
	var view: Dictionary = fixtures.prepared
	var city: Control = CityView.new()
	root.add_child(city)
	await _settle()
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CityView.CITY_ART_METADATA))
	_check_new_art(city, metadata)
	for width: float in [1280.0,390.0]:
		await _check_plan(city, view, width)
	# A pending upgrade must not adopt the queued future architecture early.
	var queued: Dictionary = view.duplicate(true)
	for row: Dictionary in queued.buildings:
		if str(row.id) == "hall":
			row.level = 7
			row.queue = {"start":FIXTURE_TIME_MS-1000,"end":FIXTURE_TIME_MS+30000,"level":8}
	for slot: Dictionary in queued.buildingSlots:
		if int(slot.site) == 14:
			slot.level = 7
	city.set_city(queued,FIXTURE_TIME_MS)
	await _settle()
	_check(city.sprite_draw_records()["hall#14"].tierKey == "hall_mid", "An unfinished level8 hall keeps its completed mid-tier appearance")
	var before: Dictionary = city.sprite_draw_records()
	before["hall#14"].tierKey = "tampered"
	_check(city.sprite_draw_records()["hall#14"].tierKey == "hall_mid", "Read-only diagnostics cannot mutate live visual state")
	# Missing new assets preserve old sprites and canonical clickability.
	city._tier_sprites.erase("hall_mid")
	city._tier_sprites.erase("hall_low")
	city.set_city(queued,FIXTURE_TIME_MS)
	await _settle()
	_check(city.sprite_draw_records()["hall#14"].tierKey == "hall" and city._building_at((city._hit_boxes["hall#14"] as Rect2).get_center()) == "hall#14", "Missing tier art falls back to the base hall while keeping the true site action")
	city.queue_free()
	await _settle()
	print("CITY_DISTRICT_POLISH_CHECKS=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
