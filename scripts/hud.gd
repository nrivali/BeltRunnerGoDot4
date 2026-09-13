class_name Hud
extends CanvasLayer
## The flight HUD, rebuilt with Control nodes: the status pane bottom-centre (hull, fuel, throttle, cargo, speed), the
## situation readout top-right (zone, laser, radar, target), a crosshair, the cargo ship marker, a toast column, the
## letterbox and caption for cutscenes, the fade for a jump, the nav map, and the cargo ship services panel (with the
## colony market at the Hub) while docked. Layout follows the browser HUD; the styling is plain until the art pass.

const AMBER := Color("#F2A33A")
const CYAN := Color("#35D6C2")
const GREEN := Color("#6BD69A")
const RED := Color("#FF2E63")
const DIM := Color(0.62, 0.66, 0.78)

var zone: Dictionary = Data.ZONE_KESSLER

var _hull: ProgressBar
var _fuel: ProgressBar
var _thr: ProgressBar
var _cargo: ProgressBar
var _hull_t: Label
var _fuel_t: Label
var _thr_t: Label
var _cargo_t: Label
var _speed: Label
var _right: Label
var _target_box: PanelContainer
var _target_name: Label
var _target_sub: Label
var _target_hp: ProgressBar
var _toasts: VBoxContainer
var _credits: Label
var _cross: Label
var _marker: Label
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _caption: Label
var _fade: ColorRect
var _flight: Array = []       # everything that hides while docked
# services panel
var _panel: PanelContainer
var _panel_title: Label
var _panel_sub: Label
var _gauges: Dictionary = {}  # name -> [ProgressBar, Label]
var _hold_list: Label
var _refits: VBoxContainer
var _market: VBoxContainer
var _ship: Ship
# nav map
var _map: PanelContainer
var _map_body: VBoxContainer
var map_open := false


