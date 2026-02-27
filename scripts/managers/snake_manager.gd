extends Node
class_name SnakeManager

signal snake_spawned(snake_id: StringName)
signal snake_died(snake_id: StringName, reason: StringName)
signal snake_mass_dropped(world_position: Vector2, amount: int, bypass_food_cap: bool)
signal score_changed(snake_id: StringName, score: int)
signal enemy_state_changed(snake_id: StringName, state: StringName)

@export var player_snake_scene: PackedScene
@export var enemy_snake_scene: PackedScene
@export var movement_config: Resource
@export var ai_config: Resource
@export var player_skin: Resource
@export var enemy_skin: Resource
@export var growth_per_food: float = 8.0
@export var enemy_spawn_radius_min: float = 420.0
@export var enemy_spawn_radius_max: float = 980.0
@export var enemy_spawn_attempts: int = 24
@export var enemy_spawn_player_safe_radius: float = 420.0
@export var enemy_spawn_front_block_dot: float = 0.2
@export var player_respawn_invincibility_seconds: float = 3.0
@export var world_radius: float = 2200.0
@export var head_to_body_collision_radius: float = 8.0
@export var head_to_body_ignore_points: int = 4
@export var head_to_body_sample_step: int = 2

const STATE_PATROL: StringName = &"patrol"
const STATE_SEEK: StringName = &"seek"
const STATE_CHASE: StringName = &"chase"
const STATE_AVOID: StringName = &"avoid"
const ENEMY_NAME_POOL := [
	"Viper",
	"Cobra",
	"Mamba",
	"Krait",
	"Asp",
	"Adder",
	"Fang",
	"Razor",
	"Ember",
	"Riptide",
	"Nova",
	"Storm",
	"Blaze",
	"Echo",
	"Comet",
	"Zephyr",
	"Spike",
	"Shadow",
]

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
var _shed_length_remainder: Dictionary[StringName, float] = {}
var _invincibility_remaining: Dictionary[StringName, float] = {}
var _snake_display_names: Dictionary[StringName, String] = {}

func _ready() -> void:
	_rng.randomize()

func _physics_process(delta: float) -> void:
	_update_invincibility(delta)
	_update_enemy_ai(delta)
	_check_world_bounds()
	_check_head_to_head_collision()
	_check_head_to_body_collision()

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
	if reason != &"despawned" and _is_snake_invincible(snake_id):
		return

	var allow_mass_drop: bool = reason != &"despawned"
	var was_enemy: bool = _enemy_ids.has(snake_id)
	var drop_position: Vector2 = Vector2.ZERO
	var drop_amount: int = 0
	var drop_points: PackedVector2Array = PackedVector2Array()
	if _snake_nodes.has(snake_id):
		var snake_node: Node2D = _snake_nodes[snake_id]
		drop_position = snake_node.global_position
		if allow_mass_drop and snake_node.has_method("get_body_length"):
			var body_length_value: Variant = snake_node.call("get_body_length")
			if body_length_value is float or body_length_value is int:
				var growth_unit: float = max(growth_per_food, 1.0)
				drop_amount = int(max(round(float(body_length_value) / growth_unit), 4.0))
		if allow_mass_drop and snake_node.has_method("get_body_points"):
			var drop_points_value: Variant = snake_node.call("get_body_points")
			if drop_points_value is PackedVector2Array:
				drop_points = drop_points_value

		snake_node.queue_free()
		_snake_nodes.erase(snake_id)

	_scores.erase(snake_id)
	_shed_length_remainder.erase(snake_id)
	_invincibility_remaining.erase(snake_id)
	_snake_display_names.erase(snake_id)
	if snake_id == _player_snake_id:
		_player_snake_id = &""
	if was_enemy:
		_enemy_ids.erase(snake_id)
		_enemy_states.erase(snake_id)
		_enemy_targets.erase(snake_id)
		_enemy_retarget_cooldown.erase(snake_id)

	if allow_mass_drop and drop_amount > 0:
		_emit_mass_drop(drop_points, drop_position, drop_amount)

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

