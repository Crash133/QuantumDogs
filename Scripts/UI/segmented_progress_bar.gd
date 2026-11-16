class_name SegmentedProgressBar
extends ProgressBar

## ProgressBar drawn as separate segments (the Heat bar). Each segment fills in
## turn; theme styleboxes are suppressed so only the segments show.

@export_range(1, 20) var segments: int = 5
@export var gap: float = 6.0
@export var fill_color: Color = Color(0.25, 0.9, 1.0)
## Optional: each segment takes the colour at its position along the gradient.
@export var fill_gradient: Gradient
@export var empty_color: Color = Color(0.12, 0.14, 0.2, 0.7)

func _ready() -> void:
	show_percentage = false
	add_theme_stylebox_override(&"background", StyleBoxEmpty.new())
	add_theme_stylebox_override(&"fill", StyleBoxEmpty.new())

func _draw() -> void:
	var count := maxi(1, segments)
	var width := (size.x - gap * float(count - 1)) / float(count)
	var span := max_value - min_value
	var ratio := 0.0 if span <= 0.0 else clampf((value - min_value) / span, 0.0, 1.0)
	for index in range(count):
		var left := float(index) * (width + gap)
		draw_rect(Rect2(left, 0.0, width, size.y), empty_color)
		var filled := clampf(ratio * float(count) - float(index), 0.0, 1.0)
		if filled > 0.0:
			var color := fill_gradient.sample((float(index) + 0.5) / float(count)) if fill_gradient != null else fill_color
			draw_rect(Rect2(left, 0.0, width * filled, size.y), color)
