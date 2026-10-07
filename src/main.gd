extends Control

const ApiScript: Script = preload("res://src/game_api.gd")
const MapScript: Script = preload("res://src/world_map.gd")
const CityScript: Script = preload("res://src/city_view.gd")
const SuburbScript: Script = preload("res://src/suburb_view.gd")
const BattleScript: Script = preload("res://src/battle_view.gd")
const ManagementScript: Script = preload("res://src/management_dialog.gd")
const InputSettingsScript: Script = preload("res://src/input_settings.gd")
const InputSettingsDialogScript: Script = preload("res://src/input_settings_dialog.gd")
const PvpDialogScript: Script = preload("res://src/pvp_dialog.gd")
const LobbyApiScript: Script = preload("res://src/lobby_api.gd")
const LobbyDialogScript: Script = preload("res://src/lobby_dialog.gd")
const AudioScript: Script = preload("res://src/presentation_audio.gd")
const MenuScript: Script = preload("res://src/presentation_menu.gd")
const DialogueScript: Script = preload("res://src/presentation_dialogue.gd")
const HeroScript: Script = preload("res://src/hero_dialog.gd")
const ProgressionScript: Script = preload("res://src/progression_dialog.gd")
const WarManagementScript: Script = preload("res://src/war_management_dialog.gd")
const InventoryScript: Script = preload("res://src/inventory_dialog.gd")
const RealmScript: Script = preload("res://src/realm_dialog.gd")
const UiThemeScript: Script = preload("res://src/ui_theme.gd")
const UiFeedbackScript: Script = preload("res://src/ui_feedback.gd")
const GrowthRouteScript: Script = preload("res://src/growth_route_view.gd")
const ReportEconomyScript: Script = preload("res://src/report_economy_view.gd")
const IntelPanelScript: Script = preload("res://src/intel_panel.gd")
const DispatchDialogScript: Script = preload("res://src/dispatch_dialog.gd")
const ActivityBarScript: Script = preload("res://src/army_activity_bar.gd")
const ConstructionPanelScript: Script = preload("res://src/city_construction_panel.gd")
const CapacityCompareScript: Script = preload("res://src/city_capacity_compare.gd")
const NotificationScript: Script = preload("res://src/notification_center.gd")
const ReportLootScript: Script = preload("res://src/report_loot_view.gd")
const PostBattleScript: Script = preload("res://src/post_battle_actions.gd")
const RaidTargetsScript: Script = preload("res://src/raid_targets_view.gd")
const PracticeScript: Script = preload("res://src/practice_dialog.gd")
const BattleReviewScript: Script = preload("res://src/battle_review_view.gd")
const CountyGovernanceScript: Script = preload("res://src/county_governance_view.gd")
const FONT: Font = preload("res://assets/fonts/UI.tres")
const RES_NAMES: Dictionary = {"food": "粮草", "wood": "木材", "stone": "石料", "iron": "铁锭", "gold": "黄金"}
const RES_SHORT_NAMES: Dictionary = {"food": "粮", "wood": "木", "stone": "石", "iron": "铁", "gold": "金"}
const CITY_BUILD_USES: Dictionary = {
	"house": "扩充平民人口，可建设多座", "academy": "研究科技，同城同时研究一项", "inn": "查看和招募候选将领",
	"market": "买卖资源，调配城池库存", "warehouse": "增加储量，保护四种资源", "drill": "出征指挥，增加队伍名额",
	"barracks": "训练士兵，发展军队兵种", "tavern": "提供招募与收容将领的房间", "embassy": "联盟与援军接待设施",
	"smith": "发展军事武器和装备", "workshop": "发展攻城器械制造", "stable": "发展骑兵所需设施",
	"post": "加快己方与友城运输", "beacon": "来袭预警与情报设施", "hall": "城务管理，扩展城外名额", "wall": "庇护守军，建设城防"
}

var api: KingdomApi
var _view: Dictionary = {}
var _state: Dictionary = {}
var _page: String = "world"
var _selected: Dictionary = {}
var _scouting_target_id: String = ""
var _last_structure: String = ""
var _map: KingdomWorldMap
var _city: KingdomCityView
var _suburb: KingdomSuburbView
var _city_zone: String = "inner"
var _battle: KingdomBattleView
var _center: Control
var _center_area: VBoxContainer
var _city_toolbar: HFlowContainer
var _side: VBoxContainer
var _detail: VBoxContainer
var _nav: HBoxContainer
var _status: Label
var _toast: Label
var _notifications: KingdomNotificationCenter
var _messages_button: Button
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
var _tasks_labels: Array[Label] = []
var _tasks_action: Button
var _save_text: TextEdit
var _world: Dictionary = {}
var _clock: Timer
var _pending_battle: bool = false
var _pending_recall: Dictionary = {}
var _management: KingdomManagementDialog
var input_settings: KingdomInputSettings
var _input_settings_dialog: KingdomInputSettingsDialog
var _input_settings_button: Button
var _shortcut_hint: Label
var _nav_buttons: Dictionary = {}
var _map_home_button: Button
var _map_toolbar: HFlowContainer
var _map_filter: OptionButton
var _map_filter_kind: String = "all"
var _input_window_active: bool = true
var _pan_key_active: bool = false
var _pvp: KingdomPvpDialog
var _pvp_button: Button
var _lobby_button: Button
var _lobby_api: KingdomLobbyApi
var _lobby: KingdomLobbyDialog
var _audio: KingdomPresentationAudio
var _menu: KingdomPresentationMenu
var _heroes: KingdomHeroDialog
var _progression: KingdomProgressionDialog
var _war_management: KingdomWarManagementDialog
var _inventory: KingdomInventoryDialog
var _realm: KingdomRealmDialog
var _guide: KingdomPresentationDialogue
var _ui_feedback: KingdomUiFeedback
var _compact_objective_panel: PanelContainer
var _compact_objective_title: Label
var _compact_objective_text: Label
var _compact_objective_button: Button
var _connection_indicator: Label
var _popup_return_focus: WeakRef
var _growth_button: Button
var _growth_route: KingdomGrowthRouteView
var _report_economy: KingdomReportEconomyView
var _report_loot: KingdomReportLootView
var _report_recovery: KingdomPostBattleActions
var _raid_targets: KingdomRaidTargetsView
var _report_key: String = ""
var _economy_signature: String = ""
var _scouting: KingdomScoutingDialog
var _detail_intel: KingdomIntelPanel
var _dispatch_intel: KingdomIntelPanel
var _dispatch_intel_target: Dictionary = {}
var _march_labels: Dictionary = {}
var _march_action_buttons: Dictionary = {}
var _march_content: VBoxContainer
var _march_filter: String = "all"
var _march_empty: Label
var _intel_server_offset: float = 0.0
var _shell_root: VBoxContainer
var _shell_margin: MarginContainer
var _sidebar_expanded: bool = false
var _task_toggle: Button
var _compact_growth_button: Button
var _resource_buttons: Dictionary = {}
var _resource_detail_labels: Dictionary = {}
var _activity_bar: KingdomArmyActivityBar
var _resource_status: Label
var _city_construction_panel: KingdomCityConstructionPanel
var _city_construction_site: int = -1
var _city_construction_source: String = ""
var _compact_objective_expand: Button
var _city_objective_expanded: bool = false
var _city_status_row: HBoxContainer
var _city_queue_button: Button
var _city_military_button: Button
var _practice: KingdomPracticeDialog
var _practice_button: Button
var _report_review: KingdomBattleReviewView
var _county_governance: KingdomCountyGovernanceView
var _county_source: String = ""
var _county_identity_label: Label
var _county_baseline: bool = false
var _county_conquest: Dictionary = {}
var _county_conquest_button: Button
var _county_after_switch: String = ""
var _county_battle_pending: Dictionary = {}
var _first_steps: HFlowContainer

func _ready() -> void:
	get_window().title = "山河策"
	_smoke = OS.get_cmdline_user_args().has("--smoke")
	_initialize_inputs()
	_sync_web_scale()
	theme = _make_theme()
	_audio = AudioScript.new() as KingdomPresentationAudio
	add_child(_audio)
	_build_shell()
	_initialize_presentation()
	api = ApiScript.new() as KingdomApi
	add_child(api)
	api.snapshot_received.connect(_receive_snapshot)
	api.world_received.connect(_receive_world)
	api.status_changed.connect(_connection_changed)
	api.request_failed.connect(_request_failed)
	api.command_completed.connect(_command_completed)
	api.export_received.connect(_show_export)
	api.mode_changed.connect(_mode_changed)
	api.quote_received.connect(_receive_quote)
	_clock = Timer.new()
	_clock.wait_time = 1.0
	_clock.timeout.connect(_refresh_clock)
	add_child(_clock)
	_clock.start()
	_show_page("world")
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var explicit_url: String = ""
	var lobby_url: String = ""
	for arg: String in arguments:
		if arg.begins_with("--api="):
			explicit_url = arg.trim_prefix("--api=")
		elif arg.begins_with("--lobby="):
			lobby_url = arg.trim_prefix("--lobby=")
	var room_invite: String = _web_room_invitation()
	if not explicit_url.is_empty():
		api.connect_to(explicit_url, OS.get_environment("TK_BRIDGE_TOKEN"))
	elif not lobby_url.is_empty() or not room_invite.is_empty():
		_status.text = "请选择自己的房间城主"
		_show_lobby(room_invite, lobby_url)
	else:
		api.start_local()
	if _smoke:
		get_tree().create_timer(25.0).timeout.connect(func() -> void:
			if not (_smoke_snapshot and _smoke_world):
				push_error("GODOT_SMOKE_FAILED: no canonical state/world")
				get_tree().quit(1))

func _initialize_inputs() -> void:
	if input_settings == null:
		input_settings = InputSettingsScript.new() as KingdomInputSettings
	input_settings.initialize()
	if not input_settings.bindings_changed.is_connected(_update_shortcut_help):
		input_settings.bindings_changed.connect(_update_shortcut_help)
	if not get_window().focus_entered.is_connected(_input_focus_entered):
		get_window().focus_entered.connect(_input_focus_entered)
		get_window().focus_exited.connect(_input_focus_exited)

func _initialize_presentation() -> void:
	if not is_instance_valid(_ui_feedback):
		_ui_feedback = UiFeedbackScript.new() as KingdomUiFeedback
		add_child(_ui_feedback)
	_menu = MenuScript.new() as KingdomPresentationMenu
	_menu.audio = _audio
	_menu.feedback = _ui_feedback
	_menu.theme = theme
	add_child(_menu)
	_guide = DialogueScript.new() as KingdomPresentationDialogue
	_guide.audio = _audio
	_guide.theme = theme
	add_child(_guide)
	_menu.input_requested.connect(_show_input_settings)
	_menu.guide_requested.connect(_guide.start)
	_menu.practice_requested.connect(_show_practice)
	_menu.save_requested.connect(_save_dialog)
	_menu.connection_requested.connect(_show_lobby)
	_menu.visibility_changed.connect(_on_popup_visibility.bind(_menu))
	_guide.visibility_changed.connect(_on_popup_visibility.bind(_guide))
	_watch_buttons(self)
	if not _smoke and not Array(OS.get_cmdline_user_args()).any(func(value: String) -> bool: return value.begins_with("--lobby=")):
		_menu.call_deferred("open_menu")

func _open_menu() -> void:
	_remember_keyboard_focus()
	_stop_keyboard_pan()
	_hide_feature_panels()
	if is_instance_valid(_menu):
		_menu.open_menu()

func _input_focus_entered() -> void:
	_input_window_active = true

func _input_focus_exited() -> void:
	_input_window_active = false
	_stop_keyboard_pan()

func _stop_keyboard_pan() -> void:
	_pan_key_active = false
	if input_settings != null:
		for action: String in ["tk_map_left", "tk_map_right", "tk_map_up", "tk_map_down"]:
			Input.action_release(action)

func _visible_popup(node: Node) -> bool:
	for child: Node in node.get_children(true):
		if child is Window and child.visible:
			return true
		if _visible_popup(child):
			return true
	return false

func _shortcut_blocked() -> bool:
	if not _input_window_active or _visible_popup(self):
		return true
	var focus: Control = get_viewport().gui_get_focus_owner()
	return is_instance_valid(focus) and focus.is_visible_in_tree() and (focus is LineEdit or focus is TextEdit)

func _process(delta: float) -> void:
	if not _pan_key_active:
		return
	if input_settings == null or _page != "world" or not is_instance_valid(_map) or _shortcut_blocked():
		_stop_keyboard_pan()
		return
	var direction: Vector2 = input_settings.movement_vector()
	if direction.is_zero_approx():
		var held: bool = false
		for action: String in ["tk_map_left", "tk_map_right", "tk_map_up", "tk_map_down"]:
			held = held or Input.is_action_pressed(action, true)
		_pan_key_active = held
		return
	_map.keyboard_pan(direction, delta)

func _input(event: InputEvent) -> void:
	# Map arrows must be consumed before Control's default spatial focus moves
	# away from the map. Other focused controls keep their native navigation.
	if input_settings == null or _page != "world" or not is_instance_valid(_map) or _shortcut_blocked():
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and focus != _map:
		return
	var action: String = input_settings.action_for_event(event)
	if action in ["tk_map_left", "tk_map_right", "tk_map_up", "tk_map_down", "tk_map_zoom_in", "tk_map_zoom_out"]:
		_unhandled_key_input(event)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or input_settings == null:
		return
	if _shortcut_blocked():
		_stop_keyboard_pan()
		return
	var action: String = input_settings.action_for_event(event)
	if action.is_empty():
		return
	if action.begins_with("tk_page_"):
		_show_page(action.trim_prefix("tk_page_"))
		if is_instance_valid(_map):
			_map.grab_focus()
	elif action == "tk_tasks":
		_tasks_dialog()
	elif action == "tk_save":
		_save_dialog()
	elif action == "tk_settings":
		_show_input_settings()
	elif action == "tk_map_home":
		if _page != "world":
			_show_page("world")
		_map.focus_home()
		_map.grab_focus()
	elif action.begins_with("tk_map_") and _page == "world" and is_instance_valid(_map):
		if action == "tk_map_zoom_in":
			_map.keyboard_zoom(1.12)
		elif action == "tk_map_zoom_out":
			_map.keyboard_zoom(1.0 / 1.12)
		else:
			_pan_key_active = true
			var direction: Vector2 = input_settings.movement_vector()
			var any_held: bool = false
			for movement: String in ["tk_map_left", "tk_map_right", "tk_map_up", "tk_map_down"]:
				any_held = any_held or Input.is_action_pressed(movement, true)
			if direction.is_zero_approx() and not any_held:
				direction = {"tk_map_left": Vector2.LEFT, "tk_map_right": Vector2.RIGHT, "tk_map_up": Vector2.UP, "tk_map_down": Vector2.DOWN}[action]
			_map.keyboard_pan(direction, 1.0 / 60.0)
	else:
		return
	get_viewport().set_input_as_handled()

func _show_input_settings() -> void:
	_remember_keyboard_focus()
	_stop_keyboard_pan()
	_hide_feature_panels()
	if input_settings == null:
		_initialize_inputs()
	if is_instance_valid(_dialog):
		_dialog.hide()
	if is_instance_valid(_management):
		_management.hide()
	if is_instance_valid(_pvp):
		_pvp.hide()
	if is_instance_valid(_lobby):
		_lobby.hide()
	if not is_instance_valid(_input_settings_dialog):
		_input_settings_dialog = InputSettingsDialogScript.new() as KingdomInputSettingsDialog
		add_child(_input_settings_dialog)
		_input_settings_dialog.setup(input_settings)
		_input_settings_dialog.visibility_changed.connect(_on_popup_visibility.bind(_input_settings_dialog))
	_input_settings_dialog.show_settings()

func _on_popup_visibility(popup: Window) -> void:
	call_deferred("_adapt_layout")
	if not popup.visible:
		call_deferred("_restore_keyboard_focus")

func _restore_keyboard_focus() -> void:
	if not is_inside_tree() or _visible_popup(self):
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and not focus.is_visible_in_tree():
		focus.release_focus()
	if _popup_return_focus != null:
		var previous: Variant = _popup_return_focus.get_ref()
		_popup_return_focus = null
		if is_instance_valid(previous) and previous is Control and previous.is_visible_in_tree() and not (previous is BaseButton and previous.disabled):
			previous.grab_focus()
		else:
			_focus_current_page()
	elif not is_instance_valid(focus) or not focus.is_visible_in_tree():
		_focus_current_page()
	# The web exporter uses a hidden DOM text input for IME. Return browser
	# keyboard focus to the canvas after an editor window closes.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("document.getElementById('canvas')?.focus();", true)

