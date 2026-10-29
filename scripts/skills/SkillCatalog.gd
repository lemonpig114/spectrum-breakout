class_name SkillCatalog
extends RefCounted

## 技能树与恶魔/天使遗物的唯一数据源。
##
## 每一条线 4 阶：
##   1 阶无前置；2、3 阶只要求 1 阶；4 阶要求 2 阶与 3 阶都点亮。
## 数值类能力通过 modifiers 写入武器/玩家 StatBlock；
## 结算类能力（暴击、闪避、元素、溅射、灵魂等）由 Skills 根据节点 id 结算。

const T_W := StatModifierResource.Target.WEAPON
const T_P := StatModifierResource.Target.PLAYER

const OP_FLAT := StatModifierResource.Op.FLAT
const OP_ADD := StatModifierResource.Op.ADD_PERCENT
const OP_MUL := StatModifierResource.Op.MULTIPLY


static func build() -> Array[SkillNodeResource]:
	var nodes: Array[SkillNodeResource] = []

	var pre_blade_t1: Array[StringName] = [&"fire_1"]
	var pre_blade_t4: Array[StringName] = [&"fire_2", &"fire_3"]

	# ── 1. 射速线 ────────────────────────────────────────────────
	nodes.append(_node(
		&"fire_1", "扳机联动", "+25% 射速",
		&"fire_rate", "射速", 1, [],
		[_mod(&"fire_rate_mult", OP_ADD, 0.25, T_W)], [&"fire_rate"]
	))
	nodes.append(_node(
		&"fire_2", "过载扳机", "+40% 射速\n-20% 伤害倍率",
		&"fire_rate", "射速", 2, pre_blade_t1,
		[
			_mod(&"fire_rate_mult", OP_ADD, 0.40, T_W),
			_mod(&"damage_mult", OP_ADD, -0.20, T_W),
		], [&"fire_rate"]
	))
	nodes.append(_node(
		&"fire_3", "弹幕扩散", "+30% 射速\n+7° 射击散布",
		&"fire_rate", "射速", 3, pre_blade_t1,
		[
			_mod(&"fire_rate_mult", OP_ADD, 0.30, T_W),
			_mod(&"spread_degrees", OP_FLAT, 7.0, T_W),
		], [&"fire_rate"]
	))
	nodes.append(_node(
		&"fire_4", "无限扳机", "+20% 射速（最终乘算）\n射速上限提升至原先三倍",
		&"fire_rate", "射速", 4, pre_blade_t4,
		[_mod(&"fire_rate_final", OP_MUL, 1.20, T_W)], [&"fire_rate", &"fire_cap"]
	))

	# ── 2. 高伤害线 ──────────────────────────────────────────────
	var heavy_t1: Array[StringName] = [&"heavy_1"]
	var heavy_t4: Array[StringName] = [&"heavy_2", &"heavy_3"]

	nodes.append(_node(
		&"heavy_1", "加厚弹头", "+10 基础伤害\n+20% 攻击倍率",
		&"heavy", "重击", 1, [],
		[_mod(&"damage", OP_FLAT, 10.0, T_W), _mod(&"damage_mult", OP_ADD, 0.20, T_W)], [&"heavy"]
	))
	nodes.append(_node(
		&"heavy_2", "重型弹芯", "+50% 攻击倍率\n-20% 射速\n+20% 子弹大小\n命中击退小怪",
		&"heavy", "重击", 2, heavy_t1,
		[
			_mod(&"damage_mult", OP_ADD, 0.50, T_W),
			_mod(&"fire_rate_mult", OP_ADD, -0.20, T_W),
			_mod(&"projectile_size", OP_ADD, 0.20, T_W),
		], [&"heavy"]
	))
	nodes.append(_node(
		&"heavy_3", "破甲重击", "+1 穿透\n+20% 攻击倍率",
		&"heavy", "重击", 3, heavy_t1,
		[
			_mod(&"damage_mult", OP_ADD, 0.20, T_W),
			_mod(&"pierce", OP_FLAT, 1.0, T_W),
		], [&"heavy"]
	))
	nodes.append(_node(
		&"heavy_4", "五秒处刑",
		"+20% 攻击倍率\n+20% 绝对攻击倍率\n每 5 秒蓄力重弹：+40 基础伤害、最终伤害 ×2.5、弹体 +50%",
		&"heavy", "重击", 4, heavy_t4,
		[_mod(&"damage_mult", OP_ADD, 0.20, T_W), _mod(&"damage_final", OP_MUL, 1.20, T_W)], [&"heavy", &"heavy_shot"]
	))

	# ── 3. 能量线 ────────────────────────────────────────────────
	var energy_t1: Array[StringName] = [&"energy_1"]
	var energy_t4: Array[StringName] = [&"energy_2", &"energy_3"]

	nodes.append(_node(
		&"energy_1", "储能核心", "能量上限 +1\n能量回复速度 +30%",
		&"energy", "能量", 1, [], [], [&"energy"]
	))
	nodes.append(_node(
		&"energy_2", "能量转化", "每消耗 1 点能量，伤害倍率 +10%、射速 +5%，持续 5 秒，各层独立计时\n能量回复速度 +10%",
		&"energy", "能量", 2, energy_t1, [], [&"energy", &"energy_spend_damage", &"fire_rate"]
	))
	nodes.append(_node(
		&"energy_3", "低能超载", "能量低于 50% 时，回复速度 +50%\n能量上限 +1",
		&"energy", "能量", 3, energy_t1, [], [&"energy"]
	))
	nodes.append(_node(
		&"energy_4", "能量回流", "能量上限 +3\n每次消耗能量有 20% 概率回满能量",
		&"energy", "能量", 4, energy_t4, [], [&"energy"]
	))

	# ── 4. 速度线 ────────────────────────────────────────────────
	var speed_t1: Array[StringName] = [&"speed_1"]
	var speed_t4: Array[StringName] = [&"speed_2", &"speed_3"]

	nodes.append(_node(
		&"speed_1", "轻步", "移速 +20%\n射速 +10%",
		&"speed", "速度", 1, [],
		[_mod(&"move_speed", OP_ADD, 0.20, T_P), _mod(&"fire_rate_mult", OP_ADD, 0.10, T_W)], [&"speed"]
	))
	nodes.append(_node(
		&"speed_2", "疾影", "体型 -20%\n移速 +10%\n射速 +20%",
		&"speed", "速度", 2, speed_t1,
		[
			_mod(&"move_speed", OP_ADD, 0.10, T_P),
			_mod(&"fire_rate_mult", OP_ADD, 0.20, T_W),
		], [&"speed", &"small_body"]
	))
	nodes.append(_node(
		&"speed_3", "流线体", "移速每 +10%，绝对射速倍率 +5%\n移速 +20%",
		&"speed", "速度", 3, speed_t1,
		[_mod(&"move_speed", OP_ADD, 0.20, T_P)], [&"speed", &"speed_to_rate"]
	))
	nodes.append(_node(
		&"speed_4", "突破极速",
		"移速上限提高至 1.3 倍\n每移动约 4000 像素，获得 2 秒加速与无敌穿行",
		&"speed", "速度", 4, speed_t4, [], [&"speed", &"distance_burst"]
	))

	# ── 5. 恶魔 / 天使线（二选一） ───────────────────────────────
	_add_path_nodes(nodes, &"demon", "恶魔")
	_add_path_nodes(nodes, &"angel", "天使")

	# ── 6. 经验线 ────────────────────────────────────────────────
	var xp_t1: Array[StringName] = [&"xp_1"]
	var xp_t4: Array[StringName] = [&"xp_2", &"xp_3"]

	nodes.append(_node(
		&"xp_1", "求知", "经验获取 +20%\n拾取范围 +50%",
		&"xp", "经验", 1, [],
		[_mod(&"xp_gain", OP_FLAT, 0.20, T_P)], [&"xp"]
	))
	nodes.append(_node(
		&"xp_2", "拾金得智", "拾取金币时，50% 概率获得 1 经验",
		&"xp", "经验", 2, xp_t1, [], [&"xp", &"gold_to_xp"]
	))
	nodes.append(_node(
		&"xp_3", "博览", "经验获取 +30%",
		&"xp", "经验", 3, xp_t1,
		[_mod(&"xp_gain", OP_FLAT, 0.30, T_P)], [&"xp"]
	))
	nodes.append(_node(
		&"xp_4", "全知", "经验球自动吸取，范围无限\n经验获取绝对 +20%",
		&"xp", "经验", 4, xp_t4,
		[_mod(&"xp_gain", OP_FLAT, 0.20, T_P)], [&"xp", &"xp_auto_collect"]
	))

	# ── 7. 金币线 ────────────────────────────────────────────────
	var gold_t1: Array[StringName] = [&"gold_1"]
	var gold_t4: Array[StringName] = [&"gold_2", &"gold_3"]

	nodes.append(_node(
		&"gold_1", "贪婪", "金币获取 +25%\n拾取范围 +50%",
		&"gold", "金币", 1, [],
		[_mod(&"gold_gain", OP_FLAT, 0.25, T_P)], [&"gold"]
	))
	nodes.append(_node(
		&"gold_2", "战利品", "击杀怪物额外获得 1 金币",
		&"gold", "金币", 2, gold_t1, [], [&"gold", &"kill_gold"]
	))
	nodes.append(_node(
		&"gold_3", "磁吸", "金币自动吸取，范围无限",
		&"gold", "金币", 3, gold_t1, [], [&"gold", &"gold_auto_collect"]
	))
	nodes.append(_node(
		&"gold_4", "点石成金", "攻击命中 20% 概率掉落 1 金币\n金币获取绝对 +20%",
		&"gold", "金币", 4, gold_t4,
		[_mod(&"gold_gain", OP_FLAT, 0.20, T_P)], [&"gold", &"hit_gold"]
	))

	# ── 8. 灵魂线 ────────────────────────────────────────────────
	var soul_t1: Array[StringName] = [&"soul_1"]
	var soul_t4: Array[StringName] = [&"soul_2", &"soul_3"]

	nodes.append(_node(
		&"soul_1", "灵魂震荡", "每 3 秒对范围内敌人造成真实伤害\n伤害随灵魂数增加",
		&"soul", "灵魂", 1, [], [], [&"soul"]
	))
	nodes.append(_node(
		&"soul_2", "灵魂共鸣", "灵魂伤害倍率提升至 1.7 倍",
		&"soul", "灵魂", 2, soul_t1, [], [&"soul"]
	))
	nodes.append(_node(
		&"soul_3", "灵魂领域", "范围 +50%\n间隔从 3 秒缩短到 2 秒",
		&"soul", "灵魂", 3, soul_t1, [], [&"soul"]
	))
	nodes.append(_node(
		&"soul_4", "灵魂汲取", "灵魂冲击击杀获得双倍灵魂\n冲击伤害按双倍灵魂数计算",
		&"soul", "灵魂", 4, soul_t4, [], [&"soul", &"soul_growth"]
	))

	# ── 9. 溅射线 ────────────────────────────────────────────────
	var splash_t1: Array[StringName] = [&"splash_1"]
	var splash_t4: Array[StringName] = [&"splash_2", &"splash_3"]

	nodes.append(_node(
		&"splash_1", "冲击扩散", "命中首个敌人或穿透归零时，造成 40% 伤害的溅射\n射速 -20%",
		&"splash", "溅射", 1, [],
		[_mod(&"fire_rate_mult", OP_ADD, -0.20, T_W)], [&"splash"]
	))
	nodes.append(_node(
		&"splash_2", "激波", "溅射伤害提升至 60%",
		&"splash", "溅射", 2, splash_t1, [], [&"splash"]
	))
	nodes.append(_node(
		&"splash_3", "广域爆散", "溅射范围 +50%\n基础伤害 -5",
		&"splash", "溅射", 3, splash_t1,
		[_mod(&"damage", OP_FLAT, -5.0, T_W)], [&"splash"]
	))
	nodes.append(_node(
		&"splash_4", "连锁崩解", "每次命中都会触发溅射\n绝对伤害倍率 -10%\n绝对射速倍率 -20%",
		&"splash", "溅射", 4, splash_t4,
		[
			_mod(&"damage_final", OP_MUL, 0.90, T_W),
			_mod(&"fire_rate_final", OP_MUL, 0.80, T_W),
		], [&"splash"]
	))

	# ── 10. 弱点线 ───────────────────────────────────────────────
	var weak_t1: Array[StringName] = [&"weak_1"]
	var weak_t4: Array[StringName] = [&"weak_2", &"weak_3"]

	nodes.append(_node(
		&"weak_1", "弱点洞察", "弱点伤害倍率从 150% 提升到 200%",
		&"weakness", "弱点", 1, [],
		[_mod(&"weakness_multiplier", OP_FLAT, 0.50, T_P)], [&"weakness"]
	))
	nodes.append(_node(
		&"weak_2", "元素增幅", "元素伤害 +30%",
		&"weakness", "弱点", 2, weak_t1,
		[_mod(&"elemental_damage", OP_FLAT, 0.30, T_P)], [&"weakness"]
	))
	nodes.append(_node(
		&"weak_3", "元素附着",
		"弱点命中附加元素效果：\n红：200% 基础伤害的灼伤（2 秒内每半秒结算）\n绿：45% 基础伤害/秒的中毒（每半秒结算，层数不消失）\n蓝：25% 减速，冰附着追加 20% 冰裂伤害",
		&"weakness", "弱点", 3, weak_t1, [], [&"weakness", &"elemental"]
	))
	nodes.append(_node(
		&"weak_4", "处决", "弱点命中生命低于 15% 的普通敌人直接斩杀\nBoss 为 5%",
		&"weakness", "弱点", 4, weak_t4, [], [&"weakness", &"execute"]
	))

	# ── 11. 暴击线 ───────────────────────────────────────────────
	var crit_t1: Array[StringName] = [&"crit_1"]
	var crit_t4: Array[StringName] = [&"crit_2", &"crit_3"]

	nodes.append(_node(
		&"crit_1", "会心", "暴击率 +20%\n暴击伤害 +20%",
		&"crit", "暴击", 1, [],
		[
			_mod(&"crit_chance", OP_FLAT, 0.20, T_P),
			_mod(&"crit_damage", OP_FLAT, 0.20, T_P),
		], [&"crit"]
	))
	nodes.append(_node(
		&"crit_2", "致命", "暴击率 +25%\n暴击伤害 +50%",
		&"crit", "暴击", 2, crit_t1,
		[
			_mod(&"crit_chance", OP_FLAT, 0.25, T_P),
			_mod(&"crit_damage", OP_FLAT, 0.50, T_P),
		], [&"crit"]
	))
	nodes.append(_node(
		&"crit_3", "痛处",
		"对单个敌人：暴击率 + 已损失生命百分比 / 2\n暴击伤害 + 已损失生命百分比 × 2",
		&"crit", "暴击", 3, crit_t1, [], [&"crit"]
	))
	nodes.append(_node(
		&"crit_4", "超暴击",
		"获得 1% 超暴击概率\n溢出暴击率转化为超暴击概率\n超暴击吃两次暴伤加成，且强制视为弱点伤害",
		&"crit", "暴击", 4, crit_t4, [], [&"crit", &"super_crit"]
	))

	# ── 12. 散弹线 ────────────────────────────────────────────────
	var shotgun_t1: Array[StringName] = [&"shotgun_1"]
	var shotgun_t4: Array[StringName] = [&"shotgun_2", &"shotgun_3"]

	nodes.append(_node(
		&"shotgun_1", "散弹", "+1 子弹\n+10° 射击散布\n伤害倍率 -20%\n射速 -10%",
		&"shotgun", "散弹", 1, [],
		[
			_mod(&"projectiles_per_shot", OP_FLAT, 1.0, T_W),
			_mod(&"spread_degrees", OP_FLAT, 10.0, T_W),
			_mod(&"damage_mult", OP_ADD, -0.20, T_W),
			_mod(&"fire_rate_mult", OP_ADD, -0.10, T_W),
		], [&"shotgun"]
	))
	nodes.append(_node(
		&"shotgun_2", "裂片", "敌人死亡时裂出 3 枚 35% 伤害的小子弹",
		&"shotgun", "散弹", 2, shotgun_t1, [], [&"shotgun", &"death_burst"]
	))
	nodes.append(_node(
		&"shotgun_3", "扩容弹匣", "+1 子弹\n+1 穿透\n+5° 射击散布",
		&"shotgun", "散弹", 3, shotgun_t1,
		[
			_mod(&"projectiles_per_shot", OP_FLAT, 1.0, T_W),
			_mod(&"pierce", OP_FLAT, 1.0, T_W),
			_mod(&"spread_degrees", OP_FLAT, 5.0, T_W),
		], [&"shotgun"]
	))
	nodes.append(_node(
		&"shotgun_4", "双倍装填", "伤害倍率 -20%\n射速 -20%\n子弹数翻倍",
		&"shotgun", "散弹", 4, shotgun_t4,
		[
			_mod(&"damage_mult", OP_ADD, -0.20, T_W),
			_mod(&"fire_rate_mult", OP_ADD, -0.20, T_W),
			_mod(&"projectiles_per_shot", OP_MUL, 2.0, T_W),
		], [&"shotgun"]
	))

	# ── 13. 幸运线 ────────────────────────────────────────────────
	var luck_t1: Array[StringName] = [&"luck_1"]
	var luck_t4: Array[StringName] = [&"luck_2", &"luck_3"]

	nodes.append(_node(
		&"luck_1", "幸运",
		"幸运 +12\n解锁幸运遗物；击杀有概率掉落宝箱\n宝箱可开出遗物 / 经验 / 金币",
		&"luck", "幸运", 1, [],
		[_mod(&"luck", OP_FLAT, 12.0, T_P)], [&"luck", &"chest"]
	))
	nodes.append(_node(
		&"luck_2", "好运", "幸运 +12\n宝箱出遗物概率 +5%",
		&"luck", "幸运", 2, luck_t1,
		[_mod(&"luck", OP_FLAT, 12.0, T_P)], [&"luck", &"chest_relic"]
	))
	nodes.append(_node(
		&"luck_3", "天选", "幸运 +16\n发现一个蓝色~橙色幸运遗物，可选择拾取或丢弃",
		&"luck", "幸运", 3, luck_t1,
		[_mod(&"luck", OP_FLAT, 16.0, T_P)], [&"luck", &"lucky_gift"]
	))
	nodes.append(_node(
		&"luck_4", "锦鲤", "发现宝箱时\n幸运 +6，持续 60 秒（重复触发刷新时长）",
		&"luck", "幸运", 4, luck_t4, [], [&"luck", &"temp_luck"]
	))

	# ── 14. 脆弱线 ────────────────────────────────────────────────
	var fragile_t1: Array[StringName] = [&"fragile_1"]
	var fragile_t4: Array[StringName] = [&"fragile_2", &"fragile_3"]
	nodes.append(_node(&"fragile_1", "裂痕", "首次伤害附加 20% 脆弱，随时间衰减",
		&"fragile", "脆弱", 1, [], [], [&"fragile"]))
	nodes.append(_node(&"fragile_2", "深裂", "首次脆弱提高至 35%",
		&"fragile", "脆弱", 2, fragile_t1, [], [&"fragile"]))
	nodes.append(_node(&"fragile_3", "持久裂痕", "脆弱衰减速度减半",
		&"fragile", "脆弱", 3, fragile_t1, [], [&"fragile"]))
	nodes.append(_node(&"fragile_4", "连击扩裂", "每次攻击追加 0.5% 脆弱，不超过首次上限",
		&"fragile", "脆弱", 4, fragile_t4, [], [&"fragile"]))

	# ── 15. 精灵线 ────────────────────────────────────────────────
	var sprite_t1: Array[StringName] = [&"sprite_1"]
	var sprite_t4: Array[StringName] = [&"sprite_2", &"sprite_3"]
	nodes.append(_node(&"sprite_1", "灵光精灵", "召唤一只彩色精灵，冲刺冷却 2 秒\n沿途造成 300% 元素伤害",
		&"sprite", "精灵", 1, [], [], [&"sprite"]))
	nodes.append(_node(&"sprite_2", "双生灵光", "精灵数 +1\n召唤伤害倍率 +20%",
		&"sprite", "精灵", 2, sprite_t1,
		[_mod(&"summon_damage", OP_ADD, 0.20, T_P)], [&"sprite"]))
	nodes.append(_node(&"sprite_3", "璀璨俯冲", "精灵变大，冲刺范围扩大\n冲刺伤害提高至 400%",
		&"sprite", "精灵", 3, sprite_t1, [], [&"sprite"]))
	nodes.append(_node(&"sprite_4", "灵光增殖", "精灵数 +1，冲刺间隔缩短至 1.3 秒\n每次命中使该精灵基础攻击 +0.5",
		&"sprite", "精灵", 4, sprite_t4, [], [&"sprite"]))

	# ── 16. 分身线 ────────────────────────────────────────────────
	var clone_t1: Array[StringName] = [&"clone_1"]
	var clone_t4: Array[StringName] = [&"clone_2", &"clone_3"]
	nodes.append(_node(&"clone_1", "镜像", "每 15 秒召唤一名持续 15 秒的分身\n继承主武器与移动速度，最多 20 名",
		&"clone", "分身", 1, [], [], [&"clone"]))
	nodes.append(_node(&"clone_2", "共鸣镜像", "召唤伤害倍率 +40%\n召唤速度 +20%",
		&"clone", "分身", 2, clone_t1,
		[_mod(&"summon_damage", OP_ADD, 0.40, T_P)], [&"clone"]))
	nodes.append(_node(&"clone_3", "染色镜像", "分身获得色彩并主动切换\n持续时间 +5 秒",
		&"clone", "分身", 3, clone_t1, [], [&"clone"]))
	nodes.append(_node(&"clone_4", "终末镜像", "召唤间隔变为 10 秒\n分身消失时在更大范围爆发 300% 可暴击伤害",
		&"clone", "分身", 4, clone_t4, [], [&"clone"]))

	# ── 17. 法阵线 ────────────────────────────────────────────────
	var circle_t1: Array[StringName] = [&"circle_1"]
	var circle_t4: Array[StringName] = [&"circle_2", &"circle_3"]
	nodes.append(_node(&"circle_1", "幽影法阵", "每击杀 30 名敌人生成法阵，持续 10 秒\n阵内伤害倍率 +50%，射速 +30%",
		&"circle", "法阵", 1, [], [], [&"circle"]))
	nodes.append(_node(&"circle_2", "幽影侵蚀", "阵内敌人每 0.5 秒受到灵魂伤害并减速 15%",
		&"circle", "法阵", 2, circle_t1, [], [&"circle"]))
	nodes.append(_node(&"circle_3", "广域法阵", "法阵范围扩大\n阵内绝对伤害倍率 +20%",
		&"circle", "法阵", 3, circle_t1, [], [&"circle"]))
	nodes.append(_node(&"circle_4", "魂续法阵", "阵内击杀延长法阵 0.5 秒\n法阵伤害击杀敌人时获得 1 灵魂",
		&"circle", "法阵", 4, circle_t4, [], [&"circle"]))

	# ── 18. 巨化线 ────────────────────────────────────────────────
	var giant_t1: Array[StringName] = [&"giant_1"]
	var giant_t4: Array[StringName] = [&"giant_2", &"giant_3"]
	nodes.append(_node(&"giant_1", "巨化", "生命上限 +1\n体型 +20%，移速 -5%",
		&"giant", "巨化", 1, [], [
			_mod(&"max_health", OP_FLAT, 1.0, T_P),
			_mod(&"body_scale", OP_ADD, 0.20, T_P),
			_mod(&"move_speed", OP_ADD, -0.05, T_P),
		], [&"giant"]))
	nodes.append(_node(&"giant_2", "体型动能", "体型增长转化为子弹大小与伤害倍率\n体型 +20%",
		&"giant", "巨化", 2, giant_t1, [
			_mod(&"body_scale", OP_ADD, 0.20, T_P),
		], [&"giant"]))
	nodes.append(_node(&"giant_3", "山岳之躯", "移速 -15%，体型 +40%\n伤害倍率 +30%，生命上限 +1",
		&"giant", "巨化", 3, giant_t1, [
			_mod(&"move_speed", OP_ADD, -0.15, T_P),
			_mod(&"body_scale", OP_ADD, 0.40, T_P),
			_mod(&"damage_mult", OP_ADD, 0.30, T_W),
			_mod(&"max_health", OP_FLAT, 1.0, T_P),
		], [&"giant"]))
	nodes.append(_node(&"giant_4", "不朽巨躯", "生命上限 +1，移速 -10%\n每击杀 300 名敌人回复半颗心",
		&"giant", "巨化", 4, giant_t4, [
			_mod(&"max_health", OP_FLAT, 1.0, T_P),
			_mod(&"move_speed", OP_ADD, -0.10, T_P),
		], [&"giant"]))

	return nodes


