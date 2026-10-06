extends SceneTree

## Exercises production InputMap, durable settings and UI event routing. Every
## file and transport request stays inside this process's disposable user dir.
class TransportProbe extends "res://src/game_api.gd":
	var requests: Array[Dictionary] = []
	var export_requests: int = 0
	func _ready() -> void:
		pass
	func _pump() -> void:
		pass
	func command(type: String, args: Array = [], source_city: String = "") -> void:
		requests.append({"type": type, "args": args, "sourceCity": source_city})
	func fetch_export() -> void:
		export_requests += 1
		call_deferred("_deliver_export")
	func _deliver_export() -> void:
		export_received.emit({"inputTest": true})

class ClientProbe extends "res://src/main.gd":
	func _ready() -> void:
		theme = _make_theme()
		_initialize_inputs()
		_build_shell()
		add_child(api)
		api.snapshot_received.connect(_receive_snapshot)
		api.world_received.connect(_receive_world)
		api.status_changed.connect(_connection_changed)
		api.request_failed.connect(_request_failed)
		api.command_completed.connect(_command_completed)
		api.export_received.connect(_show_export)
		_show_page("world")

const SettingsScript: Script = preload("res://src/input_settings.gd")
var _checks: int = 0
var _failures: int = 0
var _old_custom_user_dir: Variant
var _old_custom_user_name: Variant
var _temporary_user_dir: String = ""
var _built_in_actions: Dictionary = {}
var _changes: int = 0
var _fixture: Dictionary = {}
var _client: ClientProbe
var _api: TransportProbe

func _initialize() -> void:
	_old_custom_user_dir = ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	_old_custom_user_name = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	var unique_name: String = "ThreeKingdomsInputTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", unique_name)
	_temporary_user_dir = OS.get_user_data_dir()
	if not _temporary_user_dir.ends_with(unique_name):
		push_error("Refusing input tests without a unique disposable user directory.")
		_restore_settings()
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_temporary_user_dir)
	for action: StringName in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			_built_in_actions[action] = _event_fingerprint(action)
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

func _event_fingerprint(action: StringName) -> Array[String]:
	var result: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		result.append(event.get_class() + ":" + event.as_text())
	return result

