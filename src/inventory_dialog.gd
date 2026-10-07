class_name KingdomInventoryDialog
extends AcceptDialog

signal command_requested(type: String, args: Array)
signal route_requested(route: String, target: String)

const ItemArt: Script = preload("res://src/item_art.gd")
var _column: VBoxContainer
var _footer: VBoxContainer
var _shop_body: BoxContainer
var _wallet: Label
var _category_tabs: HFlowContainer
var _item_visuals: Dictionary = {}
var _view: Dictionary = {}
var _section: String = "inventory"
var _connected: bool = true
var _pending: bool = false
var _error_message: String = ""
var _scroll: ScrollContainer
var _content: VBoxContainer
var _status: Label
var _category: OptionButton
var _search: LineEdit
var _available: CheckBox
var _items: OptionButton
var _grid_scroll: ScrollContainer
var _item_grid: GridContainer
var _empty_notice: Label
var _item_buttons: Dictionary = {}
var _detail: VBoxContainer
var _description: Label
var _quote: Label
var _target: OptionButton
var _text: LineEdit
var _count: SpinBox
var _apply: Button
var _route: Button
var _selected_item: String = ""
var _selected_category: String = ""
var _target_id: String = ""
var _drafts: Dictionary = {}
var _item_signature: String = ""
var _target_signature: String = ""
var _updating: bool = false


func _ready() -> void:
	dialog_text = ""
	get_ok_button().text = "关闭"
	wrap_controls = false
	_column = VBoxContainer.new()
	add_child(_column)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(_scroll)
	_footer = VBoxContainer.new()
	_column.add_child(_footer)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	get_tree().root.size_changed.connect(_fit_window)
	_build()


func show_section(section: String, view: Dictionary) -> void:
	_remember()
	_view = view
	_section = "shop" if section == "shop" else "inventory"
	_error_message = ""
	_build()
	_fit_window()
	popup_centered()


func update_view(view: Dictionary) -> void:
	_view = view
	if is_instance_valid(_content):
		_sync_items()
		_refresh()


func select_item(item_id: String, target_id: String = "") -> bool:
	if _section != "inventory" or not is_instance_valid(_items): return false
	var found: bool = false
	for item: Dictionary in _data().get("items", []):
		if str(item.get("id", "")) == item_id and int(item.get("count", 0)) > 0:
			found = true
			break
	if not found: return false
	_remember()
	# Old editors must not overwrite the newly selected item's saved draft.
	_target = null
	_text = null
	_count = null
	_selected_item = item_id
	_selected_category = ""
	_category.select(0)
	_search.text = ""
	if not target_id.is_empty():
		var draft: Dictionary = _drafts.get(item_id, {}).duplicate()
		draft.target = target_id
		_drafts[item_id] = draft
	_item_signature = ""
	_sync_items(true)
	_build_detail()
	return true


func set_command_state(connected: bool, pending: bool) -> void:
	_connected = connected
	_pending = pending
	_refresh()


func show_error(message: String) -> void:
	_error_message = message
	_refresh()


func acknowledge_command(connected: bool, pending: bool) -> void:
	_error_message = ""
	set_command_state(connected, pending)


func _data() -> Dictionary:
	return _view.get("inventoryManagement", {})


func _item() -> Dictionary:
	for item: Dictionary in _data().get("items", []):
		if str(item.id) == _selected_item: return item
	return {}


func _label(text: String, font_size: int = 15) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 44
	button.pressed.connect(callback)
	return button


func _fit_window() -> void:
	var available: Vector2 = Vector2(get_tree().root.size)
	if get_parent() is Control: available = (get_parent() as Control).size
	var width: int = mini(1080 if _section == "shop" else 680, maxi(280, int(available.x) - 40))
	var height: int = mini(850 if _section == "shop" else 650, maxi(340, int(available.y) - 80))
	_scroll.custom_minimum_size = Vector2(width - 48, 120)
	min_size = Vector2i(280, 340)
	size = Vector2i(width, height)
	if is_instance_valid(_shop_body):
		_shop_body.vertical = width < 800
		_detail.custom_minimum_size.x = 0 if _shop_body.vertical else 300
		_detail.size_flags_horizontal = Control.SIZE_FILL
		_category.visible = width < 800
		_category_tabs.visible = width >= 800
	_fit_item_grid()
	_column.position = Vector2(14, 14)
	_column.size = Vector2(width - 28, height - 74)
	position = Vector2i((available - Vector2(size)) / 2.0)
	call_deferred("_fit_item_grid")


