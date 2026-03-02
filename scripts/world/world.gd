extends Node2D

signal food_eaten(snake_id: StringName, amount: int)
signal score_changed(snake_id: StringName, score: int)
signal snake_died(snake_id: StringName, reason: StringName)
signal snake_spawned(snake_id: StringName)
signal match_state_changed(state: StringName)
signal enemy_state_changed(snake_id: StringName, state: StringName)
signal lives_changed(remaining_lives: int)
signal difficulty_changed(level: int, enemy_target: int)
signal leaderboard_changed(entries: Array[Dictionary])

@export var movement_config: Resource
@export var food_config: Resource
@export var ai_config: Resource
@export var camera_follow_lerp_speed: float = 8.0
@export var world_radius: float = 2200.0
@export var background_color: Color = Color(0.94, 0.98, 0.95, 1.0)
@export var grid_minor_color: Color = Color(0.35, 0.52, 0.42, 0.08)
@export var grid_major_color: Color = Color(0.27, 0.42, 0.33, 0.14)
@export var grid_cell_size: float = 60.0
@export var grid_major_every: int = 5
@export var grid_margin: float = 180.0
@export var boundary_color: Color = Color(1.0, 0.2, 0.2, 0.95)
@export var boundary_inner_color: Color = Color(1.0, 0.6, 0.2, 0.55)
@export var boundary_line_width: float = 16.0
@export var boundary_warning_band: float = 180.0
@export var player_lives: int = 3
@export var difficulty_tick_interval: float = 0.5

@onready var snake_manager := $SnakeManager
@onready var food_manager := $FoodManager
@onready var camera_rig: Camera2D = $CameraRig

var _camera_target_snake_id: StringName = &""
var _remaining_lives: int = 0
var _difficulty_level: int = 0
var _difficulty_check_cooldown: float = 0.0
var _base_enemy_count: int = 0
var _max_enemy_count: int = 0
var _score_per_level: int = 20
var _max_difficulty_level: int = 5
var _base_camera_follow_lerp_speed: float = 8.0
var _pre_pause_state: StringName = &"running"
var _last_leaderboard_signature: String = ""
var _player_mouse_controls_enabled: bool = true

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
	if snake_manager.has_method("set_player_mouse_controls_enabled"):
		snake_manager.call("set_player_mouse_controls_enabled", _player_mouse_controls_enabled)

	if ai_config != null:
		_base_enemy_count = int(max(ai_config.enemy_count, 0))
		_max_enemy_count = int(max(ai_config.max_enemy_count, _base_enemy_count))
		_score_per_level = int(max(ai_config.score_per_difficulty_level, 1))
		_max_difficulty_level = int(max(ai_config.max_difficulty_level, 0))
	else:
		_base_enemy_count = 4
		_max_enemy_count = 8
		_score_per_level = 20
		_max_difficulty_level = 5

	_base_camera_follow_lerp_speed = camera_follow_lerp_speed

	if food_config != null:
		food_manager.initial_food_count = food_config.initial_food_count
		food_manager.spawn_radius = food_config.spawn_radius
		food_manager.safe_spawn_radius = food_config.safe_spawn_radius
		food_manager.respawn_on_consume = food_config.respawn_on_consume

	food_manager.bootstrap_food()
	queue_redraw()

func _draw() -> void:
	var radius: float = max(world_radius, 1.0)
	var extent: float = radius + max(grid_margin, 0.0)
	var background_rect: Rect2 = Rect2(Vector2(-extent, -extent), Vector2(extent * 2.0, extent * 2.0))
	draw_rect(background_rect, background_color, true)

	var cell_size: float = max(grid_cell_size, 12.0)
	var major_step: int = max(grid_major_every, 1)
	var min_grid: int = int(floor(-extent / cell_size))
	var max_grid: int = int(ceil(extent / cell_size))
	for grid_index: int in range(min_grid, max_grid + 1):
		var line_pos: float = float(grid_index) * cell_size
		var line_color: Color = grid_major_color if posmod(grid_index, major_step) == 0 else grid_minor_color
		draw_line(Vector2(line_pos, -extent), Vector2(line_pos, extent), line_color, 1.0, true)
		draw_line(Vector2(-extent, line_pos), Vector2(extent, line_pos), line_color, 1.0, true)

	var line_width: float = max(boundary_line_width, 2.0)
	var warning_radius: float = max(radius - max(boundary_warning_band, 0.0), line_width)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 256, boundary_color, line_width, true)
	draw_arc(Vector2.ZERO, warning_radius, 0.0, TAU, 256, boundary_inner_color, max(line_width * 0.5, 2.0), true)

func _physics_process(delta: float) -> void:
	_update_dynamic_difficulty(delta)
	_emit_leaderboard_if_changed()

	if _camera_target_snake_id == &"":
		return
	if not snake_manager.has_snake(_camera_target_snake_id):
		return

	var target_position: Vector2 = snake_manager.get_snake_position(_camera_target_snake_id)
	var follow_weight: float = clamp(camera_follow_lerp_speed * delta, 0.0, 1.0)
	camera_rig.global_position = camera_rig.global_position.lerp(target_position, follow_weight)

