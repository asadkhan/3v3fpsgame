extends Node
## sound. registered as the Audio autoload.
##
## everything's synthesized here at startup - no audio assets needed. to swap
## in a real recording later, just load a file into _library under the same
## name, play() and play_at() don't care.
##
## two ways to play:
## - play(): flat, for stuff that happens to you - your own gun, hit
##   confirmations, UI, round stings.
## - play_at(): positioned in the world, for anything you need to locate -
##   other players' shots and footsteps, the planted core.
##
## volume follows GameConfig.master_volume.

const RATE := 22050

## sound name -> AudioStreamWAV.
var _library: Dictionary = {}

var _flat_players: Array[AudioStreamPlayer] = []
const FLAT_VOICES := 16
var _next_flat: int = 0

const MAX_WORLD_VOICES := 32
var _world_voices: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in FLAT_VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_flat_players.append(player)
	_apply_volume()
	GameConfig.setting_changed.connect(func(key: String, _value: Variant) -> void:
		if key == "audio/master_volume":
			_apply_volume()
		elif key == "audio/music_volume":
			_update_music(0.3))
	_build_library()
	# low-pass on the master bus, wide open; a nearby blast closes it briefly
	# to muffle the world.
	_muffle = AudioEffectLowPassFilter.new()
	_muffle.cutoff_hz = 20500.0
	AudioServer.add_bus_effect(0, _muffle)
	# every button gets a hover tick + grow, and a click on press
	get_tree().node_added.connect(_on_node_added)
	_setup_music.call_deferred()


var _muffle: AudioEffectLowPassFilter = null
var _muffle_tween: Tween = null


## muffles everything and rings the ears. strength is 0..1 of a blast.
func concuss(strength: float) -> void:
	if _muffle == null:
		return
	play(&"tinnitus", linear_to_db(clampf(strength, 0.05, 1.0)) - 4.0, 0.0)
	if _muffle_tween != null:
		_muffle_tween.kill()
	_muffle.cutoff_hz = lerpf(3000.0, 500.0, strength)
	_muffle_tween = create_tween()
	_muffle_tween.tween_property(_muffle, "cutoff_hz", 20500.0, 1.5 + strength * 2.0) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)


func _on_node_added(node: Node) -> void:
	if not node is BaseButton:
		return
	var button := node as BaseButton
	button.mouse_entered.connect(func() -> void:
		if button.disabled:
			return
		play(&"ui_hover", -14.0, 0.05)
		button.pivot_offset = button.size * 0.5
		var tween := button.create_tween()
		tween.tween_property(button, "scale", Vector2.ONE * 1.03, 0.08))
	button.mouse_exited.connect(func() -> void:
		var tween := button.create_tween()
		tween.tween_property(button, "scale", Vector2.ONE, 0.1))
	button.pressed.connect(func() -> void: play(&"ui_click", -8.0, 0.05))


## two thumps, lub-dub
func _heartbeat() -> AudioStreamWAV:
	var seconds := 0.5
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var v := 0.0
		for beat: Array in [[0.0, 1.0], [0.2, 0.7]]:
			var r: float = t - beat[0]
			if r >= 0.0:
				v += sin(TAU * 52.0 * r) * exp(-r * 22.0) * beat[1]
		samples[i] = v * 0.9
	return _to_stream(samples)


# --- Music --------------------------------------------------------------------

## the menu theme. swap the file to change the music.
const MUSIC_PATH := "res://assets/audio/music/menu_theme.wav"
## how loud the music sits under everything else, before the music slider
const MUSIC_BASE_DB := -9.0
## per phase, dB on top of the base. missing = music off (live rounds, so
## footsteps stay readable)
const MUSIC_BY_PHASE := {
	GamePhase.Phase.MAIN_MENU: 0.0,
	GamePhase.Phase.LOBBY: -4.0,
	GamePhase.Phase.WARMUP: -8.0,
	GamePhase.Phase.BUY: -10.0,
	GamePhase.Phase.MATCH_END: 0.0,
}

var _music: AudioStreamPlayer = null
var _music_tween: Tween = null


