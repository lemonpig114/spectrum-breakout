extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	print("RANGE RELIC %s %s" % ["PASS" if ok else "FAIL",label])
	if not ok: failures += 1
func _ready() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2).timeout
	Director.stop()
	main.player.controls_enabled = false
	main.player.set_physics_process(false)
	check(Skills.relics.size()==59,"three relics enter catalog")
	var base: float = main.player.weapon.attack_range()
	check(Skills.grant_relic(&"dust_glasses") and is_equal_approx(main.player.weapon.attack_range(),base*1.15),"glasses add fifteen percent range")
	check(Skills.grant_relic(&"rare_telescope") and is_equal_approx(main.player.weapon.attack_range(),base*1.55),"telescope adds forty percent in shared range stat")
	check(Skills.get_relic(&"epic_sniper_scope").rarity==RelicResource.RARITY_EPIC,"scope uses torch rarity")
	Skills.grant_relic(&"epic_sniper_scope")
	var e := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	e.configure(ContentDB.get_enemy(&"chaser_triangle"),main.player,ColorType.RED)
	main.world.add_child(e)
	e.set_physics_process(false)
	e.health = 1000000
	e.max_health = 1000000
	for pair in [[0.0,1.0],[4.0,1.0],[7.0,1.5],[10.0,2.0],[14.0,2.0]]:
		e.global_position = main.player.global_position+Vector2(float(pair[0])*GridBackground.major_spacing_world,0)
		var hit := Skills.build_hit_context(main.player,e,100,-1,false,false)
		var before := e.health
		e.take_damage(hit)
		check(is_equal_approx(before-e.health,100*float(pair[1])),"linear range damage at %.0f grid cells" % float(pair[0]))
	Skills.grant_relic(&"epic_sniper_scope")
	Skills.grant_relic(&"epic_sniper_scope")
	check(not Skills.grant_relic(&"epic_sniper_scope") and Skills.relic_count(&"epic_sniper_scope")==3,"scope capped at three copies")
	e.global_position = main.player.global_position+Vector2(640,0)
	var max_hit := Skills.build_hit_context(main.player,e,100,-1,false,false)
	var before_max := e.health
	e.take_damage(max_hit)
	check(is_equal_approx(before_max-e.health,400) and is_equal_approx(main.player.weapon.attack_range(),base*3.05),"three copies add three hundred percent distant damage and one hundred fifty percent range")
	var elemental := DamageContext.new()
	elemental.amount = 25
	elemental.color_index = -1
	elemental.add_tag(&"elemental")
	elemental.add_tag(&"element_secondary")
	var elemental_before := e.health
	e.take_damage(elemental)
	check(is_equal_approx(elemental_before-e.health,100),"elemental ticks share distant-target damage without double application")
	var soul_before := e.health
	e.take_true_damage(25)
	check(is_equal_approx(soul_before-e.health,100),"soul damage also receives the distant-target multiplier")
	print("RANGE RELIC TEST %s (%d failures)" % ["PASS" if failures==0 else "FAIL",failures])
	get_tree().quit(0 if failures==0 else 1)
