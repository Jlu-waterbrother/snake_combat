# Copilot Instructions

## Build, test, and lint commands
- Launch the project with Godot Flatpak: `flatpak run org.godotengine.Godot --path .` (the project plan also documents `flatpak run org.godotengine.Godot`).
- No repository-defined build, lint, or automated test scripts are committed yet (no workflow/Makefile/package-manager test harness in this repo).
- A single-test command is not available yet because no automated test framework is configured.

## High-level architecture
- `project.godot` runs `res://scenes/main/main.tscn` and autoloads `GameState` (`res://scripts/core/game_state.gd`).
- `Main` (`scripts/main/main.gd`) is the composition shell: it binds `HUD` to `World`, starts the match, and handles pause toggling.
- `World` (`scripts/world/world.gd`) orchestrates gameplay systems: it wires manager signals, forwards gameplay events, tracks lives/respawn flow, applies dynamic difficulty, and updates camera follow.
- `SnakeManager` owns snake simulation and lifecycle: player/enemy spawning, AI state machine (`patrol/seek/chase/avoid`), world-bound checks, head-to-head and head-to-body collision resolution, and death mass-drop emission.
- `FoodManager` owns food lifecycle with pooling: prewarms `FoodItem` nodes, recycles active/inactive pools, emits `food_eaten`, and exposes nearest-food queries used by enemy retargeting.
- `PlayerSnake` (`scripts/snake/player_snake.gd`) performs deterministic movement/body-trail simulation in `_physics_process`, supports player and AI control modes, and handles self-collision.
- UI stays read-only over world state: `HUD` updates labels from world signals, while `MobileControls` translates touch input into existing InputMap actions (`turn_left`, `turn_right`, `boost`).

## Key repository conventions
- Keep gameplay simulation in `_physics_process`; reserve `_unhandled_input` for control events (pause/touch) and input bridging.
- Use typed GDScript and `StringName` identifiers consistently for snake IDs and state names (`player`, `enemy_%d`, `running`, `respawning`, etc.).
- Route cross-system state changes through manager/world signals rather than direct deep-node reads (`match_state_changed`, `score_changed`, `snake_died`, `snake_spawned`, `enemy_state_changed`).
- Keep balancing values data-driven through `Resource` configs in `resources/config/*.tres` (`MovementConfig`, `FoodConfig`, `AIConfig`) and inject them through `World`/manager exports.
- Preserve the food collision contract: snake head areas must be in the `snake_head` group and carry `snake_id` metadata for `FoodItem` consumption events.
- Maintain manager ownership boundaries: `SnakeManager` handles spawn/kill/collision rules; `FoodManager` handles spawn safety and node pooling; HUD/mobile controls should not mutate simulation state directly.
