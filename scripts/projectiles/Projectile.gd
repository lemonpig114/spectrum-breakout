class_name Projectile
extends Area2D

var manager: ProjectileManager
var direction := Vector2.RIGHT
var speed := 700.0
var damage := 10.0
var color_index := ColorType.RED
var lifetime := 1.0
var pierce := 0
var projectile_size := 5.0
var projectile_sides := 4
var is_heavy := false
var allow_crit := true
var source_kind: StringName = &""
var damage_bonus_ratios: Dictionary = {}

var _age := 0.0
var _released := false
var _owns_shape := false
var _hit_ids: Dictionary = {}
var active_index := -1
var batch_rendered := false

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_shape()


func setup(
	owner_manager: ProjectileManager,
	origin: Vector2,
	shot_direction: Vector2,
	stats: StatBlock,
	color_value: int,
	core: WeaponCoreResource,
	heavy: bool = false,
	damage_scale: float = 1.0,
	size_scale: float = 1.0,
	speed_scale: float = 1.0,
	lifetime_scale: float = 1.0,
	crit_allowed: bool = true,
	shot_source: StringName = &""
) -> void:
	manager = owner_manager
	global_position = origin

	direction = shot_direction.normalized()
	rotation = direction.angle()
	speed = stats.get_value(&"projectile_speed") * speed_scale
	allow_crit = crit_allowed
	source_kind = shot_source

	var raw_damage := stats.get_value(&"damage")
	var damage_mult := stats.get_value(&"damage_mult")
	# 透镜与破裂盔甲都加进同一个“伤害倍率”乘区，而不是独立乘区。
	damage_mult += Skills.lens_damage_bonus(color_value)
	damage_mult += Skills.cracked_armor_bonus()
	var damage_final := stats.get_value(&"damage_final")
	damage = raw_damage * damage_mult * damage_final * damage_scale
	damage_bonus_ratios = Skills.projectile_bonus_ratios(stats, color_value, heavy)
	projectile_size = stats.get_value(&"projectile_size") * size_scale
	is_heavy = heavy
	batch_rendered = not heavy and owner_manager.batch_enabled
	if is_heavy:
		damage = (raw_damage + 40.0) * damage_mult * damage_final * 2.5 * damage_scale
		projectile_size *= 1.5

	lifetime = stats.get_value(&"projectile_lifetime") * lifetime_scale
	# 裂片类小子弹不继承穿透，也不继承暴击。
	pierce = 0 if damage_scale < 0.99 or source_kind == &"clone" else int(stats.get_value(&"pierce"))
	projectile_sides = core.projectile_sides if core != null else 4
	color_index = color_value

	_age = 0.0
	_released = false
	_hit_ids.clear()
	visible = true
	collision_mask = 2
	set_physics_process(true)
	_apply_shape()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_age += delta
	global_position += direction * speed * delta

	if _age >= lifetime or not RunState.arena_rect.grow(64.0).has_point(global_position):
		_release()


