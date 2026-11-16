class_name UpgradeRow
extends Button

## One purchasable permanent stat (the Figma "Purchasable Upgrade" component):
## icon, name + level text (the button text), price tag top right and a level
## indicator along the bottom.

const STAT_NAMES := {
	&"damage": "Damage",
	&"heat_damage_multiplier": "Heat damage",
	&"battery_drain_reduction": "Battery saver",
	&"dash_cooldown_reduction": "Dash recharge",
	&"heat_gauge_increase": "Heat capacity",
}
const ICON_SIZE := 48.0
const BAR_HEIGHT := 16.0

var stat_id: StringName
var _row: Dictionary = {}
var _built := false
var _glyph: RewardGlyph
var _price: Label
var _price_box: PanelContainer
var _pips: HBoxContainer

func setup(row: Dictionary) -> void:
	_row = row
	stat_id = row.id
	var display: String = STAT_NAMES.get(stat_id, String(stat_id).replace("_", " ").capitalize())
	# Name and level in one line; tests and screen readers read the same text.
	text = "%s  Lv%d/%d" % [display.to_upper(), row.level, row.cap]
	disabled = not row.can_purchase
	if _built:
		_apply()

func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	custom_minimum_size = Vector2(0, 78)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_override("font", RewardStyle.FONT)
	add_theme_font_size_override("font_size", 13)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		add_theme_color_override(color_name, RewardStyle.PALE)
	add_theme_color_override("font_disabled_color", RewardStyle.MUTED)
	var margin := Vector4(ICON_SIZE + 24.0, 6, 104, BAR_HEIGHT + 10.0)
	add_theme_stylebox_override("normal", RewardStyle.box(RewardStyle.PANEL_RAISED, Color(0.25, 0.9, 1.0, 0.3), 2, margin))
	add_theme_stylebox_override("hover", RewardStyle.box(Color(0.08, 0.12, 0.2, 0.96), Color(0.25, 0.9, 1.0, 0.85), 2, margin))
	add_theme_stylebox_override("pressed", RewardStyle.glow_box(Color(0.06, 0.16, 0.24, 0.96), RewardStyle.CYAN, 8.0))
	add_theme_stylebox_override("disabled", RewardStyle.box(Color(0.035, 0.05, 0.08, 0.78), Color(0.45, 0.55, 0.65, 0.2), 2, margin))
	add_theme_stylebox_override("focus", RewardStyle.box(Color(0, 0, 0, 0), RewardStyle.PALE, 2, margin))
	_build()
	_apply()

func _build() -> void:
	_built = true
	var icon_box := Panel.new()
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.position = Vector2(8, 8)
	icon_box.size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_box.add_theme_stylebox_override("panel", RewardStyle.box(Color(0.02, 0.04, 0.08, 0.95), Color(0.25, 0.9, 1.0, 0.45), 1, Vector4(0, 0, 0, 0)))
	add_child(icon_box)
	_glyph = RewardGlyph.new()
	_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glyph.offset_left = 8
	_glyph.offset_top = 8
	_glyph.offset_right = -8
	_glyph.offset_bottom = -8
	icon_box.add_child(_glyph)
	_price_box = PanelContainer.new()
	_price_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_price_box.offset_left = -92
	_price_box.offset_right = -8
	_price_box.offset_top = 6
	_price_box.offset_bottom = 34
	add_child(_price_box)
	_price = Label.new()
	_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	RewardStyle.label(_price, 13, RewardStyle.AMBER)
	_price_box.add_child(_price)
	var bar := PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = -BAR_HEIGHT - 8
	bar.offset_bottom = -8
	bar.add_theme_stylebox_override("panel", RewardStyle.box(Color(0.02, 0.035, 0.07, 0.9), Color(0.25, 0.9, 1.0, 0.25), 1, Vector4(4, 4, 4, 4)))
	add_child(bar)
	_pips = HBoxContainer.new()
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.add_theme_constant_override("separation", 4)
	bar.add_child(_pips)

func _apply() -> void:
	_glyph.kind = stat_id
	_glyph.color = RewardStyle.CYAN if not disabled or _row.get("capped", false) else RewardStyle.MUTED
	var capped: bool = _row.get("capped", false)
	_price.text = "MAX" if capped else "%.2f" % float(_row.get("cost", 0.0))
	var price_color := RewardStyle.PALE if capped else (RewardStyle.AMBER if _row.get("can_purchase", false) else RewardStyle.DANGER)
	_price.add_theme_color_override("font_color", price_color)
	_price_box.add_theme_stylebox_override("panel", RewardStyle.box(Color(0.03, 0.05, 0.1, 0.95), Color(price_color.r, price_color.g, price_color.b, 0.6), 1, Vector4(6, 2, 6, 2)))
	for child in _pips.get_children():
		_pips.remove_child(child)
		child.queue_free()
	for index in int(_row.get("cap", 0)):
		var pip := ColorRect.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pip.color = RewardStyle.CYAN if index < int(_row.get("level", 0)) else Color(0.25, 0.9, 1.0, 0.14)
		_pips.add_child(pip)
