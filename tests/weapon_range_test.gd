extends Node
var failures := 0
var main: Node

func check(ok: bool, label: String) -> void:
	print("RANGE %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1

func clear_shots() -> void:
	for shot in main.projectile_manager._active.duplicate():
		main.projectile_manager.release(shot)

func fire(heavy := false) -> Projectile:
	var w: WeaponRuntime = main.player.weapon
	main.projectile_manager.fire(main.player.global_position, Vector2.RIGHT, w.stats, ColorType.BLUE, w.core,
		heavy, 1, 1, 1, 1, true, &"", w)
	var shot: Projectile = main.projectile_manager._active.back()
	shot.set_physics_process(false)
	return shot

func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2).timeout
	Director.stop()
	main.projectile_manager.centralized_collision = true
	main.player.controls_enabled = false
	main.player.set_physics_process(false)
	main.player._invuln = 999
	clear_shots()
	var w: WeaponRuntime = main.player.weapon
	check(w.attack_range(&"sword") == 150 and w.attack_range(&"scythe") == 130, "initial close weapon ranges")
	w.stats.set_base(&"range_mult", 2)
	check(w.attack_range(&"lightning") == 560 and w.attack_range(&"wave") == 480, "one range multiplier feeds different forms")
	check(w.attack_range(&"star", true) == 3600, "execution shot range triples")
	w.stats.set_base(&"range_mult", 1)
	w.stats.set_base(&"range", 120)
	w.stats.set_base(&"projectile_lifetime", 10)
	var shot := fire()
	shot._simulate_projectile(0.2)
	check(shot.active_index < 0, "range exhaustion returns ordinary projectile before lifetime")
	w.stats.set_base(&"range", 600)
	shot = fire(true)
	check(is_equal_approx(shot.range_limit,main.projectile_manager.clip_weapon_range(main.player.global_position,Vector2.RIGHT,1800)) and shot.infinite_pierce, "execution range and unlimited pierce coexist")
	shot.global_position = main.player.global_position + Vector2(1100, 0)
	shot._simulate_projectile(0)
	check(shot.active_index < 0, "offscreen boundary retires projectile before range exhaustion")
	w.acquire_form(&"boomerang")
	shot = fire()
	shot._begin_return()
	check(not shot._returning and shot._return_extension == 36, "return requests include a short outward extension")
	shot._simulate_projectile(0.08)
	check(shot._returning, "boomerang returns after outward extension")
	clear_shots()
	w.remove_form(&"boomerang")
	w.acquire_form(&"sprite")
	shot = fire()
	shot._age = 2.01
	shot._simulate_projectile(0)
	check(shot.active_index < 0, "sprite lifetime is at most two seconds")
	for i in 101: fire()
	shot = main.projectile_manager._active[0]
	shot._age = 1.01
	shot._simulate_projectile(0)
	check(shot.active_index < 0, "existing sprite bullets also expire at one second under load")
	clear_shots()
	w.remove_form(&"sprite")
	shot = fire()
	check(not shot._sprite_limited and shot.distance_traveled == 0, "pool reuse resets range and sprite limits")
	clear_shots()
	w.stats.set_base(&"range", 40)
	w.stats.set_base(&"projectile_speed", 7200)
	var near := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	near.configure(ContentDB.get_enemy(&"chaser_triangle"), main.player, ColorType.RED)
	main.world.add_child(near)
	near.global_position = main.player.global_position + Vector2(100,0)
	near.health = 100000
	near.max_health = near.health
	near.set_physics_process(false)
	var distant := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	distant.configure(ContentDB.get_enemy(&"chaser_triangle"), main.player, ColorType.RED)
	main.world.add_child(distant)
	distant.global_position = main.player.global_position + Vector2(300,0)
	distant.health = 100000
	distant.max_health = distant.health
	distant.set_physics_process(false)
	shot = fire(true)
	main.projectile_manager._physics_process(0.1)
	check(near.health < 100000 and distant.health == 100000 and shot.active_index < 0,
		"central swept collision hits before range end without tunneling or beyond-range damage")
	clear_shots()
	w.stats.set_base(&"range",600)
	w.stats.set_base(&"projectile_speed",720)
	var bounds: Rect2 = main.projectile_manager.projectile_visible_bounds()
	var expected_right: float = bounds.end.x-main.player.global_position.x
	check(is_equal_approx(main.projectile_manager.clip_weapon_range(main.player.global_position,Vector2.RIGHT,10000),expected_right),"horizontal range stops exactly at visible screen edge")
	var origin: Vector2 = main.player.global_position
	var diagonal := Vector2(1,1).normalized()
	var diagonal_range: float = main.projectile_manager.clip_weapon_range(origin,diagonal,10000)
	check(bounds.grow(0.01).has_point(origin+diagonal*diagonal_range) and not bounds.has_point(origin+diagonal*(diagonal_range+1)),"diagonal range uses ray intersection with the visible rectangle")
	var outside := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	outside.configure(ContentDB.get_enemy(&"chaser_triangle"),main.player,ColorType.RED)
	main.world.add_child(outside)
	outside.global_position = bounds.end+Vector2(50,50)
	outside.health = 100000
	outside.set_physics_process(false)
	main.projectile_manager.combat.resolve_hit(main.projectile_manager.combat,outside,100,ColorType.BLUE,Vector2.RIGHT,false,&"weapon_sword",true,true,false,&"sword",w)
	check(outside.health==100000,"non-projectile weapon cannot damage an offscreen enemy")
	var camera := get_viewport().get_camera_2d()
	var old_zoom := camera.zoom
	camera.zoom = old_zoom*1.3
	main.projectile_manager._bounds_frame = -1
	var phone_bounds: Rect2 = main.projectile_manager.projectile_visible_bounds()
	check(is_equal_approx(phone_bounds.size.x,bounds.size.x/1.3),"screen boundary adapts to mobile camera zoom")
	camera.zoom = old_zoom
	main.projectile_manager._bounds_frame = -1
	for node in get_tree().get_nodes_in_group(&"enemies"): node.remove_from_group(&"enemies")
	var chain_targets: Array[Enemy] = []
	for i in 2:
		var target := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
		target.configure(ContentDB.get_enemy(&"chaser_triangle"),main.player,ColorType.RED)
		main.world.add_child(target)
		target.global_position = main.player.global_position+Vector2(100+i*30,0)
		target.health = 100000
		target.max_health = 100000
		target.set_physics_process(false)
		chain_targets.append(target)
	main.projectile_manager._collision_frame = -1
	var lightning := WeaponRuntime.new(w.core)
	lightning.acquire_form(&"lightning")
	main.projectile_manager.combat._lightning({"origin":main.player.global_position,"direction":Vector2.RIGHT,
		"damage":100.0,"color":-1,"heavy":false,"weapon":lightning,"budget":main.projectile_manager.combat.new_budget(),"secondary":false})
	check(is_equal_approx(100000-chain_targets[0].health,100) and is_equal_approx(100000-chain_targets[1].health,90),"lightning preserves first hit and reduces later chains by ten percent")
	print("WEAPON RANGE TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
