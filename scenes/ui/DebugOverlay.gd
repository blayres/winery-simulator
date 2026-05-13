## DebugOverlay.gd
## Compact always-visible HUD.
## Shows: time, climate, selected tile, zoom, grid, hints.
## F1 toggles visibility.
## Uses position+size (not anchors) — direct child of a CanvasLayer.

class_name DebugOverlay
extends CanvasLayer

const PANEL_W: float = 340.0
const PANEL_H: float = 310.0
const MARGIN:  float = 10.0

var _grid:   GridSystem       = null
var _camera: CameraController = null

@onready var _panel:       PanelContainer = $Panel
@onready var _lbl_time:    Label = $Panel/Margin/VBox/TimeLabel
@onready var _lbl_auto:    Label = $Panel/Margin/VBox/AutoLabel
@onready var _lbl_climate: Label = $Panel/Margin/VBox/ClimateLabel
@onready var _lbl_temp:    Label = $Panel/Margin/VBox/TempLabel
@onready var _lbl_rain:    Label = $Panel/Margin/VBox/RainLabel
@onready var _lbl_hum:     Label = $Panel/Margin/VBox/HumLabel
@onready var _lbl_wind:    Label = $Panel/Margin/VBox/WindLabel
@onready var _lbl_tile:    Label = $Panel/Margin/VBox/TileLabel
@onready var _lbl_soil:    Label = $Panel/Margin/VBox/SoilLabel
@onready var _lbl_zoom:    Label = $Panel/Margin/VBox/ZoomLabel
@onready var _lbl_grid:    Label = $Panel/Margin/VBox/GridLabel
@onready var _lbl_hint:    Label = $Panel/Margin/VBox/HintLabel

func _ready() -> void:
	_panel.visible = true
	get_viewport().size_changed.connect(_place_panel)
	_place_panel.call_deferred()


func _place_panel() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x < 100.0:
		vp = Vector2(1280.0, 720.0)
	_panel.position = Vector2(vp.x - PANEL_W - MARGIN, vp.y - PANEL_H - MARGIN)
	_panel.size     = Vector2(PANEL_W, PANEL_H)


func _process(_delta: float) -> void:
	_update_labels()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and k.keycode == KEY_F1:
			_panel.visible = not _panel.visible
			get_viewport().set_input_as_handled()


func init(grid: GridSystem, camera: CameraController) -> void:
	_grid   = grid
	_camera = camera


func _update_labels() -> void:
	# ── Time ──────────────────────────────────────────────────────────────
	_lbl_time.text = "Time    %s" % TimeManager.get_time_string()
	_lbl_auto.text = "Auto    %s" % ("ON  (T to stop)" if TimeManager.auto_advance \
			else "OFF  (T to start)")

	# ── Climate ───────────────────────────────────────────────────────────
	_lbl_climate.text = "Weather %s  (score %.0f%%)" % [
		ClimateManager.condition,
		ClimateManager.weekly_climate_score * 100.0
	]
	_lbl_temp.text = "Temp    %.1f°C" % ClimateManager.temperature
	_lbl_rain.text = "Rain    %.0f mm" % ClimateManager.rainfall
	_lbl_hum.text  = "Humid   %d%%" % int(ClimateManager.humidity * 100.0)
	_lbl_wind.text = "Wind    %.0f km/h" % ClimateManager.wind

	# ── Selected tile ─────────────────────────────────────────────────────
	if _grid == null:
		_lbl_tile.text = "Tile    -"
		_lbl_soil.text = "Soil    -"
		_lbl_zoom.text = "Zoom    -"
		_lbl_grid.text = "Grid    -"
		_lbl_hint.text = "F1 overlay · F2 inspector"
		return

	var sel: VineyardTile = _grid.get_selected_tile()
	if sel != null:
		_lbl_tile.text = "Tile    (%d, %d)" % [sel.grid_col, sel.grid_row]
		var d: TileSimData = VineyardSimulation.get_tile_data(sel.grid_col, sel.grid_row)
		if d != null:
			var ph: String = " · " + d.grape_variety if d.is_planted else " · empty"
			_lbl_soil.text = "Soil    %s%s" % [d.soil_type.replace("_", " "), ph]
		else:
			_lbl_soil.text = "Soil    -"
	else:
		_lbl_tile.text = "Tile    -"
		_lbl_soil.text = "Soil    -"

	var gs: Vector2i = _grid.get_grid_size()
	_lbl_grid.text = "Grid    %d × %d" % [gs.x, gs.y]

	if _camera != null:
		_lbl_zoom.text = "Zoom    %.2f×" % _camera.get_zoom_level()
	else:
		_lbl_zoom.text = "Zoom    -"

	_lbl_hint.text = "F1 overlay · F2 inspector · Space week · Shift+Space season · Y auto · I/D/T/P/R actions"
