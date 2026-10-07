extends SceneTree

## Exercise production scene selection through real dialogs; no network/player saves.
class ApiProbe extends "res://src/game_api.gd":
	var pending: bool = false
	var commands: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func _has_mutation() -> bool:
		return pending
	func command(type: String, args: Array = [], source: String = "") -> void:
		if connected and not pending:
			commands.append({"type": type, "args": args.duplicate(true)})
			pending = true

class ClientProbe extends "res://src/main.gd":
	func _ready() -> void:
		_smoke = true
		_initialize_inputs()
		theme = _make_theme()
		_build_shell()
		add_child(api)
		_show_page("city")
	func _check_smoke() -> void:
		pass

var checks: int = 0
var failures: int = 0
var client: ClientProbe
var api: ApiProbe
var view: Dictionary

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceHistoricTests-%d" % OS.get_process_id())
	root.gui_embed_subwindows = true
	create_timer(70).timeout.connect(func() -> void: push_error("Historical UI test timed out"); quit(1))
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _settle() -> void:
	for frame: int in 6:
		await process_frame

func _button(host: Node, label: String) -> Button:
	for child: Node in host.find_children("*", "Button", true, false):
		if (child as Button).text == label:
			return child as Button
	return null

func _plot_quote_label(realm: KingdomRealmDialog, id: String) -> Label:
	for child: Node in realm._content.find_children("*", "Label", true, false):
		if str(child.get_meta("plot_quote_id", "")) == id:
			return child as Label
	return null

func _dialog_labels() -> Array[Label]:
	var labels: Array[Label] = []
	for child: Node in client._dialog.find_children("*", "ScrollContainer", true, false):
		for descendant: Node in child.find_children("*", "Label", true, false):
			var label: Label = descendant as Label
			# Catalog and detail now retain separate scroll areas in one Window;
			# only the active panel's actual text bounds are player-visible.
			if label.is_visible_in_tree() and not labels.has(label):
				labels.append(label)
	return labels

func _label_text(labels: Array[Label], text: String) -> Label:
	for label: Label in labels:
		if label.text == text:
			return label
	return null

func _construction_cards() -> Dictionary:
	var cards: Dictionary = {}
	for child: Node in client._dialog.find_children("*", "PanelContainer", true, false):
		var id: String = str(child.get_meta("building_option_id", ""))
		if not id.is_empty():
			cards[id] = child
	return cards

func _check_phone_dialog(context: String) -> Array[Label]:
	var dialog: AcceptDialog = client._dialog
	_check(root.size.x == 390 and dialog.visible and dialog.position.x >= 0 and dialog.position.x + dialog.size.x <= 390, context + ": actual embedded window stays within 390px")
	var labels: Array[Label] = _dialog_labels()
	var rects_fit: bool = not labels.is_empty()
	var text_fits: bool = not labels.is_empty()
	for label: Label in labels:
		var rect: Rect2 = label.get_global_rect()
		rects_fit = rects_fit and rect.position.x >= -0.5 and rect.end.x <= float(dialog.size.x) + 0.5
		text_fits = text_fits and label.get_minimum_size().x <= label.size.x + 0.5 and label.size.x > 0.0
	_check(rects_fit, context + ": every content Label rect stays inside the dialog horizontally")
	_check(text_fits, context + ": rendered text minimum widths fit the allocated content rects")
	return labels

