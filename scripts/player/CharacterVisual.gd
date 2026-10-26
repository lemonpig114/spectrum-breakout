class_name CharacterVisual
extends RefCounted

## 机体与炮管的程序化绘制。Player 和角色选择界面共用同一套画法，
## 保证菜单里看到的外形就是局内实际外形。
## 所有坐标都是传入 canvas 的局部坐标；Player 的 _draw 与卡片预览都直接调用。

const BODY_CIRCLE := 0
const BODY_HEXAGON := 1
const BODY_TRIANGLE := 2

const BARREL_CHEVRON := 0
const BARREL_TWIN := 1
const BARREL_ARROW := 2


static func draw_unit(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	color: Color,
	body_style: int,
	barrel_style: int,
	aim_angle: float,
	time: float,
	recoil: float = 0.0,
	muzzle: float = 0.0,
	alpha: float = 1.0
) -> void:
	var a := clampf(alpha, 0.0, 1.0)
	if a <= 0.0:
		return

	var dir := Vector2.from_angle(aim_angle)
	var perp := Vector2(-dir.y, dir.x)
	var line_color := Color(color.r, color.g, color.b, a)
	var dim_color := Color(color.r, color.g, color.b, a * 0.35)
	var fill_color := Color(color.r * 0.11, color.g * 0.11, color.b * 0.11, a * 0.92)

	# 外层柔光：低透明度 HDR 色，交给 WorldEnvironment 的 Glow 泛开。
	var halo_radius := radius * 3.4
	canvas.draw_texture_rect(
		preload("res://scripts/fx/NeonTexture.gd").halo(),
		Rect2(center - Vector2.ONE * halo_radius, Vector2.ONE * halo_radius * 2.0),
		false, Color(color.r, color.g, color.b, a * 0.18)
	)

	# 三道缓慢旋转的细弧，增加“机体在运转”的感觉；不能太抢主体。
	for i in 3:
		var start := time * 0.85 + TAU * float(i) / 3.0
		canvas.draw_arc(
			center,
			radius + 4.5,
			start,
			start + 0.5,
			10,
			Color(color.r, color.g, color.b, a * 0.20),
			1.2,
			true
		)

	match body_style:
		BODY_HEXAGON:
			_draw_hexagon(canvas, center, radius, time, line_color, dim_color, fill_color)
		BODY_TRIANGLE:
			_draw_triangle(canvas, center, radius, dir, aim_angle, line_color, dim_color, fill_color)
		_:
			_draw_circle_body(canvas, center, radius, time, line_color, dim_color, fill_color)

	# 核心：呼吸的彩色光点 + 白色高亮，任何机体都有。
	var pulse := 1.0 + 0.08 * sin(time * 4.0)
	canvas.draw_circle(center, radius * 0.30 * pulse, Color(color.r, color.g, color.b, a * 0.85))
	canvas.draw_circle(center, radius * 0.12, Color(2.2, 2.2, 2.2, a * 0.9))

	match barrel_style:
		BARREL_TWIN:
			_draw_twin_barrel(canvas, center, radius, dir, perp, recoil, line_color, dim_color)
		BARREL_ARROW:
			_draw_arrow_barrel(canvas, center, radius, dir, perp, recoil, line_color, line_color)
		_:
			_draw_chevron_barrel(canvas, center, radius, dir, perp, recoil, line_color)

	if muzzle > 0.01:
		_draw_muzzle(canvas, center, radius, dir, perp, barrel_style, muzzle * a)


static func _draw_circle_body(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	time: float,
	line_color: Color,
	dim_color: Color,
	fill_color: Color
) -> void:
	canvas.draw_circle(center, radius, fill_color)
	canvas.draw_arc(center, radius, 0.0, TAU, 48, line_color, 2.4, true)
	# 内圈有一段随时间旋转的缺口，像内部转子。
	var start := -0.6 + time * 0.6
	canvas.draw_arc(center, radius * 0.62, start, start + 2.6, 22, dim_color, 1.2, true)


static func _draw_hexagon(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	time: float,
	line_color: Color,
	dim_color: Color,
	fill_color: Color
) -> void:
	var outer := _regular_polygon(center, radius * 1.04, 6, time * 0.32)
	canvas.draw_colored_polygon(outer, fill_color)
	var closed := outer.duplicate()
	closed.append(outer[0])
	canvas.draw_polyline(closed, line_color, 2.4, true)

	var inner := _regular_polygon(center, radius * 0.56, 6, -time * 0.48)
	var inner_closed := inner.duplicate()
	inner_closed.append(inner[0])
	canvas.draw_polyline(inner_closed, dim_color, 1.2, true)