func _remember_keyboard_focus() -> void:
	if _visible_popup(self):
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and focus.is_visible_in_tree():
		_popup_return_focus = weakref(focus)

func _focus_current_page() -> void:
	var button: Button = _nav_buttons.get(_page)
	if is_instance_valid(button) and button.is_visible_in_tree():
		button.grab_focus()

func _focus_dialog_close(popup_ref: WeakRef) -> void:
	var popup: AcceptDialog = popup_ref.get_ref() as AcceptDialog
	if not is_instance_valid(popup) or not popup.is_inside_tree() or not popup.visible or popup != _dialog:
		return
	popup.get_ok_button().grab_focus()

func _watch_buttons(node: Node) -> void:
	if not is_instance_valid(node) or not is_instance_valid(_ui_feedback):
		return
	if node is Button:
		_ui_feedback.watch_button(node as Button)
	for child: Node in node.get_children():
		_watch_buttons(child)

func _update_shortcut_help() -> void:
	if input_settings == null:
		return
	for page: String in _nav_buttons:
		_nav_buttons[page].tooltip_text = "切换页面：" + input_settings.binding_text("tk_page_" + page)
	if is_instance_valid(_input_settings_button):
		_input_settings_button.tooltip_text = "按键设置：" + input_settings.binding_text("tk_settings")
	if is_instance_valid(_map_home_button):
		_map_home_button.tooltip_text = "回城定位：" + input_settings.binding_text("tk_map_home")
	if is_instance_valid(_shortcut_hint):
		var text: String = "按键设置 %s · Tab 切换控件 · Enter 操作所选按钮 · Esc 关闭弹窗" % input_settings.binding_text("tk_settings")
		if _page == "world":
			text = "地图 %s / %s / %s / %s · 缩放 %s / %s · 回城 %s\n" % [input_settings.binding_text("tk_map_up"), input_settings.binding_text("tk_map_left"), input_settings.binding_text("tk_map_down"), input_settings.binding_text("tk_map_right"), input_settings.binding_text("tk_map_zoom_in"), input_settings.binding_text("tk_map_zoom_out"), input_settings.binding_text("tk_map_home")] + text
		elif _page == "city":
			text = "Tab 聚焦地块 · 方向键选格 · Enter 查看建设 · Shift+Tab 返回工具栏\n" + text
		_shortcut_hint.text = text

func _make_theme() -> Theme:
	return UiThemeScript.create(FONT)

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
	background.color = Color("171819")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	_shell_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	_shell_root = root
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)
	var top: HBoxContainer = HBoxContainer.new()
	root.add_child(top)
	var title: Label = _label("山河策", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_task_toggle = _button("任务", _toggle_task_sidebar)
	_task_toggle.theme_type_variation = "UtilityButton"
	_task_toggle.toggle_mode = true
	top.add_child(_task_toggle)
	_pvp_button = _button("玩家战争", _show_pvp)
	_pvp_button.theme_type_variation = "UtilityButton"
	_pvp_button.visible = false
	top.add_child(_pvp_button)
	var transactions: Button = _button("事务", _tasks_dialog)
	transactions.theme_type_variation = "PrimaryButton"
	top.add_child(transactions)
	var menu_button: Button = _button("菜单", _open_menu)
	menu_button.theme_type_variation = "UtilityButton"
	top.add_child(menu_button)
	_nav = HBoxContainer.new()
	root.add_child(_nav)
	for entry: Array in [["city", "城池"], ["world", "舆图"], ["army", "军队"], ["generals", "将领"], ["reports", "战报"]]:
		var button: Button = _button(str(entry[1]), _show_page.bind(str(entry[0])))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = "NavButton"
		button.toggle_mode = true
		_nav.add_child(button)
		_nav_buttons[str(entry[0])] = button
	var resources_row: GridContainer = GridContainer.new()
	resources_row.columns = 5
	resources_row.add_theme_constant_override("h_separation", 4)
	_resource_grid = resources_row
	root.add_child(resources_row)
	for id: String in RES_NAMES:
		var action: Button = _button("", _resource_dialog.bind(id))
		action.theme_type_variation = "UtilityButton"
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.custom_minimum_size = Vector2(0, 44)
		resources_row.add_child(action)
		var label: Label = _label(str(RES_NAMES[id]) + "  —", 13)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
		action.add_child(label)
		_resources[id] = label
		_resource_buttons[id] = action
		action.disabled = true
	_compact_objective_panel = PanelContainer.new()
	_compact_objective_panel.theme_type_variation = "InsetPanel"
	root.add_child(_compact_objective_panel)
	var objective_row: HBoxContainer = HBoxContainer.new()
	_compact_objective_panel.add_child(objective_row)
	var objective_column: VBoxContainer = VBoxContainer.new()
	objective_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_column.add_theme_constant_override("separation", 3)
	objective_row.add_child(objective_column)
	_compact_objective_title = _label("当前目标 · 整备城池", 14)
	_compact_objective_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compact_objective_title.max_lines_visible = 1
	objective_column.add_child(_compact_objective_title)
	_compact_objective_text = _label("正在读取进度…", 12, Color("c3bcaa"))
	_compact_objective_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compact_objective_text.max_lines_visible = 1
	objective_column.add_child(_compact_objective_text)
	_compact_objective_button = _button("前往", _objective_action)
	_compact_objective_button.theme_type_variation = "PrimaryButton"
	_compact_objective_button.custom_minimum_size.x = 64.0
	objective_row.add_child(_compact_objective_button)
	_compact_growth_button = _button("成长", _show_growth_route)
	_compact_growth_button.theme_type_variation = "UtilityButton"
	objective_row.add_child(_compact_growth_button)
	_compact_objective_expand = _button("展开", _toggle_city_objective)
	_compact_objective_expand.custom_minimum_size.x = 44.0
	_compact_objective_expand.theme_type_variation = "UtilityButton"
	_compact_objective_expand.tooltip_text = "展开当前目标与奖励"
	_compact_objective_expand.visible = false
	objective_row.add_child(_compact_objective_expand)
	for action: Button in [_compact_objective_button, _compact_growth_button, _compact_objective_expand]:
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var first_steps: HFlowContainer = HFlowContainer.new()
	_first_steps = first_steps
	root.add_child(first_steps)
	_practice_button = _button("先练一战 · 借调部队", _show_practice)
	_practice_button.theme_type_variation = "PrimaryButton"
	_practice_button.tooltip_text = "先用借调部队学习军令，再准备30弓首次自主出征"
	first_steps.add_child(_practice_button)
	_county_conquest_button = _button("县城归附 · 查看新领地", _show_county_conquest)
	_county_conquest_button.theme_type_variation = "PrimaryButton"
	_county_conquest_button.visible = false
	first_steps.add_child(_county_conquest_button)
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
	_objective_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(_objective_title)
	_objective_text = _label("正在读取进度…", 15)
	_objective_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(_objective_text)
	_objective_button = _button("查看目标", _objective_action)
	_objective_button.theme_type_variation = "PrimaryButton"
	_side.add_child(_objective_button)
	_growth_button = _button("成长路线", _show_growth_route)
	_growth_button.disabled = true
	_side.add_child(_growth_button)
	_side.add_child(_button("晋升筹备", _show_progression.bind("preparation")))
	_side.add_child(HSeparator.new())
	_side.add_child(_label("常用事务", 14, Color("baae85")))
	_side.add_child(_button("领取已解锁礼包", func() -> void: _send_command("onboarding.claimAvailable")))
	_side.add_child(_button("任务与官爵", _show_progression.bind("missions")))
	_side.add_child(_button("城池与运输", _show_realm.bind("cities")))
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
	_center_area = VBoxContainer.new()
	_center_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_center_area)
	_center_area.add_child(center_scroll)
	_center = VBoxContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_scroll.add_child(_center)
	_detail_panel = PanelContainer.new()
	_detail_panel.custom_minimum_size.x = 280.0
	_body.add_child(_detail_panel)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail)
	_city_status_row = HBoxContainer.new()
	root.add_child(_city_status_row)
	_city_queue_button = _button("施工队列", _city_build_queue_dialog)
	_city_queue_button.theme_type_variation = "PrimaryButton"
	_city_queue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_city_status_row.add_child(_city_queue_button)
	_city_military_button = _button("军情", _city_military_dialog)
	_city_military_button.theme_type_variation = "UtilityButton"
	_city_status_row.add_child(_city_military_button)
	_activity_bar = ActivityBarScript.new() as KingdomArmyActivityBar
	root.add_child(_activity_bar)
	_activity_bar.route_requested.connect(_route_army_activity)
	_shortcut_hint = _label("", 13, Color("a4b5a3"))
	_shortcut_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_shortcut_hint)
	_toast = _label("拖动舆图 · 滚轮缩放 · 点选目标", 14, Color("b9bfab"))
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.max_lines_visible = 1
	var footer: HBoxContainer = HBoxContainer.new()
	root.add_child(footer)
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_toast)
	_messages_button = _button("消息", _messages_dialog)
	_messages_button.theme_type_variation = "UtilityButton"
	_messages_button.tooltip_text = "本次打开客户端的最近30条操作提示；切换进度后清空"
	footer.add_child(_messages_button)
	_connection_indicator = _label("未连接", 12, Color("afb8ad"))
	footer.add_child(_connection_indicator)
	_notifications = NotificationScript.new() as KingdomNotificationCenter
	add_child(_notifications)
	_notifications.history_changed.connect(func(count: int) -> void:
		_messages_button.text = "消息 %d" % count if count > 0 else "消息")
	resized.connect(_adapt_layout)
	call_deferred("_adapt_layout")

func _adapt_layout() -> void:
	_sync_web_scale()
	_sidebar_panel.visible = size.x >= 1000.0 and _sidebar_expanded
	_compact_objective_panel.visible = not _sidebar_panel.visible
	_detail_panel.visible = size.x >= 1000.0 and _page == "world" and not _selected.is_empty() and not (is_instance_valid(_scouting) and _scouting.visible)
	_resource_grid.columns = 5
	_task_toggle.set_pressed_no_signal(_sidebar_panel.visible)
	_task_toggle.text = "收起任务" if _sidebar_panel.visible else "任务"
	for edge: String in ["left", "right", "top", "bottom"]:
		_shell_margin.add_theme_constant_override("margin_" + edge, 8 if size.x < 760.0 else 12)
	_shell_root.move_child(_nav, _shell_root.get_child_count() - 1 if size.x < 760.0 else 1)
	if is_instance_valid(_activity_bar):
		_activity_bar.set_compact(size.x < 760.0)
	if is_instance_valid(_city):
		_city.custom_minimum_size.y = _city.recommended_height(_city.size.x if _city.size.x > 240.0 else maxf(240.0, _center.size.x))
	for label: Label in _resources.values():
		label.add_theme_font_size_override("font_size", 12 if size.x < 760.0 else 13)
	_sync_resources()
	_sync_city_context_hud()
	var compact_city: bool = _page == "city" and size.x < 760.0
	_compact_objective_expand.visible = compact_city
	_compact_objective_expand.text = "收起" if _city_objective_expanded else "展开"
	_compact_objective_text.visible = not compact_city or _city_objective_expanded
	_compact_objective_text.max_lines_visible = -1 if compact_city and _city_objective_expanded else 1
	if not _view.is_empty():
		_refresh_objective()
	if is_instance_valid(_management) and _management.visible:
		_management._fit_window()
	_pvp_button.visible = size.x >= 1000.0 and api != null and api.mode == "shared"
	_shortcut_hint.visible = false
	if is_instance_valid(_input_settings_dialog) and _input_settings_dialog.visible:
		_input_settings_dialog._fit_window()
	if is_instance_valid(_lobby) and _lobby.visible:
		_lobby._fit_window()
	for panel: Window in [_progression, _heroes, _war_management, _inventory, _scouting]:
		if is_instance_valid(panel) and panel.visible:
			panel._fit_window()
	if is_instance_valid(_realm) and _realm.visible:
		_realm._fit()

func _toggle_task_sidebar() -> void:
	if size.x < 1000.0:
		_tasks_dialog()
		_task_toggle.set_pressed_no_signal(false)
		return
	_sidebar_expanded = not _sidebar_expanded
	_adapt_layout()

func _dismiss_target() -> void:
	_selected = {}
	if is_instance_valid(_map):
		_map.selected_tile = {}
		_map.queue_redraw()
	_render_detail()

func _resource_amount(value: float) -> String:
	if absf(value) >= 100000000.0:
		return "%.1f亿" % (value / 100000000.0)
	if absf(value) >= 10000.0:
		return "%.1f万" % (value / 10000.0)
	return str(int(floor(value)))

func _resource_facts(id: String) -> String:
	if _view.is_empty():
		return str(RES_NAMES[id]) + " · 等待当前城池数据"
	var value: float = float(_view.get("res", {}).get(id, 0))
	var capacity: float = float(_view.get("caps", {}).get(id, 0))
	var rate: float = float(_view.get("rates", {}).get(id, 0)) * 60.0
	return "%s %s / 容量 %s\n每分钟 %+.1f%s" % [str(RES_NAMES[id]), str(int(floor(value))), str(int(floor(capacity))), rate, " · 超仓" if capacity > 0.0 and value > capacity else ""]

func _sync_resources() -> void:
	if _view.is_empty():
		for id: String in _resources:
			(_resources[id] as Label).text = str(RES_NAMES[id]) + "  —"
			(_resources[id] as Label).tooltip_text = ""
			(_resource_buttons[id] as Button).tooltip_text = ""
			(_resource_buttons[id] as Button).disabled = true
		_sync_resource_details()
		return
	for id: String in _resources:
		var label: Label = _resources[id]
		var value: float = float(_view.get("res", {}).get(id, 0))
		var capacity: float = float(_view.get("caps", {}).get(id, 0))
		var overflow: bool = capacity > 0.0 and value > capacity
		var compact_city: bool = _page == "city" and size.x < 760.0
		label.text = str(RES_SHORT_NAMES[id]) + _resource_amount(value) + ("!" if overflow else "") if compact_city else str(RES_NAMES[id]) + ("超仓" if overflow else "") + "\n" + _resource_amount(value)
		label.modulate = Color("e0b36e") if overflow else Color.WHITE
		label.tooltip_text = _resource_facts(id)
		_resource_buttons[id].tooltip_text = label.tooltip_text + "\n点击查看资源详情"
		_resource_buttons[id].disabled = _view.is_empty()
	_sync_resource_details()

func _toggle_city_objective() -> void:
	_city_objective_expanded = not _city_objective_expanded
	_adapt_layout()

func _city_has_military_activity() -> bool:
	if api == null or not api.connected or _view.is_empty():
		return true
	if not _view.get("queues", {}).get("train", []).is_empty() or not _view.get("queues", {}).get("defense", []).is_empty() or not _view.get("marches", []).is_empty() or not _view.get("reports", []).is_empty():
		return true
	if _view.get("battle") is Dictionary:
		return true
	var defense: Dictionary = _view.get("warManagement", {}).get("defense", {})
	if defense.get("incoming") is Dictionary or defense.get("battle") is Dictionary:
		return true
	return not _view.get("warManagement", {}).get("wages", {}).get("status", {}).get("warnings", []).is_empty()

func _sync_city_context_hud() -> void:
	if not is_instance_valid(_city_status_row) or not is_instance_valid(_activity_bar):
		return
	var city_page: bool = _page == "city"
	_city_status_row.visible = city_page
	_activity_bar.visible = not city_page or _city_has_military_activity()
	_city_military_button.text = "军情" if not _city_has_military_activity() else "军情提醒"
	var queues: Array = _view.get("queues", {}).get("build", [])
	_city_queue_button.text = "施工 %d/%d · 查看队列" % [queues.size(), int(_view.get("queueLimits", {}).get("build", 0))]
	_city_queue_button.disabled = _view.is_empty()
	_city_queue_button.tooltip_text = "查看本城建筑与城外地块的施工、升级和加速入口"

