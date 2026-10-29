extends Node

## 局内技能树运行时。
##
## - 维护 76 个技能节点（19 线 × 4 阶）与解锁状态：1 阶无前置；2/3 阶需要 1 阶；
##   4 阶需要 2、3 阶都点亮。
## - 普通数值写入武器/player 的 StatBlock；特殊能力在这里结算。
## - 恶魔/天使线互斥：2 阶决定契约阵营，本侧遗物才会进入商店；3 阶解锁地面祭坛。
## - 商店直接结算；宝箱/技能/祭坛随机奖励先进入待选队列，确认后生效。

const CATALOG := preload("res://scripts/skills/SkillCatalog.gd")

const BASE_CRIT_CHANCE := 0.0
const BASE_CRIT_DAMAGE := 1.5
const BASE_WEAKNESS := 1.5
const SPLASH_BASE_RADIUS := 80.0
const SOUL_BASE_RADIUS := 180.0
const ARROW_RELICS := [
	[&"rare_poison_arrow", ColorType.GREEN, &"arrow_poison"],
	[&"rare_frost_arrow", ColorType.BLUE, &"arrow_frost"],
	[&"rare_burning_arrow", ColorType.RED, &"arrow_burning"],
]

## 商店基础 4 格，每次捐款升级 +1 格；最多 14 格（遗物池的实际上限）。
const SHOP_BASE_SLOTS := 4
const SHOP_MAX_SLOTS := 14
## 商人基础间隔 90 秒；第一只固定 1:20 出现（见 Director）。
const MERCHANT_BASE_INTERVAL := 90.0

var nodes: Array[SkillNodeResource] = []
var relics: Array[RelicResource] = []
var unlocked: Dictionary = {}
var owned_relics: Array[RelicResource] = []
## 实际伤害按造成的生命损失统计；属性增伤另列单项移除估算，不能相加。
var damage_totals: Dictionary = {}
var damage_bonus_estimates: Dictionary = {}
## 自动奖励只进入待选队列，确认后才生效。票号跨局递增，旧面板不能结算新奖励。
var pending_relic_offers: Array[Dictionary] = []
var _offer_serial := 0
var player: Player
## 本局商店等级：0 = 基础四格；每次捐款升级 +1（货架 +1 格、品质提高）。
var shop_level := 0
var shop_purchases := 0
var shop_rerolls := 0

var soul_kills := 0

var _by_id: Dictionary = {}
var _soul_timer := 0.0
## 二阶每消耗一点能量产生一个独立五秒层数，后续消耗不会刷新旧层。
var _energy_buff_timers: Array[float] = []
var _energy_buff_mod: StatModifierResource
var _energy_rate_mod: StatModifierResource
var _speed_rate_mod: StatModifierResource
var _giant_damage_mod: StatModifierResource
var _giant_size_mod: StatModifierResource
var _giant_kills := 0
var _pointed_damage_mod: StatModifierResource
var _pointed_rate_mod: StatModifierResource
var guardian_shields := 0
## 护盾发生器只保护生成时的颜色；独立于守护层数，不在 HUD 显示。
var color_shield := -1
var _travel_distance := 0.0
var _revolver_volleys: Array[Dictionary] = []
## 锦鲤：发现地面宝箱即获得临时幸运，刷新而不叠加。
var _temp_luck := 0.0
var _temp_luck_time := 0.0
## 肾上腺素：受伤后 20 秒线性衰减的伤害/射速增益。
var _adrenaline_time := 0.0
var _adrenaline_damage_mod: StatModifierResource
var _adrenaline_rate_mod: StatModifierResource
## 命运骰子：每 10 秒重掷一次，结果写入三个动态修改器。
var _dice_time := 0.0
var _dice_roll := 0
var _dice_damage_mod: StatModifierResource
var _dice_rate_mod: StatModifierResource
var _dice_crit_mod: StatModifierResource
## 每个遗物实例的修改器 source 都用独立序号，重复拾取叠加时不会互相覆盖。
var _relic_source_serial := 0

## 调试开关：启动参数 `-- --force-super-crit` 让所有命中强制超暴击，
## 便于在没有刷到暴击 4 阶时检查数字表现。
var debug_force_super_crit := false


func _ready() -> void:
	debug_force_super_crit = OS.get_cmdline_user_args().has("--force-super-crit")
	if debug_force_super_crit:
		print("SKILLS debug: every hit is a super crit")
	EventBus.energy_spent.connect(_on_energy_spent)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.color_changed.connect(_on_color_changed_impact)
	EventBus.color_changed.connect(_on_color_changed_relics)
	EventBus.player_died.connect(clear_relic_offers)
	EventBus.run_ended.connect(clear_relic_offers)


func begin_run() -> void:
	nodes = CATALOG.build()
	relics = CATALOG.build_relics()
	_by_id.clear()
	for node in nodes:
		_by_id[node.id] = node

	unlocked.clear()
	owned_relics.clear()
	damage_totals.clear()
	damage_bonus_estimates.clear()
	clear_relic_offers()
	player = null
	shop_level = 0
	shop_purchases = 0
	shop_rerolls = 0

	soul_kills = 0
	_soul_timer = 0.0
	_energy_buff_timers.clear()
	_energy_buff_mod = null
	_energy_rate_mod = null
	_speed_rate_mod = null
	_giant_damage_mod = null
	_giant_size_mod = null
	_giant_kills = 0
	_pointed_damage_mod = null
	_pointed_rate_mod = null
	guardian_shields = 0
	color_shield = -1
	_travel_distance = 0.0
	_revolver_volleys.clear()
	_temp_luck = 0.0
	_temp_luck_time = 0.0
	_adrenaline_time = 0.0
	_adrenaline_damage_mod = null
	_adrenaline_rate_mod = null
	_dice_time = 0.0
	_dice_roll = 0
	_dice_damage_mod = null
	_dice_rate_mod = null
	_dice_crit_mod = null
	_relic_source_serial = 0


func bind_player(player_node: Player) -> void:
	player = player_node
	_ensure_dynamic_modifiers()


func get_node_by_id(id: StringName) -> SkillNodeResource:
	return _by_id.get(id) as SkillNodeResource


func is_unlocked(id: StringName) -> bool:
	return unlocked.has(id)


func record_damage(key: StringName, amount: float) -> void:
	if amount > 0.0:
		damage_totals[key] = float(damage_totals.get(key, 0.0)) + amount


func record_projectile_damage(context: DamageContext, dealt: float) -> void:
	if dealt <= 0.0:
		return
	if context.has_tag(&"splash"):
		record_damage(&"skill:splash_1", dealt)
		return
	if context.has_tag(&"impact"):
		record_damage(&"relic:rare_impact_releaser", dealt)
		return
	if context.has_tag(&"clone"):
		record_damage(&"skill:clone_1", dealt)
		return
	if context.has_tag(&"sprite"):
		record_damage(&"skill:sprite_1", dealt)
		return
	if context.has_tag(&"arrow_poison"):
		record_damage(&"relic:rare_poison_arrow", dealt)
		return
	if context.has_tag(&"arrow_frost"):
		record_damage(&"relic:rare_frost_arrow", dealt)
		return
	if context.has_tag(&"arrow_burning"):
		record_damage(&"relic:rare_burning_arrow", dealt)
		return
	var ice := minf(dealt, context.elemental_bonus)
	if ice > 0.0:
		record_damage(&"skill:weak_3_ice", ice)
	dealt -= ice
	record_damage(StringName("weapon:%s" % String(context.weapon_id)) if context.weapon_id != &"" else &"base", dealt)
	if context.source is Projectile:
		var projectile := context.source as Projectile
		for key in projectile.damage_bonus_ratios:
			damage_bonus_estimates[key] = float(damage_bonus_estimates.get(key, 0.0)) + dealt * float(projectile.damage_bonus_ratios[key])


