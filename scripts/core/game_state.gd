extends Node

signal score_changed(snake_id: StringName, score: int)
signal match_state_changed(state: StringName)

var _scores: Dictionary[StringName, int] = {}
var _match_state: StringName = &"boot"

func _ready() -> void:
	_ensure_input_action(&"turn_left", KEY_A)
	_ensure_input_action(&"turn_right", KEY_D)
	_ensure_input_action(&"boost", KEY_SHIFT)
	_ensure_input_action(&"pause", KEY_ESCAPE)

func register_snake(snake_id: StringName) -> void:
	if _scores.has(snake_id):
		push_warning("Snake already registered: %s" % snake_id)
		return
	_scores[snake_id] = 0
	score_changed.emit(snake_id, 0)

func set_score(snake_id: StringName, score: int) -> void:
	if score < 0:
		push_warning("Negative score is invalid for snake: %s" % snake_id)
		return
	_scores[snake_id] = score
	score_changed.emit(snake_id, score)

func set_match_state(state: StringName) -> void:
	_match_state = state
	match_state_changed.emit(state)

func get_match_state() -> StringName:
	return _match_state

func get_score(snake_id: StringName) -> int:
	if not _scores.has(snake_id):
		return 0
	return _scores[snake_id]

func _ensure_input_action(action: StringName, key_code: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and event.keycode == key_code:
			return

	var key_event: InputEventKey = InputEventKey.new()
	key_event.keycode = key_code
	InputMap.action_add_event(action, key_event)
