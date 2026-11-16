# Combat weapon resources

These four editable `WeaponData` resources are the runtime catalogue. Their graphs preserve the inspected GDD diagrams on PDF pages 37, 39, 41, and 43; see `Docs/Proposals/Combat-GDD-Evidence.md`. `Scenes/Weapons/` uses the supplied source meshes with temporary colors/scale/grip and incomplete attack animation coverage; this is not final presentation acceptance.

All numerical attack timings, damage, stun, Heat, dimensions, and magnetism below are **playtest placeholders**, not values supplied by the diagrams. Per-weapon timing differences implement the approved fast/balanced/slow profiles without claiming final animation authoring. Windows headless tests verify resource loading, transitions, required profiles, and selected native integration; human feel remains unverified.

| Weapon | Duration ticks | Input window | Switch window | Active ticks | Damage | Stun | Heat |
|---|---:|---|---|---|---:|---:|---:|
| Mantis Blades | 24 | 8–21 | 14–22 | 5–13 | 10 | 8 | 9 |
| Rocket Lance | 36 | 12–31 | 20–34 | 9–24 | 10 | 16 | 14 |
| Saber | 30 | 10–26 | 18–28 | 8–18 | 14 | 10 | 12 |
| Greatsword | 54 | 24–46 | 32–50 | 20–34 | 25.2 | 18 | 21.6 |

Mantis/Saber/Lance primary volumes are capsules; Greatsword primary is a box. Rocket Lance Fire uses the required cone. Circle volumes use ring profiles as a provisional geometric interpretation of the circular attacks. Dimensions are editable in each resource. All nodes currently share their weapon's timing row, use magnetism 0.35, and retain an 8-tick lingering trail. The existing Lunge travel placeholder is 2 units. Animation keys identify requested attacks; missing production clips must be reported/fallback explicitly rather than treated as authored.

The two Lance Circle boxes and two Saber Storm boxes retain separate internal IDs and source-specific edges, with shared human-readable labels. Lance Lunge/Fire/Stoke reject airborne entry. Every permitted air node requests Lace's existing once-per-landing gravity hold, including the first fresh attack after aerial follow. Launch tags on Uppercut, High Throw, and Fissure now reach the approved enemy launch/gravity-hold and aerial-follow behavior. See `Docs/superpowers/specs/2026-11-11-aerial-followup-design.md`.

## Authoring format (2026-11-12)

