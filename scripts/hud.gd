class_name Hud
extends CanvasLayer
## The flight HUD, rebuilt with Control nodes: the status pane bottom-centre (hull, fuel, throttle, cargo, speed), the
## situation readout top-right (zone, laser, radar, target), a crosshair, and a toast column. Layout follows the browser
## HUD; the styling is deliberately plain until the art pass.

const AMBER := Color("#F2A33A")
const CYAN := Color("#35D6C2")
const GREEN := Color("#6BD69A")
const RED := Color("#FF2E63")
const DIM := Color(0.62, 0.66, 0.78)

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
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 28)
	cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	cross.anchor_left = 0.5
	cross.anchor_right = 0.5
	cross.anchor_top = 0.5
	cross.anchor_bottom = 0.5
	cross.offset_left = -10
	cross.offset_right = 10
	cross.offset_top = -20
	cross.offset_bottom = 20
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(cross)
	# toasts
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.offset_left = -260
	_toasts.offset_right = 260
	_toasts.offset_top = 100
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_toasts)


func _box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.07, 0.14, 0.85)
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


func toast(msg: String, bad: bool) -> void:
	var l := Label.new()
	l.text = msg
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", RED if bad else Color.WHITE)
	_toasts.add_child(l)
	var t := get_tree().create_timer(3.3)
	t.timeout.connect(l.queue_free)


func update(ship: Ship, belt: Belt) -> void:
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
	_cargo_t.text = "%d / %d u · %d / %d slots" % [roundi(ct), roundi(cc), _used_slots(), State.cargo_slots()]
	_speed.text = "%d" % roundi(ship.speed() * Data.METRE)
	var laser := "CUTTING" if ship.laser_on else ("FIRING" if ship.firing else "ready")
	if ship.overcharge:
		laser += " ⚡×%s" % str(State.stat("overcharge")["mult"])
	var radar := "READY" if ship.radar_cd <= 0.0 else "%.1fs" % ship.radar_cd
	_right.text = "ZONE  Kessler Belt\nLASER  %s   RANGE  %s m\nRADAR  %s\nALTITUDE  %s km" % [laser, Data.fm(State.stat("range")["reach"]), radar, Data.fmt((ship.true_pos().length() - belt.planet_r) * Data.METRE / 1000.0)]
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


func _used_slots() -> int:
	var n := 0
	for k in State.cargo:
		if State.cargo[k] > 0.5:
			n += int(ceil(State.cargo[k] / Data.STACK))
	return n
