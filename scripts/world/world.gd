extends Node2D

signal food_eaten(snake_id: StringName, amount: int)
signal score_changed(snake_id: StringName, score: int)
signal snake_died(snake_id: StringName, reason: StringName)
signal snake_spawned(snake_id: StringName)
signal match_state_changed(state: StringName)

@export var movement_config: Resource
@export var food_config: Resource
@export var ai_config: Resource
@export var camera_follow_lerp_speed: float = 8.0

@onready var snake_manager := $SnakeManager
@onready var food_manager := $FoodManager
@onready var camera_rig: Camera2D = $CameraRig

var _camera_target_snake_id: StringName = &""

func _ready() -> void:
	snake_manager.snake_spawned.connect(_on_snake_spawned)
	snake_manager.snake_died.connect(_on_snake_died)
	snake_manager.score_changed.connect(_on_score_changed)
	food_manager.food_eaten.connect(_on_food_eaten)

	snake_manager.set_movement_config(movement_config)
	if food_config != null:
		food_manager.initial_food_count = food_config.initial_food_count
		food_manager.spawn_radius = food_config.spawn_radius

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

func _on_snake_spawned(snake_id: StringName) -> void:
	snake_spawned.emit(snake_id)
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.register_snake(snake_id)

func _set_match_state(state: StringName) -> void:
	match_state_changed.emit(state)
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.set_match_state(state)
