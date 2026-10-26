extends Node

## 无头音效测试：不依赖音频设备，检查音效库、池上限、冷却、静音与事件接线。
## 运行：
## godot --headless --fixed-fps 60 --path . res://tests/audio_test.tscn

var _failures := 0


func _ready() -> void:
	await get_tree().process_frame

	print("AUDIO sounds=%d voices=%d volume=%.2f muted=%s" % [
		Audio.sound_ids().size(), Audio.VOICE_COUNT, Audio.volume(), Audio.is_muted()
	])
	_check(Audio.sound_ids().size() >= 20, "sound library has at least 20 effects")
	_check(Audio.sound_ids().size() == Audio.SOUND_DEFS.size(), "every defined sound has an id")
	print("AUDIO shoot stream=%s" % Audio.stream_for(&"shoot").get_class())

	# 每个音效都必须有可播放的流；内置 WAV 还要有非空 PCM 数据。
	var empty_streams := 0
	for id in Audio.sound_ids():
		var stream := Audio.stream_for(id)
		if stream == null:
			empty_streams += 1
			continue
		if stream is AudioStreamWAV and (stream as AudioStreamWAV).data.is_empty():
			empty_streams += 1
	_check(empty_streams == 0, "all sounds have non-empty streams")

	# 生成音都有自己的合成兜底；直接调用一次，确保兜底路径不会返回空流。
	var synth_empty := 0
	for id in [&"hit", &"weak_hit", &"crit", &"soul", &"level_up", &"super_crit", &"chest"]:
		var synth := Audio._synth(id)
		if synth == null or synth.data.is_empty():
			synth_empty += 1
	_check(synth_empty == 0, "generated sounds have non-empty synth fallbacks")

	# 冷却：第一声成功，立刻重播被抑制；清空冷却后可以再响。
	# 用 200ms 冷却的 hurt，避免首次加载 OGG 的冷启动开销造成测试抖动。
	var was_muted := Audio.is_muted()
	Audio.set_muted(false)
	Audio.reset_throttle()
	_check(Audio.play(&"hurt"), "first hurt plays")
	_check(not Audio.play(&"hurt"), "immediate duplicate hurt is throttled")
	Audio.reset_throttle()
	_check(Audio.play(&"hurt"), "hurt plays again after throttle reset")

	# 静音：play() 直接拒绝，不占用声部。
	Audio.set_muted(true)
	Audio.reset_throttle()
	_check(not Audio.play(&"gold"), "muted audio refuses playback")
	Audio.set_muted(false)

	# 大量并发请求不能超过固定声部上限（无设备时 playing 可能立即回落）。
	Audio.reset_throttle()
	for i in 120:
		Audio.reset_throttle()
		Audio.play(Audio.sound_ids()[i % Audio.sound_ids().size()])
	_check(Audio.active_voice_count() <= Audio.VOICE_COUNT, "voice pool stays within cap")

	# EventBus 低频事件应触发声音；未开局时的 color_changed 不应响。
	Audio.reset_throttle()
	var before := Audio.play_count()
	EventBus.player_dodged.emit()
	_check(Audio.play_count() == before + 1, "player_dodged triggers a sound")

	RunState.is_running = false
	Audio.reset_throttle()
	before = Audio.play_count()
	EventBus.color_changed.emit(0)
	_check(Audio.play_count() == before, "color_changed before run start is silent")

	Audio.shutdown()
	Audio.set_muted(was_muted)
	print("AUDIO %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("AUDIO PASS: %s" % label)
	else:
		_failures += 1
		print("AUDIO FAIL: %s" % label)
