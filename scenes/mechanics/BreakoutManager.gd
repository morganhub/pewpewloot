extends Node2D

## BreakoutManager — Orchestre une vague "breakout" :
## le vaisseau joueur devient une raquette en bas (mode pong reutilise) et
## renvoie une ou plusieurs balles vers un mur de briques en haut de l'ecran.
## Brique detruite = score + chance de cristal ; mur nettoye avant le timer =
## pluie de cristaux + fin anticipee ; DERNIERE balle perdue en bas = degats en
## % des HP max puis resserve (les balles multiball supplementaires sont
## gratuites). Duree limitee, compte a rebours seul au HUD.
## Collisions balle/raquette/briques en manuel (cercle vs AABB, normales de
## coin incluses) — pas de physics engine, comme le pong.
##
## BONUS TOMBANTS (data : bonus_pool[]) : des briques speciales "bonus" (asset
## de brique dedie par bonus) lachent a leur destruction une capsule ronde
## (asset dedie) qui tombe avec la gravite — l'ATTRAPER AVEC LA RAQUETTE active
## l'effet, la manquer la perd :
## - multiball : +2 balles (cap multiball_max_balls ; degats a la derniere
##   balle seulement).
## - laser : la raquette tire des missiles vers le haut pendant duration_sec
##   (un missile = -1 HP de brique, les blindees l'arretent sans degat).
## - fireball : la balle DETRUIT sans rebondir (perce) pendant duration_sec —
##   les blindees font toujours rebondir.
## - paddle_xl / paddle_xs (piege) : largeur de raquette x scale_mult
##   (overlays hitbox pattern pong).
## - net : barriere electrique 1 charge sous la raquette (visuel shield_orb
##   pong — sinusoide multicouches additive).
## - slow_ball : vitesse des balles x speed_mult pendant duration_sec.
## TYPES DE BRIQUES (kind) : normal, bonus, armored (indestructible, exclue du
## clear), mystery (« ? » : effet aleatoire), bomb (detruit ses 8 voisines,
## chainable), boss (geante 3x2 cellules, gros HP, pluie de cristaux).
## GENERATEUR DE TABLEAUX (board_style: "patterns") : masque de cellules a
## motifs geometriques symetriques (diamond/ring/checker/pyramid/cross/frame/
## hourglass/arrow/stripes/zigzag), 8-16 rangees, remplissage partiel garanti
## dans [pattern_fill_min, pattern_fill_max]. Story = grille pleine (defaut).
## EVENEMENTS : pluie de debris (briques qui lachent des eclats a esquiver),
## rangee surprise (le mur descend d'un cran + nouvelle rangee, telegraphie),
## balle doree (cristal garanti par brique), tempete (courbure laterale
## telegraphee), sauvetage (la derniere balle perdue retombe une fois au
## ralenti — la rattraper annule les degats).
## Tous les assets et reglages dans wave_types.json > breakout (PH proceduraux
## si vides).

signal finished

enum State { INTRO, SERVE, PLAY, DONE }

# Anti-tunneling: cap the ball integration step on long frames.
const MAX_BALL_STEP_SEC: float = 1.0 / 30.0
const BRICK_SHADER: Shader = preload("res://scenes/mechanics/brick_rounded.gdshader")

var _config: Dictionary = {}
var _cfg: Dictionary = {}
var _player: Node2D = null
var _hud: Node = null
var _game: Node = null

var _state: int = State.INTRO
var _state_timer: float = 0.0
var _duration: float = 45.0
var _elapsed: float = 0.0

# Balles (mouvement manuel, multiball) : { "node": Node2D, "vel": Vector2,
# "speed": float, "rescue": bool (2e chance au ralenti, teinte fantome) }.
var _balls: Array = []
var _ball_radius: float = 14.0
var _ball_base_speed: float = 460.0
var _ball_speed_max: float = 900.0
var _ball_speed_increase_hit: float = 12.0
var _ball_speed_increase_brick: float = 4.0
var _max_bounce_angle_deg: float = 55.0
var _wall_margin: float = 10.0
var _serve_delay: float = 0.8
var _serve_angle_max_deg: float = 35.0

# Player paddle: manual AABB around _player.global_position (pong mode).
var _player_half_extents: Vector2 = Vector2(96.0, 16.0)

# Brick wall. Entries: { "node": Node2D, "rect": Rect2, "hp": int,
# "max_hp": int, "tint": Color, "kind": String, "bonus_def": Dictionary,
# "doomed": bool }
var _bricks: Array = []
var _brick_size: Vector2 = Vector2(96.0, 40.0)
var _brick_spacing: float = 5.0
var _grid_bottom_y: float = 0.0
var _brick_material: ShaderMaterial = null
# Compteur des briques DESTRUCTIBLES (les blindees n'y sont jamais) :
# clear du mur quand il tombe a 0.
var _destructible_count: int = 0
# Kills differes (chaines de bombes) : { "brick": Dictionary, "delay": float }.
var _pending_kills: Array = []

var _damage_percent: float = 0.15
var _crystal_brick_chance: float = 0.18
var _crystals_on_clear: int = 6
var _brick_flash_sec: float = 0.1
var _brick_score: int = 10
var _reward_mult: float = 1.0

# --- Bonus tombants ---
var _bonus_pool: Array = []
# Capsules en chute : { "node": Node2D, "pos": Vector2, "def": Dictionary }.
var _drops: Array = []
var _bonus_fall_speed: float = 270.0
var _bonus_drop_radius: float = 30.0
# Effets actifs (timers reels).
var _multiball_max: int = 8
var _laser_time: float = 0.0
var _laser_fire_timer: float = 0.0
var _missiles: Array = [] # { "node": Node2D, "pos": Vector2 }
var _fireball_time: float = 0.0
var _xl_time: float = 0.0
var _xl_scale: float = 1.5
var _xs_time: float = 0.0
var _xs_scale: float = 0.5
var _paddle_overlay: Polygon2D = null
var _net_charges: int = 0
var _net_lines: Array = []
var _net_material: CanvasItemMaterial = null
var _slow_time: float = 0.0
var _slow_mult: float = 0.8

# --- Evenements ---
var _golden_time: float = 0.0
var _golden_timer: float = 0.0
var _storm_time: float = 0.0
var _storm_pending: float = 0.0
var _storm_timer: float = 0.0
var _storm_dir: int = 1
var _storm_arrow: Label = null
var _debris: Array = [] # { "node": Node2D, "pos": Vector2 }
var _debris_invuln: float = 0.0
var _rescue_cooldown: float = 0.0
var _surprise_pending: float = 0.0
var _surprise_timer: float = 0.0
var _surprise_done: bool = false
var _event_banner: Label = null
var _banner_time: float = 0.0
# Mur coulissant : offset X sinusoidal global.
var _wall_slide_enabled: bool = false
var _slide_phase: float = 0.0
var _slide_offset: float = 0.0

var _countdown_label: Label = null
var _finished_emitted: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(config: Dictionary, player_ref: Node2D, hud_ref: Node) -> void:
	_config = config.duplicate(true)
	_player = player_ref
	_hud = hud_ref
	_game = get_tree().get_first_node_in_group("game_controller")
	_cfg = DataManager.get_wave_type_config("breakout") if DataManager else {}

	# Per-wave overrides (world_x.json) take precedence over global defaults.
	_duration = maxf(1.0, float(_config.get("duration", _cfg.get("duration_sec_default", 45.0))))
	_ball_radius = maxf(4.0, float(_cfg.get("ball_radius_px", 14.0)))
	_ball_base_speed = maxf(60.0, float(_config.get("ball_speed_px_sec", _cfg.get("ball_speed_px_sec_default", 460.0))))
	_ball_speed_max = maxf(_ball_base_speed, float(_cfg.get("ball_speed_max_px_sec", 900.0)))
	_ball_speed_increase_hit = maxf(0.0, float(_cfg.get("ball_speed_increase_per_hit", 12.0)))
	_ball_speed_increase_brick = maxf(0.0, float(_cfg.get("ball_speed_increase_per_brick", 4.0)))
	_max_bounce_angle_deg = clampf(float(_cfg.get("ball_max_bounce_angle_deg", 55.0)), 10.0, 80.0)
	_wall_margin = maxf(0.0, float(_cfg.get("wall_margin_px", 10.0)))
	_serve_delay = maxf(0.1, float(_cfg.get("serve_delay_sec", 0.8)))
	_serve_angle_max_deg = clampf(float(_cfg.get("serve_angle_max_deg", 35.0)), 0.0, 60.0)

	_player_half_extents = Vector2(
		maxf(16.0, float(_cfg.get("player_paddle_half_width_px", 96.0))),
		maxf(6.0, float(_cfg.get("player_paddle_half_height_px", 16.0)))
	)

	_damage_percent = clampf(float(_get_conf("damage_percent_per_ball_lost", 0.15)), 0.0, 1.0)
	_crystal_brick_chance = clampf(float(_get_conf("crystal_brick_chance", 0.18)), 0.0, 1.0)
	_crystals_on_clear = maxi(0, int(_get_conf("crystals_on_clear", 6)))
	_brick_flash_sec = maxf(0.02, float(_cfg.get("brick_hp_flash_sec", 0.1)))
	_brick_score = maxi(0, int(_get_conf("brick_score", 10)))
	_reward_mult = maxf(0.0, float(_get_conf("reward_multiplier", _cfg.get("reward_multiplier_default", 1.0))))

	# Bonus tombants + effets.
	var pool_v: Variant = _get_conf("bonus_pool", [])
	_bonus_pool = (pool_v as Array).duplicate(true) if pool_v is Array else []
	_bonus_fall_speed = maxf(60.0, float(_get_conf("bonus_fall_speed_px_sec", 270.0)))
	_bonus_drop_radius = maxf(10.0, float(_get_conf("bonus_drop_radius_px", 30.0)))
	_multiball_max = clampi(int(_get_conf("multiball_max_balls", 8)), 1, 24)

	# Evenements (off par defaut : chances a 0 dans wave_types.json).
	_golden_timer = maxf(3.0, float(_get_conf("golden_interval_sec", 20.0)))
	_storm_timer = maxf(3.0, float(_get_conf("storm_interval_sec", 25.0)))
	_surprise_timer = maxf(3.0, float(_get_conf("surprise_row_interval_sec", 0.0)))
	_wall_slide_enabled = bool(_get_conf("wall_slide_enabled", false))

	_begin_player_mode()
	_build_brick_grid()
	_spawn_ball(Vector2.ZERO)
	_ensure_countdown_label()

	_elapsed = 0.0
	_state = State.INTRO
	_state_timer = maxf(0.05, float(_cfg.get("intro_tween_sec", 0.6)))
	set_process(true)

