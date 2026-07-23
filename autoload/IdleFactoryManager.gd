extends Node
## IdleFactoryManager — chaine de production idle du HomeScreen.
## Spec : markdown/homeScreenGame.md. Config : data/idle_factory.json.
##
## Economie : cristaux (gameplay) -> zelerium -> neorite -> ionium -> tritanium
## -> unlock final 1M. Le systeme ne produit JAMAIS de cristaux.
## La production ne consomme pas la ressource precedente (depense uniquement
## pour debloquer/ameliorer/acheter l'unlock final).
##
## Temps : tout passe par apply_elapsed_time(current_unix) — offline au boot,
## tick runtime (timer interne), retour de pause Android. Par generateur, le
## segment ecoule est decoupe en (temps sous Overdrive x3) + (temps normal x1).
## La charge temporaire 5 s (taps) est runtime only, jamais persistee ; seul
## overdrive_end_unix est sauvegarde.
##
## Persistance : etat runtime dans ce manager, flush_to_profile() throttle
## (transactions, passage en Overdrive, timer save_interval_seconds, sortie
## HomeScreen, pause app) — ProfileManager._update_active_profile ecrit tout
## le fichier a chaque appel, donc jamais de save par tick.

signal resource_amount_changed(resource_id: String, amount: float)
signal generator_state_changed(generator_id: String)
signal overdrive_started(generator_id: String, end_unix: int)
signal overdrive_ended(generator_id: String)
signal final_unlock_purchased(reward_id: String)
## Emis a chaque action volontaire du joueur sur le mini-jeu (tap/boost, unlock,
## upgrade, achat final). Sert au HomeScreen a ne pas afficher le hint "Touchez
## pour changer" tant que le joueur interagit avec la chaine de production.
signal user_interacted()

const TICK_INTERVAL_SEC := 0.2

var _config: Dictionary = {}
var _state: Dictionary = {}
var _initialized := false
# Charge temporaire par generateur : { charge_steps: int, expire_unix_ms: int }
var _tap_charges: Dictionary = {}
var _tick_accum := 0.0
var _save_accum := 0.0
var _dirty := false

func _ready() -> void:
	# Les profils ne sont charges qu'apres le LoadingScreen : ne rien lire ici.
	set_process(false)

func _notification(what: int) -> void:
	# Android : flush + recalage temps aux transitions d'application.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _initialized:
			apply_elapsed_time(_now_unix())
			flush_to_profile()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _initialized:
			_clear_tap_charges()
			apply_elapsed_time(_now_unix())

func _process(delta: float) -> void:
	if not _initialized:
		return
	_tick_accum += delta
	if _tick_accum >= TICK_INTERVAL_SEC:
		_tick_accum = 0.0
		apply_elapsed_time(_now_unix())
		_expire_tap_charges()
	_save_accum += delta
	if _dirty and _save_accum >= _save_interval_sec():
		_save_accum = 0.0
		flush_to_profile()

# =============================================================================
# CYCLE DE VIE / PROFIL
# =============================================================================

## A appeler au boot (apres load des profils) et a chaque changement de profil.
## Applique le temps hors ligne puis demarre la production runtime.
func initialize_for_active_profile() -> void:
	_config = DataManager.get_idle_factory_config() if DataManager else {}
	if not ProfileManager or ProfileManager.get_active_profile().is_empty():
		_initialized = false
		set_process(false)
		return
	_state = ProfileManager.get_idle_factory_state()
	_clear_tap_charges()
	apply_elapsed_time(_now_unix())
	flush_to_profile()
	_initialized = true
	set_process(true)

## Flush du profil sortant avant un changement de profil.
func prepare_profile_switch() -> void:
	if _initialized:
		apply_elapsed_time(_now_unix())
		flush_to_profile()
	halt_without_flush()

## Stoppe l'idle sans rien ecrire (profil en cours de suppression).
func halt_without_flush() -> void:
	_clear_tap_charges()
	_state = {}
	_dirty = false
	_initialized = false
	set_process(false)

## Un seul point d'ecriture profil (throttle par l'appelant / le timer).
func flush_to_profile() -> void:
	if _state.is_empty() or not ProfileManager:
		return
	ProfileManager.set_idle_factory_state(_state)
	_dirty = false
	_save_accum = 0.0

