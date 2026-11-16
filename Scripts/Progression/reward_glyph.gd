class_name RewardGlyph
extends Control

## Small procedural icon for a stat or upgrade (no art assets): drawn in a
## unit box so it scales with the control.

@export var kind: StringName = &"upgrade":
	set(value):
		kind = value
		queue_redraw()
@export var color: Color = RewardStyle.CYAN:
	set(value):
		color = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _p(x: float, y: float) -> Vector2:
	var side := minf(size.x, size.y)
	return Vector2((size.x - side) * 0.5, (size.y - side) * 0.5) + Vector2(x, y) * side

func _draw() -> void:
	var side := minf(size.x, size.y)
	var width := maxf(2.0, side * 0.085)
	match kind:
		&"damage":
			draw_line(_p(0.18, 0.82), _p(0.82, 0.18), color, width)
			draw_line(_p(0.18, 0.18), _p(0.82, 0.82), color, width)
			draw_line(_p(0.12, 0.62), _p(0.38, 0.88), color, width * 0.8)
			draw_line(_p(0.62, 0.88), _p(0.88, 0.62), color, width * 0.8)
		&"heat_damage_multiplier":
			draw_colored_polygon(PackedVector2Array([_p(0.5, 0.06), _p(0.74, 0.42), _p(0.68, 0.84), _p(0.5, 0.94), _p(0.32, 0.84), _p(0.26, 0.5), _p(0.4, 0.58)]), color)
			draw_colored_polygon(PackedVector2Array([_p(0.5, 0.52), _p(0.6, 0.7), _p(0.5, 0.86), _p(0.4, 0.7)]), RewardStyle.INK)
		&"battery_drain_reduction":
			draw_rect(Rect2(_p(0.2, 0.3), Vector2(0.56, 0.4) * side), color, false, width)
			draw_rect(Rect2(_p(0.76, 0.42), Vector2(0.08, 0.16) * side), color)
			draw_line(_p(0.36, 0.42), _p(0.5, 0.58), color, width * 0.9)
			draw_line(_p(0.5, 0.58), _p(0.64, 0.42), color, width * 0.9)
		&"dash_cooldown_reduction":
			for offset in [0.0, 0.26]:
				draw_polyline(PackedVector2Array([_p(0.18 + offset, 0.22), _p(0.46 + offset, 0.5), _p(0.18 + offset, 0.78)]), color, width)
		&"heat_gauge_increase":
			draw_arc(_p(0.5, 0.66), side * 0.36, PI, TAU, 24, color, width)
			draw_line(_p(0.5, 0.66), _p(0.7, 0.4), color, width * 0.9)
			draw_line(_p(0.3, 0.9), _p(0.7, 0.9), color, width * 0.9)
			draw_line(_p(0.5, 0.78), _p(0.5, 1.0), color, width * 0.9)
		_:
			for offset in [0.0, 0.28]:
				draw_polyline(PackedVector2Array([_p(0.2, 0.6 - offset), _p(0.5, 0.3 - offset), _p(0.8, 0.6 - offset)]), color, width)
