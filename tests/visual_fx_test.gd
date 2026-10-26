extends Node

var failures := 0


func _ready() -> void:
	var layer := Node2D.new()
	add_child(layer)
	layer.add_to_group("fx_layer")
	FX.prewarm(layer)
	var node_count := layer.get_child_count()
	for i in 12:
		FX.hit_impact(Vector2(i * 8, 0), Color(1.5, 0.5, 0.3), Vector2.RIGHT)
	var text_layer := FX._text_layer as FloatingTextLayer
	var active_impacts := 0
	for active_flag in text_layer._impact_alive:
		active_impacts += int(active_flag)
	_check(active_impacts == FloatingTextLayer.IMPACTS_PER_FRAME and layer.get_child_count() == node_count,
		"bullet impact animation uses a fixed pool and per-frame budget")
	await get_tree().create_timer(0.18).timeout
	active_impacts = 0
	for active_flag in text_layer._impact_alive:
		active_impacts += int(active_flag)
	_check(active_impacts == 0, "bullet impact animation ends quickly")
	for i in 24:
		FX.hit_burst(Vector2(i * 10, 0), Color(0.2, 0.7, 2.0), 50, 0.08, EnergyBurst.STYLE_SOUL)
	var active := 0
	var veils := 0
	for child in layer.get_children():
		if child is EnergyBurst and child.visible:
			active += 1
			if child._veil.visible:
				veils += 1
	_check(active == 24 and veils == 12, "burst budget preserves geometry and caps soft layers")
	await get_tree().create_timer(0.2).timeout
	_check(EnergyBurst._active_veils == 0, "expired pooled bursts release every veil slot")
	_check(FX._burst_pool.size() == FX.BURST_PREWARM, "all bursts return to the prewarmed pool")
	FX.hit_burst(Vector2.ZERO, Color(2, 0.1, 0.2), 35, 1, EnergyBurst.STYLE_HEAVY)
	var reused: EnergyBurst
	for child in layer.get_children():
		if child is EnergyBurst and child.visible:
			reused = child
	if reused != null:
		_check(reused._veil_material.get_shader_parameter("tint") == Color(2, 0.1, 0.2), "reuse resets the previous color")
		FX.release_burst(reused)
		FX.hit_burst(Vector2.ZERO, Color.WHITE, 22, 1, EnergyBurst.STYLE_STAR)
		_check(not reused._veil.visible and EnergyBurst._active_veils == 0, "star reuse clears the soft layer")
	else:
		_check(false, "reused burst exists")
	FX.hit_burst(Vector2.ZERO, Color.WHITE, 34, 1, EnergyBurst.STYLE_SHATTER)
	for child in layer.get_children():
		if child is EnergyBurst and child.visible and child.style == EnergyBurst.STYLE_SHATTER:
			_check(not child._veil.visible and EnergyBurst._active_veils == 0, "death fragments never activate a ring-shaped energy veil")
	var pool_before := FX._burst_pool.size()
	for i in 100:
		FX.shockwave(Vector2.ZERO, Color.WHITE, 60, 0.26, EnergyBurst.STYLE_SPLASH)
	_check(FX._burst_pool.size() == pool_before - 1, "same-frame overlapping splash visuals coalesce")
	for i in 100:
		FX.shockwave(Vector2(100 + i * 60, 0), Color.WHITE, 60, 0.26, EnergyBurst.STYLE_SPLASH)
	_check(FX._burst_pool.size() == pool_before - 4, "dense splash visuals have a four-burst reserve")
	FX.hit_burst(Vector2.ZERO, Color.WHITE, 50, 1, EnergyBurst.STYLE_SOUL)
	FX.shards(Vector2.ZERO, Color.WHITE, 6)
	FX.hit_spark(Vector2.ZERO, Color.WHITE)
	_check(not FX._shard_active.is_empty() and not FX._spark_active.is_empty(), "scene teardown starts with live particles")
	layer.queue_free()
	await get_tree().process_frame
	_check(EnergyBurst._active_veils == 0, "scene teardown releases the shared visual budget")
	await get_tree().create_timer(1.0).timeout
	_check(FX._shard_active.is_empty() and FX._spark_active.is_empty(), "freed scene particles expire without a type error")
	print("VISUAL FX %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("VISUAL FX %s: %s" % ["PASS" if ok else "FAIL", description])
