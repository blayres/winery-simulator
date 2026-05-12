## World.gd
## Attached to: scenes/world/World.tscn (root node)
##
## Responsibility:
##   - Top-level scene orchestrator.
##   - Wires GridSystem, CameraController, and DebugOverlay together.
##   - Sets camera bounds and initial position after grid is built.
##   - Sets background clear color from world_config.json.
##
## Architecture note:
##   World.gd is intentionally thin — it connects systems but holds no logic.
##   All heavy lifting lives in the individual system scripts.

class_name World
extends Node2D

# ─── Child references ─────────────────────────────────────────────────────────
@onready var _grid:    GridSystem    = $GridSystem
@onready var _camera:  CameraController = $WorldCamera
@onready var _debug:   DebugOverlay  = $WorldUI/DebugOverlay

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_apply_background_color()

	_grid.grid_ready.connect(_on_grid_ready)
	_grid.tile_selected.connect(_on_tile_selected)
	_grid.tile_hovered.connect(_on_tile_hovered)
	_grid.tile_unhovered.connect(_on_tile_unhovered)


# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_grid_ready() -> void:
	var tile_size: Vector2  = _grid.get_tile_size()
	var grid_size: Vector2i = _grid.get_grid_size()

	var bounds: Rect2 = IsometricUtils.grid_bounds(
		grid_size.x, grid_size.y,
		tile_size.x, tile_size.y
	)

	var cfg: Dictionary     = DataManager.get_data("world_config")
	var raw_cam: Variant    = cfg.get("camera", {})
	var cam_cfg: Dictionary = raw_cam if raw_cam is Dictionary else {}
	var margin: float       = float(cam_cfg.get("bounds_margin", 300.0))

	_camera.set_bounds(bounds, margin)
	_camera.snap_to(bounds.get_center())

	# Give the debug overlay its references now that everything is ready.
	_debug.init(_grid, _camera)

	print("World: ready. Grid=%s  Bounds=%s" % [str(grid_size), str(bounds)])


func _on_tile_selected(tile: VineyardTile) -> void:
	# Future: open tile inspector panel, trigger farming actions, etc.
	pass


func _on_tile_hovered(_tile: VineyardTile) -> void:
	# Future: update status bar.
	pass


func _on_tile_unhovered(_tile: VineyardTile) -> void:
	# Future: clear status bar.
	pass


# ─── Private ──────────────────────────────────────────────────────────────────

func _apply_background_color() -> void:
	var cfg: Dictionary      = DataManager.get_data("world_config")
	var raw_atmo: Variant    = cfg.get("atmosphere", {})
	if not raw_atmo is Dictionary:
		return
	var atmo: Dictionary     = raw_atmo
	var raw_color: Variant   = atmo.get("background_color", "3d5a4a")
	var bg: Color            = Color(str(raw_color))
	RenderingServer.set_default_clear_color(bg)
