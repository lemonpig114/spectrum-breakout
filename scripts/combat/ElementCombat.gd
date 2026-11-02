class_name ElementCombat
extends Node2D

# All secondary damage is queued, never invoked recursively from a death callback.
const LIMIT := 512
const PER_FRAME := 48
const PER_ROOT := 128
var events: Array[Dictionary] = []
var fields: Array[Dictionary] = []
var charges: Array[Dictionary] = []
var origin_bursts: Array[Dictionary] = []
var clock := 0.0
var _active_budget: Dictionary = {}
var _frame_hits := 0

func clear() -> void:
	events.clear()
	fields.clear()
	charges.clear()
	origin_bursts.clear()
	_active_budget = {}
	clock = 0.0
	queue_redraw()

func enqueue(event: Dictionary, budget: Dictionary = {}) -> bool:
	if events.size()+charges.size() >= LIMIT: return false
	if budget.is_empty(): budget = {"count": 0}
	if int(budget.get("count",0)) >= PER_ROOT: return false
	budget.count = int(budget.get("count",0))+1
	event.budget = budget
	events.append(event)
	return true

func attach(enemy: Enemy, color: int, amount: float, spread := false, budget: Dictionary = {}) -> void:
	if enemy.is_dead or color < 0 or amount <= 0: return
	var old := enemy.element_layers.duplicate()
	enemy.element_layers[color] = float(enemy.element_layers.get(color,0.0)) + amount
	if try_origin(enemy,budget): return
	if not spread and Skills.is_unlocked(&"element_2") and clock >= enemy.element_reaction_until:
		for other in old:
			if int(other) == color: continue
			var layers := float(old[other])
			var pair := (1 << int(other)) | (1 << color)
			var kind := &"melt" if pair == ((1<<ColorType.BLUE)|(1<<ColorType.RED)) else (&"impact" if pair == ((1<<ColorType.BLUE)|(1<<ColorType.GREEN)) else &"burn")
			enemy.element_layers.erase(other)
			enemy.element_reaction_until = clock+0.5
			enqueue({"kind":kind,"at":enemy.global_position,"target":weakref(enemy),"damage":layers,"color":color},budget)
			break
	enemy._refresh_status_icons()

func try_origin(enemy: Enemy, budget: Dictionary = {}) -> bool:
	if not Skills.is_unlocked(&"element_4") or enemy.element_layers.size() < 3 or clock < enemy.element_reaction_until: return false
	var layers := 0.0
	for value in enemy.element_layers.values(): layers += float(value)
	enemy.element_layers.clear()
	enemy.element_reaction_until = clock+0.5
	var base := Skills.player.weapon.get_final_damage() if is_instance_valid(Skills.player) else 0.0
	enqueue({"kind":&"origin","at":enemy.global_position,"target":weakref(enemy),"damage":layers+base,"color":enemy.color_index},budget)
	enemy._refresh_status_icons()
	return true

func trigger_origin(enemy: Enemy, layers: float) -> bool:
	if not is_instance_valid(enemy) or enemy.is_dead: return false
	var base := Skills.player.weapon.get_final_damage() if is_instance_valid(Skills.player) else 0.0
	return enqueue({"kind":&"origin","at":enemy.global_position,"target":weakref(enemy),"damage":maxf(0,layers)+base,"color":enemy.color_index})

func reaction_radius(kind: StringName) -> float:
	if kind != &"origin": return 200.0
	var camera := get_viewport().get_camera_2d()
	return maxf(700.0,get_viewport_rect().size.length()*0.85/(camera.zoom.x if camera != null else 1.0))

func on_attack(enemy: Enemy, context: DamageContext) -> void:
	if not context.has_tag(&"element_secondary") and Skills.is_unlocked(&"element_1") and context.color_index >= 0:
		attach(enemy,context.color_index,(context.base_damage if context.base_damage > 0 else context.amount)*0.5*(1.0 if context.has_tag(&"elemental") else Skills.elemental_multiplier()),false,_active_budget)
	if context.has_tag(&"weakness"):
		enemy.weak_last_color = context.color_index
		enemy.weak_last_damage = context.base_damage if context.base_damage > 0 else context.amount
		if enemy.health <= 0: weak_kill(enemy)

func weak_kill(enemy: Enemy) -> void:
	if enemy.weak_blast_queued or not Skills.is_unlocked(&"weak_4") or enemy.weak_last_damage <= 0: return
	enemy.weak_blast_queued = true
	if RunState.rng.randf() < 0.20:
		enqueue({"kind":&"weak","at":enemy.global_position,"damage":enemy.weak_last_damage*1.5,"color":enemy.weak_last_color},_active_budget)

