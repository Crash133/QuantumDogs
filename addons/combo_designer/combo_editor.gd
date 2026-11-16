@tool
class_name ComboEditor
extends Control

const LAYOUT_SCRIPT: Script = preload("res://addons/combo_designer/combo_graph_layout.gd")

@onready var canvas: ComboGraphCanvas = %GraphCanvas
@onready var graph_path: LineEdit = %GraphPath
@onready var selected_name: LineEdit = %SelectedName
@onready var selected_animation: LineEdit = %SelectedAnimation
@onready var duration: SpinBox = %DurationTicks
@onready var clip_start: SpinBox = %ClipStartSeconds
@onready var clip_end: SpinBox = %ClipEndSeconds
@onready var inspector_button: Button = %OpenInspector
@onready var window_kind: OptionButton = %WindowKind
@onready var window_start: SpinBox = %WindowStart
@onready var window_end: SpinBox = %WindowEnd
@onready var window_start_seconds: Label = %WindowStartSeconds
@onready var window_end_seconds: Label = %WindowEndSeconds
@onready var dispatch_mode: OptionButton = %DispatchMode
@onready var dispatch_tick: SpinBox = %DispatchTick
@onready var blend_ticks: SpinBox = %BlendTicks
@onready var timeline: ComboTimeline = %Timeline
@onready var validation: RichTextLabel = %Validation
@onready var preview: ComboPreview = %Preview
@onready var file_dialog: FileDialog = %ResourceDialog

var _editor_interface: EditorInterface
var _history: Object
var _commands := ComboEditCommands.new()
var _graph: ComboGraph
var _weapon: WeaponData
var _layout: ComboGraphLayout
var _selected_node: ComboNode
var _window_entries: Array[Dictionary] = []
var _loading_ui: bool = false
var _save_as_pending: bool = false
var _drag_window_before: Dictionary = {}
var _validation_edge_targets: Array[Dictionary] = []

## Normalize every standalone combo graph path to the dedicated `.combo.tres` suffix.
static func combo_resource_path(path: String) -> String:
	var normalized := path.strip_edges()
	if normalized.is_empty():
		return normalized
	var lowercase_path := normalized.to_lower()
	if lowercase_path.ends_with(".combo.tres"):
		return normalized
	if lowercase_path.ends_with(".tres"):
		return normalized.left(normalized.length() - 5) + ".combo.tres"
	var extension := normalized.get_extension()
	if not extension.is_empty():
		normalized = normalized.left(normalized.length() - extension.length() - 1)
	return normalized.trim_suffix(".") + ".combo.tres"

## Layouts for standalone graphs share their graph stem; WeaponData keeps its legacy companion name.
static func combo_layout_path(source: String) -> String:
	if source.to_lower().ends_with(".combo.tres"):
		return source.left(source.length() - 5) + "_layout.tres"
	return source.get_basename() + "_combo_layout.tres"

func _ready() -> void:
	_bind_ui()
	if _editor_interface != null:
		canvas.configure(_editor_interface, _history)

func configure(editor: EditorInterface, history: Object) -> void:
	_editor_interface = editor
	_history = history
	_connect_history()
	if is_inside_tree():
		canvas.configure(_editor_interface, _history)

## Open a standalone graph without changing any weapon's assignment.
func edit_graph(graph: ComboGraph, weapon: WeaponData = null) -> void:
	_weapon = weapon
	_graph = graph
	_selected_node = null
	if graph == null:
		validation.text = "No ComboGraph is assigned."
		return
	_load_layout()
	canvas.show_graph(_graph, _layout)
	graph_path.text = _weapon.resource_path if _weapon != null else _graph.resource_path
	_refresh_validation()
	_update_selection_ui()
	if _weapon != null:
		preview.load_copy(_weapon)

func edit_weapon(weapon: WeaponData) -> void:
	if weapon == null:
		return
	_weapon = weapon
	edit_graph(weapon.graph, weapon)

func validate_graph() -> Array[String]:
	var errors: Array[String] = []
	if _graph == null:
		errors.append("No ComboGraph is assigned.")
		return errors
	if _weapon != null:
		errors.append_array(_weapon.validate())
		_append_rig_validation(errors)
	else:
		errors.append_array(_graph.validate())
	return errors