func projectile_bonus_ratios(stats: StatBlock, color_index: int, heavy: bool) -> Dictionary:
	var result := {}
	var raw := stats.get_value(&"damage") + (40.0 if heavy else 0.0)
	var mult := stats.get_value(&"damage_mult") + lens_damage_bonus(color_index) + cracked_armor_bonus()
	var final_mult := stats.get_value(&"damage_final")
	var current := raw * mult * final_mult
	if current <= 0.0:
		return result
	var sources := {}
	for stat in [&"damage", &"damage_mult", &"damage_final"]:
		for modifier: StatModifierResource in stats._by_stat.get(stat, []):
			if modifier.source != &"" and not String(modifier.source).begins_with("character_"):
				sources[modifier.source] = true
	for source in sources:
		var key := _damage_source_key(source)
		if key == &"":
			continue
		var without_raw := stats.get_value_without_source(&"damage", source) + (40.0 if heavy else 0.0)
		var without_mult := stats.get_value_without_source(&"damage_mult", source) + lens_damage_bonus(color_index) + cracked_armor_bonus()
		var without_final := stats.get_value_without_source(&"damage_final", source)
		var ratio := 1.0 - without_raw * without_mult * without_final / current
		if absf(ratio) > 0.0001:
			result[key] = float(result.get(key, 0.0)) + ratio
	return result


func _damage_source_key(source: StringName) -> StringName:
	if _by_id.has(source):
		return StringName("skill:%s" % String(source))
	var source_text := String(source)
	if source_text.begins_with("relic_"):
		for relic in owned_relics:
			if source_text.begins_with("relic_%s_" % String(relic.id)) or source_text.begins_with("relic_%s_double_" % String(relic.id)):
				return StringName("relic:%s" % String(relic.id))
		if source_text.begins_with("relic_adrenaline_"):
			return &"relic:rare_adrenaline"
		if source_text.begins_with("relic_dice_"):
			return &"relic:rare_fate_dice"
	if source_text.begins_with("skill_energy_2"):
		return &"skill:energy_2"
	return &""


func damage_source_name(key: StringName) -> String:
	if key == &"base":
		return "基础射击"
	if key == &"skill:weak_3_burn":
		return "元素附着 · 灼烧"
	if key == &"skill:weak_3_poison":
		return "元素附着 · 中毒"
	if key == &"skill:weak_3_ice":
		return "元素附着 · 冰裂"
	var parts := String(key).split(":", false, 1)
	if parts.size() != 2:
		return String(key)
	if parts[0] == "skill":
		var node := get_node_by_id(StringName(parts[1]))
		return node.display_name if node != null else parts[1]
	if parts[0] == "weapon":
		var weapon_data := ContentDB.get_data(StringName(parts[1])) as WeaponTraitResource
		return weapon_data.display_name if weapon_data != null else parts[1]
	for relic in relics:
		if String(relic.id) == parts[1]:
			return relic.display_name
	return parts[1]


func unlocked_count() -> int:
	return unlocked.size()


func has_flag(flag: StringName) -> bool:
	for node in unlocked.values():
		if (node as SkillNodeResource).has_flag(flag):
			return true
	return false


# ── 解锁规则 ────────────────────────────────────────────────────

func is_available(node: SkillNodeResource) -> bool:
	if node == null or unlocked.has(node.id):
		return false

	for prerequisite in node.prerequisites:
		if not unlocked.has(prerequisite):
			return false

	# 恶魔/天使只能选一边。
	if node.branch == &"demon" and unlocked.has(&"path_angel_1"):
		return false
	if node.branch == &"angel" and unlocked.has(&"path_demon_1"):
		return false

	return true


func get_available_nodes() -> Array[SkillNodeResource]:
	var available: Array[SkillNodeResource] = []
	for node in nodes:
		if is_available(node):
			available.append(node)
	return available


## 三选一时尽量来自不同分支，避免同一路线的 2/3 阶同时挤在一屏。
func pick_options(count: int, excluded: Array[StringName] = []) -> Array[SkillNodeResource]:
	var result: Array[SkillNodeResource] = []
	var remaining := get_available_nodes()
	for node in remaining.duplicate():
		if excluded.has(node.id):
			remaining.erase(node)
	var branches: Dictionary = {}

	for node in remaining:
		if not branches.has(node.branch):
			branches[node.branch] = []
		branches[node.branch].append(node)

	var keys := branches.keys()
	while result.size() < count and not keys.is_empty():
		var branch_key := _pick_branch(branches, keys)
		var branch_nodes: Array = branches[branch_key]
		var node := _pick_node(branch_nodes)
		if node != null:
			result.append(node)
			remaining.erase(node)
		keys.erase(branch_key)

	while result.size() < count and not remaining.is_empty():
		var node := _pick_node(remaining)
		if node == null:
			break
		result.append(node)
		remaining.erase(node)

	return result


func unlock(id: StringName, force: bool = false) -> bool:
	var node := get_node_by_id(id)
	if node == null or unlocked.has(id):
		return false
	if not force and not is_available(node):
		return false

	unlocked[id] = node
	for modifier in node.modifiers:
		_apply_modifier(modifier, node.id)

	_after_unlock(node)
	return true


# ── 运行时结算 ──────────────────────────────────────────────────

func xp_multiplier() -> float:
	return maxf(0.0, _stat(&"xp_gain", 1.0))


func gold_multiplier() -> float:
	return maxf(0.0, _stat(&"gold_gain", 1.0))


func gold_kill_bonus() -> int:
	return 1 if is_unlocked(&"gold_2") else 0


## 拾取范围：经验/金币两条一阶各 +50%，同时作用于两种掉落；两者都点则翻倍。
func pickup_radius_multiplier() -> float:
	var multiplier := 1.0
	if is_unlocked(&"xp_1"):
		multiplier += 0.50
	if is_unlocked(&"gold_1"):
		multiplier += 0.50
	multiplier += 0.30 * float(relic_count(&"dust_magnet"))
	return multiplier


## 三色透镜：三种颜色都获得 +15% 的加算伤害倍率。
func lens_damage_bonus(color_index: int) -> float:
	return 0.15 * float(relic_count(&"rare_prism_lens")) if color_index >= 0 and color_index < ColorType.COUNT else 0.0


## 破裂盔甲：每颗已损失的心提供 +5% 伤害倍率，随生命实时变化。
func cracked_armor_bonus() -> float:
	var stacks := relic_count(&"rare_cracked_armor")
	if stacks <= 0 or player == null or not is_instance_valid(player):
		return 0.0
	var lost_hearts := maxf(0.0, player.max_health - player.health)
	return lost_hearts * 0.05 * float(stacks)


## 冲击释放器：切换形态时，对周围被新形态克制的敌人打出一轮弱点伤害。
## 伤害按普通子弹的最终值计算；可暴击，但允许超暴击的开关必须关掉。
const IMPACT_RELEASER_RADIUS := 340.0

func _on_color_changed_impact(new_color: int) -> void:
	if not RunState.is_running or RunState.is_dead:
		return
	if player == null or not is_instance_valid(player):
		return
	var stacks := relic_count(&"rare_impact_releaser")
	if stacks <= 0:
		return

	var base_damage := impact_base_damage(new_color) * 2.0 * float(stacks)
	var center := player.global_position
	var radius_sq := IMPACT_RELEASER_RADIUS * IMPACT_RELEASER_RADIUS
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead:
			continue
		if enemy.global_position.distance_squared_to(center) > radius_sq:
			continue
		if RunState.color_relation(new_color, enemy.color_index) != &"advantage":
			continue
		var context := build_hit_context(player, enemy, base_damage, new_color, false)
		context.add_tag(&"impact")
		enemy.take_damage(context)
		# 冲击按“一次弱点命中”结算，因此弱点线的元素附着与处决也会触发。
		if not enemy.is_dead:
			on_weakness_hit(enemy, base_damage, new_color)
			try_execute(enemy, true)

	FX.shockwave(center, RunState.color_of(new_color), IMPACT_RELEASER_RADIUS * 0.8, 0.42, EnergyBurst.STYLE_HEAVY)
	FX.ripple(center, 0.35)


