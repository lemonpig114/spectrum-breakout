class_name WeaponChoicePanel
extends Control

signal finished

var _player: Player
var _stage := &""
var _choices: Array[StringName] = []
var _title: Label
var _hint: Label
var _cards: VBoxContainer
var _box: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.005, 0.008, 0.02, 0.79)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_box = PanelContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER)
	_box.custom_minimum_size = Vector2(470, 0)
	add_child(_box)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.045, 0.085, 0.98)
	panel_style.border_color = Color(0.38, 0.82, 1.0, 0.85)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(9)
	panel_style.shadow_color = Color(0.0, 0.4, 1.0, 0.27)
	panel_style.shadow_size = 16
	_box.add_theme_stylebox_override("panel", panel_style)
	var margin := MarginContainer.new()
	for side in [&"left", &"right"]:
		margin.add_theme_constant_override(StringName("margin_%s" % side), 22)
	for side in [&"top", &"bottom"]:
		margin.add_theme_constant_override(StringName("margin_%s" % side), 18)
	_box.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	column.add_child(_title)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	column.add_child(_hint)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 8)
	column.add_child(_cards)


func open_reward(player_node: Player, source: String) -> bool:
	_player = player_node
	_choices.clear()
	for id in ContentDB.all_ids():
		if ContentDB.get_data(id) is WeaponTraitResource and not _player.weapon.has_form(id):
			_choices.append(id)
	if _choices.is_empty():
		return false
	_choices.sort()
	for i in range(_choices.size() - 1, 0, -1):
		var j := RunState.rng.randi_range(0, i)
		var swap := _choices[i]
		_choices[i] = _choices[j]
		_choices[j] = swap
	_choices.resize(mini(3, _choices.size()))
	_stage = &"acquire"
	_title.text = "选择武器"
	_hint.text = "%s · 首件替换基础弹，后续融合机制" % source
	_rebuild_cards()
	visible = true
	return true


func open_primary_choice(player_node: Player, source: String) -> bool:
	_player = player_node
	_choices = _player.weapon.owned_forms.duplicate()
	if _choices.is_empty():
		return false
	_stage = &"primary"
	_title.text = "选择主形态"
	_hint.text = "%s · 主形态决定攻击动作与倍率" % source
	_rebuild_cards()
	visible = true
	return true


func _rebuild_cards() -> void:
	for child in _cards.get_children():
		child.queue_free()
	for i in _choices.size():
		var id := _choices[i]
		var data := ContentDB.get_data(id) as WeaponTraitResource
		if data == null:
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(420, 76 if GameInput.touch_controls_active else 66)
		button.add_theme_font_size_override("font_size", 17)
		for state in ["normal", "hover", "pressed"]:
			var card_style := StyleBoxFlat.new()
			card_style.bg_color = Color(0.07, 0.12, 0.20, 0.96) if state == "normal" else Color(0.12, 0.25, 0.38, 0.98)
			card_style.border_color = Color(0.30, 0.65, 0.85, 0.5) if state == "normal" else Color(0.55, 0.95, 1.0, 0.95)
			card_style.set_border_width_all(1)
			card_style.set_corner_radius_all(5)
			button.add_theme_stylebox_override(state, card_style)
		button.text = "%d  %s  ·  %s\n%s" % [i + 1, data.display_name, data.brief,
			("主形态：" + data.description) if _stage == &"acquire" else _preview(id)]
		button.pressed.connect(_choose.bind(i))
		_cards.add_child(button)
	_box.position = (size - Vector2(470, 85 + _choices.size() * 78)) * 0.5


func _preview(id: StringName) -> String:
	var data := ContentDB.get_data(id) as WeaponTraitResource
	var others := PackedStringArray()
	for owned in _player.weapon.owned_forms:
		if owned != id:
			var other := ContentDB.get_data(owned) as WeaponTraitResource
			if other != null:
				others.append(other.brief)
	return "主：%s  ·  融合：%s" % [data.brief, "、".join(others)]


func _choose(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	var id := _choices[index]
	if _stage == &"acquire":
		if not _player.weapon.acquire_form(id):
			return
		Audio.play(&"ui_buy")
		if _player.weapon.owned_forms.size() > 1:
			_stage = &"primary"
			_title.text = "选择主形态"
			_hint.text = "主形态决定攻击动作与倍率 · 下次融合时可再选择"
			_choices = _player.weapon.owned_forms.duplicate()
			_rebuild_cards()
			return
	else:
		_player.weapon.select_primary(id)
	visible = false
	_stage = &""
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var index: int = event.keycode - KEY_1
	if index >= 0 and index < _choices.size():
		_choose(index)
		get_viewport().set_input_as_handled()
