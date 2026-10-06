extends SceneTree

## Native-only, reproducible render benchmark. It never instantiates GameAPI,
## opens a bridge connection, or reads/writes a player save. Example:
## godot --path . --script scripts/map_profile.gd -- --label before \
##   --output .local/performance/map-before.json --warmup 30 --frames 150
## _draw timings are CPU command construction, not GPU time or FPS.

const WORKLOAD_VERSION: int = 1
const FIXTURE_SEED: int = 439903
const VIEWPORT_SIZE: Vector2i = Vector2i(1280, 800)
const MAP_PATH: String = "res://src/world_map.gd"
const METRIC_NAMES: Array[String] = [
	"frame_interval_ms", "process_cpu_ms", "draw_cpu_ms", "landform_cpu_ms",
	"rivers_cpu_ms", "marches_cpu_ms", "tile_features_cpu_ms",
	"tile_feature_calls", "route_calls", "canvas_draw_calls", "canvas_objects",
	"static_memory_bytes", "static_memory_peak_bytes"
]

class ProfiledWorldMap:
	extends "res://src/world_map.gd"

	var draw_records: Array[Dictionary] = []
	var process_records: Array[float] = []
	var layer_us: Dictionary = {}
	var tile_feature_calls: int = 0
	var route_calls: int = 0

	func _draw() -> void:
		layer_us = {"landform": 0, "rivers": 0, "marches": 0, "tile_features": 0}
		tile_feature_calls = 0
		route_calls = 0
		var started: int = Time.get_ticks_usec()
		super._draw()
		draw_records.append({
			"draw_cpu_ms": float(Time.get_ticks_usec() - started) / 1000.0,
			"landform_cpu_ms": float(layer_us["landform"]) / 1000.0,
			"rivers_cpu_ms": float(layer_us["rivers"]) / 1000.0,
			"marches_cpu_ms": float(layer_us["marches"]) / 1000.0,
			"tile_features_cpu_ms": float(layer_us["tile_features"]) / 1000.0,
			"tile_feature_calls": tile_feature_calls, "route_calls": route_calls
		})

	func _draw_landform(min_x: int, max_x: int, min_y: int, max_y: int) -> void:
		var started: int = Time.get_ticks_usec()
		super._draw_landform(min_x, max_x, min_y, max_y)
		layer_us["landform"] += Time.get_ticks_usec() - started

	func _draw_rivers() -> void:
		var started: int = Time.get_ticks_usec()
		super._draw_rivers()
		layer_us["rivers"] += Time.get_ticks_usec() - started

	func _draw_marches() -> void:
		var started: int = Time.get_ticks_usec()
		super._draw_marches()
		layer_us["marches"] += Time.get_ticks_usec() - started

	func _draw_tile_features(tile: Dictionary, coordinates: Vector2i) -> void:
		var started: int = Time.get_ticks_usec()
		super._draw_tile_features(tile, coordinates)
		layer_us["tile_features"] += Time.get_ticks_usec() - started
		tile_feature_calls += 1

	func _draw_dashed_line(start: Vector2, target: Vector2, color: Color, width: float) -> void:
		route_calls += 1
		super._draw_dashed_line(start, target, color, width)

	func _process(delta: float) -> void:
		var started: int = Time.get_ticks_usec()
		super._process(delta)
		process_records.append(float(Time.get_ticks_usec() - started) / 1000.0)


