extends Node

@onready var world := $World
@onready var hud := $HUD

var _is_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud.bind_world(world)
	world.start_match()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _toggle_pause() -> void:
	_is_paused = not _is_paused
	world.set_pause_state(_is_paused)
	get_tree().paused = _is_paused
