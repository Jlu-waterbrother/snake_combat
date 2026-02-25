extends Area2D
class_name FoodItem

signal consumed(snake_id: StringName, amount: int)

@export var amount: int = 1
@export var radius: float = 5.0
@export var color: Color = Color(0.99, 0.8, 0.1)

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var food_id: int = 0

func _ready() -> void:
	collision_layer = 8
	collision_mask = 4
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)
	_sync_collision_radius()
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)

func configure(new_food_id: int, world_position: Vector2, new_amount: int) -> void:
	food_id = new_food_id
	amount = max(new_amount, 1)
	global_position = world_position
	visible = true
	monitoring = true
	monitorable = true
	_sync_collision_radius()

func deactivate() -> void:
	monitoring = false
	monitorable = false
	visible = false

func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("snake_head"):
		return

	var snake_id_value: Variant = area.get_meta("snake_id", "")
	if typeof(snake_id_value) != TYPE_STRING and typeof(snake_id_value) != TYPE_STRING_NAME:
		push_warning("Snake head area missing valid snake_id metadata.")
		return

	var snake_id: StringName = StringName(snake_id_value)
	consumed.emit(snake_id, amount)

func _sync_collision_radius() -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision_shape.shape = shape