var warmup_frames: int = 30
var sample_frames: int = 150
var run_label: String = "native"
var output_path: String = ""
var only_scenario: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _parse_arguments():
		quit(2)
		return
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		push_error("MAP_PROFILE requires an actual native window and renderer; headless/Web timing is rejected.")
		quit(2)
		return
	Engine.max_fps = 60
	OS.low_processor_usage_mode = false
	root.size = VIEWPORT_SIZE
	root.title = "三国城志 · 地图性能基准（不读写玩家存档）"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	await process_frame
	await RenderingServer.frame_post_draw
	var map_hash: String = FileAccess.get_sha256(MAP_PATH)
	var harness_hash: String = FileAccess.get_sha256("res://scripts/map_profile.gd")
	var started_at: String = Time.get_datetime_string_from_system(true)
	var result: Dictionary = {
		"schema_version": 1, "workload_version": WORKLOAD_VERSION,
		"label": run_label, "started_at_utc": started_at,
		"source_sha256": map_hash,
		"harness_sha256": harness_hash,
		"environment": _environment(),
		"parameters": {"seed": FIXTURE_SEED, "warmup_frames": warmup_frames,
			"sample_frames": sample_frames, "frame_cap": Engine.max_fps,
			"viewport_size": [VIEWPORT_SIZE.x, VIEWPORT_SIZE.y],
			"march_relative_start_ms": -86400000, "march_relative_arrive_ms": 86400000},
		"limitations": [
			"Native macOS/Windows/Linux run only; this is not Windows or Web validation unless that OS is recorded.",
			"CPU draw metrics measure GDScript drawing-command construction with instrumentation overhead; never infer FPS from them.",
			"Frame intervals include VSync, OS scheduling and rendering; samples do not measure input latency.",
			"No GPU frame time is captured. GPU timing is unavailable in this harness.",
			"Static-memory monitors cover the whole debug Godot process, not exclusively map memory or total OS resident memory.",
			"Synthetic complete tile DTOs exercise rendering capacity; a 256x256 fixture does not change the canonical 64x64 game world.",
			"Marches use relative real system timestamps, with 48-hour trips to keep geometry nearly fixed while production animation runs.",
			"Canvas draw calls are actual viewport CANVAS renderer counters; layer/tile/route calls are separate script counts.",
			"A static map normally has zero sample redraws after warm-up; its initial draw cost is recorded separately.",
			"No committed performance budget is loaded by this harness; measured values have no pass/fail budget verdict."
		],
		"gpu_frame_time_ms": null, "gpu_frame_time_status": "UNAVAILABLE",
		"scenarios": []
	}
	var scenarios: Array[Dictionary] = [
		{"id": "64_static", "dimension": 64, "zoom": 0.8, "marches": 0, "pan": false},
		{"id": "64_pan", "dimension": 64, "zoom": 0.8, "marches": 0, "pan": true},
		{"id": "256_overview_pan", "dimension": 256, "zoom": 0.17, "marches": 0, "pan": true},
		{"id": "256_marches_pan", "dimension": 256, "zoom": 0.8, "marches": 200, "pan": true},
		{"id": "256_marches_idle", "dimension": 256, "zoom": 0.8, "marches": 200, "pan": false}
	]
	for scenario: Dictionary in scenarios:
		if not only_scenario.is_empty() and str(scenario["id"]) != only_scenario:
			continue
		var scenario_result: Variant = await _sample_scenario(scenario)
		if not scenario_result is Dictionary:
			push_error("Scenario failed; incomplete output will not be saved: " + str(scenario["id"]))
			quit(5)
			return
		result["scenarios"].append(scenario_result)
	if result["scenarios"].is_empty():
		push_error("Unknown --scenario. No benchmark was run.")
		quit(2)
		return
	result["completed_at_utc"] = Time.get_datetime_string_from_system(true)
	result["source_unchanged_during_run"] = map_hash == FileAccess.get_sha256(MAP_PATH)
	result["harness_unchanged_during_run"] = harness_hash == FileAccess.get_sha256("res://scripts/map_profile.gd")
	result["viewport_unchanged_during_run"] = root.size == VIEWPORT_SIZE
	var scenarios_valid: bool = true
	for scenario: Dictionary in result["scenarios"]:
		scenarios_valid = scenarios_valid and bool(scenario["valid"])
	result["all_scenarios_valid"] = scenarios_valid
	result["valid"] = bool(result["source_unchanged_during_run"]) and bool(result["harness_unchanged_during_run"]) and bool(result["viewport_unchanged_during_run"]) and scenarios_valid
	if not _write_atomic(result):
		quit(3)
		return
	print("MAP_PROFILE_OUTPUT=" + output_path)
	print("MAP_PROFILE_VALID=" + str(result["valid"]))
	quit(0 if bool(result["valid"]) else 4)


