extends Node

## 临时性能探针：维持 70 个“不死”敌人并解锁全部技能，观察满负载下的 FPS。
## 敌人血量设为极大值，避免满技能输出把它们瞬间清空，从而真正压住敌人数量。
## 手工 GPU 压测，不纳入无头功能回归。

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const TARGET_ENEMIES := 70
const DURATION := 20.0
const WARMUP := 1.5
const SURVIVE_HEALTH := 1_000_000_000.0

var _main: Node
var _started := false
var _no_fire := false
var _no_flock := false
var _mortal := false
var _no_skills := false
var _no_splash := false
var _no_text := false
var _freeze := false
var _hide_enemies := false
var _with_boss := false
var _square_only := false
var _with_statuses := false
var _pickup_count := 0
var _pickup_redraw_60 := false
var _pickup_full_detail := false
var _target_enemies := TARGET_ENEMIES
var _spawn_timer := 0.0
var _remaining := DURATION
var _warmup := WARMUP
var _rng := RandomNumberGenerator.new()

var _frames := 0
var _fps_sum := 0.0
var _min_fps := 1.0e9
var _max_frame_ms := 0.0
var _frames_below_55 := 0
var _min_enemies := TARGET_ENEMIES
var _process_ms_sum := 0.0
var _physics_ms_sum := 0.0
var _max_process_ms := 0.0
var _max_physics_ms := 0.0
var _projectiles_peak := 0


func _ready() -> void:
	# 可选参数：-- --no-fire --mortal --no-skills --enemies=N
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-fire":
			_no_fire = true
		elif arg == "--no-flock":
			_no_flock = true
		elif arg == "--mortal":
			_mortal = true
		elif arg == "--no-skills":
			_no_skills = true
		elif arg == "--no-splash":
			_no_splash = true
		elif arg == "--no-text":
			_no_text = true
		elif arg == "--freeze":
			_freeze = true
		elif arg == "--hide":
			_hide_enemies = true
		elif arg == "--boss":
			_with_boss = true
		elif arg == "--squares":
			_square_only = true
		elif arg == "--statuses":
			_with_statuses = true
		elif arg == "--pickup-redraw-60":
			_pickup_redraw_60 = true
		elif arg == "--pickup-full-detail":
			_pickup_full_detail = true
		elif arg.begins_with("--pickups="):
			_pickup_count = maxi(0, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--enemies="):
			_target_enemies = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--seconds="):
			_remaining = maxf(3.0, float(arg.get_slice("=", 1)))

	_rng.seed = 20261022
	seed(20261022)
	RunState.rng.seed = 20261022
	EnemyFlock.enabled = not _no_flock
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)

	await get_tree().create_timer(2.8).timeout

	Director.stop()
	RunState.level = 1000000
	RunState.xp = 0
	_main.player.set("_invuln", 9999.0)

	if not _no_skills:
		for node in Skills.nodes:
			if _no_splash and node.branch == &"splash":
				continue
			Skills.unlock(node.id, true)

	_fill_enemies(_target_enemies)
	var pickup_field := _main.get_node_or_null("World/PickupField") as PickupField
	if pickup_field != null:
		if _pickup_redraw_60:
			pickup_field.visual_redraw_step = 1.0 / 60.0
		if _pickup_full_detail:
			pickup_field.force_full_detail = true
		for i in _pickup_count:
			var angle := TAU * float(i) / maxf(1.0, float(_pickup_count))
			pickup_field._append_item(PickupField.KIND_XP,
				_main.player.global_position + Vector2.from_angle(angle) * (220.0 + float(i % 5) * 45.0),
				1.0, 0.0)
	if _with_boss:
		RunState.elapsed = 240.0
		var boss := Director.spawn_boss_now(_main.player.global_position + Vector2(250.0, 0.0))
		if boss != null:
			boss.max_health = SURVIVE_HEALTH
			boss.health = SURVIVE_HEALTH
			boss._refresh_healthbar()
	if _no_fire:
		_main.player.controls_enabled = false
	if _no_text:
		for child in _main.fx_layer.get_children():
			if child is FloatingTextLayer:
				child.visible = false
	_min_enemies = get_tree().get_nodes_in_group("enemies").size()
	_started = true


