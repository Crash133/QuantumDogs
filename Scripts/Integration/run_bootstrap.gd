class_name RunBootstrap
extends Node3D

## Playable integrated run: HitManager, Player + camera, StyleSystem (no HUD),
## RunController. Open Scenes/Integration/RunBootstrap.tscn and press F6.
## FrontEndRoot owns menus; this scene owns the reusable gameplay composition.

@export_group("Run Startup")
@export var mode: StringName = &"Normal"
@export var run_seed: int = 0 ## 0 picks a random seed.
@export var continue_saved_run: bool = false
@export var autostart: bool = true
## Optional authored Resource for permanent stat and weapon-card build mappings.
## Leave unset until production values/cards are approved.
@export var combat_build_policy: CombatBuildPolicy

@export_group("Scene References")
## Native contact service; ready before Player registers combat shapes.
@export var hit_manager: HitManagerNode
@export var player: Player
@export var style_system: StyleSystem
@export var run: RunController
## Game Feel: authored child; bound to this run's real player, camera, Style and encounter.
@export var feedback: FeedbackDirector
@export var camera_rig: CameraRig

func _ready() -> void:
	if hit_manager == null or player == null or style_system == null or run == null:
		push_error("RunBootstrap: assign the scene references in the Inspector.")
		return
	if hit_manager.native_manager == null or not hit_manager.native_manager.is_ready():
		return
	if combat_build_policy != null:
		run.build_policy = combat_build_policy
	run.setup(self, player, style_system, IntegrationContent.make_catalog())
	_bind_feedback()
	if autostart:
		if not continue_saved_run or not run.continue_run():
			run.start_new_run(mode, run_seed if run_seed != 0 else randi())

func _bind_feedback() -> void:
	if feedback == null:
		return
	feedback.bind_world(self)
	feedback.bind_camera(camera_rig)
	feedback.bind_combat(get_node_or_null("/root/CombatEvents"))
	feedback.bind_style(style_system)
	feedback.bind_encounter(run.director)
	feedback.bind_hit_adapter(player.get_node_or_null("CombatHitAdapter"))
	feedback.bind_player(player)
	feedback.bind_run(run)