func _build() -> void:
	if not is_instance_valid(_content): return
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	# show_section() remembers the old editors before rebuilding. Detaching
	# them does not invalidate their references until queue_free() flushes;
	# never let item synchronization wire focus or refresh those old controls.
	for child: Node in _footer.get_children():
		_footer.remove_child(child)
		child.queue_free()
	_footer.visible = _section == "shop"
	_shop_body = null
	_item_visuals.clear()
	_description = null
	_quote = null
	_target = null
	_text = null
	_count = null
	_apply = null
	_route = null
	_item_buttons.clear()
	title = "宝物背包" if _section == "inventory" else "商城"
	var tabs: GridContainer = GridContainer.new()
	tabs.columns = 2
	_content.add_child(tabs)
	for section: String in ["inventory", "shop"]:
		var button: Button = _button("宝物背包" if section == "inventory" else "商城", func() -> void: show_section(section, _view))
		button.disabled = section == _section
		tabs.add_child(button)
	_wallet = _label("", 18)
	_wallet.visible = _section == "shop"
	_content.add_child(_wallet)
	_status = _label("", 13)
	_content.add_child(_status)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索宝物名称"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_search)
	_search.text_changed.connect(func(_value: String) -> void: _sync_items(true))
	_category = OptionButton.new()
	_category.clip_text = true
	_category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category.add_item("全部分类")
	_category.set_item_metadata(0, "")
	for category: String in _data().get("categories", []):
		_category.add_item(category)
		_category.set_item_metadata(_category.item_count - 1, category)
		if category == _selected_category: _category.select(_category.item_count - 1)
	_content.add_child(_category)
	_category.visible = _section != "shop"
	_category_tabs = HFlowContainer.new()
	_category_tabs.visible = _section == "shop"
	_content.add_child(_category_tabs)
	for index: int in range(_category.item_count):
		var category_button: Button = _button(_category.get_item_text(index), _select_shop_category.bind(index))
		category_button.custom_minimum_size.x = 88
		_category_tabs.add_child(category_button)
	_category.item_selected.connect(func(index: int) -> void:
		_selected_category = str(_category.get_item_metadata(index))
		_sync_items(true))
	_available = CheckBox.new()
	_available.text = "仅显示已开放出售的宝物"
	_available.button_pressed = true
	_available.visible = _section == "shop"
	_content.add_child(_available)
	_available.toggled.connect(func(_value: bool) -> void: _sync_items(true))
	_items = OptionButton.new()
	_items.clip_text = true
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.custom_minimum_size.y = 44
	# Both sections use one hidden ID selection model and visible icon tiles.
	_items.visible = false
	_items.focus_mode = Control.FOCUS_NONE
	_content.add_child(_items)
	_items.item_selected.connect(func(index: int) -> void:
		_choose_item(str(_items.get_item_metadata(index))))
	_empty_notice = _label("暂无已持有宝物；领取礼包或战斗缴获后会出现在这里。", 14)
	_empty_notice.visible = false
	_content.add_child(_empty_notice)
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_scroll.follow_focus = true
	_grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body: Node = _content
	if _section == "shop":
		_shop_body = BoxContainer.new()
		_shop_body.add_theme_constant_override("separation", 16)
		_content.add_child(_shop_body)
		body = _shop_body
	body.add_child(_grid_scroll)
	_item_grid = GridContainer.new()
	_item_grid.columns = 2
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_grid.visible = true
	_item_grid.add_theme_constant_override("h_separation", 8)
	_item_grid.add_theme_constant_override("v_separation", 8)
	_grid_scroll.add_child(_item_grid)
	_item_grid.resized.connect(_fit_item_grid)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_detail)
	_item_signature = ""
	_sync_items()
	_build_detail()
	call_deferred("_fit_window")


func _select_shop_category(index: int) -> void:
	_category.select(index)
	_selected_category = str(_category.get_item_metadata(index))
	_sync_items(true)