func _bind_ui() -> void:
	_connect_history()
	if dispatch_mode.item_count == 0:
		dispatch_mode.add_item("Immediate", ComboEdge.TransitionMode.IMMEDIATE)
		dispatch_mode.add_item("At tick", ComboEdge.TransitionMode.AT_TICK)
	if not %OpenResource.pressed.is_connected(_on_open_resource):
		%OpenResource.pressed.connect(_on_open_resource)
	if not %NewGraph.pressed.is_connected(_on_new_graph):
		%NewGraph.pressed.connect(_on_new_graph)
	if not %SaveResource.pressed.is_connected(_on_save_resource):
		%SaveResource.pressed.connect(_on_save_resource)
	if not %SaveAsResource.pressed.is_connected(_on_save_as_resource):
		%SaveAsResource.pressed.connect(_on_save_as_resource)
	if not %ChooseResource.pressed.is_connected(_on_choose_resource):
		%ChooseResource.pressed.connect(_on_choose_resource)
	if not %AddAttack.pressed.is_connected(_on_add_attack):
		%AddAttack.pressed.connect(_on_add_attack)
	if not %DuplicateAttack.pressed.is_connected(_on_duplicate_attack):
		%DuplicateAttack.pressed.connect(_on_duplicate_attack)
	if not %DeleteAttack.pressed.is_connected(_on_delete_attack):
		%DeleteAttack.pressed.connect(_on_delete_attack)
	if not %MigrateLegacy.pressed.is_connected(_on_migrate_legacy):
		%MigrateLegacy.pressed.connect(_on_migrate_legacy)
	if not inspector_button.pressed.is_connected(_on_open_inspector):
		inspector_button.pressed.connect(_on_open_inspector)
	if not canvas.attack_selected.is_connected(_on_attack_selected):
		canvas.attack_selected.connect(_on_attack_selected)
	if not canvas.graph_changed.is_connected(_refresh_validation):
		canvas.graph_changed.connect(_refresh_validation)
	if not timeline.window_selected.is_connected(_on_timeline_window_selected):
		timeline.window_selected.connect(_on_timeline_window_selected)
	if not timeline.window_drag_started.is_connected(_on_timeline_window_change_started):
		timeline.window_drag_started.connect(_on_timeline_window_change_started)
	if not timeline.window_dragged.is_connected(_on_timeline_window_changed):
		timeline.window_dragged.connect(_on_timeline_window_changed)
	if not timeline.window_drag_finished.is_connected(_on_timeline_window_change_finished):
		timeline.window_drag_finished.connect(_on_timeline_window_change_finished)
	if not selected_name.text_submitted.is_connected(_on_name_submitted):
		selected_name.text_submitted.connect(_on_name_submitted)
	if not selected_animation.text_submitted.is_connected(_on_animation_submitted):
		selected_animation.text_submitted.connect(_on_animation_submitted)
	if not duration.value_changed.is_connected(_on_duration_changed):
		duration.value_changed.connect(_on_duration_changed)
	if not clip_start.value_changed.is_connected(_on_clip_start_changed):
		clip_start.value_changed.connect(_on_clip_start_changed)
	if not clip_end.value_changed.is_connected(_on_clip_end_changed):
		clip_end.value_changed.connect(_on_clip_end_changed)
	if not window_kind.item_selected.is_connected(_on_window_kind_selected):
		window_kind.item_selected.connect(_on_window_kind_selected)
	if not window_start.value_changed.is_connected(_on_window_value_changed.bind(true)):
		window_start.value_changed.connect(_on_window_value_changed.bind(true))
	if not window_end.value_changed.is_connected(_on_window_value_changed.bind(false)):
		window_end.value_changed.connect(_on_window_value_changed.bind(false))
	if not dispatch_mode.item_selected.is_connected(_on_dispatch_mode_selected):
		dispatch_mode.item_selected.connect(_on_dispatch_mode_selected)
	if not dispatch_tick.value_changed.is_connected(_on_dispatch_tick_changed):
		dispatch_tick.value_changed.connect(_on_dispatch_tick_changed)
	if not blend_ticks.value_changed.is_connected(_on_blend_ticks_changed):
		blend_ticks.value_changed.connect(_on_blend_ticks_changed)
	if not file_dialog.file_selected.is_connected(_on_resource_file_selected):
		file_dialog.file_selected.connect(_on_resource_file_selected)
	if not file_dialog.canceled.is_connected(_on_resource_dialog_canceled):
		file_dialog.canceled.connect(_on_resource_dialog_canceled)
	if not validation.meta_clicked.is_connected(_on_validation_meta_clicked):
		validation.meta_clicked.connect(_on_validation_meta_clicked)

func _on_choose_resource() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.popup_centered_ratio(0.7)

func _on_resource_file_selected(path: String) -> void:
	if _save_as_pending:
		_save_as_pending = false
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_save_graph_as(path)
		return
	graph_path.text = path
	_load_resource_path(path)

