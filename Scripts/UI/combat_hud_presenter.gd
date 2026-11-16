class_name CombatHudPresenter
extends Node

var hud: Control
var player: Player
var style_system: Node
var run_controller: RunController
var device_tracker: DeviceTracker
var _style_hud: StyleHud
## Blinking warning glyph appears at or below this Battery ratio.
var low_battery_ratio: float = 0.25
var reduce_motion: bool = false
var hits: int = 0
var kills: int = 0
var _dash_icon_count: int = -1
## Weapon id -> icon node on the bottom-left d-pad. The equipped weapon is lit.
const WEAPON_ICONS := {&"mantis_blades": "Mantis", &"rocket_lance": "Lance", &"saber": "Saber", &"greatsword": "Sword"}
const ICON_ACTIVE := Color(0.25, 0.9, 1.0, 1.0)
const ICON_OWNED := Color(0.6, 0.68, 0.78, 0.85)
## Not in the loadout: blacked out like a locked roster slot.
const ICON_LOCKED := Color(0.0, 0.0, 0.0, 1.0)
const OUTLINE_LOCKED := Color(0.4, 0.5, 0.65, 0.9)

func attach_hud(root: Control) -> void:
	hud = root
	# The HUD scene already holds the Style feedback; never stack a second copy.
	_style_hud = hud.find_child("StyleRank", true, false) as StyleHud

func bind(player_node: Player, style: Node, run: RunController, tracker: DeviceTracker) -> void:
	unbind()
	player = player_node
	style_system = style
	run_controller = run
	device_tracker = tracker
	if hud == null or player == null or player.combat_controller == null: return
	var combat := player.combat_controller
	combat.battery.value_changed.connect(_on_battery_changed)
	combat.heat.value_changed.connect(_on_heat_changed)
	combat.revolver.ammo_changed.connect(_on_ammo_changed)
	combat.loadout_changed.connect(_on_loadout_changed)
	if _style_hud != null and style_system != null:
		_style_hud.attach_style_system(style_system, _label("RatingLabel"), _label("ActionList"), _label("PayoutLabel"), _style_hud.get_node("../../../AnimationPlayer"))
	var events := get_node_or_null("/root/CombatEvents")
	if events != null and events.has_signal("weapon_switched"):
		if not events.weapon_switched.is_connected(_on_weapon_switched): events.weapon_switched.connect(_on_weapon_switched)
	if events != null:
		if not events.hit_landed.is_connected(_on_hit_landed): events.hit_landed.connect(_on_hit_landed)
		if not events.enemy_killed.is_connected(_on_enemy_killed): events.enemy_killed.connect(_on_enemy_killed)
	if run_controller != null and not run_controller.level_started.is_connected(_on_level_started):
		run_controller.level_started.connect(_on_level_started)
	reset_combat_log()
	if device_tracker != null:
		device_tracker.device_changed.connect(_on_device_changed)
	update_all()

func unbind() -> void:
	if style_system != null and _style_hud != null:
		for signal_name in [&"style_changed", &"action_tally_changed", &"style_points_awarded", &"damage_penalty_applied"]:
			var callback := Callable(_style_hud, "_on_" + String(signal_name))
			if style_system.is_connected(signal_name, callback): style_system.disconnect(signal_name, callback)
	if player != null and player.combat_controller != null:
		var combat := player.combat_controller
		if combat.battery.value_changed.is_connected(_on_battery_changed): combat.battery.value_changed.disconnect(_on_battery_changed)
		if combat.heat.value_changed.is_connected(_on_heat_changed): combat.heat.value_changed.disconnect(_on_heat_changed)
		if combat.revolver.ammo_changed.is_connected(_on_ammo_changed): combat.revolver.ammo_changed.disconnect(_on_ammo_changed)
		if combat.loadout_changed.is_connected(_on_loadout_changed): combat.loadout_changed.disconnect(_on_loadout_changed)
	var events := get_node_or_null("/root/CombatEvents")
	if events != null and events.has_signal("weapon_switched") and events.weapon_switched.is_connected(_on_weapon_switched):
		events.weapon_switched.disconnect(_on_weapon_switched)
	if events != null:
		if events.hit_landed.is_connected(_on_hit_landed): events.hit_landed.disconnect(_on_hit_landed)
		if events.enemy_killed.is_connected(_on_enemy_killed): events.enemy_killed.disconnect(_on_enemy_killed)
	if run_controller != null and run_controller.level_started.is_connected(_on_level_started):
		run_controller.level_started.disconnect(_on_level_started)
	if device_tracker != null and device_tracker.device_changed.is_connected(_on_device_changed): device_tracker.device_changed.disconnect(_on_device_changed)
	player = null
	style_system = null
	run_controller = null

