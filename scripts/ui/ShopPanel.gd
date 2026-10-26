class_name ShopPanel
extends Control

## 商人货架：基础 4 件遗物；每次捐款升级 +1 格，最多 14 格。
## 面板在暂停状态下运行（process_mode = WHEN_PAUSED），关闭后通过 closed 交给 Main 收尾。

signal closed
## 隐藏机制：本次到访买空整排货架时发出一次；由 Main 提前下一只商人。
signal shelf_cleared

const CARD_SIZE := Vector2(240.0, 226.0)
const CARD_COMPACT_HEIGHT := 194.0
const CARD_MIN_WIDTH := 160.0
const CARD_ROW_GAP := 18.0
const REROLL_BASE := 8
const REROLL_GROWTH := 4
const PURCHASE_GROWTH := 5
const HEAL_HEARTS := 1.5
## 捐款升级：越早越贵，价格随游戏时间非线性下降，最低 0；每级价格大幅增加。
const UPGRADE_BASE := 60.0
const UPGRADE_ZERO_TIME := 300.0
const UPGRADE_GROWTH := 0.18

const GOLD := Color(1.0, 0.82, 0.34, 1.0)
const GOLD_DIM := Color(0.78, 0.62, 0.28, 1.0)
const DEMON_ACCENT := Color(1.0, 0.3, 0.34, 1.0)
const ANGEL_ACCENT := Color(0.62, 0.82, 1.0, 1.0)
const BUY_LINES := ["谢谢惠顾，下次还来。", "好眼光，这件很适合你。", "这笔交易，我很满意。", "拿稳了，别在路上弄丢。", "祝你撑过下一波。", "识货的人总能找到好东西。"]
const UPGRADE_LINES := ["多谢投资，货架马上扩张。", "赞助收到，给你看点好的。", "眼光长远，我喜欢。", "货架升级，稀有货更容易来。", "这笔钱会花在刀刃上。", "欢迎成为本店贵客。"]
const REROLL_LINES := ["换一批，或许有惊喜。", "再看看这些如何？", "运气总会轮到你。", "新货到了，慢慢挑。", "这一轮你会看中什么？"]

var _player: Player
var _offers: Array[RelicResource] = []
var _offer_prices: Array[int] = []
var _display_gold := 0.0
var _speech := ""
var _speech_time := 0.0
var _squint_time := 0.0
var _coin_flights: Array[Dictionary] = []
var _sold: Array[bool] = []
var _hover := -1
var _hover_button := -1
var _appear := 0.0
var _message := ""
var _message_success := false
var _message_time := 0.0
var _rerolls := 0
var _reroll_cost := REROLL_BASE
var _free_rerolls := 0
var _heal_used := false
var _shelf_bonus_used := false
var _time := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_font = ThemeDB.fallback_font


func open(player_node: Player) -> void:
	_player = player_node
	_rerolls = 0
	_reroll_cost = _next_reroll_cost()
	_free_rerolls = Skills.free_rerolls()
	_heal_used = false
	_shelf_bonus_used = false
	_hover = -1
	_hover_button = -1
	_appear = 0.0
	_message = ""
	_message_time = 0.0
	_display_gold = float(RunState.gold)
	_speech = "欢迎，看看今天的货。"
	_speech_time = 3.0
	_squint_time = 0.0
	_coin_flights.clear()
	_restock([])
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	_offers.clear()
	_offer_prices.clear()
	_sold.clear()
	_hover = -1
	_hover_button = -1
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_font = ThemeDB.fallback_font
	_appear = minf(1.0, _appear + delta * 7.0)
	_message_time = maxf(0.0, _message_time - delta)
	_speech_time = maxf(0.0, _speech_time - delta)
	_squint_time = maxf(0.0, _squint_time - delta)
	_display_gold = move_toward(_display_gold, float(RunState.gold), maxf(35.0, absf(_display_gold - float(RunState.gold)) * 6.0) * delta)
	for i in range(_coin_flights.size() - 1, -1, -1):
		_coin_flights[i]["age"] = float(_coin_flights[i]["age"]) + delta
		if float(_coin_flights[i]["age"]) >= 0.5:
			_coin_flights.remove_at(i)
	queue_redraw()


