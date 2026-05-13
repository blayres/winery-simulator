## VineyardActionsPanel.gd
## Attached to: scenes/ui/VineyardActionsPanel.tscn
##
## TEMPORARY DEVELOPER UI — not the final production panel.
## Provides clickable buttons for all vineyard actions on the selected tile.
## Replace with the proper game HUD when the UI system is built.
##
## Architecture:
##   Buttons call VineyardActionSystem — no action logic lives here.
##   Panel state (enabled/disabled buttons) is driven by the selected tile's
##   TileSimData, read from VineyardSimulation.
##   World injects the GridSystem reference via init() after grid is ready.
##
## Layout rule:
##   Panel is a direct child of a CanvasLayer — use position/size, not anchors.

class_name VineyardActionsPanel
extends CanvasLayer

# ─── Panel geometry ───────────────────────────────────────────────────────────
const PANEL_W: float = 160.0
const PANEL_H: float = 260.0
const MARGIN:  float = 10.0

# ─── Flash colors (match World.gd) ───────────────────────────────────────────
const FLASH_IRRIGATE: Color = Color(0.40, 0.70, 1.00, 1.0)
const FLASH_DRAIN:    Color = Color(0.85, 0.75, 0.40, 1.0)
const FLASH_TREAT:    Color = Color(0.40, 1.00, 0.55, 1.0)
const FLASH_PRUNE:    Color = Color(0.90, 0.90, 0.40, 1.0)
const FLASH_REPLANT:  Color = Color(0.55, 1.00, 0.55, 1.0)

# ─── Child nodes ──────────────────────────────────────────────────────────────
@onready var _root_panel:   PanelContainer = $RootPanel
@onready var _lbl_title:    Label          = $RootPanel/Margin/VBox/Title
@onready var _lbl_status:   Label          = $RootPanel/Margin/VBox/StatusLabel
@onready var _btn_irrigate: Button         = $RootPanel/Margin/VBox/BtnIrrigate
@onready var _btn_drain:    Button         = $RootPanel/Margin/VBox/BtnDrain
@onready var _btn_treat:    Button         = $RootPanel/Margin/VBox/BtnTreat
@onready var _btn_prune:    Button         = $RootPanel/Margin/VBox/BtnPrune
@onready var _btn_replant:  Button         = $RootPanel/Margin/VBox/BtnReplant

# ─── State ────────────────────────────────────────────────────────────────────
var _grid: GridSystem = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	get_viewport().size_changed.connect(_place_panel)
	_place_panel.call_deferred()

	# Wire button signals.
	_btn_irrigate.pressed.connect(_on_irrigate_pressed)
	_btn_drain.pressed.connect(_on_drain_pressed)
	_btn_treat.pressed.connect(_on_treat_pressed)
	_btn_prune.pressed.connect(_on_prune_pressed)
	_btn_replant.pressed.connect(_on_replant_pressed)

	# Listen for action results to refresh button state.
	VineyardActionSystem.action_performed.connect(_on_action_performed)

	_set_no_selection()


func _place_panel() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x < 100.0:
		vp = Vector2(1280.0, 720.0)
	# Bottom-left corner.
	_root_panel.position = Vector2(MARGIN, vp.y - PANEL_H - MARGIN)
	_root_panel.size     = Vector2(PANEL_W, PANEL_H)


# ─── Public API ───────────────────────────────────────────────────────────────

## Called by World after grid is ready.
func init(grid: GridSystem) -> void:
	_grid = grid
	_grid.tile_selected.connect(_on_tile_selected)
	_grid.tile_unhovered.connect(_on_tile_unhovered)


# ─── Private — selection state ────────────────────────────────────────────────

func _on_tile_selected(_tile: VineyardTile) -> void:
	_refresh_buttons()


func _on_tile_unhovered(_tile: VineyardTile) -> void:
	# Don't clear on unhover — only clear when selection is explicitly lost.
	pass


func _on_action_performed(_action: String, _col: int, _row: int, _result: String) -> void:
	# Refresh button states after any action (planted state may have changed).
	_refresh_buttons()


func _refresh_buttons() -> void:
	if _grid == null:
		_set_no_selection()
		return

	var sel: VineyardTile = _grid.get_selected_tile()
	if sel == null:
		_set_no_selection()
		return

	var data: TileSimData = VineyardSimulation.get_tile_data(sel.grid_col, sel.grid_row)
	if data == null:
		_set_no_selection()
		return

	# All buttons enabled when a tile is selected.
	_btn_irrigate.disabled = false
	_btn_drain.disabled    = false
	_btn_replant.disabled  = false

	# Planted-only actions.
	_btn_treat.disabled = not data.is_planted
	_btn_prune.disabled = not data.is_planted

	# Status line.
	if data.is_planted:
		_lbl_status.text = "(%d,%d)  %s" % [sel.grid_col, sel.grid_row,
				data.lifecycle_stage.capitalize()]
	else:
		_lbl_status.text = "(%d,%d)  empty" % [sel.grid_col, sel.grid_row]


func _set_no_selection() -> void:
	_lbl_status.text       = "No tile selected"
	_btn_irrigate.disabled = true
	_btn_drain.disabled    = true
	_btn_treat.disabled    = true
	_btn_prune.disabled    = true
	_btn_replant.disabled  = true


# ─── Private — button handlers ────────────────────────────────────────────────

func _on_irrigate_pressed() -> void:
	var sel: VineyardTile = _get_selected()
	if sel == null:
		return
	VineyardActionSystem.irrigate(sel.grid_col, sel.grid_row)
	sel.flash_action(FLASH_IRRIGATE)


func _on_drain_pressed() -> void:
	var sel: VineyardTile = _get_selected()
	if sel == null:
		return
	VineyardActionSystem.drain(sel.grid_col, sel.grid_row)
	sel.flash_action(FLASH_DRAIN)


func _on_treat_pressed() -> void:
	var sel: VineyardTile = _get_selected()
	if sel == null:
		return
	VineyardActionSystem.treat_disease(sel.grid_col, sel.grid_row)
	sel.flash_action(FLASH_TREAT)


func _on_prune_pressed() -> void:
	var sel: VineyardTile = _get_selected()
	if sel == null:
		return
	VineyardActionSystem.prune(sel.grid_col, sel.grid_row)
	sel.flash_action(FLASH_PRUNE)


func _on_replant_pressed() -> void:
	var sel: VineyardTile = _get_selected()
	if sel == null:
		return
	VineyardActionSystem.replant(sel.grid_col, sel.grid_row)
	sel.flash_action(FLASH_REPLANT)


func _get_selected() -> VineyardTile:
	if _grid == null:
		return null
	return _grid.get_selected_tile()