# =============================================================================
# PRODUCTION (runtime + offline unifies)
# =============================================================================

## Produit les ressources entre last_update_unix et current_unix, en separant
## pour chaque generateur le temps passe en Overdrive (x3) du temps normal.
## Ne simule pas seconde par seconde (spec §7.1).
func apply_elapsed_time(current_unix: int) -> void:
	if _state.is_empty():
		return
	# FINAL FORM (final_boss.md §3.4) : usine terminee — plus AUCUNE production
	# (runtime, offline, resume). last_update_unix est quand meme avance pour
	# interdire tout rattrapage retroactif si l'etat devait etre de-gele un jour.
	if bool(_state.get("final_unlock_purchased", false)):
		_state["last_update_unix"] = current_unix
		return
	var last_update := int(_state.get("last_update_unix", 0))
	if last_update <= 0:
		_state["last_update_unix"] = current_unix
		_dirty = true
		return
	var elapsed := maxi(0, current_unix - last_update)
	var cap := int(_config.get("offline_cap_seconds", 0))
	# Le cap ne s'applique qu'aux longues absences (offline), pas au tick runtime.
	if cap > 0 and elapsed > cap:
		elapsed = cap
	if elapsed <= 0:
		_state["last_update_unix"] = current_unix
		return

	var resources: Dictionary = _state.get("resources", {})
	var generators_state: Dictionary = _state.get("generators", {})
	var overdrive_mult := _overdrive_multiplier()
	for gen_cfg in _generator_configs():
		var gen_id := str(gen_cfg.get("id", ""))
		var gen_state: Dictionary = generators_state.get(gen_id, {})
		var level := int(gen_state.get("level", 0))
		if level <= 0:
			continue
		var base := base_production(gen_cfg, level)
		# Decoupe overdrive / normal sur [last_update, last_update + elapsed].
		var od_end := int(gen_state.get("overdrive_end_unix", 0))
		var od_seconds := clampi(od_end - last_update, 0, elapsed)
		var normal_seconds := elapsed - od_seconds
		# Charge temporaire runtime (x1.1..x2.9) : appliquee sur le segment
		# normal du tick courant uniquement (jamais persistee).
		var temp_mult := _temporary_multiplier(gen_id)
		var produced := base * (float(od_seconds) * overdrive_mult + float(normal_seconds) * temp_mult)
		if produced > 0.0:
			var res_id := str(gen_cfg.get("resource_id", ""))
			resources[res_id] = float(resources.get(res_id, 0.0)) + produced
			resource_amount_changed.emit(res_id, float(resources[res_id]))
			_dirty = true
		# Fin d'overdrive franchie pendant ce segment.
		if od_end > 0 and current_unix >= od_end:
			gen_state["overdrive_end_unix"] = 0
			generators_state[gen_id] = gen_state
			_dirty = true
			overdrive_ended.emit(gen_id)
			generator_state_changed.emit(gen_id)
	_state["resources"] = resources
	_state["generators"] = generators_state
	_state["last_update_unix"] = current_unix

# =============================================================================
# FORMULES (data-driven, remplacables par une table levels[])
# =============================================================================

func base_production(gen_cfg: Dictionary, level: int) -> float:
	if level <= 0:
		return 0.0
	var table_v: Variant = gen_cfg.get("levels", [])
	if table_v is Array and not (table_v as Array).is_empty():
		var table := table_v as Array
		var idx := mini(level - 1, table.size() - 1)
		var entry: Variant = table[idx]
		if entry is Dictionary:
			return float((entry as Dictionary).get("production_per_second", 0.0))
	var base := float(gen_cfg.get("base_production_per_second", 0.0))
	var growth := float(gen_cfg.get("production_growth", 1.0))
	return base * pow(growth, level - 1)

## Cout du passage au niveau level+1 pour un generateur au niveau `level`.
func next_upgrade_cost(gen_cfg: Dictionary, level: int) -> int:
	var table_v: Variant = gen_cfg.get("levels", [])
	if table_v is Array and not (table_v as Array).is_empty():
		var table := table_v as Array
		var idx := mini(level, table.size() - 1)
		var entry: Variant = table[idx]
		if entry is Dictionary:
			return int((entry as Dictionary).get("upgrade_cost", 0))
	var base := float(gen_cfg.get("base_upgrade_cost", 0.0))
	var growth := float(gen_cfg.get("upgrade_cost_growth", 1.0))
	return int(ceil(base * pow(growth, level - 1)))

