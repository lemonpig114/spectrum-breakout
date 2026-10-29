class_name WeaponCombat
extends Node2D

## 直接命中统一结算；派生攻击只入 FIFO 队列，逐物理帧限额处理。
const EVENTS_PER_FRAME := 256
const DERIVATIVES_PER_ATTACK := 128
const QUEUE_LIMIT := 4096
const VISUAL_LIMIT := 160
const DERIVATIVES_PER_FRAME := 8
const SWORD_WAVE_DISTANCE := 145.0
const SWORD_WAVE_WIDTH := 108.0
const SWORD_WAVE_DEPTH := 34.0
const SWORD_WAVE_DURATION := 0.28
const CHAIN_RANGE := 210.0

var manager
var player
var _events: Array[Dictionary] = []
var _head := 0
var _visuals: Array[Dictionary] = []
var _sword_waves: Array[Dictionary] = []
var _derivative_frame := -1
var _derivatives_this_frame := 0


func _physics_process(_delta: float) -> void:
	var processed := 0
	while _head < _events.size() and processed < EVENTS_PER_FRAME:
		var event: Dictionary = _events[_head]
		_head += 1
		processed += 1
		match event.kind:
			&"sword": _sword(event)
			&"lightning": _lightning(event)
			&"split": _split(event)
			&"return_arc": _return_arc(event)
	if _head >= _events.size():
		_events.clear()
		_head = 0
	elif _head > 512:
		_events = _events.slice(_head)
		_head = 0
	_advance_sword_waves(_delta)


func _process(delta: float) -> void:
	var had_visuals := not _visuals.is_empty()
	for i in range(_visuals.size() - 1, -1, -1):
		_visuals[i].time = float(_visuals[i].time) - delta
		if _visuals[i].time <= 0.0:
			_visuals.remove_at(i)
	if had_visuals or not _sword_waves.is_empty():
		queue_redraw()


func _draw() -> void:
	for wave in _sword_waves:
		_draw_sword_wave(wave)
	for visual in _visuals:
		var c := RunState.color_of(int(visual.color))
		var alpha := clampf(float(visual.time) / 0.17, 0.0, 1.0)
		draw_line(to_local(visual.from), to_local(visual.to),
			Color(c.r, c.g, c.b, alpha), 3.0 * alpha, true)


func new_budget() -> Dictionary:
	return {"spawned": 0}


func enqueue(event: Dictionary, derivative: bool = true) -> bool:
	if derivative and _events.size() - _head >= QUEUE_LIMIT:
		return false
	if derivative:
		var frame := Engine.get_physics_frames()
		if frame != _derivative_frame:
			_derivative_frame = frame
			_derivatives_this_frame = 0
		if _derivatives_this_frame >= DERIVATIVES_PER_FRAME:
			return false
		var budget: Dictionary = event.get("budget", {})
		if int(budget.get("spawned", 0)) >= DERIVATIVES_PER_ATTACK:
			return false
		budget.spawned = int(budget.get("spawned", 0)) + 1
		_derivatives_this_frame += 1
	_events.append(event)
	return true


func _add_visual(visual: Dictionary) -> void:
	if _visuals.size() < VISUAL_LIMIT:
		_visuals.append(visual)


func fire_weapon(origin: Vector2, direction: Vector2, stats: StatBlock,
		color_index: int, heavy: bool, weapon: WeaponRuntime) -> void:
	var form := weapon.primary_form
	var budget := new_budget()
	var scale := 1.0
	var data := weapon.primary_data()
	if data != null:
		scale = data.damage_scale
	var damage := _weapon_damage(stats, color_index, heavy) * scale
	match form:
		&"sword":
			enqueue({"kind": &"sword", "origin": origin, "direction": direction,
				"damage": damage, "color": color_index, "heavy": heavy,
				"weapon": weapon, "budget": budget, "secondary": false}, false)
		&"lightning":
			enqueue({"kind": &"lightning", "origin": origin, "direction": direction,
				"damage": damage, "color": color_index, "heavy": heavy,
				"weapon": weapon, "budget": budget, "secondary": false}, false)
		_:
			manager.fire(origin, direction, stats, color_index, weapon.core, heavy, scale,
				1.0, 1.0, 1.0, true, StringName("weapon:%s" % String(form)), weapon, budget)