Profiles are typed `HitboxProfile` sub-resources (shape enum plus only that shape's fields), `poses` is a `WeaponPoses` sub-resource, `animation_aliases` is `Dictionary[StringName, StringName]`, and the unused `stat_modifiers`/`pose_animations` fields are gone. The migration kept every native shape/size identical (`tests/test_weapon_authoring.gd` compares against the legacy parser); the Lance `fire` cone keeps the legacy implicit radius 1.0. Saber plasma and Lance ghost drill are now data: `ChargedProjectileAbility` on `saber.tres` and `GatherThrowAbility` on `rocket_lance.tres` (Stoke carries tag `ghost_drill`), with the same approved values. `WeaponData.validate()` checks every resource at startup, in GUT and on editor save. How to add moves, weapons and specials: `Docs/Agent-Guides/Combat-Authoring.md`.

Earlier source gaps were resolved in the 2026-11-12 continuation. See `Docs/Proposals/Combat.md` and the Combat implementation postmortem for approved values, current implementation and remaining presentation limits. The historical notes below describe the earlier checkpoint:

- Saber continuation: five successfully started attacks charge an invisible gauge; charged attacks emit an independently damaging pooled piercing plasma slash at their first active tick. Charge persists until switching away. Approved editable speed 20, lifetime 24 ticks and radius 0.6; projectile payload copies the originating authored HitSpec. GUT and arena checks pass; visual/audio and human feel remain partial.
- Rocket Lance continuation: landed Stoke contacts gather enemies toward a moving point 2 units ahead at 8 units/second through the repeating light loop. Exiting Stoke throws them forward at 8 units/second without extra damage; death/deletion only releases. These are approved editable defaults. Final animation, visual effect and human crowd feel remain open.
- Exact stun units/animation response, per-node weapon poses and final clip lengths, and throw/pull trajectories require source/animation decisions and playtest evidence. The later approved aerial extension supplies the current launch/gravity-hold rules and placeholder speeds; final reaction feel/animation remains unverified.

No upgrades, progression, bosses, minibosses, or final-stage rules are implemented here.

## Source mesh export

The four scenes load `Assets/Objects/Exports/CombatWeapons/*.obj`, exported from MantisBlades, RocketLance, Plane (Saber), and BigSword in the live TUDO data. Blender MCP wrote only those object data-blocks to an ignored library snapshot, preserving the open file, dirty state, active object and selection. MCP's background launcher could not find Blender on PATH; the installed Blender 5.2 executable exported the snapshot directly. The master and pre-existing OBJ/texture exports were not overwritten.

`Scripts/Combat/tools/export_weapon_meshes.py` is a background-only, first-export helper for that snapshot; it refuses existing output files. It bakes source scale into copied mesh vertices, normalizes the long axis to Godot +Y, and places the grip 10% from the mesh base, retaining the previous visual lengths (0.65/1.8/1.0/1.6). These are playtest presentation choices, not new combat dimensions. Colors stay in the existing weapon scenes; source UVs/normals are retained, materials are not exported. `CombatWeapons/manifest.json` records source objects, counts, transforms and output hashes. It does not change HitSpecs, native profiles, timing or damage ownership.

GUT checks actual mesh geometry, scaled bounds, and absence of collision owners; full suite at this checkpoint is 145 tests / 1199 assertions. All four mounted meshes were inspected in Godot with clean runtime logs. Generic legacy attack fallbacks still drive Mantis/Lance/Greatsword; Saber retains its supplied rig and mapped clips. Final dual-arm/hand mounting, per-weapon clips, materials and human animation/weapon feel remain partial or unverified.

## Lace animation set (`LaceGame.glb`)

All four weapons play Lace's hand-authored clips from `Assets/Objects/Lace.blend` (81 actions, 24 fps). The game loads **`Assets/Objects/LaceGame.glb`**, not `Lace.glb`.

**Why a separate export.** Lace's clips use Rigify IK Stretch, so arm segments are scaled non-uniformly, up to about 2.7x. glTF bones always inherit their parent's full scale and can't store the resulting shear. In the normal export (`Lace.glb`), Lace's hands land up to 1 m away from where Blender shows them, in 41 of 81 clips. `LaceGame.glb` flattens the bone hierarchy (every bone is stored relative to the rig root), which reproduces Blender's deform poses. Checked over every clip at Blender's frame times, the worst error is 4.4 cm, and most bones are within millimetres.

**Deform bones only.** The export keeps just the 65 `DEF-` bones; the body is weighted to nothing else. The other 327 Rigify control and mechanism bones would otherwise be animated on every tick. Dropping them cut the player animation cost from about 9.3 ms to 2.5 ms per physics tick. The exporter also drops the weapon meshes in the `.blend` before export, because they are parented to control bones (`hand_ik.*`) and would bring those bones back.

Lace is the only player rig. The old `Standard Run` model, its AnimationTree and the dagger were removed from `Player.tscn`. A weapon without `character_scene` now reports an error instead of falling back.

To rebuild it after editing `Lace.blend` (the `.blend` is only read):

```
blender -b Assets/Objects/Lace.blend --python Scripts/Combat/tools/export_lace_game_rig.py -- Assets/Objects/LaceGame.glb
```

Import settings (`LaceGame.glb.import`):
- `animation/fps=24` matches the source, so authored keys are not resampled.
- Each weapon's `Idle` and `Running` clip loops.
- The body material comes from `Resources/Materials/lace_garage.tres`, which uses the same textures as the title garage. `ModelMaterialImport` applies it.

**Hand mounts.** Every weapon mounts on `DEF-hand.L`. The mantis right blade mounts on `DEF-hand.R` through `character_unit_bones`.
- `character_weapon_transform` is where the weapon's Grip frame sits in the hand bone. The mantis uses `character_unit_transforms`, one entry per blade.
- These values are fitted from the weapon objects in `Lace.blend`, so they include the artist's weapon size: greatsword 1.23x, lance 1.15x, mantis 1.19x and saber 1.12x the game meshes. `Tip` markers scale with them.
- The saber is the exception. In `Lace.blend` it is not attached to a hand (it hangs about 1 m away in every clip), so it borrows the greatsword's left-hand hold.
- The old grip-point markers (two-point alignment to right-hand finger and forearm bones) were removed from the weapon scenes. The two-point solver code is still there.
- `tests/test_lace_weapon_mounts.gd` compares the mounted weapons with Blender vertex positions. The fixture comes from `Scripts/Combat/tools/export_lace_weapon_points.py`. Results:
  - greatsword: 0.0 cm
  - mantis: up to 3.5 cm, because in Blender the blades follow the IK control and slip against the hand
  - lance: up to 9.4 cm, because the game's lance mesh differs in shape from Blender's

**Clips per move.** These are the `animation_aliases` / `air_animation_aliases` tables, by chain position. Light *N* is the *N*th light; Heavy *N* branches off light *N*. *Reused* means the clip set has no dedicated clip for that move.

| Weapon | Ground clips | Air clips (`Jump*`) |
|---|---|---|
| Saber | Swipe 1, Swipe 2, Pass, L-Sweep = Light1–4; R-Sweep = Light2 (*reused*, it sweeps opposite to Light4). Up Slash, Swipe Rise, Storm = Heavy1–3 (both Storms = Heavy3) | lights alternate JumpLight1/2; heavies JumpHeavy1 |
| Mantis | Lunge, X-Cut, Left Sweep, Right Sweep = Light1–4. Uppercut, Ram, Overhead Throw = Heavy1–3. Left Stab = Light1, Right Stab = Heavy3 (*reused*) | same rule |
| Lance | Sweep, Lunge, Fire, Stoke = Light1–4. Circle (both), High Throw, Behind Stab = Heavy1, Heavy2, Heavy3 | Sweep and heavies only (Lunge/Fire/Stoke are ground-only) |
| Greatsword | Slam, Earthquake, Fissure = Light1–3. Slam Ground, Circle = Heavy1–2 (Light4 and Heavy3 unused) | same rule |

Remap any move in the weapon's Inspector by changing its clip in `animation_aliases`. `validate()` rejects keys that match no move.

**Timing.** Gameplay ticks, hit windows and damage are unchanged. Each move's `clip_start_seconds` / `clip_end_seconds` puts the clip's strike frame at the centre of its active window. The strike frame is the measured peak blade-tip speed in Blender. Playback is the fastest rate between 0.75x and 2x that keeps the strike centred inside the clip.
- Nine moves land 1–6 ticks (0.1 s or less) outside their window, because their clip strikes in its first or last frames. These are Saber Swipe 2 / Pass / R-Sweep (early) and Up Slash (late), Mantis Uppercut (late), and Lance Sweep (early) and Lunge / both Circles (late).
- Jump clips play whole over the move's duration.

**Other poses.** Each weapon uses its own `Idle`, `Running`, `JumpStart`/`JumpIdle`/`JumpEnd`, `Parry` (block), `ParrySuccess` and `Hit1`. `Change` plays once when you switch to that weapon on the ground (`WeaponPoses.equip`). `Hit2`, `RunToIdle` and `MenuPose` are not used. The pose mixer caches only the clips each weapon references (`WeaponData.referenced_clips()`), because the shared rig holds all 81.

**Saber execution/parry.** The flattened rig has no bone hierarchy, so the saber's `WeaponRigCalibration` sets `flattened_rig = true` and lists the 15 left-hand finger bones in `hand_followers`. When the procedural contact solver turns an arm joint, it now turns every arm segment nearer the hand, plus those fingers, around that joint. That reproduces what a hierarchy does, so executions and parries keep the full shoulder-to-wrist correction and the elbow pole. The left-arm pole uses `(1, 0, 0)`; the mirrored value made parries diverge in the tests.
