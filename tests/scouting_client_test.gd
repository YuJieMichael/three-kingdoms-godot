extends SceneTree

## The helper declares its prepared starting boundary and runs real canonical
## scouting settlements in memory. The production main UI below receives those
## DTOs. ApiProbe records intent only: no HTTP, game consumption or save journal.
class ApiProbe extends "res://src/game_api.gd":
	var pending: bool = false
	var commands: Array[Dictionary] = []
	var quotes: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func _has_mutation() -> bool:
		return pending
	func command(type: String, args: Array = [], source_city: String = "") -> void:
		if connected and not pending:
			commands.append({"type": type, "args": args.duplicate(true), "sourceCity": source_city})
			pending = true
	func request_quote(kind: String, args: Array, request_id: String) -> void:
		if connected and not pending:
			quotes.append({"kind": kind, "args": args.duplicate(true), "requestId": request_id,
				"sourceCity": str(last_snapshot.get("view", {}).get("city", {}).get("id", ""))})


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
		api.quote_received.connect(_receive_quote)
		api.command_completed.connect(_command_completed)
		api.mode_changed.connect(_mode_changed)
		_show_page("world")
	func _check_smoke() -> void:
		pass


var _checks: int = 0
var _failures: int = 0
var _client: ClientProbe
var _api: ApiProbe
var _fixtures: Dictionary = {}
var _old_user_dir: Variant
var _old_user_name: Variant


func _initialize() -> void:
	_old_user_dir = ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	_old_user_name = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	var cache: String = OS.get_user_data_dir().path_join("shader_cache")
	var unique: String = "ShanheceScoutingClientIsolatedFixture-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", unique)
	if not OS.get_user_data_dir().ends_with(unique):
		push_error("Refusing scouting client test without an isolated user directory")
		quit(1)
		return
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
	var folder: String = "res://production/qa/evidence/story-011/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(root.get_texture().get_image().save_png(folder + name + ".png") == OK, "Isolated fixture screenshot saves: " + name)


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


func _apply(snapshot: Dictionary, with_world: bool = false) -> void:
	var received: Dictionary = snapshot.duplicate(true)
	_api.last_snapshot = received
	_api.revision = int(received.get("revision", 0))
	_client._receive_snapshot(received)
	if with_world:
		_client._receive_world(_fixtures.unknown.worldSample.duplicate(true))


func _quote(precision: String) -> Dictionary:
	var value: Dictionary = _fixtures.previews[precision].duplicate(true)
	if _api.quotes.is_empty():
		_check(false, "Main must route an ordinary-wild quote before a response can be delivered")
		return {}
	value.requestId = _api.quotes.back().requestId
	return value


func _open_scout(precision: String) -> void:
	_client._show_scouting(_fixtures.selected[precision])
	var count: SpinBox = _client._scouting._count
	count.value = float(_fixtures.previews[precision].quote.count)
	count.get_line_edit().text = str(int(count.value))
	count.get_line_edit().text_changed.emit(count.get_line_edit().text)


func _release_fixture_audio() -> void:
	# Real button callbacks started music/UI tones in the process's autoload.
	# Freeing ClientProbe alone does not release that root-level player pool.
	# Stop its queued fades and voices before releasing the test's WAV streams.
	var manager: Node = Engine.get_singleton("SoundManager") as Node
	if not is_instance_valid(manager):
		return
	for pool: Node in manager.get_children():
		for child: Node in pool.get_children():
			if child is AudioStreamPlayer:
				if pool.has_method("_remove_tween"):
					pool.call("_remove_tween", child)
				(child as AudioStreamPlayer).stop()
				(child as AudioStreamPlayer).stream = null
	if is_instance_valid(_client._audio):
		_client._audio._streams.clear()


