## GridSystem.gd
## Attached to: a Node2D child of World.tscn
##
## Responsibility:
##   - Reads grid config from DataManager (columns, rows, tile size).
##   - Instantiates VineyardTile scenes at correct isometric positions.
##   - Routes tile signals upward to World.
##   - Manages selection state (only one tile selected at a time).
##   - Provides grid query API for future gameplay systems.
##
## Architecture note:
##   GridSystem owns the tile nodes but knows nothing about gameplay.
##   It is purely structural — layout + signal routing.
##   Gameplay data is attached to tiles via tile.tile_data by other systems.

class_name GridSystem
extends Node2D

# ─── Signals ──────────────────────────────────────────────────────────────────
signal tile_hovered(tile: VineyardTile)
signal tile_unhovered(tile: VineyardTile)
signal tile_selected(tile: VineyardTile)
signal grid_ready()

# ─── Config (populated from JSON) ─────────────────────────────────────────────
var _cols:    int   = 16
var _rows:    int   = 12
var _tile_w:  float = 128.0
var _tile_h:  float = 64.0

# ─── State ────────────────────────────────────────────────────────────────────
## Flat lookup: "col,row" → VineyardTile node.
var _tiles: Dictionary = {}

var _selected_tile: VineyardTile = null

# Tile scene — preloaded once.
const TILE_SCENE_PATH: String = "res://scenes/tile/VineyardTile.tscn"
var _tile_scene: PackedScene = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_tile_scene = load(TILE_SCENE_PATH)
	if _tile_scene == null:
		push_error("GridSystem: could not load tile scene at '%s'." % TILE_SCENE_PATH)
		return

	# Config may already be loaded (DataManager runs before scene _ready calls).
	# If not, wait for the signal.
	if DataManager.is_loaded("world_config"):
		_build_grid()
	else:
		DataManager.data_loaded.connect(_on_data_loaded)


# ─── Public API ───────────────────────────────────────────────────────────────

## Returns the tile at grid address (col, row), or null if out of bounds.
func get_tile(col: int, row: int) -> VineyardTile:
	var key: String = "%d,%d" % [col, row]
	if _tiles.has(key):
		var t: Variant = _tiles[key]
		if t is VineyardTile:
			return t
	return null


## Returns all tile nodes as an Array.
func get_all_tiles() -> Array:
	return _tiles.values()


## Returns grid dimensions as Vector2i(cols, rows).
func get_grid_size() -> Vector2i:
	return Vector2i(_cols, _rows)


## Returns tile pixel dimensions as Vector2(width, height).
func get_tile_size() -> Vector2:
	return Vector2(_tile_w, _tile_h)


## Deselects the currently selected tile, if any.
func clear_selection() -> void:
	if _selected_tile != null:
		_selected_tile.deselect()
		_selected_tile = null


# ─── Private ──────────────────────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "world_config":
		_build_grid()


func _build_grid() -> void:
	var cfg: Dictionary = DataManager.get_data("world_config")

	# Read grid config with safe fallbacks.
	var raw_grid: Variant = cfg.get("grid", {})
	var grid_cfg: Dictionary = raw_grid if raw_grid is Dictionary else {}

	_cols   = int(grid_cfg.get("columns",    16))
	_rows   = int(grid_cfg.get("rows",       12))
	_tile_w = float(grid_cfg.get("tile_width",  128.0))
	_tile_h = float(grid_cfg.get("tile_height",  64.0))

	# Read tile colors.
	var raw_colors: Variant = cfg.get("tile_colors", {})
	var colors: Dictionary = raw_colors if raw_colors is Dictionary else {}

	# Spawn tiles.
	for row: int in _rows:
		for col: int in _cols:
			_spawn_tile(col, row, colors)

	grid_ready.emit()
	print("GridSystem: grid built — %d × %d (%d tiles)." % [_cols, _rows, _tiles.size()])


func _spawn_tile(col: int, row: int, colors: Dictionary) -> void:
	var tile: VineyardTile = _tile_scene.instantiate()
	add_child(tile)

	var world_pos: Vector2 = IsometricUtils.grid_to_world(col, row, _tile_w, _tile_h)
	tile.setup(col, row, world_pos, _tile_w, _tile_h, colors)

	# Route tile signals upward.
	tile.tile_hovered.connect(_on_tile_hovered)
	tile.tile_unhovered.connect(_on_tile_unhovered)
	tile.tile_selected.connect(_on_tile_selected)

	# Z-order: tiles further down the screen draw on top (isometric depth sort).
	tile.z_index = col + row

	_tiles["%d,%d" % [col, row]] = tile


func _on_tile_hovered(tile: VineyardTile) -> void:
	tile_hovered.emit(tile)


func _on_tile_unhovered(tile: VineyardTile) -> void:
	tile_unhovered.emit(tile)


func _on_tile_selected(tile: VineyardTile) -> void:
	# Deselect previous tile before selecting new one.
	if _selected_tile != null and _selected_tile != tile:
		_selected_tile.deselect()

	_selected_tile = tile
	tile_selected.emit(tile)

	print("GridSystem: tile selected — col=%d row=%d data=%s" \
			% [tile.grid_col, tile.grid_row, str(tile.tile_data)])