# ── 交易 ────────────────────────────────────────────────────────

func _restock(exclude: Array[StringName]) -> void:
	_offers = Skills.shop_offers(Skills.shop_slots(), exclude)
	_offer_prices.clear()
	for relic in _offers:
		_offer_prices.append(_price_of(relic))
	_sold.clear()
	_sold.resize(_offers.size())
	_sold.fill(false)


func _price_of(relic: RelicResource) -> int:
	return relic.price + int(RunState.elapsed / 45.0) * 3 + Skills.shop_purchases * PURCHASE_GROWTH


func _heal_price() -> int:
	return 14 + int(RunState.elapsed / 60.0) * 5


## 每次刷新后，下次刷新价格线性增长；免费刷新也计入次数。
func _next_reroll_cost() -> int:
	return REROLL_BASE + Skills.shop_rerolls * REROLL_GROWTH


func _upgrade_price() -> int:
	var time_factor := clampf(1.0 - RunState.elapsed / UPGRADE_ZERO_TIME * 0.4, 0.6, 1.0)
	var level := float(Skills.shop_level)
	return int(round(UPGRADE_BASE * time_factor * (1.0 + 0.8 * level + UPGRADE_GROWTH * level * level * level)))


func _buy(index: int) -> void:
	if index < 0 or index >= _offers.size():
		return
	if _sold[index]:
		_flash("已经买过了", false)
		return

	var relic := _offers[index]
	var price := _offer_prices[index]
	if not RunState.spend_gold(price):
		_flash("金币不足，还差 %d" % (price - RunState.gold), false)
		return

	if not Skills.grant_relic(relic.id):
		RunState.refund_gold(price)
		_flash("无法获得这件遗物", false)
		return

	_sold[index] = true
	Skills.shop_purchases += 1
	if relic.id == &"epic_vip_card":
		_free_rerolls += 2
		var exclude: Array[StringName] = []
		for stocked in _offers:
			exclude.append(stocked.id)
		var extra := Skills.shop_offers(1, exclude)
		if not extra.is_empty() and _offers.size() < Skills.shop_slots():
			_offers.append(extra[0])
			_offer_prices.append(_price_of(extra[0]))
			_sold.append(false)
	_flash("获得「%s」" % relic.display_name, true)
	_say(BUY_LINES)
	_spawn_coins(_card_rects()[index].get_center())
	_maybe_award_shelf_bonus()
	queue_redraw()


## 买空整排货架时悄悄把下一只商人提前；每次到访只发一次，重 roll 后再买空也不叠加。
func _maybe_award_shelf_bonus() -> void:
	if _sold.is_empty():
		return
	for sold in _sold:
		if not sold:
			return
	_squint_time = 1.2
	_speech = "好货都被你挑光了。"
	_speech_time = 3.0
	if not _shelf_bonus_used:
		_shelf_bonus_used = true
		shelf_cleared.emit()


func _reroll() -> void:
	if _free_rerolls > 0:
		_free_rerolls -= 1
	elif not RunState.spend_gold(_reroll_cost):
		_flash("金币不足，还差 %d" % (_reroll_cost - RunState.gold), false)
		return

	var exclude: Array[StringName] = []
	for relic in _offers:
		exclude.append(relic.id)
	_rerolls += 1
	Skills.shop_rerolls += 1
	_reroll_cost = _next_reroll_cost()
	_restock(exclude)
	_squint_time = 0.0
	_hover = -1
	_flash("货架已刷新", true)
	_say(REROLL_LINES)
	_spawn_coins(_button_rects()[2].get_center())
	queue_redraw()


