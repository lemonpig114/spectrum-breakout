extends RefCounted

## Godot 2D+Color实例格式：两行变换各4浮点，再接RGBA；一次上传整个批次。
var multi: MultiMesh
var canvas: MultiMeshInstance2D
var data := PackedFloat32Array()
var bulk := not OS.get_cmdline_user_args().has("--scalar-multimesh")


func _init(value: MultiMesh, owner_canvas: MultiMeshInstance2D) -> void:
	multi = value
	canvas = owner_canvas
	data.resize(multi.instance_count * 12)


func write(index: int, transform: Transform2D, color: Color) -> void:
	if not bulk:
		multi.set_instance_transform_2d(index, transform)
		multi.set_instance_color(index, color)
		return
	if data.size() != multi.instance_count * 12:
		data.resize(multi.instance_count * 12)
	var at := index * 12
	data[at] = transform.x.x
	data[at + 1] = transform.y.x
	data[at + 3] = transform.origin.x
	data[at + 4] = transform.x.y
	data[at + 5] = transform.y.y
	data[at + 7] = transform.origin.y
	data[at + 8] = color.r
	data[at + 9] = color.g
	data[at + 10] = color.b
	data[at + 11] = color.a


func flush(visible: int) -> void:
	if bulk and visible > 0:
		multi.buffer = data
	multi.visible_instance_count = visible
	# MultiMesh.buffer does not emit Resource.changed in Godot 4.4.1. Without
	# this notification CanvasItem keeps its old visibility rect and may cull
	# the entire moving batch, even while its live instances are onscreen.
	# Refresh once per rendered frame, never once per instance/physics substep.
	canvas.queue_redraw()
