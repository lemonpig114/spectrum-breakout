extends Node
var failures := 0
var main: Node
var combat: WeaponCombat
var manager: ProjectileManager
var enemies: Array[Enemy] = []

func check(ok: bool, label: String) -> void:
	print("WEAPON %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1

func reset(forms: Array) -> WeaponRuntime:
	for shot in manager._active.duplicate(): manager.release(shot)
	combat._events.clear()
	combat._event_hits = 0
	combat._head = 0
	combat._sword_waves.clear()
	combat._wave_pulses.clear()
	combat._scythe_sweeps.clear()
	combat._delayed_hits.clear()
	combat._passive_scythe_cooldown = 0
	combat._scythe_secondary_cooldown = 0
	combat._derivative_frame = -1
	combat._derivatives_this_frame = 0
	var w := WeaponRuntime.new(main.player.weapon.core)
	main.player.weapon = w
	for id in forms: w.acquire_form(id)
	return w

func fire(w: WeaponRuntime) -> void:
	combat.fire_weapon(main.player.global_position, Vector2.RIGHT, w.stats, ColorType.BLUE, false, w)

func tick(count: int) -> void:
	for i in count:
		combat._physics_process(1.0/60)
		for shot in manager._active.duplicate():
			if not shot.orbiting: shot._on_body_entered(enemies[0])

func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2).timeout
	Director.stop()
	main.player.controls_enabled = false
	main.player.set_physics_process(false)
	main.player._invuln = 999
	Skills.unlocked.clear()
	combat = main.projectile_manager.combat
	manager = main.projectile_manager
	for existing in get_tree().get_nodes_in_group(&"enemies"): existing.queue_free()
	await get_tree().process_frame
	for i in 3:
		var e := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
		e.configure(ContentDB.get_enemy(&"chaser_triangle"), main.player, ColorType.RED)
		main.world.add_child(e)
		e.global_position = main.player.global_position + Vector2(80 + i*50, 0)
		e.set_physics_process(false)
		e.max_health = 1000000
		e.health = e.max_health
		enemies.append(e)
	var w := reset([&"lightning", &"sword"])
	check(w.primary_form == &"lightning", "new weapon never replaces chosen main form")
	check(w.select_primary(&"sword") and w.primary_data().damage_scale == 1.2, "player chooses main form and its own multiplier")
	w = reset([&"star", &"sword"])
	fire(w)
	var shot: Projectile = manager._active.back()
	check(is_equal_approx(shot.damage, w.stats.get_value(&"damage")*0.8*1.2), "secondary sword adds twenty percent weapon multiplier")
	var shot_weapon := shot.weapon
	w.acquire_form(&"lightning")
	w.select_primary(&"lightning")
	check(shot_weapon.primary_form == &"star" and not shot_weapon.has_form(&"lightning"), "in-flight attack freezes main form and passive set")
	w = reset([&"lightning", &"star"])
	combat.resolve_hit(combat, enemies[0], 100, ColorType.BLUE, Vector2.RIGHT, false, &"weapon_lightning", true, true, false, &"lightning", w, true, combat.new_budget())
	var splits := combat._events.filter(func(e): return e.kind == &"split")
	check(splits.size() == 1 and is_equal_approx(splits[0].damage_scale * combat._weapon_damage(w.stats, ColorType.BLUE, false), 20), "secondary star creates five twenty-percent fragments")
	combat._physics_process(0)
	check(manager._active.size() == 5, "star secondary emits five physical fragments")
	for fragment in manager._active:
		check(not fragment.can_split and fragment.range_limit <= 160 and fragment.lifetime <= 0.45, "star fragments are short-range and cannot self-split")
	w = reset([&"star", &"wave"])
	combat.resolve_hit(combat, enemies[0], 100, ColorType.BLUE, Vector2.RIGHT, false, &"weapon_star", true, true, false, &"star", w, true, combat.new_budget())
	check(combat._delayed_hits.size() == 2 and combat._delayed_hits[0].damage == 20, "secondary water adds two twenty-percent judgments")
	w = reset([&"star", &"cannon"])
	combat.resolve_hit(combat, enemies[0], 100, ColorType.BLUE, Vector2.RIGHT, false, &"weapon_star", true, true, false, &"star", w, true, combat.new_budget())
	var blasts := combat._events.filter(func(e): return e.kind == &"explosion")
	check(blasts.size() == 1 and blasts[0].damage == 40, "secondary cannon emits one forty-percent splash")
	reset([&"star", &"cannon"])
	w = main.player.weapon
	Skills.unlock(&"splash_1")
	combat.resolve_hit(combat, enemies[0], 100, ColorType.BLUE, Vector2.RIGHT, false, &"weapon_star", true, true, false, &"star", w, true, combat.new_budget())
	blasts = combat._events.filter(func(e): return e.kind == &"explosion")
	check(blasts.size() == 1 and is_equal_approx(blasts[0].damage, (Skills.splash_ratio()+0.2)*100) and is_equal_approx(blasts[0].radius, Skills.splash_radius()*1.4), "cannon replaces skill splash with ratio plus twenty points and forty percent radius")
	Skills.unlocked.clear()
	w = reset([&"star", &"scythe", &"lightning", &"wave"])
	fire(w)
	var sweeps := combat._events.filter(func(e): return e.kind == &"scythe")
	check(sweeps.size() == 1 and sweeps[0].isolated and sweeps[0].weapon.owned_forms == [&"scythe"], "passive scythe excludes all other weapons")
	check(is_equal_approx(combat._passive_scythe_cooldown, 4.0/w.get_final_fire_rate()), "passive scythe rate is twenty-five percent of primary rate")
	fire(w)
	check(combat._events.filter(func(e): return e.kind == &"scythe").size() == 1, "pellets do not multiply passive scythe timer")
	var duration := WeaponCombat.SCYTHE_SWEEP_DURATION
	var quarter := WeaponCombat.scythe_turn_progress(duration*0.25)
	var middle := WeaponCombat.scythe_turn_progress(duration*0.5)
	var last := WeaponCombat.scythe_turn_progress(duration*0.75)
	check(middle-quarter > quarter and 1.0-last < last-middle and WeaponCombat.scythe_turn_progress(duration) == 1.0,
		"scythe accelerates then decelerates and completes a full revolution")
	w = reset([&"scythe"])
	fire(w)
	combat._physics_process(0.01)
	var player_start: Vector2 = main.player.global_position
	main.player.global_position += Vector2(35,20)
	combat._physics_process(0.01)
	check(combat._scythe_sweeps[0].origin == main.player.global_position, "main scythe without sword follows moving player")
	main.player.global_position = player_start
	w = reset([&"sword", &"scythe"])
	fire(w)
	combat._physics_process(0.1)
	check(combat._scythe_sweeps.size() == 1 and combat._scythe_sweeps[0].thrown and combat._sword_waves.is_empty(), "sword scythe special throws one spinning scythe")
	check(is_equal_approx(float(combat._scythe_sweeps[0].radius),w.attack_range(&"scythe")*0.8), "thrown fusion scythe is eighty percent of normal scythe size")
	var origin: Vector2 = combat._scythe_sweeps[0].origin
	combat._physics_process(0.1)
	check(combat._scythe_sweeps[0].origin != origin, "thrown scythe center advances while spinning")
	for primary in WeaponRuntime.PRIMARY_ORDER:
		for secondary in WeaponRuntime.PRIMARY_ORDER:
			if primary == secondary: continue
			w = reset([primary, secondary])
			var before := enemies[0].health
			fire(w)
			tick(42)
			check(enemies[0].health < before, "ordered fusion attacks: %s + %s" % [primary, secondary])
			check(combat._events.size()-combat._head <= WeaponCombat.QUEUE_LIMIT, "fusion queue remains bounded")
	w = reset([&"cannon", &"boomerang"])
	fire(w)
	var shell: Projectile = manager._active.back()
	shell.global_position = enemies[0].global_position
	shell._on_body_entered(enemies[0])
	check(shell._return_extension >= 0 and shell.active_index >= 0, "cannon explodes then extends toward its return instead of disappearing")
	shell._start_return()
	shell._simulate_projectile(0.01)
	check(shell._returning and shell.direction.dot((main.player.global_position-shell.global_position).normalized()) > 0.9, "cannon boomerang steers home")
	w = reset([&"star"])
	for i in 100:
		combat.enqueue({"kind": &"water_echo", "target": weakref(enemies[0]), "damage": 1.0,
			"direction": Vector2.RIGHT, "color": ColorType.BLUE, "weapon": w,
			"weapon_id": &"star", "source_kind": &"clone", "budget": combat.new_budget()}, false)
	combat._physics_process(0)
	var remaining := combat._events.size()-combat._head
	check(remaining == 100-WeaponCombat.QUEUED_HITS_PER_FRAME, "hit budget retains unprocessed FIFO entries")
	combat._physics_process(0)
	check(combat._events.size()-combat._head == remaining, "physics catch-up does not multiply the render-frame hit budget")
	for i in 5:
		combat._event_render_frame = -1
		combat._physics_process(0)
	check(combat._events.is_empty(), "accepted queued hits finish across subsequent frames")
	w = reset([&"star"])
	var crowd: Array[Enemy] = []
	var blast_origin: Vector2 = main.player.global_position + Vector2(300,300)
	for i in 30:
		var target := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
		target.configure(ContentDB.get_enemy(&"chaser_triangle"), main.player, ColorType.RED)
		main.world.add_child(target)
		target.global_position = blast_origin + Vector2(i%5,i/5)
		target.set_physics_process(false)
		target.max_health = 1000
		target.health = 1000
		crowd.append(target)
	manager._collision_frame = -1
	combat.enqueue({"kind": &"explosion", "origin": blast_origin, "damage": 1.0, "radius": 30.0,
		"color": ColorType.BLUE, "weapon": w, "budget": combat.new_budget(), "secondary": true, "clone": true}, false)
	combat._physics_process(0)
	check(crowd.filter(func(e): return e.health < 1000).size() == WeaponCombat.QUEUED_HITS_PER_FRAME, "large explosion slices targets at render budget")
	combat._event_render_frame = -1
	combat._physics_process(0)
	check(crowd.all(func(e): return e.health < 1000 and is_equal_approx(e.health,crowd[0].health)), "explosion continuation hits remaining targets exactly once")
	for target in crowd: target.queue_free()
	w = reset([&"lightning", &"sword", &"star"])
	var panel: WeaponChoicePanel = main.weapon_choice_panel
	panel.open_loadout(main.player)
	check(panel._primary_mode and panel._choices.size() == 3, "pause loadout exposes all owned forms")
	panel._choose(1)
	check(w.primary_form == &"sword" and not panel.visible, "touchable loadout selection changes main form")
	check(GameSave.snapshot(main).primary_weapon == &"sword", "save contains explicit main form")
	var ghost := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	ghost.configure(ContentDB.get_enemy(&"chaser_triangle"),main.player)
	main.world.add_child(ghost)
	var stale := {"kind": &"lightning", "excluded": ghost, "origin": main.player.global_position,
		"direction": Vector2.RIGHT, "weapon": w, "damage": 1.0, "color": ColorType.BLUE,
		"heavy": false, "secondary": true, "budget": combat.new_budget()}
	ghost.free()
	combat._lightning(stale)
	check(main.pause_panel.character_stat_rows().size() >= 20, "character panel exposes maintained combat and resource attributes")
	print("WEAPON EXPANSION TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
