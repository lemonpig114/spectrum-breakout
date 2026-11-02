class_name BossChest
extends Node2D

## Boss 掉落的宝箱：全程序化绘制，必须玩家自己走过去捡起。
## - 不参与 PickupField 的磁吸 / 自动拾取，因此不会被吸走，只能靠近触发。
## - 靠近 → 播放开箱动画（掀盖 + 金色爆发）→ 动画播完发 opened 信号，
##   由 Main 打开武器三选一（“然后才是选择武器”）。
## - 不参与物理/碰撞，只做距离检测。

signal opened

const INTERACT_RADIUS := 32.0
const BOX_W := 46.0
const BOX_H := 30.0
const LID_H := 17.0
const SPAWN_DURATION := 0.5
const OPEN_DURATION := 0.8
const FADE_DELAY := 0.35
const FADE_DURATION := 0.4

## 金色 HDR（>1.0 驱动 Glow）。
const GOLD_DARK := Color(0.48, 0.28, 0.05, 1.0)
const GOLD_BODY := Color(1.75, 1.25, 0.35, 1.0)
const GOLD_RIM := Color(2.45, 1.9, 0.72, 1.0)
const GOLD_LIGHT := Color(3.0, 2.6, 1.6, 1.0)
const GLOW := Color(1.9, 1.45, 0.5, 1.0)

var player: Player

## 读档恢复时置 true：跳过落地特效与音效，避免读档瞬间的重复反馈。
var silent_spawn := false

var _time := 0.0
var _spawn := 0.0
var _open := 0.0
var _opening := false
var _emitted := false
var _fade := 0.0
var _fading := false


func setup(player_node: Player) -> void:
	player = player_node


func _ready() -> void:
	z_index = 4
	add_to_group(&"boss_chest")
	# 落地冲击：一圈金色涟漪 + 碎光（读档恢复时跳过）。
	if not silent_spawn:
		FX.ripple(global_position, 0.7)
		FX.shards(global_position, GOLD_LIGHT, 10)
		Audio.play(&"chest")
	queue_redraw()


## 尚未开箱、仍可被拾取时为 true（存档据此判断是否需要恢复宝箱）。
func is_pending() -> bool:
	return not _emitted and not _fading


func _process(delta: float) -> void:
	_time += delta
	_spawn = minf(1.0, _spawn + delta / SPAWN_DURATION)

	if RunState.is_dead:
		queue_free()
		return

	if _fading:
		_fade = minf(1.0, _fade + delta / FADE_DURATION)
		modulate.a = 1.0 - _fade
		if _fade >= 1.0:
			queue_free()
			return

	if not _opening and _spawn >= 1.0 and RunState.is_running:
		if _player_near():
			_begin_open()

	if _opening:
		_open = minf(1.0, _open + delta / OPEN_DURATION)
		if _open >= 1.0 and not _emitted:
			_emitted = true
			opened.emit()
			# 等面板打开、停顿一下再淡出（面板暂停时 process 也会停住，恢复后继续）。
			_start_fade.call_deferred()

	queue_redraw()


func _start_fade() -> void:
	var timer := get_tree().create_timer(FADE_DELAY)
	timer.timeout.connect(func() -> void:
		_fading = true)


func _begin_open() -> void:
	_opening = true
	Audio.play(&"chest")
	# 拾取动画：金色冲击波 + 网格涟漪 + 泛光标点 + 震屏。
	FX.shockwave(global_position + Vector2(0.0, -BOX_H), GOLD_LIGHT, 150.0, 0.4, EnergyBurst.STYLE_HEAVY)
	FX.ripple(global_position, 1.4)
	FX.shards(global_position + Vector2(0.0, -BOX_H), GOLD_LIGHT, 22)
	FX.glow_pulse(1.6, 0.7)
	FX.shake(0.35)


func _player_near() -> bool:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Player
	if player == null or not is_instance_valid(player):
		return false
	return global_position.distance_to(player.global_position) <= INTERACT_RADIUS + player.body_radius


func _draw() -> void:
	var appear := _ease_out(_spawn)
	var scale_factor := 0.55 + 0.45 * appear
	# 出场：从上方落下；开箱后停止呼吸起伏。
	var lift := (1.0 - appear) * -34.0
	var bob := sin(_time * 2.2) * 2.4 * (1.0 - _open)
	var base := Vector2(0.0, bob + lift)
	var pulse := 0.5 + 0.5 * sin(_time * 3.6)
	var near := _player_near()

	_draw_beam(appear, pulse, near)
	_draw_ground_shadow(appear, scale_factor)
	_draw_halo(base, appear, pulse, near)

	draw_set_transform(base, 0.0, Vector2(scale_factor, scale_factor))
	_draw_body(pulse)
	_draw_lid(pulse)
	_draw_sparkles(pulse, near)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_open_ring(base, appear)


## 远处可见的光柱：越靠近越亮，开箱时收束。
func _draw_beam(appear: float, pulse: float, near: bool) -> void:
	var strength := appear * (0.32 + 0.22 * pulse) * (1.45 if near else 1.0) * (1.0 - _open * 0.85)
	if strength <= 0.002:
		return
	var w := BOX_W * 0.5
	var seam_y := -BOX_H
	# 梯形光柱（上窄下宽的反向：顶点在上）。
	var apex := Vector2(0.0, seam_y - 168.0)
	draw_colored_polygon(
		PackedVector2Array([apex, Vector2(-w, seam_y + 2.0), Vector2(w, seam_y + 2.0)]),
		Color(GLOW.r, GLOW.g, GLOW.b, strength * 0.13)
	)
	# 中央更亮的核心。
	draw_colored_polygon(
		PackedVector2Array([Vector2(0.0, seam_y - 150.0), Vector2(-w * 0.34, seam_y + 2.0), Vector2(w * 0.34, seam_y + 2.0)]),
		Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, strength * 0.16)
	)