func _ready() -> void:
	layer = 5
	var font_size := 15
	# bottom centre: the ship
	var pane := PanelContainer.new()
	pane.anchor_left = 0.5
	pane.anchor_right = 0.5
	pane.anchor_top = 1.0
	pane.anchor_bottom = 1.0
	pane.offset_left = -300
	pane.offset_right = 300
	pane.offset_top = -132
	pane.offset_bottom = -16
	pane.add_theme_stylebox_override("panel", _box())
	add_child(pane)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	pane.add_child(grid)
	var made := _gauge(grid, "HULL", RED)
	_hull = made[0]
	_hull_t = made[1]
	made = _gauge(grid, "FUEL", CYAN)
	_fuel = made[0]
	_fuel_t = made[1]
	made = _gauge(grid, "THRUST", AMBER)
	_thr = made[0]
	_thr_t = made[1]
	made = _gauge(grid, "CARGO", GREEN)
	_cargo = made[0]
	_cargo_t = made[1]
	_speed = Label.new()
	_speed.add_theme_font_size_override("font_size", 26)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed.anchor_left = 0.5
	_speed.anchor_right = 0.5
	_speed.anchor_top = 1.0
	_speed.anchor_bottom = 1.0
	_speed.offset_left = -80
	_speed.offset_right = 80
	_speed.offset_top = -170
	_speed.offset_bottom = -136
	add_child(_speed)
	# top right: the situation
	_right = Label.new()
	_right.add_theme_font_size_override("font_size", font_size)
	_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_right.anchor_left = 1.0
	_right.anchor_right = 1.0
	_right.offset_left = -340
	_right.offset_right = -18
	_right.offset_top = 16
	_right.offset_bottom = 140
	add_child(_right)
	# top left: credits
	_credits = Label.new()
	_credits.add_theme_font_size_override("font_size", font_size)
	_credits.offset_left = 18
	_credits.offset_top = 16
	_credits.offset_right = 300
	_credits.offset_bottom = 60
	add_child(_credits)
	# top centre: the target panel
	_target_box = PanelContainer.new()
	_target_box.anchor_left = 0.5
	_target_box.anchor_right = 0.5
	_target_box.offset_left = -140
	_target_box.offset_right = 140
	_target_box.offset_top = 16
	_target_box.offset_bottom = 90
	_target_box.add_theme_stylebox_override("panel", _box())
	_target_box.visible = false
	add_child(_target_box)
	var tv := VBoxContainer.new()
	_target_box.add_child(tv)
	_target_name = Label.new()
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_name.add_theme_font_size_override("font_size", 16)
	tv.add_child(_target_name)
	_target_sub = Label.new()
	_target_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_sub.add_theme_color_override("font_color", DIM)
	tv.add_child(_target_sub)
	_target_hp = ProgressBar.new()
	_target_hp.show_percentage = false
	_target_hp.custom_minimum_size = Vector2(240, 10)
	_target_hp.add_theme_stylebox_override("fill", _fill(AMBER))
	tv.add_child(_target_hp)
	# crosshair
	_cross = Label.new()
	_cross.text = "+"
	_cross.add_theme_font_size_override("font_size", 28)
	_cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_cross.anchor_left = 0.5
	_cross.anchor_right = 0.5
	_cross.anchor_top = 0.5
	_cross.anchor_bottom = 0.5
	_cross.offset_left = -10
	_cross.offset_right = 10
	_cross.offset_top = -20
	_cross.offset_bottom = 20
	_cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_cross)
	# the cargo ship marker: a label that follows the carrier on screen (or sits at the edge nearest to it)
	_marker = Label.new()
	_marker.text = "◇ CARGO SHIP"
	_marker.add_theme_font_size_override("font_size", 13)
	_marker.add_theme_color_override("font_color", AMBER)
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.size = Vector2(180, 40)
	add_child(_marker)
	# toasts
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.offset_left = -260
	_toasts.offset_right = 260
	_toasts.offset_top = 100
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_toasts)
	# fade to black for a jump, letterbox and caption for cutscenes
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.anchor_right = 1.0
	_fade.anchor_bottom = 1.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.anchor_right = 1.0
	_bar_top.offset_bottom = 70
	_bar_top.visible = false
	add_child(_bar_top)
	_bar_bot = ColorRect.new()
	_bar_bot.color = Color.BLACK
	_bar_bot.anchor_right = 1.0
	_bar_bot.anchor_top = 1.0
	_bar_bot.anchor_bottom = 1.0
	_bar_bot.offset_top = -70
	_bar_bot.visible = false
	add_child(_bar_bot)
	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 15)
	_caption.add_theme_color_override("font_color", AMBER)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.anchor_left = 0.5
	_caption.anchor_right = 0.5
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = -300
	_caption.offset_right = 300
	_caption.offset_top = -50
	_caption.offset_bottom = -20
	_caption.visible = false
	add_child(_caption)
	_flight = [pane, _speed, _right, _target_box, _cross, _marker]
	_build_panel()
	_build_map()


