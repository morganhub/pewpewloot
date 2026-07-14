#!/usr/bin/env python3
"""Audit script: scan data/worlds/world_*.json and report waves likely to be empty.

Run from repo root:
    python tools/audit_waves.py
"""

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
WORLDS_DIR = REPO / "data" / "worlds"
ENEMIES_FILE = REPO / "data" / "enemies.json"
PATTERNS_FILE = REPO / "data" / "patterns" / "move_patterns.json"


def _ids_from_collection(collection):
    ids = set()
    if isinstance(collection, dict):
        for k, v in collection.items():
            if isinstance(v, dict):
                ids.add(v.get("id", k))
            else:
                ids.add(k)
    elif isinstance(collection, list):
        for v in collection:
            if isinstance(v, dict) and "id" in v:
                ids.add(v["id"])
    return ids


def load_known_enemy_ids():
    with open(ENEMIES_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)
    enemies = data.get("enemies", data) if isinstance(data, dict) else data
    return _ids_from_collection(enemies)


def load_known_obstacle_ids():
    obstacles_file = REPO / "data" / "obstacles.json"
    if not obstacles_file.exists():
        return set()
    with open(obstacles_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    obstacles = data.get("obstacles", data) if isinstance(data, dict) else data
    return _ids_from_collection(obstacles)


def load_known_pattern_ids():
    patterns_file = REPO / "data" / "patterns" / "move_patterns.json"
    if not patterns_file.exists():
        return set()
    with open(patterns_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    patterns = data.get("patterns", data) if isinstance(data, dict) else data
    return _ids_from_collection(patterns)


def iter_levels(world_data):
    levels = []
    if isinstance(world_data, dict):
        if "levels" in world_data and isinstance(world_data["levels"], list):
            levels = world_data["levels"]
        elif "_levels" in world_data and isinstance(world_data["_levels"], list):
            levels = world_data["_levels"]
        else:
            for key in ("normal_levels", "boss_level"):
                if key in world_data:
                    val = world_data[key]
                    if isinstance(val, list):
                        levels.extend(val)
                    elif isinstance(val, dict):
                        levels.append(val)
    return levels


def classify_wave(wave, enemy_ids, obstacle_ids, pattern_ids):
    wave_type = wave.get("type")
    enemy_id = wave.get("enemy_id")
    obstacle_id = wave.get("obstacle_id")
    pattern_id = wave.get("pattern_id")
    interval = wave.get("interval")
    duration = wave.get("duration", 20.0)

    notes = []

    if wave_type == "obstacle":
        if not obstacle_id:
            return ("missing_obstacle_id", "type=obstacle but no obstacle_id", notes)
        if obstacle_ids and obstacle_id not in obstacle_ids:
            return ("unknown_obstacle", f"obstacle_id '{obstacle_id}' not in obstacles.json", notes)
        return ("ok_obstacle", "", notes)
    if wave_type == "snake":
        # Refonte 2026-07 : l'ex path_trial est devenu le mini-jeu snake
        # (aucun pattern_id requis, tuning pur data).
        return ("ok_snake", "", notes)

    if wave_type is None and obstacle_id:
        return ("missing_obstacle_type", "obstacle_id present but type missing -> falls into enemy branch", notes)

    if wave_type in (None, "enemy"):
        if not enemy_id:
            return ("empty_default", "no enemy_id -> falls back to enemy_basic (does not exist)", notes)
        if enemy_id not in enemy_ids:
            return ("unknown_enemy", f"enemy_id '{enemy_id}' not in enemies.json", notes)
        if interval is not None and (interval <= 0 or interval > duration):
            notes.append(f"suspect interval={interval} duration={duration}")
        return ("ok", "", notes)
    return ("unknown_type", f"unknown type '{wave_type}'", notes)


def main():
    enemy_ids = load_known_enemy_ids()
    obstacle_ids = load_known_obstacle_ids()
    pattern_ids = load_known_pattern_ids()
    print(f"Known enemy ids: {sorted(enemy_ids)}")
    print(f"Known obstacle ids: {sorted(obstacle_ids)}")
    print(f"Known pattern ids ({len(pattern_ids)}): {sorted(pattern_ids)}\n")

    issues = 0
    notes_count = 0
    suggested_patches = {}
    wave_summary = {"ok": 0, "ok_obstacle": 0, "ok_snake": 0}

    for world_path in sorted(WORLDS_DIR.glob("world_*.json")):
        with open(world_path, "r", encoding="utf-8") as f:
            world = json.load(f)
        levels = iter_levels(world)
        printed_world = False
        for level in levels:
            if not isinstance(level, dict):
                continue
            level_id = level.get("id", "?")
            waves = level.get("waves", [])
            if not isinstance(waves, list):
                continue
            for idx, wave in enumerate(waves):
                if not isinstance(wave, dict):
                    continue
                status, reason, notes = classify_wave(wave, enemy_ids, obstacle_ids, pattern_ids)
                wave_summary[status] = wave_summary.get(status, 0) + 1
                if status not in ("ok", "ok_obstacle", "ok_snake") or notes:
                    if not printed_world:
                        print(f"=== {world_path.name} ===")
                        printed_world = True
                    print(f"  level={level_id} wave#{idx} status={status} :: {reason}")
                    if notes:
                        print(f"    notes: {notes}")
                        notes_count += 1
                    print(f"    raw: {json.dumps(wave, ensure_ascii=False)}")
                    if status not in ("ok", "ok_obstacle", "ok_snake"):
                        issues += 1
                        suggested_patches.setdefault(world_path.name, []).append({
                            "level_id": level_id,
                            "wave_index": idx,
                            "status": status,
                            "reason": reason,
                            "wave": wave,
                        })
        if printed_world:
            print()

    print(f"Wave counts by status: {wave_summary}")
    print(f"Total hard issues: {issues}, notes-only: {notes_count}")
    if issues:
        out_file = REPO / "tools" / "audit_waves_report.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(suggested_patches, f, indent=2, ensure_ascii=False)
        print(f"Detailed report written to {out_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
