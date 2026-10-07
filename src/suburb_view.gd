class_name KingdomSuburbView
extends Control

## The landscape is presentation only. Availability, identity and levels are bridge data.
signal plot_selected(index: int)

const CHINESE_FONT: Font = preload("res://assets/fonts/UI.tres")
const TEXT: Color = Color("efe7d5")
const MUTED: Color = Color("c8c4ae")
const GOLD: Color = Color("d9bd7d")
const EARTH: Color = Color("77795d")
const ROAD: Color = Color("a69a7d")
const TAP_TRAVEL_LIMIT: float = 10.0

var _view: Dictionary = {}
var _plots_by_index: Dictionary = {}
var _hit_boxes: Dictionary = {}
var _hit_records: Dictionary = {}
var _site_positions: Dictionary = {}
var _site_slots: Dictionary = {}
var _wide_site_slots: Dictionary = {}
var _capacity: int = 12
var _mobile_slot_columns: int = 2
var _wide_slot_columns: int = 3
var _selected: int = -1
var _hover: int = -1
var _city: String = ""
var _touches: Dictionary = {}
var _touch_index: int = -1
var _touch_plot: int = -1
var _touch_start: Vector2 = Vector2.ZERO
var _touch_last: Vector2 = Vector2.ZERO
var _touch_travel: float = 0.0
var _touch_cancelled: bool = false

func _ready() -> void:
	# Unhandled presses and drags must reach the enclosing ScrollContainer.
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	tooltip_text = "点击实际地块，查看建设、等级与费用"
	mouse_exited.connect(func() -> void:
		_hover = -1
		queue_redraw())
	_update_minimum_height()

func set_view(view: Dictionary) -> void:
	var next_city: String = str(view.get("realmManagement", {}).get("currentCity", view.get("city", {}).get("id", view.get("city", {}).get("name", ""))))
	if next_city != _city:
		_city = next_city
		_site_slots.clear()
		_wide_site_slots.clear()
		_selected = -1
		_capacity = 12
		_clear_touch_gesture()
	_view = view.duplicate(true)
	_plots_by_index.clear()
	var rows: Array[Dictionary] = []
	for value: Variant in _view.get("plots", []):
		if value is Dictionary and int(value.get("index", -1)) >= 0:
			var row: Dictionary = value
			if bool(row.get("unlocked", false)):
				rows.append(row)
				_plots_by_index[int(row.index)] = row
	_capacity = maxi(12, rows.size())
	# A parcel's location depends only on its canonical index, including across UI recreation.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.index) < int(b.index))
	var mobile_columns: int = 3 if _capacity > 12 else 2
	var wide_columns: int = 4 if _capacity > 12 else 3
	_mobile_slot_columns = mobile_columns
	_wide_slot_columns = wide_columns
	_assign_slots(rows, _site_slots, mobile_columns)
	_assign_slots(rows, _wide_site_slots, wide_columns)
	if not _plots_by_index.has(_selected):
		_selected = -1
	if not _plots_by_index.has(_hover):
		_hover = -1
	_hit_boxes.clear()
	_hit_records.clear()
	_update_minimum_height()
	queue_redraw()

func select_plot(index: int) -> void:
	_selected = index if _plots_by_index.has(index) else -1
	queue_redraw()

func selected_plot() -> int:
	return _selected

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_minimum_height()
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_clear_touch_gesture()

func _update_minimum_height() -> void:
	var height: float = recommended_minimum_height(size.x)
	if not is_equal_approx(custom_minimum_size.y, height):
		custom_minimum_size = Vector2(0.0, height)

func recommended_minimum_height(width: float) -> float:
	var columns: int = _wide_slot_columns if width >= 530.0 else _mobile_slot_columns
	var row_count: int = int(ceil(float(_capacity) / float(columns)))
	var row_height: float = 58.0 if _capacity > 12 else 77.0 if columns == 2 else 83.0
	return maxf(430.0, 140.0 + float(row_count) * row_height)

