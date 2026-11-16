class_name InputBuffer
extends RefCounted

var lifetime_ticks: int = 6
var _pressed_at: Dictionary = {}

func configure(buffer_ticks: int) -> void:
	lifetime_ticks = maxi(0, buffer_ticks)

func push(action: StringName, tick: int) -> void:
	_pressed_at[action] = tick

func has_valid(action: StringName, tick: int) -> bool:
	if not _pressed_at.has(action):
		return false
	var age := tick - int(_pressed_at[action])
	return age >= 0 and age <= lifetime_ticks

func pressed_tick(action: StringName) -> int:
	return int(_pressed_at.get(action, -100000))

func snapshot(tick: int) -> Dictionary:
	var pending: Dictionary = {}
	for action in _pressed_at:
		if has_valid(action, tick):
			pending[action] = lifetime_ticks - (tick - int(_pressed_at[action]))
	return pending

func consume(action: StringName, tick: int) -> bool:
	var valid := has_valid(action, tick)
	_pressed_at.erase(action)
	return valid

func expire(tick: int) -> void:
	for action in _pressed_at.keys():
		if tick - int(_pressed_at[action]) > lifetime_ticks:
			_pressed_at.erase(action)

func clear() -> void:
	_pressed_at.clear()

