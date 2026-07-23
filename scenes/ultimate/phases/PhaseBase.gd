extends RefCounted
class_name FinalBossPhaseBase
## Base d'une phase du mode FINAL BOSS (spec markdown/final_boss.md §5).
## Une phase = un objet piloté par le mode : `tick(delta)` est appelé tant que
## la phase est active ; la phase agit sur le monde via les helpers publics de
## FinalBossMode (spawn_boss_bullet, get_ship_position, ...). Le SEGMENT de HP
## du boss est surveillé par le mode lui-même — `is_objective_done()` ne sert
## qu'aux phases à objectif spécial (renvois pong, fragments core...).
## `cleanup()` est TOUJOURS appelé (fin de phase, retry, sortie du mode).

var mode = null # FinalBossMode (non typé : évite la dépendance circulaire)
var params: Dictionary = {}
## true = les tirs joueur qui atteignent le boss sont absorbés SANS dégât
## (phases à mécanique exclusive — ex. suika_purge : seule l'explosion
## niveau 3 blesse le boss).
var blocks_direct_damage: bool = false

func setup(mode_ref, phase_params: Dictionary) -> void:
	mode = mode_ref
	params = phase_params if phase_params is Dictionary else {}
	_on_setup()

## Hook d'initialisation spécifique (spawn d'entités de phase...).
func _on_setup() -> void:
	pass

func tick(_delta: float) -> void:
	pass

## true quand l'objectif spécial est rempli (indépendamment du segment HP).
func is_objective_done() -> bool:
	return false

func cleanup() -> void:
	pass