func _kind(row: Dictionary) -> String:
	var value: Variant = row.get("id")
	if value == null or str(value).is_empty():
		return "empty"
	return str({"lumber": "wood", "quarry": "stone", "mine": "iron"}.get(str(value), str(value)))

func _assign_slots(rows: Array[Dictionary], slots: Dictionary, columns: int) -> void:
	slots.clear()
	var order: Array[int] = []
	var row_count: int = int(ceil(float(_capacity) / float(columns)))
	for row: int in range(row_count - 1, -1, -1):
		for column: int in range(columns):
			var slot: int = row * columns + column
			if slot < _capacity:
				order.append(slot)
	var used: Dictionary = {}
	for row: Dictionary in rows:
		var index: int = int(row.index)
		var seed: int = index % _capacity
		for offset: int in range(_capacity):
			var slot: int = order[(seed + offset) % _capacity]
			if not used.has(slot):
				slots[index] = slot
				used[slot] = true
				break

func _gui_input(event: InputEvent) -> void:
	# Native touch owns tap recognition. Its compatibility mouse events still bubble.
	if (event is InputEventMouseMotion or event is InputEventMouseButton) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		var next: int = _plot_at(event.position)
		if next != _hover:
			_hover = next
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if next >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_activate(_plot_at(event.position))
	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index] = event.position
			if event.index == _touch_index:
				_record_touch_motion(event.position)

func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _touches.is_empty():
			_touch_index = touch.index
			_touch_plot = _plot_at(touch.position)
			_touch_start = get_global_transform_with_canvas() * touch.position
			_touch_last = _touch_start
			_touch_travel = 0.0
			_touch_cancelled = touch.canceled
		else:
			_touch_cancelled = true
		_touches[touch.index] = touch.position
		return
	if not _touches.has(touch.index):
		return
	if touch.index == _touch_index:
		_record_touch_motion(touch.position)
	var plot: int = _touch_plot
	var is_tap: bool = touch.index == _touch_index and _touches.size() == 1 and not touch.canceled and not _touch_cancelled and plot >= 0 and _plot_at(touch.position) == plot
	_touches.erase(touch.index)
	if _touches.is_empty():
		_clear_touch_gesture()
	else:
		# A multi-finger gesture cannot become a tap when one finger remains.
		_touch_cancelled = true
		_touch_index = -1
		_touch_plot = -1
	if is_tap:
		_activate(plot)

func _record_touch_motion(position: Vector2) -> void:
	# The parent can move this entire scene while scrolling; local coordinates can stand still.
	var canvas_position: Vector2 = get_global_transform_with_canvas() * position
	_touch_travel += _touch_last.distance_to(canvas_position)
	_touch_last = canvas_position
	if _touch_travel > TAP_TRAVEL_LIMIT or _touch_start.distance_to(canvas_position) > TAP_TRAVEL_LIMIT:
		_touch_cancelled = true

func _clear_touch_gesture() -> void:
	_touches.clear()
	_touch_index = -1
	_touch_plot = -1
	_touch_travel = 0.0
	_touch_cancelled = false

func _activate(index: int) -> void:
	if index < 0 or not _plots_by_index.has(index):
		return
	_selected = index
	plot_selected.emit(index)
	accept_event()
	queue_redraw()

func _plot_at(point: Vector2) -> int:
	for index: int in _hit_boxes:
		if (_hit_boxes[index] as Rect2).has_point(point):
			return index
	return -1

