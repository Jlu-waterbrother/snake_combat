extends CanvasLayer

signal start_match_requested(selected_skin: Resource)

@onready var state_value_label: Label = $Margin/Rows/StateValue
@onready var score_value_label: Label = $Margin/Rows/ScoreValue
@onready var lives_value_label: Label = $Margin/Rows/LivesValue
@onready var difficulty_value_label: Label = $Margin/Rows/DifficultyValue
@onready var enemies_value_label: Label = $Margin/Rows/EnemiesValue
@onready var message_value_label: Label = $Margin/Rows/MessageValue
@onready var leaderboard_value_label: Label = $LeaderboardMargin/Rows/LeaderboardValue
@onready var pre_match_panel: PanelContainer = $PreMatchPanel
@onready var skin_select: OptionButton = $PreMatchPanel/Margin/VBox/SkinSelect
@onready var start_button: Button = $PreMatchPanel/Margin/VBox/StartButton

@export var hud_label_text_color: Color = Color(0.11, 0.21, 0.31, 1.0)
@export var hud_value_text_color: Color = Color(0.07, 0.32, 0.46, 1.0)

var _enemy_count: int = 0
var _skin_options: Array[Resource] = []

func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	_apply_hud_text_colors()
	pre_match_panel.visible = true

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

func configure_pre_match_skins(skins: Array[Resource], skin_names: PackedStringArray = PackedStringArray(), selected_skin: Resource = null) -> void:
	_skin_options.clear()
	skin_select.clear()

	for index: int in range(skins.size()):
		var skin: Resource = skins[index]
		if skin == null:
			continue

		var display_name: String = ""
		if index < skin_names.size():
			display_name = skin_names[index]
		if display_name.is_empty():
			display_name = _skin_display_name(skin)
		_skin_options.append(skin)
		skin_select.add_item(display_name)

	if _skin_options.is_empty():
		skin_select.add_item("Default")
		skin_select.disabled = true
		return

	skin_select.disabled = false
	var selected_index: int = 0
	if selected_skin != null:
		var found_index: int = _skin_options.find(selected_skin)
		if found_index >= 0:
			selected_index = found_index
	skin_select.select(selected_index)

func _on_match_state_changed(state: StringName) -> void:
	state_value_label.text = String(state)
	if state == &"running":
		message_value_label.text = "Fight"
		pre_match_panel.visible = false
	elif state == &"respawning":
		message_value_label.text = "Respawning..."
		pre_match_panel.visible = false
	elif state == &"ended":
		message_value_label.text = "Game Over"
		pre_match_panel.visible = true
		start_button.disabled = false
	elif state == &"stopped" or state == &"boot":
		message_value_label.text = "Select skin and start"
		pre_match_panel.visible = true
		start_button.disabled = false
	else:
		message_value_label.text = String(state)
		pre_match_panel.visible = false

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

func _skin_display_name(skin: Resource) -> String:
	if skin == null:
		return "Default"
	var resource_path: String = skin.resource_path
	if resource_path.is_empty():
		return "Custom Skin"
	return resource_path.get_file().get_basename().replace("_", " ")

func _on_start_button_pressed() -> void:
	start_button.disabled = true
	pre_match_panel.visible = false

	var selected_skin: Resource = null
	if not _skin_options.is_empty():
		var selected_index: int = clampi(skin_select.selected, 0, _skin_options.size() - 1)
		selected_skin = _skin_options[selected_index]

	start_match_requested.emit(selected_skin)

func _apply_hud_text_colors() -> void:
	var label_paths: PackedStringArray = PackedStringArray([
		"Margin/Rows/StateLabel",
		"Margin/Rows/ScoreLabel",
		"Margin/Rows/LivesLabel",
		"Margin/Rows/DifficultyLabel",
		"Margin/Rows/EnemiesLabel",
		"Margin/Rows/MessageLabel",
		"LeaderboardMargin/Rows/LeaderboardLabel",
		"PreMatchPanel/Margin/VBox/Title",
		"PreMatchPanel/Margin/VBox/SkinLabel",
	])
	var value_paths: PackedStringArray = PackedStringArray([
		"Margin/Rows/StateValue",
		"Margin/Rows/ScoreValue",
		"Margin/Rows/LivesValue",
		"Margin/Rows/DifficultyValue",
		"Margin/Rows/EnemiesValue",
		"Margin/Rows/MessageValue",
		"LeaderboardMargin/Rows/LeaderboardValue",
	])

	for path: String in label_paths:
		var node: Node = get_node_or_null(path)
		if node is Label:
			(node as Label).add_theme_color_override("font_color", hud_label_text_color)

	for path: String in value_paths:
		var node: Node = get_node_or_null(path)
		if node is Label:
			(node as Label).add_theme_color_override("font_color", hud_value_text_color)

	_set_control_font_colors(start_button, hud_value_text_color)
	_set_control_font_colors(skin_select, hud_value_text_color)

func _set_control_font_colors(control: Control, base_color: Color) -> void:
	if control == null:
		return
	control.add_theme_color_override("font_color", base_color)
	control.add_theme_color_override("font_hover_color", base_color.lightened(0.08))
	control.add_theme_color_override("font_pressed_color", base_color.darkened(0.12))
	control.add_theme_color_override("font_focus_color", base_color)
	control.add_theme_color_override("font_disabled_color", base_color.darkened(0.35))