func _process(_delta: float) -> void:
	var _probe := ScriptCostProbe.start()
	_process_body(_delta)
	ScriptCostProbe.stop(&"ui.hud", _probe)

func _process_body(_delta: float) -> void:
	if player == null or player.combat_controller == null: return
	var combat := player.combat_controller
	_set_text("DashLabel", "DASH  %d / %d" % [combat.dash.current, combat.dash.capacity])
	_update_dash_icons(combat.dash.current, combat.dash.capacity)
	_update_low_battery(combat.battery.value, combat.battery.maximum, combat.state == CombatController.State.DEAD)
	_update_weapon_slots()
	_update_target()
	_update_encounter()

func update_all() -> void:
	if player == null or player.combat_controller == null: return
	var combat := player.combat_controller
	_on_battery_changed(combat.battery.value, combat.battery.maximum)
	_on_heat_changed(combat.heat.value, combat.heat.maximum)
	_on_ammo_changed(combat.revolver.current, combat.revolver.capacity)
	_update_weapon_slots()
	_update_target()
	_update_encounter()
	_on_device_changed(device_tracker.current_device if device_tracker != null else DeviceTracker.Device.KEYBOARD_MOUSE)

func _on_battery_changed(value: float, maximum: float) -> void:
	_set_meter("BatteryLabel", "BATTERY", value, maximum)
	_set_text("BatteryLabel", "BATTERY") # The percentage readout carries the value.
	_set_text("BatteryPercent", "%d%%" % roundi(100.0 * value / maxf(1.0, maximum)))
func _on_heat_changed(value: float, maximum: float) -> void:
	_set_meter("HeatLabel", "HEAT", value, maximum)
func _on_ammo_changed(current: int, capacity: int) -> void:
	_set_text("AmmoLabel", "REVOLVER  %d / %d" % [current, capacity])
	var chamber := hud.find_child("RevolverChamber", true, false) as RevolverChamber
	if chamber != null: chamber.set_ammo(current, capacity)
func _on_weapon_switched(_previous: StringName, _current: StringName) -> void:
	_update_weapon_slots()

func _on_loadout_changed() -> void:
	_update_weapon_slots()

func _on_hit_landed(hit: HitData, _target: Object) -> void:
	if hit != null and player != null and hit.source == player:
		hits += 1
		_refresh_combat_log()

func _on_enemy_killed(_target: Object, hit: HitData) -> void:
	if hit != null and player != null and hit.source == player:
		kills += 1
		_refresh_combat_log()

func _on_level_started(_depth: int, _context: StageContext) -> void:
	reset_combat_log()

func reset_combat_log() -> void:
	hits = 0
	kills = 0
	_refresh_combat_log()

func _refresh_combat_log() -> void:
	if hud == null: return
	_set_text("HitsValue", str(hits))
	_set_text("KillsValue", str(kills))
	# Rows appear once they count something; the divider separates the ranking from them.
	var rows := {"HitsRow": hits, "KillsRow": kills}
	var any_shown := false
	for row_name in rows:
		var row := hud.find_child(row_name, true, false) as Control
		if row == null: continue
		row.visible = rows[row_name] != 0
		any_shown = any_shown or row.visible
	var divider := hud.find_child("LogDivider", true, false) as Control
	if divider != null: divider.visible = any_shown

## One small icon per dash charge: filled when available, dim when recharging.
func _update_dash_icons(current: int, capacity: int) -> void:
	var row := hud.find_child("DashIcons", true, false) as HBoxContainer
	if row == null: return
	if _dash_icon_count != capacity:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
		for _i in range(capacity):
			var icon := Panel.new()
			icon.custom_minimum_size = Vector2(14, 24)
			row.add_child(icon)
		_dash_icon_count = capacity
	for index in range(row.get_child_count()):
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(3)
		style.bg_color = Color(0.25, 0.9, 1.0) if index < current else Color(0.12, 0.14, 0.2, 0.7)
		(row.get_child(index) as Panel).add_theme_stylebox_override(&"panel", style)

func _update_low_battery(value: float, maximum: float, dead: bool) -> void:
	var icon := hud.find_child("LowBatteryIcon", true, false) as Control
	if icon == null: return
	var low := not dead and maximum > 0.0 and value / maximum <= low_battery_ratio
	icon.visible = low
	if low:
		icon.modulate.a = 0.85 if reduce_motion else 0.25 + 0.6 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.5))

func _set_meter(node_name: String, caption: String, value: float, maximum: float) -> void:
	_set_text(node_name, "%s  %d / %d" % [caption, roundi(value), roundi(maximum)])
	var bar := hud.find_child(node_name.replace("Label", "Bar"), true, false) as ProgressBar
	if bar != null:
		bar.max_value = maximum
		bar.value = value

