class_name Projectile
extends Area2D

var manager: ProjectileManager
var direction := Vector2.RIGHT
var speed := 700.0
var damage := 10.0
var color_index := ColorType.RED
var lifetime := 1.0
var pierce := 0
var ricochets := 0
var projectile_size := 5.0
var projectile_sides := 4
var is_heavy := false
var allow_crit := true
var source_kind: StringName = &""
var damage_bonus_ratios: Dictionary = {}
var damage_snapshot: RefCounted

var _age := 0.0
var _released := false
var _owns_shape := false
var _hit_ids: Dictionary = {}
var active_index := -1
var batch_rendered := false
var batch_star := false
var batch_sprite := false
var weapon: WeaponRuntime
var form_at_fire: StringName = &""
var budget: Dictionary = {}
var shot_scale := 1.0
var can_split := true
var orbiting := false
var orbit_exhausted := false
var spawn_serial := 0
var chain_triggered := false
var sword_triggered := false
var _returning := false
var _outward_origin := Vector2.ZERO
var _return_hit_ids: Dictionary = {}
var is_derived := false
var _sprite_dashing := false
var _sprite_dash_left := 0.0
var _sprite_seek_cooldown := 0.0
var _sprite_attacks_left := 1
var _sprite_launch_direction := Vector2.RIGHT
var _sprite_curve_previous := 0.0
var _sprite_curve_amplitude := 0.0
var _sprite_curve_frequency := 0.0
var _sprite_trail: Line2D
var _sprite_trail_clock := 0.0
var _has_sprite_trail := false
var _fusion_seek_clock := 0.0

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
	split_allowed: bool = true,
	form_override: StringName = &""
) -> void:
	manager = owner_manager
	spawn_serial += 1
	orbiting = false
	orbit_exhausted = false
	scale = Vector2.ONE
	weapon = weapon_runtime
	form_at_fire = form_override if form_override != &"" else (weapon_runtime.primary_form if weapon_runtime != null else &"")
	budget = attack_budget
	shot_scale = damage_scale
	can_split = split_allowed
	is_derived = weapon_runtime != null and not split_allowed and shot_source in [&"weapon:star", &"clone"]
	chain_triggered = false
	sword_triggered = false
	_returning = false
	_return_hit_ids.clear()
	_sprite_dashing = false
	_sprite_dash_left = 0.0
	_sprite_seek_cooldown = 0.0
	_sprite_launch_direction = shot_direction.normalized()
	_sprite_curve_previous = 0.0
	_sprite_curve_amplitude = randf_range(-31.0, 31.0)
	_sprite_curve_frequency = randf_range(4.5, 6.5)
	_sprite_trail_clock = 0.0
	_fusion_seek_clock = randf_range(0.0, 0.12)
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
	damage_snapshot = Skills.projectile_bonus_snapshot(stats, color_value, heavy)
	damage_bonus_ratios = damage_snapshot.ratios
	projectile_size = stats.get_value(&"projectile_size") * size_scale
	is_heavy = heavy
	batch_star = form_at_fire == &"star" or shot_source == &"weapon:star"
	batch_sprite = false
	batch_rendered = not heavy and owner_manager.batch_enabled and \
		form_at_fire not in [&"boomerang", &"cannon", &"sprite"]
	if is_heavy:
		damage = (raw_damage + 40.0) * damage_mult * damage_final * 2.5 * damage_scale
		projectile_size *= 1.5

	lifetime = stats.get_value(&"projectile_lifetime") * lifetime_scale
	if form_at_fire == &"sprite":
		lifetime = 20.0
	elif form_at_fire == &"cannon":
		lifetime = maxf(2.0, lifetime)
		speed *= 0.5
	# 主形态的伤害倍率不取消穿透；只有裂片、分身等派生弹不继承穿透。
	pierce = 0 if source_kind == &"clone" or (weapon_runtime == null and damage_scale < 0.99) \
		or (weapon_runtime != null and not split_allowed) else int(stats.get_value(&"pierce"))
	ricochets = maxi(0, int(stats.get_value(&"ricochet")))
	if form_at_fire == &"cannon":
		pierce = 0
	_sprite_attacks_left = 1 + maxi(0, pierce)
	projectile_sides = core.projectile_sides if core != null else 4
	color_index = color_value
	_has_sprite_trail = form_at_fire == &"sprite" and owner_manager.acquire_sprite_trail()
	if _has_sprite_trail:
		_setup_sprite_trail()
	elif _sprite_trail != null:
		_sprite_trail.visible = false
		_sprite_trail.clear_points()
	if form_at_fire == &"sprite" and not _has_sprite_trail and owner_manager.batch_enabled:
		batch_rendered = true
		batch_sprite = true

	_age = 0.0
	_released = false
	_hit_ids.clear()
	visible = true
	collision_mask = 2
	_shape.set_deferred("disabled", false)
	set_physics_process(true)
	_apply_shape()
	_request_redraw()