func get_leaderboard_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for snake_id: StringName in _snake_nodes.keys():
		entries.append({
			"snake_id": snake_id,
			"name": _snake_display_names.get(snake_id, String(snake_id)),
			"length": _snake_length(snake_id),
			"is_player": snake_id == _player_snake_id,
		})

	entries.sort_custom(_sort_leaderboard_entries)
	return entries

func set_temporary_invincibility(snake_id: StringName, duration_seconds: float) -> void:
	if not _snake_nodes.has(snake_id):
		return
	var duration: float = max(duration_seconds, 0.0)
	if duration <= 0.0:
		_invincibility_remaining.erase(snake_id)
		return
	_invincibility_remaining[snake_id] = duration

func grant_player_respawn_invincibility() -> void:
	if _player_snake_id == &"":
		return
	set_temporary_invincibility(_player_snake_id, player_respawn_invincibility_seconds)

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

	var applied_skin: bool = false
	if snake_node.has_method("set_skin"):
		var selected_skin: Resource = enemy_skin if is_enemy else player_skin
		if selected_skin != null:
			snake_node.call("set_skin", selected_skin)
			applied_skin = true
	if snake_node.has_method("set_movement_config"):
		snake_node.call("set_movement_config", movement_config)
	if snake_node.has_method("set_snake_id"):
		snake_node.call("set_snake_id", snake_id)
	if snake_node.has_method("set_control_mode"):
		snake_node.call("set_control_mode", 1 if is_enemy else 0)
	if snake_node.has_method("set_head_color") and is_enemy and not applied_skin:
		snake_node.call("set_head_color", Color(0.97, 0.27, 0.31))
	if snake_node.has_signal("snake_died"):
		snake_node.snake_died.connect(_on_snake_node_died.bind(snake_id))
	if snake_node.has_signal("mass_shed"):
		snake_node.mass_shed.connect(_on_snake_mass_shed.bind(snake_id))

	add_child(snake_node)
	snake_node.global_position = spawn_position
	_snake_nodes[snake_id] = snake_node
	_scores[snake_id] = 0
	_shed_length_remainder[snake_id] = 0.0
	_snake_display_names[snake_id] = _generate_enemy_name() if is_enemy else "Player"
	return true

func _sample_enemy_spawn_position() -> Vector2:
	var min_radius: float = max(enemy_spawn_radius_min, 120.0)
	var max_radius: float = max(enemy_spawn_radius_max, min_radius + 1.0)
	var has_player: bool = _player_snake_id != &"" and _snake_nodes.has(_player_snake_id)
	var player_position: Vector2 = Vector2.ZERO
	var player_heading: Vector2 = Vector2.RIGHT
	if has_player:
		player_position = _snake_nodes[_player_snake_id].global_position
		if _snake_nodes[_player_snake_id].has_method("get_heading"):
			var heading_value: Variant = _snake_nodes[_player_snake_id].call("get_heading")
			if heading_value is Vector2 and (heading_value as Vector2) != Vector2.ZERO:
				player_heading = (heading_value as Vector2).normalized()

	var front_dot_limit: float = clamp(enemy_spawn_front_block_dot, -1.0, 1.0)
	var safe_radius: float = max(enemy_spawn_player_safe_radius, 0.0)
	for _attempt: int in range(max(enemy_spawn_attempts, 1)):
		var candidate: Vector2 = _sample_ring_spawn_position(min_radius, max_radius)
		if not has_player:
			return candidate

		var to_candidate: Vector2 = candidate - player_position
		if to_candidate.length() < safe_radius:
			continue
		if to_candidate == Vector2.ZERO:
			continue
		if to_candidate.normalized().dot(player_heading) > front_dot_limit:
			continue
		return candidate

	if not has_player:
		return _sample_ring_spawn_position(min_radius, max_radius)

	var fallback_heading: Vector2 = -player_heading
	if fallback_heading == Vector2.ZERO:
		fallback_heading = _random_direction()
	var fallback_distance: float = max(safe_radius, min_radius)
	var fallback_point: Vector2 = player_position + fallback_heading.normalized() * fallback_distance
	var max_world_radius: float = max(world_radius - 40.0, 120.0)
	if fallback_point.length() > max_world_radius:
		fallback_point = fallback_point.normalized() * max_world_radius
	return fallback_point