func _draw() -> void:
	if size.x < 30.0 or size.y < 30.0:
		return
	_hit_boxes.clear()
	_hit_records.clear()
	_site_positions.clear()
	var w: float = size.x
	var h: float = size.y
	var columns: int = _wide_slot_columns if w >= 530.0 else _mobile_slot_columns
	var row_count: int = int(ceil(float(_capacity) / float(columns)))
	var map: Rect2 = Rect2(9.0, 72.0, w - 18.0, h - 140.0)
	_draw_landscape(w, h, map)
	var slots: Dictionary = _wide_site_slots if w >= 530.0 else _site_slots
	for index: int in _plots_by_index:
		var slot: int = int(slots.get(index, 0))
		var row: int = int(slot / columns)
		var column: int = slot % columns
		var cell: Vector2 = Vector2(map.size.x / float(columns), map.size.y / float(row_count))
		var jitter: Vector2 = Vector2(sin(float(slot) * 2.7) * 3.0, cos(float(slot) * 1.8) * (1.0 if _capacity > 12 else 3.0))
		var margins: Vector2 = Vector2(14.0, 8.0 if _capacity > 12 else 12.0)
		var rect: Rect2 = Rect2(map.position + Vector2(float(column) * cell.x, float(row) * cell.y) + Vector2(7.0, 3.0 if _capacity > 12 else 5.0) + jitter, cell - margins)
		_hit_boxes[index] = rect
		_hit_records[index] = _plots_by_index[index].duplicate(true)
		_site_positions[index] = rect.get_center()
	# Paths connect visible actual parcels to the gate; they grant no rule effects.
	for index: int in _hit_boxes:
		var rect: Rect2 = _hit_boxes[index]
		var base: Vector2 = rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.68)
		var turn_y: float = base.y + sin(float(index) * 2.4) * 10.0
		var road_point: Vector2 = Vector2(_road_x(turn_y, w, h), turn_y)
		var bend: Vector2 = road_point.lerp(base, 0.58) + Vector2(0.0, 6.0 + sin(float(index)) * 4.0)
		var points: PackedVector2Array = PackedVector2Array([road_point, bend, base + Vector2(0.0, 9.0), base])
		draw_polyline(points, Color("696b52"), 8.0, true)
		draw_polyline(points, ROAD, 5.0, true)
		if _kind(_plots_by_index[index]) == "farm":
			var left_bank: bool = base.x < w * 0.50
			var water_x: float = w * (0.055 if left_bank else 0.955)
			var edge_x: float = rect.position.x + 3.0 if left_bank else rect.end.x - 3.0
			var canal: PackedVector2Array = PackedVector2Array([Vector2(water_x, base.y - 15.0), Vector2(edge_x, base.y - 12.0), Vector2(edge_x, rect.position.y + 7.0)])
			draw_polyline(canal, Color("b0a585"), 5.0, true)
			draw_polyline(canal, Color("719699"), 2.0, true)
	for index: int in _hit_boxes:
		_draw_site(index, _plots_by_index[index], _hit_boxes[index])
	_draw_gate(Vector2(w * 0.50, h - 27.0), minf(w * 0.14, 66.0))
	_draw_headings(w, h)

