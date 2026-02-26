extends CanvasLayer

@onready var state_value_label: Label = $Margin/Rows/StateValue
@onready var score_value_label: Label = $Margin/Rows/ScoreValue
@onready var lives_value_label: Label = $Margin/Rows/LivesValue
@onready var difficulty_value_label: Label = $Margin/Rows/DifficultyValue
@onready var enemies_value_label: Label = $Margin/Rows/EnemiesValue
@onready var message_value_label: Label = $Margin/Rows/MessageValue
@onready var leaderboard_value_label: Label = $Margin/Rows/LeaderboardValue

var _enemy_count: int = 0

func bind_world(world: Node) -> void:
	world.match_state_changed.connect(_on_match_state_changed)
	world.score_changed.connect(_on_score_changed)
	world.lives_changed.connect(_on_lives_changed)
	world.difficulty_changed.connect(_on_difficulty_changed)
	world.snake_spawned.connect(_on_snake_spawned)
	world.snake_died.connect(_on_snake_died)
	if world.has_signal("leaderboard_changed"):
		world.leaderboard_changed.connect(_on_leaderboard_changed)
	if world.has_method("get_leaderboard_entries"):
		var entries_value: Variant = world.call("get_leaderboard_entries")
		if entries_value is Array:
			var entries: Array[Dictionary] = []
			for entry_value: Variant in entries_value:
				if entry_value is Dictionary:
					entries.append(entry_value)
			_on_leaderboard_changed(entries)

func _on_match_state_changed(state: StringName) -> void:
	state_value_label.text = String(state)
	if state == &"running":
		message_value_label.text = "Fight"
	elif state == &"respawning":
		message_value_label.text = "Respawning..."
	elif state == &"ended":
		message_value_label.text = "Game Over"
	else:
		message_value_label.text = String(state)

func _on_score_changed(snake_id: StringName, score: int) -> void:
	if snake_id == &"player":
		score_value_label.text = str(score)

func _on_lives_changed(remaining_lives: int) -> void:
	lives_value_label.text = str(remaining_lives)

func _on_difficulty_changed(level: int, _enemy_target: int) -> void:
	difficulty_value_label.text = str(level)

func _on_snake_spawned(snake_id: StringName) -> void:
	if String(snake_id).begins_with("enemy_"):
		_enemy_count += 1
		enemies_value_label.text = str(_enemy_count)

func _on_snake_died(snake_id: StringName, reason: StringName) -> void:
	if snake_id == &"player":
		message_value_label.text = "Player down: %s" % String(reason)
		return

	if String(snake_id).begins_with("enemy_"):
		_enemy_count = max(_enemy_count - 1, 0)
		enemies_value_label.text = str(_enemy_count)
		message_value_label.text = "Enemy eliminated"

func _on_leaderboard_changed(entries: Array[Dictionary]) -> void:
	if entries.is_empty():
		leaderboard_value_label.text = "-"
		return

	var lines: PackedStringArray = PackedStringArray()
	var rank: int = 1
	for entry: Dictionary in entries:
		var display_name: String = String(entry.get("name", "Unknown"))
		if bool(entry.get("is_player", false)):
			display_name = "%s (You)" % display_name
		var length_value: float = float(entry.get("length", 0.0))
		lines.append("%d. %s  %.0f" % [rank, display_name, length_value])
		rank += 1

	leaderboard_value_label.text = "\n".join(lines)