func _on_color_changed_relics(new_color: int) -> void:
	if not RunState.is_running or RunState.is_dead or player == null or not is_instance_valid(player):
		return
	if relic_count(&"epic_shield_generator") > 0:
		color_shield = new_color
		FX.hit_burst(player.global_position, RunState.color_of(new_color), 35.0, 0.18)
	var revolvers := relic_count(&"epic_classic_revolver")
	if revolvers > 0:
		_revolver_volleys.append({"remaining": 15 * revolvers, "angle": 0.0,
			"color": new_color, "timer": 0.0})
		if _revolver_volleys.size() > 3:
			_revolver_volleys.pop_front()


## 共享的 100% 武器基础伤害；冲击释放器在触发处乘 2，元素箭矢仍用原值。
func impact_base_damage(color_index: int) -> float:
	if player == null or not is_instance_valid(player) or player.weapon == null:
		return 0.0
	var weapon_stats := player.weapon.stats
	var damage_mult := weapon_stats.get_value(&"damage_mult")
	damage_mult += lens_damage_bonus(color_index)
	damage_mult += cracked_armor_bonus()
	return weapon_stats.get_value(&"damage") * damage_mult * weapon_stats.get_value(&"damage_final")


func apply_relic_projectile_procs(enemy: Enemy) -> void:
	if enemy == null:
		return
	if relic_count(&"demon_soul_blade") > 0 and RunState.rng.randf() < 0.20:
		_apply_soul_blade_hit(enemy)
	if enemy.is_dead:
		return
	if relic_count(&"rare_poison_arrow") + relic_count(&"rare_frost_arrow") + relic_count(&"rare_burning_arrow") <= 0:
		return
	for arrow in ARROW_RELICS:
		if relic_count(arrow[0]) <= 0 or RunState.rng.randf() >= 0.10:
			continue
		_apply_arrow_hit(enemy, arrow[1], arrow[2])
		if enemy.is_dead:
			break


func _apply_soul_blade_hit(enemy: Enemy) -> void:
	if enemy == null:
		return
	if not enemy.is_dead:
		enemy.take_true_damage(0.25 * (float(soul_kills) + 5.0), &"relic:demon_soul_blade")
	if enemy.is_dead:
		soul_kills += 1


func _apply_arrow_hit(enemy: Enemy, arrow_color: int, arrow_tag: StringName) -> void:
	if player == null or not is_instance_valid(player) or enemy == null or enemy.is_dead:
		return
	var amount := impact_base_damage(arrow_color) * elemental_multiplier()
	var context := build_hit_context(player, enemy, amount, arrow_color, false, false)
	context.add_tag(arrow_tag)
	context.add_tag(&"elemental")
	enemy.take_damage(context)


## 债券等“收益”遗物：每秒自动入账的金币。
func gold_income() -> float:
	return maxf(0.0, _stat(&"gold_income", 0.0))


## 当前幸运：永久属性 + 锦鲤的临时加成。
func luck() -> float:
	return maxf(0.0, _stat(&"luck", 0.0)) + _temp_luck


func lottery_chance() -> float:
	return 0.03 * clampf(1.0 + luck() * 0.01, 0.0, 3.0)


func try_guardian_shield() -> bool:
	if guardian_shields <= 0:
		return false
	guardian_shields -= 1
	return true


func try_color_shield(source: Node) -> bool:
	if color_shield < 0 or source == null:
		return false
	var attack_color := -1
	if source is Enemy:
		attack_color = (source as Enemy).color_index
	elif source is EnemyProjectile:
		attack_color = (source as EnemyProjectile).color_index
	if attack_color != color_shield:
		return false
	color_shield = -1
	return true


func temp_luck() -> float:
	return _temp_luck


## 刷新遗物提供的每店免费重掷次数。
func free_rerolls() -> int:
	return relic_count(&"rare_reroll") + relic_count(&"epic_six_sided_die") \
		+ 2 * relic_count(&"epic_vip_card")


## 子弹壳：每层 10% 连射概率，最多 3 层。
func bullet_shell_stacks() -> int:
	return mini(3, relic_count(&"rare_bullet_shell"))


func chain_fire_chance() -> float:
	return 0.10 * float(bullet_shell_stacks())


func roll_chain_fire() -> bool:
	var chance := chain_fire_chance()
	return chance > 0.0 and RunState.rng.randf() < chance


## 商人间隔固定 90 秒；买空货架可缩短下一次倒计时。
func merchant_interval() -> float:
	return MERCHANT_BASE_INTERVAL


## 普通升级最多 14 格；VIP 额外加一格，不占用升级名额。
func shop_slots() -> int:
	return mini(SHOP_MAX_SLOTS, SHOP_BASE_SLOTS + shop_level) + relic_count(&"epic_vip_card")


func spawn_rate_multiplier() -> float:
	return 1.0 + 0.20 * float(relic_count(&"epic_water_candle"))


func damage_invuln_bonus() -> float:
	return float(relic_count(&"rare_bloody_bandage"))


func on_player_moved(distance: float) -> void:
	var copies := relic_count(&"epic_travel_journal")
	if copies <= 0 or distance <= 0.0:
		return
	_travel_distance += distance
	while _travel_distance >= 500.0:
		_travel_distance -= 500.0
		RunState.add_gold(5 * copies)
		RunState.add_xp(5.0 * float(copies))


func can_upgrade_shop() -> bool:
	return SHOP_BASE_SLOTS + shop_level < SHOP_MAX_SLOTS


## 捐款升级：只增加等级；扣款由 ShopPanel 负责。
func upgrade_shop() -> bool:
	if not can_upgrade_shop():
		return false
	shop_level += 1
	return true


func energy_max_bonus() -> int:
	var bonus := 0
	if is_unlocked(&"energy_1"):
		bonus += 1
	if is_unlocked(&"energy_3"):
		bonus += 1
	if is_unlocked(&"energy_4"):
		bonus += 3
	return bonus


func energy_regen_multiplier() -> float:
	var multiplier := 1.0
	if is_unlocked(&"energy_1"):
		multiplier += 0.30
	if is_unlocked(&"energy_2"):
		multiplier += 0.10
	if is_unlocked(&"energy_3") and RunState.max_energy > 0.0:
		if RunState.energy < RunState.max_energy * 0.5:
			multiplier += 0.50
	multiplier += 0.20 * float(relic_count(&"rare_battery"))
	return multiplier


func fire_rate_cap_multiplier() -> float:
	return 9.0 if is_unlocked(&"fire_4") else 3.0


func heavy_shot_enabled() -> bool:
	return is_unlocked(&"heavy_4")


func weakness_multiplier() -> float:
	return _stat(&"weakness_multiplier", BASE_WEAKNESS)


func elemental_multiplier() -> float:
	return 1.0 + maxf(0.0, _stat(&"elemental_damage", 0.0))


# 闪避：超过 60% 的部分不生效，直接转为暴击率。
func get_dodge() -> float:
	var dodge := maxf(0.0, _stat(&"dodge", 0.0))
	return dodge


func effective_dodge() -> float:
	return minf(0.6, get_dodge())


func roll_dodge() -> bool:
	var dodge := effective_dodge()
	return dodge > 0.0 and RunState.rng.randf() < dodge


func get_crit_chance(target: Enemy = null) -> float:
	var chance := _stat(&"crit_chance", BASE_CRIT_CHANCE)
	if is_unlocked(&"crit_3") and target != null and is_instance_valid(target):
		chance += target.missing_health_ratio() * 0.5
	chance += maxf(0.0, get_dodge() - 0.6)
	return chance


func get_crit_damage(target: Enemy = null) -> float:
	var damage := _stat(&"crit_damage", BASE_CRIT_DAMAGE)
	if is_unlocked(&"crit_3") and target != null and is_instance_valid(target):
		damage += target.missing_health_ratio() * 2.0
	return damage


func get_super_crit_chance() -> float:
	if debug_force_super_crit:
		return 1.0
	return 0.01 if is_unlocked(&"crit_4") else 0.0