func _weapon_damage(stats: StatBlock, color_index: int, heavy: bool) -> float:
	var raw := stats.get_value(&"damage") + (40.0 if heavy else 0.0)
	var mult := stats.get_value(&"damage_mult") + Skills.lens_damage_bonus(color_index) + Skills.cracked_armor_bonus()
	return raw * mult * stats.get_value(&"damage_final") * (2.5 if heavy else 1.0)


func resolve_hit(source: Node, enemy: Enemy, damage: float, color_index: int,
		direction: Vector2, heavy: bool, source_kind: StringName,
		first_hit: bool, last_hit: bool, allow_crit: bool = true,
		weapon_id: StringName = &"") -> float:
	if enemy == null or enemy.is_dead:
		return 0.0
	var context := Skills.build_hit_context(source, enemy, damage, color_index,
		source_kind != &"clone", allow_crit)
	if source_kind == &"clone":
		context.add_tag(&"clone")
	context.weapon_id = weapon_id
	var before := enemy.health
	enemy.take_damage(context)
	if source_kind != &"clone":
		Skills.apply_relic_projectile_procs(enemy)
	var weakness := context.has_tag(&"weakness")
	var hit_sound := &"hit"
	if context.has_tag(&"super_crit"):
		hit_sound = &"super_crit"
	elif context.is_crit:
		hit_sound = &"crit"
	elif weakness:
		hit_sound = &"weak_hit"
	elif heavy:
		hit_sound = &"hit_heavy"
	Audio.play(hit_sound)
	if not enemy.is_dead and source_kind != &"clone":
		if weakness:
			Skills.on_weakness_hit(enemy, damage, color_index)
		Skills.try_execute(enemy, weakness)
		if Skills.is_unlocked(&"heavy_2") and (enemy.type_data == null or not enemy.type_data.is_boss):
			enemy.apply_knockback(enemy.global_position - direction * 15.0, 300.0, 0.18)
	if source_kind != &"clone":
		Skills.try_gold_on_hit(enemy.global_position)
	var burst_color := RunState.color_of(color_index)
	if context.has_tag(&"super_crit"):
		burst_color = Color(2.8, 2.8, 2.8, 1.0)
	elif weakness or context.is_crit:
		burst_color = burst_color.lerp(Color.WHITE, 0.25)
	FX.hit_spark(enemy.global_position, burst_color, weakness or context.is_crit)
	FX.hit_impact(enemy.global_position, burst_color, direction)
	if context.is_crit:
		FX.hit_burst(enemy.global_position, burst_color, 22.0, 0.16, EnergyBurst.STYLE_STAR)
	if heavy:
		FX.hit_burst(enemy.global_position, burst_color, 38.0, 0.28, EnergyBurst.STYLE_HEAVY)
	if source_kind != &"clone" and Skills.has_splash() and (Skills.splash_every_hit() or first_hit or last_hit):
		Skills.apply_splash(enemy.global_position, context.amount, color_index, enemy)
	return minf(before, context.amount)


