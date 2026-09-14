class_name Ui
extends Object
## The browser HUD's stylesheet, in Godot terms. belt-runner-3d.html styles its HUD with CSS: chamfered glass panes with
## cyan corner brackets, segmented gauges that glow, Chakra Petch for display type, IBM Plex Sans for body text and IBM
## Plex Mono for numbers, amber primary buttons cut at two corners, key chips. Everything here is a static helper or a
## small custom Control that draws one of those pieces, so hud.gd and menu.gd read like the markup. The fonts are the
## same three families the browser pulls from Google Fonts, bundled under assets/fonts (Open Font Licence).

const BG := Color("#070912")
const PANEL := Color("#0E1224")
const PANEL2 := Color("#151A30")
const LINE := Color("#262D4C")
const LINE2 := Color("#343C62")
const TEXT := Color("#E8ECF8")
const MUTED := Color("#8E96B4")
const DIM := Color("#5B6384")
const AMBER := Color("#F2A33A")
const AMBER2 := Color("#FFC466")
const AMBER_DIM := Color("#7A5320")
const CYAN := Color("#5ED3F0")
const RED := Color("#F26B5E")
const GREEN := Color("#6BD69A")
const CARGO := Color("#B8C0DA")
const INK := Color("#1A1004")
const GLOW_TEXT := Color("#DFF7FF")
const HUD_DIM := Color(0.369, 0.827, 0.941, 0.55)
const HUD_FAINT := Color(0.369, 0.827, 0.941, 0.22)
const HUD_GLOW := Color(0.369, 0.827, 0.941, 0.45)
const AMBER_GLOW := Color(0.949, 0.639, 0.227, 0.55)
const GLASS_TOP := Color(0.031, 0.047, 0.102, 0.74)
const GLASS_BOT := Color(0.031, 0.047, 0.102, 0.5)
const CARD_BG := Color(0.055, 0.071, 0.141, 0.94)
const SIDE_BG := Color(0.055, 0.071, 0.141, 0.84)
const OVERLAY := Color(0.016, 0.024, 0.055, 0.62)
const HOVER := Color("#1C2340")

const FONT_FILES := {
	"display": "res://assets/fonts/ChakraPetch-SemiBold.ttf",
	"display_bold": "res://assets/fonts/ChakraPetch-Bold.ttf",
	"display_med": "res://assets/fonts/ChakraPetch-Medium.ttf",
	"body": "res://assets/fonts/IBMPlexSans-Variable.ttf",
	"mono": "res://assets/fonts/IBMPlexMono-Regular.ttf",
	"mono_med": "res://assets/fonts/IBMPlexMono-Medium.ttf",
	"mono_semi": "res://assets/fonts/IBMPlexMono-SemiBold.ttf",
}
static var _fonts := {}