func _key(code: int, pressed: bool = true, ctrl: bool = false, alt: bool = false, shift: bool = false, meta: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.shift_pressed = shift
	event.meta_pressed = meta
	if code >= KEY_SPACE and code <= KEY_ASCIITILDE:
		event.unicode = code
	return event

func _tap(code: int, ctrl: bool = false, alt: bool = false, shift: bool = false, meta: bool = false) -> void:
	Input.parse_input_event(_key(code, true, ctrl, alt, shift, meta))
	await _settle()
	Input.parse_input_event(_key(code, false, ctrl, alt, shift, meta))
	await _settle()

func _run() -> void:
	_test_settings_storage()
	_test_corrupt_settings()
	_test_unwritable_settings()
	await _test_map_controls()
	await _test_client_controls()
	for action: StringName in _built_in_actions:
		_check(_event_fingerprint(action) == _built_in_actions[action], "Input settings must preserve the built-in %s mappings." % action)
	_finish()

func _test_settings_storage() -> void:
	var unrelated: StringName = &"input_test_unrelated"
	InputMap.add_action(unrelated)
	InputMap.action_add_event(unrelated, _key(KEY_F12))
	var unrelated_before: Array[String] = _event_fingerprint(unrelated)
	var path: String = _temporary_user_dir.path_join("bindings.cfg")
	var settings: KingdomInputSettings = SettingsScript.new(path)
	settings.initialize()
	_check(settings.load_warning.is_empty(), "First launch without a binding file must be normal, without a corruption warning.")
	_check(settings.actions().has("tk_page_city") and settings.actions().has("tk_map_left"), "The action list must expose navigation and continuous map movement.")
	_check(settings.action_for_event(_key(KEY_1)) == "tk_page_city", "Default physical 1 must select the city action.")
	_check(settings.action_for_event(_key(KEY_1, true, true)).is_empty(), "Modified keys must not accidentally match plain page shortcuts.")
	_check(settings.action_for_event(_key(KEY_1, true, false, false, true)).is_empty(), "A shifted number must not accidentally match a plain page shortcut.")
	_check(settings.action_for_event(InputEventMouseButton.new()).is_empty(), "Keyboard action matching must ignore mouse events.")
	_check(not settings.binding_text("tk_page_city").is_empty(), "Each visible keyboard action must have a readable binding.")
	settings.bindings_changed.connect(func() -> void: _changes += 1)
	var outcome: String = settings.rebind("tk_page_city", _key(KEY_F6))
	_check(outcome.is_empty() and _changes == 1, "A successful rebind must notify the live UI exactly once.")
	_check(FileAccess.file_exists(path), "A successful rebind must create a durable settings file.")
	_check(settings.action_for_event(_key(KEY_F6)) == "tk_page_city" and settings.action_for_event(_key(KEY_1)).is_empty(), "The custom binding must replace its old page key.")
	_check(InputMap.event_is_action(_key(KEY_F6), "tk_page_city", true), "The actual InputMap must receive a successful rebind.")
	var saved: String = FileAccess.get_file_as_string(path)
	_check(not settings.rebind("tk_page_army", _key(KEY_F6)).is_empty(), "A key already used by another action must be rejected.")
	_check(settings.action_for_event(_key(KEY_F6)) == "tk_page_city" and _changes == 1 and FileAccess.get_file_as_string(path) == saved, "A duplicate rejection must leave live mappings, notifications and storage unchanged.")
	_check(not settings.rebind("tk_unknown_action", _key(KEY_F7)).is_empty(), "Unknown actions must not be added through rebinding.")
	for reserved: InputEventKey in [_key(KEY_ESCAPE), _key(KEY_ENTER), _key(KEY_TAB), _key(KEY_SHIFT), _key(KEY_W, true, true), _key(KEY_F4, true, false, true)]:
		_check(not settings.rebind("tk_page_city", reserved).is_empty(), "A native UI or operating-system reserved key must be rejected: %s." % reserved.as_text())
	_check(_changes == 1 and FileAccess.get_file_as_string(path) == saved, "All rejected reserved keys must preserve the previous durable binding.")
	_check(settings.rebind("tk_page_army", _key(KEY_P, true, true)).is_empty(), "A permitted physical key with a modifier must be bindable.")
	_check(settings.action_for_event(_key(KEY_P, true, true)) == "tk_page_army" and settings.action_for_event(_key(KEY_P)).is_empty(), "A custom modifier binding must match the complete combination only.")
	var reopened: KingdomInputSettings = SettingsScript.new(path)
	reopened.initialize()
	_check(reopened.load_warning.is_empty() and reopened.action_for_event(_key(KEY_F6)) == "tk_page_city", "A fresh settings instance must read a previously saved binding.")
	_check(reopened.restore_defaults().is_empty(), "Restoring defaults must persist successfully.")
	var restored: KingdomInputSettings = SettingsScript.new(path)
	restored.initialize()
	_check(restored.action_for_event(_key(KEY_1)) == "tk_page_city" and restored.action_for_event(_key(KEY_F6)).is_empty(), "Restored defaults must survive a fresh settings instance.")
	_check(_event_fingerprint(unrelated) == unrelated_before, "Updating game keys must leave unrelated InputMap actions unchanged.")
	InputMap.erase_action(unrelated)

func _test_corrupt_settings() -> void:
	var valid_path: String = _temporary_user_dir.path_join("bindings.cfg")
	var cases: Array[String] = ["version", "unknown_action", "missing_action", "wrong_type", "duplicate", "extra_field", "reserved_key"]
	for corruption: String in cases:
		var config: ConfigFile = ConfigFile.new()
		_check(config.load(valid_path) == OK, "The corruption test must start from a valid stored configuration.")
		match corruption:
			"version":
				config.set_value("meta", "version", 999)
			"unknown_action":
				config.set_value("bindings", "tk_fake_economy", config.get_value("bindings", "tk_page_city"))
			"missing_action":
				config.erase_section_key("bindings", "tk_page_city")
			"wrong_type":
				var events: Array = config.get_value("bindings", "tk_page_city").duplicate(true)
				events[0]["ctrl"] = "false"
				config.set_value("bindings", "tk_page_city", events)
			"duplicate":
				config.set_value("bindings", "tk_page_army", config.get_value("bindings", "tk_page_city"))
			"extra_field":
				var events: Array = config.get_value("bindings", "tk_page_city").duplicate(true)
				events[0]["command"] = "trade"
				config.set_value("bindings", "tk_page_city", events)
			"reserved_key":
				var events: Array = config.get_value("bindings", "tk_page_city").duplicate(true)
				events[0]["physical_keycode"] = KEY_ENTER
				config.set_value("bindings", "tk_page_city", events)
		var path: String = _temporary_user_dir.path_join("corrupt-%s.cfg" % corruption)
		_check(config.save(path) == OK, "The malformed %s fixture must be written only in the temporary directory." % corruption)
		var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var settings: KingdomInputSettings = SettingsScript.new(path)
		settings.initialize()
		_check(not settings.load_warning.is_empty(), "The %s configuration must explain its fallback instead of silently accepting it." % corruption)
		_check(settings.action_for_event(_key(KEY_1)) == "tk_page_city" and settings.action_for_event(_key(KEY_3)) == "tk_page_army", "The %s configuration must fall back to a complete conflict-free default map." % corruption)
		_check(FileAccess.get_file_as_bytes(path) == original_bytes, "Loading the %s configuration must preserve its original bytes for recovery." % corruption)
		_check(not InputMap.has_action("tk_fake_economy"), "Unknown data in the %s configuration must never introduce an InputMap action." % corruption)

func _test_unwritable_settings() -> void:
	var path: String = _temporary_user_dir.path_join("blocked.cfg")
	var settings: KingdomInputSettings = SettingsScript.new(path)
	settings.initialize()
	_check(settings.rebind("tk_page_city", _key(KEY_F9)).is_empty(), "The rollback scenario must first persist a valid custom binding.")
	var changes: Array[int] = [0]
	settings.bindings_changed.connect(func() -> void: changes[0] += 1)
	_check(DirAccess.remove_absolute(path) == OK and DirAccess.make_dir_absolute(path) == OK, "The rollback fixture must replace only its own cfg file with a directory.")
	_check(not settings.rebind("tk_page_city", _key(KEY_F10)).is_empty(), "A binding must fail visibly when its destination cannot be replaced.")
	_check(settings.action_for_event(_key(KEY_F9)) == "tk_page_city" and settings.action_for_event(_key(KEY_F10)).is_empty(), "Failed storage must retain the last acknowledged live binding.")
	_check(InputMap.event_is_action(_key(KEY_F9), "tk_page_city", true) and not InputMap.event_is_action(_key(KEY_F10), "tk_page_city", true), "Failed storage must retain the last acknowledged InputMap mapping.")
	_check(not settings.restore_defaults().is_empty() and settings.action_for_event(_key(KEY_F9)) == "tk_page_city", "A failed default restoration must also roll back its live bindings.")
	_check(changes[0] == 0, "Failed writes must never advertise a successful change to the live UI.")
	_check(DirAccess.dir_exists_absolute(path), "The storage failure must not delete an unrelated directory at the destination.")

func _test_map_controls() -> void:
	var map: KingdomWorldMap = KingdomWorldMap.new()
	root.add_child(map)
	map.set_process(false)
	map.size = Vector2(600, 320)
	map.set_world({"width": 128, "height": 128, "home": {"x": 62, "y": 63}, "tiles": [], "marches": []})
	var screen_distances: Array[float] = []
	for scale: float in [0.3, 1.2]:
		map.zoom = scale
		map.camera_center = Vector2(64, 64)
		var before: Vector2 = map.camera_center
		map._velocity = Vector2(5, 3)
		map.keyboard_pan(Vector2.RIGHT, 0.05)
		screen_distances.append((map.camera_center - before).length() * map.cell_pixels())
		_check(map.camera_center.x > before.x and is_equal_approx(map.camera_center.y, before.y), "The right map action must move horizontally toward eastern tiles.")
		_check(map._velocity.is_zero_approx(), "Keyboard movement must cancel residual mouse inertia.")
	_check(is_equal_approx(screen_distances[0], screen_distances[1]) and screen_distances[0] > 0.0, "Keyboard map panning must have the same screen speed at different zoom levels.")
	map.zoom = 0.8
	map.camera_center = Vector2(64, 64)
	var start: Vector2 = map.camera_center
	map.keyboard_pan(Vector2(1, 1), 0.05)
	var diagonal: float = (map.camera_center - start).length() * map.cell_pixels()
	_check(is_equal_approx(diagonal, screen_distances[0]), "Diagonal map movement must not outrun a cardinal direction.")
	map.camera_center = Vector2(64, 64)
	map.keyboard_pan(Vector2.RIGHT, 1.0)
	_check((map.camera_center - Vector2(64, 64)).length() * map.cell_pixels() <= screen_distances[0] * 2.0 + 0.001, "A delayed process frame must not jump the keyboard camera across the world.")
	map.camera_center = Vector2(0, 0)
	map.keyboard_pan(Vector2(-1, -1), 0.1)
	_check(map.world_to_screen(Vector2.ZERO).x <= 0.001 and map.world_to_screen(Vector2.ZERO).y <= 0.001, "Panning toward a world edge must keep the viewport within the map.")
	map.camera_center = Vector2(64, 64)
	var anchor: Vector2 = map.screen_to_world(map.size * 0.5)
	map._velocity = Vector2(9, -2)
	map.keyboard_zoom(1.12)
	_check(map.zoom > 0.8 and map.screen_to_world(map.size * 0.5).is_equal_approx(anchor), "A keyboard zoom must preserve the world point at the viewport centre.")
	_check(map._velocity.is_zero_approx(), "Keyboard zoom must cancel residual drag inertia.")
	map.keyboard_zoom(1000000.0)
	_check(map.zoom <= KingdomWorldMap.MAX_ZOOM, "Keyboard zoom must obey the existing maximum zoom.")
	map.keyboard_zoom(0.000001)
	_check(map.zoom >= KingdomWorldMap.MIN_ZOOM, "Keyboard zoom must obey the existing minimum zoom.")
	map.zoom = 0.8
	map.camera_center = Vector2(64, 64)
	var mouse_wheel: InputEventMouseButton = InputEventMouseButton.new()
	mouse_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	mouse_wheel.pressed = true
	mouse_wheel.position = map.size * 0.5
	map._gui_input(mouse_wheel)
	_check(map.zoom > 0.8, "The old mouse-wheel zoom must still work without using a keyboard shortcut.")
	map.camera_center = Vector2(64, 64)
	var touch_start: InputEventScreenTouch = InputEventScreenTouch.new()
	touch_start.index = 0
	touch_start.pressed = true
	touch_start.position = Vector2(100, 100)
	map._gui_input(touch_start)
	var touch_drag: InputEventScreenDrag = InputEventScreenDrag.new()
	touch_drag.index = 0
	touch_drag.position = Vector2(145, 100)
	map._gui_input(touch_drag)
	_check(map.camera_center.x < 64.0, "The old touch-drag map controls must still pan west when dragged right.")
	touch_start.pressed = false
	touch_start.position = touch_drag.position
	map._gui_input(touch_start)
	_check(map._touches.is_empty() and not map._pointer_down, "Ending the touch gesture must release its pointer state.")
	root.remove_child(map)
	map.queue_free()
	await process_frame

func _test_client_controls() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/godot-view.json"))
	_check(parsed is Dictionary, "The real view fixture must load before client input checks.")
	if not parsed is Dictionary:
		return
	_fixture = parsed
	root.size = Vector2i(1280, 800)
	_client = ClientProbe.new()
	_api = TransportProbe.new()
	_api.connected = true
	_client.api = _api
	_client.input_settings = SettingsScript.new(_temporary_user_dir.path_join("client-bindings.cfg"))
	_client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_client)
	_client._receive_snapshot(_fixture)
	_client._receive_world(_fixture.get("worldSample", {}))
	await _settle()
	await _test_navigation()
	await _test_focus_and_movement()
	await _test_modals_and_capture()
	await _test_save_input_then_navigation()
	await _test_client_input_layout()
	_check(_api.requests.is_empty(), "Navigation, key settings, map movement and cancellation must send no economic/gameplay command.")
	root.remove_child(_client)
	_client.queue_free()
	await process_frame