func _on_open_resource() -> void:
	_load_resource_path(graph_path.text.strip_edges())

func _load_resource_path(path: String) -> void:
	if path.is_empty():
		return
	var resource := load(path)
	if resource is WeaponData:
		edit_weapon(resource as WeaponData)
	elif resource is ComboGraph:
		edit_graph(resource as ComboGraph)
	else:
		validation.text = "Select a WeaponData or ComboGraph Resource."

func _on_save_resource() -> void:
	if _graph == null:
		return
	var save_resource: Resource = _weapon if _weapon != null else _graph
	var path := save_resource.resource_path
	if path.is_empty() or path.contains("::"):
		validation.text = "Use Save As to create an external .tres for this graph."
		return
	var error := ResourceSaver.save(save_resource, path)
	if error != OK:
		validation.text = "Save failed (%d): %s" % [error, path]
		return
	_save_layout()
	validation.text = "Saved %s" % path
	if _editor_interface != null:
		_editor_interface.get_resource_filesystem().scan()

func _on_new_graph() -> void:
	var graph := ComboGraph.new()
	graph.schema_version = ComboGraph.CURRENT_SCHEMA_VERSION
	if _weapon != null:
		_commands.set_resource_property(_history, _weapon, &"graph", graph)
	edit_graph(graph, _weapon)
	validation.text = "Created a new versioned graph. Add attacks and Rest light/heavy links, then save."

func _on_save_as_resource() -> void:
	if _graph == null:
		return
	_save_as_pending = true
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = "%s.combo.tres" % (_weapon.id if _weapon != null else "combo_graph")
	file_dialog.popup_centered_ratio(0.7)

func _on_resource_dialog_canceled() -> void:
	_save_as_pending = false
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE

func _save_graph_as(path: String) -> void:
	path = combo_resource_path(path)
	if path.is_empty():
		return
	var error := ResourceSaver.save(_graph, path)
	if error != OK:
		validation.text = "Save failed (%d): %s" % [error, path]
		return
	_graph.resource_path = path
	if _weapon != null:
		_commands.set_resource_property(_history, _weapon, &"graph", _graph)
		if not _weapon.resource_path.is_empty():
			var weapon_error := ResourceSaver.save(_weapon, _weapon.resource_path)
			if weapon_error != OK:
				validation.text = "Graph saved, but owning WeaponData save failed (%d)." % weapon_error
				return
	graph_path.text = path
	_save_layout()
	validation.text = "Saved graph %s" % path
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE

func _on_add_attack() -> void:
	if _graph == null:
		return
	var name := String(%NewAttackName.text).strip_edges()
	var animation := StringName(%NewAttackAnimation.text.strip_edges())
	if name.is_empty() or animation == &"":
		validation.text = "Enter an attack name and supplied animation clip before adding a node."
		return
	var created := canvas.add_attack(name, animation)
	if created != null:
		_on_attack_selected(created.id)
		_refresh_validation()

func _on_delete_attack() -> void:
	if _selected_node == null:
		return
	_commands.delete_node(_history, _graph, _selected_node.id)
	_selected_node = null
	canvas.show_graph(_graph, _layout)
	_update_selection_ui()
	_refresh_validation()

func _on_duplicate_attack() -> void:
	if _selected_node == null:
		return
	var duplicate := canvas.duplicate_attack(_selected_node.id)
	if duplicate != null:
		_on_attack_selected(duplicate.id)
		_refresh_validation()

func _on_migrate_legacy() -> void:
	if _graph == null or _graph.schema_version != 0:
		return
	var result := ComboGraphMigration.migrate_copy(_graph)
	var errors: PackedStringArray = result.errors
	if not errors.is_empty():
		validation.text = "Migration has %d issue(s):\n• %s" % [errors.size(), "\n• ".join(errors)]
		return
	var migrated := result.graph as ComboGraph
	if migrated == null:
		validation.text = "Migration did not produce a ComboGraph copy."
		return
	if _weapon != null:
		_commands.set_resource_property(_history, _weapon, &"graph", migrated)
	edit_graph(migrated, _weapon)
	var changes: PackedStringArray = result.changes
	validation.text = "Migrated a copy; source graph was not edited.\n• %s" % "\n• ".join(changes)

func _on_attack_selected(node_id: StringName) -> void:
	_selected_node = _graph.get_node(node_id) if _graph != null else null
	_update_selection_ui()