func _setup_music() -> void:
	if not ResourceLoader.exists(MUSIC_PATH):
		return
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.stream = load(MUSIC_PATH)
	_music.volume_db = -60.0
	add_child(_music)
	GameManager.state_changed.connect(func(_from: int, _to: int) -> void: _update_music(1.5))
	_update_music(2.0)


## fades the music to wherever the current phase wants it, over seconds.
func _update_music(seconds: float) -> void:
	if _music == null:
		return
	var phase: int = GameManager.current_phase
	var music := clampf(GameConfig.music_volume, 0.0, 1.0)
	var on := MUSIC_BY_PHASE.has(phase) and music > 0.001
	var target := MUSIC_BASE_DB + float(MUSIC_BY_PHASE.get(phase, 0.0)) + linear_to_db(maxf(music, 0.0001))
	if on and not _music.playing:
		_music.volume_db = -60.0
		_music.play()
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	if on:
		_music_tween.tween_property(_music, "volume_db", target, seconds)
	else:
		_music_tween.tween_property(_music, "volume_db", -60.0, seconds)
		_music_tween.tween_callback(_music.stop)


func _apply_volume() -> void:
	var volume := clampf(GameConfig.master_volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)


# --- Playing ------------------------------------------------------------------

## plays sound_name flat (not positioned). random pitch spread keeps repeated
## sounds from sounding robotic.
func play(sound_name: StringName, volume_db: float = 0.0, pitch_spread: float = 0.04) -> void:
	var stream: AudioStream = _library.get(sound_name)
	if stream == null:
		return
	var player := _flat_players[_next_flat]
	_next_flat = (_next_flat + 1) % FLAT_VOICES
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	player.play()


## plays sound_name at position in the world. distance attenuates and muffles
## the highs, so a far shot sounds far.
func play_at(sound_name: StringName, position: Vector3, volume_db: float = 0.0,
		pitch_spread: float = 0.04, reach: float = 60.0) -> void:
	var stream: AudioStream = _library.get(sound_name)
	if stream == null or _world_voices >= MAX_WORLD_VOICES:
		return
	# parent to the match scene so the sound gets cut off when the match ends
	var scene := get_tree().get_first_node_in_group(&"match_scene")
	if scene == null:
		scene = get_tree().current_scene
	if scene == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	player.unit_size = 8.0
	player.max_distance = reach
	player.attenuation_filter_cutoff_hz = 4500.0
	player.attenuation_filter_db = -18.0
	player.panning_strength = 1.2
	scene.add_child(player)
	player.global_position = position
	_world_voices += 1
	player.finished.connect(func() -> void:
		_world_voices -= 1
		player.queue_free())
	player.play()


func has_sound(sound_name: StringName) -> bool:
	return _library.has(sound_name)


# --- Synthesis ------------------------------------------------------------------

