extends Control

const ApiScript: Script = preload("res://src/game_api.gd")
const MapScript: Script = preload("res://src/world_map.gd")
const CityScript: Script = preload("res://src/city_view.gd")
const BattleScript: Script = preload("res://src/battle_view.gd")
const FONT: Font = preload("res://assets/fonts/UI.tres")
const RES_NAMES: Dictionary = {"food": "粮草", "wood": "木材", "stone": "石料", "iron": "铁锭", "gold": "黄金"}

var api: KingdomApi
var _view: Dictionary = {}
var _state: Dictionary = {}
var _page: String = "world"
var _selected: Dictionary = {}
var _last_structure: String = ""
var _map: KingdomWorldMap
var _city: KingdomCityView
var _battle: KingdomBattleView
var _center: Control
var _side: VBoxContainer
var _detail: VBoxContainer
var _nav: HBoxContainer
var _status: Label
var _toast: Label
var _objective_title: Label
var _objective_text: Label
var _objective_button: Button
var _resources: Dictionary = {}
var _resource_grid: GridContainer
var _body: HBoxContainer
var _sidebar_panel: PanelContainer
var _detail_panel: PanelContainer
var _smoke: bool = false
var _smoke_snapshot: bool = false
var _smoke_world: bool = false
var _dialog: AcceptDialog
var _save_text: TextEdit
var _world: Dictionary = {}
var _clock: Timer
var _pending_battle: bool = false

func _ready() -> void:
	_smoke = OS.get_cmdline_user_args().has("--smoke")
	_sync_web_scale()
	theme = _make_theme()
	_build_shell()
	api = ApiScript.new() as KingdomApi
	add_child(api)
	api.snapshot_received.connect(_receive_snapshot)
	api.world_received.connect(_receive_world)
	api.status_changed.connect(_connection_changed)
	api.request_failed.connect(func(message: String) -> void: _pending_battle = false; _show_toast(message))
	api.command_completed.connect(_command_completed)
	api.export_received.connect(_show_export)
	_clock = Timer.new()
	_clock.wait_time = 1.0
	_clock.timeout.connect(_refresh_clock)
	add_child(_clock)
	_clock.start()
	_show_page("world")
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var explicit_url: String = ""
	for arg: String in arguments:
		if arg.begins_with("--api="):
			explicit_url = arg.trim_prefix("--api=")
	if not explicit_url.is_empty():
		api.connect_to(explicit_url, OS.get_environment("TK_BRIDGE_TOKEN"))
	else:
		api.start_local()
	if _smoke:
		get_tree().create_timer(25.0).timeout.connect(func() -> void:
			if not (_smoke_snapshot and _smoke_world):
				push_error("GODOT_SMOKE_FAILED: no canonical state/world")
				get_tree().quit(1))

func _make_theme() -> Theme:
	var result: Theme = Theme.new()
	result.default_font = FONT
	result.default_font_size = 16
	result.set_color("font_color", "Label", Color("e1dfcd"))
	result.set_color("font_color", "Button", Color("e5dfc7"))
	result.set_color("font_disabled_color", "Button", Color("6c746d"))
	result.set_color("font_hover_color", "Button", Color("fff1bc"))
	for node_type: String in ["PanelContainer", "Panel", "PopupPanel", "AcceptDialog"]:
		result.set_stylebox("panel", node_type, _box(Color("202a28"), Color("445046"), 8))
	result.set_stylebox("normal", "Button", _box(Color("2d3832"), Color("5c6650"), 5))
	result.set_stylebox("hover", "Button", _box(Color("435042"), Color("b19b5f"), 5))
	result.set_stylebox("pressed", "Button", _box(Color("73613c"), Color("d7bb73"), 5))
	result.set_stylebox("disabled", "Button", _box(Color("222c29"), Color("343f36"), 5))
	result.set_stylebox("normal", "LineEdit", _box(Color("172320"), Color("5b6451"), 4))
	result.set_stylebox("normal", "TextEdit", _box(Color("172320"), Color("5b6451"), 4))
	result.set_stylebox("normal", "SpinBox", _box(Color("172320"), Color("5b6451"), 4))
	result.set_constant("separation", "VBoxContainer", 12)
	result.set_constant("separation", "HBoxContainer", 12)
	return result