func _update_weapon_icons(combat: CombatController) -> void:
	var owned: Array[StringName] = []
	for weapon in combat.weapons:
		owned.append(weapon.id)
	var active: StringName = combat.combo.weapon.id if combat.combo.weapon != null else &""
	for weapon_id: StringName in WEAPON_ICONS:
		var icon := hud.find_child(WEAPON_ICONS[weapon_id], true, false) as TextureRect
		if icon == null: continue
		if not icon.material is ShaderMaterial:
			var material := ShaderMaterial.new()
			material.shader = load("res://Shaders/WeaponIcon.gdshader")
			icon.material = material
		var tint := ICON_ACTIVE if weapon_id == active else (ICON_OWNED if owned.has(weapon_id) else ICON_LOCKED)
		(icon.material as ShaderMaterial).set_shader_parameter(&"tint", tint)
		(icon.material as ShaderMaterial).set_shader_parameter(&"outline", OUTLINE_LOCKED if tint == ICON_LOCKED else Color(0, 0, 0, 0))

func _update_weapon_slots() -> void:
	if player == null or player.combat_controller == null: return
	var combat := player.combat_controller
	_update_weapon_icons(combat)
	for index in range(4):
		var label := hud.find_child("WeaponSlot%d" % (index + 1), true, false) as Label
		if label == null: continue
		if index < combat.weapons.size():
			var weapon: WeaponData = combat.weapons[index]
			label.text = "%s  %s" % ["[%d]" % (index + 1), String(weapon.display_name if weapon.display_name != &"" else weapon.id).to_upper()]
			label.modulate = Color(0.35, 1.0, 0.9) if combat.active_weapon_index == index else Color.WHITE
			label.show()
		else:
			label.hide()
	var ammo_label := hud.find_child("AmmoLabel", true, false) as Control
	if ammo_label != null: ammo_label.visible = combat.revolver_available
	var chamber := hud.find_child("RevolverChamber", true, false) as Control
	if chamber != null: chamber.visible = combat.revolver_available
	if combat.revolver_available:
		_set_text("AmmoLabel", "REVOLVER  %d / %d" % [combat.revolver.current, combat.revolver.capacity])

func _update_target() -> void:
	var panel := hud.find_child("TargetPanel", true, false) as Control
	if panel == null or player == null or player.combat_controller == null: return
	var combat := player.combat_controller
	var target: Node3D = combat.get_execution_target()
	if not is_instance_valid(target) and combat.targeting_service != null:
		target = combat.targeting_service.locked_target
	if not is_instance_valid(target) or not bool(target.get("elite")):
		panel.hide()
		return
	var name_label := panel.find_child("TargetNameLabel", true, false) as Label
	var detail := panel.find_child("TargetDetailLabel", true, false) as Label
	if name_label != null: name_label.text = "ELITE  " + String(target.name).to_upper()
	if detail != null:
		var meter: HeatMeter = target.get_heat_meter() if target.has_method("get_heat_meter") else null
		var shockwave_locked := target.has_method("is_execution_shockwave_locked") and bool(target.call("is_execution_shockwave_locked"))
		var readiness := "SHOCKWAVE STUNNED" if shockwave_locked else "EXECUTION READY" if target.is_staggered() else "BUILD HEAT"
		if meter != null:
			detail.text = "HEAT %d / %d  •  %s" % [roundi(meter.value), roundi(meter.maximum), readiness]
		else: detail.text = "ELITE TARGET LOCKED"
	panel.show()

func _update_encounter() -> void:
	if run_controller == null or run_controller.director == null: return
	if run_controller.service != null and run_controller.service.profile != null:
		_set_text("CurrencyLabel", "STYLE POINTS  %d" % floori(run_controller.service.profile.style_points))
	var stage: StageContext = run_controller.context
	var level := str(stage.ascent_depth) if stage != null else "--"
	var difficulty := String(stage.mode).to_upper() if stage != null else "--"
	_set_text("EncounterLabel", "LEVEL %s  |  DIFFICULTY %s  |  ENCOUNTER %d / %d" % [level, difficulty, run_controller.director.alive_count, run_controller.director.manifest_total])

func _on_device_changed(device: int) -> void:
	if hud == null: return
	_set_text("DashPromptLabel", "DASH  %s" % PromptGlyphs.get_glyph(&"dash", device))
	_set_text("AttackPromptLabel", "%s  %s" % [PromptGlyphs.get_glyph(&"light", device), PromptGlyphs.get_glyph(&"heavy", device)])

func _label(path: String) -> Label:
	return hud.get_node_or_null(path) as Label

func _set_text(node_name: String, value: String) -> void:
	var label := hud.find_child(node_name, true, false) as Label
	if label != null: label.text = value

static func format_meter(value: float, maximum: float) -> String:
	return "%d / %d" % [roundi(value), roundi(maximum)]
