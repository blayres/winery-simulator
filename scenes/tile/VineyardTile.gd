## VineyardTile.gd
## Attached to: scenes/tile/VineyardTile.tscn
##
## Responsibility:
##   - Represents one tile in the vineyard grid.
##   - Three visual states: DEFAULT, HOVERED, SELECTED.
##   - Smooth Tween-based scale and color transitions.
##   - Alternating checkerboard base colors for isometric readability.
##   - Shadow polygon for fake depth.
##   - Emits signals upward — never calls parent directly.
##   - tile_data Dictionary slot for future gameplay attachment.
##
## Architecture note:
##   All animation values come from world_config.json.
##   The tile is self-contained — it knows nothing about the grid or camera.

class_name VineyardTile
extends Area2D

# ─── Signals ──────────────────────────────────────────────────────────────────
signal tile_hovered(tile: VineyardTile)
signal tile_unhovered(tile: VineyardTile)
signal tile_selected(tile: VineyardTile)

# ─── State ────────────────────────────────────────────────────────────────────
enum TileState { DEFAULT, HOVERED, SELECTED }

var _state: TileState = TileState.DEFAULT

# ─── Public data ──────────────────────────────────────────────────────────────
var grid_col:  int        = 0
var grid_row:  int        = 0
var tile_data: Dictionary = {}

# ─── Colors (set from config in setup) ───────────────────────────────────────
var _color_base:     Color = Color("4a7c59")   # this tile's checkerboard color
var _color_hover:    Color = Color("6aab7a")
var _color_selected: Color = Color("f0c060")
var _color_outline:  Color = Color("2a4a35")
var _color_shadow:   Color = Color(0.1, 0.16, 0.12, 0.55)

# ─── Animation values (set from config in setup) ──────────────────────────────
var _hover_scale:    float = 1.05
var _hover_dur:      float = 0.15
var _select_scale:   float = 1.08
var _select_dur:     float = 0.20

# ─── Child nodes ──────────────────────────────────────────────────────────────
var _shadow:    Polygon2D
var _outline:   Polygon2D
var _polygon:   Polygon2D
var _label:     Label

# Active tween — killed before starting a new one.
var _tween: Tween = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_shadow  = $TileShadow
	_outline = $TileOutline
	_polygon = $TilePolygon
	_label   = $DebugLabel

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)


# ─── Public API ───────────────────────────────────────────────────────────────

## Called once by GridSystem after instantiation.
## [param col/row]     — grid address
## [param world_pos]   — pixel position in scene
## [param tile_w/h]    — tile dimensions
## [param colors]      — Dictionary from world_config tile_colors
## [param anim]        — Dictionary from world_config tile_animation
## [param checkerboard]— true = use default_b color for visual variety
func setup(col: int, row: int, world_pos: Vector2,
		tile_w: float, tile_h: float,
		colors: Dictionary, anim: Dictionary,
		checkerboard: bool) -> void:

	grid_col = col
	grid_row = row
	position = world_pos

	# ── Build diamond polygon ──────────────────────────────────────────────
	var hw: float = tile_w * 0.5
	var hh: float = tile_h * 0.5
	var diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -hh),
		Vector2(hw,  0.0),
		Vector2(0.0,  hh),
		Vector2(-hw, 0.0),
	])

	_polygon.polygon = diamond
	_outline.polygon = diamond

	# Shadow is a slightly enlarged, offset diamond for fake depth.
	var shadow_offset: float = hh * 0.35
	var shadow_diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0.0,        -hh + shadow_offset),
		Vector2(hw  + 2.0,   shadow_offset),
		Vector2(0.0,          hh + shadow_offset),
		Vector2(-hw - 2.0,   shadow_offset),
	])
	_shadow.polygon = shadow_diamond

	# Collision matches the main diamond.
	var collision: CollisionPolygon2D = $CollisionShape
	collision.polygon = diamond

	# ── Colors ────────────────────────────────────────────────────────────
	var key_base: String = "default_b" if checkerboard else "default_a"
	if colors.has(key_base):
		_color_base = Color(str(colors[key_base]))
	if colors.has("hover"):
		_color_hover    = Color(str(colors["hover"]))
	if colors.has("selected"):
		_color_selected = Color(str(colors["selected"]))
	if colors.has("outline"):
		_color_outline  = Color(str(colors["outline"]))
	if colors.has("shadow"):
		_color_shadow   = Color(str(colors["shadow"]))
		_color_shadow.a = 0.45

	# ── Animation values ──────────────────────────────────────────────────
	_hover_scale  = float(anim.get("hover_scale",    1.05))
	_hover_dur    = float(anim.get("hover_duration",  0.15))
	_select_scale = float(anim.get("select_scale",    1.08))
	_select_dur   = float(anim.get("select_duration", 0.20))

	# ── Debug label ───────────────────────────────────────────────────────
	_label.text = "%d,%d" % [col, row]

	_apply_state_instant()


## Deselect this tile (called by GridSystem when another tile is selected).
func deselect() -> void:
	if _state == TileState.SELECTED:
		_set_state(TileState.DEFAULT)


func is_selected() -> bool:
	return _state == TileState.SELECTED


# ─── Private — input ──────────────────────────────────────────────────────────

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


# ─── Private — state machine ──────────────────────────────────────────────────

func _set_state(new_state: TileState) -> void:
	if _state == new_state:
		return
	_state = new_state
	_animate_to_state()


## Instant apply — used during setup before the tile is visible.
func _apply_state_instant() -> void:
	_polygon.color = _color_base
	_outline.color = _color_outline
	_shadow.color  = _color_shadow
	scale          = Vector2.ONE


## Tween-based transition to the current state.
func _animate_to_state() -> void:
	# Kill any running tween cleanly.
	if _tween != null and _tween.is_running():
		_tween.kill()

	var target_color: Color
	var target_scale: float
	var duration:     float

	match _state:
		TileState.DEFAULT:
			target_color = _color_base
			target_scale = 1.0
			duration     = _hover_dur
		TileState.HOVERED:
			target_color = _color_hover
			target_scale = _hover_scale
			duration     = _hover_dur
		TileState.SELECTED:
			target_color = _color_selected
			target_scale = _select_scale
			duration     = _select_dur

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK if _state == TileState.SELECTED else Tween.TRANS_SINE)

	_tween.tween_property(_polygon, "color", target_color, duration)
	_tween.tween_property(self, "scale",
			Vector2(target_scale, target_scale), duration)
