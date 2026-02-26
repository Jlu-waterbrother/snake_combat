---
name: godot-performance-mobile-ui
description: Performance and mobile control guidance for dense 2D snake scenes in Godot 4.6. Use this when optimizing frame time or touch controls.
license: MIT
---

Optimization priorities:
- Use object pools for food and snake segments.
- Avoid per-frame node churn in busy scenes.
- Batch expensive queries and reuse buffers.
- Profile with Godot profiler before and after each optimization.

Mobile UX priorities:
- Provide virtual joystick plus boost button.
- Keep thumb zones away from HUD-critical controls.
- Expose sensitivity and camera zoom options.

Targets:
1. Stable frame pacing during high entity counts.
2. Predictable input latency under load.