func _parse_arguments() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < args.size():
		var option: String = args[index]
		if option == "--help":
			print("Native map profile: --output .local/performance/file.json --label before|after --warmup 30 --frames 150 [--scenario 64_static|64_pan|256_overview_pan|256_marches_pan|256_marches_idle]")
			return false
		if option not in ["--output", "--label", "--warmup", "--frames", "--scenario"] or index + 1 >= args.size():
			push_error("Unknown option or missing value: " + option)
			return false
		var value: String = args[index + 1]
		match option:
			"--output": output_path = value
			"--label": run_label = value
			"--scenario": only_scenario = value
			"--warmup":
				if not value.is_valid_int(): return false
				warmup_frames = int(value)
			"--frames":
				if not value.is_valid_int(): return false
				sample_frames = int(value)
		index += 2
	if warmup_frames < 2 or warmup_frames > 300 or sample_frames < 10 or sample_frames > 1800:
		push_error("Use 2..300 warm-up frames and 10..1800 sample frames.")
		return false
	if output_path.is_empty():
		output_path = ".local/performance/map-" + Time.get_datetime_string_from_system(true).replace(":", "-") + ".json"
	if not output_path.is_absolute_path():
		output_path = ProjectSettings.globalize_path("res://" + output_path)
	output_path = output_path.simplify_path()
	var allowed: String = ProjectSettings.globalize_path("res://.local/performance/")
	if not output_path.begins_with(allowed) or not output_path.ends_with(".json"):
		push_error("Benchmark output must be a .json file inside this project's .local/performance/ folder.")
		return false
	return true


func _environment() -> Dictionary:
	return {
		"os": OS.get_name(), "os_version": OS.get_version(),
		"processor": OS.get_processor_name(), "processor_count": OS.get_processor_count(),
		"godot": Engine.get_version_info(), "debug_build": OS.is_debug_build(),
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"video_vendor": RenderingServer.get_video_adapter_vendor(),
		"video_api": RenderingServer.get_video_adapter_api_version(),
		"screen_refresh_rate_hz": DisplayServer.screen_get_refresh_rate(),
		"screen_scale": DisplayServer.screen_get_scale(),
		"window_size": [root.size.x, root.size.y],
		"viewport_size": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"headless": false, "player_data_accessed": false
	}


