## GrapeLot.gd
## Pure data Resource — one harvested batch of grapes from a single tile.
##
## Created by HarvestManager when a tile is harvested.
## Passed to future fermentation/winemaking systems.
## All fields are @export for future ResourceSaver compatibility.
##
## Architecture:
##   GrapeLot is READ-ONLY after creation.
##   HarvestManager creates it; WineManager (future) consumes it.
##   No methods that mutate state — only helpers for display.

class_name GrapeLot
extends Resource

# ─── Identity ─────────────────────────────────────────────────────────────────
@export var lot_id:       int    = 0
@export var harvest_year: int    = 1

# ─── Source tile ──────────────────────────────────────────────────────────────
@export var source_col:   int    = 0
@export var source_row:   int    = 0
@export var soil_type:    String = ""

# ─── Grape data ───────────────────────────────────────────────────────────────
@export var grape_variety:     String = ""
@export var ripeness:          float  = 0.0
@export var sugar_level:       float  = 0.0
@export var acidity_level:     float  = 0.0
@export var vine_health:       float  = 0.0
@export var productivity:      float  = 0.0
@export var quality_potential: float  = 0.0
@export var disease_risk:      float  = 0.0

# ─── Computed ─────────────────────────────────────────────────────────────────
## 0.0–1.0  estimated grape quality for winemaking.
## Computed at harvest time from all contributing factors.
@export var estimated_grape_quality: float = 0.0

# ─── Helpers ──────────────────────────────────────────────────────────────────

## One-line summary for console logging.
func summary() -> String:
	return "GrapeLot #%d  Year %d  %s @ (%d,%d)  quality=%.2f  sugar=%.2f  acidity=%.2f" % [
		lot_id, harvest_year, grape_variety,
		source_col, source_row,
		estimated_grape_quality, sugar_level, acidity_level
	]


## Quality tier label for UI display.
## Thresholds calibrated to the actual grape_quality output range (~0.20–0.55).
func quality_label() -> String:
	if estimated_grape_quality >= 0.50:
		return "Exceptional"
	elif estimated_grape_quality >= 0.38:
		return "Good"
	elif estimated_grape_quality >= 0.25:
		return "Average"
	else:
		return "Poor"
