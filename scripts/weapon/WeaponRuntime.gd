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


func _init(core_resource: WeaponCoreResource = null) -> void:
	if core_resource != null:
		set_core(core_resource)


func set_core(core_resource: WeaponCoreResource) -> void:
	core = core_resource
	stats = StatBlock.new()
	if core == null:
		return

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
	if primary_form == &"":
		primary_form = id
	return true


func select_primary(id: StringName) -> bool:
	if not owned_forms.has(id):
		return false
	primary_form = id
	return true


func has_form(id: StringName) -> bool:
	return owned_forms.has(id)


func primary_data() -> WeaponTraitResource:
	return ContentDB.get_data(primary_form) as WeaponTraitResource


func get_stat(stat_name: StringName) -> float:
	return stats.get_value(stat_name)


func get_final_damage() -> float:
	return stats.get_value(&"damage") * stats.get_value(&"damage_mult") * stats.get_value(&"damage_final")


func get_final_fire_rate() -> float:
	return stats.get_value(&"fire_rate") * stats.get_value(&"fire_rate_mult") * stats.get_value(&"fire_rate_final")