func _physics_process(delta: float) -> void:
	var clock := preload("res://scripts/game/CombatProfiler.gd").begin()
	_simulate_projectile(delta)
	preload("res://scripts/game/CombatProfiler.gd").end(&"projectile", clock)


func _simulate_projectile(delta: float) -> void:
	_age += delta
	var primary := form_at_fire
	if not _returning and primary != &"sprite" \
			and weapon != null and weapon.has_form(&"sprite"):
		_fusion_seek_clock -= delta
		if _fusion_seek_clock <= 0.0:
			_fusion_seek_clock = 0.12
			var target := _closest_sprite_target(300.0)
			if target != null:
				direction = direction.slerp((target.global_position - global_position).normalized(), 0.28).normalized()
				rotation = direction.angle()
	if primary == &"cannon":
		speed = move_toward(speed, 0.0, 360.0 * delta)
		if speed <= 32.0:
			manager.combat.queue_cannon_explosion(self, global_position)
			_release()
			return
	elif primary == &"sprite" and not _returning:
		if _sprite_dashing:
			_sprite_dash_left -= speed * delta
			if _sprite_dash_left <= 0.0:
				_sprite_dashing = false
				speed = 0.0
				_sprite_seek_cooldown = 0.10
		else:
			speed = move_toward(speed, 0.0, 950.0 * delta)
			_sprite_seek_cooldown -= delta
			if speed <= 75.0 and _sprite_seek_cooldown <= 0.0:
				_sprite_seek_cooldown = 0.18
				_seek_sprite_target()
	if weapon != null and weapon.has_form(&"boomerang") and primary != &"cannon":
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
	if primary == &"sprite" and not _sprite_dashing:
		var curve := _sprite_curve_amplitude * sin(_age * _sprite_curve_frequency)
		global_position += _sprite_launch_direction.orthogonal() * (curve - _sprite_curve_previous)
		_sprite_curve_previous = curve
	if primary == &"sprite" and _has_sprite_trail and _sprite_trail != null:
		_sprite_trail_clock += delta
		if _sprite_trail_clock >= 0.025:
			_sprite_trail_clock = 0.0
			_sprite_trail.add_point(global_position)
			while _sprite_trail.get_point_count() > 6:
				_sprite_trail.remove_point(0)

	var max_age := 4.0 if weapon != null and weapon.has_form(&"boomerang") else lifetime
	if _age >= max_age \
			or not RunState.arena_rect.grow(64.0).has_point(global_position):
		_release()


func _seek_sprite_target() -> void:
	var best := _closest_sprite_target(390.0)
	if best == null:
		return
	direction = (best.global_position - global_position).normalized()
	rotation = direction.angle()
	speed = 930.0
	_sprite_dashing = true
	_sprite_dash_left = 230.0
	if _sprite_trail != null:
		_sprite_trail.width = 4.5
	_request_redraw()


func _closest_sprite_target(reach: float) -> Node2D:
	return manager.friendly_target(global_position, reach, _hit_ids)


func _begin_return() -> void:
	if _returning:
		return
	_returning = true
	_return_hit_ids.clear()
	if form_at_fire == &"boomerang" and weapon != null and weapon.has_form(&"sword"):
		manager.combat.enqueue({"kind": &"sword", "origin": global_position,
			"direction": direction, "damage": damage * 0.6,
			"color": color_index, "heavy": false, "weapon": weapon,
			"budget": budget, "secondary": true, "clone": source_kind == &"clone"})


func _on_body_entered(body: Node2D) -> void:
	if _released or (orbiting and orbit_exhausted):
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
	var last_hit := ((_sprite_attacks_left <= 1 if form_at_fire == &"sprite" else pierce <= 0) and ricochets <= 0) or _returning
	manager.combat.on_projectile_hit(self, enemy, first_hit, last_hit)
	if orbiting:
		if form_at_fire == &"sprite":
			_sprite_attacks_left -= 1
			orbit_exhausted = _sprite_attacks_left <= 0
		elif pierce > 0:
			pierce -= 1
		else:
			orbit_exhausted = true
		return

	if _returning:
		return
	if ricochets > 0 and _ricochet(enemy):
		return
	if form_at_fire == &"sprite":
		_sprite_attacks_left -= 1
		if _sprite_attacks_left <= 0:
			if weapon != null and weapon.has_form(&"boomerang"):
				_begin_return()
			else:
				_release()
		else:
			_sprite_dashing = false
			_sprite_dash_left = 0.0
			speed = 0.0
			_sprite_seek_cooldown = 0.10
			if _sprite_trail != null:
				_sprite_trail.width = 2.5
			_request_redraw()
		return
	if pierce > 0:
		pierce -= 1
	elif weapon != null and weapon.has_form(&"boomerang"):
		_begin_return()
	else:
		_release()


