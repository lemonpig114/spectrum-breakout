extends RefCounted

## 程序化技能图标：暂停菜单的技能线路图与升级卡片共用。
## 不依赖贴图，所有图形都画在传入的 CanvasItem 上。
## 颜色由调用方决定（通常取节点 accent），这里只负责形状。


static func draw_branch(
	canvas: CanvasItem,
	branch: StringName,
	center: Vector2,
	radius: float,
	color: Color
) -> void:
	var r := maxf(2.0, radius)
	var width := maxf(1.0, r * 0.13)
	match branch:
		&"fire_rate":
			_draw_bolt(canvas, center, r, color)
		&"heavy":
			_draw_heavy(canvas, center, r, color, width)
		&"energy":
			_draw_energy(canvas, center, r, color, width)
		&"speed":
			_draw_speed(canvas, center, r, color, width)
		&"demon":
			_draw_demon(canvas, center, r, color, width)
		&"angel":
			_draw_angel(canvas, center, r, color, width)
		&"xp":
			canvas.draw_colored_polygon(_star(center, r * 0.96, 0.42, 5), color)
			canvas.draw_circle(center, r * 0.10, Color(color.r, color.g, color.b, color.a * 0.55))
		&"gold":
			_draw_coin(canvas, center, r, color, width)
		&"soul":
			_draw_soul(canvas, center, r, color, width)
		&"splash":
			_draw_splash(canvas, center, r, color, width)
		&"weakness":
			_draw_weakness(canvas, center, r, color, width)
		&"crit":
			_draw_crit(canvas, center, r, color, width)
		&"shotgun":
			_draw_shotgun(canvas, center, r, color, width)
		&"luck":
			_draw_luck(canvas, center, r, color, width)
		&"fragile":
			canvas.draw_arc(center, r * 0.76, 0.0, TAU, 20, color, width, true)
			canvas.draw_line(_pt(center, -0.4, -0.8, r), _pt(center, 0.1, -0.1, r), color, width, true)
			canvas.draw_line(_pt(center, 0.1, -0.1, r), _pt(center, -0.2, 0.5, r), color, width, true)
			canvas.draw_line(_pt(center, -0.2, 0.5, r), _pt(center, 0.35, 0.78, r), color, width, true)
		&"sprite":
			canvas.draw_circle(center, r * 0.33, color)
			canvas.draw_arc(center, r * 0.7, -2.8, 0.5, 14, color, width * 0.8, true)
			canvas.draw_circle(_pt(center, -0.55, 0.34, r), r * 0.08, color)
		&"clone":
			canvas.draw_colored_polygon(PackedVector2Array([_pt(center, -0.45, -0.5, r), _pt(center, 0.0, -0.85, r), _pt(center, 0.45, -0.5, r), _pt(center, 0.0, 0.15, r)]), color)
			canvas.draw_arc(_pt(center, 0.0, 0.15, r), r * 0.5, 0.1, PI - 0.1, 12, color, width, true)
		&"circle":
			canvas.draw_arc(center, r * 0.8, 0.0, TAU, 24, color, width, true)
			canvas.draw_arc(center, r * 0.45, 0.0, TAU, 20, color, width * 0.7, true)
			canvas.draw_circle(center, r * 0.12, color)
		&"giant":
			canvas.draw_colored_polygon(PackedVector2Array([_pt(center, -0.8, 0.7, r), _pt(center, -0.65, -0.25, r), _pt(center, 0.0, -0.85, r), _pt(center, 0.65, -0.25, r), _pt(center, 0.8, 0.7, r)]), color)
			canvas.draw_circle(center, r * 0.17, Color(0.08, 0.05, 0.1))
		_:
			canvas.draw_circle(center, r * 0.38, color)


static func _pt(center: Vector2, x: float, y: float, r: float) -> Vector2:
	return center + Vector2(x * r, y * r)