func start_match() -> void:
	_last_leaderboard_signature = ""
	_remaining_lives = max(player_lives, 1)
	lives_changed.emit(_remaining_lives)

	_difficulty_level = 0
	_difficulty_check_cooldown = 0.0
	snake_manager.set_target_enemy_count(_base_enemy_count)
	snake_manager.set_ai_difficulty_scalars(1.0, 1.0)
	difficulty_changed.emit(_difficulty_level, _base_enemy_count)

	var player_snake_id: StringName = snake_manager.spawn_player_snake()
	if player_snake_id == &"":
		push_error("Failed to spawn player snake.")
		_set_match_state(&"ended")
		return

	snake_manager.spawn_enemy_snakes(_base_enemy_count)
	_camera_target_snake_id = player_snake_id
	_set_match_state(&"running")
	_emit_leaderboard_if_changed()

func stop_match() -> void:
	_camera_target_snake_id = &""
	_set_match_state(&"stopped")
	_emit_leaderboard_if_changed()

func set_pause_state(paused: bool) -> void:
	if paused:
		_set_match_state(&"paused")
		return

	if _pre_pause_state == &"paused":
		_set_match_state(&"running")
		return
	_set_match_state(_pre_pause_state)

func set_player_skin(skin: Resource) -> void:
	if snake_manager == null:
		return
	snake_manager.player_skin = skin

func get_player_skin() -> Resource:
	if snake_manager == null:
		return null
	return snake_manager.player_skin

func set_player_mouse_controls_enabled(enabled: bool) -> void:
	_player_mouse_controls_enabled = enabled
	if snake_manager != null and snake_manager.has_method("set_player_mouse_controls_enabled"):
		snake_manager.call("set_player_mouse_controls_enabled", _player_mouse_controls_enabled)

func get_player_mouse_controls_enabled() -> bool:
	return _player_mouse_controls_enabled

func _update_dynamic_difficulty(delta: float) -> void:
	if _camera_target_snake_id == &"":
		return
	if not snake_manager.has_snake(_camera_target_snake_id):
		return

	_difficulty_check_cooldown -= delta
	if _difficulty_check_cooldown > 0.0:
		return
	_difficulty_check_cooldown = max(difficulty_tick_interval, 0.1)

	var player_score: int = snake_manager.get_score(_camera_target_snake_id)
	var raw_level: int = int(player_score / max(_score_per_level, 1))
	var new_level: int = clampi(raw_level, 0, _max_difficulty_level)
	if new_level == _difficulty_level:
		return

	_difficulty_level = new_level
	var target_enemy_count: int = clampi(_base_enemy_count + _difficulty_level, 0, _max_enemy_count)
	snake_manager.set_target_enemy_count(target_enemy_count)

	var normalized_level: float = 0.0
	if _max_difficulty_level > 0:
		normalized_level = float(_difficulty_level) / float(_max_difficulty_level)
	snake_manager.set_ai_difficulty_scalars(1.0 + normalized_level * 0.6, 1.0 + normalized_level * 0.5)
	camera_follow_lerp_speed = lerp(_base_camera_follow_lerp_speed, _base_camera_follow_lerp_speed + 3.0, normalized_level)
	difficulty_changed.emit(_difficulty_level, target_enemy_count)

func get_leaderboard_entries() -> Array[Dictionary]:
	if snake_manager == null or not snake_manager.has_method("get_leaderboard_entries"):
		return []

	var entries_value: Variant = snake_manager.call("get_leaderboard_entries")
	var entries: Array[Dictionary] = []
	if entries_value is Array:
		for entry_value: Variant in entries_value:
			if entry_value is Dictionary:
				entries.append(entry_value)
	return entries

func _emit_leaderboard_if_changed() -> void:
	var entries: Array[Dictionary] = get_leaderboard_entries()
	var signature_parts: PackedStringArray = PackedStringArray()
	for entry: Dictionary in entries:
		var snake_id: String = String(entry.get("snake_id", ""))
		var length_value: float = float(entry.get("length", 0.0))
		signature_parts.append("%s:%.2f" % [snake_id, length_value])

	var signature: String = "|".join(signature_parts)
	if signature == _last_leaderboard_signature:
		return

	_last_leaderboard_signature = signature
	leaderboard_changed.emit(entries)

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
		_remaining_lives = max(_remaining_lives - 1, 0)
		lives_changed.emit(_remaining_lives)
		if _remaining_lives <= 0:
			_set_match_state(&"ended")
			return
		_set_match_state(&"respawning")
		call_deferred("_respawn_player")

func _on_snake_mass_dropped(world_position: Vector2, amount: int, bypass_food_cap: bool, drop_kind: StringName, drop_color: Color) -> void:
	var split_into_units: bool = drop_kind != &"defeat"
	food_manager.spawn_food_burst(world_position, amount, bypass_food_cap, split_into_units, drop_color)

func _on_snake_spawned(snake_id: StringName) -> void:
	snake_spawned.emit(snake_id)
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.register_snake(snake_id)

func _on_enemy_state_changed(snake_id: StringName, state: StringName) -> void:
	enemy_state_changed.emit(snake_id, state)

func _set_match_state(state: StringName) -> void:
	if state != &"paused":
		_pre_pause_state = state
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
	snake_manager.grant_player_respawn_invincibility()
	_set_match_state(&"running")
