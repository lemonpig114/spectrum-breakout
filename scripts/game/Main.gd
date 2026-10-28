extends Node2D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_BATCH_RENDERER := preload("res://scripts/enemies/EnemyBatchRenderer.gd")
const WEAPON_CHOICE_PANEL := preload("res://scripts/ui/WeaponChoicePanel.gd")
const DEBUG_CONSOLE := preload("res://scripts/ui/DebugConsole.gd")
const PERFORMANCE_RECORDER := preload("res://scripts/game/PerformanceRecorder.gd")
const SUMMON_FIELD := preload("res://scripts/skills/SummonField.gd")
const MENU_SCENE := "res://scenes/character_select.tscn"
const ARENA_RECT := Rect2(-2400.0, -1800.0, 4800.0, 3600.0)
const FONT_PATH := "res://assets/fonts/NotoSansSC-Variable.ttf"
## 死亡演出（裂片、涟漪、震屏）播完再弹结算，避免一帧内冻结画面。
const GAME_OVER_DELAY := 0.6
## 商人：触碰后先击退周围敌人、吸完全屏经验/金币，再打开商店。
## 兜底时间防止掉落在角落里追不上；宝箱不参与，不会卡住商店。
const MERCHANT_VACUUM_MAX_TIME := 1.1
const MERCHANT_KNOCKBACK_RADIUS := 340.0
const MERCHANT_KNOCKBACK_STRENGTH := 760.0
const MERCHANT_KNOCKBACK_TIME := 0.42

@onready var grid: GridBackground = $Arena
@onready var camera: CameraRig = $CameraRig
@onready var world: Node2D = $World
@onready var fx_layer: Node2D = $FXLayer
@onready var projectile_manager: ProjectileManager = $World/ProjectileManager
@onready var level_up_panel: LevelUpPanel = $HUD/LevelUpPanel
@onready var shop_panel: ShopPanel = $HUD/ShopPanel
@onready var altar_panel: AltarPanel = $HUD/AltarPanel
@onready var pause_panel: PausePanel = $HUD/PausePanel
@onready var game_over_panel: GameOverPanel = $HUD/GameOverPanel
@onready var hud_control: Control = $HUD/HUDControl
@onready var pause_button: PauseButton = $HUD/HUDControl/PauseButton
@onready var mobile_controls: MobileControls = $HUD/HUDControl/MobileControls

var player: Player
var _level_ups_pending := 0
var _active_merchant: Merchant
var _pending_merchant: Merchant
var _active_altar: Altar
var _pending_altar: Altar
var _manual_paused := false
var _vacuum_merchant: Merchant
var _vacuum_timer := 0.0
var weapon_choice_panel: WeaponChoicePanel
var _weapon_rewards: Array[String] = []
var debug_console: DebugConsole


func _ready() -> void:
	Engine.time_scale = 1.0

	var font := load(FONT_PATH)
	if font != null:
		ThemeDB.fallback_font = font
		ThemeDB.fallback_font_size = 16

	RunState.arena_rect = ARENA_RECT
	grid.configure_rect(ARENA_RECT)
	fx_layer.add_to_group("fx_layer")
	FX.prewarm(fx_layer)

	RunState.begin_run()
	if OS.get_cmdline_user_args().has("--profile"):
		var recorder := PERFORMANCE_RECORDER.new()
		add_child(recorder)
		recorder.setup(self)
	_spawn_player()
	projectile_manager.combat.player = player
	world.add_child(ENEMY_BATCH_RENDERER.new())
	weapon_choice_panel = WEAPON_CHOICE_PANEL.new()
	$HUD.add_child(weapon_choice_panel)
	if OS.is_debug_build() and not OS.has_feature("mobile"):
		debug_console = DEBUG_CONSOLE.new()
		$HUD.add_child(debug_console)
		debug_console.setup(self)
	var modal_panels: Array[Control] = [
		level_up_panel, shop_panel, altar_panel, pause_panel, game_over_panel, weapon_choice_panel
	]
	mobile_controls.bind(player, pause_button, $HUD/RelicChoicePanel, modal_panels)
	Skills.bind_player(player)
	var summon_field: SummonField = SUMMON_FIELD.new()
	summon_field.name = "SummonField"
	world.add_child(summon_field)
	summon_field.setup(player)
	if player.character != null and player.character.id == &"prism":
		Skills.grant_relic(&"epic_six_sided_die")
	_debug_grant_relics()

	camera.setup(player, ARENA_RECT)
	Director.setup(world)
	EventBus.player_died.connect(_on_player_died)
	EventBus.enemy_killed.connect(_on_enemy_killed_for_weapon)
	EventBus.weapon_reward_requested.connect(_queue_weapon_reward)
	weapon_choice_panel.finished.connect(_on_weapon_reward_finished)
	EventBus.level_up.connect(_on_level_up)
	EventBus.merchant_reached.connect(_on_merchant_reached)
	EventBus.altar_reached.connect(_on_altar_reached)
	level_up_panel.skill_chosen.connect(_on_skill_chosen)
	level_up_panel.reroll_requested.connect(_on_skill_reroll_requested)
	shop_panel.closed.connect(_on_shop_closed)
	shop_panel.shelf_cleared.connect(_on_shelf_cleared)
	altar_panel.closed.connect(_on_altar_closed)
	pause_panel.closed.connect(_on_pause_closed)
	pause_panel.menu_requested.connect(_return_to_menu)
	game_over_panel.retry_requested.connect(_restart_run)
	game_over_panel.menu_requested.connect(_return_to_menu)
	pause_button.pressed.connect(_toggle_manual_pause)

	_play_intro()