func _sync_items(filter_changed: bool = false) -> void:
	if not is_instance_valid(_items): return
	var rows: Array[Dictionary] = []
	for item: Dictionary in _data().get("items", []):
		if not _selected_category.is_empty() and str(item.get("category", "")) != _selected_category: continue
		if not _search.text.strip_edges().is_empty() and not str(item.name).to_lower().contains(_search.text.strip_edges().to_lower()): continue
		if _section == "shop" and _available.button_pressed and (not item.get("supported", false) or item.get("rewardOnly", false)): continue
		if _section == "inventory" and int(item.get("count", 0)) < 1: continue
		rows.append(item)
	var ids: Array = []
	for item: Dictionary in rows: ids.append(item.id)
	var signature: String = JSON.stringify(ids)
	if signature == _item_signature and not filter_changed:
		_refresh_item_tiles()
		return
	_remember()
	_item_signature = signature
	_items.clear()
	var found: bool = false
	for item: Dictionary in rows:
		_items.add_item(str(item.name))
		_items.set_item_metadata(_items.item_count - 1, item.id)
		if str(item.id) == _selected_item:
			_items.select(_items.item_count - 1)
			found = true
	if not found:
		_selected_item = str(_items.get_item_metadata(0)) if _items.item_count > 0 else ""
		_build_detail()
	_rebuild_item_tiles(rows)
	_refresh()


func _choose_item(item_id: String) -> void:
	if item_id == _selected_item:
		_refresh_item_tiles()
		call_deferred("_show_mobile_item_detail")
		return
	var selected_index: int = -1
	for index: int in range(_items.item_count):
		if str(_items.get_item_metadata(index)) == item_id:
			selected_index = index
			break
	# A snapshot can remove an item before a queued click is delivered.
	if selected_index < 0: return
	_remember()
	_selected_item = item_id
	_items.select(selected_index)
	_build_detail()
	_refresh_item_tiles()
	call_deferred("_show_mobile_item_detail")

func _show_mobile_item_detail() -> void:
	if _section == "shop" and size.x < 800 and visible:
		_scroll.ensure_control_visible(_detail)


func _rebuild_item_tiles(rows: Array[Dictionary]) -> void:
	if not is_instance_valid(_item_grid): return
	var focus_id: String = ""
	var focus: Control = get_viewport().gui_get_focus_owner()
	for item_id: String in _item_buttons:
		if focus == _item_buttons[item_id]:
			focus_id = item_id
			break
	var scroll_position: int = _scroll.scroll_vertical
	var grid_position: int = _grid_scroll.scroll_vertical
	for child: Node in _item_grid.get_children():
		_item_grid.remove_child(child)
		child.queue_free()
	_item_buttons.clear()
	_item_visuals.clear()
	for item: Dictionary in rows:
		var item_id: String = str(item.id)
		var button: Button = _button("", _choose_item.bind(item_id))
		button.custom_minimum_size = Vector2(112, 196 if _section == "shop" else 132)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		_item_grid.add_child(button)
		_item_buttons[item_id] = button
		var card: VBoxContainer = VBoxContainer.new()
		button.add_child(card)
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.offset_left = 8
		card.offset_top = 6
		card.offset_right = -8
		card.offset_bottom = -6
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var art: TextureRect = TextureRect.new()
		art.texture = ItemArt.texture(item_id)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size.y = 60
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)
		var name_label: Label = _label(str(item.name), 14)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.max_lines_visible = 2
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_label)
		var price_label: Label = _label("", 14)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_label.add_theme_color_override("font_color", Color("e7c77d"))
		price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(price_label)
		var hint: Label = _label(str(item.get("description", "")), 13)
		hint.max_lines_visible = 2
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hint.visible = _section == "shop"
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hint)
		_item_visuals[item_id] = {"price": price_label, "name": name_label}
	_empty_notice.visible = rows.is_empty()
	_grid_scroll.visible = not rows.is_empty()
	if _empty_notice.visible:
		_empty_notice.text = "没有符合筛选的商品。" if _section == "shop" else "没有符合筛选的已持有宝物。"
	_refresh_item_tiles()
	_fit_item_grid()
	_scroll.set_deferred("scroll_vertical", scroll_position)
	_grid_scroll.set_deferred("scroll_vertical", grid_position)
	if not focus_id.is_empty():
		var target: Control = _item_buttons.get(focus_id, _item_buttons.get(_selected_item, _category))
		target.call_deferred("grab_focus")