func _build_library() -> void:
	# weapons: filtered noise crack over a falling thump, heavier guns = lower/longer body
	_library[&"shot_rifle"] = _gunshot(0.34, 95.0, 0.35, 16.0, 1.0)
	_library[&"shot_smg"] = _gunshot(0.22, 130.0, 0.45, 24.0, 0.85)
	_library[&"shot_pistol"] = _gunshot(0.24, 150.0, 0.55, 22.0, 0.9)
	_library[&"shot_burst"] = _gunshot(0.28, 110.0, 0.4, 19.0, 0.95)
	_library[&"dry_fire"] = _click(0.05, 2200.0, 0.5)
	_library[&"reload_out"] = _click(0.08, 900.0, 0.8)
	_library[&"reload_in"] = _click(0.1, 1300.0, 1.0)
	_library[&"switch"] = _click(0.09, 700.0, 0.6)
	_library[&"rack"] = _rack()
	# battlefield
	_library[&"casing"] = _tones([[4200.0, 0.0, 0.3], [6100.0, 0.0, 0.2], [8300.0, 0.0, 0.12]], 0.18, 30.0, 0.35)
	_library[&"bullet_crack"] = _crack()
	_library[&"shot_echo"] = _echo_tail(1.4, 0.5)
	_library[&"distant_boom"] = _distant_boom()
	_library[&"distant_burst"] = _distant_burst()
	_library[&"wind"] = _looped(_wind(8.0))
	_library[&"fire_crackle"] = _looped(_crackle(4.0))
	# grenades
	_library[&"grenade_throw"] = _whoosh(0.3, 500.0, 1800.0, 0.5)
	_library[&"grenade_bounce"] = _tones([[1150.0, 0.0, 0.25], [2380.0, 0.0, 0.12]], 0.16, 38.0, 0.5)
	_library[&"grenade_boom"] = _boom(2.4, 1.0)
	_library[&"smoke_pop"] = _thump(0.25, 90.0, 16.0, 0.9)
	_library[&"smoke_hiss"] = _looped(_hiss(3.0))
	_load_recordings()
	_library[&"heartbeat"] = _heartbeat()
	_library[&"tinnitus"] = _tones([[4100.0, 0.0, 0.35]], 2.6, 1.1, 0.25)
	_library[&"ui_hover"] = _click(0.025, 2400.0, 0.18)
	# knife: air, steel, impact
	_library[&"knife_swing"] = _whoosh(0.26, 700.0, 2600.0, 0.55)
	_library[&"knife_heavy"] = _whoosh(0.4, 380.0, 1700.0, 0.7)
	_library[&"knife_draw"] = _shing(0.55, 0.45)
	_library[&"knife_hit"] = _thump(0.14, 110.0, 30.0, 0.9)
	_library[&"knife_wall"] = _tones([[2650.0, 0.0, 0.2], [3980.0, 0.0, 0.14], [5310.0, 0.0, 0.08]], 0.3, 16.0, 0.5)

	# feedback on your own shots
	_library[&"hit_body"] = _tones([[1800.0, 0.0, 0.05]], 0.06, 60.0, 0.5)
	_library[&"hit_head"] = _tones([[2300.0, 0.0, 0.22], [3450.0, 0.0, 0.18]], 0.24, 14.0, 0.4)
	_library[&"kill"] = _tones([[1320.0, 0.0, 0.12], [880.0, 0.09, 0.3]], 0.4, 9.0, 0.6)
	_library[&"hurt"] = _thump(0.18, 70.0, 18.0, 0.9)

	# movement
	_library[&"step"] = _footstep()
	_library[&"land"] = _thump(0.16, 60.0, 22.0, 0.8)

	# objective and ability
	_library[&"core_beep"] = _beep(1480.0, 0.07)
	_library[&"core_planted"] = _tones([[660.0, 0.0, 0.15], [990.0, 0.12, 0.35]], 0.5, 6.0, 0.6)
	_library[&"core_defused"] = _tones([[990.0, 0.0, 0.12], [1320.0, 0.1, 0.12], [1760.0, 0.2, 0.4]], 0.62, 6.0, 0.55)
	_library[&"core_detonate"] = _boom(1.6, 0.7)
	_library[&"echo_deploy"] = _sweep(320.0, 1150.0, 0.55, 0.5)
	_library[&"buy"] = _tones([[1568.0, 0.0, 0.08], [2093.0, 0.07, 0.2]], 0.3, 12.0, 0.45)
	_library[&"ui_click"] = _click(0.04, 1600.0, 0.35)

	# round stings - major key for good news, minor for bad
	_library[&"round_start"] = _tones([[440.0, 0.0, 0.18], [660.0, 0.16, 0.4]], 0.6, 5.0, 0.4)
	_library[&"fight"] = _tones([[523.0, 0.0, 0.1], [784.0, 0.0, 0.3]], 0.35, 9.0, 0.45)
	_library[&"round_win"] = _tones([[523.0, 0.0, 0.2], [659.0, 0.12, 0.2], [784.0, 0.24, 0.5]], 0.8, 4.0, 0.45)
	_library[&"round_lose"] = _tones([[392.0, 0.0, 0.25], [311.0, 0.2, 0.25], [262.0, 0.4, 0.6]], 1.0, 3.5, 0.45)
	_library[&"match_win"] = _tones([[523.0, 0.0, 0.2], [659.0, 0.15, 0.2], [784.0, 0.3, 0.2], [1047.0, 0.45, 0.9]], 1.4, 2.5, 0.45)
	_library[&"match_lose"] = _tones([[440.0, 0.0, 0.3], [349.0, 0.28, 0.3], [294.0, 0.56, 0.3], [220.0, 0.84, 0.9]], 1.8, 2.2, 0.45)
	_library[&"multikill"] = _tones([[880.0, 0.0, 0.08], [1175.0, 0.07, 0.08], [1760.0, 0.14, 0.3]], 0.45, 8.0, 0.5)