## 捐款升级：+1 货架格，并立刻补上第 N+1 件商品。
func _upgrade() -> void:
	if not Skills.can_upgrade_shop():
		_flash("货架已经满格了", false)
		return

	var exclude: Array[StringName] = []
	for relic in _offers:
		exclude.append(relic.id)
	var has_candidate := false
	for relic in Skills.shop_relic_pool():
		if not exclude.has(relic.id):
			has_candidate = true
			break
	if not has_candidate:
		_flash("没有更多货品可上架", false)
		return

	var price := _upgrade_price()
	if not RunState.spend_gold(price):
		_flash("金币不足，还差 %d" % (price - RunState.gold), false)
		return
	if not Skills.upgrade_shop():
		RunState.refund_gold(price)
		_flash("货架已经满格了", false)
		return

	var extra := Skills.shop_offers(1, exclude)
	if extra.is_empty():
		RunState.refund_gold(price)
		Skills.shop_level -= 1
		_flash("没有更多货品可上架", false)
		return
	_offers.append(extra[0])
	_offer_prices.append(_price_of(extra[0]))
	_sold.append(false)
	_say(UPGRADE_LINES)
	_spawn_coins(_button_rects()[1].get_center())
	_flash(
		"商店升到 Lv.%d · 货架 %d 格" % [Skills.shop_level + 1, Skills.shop_slots()],
		true
	)
	queue_redraw()


func _heal() -> void:
	if _heal_used:
		_flash("这次已经回复过了", false)
		return
	var price := _heal_price()
	if not RunState.spend_gold(price):
		_flash("金币不足，还差 %d" % (price - RunState.gold), false)
		return

	_heal_used = true
	if _player != null and is_instance_valid(_player):
		# 生命以“颗”为单位，回复量固定 1.5 颗，不随生命上限缩放。
		_player.heal(HEAL_HEARTS)
	_flash("回复 %.1f 颗心" % HEAL_HEARTS, true)
	_say(BUY_LINES)
	_spawn_coins(_button_rects()[0].get_center())
	queue_redraw()


func _say(lines: Array) -> void:
	_speech = str(lines[RunState.rng.randi_range(0, lines.size() - 1)])
	_speech_time = 3.0


func _spawn_coins(origin: Vector2) -> void:
	var destination := Vector2(size.x * 0.5, _grid_top() - 92.0)
	for i in 4:
		_coin_flights.append({
			"from": origin + Vector2(float(i - 2) * 9.0, 0.0),
			"to": destination + Vector2(float(i - 2) * 5.0, 0.0),
			"age": -float(i) * 0.045,
		})


func _leave() -> void:
	Audio.play(&"ui_click")
	close()
	closed.emit()


func _flash(message: String, success: bool) -> void:
	_message = message
	_message_time = 1.8
	_message_success = success
	Audio.play(&"ui_buy" if success else &"ui_click")
	queue_redraw()


# ── 绘制 ────────────────────────────────────────────────────────

func _draw() -> void:
	if not visible or _font == null:
		return

	var ease := 1.0 - pow(1.0 - _appear, 3.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.86 * ease))

	var rects := _card_rects()
	var top := _grid_top()
	var offset := (1.0 - ease) * 16.0

	_draw_text_centered(
		"流浪商人",
		top - 104.0 + offset,
		40,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.98 * ease)
	)
	_draw_text_centered(
		"商店 Lv.%d · 货架 %d 格" % [
			Skills.shop_level + 1, Skills.shop_slots()
		],
		top - 68.0 + offset,
		15,
		Color(1.0, 1.0, 1.0, 0.55 * ease)
	)
	_draw_text_centered("金币 %d" % roundi(_display_gold), top - 39.0 + offset, 22,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.95 * ease))
	_draw_shop_health(ease)
	_draw_merchant(Vector2(size.x * 0.5 + 326.0, top - 64.0 + offset), ease)
	if _speech_time > 0.0:
		_draw_merchant_speech(top + offset, ease)

	for i in rects.size():
		if i >= _offers.size():
			break
		var rect := rects[i]
		rect.position.y += offset
		_draw_card(rect, _offers[i], i, i == _hover, ease)

	_draw_buttons(offset, ease)
	for coin in _coin_flights:
		var progress := clampf(float(coin["age"]) / 0.5, 0.0, 1.0)
		if progress <= 0.0:
			continue
		var arc := (coin["from"] as Vector2).lerp(coin["to"] as Vector2, progress)
		arc.y -= sin(progress * PI) * 38.0
		draw_circle(arc, 3.0 * (1.0 - progress * 0.45),
			Color(GOLD.r, GOLD.g, GOLD.b, (1.0 - progress) * ease))

	if _message_time > 0.0:
		var alpha := clampf(_message_time / 0.35, 0.0, 1.0)
		var color := GOLD if _message_success else Color(1.0, 0.42, 0.42, 1.0)
		_draw_text_centered(
			_message,
			_message_baseline() + offset,
			15,
			Color(color.r, color.g, color.b, alpha)
		)

	var shop_hint := "点击购买 · 1-9 购买 · U 捐款升级 · R 重掷 · H 回复 · Esc 离开"
	if GameInput.touch_controls_active:
		shop_hint = "点按商品购买 · 点按下方选项操作"
	_draw_text_centered(
		shop_hint,
		size.y - 30.0,
		13,
		Color(1.0, 1.0, 1.0, 0.38 * ease)
	)