## Per-wave override (world_X.json / freemode base_wave) > type defaults.
func _get_conf(key: String, fallback: Variant) -> Variant:
	return _config.get(key, _cfg.get(key, fallback))

## Mode libre "continuous" : la difficulté de la partie EN COURS est re-scalée
## au changement de level — balles et mur préservés (aucun re-service). Les
## clés de génération (rows, board_*, chances) s'appliquent au prochain tableau
## (le manager est recréé au clear, itération naturelle).
func update_free_mode_config(cfg: Dictionary) -> void:
	_ball_base_speed = maxf(60.0, float(cfg.get("ball_speed_px_sec", _ball_base_speed)))
	_ball_speed_max = maxf(_ball_base_speed, float(_cfg.get("ball_speed_max_px_sec", 900.0)))
	var floor_speed: float = _ball_base_speed * _speed_mult()
	for ball_v in _balls:
		var ball: Dictionary = ball_v as Dictionary
		if float(ball.get("speed", 0.0)) < floor_speed:
			ball["speed"] = floor_speed
			var vel: Vector2 = ball.get("vel", Vector2.ZERO)
			if vel != Vector2.ZERO:
				ball["vel"] = vel.normalized() * floor_speed
	_damage_percent = clampf(float(cfg.get("damage_percent_per_ball_lost", _damage_percent)), 0.0, 1.0)

func _begin_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("begin_pong"):
		# Reuses the pong paddle mode: Y locked at the paddle line, visual squash.
		var merged: Dictionary = _cfg.duplicate(true)
		for key in _config.keys():
			merged[key] = _config[key]
		_player.call("begin_pong", merged)

func _restore_player_mode() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("end_pong"):
		_player.call("end_pong")

# =============================================================================
# BRICK WALL — construction (grille pleine OU tableau a motifs)
# =============================================================================

func _build_brick_grid() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var side_margin: float = maxf(4.0, float(_cfg.get("grid_side_margin_px", 26.0)))
	_brick_spacing = clampf(float(_cfg.get("brick_spacing_px", 5.0)), 0.0, 24.0)
	var patterns_mode: bool = str(_get_conf("board_style", "full")) == "patterns"
	var rows: int
	if patterns_mode:
		var rows_min: int = clampi(int(_get_conf("board_rows_min", 8)), 1, 16)
		var rows_max: int = clampi(int(_get_conf("board_rows_max", 16)), rows_min, 16)
		rows = randi_range(rows_min, rows_max)
	else:
		rows = clampi(int(_config.get("rows", _cfg.get("rows_default", 5))), 1, 16)
	var cols: int = clampi(int(_config.get("cols", _cfg.get("cols_default", 6))), 2, 12)
	var brick_h: float = maxf(12.0, float(_cfg.get("brick_height_px", 42.0)))
	var usable_w: float = viewport_size.x - side_margin * 2.0
	var brick_w: float = maxf(16.0, (usable_w - float(cols - 1) * _brick_spacing) / float(cols))
	_brick_size = Vector2(brick_w, brick_h)
	var top_y: float = viewport_size.y * clampf(float(_cfg.get("grid_top_ratio", 0.12)), 0.05, 0.5)

	# One shared material for the whole wall: same size for every brick.
	_brick_material = _make_brick_material(_brick_size)

	var grid_root := Node2D.new()
	grid_root.name = "BrickGrid"
	grid_root.z_as_relative = false
	grid_root.z_index = 10
	add_child(grid_root)

	# Masque de cellules : motifs geometriques en "patterns", plein sinon.
	var mask: Array = _generate_board_mask(rows, cols) if patterns_mode \
		else _full_board_mask(rows, cols)
	# Types speciaux distribues sur les cellules remplies.
	var kinds: Array = _assign_brick_kinds(mask, rows, cols)

	var row_hp: Array = _resolve_row_hp(rows)
	var assets: Array = _resolve_brick_assets()
	var tints_v: Variant = _cfg.get("row_tints", [])
	var tints: Array = (tints_v as Array) if tints_v is Array else []

	for r in range(rows):
		var tex: Texture2D = _resolve_brick_texture(assets, r)
		var tint: Color = Color.WHITE
		if not tints.is_empty():
			tint = Color(str(tints[r % tints.size()]))
		var hp: int = maxi(1, int(row_hp[r]))
		for c in range(cols):
			var kind_v: Variant = (kinds[r] as Array)[c]
			if kind_v == null:
				continue
			var kind: String = str(kind_v)
			if kind == "boss_part":
				continue # cellule recouverte par la brique boss (creee a part)
			var center := Vector2(
				side_margin + (brick_w + _brick_spacing) * float(c) + brick_w * 0.5,
				top_y + (brick_h + _brick_spacing) * float(r) + brick_h * 0.5
			)
			if kind == "boss":
				_create_boss_brick(grid_root, center, r, c)
				continue
			_create_brick(grid_root, center, _brick_size, hp, tex, tint, kind, _pick_bonus_def() if kind == "bonus" else {})
	_grid_bottom_y = top_y + float(rows) * (brick_h + _brick_spacing)

