extends SceneTree

## Art contracts and native captures. Synthetic tiles below exercise visual
## masking and relationship cases only; captures use the canonical DTO helper.
class FeatureProbe extends "res://src/world_map.gd":
	var city_ids: Array[String] = []
	var task_ids: Array[String] = []
	var labels: Array[String] = []
	func _draw_city(center: Vector2, tile: Dictionary, is_home: bool) -> void:
		city_ids.append(str(tile.get("id", "")))
		super._draw_city(center, tile, is_home)
	func _draw_task(center: Vector2, tile: Dictionary) -> void:
		task_ids.append(str(tile.get("id", "")))
		super._draw_task(center, tile)
	func _draw_centered_text(label: String, position: Vector2, font_size: int, color: Color) -> void:
		labels.append(label)
		super._draw_centered_text(label, position, font_size, color)

class LandformProbe extends "res://src/world_map.gd":
	func _draw() -> void:
		_draw_landform(0, 7, 0, 7)

const ThemeScript: Script = preload("res://src/ui_theme.gd")
const MapScript: Script = preload("res://src/world_map.gd")
const UI_FONT: Font = preload("res://assets/fonts/UI.tres")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ShanheceWarVisualTests-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir().path_join("shader_cache"))
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame: int in range(5):
		await process_frame


func _luminance(color: Color) -> float:
	var linear: Color = color.srgb_to_linear()
	return linear.r * 0.2126 + linear.g * 0.7152 + linear.b * 0.0722


func _contrast(first: Color, second: Color) -> float:
	var a: float = _luminance(first)
	var b: float = _luminance(second)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


