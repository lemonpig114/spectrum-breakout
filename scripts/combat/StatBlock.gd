class_name StatBlock
extends RefCounted

## 聚合命名属性： (base + flat) * (1 + Σadd%) * Πmult
## 按属性索引修饰器；保留资源引用，动态 value 修改无需缓存失效。
## stat 在加入后不可改名；需要改名时先移除再添加。

var _by_stat: Dictionary = {}
var _base: Dictionary = {}
var _modifiers: Array[StatModifierResource] = []


func set_base(stat: StringName, value: float) -> void:
	_base[stat] = value


func get_base(stat: StringName) -> float:
	return float(_base.get(stat, 0.0))


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
	_by_stat.clear()
	for modifier in _modifiers:
		if not _by_stat.has(modifier.stat):
			_by_stat[modifier.stat] = []
		_by_stat[modifier.stat].append(modifier)


func get_value(stat: StringName) -> float:
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

	return (get_base(stat) + flat) * (1.0 + add_percent) * multiplier


## 仅用于射击时的伤害归因快照，不在每次命中时重算属性。
func get_value_without_source(stat: StringName, source: StringName) -> float:
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
	return (get_base(stat) + flat) * (1.0 + add_percent) * multiplier