func _make_brick_material(size: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = BRICK_SHADER
	mat.set_shader_parameter("rect_size", size)
	mat.set_shader_parameter("radius_px", clampf(float(_cfg.get("brick_corner_radius_px", 7.0)), 0.0, minf(size.x, size.y) * 0.5))
	return mat

func _full_board_mask(rows: int, cols: int) -> Array:
	var mask: Array = []
	for r in range(rows):
		var row: Array = []
		row.resize(cols)
		row.fill(true)
		mask.append(row)
	return mask

## Masque a motifs geometriques : 1-2 primitives symetriques (miroir vertical)
## + bruit, remplissage garanti dans [pattern_fill_min, pattern_fill_max]
## (re-tirage, fallback plein).
func _generate_board_mask(rows: int, cols: int) -> Array:
	var fill_min: float = clampf(float(_get_conf("pattern_fill_min", 0.30)), 0.05, 0.95)
	var fill_max: float = clampf(float(_get_conf("pattern_fill_max", 0.75)), fill_min, 1.0)
	var noise: float = clampf(float(_get_conf("pattern_noise", 0.05)), 0.0, 0.3)
	for _attempt in range(8):
		var primary: int = randi_range(0, 9)
		var use_second: bool = randf() < 0.5
		var secondary: int = randi_range(0, 9)
		var subtract: bool = randf() < 0.4
		var mask: Array = []
		var filled: int = 0
		for r in range(rows):
			var row: Array = []
			row.resize(cols)
			row.fill(false)
			mask.append(row)
		# Genere la moitie gauche (+ colonne centrale) puis miroir -> symetrie
		# garantie meme apres le bruit.
		var half_cols: int = int(ceil(float(cols) / 2.0))
		for r in range(rows):
			for c in range(half_cols):
				var cell: bool = _pattern_cell(primary, r, c, rows, cols)
				if use_second:
					var second: bool = _pattern_cell(secondary, r, c, rows, cols)
					cell = (cell and not second) if subtract else (cell or second)
				if noise > 0.0 and randf() < noise:
					cell = not cell
				(mask[r] as Array)[c] = cell
				(mask[r] as Array)[cols - 1 - c] = cell
		for r in range(rows):
			for c in range(cols):
				if bool((mask[r] as Array)[c]):
					filled += 1
		var ratio: float = float(filled) / float(rows * cols)
		if filled > 0 and ratio >= fill_min and ratio <= fill_max:
			return mask
	return _full_board_mask(rows, cols)

## Une primitive = un predicat cellule (coordonnees normalisees autour du
## centre). Toutes lisibles en silhouette une fois symetrisees.
func _pattern_cell(pattern_id: int, r: int, c: int, rows: int, cols: int) -> bool:
	var hr: float = maxf(1.0, float(rows - 1) * 0.5)
	var hc: float = maxf(1.0, float(cols - 1) * 0.5)
	var dr: float = (float(r) - hr) / hr # -1..1 haut->bas
	var dc: float = (float(c) - hc) / hc # -1..1 gauche->droite
	match pattern_id:
		0: # diamond
			return absf(dr) + absf(dc) <= 1.05
		1: # ring
			var d: float = sqrt(dr * dr + dc * dc)
			return d >= 0.45 and d <= 1.05
		2: # checker (damier 2x2)
			return ((r / 2) + (c / 2)) % 2 == 0
		3: # pyramid (triangle qui s'elargit vers le bas)
			return absf(dc) <= (dr + 1.0) * 0.55
		4: # zigzag (chevrons horizontaux)
			return absf(fposmod(float(c) + float(r) * 1.5, 6.0) - 3.0) < 1.6
		5: # cross (croix pleine)
			return absf(dc) <= 0.34 or absf(dr) <= 0.34
		6: # frame (cadre)
			return r < 2 or r >= rows - 2 or c < 1 or c >= cols - 1
		7: # hourglass (deux triangles tete-beche)
			return absf(dc) >= absf(dr) * 0.15 and absf(dc) <= absf(dr) * 1.1 + 0.15
		8: # arrow (fleche vers le bas : triangle + tige)
			return (dr <= 0.1 and absf(dc) <= (dr + 1.0) * 0.6) or (dr > 0.1 and absf(dc) <= 0.25)
		_: # stripes (colonnes verticales)
			return (c % 3) != 2

## Distribue les kinds sur les cellules remplies. Retourne rows x cols :
## null = vide, "normal"/"bonus"/"armored"/"mystery"/"bomb"/"boss"/"boss_part".
func _assign_brick_kinds(mask: Array, rows: int, cols: int) -> Array:
	var kinds: Array = []
	var filled_cells: Array = [] # Vector2i(r, c)
	var bottom_filled_row: int = -1
	for r in range(rows):
		var row: Array = []
		row.resize(cols)
		row.fill(null)
		kinds.append(row)
		for c in range(cols):
			if bool((mask[r] as Array)[c]):
				(kinds[r] as Array)[c] = "normal"
				filled_cells.append(Vector2i(r, c))
				bottom_filled_row = maxi(bottom_filled_row, r)
	if filled_cells.is_empty():
		return kinds

	# Boss d'abord (il reserve une zone 3x2 de cellules remplies).
	if randf() < clampf(float(_get_conf("boss_brick_chance", 0.0)), 0.0, 1.0) and rows >= 3 and cols >= 3:
		var spot: Vector2i = _find_boss_region(kinds, rows, cols)
		if spot.x >= 0:
			(kinds[spot.x] as Array)[spot.y] = "boss"
			for rr in range(spot.x, spot.x + 2):
				for cc in range(spot.y, spot.y + 3):
					if rr == spot.x and cc == spot.y:
						continue
					(kinds[rr] as Array)[cc] = "boss_part"

	# Briques bonus : compte garanti, cellules "normal" tirees au hasard.
	var bonus_count: int = _resolve_bonus_count()
	var candidates: Array = []
	for cell in filled_cells:
		if str((kinds[cell.x] as Array)[cell.y]) == "normal":
			candidates.append(cell)
	candidates.shuffle()
	if not _bonus_pool.is_empty():
		for i in range(mini(bonus_count, candidates.size())):
			var cell: Vector2i = candidates[i]
			(kinds[cell.x] as Array)[cell.y] = "bonus"

	# Blindees / mystere / bombe : chance par cellule "normal" restante.
	# Les blindees ne vont jamais sur la rangee remplie la plus basse
	# (anti-frustration) et laissent toujours >= 1 destructible.
	var armored_chance: float = clampf(float(_get_conf("armored_chance", 0.0)), 0.0, 1.0)
	var mystery_chance: float = clampf(float(_get_conf("mystery_chance", 0.0)), 0.0, 1.0)
	var bomb_chance: float = clampf(float(_get_conf("bomb_chance", 0.0)), 0.0, 1.0)
	var destructibles: int = 0
	for cell in filled_cells:
		if str((kinds[cell.x] as Array)[cell.y]) != "armored":
			destructibles += 1
	for cell in filled_cells:
		if str((kinds[cell.x] as Array)[cell.y]) != "normal":
			continue
		var roll: float = randf()
		if roll < armored_chance and cell.x != bottom_filled_row and destructibles > 1:
			(kinds[cell.x] as Array)[cell.y] = "armored"
			destructibles -= 1
		elif roll < armored_chance + mystery_chance:
			(kinds[cell.x] as Array)[cell.y] = "mystery"
		elif roll < armored_chance + mystery_chance + bomb_chance:
			(kinds[cell.x] as Array)[cell.y] = "bomb"
	return kinds

## Cherche une zone 3 (cols) x 2 (rows) entierement remplie, proche du centre.
## Retourne Vector2i(r, c) du coin haut-gauche, ou (-1, -1).
func _find_boss_region(kinds: Array, rows: int, cols: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist: float = INF
	var center := Vector2(float(rows) * 0.5, float(cols) * 0.5)
	for r in range(rows - 1):
		for c in range(cols - 2):
			var ok: bool = true
			for rr in range(r, r + 2):
				for cc in range(c, c + 3):
					if (kinds[rr] as Array)[cc] == null or str((kinds[rr] as Array)[cc]) != "normal":
						ok = false
						break
				if not ok:
					break
			if ok:
				var dist: float = Vector2(float(r) + 0.5, float(c) + 1.0).distance_squared_to(center)
				if dist < best_dist:
					best_dist = dist
					best = Vector2i(r, c)
	return best

func _resolve_bonus_count() -> int:
	if _config.has("bonus_brick_count") or _cfg.has("bonus_brick_count"):
		return maxi(0, int(_get_conf("bonus_brick_count", 0)))
	var lo: int = maxi(0, int(_get_conf("bonus_brick_count_min", 0)))
	var hi: int = maxi(lo, int(round(float(_get_conf("bonus_brick_count_max", lo)))))
	return randi_range(lo, hi)

func _pick_bonus_def() -> Dictionary:
	var total: float = 0.0
	for def_v in _bonus_pool:
		if def_v is Dictionary:
			total += maxf(0.0, float((def_v as Dictionary).get("weight", 0.0)))
	if total <= 0.0:
		return {}
	var roll: float = randf() * total
	for def_v in _bonus_pool:
		if not (def_v is Dictionary):
			continue
		roll -= maxf(0.0, float((def_v as Dictionary).get("weight", 0.0)))
		if roll <= 0.0:
			return def_v as Dictionary
	return {}

## Cree une brique standard (tous kinds sauf boss) et l'enregistre.
func _create_brick(parent: Node2D, center: Vector2, size: Vector2, hp: int, base_tex: Texture2D, tint: Color, kind: String, bonus_def: Dictionary) -> void:
	var tex: Texture2D = base_tex
	var label_text: String = ""
	match kind:
		"bonus":
			var brick_asset: String = str(bonus_def.get("brick_asset", ""))
			var bonus_tex: Texture2D = _texture_from_path(brick_asset)
			if bonus_tex != null:
				tex = bonus_tex
			else:
				tint = Color(str(bonus_def.get("tint", "#8FD3FF")))
				label_text = str(bonus_def.get("label", "?"))
		"armored":
			var armored_tex: Texture2D = _texture_from_path(str(_get_conf("armored_brick_asset", "")))
			if armored_tex != null:
				tex = armored_tex
			else:
				tint = Color(str(_get_conf("armored_tint", "#5A616E")))
			hp = 1 # jamais entame (dispatch _damage_brick), valeur sans effet
		"mystery":
			var mystery_tex: Texture2D = _texture_from_path(str(_get_conf("mystery_brick_asset", "")))
			if mystery_tex != null:
				tex = mystery_tex
			else:
				tint = Color(str(_get_conf("mystery_tint", "#C77CFF")))
				label_text = "?"
		"bomb":
			var bomb_tex: Texture2D = _texture_from_path(str(_get_conf("bomb_brick_asset", "")))
			if bomb_tex != null:
				tex = bomb_tex
			else:
				tint = Color(str(_get_conf("bomb_tint", "#FF7A4A")))
				label_text = "!"
		_:
			pass
	var brick_node := Node2D.new()
	brick_node.position = center
	var visual: Node2D = _make_brick_visual(tex, tint, size)
	brick_node.add_child(visual)
	if label_text != "":
		brick_node.add_child(_make_brick_label(label_text, size))
	parent.add_child(brick_node)
	var entry: Dictionary = {
		"node": brick_node,
		"rect": Rect2(center - size * 0.5, size),
		"hp": hp,
		"max_hp": hp,
		"tint": tint,
		"kind": kind,
		"bonus_def": bonus_def,
		"doomed": false
	}
	_bricks.append(entry)
	if kind != "armored":
		_destructible_count += 1
	_refresh_brick_tint(entry)

## Brique boss geante : 3 colonnes x 2 rangees de cellules, gros HP.
func _create_boss_brick(parent: Node2D, top_left_center: Vector2, _r: int, _c: int) -> void:
	var size := Vector2(
		_brick_size.x * 3.0 + _brick_spacing * 2.0,
		_brick_size.y * 2.0 + _brick_spacing)
	var center: Vector2 = top_left_center - _brick_size * 0.5 + size * 0.5
	var hp: int = maxi(2, int(_get_conf("boss_brick_hp", 24)))
	var tex: Texture2D = _texture_from_path(str(_get_conf("boss_brick_asset", "")))
	var tint := Color(str(_get_conf("boss_brick_tint", "#FFB05C")))
	var brick_node := Node2D.new()
	brick_node.position = center
	var visual: Node2D
	if tex != null:
		visual = _make_brick_visual_sized(tex, size, _make_brick_material(size))
	else:
		visual = _make_brick_polygon(tint, size)
	brick_node.add_child(visual)
	parent.add_child(brick_node)
	var entry: Dictionary = {
		"node": brick_node,
		"rect": Rect2(center - size * 0.5, size),
		"hp": hp,
		"max_hp": hp,
		"tint": tint if tex == null else Color.WHITE,
		"kind": "boss",
		"bonus_def": {},
		"doomed": false
	}
	_bricks.append(entry)
	_destructible_count += 1
	_refresh_brick_tint(entry)

func _make_brick_label(text: String, size: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(size.y * 0.62))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.size = size
	label.position = -size * 0.5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _resolve_row_hp(rows: int) -> Array:
	var src_v: Variant = _config.get("row_hp", _cfg.get("row_hp_default", [2, 2, 1, 1, 1]))
	var src: Array = (src_v as Array) if src_v is Array else [1]
	if src.is_empty():
		src = [1]
	var result: Array = []
	for r in range(rows):
		result.append(maxi(1, int(src[mini(r, src.size() - 1)])))
	return result

## Asset priority: per-wave "brick_assets" override > wave-type defaults.
func _resolve_brick_assets() -> Array:
	var wave_assets_v: Variant = _config.get("brick_assets", [])
	if wave_assets_v is Array and not (wave_assets_v as Array).is_empty():
		return wave_assets_v as Array
	var cfg_assets_v: Variant = _cfg.get("brick_assets", [])
	if cfg_assets_v is Array:
		return cfg_assets_v as Array
	return []

## One texture per row (the list cycles), for the classic tiered-wall look.
func _resolve_brick_texture(assets: Array, row: int) -> Texture2D:
	if assets.is_empty():
		return null
	return _texture_from_path(str(assets[row % assets.size()]))

func _texture_from_path(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is Texture2D:
		return res as Texture2D
	if res is SpriteFrames:
		var frames: SpriteFrames = res as SpriteFrames
		var names: PackedStringArray = frames.get_animation_names()
		if names.size() > 0 and frames.get_frame_count(names[0]) > 0:
			return frames.get_frame_texture(names[0], 0)
	return null

## "Cover" fill: the texture is cropped to the brick aspect ratio (centered)
## then scaled to the exact brick size — never stretched. The shared shader
## material rounds the corners.
func _make_brick_visual(tex: Texture2D, tint: Color, size: Vector2) -> Node2D:
	if tex != null:
		return _make_brick_visual_sized(tex, size, _brick_material)
	# Fallback: flat rounded rectangle (no asset configured).
	return _make_brick_polygon(tint, size)

func _make_brick_visual_sized(tex: Texture2D, size: Vector2, material: ShaderMaterial) -> Node2D:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		var brick_aspect: float = size.x / size.y
		var tex_aspect: float = tex_size.x / tex_size.y
		var region_size: Vector2
		if tex_aspect > brick_aspect:
			region_size = Vector2(tex_size.y * brick_aspect, tex_size.y)
		else:
			region_size = Vector2(tex_size.x, tex_size.x / brick_aspect)
		sprite.region_enabled = true
		sprite.region_rect = Rect2((tex_size - region_size) * 0.5, region_size)
		sprite.scale = size / region_size
	sprite.material = material
	return sprite

func _make_brick_polygon(tint: Color, size: Vector2) -> Polygon2D:
	var poly := Polygon2D.new()
	var half: Vector2 = size * 0.5
	var radius: float = clampf(float(_cfg.get("brick_corner_radius_px", 7.0)), 0.0, minf(half.x, half.y))
	var points := PackedVector2Array()
	var corners: Array = [
		[Vector2(half.x - radius, -half.y + radius), -PI * 0.5],
		[Vector2(half.x - radius, half.y - radius), 0.0],
		[Vector2(-half.x + radius, half.y - radius), PI * 0.5],
		[Vector2(-half.x + radius, -half.y + radius), PI]
	]
	var segments: int = 5
	for corner in corners:
		var corner_center: Vector2 = corner[0]
		var start_angle: float = corner[1]
		for i in range(segments + 1):
			var a: float = start_angle + (PI * 0.5) * float(i) / float(segments)
			points.append(corner_center + Vector2(cos(a), sin(a)) * radius)
	poly.polygon = points
	poly.color = tint if tint != Color.WHITE else Color("#8A93A6")
	return poly

func _refresh_brick_tint(brick: Dictionary) -> void:
	var node_v: Variant = brick.get("node", null)
	if not (node_v is Node2D) or not is_instance_valid(node_v):
		return
	if str(brick.get("kind", "normal")) == "armored":
		return # jamais entamee, teinte stable
	var hp: int = int(brick.get("hp", 1))
	var max_hp: int = maxi(1, int(brick.get("max_hp", 1)))
	var tint: Color = brick.get("tint", Color.WHITE)
	# Damaged bricks darken progressively (tiering stays readable).
	var brightness: float = lerpf(0.55, 1.0, float(hp) / float(max_hp))
	(node_v as Node2D).modulate = Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, 1.0)

# =============================================================================
# BALLES (multiball)
# =============================================================================

func _spawn_ball(vel: Vector2) -> Dictionary:
	var node := Node2D.new()
	node.name = "BreakoutBall"
	node.z_as_relative = false
	node.z_index = 11
	add_child(node)
	var ball_asset: String = str(_config.get("ball_asset", _cfg.get("ball_asset", "")))
	var visual: Node2D = _build_ball_sprite(ball_asset)
	if visual == null:
		visual = _build_ball_circle()
	node.add_child(visual)
	node.visible = false
	var ball: Dictionary = {
		"node": node,
		"vel": vel,
		"speed": maxf(vel.length(), _ball_base_speed * _speed_mult()) if vel != Vector2.ZERO else _ball_base_speed * _speed_mult(),
		"rescue": false
	}
	_balls.append(ball)
	return ball

func _free_ball(ball: Dictionary) -> void:
	var node_v: Variant = ball.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()

func _build_ball_sprite(asset_path: String) -> Node2D:
	if asset_path == "" or not ResourceLoader.exists(asset_path):
		return null
	var tex: Texture2D = _texture_from_path(asset_path)
	if tex == null:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		sprite.scale = (Vector2.ONE * _ball_radius * 2.0) / tex_size
	return sprite

func _build_ball_circle() -> Node2D:
	var circle := Polygon2D.new()
	var points := PackedVector2Array()
	var segments: int = 24
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(a), sin(a)) * _ball_radius)
	circle.polygon = points
	circle.color = Color(str(_cfg.get("ball_color", "#8FD3FF")))
	return circle

