extends SceneTree

const GrowthView = preload("res://src/growth_route_view.gd")
const UI_FONT: Font = preload("res://assets/fonts/UI.tres")
var _checks: int = 0
var _failures: int = 0
var _routes: Array[Dictionary] = []
var _card: PanelContainer


func _initialize() -> void:
	var previous_cache: String = OS.get_user_data_dir().path_join("shader_cache")
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceGrowthTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("shader_cache"))
	# Rendering is already initialized: copy directory names only, never settings
	# or shader files, so native captures remain inside this isolated test user://.
	if DirAccess.dir_exists_absolute(previous_cache):
		for shader: String in DirAccess.get_directories_at(previous_cache):
			for version: String in DirAccess.get_directories_at(previous_cache.path_join(shader)):
				DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("shader_cache").path_join(shader).path_join(version))
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _fixture() -> Dictionary:
	return {"growth": {"shared": false, "reason": "", "stage": {"id": "first_battle", "title": "首战准备", "progress": 0.0, "total": 1.0},
		"current": {"id": "first_battle", "title": "准备军营 4 级", "description": "完成实际前置后补足三十名弓箭手，并等待出征部队返城。", "navigate": {"route": "inner", "target": "barracks", "label": "前往当前一步"}, "reason": ""},
		"gaps": [{"id": "building:barracks", "label": "军营", "current": 3.0, "required": 4.0, "missing": 1.0, "unit": "级"},
			{"id": "army:archer", "label": "弓箭兵", "current": 28.0, "required": 30.0, "missing": 2.0, "unit": "人"},
			{"id": "resource:stone", "label": "石料", "current": 3000.0, "required": 6000.0, "missing": 3000.0},
			{"id": "population", "label": "空闲人口", "current": 1.0, "required": 2.0, "missing": 1.0, "unit": "人"}],
		"speedup": {"ownedCount": 8.0, "items": [], "suggestion": {"itemId": "speed_build_1h", "itemName": "建造加速 · 1 小时", "count": 2.0,
			"targetName": "城内一号 · 军营 → 4 级", "waitSeconds": 3600.0, "workSeconds": 2400.0, "shortenMinSeconds": 2400.0, "shortenMaxSeconds": 2400.0,
			"remainingMinSeconds": 3600.0, "remainingMaxSeconds": 3600.0, "wasteMinSeconds": 1200.0, "wasteMaxSeconds": 1200.0, "conserve": false,
			"navigate": {"route": "inventory", "target": "speed_build_1h", "label": "查看已入库加速"}}},
		"advice": [{"id": "resources", "text": "石料还缺三千，先恢复城外生产，再按实际净产补足。", "navigate": {"route": "outer", "target": "quarry", "label": "恢复资源生产"}},
			{"id": "gift", "text": "还有已解锁补给可领取。", "navigate": {"route": "gift", "target": "", "label": "查看已解锁礼包"}}]}}


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var folder: String = "res://production/qa/evidence/story-010/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(root.get_texture().get_image().save_png(folder + name + ".png") == OK, "Growth fixture screenshot saves.")