func _sample_scenario(scenario: Dictionary) -> Dictionary:
	print("MAP_PROFILE_SCENARIO=" + str(scenario["id"]))
	var fixture: Dictionary = _fixture(int(scenario["dimension"]), int(scenario["marches"]))
	var normalized: Dictionary = fixture.duplicate(true)
	for march: Dictionary in normalized["marches"]:
		march["start"] = -86400000
		march["arrive"] = 86400000 if march["arrive"] != null else null
	var fixture_hash: String = JSON.stringify(normalized).sha256_text()
	normalized.clear()
	var map: ProfiledWorldMap = ProfiledWorldMap.new()
	root.add_child(map)
	map.size = Vector2(VIEWPORT_SIZE)
	map.zoom = float(scenario["zoom"])
	var initial_memory: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var started: int = Time.get_ticks_usec()
	map.set_world(fixture)
	var set_world_cpu_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	map.camera_center = Vector2.ONE * (float(scenario["dimension"]) * 0.5 + 0.5)
	map.regions = [{"name": "基准分区", "bounds": [0, 0, int(scenario["dimension"]), int(scenario["dimension"])], "color": "8c937d"}]
	map.queue_redraw()
	for frame: int in range(warmup_frames):
		await process_frame
		_apply_camera(map, scenario, frame)
		await RenderingServer.frame_post_draw
	var warmup_draws: Array[Dictionary] = map.draw_records.duplicate(true)
	map.draw_records.clear()
	map.process_records.clear()
	var rows: Array[Dictionary] = []
	var previous_frame_us: int = Time.get_ticks_usec()
	var sample_started_us: int = previous_frame_us
	var total_redraws: int = 0
	var draw_rows: Array[Dictionary] = []
	for frame: int in range(sample_frames):
		await process_frame
		_apply_camera(map, scenario, warmup_frames + frame)
		await RenderingServer.frame_post_draw
		var now_us: int = Time.get_ticks_usec()
		var process_us: float = 0.0
		for value: float in map.process_records:
			process_us += value
		var row: Dictionary = {
			"frame_index": frame, "frame_interval_ms": float(now_us - previous_frame_us) / 1000.0,
			"process_cpu_ms": process_us, "process_count": map.process_records.size(), "redraw_count": map.draw_records.size(),
			"camera": [map.camera_center.x, map.camera_center.y],
			"canvas_draw_calls": root.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"canvas_objects": root.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
			"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
			"static_memory_peak_bytes": Performance.get_monitor(Performance.MEMORY_STATIC_MAX)
		}
		for name: String in ["draw_cpu_ms", "landform_cpu_ms", "rivers_cpu_ms", "marches_cpu_ms", "tile_features_cpu_ms", "tile_feature_calls", "route_calls"]:
			row[name] = 0.0
			for draw_row: Dictionary in map.draw_records:
				row[name] += float(draw_row[name])
		draw_rows.append_array(map.draw_records)
		total_redraws += map.draw_records.size()
		rows.append(row)
		map.draw_records.clear()
		map.process_records.clear()
		previous_frame_us = now_us
	var summary: Dictionary = {}
	for name: String in METRIC_NAMES:
		var values: Array[float] = []
		for row: Dictionary in rows:
			values.append(float(row[name]))
		summary[name] = _stats(values)
	var per_redraw: Dictionary = {}
	for name: String in ["draw_cpu_ms", "landform_cpu_ms", "rivers_cpu_ms", "marches_cpu_ms", "tile_features_cpu_ms", "tile_feature_calls", "route_calls"]:
		var values: Array[float] = []
		for row: Dictionary in draw_rows:
			values.append(float(row[name]))
		per_redraw[name] = _stats(values)
	var actual_duration_ms: float = float(previous_frame_us - sample_started_us) / 1000.0
	var frame_duration_ms: float = 0.0
	var valid_rows: bool = rows.size() == sample_frames
	for row: Dictionary in rows:
		frame_duration_ms += float(row["frame_interval_ms"])
		valid_rows = valid_rows and float(row["frame_interval_ms"]) > 0.0 and int(row["process_count"]) >= 1
	var duration_matches: bool = absf(frame_duration_ms - actual_duration_ms) < 0.01
	var redraws_valid: bool = not warmup_draws.is_empty()
	# Multiple real redraw callbacks in one displayed frame are a production cost
	# to measure, not a malformed sample. Panning must redraw at least once/frame.
	if bool(scenario["pan"]):
		for row: Dictionary in rows:
			redraws_valid = redraws_valid and int(row["redraw_count"]) >= 1
	if int(scenario["marches"]) > 0:
		redraws_valid = redraws_valid and total_redraws > 1
	var result: Dictionary = {
		"id": scenario["id"], "world_dimension": scenario["dimension"],
		"zoom": scenario["zoom"], "pan": scenario["pan"],
		"tile_count": fixture["tiles"].size(), "march_count": fixture["marches"].size(),
		"fixture_sha256_without_wall_clock": fixture_hash,
		"set_world_cpu_ms": set_world_cpu_ms,
		"static_memory_before_set_world_bytes": initial_memory,
		"static_memory_after_set_world_bytes": rows[0]["static_memory_bytes"],
		"warmup_redraw_count": warmup_draws.size(),
		"initial_draw": warmup_draws[0] if not warmup_draws.is_empty() else null,
		"sample_redraw_count": total_redraws,
		"sample_duration_ms": actual_duration_ms,
		"validation": {"complete_positive_frame_samples_with_process": valid_rows,
			"duration_matches_summed_intervals": duration_matches, "expected_real_redraws": redraws_valid},
		"valid": valid_rows and duration_matches and redraws_valid,
		"summary_per_frame": summary, "summary_per_redraw": per_redraw,
		"raw_frames": rows
	}
	var redraw_p95: float = float(per_redraw["draw_cpu_ms"]["p95"]) if total_redraws > 0 else 0.0
	print("MAP_PROFILE_RESULT %s redraws=%d draw_cpu_p95=%.3fms frame_interval_p95=%.3fms" % [
		str(scenario["id"]), total_redraws, redraw_p95, float(summary["frame_interval_ms"]["p95"])])
	map.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	return result