func _refresh_item_tiles() -> void:
	for item: Dictionary in _data().get("items", []):
		var item_id: String = str(item.get("id", ""))
		if not _item_buttons.has(item_id): continue
		var button: Button = _item_buttons[item_id]
		var selected: bool = item_id == _selected_item
		var visuals: Dictionary = _item_visuals.get(item_id, {})
		if not visuals.is_empty():
			(visuals.name as Label).text = ("已选 · " if selected else "") + str(item.get("name", item_id))
			(visuals.price as Label).text = "%d 元宝 / 件 · 持有 %d" % [int(item.get("price", 0)), int(item.get("count", 0))] if _section == "shop" else "持有 %d" % int(item.get("count", 0))
		button.tooltip_text = "%s · 持有 %d\n%s\n选择只查看详情；使用须在下方确认。" % [str(item.get("name", item_id)), int(item.get("count", 0)), str(item.get("description", ""))]
		button.theme_type_variation = "PrimaryButton" if selected else "UtilityButton"
		button.set_pressed_no_signal(selected)
	_wire_item_focus()


func _fit_item_grid() -> void:
	if not is_instance_valid(_item_grid): return
	var width: float = float(size.x - 60 - (316 if _section == "shop" and size.x >= 800 else 0))
	_item_grid.columns = 3 if width >= 580.0 else 2
	# A large collection must not push the selected item's confirmation below
	# dozens of rows. The grid has its own scroll area and follows keyboard focus.
	var row_count: int = ceili(float(_item_buttons.size()) / float(_item_grid.columns))
	_grid_scroll.custom_minimum_size.y = minf(float(row_count * (204 if _section == "shop" else 140) - 8), 440.0 if _section == "shop" else 256.0) if row_count > 0 else 0.0
	_wire_item_focus()


func _wire_item_focus() -> void:
	var filter_focus: Control = _search if _section == "shop" else _category
	if not is_instance_valid(_item_grid) or not _item_grid.is_inside_tree() or _item_grid.is_queued_for_deletion(): return
	if not is_instance_valid(filter_focus) or not filter_focus.is_inside_tree() or filter_focus.is_queued_for_deletion(): return
	# A filter or the last item's consumption can remove every tile. Clear
	# paths to detached tiles so normal traversal still reaches the editor/close.
	filter_focus.focus_next = NodePath()
	filter_focus.focus_neighbor_bottom = NodePath()
	if _item_buttons.is_empty(): return
	var buttons: Array[Node] = _item_grid.get_children()
	var columns: int = _item_grid.columns
	var detail_focus: Control = get_ok_button()
	for candidate: Control in [_target, _text, _apply, _route]:
		if is_instance_valid(candidate) and candidate.is_inside_tree() and not candidate.is_queued_for_deletion() and candidate.visible and candidate.focus_mode != Control.FOCUS_NONE and not (candidate is BaseButton and (candidate as BaseButton).disabled):
			detail_focus = candidate
			break
	filter_focus.focus_next = buttons[0].get_path()
	filter_focus.focus_neighbor_bottom = buttons[0].get_path()
	for index: int in range(buttons.size()):
		var button: Button = buttons[index] as Button
		button.focus_previous = filter_focus.get_path() if index == 0 else buttons[index - 1].get_path()
		button.focus_next = detail_focus.get_path() if index == buttons.size() - 1 else buttons[index + 1].get_path()
		button.focus_neighbor_left = buttons[index - 1].get_path() if index % columns > 0 else button.get_path()
		button.focus_neighbor_right = buttons[index + 1].get_path() if index % columns < columns - 1 and index + 1 < buttons.size() else button.get_path()
		button.focus_neighbor_top = buttons[index - columns].get_path() if index >= columns else filter_focus.get_path()
		button.focus_neighbor_bottom = buttons[index + columns].get_path() if index + columns < buttons.size() else detail_focus.get_path()