func _process(delta: float) -> void:
	# 开场等待期间 _process 仍会运行，未完成初始化前不能补怪/计时。
	if not _started or _main == null or not is_instance_valid(_main.player):
		return

	_main.player.set("_invuln", 9999.0)
	_remaining -= delta

	if _warmup > 0.0:
		# 跳过开场与首次生成 70 个敌人的分配/着色器尖峰。
		_warmup -= delta
	else:
		_record_sample(delta)

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 0.2
		var alive := get_tree().get_nodes_in_group("enemies").size()
		_min_enemies = mini(_min_enemies, alive)
		if alive < _target_enemies:
			_fill_enemies(mini(8, _target_enemies - alive))

	if _remaining <= 0.0:
		_finish()


func _record_sample(delta: float) -> void:
	if delta <= 0.0:
		return

	var fps := 1.0 / delta
	_frames += 1
	_fps_sum += fps
	_min_fps = minf(_min_fps, fps)
	_max_frame_ms = maxf(_max_frame_ms, delta * 1000.0)
	if fps < 55.0:
		_frames_below_55 += 1

	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_process_ms_sum += process_ms
	_physics_ms_sum += physics_ms
	_max_process_ms = maxf(_max_process_ms, process_ms)
	_max_physics_ms = maxf(_max_physics_ms, physics_ms)
	if _main != null and is_instance_valid(_main.projectile_manager):
		_projectiles_peak = maxi(
			_projectiles_peak,
			_main.projectile_manager._active.size()
		)


func _finish() -> void:
	set_process(false)

	var enemies := get_tree().get_nodes_in_group("enemies").size()
	_min_enemies = mini(_min_enemies, enemies)
	var average_fps := _fps_sum / maxf(1.0, float(_frames))
	# 不死模式要求真正维持 70 个敌人；--mortal 下敌人会被击杀，
	# 数量不能作为通过条件，改为要求战斗持续且帧率没有塌陷。
	var ok := average_fps >= 50.0 and enemies > 0
	if not _mortal:
		ok = average_fps >= 50.0 and enemies >= _target_enemies - 2

	var process_ms_avg := _process_ms_sum / maxf(1.0, float(_frames))
	var physics_ms_avg := _physics_ms_sum / maxf(1.0, float(_frames))
	print("PERF PROBE %s enemies=%d/%d min_enemies=%d avg_fps=%.1f min_fps=%.1f max_frame_ms=%.1f frames_below_55=%d nodes=%d process_ms=%.2f max_process_ms=%.2f physics_ms=%.2f max_physics_ms=%.2f projectiles_peak=%d no_fire=%s no_flock=%s mortal=%s skills=%s no_text=%s freeze=%s hide=%s" % [
		"PASS" if ok else "FAIL",
		enemies,
		_target_enemies,
		_min_enemies,
		average_fps,
		_min_fps,
		_max_frame_ms,
		_frames_below_55,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		process_ms_avg,
		_max_process_ms,
		physics_ms_avg,
		_max_physics_ms,
		_projectiles_peak,
		_no_fire,
		_no_flock,
		_mortal,
		not _no_skills,
		_no_text,
		_freeze,
		_hide_enemies,
	])
	get_tree().quit(0 if ok else 1)


func _fill_enemies(count: int) -> void:
	var types: Array[EnemyTypeResource] = []
	for enemy_type in ContentDB.get_enemies():
		if enemy_type.spawn_weight > 0.0 and (not _square_only or enemy_type.id == &"chaser_square"):
			types.append(enemy_type)
	if types.is_empty():
		return

	for i in count:
		var enemy_type: EnemyTypeResource = types[i % types.size()]
		var enemy := ENEMY_SCENE.instantiate()
		enemy.configure(enemy_type, _main.player)
		# 默认不死亡：否则满技能输出会迅速清场，测不到多敌人负载。
		if not _mortal:
			enemy.max_health = SURVIVE_HEALTH
			enemy.health = SURVIVE_HEALTH
		_main.world.add_child(enemy)
		if _with_statuses:
			enemy.apply_burn(1000.0)
			enemy.apply_poison(100.0)
			enemy.apply_ice(1000.0)
		if _freeze:
			enemy.set_physics_process(false)
		if _hide_enemies:
			enemy.visible = false
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(120.0, 480.0)
		enemy.global_position = _main.player.global_position + Vector2(
			cos(angle), sin(angle)
		) * distance
