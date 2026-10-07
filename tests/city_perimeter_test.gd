extends "res://tests/rts_city_grid_test.gd"

func _run() -> void:
	var fixtures: Dictionary = _fixtures()
	var city: Control = CityView.new()
	root.add_child(city)
	var triggered: Array = []
	city.defense_selected.connect(func() -> void: triggered.append(true))
	for width: float in [390.0, 900.0]:
		city.size = Vector2(width, city.recommended_height(width))
		var prior: float = 0.0
		for level: int in range(11):
			var view: Dictionary = fixtures.fresh.duplicate(true)
			if level > 0:
				view.buildings.append({"id":"wall", "site":0, "level":level, "name":"城防", "queue":{"start":FIXTURE_TIME_MS, "end":FIXTURE_TIME_MS + 10000, "level":level+1}})
			city.set_city(view, FIXTURE_TIME_MS)
			await _settle()
			_check(city.perimeter_level() == level, "Only completed wall level affects perimeter")
			_check(city.perimeter_height() > prior, "Every level raises the rampart")
			prior = city.perimeter_height()
			for rect: Rect2 in city.perimeter_hit_regions():
				_check(city._building_at(rect.get_center()) == "perimeter", "All four sides open defenses")
			for lot: Dictionary in city.parcel_draw_records():
				if not bool(lot.reserved):
					_check(city._building_at((lot.rect as Rect2).get_center()) == str(lot.key), "Parcel selection retains priority")
		city._activate_building("perimeter")
		_check(triggered.size() == (1 if width == 390.0 else 2), "Perimeter sends one defense event")
	city.set_city(fixtures.fresh, FIXTURE_TIME_MS)
	_check(city.perimeter_level() == 0, "Switching city does not retain previous walls")
	city.queue_free()
	await _settle()
	print("CITY_PERIMETER checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