func _clear_focus() -> void:
	var owner: Control = root.gui_get_focus_owner()
	if owner != null:
		owner.release_focus()

func _test_navigation() -> void:
	_clear_focus()
	await _tap(KEY_1)
	_check(_client._page == "city", "A real default physical-key event must navigate to the city page.")
	await _tap(KEY_2)
	_check(_client._page == "world" and _client._map != null, "A real default physical-key event must restore the map page.")
	await _tap(KEY_3, true)
	_check(_client._page == "world", "An operating-system modified number must not navigate the game.")
	var repeat: InputEventKey = _key(KEY_3)
	repeat.echo = true
	Input.parse_input_event(repeat)
	await _settle()
	Input.parse_input_event(_key(KEY_3, false))
	_check(_client._page == "world", "An auto-repeat event must not repeatedly rebuild a page.")
	_check(_client.input_settings.rebind("tk_page_city", _key(KEY_F6)).is_empty(), "The live navigation binding must be editable.")
	await _tap(KEY_1)
	_check(_client._page == "world", "A stale default key must stop navigating after a custom rebind.")
	await _tap(KEY_F6)
	_check(_client._page == "city", "The custom key must navigate immediately without restarting the game.")
	var help: String = _client.input_settings.binding_text("tk_page_city")
	_check(_client._nav.get_child(0).tooltip_text.contains(help), "Page-button help must immediately display the acknowledged custom binding.")
	_check(_client.input_settings.restore_defaults().is_empty(), "The client must restore defaults before focus and modal checks.")
	_client._show_page("world")
	await _settle()

