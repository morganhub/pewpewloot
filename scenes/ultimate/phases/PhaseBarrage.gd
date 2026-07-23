# Extends par CHEMIN (pas par class_name) : robuste au chargement isolé
# (headless verify) où l'index des classes globales n'est pas encore peuplé.
extends "res://scenes/ultimate/phases/PhaseBase.gd"
class_name FinalBossPhaseBarrage
## Phase « barrage » — ouverture shmup (spec final_boss.md §5.2 #1) : le boss
## alterne des patterns RADIAUX (éventail dans le plan écran, projeté vers le
## joueur) et des salves VISÉES (vers la position courante du vaisseau, avec
## léger spread). DPS pur sur le boss, esquive sur le plan de contrôle.

var _timer: float = 0.0
var _alternate: bool = false

func _on_setup() -> void:
	# Première salve après un court répit (lisibilité d'entrée de phase).
	_timer = maxf(0.4, float(params.get("pattern_interval_sec", 2.2))) * 0.6

func tick(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = maxf(0.4, float(params.get("pattern_interval_sec", 2.2)))
	_alternate = not _alternate
	if _alternate:
		_fire_radial()
	else:
		_fire_aimed()

func _fire_radial() -> void:
	var count := maxi(1, int(params.get("radial_count", 10)))
	for i in range(count):
		var a := TAU * float(i) / float(count)
		# Éventail elliptique dans le plan écran, poussé vers le plan de contrôle
		# (+Z) — l'écrasement vertical (0.35) garde le motif lisible en portrait.
		var dir := Vector3(cos(a) * 0.55, sin(a) * 0.35, 1.0).normalized()
		mode.spawn_boss_bullet(dir, params)

func _fire_aimed() -> void:
	var count := maxi(1, int(params.get("aimed_count", 3)))
	var spread := deg_to_rad(maxf(0.0, float(params.get("aimed_spread_deg", 14.0))))
	var to_ship: Vector3 = (mode.get_ship_position() - mode.get_boss_position()).normalized()
	for i in range(count):
		var t := 0.0 if count <= 1 else (float(i) / float(count - 1) - 0.5)
		var dir := to_ship.rotated(Vector3.UP, t * spread)
		mode.spawn_boss_bullet(dir, params)
