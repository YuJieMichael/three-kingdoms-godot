#!/usr/bin/env python3
"""Compare matched native map profiles without treating CPU draw cost as FPS.

Usage:
    python3 scripts/compare_map_profiles.py .local/performance/map-before.json \
        .local/performance/map-after.json --output .local/performance/map-comparison.json

Only the project's local benchmark directory is read or written by the CLI.
compare_profiles() is a pure function for isolated validation tests.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PERFORMANCE_DIR = ROOT / ".local" / "performance"
ENVIRONMENT_KEYS = (
    "os", "os_version", "processor", "processor_count", "godot", "debug_build",
    "display_server", "rendering_method", "rendering_driver", "video_adapter",
    "video_vendor", "video_api", "screen_refresh_rate_hz", "screen_scale",
    "window_size", "viewport_size", "vsync_mode", "headless", "player_data_accessed",
)
SCENARIO_KEYS = (
    "id", "world_dimension", "zoom", "pan", "tile_count", "march_count",
    "fixture_sha256_without_wall_clock",
)
METRICS = (
    "draw_cpu_ms", "process_cpu_ms", "frame_interval_ms", "canvas_draw_calls",
    "static_memory_bytes",
)


class ProfileMismatch(ValueError):
    """An invalid or unmatched workload must not produce a success verdict."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ProfileMismatch(message)


def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def hash_value(value: Any, description: str) -> None:
    require(isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value) is not None,
            f"{description}: missing or invalid SHA256")


def stats(value: Any, description: str, expected_count: int) -> dict[str, Any]:
    require(isinstance(value, dict), f"{description}: missing statistics")
    require(type(value.get("count")) is int and value["count"] == expected_count,
            f"{description}: incorrect sample count")
    names = ("min", "p50", "p95", "max", "mean")
    require(all(name in value for name in names), f"{description}: incomplete statistics")
    if expected_count == 0:
        require(all(value[name] is None for name in names),
                f"{description}: empty redraw statistics must retain null")
    else:
        require(all(finite_number(value[name]) and value[name] >= 0 for name in names),
                f"{description}: invalid numeric statistics")
        require(value["min"] <= value["p50"] <= value["p95"] <= value["max"],
                f"{description}: invalid percentile order")
    return value