func effective_production(gen_id: String) -> float:
	var gen_cfg := get_generator_config(gen_id)
	var gen_state := _generator_state(gen_id)
	var base := base_production(gen_cfg, int(gen_state.get("level", 0)))
	return base * production_multiplier(gen_id)

## Multiplicateur courant : Overdrive x3 > charge temporaire > x1.
func production_multiplier(gen_id: String) -> float:
	if is_overdrive_active(gen_id):
		return _overdrive_multiplier()
	return _temporary_multiplier(gen_id)

# =============================================================================
# TRANSACTIONS (atomiques : verif -> debit -> mutation -> save -> signal)
# =============================================================================

func unlock_generator(generator_id: String) -> bool:
	if bool(_state.get("final_unlock_purchased", false)):
		return false # Final form : usine gelee (final_boss.md §3.4)
	var gen_cfg := get_generator_config(generator_id)
	if gen_cfg.is_empty():
		return false
	var gen_state := _generator_state(generator_id)
	if int(gen_state.get("level", 0)) > 0:
		return false
	# Le generateur precedent doit etre actif (sauf le premier de la chaine).
	var prev_id := _previous_generator_id(generator_id)
	if prev_id != "" and int(_generator_state(prev_id).get("level", 0)) <= 0:
		return false
	var cost := int(gen_cfg.get("unlock_cost", 0))
	if not _spend_costs(str(gen_cfg.get("cost_resource_id", "")), cost, int(gen_cfg.get("crystal_flat_cost", 0))):
		return false
	gen_state["level"] = 1
	_set_generator_state(generator_id, gen_state)
	# La production demarre immediatement : le timestamp global couvre deja
	# le generateur (niveau 0 -> 0 produit jusqu'ici).
	flush_to_profile()
	generator_state_changed.emit(generator_id)
	user_interacted.emit()
	return true

func upgrade_generator(generator_id: String) -> bool:
	if bool(_state.get("final_unlock_purchased", false)):
		return false # Final form : usine gelee (final_boss.md §3.4)
	var gen_cfg := get_generator_config(generator_id)
	if gen_cfg.is_empty():
		return false
	var gen_state := _generator_state(generator_id)
	var level := int(gen_state.get("level", 0))
	if level <= 0:
		return false
	var max_level := int(gen_cfg.get("max_level", 0))
	if max_level > 0 and level >= max_level:
		return false
	# Production due jusqu'a maintenant AVANT le changement de niveau.
	apply_elapsed_time(_now_unix())
	var cost := next_upgrade_cost(gen_cfg, level)
	if not _spend_costs(str(gen_cfg.get("cost_resource_id", "")), cost, int(gen_cfg.get("crystal_flat_cost", 0))):
		return false
	gen_state["level"] = level + 1
	_set_generator_state(generator_id, gen_state)
	# L'Overdrive actif est conserve : la nouvelle production beneficie du x3.
	flush_to_profile()
	generator_state_changed.emit(generator_id)
	user_interacted.emit()
	return true

## Tap de surcadence. Retourne le nombre de pas de charge courant (0 = refuse).
func tap_generator(generator_id: String) -> int:
	if bool(_state.get("final_unlock_purchased", false)):
		return 0 # Final form : usine gelee (final_boss.md §3.4)
	var gen_state := _generator_state(generator_id)
	if int(gen_state.get("level", 0)) <= 0:
		return 0
	if is_overdrive_active(generator_id):
		return 0
	# Production due au multiplicateur courant avant de changer la charge.
	apply_elapsed_time(_now_unix())
	user_interacted.emit()
	var boost_cfg := _boost_config()
	var steps_max := int(boost_cfg.get("steps_to_overdrive", 20))
	var charge: Dictionary = _tap_charges.get(generator_id, { "charge_steps": 0, "expire_unix_ms": 0 })
	var steps := int(charge.get("charge_steps", 0)) + 1
	if steps >= steps_max:
		# 20e tap : Overdrive verrouille, jauge pleine, charge temporaire purgee.
		_tap_charges.erase(generator_id)
		var end_unix := _now_unix() + int(boost_cfg.get("overdrive_duration_seconds", 14400))
		gen_state["overdrive_end_unix"] = end_unix
		_set_generator_state(generator_id, gen_state)
		flush_to_profile()
		overdrive_started.emit(generator_id, end_unix)
		generator_state_changed.emit(generator_id)
		return steps_max
	# Chaque tap remet le delai temporaire a 5 s.
	charge["charge_steps"] = steps
	charge["expire_unix_ms"] = Time.get_ticks_msec() + int(float(boost_cfg.get("temporary_duration_seconds", 5.0)) * 1000.0)
	_tap_charges[generator_id] = charge
	generator_state_changed.emit(generator_id)
	return steps

