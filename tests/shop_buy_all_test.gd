extends Node
var failures := 0
func check(ok: bool,label: String) -> void:
	print("BULK %s %s" % ["PASS" if ok else "FAIL",label])
	if not ok: failures += 1
func click(panel: ShopPanel) -> void:
	var e := InputEventMouseButton.new()
	e.button_index=MOUSE_BUTTON_LEFT
	e.pressed=true
	e.position=panel._button_rects()[4].get_center()
	panel._gui_input(e)
func _ready() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2).timeout
	Director.stop()
	main.player.controls_enabled=false
	RunState.request_pause(&"shop")
	var panel: ShopPanel=main.shop_panel
	panel.open(main.player)
	panel._offers.assign([Skills.get_relic(&"dust_glasses"),Skills.get_relic(&"rare_telescope"),Skills.get_relic(&"dust_knife")])
	panel._offer_prices.assign([5,40,3])
	panel._sold.assign([false,false,false])
	RunState.gold=10
	click(panel)
	check(RunState.gold==10 and not panel._sold.any(func(value): return value),"first click only arms bulk purchase")
	click(panel)
	check(RunState.gold==2 and panel._sold==[true,false,true],"second click buys affordable current stock and skips unaffordable item")
	click(panel)
	panel._buy_all_deadline=Time.get_ticks_msec()-1
	click(panel)
	check(not panel._sold[1],"expired confirmation does not purchase")
	var saved := panel.save_data()
	panel.close()
	panel.restore_data(saved,main.player)
	check(panel._buy_all_deadline<0,"confirmation cannot survive closing or loading shop")
	Skills.unlock(&"fire_1",true)
	Skills.unlock(&"fire_2",true)
	Skills.unlock(&"fire_3",true)
	Skills.unlock(&"fire_4",true)
	check(Skills.fire_rate_cap_multiplier()==6 and is_equal_approx(main.player.weapon.stats.get_value(&"fire_rate_final"),1.05*1.3),"fire four doubles normal cap and adds thirty percent final rate")
	print("SHOP BULK TEST %s (%d failures)" % ["PASS" if failures==0 else "FAIL",failures])
	get_tree().quit(0 if failures==0 else 1)
