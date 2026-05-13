## WineBatch.gd
## Pure data Resource — one fermented wine batch.
##
## Created by FermentationManager from a GrapeLot.
## Passed to future aging/bottling/selling systems.
## All fields are @export for future ResourceSaver compatibility.
##
## Architecture:
##   WineBatch is READ-ONLY after creation.
##   FermentationManager creates it; future systems consume it.
##   No methods that mutate state — only helpers for display.

class_name WineBatch
extends Resource

# ─── Identity ─────────────────────────────────────────────────────────────────
@export var batch_id:          int    = 0
@export var wine_name:         String = ""
@export var grape_variety:     String = ""
@export var vintage_year:      int    = 1
@export var fermentation_method: String = "stainless_steel"

# ─── Source grape data ────────────────────────────────────────────────────────
@export var source_grape_quality: float = 0.0
@export var source_sugar:         float = 0.0
@export var source_acidity:       float = 0.0
@export var source_lot_id:        int   = 0

# ─── Wine profile ─────────────────────────────────────────────────────────────
## 0.0–1.0  estimated alcohol by volume (maps to ~8–16% ABV)
@export var alcohol_potential: float = 0.0

## 0.0–1.0  freshness / fruit-forward character
@export var freshness: float = 0.0

## 0.0–1.0  body / weight / tannin structure
@export var body: float = 0.0

## 0.0–1.0  aromatic and flavour complexity
@export var complexity: float = 0.0

## 0.0–1.0  oak influence (0 = none, 1 = heavily oaked)
@export var oak_influence: float = 0.0

## 0.0–1.0  overall wine quality score
@export var wine_quality: float = 0.0

## Estimated number of 750ml bottles from this batch
@export var bottles_estimated: int = 0

# ─── Aging ────────────────────────────────────────────────────────────────────
## Years since fermentation. Incremented by WineAgingProcessor each year.
@export var age_years: int = 0

## 0.0–1.0  how long this wine can age before declining.
## Computed at creation from acidity, complexity, quality, and method.
@export var aging_potential: float = 0.0

## Current maturity stage: "young" | "developing" | "peak" | "declining"
@export var maturity_stage: String = "young"

# ─── Helpers ──────────────────────────────────────────────────────────────────

## One-line summary for console logging.
func summary() -> String:
	var abv: float = 8.0 + alcohol_potential * 8.0
	return (
		"WineBatch #%d  %s  Year %d  Age %dy  Stage: %s  Method: %s\n" +
		"  Quality: %.2f  Alcohol: %.1f%%  Freshness: %.2f  Body: %.2f  Complexity: %.2f  Oak: %.2f\n" +
		"  Aging Potential: %.2f  Bottles: %d"
	) % [
		batch_id, wine_name, vintage_year, age_years, maturity_stage.capitalize(),
		fermentation_method, wine_quality, abv, freshness, body, complexity,
		oak_influence, aging_potential, bottles_estimated
	]


## Maturity stage display label.
func maturity_label() -> String:
	match maturity_stage:
		"young":      return "Young"
		"developing": return "Developing"
		"peak":       return "Peak"
		"declining":  return "Declining"
	return maturity_stage.capitalize()


## Quality tier label.
## Thresholds calibrated to the actual wine_quality output range (~0.25–0.55).
func quality_label() -> String:
	if wine_quality >= 0.60:
		return "Exceptional"
	elif wine_quality >= 0.45:
		return "Good"
	elif wine_quality >= 0.30:
		return "Average"
	else:
		return "Poor"


## Human-readable method name.
func method_label() -> String:
	match fermentation_method:
		"stainless_steel": return "Stainless Steel"
		"old_oak":         return "Old Oak"
		"new_oak":         return "New Oak"
	return fermentation_method.capitalize()
