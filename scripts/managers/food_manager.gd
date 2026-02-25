extends Node2D
class_name FoodManager

signal food_spawned(food_id: int, world_position: Vector2)
signal food_eaten(snake_id: StringName, amount: int)

@export var initial_food_count: int = 64
@export var spawn_radius: float = 1400.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_food_id: int = 1

func bootstrap_food() -> void:
	_rng.randomize()
	for _i: int in range(initial_food_count):
		_spawn_food_point()

func notify_food_eaten(snake_id: StringName, amount: int = 1) -> void:
	if amount <= 0:
		push_warning("Food amount must be positive when eaten.")
		return
	food_eaten.emit(snake_id, amount)

func _spawn_food_point() -> void:
	var angle: float = _rng.randf_range(0.0, TAU)
	var radius: float = sqrt(_rng.randf()) * spawn_radius
	var point: Vector2 = Vector2(cos(angle), sin(angle)) * radius

	food_spawned.emit(_next_food_id, point)
	_next_food_id += 1