## 一次命中所需的全部伤害规则：颜色、弱点、暴击/超暴击、冰附着。
## allow_super_crit = false 时只允许普通暴击（冲击释放器等固定弱点伤害用）。
func build_hit_context(
	source: Node,
	target: Enemy,
	base_damage: float,
	color_index: int,
	allow_super_crit: bool = true,
	allow_crit: bool = true
) -> DamageContext:
	var context := DamageContext.new()
	context.source = source
	context.target = target
	context.color_index = color_index
	context.hit_position = target.global_position if target != null else Vector2.ZERO

	if target == null:
		context.amount = base_damage
		return context

	# 无色分身不参与颜色克制，也不受同色减伤。
	context.relation = RunState.color_relation(color_index, target.color_index) if color_index >= 0 else &"neutral"
	context.color_multiplier = RunState.color_multiplier(color_index, target.color_index) if color_index >= 0 else 1.0

	var is_weakness := context.relation == &"advantage"
	var multiplier := context.color_multiplier
	if is_weakness:
		multiplier = weakness_multiplier()

	var crit_chance := get_crit_chance(target)
	var crit_damage := get_crit_damage(target)
	var super_chance := get_super_crit_chance()

	if is_unlocked(&"crit_4"):
		super_chance += maxf(0.0, crit_chance - 1.0)
	crit_chance = minf(1.0, crit_chance)

	var is_super := allow_crit and allow_super_crit and super_chance > 0.0 and RunState.rng.randf() < super_chance
	var is_crit := allow_crit and (is_super or RunState.rng.randf() < crit_chance)

	if is_super:
		# 超暴击强制按弱点结算，并吃两次暴伤。
		is_weakness = true
		multiplier = weakness_multiplier()
		context.relation = &"advantage"
		context.color_multiplier = multiplier
		context.amount = base_damage * multiplier * crit_damage * crit_damage
		context.add_tag(&"super_crit")
	elif is_crit:
		context.amount = base_damage * multiplier * crit_damage
		context.add_tag(&"crit")
	else:
		context.amount = base_damage * multiplier

	context.is_crit = is_crit
	if is_weakness:
		context.add_tag(&"weakness")

	if is_unlocked(&"weak_3") and target.has_ice():
		# 元素伤害吃弱点倍率，但不吃这次射击的暴击倍率。
		var ice_damage := base_damage * weakness_multiplier() * 0.20 * elemental_multiplier()
		context.elemental_bonus = ice_damage
		context.amount += ice_damage
		context.add_tag(&"ice")

	return context


## 弱点命中后的元素附着。
func on_weakness_hit(enemy: Enemy, base_damage: float, color_index: int) -> void:
	if not is_unlocked(&"weak_3") or enemy == null or enemy.is_dead:
		return

	var elemental := elemental_multiplier()
	match color_index:
		ColorType.RED:
			enemy.apply_burn(base_damage * 2.0 * weakness_multiplier() * elemental)
		ColorType.GREEN:
			enemy.apply_poison(base_damage * 0.45 * weakness_multiplier() * elemental)
		ColorType.BLUE:
			enemy.apply_slow(0.25 * elemental, 3.0)
			enemy.apply_ice(3.0)


func try_execute(enemy: Enemy, is_weakness: bool) -> void:
	if not is_unlocked(&"weak_4") or enemy == null or enemy.is_dead or not is_weakness:
		return
	if enemy.max_health <= 0.0 or enemy.health <= 0.0:
		return

	var threshold := 0.05 if enemy.type_data != null and enemy.type_data.is_boss else 0.15
	if enemy.health / enemy.max_health <= threshold:
		FX.text_popup(
			enemy.global_position + Vector2(0.0, -enemy.radius - 18.0),
			"处决",
			Color(2.6, 0.4, 0.55),
			18
		)
		enemy.execute()


func has_splash() -> bool:
	return is_unlocked(&"splash_1")


func splash_ratio() -> float:
	return 0.6 if is_unlocked(&"splash_2") else 0.4


func splash_radius() -> float:
	return SPLASH_BASE_RADIUS * (1.5 if is_unlocked(&"splash_3") else 1.0)


func splash_every_hit() -> bool:
	return is_unlocked(&"splash_4")


func apply_splash(
	world_position: Vector2,
	hit_amount: float,
	color_index: int,
	excluded: Enemy = null
) -> void:
	if not has_splash():
		return

	var radius := splash_radius()
	var amount := hit_amount * splash_ratio()
	var color := RunState.color_of(color_index)
	var context := DamageContext.new()
	context.source = null
	context.amount = amount
	context.color_index = color_index
	context.color_multiplier = 1.0
	context.hit_position = world_position
	context.add_tag(&"splash")

	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Enemy):
			continue
		var enemy := node as Enemy
		if enemy == excluded or enemy.is_dead:
			continue
		var reach := radius + enemy.radius
		if world_position.distance_squared_to(enemy.global_position) > reach * reach:
			continue

		context.target = enemy
		context.relation = RunState.color_relation(color_index, enemy.color_index)
		enemy.take_damage(context)
		try_execute(enemy, context.relation == &"advantage")

	FX.shockwave(world_position, color, radius, 0.26, EnergyBurst.STYLE_SPLASH)


func try_gold_on_hit(world_position: Vector2) -> void:
	if is_unlocked(&"gold_4") and RunState.rng.randf() < 0.2:
		Pickups.spawn_gold(world_position, 1)


func on_gold_gained(amount: int) -> void:
	if amount <= 0 or not is_unlocked(&"xp_2"):
		return
	if RunState.rng.randf() < 0.5:
		RunState.add_xp(1)


func xp_auto_collect() -> bool:
	return is_unlocked(&"xp_4")


func gold_auto_collect() -> bool:
	return is_unlocked(&"gold_3")


## 兼容旧接口：商店不再做阵营概率加倍，所有候选权重统一。
func shop_weight_multiplier(_side: StringName) -> float:
	return 1.0


func shop_quality_bonus(side: StringName) -> int:
	return 1 if is_unlocked(StringName("path_%s_2" % String(side))) else 0


func altars_enabled(side: StringName) -> bool:
	return is_unlocked(StringName("path_%s_3" % String(side)))


## 当前可用的祭坛阵营：必须先选择契约（2 阶）并点出对应 3 阶。
## 未满足时返回空，Director 不会生成祭坛。
func altar_side() -> StringName:
	var side := merchant_side()
	if side == &"" or not altars_enabled(side):
		return &""
	return side


func soul_interval() -> float:
	return 2.0 if is_unlocked(&"soul_3") else 3.0


func soul_radius() -> float:
	return SOUL_BASE_RADIUS * (1.5 if is_unlocked(&"soul_3") else 1.0)


func soul_multiplier() -> float:
	return 1.7 if is_unlocked(&"soul_2") else 1.2


func soul_damage() -> float:
	if player == null or not is_instance_valid(player):
		return 0.0
	var stats := player.weapon.stats
	var soul_count := soul_kills * (2 if is_unlocked(&"soul_4") else 1)
	return (stats.get_value(&"damage") * stats.get_value(&"damage_mult") + float(soul_count)) * soul_multiplier()


# ── 帧更新：能量增益、击杀层数、灵魂脉冲 ───────────────────────

func _process(delta: float) -> void:
	if not RunState.is_running or RunState.is_dead:
		return
	if player == null or not is_instance_valid(player):
		return

	_tick_energy_buff(delta)
	_tick_speed_rate()
	_tick_giant_scaling()
	_tick_pointed_vessel()
	_tick_temp_luck(delta)
	_tick_adrenaline(delta)
	_tick_dice(delta)
	_tick_soul(delta)
	_tick_revolver(delta)


func _tick_revolver(delta: float) -> void:
	if _revolver_volleys.is_empty() or player.projectile_manager == null or player.weapon == null:
		return
	for i in range(_revolver_volleys.size() - 1, -1, -1):
		var volley := _revolver_volleys[i]
		volley["timer"] = float(volley["timer"]) - delta
		while float(volley["timer"]) <= 0.0 and int(volley["remaining"]) > 0:
			var direction := Vector2.from_angle(float(volley["angle"]))
			player.projectile_manager.fire(
				player.global_position + direction * (player.body_radius + 8.0),
				direction, player.weapon.stats, int(volley["color"]),
				player.weapon.core, false, 1.0, 1.0, 1.0, 1.0, true, &"revolver")
			volley["angle"] = float(volley["angle"]) + TAU / 15.0
			volley["remaining"] = int(volley["remaining"]) - 1
			volley["timer"] = float(volley["timer"]) + 0.035
		if int(volley["remaining"]) <= 0:
			_revolver_volleys.remove_at(i)