func _sample_ring_spawn_position(min_radius: float, max_radius: float) -> Vector2:
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
	var avoid_margin: float = max(_ai_float("avoid_boundary_margin", 220.0), 40.0)
	if enemy_position.length() >= world_radius * avoid_ratio or enemy_position.length() >= world_radius - avoid_margin:
		state = STATE_AVOID
		target = Vector2.ZERO
	else:
		var aggression: float = clamp(_ai_float("aggression", 0.45) * _aggression_scale, 0.0, 1.0)
		var should_chase: bool = false
		if has_player:
			var player_distance: float = enemy_position.distance_to(player_position)
			if player_distance <= vision_radius:
				var enemy_length: float = _snake_length(enemy_id)
				var player_length: float = _snake_length(_player_snake_id)
				var caution_ratio: float = max(_ai_float("caution_length_ratio", 1.05), 0.3)
				var avoid_distance: float = max(_ai_float("head_on_avoid_distance", 200.0), 40.0)
				var is_outmatched: bool = enemy_length < player_length * caution_ratio
				if is_outmatched and player_distance <= avoid_distance:
					state = STATE_AVOID
					var away_direction: Vector2 = (enemy_position - player_position).normalized()
					if away_direction == Vector2.ZERO:
						away_direction = _random_direction()
					target = enemy_position + away_direction * min(vision_radius, 280.0)
				else:
					should_chase = _rng.randf() <= aggression

		if state != STATE_AVOID and should_chase and has_player:
			state = STATE_CHASE
			var predict_seconds: float = clamp(_ai_float("chase_predict_seconds", 0.35), 0.0, 1.2)
			var predicted_position: Vector2 = player_position + _player_heading() * _movement_float("base_speed", 123.75) * predict_seconds
			target = predicted_position
		elif state != STATE_AVOID and nearest_food.is_finite():
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

	var turn_scale: float = max(_ai_float("turn_responsiveness", 4.2), 0.5)
	var turn_input: float = clamp(heading.cross(desired_direction) * turn_scale, -1.0, 1.0)
	var hazard_avoid_turn: float = _compute_hazard_avoid_turn(enemy_id, enemy_node)
	if abs(hazard_avoid_turn) > 0.001:
		turn_input = hazard_avoid_turn

	var state: StringName = _enemy_states.get(enemy_id, STATE_PATROL)
	var boost_probability: float = clamp(_ai_float("boost_probability", 0.12) * _boost_scale, 0.0, 1.0)
	var wants_boost: bool = false
	if abs(hazard_avoid_turn) > 0.001:
		wants_boost = false
		if state != STATE_AVOID:
			_enemy_states[enemy_id] = STATE_AVOID
			enemy_state_changed.emit(enemy_id, STATE_AVOID)
		state = STATE_AVOID
	elif state == STATE_CHASE:
		wants_boost = _rng.randf() <= max(boost_probability * 0.8, 0.12)
	elif state == STATE_AVOID:
		wants_boost = _rng.randf() <= boost_probability * 0.2
	elif state == STATE_SEEK:
		wants_boost = _rng.randf() <= boost_probability * 0.4

	enemy_node.call("set_ai_command", turn_input, wants_boost)

func _check_world_bounds() -> void:
	var snakes_to_kill: Array[StringName] = []
	for snake_id: StringName in _snake_nodes.keys():
		var snake_node: Node2D = _snake_nodes[snake_id]
		var head_radius: float = _snake_head_radius(snake_id)
		if snake_node.global_position.length() + head_radius >= world_radius:
			snakes_to_kill.append(snake_id)

	for snake_id: StringName in snakes_to_kill:
		kill_snake(snake_id, &"out_of_bounds")

