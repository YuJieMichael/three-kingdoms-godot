class_name KingdomCityView
extends Control

## Native city presentation. All levels and availability come from the bridge.
signal building_selected(id: String)

const GOLD: Color = Color("c0a168")
const INK: Color = Color("182322")
const LABEL: Color = Color("ede2c9")
const CHINESE_FONT: Font = preload("res://assets/fonts/UI.tres")

var _view: Dictionary = {}
var _hit_boxes: Dictionary = {}
var _hit_records: Dictionary = {}
var _hover: String = ""
var _selected: String = ""
var _time: float = 0.0
var _smoke_frame: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(420.0, 470.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "点击建筑查看等级、建设条件与升级费用"
	set_process(true)

func set_city(view: Dictionary) -> void:
	_view = view.duplicate(true)
	queue_redraw()

func select_building(id: String, site: int = -1) -> void:
	_selected = "%s#%d" % [id, site]
	queue_redraw()

func selected_site() -> int:
	var row: Dictionary = _hit_records.get(_selected, {})
	return int(row.get("site", -1))

func _activate_building(key: String) -> void:
	_selected = key
	var row: Dictionary = _hit_records.get(key, {})
	building_selected.emit(str(row.get("id", "")))
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_smoke_frame += delta
	if _smoke_frame >= 0.08:
		_smoke_frame = 0.0
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var next: String = _building_at((event as InputEventMouseMotion).position)
		if next != _hover:
			_hover = next
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not next.is_empty() else Control.CURSOR_ARROW
			queue_redraw()
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			var id: String = _building_at(click.position)
			if not id.is_empty():
				_activate_building(id)
				accept_event()
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			var id: String = _building_at(touch.position)
			if not id.is_empty():
				_activate_building(id)
				accept_event()

func _building_at(point: Vector2) -> String:
	for key: Variant in _hit_boxes.keys():
		var rect: Rect2 = _hit_boxes[key]
		if rect.has_point(point):
			return str(key)
	return ""

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 10.0 or h < 10.0:
		return
	_hit_boxes.clear()
	_hit_records.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color("243332"))
	# Distant mountain silhouettes and a dawn glow behind the city.
	draw_circle(Vector2(w * 0.77, h * 0.14), 64.0, Color(0.70, 0.57, 0.36, 0.09))
	for layer: int in range(3):
		var ridge: PackedVector2Array = PackedVector2Array([Vector2(0.0, h * 0.28)])
		for i: int in range(17):
			var x: float = float(i) * w / 16.0
			var y: float = h * (0.13 + float(layer) * 0.045) + sin(float(i) * 1.3 + float(layer)) * h * 0.055
			ridge.append(Vector2(x, y))
		ridge.append(Vector2(w, h * 0.38))
		ridge.append(Vector2(0.0, h * 0.38))
		draw_colored_polygon(ridge, Color(0.13 + float(layer) * 0.015, 0.20 + float(layer) * 0.01, 0.20, 1.0))
	var city_ground: PackedVector2Array = PackedVector2Array([
		Vector2(w * 0.10, h * 0.23), Vector2(w * 0.86, h * 0.23),
		Vector2(w * 0.96, h * 0.85), Vector2(w * 0.04, h * 0.85)])
	draw_colored_polygon(city_ground, Color("3b4035"))
	# Stone roads converge at the gate and administrative court.
	var road: PackedVector2Array = PackedVector2Array([
		Vector2(w * 0.47, h * 0.28), Vector2(w * 0.54, h * 0.28),
		Vector2(w * 0.58, h * 0.92), Vector2(w * 0.44, h * 0.92)])
	draw_colored_polygon(road, Color("676350"))
	draw_line(Vector2(w * 0.10, h * 0.54), Vector2(w * 0.92, h * 0.54), Color("65614e"), 18.0)
	for i: int in range(10):
		var y: float = h * (0.34 + float(i) * 0.05)
		draw_line(Vector2(w * 0.46, y), Vector2(w * 0.56, y), Color(0.20, 0.22, 0.19, 0.23), 1.0)
	_draw_walls(w, h)
	var rows: Array = (_view.get("buildings", []) as Array).duplicate(true)
	var existing_ids: Array[String] = []
	for value: Variant in rows:
		if value is Dictionary:
			existing_ids.append(str((value as Dictionary).get("id", "")))
	for value: Variant in _view.get("buildOptions", []):
		if value is Dictionary:
			var option: Dictionary = value
			if not existing_ids.has(str(option.get("id", ""))):
				var planned: Dictionary = option.duplicate(true)
				planned["level"] = 0
				planned["site"] = -1
				rows.append(planned)
	var arrangement: Dictionary = {
		"hall": Vector2(0.50, 0.33), "barracks": Vector2(0.73, 0.48),
		"house": Vector2(0.27, 0.45), "drill": Vector2(0.74, 0.67),
		"warehouse": Vector2(0.26, 0.67), "academy": Vector2(0.30, 0.29),
		"inn": Vector2(0.19, 0.57), "market": Vector2(0.39, 0.76),
		"tavern": Vector2(0.62, 0.75), "embassy": Vector2(0.74, 0.30),
		"workshop": Vector2(0.87, 0.57), "stable": Vector2(0.59, 0.57),
		"beacon": Vector2(0.13, 0.34), "wall": Vector2(0.80, 0.84),
		"smith": Vector2(0.37, 0.58), "recruit": Vector2(0.60, 0.45),
		"post": Vector2(0.13, 0.69)}
	var fallback_index: int = 0
	var placed_ids: Dictionary = {}
	for value: Variant in rows:
		if not value is Dictionary:
			continue
		var data: Dictionary = value
		var id: String = str(data.get("id", ""))
		if id.is_empty():
			continue
		var anchor: Vector2 = arrangement.get(id, Vector2(0.17 + float(fallback_index % 5) * 0.15, 0.90))
		if not arrangement.has(id):
			fallback_index += 1
		var repeated: int = int(placed_ids.get(id, 0))
		placed_ids[id] = repeated + 1
		if repeated > 0:
			anchor = Vector2(0.17 + float((repeated - 1) % 5) * 0.15, 0.92 - float((repeated - 1) / 5) * 0.04)
		var base: Vector2 = Vector2(anchor.x * w, anchor.y * h)
		var width: float = clampf(w * (0.15 if id == "hall" else 0.105), 42.0, 118.0)
		var height: float = clampf(h * (0.09 if id == "hall" else 0.065), 28.0, 56.0)
		_draw_building(id, str(data.get("name", id)), int(data.get("level", 0)), base, width, height, int(data.get("site", -1)))
	_draw_gate(Vector2(w * 0.51, h * 0.855), w * 0.11, h * 0.075)
	var meta: Dictionary = _view.get("city", {})
	_text(Vector2(22.0, 32.0), str(meta.get("name", "城池")), 25, LABEL)
	_text(Vector2(22.0, 55.0), "内城 · 点击建筑查看建设与升级", 14, Color("b0b7a4"))
	var queues_value: Variant = _view.get("queues", [])
	var queues: Array = (queues_value as Dictionary).get("build", []) if queues_value is Dictionary else queues_value if queues_value is Array else []
	var queue_text: String = "当前无建设队列" if queues.is_empty() else "建设队列 %d 项 · 进度由城池账册同步" % queues.size()
	_text(Vector2(22.0, h - 18.0), queue_text, 14, GOLD)
	if rows.is_empty():
		_text(Vector2(22.0, 88.0), "正在读取城池数据…", 16, LABEL)