func _update_selection_ui() -> void:
	_loading_ui = true
	var has_node := _selected_node != null
	selected_name.editable = has_node
	selected_animation.editable = has_node
	duration.editable = has_node
	clip_start.editable = has_node
	clip_end.editable = has_node
	inspector_button.disabled = not has_node
	%DeleteAttack.disabled = not has_node
	%DuplicateAttack.disabled = not has_node
	%MigrateLegacy.disabled = _graph == null or _graph.schema_version != 0
	selected_name.text = _selected_node.display_name if has_node else ""
	selected_animation.text = String(_selected_node.animation) if has_node else ""
	duration.value = _selected_node.duration_ticks if has_node else 30
	clip_start.value = _selected_node.clip_start_seconds if has_node else 0.0
	clip_end.value = _selected_node.clip_end_seconds if has_node else -1.0
	_loading_ui = false
	_rebuild_window_options()

func _on_open_inspector() -> void:
	if _editor_interface != null and _selected_node != null:
		_editor_interface.edit_resource(_selected_node)

func _on_name_submitted(value: String) -> void:
	if not _loading_ui and _selected_node != null:
		_commands.set_resource_property(_history, _selected_node, &"display_name", value.strip_edges())
		canvas.show_graph(_graph, _layout)
		_refresh_validation()

func _on_animation_submitted(value: String) -> void:
	if not _loading_ui and _selected_node != null:
		_commands.set_resource_property(_history, _selected_node, &"animation", StringName(value.strip_edges()))
		_refresh_validation()

func _on_duration_changed(value: float) -> void:
	if _loading_ui or _selected_node == null:
		return
	var new_value := maxi(1, int(value))
	_commands.set_resource_property(_history, _selected_node, &"duration_ticks", new_value)
	_rebuild_window_options()
	timeline.show_node(_selected_node)
	_refresh_validation()

func _on_clip_start_changed(value: float) -> void:
	if _loading_ui or _selected_node == null:
		return
	_commands.set_resource_property(_history, _selected_node, &"clip_start_seconds", maxf(0.0, value))
	_refresh_validation()

func _on_clip_end_changed(value: float) -> void:
	if _loading_ui or _selected_node == null:
		return
	_commands.set_resource_property(_history, _selected_node, &"clip_end_seconds", value)
	_refresh_validation()

func _rebuild_window_options() -> void:
	var previously_selected: Dictionary = _window_entries[window_kind.selected] if window_kind.selected >= 0 and window_kind.selected < _window_entries.size() else {}
	window_kind.clear()
	_window_entries.clear()
	if _selected_node == null:
		window_start.editable = false
		window_end.editable = false
		return
	for index in _selected_node.edges.size():
		var edge := _selected_node.edges[index]
		if edge != null:
			_add_window_entry("Link %s → %s" % [edge.input, edge.target], {"kind": "edge", "index": index})
	for index in _selected_node.cancel_windows.size():
		var cancel := _selected_node.cancel_windows[index]
		if cancel != null:
			var cancel_action: String = ComboCancelWindow.Action.keys()[cancel.action]
			_add_window_entry("Cancel %s" % cancel_action, {"kind": "cancel", "action": cancel_action, "index": index})
	for spec_index in _selected_node.hit_specs.size():
		var spec := _selected_node.hit_specs[spec_index]
		if spec == null:
			continue
		for window_index in spec.resolved_active_windows().size():
			_add_window_entry("Hitbox %d window %d" % [spec_index + 1, window_index + 1], {"kind": "hit", "index": spec_index, "window": window_index, "refresh_ticks": spec.refresh_ticks})
	window_start.editable = not _window_entries.is_empty()
	window_end.editable = not _window_entries.is_empty()
	if not _window_entries.is_empty():
		var selection := 0
		for index in _window_entries.size():
			if _window_entries[index] == previously_selected:
				selection = index
				break
		window_kind.select(selection)
		_on_window_kind_selected(selection)
	else:
		dispatch_mode.disabled = true
		dispatch_tick.editable = false
		blend_ticks.editable = false
		timeline.show_node(_selected_node)
		timeline.set_windows([], -1)

func _add_window_entry(label: String, metadata: Dictionary) -> void:
	window_kind.add_item(label)
	window_kind.set_item_metadata(window_kind.item_count - 1, metadata)
	_window_entries.append(metadata)

