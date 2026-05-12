## ClimateTileProcessor.gd
## Pure static class — applies weekly climate effects to one TileSimData.
##
## Responsibility:
##   Contains all the math for how climate affects a tile each week.
##   Called by VineyardSimulation once per tile per climate tick.
##
## Architecture note:
##   No Node, no signals, no scene tree dependency.
##   All tuning constants come from the cfg Dictionary (vineyard_sim_config.json
##   "climate_effects" section) — nothing is hardcoded here.
##   This makes the processor easy to unit-test and safe to call in a loop
##   over thousands of tiles without overhead.
##
##   Mutation order each week:
##     1. Tile humidity  (rainfall, temperature, wind, soil drainage)
##     2. Disease risk   (humidity level, condition, wind, drainage, planted state)
##     3. Vine health    (drought, flood, frost, heat — planted tiles only)
##     4. Quality potential (water stress benefit, excess humidity, health — planted only)
##   effective_quality is recomputed last from the updated values.

class_name ClimateTileProcessor
extends RefCounted


## Apply one week of climate effects to [param tile].
## [param climate] — Dictionary from ClimateManager.get_current_state().
## [param soil]    — Dictionary from soils.json for this tile's soil_type.
## [param cfg]     — "climate_effects" section of vineyard_sim_config.json.
## Mutates tile in-place. Returns true if any value changed meaningfully.
static func apply(tile: TileSimData, climate: Dictionary,
		soil: Dictionary, cfg: Dictionary) -> bool:

	var h_cfg: Dictionary = _section(cfg, "humidity")
	var d_cfg: Dictionary = _section(cfg, "disease")
	var v_cfg: Dictionary = _section(cfg, "vine_health")
	var q_cfg: Dictionary = _section(cfg, "quality")

	var old_humidity:  float = tile.humidity
	var old_disease:   float = tile.disease_risk
	var old_health:    float = tile.vine_health
	var old_quality:   float = tile.quality_potential

	_apply_humidity(tile, climate, soil, h_cfg)
	_apply_disease(tile, climate, soil, d_cfg)

	if tile.is_planted:
		_apply_vine_health(tile, climate, v_cfg)
		_apply_quality_potential(tile, q_cfg)
		_recompute_effective_quality(tile)

	# Return true if any field changed by more than a tiny epsilon.
	return (
		absf(tile.humidity         - old_humidity) > 0.001 or
		absf(tile.disease_risk     - old_disease)  > 0.001 or
		absf(tile.vine_health      - old_health)   > 0.001 or
		absf(tile.quality_potential - old_quality) > 0.001
	)


# ─── Step 1 — Tile humidity ───────────────────────────────────────────────────

static func _apply_humidity(tile: TileSimData, climate: Dictionary,
		soil: Dictionary, cfg: Dictionary) -> void:

	var rainfall:    float = float(climate.get("rainfall",    40.0))
	var temperature: float = float(climate.get("temperature", 15.0))
	var wind:        float = float(climate.get("wind",        10.0))

	# Soil properties moderate how much rainfall actually reaches the tile.
	var drainage:   float = float(soil.get("base_drainage",      tile.drainage))
	var retention:  float = float(soil.get("water_retention",    1.0 - tile.drainage))

	# Rainfall adds humidity, moderated by drainage (well-drained soils gain less).
	var rain_gain: float = rainfall * float(cfg.get("rainfall_gain_rate", 0.008))
	rain_gain *= lerp(
		float(cfg.get("retention_modifier", 0.4)),
		1.0,
		retention
	)

	# High temperature and wind dry the tile out.
	var temp_loss: float = maxf(0.0, temperature - 15.0) * float(cfg.get("temp_dry_rate", 0.003))
	var wind_loss: float = wind * float(cfg.get("wind_dry_rate", 0.002))

	# Good drainage accelerates moisture loss.
	var drain_loss: float = drainage * float(cfg.get("drainage_modifier", 0.6)) * 0.01

	tile.humidity = clampf(
		tile.humidity + rain_gain - temp_loss - wind_loss - drain_loss,
		0.0, 1.0
	)


# ─── Step 2 — Disease risk ────────────────────────────────────────────────────