def validate_profile(profile: Any, label: str) -> None:
    require(isinstance(profile, dict), f"{label}: profile must be a JSON object")
    require(profile.get("schema_version") == 1, f"{label}: unsupported profile schema")
    for flag in ("valid", "all_scenarios_valid", "source_unchanged_during_run",
                 "harness_unchanged_during_run", "viewport_unchanged_during_run"):
        require(profile.get(flag) is True, f"{label}: {flag} is not true")
    hash_value(profile.get("harness_sha256"), f"{label} harness")
    hash_value(profile.get("source_sha256"), f"{label} source")
    parameters = profile.get("parameters")
    require(isinstance(parameters, dict), f"{label}: missing parameters")
    require(type(parameters.get("sample_frames")) is int and parameters["sample_frames"] >= 10,
            f"{label}: invalid sample_frames")
    require(type(parameters.get("warmup_frames")) is int and parameters["warmup_frames"] >= 2,
            f"{label}: invalid warmup_frames")
    environment = profile.get("environment")
    require(isinstance(environment, dict), f"{label}: missing native environment")
    require(all(key in environment for key in ENVIRONMENT_KEYS), f"{label}: incomplete native environment")
    require(environment["headless"] is False and environment["player_data_accessed"] is False,
            f"{label}: run is headless or accesses player data")
    require(environment["display_server"] != "headless" and environment["os"] != "Web",
            f"{label}: run is not native")
    require(profile.get("gpu_frame_time_status") == "UNAVAILABLE" and profile.get("gpu_frame_time_ms") is None,
            f"{label}: unsupported GPU measurement semantics")
    scenarios = profile.get("scenarios")
    require(isinstance(scenarios, list) and len(scenarios) > 0, f"{label}: no scenarios")
    seen: set[str] = set()
    for scenario in scenarios:
        require(isinstance(scenario, dict), f"{label}: null or invalid scenario")
        require(all(key in scenario for key in SCENARIO_KEYS), f"{label}: incomplete scenario metadata")
        scenario_id = scenario["id"]
        require(isinstance(scenario_id, str) and scenario_id not in seen, f"{label}: duplicate or invalid scenario ID")
        seen.add(scenario_id)
        prefix = f"{label}/{scenario_id}"
        require(scenario.get("valid") is True, f"{prefix}: scenario is invalid")
        validation = scenario.get("validation")
        require(isinstance(validation, dict) and validation and all(v is True for v in validation.values()),
                f"{prefix}: scenario validation is incomplete or failed")
        hash_value(scenario["fixture_sha256_without_wall_clock"], f"{prefix} fixture")
        rows = scenario.get("raw_frames")
        require(isinstance(rows, list) and len(rows) == parameters["sample_frames"], f"{prefix}: incomplete raw samples")
        redraw_count = scenario.get("sample_redraw_count")
        require(type(redraw_count) is int and redraw_count >= 0, f"{prefix}: invalid redraw count")
        total_redraws = 0
        total_duration = 0.0
        for index, row in enumerate(rows):
            require(isinstance(row, dict) and row.get("frame_index") == index, f"{prefix}: invalid frame index")
            require(type(row.get("redraw_count")) is int and row["redraw_count"] >= 0, f"{prefix}: invalid frame redraw count")
            require(type(row.get("process_count")) is int and row["process_count"] >= 1, f"{prefix}: process callback missing")
            camera = row.get("camera")
            require(isinstance(camera, list) and len(camera) == 2 and all(finite_number(v) for v in camera),
                    f"{prefix}: invalid camera path")
            require(all(finite_number(row.get(metric)) and row[metric] >= 0 for metric in METRICS),
                    f"{prefix}: invalid raw measurement")
            require(row["frame_interval_ms"] > 0, f"{prefix}: nonpositive frame interval")
            total_redraws += row["redraw_count"]
            total_duration += row["frame_interval_ms"]
        require(total_redraws == redraw_count, f"{prefix}: raw redraw count does not match summary")
        require(finite_number(scenario.get("sample_duration_ms")) and
                abs(total_duration - scenario["sample_duration_ms"]) < 0.01,
                f"{prefix}: sample duration does not match intervals")
        per_frame, per_redraw = scenario.get("summary_per_frame"), scenario.get("summary_per_redraw")
        require(isinstance(per_frame, dict) and isinstance(per_redraw, dict), f"{prefix}: missing summaries")
        for metric in METRICS:
            stats(per_frame.get(metric), f"{prefix}/frame/{metric}", len(rows))
        stats(per_redraw.get("draw_cpu_ms"), f"{prefix}/redraw/draw_cpu_ms", redraw_count)


