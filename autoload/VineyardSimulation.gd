## VineyardSimulation.gd
## Singleton — simulation brain for all vineyard tiles.
##
## Owns all TileSimData instances, initializes terroir, runs ticks.
## Two tick types:
##   climate_tick  — weekly, driven by ClimateManager.climate_updated
##   season_tick   — per season, driven by tick_season() (future GameManager hook)
##
## Single-writer rule: only this autoload writes TileSimData.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
## Emitted after a tile's sim data changes (visual layer listens to this).
signal tile_data_changed(data: TileSimData)
## Emitted once after the full grid is initialized.
signal simulation_initialized()

# ─── State ────────────────────────────────────────────────────────────────────
## "col,row" → TileSimData
var _tile_data: Dictionary = {}

## Parsed soil archetypes from soils.json, keyed by soil id.
var _soil_archetypes: Dictionary = {}

## Sim config values.
var _cfg: Dictionary = {}

## Noise generator for spatial humidity/fertility variation.
var _noise: FastNoiseLite = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed       = randi()

	DataManager.data_loaded.connect(_on_data_loaded)
	# Connect to climate updates — this drives the weekly tile tick.
	ClimateManager.climate_updated.connect(_on_climate_updated)
	# Connect to year transition for vine aging.
	TimeManager.year_changed.connect(_on_year_changed)

	if DataManager.is_loaded("soils") and DataManager.is_loaded("vineyard_sim"):
		_build_archetypes()


# ─── Public API ───────────────────────────────────────────────────────────────

## Initialize simulation data for a grid of [param cols] × [param rows] tiles.
func initialize_grid(cols: int, rows: int) -> void:
	_tile_data.clear()

	if _soil_archetypes.is_empty():
		push_error("VineyardSimulation: archetypes empty — attempting late build.")
		_build_archetypes()
		if _soil_archetypes.is_empty():
			push_error("VineyardSimulation: late build failed. Check soils.json.")
	var noise_scale: float = float(_cfg.get("noise_scale", 0.18))
	_noise.frequency = noise_scale

	for row: int in rows:
		for col: int in cols:
			var data: TileSimData = _create_tile_data(col, row)
			_tile_data[_key(col, row)] = data

	_assign_starting_ownership(cols, rows)
	_seed_demo_vines(cols, rows)
	# Initialize lifecycle stage and productivity for all seeded tiles.
	_init_lifecycle_for_all()
	simulation_initialized.emit()
	print("VineyardSimulation: initialized %d tiles." % _tile_data.size())


## Returns the TileSimData for (col, row), or null if not found.
func get_tile_data(col: int, row: int) -> TileSimData:
	var key: String = _key(col, row)
	if _tile_data.has(key):
		var d: Variant = _tile_data[key]
		if d is TileSimData:
			return d
	return null


## Returns all TileSimData instances as an Array.
func get_all_tile_data() -> Array:
	return _tile_data.values()


## Public wrapper for quality recomputation — used by SimDemoSeeder.
func recompute_quality_public(data: TileSimData) -> void:
	if not data.is_planted:
		data.effective_quality = 0.0
		return
	var age_factor: float = clampf(float(data.vine_age) / 4.0 / 15.0, 0.0, 1.0)
	data.effective_quality = clampf(
		data.quality_potential * data.vine_health * (0.7 + age_factor * 0.3), 0.0, 1.0
	)


## Plant a grape variety on a tile. Returns false if already planted.
func plant_vine(col: int, row: int, grape_id: String) -> bool:
	var data: TileSimData = get_tile_data(col, row)
	if data == null or data.is_planted:
		return false
	data.is_planted    = true
	data.grape_variety = grape_id
	data.vine_age      = 0
	data.vine_health   = float(_cfg.get("starting_health", 0.85))
	recompute_quality_public(data)
	tile_data_changed.emit(data)
	return true


