## TileInspectorPanel.gd
## Attached to: scenes/ui/TileInspectorPanel.tscn
##
## TEMPORARY DEVELOPER INSPECTOR — not the final production UI.
## This panel exists to verify simulation data during development.
## Replace with the proper game UI when the HUD system is built.
##
## Usage:
##   Click any tile  → panel opens and shows that tile's sim data.
##   F2              → toggle panel visibility.
##   F1              → toggle the compact DebugOverlay (separate).
##
## Layout rule:
##   RootPanel is a direct child of a CanvasLayer, so it must be
##   positioned with .position / .size — not anchors or offset_*.
##   Anchors resolve against the CanvasLayer's own rect (always 0,0,0,0).

class_name TileInspectorPanel
extends CanvasLayer

# ─── Panel geometry ───────────────────────────────────────────────────────────
const PANEL_W: float = 300.0
const PANEL_H: float = 680.0
const MARGIN:  float = 10.0

# ─── Child nodes ──────────────────────────────────────────────────────────────
@onready var _root_panel:    PanelContainer = $RootPanel
@onready var _lbl_header:    Label = $RootPanel/Margin/VBox/Header
@onready var _lbl_coords:    Label = $RootPanel/Margin/VBox/CoordsRow
@onready var _lbl_soil:      Label = $RootPanel/Margin/VBox/SoilRow
@onready var _lbl_humidity:  Label = $RootPanel/Margin/VBox/HumidityRow
@onready var _lbl_fertility: Label = $RootPanel/Margin/VBox/FertilityRow
@onready var _lbl_drainage:  Label = $RootPanel/Margin/VBox/DrainageRow
@onready var _lbl_potential: Label = $RootPanel/Margin/VBox/PotentialRow
@onready var _lbl_planted:   Label = $RootPanel/Margin/VBox/PlantedRow
@onready var _lbl_grape:     Label = $RootPanel/Margin/VBox/GrapeRow
@onready var _lbl_age:       Label = $RootPanel/Margin/VBox/AgeRow
@onready var _lbl_lifecycle: Label = $RootPanel/Margin/VBox/LifecycleRow
@onready var _lbl_health:    Label = $RootPanel/Margin/VBox/HealthRow
@onready var _lbl_disease:   Label = $RootPanel/Margin/VBox/DiseaseRow
@onready var _lbl_quality:   Label = $RootPanel/Margin/VBox/QualityRow
@onready var _lbl_prod:      Label = $RootPanel/Margin/VBox/ProductivityRow
@onready var _lbl_ripeness:  Label = $RootPanel/Margin/VBox/RipenessRow
@onready var _lbl_sugar:     Label = $RootPanel/Margin/VBox/SugarRow
@onready var _lbl_acidity:   Label = $RootPanel/Margin/VBox/AcidityRow
@onready var _lbl_harvest:   Label = $RootPanel/Margin/VBox/HarvestRow
@onready var _lbl_harvested: Label = $RootPanel/Margin/VBox/HarvestedRow
@onready var _lbl_hint:      Label = $RootPanel/Margin/VBox/HintRow

# ─── State ────────────────────────────────────────────────────────────────────
var _current_data: TileSimData = null
var _soil_names:   Dictionary  = {}
var _positioned:   bool        = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_cache_soil_names()
	VineyardSimulation.tile_data_changed.connect(_on_tile_data_changed)
	get_viewport().size_changed.connect(_place_panel)
	_root_panel.visible = false
	_place_panel.call_deferred()


func _place_panel() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x < 100.0:
		vp = Vector2(1280.0, 720.0)
	_root_panel.position = Vector2(vp.x - PANEL_W - MARGIN, MARGIN)
	_root_panel.size     = Vector2(PANEL_W, PANEL_H)
	_positioned = true


# ─── Public API ───────────────────────────────────────────────────────────────

## Show the inspector for [param data]. Called by World on tile selection.
func show_tile(data: TileSimData) -> void:
	_current_data = data
	if data == null:
		_root_panel.visible = false
		return
	if not _positioned:
		_place_panel()
	_root_panel.visible = true
	_refresh()
	# One concise console log per selection — useful during development.
	print("Inspector: %s" % data.summary())


func hide_panel() -> void:
	_current_data = null
	_root_panel.visible = false


# ─── Private — sim data signal ────────────────────────────────────────────────

func _on_tile_data_changed(data: TileSimData) -> void:
	if _current_data == null or data == null:
		return
	if data.grid_col == _current_data.grid_col and \
	   data.grid_row == _current_data.grid_row:
		_current_data = data
		_refresh()


# ─── Private — display ────────────────────────────────────────────────────────