func _draw_shop_health(alpha: float) -> void:
	var hp := 0.0
	var max_hp := 0.0
	if _player != null and is_instance_valid(_player):
		hp = _player.health
		max_hp = _player.max_health
	var hearts := maxi(1, int(ceil(maxf(0.5, max_hp))))
	var shields := maxi(0, Skills.guardian_shields)
	if hearts + shields > 30:
		_draw_shop_heart(Vector2(36, 30), 1.0, alpha)
		var label := "%s / %s" % [_format_shop_health(hp), _format_shop_health(max_hp)]
		draw_string(_font, Vector2(52, 35), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(1.0, 0.86, 0.88, alpha))
		if shields > 0:
			var width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
			var shield_center := Vector2(66.0 + width, 30.0)
			_draw_shop_shield(shield_center, alpha)
			draw_string(_font, shield_center + Vector2(14, 5), "×%d" % shields,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.8, 0.95, 1.0, alpha))
		return
	for i in hearts:
		_draw_shop_heart(_shop_health_icon_center(i), clampf(hp - float(i), 0.0, 1.0), alpha)
	for i in shields:
		_draw_shop_shield(_shop_health_icon_center(hearts + i), alpha)
	var rows := (hearts + shields - 1) / 10
	draw_string(_font, Vector2(24, 58.0 + float(rows) * 24.0),
		"生命 %s / %s 心" % [_format_shop_health(hp), _format_shop_health(max_hp)],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1.0, 1.0, 1.0, 0.55 * alpha))


func _shop_health_icon_center(index: int) -> Vector2:
	return Vector2(36.0 + float(index % 10) * 24.0, 30.0 + float(index / 10) * 24.0)


func _draw_shop_heart(center: Vector2, fraction: float, alpha: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(-10, -3), center + Vector2(-9, -7),
		center + Vector2(-6, -9), center + Vector2(-2, -9),
		center + Vector2(0, -6), center + Vector2(2, -9),
		center + Vector2(6, -9), center + Vector2(9, -7),
		center + Vector2(10, -3), center + Vector2(9, 2),
		center + Vector2(0, 10), center + Vector2(-9, 2),
	])
	var outline := points.duplicate()
	outline.append(points[0])
	draw_colored_polygon(points, Color(0.12, 0.035, 0.065, 0.88 * alpha))
	draw_polyline(outline, Color(0.65, 0.21, 0.28, 0.56 * alpha), 1.3, true)
	if fraction <= 0.001:
		return
	var fill_color := Color(1.55, 0.13, 0.27, 0.96 * alpha)
	if fraction >= 0.999:
		draw_colored_polygon(points, fill_color)
	else:
		var clip := PackedVector2Array([
			center + Vector2(-11, -11), center + Vector2(-10.0 + 20.0 * fraction, -11),
			center + Vector2(-10.0 + 20.0 * fraction, 11), center + Vector2(-11, 11),
		])
		for piece in Geometry2D.intersect_polygons(points, clip):
			if piece.size() >= 3:
				draw_colored_polygon(piece, fill_color)
	draw_polyline(outline, Color(2.0, 0.43, 0.52, 0.9 * alpha), 1.3, true)