func _on_window_kind_selected(index: int) -> void:
	if _loading_ui or _selected_node == null or index < 0 or index >= _window_entries.size():
		return
	var entry: Dictionary = _window_entries[index]
	var window := _read_window(entry)
	_loading_ui = true
	window_start.max_value = maxf(0.0, float(_selected_node.duration_ticks - 1))
	window_end.max_value = maxf(0.0, float(_selected_node.duration_ticks - 1))
	window_start.value = window.x
	window_end.value = window.y
	_update_window_seconds(window.x, window.y)
	var is_edge: bool = entry.kind == "edge"
	dispatch_mode.disabled = not is_edge
	dispatch_tick.editable = is_edge
	blend_ticks.editable = is_edge
	if is_edge:
		var edge: ComboEdge = _selected_node.edges[entry.index]
		dispatch_mode.select(edge.transition_mode)
		dispatch_tick.value = maxi(0, edge.transition_tick)
		blend_ticks.value = edge.blend_ticks
		dispatch_tick.editable = edge.transition_mode == ComboEdge.TransitionMode.AT_TICK
	_loading_ui = false
	_refresh_timeline()

func _on_window_value_changed(_value: float, edit_start: bool) -> void:
	if _loading_ui or _selected_node == null or window_kind.selected < 0:
		return
	var entry: Dictionary = _window_entries[window_kind.selected]
	var start := clampi(int(window_start.value), 0, _selected_node.duration_ticks - 1)
	var finish := clampi(int(window_end.value), start, _selected_node.duration_ticks - 1)
	_loading_ui = true
	window_start.value = start
	window_end.value = finish
	_loading_ui = false
	_update_window_seconds(start, finish)
	var interval := Vector2i(start, finish)
	_apply_window_interval(entry, interval, edit_start)
	_refresh_timeline()
	_refresh_validation()

func _on_timeline_window_selected(index: int) -> void:
	if index < 0 or index >= window_kind.item_count:
		return
	window_kind.select(index)
	_on_window_kind_selected(index)

func _on_timeline_window_change_started() -> void:
	_drag_window_before.clear()
	if window_kind.selected < 0 or window_kind.selected >= _window_entries.size():
		return
	var entry: Dictionary = _window_entries[window_kind.selected]
	_drag_window_before = _window_binding(entry)

func _on_timeline_window_changed(start_tick: int, end_tick: int) -> void:
	if window_kind.selected < 0 or window_kind.selected >= _window_entries.size():
		return
	var interval := Vector2i(start_tick, end_tick)
	var entry: Dictionary = _window_entries[window_kind.selected]
	_apply_window_interval(entry, interval, true)
	_loading_ui = true
	window_start.value = interval.x
	window_end.value = interval.y
	_loading_ui = false
	_update_window_seconds(interval.x, interval.y)
	_refresh_timeline()
	_refresh_validation()

func _on_timeline_window_change_finished(start_tick: int, end_tick: int) -> void:
	if _drag_window_before.is_empty() or _history == null or window_kind.selected < 0 or window_kind.selected >= _window_entries.size():
		_drag_window_before.clear()
		return
	var entry: Dictionary = _window_entries[window_kind.selected]
	var binding := _window_binding(entry)
	var before: Dictionary = _drag_window_before.duplicate(true)
	_drag_window_before.clear()
	var unchanged: bool = before["resource"] == binding["resource"] and before["property"] == binding["property"] and before["value"] == binding["value"]
	unchanged = unchanged and before.get("end_value") == binding.get("end_value")
	if unchanged:
		return
	_history.create_action("Edit combo timing window")
	_history.add_do_property(binding["resource"], binding["property"], binding["value"])
	_history.add_undo_property(before["resource"], before["property"], before["value"])
	if binding.has("end_property"):
		_history.add_do_property(binding["end_resource"], binding["end_property"], binding["end_value"])
		_history.add_undo_property(before["end_resource"], before["end_property"], before["end_value"])
	_history.commit_action()
	_on_timeline_window_changed(start_tick, end_tick)

func _apply_window_interval(entry: Dictionary, interval: Vector2i, edit_start: bool) -> void:
	match entry.kind:
		"edge":
			var edge: ComboEdge = _selected_node.edges[entry.index]
			edge.input_window = interval
		"cancel":
			var cancel: ComboCancelWindow = _selected_node.cancel_windows[entry.index]
			cancel.start_tick = interval.x
			cancel.end_tick = interval.y
		"hit":
			var spec: HitSpec = _selected_node.hit_specs[entry.index]
			var windows := spec.resolved_active_windows()
			windows[entry.window] = interval
			spec.active_windows = windows

func _window_binding(entry: Dictionary) -> Dictionary:
	match entry.kind:
		"edge":
			var edge: ComboEdge = _selected_node.edges[entry.index]
			return {"resource": edge, "property": &"input_window", "value": edge.input_window}
		"cancel":
			var cancel: ComboCancelWindow = _selected_node.cancel_windows[entry.index]
			return {"resource": cancel, "property": &"start_tick", "value": cancel.start_tick, "end_resource": cancel, "end_property": &"end_tick", "end_value": cancel.end_tick}
		"hit":
			var spec: HitSpec = _selected_node.hit_specs[entry.index]
			return {"resource": spec, "property": &"active_windows", "value": spec.active_windows.duplicate()}
	return {}

