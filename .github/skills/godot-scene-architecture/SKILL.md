---
name: godot-scene-architecture
description: Scene-tree architecture patterns for Godot snake-like games. Use this when creating scenes, managers, and state ownership.
license: MIT
---

Build scene hierarchy with clear ownership and low coupling.

Recommended structure:
- `Main` scene as composition root.
- `World` node for simulation.
- `SnakeManager` for player/enemy snakes.
- `FoodManager` for spawn and recycle.
- `HUD` for score/rank/respawn status.
- Optional autoload `GameState` for match-level state.

Rules:
1. Keep spawn/despawn in manager nodes.
2. Route cross-system updates through signals.
3. Keep UI read-only over gameplay state where possible.
