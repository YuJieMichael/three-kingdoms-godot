class_name KingdomCityConstructionPanel
extends VBoxContainer

## Catalog and quotation share one Window. Only the host can submit a command.
signal choose_requested(id: String)
signal confirm_requested(id: String, quote: Dictionary)
signal upgrade_requested(id: String, site: int)
signal mode_changed(details: bool)

const CompareScript: Script = preload("res://src/city_capacity_compare.gd")
const CATEGORIES: Array[String] = ["民生", "军备", "科技", "全部"]

var site: int = -1
var source_city: String = ""
var category: String = "全部"
var only_available: bool = false
var details_open: bool = false
var shown_quote: Dictionary = {}
var _view: Dictionary = {}
var _uses: Dictionary = {}
var _texture_provider: Callable
var _cost_formatter: Callable
var _time_formatter: Callable
var _reason_provider: Callable
var _can_command: bool = false
var _tabs: HBoxContainer
var _tab_buttons: Dictionary = {}
var _available: CheckButton
var _catalog_scroll: ScrollContainer
var _catalog: VBoxContainer
var _grid: GridContainer
var _detail_scroll: ScrollContainer
var _detail: VBoxContainer
var _footer: VBoxContainer
var _confirm: Button
var _back: Button
var _status: Label
var _fixed_quote: Label
var _capacity_compare: KingdomCityCapacityCompare
var _catalog_position: int = 0
var _configured: bool = false
var _last_chosen_id: String = ""
var _restore_focus: bool = false
var _catalog_signature: String = ""

