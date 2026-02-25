extends Node
class_name SnakeManager

signal snake_spawned(snake_id: StringName)
signal snake_died(snake_id: StringName, reason: StringName)
signal score_changed(snake_id: StringName, score: int)

var _scores: Dictionary[StringName, int] = {}

func spawn_player_snake() -> StringName:
	var snake_id: StringName = &"player"
	_scores[snake_id] = 0
	snake_spawned.emit(snake_id)
	score_changed.emit(snake_id, 0)
	return snake_id

func apply_food_gain(snake_id: StringName, amount: int) -> void:
	if amount <= 0:
		push_warning("Food gain amount must be positive.")
		return
	if not _scores.has(snake_id):
		push_warning("Unknown snake_id for score gain: %s" % snake_id)
		return

	_scores[snake_id] += amount
	score_changed.emit(snake_id, _scores[snake_id])

func kill_snake(snake_id: StringName, reason: StringName) -> void:
	if not _scores.has(snake_id):
		push_warning("Unknown snake_id for death event: %s" % snake_id)
		return
	snake_died.emit(snake_id, reason)

func get_score(snake_id: StringName) -> int:
	if not _scores.has(snake_id):
		return 0
	return _scores[snake_id]
