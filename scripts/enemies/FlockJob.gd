extends RefCounted

## WorkerThreadPool任务只读取主线程的不可变数值快照，不接触场景节点或资源。
var positions := PackedVector2Array()
var radii := PackedFloat32Array()
var ids := PackedInt64Array()
var steering := PackedVector2Array()
var corrections := PackedVector2Array()
var cells := {}
const OFFSETS := [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP,
	Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]


func compute() -> void:
	steering.resize(positions.size())
	corrections.resize(positions.size())
	for i in positions.size():
		var key := Vector2i(floori(positions[i].x / 64.0), floori(positions[i].y / 64.0))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	for i in positions.size():
		var center := Vector2i(floori(positions[i].x / 64.0), floori(positions[i].y / 64.0))
		var push := Vector2.ZERO
		var correction := Vector2.ZERO
		var examined := 0
		for offset in OFFSETS:
			var neighbors: Array = cells.get(center + offset, [])
			if neighbors.is_empty():
				continue
			var start := int(ids[i] % neighbors.size())
			for step in mini(neighbors.size(), 20 - examined):
				examined += 1
				var j: int = neighbors[(start + step) % neighbors.size()]
				if j == i:
					continue
				var away := positions[i] - positions[j]
				var minimum := radii[i] + radii[j] + 4.0
				var squared := away.length_squared()
				if squared >= minimum * minimum:
					continue
				if squared < 0.001:
					var first := mini(ids[i], ids[j])
					var second := maxi(ids[i], ids[j])
					var angle := float((first * 31 + second * 17) % 360) * PI / 180.0
					away = Vector2.from_angle(angle if ids[i] == first else angle + PI)
					push += away
					correction += away * minimum * 0.5
				else:
					var distance := sqrt(squared)
					push += away / distance * (1.0 - distance / minimum)
					correction += away / distance * (minimum - distance) * 0.5
			if examined >= 20:
				break
		steering[i] = push.limit_length(1.0) * 5.0
		corrections[i] = correction.limit_length(4.0)
