extends SceneTree

## Exercise the production Window, current rule quotes, touch layout and comparison routes.
class ApiProbe extends "res://src/game_api.gd":
	var pending: bool = false
	var commands: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func _has_mutation() -> bool:
		return pending
	func command(kind: String, args: Array = [], source: String = "") -> void:
		if connected and not pending:
			commands.append({"type": kind, "args": args.duplicate(true), "source": source})
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

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceConstructionPanelTests-%d" % OS.get_process_id())
	root.gui_embed_subwindows = true
	create_timer(70).timeout.connect(func() -> void: push_error("Construction panel test timed out"); quit(1))
	call_deferred("_run")

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func _settle() -> void:
	for frame: int in 8:
		await process_frame

func _button(host: Node, text: String) -> Button:
	for child: Node in host.find_children("*", "Button", true, false):
		if (child as Button).text == text and (child as Button).is_visible_in_tree():
			return child as Button
	return null

func _run() -> void:
	var node: String = OS.get_environment("TK_NODE")
	_check(not node.is_empty(), "Use the same bundled Node as the canonical bridge")
	if node.is_empty():
		quit(1)
		return
	var script: String = """const {createGameRuntime}=await import(process.argv[1]);const {gameView}=await import(process.argv[2]);
const now=1800000000000,runtime=createGameRuntime({now}),g=runtime.Game;
g.state.cityLayout[0]='house';g.state.cityLevels[0]=1;g.state.buildings.house=1;
g.state.cityLayout[1]='barracks';g.state.cityLevels[1]=1;g.state.buildings.barracks=1;
g.state.cityLevels[14]=3;g.state.buildings.hall=3;g.state.population=g.maxPop();g.save();
const idle={serverTime:now,state:structuredClone(g.state),view:gameView(g,now,runtime)};
const unit=Object.keys(g.units).find(id=>g.unitUnlocked(id));const error=g.train(unit,1);if(error)throw new Error(error);
const active={serverTime:now,state:structuredClone(g.state),view:gameView(g,now,runtime)};
const completedRuntime=createGameRuntime({now,snapshot:idle.state}),completedGame=completedRuntime.Game;
const buildError=completedGame.queueBuilding(2,'house');if(buildError)throw new Error(buildError);
const build=completedGame.state.buildQueue.find(row=>row.site===2);if(!build)throw new Error('No real house construction');
const completedTime=build.end+1;completedGame.tick(completedTime,false);completedGame.save();
if(completedGame.state.cityLevels[2]!==1)throw new Error('House did not finish');
const completed={serverTime:completedTime,state:structuredClone(completedGame.state),view:gameView(completedGame,completedTime,completedRuntime)};
process.stdout.write(JSON.stringify({idle,active,completed}).replace(/[^\\x00-\\x7F]/g,c=>String.fromCharCode(92,117)+c.charCodeAt(0).toString(16).padStart(4,String.fromCharCode(48))));"""
	var output: Array = []
	var runtime_uri: String = "file:///" + ProjectSettings.globalize_path("res://vendor/legacy/online/runtime.mjs").trim_prefix("/")
	var dto_uri: String = "file:///" + ProjectSettings.globalize_path("res://bridge/dto.mjs").trim_prefix("/")
	var result: int = OS.execute(node, ["--input-type=module", "-e", script, runtime_uri, dto_uri], output, true)
	_check(result == 0, "Idle and active snapshots are projected by the canonical runtime")
	if result != 0:
		push_error(str(output))
		quit(1)
		return
	var fixtures: Dictionary = JSON.parse_string(str(output[0]))
	root.size = Vector2i(390, 844)
	client = ClientProbe.new()
	api = ApiProbe.new()
	api.connected = true
	client.api = api
	client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(client)
	client._receive_snapshot(fixtures.idle)
	await _settle()
	_check(not client._activity_bar.visible and client._city_military_button.visible, "Idle city folds empty military counters into an accessible entry")
	_check(client._city_queue_button.visible and not client._city_queue_button.disabled, "Construction has an independent visible queue entry")
	_check(not client._compact_objective_text.visible and client._compact_objective_expand.visible, "Phone city starts with one expandable objective")
	_check(not client._resources.food.text.contains("\n") and client._resource_buttons.food.custom_minimum_size.y >= 44.0, "One-line phone resources retain usable touch targets and their detail entry")
	client._compact_objective_expand.pressed.emit()
	await _settle()
	var expanded_objective: Label = client._compact_objective_text
	var objective: Dictionary = client._current_objective()
	_check(expanded_objective.is_visible_in_tree() and expanded_objective.max_lines_visible == -1 and expanded_objective.size.y > 0.0 and expanded_objective.get_visible_line_count() > 0 and expanded_objective.get_visible_line_count() == expanded_objective.get_line_count() and expanded_objective.text.contains(str(objective.get("description", ""))) and expanded_objective.text.contains("奖励 " + client._reward_text(objective)) and client._compact_objective_expand.text == "收起", "Clicking Expand renders every objective description and reward line with a readable Collapse control")
	_check(absf(client._compact_objective_button.size.y - 44.0) <= 0.5 and absf(client._compact_growth_button.size.y - 44.0) <= 0.5 and absf(client._compact_objective_expand.size.y - 44.0) <= 0.5, "Expanding a multi-line objective keeps Go, Growth and Collapse as complete 44px buttons")
	client._city_queue_button.pressed.emit()
	await _settle()
	_check(fixtures.idle.view.queues.build.is_empty() and client._dialog.title == "本城施工队列" and client._dialog.position.x >= 0 and client._dialog.position.y >= 0 and client._dialog.position.x + client._dialog.size.x <= root.size.x and client._dialog.position.y + client._dialog.size.y <= root.size.y, "Clicking the empty construction queue fits the entire actual Window inside the 390px phone viewport")
	var queue_close: Button = client._dialog.get_ok_button()
	var queue_close_rect: Rect2 = queue_close.get_global_rect()
	_check(queue_close.is_visible_in_tree() and queue_close.text == "关闭" and queue_close_rect.position.x >= 0.0 and queue_close_rect.position.y >= 0.0 and queue_close_rect.end.x <= float(client._dialog.size.x) + 1.0 and queue_close_rect.end.y <= float(client._dialog.size.y) + 1.0, "The queue's real Close target is fully visible within the phone Window")
	queue_close.pressed.emit()
	await _settle()
	_check(not client._dialog.visible and api.commands.is_empty(), "The visible Close target dismisses the queue without mutating progress")
	client._empty_site_dialog(35)
	await _settle()
	var panel: KingdomCityConstructionPanel = client._city_construction_panel
	var window_id: int = client._dialog.get_instance_id()
	_check(panel.site == 35 and panel.category == "全部", "Chooser starts with the exact final canonical site and all categories")
	_button(panel, "军备").pressed.emit()
	await _settle()
	_check(panel.category == "军备" and panel._grid.get_child_count() > 0, "Military category remains accessible on the phone")
	panel._available.button_pressed = true
	await _settle()
	var available_only: bool = true
	for card: Node in panel._grid.get_children():
		var option: Dictionary = client._city_build_option(str(card.get_meta("building_option_id", "")))
		available_only = available_only and client._city_build_reason(option).is_empty()
	_check(available_only, "Available filter cannot display an option blocked by the current authoritative quotation")
	panel._available.button_pressed = false
	_button(panel, "科技").pressed.emit()
	await _settle()
	panel._catalog_scroll.scroll_vertical = 100
	await _settle()
	var saved_scroll: int = panel._catalog_scroll.scroll_vertical
	print("CONSTRUCTION_CATALOG_BEFORE window=%s panel_min=%s catalog_min=%s detail_min=%s v_modes=%s/%s content_min=%s detail_content_min=%s" % [str(client._dialog.size), str(panel.get_combined_minimum_size()), str(panel._catalog_scroll.get_combined_minimum_size()), str(panel._detail_scroll.get_combined_minimum_size()), str(panel._catalog_scroll.vertical_scroll_mode), str(panel._detail_scroll.vertical_scroll_mode), str(panel._catalog.get_combined_minimum_size()), str(panel._detail.get_combined_minimum_size())])
	_button(panel, "选择书院").pressed.emit()
	await _settle()
	_check(client._dialog.get_instance_id() == window_id and api.commands.is_empty(), "Selecting a catalog item updates details in the same Window without a mutation")
	_check(client._dialog.position.x >= 0 and client._dialog.position.y >= 0 and client._dialog.position.x + client._dialog.size.x <= root.size.x and client._dialog.position.y + client._dialog.size.y <= root.size.y, "Showing the fixed quotation cannot enlarge the Window beyond the actual phone viewport")
	_check(not panel._detail_scroll.is_ancestor_of(panel._confirm) and panel._footer.visible, "Confirmation is outside the scrolling details")
	_check(not panel._detail_scroll.is_ancestor_of(panel._fixed_quote) and panel._fixed_quote.is_visible_in_tree(), "The authoritative cost and duration remain outside the scrolling details with confirmation")
	var academy: Dictionary = client._city_build_option("academy")
	_check(panel._fixed_quote.text.contains(client._cost(academy.cost)) and panel._fixed_quote.text.contains(client._city_build_duration(float(academy.seconds))), "Fixed quotation displays the selected academy's actual canonical cost and duration")
	var quote_rect: Rect2 = panel._fixed_quote.get_global_rect()
	_check(quote_rect.position.x >= 0.0 and quote_rect.position.y >= 0.0 and quote_rect.end.x <= float(client._dialog.size.x) + 1.0 and quote_rect.end.y <= float(client._dialog.size.y) + 1.0 and panel._fixed_quote.get_minimum_size().x <= panel._fixed_quote.size.x + 0.5, "The complete wrapping fixed quotation fits the actual phone Window")
	var confirm_rect: Rect2 = panel._confirm.get_global_rect()
	print("CONSTRUCTION_ACADEMY_DETAIL window=%s panel_min=%s catalog_min=%s detail_min=%s content_min=%s detail_content_min=%s footer_min=%s" % [str(client._dialog.size), str(panel.get_combined_minimum_size()), str(panel._catalog_scroll.get_combined_minimum_size()), str(panel._detail_scroll.get_combined_minimum_size()), str(panel._catalog.get_combined_minimum_size()), str(panel._detail.get_combined_minimum_size()), str(panel._footer.get_combined_minimum_size())])
	_check(confirm_rect.position.y >= 0.0 and confirm_rect.end.y <= float(client._dialog.size.y) + 1.0 and confirm_rect.end.x <= float(client._dialog.size.x) + 1.0, "The complete 44px confirmation target fits the actual phone Window")
	_button(panel, "返回建筑目录").pressed.emit()
	await _settle()
	print("CONSTRUCTION_CATALOG_RETURN saved=%d current=%d cached=%d max=%s page=%s window=%s panel=%s category=%s filtered=%s same_window=%s focus=%s" % [saved_scroll, panel._catalog_scroll.scroll_vertical, panel._catalog_position, str(panel._catalog_scroll.get_v_scroll_bar().max_value), str(panel._catalog_scroll.get_v_scroll_bar().page), str(client._dialog.size), str(panel.size), panel.category, str(panel.only_available), str(client._dialog.get_instance_id() == window_id), str(client._dialog.gui_get_focus_owner())])
	_check(client._dialog.get_instance_id() == window_id and panel.category == "科技" and not panel.only_available and absi(panel._catalog_scroll.scroll_vertical - saved_scroll) <= 1, "Returning preserves the same Window, category, filter and real catalog scroll offset")
	_button(panel, "民生").pressed.emit()
	await _settle()
	_button(panel, "选择民房").pressed.emit()
	await _settle()
	var compare: KingdomCityCapacityCompare
	for child: Node in panel._detail.get_children():
		if child is KingdomCityCapacityCompare:
			compare = child as KingdomCityCapacityCompare
	_check(is_instance_valid(compare) and not compare._body.visible, "New house details include a folded authoritative new-versus-upgrade comparison")
	if is_instance_valid(compare):
		compare._toggle.pressed.emit()
		await _settle()
		_check(compare._body.visible and compare._selected_site == 35 and compare._comparison == fixtures.idle.view.buildingComparisons.house, "Comparison uses the actual current city DTO while retaining the player's chosen new site")
		panel._detail_scroll.scroll_vertical = ceili(panel._detail_scroll.get_v_scroll_bar().max_value)
		await _settle()
		quote_rect = panel._fixed_quote.get_global_rect()
		confirm_rect = panel._confirm.get_global_rect()
		print("CONSTRUCTION_DETAIL_STICKY window=%s panel=%s quote=%s quote_min=%s visible=%s confirm=%s footer=%s detail=%s max=%s page=%s scroll=%d" % [str(client._dialog.size), str(panel.size), str(quote_rect), str(panel._fixed_quote.get_minimum_size()), str(panel._fixed_quote.is_visible_in_tree()), str(confirm_rect), str(panel._footer.get_global_rect()), str(panel._detail_scroll.get_global_rect()), str(panel._detail_scroll.get_v_scroll_bar().max_value), str(panel._detail_scroll.get_v_scroll_bar().page), panel._detail_scroll.scroll_vertical])
		_check(panel._detail_scroll.scroll_vertical > 0 and panel._fixed_quote.is_visible_in_tree() and quote_rect.end.y <= float(client._dialog.size.y) + 1.0 and confirm_rect.end.y <= float(client._dialog.size.y) + 1.0 and quote_rect.end.x <= float(client._dialog.size.x) + 1.0 and confirm_rect.end.x <= float(client._dialog.size.x) + 1.0, "Scrolling a long capacity comparison leaves the entire cost quotation and confirmation visible on the phone")
		_check(client._dialog.position.x >= 0 and client._dialog.position.y >= 0 and client._dialog.position.x + client._dialog.size.x <= root.size.x and client._dialog.position.y + client._dialog.size.y <= root.size.y, "Expanded comparison and fixed footer keep the entire Window inside the phone viewport")
		var comparison_scroll: int = panel._detail_scroll.scroll_vertical
		var selected_quote: Dictionary = panel.shown_quote.duplicate(true)
		var comparison_id: int = compare.get_instance_id()
		var unchanged_body_id: int = compare._body.get_child(0).get_instance_id()
		client._receive_snapshot(fixtures.idle)
		await _settle()
		_check(compare._body.get_child(0).get_instance_id() == unchanged_body_id, "An identical snapshot does not rebuild the read-only comparison")
		client._receive_snapshot(fixtures.completed)
		await _settle()
		_check(fixtures.completed.view.buildingComparisons.house.currentCapacity > fixtures.idle.view.buildingComparisons.house.currentCapacity and compare._comparison == fixtures.completed.view.buildingComparisons.house, "Completing a real canonical house updates the open comparison to the latest capacity DTO")
		_check(compare.get_instance_id() == comparison_id and compare._body.visible and absi(panel._detail_scroll.scroll_vertical - comparison_scroll) <= 1, "Live capacity refresh retains the existing comparison's expansion and real detail scroll offset")
		_check(panel.site == 35 and panel.shown_quote == selected_quote and panel.category == "民生" and not panel.only_available and api.commands.is_empty(), "Read-only capacity refresh preserves the player's site, original quotation and filters without a command")
		var foreign_view: Dictionary = fixtures.completed.view.duplicate(true)
		foreign_view.city.id = "another-owned-city"
		foreign_view.buildingComparisons.house.cityId = foreign_view.city.id
		foreign_view.buildingComparisons.house.currentCapacity = 9999
		panel.update_view(foreign_view, false)
		await _settle()
		_check(compare._comparison == fixtures.completed.view.buildingComparisons.house and api.commands.is_empty(), "Switching cities cannot refresh an old empty-site panel with another city's capacity")
		foreign_view.city.id = panel.source_city
		panel.update_view(foreign_view, false)
		await _settle()
		_check(compare._comparison == fixtures.completed.view.buildingComparisons.house and api.commands.is_empty(), "A comparison whose cityId disagrees with the displayed source is also rejected")
		panel.update_view(fixtures.completed.view, true)
		await _settle()
		_button(compare, "查看地块 1 升级").pressed.emit()
		await _settle()
		_check(client._dialog.title == "建筑详情" and api.commands.is_empty(), "Comparison navigates to the actual existing house without queuing an upgrade")
		var exact_site: bool = false
		for label: Node in client._dialog.find_children("*", "Label", true, false):
			exact_site = exact_site or (label as Label).text == "地块 1"
		_check(exact_site, "Upgrade detail identifies the selected existing house rather than the empty construction site")
	client._dialog.hide()
	client._receive_snapshot(fixtures.active)
	await _settle()
	_check(client._activity_bar.visible, "A real canonical training order restores the city military HUD")
	client._show_page("world")
	await _settle()
	_check(client._activity_bar.visible and not client._city_status_row.visible, "Other pages retain the complete original military HUD")
	print("CITY_CONSTRUCTION_PANEL_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
