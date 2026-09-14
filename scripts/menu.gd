class_name Menu
extends Control
## The start menu and the pause menu, one card (#intro .card.menu in belt-runner-3d.html): the sector eyebrow, the
## BELT RUNNER title, a line about the game, then Continue / Resume, New game, Controls and Settings. Settings has the
## sound switch and volume, the HUD size, a tutorial restart and the save wipe; Controls is the long list of keys.
## Escape brings it up over the frozen game and takes it away again. Main owns the game state; this only asks.

signal start_requested
signal resume_requested
signal new_game_requested
signal wipe_requested
signal tutorial_restart
signal setting_changed(key: String, value: Variant)
signal quit_requested

var started := false
var has_save := false
var _card: Ui.Pane
var _pages := {}
var _continue_btn: Ui.ChamferButton
var _continue_info: Label
var _new_btn: Ui.ChamferButton
var _new_info: Label
var _new_armed := false
var _sound_btn: Ui.ChamferButton
var _vol: HSlider
var _vol_t: Label
var _hud: HSlider
var _hud_t: Label
var _tut_btn: Ui.ChamferButton
var _wipe_btn: Ui.ChamferButton
var _wipe_armed := false
var _title_eyebrow: Label
var _syncing := false

const CONTROLS := [
	["Mouse", "Aim the ship: cursor left or right of centre yaws, above or below pitches."],
	[["W", "S"], "Throttle up and down. The engines hold whatever setting you leave them at. X cuts to zero; S at zero fires the retro thrusters."],
	[["A", "D", "↑", "↓"], "Roll left and right · pitch up and down on keys."],
	[["G"], "Laser overcharge on or off. With the refit fitted, the beam cuts ×1.5 to ×3 harder while it is armed, and the reactor feeds it from your fuel tank the whole time it is cutting. It switches itself off when the tank runs dry."],
	[["Shift"], "Afterburner: hold it with the throttle open and thrust and top speed multiply, ×2 with the first refit up to ×5 at the top level. It burns fuel far faster, so use it in bursts."],
	[["R"], "Radar pulse · marks every ore rock in scanner range"],
	[["LMB"], "Hold to fire the mining laser (Space or L too). The dish under the nose cuts whatever the crosshair is on until it breaks. It never picks targets by itself: keep the nose on the rock."],
	[["Q"], "Hover the mouse over a rock or the cargo ship (the label names it), then press Q to lock the crosshair on it. The ship steers itself to keep it in the crosshair (you keep the throttle and roll) until it breaks up or goes beyond 50,000 m. Hover a different target and press Q to switch directly to it. Press Q over the current target or empty space to release the lock. A locked object always shows its range, and its details sit top centre."],
	[["F"], "Flashlight: a spot beam from the nose, on or off. While docked F hides and shows the cargo ship services instead."],
	[["T"], "Out of fuel? T calls a tug from the cargo ship: it latches on with a tractor beam and hauls you into a hangar bay for 15% of your credits. A hull breach calls it by itself."],
	["Docking", "Fly slowly into either mouth of the cargo ship's through-hangar, or press E within 2,250 m of it and approach control flies you in. Once docked, E deposits all your ore into the cargo ship's storage. Fuel and repairs flow while you sit on the pad. The cargo ship warps with you; ore only sells at the Hub."],
	[["N"], "Open the nav map. The cargo ship makes the jump between zones, so dock in its hangar first; you ride along."],
	[["Tab", "I"], "Inventory: the hold's stacks, and the cargo ship's storage while docked."],
	[["C"], "Hide or show the flight controls list in the bottom-left corner. Remembered between sessions."],
	[["Space"], "During a docking, departure, arrival or warp cutscene, skip to the end of it."],
	[["Esc"], "Pause · opens this menu with Settings and Controls"],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Ui.OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)
	_card = Ui.Pane.new(28, 34, 28, 34, true)
	_card.custom_minimum_size.x = 520
	center.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	_card.add_child(v)
	_title_eyebrow = Ui.eyebrow("Kessler belt · sector 7", Ui.MUTED)
	v.add_child(_title_eyebrow)
	var h1 := Ui.label("BELT RUNNER", "display_bold", 40, Ui.AMBER2, 3.0)
	v.add_child(h1)
	v.add_child(Ui.spacer(false, 8))
	var tag := Ui.para("One ship, one laser, an empty hold. Cut ore from the rocks, stow it aboard your cargo ship, sell it at the Hub, and refit the ship until it can afford a jump drive out.", 14, Ui.MUTED)
	tag.add_theme_constant_override("line_spacing", 4)
	v.add_child(tag)
	v.add_child(Ui.spacer(false, 22))
	_pages["main"] = _build_main()
	_pages["settings"] = _build_settings()
	_pages["controls"] = _build_controls()
	for p in _pages.values():
		v.add_child(p)
	_show_page("main")