func configure(selected_site: int, city: String, view: Dictionary, uses: Dictionary, textures: Callable, costs: Callable, durations: Callable, reasons: Callable, can_command: bool) -> void:
	site = selected_site
	source_city = city
	_view = view.duplicate(true)
	_uses = uses
	_texture_provider = textures
	_cost_formatter = costs
	_time_formatter = durations
	_reason_provider = reasons
	_can_command = can_command
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_shell()
	_configured = true
	show_catalog(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _configured and is_instance_valid(_grid):
		_grid.columns = 2 if size.x >= 640.0 else 1

func _build_shell() -> void:
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	add_child(_tabs)
	for caption: String in CATEGORIES:
		var button: Button = Button.new()
		button.text = caption
		button.toggle_mode = true
		button.custom_minimum_size.y = 44.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = "UtilityButton"
		button.pressed.connect(_select_category.bind(caption))
		_tabs.add_child(button)
		_tab_buttons[caption] = button
	_available = CheckButton.new()
	_available.text = "当前可建"
	_available.custom_minimum_size.y = 44.0
	_available.toggled.connect(func(value: bool) -> void:
		only_available = value
		_catalog_position = 0
		_render_catalog())
	add_child(_available)
	_catalog_scroll = _scroll()
	add_child(_catalog_scroll)
	_catalog = VBoxContainer.new()
	_catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_scroll.add_child(_catalog)
	_detail_scroll = _scroll()
	add_child(_detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.add_child(_detail)
	_footer = VBoxContainer.new()
	add_child(_footer)
	_fixed_quote = _label("", 14, Color("d9bd7d"))
	_fixed_quote.set_meta("construction_fixed_quote", true)
	_footer.add_child(_fixed_quote)
	_status = _label("", 14, Color("e1b073"))
	_footer.add_child(_status)
	_confirm = _button("确认建设", func() -> void:
		if not shown_quote.is_empty():
			confirm_requested.emit(str(shown_quote.id), shown_quote.duplicate(true)))
	_confirm.theme_type_variation = "PrimaryButton"
	_footer.add_child(_confirm)
	_back = _button("返回建筑目录", func() -> void: show_catalog(true))
	_footer.add_child(_back)

func _scroll() -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 120.0
	return scroll

func _label(text: String, font_size: int = 14, color: Color = Color("c3bcaa")) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

func _button(text: String, callback: Callable) -> Button:
	var result: Button = Button.new()
	result.text = text
	result.custom_minimum_size.y = 44.0
	result.pressed.connect(callback)
	return result

func _thumbnail(id: String, dimensions: Vector2) -> TextureRect:
	var result: TextureRect = TextureRect.new()
	result.custom_minimum_size = dimensions
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.texture = _texture_provider.call(id) as Texture2D
	return result

func _select_category(value: String) -> void:
	category = value
	_catalog_position = 0
	_restore_focus = false
	_render_catalog()

func _group(id: String) -> String:
	if id in ["house", "market", "warehouse", "inn", "tavern", "embassy"]:
		return "民生"
	if id in ["barracks", "drill", "stable", "beacon", "wall"]:
		return "军备"
	return "科技"

func _remove_children(host: Node) -> void:
	for child: Node in host.get_children():
		host.remove_child(child)
		child.queue_free()

func _render_catalog() -> void:
	if not _configured:
		return
	for value: String in _tab_buttons:
		(_tab_buttons[value] as Button).set_pressed_no_signal(value == category)
	_available.set_pressed_no_signal(only_available)
	_catalog_signature = JSON.stringify([_view.get("buildOptions", []), _view.get("queueLimits", {}), _view.get("queues", {}).get("build", []).size()])
	_remove_children(_catalog)
	_grid = GridContainer.new()
	_grid.columns = 2 if size.x >= 640.0 else 1
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog.add_child(_grid)
	var visible_count: int = 0
	for option: Dictionary in _view.get("buildOptions", []):
		if category != "全部" and _group(str(option.id)) != category:
			continue
		if only_available and not str(_reason_provider.call(option)).is_empty():
			continue
		visible_count += 1
		_grid.add_child(_card(option))
	if visible_count == 0:
		_catalog.add_child(_label("当前筛选下没有可建项目。可关闭“当前可建”查看解锁条件。", 16))
	call_deferred("_restore_catalog_scroll")

func _card(option: Dictionary) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.set_meta("building_option_id", str(option.id))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows: VBoxContainer = VBoxContainer.new()
	card.add_child(rows)
	var header: HBoxContainer = HBoxContainer.new()
	rows.add_child(header)
	header.add_child(_thumbnail(str(option.id), Vector2(64.0, 66.0)))
	var identity: VBoxContainer = VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	identity.add_child(_label(str(option.name), 20, Color("f1ead9")))
	identity.add_child(_label(str(_uses.get(str(option.id), "发展城池所需设施"))))
	var cost: Label = _label(str(option.name) + " · " + str(_cost_formatter.call(option.get("cost", {}))))
	cost.set_meta("construction_cost_id", str(option.id))
	rows.add_child(cost)
	var reason: String = str(_reason_provider.call(option))
	var status: Label = _label("工期 " + str(_time_formatter.call(float(option.get("seconds", 0)))) + (" · " + reason if not reason.is_empty() else ""), 14, Color("e1b073") if not reason.is_empty() else Color("b2c9a4"))
	status.set_meta("construction_status_id", str(option.id))
	rows.add_child(status)
	rows.add_child(_button("选择" + str(option.name), func() -> void:
		_catalog_position = _catalog_scroll.scroll_vertical
		_last_chosen_id = str(option.id)
		choose_requested.emit(str(option.id))))
	return card

func show_catalog(restore_scroll: bool = true) -> void:
	details_open = false
	_tabs.visible = true
	_available.visible = true
	_catalog_scroll.visible = true
	_detail_scroll.visible = false
	_footer.visible = false
	_restore_focus = restore_scroll and not _last_chosen_id.is_empty()
	if not restore_scroll:
		_catalog_position = 0
	_render_catalog()
	mode_changed.emit(false)

func _restore_catalog_scroll() -> void:
	if not is_inside_tree():
		return
	var scene: SceneTree = get_tree()
	await scene.process_frame
	await scene.process_frame
	if not is_inside_tree() or details_open:
		return
	_catalog_scroll.scroll_vertical = _catalog_position
	if _restore_focus and not _last_chosen_id.is_empty():
		_restore_focus = false
		for card: Node in _grid.get_children():
			if str(card.get_meta("building_option_id", "")) == _last_chosen_id:
				for button: Node in card.find_children("*", "Button", true, false):
					(button as Button).grab_focus()
					return

func show_detail(option: Dictionary) -> void:
	if not details_open:
		_catalog_position = _catalog_scroll.scroll_vertical
	details_open = true
	shown_quote = option.duplicate(true)
	_tabs.visible = false
	_available.visible = false
	_catalog_scroll.visible = false
	_detail_scroll.visible = true
	_footer.visible = false
	_remove_children(_detail)
	_capacity_compare = null
	if str(option.id) != "wall":
		_detail.add_child(_thumbnail(str(option.id), Vector2(138.0, 120.0)))
	else:
		_detail.add_child(_label("木栅栏 → 石墙：升级完成后，城池四周围墙逐级加高。", 16))
	_detail.add_child(_label(str(option.name) + " · 1级", 22, Color("f1ead9")))
	_detail.add_child(_label(str(_uses.get(str(option.id), "发展城池所需设施")), 16))
	_detail.add_child(_label("建造消耗\n" + str(_cost_formatter.call(option.get("cost", {}))), 16))
	_detail.add_child(_label("工期 " + str(_time_formatter.call(float(option.get("seconds", 0)))), 15))
	var comparisons: Dictionary = _view.get("buildingComparisons", {})
	var comparison: Variant = comparisons.get(str(option.id))
	if str(option.id) in ["house", "barracks"] and comparison is Dictionary and _comparison_matches_city(comparison):
		var compare: KingdomCityCapacityCompare = CompareScript.new() as KingdomCityCapacityCompare
		_capacity_compare = compare
		_detail.add_child(compare)
		compare.configure(comparisons[str(option.id)], site, _cost_formatter, _time_formatter)
		compare.upgrade_requested.connect(func(id: String, selected: int) -> void: upgrade_requested.emit(id, selected))
	_confirm.text = "确认建设" + str(option.name)
	# A new wrapping label still has zero width until VBoxContainer sorts.
	# Seed its real available width before changing the text, so its transient
	# narrow minimum height cannot permanently enlarge the enclosing Window.
	_fixed_quote.size.x = maxf(1.0, size.x)
	_status.size.x = maxf(1.0, size.x)
	_fixed_quote.text = "消耗 " + str(_cost_formatter.call(shown_quote.get("cost", {}))) + "\n工期 " + str(_time_formatter.call(float(shown_quote.get("seconds", 0))))
	_detail_scroll.scroll_vertical = 0
	_sync_confirmation()
	_footer.visible = true
	mode_changed.emit(true)
	call_deferred("_focus_confirm_or_back")

func _focus_confirm_or_back() -> void:
	if is_inside_tree() and details_open:
		(_back if _confirm.disabled else _confirm).grab_focus()

func _sync_confirmation() -> void:
	if shown_quote.is_empty():
		return
	var current: Dictionary = {}
	for option: Dictionary in _view.get("buildOptions", []):
		if str(option.id) == str(shown_quote.id):
			current = option
			break
	var reason: String = "本城可建设的建筑已变化" if current.is_empty() else str(_reason_provider.call(current))
	if reason.is_empty() and not _can_command:
		reason = "请连接服务并等待上一项操作完成"
	_status.size.x = maxf(1.0, size.x)
	_status.text = reason
	_status.visible = not reason.is_empty()
	_confirm.disabled = not reason.is_empty()

func update_view(view: Dictionary, can_command: bool) -> void:
	var position: int = _catalog_scroll.scroll_vertical if not details_open else _catalog_position
	_view = view.duplicate(true)
	_can_command = can_command
	if details_open:
		_sync_confirmation()
		_refresh_capacity_comparison()
	elif _catalog_signature != JSON.stringify([_view.get("buildOptions", []), _view.get("queueLimits", {}), _view.get("queues", {}).get("build", []).size()]):
		_catalog_position = position
		_restore_focus = false
		_render_catalog()

func _refresh_capacity_comparison() -> void:
	if not is_instance_valid(_capacity_compare) or shown_quote.is_empty():
		return
	var comparison: Variant = _view.get("buildingComparisons", {}).get(str(shown_quote.id))
	if not comparison is Dictionary or not _comparison_matches_city(comparison):
		return
	var position: int = _detail_scroll.scroll_vertical
	if _capacity_compare.refresh(comparison):
		call_deferred("_restore_detail_scroll", position, _capacity_compare.get_instance_id())

func _comparison_matches_city(comparison: Dictionary) -> bool:
	return not source_city.is_empty() and str(_view.get("city", {}).get("id", "")) == source_city and str(comparison.get("cityId", "")) == source_city

func _restore_detail_scroll(position: int, compare_id: int) -> void:
	if not is_inside_tree():
		return
	var scene: SceneTree = get_tree()
	await scene.process_frame
	await scene.process_frame
	if is_inside_tree() and details_open and is_instance_valid(_capacity_compare) and _capacity_compare.get_instance_id() == compare_id:
		_detail_scroll.scroll_vertical = position
