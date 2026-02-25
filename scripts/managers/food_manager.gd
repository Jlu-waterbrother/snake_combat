extends Node2D
class_name FoodManager

signal food_spawned(food_id: int, world_position: Vector2)
signal food_eaten(snake_id: StringName, amount: int)

@export var food_scene: PackedScene
@export var initial_food_count: int = 64
@export var spawn_radius: float = 1400.0
@export var safe_spawn_radius: float = 180.0
@export var respawn_on_consume: bool = true
@export var spawn_attempts: int = 8

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_food_id: int = 1
var _active_food: Array[Area2D] = []
var _inactive_food: Array[Area2D] = []

func bootstrap_food() -> void:
	if food_scene == null:
		push_error("food_scene is not assigned on FoodManager.")
		return

	_rng.randomize()
	_ensure_pool_capacity(initial_food_count)
	for _i: int in range(initial_food_count):
		_spawn_food_at_position(_sample_spawn_point(), 1)

func spawn_food_burst(center_position: Vector2, amount: int) -> void:
	if amount <= 0:
		push_warning("Food burst amount must be positive.")
		return

	var burst_radius: float = min(spawn_radius * 0.05, 120.0)
	for _i: int in range(amount):
		var offset: Vector2 = _random_point_in_radius(burst_radius)
		_spawn_food_at_position(center_position + offset, 1)

func get_nearest_food_position(origin: Vector2, max_distance: float) -> Vector2:
	var query: Dictionary = {&"single": origin}
	var nearest_map: Dictionary = get_nearest_food_positions(query, max_distance)
	var nearest_value: Variant = nearest_map.get(&"single", Vector2.INF)
	if nearest_value is Vector2:
		return nearest_value
	return Vector2.INF

func get_nearest_food_positions(origins: Dictionary, max_distance: float) -> Dictionary:
	var nearest_map: Dictionary = {}
	if origins.is_empty():
		return nearest_map

	var max_distance_squared: float = max_distance * max_distance
	var best_distance_squared: Dictionary = {}
	for origin_key: Variant in origins.keys():
		nearest_map[origin_key] = Vector2.INF
		best_distance_squared[origin_key] = max_distance_squared

	var active_positions: PackedVector2Array = PackedVector2Array()
	for food_node: Area2D in _active_food:
		if not is_instance_valid(food_node) or not food_node.visible:
			continue
		active_positions.append(food_node.global_position)

	for food_position: Vector2 in active_positions:
		for origin_key: Variant in origins.keys():
			var origin_value: Variant = origins.get(origin_key, Vector2.ZERO)
			if origin_value is not Vector2:
				continue

			var best_value: Variant = best_distance_squared.get(origin_key, max_distance_squared)
			var best_value_float: float = float(best_value)
			var distance_squared: float = (origin_value as Vector2).distance_squared_to(food_position)
			if distance_squared < best_value_float:
				best_distance_squared[origin_key] = distance_squared
				nearest_map[origin_key] = food_position

	return nearest_map

func get_active_food_count() -> int:
	return _active_food.size()

func _ensure_pool_capacity(target_count: int) -> void:
	while _active_food.size() + _inactive_food.size() < target_count:
		var food_node := food_scene.instantiate() as Area2D
		if food_node == null:
			push_error("food_scene must instantiate to Area2D.")
			return

		add_child(food_node)
		if food_node.has_signal("consumed"):
			food_node.consumed.connect(_on_food_consumed.bind(food_node))
		else:
			push_error("Food scene script must define signal 'consumed'.")
			return

		if food_node.has_method("deactivate"):
			food_node.call("deactivate")
		_inactive_food.append(food_node)

func _spawn_food_at_position(point: Vector2, food_amount: int) -> void:
	var food_node: Area2D = _acquire_food_node()
	if food_node == null:
		return

	var food_id: int = _next_food_id
	_next_food_id += 1

	if food_node.has_method("configure"):
		food_node.call("configure", food_id, point, food_amount)
	else:
		food_node.global_position = point
		food_node.visible = true
		food_node.monitoring = true

	_active_food.append(food_node)
	food_spawned.emit(food_id, point)

func _acquire_food_node() -> Area2D:
	if _inactive_food.is_empty():
		_ensure_pool_capacity(_active_food.size() + 1)
		if _inactive_food.is_empty():
			push_error("Unable to allocate food pool node.")
			return null

	return _inactive_food.pop_back()

func _sample_spawn_point() -> Vector2:
	var sampled: Vector2 = Vector2.RIGHT * safe_spawn_radius
	for _attempt: int in range(max(spawn_attempts, 1)):
		sampled = _random_point_in_radius(spawn_radius)
		if sampled.length() >= safe_spawn_radius:
			return sampled

	if sampled == Vector2.ZERO:
		return Vector2.RIGHT * safe_spawn_radius
	return sampled.normalized() * safe_spawn_radius

func _random_point_in_radius(radius_limit: float) -> Vector2:
	var angle: float = _rng.randf_range(0.0, TAU)
	var radius: float = sqrt(_rng.randf()) * radius_limit
	return Vector2(cos(angle), sin(angle)) * radius

func _on_food_consumed(snake_id: StringName, amount: int, food_node: Area2D) -> void:
	if not _active_food.has(food_node):
		return

	_active_food.erase(food_node)
	if food_node.has_method("deactivate"):
		food_node.call("deactivate")
	else:
		food_node.visible = false
		food_node.monitoring = false

	_inactive_food.append(food_node)
	food_eaten.emit(snake_id, amount)

	if respawn_on_consume:
		_spawn_food_at_position(_sample_spawn_point(), 1)