## A font by role: display / display_bold / display_med / body / body_med / body_semi / mono / mono_med / mono_semi, with
## optional letter spacing in pixels (the CSS's letter-spacing). Missing font files fall back to the engine's font.
static func font(kind: String, spacing: float = 0.0) -> Font:
	var key := "%s:%.1f" % [kind, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var base_kind := kind
	var weight := 0
	if kind == "body_med":
		base_kind = "body"
		weight = 500
	elif kind == "body_semi":
		base_kind = "body"
		weight = 600
	var base: Font = null
	if FONT_FILES.has(base_kind) and ResourceLoader.exists(FONT_FILES[base_kind]):
		base = load(FONT_FILES[base_kind])
	if base == null:
		base = ThemeDB.fallback_font
	var f: Font = base
	if weight > 0 or spacing != 0.0:
		var v := FontVariation.new()
		v.base_font = base
		if weight > 0:
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		if spacing != 0.0:
			v.spacing_glyph = roundi(spacing)
		f = v
	_fonts[key] = f
	return f


static func label(text: String, kind: String, size: int, color: Color, spacing: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind, spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The CSS text-shadow glow: a soft outline in the glow colour, no offset.
static func glow(l: Control, c: Color, size: int = 6) -> Control:
	l.add_theme_color_override("font_shadow_color", c)
	l.add_theme_constant_override("shadow_outline_size", size)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	return l


## .eyebrow: display 11px, uppercase, letter-spaced, muted (hud-dim on the flight HUD, muted on cards).
static func eyebrow(text: String, color: Color = HUD_DIM, size: int = 11) -> Label:
	return label(text.to_upper(), "display", size, color, 1.5)


## A mono number, glowing cyan as the HUD's readings do.
static func reading(text: String, size: int = 12) -> Label:
	return glow(label(text, "mono", size, GLOW_TEXT), Color(HUD_GLOW, 0.35)) as Label


## A body-text label that wraps.
static func para(text: String, size: int = 13, color: Color = TEXT) -> Label:
	var l := label(text, "body", size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A row of key chips, e.g. ["W", "S"], as an HBox.
static func keys(list: Array, hud: bool = true) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in list:
		h.add_child(chip(str(k), hud))
	return h


## <kbd>: a key chip. HUD chips are cyan glass; card chips are the darker panel2 with a heavier bottom edge.
static func chip(text: String, hud: bool = true) -> PanelContainer:
	var l := label(text, "mono", 10 if hud else 11, GLOW_TEXT if hud else TEXT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CYAN, 0.08) if hud else PANEL2
	sb.border_color = HUD_FAINT if hud else LINE2
	sb.set_border_width_all(1)
	if not hud:
		sb.border_width_bottom = 2
	sb.content_margin_left = 5 if hud else 6
	sb.content_margin_right = 5 if hud else 6
	sb.content_margin_top = 0 if hud else 1
	sb.content_margin_bottom = 0 if hud else 1
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(l)
	return p


static func empty_box(top: float, right: float, bottom: float, left: float) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_top = top
	sb.content_margin_right = right
	sb.content_margin_bottom = bottom
	sb.content_margin_left = left
	return sb


static func flat_box(bg: Color, border: Color = Color.TRANSPARENT, width: int = 0, pad: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_content_margin_all(pad)
	return sb


## A polygon with two corners cut: the pane cuts top-right and bottom-left, the card / button cut top-left and bottom-right.
static func chamfer(size: Vector2, cut: float, card: bool) -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var c: float = min(cut, w * 0.5, h * 0.5)
	if card:
		return PackedVector2Array([Vector2(c, 0), Vector2(w, 0), Vector2(w, h - c), Vector2(w - c, h), Vector2(0, h), Vector2(0, c)])
	return PackedVector2Array([Vector2(0, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h), Vector2(c, h), Vector2(0, h - c)])


static func spacer(h: bool = true, px: float = 0.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size.x = px
	else:
		c.custom_minimum_size.y = px
	return c


static func hrule(color: Color = LINE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size.y = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## .link: underlined dim text that turns red on hover.
static func link(text: String, fn: Callable, size: int = 12) -> LinkButton:
	var b := LinkButton.new()
	b.text = text
	b.add_theme_font_override("font", font("body"))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", RED)
	b.add_theme_color_override("font_pressed_color", RED)
	b.add_theme_color_override("font_focus_color", DIM)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	return b


## A RichTextLabel set up with the three families so [b], [code] and colours read as the browser's inline markup.
static func rich(size: int = 13, color: Color = TEXT) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", font("body"))
	r.add_theme_font_override("bold_font", font("body_semi"))
	r.add_theme_font_override("mono_font", font("mono"))
	r.add_theme_font_override("italics_font", font("display", 1.5))
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("mono_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_color_override("default_color", color)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


## An inline key chip for RichTextLabel text: [E] rendered as a boxed mono key.
static func bb_kbd(k: String) -> String:
	return "[bgcolor=#5ed3f018][color=#dff7ff][code] %s [/code][/color][/bgcolor]" % k


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


# ---- .pane / .panel / .card: the chamfered surfaces
## The glass pane of the flight HUD: a gradient glass cut at the top-right and bottom-left corners, a faint cyan border
## and two bright corner brackets (top-left, bottom-right). `card` swaps to the solid panel of the overlays: the panel
## colour, a line2 border, and the cut at the other two corners, without brackets.
class Pane extends PanelContainer:
	var cut := 14.0
	var card := false
	var brackets := true
	var top_color: Color = Ui.GLASS_TOP
	var bot_color: Color = Ui.GLASS_BOT
	var border: Color = Ui.HUD_FAINT
	var bracket_color: Color = Ui.CYAN

	func _init(pad_top := 12.0, pad_right := 18.0, pad_bottom := 12.0, pad_left := 18.0, as_card := false) -> void:
		card = as_card
		if card:
			top_color = Ui.PANEL
			bot_color = Ui.PANEL
			border = Ui.LINE2
			brackets = false
		add_theme_stylebox_override("panel", Ui.empty_box(pad_top, pad_right, pad_bottom, pad_left))
		mouse_filter = Control.MOUSE_FILTER_STOP if card else Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var poly := Ui.chamfer(size, cut, card)
		var cols := PackedColorArray()
		for p in poly:
			cols.append(top_color.lerp(bot_color, clampf(p.y / max(1.0, size.y), 0.0, 1.0)))
		draw_polygon(poly, cols)
		var outline := PackedVector2Array(poly)
		outline.append(poly[0])
		draw_polyline(outline, border, 1.0, true)
		if brackets:
			var b := 16.0
			draw_polyline(PackedVector2Array([Vector2(1, b), Vector2(1, 1), Vector2(b, 1)]), bracket_color, 2.0, true)
			var w := size.x
			var h := size.y
			draw_polyline(PackedVector2Array([Vector2(w - b, h - 1), Vector2(w - 1, h - 1), Vector2(w - 1, h - b)]), bracket_color, 2.0, true)


## .bar: the segmented gauge bar (6 px on, 2 px off) with a glow under the filled part.
class SegBar extends Control:
	var value := 0.0
	var color: Color = Ui.CYAN
	var track: Color = Color(Ui.CYAN, 0.08)
	var segmented := true
	var blink := false
	var _t := 0.0

	func _init(h := 8.0) -> void:
		custom_minimum_size = Vector2(0, h)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		_t += dt
		if blink:
			modulate.a = 0.35 if fmod(_t, 1.0) > 0.5 else 1.0
		elif modulate.a != 1.0:
			modulate.a = 1.0

	func set_value(v: float, c: Color) -> void:
		if absf(v - value) > 0.001 or c != color:
			value = v
			color = c
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var fw := clampf(value, 0.0, 1.0) * w
		if segmented:
			var x := 0.0
			while x < w:
				draw_rect(Rect2(x, 0, min(6.0, w - x), h), track)
				x += 8.0
			if fw > 0.5:
				draw_rect(Rect2(-2, -2, fw + 4, h + 4), Color(color, 0.16))
				x = 0.0
				while x < fw:
					draw_rect(Rect2(x, 0, min(6.0, fw - x), h), color)
					x += 8.0
		else:
			draw_rect(Rect2(0, 0, w, h), track)
			if fw > 0.5:
				draw_rect(Rect2(0, 0, fw, h), color)


## .gauge: a head row (eyebrow name, mono reading) over a segmented bar.
class Gauge extends VBoxContainer:
	var name_l: Label
	var value_l: Label
	var bar: SegBar

	func _init(title: String, color: Color, width := 150.0, big := false, bar_h := 8.0) -> void:
		custom_minimum_size.x = width
		add_theme_constant_override("separation", 7 if big else 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l = Ui.eyebrow(title, Ui.HUD_DIM, 14 if big else 11)
		head.add_child(name_l)
		head.add_child(Ui.spacer())
		value_l = Ui.reading("", 15 if big else 12)
		head.add_child(value_l)
		add_child(head)
		bar = SegBar.new(bar_h)
		bar.color = color
		add_child(bar)

	func show_value(v: float, text: String, color: Color, blink := false) -> void:
		value_l.text = text
		bar.set_value(v, color)
		bar.blink = blink


## .btn: display type, uppercase, letter-spaced, cut at the top-left and bottom-right corners; `primary` is the amber one.
## The chamfered face is drawn by a child behind the button's own (empty) styleboxes.
class ChamferButton extends Button:
	var primary := false
	var cut := 6.0
	var _face: Control

	func _init(t: String, prim := false, mono := false, min_w := 0.0) -> void:
		text = t.to_upper() if not mono else t
		primary = prim
		focus_mode = Control.FOCUS_NONE
		for s in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(s, Ui.empty_box(9, 16, 9, 16))
		add_theme_font_override("font", Ui.font("mono_med" if mono else "display", 0.0 if mono else 0.8))
		add_theme_font_size_override("font_size", 14 if mono else 13)
		custom_minimum_size.x = min_w
		_face = Face.new()
		_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_face.show_behind_parent = true
		_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_face)
		_recolor()

	func set_primary(p: bool) -> void:
		primary = p
		_recolor()

	func _recolor() -> void:
		var fc: Color = Ui.INK if primary else Ui.TEXT
		add_theme_color_override("font_color", fc)
		add_theme_color_override("font_hover_color", fc)
		add_theme_color_override("font_pressed_color", fc)
		add_theme_color_override("font_focus_color", fc)
		add_theme_color_override("font_hover_pressed_color", fc)
		add_theme_color_override("font_disabled_color", Color(fc, 0.42))

	class Face extends Control:
		func _process(_dt: float) -> void:
			queue_redraw()
		func _draw() -> void:
			var b: ChamferButton = get_parent()
			var bg: Color
			var border: Color
			if b.primary:
				bg = Ui.AMBER2 if (b.is_hovered() and not b.disabled) else Ui.AMBER
				border = bg
			else:
				bg = Ui.HOVER if (b.is_hovered() and not b.disabled) else Ui.PANEL2
				border = Ui.LINE2
			if b.disabled:
				bg.a *= 0.42
				border.a *= 0.42
			var poly := Ui.chamfer(size, b.cut, true)
			draw_colored_polygon(poly, bg)
			var outline := PackedVector2Array(poly)
			outline.append(poly[0])
			draw_polyline(outline, border, 1.0, true)


static func button(text: String, fn: Callable, primary := false, mono := false, min_w := 0.0) -> ChamferButton:
	var b := ChamferButton.new(text, primary, mono, min_w)
	b.pressed.connect(fn)
	return b


## .reticle: four corner brackets round whatever the nose is on; amber while the laser cuts; heavier when locked.
class Reticle extends Control:
	var hot := false
	var locked := false

	func _init() -> void:
		size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c: Color = Ui.AMBER if hot else Ui.CYAN
		var w := 3.0 if locked else 2.0
		var l := 18.0 if locked else 14.0
		var s := size.x
		var glow := Color(c, 0.35)
		for pass_i in 2:
			var col := glow if pass_i == 0 else c
			var wd := w + 3.0 if pass_i == 0 else w
			draw_polyline(PackedVector2Array([Vector2(0, l), Vector2(0, 0), Vector2(l, 0)]), col, wd)
			draw_polyline(PackedVector2Array([Vector2(s - l, 0), Vector2(s, 0), Vector2(s, l)]), col, wd)
			draw_polyline(PackedVector2Array([Vector2(0, s - l), Vector2(0, s), Vector2(l, s)]), col, wd)
			draw_polyline(PackedVector2Array([Vector2(s - l, s), Vector2(s, s), Vector2(s, s - l)]), col, wd)


## .marker: a rotated square (or, off screen, an arrow) over a small letter-spaced label. The HUD moves it each frame.
class Marker extends Control:
	var text := "CARGO SHIP"
	var color: Color = Ui.AMBER
	var off := false
	var angle := 0.0
	var round := false    # .marker.field: a dashed circle instead of the diamond
	var small := false    # .marker.drone: a smaller diamond and label
	var font: Font

	func _init() -> void:
		size = Vector2(240, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = Ui.font("display", 1.4)

	func _draw() -> void:
		var cx := size.x * 0.5
		var half := 4.0 if small else 5.0
		if off:
			var t := Transform2D(angle + PI * 0.5, Vector2(cx, 8))
			draw_set_transform_matrix(t)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -6), Vector2(6, 5), Vector2(-6, 5)]), color)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		elif round:
			for k in 8:
				draw_arc(Vector2(cx, 8), 4.5, k * TAU / 8.0, (k + 0.6) * TAU / 8.0, 4, color, 2.0)
		else:
			var t := Transform2D(PI * 0.25, Vector2(cx, 8))
			draw_set_transform_matrix(t)
			draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), color, false, 2.0)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		var fs := 9 if small else 10
		draw_string(font, Vector2(1, 33), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(0, 32), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, color)


## Radar blips: a diamond in the ore's colour on every marked rock in view (an arrow at the screen edge for the ones out
## of view), the nearest few with a name-and-range label on a dark backing.
class Blips extends Control:
	var items: Array = []   # {pos, off, ang, color, label, alpha}
	var font: Font

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = Ui.font("mono_med")

	func _draw() -> void:
		for it in items:
			var p: Vector2 = it["pos"]
			var c: Color = it["color"]
			c.a = it["alpha"]
			if it["off"]:
				draw_set_transform_matrix(Transform2D(float(it["ang"]) + PI * 0.5, p))
				draw_colored_polygon(PackedVector2Array([Vector2(0, -7), Vector2(7, 6), Vector2(-7, 6)]), c)
			else:
				draw_set_transform_matrix(Transform2D(PI * 0.25, p))
				draw_rect(Rect2(-6.5, -6.5, 13, 13), Color(c, c.a * 0.35), false, 4.0)
				draw_rect(Rect2(-4.5, -4.5, 9, 9), c, false, 2.0)
			draw_set_transform_matrix(Transform2D.IDENTITY)
			var lbl: String = it["label"]
			if lbl != "":
				var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				var r := Rect2(p.x - tw * 0.5 - 6, p.y + 11, tw + 12, 20)
				draw_rect(r, Color(0.024, 0.039, 0.094, 0.6 * c.a))
				draw_rect(r, Color(Ui.CYAN, 0.25 * c.a), false, 1.0)
				draw_string(font, Vector2(r.position.x + 6, r.position.y + 15), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Ui.GLOW_TEXT, c.a))


## .hudfx and .dmg: a soft vignette, and the red flash on a hull knock, as full-screen shader rects.
class Vignette extends ColorRect:
	const SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.008, 0.016, 0.047, 1.0);
