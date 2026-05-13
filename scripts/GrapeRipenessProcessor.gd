## GrapeRipenessProcessor.gd
## Pure static class — weekly grape ripeness simulation.
##
## Responsibility:
##   Advances ripeness, sugar, and acidity each week for planted tiles.
##   Determines harvest_ready state.
##   Applies overripe quality penalty.
##
## Ripeness model:
##   - Only progresses during ripening seasons (summer=1, autumn=2 by default).
##   - Spring resets ripeness to 0 (new growing cycle).
##   - Rate = base_rate × temperature_modifier × climate_score × health_factor.
##   - Young vines ripen slower (young_vine_penalty multiplier).
##   - Sugar rises with ripeness + warm temperature.
##   - Acidity falls as ripeness rises (inverse — classic viticulture).
##   - harvest_ready = ripeness ≥ threshold AND stage is mature/old.
##   - Overripe (ripeness > overripe_threshold) degrades quality_potential.
##
## All constants from vineyard_sim_config.json "ripeness" section.
## No hardcoded values.

class_name GrapeRipenessProcessor
extends RefCounted


## Apply one week of ripeness simulation to [param tile].
## [param climate]  — Dictionary from ClimateManager.get_current_state().
## [param cfg]      — "ripeness" section of vineyard_sim_config.json.
## [param season]   — current season index (0=Spring 1=Summer 2=Autumn 3=Winter).
## Returns true if any ripeness value changed meaningfully.
static func apply(tile: TileSimData, climate: Dictionary,
		cfg: Dictionary, season: int) -> bool:

	if not tile.is_planted:
		_reset_ripeness(tile, cfg)
		return false

	var old_ripeness: float = tile.ripeness
	var old_sugar:    float = tile.sugar_level
	var old_acidity:  float = tile.acidity_level

	# Spring resets the ripeness cycle.
	var spring_reset: bool = bool(cfg.get("spring_reset", true))
	if season == 0 and spring_reset:
		_reset_ripeness(tile, cfg)
		tile.harvest_ready = false
		return old_ripeness > 0.001

	# Only ripen during configured seasons.
	var ripening_seasons: Array = cfg.get("ripening_seasons", [1, 2]) as Array
	if not ripening_seasons.has(season):
		# Winter: hold current ripeness, no change.
		return false

	# ── Compute weekly ripeness gain ──────────────────────────────────────
	var temp: float          = float(climate.get("temperature", 18.0))
	var climate_score: float = float(climate.get("weekly_climate_score", 0.8))

	var base_rate: float = float(cfg.get("base_rate_per_week", 0.06))

	# Temperature modifier — warm accelerates, cool slows.
	var temp_mod: float = 1.0
	var temp_bonus_above: float = float(cfg.get("temp_bonus_above", 18.0))
	var temp_penalty_below: float = float(cfg.get("temp_penalty_below", 12.0))
	if temp > temp_bonus_above:
		temp_mod += (temp - temp_bonus_above) * float(cfg.get("temp_bonus_rate", 0.008))
	elif temp < temp_penalty_below:
		temp_mod -= (temp_penalty_below - temp) * float(cfg.get("temp_penalty_rate", 0.006))
	temp_mod = clampf(temp_mod, 0.1, 2.0)

	# Climate score and health both influence ripening rate.
	var cs_weight: float = float(cfg.get("climate_score_weight", 0.4))
	var h_weight:  float = float(cfg.get("health_weight", 0.3))
	var rate_modifier: float = (
		(1.0 - cs_weight - h_weight) +
		climate_score * cs_weight +
		tile.vine_health * h_weight
	)

	# Young vines ripen slower.
	var stage_mult: float = 1.0
	if tile.lifecycle_stage == "young":
		stage_mult = float(cfg.get("young_vine_penalty", 0.5))

	var gain: float = base_rate * temp_mod * rate_modifier * stage_mult
	tile.ripeness = clampf(tile.ripeness + gain, 0.0, 1.0)

	# ── Sugar and acidity ─────────────────────────────────────────────────
	var sugar_base: float    = float(cfg.get("sugar_base", 0.20))
	var sugar_ripe: float    = float(cfg.get("sugar_ripeness_rate", 0.70))
	var sugar_temp: float    = float(cfg.get("sugar_temp_bonus", 0.003))
	tile.sugar_level = clampf(
		sugar_base + tile.ripeness * sugar_ripe + maxf(0.0, temp - 15.0) * sugar_temp,
		0.0, 1.0
	)

	var acid_base: float     = float(cfg.get("acidity_base", 0.85))
	var acid_ripe: float     = float(cfg.get("acidity_ripeness_loss", 0.55))
	var acid_temp: float     = float(cfg.get("acidity_temp_loss", 0.002))
	tile.acidity_level = clampf(
		acid_base - tile.ripeness * acid_ripe - maxf(0.0, temp - 15.0) * acid_temp,
		0.0, 1.0
	)

	# ── Harvest readiness ─────────────────────────────────────────────────
	var ready_threshold: float = float(cfg.get("harvest_ready_threshold", 0.75))
	var is_mature_enough: bool = (
		tile.lifecycle_stage == "mature" or
		tile.lifecycle_stage == "old"
	)
	tile.harvest_ready = tile.ripeness >= ready_threshold and is_mature_enough

	# ── Overripe quality penalty ──────────────────────────────────────────
	var overripe_threshold: float = float(cfg.get("overripe_threshold", 0.95))
	if tile.ripeness > overripe_threshold:
		var penalty: float = float(cfg.get("overripe_quality_loss", 0.004))
		tile.quality_potential = clampf(tile.quality_potential - penalty, 0.10, 1.0)

	return (
		absf(tile.ripeness     - old_ripeness) > 0.001 or
		absf(tile.sugar_level  - old_sugar)    > 0.001 or
		absf(tile.acidity_level - old_acidity) > 0.001
	)


static func _reset_ripeness(tile: TileSimData, cfg: Dictionary) -> void:
	tile.ripeness      = 0.0
	tile.sugar_level   = float(cfg.get("sugar_base",    0.20))
	tile.acidity_level = float(cfg.get("acidity_base",  0.85))
	tile.harvest_ready = false
