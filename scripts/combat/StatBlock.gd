class_name StatBlock
extends RefCounted

## 聚合命名属性： (base + flat) * (1 + Σadd%) * Πmult
## 按属性索引修饰器；保留资源引用，动态 value 修改无需缓存失效。
## stat 在加入后不可改名；需要改名时先移除再添加。

var _by_stat: Dictionary = {}
var _base: Dictionary = {}
var _modifiers: Array[StatModifierResource] = []
static var cache_enabled := not OS.get_cmdline_user_args().has("--no-stat-cache")
var _cached := {}
var _cached_without := {}
var _revision := -1


func _invalidate() -> void:
	_cached.clear()
	_cached_without.clear()
	_revision = StatModifierResource.value_revision


func _sync_cache() -> void:
	if _revision != StatModifierResource.value_revision:
		_invalidate()


func set_base(stat: StringName, value: float) -> void:
	_base[stat] = value
	StatModifierResource.value_revision += 1
	_invalidate()


func get_base(stat: StringName) -> float:
	return float(_base.get(stat, 0.0))


func save_data() -> Dictionary:
	var modifiers: Array[Dictionary] = []
	for m in _modifiers:
		modifiers.append({"stat": m.stat, "op": m.op, "value": m.value,
			"priority": m.priority, "source": m.source, "target": m.target})
	return {"base": _base.duplicate(), "modifiers": modifiers}


func restore_data(data: Dictionary) -> void:
	_base = data.get("base", {}).duplicate()
	_modifiers.clear()
	for item in data.get("modifiers", []):
		var m := StatModifierResource.new()
		for key in item:
			m.set(key, item[key])
		_modifiers.append(m)
	_reindex()


func add_modifier(modifier: StatModifierResource) -> void:
	if modifier == null:
		return
	_modifiers.append(modifier)
	_modifiers.sort_custom(func(a, b): return a.priority < b.priority)
	_reindex()


func remove_modifiers_from(source: StringName) -> void:
	var kept: Array[StatModifierResource] = []
	for modifier in _modifiers:
		if modifier.source != source:
			kept.append(modifier)
	_modifiers = kept
	_reindex()


func _reindex() -> void:
	StatModifierResource.value_revision += 1
	_invalidate()
	_by_stat.clear()
	for modifier in _modifiers:
		if not _by_stat.has(modifier.stat):
			_by_stat[modifier.stat] = []
		_by_stat[modifier.stat].append(modifier)


func get_value(stat: StringName) -> float:
	if cache_enabled:
		_sync_cache()
		if _cached.has(stat):
			return _cached[stat]
	var flat := 0.0
	var add_percent := 0.0
	var multiplier := 1.0

	for modifier: StatModifierResource in _by_stat.get(stat, []):
		match modifier.op:
			StatModifierResource.Op.FLAT:
				flat += modifier.value
			StatModifierResource.Op.ADD_PERCENT:
				add_percent += modifier.value
			StatModifierResource.Op.MULTIPLY:
				multiplier *= modifier.value

	var result := (get_base(stat) + flat) * (1.0 + add_percent) * multiplier
	if cache_enabled:
		_cached[stat] = result
	return result


## 仅用于射击时的伤害归因快照，不在每次命中时重算属性。
func get_value_without_source(stat: StringName, source: StringName) -> float:
	if cache_enabled:
		_sync_cache()
		if _cached_without.has(stat) and _cached_without[stat].has(source):
			return _cached_without[stat][source]
	var flat := 0.0
	var add_percent := 0.0
	var multiplier := 1.0
	for modifier: StatModifierResource in _by_stat.get(stat, []):
		if modifier.source == source:
			continue
		match modifier.op:
			StatModifierResource.Op.FLAT:
				flat += modifier.value
			StatModifierResource.Op.ADD_PERCENT:
				add_percent += modifier.value
			StatModifierResource.Op.MULTIPLY:
				multiplier *= modifier.value
	var result := (get_base(stat) + flat) * (1.0 + add_percent) * multiplier
	if cache_enabled:
		if not _cached_without.has(stat):
			_cached_without[stat] = {}
		_cached_without[stat][source] = result
	return result
