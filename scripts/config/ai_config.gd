extends Resource
class_name AIConfig

@export var enemy_count: int = 6
@export var max_enemy_count: int = 10
@export var score_per_difficulty_level: int = 20
@export var max_difficulty_level: int = 5
@export var vision_radius: float = 540.0
@export var aggression: float = 0.45
@export var boost_probability: float = 0.12
@export var avoid_boundary_ratio: float = 0.8
@export var avoid_boundary_margin: float = 220.0
@export var retarget_interval: float = 0.2
@export var turn_responsiveness: float = 4.2
@export var hazard_probe_interval: float = 0.08
@export var hazard_probe_distance: float = 180.0
@export var hazard_probe_angle_deg: float = 28.0
@export var head_on_avoid_distance: float = 200.0
@export var caution_length_ratio: float = 1.05
@export var chase_predict_seconds: float = 0.35
@export var chase_flank_distance: float = 90.0