static func _star(center: Vector2, r: float, inner: float, points: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points * 2:
		var radius := r if i % 2 == 0 else r * inner
		var angle := -PI * 0.5 + PI * float(i) / float(points)
		result.append(center + Vector2.from_angle(angle) * radius)
	return result


static func _draw_bolt(canvas: CanvasItem, center: Vector2, r: float, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([
		_pt(center, 0.02, -1.0, r),
		_pt(center, 0.55, -1.0, r),
		_pt(center, 0.12, -0.12, r),
		_pt(center, 0.48, -0.12, r),
		_pt(center, -0.42, 1.0, r),
		_pt(center, -0.16, 0.12, r),
		_pt(center, -0.52, 0.12, r),
	]), color)


static func _draw_heavy(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	canvas.draw_line(_pt(center, -0.58, -0.55, r), _pt(center, 0.0, 0.08, r), color, width * 2.6, true)
	canvas.draw_line(_pt(center, 0.0, 0.08, r), _pt(center, 0.58, -0.55, r), color, width * 2.6, true)
	canvas.draw_line(_pt(center, -0.48, 0.52, r), _pt(center, 0.48, 0.52, r), color, width * 2.0, true)


static func _draw_energy(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	var diamond := PackedVector2Array([
		_pt(center, 0.0, -0.9, r),
		_pt(center, 0.72, 0.0, r),
		_pt(center, 0.0, 0.9, r),
		_pt(center, -0.72, 0.0, r),
		_pt(center, 0.0, -0.9, r),
	])
	canvas.draw_polyline(diamond, color, width, true)
	canvas.draw_circle(center, r * 0.16, color)
	canvas.draw_circle(center, r * 0.52, Color(color.r, color.g, color.b, color.a * 0.35), false, width * 0.7)


static func _draw_speed(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	for i in 3:
		var x := -0.52 + float(i) * 0.42
		canvas.draw_line(_pt(center, x, -0.58, r), _pt(center, x + 0.36, 0.0, r), color, width * 1.7, true)
		canvas.draw_line(_pt(center, x + 0.36, 0.0, r), _pt(center, x, 0.58, r), color, width * 1.7, true)


static func _draw_demon(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	var triangle := PackedVector2Array([
		_pt(center, 0.0, 0.72, r),
		_pt(center, -0.72, -0.42, r),
		_pt(center, 0.72, -0.42, r),
		_pt(center, 0.0, 0.72, r),
	])
	canvas.draw_polyline(triangle, color, width, true)
	canvas.draw_line(_pt(center, -0.7, -0.42, r), _pt(center, -0.45, -0.9, r), color, width, true)
	canvas.draw_line(_pt(center, 0.7, -0.42, r), _pt(center, 0.45, -0.9, r), color, width, true)
	canvas.draw_circle(_pt(center, 0.0, 0.02, r), r * 0.12, color)


static func _draw_angel(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	canvas.draw_arc(center, r * 0.38, -PI, 0.0, 18, color, width, true)
	canvas.draw_line(_pt(center, 0.0, -0.38, r), _pt(center, 0.0, 0.55, r), color, width, true)
	canvas.draw_arc(_pt(center, -0.55, 0.05, r), r * 0.6, -1.8, 1.25, 12, color, width * 0.9, true)
	canvas.draw_arc(_pt(center, 0.55, 0.05, r), r * 0.6, 1.89, 4.94, 12, color, width * 0.9, true)


static func _draw_coin(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	canvas.draw_circle(center, r * 0.8, color, false, width, true)
	canvas.draw_circle(center, r * 0.55, Color(color.r, color.g, color.b, color.a * 0.18))
	canvas.draw_line(_pt(center, 0.0, -0.38, r), _pt(center, 0.0, 0.42, r), color, width, true)
	canvas.draw_line(_pt(center, -0.32, -0.18, r), _pt(center, 0.0, 0.12, r), color, width, true)
	canvas.draw_line(_pt(center, 0.32, -0.18, r), _pt(center, 0.0, 0.12, r), color, width, true)


static func _draw_soul(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	var up := PackedVector2Array([
		_pt(center, 0.0, -0.85, r),
		_pt(center, 0.74, 0.43, r),
		_pt(center, -0.74, 0.43, r),
		_pt(center, 0.0, -0.85, r),
	])
	var down := PackedVector2Array([
		_pt(center, 0.0, 0.85, r),
		_pt(center, 0.74, -0.43, r),
		_pt(center, -0.74, -0.43, r),
		_pt(center, 0.0, 0.85, r),
	])
	canvas.draw_polyline(up, color, width * 0.85, true)
	canvas.draw_polyline(down, color, width * 0.85, true)
	canvas.draw_circle(center, r * 0.1, color)


static func _draw_splash(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	canvas.draw_circle(center, r * 0.26, color)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var start := center + Vector2.from_angle(angle) * r * 0.46
		var end := center + Vector2.from_angle(angle) * r * 0.92
		canvas.draw_line(start, end, color, width, true)
		canvas.draw_circle(end, maxf(1.0, width * 0.8), color)


static func _draw_weakness(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	canvas.draw_circle(center, r * 0.82, color, false, width, true)
	canvas.draw_circle(center, r * 0.46, color, false, width * 0.8, true)
	canvas.draw_circle(center, r * 0.12, color)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2.from_angle(angle)
		canvas.draw_line(center + direction * r * 0.92, center + direction * r * 1.18, color, width, true)


static func _draw_crit(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	canvas.draw_colored_polygon(_star(center, r * 0.92, 0.3, 4), color)
	canvas.draw_line(_pt(center, -0.75, 0.75, r), _pt(center, 0.72, -0.72, r), color, width * 1.4, true)


static func _draw_shotgun(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	for i in 3:
		var offset := Vector2(-0.45 + float(i) * 0.45, 0.08 + absf(float(i) - 1.0) * 0.18) * r
		canvas.draw_circle(center + offset, r * 0.19, color)
		canvas.draw_line(center + offset + Vector2(0.0, -r * 0.34), center + offset + Vector2(0.0, -r * 0.62), color, width, true)


static func _draw_luck(
	canvas: CanvasItem, center: Vector2, r: float, color: Color, width: float
) -> void:
	for angle in [-PI * 0.5, 0.0, PI * 0.5, PI]:
		var p := center + Vector2.from_angle(angle) * r * 0.38
		canvas.draw_circle(p, r * 0.31, Color(color.r, color.g, color.b, color.a * 0.9), false, width, true)
	canvas.draw_line(center, _pt(center, 0.22, 0.82, r), color, width, true)
	canvas.draw_circle(center, r * 0.12, color)