func _tick_adrenaline(delta: float) -> void:
	if _adrenaline_time <= 0.0:
		return
	_adrenaline_time = maxf(0.0, _adrenaline_time - delta)
	_update_adrenaline()


func _tick_dice(delta: float) -> void:
	if relic_count(&"rare_fate_dice") <= 0:
		return
	_ensure_dynamic_modifiers()
	_dice_time -= delta
	if _dice_time <= 0.0:
		_roll_dice()


func _tick_temp_luck(delta: float) -> void:
	if _temp_luck_time <= 0.0:
		return
	_temp_luck_time -= delta
	if _temp_luck_time <= 0.0:
		_temp_luck = 0.0
		_temp_luck_time = 0.0


func _tick_energy_buff(delta: float) -> void:
	if _energy_buff_timers.is_empty():
		return
	var expired := false
	for i in range(_energy_buff_timers.size() - 1, -1, -1):
		_energy_buff_timers[i] -= delta
		if _energy_buff_timers[i] <= 0.0:
			_energy_buff_timers.remove_at(i)
			expired = true
	if expired:
		_update_energy_buff()


func _tick_soul(delta: float) -> void:
	if not is_unlocked(&"soul_1"):
		return

	_soul_timer -= delta
	if _soul_timer > 0.0:
		return

	_soul_timer = soul_interval()
	_do_soul_pulse()


func _do_soul_pulse() -> void:
	var radius := soul_radius()
	var amount := soul_damage()
	# 使用饱和的 SDR 紫色，减少不同渲染方式下的高亮泛白。
	var color := Color(0.68, 0.22, 1.0, 1.0)
	Audio.play(&"soul")
	FX.shockwave(player.global_position, color, radius, 0.32, EnergyBurst.STYLE_SOUL)
	FX.ripple(player.global_position, 0.35)

	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Enemy):
			continue
		var enemy := node as Enemy
		if enemy.is_dead:
			continue
		var reach := radius + enemy.radius
		if player.global_position.distance_squared_to(enemy.global_position) > reach * reach:
			continue

		var was_alive := not enemy.is_dead
		enemy.take_true_damage(amount)
		if was_alive and enemy.is_dead:
			soul_kills += 2 if is_unlocked(&"soul_4") else 1


func _on_energy_spent(amount: float) -> void:
	if amount <= 0.0:
		return
	if is_unlocked(&"energy_2"):
		for _i in maxi(1, roundi(amount)):
			_energy_buff_timers.append(5.0)
		_ensure_dynamic_modifiers()
		_update_energy_buff()
	if is_unlocked(&"energy_4") and RunState.rng.randf() < 0.20:
		RunState.restore_energy_full()


func _on_enemy_killed(enemy: Node, _gold: int, _xp: float) -> void:
	if not (enemy is Enemy):
		return
	if is_unlocked(&"giant_4"):
		_giant_kills += 1
		if _giant_kills >= 300:
			_giant_kills = 0
			player.heal(0.5)
	var death_position := (enemy as Enemy).global_position
	if is_unlocked(&"shotgun_2"):
		_shotgun_death_burst(death_position)
	try_spawn_chest(death_position)


## 散弹 2 阶：敌人死亡时从尸体位置裂出 3 枚 35% 伤害的小子弹。
func _shotgun_death_burst(death_position: Vector2, deferred: bool = false) -> void:
	# 碰撞回调里的连锁死亡要等物理查询结束，才能安全复用/创建碰撞体。
	if Engine.is_in_physics_frame() and not deferred:
		_shotgun_death_burst.call_deferred(death_position, true)
		return
	if not RunState.is_running or RunState.is_dead:
		return
	if player == null or not is_instance_valid(player):
		return
	var manager := player.projectile_manager
	if manager == null or player.weapon == null or player.weapon.core == null:
		return

	var nearest := _nearest_enemy_to(death_position)
	var base_direction := Vector2.RIGHT
	if nearest != null:
		base_direction = (nearest.global_position - death_position).normalized()
	else:
		base_direction = Vector2.from_angle(RunState.rng.randf() * TAU)

	var spread := deg_to_rad(62.0)
	for i in 3:
		var offset := lerpf(-spread * 0.5, spread * 0.5, float(i) / 2.0)
		manager.fire(
			death_position,
			base_direction.rotated(offset),
			player.weapon.stats,
			player.color_index,
			player.weapon.core,
			false,
			0.35,
			0.68,
			0.50,  # 裂片速度减半
			0.45,  # 存活时间 45%，射程约剩两成
			false  # 不继承暴击
		)


func _nearest_enemy_to(world_position: Vector2) -> Enemy:
	var best: Enemy = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if not (node is Enemy):
			continue
		var enemy := node as Enemy
		if enemy.is_dead:
			continue
		var distance := world_position.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


# ── 幸运 / 宝箱 ────────────────────────────────────────────────

## 前期多开资源箱，后期限制箱量：2% 基础 + 每点幸运 0.2%，封顶 6%。
## 上限压低是为了控制后期：高击杀密度会把“每次击杀概率”放大成宝箱瀑布。
func chest_drop_chance() -> float:
	if not is_unlocked(&"luck_1"):
		return 0.0
	return minf(0.06, 0.02 + luck() * 0.002)


## 遗物低频产出：10% 基础，二阶 +5%，虹彩每层 +2%，封顶 20%。
func chest_relic_chance() -> float:
	if not is_unlocked(&"luck_1"):
		return 0.0
	var chance := 0.10
	if is_unlocked(&"luck_2"):
		chance += 0.05
	chance += 0.02 * float(relic_count(&"legendary_rainbow_clover"))
	return minf(0.20, chance)


func try_spawn_chest(world_position: Vector2) -> void:
	var chance := chest_drop_chance()
	if chance <= 0.0 or RunState.rng.randf() >= chance:
		return
	var offset := Vector2.from_angle(RunState.rng.randf() * TAU) \
		* RunState.rng.randf_range(12.0, 30.0)
	Pickups.spawn_chest(world_position + offset)


func on_chest_discovered() -> void:
	if is_unlocked(&"luck_4"):
		grant_temp_luck(6.0, 60.0)


## 宝箱在磁吸到玩家后打开：先判定遗物，否则给金币/经验。
func open_chest(world_position: Vector2) -> void:
	Audio.play(&"chest")
	var relic := _roll_chest_relic() if RunState.rng.randf() < chest_relic_chance() else null
	if relic != null and offer_relic(relic.id, "宝箱", true):
		FX.text_popup(
			world_position + Vector2(0.0, -18.0),
			"发现：%s" % relic.display_name,
			_rarity_color(relic.rarity),
			17
		)
		FX.hit_burst(world_position, _rarity_color(relic.rarity), 46.0, 0.3, EnergyBurst.STYLE_STAR)
		FX.ripple(world_position, 0.35)
		return

	# 没出遗物：金币与经验各半，数量随幸运小幅提高。
	var bonus := int(round(luck() * 0.5))
	if RunState.rng.randf() < 0.5:
		Pickups.spawn_gold(world_position, 6 + bonus)
		FX.text_popup(world_position + Vector2(0.0, -16.0), "金币 +%d" % (6 + bonus), Color(1.0, 0.85, 0.35), 15)
	else:
		Pickups.spawn_xp(world_position, 3 + int(round(luck() * 0.35)))
		FX.text_popup(world_position + Vector2(0.0, -16.0), "经验 +%d" % (3 + int(round(luck() * 0.35))), Color(0.5, 0.95, 1.0), 15)
	FX.hit_burst(world_position, Color(1.6, 1.2, 0.45), 28.0, 0.22, EnergyBurst.STYLE_HEAVY)


