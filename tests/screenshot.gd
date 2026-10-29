extends Node

## 开发用：运行主场景几秒后保存一张截图，便于无编辑器环境下检查视觉。
## godot --path . res://tests/screenshot.tscn
## 可选模式（参数放在 -- 之后）：
##   selector  截图时显示右键半圆选择标
##   levelup   触发升级，截图升级三选一面板
##   panic     在玩家周围生成敌人并触发受伤反击
##   fx        同屏展示普通命中火花、弱点/暴击伤害数字与敌人死亡消散
##   supercrit 强制超暴击，检查 35px 琉璃彩数字
##   switch    展示右键轮盘展开与玩家换色光环的中间帧
##   blue      展示蓝色角色和切色选择器，检查是否仍是蓝色
##   soul_palette  对比灵魂紫色在不同渲染器中的颜色
##   styles    同屏对比六种爆炸几何语言（星芒/重型/溅射/灵魂/反击/死亡碎裂）
##   hearts    把生命压到 57%，检查以撒式心形容器和残血填充
##   pickups   地面金币/经验与全屏吸取流光同屏展示
##   merchant  商人站在玩家旁边，检查金币身体、手脚、钱符号与蹦跳姿态
##   merchant_arrow  商人刷在屏幕外，检查 HUD 边缘的金色指向箭头
##   shop      走进商人打开的货架面板（基础 4 格）
##   shop_full 升级到 14 格的满货架（检查两行自适应布局）
##   pause     打开手动暂停面板
##   pause_build    带技能/遗物的暂停面板（技能路线页）
##   pause_relics   带遗物的暂停面板（遗物清单页）
##   pause_damage   伤害统计页
##   pause_settings 暂停面板的设置页
##   pause_quit     暂停面板的退出确认页
##   shotgun   四阶散弹一次 6 发，检查固定扇面的分道效果
##   clone     主角与简化分身的造型对比
##   weapon    武器三选一面板
##   console   桌面调试控制台
##   sword     宽剑气推进的中间帧


