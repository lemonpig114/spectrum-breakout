extends Node

## 手动试玩采样：--profile 启用；每秒写一行，异常退出也可读到此前记录。
var _main: Node
var _file: FileAccess
var _elapsed := 0.0
var _frames := 0
var _fps_sum := 0.0
var _fps_min := INF
var _frame_max_ms := 0.0
var _process_sum := 0.0
var _physics_sum := 0.0
var _process_max := 0.0
var _physics_max := 0.0


func setup(main: Node) -> void:
	_main = main
	var path := "user://performance_session.csv"
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("无法创建性能日志：%s" % path)
		return
	_file.store_line("run_s,avg_fps,min_fps,max_frame_ms,process_ms,process_max_ms,physics_ms,physics_max_ms,static_mb,nodes,resources,enemies,projectiles,pickups,fx_children,bursts,sparks,shards")
	_file.flush()
	print("PERFORMANCE LOG: ", ProjectSettings.globalize_path(path))


func _process(delta: float) -> void:
	if _file == null or not RunState.is_running or get_tree().paused:
		return
	if delta <= 0.0:
		return
	_elapsed += delta
	_frames += 1
	var fps := 1.0 / delta
	_fps_sum += fps
	_fps_min = minf(_fps_min, fps)
	_frame_max_ms = maxf(_frame_max_ms, delta * 1000.0)
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_process_sum += process_ms
	_physics_sum += physics_ms
	_process_max = maxf(_process_max, process_ms)
	_physics_max = maxf(_physics_max, physics_ms)
	if _elapsed < 1.0:
		return
	var enemies := get_tree().get_nodes_in_group(&"enemies").size()
	var projectiles := 0
	var pickups := 0
	var fx_children := 0
	if is_instance_valid(_main):
		if is_instance_valid(_main.projectile_manager):
			projectiles = _main.projectile_manager._active.size()
		if is_instance_valid(_main.fx_layer):
			fx_children = _main.fx_layer.get_child_count()
		var pickup_field := _main.get_node_or_null("World/PickupField") as PickupField
		if pickup_field != null:
			pickups = pickup_field.total_count()
	_file.store_csv_line(PackedStringArray([
		"%.1f" % RunState.elapsed,
		"%.1f" % (_fps_sum / float(_frames)),
		"%.1f" % _fps_min,
		"%.1f" % _frame_max_ms,
		"%.2f" % (_process_sum / float(_frames)),
		"%.2f" % _process_max,
		"%.2f" % (_physics_sum / float(_frames)),
		"%.2f" % _physics_max,
		"%.1f" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
		str(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))),
		str(int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))),
		str(enemies), str(projectiles), str(pickups), str(fx_children),
		str(FX._burst_count), str(FX._spark_count), str(FX._shard_count),
	]))
	_file.flush()
	_elapsed = 0.0
	_frames = 0
	_fps_sum = 0.0
	_fps_min = INF
	_frame_max_ms = 0.0
	_process_sum = 0.0
	_physics_sum = 0.0
	_process_max = 0.0
	_physics_max = 0.0
