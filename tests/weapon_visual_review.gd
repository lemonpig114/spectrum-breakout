extends Node

## 真实渲染窗口下截取单把武器的视觉草稿，供美术验收。
const FORMS := [&"cannon", &"sprite", &"wave", &"scythe"]


func _ready() -> void:
	var form: StringName = &"cannon"
	var shot := "res://tests/weapon_visual_review.png"
	var impact := false
	var grown := false
	var fusion: StringName = &""
	var delay := -1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weapon="):
			form = StringName(arg.get_slice("=", 1))
		elif arg.begins_with("--shot="):
			shot = arg.get_slice("=", 1)
		elif arg == "--impact":
			impact = true
		elif arg == "--grown":
			grown = true
		elif arg.begins_with("--fuse="):
			fusion = StringName(arg.get_slice("=", 1))
		elif arg.begins_with("--delay="):
			delay = float(arg.get_slice("=", 1))
	if not FORMS.has(form):
		push_error("Unknown weapon visual: %s" % form)
		get_tree().quit(1)
		return
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(2.2).timeout
	Director.stop()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await get_tree().process_frame
	var player: Player = main.player
	main.camera.zoom = Vector2(2.4, 2.4)
	player.controls_enabled = false
	player.set_physics_process(false)
	player.weapon.acquire_form(form)
	if fusion != &"":
		player.weapon.acquire_form(fusion)
	player.weapon.select_primary(form)
	var direction := Vector2.RIGHT
	if form == &"scythe" and fusion != &"sword":
		direction = Vector2.UP
	if fusion == &"sword":
		main.camera.zoom = Vector2(1.5, 1.5)
	main.projectile_manager.combat.fire_weapon(player.global_position, direction,
		player.weapon.stats, player.color_index, false, player.weapon)
	if impact and form == &"cannon":
		var cannon: Projectile = main.projectile_manager._active.back()
		main.projectile_manager.combat.queue_cannon_explosion(cannon,
			player.global_position + Vector2(105.0, 0.0))
		main.projectile_manager.release(cannon)
	if delay >= 0.0:
		await get_tree().create_timer(delay).timeout
	elif form == &"wave":
		await get_tree().create_timer(0.12).timeout
	elif form == &"sprite":
		await get_tree().create_timer(0.38).timeout
	else:
		await get_tree().create_timer(0.10).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(shot)
	print("WEAPON VISUAL %s %s" % [form, "PASS" if err == OK else "FAIL"])
	get_tree().quit(0 if err == OK else 1)