func _test_theme() -> void:
	var theme: Theme = ThemeScript.create(UI_FONT)
	for type: String in ["Button", "PrimaryButton", "NavButton", "UtilityButton", "OptionButton"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var box: StyleBoxFlat = theme.get_stylebox(state, type) as StyleBoxFlat
			var font_state: String = "font_color" if state == "normal" else "font_%s_color" % state
			_check(_contrast(theme.get_color(font_state, type), box.bg_color) >= 4.5, "%s %s text remains readable against bronze/charcoal surfaces." % [type, state])
		var normal: StyleBoxFlat = theme.get_stylebox("normal", type) as StyleBoxFlat
		var focus: StyleBoxFlat = theme.get_stylebox("focus", type) as StyleBoxFlat
		_check(_contrast(focus.border_color, normal.bg_color) >= 3.0, "%s retains a visible keyboard focus outline." % type)
	for type: String in ["PanelContainer", "ResourcePanel", "InsetPanel"]:
		var panel: StyleBoxFlat = theme.get_stylebox("panel", type) as StyleBoxFlat
		_check(_contrast(ThemeScript.TEXT, panel.bg_color) >= 4.5 and _contrast(ThemeScript.MUTED, panel.bg_color) >= 4.5, "%s supports readable primary and secondary information." % type)
		_check(absf(panel.bg_color.r - panel.bg_color.g) < 0.025, "%s uses a neutral charcoal surface instead of a green sheet." % type)


func _test_flags() -> void:
	# These exact semantic colors predate the art change. Preserve what players
	# learned about ownership, allies, enemies and Yellow Turban settlements.
	_check(MapScript.city_flag_color({}, true).is_equal_approx(Color("e2c181")), "The home flag retains the established ownership gold.")
	_check(MapScript.city_flag_color({"owned": true, "relation": "enemy"}, false).is_equal_approx(Color("e2c181")), "Authoritative ownership takes precedence over a stale relation.")
	for relation: String in ["allied", "friendly", "ally"]:
		_check(MapScript.city_flag_color({"relation": relation}, false).is_equal_approx(Color("75afba")), "Alliance aliases retain their established blue flag.")
	for relation: String in ["enemy", "hostile"]:
		_check(MapScript.city_flag_color({"relation": relation}, false).is_equal_approx(Color("c9715e")), "Hostile aliases retain their established red flag.")
	_check(MapScript.city_flag_color({"kind": "yellow_city"}, false).is_equal_approx(Color("d3b447")), "Yellow Turban settlements retain their established yellow flag.")
	_check(MapScript.city_flag_color({"faction": "unrecognized"}, false) == MapScript.city_flag_color({}, false), "An unrecognized faction does not invent a relationship or ownership.")


func _test_hidden_features() -> void:
	var map: FeatureProbe = FeatureProbe.new()
	root.add_child(map)
	map.size = Vector2(800, 600)
	map.set_world({"width": 64, "height": 64, "home": {"x": 32, "y": 32}, "tiles": [
		{"id": "home", "x": 32, "y": 32, "name": "青溪城", "kind": "city", "owned": true},
		{"id": "hidden-city", "x": 33, "y": 32, "name": "SECRET_CITY", "kind": "city", "hidden": true, "selectable": false, "faction": "SECRET_FACTION"},
		{"id": "hidden-task", "x": 34, "y": 32, "name": "SECRET_TASK", "kind": "landmark", "hidden": true, "selectable": false},
		{"id": "visible-city", "x": 31, "y": 32, "name": "可见城池", "kind": "city", "faction": "盟"}
	], "marches": []})
	map.focus_home()
	for scale: float in [0.25, 0.80, 1.20]:
		map.city_ids.clear()
		map.task_ids.clear()
		map.labels.clear()
		map._zoom_at(map.size * 0.5, scale)
		await _settle()
		_check(map.city_ids.has("home") and map.city_ids.has("visible-city"), "Visible settlements remain in overview, regional and close views.")
		_check(not map.city_ids.has("hidden-city") and not map.task_ids.has("hidden-task"), "Hidden DTO targets produce no city or task silhouette at any scale.")
		_check(not map.labels.has("SECRET_CITY") and not map.labels.has("SECRET_TASK") and not map.labels.has("S"), "Hidden target names and faction glyphs remain masked.")
		if scale >= 1.05:
			_check(map.labels.has("盟"), "A close view draws only the faction supplied by the visible tile.")
	map.queue_free()
	await _settle()


func _test_native_seams() -> void:
	if DisplayServer.get_name() == "headless":
		return
	root.size = Vector2i(512, 512)
	var map: LandformProbe = LandformProbe.new()
	root.add_child(map)
	map.size = Vector2(512, 512)
	map.zoom = 1.0
	var tiles: Array = []
	for y: int in range(8):
		for x: int in range(8):
			tiles.append({"x": x, "y": y, "terrain": "forest" if x < 4 else "plain"})
	map.set_world({"width": 8, "height": 8, "home": {"x": 4, "y": 4}, "tiles": tiles, "marches": []})
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(not image.is_empty() and image.get_width() == 512, "Native terrain validation reads the rendered viewport.")
	for y: int in [100, 164, 228, 292, 356, 420]:
		var left: Color = image.get_pixel(255, y)
		var right: Color = image.get_pixel(257, y)
		_check(absf(_luminance(left) - _luminance(right)) < 0.025, "Forest/plain rule-tile boundaries remain visually continuous at native resolution.")
	_check(_luminance(image.get_pixel(96, 200)) < _luminance(image.get_pixel(416, 200)), "Continuous terrain still distinguishes forest earth from open earth.")
	map.queue_free()
	await _settle()


func _capture_canonical() -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	var node: String = OS.get_environment("TK_NODE")
	var output: Array = []
	_check(not node.is_empty(), "TK_NODE is required for canonical screenshot fixtures.")
	if node.is_empty():
		return
	var result: int = OS.execute(node, [ProjectSettings.globalize_path("res://tests/helpers/playable-view.mjs")], output)
	_check(result == 0, "Canonical world DTO fixture loads without player data.")
	if result != 0:
		return
	var fixture: Dictionary = JSON.parse_string(str(output[0]))
	var shell: PanelContainer = PanelContainer.new()
	shell.theme = ThemeScript.create(UI_FONT)
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shell)
	var column: VBoxContainer = VBoxContainer.new()
	shell.add_child(column)
	var title: Label = Label.new()
	title.text = "天下舆图"
	title.theme_type_variation = "TitleLabel"
	column.add_child(title)
	var actions: HBoxContainer = HBoxContainer.new()
	column.add_child(actions)
	for caption: String in ["回城定位", "城池", "资源"]:
		var button: Button = Button.new()
		button.text = caption
		button.theme_type_variation = "UtilityButton"
		actions.add_child(button)
	var map: KingdomWorldMap = MapScript.new() as KingdomWorldMap
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(map)
	map.set_world(fixture["worldSample"])
	var hint: Label = Label.new()
	hint.text = "拖动浏览 · 滚轮缩放 · 点选目标"
	hint.theme_type_variation = "MutedLabel"
	column.add_child(hint)
	var folder: String = "res://production/qa/evidence/story-012/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(390, 844)]:
		root.size = dimensions
		await _settle()
		map.focus_home()
		map._zoom_at(map.size * 0.5, 0.80)
		await _settle()
		await RenderingServer.frame_post_draw
		var capture_result: Error = root.get_texture().get_image().save_png(folder + "war-map-%d.png" % dimensions.x)
		_check(capture_result == OK, "Canonical desktop and narrow map captures are saved.")
	root.size = Vector2i(1280, 800)
	await _settle()
	map.focus_home()
	map._zoom_at(map.size * 0.5, 0.25)
	await _settle()
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(folder + "war-map-overview.png") == OK, "Sparse overview capture is saved.")
	shell.queue_free()
	await _settle()


func _run() -> void:
	_test_theme()
	_test_flags()
	await _test_hidden_features()
	await _test_native_seams()
	await _capture_canonical()
	print("WAR_VISUAL_TEST_CHECKS=%d failures=%d native=%s" % [_checks, _failures, str(DisplayServer.get_name() != "headless")])
	quit(1 if _failures else 0)