## DEBUG (OptionsMenu, manual_debug_mode) : force l'etat final_unlock sans cout.
## ON n'emet PAS le signal final_unlock_purchased (pas de choregraphie/lancement
## auto depuis les options) — le HomeScreen reconstruit l'etat au retour.
## OFF : l'usine repart sans rattrapage (last_update_unix a continue d'avancer
## pendant le gel, cf. apply_elapsed_time).
func debug_set_final_unlock(purchased: bool) -> void:
	if _state.is_empty():
		return
	_state["final_unlock_purchased"] = purchased
	_dirty = true
	flush_to_profile()

func purchase_final_unlock() -> bool:
	if bool(_state.get("final_unlock_purchased", false)):
		return false
	var final_cfg: Dictionary = _config.get("final_unlock", {})
	var res_id := str(final_cfg.get("resource_id", "tritanium"))
	var cost := int(final_cfg.get("cost", 1000000))
	apply_elapsed_time(_now_unix())
	if not _spend_cost_resource(res_id, cost):
		return false
	_state["final_unlock_purchased"] = true
	_dirty = true
	flush_to_profile()
	final_unlock_purchased.emit(str(final_cfg.get("reward_id", "")))
	user_interacted.emit()
	return true

# =============================================================================
# LECTURE (UI)
# =============================================================================

func is_ready() -> bool:
	return _initialized

func get_config() -> Dictionary:
	return _config

func get_resource_amount(resource_id: String) -> float:
	if resource_id == "crystals":
		return float(ProfileManager.get_crystals()) if ProfileManager else 0.0
	var resources: Dictionary = _state.get("resources", {})
	return float(resources.get(resource_id, 0.0))

func get_generator_config(generator_id: String) -> Dictionary:
	for gen_cfg in _generator_configs():
		if str(gen_cfg.get("id", "")) == generator_id:
			return gen_cfg
	return {}

func get_generator_ids() -> Array[String]:
	var ids: Array[String] = []
	for gen_cfg in _generator_configs():
		ids.append(str(gen_cfg.get("id", "")))
	return ids

func is_overdrive_active(generator_id: String) -> bool:
	return int(_generator_state(generator_id).get("overdrive_end_unix", 0)) > _now_unix()

func get_overdrive_remaining_sec(generator_id: String) -> int:
	return maxi(0, int(_generator_state(generator_id).get("overdrive_end_unix", 0)) - _now_unix())

func get_charge_steps(generator_id: String) -> int:
	if is_overdrive_active(generator_id):
		return int(_boost_config().get("steps_to_overdrive", 20))
	var charge: Dictionary = _tap_charges.get(generator_id, {})
	return int(charge.get("charge_steps", 0))

## Fraction de temps restant (1.0 juste apres un tap -> 0.0 a l'expiration des 5 s)
## de la charge temporaire. Continu (base sur Time.get_ticks_msec()) : sert a
## l'UI a faire descendre la jauge progressivement sur toute la fenetre de 5 s.
## 0.0 s'il n'y a pas de charge, 1.0 pendant l'Overdrive (jauge pleine verrouillee).
func get_temporary_remaining_ratio(generator_id: String) -> float:
	if is_overdrive_active(generator_id):
		return 1.0
	var charge: Dictionary = _tap_charges.get(generator_id, {})
	if int(charge.get("charge_steps", 0)) <= 0:
		return 0.0
	var dur_ms := float(_boost_config().get("temporary_duration_seconds", 5.0)) * 1000.0
	if dur_ms <= 0.0:
		return 0.0
	var remaining := float(int(charge.get("expire_unix_ms", 0)) - Time.get_ticks_msec())
	return clampf(remaining / dur_ms, 0.0, 1.0)

