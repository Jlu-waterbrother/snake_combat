extends CanvasLayer

@export var joystick_radius: float = 76.0
@export var deadzone: float = 0.18

@onready var joystick_zone: Control = $JoystickZone
@onready var joystick_knob: Control = $JoystickZone/Knob
@onready var boost_zone: Control = $BoostZone

var _joystick_touch_id: int = -1
var _boost_touch_id: int = -1
var _turn_input: float = 0.0
var _boosting: bool = false
var _controls_enabled: bool = false
var _pressed_left: bool = false
var _pressed_right: bool = false
var _pressed_boost: bool = false

func _ready() -> void:
	_controls_enabled = DisplayServer.is_touchscreen_available()
	visible = _controls_enabled
	_reset_knob()

func _unhandled_input(event: InputEvent) -> void:
	if not _controls_enabled:
		return

	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)

func _physics_process(_delta: float) -> void:
	if not _controls_enabled:
		return
	_apply_actions()

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var touch_position: Vector2 = event.position
	if event.pressed:
		if _joystick_touch_id == -1 and joystick_zone.get_global_rect().has_point(touch_position):
			_joystick_touch_id = event.index
			_update_joystick(touch_position)
			return

		if _boost_touch_id == -1 and boost_zone.get_global_rect().has_point(touch_position):
			_boost_touch_id = event.index
			_boosting = true
			return
		return

	if event.index == _joystick_touch_id:
		_joystick_touch_id = -1
		_turn_input = 0.0
		_reset_knob()

	if event.index == _boost_touch_id:
		_boost_touch_id = -1
		_boosting = false

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joystick_touch_id:
		_update_joystick(event.position)

func _update_joystick(touch_position: Vector2) -> void:
	var center: Vector2 = joystick_zone.get_global_rect().get_center()
	var offset: Vector2 = touch_position - center
	var clamped_offset: Vector2 = offset.limit_length(joystick_radius)
	_turn_input = clamp(clamped_offset.x / joystick_radius, -1.0, 1.0)
	joystick_knob.global_position = center + clamped_offset - joystick_knob.size * 0.5

func _reset_knob() -> void:
	var center: Vector2 = joystick_zone.get_global_rect().get_center()
	joystick_knob.global_position = center - joystick_knob.size * 0.5

func _apply_actions() -> void:
	var wants_left: bool = _turn_input < -deadzone
	var wants_right: bool = _turn_input > deadzone
	var left_strength: float = abs(_turn_input)
	var right_strength: float = _turn_input

	if wants_left:
		Input.action_press("turn_left", left_strength)
		_pressed_left = true
	elif _pressed_left:
		Input.action_release("turn_left")
		_pressed_left = false

	if wants_right:
		Input.action_press("turn_right", right_strength)
		_pressed_right = true
	elif _pressed_right:
		Input.action_release("turn_right")
		_pressed_right = false

	if _boosting:
		Input.action_press("boost")
		_pressed_boost = true
	elif _pressed_boost:
		Input.action_release("boost")
		_pressed_boost = false
