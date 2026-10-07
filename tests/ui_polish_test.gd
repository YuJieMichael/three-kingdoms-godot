extends SceneTree

class ApiProbe extends "res://src/game_api.gd":
	var pending: bool = false
	var commands: Array = []
	func _ready() -> void:
		pass
	func _has_mutation() -> bool:
		return pending
	func command(type: String, args: Array = [], _source: String = "") -> void:
		if not connected or pending:
			return
		commands.append({"type": type, "args": args})
		pending = true

class ClientProbe extends "res://src/main.gd":
	func _ready() -> void:
		_smoke = true
		theme = _make_theme()
		_build_shell()
		add_child(api)
		_audio = AudioScript.new() as KingdomPresentationAudio
		add_child(_audio)
		_initialize_presentation()
		_show_page("world")
	func _check_smoke() -> void:
		pass

var _checks: int = 0
var _failures: int = 0
var _client: ClientProbe
var _api: ApiProbe

func _initialize() -> void:
	var cache: String = OS.get_user_data_dir().path_join("shader_cache")
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceUiTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
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
	for i: int in 5:
		await process_frame

func _capture(name: String) -> void:
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		var folder: String = "res://production/qa/evidence/story-009/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		root.get_texture().get_image().save_png(folder + name + ".png")

func _find(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find(child, text)
		if found != null:
			return found
	return null

func _run() -> void:
	if not Engine.has_singleton("SoundManager"):
		root.add_child(load("res://addons/sound_manager/sound_manager.gd").new())
	if not Engine.has_singleton("DialogueManager"):
		root.add_child(load("res://addons/dialogue_manager/dialogue_manager.gd").new())
	var output: Array = []
	var node: String = OS.get_environment("TK_NODE")
	if node.is_empty() or OS.execute(node, [ProjectSettings.globalize_path("res://tests/helpers/playable-view.mjs")], output) != 0:
		_check(false, "TK_NODE must provide the isolated canonical fixture")
		quit(1)
		return
	var fixture: Dictionary = JSON.parse_string(str(output[0]))
	_client = ClientProbe.new()
	_api = ApiProbe.new()
	_api.connected = true
	_client.api = _api
	_client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_client)
	_client._receive_snapshot(fixture)
	_client._receive_world(fixture.worldSample)
	await _settle()
	for width: int in [390, 768, 1000, 1280]:
		root.size = Vector2i(width, 720 if width == 1280 else 844)
		await _settle()
		for page: String in ["world", "city", "army", "generals", "reports"]:
			_client._show_page(page)
			await _settle()
			_check(_client.get_child(1).get_combined_minimum_size().x <= width, "%s shell fits %dpx" % [page, width])
			_check(_client._body.get_global_rect().end.x <= width, "%s body stays inside %dpx viewport" % [page, width])
			_check(_client._toast.get_global_rect().end.y <= root.size.y + 1, "%s feedback stays visible at %dpx" % [page, width])
			_check(_client._compact_objective_panel.visible and not _client._sidebar_panel.visible, "Narrow objective remains visible at %dpx" % width)
			for id: String in _client._nav_buttons:
				var button: Button = _client._nav_buttons[id]
				_check(button.button_pressed == (id == page), "Navigation state follows %s" % page)
				_check(button.size.y >= 44, "Navigation touch target is 44px")
		_client._show_page("world")
		await _settle()
		if width in [390, 1280]:
			await _capture("hud-%d" % width)
		_client._tasks_dialog()
		await _settle()
		var tabs: TabContainer = _client._dialog.find_child("TransactionsTabs", true, false) as TabContainer
		_check(tabs != null and tabs.get_tab_count() == 4, "Transactions group four navigation categories")
		_check(_client._dialog.get_viewport().gui_get_focus_owner() == _client._dialog.get_ok_button(), "Modal initially focuses close, not a resource command")
		for caption: String in ["领取已解锁礼包", "城外资源", "研究", "宝物与物资", "按键设置", "联机大厅", "黄巾来袭", "玩家战争"]:
			_check(_find(_client._dialog, caption) != null, "Transactions preserve " + caption)
		for tab: int in 4:
			tabs.current_tab = tab
			await _settle()
			var scroll: ScrollContainer = tabs.get_child(tab)
			_check(scroll.get_child(0).get_combined_minimum_size().x <= scroll.size.x, "Transaction group fits %dpx" % width)
			if width in [390, 1280] and tab == 1:
				await _capture("transactions-%d" % width)
		_client._dialog.hide()
		await _settle()
	await _test_state_and_focus(fixture)
	_client._ui_feedback.set_reduced_motion(true)
	_client._open_menu()
	_client._menu._tabs.current_tab = 2
	await _settle()
	_check(_client._menu._reduced_motion.button_pressed, "Display checkbox uses real preferences")
	await _capture("display-settings")
	_check(_api.commands.is_empty(), "Layout, menus, resize and preferences send no gameplay commands")
	_client.queue_free()
	await _settle()
	print("UI_POLISH_TEST_CHECKS=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures else 0)

func _test_state_and_focus(fixture: Dictionary) -> void:
	var snapshot: Dictionary = fixture.duplicate(true)
	snapshot.view.objective = {"title": "甲私目标", "description": "甲私奖励说明", "ready": true, "action": "claimMission", "reward": {"gold": 1234}}
	snapshot.view.res.food = 9381
	snapshot.view.caps.food = 100
	_client._receive_snapshot(snapshot)
	_check(_client._compact_objective_title.text.contains("甲私目标") and _client._compact_objective_button.text == "领取", "Compact target reflects real readiness")
	_check(_client._resources.food.text.contains("超仓") and _client._resources.food.tooltip_text.contains("9381"), "Over-cap status and precise tooltip remain explicit")
	_client._objective_action()
	_check(_api.commands.size() == 1 and _api.commands[0].type == "claimMission", "Ready goal sends its actual command")
	_check(_client._compact_objective_button.disabled and _client._objective_button.disabled, "Pending commands lock both goal actions")
	_client._objective_action()
	_check(_api.commands.size() == 1, "Repeated goal activation sends no second command")
	_api.commands.clear()
	_api.pending = false
	_client._command_completed("claimMission", {})
	_check(not _client._compact_objective_button.disabled and not _client._objective_button.disabled, "Receipt restores both goal actions")
	_api.connected = false
	_client._connection_changed("断线", false)
	_check(_client._compact_objective_button.disabled and _client._connection_indicator.text == "连接中断", "Disconnected goals remain safe and visibly offline")
	_client._mode_changed("private")
	_check(not _client._compact_objective_title.text.contains("甲私") and not _client._compact_objective_text.text.contains("甲私"), "Identity replacement clears compact goal")
	_check(_client._compact_objective_text.tooltip_text.is_empty() and _client._resources.food.tooltip_text.is_empty(), "Identity replacement clears private tooltips")
	_api.mode = "shared"
	_api.room = {"name": "测试房间"}
	_api.connected = true
	_client._receive_snapshot(fixture)
	_check(_client._compact_objective_title.text.contains("测试房间") and _client._compact_objective_button.text == "前往", "Shared target uses room instructions instead of private reward")
	_api.mode = "private"
	_client._receive_snapshot(fixture)
	_client._nav_buttons.city.grab_focus()
	_client._tasks_dialog()
	await _settle()
	_client._show_management("market")
	await _settle()
	_check(_client._management.visible and not _client._dialog.visible, "Transactions transfer to one feature window")
	_check(_client._shortcut_blocked(), "Feature transfer keeps global shortcuts blocked")
	_client._management.hide()
	await _settle()
	_check(_client.get_viewport().gui_get_focus_owner() == _client._nav_buttons.city, "Closing feature restores original visible opener")
