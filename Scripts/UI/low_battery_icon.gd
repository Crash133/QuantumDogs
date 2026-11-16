class_name LowBatteryIcon
extends Control

## Warning glyph: an almost empty battery with a bolt. The presenter shows and
## blinks it only while Battery is low.

@export var warning_color: Color = Color(0.93, 0.27, 0.27)
@export var outline_color: Color = Color(0.13, 0.13, 0.14)

func _draw() -> void:
	var nub := size.x * 0.07
	var body := Rect2(Vector2.ZERO, Vector2(size.x - nub, size.y))
	draw_rect(body, outline_color)
	var inner := body.grow(-size.y * 0.07)
	draw_rect(inner, Color.WHITE)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * 0.12, inner.size.y)), warning_color)
	draw_rect(Rect2(body.end.x, size.y * 0.3, nub, size.y * 0.4), outline_color)
	var bolt := PackedVector2Array()
	for unit in [Vector2(0.18, 0.58), Vector2(0.5, 0.26), Vector2(0.5, 0.43), Vector2(0.84, 0.4), Vector2(0.5, 0.74), Vector2(0.5, 0.57)]:
		bolt.append(inner.position + unit * inner.size)
	draw_colored_polygon(bolt, warning_color)
