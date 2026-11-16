"""Regenerate tests/fixtures/lace_weapon_points.json from Assets/Objects/Lace.blend.

Run in background mode only (the .blend is read, never saved):

    blender -b Assets/Objects/Lace.blend --python Scripts/Combat/tools/export_lace_weapon_points.py -- tests/fixtures/lace_weapon_points.json

Records where Blender places sample weapon vertices (rig space, converted to Godot's
Y-up axes) at a few clip times. tests/test_lace_weapon_mounts.gd checks the mounted
game weapons against these points. The saber is absent: its object in Lace.blend is
not attached to a hand (see Assets/Weapons/README.md).
"""
import json
import sys

import bpy

if not bpy.app.background:
    raise SystemExit("Run with blender -b so the open file is never modified")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) != 1:
    raise SystemExit("Usage: blender -b Lace.blend --python export_lace_weapon_points.py -- <output.json>")

SAMPLES = {
    "greatsword": ("BigSword", [("BigSwordLight1", 8), ("BigSwordHeavy2", 17), ("BigSwordIdle", 0)]),
    "rocket_lance": ("RocketLance", [("LanceLight3", 8), ("LanceIdle", 0)]),
    "mantis_left": ("MantisBlades", [("MantisLight3", 6), ("MantisIdle", 0)]),
    "mantis_right": ("MantisBlades.001", [("MantisLight3", 6), ("MantisIdle", 0)]),
}
scene = bpy.context.scene
rig = bpy.data.objects["LaceRig"]
fps = scene.render.fps / scene.render.fps_base
result = {}
for key, (object_name, frames) in SAMPLES.items():
    weapon = bpy.data.objects[object_name]
    count = len(weapon.data.vertices)
    indices = sorted({0, count // 7, 2 * count // 7, 3 * count // 7, 4 * count // 7, 5 * count // 7, 6 * count // 7, count - 1})
    samples = []
    for clip, frame in frames:
        action = bpy.data.actions[clip]
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        scene.frame_set(frame)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        to_rig = rig.evaluated_get(depsgraph).matrix_world.inverted() @ weapon.evaluated_get(depsgraph).matrix_world
        points = []
        for index in indices:
            p = to_rig @ weapon.data.vertices[index].co
            points.append([round(p.x, 5), round(p.z, 5), round(-p.y, 5)])  # Blender Z-up -> Godot Y-up
        samples.append({"clip": clip, "time": frame / fps, "points": points})
    result[key] = {"blender_object": object_name, "vertex_indices": indices, "samples": samples}
with open(argv[0], "w") as handle:
    json.dump(result, handle, indent=1)
print("Wrote", argv[0])
