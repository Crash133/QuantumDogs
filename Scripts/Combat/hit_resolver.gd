class_name HitResolver
extends RefCounted

const REACTION_KINDS: Array[StringName] = [&"flinch", &"pushback", &"launch", &"knockdown", &"slam"]
## Authored stun_ticks are 60 Hz ticks, whatever the physics rate.
const AUTHORED_TICKS_PER_SECOND := 60.0

var _warned_invalid_multiplier_sources: Dictionary = {}
var _warned_reaction_kinds: Dictionary = {}

# Stale Object references must reach this validation boundary. Object-typed
# parameters reject freed instances before GDScript can drop/log the contact.
func resolve_contact(spec: HitSpec, potency: float, source: Variant, target: Variant, battery: BatteryMeter = null, weapon_id: StringName = &"", attack_basis: Variant = null, feedback_burst_id: StringName = &"", contact_context: HitContactContext = null) -> HitData:
	if spec == null or typeof(target) != TYPE_OBJECT or not is_instance_valid(target) or not target.has_method("take_hit"):
		push_warning("Dropped combat contact without a resolvable Combatant")
		return null
	if target.has_method("is_alive") and not target.is_alive():
		return null
	source = _live_object(source)
	# Factions are optional, side-effect-free identity queries. Empty/missing
	# identity preserves unaligned contacts (including source-less hazards).
	if source != null and source.has_method("get_faction") and target.has_method("get_faction"):
		var source_faction: StringName = source.get_faction()
		if source_faction != &"" and source_faction == target.get_faction():
			return null
	var hit := HitData.new()
	var multipliers := _source_hit_multipliers(source, weapon_id)
	hit.damage = spec.damage * potency * multipliers.x
	hit.hitstun = float(maxi(spec.stun_ticks, 0)) * maxf(potency, 0.0) / AUTHORED_TICKS_PER_SECOND
	# Malformed reaction data drops the reaction, never the damage event.
	hit.knockback = spec.knockback * potency if spec.knockback.is_finite() and is_finite(potency) else Vector3.ZERO
	hit.reaction_kind = _reaction_kind(spec)
	hit.interrupts_armor = spec.interrupts_armor
	if hit.knockback != Vector3.ZERO:
		hit.knockback = _knockback_basis(source, attack_basis) * hit.knockback
	hit.heat = spec.heat * potency * multipliers.y
	hit.effect = spec.effect
	hit.source = source
	hit.weapon_id = weapon_id
	hit.potency = potency
	hit.feedback_cue_id = spec.feedback_cue_id
	hit.feedback_burst_id = feedback_burst_id
	hit.contact_context = contact_context
	if target.has_method("try_parry") and target.try_parry(hit):
		source = _live_object(source)
		if source != null and source.has_method("on_attack_parried"):
			source.on_attack_parried()
		if is_instance_valid(target):
			_emit_event(&"parried", [target, _live_object(source)])
		return null
	if not is_instance_valid(target):
		push_warning("Dropped combat contact without a resolvable Combatant")
		return null
	source = _live_object(source)
	hit.source = source
	var battery_target: bool = target.has_method("get_battery_meter")
	var application_result: Variant = target.take_hit(hit)
	var landed := true
	if battery_target:
		landed = application_result == DefenseResolver.Result.DAMAGED
	if not landed:
		return hit
	source = _live_object(source)
	# Follow only an accepted launch, never a merely requested one.
	if is_instance_valid(target) and hit.reaction_outcome == &"launch" and target is Node3D and target.has_method("is_alive") and target.is_alive() and source != null and source.has_method("on_enemy_launched"):
		source.on_enemy_launched(target)
	source = _live_object(source)
	hit.source = source
	var attacking_battery := battery
	if source != null and source.has_method("get_battery_meter"):
		attacking_battery = source.get_battery_meter()
	if attacking_battery != null and attacking_battery.tuning != null:
		attacking_battery.heal(attacking_battery.tuning.battery_hit_heal * potency)
		if source != null and source.has_method("get_heat_meter"):
			var attacker_heat: HeatMeter = source.get_heat_meter()
			if attacker_heat != null:
				attacker_heat.reduce_heat(attacking_battery.tuning.heat_hit_reduce * potency)
	hit.source = _live_object(source)
	if not is_instance_valid(target):
		push_warning("Combatant freed during hit application; subsequent target events skipped")
		return hit
	_emit_event(&"hit_landed", [hit, target])
	hit.source = _live_object(source)
	if not is_instance_valid(target):
		push_warning("Combatant freed during hit_landed; subsequent target events skipped")
		return hit
	# Battery/Player death has its own player_died event. It must never award
	# an enemy kill to downstream CombatEvents consumers.
	if not battery_target and target.has_method("is_alive") and not target.is_alive():
		_emit_event(&"enemy_killed", [target, hit])
	return hit

func _reaction_kind(spec: HitSpec) -> StringName:
	if spec.reaction_kind == &"flinch" and spec.effect == &"launch":
		return &"launch" # Legacy authoring alias.
	if spec.reaction_kind in REACTION_KINDS:
		return spec.reaction_kind
	if not _warned_reaction_kinds.has(spec.reaction_kind):
		_warned_reaction_kinds[spec.reaction_kind] = true
		push_warning("Unknown reaction_kind '%s' on a HitSpec; expected one of %s. No reaction is applied." % [spec.reaction_kind, REACTION_KINDS])
	return &""

func _source_hit_multipliers(source: Variant, weapon_id: StringName) -> Vector2:
	if source == null or not source.has_method("get_outgoing_hit_multipliers"):
		return Vector2.ONE
	var result: Variant = source.get_outgoing_hit_multipliers(weapon_id)
	if result is Vector2 and result.is_finite() and result.x >= 0.0 and result.y >= 0.0:
		return result
	var source_id: int = source.get_instance_id()
	if not _warned_invalid_multiplier_sources.has(source_id):
		_warned_invalid_multiplier_sources[source_id] = true
		push_warning("Invalid outgoing hit multipliers from source; using identity")
	return Vector2.ONE

func _live_object(value: Variant) -> Object:
	return value if typeof(value) == TYPE_OBJECT and is_instance_valid(value) else null

func _knockback_basis(source: Object, attack_basis: Variant) -> Basis:
	var basis := Basis.IDENTITY
	if attack_basis is Basis:
		# Native scene adapters supply the attacking proxy/flight frame. A
		# projectile or retired attack must not follow the source's later facing.
		basis = attack_basis
	elif source is Node3D:
		if source.has_method("get_combat_facing"):
			var facing: Vector3 = source.get_combat_facing()
			if facing.is_finite() and not facing.is_zero_approx():
				facing = facing.normalized()
				var up := Vector3.FORWARD if absf(facing.dot(Vector3.UP)) > 0.999 else Vector3.UP
				return Basis.looking_at(facing, up)
		basis = source.global_basis
	# Profile and knockback dimensions are world units, independent of art scale.
	return basis.orthonormalized() if basis.is_finite() and absf(basis.determinant()) > 0.000001 else Basis.IDENTITY

func _emit_event(event_name: StringName, arguments: Array) -> void:
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return
	var events := (main_loop as SceneTree).root.get_node_or_null("CombatEvents")
	if events != null and events.has_signal(event_name):
		Callable(events, "emit_signal").callv([event_name] + arguments)
