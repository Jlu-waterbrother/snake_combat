extends Node2D

signal snake_died(reason: StringName)
signal mass_shed(world_position: Vector2, consumed_length: float)

enum ControlMode {
	PLAYER,
	AI,
}

@export var movement_config: Resource
@export var skin: Resource
@export var default_base_speed: float = 123.75
@export var default_boost_speed: float = 210.0
@export var boost_body_drain_per_second: float = 18.0
@export var min_body_length_for_boost: float = 120.0
@export var min_body_length: float = 80.0
@export var visual_reference_length: float = 180.0
@export var head_growth_scale: float = 0.35
@export var body_width_growth_scale: float = 0.3
@export var max_visual_scale: float = 2.4
@export var coiling_turn_threshold: float = 0.55
@export var coiling_shrink_per_second: float = 8.0
@export var default_turn_rate_deg_per_second: float = 220.0
@export var default_segment_spacing: float = 10.0
@export var body_length: float = 180.0
@export var initial_heading: Vector2 = Vector2.RIGHT
@export var rotate_head_texture_with_heading: bool = true
@export var head_svg_render_scale: float = 2.0
@export var body_svg_render_scale: float = 1.5
@export var head_radius: float = 10.0
@export var head_color: Color = Color(0.22, 0.84, 0.31)
@export var self_collision_radius: float = 9.0
@export var self_collision_min_body_length: float = 260.0
@export var self_collision_sample_step: int = 2
@export var control_mode: ControlMode = ControlMode.PLAYER
@export var enable_desktop_mouse_controls: bool = true
@export var mouse_turn_responsiveness: float = 3.0
@export var mouse_turn_deadzone: float = 0.02

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
var _base_head_radius: float = 10.0
var _base_body_line_width: float = 12.0
var _skin_head_color: Color = Color(0.22, 0.84, 0.31)
var _skin_body_color: Color = Color(0.18, 0.67, 0.25)
var _skin_head_radius_scale: float = 1.0
var _skin_body_width_scale: float = 1.0
var _skin_head_texture: Texture2D
var _skin_body_texture: Texture2D
var _head_sprite: Sprite2D

static var _svg_texture_cache: Dictionary = {}

func _ready() -> void:
	_heading = initial_heading.normalized()
	if _heading == Vector2.ZERO:
		_heading = Vector2.RIGHT

	head_area.collision_layer = 4
	head_area.collision_mask = 8
	head_area.add_to_group("snake_head")
	_base_head_radius = max(head_radius, 1.0)
	_base_body_line_width = max(body_line.width, 1.0)
	_skin_head_color = head_color
	_skin_body_color = head_color.darkened(0.2)
	_head_sprite = Sprite2D.new()
	_head_sprite.centered = true
	_head_sprite.z_index = 2
	_head_sprite.visible = false
	add_child(_head_sprite)
	_apply_skin()
	_sync_visual_scale()
	_sync_head_collision()
	_sync_body_style()

	_trail_points = [global_position - _heading * body_length, global_position]
	_sync_body_line()
	queue_redraw()

func _draw() -> void:
	if _skin_head_texture == null:
		draw_circle(Vector2.ZERO, head_radius, head_color)

func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	var base_speed_raw: float = _config_number("base_speed", default_base_speed)
	var boost_speed_raw: float = _config_number("boost_speed", default_boost_speed)
	var turn_rate_deg: float = _config_number("turn_rate_deg_per_second", default_turn_rate_deg_per_second)
	_segment_spacing = max(_config_number("segment_spacing", default_segment_spacing), 1.0)

	var base_speed: float = base_speed_raw
	var boost_speed: float = boost_speed_raw

	var turn_input: float = _read_turn_input()
	_heading = _heading.rotated(deg_to_rad(turn_rate_deg) * turn_input * delta).normalized()
	_sync_head_texture_rotation()

	var wants_boost: bool = _wants_boost()
	var can_boost: bool = _can_boost(wants_boost)
	var boost_length_loss: float = 0.0
	var speed: float = boost_speed if can_boost else base_speed
	global_position += _heading * speed * delta
	if can_boost:
		var boost_min_length: float = max(min_body_length_for_boost, min_body_length)
		var previous_length: float = body_length
		body_length = max(body_length - boost_body_drain_per_second * delta, boost_min_length)
		boost_length_loss = max(previous_length - body_length, 0.0)

	var contraction_factor: float = _coiling_contraction_factor(abs(turn_input))
	if can_boost and contraction_factor > 0.0:
		body_length = max(body_length - coiling_shrink_per_second * contraction_factor * delta, min_body_length)

	_sync_visual_scale()
	_append_trail_point(global_position)
	_trim_trail_to_length(body_length)
	_sync_body_line()
	if boost_length_loss > 0.0:
		mass_shed.emit(_tail_world_position(), boost_length_loss)

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
	_skin_head_color = new_head_color
	_skin_body_color = new_head_color.darkened(0.2)
	if is_inside_tree():
		_sync_body_style()
		queue_redraw()