func _city_build_queue_dialog() -> void:
	var content: VBoxContainer = _open_dialog("本城施工队列", 600)
	var queues: Array = _view.get("queues", {}).get("build", [])
	content.add_child(_label("施工 %d / 建造队容量 %d" % [queues.size(), int(_view.get("queueLimits", {}).get("build", 0))], 20))
	if queues.is_empty():
		content.add_child(_label("建造队空闲。\n点城内空地或城外田庄，\n选择要建造的设施。", 16))
	for job: Dictionary in queues:
		var summary: Label = _label(_queue_name(job, "build") + " · " + _march_remaining(float(job.get("end", 0))), 16)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(summary)
		if job.has("plot"):
			content.add_child(_button("查看城外地块 %d" % (int(job.plot) + 1), _show_plot.bind(int(job.plot))))
		else:
			content.add_child(_button("查看城内地块 %d" % (int(job.get("site", -1)) + 1), _building_dialog.bind(str(job.get("id", "")), int(job.get("site", -1)))))
	content.add_child(_button("查看加速道具", _show_inventory.bind("inventory")))

func _city_military_dialog() -> void:
	var content: VBoxContainer = _open_dialog("军情与部队", 560)
	var defense: Dictionary = _view.get("warManagement", {}).get("defense", {})
	if defense.get("incoming") is Dictionary:
		var incoming: Dictionary = defense.incoming
		var alert: Label = _label("来袭 · %s · %s" % [str(incoming.get("name", "敌军")), _march_remaining(float(incoming.get("arriveAt", 0)))], 16, Color("e1b073"))
		alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(alert)
		content.add_child(_button("准备守城", _show_war_management.bind("defense")))
	for warning: String in _view.get("warManagement", {}).get("wages", {}).get("status", {}).get("warnings", []):
		var alert: Label = _label(warning, 15, Color("e1b073"))
		alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(alert)
	for entry: Array in [["training", "驻军与训练"], ["marches", "行军部队"], ["stationed", "驻扎部队"], ["reports", "查看战报"]]:
		content.add_child(_button(str(entry[1]), _route_army_activity.bind(str(entry[0]))))
	content.add_child(_button("黄巾来袭与城防", _show_war_management.bind("defense")))
	content.add_child(_button("民心与军饷", _show_war_management.bind("wages")))

