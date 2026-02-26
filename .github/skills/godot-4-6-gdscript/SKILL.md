---
name: godot-4-6-gdscript
description: Godot 4.6 typed GDScript conventions for gameplay code. Use this when implementing or refactoring gameplay scripts.
license: MIT
---

Use typed GDScript and Godot 4.6 APIs by default.

Guidelines:
- Prefer explicit types for exported vars, locals, and function signatures.
- Keep logic deterministic in `_physics_process(delta)` for gameplay simulation.
- Use signals for decoupling scene nodes instead of deep node-path coupling.
- Keep script responsibilities small: one script per gameplay role.

Checklist:
1. Validate node paths and `@onready` bindings.
2. Emit signals for domain events (`food_eaten`, `snake_died`, `score_changed`).
3. Avoid frame-rate dependent mechanics in `_process`.