func on_projectile_hit(projectile: Node, enemy: Enemy, first_hit: bool, last_hit: bool) -> void:
	var form: StringName = projectile.weapon.primary_form if projectile.weapon != null else &""
	var attribution := form
	if String(projectile.source_kind).begins_with("weapon:"):
		attribution = StringName(String(projectile.source_kind).trim_prefix("weapon:"))
	resolve_hit(projectile, enemy, projectile.damage, projectile.color_index,
		projectile.direction, projectile.is_heavy, projectile.source_kind,
		first_hit, last_hit, projectile.allow_crit, attribution)
	var weapon: WeaponRuntime = projectile.weapon
	if weapon == null or projectile.source_kind == &"clone":
		return
	if weapon.has_form(&"lightning") and form != &"lightning" and not projectile.chain_triggered:
		projectile.chain_triggered = true
		enqueue({"kind": &"lightning", "origin": enemy.global_position,
			"direction": projectile.direction, "damage": projectile.damage * 0.5,
			"color": projectile.color_index, "heavy": false, "weapon": weapon,
			"budget": projectile.budget, "secondary": true, "excluded": enemy})
	if weapon.has_form(&"star") and form != &"star" and projectile.can_split:
		projectile.can_split = false
		enqueue({"kind": &"split", "origin": enemy.global_position,
			"direction": projectile.direction, "damage_scale": projectile.shot_scale * 0.5,
			"color": projectile.color_index, "weapon": weapon, "budget": projectile.budget})
	elif form == &"star" and projectile.can_split:
		projectile.can_split = false
		enqueue({"kind": &"split", "origin": enemy.global_position,
			"direction": projectile.direction, "damage_scale": projectile.shot_scale * 0.5,
			"color": projectile.color_index, "weapon": weapon, "budget": projectile.budget})
	if weapon.has_form(&"sword") and form != &"sword" and form != &"boomerang" and not projectile.sword_triggered:
		projectile.sword_triggered = true
		enqueue({"kind": &"sword", "origin": enemy.global_position,
			"direction": projectile.direction, "damage": projectile.damage * 0.6,
			"color": projectile.color_index, "heavy": false, "weapon": weapon,
			"budget": projectile.budget, "secondary": true})


func _sword(event: Dictionary) -> void:
	if _sword_waves.size() >= 48:
		return
	_sword_waves.append({
		"origin": event.origin, "direction": (event.direction as Vector2).normalized(),
		"age": 0.0, "returning": false, "hit_ids": {}, "return_ids": {},
		"first_hit": true, "damage": event.damage, "color": event.color,
		"heavy": event.heavy, "weapon": event.weapon, "budget": event.budget,
		"secondary": event.secondary,
		"can_return": not bool(event.secondary) and (event.weapon as WeaponRuntime).has_form(&"boomerang"),
	})
	queue_redraw()


func _advance_sword_waves(delta: float) -> void:
	for i in range(_sword_waves.size() - 1, -1, -1):
		var wave: Dictionary = _sword_waves[i]
		wave.age = float(wave.age) + delta
		if float(wave.age) >= SWORD_WAVE_DURATION:
			if bool(wave.can_return) and not bool(wave.returning):
				wave.returning = true
				wave.age = 0.0
			else:
				_sword_waves.remove_at(i)
				queue_redraw()
				continue
		var progress := clampf(float(wave.age) / SWORD_WAVE_DURATION, 0.0, 1.0)
		var distance := lerpf(22.0, SWORD_WAVE_DISTANCE, 1.0 - progress if bool(wave.returning) else progress)
		var direction: Vector2 = wave.direction
		var position: Vector2 = wave.origin + direction * distance
		var side := direction.orthogonal()
		var hit_ids: Dictionary = wave.return_ids if bool(wave.returning) else wave.hit_ids
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Enemy
			if enemy == null or enemy.is_dead or hit_ids.has(enemy.get_instance_id()):
				continue
			var offset := enemy.global_position - position
			if absf(offset.dot(direction)) > SWORD_WAVE_DEPTH * 0.5 + enemy.radius \
					or absf(offset.dot(side)) > SWORD_WAVE_WIDTH * 0.5 + enemy.radius:
				continue
			hit_ids[enemy.get_instance_id()] = true
			var first := bool(wave.first_hit)
			wave.first_hit = false
			resolve_hit(self, enemy, float(wave.damage) * (0.65 if bool(wave.returning) else 1.0),
				int(wave.color), direction, bool(wave.heavy) and not bool(wave.returning),
				&"weapon_sword", first, true, true, &"sword")
			enemy.apply_knockback(wave.origin, 220.0 if enemy.type_data == null or not enemy.type_data.is_boss else 55.0, 0.16)
			if first and not bool(wave.secondary) and not bool(wave.returning):
				_sword_first_hit_effects(wave, enemy)


