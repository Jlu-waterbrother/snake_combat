extends Node
class_name SnakeManager

signal snake_spawned(snake_id: StringName)
signal snake_died(snake_id: StringName, reason: StringName)
signal snake_mass_dropped(world_position: Vector2, amount: int)
signal score_changed(snake_id: StringName, score: int)
signal enemy_state_changed(snake_id: StringName, state: StringName)

@export var player_snake_scene: PackedScene
@export var enemy_snake_scene: PackedScene
@export var movement_config: Resource
@export var ai_config: Resource
@export var growth_per_food: float = 8.0
@export var enemy_spawn_radius_min: float = 420.0
@export var enemy_spawn_radius_max: float = 980.0
@export var world_radius: float = 2200.0

const STATE_PATROL: StringName = &"patrol"
const STATE_SEEK: StringName = &"seek"
const STATE_CHASE: StringName = &"chase"
const STATE_AVOID: StringName = &"avoid"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _scores: Dictionary[StringName, int] = {}
var _snake_nodes: Dictionary[StringName, Node2D] = {}
var _enemy_ids: Array[StringName] = []
var _enemy_states: Dictionary[StringName, StringName] = {}
var _enemy_targets: Dictionary[StringName, Vector2] = {}
var _enemy_retarget_cooldown: Dictionary[StringName, float] = {}
var _player_snake_id: StringName = &""
var _target_enemy_count: int = 0
var _next_enemy_index: int = 1
var _food_manager: Node2D
var _aggression_scale: float = 1.0
var _boost_scale: float = 1.0

func _ready() -> void:
	_rng.randomize()

func _physics_process(delta: float) -> void:
	_update_enemy_ai(delta)
	_check_world_bounds()
	_check_head_to_head_collision()

func spawn_player_snake() -> StringName:
	var snake_id: StringName = &"player"
	if _snake_nodes.has(snake_id):
		push_warning("Player snake is already spawned.")
		return snake_id
	if player_snake_scene == null:
		push_error("player_snake_scene is not assigned on SnakeManager.")
		return &""

	if not _spawn_snake(snake_id, player_snake_scene, Vector2.ZERO, false):
		return &""

	_player_snake_id = snake_id
	snake_spawned.emit(snake_id)
	score_changed.emit(snake_id, 0)
	return snake_id

func spawn_enemy_snakes(count: int) -> void:
	set_target_enemy_count(count)

func set_target_enemy_count(count: int) -> void:
	_target_enemy_count = max(count, 0)
	_sync_enemy_count()

func set_movement_config(config: Resource) -> void:
	movement_config = config
	for snake_node: Node2D in _snake_nodes.values():
		if snake_node.has_method("set_movement_config"):
			snake_node.call("set_movement_config", movement_config)

func set_ai_config(config: Resource) -> void:
	ai_config = config

func set_food_manager(food_manager: Node2D) -> void:
	_food_manager = food_manager

func set_world_radius(radius: float) -> void:
	world_radius = max(radius, 200.0)

func set_ai_difficulty_scalars(aggression_scale: float, boost_scale: float) -> void:
	_aggression_scale = clamp(aggression_scale, 0.5, 2.0)
	_boost_scale = clamp(boost_scale, 0.5, 2.0)

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

	var allow_mass_drop: bool = reason != &"despawned"
	var was_enemy: bool = _enemy_ids.has(snake_id)
	var drop_position: Vector2 = Vector2.ZERO
	var drop_amount: int = 0
	if _snake_nodes.has(snake_id):
		var snake_node: Node2D = _snake_nodes[snake_id]
		drop_position = snake_node.global_position
		if allow_mass_drop and snake_node.has_method("get_body_length"):
			var body_length_value: Variant = snake_node.call("get_body_length")
			if body_length_value is float or body_length_value is int:
				var growth_unit: float = max(growth_per_food, 1.0)
				drop_amount = int(max(round(float(body_length_value) / growth_unit), 4.0))

		snake_node.queue_free()
		_snake_nodes.erase(snake_id)

	_scores.erase(snake_id)
	if snake_id == _player_snake_id:
		_player_snake_id = &""
	if was_enemy:
		_enemy_ids.erase(snake_id)
		_enemy_states.erase(snake_id)
		_enemy_targets.erase(snake_id)
		_enemy_retarget_cooldown.erase(snake_id)

	if allow_mass_drop and drop_amount > 0:
		snake_mass_dropped.emit(drop_position, drop_amount)

	snake_died.emit(snake_id, reason)

	if was_enemy and reason != &"despawned" and _enemy_ids.size() < _target_enemy_count:
		_spawn_next_enemy()

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

func get_enemy_count() -> int:
	return _enemy_ids.size()

func get_player_snake_id() -> StringName:
	return _player_snake_id

func get_player_body_length() -> float:
	if _player_snake_id == &"" or not _snake_nodes.has(_player_snake_id):
		return 0.0
	if _snake_nodes[_player_snake_id].has_method("get_body_length"):
		var value: Variant = _snake_nodes[_player_snake_id].call("get_body_length")
		if value is float or value is int:
			return float(value)
	return 0.0

