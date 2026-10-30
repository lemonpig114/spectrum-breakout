extends Node

var failures := 0


func _ready() -> void:
	Director.stop()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	var batch := EnemyBatchRenderer.new()
	world.add_child(batch)
	var overlays := EnemyOverlayRenderer.new()
	world.add_child(overlays)
	var scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var enemy := scene.instantiate() as Enemy
	enemy.configure(ContentDB.get_enemy(&"chaser_square"), null, ColorType.RED)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.health *= 0.5
	enemy._refresh_healthbar()
	enemy._healthbar.set_statuses(true, false, false)
	# Camera and live enemy move together: the sprite must remain in the viewport,
	# even when its world position is outside the first frame's cached draw bounds.
	for offset in [Vector2.ZERO, Vector2(900, 600), Vector2(-900, -600), Vector2(1600, 0), Vector2.ZERO]:
		enemy.position = offset + Vector2(128, 128)
		viewport.canvas_transform = Transform2D(0.0, -offset)
		await _render()
		var image := viewport.get_texture().get_image()
		_check(_lit_pixels(image, Rect2i(104, 104, 48, 48)) > 12,
			"live enemy remains drawn at camera offset %s" % offset)
		_check(_lit_pixels(image, Rect2i(96, 105, 64, 6)) > 5,
			"health bar remains drawn at camera offset %s" % offset)
		_check(_lit_pixels(image, Rect2i(118, 148, 20, 20)) > 5,
			"status remains drawn at camera offset %s" % offset)
	# Returning from an empty batch must not reuse its earlier culling bounds.
	enemy.hide()
	await _render()
	_check(_lit_pixels(viewport.get_texture().get_image(), Rect2i(0, 0, 256, 256)) == 0,
		"hidden enemy clears all batches")
	enemy.show()
	enemy.position = Vector2(2800, 1400) + Vector2(128, 128)
	viewport.canvas_transform = Transform2D(0.0, Vector2(-2800, -1400))
	await _render()
	_check(_lit_pixels(viewport.get_texture().get_image(), Rect2i(104, 104, 48, 48)) > 12,
		"empty batch repopulates outside its previous bounds")
	enemy.empower(ColorType.BLUE)
	await _render()
	_check(not enemy.batch_rendered and _lit_pixels(viewport.get_texture().get_image(), Rect2i(104, 104, 48, 48)) > 12,
		"boss empowerment switches to custom drawing without losing body")
	enemy.hide()
	var manager := ProjectileManager.new()
	world.add_child(manager)
	for i in 3:
		var bullet := manager._create_pooled()
		bullet.batch_rendered = true
		bullet.batch_star = i == 1
		bullet.batch_sprite = i == 2
		bullet.color_index = i
		bullet.show()
		bullet.active_index = manager._active.size()
		manager._active.append(bullet)
	for offset in [Vector2.ZERO, Vector2(1800, 1200), Vector2(-1800, -1200), Vector2.ZERO]:
		viewport.canvas_transform = Transform2D(0.0, -offset)
		for i in 3:
			manager._active[i].position = offset + Vector2(64 + 64 * i, 128)
		await _render()
		var image := viewport.get_texture().get_image()
		for i in 3:
			_check(_lit_pixels(image, Rect2i(54 + 64 * i, 118, 20, 20)) > 5,
				"projectile batch %d remains drawn at camera offset %s" % [i, offset])
	print("BATCH VISIBILITY TEST %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _render() -> void:
	for i in 4:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func _lit_pixels(image: Image, rect: Rect2i) -> int:
	var count := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.12:
				count += 1
	return count


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)