const RELIC_BRIEFS := {
	&"demon_pointed_vessel": "以生命换取攻击和射速",
	&"demon_soul_blade": "射击有机会追加灵魂伤害",
	&"angel_halo": "全面强化战斗属性",
	&"angel_guardian": "免除接下来的两次伤害",
	&"dust_knife": "暴击伤害提升",
	&"dust_paper_star": "暴击更容易触发",
	&"dust_iron_glove": "伤害提升，射速降低",
	&"dust_cloth_glove": "射速提升，伤害降低",
	&"dust_apple": "立即回复两颗心",
	&"dust_blunt_blade": "伤害提升，拾取时损失一颗心",
	&"dust_running_shoes": "移动更快",
	&"dust_blindfold": "射速提升，暴击能力降低",
	&"dust_lottery": "小概率赢得三千金币",
	&"dust_magnet": "拾取范围扩大",
	&"rare_bond": "持续获得金币",
	&"rare_four_leaf": "幸运提升",
	&"rare_three_leaf": "暴击能力提升，幸运降低",
	&"rare_dumbbell": "基础伤害提升",
	&"rare_bullet_shell": "攻击有机会连续开火",
	&"rare_reroll": "每次进店获得免费重掷",
	&"epic_six_sided_die": "升级可重选技能，每次进店免费刷新",
	&"rare_golden_apple": "立即回满生命",
	&"rare_adrenaline": "受伤后短暂提升伤害与射速",
	&"rare_gold_nugget": "立即获得一笔金币",
	&"rare_feast": "生命与伤害提升，移速降低、体型增大",
	&"rare_fate_dice": "定时掷骰，火力随点数起伏",
	&"rare_prism_lens": "三种颜色的攻击伤害提升",
	&"rare_flint": "暴击能力提升",
	&"rare_poison_arrow": "射击有机会追加绿色元素伤害",
	&"rare_frost_arrow": "射击有机会追加蓝色元素伤害",
	&"rare_burning_arrow": "射击有机会追加红色元素伤害",
	&"rare_dictionary": "经验获取提升",
	&"rare_silver_coin": "金币获取提升",
	&"rare_cracked_armor": "损失的生命越多，伤害越高",
	&"rare_battery": "能量回复加快",
	&"rare_impact_releaser": "切色时冲击附近被克制的敌人",
	&"rare_dog_food": "召唤物伤害提升",
	&"rare_ounce_soul": "立即获得五十点灵魂",
	&"rare_mystery_gift": "随机获得一件尘灰至炬火遗物",
	&"rare_high_bond": "负债换取更高固定收益",
	&"rare_bloody_bandage": "受伤后的无敌时间延长",
	&"epic_health_crystal": "生命上限增加一颗心",
	&"epic_vip_card": "商店多一格，每次进店多两次刷新",
	&"epic_war_arrow": "暴击率与暴击伤害提升",
	&"epic_shield_generator": "切色获得一次同色攻击护盾",
	&"epic_classic_revolver": "切色时环射十五枚子弹",
	&"epic_prism": "弱点伤害倍率提升",
	&"epic_water_candle": "敌人刷新量增加",
	&"epic_travel_journal": "移动一段距离获得金币和经验",
	&"epic_lucky_coin": "幸运与金币收益提升",
	&"legendary_rainbow_clover": "幸运提升，更容易开出遗物",
}


