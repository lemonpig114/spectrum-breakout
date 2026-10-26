extends Node

var failures := 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.4).timeout
	Director.stop()
	var player: Player = main.player
	player.controls_enabled = false
	var arena := RunState.arena_rect
	_check(arena.size == Vector2(4800.0, 3600.0), "arena area is four times the old size")
	var soft_edge := arena.end.x - player.body_radius - 6.0
	player.global_position = Vector2(soft_edge - 20.0, 0.0)
	player.velocity = Vector2(100.0, 0.0)
	player._apply_soft_wall_resistance()
	_check(player.velocity.x > 0.0 and player.velocity.x < 40.0,
		"approaching the wall slows outward movement")
	main.grid._process(0.1)
	var material: ShaderMaterial = main.grid.material
	_check(float(material.get_shader_parameter("wall_visibility")) > 0.5,
		"wall becomes visible near the edge")
	player.global_position = Vector2.ZERO
	main.grid._process(0.1)
	_check(is_zero_approx(float(material.get_shader_parameter("wall_visibility"))),
		"wall fades away in the middle")

	var enemy := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	enemy.configure(ContentDB.get_enemy(&"chaser_triangle"), player, ColorType.RED)
	main.world.add_child(enemy)
	enemy.global_position = Vector2(arena.end.x + 10.0, 0.0)
	enemy.velocity = Vector2(100.0, 0.0)
	enemy._move_manually(0.1)
	_check(enemy.global_position.x > arena.end.x + 10.0,
		"enemy can move through the soft wall")
	enemy.queue_free()

	print("ARENA WALL TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", message)
