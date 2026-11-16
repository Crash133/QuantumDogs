class_name CombatDecayEditor
extends VBoxContainer

var controller: CombatController
var apply_curve: Callable
var _weapon: OptionButton
var _node: OptionButton
var _spec: OptionButton
var _plot: Control
var _values: Array[SpinBox] = []
var _message: Label

func _ready() -> void:
	_weapon = _picker()
	_node = _picker()
	_spec = _picker()
	for weapon in controller.weapons:
		_weapon.add_item(weapon.display_name)
	_weapon.item_selected.connect(func(_index: int) -> void: _select_weapon())
	_node.item_selected.connect(func(_index: int) -> void: _select_node())
	_spec.item_selected.connect(func(_index: int) -> void: _load_values())
	_plot = Control.new()
	_plot.custom_minimum_size = Vector2(316.0, 65.0)
	_plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plot.draw.connect(_draw_plot)
	add_child(_plot)
	for index in range(5):
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		label.text = "%d%% trail age" % (index * 25)
		label.add_theme_font_size_override(&"font_size", 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var value := SpinBox.new()
		value.min_value = 0.0
		value.max_value = 1.0
		value.step = 0.05
		value.custom_minimum_size.x = 90.0
		value.get_line_edit().editable = index != 0
		value.editable = index != 0
		value.value_changed.connect(func(_number: float) -> void: _plot.queue_redraw())
		row.add_child(value)
		_values.append(value)
	var apply := Button.new()
	apply.text = "Apply 5-point curve (next attack)"
	apply.pressed.connect(_apply)
	add_child(apply)
	_message = Label.new()
	_message.add_theme_font_size_override(&"font_size", 11)
	add_child(_message)
	_select_weapon()

func _picker() -> OptionButton:
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(picker)
	return picker

func _select_weapon() -> void:
	_node.clear()
	var weapon := controller.weapons[_weapon.selected]
	for node in weapon.graph.nodes:
		_node.add_item(String(node.id))
	_select_node()

func _selected_node() -> ComboNode:
	return controller.weapons[_weapon.selected].graph.nodes[_node.selected]

func _select_node() -> void:
	_spec.clear()
	for spec in _selected_node().hit_specs:
		_spec.add_item("HitSpec %d · %s" % [_spec.item_count + 1, spec.profile])
	_load_values()

func _load_values() -> void:
	if _spec.item_count == 0:
		_message.text = "No HitSpec on this node."
		return
	var spec := _selected_node().hit_specs[_spec.selected]
	for index in range(_values.size()):
		var age := float(index) / 4.0
		_values[index].set_value_no_signal(1.0 - 0.7 * age if spec.decay == null else spec.decay.sample(age))
	_values[0].set_value_no_signal(1.0)
	_message.text = "Age 0 → 100% · linear knots · session edits only"
	_plot.queue_redraw()

func _samples() -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for value in _values:
		samples.append(value.value)
	return samples

func _apply() -> void:
	if _spec.item_count == 0:
		return
	var applied: bool = apply_curve.call(_weapon.selected, _selected_node().id, _spec.selected, _samples())
	_message.text = "Applied · native table bakes on next attack" if applied else "Invalid curve or selection"

func _draw_plot() -> void:
	var bounds := Rect2(Vector2(4.0, 4.0), _plot.size - Vector2(8.0, 8.0))
	_plot.draw_rect(bounds, Color(0.1, 0.15, 0.2))
	for level in [0.0, 0.5, 1.0]:
		var y: float = bounds.end.y - bounds.size.y * float(level)
		_plot.draw_line(Vector2(bounds.position.x, y), Vector2(bounds.end.x, y), Color(0.25, 0.3, 0.35))
	var points := PackedVector2Array()
	for index in range(_values.size()):
		points.append(Vector2(bounds.position.x + bounds.size.x * float(index) / 4.0, bounds.end.y - bounds.size.y * _values[index].value))
	if points.size() > 1:
		_plot.draw_polyline(points, Color.CYAN, 2.0, true)
	for point in points:
		_plot.draw_circle(point, 3.0, Color.WHITE)