func _check_head_to_body_collision() -> void:
	var snake_ids: Array[StringName] = []
	for snake_id: StringName in _snake_nodes.keys():
		snake_ids.append(snake_id)

	for attacker_id: StringName in snake_ids:
		if not _snake_nodes.has(attacker_id):
			continue
		var attacker_node: Node2D = _snake_nodes[attacker_id]
		var head_position: Vector2 = attacker_node.global_position

		for defender_id: StringName in snake_ids:
			if attacker_id == defender_id:
				continue
			if not _snake_nodes.has(defender_id):
				continue

			var defender_node: Node2D = _snake_nodes[defender_id]
			if not defender_node.has_method("collides_with_body"):
				continue

			var collided_value: Variant = defender_node.call(
				"collides_with_body",
				head_position,
				head_to_body_collision_radius,
				head_to_body_ignore_points,
				head_to_body_sample_step
			)
			if collided_value is bool and collided_value:
				kill_snake(attacker_id, &"body_collision")
				return

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

func _snake_head_radius(snake_id: StringName) -> float:
	if not _snake_nodes.has(snake_id):
		return 0.0
	if _snake_nodes[snake_id].has_method("get_head_radius"):
		var value: Variant = _snake_nodes[snake_id].call("get_head_radius")
		if value is float or value is int:
			return max(float(value), 0.0)
	return 0.0

func _player_heading() -> Vector2:
	if _player_snake_id == &"" or not _snake_nodes.has(_player_snake_id):
		return Vector2.RIGHT
	var player_node: Node2D = _snake_nodes[_player_snake_id]
	if player_node.has_method("get_heading"):
		var heading_value: Variant = player_node.call("get_heading")
		if heading_value is Vector2 and (heading_value as Vector2) != Vector2.ZERO:
			return (heading_value as Vector2).normalized()
	return Vector2.RIGHT

func _compute_hazard_avoid_turn(enemy_id: StringName, enemy_node: Node2D) -> float:
	var heading: Vector2 = Vector2.RIGHT
	if enemy_node.has_method("get_heading"):
		var heading_value: Variant = enemy_node.call("get_heading")
		if heading_value is Vector2 and (heading_value as Vector2) != Vector2.ZERO:
			heading = (heading_value as Vector2).normalized()

	var probe_distance: float = max(_ai_float("hazard_probe_distance", 180.0), 40.0)
	var probe_angle: float = deg_to_rad(clamp(_ai_float("hazard_probe_angle_deg", 28.0), 5.0, 80.0))
	var forward_probe: Vector2 = enemy_node.global_position + heading * probe_distance
	if not _is_probe_position_dangerous(enemy_id, forward_probe):
		return 0.0

	var left_probe: Vector2 = enemy_node.global_position + heading.rotated(probe_angle) * probe_distance
	var right_probe: Vector2 = enemy_node.global_position + heading.rotated(-probe_angle) * probe_distance
	var left_danger: bool = _is_probe_position_dangerous(enemy_id, left_probe)
	var right_danger: bool = _is_probe_position_dangerous(enemy_id, right_probe)
	if left_danger and not right_danger:
		return -1.0
	if right_danger and not left_danger:
		return 1.0

	var toward_center: Vector2 = (-enemy_node.global_position).normalized()
	if toward_center == Vector2.ZERO:
		return 1.0
	return clamp(heading.cross(toward_center) * 4.0, -1.0, 1.0)

func _is_probe_position_dangerous(attacker_id: StringName, probe_position: Vector2) -> bool:
	var boundary_margin: float = max(_ai_float("avoid_boundary_margin", 220.0), 40.0)
	if probe_position.length() >= world_radius - boundary_margin:
		return true

	var max_check_distance: float = max(_ai_float("hazard_probe_distance", 180.0) * 2.5, 220.0)
	var max_check_distance_squared: float = max_check_distance * max_check_distance
	var probe_radius: float = max(head_to_body_collision_radius, 1.0)
	for snake_id: StringName in _snake_nodes.keys():
		if snake_id == attacker_id:
			continue

		var snake_node: Node2D = _snake_nodes[snake_id]
		var head_distance_squared: float = snake_node.global_position.distance_squared_to(probe_position)
		if head_distance_squared > max_check_distance_squared:
			continue

		var threat_head_radius: float = _snake_head_radius(snake_id) + probe_radius
		if head_distance_squared <= threat_head_radius * threat_head_radius:
			return true

		if snake_node.has_method("collides_with_body"):
			var collided_value: Variant = snake_node.call(
				"collides_with_body",
				probe_position,
				probe_radius,
				head_to_body_ignore_points,
				head_to_body_sample_step
			)
			if collided_value is bool and collided_value:
				return true

	return false