func set_skin(new_skin: Resource) -> void:
	skin = new_skin
	_apply_skin()

func grow_by(length_delta: float) -> void:
	if length_delta <= 0.0:
		push_warning("Snake growth delta must be positive.")
		return
	body_length += length_delta

func get_body_length() -> float:
	return body_length

func get_head_radius() -> float:
	return head_radius

func get_body_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for trail_point: Vector2 in _trail_points:
		points.append(trail_point)
	return points

func get_heading() -> Vector2:
	return _heading

func get_food_drop_color() -> Color:
	return _skin_body_color

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

	var keyboard_turn: float = Input.get_axis("turn_left", "turn_right")
	if not _uses_desktop_mouse_controls():
		return keyboard_turn

	var to_mouse: Vector2 = get_global_mouse_position() - global_position
	if to_mouse == Vector2.ZERO:
		return keyboard_turn

	var desired_direction: Vector2 = to_mouse.normalized()
	var mouse_turn_scale: float = max(mouse_turn_responsiveness, 0.0)
	var mouse_turn: float = clamp(_heading.cross(desired_direction) * mouse_turn_scale, -1.0, 1.0)
	if abs(mouse_turn) <= max(mouse_turn_deadzone, 0.0):
		return keyboard_turn
	return mouse_turn

func _wants_boost() -> bool:
	if control_mode == ControlMode.AI:
		return _ai_boosting

	var wants_boost: bool = Input.is_action_pressed("boost")
	if _uses_desktop_mouse_controls() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		wants_boost = true
	return wants_boost

func _can_boost(wants_boost: bool) -> bool:
	if not wants_boost:
		return false
	if boost_body_drain_per_second <= 0.0:
		return false
	return body_length > max(min_body_length_for_boost, min_body_length)

func _uses_desktop_mouse_controls() -> bool:
	if not enable_desktop_mouse_controls:
		return false
	var os_name: String = OS.get_name()
	return os_name != "Android" and os_name != "iOS"

func _coiling_contraction_factor(turn_amount: float) -> float:
	var threshold: float = clamp(coiling_turn_threshold, 0.0, 0.99)
	if turn_amount <= threshold:
		return 0.0
	return clamp((turn_amount - threshold) / (1.0 - threshold), 0.0, 1.0)

func _tail_world_position() -> Vector2:
	if _trail_points.is_empty():
		return global_position
	return _trail_points[0]

func _apply_skin() -> void:
	var next_head_color: Color = _skin_head_color
	var next_body_color: Color = _skin_body_color
	var next_head_scale: float = 1.0
	var next_body_scale: float = 1.0
	var next_head_texture: Texture2D = null
	var next_body_texture: Texture2D = null
	var next_head_svg_path: String = ""
	var next_body_svg_path: String = ""

	if skin != null:
		next_head_color = _skin_color("head_color", _skin_head_color)
		next_body_color = _skin_color("body_color", next_head_color.darkened(0.2))
		next_head_scale = max(_skin_number("head_radius_scale", 1.0), 0.4)
		next_body_scale = max(_skin_number("body_width_scale", 1.0), 0.4)
		next_head_texture = _skin_texture("head_texture")
		next_body_texture = _skin_texture("body_texture")
		next_head_svg_path = _skin_string("head_svg_path", "")
		next_body_svg_path = _skin_string("body_svg_path", "")
		if not next_head_svg_path.is_empty():
			var svg_head_texture: Texture2D = _load_texture_from_svg(next_head_svg_path, head_svg_render_scale)
			if svg_head_texture != null:
				next_head_texture = svg_head_texture
		if not next_body_svg_path.is_empty():
			var svg_body_texture: Texture2D = _load_texture_from_svg(next_body_svg_path, body_svg_render_scale)
			if svg_body_texture != null:
				next_body_texture = svg_body_texture

	_skin_head_color = next_head_color
	_skin_body_color = next_body_color
	_skin_head_radius_scale = next_head_scale
	_skin_body_width_scale = next_body_scale
	_skin_head_texture = next_head_texture
	_skin_body_texture = next_body_texture
	head_color = _skin_head_color

	if is_inside_tree():
		_sync_visual_scale()
		_sync_body_style()
		queue_redraw()

