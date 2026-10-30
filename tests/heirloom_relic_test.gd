extends Node

var failures := 0


func check(ok: bool, label: String) -> void:
	print("HEIRLOOM %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	Director.stop()
	main.player.set_physics_process(false)
	var relic := Skills.get_relic(&"epic_weapon_cache")
	var shop: ShopPanel = main.get_node("HUD/ShopPanel")
	check(relic.display_name == "家传神兵" and relic.repeat_label() == "特殊道具"
		and relic.rarity == RelicResource.RARITY_IRIDESCENT, "special heirloom has iridescent quality")
	check(relic.price == 0 and shop._price_of(relic) == 0, "heirloom price is zero")
	RunState.elapsed = 1800.0
	Skills.shop_purchases = 100
	check(shop._price_of(relic) == 0, "elapsed time and purchase inflation cannot change the price")
	check(not Skills.shop_relic_pool().has(relic) and not Skills.shop_relic_pool(true).has(relic),
		"normal rarity and chest pools exclude the heirloom")
	RunState.rng.seed = 2951
	var appearances := 0
	for i in 30000:
		Skills._weapon_cache_offered = false
		if Skills._roll_weapon_cache_offer([]) != null:
			appearances += 1
	check(absf(float(appearances) / 30000.0 - 0.01) < 0.0015, "fixed shop chance is near one percent")
	var rng_state := RunState.rng.state
	Skills._weapon_cache_offered = false
	var normal := Skills._roll_weapon_cache_offer([])
	RunState.rng.state = rng_state
	Skills._weapon_cache_offered = false
	Skills.shop_level = 99
	Skills.player.stats.set_base(&"luck", 10000.0)
	check(Skills._roll_weapon_cache_offer([]) == normal, "shop quality and luck cannot change the special roll")
	Skills._weapon_cache_offered = false
	var page: Array[RelicResource] = []
	for i in 2000:
		page = Skills.shop_offers(4)
		if page.has(relic):
			break
	check(page.size() == 4 and page.has(relic), "special occupies one slot without changing shelf size")
	var appeared_again := false
	for i in 100:
		if Skills.shop_offers(4).has(relic):
			appeared_again = true
	check(not appeared_again, "declining the first offer prevents all later appearances")
	shop._offers.assign([relic])
	shop._offer_prices.assign([shop._price_of(relic)])
	shop._sold.assign([false])
	RunState.gold = -500
	var before: float = main.player.weapon.stats.get_value(&"damage_final")
	shop._buy(0)
	check(shop._sold[0] and Skills.relic_count(relic.id) == 1 and RunState.gold == -500,
		"negative balance can buy the fixed-free heirloom without changing gold")
	check(is_equal_approx(main.player.weapon.stats.get_value(&"damage_final"), before * 0.85),
		"heirloom applies a fifteen percent final damage penalty")
	check(main.weapon_choice_panel.visible, "heirloom opens the weapon reward choice")
	main.weapon_choice_panel._choose(0)
	check(main.player.weapon.owned_forms.size() == 1, "reward grants one new weapon")
	check(not Skills.grant_relic(relic.id), "heirloom remains unique after purchase")
	print("HEIRLOOM RELIC TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
