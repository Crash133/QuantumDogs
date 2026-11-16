class_name ProgressionRuntimeAdapter
extends RefCounted

var style_award_signal: StringName = &"style_points_awarded"
var _style: Node
var _style_service: ProgressionService
var _service: ProgressionService
var _coordinator: StageRewardCoordinator
var _submitter: Callable
var _presentation: Callable
var _forwarded_request := -1

func connect_style(style_system: Node, service: ProgressionService) -> Error:
	if not is_instance_valid(style_system) or not style_system.has_signal(style_award_signal): return ERR_UNAVAILABLE
	if is_instance_valid(_style) and _style.is_connected(style_award_signal, _on_style_award): _style.disconnect(style_award_signal, _on_style_award)
	_style = style_system
	_style_service = service
	return _style.connect(style_award_signal, _on_style_award)

func _on_style_award(award) -> void:
	if award == null: return
	var amount = award.get("amount") if award is Object or award is Dictionary else null
	if amount is float or amount is int: _style_service.credit_style_points(float(amount))

func configure(service: ProgressionService, coordinator: StageRewardCoordinator, submitter: Callable, presentation: Callable) -> void:
	if _coordinator != null and _coordinator.transition_ready.is_connected(_on_transition): _coordinator.transition_ready.disconnect(_on_transition)
	_service = service
	_coordinator = coordinator
	_submitter = submitter
	_presentation = presentation
	_coordinator.transition_ready.connect(_on_transition)

func get_combat_modifier_snapshot(profile: PersistentProfile, run: RunProgressionState) -> Dictionary:
	var upgrades: Array = []
	for card in run.deck.selected_cards():
		upgrades.append({"upgrade_id": card.upgrade_id, "family_id": card.family_id, "level": card.level, "eligible_weapon_ids": card.eligible_weapon_ids.duplicate(), "modifier_data": card.modifier_data.duplicate(true)})
	return {"stat_levels": profile.get_stat_levels(), "weapon_upgrades": upgrades}

func make_arena_request_payload(context: StageContext) -> Dictionary:
	return {"run_seed": context.run_seed, "ascent_depth": context.ascent_depth, "mode": context.mode, "band": context.band, "difficulty_parameters": context.difficulty_parameters.duplicate(true), "arena_profile": context.arena_profile.duplicate(true), "encounter": context.encounter.duplicate(true)}

func request_arena_generation(context: StageContext, request_id: int) -> void:
	if _submitter.is_valid(): _submitter.call(make_arena_request_payload(context), request_id)
	else: _coordinator.on_generation_completed(request_id, null)

func on_generation_completed(request_id: int, result: Resource) -> void:
	if _coordinator != null: _coordinator.on_generation_completed(request_id, result)

func _on_transition(result: Resource, context: StageContext) -> void:
	if _forwarded_request == _coordinator.request_id or _service.run.ended: return
	var expected := _service.run.make_next_stage_context(_service.catalog)
	if result == null or result.get("success") != true or context == null or expected == null or context.run_seed != expected.run_seed or context.ascent_depth != expected.ascent_depth or context.mode != expected.mode or context.band != expected.band:
		_coordinator.transition_failed.emit("Prepared stage could not be applied")
		return
	if _presentation.is_valid():
		var committed = _presentation.call(result, context.duplicate(true))
		if committed is bool and not committed: return
	_forwarded_request = _coordinator.request_id
