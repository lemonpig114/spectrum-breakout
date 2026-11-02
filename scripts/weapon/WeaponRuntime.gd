class_name WeaponRuntime
extends RefCounted

## 运行时武器：Core + Traits + StatBlock + 管道。
## Resource 本身保持只读，运行时修改都发生在这里。

var core: WeaponCoreResource
var stats := StatBlock.new()
var pipeline := ModifierPipeline.new()
var traits: Array[WeaponTraitResource] = []
var owned_forms: Array[StringName] = []
var primary_form: StringName = &""
var _is_snapshot := false
var _snapshot_cache: WeaponRuntime
var _snapshot_key := 0
const PRIMARY_ORDER: Array[StringName] = [&"sword", &"scythe", &"wave", &"boomerang",
	&"sprite", &"star", &"lightning", &"cannon"]


func _init(core_resource: WeaponCoreResource = null) -> void:
	if core_resource != null:
		set_core(core_resource)


func set_core(core_resource: WeaponCoreResource) -> void:
	core = core_resource
	stats = StatBlock.new()
	if core == null:
		return

	stats.set_base(&"range", 600.0)
	stats.set_base(&"range_mult", 1.0)
	stats.set_base(&"damage", core.damage)
	stats.set_base(&"fire_rate", core.fire_rate)
	stats.set_base(&"projectile_speed", core.projectile_speed)
	stats.set_base(&"projectile_size", core.projectile_size)
	stats.set_base(&"projectile_lifetime", core.projectile_lifetime)
	stats.set_base(&"projectiles_per_shot", core.projectiles_per_shot)
	stats.set_base(&"spread_degrees", core.spread_degrees)
	stats.set_base(&"pierce", core.pierce)

	# 技能树把“基础值 / 伤害倍率 / 最终倍率”分成三层：
	# (base + flat) * damage_mult * damage_final
	stats.set_base(&"damage_mult", 1.0)
	stats.set_base(&"damage_final", 1.0)
	stats.set_base(&"fire_rate_mult", 1.0)
	stats.set_base(&"fire_rate_final", 1.0)


func add_trait(weapon_trait: WeaponTraitResource) -> void:
	if weapon_trait != null and not traits.has(weapon_trait):
		traits.append(weapon_trait)


func acquire_form(id: StringName) -> bool:
	if owned_forms.has(id):
		return false
	var weapon_trait := ContentDB.get_data(id) as WeaponTraitResource
	if weapon_trait == null:
		return false
	owned_forms.append(id)
	add_trait(weapon_trait)
	refresh_primary()
	return true


func remove_form(id: StringName) -> bool:
	if not owned_forms.has(id):
		return false
	owned_forms.erase(id)
	var weapon_trait := ContentDB.get_data(id) as WeaponTraitResource
	if weapon_trait != null:
		traits.erase(weapon_trait)
	refresh_primary()
	return true


func refresh_primary() -> void:
	if owned_forms.has(primary_form):
		return
	primary_form = &""
	for id in PRIMARY_ORDER:
		if owned_forms.has(id):
			primary_form = id
			return


func select_primary(id: StringName) -> bool:
	if not owned_forms.has(id):
		return false
	primary_form = id
	return true


static func secondary_description(id: StringName) -> String:
	return {&"sword": "武器倍率+20%", &"scythe": "按主武器25%攻速额外斩击，仅继承技能",
		&"lightning": "命中触发闪电链", &"wave": "命中追加两段20%伤害",
		&"boomerang": "攻击向外延伸后折返", &"star": "命中分裂五颗20%短程星片",
		&"cannon": "额外40%溅射；已有溅射时倍率+20%、范围+40%",
		&"sprite": "射程+50%，获得追踪；弹体最多2秒，高压1秒"}.get(id, "")


func has_secondary(id: StringName) -> bool:
	return id != primary_form and has_form(id)


func attack_snapshot(isolated := false) -> WeaponRuntime:
	if _is_snapshot and not isolated: return self
	var key := hash(owned_forms) ^ hash(primary_form) ^ stats.get_instance_id()
	if not isolated and _snapshot_cache != null and key == _snapshot_key: return _snapshot_cache
	var result := WeaponRuntime.new()
	result._is_snapshot = true
	result.core = core
	result.stats = stats
	result.primary_form = primary_form
	result.owned_forms.assign([primary_form] if isolated else owned_forms)
	result.traits.assign(traits)
	if not isolated:
		_snapshot_cache = result
		_snapshot_key = key
	return result


func has_form(id: StringName) -> bool:
	return owned_forms.has(id)


func primary_data() -> WeaponTraitResource:
	return ContentDB.get_data(primary_form) as WeaponTraitResource


## 射程点数600为基准，各形态映射为实际距离；与弹体大小独立。
func attack_range(form: StringName = &"", heavy := false) -> float:
	var id := primary_form if form == &"" else form
	var bases := {&"sword": 150.0, &"scythe": 130.0, &"wave": 240.0,
		&"lightning": 280.0, &"boomerang": 340.0, &"sprite": 450.0,
		&"cannon": 300.0, &"star": 600.0}
	# 旧存档没有射程字段，按原始基准恢复。
	var value := stats.get_value(&"range") if stats._base.has(&"range") else 600.0
	var multiplier := stats.get_value(&"range_mult") if stats._base.has(&"range_mult") else 1.0
	var result := float(bases.get(id, 600.0)) * maxf(0.0, value / 600.0) * maxf(0.0, multiplier)
	if id != &"sprite" and has_form(&"sprite"):
		result *= 1.5
	return result * (3.0 if heavy else 1.0)


func get_stat(stat_name: StringName) -> float:
	return stats.get_value(stat_name)


func get_final_damage() -> float:
	return stats.get_value(&"damage") * stats.get_value(&"damage_mult") * stats.get_value(&"damage_final")


func get_final_fire_rate() -> float:
	return stats.get_value(&"fire_rate") * stats.get_value(&"fire_rate_mult") * stats.get_value(&"fire_rate_final")
