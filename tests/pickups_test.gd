extends Node

## 掉落系统专项无头测试：
## godot --headless --fixed-fps 60 --path . res://tests/pickups_test.tscn
##
## 覆盖：击杀不再直接结算、地面掉落需要靠近/磁吸拾取、重叠合并、
## 全屏吸取在生成时直接进入收集状态（有流光）、以及流光池溢出时奖励不丢失。
## 未拾取掉落达到上限后会丢弃旧物，不会直接结算经验。

var failures := 0
var main: Node
var player: Player
var field: PickupField


func _ready() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	main = main_scene.instantiate()
	add_child(main)

	await get_tree().create_timer(2.4).timeout
	Director.stop()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

	player = main.player
	player.set("_invuln", 999.0)
	field = main.get_node("World/PickupField") as PickupField
	Pickups.clear()

	failures += _check(player != null, "player exists")
	failures += _check(field != null and Pickups.field == field, "pickup field is attached")

	await _test_ground_pickup()
	await _test_merge()
	_test_aged_merge()
	await _test_enemy_drop()
	await _test_chest_drop()
	await _test_collect_clamp()
	await _test_pickup_range()
	# 吸附要在解锁全屏吸取（gold_3 / xp_4）之前测，否则掉落生成即自动起飞。
	await _test_vacuum_all()
	_test_unpicked_cap()
	await _test_auto_collect()
	await _test_streak_overflow()

	print("PICKUP TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_ground_pickup() -> void:
	Pickups.clear()
	var gold_before := RunState.gold
	Pickups.spawn_gold(player.global_position + Vector2(55.0, 0.0), 5)
	failures += _check(field.idle_count() == 1, "ground gold waits on the floor")
	failures += _check(RunState.gold == gold_before, "ground gold is not awarded at spawn")

	await get_tree().create_timer(0.8).timeout
	failures += _check(
		RunState.gold == gold_before + 5,
		"magnet pulls ground gold in and awards it"
	)
	failures += _check(field.total_count() == 0, "collected pickup leaves the field")

	# 经验用同样的路径，但直接设置等级/经验避免早先击杀干扰断言。
	RunState.level = 1000
	RunState.xp = 0
	Pickups.spawn_xp(player.global_position + Vector2(-55.0, 0.0), 3)
	await get_tree().create_timer(0.8).timeout
	failures += _check(RunState.xp == 3, "xp pickup awards xp on arrival")


func _test_merge() -> void:
	Pickups.clear()


func _test_aged_merge() -> void:
	Pickups.clear()
	var gold_before := RunState.gold
	Pickups.spawn_gold(player.global_position + Vector2(420.0, 0.0), 3)
	Pickups.spawn_gold(player.global_position + Vector2(475.0, 0.0), 4)
	Pickups.spawn_xp(player.global_position + Vector2(450.0, 0.0), 5.0)
	field._merge_aged_neighbours()
	failures += _check(field.total_count() == 3, "young nearby drops stay separate")
	var ages: PackedFloat32Array = field.get("_age")
	for i in ages.size():
		ages[i] = 10.0
	field.set("_age", ages)
	field._merge_aged_neighbours()
	failures += _check(field.total_count() == 2, "ten-second nearby gold drops merge")
	var amounts: PackedFloat32Array = field.get("_amount")
	var counts: PackedInt32Array = field.get("_merged_count")
	var kinds: PackedInt32Array = field.get("_kind")
	var gold_index := kinds.find(PickupField.KIND_GOLD)
	failures += _check(gold_index >= 0 and is_equal_approx(amounts[gold_index], 7.0)
		and counts[gold_index] == 2, "merged pickup preserves value and grows its visual count")
	failures += _check(RunState.gold == gold_before, "aged merge does not credit uncollected gold")
	Pickups.clear()
	Pickups.spawn_gold(player.global_position + Vector2(420.0, 0.0), 1)
	Pickups.spawn_gold(player.global_position + Vector2(426.0, 0.0), 2)
	failures += _check(field.idle_count() == 1, "overlapping drops merge into one item")
	Pickups.clear()


func _test_enemy_drop() -> void:
	Pickups.clear()
	var enemy_scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var enemy := enemy_scene.instantiate() as Enemy
	enemy.configure(ContentDB.get_enemy(&"chaser_triangle"), player)
	main.world.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(520.0, 0.0)
	enemy.set_physics_process(false)

	var gold_before := RunState.gold
	var death_position := enemy.global_position
	enemy.force_kill()
	await get_tree().process_frame
	failures += _check(field.idle_count() == 2, "enemy death drops one gold and one xp")
	failures += _check(RunState.gold == gold_before, "kill rewards wait for pickup")

	# 金币和经验各自散开，不能精确叠在尸体同一点。
	var drops: PackedVector2Array = field.get("_item_pos")
	if drops.size() == 2:
		var gold_offset := drops[0].distance_to(death_position)
		var xp_offset := drops[1].distance_to(death_position)
		failures += _check(
			gold_offset >= 8.0 and gold_offset <= 27.0 and xp_offset >= 8.0 and xp_offset <= 27.0,
			"drops scatter 9-26px around the corpse"
		)
		failures += _check(
			drops[0].distance_to(drops[1]) > 0.5,
			"gold and xp land on different positions"
		)
	else:
		failures += _check(false, "two drop positions are readable")

	Pickups.clear()
	await get_tree().process_frame


## 幸运宝箱：地面等待磁吸，靠近后打开并给出遗物/金币/经验之一。
func _test_chest_drop() -> void:
	Pickups.clear()
	Skills.unlock(&"luck_1", true)
	# 幸运提高了资源箱经验；此套专测拾取，避免连开资源箱触发升级暂停。
	RunState.level = 1000
	RunState.xp = 0
	var gold_before := RunState.gold
	var xp_before := RunState.xp
	var relics_before := Skills.owned_relics.size()
	var offers_before := Skills.pending_relic_offers.size()

	Pickups.spawn_chest(player.global_position + Vector2(50.0, 0.0))
	Pickups.spawn_chest(player.global_position + Vector2(53.0, 0.0))
	failures += _check(field.idle_count() == 2, "chests never merge with each other")

	await get_tree().create_timer(0.8).timeout
	var gained := RunState.gold - gold_before
	var xp_gained := RunState.xp - xp_before
	var relic_gained := Skills.owned_relics.size() - relics_before
	failures += _check(field.total_count() == 0, "chests open and leave the field")
	failures += _check(
		gained > 0 or xp_gained > 0 or relic_gained > 0 or Skills.pending_relic_offers.size() > offers_before,
		"a chest pays out gold, xp or a relic offer"
	)


## 回归：高速磁吸的掉落单帧不能越过玩家后再折返（表现为“抽搐”）。
func _test_collect_clamp() -> void:
	Pickups.clear()
	var gold_before := RunState.gold
	Pickups.spawn_gold(player.global_position + Vector2(17.0, 0.0), 2)
	# 第一帧进入收集，第二帧就会尝试越过收集半径。
	field._process(1.0 / 60.0)
	field._process(1.0 / 60.0)
	failures += _check(
		field.total_count() == 0,
		"fast pickup is clamped and credited instead of overshooting"
	)
	failures += _check(RunState.gold == gold_before + 2, "clamped pickup still pays out")


## 经验/金币一阶技能各 +50% 磁吸范围，且对两种掉落都生效。
## 基底可能已被宝箱开出的透镜类遗物抬高，所以按当前倍率取边界，断言“增量”而不是固定 100/150 px。
func _test_pickup_range() -> void:
	Pickups.clear()
	var origin := player.global_position
	var base_multiplier := Skills.pickup_radius_multiplier()
	var base_radius := PickupField.MAGNET_RADIUS * base_multiplier
	var outside := ceilf(base_radius) + 8.0

	Pickups.spawn_gold(origin + Vector2(outside, 0.0), 1)
	field._process(1.0 / 60.0)
	failures += _check(
		field.idle_count() == 1,
		"gold just outside the base magnet stays on the floor"
	)

	Skills.unlock(&"xp_1", true)
	failures += _check(
		is_equal_approx(Skills.pickup_radius_multiplier(), base_multiplier + 0.5),
		"xp tier 1 adds 50% pickup range"
	)
	Pickups.clear()
	Pickups.spawn_gold(origin + Vector2(base_radius + 20.0, 0.0), 1)
	field._process(1.0 / 60.0)
	failures += _check(
		field.collecting_count() == 1,
		"xp tier 1 widens the magnet for gold too"
	)

	var after_xp_radius := PickupField.MAGNET_RADIUS * Skills.pickup_radius_multiplier()
	Pickups.clear()
	Pickups.spawn_gold(origin + Vector2(after_xp_radius + 8.0, 0.0), 1)
	field._process(1.0 / 60.0)
	failures += _check(field.idle_count() == 1, "gold just outside the +50% magnet stays")

	Skills.unlock(&"gold_1", true)
	failures += _check(
		is_equal_approx(Skills.pickup_radius_multiplier(), base_multiplier + 1.0),
		"both tier 1 nodes stack their pickup range"
	)
	field._process(1.0 / 60.0)
	failures += _check(
		field.collecting_count() == 1,
		"stacked pickup range reaches the waiting gold"
	)
	Pickups.clear()


## 商人吸附：全屏经验/金币立即起飞，宝箱留在原地，奖励照常结算。
func _test_vacuum_all() -> void:
	Pickups.clear()
	# 拾取测试避开升级面板，升级节奏由 xp_test 覆盖。
	RunState.level = 1000
	RunState.xp = 0
	var gold_before := RunState.gold
	var level_before := RunState.level
	var xp_before := RunState.xp
	# 放在磁吸范围外，确保是 vacuum_all 而不是自动拾取让它们起飞。
	Pickups.spawn_gold(player.global_position + Vector2(500.0, 200.0), 4)
	Pickups.spawn_xp(player.global_position + Vector2(-500.0, -200.0), 2)
	Pickups.spawn_chest(player.global_position + Vector2(0.0, 520.0))

	failures += _check(field.idle_count() == 3, "vacuum fixture has two currency drops and a chest")
	failures += _check(Pickups.currency_count() == 2, "currency count ignores chests")

	var moved := Pickups.vacuum_all()
	failures += _check(moved == 2, "vacuum starts every currency drop")
	failures += _check(field.collecting_count() == 2, "vacuumed currency is already in flight")
	failures += _check(field.idle_count() == 1, "vacuum leaves chests on the floor")

	await get_tree().create_timer(0.8).timeout

	failures += _check(Pickups.currency_count() == 0, "vacuumed currency reaches the player")
	# gold_1 会抬高金币收益倍率，这里只断言“确实入账”，不锁死数值。
	failures += _check(RunState.gold > gold_before, "vacuumed gold is credited")
	failures += _check(
		RunState.level > level_before or RunState.xp > xp_before,
		"vacuumed xp is credited"
	)
	failures += _check(field.idle_count() == 1, "chest is still waiting after the vacuum")
	Pickups.clear()


## 全屏吸取：解锁 gold_3 / xp_4 后，掉落生成即进入收集状态并立刻画出流光。
func _test_auto_collect() -> void:
	Pickups.clear()
	Skills.unlock(&"gold_3", true)
	Skills.unlock(&"xp_4", true)

	var gold_before := RunState.gold
	Pickups.spawn_gold(player.global_position + Vector2(650.0, 0.0), 4)
	failures += _check(field.idle_count() == 0, "auto gold never lands on the floor")
	failures += _check(field.collecting_count() == 1, "auto gold starts in the collecting state")
	failures += _check(field.active_streak_count() == 1, "collecting gold uses a pooled Line2D streak")

	await get_tree().create_timer(1.2).timeout
	failures += _check(
		RunState.gold >= gold_before + 4,
		"auto gold flies in and awards on arrival"
	)
	failures += _check(field.total_count() == 0, "auto gold clears after arrival")

	RunState.level = 1000
	RunState.xp = 0
	Pickups.spawn_xp(player.global_position + Vector2(-650.0, 0.0), 5)
	failures += _check(field.idle_count() == 0, "auto xp never lands on the floor")
	await get_tree().create_timer(1.2).timeout
	failures += _check(RunState.xp >= 5, "auto xp flies in and awards xp")

	# 金币的拾取移动速度比经验慢 25%（两者初始速度比应为 0.75）。
	Pickups.clear()
	Pickups.spawn_gold(player.global_position + Vector2(650.0, 0.0), 1)
	Pickups.spawn_xp(player.global_position + Vector2(-650.0, 0.0), 1)
	var speeds: PackedFloat32Array = field.get("_speed")
	if speeds.size() == 2 and speeds[1] > 0.0:
		var ratio := speeds[0] / speeds[1]
		failures += _check(
			ratio > 0.72 and ratio < 0.78,
			"gold pickup speed is 25%% slower than xp (ratio %.2f)" % ratio
		)
	else:
		failures += _check(false, "gold and xp pickup speeds are readable")
	Pickups.clear()


func _test_unpicked_cap() -> void:
	Pickups.clear()
	RunState.level = 1000
	RunState.xp = 0.0
	for i in 120:
		var angle := TAU * float(i) / 120.0
		field._spawn(PickupField.KIND_XP,
			player.global_position + Vector2.from_angle(angle) * 650.0, 1.0, false)
	failures += _check(field.idle_count() == PickupField.MAX_IDLE,
		"uncollected ground drops stay under the lower cap")
	failures += _check(is_zero_approx(RunState.xp),
		"discarded uncollected drops do not grant XP")
	Pickups.clear()
	for i in PickupField.MAX_ITEMS:
		field._append_item(PickupField.KIND_XP, player.global_position + Vector2(700.0 + i, 0.0), 1.0, 0.0)
	field._spawn(PickupField.KIND_XP, player.global_position + Vector2(-700.0, 0.0), 1.0, false)
	failures += _check(field.total_count() <= PickupField.MAX_ITEMS and is_zero_approx(RunState.xp),
		"total item cap never credits an uncollected drop")
	Pickups.clear()


## 超过 Line2D 池上限时，已经自动拾取的掉落不画线但奖励仍要结算。
func _test_streak_overflow() -> void:
	Pickups.clear()
	var gold_before := RunState.gold
	var count := 120
	for i in count:
		var angle := TAU * float(i) / float(count)
		Pickups.spawn_gold(
			player.global_position + Vector2(cos(angle), sin(angle)) * 620.0,
			1
		)
	failures += _check(
		field.active_streak_count() <= PickupField.MAX_STREAKS,
		"streak lines stay within the pool"
	)
	await get_tree().create_timer(1.6).timeout
	failures += _check(
		RunState.gold >= gold_before + count,
		"overflow rewards are still paid out"
	)
	failures += _check(field.total_count() == 0, "overflow pickups all cleared")


func _check(condition: bool, label: String) -> int:
	if condition:
		print("PICKUP PASS  %s" % label)
		return 0
	print("PICKUP FAIL  %s" % label)
	return 1
