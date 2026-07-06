import json, math, os

ROOT = r"C:\Tafor\Projet\pewpewloot"
SPAWN_STOP = 5.0

with open(os.path.join(ROOT, "data", "enemies.json"), encoding="utf-8") as f:
    enemies_data = json.load(f)
# enemies.json only has forest enemies (5 archetypes). Scores are reused across worlds since enemy_id is the same name.
ENEMY_SCORE = {e["id"]: e["score"] for e in enemies_data["enemies"]}
# swarmer=10 fighter=25 tank=50 artillery=40 elite=100

with open(os.path.join(ROOT, "data", "bosses.json"), encoding="utf-8") as f:
    bosses_data = json.load(f)
BOSS_SCORE = {b["id"]: b["score"] for b in bosses_data["bosses"]}

with open(os.path.join(ROOT, "data", "game.json"), encoding="utf-8") as f:
    game = json.load(f)
gp = game["gameplay"]
DENS_MULT = gp.get("enemy_density_multiplier", 1.0)
DENS_CAP = gp.get("enemy_density_max_per_wave", 0)
SWARM_DEFAULT = gp.get("swarm", {}).get("default_count", 35)
TANK_DEFAULT_INTERVAL = gp.get("tank_wave", {}).get("default_interval_sec", 9.0)

def compute_enemy_count(interval, force_duration, max_spawns):
    spawn_window = max(0.1, force_duration - SPAWN_STOP)
    safe_interval = max(0.05, interval)
    base_count = max(1, math.ceil(spawn_window / safe_interval))
    count = max(1, math.ceil(base_count * DENS_MULT))
    max_count = max(1, max_spawns)
    if DENS_CAP > 0:
        max_count = min(max_count, DENS_CAP)
    return min(count, max_count)

def compute_tank_count(interval, force_duration):
    spawn_window = max(0.1, force_duration - SPAWN_STOP)
    return max(1, math.ceil(spawn_window / max(0.1, interval)))

def compute_artillery_count(wave, world_default):
    rows = max(1, int(wave.get("rows", 3)))  # default artillery_rows = 3
    requested = max(rows, int(wave.get("count", world_default)))
    count = math.ceil(requested / rows) * rows
    return count

def analyze_level(level, world_defaults):
    force_duration = world_defaults.get("force_duration_sec", 20.0)
    max_spawns = world_defaults.get("enemy_max_spawns_per_wave", 160)
    artillery_default = world_defaults.get("artillery_count", 18)
    artillery_rows = world_defaults.get("artillery_rows", 3)
    target_interval = world_defaults.get("enemy_target_interval_sec", 1.0)

    enemy_counts = {}  # id -> count
    for wave in level.get("waves", []):
        wtype = wave.get("type", "enemy")
        if wtype == "obstacle" or wtype == "path_trial":
            continue
        eid = wave.get("enemy_id", "")
        if not eid:
            continue
        if wtype == "swarm":
            c = max(1, int(wave.get("count", SWARM_DEFAULT)))
        elif wtype == "tank":
            interval = max(0.1, float(wave.get("interval", TANK_DEFAULT_INTERVAL)))
            c = max(1, int(wave.get("count", compute_tank_count(interval, force_duration))))
        elif wtype == "artillery":
            rows = max(1, int(wave.get("rows", artillery_rows)))
            requested = max(rows, int(wave.get("count", artillery_default)))
            c = math.ceil(requested / rows) * rows
        else:
            interval = max(0.05, float(wave.get("interval", target_interval)))
            c = compute_enemy_count(interval, force_duration, max_spawns)
        enemy_counts[eid] = enemy_counts.get(eid, 0) + c
    return enemy_counts

print("# Score baseline par level\n")
world_totals = {}
for i in range(1, 10):
    path = os.path.join(ROOT, "data", "worlds", f"world_{i}.json")
    with open(path, encoding="utf-8") as f:
        world = json.load(f)
    defaults = world.get("wave_runtime_defaults", {})
    print(f"\n## World {i}: {world.get('name','')}\n")
    print(f"(force_duration={defaults.get('force_duration_sec')}, max_spawns={defaults.get('enemy_max_spawns_per_wave')}, target_interval={defaults.get('enemy_target_interval_sec')}, artillery_count={defaults.get('artillery_count')})\n")
    print("| Niveau | Enemies (id x count) | Total ennemis | Score ennemis | Boss (score) | Total niveau | Cumulé |")
    print("|---|---|---:|---:|---:|---:|---:|")
    cum = 0
    grand_total = 0
    for lvl in world["levels"]:
        counts = analyze_level(lvl, defaults)
        enemy_breakdown = ", ".join(f"{eid}x{c}" for eid,c in counts.items())
        n_enemies = sum(counts.values())
        enemy_score = sum(c * ENEMY_SCORE.get(eid, 0) for eid,c in counts.items())
        boss_id = lvl.get("boss_id", "")
        boss_score = BOSS_SCORE.get(boss_id, 0) if boss_id else 0
        level_total = enemy_score + boss_score
        cum += level_total
        boss_repr = f"{boss_id} ({boss_score})" if boss_id else "-"
        print(f"| lvl_{lvl.get('index','?')} ({lvl.get('name','')}) | {enemy_breakdown} | {n_enemies} | {enemy_score} | {boss_repr} | {level_total} | {cum} |")
        grand_total = cum
    world_totals[i] = grand_total
    print(f"\n**Total World {i} : {grand_total}**\n")

print("\n## Récap: score baseline par world (somme des 6 niveaux)\n")
print("| World | Total baseline |")
print("|---|---:|")
for i, t in world_totals.items():
    print(f"| World {i} | {t} |")