## 调试：`-- --relic=dust_knife --relic=dust_apple` 开局直接拾取遗物。
func _debug_grant_relics() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--relic="):
			continue
		var id := StringName(arg.trim_prefix("--relic="))
		if not Skills.grant_relic(id):
			push_warning("遗物不存在，或唯一遗物已拥有：%s" % id)


## 调试：`-- --levels=10`（裸 `--levels` 即 10）开局连升 N 级。
## 仍逐级发 level_up，因此会依次弹出正常的三选一面板，方便直接组出测试用 Build。
func _debug_grant_levels() -> void:
	var count := -1
	for arg in OS.get_cmdline_user_args():
		if arg == "--levels":
			count = 10
			break
		if arg.begins_with("--levels="):
			count = int(arg.trim_prefix("--levels="))
			break
	if count <= 0:
		return
	RunState.debug_grant_levels(count)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = Vector2.ZERO
	player.projectile_manager = projectile_manager
	world.add_child(player)


func _play_intro() -> void:
	player.controls_enabled = false
	player.intro_white = true
	player.queue_redraw()

	camera.play_intro(3.0, 1.0, 1.4)

	await get_tree().create_timer(0.55).timeout

	player.intro_white = false
	player.play_color_reveal()
	FX.glow_pulse(0.8, 0.7)

	await get_tree().create_timer(0.95).timeout

	player.controls_enabled = true
	RunState.start()
	Director.start()

	# 调试：`-- --merchant` 开局直接叫出商人（方便手动检查箭头与商店）。
	if OS.get_cmdline_user_args().has("--merchant"):
		Director.spawn_merchant_now()
	# 调试：`-- --boss` 开局直接生成 180 秒 Boss，省去等待。
	if OS.get_cmdline_user_args().has("--boss"):
		Director.spawn_boss_now()
	_debug_grant_levels()


func _on_level_up(_new_level: int) -> void:
	_level_ups_pending += 1
	if not level_up_panel.visible:
		_open_next_level_up()


func _open_next_level_up() -> void:
	if _level_ups_pending <= 0:
		return

	var options := Skills.pick_options(3)
	if options.is_empty():
		_level_ups_pending -= 1
		if _level_ups_pending > 0:
			_open_next_level_up()
		else:
			_finish_level_ups()
		return

	hud_control.visible = false
	RunState.request_pause(&"level_up")
	level_up_panel.open(options, 1 if Skills.relic_count(&"epic_six_sided_die") > 0 else 0)


func _on_skill_reroll_requested() -> void:
	var excluded: Array[StringName] = []
	for node in level_up_panel._options:
		excluded.append(node.id)
	var options := Skills.pick_options(3, excluded)
	if options.is_empty():
		return
	level_up_panel.open(options, 0)


func _on_skill_chosen(node: SkillNodeResource) -> void:
	_level_ups_pending = maxi(0, _level_ups_pending - 1)
	# 面板打开期间游戏暂停，节点一定仍然可用；force 只用于防御性兜底。
	Skills.unlock(node.id, true)

	if _level_ups_pending > 0:
		_open_next_level_up()
	else:
		_finish_level_ups()


func _finish_level_ups() -> void:
	level_up_panel.close()
	hud_control.visible = true
	RunState.release_pause(&"level_up")

	# 同一帧里既升级又碰到商人/祭坛：先处理完升级队列再打开事件面板。
	_flush_pending_events()


