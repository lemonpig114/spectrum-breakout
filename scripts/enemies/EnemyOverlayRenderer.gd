class_name EnemyOverlayRenderer
extends Node2D

## 血条、状态图标及六边形护盾共用七个MultiMesh；原节点只保留状态与跳动计时。
var batches := {}
var counts := {}
var _writers := {}
const TYPES := [&"back", &"fill", &"burn", &"poison", &"ice", &"fragile", &"rally"]


func _ready() -> void:
	add_to_group(&"enemy_overlay_renderer")
	z_index = 9
	for kind in TYPES:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_2D
		multi.use_colors = true
		multi.mesh = _make_mesh(kind)
		multi.instance_count = 256
		multi.visible_instance_count = 0
		var node := MultiMeshInstance2D.new()
		node.multimesh = multi
		add_child(node)
		batches[kind] = multi
		_writers[kind] = preload("res://scripts/fx/InstanceBatch.gd").new(multi, node)


func _process(_delta: float) -> void:
	for kind in TYPES:
		counts[kind] = 0
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead or not enemy.visible:
			continue
		var bar := enemy._healthbar
		if bar == null or not bar.visible or not bar.batched:
			continue
		var center := enemy.global_position
		if enemy._hex_rally_time > 0.0:
			var pulse := 0.72 + sin(RunState.elapsed * 9.0) * 0.2
			_add(&"rally", Transform2D(enemy._visual_angle, Vector2.ONE * (enemy.radius + 7.0), 0.0, center),
				Color(1.0, 1.0, 1.0, pulse * minf(1.0, enemy._hex_rally_time)))
		if bar.current > 0.0 and bar.current < bar.maximum:
			var width := bar.body_radius * 2.0
			var at := center + Vector2(-width * 0.5, -bar.body_radius - 8.0)
			_add(&"back", Transform2D(0.0, Vector2(width, 2.0), 0.0, at), Color(1, 1, 1, 0.18))
			_add(&"fill", Transform2D(0.0, Vector2(width * bar.current / bar.maximum, 2.0), 0.0, at), Color(bar.tint.r, bar.tint.g, bar.tint.b, 0.9))
		var kinds: Array[StringName] = []
		var pulses: Array[float] = []
		if bar.burn or bar._burn_pulse > 0.0:
			kinds.append(&"burn")
			pulses.append(bar._burn_pulse)
		if bar.poison or bar._poison_pulse > 0.0:
			kinds.append(&"poison")
			pulses.append(bar._poison_pulse)
		if bar.ice or bar._ice_pulse > 0.0:
			kinds.append(&"ice")
			pulses.append(bar._ice_pulse)
		if bar.fragile:
			kinds.append(&"fragile")
			pulses.append(0.0)
		for i in kinds.size():
			var progress := pulses[i] / EnemyHealthBar.PULSE_TIME
			var at := center + Vector2(-float(kinds.size() - 1) * 6.5 + i * 13.0, bar.body_radius + 10.0 - 3.0 * progress)
			_add(kinds[i], Transform2D(0.0, Vector2.ONE * (1.0 + progress * 0.22), 0.0, at), Color.WHITE)
	for kind in TYPES:
		_writers[kind].flush(counts[kind])


func _add(kind: StringName, transform: Transform2D, tint: Color) -> void:
	if kind not in [&"back", &"fill"]:
		tint = Color(tint.r * 3.0, tint.g * 3.0, tint.b * 3.0, tint.a)
	var multi: MultiMesh = batches[kind]
	var i: int = counts[kind]
	if i >= multi.instance_count:
		# Rare overflow: grow without rebuilding on every frame.
		multi.instance_count *= 2
	_writers[kind].write(i, transform, tint)
	counts[kind] = i + 1


func _polygon(vertices: PackedVector2Array, colors: PackedColorArray, points: PackedVector2Array, color: Color) -> void:
	var triangles := Geometry2D.triangulate_polygon(points)
	for index in triangles:
		vertices.append(points[index])
		colors.append(color)


func _line(vertices: PackedVector2Array, colors: PackedColorArray, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var side := (b - a).orthogonal().normalized() * width * 0.5
	_polygon(vertices, colors, PackedVector2Array([a + side, b + side, b - side, a - side]), color)


func _make_mesh(kind: StringName) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	if kind == &"rally":
		for i in 6:
			var a := Vector2.from_angle(i * TAU / 6.0)
			var b := Vector2.from_angle((i + 1) * TAU / 6.0)
			_line(vertices, colors, a, b, 0.055, Color(0.5, 1.5, 2.6, 0.9))
			_line(vertices, colors, a * 1.1, a * 1.26, 0.04, Color(0.9, 1.7, 2.7, 0.8))
	elif kind in [&"back", &"fill"]:
		_polygon(vertices, colors, PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]), Color.WHITE)
	else:
		_polygon(vertices, colors, PackedVector2Array([Vector2(-5.5, -5.5), Vector2(5.5, -5.5), Vector2(5.5, 5.5), Vector2(-5.5, 5.5)]), Color(0.015, 0.025, 0.055, 0.78))
		match kind:
			&"burn":
				_polygon(vertices, colors, PackedVector2Array([Vector2(-3.5, 4), Vector2(-2.5, -1), Vector2(0, -5), Vector2(1, 0), Vector2(3, -2), Vector2(3.5, 4)]), Color(2.5, 0.65, 0.2, 0.95))
			&"poison":
				for circle in [Vector3(-2, -1.5, 1.8), Vector3(2, 1.5, 2.5)]:
					var points := PackedVector2Array()
					for i in 12:
						points.append(Vector2(circle.x, circle.y) + Vector2.from_angle(i * TAU / 12.0) * circle.z)
					_polygon(vertices, colors, points, Color(0.45, 2.2, 0.6, 0.95))
			&"ice":
				var color := Color(0.5, 1.55, 2.6, 0.95)
				_line(vertices, colors, Vector2(-4, 0), Vector2(4, 0), 1.4, color)
				_line(vertices, colors, Vector2(0, -4), Vector2(0, 4), 1.4, color)
				_line(vertices, colors, Vector2(-3, -3), Vector2(3, 3), 1.0, color)
				_line(vertices, colors, Vector2(-3, 3), Vector2(3, -3), 1.0, color)
			&"fragile":
				var color := Color(1.7, 0.55, 1.25, 0.95)
				_line(vertices, colors, Vector2(-3, -4), Vector2(1, -1), 1.5, color)
				_line(vertices, colors, Vector2(1, -1), Vector2(-1, 1), 1.5, color)
				_line(vertices, colors, Vector2(-1, 1), Vector2(3, 4), 1.5, color)
	var arrays := []
	if kind not in [&"back", &"fill"]:
		for i in colors.size():
			colors[i] = Color(colors[i].r / 3.0, colors[i].g / 3.0, colors[i].b / 3.0, colors[i].a)
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