func on_death(enemy: Enemy) -> void:
	if not Skills.is_unlocked(&"element_4"): return
	for color in enemy.element_layers:
		enqueue({"kind":&"death","at":enemy.global_position,"damage":float(enemy.element_layers[color]),"color":int(color)},_active_budget)
	enemy.element_layers.clear()

func tick(enemy: Enemy) -> void:
	try_origin(enemy)
	for color in enemy.element_layers.keys():
		var amount := float(enemy.element_layers[color])
		if amount <= 10.0: enemy.element_layers.erase(color)
		else: enemy.element_layers[color] = amount*0.5
		_hit(enemy,amount,int(color),false,false)
		if enemy.is_dead: break
	enemy._refresh_status_icons()

func _process(delta: float) -> void:
	if get_tree().paused or not RunState.is_running or RunState.is_dead: return
	clock += delta
	var had_charge_visuals := not charges.is_empty() or not origin_bursts.is_empty()
	for i in range(charges.size()-1,-1,-1):
		var charge := charges[i]
		if charge.event.has("target"):
			var target: Variant = charge.event.target.get_ref()
			if is_instance_valid(target) and not target.is_dead: charge.event.at = target.global_position
		charge.age = minf(float(charge.duration),float(charge.age)+delta)
		if float(charge.age) >= float(charge.duration)-0.000001:
			charges.remove_at(i)
			charge.event.charged = true
			events.append(charge.event)
	for i in range(origin_bursts.size()-1,-1,-1):
		origin_bursts[i].age = float(origin_bursts[i].age)+delta
		if float(origin_bursts[i].age) >= 0.8: origin_bursts.remove_at(i)
	if had_charge_visuals: queue_redraw()
	var had_fields := not fields.is_empty()
	for i in range(fields.size()-1,-1,-1):
		var f := fields[i]
		var step := minf(delta,5.0-float(f.age))
		f.age = float(f.age)+step
		f.tick = float(f.tick)+step
		while float(f.tick) >= 0.5:
			f.tick = float(f.tick)-0.5
			enqueue({"kind":&"field_tick","at":f.at,"damage":f.damage,"color":f.color},f.budget)
		if float(f.age) >= 5.0: fields.remove_at(i)
	if had_fields: queue_redraw()
	# Process only the queue prefix present at frame start, bounding death propagation.
	var count := mini(PER_FRAME,events.size())
	_frame_hits = 0
	for i in count:
		if _frame_hits >= 64 or events.is_empty() or RunState.is_dead: break
		var event: Dictionary = events.pop_front()
		_active_budget = event.budget
		_resolve(event)
	_active_budget = {}
	if not fields.is_empty(): queue_redraw()

