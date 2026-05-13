## World.gd
## Attached to: scenes/world/World.tscn (root node)
##
## Responsibility:
##   Integration layer — wires GridSystem, CameraController,
##   VineyardSimulation, DebugOverlay, and TileInspectorPanel together.
##
## Data flow:
##   GridSystem.grid_ready
##     → World._on_grid_ready()
##         → VineyardSimulation.initialize_grid()
##         → World._link_sim_data_to_tiles()
##         → _debug.init() / _inspector ready
##
##   GridSystem.tile_selected(tile)
##     → World._on_tile_selected(tile)
##         → VineyardSimulation.get_tile_data(col, row)  → TileSimData
##         → _inspector.show_tile(data)
##
##   VineyardSimulation.tile_data_changed(data)
##     → World._on_tile_data_changed(data)
##         → GridSystem.get_tile(col, row)  → VineyardTile
##         → tile.notify_sim_updated()

class_name World
extends Node2D

# ─── Child references ─────────────────────────────────────────────────────────
@onready var _grid:      GridSystem         = $GridSystem
@onready var _camera:    CameraController   = $WorldCamera
@onready var _debug:     DebugOverlay       = $WorldUI/DebugOverlay
@onready var _inspector: TileInspectorPanel = $TileInspectorPanel
@onready var _actions:   VineyardActionsPanel = $VineyardActionsPanel

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Validate all child references before connecting anything.
	if not _validate_children():
		return

	_apply_background_color()

	# Connect BEFORE triggering anything that might emit grid_ready.
	_grid.grid_ready.connect(_on_grid_ready)
	_grid.tile_selected.connect(_on_tile_selected)
	_grid.tile_hovered.connect(_on_tile_hovered)
	_grid.tile_unhovered.connect(_on_tile_unhovered)

	VineyardSimulation.tile_data_changed.connect(_on_tile_data_changed)

	# Trigger grid build now that we are connected.
	# GridSystem deferred its build waiting for this call.
	_grid.build_when_ready()

	# Put GameManager into PLAYING state so time can advance.
	GameManager.start_game()

	print("World: _ready() complete — grid build triggered.")


# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_grid_ready() -> void:
	print("World: grid_ready received.")

	# ── 1. Camera bounds ──────────────────────────────────────────────────
	var tile_size: Vector2  = _grid.get_tile_size()
	var grid_size: Vector2i = _grid.get_grid_size()
	var bounds: Rect2 = IsometricUtils.grid_bounds(
		grid_size.x, grid_size.y, tile_size.x, tile_size.y
	)
	var cfg: Dictionary     = DataManager.get_data("world_config")
	var raw_cam: Variant    = cfg.get("camera", {})
	var cam_cfg: Dictionary = raw_cam if raw_cam is Dictionary else {}
	var margin: float       = float(cam_cfg.get("bounds_margin", 300.0))
	_camera.set_bounds(bounds, margin)
	_camera.snap_to(bounds.get_center())

	# ── 2. Initialize simulation ──────────────────────────────────────────
	print("World: calling VineyardSimulation.initialize_grid(%d, %d)." \
			% [grid_size.x, grid_size.y])
	VineyardSimulation.initialize_grid(grid_size.x, grid_size.y)

	# Verify sim data was actually created.
	var sample: TileSimData = VineyardSimulation.get_tile_data(0, 0)
	if sample == null:
		push_error("World: VineyardSimulation.get_tile_data(0,0) returned null after init!")
	else:
		print("World: sim data verified — tile(0,0) soil=%s humidity=%.2f" \
				% [sample.soil_type, sample.humidity])

	# ── 3. Link sim data to tile nodes ────────────────────────────────────
	_link_sim_data_to_tiles()

	# ── 4. Wire debug overlay and actions panel ──────────────────────────
	_debug.init(_grid, _camera)
	_actions.init(_grid)

	print("World: fully initialized. Grid=%s" % str(grid_size))


func _on_tile_selected(tile: VineyardTile) -> void:
	print("World: tile_selected signal received — col=%d row=%d" \
			% [tile.grid_col, tile.grid_row])

	var data: TileSimData = VineyardSimulation.get_tile_data(tile.grid_col, tile.grid_row)

	if data == null:
		push_error("World: get_tile_data(%d,%d) returned null — sim not initialized?" \
				% [tile.grid_col, tile.grid_row])
		return

	print("World: passing TileSimData to inspector — soil=%s planted=%s" \
			% [data.soil_type, str(data.is_planted)])

	_inspector.show_tile(data)


func _on_tile_hovered(_tile: VineyardTile) -> void:
	pass


func _on_tile_unhovered(_tile: VineyardTile) -> void:
	pass


func _on_tile_data_changed(data: TileSimData) -> void:
	var tile: VineyardTile = _grid.get_tile(data.grid_col, data.grid_row)
	if tile != null:
		tile.notify_sim_updated()


# ─── Dev time controls ────────────────────────────────────────────────────────
## Temporary developer shortcuts — remove or gate behind a debug flag later.
##   Space            → advance one week
##   Shift + Space    → advance one full season (4 weeks)
##   Y                → toggle auto-advance  (was T — freed for Treat Disease)
##
## Vineyard action hotkeys (selected tile only):
##   I  → Irrigate      (raise humidity)
##   D  → Drain         (lower humidity)
##   T  → Treat Disease (reduce disease risk — planted only)
##   P  → Prune         (improve health/productivity — planted only)
##   R  → Replant       (plant or replace vine)
##   H  → Harvest       (collect ripe grapes — harvest_ready only)
##   G  → [DEV] Force harvest-ready state on selected tile (debug only)
##
## Global hotkeys (no tile required):
##   F  → Ferment most recent grape lot (stainless steel)

