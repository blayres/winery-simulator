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
const PANEL_H: float = 380.0   # taller to fit Buy Land button
const MARGIN:  float = 10.0

# ─── Flash colors (match World.gd) ───────────────────────────────────────────
const FLASH_IRRIGATE: Color = Color(0.40, 0.70, 1.00, 1.0)
const FLASH_DRAIN:    Color = Color(0.85, 0.75, 0.40, 1.0)
const FLASH_TREAT:    Color = Color(0.40, 1.00, 0.55, 1.0)
const FLASH_PRUNE:    Color = Color(0.90, 0.90, 0.40, 1.0)
const FLASH_REPLANT:  Color = Color(0.55, 1.00, 0.55, 1.0)
const FLASH_HARVEST:  Color = Color(1.00, 0.85, 0.20, 1.0)
const FLASH_FERMENT:  Color = Color(0.80, 0.40, 0.90, 1.0)
const FLASH_BUY_LAND: Color = Color(1.00, 0.90, 0.30, 1.0)   # gold

# ─── Child nodes ──────────────────────────────────────────────────────────────
@onready var _root_panel:   PanelContainer = $RootPanel
@onready var _lbl_title:    Label          = $RootPanel/Margin/VBox/Title
@onready var _lbl_status:   Label          = $RootPanel/Margin/VBox/StatusLabel
@onready var _btn_buy_land: Button         = $RootPanel/Margin/VBox/BtnBuyLand
@onready var _btn_irrigate: Button         = $RootPanel/Margin/VBox/BtnIrrigate
@onready var _btn_drain:    Button         = $RootPanel/Margin/VBox/BtnDrain
@onready var _btn_treat:    Button         = $RootPanel/Margin/VBox/BtnTreat
@onready var _btn_prune:    Button         = $RootPanel/Margin/VBox/BtnPrune
@onready var _btn_replant:  Button         = $RootPanel/Margin/VBox/BtnReplant
@onready var _btn_harvest:  Button         = $RootPanel/Margin/VBox/BtnHarvest
@onready var _btn_ferment:  Button         = $RootPanel/Margin/VBox/BtnFerment

# ─── State ────────────────────────────────────────────────────────────────────
var _grid: GridSystem = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	get_viewport().size_changed.connect(_place_panel)
	_place_panel.call_deferred()

	# Wire button signals.
	_btn_buy_land.pressed.connect(_on_buy_land_pressed)
	_btn_irrigate.pressed.connect(_on_irrigate_pressed)
	_btn_drain.pressed.connect(_on_drain_pressed)
	_btn_treat.pressed.connect(_on_treat_pressed)
	_btn_prune.pressed.connect(_on_prune_pressed)
	_btn_replant.pressed.connect(_on_replant_pressed)
	_btn_harvest.pressed.connect(_on_harvest_pressed)
	_btn_ferment.pressed.connect(_on_ferment_pressed)

	# Listen for action results to refresh button state.
	VineyardActionSystem.action_performed.connect(_on_action_performed)
	# Refresh when money changes — buttons may become affordable/unaffordable.
	WineMarket.money_changed.connect(_on_money_changed)
	# Refresh when fermentation method changes — cost shown on Ferment button changes.
	FermentationManager.method_changed.connect(_on_method_changed)

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
	_refresh_buttons()


func _on_money_changed(_new_amount: float, _delta: float) -> void:
	_refresh_buttons()