## packs mono float samples (-1..1) into a 16-bit WAV stream
func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream


func _gunshot(seconds: float, body_hz: float, brightness: float, decay: float, gain: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low := 0.0
	var high := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		low += (noise - low) * brightness * 0.25
		high += (noise - high) * 0.9
		var crack := (high - low) * exp(-t * 90.0)
		var hz := body_hz * (1.0 + 2.5 * exp(-t * 30.0))
		phase += TAU * hz / RATE
		var thump := sin(phase) * exp(-t * decay * 0.7)
		var body := low * exp(-t * decay)
		var attack := minf(t / 0.0015, 1.0)
		# scaled down so overlapping shots don't clip
		samples[i] = (crack * 0.8 + body * 1.2 + thump * 0.9) * attack * gain * 0.62
	return _to_stream(samples)


func _click(seconds: float, hz: float, gain: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var tone := sin(TAU * hz * t) * exp(-t * 90.0)
		var tick := randf_range(-1.0, 1.0) * exp(-t * 400.0)
		samples[i] = (tone * 0.6 + tick * 0.6) * gain
	return _to_stream(samples)


func _thump(seconds: float, hz: float, decay: float, gain: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		low += (randf_range(-1.0, 1.0) - low) * 0.05
		phase += TAU * hz * (1.0 + exp(-t * 25.0)) / RATE
		samples[i] = (sin(phase) * 0.8 + low * 1.5) * exp(-t * decay) * minf(t / 0.003, 1.0) * gain
	return _to_stream(samples)


func _footstep() -> AudioStreamWAV:
	var seconds := 0.11
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low := 0.0
	var mid := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		low += (noise - low) * 0.06
		mid += (noise - mid) * 0.3
		var scuff := (mid - low) * exp(-t * 60.0)
		samples[i] = (low * 2.2 * exp(-t * 35.0) + scuff * 0.5) * minf(t / 0.002, 1.0) * 0.9
	return _to_stream(samples)


## sine notes: each [frequency, start, length], soft attack + exponential
## tail, plus a quiet octave for body.
func _tones(notes: Array, seconds: float, decay: float, gain: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for note: Array in notes:
		var hz: float = note[0]
		var start := int(float(note[1]) * RATE)
		var length := int(float(note[2]) * RATE)
		var tail := int(length * 1.8)
		for j in tail:
			var i := start + j
			if i >= count:
				break
			var t := float(j) / RATE
			var env := minf(t / 0.004, 1.0) * exp(-t * decay)
			if j > length:
				env *= exp(-float(j - length) / RATE * 20.0)
			samples[i] += (sin(TAU * hz * t) + 0.25 * sin(TAU * hz * 2.0 * t)) * env * gain
	return _to_stream(samples)


func _beep(hz: float, seconds: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var wave := sin(TAU * hz * t)
		var square := 1.0 if wave >= 0.0 else -1.0
		samples[i] = (wave * 0.6 + square * 0.15) * minf(t / 0.002, 1.0) * exp(-t * 25.0) * 0.7
	return _to_stream(samples)


func _sweep(from_hz: float, to_hz: float, seconds: float, gain: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var k := t / seconds
		phase += TAU * lerpf(from_hz, to_hz, k * k) / RATE
		var tremolo := 0.75 + 0.25 * sin(TAU * 18.0 * t)
		var env := minf(t / 0.02, 1.0) * (1.0 - k)
		samples[i] = sin(phase) * tremolo * env * gain
	return _to_stream(samples)


## air torn by a blade: noise band sweeps up then back down over seconds
func _whoosh(seconds: float, low_hz: float, high_hz: float, gain: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	var lp2 := 0.0
	for i in count:
		var k := float(i) / count
		var hz := lerpf(low_hz, high_hz, sin(PI * k))
		var alpha := clampf(TAU * hz / RATE, 0.0, 1.0)
		var noise := randf_range(-1.0, 1.0)
		lp += (noise - lp) * alpha
		lp2 += (lp - lp2) * alpha * 0.5
		var env := pow(sin(PI * k), 1.6)
		samples[i] = (lp - lp2) * env * gain * 3.0
	return _to_stream(samples)


## steel drawn from a sheath: a scrape, then ringing partials
func _shing(seconds: float, gain: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var hp := 0.0
	var last := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		hp = 0.92 * (hp + noise - last)
		last = noise
		var scrape := hp * clampf(t / 0.12, 0.0, 1.0) * exp(-maxf(t - 0.12, 0.0) * 40.0) * 0.35
		var ring := 0.0
		if t > 0.1:
			var r := t - 0.1
			var partials := sin(TAU * 3120.0 * r) * 0.5 + sin(TAU * 4710.0 * r) * 0.3 + sin(TAU * 6240.0 * r) * 0.2
			ring = partials * exp(-r * 7.0) * minf(r / 0.005, 1.0)
		samples[i] = (scrape + ring * 0.5) * gain
	return _to_stream(samples)


## real recorded gunshots (CC0), replacing the synthesized ones by name.
## _far takes are miked further off, used for other players' shots.
const RECORDINGS := ["shot_rifle", "shot_rifle_far", "shot_smg", "shot_smg_far", "shot_burst",
	"shot_burst_far", "shot_pistol", "shot_pistol_far"]


## drop your own wavs in weapons_custom/ named after any sound in the
## library (shot_rifle, reload_in, rack, ...) and they replace it.
const CUSTOM_DIR := "res://assets/audio/weapons_custom"


func _load_recordings() -> void:
	for sound in RECORDINGS:
		var path := "res://assets/audio/weapons/%s.wav" % sound
		if ResourceLoader.exists(path):
			_library[StringName(sound)] = load(path)
	# overrides: wav, mp3 or ogg. exported builds list "x.wav.import" rather
	# than "x.wav". a file godot can't read is skipped with a warning.
	for file in DirAccess.get_files_at(CUSTOM_DIR):
		var clean := file.trim_suffix(".import").trim_suffix(".remap")
		if not clean.get_extension().to_lower() in ["wav", "mp3", "ogg"]:
			continue
		var path := CUSTOM_DIR + "/" + clean
		var stream: AudioStream = null
		if ResourceLoader.exists(path):
			stream = ResourceLoader.load(path, "AudioStream") as AudioStream
		if stream == null:
			push_warning("Audio: couldn't load %s - is it really a %s file, and has the editor imported it?"
				% [clean, clean.get_extension().to_upper()])
			continue
		_library[StringName(clean.get_basename())] = stream


## grenade venting smoke: steady filtered hiss
func _hiss(seconds: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	var last := 0.0
	for i in count:
		var noise := randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.4
		var hp := lp - last
		last = lp
		samples[i] = hp * 1.2
	return _to_stream(samples)


func _looped(stream: AudioStreamWAV) -> AudioStreamWAV:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	return stream


## round passing close: sharp supersonic snap with a short hiss behind it
func _crack() -> AudioStreamWAV:
	var count := int(0.16 * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var hp := 0.0
	var last := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + noise - last)
		last = noise
		var snap := hp * exp(-t * 160.0) * 1.4
		var hiss := hp * exp(-t * 28.0) * 0.25
		samples[i] = clampf(snap + hiss, -1.0, 1.0) * 0.9
	return _to_stream(samples)


## the shot echoing off walls and hills: dull decaying rumble, soft start,
## swells then dies.
func _echo_tail(seconds: float, gain: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	var lp2 := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.06
		lp2 += (lp - lp2) * 0.08
		var env := minf(t / 0.12, 1.0) * exp(-t * 3.2)
		# two or three slaps as it bounces back off different distances
		var slaps := 1.0 + 0.8 * exp(-absf(t - 0.25) * 40.0) + 0.5 * exp(-absf(t - 0.55) * 30.0)
		samples[i] = lp2 * env * slaps * gain * 6.0
	return _to_stream(samples)


## distant artillery: deep thump and a long rolling rumble
func _distant_boom() -> AudioStreamWAV:
	var seconds := 3.2
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.03
		lp2 += (lp - lp2) * 0.05
		phase += TAU * (38.0 + 20.0 * exp(-t * 4.0)) / RATE
		var thump := sin(phase) * exp(-t * 3.5) * 0.7
		var rumble := lp2 * 9.0 * minf(t / 0.05, 1.0) * exp(-t * 1.1)
		samples[i] = clampf(thump + rumble, -1.0, 1.0) * 0.8
	return _to_stream(samples)


## distant rifle burst from another fight: dulled cracks with the echo
## smeared together.
func _distant_burst() -> AudioStreamWAV:
	var seconds := 2.6
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var shots: Array[float] = []
	var at := 0.05
	for n in randi_range(4, 9):
		shots.append(at)
		at += randf_range(0.08, 0.13)
	var lp := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.12
		var v := 0.0
		for s in shots:
			if t >= s:
				var r := t - s
				v += exp(-r * 45.0) * 1.0 + exp(-r * 5.0) * 0.12
		samples[i] = clampf(lp * v * 2.2, -1.0, 1.0) * 0.8
	return _to_stream(samples)


## wind over open ground: slow filtered noise with gusts
func _wind(seconds: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	var lp2 := 0.0
	for i in count:
		var t := float(i) / RATE
		var k := t / seconds
		# gusts line up at the loop point
		var gust := 0.55 + 0.3 * sin(TAU * k * 2.0) + 0.15 * sin(TAU * k * 5.0 + 1.3)
		var noise := randf_range(-1.0, 1.0)
		lp += (noise - lp) * (0.02 + 0.03 * gust)
		lp2 += (lp - lp2) * 0.3
		samples[i] = (lp - lp2 * 0.5) * gust * 3.2
	# crossfade the ends so the loop is seamless
	var fade := int(0.4 * RATE)
	for i in fade:
		var w := float(i) / fade
		samples[i] = samples[i] * w + samples[count - fade + i] * (1.0 - w)
	samples.resize(count - fade)
	return _to_stream(samples)


## wood fire: soft roar with random pops
func _crackle(seconds: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var lp := 0.0
	var pop := 0.0
	for i in count:
		var noise := randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.05
		if randf() < 0.0009:
			pop = randf_range(0.4, 1.0)
		pop *= 0.985
		samples[i] = lp * 1.4 + noise * pop * 0.5
	return _to_stream(samples)


## charging handle: two metal clacks, back and forward
func _rack() -> AudioStreamWAV:
	var seconds := 0.3
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var v := 0.0
		for at: float in [0.0, 0.16]:
			if t >= at:
				var r := t - at
				v += (sin(TAU * 1450.0 * r) * 0.5 + randf_range(-1.0, 1.0) * 0.7) * exp(-r * 70.0)
		samples[i] = v * 0.6
	return _to_stream(samples)


func _boom(seconds: float, gain: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low := 0.0
	var mid := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		low += (noise - low) * 0.02
		mid += (noise - mid) * 0.15
		phase += TAU * (35.0 + 70.0 * exp(-t * 4.0)) / RATE
		var rumble := sin(phase) * exp(-t * 2.2)
		var blast := mid * exp(-t * 9.0)
		samples[i] = (rumble * 0.9 + low * 3.0 * exp(-t * 1.8) + blast * 0.8) * minf(t / 0.004, 1.0) * gain
	return _to_stream(samples)