func _sword_first_hit_effects(wave: Dictionary, enemy: Enemy) -> void:
	var weapon: WeaponRuntime = wave.weapon
	if weapon.has_form(&"lightning"):
		enqueue({"kind": &"lightning", "origin": enemy.global_position,
			"direction": wave.direction, "damage": float(wave.damage) * 0.5,
			"color": wave.color, "heavy": false, "weapon": weapon,
			"budget": wave.budget, "secondary": true, "excluded": enemy})
	if weapon.has_form(&"star"):
		enqueue({"kind": &"split", "origin": enemy.global_position,
			"direction": wave.direction, "damage_scale": 0.6,
			"color": wave.color, "weapon": weapon, "budget": wave.budget})


func _draw_sword_wave(wave: Dictionary) -> void:
	var progress := clampf(float(wave.age) / SWORD_WAVE_DURATION, 0.0, 1.0)
	var fade := pow(1.0 - progress, 1.25) * (0.72 if bool(wave.returning) else 1.0)
	var distance := lerpf(22.0, SWORD_WAVE_DISTANCE, 1.0 - progress if bool(wave.returning) else progress)
	var direction: Vector2 = wave.direction
	var center: Vector2 = to_local(wave.origin + direction * distance)
	var side := direction.orthogonal()
	var color := RunState.color_of(int(wave.color))
	var body := PackedVector2Array()
	var shades := PackedColorArray()
	for half in [-1.0, 1.0]:
		for i in 19:
			var t := float(i) / 18.0 if half < 0.0 else float(18 - i) / 18.0
			var point := _sword_curve(t)
			body.append(center + direction * point.x + side * point.y * half)
			shades.append(Color(color.r, color.g, color.b, fade * 0.16 * sin(PI * t)))
	draw_polygon(body, shades)
	draw_line(center - direction * 26.0, center + direction * 58.0,
		Color(color.r, color.g, color.b, fade * 0.18), 2.0, true)
	# 镜像的两条刀锋共用中心线；不同宽度的色带形成柔光与细高光。
	for half in [-1.0, 1.0]:
		_draw_sword_ribbon(center, direction, side * half, color, fade, Vector2.ZERO, 13.0, 0.28)
		_draw_sword_ribbon(center, direction, side * half, color.lerp(Color.WHITE, 0.5), fade,
			Vector2(0.0, 1.5), 3.0, 0.88)


func _draw_sword_ribbon(center: Vector2, forward: Vector2, side: Vector2,
		color: Color, fade: float, shift: Vector2, thickness: float, opacity: float) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var left_colors := PackedColorArray()
	var right_colors := PackedColorArray()
	for i in 19:
		var t := float(i) / 18.0
		var point := _sword_curve(t)
		var tangent := (_sword_curve(minf(1.0, t + 0.01)) - _sword_curve(maxf(0.0, t - 0.01))).normalized()
		var normal := tangent.orthogonal()
		var taper := pow(sin(PI * t), 0.65)
		var width := thickness * taper * (0.55 + 0.45 * t)
		var base := center + forward * (point.x + shift.x) + side * (point.y + shift.y)
		var normal_world := forward * normal.x + side * normal.y
		left.append(base - normal_world * width)
		right.append(base + normal_world * width)
		var alpha := opacity * fade * taper
		left_colors.append(Color(color.r, color.g, color.b, alpha * 0.25))
		right_colors.append(Color(color.r, color.g, color.b, alpha))
	var points := left.duplicate()
	var colors := left_colors
	for i in range(18, -1, -1):
		points.append(right[i])
		colors.append(right_colors[i])
	draw_polygon(points, colors)


func _sword_curve(t: float) -> Vector2:
	var u := 1.0 - t
	return Vector2(-42.0, 0.0) * (u * u * u) \
		+ Vector2(-5.0, -41.0) * (3.0 * u * u * t) \
		+ Vector2(58.0, -56.0) * (3.0 * u * t * t) \
		+ Vector2(74.0, 0.0) * (t * t * t)


