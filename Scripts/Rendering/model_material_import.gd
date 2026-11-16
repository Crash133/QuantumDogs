@tool
class_name ModelMaterialImport
extends EditorScenePostImport

## Import script for models whose GLB carries no material slots. Binds the
## authored material for the file being imported to every surface, so every
## instance (including ones built at runtime) gets it and it survives re-import.

const MATERIALS := {
	"CommonEnemy.glb": "res://Resources/Materials/enemy_common.tres",
	"EliteAnimation.glb": "res://Resources/Materials/enemy_elite.tres",
	"FlyingEnemy.glb": "res://Resources/Materials/enemy_drone.tres",
	# Same textures as the Lace material in Scenes/UI/TitleGarage.tscn.
	"LaceGame.glb": "res://Resources/Materials/lace_garage.tres",
	"ProtagonistLowPolySaberAnimation.glb": "res://Resources/Materials/protagonist.tres",
}

func _post_import(scene: Node) -> Object:
	var path: String = MATERIALS.get(get_source_file().get_file(), "")
	if path.is_empty():
		push_warning("ModelMaterialImport: no material mapped for %s" % get_source_file())
		return scene
	var material := load(path) as Material
	if material == null:
		push_error("ModelMaterialImport: cannot load %s" % path)
		return scene
	# Skinned models arrive as MeshInstance3D, unskinned ones as ImporterMeshInstance3D.
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			mesh.surface_set_material(surface, material)
	for node in scene.find_children("*", "ImporterMeshInstance3D", true, false):
		var importer_mesh := (node as ImporterMeshInstance3D).mesh
		for surface in importer_mesh.get_surface_count():
			importer_mesh.set_surface_material(surface, material)
	return scene
