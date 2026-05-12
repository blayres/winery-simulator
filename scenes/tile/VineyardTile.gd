## VineyardTile.gd
## Attached to: scenes/tile/VineyardTile.tscn
##
## Responsibility:
##   - Represents one tile in the vineyard grid.
##   - Manages its own visual state (default / hover / selected).
##   - Emits signals upward — never calls parent directly.
##   - Holds grid coordinates and a data payload slot for future gameplay.
##
## Architecture note:
##   Tile visuals are drawn with a Polygon2D (no sprites needed for prototype).
##   Colors come from world_config.json via the config dictionary passed at init.
##   This tile has zero knowledge of the grid system or camera.

class_name VineyardTile
extends Area2D

# ─── Signals ──────────────────────────────────────────────────────────────────
signal tile_hovered(tile: VineyardTile)
signal tile_unhovered(tile: VineyardTile)
signal tile_selected(tile: VineyardTile)

# ─── State enum ───────────────────────────────────────────────────────────────
enum TileState { DEFAULT, HOVERED, SELECTED }

# ─── Public data ──────────────────────────────────────────────────────────────
## Grid address — set once by GridSystem at spawn time.
var grid_col: int = 0
var grid_row: int = 0

## Gameplay data slot — populated by future systems (soil type, grape, etc.).
## Kept as Dictionary so any system can attach arbitrary data without subclassing.
var tile_data: Dictionary = {}

# ─── Internal ─────────────────────────────────────────────────────────────────
var _state: TileState = TileState.DEFAULT

# Color values — set from config in setup().
var _color_default:  Color = Color("4a7c59")
var _color_hover:    Color = Color("6aab7a")
var _color_selected: Color = Color("f0c060")
var _color_outline:  Color = Color("2a4a35")

# Child node references — assigned in _ready().
var _polygon:  Polygon2D
var _outline:  Polygon2D
var _label:    Label        # Debug label, hidden in release.

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_polygon = $TilePolygon
	_outline = $TileOutline
	_label   = $DebugLabel

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)

	_apply_state()


# ─── Public API ───────────────────────────────────────────────────────────────

## Called by GridSystem immediately after instantiation.
## [param col] / [param row] — grid address.
## [param world_pos] — pixel position in the scene.
## [param tile_w] / [param tile_h] — tile dimensions for polygon shape.
## [param colors] — Dictionary with keys: default, hover, selected, outline.
func setup(col: int, row: int, world_pos: Vector2,
		tile_w: float, tile_h: float, colors: Dictionary) -> void:
	grid_col = col
	grid_row = row
	position = world_pos

	# Build the diamond polygon from tile dimensions.
	var hw: float = tile_w * 0.5
	var hh: float = tile_h * 0.5
	var diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0.0,  -hh),   # top
		Vector2(hw,   0.0),   # right
		Vector2(0.0,   hh),   # bottom
		Vector2(-hw,  0.0),   # left
	])
	_polygon.polygon = diamond
	_outline.polygon = diamond

	# Apply colors from config.
	if colors.has("default"):
		_color_default  = Color(str(colors["default"]))
	if colors.has("hover"):
		_color_hover    = Color(str(colors["hover"]))
	if colors.has("selected"):
		_color_selected = Color(str(colors["selected"]))
	if colors.has("outline"):
		_color_outline  = Color(str(colors["outline"]))

	# Build the collision shape to match the diamond.
	var collision: CollisionPolygon2D = $CollisionShape
	collision.polygon = diamond

	# Debug label shows grid address.
	_label.text = "%d,%d" % [col, row]
	_label.position = Vector2(-12.0, -6.0)

	_apply_state()


## Deselect this tile (called by GridSystem when another tile is selected).
func deselect() -> void:
	if _state == TileState.SELECTED:
		_set_state(TileState.DEFAULT)


## Returns true if this tile is currently selected.
func is_selected() -> bool:
	return _state == TileState.SELECTED


# ─── Private ──────────────────────────────────────────────────────────────────

func _on_mouse_entered() -> void:
	if _state != TileState.SELECTED:
		_set_state(TileState.HOVERED)
	tile_hovered.emit(self)


func _on_mouse_exited() -> void:
	if _state == TileState.HOVERED:
		_set_state(TileState.DEFAULT)
	tile_unhovered.emit(self)


func _on_input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_set_state(TileState.SELECTED)
			tile_selected.emit(self)


func _set_state(new_state: TileState) -> void:
	if _state == new_state:
		return
	_state = new_state
	_apply_state()


func _apply_state() -> void:
	if _polygon == null:
		return
	match _state:
		TileState.DEFAULT:
			_polygon.color  = _color_default
			_outline.color  = _color_outline
		TileState.HOVERED:
			_polygon.color  = _color_hover
			_outline.color  = _color_outline
		TileState.SELECTED:
			_polygon.color  = _color_selected
			_outline.color  = _color_outline
