class_name RelicChoicePanel
extends Control

## 非模态奖励条：战斗继续；其它面板暂停游戏时隐藏、停表。
const AUTO_TAKE_SECONDS := 5.0
var _ticket := -1
var _remaining := AUTO_TAKE_SECONDS
var _card: PanelContainer
var _name: Label
var _details: Label
var _countdown: Label
var _progress: ProgressBar
var _take_button: Button
var _discard_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.gui_input.connect(_consume_card_input)
	add_child(_card)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	_card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	margin.add_child(body)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	body.add_child(actions)
	_name = _label(actions, 15, Color.WHITE)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_countdown = _label(actions, 10, Color(0.65, 0.76, 0.86))
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_discard_button = _button(actions, "丢弃", false)
	_take_button = _button(actions, "拾取", true)
	_details = _label(body, 11, Color(0.75, 0.82, 0.90))
	_details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_details.clip_text = true
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 2
	_progress.show_percentage = false
	_progress.max_value = AUTO_TAKE_SECONDS
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var progress_background := StyleBoxFlat.new()
	progress_background.bg_color = Color(0.4, 0.5, 0.6, 0.08)
	_progress.add_theme_stylebox_override("background", progress_background)
	body.add_child(_progress)
	# 文字区域不阻止事件向卡片冒泡；卡片外仍然可以瞄准、切色。
	for label in [_name, _details, _countdown]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _label(parent: Node, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	parent.add_child(label)
	return label


func _button(parent: Node, title: String, take: bool) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(40, 23)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	for state in ["normal", "hover", "pressed"]:
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.35, 0.48, 0.60, 0.12 if state == "normal" else 0.30)
		background.set_corner_radius_all(3)
		button.add_theme_stylebox_override(state, background)
	button.pressed.connect(func(): _choose(take))
	parent.add_child(button)
	return button


func _consume_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()


func _process(delta: float) -> void:
	if RunState.is_dead or not RunState.is_running or Skills.pending_relic_offers.is_empty():
		visible = false
		_ticket = -1
		return
	if get_tree().paused:
		visible = false
		return
	var offer: Dictionary = Skills.pending_relic_offers[0]
	if _ticket != int(offer.ticket):
		_ticket = int(offer.ticket)
		_remaining = AUTO_TAKE_SECONDS
		_show_offer(offer)
	visible = true
	_remaining = maxf(0.0, _remaining - delta)
	_progress.value = _remaining
	_countdown.text = "自动 %.1fs" % _remaining
	_layout_card()
	if _remaining <= 0.0:
		_choose(true)


func _show_offer(offer: Dictionary) -> void:
	var relic := Skills.get_relic(offer.id)
	if relic == null:
		Skills.resolve_relic_offer(_ticket, false)
		return
	var tint := Skills._rarity_color(relic.rarity).clamp()
	_name.text = relic.display_name
	_name.add_theme_color_override("font_color", tint)
	_details.text = relic.brief_description
	_card.tooltip_text = relic.description
	if relic.side != &"" and Skills.is_unlocked(StringName("path_%s_4" % String(relic.side))):
		_card.tooltip_text += "\n契约四阶：属性效果按双倍结算"
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.018, 0.025, 0.045, 0.55)
	background.border_color = Color(tint, 0.28)
	background.set_border_width_all(1)
	background.border_width_top = 1
	background.set_corner_radius_all(5)
	background.shadow_color = Color(0, 0, 0, 0.18)
	background.shadow_size = 4
	_card.add_theme_stylebox_override("panel", background)
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = Color(tint, 0.55)
	_progress.add_theme_stylebox_override("fill", progress_fill)
	_layout_card()


func _layout_card() -> void:
	var width := minf(420.0, size.x - 24.0)
	_card.size = Vector2(width, 0)
	_card.position = Vector2((size.x - width) * 0.5, 80.0)


func _choose(take: bool) -> void:
	if not visible or get_tree().paused or RunState.is_dead:
		return
	Skills.resolve_relic_offer(_ticket, take)
	if not take:
		Audio.play(&"ui_click")
	visible = false
	_ticket = -1
