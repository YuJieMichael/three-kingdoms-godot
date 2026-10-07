extends SceneTree

const ActivityScript: Script = preload("res://src/army_activity_bar.gd")
const ThemeScript: Script = preload("res://src/ui_theme.gd")
const UI_FONT: Font = preload("res://assets/fonts/UI.tres")
const NOW: float = 1800000000000.0
var _checks: int = 0
var _failures: int = 0
var _routes: Array[String] = []
var _bar: PanelContainer
var _host: Control
var _column: VBoxContainer


func _initialize() -> void:
	# Fixtures do not initialize the API, canonical simulation, or player save.
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceArmyActivityTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for _frame: int in range(4):
		await process_frame


func _fixture() -> Dictionary:
	return {"city": {"id": "capital", "name": "青溪城"}, "cityList": [{"id": "capital", "name": "青溪城"}, {"id": "north", "name": "北原城"}],
		"units": [{"id": "archer", "name": "弓箭兵"}, {"id": "scout", "name": "斥候"}],
		"queues": {"train": [{"id": "archer", "count": 30, "end": NOW + 30000}, {"id": "scout", "count": 10, "end": NOW + 50000}]},
		"marches": [
			{"id": "expedition:capital:field", "label": "林朔 · 野地", "sourceCity": "capital", "status": "march", "arrive": NOW + 60000, "count": 30},
			{"id": "logistics:1", "label": "物资运输", "sourceCity": "north", "status": "outbound", "arrive": NOW + 45000, "count": 12},
			{"id": "scout:north:1", "label": "河畔荒田", "type": "scout", "sourceCity": "north", "status": "return", "arrive": NOW + 90000, "nextArrival": NOW + 10000, "count": 18, "sentCount": 20, "lost": 2},
			{"id": "garrison:capital:hill", "label": "苏砚 · 驻扎山岭", "sourceCity": "capital", "status": "return", "arrive": NOW - 1000, "returnAt": NOW + 20000, "count": 22},
			{"id": "garrison:north:camp", "label": "卫衡 · 驻扎营地", "sourceCity": "north", "status": "stationed", "arrive": null, "count": 50},
			{"id": "shared-aid", "label": "援军 · 来军", "shared": true, "incoming": true, "sourceCity": "capital", "status": "stationed", "count": null},
			{"id": "shared-attack", "label": "讨伐 · 来军", "shared": true, "incoming": true, "sourceCity": "capital", "status": "march", "arrive": NOW + 120000, "count": null},
			{"id": "battle:capital", "label": "交战队", "sourceCity": "capital", "status": "battle", "count": 15},
			{"id": "done", "label": "已完成", "status": "done", "count": 5},
			{"id": "not-stationed", "label": "采集", "status": "gathering", "count": 5}],
		# These are other projections of the same groups; adding them would double
		# count. Training intentionally remains the current city queue only.
		"realmManagement": {"logistics": [{"id": "1"}], "cities": [{"id": "north", "trainQueue": [{"id": "archer", "count": 900}]}]},
		"shared": {"marches": [{"id": "shared-attack"}], "reports": [{"id": "shared-report"}]},
		"reports": [{"id": "older", "title": "山岭掠夺", "at": NOW - 60000, "won": false}, {"id": "newer", "title": "北原营地", "at": NOW - 5000, "won": true}]}


func _build_shell() -> void:
	_host = Control.new()
	_host.theme = ThemeScript.create(UI_FONT)
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_host)
	var background: ColorRect = ColorRect.new()
	background.color = Color("243332")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_host.add_child(margin)
	_column = VBoxContainer.new()
	margin.add_child(_column)
	_bar = ActivityScript.new() as PanelContainer
	_column.add_child(_bar)
	_bar.route_requested.connect(func(section: String) -> void: _routes.append(section))
	var map_space: ColorRect = ColorRect.new()
	map_space.color = Color("34493a")
	map_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(map_space)
	var fixture_label: Label = Label.new()
	fixture_label.text = "军队动态 HUD · 只读 Fixture"
	fixture_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fixture_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	map_space.add_child(fixture_label)


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var folder: String = OS.get_user_data_dir().path_join("army-activity-evidence")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			folder = argument.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join(name + ".png")
	_check(root.get_texture().get_image().save_png(path) == OK, "Army activity fixture screenshot saves")
	print("Army activity evidence: " + path)