func _draw_landscape(w: float, h: float, map: Rect2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), EARTH)
	draw_rect(Rect2(0.0, 0.0, w, 61.0), Color("697b7c"))
	# Layered wooded and mineral slopes are continuous terrain, not resource cards.
	_polygon([Vector2(0, 78), Vector2(w * 0.09, 45), Vector2(w * 0.24, 64), Vector2(w * 0.40, 36), Vector2(w * 0.59, 77), Vector2(w, 72), Vector2(w, h * 0.42), Vector2(0, h * 0.40)], Color("596a5d"))
	_polygon([Vector2(w * 0.45, 115), Vector2(w * 0.63, 54), Vector2(w * 0.76, 77), Vector2(w * 0.89, 42), Vector2(w, 88), Vector2(w, h * 0.46), Vector2(w * 0.71, h * 0.37)], Color("777a6d"))
	_polygon([Vector2(w * 0.66, 101), Vector2(w * 0.77, 85), Vector2(w * 0.82, 115), Vector2(w * 0.96, 70), Vector2(w, 93), Vector2(w, maxf(h * 0.29, 165.0)), Vector2(w * 0.72, maxf(h * 0.24, 150.0))], Color("909183"))
	_polygon([Vector2(0, h * 0.33), Vector2(w * 0.25, h * 0.29), Vector2(w * 0.49, h * 0.44), Vector2(w * 0.71, h * 0.31), Vector2(w, h * 0.46), Vector2(w, h), Vector2(0, h)], Color("858269"))
	_polygon([Vector2(0, h * 0.61), Vector2(w * 0.18, h * 0.58), Vector2(w * 0.41, h * 0.67), Vector2(w * 0.67, h * 0.61), Vector2(w, h * 0.78), Vector2(w, h), Vector2(0, h)], Color("8b896a"))
	for i: int in range(34):
		var p: Vector2 = Vector2(fmod(float(i) * 73.0 + 27.0, w), map.position.y + fmod(float(i) * 57.0 + 34.0, map.size.y))
		draw_line(p, p + Vector2(6.0, -2.0), Color(0.29, 0.34, 0.25, 0.28), 1.0, true)
		if i % 4 == 0:
			_oval(p + Vector2(2.0, 3.0), Vector2(4.0, 2.0), Color("9d9a80"))
	var stream: PackedVector2Array = PackedVector2Array([Vector2(w * 0.02, 74.0), Vector2(w * 0.065, h * 0.27), Vector2(w * 0.035, h * 0.45), Vector2(w * 0.06, h * 0.69), Vector2(w * 0.15, h * 0.91), Vector2(w * 0.31, h)])
	draw_polyline(stream, Color("a6a187"), 13.0, true)
	draw_polyline(stream, Color("6f9395"), 8.0, true)
	draw_polyline(stream, Color(0.66, 0.77, 0.75, 0.6), 1.0, true)
	var east_fields: bool = false
	for index: int in _plots_by_index:
		var slots: Dictionary = _wide_site_slots if w >= 530.0 else _site_slots
		var columns: int = _wide_slot_columns if w >= 530.0 else _mobile_slot_columns
		if _kind(_plots_by_index[index]) == "farm" and int(slots.get(index, 0)) % columns >= int(columns / 2):
			east_fields = true
			break
	if east_fields:
		var irrigation: PackedVector2Array = PackedVector2Array([Vector2(w * 0.095, h - 77.0), Vector2(w * 0.34, h - 75.0), Vector2(w * 0.68, h - 82.0), Vector2(w * 0.955, h - 80.0), Vector2(w * 0.955, 72.0)])
		draw_polyline(irrigation, Color("b0a585"), 6.0, true)
		draw_polyline(irrigation, Color("719699"), 3.0, true)
	var road: PackedVector2Array = PackedVector2Array()
	for i: int in range(15):
		var y: float = lerpf(72.0, h - 26.0, float(i) / 14.0)
		road.append(Vector2(_road_x(y, w, h), y))
	draw_polyline(road, Color("727158"), 15.0, true)
	draw_polyline(road, ROAD, 10.0, true)
	for i: int in range(10):
		var p: Vector2 = Vector2(w * (0.08 + float(i % 3) * 0.06), 88.0 + float(i) * 8.0)
		_draw_tree(p, 12.0 + float(i % 3) * 2.0, true)
	# The lower wall identifies the south gate and the boundary of the city.
	draw_rect(Rect2(0.0, h - 39.0, w, 22.0), Color("686d65"))
	draw_line(Vector2(0, h - 41.0), Vector2(w, h - 41.0), Color("a1a190"), 4.0)
	for i: int in range(int(w / 18.0) + 1):
		draw_rect(Rect2(float(i) * 18.0, h - 46.0, 10.0, 9.0), Color("929688"))
		draw_line(Vector2(float(i) * 18.0, h - 27.0), Vector2(float(i) * 18.0 + 18.0, h - 27.0), Color("7c8275"), 1.0)

func _road_x(y: float, w: float, h: float) -> float:
	return w * (0.50 + sin((y / h) * 5.6) * 0.034)

