extends Node

@onready var world := $World
@onready var hud := $HUD

@export var available_player_skins: Array[Resource] = []
@export var available_player_skin_names: PackedStringArray = PackedStringArray()

var _is_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud.bind_world(world)
	hud.start_match_requested.connect(_on_start_match_requested)
	_configure_pre_match_skin_selection()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _toggle_pause() -> void:
	_is_paused = not _is_paused
	world.set_pause_state(_is_paused)
	get_tree().paused = _is_paused

func _configure_pre_match_skin_selection() -> void:
	if not hud.has_method("configure_pre_match_skins"):
		return

	var current_skin: Resource = null
	if world.has_method("get_player_skin"):
		var skin_value: Variant = world.call("get_player_skin")
		if skin_value is Resource:
			current_skin = skin_value

	var skin_options: Array[Resource] = []
	if available_player_skins.is_empty():
		if current_skin != null:
			skin_options.append(current_skin)
	else:
		for skin: Resource in available_player_skins:
			if skin != null:
				skin_options.append(skin)

	hud.call("configure_pre_match_skins", skin_options, available_player_skin_names, current_skin)

func _on_start_match_requested(selected_skin: Resource) -> void:
	if selected_skin != null and world.has_method("set_player_skin"):
		world.call("set_player_skin", selected_skin)
	world.start_match()