func _refresh_timeline() -> void:
	var intervals: Array[Dictionary] = []
	for index in _window_entries.size():
		var entry: Dictionary = _window_entries[index].duplicate()
		entry.interval = _read_window(entry)
		if entry.kind == "edge":
			var edge: ComboEdge = _selected_node.edges[entry.index]
			entry.dispatch_tick = edge.transition_tick if edge.transition_mode == ComboEdge.TransitionMode.AT_TICK else -1
			entry.blend_ticks = edge.blend_ticks
		intervals.append(entry)
	timeline.show_node(_selected_node)
	timeline.set_windows(intervals, window_kind.selected)

func _update_window_seconds(start_tick: int, end_tick: int) -> void:
	window_start_seconds.text = "%.3f s" % (float(start_tick) / 60.0)
	window_end_seconds.text = "%.3f s" % (float(end_tick) / 60.0)

func _connect_history() -> void:
	if _history != null and _history.has_signal("version_changed"):
		var callback := Callable(self, "_on_history_version_changed")
		if not _history.is_connected("version_changed", callback):
			_history.connect("version_changed", callback)

func _on_history_version_changed(_history_id: StringName = &"") -> void:
	if _graph == null:
		return
	var selected_id := _selected_node.id if _selected_node != null else &""
	_selected_node = _graph.get_node(selected_id) if selected_id != &"" else null
	canvas.show_graph(_graph, _layout)
	_loading_ui = true
	_update_selection_ui()
	_loading_ui = false
	_refresh_validation()

func _on_dispatch_mode_selected(index: int) -> void:
	var edge := _selected_edge()
	if edge == null or _loading_ui:
		return
	_commands.set_resource_property(_history, edge, &"transition_mode", index)
	dispatch_tick.editable = index == ComboEdge.TransitionMode.AT_TICK
	_refresh_validation()

func _on_dispatch_tick_changed(value: float) -> void:
	var edge := _selected_edge()
	if edge == null or _loading_ui:
		return
	_commands.set_resource_property(_history, edge, &"transition_tick", int(value))
	_refresh_validation()

func _on_blend_ticks_changed(value: float) -> void:
	var edge := _selected_edge()
	if edge == null or _loading_ui:
		return
	_commands.set_resource_property(_history, edge, &"blend_ticks", int(value))

func _selected_edge() -> ComboEdge:
	if _selected_node == null or window_kind.selected < 0 or window_kind.selected >= _window_entries.size():
		return null
	var entry: Dictionary = _window_entries[window_kind.selected]
	return _selected_node.edges[entry.index] as ComboEdge if entry.kind == "edge" else null

func _read_window(entry: Dictionary) -> Vector2i:
	match entry.kind:
		"edge":
			var edge: ComboEdge = _selected_node.edges[entry.index]
			return edge.input_window if edge.input_window.x >= 0 else _selected_node.input_window
		"cancel":
			var cancel: ComboCancelWindow = _selected_node.cancel_windows[entry.index]
			return Vector2i(cancel.start_tick, cancel.end_tick)
		"hit":
			var spec: HitSpec = _selected_node.hit_specs[entry.index]
			var windows := spec.resolved_active_windows()
			return windows[entry.window]
	return Vector2i.ZERO