func _draw_site(index: int, row: Dictionary, rect: Rect2) -> void:
	var kind: String = _kind(row)
	var ground: Rect2 = Rect2(rect.position + Vector2(4.0, 7.0), rect.size - Vector2(8.0, 29.0))
	var base: Vector2 = ground.position + Vector2(ground.size.x * 0.5, ground.size.y * 0.75)
	var selected: bool = index == _selected
	if selected or index == _hover:
		_oval(ground.get_center(), Vector2(ground.size.x * 0.55, ground.size.y * 0.55), Color(0.87, 0.75, 0.46, 0.18))
	if kind == "farm":
		_draw_farm(ground, index)
	elif kind == "wood":
		_draw_woodlot(ground)
	elif kind == "stone":
		_draw_quarry(ground)
	elif kind == "iron":
		_draw_ironworks(ground)
	else:
		_draw_unbuilt(ground, index)
	if row.get("queue") != null:
		# A work marker reports an actual queue, without inventing production motion.
		var marker: Vector2 = base + Vector2(ground.size.x * 0.31, -ground.size.y * 0.62)
		draw_line(marker, marker + Vector2(0, 20), Color("62513c"), 2.0)
		_polygon([marker, marker + Vector2(12, 3), marker + Vector2(10, 11), marker + Vector2(0, 9)], Color("b9a36e"))
	if selected:
		var outline: PackedVector2Array = PackedVector2Array()
		for i: int in range(25):
			var angle: float = TAU * float(i) / 24.0
			outline.append(ground.get_center() + Vector2(cos(angle) * ground.size.x * 0.54, sin(angle) * ground.size.y * 0.56))
		draw_polyline(outline, GOLD, 2.0, true)
	var constructed: bool = kind != "empty"
	var name: String = str(row.get("name", "空地"))
	var label: String = "%d %s · %d级" % [index + 1, name, int(row.get("level", 0))] if constructed else "%d 空地 · 未建" % (index + 1)
	if row.get("queue") != null:
		label = "%d %s · 建设中" % [index + 1, name]
	if rect.size.x < 105.0:
		label = "%d%s·%d级" % [index + 1, name, int(row.get("level", 0))] if constructed else "%d空地·未建" % (index + 1)
		if row.get("queue") != null:
			label = "%d%s·在建" % [index + 1, name]
	var font_size: int = 11 if rect.size.x < 105.0 else 13 if size.x >= 530.0 else 12
	label = _elide(label, rect.size.x - 10.0, font_size)
	var text_width: float = CHINESE_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var plaque: Rect2 = Rect2(Vector2(rect.get_center().x - text_width * 0.5 - 3.0, rect.end.y - 19.0), Vector2(text_width + 6.0, 18.0))
	if selected or index == _hover:
		draw_rect(plaque, Color(0.18, 0.21, 0.17, 0.72))
	if selected:
		draw_line(plaque.position, plaque.position + Vector2(plaque.size.x, 0), GOLD, 2.0)
	var baseline: Vector2 = plaque.position + Vector2(3.0, 14.0)
	draw_string_outline(CHINESE_FONT, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0.19, 0.22, 0.17, 0.91))
	_text(baseline, label, font_size, GOLD if selected else TEXT if constructed else MUTED)

