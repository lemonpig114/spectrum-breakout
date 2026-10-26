class_name ModifierPipeline
extends RefCounted

## 行为修改器管道。M0 只搭骨架并预留阶段；
## 后续技能/遗物通过 add() 挂载回调，按 priority + 插入顺序稳定执行。

enum Stage {
	ON_FIRE,
	ON_SPAWN,
	ON_TRAVEL_TICK,
	ON_HIT,
	ON_KILL,
	ON_EXPIRE,
}

var _entries: Array[Dictionary] = []


func add(stage: int, callback: Callable, priority: int = 0, source: StringName = &"") -> void:
	if not callback.is_valid():
		return
	_entries.append({
		"stage": stage,
		"callback": callback,
		"priority": priority,
		"source": source,
	})
	_entries.sort_custom(func(a, b): return a.priority < b.priority)


func run(stage: int, context) -> void:
	for entry in _entries:
		if entry.stage == stage:
			var callback: Callable = entry.callback
			if callback.is_valid():
				callback.call(context)


func clear_source(source: StringName) -> void:
	var kept: Array[Dictionary] = []
	for entry in _entries:
		if entry.source != source:
			kept.append(entry)
	_entries = kept