static func _draw_triangle(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	dir: Vector2,
	aim_angle: float,
	line_color: Color,
	dim_color: Color,
	fill_color: Color
) -> void:
	# 飞镖形：机首永远朝瞄准方向。
	var tip := center + dir * radius * 1.35
	var back_left := center + Vector2.from_angle(aim_angle + 2.35) * radius * 0.98
	var back_right := center + Vector2.from_angle(aim_angle - 2.35) * radius * 0.98
	canvas.draw_colored_polygon(PackedVector2Array([tip, back_left, back_right]), fill_color)
	canvas.draw_polyline(
		PackedVector2Array([tip, back_left, back_right, tip]), line_color, 2.4, true
	)

	var inner_tip := center + dir * radius * 0.62
	var inner_left := center + Vector2.from_angle(aim_angle + 2.3) * radius * 0.46
	var inner_right := center + Vector2.from_angle(aim_angle - 2.3) * radius * 0.46
	canvas.draw_polyline(
		PackedVector2Array([inner_tip, inner_left, inner_right, inner_tip]), dim_color, 1.2, true
	)


static func _draw_chevron_barrel(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	dir: Vector2,
	perp: Vector2,
	recoil: float,
	line_color: Color
) -> void:
	# 人字炮：两道斜线在机首前方交汇成 ^，不与机体重叠成实心三角。
	var kick := 5.0 * recoil
	var base := radius * 0.75 - kick
	var length := radius + 12.0 - kick
	var half := radius * 0.50
	var left := center + dir * base + perp * half
	var right := center + dir * base - perp * half
	var tip := center + dir * length
	# 中央炮身让 ^ 不只是两根叉子，收束点更像炮口。
	canvas.draw_line(center + dir * (base * 0.55), tip, Color(line_color.r, line_color.g, line_color.b, line_color.a * 0.55), 1.5, true)
	canvas.draw_line(left, tip, line_color, 2.0, true)
	canvas.draw_line(right, tip, line_color, 2.0, true)
	canvas.draw_circle(tip, 2.0, line_color)


static func _draw_twin_barrel(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	dir: Vector2,
	perp: Vector2,
	recoil: float,
	line_color: Color,
	dim_color: Color
) -> void:
	# 双轨炮：两根平行轨道 + 前端收束的人字炮口。
	var kick := 5.0 * recoil
	var gap := radius * 0.34
	var start_dist := radius * 0.85 - kick
	var end_dist := radius + 8.0 - kick
	var offset := perp * gap
	canvas.draw_line(center + dir * start_dist + offset, center + dir * end_dist + offset, line_color, 2.2, true)
	canvas.draw_line(center + dir * start_dist - offset, center + dir * end_dist - offset, line_color, 2.2, true)

	var cross_dist := (start_dist + end_dist) * 0.5
	canvas.draw_line(
		center + dir * cross_dist + offset,
		center + dir * cross_dist - offset,
		dim_color,
		1.4,
		true
	)

	var apex := center + dir * (radius + 15.0 - kick)
	canvas.draw_line(center + dir * end_dist + offset, apex, line_color, 2.0, true)
	canvas.draw_line(center + dir * end_dist - offset, apex, line_color, 2.0, true)
	canvas.draw_circle(apex, 2.0, line_color)


static func _draw_arrow_barrel(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	dir: Vector2,
	perp: Vector2,
	recoil: float,
	line_color: Color,
	dim_color: Color
) -> void:
	# 箭形炮：细长炮身 + 后掠箭头。
	var kick := 5.0 * recoil
	var start_dist := radius * 0.8 - kick
	var end_dist := radius + 13.0 - kick
	var tip := center + dir * end_dist
	canvas.draw_line(center + dir * start_dist, tip, line_color, 2.2, true)
	canvas.draw_line(tip, tip - dir * 7.0 + perp * 4.6, line_color, 2.0, true)
	canvas.draw_line(tip, tip - dir * 7.0 - perp * 4.6, line_color, 2.0, true)
	canvas.draw_circle(tip, 1.8, dim_color)


static func _draw_muzzle(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	dir: Vector2,
	perp: Vector2,
	barrel_style: int,
	strength: float
) -> void:
	var distance := radius + 12.0
	if barrel_style == BARREL_TWIN:
		distance = radius + 15.0
	elif barrel_style == BARREL_ARROW:
		distance = radius + 13.0
	var tip := center + dir * distance
	canvas.draw_circle(tip, radius * 0.30 * strength, Color(2.4, 2.4, 2.4, strength * 0.75))
	canvas.draw_line(
		tip - perp * radius * 0.55 * strength,
		tip + perp * radius * 0.55 * strength,
		Color(2.0, 2.0, 2.0, strength * 0.45),
		1.5,
		true
	)


static func _regular_polygon(
	center: Vector2, radius: float, sides: int, rotation: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		points.append(center + Vector2.from_angle(rotation + TAU * float(i) / float(sides)) * radius)
	return points
