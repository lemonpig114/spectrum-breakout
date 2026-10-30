class_name EnemyProjectile
extends Node2D

## 远程怪的慢速可见弹体；手动做线段命中，避免高速时穿过玩家。
var direction := Vector2.RIGHT
var speed := 310.0
var damage := 0.5
var target: Node2D
var tint := Color.WHITE
var color_index := -1
var _lifetime := 2.2
var orbiting := false
var orbit_hit := false


func configure(origin: Vector2, aim: Vector2, player_target: Node2D, color: Color,
	travel_speed: float, hit_damage: float, attack_color: int = -1) -> void:
	global_position = origin
	direction = aim.normalized() if aim.length_squared() > 0.001 else Vector2.RIGHT
	rotation = direction.angle()
	target = player_target
	tint = color
	color_index = attack_color
	speed = travel_speed
	damage = hit_damage
	queue_redraw()


func _ready() -> void:
	add_to_group(&"enemy_projectiles")
	z_index = 8


func _physics_process(delta: float) -> void:
	if RunState.is_dead or not RunState.is_running or target == null or not is_instance_valid(target):
		queue_free()
		return
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return
	var start := global_position
	var travel := direction * speed * delta
	var center := target.global_position
	var along := clampf((center - start).dot(travel) / maxf(travel.length_squared(), 0.001), 0.0, 1.0)
	var closest := start + travel * along
	var hit_radius := (target as Player).body_radius + 5.0 if target is Player else 16.0
	if closest.distance_squared_to(center) <= hit_radius * hit_radius:
		if target.has_method("take_damage"):
			target.take_damage(damage, self)
		queue_free()
		return
	global_position = start + travel
	if not RunState.arena_rect.grow(80.0).has_point(global_position):
		queue_free()


func _draw() -> void:
	var fill := Color(tint.r * 0.7, tint.g * 0.7, tint.b * 0.7, 0.9)
	draw_line(Vector2(-12, 0), Vector2(-3, 0), Color(tint.r, tint.g, tint.b, 0.38), 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(6, 0), Vector2(-2, -4), Vector2(-5, 0), Vector2(-2, 4)
	]), fill)
	draw_polyline(PackedVector2Array([
		Vector2(6, 0), Vector2(-2, -4), Vector2(-5, 0), Vector2(-2, 4), Vector2(6, 0)
	]), Color(tint.r, tint.g, tint.b, 0.95), 1.2, true)