## Multiplicateur de vitesse global (slow_ball).
func _speed_mult() -> float:
	return _slow_mult if _slow_time > 0.0 else 1.0

## Re-scale les vitesses des balles EN VOL (slow_ball on/off).
func _rescale_ball_speeds(factor: float) -> void:
	for ball_v in _balls:
		var ball: Dictionary = ball_v as Dictionary
		var speed: float = maxf(40.0, float(ball.get("speed", _ball_base_speed)) * factor)
		ball["speed"] = speed
		var vel: Vector2 = ball.get("vel", Vector2.ZERO)
		if vel.length_squared() > 1.0:
			ball["vel"] = vel.normalized() * speed

## Teintes des balles selon les effets (priorite : rescue > fireball > golden).
func _refresh_ball_tints() -> void:
	var tint: Color = Color.WHITE
	if _fireball_time > 0.0:
		tint = Color(str(_get_conf("fireball_tint", "#FF9A4A")))
	elif _golden_time > 0.0:
		tint = Color(str(_get_conf("golden_tint", "#FFD866")))
	for ball_v in _balls:
		var ball: Dictionary = ball_v as Dictionary
		var node: Node2D = ball.get("node") as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if bool(ball.get("rescue", false)):
			node.modulate = Color(0.75, 0.85, 1.0, 0.6)
		else:
			node.modulate = tint

# =============================================================================
# MATCH LOOP
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.DONE:
		return
	# A dead player means the game-over flow took over: freeze the wave
	# without emitting finished.
	if _player == null or not is_instance_valid(_player):
		_state = State.DONE
		return
	_elapsed += minf(delta, 0.25)
	_update_countdown_label()
	match _state:
		State.INTRO:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_reset_ball()
		State.SERVE:
			_stick_ball_to_paddle()
			_update_side_systems(delta)
			_state_timer -= delta
			if _state_timer <= 0.0:
				_serve()
		State.PLAY:
			_update_balls(delta)
			_update_side_systems(delta)
			_update_events(delta)
	if _elapsed >= _duration:
		_finish()

## Systemes annexes communs SERVE/PLAY : drops, missiles, debris, effets,
## chaines de bombes, mur coulissant, bandeaux.
func _update_side_systems(delta: float) -> void:
	_update_drops(delta)
	_update_missiles(delta)
	_update_debris(delta)
	_update_effects(delta)
	_drain_pending_kills(delta)
	_update_wall_slide(delta)
	_update_banner(delta)

## Ball lost or wave start: a single ball sticks to the paddle for a breather.
func _reset_ball() -> void:
	for i in range(_balls.size() - 1, -1, -1):
		_free_ball(_balls[i])
	_balls.clear()
	var ball: Dictionary = _spawn_ball(Vector2.ZERO)
	ball["speed"] = _ball_base_speed * _speed_mult()
	_state = State.SERVE
	_state_timer = _serve_delay
	var node: Node2D = ball.get("node") as Node2D
	if node and is_instance_valid(node):
		node.visible = true
	_stick_ball_to_paddle()

func _stick_ball_to_paddle() -> void:
	if _balls.is_empty() or _player == null or not is_instance_valid(_player):
		return
	var node: Node2D = (_balls[0] as Dictionary).get("node") as Node2D
	if node and is_instance_valid(node):
		node.global_position = _player.global_position - Vector2(0.0, _paddle_half_extents().y + _ball_radius + 6.0)

func _serve() -> void:
	if _balls.is_empty():
		_reset_ball()
		return
	var ball: Dictionary = _balls[0]
	var angle: float = deg_to_rad(randf_range(-_serve_angle_max_deg, _serve_angle_max_deg))
	var speed: float = _ball_base_speed * _speed_mult()
	ball["speed"] = speed
	ball["vel"] = Vector2(sin(angle), -cos(angle)) * speed
	_state = State.PLAY

func _update_balls(delta: float) -> void:
	var remaining: float = minf(delta, 0.25)
	var step_cap: float = minf(MAX_BALL_STEP_SEC, (_ball_radius * 1.5) / maxf(1.0, _ball_speed_max))
	while remaining > 0.0 and _state == State.PLAY:
		var step: float = minf(remaining, step_cap)
		remaining -= step
		for i in range(_balls.size() - 1, -1, -1):
			if not _step_ball(_balls[i], step):
				_free_ball(_balls[i])
				_balls.remove_at(i)
		if _balls.is_empty() and _state == State.PLAY:
			_on_last_ball_lost()
			break