func _remember() -> void:
	if _selected_item.is_empty(): return
	var draft: Dictionary = _drafts.get(_selected_item, {}).duplicate()
	if is_instance_valid(_text): draft.text = _text.text
	if is_instance_valid(_count): draft.count = _count.get_line_edit().text
	if is_instance_valid(_target): draft.target = _target_id
	_drafts[_selected_item] = draft


func _build_detail() -> void:
	if not is_instance_valid(_detail): return
	_detail.visible = not _item().is_empty()
	_footer.visible = _section == "shop" and not _item().is_empty()
	for child: Node in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	_target = null
	_text = null
	_count = null
	_apply = null
	_route = null
	_target_signature = ""
	var picture: TextureRect = TextureRect.new()
	picture.texture = ItemArt.texture(_selected_item)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size.y = 86
	_detail.add_child(picture)
	_description = _label("")
	_detail.add_child(_description)
	var item: Dictionary = _item()
	var draft: Dictionary = _drafts.get(_selected_item, {})
	var editor: VBoxContainer = _footer if _section == "shop" else _detail
	if _section == "shop":
		for child: Node in _footer.get_children():
			_footer.remove_child(child)
			child.queue_free()
		_count = SpinBox.new()
		_count.min_value = 1
		_count.max_value = 99
		_count.step = 1
		_count.rounded = true
		_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var quantity_row: HBoxContainer = HBoxContainer.new()
		editor.add_child(quantity_row)
		quantity_row.add_child(_label("购买数量", 14))
		quantity_row.add_child(_count)
		if draft.has("count"): _count.get_line_edit().text = str(draft.count)
		_count.value_changed.connect(func(_value: float) -> void: _refresh())
		_count.get_line_edit().text_changed.connect(func(_value: String) -> void: _refresh())
	else:
		var kind: String = str(item.get("use", {}).get("targetKind", "none"))
		if kind in ["hero", "speedup", "slot", "choice"]:
			_detail.add_child(_label("选择调拨方向" if kind == "choice" else "选择将领" if kind == "hero" else "选择加速队列" if kind == "speedup" else "选择装备部位", 14))
			_target = OptionButton.new()
			_target.clip_text = true
			_target.custom_minimum_size.y = 44
			_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_detail.add_child(_target)
			_target_id = str(draft.get("target", ""))
			_target.item_selected.connect(func(index: int) -> void: _target_id = str(_target.get_item_metadata(index)); _refresh())
			_sync_targets()
		elif kind == "text":
			_text = LineEdit.new()
			_text.placeholder_text = "输入新名字（最多 %d 字）" % int(item.get("use", {}).get("maxLength", 0))
			_text.text = str(draft.get("text", ""))
			_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_detail.add_child(_text)
			_text.text_changed.connect(func(_value: String) -> void: _refresh())
	_quote = _label("")
	editor.add_child(_quote)
	_apply = _button("购买" if _section == "shop" else "使用宝物", _submit)
	editor.add_child(_apply)
	_route = _button("前往对应功能", _navigate)
	editor.add_child(_route)
	_refresh()


func _sync_targets() -> void:
	if not is_instance_valid(_target): return
	var rows: Array = _item().get("use", {}).get("targets", [])
	var ids: Array = []
	for row: Dictionary in rows: ids.append(str(row.get("id", row.get("key", ""))))
	var signature: String = JSON.stringify(ids)
	if signature == _target_signature: return
	_target_signature = signature
	_target.clear()
	var found: bool = false
	for row: Dictionary in rows:
		var id: String = str(row.get("id", row.get("key", "")))
		_target.add_item(str(row.get("name", id)))
		_target.set_item_metadata(_target.item_count - 1, id)
		if id == _target_id:
			_target.select(_target.item_count - 1)
			found = true
	if not found and not _target_id.is_empty():
		_target.add_item("原目标已结束或已离开，请重新选择")
		_target.set_item_metadata(_target.item_count - 1, _target_id)
		_target.select(_target.item_count - 1)
		_target.set_item_disabled(_target.item_count - 1, true)
	elif not found:
		_target_id = str(_target.get_item_metadata(0)) if _target.item_count > 0 else ""


