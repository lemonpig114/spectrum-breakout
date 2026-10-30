extends Node

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		print("FAIL ", message)

func _ready() -> void:
	var boundaries := [0.0, 30.0, 60.0, 120.0, 180.0, 240.0, 270.0, 300.0, 330.0, 360.0, 420.0, 480.0, 540.0]
	var rates := [3.0, 4.0, 6.0, 13.0, 6.0, 8.0, 12.0, 6.0, 8.0, 10.0, 6.0, 10.0, 12.0]
	for i in boundaries.size():
		check(Director.spawn_phase(boundaries[i]) == i, "phase boundary %d" % i)
		check(is_equal_approx(Director.spawn_rate(boundaries[i]), rates[i]), "rate boundary %d" % i)
	check(Director.spawn_phase(29.99) == 0 and Director.spawn_phase(299.99) == 6, "phase end points")
	check(Director.enemy_limit(119.99) == 55 and Director.enemy_limit(120) == 100 and Director.enemy_limit(180) == 70 and Director.enemy_limit(240) == 80, "phase caps")
	check(Director._spawn_batch_size(3) == 13 and is_equal_approx(Director._spawn_interval(3), 1.0), "thirteen simultaneous surround enemies per second")
	check(Director.enemy_damage_multiplier(239.99) == 1.0 and Director.enemy_damage_multiplier(240) == 2.0, "damage step")
	Director._enemy_types = ContentDB.get_enemies()
	check(Director._phase_type(0, 0).id == &"chaser_triangle", "opening triangles")
	check(Director._phase_type(3, 0).id == &"chaser_triangle", "high pressure triangles")
	check(Director._phase_type(4, 0).id == &"chaser_square", "boss phase squares")
	check(Director._phase_type(5, 0).id == &"ranged_plane" and Director._phase_type(5, 3).id == &"chaser_square", "plane-square phase")
	for index in 8:
		check(Director._phase_type(5, index).id == (&"ranged_plane" if index < 3 else &"chaser_square"), "3:5 plane-square mix")
	for index in 12:
		var wanted: StringName = &"ranged_plane" if index < 2 else (&"chaser_square" if index < 6 else (&"chaser_triangle" if index < 10 else &"chaser_round"))
		check(Director._phase_type(6, index).id == wanted, "late four-type mix")
	check(Director._phase_type(7, 0).id == &"chaser_hex" and Director._phase_type(7, 1).id == &"chaser_hex", "five-to-six-minute solo hex phase")
	for index in 8:
		check(Director._phase_type(8, index).id == (&"chaser_hex" if index < 6 else &"chaser_round"), "330-second hex/exploder 6:2 cycle")
	for index in 10:
		check(Director._phase_type(9, index).id == (&"chaser_hex" if index < 8 else &"ranged_plane"), "360-second hex/ranged 8:2 cycle")
		check(Director._phase_type(10, index).id == &"chaser_hex", "boss phase only hex")
		check(Director._phase_type(11, index).id == (&"chaser_hex" if index < 6 else &"ranged_plane"), "480-second hex/ranged 6:4 cycle")
	for i in 15:
		var seconds := 540.0 + i * 15.0
		var wanted: StringName = [&"chaser_triangle", &"chaser_square", &"chaser_hex", &"chaser_round", &"ranged_plane"][i % 5]
		check(Director._phase_type(Director.spawn_phase(seconds), 0).id == wanted, "endless cycles through five single-type waves")
		check(Director.spawn_rate(seconds) == [12.0, 10.0, 8.0, 10.0, 8.0][i % 5], "endless rate per wave")
		check(Director.health_multiplier(seconds) == 35.0 + floorf((seconds - 540.0) / 100.0), "endless hp grows every hundred seconds")
	check(Director.health_multiplier(539.99) == 20.0 and Director.health_multiplier(540.0) == 35.0 and Director.health_multiplier(639.99) == 35.0 and Director.health_multiplier(640.0) == 36.0, "endless hp exact boundaries")
	check(Director.health_multiplier(329.99) == 6.0 and Director.health_multiplier(330) == 7.0
		and Director.health_multiplier(360) == 10.0 and Director.health_multiplier(420) == 15.0, "new late-game hp steps")
	var triangle := ContentDB.get_enemy(&"chaser_triangle")
	var square := ContentDB.get_enemy(&"chaser_square")
	check(triangle.max_health * Director.health_multiplier(0) == 20.0 and Director.health_multiplier(15) == 1.0, "opening 0.8 hp")
	check(is_equal_approx(Director.health_multiplier(59.99), 1.0) and is_equal_approx(Director.health_multiplier(60), 1.5), "minute-one hp step")
	check(is_equal_approx(Director.health_multiplier(120), 2.0) and is_equal_approx(Director.health_multiplier(180), 2.5) and is_equal_approx(Director.health_multiplier(240), 3.5) and is_equal_approx(Director.health_multiplier(270), 5.0) and is_equal_approx(Director.health_multiplier(300), 6.0), "later hp steps")
	check(is_equal_approx(13.0 * triangle.max_health * Director.health_multiplier(120), 650.0), "high-pressure theoretical hp per second")
	check(is_equal_approx(6.0 * square.max_health * Director.health_multiplier(180), 900.0), "boss phase theoretical hp per second")
	var world := Node2D.new()
	add_child(world)
	var target := Node2D.new()
	world.add_child(target)
	Director.world = world
	Director.player = target
	Director._phase_spawn_index = 0
	RunState.elapsed = 60.0
	for i in 10:
		Director._spawn_phase_enemy(2)
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() == 10, "ten phase spawns")
	if enemies.size() == 10:
		for i in 10:
			check(enemies[i].type_data.id == (&"chaser_square" if i % 5 == 4 else &"chaser_triangle"), "opening mix remains 4:1")
	RunState.begin_run()
	RunState.elapsed = 120.0
	RunState.start()
	Director.start()
	Director._spawn_timer = 0.0
	Director._phase_index = 2
	Director._process(0.0)
	enemies = get_tree().get_nodes_in_group("enemies")
	check(enemies.size() == 23, "high-pressure tick creates thirteen enemies together")
	if enemies.size() == 23:
		var colors := {}
		var octants := {}
		var nearest := INF
		var spread := 0.0
		for i in range(10, 23):
			var enemy: Enemy = enemies[i]
			colors[enemy.color_index] = true
			nearest = minf(nearest, enemy.position.distance_to(target.position))
			var octant := int(fposmod((enemy.position - target.position).angle(), TAU) / (TAU / 8.0)) % 8
			octants[octant] = true
			for j in range(10, 23):
				spread = maxf(spread, enemy.position.distance_to(enemies[j].position))
		check(colors.size() >= 2, "surround spawns are not one color")
		check(nearest >= 380.0, "surround spawns stay outside the player")
		check(spread >= 500.0, "surround spawns ring the player")
		check(octants.size() >= 6, "surround covers most directions")
		check(enemies[10].type_data.id == &"chaser_triangle", "surround keeps triangles")
	var announcements := [0]
	EventBus.endless_mode_entered.connect(func(): announcements[0] += 1)
	Director._boss_spawned = true
	Director._hex_boss_spawned = true
	Director._endless_announced = false
	Director._spawn_timer = 1.0
	RunState.elapsed = 540.0
	Director._process(0.0)
	Director._process(0.0)
	check(announcements[0] == 1 and Director._endless_announced, "endless announcement fires only once")
	Director.stop()
	RunState.end_run()
	world.queue_free()
	RunState.elapsed = 0.0
	await get_tree().process_frame
	print("SPAWN PHASE TEST ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