func _draw_walls(w: float, h: float) -> void:
	var stone: Color = Color("73776b")
	var shadow: Color = Color("2c3430")
	var left: Vector2 = Vector2(w * 0.075, h * 0.78)
	var right: Vector2 = Vector2(w * 0.935, h * 0.78)
	draw_line(Vector2(w * 0.11, h * 0.24), left, shadow, 17.0)
	draw_line(Vector2(w * 0.87, h * 0.24), right, shadow, 17.0)
	draw_line(Vector2(w * 0.10, h * 0.24), Vector2(w * 0.88, h * 0.24), stone, 9.0)
	draw_line(left, right, shadow, 23.0)
	draw_line(left - Vector2(0.0, 10.0), right - Vector2(0.0, 10.0), stone, 14.0)
	for i: int in range(33):
		var x: float = lerpf(left.x, right.x, float(i) / 32.0)
		draw_rect(Rect2(Vector2(x - 4.0, left.y - 26.0), Vector2(8.0, 12.0)), Color("818276"))
	for p: Vector2 in [left, right, Vector2(w * 0.10, h * 0.24), Vector2(w * 0.88, h * 0.24)]:
		draw_rect(Rect2(p - Vector2(15.0, 35.0), Vector2(30.0, 40.0)), Color("626c63"))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-21.0, -35.0), p + Vector2(0.0, -49.0), p + Vector2(21.0, -35.0)]), Color("283c3a"))
		_draw_flag(p + Vector2(0.0, -50.0), Color("937345"))