func _check_phone_construction_dialogs(node: String, prepared: Dictionary) -> void:
	# These are rule-produced quotes from a fresh game and a prepared second-tier
	# hall, rather than invented long text or altered prices used to force wrapping.
	var script: String = """const {createGameRuntime} = await import(process.argv[1]);
const {gameView} = await import(process.argv[2]);
const now = 1800000000000;
const runtime = createGameRuntime({now});
const game = runtime.Game;
const fresh = {state: structuredClone(game.state), view: gameView(game, now, runtime)};
game.state.cityLevels[14] = 2;
game.state.buildings.hall = 2;
game.save();
const upgraded = {state: structuredClone(game.state), view: gameView(game, now, runtime)};
process.stdout.write(JSON.stringify({fresh, upgraded}).replace(/[^\\x00-\\x7F]/g, c => String.fromCharCode(92, 117) + c.charCodeAt(0).toString(16).padStart(4, String.fromCharCode(48))));
"""
	var output: Array = []
	var runtime_uri: String = "file:///" + ProjectSettings.globalize_path("res://vendor/legacy/online/runtime.mjs").trim_prefix("/")
	var dto_uri: String = "file:///" + ProjectSettings.globalize_path("res://bridge/dto.mjs").trim_prefix("/")
	# ASCII JSON escapes preserve Chinese text across OS.execute pipe chunks.
	var result: int = OS.execute(node, ["--input-type=module", "-e", script, runtime_uri, dto_uri], output, true)
	_check(result == 0, "Fresh and upgraded hall phone fixtures use the canonical rules")
	if result != 0:
		push_error(str(output))
		return
	var snapshots: Dictionary = JSON.parse_string(str(output[0]))
	root.size = Vector2i(390, 844)
	for key: String in ["fresh", "upgraded"]:
		var snapshot: Dictionary = snapshots[key]
		client._receive_snapshot(snapshot)
		client._show_city_zone("inner")
		await _settle()
		var hall: Dictionary = snapshot.view.buildings.filter(func(row: Dictionary) -> bool: return str(row.id) == "hall")[0]
		client._building_dialog("hall", int(hall.site))
		await _settle()
		var labels: Array[Label] = _check_phone_dialog(key + " hall upgrade")
		_check(is_instance_valid(_label_text(labels, "%s · %d级" % [str(hall.name), int(hall.level)])), "Hall detail displays its canonical integer level on the phone")
		var cost: Label = _label_text(labels, "升级消耗\n" + client._cost(hall.cost))
		_check(is_instance_valid(cost) and cost.get_line_count() > 2, "Actual four-resource hall upgrade quote wraps beyond its explicit heading line")
		if hall.get("requirement") != null and not str(hall.requirement).is_empty():
			var requirement: Label = _label_text(labels, str(hall.requirement))
			_check(is_instance_valid(requirement) and requirement.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "Canonical upgraded hall prerequisite is visible in a wrapping content label")
		client._dialog.hide()
	client._receive_snapshot(snapshots.fresh)
	client._show_city_zone("inner")
	await _settle()
	client._empty_site_dialog(35)
	await _settle()
	var labels: Array[Label] = _check_phone_dialog("empty parcel 36 construction")
	_check(client._dialog.title == "空地 36 · 规划建设", "Phone chooser preserves the selected final actual parcel")
	var quotes_match: bool = true
	var cost_wraps: bool = false
	for option: Dictionary in snapshots.fresh.view.buildOptions:
		var cost: Label = _label_text(labels, str(option.name) + " · " + client._cost(option.cost))
		quotes_match = quotes_match and is_instance_valid(cost)
		if is_instance_valid(cost):
			cost_wraps = cost_wraps or cost.get_line_count() > 1
	var cards: Dictionary = _construction_cards()
	var option_ids: Array = snapshots.fresh.view.buildOptions.map(func(option: Dictionary) -> String: return str(option.id))
	var card_ids: Array = cards.keys()
	option_ids.sort()
	card_ids.sort()
	_check(quotes_match and card_ids == option_ids, "Grouped construction cards retain exactly the canonical options and each option's own cost")
	_check(cost_wraps, "Real four-resource construction costs wrap in the 390px chooser")
	var requirements_match: bool = true
	var requirement_wraps: bool = false
	for option: Dictionary in snapshots.fresh.view.buildOptions:
		var requirement: String = "" if option.get("requirement") == null else str(option.requirement)
		if requirement.is_empty():
			continue
		var found: bool = false
		for label: Label in labels:
			if label.text.begins_with("工期 ") and label.text.ends_with(" · " + requirement):
				found = true
				requirement_wraps = requirement_wraps or label.get_line_count() > 1
				break
		requirements_match = requirements_match and found
	_check(requirements_match and requirement_wraps, "Canonical option durations and long prerequisites remain visible as wrapped text")
	var before: int = api.commands.size()
	var window_id: int = client._dialog.get_instance_id()
	var choose_house: Button = _button(client._dialog, "选择民房")
	_check(is_instance_valid(choose_house), "The current canonical repeatable house can be selected from its card")
	if is_instance_valid(choose_house):
		choose_house.pressed.emit()
		await _settle()
		labels = _check_phone_dialog("parcel 36 house confirmation")
		var house: Dictionary = snapshots.fresh.view.buildOptions.filter(func(option: Dictionary) -> bool: return str(option.id) == "house")[0]
		_check(api.commands.size() == before and client._dialog.title == "地块 36 · 建设民房", "Selecting a building previews the exact final parcel without submitting construction")
		_check(client._dialog.get_instance_id() == window_id and client._city_construction_panel.details_open and client._city_construction_panel.site == 35, "Catalog-to-detail keeps the same native Window and actual selected parcel")
		_check(is_instance_valid(_label_text(labels, "建造消耗\n" + client._cost(house.cost))) and is_instance_valid(_label_text(labels, "工期 " + client._city_build_duration(float(house.seconds)))), "Phone confirmation displays that selected building's canonical cost and duration")
		_check(is_instance_valid(_button(client._dialog, "确认建设民房")), "Construction requires its separate explicit confirmation action")
		_button(client._dialog, "返回建筑目录").pressed.emit()
		await _settle()
		_check(api.commands.size() == before and client._dialog.title == "空地 36 · 规划建设", "Returning from confirmation cancels without spending or changing the selected parcel")
		_check(client._dialog.get_instance_id() == window_id and not client._city_construction_panel.details_open, "Returning from detail restores the catalog inside its original Window")
	client._dialog.hide()
	client._receive_snapshot(prepared)
	await _settle()

