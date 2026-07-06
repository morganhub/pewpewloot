extends SceneTree

## Headless GDScript compile-check (voir project.md > "Tester la compilation Godot").
##
## Charge chaque script cible avec les autoloads enregistres, ce qui fait
## remonter les VRAIES erreurs de compilation sans les faux positifs
## "Identifier not found: DataManager/..." du mode --check-only (qui compile les
## scripts isoles, hors contexte des singletons).
##
## Usage (les chemins res:// passent apres `++`) :
##   godot --headless --path . --script res://tools/verify_compile.gd ++ \
##     res://scenes/Player.gd res://scenes/Game.gd
##
## Sans argument : balaye tout le projet (scenes/, autoload/, scripts/, tools/).
## Sortie process = 0 si tout compile, 1 sinon.

func _initialize() -> void:
	var targets: PackedStringArray = OS.get_cmdline_user_args()
	if targets.is_empty():
		targets = _scan_all_scripts()
		print("[VERIFY] no args -> full project sweep (", targets.size(), " scripts)")

	var failed: int = 0
	for p in targets:
		var path: String = str(p)
		if not path.ends_with(".gd"):
			continue
		var s: Variant = load(path)
		if s == null:
			print("[VERIFY] FAIL  ", path)
			failed += 1
		else:
			print("[VERIFY] OK    ", path)

	print("[VERIFY] RESULT ", "ALL_OK" if failed == 0 else "HAS_ERRORS (%d)" % failed)
	quit(0 if failed == 0 else 1)

func _scan_all_scripts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for root_dir in ["res://scenes", "res://autoload", "res://scripts", "res://tools"]:
		_collect_gd(root_dir, out)
	return out

func _collect_gd(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var full: String = dir_path + "/" + name
			if dir.current_is_dir():
				_collect_gd(full, out)
			elif name.ends_with(".gd"):
				out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
