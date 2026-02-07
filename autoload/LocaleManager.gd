extends Node

## LocaleManager — Gestion de la localisation (i18n).
## Charge les fichiers de langue et fournit les traductions.

var _current_locale: String = "fr"
var _strings: Dictionary = {}

func _ready() -> void:
	load_locale(_current_locale)

func load_locale(locale: String) -> void:
	_current_locale = locale
	var path := "res://data/locales/" + locale + ".json"
	
	if not FileAccess.file_exists(path):
		push_warning("[LocaleManager] Locale file not found: " + path)
		return
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[LocaleManager] Could not open locale file: " + path)
		return
	
	var text := file.get_as_text()
	file.close()
	
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var data := parsed as Dictionary
		var strings_data: Variant = data.get("strings", {})
		if strings_data is Dictionary:
			_strings = strings_data as Dictionary
	
	print("[LocaleManager] Loaded locale: ", locale, " (", _strings.size(), " strings)")

## Retourne la locale actuelle
func get_locale() -> String:
	return _current_locale

## Change la locale
func set_locale(locale: String) -> void:
	load_locale(locale)

## Traduit une clé avec substitution de paramètres
## Exemple: translate("home_profile", {"name": "John"}) -> "Profil: John"
func translate(key: String, params: Dictionary = {}) -> String:
	var text: String = str(_strings.get(key, key))
	
	# Substitution des paramètres {key} -> value
	for param_key in params.keys():
		var placeholder := "{" + str(param_key) + "}"
		text = text.replace(placeholder, str(params[param_key]))
	
	return text

## Raccourci pour les traductions simples sans paramètres
func t(key: String) -> String:
	return translate(key, {})

## Vérifie si une clé existe dans les cordes chargées
func has_key(key: String) -> bool:
	return _strings.has(key)
