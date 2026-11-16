class_name CombatPracticeDummy
extends Combatant

# Manual lab control only. Enemy AI chooses its own parry opportunities through
# Combatant.try_parry; this fixture supplies no timing, chance or decision loop.
var parry_armed: bool = false

func arm_next_parry() -> bool:
	if not elite or not is_alive() or is_staggered():
		return false
	parry_armed = true
	return true

func try_parry(_hit: HitData) -> bool:
	var armed := parry_armed
	parry_armed = false
	return armed and elite and is_alive() and not is_staggered()
