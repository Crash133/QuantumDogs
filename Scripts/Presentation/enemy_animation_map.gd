class_name EnemyAnimationMap
extends Resource

## Visual state -> action name on the role scene's imported AnimationPlayer.
## Keys: idle, pursue, windup, attack, recovery, hit (stun), stagger (Elite
## heat), defeated. Values must be inspected source action names.
@export var role: StringName
@export var clips: Dictionary[StringName, StringName] = {}
## Played when a mapped action is absent from the imported player.
@export var fallback: StringName
## Fraction of the attack clip where windup ends and recovery starts. The
## strike pose lands inside the role's authoritative active window.
@export var strike_window: Vector2 = Vector2(0.45, 0.6)
## Below this planar speed the enemy shows `idle` instead of `pursue`.
@export var walk_speed_threshold: float = 0.2

func clip_for(state: StringName) -> StringName:
	return clips.get(state, fallback)
