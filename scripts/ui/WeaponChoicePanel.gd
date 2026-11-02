class_name WeaponChoicePanel
extends Control
signal finished

var _player: Player
var _choices: Array[StringName] = []
var _rerolls_left := 0
var _primary_mode := false
var _loadout_only := false
var _choosing := false
var _generation := 0
var _title: Label
var _hint: Label
var _reroll_button: Button
var _back: Button
var _cards: GridContainer
var _scroll: ScrollContainer
var _box: PanelContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.005, 0.008, 0.02, 0.9)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_box = PanelContainer.new()
	add_child(_box)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.02, 0.035, 0.06, 0.98)
	panel.border_color = Color(0.25, 0.55, 0.7, 0.6)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(12)
	panel.content_margin_left = 20
	panel.content_margin_right = 20
	panel.content_margin_top = 18
	panel.content_margin_bottom = 18
	_box.add_theme_stylebox_override("panel", panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_box.add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	column.add_child(_title)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.custom_minimum_size.y = 48
	column.add_child(_hint)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_cards = GridContainer.new()
	_cards.columns = 3
	_cards.add_theme_constant_override("h_separation", 16)
	_cards.add_theme_constant_override("v_separation", 16)
	_scroll.add_child(_cards)
	_reroll_button = Button.new()
	_reroll_button.custom_minimum_size.y = 38
	_reroll_button.pressed.connect(_reroll)
	column.add_child(_reroll_button)
	_back = Button.new()
	_back.text = "返回 · 保持当前主武器"
	_back.pressed.connect(func():
		if _choosing: return
		visible = false
		if not _loadout_only: finished.emit())
	column.add_child(_back)

func open_reward(player_node: Player, source: String) -> bool:
	_player = player_node
	_primary_mode = false
	_loadout_only = false
	_choosing = false
	_generation += 1
	if not _roll_choices([]): return false
	_rerolls_left = Skills.weapon_reward_rerolls()
	_title.text = "选择武器"
	_hint.text = source + " · 获得新机制后，可选择主武器"
	_rebuild_cards()
	visible = true
	return true

func open_loadout(player_node: Player) -> void:
	_player = player_node
	if _player.weapon.owned_forms.is_empty(): return
	_generation += 1
	_choosing = false
	_loadout_only = true
	_show_primary_choices()
	visible = true

func _show_primary_choices() -> void:
	_primary_mode = true
	_choices.assign(_player.weapon.owned_forms)
	_rerolls_left = 0
	_title.text = "选择主武器"
	_hint.text = "主武器决定攻击方式，其他武器提供被动兼容"
	_rebuild_cards()

func restore_reward(player_node: Player, choices: Array, rerolls: int = 0, primary_mode := false) -> void:
	_player = player_node
	_choices.assign(choices)
	_rerolls_left = maxi(0, rerolls)
	_primary_mode = primary_mode
	_loadout_only = false
	_choosing = false
	_generation += 1
	_title.text = "选择主武器" if primary_mode else "选择武器"
	_hint.text = "继续未完成的武器选择"
	_rebuild_cards()
	visible = true

func _roll_choices(exclude: Array) -> bool:
	var pool: Array[StringName] = []
	for id in ContentDB.all_ids():
		if ContentDB.get_data(id) is WeaponTraitResource and not _player.weapon.has_form(id) and not exclude.has(id): pool.append(id)
	if pool.is_empty(): return false
	pool.sort()
	for i in range(pool.size()-1, 0, -1):
		var j := RunState.rng.randi_range(0, i)
		var swap := pool[i]
		pool[i] = pool[j]
		pool[j] = swap
	pool.resize(mini(3, pool.size()))
	_choices.assign(pool)
	return true

func _reroll() -> void:
	if not visible or _primary_mode or _choosing or _rerolls_left <= 0: return
	if not _roll_choices(_choices.duplicate()): return
	_rerolls_left -= 1
	Audio.play(&"ui_click")
	_rebuild_cards()

func _refresh_reroll_button() -> void:
	_reroll_button.visible = not _primary_mode and _rerolls_left > 0
	_reroll_button.text = "重选一次（剩余 %d）" % _rerolls_left
	_back.visible = _primary_mode

func _rebuild_cards() -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	var width := minf(1060, size.x-48)
	_cards.columns = mini(3, maxi(1, int(width / 240)))
	var card_width := (width - 40 - 16 * (_cards.columns-1)) / _cards.columns
	var card_height := 280.0 if not _primary_mode else 240.0
	for i in _choices.size():
		var id := _choices[i]
		var data := ContentDB.get_data(id) as WeaponTraitResource
		if data == null: continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(card_width, card_height)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.035, 0.065, 0.10) if state == "normal" else Color(0.08, 0.15, 0.22)
			style.border_color = WeaponIcon.COLORS.get(id, Color.WHITE) * (0.4 if state == "normal" else 0.9)
			style.set_border_width_all(1)
			style.set_corner_radius_all(10)
			button.add_theme_stylebox_override(state, style)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 18
		column.offset_right = -18
		column.offset_top = 18
		column.offset_bottom = -18
		column.add_theme_constant_override("separation", 12)
		button.add_child(column)
		var icon := WeaponIcon.new()
		icon.weapon_id = id
		icon.custom_minimum_size = Vector2(74, 74)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(icon)
		for text in ["%d  %s%s" % [i+1, data.display_name, " · 当前" if _player.weapon.primary_form == id else ""], data.brief, _reward_preview(id)]:
			var label := Label.new()
			label.text = text
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 21 if column.get_child_count() == 1 else 12)
			column.add_child(label)
		button.resized.connect(func(): button.pivot_offset = button.size * 0.5)
		button.mouse_entered.connect(func():
			_animate_card(button, 1.035)
			if _primary_mode: _hint.text = _full_primary_preview(id))
		button.mouse_exited.connect(func(): _animate_card(button, 1.0))
		button.pressed.connect(_choose.bind(i))
		_cards.add_child(button)
	_scroll.custom_minimum_size = Vector2(width-40, minf(size.y-230, card_height * ceilf(float(_choices.size())/_cards.columns) + 16))
	_box.custom_minimum_size = Vector2(width, 0)
	_box.size = Vector2(width, 0)
	_refresh_reroll_button()
	_layout_later.call_deferred()

