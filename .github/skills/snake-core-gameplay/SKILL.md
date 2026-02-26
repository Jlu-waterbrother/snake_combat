---
name: snake-core-gameplay
description: Core gameplay loop for a Slither-like game. Use this when implementing eat-grow-score-death cycle.
license: MIT
---

Implement and preserve the core loop:
1. Spawn food in safe positions.
2. Snake eats food to gain score and length.
3. Update movement scaling and camera feel gradually.
4. Trigger death on invalid collisions.
5. Convert dead snake mass into collectable food (optional but recommended).

Behavior defaults:
- Keep controls responsive with turn-rate limits rather than hard input delay.
- Keep growth incremental to preserve pacing.
- Keep score and body length derived from one source of truth.
