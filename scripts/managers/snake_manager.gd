extends Node
class_name SnakeManager

signal snake_spawned(snake_id: StringName)
signal snake_died(snake_id: StringName, reason: StringName)
signal snake_mass_dropped(world_position: Vector2, amount: int)
signal score_changed(snake_id: StringName, score: int)

@export var player_snake_scene: PackedScene
@export var movement_config: Resource
@export var growth_per_food: float = 8.0

var _scores: Dictionary[StringName, int] = {}
var _snake_nodes: Dictionary[StringName, Node2D] = {}

func spawn_player_snake() -> StringName:
	var snake_id: StringName = &"player"
	if _snake_nodes.has(snake_id):
		push_warning("Player snake is already spawned.")
		return snake_id

	if player_snake_scene == null:
		push_error("player_snake_scene is not assigned on SnakeManager.")
		return &""

	var snake_node := player_snake_scene.instantiate() as Node2D
	if snake_node == null:
		push_error("player_snake_scene must instantiate to Node2D.")
		return &""

	if snake_node.has_method("set_movement_config"):
		snake_node.call("set_movement_config", movement_config)
	if snake_node.has_method("set_snake_id"):
		snake_node.call("set_snake_id", snake_id)
	if snake_node.has_signal("snake_died"):
		snake_node.snake_died.connect(_on_snake_node_died.bind(snake_id))

	add_child(snake_node)
	snake_node.global_position = Vector2.ZERO
	_snake_nodes[snake_id] = snake_node
	_scores[snake_id] = 0

	snake_spawned.emit(snake_id)
	score_changed.emit(snake_id, 0)
	return snake_id

func set_movement_config(config: Resource) -> void:
	movement_config = config
	for snake_node in _snake_nodes.values():
		if snake_node.has_method("set_movement_config"):
			snake_node.call("set_movement_config", movement_config)

func apply_food_gain(snake_id: StringName, amount: int) -> void:
	if amount <= 0:
		push_warning("Food gain amount must be positive.")
		return
	if not _scores.has(snake_id):
		push_warning("Unknown snake_id for score gain: %s" % snake_id)
		return

	_scores[snake_id] += amount
	score_changed.emit(snake_id, _scores[snake_id])

	if _snake_nodes.has(snake_id) and _snake_nodes[snake_id].has_method("grow_by"):
		_snake_nodes[snake_id].call("grow_by", growth_per_food * float(amount))

func kill_snake(snake_id: StringName, reason: StringName) -> void:
	if not _scores.has(snake_id):
		push_warning("Unknown snake_id for death event: %s" % snake_id)
		return

	var drop_position: Vector2 = Vector2.ZERO
	var drop_amount: int = 0
	if _snake_nodes.has(snake_id):
		var snake_node: Node2D = _snake_nodes[snake_id]
		drop_position = snake_node.global_position
		if snake_node.has_method("get_body_length"):
			var body_length_value: Variant = snake_node.call("get_body_length")
			if body_length_value is float or body_length_value is int:
				var growth_unit: float = max(growth_per_food, 1.0)
				drop_amount = int(max(round(float(body_length_value) / growth_unit), 4.0))

		snake_node.queue_free()
		_snake_nodes.erase(snake_id)

	_scores.erase(snake_id)
	if drop_amount > 0:
		snake_mass_dropped.emit(drop_position, drop_amount)

	snake_died.emit(snake_id, reason)

func has_snake(snake_id: StringName) -> bool:
	return _snake_nodes.has(snake_id)

func get_snake_position(snake_id: StringName) -> Vector2:
	if not _snake_nodes.has(snake_id):
		push_warning("Unknown snake_id for position query: %s" % snake_id)
		return Vector2.ZERO
	return _snake_nodes[snake_id].global_position

func get_score(snake_id: StringName) -> int:
	if not _scores.has(snake_id):
		return 0
	return _scores[snake_id]

func _on_snake_node_died(reason: StringName, snake_id: StringName) -> void:
	kill_snake(snake_id, reason)