func _draw_farm(rect: Rect2, index: int) -> void:
	var p: Vector2 = rect.position
	var d: Vector2 = rect.size
	var field: PackedVector2Array = PackedVector2Array([p + Vector2(d.x * 0.08, 2), p + Vector2(d.x * 0.91, 0), p + Vector2(d.x, d.y * 0.89), p + Vector2(0, d.y)])
	draw_colored_polygon(field, Color("676d43") if index % 2 == 0 else Color("827746"))
	field.append(field[0])
	draw_polyline(field, Color("b4a17a"), 2.0, true)
	for i: int in range(7):
		var t: float = float(i + 1) / 8.0
		var left: Vector2 = p + Vector2(lerpf(d.x * 0.08, 0.0, t), d.y * t)
		var right: Vector2 = p + Vector2(lerpf(d.x * 0.91, d.x, t), d.y * t * 0.89)
		draw_line(left, right, Color("aaa166"), 2.0, true)
		for j: int in range(6):
			var crop: Vector2 = left.lerp(right, (float(j) + 0.45) / 6.0)
			draw_line(crop, crop + Vector2(1.0, -3.5), Color("bcc080"), 1.0, true)
	var hut: Vector2 = p + Vector2(d.x * 0.79, d.y * 0.25)
	_draw_house(hut, Vector2(d.x * 0.25, d.y * 0.33), true)
	var canal_side: float = 0.08 if rect.get_center().x < size.x * 0.50 else 0.93
	draw_line(p + Vector2(d.x * canal_side, d.y * 0.10), p + Vector2(d.x * canal_side, d.y * 0.85), Color("799b99"), 2.0, true)

func _draw_woodlot(rect: Rect2) -> void:
	var p: Vector2 = rect.position
	var d: Vector2 = rect.size
	_oval(rect.get_center(), Vector2(d.x * 0.49, d.y * 0.51), Color("65705b"))
	for i: int in range(5):
		_draw_tree(p + Vector2(d.x * (0.10 + float(i) * 0.18), d.y * (0.35 + float(i % 2) * 0.18)), d.y * 0.47, false)
	_draw_house(p + Vector2(d.x * 0.64, d.y * 0.84), Vector2(d.x * 0.36, d.y * 0.39), false)
	for i: int in range(4):
		var log: Vector2 = p + Vector2(d.x * 0.16, d.y * 0.79 - float(i) * 3.0)
		draw_line(log, log + Vector2(d.x * 0.29, -2), Color("63513b"), 4.0, true)
		draw_circle(log, 2.1, Color("b4a176"))
	# A static trestle saw and timber pile distinguish this facility from a house.
	var saw: Vector2 = p + Vector2(d.x * 0.77, d.y * 0.74)
	draw_line(saw, saw + Vector2(0, -12), Color("b3b3a3"), 1.5)
	draw_line(saw + Vector2(-5, 0), saw + Vector2(5, 0), Color("746047"), 2.0)

func _draw_quarry(rect: Rect2) -> void:
	var p: Vector2 = rect.position
	var d: Vector2 = rect.size
	_polygon([p + Vector2(0, d.y * 0.63), p + Vector2(d.x * 0.10, d.y * 0.14), p + Vector2(d.x * 0.57, 0), p + Vector2(d.x, d.y * 0.45), p + Vector2(d.x * 0.81, d.y), p + Vector2(d.x * 0.21, d.y * 0.97)], Color("98988b"))
	for i: int in range(4):
		var y: float = d.y * (0.25 + float(i) * 0.17)
		var x: float = d.x * (0.14 + float(i) * 0.06)
		draw_line(p + Vector2(x, y), p + Vector2(d.x * 0.73, y + d.y * 0.10), Color("686f65"), 3.0, true)
	for i: int in range(4):
		var block: Vector2 = p + Vector2(d.x * (0.57 + float(i % 2) * 0.17), d.y * (0.64 + float(i / 2) * 0.15))
		draw_rect(Rect2(block, Vector2(d.x * 0.14, d.y * 0.15)), Color("bdbaa7"))
		draw_line(block, block + Vector2(d.x * 0.14, 0), Color("d1cdb7"), 1.0)
	_draw_house(p + Vector2(d.x * 0.20, d.y * 0.95), Vector2(d.x * 0.23, d.y * 0.28), false)