func _check_city_construction_guards(payload: Dictionary, site: int) -> void:
	var source: String = str(payload.view.city.id)
	var quote: Dictionary = payload.view.buildOptions.filter(func(option: Dictionary) -> bool: return str(option.id) == "house")[0].duplicate(true)
	var before: int = api.commands.size()
	# Each case represents a later snapshot arriving while the confirmation is
	# still visible. Only the current DTO may authorize the final command.
	for changed_field: String in ["cost", "seconds", "requirement", "affordable", "option_removed", "queue_full", "occupied", "source"]:
		var changed: Dictionary = payload.duplicate(true)
		var option: Dictionary = changed.view.buildOptions.filter(func(row: Dictionary) -> bool: return str(row.id) == "house")[0]
		match changed_field:
			"cost":
				option.cost.wood = float(option.cost.get("wood", 0)) + 1.0
			"seconds":
				option.seconds = float(option.seconds) + 1.0
			"requirement":
				option.requirement = "后续快照中的建设前置"
			"affordable":
				option.affordable = false
			"option_removed":
				changed.view.buildOptions = changed.view.buildOptions.filter(func(row: Dictionary) -> bool: return str(row.id) != "house")
			"queue_full":
				changed.view.queueLimits = {"build": 1}
				changed.view.queues.build = [{"site": 0, "id": "warehouse", "level": 1}]
			"occupied":
				for slot: Dictionary in changed.view.buildingSlots:
					if int(slot.site) == site:
						slot.id = "warehouse"
						slot.level = 1
			"source":
				changed.view.city.id = "new-confirmation-source"
		client._receive_snapshot(changed)
		client._confirm_city_construction(site, "house", source, quote)
		await _settle()
		_check(api.commands.size() == before, "A later %s snapshot cannot submit the older construction confirmation" % changed_field)
		if changed_field in ["cost", "seconds", "requirement"]:
			_check(client._dialog.title == "地块 %d · 建设民房" % (site + 1), "A changed quote opens fresh details for review rather than silently accepting new terms")
	client._receive_snapshot(payload)
	await _settle()
	api.pending = true
	client._confirm_city_construction(site, "house", source, quote)
	_check(api.commands.size() == before, "Pending mutation blocks a repeated confirmation")
	api.pending = false
	api.connected = false
	client._confirm_city_construction(site, "house", source, quote)
	_check(api.commands.size() == before, "A disconnected client cannot confirm construction")
	api.connected = true
	client._confirm_city_construction(15, "house", source, quote)
	_check(api.commands.size() == before, "Confirmation cannot target canonical reserved land")
	client._dialog.hide()
	client._receive_snapshot(payload)
	await _settle()

