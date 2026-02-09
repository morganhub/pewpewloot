extends Node

## AudioManager — Gère la musique de fond globale avec loop et fade in/out.
## Persistent (Autoload).

var _music_player: AudioStreamPlayer
var _current_track_path: String = ""
var _current_tween: Tween

const DEFAULT_FADE_DURATION: float = 1.0 # 1 seconde de fade par défaut

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Continue playing even when paused
	
	_setup_audio_buses()
	
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	
	if AudioServer.get_bus_index("Music") != -1:
		_music_player.bus = "Music"
	else:
		_music_player.bus = "Master"
		
	add_child(_music_player)
	
	# Connecter le signal de fin pour boucler
	# Connecter le signal de fin pour boucler
	_music_player.finished.connect(_on_music_finished)
	
	# Initialiser les volumes
	sync_volumes()
	
	call_deferred("_init_music")

func _setup_audio_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		var idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
		
	if AudioServer.get_bus_index("SFX") == -1:
		var idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")

func set_music_volume(linear_val: float) -> void:
	var idx = AudioServer.get_bus_index("Music")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear_val))

func set_sfx_volume(linear_val: float) -> void:
	var idx = AudioServer.get_bus_index("SFX")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear_val))

func sync_volumes() -> void:
	var vol_music = ProfileManager.get_setting("music_volume", 1.0)
	var vol_sfx = ProfileManager.get_setting("sfx_volume", 1.0)
	set_music_volume(vol_music)
	set_sfx_volume(vol_sfx)

func _init_music() -> void:
	if not DataManager:
		push_error("[AudioManager] DataManager not found!")
		return
		
	var config: Dictionary = DataManager.get_game_config()
	if config.has("main_menu"):
		var menu_config: Dictionary = config["main_menu"]
		var music_path: String = str(menu_config.get("music", ""))
		if music_path != "":
			play_music(music_path, 2.0) # Fade in plus doux au démarrage (2s)

## Joue une musique avec Fade In/Out
func play_music(path: String, fade_duration: float = DEFAULT_FADE_DURATION) -> void:
	if path == _current_track_path and _music_player.playing:
		return # Déjà en lecture
		
	if not ResourceLoader.exists(path):
		push_warning("[AudioManager] Music file not found: " + path)
		return
		
	var stream = load(path)
	if not stream: return
	
	# S'assurer que les volumes sont à jour
	sync_volumes()

	# Annuler le tween en cours s'il existe
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
		
	_current_tween = create_tween()
	
	if _music_player.playing:
		# Scenario: Musique en cours -> Fade Out -> Changement -> Fade In
		# 1. Fade OUT
		_current_tween.tween_property(_music_player, "volume_db", -80.0, fade_duration * 0.5)
		
		# 2. Callback de changement
		_current_tween.tween_callback(func():
			_current_track_path = path
			_music_player.stream = stream
			_music_player.play()
			print("[AudioManager] Switch track: ", path)
		)
		
		# 3. Fade IN
		_current_tween.tween_property(_music_player, "volume_db", 0.0, fade_duration * 0.5)
		
	else:
		# Scenario: Pas de musique -> Start direct avec Fade In
		_current_track_path = path
		_music_player.stream = stream
		_music_player.volume_db = -80.0
		_music_player.play()
		print("[AudioManager] Start track: ", path)
		
		_current_tween.tween_property(_music_player, "volume_db", 0.0, fade_duration)

## Stoppe la musique avec un Fade Out
func stop_music(fade_duration: float = DEFAULT_FADE_DURATION) -> void:
	if not _music_player.playing: return
	
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
		
	_current_tween = create_tween()
	_current_tween.tween_property(_music_player, "volume_db", -80.0, fade_duration)
	_current_tween.tween_callback(func():
		_music_player.stop()
		_current_track_path = ""
	)

func _on_music_finished() -> void:
	# Boucle automatique : Relancer la musique si elle s'arrête
	if _current_track_path != "" and _music_player.stream:
		# Pas de fade ici, on veut une boucle seamless
		_music_player.play()

# =============================================================================
# SFX
# =============================================================================

const MAX_SFX_PLAYERS: int = 24
var _sfx_players: Array[AudioStreamPlayer] = []

func play_sfx(path: String, pitch_rng: float = 0.0) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
		
	var stream = load(path)
	if not stream: return
	
	var player = _get_available_sfx_player()
	player.stream = stream
	
	if pitch_rng > 0:
		player.pitch_scale = randf_range(1.0 - pitch_rng, 1.0 + pitch_rng)
	else:
		player.pitch_scale = 1.0
		
	player.play()

func _get_available_sfx_player() -> AudioStreamPlayer:
	# Chercher un player libre
	for p in _sfx_players:
		if not p.playing:
			return p
			
	# Si aucun libre et pas encore au max, en créer un
	if _sfx_players.size() < MAX_SFX_PLAYERS:
		var p = AudioStreamPlayer.new()
		p.name = "SFXPlayer_" + str(_sfx_players.size())
		if AudioServer.get_bus_index("SFX") != -1:
			p.bus = "SFX"
		else:
			p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)
		return p
		
	# Sinon, recycler le plus ancien (le premier de la liste qui n'est pas forcément fini mais bon)
	# On pourrait faire un index tournant
	var p = _sfx_players[0]
	_sfx_players.pop_front()
	_sfx_players.push_back(p)
	return p