func _lightning(event: Dictionary) -> void:
	var weapon: WeaponRuntime = event.weapon
	var origin: Vector2 = event.origin
	var previous: Enemy = event.get("excluded") as Enemy
	var visited := {}
	if previous != null:
		visited[previous.get_instance_id()] = true
	var path: Array[Vector2] = [origin]
	var pierce := maxi(0, int(player.weapon.stats.get_value(&"pierce")))
	var total := (1 if bool(event.secondary) else 2) + pierce
	for hop in total:
		var best: Enemy
		var best_distance := INF
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Enemy
			if enemy == null or enemy.is_dead or enemy == previous:
				continue
			if hop >= total - pierce and visited.has(enemy.get_instance_id()):
				continue
			var offset := enemy.global_position - origin
			var dist := offset.length_squared()
			if dist > (620.0 if hop == 0 and not bool(event.secondary) else CHAIN_RANGE) ** 2:
				continue
			if hop == 0 and not bool(event.secondary) and absf((event.direction as Vector2).angle_to(offset)) > PI / 4.0:
				continue
			if dist < best_distance:
				best = enemy
				best_distance = dist
		if best == null:
			break
		var damage := float(event.damage) * (0.5 if hop >= total - pierce else 1.0)
		resolve_hit(self, best, damage, int(event.color),
			(best.global_position - origin).normalized(), bool(event.heavy),
			&"weapon_lightning", hop == 0, hop == total - 1, true, &"lightning")
		_add_visual({"kind": &"line", "from": origin, "to": best.global_position,
			"color": event.color, "time": 0.17})
		origin = best.global_position
		path.append(origin)
		visited[best.get_instance_id()] = true
		previous = best
	if not bool(event.secondary) and path.size() > 1:
		if weapon.has_form(&"star"):
			enqueue({"kind": &"split", "origin": origin,
				"direction": event.direction, "damage_scale": 0.5,
				"color": event.color, "weapon": weapon, "budget": event.budget})
		if weapon.has_form(&"boomerang"):
			enqueue({"kind": &"return_arc", "path": path, "damage": float(event.damage) * 0.5,
				"color": event.color, "budget": event.budget})
		if weapon.has_form(&"sword"):
			enqueue({"kind": &"sword", "origin": origin,
				"direction": event.direction, "damage": float(event.damage) * 0.6,
				"color": event.color, "heavy": false, "weapon": weapon,
				"budget": event.budget, "secondary": true})


func _split(event: Dictionary) -> void:
	for i in 5:
		var angle := (event.direction as Vector2).angle() + TAU * float(i) / 5.0
		var direction := Vector2.from_angle(angle)
		var budget: Dictionary = event.budget
		if int(budget.spawned) >= DERIVATIVES_PER_ATTACK:
			break
		budget.spawned = int(budget.spawned) + 1
		manager.fire(event.origin + direction * 12.0, direction, player.weapon.stats,
			int(event.color), player.weapon.core, false, float(event.damage_scale),
			0.65, 1.0, 0.7, false, &"weapon:star", event.weapon, budget, false)


func _return_arc(event: Dictionary) -> void:
	var path: Array = event.path
	var hit_ids := {}
	for i in range(path.size() - 1, 0, -1):
		var start: Vector2 = path[i]
		var finish: Vector2 = path[i - 1]
		_add_visual({"kind": &"line", "from": start, "to": finish,
			"color": event.color, "time": 0.17})
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Enemy
			if enemy == null or enemy.is_dead or hit_ids.has(enemy.get_instance_id()):
				continue
			if Geometry2D.get_closest_point_to_segment(enemy.global_position, start, finish).distance_to(enemy.global_position) <= enemy.radius + 8.0:
				hit_ids[enemy.get_instance_id()] = true
				resolve_hit(self, enemy, float(event.damage), int(event.color),
					(finish - start).normalized(), false, &"weapon_lightning", false, true, true, &"lightning")