## Avance UNE balle d'un sous-pas. false = balle sortie en bas.
func _step_ball(ball: Dictionary, step: float) -> bool:
	var node: Node2D = ball.get("node") as Node2D
	if node == null or not is_instance_valid(node):
		return false
	var viewport_size: Vector2 = get_viewport_rect().size
	var vel: Vector2 = ball.get("vel", Vector2.ZERO)
	# Tempete : courbure laterale (nudge horizontal renormalise, recette pong).
	if _storm_time > 0.0 and vel.length_squared() > 1.0:
		var storm_strength: float = maxf(0.0, float(_get_conf("storm_strength_px_sec2", 760.0)))
		vel = (vel + Vector2(float(_storm_dir) * storm_strength * step, 0.0)).normalized() \
			* float(ball.get("speed", _ball_base_speed))
	var pos: Vector2 = node.global_position + vel * step

	# Side and top walls: reflect and re-seat to avoid double bounces.
	var left_x: float = _wall_margin + _ball_radius
	var right_x: float = viewport_size.x - _wall_margin - _ball_radius
	var top_y: float = _wall_margin + _ball_radius
	if pos.x <= left_x and vel.x < 0.0:
		pos.x = left_x
		vel.x = -vel.x
	elif pos.x >= right_x and vel.x > 0.0:
		pos.x = right_x
		vel.x = -vel.x
	if pos.y <= top_y and vel.y < 0.0:
		pos.y = top_y
		vel.y = -vel.y

	# Player paddle: only intercepts a ball travelling downward.
	if vel.y > 0.0 and _player and is_instance_valid(_player):
		var p: Vector2 = _player.global_position
		var half: Vector2 = _paddle_half_extents()
		if absf(pos.x - p.x) <= half.x + _ball_radius and absf(pos.y - p.y) <= half.y + _ball_radius:
			pos.y = p.y - half.y - _ball_radius
			ball["vel"] = vel
			vel = _bounce_off_paddle(ball, pos.x, p.x, half.x)
			# Sauvetage rattrape : la balle redevient normale (vitesse restauree),
			# sans degats.
			if bool(ball.get("rescue", false)):
				ball["rescue"] = false
				ball["speed"] = _ball_base_speed * _speed_mult()
				vel = vel.normalized() * float(ball["speed"])
				_show_floating(_translate_or("breakout_rescue", "SAVED!"), Color("#8FD3FF"), pos)

	# Filet de securite : barriere 1 charge sous la raquette.
	if _net_charges > 0 and vel.y > 0.0:
		var net_y: float = _net_line_y()
		if pos.y + _ball_radius >= net_y and pos.y - _ball_radius <= net_y:
			vel.y = -absf(vel.y)
			pos.y = net_y - _ball_radius
			_net_charges -= 1
			if VFXManager:
				VFXManager.spawn_impact(Vector2(pos.x, net_y), 16.0, self)
			if _net_charges <= 0:
				_free_net_lines()

	ball["vel"] = vel
	# Bricks: circle vs AABB with corner normals; one brick per substep.
	if pos.y - _ball_radius < _grid_bottom_y + 8.0:
		pos = _collide_with_bricks(ball, pos)

	node.global_position = pos

	# Ball lost below the screen.
	if pos.y - _ball_radius > viewport_size.y:
		return false
	return true

## Largeur effective de la raquette (XL x XS cumulables, pattern pong).
func _paddle_width_mult() -> float:
	var mult: float = 1.0
	if _xl_time > 0.0:
		mult *= _xl_scale
	if _xs_time > 0.0:
		mult *= _xs_scale
	return mult

func _paddle_half_extents() -> Vector2:
	return Vector2(_player_half_extents.x * _paddle_width_mult(), _player_half_extents.y)

func _bounce_off_paddle(ball: Dictionary, ball_x: float, paddle_x: float, half_width: float) -> Vector2:
	var offset: float = clampf((ball_x - paddle_x) / maxf(1.0, half_width), -1.0, 1.0)
	var angle: float = deg_to_rad(offset * _max_bounce_angle_deg)
	var speed: float = minf(float(ball.get("speed", _ball_base_speed)) + _ball_speed_increase_hit,
		_ball_speed_max * _speed_mult())
	ball["speed"] = speed
	return Vector2(sin(angle), -cos(angle)) * speed

func _collide_with_bricks(ball: Dictionary, pos: Vector2) -> Vector2:
	var radius_sq: float = _ball_radius * _ball_radius
	var vel: Vector2 = ball.get("vel", Vector2.ZERO)
	var fireball: bool = _fireball_time > 0.0
	for i in range(_bricks.size() - 1, -1, -1):
		if i >= _bricks.size():
			continue # le mur a pu etre vide par une cascade (fireball + bombes)
		var brick: Dictionary = _bricks[i]
		if bool(brick.get("doomed", false)):
			continue
		var rect: Rect2 = brick.get("rect", Rect2())
		var closest := Vector2(
			clampf(pos.x, rect.position.x, rect.end.x),
			clampf(pos.y, rect.position.y, rect.end.y)
		)
		var delta: Vector2 = pos - closest
		var dist_sq: float = delta.length_squared()
		if dist_sq > radius_sq:
			continue
		var kind: String = str(brick.get("kind", "normal"))
		# Balle enflammee : perce (detruit sans rebondir) — sauf les blindees.
		if fireball and kind != "armored":
			_kill_brick_at(i)
			continue
		var normal: Vector2
		if dist_sq > 0.0001:
			normal = delta.normalized()
		else:
			# Ball center inside the brick: push out along the least-penetrated axis.
			var center_delta: Vector2 = pos - rect.get_center()
			if absf(center_delta.x) / maxf(1.0, rect.size.x) > absf(center_delta.y) / maxf(1.0, rect.size.y):
				normal = Vector2(signf(center_delta.x), 0.0)
			else:
				normal = Vector2(0.0, signf(center_delta.y))
		if vel.dot(normal) < 0.0:
			vel = vel.bounce(normal)
		var speed: float = minf(float(ball.get("speed", _ball_base_speed)) + _ball_speed_increase_brick,
			_ball_speed_max * _speed_mult())
		ball["speed"] = speed
		ball["vel"] = vel.normalized() * speed
		pos = closest + normal * (_ball_radius + 0.5)
		_damage_brick(i)
		break
	return pos

# =============================================================================
# BRIQUES — degats, kinds, recompenses
# =============================================================================

func _damage_brick(index: int) -> void:
	var brick: Dictionary = _bricks[index]
	var kind: String = str(brick.get("kind", "normal"))
	var node_v: Variant = brick.get("node", null)
	if kind == "armored":
		# Indestructible : clink, aucun degat.
		if node_v is Node2D and is_instance_valid(node_v) and VFXManager:
			VFXManager.flash_sprite(node_v, Color(1.3, 1.3, 1.3), _brick_flash_sec)
		return
	brick["hp"] = int(brick.get("hp", 1)) - 1
	if int(brick["hp"]) <= 0:
		_kill_brick_at(index)
		return
	_refresh_brick_tint(brick)
	if node_v is Node2D and is_instance_valid(node_v) and VFXManager:
		VFXManager.flash_sprite(node_v, Color(1.6, 1.6, 1.6), _brick_flash_sec)

## Destruction d'une brique : recompenses + effets de kind + check de clear.
func _kill_brick_at(index: int) -> void:
	var brick: Dictionary = _bricks[index]
	var rect: Rect2 = brick.get("rect", Rect2())
	var center: Vector2 = rect.get_center()
	var kind: String = str(brick.get("kind", "normal"))
	_bricks.remove_at(index)
	var node_v: Variant = brick.get("node", null)
	if node_v is Node2D and is_instance_valid(node_v):
		(node_v as Node2D).queue_free()
	if kind != "armored":
		_destructible_count -= 1

	# Recompenses standard : score + cristal (garanti pendant la balle doree).
	if _game and is_instance_valid(_game):
		if _brick_score > 0 and _game.has_method("add_wave_bonus_score"):
			var pts: int = maxi(1, int(round(float(_brick_score) * _reward_mult)))
			if kind == "boss":
				pts = maxi(pts, int(round(float(_get_conf("boss_brick_score", 150)) * _reward_mult)))
			_game.call("add_wave_bonus_score", pts, center)
		var crystal_chance: float = 1.0 if _golden_time > 0.0 else _crystal_brick_chance
		if randf() <= crystal_chance and _game.has_method("spawn_reward_crystal_at"):
			_game.call("spawn_reward_crystal_at", center)
	if VFXManager:
		VFXManager.spawn_impact(center, 14.0, self)

	# Effets de kind.
	match kind:
		"bonus":
			_spawn_bonus_drop(brick.get("bonus_def", {}) as Dictionary, center)
		"mystery":
			_resolve_mystery(center)
		"bomb":
			_explode_neighbors(center)
		"boss":
			_on_boss_brick_killed(center)
		_:
			pass

	# Pluie de debris : chance sur toute destruction.
	if randf() < clampf(float(_get_conf("debris_chance", 0.0)), 0.0, 1.0):
		_spawn_debris(center)

	if _destructible_count <= 0:
		_on_wall_cleared()

