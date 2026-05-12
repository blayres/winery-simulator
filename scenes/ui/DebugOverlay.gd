## DebugOverlay.gd
## Attached to: scenes/ui/DebugOverlay.tscn (CanvasLayer)
##
## Responsibility:
##   - Minimal debug panel showing: selected tile coords, zoom level, grid size.
##   - Toggled with F1 key.
##   - Reads live data from GridSystem and CameraController via references
##     passed in from World — no direct autoload coupling.
##
## Architecture note:
##   DebugOverlay is purely presentational. It polls data every frame
##   rather than using signals, which is fine for a debug panel.
##   It will be removed or hidden in the final game.

class_name DebugOverlay
extends CanvasLayer

# ─── External references (set by World after grid is ready) ───────────────────
var _grid:   GridSystem       = null
var _camera: CameraController = null

# ─── Child nodes ──────────────────────────────────────────────────────────────
@onready var _panel:      PanelContainer = $Panel
@onready var _lbl_tile:   Label          = $Panel/VBox/TileLabel
@onready var _lbl_zoom:   Label          = $Panel/VBox/ZoomLabel
@onready var _lbl_grid:   Label          = $Panel/VBox/GridLabel
@onready var _lbl_hint:   Label          = $Panel/VBox/HintLabel

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_panel.visible = true   # Visible by default in prototype.
	_update_labels()


func _process(_delta: float) -> void:
	_update_labels()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and k.keycode == KEY_F1:
			_panel.visible = not _panel.visible
			get_viewport().set_input_as_handled()


# ─── Public API ───────────────────────────────────────────────────────────────

## Called by World once systems are ready.
func init(grid: GridSystem, camera: CameraController) -> void:
	_grid   = grid
	_camera = camera


# ─── Private ──────────────────────────────────────────────────────────────────

func _update_labels() -> void:
	# Tile info.
	if _grid != null:
		var sel: VineyardTile = _grid.get_selected_tile()
		if sel != null:
			_lbl_tile.text = "Tile:  (%d, %d)" % [sel.grid_col, sel.grid_row]
		else:
			_lbl_tile.text = "Tile:  —"

		var gs: Vector2i = _grid.get_grid_size()
		_lbl_grid.text = "Grid:  %d × %d" % [gs.x, gs.y]
	else:
		_lbl_tile.text = "Tile:  —"
		_lbl_grid.text = "Grid:  —"

	# Zoom info.
	if _camera != null:
		_lbl_zoom.text = "Zoom:  %.2f×" % _camera.get_zoom_level()
	else:
		_lbl_zoom.text = "Zoom:  —"

	_lbl_hint.text = "F1 toggle  |  WASD pan  |  Scroll zoom  |  MMB drag"