## Remove a vine from a tile.
func uproot_vine(col: int, row: int) -> void:
	var data: TileSimData = get_tile_data(col, row)
	if data == null or not data.is_planted:
		return
	data.is_planted    = false
	data.grape_variety = ""
	data.vine_age      = 0
	data.vine_health   = 0.0
	recompute_quality_public(data)
	tile_data_changed.emit(data)


## Returns the land purchase cost for a tile.
## Formula: base_cost + quality_potential × quality_range
## Range: €500 (low quality) – €1500 (high quality).
func calculate_land_cost(col: int, row: int) -> float:
	var data: TileSimData = get_tile_data(col, row)
	if data == null:
		return 0.0
	var land_cfg: Dictionary = _get_cfg_section("land")
	var base: float  = float(land_cfg.get("cost_base",  500.0))
	var range_: float = float(land_cfg.get("cost_range", 1000.0))
	return base + data.quality_potential * range_


## Purchase a locked tile. Returns true on success, false if already owned or not found.
## Caller (VineyardActionSystem) is responsible for charging money.
func buy_land(col: int, row: int) -> bool:
	var data: TileSimData = get_tile_data(col, row)
	if data == null or data.is_owned:
		return false
	data.is_owned = true
	tile_data_changed.emit(data)
	return true

# ─── Save / Load interface ────────────────────────────────────────────────────

## Serialize all tile sim data for saving.
func get_save_data() -> Dictionary:
	var tiles_arr: Array = []
	for key: String in _tile_data:
		var raw: Variant = _tile_data[key]
		if not raw is TileSimData:
			continue
		var d: TileSimData = raw
		tiles_arr.append({
			"grid_col":          d.grid_col,
			"grid_row":          d.grid_row,
			"soil_type":         d.soil_type,
			"humidity":          d.humidity,
			"fertility":         d.fertility,
			"drainage":          d.drainage,
			"disease_risk":      d.disease_risk,
			"quality_potential": d.quality_potential,
			"is_owned":          d.is_owned,
			"is_planted":        d.is_planted,
			"grape_variety":     d.grape_variety,
			"vine_age":          d.vine_age,
			"vine_health":       d.vine_health,
			"lifecycle_stage":   d.lifecycle_stage,
			"productivity":      d.productivity,
			"effective_quality": d.effective_quality,
			"ripeness":          d.ripeness,
			"sugar_level":       d.sugar_level,
			"acidity_level":     d.acidity_level,
			"harvest_ready":     d.harvest_ready,
			"harvested_this_year": d.harvested_this_year,
		})
	return { "tiles": tiles_arr }


## Restore tile sim data from a save. Re-links tiles to VineyardTile nodes.
func load_save_data(data: Dictionary) -> void:
	var raw: Variant = data.get("tiles", [])
	if not raw is Array:
		push_warning("VineyardSimulation.load_save_data: 'tiles' is not an Array.")
		return
	var arr: Array = raw
	var restored: int = 0
	for i: int in arr.size():
		if not arr[i] is Dictionary:
			continue
		var d: Dictionary = arr[i]
		var col: int = int(d.get("grid_col", -1))
		var row: int = int(d.get("grid_row", -1))
		if col < 0 or row < 0:
			continue
		var tile: TileSimData = get_tile_data(col, row)
		if tile == null:
			# Tile doesn't exist yet — grid may not be initialized.
			push_warning("VineyardSimulation.load_save_data: tile (%d,%d) not found." % [col, row])
			continue
		tile.soil_type         = str(d.get("soil_type",         tile.soil_type))
		tile.humidity          = float(d.get("humidity",          tile.humidity))
		tile.fertility         = float(d.get("fertility",         tile.fertility))
		tile.drainage          = float(d.get("drainage",          tile.drainage))
		tile.disease_risk      = float(d.get("disease_risk",      tile.disease_risk))
		tile.quality_potential = float(d.get("quality_potential", tile.quality_potential))
		tile.is_owned          = bool(d.get("is_owned",           true))
		tile.is_planted        = bool(d.get("is_planted",         false))
		tile.grape_variety     = str(d.get("grape_variety",       ""))
		tile.vine_age          = int(d.get("vine_age",            0))
		tile.vine_health       = float(d.get("vine_health",       0.0))
		tile.lifecycle_stage   = str(d.get("lifecycle_stage",     "empty"))
		tile.productivity      = float(d.get("productivity",      0.0))
		tile.effective_quality = float(d.get("effective_quality", 0.0))
		tile.ripeness          = float(d.get("ripeness",          0.0))
		tile.sugar_level       = float(d.get("sugar_level",       0.0))
		tile.acidity_level     = float(d.get("acidity_level",     0.0))
		tile.harvest_ready     = bool(d.get("harvest_ready",      false))
		tile.harvested_this_year = bool(d.get("harvested_this_year", false))
		tile_data_changed.emit(tile)
		restored += 1
	print("VineyardSimulation: restored %d tiles from save." % restored)