# Flash colors per action — defined here so they're easy to tune.
const FLASH_IRRIGATE: Color = Color(0.40, 0.70, 1.00, 1.0)   # blue
const FLASH_DRAIN:    Color = Color(0.85, 0.75, 0.40, 1.0)   # sandy
const FLASH_TREAT:    Color = Color(0.40, 1.00, 0.55, 1.0)   # green
const FLASH_PRUNE:    Color = Color(0.90, 0.90, 0.40, 1.0)   # yellow
const FLASH_REPLANT:  Color = Color(0.55, 1.00, 0.55, 1.0)   # bright green
const FLASH_HARVEST:  Color = Color(1.00, 0.85, 0.20, 1.0)   # golden
const FLASH_FERMENT:  Color = Color(0.80, 0.40, 0.90, 1.0)   # purple/wine

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var k: InputEventKey = event
	if not k.pressed:
		return

	# ── Time controls ─────────────────────────────────────────────────────
	if k.keycode == KEY_SPACE and k.shift_pressed:
		TimeManager.advance_season_full()
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_SPACE:
		TimeManager.advance_week()
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_Y:
		TimeManager.toggle_auto_advance()
		get_viewport().set_input_as_handled()
		return

	# ── Vineyard actions — require a selected tile ─────────────────────────
	var sel: VineyardTile = _grid.get_selected_tile()
	if sel == null:
		return

	var col: int = sel.grid_col
	var row: int = sel.grid_row

	match k.keycode:
		KEY_I:
			var result: String = VineyardActionSystem.irrigate(col, row)
			_flash_tile(sel, FLASH_IRRIGATE)
			get_viewport().set_input_as_handled()
		KEY_D:
			var result: String = VineyardActionSystem.drain(col, row)
			_flash_tile(sel, FLASH_DRAIN)
			get_viewport().set_input_as_handled()
		KEY_T:
			var result: String = VineyardActionSystem.treat_disease(col, row)
			_flash_tile(sel, FLASH_TREAT)
			get_viewport().set_input_as_handled()
		KEY_P:
			var result: String = VineyardActionSystem.prune(col, row)
			_flash_tile(sel, FLASH_PRUNE)
			get_viewport().set_input_as_handled()
		KEY_R:
			var result: String = VineyardActionSystem.replant(col, row)
			_flash_tile(sel, FLASH_REPLANT)
			get_viewport().set_input_as_handled()
		KEY_H:
			var result: String = VineyardActionSystem.harvest(col, row)
			_flash_tile(sel, FLASH_HARVEST)
			get_viewport().set_input_as_handled()
		KEY_G:
			# DEV: force selected tile into harvest-ready state for testing.
			var result: String = VineyardActionSystem.debug_force_harvest_ready(col, row)
			_flash_tile(sel, FLASH_HARVEST)
			get_viewport().set_input_as_handled()

	# ── Ferment — does not require a selected tile ────────────────────────
	if k.keycode == KEY_F:
		var result: String = VineyardActionSystem.ferment()
		print("Ferment: %s" % result)
		get_viewport().set_input_as_handled()


func _flash_tile(tile: VineyardTile, color: Color) -> void:
	tile.flash_action(color)


# ─── Private ──────────────────────────────────────────────────────────────────

## Validates all @onready references and logs any that are null.
## Returns false if any critical reference is missing.
func _validate_children() -> bool:
	var ok: bool = true
	if _grid == null:
		push_error("World: $GridSystem is null — check World.tscn node names.")
		ok = false
	if _camera == null:
		push_error("World: $WorldCamera is null — check World.tscn node names.")
		ok = false
	if _debug == null:
		push_error("World: $WorldUI/DebugOverlay is null — DebugOverlay.tscn may have failed to load.")
		ok = false
	if _inspector == null:
		push_error("World: $TileInspectorPanel is null — TileInspectorPanel.tscn may have failed to load.")
		ok = false
	if _actions == null:
		push_error("World: $VineyardActionsPanel is null — VineyardActionsPanel.tscn may have failed to load.")
		ok = false
	return ok


## Attach TileSimData to each VineyardTile node and trigger initial visual refresh.
func _link_sim_data_to_tiles() -> void:
	var all_tiles: Array = _grid.get_all_tiles()
	var linked: int      = 0
	var missing: int     = 0

	for i: int in all_tiles.size():
		if not all_tiles[i] is VineyardTile:
			continue
		var tile: VineyardTile = all_tiles[i]
		var data: TileSimData  = VineyardSimulation.get_tile_data(tile.grid_col, tile.grid_row)
		if data == null:
			missing += 1
			continue
		tile.sim_data = data
		tile.notify_sim_updated()
		linked += 1

	print("World: linked %d tiles with sim data (%d missing)." % [linked, missing])


func _apply_background_color() -> void:
	var cfg: Dictionary   = DataManager.get_data("world_config")
	var raw_atmo: Variant = cfg.get("atmosphere", {})
	if not raw_atmo is Dictionary:
		return
	var atmo: Dictionary = raw_atmo
	var raw_col: Variant = atmo.get("background_color", "3d5a4a")
	RenderingServer.set_default_clear_color(Color(str(raw_col)))