func _append_rig_validation(errors: Array[String]) -> void:
	if _weapon == null:
		return
	if _weapon.character_scene == null:
		errors.append("Weapon %s has no character rig assigned; choose a character_scene with an AnimationPlayer." % _weapon.id)
		return
	var rig := _weapon.character_scene.instantiate()
	if rig == null:
		errors.append("Weapon %s character_scene could not be instantiated for preview." % _weapon.id)
		return
	var players := rig.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		errors.append("Weapon %s character rig has no AnimationPlayer." % _weapon.id)
	else:
		var player := players[0] as AnimationPlayer
		for combo_node in _graph.nodes:
			if combo_node == null:
				continue
			var clip: StringName = _weapon.animation_aliases.get(combo_node.animation, combo_node.animation)
			if not player.has_animation(clip):
				errors.append("Node %s references missing animation clip '%s' on the configured character rig." % [combo_node.id, clip])
			else:
				var animation := player.get_animation(clip)
				if combo_node.clip_start_seconds >= animation.length:
					errors.append("Node %s clip start %.3f s is outside animation '%s' (%.3f s)." % [combo_node.id, combo_node.clip_start_seconds, clip, animation.length])
				if combo_node.clip_end_seconds >= 0.0 and combo_node.clip_end_seconds > animation.length:
					errors.append("Node %s clip end %.3f s exceeds animation '%s' (%.3f s)." % [combo_node.id, combo_node.clip_end_seconds, clip, animation.length])
	var skeletons := rig.find_children("*", "Skeleton3D", true, false)
	if _weapon.character_unit_bones.is_empty() and _weapon.character_weapon_bone != &"":
		if not _rig_has_bone(skeletons, _weapon.character_weapon_bone):
			errors.append("Weapon %s hand bone '%s' was not found on its character rig." % [_weapon.id, _weapon.character_weapon_bone])
	else:
		for unit_id: StringName in _weapon.character_unit_bones:
			if not _rig_has_bone(skeletons, _weapon.character_unit_bones[unit_id]):
				errors.append("Weapon unit %s hand bone '%s' was not found on its character rig." % [unit_id, _weapon.character_unit_bones[unit_id]])
	rig.free()
	if _weapon.scene == null:
		errors.append("Weapon %s has no weapon scene; assign a PackedScene containing authored WeaponUnit, Grip and Tip nodes." % _weapon.id)
		return
	var weapon_root := _weapon.scene.instantiate()
	if weapon_root == null:
		errors.append("Weapon %s weapon scene could not be instantiated." % _weapon.id)
		return
	var units: Array[WeaponUnit] = []
	var markers: Dictionary = {}
	for candidate in weapon_root.find_children("*", "Node", true, false):
		if candidate is WeaponUnit:
			var unit := candidate as WeaponUnit
			units.append(unit)
			for unit_error in unit.validate():
				errors.append("Weapon %s: %s" % [_weapon.id, unit_error])
		elif candidate is WeaponHitboxMarker:
			var marker := candidate as WeaponHitboxMarker
			if markers.has(marker.marker_id):
				errors.append("Weapon %s has duplicate hitbox marker id '%s'." % [_weapon.id, marker.marker_id])
			else:
				markers[marker.marker_id] = true
	if weapon_root is WeaponUnit:
		units.append(weapon_root as WeaponUnit)
		for unit_error in (weapon_root as WeaponUnit).validate():
			errors.append("Weapon %s: %s" % [_weapon.id, unit_error])
	if weapon_root is WeaponHitboxMarker:
		markers[(weapon_root as WeaponHitboxMarker).marker_id] = true
	if units.is_empty():
		errors.append("Weapon %s weapon scene has no WeaponUnit. Add a unit with authored Grip and Tip markers." % _weapon.id)
	for combo_node in _graph.nodes:
		if combo_node == null:
			continue
		for spec in combo_node.hit_specs:
			if spec != null and spec.placement == HitSpec.Placement.WEAPON_MARKER and not markers.has(spec.marker_id):
				errors.append("Node %s hitbox uses missing weapon marker '%s'." % [combo_node.id, spec.marker_id])
	weapon_root.free()

func _rig_has_bone(skeletons: Array[Node], bone: StringName) -> bool:
	for candidate in skeletons:
		if (candidate as Skeleton3D).find_bone(bone) >= 0:
			return true
	return false

func _on_validation_meta_clicked(meta: Variant) -> void:
	var target := String(meta)
	if target.begins_with("node:"):
		var node_id := StringName(target.trim_prefix("node:"))
		if _graph != null and _graph.get_node(node_id) != null:
			canvas.select_attack(node_id)
			_on_attack_selected(node_id)
	elif target.begins_with("edge:"):
		var edge_index := target.trim_prefix("edge:").to_int()
		if edge_index < 0 or edge_index >= _validation_edge_targets.size():
			return
		var reference: Dictionary = _validation_edge_targets[edge_index]
		var owner_id: StringName = reference.get("owner_id", &"")
		if owner_id == &"__rest":
			var rest_edge: ComboEdge = _graph.rest_edges[reference.edge_index] if _graph != null and reference.edge_index < _graph.rest_edges.size() else null
			if rest_edge != null and _graph.get_node(rest_edge.target) != null:
				canvas.select_attack(rest_edge.target)
				_on_attack_selected(rest_edge.target)
			return
		if _graph == null or _graph.get_node(owner_id) == null:
			return
		canvas.select_attack(owner_id)
		_on_attack_selected(owner_id)
		for index in _window_entries.size():
			var window_entry: Dictionary = _window_entries[index]
			if window_entry.get("kind") == "edge" and int(window_entry.get("index", -1)) == int(reference.edge_index):
				window_kind.select(index)
				_on_window_kind_selected(index)
				return
	elif target.begins_with("weapon:") and _weapon != null and _editor_interface != null:
		_editor_interface.edit_resource(_weapon)