func _refresh() -> void:
	var d: TileSimData = _current_data
	if d == null or _lbl_coords == null:
		return

	_lbl_header.text    = "Tile Inspector"
	_lbl_coords.text    = "Coords      (%d, %d)" % [d.grid_col, d.grid_row]
	_lbl_soil.text      = "Soil        %s" % _soil_display_name(d.soil_type)
	_lbl_humidity.text  = "Humidity    %s" % _bar(d.humidity)
	_lbl_fertility.text = "Fertility   %s" % _bar(d.fertility)
	_lbl_drainage.text  = "Drainage    %s" % _bar(d.drainage)
	_lbl_potential.text = "Potential   %s" % _bar(d.quality_potential)

	# ── Locked tile — show minimal info and buy prompt ────────────────────
	if not d.is_owned:
		var cost: float = VineyardSimulation.calculate_land_cost(d.grid_col, d.grid_row)
		_lbl_planted.text   = "Locked land"
		_lbl_grape.text     = "Buy cost    €%.0f" % cost
		_lbl_age.text       = "Press B to buy"
		_lbl_lifecycle.text = "—"
		_lbl_health.text    = "—"
		_lbl_disease.text   = "—"
		_lbl_quality.text   = "—"
		_lbl_prod.text      = "—"
		_lbl_ripeness.text  = "—"
		_lbl_sugar.text     = "—"
		_lbl_acidity.text   = "—"
		_lbl_harvest.text   = "—"
		_lbl_harvested.text = "—"
		_lbl_hint.text      = "F2  show / hide"
		return

	if d.is_planted:
		var grape: String = d.grape_variety if d.grape_variety != "" else "unknown"
		_lbl_planted.text   = "Planted     yes"
		_lbl_grape.text     = "Grape       %s" % grape
		_lbl_age.text       = "Age         %s" % d.vine_age_label()
		_lbl_lifecycle.text = "Stage       %s" % d.lifecycle_stage.capitalize()
		_lbl_health.text    = "Health      %s" % _bar(d.vine_health)
		_lbl_disease.text   = "Disease     %s" % _risk_label(d.disease_risk)
		_lbl_quality.text   = "Quality     %s" % _bar(d.effective_quality)
		_lbl_prod.text      = "Productivity %s" % _bar(d.productivity)
		_lbl_ripeness.text  = "Ripeness    %s" % _bar(d.ripeness)
		_lbl_sugar.text     = "Sugar       %s" % _bar(d.sugar_level)
		_lbl_acidity.text   = "Acidity     %s" % _bar(d.acidity_level)
		if d.harvest_ready:
			_lbl_harvest.text = "Harvest     ★ READY"
		else:
			_lbl_harvest.text = "Harvest     not ready"
		_lbl_harvested.text = "Harvested   %s" % ("yes — done this year" if d.harvested_this_year else "no")
	else:
		_lbl_planted.text   = "Planted     empty"
		_lbl_grape.text     = "Grape       —"
		_lbl_age.text       = "Age         —"
		_lbl_lifecycle.text = "Stage       —"
		_lbl_health.text    = "Health      —"
		_lbl_disease.text   = "Disease     —"
		_lbl_quality.text   = "Quality     —"
		_lbl_prod.text      = "Productivity —"
		_lbl_ripeness.text  = "Ripeness    —"
		_lbl_sugar.text     = "Sugar       —"
		_lbl_acidity.text   = "Acidity     —"
		_lbl_harvest.text   = "Harvest     —"
		_lbl_harvested.text = "Harvested   —"

	_lbl_hint.text = "F2  show / hide"


# ─── Private — formatting ─────────────────────────────────────────────────────

func _bar(value: float, width: int = 8) -> String:
	var v: float    = clampf(value, 0.0, 1.0)
	var filled: int = int(v * float(width))
	return "█".repeat(filled) + "░".repeat(width - filled) + "  %d%%" % int(v * 100.0)


func _risk_label(risk: float) -> String:
	if risk < 0.15:
		return "Low   %d%%" % int(risk * 100.0)
	elif risk < 0.40:
		return "Med   %d%%" % int(risk * 100.0)
	return "High  %d%%" % int(risk * 100.0)


func _soil_display_name(soil_id: String) -> String:
	if _soil_names.has(soil_id):
		return str(_soil_names[soil_id])
	return soil_id


func _cache_soil_names() -> void:
	var raw: Dictionary = DataManager.get_data("soils")
	var arr: Variant    = raw.get("soils", [])
	if not arr is Array:
		return
	var soils: Array = arr
	for i: int in soils.size():
		if not soils[i] is Dictionary:
			continue
		var s: Dictionary = soils[i]
		var sid: String   = str(s.get("id", ""))
		if sid != "":
			_soil_names[sid] = str(s.get("name", sid))


# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and k.keycode == KEY_F2:
			_root_panel.visible = not _root_panel.visible
			get_viewport().set_input_as_handled()