func _box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.07, 0.14, 0.88)
	sb.border_color = Color(0.3, 0.36, 0.5, 0.6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	return sb


func _fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	return sb


func _gauge(grid: GridContainer, label: String, color: Color) -> Array:
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", DIM)
	lbl.add_theme_font_size_override("font_size", 12)
	grid.add_child(lbl)
	var text := Label.new()
	text.add_theme_font_size_override("font_size", 12)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(text)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(130, 8)
	bar.add_theme_stylebox_override("fill", _fill(color))
	bar.max_value = 1.0
	grid.add_child(bar)
	var spacer := Control.new()
	grid.add_child(spacer)
	return [bar, text]


func _head(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)


func _button(parent: Node, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func toast(msg: String, bad: bool) -> void:
	var l := Label.new()
	l.text = msg
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", RED if bad else Color.WHITE)
	_toasts.add_child(l)
	var t := get_tree().create_timer(3.3)
	t.timeout.connect(l.queue_free)


# ---- the cargo ship services panel: gauges, the hold, the market at the Hub, refits, depart / nav map
func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -460
	_panel.offset_right = -16
	_panel.offset_top = 16
	_panel.offset_bottom = -16
	_panel.add_theme_stylebox_override("panel", _box())
	_panel.visible = false
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	_panel_title = Label.new()
	_panel_title.text = "CARGO SHIP"
	_panel_title.add_theme_font_size_override("font_size", 22)
	v.add_child(_panel_title)
	_panel_sub = Label.new()
	_panel_sub.add_theme_color_override("font_color", DIM)
	_panel_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_panel_sub)
	for g in [["storage", "Cargo ship storage", GREEN], ["fuel", "Cargo ship fuel supply", CYAN], ["parts", "Repair parts", GREEN]]:
		var head := HBoxContainer.new()
		var n := Label.new()
		n.text = g[1]
		n.add_theme_color_override("font_color", DIM)
		n.add_theme_font_size_override("font_size", 12)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(n)
		var t := Label.new()
		t.add_theme_font_size_override("font_size", 12)
		head.add_child(t)
		v.add_child(head)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.max_value = 1.0
		bar.add_theme_stylebox_override("fill", _fill(g[2]))
		v.add_child(bar)
		_gauges[g[0]] = [bar, t]
	# the market (filled in at the Hub)
	_market = VBoxContainer.new()
	_market.add_theme_constant_override("separation", 6)
	v.add_child(_market)
	_head(v, "YOUR HOLD")
	_hold_list = Label.new()
	_hold_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hold_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_button(row, "Deposit all  [E]", func(): if _ship: _ship.deposit_all())
	_button(row, "Take all", func(): if _ship: _ship.take_all())
	v.add_child(row)
	_head(v, "REFITS")
	_refits = VBoxContainer.new()
	_refits.add_theme_constant_override("separation", 6)
	v.add_child(_refits)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	_button(foot, "Depart  [W]", func(): if _ship: _ship.start_departure())
	_button(foot, "Nav map  [N]", func(): toggle_map())
	v.add_child(foot)


func bind(ship: Ship) -> void:
	_ship = ship
	ship.docked_changed.connect(_on_docked)
	ship.map_requested.connect(open_map)


func _on_docked(is_docked: bool) -> void:
	_panel.visible = is_docked
	for c in _flight:
		c.visible = not is_docked
	if is_docked:
		refresh_panel()
	elif map_open:
		close_map()


func refresh_panel() -> void:
	if _ship == null:
		return
	var at_hub: bool = _ship.hold
	_panel_sub.text = ("Holding station off %s · %s cr" % [zone.get("colony", "the colony"), Data.fmt(State.credits)]) if at_hub else ("Docked in %s · %s cr" % [CargoShip.bay_name(_ship.dock_side), Data.fmt(State.credits)])
	var su := State.store_used()
	_gauges["storage"][0].value = State.store_total() / (Data.STORE_SLOTS * Data.STACK)
	_gauges["storage"][1].text = "%d / %d slots · %s cr" % [su, Data.STORE_SLOTS, Data.fmt(State.value_of(State.store))]
	_gauges["fuel"][0].value = State.ship_fuel / Data.CARGO_FUEL_CAP
	_gauges["fuel"][1].text = "%d / %d" % [roundi(State.ship_fuel), roundi(Data.CARGO_FUEL_CAP)]
	_gauges["parts"][0].value = State.parts / Data.PARTS_CAP
	_gauges["parts"][1].text = "%d / %d" % [roundi(State.parts), Data.PARTS_CAP]
	var lines: Array = []
	for k in Data.ORE_KEYS:
		if State.cargo[k] > 0.5:
			lines.append("%s %d u" % [Data.ORES[k]["name"], roundi(State.cargo[k])])
	_hold_list.text = (", ".join(lines) + "   ·   worth %s cr at the Hub" % Data.fmt(State.value_of(State.cargo))) if lines.size() > 0 else "The hold is empty."
	_refresh_market(at_hub)
	for c in _refits.get_children():
		c.queue_free()
	for key in Data.UPGRADES:
		var u: Dictionary = Data.UPGRADES[key]
		var i: int = State.up[key]
		var maxed: bool = i >= u["costs"].size()
		var row := HBoxContainer.new()
		var txt := VBoxContainer.new()
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := Label.new()
		n.text = "%s  ·  Lv%d" % [u["name"], i + 1]
		txt.add_child(n)
		var d := Label.new()
		d.add_theme_color_override("font_color", DIM)
		d.add_theme_font_size_override("font_size", 12)
		d.text = (Data.describe(key, i) + " · fully upgraded") if maxed else (Data.describe(key, i) + "  →  " + Data.describe(key, i + 1))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.add_child(d)
		row.add_child(txt)
		var btn := Button.new()
		if maxed:
			btn.text = "Max"
			btn.disabled = true
		else:
			var cost: float = u["costs"][i]
			btn.text = "%s cr" % Data.fmt(cost)
			btn.disabled = State.credits < cost
			btn.pressed.connect(_buy.bind(key))
		row.add_child(btn)
		_refits.add_child(row)


## The colony market: what is aboard and what it fetches, sell buttons, today's prices, and the cargo ship's fuel and parts.
func _refresh_market(at_hub: bool) -> void:
	for c in _market.get_children():
		c.queue_free()
	if not at_hub:
		return
	_head(_market, "%s MARKET" % str(zone.get("colony", "colony")).to_upper())
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	for h in ["Ore", "Hold", "Storage", "cr / u", "Value"]:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", DIM)
		l.add_theme_font_size_override("font_size", 11)
		grid.add_child(l)
	var total := 0.0
	var any := false
	for k in Data.ORE_KEYS:
		var h: float = State.cargo[k]
		var s: float = State.store[k]
		if h + s < 0.5:
			continue
		any = true
		var p: float = State.price(k)
		total += (h + s) * p
		for cell in [Data.ORES[k]["name"], "%d" % roundi(h), "%d" % roundi(s), "%.1f" % p, Data.fmt((h + s) * p)]:
			var l := Label.new()
			l.text = cell
			l.add_theme_font_size_override("font_size", 12)
			grid.add_child(l)
	_market.add_child(grid)
	if any:
		var tot := Label.new()
		tot.text = "Everything aboard   %s cr" % Data.fmt(total)
		tot.add_theme_font_size_override("font_size", 14)
		_market.add_child(tot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_button(row, "Sell everything", func(): if _ship: _ship.sell(Data.ORE_KEYS, true, true))
		_button(row, "Hold only", func(): if _ship: _ship.sell(Data.ORE_KEYS, true, false))
		_button(row, "Storage only", func(): if _ship: _ship.sell(Data.ORE_KEYS, false, true))
		_market.add_child(row)
	else:
		var none := Label.new()
		none.text = "Nothing aboard to sell."
		none.add_theme_color_override("font_color", DIM)
		_market.add_child(none)
	var prices: Array = []
	for k in Data.ORE_KEYS:
		var d := roundi((float(State.market[k]) - 1.0) * 100.0)
		var drift := "" if d == 0 else (" ▲%d%%" % d if d > 0 else " ▼%d%%" % -d)
		prices.append("%s %.1f%s" % [Data.ORES[k]["name"], State.price(k), drift])
	var pl := Label.new()
	pl.text = "Prices today: " + " · ".join(prices)
	pl.add_theme_color_override("font_color", DIM)
	pl.add_theme_font_size_override("font_size", 11)
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_market.add_child(pl)
	var fuel_cost := ceili((Data.CARGO_FUEL_CAP - State.ship_fuel) * Data.CARGO_FUEL_PRICE)
	var parts_cost := ceili((float(Data.PARTS_CAP) - State.parts) * Data.PARTS_PRICE)
	var buy := HBoxContainer.new()
	buy.add_theme_constant_override("separation", 6)
	var fb := _button(buy, ("Refuel supply · %s cr" % Data.fmt(fuel_cost)) if fuel_cost > 0 else "Fuel supply full", func(): if _ship: _ship.refuel_cargo_ship())
	fb.disabled = fuel_cost <= 0
	var pb := _button(buy, ("Restock parts · %s cr" % Data.fmt(parts_cost)) if parts_cost > 0 else "Parts store full", func(): if _ship: _ship.buy_parts())
	pb.disabled = parts_cost <= 0
	_market.add_child(buy)


func _buy(key: String) -> void:
	var r: Dictionary = State.buy(key)
	toast(r["msg"], not r["ok"])
	refresh_panel()


# ---- the nav map: every charted zone, and the warp button for the one you pick (the cargo ship makes the jump)
func _build_map() -> void:
	_map = PanelContainer.new()
	_map.anchor_left = 0.5
	_map.anchor_right = 0.5
	_map.anchor_top = 0.5
	_map.anchor_bottom = 0.5
	_map.offset_left = -330
	_map.offset_right = 330
	_map.offset_top = -230
	_map.offset_bottom = 230
	_map.add_theme_stylebox_override("panel", _box())
	_map.visible = false
	add_child(_map)
	_map_body = VBoxContainer.new()
	_map_body.add_theme_constant_override("separation", 10)
	_map.add_child(_map_body)


func toggle_map() -> void:
	if map_open:
		close_map()
	else:
		open_map()


func open_map() -> void:
	map_open = true
	_map.visible = true
	_refresh_map()


func close_map() -> void:
	map_open = false
	_map.visible = false


func _refresh_map() -> void:
	for c in _map_body.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "NAV COMPUTER · CHARTED ZONES"
	title.add_theme_font_size_override("font_size", 20)
	_map_body.add_child(title)
	var sub := Label.new()
	sub.text = "Cargo ship fuel supply %d / %d · the cargo ship makes the jump, so dock with it first. The jump itself is free." % [roundi(State.ship_fuel), roundi(Data.CARGO_FUEL_CAP)]
	sub.add_theme_color_override("font_color", DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_body.add_child(sub)
	for z in Data.ZONES:
		var cur: bool = z["id"] == zone["id"]
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", _box())
		var v := VBoxContainer.new()
		box.add_child(v)
		var head := HBoxContainer.new()
		var n := Label.new()
		n.text = str(z["name"]) + ("   · here" if cur else "   · %s ly" % str(Data.zone_ly(zone, z)))
		n.add_theme_font_size_override("font_size", 16)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(n)
		var b := Button.new()
		var can: bool = not cur and _ship != null and _ship.docked and _ship.warp.is_empty()
		b.text = "You are here" if cur else ("Warp · %s ly" % str(Data.zone_ly(zone, z)) if can else "Dock with the cargo ship to warp")
		b.disabled = not can
		if can:
			b.pressed.connect(func(): close_map(); _ship.start_warp(z))
		head.add_child(b)
		v.add_child(head)
		var tag := Label.new()
		tag.text = str(z["tag"])
		tag.add_theme_color_override("font_color", DIM)
		tag.add_theme_font_size_override("font_size", 12)
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(tag)
		var det := Label.new()
		if z["hub"]:
			var aboard := floori(State.cargo_total() + State.store_total())
			det.text = "Market: buys every ore · exotics +%d%%   ·   aboard to sell: %s" % [roundi((Data.EXPORT_BONUS - 1.0) * 100.0), ("%d units" % aboard) if aboard > 0 else "nothing yet"]
		else:
			var ex: Array = []
			for k in Data.ORE_KEYS:
				if Data.ORES[k].get("zone", "") == z["id"]:
					ex.append(Data.ORES[k]["name"])
			det.text = "Market: none · sell at the Hub   ·   exclusive ore: %s   ·   planet %s" % [", ".join(ex), z["planet"]["name"]]
		det.add_theme_font_size_override("font_size", 12)
		det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(det)
		_map_body.add_child(box)
	var close := Button.new()
	close.text = "Close  [N]"
	close.pressed.connect(close_map)
	_map_body.add_child(close)


func update(ship: Ship, belt: Belt, carrier: CargoShip) -> void:
	var hp: float = State.stat("hull")["hp"]
	var tank: float = State.stat("tank")["cap"]
	_hull.value = State.hull / hp
	_hull_t.text = "%d / %d" % [roundi(State.hull), roundi(hp)]
	_fuel.value = State.fuel / tank
	_fuel_t.text = "%d / %d" % [roundi(State.fuel), roundi(tank)]
	_thr.value = 1.0 if ship.braking else ship.throttle
	_thr_t.text = ("RETRO" if ship.braking else ("BOOST %d%%" if ship.afterburning else "%d%%") % roundi(ship.throttle * 100.0))
	var ct := State.cargo_total()
	var cc := State.cargo_capacity()
	_cargo.value = ct / cc
	_cargo_t.text = "%d / %d u · %d / %d slots" % [roundi(ct), roundi(cc), State.used_slots(), State.cargo_slots()]
	_speed.text = "%d" % roundi(ship.speed() * Data.METRE)
	var laser := "CUTTING" if ship.laser_on else ("FIRING" if ship.firing else "ready")
	if ship.overcharge:
		laser += " ⚡×%s" % str(State.stat("overcharge")["mult"])
	var radar := "READY" if ship.radar_cd <= 0.0 else "%.1fs" % ship.radar_cd
	var to_carrier := ship.true_pos().distance_to(carrier.true_pos) if carrier else 0.0
	_right.text = "ZONE  %s\nCARGO SHIP  %s m\nLASER  %s   RANGE  %s m\nRADAR  %s" % [zone["name"], Data.fm(to_carrier), laser, Data.fm(State.stat("range")["reach"]), radar]
	_credits.text = "%s cr" % Data.fmt(State.credits)
	if ship.target >= 0 and belt.alive[ship.target] == 1:
		var i := ship.target
		_target_box.visible = true
		_target_name.text = belt.rock_name(i)
		var need := 1 if belt.ore[i] < 0 else int(Data.ORES[Data.ORE_KEYS[belt.ore[i]]]["unlock"])
		var lock := "" if need <= State.up["laser"] + 1 else "   needs laser Lv%d" % need
		_target_sub.text = "%s   %s m   %d ore%s" % [Belt.CLS_NAME[belt.cls[i]], Data.fm(belt.pos[i].distance_to(ship.true_pos())), roundi(belt.amount[i]), lock]
		_target_hp.max_value = belt.hp_max[i]
		_target_hp.value = belt.hp[i]
	else:
		_target_box.visible = false
	# cutscenes play under letterbox bars with a caption; the departure and the pad do not
	var in_cut: bool = ship.in_cinematic()
	_bar_top.visible = in_cut
	_bar_bot.visible = in_cut
	_caption.visible = in_cut
	if in_cut:
		if not ship.warp.is_empty():
			var z: Dictionary = ship.warp["z"]
			_caption.text = "Jump · %s · %s ly · Space skips" % [z["name"], str(Data.zone_ly(zone, z))]
		elif ship.cut["mode"] == "hold":
			_caption.text = "Arrival · %s · Space skips" % str(zone.get("colony", "the colony"))
		else:
			_caption.text = "Approach · %s · Cargo ship · Space skips" % CargoShip.bay_name(int(ship.cut["side"]))
		_cross.visible = false
		_panel.visible = false
	elif not ship.docked:
		_cross.visible = ship.cut.is_empty()
	_fade.color = Color(0, 0, 0, ship.warp_fade())
	# the cargo ship marker
	if carrier and not ship.docked and not in_cut:
		var cam := ship.cam
		var p := carrier.position
		var vp := get_viewport().get_visible_rect().size
		var behind := cam.is_position_behind(p)
		var sp := cam.unproject_position(p)
		if behind:
			sp = vp - sp
		var m := Vector2(40, 40)
		var on := not behind and sp.x > 0 and sp.x < vp.x and sp.y > 0 and sp.y < vp.y
		if not on:
			var c := vp * 0.5
			var d := sp - c
			if d.length() < 1.0:
				d = Vector2(1, 0)
			var sc: float = min(absf((c.x - m.x) / d.x) if d.x != 0.0 else INF, absf((c.y - m.y) / d.y) if d.y != 0.0 else INF)
			sp = c + d * sc
		_marker.visible = true
		_marker.text = ("◇ CARGO SHIP\n%s m" if on else "△ CARGO SHIP · %s m") % Data.fm(to_carrier)
		_marker.position = sp - _marker.size * 0.5 + Vector2(0, -34 if on else 0)
	else:
		_marker.visible = false
	if ship.docked and Engine.get_process_frames() % 30 == 0:
		refresh_panel()