func _refresh_validation() -> void:
	_validation_edge_targets.clear()
	if _graph == null:
		validation.text = "Open a WeaponData or ComboGraph Resource."
		return
	var errors := validate_graph()
	if errors.is_empty():
		validation.text = "Graph valid 60 Hz inclusive ticks; %d attacks" % _graph.nodes.size()
		return
	var lines: PackedStringArray = []
	for issue in errors:
		var display := issue
		var edge_link_placeholders: Dictionary = {}
		var edge_reference := _validation_edge_reference(issue)
		if not edge_reference.is_empty():
			var edge_label: String = edge_reference.label
			var token := StringName("edge:%d" % _validation_edge_targets.size())
			var placeholder := "__COMBO_VALIDATION_EDGE_%d__" % _validation_edge_targets.size()
			_validation_edge_targets.append(edge_reference)
			edge_link_placeholders[placeholder] = "[url=%s]%s[/url]" % [token, edge_label]
		if not edge_reference.is_empty() and not String(edge_reference.edge_id).is_empty():
			display = display.replace(String(edge_reference.edge_id), "__COMBO_VALIDATION_EDGE_%d__" % (_validation_edge_targets.size() - 1))
		elif not edge_reference.is_empty():
			display = display.replace("(unnamed)", "__COMBO_VALIDATION_EDGE_%d__" % (_validation_edge_targets.size() - 1))
		for combo_node in _graph.nodes:
			if combo_node != null and not combo_node.id.is_empty() and display.contains(String(combo_node.id)):
				display = display.replace(String(combo_node.id), "[url=node:%s]%s[/url]" % [combo_node.id, combo_node.id])
			if _weapon != null and not String(_weapon.id).is_empty() and display.contains(String(_weapon.id)):
				display = display.replace(String(_weapon.id), "[url=weapon:%s]%s[/url]" % [_weapon.id, _weapon.id])
		for placeholder in edge_link_placeholders:
			display = display.replace(placeholder, String(edge_link_placeholders[placeholder]))
		lines.append("• %s" % display)
	validation.text = "Graph has %d issue(s):\n%s" % [errors.size(), "\n".join(lines)]

func _validation_edge_reference(issue: String) -> Dictionary:
	var duplicate_id_issue := issue.contains("edge ids must be unique")
	for node in _graph.nodes:
		if node == null:
			continue
		for edge_index in node.edges.size():
			var edge: ComboEdge = node.edges[edge_index]
			if edge == null:
				continue
			var location := "Node %s edge[%d]" % [node.id, edge_index]
			if duplicate_id_issue:
				if edge.id != &"" and issue.contains(String(edge.id)) and issue.ends_with("in %s" % location):
					return {"owner_id": node.id, "edge_index": edge_index, "edge_id": edge.id, "label": String(edge.id)}
			elif issue.begins_with("%s " % location):
				var label := String(edge.id) if edge.id != &"" else "edge %d" % (edge_index + 1)
				return {"owner_id": node.id, "edge_index": edge_index, "edge_id": edge.id, "label": label}
	if issue.contains("Rest"):
		for edge_index in _graph.rest_edges.size():
			var edge: ComboEdge = _graph.rest_edges[edge_index]
			if edge != null and duplicate_id_issue and edge.id != &"" and issue.contains(String(edge.id)) and issue.ends_with("in Rest edge[%d]" % edge_index):
				return {"owner_id": &"__rest", "edge_index": edge_index, "edge_id": edge.id, "label": String(edge.id)}
	return {}

func _load_layout() -> void:
	_layout = LAYOUT_SCRIPT.new() as ComboGraphLayout
	var source := _weapon.resource_path if _weapon != null else _graph.resource_path
	if source.contains("::"):
		source = source.split("::", false, 1)[0]
	if source.is_empty():
		return
	var path := combo_layout_path(source)
	if ResourceLoader.exists(path):
		var saved := load(path) as ComboGraphLayout
		if saved != null:
			_layout = saved
	_layout.graph_key = source

func _save_layout() -> void:
	if _layout == null or _graph == null:
		return
	var source := _weapon.resource_path if _weapon != null else _graph.resource_path
	if source.is_empty():
		return
	if source.contains("::"):
		source = source.split("::", false, 1)[0]
	_layout.graph_key = source
	var path := combo_layout_path(source)
	var error := ResourceSaver.save(_layout, path)
	if error != OK:
		validation.text = "Could not save graph layout (%d): %s" % [error, path]
