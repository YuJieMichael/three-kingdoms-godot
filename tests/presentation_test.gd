extends SceneTree

class ClientProbe extends "res://src/main.gd":
	func _ready() -> void:
		_smoke = true
		_initialize_inputs()
		theme = _make_theme()
		_audio = AudioScript.new() as KingdomPresentationAudio
		add_child(_audio)
		_build_shell()
		_initialize_presentation()
		api = ApiScript.new() as KingdomApi
		add_child(api)
		_show_page("world")

var failures: int = 0
var checks: int = 0
var _capture: bool = false

func _initialize() -> void:
	# Rendering initializes before this script. Mirror only the pre-created cache
	# directory names when changing user://; never read or copy player settings.
	var previous_cache: String = OS.get_user_data_dir().path_join("shader_cache")
	var temporary_name: String = "ThreeKingdomsPresentationTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", temporary_name)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("shader_cache"))
	if DirAccess.dir_exists_absolute(previous_cache):
		for shader: String in DirAccess.get_directories_at(previous_cache):
			for version: String in DirAccess.get_directories_at(previous_cache.path_join(shader)):
				DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("shader_cache").path_join(shader).path_join(version))
	_capture = OS.get_cmdline_user_args().has("--capture")
	root.gui_embed_subwindows = true
	call_deferred("_run")

func _assert(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _settle() -> void:
	for i: int in 5:
		await process_frame

func _capture_view(name: String) -> void:
	if _capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/presentation-%s.png" % name)

func _run() -> void:
	# --script may not provide project autoloads: instantiate the real plugins.
	if not Engine.has_singleton("SoundManager"):
		root.add_child(load("res://addons/sound_manager/sound_manager.gd").new())
	if not Engine.has_singleton("DialogueManager"):
		root.add_child(load("res://addons/dialogue_manager/dialogue_manager.gd").new())
	var client: ClientProbe = ClientProbe.new()
	client.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(client)
	await _settle()
	var audio: KingdomPresentationAudio = client._audio
	_assert(audio.manager != null, "Use the real Sound Manager singleton")
	_assert(not audio._started, "Startup must not autoplay before a deliberate interaction")
	_assert(audio.set_level("UI", 0.0) == OK, "Mute persists")
	_assert(AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")), "Zero volume mutes the bus")
	var previous: float = float(audio.levels["Music"])
	var previous_path: String = audio.settings_path
	audio.settings_path = "user://missing-parent/audio.cfg"
	_assert(audio.set_level("Music", 0.8) != OK, "Report write failure")
	_assert(float(audio.levels["Music"]) == previous, "Write failure retains live settings")
	audio.settings_path = previous_path
	_assert(audio.set_level("Music", 0.15) == OK, "Music setting writes")
	audio.levels["Music"] = 0.9
	audio.load_settings()
	_assert(is_equal_approx(float(audio.levels["Music"]), 0.15), "Settings reload from disk")
	_assert(audio.set_level("bad", 0.5) == ERR_INVALID_PARAMETER, "Unknown bus is rejected")
	_assert(audio.set_level("UI", 0.5) == OK, "Restore audible test UI")
	audio.click()
	_assert(audio._started and audio.manager.is_music_playing(), "First interaction starts actual music playback")
	audio.confirmed("dispatch")
	_assert(audio.manager.sound_effects.get_child_count() > 0, "Confirmed command uses the actual sound pool")
	for width: int in [1280, 390]:
		root.size = Vector2i(width, 844)
		await _settle()
		client._open_menu()
		await _settle()
		# The dummy display clamps popup_centered to its nonexistent screen.
		# Reapply the same production fitting method to test root-viewport sizing;
		# non-headless capture separately verifies the actual popup on a display.
		if DisplayServer.get_name() == "headless":
			client._menu._fit_window()
		_assert(client._shortcut_blocked(), "Menu blocks game shortcuts")
		_assert(client._menu.size.x <= width - 24, "Menu fits viewport")
		_assert(client._menu.size.x >= mini(560, width - 24), "Menu uses the root viewport instead of its own small viewport")
		_assert(client._menu._tabs.get_tab_count() == 4, "Game/audio/display/credits tabs exist")
		client._menu._tabs.current_tab = 1
		await _settle()
		await _capture_view("audio-%d" % width)
		client._menu._tabs.current_tab = 3
		var page_down: InputEventAction = InputEventAction.new()
		page_down.action = "ui_page_down"
		page_down.pressed = true
		client._menu._tabs._unhandled_input(page_down)
		_assert(client._menu._tabs.current_tab == 0, "Imported Maaack pagination wraps tabs")
		await _capture_view("menu-%d" % width)
		var general: VBoxContainer = client._menu._tabs.get_child(0).get_child(0)
		(general.get_child(2) as Button).pressed.emit()
		await _settle()
		if DisplayServer.get_name() == "headless":
			client._guide._fit_window()
		_assert(not client._menu.visible and client._guide.visible, "Menu guide button opens real dialogue UI")
		_assert(client._guide._body.get_child_count() == 4, "Introduction offers three branches")
		_assert(client._guide.size.x <= width - 24, "Dialogue fits viewport")
		_assert(client._guide.size.x >= mini(620, width - 24), "Dialogue uses the root viewport")
		await _capture_view("guide-%d" % width)
		(client._guide._body.get_child(1) as Button).pressed.emit()
		await _settle()
		_assert((client._guide._body.get_child(0) as Label).text.contains("建筑"), "City branch reaches its text")
		for i: int in 3:
			(client._guide._body.get_child(1) as Button).pressed.emit()
			await _settle()
		_assert(not client._guide.visible, "City branch ends cleanly")
		client._guide.start()
		await _settle()
		(client._guide._body.get_child(2) as Button).pressed.emit()
		await _settle()
		_assert((client._guide._body.get_child(0) as Label).text.contains("派出部队"), "Army branch reaches its text")
		client._guide.hide()
		await _settle()
		_assert(not client._shortcut_blocked(), "Closing dialogue restores game shortcuts")
		_assert(client.api._queue.is_empty(), "Menu and guide do not send gameplay commands")
	audio.manager.stop_music()
	await create_timer(0.1).timeout
	client.queue_free()
	await _settle()
	print("PRESENTATION_TEST_CHECKS=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
