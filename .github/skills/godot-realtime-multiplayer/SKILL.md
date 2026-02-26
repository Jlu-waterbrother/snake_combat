---
name: godot-realtime-multiplayer
description: Realtime multiplayer sync strategy for Godot 4.6 snake games. Use this when building online movement and combat.
license: MIT
---

Prefer server-authoritative simulation.

Networking playbook:
- Use `ENetMultiplayerPeer` for low-latency state sync.
- Send compact input commands from client to server.
- Simulate authoritative movement/collisions on server.
- Replicate snapshots at fixed intervals.
- Interpolate remote entities on clients.

Reliability rules:
1. Never trust client collision outcomes.
2. Keep protocol versioned and backwards-safe.
3. Log desync indicators for debugging.
