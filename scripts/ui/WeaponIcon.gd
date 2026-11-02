class_name WeaponIcon
extends Control

var weapon_id: StringName = &"sword"
const COLORS := {&"sword": Color(0.45, 0.85, 1), &"lightning": Color(1, 0.85, 0.35),
	&"star": Color(1, 0.65, 0.85), &"boomerang": Color(0.55, 1, 0.8),
	&"cannon": Color(1, 0.55, 0.3), &"sprite": Color(0.6, 0.85, 1),
	&"wave": Color(0.35, 0.8, 1), &"scythe": Color(0.8, 0.65, 1)}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(68, 68)


func _draw() -> void:
	var c: Color = COLORS.get(weapon_id, Color.WHITE)
	draw_style_box(_background(c), Rect2(Vector2.ZERO, size))
	draw_set_transform(size * 0.5, 0, Vector2.ONE * minf(size.x, size.y) / 60.0)
	match weapon_id:
		&"sword":
			draw_colored_polygon(PackedVector2Array([Vector2(-10, 8), Vector2(12, -17), Vector2(17, -20), Vector2(16, -12), Vector2(-5, 13)]), c)
			draw_line(Vector2(-14, 4), Vector2(-2, 16), c, 3, true)
			draw_line(Vector2(-8, 11), Vector2(-15, 19), c, 4, true)
		&"lightning":
			draw_colored_polygon(PackedVector2Array([Vector2(4, -22), Vector2(-14, 3), Vector2(-2, 3), Vector2(-7, 22), Vector2(15, -5), Vector2(3, -5)]), c)
		&"star":
			var points := PackedVector2Array()
			for i in 10:
				points.append(Vector2.from_angle(-PI / 2 + i * TAU / 10) * (22 if i % 2 == 0 else 10))
			draw_colored_polygon(points, c)
		&"boomerang":
			draw_polyline(PackedVector2Array([Vector2(-19, 12), Vector2(0, -17), Vector2(19, 12), Vector2(0, -4), Vector2(-19, 12)]), c, 4, true)
		&"cannon":
			draw_circle(Vector2(0, 3), 15, c)
			draw_arc(Vector2(-3, 0), 10, PI, PI * 1.4, 12, Color.WHITE, 2, true)
			draw_polyline(PackedVector2Array([Vector2(6, -10), Vector2(11, -19), Vector2(19, -16)]), c, 2, true)
		&"sprite":
			for i in 3:
				draw_arc(Vector2(-10 - i * 3, 4), 12 + i * 3, -0.8, 1.6, 16, Color(c, 0.2 + i * 0.15), 2, true)
			draw_circle(Vector2(9, -4), 7, c)
			draw_circle(Vector2(10, -5), 3, Color.WHITE)
		&"wave":
			for i in 3:
				var points := PackedVector2Array()
				for j in 25:
					var x := -22 + j * 44.0 / 24
					points.append(Vector2(x, sin(x * 0.15 + i) * 4 + (i - 1) * 11))
				draw_polyline(points, Color(c, 1 - i * 0.2), 2, true)
		&"scythe":
			draw_line(Vector2(11, -15), Vector2(-12, 22), c, 3, true)
			var blade := PackedVector2Array()
			for i in 20:
				blade.append(Vector2(-2, -3) + Vector2.from_angle(-2.8 + i * 2.5 / 19) * 21)
			for i in range(19, -1, -1):
				blade.append(Vector2(1, -1) + Vector2.from_angle(-2.8 + i * 2.5 / 19) * 15)
			draw_colored_polygon(blade, c)
	draw_set_transform(Vector2.ZERO)


func _background(c: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(c * 0.1, 0.9)
	style.border_color = Color(c, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style
