extends CanvasLayer

@onready var state_value_label: Label = $Margin/Rows/StateValue
@onready var score_value_label: Label = $Margin/Rows/ScoreValue

func bind_world(world: Node) -> void:
	world.match_state_changed.connect(_on_match_state_changed)
	world.score_changed.connect(_on_score_changed)

func _on_match_state_changed(state: StringName) -> void:
	state_value_label.text = String(state)

func _on_score_changed(_snake_id: StringName, score: int) -> void:
	score_value_label.text = str(score)
