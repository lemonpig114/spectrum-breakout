extends Node
## 相同修饰器和查询序列，对比原全量扫描与属性索引；不代表整局 FPS。
func _ready() -> void:
	var stats := StatBlock.new()
	var catalog := SkillCatalog.build()
	for skill in catalog:
		for modifier in skill.modifiers:
			stats.add_modifier(modifier)
	var fields: Array[StringName] = [&"damage", &"damage_mult", &"fire_rate_mult", &"projectile_speed", &"crit_chance", &"move_speed"]
	var sum_old := 0.0
	var sum_new := 0.0
	var start := Time.get_ticks_usec()
	for i in 30000:
		sum_old += scan(stats, fields[i % fields.size()])
	var old_us := Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	for i in 30000:
		sum_new += stats.get_value(fields[i % fields.size()])
	var new_us := Time.get_ticks_usec() - start
	print("STAT BENCH scan_us=%d indexed_us=%d speedup=%.2fx equal=%s modifiers=%d" % [old_us, new_us, float(old_us) / maxf(1, new_us), is_equal_approx(sum_old, sum_new), stats._modifiers.size()])
	get_tree().quit(0 if is_equal_approx(sum_old, sum_new) else 1)

func scan(stats: StatBlock, stat: StringName) -> float:
	var flat := 0.0
	var add := 0.0
	var mult := 1.0
	for modifier in stats._modifiers:
		if modifier.stat != stat:
			continue
		match modifier.op:
			StatModifierResource.Op.FLAT: flat += modifier.value
			StatModifierResource.Op.ADD_PERCENT: add += modifier.value
			StatModifierResource.Op.MULTIPLY: mult *= modifier.value
	return (stats.get_base(stat) + flat) * (1.0 + add) * mult