func _test_focus_and_movement() -> void:
	var entries: Array[Control] = [LineEdit.new(), TextEdit.new(), SpinBox.new()]
	for entry: Control in entries:
		_client.add_child(entry)
		var focus: Control = entry.get_line_edit() if entry is SpinBox else entry
		focus.grab_focus()
		await _settle()
		_check(_client._shortcut_blocked(), "A focused %s must block global game shortcuts." % entry.get_class())
		await _tap(KEY_1)
		_check(_client._page == "world", "Typing a page-key character into %s must not navigate." % entry.get_class())
		var camera: Vector2 = _client._map.camera_center
		Input.parse_input_event(_key(KEY_D))
		await _settle()
		_check(_client._map.camera_center.is_equal_approx(camera), "Holding a movement-key character in %s must not move the map." % entry.get_class())
		Input.parse_input_event(_key(KEY_D, false))
		focus.release_focus()
		_client.remove_child(entry)
		entry.queue_free()
		await _settle()
	_clear_focus()
	_client._map.focus_tile(32, 32)
	var before: Vector2 = _client._map.camera_center
	Input.parse_input_event(_key(KEY_D))
	await _settle()
	_check(_client._map.camera_center.x > before.x, "A held movement key must pan the unobstructed visible map.")
	Input.parse_input_event(_key(KEY_D, false))
	await _settle()
	before = _client._map.camera_center
	await _settle()
	_check(_client._map.camera_center.is_equal_approx(before), "Releasing the movement key must stop keyboard movement without inertia.")
	_client._map.grab_focus()
	await _settle()
	before = _client._map.camera_center
	Input.parse_input_event(_key(KEY_RIGHT))
	await _settle()
	_check(_client._map.camera_center.x > before.x, "The alternative right-arrow key must pan a focused map before GUI focus navigation can consume it.")
	_check(root.gui_get_focus_owner() == _client._map, "A direction key used on the focused map must keep focus on that map.")
	Input.parse_input_event(_key(KEY_RIGHT, false))
	await _settle()
	var nav_button: Button = _client._nav.get_child(0) as Button
	nav_button.grab_focus()
	await _settle()
	before = _client._map.camera_center
	await _tap(KEY_RIGHT)
	_check(_client._map.camera_center.is_equal_approx(before), "A direction key on a focused UI button must leave the map camera unchanged.")
	_check(root.gui_get_focus_owner() != nav_button and root.gui_get_focus_owner() != _client._map, "A direction key on a UI button must retain Godot's normal control-focus navigation.")
	_client._map.grab_focus()
	await _settle()
	for fast_key: int in [KEY_D, KEY_RIGHT]:
		before = _client._map.camera_center
		Input.parse_input_event(_key(fast_key))
		Input.parse_input_event(_key(fast_key, false))
		await _settle()
		_check(_client._map.camera_center.x > before.x, "A %s down/up in one frame must still create a visible map movement tick." % OS.get_keycode_string(fast_key))
		_check(root.gui_get_focus_owner() == _client._map, "A fast %s map tap must not transfer focus to unrelated UI controls." % OS.get_keycode_string(fast_key))
	before = _client._map.camera_center
	Input.parse_input_event(_key(KEY_D, true, true))
	await _settle()
	_check(_client._map.camera_center.is_equal_approx(before), "An OS-modified movement key must not pan a plain-key action.")
	Input.parse_input_event(_key(KEY_D, false, true))
	await _settle()
	for first: int in [KEY_A, KEY_D]:
		var second: int = KEY_D if first == KEY_A else KEY_A
		var sign: float = -1.0 if first == KEY_A else 1.0
		Input.parse_input_event(_key(first))
		await _settle()
		Input.parse_input_event(_key(second))
		await _settle()
		before = _client._map.camera_center
		_check(_client.input_settings.movement_vector().is_zero_approx(), "Opposite held movement keys must cancel instead of choosing a direction.")
		await _settle()
		_check(_client._map.camera_center.is_equal_approx(before), "Holding A and D together must keep the map stationary.")
		Input.parse_input_event(_key(second, false))
		await _settle()
		_check((_client._map.camera_center.x - before.x) * sign > 0.0, "Releasing an opposing key must resume the still-held %s without requiring another press." % OS.get_keycode_string(first))
		Input.parse_input_event(_key(first, false))
		await _settle()
		before = _client._map.camera_center
		await _settle()
		_check(_client._map.camera_center.is_equal_approx(before), "Releasing both keys after a cancelling chord must stop the map.")
	Input.parse_input_event(_key(KEY_D))
	await _settle()
	_client.get_window().focus_exited.emit()
	await _settle()
	before = _client._map.camera_center
	_check(_client._shortcut_blocked(), "The real window focus-exited signal must pause game shortcuts.")
	await _tap(KEY_1)
	await _settle()
	_check(_client._page == "world" and _client._map.camera_center.is_equal_approx(before), "An inactive game window must neither navigate nor continue held-key panning.")
	_client.get_window().focus_entered.emit()
	await _settle()
	_check(not _client._shortcut_blocked() and _client._map.camera_center.is_equal_approx(before), "Restoring window focus must wait for a new key press instead of reviving a held key.")
	Input.parse_input_event(_key(KEY_D, false))
	await _settle()
	Input.parse_input_event(_key(KEY_D))
	await _settle()
	_check(_client._map.camera_center.x > before.x, "A fresh movement press after window focus returns must work normally.")
	Input.parse_input_event(_key(KEY_D, false))
	_client._show_page("city")
	Input.parse_input_event(_key(KEY_D))
	await _settle()
	_check(_client._page == "city" and _client._map == null, "A held movement key outside the map must not open or rebuild the map page.")
	Input.parse_input_event(_key(KEY_D, false))
	_client._show_page("world")
	await _settle()
	_clear_focus()
	var zoom: float = _client._map.zoom
	await _tap(KEY_EQUAL)
	_check(_client._map.zoom > zoom, "The physical zoom-in action must reach the map through real event routing.")
	_client._map.focus_tile(40, 40)
	await _tap(KEY_H)
	var home: Dictionary = _client._map.world.get("home", {})
	_check(int(_client._map.selected_tile.get("x", -1)) == int(home.get("x", -2)), "The keyboard home action must focus the canonical home tile.")

