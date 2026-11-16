class_name RevolverChamber
extends Control

## Procedural revolver cylinder for the HUD. Following the ammo count: each
## shot spends the round at the top, spins the cylinder one step clockwise and
## the round flies out; auto-reload spins it back one step counter-clockwise
## and a new round pops into the emptied chamber. Pure drawing, no gameplay.

@export var body_color: Color = Color(0.28, 0.36, 0.48)
@export var outline_color: Color = Color(0.04, 0.05, 0.09)
## Classic brass cartridges with a silver bullet.
@export var case_color: Color = Color(0.96, 0.78, 0.22)
@export var bullet_color: Color = Color(0.78, 0.8, 0.82)
@export var spin_seconds: float = 0.12

var capacity: int = 6
var _filled: Array[bool] = []
var _scale: Array[float] = []      # 0..1 pop-in per chamber
var _head: int = 0                 # unwrapped step count; chamber at top is posmod(_head, capacity)
var _head_f: float = 0.0           # animated head
var _count: int = -1
var _ejected: Array[Dictionary] = []  # {angle, age}
const EJECT_SECONDS := 0.35

func set_ammo(current: int, new_capacity: int) -> void:
	if new_capacity < 1:
		return
	if new_capacity != capacity or _count < 0:
		_reset(current, new_capacity)
		return
	while _count > current:
		_fire()
	while _count < current:
		_reload()
	queue_redraw()

func _reset(current: int, new_capacity: int) -> void:
	capacity = new_capacity
	_count = clampi(current, 0, capacity)
	_filled.clear()
	_scale.clear()
	for _i in range(capacity):
		_filled.append(true)
		_scale.append(1.0)
	# After k shots the spent chambers sit just past the head.
	_head = posmod(-(capacity - _count), capacity)
	_head_f = float(_head)
	for j in range(capacity - _count):
		_filled[posmod(_head + j + 1, capacity)] = false
	_ejected.clear()
	queue_redraw()

func _fire() -> void:
	var slot := posmod(_head, capacity)
	if _filled[slot]:
		_ejected.append({"angle": (float(slot) - _head_f) * TAU / float(capacity), "age": 0.0})
	_filled[slot] = false
	_head -= 1
	_count -= 1

func _reload() -> void:
	_head += 1
	var slot := posmod(_head, capacity)
	_filled[slot] = true
	_scale[slot] = 0.0
	_count += 1

func _process(delta: float) -> void:
	if _filled.size() != capacity:
		return # No ammo reported yet.
	var moving := not is_equal_approx(_head_f, float(_head)) or not _ejected.is_empty()
	for index in range(capacity):
		if _scale[index] < 1.0:
			_scale[index] = minf(1.0, _scale[index] + delta / maxf(0.01, spin_seconds * 2.0))
			moving = true
	_head_f = move_toward(_head_f, float(_head), delta / maxf(0.01, spin_seconds))
	for entry in _ejected:
		entry.age += delta
	_ejected = _ejected.filter(func(e: Dictionary) -> bool: return e.age < EJECT_SECONDS)
	if moving:
		queue_redraw()

func _draw() -> void:
	if capacity < 1 or _filled.size() != capacity:
		return
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	var step := TAU / float(capacity)
	# Body: scalloped disc. Flutes sit between chambers and turn with the cylinder.
	draw_set_transform(center, -_head_f * step, Vector2.ONE)
	var rim := PackedVector2Array()
	var outer := PackedVector2Array()
	for point in range(96):
		var phi := TAU * float(point) / 96.0
		var flute := 1.0 - smoothstep(-1.0, 0.3, cos(float(capacity) * phi))
		var r := radius - radius * 0.14 * flute
		rim.append(Vector2(sin(phi), -cos(phi)) * r)
		outer.append(Vector2(sin(phi), -cos(phi)) * (r + 3.0))
	draw_colored_polygon(outer, outline_color)
	draw_colored_polygon(rim, body_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ring := radius * 0.64
	var case_r := radius * 0.27
	for slot in range(capacity):
		var angle := (float(slot) - _head_f) * step
		var at := center + Vector2(sin(angle), -cos(angle)) * ring
		if _filled[slot]:
			var pop := _scale[slot]
			draw_circle(at, case_r * pop + 2.0, outline_color)
			draw_circle(at, case_r * pop, case_color)
			draw_circle(at, case_r * 0.62 * pop, bullet_color)
			# Primer: dead centre of the case.
			draw_circle(at, case_r * 0.22 * pop, Color(1, 1, 1, 0.9))
		else:
			draw_circle(at, case_r + 2.0, outline_color)
			draw_circle(at, case_r, Color(0.07, 0.09, 0.14))
	for entry in _ejected:
		var angle: float = entry.angle
		var age: float = entry.age / EJECT_SECONDS
		var from := center + Vector2(sin(angle), -cos(angle)) * ring
		var at: Vector2 = from + Vector2(0.9, -1.0).normalized() * radius * 1.1 * age
		draw_circle(at, case_r * (1.0 - 0.5 * age), Color(case_color, 1.0 - age))
	# Hub with the round count, and the firing marker at the top.
	draw_circle(center, radius * 0.3 + 2.0, outline_color)
	draw_circle(center, radius * 0.3, Color(0.09, 0.11, 0.17))
	var font := get_theme_default_font()
	var font_size := int(radius * 0.36)
	var text := str(maxi(_count, 0))
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, center + Vector2(-text_size.x * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.85, 0.93, 1.0))
	draw_colored_polygon(PackedVector2Array([Vector2(center.x - 7.0, 1.0), Vector2(center.x + 7.0, 1.0), Vector2(center.x, 11.0)]), case_color)