func _draw_building(id: String, label: String, level: int, base: Vector2, w: float, h: float, site: int) -> void:
	var rect: Rect2 = Rect2(base - Vector2(w * 0.60, h * 1.6), Vector2(w * 1.20, h * 2.25))
	var key: String = "%s#%d" % [id, site]
	_hit_boxes[key] = rect
	_hit_records[key] = {"id": id, "site": site}
	var active: bool = key == _hover or key == _selected
	var constructed: bool = level > 0
	var timber: Color = Color("817358") if constructed else Color("4b5043")
	var roof: Color = Color("3c5250") if constructed else Color("303d36")
	_draw_oval_shadow(base + Vector2(5.0, 5.0), Vector2(w * 0.63, h * 0.29), Color(0.04, 0.07, 0.06, 0.32))
	if id == "drill":
		draw_rect(Rect2(base - Vector2(w * 0.52, h * 0.85), Vector2(w * 1.05, h * 0.85)), Color("626046"))
		for i: int in range(4):
			var p: Vector2 = base + Vector2(float(i) * w * 0.20 - w * 0.32, -h * 0.32)
			draw_line(p + Vector2(0.0, -14.0), p + Vector2(0.0, 6.0), Color("a49569"), 2.0)
			draw_circle(p + Vector2(0.0, -11.0), 4.0, Color("614d35"))
	elif id == "wall":
		draw_rect(Rect2(base - Vector2(w * 0.55, h * 0.8), Vector2(w * 1.1, h * 0.75)), Color("6f786f"))
		for i: int in range(6):
			draw_rect(Rect2(base + Vector2(float(i) * w / 6.0 - w * 0.55, -h), Vector2(w / 10.0, h * 0.35)), Color("828c7f"))
	else:
		draw_rect(Rect2(base - Vector2(w * 0.48, h), Vector2(w * 0.96, h)), timber)
		draw_rect(Rect2(base + Vector2(w * 0.26, -h), Vector2(w * 0.22, h)), timber.darkened(0.24))
		var points: PackedVector2Array = PackedVector2Array([base + Vector2(-w * 0.63, -h * 0.98), base + Vector2(0.0, -h * 1.55), base + Vector2(w * 0.63, -h * 0.98), base + Vector2(w * 0.52, -h * 0.82), base + Vector2(-w * 0.52, -h * 0.82)])
		draw_colored_polygon(points, roof)
		draw_polyline(PackedVector2Array([points[0], points[1], points[2]]), roof.lightened(0.25), 2.0, true)
		for i: int in range(7):
			var x: float = -w * 0.50 + float(i) * w / 6.0
			draw_line(base + Vector2(x, -h * 1.0), base + Vector2(x * 0.15, -h * 1.42), Color(0.04, 0.10, 0.10, 0.35), 1.0)
		draw_rect(Rect2(base + Vector2(-w * 0.11, -h * 0.64), Vector2(w * 0.22, h * 0.64)), Color("26332e"))
		for side: int in [-1, 1]:
			draw_rect(Rect2(base + Vector2(float(side) * w * 0.31 - w * 0.06, -h * 0.62), Vector2(w * 0.12, h * 0.26)), Color("a3976b") if constructed else INK)
		if id == "hall":
			draw_line(base + Vector2(-w * 0.48, 2.0), base + Vector2(w * 0.48, 2.0), GOLD, 3.0)
		if id in ["barracks", "beacon"]:
			_draw_flag(base + Vector2(w * 0.40, -h * 1.40), Color("826340"))
		if id in ["house", "workshop", "inn", "tavern"] and constructed:
			for i: int in range(4):
				var phase: float = fmod(_time * 0.22 + float(i) * 0.25, 1.0)
				var p: Vector2 = base + Vector2(w * 0.25 + sin(phase * 5.0 + float(i)) * 8.0, -h * 1.5 - phase * 36.0)
				draw_circle(p, 3.0 + phase * 6.0, Color(0.72, 0.73, 0.65, (1.0 - phase) * 0.13))
	if active:
		draw_rect(rect.grow(3.0), Color(0.74, 0.62, 0.40, 0.10))
		draw_rect(rect.grow(3.0), GOLD, false, 1.5)
	var text: String = "%s  %d级" % [label, level] if constructed else "%s · 未建" % label
	var font: Font = CHINESE_FONT
	var font_size: int = 14 if size.x > 650.0 else 12
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var badge: Rect2 = Rect2(base + Vector2(-text_width / 2.0 - 6.0, 8.0), Vector2(text_width + 12.0, 22.0))
	draw_rect(badge, Color(0.08, 0.13, 0.12, 0.93))
	_text(badge.position + Vector2(6.0, 16.0), text, font_size, LABEL if constructed else Color("9ca18c"))

func _draw_gate(base: Vector2, w: float, h: float) -> void:
	draw_rect(Rect2(base - Vector2(w * 0.5, h), Vector2(w, h)), Color("687268"))
	draw_rect(Rect2(base - Vector2(w * 0.22, h * 0.68), Vector2(w * 0.44, h * 0.68)), Color("172624"))
	draw_colored_polygon(PackedVector2Array([base + Vector2(-w * 0.64, -h), base + Vector2(0.0, -h * 1.50), base + Vector2(w * 0.64, -h)]), Color("304845"))
	_draw_flag(base + Vector2(0.0, -h * 1.55), Color("9a7946"))

func _draw_flag(p: Vector2, color: Color) -> void:
	draw_line(p, p + Vector2(0.0, 24.0), Color("a89b73"), 1.5)
	var flutter: float = sin(_time * 1.7 + p.x * 0.01) * 3.0
	draw_colored_polygon(PackedVector2Array([p, p + Vector2(17.0, 3.0 + flutter), p + Vector2(14.0, 13.0 + flutter), p + Vector2(0.0, 12.0)]), color)

func _draw_oval_shadow(center: Vector2, radius: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(24):
		var angle: float = TAU * float(i) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)

func _text(point: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(CHINESE_FONT, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