## Bombe : condamne les 8 voisines (kills echelonnes, chainable). Les blindees
## resistent ; la brique boss encaisse bomb_boss_damage au lieu de mourir.
func _explode_neighbors(center: Vector2) -> void:
	var reach_x: float = (_brick_size.x + _brick_spacing) * 1.5
	var reach_y: float = (_brick_size.y + _brick_spacing) * 1.5
	var order: int = 0
	for brick_v in _bricks:
		var brick: Dictionary = brick_v as Dictionary
		if bool(brick.get("doomed", false)):
			continue
		var b_center: Vector2 = (brick.get("rect", Rect2()) as Rect2).get_center()
		if absf(b_center.x - center.x) > reach_x or absf(b_center.y - center.y) > reach_y:
			continue
		var kind: String = str(brick.get("kind", "normal"))
		if kind == "armored":
			continue
		if kind == "boss":
			brick["hp"] = int(brick.get("hp", 1)) - maxi(1, int(_get_conf("bomb_boss_damage", 3)))
			if int(brick["hp"]) > 0:
				_refresh_brick_tint(brick)
				continue
		brick["doomed"] = true
		order += 1
		_pending_kills.append({ "brick": brick, "delay": 0.06 * float(order) })

func _drain_pending_kills(delta: float) -> void:
	if _pending_kills.is_empty():
		return
	for i in range(_pending_kills.size() - 1, -1, -1):
		if i >= _pending_kills.size():
			continue # la liste a pu etre videe par un clear en cascade
		var entry: Dictionary = _pending_kills[i]
		entry["delay"] = float(entry.get("delay", 0.0)) - delta
		if float(entry["delay"]) > 0.0:
			continue
		_pending_kills.remove_at(i)
		var brick: Dictionary = entry.get("brick", {}) as Dictionary
		var idx: int = _bricks.find(brick)
		if idx >= 0:
			brick["doomed"] = false
			_kill_brick_at(idx)

## Brique mystere : effet aleatoire pondere (mystery_outcomes).
func _resolve_mystery(center: Vector2) -> void:
	var outcomes_v: Variant = _get_conf("mystery_outcomes", {"crystal": 40, "extra_ball": 20, "debris": 20, "nothing": 20})
	var outcomes: Dictionary = (outcomes_v as Dictionary) if outcomes_v is Dictionary else {}
	var total: float = 0.0
	for key in outcomes.keys():
		total += maxf(0.0, float(outcomes[key]))
	if total <= 0.0:
		return
	var roll: float = randf() * total
	for key in outcomes.keys():
		roll -= maxf(0.0, float(outcomes[key]))
		if roll > 0.0:
			continue
		match str(key):
			"crystal":
				if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
					_game.call("spawn_reward_crystal_at", center)
			"extra_ball":
				_add_extra_ball(center)
			"debris":
				_spawn_debris(center)
			_:
				pass
		return

func _on_boss_brick_killed(center: Vector2) -> void:
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystal_at"):
		for i in range(maxi(0, int(_get_conf("boss_brick_crystals", 5)))):
			var offset := Vector2(randf_range(-_brick_size.x, _brick_size.x), randf_range(-_brick_size.y, _brick_size.y))
			_game.call("spawn_reward_crystal_at", center + offset)
	if VFXManager:
		VFXManager.spawn_impact(center, 30.0, self)

## Derniere balle perdue : sauvetage (2e chance au ralenti) sinon degats + resserve.
func _on_last_ball_lost() -> void:
	var rescue_enabled: bool = bool(_get_conf("rescue_enabled", false))
	if rescue_enabled and _rescue_cooldown <= 0.0:
		_rescue_cooldown = maxf(1.0, float(_get_conf("rescue_cooldown_sec", 25.0)))
		var viewport_size: Vector2 = get_viewport_rect().size
		var speed: float = _ball_base_speed * _speed_mult() * clampf(float(_get_conf("rescue_speed_mult", 0.45)), 0.1, 1.0)
		var ball: Dictionary = _spawn_ball(Vector2.DOWN * speed)
		ball["speed"] = speed
		ball["rescue"] = true
		var node: Node2D = ball.get("node") as Node2D
		if node and is_instance_valid(node):
			node.visible = true
			node.global_position = Vector2(viewport_size.x * randf_range(0.3, 0.7), viewport_size.y * 0.45)
		_refresh_ball_tints()
		return
	if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
		var max_hp_v: Variant = _player.get("max_hp")
		var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
		# Standard damage path: shield absorbs first, then HP; die() below 0.
		var dmg: int = maxi(1, int(ceil(float(max_hp) * _damage_percent)))
		_player.call("take_damage", dmg)
	_reset_ball()

## Wall cleared before the timer: crystal rain and early finish. Les blindees
## restantes disparaissent avec le mur.
func _on_wall_cleared() -> void:
	for brick_v in _bricks:
		var node_v: Variant = (brick_v as Dictionary).get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).queue_free()
	_bricks.clear()
	_pending_kills.clear()
	if _game and is_instance_valid(_game) and _game.has_method("spawn_reward_crystals_from_top"):
		_game.call("spawn_reward_crystals_from_top", _crystals_on_clear)
	_finish()

# =============================================================================
# BONUS TOMBANTS (capsules attrapees par la raquette)
# =============================================================================

func _spawn_bonus_drop(def: Dictionary, at_pos: Vector2) -> void:
	if def.is_empty():
		return
	var node := Node2D.new()
	node.z_as_relative = false
	node.z_index = 12
	var tex: Texture2D = _texture_from_path(str(def.get("drop_asset", "")))
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = (Vector2.ONE * _bonus_drop_radius * 2.0) / tex_size
		node.add_child(sprite)
	else:
		# PH procedural : anneau colore + lettre (pattern powerups pong).
		var circle := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(20):
			var a: float = TAU * float(i) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * _bonus_drop_radius)
		circle.polygon = pts
		circle.color = Color(str(def.get("tint", "#8FD3FF")))
		node.add_child(circle)
		node.add_child(_make_brick_label(str(def.get("label", "?")), Vector2.ONE * _bonus_drop_radius * 2.0))
	node.global_position = at_pos
	add_child(node)
	_drops.append({ "node": node, "pos": at_pos, "def": def })

func _update_drops(delta: float) -> void:
	if _drops.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var p: Vector2 = _player.global_position if (_player and is_instance_valid(_player)) else Vector2(-9999, -9999)
	var half: Vector2 = _paddle_half_extents()
	for i in range(_drops.size() - 1, -1, -1):
		var drop: Dictionary = _drops[i]
		var pos: Vector2 = drop.get("pos", Vector2.ZERO)
		pos.y += _bonus_fall_speed * delta
		drop["pos"] = pos
		var node_v: Variant = drop.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			var node: Node2D = node_v as Node2D
			node.global_position = pos
			node.scale = Vector2.ONE * (1.0 + 0.08 * sin(_elapsed * 6.0))
		# Attrape par la raquette (AABB elargie du rayon de capsule).
		if absf(pos.x - p.x) <= half.x + _bonus_drop_radius and absf(pos.y - p.y) <= half.y + _bonus_drop_radius:
			var def: Dictionary = drop.get("def", {}) as Dictionary
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_drops.remove_at(i)
			_apply_bonus(def, pos)
			continue
		if pos.y - _bonus_drop_radius > viewport_size.y:
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_drops.remove_at(i)

func _apply_bonus(def: Dictionary, at_pos: Vector2) -> void:
	var duration: float = maxf(0.5, float(def.get("duration_sec", 10.0)))
	match str(def.get("id", "")):
		"multiball":
			for i in range(2):
				if _balls.size() < _multiball_max:
					_add_extra_ball(at_pos)
		"laser":
			_laser_time = maxf(_laser_time, duration)
			_laser_fire_timer = 0.0
		"fireball":
			_fireball_time = maxf(_fireball_time, duration)
		"paddle_xl":
			_xl_scale = maxf(1.1, float(def.get("scale_mult", 1.5)))
			_xl_time = maxf(_xl_time, duration)
			_refresh_paddle_overlay()
		"paddle_xs":
			_xs_scale = clampf(float(def.get("scale_mult", 0.5)), 0.1, 0.95)
			_xs_time = maxf(_xs_time, duration)
			_refresh_paddle_overlay()
		"net":
			_net_charges = 1
			_ensure_net_lines()
		"slow_ball":
			if _slow_time <= 0.0:
				_slow_mult = clampf(float(def.get("speed_mult", 0.8)), 0.3, 1.0)
				_rescale_ball_speeds(_slow_mult)
			_slow_time = maxf(_slow_time, duration)
		_:
			pass
	if VFXManager:
		VFXManager.spawn_impact(at_pos, 18.0, self)

## Clone une balle vivante (multiball / brique mystere). Sans balle en vol
## (SERVE), aucune creation — la capsule reste sans effet.
func _add_extra_ball(at_pos: Vector2) -> void:
	if _balls.size() >= _multiball_max or _state != State.PLAY:
		return
	var source: Dictionary = {}
	for ball_v in _balls:
		if not bool((ball_v as Dictionary).get("rescue", false)):
			source = ball_v as Dictionary
			break
	if source.is_empty():
		return
	var vel: Vector2 = source.get("vel", Vector2.UP * _ball_base_speed)
	var new_vel: Vector2 = vel.rotated(deg_to_rad(randf_range(-30.0, 30.0)))
	if new_vel.y > -40.0:
		new_vel = Vector2(new_vel.x, -absf(new_vel.y) - 60.0).normalized() * vel.length()
	var src_node: Node2D = source.get("node") as Node2D
	var spawn_pos: Vector2 = src_node.global_position if (src_node and is_instance_valid(src_node)) else at_pos
	var ball: Dictionary = _spawn_ball(new_vel.normalized() * float(source.get("speed", _ball_base_speed)))
	ball["speed"] = float(source.get("speed", _ball_base_speed))
	var node: Node2D = ball.get("node") as Node2D
	if node and is_instance_valid(node):
		node.visible = true
		node.global_position = spawn_pos

# =============================================================================
# EFFETS (timers reels) + MISSILES LASER + OVERLAY RAQUETTE + FILET
# =============================================================================

