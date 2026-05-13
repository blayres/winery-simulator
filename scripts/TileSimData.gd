## TileSimData.gd
## class_name: TileSimData
## Type: Resource (NOT a Node)
##
## Responsibility:
##   Pure data container for one vineyard tile's simulation state.
##   No rendering, no scene tree, no signals.
##
## Architecture note:
##   Using Resource (not Dictionary) gives us:
##     - Type safety and autocomplete
##     - Native Godot save/load via ResourceSaver (future)
##     - Clean separation from visual layer
##     - Cheap duplication via .duplicate()
##
##   VineyardTile (visual) holds a reference to TileSimData.
##   VineyardSimulation (autoload) owns and mutates all TileSimData instances.
##   The visual layer NEVER writes to TileSimData — it only reads.
##
## Save compatibility:
##   All fields are @export so ResourceSaver can serialize them.
##   String IDs (soil_type, grape_variety) reference JSON data keys.

class_name TileSimData
extends Resource

# ─── Grid identity ────────────────────────────────────────────────────────────
@export var grid_col: int = 0
@export var grid_row: int = 0

# ─── Terroir (set at world generation, rarely changes) ────────────────────────
## ID matching a soil entry in data/terroir/soils.json
@export var soil_type: String = "limestone_clay"

## 0.0–1.0  base fertility from soil, modified by player actions later
@export var fertility: float = 0.70

## 0.0–1.0  how well this tile drains water (from soil archetype)
@export var drainage: float = 0.60

## 0.0–1.0  current moisture level — varies tile-to-tile and season-to-season
@export var humidity: float = 0.50

## 0.0–1.0  intrinsic quality ceiling for wine from this tile
@export var quality_potential: float = 0.75

# ─── Vine state ───────────────────────────────────────────────────────────────
## Whether a vine has been planted on this tile
@export var is_planted: bool = false

## ID matching a grape entry in data/grapes/grapes.json ("" = none)
@export var grape_variety: String = ""

## Age in seasons (4 seasons = 1 year). Young vines < 12, mature 12–80, old > 80.
@export var vine_age: int = 0

## 0.0–1.0  current vine health
@export var vine_health: float = 0.0

## 0.0–1.0  current disease risk level
@export var disease_risk: float = 0.05

# ─── Derived / cached ─────────────────────────────────────────────────────────
## Effective quality = quality_potential × soil modifier × vine health factor.
## Recomputed by VineyardSimulation — cached here for fast reads by UI/renderer.
@export var effective_quality: float = 0.0

## Lifecycle stage: "empty" | "young" | "mature" | "old" | "declining"
## Set by VineLifecycle.update_stage() each year.
@export var lifecycle_stage: String = "empty"

## 0.0–1.0  estimated yield/output capacity this season.
## Combines age stage, health, disease, and climate score.
@export var productivity: float = 0.0

# ─── Ripeness ─────────────────────────────────────────────────────────────────
## 0.0–1.0  current grape ripeness. Progresses in summer/autumn, resets in spring.
@export var ripeness: float = 0.0

## 0.0–1.0  sugar content. Rises with ripeness and warm temperatures.
@export var sugar_level: float = 0.20

## 0.0–1.0  acidity level. Decreases as ripeness rises (inverse relationship).
@export var acidity_level: float = 0.85

## True when ripeness ≥ harvest_ready_threshold and vine is mature/old.
@export var harvest_ready: bool = false

# ─── Helpers ──────────────────────────────────────────────────────────────────

## Returns a human-readable summary string for debug display.
func summary() -> String:
	var planted_str: String = grape_variety if is_planted else "empty"
	var ripe_str: String = "  ripe=%.2f sug=%.2f acid=%.2f%s" % [
		ripeness, sugar_level, acidity_level,
		"  READY" if harvest_ready else ""
	] if is_planted else ""
	return (
		"[%d,%d] soil=%s  humidity=%.2f  fertility=%.2f\n" +
		"       planted=%s  stage=%s  age=%dy  health=%.2f  quality=%.2f  disease=%.2f  prod=%.2f%s"
	) % [
		grid_col, grid_row, soil_type, humidity, fertility,
		planted_str, lifecycle_stage, vine_age / 4,
		vine_health, effective_quality, disease_risk, productivity, ripe_str
	]


## Returns the vine age as a readable string including lifecycle stage.
func vine_age_label() -> String:
	if not is_planted:
		return "—"
	var years: int = vine_age / 4
	return "%s  (%dy)" % [lifecycle_stage.capitalize(), years]


## Returns a 0–3 health tier: 0=poor, 1=fair, 2=good, 3=excellent
func health_tier() -> int:
	if vine_health >= 0.80:
		return 3
	elif vine_health >= 0.55:
		return 2
	elif vine_health >= 0.30:
		return 1
	else:
		return 0
