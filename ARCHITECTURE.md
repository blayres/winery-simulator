# Terroir Wars — Architecture Reference

## Autoload Load Order

```
DataManager       ← loads all JSON at startup; must be first
GameManager       ← owns season/year/phase state
ClimateManager    ← depends on DataManager + GameManager signals
EconomyManager    ← depends on DataManager + GameManager signals
WineManager       ← depends on DataManager + GameManager + EconomyManager
EventManager      ← depends on DataManager + GameManager + ClimateManager + EconomyManager
SaveManager       ← depends on all managers (calls get_save_data / load_save_data)
```

## Signal Flow

```
GameManager
  ├── season_changed      → ClimateManager, EventManager
  ├── year_advanced       → ClimateManager, EconomyManager, WineManager
  ├── game_started        → EconomyManager
  └── phase_changed       → UI

ClimateManager
  ├── climate_profile_changed   → UI, EventManager (future)
  └── season_conditions_updated → UI, VineyardSystem (future)

EconomyManager
  ├── funds_changed       → UI
  ├── transaction_recorded → UI ledger
  └── bankruptcy_occurred → GameManager (future: trigger game over)

WineManager
  ├── wine_crafted        → UI, EconomyManager (future: prestige)
  ├── wine_aged           → UI
  └── inventory_changed   → UI

EventManager
  ├── event_triggered     → UI (show event modal)
  └── event_resolved      → effects dispatched to managers
```

## Data Pipeline

```
JSON files (data/)
    ↓
DataManager._load_file()   ← called at startup for all registered keys
    ↓
DataManager._cache         ← in-memory Dictionary
    ↓
Manager._on_data_loaded()  ← each manager pulls its slice on the signal
    ↓
Manager uses data          ← never re-reads from disk
```

## Adding a New Manager

1. Create `autoload/MyManager.gd` extending `Node`.
2. Implement `get_save_data() → Dictionary` and `load_save_data(data)`.
3. Connect to `DataManager.data_loaded` if you need JSON.
4. Connect to `GameManager` signals for season/year hooks.
5. Register in `project.godot` `[autoload]` section (after its dependencies).
6. Add its save key to `SaveManager._collect_save_data` / `_distribute_save_data`.

## Adding New Data

1. Create the JSON file under `data/`.
2. Add an entry to `DataManager.FILE_REGISTRY`.
3. That's it — DataManager loads it automatically at startup.

## File Size Rule

All `.gd` files must stay under 300 lines.
If a file grows beyond that, extract a helper script into `scripts/`.