func _run() -> void:
	root.size = Vector2i(390, 844)
	var host: Control = Control.new()
	host.size = Vector2(390, 844)
	host.theme = KingdomUiTheme.create(UI_FONT)
	root.add_child(host)
	var background: ColorRect = ColorRect.new()
	background.color = KingdomUiTheme.INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(background)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(20, 20)
	scroll.size = Vector2(350, 800)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(scroll)
	_card = GrowthView.new()
	scroll.add_child(_card)
	_card.navigate_requested.connect(func(route: String, target: String) -> void: _routes.append({"route": route, "target": target}))
	var view: Dictionary = _fixture()
	_card.update_view(view)
	await _settle()
	_check(_card.size.x <= 350.0, "Growth card must fit the 390-width modal without forcing horizontal overflow.")
	_check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page + 1.0, "Long growth guidance must wrap without horizontal scrolling.")
	_check(_card._speedup.text.contains("建造加速 · 1 小时 · 库存 2 件") and not _card._speedup.text.contains("×2"), "The item count explicitly means inventory stock, never the number consumed in one quote.")
	await _capture("growth-390")
	_check(_card._gaps.text.contains("军营 3 / 4级") and not _card._gaps.text.contains("3.0"), "JSON numeric values must render as integer prerequisite counts.")
	_check(not _card._gaps.text.contains("空闲人口"), "Default card shows only three prerequisite rows.")
	_card._more.emit_signal("pressed")
	_check(_card._gaps.text.contains("空闲人口") and _card._expanded, "All real prerequisite gaps remain available on expansion.")
	var action: Button = _card._current
	_card.focus_current()
	_check(root.gui_get_focus_owner() == action, "Host can put keyboard focus on the current step.")
	_card._current.emit_signal("pressed")
	_check(_routes.back() == {"route": "inner", "target": "barracks"}, "Current step emits only its navigation route and canonical target.")
	_card._speedup_action.emit_signal("pressed")
	_check(_routes.back() == {"route": "inventory", "target": "speed_build_1h"}, "Acceleration action opens inventory without consuming an item.")
	_check(_card._speedup.text.contains("含排队 1时00分") and _card._speedup.text.contains("使用后还需 1时00分"), "Queued acceleration must keep its waiting time in the visible result.")
	_check(_card._speedup.text.contains("20分00秒 不保留"), "Unused item duration must be disclosed.")
	_card.update_view(view.duplicate(true))
	_check(_card._current == action and _card._expanded, "Snapshot updates preserve controls and expanded prerequisite state.")
	_check(root.gui_get_focus_owner() == action, "Updating the same step preserves keyboard focus.")
	_card.set_navigation_state(true, true)
	var count: int = _routes.size()
	_card._current.emit_signal("pressed")
	_card._speedup_action.emit_signal("pressed")
	_card._advice_actions[0].emit_signal("pressed")
	_check(_routes.size() == count and _card._current.disabled, "Pending mutation blocks even synthetic navigation clicks.")
	_card.set_navigation_state(false, false)
	_card._current.emit_signal("pressed")
	_check(_routes.size() == count and _card._status.text.contains("连接"), "Offline state prevents stale navigation.")
	_card.set_navigation_state(true, false)
	_check(not _card._current.disabled, "Acknowledged connected state restores route navigation.")
	view.growth.speedup.suggestion.conserve = true
	_card.update_view(view)
	_check(_card._speedup.text.contains("保留大加速给长工程"), "Oversized earned accelerations advise conservation without imposing a new rule.")
	view.growth.speedup.suggestion = null
	_card.update_view(view)
	_check(_card._speedup.text.contains("已入库可用加速 8 件") and _card._speedup.text.contains("尚无可推荐"), "Owned earned items stay visible when there is no legal current queue.")
	root.size = Vector2i(1280, 844)
	host.size = Vector2(1280, 844)
	scroll.position = Vector2(280, 20)
	scroll.size = Vector2(720, 800)
	scroll.scroll_vertical = 0
	_card.update_view(_fixture())
	await _settle()
	_check(_card.size.x <= 720.0 and scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page + 1.0, "Desktop growth modal fits a readable 720-width column inside a 1280 window.")
	await _capture("growth-1280")
	view.growth.stage = {"id": "chapter2", "title": "第二章 · 平定北境", "progress": 1.0, "total": 6.0}
	view.growth.current = {"id": "occupy:north_granary", "title": "占领北原粮仓", "description": "已经占领驿道，可以继续夺回粮仓。", "navigate": {"route": "world", "target": "north_granary", "label": "查看目标与配兵"}}
	view.growth.gaps = []
	_card.update_view(view)
	_card._current.emit_signal("pressed")
	_check(_routes.back() == {"route": "world", "target": "north_granary"} and _card._stage.text.contains("1 / 6"), "Chapter snapshots immediately advance the action and occupation count.")
	_check(not _card._gaps.visible and not _card._more.visible, "Finished prerequisite groups do not leave stale gaps or expansion controls.")
	view.growth.shared = true
	view.growth.reason = "共享演练尚未接入私人据点成长路线"
	view.growth.current = null
	_card.update_view(view)
	count = _routes.size()
	_card._current.emit_signal("pressed")
	_card._speedup_action.emit_signal("pressed")
	_check(_routes.size() == count and not _card._current.visible and not _card._speedup_action.visible, "Shared mode hides and blocks all private route buttons.")
	_check(_card._description.text.contains("共享") and not _card._speedup.visible and not _card._advice[0].visible, "Shared mode clears owned private items and recovery guidance.")
	_card.update_view({})
	_check(_card._title.text.contains("读取") and not _card._current.visible and not _card._speedup.visible, "Identity/reset empty view clears previous chapter data and item counts.")
	host.queue_free()
	await _settle()
	print("GROWTH_ROUTE_TEST_CHECKS=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