func _draw_shop_shield(center: Vector2, alpha: float) -> void:
	var shield := PackedVector2Array([
		center + Vector2(0, -10), center + Vector2(9, -7),
		center + Vector2(8, 2), center + Vector2(0, 9),
		center + Vector2(-8, 2), center + Vector2(-9, -7),
	])
	draw_colored_polygon(shield, Color(0.48, 0.8, 1.15, 0.5 * alpha))
	var outline := shield.duplicate()
	outline.append(shield[0])
	draw_polyline(outline, Color(0.78, 1.0, 1.5, 0.95 * alpha), 1.5, true)


func _format_shop_health(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value


func _draw_merchant(center: Vector2, alpha: float) -> void:
	var bob := sin(_time * 3.2) * 2.2
	var body := center + Vector2(0.0, bob)
	var dark := Color(0.44, 0.25, 0.06, alpha)
	var rim := Color(1.55, 1.02, 0.3, alpha)
	var light := Color(2.1, 1.48, 0.48, alpha)
	# 与场上商人相同的金币轮廓，页眉版本补上眼睛和嘴。
	for side in [-1.0, 1.0]:
		var shoulder := body + Vector2(side * 27.0, 1.0)
		var hand := shoulder + Vector2(side * 13.0, 8.0 + sin(_time * 2.5 + side) * 3.0)
		draw_line(shoulder, hand, dark, 4.0, true)
		draw_circle(hand, 4.0, rim)
		draw_line(body + Vector2(side * 11.0, 28.0), body + Vector2(side * 14.0, 42.0), dark, 4.0, true)
		draw_circle(body + Vector2(side * 14.0, 42.0), 4.0, rim)
	draw_circle(body, 31.0, rim)
	draw_circle(body, 27.0, light)
	draw_arc(body, 30.0, 0.0, TAU, 32, Color(2.4, 1.8, 0.68, alpha), 2.0)
	draw_arc(body + Vector2(-3, -2), 23.0, PI * 1.05, PI * 1.52, 12,
		Color(3.0, 2.4, 1.0, 0.85 * alpha), 2.0)
	var squint := _squint_time > 0.0 or fmod(_time, 4.2) < 0.12
	for side in [-1.0, 1.0]:
		var eye := body + Vector2(side * 10.0, -5.0)
		if squint:
			draw_line(eye + Vector2(-4, 1), eye + Vector2(4, -1), dark, 2.5, true)
		else:
			draw_circle(eye, 3.0, dark)
			draw_circle(eye + Vector2(-0.8, -0.8), 0.9, Color.WHITE)
	var talking := _speech_time > 0.0 and fmod(_time * 7.0, 1.0) < 0.5
	if talking:
		draw_circle(body + Vector2(0, 12), 3.1, dark)
	else:
		draw_arc(body + Vector2(0, 7), 8.0, 0.2, PI - 0.2, 12, dark, 2.0)


func _draw_merchant_speech(top: float, alpha: float) -> void:
	var fade := minf(1.0, _speech_time * 3.0) * alpha
	var rect := Rect2(Vector2(size.x * 0.5 + 82.0, top - 76.0), Vector2(194.0, 38.0))
	draw_rect(rect, Color(0.11, 0.09, 0.055, 0.94 * fade))
	draw_rect(rect, Color(GOLD.r, GOLD.g, GOLD.b, 0.68 * fade), false, 1.4)
	var tail := PackedVector2Array([
		Vector2(rect.end.x, rect.position.y + 14.0),
		Vector2(rect.end.x + 49.0, rect.position.y + 24.0),
		Vector2(rect.end.x, rect.position.y + 28.0),
	])
	draw_colored_polygon(tail, Color(0.11, 0.09, 0.055, 0.94 * fade))
	draw_polyline(PackedVector2Array([tail[0], tail[1], tail[2]]),
		Color(GOLD.r, GOLD.g, GOLD.b, 0.68 * fade), 1.2, true)
	draw_string(_font, rect.position + Vector2(8.0, 25.0), _speech,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 16.0, 12,
		Color(1.0, 0.94, 0.77, fade))


func _draw_card(
	rect: Rect2,
	relic: RelicResource,
	index: int,
	hovered: bool,
	alpha: float
) -> void:
	var sold := _sold[index]
	var price := _offer_prices[index]
	var affordable := RunState.gold >= price and not sold
	var accent := _accent_of(relic)
	var compact := rect.size.y < 214.0

	var border_alpha := 0.95 if hovered and affordable else 0.32
	draw_rect(rect, Color(0.05, 0.06, 0.09, 0.98 * alpha))
	draw_rect(
		rect,
		Color(accent.r, accent.g, accent.b, border_alpha * alpha),
		false,
		2.0
	)
	draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, 3.0)),
		Color(accent.r, accent.g, accent.b, (0.25 if sold else 0.9) * alpha)
	)

	draw_string(
		_font,
		rect.position + Vector2(14.0, 27.0),
		str(index + 1),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		15,
		Color(accent.r, accent.g, accent.b, 0.75 * alpha)
	)

	var tag := _rarity_name(relic)
	if relic.lucky:
		tag += " · 幸运"
	var owned := Skills.relic_count(relic.id)
	if owned > 0:
		tag += " · 已有 ×%d" % owned
	elif relic.repeat_label() != "":
		tag += " · %s" % relic.repeat_label()
	elif relic.max_stacks > 0:
		tag += " · %d/%d" % [owned, relic.max_stacks]
	var tag_width := _font.get_string_size(
		tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12
	).x
	draw_string(
		_font,
		rect.position + Vector2(rect.size.x - 12.0 - tag_width, 27.0),
		tag,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		Color(accent.r, accent.g, accent.b, 0.8 * alpha)
	)

	var name_y := 58.0 if compact else 68.0
	var name_size := 20 if rect.size.x < 200.0 else 23
	draw_string(
		_font,
		rect.position + Vector2(0.0, name_y),
		relic.display_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		name_size,
		Color(1.0, 1.0, 1.0, 0.96 * alpha)
	)

	var line_y := name_y + 18.0
	draw_line(
		rect.position + Vector2(18.0, line_y),
		rect.position + Vector2(rect.size.x - 18.0, line_y),
		Color(1.0, 1.0, 1.0, 0.09 * alpha),
		1.0
	)

	var narrow := rect.size.x < 200.0
	var desc_font := 11 if narrow else (12 if compact else 13)
	var desc_y := line_y + 22.0
	var max_lines := 4 if compact else 6
	draw_multiline_string(
		_font,
		rect.position + Vector2(14.0, desc_y),
		relic.description,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 28.0,
		desc_font,
		max_lines,
		Color(1.0, 1.0, 1.0, 0.72 * alpha)
	)

	draw_line(
		rect.position + Vector2(16.0, rect.size.y - 38.0),
		rect.end + Vector2(-16.0, -38.0),
		Color(1.0, 1.0, 1.0, 0.1 * alpha),
		1.0
	)

	if sold:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.55 * alpha))
		draw_string(
			_font,
			rect.position + Vector2(0.0, rect.size.y - 13.0),
			"已售出",
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x,
			15,
			Color(1.0, 1.0, 1.0, 0.42 * alpha)
		)
		return

	var price_color := GOLD if affordable else Color(0.75, 0.35, 0.35, 1.0)
	draw_string(
		_font,
		rect.position + Vector2(0.0, rect.size.y - 13.0),
		"%d 金币" % price,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		16,
		Color(price_color.r, price_color.g, price_color.b, alpha)
	)


