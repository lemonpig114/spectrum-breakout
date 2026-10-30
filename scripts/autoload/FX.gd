extends Node

## 全局反馈：顿帧、震屏、网格涟漪、几何碎片、伤害数字。
## 场景对象通过 group 查找，避免 autoload 持有场景引用。
##
## 性能约定：
## - 浮动文字、能量爆点、碎片粒子都使用固定容量的对象池，运行时不再反复 new/free；
## - 碎片有每秒预算，避免高射速下粒子数量失控；
## - 顿帧只在玩家受伤等低频事件触发，并由 min_interval 限流。

const TEXT_LAYER_SCRIPT := preload("res://scripts/fx/FloatingTextLayer.gd")
const DICE_EFFECT_SCRIPT := preload("res://scripts/fx/DiceRollEffect.gd")
const BURST_PREWARM := 32
const BURST_HARD_CAP := 96
const SHARD_PREWARM := 16
const SHARD_HARD_CAP := 64
const SHARD_BUDGET_PER_SECOND := 30.0
# 命中火花是独立的小粒子池：数量少、寿命短，和死亡碎片/爆炸彻底分开。
const SPARK_PREWARM := 16
const SPARK_HARD_CAP := 48
const SPARK_BUDGET_PER_SECOND := 45.0
const SPARK_AMOUNT := 3
## 密集战斗时限制元素数字的绘制数量；伤害与状态图标照常结算。
const ELEMENTAL_LABELS_PER_FRAME := 3
const SPLASH_LABELS_PER_FRAME := 2
const DIRECT_LABELS_PER_FRAME := 48
var _direct_label_frame := -1
var _direct_labels_this_frame := 0
var _elemental_label_frame := -1
var _elemental_labels_this_frame := 0
var _splash_label_frame := -1
var _splash_labels_this_frame := 0

var _shard_texture: ImageTexture
var _particle_fade: Gradient
var _particle_scale: Curve
var _last_hitstop_msec := -100000
var _hitstop_token := 0

var _fx_layer: Node
var _text_layer: Node2D
var _dice_effect: DiceRollEffect

# 泛光脉冲：只给 Boss 死亡 / 玩家死亡这类低频大事件用，避免每次都亮一下。
var _glow_env: Environment
var _glow_base := 1.8
var _glow_tween: Tween

var _burst_pool: Array[EnergyBurst] = []
var _burst_count := 0
# 密集溅射合并视觉：伤害仍逐次结算；保留短促爆点，避免白屏。
const SPLASH_VISUAL_RATE := 12.0
const SPLASH_VISUAL_RESERVE := 4.0
var _splash_budget := SPLASH_VISUAL_RESERVE
var _splash_frame := -1
var _splash_cells: Dictionary = {}

var _shard_pool: Array[CPUParticles2D] = []
var _shard_active: Array[CPUParticles2D] = []
var _shard_timers: Array[float] = []
var _shard_count := 0
var _shard_budget := SHARD_BUDGET_PER_SECOND

var _spark_pool: Array[CPUParticles2D] = []
var _spark_active: Array[CPUParticles2D] = []
var _spark_timers: Array[float] = []
var _spark_count := 0
var _spark_budget := SPARK_BUDGET_PER_SECOND
var _hit_burst_budget := 60.0
var _hit_burst_frame := -1
var _hit_burst_cells := {}
var _hit_bursts_this_frame := 0


func _ready() -> void:
	EventBus.player_died.connect(clear_dice_roll)
	EventBus.run_ended.connect(clear_dice_roll)
	_shard_texture = _make_shard_texture()
	_particle_fade = Gradient.new()
	_particle_fade.offsets = PackedFloat32Array([0.0, 0.18, 0.65, 1.0])
	_particle_fade.colors = PackedColorArray([
		Color(1.5, 1.5, 1.5, 1), Color.WHITE,
		Color(1, 1, 1, 0.48), Color(1, 1, 1, 0),
	])
	_particle_scale = Curve.new()
	_particle_scale.add_point(Vector2(0, 1))
	_particle_scale.add_point(Vector2(0.35, 0.7))
	_particle_scale.add_point(Vector2(1, 0.08))


