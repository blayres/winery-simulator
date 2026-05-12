# Scripts

Domain-specific helper scripts that are NOT singletons.

Examples of what goes here:
- `VineTile.gd` — logic for a single vineyard tile
- `HarvestCalculator.gd` — pure functions for harvest quality math
- `WineDescriptorBuilder.gd` — assembles descriptor strings from JSON data

Rules:
- Scripts here should be under 300 lines.
- No direct references to other scripts — use signals or pass data as arguments.
- No JSON loading — always go through DataManager.
