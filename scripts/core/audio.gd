extends Node
## Sound. Registered as the [code]Audio[/code] autoload.
##
## [b]Every sound is synthesised here at startup[/b] - noise bursts, filtered
## thumps and tuned tones - so the game has a full, consistent soundscape with
## no asset files and no licensing to track. They are placeholders in the sense
## that the art pass may replace them with recorded ones: [method play] and
## [method play_at] take a sound's name, so swapping one in means loading a file
## into [member _library] under the same name and nothing else changes.
##
## Two ways to play:
## - [method play]: flat, for things that happen to you - your own gun, hit
##   confirmations, UI, round stings.
## - [method play_at]: positioned in the world and heard through the current
##   camera, for everything a tactical player needs to locate - other players'
##   shots and footsteps, the planted core.
##
## Volume follows [code]GameConfig.master_volume[/code].

const RATE := 22050

## Name -> AudioStreamWAV.
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
			_apply_volume())
	_build_library()


func _apply_volume() -> void:
	var volume := clampf(GameConfig.master_volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)


# --- Playing ------------------------------------------------------------------

## Plays [param sound_name] flat (not positioned). [param volume_db] and a
## random pitch spread keep repeated sounds from sounding mechanical.
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


## Plays [param sound_name] at [param position] in the world. Distance
## attenuates it and muffles the high end, so a far shot sounds far.
func play_at(sound_name: StringName, position: Vector3, volume_db: float = 0.0,
		pitch_spread: float = 0.04, reach: float = 60.0) -> void:
	var stream: AudioStream = _library.get(sound_name)
	if stream == null or _world_voices >= MAX_WORLD_VOICES:
		return
	# Parented to the match scene when there is one, so a sound cut off by the
	# match ending stops with it.
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
	# Weapons: a filtered noise crack over a falling low thump. Heavier guns get
	# a lower, longer body.
	_library[&"shot_rifle"] = _gunshot(0.34, 95.0, 0.35, 16.0, 1.0)
	_library[&"shot_smg"] = _gunshot(0.22, 130.0, 0.45, 24.0, 0.85)
	_library[&"shot_pistol"] = _gunshot(0.24, 150.0, 0.55, 22.0, 0.9)
	_library[&"shot_burst"] = _gunshot(0.28, 110.0, 0.4, 19.0, 0.95)
	_library[&"dry_fire"] = _click(0.05, 2200.0, 0.5)
	_library[&"reload_out"] = _click(0.08, 900.0, 0.8)
	_library[&"reload_in"] = _click(0.1, 1300.0, 1.0)
	_library[&"switch"] = _click(0.09, 700.0, 0.6)

	# Feedback on your own shots.
	_library[&"hit_body"] = _tones([[1800.0, 0.0, 0.05]], 0.06, 60.0, 0.5)
	_library[&"hit_head"] = _tones([[2300.0, 0.0, 0.22], [3450.0, 0.0, 0.18]], 0.24, 14.0, 0.4)
	_library[&"kill"] = _tones([[1320.0, 0.0, 0.12], [880.0, 0.09, 0.3]], 0.4, 9.0, 0.6)
	_library[&"hurt"] = _thump(0.18, 70.0, 18.0, 0.9)

	# Movement.
	_library[&"step"] = _footstep()
	_library[&"land"] = _thump(0.16, 60.0, 22.0, 0.8)

	# Objective and ability.
	_library[&"core_beep"] = _beep(1480.0, 0.07)
	_library[&"core_planted"] = _tones([[660.0, 0.0, 0.15], [990.0, 0.12, 0.35]], 0.5, 6.0, 0.6)
	_library[&"core_defused"] = _tones([[990.0, 0.0, 0.12], [1320.0, 0.1, 0.12], [1760.0, 0.2, 0.4]], 0.62, 6.0, 0.55)
	_library[&"core_detonate"] = _boom(1.6, 0.7)
	_library[&"echo_deploy"] = _sweep(320.0, 1150.0, 0.55, 0.5)
	_library[&"buy"] = _tones([[1568.0, 0.0, 0.08], [2093.0, 0.07, 0.2]], 0.3, 12.0, 0.45)
	_library[&"ui_click"] = _click(0.04, 1600.0, 0.35)

	# Round stings - short tonal cues, major for good news, minor for bad.
	_library[&"round_start"] = _tones([[440.0, 0.0, 0.18], [660.0, 0.16, 0.4]], 0.6, 5.0, 0.4)
	_library[&"fight"] = _tones([[523.0, 0.0, 0.1], [784.0, 0.0, 0.3]], 0.35, 9.0, 0.45)
	_library[&"round_win"] = _tones([[523.0, 0.0, 0.2], [659.0, 0.12, 0.2], [784.0, 0.24, 0.5]], 0.8, 4.0, 0.45)
	_library[&"round_lose"] = _tones([[392.0, 0.0, 0.25], [311.0, 0.2, 0.25], [262.0, 0.4, 0.6]], 1.0, 3.5, 0.45)
	_library[&"match_win"] = _tones([[523.0, 0.0, 0.2], [659.0, 0.15, 0.2], [784.0, 0.3, 0.2], [1047.0, 0.45, 0.9]], 1.4, 2.5, 0.45)
	_library[&"match_lose"] = _tones([[440.0, 0.0, 0.3], [349.0, 0.28, 0.3], [294.0, 0.56, 0.3], [220.0, 0.84, 0.9]], 1.8, 2.2, 0.45)
	_library[&"multikill"] = _tones([[880.0, 0.0, 0.08], [1175.0, 0.07, 0.08], [1760.0, 0.14, 0.3]], 0.45, 8.0, 0.5)


## Packs mono float samples (-1..1) into a 16-bit WAV stream.
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
		# Scaled to leave headroom: several shots overlapping must not clip.
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


## Several sine notes: each [frequency, start, length] with a soft attack and an
## exponential tail, plus a quiet octave for body.
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