func _roll_chest_relic() -> RelicResource:
	var candidates: Array[RelicResource] = []
	var weights: Array[float] = []
	for relic in shop_relic_pool(true):
		candidates.append(relic)
		weights.append(_chest_relic_weight(relic))
	if candidates.is_empty():
		return null

	var total := 0.0
	for weight in weights:
		total += weight
	if total <= 0.0:
		return null

	var roll := RunState.rng.randf() * total
	for i in candidates.size():
		if roll <= weights[i]:
			return candidates[i]
		roll -= weights[i]
	return candidates.back()


func _chest_relic_weight(relic: RelicResource) -> float:
	var l := luck()
	match relic.rarity:
		RelicResource.RARITY_RARE:
			return relic.offer_weight * (0.6 + l * 0.05)
		RelicResource.RARITY_EPIC:
			return relic.offer_weight * (0.2 + l * 0.03)
		RelicResource.RARITY_LEGENDARY:
			return relic.offer_weight * (0.05 + l * 0.015)
		RelicResource.RARITY_IRIDESCENT:
			return relic.offer_weight * (0.02 + l * 0.005)
		RelicResource.RARITY_CURSED:
			return relic.offer_weight * 0.03
		_:
			return relic.offer_weight


func _on_player_damaged(_amount: float) -> void:
	if relic_count(&"rare_adrenaline") <= 0:
		return
	_ensure_dynamic_modifiers()
	_adrenaline_time = 20.0
	_update_adrenaline()


func _update_adrenaline() -> void:
	if _adrenaline_damage_mod == null or _adrenaline_rate_mod == null:
		return
	var stacks := float(relic_count(&"rare_adrenaline"))
	var factor := clampf(_adrenaline_time / 20.0, 0.0, 1.0) * stacks
	_adrenaline_damage_mod.value = 1.0 * factor
	_adrenaline_rate_mod.value = 1.0 + 0.5 * factor


## 命运骰子：六种结果，重复拾取会让数值按份数放大，但仍然是同一次投掷。
func _roll_dice() -> void:
	var stacks := float(relic_count(&"rare_fate_dice"))
	if stacks <= 0.0:
		return
	_dice_roll = RunState.rng.randi_range(1, 6)
	var damage := 0.0
	var rate := 0.0
	var crit := 0.0
	match _dice_roll:
		1:
			damage = -0.20
			rate = -0.20
		2:
			damage = -0.20
		4:
			damage = 0.10
		5:
			damage = 0.20
			rate = 0.20
		6:
			damage = 0.30
			rate = 0.30
			crit = 0.50
	if _dice_damage_mod != null:
		_dice_damage_mod.value = damage * stacks
	if _dice_rate_mod != null:
		_dice_rate_mod.value = maxf(0.0, 1.0 + rate * stacks)
	if _dice_crit_mod != null:
		_dice_crit_mod.value = crit * stacks
	_dice_time = 10.0
	FX.dice_roll(player, _dice_roll)


## 当前骰子点数（0 = 还没投掷）；测试与调试用。
func dice_roll() -> int:
	return _dice_roll


func grant_temp_luck(amount: float, duration: float) -> void:
	if amount <= 0.0 or duration <= 0.0:
		return
	_temp_luck = maxf(_temp_luck, amount)
	_temp_luck_time = maxf(_temp_luck_time, duration)


func _rarity_color(rarity: int) -> Color:
	match rarity:
		RelicResource.RARITY_RARE:
			return Color(0.45, 0.72, 1.0)
		RelicResource.RARITY_EPIC:
			return Color(0.75, 0.45, 1.0)
		RelicResource.RARITY_LEGENDARY:
			return Color(1.0, 0.65, 0.25)
		RelicResource.RARITY_IRIDESCENT:
			return Color(0.8, 1.0, 0.75)
		RelicResource.RARITY_CURSED:
			return Color(1.0, 0.25, 0.3)
		_:
			return Color(0.75, 0.7, 0.55)


# ── 内部 ────────────────────────────────────────────────────────

func _stat(stat: StringName, fallback: float) -> float:
	if player != null and is_instance_valid(player):
		return player.stats.get_value(stat)
	return fallback


func _apply_modifier(modifier: StatModifierResource, source: StringName) -> void:
	if player == null or not is_instance_valid(player):
		return
	var copy := modifier.duplicate() as StatModifierResource
	if copy == null:
		return
	copy.source = source
	player.apply_stat_modifier(copy)


func _after_unlock(node: SkillNodeResource) -> void:
	match node.id:
		&"path_demon_1":
			_grant_relic(&"demon")
		&"path_angel_1":
			_grant_relic(&"angel")
		&"path_demon_3":
			_grant_relic(&"demon")
		&"path_angel_3":
			_grant_relic(&"angel")
		&"path_demon_4":
			_double_relics(&"demon")
		&"path_angel_4":
			_double_relics(&"angel")
		&"luck_3":
			_grant_lucky_relic()
		&"giant_4":
			_giant_kills = 0

	_ensure_dynamic_modifiers()

	RunState.refresh_energy_caps()
	if player != null and is_instance_valid(player):
		player.refresh_derived()
		if node.id == &"giant_4":
			player.heal(player.max_health)


## 按 id 查找遗物定义（含一次性物品）。
func get_relic(id: StringName) -> RelicResource:
	for relic in relics:
		if relic.id == id:
			return relic
	return null


## 已拥有数量；商店卡片用它显示“小刀 ×3”。
func relic_count(id: StringName) -> int:
	var count := 0
	for relic in owned_relics:
		if relic.id == id:
			count += 1
	return count


## 已选择契约的阵营：恶魔/天使二阶节点只会有一个。
## 未选择时返回空，此时任何恶魔/天使遗物都不会进入商店。
func merchant_side() -> StringName:
	if is_unlocked(&"path_demon_2"):
		return &"demon"
	if is_unlocked(&"path_angel_2"):
		return &"angel"
	return &""


## 商店可售遗物：
## - 恶魔/天使遗物只有在对应契约 2 阶已选择后才可能出现；
## - 幸运遗物需要先解锁幸运 1 阶；
## - 排除已拥有的唯一遗物与已达叠加上限的遗物；
## - 金块是宝箱专属，默认不进商店；吸铁石在金币线或经验线点满后消失。
func shop_relic_pool(include_chest_only: bool = false) -> Array[RelicResource]:
	var committed := merchant_side()
	var pool: Array[RelicResource] = []
	for relic in relics:
		if relic.chest_only and not include_chest_only:
			continue
		if relic.unique and (owned_relics.has(relic) or pending_relic_count(relic.id) > 0):
			continue
		if relic.max_stacks > 0 and relic_count(relic.id) + pending_relic_count(relic.id) >= relic.max_stacks:
			continue
		if relic.side != &"" and relic.side != committed:
			continue
		if relic.lucky and not is_unlocked(&"luck_1"):
			continue
		if relic.id == &"dust_magnet" and (_line_maxed(&"xp") or _line_maxed(&"gold")):
			continue
		pool.append(relic)
	return pool


## 整条技能线 4 阶全部点满。
func _line_maxed(branch: StringName) -> bool:
	for tier in range(1, 5):
		if not is_unlocked(StringName("%s_%d" % [String(branch), tier])):
			return false
	return true