func _process(delta: float) -> void:
	_hit_burst_budget = minf(60.0, _hit_burst_budget + delta * 60.0)
	_splash_budget = minf(SPLASH_VISUAL_RESERVE, _splash_budget + delta * SPLASH_VISUAL_RATE)
	_shard_budget = minf(
		SHARD_BUDGET_PER_SECOND,
		_shard_budget + delta * SHARD_BUDGET_PER_SECOND
	)
	_spark_budget = minf(
		SPARK_BUDGET_PER_SECOND,
		_spark_budget + delta * SPARK_BUDGET_PER_SECOND
	)

	for i in range(_shard_active.size() - 1, -1, -1):
		_shard_timers[i] -= delta
		if _shard_timers[i] > 0.0:
			continue
		var particles: Variant = _shard_active[i]
		_shard_active.remove_at(i)
		_shard_timers.remove_at(i)
		_release_particles(particles)

	for i in range(_spark_active.size() - 1, -1, -1):
		_spark_timers[i] -= delta
		if _spark_timers[i] > 0.0:
			continue
		var spark: Variant = _spark_active[i]
		_spark_active.remove_at(i)
		_spark_timers.remove_at(i)
		_release_spark(spark)


## 在主场景就绪后调用：预先创建对象池，避免首次受击/首次浮动文字时的分配尖峰。
func prewarm(root: Node) -> void:
	if root == null:
		return

	_splash_budget = SPLASH_VISUAL_RESERVE
	_splash_cells.clear()
	_splash_frame = -1
	_fx_layer = root
	_ensure_text_layer(root)
	_ensure_dice_effect(root)

	for burst in _burst_pool:
		if is_instance_valid(burst):
			burst.queue_free()
	for particles in _shard_pool:
		if is_instance_valid(particles):
			particles.queue_free()
	for particles in _shard_active:
		if is_instance_valid(particles):
			particles.queue_free()
	for spark in _spark_pool:
		if is_instance_valid(spark):
			spark.queue_free()
	for spark in _spark_active:
		if is_instance_valid(spark):
			spark.queue_free()

	_burst_pool.clear()
	_shard_pool.clear()
	_shard_active.clear()
	_shard_timers.clear()
	_spark_pool.clear()
	_spark_active.clear()
	_spark_timers.clear()
	_burst_count = 0
	_shard_count = 0
	_spark_count = 0

	for i in BURST_PREWARM:
		var burst := _create_burst(root)
		burst.visible = false
		_burst_pool.append(burst)

	for i in SHARD_PREWARM:
		var particles := _create_particles(root)
		particles.visible = false
		particles.emitting = false
		_shard_pool.append(particles)

	for i in SPARK_PREWARM:
		var spark := _create_spark(root)
		spark.visible = false
		spark.emitting = false
		_spark_pool.append(spark)


func _ensure_dice_effect(root: Node) -> DiceRollEffect:
	if is_instance_valid(_dice_effect) and _dice_effect.get_parent() == root:
		return _dice_effect
	if is_instance_valid(_dice_effect):
		_dice_effect.queue_free()
	_dice_effect = DICE_EFFECT_SCRIPT.new()
	root.add_child(_dice_effect)
	return _dice_effect


func dice_roll(target: Node2D, value: int) -> void:
	var root := _fx_root()
	if root != null and is_instance_valid(target):
		_ensure_dice_effect(root).play(target, value)


func clear_dice_roll() -> void:
	if is_instance_valid(_dice_effect):
		_dice_effect.clear()


func hitstop(duration: float, min_interval: float = 0.18) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hitstop_msec < int(min_interval * 1000.0):
		return
	_last_hitstop_msec = now

	_hitstop_token += 1
	var token := _hitstop_token
	# 0.15 比原来的 0.06 更轻，且触发频率被压低，避免持续性的“卡一下”。
	Engine.time_scale = 0.15

	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0


func shake(amount: float) -> void:
	var camera := get_tree().get_first_node_in_group("camera_rig")
	if camera != null and camera.has_method("add_trauma"):
		camera.add_trauma(amount)


## 全局泛光短促增强，然后缓回基线。
## 只用于 Boss 死亡、玩家死亡、开局色彩揭示这类低频高潮点；
## 普通命中/爆炸不要调用，不然泛光会变成噪声。
func glow_pulse(extra: float = 1.2, duration: float = 0.55) -> void:
	var environment := _find_environment()
	if environment == null:
		return

	if environment != _glow_env:
		_glow_env = environment
		_glow_base = environment.glow_intensity
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
		_glow_env.glow_intensity = _glow_base

	_glow_env.glow_intensity = _glow_base + extra
	_glow_tween = create_tween()
	_glow_tween.tween_property(_glow_env, "glow_intensity", _glow_base, duration) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)


