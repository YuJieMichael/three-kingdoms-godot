extends SceneTree

## Integration UI verification. The helper labels naturally earned first-battle
## snapshots separately from prepared later-chapter/shared scenario boundaries.
## ApiProbe has no HTTP/timer/journal and records, rather than executes, commands.
class ApiProbe extends "res://src/game_api.gd":
	var pending: bool = false
	var commands: Array[Dictionary] = []
	var quotes: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func _has_mutation() -> bool:
		return pending
	func command(type: String, args: Array = [], _source: String = "") -> void:
		if connected and not pending:
			commands.append({"type": type, "args": args.duplicate(true)})
			pending = true
	func request_quote(kind: String, args: Array, request_id: String) -> void:
		quotes.append({"kind": kind, "args": args.duplicate(true), "requestId": request_id})


class ClientProbe extends "res://src/main.gd":
	func _ready() -> void:
		_smoke = true
		_initialize_inputs()
		theme = _make_theme()
		_audio = AudioScript.new() as KingdomPresentationAudio
		add_child(_audio)
		_build_shell()
		add_child(api)
		_initialize_presentation()
		_show_page("world")
	func _check_smoke() -> void:
		pass


var _checks: int = 0
var _failures: int = 0
var _client: ClientProbe
var _api: ApiProbe
var _fixtures: Dictionary = {}


func _initialize() -> void:
	# Rendering initializes before this script. Carry over directory names only;
	# all settings, pending journals and runtime writes use a fresh user directory.
	var cache: String = OS.get_user_data_dir().path_join("shader_cache")
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceGrowthEconomyClientTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("shader_cache"))
	if DirAccess.dir_exists_absolute(cache):
		for shader: String in DirAccess.get_directories_at(cache):
			for version: String in DirAccess.get_directories_at(cache.path_join(shader)):
				DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("shader_cache").path_join(shader).path_join(version))
	root.gui_embed_subwindows = true
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for index: int in 5:
		await process_frame


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var folder: String = "res://production/qa/evidence/story-010/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(root.get_texture().get_image().save_png(folder + name + ".png") == OK, "Native integration screenshot saves: " + name)


func _find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption:
		return node as Button
	for child: Node in node.get_children():
		var result: Button = _find_button(child, caption)
		if result != null:
			return result
	return null