static func build_relics() -> Array[RelicResource]:
	var relics: Array[RelicResource] = []

	relics.append(_relic(
		&"demon_pointed_vessel", "尖锐祭器", "拾取后当前生命变为半颗\n每失去半颗心，基础攻击 +5、射速 +3%",
		&"demon", RelicResource.RARITY_RARE, [], 50
	))
	relics.append(_relic(
		&"demon_soul_blade", "噬魂刀", "子弹 20% 概率追加 0.25×(灵魂数+5) 灵魂伤害\n造成击杀时获得 1 灵魂",
		&"demon", RelicResource.RARITY_EPIC, [], 90
	))
	relics.append(_relic(
		&"angel_halo", "光环", "移速 +10%、暴击率 +5%、幸运 +10\n基础攻击 +3、射速 +10%、暴击伤害 +10%",
		&"angel", RelicResource.RARITY_RARE,
		[
			_mod(&"move_speed", OP_ADD, 0.10, T_P),
			_mod(&"crit_chance", OP_FLAT, 0.05, T_P),
			_mod(&"luck", OP_FLAT, 10.0, T_P),
			_mod(&"damage", OP_FLAT, 3.0, T_W),
			_mod(&"fire_rate_mult", OP_ADD, 0.10, T_W),
			_mod(&"crit_damage", OP_FLAT, 0.10, T_P),
		], 65
	))
	relics.append(_relic(
		&"angel_guardian", "守护", "获得两层护盾，每层免除一次伤害",
		&"angel", RelicResource.RARITY_RARE, [], 55
	))

	# ── 尘灰遗物：轻微的正负杠杆，商店最低一档 ──
	relics.append(_relic(
		&"dust_knife", "小刀", "暴击伤害 +15%",
		&"", RelicResource.RARITY_DUST,
		[_mod(&"crit_damage", OP_FLAT, 0.15, T_P)],
		12, false, 0.0, 0.0, false, false, 3
	))
	relics.append(_relic(
		&"dust_paper_star", "纸星星", "暴击率 +5%",
		&"", RelicResource.RARITY_DUST,
		[_mod(&"crit_chance", OP_FLAT, 0.05, T_P)],
		12
	))
	relics.append(_relic(
		&"dust_iron_glove", "铁手套", "基础伤害 +3\n射速 -5%",
		&"", RelicResource.RARITY_DUST,
		[
			_mod(&"damage", OP_FLAT, 3.0, T_W),
			_mod(&"fire_rate_mult", OP_ADD, -0.05, T_W),
		],
		14
	))
	relics.append(_relic(
		&"dust_cloth_glove", "布手套", "基础伤害 -3\n射速 +15%",
		&"", RelicResource.RARITY_DUST,
		[
			_mod(&"damage", OP_FLAT, -3.0, T_W),
			_mod(&"fire_rate_mult", OP_ADD, 0.15, T_W),
		],
		12
	))
	relics.append(_relic(
		&"dust_apple", "苹果", "立即回复 2 颗心\n（一次性，不占遗物栏）",
		&"", RelicResource.RARITY_DUST,
		[],
		8, true, 0.0, 0.0, false, false, 0, 2.0
	))
	relics.append(_relic(
		&"dust_blunt_blade", "钝刀片", "拾取时失去 1 颗心\n基础伤害 +5",
		&"", RelicResource.RARITY_DUST,
		[_mod(&"damage", OP_FLAT, 5.0, T_W)],
		10
	))
	relics[-1].pickup_health_loss_hearts = 1.0
	relics.append(_relic(
		&"dust_running_shoes", "跑鞋", "移速 +5%",
		&"", RelicResource.RARITY_DUST,
		[_mod(&"move_speed", OP_ADD, 0.05, T_P)],
		10, false, 0.0, 0.0, false, false, 3
	))
	relics.append(_relic(
		&"dust_blindfold", "蒙眼布条", "射速 +20%\n暴击率 -3%\n暴击伤害 -7%",
		&"", RelicResource.RARITY_DUST,
		[
			_mod(&"fire_rate_mult", OP_ADD, 0.20, T_W),
			_mod(&"crit_chance", OP_FLAT, -0.03, T_P),
			_mod(&"crit_damage", OP_FLAT, -0.07, T_P),
		],
		14
	))
	relics.append(_relic(
		&"dust_lottery", "彩票", "幸运遗物：3% 基础概率赢得 3000 金币\n幸运提高中奖概率，最高 9%",
		&"", RelicResource.RARITY_DUST,
		[],
		18, true, 0.0, 0.0, false, true
	))
	relics.append(_relic(
		&"dust_magnet", "吸铁石", "拾取范围 +30%\n金币线或经验线点满后不再出现",
		&"", RelicResource.RARITY_DUST,
		[],
		18
	))

	# ── 微光（蓝）：生命/经济/攻击方式的小遗物 ──
	relics.append(_relic(
		&"rare_bond", "债券", "拾取后金币 -300，可负债\n每秒获得 3 金币",
		&"", RelicResource.RARITY_RARE,
		[_mod(&"gold_income", OP_FLAT, 3.0, T_P)],
		45
	))
	relics.append(_relic(
		&"rare_four_leaf", "四叶草", "幸运遗物：幸运 +4",
		&"", RelicResource.RARITY_RARE,
		[_mod(&"luck", OP_FLAT, 4.0, T_P)],
		45, false, 0.0, 0.0, false, true
	))
	relics.append(_relic(
		&"rare_three_leaf", "三叶草", "幸运遗物：幸运 -3\n暴击率 +20%\n暴击伤害 +20%",
		&"", RelicResource.RARITY_RARE,
		[
			_mod(&"luck", OP_FLAT, -3.0, T_P),
			_mod(&"crit_chance", OP_FLAT, 0.20, T_P),
			_mod(&"crit_damage", OP_FLAT, 0.20, T_P),
		],
		50, false, 0.0, 0.0, false, true
	))
	relics.append(_relic(
		&"rare_dumbbell", "哑铃", "基础伤害 +6",
		&"", RelicResource.RARITY_RARE,
		[_mod(&"damage", OP_FLAT, 6.0, T_W)],
		45
	))
	relics.append(_relic(
		&"rare_bullet_shell", "子弹壳", "攻击有 10% 概率连射\n下一次攻击间隔变为射速上限间隔",
		&"", RelicResource.RARITY_RARE,
		[],
		55, false, 0.0, 0.0, false, false, 3
	))
	relics.append(_relic(
		&"rare_reroll", "刷新", "每次进入商店，免费重掷 +1 次",
		&"", RelicResource.RARITY_RARE,
		[],
		45, false, 0.0, 0.0, false, false, 10
	))
	relics.append(_relic(
		&"rare_golden_apple", "金苹果", "立即回满生命",
		&"", RelicResource.RARITY_RARE,
		[],
		48
	))
	relics.append(_relic(
		&"rare_adrenaline", "肾上腺素",
		"受伤后 20 秒内：\n伤害 +100%、射速 +50%\n加成随时间线性衰减",
		&"", RelicResource.RARITY_RARE,
		[],
		58
	))
	relics.append(_relic(
		&"rare_gold_nugget", "金块", "立即获得 500 金币\n（仅能从幸运宝箱中开出）",
		&"", RelicResource.RARITY_RARE,
		[],
		0, false, 0.0, 0.0, false, false, 0, 0.0, 500, true
	))
	relics.append(_relic(
		&"rare_feast", "大餐",
		"生命上限 +1 颗、回复 1 颗心\n移速 -10%、伤害倍率 +30%\n体型略微增大",
		&"", RelicResource.RARITY_EPIC,
		[
			_mod(&"max_health", OP_FLAT, 1.0, T_P),
			_mod(&"move_speed", OP_ADD, -0.10, T_P),
			_mod(&"damage_mult", OP_ADD, 0.30, T_W),
			_mod(&"body_scale", OP_ADD, 0.08, T_P),
		],
		65, false, 0.0, 0.0, false, false, 3, 1.0
	))
	relics.append(_relic(
		&"rare_fate_dice", "命运骰子",
		"每 10 秒投掷一次六面骰：\n1 伤害 -20% / 射速 -20%\n2 伤害 -20%  3 无事发生\n4 伤害 +10%\n5 伤害 +20% / 射速 +20%\n6 伤害 +30% / 射速 +30%\n   暴击伤害 +50%",
		&"", RelicResource.RARITY_RARE,
		[],
		70, false, 0.0, 0.0, false, false, 2
	))
	relics.append(_relic(
		&"rare_prism_lens", "三色透镜", "所有颜色攻击的伤害倍率 +15%",
		&"", RelicResource.RARITY_RARE, [], 55
	))
	relics.append(_relic(
		&"rare_flint", "打火石", "暴击率 +5%，暴击伤害 +15%",
		&"", RelicResource.RARITY_RARE,
		[_mod(&"crit_chance", OP_FLAT, 0.05, T_P), _mod(&"crit_damage", OP_FLAT, 0.15, T_P)],
		45, false, 0.0, 0.0, false, false, 3
	))
	relics.append(_relic(
		&"rare_poison_arrow", "剧毒箭矢", "攻击 10% 概率追加 100% 绿色元素伤害",
		&"", RelicResource.RARITY_RARE, [], 55, false, 0.0, 0.0, true
	))
	relics[-1].offer_weight = 0.5
	relics.append(_relic(
		&"rare_frost_arrow", "冰霜箭矢", "攻击 10% 概率追加 100% 蓝色元素伤害",
		&"", RelicResource.RARITY_RARE, [], 55, false, 0.0, 0.0, true
	))
	relics[-1].offer_weight = 0.5
	relics.append(_relic(
		&"rare_burning_arrow", "灼烧箭矢", "攻击 10% 概率追加 100% 红色元素伤害",
		&"", RelicResource.RARITY_RARE, [], 55, false, 0.0, 0.0, true
	))
	relics[-1].offer_weight = 0.5
	relics.append(_relic(
		&"rare_dictionary", "字典", "经验获取 +15%",
		&"", RelicResource.RARITY_RARE,
		[_mod(&"xp_gain", OP_ADD, 0.15, T_P)], 48
	))
	relics.append(_relic(
		&"rare_silver_coin", "银币", "金币获取 +15%",
		&"", RelicResource.RARITY_RARE,
		[_mod(&"gold_gain", OP_ADD, 0.15, T_P)], 48
	))
	relics.append(_relic(
		&"rare_cracked_armor", "破裂盔甲", "每颗已损失的心提供\n伤害倍率 +5%",
		&"", RelicResource.RARITY_RARE,
		[],
		55
	))
	relics.append(_relic(
		&"rare_battery", "小电池", "能量回复速度 +20%",
		&"", RelicResource.RARITY_RARE,
		[],
		45
	))
	relics.append(_relic(
		&"rare_impact_releaser", "冲击释放器",
		"切换形态后，对周围 340 范围内\n被新形态克制的敌人造成\n200% 弱点伤害\n可暴击，不会超暴击（可叠加）",
		&"", RelicResource.RARITY_RARE,
		[],
		60
	))
	relics.append(_relic(
		&"rare_dog_food", "狗粮", "召唤物伤害倍率 +15%",
		&"", RelicResource.RARITY_RARE,
		[_mod(&"summon_damage", OP_ADD, 0.15, T_P)], 50
	))
	relics.append(_relic(
		&"rare_ounce_soul", "一盎司灵魂", "立即获得 50 点灵魂",
		&"", RelicResource.RARITY_RARE, [], 55
	))
	relics.append(_relic(
		&"rare_mystery_gift", "神秘礼物", "随机获得一件尘灰至炬火遗物",
		&"", RelicResource.RARITY_RARE, [], 60, true
	))
	relics.append(_relic(
		&"rare_high_bond", "高额债券", "拾取后金币 -1000，可负债\n每秒固定获得 12 金币",
		&"", RelicResource.RARITY_RARE,
		[_mod(&"gold_income", OP_FLAT, 12.0, T_P)], 100
	))
	relics.append(_relic(
		&"rare_bloody_bandage", "染血绷带", "受伤后无敌时间 +1 秒",
		&"", RelicResource.RARITY_RARE, [], 65,
		false, 0.0, 0.0, false, false, 3
	))

	# ── 炬火：中后期构筑方向 ──
	relics.append(_relic(
		&"epic_weapon_cache", "武装密钥", "选择一件新武器；同种武器不会重复获得",
		&"", RelicResource.RARITY_EPIC, [], 120,
		false, 0.0, 0.0, true
	))
	relics.append(_relic(
		&"epic_health_crystal", "生命水晶", "生命上限 +1 颗心",
		&"", RelicResource.RARITY_EPIC,
		[_mod(&"max_health", OP_FLAT, 1.0, T_P)], 90
	))
	relics.append(_relic(
		&"epic_vip_card", "VIP卡", "商店货架 +1 格\n每次进店免费刷新 +2 次",
		&"", RelicResource.RARITY_EPIC, [], 110,
		false, 0.0, 0.0, true
	))
	relics.append(_relic(
		&"epic_war_arrow", "战争箭矢", "暴击率 +15%，暴击伤害 +30%",
		&"", RelicResource.RARITY_EPIC,
		[_mod(&"crit_chance", OP_FLAT, 0.15, T_P),
		_mod(&"crit_damage", OP_FLAT, 0.30, T_P)], 100,
		false, 0.0, 0.0, false, false, 3
	))
	relics.append(_relic(
		&"epic_shield_generator", "护盾发生器",
		"切换形态多消耗 1 能量，获得一次当前颜色护盾\n同色攻击免疫一次，不叠加",
		&"", RelicResource.RARITY_EPIC, [], 120,
		false, 0.0, 0.0, true
	))
	relics.append(_relic(
		&"epic_classic_revolver", "古典左轮",
		"切换形态时依次环射 15 枚普通子弹\n每多一件多转一圈",
		&"", RelicResource.RARITY_EPIC, [], 125,
		false, 0.0, 0.0, false, false, 3
	))
	relics.append(_relic(
		&"epic_prism", "棱镜", "弱点伤害倍率 +50%",
		&"", RelicResource.RARITY_EPIC,
		[_mod(&"weakness_multiplier", OP_FLAT, 0.50, T_P)], 110
	))
	relics.append(_relic(
		&"epic_water_candle", "水蜡烛", "敌人刷新量 +20%",
		&"", RelicResource.RARITY_EPIC, [], 90
	))
	relics.append(_relic(
		&"epic_travel_journal", "旅行手册", "每移动 500 像素获得 5 金币与 5 经验",
		&"", RelicResource.RARITY_EPIC, [], 95
	))

	# ── 高级幸运遗物：支撑“蓝到橙随机”的宝箱品质 ──
	relics.append(_relic(
		&"epic_six_sided_die", "六面骰",
		"每次升级的技能选择可免费重选 1 次\n每次进入商店，免费刷新 +1 次",
		&"", RelicResource.RARITY_EPIC,
		[],
		90, false, 0.0, 0.0, true
	))
	relics.append(_relic(
		&"epic_lucky_coin", "幸运币", "幸运遗物：幸运 +6\n金币获取 +10%",
		&"", RelicResource.RARITY_EPIC,
		[
			_mod(&"luck", OP_FLAT, 6.0, T_P),
			_mod(&"gold_gain", OP_ADD, 0.10, T_P),
		],
		80, false, 0.0, 0.0, false, true
	))
	relics.append(_relic(
		&"legendary_rainbow_clover", "虹彩四叶草",
		"幸运遗物：幸运 +10\n宝箱出遗物概率 +2%",
		&"", RelicResource.RARITY_LEGENDARY,
		[_mod(&"luck", OP_FLAT, 10.0, T_P)],
		140, false, 0.0, 0.0, false, true
	))

	return relics