func _target_quote() -> Dictionary:
	for row: Dictionary in _item().get("use", {}).get("targets", []):
		if str(row.get("id", row.get("key", ""))) == _target_id: return row
	return {"reason": "原目标已结束或已离开，请重新选择"}


func _quantity() -> int:
	if not is_instance_valid(_count): return 0
	var raw: String = _count.get_line_edit().text.strip_edges()
	var amount: int = roundi(float(raw)) if raw.is_valid_float() else int(_count.value)
	return clampi(amount, 0, int(_item().get("purchase", {}).get("limit", 0)))


func _action() -> Dictionary:
	var item: Dictionary = _item()
	if item.is_empty(): return {"reason": "暂无所选宝物"}
	if _section == "shop":
		var quantity: int = _quantity()
		var reason: String = str(item.get("purchase", {}).get("reason", ""))
		if reason.is_empty() and quantity < 1: reason = "请选择购买数量"
		return {"type": str(item.get("buyType", "buyItem")), "args": [_selected_item, quantity], "reason": reason}
	var use: Dictionary = item.get("use", {})
	var reason: String = str(use.get("reason", ""))
	var kind: String = str(use.get("targetKind", "none"))
	if reason.is_empty() and kind in ["hero", "speedup", "slot", "choice"]: reason = str(_target_quote().get("reason", ""))
	if str(item.get("effect", "")) == "supplyBundle":
		return {"type": str(item.get("openType", "supplies.open")), "args": [_selected_item, _target_id] if kind == "choice" else [_selected_item], "reason": reason}
	if kind == "text":
		var text: String = _text.text.strip_edges() if is_instance_valid(_text) else ""
		if reason.is_empty() and (text.is_empty() or text.length() > int(use.get("maxLength", 0))): reason = "名称长度不合适"
		return {"type": "useItem", "args": [_selected_item, "", text], "reason": reason}
	if str(item.get("effect", "")) in ["jewelBox", "equipmentBox"]:
		return {"type": "onboarding.openItem", "args": [_selected_item, _target_id] if kind == "slot" else [_selected_item], "reason": reason}
	if kind == "speedup": return {"type": "useSpeedup", "args": [_selected_item, _target_id], "reason": reason}
	return {"type": "useItem", "args": [_selected_item, _target_id] if kind == "hero" else [_selected_item], "reason": reason}


func _seconds(milliseconds: Variant) -> String:
	return "%s 秒" % maxi(0, ceili(float(milliseconds) / 1000.0))