func _labels(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child: Node in node.get_children():
		result += _labels(child)
	return result


func _apply(snapshot: Dictionary, world: Dictionary = {}) -> void:
	# Main owns and clears its current dictionaries on identity changes. Leave
	# the original evidence DTOs intact, as a real API would replace envelopes.
	var received: Dictionary = snapshot.duplicate(true)
	_api.last_snapshot = received
	_api.actor = received.get("actor", {})
	_api.shared_world = received.get("shared", {})
	_client._receive_snapshot(received)
	if not world.is_empty():
		_client._receive_world(world.duplicate(true))


func _report(snapshot: Dictionary, shared_id: String = "") -> Dictionary:
	for row: Dictionary in snapshot.view.reports:
		if (not shared_id.is_empty() and str(row.get("id", "")) == shared_id) or (shared_id.is_empty() and row.get("node", "") == "field"):
			return row
	return {}


func _scroll() -> ScrollContainer:
	return _client._growth_route.get_parent().get_parent() as ScrollContainer


func _check_report_width(context: String) -> void:
	var content: VBoxContainer = _client._report_economy.get_parent() as VBoxContainer
	var scroll: ScrollContainer = content.get_parent() as ScrollContainer
	if _client._dialog.size.x > root.size.x - 24:
		print("REPORT_WIDTH_DIAGNOSTIC %s viewport=%s client=%s popup=%s scroll=%s content_min=%s economy=%s economy_min=%s" % [context, root.size, _client.size, _client._dialog.size, scroll.size, content.get_combined_minimum_size(), _client._report_economy.size, _client._report_economy.get_combined_minimum_size()])
		for child: Node in content.get_children():
			if child is Label:
				print("REPORT_LABEL_DIAGNOSTIC wrap=%d min=%s text=%s" % [child.autowrap_mode, child.get_combined_minimum_size(), child.text])
	_check(_client._dialog.size.x <= root.size.x - 24, context + " modal stays inside the actual viewport")
	_check(content.get_combined_minimum_size().x <= scroll.size.x, context + " report body does not push its scroll region wider")
	_check(_client._report_economy.size.x <= root.size.x - 40, context + " economic metrics remain inside the actual viewport")


func _run() -> void:
	if not Engine.has_singleton("SoundManager"):
		root.add_child(load("res://addons/sound_manager/sound_manager.gd").new())
	if not Engine.has_singleton("DialogueManager"):
		root.add_child(load("res://addons/dialogue_manager/dialogue_manager.gd").new())
	var output: Array = []
	var node: String = OS.get_environment("TK_NODE")
	if node.is_empty() or OS.execute(node, [ProjectSettings.globalize_path("res://tests/helpers/growth-economy-view.mjs")], output) != 0:
		_check(false, "TK_NODE must execute isolated, canonical growth/economy fixtures")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(str(output[0]))
	if not parsed is Dictionary:
		_check(false, "Canonical integration helper produces a valid DTO envelope")
		quit(1)
		return
	_fixtures = parsed
	var original: String = JSON.stringify(_fixtures)
	_check(_fixtures.meta.natural and _fixtures.meta.naturalCommands > 0, "Private snapshots come from natural legal first-battle commands")
	_check(_fixtures.meta.naturalVictories == 1 and _fixtures.meta.returnedArchers == 30, "Natural first battle finishes with one victory and 30 returned/refilled archers")
	_check(_fixtures.meta.earnedGifts.size() == 2 and int(_fixtures.meta.earnedGifts[0]) == 1 and int(_fixtures.meta.earnedGifts[1]) == 2, "Acceleration inventory comes from real earned onboarding gifts")
	_check(_fixtures.queued.fixtureScope.begins_with("natural:") and _fixtures.chapter.fixtureScope.begins_with("prepared:"), "Later chapter routing boundary is explicitly separate from the natural route")
	_check(_fixtures.meta.sharedPrepared and not _fixtures.meta.sharedActualReturn.loot.is_empty(), "Shared proof comes from an actual nonzero return transaction in a declared prepared scenario")
	_client = ClientProbe.new()
	_api = ApiProbe.new()
	_api.mode = "private"
	_api.connected = true
	_client.api = _api
	_client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_client)
	_client._connection_changed("隔离 fixture 已连接", true)
	for width: int in [390, 1280]:
		await _test_growth(width)
	await _test_routes()
	await _test_reports()
	await _test_identity_clear()
	_check(_api.commands.is_empty(), "Growth previews, routes, report receipts, polling and identity changes issue no gameplay commands")
	_check(JSON.stringify(_fixtures) == original, "UI navigation and identity cleanup leave all canonical evidence DTOs unchanged")
	_client.queue_free()
	await _settle()
	print("GROWTH_ECONOMY_CLIENT_TEST_CHECKS=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_growth(width: int) -> void:
	root.size = Vector2i(width, 844)
	_apply(_fixtures.queued, _fixtures.natural.worldSample)
	_client._show_page("world")
	await _settle()
	# Preserve a real prior filter so routing has to clear it to reveal the item.
	_client._inventory_dialog()
	_client._inventory._search.text = "不存在的旧搜索"
	_client._inventory._search.text_changed.emit(_client._inventory._search.text)
	_client._inventory.hide()
	await _settle()
	_client._nav_buttons.city.grab_focus()
	_client._show_growth_route()
	await _settle()
	var card: KingdomGrowthRouteView = _client._growth_route
	var popup: AcceptDialog = _client._dialog
	var scroll: ScrollContainer = _scroll()
	var suggestion: Dictionary = _fixtures.queued.view.growth.speedup.suggestion
	_check(popup.visible and popup.title == "成长路线", "Real main growth modal opens at %dpx" % width)
	_check(popup.size.x <= width - 24, "Growth modal fits %dpx viewport" % width)
	_check(card.get_combined_minimum_size().x <= scroll.size.x, "Growth content avoids horizontal clipping at %dpx" % width)
	_check(popup.get_viewport().gui_get_focus_owner() == popup.get_ok_button(), "Growth modal initially focuses its safe close action at %dpx" % width)
	_check(card._speedup.text.contains("库存 %d 件" % int(suggestion.count)) and not card._speedup.text.contains("×%d" % int(suggestion.count)), "Owned stock is not presented as a multiple-item consumption at %dpx" % width)
	_check(card._speedup.text.contains("可缩短") and card._speedup.text.contains("使用后还需") and card._speedup.text.contains("不保留"), "Natural acceleration explains shortened work, remaining wait and wasted duration at %dpx" % width)
	await _capture("03-growth-client-natural-queued-%d" % width)
	card._more.pressed.emit()
	card.focus_current()
	await _settle()
	scroll.scroll_vertical = 80
	await _settle()
	var position: int = scroll.scroll_vertical
	var focused: Control = popup.get_viewport().gui_get_focus_owner()
	var current_button: Button = card._current
	_apply(_fixtures.queued)
	await _settle()
	_check(_client._dialog == popup and _client._growth_route == card and card._current == current_button, "Stable polling preserves modal, route card and current button at %dpx" % width)
	_check(card._expanded and card._gaps.text.contains("真实前置"), "Stable polling preserves expanded prerequisite details at %dpx" % width)
	_check(scroll.scroll_vertical == position and popup.get_viewport().gui_get_focus_owner() == focused, "Stable polling preserves growth scroll and keyboard focus at %dpx" % width)
	_api.pending = true
	_client._connection_changed("正在确认", true)
	_check(card._current.disabled and card._speedup_action.disabled, "Pending mutation locks growth navigation at %dpx" % width)
	for button: Button in card._advice_actions:
		if button.visible:
			_check(button.disabled, "Pending mutation locks each visible growth recovery route at %dpx" % width)
	card._current.pressed.emit()
	card._speedup_action.pressed.emit()
	_check(popup.visible and not _client._inventory.visible, "Synthetic repeated activation while pending cannot open an expense page at %dpx" % width)
	_api.connected = false
	_client._connection_changed("断线", false)
	_apply(_fixtures.queued)
	_check(card._current.disabled and card._speedup_action.disabled, "Disconnected polling keeps pending growth actions locked at %dpx" % width)
	_api.pending = false
	_client._connection_changed("仍离线", false)
	_check(card._current.disabled and card._speedup_action.disabled, "Disconnected growth remains locked even after the pending flag clears at %dpx" % width)
	_api.connected = true
	_client._connection_changed("已连接", true)
	_check(not card._current.disabled and not card._speedup_action.disabled, "Reconnect restores legal read-only growth navigation at %dpx" % width)
	card._speedup_action.pressed.emit()
	await _settle()
	_check(_client._inventory.visible and not popup.visible, "Acceleration route transfers to the actual inventory modal at %dpx" % width)
	_check(_client._inventory._selected_item == suggestion.itemId and _client._inventory._target_id == suggestion.targetKey, "Inventory selects the precise owned item and canonical queue key at %dpx" % width)
	_check(_client._inventory._search.text.is_empty() and _client._inventory._selected_category.is_empty(), "Exact item routing clears a prior search/category filter at %dpx" % width)
	var action: Dictionary = _client._inventory._action()
	_check(action.type == "useSpeedup" and action.args == [suggestion.itemId, suggestion.targetKey] and str(action.reason).is_empty(), "Prepared inventory action quotes one item on the exact queue at %dpx" % width)
	_check(_api.commands.is_empty(), "Opening a speedup quote consumes no owned item at %dpx" % width)
	_client._inventory.hide()
	await _settle()
	_check(_client.get_viewport().gui_get_focus_owner() == _client._nav_buttons.city, "Closing inventory restores the original visible growth opener at %dpx" % width)
	# Remove the prior modal so the next size starts without any hidden targets.
	_client._mode_changed("private")
	await _settle()


func _test_routes() -> void:
	_apply(_fixtures.battleSettled, _fixtures.natural.worldSample)
	_client._show_growth_route()
	await _settle()
	_check(_client._growth_route._title.text.contains("返城") and _client._growth_route._view.growth.current.navigate.route == "marches", "Natural battle victory keeps the return prerequisite until the actual expedition arrives")
	_apply(_fixtures.natural, _fixtures.natural.worldSample)
	_client._show_growth_route()
	await _settle()
	_check(_client._growth_route._stage.text.contains("史诗与官爵") and not _client._growth_route._title.text.contains("首战"), "Natural victory/return immediately advances growth into epic and honor prerequisites")
	_client._route_objective("chapters")
	await _settle()
	_check(_client._progression.visible and _client._progression._section == "chapters", "Chapter route opens the actual chapter section")
	_client._route_objective("missions")
	_check(_client._progression._section == "missions", "Mission route remains distinct from chapters")
	_client._route_objective("epic", "exchange")
	_check(_client._progression._section == "epic" and _client._progression._filter.selected == 3, "Epic exchange route selects the actual exchange filter")
	for route: String in ["holdings", "gather"]:
		_client._route_objective(route)
		_check(_client._realm.visible and _client._realm._section == "holdings", route + " opens the actual gathering section")
	_apply(_fixtures.chapter, _fixtures.chapter.worldSample)
	_client._show_growth_route()
	await _settle()
	_check(_client._growth_route._stage.text.contains("1 / 6") and _client._growth_route._title.text.contains("粮仓"), "Prepared county/chapter snapshot advances immediately to the next open chapter objective")
	_client._growth_route._current.pressed.emit()
	await _settle()
	_check(_client._page == "world" and str(_client._selected.get("id", "")) == "north_granary", "Chapter growth navigation selects the exact open world target")
	_apply(_fixtures.chapterComplete, _fixtures.chapterComplete.worldSample)
	_client._show_growth_route()
	await _settle()
	_check(_client._growth_route._stage.text.contains("第二章已平定") and _client._growth_route._stage.text.contains("6 / 6"), "Prepared six-occupation boundary immediately replaces the second-chapter progress title")
	_check(_client._growth_route._view.growth.current.navigate == _fixtures.chapterComplete.view.growth.current.navigate, "Completed chapter preserves only the canonical next open route")
	_check(_api.commands.is_empty(), "Chapter, exchange and gathering routes remain read-only")


func _test_reports() -> void:
	root.size = Vector2i(390, 844)
	_apply(_fixtures.oldReport)
	_client._report_dialog(_report(_fixtures.oldReport))
	await _settle()
	var economy: KingdomReportEconomyView = _client._report_economy
	var popup: AcceptDialog = _client._dialog
	_check(economy._economy.status == "unknown" and economy._resource_rows.food.received.text == "实际入库 未确认", "Legacy report with absent receipt fields never invents deposited income")
	_check_report_width("Legacy private 390px")
	await _capture("04-report-client-legacy-390")
	_apply(_fixtures.natural)
	await _settle()
	_check(_client._dialog == popup and _client._report_economy == economy and economy._economy.status == "delivered", "A real natural receipt refreshes the existing legacy report component")
	_check_report_width("Natural delivered private 390px")
	var received: Dictionary = _report(_fixtures.natural).economy.received
	for id: String in KingdomReportEconomyView.RESOURCE_IDS:
		_check(economy._resource_rows[id].received.text == "实际入库 " + economy._number_text(float(received.get(id, 0))), "Private " + id + " income displays actual receipt amounts")
	var row: Label = economy._resource_rows.food.received
	_apply(_fixtures.natural)
	_check(economy._resource_rows.food.received == row, "Unchanged report polling retains the original resource controls")
	await _capture("05-report-client-natural-delivered-390")
	_api.mode = "shared"
	_api.room = {"name": "隔离共享演练"}
	_client._mode_changed("shared")
	_apply(_fixtures.pending, _fixtures.sharedWorld)
	await _settle()
	_check(not _client._growth_button.visible, "Shared mode hides the private growth sidebar entry")
	_client._tasks_dialog()
	await _settle()
	_check(_find_button(_client._dialog, "成长路线") == null, "Shared transactions do not expose the private growth entry")
	var shared_id: String = str(_fixtures.meta.sharedReportId)
	var stale: Dictionary = _report(_fixtures.pending, shared_id).duplicate(true)
	_client._report_dialog(stale)
	await _settle()
	economy = _client._report_economy
	popup = _client._dialog
	_check(economy._economy.status == "pending" and economy._resource_rows.food.received.text == "实际入库 尚未入库", "Canonical shared battle remains unconfirmed before its real return")
	_check_report_width("Shared pending 390px")
	await _capture("06-report-client-shared-pending-390")
	_apply(_fixtures.proofless)
	_check(_client._report_economy == economy and economy._economy.status == "unknown" and economy._resource_rows.food.received.text == "实际入库 未确认", "Delivered boolean with no resource receipt cannot fabricate actual income")
	_apply(_fixtures.delivered)
	await _settle()
	_check(_client._dialog == popup and _client._report_economy == economy and economy._economy.status == "delivered", "Actual shared return updates the currently open economy component")
	_check_report_width("Shared delivered 390px")
	var actual: Dictionary = _fixtures.meta.sharedActualReturn.loot
	for id: String in KingdomReportEconomyView.RESOURCE_IDS:
		_check(economy._resource_rows[id].received.text == "实际入库 " + economy._number_text(float(actual.get(id, 0))), "Shared " + id + " income agrees with the actual canonical return transaction")
	await _capture("07-report-client-shared-delivered-390")
	# PvP list callbacks can retain a raw or stale report after its cargo returns.
	stale.erase("economy")
	_client._report_dialog(stale)
	await _settle()
	_check(_client._report_economy._economy.status == "delivered" and _client._report_economy._resource_rows.food.received.text == "实际入库 " + _client._report_economy._number_text(float(actual.food)), "Raw/stale PvP callback resolves the latest identity-matched receipt projection")
	root.size = Vector2i(1280, 844)
	_client._report_dialog(stale)
	await _settle()
	_check(_client._dialog.size.x <= 1280 - 24 and _client._report_economy.size.x <= _client._dialog.size.x, "Real shared report modal fits the desktop viewport")
	_check_report_width("Shared delivered 1280px")
	await _capture("08-report-client-shared-delivered-1280")
	_client._mode_changed("shared")
	_apply(_fixtures.defenderView, _fixtures.sharedWorld)
	_client._report_dialog(_report(_fixtures.defenderView, shared_id))
	await _settle()
	_check(_client._report_economy._economy.scope == "defenders-total" and _labels(_client._report_economy).contains("含盟友") and _labels(_client._report_economy).contains("不能分摊本人"), "Defender aggregate recovery scope is not presented as the current player's personal bill")
	_check(_api.commands.is_empty(), "Report presentation and receipt updates execute no treatment, replacement or delivery commands")


func _test_identity_clear() -> void:
	_api.mode = "private"
	_client._mode_changed("private")
	_apply(_fixtures.queued, _fixtures.natural.worldSample)
	_client._show_growth_route()
	await _settle()
	var old_growth: WeakRef = weakref(_client._growth_route)
	var old_dialog: WeakRef = weakref(_client._dialog)
	_api.mode = "shared"
	_client._mode_changed("shared")
	_check(_client._view.is_empty() and _client._state.is_empty() and _client._world.is_empty(), "Identity replacement clears all private snapshot and world dictionaries before a new snapshot")
	_check(_client._growth_route == null and _client._report_economy == null and _client._dialog == null and _client._inventory == null, "Identity replacement detaches old growth, economy, dialog and inventory references")
	_check(not _client._growth_button.visible and _client._resources.food.tooltip_text.is_empty(), "Identity replacement removes private entry points and precise resource tooltips")
	await _settle()
	_check(old_growth.get_ref() == null and old_dialog.get_ref() == null, "Detached private growth controls are freed safely after deferred callbacks")
	_apply(_fixtures.delivered, _fixtures.sharedWorld)
	_client._report_dialog(_report(_fixtures.delivered, str(_fixtures.meta.sharedReportId)))
	await _settle()
	var old_economy: WeakRef = weakref(_client._report_economy)
	# Same-mode actor changes must clear an old actor's confirmed resource proof.
	_client._mode_changed("shared")
	_check(_client._report_economy == null and _client._report_key.is_empty() and _client._economy_signature.is_empty(), "Same-mode actor replacement clears old report identity and receipt signature")
	await _settle()
	_check(old_economy.get_ref() == null, "Old actor economy controls are destroyed before a replacement receipt arrives")
