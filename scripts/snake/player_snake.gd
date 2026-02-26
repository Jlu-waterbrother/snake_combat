extends Node2D

signal snake_died(reason: StringName)

enum ControlMode {
	PLAYER,
	AI,
}

@export var movement_config: Resource
@export var default_base_speed: float = 220.0
@export var default_boost_speed: float = 340.0
@export var default_turn_rate_deg_per_second: float = 300.0
@export var default_segment_spacing: float = 10.0
@export var body_length: float = 180.0
@export var initial_heading: Vector2 = Vector2.RIGHT
@export var head_radius: float = 10.0
@export var head_color: Color = Color(0.22, 0.84, 0.31)
@export var self_collision_radius: float = 9.0
@export var self_collision_min_body_length: float = 260.0
@export var self_collision_sample_step: int = 2
@export var control_mode: ControlMode = ControlMode.PLAYER

@onready var body_line: Line2D = $BodyLine
@onready var head_area: Area2D = $HeadArea
@onready var head_collision_shape: CollisionShape2D = $HeadArea/CollisionShape2D

var snake_id: StringName = &"player"
var _heading: Vector2 = Vector2.RIGHT
var _trail_points: Array[Vector2] = []
var _segment_spacing: float = 10.0
var _is_dead: bool = false
var _ai_turn_input: float = 0.0
var _ai_boosting: bool = false

func _ready() -> void:
	_heading = initial_heading.normalized()
	if _heading == Vector2.ZERO:
		_heading = Vector2.RIGHT

	head_area.collision_layer = 4
	head_area.collision_mask = 8
	head_area.add_to_group("snake_head")
	_sync_head_collision()
	_sync_body_style()

	_trail_points = [global_position - _heading * body_length, global_position]
	_sync_body_line()
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, head_radius, head_color)

func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	var base_speed_raw: float = _config_number("base_speed", default_base_speed)
	var boost_speed_raw: float = _config_number("boost_speed", default_boost_speed)
	var turn_rate_deg: float = _config_number("turn_rate_deg_per_second", default_turn_rate_deg_per_second)
	_segment_spacing = max(_config_number("segment_spacing", default_segment_spacing), 1.0)

	var growth_ratio: float = max(body_length / 180.0, 1.0)
	var base_speed: float = base_speed_raw / (1.0 + (growth_ratio - 1.0) * 0.15)
	var boost_speed: float = boost_speed_raw / (1.0 + (growth_ratio - 1.0) * 0.1)

	var turn_input: float = _read_turn_input()
	_heading = _heading.rotated(deg_to_rad(turn_rate_deg) * turn_input * delta).normalized()

	var speed: float = boost_speed if _wants_boost() else base_speed
	global_position += _heading * speed * delta

	_append_trail_point(global_position)
	_trim_trail_to_length(body_length)
	_sync_body_line()

	if _detect_self_collision():
		_is_dead = true
		snake_died.emit(&"self_collision")

func set_movement_config(config: Resource) -> void:
	movement_config = config

func set_control_mode(mode: int) -> void:
	if mode != ControlMode.PLAYER and mode != ControlMode.AI:
		push_warning("Unsupported control mode for snake: %s" % mode)
		return
	control_mode = mode

func set_ai_command(turn_input: float, boosting: bool) -> void:
	_ai_turn_input = clamp(turn_input, -1.0, 1.0)
	_ai_boosting = boosting

func set_snake_id(new_snake_id: StringName) -> void:
	snake_id = new_snake_id
	var head := get_node_or_null("HeadArea") as Area2D
	if head != null:
		head.set_meta("snake_id", String(snake_id))

func set_head_color(new_head_color: Color) -> void:
	head_color = new_head_color
	if is_inside_tree():
		_sync_body_style()
		queue_redraw()

func grow_by(length_delta: float) -> void:
	if length_delta <= 0.0:
		push_warning("Snake growth delta must be positive.")
		return
	body_length += length_delta

func get_body_length() -> float:
	return body_length