func _find_environment() -> Environment:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	var node := root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if node == null or node.environment == null:
		return null
	# 菜单场景共用 neon.tres；复制一份，避免把共享资源改掉。
	if not node.environment.resource_path.is_empty():
		node.environment = node.environment.duplicate()
	return node.environment


func ripple(world_position: Vector2, strength: float = 1.0) -> void:
	var grid := get_tree().get_first_node_in_group("grid_background")
	if grid != null and grid.has_method("add_ripple"):
		grid.add_ripple(world_position, strength)


## 短促爆点。默认是暴击/闪避的四芒星；重型弹传入 STYLE_HEAVY。
## 普通命中不再使用它。
func hit_burst(
	world_position: Vector2,
	color: Color,
	radius: float = 30.0,
	duration: float = 0.26,
	style: int = EnergyBurst.STYLE_STAR
) -> void:
	if style in [EnergyBurst.STYLE_STAR, EnergyBurst.STYLE_HEAVY]:
		var frame := Engine.get_process_frames()
		if frame != _hit_burst_frame:
			_hit_burst_frame = frame
			_hit_burst_cells.clear()
			_hit_bursts_this_frame = 0
		var cell := Vector3i(floori(world_position.x / 40.0), floori(world_position.y / 40.0), style)
		if _hit_burst_budget < 1.0 or _hit_bursts_this_frame >= 6 or _hit_burst_cells.has(cell):
			return
		_hit_burst_cells[cell] = true
		_hit_burst_budget -= 1.0
		_hit_bursts_this_frame += 1
	_spawn_burst(world_position, color, radius, duration, style)


## 大范围冲击波。默认是受伤反击的双环；灵魂脉冲/溅射传入各自样式。
func shockwave(
	world_position: Vector2,
	color: Color,
	radius: float = 280.0,
	duration: float = 0.55,
	style: int = EnergyBurst.STYLE_PANIC
) -> void:
	if style == EnergyBurst.STYLE_SPLASH:
		var frame := Engine.get_process_frames()
		if frame != _splash_frame:
			_splash_cells.clear()
			_splash_frame = frame
		var cell := Vector2i(floori(world_position.x / 48.0), floori(world_position.y / 48.0))
		if _splash_cells.has(cell) or _splash_budget < 1.0:
			return
		_splash_cells[cell] = true
		_splash_budget -= 1.0
	_spawn_burst(world_position, color, radius, duration, style)


func _spawn_burst(
	world_position: Vector2,
	color: Color,
	radius: float,
	duration: float,
	style: int
) -> void:
	var root := _fx_root()
	if root == null:
		return

	var burst: EnergyBurst = null
	while not _burst_pool.is_empty():
		var candidate: EnergyBurst = _burst_pool.pop_back()
		if is_instance_valid(candidate) and candidate.get_parent() == root:
			burst = candidate
			break
		_burst_count = maxi(0, _burst_count - 1)

	if burst == null:
		if _burst_count >= BURST_HARD_CAP:
			return
		burst = _create_burst(root)

	burst.setup(world_position, color, radius, duration, style)


func release_burst(burst: EnergyBurst) -> void:
	if burst == null or not is_instance_valid(burst):
		return

	burst.release_veil()
	burst.visible = false
	burst.set_process(false)

	var root := _fx_root()
	if root != null and burst.get_parent() == root and _burst_pool.size() < BURST_HARD_CAP:
		_burst_pool.append(burst)
	else:
		_burst_count = maxi(0, _burst_count - 1)
		burst.queue_free()


func shards(world_position: Vector2, color: Color, count: int = 8) -> void:
	if _shard_budget < 1.0:
		return

	var root := _fx_root()
	if root == null:
		return

	var particles: CPUParticles2D = null
	while not _shard_pool.is_empty():
		var candidate: CPUParticles2D = _shard_pool.pop_back()
		if is_instance_valid(candidate) and candidate.get_parent() == root:
			particles = candidate
			break
		_shard_count = maxi(0, _shard_count - 1)

	if particles == null:
		if _shard_count >= SHARD_HARD_CAP:
			return
		particles = _create_particles(root)

	_shard_budget -= 1.0

	particles.position = world_position
	particles.amount = count
	particles.lifetime = 0.5
	particles.color = color
	particles.visible = true
	particles.restart()
	particles.emitting = true

	_shard_active.append(particles)
	_shard_timers.append(particles.lifetime + 0.4)


