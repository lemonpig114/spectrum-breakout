class_name ProjectileBatchRenderer
extends MultiMeshInstance2D

## 普通弹丸只共享画面；Area2D 碰撞、穿透与命中仍由 Projectile 处理。
const CAPACITY := 512
var manager: ProjectileManager
var _star_batch: MultiMeshInstance2D
var _sprite_batch: MultiMeshInstance2D
var _writers: Array[RefCounted] = []


func _ready() -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.use_colors = true
	multi.mesh = _make_mesh()
	multi.instance_count = CAPACITY
	multi.visible_instance_count = 0
	multimesh = multi
	var star_multi := MultiMesh.new()
	star_multi.transform_format = MultiMesh.TRANSFORM_2D
	star_multi.use_colors = true
	star_multi.mesh = _make_star_mesh()
	star_multi.instance_count = CAPACITY
	star_multi.visible_instance_count = 0
	_star_batch = MultiMeshInstance2D.new()
	_star_batch.multimesh = star_multi
	add_child(_star_batch)
	var sprite_multi := MultiMesh.new()
	sprite_multi.transform_format = MultiMesh.TRANSFORM_2D
	sprite_multi.use_colors = true
	sprite_multi.mesh = _make_sprite_mesh()
	sprite_multi.instance_count = CAPACITY
	sprite_multi.visible_instance_count = 0
	_sprite_batch = MultiMeshInstance2D.new()
	_sprite_batch.multimesh = sprite_multi
	add_child(_sprite_batch)
	for node in [self, _star_batch, _sprite_batch]:
		_writers.append(preload("res://scripts/fx/InstanceBatch.gd").new(node.multimesh, node))


func _process(_delta: float) -> void:
	if manager == null:
		return
	if manager._active.size() > multimesh.instance_count:
		multimesh.instance_count = maxi(manager._active.size(), multimesh.instance_count * 2)
	if manager._active.size() > _star_batch.multimesh.instance_count:
		_star_batch.multimesh.instance_count = maxi(manager._active.size(), _star_batch.multimesh.instance_count * 2)
	if manager._active.size() > _sprite_batch.multimesh.instance_count:
		_sprite_batch.multimesh.instance_count = maxi(manager._active.size(), _sprite_batch.multimesh.instance_count * 2)
	var index := 0
	var star_index := 0
	var sprite_index := 0
	for projectile in manager._active:
		if not projectile.batch_rendered or not projectile.visible:
			continue
		var transform := projectile.global_transform
		transform.x *= projectile.projectile_size
		transform.y *= projectile.projectile_size
		if projectile.batch_sprite:
			_writers[2].write(sprite_index, transform, RunState.color_of(projectile.color_index))
			sprite_index += 1
		elif projectile.batch_star:
			_writers[1].write(star_index, transform, RunState.color_of(projectile.color_index))
			star_index += 1
		else:
			_writers[0].write(index, transform, RunState.color_of(projectile.color_index))
			index += 1
	_writers[0].flush(index)
	_writers[1].flush(star_index)
	_writers[2].flush(sprite_index)


func _make_sprite_mesh() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for i in 12:
		var a := Vector2.from_angle(TAU * float(i) / 12.0)
		var b := Vector2.from_angle(TAU * float(i + 1) / 12.0)
		_add_triangle(vertices, colors, Vector2.ZERO, a * 1.0, b * 1.0,
			Color(1.0, 1.0, 1.0, 0.14), Color(1.0, 1.0, 1.0, 0.0))
		_add_triangle(vertices, colors, Vector2.ZERO, a * 0.58, b * 0.58,
			Color.WHITE, Color.WHITE)
	for i in 8:
		var a := Vector2.from_angle(TAU * float(i) / 8.0) * 0.23
		var b := Vector2.from_angle(TAU * float(i + 1) / 8.0) * 0.23
		_add_triangle(vertices, colors, Vector2.ZERO, a, b,
			Color(2.0, 2.0, 2.0), Color(2.0, 2.0, 2.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_star_mesh() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for i in 10:
		var a := Vector2.from_angle(TAU * float(i) / 10.0) * (1.75 if i % 2 == 0 else 0.75)
		var b := Vector2.from_angle(TAU * float(i + 1) / 10.0) * (1.75 if (i + 1) % 2 == 0 else 0.75)
		_add_triangle(vertices, colors, Vector2.ZERO, a, b, Color.WHITE, Color.WHITE)
	for i in 8:
		var a := Vector2.from_angle(TAU * float(i) / 8.0) * 0.36
		var b := Vector2.from_angle(TAU * float(i + 1) / 8.0) * 0.36
		_add_triangle(vertices, colors, Vector2.ZERO, a, b,
			Color(2.5, 2.5, 2.5), Color(2.5, 2.5, 2.5))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_mesh() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	# 用顶点透明度做小光晕，省掉每发子弹的贴图绘制命令。
	for i in 12:
		var a := Vector2.from_angle(TAU * float(i) / 12.0) * 2.6
		var b := Vector2.from_angle(TAU * float(i + 1) / 12.0) * 2.6
		_add_triangle(vertices, colors, Vector2.ZERO, a, b,
			Color(0.65, 0.65, 0.65, 0.30), Color(0.65, 0.65, 0.65, 0.0))
	_add_triangle(vertices, colors, Vector2(0.5, 0.0), Vector2(-1.0, 0.65),
		Vector2(-6.5, 0.0), Color(1.0, 1.0, 1.0, 0.28), Color(1.0, 1.0, 1.0, 0.0))
	_add_triangle(vertices, colors, Vector2(0.5, 0.0), Vector2(-6.5, 0.0),
		Vector2(-1.0, -0.65), Color(1.0, 1.0, 1.0, 0.28), Color(1.0, 1.0, 1.0, 0.0))
	_add_triangle(vertices, colors, Vector2(1.8, 0.0), Vector2(0.0, 1.0),
		Vector2(-0.6, 0.0), Color.WHITE, Color.WHITE)
	_add_triangle(vertices, colors, Vector2(1.8, 0.0), Vector2(-0.6, 0.0),
		Vector2(0.0, -1.0), Color.WHITE, Color.WHITE)
	for i in 8:
		var a := Vector2.from_angle(TAU * float(i) / 8.0) * 0.42
		var b := Vector2.from_angle(TAU * float(i + 1) / 8.0) * 0.42
		_add_triangle(vertices, colors, Vector2.ZERO, a, b,
			Color(2.5, 2.5, 2.5), Color(2.5, 2.5, 2.5))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_triangle(vertices: PackedVector2Array, colors: PackedColorArray,
		a: Vector2, b: Vector2, c: Vector2, inner: Color, outer: Color) -> void:
	vertices.append_array(PackedVector2Array([a, b, c]))
	colors.append_array(PackedColorArray([inner, outer, outer]))