func get_body_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for trail_point: Vector2 in _trail_points:
		points.append(trail_point)
	return points

func get_heading() -> Vector2:
	return _heading

func get_body_collision_radius() -> float:
	if body_line == null:
		return head_radius
	return max(body_line.width * 0.5, head_radius * 0.7)

func collides_with_body(point: Vector2, other_radius: float, ignore_points_from_head: int = 4, sample_step: int = 1) -> bool:
	if _trail_points.size() < 3:
		return false

	var collision_radius: float = get_body_collision_radius() + max(other_radius, 0.0)
	var threshold_squared: float = collision_radius * collision_radius
	var max_index: int = _trail_points.size() - max(ignore_points_from_head, 0)
	if max_index <= 0:
		return false

	var step: int = max(sample_step, 1)
	for i: int in range(0, max_index, step):
		if _trail_points[i].distance_squared_to(point) <= threshold_squared:
			return true
	return false

func _read_turn_input() -> float:
	if control_mode == ControlMode.AI:
		return _ai_turn_input
	return Input.get_axis("turn_left", "turn_right")

func _wants_boost() -> bool:
	if control_mode == ControlMode.AI:
		return _ai_boosting
	return Input.is_action_pressed("boost")

func _append_trail_point(world_point: Vector2) -> void:
	if _trail_points.is_empty():
		_trail_points.append(world_point)
		return

	var last_point: Vector2 = _trail_points[_trail_points.size() - 1]
	var distance: float = last_point.distance_to(world_point)
	if distance <= 0.001:
		return

	var direction: Vector2 = (world_point - last_point) / distance
	var spacing: float = max(_segment_spacing, 1.0)
	var traveled: float = spacing
	while traveled < distance:
		_trail_points.append(last_point + direction * traveled)
		traveled += spacing

	_trail_points.append(world_point)

func _trim_trail_to_length(max_length: float) -> void:
	if _trail_points.size() < 2:
		return

	var accumulated: float = 0.0
	var keep_index: int = _trail_points.size() - 1

	for i: int in range(_trail_points.size() - 1, 0, -1):
		var head_point: Vector2 = _trail_points[i]
		var tail_point: Vector2 = _trail_points[i - 1]
		var segment_length: float = head_point.distance_to(tail_point)

		if accumulated + segment_length >= max_length:
			var remaining: float = max_length - accumulated
			if segment_length > 0.0:
				var direction: Vector2 = (tail_point - head_point) / segment_length
				_trail_points[i - 1] = head_point + direction * remaining
			keep_index = i - 1
			break

		accumulated += segment_length
		keep_index = i - 1

	if keep_index > 0:
		_trail_points = _trail_points.slice(keep_index, _trail_points.size())

func _detect_self_collision() -> bool:
	if body_length < self_collision_min_body_length:
		return false
	if _trail_points.size() < 10:
		return false

	var head_position: Vector2 = global_position
	var points_to_ignore: int = int(max(4.0, ceil(24.0 / max(_segment_spacing, 1.0))))
	var max_index: int = _trail_points.size() - points_to_ignore
	if max_index <= 0:
		return false

	var step: int = max(self_collision_sample_step, 1)
	for i: int in range(0, max_index, step):
		if _trail_points[i].distance_to(head_position) <= self_collision_radius:
			return true
	return false

func _sync_body_line() -> void:
	var local_points: PackedVector2Array = PackedVector2Array()
	for world_point: Vector2 in _trail_points:
		local_points.append(to_local(world_point))
	body_line.points = local_points

func _sync_head_collision() -> void:
	var shape := CircleShape2D.new()
	shape.radius = head_radius
	head_collision_shape.shape = shape
	head_area.set_meta("snake_id", String(snake_id))

func _sync_body_style() -> void:
	if body_line == null:
		return
	body_line.default_color = head_color.darkened(0.2)

func _config_number(property_name: String, fallback: float) -> float:
	if movement_config == null:
		return fallback

	var value: Variant = movement_config.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback
