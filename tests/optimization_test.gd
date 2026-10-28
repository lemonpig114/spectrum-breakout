extends Node

var failures := 0


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.8).timeout
	Director.stop()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var player: Player = main.player
	var enemy_scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var enemy_type := ContentDB.get_enemy(&"chaser_triangle")
	var offscreen := enemy_scene.instantiate() as Enemy
	offscreen.configure(enemy_type, player)
	main.world.add_child(offscreen)
	offscreen.global_position = player.global_position + Vector2(800.0, 0.0)
	failures += _check(player._find_nearest_enemy() == null, "offscreen enemy is not targeted")
	var near := enemy_scene.instantiate() as Enemy
	near.configure(enemy_type, player)
	main.world.add_child(near)
	near.global_position = player.global_position + Vector2(150.0, 0.0)
	failures += _check(player._find_nearest_enemy() == near, "visible nearby enemy is targeted")
	near.global_position = player.global_position + Vector2(640.0, 0.0)
	failures += _check(player._find_nearest_enemy() == null, "auto aim obeys range cap")
	near.global_position = player.global_position + Vector2(150.0, 0.0)
	near._poison_dps = 4.0
	var before := near.health
	EventBus.dot_tick.emit((near._dot_bucket + 1) % 4)
	failures += _check(is_equal_approx(near.health, before), "other DoT bucket leaves enemy untouched")
	EventBus.dot_tick.emit(near._dot_bucket)
	failures += _check(near.health < before, "global DoT bucket applies damage")
	print("OPTIMIZATION TEST %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("PASS ", label)
		return 0
	push_error("FAIL " + label)
	return 1