func _refresh() -> void:
	if _updating or not is_instance_valid(_status): return
	_updating = true
	_status.text = _error_message if not _error_message.is_empty() else "正在结算，请稍候…" if _pending else "请先连接规则服务" if not _connected else "操作确认后自动保存"
	_wallet.text = "商城宝物 · 持有元宝 %d" % int(_data().get("gems", 0))
	for index: int in range(_category_tabs.get_child_count()):
		(_category_tabs.get_child(index) as Button).theme_type_variation = "PrimaryButton" if index == _category.selected else "UtilityButton"
	_status.modulate = Color("e7bc72") if not _error_message.is_empty() else Color.WHITE
	_sync_targets()
	var item: Dictionary = _item()
	if is_instance_valid(_description):
		_description.text = "%s · 持有 %d\n%s" % [item.get("name", "暂无宝物"), int(item.get("count", 0)), item.get("description", "")]
	if is_instance_valid(_quote):
		var details: PackedStringArray = []
		if _section == "shop":
			var purchase: Dictionary = item.get("purchase", {})
			var quantity: int = _quantity()
			var costs: Array = purchase.get("costs", [])
			details.append("持有元宝 %d · 本次 %d 件 / 元宝 ×%d\n当前可买上限 %d" % [int(_data().get("gems", 0)), quantity, int(costs[quantity - 1]) if quantity > 0 and quantity <= costs.size() else 0, int(purchase.get("limit", 0))])
			if purchase.get("remaining") != null: details.append(("本存档限购剩余 %d / %d" if str(purchase.get("period", "")) == "save" else "该种金砖今日剩余 %d / %d") % [int(purchase.remaining), int(purchase.get("dailyLimit", 0))])
		else:
			var target: Dictionary = _target_quote()
			if str(item.get("use", {}).get("targetKind", "")) == "choice": details.append("本次选择：" + str(target.get("name", "请选择方向")))
			if str(item.get("use", {}).get("targetKind", "")) == "speedup" and target.has("quote"):
				var q: Dictionary = target.quote
				details.append("等待 %s · 原工作时间 %s\n使用后剩余 %s — %s%s" % [_seconds(q.get("waitMs", 0)), _seconds(q.get("workMs", 0)), _seconds(q.get("afterMinMs", 0)), _seconds(q.get("afterMaxMs", 0)), "\n超出工作时间的加速会消耗" if q.get("overflow", false) else ""])
			if item.get("effect") == "heroReset" and target.get("consume") != null: details.append("本次消耗洗髓丹 ×%d" % int(target.consume))
			var opened: Dictionary = _data().get("lastOpen") if _data().get("lastOpen") is Dictionary else {}
			if not opened.is_empty(): details.append("最近开箱：%s ×%d" % [opened.get("name", ""), int(opened.get("count", 1))])
		var action: Dictionary = _action()
		if not str(action.get("reason", "")).is_empty(): details.append(str(action.reason))
		_quote.text = "\n".join(details)
		_apply.disabled = not _connected or _pending or not str(action.get("reason", "")).is_empty()
		_apply.text = "购买 · %s 件" % _quantity() if _section == "shop" else "预览开包" if str(item.get("effect", "")) == "supplyBundle" else "开启盒子" if str(item.get("effect", "")) in ["jewelBox", "equipmentBox"] else "使用宝物"
		_apply.tooltip_text = str(action.get("reason", ""))
		var route: Dictionary = item.get("use", {}).get("route") if item.get("use", {}).get("route") is Dictionary else {}
		_route.visible = _section == "inventory" and not route.is_empty()
		_route.text = str(route.get("label", "前往对应功能"))
		_route.disabled = _pending
	_updating = false
	_refresh_item_tiles()


func _submit() -> void:
	if not _connected or _pending: return
	var action: Dictionary = _action()
	if not str(action.get("reason", "")).is_empty():
		show_error(str(action.reason))
		return
	if _section == "shop":
		_count.value = _quantity()
		_count.get_line_edit().text = str(int(action.args[1]))
	if str(action.get("type", "")).begins_with("supplies."):
		_confirm_supply(action)
		return
	_commit_action(action)


func _confirm_supply(action: Dictionary) -> void:
	var source: String = str(_view.get("city", {}).get("id", ""))
	var fingerprint: String = JSON.stringify(action)
	var confirmation: ConfirmationDialog = ConfirmationDialog.new()
	confirmation.title = "确认购买军需" if _section == "shop" else "确认使用军需"
	confirmation.dialog_text = _description.text + "\n" + _quote.text + "\n" + ("购买后收入背包，可稍后开包。" if _section == "shop" else "本次消耗1包；奖励完整收入当前城池及共用道具库存。")
	confirmation.dialog_autowrap = true
	confirmation.exclusive = true
	confirmation.min_size = Vector2i(280, 240)
	add_child(confirmation)
	confirmation.confirmed.connect(func() -> void:
		if not _connected or _pending or source != str(_view.get("city", {}).get("id", "")) or JSON.stringify(_action()) != fingerprint:
			show_error("城池、包裹、方向或购买条件已变化，请重新预览。")
		else:
			_commit_action(action)
		confirmation.queue_free())
	confirmation.canceled.connect(confirmation.queue_free)
	confirmation.popup_centered(Vector2i(mini(580, maxi(280, int(get_tree().root.size.x) - 48)), mini(500, maxi(260, int(get_tree().root.size.y) - 100))))


func _commit_action(action: Dictionary) -> void:
	_remember()
	_error_message = ""
	_pending = true
	_refresh()
	command_requested.emit(str(action.type), action.get("args", []))


func _navigate() -> void:
	if _pending: return
	var route: Dictionary = _item().get("use", {}).get("route") if _item().get("use", {}).get("route") is Dictionary else {}
	if not route.is_empty(): route_requested.emit(str(route.route), str(route.get("target", "")))
