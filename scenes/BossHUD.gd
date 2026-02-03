extends Control

## BossHUD — Barre de vie et nom du boss en haut de l'écran.

@onready var boss_name_label: Label = $Panel/VBox/BossName
@onready var boss_hp_bar: ProgressBar = $Panel/VBox/HPBar
@onready var phase_label: Label = $Panel/VBox/PhaseLabel

var boss_ref: CharacterBody2D = null

func setup(boss: CharacterBody2D) -> void:
	boss_ref = boss
	boss_name_label.text = boss.boss_name
	boss_hp_bar.max_value = boss.max_hp
	boss_hp_bar.value = boss.current_hp
	phase_label.text = "Phase 1"
	
	# Connecter les signaux
	boss.phase_changed.connect(_on_phase_changed)
	boss.tree_exiting.connect(_on_boss_died)
	
	show()

func _process(_delta: float) -> void:
	if boss_ref and is_instance_valid(boss_ref):
		boss_hp_bar.value = boss_ref.current_hp
		
		# Couleur de la barre
		var hp_percent := float(boss_ref.current_hp) / float(boss_ref.max_hp)
		if hp_percent > 0.5:
			boss_hp_bar.modulate = Color.RED
		elif hp_percent > 0.25:
			boss_hp_bar.modulate = Color.ORANGE_RED
		else:
			boss_hp_bar.modulate = Color.DARK_RED

func _on_phase_changed(phase: int) -> void:
	phase_label.text = "Phase " + str(phase)
	
	# Animation flash
	var tween := create_tween()
	tween.tween_property(phase_label, "modulate", Color.YELLOW, 0.1)
	tween.tween_property(phase_label, "modulate", Color.WHITE, 0.1)
	tween.set_loops(3)

func _on_boss_died() -> void:
	# Fade out
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(queue_free)
