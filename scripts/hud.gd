class_name Hud
extends CanvasLayer
## The flight HUD and the in-game panels, laid out and styled as belt-runner-3d.html's are (see ui.gd for the
## stylesheet): the ship status pane bottom-centre, the situation readouts top-right, the target pane top-centre, the
## flight controls list bottom-left, the hint bar above the status pane, the boresight brackets on whatever the nose is
## on, the cargo ship marker, radar blips, toasts, the cargo-full notice, the letterbox and caption for cutscenes, the
## fade for a jump, the vignette and the damage flash, the version tag; the cargo ship services side panel (right), the
## inventory side panel (left), the nav computer, and the tutorial card top-left with its highlight rings.

var zone: Dictionary = Data.ZONE_KESSLER
var tutorial: Tutorial
var inv_open := false
var map_open := false
var services_visible := false
var started := false

# the flight HUD
var _vignette: Ui.Vignette
var _dmg: Ui.Vignette
var _blips: Ui.Blips
var _reticle: Ui.Reticle
var _marker: Ui.Marker
var _status: Ui.Pane
var _g_hull: Ui.Gauge
var _g_fuel: Ui.Gauge
var _g_thr: Ui.Gauge
var _g_cargo: Ui.Gauge
var _speed_big: Label
var _readouts: Ui.Pane
var _row1: RichTextLabel
var _row2: RichTextLabel
var _target: Ui.Pane
var _t_eyebrow: Label
var _t_name: Label
var _t_rows: RichTextLabel
var _t_hp_row: HBoxContainer
var _t_hp: Ui.SegBar
var _t_hp_t: Label
var _t_warn: Label
var _controls: Ui.Pane
var _prompt: Ui.Pane
var _prompt_text: RichTextLabel
var _notice: PanelContainer
var _toasts: VBoxContainer
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _caption: Label
var _fade: ColorRect
var _version: Label
var _last_hull := -1.0
var _dmg_t := 0.0
var _ship: Ship
# the cargo ship services panel
var _services: PanelContainer
var _svc_eyebrow: Label
var _svc_sub: Label
var _svc_credits: Label
var _svc_cargo_h: Label
var _svc_cargo: VBoxContainer
var _svc_refits: VBoxContainer
var _svc_gauges: Dictionary = {}
var _deposit_btn: Ui.ChamferButton
var _depart_btn: Ui.ChamferButton
var _nav_btn: Ui.ChamferButton
var _reset_link: LinkButton
var _reset_armed := false
# the inventory panel
var _inv: PanelContainer
var _inv_cap: Label
var _inv_credits: Label
var _inv_bar: Ui.SegBar
var _inv_body: VBoxContainer
var _inv_sig := ""
# the nav computer
var _map: Control
var _map_card: Ui.Pane
var _chart: Ui.Chart
var _zinfo: VBoxContainer
var _map_fuel: Label
var _map_sel: Dictionary = {}
# the tutorial card and its rings
var _tut_box: PanelContainer
var _tut_step: Label
var _tut_title: Label
var _tut_text: Label
var _tut_next: Ui.ChamferButton
var _tut_wait: Label
var _tut_hidden := false
var _rings: RingOverlay
var _ring_targets := {}
var _ring_names: Array = []


## Pulsing amber frames round the HUD pieces the tutorial is talking about (.tut-ring).
class RingOverlay extends Control:
	var rects: Array = []
	var t := 0.0
	func _process(dt: float) -> void:
		t += dt
		queue_redraw()
	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(t * 4.2)
		for r in rects:
			var rr: Rect2 = (r as Rect2).grow(6.0)
			draw_rect(rr.grow(3.0), Color(Ui.AMBER, 0.18), false, 3.0)
			draw_rect(rr.grow(6.0), Color(Ui.AMBER, 0.12 * pulse), false, 8.0)
			draw_rect(rr, Color(Ui.AMBER, 0.55 + 0.45 * pulse), false, 2.0)


