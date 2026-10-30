extends Polygon2D

## 由 WeaponCombat 复用，纯顶点颜色形成渐细、渐隐的刀气带。
func update_sweep(center: Vector2, angle: float, radius: float,
		progress: float, tint: Color, reverse: bool) -> void:
	position = center
	self_modulate = tint
	var points := PackedVector2Array()
	var inner := PackedVector2Array()
	var colors := PackedColorArray()
	var inner_colors := PackedColorArray()
	var sign_value := -1.0 if reverse else 1.0
	var span := minf(2.1, progress * TAU)
	var fade := 1.0 - smoothstep(0.72, 1.0, progress)
	for i in 21:
		var t := float(i) / 20.0
		var a := angle - sign_value * span * (1.0 - t)
		var width := sin(PI * t) * 24.0
		points.append(Vector2.from_angle(a) * (radius + width * 0.2))
		inner.append(Vector2.from_angle(a) * (radius - width))
		colors.append(Color(1.0, 1.0, 1.0, 0.50 * t * fade))
		inner_colors.append(Color(1.0, 1.0, 1.0, 0.035 * t * fade))
	for i in range(20, -1, -1):
		points.append(inner[i])
		colors.append(inner_colors[i])
	polygon = points
	vertex_colors = colors