func _on_body_entered(body: Node2D) -> void:
	if _released:
		return
	if not (body is Enemy):
		return

	var enemy := body as Enemy
	if enemy.is_dead:
		return

	var instance_id := enemy.get_instance_id()
	if _hit_ids.has(instance_id):
		return
	_hit_ids[instance_id] = true

	var first_hit := _hit_ids.size() == 1
	var last_hit := pierce <= 0

	var context := Skills.build_hit_context(self, enemy, damage, color_index, source_kind != &"clone", allow_crit)
	if source_kind == &"clone":
		context.add_tag(&"clone")
	enemy.take_damage(context)
	if source_kind != &"clone":
		Skills.apply_relic_projectile_procs(enemy)

	var weakness := context.has_tag(&"weakness")
	# 命中音按结算结果分层；同帧多弹丸由 Audio 的冷却合并。
	var hit_sound := &"hit"
	if context.has_tag(&"super_crit"):
		hit_sound = &"super_crit"
	elif context.is_crit:
		hit_sound = &"crit"
	elif weakness:
		hit_sound = &"weak_hit"
	elif is_heavy:
		hit_sound = &"hit_heavy"
	Audio.play(hit_sound)
	if not enemy.is_dead and source_kind != &"clone":
		if weakness:
			Skills.on_weakness_hit(enemy, damage, color_index)
		Skills.try_execute(enemy, weakness)
		if Skills.is_unlocked(&"heavy_2") and (enemy.type_data == null or not enemy.type_data.is_boss):
			enemy.apply_knockback(global_position, 300.0, 0.18)

	if source_kind != &"clone":
		Skills.try_gold_on_hit(global_position)

	var emphasis := weakness or context.is_crit
	var burst_color := RunState.color_of(color_index)
	if context.has_tag(&"super_crit"):
		burst_color = Color(2.8, 2.8, 2.8, 1.0)
	elif emphasis:
		burst_color = burst_color.lerp(Color.WHITE, 0.25)
	# 普通命中只有几颗小火花；暴击与重型弹额外带一圈短促爆点。
	FX.hit_spark(global_position, burst_color, emphasis)
	FX.hit_impact(global_position, burst_color, direction)
	if context.is_crit:
		FX.hit_burst(global_position, burst_color, 22.0, 0.16, EnergyBurst.STYLE_STAR)
	if is_heavy:
		FX.hit_burst(global_position, burst_color, 38.0, 0.28, EnergyBurst.STYLE_HEAVY)

	if source_kind != &"clone" and Skills.has_splash() and (Skills.splash_every_hit() or first_hit or last_hit):
		Skills.apply_splash(global_position, context.amount, color_index, enemy)

	if pierce > 0:
		pierce -= 1
	else:
		_release()


func _release() -> void:
	if _released:
		return
	_released = true
	if manager != null:
		manager.release(self)
	else:
		queue_free()


func _apply_shape() -> void:
	if _shape == null:
		return

	var circle := _shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		_shape.shape = circle
		_owns_shape = true
	elif not _owns_shape:
		circle = circle.duplicate() as CircleShape2D
		_shape.shape = circle
		_owns_shape = true

	circle.radius = maxf(3.0, projectile_size * 0.9)


func _draw() -> void:
	if batch_rendered:
		return
	var c := RunState.color_of(color_index)
	var s := projectile_size
	# 尾焰使用顶点透明度渐变，不增加节点；尾端完全透明。
	var tail := minf(speed * 0.045, s * (9.0 if is_heavy else 7.0))
	var tail_color := Color(c.r, c.g, c.b, 0.26)
	var clear := Color(c.r, c.g, c.b, 0.0)
	draw_polygon(PackedVector2Array([
		Vector2(s * 0.5, 0), Vector2(-s, s * 0.65),
		Vector2(-tail, 0), Vector2(-s, -s * 0.65),
	]), PackedColorArray([tail_color, tail_color, clear, tail_color]))
	var halo_size := s * (3.8 if is_heavy else 2.8)
	draw_texture_rect(preload("res://scripts/fx/NeonTexture.gd").halo(),
		Rect2(-Vector2.ONE * halo_size, Vector2.ONE * halo_size * 2.0),
		false, Color(c.r, c.g, c.b, 0.32))

	var points := PackedVector2Array([
		Vector2(s * 1.8, 0.0),
		Vector2(0.0, s),
		Vector2(-s * 0.6, 0.0),
		Vector2(0.0, -s),
	])
	draw_colored_polygon(points, Color(c.r, c.g, c.b, 1.0))
	draw_circle(Vector2.ZERO, s * 0.42, Color(2.5, 2.5, 2.5, 1.0))
	draw_line(Vector2(-tail * 0.65, 0.0), Vector2(-s * 0.5, 0.0), Color(c.r, c.g, c.b, 0.42), 1.0, true)
	if is_heavy:
		draw_arc(Vector2.ZERO, s * 1.5, 0.0, TAU, 24, Color(2.6, 2.6, 2.6, 0.85), 2.0, true)