func _sync_enemy_count() -> void:
	while _enemy_ids.size() < _target_enemy_count:
		var enemy_count_before: int = _enemy_ids.size()
		_spawn_next_enemy()
		if _enemy_ids.size() == enemy_count_before:
			break
	while _enemy_ids.size() > _target_enemy_count:
		var enemy_id: StringName = _enemy_ids[_enemy_ids.size() - 1]
		kill_snake(enemy_id, &"despawned")

func _spawn_next_enemy() -> void:
	var enemy_id: StringName = StringName("enemy_%d" % _next_enemy_index)
	_next_enemy_index += 1
	var enemy_scene: PackedScene = enemy_snake_scene if enemy_snake_scene != null else player_snake_scene
	if enemy_scene == null:
		push_error("enemy_snake_scene and fallback player_snake_scene are both null.")
		return

	if not _spawn_snake(enemy_id, enemy_scene, _sample_enemy_spawn_position(), true):
		return

	_enemy_ids.append(enemy_id)
	_enemy_states[enemy_id] = STATE_PATROL
	_enemy_targets[enemy_id] = _snake_nodes[enemy_id].global_position + Vector2.RIGHT * 120.0
	_enemy_retarget_cooldown[enemy_id] = 0.0
	snake_spawned.emit(enemy_id)
	score_changed.emit(enemy_id, 0)
	enemy_state_changed.emit(enemy_id, STATE_PATROL)

func _spawn_snake(snake_id: StringName, snake_scene: PackedScene, spawn_position: Vector2, is_enemy: bool) -> bool:
	var snake_node := snake_scene.instantiate() as Node2D
	if snake_node == null:
		push_error("Snake scene must instantiate to Node2D.")
		return false

	if snake_node.has_method("set_movement_config"):
		snake_node.call("set_movement_config", movement_config)
	if snake_node.has_method("set_snake_id"):
		snake_node.call("set_snake_id", snake_id)
	if snake_node.has_method("set_control_mode"):
		snake_node.call("set_control_mode", 1 if is_enemy else 0)
	if snake_node.has_method("set_head_color") and is_enemy:
		snake_node.call("set_head_color", Color(0.97, 0.27, 0.31))
	if snake_node.has_signal("snake_died"):
		snake_node.snake_died.connect(_on_snake_node_died.bind(snake_id))

	add_child(snake_node)
	snake_node.global_position = spawn_position
	_snake_nodes[snake_id] = snake_node
	_scores[snake_id] = 0
	return true

func _sample_enemy_spawn_position() -> Vector2:
	var min_radius: float = max(enemy_spawn_radius_min, 120.0)
	var max_radius: float = max(enemy_spawn_radius_max, min_radius + 1.0)
	var angle: float = _rng.randf_range(0.0, TAU)
	var radius: float = _rng.randf_range(min_radius, max_radius)
	return Vector2(cos(angle), sin(angle)) * radius

func _update_enemy_ai(delta: float) -> void:
	if _enemy_ids.is_empty():
		return

	var has_player: bool = _player_snake_id != &"" and _snake_nodes.has(_player_snake_id)
	var player_position: Vector2 = Vector2.ZERO
	if has_player:
		player_position = _snake_nodes[_player_snake_id].global_position

	var retarget_origins: Dictionary = {}
	var retarget_interval: float = max(_ai_float("retarget_interval", 0.2), 0.05)
	for enemy_id: StringName in _enemy_ids:
		if not _snake_nodes.has(enemy_id):
			continue
		var enemy_node: Node2D = _snake_nodes[enemy_id]
		var cooldown: float = _enemy_retarget_cooldown.get(enemy_id, 0.0) - delta
		_enemy_retarget_cooldown[enemy_id] = cooldown
		if cooldown <= 0.0:
			retarget_origins[enemy_id] = enemy_node.global_position
			_enemy_retarget_cooldown[enemy_id] = retarget_interval

	var vision_radius: float = _ai_float("vision_radius", 520.0)
	var nearest_food_by_enemy: Dictionary = {}
	if not retarget_origins.is_empty() and _food_manager != null and _food_manager.has_method("get_nearest_food_positions"):
		var nearest_value: Variant = _food_manager.call("get_nearest_food_positions", retarget_origins, vision_radius)
		if nearest_value is Dictionary:
			nearest_food_by_enemy = nearest_value

	for enemy_id: StringName in _enemy_ids:
		if not _snake_nodes.has(enemy_id):
			continue
		if retarget_origins.has(enemy_id):
			var enemy_position_value: Variant = retarget_origins.get(enemy_id, Vector2.ZERO)
			var nearest_food_value: Variant = nearest_food_by_enemy.get(enemy_id, Vector2.INF)
			var enemy_position: Vector2 = Vector2.ZERO
			if enemy_position_value is Vector2:
				enemy_position = enemy_position_value
			var nearest_food: Vector2 = Vector2.INF
			if nearest_food_value is Vector2:
				nearest_food = nearest_food_value
			_retarget_enemy(enemy_id, enemy_position, has_player, player_position, nearest_food, vision_radius)

		var enemy_node: Node2D = _snake_nodes[enemy_id]
		var target_position: Vector2 = _enemy_targets.get(enemy_id, enemy_node.global_position + Vector2.RIGHT * 120.0)
		_apply_enemy_steering(enemy_id, enemy_node, target_position)

