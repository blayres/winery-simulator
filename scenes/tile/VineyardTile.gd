## VineyardTile.gd
## Attached to: scenes/tile/VineyardTile.tscn
##
## Responsibility:
##   - Visual representation and input handling for one grid tile.
##   - Three interaction states: DEFAULT, HOVERED, SELECTED.
##   - Smooth Tween-based scale and color transitions.
##   - Delegates all color decisions to TileVisualController.
##   - Holds a reference to TileSimData (read-only — never writes to it).
##
## Architecture note:
##   VineyardTile is PURELY visual + input.
##   It never reads simulation values directly for logic decisions.
##   When sim data changes, VineyardSimulation calls notify_sim_updated()
##   and this tile recomputes its visuals via TileVisualController.
##
##   Separation enforced:
##     VineyardTile  → reads TileSimData for display only
##     TileVisualController → maps sim values to colors
##     VineyardSimulation   → writes TileSimData

class_name VineyardTile
extends Area2D

# ─── Signals ──────────────────────────────────────────────────────────────────
signal tile_hovered(tile: VineyardTile)
signal tile_unhovered(tile: VineyardTile)
signal tile_selected(tile: VineyardTile)

# ─── Interaction state ────────────────────────────────────────────────────────
enum TileState { DEFAULT, HOVERED, SELECTED }
var _state: TileState = TileState.DEFAULT

# ─── Identity ─────────────────────────────────────────────────────────────────
var grid_col:     int         = 0
var grid_row:     int         = 0
var _checkerboard: bool       = false

# ─── Simulation data reference (READ-ONLY from this script) ──────────────────
var sim_data: TileSimData = null

# ─── Interaction colors (from world_config, for hover/select states) ──────────
var _color_hover:    Color = Color("6aab7a")
var _color_selected: Color = Color("f0c060")

# ─── Computed base color (from TileVisualController) ─────────────────────────
var _color_base:    Color = Color("4a7c59")
var _color_outline: Color = Color("2a4a35")

# ─── Animation config ─────────────────────────────────────────────────────────
var _hover_scale:  float = 1.05
var _hover_dur:    float = 0.15
var _select_scale: float = 1.08
var _select_dur:   float = 0.20

# ─── Child nodes ──────────────────────────────────────────────────────────────
var _shadow:  Polygon2D
var _outline: Polygon2D
var _polygon: Polygon2D
var _label:   Label
var _tween:   Tween = null

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
func setup(col: int, row: int, world_pos: Vector2,
		tile_w: float, tile_h: float,
		colors: Dictionary, anim: Dictionary,
		checkerboard: bool) -> void:

	grid_col      = col
	grid_row      = row
	_checkerboard = checkerboard
	position      = world_pos

	var hw: float = tile_w * 0.5
	var hh: float = tile_h * 0.5
	var diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -hh), Vector2(hw, 0.0),
		Vector2(0.0,  hh), Vector2(-hw, 0.0),
	])
	_polygon.polygon = diamond
	_outline.polygon = diamond

	var so: float = hh * 0.35
	_shadow.polygon = PackedVector2Array([
		Vector2(0.0,      -hh + so), Vector2(hw + 2.0,  so),
		Vector2(0.0,       hh + so), Vector2(-hw - 2.0, so),
	])

	var collision: CollisionPolygon2D = $CollisionShape
	collision.polygon = diamond

	# Interaction colors from world_config.
	if colors.has("hover"):
		_color_hover    = Color(str(colors["hover"]))
	if colors.has("selected"):
		_color_selected = Color(str(colors["selected"]))

	# Shadow color.
	var shadow_color: Color = Color("1a2a1f")
	if colors.has("shadow"):
		shadow_color = Color(str(colors["shadow"]))
	shadow_color.a = 0.45
	_shadow.color  = shadow_color

	# Animation config.
	_hover_scale  = float(anim.get("hover_scale",    1.05))
	_hover_dur    = float(anim.get("hover_duration",  0.15))
	_select_scale = float(anim.get("select_scale",    1.08))
	_select_dur   = float(anim.get("select_duration", 0.20))

	_label.text = "%d,%d" % [col, row]

	# Apply default visual immediately (sim data not yet attached).
	_refresh_base_colors()
	_apply_state_instant()


## Called by VineyardSimulation (via World) when this tile's sim data changes.
## This is the ONLY entry point for simulation → visual updates.
func notify_sim_updated() -> void:
	_refresh_base_colors()
	# Only repaint if not in an interaction state — don't fight the tween.
	if _state == TileState.DEFAULT:
		_apply_state_instant()
	# Update label to show sim-driven info.
	_label.text = TileVisualController.tile_label(sim_data)


## Brief color flash to confirm a player action was applied.
## [param flash_color] — action-specific highlight color.
func flash_action(flash_color: Color) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_polygon, "color", flash_color, 0.08)
	_tween.tween_property(_polygon, "color", _color_base, 0.35)


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


# ─── Private — visual state ───────────────────────────────────────────────────

func _refresh_base_colors() -> void:
	_color_base    = TileVisualController.compute_base_color(sim_data, _checkerboard)
	_color_outline = TileVisualController.compute_outline_color(sim_data)


func _set_state(new_state: TileState) -> void:
	if _state == new_state:
		return
	_state = new_state
	_animate_to_state()


func _apply_state_instant() -> void:
	if _polygon == null:
		return
	_polygon.color = _color_base
	_outline.color = _color_outline
	scale          = Vector2.ONE


func _animate_to_state() -> void:
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
	_tween.set_trans(
		Tween.TRANS_BACK if _state == TileState.SELECTED else Tween.TRANS_SINE
	)
	_tween.tween_property(_polygon, "color", target_color, duration)
	_tween.tween_property(self, "scale", Vector2(target_scale, target_scale), duration)
