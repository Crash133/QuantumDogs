class_name CombatDebugOverlay
extends CanvasLayer

var arena: Node3D
var player: Player
var _panel: PanelContainer
var _status: Label
var _glyphs: Label
var _pause_button: Button
var _drain: CheckBox
var _rebind_panel: CombatRebindPanel
var _decay_editor: CombatDecayEditor
var _stepping: bool = false
var _original_time_scale: float
var _original_physics_rate: int

const POSITIVE_FIELDS := [&"heat_max", &"battery_max", &"stagger_ticks", &"elite_stagger_ticks", &"dash_charges_base", &"dash_iframe_ticks", &"dash_regen_ticks", &"revolver_capacity", &"revolver_shot_interval_ticks", &"revolver_regen_ticks_per_shot"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_original_time_scale = Engine.time_scale
	_original_physics_rate = Engine.physics_ticks_per_second
	_panel = PanelContainer.new()
	_panel.position = Vector2(12.0, 12.0)
	_panel.custom_minimum_size.x = 340.0
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.035, 0.05, 0.92)
	background.content_margin_left = 12.0
	background.content_margin_right = 12.0
	background.content_margin_top = 10.0
	background.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override(&"panel", background)
	add_child(_panel)
	var viewport_scroll := ScrollContainer.new()
	viewport_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(viewport_scroll)
	_panel.size = Vector2(380.0, maxf(120.0, get_viewport().get_visible_rect().size.y - 24.0))
	get_viewport().size_changed.connect(func() -> void:
		_panel.size = Vector2(380.0, maxf(120.0, get_viewport().get_visible_rect().size.y - 24.0)))
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 5)
	viewport_scroll.add_child(column)
	_label(column, "COMBAT LAB · click arena to play", 15)
	_status = _label(column, "", 13)
	_glyphs = _label(column, "", 12)
	_glyphs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_glyphs.custom_minimum_size.x = 316.0
	var spawns := HBoxContainer.new()
	column.add_child(spawns)
	_button(spawns, "Basic", func() -> void: _spawn(false, false))
	_button(spawns, "Elite", func() -> void: _spawn(true, false))
	_button(spawns, "Flying", func() -> void: _spawn(false, true))
	var hits := HBoxContainer.new()
	column.add_child(hits)
	_button(hits, "Hit after 1s", _incoming_hit)
	_button(hits, "Fill Elite Heat", _stagger_elite)
	var parry_button := _button(column, "Arm nearest Elite parry", arm_elite_parry)
	parry_button.tooltip_text = "The next hit is parried once. Staggered Elites cannot parry."
	var time_row := HBoxContainer.new()
	column.add_child(time_row)
	_pause_button = _button(time_row, "Pause", func() -> void: get_tree().paused = not get_tree().paused)
	_button(time_row, "Step", step_once)
	var speed := OptionButton.new()
	for title in ["1×", "½×", "¼×"]:
		speed.add_item(title)
	speed.item_selected.connect(func(index: int) -> void: set_slow_motion([1.0, 0.5, 0.25][index]))
	time_row.add_child(speed)
	_button(time_row, "Reset", _reset)
	_drain = CheckBox.new()
	_drain.text = "Battery drain"
	_drain.button_pressed = player.combat_controller.battery_drain_enabled
	_drain.toggled.connect(func(enabled: bool) -> void: apply_tuning(&"battery_drain_enabled", enabled))
	column.add_child(_drain)
	var gizmo_row := HBoxContainer.new()
	column.add_child(gizmo_row)
	var hits_toggle := CheckBox.new()
	hits_toggle.text = "Hit/trail gizmos"
	gizmo_row.add_child(hits_toggle)
	var hurt_toggle := CheckBox.new()
	hurt_toggle.text = "Hurtboxes"
	gizmo_row.add_child(hurt_toggle)
	var update_gizmos := func(_pressed: bool) -> void:
		var gizmos := arena.get_node("HitGizmos") as CombatHitGizmos
		gizmos.show_hits = hits_toggle.button_pressed
		gizmos.show_hurtboxes = hurt_toggle.button_pressed
		gizmos.visible = gizmos.show_hits or gizmos.show_hurtboxes
	hits_toggle.toggled.connect(update_gizmos)
	hurt_toggle.toggled.connect(update_gizmos)
	_label(column, "Green: live · orange: trail · magenta: swept path", 11)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(316.0, 180.0)
	scroll.visible = false
	_button(column, "Live tuning ▾", func() -> void:
		scroll.visible = not scroll.visible
		if scroll.visible:
			_rebind_panel.cancel_rebind()
			_rebind_panel.visible = false
			_decay_editor.visible = false)
	column.add_child(scroll)
	var values := VBoxContainer.new()
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(values)
	for property in player.combat_controller.tuning.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or property.usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var field := StringName(property.name)
		if field in [&"tick_rate", &"battery_drain_enabled"] or property.type not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var row := HBoxContainer.new()
		values.add_child(row)
		var label := _label(row, String(field).replace("_", " "), 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var spin := SpinBox.new()
		spin.min_value = 1.0 if field in POSITIVE_FIELDS else 0.0
		spin.max_value = 100000.0
		spin.step = 1.0 if property.type == TYPE_INT else 0.1
		spin.value = player.combat_controller.tuning.get(field)
		spin.custom_minimum_size.x = 90.0
		spin.value_changed.connect(func(value: float) -> void: apply_tuning(field, value))
		row.add_child(spin)
	_rebind_panel = CombatRebindPanel.new()
	_rebind_panel.name = "RebindPanel"
	_rebind_panel.ui_exclusion = _panel
	_rebind_panel.visible = false
	_rebind_panel.capture_changed.connect(func(active: bool) -> void:
		if active: player.combat_controller.input_sampling_enabled = false)
	_button(column, "Rebind controls ▾", func() -> void:
		_rebind_panel.visible = not _rebind_panel.visible
		if _rebind_panel.visible:
			scroll.visible = false
			_decay_editor.visible = false
		else:
			_rebind_panel.cancel_rebind())
	column.add_child(_rebind_panel)
	_decay_editor = CombatDecayEditor.new()
	_decay_editor.name = "DecayEditor"
	_decay_editor.controller = player.combat_controller
	_decay_editor.apply_curve = apply_decay
	_decay_editor.visible = false
	_button(column, "Trail decay curves", func() -> void:
		_decay_editor.visible = not _decay_editor.visible
		if _decay_editor.visible:
			scroll.visible = false
			_rebind_panel.cancel_rebind()
			_rebind_panel.visible = false)
	column.add_child(_decay_editor)
	_label(column, "Orange: Elite · blue: flying · gray: basic", 11)
	_panel.mouse_entered.connect(func() -> void: player.combat_controller.input_sampling_enabled = false)

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	var controller := player.combat_controller
	var node := controller.combo.current_node
	var node_name := "Rest" if node == null else (node.display_name if not node.display_name.is_empty() else String(node.id))
	var weapon := controller.combo.weapon.display_name if controller.combo.weapon != null else "None"
	_status.text = "%s · %s\n%s · tick %d · depth %d\nBattery %.1f/%.1f · Heat %.1f/%.1f\nDash %d/%d · Revolver %d/%d\nNative %.3f ms · contacts %d\nBuffer %s · hit in %.2fs" % [weapon, CombatController.State.keys()[controller.state], node_name, controller.tick, controller.combo.depth, controller.battery.value, controller.battery.maximum, controller.heat.value, controller.heat.maximum, controller.dash.current, controller.dash.capacity, controller.revolver.current, controller.revolver.capacity, float(arena.get("last_native_usec")) / 1000.0, arena.get("contacts_total"), controller.input_buffer.snapshot(controller.tick), float(arena.get("incoming_hit_ticks_left")) / 60.0]
	var tracker := player.get_node_or_null("DeviceTracker") as DeviceTracker
	var device := tracker.current_device if tracker != null else DeviceTracker.Device.KEYBOARD_MOUSE
	var prompts: Array[String] = []
	for action: StringName in [&"light", &"heavy", &"dash", &"jump", &"block", &"execute", &"shoot"]:
		prompts.append("%s %s" % [String(action), PromptGlyphs.get_glyph(action, device)])
	_glyphs.text = " · ".join(prompts)
	_pause_button.text = "Resume" if get_tree().paused else "Pause"
	_drain.set_pressed_no_signal(controller.battery_drain_enabled and controller.tuning.battery_drain_enabled)
	var focus := get_viewport().gui_get_focus_owner()
	controller.input_sampling_enabled = not _rebind_panel.is_capturing() and not _panel.get_global_rect().has_point(get_viewport().get_mouse_position()) and not (is_instance_valid(focus) and _panel.is_ancestor_of(focus))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if _panel.get_global_rect().has_point(event.position):
			player.combat_controller.input_sampling_enabled = false
		else:
			var focus := get_viewport().gui_get_focus_owner()
			if is_instance_valid(focus) and _panel.is_ancestor_of(focus):
				focus.release_focus()

func apply_tuning(field: StringName, value: Variant) -> void:
	var controller := player.combat_controller
	var before: Variant = controller.tuning.get(field)
	if field == &"tick_rate" or typeof(before) not in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
		return
	if field == &"trail_linger_ticks":
		value = clampi(int(value), 0, 256)
	if typeof(before) == TYPE_INT:
		value = maxi(1 if field in POSITIVE_FIELDS else 0, int(value))
	elif typeof(before) == TYPE_FLOAT:
		value = maxf(1.0 if field in POSITIVE_FIELDS else 0.0, float(value))
	controller.tuning.set(field, value)
	controller.input_buffer.configure(controller.tuning.input_buffer_ticks)
	controller.heat.maximum = controller.tuning.heat_max
	controller.heat.stagger_duration = controller.tuning.stagger_ticks
	controller.heat.value = minf(controller.heat.value, controller.heat.maximum)
	controller.battery.maximum = controller.tuning.battery_max
	controller.battery.value = minf(controller.battery.value, controller.battery.maximum)
	controller.battery.value_changed.emit(controller.battery.value, controller.battery.maximum)
	controller.heat.value_changed.emit(controller.heat.value, controller.heat.maximum)
	if controller.heat.value >= controller.heat.maximum and not controller.heat.is_staggered():
		controller.heat.start_stagger()
	controller.dash.capacity = maxi(1, controller.tuning.dash_charges_base)
	controller.dash.current = mini(controller.dash.current, controller.dash.capacity)
	if field == &"battery_drain_enabled":
		controller.battery_drain_enabled = bool(value)
		controller.battery.drain_enabled = bool(value)
	if String(field).begins_with("revolver_"):
		var ammo_field := StringName(String(field).trim_prefix("revolver_"))
		controller.ranged_weapon.set(ammo_field, value)
		controller.revolver.set(ammo_field, value)
		controller.revolver.current = mini(controller.revolver.current, controller.revolver.capacity)
	if field == &"trail_linger_ticks":
		for weapon in controller.weapons:
			if weapon == null or weapon.graph == null:
				continue
			for node in weapon.graph.nodes:
				for spec in node.hit_specs:
					spec.linger_ticks = clampi(int(value), 0, 256)
	for target in get_tree().get_nodes_in_group("combatants"):
		if not arena.is_ancestor_of(target) or not target.get("tuning") is CombatTuning:
			continue
		target.tuning.set(field, value)
		var meter: HeatMeter = target.get_heat_meter() if target.has_method("get_heat_meter") else null
		if meter != null:
			meter.maximum = target.tuning.heat_max
			meter.stagger_duration = target.tuning.elite_stagger_ticks
			meter.value = minf(meter.value, meter.maximum)
			meter.value_changed.emit(meter.value, meter.maximum)
			if meter.value >= meter.maximum and not meter.is_staggered():
				meter.start_stagger()

func apply_decay(weapon_index: int, node_id: StringName, spec_index: int, samples: PackedFloat32Array) -> bool:
	var weapons := player.combat_controller.weapons
	if weapon_index < 0 or weapon_index >= weapons.size() or samples.size() < 2 or samples.size() > 257:
		return false
	var weapon := weapons[weapon_index]
	if weapon == null or weapon.graph == null:
		return false
	var node := weapon.graph.get_node(node_id)
	if node == null or spec_index < 0 or spec_index >= node.hit_specs.size() or node.hit_specs[spec_index] == null:
		return false
	# Live contacts always have full potency. Curves tune the aging trail only.
	if samples[0] != 1.0:
		return false
	for sample in samples:
		if not is_finite(sample) or sample < 0.0 or sample > 1.0:
			return false
	var curve := Curve.new()
	for index in range(samples.size()):
		curve.add_point(Vector2(float(index) / float(samples.size() - 1), samples[index]), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	node.hit_specs[spec_index].decay = curve
	return true

func set_slow_motion(scale: float) -> void:
	if _stepping or scale not in [1.0, 0.5, 0.25]:
		return
	Engine.time_scale = scale
	Engine.physics_ticks_per_second = int(60.0 * scale)

func step_once() -> void:
	if _stepping:
		return
	_stepping = true
	var tree := get_tree()
	tree.paused = false
	await tree.physics_frame
	await tree.physics_frame
	tree.paused = true
	_stepping = false

func _spawn(elite: bool, flying: bool) -> void:
	var at := player.global_position + player.get_combat_facing() * 3.0
	at.y = 2.5 if flying else 0.9
	arena.spawn_dummy(elite, flying, at)

func _incoming_hit() -> void:
	arena.queue_incoming_hit(60)

func _stagger_elite() -> void:
	var best: Combatant
	var nearest := INF
	for target in get_tree().get_nodes_in_group("combatants"):
		if not target is Combatant or not arena.is_ancestor_of(target) or not target.elite or not target.is_alive():
			continue
		var distance := player.global_position.distance_squared_to(target.global_position)
		if distance < nearest:
			nearest = distance
			best = target
	if best != null:
		best.heat_meter.add_heat(best.heat_meter.maximum)

func arm_elite_parry() -> bool:
	var best: CombatPracticeDummy
	var nearest := INF
	for target in get_tree().get_nodes_in_group("combatants"):
		if not target is CombatPracticeDummy or not arena.is_ancestor_of(target) or not target.elite or not target.is_alive() or target.is_staggered():
			continue
		var distance := player.global_position.distance_squared_to(target.global_position)
		if distance < nearest:
			nearest = distance
			best = target
	return best.arm_next_parry() if best != null else false

func _reset() -> void:
	if _stepping:
		return
	_rebind_panel.cancel_rebind()
	get_tree().paused = false
	if get_tree().current_scene == arena:
		get_tree().reload_current_scene()

func _exit_tree() -> void:
	Engine.time_scale = _original_time_scale
	Engine.physics_ticks_per_second = _original_physics_rate
	if is_instance_valid(player) and player.combat_controller != null:
		player.combat_controller.input_sampling_enabled = true

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	parent.add_child(button)
	return button
