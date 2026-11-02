extends Node
var failures := 0
var main: Node
var ec: ElementCombat
func check(ok: bool, label: String) -> void:
	print("REWORK %s %s" % ["PASS" if ok else "FAIL",label])
	if not ok: failures += 1
func enemy(at: Vector2 = Vector2(300,0)) -> Enemy:
	var e := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	e.configure(ContentDB.get_enemy(&"chaser_hex"),main.player,ColorType.RED)
	main.world.add_child(e)
	e.global_position = at
	e.max_health = 1000000
	e.health = e.max_health
	e.set_physics_process(false)
	return e
func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2).timeout
	Director.stop()
	main.player.controls_enabled = false
	main.player.set_physics_process(false)
	ec = Skills.element_combat
	ec.set_process(false)
	for e in get_tree().get_nodes_in_group(&"enemies"): e.queue_free()
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--preview-origin"):
		var preview_target := enemy(Vector2(180,0))
		ec.trigger_origin(preview_target,1000)
		ec._process(0)
		ec._process(0.65)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/visual_origin_charge.png")
		ec._process(0.35)
		ec._process(0.10)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/visual_origin_burst.png")
		get_tree().quit()
		return
	check(Skills.nodes.size()==84,"21 branches with four tiers")
	Skills.unlock(&"weak_1",true)
	Skills.unlock(&"weak_2",true)
	var e := enemy()
	main.player.stats.set_base(&"crit_chance",0.8)
	var h := Skills.build_hit_context(main.player,e,10,ColorType.BLUE)
	check(h.is_crit and is_equal_approx(h.amount,40),"weak attacks gain twenty crit points and fifty crit damage points")
	main.player.stats.set_base(&"crit_chance",0)
	Skills.unlock(&"weak_4",true)
	h = Skills.build_hit_context(main.player,e,100,ColorType.BLUE,false,false)
	var before := e.health
	e.take_damage(h)
	check(is_equal_approx(before-e.health,160),"weak hit changes hex thirty percent armor to twenty")
	Skills.unlock(&"weak_3",true)
	e.health = e.max_health*0.1
	Skills.try_execute(e,true)
	check(e.is_dead,"third weak tier inherits execution")
	e = enemy()
	check(Skills.relics.filter(func(relic): return relic.skill_item).all(func(relic): return relic.id in [&"epic_classic_revolver", &"epic_shield_generator"]),"energy gifts exclude economic and treasure-finding utility items")
	Skills.unlock(&"energy_1",true)
	Skills.unlock(&"energy_2",true)
	var count := Skills.owned_relics.size()
	Skills.unlock(&"energy_3",true)
	check(Skills.owned_relics.size()==count+1 and is_equal_approx(Skills.energy_regen_multiplier(),1.6),"energy three adds regen and one eligible item")
	Skills.unlock(&"energy_4",true)
	RunState.energy = 0
	check(RunState.max_energy==8 and is_equal_approx(Skills.energy_regen_multiplier(),2.6),"energy four cap and low energy recovery")
	RunState.energy = RunState.max_energy
	check(is_equal_approx(Skills.energy_regen_multiplier(),1.6),"energy four bonus requires below half")
	Skills.owned_relics.clear()
	Skills.grant_relic(&"epic_classic_revolver")
	Skills.grant_relic(&"epic_classic_revolver")
	Skills._on_color_changed_relics(ColorType.BLUE)
	check(Skills._revolver_volleys.back().remaining==15 and Skills._revolver_volleys.back().scale==2,"stacked revolver adds damage not projectile count")
	Skills.unlock(&"shotgun_1",true)
	check(is_equal_approx(main.player.weapon.attack_range(),480),"shotgun one range penalty")
	Skills.unlock(&"shotgun_2",true)
	var shot: Projectile = main.projectile_manager.fire(Vector2.ZERO,Vector2.RIGHT,main.player.weapon.stats,ColorType.BLUE,main.player.weapon.core)
	shot.distance_traveled = 0
	var near := Skills.build_hit_context(shot,e,10,ColorType.BLUE,false,false)
	shot.distance_traveled = main.player.body_radius*4
	var far := Skills.build_hit_context(shot,e,10,ColorType.BLUE,false,false)
	check(is_equal_approx(near.amount,far.amount*3),"close damage falls from plus two hundred percent to zero")
	Skills.unlock(&"shotgun_3",true)
	var mult: float = main.player.weapon.stats.get_value(&"damage_mult")
	Skills.unlock(&"shotgun_4",true)
	check(is_equal_approx(mult,main.player.weapon.stats.get_value(&"damage_mult")) and is_equal_approx(main.player.weapon.attack_range(),300),"shotgun four exchanges damage penalty for range")
	Skills.unlock(&"element_1",true)
	ec.clear()
	ec.attach(e,ColorType.RED,100)
	before = e.health
	ec.tick(e)
	check(is_equal_approx(e.element_layers[ColorType.RED],50) and is_equal_approx(before-e.health,70),"one-second element tick deals full pool and halves it")
	Skills.unlock(&"element_2",true)
	ec.attach(e,ColorType.BLUE,20)
	check(ec.events.back().kind==&"melt" and not e.element_layers.has(ColorType.RED),"red blue melt consumes previous pool before replacement")
	before = e.health
	ec._resolve(ec.events.pop_front())
	check(is_equal_approx(before-e.health,175.0),"melt deals five hundred percent of consumed layers exactly once")
	ec.attach(e,ColorType.GREEN,30)
	check(e.element_layers.size()==2,"reaction cooldown permits real concurrent attachments")
	Skills.unlock(&"element_3",true)
	Skills.unlock(&"element_4",true)
	ec.attach(e,ColorType.RED,40,true)
	check(e.element_layers.size()==3,"death spread can preserve all three elements during cooldown")
	ec.clock += 0.5
	check(ec.try_origin(e) and e.element_layers.is_empty() and ec.events.back().kind==&"origin","actual simultaneous three colors trigger source reaction after cooldown")
	ec.clear()
	e.element_layers.clear()
	e.element_reaction_until = 0
	ec.attach(e,ColorType.BLUE,100)
	ec.attach(e,ColorType.GREEN,20)
	main.projectile_manager._collision_frame = -1
	before = e.health
	ec._resolve(ec.events.pop_front())
	check(e.health==before and ec.charges.size()==1,"impact charges without immediate damage")
	ec._process(0.29)
	check(e.health==before,"impact does not damage before point three seconds")
	ec._process(0.01)
	check(is_equal_approx(before-e.health,105.0),"blue green impact deals one hundred fifty percent layers in its area")
	ec.clear()
	e.element_layers.clear()
	ec.attach(e,ColorType.RED,100,true)
	ec.on_death(e)
	check(ec.events.size()==1 and ec.events[0].kind==&"death","attached enemy death queues elemental explosion")
	ec.clear()
	var root := {"count":0}
	for i in 1000: ec.enqueue({"kind":&"field_tick","at":Vector2.ZERO,"damage":1,"color":0},root)
	check(ec.events.size()==128,"one root cannot recursively generate unlimited effects")
	ec.clear()
	var field := {"kind":&"burn","at":Vector2.ZERO,"damage":100.0,"color":ColorType.RED,"budget":{"count":0}}
	ec._resolve(field)
	check(ec.fields.size()==1,"burn creates a bounded five-second field")
	ec._process(5.0)
	check(ec.fields.is_empty(),"burn field finishes at five seconds including last scheduled tick")
	ec.clear()
	e.element_layers.clear()
	e.health = 1
	var chosen_seed := 0
	for candidate in 100:
		var probe := RandomNumberGenerator.new()
		probe.seed = candidate
		if probe.randf() < 0.20:
			chosen_seed = candidate
			break
	RunState.rng.seed = chosen_seed
	var lethal := DamageContext.new()
	lethal.amount = 10
	lethal.base_damage = 10
	lethal.color_index = ColorType.BLUE
	lethal.add_tag(&"weakness")
	e.take_damage(lethal)
	var blasts := ec.events.filter(func(event): return event.kind == &"weak")
	check(blasts.size()==1 and is_equal_approx(blasts[0].damage,15),"weak kill queues one hundred fifty percent explosion without double-counting crit")
	if not blasts.is_empty():
		var target := enemy(e.global_position)
		main.player.stats.set_base(&"crit_chance",1.0)
		main.projectile_manager._collision_frame = -1
		before = target.health
		ec._frame_hits = 0
		ec._resolve(blasts[0])
		check(is_equal_approx(before-target.health,48) and target.color_index==ColorType.BLUE,"weak explosion rolls crit and weakness then recolors surviving target")
	ec.clear()
	var victim := enemy(Vector2(100,0))
	var saved_health := victim.health
	check(ec.trigger_origin(victim,1000),"console hook schedules origin without unlocking elemental skills")
	ec._process(0)
	check(victim.health==saved_health and ec.charges.size()==1,"source starts one-second charge")
	ec._process(0.99)
	check(victim.health==saved_health,"source does not damage before one second")
	main.projectile_manager._collision_frame = -1
	ec._process(0.01)
	check(victim.health < saved_health and ec.origin_bursts.size()==1,"source damage and ornate burst occur together after one second")
	ec.clear()
	ec.trigger_origin(victim,100)
	ec._process(0)
	victim.free()
	ec._process(1)
	check(ec.charges.is_empty(),"freed source target finishes safely at last position")
	ec.clear()
	if main.debug_console != null:
		var console_target := enemy()
		main.debug_console._submit("origin 1000")
		check(ec.events.size()==1 and ec.events[0].kind==&"origin","console origin X creates exactly one source event")
		var prior_count := ec.events.size()
		main.debug_console._submit("origin -1")
		check(ec.events.size()==prior_count,"console rejects invalid damage")
		ec.clear()
	ec.clear()
	var tail_target := enemy()
	ec.attach(tail_target,ColorType.RED,10)
	var tail_before := tail_target.health
	ec._process(0.49)
	check(tail_target.element_layers.has(ColorType.RED) and tail_target.health==tail_before and ec.events.is_empty(),"small attachment remains available for reactions until next dot tick")
	ec.tick(tail_target)
	check(tail_target.element_layers.is_empty() and is_equal_approx(tail_before-tail_target.health,7.0),"next one-second tick settles ten layers once at full strength")
	ec.attach(tail_target,ColorType.RED,20)
	tail_before = tail_target.health
	ec.tick(tail_target)
	check(is_equal_approx(float(tail_target.element_layers.get(ColorType.RED,0)),10.0) and is_equal_approx(tail_before-tail_target.health,14.0),"twenty layers deal twenty and retain ten until the following tick")
	ec.tick(tail_target)
	check(tail_target.element_layers.is_empty() and is_equal_approx(tail_before-tail_target.health,21.0),"following tick settles the ten-layer tail")
	ec.tick(tail_target)
	check(is_equal_approx(tail_before-tail_target.health,21.0),"settled tail cannot damage again")
	ec.clear()
	tail_target.element_reaction_until = 0
	ec.attach(tail_target,ColorType.RED,5)
	ec.attach(tail_target,ColorType.BLUE,20)
	check(ec.events.size()==1 and ec.events[0].kind==&"melt" and ec.events[0].damage==5,"sub-ten attachment can react before its scheduled tick")
	ec.clear()
	var timed_target := enemy()
	ec.attach(timed_target,ColorType.RED,10)
	var timed_before := timed_target.health
	timed_target._on_global_dot_tick(timed_target._dot_bucket)
	check(timed_target.health==timed_before and timed_target.element_layers.has(ColorType.RED),"legacy half-second timer cannot consume elemental attachment")
	timed_target._on_element_tick(timed_target._dot_bucket)
	check(timed_target.health < timed_before and timed_target.element_layers.is_empty(),"separate one-second elemental timer settles the small pool")
	var legacy := StatModifierResource.new()
	legacy.stat = &"elemental_damage"
	legacy.value = 0.3
	legacy.source = &"weak_2"
	main.player.stats.add_modifier(legacy)
	GameSave.migrate_legacy_skill_balance(main.player,0)
	check(is_equal_approx(Skills.elemental_multiplier(),1.5) and is_equal_approx(main.player.weapon.stats.get_value(&"range_mult"),0.5),"legacy save migration removes old weak elemental bonus and reapplies new shotgun range penalties")
	print("SKILL REWORK TEST %s (%d failures)" % ["PASS" if failures==0 else "FAIL",failures])
	get_tree().quit(0 if failures==0 else 1)
