extends Node

const VERSION := 1
const HEX_BOSS_FIELDS := ["global_position", "health", "max_health", "color_index", "rotation", "velocity",
	"edge_max_health", "edge_health", "edge_colors", "_fragment_color", "_vertices", "_morph_from", "_morph_to", "_morph_time", "_join_edge",
	"_spin", "_dash_cd", "_dash_left", "_windup", "_dash_direction", "_fragment_a", "_fragment_b",
	"_fragment_age", "_last_edge", "_edge_flash", "_crush_frame", "_resist_time", "_contact_cooldown",
	"_burn_ticks", "_burn_cursor", "_burn_pending", "_poison_dps", "_slow", "_slow_time", "_ice_time",
	"vulnerability", "_vulnerability_applied"]
const AUTO_INTERVAL := 10.0
var storage_path := "user://run_save.dat"
var pending: Dictionary = {}
var _main: WeakRef
var _clock := 0.0
const RUN_FIELDS := ["elapsed", "gold", "xp", "level", "energy", "max_energy", "color_index",
	"_xp_fraction", "_gold_fraction", "_income_accum", "_dot_clock", "_dot_bucket"]
const PLAYER_FIELDS := ["health", "global_position", "_fire_cooldown", "_heavy_timer", "_heavy_primed",
	"_altar_trades", "_distance_traveled", "_speed_burst_time", "_invuln"]
const SKILL_FIELDS := ["shop_level", "shop_purchases", "shop_rerolls", "_weapon_cache_offered", "soul_kills",
	"demon_shields", "_demon_shield_timer", "_demon_shield_fraction", "_lucifer_capacity", "_lucifer_healing_damage",
	"_soul_timer", "_energy_buff_timers", "_giant_kills", "guardian_shields", "color_shield", "_travel_distance",
	"_temp_luck", "_temp_luck_time", "_adrenaline_time", "_dice_time", "_dice_roll", "_relic_source_serial",
	"_offer_serial", "pending_relic_offers", "damage_totals", "damage_bonus_estimates"]
const MOD_REFS := ["_energy_buff_mod", "_energy_rate_mod", "_speed_rate_mod", "_giant_damage_mod",
	"_giant_size_mod", "_pointed_damage_mod", "_pointed_rate_mod", "_adrenaline_damage_mod",
	"_adrenaline_rate_mod", "_dice_damage_mod", "_dice_rate_mod", "_dice_crit_mod"]
const DIRECTOR_FIELDS := ["_merchant_timer", "_altar_timer", "_phase_index", "_phase_spawn_index", "_ring_angle", "_endless_announced"]
const HOLE_FIELDS := ["active", "age", "cooldown", "damage", "radius", "target_radius", "absorbed", "_tick", "_angle"]
const SUMMON_FIELDS := ["_color_offset", "_clone_timer", "_circle_kills", "_circle_time", "_circle_position",
	"_circle_tick", "_circle_buffed", "_circle_final_applied", "_circle_phase"]