func _check_phone_hall_focus() -> void:
	var button: Button = _button(client._center_area, "定位官府")
	_check(is_instance_valid(button), "The phone's fixed city toolbar offers a hall locator")
	if not is_instance_valid(button):
		return
	var scroll: ScrollContainer = client._center.get_parent() as ScrollContainer
	_check(is_instance_valid(scroll), "The existing center content remains the direct child of its ScrollContainer")
	if not is_instance_valid(scroll):
		return
	var toolbar_rect: Rect2 = client._city_toolbar.get_global_rect()
	var before: int = api.commands.size()
	button.pressed.emit()
	await _settle()
	var hall: Dictionary = {}
	for parcel: Dictionary in client._city.parcel_draw_records():
		if str(parcel.id) == "hall":
			hall = parcel
			break
	_check(not hall.is_empty(), "Hall focus resolves the current canonical parcel instead of a fixed visual cell")
	if not hall.is_empty():
		var parcel: Rect2 = hall.rect
		var global_rect: Rect2 = Rect2(client._city.get_global_transform_with_canvas() * parcel.position, parcel.size)
		_check(scroll.scroll_vertical > 0 and scroll.get_global_rect().grow(1.0).encloses(global_rect) and client._city.selected_site() == int(hall.site), "The real phone hall is selected and its whole cell scrolls into view")
	_check(client._city_toolbar.get_global_rect() == toolbar_rect and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(toolbar_rect), "City actions stay visible above scrolling content on the phone")
	_check(api.commands.size() == before, "Locating the hall does not upgrade, build or mutate the game")
	await _capture("rts-city-hall-focused-fixture-390")
	scroll.scroll_vertical = 0
	await _settle()

func _capture_folder() -> String:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = "res://production/qa/evidence/story-016/"
	for index: int in range(arguments.size()):
		if arguments[index].begins_with("--capture-folder="):
			folder = arguments[index].trim_prefix("--capture-folder=")
		elif arguments[index] == "--capture-folder" and index + 1 < arguments.size():
			folder = arguments[index + 1]
	return folder.trim_suffix("/") + "/"

func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder: String = _capture_folder()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(root.get_texture().get_image().save_png(folder + name + ".png") == OK, "Capture saved")