func _draw_buttons(offset: float, alpha: float) -> void:
	var rects := _button_rects()
	for i in rects.size():
		rects[i].position.y += offset

	var heal_text := "回复 %.1f 心" % HEAL_HEARTS
	if _heal_used:
		heal_text = "已回复"
	else:
		heal_text += " · %d 金币" % _heal_price()
	_draw_button(rects[0], heal_text, _hover_button == 0, not _heal_used, alpha, ANGEL_ACCENT)

	var upgrade_text := "货架已满"
	if Skills.can_upgrade_shop():
		upgrade_text = "捐款升级 · %d 金币" % _upgrade_price()
	_draw_button(
		rects[1],
		upgrade_text,
		_hover_button == 1,
		Skills.can_upgrade_shop(),
		alpha,
		Color(0.55, 1.0, 0.62)
	)

	var reroll_text := "重掷货架 · %d 金币" % _reroll_cost
	if _free_rerolls > 0:
		reroll_text = "免费重掷 · 剩余 %d" % _free_rerolls
	_draw_button(rects[2], reroll_text, _hover_button == 2, true, alpha, GOLD_DIM)

	_draw_button(rects[3], "离开" if GameInput.touch_controls_active else "离开 (Esc)",
		_hover_button == 3, true, alpha, Color(0.7, 0.7, 0.75, 1.0))