func _draw_ground_shadow(appear: float, scale_factor: float) -> void:
	draw_set_transform(Vector2(0.0, 2.0), 0.0, Vector2(scale_factor, 0.34 * scale_factor))
	draw_circle(Vector2.ZERO, BOX_W * 0.62, Color(0.0, 0.0, 0.0, 0.5 * appear))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_body(pulse: float) -> void:
	var half := BOX_W * 0.5
	var top := -BOX_H
	# 开箱后的内部亮光：只有箱口透光，不把整面填成一块白。
	if _open > 0.01:
		draw_rect(Rect2(Vector2(-half + 3.0, top), Vector2(BOX_W - 6.0, BOX_H * 0.45)),
			Color(1.0, 0.95, 0.7, 0.85 * _open))
		draw_line(Vector2(-half + 3.0, top), Vector2(half - 3.0, top),
			Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, 0.9 * _open), 2.0)
	# 箱体：暗边 + 亮面。
	draw_rect(Rect2(Vector2(-half - 1.5, top - 1.5), Vector2(BOX_W + 3.0, BOX_H + 1.5)), GOLD_DARK)
	draw_rect(Rect2(Vector2(-half, top), Vector2(BOX_W, BOX_H)), GOLD_BODY)
	draw_rect(Rect2(Vector2(-half, top), Vector2(BOX_W, BOX_H)), GOLD_RIM, false, 2.2)
	# 竖向金属带。
	for sx in [-1.0, 1.0]:
		draw_rect(Rect2(Vector2(sx * (half - 8.0) - 1.6, top), Vector2(3.2, BOX_H)), GOLD_DARK)
	# 正面锁扣 + 锁孔。
	draw_rect(Rect2(Vector2(-4.5, top + BOX_H * 0.32), Vector2(9.0, 10.0)), GOLD_RIM)
	draw_circle(Vector2(0.0, top + BOX_H * 0.32 + 5.0), 1.9, Color(0.35, 0.2, 0.03, 1.0))
	# 呼吸高光带。
	draw_rect(Rect2(Vector2(-half + 3.5, top + 2.5), Vector2(BOX_W - 7.0, 3.0)),
		Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, 0.22 + 0.28 * pulse))


func _draw_lid(pulse: float) -> void:
	var half := BOX_W * 0.5
	var hinge := Vector2(0.0, -BOX_H)
	# 掀盖：绕后沿旋转约 110°。
	draw_set_transform(hinge, -_open * 1.95, Vector2.ONE)

	var hw := half + 1.5
	var pts := PackedVector2Array([
		Vector2(-hw, 1.0),
		Vector2(-hw, -LID_H * 0.5),
		Vector2(-hw + 4.5, -LID_H),
		Vector2(hw - 4.5, -LID_H),
		Vector2(hw, -LID_H * 0.5),
		Vector2(hw, 1.0),
	])
	draw_colored_polygon(pts, GOLD_BODY)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, GOLD_RIM, 2.2, true)
	# 盖面高光。
	draw_line(Vector2(-hw + 5.0, -LID_H + 3.2), Vector2(hw - 5.0, -LID_H + 3.2),
		Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, 0.45 + 0.35 * pulse), 2.2)
	# 盖上的竖向金属带。
	for sx in [-1.0, 1.0]:
		draw_rect(Rect2(Vector2(sx * (half - 8.0) - 1.6, -LID_H), Vector2(3.2, LID_H)), GOLD_DARK)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 环绕的旋转金色菱片，靠近时更多更亮。
func _draw_sparkles(pulse: float, near: bool) -> void:
	var count := 6 if near else 4
	var brightness := 0.55 + 0.4 * pulse
	for i in count:
		var ang := _time * 1.3 + TAU * float(i) / float(count)
		var radius := BOX_W * (0.72 + 0.08 * sin(_time * 2.0 + float(i)))
		var center := Vector2(cos(ang), sin(ang) * 0.55) * radius + Vector2(0.0, -BOX_H * 0.5)
		var size := 2.6 + 1.2 * pulse
		draw_colored_polygon(
			PackedVector2Array([
				center + Vector2(0.0, -size),
				center + Vector2(size * 0.7, 0.0),
				center + Vector2(0.0, size),
				center + Vector2(-size * 0.7, 0.0),
			]),
			Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, brightness)
		)


func _draw_halo(base: Vector2, appear: float, pulse: float, near: bool) -> void:
	var strength := appear * (0.5 + 0.5 * pulse) * (1.5 if near else 1.0)
	var center := base + Vector2(0.0, -BOX_H * 0.5)
	# 只画柔和光环 + 一点内芯，避免大实心圆被 HDR 泛光糊成一团。
	draw_arc(center, BOX_W * (0.88 + 0.10 * strength), 0.0, TAU, 42,
		Color(GLOW.r, GLOW.g, GLOW.b, (0.10 + 0.15 * strength) * appear), 2.0, true)
	draw_circle(center, BOX_W * 0.52, Color(GLOW.r, GLOW.g, GLOW.b, 0.05 * strength * appear))


## 开箱瞬间扩散的金色圆环。
func _draw_open_ring(base: Vector2, appear: float) -> void:
	if _open <= 0.001 or _open >= 1.0:
		return
	var radius := BOX_W * (0.6 + 2.2 * _open)
	var alpha := (1.0 - _open) * 0.85 * appear
	draw_arc(base + Vector2(0.0, -BOX_H * 0.5), radius, 0.0, TAU, 40,
		Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, alpha), 3.0 * (1.0 - _open) + 1.0, true)


func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)