func _sync_visual_scale() -> void:
	var reference_length: float = max(visual_reference_length, 1.0)
	var length_ratio: float = max(body_length / reference_length, 0.01)
	var growth_amount: float = max(length_ratio - 1.0, 0.0)
	var visual_scale_limit: float = max(max_visual_scale, 1.0)

	var head_scale: float = clamp(1.0 + growth_amount * max(head_growth_scale, 0.0), 1.0, visual_scale_limit)
	var body_scale: float = clamp(1.0 + growth_amount * max(body_width_growth_scale, 0.0), 1.0, visual_scale_limit)

	var target_head_radius: float = _base_head_radius * _skin_head_radius_scale * head_scale
	var target_body_width: float = _base_body_line_width * _skin_body_width_scale * body_scale
	var head_changed: bool = not is_equal_approx(head_radius, target_head_radius)

	head_radius = target_head_radius
	if body_line != null:
		body_line.width = target_body_width
	_sync_head_visual()
	if head_changed:
		_sync_head_collision()
		queue_redraw()

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
	if _skin_body_texture != null:
		body_line.texture = _skin_body_texture
		body_line.texture_mode = Line2D.LINE_TEXTURE_TILE
		body_line.default_color = _skin_body_color
	else:
		body_line.texture = null
		body_line.texture_mode = Line2D.LINE_TEXTURE_NONE
		body_line.default_color = _skin_body_color

func _sync_head_visual() -> void:
	if _head_sprite == null:
		return
	if _skin_head_texture == null:
		_head_sprite.texture = null
		_head_sprite.visible = false
		return

	_head_sprite.texture = _skin_head_texture
	_head_sprite.modulate = _skin_head_color
	var texture_size: Vector2 = _skin_head_texture.get_size()
	var max_dimension: float = max(texture_size.x, texture_size.y)
	var target_diameter: float = max(head_radius * 2.0, 1.0)
	var scale_factor: float = 1.0
	if max_dimension > 0.0:
		scale_factor = target_diameter / max_dimension
	_head_sprite.scale = Vector2.ONE * scale_factor
	_head_sprite.visible = true
	_sync_head_texture_rotation()

func _sync_head_texture_rotation() -> void:
	if _head_sprite == null or not _head_sprite.visible:
		return
	if rotate_head_texture_with_heading:
		_head_sprite.rotation = _heading.angle()
	else:
		_head_sprite.rotation = 0.0

func _config_number(property_name: String, fallback: float) -> float:
	if movement_config == null:
		return fallback

	var value: Variant = movement_config.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback

func _skin_number(property_name: String, fallback: float) -> float:
	if skin == null:
		return fallback

	var value: Variant = skin.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback

func _skin_color(property_name: String, fallback: Color) -> Color:
	if skin == null:
		return fallback

	var value: Variant = skin.get(property_name)
	if value is Color:
		return value
	return fallback

func _skin_texture(property_name: String) -> Texture2D:
	if skin == null:
		return null

	var value: Variant = skin.get(property_name)
	if value is Texture2D:
		return value
	return null

func _skin_string(property_name: String, fallback: String) -> String:
	if skin == null:
		return fallback

	var value: Variant = skin.get(property_name)
	if value is String or value is StringName:
		return String(value)
	return fallback

func _load_texture_from_svg(svg_path: String, render_scale: float) -> Texture2D:
	if svg_path.is_empty():
		return null

	var cache_key: String = "%s@%.2f" % [svg_path, render_scale]
	var cached_value: Variant = _svg_texture_cache.get(cache_key, null)
	if cached_value is Texture2D:
		return cached_value as Texture2D

	if FileAccess.file_exists(svg_path):
		var svg_file: FileAccess = FileAccess.open(svg_path, FileAccess.READ)
		if svg_file != null:
			var svg_text: String = svg_file.get_as_text()
			var image: Image = Image.new()
			var parse_error: Error = image.load_svg_from_string(svg_text, max(render_scale, 0.1))
			if parse_error == OK:
				var generated_texture: ImageTexture = ImageTexture.create_from_image(image)
				_svg_texture_cache[cache_key] = generated_texture
				return generated_texture

	var imported_texture_value: Variant = load(svg_path)
	if imported_texture_value is Texture2D:
		var imported_texture: Texture2D = imported_texture_value as Texture2D
		_svg_texture_cache[cache_key] = imported_texture
		return imported_texture

	push_warning("Unable to load snake SVG texture: %s" % svg_path)
	return null