## 普通命中：几颗很小的火花，散开即消失，和敌人死亡的表现完全分开。
func hit_spark(world_position: Vector2, color: Color, emphasis: bool = false) -> void:
	if _spark_budget < 1.0:
		return

	var root := _fx_root()
	if root == null:
		return

	var spark: CPUParticles2D = null
	while not _spark_pool.is_empty():
		var candidate: CPUParticles2D = _spark_pool.pop_back()
		if is_instance_valid(candidate) and candidate.get_parent() == root:
			spark = candidate
			break
		_spark_count = maxi(0, _spark_count - 1)

	if spark == null:
		if _spark_count >= SPARK_HARD_CAP:
			return
		spark = _create_spark(root)

	_spark_budget -= 1.0

	spark.position = world_position
	spark.color = color.lerp(Color(1.5, 1.5, 1.5, 1.0), 0.2)
	spark.initial_velocity_min = 85.0 if emphasis else 55.0
	spark.initial_velocity_max = 230.0 if emphasis else 165.0
	spark.scale_amount_min = 0.8 if emphasis else 0.5
	spark.scale_amount_max = 1.5 if emphasis else 1.0
	spark.lifetime = 0.24 if emphasis else 0.18
	spark.visible = true
	spark.restart()
	spark.emitting = true

	_spark_active.append(spark)
	_spark_timers.append(spark.lifetime + 0.2)


## 敌人死亡：分离壳片 + 小碎屑；不产生圆波、圆弧或网格涟漪。
func death_effect(world_position: Vector2, color: Color) -> void:
	_spawn_burst(world_position, color, 34.0, 0.30, EnergyBurst.STYLE_SHATTER)
	shards(world_position, color, 6)
	shake(0.1)


func damage_number(
	world_position: Vector2,
	amount: float,
	color: Color,
	emphasis: bool = false,
	style: int = -1,
	caption: String = ""
) -> void:
	if style not in [FloatingTextLayer.STYLE_BURN, FloatingTextLayer.STYLE_POISON,
			FloatingTextLayer.STYLE_ICE, FloatingTextLayer.STYLE_SPLASH, FloatingTextLayer.STYLE_SUPER_CRIT]:
		var frame := Engine.get_process_frames()
		if frame != _direct_label_frame:
			_direct_label_frame = frame
			_direct_labels_this_frame = 0
		if _direct_labels_this_frame >= DIRECT_LABELS_PER_FRAME:
			return
		_direct_labels_this_frame += 1
	if style == FloatingTextLayer.STYLE_SPLASH:
		var splash_frame := Engine.get_process_frames()
		if splash_frame != _splash_label_frame:
			_splash_label_frame = splash_frame
			_splash_labels_this_frame = 0
		if _splash_labels_this_frame >= SPLASH_LABELS_PER_FRAME:
			return
		_splash_labels_this_frame += 1
	if style == FloatingTextLayer.STYLE_BURN or style == FloatingTextLayer.STYLE_POISON or style == FloatingTextLayer.STYLE_ICE:
		var frame := Engine.get_process_frames()
		if frame != _elemental_label_frame:
			_elemental_label_frame = frame
			_elemental_labels_this_frame = 0
		if _elemental_labels_this_frame >= ELEMENTAL_LABELS_PER_FRAME:
			return
		_elemental_labels_this_frame += 1
	var root := _fx_root()
	if root == null:
		return
	if style < 0:
		style = FloatingTextLayer.STYLE_WEAKNESS if emphasis else FloatingTextLayer.STYLE_NORMAL
	_ensure_text_layer(root).add_text(world_position, str(int(round(amount))), color, 0, style, caption)


## 极短的弹着点动画；与数字共用固定容量绘制层，不分配命中节点。
func hit_impact(world_position: Vector2, color: Color, direction: Vector2) -> void:
	var root := _fx_root()
	if root == null:
		return
	_ensure_text_layer(root).add_impact(world_position, color, direction)