func is_final_unlock_purchased() -> bool:
	return bool(_state.get("final_unlock_purchased", false))

## Vue complete d'un generateur pour l'UI (aucune logique cote panneau).
func get_generator_view_data(generator_id: String) -> Dictionary:
	var gen_cfg := get_generator_config(generator_id)
	var gen_state := _generator_state(generator_id)
	var level := int(gen_state.get("level", 0))
	var prev_id := _previous_generator_id(generator_id)
	var cost_res := str(gen_cfg.get("cost_resource_id", ""))
	var next_cost := int(gen_cfg.get("unlock_cost", 0)) if level <= 0 else next_upgrade_cost(gen_cfg, level)
	# Surcout fixe en cristaux (crystal_flat_cost) applique a chaque unlock/upgrade.
	var crystal_flat := int(gen_cfg.get("crystal_flat_cost", 0))
	var crystal_need := crystal_flat + (next_cost if cost_res == "crystals" else 0)
	var can_afford_crystals: bool = crystal_need <= 0 or get_resource_amount("crystals") >= float(crystal_need)
	var can_afford_cost: bool = can_afford_crystals if cost_res == "crystals" \
		else get_resource_amount(cost_res) >= float(next_cost)
	return {
		"id": generator_id,
		"resource_id": str(gen_cfg.get("resource_id", "")),
		"cost_resource_id": cost_res,
		"level": level,
		"unlocked": level > 0,
		"can_unlock": level <= 0 and (prev_id == "" or int(_generator_state(prev_id).get("level", 0)) > 0),
		"next_cost": next_cost,
		"crystal_flat_cost": crystal_flat,
		"can_afford_cost": can_afford_cost,
		"can_afford_crystals": can_afford_crystals,
		"can_afford": can_afford_cost and can_afford_crystals,
		"effective_production": effective_production(generator_id),
		"multiplier": production_multiplier(generator_id),
		"charge_steps": get_charge_steps(generator_id),
		"steps_max": int(_boost_config().get("steps_to_overdrive", 20)),
		"temp_remaining_ratio": get_temporary_remaining_ratio(generator_id),
		"overdrive_active": is_overdrive_active(generator_id),
		"overdrive_remaining_sec": get_overdrive_remaining_sec(generator_id)
	}

# Divisions entieres intentionnelles (formatage dixiemes / h:min:s).
@warning_ignore_start("integer_division")
## Format d'un debit "+X,X/s" : une decimale, virgule (ex. "2,1", "0,0").
## Non-static : appelee sur le singleton IdleFactoryManager (evite STATIC_CALLED_ON_INSTANCE).
func format_rate(value: float) -> String:
	if value >= 1000.0:
		return str(int(round(value)))
	var tenths := int(round(value * 10.0))
	return str(tenths / 10) + "," + str(tenths % 10)

## Format "3 h 58" / "12 min 24 s" (spec §6.4).
func format_duration(seconds: int) -> String:
	var s := maxi(0, seconds)
	if s >= 3600:
		return str(s / 3600) + " h " + str((s % 3600) / 60).pad_zeros(2)
	return str(s / 60) + " min " + str(s % 60).pad_zeros(2) + " s"
@warning_ignore_restore("integer_division")

# =============================================================================
# INTERNES
# =============================================================================

func _now_unix() -> int:
	return int(Time.get_unix_time_from_system())

func _boost_config() -> Dictionary:
	var v: Variant = _config.get("boost", {})
	return v if v is Dictionary else {}

func _overdrive_multiplier() -> float:
	var boost := _boost_config()
	return 1.0 + float(boost.get("steps_to_overdrive", 20)) * float(boost.get("tap_percent", 10.0)) / 100.0

func _temporary_multiplier(gen_id: String) -> float:
	var charge: Dictionary = _tap_charges.get(gen_id, {})
	var steps := int(charge.get("charge_steps", 0))
	if steps <= 0:
		return 1.0
	return 1.0 + float(steps) * float(_boost_config().get("tap_percent", 10.0)) / 100.0