## 恶魔/天使共用的四阶结构。
static func _add_path_nodes(nodes: Array[SkillNodeResource], side: StringName, side_name: String) -> void:
	var t1: Array[StringName] = [StringName("path_%s_1" % String(side))]
	var t4: Array[StringName] = [
		StringName("path_%s_2" % String(side)),
		StringName("path_%s_3" % String(side)),
	]
	var is_demon := side == &"demon"
	var altar_text := "恶魔祭坛" if is_demon else "天使祭坛"

	nodes.append(_node(
		StringName("path_%s_1" % String(side)),
		"%s契约" % side_name,
		"获取一个%s遗物" % side_name,
		side, side_name, 1, [], [], [side, &"path"]
	))
	nodes.append(_node(
		StringName("path_%s_2" % String(side)),
		"%s偏袒" % ("深渊" if is_demon else "天国"),
		"商店出现%s遗物" % side_name,
		side, side_name, 2, t1, [], [side, &"path", &"shop_bias"]
	))
	nodes.append(_node(
		StringName("path_%s_3" % String(side)),
		"%s印" % ("第二契" if is_demon else "第二圣"),
		"再获得一个%s遗物\n选择偏袒后解锁%s" % [side_name, altar_text],
		side, side_name, 3, t1, [], [side, &"path", &"altar"]
	))
	nodes.append(_node(
		StringName("path_%s_4" % String(side)),
		"%s化身" % side_name,
		"该系列遗物提供的属性加成翻倍",
		side, side_name, 4, t4, [], [side, &"path", &"relic_double"]
	))