func _draw_ironworks(rect: Rect2) -> void:
	var p: Vector2 = rect.position
	var d: Vector2 = rect.size
	_polygon([p + Vector2(d.x * 0.02, d.y * 0.75), p + Vector2(d.x * 0.19, 0), p + Vector2(d.x * 0.61, d.y * 0.08), p + Vector2(d.x * 0.81, d.y * 0.77)], Color("7a7669"))
	var adit: Vector2 = p + Vector2(d.x * 0.33, d.y * 0.45)
	draw_rect(Rect2(adit, Vector2(d.x * 0.22, d.y * 0.33)), Color("373a32"))
	draw_line(adit, adit + Vector2(d.x * 0.22, 0), Color("aa9876"), 3.0)
	draw_line(adit, adit + Vector2(0, d.y * 0.33), Color("8c7759"), 3.0)
	draw_line(adit + Vector2(d.x * 0.22, 0), adit + Vector2(d.x * 0.22, d.y * 0.33), Color("8c7759"), 3.0)
	# An unlit clay furnace and ore stack show structures, not fabricated activity.
	var furnace: Vector2 = p + Vector2(d.x * 0.77, d.y * 0.81)
	_polygon([furnace + Vector2(-d.x * 0.13, 0), furnace + Vector2(-d.x * 0.085, -d.y * 0.44), furnace + Vector2(d.x * 0.065, -d.y * 0.44), furnace + Vector2(d.x * 0.14, 0)], Color("9b7e62"))
	draw_rect(Rect2(furnace + Vector2(-3, -d.y * 0.19), Vector2(6, d.y * 0.19)), Color("494135"))
	draw_line(furnace + Vector2(-d.x * 0.10, -d.y * 0.45), furnace + Vector2(d.x * 0.08, -d.y * 0.45), Color("c3ac88"), 2.0)
	for i: int in range(5):
		_oval(p + Vector2(d.x * 0.16 + float(i % 3) * 7.0, d.y * 0.88 - float(i / 3) * 4.0), Vector2(5, 3), Color("5e5b4e"))

func _draw_unbuilt(rect: Rect2, index: int) -> void:
	var p: Vector2 = rect.position
	var d: Vector2 = rect.size
	_polygon([p + Vector2(d.x * 0.05, d.y * 0.13), p + Vector2(d.x * 0.90, 0), p + Vector2(d.x, d.y * 0.88), p + Vector2(0, d.y)], Color("929076"))
	for i: int in range(6):
		var grass: Vector2 = p + Vector2(d.x * (0.13 + float(i % 3) * 0.31), d.y * (0.37 + float(i / 3) * 0.34))
		draw_line(grass, grass + Vector2(-2, -4), Color("667451"), 1.0)
		draw_line(grass, grass + Vector2(2, -5), Color("737e57"), 1.0)
	for corner: Vector2 in [p + Vector2(d.x * 0.05, d.y * 0.13), p + Vector2(d.x * 0.90, 0), p + Vector2(d.x, d.y * 0.88), p + Vector2(0, d.y)]:
		draw_line(corner, corner - Vector2(0, 6), Color("c0ab7f"), 2.0)
	var stake: Vector2 = p + Vector2(d.x * 0.51, d.y * 0.58)
	draw_line(stake, stake + Vector2(0, 10), Color("6e6047"), 2.0)
	draw_rect(Rect2(stake - Vector2(10, 9), Vector2(20, 12)), Color("c2b58e"))
	_text(stake + Vector2(-7.0, 1.0), str(index + 1), 10, Color("484c3c"))