func _sort_leaderboard_entries(a: Dictionary, b: Dictionary) -> bool:
	var length_a: float = float(a.get("length", 0.0))
	var length_b: float = float(b.get("length", 0.0))
	if is_equal_approx(length_a, length_b):
		var name_a: String = String(a.get("name", ""))
		var name_b: String = String(b.get("name", ""))
		return name_a < name_b
	return length_a > length_b

func _generate_enemy_name() -> String:
	if ENEMY_NAME_POOL.is_empty():
		return "Enemy-%03d" % _rng.randi_range(0, 999)

	var attempts: int = max(ENEMY_NAME_POOL.size() * 2, 8)
	for _attempt: int in range(attempts):
		var pool_index: int = _rng.randi_range(0, ENEMY_NAME_POOL.size() - 1)
		var base_name: String = ENEMY_NAME_POOL[pool_index]
		var candidate: String = "%s-%02d" % [base_name, _rng.randi_range(0, 99)]
		if not _snake_display_names.values().has(candidate):
			return candidate

	return "%s-%03d" % [ENEMY_NAME_POOL[0], _rng.randi_range(100, 999)]

func _update_invincibility(delta: float) -> void:
	if _invincibility_remaining.is_empty():
		return

	var expired_ids: Array[StringName] = []
	for snake_id: StringName in _invincibility_remaining.keys():
		if not _snake_nodes.has(snake_id):
			expired_ids.append(snake_id)
			continue

		var remaining: float = float(_invincibility_remaining.get(snake_id, 0.0)) - delta
		if remaining <= 0.0:
			expired_ids.append(snake_id)
		else:
			_invincibility_remaining[snake_id] = remaining

	for snake_id: StringName in expired_ids:
		_invincibility_remaining.erase(snake_id)

func _is_snake_invincible(snake_id: StringName) -> bool:
	var remaining: float = float(_invincibility_remaining.get(snake_id, 0.0))
	return remaining > 0.0

func _emit_mass_drop(drop_points: PackedVector2Array, fallback_position: Vector2, total_amount: int) -> void:
	if total_amount <= 0:
		return
	if drop_points.is_empty():
		snake_mass_dropped.emit(fallback_position, total_amount, true)
		return

	var point_count: int = min(drop_points.size(), total_amount)
	if point_count <= 0:
		snake_mass_dropped.emit(fallback_position, total_amount, true)
		return

	var denominator: float = float(max(point_count - 1, 1))
	var max_index: int = drop_points.size() - 1
	var base_amount: int = int(total_amount / point_count)
	var remainder: int = total_amount % point_count

	for i: int in range(point_count):
		var ratio: float = float(i) / denominator
		var point_index: int = int(round(ratio * float(max_index)))
		point_index = clampi(point_index, 0, max_index)
		var amount: int = base_amount + (1 if i < remainder else 0)
		if amount > 0:
			snake_mass_dropped.emit(drop_points[point_index], amount, true)

func _on_snake_mass_shed(world_position: Vector2, consumed_length: float, snake_id: StringName) -> void:
	if consumed_length <= 0.0:
		return
	if not _scores.has(snake_id):
		return

	var growth_unit: float = max(growth_per_food, 1.0)
	var accumulated_length: float = _shed_length_remainder.get(snake_id, 0.0) + consumed_length
	var drop_amount: int = int(floor(accumulated_length / growth_unit))
	_shed_length_remainder[snake_id] = accumulated_length - float(drop_amount) * growth_unit

	if drop_amount > 0:
		snake_mass_dropped.emit(world_position, drop_amount, false)

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

func _movement_float(property_name: String, fallback: float) -> float:
	if movement_config == null:
		return fallback
	var value: Variant = movement_config.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback

func _on_snake_node_died(reason: StringName, snake_id: StringName) -> void:
	kill_snake(snake_id, reason)