static func _apply_disease(tile: TileSimData, climate: Dictionary,
		soil: Dictionary, cfg: Dictionary) -> void:

	var humidity:   float  = tile.humidity
	var wind:       float  = float(climate.get("wind",      10.0))
	var condition:  String = str(climate.get("condition",   "Clear"))
	var drainage:   float  = float(soil.get("base_drainage", tile.drainage))

	var delta: float = 0.0

	# Wet, stagnant conditions increase disease pressure.
	if humidity >= float(cfg.get("high_humidity_threshold", 0.70)):
		delta += float(cfg.get("high_humidity_gain", 0.04))

	if condition == "Rainy":
		delta += float(cfg.get("rainy_condition_gain", 0.03))

	if wind < float(cfg.get("low_wind_threshold", 8.0)):
		delta += float(cfg.get("low_wind_gain", 0.02))

	# Dry and windy conditions reduce disease pressure.
	if condition == "Dry":
		delta -= float(cfg.get("dry_condition_loss", 0.03))

	if wind >= float(cfg.get("high_wind_threshold", 20.0)):
		delta -= float(cfg.get("high_wind_loss", 0.02))

	# Good drainage reduces standing moisture and disease.
	if drainage >= 0.70:
		delta -= float(cfg.get("good_drainage_loss", 0.01))

	# Unplanted tiles recover toward baseline faster.
	if not tile.is_planted:
		delta -= float(cfg.get("unplanted_recovery_rate", 0.02))

	tile.disease_risk = clampf(tile.disease_risk + delta, 0.0, 1.0)


# ─── Step 3 — Vine health (planted tiles only) ───────────────────────────────

static func _apply_vine_health(tile: TileSimData, climate: Dictionary,
		cfg: Dictionary) -> void:

	var humidity:   float = tile.humidity
	var frost_risk: float = float(climate.get("frost_risk",   0.0))
	var temp:       float = float(climate.get("temperature",  15.0))

	var delta: float = 0.0

	# Drought stress — too dry damages vines.
	if humidity < float(cfg.get("drought_threshold", 0.25)):
		delta -= float(cfg.get("drought_damage", 0.04))

	# Waterlogging — too wet also damages vines (root rot pressure).
	elif humidity > float(cfg.get("flood_threshold", 0.80)):
		delta -= float(cfg.get("flood_damage", 0.02))

	# Balanced humidity allows slight recovery.
	elif humidity >= float(cfg.get("balanced_min", 0.35)) and \
		 humidity <= float(cfg.get("balanced_max", 0.65)):
		delta += float(cfg.get("balanced_recovery", 0.01))

	# Frost damages vines proportionally to frost_risk.
	if frost_risk > 0.0:
		delta -= frost_risk * float(cfg.get("frost_damage", 0.06))

	# Heatwave stress.
	if temp >= 32.0:
		delta -= float(cfg.get("heat_damage", 0.03))

	tile.vine_health = clampf(tile.vine_health + delta, 0.0, 1.0)


# ─── Step 4 — Quality potential (planted tiles only) ─────────────────────────

static func _apply_quality_potential(tile: TileSimData, cfg: Dictionary) -> void:
	var humidity: float = tile.humidity
	var delta:    float = 0.0

	# Mild water stress (slightly dry) concentrates flavour — classic viticulture.
	if humidity >= float(cfg.get("stress_benefit_min", 0.28)) and \
	   humidity <= float(cfg.get("stress_benefit_max", 0.38)):
		delta += float(cfg.get("stress_gain", 0.005))

	# Excess humidity dilutes quality potential.
	if humidity > float(cfg.get("excess_humidity_threshold", 0.75)):
		delta -= float(cfg.get("excess_humidity_loss", 0.004))

	# Poor vine health degrades quality ceiling over time.
	if tile.vine_health < float(cfg.get("low_health_threshold", 0.40)):
		delta -= float(cfg.get("low_health_loss", 0.006))

	tile.quality_potential = clampf(tile.quality_potential + delta, 0.10, 1.0)


# ─── Effective quality recompute ─────────────────────────────────────────────

static func _recompute_effective_quality(tile: TileSimData) -> void:
	if not tile.is_planted:
		tile.effective_quality = 0.0
		return
	var age_years:  float = float(tile.vine_age) / 4.0
	var age_factor: float = clampf(age_years / 15.0, 0.0, 1.0)
	tile.effective_quality = clampf(
		tile.quality_potential * tile.vine_health * (0.7 + age_factor * 0.3),
		0.0, 1.0
	)


# ─── Helper ───────────────────────────────────────────────────────────────────

static func _section(cfg: Dictionary, key: String) -> Dictionary:
	var raw: Variant = cfg.get(key, {})
	return raw if raw is Dictionary else {}
