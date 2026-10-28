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
var batch_star := false
var weapon: WeaponRuntime
var budget: Dictionary = {}
var shot_scale := 1.0
var can_split := true
var chain_triggered := false
var sword_triggered := false
var _returning := false
var _outward_origin := Vector2.ZERO
var _return_hit_ids: Dictionary = {}
var is_derived := false

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
	shot_source: StringName = &"",
	weapon_runtime: WeaponRuntime = null,
	attack_budget: Dictionary = {},
	split_allowed: bool = true
) -> void:
	manager = owner_manager
	weapon = weapon_runtime
	budget = attack_budget
	shot_scale = damage_scale
	can_split = split_allowed
	is_derived = weapon_runtime != null and not split_allowed and shot_source == &"weapon:star"
	chain_triggered = false
	sword_triggered = false
	_returning = false
	_return_hit_ids.clear()
	global_position = origin
	_outward_origin = origin

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
	batch_star = weapon != null and (weapon.primary_form == &"star" or shot_source == &"weapon:star")
	batch_rendered = not heavy and owner_manager.batch_enabled and \
		(weapon == null or (weapon.primary_form != &"boomerang" and source_kind != &"weapon:sword"))
	if is_heavy:
		damage = (raw_damage + 40.0) * damage_mult * damage_final * 2.5 * damage_scale
		projectile_size *= 1.5

	lifetime = stats.get_value(&"projectile_lifetime") * lifetime_scale
	# 主形态的伤害倍率不取消穿透；只有裂片、分身等派生弹不继承穿透。
	pierce = 0 if source_kind == &"clone" or (weapon_runtime == null and damage_scale < 0.99) \
		or (weapon_runtime != null and not split_allowed) else int(stats.get_value(&"pierce"))
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
	if weapon != null and weapon.has_form(&"boomerang"):
		if _returning:
			if manager.combat.player == null or not is_instance_valid(manager.combat.player):
				_release()
				return
			var to_player: Vector2 = manager.combat.player.global_position - global_position
			if to_player.length() <= 20.0:
				_release()
				return
			direction = to_player.normalized()
			rotation = direction.angle()
		elif global_position.distance_to(_outward_origin) >= 340.0:
			_begin_return()
	global_position += direction * speed * delta

	if _age >= (4.0 if weapon != null and weapon.has_form(&"boomerang") else lifetime) \
			or not RunState.arena_rect.grow(64.0).has_point(global_position):
		_release()


func _begin_return() -> void:
	if _returning:
		return
	_returning = true
	_return_hit_ids.clear()
	if weapon != null and weapon.primary_form == &"boomerang" and weapon.has_form(&"sword"):
		manager.combat.enqueue({"kind": &"sword", "origin": global_position,
			"direction": direction, "damage": damage * 0.6,
			"color": color_index, "heavy": false, "weapon": weapon,
			"budget": budget, "secondary": true})


func _on_body_entered(body: Node2D) -> void:
	if _released:
		return
	if not (body is Enemy):
		return

	var enemy := body as Enemy
	if enemy.is_dead:
		return

	var instance_id := enemy.get_instance_id()
	if _returning and _return_hit_ids.has(instance_id):
		return
	if not _returning and _hit_ids.has(instance_id):
		return
	if _returning:
		_return_hit_ids[instance_id] = true
	else:
		_hit_ids[instance_id] = true

	var first_hit := _hit_ids.size() == 1 and not _returning
	var last_hit := pierce <= 0 or _returning
	manager.combat.on_projectile_hit(self, enemy, first_hit, last_hit)

	if _returning:
		return
	if pierce > 0:
		pierce -= 1
	elif weapon != null and weapon.has_form(&"boomerang"):
		_begin_return()
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
	if weapon != null and (weapon.primary_form == &"boomerang" or source_kind == &"weapon:sword"):
		var points := PackedVector2Array([
			Vector2(s * 1.8, -s * 0.8), Vector2(s * 0.2, 0),
			Vector2(s * 1.8, s * 0.8), Vector2(-s * 1.2, s * 0.5),
			Vector2(-s * 1.7, 0), Vector2(-s * 1.2, -s * 0.5),
		])
		draw_colored_polygon(points, Color(c.r * 0.25, c.g * 0.25, c.b * 0.25))
		draw_polyline(PackedVector2Array([points[0], points[1], points[2]]), c, 2.5, true)
		draw_line(points[5], points[3], c, 2.0, true)
		return
	if weapon != null and (weapon.primary_form == &"star" or source_kind == &"weapon:star"):
		var points := PackedVector2Array()
		for i in 10:
			points.append(Vector2.from_angle(TAU * float(i) / 10.0) * s * (1.75 if i % 2 == 0 else 0.75))
		draw_colored_polygon(points, c)
		draw_circle(Vector2.ZERO, s * 0.36, Color(2.5, 2.5, 2.5))
		return
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