func _draw_house(base: Vector2, dimensions: Vector2, thatch: bool) -> void:
	var w: float = dimensions.x
	var h: float = dimensions.y
	_oval(base + Vector2(3, 2), Vector2(w * 0.58, 4), Color(0.21, 0.24, 0.18, 0.28))
	draw_rect(Rect2(base - Vector2(w * 0.44, h), Vector2(w * 0.88, h)), Color("b1a07c"))
	draw_rect(Rect2(base + Vector2(w * 0.20, -h), Vector2(w * 0.24, h)), Color("8a8064"))
	var roof: Color = Color("ada07a") if thatch else Color("66716f")
	_polygon([base + Vector2(-w * 0.55, -h * 0.95), base + Vector2(-w * 0.34, -h * 1.50), base + Vector2(w * 0.31, -h * 1.52), base + Vector2(w * 0.56, -h * 0.95)], roof)
	draw_line(base + Vector2(-w * 0.54, -h * 0.95), base + Vector2(w * 0.56, -h * 0.95), roof.lightened(0.2), 1.5)
	for i: int in range(6):
		var x: float = -0.37 + float(i) * 0.14
		draw_line(base + Vector2(w * x, -h * 1.43), base + Vector2(w * x * 1.30, -h), roof.darkened(0.16), 1.0)
	draw_rect(Rect2(base - Vector2(w * 0.12, h * 0.60), Vector2(w * 0.24, h * 0.60)), Color("514f3e"))

func _draw_tree(base: Vector2, height: float, distant: bool) -> void:
	draw_line(base, base - Vector2(0, height * 0.51), Color("665740"), 2.0)
	var shade: Color = Color("4b6250") if distant else Color("4f654b")
	_oval(base - Vector2(0, height * 0.69), Vector2(height * 0.32, height * 0.43), shade)
	_oval(base - Vector2(height * 0.16, height * 0.82), Vector2(height * 0.22, height * 0.26), shade.lightened(0.07))
	_oval(base - Vector2(-height * 0.17, height * 0.72), Vector2(height * 0.25, height * 0.29), shade.darkened(0.07))

func _draw_gate(base: Vector2, width: float) -> void:
	var height: float = width * 0.43
	draw_rect(Rect2(base - Vector2(width * 0.46, height), Vector2(width * 0.92, height + 9.0)), Color("a39e8a"))
	draw_rect(Rect2(base - Vector2(width * 0.16, height * 0.65), Vector2(width * 0.32, height * 0.65 + 9.0)), Color("484e43"))
	_polygon([base + Vector2(-width * 0.59, -height), base + Vector2(-width * 0.34, -height * 1.54), base + Vector2(width * 0.33, -height * 1.54), base + Vector2(width * 0.59, -height)], Color("586665"))
	draw_line(base + Vector2(-width * 0.58, -height), base + Vector2(width * 0.58, -height), Color("a2aaa0"), 2.0)
	_text(Vector2(base.x - 12.0, base.y + 6.0), "南门", 12, TEXT)

func _draw_headings(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, 65), Color(0.17, 0.22, 0.20, 0.91))
	var city_name: String = str(_view.get("city", {}).get("name", "城池"))
	_text(Vector2(14, 25), _elide(city_name + " · 城外", w - 28.0, 19), 19, TEXT)
	var counts: Dictionary = {"farm": 0, "wood": 0, "stone": 0, "iron": 0, "empty": 0}
	for row: Dictionary in _plots_by_index.values():
		var kind: String = _kind(row)
		if counts.has(kind):
			counts[kind] += 1
	var summary: String = "田 %d · 林 %d · 石 %d · 铁 %d · 空 %d" % [counts.farm, counts.wood, counts.stone, counts.iron, counts.empty]
	_text(Vector2(14, 48), _elide(summary, w - 28.0, 13), 13, MUTED)
	draw_rect(Rect2(0, h - 18, w, 18), Color("3d483d"))
	var hint: String = "点击地块查看建设 · 可用 %d 块" % _plots_by_index.size()
	if _plots_by_index.is_empty():
		hint = "暂无已解锁地块"
	_text(Vector2(12, h - 4), _elide(hint, w - 24.0, 12), 12, TEXT)

func _elide(value: String, width: float, font_size: int) -> String:
	if CHINESE_FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return value
	var result: String = value
	while not result.is_empty() and CHINESE_FONT.get_string_size(result + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		result = result.left(result.length() - 1)
	return result + "…"

func _text(position: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(CHINESE_FONT, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _polygon(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)

func _oval(center: Vector2, radius: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(20):
		var angle: float = TAU * float(i) / 20.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