## Run one simulation tick (called each season by GameManager).
func tick_season() -> void:
	for key: String in _tile_data:
		var raw: Variant = _tile_data[key]
		if not raw is TileSimData:
			continue
		var data: TileSimData = raw
		if data.is_planted:
			_tick_vine(data)
			tile_data_changed.emit(data)


# ─── Private — climate tick ───────────────────────────────────────────────────

func _on_climate_updated(climate_state: Dictionary) -> void:
	if _tile_data.is_empty():
		return
	var effects_cfg:  Dictionary = _get_cfg_section("climate_effects")
	var ripeness_cfg: Dictionary = _get_cfg_section("ripeness")
	var season:       int        = TimeManager.current_season
	var stats: Dictionary = _run_climate_tick(climate_state, effects_cfg, ripeness_cfg, season)
	_log_tick_summary(stats)


func _run_climate_tick(climate_state: Dictionary, effects_cfg: Dictionary,
		ripeness_cfg: Dictionary, season: int) -> Dictionary:
	var changed:           int   = 0
	var sum_humidity:      float = 0.0
	var sum_health:        float = 0.0
	var sum_disease:       float = 0.0
	var sum_quality:       float = 0.0
	var sum_ripeness:      float = 0.0
	var sum_sugar:         float = 0.0
	var sum_acidity:       float = 0.0
	var ready_count:       int   = 0
	var mature_count:      int   = 0
	var ripened_count:     int   = 0
	var skipped_season:    int   = 0
	var skipped_spring:    int   = 0
	var min_humidity:      float = 1.0
	var max_humidity:      float = 0.0
	var min_health:        float = 1.0
	var max_health:        float = 0.0
	var planted:           int   = 0
	var total:             int   = 0

	for key: String in _tile_data:
		var raw: Variant = _tile_data[key]
		if not raw is TileSimData:
			continue
		var tile: TileSimData = raw
		total += 1

		var soil: Dictionary = _get_archetype(tile.soil_type)
		var climate_changed: bool = ClimateTileProcessor.apply(tile, climate_state, soil, effects_cfg)

		var ripe_result: Dictionary = GrapeRipenessProcessor.apply(tile, climate_state, ripeness_cfg, season)
		var ripeness_changed: bool  = bool(ripe_result.get("ripened", false)) and \
				absf(float(ripe_result.get("gain", 0.0))) > 0.001

		if bool(ripe_result.get("ripened", false)):
			ripened_count += 1
		elif bool(ripe_result.get("skipped_season", false)):
			skipped_season += 1
		elif bool(ripe_result.get("skipped_spring_reset", false)):
			skipped_spring += 1

		if climate_changed or ripeness_changed:
			changed += 1
			tile_data_changed.emit(tile)

		sum_humidity  += tile.humidity
		min_humidity   = minf(min_humidity, tile.humidity)
		max_humidity   = maxf(max_humidity, tile.humidity)
		sum_disease   += tile.disease_risk
		if tile.is_planted:
			planted    += 1
			sum_health += tile.vine_health
			min_health  = minf(min_health, tile.vine_health)
			max_health  = maxf(max_health, tile.vine_health)
			sum_quality  += tile.quality_potential
			sum_ripeness += tile.ripeness
			sum_sugar    += tile.sugar_level
			sum_acidity  += tile.acidity_level
			if tile.harvest_ready:
				ready_count += 1
			if tile.lifecycle_stage == "mature" or tile.lifecycle_stage == "old":
				mature_count += 1

	return {
		"total": total, "changed": changed, "planted": planted,
		"mature_count":   mature_count,   "ready_count":    ready_count,
		"ripened_count":  ripened_count,  "skipped_season": skipped_season,
		"skipped_spring": skipped_spring,
		"sum_humidity": sum_humidity, "min_humidity": min_humidity, "max_humidity": max_humidity,
		"sum_health":   sum_health,   "min_health":   min_health,   "max_health":   max_health,
		"sum_disease":  sum_disease,  "sum_quality":  sum_quality,
		"sum_ripeness": sum_ripeness, "sum_sugar":    sum_sugar,
		"sum_acidity":  sum_acidity,
	}