func _on_merchant_reached(merchant_node: Node) -> void:
	if RunState.is_dead or shop_panel.visible or altar_panel.visible or pause_panel.visible:
		return
	var merchant := merchant_node as Merchant
	if merchant == null:
		return

	# 升级/暂停/祭坛面板优先；关闭时再接着打开商店。
	if level_up_panel.visible or altar_panel.visible or _manual_paused:
		_pending_merchant = merchant
		return

	_begin_merchant_vacuum(merchant)


## 触碰商人：不暂停，先击退周围敌人并把全屏经验/金币吸向玩家。
## 吸完（或超过兜底时间）后由 `_process` 打开商店。
func _begin_merchant_vacuum(merchant: Merchant) -> void:
	if RunState.is_dead or merchant == null or not is_instance_valid(merchant):
		return
	if _vacuum_merchant != null and is_instance_valid(_vacuum_merchant):
		return

	_vacuum_merchant = merchant
	_vacuum_timer = MERCHANT_VACUUM_MAX_TIME
	_knockback_enemies(merchant.global_position)
	Pickups.vacuum_all()
	FX.shockwave(
		merchant.global_position,
		Color(1.9, 1.35, 0.4, 1.0),
		MERCHANT_KNOCKBACK_RADIUS,
		0.45,
		EnergyBurst.STYLE_PANIC
	)
	FX.ripple(merchant.global_position, 0.8)


func _knockback_enemies(origin: Vector2) -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(origin) > MERCHANT_KNOCKBACK_RADIUS:
			continue
		enemy.apply_knockback(origin, MERCHANT_KNOCKBACK_STRENGTH, MERCHANT_KNOCKBACK_TIME)


func _process(delta: float) -> void:
	if _vacuum_merchant == null:
		return
	if RunState.is_dead or not is_instance_valid(_vacuum_merchant):
		_vacuum_merchant = null
		return
	# 升级/祭坛/暂停面板会暂停整棵树，这里自然停住；关闭后接着吸完再进店。
	if level_up_panel.visible or altar_panel.visible or pause_panel.visible:
		return

	_vacuum_timer -= delta
	if _vacuum_timer > 0.0 and Pickups.currency_count() > 0:
		return

	var merchant := _vacuum_merchant
	_vacuum_merchant = null
	_open_shop(merchant)


func _open_shop(merchant: Merchant) -> void:
	if RunState.is_dead or merchant == null or not is_instance_valid(merchant):
		return
	_active_merchant = merchant
	hud_control.visible = false
	RunState.request_pause(&"shop")
	shop_panel.open(player)


## 隐藏机制：买空一次货架，下一只商人提前 10 秒；页面上不提示。
func _on_shelf_cleared() -> void:
	Director.shorten_next_merchant(Director.SHELF_CLEAR_BONUS)


func _on_shop_closed() -> void:
	shop_panel.close()
	hud_control.visible = true
	RunState.release_pause(&"shop")

	if _active_merchant != null and is_instance_valid(_active_merchant):
		_active_merchant.leave()
	_active_merchant = null

	_flush_pending_events()


# ── 祭坛 ─────────────────────────────────────────────────────────

func _on_altar_reached(altar_node: Node) -> void:
	if RunState.is_dead or altar_panel.visible:
		return
	var altar := altar_node as Altar
	if altar == null:
		return

	if level_up_panel.visible or shop_panel.visible or pause_panel.visible or _manual_paused:
		_pending_altar = altar
		return

	_open_altar(altar)


func _open_altar(altar: Altar) -> void:
	if altar == null or not is_instance_valid(altar):
		return
	_active_altar = altar
	hud_control.visible = false
	RunState.request_pause(&"altar")
	altar_panel.open(altar, player)


func _on_altar_closed(_traded: bool) -> void:
	altar_panel.close()
	hud_control.visible = true
	RunState.release_pause(&"altar")

	if _active_altar != null and is_instance_valid(_active_altar):
		_active_altar.leave()
	_active_altar = null

	_flush_pending_events()


## 任意事件面板关闭后统一处理排队：商人优先，其次祭坛。
func _flush_pending_events() -> void:
	if RunState.is_dead:
		return
	if level_up_panel.visible or shop_panel.visible or altar_panel.visible \
			or pause_panel.visible or weapon_choice_panel.visible or _manual_paused:
		return

	if _pending_merchant != null and is_instance_valid(_pending_merchant):
		var merchant := _pending_merchant
		_pending_merchant = null
		_begin_merchant_vacuum(merchant)
		return
	if _pending_altar != null and is_instance_valid(_pending_altar):
		var altar := _pending_altar
		_pending_altar = null
		_open_altar(altar)
		return
	if not _weapon_rewards.is_empty():
		var source: String = _weapon_rewards.pop_front()
		hud_control.visible = false
		RunState.request_pause(&"weapon_reward")
		if not weapon_choice_panel.open_reward(player, source):
			RunState.add_gold(100)
			_on_weapon_reward_finished()