func _box(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box

func _build_shell() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("121d1d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	margin.add_child(root)
	var top: HBoxContainer = HBoxContainer.new()
	root.add_child(top)
	var title: Label = _label("三国城志", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_button("事务", _tasks_dialog))
	top.add_child(_button("存档", _save_dialog))
	top.add_child(_button("连接", _connection_dialog))
	_nav = HBoxContainer.new()
	root.add_child(_nav)
	for entry: Array in [["city", "城池"], ["world", "舆图"], ["army", "军队"], ["generals", "将领"], ["reports", "战报"]]:
		var button: Button = _button(str(entry[1]), _show_page.bind(str(entry[0])))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_nav.add_child(button)
	var resources_row: GridContainer = GridContainer.new()
	resources_row.columns = 5
	resources_row.add_theme_constant_override("h_separation", 8)
	_resource_grid = resources_row
	root.add_child(resources_row)
	for id: String in RES_NAMES:
		var panel: PanelContainer = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resources_row.add_child(panel)
		var label: Label = _label(str(RES_NAMES[id]) + "  —", 16)
		panel.add_child(label)
		_resources[id] = label
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_body)
	_sidebar_panel = PanelContainer.new()
	_sidebar_panel.custom_minimum_size.x = 210.0
	_body.add_child(_sidebar_panel)
	var sidebar_scroll: ScrollContainer = ScrollContainer.new()
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sidebar_panel.add_child(sidebar_scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar_scroll.add_child(_side)
	_side.add_child(_label("当前目标", 14, Color("baae85")))
	_objective_title = _label("整备城池", 21)
	_side.add_child(_objective_title)
	_objective_text = _label("正在读取进度…", 15)
	_objective_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(_objective_text)
	_objective_button = _button("查看目标", _objective_action)
	_side.add_child(_objective_button)
	_side.add_child(HSeparator.new())
	_side.add_child(_button("已解锁礼包领取", func() -> void: api.command("onboarding.claimAvailable")))
	_side.add_child(_button("任务册", _tasks_dialog))
	_side.add_child(_button("城外资源", _plots_dialog))
	_side.add_child(_button("研究", _research_dialog))
	_side.add_child(_button("宝物与物资", _inventory_dialog))
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.add_child(spacer)
	_status = _label("准备连接…", 13, Color("a8b3a3"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(_status)
	var center_scroll: ScrollContainer = ScrollContainer.new()
	center_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(center_scroll)
	_center = VBoxContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_scroll.add_child(_center)
	_detail_panel = PanelContainer.new()
	_detail_panel.custom_minimum_size.x = 275.0
	_body.add_child(_detail_panel)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail)
	_toast = _label("拖动舆图 · 滚轮缩放 · 点选目标", 14, Color("b9bfab"))
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_toast)
	resized.connect(_adapt_layout)
	call_deferred("_adapt_layout")

func _adapt_layout() -> void:
	_sync_web_scale()
	_sidebar_panel.visible = size.x >= 1000.0
	_detail_panel.visible = size.x >= 760.0
	_resource_grid.columns = 3 if size.x < 760.0 else 5
	for label: Label in _resources.values():
		label.add_theme_font_size_override("font_size", 12 if size.x < 760.0 else 16)

func _sync_web_scale() -> void:
	if OS.has_feature("web"):
		var pixel_scale: float = maxf(0.5, DisplayServer.screen_get_scale())
		if not is_equal_approx(get_window().content_scale_factor, pixel_scale):
			get_window().content_scale_factor = pixel_scale

func _label(text: String, font_size: int = 16, color: Color = Color("e1dfcd")) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 38.0
	button.disabled = disabled
	button.pressed.connect(callback)
	return button

func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _show_page(page: String) -> void:
	_page = page
	_last_structure = ""
	_clear(_center)
	_map = null
	_city = null
	_battle = null
	match page:
		"world":
			var toolbar: HBoxContainer = HBoxContainer.new()
			_center.add_child(toolbar)
			toolbar.add_child(_label("天下舆图", 22))
			toolbar.add_child(_button("回城定位", func() -> void: _map.focus_home()))
			toolbar.add_child(_button("行军", _marches_dialog))
			var map_panel: PanelContainer = PanelContainer.new()
			map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_center.add_child(map_panel)
			_map = MapScript.new() as KingdomWorldMap
			_map.custom_minimum_size = Vector2(240.0, 300.0)
			map_panel.add_child(_map)
			_map.tile_selected.connect(_select_tile)
			if not _world.is_empty():
				_map.set_world(_world)
		"city":
			_center.add_child(_label("城池 · 建设与经营", 22))
			_city = CityScript.new() as KingdomCityView
			_city.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_center.add_child(_city)
			_city.custom_minimum_size = Vector2(240.0, 280.0)
			_city.building_selected.connect(_building_dialog)
			_city.set_city(_view)
			_center.add_child(_button("建筑总览与空地建设", _buildings_dialog))
		"army":
			_center.add_child(_label("军队 · 城防与出征", 22))
			_battle = BattleScript.new() as KingdomBattleView
			_battle.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_battle.custom_minimum_size.y = 260.0
			_center.add_child(_battle)
			_battle.custom_minimum_size = Vector2(260.0, 540.0)
			_battle.action_requested.connect(_battle_action)
			_battle.set_battle(_present_battle(), _unit_dictionary())
			_center.add_child(_button("训练与驻军", _training_dialog))
			_center.add_child(_button("行军与驻扎部队", _marches_dialog))
		"generals", "reports":
			_center.add_child(_label("将领名册" if page == "generals" else "战报与战利品", 22))
			var scroll: ScrollContainer = ScrollContainer.new()
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_center.add_child(scroll)
			var content: VBoxContainer = VBoxContainer.new()
			content.name = "Content"
			content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(content)
	_render_detail()
	_update_page_content()

func _receive_snapshot(payload: Dictionary) -> void:
	_view = payload.get("view", {})
	_state = payload.get("state", {})
	for id: String in _resources:
		var amount: float = float(_view.get("res", {}).get(id, 0))
		var cap: float = float(_view.get("caps", {}).get(id, 0))
		var text: String = str(RES_NAMES[id]) + " " + _number(amount)
		if cap > 0:
			text += "\n上限 " + _number(cap)
		var label: Label = _resources[id]
		label.text = text
		label.modulate = Color("f2c578") if cap > 0 and amount > cap else Color.WHITE
	var objective: Dictionary = _view.get("objective", {})
	_objective_title.text = str(objective.get("title", "整备城池"))
	_objective_text.text = str(objective.get("description", "")) + "\n奖励 " + _cost(objective.get("reward", {}))
	_objective_button.text = "领取奖励" if objective.get("ready", false) else "查看目标"
	if _city != null:
		_city.set_city(_view)
	if _battle != null:
		_battle.set_battle(_present_battle(), _unit_dictionary())
	var signature: String = JSON.stringify([_view.get("buildings", []), _view.get("queues", {}), _view.get("marches", []), _view.get("reports", []), _view.get("generals", [])])
	if signature != _last_structure:
		_last_structure = signature
		_update_page_content()
		_render_detail()
	_smoke_snapshot = true
	_check_smoke()

func _receive_world(world: Dictionary) -> void:
	_world = world
	if _map != null:
		_map.set_world(world)
	_smoke_world = true
	_check_smoke()

func _check_smoke() -> void:
	if _smoke and _smoke_snapshot and _smoke_world:
		print("GODOT_SMOKE_OK canonical_revision=" + str(api.revision) + " tiles=" + str(_world.get("tiles", []).size()))
		get_tree().quit(0)

func _connection_changed(message: String, _connected: bool) -> void:
	_status.text = message
	_status.modulate = Color("aed1a9") if _connected else Color("e0b36e")

func _show_toast(message: String) -> void:
	_toast.text = message

func _number(value: float) -> String:
	if value >= 1000000.0:
		return "%.2f百万" % (value / 1000000.0)
	if value >= 10000.0:
		return "%.1f万" % (value / 10000.0)
	return str(int(value))

func _cost(cost: Dictionary) -> String:
	var pieces: PackedStringArray = []
	for id: String in cost:
		pieces.append(str(RES_NAMES.get(id, id)) + " " + _number(float(cost[id])))
	return " · ".join(pieces) if not pieces.is_empty() else "—"

func _remaining(end: float) -> String:
	var seconds: int = maxi(0, int(ceil((end - Time.get_unix_time_from_system() * 1000.0) / 1000.0)))
	if seconds >= 3600:
		return "%d时%02d分" % [seconds / 3600, (seconds % 3600) / 60]
	return "%d分%02d秒" % [seconds / 60, seconds % 60]

func _unit_dictionary() -> Dictionary:
	var units: Dictionary = {}
	for unit: Dictionary in _view.get("units", []):
		units[str(unit.id)] = {"name": unit.name, "range": unit.get("stats", {}).get("range", 0), "hp": unit.get("stats", {}).get("hp", 1)}
	return units

func _render_detail() -> void:
	_clear(_detail)
	if _page == "world" and not _selected.is_empty():
		_detail.add_child(_label(str(_selected.get("name", "目标")), 22))
		_detail.add_child(_label("坐标 %d,%d · 等级 %d" % [int(_selected.get("x", 0)), int(_selected.get("y", 0)), int(_selected.get("level", 0))], 14))
		_detail.add_child(_button("配兵出征", _dispatch_dialog.bind(_selected), bool(_selected.get("owned", false))))
		_detail.add_child(HSeparator.new())
	else:
		_detail.add_child(_label(str(_view.get("city", {}).get("name", "主城")), 22))
		_detail.add_child(_label("人口 %s / %s" % [_number(float(_view.get("population", 0))), _number(float(_view.get("maxPopulation", 0)))], 14))
		_detail.add_child(_label("民心 %s · 空闲 %s" % [_number(float(_view.get("morale", 0))), _number(float(_view.get("freePopulation", 0)))], 14))
	_detail.add_child(_label("建设与训练", 17, Color("c5b37b")))
	for kind: String in ["build", "train", "research"]:
		for queue: Dictionary in _view.get("queues", {}).get(kind, []):
			var label: Label = _label(_queue_name(queue, kind) + "\n" + _remaining(float(queue.get("end", 0))), 14)
			label.set_meta("queue_end", queue.get("end", 0))
			label.set_meta("queue_name", _queue_name(queue, kind))
			_detail.add_child(label)
	if _view.get("queues", {}).get("build", []).is_empty() and _view.get("queues", {}).get("train", []).is_empty():
		_detail.add_child(_label("暂无队列 · 城池待命", 14, Color("98aa9a")))
	_detail.add_child(HSeparator.new())
	_detail.add_child(_label("外出部队", 17, Color("c5b37b")))
	for march: Dictionary in _view.get("marches", []):
		var label: Label = _label(str(march.get("label", "部队")) + "\n" + _march_status(march), 14)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(label)
		if march.get("canStartBattle", false):
			_detail.add_child(_button("进入战斗", _start_march_battle.bind(march)))
		elif march.has("recallCommand"):
			_detail.add_child(_button("召回驻军", _send_record_command.bind(march.recallCommand)))

func _queue_name(queue: Dictionary, kind: String) -> String:
	var id: String = str(queue.get("id", ""))
	if kind == "train":
		return str(_unit_dictionary().get(id, {}).get("name", id)) + " ×" + str(queue.get("count", 0))
	for building: Dictionary in _view.get("buildings", []):
		if building.id == id:
			return str(building.name) + " → " + str(int(queue.get("level", 1))) + "级"
	return id + " → " + str(int(queue.get("level", 1))) + "级"

func _march_status(march: Dictionary) -> String:
	var status: String = str(march.get("status", "march"))
	if status == "battle":
		return "交战中 · " + str(int(march.get("count", 0))) + "人"
	if status == "stationed":
		return "驻扎 · " + str(march.get("count", 0)) + "人"
	if march.get("canStartBattle", false):
		return "已抵达 · 等待交战"
	return ("返城中 · " if status == "return" else "行进中 · ") + _remaining(float(march.get("arrive", 0)))

func _refresh_clock() -> void:
	for child: Node in _detail.get_children():
		if child is Label and child.has_meta("queue_end"):
			(child as Label).text = str(child.get_meta("queue_name")) + "\n" + _remaining(float(child.get_meta("queue_end")))

func _select_tile(tile: Dictionary) -> void:
	_selected = tile
	_render_detail()
	_show_toast(str(tile.get("name", "目标")) + " · 坐标 " + str(tile.get("x", 0)) + "," + str(tile.get("y", 0)))
	if size.x < 760.0:
		_dispatch_dialog(tile)

func _update_page_content() -> void:
	if _page not in ["generals", "reports"]:
		return
	var scroll: Node = _center.get_child(_center.get_child_count() - 1)
	var content: VBoxContainer = scroll.get_node("Content") as VBoxContainer
	_clear(content)
	if _page == "generals":
		content.add_child(_label("姓名                 等级        武勇       智谋       内政       忠诚", 15, Color("bbad7c")))
		for general: Dictionary in _view.get("generals", []):
			var row: HBoxContainer = HBoxContainer.new()
			content.add_child(row)
			var label: Label = _label(str(general.get("name", "将领")) + (" · 出征中" if general.get("busy", false) else " · 待命"), 17)
			label.custom_minimum_size.x = 190.0
			row.add_child(label)
			for key: String in ["level", "atk", "wis", "pol", "loyalty"]:
				var value: int = int(general.get(key, 0))
				var stat: Label = _label(str(value), 17)
				stat.custom_minimum_size.x = 70.0
				if key in ["atk", "wis", "pol"]:
					stat.modulate = Color("e7bc5c") if value >= 90 else Color("b49ce0") if value >= 80 else Color("81bfe0") if value >= 70 else Color.WHITE
				row.add_child(stat)
	else:
		var reports: Array = _view.get("reports", [])
		if reports.is_empty():
			content.add_child(_label("首次出征后，战报会记录战损、缴获与返程资源。", 17))
		for report: Dictionary in reports:
			var text: Label = _label(_report_title(report) + "\n" + str(int(report.get("round", 0))) + " 回合 · 损失 " + _army_text(report.get("lost", {})), 17)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(text)
			content.add_child(_button("查看战报", _report_dialog.bind(report)))

func _open_dialog(title: String, width: int = 600) -> VBoxContainer:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = AcceptDialog.new()
	_dialog.title = title
	_dialog.dialog_text = ""
	_dialog.min_size = Vector2i(mini(width, maxi(300, int(size.x) - 40)), mini(550, maxi(240, int(size.y) - 60)))
	add_child(_dialog)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(float(_dialog.min_size.x - 40), 260.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dialog.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_dialog.popup_centered()
	return content

func _building_dialog(id: String) -> void:
	var content: VBoxContainer = _open_dialog("建筑详情")
	var chosen_site: int = _city.selected_site() if _city != null else -1
	var found: bool = false
	for building: Dictionary in _view.get("buildings", []):
		if str(building.id) != id or chosen_site >= 0 and int(building.site) != chosen_site:
			continue
		found = true
		content.add_child(_label(str(building.name) + " · " + str(building.level) + "级", 23))
		content.add_child(_label("升级消耗\n" + _cost(building.get("cost", {}))))
		content.add_child(_label("时间 " + _remaining(Time.get_unix_time_from_system() * 1000.0 + float(building.get("seconds", 0)) * 1000.0)))
		var blocked: String = str(building.get("requirement", "")) if building.get("requirement") != null else ""
		if not blocked.is_empty():
			content.add_child(_label(blocked, 15, Color("e1b073")))
		content.add_child(_button("升级建筑", _command_close.bind("queueBuilding", [int(building.site), id]), not blocked.is_empty()))
	if found:
		return
	var empty_site: int = -1
	for slot: Dictionary in _view.get("buildingSlots", []):
		if slot.get("id") == null or str(slot.get("id", "")) == "":
			empty_site = int(slot.site)
			break
	for option: Dictionary in _view.get("buildOptions", []):
		if str(option.id) != id:
			continue
		content.add_child(_label(str(option.name) + " · 规划建筑", 23))
		content.add_child(_label("建造消耗\n" + _cost(option.get("cost", {}))))
		var blocked: String = "" if option.get("requirement") == null else str(option.get("requirement", ""))
		if not blocked.is_empty():
			content.add_child(_label(blocked, 15, Color("e1b073")))
		content.add_child(_button("开始建造", _command_close.bind("queueBuilding", [empty_site, id]), empty_site < 0 or not blocked.is_empty()))

func _buildings_dialog() -> void:
	var content: VBoxContainer = _open_dialog("城内建筑", 680)
	for building: Dictionary in _view.get("buildings", []):
		content.add_child(_button(str(building.name) + "  " + str(building.level) + "级", _building_dialog.bind(str(building.id))))
	for slot: Dictionary in _view.get("buildingSlots", []):
		if slot.get("id") != null and str(slot.get("id")) != "":
			continue
		content.add_child(_label("空地 " + str(int(slot.site) + 1), 17, Color("c5b37b")))
		for option: Dictionary in _view.get("buildOptions", []):
			var blocked: bool = option.get("requirement") != null and not str(option.get("requirement", "")).is_empty()
			content.add_child(_button(str(option.name) + " · " + _cost(option.get("cost", {})), _command_close.bind("queueBuilding", [int(slot.site), str(option.id)]), blocked))
		break

func _training_dialog() -> void:
	var content: VBoxContainer = _open_dialog("驻军与训练", 680)
	for unit: Dictionary in _view.get("units", []):
		var row: HBoxContainer = HBoxContainer.new()
		content.add_child(row)
		var label: Label = _label(str(unit.name) + "  ×" + str(unit.available), 17)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_button("训练", _train_unit_dialog.bind(unit), not bool(unit.get("unlocked", false))))

func _train_unit_dialog(unit: Dictionary) -> void:
	var content: VBoxContainer = _open_dialog("训练" + str(unit.name))
	content.add_child(_label(str(unit.get("role", "")), 17))
	content.add_child(_label("每名费用 " + _cost(unit.get("cost", {})), 15))
	var count: SpinBox = SpinBox.new()
	count.min_value = 1.0
	count.max_value = 100000.0
	count.value = 20.0
	content.add_child(count)
	content.add_child(_button("开始训练", func() -> void: _command_close("train", [str(unit.id), int(count.value)])))

func _dispatch_dialog(tile: Dictionary) -> void:
	if tile.get("owned", false):
		_show_toast("这是己方城池，可在城池列表切换")
		return
	var content: VBoxContainer = _open_dialog("出征 · " + str(tile.get("name", "目标")), 680)
	content.add_child(_label("选择将领与兵力，抵达后进入战斗。", 15))
	var general_picker: OptionButton = OptionButton.new()
	for general: Dictionary in _view.get("generals", []):
		if general.get("busy", false) or general.get("governor", false):
			continue
		general_picker.add_item(str(general.name))
		general_picker.set_item_metadata(general_picker.item_count - 1, str(general.id))
	content.add_child(general_picker)
	var choices: Dictionary = {}
	for unit: Dictionary in _view.get("units", []):
		if int(unit.available) <= 0:
			continue
		var row: HBoxContainer = HBoxContainer.new()
		content.add_child(row)
		var label: Label = _label(str(unit.name) + " · 可用 " + str(unit.available), 15)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var count: SpinBox = SpinBox.new()
		count.min_value = 0.0
		count.max_value = float(unit.available)
		count.value = float(unit.available)
		count.custom_minimum_size.x = 115.0
		row.add_child(count)
		choices[str(unit.id)] = count
	var mode: OptionButton = OptionButton.new()
	mode.add_item("掠夺")
	mode.add_item("占领")
	content.add_child(mode)
	var return_option: CheckBox = CheckBox.new()
	return_option.text = "占领后返回（不选则驻扎）"
	content.add_child(return_option)
	content.add_child(_button("派遣部队", func() -> void:
		if general_picker.item_count == 0:
			_show_toast("没有可出征将领")
			return
		var army: Dictionary = {}
		for id: String in choices:
			army[id] = int((choices[id] as SpinBox).value)
		_command_close("dispatch", [str(tile.id), str(general_picker.get_item_metadata(general_picker.selected)), army, "raid" if mode.selected == 0 else "occupy", return_option.button_pressed])))

func _marches_dialog() -> void:
	var content: VBoxContainer = _open_dialog("行军与驻扎部队", 680)
	for march: Dictionary in _view.get("marches", []):
		content.add_child(_label(str(march.get("label", "部队")) + "\n" + _march_status(march), 17))
		if march.get("canStartBattle", false):
			content.add_child(_button("进入战斗", _start_march_battle.bind(march)))
		elif march.has("recallCommand"):
			content.add_child(_button("召回", _send_record_command.bind(march.recallCommand)))
		elif march.get("status") == "march":
			content.add_child(_button("召回", _command_close.bind("recall", [str(march.get("node", ""))])))
	if _view.get("marches", []).is_empty():
		content.add_child(_label("暂无外出军队。城内训练后，在舆图选择目标出征。", 16))

func _start_march_battle(march: Dictionary) -> void:
	_pending_battle = true
	_send_record_command(march.get("selectCommand", {}))
	if is_instance_valid(_dialog):
		_dialog.hide()

func _command_completed(type: String, _payload: Dictionary) -> void:
	if type == "selectExpedition" and _pending_battle:
		_pending_battle = false
		api.command("startBattle")
		_show_page("army")
	else:
		_show_toast("操作已完成 · 进度已保存")

func _send_record_command(record: Dictionary) -> void:
	if record.is_empty():
		return
	api.command(str(record.type), record.get("args", []), str(record.get("sourceCity", "")))

func _battle_action(type: String, args: Array) -> void:
	api.command(type, args)

func _command_close(type: String, args: Array) -> void:
	api.command(type, args)
	if is_instance_valid(_dialog):
		_dialog.hide()

func _objective_action() -> void:
	var objective: Dictionary = _view.get("objective", {})
	if objective.get("ready", false) and not str(objective.get("action", "")).is_empty():
		api.command(str(objective.action), objective.get("args", []))
	else:
		_tasks_dialog()

func _tasks_dialog() -> void:
	var content: VBoxContainer = _open_dialog("当前任务")
	var objective: Dictionary = _view.get("objective", {})
	content.add_child(_label(str(objective.get("title", "整备城池")), 23))
	var description: Label = _label(str(objective.get("description", "")))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	content.add_child(_label("奖励 " + _cost(objective.get("reward", {})), 15))
	if objective.get("ready", false):
		content.add_child(_button("领取奖励", _command_close.bind(str(objective.get("action", "claimMission")), objective.get("args", []))))
	content.add_child(_button("前往城池建设", func() -> void: _dialog.hide(); _show_page("city")))
	content.add_child(_button("领取已解锁礼包", _command_close.bind("onboarding.claimAvailable", [])))
	content.add_child(_button("城外资源", _plots_dialog))
	content.add_child(_button("研究", _research_dialog))
	content.add_child(_button("宝物与物资", _inventory_dialog))

func _plots_dialog() -> void:
	var content: VBoxContainer = _open_dialog("城外资源", 700)
	for plot: Dictionary in _view.get("plots", []):
		if not plot.get("unlocked", false):
			continue
		if plot.get("id") != null and not str(plot.get("id", "")).is_empty():
			content.add_child(_button("%d号 %s · %d级 · %s" % [int(plot.index) + 1, str(plot.name), int(plot.level), _cost(plot.get("cost", {}))], _command_close.bind("developPlot", [int(plot.index), str(plot.id)]), plot.get("queue") != null))
		else:
			content.add_child(_label(str(int(plot.index) + 1) + "号空地"))
			for option: Dictionary in _view.get("plotOptions", []):
				content.add_child(_button(str(option.name), _command_close.bind("developPlot", [int(plot.index), str(option.id)])))

func _research_dialog() -> void:
	var content: VBoxContainer = _open_dialog("研究")
	for tech: Dictionary in _view.get("techs", []):
		content.add_child(_label(str(tech.name) + " · " + str(tech.level) + "级", 18))
		var reason: String = "" if tech.get("requirement") == null else str(tech.get("requirement", ""))
		content.add_child(_label(_cost(tech.get("cost", {})) + ("\n" + reason if not reason.is_empty() else ""), 14))
		content.add_child(_button("开始研究", _command_close.bind("research", [str(tech.id)]), not reason.is_empty()))
	content.add_child(_button("开启自动研究", _command_close.bind("setAutoResearch", [true])))
	content.add_child(_button("关闭自动研究", _command_close.bind("setAutoResearch", [false])))

func _inventory_dialog() -> void:
	var content: VBoxContainer = _open_dialog("宝物与物资")
	for item: Dictionary in _view.get("inventory", []):
		content.add_child(_label(str(item.name) + " ×" + str(item.count), 18))
		if item.get("speedup", false):
			for target: Dictionary in item.get("targets", []):
				content.add_child(_button("加速 " + str(target.name), _command_close.bind("useSpeedup", [str(item.id), str(target.key)])))
		elif not item.get("requiresGeneral", false) and not item.get("requiresText", false):
			content.add_child(_button("使用", _command_close.bind("useItem", [str(item.id)])))
		else:
			content.add_child(_label("这件宝物需在对应将领或城池中使用", 14, Color("b9b38a")))
	content.add_child(_button("领取已解锁礼包", _command_close.bind("onboarding.claimAvailable", [])))

func _report_dialog(report: Dictionary) -> void:
	var content: VBoxContainer = _open_dialog("战报", 740)
	content.add_child(_label(_report_title(report), 22))
	content.add_child(_label("交战 " + str(int(report.get("round", 0))) + " 回合 · 将领经验 +" + str(int(report.get("xp", 0)))))
	var received: Dictionary = {}
	var receipts: Dictionary = report.get("resourceReceipt", {})
	for kind: String in ["base", "bonus"]:
		var part: Dictionary = receipts.get(kind, {}).get("received", {})
		for id: String in part:
			received[id] = float(received.get(id, 0)) + float(part[id])
	for line: String in ["实际已入库：" + _cost(received), "永久损失：" + _army_text(report.get("lost", {})), "伤兵入营：" + _army_text(report.get("wounded", {})), "幸存部队：" + _army_text(report.get("back", {})), "俘虏士兵：" + _army_text(report.get("captures", {}))]:
		var label: Label = _label(line, 16)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(label)
	if bool(report.get("claimed", false)):
		content.add_child(_label("已占领目标，" + ("幸存部队驻扎当地。" if report.get("stationed", false) else "部队返回出发城。"), 16, Color("bdcc9e")))
	elif report.get("stationed", false):
		content.add_child(_label("部队驻扎当地；民心尚未归附。"))
	else:
		content.add_child(_label("幸存部队返回出发城。"))
	var failure: Variant = report.get("failure")
	if failure is Dictionary:
		var reasons: Dictionary = {"retreat": "主动撤退", "army": "我军损失殆尽", "gate": "未攻破城门", "enemy": "未击败全部守军", "gate_and_enemy": "城门与守军均未突破"}
		content.add_child(_label("败因：" + str(reasons.get(failure.get("reason", ""), "战线未能突破")), 16, Color("dfa481")))
		if bool(failure.get("outOfRange", false)):
			content.add_child(_label("仍有部队未进入射程；可调整兵种或前进命令。", 15))

func _report_title(report: Dictionary) -> String:
	var id: String = str(report.get("node", ""))
	return _node_name(id) + " · " + ("占领" if report.get("mode", "raid") == "occupy" else "掠夺") + ("胜利" if report.get("won", false) else "失利")

func _present_battle() -> Variant:
	var battle: Variant = _view.get("battle")
	if not battle is Dictionary:
		return null
	var display: Dictionary = battle.duplicate(true)
	display["nodeName"] = _node_name(str(display.get("node", "")))
	return display

func _node_name(id: String) -> String:
	var name: String = id
	for node: Dictionary in _view.get("nodes", []):
		if str(node.get("id", "")) == id:
			name = str(node.get("name", id))
			break
	if name == id:
		for tile: Dictionary in _world.get("tiles", []):
			if str(tile.get("id", "")) == id:
				name = str(tile.get("name", id))
				break
	return name

func _army_text(army: Dictionary) -> String:
	var names: Dictionary = _unit_dictionary()
	var parts: PackedStringArray = []
	for id: String in army:
		if int(army[id]) > 0:
			parts.append(str(names.get(id, {}).get("name", id)) + " " + str(int(army[id])))
	return "、".join(parts) if not parts.is_empty() else "无"

func _connection_dialog() -> void:
	var content: VBoxContainer = _open_dialog("连接规则服务")
	content.add_child(_label("本地试玩自动启动服务；网页试玩填写相同服务地址。", 15))
	var url: LineEdit = LineEdit.new()
	url.text = api.base_url
	content.add_child(url)
	var token_field: LineEdit = LineEdit.new()
	token_field.secret = true
	token_field.placeholder_text = "服务访问令牌"
	token_field.text = api.token
	content.add_child(token_field)
	content.add_child(_button("连接", func() -> void: api.connect_to(url.text, token_field.text); _dialog.hide()))
	content.add_child(_button("重试未确认操作 / 重连", func() -> void: api.retry_last(); _dialog.hide()))
	content.add_child(_label("试玩规则服务用于本地验证。正式共享世界将接入账号服务。", 14, Color("b9b38a")))

func _save_dialog() -> void:
	api.fetch_export()

func _show_export(snapshot: Dictionary) -> void:
	var content: VBoxContainer = _open_dialog("存档 · 导入与导出", 760)
	content.add_child(_label("进度自动保存。可复制 JSON，在原网页与新客户端之间导入。", 15))
	_save_text = TextEdit.new()
	_save_text.text = JSON.stringify(snapshot)
	_save_text.custom_minimum_size = Vector2(300.0, 230.0)
	_save_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.add_child(_save_text)
	content.add_child(_button("复制存档", func() -> void: DisplayServer.clipboard_set(_save_text.text); _show_toast("存档已复制")))
	content.add_child(_button("导入输入框中的存档", func() -> void:
		var parsed: Variant = JSON.parse_string(_save_text.text)
		if not parsed is Dictionary:
			_show_toast("存档 JSON 格式无效")
			return
		api.import_snapshot(parsed)
		_dialog.hide()))
	if not OS.has_feature("web"):
		content.add_child(_button("保存 JSON 文件", _save_file))
		content.add_child(_button("从 JSON 文件导入", _load_file))

func _save_file() -> void:
	var picker: FileDialog = FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray(["*.json ; 三国存档"])
	picker.current_file = "three-kingdoms-save.json"
	picker.size = Vector2i(750, 500)
	add_child(picker)
	picker.file_selected.connect(func(path: String) -> void:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_show_toast("无法写入存档文件")
		else:
			file.store_string(_save_text.text)
			_show_toast("存档已保存")
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered()

func _load_file() -> void:
	var picker: FileDialog = FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray(["*.json ; 三国存档"])
	picker.size = Vector2i(750, 500)
	add_child(picker)
	picker.file_selected.connect(func(path: String) -> void:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			api.import_snapshot(parsed)
			_dialog.hide()
		else:
			_show_toast("文件不是有效存档 JSON")
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered()