func _ready() -> void:
	var args := OS.get_cmdline_user_args()

	# 可选：--character falcon / bulwark，检查局内机体外形。
	var character_index := args.find("--character")
	if character_index >= 0 and character_index + 1 < args.size():
		RunState.selected_character_id = StringName(args[character_index + 1])

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	add_child(main)
	if args.has("--no-glow"):
		(main.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false

	var mode := ""
	for candidate in [
		"selector", "levelup", "panic", "fx", "supercrit", "switch", "blue", "soul_palette",
		"styles", "hearts", "pickups", "merchant", "merchant_arrow", "shop",
		"shop_full", "pause", "pause_build", "pause_relics", "pause_damage", "pause_settings",
		"pause_quit", "shotgun", "clone", "weapon", "console", "sword", "boss", "boss_hammer", "boss_impact", "round_blast", "round_motion", "wall",
	]:
		if args.has(candidate):
			mode = candidate
			break

	await get_tree().create_timer(2.4 if mode in ["shop", "shop_full", "hearts", "wall"] else 7.0).timeout
	if args.has("--guardian"):
		Skills.guardian_shields = 2

	if mode == "selector":
		EventBus.color_switch_preview.emit(
			true,
			Vector2(640.0, 360.0),
			1,
			ColorType.next(RunState.color_index, -1),
			ColorType.next(RunState.color_index, 1)
		)
		await get_tree().create_timer(1.0).timeout
	elif mode == "levelup":
		RunState.add_xp(1000)
		await get_tree().create_timer(1.0).timeout
	elif mode == "panic":
		_spawn_panic_enemies(main)
		main.player.set("_invuln", 0.0)
		main.player.take_damage(0.5)
		await get_tree().create_timer(0.24).timeout
	elif mode == "fx":
		await _setup_fx_demo(main)
		await get_tree().create_timer(0.12).timeout
	elif mode == "supercrit":
		await _setup_super_crit_demo(main)
		await get_tree().create_timer(0.12).timeout
	elif mode == "switch":
		await _setup_switch_demo(main)
		await get_tree().create_timer(0.18).timeout
	elif mode == "blue":
		Director.stop()
		main.player.controls_enabled = false
		main.player.set("_invuln", 0.0)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()
		while RunState.color_index != ColorType.BLUE:
			RunState.cycle_color(1)
		await get_tree().create_timer(0.35).timeout
	elif mode == "soul_palette":
		Director.stop()
		main.player.controls_enabled = false
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()
		await get_tree().process_frame
		await get_tree().create_timer(0.8).timeout
		var center: Vector2 = main.player.global_position
		var colors := [Color(1.2, 0.25, 2.6), Color(1.3, 0.4, 2.6),
			Color(1.4, 0.5, 2.6), Color(1.2, 0.35, 3.0)]
		for i in colors.size():
			FX.shockwave(center + Vector2(-300.0 + i * 200.0, 90.0), colors[i],
				92.0, 0.45, EnergyBurst.STYLE_SOUL)
		await get_tree().create_timer(0.12).timeout
	elif mode == "styles":
		await _setup_style_demo(main)
		await get_tree().create_timer(0.12).timeout
	elif mode == "hearts":
		await _setup_hearts_demo(main)
		await get_tree().create_timer(0.3).timeout
	elif mode == "pickups":
		await _setup_pickup_demo(main)
		await get_tree().create_timer(0.22).timeout
	elif mode == "merchant":
		await _setup_merchant_demo(main, 220.0)
		await get_tree().create_timer(0.22).timeout
	elif mode == "merchant_arrow":
		await _setup_merchant_demo(main, 900.0)
		await get_tree().create_timer(0.3).timeout
	elif mode == "shop":
		await _setup_shop_demo(main)
		await get_tree().create_timer(0.55).timeout
	elif mode == "shop_full":
		await _setup_shop_demo(main, true)
		await get_tree().create_timer(0.55).timeout
	elif mode == "pause":
		main._toggle_manual_pause()
		await get_tree().create_timer(0.55).timeout
	elif mode == "pause_build":
		await _setup_pause_demo(main, 0, 0)
	elif mode == "pause_relics":
		await _setup_pause_demo(main, 1, 0)
	elif mode == "pause_damage":
		await _setup_pause_demo(main, 2, 0)
		Skills.damage_totals = {&"base": 28540.0, &"skill:splash_1": 7120.0,
			&"skill:weak_3_burn": 2280.0, &"skill:soul_1": 1440.0}
		Skills.damage_bonus_estimates = {&"skill:heavy_1": 6310.0,
			&"relic:dust_knife": 1580.0}
		main.pause_panel.queue_redraw()
	elif mode == "pause_settings":
		await _setup_pause_demo(main, 0, 1)
	elif mode == "pause_quit":
		await _setup_pause_demo(main, 0, 2)
	elif mode == "shotgun":
		_setup_shotgun_demo(main)
		await get_tree().create_timer(0.30).timeout
	elif mode == "weapon":
		Director.stop()
		main._queue_weapon_reward("Boss 宝箱")
		await get_tree().create_timer(0.12).timeout
	elif mode == "console":
		var toggle := InputEventKey.new()
		toggle.pressed = true
		toggle.physical_keycode = KEY_QUOTELEFT
		main.debug_console._unhandled_key_input(toggle)
		main.debug_console._submit("help")
		await get_tree().create_timer(0.12).timeout
	elif mode == "sword":
		Director.stop()
		main.player.controls_enabled = false
		main.player.set("_invuln", 999.0)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()
		await get_tree().process_frame
		main.player.weapon.acquire_form(&"sword")
		main.player.weapon.select_primary(&"sword")
		main.projectile_manager.combat.fire_weapon(main.player.global_position,
			Vector2.RIGHT, main.player.weapon.stats, main.player.color_index, false, main.player.weapon)
		await get_tree().create_timer(0.12).timeout
	elif mode == "clone":
		Director.stop()
		main.player.controls_enabled = false
		main.player.set("_invuln", 999.0)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()
		Skills.unlock(&"clone_1", true)
		var clone := load("res://scripts/skills/MirrorClone.gd").new() as MirrorClone
		main.world.add_child(clone)
		clone.setup(main.player, main.player.global_position + Vector2(56.0, 0.0))
		await get_tree().create_timer(0.20).timeout
	elif mode in ["boss", "boss_hammer", "boss_impact"]:
		await _setup_boss_demo(main, mode)
		await get_tree().create_timer(0.20).timeout
	elif mode == "round_blast":
		Director.stop()
		main.player.controls_enabled = false
		main.player.set("_invuln", 999.0)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()
		for color in ColorType.COUNT:
			var blast: Node2D = load("res://scripts/fx/RoundExplosion.gd").new()
			blast.set("tint", RunState.color_of(color))
			main.world.add_child(blast)
			blast.global_position = main.player.global_position + Vector2((color - 1) * 110.0, -80.0)
		await get_tree().create_timer(0.17).timeout
	elif mode == "round_motion":
		Director.stop()
		main.player.controls_enabled = false
		main.player.set("_invuln", 999.0)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()
		await get_tree().process_frame
		for color in ColorType.COUNT:
			var round_enemy := Director.ENEMY_SCENE.instantiate() as Enemy
			round_enemy.configure(ContentDB.get_enemy(&"chaser_round"), main.player, color)
			main.world.add_child(round_enemy)
			round_enemy.global_position = main.player.global_position + Vector2(225.0 + color * 45.0, -90.0 + color * 90.0)
		await get_tree().create_timer(0.5).timeout
	elif mode == "wall":
		Director.stop()
		main.player.controls_enabled = false
		main.player.global_position = Vector2(RunState.arena_rect.end.x - 85.0, 0.0)
		main.camera.global_position = main.player.global_position
		await get_tree().create_timer(0.35).timeout
	else:
		await get_tree().create_timer(1.0).timeout
	var heart_count_index := args.find("--heart-count")
	if heart_count_index >= 0 and heart_count_index + 1 < args.size():
		main.player.max_health = float(maxi(1, int(args[heart_count_index + 1])))
		main.player.health = main.player.max_health
		EventBus.player_health_changed.emit(main.player.health, main.player.max_health)
	var shield_count_index := args.find("--shield-count")
	if shield_count_index >= 0 and shield_count_index + 1 < args.size():
		Skills.guardian_shields = maxi(0, int(args[shield_count_index + 1]))
	if heart_count_index >= 0 or shield_count_index >= 0:
		await get_tree().create_timer(0.1).timeout

	await RenderingServer.frame_post_draw

	var path := "res://tests/screenshot.png"
	if mode == "selector":
		path = "res://tests/screenshot_selector.png"
	elif mode == "levelup":
		path = "res://tests/screenshot_levelup.png"
	elif mode == "panic":
		path = "res://tests/screenshot_panic.png"
	elif mode == "fx":
		path = "res://tests/screenshot_fx.png"
	elif mode == "supercrit":
		path = "res://tests/screenshot_supercrit.png"
	elif mode == "switch":
		path = "res://tests/screenshot_switch.png"
	elif mode == "blue":
		path = "res://tests/screenshot_blue.png"
	elif mode == "soul_palette":
		path = "res://tests/screenshot_soul_palette.png"
	elif mode == "styles":
		path = "res://tests/screenshot_styles.png"
	elif mode == "hearts":
		path = "res://tests/screenshot_hearts.png"
	elif mode == "pickups":
		path = "res://tests/screenshot_pickups.png"
	elif mode == "merchant":
		path = "res://tests/screenshot_merchant.png"
	elif mode == "merchant_arrow":
		path = "res://tests/screenshot_merchant_arrow.png"
	elif mode == "shop":
		path = "res://tests/screenshot_shop.png"
	elif mode == "shop_full":
		path = "res://tests/screenshot_shop_full.png"
	elif mode == "pause":
		path = "res://tests/screenshot_pause.png"
	elif mode == "pause_build":
		path = "res://tests/screenshot_pause_build.png"
	elif mode == "pause_relics":
		path = "res://tests/screenshot_pause_relics.png"
	elif mode == "pause_damage":
		path = "res://tests/screenshot_pause_damage.png"
	elif mode == "pause_settings":
		path = "res://tests/screenshot_pause_settings.png"
	elif mode == "pause_quit":
		path = "res://tests/screenshot_pause_quit.png"
	elif mode == "shotgun":
		path = "res://tests/screenshot_shotgun.png"
	elif mode == "weapon":
		path = "res://tests/screenshot_weapon.png"
	elif mode == "console":
		path = "res://tests/screenshot_console.png"
	elif mode == "sword":
		path = "res://tests/screenshot_sword.png"
	elif mode == "clone":
		path = "res://tests/screenshot_clone.png"
	elif mode == "boss":
		path = "res://tests/screenshot_boss.png"
	elif mode == "boss_hammer":
		path = "res://tests/screenshot_boss_hammer.png"
	elif mode == "boss_impact":
		path = "res://tests/screenshot_boss_impact.png"
	elif mode == "round_blast":
		path = "res://tests/screenshot_round_blast.png"
	elif mode == "round_motion":
		path = "res://tests/screenshot_round_motion.png"
	elif mode == "wall":
		path = "res://tests/screenshot_wall.png"

	var shot_index := args.find("--shot")
	if shot_index >= 0 and shot_index + 1 < args.size():
		path = args[shot_index + 1]

	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("SCREENSHOT saved error=%s size=%s path=%s paused=%s" % [
		error, image.get_size(), path, get_tree().paused
	])
	get_tree().quit()


func _setup_boss_demo(main: Node, variant: String = "boss") -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	RunState.elapsed = 240.0
	var boss := Director.spawn_boss_now(main.player.global_position + Vector2(205.0, 0.0))
	if boss == null:
		return
	boss.set_physics_process(false)
	for i in 4:
		var square := Director.ENEMY_SCENE.instantiate() as Enemy
		square.configure(ContentDB.get_enemy(&"chaser_square"), main.player, boss.color_index)
		main.world.add_child(square)
		square.global_position = main.player.global_position + Vector2(185.0 + i * 42.0, -145.0)
		square.empower(boss.color_index)
		square.set_physics_process(false)
	if variant == "boss_hammer":
		boss._begin_action(&"hammer")
		boss._windup = boss._windup_total * 0.18
	elif variant == "boss_impact":
		boss._begin_action(&"hammer")
		boss._resolve_action()
	else:
		boss._begin_action(&"summon")
		boss._windup = boss._windup_total * 0.35
	boss.queue_redraw()


## 固定站位展示三套反馈：普通命中、弱点/暴击数字、死亡消散。
func _setup_fx_demo(main: Node) -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	# 等上一场战斗的浮字和碎片自然消失，避免混进截图。
	await get_tree().create_timer(1.0).timeout

	var center: Vector2 = main.player.global_position
	var normal := _spawn_demo_enemy(main, center + Vector2(130.0, -90.0), 9999.0)
	var weakness := _spawn_demo_enemy(main, center + Vector2(150.0, 0.0), 9999.0)
	var crit := _spawn_demo_enemy(main, center + Vector2(130.0, 100.0), 9999.0)
	var dying := _spawn_demo_enemy(main, center + Vector2(-150.0, 0.0), 40.0)

	var normal_hit := DamageContext.new()
	normal_hit.amount = 37.0
	normal_hit.color_index = RunState.color_index
	normal_hit.relation = &"neutral"
	normal.take_damage(normal_hit)
	FX.hit_spark(normal.global_position, RunState.color_of(RunState.color_index), false)

	var weakness_hit := DamageContext.new()
	weakness_hit.amount = 54.0
	weakness_hit.color_index = RunState.color_index
	weakness_hit.relation = &"advantage"
	weakness.take_damage(weakness_hit)
	FX.hit_spark(weakness.global_position, RunState.color_of(RunState.color_index), true)

	var crit_hit := DamageContext.new()
	crit_hit.amount = 86.0
	crit_hit.color_index = RunState.color_index
	crit_hit.relation = &"advantage"
	crit_hit.is_crit = true
	crit.take_damage(crit_hit)
	FX.hit_spark(crit.global_position, Color(2.8, 2.8, 2.8, 1.0), true)

	var kill_hit := DamageContext.new()
	kill_hit.amount = 999.0
	kill_hit.color_index = RunState.color_index
	dying.take_damage(kill_hit)


## 走真实的 build_hit_context 路径，只把超暴击概率强制为 100%。
func _setup_super_crit_demo(main: Node) -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout

	Skills.debug_force_super_crit = true
	var center: Vector2 = main.player.global_position
	var targets: Array[Enemy] = [
		_spawn_demo_enemy(main, center + Vector2(0.0, -130.0), 99999.0),
		_spawn_demo_enemy(main, center + Vector2(-160.0, 70.0), 99999.0),
		_spawn_demo_enemy(main, center + Vector2(160.0, 70.0), 99999.0),
	]
	var base_damages: Array[float] = [80.0, 300.0, 800.0]
	for i in targets.size():
		var context := Skills.build_hit_context(
			main.player, targets[i], base_damages[i], RunState.color_index
		)
		targets[i].take_damage(context)
		FX.hit_spark(targets[i].global_position, Color(2.8, 2.8, 2.8, 1.0), true)


## 模拟长按右键确认换色：轮盘处于展开/高亮中，玩家同时播放换色光环。
func _setup_switch_demo(main: Node) -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout

	EventBus.color_switch_preview.emit(
		true,
		Vector2(900.0, 360.0),
		1,
		ColorType.next(RunState.color_index, -1),
		ColorType.next(RunState.color_index, 1)
	)
	RunState.cycle_color(1)


## 并排展示六种爆炸几何语言，用于检查“所有效果都是同一个圈”的问题。
func _setup_style_demo(main: Node) -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout

	var center: Vector2 = main.player.global_position
	FX.hit_burst(center + Vector2(-250.0, -120.0), Color(0.5, 1.6, 2.2, 1.0), 38.0, 0.4, EnergyBurst.STYLE_STAR)
	FX.hit_burst(center + Vector2(0.0, -120.0), Color(1.9, 1.3, 0.5, 1.0), 48.0, 0.4, EnergyBurst.STYLE_HEAVY)
	FX.shockwave(center + Vector2(250.0, -120.0), Color(2.2, 0.5, 0.6, 1.0), 82.0, 0.4, EnergyBurst.STYLE_SPLASH)
	FX.shockwave(center + Vector2(-250.0, 110.0), Color(1.4, 1.1, 2.6, 1.0), 92.0, 0.45, EnergyBurst.STYLE_SOUL)
	FX.shockwave(center + Vector2(0.0, 110.0), Color(2.0, 0.9, 0.4, 1.0), 108.0, 0.55, EnergyBurst.STYLE_PANIC)
	FX.hit_burst(center + Vector2(250.0, 110.0), Color(0.7, 2.0, 1.1, 1.0), 42.0, 0.4, EnergyBurst.STYLE_SHATTER)


## 生命压到半颗心，便于检查第三颗心的半心填充。
func _setup_hearts_demo(main: Node) -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

	var player: Player = main.player
	player.health = Player.snap_to_half(player.max_health * 0.45)
	EventBus.player_health_changed.emit(player.health, player.max_health)


## 左侧经验、右侧金币；地面上留一圈待拾取掉落，再用全屏吸取生成一批
## 已经进入收集状态的掉落，截到流光的中间帧。
func _setup_pickup_demo(main: Node) -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	Pickups.clear()

	var center: Vector2 = main.player.global_position
	# 地面上等待拾取的掉落：右侧金币，左侧经验，距离在磁吸半径之外。
	for i in 5:
		var row := float(i) - 2.0
		Pickups.spawn_gold(center + Vector2(250.0 + absf(row) * 18.0, row * 34.0), 1 + i)
		Pickups.spawn_xp(center + Vector2(-250.0 - absf(row) * 18.0, row * 34.0), 2)

	# 解锁全屏吸取后再生成，掉落直接进入 collecting，画出从边缘汇向玩家的流光。
	Skills.unlock(&"gold_3", true)
	Skills.unlock(&"xp_4", true)
	for i in 7:
		var angle := TAU * float(i) / 7.0
		Pickups.spawn_gold(center + Vector2(cos(angle), sin(angle)) * 430.0, 3)
		Pickups.spawn_xp(center + Vector2(cos(angle + 0.35), sin(angle + 0.35)) * 470.0, 4)


## 商人静态展示：offset_x 较大时商人落在屏幕外，用来检查 HUD 箭头。
func _setup_merchant_demo(main: Node, offset_x: float) -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout

	Director.spawn_merchant_now(
		main.player.global_position + Vector2(offset_x, -20.0)
	)


func _setup_shop_demo(main: Node, full_shelf: bool = false) -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout

	RunState.gold = 120
	Director.spawn_merchant_now(main.player.global_position + Vector2(42.0, 0.0))
	await get_tree().create_timer(0.25).timeout
	if full_shelf:
		Skills.shop_level = Skills.SHOP_MAX_SLOTS - Skills.SHOP_BASE_SLOTS
		var panel := main.get_node("HUD/ShopPanel") as ShopPanel
		panel._restock([])
		panel.queue_redraw()


## 四阶散弹：一次 6 发，等待弹丸飞出后检查固定扇面的分道效果。
func _setup_shotgun_demo(main: Node) -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	var demo_nodes: Array[StringName] = [&"shotgun_1"]
	if not OS.get_cmdline_user_args().has("--dual"):
		demo_nodes.append(&"shotgun_3")
		demo_nodes.append(&"shotgun_4")
	for id in demo_nodes:
		Skills.unlock(id, true)
	var manager: ProjectileManager = main.projectile_manager
	for projectile in manager._active.duplicate():
		manager.release(projectile)
	main.player.set("_heavy_timer", 10.0)
	main.player.set("_heavy_primed", false)
	main.player._fire(Vector2.RIGHT)


## 暂停面板的构筑展示：塞入一套技能和遗物，再按 tab / screen 打开对应子页。
func _setup_pause_demo(main: Node, tab: int, screen: int) -> void:
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout

	RunState.gold = 487
	RunState.level = 14
	RunState.elapsed = 168.0
	for id in [
		&"fire_1", &"fire_2", &"fire_3", &"fire_4",
		&"heavy_1", &"heavy_2", &"heavy_3",
		&"energy_1", &"energy_2",
		&"speed_1", &"speed_2", &"speed_3",
		&"xp_1", &"xp_2", &"gold_1", &"gold_2",
		&"soul_1", &"soul_2", &"splash_1", &"splash_2",
		&"weakness_1", &"weakness_2", &"weakness_3",
		&"crit_1", &"crit_2", &"crit_3",
		&"shotgun_1", &"shotgun_2", &"luck_1", &"luck_2",
		&"fragile_1", &"sprite_1", &"clone_1", &"circle_1", &"giant_1",
		&"path_angel_1", &"path_angel_2", &"path_angel_3",
	]:
		Skills.unlock(id, true)
	for relic_id in [
		&"dust_knife", &"dust_knife", &"dust_knife",
		&"dust_paper_star", &"dust_paper_star",
		&"dust_iron_glove", &"dust_cloth_glove", &"dust_running_shoes",
		&"dust_blindfold", &"dust_blunt_blade", &"dust_lottery", &"dust_magnet",
		&"rare_four_leaf", &"rare_four_leaf", &"rare_three_leaf",
		&"rare_bullet_shell", &"rare_bullet_shell",
		&"rare_adrenaline", &"rare_bond", &"rare_reroll",
		&"rare_impact_releaser", &"rare_prism_lens", &"rare_battery",
		&"rare_cracked_armor", &"rare_fate_dice", &"rare_feast",
		&"rare_golden_apple", &"rare_gold_nugget", &"rare_dumbbell",
		&"rare_flint", &"rare_poison_arrow", &"rare_frost_arrow", &"rare_burning_arrow",
		&"rare_dictionary", &"rare_silver_coin",
		&"epic_lucky_coin", &"legendary_rainbow_clover",
		&"angel_guardian", &"angel_halo", &"demon_pointed_vessel", &"demon_soul_blade",
	]:
		Skills.grant_relic(relic_id)

	main._toggle_manual_pause()
	await get_tree().create_timer(0.4).timeout
	var panel := main.pause_panel as PausePanel
	panel._tab = tab
	panel._screen = screen
	panel._focus_skill_id = &"fire_4"
	panel._focus_relic_id = &"legendary_rainbow_clover"
	panel.queue_redraw()
	await get_tree().create_timer(0.35).timeout


func _spawn_demo_enemy(main: Node, position: Vector2, health: float) -> Enemy:
	var enemy_scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var enemy := enemy_scene.instantiate() as Enemy
	enemy.configure(ContentDB.get_enemy(&"chaser_triangle"), main.player)
	main.world.add_child(enemy)
	enemy.global_position = position
	enemy.max_health = health
	enemy.health = health
	# 固定站位便于截图，不追玩家。
	enemy.set_physics_process(false)
	return enemy


func _spawn_panic_enemies(main: Node) -> void:
	var enemy_scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var enemy_type := ContentDB.get_enemy(&"chaser_triangle")
	var center: Vector2 = main.player.global_position

	for i in 10:
		var enemy := enemy_scene.instantiate()
		enemy.configure(enemy_type, main.player)
		main.world.add_child(enemy)
		var angle := TAU * float(i) / 10.0
		enemy.global_position = center + Vector2(cos(angle), sin(angle)) * randf_range(55.0, 165.0)