func _retarget_enemy(enemy_id: StringName, enemy_position: Vector2, has_player: bool, player_position: Vector2, nearest_food: Vector2, vision_radius: float) -> void:
	var state: StringName = STATE_PATROL
	var target: Vector2 = enemy_position + _random_direction() * 240.0
	var avoid_ratio: float = clamp(_ai_float("avoid_boundary_ratio", 0.8), 0.5, 0.95)
	if enemy_position.length() >= world_radius * avoid_ratio:
		state = STATE_AVOID
		target = Vector2.ZERO
	else:
		var aggression: float = clamp(_ai_float("aggression", 0.45) * _aggression_scale, 0.0, 1.0)
		var should_chase: bool = false
		if has_player and enemy_position.distance_to(player_position) <= vision_radius:
			should_chase = _rng.randf() <= aggression

		if should_chase:
			state = STATE_CHASE
			target = player_position
		elif nearest_food.is_finite():
			state = STATE_SEEK
			target = nearest_food

	_enemy_targets[enemy_id] = target
	var previous_state: StringName = _enemy_states.get(enemy_id, STATE_PATROL)
	if previous_state != state:
		_enemy_states[enemy_id] = state
		enemy_state_changed.emit(enemy_id, state)

func _apply_enemy_steering(enemy_id: StringName, enemy_node: Node2D, target_position: Vector2) -> void:
	if not enemy_node.has_method("set_ai_command"):
		return

	var heading: Vector2 = Vector2.RIGHT
	if enemy_node.has_method("get_heading"):
		var heading_value: Variant = enemy_node.call("get_heading")
		if heading_value is Vector2 and heading_value != Vector2.ZERO:
			heading = heading_value

	var desired_direction: Vector2 = (target_position - enemy_node.global_position).normalized()
	if desired_direction == Vector2.ZERO:
		desired_direction = heading

	var turn_input: float = clamp(heading.cross(desired_direction) * 6.0, -1.0, 1.0)
	var state: StringName = _enemy_states.get(enemy_id, STATE_PATROL)
	var boost_probability: float = clamp(_ai_float("boost_probability", 0.12) * _boost_scale, 0.0, 1.0)
	var wants_boost: bool = false
	if state == STATE_CHASE or state == STATE_AVOID:
		wants_boost = _rng.randf() <= max(boost_probability, 0.25)
	elif state == STATE_SEEK:
		wants_boost = _rng.randf() <= boost_probability * 0.5

	enemy_node.call("set_ai_command", turn_input, wants_boost)

func _check_world_bounds() -> void:
	var snakes_to_kill: Array[StringName] = []
	for snake_id: StringName in _snake_nodes.keys():
		var snake_node: Node2D = _snake_nodes[snake_id]
		if snake_node.global_position.length() > world_radius:
			snakes_to_kill.append(snake_id)

	for snake_id: StringName in snakes_to_kill:
		kill_snake(snake_id, &"out_of_bounds")

func _check_head_to_head_collision() -> void:
	var snake_ids: Array[StringName] = []
	for snake_id: StringName in _snake_nodes.keys():
		snake_ids.append(snake_id)

	for i: int in range(snake_ids.size()):
		var snake_a_id: StringName = snake_ids[i]
		if not _snake_nodes.has(snake_a_id):
			continue

		for j: int in range(i + 1, snake_ids.size()):
			var snake_b_id: StringName = snake_ids[j]
			if not _snake_nodes.has(snake_b_id):
				continue

			var snake_a_position: Vector2 = _snake_nodes[snake_a_id].global_position
			var snake_b_position: Vector2 = _snake_nodes[snake_b_id].global_position
			if snake_a_position.distance_squared_to(snake_b_position) > 324.0:
				continue

			var length_a: float = _snake_length(snake_a_id)
			var length_b: float = _snake_length(snake_b_id)
			if is_equal_approx(length_a, length_b):
				kill_snake(snake_a_id, &"head_collision")
				kill_snake(snake_b_id, &"head_collision")
			elif length_a > length_b:
				kill_snake(snake_b_id, &"head_collision")
			else:
				kill_snake(snake_a_id, &"head_collision")
			return

func _snake_length(snake_id: StringName) -> float:
	if not _snake_nodes.has(snake_id):
		return 0.0
	if _snake_nodes[snake_id].has_method("get_body_length"):
		var value: Variant = _snake_nodes[snake_id].call("get_body_length")
		if value is float or value is int:
			return float(value)
	return 0.0

func _random_direction() -> Vector2:
	var angle: float = _rng.randf_range(0.0, TAU)
	return Vector2(cos(angle), sin(angle))

func _ai_float(property_name: String, fallback: float) -> float:
	if ai_config == null:
		return fallback
	var value: Variant = ai_config.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback

func _on_snake_node_died(reason: StringName, snake_id: StringName) -> void:
	kill_snake(snake_id, reason)
