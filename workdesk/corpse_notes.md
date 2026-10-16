# Corpses and gravekeepers

- `world/corpse_manager.gd` owns the current floor's traces. They are separate
  from terrain, items, and combat entities, so they do not block movement,
  pathfinding, FOV, or projectiles.
- `enemy.die()` records original ID, name, grid tile, and world position once.
  Unseen deaths do not reveal themselves. Discovered remains persist dimly in
  explored terrain. Inspection displays the original enemy's name.
- Only the active floor's save section stores corpses. Floor caches never store
  them. Actual floor/chunk/world-map transitions clear the registry.
- Gravekeepers spawn on normal floors 2–9. They choose the nearest reachable
  corpse they can currently see using the shared NPC perception rules. This
  takes priority over attacking the player. With no recognized corpse they use
  their normal aggressive AI.
- Arrival and consumption are separate turns. One action consumes one corpse:
  50% attack +2, 50% resurrection using the original enemy definition at full HP.
  Occupied or impassable spawn cells are skipped; if no valid resurrection
  cell/definition exists, absorption is used. New enemies begin acting next turn.
- Attack gains are included in ordinary enemy saves and floor caches.
- `add_corpse`, `remove_corpse`, `resurrect`, `serialize`, and `restore` are
  independent entry points for future corpse consumers and item conversion.

Verification: `--headless --path . --script workdesk/gravekeeper_test.gd`.
