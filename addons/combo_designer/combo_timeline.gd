@tool
class_name ComboTimeline
extends Control
## Editable inclusive tick windows. Drag either endpoint; numeric fields remain available.
signal window_selected(index: int)
signal window_drag_started
signal window_dragged(start_tick: int, end_tick: int)
signal window_drag_finished(start_tick: int, end_tick: int)

const LEFT_MARGIN := 94.0
const RIGHT_MARGIN := 12.0
const LANE_Y := {"edge": 38.0, "DODGE": 66.0, "BLOCK_PARRY": 88.0, "SWITCH": 110.0, "JUMP": 132.0, "EXECUTE": 154.0, "hit": 176.0}
const LANE_COLOR := {"edge": Color("51a9e8"), "cancel": Color("e7a545"), "hit": Color("ee6379")}

var combo_node: ComboNode
var window_entries: Array[Dictionary] = []
var selected_index := -1
var _drag_handle := ""
var _drag_index := -1
var _drag_start := 0
var _drag_end := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func show_node(value: ComboNode) -> void:
	combo_node = value
	queue_redraw()

func set_windows(value: Array[Dictionary], selected: int) -> void:
	window_entries = value.duplicate(true)
	selected_index = selected if selected >= 0 and selected < window_entries.size() else -1
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	var left := LEFT_MARGIN
	var right := size.x - RIGHT_MARGIN
	var width := maxf(1.0, right - left)
	var duration := maxi(1, combo_node.duration_ticks if combo_node != null else 30)
	draw_rect(Rect2(Vector2(left, 10), Vector2(width, 190)), Color("202933"), true)
	for tick in range(duration + 1):
		var x := left + width * float(tick) / float(duration)
		var major := tick % 5 == 0
		draw_line(Vector2(x, 10), Vector2(x, 200 if major else 194), Color(0.55, 0.63, 0.7, 0.32), 1.0)
		if major:
			draw_string(font, Vector2(x + 2, 22), str(tick), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, Color(0.76, 0.82, 0.88))
	_draw_lane_label(font, font_size, "edge", "Link")
	_draw_lane_label(font, font_size, "DODGE", "Dodge")
	_draw_lane_label(font, font_size, "BLOCK_PARRY", "Block/Parry")
	_draw_lane_label(font, font_size, "SWITCH", "Switch")
	_draw_lane_label(font, font_size, "JUMP", "Jump")
	_draw_lane_label(font, font_size, "EXECUTE", "Execute")
	_draw_lane_label(font, font_size, "hit", "Hitbox")
	if combo_node == null:
		return
	for index in window_entries.size():
		var entry: Dictionary = window_entries[index]
		var kind := String(entry.get("kind", ""))
		var lane := String(entry.get("action", "")) if kind == "cancel" else kind
		var y := float(LANE_Y.get(lane, 38.0))
		var color: Color = LANE_COLOR.get(kind, Color.WHITE)
		var interval: Vector2i = entry.get("interval", Vector2i.ZERO)
		var alpha := 1.0 if index == selected_index else 0.58
		_draw_window(left, width, duration, interval, y, color * Color(1, 1, 1, alpha), String(entry.get("label", "")), index == selected_index)
		if kind == "hit":
			for refresh_tick in entry.get("refresh_ticks", PackedInt32Array()):
				if refresh_tick >= 0 and refresh_tick <= duration:
					var refresh_x := left + width * float(refresh_tick) / float(duration)
					draw_line(Vector2(refresh_x, y + 18), Vector2(refresh_x, y + 24), Color.WHITE, 2.0)
		if kind == "edge" and int(entry.get("dispatch_tick", -1)) >= 0:
			var dispatch_x := left + width * float(entry.dispatch_tick) / float(duration)
			draw_line(Vector2(dispatch_x, y - 3), Vector2(dispatch_x, y + 22), Color.WHITE, 1.0)
			draw_string(font, Vector2(dispatch_x + 2, y - 4), "D%d" % entry.dispatch_tick, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 3, Color.WHITE)
		if kind == "edge":
			var blend_x := left + width * float(interval.y + 1) / float(duration)
			draw_string(font, Vector2(blend_x + 2, y + 14), "B%d" % int(entry.get("blend_ticks", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 3, Color.WHITE)

func _draw_lane_label(font: Font, font_size: int, kind: String, label: String) -> void:
	draw_string(font, Vector2(10, float(LANE_Y[kind]) + 14), label, HORIZONTAL_ALIGNMENT_LEFT, 76, font_size, Color(0.78, 0.82, 0.87))

func _draw_window(left: float, width: float, duration: int, window: Vector2i, y: float, color: Color, label: String, selected: bool) -> void:
	var start := clampi(window.x, 0, duration - 1)
	var finish := clampi(window.y, start, duration - 1)
	var x0 := left + width * float(start) / float(duration)
	var x1 := left + width * float(finish + 1) / float(duration)
	draw_rect(Rect2(Vector2(x0, y), Vector2(maxf(5.0, x1 - x0), 19)), color, true)
	if selected:
		var handle_color := Color.WHITE
		draw_rect(Rect2(Vector2(x0 - 3, y - 2), Vector2(6, 23)), handle_color, true)
		draw_rect(Rect2(Vector2(x1 - 3, y - 2), Vector2(6, 23)), handle_color, true)
	draw_string(ThemeDB.fallback_font, Vector2(x0 + 4, y + 14), label, HORIZONTAL_ALIGNMENT_LEFT, maxf(8, x1 - x0 - 4), ThemeDB.fallback_font_size - 2, Color.WHITE)

func _gui_input(event: InputEvent) -> void:
	if combo_node == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := event as InputEventMouseButton
		if mouse.pressed:
			_begin_drag(mouse.position)
		elif _drag_index >= 0:
			var entry: Dictionary = window_entries[_drag_index]
			emit_signal("window_drag_finished", int(entry.interval.x), int(entry.interval.y))
			_drag_index = -1
			_drag_handle = ""
			accept_event()
	elif event is InputEventMouseMotion and _drag_index >= 0:
		_update_drag((event as InputEventMouseMotion).position.x)
		accept_event()

func _begin_drag(position: Vector2) -> void:
	var duration := maxi(1, combo_node.duration_ticks)
	var left := LEFT_MARGIN
	var width := maxf(1.0, size.x - LEFT_MARGIN - RIGHT_MARGIN)
	for index in range(window_entries.size() - 1, -1, -1):
		var entry: Dictionary = window_entries[index]
		var kind := String(entry.get("kind", ""))
		var lane := String(entry.get("action", "")) if kind == "cancel" else kind
		var y := float(LANE_Y.get(lane, -100.0))
		if position.y < y - 4 or position.y > y + 23:
			continue
		var interval: Vector2i = entry.get("interval", Vector2i.ZERO)
		var x0 := left + width * float(interval.x) / float(duration)
		var x1 := left + width * float(interval.y + 1) / float(duration)
		if position.x < x0 - 6 or position.x > x1 + 6:
			continue
		selected_index = index
		emit_signal("window_selected", index)
		var left_distance := absf(position.x - x0)
		var right_distance := absf(position.x - x1)
		if minf(left_distance, right_distance) <= 9.0:
			_drag_index = index
			_drag_handle = "start" if left_distance <= right_distance else "end"
			_drag_start = interval.x
			_drag_end = interval.y
			emit_signal("window_drag_started")
		accept_event()
		queue_redraw()
		return

func _update_drag(x: float) -> void:
	if _drag_index < 0 or combo_node == null:
		return
	var duration := maxi(1, combo_node.duration_ticks)
	var width := maxf(1.0, size.x - LEFT_MARGIN - RIGHT_MARGIN)
	var tick := clampi(roundi((x - LEFT_MARGIN) / width * duration), 0, duration - 1)
	if _drag_handle == "start":
		_drag_start = mini(tick, _drag_end)
	else:
		_drag_end = maxi(tick, _drag_start)
	var entry: Dictionary = window_entries[_drag_index]
	entry.interval = Vector2i(_drag_start, _drag_end)
	window_entries[_drag_index] = entry
	emit_signal("window_dragged", _drag_start, _drag_end)
	queue_redraw()