func _ricochet(enemy: Enemy) -> bool:
	var next := manager.guidance_target(enemy.global_position, 320.0, _hit_ids)
	if next == null:
		return false
	ricochets -= 1
	direction = (next.global_position - global_position).normalized()
	rotation = direction.angle()
	if form_at_fire == &"sprite":
		_sprite_dashing = true
		_sprite_dash_left = global_position.distance_to(next.global_position) + next.radius + 20.0
		speed = 930.0
	elif form_at_fire == &"cannon":
		speed = maxf(speed, 240.0)
	if weapon == null or not weapon.has_form(&"boomerang"):
		# Leave enough flight time for the redirected segment; boomerangs keep
		# their original strict four-second total lifetime.
		_age = minf(_age, maxf(0.0, lifetime - global_position.distance_to(next.global_position) / maxf(speed, 1.0) - 0.1))
	_request_redraw()
	return true


func _release() -> void:
	if _released:
		return
	_released = true
	if manager != null:
		manager.release(self)
	else:
		queue_free()


func deactivate_sprite_trail() -> void:
	if _has_sprite_trail and manager != null:
		manager.release_sprite_trail()
	_has_sprite_trail = false
	if _sprite_trail != null:
		_sprite_trail.visible = false
		_sprite_trail.clear_points()


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


func _setup_sprite_trail() -> void:
	if _sprite_trail == null:
		_sprite_trail = Line2D.new()
		_sprite_trail.top_level = true
		_sprite_trail.z_index = -1
		_sprite_trail.antialiased = true
		_sprite_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_sprite_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
		var taper := Curve.new()
		taper.add_point(Vector2(0.0, 0.0))
		taper.add_point(Vector2(1.0, 1.0))
		_sprite_trail.width_curve = taper
		add_child(_sprite_trail)
	_sprite_trail.global_position = Vector2.ZERO
	_sprite_trail.width = 5.0 if _sprite_dashing else 3.0
	var c := RunState.color_of(color_index)
	var fade := Gradient.new()
	fade.set_color(0, Color(c.r, c.g, c.b, 0.0))
	fade.set_color(1, Color(c.r, c.g, c.b, 0.48))
	_sprite_trail.gradient = fade
	_sprite_trail.clear_points()
	_sprite_trail.add_point(global_position)
	_sprite_trail.visible = true


func _draw() -> void:
	if batch_rendered:
		return
	var c := RunState.color_of(color_index)
	var s := projectile_size
	if form_at_fire == &"cannon":
		var shell := maxf(5.0, s * 1.25)
		draw_circle(Vector2.ZERO, shell * 1.9, Color(c.r, c.g, c.b, 0.035))
		draw_circle(Vector2.ZERO, shell, Color(c.r * 0.22, c.g * 0.22, c.b * 0.22))
		draw_circle(Vector2.ZERO, shell * 0.78, Color(c.r * 0.72, c.g * 0.72, c.b * 0.72))
		draw_arc(Vector2.ZERO, shell * 0.95, -PI * 0.72, PI * 0.28, 16,
			Color(2.2, 2.2, 2.2, 0.82), 1.8, true)
		draw_circle(Vector2(shell * 0.28, -shell * 0.24), shell * 0.18,
			Color(2.3, 2.3, 2.3, 0.85))
		return
	if form_at_fire == &"sprite":
		var dot := maxf(2.3, s * 0.58)
		draw_circle(Vector2.ZERO, dot * 1.7, Color(c.r, c.g, c.b, 0.08))
		draw_circle(Vector2.ZERO, dot, Color(c.r, c.g, c.b, 0.86))
		draw_circle(Vector2.ZERO, dot * 0.4, Color(2.0, 2.0, 2.0, 0.9))
		return
	if form_at_fire == &"boomerang":
		var points := PackedVector2Array([
			Vector2(s * 1.8, -s * 0.8), Vector2(s * 0.2, 0),
			Vector2(s * 1.8, s * 0.8), Vector2(-s * 1.2, s * 0.5),
			Vector2(-s * 1.7, 0), Vector2(-s * 1.2, -s * 0.5),
		])
		draw_colored_polygon(points, Color(c.r * 0.25, c.g * 0.25, c.b * 0.25))
		draw_polyline(PackedVector2Array([points[0], points[1], points[2]]), c, 2.5, true)
		draw_line(points[5], points[3], c, 2.0, true)
		return
	if form_at_fire == &"star" or source_kind == &"weapon:star":
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



func _request_redraw() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()
	set_process(false)