func _resolve(e: Dictionary) -> void:
	var kind: StringName = e.kind
	if kind in [&"impact", &"origin"] and not e.get("charged",false):
		if events.size()+charges.size() < LIMIT:
			charges.append({"event":e,"age":0.0,"duration":1.0 if kind == &"origin" else 0.3,"radius":reaction_radius(kind)})
			queue_redraw()
		return
	var names := {&"melt":"融化",&"impact":"冲击",&"burn":"燃烧",&"origin":"源反应"}
	if names.has(kind) and not e.get("started",false):
		FX.text_popup(e.at+Vector2(0,-100 if kind == &"origin" else -72),names[kind],Color(1.3,1.3,1.6) if kind == &"origin" else RunState.color_of(e.color),30 if kind == &"origin" else 24)
	if kind == &"melt":
		var target: Variant = e.target.get_ref()
		if is_instance_valid(target) and not target.is_dead: _hit(target,float(e.damage)*5,e.color)
		return
	var radius := 82.0
	var ratio := 1.0
	match kind:
		&"impact": radius = 200.0; ratio = 1.5
		&"burn":
			radius = 110.0; ratio = 0.7
			if not e.get("started",false) and fields.size() < 24: fields.append({"at":e.at,"damage":float(e.damage)*0.5,"color":e.color,"age":0.0,"tick":0.0,"budget":e.budget})
		&"field_tick": radius = 110.0
		&"origin":
			radius = reaction_radius(kind)
	if kind not in [&"field_tick", &"origin"] and not e.get("started",false):
		FX.hit_burst(e.at,RunState.color_of(e.color),radius,0.45 if kind == &"origin" else 0.22,EnergyBurst.STYLE_PANIC if kind == &"origin" else EnergyBurst.STYLE_SPLASH)
	if kind == &"origin" and not e.get("started",false) and origin_bursts.size() < 24:
		origin_bursts.append({"at":e.at,"radius":radius,"age":0.0})
		FX.hit_burst(e.at,Color(1.2,1.3,1.8),80,0.4,EnergyBurst.STYLE_STAR)
		queue_redraw()
	e.started = true
	if not e.has("targets"):
		e.targets = Skills.player.projectile_manager.enemies_near(e.at,radius).duplicate() if is_instance_valid(Skills.player) else []
		e.cursor = 0
	while int(e.cursor) < e.targets.size():
		if _frame_hits >= 64:
			events.push_front(e)
			return
		var node: Variant = e.targets[int(e.cursor)]
		e.cursor = int(e.cursor)+1
		if not is_instance_valid(node): continue
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead or enemy.global_position.distance_squared_to(e.at) > (radius+enemy.radius)**2: continue
		_frame_hits += 1
		if kind == &"weak":
			var hit := Skills.build_hit_context(self,enemy,e.damage,e.color)
			hit.add_tag(&"weak_explosion")
			enemy.take_damage(hit)
			if not enemy.is_dead: enemy.recolor(e.color)
		else:
			if kind == &"death" and Skills.is_unlocked(&"element_1"):
				attach(enemy,e.color,float(e.damage)*0.5,true,e.budget)
			_hit(enemy,float(e.damage)*ratio,e.color,kind == &"origin",kind == &"origin")

func _hit(enemy: Enemy, amount: float, color: int, force_weak := false, large := false) -> void:
	var hit := DamageContext.new()
	hit.source = self
	hit.target = enemy
	hit.base_damage = amount
	hit.amount = amount*(Skills.weakness_multiplier() if force_weak else 1.0)
	hit.color_index = color
	hit.hit_position = enemy.global_position
	hit.add_tag(&"elemental")
	hit.add_tag(&"element_secondary")
	if force_weak: hit.add_tag(&"weakness"); hit.add_tag(&"guaranteed_weakness")
	if large: hit.add_tag(&"element_origin")
	enemy.take_damage(hit)
	if not enemy.is_dead: enemy._healthbar.pulse_status(&"burn" if color == ColorType.RED else (&"poison" if color == ColorType.GREEN else &"ice"))

func _draw() -> void:
	for charge in charges:
		var at: Vector2 = charge.event.at
		var t := clampf(float(charge.age)/float(charge.duration),0,1)
		var source: bool = charge.event.kind == &"origin"
		var radius: float = lerpf(minf(180.0,float(charge.radius)*0.4),18.0,t*t)
		var tint := RunState.color_of(charge.event.color)
		draw_circle(at,8+t*16,Color(tint,0.08+t*0.12))
		for ring in (3 if source else 1):
			var c := RunState.color_of(ring) if source else tint
			var angle := float(charge.age)*(2.0+ring)
			draw_arc(at,radius+ring*9,angle,angle+TAU*0.8,48,Color(c,0.2+t*0.65),1.5+t*2,true)
			for ray in (8 if source else 4):
				var direction := Vector2.from_angle(angle+TAU*ray/(8.0 if source else 4.0))
				draw_line(at+direction*(radius+24),at+direction*radius,Color(c,0.1+t*0.55),1.5,true)
		draw_circle(at,3+t*7,Color(2,2,2,0.35+t*0.6))
	for burst in origin_bursts:
		var t := clampf(float(burst.age)/0.8,0,1)
		var radius: float = float(burst.radius)*(1-pow(1-t,3))
		var at: Vector2 = burst.at
		for ring in 3:
			var c := RunState.color_of(ring)
			draw_arc(at,maxf(1,radius-ring*14),0,TAU,96,Color(c,(1-t)*0.65),maxf(1,7*(1-t)),true)
		for ray in 18:
			var direction := Vector2.from_angle(TAU*ray/18.0)
			draw_line(at+direction*radius*0.6,at+direction*radius,Color(RunState.color_of(ray%3),(1-t)*0.45),2,true)
	for field in fields:
		var color := RunState.color_of(field.color)
		draw_circle(field.at,110.0,Color(color,0.045))
		draw_arc(field.at,110,0,TAU,32,Color(color,0.25),1.5,true)