func _test_modals_and_capture() -> void:
	_client._tasks_dialog()
	await _settle()
	_check(_client._shortcut_blocked(), "A visible transactions popup must block shortcuts and continuous movement.")
	var camera: Vector2 = _client._map.camera_center
	await _tap(KEY_1)
	Input.parse_input_event(_key(KEY_D))
	await _settle()
	_check(_client._page == "world" and _client._map.camera_center.is_equal_approx(camera), "A visible popup must retain its page and map camera while game keys are pressed.")
	Input.parse_input_event(_key(KEY_D, false))
	await _tap(KEY_ESCAPE)
	_check(not _client._dialog.visible, "The built-in Escape action must still close an ordinary popup.")
	_clear_focus()
	await _tap(KEY_K)
	_check(is_instance_valid(_client._input_settings_dialog) and _client._input_settings_dialog.visible, "The settings action must open the actual binding popup.")
	var dialog: KingdomInputSettingsDialog = _client._input_settings_dialog
	dialog._begin_capture("tk_page_city")
	await _settle()
	_check(dialog.capturing_action() == "tk_page_city", "Clicking rebind must enter a clear capture state.")
	await _tap(KEY_ENTER)
	_check(dialog.visible and dialog.capturing_action() == "tk_page_city" and _api.requests.is_empty(), "Enter during capture must be rejected without closing the popup or issuing a command.")
	await _tap(KEY_4)
	_check(_client._page == "world" and _client.input_settings.action_for_event(_key(KEY_4)) == "tk_page_generals", "A conflicting captured key must not navigate or replace its existing action.")
	dialog._begin_capture("tk_page_city")
	await _tap(KEY_F6)
	_check(_client._page == "world" and _client.input_settings.action_for_event(_key(KEY_F6)) == "tk_page_city", "A successfully captured key must update bindings without triggering that navigation.")
	_check(dialog.capturing_action().is_empty(), "A successful rebind must leave capture mode.")
	dialog._begin_capture("tk_page_city")
	await _tap(KEY_ESCAPE)
	_check(dialog.capturing_action().is_empty() and _client.input_settings.action_for_event(_key(KEY_F6)) == "tk_page_city", "Escape must cancel capture without changing the last accepted binding.")
	if dialog.visible:
		await _tap(KEY_ESCAPE)
	_check(not dialog.visible, "A second Escape must close the key-settings popup.")
	_clear_focus()
	await _tap(KEY_F6)
	_check(_client._page == "city", "The captured key must work after its settings popup closes.")
	_client.input_settings.restore_defaults()
	_client._show_management("market")
	await _settle()
	_check(_client._shortcut_blocked(), "An economic management modal must block global game shortcuts.")
	_client._management._count.get_line_edit().grab_focus()
	await _tap(KEY_ENTER)
	_check(_api.requests.is_empty(), "Enter in an economic quantity field must not issue a market transaction.")
	await _tap(KEY_ESCAPE)
	_check(not _client._management.visible, "The built-in Escape action must close an economic management popup.")
	_clear_focus()