## 抽 count 个不重复的商店货品；exclude 用于重掷时避开当前货架。
## 商店等级 / 契约品质会提高高稀有度遗物的权重，不再有阵营概率翻倍。
func shop_offers(count: int, exclude: Array[StringName] = []) -> Array[RelicResource]:
	var candidates: Array[RelicResource] = []
	for relic in shop_relic_pool():
		if exclude.has(relic.id):
			continue
		candidates.append(relic)

	var offers: Array[RelicResource] = []
	while offers.size() < count and not candidates.is_empty():
		var rarity_totals := _shop_rarity_weights()
		var available_total := 0.0
		for rarity in rarity_totals:
			var exists := false
			for relic in candidates:
				if relic.rarity == rarity:
					exists = true
					break
			if exists:
				available_total += float(rarity_totals[rarity])
			else:
				rarity_totals[rarity] = 0.0
		if available_total <= 0.0:
			break
		var rarity_roll := RunState.rng.randf() * available_total
		var selected_rarity := RelicResource.RARITY_DUST
		for rarity in rarity_totals:
			if rarity_roll <= float(rarity_totals[rarity]):
				selected_rarity = rarity
				break
			rarity_roll -= float(rarity_totals[rarity])
		var within_total := 0.0
		for relic in candidates:
			if relic.rarity == selected_rarity:
				within_total += relic.offer_weight
		var within_roll := RunState.rng.randf() * within_total
		var picked := -1
		for i in candidates.size():
			if candidates[i].rarity != selected_rarity:
				continue
			picked = i
			if within_roll <= candidates[i].offer_weight:
				break
			within_roll -= candidates[i].offer_weight
		if picked < 0:
			break
		offers.append(candidates[picked])
		candidates.remove_at(picked)

	return offers


func _shop_rarity_weights() -> Dictionary:
	var level := shop_level + shop_quality_bonus(merchant_side())
	match level:
		0: return {0: 0.70, 1: 0.30}
		1: return {0: 0.55, 1: 0.40, 2: 0.05}
		2: return {0: 0.40, 1: 0.48, 2: 0.12}
		3: return {0: 0.25, 1: 0.55, 2: 0.18, 3: 0.02}
		4: return {0: 0.15, 1: 0.55, 2: 0.25, 3: 0.05}
		_: return {0: 0.05, 1: 0.50, 2: 0.35, 3: 0.10}


## 商店/调试用的直接拾取。
## 默认可重复拾取并叠加生效；只有 unique 遗物在第二次拾取时被拒绝。
## 一次性物品（consumable）执行效果后不进入遗物栏。
func grant_relic(id: StringName, value_multiplier: float = 1.0) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var relic := get_relic(id)
	if relic == null:
		return false
	if relic.unique and owned_relics.has(relic):
		return false
	if relic.max_stacks > 0 and relic_count(relic.id) >= relic.max_stacks:
		return false
	if relic.lucky and not is_unlocked(&"luck_1"):
		return false

	if relic.pickup_health_loss_ratio > 0.0:
		player.pay_health_ratio(relic.pickup_health_loss_ratio)
	if relic.pickup_health_loss_hearts > 0.0:
		player.pay_health_flat(relic.pickup_health_loss_hearts)
	if relic.pickup_heal_ratio > 0.0:
		player.heal(player.max_health * relic.pickup_heal_ratio)
	if relic.pickup_heal_hearts > 0.0:
		player.heal(relic.pickup_heal_hearts)
	if relic.pickup_gold > 0:
		RunState.add_gold(relic.pickup_gold)
	if relic.id == &"dust_lottery" and RunState.rng.randf() < lottery_chance():
		RunState.add_gold_debt(3000)
	if relic.id == &"rare_mystery_gift":
		var candidates: Array[RelicResource] = []
		for candidate in shop_relic_pool():
			if candidate.rarity <= RelicResource.RARITY_EPIC and candidate.id != relic.id:
				candidates.append(candidate)
		if candidates.is_empty():
			return false
		return grant_relic(candidates[RunState.rng.randi_range(0, candidates.size() - 1)].id)

	if relic.consumable:
		return true

	owned_relics.append(relic)
	_apply_relic(relic, value_multiplier, "")
	if relic.id == &"epic_weapon_cache":
		EventBus.weapon_reward_requested.emit("武装密钥")
	if relic.id == &"rare_golden_apple":
		player.heal(player.max_health)
	elif relic.id == &"rare_bond":
		RunState.add_gold_debt(-300)
	elif relic.id == &"rare_high_bond":
		RunState.add_gold_debt(-1000)
	elif relic.id == &"rare_ounce_soul":
		soul_kills += 50
	elif relic.id == &"demon_pointed_vessel":
		player.health = 0.5
		EventBus.player_health_changed.emit(player.health, player.max_health)
		_ensure_dynamic_modifiers()
		_tick_pointed_vessel()
	elif relic.id == &"angel_guardian":
		guardian_shields += 2 * maxi(1, roundi(value_multiplier))

	if relic.id == &"rare_adrenaline":
		_ensure_dynamic_modifiers()
		_update_adrenaline()
	elif relic.id == &"rare_fate_dice":
		_ensure_dynamic_modifiers()
		_roll_dice()
	return true


func clear_relic_offers() -> void:
	pending_relic_offers.clear()


func pending_relic_count(id: StringName) -> int:
	var count := 0
	for offer in pending_relic_offers:
		if offer.id == id:
			count += 1
	return count


## 宝箱/技能/祭坛的发现入口。唯一和叠层上限包含排队奖励，防止重复预留。
func offer_relic(id: StringName, source: String, from_chest: bool = false) -> bool:
	if player == null or not is_instance_valid(player) or RunState.is_dead:
		return false
	var relic := get_relic(id)
	if relic == null or (relic.lucky and not is_unlocked(&"luck_1")):
		return false
	var reserved := relic_count(id) + pending_relic_count(id)
	if (relic.unique and reserved > 0) or (relic.max_stacks > 0 and reserved >= relic.max_stacks):
		return false
	_offer_serial += 1
	pending_relic_offers.append({"ticket": _offer_serial, "id": id, "source": source, "from_chest": from_chest})
	return true


## 只允许结算队首；丢弃不发放属性、金币、治疗或锦鲤增益。
func resolve_relic_offer(ticket: int, take: bool) -> bool:
	if pending_relic_offers.is_empty() or pending_relic_offers[0].ticket != ticket:
		return false
	var offer: Dictionary = pending_relic_offers.pop_front()
	if not take:
		return true
	if RunState.is_dead:
		return false
	var relic := get_relic(offer.id)
	if relic == null:
		return false
	var value_multiplier := 1.0
	if relic.side != &"" and is_unlocked(StringName("path_%s_4" % String(relic.side))):
		value_multiplier = 2.0
	if not grant_relic(relic.id, value_multiplier):
		return false
	Audio.play(&"ui_buy")
	return true


## 幸运 3 阶：从蓝色~橙色幸运遗物中随机获取一个。
func _grant_lucky_relic() -> void:
	var pool: Array[RelicResource] = []
	for relic in relics:
		if not relic.lucky:
			continue
		if relic.rarity < RelicResource.RARITY_RARE \
			or relic.rarity > RelicResource.RARITY_LEGENDARY:
			continue
		if relic.unique and (owned_relics.has(relic) or pending_relic_count(relic.id) > 0):
			continue
		if relic.max_stacks > 0 and relic_count(relic.id) + pending_relic_count(relic.id) >= relic.max_stacks:
			continue
		pool.append(relic)
	if pool.is_empty():
		RunState.add_gold(40)
		return
	var relic := pool[RunState.rng.randi_range(0, pool.size() - 1)]
	if not offer_relic(relic.id, "天选奖励"):
		RunState.add_gold(40)


## 本阵营还有几个未拥有的遗物；祭坛面板据此决定显示“遗物”还是“馈赠”。
func side_relic_remaining(side: StringName) -> int:
	var count := 0
	for relic in relics:
		if relic.side == side and not owned_relics.has(relic) and pending_relic_count(relic.id) == 0:
			count += 1
	return count


## 祭坛/契约奖励：随机给一个尚未拥有的本阵营遗物。
## 收益规则与契约奖励一致（4 阶时属性翻倍）；池子为空返回 null。
func grant_side_relic(side: StringName) -> RelicResource:
	if player == null or not is_instance_valid(player):
		return null

	var pool: Array[RelicResource] = []
	for relic in relics:
		if relic.side == side and not owned_relics.has(relic):
			pool.append(relic)
	if pool.is_empty():
		return null

	var relic: RelicResource = pool[RunState.rng.randi_range(0, pool.size() - 1)]
	var value_multiplier := 2.0 if is_unlocked(StringName("path_%s_4" % String(side))) else 1.0
	return relic if grant_relic(relic.id, value_multiplier) else null