func _resource_dialog(id: String) -> void:
	var content: VBoxContainer = _open_dialog("资源 · " + str(RES_NAMES.get(id, "详情")), 600)
	for resource: String in RES_NAMES:
		var label: Label = _label("", 18 if resource == id else 15, Color("d9bd7d") if resource == id else Color("f1ead9"))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(label)
		_resource_detail_labels[resource] = label
	var note: Label = _label("容量限制自然生产；战斗、采集、占领等按现有规则入库。超仓物资会保留，具体交易以确认前预览为准。", 14, Color("c3bcaa"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	_resource_status = _label("", 14, Color("e0b36e"))
	content.add_child(_resource_status)
	_sync_resource_details()

func _sync_resource_details() -> void:
	for id: String in _resource_detail_labels:
		var label: Label = _resource_detail_labels[id]
		if is_instance_valid(label):
			label.text = _resource_facts(id)
	if is_instance_valid(_resource_status):
		_resource_status.text = "正在读取当前城池数据" if _view.is_empty() else "" if api != null and api.connected else "连接中断 · 当前显示最后收到的数据"

func _route_army_activity(section: String) -> void:
	match section:
		"training":
			_training_dialog()
		"marches":
			_marches_dialog()
		"stationed":
			_marches_dialog("stationed")
		"reports":
			_hide_feature_panels()
			if is_instance_valid(_dialog):
				_dialog.hide()
			_show_page("reports")

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
	button.custom_minimum_size.y = 44.0
	button.disabled = disabled
	button.pressed.connect(callback)
	button.pressed.connect(func() -> void:
		if is_instance_valid(_audio):
			_audio.click())
	if is_instance_valid(_ui_feedback):
		_ui_feedback.watch_button(button)
	return button

func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _show_page(page: String) -> void:
	_stop_keyboard_pan()
	_page = page
	for id: String in _nav_buttons:
		var nav_button: Button = _nav_buttons[id]
		nav_button.set_pressed_no_signal(id == page)
		nav_button.text = ("· " if id == page else "") + {"city": "城池", "world": "舆图", "army": "军队", "generals": "将领", "reports": "战报"}[id]
	_last_structure = ""
	if is_instance_valid(_city_toolbar):
		_center_area.remove_child(_city_toolbar)
		_city_toolbar.queue_free()
		_city_toolbar = null
	_clear(_center)
	_map = null
	_city = null
	_suburb = null
	_battle = null
	_map_home_button = null
	_map_toolbar = null
	_map_filter = null
	match page:
		"world":
			_build_map_toolbar()
			var map_panel: PanelContainer = PanelContainer.new()
			map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_center.add_child(map_panel)
			_map = MapScript.new() as KingdomWorldMap
			_map.custom_minimum_size = Vector2(240.0, 260.0)
			map_panel.add_child(_map)
			_map.tile_selected.connect(_select_tile)
			if not _world.is_empty():
				_map.set_world(_world)
			_map.set_filter(_map_filter_kind)
		"city":
			_city_toolbar = HFlowContainer.new()
			_city_toolbar.add_theme_constant_override("h_separation", 6)
			_center_area.add_child(_city_toolbar)
			_center_area.move_child(_city_toolbar, 0)
			for zone: Array in [["inner", "城内"], ["outer", "城外田庄"]]:
				var tab: Button = _button(str(zone[1]), _show_city_zone.bind(str(zone[0])))
				tab.toggle_mode = true
				tab.set_pressed_no_signal(_city_zone == str(zone[0]))
				_city_toolbar.add_child(tab)
			_city_toolbar.add_child(_button("城务", _city_affairs_dialog))
			_city_toolbar.add_child(_button("经营方案", _show_realm.bind("plans")))
			if api == null or api.mode != "shared":
				_city_toolbar.add_child(_button("领地治理", _show_county_governance))
				_county_identity_label = _label("", 14, Color("d8c28b"))
				_county_identity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				_city_toolbar.add_child(_county_identity_label)
				_sync_county_identity()
			if _city_zone == "inner":
				var locate_hall: Button = _button("定位官府", _focus_city_hall)
				locate_hall.theme_type_variation = "UtilityButton"
				locate_hall.tooltip_text = "滚动到本城官府，保留当前地块顺序"
				_city_toolbar.add_child(locate_hall)
			if _city_zone == "outer":
				_suburb = SuburbScript.new() as KingdomSuburbView
				_suburb.size_flags_vertical = Control.SIZE_EXPAND_FILL
				_center.add_child(_suburb)
				_suburb.custom_minimum_size.x = 240.0
				_suburb.plot_selected.connect(_show_plot)
				_suburb.set_view(_view)
				_center.add_child(_button("城外建设与样板", _show_realm.bind("plots")))
			else:
				_city = CityScript.new() as KingdomCityView
				_city.size_flags_vertical = Control.SIZE_EXPAND_FILL
				_center.add_child(_city)
				_city.custom_minimum_size = Vector2(240.0, _city.recommended_height(maxf(240.0, _center.size.x)))
				_city.building_selected.connect(func(id: String) -> void: _building_dialog(id, _city.selected_site()))
				_city.empty_site_selected.connect(_empty_site_dialog)
				_city.defense_selected.connect(_perimeter_defense_dialog)
				_city.set_city(_view, _intel_now())
				_center.add_child(_button("建筑总览与空地建设", _buildings_dialog))
				call_deferred("_adapt_layout")
		"army":
			_center.add_child(_label("军队 · 城防与出征", 22))
			if api == null or api.mode != "shared":
				_center.add_child(_button("战役军令 · 长期征战与挑战", _show_progression.bind("campaign")))
				_center.add_child(_button("借调演练 · 比较三种战术", _show_practice))
			_battle = BattleScript.new() as KingdomBattleView
			_battle.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_battle.custom_minimum_size.y = 260.0
			_center.add_child(_battle)
			_battle.custom_minimum_size = Vector2(260.0, 540.0)
			_battle.action_requested.connect(_battle_action)
			_battle.set_battle(_present_battle(), _unit_dictionary())
			_center.add_child(_button("训练与驻军", _training_dialog))
			_center.add_child(_button("行军与驻扎部队", _marches_dialog))
			var war_actions: GridContainer = GridContainer.new()
			war_actions.columns = 2
			_center.add_child(war_actions)
			for entry: Array in [["hospital", "伤兵治疗"], ["captives", "俘虏招降"], ["defenses", "建设城防"], ["defense", "黄巾来袭"]]:
				war_actions.add_child(_button(str(entry[1]), _show_war_management.bind(str(entry[0]))))
		"generals", "reports":
			_center.add_child(_label("将领名册" if page == "generals" else "战报与战利品", 22))
			if page == "generals":
				var general_actions: GridContainer = GridContainer.new()
				general_actions.columns = 2
				_center.add_child(general_actions)
				for entry: Array in [["inn", "招募将领"], ["governance", "任命城守"]]:
					var action: Button = _button(str(entry[1]), _show_management.bind(str(entry[0])))
					action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					general_actions.add_child(action)
				for entry: Array in [["generals", "培养与忠诚"], ["specializations", "专长训练"], ["wild", "野地抓将"], ["captives", "俘虏将领"], ["equipment", "装备与打造"]]:
					general_actions.add_child(_button(str(entry[1]), _show_heroes.bind(str(entry[0]))))
			var scroll: ScrollContainer = ScrollContainer.new()
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_center.add_child(scroll)
			var content: VBoxContainer = VBoxContainer.new()
			content.name = "Content"
			content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(content)
	_render_detail()
	_update_page_content()
	_update_shortcut_help()
	_adapt_layout()
	call_deferred("_watch_buttons", _center)
	if is_instance_valid(_city_toolbar):
		call_deferred("_watch_buttons", _city_toolbar)

func _focus_city_hall() -> void:
	if not is_instance_valid(_city) or _city_zone != "inner":
		return
	var scroller: ScrollContainer = _center.get_parent() as ScrollContainer
	if not is_instance_valid(scroller):
		return
	for parcel: Dictionary in _city.parcel_draw_records():
		if str(parcel.get("id", "")) != "hall" or bool(parcel.get("reserved", false)):
			continue
		var rect: Rect2 = parcel.get("rect", Rect2())
		var center_y: float = _city.position.y + rect.get_center().y
		scroller.scroll_vertical = maxi(0, roundi(center_y - scroller.size.y * 0.5))
		_city.select_building("hall", int(parcel.get("site", -1)))
		_show_toast("已定位官府 · 地块 %d" % (int(parcel.get("site", -1)) + 1), false, false)
		return
	_show_toast("正在读取本城官府位置，请稍后再试")

func _build_map_toolbar() -> void:
	_map_toolbar = HFlowContainer.new()
	_map_toolbar.add_theme_constant_override("h_separation", 8)
	_map_toolbar.add_theme_constant_override("v_separation", 4)
	_center.add_child(_map_toolbar)
	# The two compact groups wrap from their actual available width, including
	# when the task rail or selected-target panel reduces the desktop map space.
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	_map_toolbar.add_child(heading)
	var title: Label = _label("天下舆图", 18)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(title)
	_map_filter = OptionButton.new()
	_map_filter.custom_minimum_size = Vector2(88.0, 44.0)
	_map_filter.theme_type_variation = "UtilityButton"
	_map_filter.tooltip_text = "筛选地图上的城池、资源、行军或任务目标"
	for entry: Array in [["all", "全部"], ["cities", "城池"], ["resources", "资源"], ["marches", "行军"], ["tasks", "任务"]]:
		_map_filter.add_item(str(entry[1]))
		var index: int = _map_filter.item_count - 1
		_map_filter.set_item_metadata(index, str(entry[0]))
		if str(entry[0]) == _map_filter_kind:
			_map_filter.select(index)
	_map_filter.item_selected.connect(func(index: int) -> void:
		_map_filter_kind = str(_map_filter.get_item_metadata(index))
		if is_instance_valid(_map):
			_map.set_filter(_map_filter_kind))
	heading.add_child(_map_filter)
	var navigation: HBoxContainer = HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 4)
	_map_toolbar.add_child(navigation)
	for entry: Array in [["−", 1.0 / 1.2, "缩小地图"], ["+", 1.2, "放大地图"]]:
		var factor: float = float(entry[1])
		var zoom_button: Button = _button(str(entry[0]), func() -> void:
			if is_instance_valid(_map):
				_map.keyboard_zoom(factor))
		zoom_button.custom_minimum_size.x = 44.0
		zoom_button.theme_type_variation = "UtilityButton"
		zoom_button.tooltip_text = str(entry[2])
		navigation.add_child(zoom_button)
	_map_home_button = _button("回城定位", func() -> void:
		if is_instance_valid(_map):
			_map.focus_home())
	_map_home_button.theme_type_variation = "UtilityButton"
	navigation.add_child(_map_home_button)
	var marches: Button = _button("行军", _marches_dialog)
	marches.theme_type_variation = "UtilityButton"
	navigation.add_child(marches)
	if api == null or api.mode != "shared":
		var find_resources: Button = _button("掠夺找资源", _show_raid_targets)
		find_resources.theme_type_variation = "PrimaryButton"
		navigation.add_child(find_resources)

func _receive_snapshot(payload: Dictionary) -> void:
	_intel_server_offset = float(payload.get("serverTime", Time.get_unix_time_from_system() * 1000.0)) - Time.get_unix_time_from_system() * 1000.0
	_view = payload.get("view", {})
	_state = payload.get("state", {})
	if _toast.text == "正在读取当前进度…":
		_show_toast("当前进度已加载")
	if api.mode == "shared":
		_update_pvp()
	_sync_resources()
	if is_instance_valid(_activity_bar):
		_activity_bar.update_view(_view, _intel_now())
		_activity_bar.set_connected(api.connected)
	_refresh_objective()
	_sync_tasks_hub()
	_sync_growth_route()
	_sync_report_economy()
	_sync_county_governance()
	_establish_county_baseline()
	_sync_county_identity()
	if is_instance_valid(_raid_targets):
		_raid_targets.update_view(_view)
		_raid_targets.set_navigation_state(api.connected, api._has_mutation())
	_refresh_city_construction_panel()
	if _city != null:
		_city.set_city(_view, _intel_now())
	if _suburb != null:
		_suburb.set_view(_view)
	if _battle != null:
		_battle.set_battle(_present_battle(), _unit_dictionary())
	if is_instance_valid(_management):
		_management.update_view(_view)
	for popup: Window in [_heroes, _progression, _war_management, _realm, _inventory, _scouting]:
		if is_instance_valid(popup):
			popup.update_view(_scouting_view() if popup == _scouting else _view)
			popup.set_command_state(api.connected, api._has_mutation())
	var signature: String = JSON.stringify([_view.get("buildings", []), _view.get("queues", {}), _view.get("marches", []), _view.get("reports", []), _view.get("generals", [])])
	if signature != _last_structure:
		_last_structure = signature
		_update_page_content()
		_render_detail()
	_sync_scouting_intel()
	_refresh_scout_marches()
	_adapt_layout()
	_smoke_snapshot = true
	_check_smoke()

func _receive_world(world: Dictionary) -> void:
	var first_world: bool = _world.is_empty()
	_world = world
	if api.mode == "shared":
		_update_pvp()
		if not _selected.is_empty():
			for tile: Dictionary in world.get("tiles", []):
				if str(tile.get("id", "")) == str(_selected.get("id", "")):
					_selected = tile.duplicate(true)
					break
		_render_detail()
	if is_instance_valid(_scouting):
		_scouting.update_view(_scouting_view())
	_sync_scouting_intel()
	if _map != null:
		_map.set_world(world)
		if first_world:
			_map.focus_home()
	_smoke_world = true
	_check_smoke()

func _check_smoke() -> void:
	if _smoke and _smoke_snapshot and _smoke_world:
		print("GODOT_SMOKE_OK canonical_revision=" + str(api.revision) + " tiles=" + str(_world.get("tiles", []).size()))
		get_tree().quit(0)

func _connection_changed(message: String, _connected: bool) -> void:
	if is_instance_valid(_activity_bar):
		_activity_bar.set_connected(_connected)
	if is_instance_valid(_report_loot):
		_report_loot.set_navigation_state(_connected, api._has_mutation())
	if is_instance_valid(_report_recovery):
		_report_recovery.set_navigation_state(_connected, api._has_mutation())
	if is_instance_valid(_raid_targets):
		_raid_targets.set_navigation_state(_connected, api._has_mutation())
	_sync_resource_details()
	_refresh_scout_marches()
	_status.text = message
	_connection_indicator.text = "已连接" if _connected else "连接中断"
	_connection_indicator.tooltip_text = message
	_connection_indicator.add_theme_color_override("font_color", Color("9bbfa6") if _connected else Color("e0b36e"))
	_sync_objective_actions()
	_refresh_city_construction_panel()
	_sync_tasks_hub()
	_status.modulate = Color("aed1a9") if _connected else Color("e0b36e")
	if is_instance_valid(_management):
		_management.set_command_state(_connected, api._has_mutation())
	_update_pvp()
	for popup: Window in [_heroes, _progression, _war_management, _realm, _inventory, _scouting]:
		if is_instance_valid(popup):
			popup.set_command_state(_connected, api._has_mutation())
	if is_instance_valid(_lobby):
		_lobby.connection_status(message, _connected, api.actor, api.room, api._authority)

func _request_failed(message: String) -> void:
	_county_after_switch = ""
	_county_battle_pending.clear()
	_pending_battle = false
	_pending_recall.clear()
	_sync_objective_actions()
	_refresh_city_construction_panel()
	_sync_tasks_hub()
	_show_toast(message, true)
	_update_pvp()
	if is_instance_valid(_pvp):
		_pvp.show_request_error(message)
	if is_instance_valid(_management):
		_management.set_command_state(api.connected, api._has_mutation())
		_management.show_error(message)
	for popup: Window in [_heroes, _progression, _war_management, _realm, _inventory, _scouting]:
		if is_instance_valid(popup):
			popup.set_command_state(api.connected, api._has_mutation())
			popup.show_error(message)

func _show_toast(message: String, error: bool = false, announce: bool = true) -> void:
	_toast.text = message
	_toast.tooltip_text = message
	_toast.add_theme_color_override("font_color", Color("edb68f") if error else Color("c9d2be"))
	if is_instance_valid(_ui_feedback):
		_ui_feedback.notice(_toast)
	if announce and is_instance_valid(_notifications):
		_notifications.push_notice(message, error)

func _messages_dialog() -> void:
	var content: VBoxContainer = _open_dialog("最近操作消息", 600)
	var note: Label = _label("仅保留当前进度、本次打开客户端的最近30条提示。最新消息在上方。", 14, Color("c3bcaa"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	var records: Array[Dictionary] = _notifications.records() if is_instance_valid(_notifications) else []
	if records.is_empty():
		content.add_child(_label("还没有操作消息。", 16))
	for record: Dictionary in records:
		var text: Label = _label(str(record.get("time", "")) + " · " + ("请核对操作状态" if record.get("error", false) else "操作提示") + "\n" + str(record.get("message", "")), 16, Color("edb68f") if record.get("error", false) else Color("f1ead9"))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(text)
		content.add_child(HSeparator.new())

func _current_objective() -> Dictionary:
	if api != null and api.mode == "shared":
		return {"title": "共享攻防演练" if api.room.is_empty() else str(api.room.get("name", "房间")) + " · 攻防演练", "description": "向盟友派遣援军，或选择敌方城池掠夺。抵达自动交战，返程后入库。", "ready": false}
	return _view.get("objective", {})

func _refresh_objective() -> void:
	var objective: Dictionary = _current_objective()
	var title: String = str(objective.get("title", "整备城池"))
	var description: String = str(objective.get("description", "正在读取城池与目标…"))
	_objective_title.text = title
	_objective_text.text = description + ("\n奖励 " + _reward_text(objective) if api == null or api.mode != "shared" else "")
	_objective_button.text = "查看玩家战争" if api != null and api.mode == "shared" else "领取奖励" if objective.get("ready", false) else "查看目标"
	var compact_city: bool = _page == "city" and size.x < 760.0
	_compact_objective_title.text = title if compact_city else "当前目标 · " + title
	_compact_objective_title.tooltip_text = "当前目标 · " + title + "\n" + _objective_text.text
	_compact_objective_text.text = _objective_text.text if compact_city and _city_objective_expanded else description
	_compact_objective_text.tooltip_text = _objective_text.text
	_compact_objective_button.text = "领取" if objective.get("ready", false) else "前往"
	_sync_objective_actions()

func _sync_objective_actions() -> void:
	var blocked: bool = api == null or not api.connected or api._has_mutation()
	if is_instance_valid(_battle):
		_battle.set_actions_enabled(not blocked and api.mode == "local")
	_objective_button.disabled = blocked
	_compact_objective_button.disabled = blocked
	if is_instance_valid(_growth_button):
		_growth_button.visible = api == null or api.mode != "shared"
		_growth_button.disabled = blocked or _view.get("growth", {}).is_empty()
	if is_instance_valid(_compact_growth_button):
		_compact_growth_button.visible = api == null or api.mode != "shared"
		_compact_growth_button.disabled = blocked or _view.get("growth", {}).is_empty()
	if is_instance_valid(_growth_route):
		_growth_route.set_navigation_state(api != null and api.connected, api != null and api._has_mutation())
	if is_instance_valid(_practice_button):
		var first_battle: Dictionary = _view.get("progression", {}).get("firstBattle", {})
		_practice_button.visible = api != null and api.mode == "local" and not first_battle.is_empty() and not first_battle.get("complete", false)
		_practice_button.disabled = blocked
	if is_instance_valid(_county_governance):
		_county_governance.set_command_state(not blocked and _county_source == str(_view.get("city", {}).get("id", "")), api != null and api._has_mutation())
	if is_instance_valid(_county_conquest_button):
		_county_conquest_button.visible = not _county_conquest.is_empty() and api != null and api.mode == "local"
		_county_conquest_button.disabled = blocked
	if is_instance_valid(_first_steps):
		_first_steps.visible = _practice_button.visible or _county_conquest_button.visible

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
	if is_instance_valid(_shell_root):
		_adapt_layout()
	_detail_intel = null
	_clear(_detail)
	if _page == "world" and not _selected.is_empty():
		_detail.add_child(_button("关闭目标", _dismiss_target))
		_detail.add_child(_label(str(_selected.get("name", "目标")), 22))
		_detail.add_child(_label("坐标 %d,%d · 等级 %d" % [int(_selected.get("x", 0)), int(_selected.get("y", 0)), int(_selected.get("level", 0))], 14))
		if api.mode == "shared" and _selected.has("playerId"):
			var ally: bool = str(_selected.get("relation", "")) in ["allied", "ally", "friendly"]
			_detail.add_child(_label("己方" if _selected.get("owned", false) else "同盟城池" if ally else "敌方城池", 15))
			_detail.add_child(_button("派遣援军" if ally else "配兵掠夺", _dispatch_dialog.bind(_selected), bool(_selected.get("owned", false))))
		else:
			if api.mode == "shared":
				_detail.add_child(_label("本轮演练先开放玩家城池攻防。", 15))
			else:
				if not _selected.get("owned", false):
					_detail_intel = IntelPanelScript.new() as KingdomIntelPanel
					_detail.add_child(_detail_intel)
					_detail_intel.set_intel(_intel_node(_selected), _view.get("units", []), _intel_now())
					_detail.add_child(_button("侦察目标", _show_scouting.bind(_selected)))
				_detail.add_child(_button("配兵出征", _dispatch_dialog.bind(_selected), bool(_selected.get("owned", false))))

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
		return "驻扎 · 兵力未侦察" if march.get("count") == null else "驻扎 · " + str(march.get("count", 0)) + "人"
	if march.get("canStartBattle", false):
		return "已抵达 · 等待交战"
	var end: float = float(march.get("returnAt", march.get("arrive", 0))) if status == "return" else float(march.get("nextArrival", march.get("arrive", 0)))
	return ("返城中 · " if status == "return" else "行进中 · ") + _march_remaining(end)

func _march_remaining(end: float) -> String:
	var seconds: int = maxi(0, int(ceil((end - _intel_now()) / 1000.0)))
	return "待服务器结算" if seconds == 0 else "%d分%02d秒" % [seconds / 60, seconds % 60]

func _refresh_clock() -> void:
	if is_instance_valid(_activity_bar):
		_activity_bar.refresh_clock(_intel_now())
	_sync_scouting_intel()
	_refresh_scout_marches()
	for child: Node in _detail.get_children():
		if child is Label and child.has_meta("queue_end"):
			(child as Label).text = str(child.get_meta("queue_name")) + "\n" + _remaining(float(child.get_meta("queue_end")))
		elif child is Label and child.has_meta("march"):
			(child as Label).text = str(child.get_meta("march_name")) + "\n" + _march_status(child.get_meta("march"))

func _select_tile(tile: Dictionary) -> void:
	_selected = tile.duplicate(true)
	_render_detail()
	_show_toast(str(tile.get("name", "目标")) + " · 坐标 " + str(tile.get("x", 0)) + "," + str(tile.get("y", 0)), false, false)
	if size.x < 1000.0:
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
			var summary: String = "自动结算 · 攻方永久损失 " + _army_text(report.get("lost", {})) if report.get("shared", false) else str(int(report.get("round", 0))) + " 回合 · 损失 " + _army_text(report.get("lost", {}))
			var text: Label = _label(_report_title(report) + "\n" + summary, 17)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(text)
			content.add_child(_button("查看战报", _report_dialog.bind(report)))

func _open_dialog(title: String, width: int = 600, managed_scroll: bool = true) -> VBoxContainer:
	_city_construction_panel = null
	_city_construction_site = -1
	_city_construction_source = ""
	_resource_detail_labels.clear()
	_resource_status = null
	_dispatch_intel = null
	_dispatch_intel_target = {}
	_march_labels.clear()
	_march_action_buttons.clear()
	_march_content = null
	_march_empty = null
	_growth_route = null
	_county_governance = null
	_county_source = ""
	_report_review = null
	_report_economy = null
	_report_loot = null
	_report_recovery = null
	_raid_targets = null
	_report_key = ""
	_economy_signature = ""
	_remember_keyboard_focus()
	_stop_keyboard_pan()
	_hide_feature_panels()
	if is_instance_valid(_lobby):
		_lobby.hide()
	if is_instance_valid(_pvp):
		_pvp.hide()
	if is_instance_valid(_input_settings_dialog):
		_input_settings_dialog.hide()
	if is_instance_valid(_management):
		_management.hide()
	if is_instance_valid(_dialog):
		_dialog.hide()
		if _dialog == _scouting:
			_scouting = null
		# A button in this Window may still be dispatching its current input.
		# Keep its Viewport in the tree until queue_free flushes after the frame.
		_dialog.queue_free()
	_dialog = AcceptDialog.new()
	_dialog.title = title
	_dialog.dialog_text = ""
	_dialog.get_ok_button().text = "关闭"
	_dialog.min_size = Vector2i(mini(width, maxi(300, int(size.x) - 40)), mini(550, maxi(240, int(size.y) - 60)))
	add_child(_dialog)
	_dialog.visibility_changed.connect(_on_popup_visibility.bind(_dialog))
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if managed_scroll:
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(float(_dialog.min_size.x - 40), 260.0)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_dialog.add_child(scroll)
		scroll.add_child(content)
	else:
		content.custom_minimum_size = Vector2(float(_dialog.min_size.x - 40), float(_dialog.min_size.y - 70))
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_dialog.add_child(content)
	_dialog.popup_centered()
	call_deferred("_focus_dialog_close", weakref(_dialog))
	call_deferred("_watch_buttons", _dialog)
	return content

func _show_city_zone(zone: String) -> void:
	_city_zone = "outer" if zone == "outer" else "inner"
	_show_page("city")

func _perimeter_defense_dialog() -> void:
	for building: Dictionary in _view.get("buildings", []):
		if str(building.get("id", "")) == "wall":
			_building_dialog("wall", int(building.site))
			return
	for slot: Dictionary in _view.get("buildingSlots", []):
		if _slot_is_empty(int(slot.get("site", -1))):
			_city_construction_dialog(int(slot.site), "wall", str(_view.get("city", {}).get("id", "")))
			return
	var content: VBoxContainer = _open_dialog("修筑城防")
	content.add_child(_label("城内用地已满。请先腾出一处地块，再修筑城防。", 16))

func _city_affairs_dialog() -> void:
	var content: VBoxContainer = _open_dialog("城务", 560)
	for entry: Array in [["market", "市场交易"], ["governance", "城守税率"], ["inn", "客栈招募"]]:
		content.add_child(_button(str(entry[1]), _show_management.bind(str(entry[0]))))
	for entry: Array in [["cities", "城池任职"], ["logistics", "运输调遣"]]:
		content.add_child(_button(str(entry[1]), _show_realm.bind(str(entry[0]))))
	content.add_child(_button("城墙与城防", _perimeter_defense_dialog))
	content.add_child(_button("安民与征收", _show_war_management.bind("civic")))

func _show_plot(index: int) -> void:
	_show_realm("plots")
	_realm.select_plot(index)

func _city_slot(site: int) -> Dictionary:
	for slot: Dictionary in _view.get("buildingSlots", []):
		if int(slot.get("site", -1)) == site:
			return slot
	return {}

func _slot_is_empty(site: int) -> bool:
	var slot: Dictionary = _city_slot(site)
	return not slot.is_empty() and not bool(slot.get("reserved", false)) and (slot.get("id") == null or str(slot.get("id", "")) == "")

func _queue_city_building(site: int, id: String, empty: bool, source: String, expected_level: int = -1) -> void:
	var slot: Dictionary = _city_slot(site)
	if str(_view.get("city", {}).get("id", "")) != source or slot.is_empty() or bool(slot.get("reserved", false)) or (not _slot_is_empty(site) if empty else str(slot.get("id", "")) != id) or (expected_level >= 0 and int(slot.get("level", 0)) != expected_level):
		_show_toast("这处建筑或城池已变化，请重新选择")
		return
	_command_close("queueBuilding", [site, id])

func _empty_site_dialog(site: int) -> void:
	if not _slot_is_empty(site):
		_show_toast("这处空地已变化，请重新选择")
		return
	var source: String = str(_view.get("city", {}).get("id", ""))
	_ensure_city_construction_panel(site, source)
	_city_construction_panel.show_catalog(true)
	call_deferred("_watch_buttons", _city_construction_panel)

func _city_texture(id: String, level: int = 1) -> Texture2D:
	return _city.art_sprite_texture(id, level) if is_instance_valid(_city) else null

func _ensure_city_construction_panel(site: int, source: String) -> void:
	if is_instance_valid(_city_construction_panel) and is_instance_valid(_dialog) and _dialog.visible and _city_construction_site == site and _city_construction_source == source:
		_city_construction_panel.update_view(_view, api != null and api.connected and not api._has_mutation())
		return
	var content: VBoxContainer = _open_dialog("空地 %d · 规划建设" % (site + 1), 780, false)
	_city_construction_site = site
	_city_construction_source = source
	_city_construction_panel = ConstructionPanelScript.new() as KingdomCityConstructionPanel
	content.add_child(_city_construction_panel)
	var panel: KingdomCityConstructionPanel = _city_construction_panel
	# Perimeter can open a quote before the first container layout pass.
	panel.size.x = maxf(1.0, content.custom_minimum_size.x)
	var window: AcceptDialog = _dialog
	panel.choose_requested.connect(func(id: String) -> void: _city_construction_dialog(site, id, source))
	panel.confirm_requested.connect(func(id: String, quote: Dictionary) -> void: _confirm_city_construction(site, id, source, quote))
	panel.upgrade_requested.connect(func(id: String, selected: int) -> void: _open_comparison_upgrade(id, selected, source))
	panel.mode_changed.connect(func(details: bool) -> void:
		if is_instance_valid(window) and _dialog == window:
			window.title = "地块 %d · 建设%s" % [site + 1, str(panel.shown_quote.get("name", "建筑"))] if details else "空地 %d · 规划建设" % (site + 1)
			call_deferred("_watch_buttons", panel))
	panel.configure(site, source, _view, CITY_BUILD_USES, _city_texture, _cost, _city_build_duration, _city_build_reason, api != null and api.connected and not api._has_mutation())

func _refresh_city_construction_panel() -> void:
	if is_instance_valid(_city_construction_panel) and is_instance_valid(_dialog) and _dialog.visible:
		var context_valid: bool = _city_construction_source == str(_view.get("city", {}).get("id", "")) and _slot_is_empty(_city_construction_site)
		_city_construction_panel.update_view(_view, context_valid and api != null and api.connected and not api._has_mutation())

func _add_city_capacity_comparison(content: VBoxContainer, id: String, selected_upgrade_site: int = -1) -> void:
	var comparisons: Dictionary = _view.get("buildingComparisons", {})
	var comparison: Variant = comparisons.get(id)
	if not id in ["house", "barracks"] or not comparison is Dictionary:
		return
	var source: String = str(_view.get("city", {}).get("id", ""))
	if str(comparison.get("cityId", source)) != source:
		return
	var compare: KingdomCityCapacityCompare = CapacityCompareScript.new() as KingdomCityCapacityCompare
	content.add_child(compare)
	compare.configure(comparison, -1, _cost, _city_build_duration, selected_upgrade_site)
	compare.upgrade_requested.connect(func(chosen_id: String, site: int) -> void: _open_comparison_upgrade(chosen_id, site, source))

func _open_comparison_upgrade(id: String, site: int, source: String) -> void:
	if str(_view.get("city", {}).get("id", "")) != source:
		_show_toast("城池已变化，请重新查看收益对照", true)
		return
	for building: Dictionary in _view.get("buildings", []):
		if str(building.get("id", "")) == id and int(building.get("site", -1)) == site and int(building.get("level", 0)) > 0:
			_building_dialog(id, site)
			return
	_show_toast("这处建筑已变化，请重新查看收益对照", true)

func _city_build_option(id: String) -> Dictionary:
	for option: Dictionary in _view.get("buildOptions", []):
		if str(option.get("id", "")) == id:
			return option.duplicate(true)
	return {}

func _city_build_reason(option: Dictionary) -> String:
	var reason: String = "" if option.get("requirement") == null else str(option.get("requirement", ""))
	if not reason.is_empty():
		return reason
	if not bool(option.get("affordable", true)):
		return "建设资源不足"
	var limit: int = int(_view.get("queueLimits", {}).get("build", 0))
	if limit > 0 and _view.get("queues", {}).get("build", []).size() >= limit:
		return "建造队正在忙碌"
	return ""

func _city_build_duration(seconds: float) -> String:
	var duration: int = maxi(0, int(ceil(seconds)))
	if duration >= 3600:
		return "%d时%02d分" % [duration / 3600, (duration % 3600) / 60]
	return "%d分%02d秒" % [duration / 60, duration % 60]

func _city_construction_dialog(site: int, id: String, source: String) -> void:
	if str(_view.get("city", {}).get("id", "")) != source or not _slot_is_empty(site):
		_show_toast("这处空地或城池已变化，请重新选择", true)
		return
	var option: Dictionary = _city_build_option(id)
	if option.is_empty():
		_show_toast("本城可建设的建筑已变化，请重新选择", true)
		_empty_site_dialog(site)
		return
	_ensure_city_construction_panel(site, source)
	_city_construction_panel.show_detail(option)
	call_deferred("_watch_buttons", _city_construction_panel)

func _confirm_city_construction(site: int, id: String, source: String, shown_quote: Dictionary) -> void:
	if str(_view.get("city", {}).get("id", "")) != source or not _slot_is_empty(site):
		_show_toast("这处空地或城池已变化，请重新选择", true)
		return
	var current: Dictionary = _city_build_option(id)
	if current.is_empty():
		_show_toast("本城可建设的建筑已变化，请重新选择", true)
		_empty_site_dialog(site)
		return
	if current.get("cost", {}) != shown_quote.get("cost", {}) or float(current.get("seconds", 0)) != float(shown_quote.get("seconds", 0)) or current.get("requirement") != shown_quote.get("requirement"):
		_city_construction_dialog(site, id, source)
		_show_toast("建造费用或条件已变化，请核对后再确认", true)
		return
	var reason: String = _city_build_reason(current)
	if not reason.is_empty():
		_city_construction_dialog(site, id, source)
		_show_toast(reason, true)
		return
	if api == null or not api.connected or api._has_mutation():
		_show_toast("请连接服务并等待上一项操作完成", true)
		return
	_queue_city_building(site, id, true, source)

func _building_dialog(id: String, chosen_site: int = -1) -> void:
	var content: VBoxContainer = _open_dialog("建筑详情")
	var source: String = str(_view.get("city", {}).get("id", ""))
	var found: bool = false
	for building: Dictionary in _view.get("buildings", []):
		if str(building.id) != id or chosen_site >= 0 and int(building.site) != chosen_site:
			continue
		found = true
		content.add_child(_label("%s · %d级" % [str(building.name), int(building.level)], 23))
		content.add_child(_label("地块 %d" % (int(building.site) + 1), 14))
		if id == "wall":
			content.add_child(_label("1级为木栅栏，2级起为石墙。\n升级完成后，围墙随等级加高。", 14))
		if id != "wall" and int(building.level) > 0 and _city_texture(id, int(building.level)) != null:
			var preview: HBoxContainer = HBoxContainer.new()
			content.add_child(preview)
			for level: int in [int(building.level), mini(10, int(building.level) + 1)]:
				var column: VBoxContainer = VBoxContainer.new()
				column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				preview.add_child(column)
				var art: TextureRect = TextureRect.new()
				art.texture = _city_texture(id, level)
				art.custom_minimum_size = Vector2(96.0, 88.0)
				art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				column.add_child(art)
				column.add_child(_label(("当前" if level == int(building.level) else "升级后") + " %d级" % level, 14))
				if int(building.level) >= 10:
					break
		match id:
			"hall": content.add_child(_button("城守税率", _show_management.bind("governance")))
			"market": content.add_child(_button("市场交易", _show_management.bind("market")))
			"inn", "tavern": content.add_child(_button("客栈招募", _show_management.bind("inn")))
			"barracks", "drill": content.add_child(_button("训练兵士", _training_dialog))
			"academy": content.add_child(_button("研究技术", _research_dialog))
			"wall": content.add_child(_button("城防建设", _show_war_management.bind("defenses")))
			"post": content.add_child(_button("运输调遣", _show_realm.bind("logistics")))
		var cost_label: Label = _label("升级消耗\n" + _cost(building.get("cost", {})))
		cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(cost_label)
		content.add_child(_label("时间 " + _remaining(Time.get_unix_time_from_system() * 1000.0 + float(building.get("seconds", 0)) * 1000.0)))
		var blocked: String = str(building.get("requirement", "")) if building.get("requirement") != null else ""
		if not blocked.is_empty():
			var requirement_label: Label = _label(blocked, 15, Color("e1b073"))
			requirement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(requirement_label)
		content.add_child(_button("升级建筑", _queue_city_building.bind(int(building.site), id, false, source, int(building.level)), not blocked.is_empty()))
		_add_city_capacity_comparison(content, id, int(building.site))
		break
	if found:
		return
	if chosen_site >= 0:
		content.add_child(_label("这处建筑已变化，请关闭后重新选择。"))
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
		content.add_child(_button("开始建造", _queue_city_building.bind(empty_site, id, true, source), empty_site < 0 or not blocked.is_empty()))

func _buildings_dialog() -> void:
	var content: VBoxContainer = _open_dialog("城内建筑", 680)
	for building: Dictionary in _view.get("buildings", []):
		content.add_child(_button(str(building.name) + "  " + str(building.level) + "级 · 地块" + str(int(building.site) + 1), _building_dialog.bind(str(building.id), int(building.site))))
	for slot: Dictionary in _view.get("buildingSlots", []):
		if slot.get("id") != null and str(slot.get("id")) != "":
			continue
		if not bool(slot.get("reserved", false)):
			content.add_child(_button("空地 " + str(int(slot.site) + 1) + " · 规划建设", _empty_site_dialog.bind(int(slot.site))))

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
	if api.mode == "shared" and tile.has("playerId"):
		_show_pvp()
		for player: Dictionary in api.shared_world.get("players", []):
			if str(player.get("id", "")) == str(tile.get("playerId", "")):
				_pvp.show_dispatch(player)
				return
		_show_toast("城池信息已变化，请刷新地图")
		return
	if api.mode == "shared":
		_show_toast("本轮共享演练请先选择玩家城池")
		return
	_open_dispatch_flow(tile, "march")

func _marches_dialog(filter: String = "all") -> void:
	_march_content = _open_dialog("驻扎部队" if filter == "stationed" else "行军与驻扎部队", 680)
	_march_filter = filter
	_march_empty = _label("暂无驻扎部队。" if filter == "stationed" else "暂无外出军队。城内训练后，在舆图选择目标出征。", 16)
	_march_content.add_child(_march_empty)
	_refresh_scout_marches()

func _add_march_row(march: Dictionary) -> void:
	var id: String = str(march.get("id", ""))
	var label: Label = _label("", 17)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_meta("march", march.duplicate(true))
	_march_content.add_child(label)
	_march_labels[id] = label
	var action: Button = Button.new()
	action.custom_minimum_size.y = 44
	action.set_meta("march_id", id)
	action.pressed.connect(func() -> void: _activate_march_action(str(action.get_meta("march_id", ""))))
	_march_content.add_child(action)
	_march_action_buttons[id] = action

func _march_row_identity(march: Dictionary) -> String:
	var id: String = str(march.get("id", ""))
	return JSON.stringify(["expedition", march.get("sourceCity", ""), march.get("node", "")]) if id.begins_with("expedition:") else id

func _start_march_battle(march: Dictionary) -> void:
	_pending_recall.clear()
	_pending_battle = true
	_send_record_command(march.get("selectCommand", {}))
	if is_instance_valid(_dialog):
		_dialog.hide()

func _command_completed(type: String, _payload: Dictionary) -> void:
	_sync_tasks_hub()
	_update_pvp()
	if is_instance_valid(_pvp):
		_pvp.acknowledge_command_success(type)
	if is_instance_valid(_audio):
		_audio.confirmed(type)
	if is_instance_valid(_management):
		_management.acknowledge_command(api.connected, api._has_mutation())
	for popup: Window in [_heroes, _progression, _war_management, _realm, _inventory, _scouting]:
		if is_instance_valid(popup):
			popup.acknowledge_command(api.connected, api._has_mutation())
	if type == "selectExpedition" and not _pending_recall.is_empty():
		var record: Dictionary = _pending_recall.duplicate(true)
		_pending_recall.clear()
		var selected: Dictionary = _state.get("expedition", {}) if _state.get("expedition") is Dictionary else {}
		if str(_view.get("city", {}).get("id", "")) == str(record.sourceCity) and str(selected.get("node", "")) == str(record.args[0]) and str(selected.get("phase", "")) == "march":
			_send_command("recall", [], str(record.sourceCity))
		else:
			_show_toast("目标部队或出发城已变化，请重新选择召回")
	elif type == "selectExpedition" and _pending_battle:
		_pending_battle = false
		_send_command("startBattle")
		_show_page("army")
	else:
		var messages: Dictionary = {
			"queueBuilding": "建设操作已结算", "upgrade": "升级操作已结算", "developPlot": "田庄建设操作已结算",
			"research": "研究操作已结算", "train": "练兵操作已结算", "buildDefense": "城防建设操作已结算",
			"claimStarterGift": "新手礼包领取已结算", "onboarding.claimAvailable": "已领取全部可领取礼包",
			"onboarding.claim": "成长礼包领取已结算", "onboarding.openItem": "开箱操作已结算，请在背包查看结果",
			"claimMission": "任务奖励领取已结算", "claimDaily": "日常奖励领取已结算", "claimReadyMissions": "主线奖励领取已结算",
			"buyItem": "购买操作已结算，请在背包查看", "useItem": "道具使用已结算", "useSpeedup": "加速操作已结算",
			"dispatch": "出征操作已结算，请查看行军", "dispatchScout": "侦察派遣已结算，请查看行军",
			"healWounded": "伤兵治疗已结算", "recruitCaptives": "士兵招降已结算", "recruitAllCaptives": "士兵招降已结算",
			"wild.recruit": "俘将招降已结算", "hero.equip": "装备穿戴已结算", "hero.forge": "装备打造已结算",
			"trainGeneralSkill": "将领专长训练已结算", "war.exchange": "军功兑换已结算，请在背包查看",
			"exchangeCopper": "铜钱兑换已结算，请核对珍宝库存", "applyPlotTemplate": "经营方案已安排，请查看施工队列",
			"supplies.buy": "军需包已入背包", "supplies.open": "军需包已打开，奖励已入库",
			"supplies.claimStarter": "首战工程补给已领取，请按成长路线安排并加速工程",
			"setBattleOrders": "全军军令已更新", "setBattleOrder": "兵队军令已更新", "battleRound": "本回合已结算",
			"recall": "部队已开始返程"
		}
		var message: String = str(messages.get(type, "操作已完成"))
		if type in ["supplies.open", "supplies.claimStarter"]:
			var rewards: PackedStringArray = []
			var result: Dictionary = _payload.get("result", {}) if _payload.get("result") is Dictionary else {}
			for item_id: String in result.get("items", {}):
				var item_name: String = item_id
				for item: Dictionary in _view.get("inventoryManagement", {}).get("items", []):
					if str(item.get("id", "")) == item_id:
						item_name = str(item.get("name", item_id))
				rewards.append(item_name + " ×" + str(int(result.items[item_id])))
			for id: String in result.get("resources", {}):
				rewards.append(str(RES_NAMES.get(id, id)) + " +" + str(int(result.resources[id])))
			if not result.get("bundles", {}).is_empty():
				rewards.append("百工调拨令 ×1")
			if not rewards.is_empty():
				message += "\n" + "、".join(rewards)
		_show_toast(message + " · 进度已保存")
	_sync_objective_actions()
	if type == "battleRound":
		_celebrate_county_receipt(_payload)
	if type == "switchCity" and not _county_after_switch.is_empty():
		var destination: String = _county_after_switch
		_county_after_switch = ""
		if not _payload.get("replayed", false) and int(_payload.get("revision", -1)) >= api.revision and str(_view.get("city", {}).get("id", "")) == destination:
			_show_county_governance()

func _send_command(type: String, args: Array = [], source_city: String = "") -> void:
	if type == "battleRound":
		_county_battle_pending.clear()
		var live: Variant = _view.get("battle")
		if api.connected and not api._has_mutation() and api.mode == "local" and _county_baseline and _owned_named_cities().is_empty() and live is Dictionary and not live.get("finished", false):
			_county_battle_pending = {"identity": _campaign_identity(), "node": live.get("node", ""), "general": live.get("general", ""), "sourceCity": live.get("sourceCity", "")}
	api.command(type, args, source_city)
	if is_instance_valid(_report_recovery):
		_report_recovery.set_navigation_state(api.connected, api._has_mutation())
	if is_instance_valid(_raid_targets):
		_raid_targets.set_navigation_state(api.connected, api._has_mutation())
	_sync_objective_actions()
	_refresh_city_construction_panel()
	_sync_tasks_hub()
	_refresh_scout_marches()

func _send_record_command(record: Dictionary) -> void:
	if record.is_empty():
		return
	_send_command(str(record.type), record.get("args", []), str(record.get("sourceCity", "")))

func _battle_action(type: String, args: Array) -> void:
	_send_command(type, args)

func _command_close(type: String, args: Array) -> void:
	_send_command(type, args)
	if is_instance_valid(_dialog):
		_dialog.hide()

func _objective_action() -> void:
	if api.mode == "shared":
		_show_pvp()
		return
	var objective: Dictionary = _view.get("objective", {})
	if objective.get("ready", false) and not str(objective.get("action", "")).is_empty():
		_send_command(str(objective.action), objective.get("args", []))
	else:
		_route_objective(str(objective.get("route", "inner")), str(objective.get("target", "")))

func _tasks_dialog() -> void:
	var content: VBoxContainer = _open_dialog("城池事务", 680)
	var objective: Dictionary = _current_objective()
	_tasks_labels.clear()
	for entry: Array in [[str(objective.get("title", "当前目标")), 21], [str(objective.get("description", "连接后显示当前任务")), 15], ["奖励 " + _reward_text(objective), 14]]:
		var label: Label = _label(str(entry[0]), int(entry[1]))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(label)
		_tasks_labels.append(label)
	_tasks_action = _button("领取奖励" if objective.get("ready", false) else "前往当前目标", _objective_action)
	_tasks_action.theme_type_variation = "PrimaryButton"
	content.add_child(_tasks_action)
	var tabs: TabContainer = TabContainer.new()
	tabs.name = "TransactionsTabs"
	tabs.tab_focus_mode = Control.FOCUS_ALL
	tabs.custom_minimum_size.y = 220.0
	content.add_child(tabs)
	var groups: Array = [
		["成长", [["成长路线", _show_growth_route], ["主线任务", _show_progression.bind("missions")], ["每日任务", _show_progression.bind("daily")], ["黄巾史诗", _show_progression.bind("epic")], ["官职与爵位", _show_progression.bind("honors")], ["征战章节", _show_progression.bind("chapters")], ["十阶礼包", _show_progression.bind("gifts")], ["领取已解锁礼包", _command_close.bind("onboarding.claimAvailable", [])]]],
		["经营", [["市场交易", _show_management.bind("market")], ["城守与税率", _show_management.bind("governance")], ["城池与运输", _show_realm.bind("cities")], ["城外资源", _plots_dialog], ["研究", _research_dialog], ["挂机设置", _show_realm.bind("automation")]]],
		["军务", [["客栈招募", _show_management.bind("inn")], ["野地抓将", _show_heroes.bind("wild")], ["伤兵与俘虏", _show_war_management.bind("hospital")], ["黄巾来袭", _show_war_management.bind("defense")], ["玩家战争", _show_pvp]]],
		["物资", [["宝物与物资", _inventory_dialog], ["商城", _show_inventory.bind("shop")], ["领地采集", _show_realm.bind("holdings")], ["存档与备份", _save_dialog], ["联机大厅", _show_lobby], ["按键设置", _show_input_settings]]]
	]
	for group: Array in groups:
		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.name = str(group[0])
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var actions: GridContainer = GridContainer.new()
		actions.columns = 2
		actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(actions)
		for entry: Array in group[1]:
			if str(entry[0]) == "成长路线" and api != null and api.mode == "shared":
				continue
			var action: Button = _button(str(entry[0]), entry[1])
			action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			actions.add_child(action)
	_sync_tasks_hub()

func _sync_tasks_hub() -> void:
	if not is_instance_valid(_dialog) or not _dialog.visible or _dialog.title != "城池事务" or _tasks_labels.size() != 3 or not is_instance_valid(_tasks_action):
		return
	var objective: Dictionary = _current_objective()
	_tasks_labels[0].text = str(objective.get("title", "当前目标"))
	_tasks_labels[1].text = str(objective.get("description", "连接后显示当前任务"))
	_tasks_labels[2].text = "奖励 " + _reward_text(objective)
	_tasks_action.text = "领取奖励" if objective.get("ready", false) else "前往当前目标"
	_tasks_action.disabled = not api.connected or api._has_mutation()

func _show_management(section: String) -> void:
	_remember_keyboard_focus()
	_stop_keyboard_pan()
	_hide_feature_panels()
	if is_instance_valid(_lobby):
		_lobby.hide()
	if is_instance_valid(_input_settings_dialog):
		_input_settings_dialog.hide()
	if is_instance_valid(_dialog):
		_dialog.hide()
	if not is_instance_valid(_management):
		_management = ManagementScript.new() as KingdomManagementDialog
		add_child(_management)
		_management.command_requested.connect(func(type: String, args: Array) -> void: _send_command(type, args))
		_management.visibility_changed.connect(_on_popup_visibility.bind(_management))
	_management.set_command_state(api.connected, api._has_mutation())
	_management.show_section(section, _view)
	call_deferred("_watch_buttons", _management)

func _plots_dialog() -> void:
	_show_realm("plots")

func _research_dialog() -> void:
	var content: VBoxContainer = _open_dialog("研究")
	for tech: Dictionary in _view.get("techs", []):
		content.add_child(_label(str(tech.name) + " · " + str(tech.level) + "级", 18))
		var reason: String = "" if tech.get("requirement") == null else str(tech.get("requirement", ""))
		content.add_child(_label(_cost(tech.get("cost", {})) + ("\n" + reason if not reason.is_empty() else ""), 14))
		content.add_child(_button("开始研究", _command_close.bind("research", [str(tech.id)]), not reason.is_empty()))
	content.add_child(_button("开启自动研究", _command_close.bind("setAutoResearch", [true])))
	content.add_child(_button("关闭自动研究", _command_close.bind("setAutoResearch", [false])))
	content.add_child(_button("研究方向与资源保留", _show_realm.bind("automation")))

func _inventory_dialog() -> void:
	_show_inventory("inventory")

func _show_growth_route() -> void:
	if api == null or api.mode == "shared" or _view.get("growth", {}).is_empty():
		_show_toast("本机进度连接后可查看成长路线")
		return
	var content: VBoxContainer = _open_dialog("成长路线", 680)
	_growth_route = GrowthRouteScript.new() as KingdomGrowthRouteView
	content.add_child(_growth_route)
	_growth_route.navigate_requested.connect(_route_objective)
	_growth_route.speedup_requested.connect(_confirm_growth_speedup)
	_sync_growth_route()
	call_deferred("_watch_buttons", _growth_route)

func _show_practice() -> void:
	if api == null or api.mode != "local" or not api.connected or api._has_mutation():
		_show_toast("连接本机进度并等待当前操作确认后，可借调部队演练。")
		return
	if not is_instance_valid(_practice):
		_practice = PracticeScript.new() as KingdomPracticeDialog
		_practice.api = api
		add_child(_practice)
		_practice.campaign_requested.connect(_show_growth_route)
		_practice.visibility_changed.connect(_on_popup_visibility.bind(_practice))
	_prepare_feature_panel(_practice)
	_practice.open_practice()

func _campaign_identity() -> String:
	return api.base_url + "|" + api._authority + "|" + api.mode if api != null else ""

func _growth_speedup_target(item_id: String, target_key: String) -> Dictionary:
	for item: Dictionary in _view.get("inventoryManagement", {}).get("items", []):
		if str(item.get("id", "")) != item_id or int(item.get("count", 0)) < 1:
			continue
		var use: Dictionary = item.get("use", {})
		if str(use.get("targetKind", "")) != "speedup" or not str(use.get("reason", "")).is_empty():
			return {}
		for target: Dictionary in use.get("targets", []):
			if str(target.get("key", "")) == target_key and str(target.get("reason", "")).is_empty() and not target.get("quote", {}).get("error"):
				return {"item": item, "target": target}
	return {}

func _confirm_growth_speedup(item_id: String, target_key: String) -> void:
	if api == null or api.mode != "local" or not api.connected or api._has_mutation():
		return
	var preview: Dictionary = _growth_speedup_target(item_id, target_key)
	if preview.is_empty():
		_show_toast("这项队列或库存已变化，请重新查看成长路线。", true)
		return
	var source: String = str(_view.get("city", {}).get("id", ""))
	var identity: String = _campaign_identity()
	var item: Dictionary = preview.item
	var target: Dictionary = preview.target
	var quote: Dictionary = target.get("quote", {})
	var content: VBoxContainer = _open_dialog("确认使用加速", 600)
	content.add_child(_report_label("消耗 %s ×1 · 当前拥有 %d 件" % [str(item.get("name", "加速")), int(item.get("count", 0))], 20))
	content.add_child(_report_label(str(target.get("name", "当前队列"))))
	content.add_child(_report_label("工作剩余 %s · 排队等待 %s\n本次缩短范围 %s～%s\n使用后工作剩余 %s～%s；排队时间另计。" % [_time_text(float(quote.get("workMs", 0)) / 1000.0), _time_text(float(quote.get("waitMs", 0)) / 1000.0), _time_text(float(quote.get("minMs", 0)) / 1000.0), _time_text(float(quote.get("maxMs", 0)) / 1000.0), _time_text(float(quote.get("afterMinMs", 0)) / 1000.0), _time_text(float(quote.get("afterMaxMs", 0)) / 1000.0)]))
	if quote.get("overflow", false):
		content.add_child(_report_label("超出工作时间的加速不会保留，请确认是否值得消耗。", 15, Color("edb68f")))
	content.add_child(_report_label("上方是当前预览；实际剩余时间随时间推进，最终以原规则回执为准。", 14))
	var confirm: Button = _button("确认消耗1件", func() -> void:
		if not api.connected or api._has_mutation() or identity != _campaign_identity() or source != str(_view.get("city", {}).get("id", "")) or _growth_speedup_target(item_id, target_key).is_empty():
			_show_toast("当前城池、队列或库存已变化，请重新预览。", true)
			return
		_send_command("useSpeedup", [item_id, target_key], source)
		_dialog.hide())
	confirm.theme_type_variation = "PrimaryButton"
	content.add_child(confirm)
	content.add_child(_button("返回成长路线", _show_growth_route))

func _time_text(seconds: float) -> String:
	var amount: int = maxi(0, int(ceil(seconds)))
	return "%d时%02d分" % [amount / 3600, (amount % 3600) / 60] if amount >= 3600 else "%d分%02d秒" % [amount / 60, amount % 60]

func _owned_named_cities() -> Dictionary:
	var result: Dictionary = {}
	for city: Dictionary in _view.get("realmManagement", {}).get("cities", []):
		var identity: Dictionary = city.get("identity", {})
		if identity.get("owned", false) and str(identity.get("id", "")) == str(city.get("node", "")) and str(identity.get("tier", "")) == "county":
			result[str(city.get("id", ""))] = city
	return result

func _reset_county_context() -> void:
	_county_baseline = false
	_county_conquest.clear()
	_county_after_switch = ""
	_county_battle_pending.clear()
	if is_instance_valid(_county_conquest_button):
		_county_conquest_button.visible = false

func _establish_county_baseline() -> void:
	# Polling and imports only establish the current baseline. Celebration is
	# restricted to the fresh, non-replayed battle command receipt below.
	_county_baseline = true

func _celebrate_county_receipt(payload: Dictionary) -> void:
	var pending: Dictionary = _county_battle_pending.duplicate(true)
	_county_battle_pending.clear()
	if pending.is_empty() or str(pending.get("identity", "")) != _campaign_identity() or api.mode != "local" or payload.get("replayed", false) or int(payload.get("revision", -1)) < api.revision:
		return
	var live: Variant = _view.get("battle")
	if not live is Dictionary or not live.get("finished", false):
		return
	var result: Dictionary = live.get("result", {})
	if not result.get("claimed", false) or not result.get("won", false) or str(live.get("mode", "")) != "occupy":
		return
	for key: String in ["node", "general", "sourceCity"]:
		if str(live.get(key, "")) != str(pending.get(key, "")):
			return
	var current: Dictionary = _owned_named_cities()
	if current.is_empty() or not _county_conquest.is_empty():
		return
	for report: Dictionary in _view.get("reports", []):
		var city_id: String = "city_" + str(report.get("node", ""))
		if not current.has(city_id) or not report.get("claimed", false) or not report.get("won", false) or str(report.get("mode", "")) != "occupy" or int(report.get("round", -1)) != int(live.get("round", -2)):
			continue
		var matches: bool = true
		for key: String in ["node", "general", "sourceCity"]:
			if str(report.get(key, "")) != str(pending.get(key, "")):
				matches = false
		if not matches:
			continue
		_county_conquest = {"city": current[city_id], "report": report.duplicate(true), "identity": _campaign_identity()}
		_show_toast(str(current[city_id].get("name", "县城")) + "真正归附 · 新领地已加入己方城池。")
		_sync_objective_actions()
		return

func _sync_county_identity() -> void:
	if not is_instance_valid(_county_identity_label):
		return
	_county_identity_label.text = ""
	for city: Dictionary in _view.get("realmManagement", {}).get("cities", []):
		if str(city.get("id", "")) != str(_view.get("city", {}).get("id", "")):
			continue
		var identity: Dictionary = city.get("identity", {})
		_county_identity_label.text = "⚑ " + str(city.get("name", "")) + " · " + str(identity.get("tierName", "")) if identity.get("owned", false) else ""

func _show_county_conquest() -> void:
	if _county_conquest.is_empty() or str(_county_conquest.get("identity", "")) != _campaign_identity():
		return
	var city: Dictionary = _county_conquest.city
	var id: String = str(city.get("id", ""))
	if not _owned_named_cities().has(id):
		_county_conquest.clear()
		_sync_objective_actions()
		return
	var report: Dictionary = _county_conquest.report
	var content: VBoxContainer = _open_dialog("县城归附 · 经营一城，治理一地", 680)
	content.add_child(_report_label("⚑ " + str(city.get("name", "县城")) + "已加入你的领地", 24, Color("d8c28b")))
	content.add_child(_report_label("这是实际易主后的新城。仅击退守军或降低民心不会触发归附提示。", 14))
	content.add_child(_report_label("幸存部队驻扎新城。" if report.get("stationed", false) else "幸存部队正返回原出发城。"))
	content.add_child(_report_label("战利品按原规则结算到出发城；新城需要安排补给、人口与驻军。"))
	if str(city.get("node", "")) == "fort":
		for chapter: Dictionary in _view.get("progression", {}).get("chapters", []):
			if int(chapter.get("chapter", chapter.get("id", 0))) == 2 and chapter.get("unlocked", false):
				content.add_child(_report_label("第二章已开放 · 下一步可查看征战章节。", 18, Color("bdcc9e")))
	content.add_child(_button("进入新城 · 选择安民、征粮或补给", func() -> void:
		if not api.connected or api._has_mutation() or str(_county_conquest.get("identity", "")) != _campaign_identity() or not _owned_named_cities().has(id):
			_show_toast("请核对当前城池与连接后再进入新城。", true)
			return
		if str(_view.get("city", {}).get("id", "")) == id:
			_show_county_governance()
		else:
			_county_after_switch = id
			_send_command("switchCity", [id])
			_dialog.hide()))
	content.add_child(_button("查看下一章与目标", _show_progression.bind("chapters")))
	content.add_child(_button("我已了解，继续经营", func() -> void:
		_county_conquest.clear()
		_sync_objective_actions()
		_dialog.hide()))

func _show_county_governance() -> void:
	if api == null or api.mode != "local":
		_show_toast("领地治理用于本机已占名城。")
		return
	var source: String = str(_view.get("city", {}).get("id", ""))
	var identity: String = _campaign_identity()
	var content: VBoxContainer = _open_dialog("领地治理", 680)
	_county_source = source
	_county_governance = CountyGovernanceScript.new() as KingdomCountyGovernanceView
	content.add_child(_county_governance)
	_county_governance.route_requested.connect(_route_county_governance)
	_county_governance.command_requested.connect(func(type: String, args: Array) -> void:
		if not api.connected or api._has_mutation() or identity != _campaign_identity() or source != str(_view.get("city", {}).get("id", "")):
			_show_toast("城池或连接已变化，请重新打开治理页面。", true)
			return
		_send_command(type, args, source))
	_sync_county_governance()
	call_deferred("_watch_buttons", _county_governance)

func _sync_county_governance() -> void:
	if not is_instance_valid(_county_governance):
		return
	var current: bool = _county_source == str(_view.get("city", {}).get("id", ""))
	_county_governance.update_view(_view if current else {})
	_county_governance.set_command_state(api.connected and current, api._has_mutation())

func _route_county_governance(section: String, target: String) -> void:
	if api == null or not api.connected or api._has_mutation():
		return
	if section != "cities" and not target.is_empty() and target != "fort" and target != str(_view.get("city", {}).get("id", "")):
		_show_toast("当前城池已变化，请重新选择。", true)
		return
	match section:
		"civic": _show_war_management("civic")
		"governance": _show_management("governance")
		"logistics":
			_show_realm("cities")
			_show_toast("补给新城：先切到有物资的出发城，再打开运输调遣，选择这座新城作为目的地。")
		"cities": _show_realm("cities")
		"world": _route_objective("world", target)
		_: _show_growth_route()

func _show_raid_targets() -> void:
	if api == null or api.mode == "shared":
		_show_toast("掠夺找资源用于本机野地；共享房间请查看玩家战争。")
		return
	var content: VBoxContainer = _open_dialog("掠夺找资源", 680)
	_raid_targets = RaidTargetsScript.new() as KingdomRaidTargetsView
	content.add_child(_raid_targets)
	_raid_targets.update_view(_view)
	_raid_targets.set_navigation_state(api.connected, api._has_mutation())
	_raid_targets.target_requested.connect(_prepare_raid_target)
	call_deferred("_watch_buttons", _raid_targets)

func _prepare_raid_target(id: String) -> void:
	if not is_instance_valid(_raid_targets) or api == null or api.mode == "shared" or not api.connected or api._has_mutation():
		return
	# Resolve against this actor's latest safe world before opening the same
	# preparation flow as a map click. This never sends a dispatch command.
	var target: Dictionary = {}
	for tile: Dictionary in _world.get("tiles", []):
		if str(tile.get("id", "")) == id and not tile.get("hidden", false) and not tile.get("owned", false):
			target = tile
			break
	if target.is_empty():
		_show_toast("目标已变化或尚未显示，请刷新舆图后重新选择。", true)
		return
	if is_instance_valid(_dialog):
		_dialog.hide()
	_selected = target.duplicate(true)
	_show_page("world")
	_map.focus_tile(int(target.get("x", 0)), int(target.get("y", 0)))
	var intel: Dictionary = _intel_node(target).get("intel", {})
	var expiry: Variant = intel.get("expiresAt")
	var exact: bool = str(intel.get("precision", "")) == "exact" and (expiry is int or expiry is float) and float(expiry) > _intel_now()
	_open_dispatch_flow(target, "march" if bool(intel.get("public", false)) or exact else "scout")

func _sync_growth_route() -> void:
	if is_instance_valid(_growth_route) and is_instance_valid(_dialog) and _dialog.visible:
		_growth_route.update_view(_view)
		_growth_route.set_navigation_state(api != null and api.connected, api != null and api._has_mutation())

func _report_identity(report: Dictionary) -> String:
	return JSON.stringify([report.get("shared", false), report.get("id"), report.get("node"), report.get("source"), report.get("target"), report.get("sourceCity")])

func _sync_report_economy() -> void:
	if not is_instance_valid(_report_economy) or not is_instance_valid(_dialog) or not _dialog.visible:
		return
	if is_instance_valid(_report_loot):
		_report_loot.set_navigation_state(api.connected, api._has_mutation())
	if is_instance_valid(_report_recovery):
		_report_recovery.set_navigation_state(api.connected, api._has_mutation())
	for report: Dictionary in _view.get("reports", []):
		if _report_identity(report) == _report_key:
			if is_instance_valid(_report_review):
				_report_review.set_review(report.get("review", {}))
			if is_instance_valid(_report_recovery):
				_report_recovery.update_context(report, _view, api.connected, api._has_mutation())
			var economy: Dictionary = report.get("economy", {})
			var signature: String = JSON.stringify(economy)
			if signature != _economy_signature:
				_economy_signature = signature
				_report_economy.set_economy(economy)
			return

func _report_dialog(report: Dictionary) -> void:
	# A list/PvP button may hold an older report while its march is returning.
	# Resolve the latest actor-scoped projection before showing delivery proof.
	for latest: Dictionary in _view.get("reports", []):
		if _report_identity(latest) == _report_identity(report):
			report = latest
			break
	var content: VBoxContainer = _open_dialog("战报", 740)
	content.add_child(_report_label(_report_title(report), 22))
	_report_key = _report_identity(report)
	_report_economy = ReportEconomyScript.new() as KingdomReportEconomyView
	_economy_signature = JSON.stringify(report.get("economy", {}))
	_report_economy.set_economy(report.get("economy", {}))
	content.add_child(_report_economy)
	_report_recovery = PostBattleScript.new() as KingdomPostBattleActions
	content.add_child(_report_recovery)
	_report_recovery.update_context(report, _view, api.connected, api._has_mutation())
	_report_recovery.route_requested.connect(_route_report_recovery)
	_report_loot = ReportLootScript.new() as KingdomReportLootView
	content.add_child(_report_loot)
	_report_loot.set_report(report, _view)
	_report_loot.set_navigation_state(api.connected, api._has_mutation())
	_report_loot.navigate_requested.connect(func(section: String) -> void:
		if section == "inventory":
			_show_inventory("inventory")
		elif section == "equipment":
			_show_heroes("equipment")
		elif section == "hero_captives":
			_show_heroes("captives")
		elif section == "soldier_captives":
			_show_war_management("captives"))
	# Keep the next action and rewards ahead of the longer accounting breakdown.
	content.move_child(_report_recovery, 1)
	content.move_child(_report_loot, 2)
	if not report.get("shared", false):
		_report_review = BattleReviewScript.new() as KingdomBattleReviewView
		content.add_child(_report_review)
		_report_review.set_review(report.get("review", {}))
		content.move_child(_report_review, 3)
	if report.get("shared", false):
		_render_shared_report(content, report)
		return
	content.add_child(_report_label("交战 " + str(int(report.get("round", 0))) + " 回合 · 将领经验 +" + str(int(report.get("xp", 0)))))
	for line: String in ["永久损失：" + _army_text(report.get("lost", {})), "伤兵入营：" + _army_text(report.get("wounded", {})), "幸存部队：" + _army_text(report.get("back", {})), "俘虏士兵：" + _army_text(report.get("captures", {}))]:
		var label: Label = _report_label(line, 16)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(label)
	if bool(report.get("claimed", false)):
		content.add_child(_report_label("已占领目标，" + ("幸存部队驻扎当地。" if report.get("stationed", false) else "部队返回出发城。"), 16, Color("bdcc9e")))
	elif report.get("stationed", false):
		content.add_child(_report_label("部队驻扎当地；民心尚未归附。"))
	else:
		content.add_child(_report_label("幸存部队返回出发城。"))
	var failure: Variant = report.get("failure")
	if failure is Dictionary:
		var reasons: Dictionary = {"retreat": "主动撤退", "army": "我军损失殆尽", "gate": "未攻破城门", "enemy": "未击败全部守军", "gate_and_enemy": "城门与守军均未突破"}
		content.add_child(_report_label("败因：" + str(reasons.get(failure.get("reason", ""), "战线未能突破")), 16, Color("dfa481")))
		if bool(failure.get("outOfRange", false)):
			content.add_child(_report_label("仍有部队未进入射程；可调整兵种或前进命令。", 15))

func _route_report_recovery(section: String) -> void:
	if not is_instance_valid(_report_recovery) or api == null or not api.connected or api._has_mutation():
		return
	if section in ["hospital", "training"] and _report_recovery.source_city() != str(_view.get("city", {}).get("id", "")):
		_show_realm("cities")
		return
	match section:
		"hospital": _show_war_management("hospital")
		"training": _training_dialog()
		"cities": _show_realm("cities")
		"growth": _show_growth_route()

func _report_label(text: String, font_size: int = 16, color: Color = Color("e1dfcd")) -> Label:
	var label: Label = _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _report_title(report: Dictionary) -> String:
	if report.get("shared", false):
		return _shared_player_name(str(report.get("source", ""))) + " → " + _shared_player_name(str(report.get("target", ""))) + " · " + ("攻方胜利" if report.get("won", false) else "守方守住")
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
	var campaign_target: Dictionary = _campaign_target(id)
	if not campaign_target.is_empty():
		return str(campaign_target.get("name", id))
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
	content.add_child(_label("私人试玩使用本地进度。共享演练请使用同一服务地址和各自账号令牌；双方进度分开保存。", 15))
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

func _web_room_invitation() -> String:
	if not OS.has_feature("web"):
		return ""
	var value: Variant = JavaScriptBridge.eval("(() => { const hash = window.location.hash; if (!hash.startsWith('#room=')) return ''; let value = ''; try { value = decodeURIComponent(hash.slice(6)); } catch (_) {} window.history.replaceState(window.history.state, '', window.location.pathname + window.location.search); return /^[a-f0-9]{64}$/.test(value) ? value : ''; })()", true)
	return value if value is String else ""

func _new_lobby_service() -> KingdomLobbyApi:
	return LobbyApiScript.new() as KingdomLobbyApi

func _show_lobby(invite_code: String = "", service_url: String = "") -> void:
	_remember_keyboard_focus()
	_stop_keyboard_pan()
	for window: Window in [_dialog, _pvp, _management, _input_settings_dialog, _heroes, _progression, _war_management, _realm, _inventory, _scouting]:
		if is_instance_valid(window):
			window.hide()
	if not is_instance_valid(_lobby_api):
		_lobby_api = _new_lobby_service()
		add_child(_lobby_api)
		_lobby_api.account_signed_out.connect(func() -> void: api.disconnect_account())
	if not service_url.is_empty():
		_lobby_api.configure_url(service_url)
	if not is_instance_valid(_lobby):
		_lobby = LobbyDialogScript.new() as KingdomLobbyDialog
		add_child(_lobby)
		_lobby.setup(_lobby_api)
		_lobby.connection_requested.connect(func(url: String, access_token: String, expected_identity: Dictionary) -> void:
			api.connect_to(url, access_token, expected_identity, _lobby_api.account_session))
		_lobby.advanced_requested.connect(_connection_dialog)
		_lobby.reconnect_requested.connect(func() -> void:
			if api.token.is_empty():
				_lobby.connection_status("尚无当前会话，请创建、加入或恢复席位", false, api.actor, api.room, api._authority)
			else:
				api.retry_last())
		_lobby.visibility_changed.connect(_on_popup_visibility.bind(_lobby))
	_lobby.show_lobby(api.actor, api.room, api.connected, invite_code)

func _scrub_retiring_window(node: Node) -> void:
	# Retirement is deferred so a Window can finish dispatching its input.
	# Clear its display data synchronously without emitting editor/selection
	# signals that could rebuild old actor controls or request an old quotation.
	var signals_were_blocked: bool = node.is_blocking_signals()
	node.set_block_signals(true)
	if node is Control:
		(node as Control).tooltip_text = ""
	if node is Window:
		(node as Window).title = ""
	if node is AcceptDialog:
		(node as AcceptDialog).dialog_text = ""
	if node is Label or node is Button or node is RichTextLabel or node is TextEdit or node is LineEdit:
		node.set("text", "")
	if node is LineEdit:
		(node as LineEdit).placeholder_text = ""
	if node is TextEdit:
		(node as TextEdit).placeholder_text = ""
	if node is OptionButton:
		(node as OptionButton).clear()
	if node is PopupMenu:
		(node as PopupMenu).clear()
	for child: Node in node.get_children():
		_scrub_retiring_window(child)
	node.set_block_signals(signals_were_blocked)

func _mode_changed(_mode: String) -> void:
	_reset_county_context()
	_county_identity_label = null
	_county_governance = null
	_county_source = ""
	_report_review = null
	if is_instance_valid(_practice):
		_practice.clear_context()
	if is_instance_valid(_notifications):
		_notifications.clear_context()
	_city_construction_panel = null
	_city_construction_site = -1
	_city_construction_source = ""
	_city_objective_expanded = false
	_pending_recall.clear()
	if is_instance_valid(_activity_bar):
		_activity_bar.clear_context()
	_resource_detail_labels.clear()
	_resource_status = null
	# This signal also covers actor/authority changes within the same mode.
	# Clear derived Controls now: the replacement snapshot may never arrive.
	_view.clear()
	_state.clear()
	_world.clear()
	_selected.clear()
	_scouting_target_id = ""
	_city_zone = "inner"
	_last_structure = ""
	_pending_battle = false
	for id: String in _resources:
		var label: Label = _resources[id]
		label.text = str(RES_NAMES[id]) + "  —"
		label.tooltip_text = ""
		label.modulate = Color.WHITE
		if _resource_buttons.has(id):
			_resource_buttons[id].tooltip_text = ""
			_resource_buttons[id].disabled = true
	_objective_title.text = "等待当前进度"
	_objective_title.tooltip_text = ""
	_objective_text.text = "正在读取城池与目标…"
	_objective_text.tooltip_text = ""
	_objective_button.text = "查看目标"
	_objective_button.disabled = true
	_compact_objective_title.text = "当前目标 · 等待当前进度"
	_compact_objective_title.tooltip_text = ""
	_compact_objective_text.text = "正在读取城池与目标…"
	_compact_objective_text.tooltip_text = ""
	_compact_objective_button.text = "前往"
	_compact_objective_button.disabled = true
	_popup_return_focus = null
	_growth_route = null
	_report_economy = null
	_report_loot = null
	_report_recovery = null
	_raid_targets = null
	_report_key = ""
	_economy_signature = ""
	_detail_intel = null
	_dispatch_intel = null
	_dispatch_intel_target.clear()
	_march_labels.clear()
	_march_action_buttons.clear()
	_march_content = null
	_march_empty = null
	_intel_server_offset = 0.0
	if is_instance_valid(_scouting):
		_scouting.clear_context()
	var retiring_windows: Array[Window] = [_pvp, _dialog, _management, _heroes, _progression, _war_management, _realm, _inventory, _scouting, _practice]
	# Earlier dialog transitions may already have queued a Window for deletion
	# during this same frame; those no longer have a cached field reference.
	for child: Node in get_children():
		if child is Window and (child.is_queued_for_deletion() or retiring_windows.has(child)):
			_scrub_retiring_window(child)
	for window: Window in retiring_windows:
		if is_instance_valid(window):
			window.hide()
			window.queue_free()
	_pvp = null
	_dialog = null
	_management = null
	_heroes = null
	_progression = null
	_war_management = null
	_realm = null
	_inventory = null
	_scouting = null
	_practice = null
	_save_text = null
	_show_toast("正在读取当前进度…")
	_show_page(_page)
	_adapt_layout()
	_sync_objective_actions()
	if is_instance_valid(_pvp_button):
		_pvp_button.text = "共享战争" if api.mode == "shared" else "玩家战争"
	if is_instance_valid(_lobby):
		_lobby.clear_other_identity(api.actor, api.room, api._authority)

func _update_pvp() -> void:
	if api == null:
		return
	if is_instance_valid(_lobby):
		_lobby._update_current(api.actor, api.room, api.connected)
	if not is_instance_valid(_pvp):
		return
	_pvp.update_data(_view, api.shared_world, api.actor, float(api.last_snapshot.get("serverTime", Time.get_unix_time_from_system() * 1000.0)), api.connected and not api._has_mutation(), api.room)

func _show_pvp() -> void:
	_remember_keyboard_focus()
	if api == null or api.mode != "shared":
		_show_lobby()
		_show_toast("请在联机大厅创建、加入或恢复自己的房间城主")
		return
	_stop_keyboard_pan()
	for window: Window in [_dialog, _management, _input_settings_dialog, _lobby, _heroes, _progression, _war_management, _realm, _inventory, _scouting]:
		if is_instance_valid(window):
			window.hide()
	if not is_instance_valid(_pvp):
		_pvp = PvpDialogScript.new() as KingdomPvpDialog
		add_child(_pvp)
		_pvp.command_requested.connect(func(type: String, args: Array) -> void: _send_command(type, args))
		_pvp.focus_requested.connect(func(x: int, y: int) -> void:
			_pvp.hide()
			_show_page("world")
			_map.focus_tile(x, y))
		_pvp.report_requested.connect(_report_dialog)
		_pvp.visibility_changed.connect(_on_popup_visibility.bind(_pvp))
	_update_pvp()
	_pvp.show_world()

func _shared_player_name(id: String) -> String:
	for player: Dictionary in api.shared_world.get("players", []):
		if str(player.get("id", "")) == id:
			return str(player.get("name", "城主"))
	return "城主"

func _hide_feature_panels(except: Window = null) -> void:
	for popup: Window in [_heroes, _progression, _war_management, _realm, _inventory, _scouting, _practice]:
		if is_instance_valid(popup) and popup != except:
			popup.hide()

func _prepare_feature_panel(popup: Window) -> void:
	_remember_keyboard_focus()
	call_deferred("_watch_buttons", popup)
	_stop_keyboard_pan()
	_hide_feature_panels(popup)
	for window: Window in [_dialog, _management, _lobby, _pvp, _input_settings_dialog, _menu]:
		if is_instance_valid(window) and window != popup:
			window.hide()
	popup.set_command_state(api.connected, api._has_mutation())

func _show_heroes(section: String = "generals") -> void:
	if not is_instance_valid(_heroes):
		_heroes = HeroScript.new() as KingdomHeroDialog
		add_child(_heroes)
		_heroes.command_requested.connect(func(type: String, args: Array) -> void: _send_command(type, args))
		_heroes.focus_requested.connect(_focus_world)
		_heroes.dispatch_requested.connect(_dispatch_node)
		_heroes.visibility_changed.connect(_on_popup_visibility.bind(_heroes))
	_prepare_feature_panel(_heroes)
	_heroes.show_section(section, _view)

func _show_progression(section: String = "missions") -> void:
	if not is_instance_valid(_progression):
		_progression = ProgressionScript.new() as KingdomProgressionDialog
		add_child(_progression)
		_progression.command_requested.connect(func(type: String, args: Array) -> void: _send_command(type, args))
		_progression.route_requested.connect(_route_objective)
		_progression.visibility_changed.connect(_on_popup_visibility.bind(_progression))
	_prepare_feature_panel(_progression)
	_progression.show_section(section, _view)

func _show_war_management(section: String = "hospital") -> void:
	if not is_instance_valid(_war_management):
		_war_management = WarManagementScript.new() as KingdomWarManagementDialog
		add_child(_war_management)
		_war_management.command_requested.connect(func(type: String, args: Array) -> void: _send_command(type, args))
		_war_management.visibility_changed.connect(_on_popup_visibility.bind(_war_management))
	_prepare_feature_panel(_war_management)
	_war_management.show_section(section, _view)

func _show_realm(section: String = "cities") -> void:
	if not is_instance_valid(_realm):
		_realm = RealmScript.new() as KingdomRealmDialog
		add_child(_realm)
		_realm.command_requested.connect(func(type: String, args: Array) -> void: _send_command(type, args))
		_realm.quote_requested.connect(func(kind: String, args: Array, request_id: String) -> void: api.request_quote(kind, args, request_id))
		_realm.focus_requested.connect(_focus_world)
		_realm.visibility_changed.connect(_on_popup_visibility.bind(_realm))
	_prepare_feature_panel(_realm)
	_realm.show_section(section, _view)

func _receive_quote(payload: Dictionary) -> void:
	if is_instance_valid(_scouting):
		_scouting.receive_quote(payload)
	if is_instance_valid(_realm):
		_realm.receive_quote(payload)

func _focus_world(x: int, y: int) -> void:
	_hide_feature_panels()
	_show_page("world")
	_map.focus_tile(x, y)
	for tile: Dictionary in _world.get("tiles", []):
		if int(tile.get("x", -1)) == x and int(tile.get("y", -1)) == y and not tile.get("hidden", false):
			_select_tile(tile)
			break

func _dispatch_node(id: String) -> void:
	for tile: Dictionary in _world.get("tiles", []):
		if str(tile.get("id", "")) == id and not tile.get("hidden", false):
			_hide_feature_panels()
			_dispatch_dialog(tile)
			return
	_show_toast("目标尚未显示，请刷新地图后再出征")

func _route_objective(route: String, target: String = "") -> void:
	_hide_feature_panels()
	if is_instance_valid(_dialog):
		_dialog.hide()
	match route:
		"inner", "city":
			_city_zone = "inner"
			_show_page("city")
			if target == "blueprint":
				_buildings_dialog()
			elif not target.is_empty():
				_building_dialog(target)
		"outer": _show_realm("plots")
		"army":
			_show_page("army")
			var chosen: Dictionary = {}
			for unit: Dictionary in _view.get("units", []):
				if str(unit.id) == target:
					chosen = unit
			if not chosen.is_empty():
				_train_unit_dialog(chosen)
			else:
				_training_dialog()
		"research": _research_dialog()
		"marches": _marches_dialog()
		"world":
			_show_page("world")
			for tile: Dictionary in _world.get("tiles", []):
				if str(tile.get("id", "")) == target and not tile.get("hidden", false):
					_map.focus_tile(int(tile.x), int(tile.y))
					_select_tile(tile)
					return
		"wildGenerals": _show_heroes("wild")
		"heroes": _show_heroes("equipment" if target == "equipment" else "generals")
		"specialization": _show_heroes("specializations")
		"growth": _show_growth_route()
		"campaign": _prepare_campaign_target(target)
		"plans": _show_realm("plans")
		"gift": _show_progression("gifts")
		"epic", "honors", "chapters", "missions", "daily", "preparation":
			_show_progression(route)
			if route == "epic" and target == "exchange":
				_progression.select_filter(3)
		"holdings", "gather": _show_realm("holdings")
		"inventory":
			_inventory_dialog()
			if not target.is_empty():
				var suggestion: Dictionary = _view.get("growth", {}).get("speedup", {}).get("suggestion", {}) if _view.get("growth", {}).get("speedup", {}).get("suggestion") is Dictionary else {}
				_inventory.select_item(target, str(suggestion.get("targetKey", "")) if str(suggestion.get("itemId", "")) == target else "")
		"civic", "defense", "captives": _show_war_management(route)
		"market": _show_management("market")
		_: _show_progression("missions")

func _reward_text(objective: Dictionary) -> String:
	var rewards: Dictionary = objective.get("rewards", {})
	var parts: PackedStringArray = []
	var resources: Dictionary = rewards.get("resources", objective.get("reward", {}))
	if not resources.is_empty():
		parts.append(_cost(resources))
	for kind: String in ["items", "jewels", "army"]:
		for entry: Dictionary in rewards.get(kind, []):
			parts.append(str(entry.get("name", entry.get("id", "物资"))) + " ×" + str(entry.get("count", 0)))
	return " · ".join(parts) if not parts.is_empty() else "—"

func _render_shared_report(content: VBoxContainer, report: Dictionary) -> void:
	content.add_child(_report_label("双方依据出征与守城军令自动交战。守方统计包含实际抵达的盟友援军。", 15))
	for side: String in ["attacker", "defender"]:
		content.add_child(_report_label("攻方" if side == "attacker" else "守方合计", 19, Color("c5b37b")))
		content.add_child(_report_label("幸存：" + _army_text(report.get(side, {})), 16))
		content.add_child(_report_label("永久损失：" + _army_text(report.get("lost" if side == "attacker" else "defenderLost", {})), 16))
		content.add_child(_report_label("伤兵：" + _army_text(report.get("wounded" if side == "attacker" else "defenderWounded", {})), 16))
	if not str(report.get("reason", "")).is_empty():
		content.add_child(_report_label("结果说明：" + str(report.reason), 16))
	content.add_child(HSeparator.new())
	content.add_child(_report_label("逐回合记录", 18))
	var units: Dictionary = _unit_dictionary()
	for event: Dictionary in report.get("log", []):
		var unit: String = str(units.get(str(event.get("unit", "")), {}).get("name", event.get("unit", "部队")))
		var target: String = str(units.get(str(event.get("target", "")), {}).get("name", event.get("target", "守军")))
		var side: String = "攻方" if str(event.get("side", "")) == "a" else "守方"
		var text: String = "第%d回合 · %s%s" % [int(event.get("round", 0)), side, unit]
		if event.get("type", "") == "move":
			text += " 移动至 " + str(event.get("to", event.get("position", "—")))
		else:
			text += " 攻击" + target + " · 对方减员 " + str(event.get("killed", 0)) + "兵"
		content.add_child(_report_label(text, 14))

func _save_dialog() -> void:
	if api.mode == "shared":
		_show_toast("共享城池由服务器保存，私人存档无法覆盖共享进度")
		return
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
		_reset_county_context()
		api.import_snapshot(parsed)
		_dialog.hide()))
	if not OS.has_feature("web"):
		content.add_child(_button("保存 JSON 文件", _save_file))
		content.add_child(_button("从 JSON 文件导入", _load_file))

func _save_file() -> void:
	var picker: FileDialog = FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray(["*.json ; 山河策存档"])
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
	picker.filters = PackedStringArray(["*.json ; 山河策存档"])
	picker.size = Vector2i(750, 500)
	add_child(picker)
	picker.file_selected.connect(func(path: String) -> void:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_reset_county_context()
			api.import_snapshot(parsed)
			_dialog.hide()
		else:
			_show_toast("文件不是有效存档 JSON")
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered()

func _show_inventory(section: String = "inventory") -> void:
	if not is_instance_valid(_inventory):
		_inventory = InventoryScript.new() as KingdomInventoryDialog
		add_child(_inventory)
		_inventory.command_requested.connect(func(type: String, args: Array) -> void: _send_command(type, args))
		_inventory.route_requested.connect(_route_objective)
		_inventory.visibility_changed.connect(_on_popup_visibility.bind(_inventory))
	_prepare_feature_panel(_inventory)
	_inventory.show_section(section, _view)


func _intel_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _intel_server_offset

func _scouting_view() -> Dictionary:
	var view: Dictionary = _view.duplicate(true)
	view["serverTime"] = _intel_now()
	var campaign_target: Dictionary = _campaign_target(_scouting_target_id)
	if not campaign_target.is_empty():
		view["nodes"].append(campaign_target.duplicate(true))
	# The state DTO contains landmarks; ordinary wilds live in the safe world DTO.
	# Add only the current target, with military data rebuilt from current intel.
	if not _scouting_target_id.is_empty():
		for tile: Dictionary in _world.get("tiles", []):
			if str(tile.get("id", "")) == _scouting_target_id:
				var present: bool = false
				for node: Dictionary in view.get("nodes", []):
					if str(node.get("id", "")) == _scouting_target_id:
						present = true
						break
				if not present:
					view["nodes"].append(_intel_node(tile))
				break
	return view

func _intel_node(tile: Dictionary) -> Dictionary:
	var node: Dictionary = tile.duplicate(true)
	# A tile may be the previous selection; revoke its derived military data.
	node.erase("intel")
	node["army"] = {}
	var campaign_target: Dictionary = _campaign_target(str(tile.get("id", "")))
	if not campaign_target.is_empty():
		node.merge(campaign_target, true)
	for current: Dictionary in _view.get("nodes", []):
		if str(current.get("id", "")) == str(tile.get("id", "")):
			node.merge(current, true)
			break
	var reports: Dictionary = _view.get("scouting", {}).get("intelByNode", {})
	if reports.has(str(tile.get("id", ""))):
		node["intel"] = reports[str(tile.id)].duplicate(true)
		# Only the normalized server intel decides which numbers may be read.
		node["army"] = node.intel.get("army", {}).duplicate(true) if node.intel.get("army", {}) is Dictionary else {}
	return node

func _campaign_target(id: String) -> Dictionary:
	if not _view.get("campaign", {}).get("unlocked", false):
		return {}
	for route: Dictionary in _view.get("campaign", {}).get("routes", []):
		for target: Dictionary in route.get("targets", []):
			if str(target.get("id", "")) == id:
				return target
	return {}

func _prepare_campaign_target(id: String) -> void:
	if id.is_empty():
		_show_progression("campaign")
		return
	if api == null or api.mode != "local" or not api.connected or api._has_mutation():
		return
	var target: Dictionary = _campaign_target(id)
	if target.is_empty() or not str(target.get("reason", "")).is_empty():
		_show_toast(str(target.get("reason", "当前军令已变化，请刷新后选择。")), true)
		return
	_open_dispatch_flow(target, "march")

func _sync_scouting_intel() -> void:
	if api == null or api.mode == "shared":
		return
	if is_instance_valid(_detail_intel) and not _selected.is_empty():
		_detail_intel.set_intel(_intel_node(_selected), _view.get("units", []), _intel_now())
	if is_instance_valid(_dispatch_intel) and not _dispatch_intel_target.is_empty():
		_dispatch_intel.set_intel(_intel_node(_dispatch_intel_target), _view.get("units", []), _intel_now())

func _show_scouting(tile: Dictionary) -> void:
	_open_dispatch_flow(tile, "scout")

func _open_dispatch_flow(tile: Dictionary, tab: String) -> void:
	if api == null or api.mode == "shared":
		_show_toast("玩家城池侦察尚未开放")
		return
	if tile.get("owned", false) or tile.get("hidden", false) or not tile.get("selectable", true):
		_show_toast("请选择已开放的城外目标")
		return
	if not is_instance_valid(_scouting):
		_scouting = DispatchDialogScript.new() as KingdomScoutingDialog
		add_child(_scouting)
		_scouting.quote_requested.connect(func(kind: String, args: Array, request_id: String) -> void: api.request_quote(kind, args, request_id))
		_scouting.command_requested.connect(func(type: String, args: Array, source: String) -> void: _send_command(type, args, source))
		_scouting.visibility_changed.connect(_on_popup_visibility.bind(_scouting))
	_prepare_feature_panel(_scouting)
	_scouting_target_id = str(tile.get("id", ""))
	_scouting.update_view(_scouting_view())
	_scouting.configure_target(_intel_node(tile))
	_scouting.set_command_state(api.connected, api._has_mutation())
	_scouting.call("show_tab", tab)
	_dispatch_intel_target = tile.duplicate(true)
	_dispatch_intel = _scouting.get("_march_intel") as KingdomIntelPanel
	_scouting.popup()
	_scouting._fit_window()
	_adapt_layout()
	call_deferred("_watch_buttons", _scouting)

func _refresh_scout_marches() -> void:
	var current: Dictionary = {}
	for march: Dictionary in _view.get("marches", []):
		current[str(march.get("id", ""))] = march
	if is_instance_valid(_march_content):
		for id: String in current:
			var march: Dictionary = current[id]
			if _march_labels.has(id) or _march_filter == "stationed" and str(march.get("status", "")) != "stationed":
				continue
			var reused: bool = false
			for prior_id: String in _march_labels.keys():
				var existing: Label = _march_labels[prior_id]
				if not current.has(prior_id) and _march_row_identity(existing.get_meta("march", {})) == _march_row_identity(march):
					_march_labels[id] = existing
					_march_labels.erase(prior_id)
					var existing_action: Button = _march_action_buttons[prior_id]
					existing_action.set_meta("march_id", id)
					_march_action_buttons[id] = existing_action
					_march_action_buttons.erase(prior_id)
					reused = true
					break
			if not reused:
				_add_march_row(march)
	var visible_rows: int = 0
	for id: String in _march_labels:
		var label: Label = _march_labels[id]
		if not is_instance_valid(label):
			continue
		var prior: Dictionary = label.get_meta("march", {})
		var action: Button = _march_action_buttons.get(id)
		if current.has(id):
			var march: Dictionary = current[id]
			label.set_meta("march", march.duplicate(true))
			label.visible = _march_filter != "stationed" or str(march.get("status", "")) == "stationed"
			if label.visible:
				visible_rows += 1
			if str(march.get("type", "")) == "scout":
				var returning: bool = str(march.get("status", "")) == "return"
				var end: float = float(march.get("returnAt", march.get("arrive", 0))) if returning else float(march.get("nextArrival", march.get("arrive", 0)))
				label.text = str(march.get("label", "斥候")) + "\n出发城 " + _scout_city_name(str(march.get("sourceCity", "capital"))) + "\n" + ("斥候返程 · " if returning else "侦察途中 · ") + _march_remaining(end) + " · %d人" % int(march.get("count", 0))
				var loss: Variant = march.get("lost")
				if returning and (loss is int or loss is float) and is_finite(float(loss)) and float(loss) >= 0:
					label.text += " · 损失 %d人" % int(loss)
			else:
				label.text = str(march.get("label", "部队")) + "\n" + _march_status(march)
			if is_instance_valid(action):
				action.text = "进入战斗" if march.get("canStartBattle", false) else "召回" if _march_can_recall(march) else ""
				action.visible = label.visible and not action.text.is_empty()
				action.disabled = not api.connected or api._has_mutation()
		else:
			label.visible = _march_filter != "stationed"
			label.text = str(prior.get("label", "部队")) + ("\n斥候已返城，人数以出发城驻军为准。" if str(prior.get("type", "")) == "scout" else "\n本次行军已结束，兵力与资源以服务器回执为准。")
			if is_instance_valid(action):
				action.hide()

	if is_instance_valid(_march_empty):
		_march_empty.visible = visible_rows == 0

func _march_can_recall(march: Dictionary) -> bool:
	var status: String = str(march.get("status", ""))
	if status in ["return", "battle"] or str(march.get("type", "")) == "scout":
		return false
	if march.has("recallCommand"):
		return status in ["stationed", "march"]
	var select: Dictionary = march.get("selectCommand", {})
	return status == "march" and not march.get("shared", false) and str(select.get("type", "")) == "selectExpedition" and not str(select.get("sourceCity", "")).is_empty()

func _activate_march_action(id: String) -> void:
	if api == null or not api.connected or api._has_mutation():
		return
	for march: Dictionary in _view.get("marches", []):
		if str(march.get("id", "")) != id:
			continue
		if march.get("canStartBattle", false):
			_start_march_battle(march)
		elif _march_can_recall(march):
			if march.has("recallCommand"):
				_send_record_command(march.recallCommand)
			else:
				_pending_battle = false
				_pending_recall = march.selectCommand.duplicate(true)
				_send_record_command(_pending_recall)
		return

func _scout_city_name(id: String) -> String:
	for city: Dictionary in _view.get("cityList", []):
		if str(city.get("id", "")) == id:
			return str(city.get("name", id))
	return str(_view.get("city", {}).get("name", id)) if str(_view.get("city", {}).get("id", "")) == id else id
