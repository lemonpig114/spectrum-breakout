class_name Altar
extends Node2D

## 恶魔/天使地面祭坛。契约 3 阶（`path_*_3`）解锁后由 Director 刷新。
##
## - 恶魔祭坛：支付 1 颗生命上限，获得一个尚未拥有的恶魔遗物。
## - 天使祭坛：支付金币（随存活时间小幅上涨），获得一个尚未拥有的天使遗物。
## - 本阵营 3 个遗物都拿完后，交易改为“馈赠”：恶魔回 2 颗心 / 天使 +150 金币。
##
## 和商人一样不参与物理：只做距离检测，靠近后暂停并打开 AltarPanel（由 Main 管理）。

const BODY_RADIUS := 26.0
const INTERACT_RADIUS := 42.0
const LIFETIME := 45.0

const DEMON_HEALTH_COST := 1.0
const ANGEL_GOLD_BASE := 120
const ANGEL_GOLD_PER_MINUTE := 20
const EMPTY_REWARD_HEAL := 2.0
const EMPTY_REWARD_GOLD := 150

const SPIN_SPEED := 0.9
const BOB_SPEED := 1.7

var player: Player
var side: StringName = &"demon"

var _time := 0.0
var _lifetime := LIFETIME
var _interacted := false
var _traded := false
var _leaving := false


static func side_color(value: StringName) -> Color:
	if value == &"demon":
		return Color(2.6, 0.24, 0.34, 1.0)
	return Color(2.6, 1.9, 0.45, 1.0)


static func side_name(value: StringName) -> String:
	return "恶魔" if value == &"demon" else "天使"


func setup(player_node: Player, side_value: StringName) -> void:
	player = player_node
	side = side_value


func _ready() -> void:
	add_to_group(&"altar")
	z_index = 2
	queue_redraw()


func _exit_tree() -> void:
	EventBus.altar_despawned.emit(self)


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


## 天使祭坛的金币价格：基础 120，每存活一分钟 +20。
func gold_cost() -> int:
	return ANGEL_GOLD_BASE + ANGEL_GOLD_PER_MINUTE * int(RunState.elapsed / 60.0)


func health_cost() -> float:
	return DEMON_HEALTH_COST


func reward_is_relic() -> bool:
	return Skills.side_relic_remaining(side) > 0


func reward_label() -> String:
	if reward_is_relic():
		return "随机一个未拥有的%s遗物\n（剩余 %d 个）" % [
			side_name(side), Skills.side_relic_remaining(side)
		]
	if side == &"demon":
		return "鲜血馈赠：回复 %.1f 颗心" % EMPTY_REWARD_HEAL
	return "天国馈赠：金币 +%d" % EMPTY_REWARD_GOLD


func cost_label() -> String:
	if side == &"demon":
		return "生命上限 -%.1f 颗心" % DEMON_HEALTH_COST
	return "金币 -%d" % gold_cost()


func can_afford(player_node: Player) -> bool:
	if player_node == null or not is_instance_valid(player_node):
		return false
	if side == &"demon":
		return Player.snap_to_half(
			player_node.stats.get_value(&"max_health") - DEMON_HEALTH_COST
		) >= 1.0
	return RunState.gold >= gold_cost()


## 结算交易。成功返回 true；失败时不会扣任何代价。
## 奖励与代价都在这里完成，测试可以直接调用（不必经过面板）。
func trade(player_node: Player) -> bool:
	if _traded or not can_afford(player_node):
		return false

	if side == &"demon":
		if not player_node.pay_max_health(DEMON_HEALTH_COST):
			return false
	elif not RunState.spend_gold(gold_cost()):
		return false

	var color := side_color(side)
	var relic := Skills.offer_side_relic(side)
	if relic != null:
		FX.text_popup(
			global_position + Vector2(0.0, -52.0),
			"发现「%s」" % relic.display_name,
			color,
			18
		)
	else:
		# 本阵营遗物已集齐：交易转化为即时馈赠，避免祭坛变成空箱子。
		if side == &"demon":
			player_node.heal(EMPTY_REWARD_HEAL)
			FX.text_popup(
				global_position + Vector2(0.0, -52.0),
				"鲜血馈赠：回复 %.1f 颗心" % EMPTY_REWARD_HEAL,
				color,
				17
			)
		else:
			RunState.add_gold(EMPTY_REWARD_GOLD)
			FX.text_popup(
				global_position + Vector2(0.0, -52.0),
				"天国馈赠：金币 +%d" % EMPTY_REWARD_GOLD,
				color,
				17
			)

	_traded = true
	Audio.play(&"altar_trade")
	FX.hit_burst(global_position, color, 56.0, 0.42, EnergyBurst.STYLE_STAR)
	FX.ripple(global_position, 0.55)
	queue_redraw()
	return true


func _interact() -> void:
	if _interacted:
		return
	_interacted = true
	EventBus.altar_reached.emit(self)
	queue_redraw()