func _bounds(width: int) -> void:
	_check(_bar.get_global_rect().end.x <= width - 15, "Activity HUD fits %dpx without horizontal overflow" % width)
	_check(_bar.size.y <= 90, "Activity HUD stays shallow enough to leave room for the map at %dpx" % width)
	for section: String in ActivityScript.SECTIONS:
		var button: Button = _bar._buttons[section]
		_check(button.size.y >= 44 and button.get_global_rect().end.x <= width - 20, "%s remains touch sized and inside the HUD at %dpx" % [section, width])
	_check(_bar._row.columns == 4, "Both layouts keep one row of four activity shortcuts")


func _run() -> void:
	root.size = Vector2i(390, 844)
	_build_shell()
	_bar.set_compact(true)
	var view: Dictionary = _fixture()
	var original: String = JSON.stringify(view)
	_bar.update_view(view, NOW)
	await _settle()
	_check(JSON.stringify(view) == original, "Activity projection leaves the source DTO unchanged")
	_check(_bar._training.size() == 2, "Training counts only current-city queues, never another city's raw queue")
	_check(_bar._outbound_count == 3 and _bar._return_count == 2 and _bar._battle_count == 1, "All-city expeditions, logistics, scouts, and shared marches each enter their actual phase once")
	_check(_bar._marches.size() == 6 and _bar._stationed.size() == 2, "Stationed groups are separate from outgoing/return/battle, and unrelated phases are excluded")
	_check(_bar._reports.size() == 2 and _bar._buttons.reports.text == "战报2", "Report indicator uses the actual normalized array, with no duplicate or unread count")
	_check(_bar._buttons.training.tooltip_text.contains("青溪城") and _bar._buttons.training.tooltip_text.contains("弓箭兵 ×30"), "Training retains the real current city, unit, and batch quantity")
	_check(_bar._summary.text.contains("斥候") and _bar._summary.text.contains("北原城") and _bar._summary.text.contains("返程") and _bar._summary.text.contains("0分10秒"), "Earliest scout leg uses its own nextArrival and recognizable phase/source city")
	_check(_bar._buttons.marches.tooltip_text.contains("苏砚 · 驻扎山岭") and _bar._buttons.marches.tooltip_text.contains("0分20秒"), "Returning garrison uses returnAt rather than stale outgoing arrival")
	_check(_bar._buttons.stationed.tooltip_text.contains("援军 · 来军 · 青溪城 · 兵力未公开") and not _bar._buttons.stationed.tooltip_text.contains(" · 0人"), "Hidden shared stationed strength stays unknown rather than fabricated zero")
	_check(_bar._buttons.reports.tooltip_text.contains("北原营地 · 胜利") and not _bar._buttons.reports.tooltip_text.contains("未读"), "Latest report is source grounded and does not invent reading state")
	_bounds(390)
	await _capture("army-activity-390")
	var focus: Button = _bar._buttons.marches
	focus.grab_focus()
	_check(root.gui_get_focus_owner() == focus, "Activity shortcuts accept keyboard focus")
	_bar.update_view(view.duplicate(true), NOW + 1000)
	_bar.refresh_clock(NOW + 5000)
	_check(_bar._buttons.marches == focus and root.gui_get_focus_owner() == focus, "Snapshots and clock refresh preserve the focused control")
	_check(not focus.focus_neighbor_left.is_empty() and not focus.focus_neighbor_right.is_empty(), "Activity row defines keyboard/gamepad neighbours")
	var routes_before: int = _routes.size()
	for section: String in ActivityScript.SECTIONS:
		(_bar._buttons[section] as Button).pressed.emit()
	_check(_routes.slice(routes_before) == ["training", "marches", "stationed", "reports"], "Shortcuts emit exactly the four navigation routes")
	_check(not _bar.has_signal("command_requested") and not _bar.has_signal("quote_requested"), "HUD exposes no gameplay mutation or quote interface")
	_check(_bar.get_node_or_null("GameApi") == null and not _bar.is_processing(), "HUD neither owns an API nor polls gameplay each frame")
	_bar.refresh_clock(NOW + 130000)
	_check(_bar._summary.text.contains("待结算") and not _bar._summary.text.contains("已抵达"), "Expired countdown requests settlement evidence rather than declaring arrival")
	_check(_bar._training.size() == 2 and _bar._marches.size() == 6 and _bar._stationed.size() == 2, "Local clock expiry does not remove jobs, zero armies, or move groups into stationed")
	_check(_bar._buttons.training.tooltip_text.contains("待结算") and _bar._buttons.marches.tooltip_text.contains("待结算"), "All expired training and march deadlines retain a pending state")
	view.queues.train.clear()
	view.marches.clear()
	view.reports.clear()
	_bar.refresh_clock(NOW + 140000)
	_check(_bar._training.size() == 2 and _bar._marches.size() == 6 and _bar._reports.size() == 2, "Caller mutations cannot alter the cached snapshot between updates")
	var duplicate: Dictionary = _fixture()
	duplicate.marches.append(duplicate.marches[0].duplicate(true))
	_bar.update_view(duplicate, NOW)
	_check(_bar._marches.size() == 6, "Duplicate normalized group identity is counted once")
	duplicate.city = {"id": "north", "name": "北原城"}
	duplicate.queues.train = [{"id": "scout", "count": 7, "end": NOW + 8000}]
	_bar.update_view(duplicate, NOW)
	_check(_bar._buttons.training.tooltip_text.contains("本城训练 · 北原城 · 1项") and not _bar._buttons.training.tooltip_text.contains("弓箭兵 ×30"), "Switching cities replaces only the current training context")
	_check(_bar._marches.size() == 6 and _bar._summary.text.contains("北原城训练 · 斥候 ×7"), "City switch preserves all-city marches and uses current training's own clock")
	_bar.set_connected(false)
	routes_before = _routes.size()
	for section: String in ActivityScript.SECTIONS:
		(_bar._buttons[section] as Button).pressed.emit()
	_check(_routes.size() == routes_before and _bar._summary.text.begins_with("离线"), "Offline state labels known data and blocks even synthetic stale navigation")
	_bar.clear_context()
	_check(_bar._summary.text == "连接后显示军队动态" and _bar._view.is_empty() and _bar._timed_items.is_empty(), "Identity clear immediately drops prior names, deadlines, and snapshot data")
	_check(not _bar._buttons.training.tooltip_text.contains("北原") and _bar._buttons.reports.text == "战报—", "Identity clear removes prior player activity from shortcuts and tooltips")
	_bar.set_connected(true)
	(_bar._buttons.training as Button).pressed.emit()
	_check(_routes.size() == routes_before, "Reconnect without a fresh context cannot open an old route")
	var empty: Dictionary = {"city": {"id": "capital", "name": "青溪城"}, "queues": {"train": []}, "marches": [], "reports": []}
	_bar.update_view(empty, NOW)
	_check(_bar._summary.text.contains("无训练队列") and _bar._buttons.marches.text == "行军0", "Actual empty snapshot shows confirmed zero activity")
	var reports_only: Dictionary = _fixture()
	reports_only.queues.train.clear()
	reports_only.marches.clear()
	_bar.update_view(reports_only, NOW)
	_check(_bar._summary.text == "最新战报 · 北原营地 · 胜利", "When no clocks are active, actual latest report occupies the summary")
	var missing_time: Dictionary = empty.duplicate(true)
	missing_time.queues.train = [{"id": "archer", "count": 3}]
	_bar.update_view(missing_time, NOW)
	_check(_bar._summary.text.contains("时间待同步") and not _bar._summary.text.contains("待结算"), "Missing deadline remains unknown instead of pretending expired")
	root.size = Vector2i(1280, 800)
	_bar.set_compact(false)
	_bar.update_view(_fixture(), NOW)
	await _settle()
	_bounds(1280)
	_check(_bar._buttons.training.text == "本城训练 2" and _bar._buttons.marches.text.contains("全域行军 6"), "Desktop labels explain current-city training versus all-city activity")
	await _capture("army-activity-1280")
	print("Army activity checks: %d; failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)
