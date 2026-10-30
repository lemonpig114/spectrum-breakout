class_name CombatProfiler
extends RefCounted

## --hotspots 时收集脚本耗时；统计为包含子调用的时间，不能各项直接相加。
static var enabled := OS.get_cmdline_user_args().has("--hotspots")
static var totals := {}
static var counts := {}


static func begin() -> int:
	return Time.get_ticks_usec() if enabled else 0


static func end(label: StringName, started: int) -> void:
	if started == 0:
		return
	totals[label] = int(totals.get(label, 0)) + Time.get_ticks_usec() - started
	counts[label] = int(counts.get(label, 0)) + 1


static func reset() -> void:
	totals.clear()
	counts.clear()


static func report(frames: int) -> void:
	for label in totals:
		print("HOTSPOT %s ms/render_frame=%.3f calls/frame=%.1f" % [label,
			float(totals[label]) / maxf(1.0, frames) / 1000.0,
			float(counts[label]) / maxf(1.0, frames)])