## 交易完成/玩家离开后收场；与商人相同，用暂停安全 Tween 缩放淡出。
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	remove_from_group(&"altar")

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.62, 0.62), 0.32)
	tween.tween_property(self, "modulate:a", 0.0, 0.32)
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	var color := side_color(side)
	var bob := sin(_time * BOB_SPEED) * 3.0
	var pulse := 0.5 + 0.5 * sin(_time * 2.6)
	var center := Vector2(0.0, -28.0 + bob)

	# 地面光环：压扁成椭圆，缓慢反向旋转。
	draw_set_transform(Vector2(0.0, 8.0), -_time * 0.35, Vector2(1.0, 0.36))
	draw_arc(
		Vector2.ZERO,
		36.0,
		0.0,
		TAU,
		48,
		Color(color.r, color.g, color.b, 0.18 + 0.22 * pulse),
		2.0,
		true
	)
	draw_arc(
		Vector2.ZERO,
		27.0,
		0.0,
		TAU,
		40,
		Color(color.r, color.g, color.b, 0.10 + 0.14 * pulse),
		1.2,
		true
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 环绕的三枚小菱形，暗示祭坛正在运转。
	for i in 3:
		var angle := _time * SPIN_SPEED + TAU * float(i) / 3.0
		var orbit := Vector2(cos(angle) * 34.0, sin(angle) * 13.0 - 18.0 + bob * 0.4)
		_draw_diamond(orbit, 5.0, Color(color.r, color.g, color.b, 0.55 + 0.3 * pulse))

	if side == &"demon":
		_draw_demon(center, color, pulse)
	else:
		_draw_angel(center, color, pulse)

	# 核心：白亮小圆，Glow 会把祭坛从背景里拉出来。
	draw_circle(center + Vector2(0.0, 2.0), 4.0 + 1.2 * pulse, Color(2.4, 2.4, 2.4, 0.95))


func _draw_demon(center: Vector2, color: Color, pulse: float) -> void:
	var fill := Color(color.r * 0.10, color.g * 0.08, color.b * 0.09, 1.0)
	# 倒三角石碑：尖端朝下，两根外挑的角。
	var body := PackedVector2Array([
		center + Vector2(0.0, 30.0),
		center + Vector2(-25.0, -14.0),
		center + Vector2(0.0, -26.0),
		center + Vector2(25.0, -14.0),
	])
	draw_colored_polygon(body, fill)
	draw_polyline(body, Color(color.r, color.g, color.b, 0.9), 2.0, true)
	draw_line(
		center + Vector2(-12.0, 4.0),
		center + Vector2(12.0, 4.0),
		Color(color.r, color.g, color.b, 0.5 + 0.3 * pulse),
		1.5,
		true
	)
	# 内部倒置菱形“眼睛”，内部越亮越像一颗心。
	_draw_diamond(center + Vector2(0.0, -5.0), 10.0, Color(color.r, color.g, color.b, 0.55))
	draw_circle(center + Vector2(0.0, -5.0), 3.0, Color(2.2, 0.5, 0.55, 0.9 * pulse + 0.1))
	# 向上悬浮的两根尖刺。
	draw_line(
		center + Vector2(-17.0, -18.0),
		center + Vector2(-24.0, -36.0),
		Color(color.r, color.g, color.b, 0.75),
		2.0,
		true
	)
	draw_line(
		center + Vector2(17.0, -18.0),
		center + Vector2(24.0, -36.0),
		Color(color.r, color.g, color.b, 0.75),
		2.0,
		true
	)


func _draw_angel(center: Vector2, color: Color, pulse: float) -> void:
	var fill := Color(color.r * 0.10, color.g * 0.10, color.b * 0.06, 1.0)
	# 正三角方尖碑 + 背后的光翼。
	var left_wing := PackedVector2Array([
		center + Vector2(-8.0, -2.0),
		center + Vector2(-38.0, -20.0),
		center + Vector2(-26.0, 8.0),
	])
	var right_wing := PackedVector2Array([
		center + Vector2(8.0, -2.0),
		center + Vector2(38.0, -20.0),
		center + Vector2(26.0, 8.0),
	])
	draw_colored_polygon(left_wing, Color(color.r, color.g, color.b, 0.10 + 0.08 * pulse))
	draw_colored_polygon(right_wing, Color(color.r, color.g, color.b, 0.10 + 0.08 * pulse))
	draw_polyline(left_wing, Color(color.r, color.g, color.b, 0.48), 1.4, true)
	draw_polyline(right_wing, Color(color.r, color.g, color.b, 0.48), 1.4, true)

	var body := PackedVector2Array([
		center + Vector2(0.0, -30.0),
		center + Vector2(19.0, 20.0),
		center + Vector2(-19.0, 20.0),
	])
	draw_colored_polygon(body, fill)
	draw_polyline(body, Color(color.r, color.g, color.b, 0.9), 2.0, true)

	# 头顶光环。
	draw_set_transform(center + Vector2(0.0, -42.0), 0.0, Vector2(1.0, 0.34))
	draw_arc(
		Vector2.ZERO,
		15.0,
		0.0,
		TAU,
		32,
		Color(color.r, color.g, color.b, 0.55 + 0.35 * pulse),
		2.2,
		true
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_diamond(center + Vector2(0.0, 2.0), 9.0, Color(color.r, color.g, color.b, 0.55))


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, Color(color.r, color.g, color.b, color.a * 0.25))
	draw_polyline(points, color, 1.4, true)