func _ready() -> void:
	layer = 5
	_vignette = Ui.Vignette.new(Color(0.008, 0.016, 0.047), 0.58, 0.5)
	add_child(_vignette)
	_dmg = Ui.Vignette.new(Ui.RED, 0.45, 0.0)
	add_child(_dmg)
	_blips = Ui.Blips.new()
	add_child(_blips)
	_reticle = Ui.Reticle.new()
	_reticle.visible = false
	add_child(_reticle)
	_marker = Ui.Marker.new()
	_marker.visible = false
	add_child(_marker)
	_build_status()
	_build_readouts()
	_build_target()
	_build_controls()
	_build_prompt()
	_build_notice()
	_toasts = VBoxContainer.new()
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin(_toasts, 0.5, 0.0, 0, 22, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	add_child(_toasts)
	_build_cine()
	_version = Ui.label("v" + Data.VERSION, "mono", 11, Color(Ui.DIM, 0.75), 1.0)
	_pin(_version, 0.0, 1.0, 14, -8, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	add_child(_version)
	_build_services()
	_build_inventory()
	_build_map()
	_build_tutorial()
	_ring_targets = {"status": _status, "readout": _readouts, "target": _target, "marker": _marker, "controls": _controls, "refits": _svc_refits, "deposit": _deposit_btn, "navmap": _nav_btn, "depart": _depart_btn}
	_controls.visible = bool(State.settings.get("controls", true))


## Anchor a control at one point of the screen (ax, ay in 0..1) with an offset, growing away from that point. Containers
## take their minimum size, so a pane hugs its content wherever it hangs.
func _pin(c: Control, ax: float, ay: float, dx: float, dy: float, gx: int, gy: int) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = dx
	c.offset_right = dx
	c.offset_top = dy
	c.offset_bottom = dy
	c.grow_horizontal = gx as Control.GrowDirection
	c.grow_vertical = gy as Control.GrowDirection


func _h3(text: String) -> Label:
	return Ui.label(text.to_upper(), "display", 13, Ui.MUTED, 2.0)


func _card_eyebrow(text: String) -> Label:
	return Ui.eyebrow(text, Ui.MUTED)


func _h2(text: String) -> Label:
	return Ui.label(text.to_upper(), "display_bold", 24, Ui.TEXT, 1.4)


func _margin(top: float, right: float, bottom: float, left: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", int(top))
	m.add_theme_constant_override("margin_right", int(right))
	m.add_theme_constant_override("margin_bottom", int(bottom))
	m.add_theme_constant_override("margin_left", int(left))
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return m


func _vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h


# ---- bottom centre: the ship (.hud-tl)
func _build_status() -> void:
	_status = Ui.Pane.new(12, 18, 12, 18)
	_pin(_status, 0.5, 1.0, 0, -18, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_child(row)
	_g_hull = Ui.Gauge.new("Hull", Ui.GREEN)
	row.add_child(_g_hull)
	_g_fuel = Ui.Gauge.new("Fuel", Ui.CYAN)
	row.add_child(_g_fuel)
	var sp := VBoxContainer.new()
	sp.custom_minimum_size.x = 96
	sp.add_theme_constant_override("separation", 5)
	sp.alignment = BoxContainer.ALIGNMENT_END
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var se := Ui.eyebrow("Speed")
	se.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sp.add_child(se)
	_speed_big = Ui.glow(Ui.label("0", "mono_semi", 24, Ui.GLOW_TEXT), Ui.HUD_GLOW, 8) as Label
	_speed_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sp.add_child(_speed_big)
	row.add_child(sp)
	_g_thr = Ui.Gauge.new("Thrust", Ui.AMBER, 150.0, false, 10.0)
	row.add_child(_g_thr)
	_g_cargo = Ui.Gauge.new("Cargo", Ui.CARGO)
	row.add_child(_g_cargo)


# ---- top right: the situation (.hud-tr .readouts)
func _build_readouts() -> void:
	_readouts = Ui.Pane.new(10, 14, 10, 14)
	_pin(_readouts, 1.0, 0.0, -20, 18, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	add_child(_readouts)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readouts.add_child(v)
	_row1 = _readout_row()
	v.add_child(_row1)
	_row2 = _readout_row()
	v.add_child(_row2)


func _readout_row() -> RichTextLabel:
	var r := Ui.rich(12, Ui.HUD_DIM)
	r.add_theme_font_override("normal_font", Ui.font("mono", 0.7))
	r.add_theme_font_override("bold_font", Ui.font("mono_med", 0.7))
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.size_flags_horizontal = Control.SIZE_SHRINK_END
	Ui.glow(r, Color(Ui.HUD_GLOW, 0.35), 5)
	return r


func _kv(key: String, val: String) -> String:
	return "%s [color=#dff7ff]%s[/color]" % [key, val]


# ---- top centre: the target (.hud-tc .target)
func _build_target() -> void:
	_target = Ui.Pane.new(10, 14, 10, 14)
	_target.custom_minimum_size.x = 230
	_target.visible = false
	_pin(_target, 0.5, 0.0, 0, 56, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	add_child(_target)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target.add_child(v)
	_t_eyebrow = Ui.eyebrow("Target")
	_t_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_t_eyebrow)
	_t_name = Ui.glow(Ui.label("", "display", 15, Color.WHITE, 0.6), Color(Ui.CYAN, 0.5), 6) as Label
	_t_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_t_name)
	_t_rows = Ui.rich(12, Ui.HUD_DIM)
	_t_rows.add_theme_font_override("normal_font", Ui.font("mono", 0.7))
	_t_rows.autowrap_mode = TextServer.AUTOWRAP_OFF
	_t_rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	Ui.glow(_t_rows, Color(Ui.HUD_GLOW, 0.35), 5)
	v.add_child(_t_rows)
	_t_hp_row = HBoxContainer.new()
	_t_hp_row.add_theme_constant_override("separation", 8)
	_t_hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t_hp = Ui.SegBar.new(8.0)
	_t_hp.color = Ui.AMBER2
	_t_hp_row.add_child(_t_hp)
	_t_hp_t = Ui.label("", "mono", 11, Ui.MUTED)
	_t_hp_row.add_child(_t_hp_t)
	v.add_child(_t_hp_row)
	_t_warn = Ui.label("", "body", 12, Ui.AMBER)
	_t_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_t_warn.visible = false
	v.add_child(_t_warn)


# ---- bottom left: the flight controls list (.hud-bl .controls), C hides it
const CONTROL_ROWS := [
	["Mouse", "Yaw · pitch"],
	[["W", "S"], "Throttle up · down"],
	[["X"], "Cut throttle · S at zero fires retros"],
	[["A", "D"], "Roll left · right"],
	[["Shift"], "Afterburner while throttled up (needs the refit · ×2 to ×5 speed · burns fuel fast)"],
	[["G"], "Laser overcharge on · off (needs the refit · up to ×3 damage · the beam draws fuel while it cuts)"],
	[["↑", "↓"], "Pitch"],
	[["LMB"], "Hold to fire the mining laser (Space or L too). It cuts only what the crosshair is on: aim the nose at a rock"],
	[["R"], "Radar pulse"],
	[["F"], "Flashlight on · off in flight · cargo ship services when docked"],
	[["E"], "Approach control within 2,250 m of the cargo ship · deposit ore on the pad"],
	[["Tab", "I"], "Inventory · slots of 100 · jettison stacks"],
	[["N"], "Nav map · warp (docked in the cargo ship)"],
	[["C"], "Hide · show this list"],
	[["Space"], "Skip a docking, departure or warp cutscene"],
	[["Esc"], "Pause · the menu with settings and controls"],
]


func _build_controls() -> void:
	_controls = Ui.Pane.new(10, 14, 10, 14)
	_pin(_controls, 0.0, 1.0, 20, -18, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	add_child(_controls)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.add_child(v)
	v.add_child(Ui.label("FLIGHT CONTROLS", "display", 10, Ui.HUD_DIM, 2.0))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grid)
	for row in CONTROL_ROWS:
		if row[0] is String:
			grid.add_child(Ui.label(row[0], "body", 11, Color(Ui.MUTED, 0.85)))
		else:
			grid.add_child(Ui.keys(row[0], true))
		var d := Ui.label(row[1], "body", 11, Color(Ui.MUTED, 0.85))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 300
		grid.add_child(d)


# ---- the hint bar above the status pane (.prompt) and the cargo-full notice (.notice)
func _build_prompt() -> void:
	_prompt = Ui.Pane.new(8, 14, 8, 14)
	_prompt.cut = 10.0
	_prompt.brackets = false
	_prompt.visible = false
	_pin(_prompt, 0.5, 1.0, 0, -160, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	add_child(_prompt)
	_prompt_text = Ui.rich(14, Ui.TEXT)
	_prompt_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_prompt_text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prompt.add_child(_prompt_text)


func _build_notice() -> void:
	_notice = PanelContainer.new()
	var sb := Ui.flat_box(Color(0.157, 0.086, 0.024, 0.92), Ui.AMBER, 1, 8)
	sb.border_width_left = 4
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	_notice.add_theme_stylebox_override("panel", sb)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.visible = false
	_pin(_notice, 0.5, 1.0, 0, -220, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	add_child(_notice)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.add_child(v)
	var b := Ui.label("CARGO HOLD FULL", "display", 13, Ui.AMBER2, 2.3)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	var t := Ui.rich(12, Ui.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.text = "Return to the cargo ship to stow it · press %s within %s to auto-dock" % [Ui.bb_kbd("E"), Data.fm(Data.DOCK_RANGE)]
	v.add_child(t)


# ---- cutscenes: letterbox bars with a caption (.cine); the fade for a jump
func _build_cine() -> void:
	_fade = ColorRect.new()
	_fade.color = Color(0.008, 0.012, 0.039, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_bar_top = ColorRect.new()
	_bar_top.color = Color("#02030a")
	_bar_top.anchor_right = 1.0
	_bar_top.offset_bottom = 80
	_bar_top.visible = false
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_top)
	_bar_bot = ColorRect.new()
	_bar_bot.color = Color("#02030a")
	_bar_bot.anchor_right = 1.0
	_bar_bot.anchor_top = 1.0
	_bar_bot.anchor_bottom = 1.0
	_bar_bot.offset_top = -80
	_bar_bot.visible = false
	_bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_bot)
	_caption = Ui.label("", "display", 13, Ui.AMBER2, 2.3)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.visible = false
	_pin(_caption, 0.5, 1.0, 0, -26, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	add_child(_caption)


# ---- toasts (.toast): a dark strip with an amber (or red) left edge, fading in and out
func toast(msg: String, bad: bool) -> void:
	# the coloured left edge is an outer panel showing through a 3 px margin, since a stylebox has one border colour
	var p := PanelContainer.new()
	var ob := Ui.flat_box(Ui.RED if bad else Ui.AMBER)
	ob.content_margin_left = 3
	p.add_theme_stylebox_override("panel", ob)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var inner := PanelContainer.new()
	var sb := Ui.flat_box(Color(0.024, 0.039, 0.094, 0.9), Ui.LINE2, 1, 7)
	sb.border_width_left = 0
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	inner.add_theme_stylebox_override("panel", sb)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(Ui.label(msg, "body", 13, Ui.TEXT))
	p.add_child(inner)
	p.modulate.a = 0.0
	_toasts.add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.3)
	tw.tween_property(p, "modulate:a", 0.0, 0.64)
	tw.tween_callback(p.queue_free)


# ---- the cargo ship services panel (#station): a glass side panel over the live view of the ship on the pad
func _build_services() -> void:
	_services = PanelContainer.new()
	var sb := Ui.flat_box(Ui.SIDE_BG, Ui.LINE2, 0, 0)
	sb.border_width_left = 1
	_services.add_theme_stylebox_override("panel", sb)
	_services.anchor_left = 1.0
	_services.anchor_right = 1.0
	_services.anchor_bottom = 1.0
	_services.offset_left = -580
	_services.visible = false
	add_child(_services)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	_services.add_child(v)
	# header
	var head := _margin(20, 26, 16, 26)
	var hh := _hbox(16)
	var left := _vbox(2)
	_svc_eyebrow = _card_eyebrow("Docked")
	left.add_child(_svc_eyebrow)
	left.add_child(_h2("Cargo ship"))
	_svc_sub = Ui.label("", "mono", 12, Ui.MUTED)
	left.add_child(_svc_sub)
	hh.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	var be := _card_eyebrow("Balance")
	be.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(be)
	_svc_credits = Ui.label("0 cr", "mono_semi", 24, Ui.AMBER2)
	_svc_credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_svc_credits)
	hh.add_child(right)
	head.add_child(hh)
	v.add_child(head)
	v.add_child(Ui.hrule())
	# body
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var body := _vbox(0)
	scroll.add_child(body)
	var col1 := _margin(20, 26, 20, 26)
	var c1 := _vbox(12)
	_svc_cargo_h = _h3("Cargo")
	c1.add_child(_svc_cargo_h)
	for g in [["storage", "Cargo ship storage", Ui.CARGO], ["fuel", "Cargo ship fuel supply", Ui.CYAN], ["parts", "Repair parts", Ui.GREEN]]:
		var gg := Ui.Gauge.new(g[1], g[2], 0.0, true, 10.0)
		gg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c1.add_child(gg)
		_svc_gauges[g[0]] = gg
	_svc_cargo = _vbox(10)
	c1.add_child(_svc_cargo)
	c1.add_child(Ui.spacer(false, 6))
	c1.add_child(_h3("Your hold"))
	var hold_l := Ui.para("", 13, Ui.MUTED)
	hold_l.name = "HoldList"
	c1.add_child(hold_l)
	var row := _hbox(10)
	_deposit_btn = Ui.button("Deposit all", func(): if _ship: _ship.deposit_all(), true)
	row.add_child(_deposit_btn)
	row.add_child(Ui.chip("E", false))
	row.add_child(Ui.button("Take all", func(): if _ship: _ship.take_all()))
	c1.add_child(row)
	col1.add_child(c1)
	body.add_child(col1)
	body.add_child(Ui.hrule())
	var col2 := _margin(20, 26, 20, 26)
	var c2 := _vbox(0)
	c2.add_child(_h3("Personal ship"))
	c2.add_child(Ui.spacer(false, 12))
	_svc_refits = _vbox(0)
	c2.add_child(_svc_refits)
	col2.add_child(c2)
	body.add_child(col2)
	# footer
	v.add_child(Ui.hrule())
	var foot := _margin(14, 26, 14, 26)
	var fh := _hbox(10)
	_depart_btn = Ui.button("Depart", func(): _depart_pressed(), true)
	fh.add_child(_depart_btn)
	fh.add_child(Ui.chip("W", false))
	_nav_btn = Ui.button("Warp to the Hub", func(): if _ship and _ship.docked and not zone["hub"]: _ship.start_warp(Data.ZONE_HUB))
	fh.add_child(_nav_btn)
	fh.add_child(Ui.button("Hide", func(): toggle_services()))
	fh.add_child(Ui.chip("F", false))
	fh.add_child(Ui.spacer())
	_reset_link = Ui.link("Reset save", func(): _reset_pressed())
	fh.add_child(_reset_link)
	foot.add_child(fh)
	v.add_child(foot)


func _depart_pressed() -> void:
	if _ship == null:
		return
	if zone["hub"]:
		toggle_map()
	else:
		_ship.start_departure()


func _reset_pressed() -> void:
	if _reset_armed:
		_reset_armed = false
		_reset_link.text = "Reset save"
		var m = get_parent()
		if m and m.has_method("wipe_save"):
			m.wipe_save()
		return
	_reset_armed = true
	_reset_link.text = "Click again to wipe save"
	get_tree().create_timer(4.0).timeout.connect(func(): _reset_armed = false; _reset_link.text = "Reset save")


func bind(ship: Ship) -> void:
	_ship = ship
	ship.docked_changed.connect(_on_docked)
	ship.map_requested.connect(open_map)


func _on_docked(is_docked: bool) -> void:
	if is_docked and not services_visible and not _services.visible:
		services_visible = true
	if not is_docked:
		services_visible = false
		if map_open:
			close_map()
	_services.visible = is_docked and services_visible
	if is_docked:
		refresh_panel()
		_inv_sig = ""


func toggle_services() -> void:
	if _ship == null or not _ship.docked:
		return
	services_visible = not services_visible
	_services.visible = services_visible
	if services_visible:
		refresh_panel()


## The pips beside a refit's name: one square per level, the earned ones amber.
func _pips(total: int, have: int) -> RichTextLabel:
	var r := Ui.rich(13, Ui.AMBER)
	r.add_theme_font_override("normal_font", Ui.font("mono", 1.5))
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var s := ""
	for j in total:
		s += "■" if j < have else "[color=%s]■[/color]" % Ui.hex(Ui.LINE2)
	r.text = s
	return r


## One refit row (.up): name and pips, the description with the next level in bold, the price button on the right.
func _refit_row(parent: Node, name: String, total: int, have: int, desc: String, cost: float, maxed: bool, fn: Callable, first: bool) -> void:
	if not first:
		parent.add_child(Ui.hrule())
	var pad := _margin(0 if first else 13, 0, 13, 0)
	var h := _hbox(14)
	var txt := _vbox(3)
	var head := _hbox(10)
	head.add_child(Ui.label(name, "display", 16, Ui.TEXT, 0.5))
	head.add_child(_pips(total, have))
	txt.add_child(head)
	var d := Ui.rich(14, Ui.MUTED)
	d.text = desc
	txt.add_child(d)
	h.add_child(txt)
	var b: Ui.ChamferButton
	if maxed:
		b = Ui.button("Max", func(): pass, false, true, 118.0)
		b.disabled = true
	else:
		b = Ui.button("%s cr" % Data.fmt(cost), fn, State.credits >= cost, true, 118.0)
		b.disabled = State.credits < cost
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	pad.add_child(h)
	parent.add_child(pad)


func refresh_panel() -> void:
	if _ship == null:
		return
	var at_hub: bool = _ship.hold
	_svc_eyebrow.text = "HOLDING STATION" if at_hub else "DOCKED"
	_svc_sub.text = ("Off %s" % str(zone.get("colony", "the colony"))) if at_hub else CargoShip.bay_name(_ship.dock_side)
	_svc_credits.text = "%s cr" % Data.fmt(State.credits)
	_svc_cargo_h.text = "CARGO AND MARKET" if at_hub else "CARGO"
	var su := State.store_used()
	var full: bool = su >= Data.STORE_SLOTS
	(_svc_gauges["storage"] as Ui.Gauge).show_value(State.store_total() / (Data.STORE_SLOTS * Data.STACK), ("%d / %d slots · FULL" if full else "%d / %d slots") % [su, Data.STORE_SLOTS], Ui.AMBER if full else Ui.CARGO)
	var low_fuel: bool = State.ship_fuel < Data.CARGO_FUEL_CAP * 0.2
	(_svc_gauges["fuel"] as Ui.Gauge).show_value(State.ship_fuel / Data.CARGO_FUEL_CAP, "%d / %d" % [floori(State.ship_fuel), roundi(Data.CARGO_FUEL_CAP)], Ui.AMBER if low_fuel else Ui.CYAN)
	var low_parts: bool = State.parts < float(Data.PARTS_CAP) * 0.2
	(_svc_gauges["parts"] as Ui.Gauge).show_value(State.parts / float(Data.PARTS_CAP), "%d / %d" % [floori(State.parts), Data.PARTS_CAP], Ui.AMBER if low_parts else Ui.GREEN)
	var lines: Array = []
	for k in Data.ORE_KEYS:
		if State.cargo[k] > 0.5:
			lines.append("%s %d u" % [Data.ORES[k]["name"], roundi(State.cargo[k])])
	var hold_l: Label = _services.find_child("HoldList", true, false)
	hold_l.text = (", ".join(lines) + "  ·  worth %s cr at the Hub" % Data.fmt(State.value_of(State.cargo))) if lines.size() > 0 else "The hold is empty."
	_deposit_btn.set_primary(lines.size() > 0)
	_deposit_btn.disabled = lines.size() == 0
	_refresh_market(at_hub)
	_depart_btn.text = "NAV MAP" if at_hub else "DEPART"
	_nav_btn.visible = not at_hub
	for c in _svc_refits.get_children():
		c.queue_free()
	var first := true
	for key in Data.UPGRADES:
		var u: Dictionary = Data.UPGRADES[key]
		var i: int = State.up[key]
		var maxed: bool = i >= u["costs"].size()
		var desc: String = ("[color=%s][b]%s[/b][/color] · Fully upgraded" % [Ui.hex(Ui.TEXT), Data.describe(key, i)]) if maxed else ("%s → [color=%s][b]%s[/b][/color]" % [Data.describe(key, i), Ui.hex(Ui.TEXT), Data.describe(key, i + 1)])
		var cost: float = 0.0 if maxed else float(u["costs"][i])
		_refit_row(_svc_refits, u["name"], u["levels"].size(), i + 1, desc, cost, maxed, _buy.bind(key), first)
		first = false
	_svc_refits.add_child(Ui.spacer(false, 18))
	_svc_refits.add_child(_h3("Cargo ship"))
	_svc_refits.add_child(Ui.spacer(false, 10))
	first = true
	for key in Data.DEPOT_UPGRADES:
		var u: Dictionary = Data.DEPOT_UPGRADES[key]
		var i: int = State.depot[key]
		var maxed: bool = i >= u["costs"].size()
		var desc: String = ("[color=%s][b]%s[/b][/color] · Fully upgraded" % [Ui.hex(Ui.TEXT), Data.describe_depot(key, i)]) if maxed else ("%s → [color=%s][b]%s[/b][/color]" % [Data.describe_depot(key, i), Ui.hex(Ui.TEXT), Data.describe_depot(key, i + 1)])
		var cost: float = 0.0 if maxed else float(u["costs"][i])
		_refit_row(_svc_refits, u["name"], u["costs"].size(), i, desc, cost, maxed, _buy_depot.bind(key), first)
		first = false
	var hint := Ui.rich(12, Ui.DIM)
	hint.text = "The dish leaves the ore it frees adrift for you to pick up. Collector drones gather it and stow it in the cargo ship's storage%s." % ((" · [b]%s[/b] stowed so far" % Data.fmt(State.drone_units)) if State.drone_units > 0.5 else "")
	_svc_refits.add_child(Ui.spacer(false, 10))
	_svc_refits.add_child(hint)


func _buy_depot(key: String) -> void:
	var r: Dictionary = State.buy_depot(key)
	toast(r["msg"], not r["ok"])
	if r["ok"]:
		Audio.sfx("chime")
	refresh_panel()


func _buy(key: String) -> void:
	var r: Dictionary = State.buy(key)
	toast(r["msg"], not r["ok"])
	if r["ok"]:
		Audio.sfx("chime")
	refresh_panel()


func _th(text: String, right: bool) -> Label:
	var l := Ui.label(text.to_upper(), "display_med", 11, Ui.DIM, 1.3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _td(text: String, right: bool = true, color: Color = Ui.TEXT) -> RichTextLabel:
	var r := Ui.rich(13, color)
	r.add_theme_font_override("normal_font", Ui.font("mono"))
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.text = ("[right]%s[/right]" % text) if right else text
	return r


func _dot(k: String) -> String:
	return "[color=%s]◆[/color] " % Ui.hex(Data.ORES[k]["color"])


## The colony market (renderMarket): what is aboard and what it fetches, the sell buttons, today's prices; and the
## cargo ship's fuel and parts purchases.
func _refresh_market(at_hub: bool) -> void:
	for c in _svc_cargo.get_children():
		c.queue_free()
	if not at_hub:
		return
	var fuel_cost := ceili((Data.CARGO_FUEL_CAP - State.ship_fuel) * Data.CARGO_FUEL_PRICE)
	var parts_cost := ceili((float(Data.PARTS_CAP) - State.parts) * Data.PARTS_PRICE)
	var buy := _hbox(10)
	var fb := Ui.button(("Refuel supply · %s cr" % Data.fmt(fuel_cost)) if fuel_cost > 0 else "Fuel supply full", func(): if _ship: _ship.refuel_cargo_ship(), fuel_cost > 0 and State.credits >= 1.0)
	fb.disabled = fuel_cost <= 0
	buy.add_child(fb)
	var pb := Ui.button(("Restock parts · %s cr" % Data.fmt(parts_cost)) if parts_cost > 0 else "Parts store full", func(): if _ship: _ship.buy_parts(), parts_cost > 0 and State.credits >= Data.PARTS_PRICE)
	pb.disabled = parts_cost <= 0
	buy.add_child(pb)
	_svc_cargo.add_child(buy)
	_svc_cargo.add_child(Ui.spacer(false, 10))
	_svc_cargo.add_child(_h3("%s market" % str(zone.get("colony", "Colony"))))
	var total := 0.0
	var any := false
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 7)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for h in ["Ore", "Hold", "Storage", "cr each", "Value", ""]:
		grid.add_child(_th(h, h != "Ore"))
	for k in Data.ORE_KEYS:
		var h: float = State.cargo[k]
		var s: float = State.store[k]
		if h + s < 0.5:
			continue
		any = true
		var p: float = State.price(k)
		var v: float = (h + s) * p
		total += v
		var d := roundi((float(State.market[k]) - 1.0) * 100.0)
		var delta := "" if d == 0 else (" [color=%s]▲%d%%[/color]" % [Ui.hex(Ui.GREEN), d] if d > 0 else " [color=%s]▼%d%%[/color]" % [Ui.hex(Ui.RED), -d])
		var exp := (" [color=%s]exotic +%d%%[/color]" % [Ui.hex(Ui.GREEN), roundi((Data.EXPORT_BONUS - 1.0) * 100.0)]) if Data.ORES[k].has("zone") else ""
		var name_cell := Ui.rich(13, Ui.TEXT)
		name_cell.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_cell.text = _dot(k) + str(Data.ORES[k]["name"]) + exp
		grid.add_child(name_cell)
		grid.add_child(_td(Data.fmt(h)))
		grid.add_child(_td(Data.fmt(s)))
		grid.add_child(_td("%.1f%s" % [p, delta]))
		grid.add_child(_td(Data.fmt(v)))
		var sl := Ui.link("sell", func(): if _ship: _ship.sell([k], true, true), 12)
		sl.size_flags_horizontal = Control.SIZE_SHRINK_END
		grid.add_child(sl)
	if any:
		_svc_cargo.add_child(grid)
		var tot := _hbox(10)
		tot.add_child(Ui.label("Everything aboard", "mono", 13, Ui.TEXT))
		tot.add_child(Ui.spacer())
		tot.add_child(Ui.label("%s cr" % Data.fmt(total), "mono_semi", 13, Ui.AMBER2))
		_svc_cargo.add_child(tot)
		var row := _hbox(10)
		row.add_child(Ui.button("Sell everything", func(): if _ship: _ship.sell(Data.ORE_KEYS, true, true), true))
		row.add_child(Ui.button("Sell hold only", func(): if _ship: _ship.sell(Data.ORE_KEYS, true, false)))
		row.add_child(Ui.button("Sell storage only", func(): if _ship: _ship.sell(Data.ORE_KEYS, false, true)))
		_svc_cargo.add_child(row)
	else:
		var none := Ui.para("Nothing aboard to sell. Cut ore in a belt zone and bring it back.", 13, Ui.DIM)
		_svc_cargo.add_child(none)
	var pg := GridContainer.new()
	pg.columns = 3
	pg.add_theme_constant_override("h_separation", 10)
	pg.add_theme_constant_override("v_separation", 7)
	pg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pg.add_child(_th("Prices today", false))
	pg.add_child(_th("", true))
	pg.add_child(_th("cr each", true))
	for k in Data.ORE_KEYS:
		var d := roundi((float(State.market[k]) - 1.0) * 100.0)
		var delta := "" if d == 0 else (" [color=%s]▲%d%%[/color]" % [Ui.hex(Ui.GREEN), d] if d > 0 else " [color=%s]▼%d%%[/color]" % [Ui.hex(Ui.RED), -d])
		var name_cell := Ui.rich(13, Ui.TEXT)
		name_cell.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_cell.text = _dot(k) + str(Data.ORES[k]["name"]) + ((" [color=%s]exotic[/color]" % Ui.hex(Ui.DIM)) if Data.ORES[k].has("zone") else "")
		pg.add_child(name_cell)
		var need: int = int(Data.ORES[k]["unlock"])
		pg.add_child(_td(("needs laser Lv%d" % need) if need > State.up["laser"] + 1 else "", true, Ui.DIM))
		pg.add_child(_td("%.1f%s" % [State.price(k), delta]))
	_svc_cargo.add_child(Ui.spacer(false, 4))
	_svc_cargo.add_child(pg)


# ---- the inventory (#inv): a glass panel from the left edge with the hold's slots (and the storage's while docked)
func _build_inventory() -> void:
	_inv = PanelContainer.new()
	var sb := Ui.flat_box(Ui.SIDE_BG, Ui.LINE2, 0, 0)
	sb.border_width_right = 1
	_inv.add_theme_stylebox_override("panel", sb)
	_inv.anchor_bottom = 1.0
	_inv.offset_right = 520
	_inv.visible = false
	add_child(_inv)
	var outer := _margin(22, 26, 18, 26)
	_inv.add_child(outer)
	var v := _vbox(0)
	outer.add_child(v)
	var head := _hbox(12)
	var left := _vbox(2)
	left.add_child(_card_eyebrow("Cargo hold"))
	left.add_child(_h2("Inventory"))
	head.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.alignment = BoxContainer.ALIGNMENT_END
	var he := _card_eyebrow("Hold")
	he.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(he)
	_inv_cap = Ui.label("0 / 4 slots", "mono_semi", 20, Ui.AMBER2)
	_inv_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_inv_cap)
	head.add_child(right)
	v.add_child(head)
	v.add_child(Ui.spacer(false, 12))
	var cr := _vbox(2)
	cr.add_child(_card_eyebrow("Credits"))
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 8)
	_inv_credits = Ui.glow(Ui.label("0", "mono_semi", 34, Ui.AMBER2), AMBER_TEXT_GLOW, 8) as Label
	ch.add_child(_inv_credits)
	var unit := Ui.label("cr", "mono_med", 14, Ui.AMBER)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	ch.add_child(unit)
	cr.add_child(ch)
	v.add_child(cr)
	v.add_child(Ui.spacer(false, 12))
	_inv_bar = Ui.SegBar.new(8.0)
	_inv_bar.segmented = false
	_inv_bar.track = Color(0.078, 0.098, 0.212)
	_inv_bar.color = Ui.CARGO
	v.add_child(_inv_bar)
	v.add_child(Ui.spacer(false, 14))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_inv_body = _vbox(10)
	scroll.add_child(_inv_body)
	v.add_child(Ui.spacer(false, 16))
	var foot := _hbox(14)
	foot.add_child(Ui.para("Each slot holds one stack of up to %d units of one ore, sorted most valuable first. Click ✕ to jettison a stack. Dock with the cargo ship to stow stacks in its storage; sell at the Hub." % roundi(Data.STACK), 13, Ui.DIM))
	var cb := Ui.button("Close", func(): toggle_inventory())
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(cb)
	var chip := Ui.chip("Tab", false)
	foot.add_child(chip)
	v.add_child(foot)

const AMBER_TEXT_GLOW := Color(0.949, 0.639, 0.227, 0.55)


func toggle_inventory() -> void:
	inv_open = not inv_open
	_inv.visible = inv_open
	if inv_open:
		_inv_sig = ""
		_refresh_inventory()


## One inventory slot (.slot): the ore's colour along the top edge, its name, the stack size, its value; ✕ jettisons.
## `store` slots take the stack back aboard on a click; hold slots stow theirs while docked.
func _slot(st: Dictionary, store: bool, docked: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := Ui.flat_box(Ui.PANEL2, Ui.LINE2, 1, 10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	p.custom_minimum_size = Vector2(0, 92)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if st.is_empty():
		sb.bg_color = Color(Ui.PANEL2, 0.45)
		sb.border_color = Color(Ui.LINE2, 0.45)
		p.add_theme_stylebox_override("panel", sb)
		var e := Ui.label("EMPTY", "body", 12, Color(Ui.DIM, 0.6), 1.5)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(e)
		return p
	var k: String = st["k"]
	var u: float = st["u"]
	var o: Dictionary = Data.ORES[k]
	# the ore's colour along the top edge: an outer panel in that colour showing through a 2 px top margin
	var ob := Ui.flat_box(o["color"])
	ob.content_margin_top = 2
	p.add_theme_stylebox_override("panel", ob)
	sb.border_width_top = 0
	var inner := PanelContainer.new()
	inner.add_theme_stylebox_override("panel", sb)
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.custom_minimum_size = Vector2(0, 90)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(Ui.label(o["name"], "body_semi", 14, Ui.TEXT))
	v.add_child(Ui.label("%d / %d" % [floori(u), roundi(Data.STACK)], "mono", 14, Ui.TEXT))
	v.add_child(Ui.label("%s cr" % Data.fmt(u * State.price(k)), "mono", 12, Ui.DIM))
	inner.add_child(v)
	# a plain Control does not lay its children out, so the ✕ can sit in the corner
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(overlay)
	p.add_child(inner)
	if not store:
		var x := Button.new()
		x.text = "✕"
		x.focus_mode = Control.FOCUS_NONE
		x.tooltip_text = "Jettison this stack"
		x.add_theme_font_override("font", Ui.font("body"))
		x.add_theme_font_size_override("font_size", 11)
		x.add_theme_color_override("font_color", Ui.MUTED)
		x.add_theme_color_override("font_hover_color", Ui.RED)
		for s in ["normal", "hover", "pressed"]:
			x.add_theme_stylebox_override(s, Ui.flat_box(Ui.PANEL, Ui.RED if s == "hover" else Ui.LINE2, 1, 0))
		x.custom_minimum_size = Vector2(20, 20)
		x.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		x.offset_left = -14
		x.offset_top = -6
		x.offset_right = 6
		x.offset_bottom = 14
		x.pressed.connect(func(): _jettison(k, u))
		overlay.add_child(x)
	if docked:
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.tooltip_text = "Click to take it back aboard" if store else "Click to stow it aboard the cargo ship"
		p.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if store:
					_take_stack(k, u)
				else:
					_stow_stack(k, u))
	return p


func _jettison(k: String, u: float) -> void:
	var dropped := State.jettison(k, u)
	if dropped > 0.5:
		toast("Jettisoned %d %s" % [roundi(dropped), Data.ORES[k]["name"]], false)
	_inv_sig = ""
	_refresh_inventory()


func _stow_stack(k: String, u: float) -> void:
	var moved := State.stow_stack(k, u)
	if moved < 0.5:
		toast("Cargo ship storage is full", true)
	else:
		Audio.sfx("stow")
		toast("Stowed %d %s aboard the cargo ship" % [roundi(moved), Data.ORES[k]["name"]], false)
		State.save_game()
	_inv_sig = ""
	_refresh_inventory()
	refresh_panel()


func _take_stack(k: String, u: float) -> void:
	var moved := State.take_stack(k, u)
	if moved < 0.5:
		toast("No room in the hold", true)
	else:
		Audio.sfx("stow")
		toast("Took %d %s back aboard" % [roundi(moved), Data.ORES[k]["name"]], false)
		State.save_game()
	_inv_sig = ""
	_refresh_inventory()
	refresh_panel()


func _grid(cols: int = 3) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


func _total_row(label: String, value: String, top_line: bool = true, color: Color = Ui.AMBER2) -> Control:
	var v := _vbox(10)
	if top_line:
		v.add_child(Ui.hrule(Ui.LINE2))
	var h := _hbox(10)
	h.add_child(Ui.label(label, "mono", 15, Ui.TEXT))
	h.add_child(Ui.spacer())
	h.add_child(Ui.label(value, "mono_semi", 15, color))
	v.add_child(h)
	return v


func _refresh_inventory() -> void:
	var docked: bool = _ship != null and _ship.docked
	var hold_st := State.stacks(State.cargo)
	var store_st := State.stacks(State.store) if docked else []
	var sig := "%d|%s|%s|%s|%d" % [State.cargo_slots(), str(hold_st), str(store_st), zone["id"], roundi(State.credits)]
	if sig == _inv_sig:
		return
	_inv_sig = sig
	var ns := State.cargo_slots()
	var us := State.used_slots()
	_inv_cap.text = "%d / %d slots" % [us, ns]
	_inv_credits.text = Data.fmt(State.credits)
	_inv_bar.set_value(float(us) / float(ns), Ui.AMBER if us >= ns else Ui.CARGO)
	for c in _inv_body.get_children():
		c.queue_free()
	var g := _grid(3)
	for i in ns:
		g.add_child(_slot(hold_st[i] if i < hold_st.size() else {}, false, docked))
	_inv_body.add_child(g)
	var can_deposit: bool = docked and State.cargo_total() > 0.5
	var row := _hbox(10)
	var dep := Ui.button("Deposit all", func(): if _ship: _ship.deposit_all(); _inv_sig = ""; _refresh_inventory(), can_deposit)
	dep.disabled = not can_deposit
	row.add_child(dep)
	row.add_child(Ui.chip("E", false))
	_inv_body.add_child(row)
	if us > 0:
		_inv_body.add_child(_total_row("Hold value at Hub prices", "%s cr" % Data.fmt(State.value_of(State.cargo))))
	else:
		var e := Ui.para("The hold is empty. Break a rock and fly through the ore it drops.", 14, Ui.DIM)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_inv_body.add_child(e)
	var su := State.store_used()
	if docked:
		_inv_body.add_child(Ui.spacer(false, 8))
		var xh := _hbox(10)
		xh.add_child(_card_eyebrow("Cargo ship storage"))
		xh.add_child(Ui.label("%d / %d slots" % [su, Data.STORE_SLOTS], "mono", 13, Ui.DIM))
		xh.add_child(Ui.spacer())
		xh.add_child(Ui.link("▲ Take all", func(): if _ship: _ship.take_all(); _inv_sig = ""; _refresh_inventory(), 13))
		_inv_body.add_child(xh)
		var sg := _grid(3)
		for i in Data.STORE_SLOTS:
			sg.add_child(_slot(store_st[i] if i < store_st.size() else {}, true, true))
		_inv_body.add_child(sg)
		if su > 0:
			_inv_body.add_child(_total_row("Storage value at Hub prices", "%s cr" % Data.fmt(State.value_of(State.store))))
		if su > 0 and us > 0:
			_inv_body.add_child(_total_row("Everything aboard", "%s cr" % Data.fmt(State.value_of(State.store) + State.value_of(State.cargo)), false))
		_inv_body.add_child(Ui.para("Click a stack to move it between the two grids. The storage rides with the cargo ship and sells at the Hub.", 12, Ui.DIM))
	else:
		_inv_body.add_child(_total_row("Cargo ship storage", "%d / %d slots · dock to transfer" % [su, Data.STORE_SLOTS], false, Ui.TEXT))


# ---- the nav computer (#map): the chart of charted zones and the picked zone's details, with the warp button
func _build_map() -> void:
	_map = Control.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.visible = false
	add_child(_map)
	var dimmer := ColorRect.new()
	dimmer.color = Ui.OVERLAY
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.add_child(dimmer)
	_map_card = Ui.Pane.new(0, 0, 0, 0, true)
	_map.add_child(_map_card)
	var v := _vbox(0)
	_map_card.add_child(v)
	var head := _margin(20, 26, 16, 26)
	var hh := _hbox(16)
	var left := _vbox(2)
	left.add_child(_card_eyebrow("Nav computer"))
	left.add_child(_h2("Charted zones"))
	hh.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	var fe := _card_eyebrow("Cargo ship fuel supply")
	fe.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(fe)
	_map_fuel = Ui.label("", "mono_semi", 24, Ui.AMBER2)
	_map_fuel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_map_fuel)
	hh.add_child(right)
	head.add_child(hh)
	v.add_child(head)
	v.add_child(Ui.hrule())
	var body := _hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cm := _margin(18, 22, 18, 22)
	cm.size_flags_stretch_ratio = 3.0
	_chart = Ui.Chart.new()
	_chart.zones = Data.ZONES
	_chart.picked.connect(func(z: Dictionary): _map_sel = z; _refresh_map())
	cm.add_child(_chart)
	body.add_child(cm)
	var vr := ColorRect.new()
	vr.color = Ui.LINE
	vr.custom_minimum_size.x = 1
	body.add_child(vr)
	var zm := _margin(20, 24, 20, 24)
	zm.size_flags_stretch_ratio = 2.0
	var zs := ScrollContainer.new()
	zs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	zs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_zinfo = _vbox(14)
	zs.add_child(_zinfo)
	zm.add_child(zs)
	body.add_child(zm)
	v.add_child(body)
	v.add_child(Ui.hrule())
	var foot := _margin(14, 26, 14, 26)
	var fh := _hbox(14)
	fh.add_child(Ui.para("Nothing sells in the belt: haul it to the Hub, where exclusive ore fetches 50% more. Your cargo ship, storage and all, warps with you.", 12, Ui.DIM))
	var cb := Ui.button("Close", func(): close_map())
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(cb)
	fh.add_child(Ui.chip("N", false))
	foot.add_child(fh)
	v.add_child(foot)


func toggle_map() -> void:
	if map_open:
		close_map()
	else:
		open_map()


func open_map() -> void:
	if _ship != null and not _ship.warp.is_empty():
		return
	map_open = true
	_map.visible = true
	if _map_sel.is_empty() or _map_sel["id"] == zone["id"]:
		_map_sel = {}
	_refresh_map()


func close_map() -> void:
	map_open = false
	_map.visible = false


func _kv_grid(pairs: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 4)
	for p in pairs:
		g.add_child(Ui.label(p[0], "body", 12, Ui.MUTED))
		var r := Ui.rich(12, Ui.TEXT)
		r.add_theme_font_override("normal_font", Ui.font("mono_med"))
		r.text = p[1]
		g.add_child(r)
	return g


func _ore_row(parent: Node, name_bb: String, rarity: String, price: String) -> void:
	parent.add_child(Ui.hrule())
	var h := _hbox(10)
	var l := _vbox(2)
	var n := Ui.rich(13, Ui.TEXT)
	n.text = name_bb
	l.add_child(n)
	l.add_child(Ui.label(rarity.to_upper(), "display", 10, Ui.DIM, 1.2))
	h.add_child(l)
	var pr := Ui.rich(12, Ui.MUTED)
	pr.add_theme_font_override("normal_font", Ui.font("mono"))
	pr.size_flags_horizontal = Control.SIZE_SHRINK_END
	pr.autowrap_mode = TextServer.AUTOWRAP_OFF
	pr.text = "[right]%s[/right]" % price
	h.add_child(pr)
	parent.add_child(h)


func _refresh_map() -> void:
	var vp := get_viewport().get_visible_rect().size
	var w: float = min(1060.0, vp.x - 48.0)
	var h: float = min(620.0, vp.y - 48.0)
	_map_card.set_anchors_preset(Control.PRESET_CENTER)
	_map_card.offset_left = -w * 0.5
	_map_card.offset_right = w * 0.5
	_map_card.offset_top = -h * 0.5
	_map_card.offset_bottom = h * 0.5
	_map_fuel.text = "%d / %d" % [floori(State.ship_fuel), roundi(Data.CARGO_FUEL_CAP)]
	var cur: Dictionary = zone
	var sel: Dictionary = _map_sel if not _map_sel.is_empty() else cur
	_chart.cur = cur
	_chart.sel = sel
	_chart.queue_redraw()
	for c in _zinfo.get_children():
		c.queue_free()
	var is_cur: bool = sel["id"] == cur["id"]
	var accent: Color = sel.get("accent", Ui.AMBER)
	var head := _vbox(2)
	head.add_child(Ui.eyebrow("Current zone" if is_cur else ("Colony zone" if sel["hub"] else "Charted belt"), accent))
	head.add_child(Ui.label(str(sel["name"]).to_upper(), "display", 20, Ui.TEXT, 1.2))
	_zinfo.add_child(head)
	_zinfo.add_child(Ui.para(str(sel["tag"]), 13, Ui.MUTED))
	var dist := "here" if is_cur else "%s ly" % str(Data.zone_ly(cur, sel))
	if sel["hub"]:
		_zinfo.add_child(_kv_grid([["Distance", dist], ["Colony", str(sel["colony"])], ["Market", "buys every ore · exotics +%d%%" % roundi((Data.EXPORT_BONUS - 1.0) * 100.0)], ["Fuel", "cargo ship resupplies here · %s cr/u" % str(Data.CARGO_FUEL_PRICE)], ["Danger", "none · colony patrols"]]))
		var aboard := floori(State.cargo_total() + State.store_total())
		var s1 := _vbox(4)
		s1.add_child(_h3("Aboard to sell"))
		s1.add_child(Ui.para(("%d across the hold and the cargo ship's storage" % aboard) if aboard > 0 else "nothing yet · the storage rides with the cargo ship", 12, Ui.MUTED))
		_zinfo.add_child(s1)
		var s2 := _vbox(4)
		s2.add_child(_h3("Holding station"))
		s2.add_child(Ui.para("On arrival the cargo ship flies in and takes up station off Meridian Colony, and the market and services open from there. Set a course here to leave.", 12, Ui.MUTED))
		_zinfo.add_child(s2)
	else:
		var danger: float = float(sel.get("danger", 0.5))
		var dtext := "quiet · light patrols" if danger <= 0.6 else ("patrolled · mines near rich fields" if danger <= 1.1 else ("contested · raider holds" if danger <= 1.6 else "lawless · heavy raider presence"))
		var dcol: Color = Ui.RED if danger > 1.6 else (Ui.AMBER if danger > 1.1 else Ui.TEXT)
		var nfields := 0
		for n in Belt.FIELDS_PER_BELT:
			nfields += n
		_zinfo.add_child(_kv_grid([["Distance", dist], ["Market", "none · sell at the Hub"], ["Belts", "%s · %d fields" % ["rich seams" if float(sel.get("amountMult", 1.0)) > 1.2 else ("sparse" if float(sel.get("density", 1.0)) < 1.0 else "typical"), nfields]], ["Danger", "[color=%s]%s[/color]" % [Ui.hex(dcol), dtext]]]))
		var s1 := _vbox(4)
		s1.add_child(_h3("Asteroid fields"))
		s1.add_child(Ui.para("%d ore fields and rich pockets across the base belts, and the ring belt above the planet." % nfields, 12, Ui.MUTED))
		_zinfo.add_child(s1)
		var s2 := _vbox(0)
		s2.add_child(_h3("Exclusive ore"))
		for k in Data.ORE_KEYS:
			var o: Dictionary = Data.ORES[k]
			if o.get("zone", "") != sel["id"]:
				continue
			var locked: bool = int(o["unlock"]) > State.up["laser"] + 1
			_ore_row(s2, _dot(k) + str(o["name"]), str(o.get("rarity", "Zone exclusive")) + ((" · needs laser Lv%d" % int(o["unlock"])) if locked else ""), "%d cr at the Hub" % roundi(float(o["price"]) * Data.EXPORT_BONUS))
		_zinfo.add_child(s2)
		var s3 := _vbox(0)
		s3.add_child(_h3("Planet"))
		var pd: Dictionary = sel["planet"]
		_ore_row(s3, "[color=%s]◆[/color] %s" % [Ui.hex(pd.get("tint", Ui.MUTED)), str(pd["name"])], "central world · not mineable", "")
		_zinfo.add_child(s3)
	var can: bool = not is_cur and _ship != null and _ship.docked and _ship.warp.is_empty()
	var wb := Ui.button("You are here" if is_cur else ("Warp · %s ly" % str(Data.zone_ly(cur, sel)) if can else "Dock with the cargo ship to warp"), func(): if can: close_map(); _ship.start_warp(sel), can)
	wb.disabled = not can
	_zinfo.add_child(wb)


# ---- the tutorial card (top-left) and its rings, fed by Tutorial
func _build_tutorial() -> void:
	_rings = RingOverlay.new()
	_rings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rings)
	_tut_box = PanelContainer.new()
	var sb := Ui.flat_box(Ui.CARD_BG, Ui.AMBER, 1, 12)
	sb.border_width_left = 4
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_bottom = 14
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	_tut_box.add_theme_stylebox_override("panel", sb)
	_tut_box.custom_minimum_size.x = 420
	_tut_box.offset_left = 18
	_tut_box.offset_top = 18
	_tut_box.offset_right = 438
	_tut_box.visible = false
	add_child(_tut_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_tut_box.add_child(v)
	var head := _hbox(10)
	_tut_step = _card_eyebrow("Flight Ops")
	head.add_child(_tut_step)
	head.add_child(Ui.spacer())
	head.add_child(Ui.link("Replay", func(): if tutorial: tutorial.speak(), 11))
	head.add_child(Ui.link("Skip tutorial", func(): if tutorial: tutorial.skip(), 11))
	v.add_child(head)
	_tut_title = Ui.label("", "display", 17, Ui.TEXT, 0.6)
	v.add_child(_tut_title)
	_tut_text = Ui.para("", 13, Ui.TEXT)
	_tut_text.add_theme_constant_override("line_spacing", 4)
	v.add_child(_tut_text)
	v.add_child(Ui.spacer(false, 6))
	var foot := _hbox(12)
	_tut_next = Ui.button("Next", func(): if tutorial: tutorial.advance(), true)
	foot.add_child(_tut_next)
	foot.add_child(Ui.chip("Enter", false))
	_tut_wait = Ui.label("", "mono", 11, Ui.AMBER2)
	_tut_wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_tut_wait)
	v.add_child(foot)


## Show a step ({} hides the card): step, total, title, text, auto, wait, final, ring, ring2.
func show_tutorial(d: Dictionary) -> void:
	if d.is_empty():
		_tut_box.visible = false
		_ring_names = []
		_rings.rects = []
		return
	_tut_box.visible = not _tut_hidden
	_tut_step.text = "FLIGHT OPS · %d / %d" % [d["step"], d["total"]]
	_tut_title.text = d["title"]
	_tut_text.text = d["text"]
	_tut_next.visible = not d["auto"]
	_tut_next.get_parent().get_child(1).visible = not d["auto"]
	_tut_next.text = "FINISH" if d["final"] else "NEXT"
	_tut_wait.text = ("waiting · " + str(d["wait"])) if d["auto"] else ""
	_ring_names = []
	for k in ["ring", "ring2"]:
		if str(d.get(k, "")) != "":
			_ring_names.append(d[k])


func tutorial_hidden(h: bool) -> void:
	_tut_hidden = h
	if tutorial and tutorial.active():
		_tut_box.visible = not h


func toggle_controls() -> void:
	_controls.visible = not _controls.visible
	State.settings["controls"] = _controls.visible
	State.save_game()


## The red flash of a hull knock (.dmg.on).
func damage_flash() -> void:
	_dmg_t = 0.6


# ---- every frame
func update(ship: Ship, belt: Belt, carrier: CargoShip) -> void:
	var vp := get_viewport().get_visible_rect().size
	var docked: bool = ship.docked
	var in_cut: bool = ship.in_cinematic()
	var hold: bool = ship.hold
	# the ship: hull, fuel, speed, thrust, cargo
	var hp: float = State.stat("hull")["hp"]
	var hf: float = State.hull / hp
	_g_hull.show_value(hf, "%d / %d" % [ceili(State.hull), roundi(hp)], Ui.RED if hf < 0.25 else (Ui.AMBER if hf < 0.5 else Ui.GREEN), hf < 0.25)
	var tank: float = State.stat("tank")["cap"]
	var ff: float = State.fuel / tank
	_g_fuel.show_value(ff, "%d / %d" % [floori(State.fuel), roundi(tank)], Ui.RED if ff < 0.2 else Ui.CYAN)
	var tv: float = 1.0 if ship.braking else ship.throttle
	_g_thr.show_value(tv, "RETRO" if ship.braking else ("%d%%" % roundi(ship.throttle * 100.0)), Ui.CYAN if ship.braking else (Ui.AMBER2 if ship.afterburning else Ui.AMBER))
	var us := State.used_slots()
	var ns := State.cargo_slots()
	var full: bool = us >= ns and State.cargo_total() >= State.cargo_capacity() - 0.5
	_g_cargo.show_value(State.cargo_total() / State.cargo_capacity(), "%d / %d slots" % [us, ns], Ui.AMBER if full else Ui.CARGO)
	_g_cargo.value_l.add_theme_color_override("font_color", Ui.AMBER2 if full else Ui.GLOW_TEXT)
	var spd := ship.speed() * Data.METRE
	_speed_big.text = ("HOLD" if hold else "DOCK") if docked else Data.fmt(spd)
	# the situation
	var to_carrier: float = ship.true_pos().distance_to(carrier.true_pos) if carrier else 0.0
	var spd_t := ("HOLDING" if hold else "DOCKED") if docked else str(roundi(spd))
	_row1.text = "[right]%s   %s   %s   %s[/right]" % [_kv("ZONE", str(zone["name"])), _kv("SPD", spd_t), _kv("CARGO SHIP", Data.fm(to_carrier)), _kv("FIELD", "—")]
	var laser := "CUTTING" if ship.laser_on else ("FIRING" if ship.firing else "ready")
	if ship.overcharge:
		laser += " ⚡×%s" % str(State.stat("overcharge")["mult"])
	var radar := "READY" if ship.radar_cd <= 0.0 else "%.1fs" % ship.radar_cd
	_row2.text = "[right]%s   %s   %s   %s[/right]" % [_kv("LASER", laser), _kv("RANGE", "%s m" % Data.fm(State.stat("range")["reach"])), _kv("RADAR", radar), _kv("THREAT", "none")]
	# the target
	var has_target: bool = ship.target >= 0 and belt.alive[ship.target] == 1 and not docked
	var reach: float = State.stat("range")["reach"]
	var tdist := 0.0
	var reason := ""
	if has_target:
		var i := ship.target
		tdist = belt.pos[i].distance_to(ship.true_pos())
		_target.visible = true
		_t_name.text = ("Barren" if belt.ore[i] < 0 else str(Data.ORES[Data.ORE_KEYS[belt.ore[i]]]["name"])) + " Rock"
		_t_rows.text = "%s   %s" % [_kv("SIZE", Belt.CLS_NAME[belt.cls[i]]), _kv("RANGE", Data.fm(tdist) + " m" + ("" if tdist <= reach else " · beyond reach"))]
		_t_hp.set_value(belt.hp[i] / max(1.0, belt.hp_max[i]), Ui.AMBER2)
		_t_hp_t.text = "%d / %d" % [ceili(max(0.0, belt.hp[i])), roundi(belt.hp_max[i])]
		if belt.ore[i] >= 0:
			var need: int = int(Data.ORES[Data.ORE_KEYS[belt.ore[i]]]["unlock"])
			if need > State.up["laser"] + 1:
				reason = "Needs the Lv%d mining laser" % need
		_t_warn.text = reason
		_t_warn.visible = reason != ""
	else:
		_target.visible = false
	# the hint bar
	var segs: Array = []
	if not docked:
		if not ship.cut.is_empty():
			if ship.cut["mode"] == "hold":
				segs.append("Colony control has the cargo ship · %s" % str(zone.get("colony", "the colony")))
			elif ship.cut["mode"] == "dock":
				segs.append("Approach control has the ship · %s" % CargoShip.bay_name(int(ship.cut["side"])))
			if ship.cut["mode"] != "depart":
				segs.append("%s Skip" % Ui.bb_kbd("Space"))
		elif carrier and to_carrier < Data.DOCK_RANGE and not hold:
			segs.append("%s Auto-dock with the cargo ship · or fly in through either hangar mouth" % Ui.bb_kbd("E"))
		if has_target and ship.cut.is_empty():
			var i := ship.target
			if not ship.firing:
				segs.append("%s Hold to mine" % Ui.bb_kbd("LMB"))
			elif belt.ore[i] < 0:
				segs.append("Breaking rock · scrap only")
			else:
				segs.append("%s %s" % ["Cutting" if ship.laser_on else "Aiming at", str(Data.ORES[Data.ORE_KEYS[belt.ore[i]]]["name"])])
	elif started and State.cargo_total() > 0.5 and not hold:
		segs.append("%s Deposit all ore into the cargo ship" % Ui.bb_kbd("E"))
	var ptext := ("[color=%s]  ·  [/color]" % Ui.hex(Ui.DIM)).join(segs)
	if ptext != _prompt_text.text:
		_prompt_text.text = ptext
	var base: float = 18.0 + _status.size.y + 14.0
	_prompt.offset_top = -base
	_prompt.offset_bottom = -base
	_notice.offset_top = -(base + (_prompt.size.y + 10.0 if segs.size() > 0 else 0.0))
	_notice.offset_bottom = _notice.offset_top
	_notice.visible = started and full and not docked and not in_cut
	# what shows when: the hangar hides the situation, the controls and the hint; a cutscene hides nearly everything
	var show_flight: bool = started and not in_cut
	_status.visible = show_flight
	_status.modulate.a = 0.85 if docked else 1.0
	_readouts.visible = show_flight and not docked
	_controls.visible = show_flight and not docked and bool(State.settings.get("controls", true))
	_prompt.visible = show_flight and not docked and segs.size() > 0
	_target.visible = _target.visible and show_flight
	if in_cut:
		_tut_box.visible = false
	_bar_top.visible = in_cut
	_bar_bot.visible = in_cut
	_bar_top.offset_bottom = vp.y * 0.11
	_bar_bot.offset_top = -vp.y * 0.11
	_caption.visible = in_cut
	_caption.offset_top = -vp.y * 0.036 - 16.0
	_caption.offset_bottom = _caption.offset_top
	if in_cut:
		if not ship.warp.is_empty():
			var z: Dictionary = ship.warp["z"]
			_caption.text = ("JUMP · %s · %s LY · SPACE SKIPS" % [str(z["name"]), str(Data.zone_ly(zone, z))]).to_upper()
		elif ship.cut["mode"] == "hold":
			_caption.text = ("ARRIVAL · %s · SPACE SKIPS" % str(zone.get("colony", "the colony"))).to_upper()
		else:
			_caption.text = ("APPROACH · %s · CARGO SHIP · SPACE SKIPS" % CargoShip.bay_name(int(ship.cut["side"]))).to_upper()
		if _services.visible:
			_services.visible = false
	elif docked and services_visible and not _services.visible:
		_services.visible = true
	_fade.color.a = ship.warp_fade()
	# the reticle on the target
	if has_target and show_flight and ship.cut.is_empty():
		var sp := ship.cam.unproject_position(belt.pos[ship.target] - ship.main.world_offset)
		_reticle.visible = not ship.cam.is_position_behind(belt.pos[ship.target] - ship.main.world_offset)
		_reticle.position = sp - Vector2(32, 32)
		_reticle.hot = ship.laser_on
		_reticle.queue_redraw()
	else:
		_reticle.visible = false
	# the cargo ship marker
	if carrier and show_flight and not docked and not hold:
		var p := carrier.position
		var cam := ship.cam
		var behind := cam.is_position_behind(p)
		var sp := cam.unproject_position(p)
		if behind:
			sp = vp - sp
		var on := not behind and sp.x > 0 and sp.x < vp.x and sp.y > 0 and sp.y < vp.y
		var ang := 0.0
		if not on:
			var c := vp * 0.5
			var d := sp - c
			if d.length() < 1.0:
				d = Vector2(1, 0)
			ang = d.angle()
			var m := 46.0
			var sc: float = min(absf((c.x - m) / d.x) if d.x != 0.0 else INF, absf((c.y - m) / d.y) if d.y != 0.0 else INF)
			sp = c + d * sc
		_marker.visible = true
		_marker.off = not on
		_marker.angle = ang
		_marker.position = sp - Vector2(_marker.size.x * 0.5, 8.0 if on else 8.0) - (Vector2(0, 30) if on else Vector2.ZERO)
		_marker.queue_redraw()
	else:
		_marker.visible = false
	# radar blips
	var items: Array = []
	if show_flight and not docked and belt.count > 0:
		var marked := belt.marked(State.time, ship.true_pos(), 36)
		var bi := 0
		for m in marked:
			var i: int = m[0]
			if i == ship.target:
				continue
			var wp: Vector3 = belt.pos[i] - ship.main.world_offset
			var behind := ship.cam.is_position_behind(wp)
			var sp := ship.cam.unproject_position(wp)
			if behind:
				sp = vp - sp
			var on := not behind and sp.x > 0 and sp.x < vp.x and sp.y > 0 and sp.y < vp.y
			var ang := 0.0
			if not on:
				var c := vp * 0.5
				var d := sp - c
				if d.length() < 1.0:
					d = Vector2(1, 0)
				ang = d.angle()
				var mm := 46.0
				var sc: float = min(absf((c.x - mm) / d.x) if d.x != 0.0 else INF, absf((c.y - mm) / d.y) if d.y != 0.0 else INF)
				sp = c + d * sc
			var col: Color = Data.ORES[Data.ORE_KEYS[belt.ore[i]]]["color"] if belt.ore[i] >= 0 else Ui.CYAN
			var lbl := ("%s %s m" % [str(Data.ORES[Data.ORE_KEYS[belt.ore[i]]]["name"]) if belt.ore[i] >= 0 else "Rock", Data.fm(float(m[1]))]) if bi < 4 else ""
			items.append({"pos": sp, "off": not on, "ang": ang, "color": col, "label": lbl, "alpha": clampf(float(m[2]) / 6.0, 0.0, 1.0)})
			bi += 1
	_blips.items = items
	_blips.queue_redraw()
	# the damage flash on a knock
	if _last_hull >= 0.0 and State.hull < _last_hull - 0.5 and not docked:
		damage_flash()
	_last_hull = State.hull
	if _dmg_t > 0.0:
		_dmg_t = max(0.0, _dmg_t - get_process_delta_time())
		_dmg.set_strength(0.55 * _dmg_t / 0.6)
	# side panels follow the window
	_services.offset_left = -min(580.0, vp.x * 0.52)
	_inv.offset_right = min(520.0, vp.x * 0.48)
	if docked and Engine.get_process_frames() % 30 == 0 and _services.visible:
		refresh_panel()
	if inv_open and Engine.get_process_frames() % 15 == 0:
		_refresh_inventory()
	# the tutorial's rings follow their targets
	var rects: Array = []
	if _tut_box.visible:
		for n in _ring_names:
			var c: Control = _ring_targets.get(n)
			if c and c.is_visible_in_tree():
				var r := c.get_global_rect()
				if r.size.x > 2.0 and r.size.y > 2.0:
					rects.append(r)
	_rings.rects = rects
