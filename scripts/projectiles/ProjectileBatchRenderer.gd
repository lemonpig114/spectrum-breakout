class_name ProjectileBatchRenderer
extends MultiMeshInstance2D

## 普通弹丸只共享画面；Area2D 碰撞、穿透与命中仍由 Projectile 处理。
const CAPACITY := 512
var manager: ProjectileManager


func _ready() -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.use_colors = true
	multi.mesh = _make_mesh()
	multi.instance_count = CAPACITY
	multi.visible_instance_count = 0
	multimesh = multi


func _process(_delta: float) -> void:
	if manager == null:
		return
	if manager._active.size() > multimesh.instance_count:
		multimesh.instance_count = maxi(manager._active.size(), multimesh.instance_count * 2)
	var index := 0
	for projectile in manager._active:
		if not projectile.batch_rendered or not projectile.visible:
			continue
		var transform := projectile.global_transform
		transform.x *= projectile.projectile_size
		transform.y *= projectile.projectile_size
		multimesh.set_instance_transform_2d(index, transform)
		multimesh.set_instance_color(index, RunState.color_of(projectile.color_index))
		index += 1
	multimesh.visible_instance_count = index


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
