extends SceneTree

const FeedbackScript: Script = preload("res://src/ui_feedback.gd")
const ThemeScript: Script = preload("res://src/ui_theme.gd")
const MenuScript: Script = preload("res://src/presentation_menu.gd")
const UI_FONT: Font = preload("res://assets/fonts/UI.tres")

class QuietAudio extends "res://src/presentation_audio.gd":
	func _ready() -> void:
		pass
	func click() -> void:
		pass

var failures: int = 0
var checks: int = 0
var _directory: String
var _changes: int = 0
var _capture: bool = false


func _initialize() -> void:
	# The service receives an explicit temporary path before entering the tree.
	# This test never initializes game progress or reads player preferences.
	_directory = OS.get_temp_dir().path_join("three-kingdoms-ui-feedback-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(_directory)
	root.gui_embed_subwindows = true
	_capture = OS.get_cmdline_user_args().has("--capture")
	call_deferred("_run")


func _assert(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _write(path: String, value: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func _run() -> void:
	var preferences_path: String = _directory.path_join("preferences.cfg")
	var feedback: KingdomUiFeedback = FeedbackScript.new() as KingdomUiFeedback
	feedback.settings_path = preferences_path
	feedback.preferences_changed.connect(func() -> void: _changes += 1)
	root.add_child(feedback)
	_assert(feedback.is_in_group("ui_feedback"), "Presentation feedback is discoverable through its group")
	_assert(not feedback.reduced_motion and feedback.load_warning.is_empty(), "Missing preferences use ordinary feedback without a warning")
	_assert(feedback.set_reduced_motion(true) == OK, "Reduced motion commits to a local file")
	_assert(feedback.reduced_motion and _changes == 1, "Successful commit applies and signals once")
	var saved: String = FileAccess.get_file_as_string(preferences_path)
	_assert(feedback.set_reduced_motion(true) == OK and _changes == 1, "Repeated preference does not emit another change")
	feedback.settings_path = _directory.path_join("missing-parent/preferences.cfg")
	_assert(feedback.set_reduced_motion(false) != OK, "Write failure is reported")
	_assert(feedback.reduced_motion and _changes == 1, "Write failure preserves the live preference and emits no change")
	_assert(FileAccess.get_file_as_string(preferences_path) == saved, "Write failure preserves the previous preferences file")
	feedback.settings_path = preferences_path
	var directory_path: String = _directory.path_join("directory.cfg")
	DirAccess.make_dir_absolute(directory_path)
	feedback.settings_path = directory_path
	_assert(feedback.set_reduced_motion(false) != OK and feedback.reduced_motion, "A directory destination is rejected without changing the setting")
	feedback.load_settings()
	_assert(not feedback.reduced_motion and not feedback.load_warning.is_empty(), "An unreadable configuration path falls back with a warning")
	feedback.settings_path = preferences_path
	feedback.load_settings()
	DirAccess.make_dir_absolute(preferences_path + ".tmp")
	_assert(feedback.set_reduced_motion(false) != OK, "Unwritable sibling staging path reports failure")
	_assert(feedback.reduced_motion and FileAccess.get_file_as_string(preferences_path) == saved, "Staging failure keeps the old file and live preference")
	DirAccess.remove_absolute(preferences_path + ".tmp")
	var reloaded: KingdomUiFeedback = FeedbackScript.new() as KingdomUiFeedback
	reloaded.settings_path = preferences_path
	root.add_child(reloaded)
	_assert(reloaded.reduced_motion, "A new service reloads the persisted preference")
	reloaded.queue_free()
	await process_frame
	_write(preferences_path, "[display\nreduced_motion=true")
	# Suppress only ConfigFile's expected diagnostic for this malformed fixture;
	# restore engine output before the fallback assertion or any other test.
	var previous_error_output: bool = Engine.print_error_messages
	Engine.print_error_messages = false
	feedback.load_settings()
	Engine.print_error_messages = previous_error_output
	_assert(not feedback.reduced_motion and not feedback.load_warning.is_empty(), "Damaged configuration falls back to ordinary feedback")
	_write(preferences_path, '[meta]\nversion=1\n[display]\nreduced_motion="true"\n')
	feedback.load_settings()
	_assert(not feedback.reduced_motion and not feedback.load_warning.is_empty(), "A nonboolean preference is rejected")
	_write(preferences_path, "[meta]\nversion=99\n[display]\nreduced_motion=true\n")
	feedback.load_settings()
	_assert(not feedback.reduced_motion and not feedback.load_warning.is_empty(), "Unsupported configuration version falls back")
	_assert(feedback.set_reduced_motion(false) == OK and feedback.load_warning.is_empty(), "Saving a valid preference replaces a damaged configuration")
	var quiet_audio: QuietAudio = QuietAudio.new()
	root.add_child(quiet_audio)
	var menu: KingdomPresentationMenu = MenuScript.new() as KingdomPresentationMenu
	menu.audio = quiet_audio
	menu.feedback = feedback
	menu.theme = ThemeScript.create(UI_FONT)
	root.add_child(menu)
	_assert(menu._tabs.get_tab_count() == 4, "Menu includes the display preferences page")
	_assert(menu._tabs.get_tab_title(2) == "显示", "Display preferences are labeled in the tab bar")
	_assert(not menu._reduced_motion.disabled and menu._reduced_motion.focus_mode == Control.FOCUS_ALL, "Display preference supports mouse and keyboard focus")
	menu._reduced_motion.button_pressed = true
	_assert(feedback.reduced_motion and menu._display_feedback.text == "显示设置已保存", "Toggling the native checkbox commits and confirms the preference")
	feedback.settings_path = _directory.path_join("missing-parent/preferences.cfg")
	menu._reduced_motion.button_pressed = false
	_assert(feedback.reduced_motion and menu._reduced_motion.button_pressed, "Menu restores the checkbox when saving fails")
	_assert(menu._display_feedback.text == "显示设置保存失败，保留原设置", "Menu explains preference write failure")
	feedback.settings_path = preferences_path
	_assert(feedback.set_reduced_motion(false) == OK and not menu._reduced_motion.button_pressed, "Menu follows preference changes without reconnecting")
	for width: int in [1280, 390]:
		root.size = Vector2i(width, 800)
		menu._tabs.current_tab = 2
		menu.open_menu()
		for i: int in 5:
			await process_frame
		menu._fit_window()
		menu._reduced_motion.grab_focus()
		_assert(menu.size.x <= width - 24, "Display page fits a %d-pixel viewport" % width)
		_assert(menu._reduced_motion.has_focus(), "Display checkbox accepts keyboard focus in a %d-pixel viewport" % width)
		var before_keyboard: bool = feedback.reduced_motion
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = KEY_SPACE
		key.keycode = KEY_SPACE
		key.pressed = true
		menu.push_input(key)
		await process_frame
		key = key.duplicate() as InputEventKey
		key.pressed = false
		menu.push_input(key)
		await process_frame
		_assert(feedback.reduced_motion != before_keyboard, "Space activates the focused display checkbox in a %d-pixel viewport" % width)
		var before_mouse: bool = feedback.reduced_motion
		var pointer: Vector2 = Vector2(menu.position) + menu._reduced_motion.get_global_rect().get_center()
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = pointer
		motion.global_position = pointer
		root.push_input(motion, true)
		await process_frame
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = pointer
		click.global_position = pointer
		click.button_mask = MOUSE_BUTTON_MASK_LEFT
		click.pressed = true
		root.push_input(click, true)
		await process_frame
		click = click.duplicate() as InputEventMouseButton
		click.pressed = false
		click.button_mask = 0
		root.push_input(click, true)
		await process_frame
		_assert(feedback.reduced_motion != before_mouse, "Mouse click activates the display checkbox in a %d-pixel viewport" % width)
		if _capture:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/ui-feedback-display-%d.png" % width)
		menu.hide()
	menu.queue_free()
	quiet_audio.queue_free()
	await process_frame
	var holder: Control = Control.new()
	root.add_child(holder)
	var button: Button = Button.new()
	button.text = "令出"
	button.modulate = Color(0.8, 0.9, 0.7, 1)
	holder.add_child(button)
	var button_base: Color = button.modulate
	var button_scale: Vector2 = button.scale
	feedback.watch_button(button)
	feedback.watch_button(button)
	feedback.watch_button(button)
	_assert(button.pressed.get_connections().size() == 1, "Watching a button repeatedly makes only one connection")
	button.pressed.emit()
	button.pressed.emit()
	_assert(feedback._effects.size() == 1, "Rapid button input replaces its existing tween")
	_assert(button.scale == button_scale and not button.disabled, "Button feedback preserves layout and input")
	var notice: Label = Label.new()
	notice.text = "调令已下达"
	notice.modulate = Color(0.9, 0.75, 0.5, 0.8)
	holder.add_child(notice)
	var notice_base: Color = notice.modulate
	var time_scale: float = Engine.time_scale
	for i: int in 10:
		feedback.notice(notice)
	_assert(feedback._effects.size() == 2, "Rapid notices keep one effect per control")
	_assert(Engine.time_scale == time_scale, "Feedback does not change game time")
	_assert(feedback.set_reduced_motion(true) == OK, "Reduced motion can be enabled while effects are active")
	_assert(feedback._effects.is_empty(), "Reduced motion cancels every running effect")
	_assert(button.modulate.is_equal_approx(button_base) and notice.modulate.is_equal_approx(notice_base), "Cancelling effects restores every original color and opacity")
	button.pressed.emit()
	notice.hide()
	feedback.notice(notice)
	_assert(feedback._effects.is_empty() and notice.visible, "Reduced motion displays notices immediately without a tween")
	_assert(button.modulate.is_equal_approx(button_base) and notice.modulate.is_equal_approx(notice_base), "Reduced motion retains original modulation")
	_assert(feedback.set_reduced_motion(false) == OK, "Normal feedback can be reenabled")
	feedback.notice(notice)
	button.pressed.emit()
	await create_timer(0.25).timeout
	_assert(feedback._effects.is_empty(), "Completed effects clean up their tweens")
	_assert(button.modulate.is_equal_approx(button_base) and notice.modulate.is_equal_approx(notice_base), "Completed effects return to original modulation")
	feedback.notice(notice)
	var notice_id: int = notice.get_instance_id()
	notice.queue_free()
	await process_frame
	_assert(feedback._effects.is_empty() and not feedback._tracked.has(notice_id), "Freed notices clean up effects without stale references")
	button.pressed.emit()
	feedback.queue_free()
	await process_frame
	_assert(button.modulate.is_equal_approx(button_base), "Freeing the service restores in-flight button feedback")
	_assert(button.pressed.get_connections().is_empty(), "Freeing the service removes its button connection")
	var theme: Theme = ThemeScript.create(UI_FONT)
	_assert(theme.default_font == UI_FONT, "Theme retains the Chinese UI font")
	for type: String in ["Button", "PrimaryButton", "NavButton", "UtilityButton", "LineEdit", "TextEdit"]:
		_assert(theme.has_stylebox("focus", type), "%s has a visible keyboard focus style" % type)
	for type: String in ["Button", "PrimaryButton", "NavButton", "UtilityButton"]:
		_assert(theme.has_stylebox("hover", type) and theme.has_stylebox("disabled", type), "%s distinguishes hover and disabled states" % type)
	_assert(theme.has_stylebox("panel", "ResourcePanel"), "Resource panels have a compact independent visual treatment")
	holder.queue_free()
	await process_frame
	DirAccess.remove_absolute(preferences_path)
	DirAccess.remove_absolute(directory_path)
	DirAccess.remove_absolute(_directory)
	print("UI_FEEDBACK_TEST_CHECKS=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