func _log_tick_summary(s: Dictionary) -> void:
	var total:   int = int(s.get("total",   0))
	var planted: int = int(s.get("planted", 0))
	if total == 0:
		return

	var avg_h: float = float(s["sum_humidity"]) / float(total)
	var avg_d: float = float(s["sum_disease"])  / float(total)
	var avg_v: float = float(s["sum_health"])   / float(planted) if planted > 0 else 0.0
	var avg_q: float = float(s["sum_quality"])  / float(planted) if planted > 0 else 0.0
	var mature: int  = int(s.get("mature_count", 0))
	var ready:  int  = int(s.get("ready_count",  0))

	print("Vineyard: health=%.2f  humidity=%.2f  disease=%.2f  quality=%.2f  mature=%d  ready=%d  (%d changed)" \
			% [avg_v, avg_h, avg_d, avg_q, mature, ready, int(s.get("changed", 0))])

	# Ripeness line — always print during Summer (1) and Autumn (2).
	var current_season: int = TimeManager.current_season
	if planted > 0 and (current_season == 1 or current_season == 2):
		var avg_r: float    = float(s.get("sum_ripeness", 0.0)) / float(planted)
		var avg_s: float    = float(s.get("sum_sugar",    0.0)) / float(planted)
		var avg_a: float    = float(s.get("sum_acidity",  0.0)) / float(planted)
		var ripened: int    = int(s.get("ripened_count",  0))
		var skipped_s: int  = int(s.get("skipped_season", 0))
		print("Ripeness:  avg=%.2f  sugar=%.2f  acidity=%.2f  ready=%d/%d mature  [ripened=%d skipped_season=%d]" \
				% [avg_r, avg_s, avg_a, ready, mature, ripened, skipped_s])


# ─── Private — year tick ──────────────────────────────────────────────────────

func _on_year_changed(_year: int) -> void:
	if _tile_data.is_empty():
		return
	var lc_cfg: Dictionary = _get_cfg_section("lifecycle")
	var climate_score: float = ClimateManager.weekly_climate_score
	var counts: Dictionary = { "young": 0, "mature": 0, "old": 0, "declining": 0 }

	for key: String in _tile_data:
		var raw: Variant = _tile_data[key]
		if not raw is TileSimData:
			continue
		var tile: TileSimData = raw
		if not tile.is_planted:
			tile.lifecycle_stage = VineLifecycle.STAGE_EMPTY
			tile.productivity    = 0.0
			continue
		# Age by one year (4 seasons) at year transition.
		tile.vine_age = mini(tile.vine_age + 4, int(_get_vine_cfg("max_age", 50)) * 4)
		tile.harvested_this_year = false   # reset harvest flag for new year
		VineLifecycle.tick_year(tile, lc_cfg, climate_score)
		recompute_quality_public(tile)
		tile_data_changed.emit(tile)
		var stage: String = tile.lifecycle_stage
		if counts.has(stage):
			counts[stage] = int(counts[stage]) + 1

	print("Year Transition: %d young, %d mature, %d old, %d declining vines" % [
		int(counts["young"]), int(counts["mature"]),
		int(counts["old"]),   int(counts["declining"])
	])