func _update_effects(delta: float) -> void:
	if _laser_time > 0.0:
		_laser_time -= delta
		_laser_fire_timer -= delta
		if _laser_fire_timer <= 0.0 and _laser_time > 0.0:
			_laser_fire_timer = maxf(0.1, float(_get_conf("laser_fire_interval_sec", 0.4)))
			_fire_laser_missile()
	if _fireball_time > 0.0:
		_fireball_time -= delta
	if _golden_time > 0.0:
		_golden_time -= delta
	if _xl_time > 0.0:
		_xl_time -= delta
		if _xl_time <= 0.0:
			_refresh_paddle_overlay()
	if _xs_time > 0.0:
		_xs_time -= delta
		if _xs_time <= 0.0:
			_refresh_paddle_overlay()
	if _slow_time > 0.0:
		_slow_time -= delta
		if _slow_time <= 0.0:
			_rescale_ball_speeds(1.0 / maxf(0.05, _slow_mult))
	if _storm_time > 0.0:
		_storm_time -= delta
		if _storm_time <= 0.0 and _storm_arrow and is_instance_valid(_storm_arrow):
			_storm_arrow.visible = false
	if _debris_invuln > 0.0:
		_debris_invuln -= delta
	if _rescue_cooldown > 0.0:
		_rescue_cooldown -= delta
	_refresh_ball_tints()
	if _paddle_overlay and is_instance_valid(_paddle_overlay) and _player and is_instance_valid(_player):
		_paddle_overlay.global_position = _player.global_position
	_animate_net()

func _fire_laser_missile() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var from: Vector2 = _player.global_position + Vector2(0.0, -20.0)
	var node := Node2D.new()
	node.z_as_relative = false
	node.z_index = 11
	var size_v: Variant = _get_conf("laser_missile_size_px", [8, 22])
	var missile_size := Vector2(8.0, 22.0)
	if size_v is Array and (size_v as Array).size() >= 2:
		missile_size = Vector2(float((size_v as Array)[0]), float((size_v as Array)[1]))
	var tex: Texture2D = _texture_from_path(str(_get_conf("laser_missile_asset", "")))
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = missile_size / tex_size
		node.add_child(sprite)
	else:
		var tri := Polygon2D.new()
		var half: Vector2 = missile_size * 0.5
		tri.polygon = PackedVector2Array([
			Vector2(0.0, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)
		])
		tri.color = Color(str(_get_conf("laser_missile_color", "#FF8A5C")))
		node.add_child(tri)
	node.global_position = from
	add_child(node)
	_missiles.append({ "node": node, "pos": from })

func _update_missiles(delta: float) -> void:
	if _missiles.is_empty():
		return
	var speed: float = maxf(120.0, float(_get_conf("laser_missile_speed_px_sec", 700.0)))
	for i in range(_missiles.size() - 1, -1, -1):
		var missile: Dictionary = _missiles[i]
		var pos: Vector2 = (missile.get("pos", Vector2.ZERO) as Vector2) + Vector2(0.0, -speed * delta)
		missile["pos"] = pos
		var node_v: Variant = missile.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).global_position = pos
		var consumed: bool = false
		for j in range(_bricks.size() - 1, -1, -1):
			var brick: Dictionary = _bricks[j]
			if bool(brick.get("doomed", false)):
				continue
			var rect: Rect2 = (brick.get("rect", Rect2()) as Rect2).grow(4.0)
			if not rect.has_point(pos):
				continue
			# -1 HP normal ; les blindees arretent le missile sans degat.
			_damage_brick(j)
			if VFXManager:
				VFXManager.spawn_impact(pos, 10.0, self)
			consumed = true
			break
		if consumed or pos.y < -40.0:
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_missiles.remove_at(i)

## Overlay de hitbox raquette (glow vert net > 1, rouge net < 1 — pattern pong).
func _refresh_paddle_overlay() -> void:
	if _paddle_overlay and is_instance_valid(_paddle_overlay):
		_paddle_overlay.queue_free()
	_paddle_overlay = null
	var net_mult: float = _paddle_width_mult()
	var color: Color
	if net_mult > 1.001:
		color = Color(0.5, 0.9, 0.55, 0.4)
	elif net_mult < 0.999:
		color = Color(str(_get_conf("xs_overlay_color", "#FF3D5A73")))
	else:
		return
	var overlay := Polygon2D.new()
	var half := Vector2(_player_half_extents.x * net_mult, _player_half_extents.y)
	overlay.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)
	])
	overlay.color = color
	overlay.z_as_relative = false
	overlay.z_index = 9
	add_child(overlay)
	if _player and is_instance_valid(_player):
		overlay.global_position = _player.global_position
	_paddle_overlay = overlay

## Filet : barriere electrique pleine largeur pres du bas (recette shield pong).
func _net_line_y() -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	return viewport_size.y - maxf(8.0, float(_get_conf("net_offset_from_bottom_px", 42.0)))

func _ensure_net_lines() -> void:
	if not _net_lines.is_empty():
		return
	if _net_material == null:
		_net_material = CanvasItemMaterial.new()
		_net_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var layers_v: Variant = _get_conf("net_line_layers", [])
	var layers: Array = (layers_v as Array) if layers_v is Array else []
	if layers.is_empty():
		layers = [
			{ "color": "#1E5DFF55", "width_px": 22.0, "additive": true },
			{ "color": "#3D8BFF88", "width_px": 12.0, "additive": true },
			{ "color": "#FFFFFF", "width_px": 3.0, "additive": false }
		]
	var idx: int = 0
	for layer_v in layers:
		if not (layer_v is Dictionary):
			continue
		var layer: Dictionary = layer_v as Dictionary
		var line := Line2D.new()
		line.width = maxf(1.0, float(layer.get("width_px", 8.0)))
		line.default_color = Color(str(layer.get("color", "#4FA8FF")))
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.z_as_relative = false
		line.z_index = 12 + idx
		if bool(layer.get("additive", true)):
			line.material = _net_material
		add_child(line)
		_net_lines.append(line)
		idx += 1

## Sinusoide defilante + jitter = arc electrique (meme recette que pong).
func _animate_net() -> void:
	if _net_lines.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var y0: float = _net_line_y()
	var segments: int = 24
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var x: float = lerpf(_wall_margin, viewport_size.x - _wall_margin, float(i) / float(segments))
		points.append(Vector2(x, y0 + sin(x * 0.045 + _elapsed * 7.0) * 5.0 + randf_range(-2.0, 2.0)))
	for line_v in _net_lines:
		if line_v is Line2D and is_instance_valid(line_v):
			(line_v as Line2D).points = points

func _free_net_lines() -> void:
	for line_v in _net_lines:
		if line_v is Line2D and is_instance_valid(line_v):
			(line_v as Line2D).queue_free()
	_net_lines.clear()

# =============================================================================
# EVENEMENTS (schedulers PLAY) + DEBRIS + RANGEE SURPRISE + MUR COULISSANT
# =============================================================================

func _update_events(delta: float) -> void:
	# Balle doree : intervalle + chance.
	var golden_chance: float = clampf(float(_get_conf("golden_chance", 0.0)), 0.0, 1.0)
	if golden_chance > 0.0:
		_golden_timer -= delta
		if _golden_timer <= 0.0:
			_golden_timer = maxf(3.0, float(_get_conf("golden_interval_sec", 20.0)))
			if randf() < golden_chance:
				_golden_time = maxf(1.0, float(_get_conf("golden_duration_sec", 5.0)))
	# Tempete : telegraphe puis courbure.
	var storm_chance: float = clampf(float(_get_conf("storm_chance", 0.0)), 0.0, 1.0)
	if _storm_pending > 0.0:
		_storm_pending -= delta
		if _storm_arrow and is_instance_valid(_storm_arrow):
			_storm_arrow.modulate.a = 0.5 + 0.5 * absf(sin(_elapsed * 9.0))
		if _storm_pending <= 0.0:
			_storm_time = maxf(1.0, float(_get_conf("storm_duration_sec", 6.0)))
	elif storm_chance > 0.0 and _storm_time <= 0.0:
		_storm_timer -= delta
		if _storm_timer <= 0.0:
			_storm_timer = maxf(3.0, float(_get_conf("storm_interval_sec", 25.0)))
			if randf() < storm_chance:
				_storm_dir = 1 if randf() < 0.5 else -1
				_storm_pending = maxf(0.2, float(_get_conf("storm_telegraph_sec", 1.0)))
				_show_storm_arrow()
	# Rangee surprise : one-shot au ratio (story) OU intervalle (libre).
	var surprise_chance: float = clampf(float(_get_conf("surprise_row_chance", 0.0)), 0.0, 1.0)
	if _surprise_pending > 0.0:
		_surprise_pending -= delta
		if _surprise_pending <= 0.0:
			_insert_surprise_row()
	elif surprise_chance > 0.0:
		var interval: float = float(_get_conf("surprise_row_interval_sec", 0.0))
		if interval > 0.0:
			_surprise_timer -= delta
			if _surprise_timer <= 0.0:
				_surprise_timer = interval
				if randf() < surprise_chance:
					_trigger_surprise_row()
		elif not _surprise_done and _elapsed >= _duration * clampf(float(_get_conf("surprise_row_time_ratio", 0.5)), 0.05, 0.95):
			_surprise_done = true
			if randf() < surprise_chance:
				_trigger_surprise_row()

func _trigger_surprise_row() -> void:
	# Jamais si le mur approche la raquette.
	var viewport_size: Vector2 = get_viewport_rect().size
	if _grid_bottom_y + _brick_size.y + _brick_spacing > viewport_size.y * clampf(float(_get_conf("surprise_row_max_bottom_ratio", 0.55)), 0.2, 0.9):
		return
	if _bricks.is_empty():
		return
	_surprise_pending = 1.0
	_show_banner(_translate_or("breakout_surprise_row", "REINFORCEMENTS!"), Color("#FF8A5C"))

