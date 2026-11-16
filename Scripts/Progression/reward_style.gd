class_name RewardStyle
extends RefCounted

## Shared look for the stage-reward screen: the HUD's dark navy panels, cyan
## accent and Xirod headings. Presentation only.

const FONT: Font = preload("res://Assets/FrontEndPrototype/Xirod.otf")
const INK := Color(0.015, 0.025, 0.05, 1.0)
const PANEL := Color(0.03, 0.05, 0.1, 0.86)
const PANEL_RAISED := Color(0.055, 0.085, 0.15, 0.94)
const CYAN := Color(0.25, 0.9, 1.0, 1.0)
const PALE := Color(0.85, 0.93, 1.0, 1.0)
const MUTED := Color(0.52, 0.62, 0.74, 1.0)
const AMBER := Color(1.0, 0.82, 0.28, 1.0)
const DANGER := Color(1.0, 0.38, 0.32, 1.0)

static func box(fill: Color, border: Color, border_width: int = 2, margin: Vector4 = Vector4(12, 8, 12, 8)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin.x
	style.content_margin_top = margin.y
	style.content_margin_right = margin.z
	style.content_margin_bottom = margin.w
	return style

static func glow_box(fill: Color, border: Color, glow: float = 14.0) -> StyleBoxFlat:
	var style := box(fill, border, 2, Vector4(0, 0, 0, 0))
	style.shadow_color = Color(border.r, border.g, border.b, 0.55)
	style.shadow_size = int(glow)
	return style

static func label(target: Label, size: int, color: Color = PALE, heading: bool = true) -> void:
	if heading:
		target.add_theme_font_override("font", FONT)
	target.add_theme_font_size_override("font_size", size)
	target.add_theme_color_override("font_color", color)
