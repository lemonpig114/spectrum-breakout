class_name EnemyBatchRenderer
extends Node2D

## 普通多边形怪共用三种小网格；AI、碰撞和血条仍由 Enemy 负责。
const CAPACITY := 256
const SHAPES := [3, 4, 6]
var _batches: Dictionary = {}


func _ready() -> void:
	add_to_group(&"enemy_batch_renderer")
	for sides in SHAPES:
		var mesh := _make_mesh(sides)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_2D
		multi.use_colors = true
		multi.mesh = mesh
		multi.instance_count = CAPACITY
		multi.visible_instance_count = 0
		var node := MultiMeshInstance2D.new()
		node.multimesh = multi
		add_child(node)
		_batches[sides] = multi


func _process(_delta: float) -> void:
	var lists := {3: [], 4: [], 6: []}
	for item in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := item as Enemy
		if enemy == null or not enemy.batch_rendered or not enemy.visible:
			continue
		var sides := enemy.type_data.sides
		if lists.has(sides):
			lists[sides].append(enemy)
	for sides in SHAPES:
		var multi: MultiMesh = _batches[sides]
		var enemies: Array = lists[sides]
		if enemies.size() > multi.instance_count:
			multi.instance_count = maxi(enemies.size(), multi.instance_count * 2)
		multi.visible_instance_count = enemies.size()
		for i in enemies.size():
			var enemy: Enemy = enemies[i]
			var transform := enemy.global_transform
			transform.x *= enemy.radius
			transform.y *= enemy.radius
			multi.set_instance_transform_2d(i, transform)
			var color := RunState.color_of(enemy.color_index)
			multi.set_instance_color(i, Color(color.r * enemy.modulate.r,
				color.g * enemy.modulate.g, color.b * enemy.modulate.b, enemy.modulate.a))


func _make_mesh(sides: int) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var points := PackedVector2Array()
	for i in sides:
		points.append(Vector2.from_angle(TAU * float(i) / float(sides)))
	for i in sides:
		_add_triangle(vertices, colors, Vector2.ZERO, points[i], points[(i + 1) % sides], 0.12)
	for i in sides:
		var a := points[i]
		var b := points[(i + 1) % sides]
		var normal := (b - a).orthogonal().normalized() * 0.075
		_add_triangle(vertices, colors, a - normal, b - normal, b + normal, 1.0)
		_add_triangle(vertices, colors, a - normal, b + normal, a + normal, 1.0)
	# 中心亮点也归入批次，免去每只怪额外绘制命令。
	for i in 8:
		var a := Vector2.from_angle(TAU * float(i) / 8.0) * 0.19
		var b := Vector2.from_angle(TAU * float(i + 1) / 8.0) * 0.19
		_add_triangle(vertices, colors, Vector2.ZERO, a, b, 0.9)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_triangle(vertices: PackedVector2Array, colors: PackedColorArray,
		a: Vector2, b: Vector2, c: Vector2, brightness: float) -> void:
	vertices.append_array(PackedVector2Array([a, b, c]))
	var tint := Color(brightness, brightness, brightness)
	colors.append_array(PackedColorArray([tint, tint, tint]))
