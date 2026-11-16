"""Export the in-game Lace rig from Assets/Objects/Lace.blend.

Run in background mode only (the .blend is read, never saved):

    blender -b Assets/Objects/Lace.blend --python Scripts/Combat/tools/export_lace_game_rig.py -- Assets/Objects/LaceGame.glb

Why a separate export: Lace's clips use Rigify IK Stretch, so arm segments get
non-uniform scale (up to ~2.7x). glTF bones always inherit their parent's full
scale and cannot store the resulting shear, so a normal hierarchical export puts
Lace's hands up to ~1 m away from where Blender shows them. Flattening the bone
hierarchy stores every bone relative to the rig root, which reproduces Blender's
deform poses in Godot. Every action becomes one clip with the same name.

Only deform (DEF-) bones are exported: the body is weighted to nothing else, and
the 327 Rigify control/mechanism bones would otherwise be animated every tick.
"""
import sys

import bpy

if not bpy.app.background:
    raise SystemExit("Run this exporter with blender -b so the open file is never modified")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) != 1:
    raise SystemExit("Usage: blender -b Lace.blend --python export_lace_game_rig.py -- <output.glb>")

rig = bpy.data.objects["LaceRig"]
body = bpy.data.objects["body"]
# The rig's active action would otherwise also be baked as the rest pose.
rig.animation_data.action = None
# Weapon meshes are parented to control bones (hand_ik.*); the exporter would keep
# those bones, and Godot would then wrap the rig in an extra scaled root bone.
for child in [c for c in rig.children if c != body]:
    bpy.data.objects.remove(child)
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(
    filepath=argv[0],
    export_format="GLB",
    use_selection=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_hierarchy_flatten_bones=True,
    export_def_bones=True,
)
print("Exported Lace game rig to", argv[0])
