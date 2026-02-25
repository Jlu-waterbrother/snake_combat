extends Node

@onready var world := $World
@onready var hud := $HUD

func _ready() -> void:
	hud.bind_world(world)
	world.start_match()