func _on_enemy_killed_for_weapon(enemy: Node, _gold: int, _xp: float) -> void:
	if enemy is Enemy and enemy.type_data != null and enemy.type_data.is_boss:
		_queue_weapon_reward.call_deferred("Boss 宝箱")


func _queue_weapon_reward(source: String) -> void:
	_weapon_rewards.append(source)
	_flush_pending_events()


func open_debug_weapon_choice() -> void:
	hud_control.visible = false
	RunState.request_pause(&"weapon_reward")
	if not weapon_choice_panel.open_primary_choice(player, "控制台获得武器"):
		_on_weapon_reward_finished()


func _on_weapon_reward_finished() -> void:
	hud_control.visible = true
	RunState.release_pause(&"weapon_reward")
	_flush_pending_events()


# ── 手动暂停 ─────────────────────────────────────────────────────

func _toggle_manual_pause() -> void:
	if _manual_paused:
		_on_pause_closed()
	elif pause_panel.visible:
		pause_panel.close()
		_on_pause_closed()
	elif RunState.is_running and not RunState.is_dead \
			and not level_up_panel.visible and not shop_panel.visible \
			and not altar_panel.visible:
		_manual_paused = true
		hud_control.visible = false
		RunState.request_pause(&"manual_pause")
		pause_panel.open()


func _on_pause_closed() -> void:
	if not _manual_paused:
		pause_panel.close()
		return
	pause_panel.close()
	_manual_paused = false
	RunState.release_pause(&"manual_pause")
	if RunState.is_dead:
		return
	hud_control.visible = true

	# 暂停前碰到的商人/祭坛不会丢：恢复后接着打开。
	_flush_pending_events()


func _on_player_died() -> void:
	_pending_merchant = null
	_pending_altar = null
	_vacuum_merchant = null
	_manual_paused = false
	if pause_panel.visible:
		pause_panel.close()
	RunState.release_pause(&"manual_pause")
	if shop_panel.visible:
		shop_panel.close()
		RunState.release_pause(&"shop")
		hud_control.visible = true
	if altar_panel.visible:
		altar_panel.close()
		RunState.release_pause(&"altar")
		hud_control.visible = true
	if _active_merchant != null and is_instance_valid(_active_merchant):
		_active_merchant.leave()
	_active_merchant = null
	if _active_altar != null and is_instance_valid(_active_altar):
		_active_altar.leave()
	_active_altar = null

	_finish_level_ups()
	RunState.end_run()
	Director.stop()
	FX.ripple(player.global_position, 1.6)
	FX.shake(0.7)
	_show_game_over_soon()


func _show_game_over_soon() -> void:
	await get_tree().create_timer(GAME_OVER_DELAY).timeout
	if not is_inside_tree() or not RunState.is_dead or game_over_panel.visible:
		return
	hud_control.visible = false
	game_over_panel.open()
	RunState.request_pause(&"game_over")


func _restart_run() -> void:
	game_over_panel.close()
	RunState.release_pause(&"game_over")
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


## 结算/暂停菜单的统一出口：清掉暂停原因与局内状态后回到机体选择。
func _return_to_menu() -> void:
	_pending_merchant = null
	_pending_altar = null
	_vacuum_merchant = null
	_active_merchant = null
	_active_altar = null
	_manual_paused = false
	level_up_panel.close()
	shop_panel.close()
	altar_panel.close()
	pause_panel.close()
	game_over_panel.close()
	RunState.abandon_run()
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if RunState.is_dead and event.is_action_pressed(&"restart"):
		# 场景切换可能立即把 Main 移出树，先消费事件再重开。
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		_restart_run()
		return

	# Esc 打开暂停；暂停/升级/商店界面会先自行消费 Esc。
	if event.is_action_pressed(&"pause") and not RunState.is_dead:
		if level_up_panel.visible or shop_panel.visible or altar_panel.visible \
				or pause_panel.visible:
			return
		if RunState.is_running:
			_toggle_manual_pause()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if not GameInput.touch_controls_active or not is_node_ready():
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if RunState.is_running and not get_tree().paused:
			_toggle_manual_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if shop_panel.visible:
			_on_shop_closed()
		elif altar_panel.visible:
			_on_altar_closed(false)
		elif not level_up_panel.visible and not RunState.is_dead:
			_toggle_manual_pause()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
