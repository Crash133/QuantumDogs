@tool
extends EditorPlugin

const EDITOR_SCENE: PackedScene = preload("res://addons/combo_designer/scenes/ComboDesigner.tscn")

var _editor: ComboEditor
var _dock: EditorDock

func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "Combo Designer"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_editor = EDITOR_SCENE.instantiate() as ComboEditor
	_editor.configure(get_editor_interface(), get_undo_redo())
	_dock.add_child(_editor)
	add_dock(_dock)
	add_tool_menu_item("Open Combo Designer", _open_current_selection)

func _exit_tree() -> void:
	remove_tool_menu_item("Open Combo Designer")
	if _dock != null and is_instance_valid(_dock):
		remove_dock(_dock)
		_dock.queue_free()
	_editor = null
	_dock = null

func _handles(object: Object) -> bool:
	return object is WeaponData or object is ComboGraph

func _edit(object: Object) -> void:
	if _editor == null:
		return
	if object is WeaponData:
		_editor.edit_weapon(object as WeaponData)
	elif object is ComboGraph:
		_editor.edit_graph(object as ComboGraph)

func _open_current_selection() -> void:
	if _editor == null or _dock == null:
		return
	var paths := get_editor_interface().get_selected_paths()
	if not paths.is_empty():
		var resource := load(paths[0])
		if resource is WeaponData:
			_editor.edit_weapon(resource as WeaponData)
		elif resource is ComboGraph:
			_editor.edit_graph(resource as ComboGraph)
	_dock.make_visible()
