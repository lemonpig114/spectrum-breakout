extends Node

## 商人与商店专项无头测试：
## godot --headless --fixed-fps 60 --path . res://tests/merchant_test.tscn

var failures := 0
var main: Node
var player: Player
var panel: ShopPanel
var merchant: Merchant


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
	panel = main.get_node("HUD/ShopPanel") as ShopPanel

	failures += _check(player != null, "player exists")
	failures += _check(panel != null, "shop panel exists")

	# 先拿一个唯一遗物，用来验证它不会再出现在商店池里。
	Skills.grant_relic(&"demon_pointed_vessel")

	await _test_spawn_and_open()
	_test_health_icon_layout()
	_test_upgrade_price()
	await _test_upgrade()
	await _test_purchase()
	await _test_reroll()
	await _test_heal()
	await _test_close()
	await _test_scheduler()
	_test_shop_bias()
	_test_large_shelf()
	_test_shelf_bonus()

	print("MERCHANT TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_spawn_and_open() -> void:
	merchant = Director.spawn_merchant_now(Vector2(500.0, 300.0))
	failures += _check(merchant != null, "merchant spawns")
	failures += _check(
		get_tree().get_nodes_in_group(&"merchant").size() == 1,
		"merchant joins the merchant group"
	)
	failures += _check(
		Director.spawn_merchant_now(Vector2(700.0, 300.0)) == merchant,
		"only one merchant can exist at a time"
	)

	# 先在地面放两份金币，验证触碰商人后先吸取再进店。
	Pickups.clear()
	Pickups.spawn_gold(player.global_position + Vector2(320.0, 0.0), 5)
	Pickups.spawn_gold(player.global_position + Vector2(-360.0, 80.0), 5)
	failures += _check(Pickups.currency_count() == 2, "two gold drops wait on the floor")

	# 靠到玩家身边触发交互。
	merchant.global_position = player.global_position + Vector2(40.0, 0.0)
	await get_tree().create_timer(0.05).timeout

	failures += _check(
		Pickups.collecting_count() == 2,
		"touching the merchant vacuums every ground drop"
	)
	failures += _check(
		main.hud_control.visible and not panel.visible,
		"vacuum plays out with the HUD still visible"
	)

	await get_tree().create_timer(0.9).timeout

	failures += _check(Pickups.currency_count() == 0, "vacuum absorbs every drop")
	failures += _check(panel.visible, "touching the merchant opens the shop after the vacuum")
	failures += _check(get_tree().paused, "shop pauses the tree")
	failures += _check(
		not main.hud_control.visible,
		"HUD hides while the shop is open"
	)

	var offers: Array[RelicResource] = panel.get("_offers")
	failures += _check(Skills.shop_slots() == 4, "base shelf has four slots")
	failures += _check(offers.size() == 4, "shop stocks four relics")
	var ids: Array[StringName] = []
	for relic in offers:
		ids.append(relic.id)
	var has_duplicate := false
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if ids[i] == ids[j]:
				has_duplicate = true
	failures += _check(not has_duplicate, "one shop never stocks duplicate relics")
	failures += _check(
		not ids.has(&"demon_pointed_vessel"),
		"owned unique relic is removed from the shop pool"
	)
	# 未选择契约时，恶魔/天使遗物都不该出现。
	var has_side := false
	for relic in offers:
		if relic.side != &"":
			has_side = true
	failures += _check(not has_side, "side relics require the matching path first")


func _test_health_icon_layout() -> void:
	var hud: Node = main.hud_control
	var saved_shields := Skills.guardian_shields
	hud.call("_on_health_changed", 10.0, 10.0)
	Skills.guardian_shields = 0
	failures += _check(is_zero_approx(float(hud.call("_health_extra_height"))),
		"ten hearts fit on one row")
	Skills.guardian_shields = 1
	var row_one: Vector2 = hud.call("_health_icon_center", 0)
	var row_two: Vector2 = hud.call("_health_icon_center", 10)
	failures += _check(is_equal_approx(float(hud.call("_health_extra_height")), 24.0)
		and is_equal_approx(row_two.y, row_one.y + 24.0)
		and is_equal_approx(panel._shop_health_icon_center(10).y,
			panel._shop_health_icon_center(0).y + 24.0),
		"the first guardian shield wraps after ten hearts in HUD and shop")
	hud.call("_on_health_changed", 29.0, 29.0)
	Skills.guardian_shields = 1
	failures += _check(is_equal_approx(float(hud.call("_health_extra_height")), 48.0),
		"thirty icons fit on three rows")
	Skills.guardian_shields = 2
	failures += _check(is_zero_approx(float(hud.call("_health_extra_height"))),
		"more than thirty icons switch to the compact numeric layout")
	Skills.guardian_shields = saved_shields
	hud.call("_on_health_changed", player.health, player.max_health)


## 捐款价格：越早越贵；等级越高越贵；5 分钟后可以降到 0，且永不为负。
func _test_upgrade_price() -> void:
	var saved_level := Skills.shop_level
	Skills.shop_level = 0
	RunState.elapsed = 0.0
	var early := panel._upgrade_price()
	Skills.shop_level = 2
	var higher := panel._upgrade_price()
	Skills.shop_level = 0
	RunState.elapsed = 200.0
	var late := panel._upgrade_price()
	RunState.elapsed = 9999.0
	var free := panel._upgrade_price()
	Skills.shop_level = saved_level
	RunState.elapsed = 0.0

	failures += _check(early > late, "donation is more expensive early in the run")
	failures += _check(higher > early, "each shop level sharply raises the donation price")
	failures += _check(free > 0, "donation price retains a positive late-game floor")
	var rarity_weights := Skills._shop_rarity_weights()
	failures += _check(is_equal_approx(rarity_weights[0], 0.70)
		and is_equal_approx(rarity_weights[1], 0.30), "level-one shop is 70 percent dust and 30 percent rare")


func _test_upgrade() -> void:
	RunState.gold = 1000
	var before_gold := RunState.gold
	var price := panel._upgrade_price()
	var before_count := (panel.get("_offers") as Array).size()

	panel.call("_upgrade")

	var offers: Array[RelicResource] = panel.get("_offers")
	failures += _check(Skills.shop_level == 1, "donation raises the shop level")
	failures += _check(Skills.shop_slots() == 5, "shop level adds one shelf slot")
	failures += _check(offers.size() == before_count + 1, "upgrade immediately stocks a new relic")
	failures += _check(
		RunState.gold == before_gold - price,
		"donation charges the displayed price"
	)
	var rects: Array[Rect2] = panel._card_rects()
	failures += _check(rects.size() == 5, "five cards get laid out after upgrading")
	var view := panel.size
	var inside := true
	for rect in rects:
		if rect.position.x < 0.0 or rect.end.x > view.x:
			inside = false
	failures += _check(inside, "five-card row stays inside the screen")


func _test_purchase() -> void:
	RunState.gold = 1000
	var offers: Array[RelicResource] = panel.get("_offers")

	var buy_index := -1
	for i in offers.size():
		if not offers[i].consumable:
			buy_index = i
			break
	failures += _check(buy_index >= 0, "shop has a non-consumable relic to buy")
	if buy_index < 0:
		return

	var relic := offers[buy_index]
	var price := panel._price_of(relic)
	var before_gold := RunState.gold
	var before_count := Skills.relic_count(relic.id)
	var frozen_prices: Array[int] = panel.get("_offer_prices").duplicate()
	panel.call("_buy", buy_index)

	failures += _check(
		RunState.gold == before_gold - price
			- (300 if relic.id == &"rare_bond" else (1000 if relic.id == &"rare_high_bond" else 0)),
		"buying a relic spends its price"
	)
	failures += _check(panel.get("_offer_prices") == frozen_prices and Skills.shop_purchases == 1,
		"purchase inflation only affects future shelves")
	failures += _check(panel._price_of(relic) == price + ShopPanel.PURCHASE_GROWTH,
		"each purchase increases future prices linearly")
	failures += _check(
		Skills.relic_count(relic.id) == before_count + 1,
		"bought relic is granted and stacked"
	)
	var sold: Array[bool] = panel.get("_sold")
	failures += _check(sold[buy_index], "sold card is marked")

	# 金币不足时不能扣款或发货。
	panel.call("_buy", buy_index)
	failures += _check(
		Skills.relic_count(relic.id) == before_count + 1,
		"re-clicking a sold card does nothing"
	)


func _test_reroll() -> void:
	var offers: Array[RelicResource] = panel.get("_offers")
	var old_ids: Array[StringName] = []
	for relic in offers:
		old_ids.append(relic.id)

	var before_gold := RunState.gold
	var cost := int(panel.get("_reroll_cost"))
	var free_before := int(panel.get("_free_rerolls"))
	panel.call("_reroll")

	var new_offers: Array[RelicResource] = panel.get("_offers")
	failures += _check(
		RunState.gold == before_gold - (0 if free_before > 0 else cost),
		"reroll uses the free charge before gold"
	)
	failures += _check(new_offers.size() == Skills.shop_slots(), "reroll refills the whole shelf")
	failures += _check(panel.get("_reroll_cost") == cost + ShopPanel.REROLL_GROWTH,
		"reroll price grows linearly for the next reroll")

	var reused := false
	for relic in new_offers:
		if old_ids.has(relic.id):
			reused = true
	failures += _check(not reused, "reroll avoids the previous shelf")
	var sold: Array[bool] = panel.get("_sold")
	failures += _check(not sold.has(true), "reroll resets sold markers")


func _test_heal() -> void:
	RunState.gold = 1000
	player.health = 2.0
	var before_gold := RunState.gold
	var before_health := player.health
	var cost := panel._heal_price()

	panel.call("_heal")
	failures += _check(
		player.health == minf(player.max_health, Player.snap_to_half(before_health + ShopPanel.HEAL_HEARTS)),
		"shop heal restores 1.5 hearts"
	)
	failures += _check(
		RunState.gold == before_gold - cost,
		"shop heal charges gold"
	)

	# 一次进货只能回复一次。
	var gold_after := RunState.gold
	panel.call("_heal")
	failures += _check(
		RunState.gold == gold_after and player.health <= player.max_health,
		"heal can only be bought once per visit"
	)


func _test_close() -> void:
	panel.call("_leave")
	await get_tree().process_frame

	failures += _check(not panel.visible, "leaving closes the shop panel")
	failures += _check(not get_tree().paused, "leaving resumes the tree")
	failures += _check(main.hud_control.visible, "HUD returns after shopping")

	await get_tree().create_timer(0.6).timeout
	failures += _check(
		get_tree().get_nodes_in_group(&"merchant").is_empty(),
		"merchant hops away after the shop closes"
	)


## Director 自身的倒计时：清零后应自动刷出商人，并把下一只排到基础 90 秒后。
func _test_scheduler() -> void:
	Director.start()
	Director.set("_merchant_timer", 0.0)
	# process_frame 信号早于节点 _process，等一个短计时让 Director 真正跑过一帧。
	await get_tree().create_timer(0.1).timeout

	var auto_merchant: Merchant = Director.merchant
	failures += _check(auto_merchant != null, "director timer spawns a merchant")
	var expected_interval := Skills.merchant_interval()
	failures += _check(
		float(Director.get("_merchant_timer")) >= expected_interval - 1.0,
		"next merchant is scheduled by the base interval"
	)
	failures += _check(
		is_equal_approx(Director.MERCHANT_FIRST_DELAY, 80.0)
			and is_equal_approx(Skills.merchant_interval(), 90.0),
		"first merchant arrives at 1:20, then every 90 seconds"
	)

	if auto_merchant != null and is_instance_valid(auto_merchant):
		auto_merchant.leave()
	Director.stop()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().create_timer(0.5).timeout


func _test_shop_bias() -> void:
	# 未选择契约：两种阵营遗物都不进商店池。
	var uncommitted_pool := Skills.shop_relic_pool()
	var has_demon := false
	var has_angel := false
	for relic in uncommitted_pool:
		if relic.side == &"demon":
			has_demon = true
		elif relic.side == &"angel":
			has_angel = true
	failures += _check(
		not has_demon and not has_angel,
		"no side relics in the shop before committing a path"
	)

	# 选择恶魔二阶后，只有恶魔遗物可能出现，且没有概率翻倍。
	Skills.unlock(&"path_demon_2", true)
	failures += _check(Skills.merchant_side() == &"demon", "demon tier 2 commits the shop")
	var pool := Skills.shop_relic_pool()
	has_angel = false
	has_demon = false
	var has_owned_unique := false
	for relic in pool:
		if relic.side == &"angel":
			has_angel = true
		elif relic.side == &"demon":
			has_demon = true
		if relic.id == &"demon_pointed_vessel":
			has_owned_unique = true

	failures += _check(not has_angel, "opposite-side relics disappear from the pool")
	failures += _check(has_demon, "committed-side relics stay in the pool")
	failures += _check(not has_owned_unique, "unique relics stay excluded after commit")
	failures += _check(
		is_equal_approx(Skills.shop_weight_multiplier(&"demon"), 1.0),
		"committing a path no longer doubles side weights"
	)


## 满级货架 14 格仍能完整布局；溢出时升级失败但不扣钱。
func _test_large_shelf() -> void:
	while Skills.can_upgrade_shop():
		Skills.upgrade_shop()
	failures += _check(Skills.shop_slots() == 14, "shop shelf caps at fourteen slots")
	failures += _check(not Skills.upgrade_shop(), "upgrade is rejected once the shelf is full")

	panel.visible = true
	panel._restock([])
	var offers: Array[RelicResource] = panel.get("_offers")
	var rects: Array[Rect2] = panel._card_rects()
	failures += _check(rects.size() == offers.size(), "every stocked relic gets a rect")
	var inside := true
	for rect in rects:
		if rect.position.x < 0.0 or rect.end.x > panel.size.x \
				or rect.position.y < 0.0 or rect.end.y > panel.size.y:
			inside = false
	failures += _check(inside, "fourteen cards fit inside the screen across two rows")
	panel.visible = false


## 隐藏机制：买空整排货架，下一只商人提前 10 秒；每次商店到访最多一次。
func _test_shelf_bonus() -> void:
	Skills.shop_level = 0
	RunState.gold = 1000000
	Director.set("_merchant_timer", 90.0)
	panel.open(player)

	var offers: Array[RelicResource] = panel.get("_offers")
	failures += _check(offers.size() == 4, "shelf bonus uses a four-card shelf")
	var timer_before := float(Director.get("_merchant_timer"))
	for i in offers.size():
		panel.call("_buy", i)
	var sold: Array[bool] = panel.get("_sold")
	failures += _check(not sold.has(false), "buying every card clears the shelf")
	failures += _check(float(panel.get("_squint_time")) > 0.0
		and panel.get("_speech") == "好货都被你挑光了。",
		"merchant squints and comments when the shelf sells out")
	failures += _check(
		is_equal_approx(float(Director.get("_merchant_timer")), timer_before - 10.0),
		"clearing a shelf pulls the next merchant 10 seconds earlier"
	)

	# 同一次到访重 roll 后再买空一次，不能再次提前。
	panel.call("_reroll")
	failures += _check(is_zero_approx(float(panel.get("_squint_time"))),
		"merchant opens eyes when the shelf is restocked")
	var timer_after := float(Director.get("_merchant_timer"))
	var rerolled: Array[RelicResource] = panel.get("_offers")
	for i in rerolled.size():
		panel.call("_buy", i)
	failures += _check(float(panel.get("_squint_time")) > 0.0,
		"merchant also squints on a second sellout")
	failures += _check(
		is_equal_approx(float(Director.get("_merchant_timer")), timer_after),
		"the shelf bonus only applies once per shop visit"
	)

	# 下一次进入商店重新计数。
	panel.close()
	panel.open(player)
	var fresh_offers: Array[RelicResource] = panel.get("_offers")
	var fresh_timer := float(Director.get("_merchant_timer"))
	for i in fresh_offers.size():
		panel.call("_buy", i)
	failures += _check(
		is_equal_approx(float(Director.get("_merchant_timer")), fresh_timer - 10.0),
		"a new shop visit can earn the shelf bonus again"
	)
	panel.close()


func _check(condition: bool, label: String) -> int:
	if condition:
		print("MERCHANT PASS  %s" % label)
		return 0
	print("MERCHANT FAIL  %s" % label)
	return 1