func _run() -> void:
	var output: Array = []
	var node: String = OS.get_environment("TK_NODE")
	_check(not node.is_empty(), "Canonical fixture requires TK_NODE")
	if node.is_empty():
		quit(1)
		return
	var result: int = OS.execute(node, [ProjectSettings.globalize_path("res://tests/helpers/historic-city-view.mjs")], output)
	_check(result == 0, "Prepared canonical city fixture loads")
	if result != 0:
		quit(1)
		return
	var payload: Dictionary = JSON.parse_string(str(output[0]))
	view = payload.view
	client = ClientProbe.new()
	api = ApiProbe.new()
	api.connected = true
	client.api = api
	client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(client)
	client._receive_snapshot(payload)
	client._receive_world(payload.worldSample)
	for width: int in [1280, 390]:
		root.size = Vector2i(width, 1400 if width == 1280 else 844)
		client._show_city_zone("inner")
		await _settle()
		_check(client._city != null and client._suburb == null, "Inner tab opens city scene")
		_check(client._shell_margin.get_combined_minimum_size().x <= width, "City shell fits viewport")
		_check(_button(client._center_area, "城务") != null and _button(client._center_area, "市场交易") == null, "Scene precedes folded city affairs")
		if width == 390:
			_check(client._city._hit_boxes.values().all(func(rect: Rect2) -> bool: return rect.size.x >= 44.0 and rect.size.y >= 44.0), "Phone city parcels preserve a 44px tap target")
		await _capture("rts-city-developed-fixture-%d" % width)
		if width == 390:
			await _check_phone_hall_focus()
		client._show_city_zone("outer")
		await _settle()
		_check(client._suburb != null and client._city == null, "Outer tab opens geographic plots scene")
		_check(client._shell_margin.get_combined_minimum_size().x <= width, "Outer shell fits viewport")
		await _capture("rts-suburb-developed-fixture-%d" % width)
		client._suburb.plot_selected.emit(2)
		await _settle()
		_check(client._realm.visible and client._realm._selected_plot == 2, "Scene opens management for exact plot index")
		await _capture("rts-plot-detail-fixture-%d" % width)
		client._realm.hide()
	await _check_phone_construction_dialogs(node, payload)
	root.size = Vector2i(1280, 1400)
	client._show_city_zone("inner")
	await _settle()
	var houses: Array = view.buildings.filter(func(row: Dictionary) -> bool: return row.id == "house")
	_check(houses.size() >= 2, "Fixture has independent duplicate buildings")
	var selected_site: int = int(houses.back().site)
	client._city.select_building("house", selected_site)
	client._city.building_selected.emit("house")
	await _settle()
	_button(client._dialog, "升级建筑").pressed.emit()
	_check(api.commands.size() == 1 and api.commands[0] == {"type": "queueBuilding", "args": [selected_site, "house"]}, "Duplicate house upgrade uses clicked site's actual identity")
	api.pending = false
	var empties: Array = view.buildingSlots.filter(func(row: Dictionary) -> bool: return row.get("id") == null)
	var empty_site: int = int(empties.back().site)
	client._city.empty_site_selected.emit(empty_site)
	await _settle()
	_button(client._dialog, "选择民房").pressed.emit()
	await _settle()
	_check(api.commands.size() == 1 and client._dialog.title == "地块 %d · 建设民房" % (empty_site + 1), "Selecting a construction card is a preview and retains the clicked site's identity")
	_button(client._dialog, "确认建设民房").pressed.emit()
	_check(api.commands.size() == 2 and api.commands[1] == {"type": "queueBuilding", "args": [empty_site, "house"]}, "Empty parcel never silently substitutes the first vacant slot")
	api.pending = false
	await _check_city_construction_guards(payload, empty_site)
	client._queue_city_building(15, "house", true, str(view.city.id))
	_check(api.commands.size() == 2, "Reserved government plot cannot be built")
	client._queue_city_building(empty_site, "house", true, "other-city")
	_check(api.commands.size() == 2, "Stale building dialog cannot target another city")
	client._queue_city_building(selected_site, "house", false, str(view.city.id), 1)
	_check(api.commands.size() == 2, "A completed upgrade invalidates the older displayed construction tier")
	client._building_dialog("market")
	_check(_button(client._dialog, "市场交易") != null, "An objective route ignores stale selected house identity")
	client._show_plot(27)
	await _settle()
	var realm: KingdomRealmDialog = client._realm
	_check(not realm._templates_open and _button(realm, "确认替换布局") == null, "Plot templates are initially folded")
	_button(realm, "展开地块图").pressed.emit()
	await _settle()
	var land: KingdomSuburbView
	for child: Node in realm._content.get_children():
		if child is KingdomSuburbView:
			land = child as KingdomSuburbView
	_check(is_instance_valid(land), "Management can expand the geographic plot selector")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = (land._hit_boxes[27] as Rect2).get_center()
	land._gui_input(click)
	await _settle()
	_check(realm._selected_plot == 27 and _button(realm, "建设农田") != null, "Real plot pointer selection safely rebuilds its focused controls")
	realm._toggle_plot_map()
	await _settle()
	var changed: Dictionary = view.duplicate(true)
	changed.plots.reverse()
	realm.update_view(changed)
	await _settle()
	_check(realm._selected_plot == 27, "Reordered DTO retains real plot index selection")
	for row: Dictionary in changed.plots:
		if int(row.index) == 27:
			row.cost = {"gold": 987654321}
			row.seconds = 987654321
			row.requirement = "空地默认农田投影不能用于其他用途"
	realm.update_view(changed)
	await _settle()
	var option_ids: Array[String] = []
	for option: Dictionary in changed.get("plotOptions", []):
		var id: String = str(option.id)
		option_ids.append(id)
		_check(option.has("cost") and option.has("seconds") and option.has("requirement") and option.has("affordable"), "Each empty-land purpose has its own canonical first-level quote")
		var label: Label = _plot_quote_label(realm, id)
		_check(is_instance_valid(label), "Every empty-land purpose displays a quote label")
		if is_instance_valid(label):
			_check(label.text.contains(str(option.name) + " · 1级") and label.text.contains("工期 " + realm._duration(float(option.seconds))) and label.text.contains("费用 " + realm._cost(option.cost)), "Empty-land quote displays this type's first-level cost and duration")
			_check(not label.text.contains("987654321") and not label.text.contains("空地默认农田"), "Empty-land options never borrow the parcel's default farm projection")
		var unmet_requirement: bool = option.get("requirement") != null and not str(option.requirement).is_empty()
		_check(_button(realm, "建设" + str(option.name)).disabled == (unmet_requirement or not bool(option.affordable)), "Each empty-land purpose uses its own canonical prerequisite and payment gate")
	option_ids.sort()
	_check(option_ids == ["farm", "lumber", "mine", "quarry"], "All four canonical empty-land purposes have independent displayed quotes")
	var queue_poll: Dictionary = changed.duplicate(true)
	queue_poll.queueLimits = {"build": 2}
	queue_poll.queues = {"build": [{"end": 1800000001000}, {"end": 1800000002000}]}
	var farm_button: Button = _button(realm, "建设农田")
	var farm_label: Label = _plot_quote_label(realm, "farm")
	realm.update_view(queue_poll)
	await _settle()
	_check(_button(realm, "建设农田") == farm_button and farm_button.disabled and farm_button.tooltip_text == "建造队正在忙碌" and farm_label.text.contains("建造队正在忙碌"), "A canonical full construction queue updates the existing empty-land quote and action gate")
	_check(queue_poll.plotOptions.all(func(option: Dictionary) -> bool: return _button(realm, "建设" + str(option.name)).disabled), "A full canonical construction queue blocks all four empty-land purposes")
	farm_button.pressed.emit()
	_check(api.commands.size() == 2, "Queue capacity prevents construction even with affordable first-level quotes")
	queue_poll.queues.build.pop_back()
	realm.update_view(queue_poll)
	await _settle()
	_check(_button(realm, "建设农田") == farm_button and not farm_button.disabled and not farm_label.text.contains("建造队正在忙碌"), "When canonical construction capacity returns, the live quote and existing action become available")
	realm.update_view(changed)
	await _settle()
	var quote_poll: Dictionary = changed.duplicate(true)
	var timber: Dictionary
	for option: Dictionary in quote_poll.plotOptions:
		if str(option.id) == "lumber":
			timber = option
	var timber_label: Label = _plot_quote_label(realm, "lumber")
	timber.cost = {"wood": 654321, "iron": 72}
	timber.seconds = 122
	timber.requirement = "官府未达到木场建设前置"
	timber.affordable = false
	realm.update_view(quote_poll)
	await _settle()
	_check(_plot_quote_label(realm, "lumber") == timber_label and timber_label.text.contains("木材 654321") and timber_label.text.contains("铁锭 72") and timber_label.text.contains("工期 2分02秒") and timber_label.text.contains(str(timber.requirement)), "Quote polls update cost, duration and prerequisite in the existing type-specific label")
	_check(_button(realm, "建设" + str(timber.name)).disabled and _button(realm, "建设" + str(timber.name)).tooltip_text == str(timber.requirement), "A changed type-specific prerequisite disables its construction action")
	_button(realm, "建设" + str(timber.name)).pressed.emit()
	_check(api.commands.size() == 2, "Unmet canonical plot-option requirements reject programmatic construction")
	timber.requirement = null
	realm.update_view(quote_poll)
	await _settle()
	_check(_button(realm, "建设" + str(timber.name)).disabled and timber_label.text.contains("资源不足"), "An unaffordable quote remains visibly blocked after its prerequisite is satisfied")
	_button(realm, "建设" + str(timber.name)).pressed.emit()
	_check(api.commands.size() == 2, "Insufficient resources cannot submit construction for that plot type")
	for option: Dictionary in quote_poll.plotOptions:
		if str(option.id) == "quarry":
			option.erase("cost")
			var quarry_name: String = str(option.name)
			realm.update_view(quote_poll)
			await _settle()
			_check(_button(realm, "建设" + quarry_name).disabled and _plot_quote_label(realm, "quarry").text.contains("正在读取"), "A missing option quote is unavailable rather than replaced with a default farm cost")
	realm.update_view(changed)
	await _settle()
	_button(realm, "建设农田").pressed.emit()
	_button(realm, "建设农田").pressed.emit()
	_check(api.commands.size() == 3 and api.commands.back() == {"type": "developPlot", "args": [27, "farm"]}, "Selected plot sends exact index once while pending")
	api.pending = false
	realm.acknowledge_command(true, false)
	for row: Dictionary in changed.plots:
		if int(row.index) == 27:
			row.queue = {"end": 1800000030000}
	realm.update_view(changed)
	await _settle()
	_check(_button(realm, "建设农田").disabled, "Queue polling blocks construction on already queued empty ground")
	_button(realm, "建设农田").pressed.emit()
	_check(api.commands.size() == 3, "Disabled queued plot rejects programmatic button emit")
	realm.set_command_state(false, false)
	_check(_button(realm, "建设农田").disabled, "Disconnected plot management is disabled")
	changed.realmManagement.currentCity = "city-other"
	changed.city.id = "city-other"
	realm.update_view(changed)
	await _settle()
	_check(realm._selected_plot != 27, "Switching cities clears old plot context")
	realm.hide()
	client._mode_changed("private")
	await _settle()
	_check(client._city_zone == "inner" and not is_instance_valid(client._realm), "Actor changes clear private plot context")
	client.queue_free()
	await _settle()
	print("HISTORIC_STRUCTURE_CLIENT_CHECKS=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