func _draw_button(
	rect: Rect2,
	text: String,
	hovered: bool,
	enabled: bool,
	alpha: float,
	accent: Color
) -> void:
	var border_alpha := (0.9 if hovered else 0.4) * alpha
	draw_rect(rect, Color(0.07, 0.08, 0.11, 0.96 * alpha))
	draw_rect(
		rect,
		Color(accent.r, accent.g, accent.b, border_alpha * (1.0 if enabled else 0.4)),
		false,
		1.5
	)
	draw_string(
		_font,
		rect.position + Vector2(0.0, rect.size.y * 0.5 + 5.0),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		14,
		Color(1.0, 1.0, 1.0, (0.82 if enabled else 0.35) * alpha)
	)


# ── 布局 ────────────────────────────────────────────────────────

## 4~7 张排一行；8 张起自动分两行。宽度自适应，VIP 最多支持 15 张。
func _layout() -> Dictionary:
	var count := maxi(1, _offers.size())
	var cols := count
	var rows := 1
	if count > 7:
		cols = int(ceil(float(count) / 2.0))
		rows = 2

	var gap := 24.0
	if cols == 4:
		gap = 20.0
	elif cols == 5:
		gap = 16.0
	elif cols >= 6:
		gap = 12.0

	var available := minf(size.x - 56.0, 1224.0)
	var width := clampf(
		(available - gap * float(cols - 1)) / float(cols),
		CARD_MIN_WIDTH,
		CARD_SIZE.x
	)
	var height := CARD_SIZE.y if rows == 1 else CARD_COMPACT_HEIGHT
	var total_h := height * float(rows) + CARD_ROW_GAP * float(rows - 1)
	var top := (size.y - total_h) * 0.5 - (16.0 if rows == 1 else 4.0)
	return {
		"cols": cols,
		"rows": rows,
		"gap": gap,
		"width": width,
		"height": height,
		"top": top,
	}


func _grid_top() -> float:
	return float(_layout()["top"])


func _grid_bottom() -> float:
	var layout := _layout()
	return float(layout["top"]) + float(layout["height"]) * float(layout["rows"]) \
		+ CARD_ROW_GAP * float(int(layout["rows"]) - 1)


func _card_rects() -> Array[Rect2]:
	var count := _offers.size()
	if count == 0:
		return []
	var layout := _layout()
	var cols := int(layout["cols"])
	var gap := float(layout["gap"])
	var width := float(layout["width"])
	var height := float(layout["height"])
	var total_width := width * float(cols) + gap * float(cols - 1)
	var start := Vector2(
		(size.x - total_width) * 0.5,
		float(layout["top"])
	)

	var rects: Array[Rect2] = []
	for i in count:
		var col := i % cols
		var row := i / cols
		# 两行布局时每行单独居中，避免最后一行偏左。
		var row_count := mini(cols, count - row * cols)
		var row_width := width * float(row_count) + gap * float(row_count - 1)
		var row_x := (size.x - row_width) * 0.5
		rects.append(Rect2(
			Vector2(
				row_x + float(col) * (width + gap),
				start.y + float(row) * (height + CARD_ROW_GAP)
			),
			Vector2(width, height)
		))
	return rects