func _grant_relic(side: StringName) -> void:
	offer_side_relic(side, "恶魔契约" if side == &"demon" else "天使契约")


func offer_side_relic(side: StringName, source: String = "祭坛奖励") -> RelicResource:
	var pool: Array[RelicResource] = []
	for relic in relics:
		if relic.side == side and not owned_relics.has(relic) and pending_relic_count(relic.id) == 0:
			pool.append(relic)
	if pool.is_empty():
		return null
	var relic: RelicResource = pool[RunState.rng.randi_range(0, pool.size() - 1)]
	return relic if offer_relic(relic.id, source) else null


func _double_relics(side: StringName) -> void:
	if player == null or not is_instance_valid(player):
		return
	for relic in owned_relics:
		if relic.side == side:
			_apply_relic(relic, 1.0, "_double")
			if relic.id == &"angel_guardian":
				guardian_shields += 2
	if side == &"demon":
		_tick_pointed_vessel()


func _apply_relic(relic: RelicResource, value_multiplier: float, source_suffix: String) -> void:
	for modifier in relic.modifiers:
		var copy := modifier.duplicate() as StatModifierResource
		if copy == null:
			continue
		copy.value *= value_multiplier
		_relic_source_serial += 1
		copy.source = StringName(
			"relic_%s%s_%d" % [String(relic.id), source_suffix, _relic_source_serial]
		)
		player.apply_stat_modifier(copy)


func _ensure_dynamic_modifiers() -> void:
	if player == null or not is_instance_valid(player):
		return

	if is_unlocked(&"energy_2") and _energy_buff_mod == null:
		_energy_buff_mod = _make_modifier(&"damage_mult", StatModifierResource.Op.ADD_PERCENT, 0.0)
		_energy_buff_mod.source = &"skill_energy_2_damage"
		player.weapon.stats.add_modifier(_energy_buff_mod)
		_energy_rate_mod = _make_modifier(&"fire_rate_mult", StatModifierResource.Op.ADD_PERCENT, 0.0)
		_energy_rate_mod.source = &"skill_energy_2_rate"
		player.weapon.stats.add_modifier(_energy_rate_mod)

	if is_unlocked(&"speed_3") and _speed_rate_mod == null:
		_speed_rate_mod = _make_modifier(&"fire_rate_final", StatModifierResource.Op.MULTIPLY, 1.0)
		_speed_rate_mod.source = &"skill_speed_3_rate"
		player.weapon.stats.add_modifier(_speed_rate_mod)
		_tick_speed_rate()

	if is_unlocked(&"giant_2") and _giant_damage_mod == null:
		_giant_damage_mod = _make_modifier(&"damage_mult", StatModifierResource.Op.ADD_PERCENT, 0.0)
		_giant_damage_mod.source = &"skill_giant_2_damage"
		player.weapon.stats.add_modifier(_giant_damage_mod)
		_giant_size_mod = _make_modifier(&"projectile_size", StatModifierResource.Op.ADD_PERCENT, 0.0)
		_giant_size_mod.source = &"skill_giant_2_size"
		player.weapon.stats.add_modifier(_giant_size_mod)
		_tick_giant_scaling()

	if relic_count(&"demon_pointed_vessel") > 0 and _pointed_damage_mod == null:
		_pointed_damage_mod = _make_modifier(&"damage", StatModifierResource.Op.FLAT, 0.0)
		_pointed_damage_mod.source = &"relic_pointed_vessel_damage"
		player.weapon.stats.add_modifier(_pointed_damage_mod)
		_pointed_rate_mod = _make_modifier(&"fire_rate_mult", StatModifierResource.Op.ADD_PERCENT, 0.0)
		_pointed_rate_mod.source = &"relic_pointed_vessel_rate"
		player.weapon.stats.add_modifier(_pointed_rate_mod)
		_tick_pointed_vessel()

	if relic_count(&"rare_adrenaline") > 0 and _adrenaline_damage_mod == null:
		_adrenaline_damage_mod = _make_modifier(&"damage_mult", StatModifierResource.Op.ADD_PERCENT, 0.0)
		_adrenaline_damage_mod.source = &"relic_adrenaline_damage"
		player.weapon.stats.add_modifier(_adrenaline_damage_mod)

		_adrenaline_rate_mod = _make_modifier(&"fire_rate_final", StatModifierResource.Op.MULTIPLY, 1.0)
		_adrenaline_rate_mod.source = &"relic_adrenaline_rate"
		player.weapon.stats.add_modifier(_adrenaline_rate_mod)

	if relic_count(&"rare_fate_dice") > 0 and _dice_damage_mod == null:
		_dice_damage_mod = _make_modifier(&"damage_mult", StatModifierResource.Op.ADD_PERCENT, 0.0)
		_dice_damage_mod.source = &"relic_dice_damage"
		player.weapon.stats.add_modifier(_dice_damage_mod)

		_dice_rate_mod = _make_modifier(&"fire_rate_final", StatModifierResource.Op.MULTIPLY, 1.0)
		_dice_rate_mod.source = &"relic_dice_rate"
		player.weapon.stats.add_modifier(_dice_rate_mod)

		_dice_crit_mod = _make_modifier(&"crit_damage", StatModifierResource.Op.FLAT, 0.0)
		_dice_crit_mod.source = &"relic_dice_crit"
		player.stats.add_modifier(_dice_crit_mod)
		_roll_dice()


func _update_energy_buff() -> void:
	if _energy_buff_mod != null:
		_energy_buff_mod.value = 0.10 * float(_energy_buff_timers.size())
	if _energy_rate_mod != null:
		_energy_rate_mod.value = 0.05 * float(_energy_buff_timers.size())


func _tick_speed_rate() -> void:
	if _speed_rate_mod != null:
		# 每 10% 移速加成转换为 5% 最终射速；按有效速度上限结算。
		var move_bonus := maxf(0.0, player.effective_move_speed() / Player.MOVE_SPEED - 1.0)
		_speed_rate_mod.value = 1.0 + move_bonus * 0.5


func _tick_pointed_vessel() -> void:
	if _pointed_damage_mod == null or player == null or not is_instance_valid(player):
		return
	var missing_halves := maxi(0, roundi((player.max_health - player.health) * 2.0))
	var doubled := 2.0 if is_unlocked(&"path_demon_4") else 1.0
	_pointed_damage_mod.value = float(missing_halves) * 5.0 * doubled
	_pointed_rate_mod.value = float(missing_halves) * 0.03 * doubled


func _tick_giant_scaling() -> void:
	if _giant_damage_mod == null:
		return
	var growth := maxf(0.0, player.stats.get_value(&"body_scale") - 1.0)
	_giant_damage_mod.value = growth
	_giant_size_mod.value = growth * 0.5


func _make_modifier(stat: StringName, op: int, value: float) -> StatModifierResource:
	var modifier := StatModifierResource.new()
	modifier.stat = stat
	modifier.op = op
	modifier.value = value
	return modifier


func _pick_branch(branches: Dictionary, keys: Array) -> StringName:
	var total := 0.0
	for key in keys:
		var list: Array = branches[key]
		for node in list:
			total += maxf(0.01, (node as SkillNodeResource).weight) * _branch_offer_bonus(StringName(key))

	var roll := RunState.rng.randf() * total
	for key in keys:
		var list: Array = branches[key]
		for node in list:
			roll -= maxf(0.01, (node as SkillNodeResource).weight) * _branch_offer_bonus(StringName(key))
			if roll <= 0.0:
				return StringName(key)

	return StringName(keys.back())


func _branch_offer_bonus(branch: StringName) -> float:
	for chosen: SkillNodeResource in unlocked.values():
		if chosen.branch == branch:
			return 1.5
	return 1.0


func _pick_node(list: Array) -> SkillNodeResource:
	var total := 0.0
	for node in list:
		total += maxf(0.01, (node as SkillNodeResource).weight)

	var roll := RunState.rng.randf() * total
	for node in list:
		roll -= maxf(0.01, (node as SkillNodeResource).weight)
		if roll <= 0.0:
			return node as SkillNodeResource

	return list.back() as SkillNodeResource
