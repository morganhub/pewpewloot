extends CanvasLayer

## GameHUD — Interface de jeu avec barre de vie et infos joueur.

# =============================================================================
# REFERENCES
# =============================================================================

@onready var profile_label: Label = $TopLeft/ProfileLabel
@onready var hp_bar: ProgressBar = $TopLeft/HPBar
@onready var hp_label: Label = $TopLeft/HPLabel
@onready var score_label: Label = $TopRight/ScoreLabel
@onready var boss_container: Control = $BossHealthContainer
@onready var boss_name_label: Label = $BossHealthContainer/BossNameLabel
@onready var boss_hp_bar: ProgressBar = $BossHealthContainer/BossHPBar

var current_score: int = 0

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if boss_container:
		boss_container.visible = false
	# Style pour le boss (fond noir)
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color.BLACK
	if boss_hp_bar:
		boss_hp_bar.add_theme_stylebox_override("background", sb_bg)

	_update_profile_info()
	_update_score()

# =============================================================================
# BOSS HEALTH
# =============================================================================

func show_boss_health(boss_name: String, max_hp: int) -> void:
	if boss_container: boss_container.visible = true
	if boss_name_label: boss_name_label.text = boss_name.to_upper()
	if boss_hp_bar:
		boss_hp_bar.max_value = max_hp
		boss_hp_bar.value = max_hp
	_update_boss_bar_color(1.0)

func update_boss_health(current_hp: int, max_hp: int) -> void:
	if boss_hp_bar:
		boss_hp_bar.max_value = max_hp
		boss_hp_bar.value = current_hp
	
	var percent := float(current_hp) / float(max_hp)
	_update_boss_bar_color(percent)
	
	if current_hp <= 0 and boss_container:
		boss_container.visible = false

func _update_boss_bar_color(percent: float) -> void:
	var sb_fill := StyleBoxFlat.new()
	if percent > 0.6:
		sb_fill.bg_color = Color.GREEN
	elif percent > 0.3:
		sb_fill.bg_color = Color.YELLOW
	else:
		sb_fill.bg_color = Color.RED
		
	if boss_hp_bar:
		boss_hp_bar.add_theme_stylebox_override("fill", sb_fill)


func _update_profile_info() -> void:
	var profile_name: String = ProfileManager.get_active_profile_name()
	profile_label.text = profile_name

# =============================================================================
# PLAYER HP
# =============================================================================

func update_player_hp(current_hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	hp_label.text = str(current_hp) + " / " + str(max_hp)
	
	# Couleur de la barre
	var hp_percent := float(current_hp) / float(max_hp)
	if hp_percent > 0.5:
		hp_bar.modulate = Color.GREEN
	elif hp_percent > 0.25:
		hp_bar.modulate = Color.YELLOW
	else:
		hp_bar.modulate = Color.RED

func set_player_max_hp(max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = max_hp
	hp_label.text = str(max_hp) + " / " + str(max_hp)

# =============================================================================
# SCORE
# =============================================================================

func add_score(points: int) -> void:
	current_score += points
	_update_score()

func _update_score() -> void:
	score_label.text = "Score: " + str(current_score)

func get_score() -> int:
	return current_score