static func _node(
	id: StringName,
	display_name: String,
	description: String,
	branch: StringName,
	branch_name: String,
	tier: int,
	prerequisites: Array,
	modifiers: Array,
	flags: Array = []
) -> SkillNodeResource:
	var node := SkillNodeResource.new()
	node.id = id
	node.display_name = display_name
	node.description = description
	node.branch = branch
	node.branch_name = branch_name
	node.tier = tier
	node.accent = _branch_color(branch)

	for prerequisite in prerequisites:
		node.prerequisites.append(StringName(prerequisite))
	for modifier in modifiers:
		node.modifiers.append(modifier as StatModifierResource)
	for flag in flags:
		node.flags.append(StringName(flag))

	return node


static func _relic(
	id: StringName,
	display_name: String,
	description: String,
	side: StringName,
	rarity: int,
	modifiers: Array,
	price: int = 25,
	consumable: bool = false,
	heal_ratio: float = 0.0,
	health_loss_ratio: float = 0.0,
	unique: bool = false,
	lucky: bool = false,
	max_stacks: int = 0,
	heal_hearts: float = 0.0,
	pickup_gold: int = 0,
	chest_only: bool = false
) -> RelicResource:
	var relic := RelicResource.new()
	relic.id = id
	relic.display_name = display_name
	relic.description = description
	relic.brief_description = RELIC_BRIEFS.get(id, description.get_slice("\n", 0))
	relic.side = side
	relic.rarity = rarity
	relic.price = price
	relic.consumable = consumable
	relic.pickup_heal_ratio = heal_ratio
	relic.pickup_heal_hearts = heal_hearts
	relic.pickup_health_loss_ratio = health_loss_ratio
	relic.pickup_gold = pickup_gold
	relic.chest_only = chest_only
	# 恶魔/天使遗物是契约的专属奖励，整局唯一；尘灰遗物默认可重复叠加。
	# 未来若出现其他不可重复遗物，在调用处传 unique = true。
	relic.unique = unique or side != &""
	relic.lucky = lucky
	relic.max_stacks = max_stacks
	if relic.unique:
		relic.description += "\n（唯一）"
	if max_stacks > 0:
		relic.description += "\n（最多 %d 层）" % max_stacks
	for modifier in modifiers:
		relic.modifiers.append(modifier as StatModifierResource)
	return relic