def compare_profiles(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    """Validate actual native profiles and return a separate matched comparison."""
    validate_profile(before, "before")
    validate_profile(after, "after")
    for key in ("schema_version", "workload_version", "harness_sha256", "parameters"):
        require(key in before and key in after and before[key] == after[key], f"{key} mismatch")
    for key in ENVIRONMENT_KEYS:
        require(before["environment"][key] == after["environment"][key], f"native environment {key} mismatch")
    require([s["id"] for s in before["scenarios"]] == [s["id"] for s in after["scenarios"]],
            "scenario list/order mismatch")
    comparisons = []
    for old, new in zip(before["scenarios"], after["scenarios"]):
        scenario_id = old["id"]
        for key in SCENARIO_KEYS:
            require(old[key] == new[key], f"{scenario_id}: {key} mismatch")
        for index, (old_row, new_row) in enumerate(zip(old["raw_frames"], new["raw_frames"])):
            require(old_row["camera"] == new_row["camera"], f"{scenario_id}: camera path mismatch at frame {index}")
        old_draw = old["summary_per_redraw"]["draw_cpu_ms"]
        new_draw = new["summary_per_redraw"]["draw_cpu_ms"]
        comparisons.append({
            "id": scenario_id,
            "sample_frames": before["parameters"]["sample_frames"],
            "cpu_draw_per_redraw_ms": {"before": old_draw, "after": new_draw},
            "cpu_draw_per_sample_frame_ms": {
                "before": old["summary_per_frame"]["draw_cpu_ms"],
                "after": new["summary_per_frame"]["draw_cpu_ms"],
            },
            "redraw_count": {"before": old["sample_redraw_count"], "after": new["sample_redraw_count"]},
            "frame_interval_ms": {"before": old["summary_per_frame"]["frame_interval_ms"],
                                  "after": new["summary_per_frame"]["frame_interval_ms"]},
            "canvas_draw_calls": {"before": old["summary_per_frame"]["canvas_draw_calls"],
                                  "after": new["summary_per_frame"]["canvas_draw_calls"]},
            "process_cpu_ms": {"before": old["summary_per_frame"]["process_cpu_ms"],
                               "after": new["summary_per_frame"]["process_cpu_ms"]},
            "static_memory_bytes": {"before": old["summary_per_frame"]["static_memory_bytes"],
                                    "after": new["summary_per_frame"]["static_memory_bytes"]},
        })
    return {
        "schema_version": 1, "matched": True,
        "harness_sha256": before["harness_sha256"],
        "source_sha256": {"before": before["source_sha256"], "after": after["source_sha256"]},
        "parameters": before["parameters"], "environment": before["environment"],
        "scenarios": comparisons,
        "limitations": [
            "CPU draw metrics measure instrumented drawing-command construction, not FPS or GPU time.",
            "Observed frame intervals include VSync, OS scheduling and rendering; they are reported separately.",
            "A single matched before/after run is a local sample, not a Windows/Web or general hardware guarantee.",
            "Per-redraw null statistics are retained when a static map does not redraw after warm-up.",
            "set_world is a single snapshot and is intentionally excluded from percentage speedup claims.",
            "GPU frame timing remains unavailable; no performance-budget pass/fail verdict is produced.",
        ],
    }


def percentile_pair(value: dict[str, Any]) -> str:
    return "null / null" if value["count"] == 0 else f'{value["p50"]:.3f} / {value["p95"]:.3f}'


def print_tables(comparison: dict[str, Any]) -> None:
    print("Matched native workload and environment; values are p50 / p95 in milliseconds.")
    print("CPU drawing-command construction (not FPS or GPU time):")
    print("| Scenario | Per redraw before | Per redraw after | Per sample frame before | Per sample frame after |")
    print("|---|---:|---:|---:|---:|")
    for row in comparison["scenarios"]:
        draw, frame = row["cpu_draw_per_redraw_ms"], row["cpu_draw_per_sample_frame_ms"]
        print(f'| {row["id"]} | {percentile_pair(draw["before"])} | {percentile_pair(draw["after"])} | '
              f'{percentile_pair(frame["before"])} | {percentile_pair(frame["after"])} |')
    print("\nActual frame intervals and real viewport CANVAS renderer counters:")
    print("| Scenario | Redraws before / after | Frame interval before | Frame interval after | CANVAS draw calls p95 before / after |")
    print("|---|---:|---:|---:|---:|")
    for row in comparison["scenarios"]:
        redraw, interval, calls = row["redraw_count"], row["frame_interval_ms"], row["canvas_draw_calls"]
        print(f'| {row["id"]} | {redraw["before"]} / {redraw["after"]} | {percentile_pair(interval["before"])} | '
              f'{percentile_pair(interval["after"])} | {calls["before"]["p95"]:.0f} / {calls["after"]["p95"]:.0f} |')
    print("\nGPU frame timing unavailable. set_world snapshot excluded from speedup claims. No budget verdict.")


def local_benchmark_path(value: str) -> Path:
    path = Path(value).expanduser().resolve()
    require(path.is_relative_to(PERFORMANCE_DIR.resolve()) and path.suffix == ".json",
            "Input/output must be .json inside this project's .local/performance/ directory")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("--output", help="Optional atomic JSON comparison inside .local/performance/")
    args = parser.parse_args(argv)
    try:
        before_path, after_path = local_benchmark_path(args.before), local_benchmark_path(args.after)
        before, after = (json.loads(path.read_text(encoding="utf-8")) for path in (before_path, after_path))
        comparison = compare_profiles(before, after)
        if args.output:
            output = local_benchmark_path(args.output)
            require(output not in (before_path, after_path), "Comparison output must not replace input profiles")
            output.parent.mkdir(parents=True, exist_ok=True)
            temporary = output.with_suffix(output.suffix + ".tmp")
            temporary.write_text(json.dumps(comparison, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
            temporary.replace(output)
        print_tables(comparison)
        return 0
    except (ProfileMismatch, OSError, json.JSONDecodeError) as error:
        print(f"MAP_PROFILE_COMPARISON_REJECTED: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