func _run() -> void:
	if not Engine.has_singleton("SoundManager"):
		root.add_child(load("res://addons/sound_manager/sound_manager.gd").new())
	if not Engine.has_singleton("DialogueManager"):
		root.add_child(load("res://addons/dialogue_manager/dialogue_manager.gd").new())
	var output: Array = []
	var node: String = OS.get_environment("TK_NODE")
	if node.is_empty() or OS.execute(node, [ProjectSettings.globalize_path("res://tests/helpers/scouting-client-view.mjs")], output) != 0:
		_check(false, "TK_NODE must execute canonical, isolated scouting fixtures")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(str(output[0]))
	if not parsed is Dictionary:
		_check(false, "Scouting fixture helper emits a valid DTO envelope")
		quit(1)
		return
	_fixtures = parsed
	var original: String = JSON.stringify(_fixtures)
	_check(_fixtures.meta.prepared and _fixtures.meta.isolated and _fixtures.meta.noHTTP and _fixtures.meta.noPlayerSave, "Prepared boundary is explicitly isolated; this is not natural pacing evidence")
	_check(int(_fixtures.meta.commandCount) == 6 and int(_fixtures.meta.initialScouts) - int(_fixtures.meta.restoredScouts) == int(_fixtures.meta.expectedLost), "Paid founding, four scouts and city switch use canonical commands; return restores actual survivors")
	_check(not _fixtures.unknown.view.nodes.any(func(value: Dictionary) -> bool: return value.id == _fixtures.selected.exact.id), "Ordinary wild target is absent from landmark nodes and relies on safe intelByNode projection")
	_client = ClientProbe.new()
	_api = ApiProbe.new()
	_api.mode = "local"
	_api.connected = true
	_client.api = _api
	_client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_client)
	_client._connection_changed("隔离 fixture · 无真实服务或消费", true)
	await _test_unknown_and_quote()
	await _test_quote_locks()
	await _test_intelligence_updates()
	await _test_marches()
	await _test_identity_clear()
	_check(_api.commands.size() == 1, "Entire main integration records exactly one intended scout command and executes none")
	_check(JSON.stringify(_fixtures) == original, "Main UI updates and identity clear never mutate canonical fixture evidence")
	_release_fixture_audio()
	_client.queue_free()
	await _settle()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", _old_user_dir)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", _old_user_name)
	print("SCOUTING_CLIENT_TEST_CHECKS=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_unknown_and_quote() -> void:
	root.size = Vector2i(390, 844)
	_apply(_fixtures.unknown, true)
	_client._show_page("world")
	_client._select_tile(_fixtures.selected.exact.duplicate(true))
	await _settle()
	_check(is_instance_valid(_client._dispatch_intel) and _client._dispatch_intel._precision.text.contains("未侦察"), "390px ordinary wild selection opens real main dispatch with unknown intelligence")
	_check(_client._dispatch_intel._details.text.contains("未知不表示") and not _client._dispatch_intel._details.text.contains("10 人"), "Unknown wild target never renders its canonical hidden militia count")
	var action: Button = _find_button(_client._scouting, "先侦察目标")
	_check(action != null and not action.disabled, "Main dispatch exposes scouting entry for a legal ordinary wild target")
	_check(_client._scouting.size.x <= 390 - 24, "Main dispatch fits the narrow isolated viewport")
	await _capture("01-scouting-client-isolatedfixture-dispatch-unknown-390")
	action.pressed.emit()
	await _settle()
	var dialog: KingdomScoutingDialog = _client._scouting
	_check(dialog.visible and dialog._target.id == _fixtures.selected.exact.id and dialog._source == "capital", "Main scouting entry preserves exact selected target and current source city")
	_check(dialog.visible and dialog.get("_tabs").current_tab == 1 and (not is_instance_valid(_client._dialog) or not _client._dialog.visible), "Scouting switches tab in the same active dispatch window without stacked modals")
	_check(dialog.get_viewport().gui_get_focus_owner() == dialog.get_ok_button(), "Scouting opens on safe keyboard close action")
	dialog._count.value = 63
	dialog._count.get_line_edit().text = "63"
	dialog._count.get_line_edit().text_changed.emit("63")
	dialog._preview.pressed.emit()
	_check(not _api.quotes.is_empty(), "Ordinary wild remains a usable scout target despite absence from landmark view.nodes")
	if _api.quotes.is_empty():
		return
	_check(_api.quotes.back().kind == "scout" and _api.quotes.back().args == [_fixtures.selected.exact.id, 63] and _api.quotes.back().sourceCity == "capital", "Production quote signal requests only canonical scout target/count under current city")
	var canonical: Dictionary = _quote("exact")
	_api.quote_received.emit(canonical)
	_check(not dialog._confirm.disabled and dialog._quote_command == canonical.quote.command, "Real quote reaches production dialog and enables only its exact canonical command")
	for fragment: String in ["粮草费用", "单程", "返程", "精确兵力", "预计斥候损失", "情报有效期", "自抵达", "点击确认后"]:
		_check(dialog._quote_label.text.contains(fragment), "Main scouting quote explains " + fragment)
	_check(dialog._quote_label.text.contains(str(int(canonical.quote.cost.food))), "Main quote shows actual canonical grain price")
	await _settle()
	_check(dialog.size.x <= 390 - 24 and dialog._content.get_combined_minimum_size().x <= dialog._scroll.size.x, "Scouting quote wraps without horizontal clipping at 390px")
	_check(dialog._preview.size.y >= 44 and dialog._confirm.size.y >= 44 and dialog._count.size.y >= 44, "Scouting primary controls have reachable 44px height")
	dialog._scroll.scroll_vertical = int(dialog._content.size.y)
	await _settle()
	_check(not dialog._scroll.is_ancestor_of(dialog._confirm) and Rect2(Vector2.ZERO, Vector2(dialog.size)).encloses(dialog._confirm.get_global_rect()), "Narrow scouting confirmation remains fully visible outside scrolling content")
	await _capture("02-scouting-client-isolatedfixture-quote-390")
	dialog._confirm.pressed.emit()
	dialog._confirm.pressed.emit()
	_check(_api.commands.size() == 1 and _api.commands[0] == canonical.quote.command, "Confirmation records dispatchScout[node,count,key] and sourceCity exactly once")
	_check(dialog._confirm.disabled and dialog._preview.disabled and _api.pending, "Pending command locks repeated scout consumption immediately")
	_api.pending = false
	_api.command_completed.emit("dispatchScout", {})
	dialog.hide()


func _test_quote_locks() -> void:
	_apply(_fixtures.unknown)
	_open_scout("exact")
	var dialog: KingdomScoutingDialog = _client._scouting
	dialog._preview.pressed.emit()
	var late: Dictionary = _quote("exact")
	dialog._count.value = 62
	dialog._count.get_line_edit().text = "62"
	dialog._count.get_line_edit().text_changed.emit("62")
	_api.quote_received.emit(late)
	dialog._confirm.pressed.emit()
	_check(dialog._confirm.disabled and dialog._quote_command.is_empty() and _api.commands.size() == 1, "Count change rejects the prior quote even through synthetic activation")
	_open_scout("exact")
	dialog._preview.pressed.emit()
	late = _quote("exact")
	_open_scout("types")
	_api.quote_received.emit(late)
	_check(dialog._target.id == _fixtures.selected.types.id and dialog._confirm.disabled, "Changed target cannot adopt a delayed quote for the old target")
	dialog._preview.pressed.emit()
	var current: Dictionary = _quote("types")
	_api.quote_received.emit(current)
	_check(not dialog._confirm.disabled, "A fresh canonical quote for the replacement target restores confirmation")
	_api.connected = false
	_client._connection_changed("隔离 fixture 断线", false)
	_api.quote_received.emit(current)
	dialog._confirm.pressed.emit()
	dialog._preview.pressed.emit()
	_check(dialog._confirm.disabled and dialog._preview.disabled and not dialog._count.editable and _api.commands.size() == 1, "Disconnected main disables editing/preview/send and ignores a delayed quote")
	_api.connected = true
	_client._connection_changed("隔离 fixture 重连", true)
	dialog._preview.pressed.emit()
	current = _quote("types")
	_api.quote_received.emit(current)
	_api.pending = true
	_client._connection_changed("隔离 fixture 等待其他操作", true)
	dialog._confirm.pressed.emit()
	dialog._preview.pressed.emit()
	_check(dialog._confirm.disabled and dialog._preview.disabled and _api.commands.size() == 1, "Unrelated pending mutation revokes a valid scout quote and prevents repeat intent")
	_api.pending = false
	_client._connection_changed("隔离 fixture 已连接", true)
	dialog._preview.pressed.emit()
	current = _quote("types")
	_apply(_fixtures.switched)
	_api.quote_received.emit(current)
	dialog._confirm.pressed.emit()
	_check(dialog._source == _fixtures.meta.secondCity and dialog._confirm.disabled and _api.commands.size() == 1, "Canonical city switch rejects old-source quote without any command")
	dialog.hide()


func _test_intelligence_updates() -> void:
	root.size = Vector2i(1280, 844)
	_apply(_fixtures.returned, true)
	_client._dispatch_dialog(_fixtures.selected.exact)
	await _settle()
	var panel: KingdomIntelPanel = _client._dispatch_intel
	var popup: AcceptDialog = _client._scouting
	_check(panel._precision.text.contains("精确") and panel._details.text.contains("10 人"), "Ordinary wild exact report becomes visible in real main dispatch despite absent landmark node")
	_check(_client._intel_node(_fixtures.selected.exact).army == _fixtures.meta.exactArmy, "Main copies exact obtained report army from safe projection")
	await _capture("03-scouting-client-isolatedfixture-dispatch-exact-1280")
	_apply(_fixtures.returned)
	await _settle()
	_check(_client._scouting == popup and _client._dispatch_intel == panel, "Stable polling updates intelligence without replacing dispatch modal or controls")
	_apply(_fixtures.expired)
	_check(_api.revision == int(_fixtures.returned.revision) and _fixtures.expired.serverTime > _fixtures.returned.serverTime, "Expiry evidence uses same revision with a later actual canonical clock")
	_check(panel._precision.text.contains("过期") and not panel._details.text.contains("10 人"), "Same-revision later server time withdraws expired precise numbers in the open main modal")
	_apply(_fixtures.returned)
	_check(panel._precision.text.contains("精确"), "Restoring an independent unexpired fixture displays its obtained report")
	_apply(_fixtures.removed)
	_check(panel._precision.text.contains("未侦察") and not panel._details.text.contains("10 人"), "Removing intelByNode revokes exact counts rather than retaining selected-tile cache")
	_apply(_fixtures.returned)
	_apply(_fixtures.switched)
	_check(panel._precision.text.contains("未侦察") and not panel._details.text.contains("10 人"), "Canonical source city switch clears a previous city's ordinary-wild intelligence")
	for precision: String in ["types", "bands", "failed"]:
		_apply(_fixtures.returning)
		_client._dispatch_dialog(_fixtures.selected[precision])
		var text: String = _client._dispatch_intel._details.text
		_check(_client._dispatch_intel._node.intel.precision == precision, "Main presents canonical " + precision + " precision without upgrading it")
		if precision == "types":
			_check(_client._dispatch_intel._precision.text.contains("数量未知") and not text.contains(" 人"), "Types report lists units without invented counts")
		elif precision == "bands":
			_check(text.contains("–") and _client._dispatch_intel._node.army.is_empty(), "Bands report shows ranges and no exact army")
		else:
			_check(text.contains("未获得有效") and _client._dispatch_intel._node.army.is_empty(), "Failed report exposes no hidden guard army")
	_apply(_fixtures.returned)
	_open_scout("exact")
	var dialog: KingdomScoutingDialog = _client._scouting
	await _settle()
	_check(dialog._intel._precision.text.contains("精确"), "Scouting dialog initially receives obtained exact wild report")
	dialog._count.get_line_edit().grab_focus()
	await _settle()
	dialog._count.get_line_edit().text = "17"
	dialog._count.get_line_edit().text_changed.emit("17")
	var owner: Control = dialog.get_viewport().gui_get_focus_owner()
	_apply(_fixtures.returned)
	await _settle()
	_check(dialog._count.get_line_edit().text == "17", "Stable snapshot preserves scouting raw quantity (actual: %s)" % dialog._count.get_line_edit().text)
	_check(dialog.get_viewport().gui_get_focus_owner() == owner, "Stable snapshot preserves scouting keyboard focus (before: %s; after: %s)" % [owner, dialog.get_viewport().gui_get_focus_owner()])
	_apply(_fixtures.removed)
	_check(dialog._intel._precision.text.contains("未侦察") and not dialog._intel._details.text.contains("10 人"), "Same open scouting dialog clears a report removed from the latest safe projection")
	_apply(_fixtures.returned)
	_apply(_fixtures.expired)
	_check(dialog._intel._precision.text.contains("过期") and not dialog._intel._details.text.contains("10 人"), "Same scouting dialog also expires numbers at new server time")
	root.size = Vector2i(390, 844)
	dialog._fit_window()
	await _settle()
	await _capture("04-scouting-client-isolatedfixture-expired-390")
	dialog.hide()


func _test_marches() -> void:
	root.size = Vector2i(1280, 844)
	_apply(_fixtures.outbound)
	_client._marches_dialog()
	await _settle()
	_check(_client._march_labels.size() == 4, "Main march modal renders all four actual outgoing scout queues")
	_check(_find_button(_client._dialog, "召回") == null and _find_button(_client._dialog, "进入战斗") == null, "Scouts never synthesize unsupported recall or battle controls")
	_client._refresh_scout_marches()
	_check(_labels(_client._dialog).contains("侦察途中"), "Outgoing scout phase is readable in the main march modal")
	var popup: AcceptDialog = _client._dialog
	_apply(_fixtures.returning)
	await _settle()
	_check(_client._dialog == popup and _labels(popup).contains("斥候返程") and _labels(popup).contains("损失 1人"), "Actual arrival updates the same open march modal to return and settled own losses")
	await _capture("05-scouting-client-isolatedfixture-marches-return-1280")
	_apply(_fixtures.returned)
	await _settle()
	_check(_client._dialog == popup and _labels(popup).contains("斥候已返城"), "Actual queue disappearance resolves the same open march modal without stale ETA")
	_client._marches_dialog()
	await _settle()
	_check(_client._march_labels.is_empty() and _labels(_client._dialog).contains("暂无外出军队"), "Reopening after real return removes completed scout entries")
	_check(_api.commands.size() == 1, "Arrival, return, expiry and all march reads record no extra gameplay commands")


func _test_identity_clear() -> void:
	_apply(_fixtures.returned)
	_open_scout("exact")
	_client._scouting._preview.pressed.emit()
	var late: Dictionary = _quote("exact")
	_api.quote_received.emit(late)
	_check(not _client._scouting._confirm.disabled, "Identity-switch regression starts with an active valid private scout quote")
	_api.mode = "shared"
	_api.mode_changed.emit("shared")
	await _settle()
	_check(_client._selected.is_empty() and _client._dispatch_intel_target.is_empty() and not is_instance_valid(_client._scouting) and not is_instance_valid(_client._dispatch_intel), "Identity change frees scout/dispatch controls and clears target intelligence immediately")
	_apply(_fixtures.sharedBlocked)
	_client._show_scouting(_fixtures.selected.exact)
	_api.quote_received.emit(late)
	_check(not is_instance_valid(_client._scouting) and _api.commands.size() == 1, "Shared main cannot reopen local scouts or revive a prior identity's quote")
	_client._dispatch_dialog(_fixtures.selected.exact)
	_check(not is_instance_valid(_client._dispatch_intel), "Shared ordinary wild dispatch cannot expose private intelligence panel")