uniform float inner = 0.58;
uniform float strength = 0.5;
void fragment() {
	float r = length((UV - 0.5) * 2.0) / 1.41421;
	COLOR = vec4(tint.rgb, smoothstep(inner, 1.0, r) * strength);
}
"""
	var mat: ShaderMaterial

	func _init(tint: Color, inner: float, strength: float) -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		color = Color.WHITE
		var sh := Shader.new()
		sh.code = SHADER
		mat = ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tint", tint)
		mat.set_shader_parameter("inner", inner)
		mat.set_shader_parameter("strength", strength)
		material = mat

	func set_strength(s: float) -> void:
		mat.set_shader_parameter("strength", s)


## The nav computer's chart: the browser's 112 x 64 SVG (grid, dashed lanes with distances, a node per zone) drawn to
## fit the control. Clicking a node picks it.
class Chart extends Control:
	signal picked(z: Dictionary)
	var zones: Array = []
	var cur: Dictionary = {}
	var sel: Dictionary = {}
	var _u := 1.0
	var _o := Vector2.ZERO

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(320, 200)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _fit() -> void:
		_u = min(size.x / 112.0, size.y / 64.0)
		_o = (size - Vector2(112, 64) * _u) * 0.5

	func _p(v: Vector2) -> Vector2:
		return _o + v * _u

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_fit()
			for z in zones:
				if _p(z["map"]).distance_to(ev.position) < 8.0 * _u:
					sel = z
					picked.emit(z)
					queue_redraw()
					return

	func _draw() -> void:
		_fit()
		var u := _u
		var fd := Ui.font("display", 0.5)
		var fm := Ui.font("mono")
		for x in range(10, 112, 10):
			draw_line(_p(Vector2(x, 2)), _p(Vector2(x, 62)), Ui.LINE, max(1.0, 0.15 * u))
		for y in range(10, 64, 10):
			draw_line(_p(Vector2(2, y)), _p(Vector2(110, y)), Ui.LINE, max(1.0, 0.15 * u))
		if cur.is_empty():
			return
		for z in zones:
			if z["id"] == cur["id"]:
				continue
			var a: Vector2 = cur["map"]
			var b: Vector2 = z["map"]
			draw_dashed_line(_p(a), _p(b), Ui.LINE2, max(1.0, 0.28 * u), 1.2 * u)
			draw_string(fm, _p((a + b) * 0.5 + Vector2(1, -1)), "%s ly" % str(Data.zone_ly(cur, z)), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, roundi(2.2 * u)), Ui.DIM)
		for z in zones:
			var m: Vector2 = z["map"]
			var c := _p(m)
			var accent: Color = z.get("accent", Ui.AMBER)
			var is_cur: bool = z["id"] == cur["id"]
			var is_sel: bool = not sel.is_empty() and z["id"] == sel["id"]
			if is_cur:
				draw_arc(c, 3.2 * u, 0, TAU, 48, accent, max(1.0, 0.3 * u), true)
			if is_sel:
				draw_arc(c, 4.6 * u, 0, TAU, 48, Color(Ui.AMBER2, 0.9), max(1.0, 0.25 * u), true)
			if z["hub"]:
				draw_arc(c, 2.1 * u, 0, TAU, 40, accent, max(1.0, 0.7 * u), true)
				draw_circle(c, 0.7 * u, accent)
			else:
				draw_set_transform_matrix(Transform2D(PI * 0.25, c))
				draw_rect(Rect2(-1.6 * u, -1.6 * u, 3.2 * u, 3.2 * u), accent)
				draw_set_transform_matrix(Transform2D.IDENTITY)
			var right: bool = m.x > 85
			var tx := m.x - 6.0 if right else m.x + 5.0
			var al := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
			var tp := _p(Vector2(tx, m.y + 1))
			var w := 60.0 * u
			var start := tp - Vector2(w, 0) if right else tp
			draw_string(fd, start, str(z["name"]).to_upper(), al, w, maxi(10, roundi(3.1 * u)), Ui.AMBER2 if is_sel else Ui.TEXT)
			var sub := "current position" if is_cur else ("colony · sells ore" if z["hub"] else _exclusives(z))
			var sp := _p(Vector2(tx, m.y + 4.2))
			var sstart := sp - Vector2(w, 0) if right else sp
			draw_string(fm, sstart, sub, al, w, maxi(9, roundi(2.3 * u)), Ui.AMBER if is_sel else Ui.MUTED)

	func _exclusives(z: Dictionary) -> String:
		var ex: Array = []
		for k in Data.ORE_KEYS:
			if Data.ORES[k].get("zone", "") == z["id"]:
				ex.append(Data.ORES[k]["name"])
		return " · ".join(ex)
