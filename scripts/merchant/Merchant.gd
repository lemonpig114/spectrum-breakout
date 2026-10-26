class_name Merchant
extends Node2D

## 可发现商人：比玩家更大的金色圆形身体，拟人化的手脚和钱符号，
## 原地蹦跳；玩家靠近即开商店。HUD 会在它离开屏幕时画方向箭头。
##
## 不参与物理/碰撞：只做距离检测，避免和敌人/弹体产生任何物理开销。

const BODY_RADIUS := 20.0
const INTERACT_RADIUS := 34.0
const LIFETIME := 45.0
const HOP_PERIOD := 1.9
const HOP_DURATION := 0.55
const HOP_HEIGHT := 15.0

const GOLD_DARK := Color(0.62, 0.36, 0.05, 1.0)
const GOLD_BODY := Color(1.9, 1.3, 0.25, 1.0)
const GOLD_RIM := Color(2.5, 1.8, 0.55, 1.0)
const GOLD_LIGHT := Color(2.7, 2.2, 0.85, 1.0)

var player: Player

var _time := 0.0
var _lifetime := LIFETIME
var _interacted := false
var _leaving := false


func setup(player_node: Player) -> void:
	player = player_node


func _ready() -> void:
	add_to_group(&"merchant")
	z_index = 3
	queue_redraw()


func _exit_tree() -> void:
	EventBus.merchant_despawned.emit(self)


func _process(delta: float) -> void:
	if _leaving:
		return

	_time += delta
	if not _interacted:
		_lifetime -= delta
		if _lifetime <= 0.0:
			leave()
			return

		if player == null or not is_instance_valid(player):
			player = get_tree().get_first_node_in_group(&"player") as Player
		if (
			player != null
			and RunState.is_running
			and not RunState.is_dead
			and global_position.distance_to(player.global_position) \
				<= INTERACT_RADIUS + player.body_radius
		):
			_interact()

	if RunState.is_dead:
		leave()
		return

	queue_redraw()


func _interact() -> void:
	if _interacted:
		return
	_interacted = true
	EventBus.merchant_reached.emit(self)
	queue_redraw()


## 商店关闭后离场；调用方也可能直接调用（例如玩家死亡）。
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	remove_from_group(&"merchant")

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.65, 0.65), 0.35)
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	var hop := _hop_height()
	var body_center := Vector2(0.0, -BODY_RADIUS - 11.0 - hop)

	# 地面影子不随跳跃升高，落地时才收紧。
	var shadow_scale := 1.0 - hop / HOP_HEIGHT * 0.35
	draw_set_transform(Vector2(0.0, 1.0), 0.0, Vector2(shadow_scale, 0.32))
	draw_circle(Vector2.ZERO, BODY_RADIUS * 0.92, Color(0.0, 0.0, 0.0, 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_limbs(body_center, hop)

	# 金色圆身：外层暗边、内层亮面、呼吸光晕。
	draw_circle(body_center, BODY_RADIUS + 7.0, Color(1.2, 0.8, 0.2, 0.06))
	draw_circle(body_center, BODY_RADIUS, GOLD_BODY)
	draw_arc(body_center, BODY_RADIUS, 0.0, TAU, 36, GOLD_RIM, 2.2)
	draw_arc(body_center, BODY_RADIUS - 4.5, 0.0, TAU, 30, Color(2.2, 1.5, 0.4, 0.5), 1.0)

	# 高光弧让金币有体积感。
	draw_arc(
		body_center + Vector2(-2.0, -1.0),
		BODY_RADIUS - 6.0,
		PI * 1.05,
		PI * 1.55,
		12,
		Color(3.0, 2.6, 1.4, 0.9),
		2.0
	)

	_draw_symbol(body_center)


func _draw_limbs(body_center: Vector2, hop: float) -> void:
	var air := hop / HOP_HEIGHT
	# 腿：跳起时收起，落地时伸开。
	var leg_top := body_center + Vector2(0.0, BODY_RADIUS - 3.0)
	var foot_y := -2.0 - hop * 0.82
	for side in [-1.0, 1.0]:
		var hip := leg_top + Vector2(side * 6.0, 0.0)
		var foot := Vector2(side * 7.5, foot_y)
		draw_line(hip, foot, GOLD_DARK, 3.0, true)
		draw_circle(foot, 3.4, GOLD_RIM)

	# 手臂：随跳跃/时间摆动，末端是小手圆点。
	var swing := sin(_time * 3.6) * 4.0
	for side in [-1.0, 1.0]:
		var shoulder := body_center + Vector2(side * (BODY_RADIUS - 2.0), 1.0)
		var hand := shoulder + Vector2(side * 8.0, 5.0 + swing * side - air * 7.0)
		draw_line(shoulder, hand, GOLD_DARK, 3.0, true)
		draw_circle(hand, 3.8, GOLD_RIM)
		draw_circle(hand, 1.7, GOLD_LIGHT)


func _draw_symbol(body_center: Vector2) -> void:
	# 只保留居中的钱符号（不再画眼睛）；粗线程序化绘制，
	# 字体里的 ¥ 在这个尺寸太细，会被金色身体吃掉。
	var origin := body_center + Vector2(0.0, -8.0)
	var dark := Color(0.32, 0.16, 0.02, 1.0)
	var light := Color(2.9, 2.65, 1.7, 1.0)
	_coin_stroke(origin + Vector2(-6.0, -1.0), origin + Vector2(0.0, 6.0), dark, light)
	_coin_stroke(origin + Vector2(6.0, -1.0), origin + Vector2(0.0, 6.0), dark, light)
	_coin_stroke(origin + Vector2(0.0, 6.0), origin + Vector2(0.0, 17.0), dark, light)
	_coin_stroke(origin + Vector2(-5.0, 10.0), origin + Vector2(5.0, 10.0), dark, light)
	_coin_stroke(origin + Vector2(-5.0, 13.5), origin + Vector2(5.0, 13.5), dark, light)


func _coin_stroke(from: Vector2, to: Vector2, dark: Color, light: Color) -> void:
	draw_line(from, to, dark, 4.6, true)
	draw_line(from, to, light, 2.1, true)


func _hop_height() -> float:
	var cycle := fmod(_time, HOP_PERIOD)
	if cycle >= HOP_DURATION:
		return 0.0
	return sin(cycle / HOP_DURATION * PI) * HOP_HEIGHT
