## VineLifecycle.gd
## Pure static class — vine lifecycle stage logic and yearly aging.
##
## Responsibility:
##   - Determines lifecycle stage from vine_age and config thresholds.
##   - Applies yearly aging effects (quality cap, declining penalties).
##   - Computes productivity from stage, health, disease, climate score.
##
## Stages:
##   empty     — no vine planted
##   young     — 0 to young_max_years: lower quality cap, lower resistance
##   mature    — young_max_years to mature_max_years: peak balance
##   old       — mature_max_years to old_max_years: quality bonus, lower yield
##   declining — beyond old_max_years: disease pressure, health loss
##
## Called by VineyardSimulation.tick_year() once per year per planted tile.
## No Node, no signals, no scene tree dependency.

class_name VineLifecycle
extends RefCounted

# Stage ID constants — used as strings in TileSimData.lifecycle_stage.
const STAGE_EMPTY:     String = "empty"
const STAGE_YOUNG:     String = "young"
const STAGE_MATURE:    String = "mature"
const STAGE_OLD:       String = "old"
const STAGE_DECLINING: String = "declining"


## Run the full yearly lifecycle update on one tile.
## [param tile] — TileSimData to mutate.
## [param cfg]  — "lifecycle" section of vineyard_sim_config.json.
## [param climate_score] — 0–1 from ClimateManager.weekly_climate_score.
static func tick_year(tile: TileSimData, cfg: Dictionary,
		climate_score: float) -> void:

	if not tile.is_planted:
		tile.lifecycle_stage = STAGE_EMPTY
		tile.productivity    = 0.0
		return

	# 1. Determine stage from age.
	tile.lifecycle_stage = _stage_for(tile.vine_age, cfg)

	# 2. Apply stage-specific yearly effects.
	_apply_stage_effects(tile, cfg)

	# 3. Compute productivity.
	tile.productivity = _compute_productivity(tile, cfg, climate_score)


## Returns the lifecycle stage string for a given vine_age (in seasons).
static func stage_for_age(vine_age: int, cfg: Dictionary) -> String:
	return _stage_for(vine_age, cfg)


## Compute productivity without applying yearly effects — used for mid-year reads.
static func compute_productivity(tile: TileSimData, cfg: Dictionary,
		climate_score: float) -> float:
	return _compute_productivity(tile, cfg, climate_score)


# ─── Private ──────────────────────────────────────────────────────────────────

static func _stage_for(vine_age: int, cfg: Dictionary) -> String:
	var years: int = vine_age / 4
	var young_max:  int = int(cfg.get("young_max_years",  3))
	var mature_max: int = int(cfg.get("mature_max_years", 25))
	var old_max:    int = int(cfg.get("old_max_years",    50))

	if years < young_max:
		return STAGE_YOUNG
	elif years < mature_max:
		return STAGE_MATURE
	elif years < old_max:
		return STAGE_OLD
	else:
		return STAGE_DECLINING


static func _apply_stage_effects(tile: TileSimData, cfg: Dictionary) -> void:
	match tile.lifecycle_stage:
		STAGE_YOUNG:
			# Young vines have a quality ceiling — cap quality_potential.
			var cap: float = float(cfg.get("young_quality_cap", 0.65))
			tile.quality_potential = minf(tile.quality_potential, cap)

		STAGE_OLD:
			# Old vines gain a small quality bonus each year (concentration).
			var bonus: float = float(cfg.get("old_quality_bonus", 0.12)) / 25.0
			tile.quality_potential = clampf(tile.quality_potential + bonus, 0.10, 1.0)

		STAGE_DECLINING:
			# Declining vines accumulate disease and lose health each year.
			var dis_gain:    float = float(cfg.get("declining_disease_gain", 0.03))
			var health_loss: float = float(cfg.get("declining_health_loss",  0.02))
			tile.disease_risk = clampf(tile.disease_risk + dis_gain, 0.0, 1.0)
			tile.vine_health  = clampf(tile.vine_health  - health_loss, 0.0, 1.0)


static func _compute_productivity(tile: TileSimData, cfg: Dictionary,
		climate_score: float) -> float:

	var prod_cfg: Dictionary = _section(cfg, "productivity")

	# Base productivity from lifecycle stage.
	var base: float
	match tile.lifecycle_stage:
		STAGE_YOUNG:     base = float(prod_cfg.get("young_base",    0.40))
		STAGE_MATURE:    base = float(prod_cfg.get("mature_base",   0.85))
		STAGE_OLD:       base = float(prod_cfg.get("old_base",      0.65))
		STAGE_DECLINING: base = float(prod_cfg.get("declining_base",0.30))
		_:               return 0.0

	# Weighted modifiers from health, disease, and climate.
	var hw: float = float(prod_cfg.get("health_weight",  0.50))
	var dw: float = float(prod_cfg.get("disease_weight", 0.25))
	var cw: float = float(prod_cfg.get("climate_weight", 0.25))

	var health_factor:  float = tile.vine_health
	var disease_factor: float = 1.0 - tile.disease_risk
	var climate_factor: float = clampf(climate_score, 0.0, 1.0)

	var modifier: float = (
		health_factor  * hw +
		disease_factor * dw +
		climate_factor * cw
	)

	return clampf(base * modifier, 0.0, 1.0)


static func _section(cfg: Dictionary, key: String) -> Dictionary:
	var raw: Variant = cfg.get(key, {})
	return raw if raw is Dictionary else {}