func _save_interval_sec() -> float:
	return float(_config.get("save_interval_seconds", 30.0))

func _generator_configs() -> Array:
	var v: Variant = _config.get("generators", [])
	return v if v is Array else []

func _generator_state(generator_id: String) -> Dictionary:
	var generators: Dictionary = _state.get("generators", {})
	var v: Variant = generators.get(generator_id, {})
	if v is Dictionary and not (v as Dictionary).is_empty():
		return v as Dictionary
	return { "level": 0, "overdrive_end_unix": 0 }

func _set_generator_state(generator_id: String, gen_state: Dictionary) -> void:
	var generators: Dictionary = _state.get("generators", {})
	generators[generator_id] = gen_state
	_state["generators"] = generators
	_dirty = true

## Generateur precedent dans la chaine (ordre de generators[]) ; "" si premier.
func _previous_generator_id(generator_id: String) -> String:
	var configs := _generator_configs()
	for i in range(configs.size()):
		if str((configs[i] as Dictionary).get("id", "")) == generator_id:
			return str((configs[i - 1] as Dictionary).get("id", "")) if i > 0 else ""
	return ""

## Debite le cout croissant (cost_resource_id) ET le surcout fixe en cristaux
## (crystal_flat_cost) dans une meme transaction : les DEUX soldes sont verifies
## AVANT tout debit — jamais de debit partiel. Si le cout croissant est deja en
## cristaux (zelerium), le flat s'y ajoute en un seul debit.
func _spend_costs(cost_resource_id: String, cost: int, crystal_flat: int) -> bool:
	if cost < 0 or crystal_flat < 0:
		return false
	var crystal_total := crystal_flat + (cost if cost_resource_id == "crystals" else 0)
	var other_cost := 0 if cost_resource_id == "crystals" else cost
	# Verification des deux soldes avant tout debit.
	if crystal_total > 0 and (not ProfileManager or ProfileManager.get_crystals() < crystal_total):
		return false
	var resources: Dictionary = _state.get("resources", {})
	if other_cost > 0 and float(resources.get(cost_resource_id, 0.0)) < float(other_cost):
		return false
	# Debits (les verifs sont passees, spend_crystals ne peut plus echouer).
	if crystal_total > 0:
		if not ProfileManager.spend_crystals(crystal_total):
			return false
		resource_amount_changed.emit("crystals", get_resource_amount("crystals"))
	if other_cost > 0:
		resources[cost_resource_id] = float(resources.get(cost_resource_id, 0.0)) - float(other_cost)
		_state["resources"] = resources
		_dirty = true
		resource_amount_changed.emit(cost_resource_id, float(resources[cost_resource_id]))
	return true

## Debite `cost` dans la ressource demandee. Cristaux via ProfileManager,
## les autres dans le state idle. Retourne false sans rien modifier si
## solde insuffisant (double-tap safe : verif + debit dans la meme passe).
func _spend_cost_resource(resource_id: String, cost: int) -> bool:
	if cost < 0:
		return false
	if resource_id == "crystals":
		if not ProfileManager or not ProfileManager.spend_crystals(cost):
			return false
		resource_amount_changed.emit("crystals", get_resource_amount("crystals"))
		return true
	var resources: Dictionary = _state.get("resources", {})
	var current := float(resources.get(resource_id, 0.0))
	if current < float(cost):
		return false
	resources[resource_id] = current - float(cost)
	_state["resources"] = resources
	_dirty = true
	resource_amount_changed.emit(resource_id, float(resources[resource_id]))
	return true

func _clear_tap_charges() -> void:
	_tap_charges.clear()

## Expiration des charges temporaires (>5 s sans tap) : retour immediat a x1.
func _expire_tap_charges() -> void:
	var now_ms := Time.get_ticks_msec()
	var expired: Array = []
	for gen_id in _tap_charges.keys():
		if now_ms >= int((_tap_charges[gen_id] as Dictionary).get("expire_unix_ms", 0)):
			expired.append(gen_id)
	for gen_id in expired:
		_tap_charges.erase(gen_id)
		generator_state_changed.emit(str(gen_id))
