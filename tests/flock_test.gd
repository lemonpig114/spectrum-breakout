extends Node
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
var enemies: Array[Enemy] = []
var failures := 0

func _ready() -> void:
	var count := 200 if OS.get_cmdline_user_args().has("--200") else 70
	var target := Node2D.new()
	target.position = Vector2(960, 540)
	add_child(target)
	var kind := ContentDB.get_enemies()[0]
	for i in count:
		var enemy := ENEMY_SCENE.instantiate() as Enemy
		enemy.configure(kind, target)
		enemy.global_position = target.position + Vector2.from_angle(float(i) * TAU / float(count)) * (68.0 + float(i % 3))
		add_child(enemy)
		enemies.append(enemy)
	var before := _overlaps()
	for frame in 360:
		await get_tree().physics_frame
	var after := _overlaps()
	var min_distance := INF
	for i in enemies.size():
		min_distance = minf(min_distance, enemies[i].global_position.distance_to(target.position))
	print("FLOCK before=%d after=%d nearest_player=%.1f grid_cells=%d" % [before, after, min_distance, EnemyFlock._cells.size()])
	check(before > 250, "crowd begins overlapped")
	check(after < before / 2, "crowd separates without physics collisions")
	check(min_distance < 50 and min_distance >= 25, "crowd still pursues without crossing player")
	check(EnemyFlock._cells.size() < count, "spatial hash groups neighbors")
	_check_freed_neighbor(target, kind)
	if OS.get_cmdline_user_args().has("--shot"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/flock_200.png" if count == 200 else "res://tests/flock_crowd.png")
	print("FLOCK TEST ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

## 回归：敌人可能在两次网格刷新之间被 queue_free（Boss 召唤物裁剪）。
## 缓存里留下已释放实例时，分离扫描必须跳过，不能对它做 `as Enemy`。
func _check_freed_neighbor(target: Node2D, kind: EnemyTypeResource) -> void:
	var doomed := ENEMY_SCENE.instantiate() as Enemy
	doomed.configure(kind, target)
	add_child(doomed)
	doomed.global_position = enemies[0].global_position + Vector2(12.0, 0.0)
	EnemyFlock._rebuild(get_tree())
	doomed.remove_from_group("enemies")
	doomed.free()
	EnemyFlock._frame = Engine.get_physics_frames()
	EnemyFlock._steerings.clear()
	var steering := EnemyFlock.separation(enemies[0])
	check(steering.length() < 100.0, "freed cached neighbor is skipped without cast error")


func _overlaps() -> int:
	var hits := 0
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			if enemies[i].global_position.distance_to(enemies[j].global_position) < enemies[i].radius + enemies[j].radius:
				hits += 1
	return hits

func check(ok: bool, message: String) -> void:
	if not ok:
		print("FAIL ", message)
		failures += 1