func _menu_button(text: String, fn: Callable, primary := false) -> Array:
	# .menu-btn: a wide left-aligned button with a small mono note at the right edge
	var b := Ui.button(text, fn, primary)
	b.add_theme_font_size_override("font_size", 15)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, Ui.empty_box(13, 16, 13, 16))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var info := Ui.label("", "mono", 11, Color(Ui.INK if primary else Ui.TEXT, 0.8))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	info.offset_left = -300
	info.offset_right = -16
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(info)
	return [b, info]


func _build_main() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var c := _menu_button("Continue", func(): if started: resume_requested.emit() else: start_requested.emit(), true)
	_continue_btn = c[0]
	_continue_info = c[1]
	v.add_child(_continue_btn)
	var n := _menu_button("New game", func(): _new_game())
	_new_btn = n[0]
	_new_info = n[1]
	v.add_child(_new_btn)
	var ctl := _menu_button("Controls", func(): _show_page("controls"))
	v.add_child(ctl[0])
	var st := _menu_button("Settings", func(): _show_page("settings"))
	v.add_child(st[0])
	var foot := Ui.para("Two charted zones for now: the Kessler Belt, where the ore is, and the Hub, where Meridian Colony buys all of it.", 11, Ui.DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(foot)
	var ver := Ui.label("Belt Runner 3D · v" + Data.VERSION, "mono", 11, Ui.DIM, 1.0)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ver)
	var q := Ui.link("Quit to desktop", func(): quit_requested.emit(), 11)
	q.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(q)
	return v


func _setting_row(label: String, control: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.flat_box(Color.TRANSPARENT, Ui.LINE, 1, 8))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Ui.label(label, "body", 13, Ui.MUTED)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	h.add_child(Ui.spacer())
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(control)
	p.add_child(h)
	return p


func _slider(minv: float, maxv: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = 100.0   # the slider's own default (0) would clamp to the minimum and read as a change: both start at 100 %
	s.custom_minimum_size.x = 150
	s.focus_mode = Control.FOCUS_NONE
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Ui.AMBER
	var track := Ui.flat_box(Ui.PANEL2, Ui.LINE2, 1)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", Ui.flat_box(Ui.AMBER))
	s.add_theme_stylebox_override("grabber_area_highlight", Ui.flat_box(Ui.AMBER2))
	return s


func _build_settings() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_sound_btn = Ui.button("On", func(): _toggle_sound(), false, false, 110.0)
	_sound_btn.add_theme_font_size_override("font_size", 12)
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		_sound_btn.add_theme_stylebox_override(s, Ui.empty_box(7, 14, 7, 14))
	v.add_child(_setting_row("Sound", _sound_btn))
	var vh := HBoxContainer.new()
	vh.add_theme_constant_override("separation", 10)
	_vol = _slider(0, 100, 1)
	_vol.value_changed.connect(func(x: float): _vol_t.text = "%d%%" % roundi(x); if not _syncing: setting_changed.emit("volume", x / 100.0))
	vh.add_child(_vol)
	_vol_t = Ui.label("100%", "mono", 11, Ui.MUTED)
	_vol_t.custom_minimum_size.x = 34
	_vol_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vh.add_child(_vol_t)
	v.add_child(_setting_row("Sound volume", vh))
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 10)
	_hud = _slider(70, 160, 5)
	_hud.value_changed.connect(func(x: float): _hud_t.text = "%d%%" % roundi(x); if not _syncing: setting_changed.emit("hud", x / 100.0))
	hh.add_child(_hud)
	_hud_t = Ui.label("100%", "mono", 11, Ui.MUTED)
	_hud_t.custom_minimum_size.x = 34
	_hud_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hh.add_child(_hud_t)
	v.add_child(_setting_row("HUD size", hh))
	_tut_btn = Ui.button("Run again", func(): _restart_tutorial(), false, false, 110.0)
	_small(_tut_btn)
	v.add_child(_setting_row("Tutorial", _tut_btn))
	_wipe_btn = Ui.button("Wipe save", func(): _wipe(), false, false, 110.0)
	_small(_wipe_btn)
	v.add_child(_setting_row("Saved game", _wipe_btn))
	v.add_child(Ui.spacer(false, 6))
	var back := Ui.button("Back", func(): _show_page("main"))
	v.add_child(back)
	return v