const BOSS_FIELDS := ["global_position", "health", "max_health", "color_index", "_action", "_windup",
	"_windup_total", "_script_index", "_script_timer", "_hammer_cooldown", "_dash_cooldown", "_dash_target",
	"_dash_origin", "_dash_duration", "_dash_elapsed", "_summon_points", "_pending_color",
	"_burn_ticks", "_burn_cursor", "_burn_pending", "_poison_dps", "_slow", "_slow_time", "_ice_time",
	"vulnerability", "_vulnerability_applied", "_contact_cooldown"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false


func attach(main: Node) -> void:
	# Embedded test scenes must never overwrite the player's real save.
	_main = weakref(main) if get_tree().current_scene == main else null
	_clock = 0.0


func is_live(main: Node) -> bool:
	return _main != null and _main.get_ref() == main


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= AUTO_INTERVAL:
		_clock = 0.0
		checkpoint()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		checkpoint()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()


func checkpoint() -> bool:
	var main: Node = _main.get_ref() if _main != null else null
	if not is_instance_valid(main) or not RunState.is_running or RunState.is_dead:
		return false
	return write_run(main)


func _fields(object: Object, keys: Array) -> Dictionary:
	var result := {}
	for key in keys:
		var value: Variant = object.get(key)
		result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result


func _restore_fields(object: Object, data: Dictionary) -> void:
	for key in data:
		var existing: Variant = object.get(key)
		if existing is Array and data[key] is Array:
			existing.assign(data[key])
		else:
			object.set(key, data[key])


func snapshot(main: Node) -> Dictionary:
	Skills.flush_damage_estimates()
	var p: Player = main.player
	var refs := {}
	for key in MOD_REFS:
		var m: StatModifierResource = Skills.get(key)
		if m != null:
			refs[key] = m.source
	var skill_ids: Array = Skills.unlocked.keys()
	var relic_ids: Array[StringName] = []
	for relic in Skills.owned_relics:
		relic_ids.append(relic.id)
	var ui := {"levels": main._level_ups_pending, "weapon_rewards": main._weapon_rewards.duplicate(),
		"level_options": [], "rerolls": main.level_up_panel._rerolls_left, "weapon_choices": []}
	if main.level_up_panel.visible:
		for node in main.level_up_panel._options:
			ui.level_options.append(node.id)
	if main.weapon_choice_panel.visible:
		ui.weapon_choices = main.weapon_choice_panel._choices.duplicate()
	var data := {"version": VERSION, "character": RunState.selected_character_id,
		"run": _fields(RunState, RUN_FIELDS), "player": _fields(p, PLAYER_FIELDS),
		"player_stats": p.stats.save_data(), "weapon_stats": p.weapon.stats.save_data(),
		"weapons": p.weapon.owned_forms.duplicate(), "skills": skill_ids, "relics": relic_ids,
		"skill_state": _fields(Skills, SKILL_FIELDS), "mod_refs": refs, "ui": ui,
		"director": _fields(Director, DIRECTOR_FIELDS), "rng_state": RunState.rng.state,
		"rng_seed": RunState.rng.seed, "director_rng_state": Director._rng.state, "director_rng_seed": Director._rng.seed,
		"boss_defeated": Director._boss_spawned and not is_instance_valid(Director.boss),
		"hole": _fields(main.get_node("World/BlackHoleField"), HOLE_FIELDS),
		"summon": _fields(main.get_node("World/SummonField"), SUMMON_FIELDS)}
	if is_instance_valid(Director.boss) and not Director.boss.is_dead:
		data.boss = _fields(Director.boss, BOSS_FIELDS)
	elif Director._boss_spawned:
		data.boss_defeated = true
	data.hex_boss_defeated = Director._hex_boss_spawned and (not is_instance_valid(Director.hex_boss) or Director.hex_boss.is_dead)
	if is_instance_valid(Director.hex_boss) and not Director.hex_boss.is_dead:
		data.hex_boss = _fields(Director.hex_boss, HEX_BOSS_FIELDS)
	if Pickups.field != null:
		data.pickups = Pickups.field.save_data()
	if is_instance_valid(Director.merchant) and not Director.merchant._leaving:
		data.merchant = _fields(Director.merchant, ["global_position", "_lifetime"])
	if is_instance_valid(Director.altar) and not Director.altar._leaving:
		data.altar = _fields(Director.altar, ["global_position", "_lifetime", "_traded"])
		data.altar.open = main.altar_panel.visible
	if main.shop_panel.visible:
		data.shop = main.shop_panel.save_data()
	return data


func write_run(main: Node) -> bool:
	if not is_instance_valid(main.player) or main.player.health <= 0.0 or RunState.is_dead:
		return false
	var file := FileAccess.open(storage_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(snapshot(main))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	var absolute := ProjectSettings.globalize_path(storage_path)
	if FileAccess.file_exists(storage_path):
		DirAccess.copy_absolute(absolute, absolute + ".bak")
	return DirAccess.rename_absolute(absolute + ".tmp", absolute) == OK


func read_run() -> Dictionary:
	for path in [storage_path, storage_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var data: Variant = file.get_var(false)
		if data is Dictionary and data.get("version") == VERSION and data.has_all(["run", "player", "player_stats", "weapon_stats", "skills", "relics", "weapons"]):
			return data
	return {}


func request_continue() -> bool:
	pending = read_run()
	if pending.is_empty():
		return false
	RunState.selected_character_id = StringName(pending.get("character", &"prism"))
	return true


func clear_run() -> void:
	pending.clear()
	for path in [storage_path, storage_path + ".bak", storage_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func restore_run(main: Node, data: Dictionary) -> void:
	var p: Player = main.player
	Skills.unlocked.clear()
	for id in data.skills:
		var node := Skills.get_node_by_id(StringName(id))
		if node != null:
			Skills.unlocked[node.id] = node
	Skills.owned_relics.clear()
	for id in data.relics:
		var relic := Skills.get_relic(StringName(id))
		if relic != null:
			Skills.owned_relics.append(relic)
	for id in data.weapons:
		p.weapon.acquire_form(StringName(id))
	p.stats.restore_data(data.player_stats)
	p.weapon.stats.restore_data(data.weapon_stats)
	_restore_fields(Skills, data.get("skill_state", {}))
	for key in MOD_REFS:
		Skills.set(key, null)
		var source: StringName = data.get("mod_refs", {}).get(key, &"")
		for block in [p.stats, p.weapon.stats]:
			for modifier in block._modifiers:
				if source != &"" and modifier.source == source:
					Skills.set(key, modifier)
	_restore_fields(RunState, data.run)
	p.refresh_derived()
	_restore_fields(p, data.player)
	p.color_index = RunState.color_index
	p._display_color = RunState.current_color()
	p._color_from = p._display_color
	p._color_to = p._display_color
	p._color_blend = 1.0
	if p._speed_burst_time > 0.0:
		p.collision_mask = 0
	p.queue_redraw()
	_restore_fields(Director, data.get("director", {}))
	Director._boss_spawned = bool(data.get("boss_defeated", false))
	if data.has("boss"):
		var boss := Director.spawn_boss_now()
		if boss != null:
			_restore_fields(boss, data.boss)
			boss._refresh_healthbar()
	Director._hex_boss_spawned = bool(data.get("hex_boss_defeated", false))
	if data.has("hex_boss"):
		var hex := Director.spawn_hex_boss_now()
		if hex != null:
			_restore_fields(hex, data.hex_boss)
			hex._refresh_healthbar()
			hex._request_redraw()
	if data.has("merchant"):
		var merchant := Director.spawn_merchant_now(data.merchant.global_position)
		if merchant != null:
			_restore_fields(merchant, data.merchant)
	if data.has("altar"):
		var altar := Director.spawn_altar_now(data.altar.global_position)
		if altar != null:
			var state: Dictionary = data.altar.duplicate()
			state.erase("open")
			_restore_fields(altar, state)
	_restore_fields(Director, data.get("director", {}))
	_restore_fields(main.get_node("World/BlackHoleField"), data.get("hole", {}))
	main.get_node("World/BlackHoleField")._request_redraw()
	_restore_fields(main.get_node("World/SummonField"), data.get("summon", {}))
	if data.has("pickups") and Pickups.field != null:
		Pickups.field.restore_data(data.pickups)
	RunState.rng.seed = int(data.get("rng_seed", 0))
	RunState.rng.state = int(data.get("rng_state", 0))
	Director._rng.seed = int(data.get("director_rng_seed", 0))
	Director._rng.state = int(data.get("director_rng_state", 0))
	EventBus.player_health_changed.emit(p.health, p.max_health)
	EventBus.gold_changed.emit(RunState.gold)
	EventBus.xp_changed.emit(RunState.xp, RunState.level)
	EventBus.run_time_changed.emit(RunState.elapsed)
	# Loading a color is not switching color: do not reroll dice or trigger relic attacks.
	RunState._emit_energy(true)


func restore_ui(main: Node, data: Dictionary) -> void:
	var ui: Dictionary = data.get("ui", {})
	main._level_ups_pending = int(ui.get("levels", 0))
	main._weapon_rewards.assign(ui.get("weapon_rewards", []))
	if data.has("shop"):
		main._active_merchant = Director.spawn_merchant_now()
		main.shop_panel.restore_data(data.shop, main.player)
		main.hud_control.hide()
		RunState.request_pause(&"shop")
	if data.get("altar", {}).get("open", false) and is_instance_valid(Director.altar):
		main._active_altar = Director.altar
		Director.altar._interacted = true
		main.altar_panel.open(Director.altar, main.player)
		main.hud_control.hide()
		RunState.request_pause(&"altar")
	var options: Array[SkillNodeResource] = []
	for id in ui.get("level_options", []):
		var node := Skills.get_node_by_id(StringName(id))
		if node != null and Skills.is_available(node):
			options.append(node)
	if not options.is_empty():
		main.level_up_panel.open(options, int(ui.get("rerolls", 0)))
		main.hud_control.hide()
		RunState.request_pause(&"level_up")
	elif main._level_ups_pending > 0:
		main._open_next_level_up()
	if not ui.get("weapon_choices", []).is_empty():
		main.weapon_choice_panel.restore_reward(main.player, ui.weapon_choices)
		main.hud_control.hide()
		RunState.request_pause(&"weapon_reward")
	main._flush_pending_events()