## 任意短文字浮字："闪避"、"处决"等。
func execution_number(world_position: Vector2) -> void:
	var root := _fx_root()
	if root != null:
		_ensure_text_layer(root).add_text(world_position, "99999999999999", Color(0.12, 0.005, 0.015), 26, FloatingTextLayer.STYLE_EXECUTION)


func text_popup(world_position: Vector2, text: String, color: Color, font_size: int = 16) -> void:
	var root := _fx_root()
	if root == null:
		return
	_ensure_text_layer(root).add_text(world_position, text, color, font_size)


func _create_burst(root: Node) -> EnergyBurst:
	var burst := EnergyBurst.new()
	root.add_child(burst)
	burst.visible = false
	burst.set_process(false)
	_burst_count += 1
	return burst


func _create_particles(root: Node) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.z_index = 30
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector2.RIGHT
	particles.spread = 180.0
	particles.initial_velocity_min = 110.0
	particles.initial_velocity_max = 340.0
	particles.gravity = Vector2.ZERO
	particles.damping_min = 160.0
	particles.damping_max = 260.0
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.2
	particles.angular_velocity_min = -360.0
	particles.angular_velocity_max = 360.0
	particles.texture = _shard_texture
	particles.color_ramp = _particle_fade
	particles.scale_amount_curve = _particle_scale
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.local_coords = false
	particles.emitting = false
	root.add_child(particles)
	_shard_count += 1
	return particles


func _create_spark(root: Node) -> CPUParticles2D:
	var spark := CPUParticles2D.new()
	spark.z_index = 31
	spark.one_shot = true
	spark.explosiveness = 1.0
	spark.amount = SPARK_AMOUNT
	spark.lifetime = 0.18
	spark.direction = Vector2.RIGHT
	spark.spread = 180.0
	spark.initial_velocity_min = 55.0
	spark.initial_velocity_max = 165.0
	spark.gravity = Vector2.ZERO
	spark.damping_min = 300.0
	spark.damping_max = 460.0
	spark.scale_amount_min = 0.5
	spark.scale_amount_max = 1.0
	spark.angular_velocity_min = -540.0
	spark.angular_velocity_max = 540.0
	spark.texture = _shard_texture
	spark.color_ramp = _particle_fade
	spark.scale_amount_curve = _particle_scale
	spark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spark.local_coords = false
	spark.emitting = false
	root.add_child(spark)
	_spark_count += 1
	return spark


func _release_spark(candidate: Variant) -> void:
	if not is_instance_valid(candidate):
		_spark_count = maxi(0, _spark_count - 1)
		return
	var spark := candidate as CPUParticles2D
	if spark == null:
		_spark_count = maxi(0, _spark_count - 1)
		return

	spark.visible = false
	spark.emitting = false

	var root := _fx_root()
	if root != null and spark.get_parent() == root and _spark_pool.size() < SPARK_HARD_CAP:
		_spark_pool.append(spark)
	else:
		_spark_count = maxi(0, _spark_count - 1)
		spark.queue_free()


func _release_particles(candidate: Variant) -> void:
	if not is_instance_valid(candidate):
		_shard_count = maxi(0, _shard_count - 1)
		return
	var particles := candidate as CPUParticles2D
	if particles == null:
		_shard_count = maxi(0, _shard_count - 1)
		return

	particles.visible = false
	particles.emitting = false

	var root := _fx_root()
	if root != null and particles.get_parent() == root and _shard_pool.size() < SHARD_HARD_CAP:
		_shard_pool.append(particles)
	else:
		_shard_count = maxi(0, _shard_count - 1)
		particles.queue_free()


func _ensure_text_layer(root: Node) -> FloatingTextLayer:
	if (
		_text_layer != null
		and is_instance_valid(_text_layer)
		and _text_layer.get_parent() == root
	):
		return _text_layer

	_text_layer = TEXT_LAYER_SCRIPT.new() as FloatingTextLayer
	root.add_child(_text_layer)
	return _text_layer


func _fx_root() -> Node:
	if _fx_layer != null and is_instance_valid(_fx_layer):
		return _fx_layer
	_fx_layer = get_tree().get_first_node_in_group("fx_layer")
	return _fx_layer


func _make_shard_texture() -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