func _button_rects() -> Array[Rect2]:
	var y := _grid_bottom() + 22.0
	var widths: Array[float] = [170.0, 230.0, 190.0, 140.0]
	const GAP := 16.0
	var total := 0.0
	for width in widths:
		total += width
	total += GAP * float(widths.size() - 1)

	var rects: Array[Rect2] = []
	var x := (size.x - total) * 0.5
	for width in widths:
		rects.append(Rect2(Vector2(x, y), Vector2(width, 40.0)))
		x += width + GAP
	return rects


func _message_baseline() -> float:
	return _button_rects()[0].end.y + 26.0


func _accent_of(relic: RelicResource) -> Color:
	if relic.side == &"demon":
		return DEMON_ACCENT
	if relic.side == &"angel":
		return ANGEL_ACCENT
	match relic.rarity:
		RelicResource.RARITY_RARE:
			return Color(0.45, 0.72, 1.0)
		RelicResource.RARITY_EPIC:
			return Color(0.75, 0.45, 1.0)
		RelicResource.RARITY_LEGENDARY:
			return Color(1.0, 0.65, 0.25)
		RelicResource.RARITY_IRIDESCENT:
			var rainbow := Color.from_hsv(fmod(_time * 0.18, 1.0), 0.55, 1.0)
			return Color(rainbow.r * 1.6, rainbow.g * 1.6, rainbow.b * 1.6, 1.0)
		RelicResource.RARITY_CURSED:
			return Color(1.0, 0.25, 0.3)
		_:
			return GOLD


func _rarity_name(relic: RelicResource) -> String:
	match relic.rarity:
		RelicResource.RARITY_RARE:
			return "微光"
		RelicResource.RARITY_EPIC:
			return "炬火"
		RelicResource.RARITY_LEGENDARY:
			return "璀璨"
		RelicResource.RARITY_IRIDESCENT:
			return "幻彩"
		RelicResource.RARITY_CURSED:
			return "诅咒"
		_:
			return "尘灰"


func _draw_text_centered(text: String, baseline_y: float, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	).x
	draw_string(
		_font,
		Vector2((size.x - width) * 0.5, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)


# ── 输入 ────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var card := _index_at(motion.position)
		var button := _button_at(motion.position)
		if card != _hover or button != _hover_button:
			_hover = card
			_hover_button = button
			queue_redraw()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			var card := _index_at(mouse.position)
			if card >= 0:
				accept_event()
				_buy(card)
				return
			var button := _button_at(mouse.position)
			if button == 0:
				accept_event()
				_heal()
			elif button == 1:
				accept_event()
				_upgrade()
			elif button == 2:
				accept_event()
				_reroll()
			elif button == 3:
				accept_event()
				_leave()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return

	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	var index := -1
	match key.keycode:
		KEY_1, KEY_KP_1:
			index = 0
		KEY_2, KEY_KP_2:
			index = 1
		KEY_3, KEY_KP_3:
			index = 2
		KEY_4, KEY_KP_4:
			index = 3
		KEY_5, KEY_KP_5:
			index = 4
		KEY_6, KEY_KP_6:
			index = 5
		KEY_7, KEY_KP_7:
			index = 6
		KEY_8, KEY_KP_8:
			index = 7
		KEY_9, KEY_KP_9:
			index = 8
		KEY_0, KEY_KP_0:
			index = 9
		KEY_U:
			_upgrade()
			get_viewport().set_input_as_handled()
			return
		KEY_R:
			_reroll()
			get_viewport().set_input_as_handled()
			return
		KEY_H:
			_heal()
			get_viewport().set_input_as_handled()
			return
		KEY_ESCAPE:
			_leave()
			get_viewport().set_input_as_handled()
			return
		_:
			return

	if index >= 0 and index < _offers.size():
		_buy(index)
		get_viewport().set_input_as_handled()


func _index_at(point: Vector2) -> int:
	var rects := _card_rects()
	for i in rects.size():
		if rects[i].has_point(point):
			return i
	return -1


func _button_at(point: Vector2) -> int:
	var rects := _button_rects()
	for i in rects.size():
		if rects[i].has_point(point):
			return i
	return -1