func _on_method_changed(_method: String) -> void:
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

	var costs: Dictionary = _costs()
	var money: float      = WineMarket.get_money()

	# ── Locked tile: show only Buy Land ──────────────────────────────────
	if not data.is_owned:
		var land_cost: float = VineyardSimulation.calculate_land_cost(sel.grid_col, sel.grid_row)
		_lbl_status.text = "(%d,%d)  Locked  €%.0f" % [sel.grid_col, sel.grid_row, money]
		_btn_buy_land.text     = "Buy Land  €%.0f" % land_cost
		_btn_buy_land.disabled = money < land_cost
		_btn_buy_land.visible  = true
		_btn_irrigate.visible  = false
		_btn_drain.visible     = false
		_btn_treat.visible     = false
		_btn_prune.visible     = false
		_btn_replant.visible   = false
		_btn_harvest.visible   = false
		_btn_ferment.visible   = false
		return

	# ── Owned tile: show all management actions ───────────────────────────
	_btn_buy_land.visible  = false
	_btn_irrigate.visible  = true
	_btn_drain.visible     = true
	_btn_treat.visible     = true
	_btn_prune.visible     = true
	_btn_replant.visible   = true
	_btn_harvest.visible   = true
	_btn_ferment.visible   = true

	# Update button text with costs and disable if unaffordable.
	_btn_irrigate.text     = "Irrigate  €%d" % int(costs.get("irrigate", 50))
	_btn_drain.text        = "Drain  €%d"    % int(costs.get("drain",    70))
	_btn_treat.text        = "Treat  €%d"    % int(costs.get("treat",   120))
	_btn_prune.text        = "Prune  €%d"    % int(costs.get("prune",    80))
	_btn_replant.text      = "Replant  €%d"  % int(costs.get("replant", 300))
	_btn_harvest.text      = "Harvest  €%d"  % int(costs.get("harvest",  50))
	var _ferment_cost_owned: float = FermentationManager.get_method_cost(FermentationManager.get_selected_method())
	_btn_ferment.text      = "Ferment  €%d"  % int(_ferment_cost_owned)

	_btn_irrigate.disabled = money < float(costs.get("irrigate", 50))
	_btn_drain.disabled    = money < float(costs.get("drain",    70))
	_btn_replant.disabled  = money < float(costs.get("replant", 300))

	_btn_treat.disabled = not data.is_planted or money < float(costs.get("treat", 120))
	_btn_prune.disabled = not data.is_planted or money < float(costs.get("prune",  80))

	_btn_harvest.disabled = not (
		data.is_planted and data.harvest_ready and
		not data.harvested_this_year
	) or money < float(costs.get("harvest", 50))

	_btn_ferment.disabled = HarvestManager.get_lot_count() == 0 or \
			money < _ferment_cost_owned

	if data.is_planted:
		var harvest_hint: String = "  ★" if data.harvest_ready and not data.harvested_this_year else ""
		_lbl_status.text = "(%d,%d)  %s%s  €%.0f" % [
			sel.grid_col, sel.grid_row,
			data.lifecycle_stage.capitalize(), harvest_hint, money
		]
	else:
		_lbl_status.text = "(%d,%d)  empty  €%.0f" % [sel.grid_col, sel.grid_row, money]


func _set_no_selection() -> void:
	var costs: Dictionary = _costs()
	var money: float      = WineMarket.get_money()

	_lbl_status.text = "No tile selected  €%.0f" % money

	_btn_buy_land.visible  = false
	_btn_irrigate.visible  = true
	_btn_drain.visible     = true
	_btn_treat.visible     = true
	_btn_prune.visible     = true
	_btn_replant.visible   = true
	_btn_harvest.visible   = true
	_btn_ferment.visible   = true

	_btn_irrigate.text     = "Irrigate  €%d" % int(costs.get("irrigate", 50))
	_btn_drain.text        = "Drain  €%d"    % int(costs.get("drain",    70))
	_btn_treat.text        = "Treat  €%d"    % int(costs.get("treat",   120))
	_btn_prune.text        = "Prune  €%d"    % int(costs.get("prune",    80))
	_btn_replant.text      = "Replant  €%d"  % int(costs.get("replant", 300))
	_btn_harvest.text      = "Harvest  €%d"  % int(costs.get("harvest",  50))
	var _ferment_cost_none: float = FermentationManager.get_method_cost(FermentationManager.get_selected_method())
	_btn_ferment.text      = "Ferment  €%d"  % int(_ferment_cost_none)

	_btn_irrigate.disabled = true
	_btn_drain.disabled    = true
	_btn_treat.disabled    = true
	_btn_prune.disabled    = true
	_btn_replant.disabled  = true
	_btn_harvest.disabled  = true
	_btn_ferment.disabled  = HarvestManager.get_lot_count() == 0 or \
			money < _ferment_cost_none


# ─── Private — button handlers ────────────────────────────────────────────────

func _on_buy_land_pressed() -> void:
	var sel: VineyardTile = _get_selected()
	if sel == null:
		return
	VineyardActionSystem.buy_land(sel.grid_col, sel.grid_row)
	sel.flash_action(FLASH_BUY_LAND)


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


func _on_harvest_pressed() -> void:
	var sel: VineyardTile = _get_selected()
	if sel == null:
		return
	VineyardActionSystem.harvest(sel.grid_col, sel.grid_row)
	sel.flash_action(FLASH_HARVEST)


func _on_ferment_pressed() -> void:
	# Ferment does not require a selected tile — uses most recent grape lot.
	VineyardActionSystem.ferment()
	# Flash the selected tile if one exists, otherwise no visual feedback needed.
	var sel: VineyardTile = _get_selected()
	if sel != null:
		sel.flash_action(FLASH_FERMENT)


func _get_selected() -> VineyardTile:
	if _grid == null:
		return null
	return _grid.get_selected_tile()


## Returns the action costs dictionary from JSON config.
func _costs() -> Dictionary:
	var cfg: Dictionary    = DataManager.get_data("vineyard_sim")
	var raw_pa: Variant    = cfg.get("player_actions", {})
	if not raw_pa is Dictionary:
		return {}
	var raw_costs: Variant = (raw_pa as Dictionary).get("costs", {})
	return raw_costs if raw_costs is Dictionary else {}
