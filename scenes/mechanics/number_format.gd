extends RefCounted

## Utilitaire statique — consommé via preload :
##   const NumberFormat := preload("res://scenes/mechanics/number_format.gd")
## (pas de class_name : le cache global de classes n'est pas fiable en
## headless/CLI, le preload l'est toujours.)
##
## Formatage compact des grands nombres du gate_runner : « 1,5K », « 12,5K »,
## « 200K », « 2,5M » — une décimale (supprimée si nulle), séparateur virgule,
## cap d'affichage 999,9M (la ressource elle-même est cappée à 999 999 999 côté
## Player). Les petits nombres non entiers (ex. valeurs ×2.5 des portes)
## gardent deux décimales comme avant.

static func compact(value: float) -> String:
	var v: float = absf(value)
	var sign_str: String = "-" if value < 0.0 else ""
	if v < 1000.0:
		if is_equal_approx(v, round(v)):
			return sign_str + str(int(round(v)))
		return sign_str + str(snappedf(v, 0.01))
	var suffix: String
	var scaled: float
	if v < 1_000_000.0:
		suffix = "K"
		scaled = v / 1000.0
	else:
		suffix = "M"
		scaled = minf(v / 1_000_000.0, 999.9)
	# Une décimale tronquée (pas d'arrondi vers le haut : 999 999 -> 999,9K).
	var whole: int = int(scaled)
	var tenth: int = int(floor((scaled - float(whole)) * 10.0 + 0.0001))
	if tenth <= 0:
		return sign_str + str(whole) + suffix
	return sign_str + str(whole) + "," + str(tenth) + suffix
