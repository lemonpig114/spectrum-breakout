extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	print("FIX %s %s" % ["PASS" if ok else "FAIL",label])
	if not ok: failures += 1
func touch(index: int, point: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index=index
	e.position=point
	e.pressed=down
	get_viewport().push_input(e,true)
func _ready() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2).timeout
	Director.stop()
	main.player.controls_enabled = true
	main.player.set_physics_process(false)
	for e in get_tree().get_nodes_in_group(&"enemies"): e.queue_free()
	await get_tree().process_frame
	var target := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	target.configure(ContentDB.get_enemy(&"chaser_triangle"),main.player,ColorType.RED)
	main.world.add_child(target)
	target.global_position=main.player.global_position+Vector2(80,0)
	target.health=1000000
	target.set_physics_process(false)
	var clone := MirrorClone.new()
	main.world.add_child(clone)
	clone.setup(main.player,main.player.global_position)
	clone.set_physics_process(false)
	for form in [&"scythe",&"cannon",&"lightning"]:
		main.player.weapon.acquire_form(form)
		main.player.weapon.select_primary(form)
		clone._cached_target=target
		clone._target_scan_timer=100
		clone._shot_cooldown=0
		clone._physics_process(0)
		check(is_equal_approx(clone._shot_cooldown,1.0/main.player.effective_fire_rate()),"clone shares main-form rate for %s" % form)
		if form == &"scythe": check(is_equal_approx(clone._shot_cooldown,2.0/main.player.weapon.get_final_fire_rate()),"scythe half-rate doubles clone attack interval")
		var duration := clone._shot_cooldown
		clone._physics_process(duration*0.5)
		check(clone._shot_cooldown > 0 and clone._shot_cooldown < duration,"clone waits between attacks")
	main.player.weapon.stats.set_base(&"fire_rate",10000)
	clone._shot_cooldown=0
	clone._physics_process(0)
	check(is_equal_approx(clone._shot_cooldown,1.0/main.player.effective_fire_rate()),"clone respects player fire-rate cap")
	Skills.clear_relic_offers()
	Skills.offer_relic(&"dust_glasses","测试",true)
	Skills.offer_relic(&"rare_telescope","测试",true)
	await get_tree().create_timer(0.1).timeout
	var panel: RelicChoicePanel=main.get_node("HUD/RelicChoicePanel")
	var mobile: MobileControls=main.mobile_controls
	touch(0,Vector2(100,550),true)
	var drag:=InputEventScreenDrag.new()
	drag.index=0
	drag.position=Vector2(160,550)
	get_viewport().push_input(drag,true)
	check(mobile._move_index==0 and GameInput.mobile_move_direction.x > 0,"first touch moves joystick")
	var pick:=panel._take_button.get_global_rect().get_center()
	touch(1,pick,true)
	touch(1,pick,false)
	check(Skills.relic_count(&"dust_glasses")==1 and mobile._move_index==0 and GameInput.mobile_move_direction.x>0,"second touch picks relic without releasing joystick")
	await get_tree().create_timer(0.05).timeout
	check(Skills.relic_count(&"rare_telescope")==0,"one tap cannot collect the next offer")
	var drop:=panel._discard_button.get_global_rect().get_center()
	touch(2,drop,true)
	touch(2,drop+Vector2(0,100),false)
	check(not Skills.pending_relic_offers.is_empty(),"releasing outside the relic button cancels the tap")
	touch(2,drop,true)
	touch(2,drop,false)
	check(Skills.pending_relic_offers.is_empty() and Skills.relic_count(&"rare_telescope")==0,"discard also works while joystick is held")
	touch(0,Vector2(160,550),false)
	check(GameInput.mobile_move_direction==Vector2.ZERO,"joystick releases normally")
	print("CLONE TOUCH FIX TEST %s (%d failures)" % ["PASS" if failures==0 else "FAIL",failures])
	get_tree().quit(0 if failures==0 else 1)
