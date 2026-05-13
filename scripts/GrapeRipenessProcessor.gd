## GrapeRipenessProcessor.gd
## Pure static class — weekly grape ripeness simulation.
##
## Ripeness model:
##   - Only progresses during ripening seasons (summer=1, autumn=2 by default).
##   - Spring resets ripeness to 0 (new growing cycle).
##   - Rate = base_rate × temp_mod × rate_modifier × stage_mult.
##   - Young vines ripen slower (young_vine_penalty multiplier).
##   - Sugar rises with ripeness + warm temperature.
##   - Acidity falls as ripeness rises (inverse — classic viticulture).
##   - harvest_ready = ripeness ≥ threshold AND stage is mature/old.
##   - Overripe (ripeness > overripe_threshold) degrades quality_potential.
##
## BUG NOTE (fixed):
##   JSON arrays are parsed as Array[float]. Array.has(int) returns false
##   because GDScript 4 has() is type-strict. Season must be compared as
##   float, or the season check must avoid Array.has() entirely.

class_name GrapeRipenessProcessor
extends RefCounted


## Apply one week of ripeness simulation to [param tile].
## Returns a Dictionary of debug counters (skipped reasons, gain applied).
static func apply(tile: TileSimData, climate: Dictionary,
		cfg: Dictionary, season: int) -> Dictionary:

	var result: Dictionary = {
		"ripened":              false,
		"skipped_not_planted":  false,
		"skipped_season":       false,
		"skipped_spring_reset": false,
		"gain":                 0.0,
	}

	if not tile.is_planted:
		_reset_ripeness(tile, cfg)
		result["skipped_not_planted"] = true
		return result

	var old_ripeness: float = tile.ripeness

	# ── Spring reset ──────────────────────────────────────────────────────
	var spring_reset: bool = bool(cfg.get("spring_reset", true))
	if season == 0 and spring_reset:
		_reset_ripeness(tile, cfg)
		tile.harvest_ready = false
		result["skipped_spring_reset"] = true
		return result

	# ── Season gate — FIX: compare as int, not via Array.has() ───────────
	# JSON parses [1,2] as Array[float]. Array.has(int) is type-strict in
	# GDScript 4 and returns false even when the value matches numerically.
	# We check membership manually to avoid this.
	var raw_seasons: Variant = cfg.get("ripening_seasons", [1, 2])
	var in_ripening_season: bool = false
	if raw_seasons is Array:
		var seasons_arr: Array = raw_seasons
		for i: int in seasons_arr.size():
			if int(seasons_arr[i]) == season:
				in_ripening_season = true
				break
	else:
		# Fallback: default to summer+autumn.
		in_ripening_season = (season == 1 or season == 2)

	if not in_ripening_season:
		result["skipped_season"] = true
		return result

	# ── Compute weekly ripeness gain ──────────────────────────────────────
	var temp: float          = float(climate.get("temperature",        18.0))
	var climate_score: float = float(climate.get("weekly_climate_score", 0.8))
	var base_rate: float     = float(cfg.get("base_rate_per_week",      0.10))

	# Temperature modifier.
	var temp_mod: float         = 1.0
	var bonus_above: float      = float(cfg.get("temp_bonus_above",   18.0))
	var penalty_below: float    = float(cfg.get("temp_penalty_below", 10.0))
	if temp > bonus_above:
		temp_mod += (temp - bonus_above) * float(cfg.get("temp_bonus_rate", 0.010))
	elif temp < penalty_below:
		temp_mod -= (penalty_below - temp) * float(cfg.get("temp_penalty_rate", 0.004))
	temp_mod = clampf(temp_mod, 0.1, 2.0)

	# Rate modifier from climate score and vine health.
	var cs_w: float = float(cfg.get("climate_score_weight", 0.35))
	var h_w:  float = float(cfg.get("health_weight",        0.15))
	var rate_modifier: float = (
		(1.0 - cs_w - h_w) +
		climate_score * cs_w +
		tile.vine_health * h_w
	)

	# Young vines ripen slower.
	var stage_mult: float = 1.0
	if tile.lifecycle_stage == "young":
		stage_mult = float(cfg.get("young_vine_penalty", 0.5))

	var gain: float = base_rate * temp_mod * rate_modifier * stage_mult
	tile.ripeness   = clampf(tile.ripeness + gain, 0.0, 1.0)

	# ── Sugar and acidity ─────────────────────────────────────────────────
	var sugar_base: float = float(cfg.get("sugar_base",          0.20))
	var sugar_ripe: float = float(cfg.get("sugar_ripeness_rate", 0.70))
	var sugar_temp: float = float(cfg.get("sugar_temp_bonus",    0.003))
	tile.sugar_level = clampf(
		sugar_base + tile.ripeness * sugar_ripe + maxf(0.0, temp - 15.0) * sugar_temp,
		0.0, 1.0
	)

	var acid_base: float = float(cfg.get("acidity_base",          0.85))
	var acid_ripe: float = float(cfg.get("acidity_ripeness_loss", 0.55))
	var acid_temp: float = float(cfg.get("acidity_temp_loss",     0.002))
	tile.acidity_level = clampf(
		acid_base - tile.ripeness * acid_ripe - maxf(0.0, temp - 15.0) * acid_temp,
		0.0, 1.0
	)

	# ── Harvest readiness ─────────────────────────────────────────────────
	var ready_threshold: float = float(cfg.get("harvest_ready_threshold", 0.75))
	var is_mature_enough: bool = (
		tile.lifecycle_stage == "mature" or tile.lifecycle_stage == "old"
	)
	tile.harvest_ready = tile.ripeness >= ready_threshold and is_mature_enough

	# ── Overripe quality penalty ──────────────────────────────────────────
	var overripe_threshold: float = float(cfg.get("overripe_threshold", 0.95))
	if tile.ripeness > overripe_threshold:
		var penalty: float = float(cfg.get("overripe_quality_loss", 0.004))
		tile.quality_potential = clampf(tile.quality_potential - penalty, 0.10, 1.0)

	result["ripened"] = true
	result["gain"]    = gain
	return result


static func _reset_ripeness(tile: TileSimData, cfg: Dictionary) -> void:
	tile.ripeness      = 0.0
	tile.sugar_level   = float(cfg.get("sugar_base",    0.20))
	tile.acidity_level = float(cfg.get("acidity_base",  0.85))
	tile.harvest_ready = false
