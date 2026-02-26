---
name: godot-2d-movement-collision
description: 2D movement and collision workflow for snake gameplay in Godot 4.6. Use this when implementing movement, pickup, and death collisions.
license: MIT
---

Keep simulation stable and deterministic.

Implementation notes:
- Move snakes on fixed ticks in `_physics_process`.
- Store heading as normalized vectors or grid-step directions.
- Use `Area2D` overlap checks for food pickup and hazard detection.
- Keep collision layers/masks explicit and documented in code.

Validation steps:
1. Verify pickup detection at high speed.
2. Verify self-collision and enemy-collision thresholds.
3. Ensure respawn immunity windows are explicit if used.