# ─── Private — initialization ─────────────────────────────────────────────────

func _on_data_loaded(key: String) -> void:
	if key == "soils" or key == "vineyard_sim":
		if DataManager.is_loaded("soils") and DataManager.is_loaded("vineyard_sim"):
			_build_archetypes()


func _build_archetypes() -> void:
	_cfg = DataManager.get_data("vineyard_sim")

	var soils_raw: Dictionary = DataManager.get_data("soils")
	var soils_arr: Variant    = soils_raw.get("soils", [])
	if not soils_arr is Array:
		push_error("VineyardSimulation: soils.json 'soils' key is not an Array.")
		return
	var soils: Array = soils_arr
	for i: int in soils.size():
		if not soils[i] is Dictionary:
			continue
		var s: Dictionary = soils[i]
		var sid: String   = str(s.get("id", ""))
		if sid != "":
			_soil_archetypes[sid] = s

	print("VineyardSimulation: archetypes built — soils=%s  cfg_keys=%s" \
			% [str(_soil_archetypes.keys()), str(_cfg.keys())])


func _create_tile_data(col: int, row: int) -> TileSimData:
	var data: TileSimData = TileSimData.new()
	data.grid_col = col
	data.grid_row = row

	# Assign soil type using noise-based spatial clustering.
	data.soil_type = _pick_soil_for(col, row)

	var archetype: Dictionary = _get_archetype(data.soil_type)

	# Base values from soil archetype + small per-tile noise variation.
	var hum_cfg: Dictionary  = _get_cfg_section("humidity")
	var fert_cfg: Dictionary = _get_cfg_section("fertility")

	var noise_val: float = (_noise.get_noise_2d(float(col), float(row)) + 1.0) * 0.5

	data.fertility = clampf(
		float(archetype.get("base_fertility", 0.60)) +
		noise_val * float(fert_cfg.get("variation_strength", 0.10)) - 0.05,
		0.10, 1.00
	)
	data.drainage = float(archetype.get("base_drainage", 0.60))
	data.humidity = clampf(
		float(archetype.get("base_humidity", 0.50)) +
		noise_val * float(hum_cfg.get("variation_strength", 0.12)) - 0.06,
		float(hum_cfg.get("base_min", 0.20)),
		float(hum_cfg.get("base_max", 0.85))
	)
	data.quality_potential = clampf(
		float(archetype.get("quality_modifier", 1.0)) *
		lerp(
			float(_get_vine_cfg("quality_base_min", 0.40)),
			float(_get_vine_cfg("quality_base_max", 1.00)),
			noise_val
		),
		0.10, 1.00
	)

	# Disease risk baseline from humidity.
	var dis_cfg: Dictionary = _get_cfg_section("disease_risk")
	data.disease_risk = clampf(
		float(dis_cfg.get("base", 0.05)) +
		data.humidity * float(dis_cfg.get("humidity_factor", 0.20)),
		0.0, 1.0
	)

	data.is_planted    = false
	data.grape_variety = ""
	data.vine_age      = 0
	data.vine_health   = 0.0
	recompute_quality_public(data)
	return data


## Picks a soil type for (col, row) using a second noise layer for clustering.
func _pick_soil_for(col: int, row: int) -> String:
	if _soil_archetypes.is_empty():
		return "limestone_clay"

	# Use a different noise offset to get independent soil clustering.
	var n: float = (_noise.get_noise_2d(float(col) + 100.0, float(row) + 100.0) + 1.0) * 0.5
	var ids: Array = _soil_archetypes.keys()
	var idx: int   = int(n * float(ids.size()))
	idx = clampi(idx, 0, ids.size() - 1)
	return str(ids[idx])


