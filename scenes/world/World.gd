## World.gd
## Attached to: scenes/world/World.tscn (root node)
##
## Responsibility:
##   - Top-level scene orchestrator for the game world.
##   - Connects GridSystem signals to world-level handlers.
##   - Sets camera bounds once the grid is built.
##   - Acts as the integration point between all world systems.
##
## Architecture note:
##   World.gd is intentionally thin. It wires systems together but contains
##   no gameplay logic. Think of it as the "main" for the world scene.
##   All heavy lifting is in GridSystem, CameraController, and future systems.

class_name World
extends Node2D

# ─── Child node references ────────────────────────────────────────────────────
@onready var _grid:   GridSystem       = $GridSystem
@onready var _camera: CameraController = $WorldCamera

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Connect grid signals to world handlers.
	_grid.grid_ready.connect(_on_grid_ready)
	_grid.tile_selected.connect(_on_tile_selected)
	_grid.tile_hovered.connect(_on_tile_hovered)
	_grid.tile_unhovered.connect(_on_tile_unhovered)


# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_grid_ready() -> void:
	# Once the grid is built, tell the camera its movement bounds.
	var tile_size: Vector2  = _grid.get_tile_size()
	var grid_size: Vector2i = _grid.get_grid_size()

	var bounds: Rect2 = IsometricUtils.grid_bounds(
		grid_size.x, grid_size.y,
		tile_size.x, tile_size.y
	)

	var cfg: Dictionary     = DataManager.get_data("world_config")
	var raw_cam: Variant    = cfg.get("camera", {})
	var cam_cfg: Dictionary = raw_cam if raw_cam is Dictionary else {}
	var margin: float       = float(cam_cfg.get("bounds_margin", 200.0))

	_camera.set_bounds(bounds, margin)

	# Center the camera on the grid at startup.
	var center: Vector2 = bounds.get_center()
	_camera.snap_to(center)

	print("World: grid ready. Bounds=%s  Center=%s" % [str(bounds), str(center)])


func _on_tile_selected(tile: VineyardTile) -> void:
	# World-level response to tile selection.
	# Future: open tile inspector UI, trigger farming actions, etc.
	print("World: tile selected at (%d, %d)" % [tile.grid_col, tile.grid_row])


func _on_tile_hovered(tile: VineyardTile) -> void:
	# Future: update status bar with tile info.
	pass


func _on_tile_unhovered(_tile: VineyardTile) -> void:
	# Future: clear status bar.
	pass
