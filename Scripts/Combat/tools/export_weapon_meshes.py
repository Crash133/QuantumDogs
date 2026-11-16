"""Blender background-only export of a task-owned live-data snapshot.

Run through Blender MCP's execute_blender_code_for_cli against
native/hit/build/combat_weapon_snapshot.blend. The source master/live session
is never opened for modification or saved. Existing outputs are never replaced.
"""
import hashlib
import json
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

root = Path(__file__).resolve().parents[3]
snapshot = root / "native/hit/build/combat_weapon_snapshot.blend"
output = root / "Assets/Objects/Exports/CombatWeapons"
if not bpy.app.background or Path(bpy.data.filepath).resolve() != snapshot.resolve():
    raise RuntimeError("Export requires the separate combat weapon snapshot in background Blender")

weapons = [
    ("mantis_blades", "MantisBlades", 2, 0.65),
    ("rocket_lance", "RocketLance", 1, 1.8),
    ("saber", "Plane", 1, 1.0),
    ("greatsword", "BigSword", 1, 1.6),
]
for weapon_id, _, _, _ in weapons:
    if (output / f"{weapon_id}.obj").exists():
        raise FileExistsError(f"Refusing to overwrite {weapon_id}.obj")
if (output / "manifest.json").exists():
    raise FileExistsError("Refusing to overwrite export manifest")
output.mkdir(parents=True, exist_ok=True)

scene = bpy.data.scenes.new("CombatWeaponExport")
if bpy.context.window:
    bpy.context.window.scene = scene
view_layer = scene.view_layers[0]
exports = []
with bpy.context.temp_override(scene=scene, view_layer=view_layer):
    for weapon_id, source_name, long_axis, length in weapons:
        source = bpy.data.objects[source_name]
        if source.type != "MESH" or source.modifiers or source.data.shape_keys:
            raise RuntimeError(f"Inspect procedural source before exporting {source_name}")
        mesh = source.data.copy()
        mesh.name = f"Combat_{weapon_id}"
        mesh.materials.clear()  # Scene materials remain explicit playtest colors.
        points = []
        for vertex in mesh.vertices:
            scaled = Vector(tuple(vertex.co[i] * source.scale[i] for i in range(3)))
            # Author Y-long sword/lance meshes and Z-long Mantis share a +Z
            # Blender axis, exported as +Y in Godot. Preserve shape proportions.
            points.append(Vector((scaled.x, -scaled.z, scaled.y)) if long_axis == 1 else scaled)
        lower = Vector(tuple(min(p[i] for p in points) for i in range(3)))
        upper = Vector(tuple(max(p[i] for p in points) for i in range(3)))
        extent = upper - lower
        if extent.z <= 0.0 or extent.z < max(extent.x, extent.y):
            raise RuntimeError(f"Unexpected long axis for {source_name}; inspect source")
        factor = length / extent.z
        shift = Vector(((lower.x + upper.x) * 0.5, (lower.y + upper.y) * 0.5, lower.z + extent.z * 0.1))
        for vertex, point in zip(mesh.vertices, points):
            vertex.co = (point - shift) * factor
        mesh.update()
        obj = bpy.data.objects.new(f"Combat_{weapon_id}", mesh)
        obj.matrix_world = Matrix.Identity(4)
        scene.collection.objects.link(obj)
        for current in view_layer.objects:
            current.select_set(False)
        obj.select_set(True)
        view_layer.objects.active = obj
        destination = output / f"{weapon_id}.obj"
        status = bpy.ops.wm.obj_export(
            filepath=str(destination), export_selected_objects=True,
            forward_axis="NEGATIVE_Z", up_axis="Y", global_scale=1.0,
            export_animation=False, apply_modifiers=False, apply_transform=True,
            export_materials=False, export_uv=True, export_normals=True,
        )
        if "FINISHED" not in status or not destination.is_file():
            raise RuntimeError(f"Export failed: {weapon_id}")
        exports.append({
            "weapon_id": weapon_id, "source_object": source_name,
            "source_vertices": len(mesh.vertices), "source_scale": list(source.scale),
            "source_long_axis": long_axis, "normalized_length": length,
            "grip_fraction_from_base": 0.1,
            "file": destination.name,
            "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
        })
        obj.select_set(False)

result = {
    "blender": bpy.app.version_string,
    "source": "Assets/Objects/Exports/TUDO.blend (live weapon snapshot)",
    "snapshot_sha256": hashlib.sha256(snapshot.read_bytes()).hexdigest(),
    "note": "Visual scale/grip and colors are playtest placeholders; no gameplay data exported",
    "exports": exports,
}
(output / "manifest.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
