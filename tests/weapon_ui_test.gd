extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	print("WEAPON UI %s %s" % ["PASS" if ok else "FAIL",label])
	if not ok: failures += 1
func _ready() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.9).timeout
	Director.stop()
	main.player.controls_enabled = false
	var panel: WeaponChoicePanel = main.weapon_choice_panel
	main.player.weapon.acquire_form(&"star")
	RunState.request_pause(&"weapon_reward")
	panel.restore_reward(main.player,[&"sword", &"lightning", &"cannon"],2)
	await get_tree().create_timer(0.15).timeout
	check(panel._cards.columns == 3 and panel._cards.get_child_count() == 3,"reward uses three touchable cards")
	check(panel._box.position.x >= 0 and panel._box.position.y >= 0 and panel._box.get_rect().end.y <= panel.size.y+1,"reward fits viewport")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/visual_weapon_cards.png")
	panel._choose(0)
	var count: int = main.player.weapon.owned_forms.size()
	panel._choose(1)
	check(count == 2 and main.player.weapon.owned_forms.size() == 2 and panel.visible and panel._primary_mode,"acquisition opens main selection and blocks double activation")
	check(main.player.weapon.primary_form == &"star","acquisition preserves chosen main")
	var saved: Dictionary = GameSave.snapshot(main)
	check(saved.ui.weapon_primary_mode and saved.ui.weapon_choices.size() == 2,"save distinguishes main selection from acquisition")
	await get_tree().create_timer(0.25).timeout
	panel._choose(1)
	check(main.player.weapon.primary_form == &"sword" and not panel.visible,"main card commits chosen form and closes modal")
	RunState.release_pause(&"weapon_reward")
	main._toggle_manual_pause()
	for id in WeaponRuntime.PRIMARY_ORDER: main.player.weapon.acquire_form(id)
	panel.open_loadout(main.player)
	await get_tree().create_timer(0.15).timeout
	check(panel._choices.size() == 8 and panel._scroll.custom_minimum_size.y < panel.size.y,"full inventory scrolls within screen")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	main.pause_panel._input(escape)
	check(main._manual_paused and main.pause_panel.visible,"underlying pause cannot consume loadout keys")
	panel._unhandled_input(escape)
	check(not panel.visible and main._manual_paused,"escape closes loadout while preserving pause")
	await get_tree().create_timer(0.5).timeout
	check(CardFeedback.active_count == 0,"card feedback expires while paused")
	print("WEAPON UI TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL",failures])
	get_tree().quit(0 if failures == 0 else 1)