static func _mod(
	stat: StringName,
	op: int,
	value: float,
	target: int = T_W
) -> StatModifierResource:
	var modifier := StatModifierResource.new()
	modifier.stat = stat
	modifier.op = op
	modifier.value = value
	modifier.target = target
	return modifier


static func _branch_color(branch: StringName) -> Color:
	match branch:
		&"fire_rate":
			return Color(1.0, 0.38, 0.24)
		&"heavy":
			return Color(1.0, 0.20, 0.36)
		&"energy":
			return Color(0.30, 0.85, 1.0)
		&"speed":
			return Color(0.32, 1.0, 0.72)
		&"demon":
			return Color(1.0, 0.16, 0.22)
		&"angel":
			return Color(1.0, 0.86, 0.38)
		&"xp":
			return Color(0.42, 1.0, 0.46)
		&"gold":
			return Color(1.0, 0.80, 0.20)
		&"soul":
			return Color(0.76, 0.52, 1.0)
		&"splash":
			return Color(1.0, 0.56, 0.16)
		&"weakness":
			return Color(1.0, 0.36, 0.86)
		&"crit":
			return Color(0.86, 0.92, 1.0)
		&"shotgun":
			return Color(1.0, 0.62, 0.30)
		&"luck":
			return Color(0.55, 1.0, 0.62)
		&"fragile":
			return Color(1.2, 0.5, 0.9)
		&"sprite":
			return Color(0.5, 1.2, 1.4)
		&"clone":
			return Color(0.8, 0.9, 1.2)
		&"circle":
			return Color(0.7, 0.45, 1.1)
		&"giant":
			return Color(1.1, 0.75, 0.48)
	return Color.WHITE
