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
@export var max_active_food_count: int = 420
@export var spatial_cell_size: float = 220.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_food_id: int = 1
var _active_food: Array[Area2D] = []
var _inactive_food: Array[Area2D] = []
var _food_cells: Dictionary = {}
var _food_cell_lookup: Dictionary = {}

func bootstrap_food() -> void:
	if food_scene == null:
		push_error("food_scene is not assigned on FoodManager.")
		return

	_rng.randomize()
	var bootstrap_count: int = max(initial_food_count, 0)
	if max_active_food_count > 0:
		bootstrap_count = min(bootstrap_count, max_active_food_count)

	_ensure_pool_capacity(bootstrap_count)
	for _i: int in range(bootstrap_count):
		_spawn_food_at_position(_sample_spawn_point(), 1)

func spawn_food_burst(center_position: Vector2, amount: int, ignore_food_cap: bool = false) -> void:
	if amount <= 0:
		push_warning("Food burst amount must be positive.")
		return

	var burst_radius: float = min(spawn_radius * 0.05, 120.0)
	for _i: int in range(amount):
		var offset: Vector2 = Vector2.ZERO if amount == 1 else _random_point_in_radius(burst_radius)
		_spawn_food_at_position(center_position + offset, 1, ignore_food_cap)

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

	if _food_cells.is_empty():
		return nearest_map

	var cell_size: float = max(spatial_cell_size, 1.0)
	var cell_radius: int = max(int(ceil(max_distance / cell_size)), 0)
	for origin_key: Variant in origins.keys():
		var origin_value: Variant = origins.get(origin_key, Vector2.ZERO)
		if origin_value is not Vector2:
			continue

		var origin_position: Vector2 = origin_value as Vector2
		var origin_cell: Vector2i = _cell_from_position(origin_position)
		var best_value_float: float = float(best_distance_squared.get(origin_key, max_distance_squared))
		for x_offset: int in range(-cell_radius, cell_radius + 1):
			for y_offset: int in range(-cell_radius, cell_radius + 1):
				var cell_key: Vector2i = Vector2i(origin_cell.x + x_offset, origin_cell.y + y_offset)
				var cell_bucket_value: Variant = _food_cells.get(cell_key, null)
				if cell_bucket_value is not Array:
					continue

				for food_value: Variant in cell_bucket_value:
					if food_value is not Area2D:
						continue
					var food_node: Area2D = food_value as Area2D
					if not is_instance_valid(food_node) or not food_node.visible:
						continue

					var food_position: Vector2 = food_node.global_position
					var distance_squared: float = origin_position.distance_squared_to(food_position)
					if distance_squared < best_value_float:
						best_value_float = distance_squared
						best_distance_squared[origin_key] = distance_squared
						nearest_map[origin_key] = food_position

	return nearest_map

func get_active_food_count() -> int:
	return _active_food.size()

func _ensure_pool_capacity(target_count: int) -> void:
	var clamped_target: int = max(target_count, 0)
	if max_active_food_count > 0:
		clamped_target = min(clamped_target, max_active_food_count)

	while _active_food.size() + _inactive_food.size() < clamped_target:
		var food_node: Area2D = _create_food_node()
		if food_node == null:
			return
		_inactive_food.append(food_node)

func _spawn_food_at_position(point: Vector2, food_amount: int, ignore_food_cap: bool = false) -> void:
	if not ignore_food_cap and max_active_food_count > 0 and _active_food.size() >= max_active_food_count:
		if _active_food.is_empty():
			return

		var recycled_food: Area2D = _active_food.pop_back()
		if not is_instance_valid(recycled_food):
			return

		var recycled_food_id: int = _next_food_id
		_next_food_id += 1
		_activate_food_node(recycled_food, recycled_food_id, point, food_amount, ignore_food_cap)
		return

	var food_node: Area2D = _acquire_food_node(ignore_food_cap)
	if food_node == null:
		return

	var food_id: int = _next_food_id
	_next_food_id += 1
	_activate_food_node(food_node, food_id, point, food_amount, ignore_food_cap)

func _activate_food_node(food_node: Area2D, food_id: int, point: Vector2, food_amount: int, _ignore_food_cap: bool = false) -> void:
	_untrack_food_node(food_node)
	if food_node.has_method("configure"):
		food_node.call("configure", food_id, point, food_amount)
	else:
		food_node.global_position = point
		food_node.visible = true
		food_node.monitoring = true

	_active_food.append(food_node)
	_track_food_node(food_node)
	food_spawned.emit(food_id, point)

func _acquire_food_node(ignore_food_cap: bool = false) -> Area2D:
	if _inactive_food.is_empty():
		if ignore_food_cap:
			var created_node: Area2D = _create_food_node()
			if created_node != null:
				_inactive_food.append(created_node)
		else:
			_ensure_pool_capacity(_active_food.size() + 1)
		if _inactive_food.is_empty():
			push_error("Unable to allocate food pool node.")
			return null

	return _inactive_food.pop_back()

func _create_food_node() -> Area2D:
	var food_node := food_scene.instantiate() as Area2D
	if food_node == null:
		push_error("food_scene must instantiate to Area2D.")
		return null

	add_child(food_node)
	if food_node.has_signal("consumed"):
		food_node.consumed.connect(_on_food_consumed.bind(food_node))
	else:
		push_error("Food scene script must define signal 'consumed'.")
		food_node.queue_free()
		return null

	if food_node.has_method("deactivate"):
		food_node.call("deactivate")
	return food_node

func _cell_from_position(world_position: Vector2) -> Vector2i:
	var cell_size: float = max(spatial_cell_size, 1.0)
	return Vector2i(
		int(floor(world_position.x / cell_size)),
		int(floor(world_position.y / cell_size))
	)

func _track_food_node(food_node: Area2D) -> void:
	if food_node == null:
		return

	var food_key: int = food_node.get_instance_id()
	var cell_key: Vector2i = _cell_from_position(food_node.global_position)
	var bucket_value: Variant = _food_cells.get(cell_key, [])
	var bucket: Array = []
	if bucket_value is Array:
		bucket = bucket_value
	if not bucket.has(food_node):
		bucket.append(food_node)
	_food_cells[cell_key] = bucket
	_food_cell_lookup[food_key] = cell_key

func _untrack_food_node(food_node: Area2D) -> void:
	if food_node == null:
		return

	var food_key: int = food_node.get_instance_id()
	if not _food_cell_lookup.has(food_key):
		return

	var cell_value: Variant = _food_cell_lookup.get(food_key)
	if cell_value is not Vector2i:
		_food_cell_lookup.erase(food_key)
		return
	var cell_key: Vector2i = cell_value as Vector2i

	var bucket_value: Variant = _food_cells.get(cell_key, [])
	if bucket_value is Array:
		var bucket: Array = bucket_value
		bucket.erase(food_node)
		if bucket.is_empty():
			_food_cells.erase(cell_key)
		else:
			_food_cells[cell_key] = bucket

	_food_cell_lookup.erase(food_key)

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
	_untrack_food_node(food_node)
	if food_node.has_method("deactivate"):
		food_node.call("deactivate")
	else:
		food_node.visible = false
		food_node.monitoring = false

	_inactive_food.append(food_node)
	food_eaten.emit(snake_id, amount)

	if respawn_on_consume:
		_spawn_food_at_position(_sample_spawn_point(), 1)