# ─── Private — per-season tick ───────────────────────────────────────────────

## Season tick: keeps lifecycle stage and productivity current.
## Year tick (on year_changed) handles aging and stage effects.
func _tick_vine(data: TileSimData) -> void:
	var lc_cfg: Dictionary = _get_cfg_section("lifecycle")
	data.lifecycle_stage = VineLifecycle.stage_for_age(data.vine_age, lc_cfg)
	data.productivity    = VineLifecycle.compute_productivity(data, lc_cfg,
			ClimateManager.weekly_climate_score)
	recompute_quality_public(data)


# ─── Private — demo seeding (prototype only) ─────────────────────────────────
## Plants a spread of vines across the grid so the inspector has interesting
## data to show immediately. Remove or replace with player actions later.
func _seed_demo_vines(cols: int, rows: int) -> void:
	SimDemoSeeder.seed_vines(self, cols, rows)


# ─── Private — starting ownership ────────────────────────────────────────────
## Marks the central region as owned and outer tiles as locked.
## The owned region is a rectangle inset by OWNERSHIP_BORDER tiles on each side.
## All demo-seeded vines are guaranteed to be in the owned region.
const OWNERSHIP_BORDER: int = 3   # tiles locked on each edge

func _assign_starting_ownership(cols: int, rows: int) -> void:
	var owned_count: int  = 0
	var locked_count: int = 0
	for key: String in _tile_data:
		var raw: Variant = _tile_data[key]
		if not raw is TileSimData:
			continue
		var tile: TileSimData = raw
		var in_owned_region: bool = (
			tile.grid_col >= OWNERSHIP_BORDER and
			tile.grid_col < cols - OWNERSHIP_BORDER and
			tile.grid_row >= OWNERSHIP_BORDER and
			tile.grid_row < rows - OWNERSHIP_BORDER
		)
		tile.is_owned = in_owned_region
		if in_owned_region:
			owned_count += 1
		else:
			locked_count += 1
	print("VineyardSimulation: ownership set — %d owned, %d locked." % [owned_count, locked_count])


## Sets lifecycle_stage and productivity on all tiles after seeding.
## Ensures the inspector shows correct data from frame 1.
func _init_lifecycle_for_all() -> void:
	var lc_cfg: Dictionary = _get_cfg_section("lifecycle")
	var climate_score: float = ClimateManager.weekly_climate_score
	for key: String in _tile_data:
		var raw: Variant = _tile_data[key]
		if not raw is TileSimData:
			continue
		var tile: TileSimData = raw
		if tile.is_planted:
			tile.lifecycle_stage = VineLifecycle.stage_for_age(tile.vine_age, lc_cfg)
			tile.productivity    = VineLifecycle.compute_productivity(
					tile, lc_cfg, climate_score)
		else:
			tile.lifecycle_stage = VineLifecycle.STAGE_EMPTY
			tile.productivity    = 0.0


# ─── Private — helpers ────────────────────────────────────────────────────────

func _key(col: int, row: int) -> String:
	return "%d,%d" % [col, row]


func _get_archetype(soil_id: String) -> Dictionary:
	if _soil_archetypes.has(soil_id):
		var a: Variant = _soil_archetypes[soil_id]
		if a is Dictionary:
			return a
	# Fallback to first archetype.
	if not _soil_archetypes.is_empty():
		var first: Variant = _soil_archetypes.values()[0]
		if first is Dictionary:
			return first
	return {}


func _get_cfg_section(section: String) -> Dictionary:
	var raw: Variant = _cfg.get(section, {})
	return raw if raw is Dictionary else {}


func _get_vine_cfg(key: String, default: float) -> float:
	var vine_cfg: Dictionary = _get_cfg_section("vine")
	return float(vine_cfg.get(key, default))