## Le mur descend d'un cran, une nouvelle rangee spawn au niveau de l'ancienne
## rangee la plus haute.
func _insert_surprise_row() -> void:
	if _bricks.is_empty():
		return
	var step_y: float = _brick_size.y + _brick_spacing
	var min_top: float = INF
	for brick_v in _bricks:
		var rect: Rect2 = (brick_v as Dictionary).get("rect", Rect2())
		min_top = minf(min_top, rect.position.y)
	for brick_v in _bricks:
		var brick: Dictionary = brick_v as Dictionary
		var rect: Rect2 = brick.get("rect", Rect2())
		rect.position.y += step_y
		brick["rect"] = rect
		var node_v: Variant = brick.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).position.y += step_y
	_grid_bottom_y += step_y
	# Nouvelle rangee pleine largeur a l'emplacement libere.
	var grid_root: Node2D = get_node_or_null("BrickGrid") as Node2D
	if grid_root == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var side_margin: float = maxf(4.0, float(_cfg.get("grid_side_margin_px", 26.0)))
	var cols: int = clampi(int(_config.get("cols", _cfg.get("cols_default", 6))), 2, 12)
	var assets: Array = _resolve_brick_assets()
	var tex: Texture2D = _resolve_brick_texture(assets, 0)
	var row_hp: Array = _resolve_row_hp(1)
	var hp: int = maxi(1, int(row_hp[0]))
	var usable_w: float = viewport_size.x - side_margin * 2.0
	var brick_w: float = maxf(16.0, (usable_w - float(cols - 1) * _brick_spacing) / float(cols))
	for c in range(cols):
		var center := Vector2(
			side_margin + (brick_w + _brick_spacing) * float(c) + brick_w * 0.5 + _slide_offset,
			min_top + _brick_size.y * 0.5)
		_create_brick(grid_root, center, _brick_size, hp, tex, Color.WHITE, "normal", {})
	if VFXManager:
		VFXManager.spawn_impact(Vector2(viewport_size.x * 0.5, min_top), 22.0, self)

func _spawn_debris(at_pos: Vector2) -> void:
	var node := Node2D.new()
	node.z_as_relative = false
	node.z_index = 11
	var size: float = maxf(6.0, float(_get_conf("debris_size_px", 18.0)))
	var tex: Texture2D = _texture_from_path(str(_get_conf("debris_asset", "")))
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			sprite.scale = (Vector2.ONE * size * 2.0) / tex_size
		node.add_child(sprite)
	else:
		var shard := Polygon2D.new()
		shard.polygon = PackedVector2Array([
			Vector2(-size * 0.5, -size * 0.3), Vector2(size * 0.4, -size * 0.5),
			Vector2(size * 0.5, size * 0.4), Vector2(-size * 0.3, size * 0.5)
		])
		shard.color = Color(str(_get_conf("debris_color", "#B0A896")))
		node.add_child(shard)
	node.global_position = at_pos
	add_child(node)
	_debris.append({ "node": node, "pos": at_pos, "drift": randf_range(-40.0, 40.0) })

func _update_debris(delta: float) -> void:
	if _debris.is_empty():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var speed: float = maxf(60.0, float(_get_conf("debris_speed_px_sec", 300.0)))
	var p: Vector2 = _player.global_position if (_player and is_instance_valid(_player)) else Vector2(-9999, -9999)
	var half: Vector2 = _paddle_half_extents()
	for i in range(_debris.size() - 1, -1, -1):
		var debris: Dictionary = _debris[i]
		var pos: Vector2 = debris.get("pos", Vector2.ZERO)
		pos.y += speed * delta
		pos.x += float(debris.get("drift", 0.0)) * delta
		debris["pos"] = pos
		var node_v: Variant = debris.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			var node: Node2D = node_v as Node2D
			node.global_position = pos
			node.rotation += delta * 3.0
		var hit: bool = _debris_invuln <= 0.0 \
			and absf(pos.x - p.x) <= half.x + 10.0 and absf(pos.y - p.y) <= half.y + 10.0
		if hit:
			_debris_invuln = 0.8
			if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
				var max_hp_v: Variant = _player.get("max_hp")
				var max_hp: int = int(max_hp_v) if (max_hp_v is int or max_hp_v is float) else 100
				var pct: float = clampf(float(_get_conf("debris_damage_percent", 0.05)), 0.0, 1.0)
				_player.call("take_damage", maxi(1, int(ceil(float(max_hp) * pct))))
			if VFXManager:
				VFXManager.spawn_impact(pos, 14.0, self)
		if hit or pos.y > viewport_size.y + 40.0:
			if node_v is Node2D and is_instance_valid(node_v):
				(node_v as Node2D).queue_free()
			_debris.remove_at(i)

## Mur coulissant : offset X sinusoidal applique aux nodes ET aux rects.
func _update_wall_slide(delta: float) -> void:
	if not _wall_slide_enabled or _bricks.is_empty():
		return
	_slide_phase += delta * TAU * maxf(0.005, float(_get_conf("wall_slide_speed_hz", 0.05)))
	var amplitude: float = maxf(0.0, float(_get_conf("wall_slide_amplitude_px", 60.0)))
	var new_offset: float = sin(_slide_phase) * amplitude
	var shift: float = new_offset - _slide_offset
	if absf(shift) < 0.001:
		return
	_slide_offset = new_offset
	for brick_v in _bricks:
		var brick: Dictionary = brick_v as Dictionary
		var rect: Rect2 = brick.get("rect", Rect2())
		rect.position.x += shift
		brick["rect"] = rect
		var node_v: Variant = brick.get("node", null)
		if node_v is Node2D and is_instance_valid(node_v):
			(node_v as Node2D).position.x += shift

# =============================================================================
# BANDEAUX / TELEGRAPHIE / FLOATING
# =============================================================================

func _show_banner(text: String, color: Color) -> void:
	if _event_banner == null or not is_instance_valid(_event_banner):
		var viewport_size: Vector2 = get_viewport_rect().size
		_event_banner = Label.new()
		_event_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_event_banner.add_theme_font_size_override("font_size", 40)
		_event_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_event_banner.add_theme_constant_override("outline_size", 5)
		_event_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_event_banner.z_as_relative = false
		_event_banner.z_index = 55
		_event_banner.size = Vector2(viewport_size.x, 46.0)
		_event_banner.position = Vector2(0.0, viewport_size.y * 0.3)
		add_child(_event_banner)
	_event_banner.text = text
	_event_banner.add_theme_color_override("font_color", color)
	_event_banner.visible = true
	_banner_time = 1.2

func _update_banner(delta: float) -> void:
	if _banner_time <= 0.0:
		return
	_banner_time -= delta
	if _event_banner and is_instance_valid(_event_banner):
		_event_banner.modulate.a = 0.5 + 0.5 * absf(sin(_elapsed * 8.0))
		if _banner_time <= 0.0:
			_event_banner.visible = false

func _show_storm_arrow() -> void:
	if _storm_arrow == null or not is_instance_valid(_storm_arrow):
		var viewport_size: Vector2 = get_viewport_rect().size
		_storm_arrow = Label.new()
		_storm_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_storm_arrow.add_theme_font_size_override("font_size", 40)
		_storm_arrow.add_theme_color_override("font_color", Color("#9AD8FF"))
		_storm_arrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_storm_arrow.add_theme_constant_override("outline_size", 5)
		_storm_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_storm_arrow.z_as_relative = false
		_storm_arrow.z_index = 55
		_storm_arrow.size = Vector2(viewport_size.x, 44.0)
		_storm_arrow.position = Vector2(0.0, viewport_size.y * 0.24)
		add_child(_storm_arrow)
	_storm_arrow.text = ">>>" if _storm_dir > 0 else "<<<"
	_storm_arrow.visible = true

func _show_floating(text: String, color: Color, at_pos: Vector2) -> void:
	if VFXManager:
		VFXManager.spawn_floating_text(at_pos, text, color, self)

func _translate_or(key: String, fallback: String) -> String:
	if LocaleManager:
		var text: String = LocaleManager.translate(key)
		if text != "" and text != key:
			return text
	return fallback

# =============================================================================
# HUD
# =============================================================================

func _ensure_countdown_label() -> void:
	if bool(_config.get("countdown_hidden", false)): # mode libre : boucle sans limite visible
		return
	if _countdown_label and is_instance_valid(_countdown_label):
		return
	_countdown_label = Label.new()
	_countdown_label.name = "BreakoutCountdownLabel"
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", maxi(10, int(_cfg.get("countdown_font_size", 48))))
	_countdown_label.add_theme_color_override("font_color", Color(str(_cfg.get("countdown_color", "#FFFFFF"))))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_countdown_label.add_theme_constant_override("outline_size", 6)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.z_as_relative = false
	_countdown_label.z_index = 60
	add_child(_countdown_label)

func _update_countdown_label() -> void:
	if _countdown_label == null or not is_instance_valid(_countdown_label):
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_countdown_label.size = Vector2(viewport_size.x, 60.0)
	_countdown_label.position = Vector2(0.0, viewport_size.y * clampf(float(_cfg.get("countdown_y_ratio", 0.16)), 0.02, 0.9))
	_countdown_label.text = str(int(ceil(maxf(0.0, _duration - _elapsed))))

# =============================================================================
# END OF WAVE
# =============================================================================

func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.DONE
	set_process(false)
	# Restore the player BEFORE notifying the wave chain.
	_restore_player_mode()
	finished.emit()
	queue_free() # balls, bricks, drops, missiles and labels are children -> freed together

func finish_now() -> void:
	_finish()

func _exit_tree() -> void:
	# Defensive: always restore the player if the manager is freed externally.
	if not _finished_emitted:
		_finished_emitted = true
		_restore_player_mode()
