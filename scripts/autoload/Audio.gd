extends Node

## 全局音效。原型阶段不依赖音频素材：启动时为每个 id 合成一段短 WAV，
## 放进固定数量的 AudioStreamPlayer 复用（不在命中时创建节点/音频流）。
##
## 替换正式素材：把同名文件放到 assets/audio/sfx/<id>.wav 或 .ogg 即可，
## 这里的加载顺序是“外部文件优先 → 内置合成兜底”，代码不用改。
## 同名时 .wav 优先于 .ogg，便于用生成的低频 8-bit 音覆盖旧素材而不删文件。
## 具体文件名、推荐素材来源与授权见 docs/AUDIO.md。

const MIX_RATE := 22050
const VOICE_COUNT := 20
const SFX_DIR := "res://assets/audio/sfx"
const SETTINGS_PATH := "user://audio.cfg"
const DEFAULT_VOLUME := 0.8

## 冷却用于抑制霰弹/连射/成群击杀造成的同帧叠音；jitter 让重复音不机械。
const SOUND_DEFS: Dictionary = {
	&"weapon_basic": {"cooldown": 100, "jitter": 0.03, "db": -7.0},
	&"weapon_hit_basic": {"cooldown": 85, "jitter": 0.04, "db": -10.0},
	&"weapon_sword": {"cooldown": 100, "jitter": 0.03, "db": -7.0},
	&"weapon_hit_sword": {"cooldown": 85, "jitter": 0.04, "db": -10.0},
	&"weapon_scythe": {"cooldown": 100, "jitter": 0.03, "db": -7.0},
	&"weapon_hit_scythe": {"cooldown": 85, "jitter": 0.04, "db": -10.0},
	&"weapon_wave": {"cooldown": 100, "jitter": 0.03, "db": -7.0},
	&"weapon_hit_wave": {"cooldown": 85, "jitter": 0.04, "db": -10.0},
	&"weapon_boomerang": {"cooldown": 100, "jitter": 0.03, "db": -7.0},
	&"weapon_hit_boomerang": {"cooldown": 85, "jitter": 0.04, "db": -10.0},
	&"weapon_sprite": {"cooldown": 100, "jitter": 0.03, "db": -7.0},
	&"weapon_hit_sprite": {"cooldown": 85, "jitter": 0.04, "db": -10.0},
	&"weapon_star": {"cooldown": 100, "jitter": 0.03, "db": -7.0},
	&"weapon_hit_star": {"cooldown": 85, "jitter": 0.04, "db": -10.0},
	&"weapon_lightning": {"cooldown": 100, "jitter": 0.03, "db": -7.0},
	&"weapon_hit_lightning": {"cooldown": 85, "jitter": 0.04, "db": -10.0},
	&"weapon_cannon": {"cooldown": 100, "jitter": 0.03, "db": -7.0},
	&"weapon_hit_cannon": {"cooldown": 85, "jitter": 0.04, "db": -10.0},
	&"weapon_black_hole": {"cooldown": 100, "jitter": 0.03, "db": -7.0},
	&"weapon_hit_black_hole": {"cooldown": 85, "jitter": 0.04, "db": -10.0},

	&"shoot": {"cooldown": 40, "jitter": 0.05, "db": -4.0},
	&"shoot_heavy": {"cooldown": 120, "jitter": 0.02, "db": -1.0},
	&"hit": {"cooldown": 40, "jitter": 0.10, "db": -8.0},
	&"hit_heavy": {"cooldown": 90, "jitter": 0.05, "db": -2.0},
	&"weak_hit": {"cooldown": 60, "jitter": 0.07, "db": -6.0},
	&"crit": {"cooldown": 70, "jitter": 0.05, "db": -5.0},
	&"super_crit": {"cooldown": 140, "jitter": 0.02, "db": -2.0},
	&"kill": {"cooldown": 65, "jitter": 0.10, "db": -7.0},
	&"soul": {"cooldown": 400, "jitter": 0.03, "db": -5.0},
	&"gold": {"cooldown": 55, "jitter": 0.05, "db": -7.0},
	&"xp": {"cooldown": 45, "jitter": 0.04, "db": -9.0},
	&"chest": {"cooldown": 200, "jitter": 0.0, "db": -2.0},
	&"heal": {"cooldown": 200, "jitter": 0.0, "db": -3.0},
	&"hurt": {"cooldown": 200, "jitter": 0.0, "db": -1.0},
	&"dodge": {"cooldown": 160, "jitter": 0.06, "db": -4.0},
	&"level_up": {"cooldown": 300, "jitter": 0.0, "db": -2.0},
	&"color_switch": {"cooldown": 90, "jitter": 0.03, "db": -4.0},
	&"merchant": {"cooldown": 500, "jitter": 0.0, "db": -3.0},
	&"shop_open": {"cooldown": 400, "jitter": 0.0, "db": -3.0},
	&"altar_spawn": {"cooldown": 500, "jitter": 0.0, "db": -2.0},
	&"altar_trade": {"cooldown": 300, "jitter": 0.0, "db": -1.0},
	&"ui_click": {"cooldown": 25, "jitter": 0.02, "db": -8.0},
	&"ui_buy": {"cooldown": 60, "jitter": 0.0, "db": -5.0},
	&"game_over": {"cooldown": 1000, "jitter": 0.0, "db": -1.0},
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _last_play_ms: Dictionary = {}
var _next_voice := 0
var _volume := DEFAULT_VOLUME
var _muted := false
var _rng := RandomNumberGenerator.new()
var _plays := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_streams()
	_build_voices()
	_load_settings()

	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_dodged.connect(_on_player_dodged)
	EventBus.player_died.connect(_on_player_died)
	EventBus.level_up.connect(_on_level_up)
	EventBus.color_changed.connect(_on_color_changed)
	EventBus.merchant_spawned.connect(_on_merchant_spawned)
	EventBus.merchant_reached.connect(_on_merchant_reached)
	EventBus.altar_spawned.connect(_on_altar_spawned)


## 播放一个音效。返回 false 表示被静音、id 不存在或处于冷却中。
func play(id: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	if _muted:
		return false
	if not _streams.has(id):
		return false

	var definition: Dictionary = SOUND_DEFS.get(id, {})
	var now := Time.get_ticks_msec()
	var cooldown := int(definition.get("cooldown", 0))
	if cooldown > 0 and now - int(_last_play_ms.get(id, -100000)) < cooldown:
		return false
	_last_play_ms[id] = now

	var player := _take_voice()
	var jitter := float(definition.get("jitter", 0.0))
	player.stream = _streams[id] as AudioStream
	player.volume_db = volume_db + float(definition.get("db", 0.0))
	player.pitch_scale = maxf(0.05, pitch * (1.0 + _rng.randf_range(-jitter, jitter)))
	player.play()
	_plays += 1
	return true


func has_sound(id: StringName) -> bool:
	return _streams.has(id)


func sound_ids() -> Array:
	return SOUND_DEFS.keys()


func stream_for(id: StringName) -> AudioStream:
	return _streams.get(id) as AudioStream


func active_voice_count() -> int:
	var count := 0
	for player in _players:
		if player.playing:
			count += 1
	return count


## 测试/调试用：清空冷却记录，让同一个音效可以立刻再次播放。
func reset_throttle() -> void:
	_last_play_ms.clear()


## 停止所有声部（重开场景/退出测试时调用，避免残留播放）。
func stop_all() -> void:
	for player in _players:
		player.stop()


## 停止、解除声部对音频流的引用并清空缓存；只应在退出/彻底重置音频时调用。
## 这样测试进程退出时不会把 OGG 播放对象留在 ObjectDB 里。
func shutdown() -> void:
	stop_all()
	for player in _players:
		player.stream = null
	_streams.clear()


func play_count() -> int:
	return _plays


func set_muted(value: bool) -> void:
	_muted = value
	_apply_bus_mute()
	_save_settings()


func is_muted() -> bool:
	return _muted


func toggle_muted() -> bool:
	set_muted(not _muted)
	return _muted


func set_volume(value: float) -> void:
	_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume()
	_save_settings()


func volume() -> float:
	return _volume


# ── 内部 ────────────────────────────────────────────────────────

func _build_streams() -> void:
	_streams.clear()
	for id in SOUND_DEFS.keys():
		var external := _load_external(id)
		_streams[id] = external if external != null else _synth(id)


func _build_voices() -> void:
	_players.clear()
	for i in VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % i
		player.bus = &"Master"
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players.append(player)


## 外部素材优先；同名 wav/ogg 同时存在时 wav 优先，方便覆盖旧素材而不删文件。
func _load_external(id: StringName) -> AudioStream:
	for extension in ["wav", "ogg"]:
		var path := "%s/%s.%s" % [SFX_DIR, String(id), extension]
		if not ResourceLoader.exists(path):
			continue
		var resource := load(path)
		if resource is AudioStream:
			return resource as AudioStream
	return null


func _take_voice() -> AudioStreamPlayer:
	for offset in VOICE_COUNT:
		var index := (_next_voice + offset) % VOICE_COUNT
		var player := _players[index]
		if not player.playing:
			_next_voice = (index + 1) % VOICE_COUNT
			return player

	# 全部占用时抢占最早的下一个声部，保证总声部数恒定。
	var stolen := _players[_next_voice]
	_next_voice = (_next_voice + 1) % VOICE_COUNT
	stolen.stop()
	return stolen


func _synth(id: StringName) -> AudioStreamWAV:
	match id:
		&"weapon_basic":
			return _tone(0.06, 430.0, 210.0, 0.18, 0.015, 0.03, 0.0)
		&"weapon_hit_basic":
			return _tone(0.07, 168.0, 84.0, 0.16, 0.004, 0.65, 0.0)
		&"weapon_sword":
			return _tone(0.2, 900.0, 220.0, 0.22, 0.015, 0.92, 0.0)
		&"weapon_hit_sword":
			return _tone(0.07, 176.0, 88.0, 0.16, 0.004, 0.65, 0.0)
		&"weapon_scythe":
			return _tone(0.42, 440.0, 100.0, 0.25, 0.015, 0.96, 0.0)
		&"weapon_hit_scythe":
			return _tone(0.07, 80.0, 40.0, 0.16, 0.004, 0.65, 0.0)
		&"weapon_wave":
			return _tone(0.25, 680.0, 240.0, 0.17, 0.015, 0.85, 0.0)
		&"weapon_hit_wave":
			return _tone(0.07, 192.0, 96.0, 0.16, 0.004, 0.65, 0.0)
		&"weapon_boomerang":
			return _tone(0.16, 350.0, 760.0, 0.16, 0.015, 0.66, 0.0)
		&"weapon_hit_boomerang":
			return _tone(0.07, 608.0, 304.0, 0.16, 0.004, 0.65, 0.0)
		&"weapon_sprite":
			return _tone(0.1, 1200.0, 680.0, 0.14, 0.015, 0.28, 0.0)
		&"weapon_hit_sprite":
			return _tone(0.07, 544.0, 272.0, 0.16, 0.004, 0.65, 0.0)
		&"weapon_star":
			return _tone(0.1, 1600.0, 1000.0, 0.14, 0.015, 0.15, 0.0)
		&"weapon_hit_star":
			return _tone(0.07, 800.0, 400.0, 0.16, 0.004, 0.65, 0.0)
		&"weapon_lightning":
			return _tone(0.1, 2500.0, 500.0, 0.17, 0.015, 0.84, 0.0)
		&"weapon_hit_lightning":
			return _tone(0.07, 400.0, 200.0, 0.16, 0.004, 0.65, 0.0)
		&"weapon_cannon":
			return _tone(0.2, 130.0, 48.0, 0.32, 0.015, 0.42, 0.0)
		&"weapon_hit_cannon":
			return _tone(0.07, 38.400000000000006, 19.200000000000003, 0.16, 0.004, 0.65, 0.0)
		&"weapon_black_hole":
			return _tone(0.3, 100.0, 55.0, 0.19, 0.015, 0.15, 0.0)
		&"weapon_hit_black_hole":
			return _tone(0.07, 44.0, 22.0, 0.16, 0.004, 0.65, 0.0)
		&"shoot":
			return _tone(0.075, 920.0, 360.0, 0.26, 0.003, 0.06, 0.30)
		&"shoot_heavy":
			return _tone(0.18, 250.0, 65.0, 0.42, 0.004, 0.16, 0.50)
		&"hit":
			return _tone(0.075, 185.0, 92.0, 0.24, 0.002, 0.0, 0.86)
		&"hit_heavy":
			return _tone(0.10, 420.0, 120.0, 0.30, 0.002, 0.45, 0.25)
		&"weak_hit":
			return _sequence([196.0, 293.66], 0.018, 0.045, 0.18, 0.80)
		&"crit":
			return _sequence([261.63, 392.0, 523.25], 0.020, 0.042, 0.18, 0.80)
		&"super_crit":
			return _impact_shine()
		&"kill":
			return _tone(0.20, 280.0, 55.0, 0.26, 0.003, 0.42, 0.18)
		&"soul":
			return _hum(0.62, 82.41, 0.16)
		&"gold":
			return _sequence([1568.0, 2093.0], 0.045, 0.055, 0.16, 0.10)
		&"xp":
			return _sequence([1760.0], 0.04, 0.055, 0.11, 0.0)
		&"chest":
			# 柔和的上行钟音，不再用刺耳的长上扬采样。
			return _sequence([523.25, 659.25, 783.99, 1046.5], 0.060, 0.14, 0.22, 0.10)
		&"heal":
			return _sequence([659.25, 880.0, 1108.73], 0.06, 0.09, 0.18, 0.0)
		&"hurt":
			return _tone(0.24, 200.0, 50.0, 0.38, 0.002, 0.30, 0.55)
		&"dodge":
			return _tone(0.15, 1100.0, 2600.0, 0.12, 0.008, 0.55, 0.0)
		&"level_up":
			# 上行四音，短促；最后一音带一点上滑，不做从高到低的收尾。
			return _sequence([523.25, 659.25, 783.99, 1046.5], 0.040, 0.055, 0.24, 0.45)
		&"color_switch":
			return _tone(0.22, 260.0, 980.0, 0.18, 0.015, 0.22, 0.0)
		&"merchant":
			return _sequence([783.99, 1046.5, 1318.5], 0.075, 0.11, 0.18, 0.06)
		&"shop_open":
			return _sequence([392.0, 523.25, 659.25], 0.055, 0.08, 0.16, 0.04)
		&"altar_spawn":
			return _tone(0.42, 98.0, 146.83, 0.18, 0.08, 0.10, 0.22)
		&"altar_trade":
			return _sequence([329.63, 440.0, 554.37], 0.09, 0.16, 0.24, 0.22)
		&"ui_click":
			return _tone(0.035, 1900.0, 1500.0, 0.10, 0.001, 0.0, 0.55)
		&"ui_buy":
			return _sequence([1046.5, 1318.5], 0.045, 0.055, 0.18, 0.18)
		&"game_over":
			return _sequence([392.0, 311.13, 233.08], 0.20, 0.26, 0.28, 0.28)
		_:
			return _tone(0.05, 440.0, 440.0, 0.12, 0.002, 0.0, 0.0)


## 单音：f0 → f1 的滑音，带噪声/方波混合和短促衰减。
func _tone(
	duration: float,
	f0: float,
	f1: float,
	amp: float,
	attack: float,
	noise_mix: float,
	square_mix: float
) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	var attack_samples := maxf(1.0, attack * MIX_RATE)
	var noise := RandomNumberGenerator.new()
	noise.seed = int(hash("%.2f|%.2f|%.4f" % [f0, f1, duration])) & 0x7fffffff
	var noise_amount := clampf(noise_mix, 0.0, 1.0)
	var square_amount := clampf(square_mix, 0.0, 1.0)

	for i in count:
		var t := float(i) / float(count)
		var frequency := lerpf(f0, f1, t * t)
		phase += TAU * frequency / float(MIX_RATE)
		var sine := sin(phase)
		var sample := sine * (1.0 - square_amount) + signf(sine) * square_amount
		sample = sample * (1.0 - noise_amount) + noise.randf_range(-1.0, 1.0) * noise_amount
		var envelope := minf(1.0, float(i) / attack_samples) * pow(1.0 - t, 2.0)
		var value := int(clampf(sample * envelope * amp, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)

	return _make_wav(data)


## 琶音/和弦：一串音高按 step 依次起音，用于拾取、升级、UI 反馈。
func _sequence(
	frequencies: Array,
	step: float,
	note_length: float,
	amp: float,
	square_mix: float
) -> AudioStreamWAV:
	var duration := step * float(frequencies.size()) + note_length
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var square_amount := clampf(square_mix, 0.0, 1.0)

	for i in count:
		var time := float(i) / float(MIX_RATE)
		var sample := 0.0
		for n in frequencies.size():
			var start := step * float(n)
			var local_time := time - start
			if local_time < 0.0 or local_time > note_length:
				continue

			var local := local_time / note_length
			var frequency := float(frequencies[n])
			var sine := sin(TAU * frequency * time)
			var tone := sine * (1.0 - square_amount) + signf(sine) * square_amount
			var envelope := minf(1.0, local * 30.0) * pow(1.0 - local, 2.2)
			sample += tone * envelope

		var value := int(clampf(sample * amp, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)

	return _make_wav(data)


## 低频嗡鸣：两个略微失谐的低音相互拍频，叠 4 Hz 颤音与慢起慢收，
## 用于灵魂震荡这类“持续存在”的技能反馈，不用短促的打击音。
func _hum(duration: float, base_frequency: float, amp: float) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase_a := 0.0
	var phase_b := 0.0
	for i in count:
		var time := float(i) / float(MIX_RATE)
		var t := float(i) / float(count)
		var frequency_a := base_frequency * (1.0 + 0.0025 * sin(TAU * 3.1 * time))
		var frequency_b := base_frequency * 1.008
		phase_a += TAU * frequency_a / float(MIX_RATE)
		phase_b += TAU * frequency_b / float(MIX_RATE)
		var sample := sin(phase_a) * 0.55 + sin(phase_b) * 0.30
		sample += sin(phase_a * 2.0) * 0.16 + sin(phase_b * 3.0) * 0.06
		sample += signf(sin(phase_a)) * 0.05
		var tremolo := 0.78 + 0.22 * sin(TAU * 4.0 * time - PI * 0.5)
		var attack := minf(1.0, time / 0.09)
		var release := clampf((duration - time) / 0.24, 0.0, 1.0)
		var envelope := attack * pow(release, 1.4)
		var value := int(clampf(sample * tremolo * envelope * amp, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	return _make_wav(data)


## 超暴击：低频冲击 + 高频闪光 + 极短噪声裂口，三层同时起音，短而重。
func _impact_shine() -> AudioStreamWAV:
	var duration := 0.24
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var low_phase := 0.0
	var high_phase := 0.0
	var noise := RandomNumberGenerator.new()
	noise.seed = 20261022

	for i in count:
		var time := float(i) / float(MIX_RATE)
		var t := time / duration
		var low_frequency := lerpf(140.0, 58.0, pow(minf(1.0, t * 1.8), 0.7))
		low_phase += TAU * low_frequency / float(MIX_RATE)
		var low_envelope := minf(1.0, time / 0.003) * pow(1.0 - t, 1.5)
		var sample := (sin(low_phase) * 0.75 + signf(sin(low_phase)) * 0.15) * low_envelope * 0.62

		if time < 0.11:
			var high_frequency := 1760.0 if time < 0.045 else 2637.0
			high_phase += TAU * high_frequency / float(MIX_RATE)
			var high_envelope := minf(1.0, time / 0.002) * pow(maxf(0.0, 1.0 - time / 0.11), 1.3)
			sample += (signf(sin(high_phase)) * 0.6 + sin(high_phase * 1.5) * 0.4) * high_envelope * 0.34

		if time < 0.022:
			sample += noise.randf_range(-1.0, 1.0) * pow(1.0 - time / 0.022, 2.0) * 0.30

		var value := int(clampf(sample * 0.82, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)

	return _make_wav(data)


func _make_wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		_apply_bus_volume()
		_apply_bus_mute()
		return
	_volume = clampf(float(config.get_value("audio", "volume", DEFAULT_VOLUME)), 0.0, 1.0)
	_muted = bool(config.get_value("audio", "muted", false))
	_apply_bus_volume()
	_apply_bus_mute()


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "volume", _volume)
	config.set_value("audio", "muted", _muted)
	config.save(SETTINGS_PATH)


func _apply_bus_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_volume, 0.0001)))


func _apply_bus_mute() -> void:
	AudioServer.set_bus_mute(0, _muted)


# ── EventBus 连线：低频、全局的事件在这里统一发声 ──────────────

func _on_player_damaged(_amount: float) -> void:
	play(&"hurt")


func _on_player_dodged() -> void:
	play(&"dodge")


func _on_player_died() -> void:
	play(&"game_over")


func _on_level_up(_level: int) -> void:
	play(&"level_up")


func _on_color_changed(_color_index: int) -> void:
	# begin_run() 也会发一次 color_changed，那一次不是切换，不要响。
	if RunState.is_running and not RunState.is_dead:
		play(&"color_switch")


func _on_merchant_spawned(_merchant: Node) -> void:
	play(&"merchant")


func _on_merchant_reached(_merchant: Node) -> void:
	play(&"shop_open")


func _on_altar_spawned(_altar: Node) -> void:
	play(&"altar_spawn")
