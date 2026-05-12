## GridSystem.gd
## Attached to: Node2D (GridSystem) in World.tscn
##
## Responsibility:
##   - Reads grid config from DataManager.
##   - Instantiates VineyardTile scenes at correct isometric positions.
##   - Passes color + animation config to each tile.
##   - Manages single-tile selection state.
##   - Routes tile signals upward to World.
##   - Provides grid query API for future gameplay systems.
##
## Architecture note:
##   GridSystem is purely structural — layout + signal routing.
##   It knows nothing about gameplay. Gameplay data attaches via tile.tile_data.

class_name GridSystem
extends Node2D

# ─── Signals ──────────────────────────────────────────────────────────────────
signal tile_hovered(tile: VineyardTile)
signal tile_unhovered(tile: VineyardTile)
signal tile_selected(tile: VineyardTile)
signal grid_ready()

# ─── Config ───────────────────────────────────────────────────────────────────
var _cols:   int   = 16
var _rows:   int   = 12
var _tile_w: float = 128.0
var _tile_h: float = 64.0

# ─── State ────────────────────────────────────────────────────────────────────
## Flat lookup: "col,row" → VineyardTile
var _tiles:         Dictionary   = {}
var _selected_tile: VineyardTile = null

const TILE_SCENE_PATH: String = "res://scenes/tile/VineyardTile.tscn"
var   _tile_scene:     PackedScene = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_tile_scene = load(TILE_SCENE_PATH)
	if _tile_scene == null:
		push_error("GridSystem: could not load tile scene at '%s'." % TILE_SCENE_PATH)
		return

	if DataManager.is_loaded("world_config"):
		_build_grid()
	else:
		DataManager.data_loaded.connect(_on_data_loaded)


# ─── Public API ───────────────────────────────────────────────────────────────

func get_tile(col: int, row: int) -> VineyardTile:
	var key: String = "%d,%d" % [col, row]
	if _tiles.has(key):
		var t: Variant = _tiles[key]
		if t is VineyardTile:
			return t
	return null


func get_all_tiles() -> Array:
	return _tiles.values()


func get_grid_size() -> Vector2i:
	return Vector2i(_cols, _rows)


func get_tile_size() -> Vector2:
	return Vector2(_tile_w, _tile_h)


func clear_selection() -> void:
	if _selected_tile != null:
		_selected_tile.deselect()
		_selected_tile = null


func get_selected_tile() -> VineyardTile:
	return _selected_tile


# ─── Private ──────────────────────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "world_config":
		_build_grid()


func _build_grid() -> void:
	var cfg: Dictionary = DataManager.get_data("world_config")

	var raw_grid: Variant    = cfg.get("grid", {})
	var grid_cfg: Dictionary = raw_grid if raw_grid is Dictionary else {}
	_cols   = int(grid_cfg.get("columns",     16))
	_rows   = int(grid_cfg.get("rows",        12))
	_tile_w = float(grid_cfg.get("tile_width",  128.0))
	_tile_h = float(grid_cfg.get("tile_height",  64.0))

	var raw_colors: Variant  = cfg.get("tile_colors", {})
	var colors: Dictionary   = raw_colors if raw_colors is Dictionary else {}

	var raw_anim: Variant    = cfg.get("tile_animation", {})
	var anim: Dictionary     = raw_anim if raw_anim is Dictionary else {}

	for row: int in _rows:
		for col: int in _cols:
			_spawn_tile(col, row, colors, anim)

	grid_ready.emit()
	print("GridSystem: built %d × %d grid (%d tiles)." % [_cols, _rows, _tiles.size()])


func _spawn_tile(col: int, row: int, colors: Dictionary, anim: Dictionary) -> void:
	var tile: VineyardTile = _tile_scene.instantiate()
	add_child(tile)

	var world_pos: Vector2 = IsometricUtils.grid_to_world(col, row, _tile_w, _tile_h)

	# Checkerboard: alternate on (col + row) parity for visual readability.
	var checkerboard: bool = (col + row) % 2 == 1

	tile.setup(col, row, world_pos, _tile_w, _tile_h, colors, anim, checkerboard)

	tile.tile_hovered.connect(_on_tile_hovered)
	tile.tile_unhovered.connect(_on_tile_unhovered)
	tile.tile_selected.connect(_on_tile_selected)

	# Isometric depth sort: tiles further down the screen draw on top.
	tile.z_index = col + row

	_tiles["%d,%d" % [col, row]] = tile


func _on_tile_hovered(tile: VineyardTile) -> void:
	tile_hovered.emit(tile)


func _on_tile_unhovered(tile: VineyardTile) -> void:
	tile_unhovered.emit(tile)


func _on_tile_selected(tile: VineyardTile) -> void:
	if _selected_tile != null and _selected_tile != tile:
		_selected_tile.deselect()
	_selected_tile = tile
	tile_selected.emit(tile)
