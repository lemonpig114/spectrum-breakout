class_name SummonField
extends Node2D

const SPRITE_SCRIPT := preload("res://scripts/skills/SpriteCompanion.gd")
const CLONE_SCRIPT := preload("res://scripts/skills/MirrorClone.gd")
const CIRCLE_RADIUS := 190.0
const CIRCLE_DURATION := 10.0

var player: Player
var companions: Array[SpriteCompanion] = []
var clones: Array[MirrorClone] = []
var _color_offset := 0
var _clone_timer := 0.0
var _circle_kills := 0
var _circle_time := 0.0
var _circle_position := Vector2.ZERO
var _circle_tick := 0.0
var _circle_buffed := false
var _circle_final_applied := false
var _circle_phase := 0.0
## 敌人死亡事件同步触发；仅法阵本次伤害击杀可由四阶获得灵魂。
var _circle_damage_target: Enemy


func setup(owner_player: Player) -> void:
	player = owner_player
	_color_offset = RunState.rng.randi_range(0, ColorType.COUNT - 1)
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not RunState.is_running or RunState.is_dead:
		return
	_sync_companions()
	_tick_clones(delta)
	_tick_circle(delta)


func _sync_companions() -> void:
	var wanted := 0
	if Skills.is_unlocked(&"sprite_1"):
		wanted = 1 + int(Skills.is_unlocked(&"sprite_2")) + int(Skills.is_unlocked(&"sprite_4"))
	while companions.size() < wanted:
		var companion: SpriteCompanion = SPRITE_SCRIPT.new()
		add_child(companion)
		var slot := companions.size()
		companion.setup(player, slot, posmod(_color_offset + slot, ColorType.COUNT))
		companions.append(companion)


func _tick_clones(delta: float) -> void:
	if not Skills.is_unlocked(&"clone_1"):
		return
	for i in range(clones.size() - 1, -1, -1):
		if not is_instance_valid(clones[i]) or clones[i].is_queued_for_deletion():
			clones.remove_at(i)
	_clone_timer -= delta
	if _clone_timer > 0.0:
		return
	_clone_timer = 10.0 if Skills.is_unlocked(&"clone_4") else (15.0 / (1.2 if Skills.is_unlocked(&"clone_2") else 1.0))
	if clones.size() >= 20:
		return
	var clone: MirrorClone = CLONE_SCRIPT.new()
	add_child(clone)
	clone.setup(player, player.global_position + Vector2.from_angle(RunState.rng.randf() * TAU) * 55.0)
	clones.append(clone)


func _on_enemy_killed(enemy: Node, _gold: int, _xp: float) -> void:
	if not (enemy is Enemy) or player == null or not is_instance_valid(player):
		return
	if _circle_time > 0.0:
		if Skills.is_unlocked(&"circle_4") and _in_circle((enemy as Enemy).global_position, (enemy as Enemy).radius):
			_circle_time = minf(CIRCLE_DURATION, _circle_time + 0.5)
			if enemy == _circle_damage_target:
				Skills.soul_kills += 1
		return
	if not Skills.is_unlocked(&"circle_1"):
		return
	_circle_kills += 1
	if _circle_kills >= 30:
		_circle_kills = 0
		_circle_position = player.global_position
		_circle_time = CIRCLE_DURATION
		_circle_tick = 0.0
		queue_redraw()


func _tick_circle(delta: float) -> void:
	if _circle_time <= 0.0:
		return
	_circle_time = maxf(0.0, _circle_time - delta)
	_circle_phase += delta * 0.35
	var inside := _circle_time > 0.0 and _in_circle(player.global_position, player.body_radius)
	if inside != _circle_buffed:
		_set_circle_buff(inside)
	elif inside and Skills.is_unlocked(&"circle_3") and not _circle_final_applied:
		_set_circle_buff(true)
	if _circle_time <= 0.0:
		_clear_circle_slow()
		queue_redraw()
		return
	if Skills.is_unlocked(&"circle_2"):
		_update_circle_slow()
		_circle_tick += delta
		if _circle_tick >= 0.5:
			_circle_tick -= 0.5
			_circle_damage_tick()
	queue_redraw()


func _circle_damage_tick() -> void:
	var damage := (10.0 + float(Skills.soul_kills)) * 0.25
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if not (node is Enemy):
			continue
		var enemy := node as Enemy
		if enemy.is_dead or not _in_circle(enemy.global_position, enemy.radius):
			continue
		_circle_damage_target = enemy
		enemy.take_true_damage(damage, &"skill:circle_2")
		_circle_damage_target = null


func _in_circle(position_value: Vector2, extra: float = 0.0) -> bool:
	var radius := (CIRCLE_RADIUS * (1.35 if Skills.is_unlocked(&"circle_3") else 1.0)) + extra
	return _circle_position.distance_squared_to(position_value) <= radius * radius


func _update_circle_slow() -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is Enemy:
			var enemy := node as Enemy
			enemy.circle_slow = not enemy.is_dead and _in_circle(enemy.global_position, enemy.radius)


func _clear_circle_slow() -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is Enemy:
			(node as Enemy).circle_slow = false


func _set_circle_buff(enabled: bool) -> void:
	_circle_buffed = enabled
	_circle_final_applied = enabled and Skills.is_unlocked(&"circle_3")
	for source in [&"skill_circle_damage", &"skill_circle_rate", &"skill_circle_final"]:
		player.weapon.stats.remove_modifiers_from(source)
	if not enabled:
		return
	_add_circle_modifier(&"damage_mult", StatModifierResource.Op.ADD_PERCENT, 0.5, &"skill_circle_damage")
	_add_circle_modifier(&"fire_rate_mult", StatModifierResource.Op.ADD_PERCENT, 0.3, &"skill_circle_rate")
	if Skills.is_unlocked(&"circle_3"):
		_add_circle_modifier(&"damage_final", StatModifierResource.Op.MULTIPLY, 1.2, &"skill_circle_final")


func _add_circle_modifier(stat: StringName, op: int, value: float, source: StringName) -> void:
	var modifier := StatModifierResource.new()
	modifier.stat = stat
	modifier.op = op
	modifier.value = value
	modifier.source = source
	player.weapon.stats.add_modifier(modifier)


func _exit_tree() -> void:
	_clear_circle_slow()
	if player != null and is_instance_valid(player) and _circle_buffed:
		_set_circle_buff(false)
	if EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.disconnect(_on_enemy_killed)


func _draw() -> void:
	if _circle_time <= 0.0:
		return
	var radius := CIRCLE_RADIUS * (1.35 if Skills.is_unlocked(&"circle_3") else 1.0)
	var fade := minf(1.0, _circle_time * 2.0)
	var c := Color(0.75, 0.42, 1.15, 0.26 * fade)
	draw_circle(_circle_position, radius, Color(0.20, 0.10, 0.34, 0.12 * fade))
	draw_arc(_circle_position, radius, 0.0, TAU, 64, c, 2.0, true)
	draw_arc(_circle_position, radius * 0.82, _circle_phase, _circle_phase + TAU, 48, Color(c.r, c.g, c.b, c.a * 0.6), 1.0, true)
	for i in 8:
		var angle := float(i) * TAU / 8.0 + _circle_phase
		var point := _circle_position + Vector2.from_angle(angle) * radius * 0.91
		draw_circle(point, 2.5, Color(c.r, c.g, c.b, c.a * 1.6))