func _test_save_input_then_navigation() -> void:
	await _tap(KEY_1)
	_check(_client._page == "city", "The save-input regression must start on the city page through a real key event.")
	var export_count: int = _api.export_requests
	await _tap(KEY_O)
	_check(_api.export_requests == export_count + 1 and is_instance_valid(_client._save_text) and _client._dialog.visible, "O must fetch an export and open the production save editor through its real callback.")
	_client._save_text.grab_focus()
	_client._save_text.select_all()
	await _settle()
	for code: int in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_K]:
		await _tap(code)
	_check(_client._save_text.text.to_lower() == "12345k", "Page and settings keys typed into the save TextEdit must remain literal text.")
	_check(_client._page == "city" and not _client._input_settings_dialog.visible, "Typing into the save editor must not navigate or reopen the keyboard settings.")
	await _tap(KEY_ESCAPE)
	_check(not _client._dialog.visible and not _client._save_text.is_visible_in_tree(), "Escape must close the save popup and hide its text editor.")
	_check(not _client._shortcut_blocked(), "A hidden save editor must not keep blocking game shortcuts after cancellation.")
	await _tap(KEY_2)
	_check(_client._page == "world" and _client._map != null, "Immediately pressing 2 after Escape must reach the map without another mouse click or forced focus reset.")

