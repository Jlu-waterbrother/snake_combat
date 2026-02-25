extends Node2D

@export var movement_config: Resource
@export var default_base_speed: float = 220.0
@export var default_boost_speed: float = 340.0
@export var default_turn_rate_deg_per_second: float = 300.0
@export var default_segment_spacing: float = 10.0
@export var body_length: float = 180.0
@export var initial_heading: Vector2 = Vector2.RIGHT
@export var head_radius: float = 10.0
@export var head_color: Color = Color(0.22, 0.84, 0.31)

@onready var body_line: Line2D = $BodyLine

var _heading: Vector2 = Vector2.RIGHT
var _trail_points: Array[Vector2] = []
var _segment_spacing: float = 10.0

func _ready() -> void:
	_heading = initial_heading.normalized()
	if _heading == Vector2.ZERO:
		_heading = Vector2.RIGHT

	_trail_points = [global_position, global_position - _heading * body_length]
	_sync_body_line()
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, head_radius, head_color)

func _physics_process(delta: float) -> void:
	var base_speed: float = _config_number("base_speed", default_base_speed)
	var boost_speed: float = _config_number("boost_speed", default_boost_speed)
	var turn_rate_deg: float = _config_number("turn_rate_deg_per_second", default_turn_rate_deg_per_second)
	_segment_spacing = max(_config_number("segment_spacing", default_segment_spacing), 1.0)

	var turn_input: float = Input.get_axis("turn_left", "turn_right")
	_heading = _heading.rotated(deg_to_rad(turn_rate_deg) * turn_input * delta).normalized()

	var speed: float = boost_speed if Input.is_action_pressed("boost") else base_speed
	global_position += _heading * speed * delta

	_append_trail_point(global_position)
	_trim_trail_to_length(body_length)
	_sync_body_line()

func set_movement_config(config: Resource) -> void:
	movement_config = config

func _append_trail_point(world_point: Vector2) -> void:
	if _trail_points.is_empty():
		_trail_points.append(world_point)
		return

	var last_point: Vector2 = _trail_points[_trail_points.size() - 1]
	if last_point.distance_to(world_point) >= _segment_spacing:
		_trail_points.append(world_point)
	else:
		_trail_points[_trail_points.size() - 1] = world_point

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

func _sync_body_line() -> void:
	var local_points: PackedVector2Array = PackedVector2Array()
	for world_point: Vector2 in _trail_points:
		local_points.append(to_local(world_point))
	body_line.points = local_points

func _config_number(property_name: String, fallback: float) -> float:
	if movement_config == null:
		return fallback

	var value: Variant = movement_config.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback
