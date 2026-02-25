extends Node2D

signal food_eaten(snake_id: StringName, amount: int)
signal score_changed(snake_id: StringName, score: int)
signal snake_died(snake_id: StringName, reason: StringName)
signal snake_spawned(snake_id: StringName)
signal match_state_changed(state: StringName)
signal enemy_state_changed(snake_id: StringName, state: StringName)

@export var movement_config: Resource
@export var food_config: Resource
@export var ai_config: Resource
@export var camera_follow_lerp_speed: float = 8.0
@export var world_radius: float = 2200.0

@onready var snake_manager := $SnakeManager
@onready var food_manager := $FoodManager
@onready var camera_rig: Camera2D = $CameraRig

var _camera_target_snake_id: StringName = &""

func _ready() -> void:
	snake_manager.snake_spawned.connect(_on_snake_spawned)
	snake_manager.snake_died.connect(_on_snake_died)
	snake_manager.snake_mass_dropped.connect(_on_snake_mass_dropped)
	snake_manager.score_changed.connect(_on_score_changed)
	snake_manager.enemy_state_changed.connect(_on_enemy_state_changed)
	food_manager.food_eaten.connect(_on_food_eaten)

	snake_manager.set_movement_config(movement_config)
	snake_manager.set_ai_config(ai_config)
	snake_manager.set_food_manager(food_manager)
	snake_manager.set_world_radius(world_radius)

	if food_config != null:
		food_manager.initial_food_count = food_config.initial_food_count
		food_manager.spawn_radius = food_config.spawn_radius
		food_manager.safe_spawn_radius = food_config.safe_spawn_radius
		food_manager.respawn_on_consume = food_config.respawn_on_consume

	food_manager.bootstrap_food()

func _physics_process(delta: float) -> void:
	if _camera_target_snake_id == &"":
		return
	if not snake_manager.has_snake(_camera_target_snake_id):
		return

	var target_position: Vector2 = snake_manager.get_snake_position(_camera_target_snake_id)
	var follow_weight: float = clamp(camera_follow_lerp_speed * delta, 0.0, 1.0)
	camera_rig.global_position = camera_rig.global_position.lerp(target_position, follow_weight)

func start_match() -> void:
	var player_snake_id: StringName = snake_manager.spawn_player_snake()
	if player_snake_id == &"":
		push_error("Failed to spawn player snake.")
		return

	var enemy_count: int = 0
	if ai_config != null:
		enemy_count = int(max(ai_config.enemy_count, 0))
	snake_manager.spawn_enemy_snakes(enemy_count)

	_camera_target_snake_id = player_snake_id
	_set_match_state(&"running")

func stop_match() -> void:
	_camera_target_snake_id = &""
	_set_match_state(&"stopped")

func _on_food_eaten(snake_id: StringName, amount: int) -> void:
	food_eaten.emit(snake_id, amount)
	snake_manager.apply_food_gain(snake_id, amount)

func _on_score_changed(snake_id: StringName, score: int) -> void:
	score_changed.emit(snake_id, score)
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.set_score(snake_id, score)

func _on_snake_died(snake_id: StringName, reason: StringName) -> void:
	snake_died.emit(snake_id, reason)
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null and game_state.has_method("unregister_snake"):
		game_state.unregister_snake(snake_id)

	if snake_id == _camera_target_snake_id:
		_camera_target_snake_id = &""
		_set_match_state(&"respawning")
		call_deferred("_respawn_player")

func _on_snake_mass_dropped(world_position: Vector2, amount: int) -> void:
	food_manager.spawn_food_burst(world_position, amount)

func _on_snake_spawned(snake_id: StringName) -> void:
	snake_spawned.emit(snake_id)
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.register_snake(snake_id)

func _on_enemy_state_changed(snake_id: StringName, state: StringName) -> void:
	enemy_state_changed.emit(snake_id, state)

func _set_match_state(state: StringName) -> void:
	match_state_changed.emit(state)
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.set_match_state(state)

func _respawn_player() -> void:
	var player_snake_id: StringName = snake_manager.spawn_player_snake()
	if player_snake_id == &"":
		_set_match_state(&"ended")
		return

	_camera_target_snake_id = player_snake_id
	_set_match_state(&"running")