func _button_labels(node: Node) -> PackedStringArray:
	var result: PackedStringArray = []
	if node is Button:
		result.append((node as Button).text)
	for child: Node in node.get_children():
		result.append_array(_button_labels(child))
	return result

func _test_client_input_layout() -> void:
	for width: int in [1280, 390]:
		root.size = Vector2i(width, 844)
		await _settle()
		_client._tasks_dialog()
		await _settle()
		_check(_button_labels(_client._dialog).has("按键设置"), "The %d px transactions menu must retain a reachable key-settings entry." % width)
		_client._dialog.hide()
		_client._input_settings_dialog.show_settings()
		await _settle()
		var dialog: KingdomInputSettingsDialog = _client._input_settings_dialog
		_check(dialog.size.x <= width - 24 and dialog.position.x >= 0 and dialog.position.x + dialog.size.x <= width, "The keyboard settings popup must fit the %d px viewport." % width)
		dialog.hide()
	root.size = Vector2i(1280, 800)

func _remove_temporary_directory(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for name: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in dir.get_directories():
		_remove_temporary_directory(path.path_join(name))
	DirAccess.remove_absolute(path)

func _restore_settings() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", _old_custom_user_dir)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", _old_custom_user_name)

func _finish() -> void:
	_remove_temporary_directory(_temporary_user_dir)
	_restore_settings()
	print("INPUT_TEST_CHECKS=", _checks, " failures=", _failures)
	quit(0 if _failures == 0 else 1)
