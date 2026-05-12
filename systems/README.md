# Systems

Scene-attached system nodes (not singletons).

These are nodes that live in a scene tree and coordinate gameplay for a
specific context (e.g. the vineyard grid, the cellar UI flow).

Examples:
- `VineyardSystem.gd` — manages the isometric grid of vine tiles
- `HarvestSystem.gd` — orchestrates the autumn harvest sequence
- `CellarSystem.gd` — manages fermentation and aging UI flow

Rules:
- Systems communicate with managers via signals, not direct calls.
- Systems own their own scene-local state.
- Systems should be removable without breaking managers.