func _small(b: Button) -> void:
	b.add_theme_font_size_override("font_size", 12)
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, Ui.empty_box(7, 14, 7, 14))


func _build_controls() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 360
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row in CONTROLS:
		if row[0] is String:
			var k := Ui.label(row[0], "body", 13, Ui.MUTED)
			k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			grid.add_child(k)
		else:
			var keys := Ui.keys(row[0], false)
			keys.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			grid.add_child(keys)
		var d := Ui.para(row[1], 13, Ui.MUTED)
		d.custom_minimum_size.x = 340
		grid.add_child(d)
	scroll.add_child(grid)
	v.add_child(scroll)
	var back := Ui.button("Back", func(): _show_page("main"))
	v.add_child(back)
	return v


func _show_page(name: String) -> void:
	for k in _pages:
		_pages[k].visible = k == name


## Bring the menu up: at launch (started = false) or as the pause menu.
func open(is_started: bool, save_exists: bool) -> void:
	started = is_started
	has_save = save_exists
	_render()
	visible = true


func close() -> void:
	visible = false


func _render() -> void:
	_continue_btn.visible = has_save or started
	_continue_btn.text = "RESUME" if started else "CONTINUE"
	_continue_info.text = "paused" if started else (("%s cr · %s" % [Data.fmt(State.credits), str(Data.zone_by_id(State.zone_id)["name"])]) if has_save else "")
	_new_btn.set_primary(not has_save and not started)
	_new_info.add_theme_color_override("font_color", Color(Ui.INK if _new_btn.primary else Ui.TEXT, 0.8))
	_new_info.text = "wipes the save" if (has_save or started) else ""
	_new_armed = false
	_title_eyebrow.text = ("PAUSED · " + str(Data.zone_by_id(State.zone_id)["name"])).to_upper() if started else "KESSLER BELT · SECTOR 7"
	_sync_settings()
	_show_page("main")


## The controls show the saved settings; nothing they emit while being set this way counts as a change.
func _sync_settings() -> void:
	var s: Dictionary = State.settings
	_syncing = true
	_sound_btn.text = "ON" if bool(s.get("sound", true)) else "OFF"
	_vol.value = roundi(float(s.get("volume", 1.0)) * 100.0)
	_vol_t.text = "%d%%" % roundi(float(s.get("volume", 1.0)) * 100.0)
	_hud.value = roundi(float(s.get("hud", 1.0)) * 100.0)
	_hud_t.text = "%d%%" % roundi(float(s.get("hud", 1.0)) * 100.0)
	_syncing = false
	_tut_btn.text = "RUN AGAIN"
	_wipe_btn.text = "WIPE SAVE"
	_wipe_armed = false


func _toggle_sound() -> void:
	var on: bool = not bool(State.settings.get("sound", true))
	setting_changed.emit("sound", on)
	_sound_btn.text = "ON" if on else "OFF"


func _restart_tutorial() -> void:
	tutorial_restart.emit()
	_tut_btn.text = "RESTARTED"
	get_tree().create_timer(2.5).timeout.connect(func(): _tut_btn.text = "RUN AGAIN")


func _wipe() -> void:
	if _wipe_armed:
		_wipe_armed = false
		wipe_requested.emit()
		return
	_wipe_armed = true
	_wipe_btn.text = "CLICK AGAIN"
	get_tree().create_timer(4.0).timeout.connect(func(): _wipe_armed = false; _wipe_btn.text = "WIPE SAVE")


func _new_game() -> void:
	if not has_save and not started:
		start_requested.emit()
		return
	if not _new_armed:
		_new_armed = true
		_new_info.text = "click again to wipe the save"
		get_tree().create_timer(4.0).timeout.connect(func(): _new_armed = false; if visible: _new_info.text = "wipes the save")
		return
	_new_armed = false
	new_game_requested.emit()