func _layout_later() -> void:
	_box.reset_size()
	_box.position = (size - _box.size) * 0.5

func _process(_delta: float) -> void:
	if visible:
		_box.reset_size()
		_box.position = (size - _box.size) * 0.5

func _animate_card(button: Button, target: float) -> void:
	if button.has_meta("hover_tween"):
		var previous: Tween = button.get_meta("hover_tween")
		if previous != null: previous.kill()
	var tween := button.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	button.set_meta("hover_tween", tween)
	tween.tween_property(button, "scale", Vector2.ONE * target, 0.12)

func _full_primary_preview(id: StringName) -> String:
	var parts := PackedStringArray()
	for other in _player.weapon.owned_forms:
		if other != id: parts.append(WeaponRuntime.secondary_description(other))
	return " · ".join(parts)

func _reward_preview(id: StringName) -> String:
	var data := ContentDB.get_data(id) as WeaponTraitResource
	var summary := "%d%%伤害 · %d%%攻速 · 射程%.0f" % [int(data.damage_scale*100), int(data.fire_rate_scale*100), _player.weapon.attack_range(id)]
	if id in [&"sword", &"scythe"] and (_player.weapon.has_form(&"sword") or _player.weapon.has_form(&"scythe")):
		summary += "\n剑×镰刀：投出旋转镰刀"
	if _primary_mode:
		return summary + "\n其余%d把武器提供被动兼容" % maxi(0, _player.weapon.owned_forms.size()-1)
	return summary + "\n副效果：" + WeaponRuntime.secondary_description(id)

func _choose(index: int) -> void:
	if _choosing or index < 0 or index >= _choices.size(): return
	var id := _choices[index]
	var card := _cards.get_child(index) as Control
	CardFeedback.play(self, Rect2(card.global_position, card.size), WeaponIcon.COLORS.get(id, Color.WHITE))
	_choosing = true
	Audio.play(&"ui_buy")
	if _primary_mode:
		_player.weapon.select_primary(id)
		visible = false
		if not _loadout_only: finished.emit()
		else: GameSave.checkpoint()
		return
	if not _player.weapon.acquire_form(id):
		_choosing = false
		return
	if _player.weapon.owned_forms.size() == 1:
		visible = false
		finished.emit()
	else:
		_show_primary_choices()
		var generation := _generation
		get_tree().create_timer(0.22).timeout.connect(func():
			if generation == _generation: _choosing = false)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		if _primary_mode and not _choosing:
			visible = false
			if not _loadout_only: finished.emit()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_R and _rerolls_left > 0:
		_reroll()
		get_viewport().set_input_as_handled()
		return
	var index: int = event.keycode-KEY_1
	if index >= 0 and index < _choices.size():
		_choose(index)
		get_viewport().set_input_as_handled()