func _apply_camera(map: ProfiledWorldMap, scenario: Dictionary, frame: int) -> void:
	if not bool(scenario["pan"]):
		return
	# Frame-indexed 480px/s nominal sweep; identical camera positions in every run.
	var center: float = float(scenario["dimension"]) * 0.5 + 0.5
	var phase: float = float(frame) / 60.0
	var displacement: Vector2 = Vector2(sin(phase) * 480.0, sin(phase * 0.7) * 240.0) / map.cell_pixels()
	map.camera_center = map.clamp_camera(Vector2.ONE * center + displacement, map.size, map.world_size(), map.cell_pixels())
	map.queue_redraw()


func _fixture(dimension: int, march_count: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = FIXTURE_SEED
	var tiles: Array[Dictionary] = []
	var middle: int = dimension / 2
	for y: int in range(dimension):
		for x: int in range(dimension):
			var ridge: float = sin(float(x) * 0.15 + cos(float(y) * 0.11) * 2.6)
			var forest: float = sin(float(x) * 0.23) * cos(float(y) * 0.18)
			var terrain: String = "mountain" if ridge > 0.82 else ("forest" if forest > 0.35 else "plain")
			var kind: String = "wild"
			var home: bool = x == middle and y == middle
			var roll: float = rng.randf()
			if home or roll < 0.002:
				kind = "city"
			elif roll < 0.003:
				kind = "landmark"
			tiles.append({"id": "home" if home else "tile-%d-%d" % [x, y],
				"x": x, "y": y, "terrain": terrain, "kind": kind,
				"name": "基准城池" if kind == "city" else ("基准据点" if kind == "landmark" else "野地"),
				"level": 3, "owned": home, "hidden": false, "selectable": true})
	var marches: Array[Dictionary] = []
	var now_ms: float = Time.get_unix_time_from_system() * 1000.0
	for index: int in range(march_count):
		var origin: Vector2i
		var target: Vector2i
		if index < 10:
			origin = Vector2i(middle + rng.randi_range(-8, 8), middle + rng.randi_range(-5, 5))
			target = origin + Vector2i(rng.randi_range(-10, 10), rng.randi_range(-6, 6))
		elif index < 16:
			origin = Vector2i(5, middle + index - 13)
			target = Vector2i(dimension - 6, middle + index - 13)
		else:
			var low_edge: bool = index % 2 == 0
			origin = Vector2i(rng.randi_range(4, dimension - 45), rng.randi_range(5, 24) if low_edge else rng.randi_range(dimension - 25, dimension - 6))
			target = origin + Vector2i(rng.randi_range(10, 40), rng.randi_range(-3, 3))
		var stationary: bool = index % 4 in [2, 3]
		var status: String = ["march", "return", "stationed", "gathering"][index % 4]
		if stationary:
			origin = target
		marches.append({"id": "bench-march-%d" % index, "label": "基准部队%d" % index,
			"from": {"x": origin.x, "y": origin.y}, "to": {"x": target.x, "y": target.y},
			"start": now_ms - 86400000.0, "arrive": null if stationary else now_ms + 86400000.0,
			"status": status, "count": 1000, "army": {"archer": 1000}})
	return {"width": dimension, "height": dimension, "home": {"x": middle, "y": middle}, "tiles": tiles, "marches": marches}


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "min": null, "p50": null, "p95": null, "max": null, "mean": null}
	values.sort()
	var total: float = 0.0
	for value: float in values:
		total += value
	return {"count": values.size(), "min": values[0],
		"p50": values[clampi(ceili(float(values.size()) * 0.50) - 1, 0, values.size() - 1)],
		"p95": values[clampi(ceili(float(values.size()) * 0.95) - 1, 0, values.size() - 1)],
		"max": values[-1], "mean": total / float(values.size())}


func _write_atomic(result: Dictionary) -> bool:
	var error: Error = DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if error != OK:
		push_error("Cannot create benchmark output directory: " + error_string(error))
		return false
	var temporary_path: String = output_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot open benchmark output: " + error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		push_error("Cannot write benchmark output: " + error_string(write_error))
		DirAccess.remove_absolute(temporary_path)
		return false
	error = DirAccess.rename_absolute(temporary_path, output_path)
	if error != OK:
		push_error("Cannot atomically replace benchmark output: " + error_string(error))
		DirAccess.remove_absolute(temporary_path)
		return false
	return true
